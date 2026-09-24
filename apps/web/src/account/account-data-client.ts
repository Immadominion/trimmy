import {
  AccountDataError,
  canonicalAccountId,
  parseAccountContext,
  parseAccountHoldings,
  type AccountContextSnapshot,
  type AccountDataErrorCode,
  type AccountHoldingsSnapshot,
} from './account-data-models.js';
import {validPrivySubject} from './token-binding.js';

export interface AccountDataReadOptions { readonly signal?: AbortSignal }

export interface AccountDataClientOptions {
  readonly apiOrigin: string;
  readonly subject: string;
  /** Canonical UUID returned by the already-established Trimmy session. */
  readonly accountId: string;
  readonly currentSubject: () => string | null;
  /** Must obtain a fresh SDK token for the exact subject supplied. */
  readonly accessToken: (expectedSubject: string) => Promise<string | null>;
  readonly fetch?: typeof globalThis.fetch;
  readonly timeoutMs?: number;
  readonly allowLoopbackForTests?: boolean;
}

type Endpoint = 'context' | 'holdings';
const MAX_RESPONSE_BYTES = 65_536;
type EndpointErrors = Readonly<Partial<Record<number, readonly AccountDataErrorCode[]>>>;
const ERROR_CODES: Readonly<Record<Endpoint, EndpointErrors>> = Object.freeze({
    context: Object.freeze({
      400: Object.freeze(['ACCOUNT_CONTEXT_INVALID_REQUEST', 'INVALID_REQUEST']),
      401: Object.freeze(['ACCOUNT_CONTEXT_UNAUTHENTICATED']),
      403: Object.freeze(['BROWSER_ORIGIN_DENIED', 'BROWSER_PREFLIGHT_DENIED']),
      404: Object.freeze(['NOT_FOUND']),
      413: Object.freeze(['PAYLOAD_TOO_LARGE']),
      415: Object.freeze(['UNSUPPORTED_MEDIA_TYPE']),
      429: Object.freeze(['PRIVY_USER_RATE_LIMITED']),
      500: Object.freeze(['INTERNAL_ERROR']),
      502: Object.freeze(['PRIVY_USER_RESPONSE_INVALID', 'PRIVY_USER_UNAVAILABLE']),
      503: Object.freeze(['ACCOUNT_CONTEXT_UNAVAILABLE', 'PRIVY_LINKED_IDENTITIES_NOT_CONFIGURED',
        'PRIVY_VERIFIED_IDENTITY_INVALID']),
      504: Object.freeze(['PRIVY_USER_TIMEOUT']),
    }) as EndpointErrors,
    holdings: Object.freeze({
      400: Object.freeze(['ACCOUNT_HOLDINGS_INVALID_REQUEST', 'INVALID_REQUEST']),
      401: Object.freeze(['ACCOUNT_HOLDINGS_UNAUTHENTICATED']),
      403: Object.freeze(['BROWSER_ORIGIN_DENIED', 'BROWSER_PREFLIGHT_DENIED']),
      404: Object.freeze(['NOT_FOUND']),
      409: Object.freeze(['ACCOUNT_HOLDINGS_WALLET_MISSING', 'ACCOUNT_HOLDINGS_WALLET_AMBIGUOUS']),
      413: Object.freeze(['PAYLOAD_TOO_LARGE']),
      415: Object.freeze(['UNSUPPORTED_MEDIA_TYPE']),
      429: Object.freeze(['PRIVY_USER_RATE_LIMITED', 'STOCK_HOLDINGS_RATE_LIMITED']),
      500: Object.freeze(['INTERNAL_ERROR']),
      502: Object.freeze(['PRIVY_USER_RESPONSE_INVALID', 'PRIVY_USER_UNAVAILABLE',
        'STOCK_HOLDINGS_OWNER_INVALID', 'STOCK_HOLDINGS_OWNER_UNVERIFIED',
        'STOCK_HOLDINGS_RPC_UNAVAILABLE', 'STOCK_HOLDINGS_RPC_RESPONSE_INVALID']),
      503: Object.freeze(['ACCOUNT_HOLDINGS_UNAVAILABLE', 'PRIVY_LINKED_IDENTITIES_NOT_CONFIGURED',
        'PRIVY_VERIFIED_IDENTITY_INVALID', 'STOCK_HOLDINGS_CONFIGURATION_INVALID', 'STOCK_HOLDINGS_WRONG_NETWORK']),
      504: Object.freeze(['PRIVY_USER_TIMEOUT', 'STOCK_HOLDINGS_RPC_TIMEOUT']),
    }) as EndpointErrors,
  });

/**
 * Read-only account transport bound to one live Privy subject.
 *
 * There is deliberately no generic request method, cache, retry, wallet input,
 * transaction builder, signer, simulator or broadcaster on this class.
 */
