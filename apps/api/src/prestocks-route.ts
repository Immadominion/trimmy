import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { PreStocksError } from './prestocks-reader.js';
import type { PreStocks } from './prestocks-reader.js';

export const PRESTOCKS_ROUTE = '/v1/markets/prestocks';

function failure(error: unknown, request: FastifyRequest, reply: FastifyReply) {
  const safe = error instanceof PreStocksError ? error : new PreStocksError('PRESTOCKS_PROVIDER_UNAVAILABLE');
  const code = safe.code;
  const status = code === 'PRESTOCKS_RATE_LIMITED' ? 429 : code === 'PRESTOCKS_TIMEOUT' ? 504 :
    code === 'PRESTOCKS_UNAVAILABLE' ? 503 : 502;
  return reply.code(status).send({error: {code, message: safe.message, requestId: request.id}});
}

/**
 * A read-only pre-IPO catalog. It supplies indicative marks and metadata; it
 * never adds an asset to any approved trading catalog and enables no order.
 */
export function registerPreStocksRoute(app: FastifyInstance, prestocks?: PreStocks): void {
  app.get(PRESTOCKS_ROUTE, {
    exposeHeadRoute: false,
    schema: {querystring: {type: 'object', additionalProperties: false, properties: {}}},
    onRequest: async (_request, reply) => { reply.header('cache-control', 'no-store'); },
  }, async (request, reply) => {
    try {
      if (!prestocks) throw new PreStocksError('PRESTOCKS_UNAVAILABLE');
      return await prestocks.catalog();
    } catch (error) { return failure(error, request, reply); }
  });
}
