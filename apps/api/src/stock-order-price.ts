/** How much worse than the market price an order may be, before the token's own fees. */
export const MARKET_PRICE_ALLOWANCE_BPS = 300;
/** Jupiter's price impact limit when no market price exists to compare. */
export const MAX_PRICE_IMPACT = 0.05;

export interface OrderPriceInput {
  readonly buying: boolean;
  /** USDC for a buy, the stock for a sell (raw units). */
  readonly inputRaw: string;
  /** The stock for a buy, USDC for a sell (raw units, as quoted). */
  readonly outputRaw: string;
  readonly decimals: number;
  readonly transferFeeBps: number;
  readonly swapFeeBps: number;
  /**
   * Trusted prices per whole token in raw units (stock-token-prices.ts): the
   * issuer's, and a liquid market's. Empty when none can be trusted.
   */
  readonly referencesUsd: readonly number[];
  /** Jupiter's own price impact for the quote (a fraction), when it reports one. */
  readonly priceImpactPct: unknown;
}

/**
 * Whether an order's price is fair: no more than 3% worse than a trusted price,
 * plus the token's own transfer fee and the swap fee. A better price is always
 * fine. With no trusted price to compare, Jupiter's price impact must stay under
 * 5%.
 */
export function orderPriceAcceptable(input: OrderPriceInput): boolean {
  const tokens = Number(input.buying ? input.outputRaw : input.inputRaw) / 10 ** input.decimals;
  const usdc = Number(input.buying ? input.inputRaw : input.outputRaw) / 1e6;
  if (!(tokens > 0) || !(usdc > 0)) return false;
  const references = input.referencesUsd.filter(value => Number.isFinite(value) && value > 0);
  if (references.length) {
    const price = usdc / tokens;
    const allowedBps = MARKET_PRICE_ALLOWANCE_BPS + input.transferFeeBps + input.swapFeeBps;
    return references.some(reference =>
      (input.buying ? price / reference - 1 : 1 - price / reference) * 10_000 <= allowedBps);
  }
  const impact = Number(input.priceImpactPct);
  return Number.isFinite(impact) && impact <= MAX_PRICE_IMPACT;
}
