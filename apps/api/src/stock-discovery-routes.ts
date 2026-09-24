import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { StockDiscoveryError } from './stock-discovery.js';
import type { StockDiscovery } from './stock-discovery.js';

export const STOCK_SEARCH_ROUTE = '/v1/markets/stocks/search';
export const STOCK_VARIANTS_ROUTE = '/v1/markets/stocks/variants';

function failure(error: unknown, request: FastifyRequest, reply: FastifyReply) {
  const safe = error instanceof StockDiscoveryError ? error : new StockDiscoveryError('STOCK_PROVIDER_UNAVAILABLE');
  const code = safe.code;
  const status = code === 'STOCK_INPUT_INVALID' ? 400 : code === 'STOCK_RATE_LIMITED' ? 429 :
    code === 'STOCK_TIMEOUT' ? 504 :
    code === 'STOCK_DISCOVERY_UNAVAILABLE' || code === 'STOCK_PROVIDER_AUTH_FAILED' ? 503 : 502;
  return reply.code(status).send({error: {code, message: safe.message, requestId: request.id}});
}

/** Discovery supplies provider metadata. It never adds assets to the approved trading catalog. */
export function registerStockDiscoveryRoutes(app: FastifyInstance, discovery?: StockDiscovery): void {
  app.get<{Querystring: {offset?: string}}>('/v1/markets/stocks/catalog', {
    exposeHeadRoute: false,
    schema: {querystring: {type: 'object', additionalProperties: false,
      properties: {offset: {type: 'string', pattern: '^(0|[1-9][0-9]{0,4})$'}}}},
  }, async (request, reply) => {
    try {
      if (!discovery?.catalog) throw new StockDiscoveryError('STOCK_DISCOVERY_UNAVAILABLE');
      return await discovery.catalog(Number(request.query.offset ?? 0));
    } catch (error) { return failure(error, request, reply); }
  });

  app.get<{Querystring: {query: string; limit?: string}}>(STOCK_SEARCH_ROUTE, {
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
        throw new StockDiscoveryError('STOCK_INPUT_INVALID');
      }
      if (!discovery) throw new StockDiscoveryError('STOCK_DISCOVERY_UNAVAILABLE');
      return await discovery.search({query: request.query.query,
        ...(request.query.limit === undefined ? {} : {limit: Number(request.query.limit)})});
    } catch (error) { return failure(error, request, reply); }
  });

  app.get<{Querystring: {assetId: string}}>(STOCK_VARIANTS_ROUTE, {
    exposeHeadRoute: false,
    schema: {querystring: {
      type: 'object', additionalProperties: false, required: ['assetId'],
      properties: {assetId: {type: 'string', minLength: 1, maxLength: 100, pattern: '^[a-z0-9]+(?:-[a-z0-9]+)*$'}},
    }},
  }, async (request, reply) => {
    try {
      if (!discovery) throw new StockDiscoveryError('STOCK_DISCOVERY_UNAVAILABLE');
      return await discovery.variants({assetId: request.query.assetId});
    } catch (error) { return failure(error, request, reply); }
  });
}
