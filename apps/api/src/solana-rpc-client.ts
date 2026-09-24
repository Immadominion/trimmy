import { randomUUID } from 'node:crypto';

/**
 * Bounded JSON-RPC transport shared by the stock-order review stages. Each
 * instance is constructed with an explicit method allowlist, so a semantics
 * reader cannot express `simulateTransaction` and a simulation boundary cannot
 * express `sendTransaction`: the method set is part of the type and is checked
 * again at call time. HTTPS only, no credentials in the URL, no redirects, one
 * total deadline per call, a hard body cap, no retries and no cache. Error
 * classes are injected so every stage keeps its own fixed error codes.
 */
export interface BoundedRpcErrorFactory<E extends Error> {
  readonly configuration: () => E;
  readonly timeout: () => E;
  readonly unavailable: () => E;
  readonly responseInvalid: () => E;
  readonly methodNotAllowed: () => E;
}

export interface BoundedRpcOptions<M extends string, E extends Error> {
  readonly rpcUrl: string;
  readonly methods: readonly M[];
  readonly errors: BoundedRpcErrorFactory<E>;
  readonly fetch?: typeof globalThis.fetch;
  readonly timeoutMs?: number;
  readonly maxBodyBytes?: number;
}

export interface BoundedRpcResult {
  readonly result: unknown;
  /** `result.context.slot` when the method returns a context envelope, else null. */
  readonly contextSlot: string | null;
  readonly apiVersion: string | null;
}

const DEFAULT_TIMEOUT_MS = 6_000;
const MAX_TIMEOUT_MS = 8_000;
const DEFAULT_MAX_BODY_BYTES = 262_144;
const MAX_MAX_BODY_BYTES = 4_194_304;

function plainRecord(value: unknown): Record<string, unknown> | null {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return null;
  const proto: unknown = Object.getPrototypeOf(value);
  if (proto !== Object.prototype && proto !== null) return null;
  return value as Record<string, unknown>;
}

function slotString(value: unknown): string | null {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= 0 ? String(value) : null;
}

export class BoundedSolanaRpc<M extends string, E extends Error> {
  readonly #url: URL;
  readonly #methods: ReadonlySet<string>;
  readonly #errors: BoundedRpcErrorFactory<E>;
  readonly #fetch: typeof globalThis.fetch;
  readonly #timeoutMs: number;
  readonly #maxBodyBytes: number;
  /** Prototype of the injected error class, so stage errors pass through untouched. */
  readonly #ownErrorPrototype: object | null;
  #requestCounter = 0;

  constructor(options: BoundedRpcOptions<M, E>) {
    const errors = options?.errors;
    if (errors === null || typeof errors !== 'object' ||
        (['configuration', 'timeout', 'unavailable', 'responseInvalid', 'methodNotAllowed'] as const)
          .some(key => typeof errors[key] !== 'function')) {
      throw new TypeError('BoundedSolanaRpc requires an error factory.');
    }
    this.#errors = errors;
    let url: URL;
    try {
      if (typeof options.rpcUrl !== 'string' || options.rpcUrl.length < 1 || options.rpcUrl.length > 2_048 ||
          /[\x00-\x20\x7f]/.test(options.rpcUrl)) {
        throw errors.configuration();
      }
      url = new URL(options.rpcUrl);
    } catch {
      throw errors.configuration();
    }
    if (url.protocol !== 'https:' || url.username !== '' || url.password !== '' || url.hash !== '') {
      throw errors.configuration();
    }
    if (!Array.isArray(options.methods) || options.methods.length < 1 || options.methods.length > 16 ||
        options.methods.some(method => typeof method !== 'string' || !/^[a-zA-Z]{3,64}$/.test(method)) ||
        (options.fetch !== undefined && typeof options.fetch !== 'function')) {
      throw errors.configuration();
    }
    const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
    const maxBodyBytes = options.maxBodyBytes ?? DEFAULT_MAX_BODY_BYTES;
    if (!Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > MAX_TIMEOUT_MS ||
        !Number.isInteger(maxBodyBytes) || maxBodyBytes < 1_024 || maxBodyBytes > MAX_MAX_BODY_BYTES) {
      throw errors.configuration();
    }
    this.#url = url;
    this.#ownErrorPrototype = Object.getPrototypeOf(errors.responseInvalid()) as object | null;
    this.#methods = new Set(options.methods);
    this.#fetch = options.fetch ?? globalThis.fetch;
    this.#timeoutMs = timeoutMs;
    this.#maxBodyBytes = maxBodyBytes;
  }

