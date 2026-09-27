import {PracticeError, normalizePracticeApiBase, parseGuest, parsePracticeSubject} from './practice-client.js';
import type {GuestCredential, PracticeAccountProof} from './practice-client.js';

/**
 * Bounded JSON client for the social, settings and Career action routes that the
 * web adds beside PracticeClient. Same rules: an explicit HTTPS origin or the
 * same-origin /api relay, no cookies, no redirects, a size cap, and a strict
 * `{error: {code}}` envelope. Only Authorization and Content-Type are sent,
 * which is all a browser preflight on the API allows.
 */
export type ProductIdentity = GuestCredential | PracticeAccountProof;
export interface ProductRequest<T> {
  readonly path: string; readonly method?: 'GET' | 'POST' | 'PUT' | undefined;
  readonly query?: Readonly<Record<string, string | undefined>> | undefined; readonly body?: unknown;
  /** Omit for public reads. An account proof sends a fresh bearer; a guest sends its guest token. */
  readonly identity?: ProductIdentity | null | undefined;
  readonly parse: (value: unknown) => T; readonly accept?: string | undefined;
  readonly expectedStatus?: readonly number[] | undefined; readonly maxBytes?: number | undefined; readonly signal?: AbortSignal | undefined;
}
export interface ProductApiOptions {readonly baseUrl: string; readonly fetch?: typeof globalThis.fetch; readonly timeoutMs?: number}

function invalid(): never {throw new PracticeError('PRODUCT_RESPONSE_INVALID', 'The server returned an invalid response.');}
export class ProductApiClient {
  readonly apiBase: string;
  readonly #fetch: typeof globalThis.fetch;
  readonly #timeoutMs: number;
  constructor(options: ProductApiOptions) {
    this.apiBase = normalizePracticeApiBase(options.baseUrl);
    this.#fetch = options.fetch ?? globalThis.fetch.bind(globalThis);
    this.#timeoutMs = options.timeoutMs ?? 15_000;
    if (!Number.isSafeInteger(this.#timeoutMs) || this.#timeoutMs < 1 || this.#timeoutMs > 120_000) throw new PracticeError('PRACTICE_CONFIG_INVALID', 'Invalid request timeout.');
  }
  async request<T>(options: ProductRequest<T>): Promise<T> {
    const identity = options.identity ?? null;
    const account = identity && 'subject' in identity ? identity : null;
    if (options.signal?.aborted || account?.signal.aborted) throw new PracticeError('PRACTICE_ABORTED', 'Request cancelled.');
    if (!/^\/v1\/[a-z0-9/-]+$/u.test(options.path) || options.path.includes('//')) throw new PracticeError('PRODUCT_REQUEST_INVALID', 'Invalid request.');
    const search = new URLSearchParams();
    for (const [key, value] of Object.entries(options.query ?? {})) if (value !== undefined) search.set(key, value);
    const url = `${this.apiBase}${options.path}${search.size ? `?${search}` : ''}`;
    const controller = new AbortController();
    let stop!: (reason: PracticeError) => void;
    const interrupted = new Promise<never>((_resolve, reject) => {stop = reject;});
    const abort = () => {controller.abort(); stop(new PracticeError('PRACTICE_ABORTED', 'Request cancelled.'));};
    options.signal?.addEventListener('abort', abort, {once: true});
    account?.signal.addEventListener('abort', abort, {once: true});
    const timer = setTimeout(() => {controller.abort(); stop(new PracticeError('PRACTICE_TIMEOUT', 'The request timed out. Try again.'));}, this.#timeoutMs);
    const accept = options.accept ?? 'application/json';
    const task = async (): Promise<T> => {
      const headers: Record<string, string> = {Accept: accept};
      if (options.body !== undefined) headers['Content-Type'] = 'application/json';
      if (account) {
        parsePracticeSubject(account.subject);
        const token = await account.freshAccessToken();
        if (controller.signal.aborted) throw new PracticeError('PRACTICE_ABORTED', 'Request cancelled.');
        if (typeof token !== 'string' || !/^[A-Za-z0-9._~-]{1,16384}$/u.test(token)) throw new PracticeError('PRACTICE_ACCOUNT_REQUIRED', 'Sign in again to continue.', 401);
        headers['Authorization'] = `Bearer ${token}`;
      } else if (identity) headers['Authorization'] = `Guest ${parseGuest(identity).token}`;
      const response = await this.#fetch(url, {method: options.method ?? 'GET', headers,
        ...(options.body === undefined ? {} : {body: JSON.stringify(options.body)}), signal: controller.signal,
        credentials: 'omit', cache: 'no-store', redirect: 'error', referrerPolicy: 'no-referrer'});
      if (response.redirected) invalid();
      const media = response.headers.get('content-type')?.split(';')[0]?.trim().toLowerCase();
      if (media !== (response.ok ? accept : 'application/json')) invalid();
      const reader = response.body?.getReader(); if (!reader) invalid();
      const limit = options.maxBytes ?? 262_144, chunks: Uint8Array[] = []; let size = 0;
      try {
        while (true) {
          const next = await reader.read(); if (next.done) break;
          size += next.value.byteLength; if (size > limit) {void reader.cancel().catch(() => undefined); invalid();}
          chunks.push(next.value);
        }
      } finally {reader.releaseLock();}
      const bytes = new Uint8Array(size); let offset = 0;
      for (const chunk of chunks) {bytes.set(chunk, offset); offset += chunk.length;}
      let json: unknown; try {json = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes));} catch {return invalid();}
      if (!response.ok) {
        const envelope = json && typeof json === 'object' && !Array.isArray(json) ? (json as Record<string, unknown>)['error'] : null;
        const code = envelope && typeof envelope === 'object' ? (envelope as Record<string, unknown>)['code'] : null;
        if (typeof code !== 'string' || !/^[A-Z][A-Z0-9_]{1,99}$/u.test(code)) invalid();
        const retry = response.headers.get('retry-after');
        throw new PracticeError(code, 'The request could not be completed.', response.status, retry && /^[0-9]{1,6}$/u.test(retry) ? Number(retry) : null);
      }
      if (!(options.expectedStatus ?? [200]).includes(response.status)) invalid();
      try {return options.parse(json);} catch (error) {if (error instanceof PracticeError) throw error; return invalid();}
    };
    try {return await Promise.race([task(), interrupted]);}
    catch (error) {if (error instanceof PracticeError) throw error; throw new PracticeError('PRACTICE_NETWORK_ERROR', 'Could not reach Trimmy. Try again.');}
    finally {clearTimeout(timer); options.signal?.removeEventListener('abort', abort); account?.signal.removeEventListener('abort', abort); controller.abort();}
  }
}

