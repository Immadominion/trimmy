import {createHash, randomUUID} from 'node:crypto';

/**
 * Server-only canonical equity evidence reader for the Career red-day mission.
 * It is deliberately separate from the public mint-history reader: this path
 * never sends a mint and only accepts Tokens.xyz ClickHouse stock candles.
 */
export const RED_DAY_PROVIDER = 'tokens-xyz-v1' as const;
export const RED_DAY_SOURCE = 'clickhouse_stock' as const;
export const RED_DAY_VERIFIER_VERSION = 'tokens-canonical-red-day-v1' as const;

export type RedDayFailureStatus = 'unavailable' | 'rejected';
export type RedDayFailureCode =
  | 'provider-auth-failed'
  | 'provider-rate-limited'
  | 'provider-unavailable'
  | 'provider-timeout'
  | 'response-invalid'
  | 'identity-mismatch'
  | 'source-mismatch'
  | 'stale-provider-data'
  | 'no-new-market-session';

export interface RedDayRequestAudit {
  readonly detailRequestId: string;
  readonly chartRequestId: string | null;
  readonly detailProviderRequestId: string | null;
  readonly chartProviderRequestId: string | null;
  readonly detailPath: string;
  readonly chartPath: string | null;
  readonly detailResponseSha256: string | null;
  readonly chartResponseSha256: string | null;
}

export interface CanonicalRedDaySession {
  readonly provider: typeof RED_DAY_PROVIDER;
  readonly source: typeof RED_DAY_SOURCE;
  readonly verifierVersion: typeof RED_DAY_VERIFIER_VERSION;
  readonly assetId: string;
  readonly listedSymbol: string;
  readonly previousMarketDate: string;
  readonly marketDate: string;
  readonly previousCloseText: string;
  readonly currentCloseText: string;
  readonly outcome: 'verified-red' | 'verified-not-red';
  readonly providerAsOf: string;
  readonly providerLastFetchedAt: string;
  readonly observedAt: string;
  readonly audit: RedDayRequestAudit;
}

export interface CanonicalRedDayRead {
  readonly sessions: readonly CanonicalRedDaySession[];
  readonly audit: RedDayRequestAudit;
  readonly observedAt: string;
}

export interface CanonicalRedDayReader {
  read(input: {readonly assetId: string; readonly listedSymbol: string;
    readonly afterMarketDate: string | null}): Promise<CanonicalRedDayRead>;
}

export class RedDayMarketError extends Error {
  constructor(
    readonly status: RedDayFailureStatus,
    readonly code: RedDayFailureCode,
    readonly audit: RedDayRequestAudit,
    readonly observedAt: string,
  ) {
    super(code);
    this.name = 'RedDayMarketError';
  }
}

class ExactJsonNumber {
  readonly kind = 'json-number' as const;
  constructor(readonly raw: string) { Object.freeze(this); }
}
interface LosslessArray extends ReadonlyArray<LosslessJson> {}
interface LosslessObject {readonly [key: string]: LosslessJson}
type LosslessJson = null | boolean | string | ExactJsonNumber | LosslessArray | LosslessObject;
interface DecimalParts {readonly digits: string; readonly scale: number; readonly zero: boolean}

const origin = 'https://api.tokens.xyz';
const maxBodyBytes = 1_048_576;
const chartWindowSeconds = 35 * 86_400;
const maximumAcceptedCandles = 40;
const maximumClockSkewMs = 5 * 60_000;
const maximumFetchAgeMs = 30 * 60_000;
const maximumLatestSessionAgeMs = 10 * 86_400_000;
const maximumRecordableSessionAgeMs = 14 * 86_400_000;
const assetPattern = /^[a-z0-9]+(?:-[a-z0-9]+)*$/u;
const symbolPattern = /^[A-Z][A-Z0-9.-]{0,14}$/u;
const datePattern = /^\d{4}-\d{2}-\d{2}$/u;
const hashPattern = /^[a-f0-9]{64}$/u;

function invalid(): never { throw new Error('invalid-response'); }

