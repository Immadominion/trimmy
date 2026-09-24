/**
 * Read-only catalog of PreStocks tokenized pre-IPO stocks. It fetches the public
 * PreStocks listing, validates every field strictly, and returns an indicative,
 * non-executable snapshot in the same shape as Trimmy's other market reads.
 *
 * It has no key, no write path, no wallet and no transaction. Prices are the
 * provider's own indicative marks with no timestamp we can verify, so the
 * snapshot says so: `executionEnabled: false`, `eligibility: 'unverified'`,
 * `mintVerification: 'not_checked'`. Nothing here is a quote to trade, a
 * balance, or a claim about a mint on chain.
 */
export type PreStocksErrorCode =
  | 'PRESTOCKS_UNAVAILABLE'
  | 'PRESTOCKS_PROVIDER_UNAVAILABLE'
  | 'PRESTOCKS_RATE_LIMITED'
  | 'PRESTOCKS_RESPONSE_INVALID'
  | 'PRESTOCKS_TIMEOUT';

const messages: Record<PreStocksErrorCode, string> = {
  PRESTOCKS_UNAVAILABLE: 'Pre-IPO stock reads are not configured.',
  PRESTOCKS_PROVIDER_UNAVAILABLE: 'Pre-IPO stock data is unavailable. Try again later.',
  PRESTOCKS_RATE_LIMITED: 'Wait before requesting pre-IPO stock data again.',
  PRESTOCKS_RESPONSE_INVALID: 'The pre-IPO stock provider returned unusable data.',
  PRESTOCKS_TIMEOUT: 'The pre-IPO stock data request took too long.',
};

export class PreStocksError extends Error {
  constructor(readonly code: PreStocksErrorCode) {
    super(messages[code]);
    this.name = 'PreStocksError';
  }
}
function invalid(): never { throw new PreStocksError('PRESTOCKS_RESPONSE_INVALID'); }

export interface PreStockListing {
  readonly name: string;
  readonly symbol: string;
  readonly description: string;
  readonly imageUrl: string;
  readonly externalUrl: string;
  /** Base58 mint address, validated for encoding and length only. */
  readonly contractAddress: string;
  /** Provider figures as strings, so no float rounding turns them into amounts. */
  readonly markPrice: string;
  readonly markValuation: string;
  readonly tokenPrice: string;
  readonly impliedValuation: string;
  readonly supply: string;
  /** tokenPrice over markPrice, expressed in basis points, when both are positive. */
  readonly premiumBasisPoints: number | null;
}

export interface PreStocksCatalog {
  readonly schemaVersion: 1;
  readonly kind: 'prestocks_catalog';
  readonly provider: 'prestocks-v1';
  readonly sourceUrl: string;
  readonly requestedAt: string;
  readonly observedAt: string;
  readonly refreshAfter: string;
  readonly providerFreshness: 'not_verified';
  readonly priceKind: 'indicative';
  readonly executionEnabled: false;
  readonly eligibility: 'unverified';
  readonly mintVerification: 'not_checked';
  readonly notice: string;
  readonly listings: readonly PreStockListing[];
}

export interface PreStocks {
  catalog(): Promise<PreStocksCatalog>;
}

export interface PreStocksReaderOptions {
  readonly fetch?: typeof globalThis.fetch;
  readonly now?: () => number;
  readonly timeoutMs?: number;
}

const ORIGIN = 'https://prestocks.com';
const PATH = '/api/prestocks';
const BYTE_LIMIT = 1_048_576;
const FRESHNESS_MS = 60_000;
const MAX_LISTINGS = 256;
const NOTICE = 'Indicative pre-IPO marks from PreStocks. Not a quote, a balance or a verified on-chain mint. No buying or selling here.';

function record(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) invalid();
  const proto: unknown = Object.getPrototypeOf(value);
  if (proto !== Object.prototype && proto !== null) invalid();
  return value as Record<string, unknown>;
}

function text(value: unknown, max: number): string {
  if (typeof value !== 'string' || value.length < 1 || value.length > max ||
      /[\u0000-\u001f\u007f]/u.test(value)) invalid();
  return value;
}

