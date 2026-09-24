import {invalid, list, record, schema, text, timestamp, StockResearchError} from './validation.js';
import {RESEARCH_AAPLX_MINT} from './estimate.js';

export type StockHistoryInterval = '1H' | '4H' | '1D';
export interface StockHistoryRequest {
  readonly assetId: 'apple';
  readonly variantMint: typeof RESEARCH_AAPLX_MINT;
  readonly interval: StockHistoryInterval;
  readonly fromUnixSeconds: string;
  readonly toUnixSeconds: string;
}
export interface StockHistoryCandle {
  readonly startUnixSeconds: string;
  /** Exact provider JSON-number lexemes; the provider does not declare their units. */
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
  readonly assetId: 'apple';
  readonly variantMint: typeof RESEARCH_AAPLX_MINT;
  readonly interval: StockHistoryInterval;
  readonly fromUnixSeconds: string;
  readonly toUnixSeconds: string;
  readonly candles: readonly StockHistoryCandle[];
  readonly dataStatus: 'observed' | 'empty_provider_cache_or_no_trades';
  readonly numericEncoding: 'exact_provider_json_number_lexemes';
  readonly priceUnit: 'provider_not_declared';
  readonly volumeUnit: 'provider_not_declared';
  readonly provenance: Readonly<{
    readonly sourceUrl: string;
    readonly requestedAt: string;
    readonly observedAt: string;
    readonly providerAsOf: null;
    readonly providerFreshness: 'not_reported';
    readonly providerCandleSource: 'not_exposed';
    readonly refreshAfter: string;
    readonly cachedUpstreamData: true;
  }>;
  readonly executionEnabled: false;
  readonly eligibility: 'unverified';
}

const intervalSeconds = Object.freeze({'1H': 3_600, '4H': 14_400, '1D': 86_400} as const);
const maximumWindowSeconds = 31 * 86_400;

function historyInputInvalid(): never { throw new StockResearchError('STOCK_HISTORY_INPUT_INVALID'); }
function historyResponseInvalid(): never { throw new StockResearchError('STOCK_HISTORY_RESPONSE_INVALID'); }

function unixSeconds(value: unknown): {readonly raw: string; readonly value: number} {
  if (typeof value !== 'string' || !/^[1-9][0-9]{0,9}$/u.test(value)) invalid();
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed)) invalid();
  return Object.freeze({raw: value, value: parsed});
}

function historyIdentity(value: unknown, nowUnixSeconds?: number): Readonly<{
  request: StockHistoryRequest; from: number; to: number; seconds: number;
}> {
  const data = record(value, ['assetId', 'variantMint', 'interval', 'fromUnixSeconds', 'toUnixSeconds']);
  if (data['assetId'] !== 'apple' || data['variantMint'] !== RESEARCH_AAPLX_MINT ||
      typeof data['interval'] !== 'string' || !Object.hasOwn(intervalSeconds, data['interval']) ||
      nowUnixSeconds !== undefined && (!Number.isSafeInteger(nowUnixSeconds) || nowUnixSeconds < 0)) invalid();
  const interval = data['interval'] as StockHistoryInterval;
  const from = unixSeconds(data['fromUnixSeconds']), to = unixSeconds(data['toUnixSeconds']);
  const seconds = intervalSeconds[interval];
  if (from.value < 946_684_800 || from.value >= to.value || to.value - from.value < seconds ||
      to.value - from.value > maximumWindowSeconds || nowUnixSeconds !== undefined && to.value > nowUnixSeconds + 60) invalid();
  return Object.freeze({request: Object.freeze({assetId: 'apple', variantMint: RESEARCH_AAPLX_MINT, interval,
    fromUnixSeconds: from.raw, toUnixSeconds: to.raw}), from: from.value, to: to.value, seconds});
}

export function parseStockHistoryRequest(value: unknown, nowUnixSeconds = Math.floor(Date.now() / 1_000)): StockHistoryRequest {
  try { return historyIdentity(value, nowUnixSeconds).request; }
  catch { return historyInputInvalid(); }
}