/** Bounded lossless parser: duplicate keys and unknown numeric rounding fail. */
function parseLosslessJson(source: string): LosslessJson {
  if (Buffer.byteLength(source, 'utf8') > maxBodyBytes) invalid();
  let offset = 0;
  let nodes = 0;
  const whitespace = (): void => { while (' \n\r\t'.includes(source[offset] ?? '\0')) offset++; };
  const value = (depth: number): LosslessJson => {
    if (++nodes > 100_000 || depth > 10) invalid();
    whitespace();
    const char = source[offset];
    if (char === '"') return string();
    if (char === '[') return array(depth + 1);
    if (char === '{') return object(depth + 1);
    for (const [literal, result] of [['true', true], ['false', false], ['null', null]] as const) {
      if (source.startsWith(literal, offset)) { offset += literal.length; return result; }
    }
    const match = /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/u.exec(source.slice(offset));
    if (!match || match[0].length > 128) invalid();
    offset += match[0].length;
    return new ExactJsonNumber(match[0]);
  };
  const string = (): string => {
    const start = offset++;
    let escaped = false;
    while (offset < source.length) {
      const char = source[offset++];
      if (char === undefined) invalid();
      if (escaped) { escaped = false; continue; }
      if (char === '\\') { escaped = true; continue; }
      if (char === '"') {
        let parsed: unknown;
        try { parsed = JSON.parse(source.slice(start, offset)); } catch { invalid(); }
        if (typeof parsed !== 'string' || parsed.length > 4_096) invalid();
        return parsed;
      }
      if (char < ' ') invalid();
    }
    return invalid();
  };
  const array = (depth: number): readonly LosslessJson[] => {
    offset++; whitespace();
    const result: LosslessJson[] = [];
    if (source[offset] === ']') { offset++; return Object.freeze(result); }
    for (;;) {
      if (result.length >= 20_000) invalid();
      result.push(value(depth)); whitespace();
      if (source[offset] === ']') { offset++; return Object.freeze(result); }
      if (source[offset++] !== ',') invalid();
    }
  };
  const object = (depth: number): LosslessObject => {
    offset++; whitespace();
    const result: Record<string, LosslessJson> = Object.create(null) as Record<string, LosslessJson>;
    let count = 0;
    if (source[offset] === '}') { offset++; return Object.freeze(result); }
    for (;;) {
      whitespace();
      if (source[offset] !== '"') invalid();
      const key = string(); whitespace();
      if (key.length > 80 || Object.hasOwn(result, key) || source[offset++] !== ':') invalid();
      if (++count > 96) invalid();
      result[key] = value(depth); whitespace();
      if (source[offset] === '}') { offset++; return Object.freeze(result); }
      if (source[offset++] !== ',') invalid();
    }
  };
  const result = value(0); whitespace();
  if (offset !== source.length) invalid();
  return result;
}