/** Small strict readers shared by the feature parsers. */
export const read = {
  record(value: unknown, keys?: readonly string[]): Record<string, unknown> {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) invalid();
    const record = value as Record<string, unknown>;
    if (keys && (Object.keys(record).length !== keys.length || keys.some(key => !Object.hasOwn(record, key)))) invalid();
    return record;
  },
  string(value: unknown, max = 300, min = 1): string {
    if (typeof value !== 'string' || [...value].length < min || [...value].length > max || /[\u0000-\u001f\u007f]/u.test(value)) invalid();
    return value;
  },
  integer(value: unknown, min = 0, max = Number.MAX_SAFE_INTEGER): number {
    if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < min || value > max) invalid();
    return value;
  },
  boolean(value: unknown): boolean {if (typeof value !== 'boolean') invalid(); return value;},
  oneOf<const T extends readonly string[]>(value: unknown, choices: T): T[number] {if (typeof value !== 'string' || !choices.includes(value)) invalid(); return value;},
  uuid(value: unknown): string {
    if (typeof value !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu.test(value)) invalid();
    return value.toLowerCase();
  },
  instant(value: unknown): string {
    if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/u.test(value) || !Number.isFinite(Date.parse(value))) invalid();
    return value;
  },
  day(value: unknown): string {if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/u.test(value) || !Number.isFinite(Date.parse(`${value}T00:00:00Z`))) invalid(); return value;},
  array(value: unknown, max = 500): unknown[] {if (!Array.isArray(value) || value.length > max) invalid(); return value;},
  nullable<T>(value: unknown, parse: (value: unknown) => T): T | null {return value === null ? null : parse(value);},
  invalid,
};
