/** Server-only public profile resolution. Never authenticates a person or proves
 * ownership of a handle. Handles can change: a later claim must independently
 * match its verified X subject to this ID, not to this display username.
 * https://docs.x.com/x-api/users/get-user-by-username
 * https://docs.x.com/fundamentals/authentication/oauth-2-0/application-only
 */
export interface XPublicProfile {
  readonly provider: 'x';
  readonly id: string;
  readonly username: string;
  readonly name: string;
  readonly lookedUpAt: string;
  readonly ownershipVerified: false;
}
export interface XProfileResolver { lookup(handle: string): Promise<XPublicProfile> }

export type XProfileLookupErrorCode =
  | 'X_LOOKUP_NOT_CONFIGURED' | 'X_HANDLE_INVALID' | 'X_PROFILE_NOT_FOUND'
  | 'X_PROVIDER_AUTH_FAILED' | 'X_PROVIDER_ACCESS_DENIED'
  | 'X_PROVIDER_PAYMENT_REQUIRED' | 'X_PROVIDER_RATE_LIMITED'
  | 'X_PROVIDER_UNAVAILABLE' | 'X_RESPONSE_INVALID' | 'X_LOOKUP_TIMEOUT'
  | 'X_LOOKUP_RATE_LIMITED' | 'X_LOOKUP_BUDGET_UNAVAILABLE';

const messages: Record<XProfileLookupErrorCode, string> = {
  X_LOOKUP_NOT_CONFIGURED: 'X profile lookup is not configured.',
  X_HANDLE_INVALID: 'Enter a valid X username.',
  X_PROFILE_NOT_FOUND: 'The X profile could not be found.',
  X_PROVIDER_AUTH_FAILED: 'The X lookup credentials need attention.',
  X_PROVIDER_ACCESS_DENIED: 'The X application cannot access this lookup.',
  X_PROVIDER_PAYMENT_REQUIRED: 'The X application needs an API billing review.',
  X_PROVIDER_RATE_LIMITED: 'The X application has reached a request limit.',
  X_PROVIDER_UNAVAILABLE: 'X profile lookup is unavailable.',
  X_RESPONSE_INVALID: 'X returned an unusable profile.',
  X_LOOKUP_TIMEOUT: 'The X profile lookup took too long.',
  X_LOOKUP_RATE_LIMITED: 'Wait before looking up another X profile.',
  X_LOOKUP_BUDGET_UNAVAILABLE: 'X profile lookup is temporarily unavailable.',
};

export class XProfileLookupError extends Error {
  constructor(readonly code: XProfileLookupErrorCode) {
    super(messages[code]);
    this.name = 'XProfileLookupError';
  }
}

export interface XProfileLookupOptions {
  readonly bearerToken: string;
  readonly fetch?: typeof globalThis.fetch;
  readonly timeoutMs?: number;
  readonly now?: () => number;
}

const maxResponseBytes = 16_384;
const userPattern = /^[A-Za-z0-9_]{1,15}$/;
function exact(pattern: RegExp, value: unknown): value is string {
  return typeof value === 'string' && pattern.exec(value)?.[0] === value;
}
function invalid(): never { throw new XProfileLookupError('X_RESPONSE_INVALID'); }
function object(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) invalid();
  return value as Record<string, unknown>;
}

/** Revalidate and project an injected resolver result before it reaches HTTP. */
export function parseXPublicProfile(value: unknown, expectedUsername: string): XPublicProfile {
  const data = object(value);
  if (!exact(userPattern, expectedUsername) || data.provider !== 'x' || data.ownershipVerified !== false ||
      !exact(/^[1-9][0-9]{0,19}$/, data.id) || BigInt(data.id) > 18_446_744_073_709_551_615n ||
      !exact(userPattern, data.username) || data.username.toLowerCase() !== expectedUsername.toLowerCase() ||
      typeof data.name !== 'string' || !data.name.trim().length || [...data.name].length > 100 ||
      /[\u0000-\u001f\u007f]/.test(data.name) ||
      typeof data.lookedUpAt !== 'string' || !Number.isFinite(Date.parse(data.lookedUpAt)) ||
      new Date(data.lookedUpAt).toISOString() !== data.lookedUpAt) invalid();
  return Object.freeze({provider: 'x', id: data.id, username: data.username,
    name: data.name, lookedUpAt: data.lookedUpAt, ownershipVerified: false});
}

/** One request per lookup with no retry/backoff loop. HTTP composition lives in
 * x-profile-routes.ts and requires an existing account plus a shared budget.
 * In particular a 402 or 429 is returned immediately; no second request follows.
 */
export class XProfileLookup implements XProfileResolver {
  readonly #bearerToken: string;
  readonly #fetch: typeof globalThis.fetch;
  readonly #timeoutMs: number;
  readonly #now: () => number;

