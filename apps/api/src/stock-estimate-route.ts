import type { FastifyInstance } from 'fastify';
import { MarketEstimateError } from './jupiter-quote-reader.js';
import { STOCK_TRADING_ASSETS } from './stock-trading-catalog.js';
import { validateStockEstimateInput } from './stock-estimates.js';
import type { StockEstimateInput, StockEstimates } from './stock-estimates.js';

export const STOCK_ESTIMATE_ROUTE = '/v1/markets/stocks/estimate';
export function registerStockEstimateRoute(app: FastifyInstance, options: {readonly stockEstimates?: StockEstimates} = {}): void {
  app.get<{Querystring: StockEstimateInput}>(STOCK_ESTIMATE_ROUTE, {
    exposeHeadRoute: false,
    schema: {querystring: {
      type: 'object', additionalProperties: false, required: ['assetId', 'variantMint', 'side', 'amountRaw'],
      properties: {
        assetId: {type: 'string', enum: STOCK_TRADING_ASSETS.map(asset => asset.assetId)},
        variantMint: {type: 'string', enum: STOCK_TRADING_ASSETS.map(asset => asset.mint)},
        side: {type: 'string', enum: ['buy', 'sell']},
        amountRaw: {type: 'string', pattern: '^[1-9][0-9]{0,8}$', maxLength: 9},
      },
    }},
  }, async (request, reply) => {
    reply.header('cache-control', 'no-store');
    try {
      validateStockEstimateInput(request.query);
      if (!options.stockEstimates) throw new MarketEstimateError('MARKET_UNAVAILABLE');
      return await options.stockEstimates.estimate(request.query);
    } catch (error) {
      const safe = error instanceof MarketEstimateError ? error : new MarketEstimateError('MARKET_PROVIDER_UNAVAILABLE');
      const code = safe.code;
      const status = code === 'MARKET_INPUT_INVALID' ? 400 : code === 'MARKET_RATE_LIMITED' ? 429 :
        code === 'MARKET_TIMEOUT' || code === 'MARKET_ESTIMATE_STALE' ? 504 :
        code === 'MARKET_UNAVAILABLE' || code === 'MARKET_PROVIDER_AUTH_FAILED' ? 503 : 502;
      return reply.code(status).send({error: {code, message: safe.message, requestId: request.id}});
    }
  });
}
