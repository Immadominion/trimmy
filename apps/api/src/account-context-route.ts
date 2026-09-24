import {address, getAddressEncoder, isOffCurveAddress} from '@solana/kit';
import type {FastifyInstance, FastifyReply, FastifyRequest} from 'fastify';
import {parsePracticeIdentity} from './practice-identity.js';
import type {PracticeIdentity} from './practice-identity.js';
import {parsePracticeUserId} from './practice-repository.js';
import {PracticeAuthenticationUnavailable} from './practice-session-routes.js';
import type {ExistingPracticeAccountAuthentication} from './practice-session-routes.js';
import {
  PrivyLinkedIdentityError,
  readPrivyLinkedIdentityResolver,
} from './privy-linked-identities.js';
import type {
  PrivyEmbeddedSolanaWallet,
  PrivyLinkedIdentityErrorCode,
  PrivyLinkedIdentityResolution,
  PrivyLinkedIdentityResolver,
  PrivyLinkedIdentityResolverOptions,
  PrivyTwitterIdentity,
} from './privy-linked-identities.js';

export const ACCOUNT_CONTEXT_ROUTE = '/v1/account/context';

export interface AccountContextIdentityResolver {
  resolve(identity: PracticeIdentity): Promise<PrivyLinkedIdentityResolution>;
  /** Optional for older read-only adapters; a requested fresh read must never
   * silently fall back to their cached resolve method. */
  resolveFresh?(identity: PracticeIdentity): Promise<PrivyLinkedIdentityResolution>;
}

export interface AccountContextAdapters {
  /** Verifier plus existing-account lookup only; this must never provision. */
  readonly authenticate: (request: FastifyRequest) =>
    Promise<ExistingPracticeAccountAuthentication | null>;
  readonly linkedIdentities: AccountContextIdentityResolver;
}

export function accountContextEnabled(value?: AccountContextAdapters): value is AccountContextAdapters {
  return typeof value?.authenticate === 'function' &&
    typeof value.linkedIdentities?.resolve === 'function';
}

/** Account context is optional. Missing either server-only credential keeps it
 * disabled; fully supplied malformed credentials still fail closed. */
export function readAccountContextResolver(
  env: Readonly<Record<string, string | undefined>>,
  overrides: Readonly<Pick<PrivyLinkedIdentityResolverOptions,
    'timeoutMs' | 'fetch' | 'clientFactory' | 'cacheTtlMs' | 'rateLimitWindowMs' |
    'perSubjectLimit' | 'globalLimit' | 'maxTrackedSubjects' | 'maxCachedSubjects' |
    'maxConcurrentReads' | 'now'>> = {},
): PrivyLinkedIdentityResolver | undefined {
  if (!env['PRIVY_APP_ID'] || !env['PRIVY_APP_SECRET']) return undefined;
  return readPrivyLinkedIdentityResolver(env, overrides);
}

export interface AccountContextResponse {
  readonly schemaVersion: 1;
  readonly userId: string;
  readonly xIdentity: PrivyTwitterIdentity;
  readonly embeddedSolanaWallet: PrivyEmbeddedSolanaWallet;
}

const xIdentitySchema = {
  oneOf: [
    {type: 'object', additionalProperties: false, required: ['status'],
      properties: {status: {const: 'missing'}}},
    {type: 'object', additionalProperties: false, required: ['status'],
      properties: {status: {const: 'ambiguous'}}},
    {type: 'object', additionalProperties: false,
      required: ['status', 'subject', 'usernameSnapshot', 'verifiedAtUnixSeconds'],
      properties: {
        status: {const: 'verified'}, subject: {type: 'string'}, usernameSnapshot: {type: 'string'},
        verifiedAtUnixSeconds: {type: 'integer'},
      }},
  ],
} as const;
const embeddedWalletSchema = {
  oneOf: [
    {type: 'object', additionalProperties: false, required: ['status'],
      properties: {status: {const: 'missing'}}},
    {type: 'object', additionalProperties: false, required: ['status'],
      properties: {status: {const: 'ambiguous'}}},
    {type: 'object', additionalProperties: false,
      required: ['status', 'address', 'verifiedAtUnixSeconds'],
      properties: {
        status: {const: 'candidate'}, address: {type: 'string'},
        verifiedAtUnixSeconds: {type: 'integer'},
      }},
  ],
} as const;
const responseSchema = {
  type: 'object', additionalProperties: false,
  required: ['schemaVersion', 'userId', 'xIdentity', 'embeddedSolanaWallet'],
  properties: {
    schemaVersion: {const: 1}, userId: {type: 'string'},
    xIdentity: xIdentitySchema, embeddedSolanaWallet: embeddedWalletSchema,
  },
} as const;