function object(value: LosslessJson): LosslessObject {
  if (value === null || typeof value !== 'object' || Array.isArray(value) || value instanceof ExactJsonNumber) invalid();
  return value as LosslessObject;
}
function exactKeys(value: LosslessObject, expected: readonly string[]): void {
  const actual = Object.keys(value).sort();
  const sortedExpected = [...expected].sort();
  if (actual.length !== sortedExpected.length || actual.some((key, index) => key !== sortedExpected[index])) invalid();
}
function text(value: LosslessJson | undefined, max = 160): string {
  if (typeof value !== 'string' || value.length < 1 || value.length > max || value.trim() !== value ||
      /[\u0000-\u001f\u007f]/u.test(value)) invalid();
  return value;
}
function displayObject(value: LosslessJson | undefined): LosslessObject {
  return object(value ?? null);
}
function displayArray(value: LosslessJson | undefined, max: number): readonly LosslessJson[] {
  if (!Array.isArray(value) || value.length > max) invalid();
  return value;
}
function displayTextArray(value: LosslessJson | undefined, max: number): void {
  const values = displayArray(value, max);
  for (const entry of values) text(entry, 160);
}
function exactInteger(value: LosslessJson | undefined, maximum = 8_640_000_000_000_000): number {
  if (!(value instanceof ExactJsonNumber) || !/^(?:0|[1-9][0-9]{0,15})$/u.test(value.raw)) invalid();
  const parsed = Number(value.raw);
  if (!Number.isSafeInteger(parsed) || parsed > maximum) invalid();
  return parsed;
}
function decimal(value: LosslessJson | undefined, allowZero: boolean): {readonly raw: string; readonly parts: DecimalParts} {
  if (!(value instanceof ExactJsonNumber) || value.raw.startsWith('-')) invalid();
  const match = /^(0|[1-9][0-9]*)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?$/u.exec(value.raw);
  if (!match) invalid();
  const exponent = Number(match[3] ?? '0');
  if (!Number.isSafeInteger(exponent) || Math.abs(exponent) > 100) invalid();
  let digits = `${match[1] ?? ''}${match[2] ?? ''}`.replace(/^0+/u, '');
  const zero = digits.length === 0;
  if (zero) digits = '0';
  if (zero && !allowZero) invalid();
  return Object.freeze({raw: value.raw,
    parts: Object.freeze({digits, scale: zero ? 0 : exponent - (match[2]?.length ?? 0), zero})});
}
function compareDecimal(left: DecimalParts, right: DecimalParts): number {
  if (left.zero || right.zero) return left.zero === right.zero ? 0 : left.zero ? -1 : 1;
  const leftMagnitude = left.digits.length + left.scale;
  const rightMagnitude = right.digits.length + right.scale;
  if (leftMagnitude !== rightMagnitude) return leftMagnitude < rightMagnitude ? -1 : 1;
  const scale = Math.min(left.scale, right.scale);
  const leftValue = BigInt(left.digits + '0'.repeat(left.scale - scale));
  const rightValue = BigInt(right.digits + '0'.repeat(right.scale - scale));
  return leftValue < rightValue ? -1 : leftValue > rightValue ? 1 : 0;
}
function sha256(value: string): string {
  const result = createHash('sha256').update(value, 'utf8').digest('hex');
  if (!hashPattern.test(result)) throw new Error('hash-failed');
  return result;
}
function iso(milliseconds: number): string {
  if (!Number.isSafeInteger(milliseconds) || milliseconds < 0 || milliseconds > 8_639_999_999_000_000) invalid();
  return new Date(milliseconds).toISOString();
}
function parseDate(value: string): number {
  if (!datePattern.test(value)) invalid();
  const milliseconds = Date.parse(`${value}T00:00:00.000Z`);
  if (!Number.isSafeInteger(milliseconds) || new Date(milliseconds).toISOString().slice(0, 10) !== value) invalid();
  return milliseconds;
}
const newYorkParts = new Intl.DateTimeFormat('en-US', {timeZone: 'America/New_York',
  year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit',
  second: '2-digit', hourCycle: 'h23'});
function newYorkInstant(marketDate: string, hour: number, minute: number): number {
  const midnight = parseDate(marketDate);
  const target = new Date(midnight);
  const targetParts = {year: target.getUTCFullYear(), month: target.getUTCMonth() + 1,
    day: target.getUTCDate(), hour, minute, second: 0};
  const targetPseudoUtc = Date.UTC(targetParts.year, targetParts.month - 1, targetParts.day,
    targetParts.hour, targetParts.minute, 0);
  let guess = targetPseudoUtc;
  for (let attempt = 0; attempt < 4; attempt++) {
    const values = Object.fromEntries(newYorkParts.formatToParts(new Date(guess))
      .filter(part => part.type !== 'literal').map(part => [part.type, Number(part.value)]));
    const actualPseudoUtc = Date.UTC(values['year'] ?? 0, (values['month'] ?? 0) - 1,
      values['day'] ?? 0, values['hour'] ?? 0, values['minute'] ?? 0, values['second'] ?? 0);
    const difference = targetPseudoUtc - actualPseudoUtc;
    if (difference === 0) return guess;
    guess += difference;
  }
  invalid();
}
function requestId(value: string | null): string | null {
  if (value === null || value === '') return null;
  if (value.length > 160 || value.trim() !== value || !/^[\x21-\x7e]+$/u.test(value)) invalid();
  return value;
}
function validInput(input: {readonly assetId: string; readonly listedSymbol: string;
  readonly afterMarketDate: string | null}): void {
  if (!input || typeof input !== 'object' || Array.isArray(input) ||
      Object.keys(input).sort().join(',') !== 'afterMarketDate,assetId,listedSymbol' ||
      !assetPattern.test(input.assetId) || input.assetId.length > 100 || !symbolPattern.test(input.listedSymbol)) {
    throw new TypeError('Invalid red-day asset input.');
  }
  if (input.afterMarketDate !== null) parseDate(input.afterMarketDate);
}

