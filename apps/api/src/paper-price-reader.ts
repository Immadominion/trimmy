import {
  PAPER_FIXED_MAX, PAPER_FIXED_SCALE, parseInstant, parsePaperAssetId, parsePaperSymbol, parsePaperVariantMint,
} from '@trimmy/domain';
import { StockDiscoveryError } from './stock-discovery.js';
import type { StockDiscovery, StockVariantsPage } from './stock-discovery.js';

export type PaperPriceErrorCode = 'PAPER_PRICE_INVALID' | 'PAPER_PRICE_UNAVAILABLE' |
  'PAPER_ASSET_UNAVAILABLE' | 'PAPER_PRICE_STALE';
export type PaperPriceFailureKind = 'default' | 'rate_limited' | 'timeout';

const messages: Record<PaperPriceErrorCode, string> = {
  PAPER_PRICE_INVALID: 'Choose a valid stock for this paper order.',
  PAPER_PRICE_UNAVAILABLE: 'A current paper price is unavailable. Try again.',
  PAPER_ASSET_UNAVAILABLE: 'That stock variant is unavailable for paper trading.',
  PAPER_PRICE_STALE: 'The paper price is no longer current. Try again.',
};

export class PaperPriceError extends Error {
  constructor(readonly code: PaperPriceErrorCode, readonly failureKind: PaperPriceFailureKind = 'default') {
    super(failureKind === 'rate_limited' ? 'Paper prices are busy. Try again shortly.'
      : failureKind === 'timeout' ? 'The paper price request took too long. Try again.' : messages[code]);
    this.name = 'PaperPriceError';
  }
}

export interface AcceptedPaperPrice {
  readonly assetId: string;
  readonly variantMint: string;
  readonly symbol: string;
  /** Six-decimal paper price accepted by this server, never a JSON number. */
  readonly pricePaperMicros: string;
  readonly source: {
    readonly provider: 'tokens-xyz-v1';
    readonly providerReference: string;
    readonly marketSource: string | null;
    readonly metricsSource: string | null;
    readonly providerTimestamps: {
      readonly asOf: string | null;
      readonly lastFetchedAt: string | null;
      readonly lastTradeAt: string | null;
      readonly unit: 'not_declared';
    };
    readonly observedAt: string;
    readonly acceptedAt: string;
  };
  readonly expiresAt: string;
}

export interface PaperPriceReader {
  read(input: {
    readonly assetId: string;
    readonly variantMint: string;
    /** Cancels this caller's wait. StockDiscovery retains its own bounded fetch lifecycle. */
    readonly signal?: AbortSignal;
  }): Promise<AcceptedPaperPrice>;
}

/** Accept a provider's finite display number into the exact six-decimal paper ledger. */
export function paperPriceMicrosFromProvider(value: unknown): string {
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0 || value >= 1_000_000_000) {
    throw new PaperPriceError('PAPER_PRICE_UNAVAILABLE');
  }
  // Provider JSON has already crossed a Number boundary. The server explicitly
  // accepts one six-decimal snapshot and persists that integer; ledger math never
  // uses the floating-point value again.
  const fixed = value.toFixed(6);
  const [whole, fraction = ''] = fixed.split('.');
  const micros = BigInt(whole!) * PAPER_FIXED_SCALE + BigInt(fraction.padEnd(6, '0'));
  if (micros <= 0n || micros > PAPER_FIXED_MAX) throw new PaperPriceError('PAPER_PRICE_UNAVAILABLE');
  return micros.toString();
}

/** Adapts the existing read-only Tokens.xyz discovery client to paper prices. */
export class TokensPaperPriceReader implements PaperPriceReader {
  readonly #discovery: StockDiscovery;
  readonly #now: () => number;
  readonly #validForMs: number;

