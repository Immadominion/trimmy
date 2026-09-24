import {BoundedProviderRead} from './bounded-provider-read.js';
import type {BoundedProviderReadConfiguration} from './bounded-provider-read.js';

/**
 * Read-only Tokens.xyz mint history. The contract was observed against AAPLx on
 * 14 September 2026; it is market-data evidence, never an execution authority.
 * Official endpoint semantics: https://docs.tokens.xyz/v1/endpoints/asset-by-id
 */
export const STOCK_HISTORY_ASSET = Object.freeze({
  assetId: 'apple',
  variantMint: 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp',
});
export type StockHistoryInterval = '1H' | '4H' | '1D';
export interface StockHistoryInput {
  readonly assetId: typeof STOCK_HISTORY_ASSET.assetId;
  readonly variantMint: typeof STOCK_HISTORY_ASSET.variantMint;
  readonly interval: StockHistoryInterval;
  readonly fromUnixSeconds: string;
  readonly toUnixSeconds: string;
}
export interface StockHistoryCandle {
  readonly startUnixSeconds: string;
  /** Exact provider JSON-number lexemes. Units are not declared in the public v1 docs. */
  readonly openRaw: string;
  readonly highRaw: string;
  readonly lowRaw: string;
  readonly closeRaw: string;
  readonly volumeRaw: string;
}
export interface StockHistoryPage {
  readonly schemaVersion: 1;
  readonly provider: 'tokens-xyz-v1';
  readonly providerContract: 'observed_not_execution_qualified';
  readonly historyKind: 'solana_mint_variant';
  readonly canonicalEquityHistory: false;
  readonly assetId: typeof STOCK_HISTORY_ASSET.assetId;
  readonly variantMint: typeof STOCK_HISTORY_ASSET.variantMint;
  readonly interval: StockHistoryInterval;
  readonly fromUnixSeconds: string;
  readonly toUnixSeconds: string;
  readonly candles: readonly StockHistoryCandle[];
  readonly dataStatus: 'observed' | 'empty_provider_cache_or_no_trades';
  readonly numericEncoding: 'exact_provider_json_number_lexemes';
  readonly priceUnit: 'provider_not_declared';
  readonly volumeUnit: 'provider_not_declared';
  readonly provenance: {
    readonly sourceUrl: string;
    readonly requestedAt: string;
    readonly observedAt: string;
    readonly providerAsOf: null;
    readonly providerFreshness: 'not_reported';
    readonly providerCandleSource: 'not_exposed';
    readonly refreshAfter: string;
    readonly cachedUpstreamData: true;
  };
  readonly executionEnabled: false;
  readonly eligibility: 'unverified';
}
export interface StockHistory {
  history(input: StockHistoryInput): Promise<StockHistoryPage>;
}

export type StockHistoryErrorCode = 'STOCK_HISTORY_INPUT_INVALID' | 'STOCK_HISTORY_UNAVAILABLE' |
  'STOCK_HISTORY_PROVIDER_AUTH_FAILED' | 'STOCK_HISTORY_PROVIDER_UNAVAILABLE' |
  'STOCK_HISTORY_RATE_LIMITED' | 'STOCK_HISTORY_RESPONSE_INVALID' | 'STOCK_HISTORY_TIMEOUT';
const messages: Record<StockHistoryErrorCode, string> = {
  STOCK_HISTORY_INPUT_INVALID: 'Choose a valid stock, interval and time range.',
  STOCK_HISTORY_UNAVAILABLE: 'Stock history is not configured.',
  STOCK_HISTORY_PROVIDER_AUTH_FAILED: 'The stock data provider requires a valid key with history access.',
  STOCK_HISTORY_PROVIDER_UNAVAILABLE: 'Stock history is unavailable. Try again later.',
  STOCK_HISTORY_RATE_LIMITED: 'Wait before requesting stock history again.',
  STOCK_HISTORY_RESPONSE_INVALID: 'The stock provider returned unusable history data.',
  STOCK_HISTORY_TIMEOUT: 'The stock history request took too long.',
};
export class StockHistoryError extends Error {
  constructor(readonly code: StockHistoryErrorCode) { super(messages[code]); this.name = 'StockHistoryError'; }
}
const badInput = (): never => { throw new StockHistoryError('STOCK_HISTORY_INPUT_INVALID'); };
const invalid = (): never => { throw new StockHistoryError('STOCK_HISTORY_RESPONSE_INVALID'); };
const intervals = Object.freeze({'1H': 3_600, '4H': 14_400, '1D': 86_400} as const);
const origin = 'https://api.tokens.xyz';
const maxBodyBytes = 1_048_576;
const maxWindowSeconds = 31 * 86_400;
const localCacheMs = 15_000;

