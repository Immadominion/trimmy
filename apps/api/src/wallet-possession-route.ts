import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { parsePracticeIdentity } from './practice-identity.js';
import type { PracticeIdentity } from './practice-identity.js';
import { parsePracticeUserId } from './practice-repository.js';
import { PracticeAuthenticationUnavailable } from './practice-session-routes.js';
import type { ExistingPracticeAccountAuthentication } from './practice-session-routes.js';
import { PrivyLinkedIdentityError } from './privy-linked-identities.js';
import type { PrivyLinkedIdentityErrorCode, PrivyLinkedIdentityResolution } from './privy-linked-identities.js';
import { WalletPossessionError } from './wallet-possession.js';
import type { WalletNetwork, WalletPossessionErrorCode, WalletPossessionService } from './wallet-possession.js';

/**
 * Two account-scoped writes that move no money: one issues a single-use
 * possession challenge for the wallet already linked to the caller's Privy
 * subject, the other accepts that wallet's signature and records the binding.
 * Neither builds, signs or submits a transaction, and neither accepts a wallet
 * address from the request: the address always comes from the server-side
 * linked-identity lookup for the authenticated subject.
 */
export const WALLET_CHALLENGE_ROUTE = '/v1/account/wallet/challenge';
export const WALLET_POSSESSION_ROUTE = '/v1/account/wallet/possession';

export interface WalletPossessionIdentityResolver {
  resolve(identity: PracticeIdentity): Promise<PrivyLinkedIdentityResolution>;
  /** Must perform a new provider read; no cache or earlier in-flight result. */
  resolveFresh(identity: PracticeIdentity): Promise<PrivyLinkedIdentityResolution>;
}

export interface WalletPossessionAdapters {
  /** Verifier plus existing-account lookup only; this must never provision. */
  readonly authenticate: (request: FastifyRequest) => Promise<ExistingPracticeAccountAuthentication | null>;
  readonly linkedIdentities: WalletPossessionIdentityResolver;
  readonly service: Pick<WalletPossessionService, 'issue' | 'verify'>;
  readonly network: WalletNetwork;
}

export function walletPossessionEnabled(value?: WalletPossessionAdapters): value is WalletPossessionAdapters {
  return typeof value?.authenticate === 'function' &&
    typeof value.linkedIdentities?.resolve === 'function' &&
    typeof value.linkedIdentities.resolveFresh === 'function' &&
    typeof value.service?.issue === 'function' && typeof value.service?.verify === 'function' &&
    ['mainnet-beta', 'devnet', 'localnet'].includes(value.network);
}

class WalletStateError extends Error {
  constructor(readonly code: 'ACCOUNT_WALLET_MISSING' | 'ACCOUNT_WALLET_AMBIGUOUS') {
    super(code === 'ACCOUNT_WALLET_MISSING'
      ? 'Connect one embedded Solana wallet to check it.'
      : 'Wallet checks are unavailable while more than one embedded Solana wallet is linked.');
    this.name = 'WalletStateError';
  }
}

function plainRecord(value: unknown): Record<string, unknown> | null {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return null;
  const proto: unknown = Object.getPrototypeOf(value);
  return proto === Object.prototype || proto === null ? value as Record<string, unknown> : null;
}

function ownData(record: Record<string, unknown>, key: string): unknown {
  const descriptor = Object.getOwnPropertyDescriptor(record, key);
  return descriptor?.enumerable && Object.hasOwn(descriptor, 'value') ? descriptor.value : undefined;
}

interface LinkedWallet { readonly address: string; readonly providerWalletId: string | null }

function linkedWallet(value: unknown, expectedSubject: string): LinkedWallet {
  const resolution = plainRecord(value);
  if (!resolution || ownData(resolution, 'provider') !== 'privy' || ownData(resolution, 'subject') !== expectedSubject) {
    throw new PrivyLinkedIdentityError('PRIVY_USER_RESPONSE_INVALID');
  }
  const wallet = plainRecord(ownData(resolution, 'embeddedSolanaWallet'));
  const status = wallet && ownData(wallet, 'status');
  if (status === 'missing') throw new WalletStateError('ACCOUNT_WALLET_MISSING');
  if (status === 'ambiguous') throw new WalletStateError('ACCOUNT_WALLET_AMBIGUOUS');
  const walletAddress = wallet && ownData(wallet, 'address');
  const verifiedAt = wallet && ownData(wallet, 'verifiedAtUnixSeconds');
  if (status !== 'candidate' || typeof walletAddress !== 'string' || walletAddress.length < 32 ||
      walletAddress.length > 44 || !/^[1-9A-HJ-NP-Za-km-z]+$/.test(walletAddress) ||
      typeof verifiedAt !== 'number' || !Number.isSafeInteger(verifiedAt) || verifiedAt <= 0) {
    throw new PrivyLinkedIdentityError('PRIVY_USER_RESPONSE_INVALID');
  }
  const providerWalletId = wallet && ownData(wallet, 'walletId');
  if (providerWalletId !== undefined && providerWalletId !== null &&
      (typeof providerWalletId !== 'string' || /^[\x21-\x7e]{1,200}$/.exec(providerWalletId)?.[0] !== providerWalletId)) {
    throw new PrivyLinkedIdentityError('PRIVY_USER_RESPONSE_INVALID');
  }
  return Object.freeze({
    address: walletAddress,
    providerWalletId: typeof providerWalletId === 'string' && providerWalletId.length >= 1 &&
      providerWalletId.length <= 200 ? providerWalletId : null,
  });
}

