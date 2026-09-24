import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { StockFactsError } from './stock-facts.js';
import type { StockFactsReader, StockInsightInput } from './stock-facts.js';

export const STOCK_CARDS_ROUTE = '/v1/markets/stocks/cards';
export const STOCK_FACTS_ROUTE = '/v1/markets/stocks/facts';

function failure(error: unknown, request: FastifyRequest, reply: FastifyReply) {
  const safe = error instanceof StockFactsError ? error : new StockFactsError('STOCK_FACTS_PROVIDER_UNAVAILABLE');
  const code = safe.code;
  const status = code === 'STOCK_FACTS_INPUT_INVALID' ? 400 : code === 'STOCK_FACTS_RATE_LIMITED' ? 429 :
    code === 'STOCK_FACTS_TIMEOUT' ? 504 :
    code === 'STOCK_FACTS_UNAVAILABLE' || code === 'STOCK_FACTS_PROVIDER_AUTH_FAILED' ? 503 : 502;
  return reply.code(status).send({error: {code, message: safe.message, requestId: request.id}});
}

/** Company facts are reading material for cards and stock pages. They never approve an asset for trading. */
export function registerStockFactsRoutes(app: FastifyInstance, facts?: StockFactsReader): void {
  app.get<{Querystring: {query: string; limit?: string}}>(STOCK_CARDS_ROUTE, {
    exposeHeadRoute: false,
    schema: {querystring: {
      type: 'object', additionalProperties: false, required: ['query'],
      properties: {
        query: {type: 'string', minLength: 1, maxLength: 80},
        limit: {type: 'string', enum: Array.from({length: 20}, (_, index) => String(index + 1))},
      },
    }},
  }, async (request, reply) => {
    try {
      if (request.query.query.trim() !== request.query.query || /[\u0000-\u001f\u007f]/u.test(request.query.query)) {
        throw new StockFactsError('STOCK_FACTS_INPUT_INVALID');
      }
      if (!facts) throw new StockFactsError('STOCK_FACTS_UNAVAILABLE');
      return await facts.cards({query: request.query.query,
        ...(request.query.limit === undefined ? {} : {limit: Number(request.query.limit)})});
    } catch (error) { return failure(error, request, reply); }
  });

  app.get<{Querystring: StockInsightInput}>('/v1/markets/stocks/insight', {
    exposeHeadRoute: false,
    schema: {querystring: {
      type: 'object', additionalProperties: false, required: ['assetId', 'mint', 'period'],
      properties: {
        assetId: {type: 'string', minLength: 1, maxLength: 100, pattern: '^[a-z0-9]+(?:-[a-z0-9]+)*$'},
        mint: {type: 'string', pattern: '^[1-9A-HJ-NP-Za-km-z]{32,44}$'},
        period: {type: 'string', enum: ['day', 'week', 'month', 'year']},
      },
    }},
  }, async (request, reply) => {
    try {
      if (!facts?.insight) throw new StockFactsError('STOCK_FACTS_UNAVAILABLE');
      return await facts.insight(request.query);
    } catch (error) { return failure(error, request, reply); }
  });

  app.get<{Querystring: {assetId: string}}>(STOCK_FACTS_ROUTE, {
    exposeHeadRoute: false,
    schema: {querystring: {
      type: 'object', additionalProperties: false, required: ['assetId'],
      properties: {assetId: {type: 'string', minLength: 1, maxLength: 100, pattern: '^[a-z0-9]+(?:-[a-z0-9]+)*$'}},
    }},
  }, async (request, reply) => {
    try {
      if (!facts) throw new StockFactsError('STOCK_FACTS_UNAVAILABLE');
      return await facts.facts({assetId: request.query.assetId});
    } catch (error) { return failure(error, request, reply); }
  });
}
