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
  /** Jupiter's market price per whole token before any display multiplier, or null. */
  readonly referenceUsd: number | null;
  /** Jupiter's own price impact for the quote (a fraction), when it reports one. */
  readonly priceImpactPct: unknown;
}

/**
 * Whether an order's price is fair: no more than 3% worse than Jupiter's market
 * price, plus the token's own transfer fee and the swap fee. A better price is
 * always fine. With no market price to compare, Jupiter's price impact must stay
 * under 5%.
 */
export function orderPriceAcceptable(input: OrderPriceInput): boolean {
  const tokens = Number(input.buying ? input.outputRaw : input.inputRaw) / 10 ** input.decimals;
  const usdc = Number(input.buying ? input.inputRaw : input.outputRaw) / 1e6;
  if (!(tokens > 0) || !(usdc > 0)) return false;
  if (input.referenceUsd !== null && Number.isFinite(input.referenceUsd) && input.referenceUsd > 0) {
    const price = usdc / tokens;
    const worseBps = (input.buying ? price / input.referenceUsd - 1 : 1 - price / input.referenceUsd) * 10_000;
    return worseBps <= MARKET_PRICE_ALLOWANCE_BPS + input.transferFeeBps + input.swapFeeBps;
  }
  const impact = Number(input.priceImpactPct);
  return Number.isFinite(impact) && impact <= MAX_PRICE_IMPACT;
}
