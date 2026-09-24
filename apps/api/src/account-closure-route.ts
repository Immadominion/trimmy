import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import {parsePracticeIdentity} from './practice-identity.js';
import type {PracticeIdentity} from './practice-identity.js';
import { PracticeAuthenticationUnavailable } from './practice-session-routes.js';
import type {ExistingPracticeAccountAuthentication} from './practice-session-routes.js';
import type {PrivyLinkedIdentityResolution} from './privy-linked-identities.js';
import { AccountClosureError } from './account-closure.js';
import type { AccountClosureRepository } from './account-closure.js';

export const ACCOUNT_CLOSURE_ROUTE = '/v1/account/closure';
const noQuery = {type: 'object', additionalProperties: false, properties: {}} as const;

/** Typed out in full so a stray or replayed request cannot close an account. */
export const ACCOUNT_CLOSURE_CONFIRMATION = 'close my account';

export interface AccountClosureAdapters {
  readonly repository: AccountClosureRepository;
  readonly authenticate: (request: FastifyRequest) => Promise<{readonly userId: string} | null>;
  readonly authenticateContext?: (request: FastifyRequest) =>
    Promise<ExistingPracticeAccountAuthentication | null>;
  readonly linkedIdentities?: Readonly<{
    resolveFresh(identity: PracticeIdentity): Promise<PrivyLinkedIdentityResolution>;
  }>;
}

export function accountClosureEnabled(adapters: AccountClosureAdapters | undefined): adapters is AccountClosureAdapters {
  return typeof adapters?.authenticate === 'function' && typeof adapters.repository?.close === 'function';
}

function problem(reply: FastifyReply, request: FastifyRequest, status: number, code: string, message: string) {
  return reply.code(status).send({error: {code, message, requestId: request.id}});
}

function ownData(value: Record<string, unknown>, key: string): unknown {
  const descriptor = Object.getOwnPropertyDescriptor(value, key);
  return descriptor?.enumerable && Object.hasOwn(descriptor, 'value') ? descriptor.value : undefined;
}

function plainObject(value: unknown): Record<string, unknown> | null {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return null;
  const prototype: unknown = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null ? value as Record<string, unknown> : null;
}

/** Optional closure evidence. Any missing, ambiguous, malformed or failed read
 * becomes null because provider availability must never prevent closure. */
function projectOptionalXSubject(value: unknown, identity: PracticeIdentity): string | null {
  const resolution = plainObject(value);
  const twitter = resolution && plainObject(ownData(resolution, 'twitter'));
  if (!resolution || ownData(resolution, 'provider') !== 'privy' ||
      ownData(resolution, 'subject') !== identity.subject || !twitter ||
      ownData(twitter, 'status') !== 'verified') return null;
  const subject = ownData(twitter, 'subject');
  try {
    return typeof subject === 'string' && /^[1-9][0-9]{0,19}$/.exec(subject)?.[0] === subject &&
      BigInt(subject) <= 18_446_744_073_709_551_615n ? subject : null;
  } catch { return null; }
}

/**
 * Closes the requesting account. It is irreversible through this API: once
 * closed, the account cannot authenticate again, so there is no reopen route.
 *
   * Closure locks the account and cancels its open invitations. It
 * does not erase saved history, which this schema keeps as immutable records.
 */
export function registerAccountClosureRoute(app: FastifyInstance, options?: AccountClosureAdapters): void {
  const adapters = accountClosureEnabled(options) ? options : undefined;

  app.post(ACCOUNT_CLOSURE_ROUTE, {
    bodyLimit: 1024,
    schema: {
      querystring: noQuery,
      body: {
        type: 'object', additionalProperties: false, required: ['schemaVersion', 'confirm'],
        properties: {schemaVersion: {const: 1}, confirm: {type: 'string', maxLength: 64}},
      },
    },
  }, async (request, reply) => {
    if (!adapters) {
      return problem(reply, request, 503, 'ACCOUNT_CLOSURE_UNAVAILABLE', 'Account closure is unavailable.');
    }
    try {
      // Identity before anything is read from the body or reaches storage. The
      // request schema still runs first, because the framework validates before
      // the handler, so a malformed body is refused with 400 even unauthenticated.
      // That discloses only the route's published shape and touches no storage.
      const context = adapters.authenticateContext
        ? await adapters.authenticateContext(request)
        : null;
      const verified = adapters.authenticateContext ? context : await adapters.authenticate(request);
      if (!verified) {
        return problem(reply, request, 401, 'ACCOUNT_CLOSURE_UNAUTHENTICATED', 'A verified account is required.');
      }
      const body = request.body as {confirm?: unknown};
      if (body?.confirm !== ACCOUNT_CLOSURE_CONFIRMATION) {
        return problem(reply, request, 400, 'ACCOUNT_CLOSURE_INVALID_INPUT',
          'Closing an account requires its exact written confirmation.');
      }
      let freshXSubject: string | null = null;
      if (context && typeof adapters.linkedIdentities?.resolveFresh === 'function') {
        try {
          const identity = parsePracticeIdentity(context.identity);
          freshXSubject = projectOptionalXSubject(
            await adapters.linkedIdentities.resolveFresh(identity), identity,
          );
        } catch { freshXSubject = null; }
      }
      const result = await adapters.repository.close(verified.userId, freshXSubject);
      return {
        schemaVersion: 1,
        closed: result.closed,
        canceledInvitations: result.canceledInvitations,
        // Said plainly, because it is the part people most need to know.
        note: 'This account can no longer sign in. Saved practice history is kept and is no longer reachable.',
      };
    } catch (error) {
      if (error instanceof PracticeAuthenticationUnavailable) {
        return problem(reply, request, 503, 'ACCOUNT_CLOSURE_UNAVAILABLE', 'Account closure is unavailable.');
      }
      if (error instanceof AccountClosureError) {
        switch (error.code) {
          case 'ACCOUNT_CLOSURE_INVALID_INPUT':
            return problem(reply, request, 400, error.code, 'Account closure request is invalid.');
          case 'ACCOUNT_CLOSURE_NOT_FOUND':
            return problem(reply, request, 404, error.code, 'That account is unavailable.');
          default:
            return problem(reply, request, 503, 'ACCOUNT_CLOSURE_UNAVAILABLE', 'Account closure is unavailable.');
        }
      }
      request.log.error({errorCode: 'ACCOUNT_CLOSURE_FAILED'}, 'account closure failed');
      return problem(reply, request, 503, 'ACCOUNT_CLOSURE_UNAVAILABLE', 'Account closure is unavailable.');
    }
  });
}