  get allowedMethods(): readonly M[] { return Object.freeze([...this.#methods]) as readonly M[]; }

  async call(method: M, params: readonly unknown[]): Promise<BoundedRpcResult> {
    if (typeof method !== 'string' || !this.#methods.has(method)) throw this.#errors.methodNotAllowed();
    if (!Array.isArray(params)) throw this.#errors.configuration();
    const id = `${++this.#requestCounter}-${randomUUID()}`;
    const controller = new AbortController();
    let timedOut = false;
    let rejectDeadline: (error: Error) => void = () => undefined;
    const deadline = new Promise<never>((_resolve, reject) => { rejectDeadline = reject; });
    const timer = setTimeout(() => {
      timedOut = true;
      controller.abort();
      rejectDeadline(this.#errors.timeout());
    }, this.#timeoutMs);
    let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
    let response: Response | undefined;
    try {
      const pending = this.#fetch(this.#url, {
        method: 'POST',
        headers: {'content-type': 'application/json', accept: 'application/json'},
        redirect: 'error',
        signal: controller.signal,
        body: JSON.stringify({jsonrpc: '2.0', id, method, params}),
      });
      void pending.then((late) => {
        if (controller.signal.aborted) void late.body?.cancel().catch(() => undefined);
      }, () => undefined);
      response = await Promise.race([pending, deadline]);
      if (!response.ok || response.redirected) throw this.#errors.unavailable();
      if (!/^application\/json(?:\s*;|$)/i.test(response.headers.get('content-type') ?? '') || !response.body) {
        throw this.#errors.responseInvalid();
      }
      const declared = response.headers.get('content-length');
      if (declared !== null && (declared.length > 20 || /^(?:0|[1-9][0-9]*)$/.exec(declared)?.[0] !== declared ||
          BigInt(declared) > BigInt(this.#maxBodyBytes))) {
        throw this.#errors.responseInvalid();
      }
      reader = response.body.getReader();
      const chunks: Uint8Array[] = [];
      let bytes = 0;
      while (true) {
        const part = await Promise.race([reader.read(), deadline]);
        if (part.done) break;
        bytes += part.value.byteLength;
        if (bytes > this.#maxBodyBytes) throw this.#errors.responseInvalid();
        chunks.push(part.value);
      }
      let payload: unknown;
      try {
        payload = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(Buffer.concat(chunks)));
      } catch {
        throw this.#errors.responseInvalid();
      }
      const envelope = plainRecord(payload);
      if (envelope === null || envelope['jsonrpc'] !== '2.0' || envelope['id'] !== id ||
          !Object.hasOwn(envelope, 'result') || Object.hasOwn(envelope, 'error')) {
        throw this.#errors.responseInvalid();
      }
      const result = envelope['result'];
      const record = plainRecord(result);
      const context = record === null ? null : plainRecord(record['context']);
      return Object.freeze({
        result,
        contextSlot: context === null ? null : slotString(context['slot']),
        apiVersion: context !== null && typeof context['apiVersion'] === 'string' && context['apiVersion'].length <= 32
          ? context['apiVersion'] : null,
      });
    } catch (error) {
      if (timedOut || controller.signal.aborted) throw this.#errors.timeout();
      if (error !== null && typeof error === 'object' && Object.getPrototypeOf(error) === this.#ownErrorPrototype) {
        throw error;
      }
      throw this.#errors.unavailable();
    } finally {
      clearTimeout(timer);
      controller.abort();
      if (reader) void reader.cancel().catch(() => undefined);
      else if (response?.body) void response.body.cancel().catch(() => undefined);
    }
  }
}