class ExactJsonNumber {
  readonly kind = 'json_number' as const;
  constructor(readonly raw: string) { Object.freeze(this); }
}
interface LosslessArray extends ReadonlyArray<LosslessJson> {}
interface LosslessObject {readonly [key: string]: LosslessJson}
type LosslessJson = null | boolean | string | ExactJsonNumber | LosslessArray | LosslessObject;
const exactNumber = (raw: string): ExactJsonNumber => new ExactJsonNumber(raw);
const isObject = (value: LosslessJson): value is LosslessObject => value !== null && typeof value === 'object' &&
  !Array.isArray(value) && !(value instanceof ExactJsonNumber);
const isNumber = (value: LosslessJson | undefined): value is ExactJsonNumber =>
  value instanceof ExactJsonNumber;

/** Small bounded JSON parser which preserves every numeric token exactly. */
function parseLosslessJson(source: string): LosslessJson {
  if (Buffer.byteLength(source, 'utf8') > maxBodyBytes) invalid();
  let offset = 0, nodes = 0;
  const whitespace = (): void => { while (' \n\r\t'.includes(source[offset] ?? '\0')) offset++; };
  const value = (depth: number): LosslessJson => {
    if (++nodes > 100_000 || depth > 8) invalid();
    whitespace();
    const char = source[offset];
    if (char === '"') return string();
    if (char === '[') return array(depth + 1);
    if (char === '{') return object(depth + 1);
    for (const [literal, result] of [['true', true], ['false', false], ['null', null]] as const) {
      if (source.startsWith(literal, offset)) { offset += literal.length; return result; }
    }
    const match = /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/u.exec(source.slice(offset));
    if (!match) return invalid();
    if (match[0].length > 128) return invalid();
    offset += match[0].length;
    return exactNumber(match[0]);
  };
  const string = (): string => {
    const start = offset++;
    let escaped = false;
    while (offset < source.length) {
      const char = source[offset]; offset++;
      if (char === undefined) return invalid();
      if (escaped) { escaped = false; continue; }
      if (char === '\\') { escaped = true; continue; }
      if (char === '"') {
        let parsed: unknown;
        try { parsed = JSON.parse(source.slice(start, offset)); } catch { invalid(); }
        if (typeof parsed !== 'string' || parsed.length > 4_096) return invalid();
        return parsed;
      }
      if (char < ' ') invalid();
    }
    return invalid();
  };
  const array = (depth: number): readonly LosslessJson[] => {
    offset++; whitespace(); const result: LosslessJson[] = [];
    if (source[offset] === ']') { offset++; return Object.freeze(result); }
    for (;;) {
      if (result.length >= 20_000) invalid();
      result.push(value(depth)); whitespace();
      if (source[offset] === ']') { offset++; return Object.freeze(result); }
      if (source[offset++] !== ',') invalid();
    }
  };
  const object = (depth: number): LosslessObject => {
    offset++; whitespace(); const result: Record<string, LosslessJson> = Object.create(null) as Record<string, LosslessJson>;
    let count = 0;
    if (source[offset] === '}') { offset++; return Object.freeze(result); }
    for (;;) {
      whitespace(); if (source[offset] !== '"') invalid();
      const key = string(); whitespace();
      if (key.length > 64 || Object.hasOwn(result, key) || source[offset++] !== ':') invalid();
      if (++count > 64) invalid(); result[key] = value(depth); whitespace();
      if (source[offset] === '}') { offset++; return Object.freeze(result); }
      if (source[offset++] !== ',') invalid();
    }
  };
  const result = value(0); whitespace();
  if (offset !== source.length) invalid();
  return result;
}