/** Descriptions carry newlines and tabs; only other control characters are refused. */
function multilineText(value: unknown, max: number): string {
  if (typeof value !== 'string' || value.length < 1 || value.length > max ||
      /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/u.test(value)) invalid();
  return value;
}

function symbol(value: unknown): string {
  if (typeof value !== 'string' || /^[A-Z0-9]{1,16}$/u.exec(value)?.[0] !== value) invalid();
  return value;
}

function httpsUrl(value: unknown): string {
  if (typeof value !== 'string' || value.length > 2_048) invalid();
  let url: URL;
  try { url = new URL(value); } catch { return invalid(); }
  if (url.protocol !== 'https:' || url.username !== '' || url.password !== '') invalid();
  return value;
}

/** Encoding and length validation only; it does not inspect the mint on chain. */
function mint(value: unknown): string {
  if (typeof value !== 'string' || value.length < 32 || value.length > 44) invalid();
  const alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  let decoded = 0n;
  for (const char of value) {
    const digit = alphabet.indexOf(char);
    if (digit < 0) invalid();
    decoded = decoded * 58n + BigInt(digit);
  }
  let bytes = 0;
  while (decoded > 0n) { bytes++; decoded >>= 8n; }
  const leadingZeroes = value.match(/^1*/u)?.[0].length ?? 0;
  if (bytes + leadingZeroes !== 32) invalid();
  return value;
}

/**
 * A finite, non-negative number kept as a canonical decimal string, so a client
 * never rounds a provider figure into a transaction amount. Rejects NaN,
 * infinities, negatives and anything outside a safe integer's worth of whole
 * units.
 */
function figure(value: unknown): {readonly text: string; readonly value: number} {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > 1e15) invalid();
  return {text: String(value), value};
}

function premiumBasisPoints(tokenPrice: number, markPrice: number): number | null {
  if (markPrice <= 0 || tokenPrice < 0) return null;
  return Math.round(((tokenPrice - markPrice) / markPrice) * 10_000);
}

function listing(value: unknown): PreStockListing {
  const row = record(value);
  const mark = figure(row['markPrice']);
  const token = figure(row['tokenPrice']);
  return Object.freeze({
    name: text(row['name'], 120),
    symbol: symbol(row['symbol']),
    description: multilineText(row['description'], 4_000),
    imageUrl: httpsUrl(row['image']),
    externalUrl: httpsUrl(row['external_url']),
    contractAddress: mint(row['contract_address']),
    markPrice: mark.text,
    markValuation: figure(row['markValuation']).text,
    tokenPrice: token.text,
    impliedValuation: figure(row['impliedValuation']).text,
    supply: figure(row['supply']).text,
    premiumBasisPoints: premiumBasisPoints(token.value, mark.value),
  });
}

export class HttpPreStocks implements PreStocks {
  readonly #fetch: typeof globalThis.fetch;
  readonly #now: () => number;
  readonly #timeout: number;
  #inFlight = false;
  #nextRequestAt = 0;

