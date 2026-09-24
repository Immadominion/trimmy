import type { FastifyInstance } from 'fastify';
import { MarketEstimateError } from './jupiter-quote-reader.js';
import type { RaydiumStockQuotes } from './raydium-stock-quotes.js';
import { STOCK_ESTIMATE_ASSET, validateStockEstimateInput } from './stock-estimates.js';
import type { StockEstimateInput } from './stock-estimates.js';

export const RAYDIUM_STOCK_QUOTE_ROUTE = '/v1/markets/stocks/quotes/raydium';

export function registerRaydiumStockQuoteRoute(app: FastifyInstance,
  options: {readonly quotes?: RaydiumStockQuotes} = {}): void {
  app.get<{Querystring: StockEstimateInput}>(RAYDIUM_STOCK_QUOTE_ROUTE, {
    exposeHeadRoute: false,
    schema: {querystring: {
      type: 'object', additionalProperties: false,
      required: ['assetId', 'variantMint', 'side', 'amountRaw'],
      properties: {
        assetId: {type: 'string', const: STOCK_ESTIMATE_ASSET.assetId},
        variantMint: {type: 'string', const: STOCK_ESTIMATE_ASSET.variantMint},
        side: {type: 'string', enum: ['buy', 'sell']},
        amountRaw: {type: 'string', pattern: '^[1-9][0-9]{0,8}$', maxLength: 9},
      },
    }},
  }, async (request, reply) => {
    reply.header('cache-control', 'no-store');
    try {
      validateStockEstimateInput(request.query);
      if (!options.quotes) throw new MarketEstimateError('MARKET_UNAVAILABLE');
      return await options.quotes.quote(request.query);
    } catch (error) {
      const safe = error instanceof MarketEstimateError ? error : new MarketEstimateError('MARKET_PROVIDER_UNAVAILABLE');
      const status = safe.code === 'MARKET_INPUT_INVALID' ? 400 : safe.code === 'MARKET_RATE_LIMITED' ? 429 :
        safe.code === 'MARKET_TIMEOUT' || safe.code === 'MARKET_ESTIMATE_STALE' ? 504 :
        safe.code === 'MARKET_UNAVAILABLE' ? 503 : 502;
      return reply.code(status).send({error: {code: safe.code, message: safe.message, requestId: request.id}});
    }
  });
}