function exactKeys(value: LosslessObject, expected: readonly string[]): void {
  const actual = Object.keys(value).sort();
  if (actual.length !== expected.length || actual.some((key, index) => key !== expected[index])) invalid();
}
function responseText(value: LosslessJson | undefined, expected?: string): string {
  if (typeof value !== 'string') return invalid();
  if (value.length > 160 || value.trim() !== value || /[\u0000-\u001f\u007f]/u.test(value) ||
      expected !== undefined && value !== expected) return invalid();
  return value;
}
function responseInteger(value: LosslessJson | undefined): {readonly raw: string; readonly value: number} {
  if (!isNumber(value)) return invalid();
  if (!/^(?:0|[1-9][0-9]{0,15})$/u.test(value.raw)) return invalid();
  const parsed = Number(value.raw); if (!Number.isSafeInteger(parsed)) invalid();
  return Object.freeze({raw: value.raw, value: parsed});
}
interface DecimalParts {readonly digits: string; readonly scale: number; readonly zero: boolean}
function decimal(value: LosslessJson | undefined, allowZero: boolean): {readonly raw: string; readonly parts: DecimalParts} {
  if (!isNumber(value)) return invalid();
  if (value.raw.startsWith('-')) return invalid();
  const match = /^(0|[1-9][0-9]*)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?$/u.exec(value.raw);
  if (!match) return invalid();
  const exponent = Number(match[3] ?? '0');
  if (!Number.isSafeInteger(exponent) || Math.abs(exponent) > 100) invalid();
  let digits = `${match[1] ?? ''}${match[2] ?? ''}`.replace(/^0+/u, '');
  const zero = digits.length === 0;
  if (zero) digits = '0';
  if (zero && !allowZero) invalid();
  return Object.freeze({raw: value.raw, parts: Object.freeze({digits, scale: zero ? 0 : exponent - (match[2]?.length ?? 0), zero})});
}
function compareDecimal(left: DecimalParts, right: DecimalParts): number {
  if (left.zero || right.zero) return left.zero === right.zero ? 0 : left.zero ? -1 : 1;
  const leftMagnitude = left.digits.length + left.scale, rightMagnitude = right.digits.length + right.scale;
  if (leftMagnitude !== rightMagnitude) return leftMagnitude < rightMagnitude ? -1 : 1;
  const scale = Math.min(left.scale, right.scale);
  const leftValue = BigInt(left.digits + '0'.repeat(left.scale - scale));
  const rightValue = BigInt(right.digits + '0'.repeat(right.scale - scale));
  return leftValue < rightValue ? -1 : leftValue > rightValue ? 1 : 0;
}

function validatedClock(now: () => number): number {
  let value: number;
  try { value = now(); } catch { throw new StockHistoryError('STOCK_HISTORY_UNAVAILABLE'); }
  if (!Number.isSafeInteger(value) || value < 0 || value > 8_639_999_999_000_000) {
    throw new StockHistoryError('STOCK_HISTORY_UNAVAILABLE');
  }
  return value;
}

export function validateStockHistoryInput(input: StockHistoryInput, nowUnixSeconds: number): Readonly<{
  assetId: typeof STOCK_HISTORY_ASSET.assetId; variantMint: typeof STOCK_HISTORY_ASSET.variantMint;
  interval: StockHistoryInterval; fromUnixSeconds: string; toUnixSeconds: string; from: number; to: number;
}> {
  if (!input || typeof input !== 'object' || Array.isArray(input) ||
      Object.keys(input).sort().join(',') !== 'assetId,fromUnixSeconds,interval,toUnixSeconds,variantMint' ||
      input.assetId !== STOCK_HISTORY_ASSET.assetId || input.variantMint !== STOCK_HISTORY_ASSET.variantMint ||
      !Object.hasOwn(intervals, input.interval) || !Number.isSafeInteger(nowUnixSeconds) || nowUnixSeconds < 0) badInput();
  const parse = (raw: unknown): number => {
    if (typeof raw !== 'string' || !/^[1-9][0-9]{0,9}$/u.test(raw)) badInput();
    const number = Number(raw); if (!Number.isSafeInteger(number)) badInput(); return number;
  };
  const from = parse(input.fromUnixSeconds), to = parse(input.toUnixSeconds);
  const intervalSeconds = intervals[input.interval];
  if (from < 946_684_800 || from >= to || to - from < intervalSeconds || to - from > maxWindowSeconds ||
      to > nowUnixSeconds + 60) badInput();
  return Object.freeze({...input, from, to});
}

