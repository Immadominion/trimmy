import { createPublicKey, randomBytes, randomUUID, verify as verifySignature } from 'node:crypto';
import { address, getAddressEncoder, getBase58Decoder, getBase58Encoder, isOffCurveAddress } from '@solana/kit';

/**
 * Wallet possession: the account owner signs a fixed, domain-separated, single
 * use challenge with the wallet linked to their Privy subject, proving they
 * control its key rather than merely having it listed on their account.
 *
 * The signed text authorizes no transfer, swap or payment, and this module
 * neither builds nor signs a transaction. A recorded binding is a fact about
 * key control at one instant; a later reviewed order still needs its own
 * explicit approval.
 */
export type WalletNetwork = 'mainnet-beta' | 'devnet' | 'localnet';

export type WalletPossessionErrorCode =
  | 'WALLET_POSSESSION_CONFIGURATION_INVALID'
  | 'WALLET_POSSESSION_INPUT_INVALID'
  | 'WALLET_POSSESSION_CHALLENGE_NOT_FOUND'
  | 'WALLET_POSSESSION_CHALLENGE_EXPIRED'
  | 'WALLET_POSSESSION_SIGNATURE_INVALID'
  | 'WALLET_POSSESSION_WALLET_CHANGED'
  | 'WALLET_POSSESSION_STORE_UNAVAILABLE'
  | 'WALLET_POSSESSION_RATE_LIMITED';

const MESSAGES: Readonly<Record<WalletPossessionErrorCode, string>> = Object.freeze({
  WALLET_POSSESSION_CONFIGURATION_INVALID: 'Wallet checks are not configured.',
  WALLET_POSSESSION_INPUT_INVALID: 'The wallet check request is invalid.',
  WALLET_POSSESSION_CHALLENGE_NOT_FOUND: 'Start the wallet check again.',
  WALLET_POSSESSION_CHALLENGE_EXPIRED: 'That wallet check expired. Start it again.',
  WALLET_POSSESSION_SIGNATURE_INVALID: 'That signature does not match your wallet.',
  WALLET_POSSESSION_WALLET_CHANGED: 'Your linked wallet changed. Start the wallet check again.',
  WALLET_POSSESSION_STORE_UNAVAILABLE: 'Wallet checks are unavailable right now.',
  WALLET_POSSESSION_RATE_LIMITED: 'Wait a moment before starting another wallet check.',
});

export class WalletPossessionError extends Error {
  constructor(readonly code: WalletPossessionErrorCode) {
    super(MESSAGES[code]);
    this.name = 'WalletPossessionError';
  }
}
const fail = (code: WalletPossessionErrorCode): never => { throw new WalletPossessionError(code); };

export interface WalletPossessionChallenge {
  readonly schemaVersion: 1;
  readonly kind: 'wallet_possession_challenge';
  readonly challengeId: string;
  readonly userId: string;
  readonly walletAddress: string;
  readonly network: WalletNetwork;
  /** Server-only context. Never accepted from the proof request body. */
  readonly providerWalletId: string | null;
  readonly nonce: string;
  readonly issuedAt: string;
  readonly expiresAt: string;
  readonly message: string;
}

export interface WalletBindingRecord {
  readonly id: string;
  readonly userId: string;
  readonly network: WalletNetwork;
  readonly address: string;
  readonly providerWalletId: string | null;
  readonly verifiedAt: string;
}

export interface WalletPossessionChallengeStore {
  put(challenge: WalletPossessionChallenge): Promise<void>;
  /** Single use: returns and removes the challenge for this account, or null. */
  take(userId: string, challengeId: string): Promise<WalletPossessionChallenge | null>;
}

