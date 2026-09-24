import {createRequire} from 'node:module';
import {address, getAddressEncoder, isOffCurveAddress} from '@solana/kit';
import {BoundedProviderRead} from './bounded-provider-read.js';
import {isPracticeAppId, parsePracticeIdentity} from './practice-identity.js';
import type {PracticeIdentity} from './practice-identity.js';

export const PRIVY_NODE_SDK_VERSION = '0.34.0' as const;
const privyApiUrl = 'https://api.privy.io';
const defaultTimeoutMs = 5_000;
const maxTimeoutMs = 10_000;
const maxLinkedAccounts = 128;
const defaultCacheTtlMs = 5_000;
const defaultRateLimitWindowMs = 60_000;
const defaultPerSubjectLimit = 6;
const defaultGlobalLimit = 300;
const defaultMaxTrackedSubjects = 2_048;
const defaultMaxCachedSubjects = 512;
const defaultMaxConcurrentReads = 16;

export type PrivyTwitterIdentity =
  | Readonly<{status: 'missing'}>
  | Readonly<{status: 'ambiguous'}>
  | Readonly<{
      status: 'verified';
      /** Stable numeric X subject. This is the identity key. */
      subject: string;
      /** Lowercase, provider-returned username snapshot. This is not an identity key. */
      usernameSnapshot: string;
      verifiedAtUnixSeconds: number;
    }>;

export type PrivyEmbeddedSolanaWallet =
  | Readonly<{status: 'missing'}>
  | Readonly<{status: 'ambiguous'}>
  | Readonly<{
      /** A linked embedded-wallet address candidate, not signing authorization. */
      status: 'candidate';
      address: string;
      /** Optional provider identifier retained only in server-side projections. */
      walletId?: string;
      verifiedAtUnixSeconds: number;
    }>;

export interface PrivyLinkedIdentityResolution {
  readonly provider: 'privy';
  readonly subject: string;
  readonly twitter: PrivyTwitterIdentity;
  readonly embeddedSolanaWallet: PrivyEmbeddedSolanaWallet;
}

export type PrivyLinkedIdentityErrorCode =
  | 'PRIVY_LINKED_IDENTITIES_NOT_CONFIGURED'
  | 'PRIVY_VERIFIED_IDENTITY_INVALID'
  | 'PRIVY_USER_RESPONSE_INVALID'
  | 'PRIVY_USER_UNAVAILABLE'
  | 'PRIVY_USER_TIMEOUT'
  | 'PRIVY_USER_RATE_LIMITED';

const errorMessages: Record<PrivyLinkedIdentityErrorCode, string> = {
  PRIVY_LINKED_IDENTITIES_NOT_CONFIGURED: 'Privy linked identities are not configured.',
  PRIVY_VERIFIED_IDENTITY_INVALID: 'The verified Privy identity is invalid.',
  PRIVY_USER_RESPONSE_INVALID: 'Privy returned an unusable user record.',
  PRIVY_USER_UNAVAILABLE: 'Privy linked identities are unavailable.',
  PRIVY_USER_TIMEOUT: 'Privy linked identities took too long to load.',
  PRIVY_USER_RATE_LIMITED: 'Too many linked identity reads. Try again shortly.',
};

export class PrivyLinkedIdentityError extends Error {
  constructor(readonly code: PrivyLinkedIdentityErrorCode) {
    super(errorMessages[code]);
    this.name = 'PrivyLinkedIdentityError';
  }
}

interface PrivyUserRequest {
  readonly signal: AbortSignal;
  readonly timeoutMs: number;
  readonly maxRetries: 0;
}

export interface PrivyUserByIdReader {
  /** The only provider capability exposed to this resolver. */
  getById(subject: string, request: PrivyUserRequest): Promise<unknown>;
}