export function parseTokensVariantHistory(body: string, request: ReturnType<typeof validateStockHistoryInput>,
  provenance: {readonly sourceUrl: string; readonly requestedAt: number; readonly observedAt: number}): StockHistoryPage {
  const payload = parseLosslessJson(body);
  if (!isObject(payload)) return invalid();
  exactKeys(payload, ['assetId', 'candles', 'from', 'interval', 'mint', 'to']);
  responseText(payload['assetId'], request.assetId);
  responseText(payload['mint'], request.variantMint);
  responseText(payload['interval'], request.interval);
  const from = responseInteger(payload['from']), to = responseInteger(payload['to']);
  if (from.raw !== request.fromUnixSeconds || to.raw !== request.toUnixSeconds) return invalid();
  const rawCandleValue = payload['candles'];
  if (!Array.isArray(rawCandleValue)) return invalid();
  const rawCandles = rawCandleValue as readonly LosslessJson[];
  const intervalSeconds = intervals[request.interval];
  const maximumCandles = Math.floor((request.to - request.from) / intervalSeconds) + 2;
  if (rawCandles.length > maximumCandles) invalid();
  const candles: StockHistoryCandle[] = [];
  let previousTime: number | undefined;
  for (const raw of rawCandles) {
    if (!isObject(raw)) return invalid();
    const candle = raw;
    exactKeys(candle, ['close', 'high', 'low', 'open', 'time', 'volume']);
    const time = responseInteger(candle['time']);
    if (time.value < request.from || time.value > request.to || time.value % intervalSeconds !== 0 ||
        previousTime !== undefined && (time.value <= previousTime || (time.value - previousTime) % intervalSeconds !== 0)) invalid();
    previousTime = time.value;
    const open = decimal(candle['open'], false), high = decimal(candle['high'], false), low = decimal(candle['low'], false);
    const close = decimal(candle['close'], false), volume = decimal(candle['volume'], true);
    if (compareDecimal(high.parts, open.parts) < 0 || compareDecimal(high.parts, close.parts) < 0 ||
        compareDecimal(high.parts, low.parts) < 0 || compareDecimal(low.parts, open.parts) > 0 ||
        compareDecimal(low.parts, close.parts) > 0) invalid();
    candles.push(Object.freeze({startUnixSeconds: time.raw, openRaw: open.raw, highRaw: high.raw,
      lowRaw: low.raw, closeRaw: close.raw, volumeRaw: volume.raw}));
  }
  const requestedAt = provenance.requestedAt, observedAt = provenance.observedAt;
  if (!Number.isSafeInteger(requestedAt) || !Number.isSafeInteger(observedAt) || observedAt < requestedAt ||
      observedAt >= requestedAt + 60_000) throw new StockHistoryError('STOCK_HISTORY_TIMEOUT');
  return Object.freeze({schemaVersion: 1, provider: 'tokens-xyz-v1',
    providerContract: 'observed_not_execution_qualified', historyKind: 'solana_mint_variant',
    canonicalEquityHistory: false, assetId: request.assetId, variantMint: request.variantMint,
    interval: request.interval, fromUnixSeconds: request.fromUnixSeconds, toUnixSeconds: request.toUnixSeconds,
    candles: Object.freeze(candles), dataStatus: candles.length === 0 ? 'empty_provider_cache_or_no_trades' : 'observed',
    numericEncoding: 'exact_provider_json_number_lexemes', priceUnit: 'provider_not_declared',
    volumeUnit: 'provider_not_declared', provenance: Object.freeze({sourceUrl: provenance.sourceUrl,
      requestedAt: new Date(requestedAt).toISOString(), observedAt: new Date(observedAt).toISOString(),
      providerAsOf: null, providerFreshness: 'not_reported', providerCandleSource: 'not_exposed',
      refreshAfter: new Date(observedAt + localCacheMs).toISOString(), cachedUpstreamData: true}),
    executionEnabled: false, eligibility: 'unverified'});
}

export interface TokensStockHistoryOptions {
  readonly apiKey: string;
  readonly fetch?: typeof globalThis.fetch;
  readonly now?: () => number;
  readonly timeoutMs?: number;
  readonly protection?: Partial<Omit<BoundedProviderReadConfiguration, 'now'>>;
}