export interface WalletBindingStore {
  /** Idempotent for an unrevoked (account, network, address) binding. */
  record(binding: {userId: string; network: WalletNetwork; address: string;
    providerWalletId: string | null; verifiedAt: string}): Promise<WalletBindingRecord>;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const HEX_NONCE = /^[0-9a-f]{64}$/;
const BASE58 = /^[1-9A-HJ-NP-Za-km-z]+$/;
const NETWORKS: readonly WalletNetwork[] = ['mainnet-beta', 'devnet', 'localnet'];
const SPKI_ED25519_PREFIX = Buffer.from('302a300506032b6570032100', 'hex');
const DEFAULT_TTL_MS = 300_000;
const MIN_TTL_MS = 30_000;
const MAX_TTL_MS = 900_000;
const DEFAULT_PER_USER_LIMIT = 5;
const RATE_WINDOW_MS = 60_000;
const DEFAULT_MAX_ENTRIES = 10_000;

/**
 * The exact text a wallet signs. It is fixed and domain separated: the leading
 * lines tell the person what they are signing, and every field that scopes the
 * proof (account, wallet, network, nonce, validity) is inside the signed bytes.
 */
export function composeWalletPossessionMessage(fields: Pick<WalletPossessionChallenge,
  'challengeId' | 'userId' | 'walletAddress' | 'network' | 'nonce' | 'issuedAt' | 'expiresAt'>): string {
  return [
    'Trimmy wallet possession',
    'This signature proves you control this wallet for your Trimmy account.',
    'It authorizes no transfer, swap or payment.',
    `challenge: ${fields.challengeId}`,
    `account: ${fields.userId}`,
    `wallet: ${fields.walletAddress}`,
    `network: ${fields.network}`,
    `nonce: ${fields.nonce}`,
    `issued: ${fields.issuedAt}`,
    `expires: ${fields.expiresAt}`,
  ].join('\n');
}

function walletAddress(value: unknown): string {
  try {
    if (typeof value !== 'string' || value.length < 32 || value.length > 44) return fail('WALLET_POSSESSION_INPUT_INVALID');
    const parsed = address(value);
    if (parsed !== value || isOffCurveAddress(parsed)) return fail('WALLET_POSSESSION_INPUT_INVALID');
    const encoded = getAddressEncoder().encode(parsed);
    if (encoded.every(byte => byte === 0)) return fail('WALLET_POSSESSION_INPUT_INVALID');
    return parsed;
  } catch (error) {
    if (error instanceof WalletPossessionError) throw error;
    return fail('WALLET_POSSESSION_INPUT_INVALID');
  }
}

/**
 * Verifies an ed25519 signature over the UTF-8 message bytes against the
 * wallet address. It returns false rather than throwing for every malformed
 * input, so a caller cannot distinguish a bad key from a bad signature.
 */
export function verifyWalletMessageSignature(input: {walletAddress: string; message: string; signature: string}): boolean {
  try {
    if (input === null || typeof input !== 'object' || typeof input.message !== 'string' ||
        input.message.length < 1 || input.message.length > 4_096 || typeof input.signature !== 'string' ||
        input.signature.length < 64 || input.signature.length > 128 || !BASE58.test(input.signature)) {
      return false;
    }
    const parsed = address(input.walletAddress);
    if (parsed !== input.walletAddress || isOffCurveAddress(parsed)) return false;
    const key = Buffer.from(getAddressEncoder().encode(parsed));
    if (key.length !== 32) return false;
    const signature = Buffer.from(getBase58Encoder().encode(input.signature));
    if (signature.length !== 64) return false;
    const publicKey = createPublicKey({
      key: Buffer.concat([SPKI_ED25519_PREFIX, key]), format: 'der', type: 'spki',
    });
    return verifySignature(null, Buffer.from(input.message, 'utf8'), publicKey, signature);
  } catch {
    return false;
  }
}

/**
 * Process-local challenge storage. It is bounded and evicts expired entries, so
 * a burst cannot grow it without limit. A multi-process deployment needs a
 * shared store: a challenge issued by one process must be takeable by another,
 * and single use must hold across all of them.
 */
export class InMemoryWalletPossessionChallengeStore implements WalletPossessionChallengeStore {
  readonly #entries = new Map<string, WalletPossessionChallenge>();
  readonly #maxEntries: number;
  readonly #now: () => number;

  constructor(options: {maxEntries?: number; now?: () => number} = {}) {
    const maxEntries = options.maxEntries ?? DEFAULT_MAX_ENTRIES;
    if (!Number.isInteger(maxEntries) || maxEntries < 1 || maxEntries > 1_000_000 ||
        (options.now !== undefined && typeof options.now !== 'function')) {
      fail('WALLET_POSSESSION_CONFIGURATION_INVALID');
    }
    this.#maxEntries = maxEntries;
    this.#now = options.now ?? Date.now;
  }

  get size(): number { return this.#entries.size; }

  async put(challenge: WalletPossessionChallenge): Promise<void> {
    this.#evict();
    if (this.#entries.size >= this.#maxEntries) fail('WALLET_POSSESSION_STORE_UNAVAILABLE');
    this.#entries.set(`${challenge.userId}:${challenge.challengeId}`, challenge);
  }

  async take(userId: string, challengeId: string): Promise<WalletPossessionChallenge | null> {
    const key = `${userId}:${challengeId}`;
    const challenge = this.#entries.get(key) ?? null;
    // Consumed on read, so a replay of the same challenge cannot verify twice.
    this.#entries.delete(key);
    return challenge;
  }

  #evict(): void {
    const now = this.#now();
    for (const [key, challenge] of this.#entries) {
      if (Date.parse(challenge.expiresAt) <= now) this.#entries.delete(key);
    }
  }
}

/** Process-local binding storage for tests and an unconfigured runtime. */
export class InMemoryWalletBindingStore implements WalletBindingStore {
  readonly #records: WalletBindingRecord[] = [];