export interface PrivyUserReaderFactoryConfiguration {
  readonly appId: string;
  readonly appSecret: string;
  readonly apiUrl: typeof privyApiUrl;
  readonly timeoutMs: number;
  readonly maxRetries: 0;
  readonly fetch?: typeof globalThis.fetch;
}

export type PrivyUserReaderFactory =
  (configuration: PrivyUserReaderFactoryConfiguration) => PrivyUserByIdReader;

export interface PrivyLinkedIdentityResolverOptions {
  readonly appId: string;
  readonly appSecret: string;
  readonly timeoutMs?: number;
  readonly cacheTtlMs?: number;
  readonly rateLimitWindowMs?: number;
  readonly perSubjectLimit?: number;
  readonly globalLimit?: number;
  readonly maxTrackedSubjects?: number;
  readonly maxCachedSubjects?: number;
  readonly maxConcurrentReads?: number;
  readonly now?: () => number;
  /** Test/transport injection. Production uses @privy-io/node 0.34.0. */
  readonly fetch?: typeof globalThis.fetch;
  readonly clientFactory?: PrivyUserReaderFactory;
}

interface SdkUsers {
  _get(subject: string, options: Readonly<{
    signal: AbortSignal;
    timeout: number;
    maxRetries: 0;
  }>): Promise<unknown>;
}
interface SdkClient {users(): SdkUsers}
type SdkClientConstructor = new (options: Readonly<Record<string, unknown>>) => SdkClient;

function loadOfficialPrivyClient(): SdkClientConstructor {
  // The exact dependency is pinned in apps/api/package.json and package-lock.json.
  // Keep the SDK behind this narrow read-only boundary: its full declarations
  // include wallet/signing surfaces that this module neither imports nor exposes.
  const sdk: unknown = createRequire(import.meta.url)('@privy-io/node');
  if (sdk === null || (typeof sdk !== 'object' && typeof sdk !== 'function')) {
    throw new Error('Privy SDK is unavailable.');
  }
  const constructor: unknown = (sdk as Record<string, unknown>)['PrivyClient'];
  if (typeof constructor !== 'function') throw new Error('Privy SDK client is unavailable.');
  return constructor as SdkClientConstructor;
}

function createOfficialReader(configuration: PrivyUserReaderFactoryConfiguration): PrivyUserByIdReader {
  const PrivyClient = loadOfficialPrivyClient();
  const options: Record<string, unknown> = {
    appId: configuration.appId,
    appSecret: configuration.appSecret,
    apiUrl: configuration.apiUrl,
    timeout: configuration.timeoutMs,
    maxRetries: configuration.maxRetries,
  };
  if (configuration.fetch !== undefined) options['fetch'] = configuration.fetch;
  const users = new PrivyClient(options).users();
  if (users === null || typeof users !== 'object' || typeof users._get !== 'function') {
    throw new Error('Privy SDK user reader is unavailable.');
  }
  return Object.freeze({
    getById: async (subject: string, request: PrivyUserRequest): Promise<unknown> =>
      users._get(subject, {
        signal: request.signal,
        timeout: request.timeoutMs,
        maxRetries: request.maxRetries,
      }),
  });
}

function exact(pattern: RegExp, value: unknown): value is string {
  return typeof value === 'string' && pattern.exec(value)?.[0] === value;
}

function configurationInvalid(): never {
  throw new PrivyLinkedIdentityError('PRIVY_LINKED_IDENTITIES_NOT_CONFIGURED');
}

function responseInvalid(): never {
  throw new PrivyLinkedIdentityError('PRIVY_USER_RESPONSE_INVALID');
}

function plainRecord(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) responseInvalid();
  const prototype: unknown = Object.getPrototypeOf(value);
  if (prototype !== Object.prototype && prototype !== null) responseInvalid();
  return value as Record<string, unknown>;
}

function ownData(record: Record<string, unknown>, key: string): unknown {
  const descriptor = Object.getOwnPropertyDescriptor(record, key);
  if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) return undefined;
  return descriptor.value;
}