interface ParsedDetail {
  readonly providerAsOfMs: number;
  readonly providerLastFetchedAtMs: number;
}

function parseDetail(body: string, assetId: string, listedSymbol: string, observedAt: number): ParsedDetail {
  const root = object(parseLosslessJson(body));
  exactKeys(root, ['asset']);
  const asset = object(root['asset'] ?? null);
  // Tokens.xyz documents these as the complete default asset-detail shape.
  // Nested display-only blocks remain bounded by the lossless parser but are
  // deliberately not interpreted as evidence.
  exactKeys(asset, ['advisories', 'aliases', 'assetId', 'canonicalMarket', 'category',
    'description', 'imageUrl', 'name', 'primaryVariant', 'primaryVariantStrategy',
    'stats', 'symbol', 'symbols', 'variantGroups']);
  text(asset['name'], 200);
  text(asset['description'], 4_096);
  const imageUrl = text(asset['imageUrl'], 2_048);
  let parsedImageUrl: URL;
  try { parsedImageUrl = new URL(imageUrl); } catch { invalid(); }
  if (parsedImageUrl.protocol !== 'https:' || parsedImageUrl.username || parsedImageUrl.password) invalid();
  text(asset['primaryVariantStrategy'], 80);
  displayTextArray(asset['aliases'], 64);
  displayTextArray(asset['symbols'], 64);
  displayObject(asset['stats']);
  displayObject(asset['variantGroups']);
  if (asset['primaryVariant'] !== null) displayObject(asset['primaryVariant']);
  for (const advisory of displayArray(asset['advisories'], 64)) displayObject(advisory);
  if (text(asset['assetId']) !== assetId || text(asset['symbol'], 40) !== listedSymbol || asset['category'] !== 'equity') {
    throw new Error('identity-mismatch');
  }
  const market = object(asset['canonicalMarket'] ?? null);
  exactKeys(market, ['asOf', 'lastFetchedAt', 'marketCap', 'price', 'priceChange24hPercent',
    'providerLastUpdatedAt', 'source', 'symbol', 'volume24hUSD']);
  if (text(market['source'], 80) !== RED_DAY_SOURCE) throw new Error('source-mismatch');
  if (text(market['symbol'], 40) !== listedSymbol) throw new Error('identity-mismatch');
  decimal(market['price'], false);
  decimal(market['marketCap'], true);
  decimal(market['volume24hUSD'], true);
  // The percentage may be negative; it is not used as red-day evidence.
  if (!(market['priceChange24hPercent'] instanceof ExactJsonNumber)) invalid();
  const fetchedAt = exactInteger(market['lastFetchedAt']);
  const asOf = exactInteger(market['asOf'], 8_640_000_000_000);
  const providerLastUpdatedAt = exactInteger(market['providerLastUpdatedAt'], 8_640_000_000_000);
  if (asOf !== providerLastUpdatedAt || fetchedAt > observedAt + maximumClockSkewMs ||
      fetchedAt < observedAt - maximumFetchAgeMs || asOf * 1000 > observedAt + maximumClockSkewMs) {
    throw new Error('stale-provider-data');
  }
  return Object.freeze({providerAsOfMs: asOf * 1000, providerLastFetchedAtMs: fetchedAt});
}

interface ParsedCandle {
  readonly marketDate: string;
  readonly marketDateMs: number;
  readonly closeText: string;
  readonly close: DecimalParts;
}