export class AccountDataClient {
  readonly subject: string;
  readonly accountId: string;
  readonly #origin: string;
  readonly #fetch: typeof globalThis.fetch;
  readonly #currentSubject: () => string | null;
  readonly #accessToken: (expectedSubject: string) => Promise<string | null>;
  readonly #timeoutMs: number;
  readonly #active = new Set<(reason: AccountDataErrorCode) => void>();
  #closed = false;
  #subjectInvalidated = false;

  constructor(options: AccountDataClientOptions) {
    const timeoutMs = options.timeoutMs ?? 8_000;
    if (!validPrivySubject(options.subject) || !Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 15_000) {
      throw new AccountDataError('ACCOUNT_DATA_INVALID_CONFIGURATION');
    }
    let accountId: string;
    try { accountId = canonicalAccountId(options.accountId); }
    catch { throw new AccountDataError('ACCOUNT_DATA_INVALID_CONFIGURATION'); }
    let origin: URL;
    try { origin = new URL(options.apiOrigin); }
    catch { throw new AccountDataError('ACCOUNT_DATA_INVALID_CONFIGURATION'); }
    const loopback = ['localhost', '127.0.0.1', '[::1]'].includes(origin.hostname);
    if ((options.apiOrigin !== origin.origin && options.apiOrigin !== `${origin.origin}/`) || origin.username ||
        origin.password || origin.pathname !== '/' || origin.search || origin.hash || origin.port === '0' ||
        (origin.protocol !== 'https:' && !(options.allowLoopbackForTests && loopback && origin.protocol === 'http:'))) {
      throw new AccountDataError('ACCOUNT_DATA_INVALID_CONFIGURATION');
    }
    this.subject = options.subject;
    this.accountId = accountId;
    this.#origin = origin.origin;
    this.#fetch = options.fetch ?? globalThis.fetch;
    this.#currentSubject = options.currentSubject;
    this.#accessToken = options.accessToken;
    this.#timeoutMs = timeoutMs;
  }