  async record(binding: {userId: string; network: WalletNetwork; address: string;
    providerWalletId: string | null; verifiedAt: string}): Promise<WalletBindingRecord> {
    const existing = this.#records.find(item => item.userId === binding.userId &&
      item.network === binding.network && item.address === binding.address);
    if (existing) return existing;
    const created = Object.freeze({id: randomUUID(), ...binding});
    this.#records.push(created);
    return created;
  }

  list(): readonly WalletBindingRecord[] { return Object.freeze([...this.#records]); }
}

export interface WalletPossessionServiceOptions {
  readonly challenges: WalletPossessionChallengeStore;
  readonly bindings: WalletBindingStore;
  readonly now?: () => number;
  readonly ttlMs?: number;
  readonly perUserLimit?: number;
}

export interface WalletPossessionVerification {
  readonly binding: WalletBindingRecord;
  readonly walletAddress: string;
  readonly possessionSignatureVerified: true;
  readonly verifiedAt: string;
}

export interface ExpectedPossessionWallet {
  readonly address: string;
  readonly network: WalletNetwork;
  readonly providerWalletId: string | null;
}

function validProviderWalletId(value: unknown): value is string | null {
  return value === null || typeof value === 'string' && /^[\x21-\x7e]{1,200}$/.exec(value)?.[0] === value;
}

export class WalletPossessionService {
  readonly #challenges: WalletPossessionChallengeStore;
  readonly #bindings: WalletBindingStore;
  readonly #now: () => number;
  readonly #ttlMs: number;
  readonly #perUserLimit: number;
  readonly #issued = new Map<string, number[]>();

  constructor(options: WalletPossessionServiceOptions) {
    const ttlMs = options?.ttlMs ?? DEFAULT_TTL_MS;
    const perUserLimit = options?.perUserLimit ?? DEFAULT_PER_USER_LIMIT;
    if (options === null || typeof options !== 'object' ||
        typeof options.challenges?.put !== 'function' || typeof options.challenges?.take !== 'function' ||
        typeof options.bindings?.record !== 'function' ||
        (options.now !== undefined && typeof options.now !== 'function') ||
        !Number.isInteger(ttlMs) || ttlMs < MIN_TTL_MS || ttlMs > MAX_TTL_MS ||
        !Number.isInteger(perUserLimit) || perUserLimit < 1 || perUserLimit > 100) {
      fail('WALLET_POSSESSION_CONFIGURATION_INVALID');
    }
    this.#challenges = options.challenges;
    this.#bindings = options.bindings;
    this.#now = options.now ?? Date.now;
    this.#ttlMs = ttlMs;
    this.#perUserLimit = perUserLimit;
  }

  async issue(input: {userId: string; walletAddress: string; network: WalletNetwork;
    providerWalletId: string | null}): Promise<WalletPossessionChallenge> {
    if (input === null || typeof input !== 'object' || typeof input.userId !== 'string' || !UUID.test(input.userId) ||
        !NETWORKS.includes(input.network) ||
        !validProviderWalletId(input.providerWalletId)) {
      return fail('WALLET_POSSESSION_INPUT_INVALID');
    }
    const wallet = walletAddress(input.walletAddress);
    const now = this.#now();
    this.#admitIssue(input.userId, now);
    const issuedAt = new Date(now).toISOString();
    const expiresAt = new Date(now + this.#ttlMs).toISOString();
    const fields = {
      challengeId: randomUUID(), userId: input.userId, walletAddress: wallet, network: input.network,
      nonce: randomBytes(32).toString('hex'), issuedAt, expiresAt,
    };
    const challenge: WalletPossessionChallenge = Object.freeze({
      schemaVersion: 1, kind: 'wallet_possession_challenge', ...fields,
      providerWalletId: input.providerWalletId,
      message: composeWalletPossessionMessage(fields),
    });
    try {
      await this.#challenges.put(challenge);
    } catch (error) {
      throw error instanceof WalletPossessionError ? error : new WalletPossessionError('WALLET_POSSESSION_STORE_UNAVAILABLE');
    }
    return challenge;
  }

  async verify(input: {userId: string; challengeId: string; signature: string;
    /** Fresh server-derived link for this authenticated account, never caller data. */
    expectedWallet: ExpectedPossessionWallet}): Promise<WalletPossessionVerification> {
    if (input === null || typeof input !== 'object' || typeof input.userId !== 'string' || !UUID.test(input.userId) ||
        typeof input.challengeId !== 'string' || !UUID.test(input.challengeId) ||
        typeof input.signature !== 'string' || input.signature.length < 64 || input.signature.length > 128 ||
        !BASE58.test(input.signature) ||
        !input.expectedWallet || typeof input.expectedWallet !== 'object' ||
        !NETWORKS.includes(input.expectedWallet.network) ||
        !validProviderWalletId(input.expectedWallet.providerWalletId)) {
      return fail('WALLET_POSSESSION_INPUT_INVALID');
    }
    const expectedAddress = walletAddress(input.expectedWallet.address);
    const expectedNetwork = input.expectedWallet.network;
    const expectedProviderWalletId = input.expectedWallet.providerWalletId;
    let challenge: WalletPossessionChallenge | null;
    try {
      challenge = await this.#challenges.take(input.userId, input.challengeId);
    } catch (error) {
      throw error instanceof WalletPossessionError ? error : new WalletPossessionError('WALLET_POSSESSION_STORE_UNAVAILABLE');
    }
    if (challenge === null) return fail('WALLET_POSSESSION_CHALLENGE_NOT_FOUND');
    if (challenge.kind !== 'wallet_possession_challenge' || challenge.userId !== input.userId ||
        challenge.challengeId !== input.challengeId || !HEX_NONCE.test(challenge.nonce) ||
        challenge.message !== composeWalletPossessionMessage(challenge) ||
        !validProviderWalletId(challenge.providerWalletId)) {
      return fail('WALLET_POSSESSION_STORE_UNAVAILABLE');
    }
    const now = this.#now();
    // The challenge is consumed whether or not it had expired.
    if (now >= Date.parse(challenge.expiresAt)) return fail('WALLET_POSSESSION_CHALLENGE_EXPIRED');
    // A confirmed change consumes the old challenge; the caller must request
    // and sign a new one for the currently linked wallet.
    if (challenge.walletAddress !== expectedAddress || challenge.network !== expectedNetwork ||
        challenge.providerWalletId !== expectedProviderWalletId) {
      return fail('WALLET_POSSESSION_WALLET_CHANGED');
    }
    if (!verifyWalletMessageSignature({
      walletAddress: challenge.walletAddress, message: challenge.message, signature: input.signature,
    })) {
      return fail('WALLET_POSSESSION_SIGNATURE_INVALID');
    }
    const verifiedAt = new Date(now).toISOString();
    let binding: WalletBindingRecord;
    try {
      binding = await this.#bindings.record({
        userId: challenge.userId, network: challenge.network, address: challenge.walletAddress,
        providerWalletId: challenge.providerWalletId, verifiedAt,
      });
    } catch (error) {
      throw error instanceof WalletPossessionError ? error : new WalletPossessionError('WALLET_POSSESSION_STORE_UNAVAILABLE');
    }
    if (binding?.userId !== challenge.userId || binding.address !== challenge.walletAddress ||
        binding.network !== challenge.network || !UUID.test(binding.id)) {
      return fail('WALLET_POSSESSION_STORE_UNAVAILABLE');
    }
    return Object.freeze({
      binding: Object.freeze({...binding}), walletAddress: challenge.walletAddress,
      possessionSignatureVerified: true, verifiedAt,
    });
  }

  /** Fixed window per account, so a lost challenge cannot be retried endlessly. */
  #admitIssue(userId: string, now: number): void {
    if (!this.#issued.has(userId) && this.#issued.size >= DEFAULT_MAX_ENTRIES) {
      for (const [key, entries] of this.#issued) {
        if (entries.every(at => now - at >= RATE_WINDOW_MS)) this.#issued.delete(key);
      }
      if (this.#issued.size >= DEFAULT_MAX_ENTRIES) fail('WALLET_POSSESSION_RATE_LIMITED');
    }
    const recent = (this.#issued.get(userId) ?? []).filter(at => now - at < RATE_WINDOW_MS);
    if (recent.length >= this.#perUserLimit) {
      this.#issued.set(userId, recent);
      fail('WALLET_POSSESSION_RATE_LIMITED');
    }
    recent.push(now);
    this.#issued.set(userId, recent);
  }
}

/** Base58 of a 64-byte signature, for callers that hold raw bytes. */
export function encodeWalletSignature(signature: Uint8Array): string {
  if (!(signature instanceof Uint8Array) || signature.byteLength !== 64) return fail('WALLET_POSSESSION_INPUT_INVALID');
  return getBase58Decoder().decode(signature);
}
