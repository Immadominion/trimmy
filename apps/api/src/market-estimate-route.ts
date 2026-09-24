import type { FastifyInstance } from 'fastify';
import { MarketEstimateError } from './market-estimates.js';
import type { MarketEstimateInput, MarketEstimates } from './market-estimates.js';

export const MARKET_ESTIMATE_ROUTE = '/v1/markets/estimate';
/** Public, quote-only research pair. No identity, wallet or execution input. */
export function registerMarketEstimateRoute(app: FastifyInstance, estimates?: MarketEstimates): void {
  app.get<{Querystring: MarketEstimateInput}>(MARKET_ESTIMATE_ROUTE, {
    exposeHeadRoute: false,
    schema: {querystring: {
      type: 'object', additionalProperties: false, required: ['inputAsset', 'outputAsset', 'amountRaw'],
      properties: {
        inputAsset: {type: 'string', enum: ['SOL', 'USDC']}, outputAsset: {type: 'string', enum: ['SOL', 'USDC']},
        amountRaw: {type: 'string', pattern: '^[1-9][0-9]{0,19}$', maxLength: 20},
      },
    }},
  }, async (request, reply) => {
    try {
      if (!estimates) throw new MarketEstimateError('MARKET_UNAVAILABLE');
      return await estimates.estimate(request.query);
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