  constructor(options: PreStocksReaderOptions = {}) {
    this.#fetch = options.fetch ?? globalThis.fetch;
    this.#now = options.now ?? Date.now;
    this.#timeout = options.timeoutMs ?? 6_000;
    if (!Number.isInteger(this.#timeout) || this.#timeout < 1 || this.#timeout > 8_000) {
      throw new PreStocksError('PRESTOCKS_UNAVAILABLE');
    }
  }

  async catalog(): Promise<PreStocksCatalog> {
    const started = this.#now();
    if (!Number.isSafeInteger(started) || started < 0 || started > 8_639_999_999_000_000) {
      throw new PreStocksError('PRESTOCKS_UNAVAILABLE');
    }
    if (this.#inFlight || started < this.#nextRequestAt) throw new PreStocksError('PRESTOCKS_RATE_LIMITED');
    this.#inFlight = true;
    this.#nextRequestAt = started + 2_000;
    const url = new URL(PATH, ORIGIN);
    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout> | undefined;
    const deadline = new Promise<never>((_resolve, reject) => {
      timer = setTimeout(() => { controller.abort(); reject(new PreStocksError('PRESTOCKS_TIMEOUT')); }, this.#timeout);
    });
    let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
    try {
      const pending = this.#fetch(url, {method: 'GET', headers: {accept: 'application/json'},
        redirect: 'error', signal: controller.signal});
      void pending.then(response => {
        if (controller.signal.aborted) { try { void response.body?.cancel().catch(() => {}); } catch { /* disposal only */ } }
      }, () => {});
      const response = await Promise.race([pending, deadline]);
      if (response.redirected || (response.url && new URL(response.url).origin !== ORIGIN)) invalid();
      if (response.status === 429) { this.#nextRequestAt = started + 60_000; throw new PreStocksError('PRESTOCKS_RATE_LIMITED'); }
      if (!response.ok) throw new PreStocksError('PRESTOCKS_PROVIDER_UNAVAILABLE');
      if (!/^application\/json(?:\s*;|$)/iu.test(response.headers.get('content-type') ?? '') || !response.body) invalid();
      const length = response.headers.get('content-length');
      if (length !== null && (!/^\d+$/u.test(length) || Number(length) > BYTE_LIMIT)) invalid();
      reader = response.body.getReader();
      const chunks: Uint8Array[] = [];
      let bytes = 0;
      for (;;) {
        const part = await Promise.race([reader.read(), deadline]);
        if (part.done) break;
        bytes += part.value.byteLength;
        if (bytes > BYTE_LIMIT) invalid();
        chunks.push(part.value);
      }
      const payload: unknown = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(Buffer.concat(chunks)));
      if (controller.signal.aborted) throw new PreStocksError('PRESTOCKS_TIMEOUT');
      const ended = this.#now();
      if (!Number.isSafeInteger(ended) || ended < started || ended >= started + FRESHNESS_MS) {
        throw new PreStocksError('PRESTOCKS_TIMEOUT');
      }
      if (!Array.isArray(payload) || payload.length < 1 || payload.length > MAX_LISTINGS) invalid();
      const listings = payload.map(listing);
      const symbols = listings.map(item => item.symbol);
      const mints = listings.map(item => item.contractAddress);
      if (new Set(symbols).size !== symbols.length || new Set(mints).size !== mints.length) invalid();
      return Object.freeze({
        schemaVersion: 1, kind: 'prestocks_catalog', provider: 'prestocks-v1', sourceUrl: url.href,
        requestedAt: new Date(started).toISOString(), observedAt: new Date(ended).toISOString(),
        refreshAfter: new Date(started + FRESHNESS_MS).toISOString(), providerFreshness: 'not_verified',
        priceKind: 'indicative', executionEnabled: false, eligibility: 'unverified', mintVerification: 'not_checked',
        notice: NOTICE, listings: Object.freeze(listings),
      });
    } catch (error) {
      if (controller.signal.aborted) throw new PreStocksError('PRESTOCKS_TIMEOUT');
      if (error instanceof PreStocksError) throw error;
      if (error instanceof SyntaxError || (error instanceof TypeError && reader !== undefined)) invalid();
      throw new PreStocksError('PRESTOCKS_PROVIDER_UNAVAILABLE');
    } finally {
      clearTimeout(timer);
      controller.abort();
      if (reader) { try { void reader.cancel().catch(() => {}); } catch { /* disposal only */ } }
      this.#inFlight = false;
    }
  }
}

/** Opt-in read: `TRIMMY_PRESTOCKS=public` enables the keyless catalog, nothing else does. */
export function readPreStocks(env: Readonly<Record<string, string | undefined>>): HttpPreStocks | undefined {
  const mode = env['TRIMMY_PRESTOCKS'];
  if (mode === undefined || mode === '' || mode === 'disabled') return undefined;
  if (mode !== 'public') throw new PreStocksError('PRESTOCKS_UNAVAILABLE');
  return new HttpPreStocks();
}