function verifiedUnixSeconds(value: unknown): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value > 0;
}

function twitterSubject(value: unknown): value is string {
  return exact(/^[1-9][0-9]{0,19}$/, value) && BigInt(value) <= 18_446_744_073_709_551_615n;
}

function canonicalUsername(value: unknown): string | null {
  if (!exact(/^[A-Za-z0-9_]{1,15}$/, value)) return null;
  return value.toLowerCase();
}

function validSolanaAddress(value: unknown): value is string {
  if (typeof value !== 'string' || value.length < 32 || value.length > 44) return false;
  try {
    const parsed = address(value);
    return parsed === value && !isOffCurveAddress(parsed) &&
      !getAddressEncoder().encode(parsed).every(byte => byte === 0);
  } catch {
    return false;
  }
}

function resolveTwitter(accounts: readonly Record<string, unknown>[]): PrivyTwitterIdentity {
  const relevant = accounts.filter(account => ownData(account, 'type') === 'twitter_oauth');
  if (relevant.length === 0) return Object.freeze({status: 'missing'});
  if (relevant.length !== 1) return Object.freeze({status: 'ambiguous'});
  const account = relevant[0];
  if (!account) return Object.freeze({status: 'ambiguous'});
  const subject = ownData(account, 'subject');
  const username = canonicalUsername(ownData(account, 'username'));
  const verifiedAt = ownData(account, 'verified_at');
  if (!twitterSubject(subject) || username === null || !verifiedUnixSeconds(verifiedAt)) {
    return Object.freeze({status: 'ambiguous'});
  }
  return Object.freeze({status: 'verified', subject, usernameSnapshot: username,
    verifiedAtUnixSeconds: verifiedAt});
}

function mightBeEmbeddedSolanaWallet(account: Record<string, unknown>): boolean {
  if (ownData(account, 'type') !== 'wallet' || ownData(account, 'chain_type') !== 'solana') return false;
  return ownData(account, 'connector_type') === 'embedded' ||
    ownData(account, 'wallet_client') === 'privy' || ownData(account, 'wallet_client_type') === 'privy';
}

function resolveEmbeddedSolanaWallet(accounts: readonly Record<string, unknown>[]): PrivyEmbeddedSolanaWallet {
  const relevant = accounts.filter(mightBeEmbeddedSolanaWallet);
  if (relevant.length === 0) return Object.freeze({status: 'missing'});
  if (relevant.length !== 1) return Object.freeze({status: 'ambiguous'});
  const account = relevant[0];
  if (!account) return Object.freeze({status: 'ambiguous'});
  const walletIndex = ownData(account, 'wallet_index');
  const verifiedAt = ownData(account, 'verified_at');
  const walletAddress = ownData(account, 'address');
  const walletId = ownData(account, 'id');
  if (ownData(account, 'connector_type') !== 'embedded' ||
      ownData(account, 'wallet_client') !== 'privy' ||
      ownData(account, 'wallet_client_type') !== 'privy' ||
      typeof ownData(account, 'delegated') !== 'boolean' ||
      typeof ownData(account, 'imported') !== 'boolean' ||
      typeof walletIndex !== 'number' || !Number.isSafeInteger(walletIndex) || walletIndex < 0 ||
      !verifiedUnixSeconds(verifiedAt) || !validSolanaAddress(walletAddress) ||
      walletId !== undefined && walletId !== null && !exact(/^[\x21-\x7e]{1,200}$/, walletId)) {
    return Object.freeze({status: 'ambiguous'});
  }
  return Object.freeze({status: 'candidate', address: walletAddress,
    ...(typeof walletId === 'string' ? {walletId} : {}),
    verifiedAtUnixSeconds: verifiedAt});
}

/** Strictly projects the one requested user. Provider metadata outside the two
 * allowed projections is discarded, including email, OAuth tokens and other
 * linked accounts. Ambiguous also covers malformed relevant account records so
 * callers can never mistake partial provider data for a unique verified link.
 */