function problem(request: FastifyRequest, reply: FastifyReply, status: number, code: string, message: string) {
  return reply.code(status).send({error: {code, message, requestId: request.id}});
}
const unavailable = (request: FastifyRequest, reply: FastifyReply) =>
  problem(request, reply, 503, 'ACCOUNT_WALLET_UNAVAILABLE', 'Wallet checks are unavailable.');
const unauthenticated = (request: FastifyRequest, reply: FastifyReply) =>
  problem(request, reply, 401, 'ACCOUNT_WALLET_UNAUTHENTICATED', 'A verified existing account is required.');

function identityFailure(error: unknown, request: FastifyRequest, reply: FastifyReply) {
  if (error instanceof WalletStateError) return problem(request, reply, 409, error.code, error.message);
  const statuses: Readonly<Record<PrivyLinkedIdentityErrorCode, number>> = Object.freeze({
    PRIVY_LINKED_IDENTITIES_NOT_CONFIGURED: 503,
    PRIVY_VERIFIED_IDENTITY_INVALID: 503,
    PRIVY_USER_RESPONSE_INVALID: 502,
    PRIVY_USER_UNAVAILABLE: 502,
    PRIVY_USER_TIMEOUT: 504,
    PRIVY_USER_RATE_LIMITED: 429,
  });
  const safe = error instanceof PrivyLinkedIdentityError && Object.hasOwn(statuses, error.code)
    ? new PrivyLinkedIdentityError(error.code) : new PrivyLinkedIdentityError('PRIVY_USER_UNAVAILABLE');
  return problem(request, reply, statuses[safe.code], safe.code, safe.message);
}

function possessionFailure(error: unknown, request: FastifyRequest, reply: FastifyReply) {
  const statuses: Readonly<Record<WalletPossessionErrorCode, number>> = Object.freeze({
    WALLET_POSSESSION_CONFIGURATION_INVALID: 503,
    WALLET_POSSESSION_INPUT_INVALID: 400,
    WALLET_POSSESSION_CHALLENGE_NOT_FOUND: 409,
    WALLET_POSSESSION_CHALLENGE_EXPIRED: 409,
    WALLET_POSSESSION_SIGNATURE_INVALID: 409,
    WALLET_POSSESSION_WALLET_CHANGED: 409,
    WALLET_POSSESSION_STORE_UNAVAILABLE: 503,
    WALLET_POSSESSION_RATE_LIMITED: 429,
  });
  const safe = error instanceof WalletPossessionError && Object.hasOwn(statuses, error.code)
    ? new WalletPossessionError(error.code) : new WalletPossessionError('WALLET_POSSESSION_STORE_UNAVAILABLE');
  return problem(request, reply, statuses[safe.code], safe.code, safe.message);
}