function parseChart(body: string, assetId: string, from: number, to: number): readonly ParsedCandle[] {
  const root = object(parseLosslessJson(body));
  exactKeys(root, ['assetId', 'candles', 'from', 'interval', 'to']);
  if (text(root['assetId']) !== assetId || text(root['interval'], 10) !== '1D' ||
      exactInteger(root['from']) !== from || exactInteger(root['to']) !== to) invalid();
  if (!Array.isArray(root['candles']) || root['candles'].length > maximumAcceptedCandles) invalid();
  const result: ParsedCandle[] = [];
  let priorTime = -1;
  for (const raw of root['candles']) {
    const candle = object(raw);
    exactKeys(candle, ['close', 'high', 'low', 'open', 'time', 'volume']);
    const time = exactInteger(candle['time'], 8_640_000_000_000);
    if (time < from || time > to || time % 86_400 !== 0 || time <= priorTime) invalid();
    priorTime = time;
    const open = decimal(candle['open'], false);
    const high = decimal(candle['high'], false);
    const low = decimal(candle['low'], false);
    const close = decimal(candle['close'], false);
    decimal(candle['volume'], true);
    if (compareDecimal(high.parts, open.parts) < 0 || compareDecimal(high.parts, close.parts) < 0 ||
        compareDecimal(high.parts, low.parts) < 0 || compareDecimal(low.parts, open.parts) > 0 ||
        compareDecimal(low.parts, close.parts) > 0) invalid();
    const marketDateMs = time * 1000;
    const marketDate = new Date(marketDateMs).toISOString().slice(0, 10);
    const weekday = new Date(marketDateMs).getUTCDay();
    // US regular equity sessions never occur on Saturday or Sunday. Holiday
    // gaps are accepted only as gaps between adjacent canonical provider rows.
    if (weekday === 0 || weekday === 6) invalid();
    result.push(Object.freeze({marketDate,
      marketDateMs, closeText: close.raw, close: close.parts}));
  }
  return Object.freeze(result);
}

interface ResponseBody {
  readonly body: string;
  readonly responseSha256: string;
  readonly providerRequestId: string | null;
}

export interface TokensCanonicalRedDayOptions {
  readonly apiKey: string;
  readonly fetch?: typeof globalThis.fetch;
  readonly now?: () => number;
  readonly timeoutMs?: number;
  readonly wait?: (durationMs: number) => Promise<void>;
  readonly paceMs?: number;
  readonly requestId?: () => string;
}

export class TokensCanonicalRedDayReader implements CanonicalRedDayReader {
  readonly #apiKey: string;
  readonly #fetch: typeof globalThis.fetch;
  readonly #now: () => number;
  readonly #timeoutMs: number;
  readonly #paceMs: number;
  readonly #wait: (durationMs: number) => Promise<void>;
  readonly #requestId: () => string;
  #nextRequestAt = 0;