interface DecimalParts {readonly digits: string; readonly scale: number; readonly zero: boolean}
function decimal(value: unknown, allowZero: boolean): {readonly raw: string; readonly parts: DecimalParts} {
  const raw = text(value, 128);
  const match = /^(0|[1-9][0-9]*)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?$/u.exec(raw);
  if (!match) invalid();
  const exponent = Number(match[3] ?? '0');
  if (!Number.isSafeInteger(exponent) || Math.abs(exponent) > 100) invalid();
  let digits = `${match[1] ?? ''}${match[2] ?? ''}`.replace(/^0+/u, '');
  const zero = digits.length === 0;
  if (zero) digits = '0';
  if (zero && !allowZero) invalid();
  return Object.freeze({raw, parts: Object.freeze({digits, scale: zero ? 0 : exponent - (match[2]?.length ?? 0), zero})});
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

function candle(value: unknown): StockHistoryCandle & {readonly time: number} {
  const data = record(value, ['startUnixSeconds', 'openRaw', 'highRaw', 'lowRaw', 'closeRaw', 'volumeRaw']);
  const start = unixSeconds(data['startUnixSeconds']);
  const open = decimal(data['openRaw'], false), high = decimal(data['highRaw'], false);
  const low = decimal(data['lowRaw'], false), close = decimal(data['closeRaw'], false);
  const volume = decimal(data['volumeRaw'], true);
  if (compareDecimal(high.parts, open.parts) < 0 || compareDecimal(high.parts, close.parts) < 0 ||
      compareDecimal(high.parts, low.parts) < 0 || compareDecimal(low.parts, open.parts) > 0 ||
      compareDecimal(low.parts, close.parts) > 0) invalid();
  return Object.freeze({startUnixSeconds: start.raw, openRaw: open.raw, highRaw: high.raw, lowRaw: low.raw,
    closeRaw: close.raw, volumeRaw: volume.raw, time: start.value});
}

function exactSourceUrl(value: unknown, request: StockHistoryRequest): string {
  const source = text(value, 2_048);
  const expected = new URL('/v1/assets/apple/ohlcv', 'https://api.tokens.xyz');
  expected.search = new URLSearchParams({mint: request.variantMint, interval: request.interval,
    from: request.fromUnixSeconds, to: request.toUnixSeconds}).toString();
  let parsed: URL;
  try { parsed = new URL(source); } catch { return invalid(); }
  if (parsed.href !== expected.href || parsed.username || parsed.password || parsed.hash) invalid();
  return source;
}

/** Strict projection of mint-specific cached OHLCV. It never claims canonical equity history. */
export function parseStockHistoryPage(value: unknown, request: StockHistoryRequest): StockHistoryPage {
  try {
    const identity = historyIdentity(request);
    request = identity.request;
    const data = record(value, ['schemaVersion', 'provider', 'providerContract', 'historyKind', 'canonicalEquityHistory',
      'assetId', 'variantMint', 'interval', 'fromUnixSeconds', 'toUnixSeconds', 'candles', 'dataStatus',
      'numericEncoding', 'priceUnit', 'volumeUnit', 'provenance', 'executionEnabled', 'eligibility']);
    schema(data['schemaVersion']);
    if (data['provider'] !== 'tokens-xyz-v1' || data['providerContract'] !== 'observed_not_execution_qualified' ||
        data['historyKind'] !== 'solana_mint_variant' || data['canonicalEquityHistory'] !== false ||
        data['assetId'] !== request.assetId || data['variantMint'] !== request.variantMint ||
        data['interval'] !== request.interval || data['fromUnixSeconds'] !== request.fromUnixSeconds ||
        data['toUnixSeconds'] !== request.toUnixSeconds || data['numericEncoding'] !== 'exact_provider_json_number_lexemes' ||
        data['priceUnit'] !== 'provider_not_declared' || data['volumeUnit'] !== 'provider_not_declared' ||
        data['executionEnabled'] !== false || data['eligibility'] !== 'unverified') invalid();
    const {from, to, seconds} = identity;
    const parsedCandles = list(data['candles'], Math.floor((to - from) / seconds) + 2, candle);
    let previous: number | undefined;
    const candles: StockHistoryCandle[] = [];
    for (const current of parsedCandles) {
      if (current.time < from || current.time > to || current.time % seconds !== 0 ||
          previous !== undefined && (current.time <= previous || (current.time - previous) % seconds !== 0)) invalid();
      previous = current.time;
      candles.push(Object.freeze({startUnixSeconds: current.startUnixSeconds, openRaw: current.openRaw,
        highRaw: current.highRaw, lowRaw: current.lowRaw, closeRaw: current.closeRaw, volumeRaw: current.volumeRaw}));
    }
    const expectedStatus = candles.length === 0 ? 'empty_provider_cache_or_no_trades' : 'observed';
    if (data['dataStatus'] !== expectedStatus) invalid();
    const provenance = record(data['provenance'], ['sourceUrl', 'requestedAt', 'observedAt', 'providerAsOf',
      'providerFreshness', 'providerCandleSource', 'refreshAfter', 'cachedUpstreamData']);
    if (provenance['providerAsOf'] !== null || provenance['providerFreshness'] !== 'not_reported' ||
        provenance['providerCandleSource'] !== 'not_exposed' || provenance['cachedUpstreamData'] !== true) invalid();
    const sourceUrl = exactSourceUrl(provenance['sourceUrl'], request);
    const requestedAt = timestamp(provenance['requestedAt']), observedAt = timestamp(provenance['observedAt']);
    const refreshAfter = timestamp(provenance['refreshAfter']);
    const requestedTime = Date.parse(requestedAt), observedTime = Date.parse(observedAt), refreshTime = Date.parse(refreshAfter);
    if (observedTime < requestedTime || observedTime >= requestedTime + 60_000 || refreshTime !== observedTime + 15_000) invalid();
    return Object.freeze({schemaVersion: 1, provider: 'tokens-xyz-v1',
      providerContract: 'observed_not_execution_qualified', historyKind: 'solana_mint_variant',
      canonicalEquityHistory: false, assetId: 'apple', variantMint: RESEARCH_AAPLX_MINT,
      interval: request.interval, fromUnixSeconds: request.fromUnixSeconds, toUnixSeconds: request.toUnixSeconds,
      candles: Object.freeze(candles), dataStatus: expectedStatus,
      numericEncoding: 'exact_provider_json_number_lexemes', priceUnit: 'provider_not_declared',
      volumeUnit: 'provider_not_declared', provenance: Object.freeze({sourceUrl, requestedAt, observedAt,
        providerAsOf: null, providerFreshness: 'not_reported', providerCandleSource: 'not_exposed', refreshAfter,
        cachedUpstreamData: true}), executionEnabled: false, eligibility: 'unverified'});
  } catch (error) {
    if (error instanceof StockResearchError && error.code === 'STOCK_UNSUPPORTED_SCHEMA') throw error;
    return historyResponseInvalid();
  }
}