export function parsePrivyLinkedIdentities(value: unknown, expectedSubject: string): PrivyLinkedIdentityResolution {
  try {
    if (!exact(/^did:privy:[A-Za-z0-9]{1,128}$/, expectedSubject)) responseInvalid();
    const user = plainRecord(value);
    if (ownData(user, 'id') !== expectedSubject) responseInvalid();
    const linkedAccounts = ownData(user, 'linked_accounts');
    if (!Array.isArray(linkedAccounts) || linkedAccounts.length > maxLinkedAccounts) responseInvalid();
    const accounts = linkedAccounts.map(entry => {
      const record = plainRecord(entry);
      if (!exact(/^[a-z][a-z0-9_]{0,63}$/, ownData(record, 'type'))) responseInvalid();
      return record;
    });
    return Object.freeze({
      provider: 'privy',
      subject: expectedSubject,
      twitter: resolveTwitter(accounts),
      embeddedSolanaWallet: resolveEmbeddedSolanaWallet(accounts),
    });
  } catch (error) {
    if (error instanceof PrivyLinkedIdentityError && error.code === 'PRIVY_USER_RESPONSE_INVALID') throw error;
    return responseInvalid();
  }
}

/** Server-only, read-only resolver for an identity already verified by the
 * access-token verifier. It performs exactly one official SDK user-ID lookup,
 * disables retries, applies SDK and outer deadlines, and exposes no mutation or
 * signing methods.
 */
export class PrivyLinkedIdentityResolver {
  readonly #appId: string;
  readonly #timeoutMs: number;
  readonly #reader: PrivyUserByIdReader;
  readonly #protectedRead: BoundedProviderRead<PrivyLinkedIdentityResolution>;

  constructor(options: PrivyLinkedIdentityResolverOptions) {
    let appId: string;
    let timeoutMs: number;
    let reader: PrivyUserByIdReader;
    let protectedRead: BoundedProviderRead<PrivyLinkedIdentityResolution>;
    try {
      if (!isPracticeAppId(options.appId) ||
          !exact(/^[\x21-\x7e]{1,4096}$/, options.appSecret) ||
          options.fetch !== undefined && typeof options.fetch !== 'function' ||
          options.clientFactory !== undefined && typeof options.clientFactory !== 'function' ||
          options.now !== undefined && typeof options.now !== 'function') {
        configurationInvalid();
      }
      timeoutMs = options.timeoutMs ?? defaultTimeoutMs;
      if (!Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > maxTimeoutMs) {
        configurationInvalid();
      }
      const configuration: PrivyUserReaderFactoryConfiguration = Object.freeze({
        appId: options.appId,
        appSecret: options.appSecret,
        apiUrl: privyApiUrl,
        timeoutMs,
        maxRetries: 0,
        ...(options.fetch === undefined ? {} : {fetch: options.fetch}),
      });
      reader = (options.clientFactory ?? createOfficialReader)(configuration);
      if (reader === null || typeof reader !== 'object' || typeof reader.getById !== 'function') {
        configurationInvalid();
      }
      protectedRead = new BoundedProviderRead({
        now: options.now ?? Date.now,
        cacheTtlMs: options.cacheTtlMs ?? defaultCacheTtlMs,
        rateLimitWindowMs: options.rateLimitWindowMs ?? defaultRateLimitWindowMs,
        perKeyLimit: options.perSubjectLimit ?? defaultPerSubjectLimit,
        globalLimit: options.globalLimit ?? defaultGlobalLimit,
        maxTrackedKeys: options.maxTrackedSubjects ?? defaultMaxTrackedSubjects,
        maxCacheEntries: options.maxCachedSubjects ?? defaultMaxCachedSubjects,
        maxConcurrentReads: options.maxConcurrentReads ?? defaultMaxConcurrentReads,
      }, {
        configurationInvalid: () => new PrivyLinkedIdentityError('PRIVY_LINKED_IDENTITIES_NOT_CONFIGURED'),
        rateLimited: () => new PrivyLinkedIdentityError('PRIVY_USER_RATE_LIMITED'),
      });
      appId = options.appId;
    } catch {
      configurationInvalid();
    }
    this.#appId = appId;
    this.#timeoutMs = timeoutMs;
    this.#reader = reader;
    this.#protectedRead = protectedRead;
  }