export class TokensStockHistory implements StockHistory {
  readonly #key: string;
  readonly #fetch: typeof globalThis.fetch;
  readonly #now: () => number;
  readonly #timeoutMs: number;
  readonly #reads: BoundedProviderRead<StockHistoryPage>;
  #providerRetryAt = 0;
  constructor(options: TokensStockHistoryOptions) {
    if (!options || typeof options.apiKey !== 'string' || options.apiKey.length < 8 || options.apiKey.length > 512 ||
        !/^[\x21-\x7e]+$/u.test(options.apiKey)) throw new StockHistoryError('STOCK_HISTORY_UNAVAILABLE');
    this.#key = options.apiKey; this.#fetch = options.fetch ?? globalThis.fetch; this.#now = options.now ?? Date.now;
    this.#timeoutMs = options.timeoutMs ?? 6_000;
    if (!Number.isInteger(this.#timeoutMs) || this.#timeoutMs < 1 || this.#timeoutMs > 8_000) {
      throw new StockHistoryError('STOCK_HISTORY_UNAVAILABLE');
    }
    this.#reads = new BoundedProviderRead<StockHistoryPage>({cacheTtlMs: localCacheMs,
      rateLimitWindowMs: 60_000, perKeyLimit: 12, globalLimit: 120, maxTrackedKeys: 128,
      maxCacheEntries: 64, maxConcurrentReads: 4, ...options.protection, now: this.#now}, {
      configurationInvalid: () => new StockHistoryError('STOCK_HISTORY_UNAVAILABLE'),
      rateLimited: () => new StockHistoryError('STOCK_HISTORY_RATE_LIMITED'),
    });
  }
  async history(input: StockHistoryInput): Promise<StockHistoryPage> {
    const now = validatedClock(this.#now);
    if (now < this.#providerRetryAt) throw new StockHistoryError('STOCK_HISTORY_RATE_LIMITED');
    const request = validateStockHistoryInput(input, Math.floor(now / 1000));
    const key = `${request.assetId}:${request.variantMint}:${request.interval}:${request.fromUnixSeconds}:${request.toUnixSeconds}`;
    return this.#reads.read(key, `${request.assetId}:${request.variantMint}`, admittedAt => this.#load(request, admittedAt));
  }
  async #load(request: ReturnType<typeof validateStockHistoryInput>, admittedAt: number): Promise<StockHistoryPage> {
    const url = new URL(`/v1/assets/${request.assetId}/ohlcv`, origin);
    url.search = new URLSearchParams({mint: request.variantMint, interval: request.interval,
      from: request.fromUnixSeconds, to: request.toUnixSeconds}).toString();
    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout> | undefined;
    const deadline = new Promise<never>((_resolve, reject) => {
      timer = setTimeout(() => { controller.abort(); reject(new StockHistoryError('STOCK_HISTORY_TIMEOUT')); }, this.#timeoutMs);
    });
    let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
    try {
      const pending = this.#fetch(url, {method: 'GET', redirect: 'error', signal: controller.signal,
        headers: {accept: 'application/json', 'x-api-key': this.#key}});
      void pending.then(response => {
        if (controller.signal.aborted) { try { void response.body?.cancel().catch(() => {}); } catch { /* disposal only */ } }
      }, () => {});
      const response = await Promise.race([pending, deadline]);
      if (response.redirected || response.url && new URL(response.url).origin !== origin) invalid();
      if (response.status === 401 || response.status === 403) throw new StockHistoryError('STOCK_HISTORY_PROVIDER_AUTH_FAILED');
      if (response.status === 429) {
        this.#providerRetryAt = Math.max(this.#providerRetryAt, admittedAt + 60_000);
        throw new StockHistoryError('STOCK_HISTORY_RATE_LIMITED');
      }
      if (!response.ok) throw new StockHistoryError('STOCK_HISTORY_PROVIDER_UNAVAILABLE');
      const responseBody = response.body;
      if (!responseBody) return invalid();
      if (!/^application\/json(?:\s*;|$)/iu.test(response.headers.get('content-type') ?? '')) return invalid();
      const declared = response.headers.get('content-length');
      if (declared !== null && (!/^\d+$/u.test(declared) || Number(declared) > maxBodyBytes)) invalid();
      reader = responseBody.getReader(); const chunks: Uint8Array[] = []; let bytes = 0;
      for (;;) {
        const part = await Promise.race([reader.read(), deadline]);
        if (part.done) break;
        bytes += part.value.byteLength; if (bytes > maxBodyBytes) invalid(); chunks.push(part.value);
      }
      const body = new TextDecoder('utf8', {fatal: true}).decode(Buffer.concat(chunks));
      if (controller.signal.aborted) throw new StockHistoryError('STOCK_HISTORY_TIMEOUT');
      return parseTokensVariantHistory(body, request, {sourceUrl: url.href, requestedAt: admittedAt,
        observedAt: validatedClock(this.#now)});
    } catch (error) {
      if (controller.signal.aborted) throw new StockHistoryError('STOCK_HISTORY_TIMEOUT');
      if (error instanceof StockHistoryError) throw error;
      if (error instanceof SyntaxError || error instanceof TypeError && reader !== undefined) invalid();
      throw new StockHistoryError('STOCK_HISTORY_PROVIDER_UNAVAILABLE');
    } finally {
      clearTimeout(timer); controller.abort();
      if (reader) { try { void reader.cancel().catch(() => {}); } catch { /* disposal only */ } }
    }
  }
}

export function readStockHistory(env: Readonly<Record<string, string | undefined>>): TokensStockHistory | undefined {
  const mode = env['TRIMMY_STOCK_HISTORY'];
  if (mode === undefined || mode === '' || mode === 'disabled') return undefined;
  if (mode !== 'tokens_xyz' || !env['TOKENS_API_KEY']) throw new StockHistoryError('STOCK_HISTORY_UNAVAILABLE');
  return new TokensStockHistory({apiKey: env['TOKENS_API_KEY']});
}
