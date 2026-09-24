import { parseRawAmount } from '@trimmy/domain';
import { JUPITER_QUOTE_ASSETS, JupiterQuoteReader, MarketEstimateError, readJupiterQuoteReader } from './jupiter-quote-reader.js';
import type { JupiterEstimateOptions, MarketEstimate } from './jupiter-quote-reader.js';

/** Research identity only; neither discovery nor this pin grants trading eligibility. */
export const STOCK_ESTIMATE_ASSET = Object.freeze({
  assetId: 'apple', variantMint: JUPITER_QUOTE_ASSETS.AAPLx.mint,
  symbol: 'AAPLx', decimals: 8, maxBuyInputRaw: '100000000', maxSellInputRaw: '100000000',
});
export interface StockEstimateInput {
  readonly assetId: 'apple';
  readonly variantMint: typeof STOCK_ESTIMATE_ASSET.variantMint;
  readonly side: 'buy' | 'sell';
  /** Raw integer input units: buy USDC (6 decimals), sell AAPLx (8 decimals). */
  readonly amountRaw: string;
}
export interface StockEstimate extends MarketEstimate {
  readonly assetId: 'apple';
  readonly variantMint: typeof STOCK_ESTIMATE_ASSET.variantMint;
  readonly side: 'buy' | 'sell';
  readonly executionEnabled: false;
  readonly eligibility: 'unverified';
  /** Raw token units must not be presented as scaled UI shares. */
  readonly amountUnits: 'raw_token_units';
}
export interface StockEstimates { estimate(input: StockEstimateInput): Promise<StockEstimate> }

/** Called at HTTP and adapter boundaries, before even injected provider code. */
export function validateStockEstimateInput(input: StockEstimateInput): void {
  if (!input || input.assetId !== STOCK_ESTIMATE_ASSET.assetId || input.variantMint !== STOCK_ESTIMATE_ASSET.variantMint ||
      (input.side !== 'buy' && input.side !== 'sell') ||
      Object.keys(input).length !== 4 || Object.keys(input).some((key) => !['assetId', 'variantMint', 'side', 'amountRaw'].includes(key))) {
    throw new MarketEstimateError('MARKET_INPUT_INVALID');
  }
  try {
    const amount = parseRawAmount(input.amountRaw);
    const cap = input.side === 'buy' ? STOCK_ESTIMATE_ASSET.maxBuyInputRaw : STOCK_ESTIMATE_ASSET.maxSellInputRaw;
    if (amount <= 0n || amount > BigInt(cap)) throw new Error();
  } catch { throw new MarketEstimateError('MARKET_INPUT_INVALID'); }
}

export class JupiterStockEstimates implements StockEstimates {
  readonly #reader: JupiterQuoteReader;
  constructor(options: JupiterEstimateOptions | JupiterQuoteReader) {
    this.#reader = options instanceof JupiterQuoteReader ? options : new JupiterQuoteReader(options);
  }
  async estimate(input: StockEstimateInput): Promise<StockEstimate> {
    validateStockEstimateInput(input);
    const request = Object.freeze({...input});
    const quote = await this.#reader.estimate({
      inputAsset: request.side === 'buy' ? 'USDC' : 'AAPLx',
      outputAsset: request.side === 'buy' ? 'AAPLx' : 'USDC', amountRaw: request.amountRaw,
    });
    return Object.freeze({...quote, assetId: request.assetId, variantMint: request.variantMint, side: request.side,
      executionEnabled: false, eligibility: 'unverified', amountUnits: 'raw_token_units'});
  }
}
export function readStockEstimates(env: Readonly<Record<string, string | undefined>>, reader = readJupiterQuoteReader(env)): JupiterStockEstimates | undefined {
  return reader === undefined ? undefined : new JupiterStockEstimates(reader);
}
