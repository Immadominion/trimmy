import { parseRawAmount } from '@trimmy/domain';
import { JUPITER_QUOTE_ASSETS, JupiterQuoteReader, MarketEstimateError, readJupiterQuoteReader } from './jupiter-quote-reader.js';
import type { MarketEstimate, JupiterEstimateOptions } from './jupiter-quote-reader.js';
export { MarketEstimateError } from './jupiter-quote-reader.js';
export type { MarketEstimate, MarketEstimateErrorCode, JupiterEstimateAccess, JupiterEstimateOptions } from './jupiter-quote-reader.js';

/** Public SOL/USDC research pair; no approved financial assets. */
export const RESEARCH_MARKET_ASSETS = Object.freeze({SOL: JUPITER_QUOTE_ASSETS.SOL, USDC: JUPITER_QUOTE_ASSETS.USDC});
export type ResearchMarketAsset = keyof typeof RESEARCH_MARKET_ASSETS;
export interface MarketEstimateInput {
  readonly inputAsset: ResearchMarketAsset;
  readonly outputAsset: ResearchMarketAsset;
  readonly amountRaw: string;
}
export interface MarketEstimates { estimate(input: MarketEstimateInput): Promise<MarketEstimate> }
export function validateMarketEstimateInput(input: MarketEstimateInput): void {
  if (!input || !Object.hasOwn(RESEARCH_MARKET_ASSETS, input.inputAsset) ||
      !Object.hasOwn(RESEARCH_MARKET_ASSETS, input.outputAsset) || input.inputAsset === input.outputAsset) {
    throw new MarketEstimateError('MARKET_INPUT_INVALID');
  }
  try {
    const amount = parseRawAmount(input.amountRaw);
    if (amount <= 0n || amount > BigInt(RESEARCH_MARKET_ASSETS[input.inputAsset].maxInputRaw)) throw new Error();
  } catch { throw new MarketEstimateError('MARKET_INPUT_INVALID'); }
}

/** Pass the same reader to both estimate adapters to share the provider budget. */
export class JupiterMarketEstimates implements MarketEstimates {
  readonly #reader: JupiterQuoteReader;
  constructor(options: JupiterEstimateOptions | JupiterQuoteReader) {
    this.#reader = options instanceof JupiterQuoteReader ? options : new JupiterQuoteReader(options);
  }
  async estimate(input: MarketEstimateInput): Promise<MarketEstimate> {
    validateMarketEstimateInput(input);
    return this.#reader.estimate(input);
  }
}
export function readMarketEstimates(env: Readonly<Record<string, string | undefined>>, reader = readJupiterQuoteReader(env)): JupiterMarketEstimates | undefined {
  return reader === undefined ? undefined : new JupiterMarketEstimates(reader);
}
