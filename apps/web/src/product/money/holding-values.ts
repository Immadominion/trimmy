import {useEffect, useState} from 'react';
import type {ProductMarketClient} from '../market-client.js';
import type {HoldingsSnapshot, WalletStockBalance} from './wallet-models.js';

/**
 * What a held token is worth: its shares (the display amount) times that token's
 * trusted price per share from the API: the issuer's price, else a liquid
 * market's. A token's last trade is not used on its own, because a token that
 * barely trades can show many times its share price. Display only; a sale is
 * still quoted before it is signed.
 */
export type HoldingPrices = ReadonlyMap<string, number>;
const REFRESH_MS = 60_000;
/** After failed refreshes the last prices serve this long, then values go blank. */
const KEEP_MS = 10 * 60_000;
const none: HoldingPrices = new Map();

export function useHoldingPrices(market: Pick<ProductMarketClient, 'prices'>, holdings: HoldingsSnapshot | null): HoldingPrices {
  const key = holdings ? [...new Set(holdings.stockTokens.map(token => token.mint))].sort().join(',') : '';
  const [state, setState] = useState<{key: string; prices: HoldingPrices; at: number}>({key: '', prices: none, at: 0});
  const [tick, setTick] = useState(0);
  useEffect(() => {const timer = window.setInterval(() => setTick(value => value + 1), REFRESH_MS); return () => clearInterval(timer);}, []);
  useEffect(() => {
    if (!key) return;
    const controller = new AbortController();
    const mints = key.split(',');
    const reads = [];
    for (let index = 0; index < mints.length; index += 50) reads.push(market.prices(mints.slice(index, index + 50), {signal: controller.signal}));
    void Promise.all(reads).then(parts => {
      if (controller.signal.aborted) return;
      setState({key, prices: new Map(parts.flatMap(part => [...part])), at: Date.now()});
    }, () => {
      if (controller.signal.aborted) return;
      setState(prior => prior.key === key && Date.now() - prior.at < KEEP_MS ? prior : {key, prices: none, at: prior.at});
    });
    return () => controller.abort();
  }, [market, key, tick]);
  return key && state.key === key ? state.prices : none;
}

export function holdingValue(holding: WalletStockBalance, prices: HoldingPrices): number | null {
  const price = prices.get(holding.mint);
  if (price === undefined || holding.displayAmount === null) return null;
  const tokens = Number(holding.displayAmount);
  return Number.isFinite(tokens) && tokens >= 0 ? tokens * price : null;
}

/** The value of every stock token held, or null while any one of them has no price. */
export function stocksValue(holdings: HoldingsSnapshot, prices: HoldingPrices): number | null {
  let total = 0;
  for (const holding of holdings.stockTokens) {
    const value = holdingValue(holding, prices);
    if (value === null) return null;
    total += value;
  }
  return total;
}
