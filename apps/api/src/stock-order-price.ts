/** How much worse than the market price an order may be, before the token's own fees. */
export const MARKET_PRICE_ALLOWANCE_BPS = 300;

export interface OrderPriceInput {
  readonly buying: boolean;
  /** USDC for a buy, the stock for a sell (raw units). */
  readonly inputRaw: string;
  /** Enforceable minimum output: stock for a buy, USDC for a sell, raw units. */
  readonly outputRaw: string;
  readonly outputTransferFeeBps?: number;
  readonly decimals: number;
  readonly transferFeeBps: number;
  readonly swapFeeBps: number;
  /**
   * Trusted prices per whole token in raw units (stock-token-prices.ts): the
   * reference selected by policy. Empty when none can be trusted.
   */
  readonly referencesUsd: readonly number[];
  /** Legacy callers may supply this; a quote never validates its own price. */
  readonly priceImpactPct?: unknown;
}

/** One explicitly selected reference, evaluated against the enforceable output
 * floor. Missing price data never falls back to the quote's own impact claim. */
export function orderPriceAcceptable(input: OrderPriceInput): boolean {
  if (!/^[1-9][0-9]{0,19}$/.test(input.inputRaw) || !/^[1-9][0-9]{0,19}$/.test(input.outputRaw) ||
      !Number.isInteger(input.decimals) || input.decimals < 0 || input.decimals > 18 ||
      ![input.transferFeeBps,input.swapFeeBps,input.outputTransferFeeBps ?? 0].every(value=>Number.isInteger(value) && value>=0 && value<=10_000) ||
      input.referencesUsd.length !== 1) return false;
  const reference=input.referencesUsd[0]!;
  if (!Number.isFinite(reference) || reference<=0) return false;
  const netOutput = BigInt(input.outputRaw) * BigInt(10_000 - (input.outputTransferFeeBps ?? 0)) / 10_000n;
  const tokens = Number(input.buying ? netOutput : input.inputRaw) / 10 ** input.decimals;
  const usdc = Number(input.buying ? input.inputRaw : netOutput) / 1e6;
  const price=usdc/tokens;
  const allowedBps=MARKET_PRICE_ALLOWANCE_BPS+input.transferFeeBps+input.swapFeeBps;
  return Number.isFinite(price) && price>0 &&
    (input.buying ? price/reference-1 : 1-price/reference)*10_000 <= allowedBps;
}
