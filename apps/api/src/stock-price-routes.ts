import type { FastifyInstance } from 'fastify';
import { findStockTradingAssetByMint } from './stock-trading-catalog.js';
import { holdingPrice } from './stock-token-prices.js';
import type { TokenPrice } from './stock-token-prices.js';

export const STOCK_PRICES_ROUTE = '/v1/markets/stocks/prices';

export interface StockPriceReader {
  read(mints: readonly string[]): Promise<ReadonlyMap<string, TokenPrice>>;
}

const MINT = '[1-9A-HJ-NP-Za-km-z]{32,44}';

/**
 * What one displayed share of each stock token is worth, for valuing holdings:
 * a deep market's price, else the issuer's, else a liquid market's
 * (stock-token-prices.ts). A token
 * with neither is left out, so the app shows no value rather than a wrong one.
 * Only Trimmy's stock tokens are priced. Display only: orders are priced when
 * quoted.
 */
export function registerStockPriceRoutes(app: FastifyInstance, prices?: StockPriceReader, now: () => number = Date.now): void {
  app.get<{Querystring: {mints: string}}>(STOCK_PRICES_ROUTE, {
    exposeHeadRoute: false,
    schema: {querystring: {type: 'object', additionalProperties: false, required: ['mints'],
      properties: {mints: {type: 'string', pattern: `^${MINT}(,${MINT}){0,49}$`}}}},
  }, async (request, reply) => {
    if (!prices) {
      return reply.code(503).send({error: {code: 'STOCK_PRICES_UNAVAILABLE', message: 'Prices are unavailable.', requestId: request.id}});
    }
    const mints = [...new Set(request.query.mints.split(','))].filter(mint => findStockTradingAssetByMint(mint) !== undefined);
    const read = mints.length ? await prices.read(mints) : new Map<string, TokenPrice>();
    const rows = mints.flatMap(mint => {
      const price = holdingPrice(read.get(mint));
      return price ? [{mint, usdPerShare: price.usdPerShare, source: price.source,
        asOf: price.asOf === null ? null : new Date(price.asOf).toISOString()}] : [];
    });
    void reply.header('cache-control', 'public, max-age=30');
    return {schema: 1, observedAt: new Date(now()).toISOString(), prices: rows};
  });
}