const noQuery = {type: 'object', additionalProperties: false, properties: {}} as const;
const challengeResponseSchema = {
  type: 'object', additionalProperties: false,
  required: ['schemaVersion', 'challenge'],
  properties: {
    schemaVersion: {const: 1},
    challenge: {
      type: 'object', additionalProperties: false,
      required: ['challengeId', 'walletAddress', 'network', 'message', 'issuedAt', 'expiresAt'],
      properties: {
        challengeId: {type: 'string', format: 'uuid'},
        walletAddress: {type: 'string', minLength: 32, maxLength: 44},
        network: {type: 'string', enum: ['mainnet-beta', 'devnet', 'localnet']},
        message: {type: 'string', minLength: 1, maxLength: 1_024},
        issuedAt: {type: 'string', minLength: 20, maxLength: 30},
        expiresAt: {type: 'string', minLength: 20, maxLength: 30},
      },
    },
  },
} as const;
const possessionBodySchema = {
  type: 'object', additionalProperties: false, required: ['challengeId', 'signature'],
  properties: {
    challengeId: {type: 'string', format: 'uuid'},
    signature: {type: 'string', minLength: 64, maxLength: 128, pattern: '^[1-9A-HJ-NP-Za-km-z]+$'},
  },
} as const;
const possessionResponseSchema = {
  type: 'object', additionalProperties: false,
  required: ['schemaVersion', 'kind', 'walletAddress', 'network', 'possessionSignatureVerified', 'verifiedAt', 'binding'],
  properties: {
    schemaVersion: {const: 1},
    kind: {const: 'wallet_possession'},
    walletAddress: {type: 'string', minLength: 32, maxLength: 44},
    network: {type: 'string', enum: ['mainnet-beta', 'devnet', 'localnet']},
    possessionSignatureVerified: {const: true},
    verifiedAt: {type: 'string', minLength: 20, maxLength: 30},
    binding: {
      type: 'object', additionalProperties: false, required: ['id', 'verifiedAt'],
      properties: {id: {type: 'string', format: 'uuid'}, verifiedAt: {type: 'string', minLength: 20, maxLength: 30}},
    },
  },
} as const;

export function registerWalletPossessionRoutes(app: FastifyInstance, options?: WalletPossessionAdapters): void {
  const adapters = walletPossessionEnabled(options) ? options : undefined;
  if (!adapters) return;
  const authenticated = new WeakMap<FastifyRequest, ExistingPracticeAccountAuthentication>();

  const authenticate = async (request: FastifyRequest, reply: FastifyReply) => {
    reply.header('cache-control', 'no-store');
    try {
      const result = await adapters.authenticate(request);
      if (!result) return unauthenticated(request, reply);
      authenticated.set(request, Object.freeze({
        userId: parsePracticeUserId(result.userId), identity: parsePracticeIdentity(result.identity),
      }));
    } catch (error) {
      return error instanceof PracticeAuthenticationUnavailable
        ? unavailable(request, reply) : unauthenticated(request, reply);
    }
  };

  app.post(WALLET_CHALLENGE_ROUTE, {
    schema: {querystring: noQuery, body: noQuery, response: {201: challengeResponseSchema}},
    onRequest: authenticate,
  }, async (request, reply) => {
    const account = authenticated.get(request);
    if (!account) return unauthenticated(request, reply);
    let wallet: LinkedWallet;
    try {
      wallet = linkedWallet(await adapters.linkedIdentities.resolve(account.identity), account.identity.subject);
    } catch (error) {
      return identityFailure(error, request, reply);
    }
    try {
      const challenge = await adapters.service.issue({
        userId: account.userId, walletAddress: wallet.address, network: adapters.network,
        providerWalletId: wallet.providerWalletId,
      });
      return reply.code(201).send({
        schemaVersion: 1,
        challenge: {
          challengeId: challenge.challengeId, walletAddress: challenge.walletAddress, network: challenge.network,
          message: challenge.message, issuedAt: challenge.issuedAt, expiresAt: challenge.expiresAt,
        },
      });
    } catch (error) {
      return possessionFailure(error, request, reply);
    }
  });

  app.post(WALLET_POSSESSION_ROUTE, {
    schema: {querystring: noQuery, body: possessionBodySchema, response: {200: possessionResponseSchema}},
    onRequest: authenticate,
  }, async (request, reply) => {
    const account = authenticated.get(request);
    if (!account) return unauthenticated(request, reply);
    const body = request.body as {challengeId: string; signature: string};
    let wallet: LinkedWallet;
    try {
      // Resolve before taking the challenge. An unavailable provider or missing
      // link cannot record a binding and does not burn a still-valid proof.
      wallet = linkedWallet(await adapters.linkedIdentities.resolveFresh(account.identity), account.identity.subject);
    } catch (error) {
      return identityFailure(error, request, reply);
    }
    try {
      const verified = await adapters.service.verify({
        userId: account.userId, challengeId: body.challengeId, signature: body.signature,
        expectedWallet: {...wallet, network: adapters.network},
      });
      return reply.code(200).send({
        schemaVersion: 1, kind: 'wallet_possession', walletAddress: verified.walletAddress,
        network: adapters.network, possessionSignatureVerified: true, verifiedAt: verified.verifiedAt,
        binding: {id: verified.binding.id, verifiedAt: verified.binding.verifiedAt},
      });
    } catch (error) {
      return possessionFailure(error, request, reply);
    }
  });
}