function ownData(record: Record<string, unknown>, key: string): unknown {
  const descriptor = Object.getOwnPropertyDescriptor(record, key);
  return descriptor?.enumerable && Object.hasOwn(descriptor, 'value') ? descriptor.value : undefined;
}

function plainRecord(value: unknown): Record<string, unknown> | undefined {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return undefined;
  const prototype: unknown = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null ? value as Record<string, unknown> : undefined;
}

function positiveUnixSeconds(value: unknown): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value > 0;
}

function xSubject(value: unknown): value is string {
  try {
    return typeof value === 'string' && /^[1-9][0-9]{0,19}$/.exec(value)?.[0] === value &&
      BigInt(value) <= 18_446_744_073_709_551_615n;
  } catch { return false; }
}

function projectXIdentity(value: unknown): PrivyTwitterIdentity | undefined {
  const record = plainRecord(value);
  const status = record && ownData(record, 'status');
  if (status === 'missing' || status === 'ambiguous') return Object.freeze({status});
  if (status !== 'verified' || !record) return undefined;
  const subject = ownData(record, 'subject');
  const usernameSnapshot = ownData(record, 'usernameSnapshot');
  const verifiedAtUnixSeconds = ownData(record, 'verifiedAtUnixSeconds');
  if (!xSubject(subject) || typeof usernameSnapshot !== 'string' ||
      /^[a-z0-9_]{1,15}$/.exec(usernameSnapshot)?.[0] !== usernameSnapshot ||
      !positiveUnixSeconds(verifiedAtUnixSeconds)) return undefined;
  return Object.freeze({status, subject, usernameSnapshot, verifiedAtUnixSeconds});
}

function projectEmbeddedWallet(value: unknown): PrivyEmbeddedSolanaWallet | undefined {
  const record = plainRecord(value);
  const status = record && ownData(record, 'status');
  if (status === 'missing' || status === 'ambiguous') return Object.freeze({status});
  if (status !== 'candidate' || !record) return undefined;
  const candidateAddress = ownData(record, 'address');
  const verifiedAtUnixSeconds = ownData(record, 'verifiedAtUnixSeconds');
  try {
    if (typeof candidateAddress !== 'string' || candidateAddress.length < 32 ||
        candidateAddress.length > 44) return undefined;
    const parsed = address(candidateAddress);
    if (parsed !== candidateAddress || isOffCurveAddress(parsed) ||
        getAddressEncoder().encode(parsed).every(byte => byte === 0) ||
        !positiveUnixSeconds(verifiedAtUnixSeconds)) return undefined;
  } catch { return undefined; }
  return Object.freeze({status, address: candidateAddress, verifiedAtUnixSeconds});
}

/** Re-project injected resolver output before crossing HTTP. This keeps provider
 * metadata and accidental extra fields out even when an adapter is faulty. */
function projectResolution(value: unknown, expectedSubject: string): Readonly<{
  xIdentity: PrivyTwitterIdentity;
  embeddedSolanaWallet: PrivyEmbeddedSolanaWallet;
}> {
  const record = plainRecord(value);
  const xIdentity = record && projectXIdentity(ownData(record, 'twitter'));
  const embeddedSolanaWallet = record && projectEmbeddedWallet(ownData(record, 'embeddedSolanaWallet'));
  if (!record || ownData(record, 'provider') !== 'privy' ||
      ownData(record, 'subject') !== expectedSubject || !xIdentity || !embeddedSolanaWallet) {
    throw new PrivyLinkedIdentityError('PRIVY_USER_RESPONSE_INVALID');
  }
  return Object.freeze({xIdentity, embeddedSolanaWallet});
}

