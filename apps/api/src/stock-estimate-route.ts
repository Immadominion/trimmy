import type { FastifyInstance } from 'fastify';
import { MarketEstimateError } from './jupiter-quote-reader.js';
import { STOCK_ASSET_ID_PATTERN, STOCK_MINT_PATTERN } from './stock-trading-catalog.js';
import { validateStockEstimateInput } from './stock-estimates.js';
import type { StockEstimateInput, StockEstimates } from './stock-estimates.js';

export const STOCK_ESTIMATE_ROUTE = '/v1/markets/stocks/estimate';
export function registerStockEstimateRoute(app: FastifyInstance, options: {readonly stockEstimates?: StockEstimates} = {}): void {
  app.get<{Querystring: StockEstimateInput}>(STOCK_ESTIMATE_ROUTE, {
    exposeHeadRoute: false,
    schema: {querystring: {
      type: 'object', additionalProperties: false, required: ['assetId', 'variantMint', 'side', 'amountRaw'],
      properties: {
        // Any token shape here; the handler checks it is a tradeable token.
        assetId: {type: 'string', maxLength: 100, pattern: STOCK_ASSET_ID_PATTERN.source},
        variantMint: {type: 'string', pattern: STOCK_MINT_PATTERN.source},
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
