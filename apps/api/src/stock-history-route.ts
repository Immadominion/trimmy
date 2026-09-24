import type {FastifyInstance, FastifyReply, FastifyRequest} from 'fastify';
import {STOCK_HISTORY_ASSET, StockHistoryError, validateStockHistoryInput} from './stock-history.js';
import type {StockHistory, StockHistoryInput} from './stock-history.js';

export const STOCK_HISTORY_ROUTE = '/v1/markets/stocks/history';

function failure(error: unknown, request: FastifyRequest, reply: FastifyReply) {
  const safe = new StockHistoryError(error instanceof StockHistoryError ? error.code : 'STOCK_HISTORY_PROVIDER_UNAVAILABLE');
  const status = safe.code === 'STOCK_HISTORY_INPUT_INVALID' ? 400 : safe.code === 'STOCK_HISTORY_RATE_LIMITED' ? 429 :
    safe.code === 'STOCK_HISTORY_TIMEOUT' ? 504 : safe.code === 'STOCK_HISTORY_UNAVAILABLE' ||
    safe.code === 'STOCK_HISTORY_PROVIDER_AUTH_FAILED' ? 503 : 502;
  return reply.code(status).send({error: {code: safe.code, message: safe.message, requestId: request.id}});
}

/** Public market-data read for one pinned mint. It has no wallet or execution input. */
export function registerStockHistoryRoute(app: FastifyInstance, history?: StockHistory): void {
  app.get<{Querystring: StockHistoryInput}>(STOCK_HISTORY_ROUTE, {
    exposeHeadRoute: false,
    schema: {querystring: {
      type: 'object', additionalProperties: false,
      required: ['assetId', 'variantMint', 'interval', 'fromUnixSeconds', 'toUnixSeconds'],
      properties: {
        assetId: {type: 'string', const: STOCK_HISTORY_ASSET.assetId},
        variantMint: {type: 'string', const: STOCK_HISTORY_ASSET.variantMint},
        interval: {type: 'string', enum: ['1H', '4H', '1D']},
        fromUnixSeconds: {type: 'string', pattern: '^[1-9][0-9]{0,9}$', maxLength: 10},
        toUnixSeconds: {type: 'string', pattern: '^[1-9][0-9]{0,9}$', maxLength: 10},
      },
    }},
  }, async (request, reply) => {
    reply.header('cache-control', 'no-store');
    try {
      if (!history) throw new StockHistoryError('STOCK_HISTORY_UNAVAILABLE');
      // Validate here as well so injected/test adapters cannot receive malformed semantic ranges.
      validateStockHistoryInput(request.query, Math.floor(Date.now() / 1000));
      return await history.history(request.query);
    } catch (error) { return failure(error, request, reply); }
  });
}