  readContext(options: AccountDataReadOptions = {}): Promise<AccountContextSnapshot> {
    return this.#get('/v1/account/context', 'context', options.signal,
      value => parseAccountContext(value, this.accountId));
  }

  readHoldings(options: AccountDataReadOptions = {}): Promise<AccountHoldingsSnapshot> {
    return this.#get('/v1/account/holdings', 'holdings', options.signal,
      value => parseAccountHoldings(value, this.accountId));
  }

  /** Permanently invalidates this client if its owning Privy session changes. */
  observeSubject(activeSubject: string | null): void {
    if (this.#closed || this.#subjectInvalidated || activeSubject === this.subject) return;
    this.#subjectInvalidated = true;
    for (const stop of [...this.#active]) stop('ACCOUNT_DATA_ACCOUNT_CHANGED');
  }

  cancelPending(): void {
    for (const stop of [...this.#active]) stop('ACCOUNT_DATA_CANCELLED');
  }

  close(): void {
    if (this.#closed) return;
    this.#closed = true;
    for (const stop of [...this.#active]) stop('ACCOUNT_DATA_CLOSED');
  }

  #check(signal?: AbortSignal): void {
    if (this.#closed) throw new AccountDataError('ACCOUNT_DATA_CLOSED');
    let current: string | null;
    try { current = this.#currentSubject(); }
    catch { current = null; }
    if (this.#subjectInvalidated || current !== this.subject) {
      this.#subjectInvalidated = true;
      throw new AccountDataError('ACCOUNT_DATA_ACCOUNT_CHANGED');
    }
    if (signal?.aborted) throw new AccountDataError('ACCOUNT_DATA_CANCELLED');
  }

  async #get<T>(path: string, endpoint: Endpoint, signal: AbortSignal | undefined,
    parse: (value: unknown) => T): Promise<T> {
    this.#check(signal);
    const controller = new AbortController();
    let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
    let body: ReadableStream<Uint8Array> | null | undefined;
    let failure: AccountDataError | undefined;
    let rejectStopped!: (error: AccountDataError) => void;
    const stopped = new Promise<never>((_resolve, reject) => { rejectStopped = reject; });
    const stop = (reason: AccountDataErrorCode): void => {
      if (failure) return;
      failure = new AccountDataError(reason);
      controller.abort();
      void reader?.cancel().catch(() => {});
      rejectStopped(failure);
    };
    const externalCancel = (): void => stop('ACCOUNT_DATA_CANCELLED');
    this.#active.add(stop);
    signal?.addEventListener('abort', externalCancel, {once: true});
    const timer = setTimeout(() => stop('ACCOUNT_DATA_TIMEOUT'), this.#timeoutMs);

    const perform = async (): Promise<T> => {
      try {
        let token: string | null;
        try { token = await this.#accessToken(this.subject); }
        catch {
          if (failure) throw failure;
          this.#check(signal);
          throw new AccountDataError('ACCOUNT_DATA_TOKEN_UNAVAILABLE');
        }
        if (failure) throw failure;
        this.#check(signal);
        if (token === null || token.length > 8_192 ||
            /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/u.exec(token)?.[0] !== token) {
          throw new AccountDataError('ACCOUNT_DATA_TOKEN_UNAVAILABLE');
        }
        const url = new URL(path, this.#origin);
        const response = await this.#fetch(url, {
          method: 'GET', headers: {accept: 'application/json', authorization: `Bearer ${token}`},
          credentials: 'omit', cache: 'no-store', redirect: 'error', referrerPolicy: 'no-referrer',
          signal: controller.signal,
        });
        if (failure) { void response.body?.cancel().catch(() => {}); throw failure; }
        this.#check(signal);
        body = response.body;
        if (response.redirected || response.type === 'opaqueredirect' ||
            response.status >= 300 && response.status < 400 || response.url && response.url !== url.href) {
          throw new AccountDataError('ACCOUNT_DATA_REDIRECT_REJECTED');
        }
        const declared = response.headers.get('content-length');
        if (declared !== null && (!/^\d+$/u.test(declared) || Number(declared) > MAX_RESPONSE_BYTES)) {
          throw new AccountDataError('ACCOUNT_DATA_RESPONSE_TOO_LARGE');
        }
        const contentType = response.headers.get('content-type')?.toLowerCase().split(';').map(part => part.trim());
        if (!contentType || contentType.length > 2 || contentType[0] !== 'application/json' ||
            contentType.slice(1).some(part => part !== 'charset=utf-8' && part !== 'charset="utf-8"') || !body) {
          throw new AccountDataError('ACCOUNT_DATA_RESPONSE_INVALID');
        }
        reader = body.getReader();
        const chunks: Uint8Array[] = [];
        let length = 0;
        while (true) {
          const next = await reader.read();
          if (failure) throw failure;
          if (next.done) break;
          length += next.value.byteLength;
          if (length > MAX_RESPONSE_BYTES) throw new AccountDataError('ACCOUNT_DATA_RESPONSE_TOO_LARGE');
          chunks.push(next.value);
        }
        reader.releaseLock();
        reader = undefined;
        this.#check(signal);
        const bytes = new Uint8Array(length);
        let offset = 0;
        for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
        let value: unknown;
        try { value = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes)); }
        catch { throw new AccountDataError('ACCOUNT_DATA_RESPONSE_INVALID'); }
        if (response.status !== 200) serverFailure(endpoint, response.status, value);
        const result = parse(value);
        this.#check(signal);
        return result;
      } catch (error) {
        controller.abort();
        if (reader) void reader.cancel().catch(() => {});
        else void body?.cancel().catch(() => {});
        if (failure) throw failure;
        if (error instanceof AccountDataError) throw error;
        throw new AccountDataError('ACCOUNT_DATA_NETWORK_ERROR');
      }
    };

    try { return await Promise.race([perform(), stopped]); }
    finally {
      clearTimeout(timer);
      signal?.removeEventListener('abort', externalCancel);
      this.#active.delete(stop);
    }
  }
}

function errorCode(value: unknown): string | undefined {
  if (value === null || typeof value !== 'object' || Array.isArray(value) ||
      ![Object.prototype, null].includes(Object.getPrototypeOf(value)) || Reflect.ownKeys(value).length !== 1) return undefined;
  const envelopeDescriptor = Object.getOwnPropertyDescriptor(value, 'error');
  const inner = envelopeDescriptor?.enumerable && Object.hasOwn(envelopeDescriptor, 'value')
    ? envelopeDescriptor.value : undefined;
  if (inner === null || typeof inner !== 'object' || Array.isArray(inner) ||
      ![Object.prototype, null].includes(Object.getPrototypeOf(inner)) || Reflect.ownKeys(inner).length !== 3) return undefined;
  const descriptors = Object.getOwnPropertyDescriptors(inner);
  if (!['code', 'message', 'requestId'].every(key => descriptors[key]?.enumerable &&
      Object.hasOwn(descriptors[key]!, 'value'))) return undefined;
  const code = descriptors['code']!.value as unknown;
  const message = descriptors['message']!.value as unknown;
  const requestId = descriptors['requestId']!.value as unknown;
  if (typeof code !== 'string' || typeof message !== 'string' || message.length > 1_024 ||
      typeof requestId !== 'string' || requestId.length < 1 || requestId.length > 128) return undefined;
  return code;
}

function serverFailure(endpoint: Endpoint, status: number, value: unknown): never {
  const code = errorCode(value);
  if (code && ERROR_CODES[endpoint][status]?.includes(code as AccountDataErrorCode)) {
    throw new AccountDataError(code as AccountDataErrorCode);
  }
  throw new AccountDataError('ACCOUNT_DATA_RESPONSE_INVALID');
}
