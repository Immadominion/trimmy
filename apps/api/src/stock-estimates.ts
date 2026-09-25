import { parseRawAmount } from '@trimmy/domain';
import { JupiterQuoteReader, MarketEstimateError, readJupiterQuoteReader } from './jupiter-quote-reader.js';
import { STOCK_TRADING_ASSETS, findStockTradingAsset } from './stock-trading-catalog.js';
import type { StockTradingAssetId } from './stock-trading-catalog.js';
import type { JupiterEstimateOptions, MarketEstimate } from './jupiter-quote-reader.js';

/** Legacy Apple fixture alias; executable identities come from the shared catalog. */
const apple = STOCK_TRADING_ASSETS.find(asset => asset.assetId === 'apple')!;
export const STOCK_ESTIMATE_ASSET = Object.freeze({...apple, assetId: 'apple' as const, variantMint: apple.mint});
export interface StockEstimateInput {
  readonly assetId: StockTradingAssetId;
  readonly variantMint: string;
  readonly side: 'buy' | 'sell';
  /** Raw integer input units: buy USDC (6 decimals), sell the selected stock token (8 decimals). */
  readonly amountRaw: string;
}
export interface StockEstimate extends MarketEstimate {
  readonly assetId: StockTradingAssetId;
  readonly variantMint: string;
  readonly side: 'buy' | 'sell';
  readonly executionEnabled: false;
  readonly eligibility: 'unverified';
  /** Raw token units must not be presented as scaled UI shares. */
  readonly amountUnits: 'raw_token_units';
}
export interface StockEstimates { estimate(input: StockEstimateInput): Promise<StockEstimate> }

/** Called at HTTP and adapter boundaries, before even injected provider code. */
export function validateStockEstimateInput(input: StockEstimateInput): void {
  const asset = input && findStockTradingAsset(input.assetId, input.variantMint);
  if (!asset ||
      (input.side !== 'buy' && input.side !== 'sell') ||
      Object.keys(input).length !== 4 || Object.keys(input).some((key) => !['assetId', 'variantMint', 'side', 'amountRaw'].includes(key))) {
    throw new MarketEstimateError('MARKET_INPUT_INVALID');
  }
  try {
    const amount = parseRawAmount(input.amountRaw);
    const cap = input.side === 'buy' ? asset.maxBuyInputRaw : asset.maxSellInputRaw;
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
    const asset = findStockTradingAsset(request.assetId, request.variantMint)!;
    const quote = await this.#reader.estimate({
      inputAsset: request.side === 'buy' ? 'USDC' : asset.symbol,
      outputAsset: request.side === 'buy' ? asset.symbol : 'USDC', amountRaw: request.amountRaw,
    });
    return Object.freeze({...quote, assetId: request.assetId, variantMint: request.variantMint, side: request.side,
      executionEnabled: false, eligibility: 'unverified', amountUnits: 'raw_token_units'});
  }
}
export function readStockEstimates(env: Readonly<Record<string, string | undefined>>, reader = readJupiterQuoteReader(env)): JupiterStockEstimates | undefined {
  return reader === undefined ? undefined : new JupiterStockEstimates(reader);
}