  async #load(subject: string): Promise<PrivyLinkedIdentityResolution> {
    const controller = new AbortController();
    const deadlineError = new PrivyLinkedIdentityError('PRIVY_USER_TIMEOUT');
    let rejectDeadline: (error: PrivyLinkedIdentityError) => void = () => {};
    const deadline = new Promise<never>((_resolve, reject) => { rejectDeadline = reject; });
    const timer = setTimeout(() => {
      controller.abort();
      rejectDeadline(deadlineError);
    }, this.#timeoutMs);
    timer.unref();
    try {
      const user = await Promise.race([
        this.#reader.getById(subject, {
          signal: controller.signal,
          timeoutMs: this.#timeoutMs,
          maxRetries: 0,
        }),
        deadline,
      ]);
      return parsePrivyLinkedIdentities(user, subject);
    } catch (error) {
      if (error === deadlineError || controller.signal.aborted) throw deadlineError;
      if (error instanceof PrivyLinkedIdentityError && error.code === 'PRIVY_USER_RESPONSE_INVALID') throw error;
      // Provider errors can contain request headers, user data or credentials.
      // Never attach them as a cause or include their text in the public error.
      throw new PrivyLinkedIdentityError('PRIVY_USER_UNAVAILABLE');
    } finally {
      clearTimeout(timer);
      controller.abort();
    }
  }

  #verifiedIdentity(identity: PracticeIdentity): PracticeIdentity {
    let verified: PracticeIdentity;
    try {
      verified = parsePracticeIdentity(identity);
    } catch {
      throw new PrivyLinkedIdentityError('PRIVY_VERIFIED_IDENTITY_INVALID');
    }
    if (verified.appId !== this.#appId) {
      throw new PrivyLinkedIdentityError('PRIVY_VERIFIED_IDENTITY_INVALID');
    }
    return verified;
  }

  async resolve(identity: PracticeIdentity): Promise<PrivyLinkedIdentityResolution> {
    const verified = this.#verifiedIdentity(identity);
    return this.#protectedRead.read(verified.subject, verified.subject,
      async () => this.#load(verified.subject));
  }

  async resolveFresh(identity: PracticeIdentity): Promise<PrivyLinkedIdentityResolution> {
    const verified = this.#verifiedIdentity(identity);
    return this.#protectedRead.readFresh(verified.subject, verified.subject, async () => this.#load(verified.subject));
  }
}

/** Explicit environment composition. A fully absent pair leaves the optional
 * capability disabled; any partial or malformed pair fails closed.
 */
export function readPrivyLinkedIdentityResolver(
  env: Readonly<Record<string, string | undefined>>,
  overrides: Readonly<Pick<PrivyLinkedIdentityResolverOptions, 'timeoutMs' | 'fetch' | 'clientFactory' |
    'cacheTtlMs' | 'rateLimitWindowMs' | 'perSubjectLimit' | 'globalLimit' |
    'maxTrackedSubjects' | 'maxCachedSubjects' | 'maxConcurrentReads' | 'now'>> = {},
): PrivyLinkedIdentityResolver | undefined {
  const appId = env['PRIVY_APP_ID'];
  const appSecret = env['PRIVY_APP_SECRET'];
  if ((appId === undefined || appId === '') && (appSecret === undefined || appSecret === '')) return undefined;
  if (appId === undefined || appId === '' || appSecret === undefined || appSecret === '') configurationInvalid();
  return new PrivyLinkedIdentityResolver({appId, appSecret, ...overrides});
}