function problem(request: FastifyRequest, reply: FastifyReply,
  status: number, code: string, message: string) {
  return reply.code(status).send({error: {code, message, requestId: request.id}});
}

const unavailable = (request: FastifyRequest, reply: FastifyReply) =>
  problem(request, reply, 503, 'ACCOUNT_CONTEXT_UNAVAILABLE', 'Account context is unavailable.');
const unauthenticated = (request: FastifyRequest, reply: FastifyReply) =>
  problem(request, reply, 401, 'ACCOUNT_CONTEXT_UNAUTHENTICATED', 'A verified existing account is required.');

function providerFailure(error: unknown, request: FastifyRequest, reply: FastifyReply) {
  const statuses: Readonly<Record<PrivyLinkedIdentityErrorCode, number>> = Object.freeze({
    PRIVY_LINKED_IDENTITIES_NOT_CONFIGURED: 503,
    PRIVY_VERIFIED_IDENTITY_INVALID: 503,
    PRIVY_USER_RESPONSE_INVALID: 502,
    PRIVY_USER_UNAVAILABLE: 502,
    PRIVY_USER_TIMEOUT: 504,
    PRIVY_USER_RATE_LIMITED: 429,
  });
  const safe = error instanceof PrivyLinkedIdentityError && Object.hasOwn(statuses, error.code)
    ? new PrivyLinkedIdentityError(error.code)
    : new PrivyLinkedIdentityError('PRIVY_USER_UNAVAILABLE');
  return problem(request, reply, statuses[safe.code], safe.code, safe.message);
}

/** Read-only composition. No POST/HEAD route, provisioning, provider linking,
 * wallet action, signing, transaction construction, or financial mutation. */
export function registerAccountContextRoute(app: FastifyInstance, options?: AccountContextAdapters): void {
  const adapters = accountContextEnabled(options) ? options : undefined;
  const authenticated = new WeakMap<FastifyRequest, ExistingPracticeAccountAuthentication>();
  app.get(ACCOUNT_CONTEXT_ROUTE, {
    exposeHeadRoute: false,
    schema: {
      querystring: {type: 'object', additionalProperties: false, properties: {}},
      response: {200: responseSchema},
    },
    onRequest: async (request, reply) => {
      reply.header('cache-control', 'no-store');
      if (!adapters) return unavailable(request, reply);
      if (request.raw.url !== ACCOUNT_CONTEXT_ROUTE ||
          request.headers['transfer-encoding'] !== undefined ||
          request.headers['content-length'] !== undefined && request.headers['content-length'] !== '0') {
        return problem(request, reply, 400, 'ACCOUNT_CONTEXT_INVALID_REQUEST',
          'Account context accepts no request body.');
      }
      try {
        const result = await adapters.authenticate(request);
        if (!result) return unauthenticated(request, reply);
        authenticated.set(request, Object.freeze({
          userId: parsePracticeUserId(result.userId),
          identity: parsePracticeIdentity(result.identity),
        }));
      } catch (error) {
        return error instanceof PracticeAuthenticationUnavailable
          ? unavailable(request, reply) : unauthenticated(request, reply);
      }
    },
  }, async (request, reply): Promise<AccountContextResponse | FastifyReply> => {
    if (!adapters) return unavailable(request, reply);
    const account = authenticated.get(request);
    if (!account) return unauthenticated(request, reply);
    try {
      let resolution: PrivyLinkedIdentityResolution;
      if (request.headers['cache-control'] === 'no-cache') {
        if (typeof adapters.linkedIdentities.resolveFresh !== 'function') return unavailable(request, reply);
        // A wallet just created in the SDK must not be hidden by a previously
        // cached missing-wallet observation. Authentication still runs first.
        resolution = await adapters.linkedIdentities.resolveFresh(account.identity);
      } else {
        resolution = await adapters.linkedIdentities.resolve(account.identity);
      }
      const linked = projectResolution(resolution, account.identity.subject);
      return Object.freeze({
        schemaVersion: 1,
        userId: account.userId,
        xIdentity: linked.xIdentity,
        embeddedSolanaWallet: linked.embeddedSolanaWallet,
      });
    } catch (error) {
      return providerFailure(error, request, reply);
    }
  });
}