  constructor(options: TokensCanonicalRedDayOptions) {
    if (!options || typeof options.apiKey !== 'string' || options.apiKey.length < 8 || options.apiKey.length > 512 ||
        !/^[\x21-\x7e]+$/u.test(options.apiKey)) throw new TypeError('Tokens.xyz key is unavailable.');
    this.#apiKey = options.apiKey;
    this.#fetch = options.fetch ?? globalThis.fetch;
    this.#now = options.now ?? Date.now;
    this.#timeoutMs = options.timeoutMs ?? 6_000;
    this.#paceMs = options.paceMs ?? 1_000;
    this.#wait = options.wait ?? (duration => new Promise(resolve => setTimeout(resolve, duration)));
    this.#requestId = options.requestId ?? randomUUID;
    if (!Number.isInteger(this.#timeoutMs) || this.#timeoutMs < 1 || this.#timeoutMs > 8_000 ||
        !Number.isInteger(this.#paceMs) || this.#paceMs < 0 || this.#paceMs > 10_000) {
      throw new TypeError('Tokens.xyz red-day reader configuration is invalid.');
    }
  }

  async read(input: {readonly assetId: string; readonly listedSymbol: string;
    readonly afterMarketDate: string | null}): Promise<CanonicalRedDayRead> {
    validInput(input);
    const initialNow = this.#clock();
    const detailRequestId = this.#uuid();
    let chartRequestId: string | null = null;
    let detailProviderRequestId: string | null = null;
    let chartProviderRequestId: string | null = null;
    let detailHash: string | null = null;
    let chartHash: string | null = null;
    const detailUrl = new URL(`/v1/assets/${encodeURIComponent(input.assetId)}`, origin);
    const to = Math.floor(initialNow / 1000);
    const from = to - chartWindowSeconds;
    const chartUrl = new URL(`/v1/assets/${encodeURIComponent(input.assetId)}/price-chart`, origin);
    chartUrl.search = new URLSearchParams({interval: '1D', from: String(from), to: String(to)}).toString();
    const audit = (): RedDayRequestAudit => Object.freeze({detailRequestId, chartRequestId,
      detailProviderRequestId, chartProviderRequestId, detailPath: detailUrl.pathname,
      chartPath: chartRequestId === null ? null : `${chartUrl.pathname}${chartUrl.search}`,
      detailResponseSha256: detailHash, chartResponseSha256: chartHash});
    const fail = (status: RedDayFailureStatus, code: RedDayFailureCode): never => {
      throw new RedDayMarketError(status, code, audit(), iso(this.#clock()));
    };
    let detail: ParsedDetail;
    try {
      const response = await this.#get(detailUrl);
      detailProviderRequestId = response.providerRequestId;
      detailHash = response.responseSha256;
      try { detail = parseDetail(response.body, input.assetId, input.listedSymbol, this.#clock()); }
      catch (error) {
        const message = error instanceof Error ? error.message : '';
        if (message === 'identity-mismatch') return fail('rejected', 'identity-mismatch');
        if (message === 'source-mismatch') return fail('rejected', 'source-mismatch');
        if (message === 'stale-provider-data') return fail('rejected', 'stale-provider-data');
        return fail('rejected', 'response-invalid');
      }
    } catch (error) {
      if (error instanceof RedDayMarketError) throw error;
      const code = this.#failureCode(error);
      return fail(code === 'response-invalid' ? 'rejected' : 'unavailable', code);
    }

    chartRequestId = this.#uuid();
    let candles: readonly ParsedCandle[];
    try {
      const response = await this.#get(chartUrl);
      chartProviderRequestId = response.providerRequestId;
      chartHash = response.responseSha256;
      try { candles = parseChart(response.body, input.assetId, from, to); }
      catch { return fail('rejected', 'response-invalid'); }
    } catch (error) {
      if (error instanceof RedDayMarketError) throw error;
      const code = this.#failureCode(error);
      return fail(code === 'response-invalid' ? 'rejected' : 'unavailable', code);
    }

    if (candles.length < 2) return fail('unavailable', 'no-new-market-session');
    const latest = candles.at(-1);
    if (!latest) return fail('rejected', 'response-invalid');
    const latestClose = newYorkInstant(latest.marketDate, 16, 0);
    if (latestClose > initialNow + maximumClockSkewMs) return fail('rejected', 'response-invalid');
    if (initialNow - latestClose > maximumLatestSessionAgeMs || detail.providerAsOfMs < latestClose) {
      return fail('rejected', 'stale-provider-data');
    }
    const sessions: CanonicalRedDaySession[] = [];
    for (let index = 1; index < candles.length; index++) {
      const previous = candles[index - 1];
      const current = candles[index];
      if (!previous || !current || input.afterMarketDate !== null && current.marketDate <= input.afterMarketDate) continue;
      const currentClose = newYorkInstant(current.marketDate, 16, 0);
      // The database accepts canonical evidence only after this session closes
      // and for fourteen days. Older pairs remain useful as the prior trading
      // close for a recent candle, but are never emitted as observations.
      if (currentClose > initialNow || initialNow - currentClose > maximumRecordableSessionAgeMs) continue;
      const outcome = compareDecimal(current.close, previous.close) < 0 ? 'verified-red' : 'verified-not-red';
      sessions.push(Object.freeze({provider: RED_DAY_PROVIDER, source: RED_DAY_SOURCE,
        verifierVersion: RED_DAY_VERIFIER_VERSION, assetId: input.assetId,
        listedSymbol: input.listedSymbol, previousMarketDate: previous.marketDate,
        marketDate: current.marketDate, previousCloseText: previous.closeText,
        currentCloseText: current.closeText, outcome,
        providerAsOf: iso(detail.providerAsOfMs), providerLastFetchedAt: iso(detail.providerLastFetchedAtMs),
        observedAt: iso(this.#clock()), audit: audit()}));
    }
    if (!sessions.length) return fail('unavailable', 'no-new-market-session');
    const observedAt = iso(this.#clock());
    return Object.freeze({sessions: Object.freeze(sessions), audit: audit(), observedAt});
  }

  #clock(): number {
    let value: number;
    try { value = this.#now(); } catch { throw new Error('provider-unavailable'); }
    if (!Number.isSafeInteger(value) || value < 0 || value > 8_639_999_999_000_000) {
      throw new Error('provider-unavailable');
    }
    return value;
  }

  #uuid(): string {
    const value = this.#requestId();
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu.test(value)) {
      throw new TypeError('Red-day request ID factory returned an invalid UUID.');
    }
    return value.toLowerCase();
  }

  #failureCode(error: unknown): RedDayFailureCode {
    const message = error instanceof Error ? error.message : '';
    if (message === 'provider-auth-failed') return 'provider-auth-failed';
    if (message === 'provider-rate-limited') return 'provider-rate-limited';
    if (message === 'provider-timeout') return 'provider-timeout';
    if (message === 'response-invalid') return 'response-invalid';
    return 'provider-unavailable';
  }

  async #get(url: URL): Promise<ResponseBody> {
    const now = this.#clock();
    const waitFor = Math.max(0, this.#nextRequestAt - now);
    if (waitFor > 0) await this.#wait(waitFor);
    this.#nextRequestAt = this.#clock() + this.#paceMs;
    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout> | undefined;
    const deadline = new Promise<never>((_resolve, reject) => {
      timer = setTimeout(() => { controller.abort(); reject(new Error('provider-timeout')); }, this.#timeoutMs);
    });
    let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
    try {
      const pending = this.#fetch(url, {method: 'GET', redirect: 'error', signal: controller.signal,
        headers: {accept: 'application/json', 'x-api-key': this.#apiKey}});
      const response = await Promise.race([pending, deadline]);
      if (response.redirected || response.url && response.url !== url.href) throw new Error('response-invalid');
      if (response.status === 401 || response.status === 403) throw new Error('provider-auth-failed');
      if (response.status === 429) throw new Error('provider-rate-limited');
      if (!response.ok) throw new Error('provider-unavailable');
      if (!/^application\/json(?:\s*;|$)/iu.test(response.headers.get('content-type') ?? '')) {
        throw new Error('response-invalid');
      }
      const declared = response.headers.get('content-length');
      if (declared !== null && (!/^\d+$/u.test(declared) || Number(declared) > maxBodyBytes)) {
        throw new Error('response-invalid');
      }
      if (!response.body) throw new Error('response-invalid');
      reader = response.body.getReader();
      const chunks: Uint8Array[] = [];
      let bytes = 0;
      for (;;) {
        const part = await Promise.race([reader.read(), deadline]);
        if (part.done) break;
        bytes += part.value.byteLength;
        if (bytes > maxBodyBytes) throw new Error('response-invalid');
        chunks.push(part.value);
      }
      let body: string;
      try { body = new TextDecoder('utf8', {fatal: true}).decode(Buffer.concat(chunks)); }
      catch { throw new Error('response-invalid'); }
      return Object.freeze({body, responseSha256: sha256(body),
        providerRequestId: requestId(response.headers.get('x-request-id'))});
    } catch (error) {
      if (controller.signal.aborted) throw new Error('provider-timeout');
      if (error instanceof Error && ['provider-auth-failed', 'provider-rate-limited', 'provider-timeout',
        'provider-unavailable', 'response-invalid'].includes(error.message)) throw error;
      throw new Error('provider-unavailable');
    } finally {
      clearTimeout(timer);
      controller.abort();
      if (reader) { try { void reader.cancel().catch(() => {}); } catch { /* disposal only */ } }
    }
  }
}