  constructor(options: XProfileLookupOptions) {
    // X tokens may include percent-encoded characters; never decode/rewrite a
    // provided token. Only a bounded, visible, whitespace-free header value fits.
    if (!exact(/^[\x21-\x7e]{1,4096}$/, options.bearerToken)) {
      throw new XProfileLookupError('X_LOOKUP_NOT_CONFIGURED');
    }
    this.#bearerToken = options.bearerToken;
    this.#fetch = options.fetch ?? globalThis.fetch;
    this.#timeoutMs = options.timeoutMs ?? 6000;
    this.#now = options.now ?? Date.now;
    if (!Number.isInteger(this.#timeoutMs) || this.#timeoutMs < 1 || this.#timeoutMs > 10_000) {
      throw new XProfileLookupError('X_LOOKUP_NOT_CONFIGURED');
    }
  }

  async lookup(handle: string): Promise<XPublicProfile> {
    if (typeof handle !== 'string') throw new XProfileLookupError('X_HANDLE_INVALID');
    const username = handle.startsWith('@') ? handle.slice(1) : handle;
    if (!exact(userPattern, username)) throw new XProfileLookupError('X_HANDLE_INVALID');
    const controller = new AbortController();
    let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
    let bodyDone = false;
    let rejectTimeout: (reason: XProfileLookupError) => void = () => {};
    const deadline = new Promise<never>((_resolve, reject) => { rejectTimeout = reject; });
    const timer = setTimeout(() => {
      controller.abort();
      rejectTimeout(new XProfileLookupError('X_LOOKUP_TIMEOUT'));
    }, this.#timeoutMs);
    try {
      // Fixed origin/path: no user-controlled URL, expansions or extra requests.
      const response = await Promise.race([
        this.#fetch(`https://api.x.com/2/users/by/username/${username}`, {
          method: 'GET',
          headers: {accept: 'application/json', authorization: `Bearer ${this.#bearerToken}`},
          redirect: 'manual',
          signal: controller.signal,
        }), deadline,
      ]);
      const statusErrors: Partial<Record<number, XProfileLookupErrorCode>> = {
        401: 'X_PROVIDER_AUTH_FAILED', 402: 'X_PROVIDER_PAYMENT_REQUIRED',
        403: 'X_PROVIDER_ACCESS_DENIED', 404: 'X_PROFILE_NOT_FOUND', 429: 'X_PROVIDER_RATE_LIMITED',
      };
      const statusError = statusErrors[response.status];
      if (statusError) throw new XProfileLookupError(statusError);
      if (response.status !== 200 || response.redirected) throw new XProfileLookupError('X_PROVIDER_UNAVAILABLE');
      if (!/^application\/json(?:\s*;|$)/i.test(response.headers.get('content-type') ?? '') || !response.body) invalid();
      const contentLength = response.headers.get('content-length');
      if (contentLength !== null && (!exact(/^\d+$/, contentLength) || Number(contentLength) > maxResponseBytes)) invalid();
      reader = response.body.getReader();
      const chunks: Uint8Array[] = [];
      let bytes = 0;
      while (true) {
        const part = await Promise.race([reader.read(), deadline]);
        if (part.done) { bodyDone = true; break; }
        bytes += part.value.byteLength;
        if (bytes > maxResponseBytes) invalid();
        chunks.push(part.value);
      }
      const payload: unknown = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(Buffer.concat(chunks)));
      const envelope = object(payload);
      // A partial/error response must not become a confirmed recipient profile.
      if ('errors' in envelope && (!Array.isArray(envelope.errors) || envelope.errors.length !== 0)) invalid();
      const data = object(envelope.data);
      if (!exact(/^[1-9][0-9]{0,19}$/, data.id) || BigInt(data.id) > 18_446_744_073_709_551_615n ||
          !exact(userPattern, data.username) || data.username.toLowerCase() !== username.toLowerCase() ||
          typeof data.name !== 'string' || data.name.trim().length === 0 ||
          [...data.name].length > 100 || /[\u0000-\u001f\u007f]/.test(data.name)) invalid();
      const now = this.#now();
      if (!Number.isSafeInteger(now) || now < 0 || now > 8_640_000_000_000_000) {
        throw new XProfileLookupError('X_LOOKUP_NOT_CONFIGURED');
      }
      return Object.freeze({provider: 'x', id: data.id, username: data.username,
        name: data.name, lookedUpAt: new Date(now).toISOString(), ownershipVerified: false});
    } catch (error) {
      if (controller.signal.aborted) throw new XProfileLookupError('X_LOOKUP_TIMEOUT');
      if (error instanceof XProfileLookupError) throw error;
      if (error instanceof SyntaxError || error instanceof TypeError && reader !== undefined) invalid();
      // Never attach a cause, response body or transport error: each can contain
      // private request headers or provider diagnostics.
      throw new XProfileLookupError('X_PROVIDER_UNAVAILABLE');
    } finally {
      clearTimeout(timer);
      controller.abort();
      if (reader && !bodyDone) void reader.cancel().catch(() => {});
    }
  }
}

/** Explicit composition only: no Keychain/file lookup or credential fallback. */
export function readXProfileLookup(env: Readonly<Record<string, string | undefined>>): XProfileLookup | undefined {
  const bearerToken = env['X_BEARER_TOKEN'];
  if (bearerToken === undefined || bearerToken === '') return undefined;
  return new XProfileLookup({bearerToken});
}
