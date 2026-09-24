import type { FastifyInstance, FastifyRequest } from 'fastify';
import { parsePracticeUserId } from './practice-repository.js';
import { PracticeIdentityError, parsePracticeBearerToken, parsePracticeIdentity } from './practice-identity.js';
import type { PracticeAccountRepository, PracticeIdentity, PracticeIdentityVerifier } from './practice-identity.js';

export const PRACTICE_SESSION_ROUTE = '/v1/practice/session';
export interface PracticeSessionAdapters {
  readonly verifier: PracticeIdentityVerifier;
  readonly accounts: PracticeAccountRepository;
}

export class PracticeAuthenticationUnavailable extends Error {
  constructor() { super('Practice authentication is unavailable.'); }
}

export function requestPracticeBearerToken(request: FastifyRequest): string | null {
  let count = 0;
  for (let index = 0; index < request.raw.rawHeaders.length; index += 2) {
    if (request.raw.rawHeaders[index]?.toLowerCase() === 'authorization') count++;
  }
  // Node can discard duplicate Authorization fields when building headers.
  // Inspect the original field list before trusting its normalized value.
  if (count !== 1) return null;
  return parsePracticeBearerToken(request.headers.authorization);
}

export function practiceAccountsEnabled(adapters?: PracticeSessionAdapters): adapters is PracticeSessionAdapters {
  return typeof adapters?.verifier?.verify === 'function' &&
    typeof adapters.accounts?.find === 'function' && typeof adapters.accounts?.provision === 'function';
}

export interface ExistingPracticeAccountAuthentication {
  readonly userId: string;
  readonly identity: PracticeIdentity;
}

/** Verifies the bearer token and looks up its existing account without creating
 * one. The UUID and Privy identity come from one verifier + mapping operation. */
export function createPracticeAccountContextAuthenticator(adapters: PracticeSessionAdapters) {
  return async (request: FastifyRequest): Promise<ExistingPracticeAccountAuthentication | null> => {
    const token = requestPracticeBearerToken(request);
    if (!token) return null;
    try {
      const verified = await adapters.verifier.verify(token);
      if (!verified) return null;
      const identity = parsePracticeIdentity(verified);
      const account = await adapters.accounts.find(identity);
      return account ? Object.freeze({userId: parsePracticeUserId(account.userId), identity}) : null;
    } catch {
      throw new PracticeAuthenticationUnavailable();
    }
  };
}

/** Progress reads look up existing accounts. Provisioning requires explicit POST. */
export function createPracticeAuthenticator(adapters: PracticeSessionAdapters) {
  const authenticateContext = createPracticeAccountContextAuthenticator(adapters);
  return async (request: FastifyRequest): Promise<{userId: string} | null> => {
    const authenticated = await authenticateContext(request);
    return authenticated ? {userId: authenticated.userId} : null;
  };
}

export function registerPracticeSessionRoute(app: FastifyInstance, options?: PracticeSessionAdapters): void {
  const adapters = practiceAccountsEnabled(options) ? options : undefined;
  const identities = new WeakMap<FastifyRequest, PracticeIdentity>();
  const problem = (request: FastifyRequest, code: string, message: string) => ({error: {code, message, requestId: request.id}});
  app.post(PRACTICE_SESSION_ROUTE, {
    bodyLimit: 1024,
    schema: {
      querystring: {type: 'object', additionalProperties: false, properties: {}},
      body: {type: 'object', additionalProperties: false, properties: {}},
    },
    onRequest: async (request, reply) => {
      if (!adapters) return reply.code(503).send(problem(request, 'PRACTICE_SYNC_UNAVAILABLE', 'Practice accounts are unavailable.'));
      const token = requestPracticeBearerToken(request);
      if (!token) return reply.code(401).send(problem(request, 'PRACTICE_UNAUTHENTICATED', 'A verified account is required.'));
      try {
        const identity = await adapters.verifier.verify(token);
        if (!identity) return reply.code(401).send(problem(request, 'PRACTICE_UNAUTHENTICATED', 'A verified account is required.'));
        identities.set(request, identity);
      } catch {
        return reply.code(503).send(problem(request, 'PRACTICE_SYNC_UNAVAILABLE', 'Practice authentication is unavailable.'));
      }
    },
  }, async (request, reply) => {
    const identity = identities.get(request);
    if (!adapters || !identity) return reply.code(401).send(problem(request, 'PRACTICE_UNAUTHENTICATED', 'A verified account is required.'));
    try {
      const {userId} = await adapters.accounts.provision(identity);
      return {schemaVersion: 1, userId: parsePracticeUserId(userId)};
    } catch (error) {
      if (error instanceof PracticeIdentityError && error.code === 'PRACTICE_ACCOUNT_UNAVAILABLE') {
        return reply.code(403).send(problem(request, 'PRACTICE_ACCOUNT_UNAVAILABLE', 'This practice account is unavailable.'));
      }
      request.log.error({errorCode: 'PRACTICE_ACCOUNT_PROVISION_FAILED'}, 'practice account request failed');
      return reply.code(503).send(problem(request, 'PRACTICE_SYNC_UNAVAILABLE', 'Practice accounts are unavailable.'));
    }
  });
}
