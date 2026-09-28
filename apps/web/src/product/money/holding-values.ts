import {useEffect, useState} from 'react';
import type {ProductMarketClient} from '../market-client.js';
import type {HoldingsSnapshot, WalletStockBalance} from './wallet-models.js';

/**
 * What a held token is worth: the token's own market price (the API's variant
 * data for that exact mint) times the tokens held. Display only; a sale is still
 * quoted before it is signed. Pre-IPO tokens can trade far from a share price,
 * so the company's stock price is never used here.
 */
export type HoldingPrices = ReadonlyMap<string, number>;
const REFRESH_MS = 60_000;
const none: HoldingPrices = new Map();

export function useHoldingPrices(market: Pick<ProductMarketClient, 'variants'>, holdings: HoldingsSnapshot | null): HoldingPrices {
  const key = holdings ? [...new Set(holdings.stockTokens.map(token => `${token.assetId} ${token.mint}`))].sort().join('|') : '';
  const [state, setState] = useState<{key: string; prices: HoldingPrices}>({key: '', prices: none});
  const [tick, setTick] = useState(0);
  useEffect(() => {const timer = window.setInterval(() => setTick(value => value + 1), REFRESH_MS); return () => clearInterval(timer);}, []);
  useEffect(() => {
    if (!key) return;
    const held = key.split('|').map(pair => {const [assetId, mint] = pair.split(' '); return {assetId: assetId!, mint: mint!};});
    const controller = new AbortController();
    void Promise.allSettled([...new Set(held.map(token => token.assetId))].map(assetId => market.variants(assetId, {signal: controller.signal}))).then(results => {
      if (controller.signal.aborted) return;
      const prices = new Map<string, number>();
      for (const result of results) {
        if (result.status !== 'fulfilled') continue;
        for (const variant of result.value.variants) {
          const price = variant.market?.priceUsd;
          if (typeof price === 'number' && Number.isFinite(price) && price > 0 && held.some(token => token.mint === variant.mint)) prices.set(variant.mint, price);
        }
      }
      // A failed refresh keeps the last prices for the same holdings rather than blanking them.
      setState(prior => ({key, prices: prices.size || prior.key !== key ? prices : prior.prices}));
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
