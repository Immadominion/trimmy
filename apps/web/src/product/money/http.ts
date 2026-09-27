/**
 * One bounded JSON request for the money clients. No cookies, no redirects, no
 * referrer, a hard deadline and a byte cap. Response bodies are never turned
 * into user-visible text; callers read only known codes.
 */
import {normalizePracticeApiBase} from '../practice-client.js';

export class MoneyHttpError extends Error {
  constructor(readonly code: 'TIMEOUT' | 'CANCELLED' | 'NETWORK' | 'TOO_LARGE' | 'INVALID' | 'REDIRECT') {
    super(code); this.name = 'MoneyHttpError';
  }
}

export interface MoneyRequest {
  readonly method?: 'GET' | 'POST';
  readonly headers?: Record<string, string>;
  readonly body?: unknown;
  /** Fetch cache mode. 'no-store' makes browsers send `Cache-Control: no-cache` themselves. */
  readonly cache?: RequestCache;
  readonly timeoutMs: number;
  readonly maxBytes: number;
  readonly signal?: AbortSignal | undefined;
}
export interface MoneyResponse {readonly status: number; readonly body: unknown}

export function moneyApiBase(value: string): string {return normalizePracticeApiBase(value);}

export async function requestJson(fetcher: typeof fetch, url: string, request: MoneyRequest): Promise<MoneyResponse> {
  if (request.signal?.aborted) throw new MoneyHttpError('CANCELLED');
  const controller = new AbortController();
  let failure: MoneyHttpError | null = null;
  const stop = (code: MoneyHttpError['code']) => {if (!failure) {failure = new MoneyHttpError(code); controller.abort();}};
  const cancel = () => stop('CANCELLED');
  request.signal?.addEventListener('abort', cancel, {once: true});
  const timer = setTimeout(() => stop('TIMEOUT'), request.timeoutMs);
  let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
  try {
    const headers: Record<string, string> = {accept: 'application/json', ...request.headers};
    if (request.body !== undefined) headers['content-type'] = 'application/json';
    let response: Response;
    try {
      response = await fetcher(url, {method: request.method ?? 'GET', headers, credentials: 'omit', cache: request.cache ?? 'no-store',
        redirect: 'error', referrerPolicy: 'no-referrer', signal: controller.signal,
        ...(request.body === undefined ? {} : {body: JSON.stringify(request.body)})});
    } catch {throw failure ?? new MoneyHttpError('NETWORK');}
    if (failure) throw failure;
    if (response.redirected || response.status >= 300 && response.status < 400) throw new MoneyHttpError('REDIRECT');
    const declared = response.headers.get('content-length');
    if (declared !== null && (!/^\d+$/.test(declared) || Number(declared) > request.maxBytes)) throw new MoneyHttpError('TOO_LARGE');
    const type = response.headers.get('content-type')?.toLowerCase().split(';')[0]?.trim();
    if (!response.body) throw new MoneyHttpError('INVALID');
    reader = response.body.getReader();
    const chunks: Uint8Array[] = [];
    let length = 0;
    for (;;) {
      let next: ReadableStreamReadResult<Uint8Array>;
      try {next = await reader.read();} catch {throw failure ?? new MoneyHttpError('NETWORK');}
      if (failure) throw failure;
      if (next.done) break;
      length += next.value.byteLength;
      if (length > request.maxBytes) throw new MoneyHttpError('TOO_LARGE');
      chunks.push(next.value);
    }
    reader = undefined;
    const bytes = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) {bytes.set(chunk, offset); offset += chunk.byteLength;}
    let body: unknown = null;
    if (length > 0) {
      if (type !== 'application/json') throw new MoneyHttpError('INVALID');
      try {body = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes));} catch {throw new MoneyHttpError('INVALID');}
    }
    return {status: response.status, body};
  } catch (error) {
    controller.abort();
    void reader?.cancel().catch(() => {});
    throw error instanceof MoneyHttpError ? error : failure ?? new MoneyHttpError('NETWORK');
  } finally {
    clearTimeout(timer);
    request.signal?.removeEventListener('abort', cancel);
  }
}

/** Reads `{code}` (trading routes) or `{error: {code}}` (account routes). */
export function responseCode(body: unknown): string | null {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) return null;
  const data = body as Record<string, unknown>;
  const direct = data['code'];
  if (typeof direct === 'string' && /^[A-Z][A-Z0-9_]{1,80}$/.test(direct)) return direct;
  const nested = data['error'];
  if (nested && typeof nested === 'object' && !Array.isArray(nested)) {
    const code = (nested as Record<string, unknown>)['code'];
    if (typeof code === 'string' && /^[A-Z][A-Z0-9_]{1,80}$/.test(code)) return code;
  }
  return null;
}

/** A bearer bound to the signed-in identity, or null once that identity is gone. */
export type BearerSource = () => Promise<string | null>;
export function validBearer(token: string | null): token is string {
  return token !== null && token.length <= 8192 && /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(token);
}