  constructor(discovery: StockDiscovery, options: {readonly now?: () => number; readonly validForMs?: number} = {}) {
    if (!discovery || typeof discovery.variants !== 'function') throw new PaperPriceError('PAPER_PRICE_UNAVAILABLE');
    this.#discovery = discovery;
    this.#now = options.now ?? Date.now;
    this.#validForMs = options.validForMs ?? 30_000;
    if (!Number.isInteger(this.#validForMs) || this.#validForMs < 5_000 || this.#validForMs > 60_000) {
      throw new PaperPriceError('PAPER_PRICE_UNAVAILABLE');
    }
  }

  #timestamp(): number {
    let value: number;
    try { value = this.#now(); }
    catch { throw new PaperPriceError('PAPER_PRICE_UNAVAILABLE'); }
    if (!Number.isSafeInteger(value) || value < 0 || value > 8_639_999_999_000_000) {
      throw new PaperPriceError('PAPER_PRICE_UNAVAILABLE');
    }
    return value;
  }

  async #variants(assetId: string, signal: AbortSignal | undefined): Promise<StockVariantsPage> {
    if (signal?.aborted) throw new PaperPriceError('PAPER_PRICE_UNAVAILABLE', 'timeout');
    const pending = this.#discovery.variants({assetId});
    if (!signal) return pending;

    let rejectAborted!: (error: PaperPriceError) => void;
    const aborted = new Promise<never>((_resolve, reject) => { rejectAborted = reject; });
    const onAbort = () => rejectAborted(new PaperPriceError('PAPER_PRICE_UNAVAILABLE', 'timeout'));
    signal.addEventListener('abort', onAbort, {once: true});
    if (signal.aborted) onAbort();
    try {
      // StockDiscovery deliberately owns the provider fetch AbortController.
      // This releases the paper-price caller immediately; the discovery read
      // remains protected by its own six-read ceiling and total deadline.
      return await Promise.race([pending, aborted]);
    } finally {
      signal.removeEventListener('abort', onAbort);
    }
  }

  async read(input: {
    readonly assetId: string;
    readonly variantMint: string;
    readonly signal?: AbortSignal;
  }): Promise<AcceptedPaperPrice> {
    let assetId: string;
    let variantMint: string;
    try { assetId = parsePaperAssetId(input?.assetId); variantMint = parsePaperVariantMint(input?.variantMint); }
    catch { throw new PaperPriceError('PAPER_PRICE_INVALID'); }
    const signal = input.signal;
    if (signal?.aborted) throw new PaperPriceError('PAPER_PRICE_UNAVAILABLE', 'timeout');
    const requestedMs = this.#timestamp();
    let page: Awaited<ReturnType<StockDiscovery['variants']>>;
    try { page = await this.#variants(assetId, signal); }
    catch (error) {
      if (error instanceof PaperPriceError) throw error;
      if (error instanceof StockDiscoveryError && error.code === 'STOCK_RATE_LIMITED') {
        throw new PaperPriceError('PAPER_PRICE_UNAVAILABLE', 'rate_limited');
      }
      if (error instanceof StockDiscoveryError && error.code === 'STOCK_TIMEOUT') {
        throw new PaperPriceError('PAPER_PRICE_UNAVAILABLE', 'timeout');
      }
      throw new PaperPriceError('PAPER_PRICE_UNAVAILABLE');
    }
    if (signal?.aborted) throw new PaperPriceError('PAPER_PRICE_UNAVAILABLE', 'timeout');
    const acceptedMs = this.#timestamp();
    if (acceptedMs < requestedMs) throw new PaperPriceError('PAPER_PRICE_UNAVAILABLE');
    let observedMs: number;
    try { observedMs = parseInstant(page.observedAt); }
    catch { throw new PaperPriceError('PAPER_PRICE_UNAVAILABLE'); }
    // The sanitized discovery snapshot must still be current when it is
    // accepted. Provider timestamps whose units are undeclared remain evidence.
    if (observedMs > acceptedMs + 5_000 || acceptedMs - observedMs > 10_000) {
      throw new PaperPriceError('PAPER_PRICE_STALE');
    }
    const variant = page.variants.find(row => row.mint === variantMint);
    if (!variant || variant.advisory !== null || !variant.market || !variant.symbol) {
      throw new PaperPriceError('PAPER_ASSET_UNAVAILABLE');
    }
    const pricePaperMicros = paperPriceMicrosFromProvider(variant.market.priceUsd);
    let symbol: string;
    try { symbol = parsePaperSymbol(variant.symbol); }
    catch { throw new PaperPriceError('PAPER_ASSET_UNAVAILABLE'); }
    const acceptedAt = new Date(acceptedMs).toISOString();
    const raw = variant.market.providerTimestamps;
    const providerTimestamps = Object.freeze({
      asOf: raw.asOf === null ? null : String(raw.asOf),
      lastFetchedAt: raw.lastFetchedAt === null ? null : String(raw.lastFetchedAt),
      lastTradeAt: raw.lastTradeAt === null ? null : String(raw.lastTradeAt), unit: 'not_declared' as const,
    });
    return Object.freeze({
      assetId, variantMint, symbol, pricePaperMicros,
      source: Object.freeze({
        provider: 'tokens-xyz-v1' as const,
        providerReference: `/v1/assets/${assetId}/variants#${variant.variantId}`,
        marketSource: variant.market.source, metricsSource: variant.market.metricsSource,
        providerTimestamps, observedAt: page.observedAt, acceptedAt,
      }),
      expiresAt: new Date(acceptedMs + this.#validForMs).toISOString(),
    });
  }
}
