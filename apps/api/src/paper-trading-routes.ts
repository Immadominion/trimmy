import { createHash, randomUUID } from 'node:crypto';
import {
  DomainError, PAPER_FIXED_SCALE, PAPER_FIXED_SCALE_DIGITS, PAPER_STARTING_CASH_MICROS, parsePaperAssetId, parsePaperOrderAction,
  parsePaperFixed, parsePaperOrderAmount, parsePaperVariantMint,
} from '@trimmy/domain';
import type { PaperOrderAction, PaperOrderAmount } from '@trimmy/domain';
import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { PaperPriceError } from './paper-price-reader.js';
import type { PaperPriceReader } from './paper-price-reader.js';
import {
  acceptsPaperPortfolioV2, PAPER_PORTFOLIO_V2_MEDIA_TYPE, valuePaperPortfolio,
} from './paper-portfolio-valuation.js';
import type { PaperPortfolioValuation } from './paper-portfolio-valuation.js';
import { PracticeAuthenticationUnavailable } from './practice-session-routes.js';
import { PaperTradingRepositoryError, parsePaperUuid } from './paper-trading-repository.js';
import type {
  PaperCommittedOrder, PaperOrderPreview, PaperPortfolio, PaperResetReceipt, PaperTradingRepository,
} from './paper-trading-repository.js';
import { GuestSessionError } from './guest-session-repository.js';
import { GUEST_RATE_WINDOW_SECONDS } from './guest-rate-windows.js';

export const PAPER_PORTFOLIO_ROUTE = '/v1/account/paper/portfolio';
export const PAPER_PREVIEW_ROUTE = '/v1/account/paper/orders/preview';
export const PAPER_COMMIT_ROUTE = '/v1/account/paper/orders/commit';
export const PAPER_RESET_ROUTE = '/v1/account/paper/reset';
export const PAPER_RESET_CONFIRMATION = 'reset my paper desk';

export interface PaperTradingAdapters {
  readonly repository: PaperTradingRepository;
  readonly prices: PaperPriceReader;
  readonly authenticate: (request: FastifyRequest) => Promise<{readonly userId: string} | null>;
  readonly newId?: () => string;
}

export function paperTradingEnabled(adapters?: PaperTradingAdapters): adapters is PaperTradingAdapters {
  return typeof adapters?.authenticate === 'function' && typeof adapters.repository?.getPortfolio === 'function' &&
    typeof adapters.repository?.findPreviewRequest === 'function' &&
    typeof adapters.repository?.createPreview === 'function' && typeof adapters.repository?.commit === 'function' &&
    typeof adapters.prices?.read === 'function';
}

const noQuery = {type: 'object', additionalProperties: false, properties: {}} as const;
const uuid = {type: 'string', pattern: '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$', maxLength: 36} as const;
const micros = {type: 'string', pattern: '^[1-9][0-9]{0,14}$', maxLength: 15} as const;
const amountSchema = {
  oneOf: [
    {type: 'object', additionalProperties: false, required: ['kind', 'paperMicros'],
      properties: {kind: {const: 'paper_amount'}, paperMicros: micros}},
    {type: 'object', additionalProperties: false, required: ['kind', 'quantityMicros'],
      properties: {kind: {const: 'share_quantity'}, quantityMicros: micros}},
  ],
} as const;

function problem(reply: FastifyReply, request: FastifyRequest, status: number, code: string, message: string) {
  return reply.code(status).send({error: {code, message, requestId: request.id}});
}

function addVary(reply: FastifyReply, name: string): void {
  const prior = reply.getHeader('vary');
  const values = (Array.isArray(prior) ? prior.join(',') : String(prior ?? ''))
    .split(',').map(value => value.trim()).filter(Boolean);
  if (!values.some(value => value === '*' || value.toLowerCase() === name.toLowerCase())) values.push(name);
  reply.header('vary', values.join(', '));
}

function hash(value: string): string { return createHash('sha256').update(value).digest('hex'); }
function previewHash(action: PaperOrderAction, assetId: string, variantMint: string, amount: PaperOrderAmount): string {
  const amountJson = amount.kind === 'paper_amount'
    ? `{"kind":"paper_amount","paperMicros":"${amount.paperMicros}"}`
    : `{"kind":"share_quantity","quantityMicros":"${amount.quantityMicros}"}`;
  return hash(`{"action":"${action}","assetId":"${assetId}","variantMint":"${variantMint}","amount":${amountJson}}`);
}
const commitHash = (previewId: string) => hash(`{"previewId":"${previewId}"}`);
const resetHash = (baseRevision: number) =>
  hash(`{"baseRevision":${baseRevision},"confirm":"${PAPER_RESET_CONFIRMATION}"}`);

function publicPreview(value: PaperOrderPreview) {
  const {requestHash: _requestHash, ...preview} = value;
  return Object.freeze({
    schemaVersion: 1, mode: 'paper' as const, unit: Object.freeze({kind: 'paper' as const, scaleDigits: PAPER_FIXED_SCALE_DIGITS}),
    preview, fees: Object.freeze({paperMicros: '0'}),
    reward: Object.freeze({trimsAwarded: 0, reason: 'Trade completion alone does not award Trims.'}),
    execution: Object.freeze({walletUsed: false, transactionBuilt: false, transactionSigned: false, transactionBroadcast: false}),
  });
}
function publicOrder(value: PaperCommittedOrder) {
  return Object.freeze({
    schemaVersion: 1, mode: 'paper' as const, unit: Object.freeze({kind: 'paper' as const, scaleDigits: PAPER_FIXED_SCALE_DIGITS}),
    order: value, fees: Object.freeze({paperMicros: '0'}),
    reward: Object.freeze({trimsAwarded: 0, reason: 'Trade completion alone does not award Trims.'}),
    execution: Object.freeze({walletUsed: false, transactionBuilt: false, transactionSigned: false, transactionBroadcast: false}),
  });
}
function publicPortfolio(value: PaperPortfolio) {
  return Object.freeze({
    schemaVersion: 1, mode: 'paper' as const,
    unit: Object.freeze({kind: 'paper' as const, scaleDigits: value.scaleDigits}),
    revision: value.revision, startingCashPaperMicros: value.startingCashPaperMicros,
    cashPaperMicros: value.cashPaperMicros, openedAt: value.openedAt, updatedAt: value.updatedAt,
    positions: value.positions, recentOrders: value.recentOrders,
    valuation: Object.freeze({status: 'not_included' as const,
      note: 'Position value needs a fresh market read; stored cost basis is not a current price.'}),
  });
}
function publicPortfolioV2(value: PaperPortfolio, valuation: PaperPortfolioValuation) {
  return Object.freeze({
    schemaVersion: 2, mode: 'paper' as const,
    unit: Object.freeze({kind: 'paper' as const, scaleDigits: value.scaleDigits}),
    revision: value.revision, startingCashPaperMicros: value.startingCashPaperMicros,
    cashPaperMicros: value.cashPaperMicros, openedAt: value.openedAt, updatedAt: value.updatedAt,
    positions: value.positions, recentOrders: value.recentOrders, valuation,
  });
}

function publicReset(value: PaperResetReceipt) {
  return Object.freeze({
    schemaVersion: 1,
    mode: 'paper' as const,
    unit: Object.freeze({kind: 'paper' as const, scaleDigits: PAPER_FIXED_SCALE_DIGITS}),
    reset: Object.freeze({
      mutationId: value.mutationId,
      previousRevision: value.previousRevision,
      revision: value.revision,
      resetAt: value.resetAt,
    }),
    portfolioAtReset: Object.freeze({
      revision: value.revision,
      startingCashPaperMicros: PAPER_STARTING_CASH_MICROS.toString(),
      cashPaperMicros: value.cashPaperMicros,
      positions: Object.freeze([]),
      recentOrders: Object.freeze([]),
    }),
  });
}

function repositoryProblem(error: PaperTradingRepositoryError, reply: FastifyReply, request: FastifyRequest) {
  const map: Partial<Record<PaperTradingRepositoryError['code'], readonly [number, string]>> = {
    PAPER_INPUT_INVALID: [400, 'Paper order request is invalid.'],
    PAPER_ACCOUNT_NOT_FOUND: [404, 'Paper account is unavailable.'],
    PAPER_ACCOUNT_UNAVAILABLE: [403, 'Paper trading is unavailable for this account.'],
    PAPER_IDEMPOTENCY_CONFLICT: [409, 'That request key already belongs to another paper order.'],
    PAPER_PREVIEW_NOT_FOUND: [404, 'That paper preview is unavailable.'],
    PAPER_PREVIEW_EXPIRED: [409, 'That paper price expired. Review the order again.'],
    PAPER_PREVIEW_ALREADY_COMMITTED: [409, 'That paper preview has already been used.'],
    PAPER_PORTFOLIO_CHANGED: [409, 'Your paper desk changed. Review the order again.'],
    PAPER_CASH_INSUFFICIENT: [409, 'There is not enough paper on this desk.'],
    PAPER_POSITION_INSUFFICIENT: [409, 'There are not enough paper shares on this desk.'],
    PAPER_TRIM_NOT_WINNING: [409, 'Trim is available only for a profitable part of a position.'],
    PAPER_TRIM_MUST_BE_PARTIAL: [409, 'A trim keeps part of the position. Use sell to close it.'],
    PAPER_ORDER_TOO_SMALL: [400, 'That paper order is too small at this price.'],
    PAPER_LIMIT_REACHED: [409, 'This paper desk has reached its supported limit.'],
  };
  const [status, message] = map[error.code] ?? [503, 'Paper trading is unavailable. Try again.'];
  return problem(reply, request, status, error.code in map ? error.code : 'PAPER_TRADING_UNAVAILABLE', message);
}

function resetRepositoryProblem(error: PaperTradingRepositoryError, reply: FastifyReply, request: FastifyRequest) {
  const map: Partial<Record<PaperTradingRepositoryError['code'], readonly [number, string]>> = {
    PAPER_INPUT_INVALID: [400, 'Paper reset request is invalid.'],
    PAPER_ACCOUNT_NOT_FOUND: [404, 'Paper account is unavailable.'],
    PAPER_ACCOUNT_UNAVAILABLE: [403, 'Paper trading is unavailable for this account.'],
    PAPER_IDEMPOTENCY_CONFLICT: [409, 'That reset request ID is already in use.'],
    PAPER_PORTFOLIO_CHANGED: [409, 'Your paper desk changed. Refresh before resetting it.'],
    PAPER_RESET_NOT_NEEDED: [409, 'This paper desk is already fresh.'],
    PAPER_REVISION_EXHAUSTED: [409, 'This paper desk cannot accept another revision.'],
  };
  const [status, message] = map[error.code] ?? [503, 'Paper reset is unavailable. Try again.'];
  return problem(reply, request, status, error.code in map ? error.code : 'PAPER_RESET_UNAVAILABLE', message);
}

function guestAuthenticationProblem(error: GuestSessionError, reply: FastifyReply, request: FastifyRequest,
  retryAfterSeconds: number) {
  if (error.code === 'GUEST_SESSION_RATE_LIMITED') {
    reply.header('retry-after', String(retryAfterSeconds));
    return problem(reply, request, 429, error.code, 'This guest desk is making requests too quickly. Try again shortly.');
  }
  if (error.code === 'GUEST_SESSION_UNAVAILABLE' || error.code === 'GUEST_SESSION_STORAGE_INVALID' ||
      error.code === 'GUEST_SESSION_RUNTIME_ROLE_INVALID') {
    return problem(reply, request, 503, 'PAPER_TRADING_UNAVAILABLE', 'Paper trading is unavailable. Try again.');
  }
  if (error.code === 'GUEST_SESSION_EXPIRED' || error.code === 'GUEST_SESSION_REVOKED') {
    return problem(reply, request, 401, error.code, 'This guest session is no longer available.');
  }
  return problem(reply, request, 401, 'PAPER_TRADING_UNAUTHENTICATED', 'An active guest session or verified account is required.');
}

export function registerPaperTradingRoutes(app: FastifyInstance, options?: PaperTradingAdapters): void {
  const adapters = paperTradingEnabled(options) ? options : undefined;
  const newId = adapters?.newId ?? randomUUID;

  app.get(PAPER_PORTFOLIO_ROUTE, {schema: {querystring: noQuery}}, async (request, reply) => {
    reply.header('cache-control', 'no-store');
    addVary(reply, 'Accept');
    if (!adapters) return problem(reply, request, 503, 'PAPER_TRADING_UNAVAILABLE', 'Paper trading is unavailable.');
    try {
      const account = await adapters.authenticate(request);
      if (!account) return problem(reply, request, 401, 'PAPER_TRADING_UNAUTHENTICATED', 'A verified account is required.');
      const portfolio = await adapters.repository.getPortfolio(account.userId);
      if (!acceptsPaperPortfolioV2(request.headers.accept)) return publicPortfolio(portfolio);
      const valuation = await valuePaperPortfolio(portfolio, adapters.prices);
      reply.type(PAPER_PORTFOLIO_V2_MEDIA_TYPE);
      return publicPortfolioV2(portfolio, valuation);
    } catch (error) {
      if (error instanceof GuestSessionError) {
        return guestAuthenticationProblem(error, reply, request, GUEST_RATE_WINDOW_SECONDS.paperRead);
      }
      if (error instanceof PaperTradingRepositoryError) return repositoryProblem(error, reply, request);
      if (error instanceof PracticeAuthenticationUnavailable) {
        return problem(reply, request, 503, 'PAPER_TRADING_UNAVAILABLE', 'Paper trading is unavailable.');
      }
      request.log.error({errorCode: 'PAPER_PORTFOLIO_FAILED'}, 'paper portfolio failed');
      return problem(reply, request, 503, 'PAPER_TRADING_UNAVAILABLE', 'Paper trading is unavailable. Try again.');
    }
  });

  app.post(PAPER_PREVIEW_ROUTE, {
    bodyLimit: 2048,
    schema: {querystring: noQuery, body: {
      type: 'object', additionalProperties: false,
      required: ['schemaVersion', 'requestId', 'action', 'assetId', 'variantMint', 'amount'],
      properties: {schemaVersion: {const: 1}, requestId: uuid, action: {enum: ['buy', 'sell', 'trim']},
        assetId: {type: 'string', pattern: '^[a-z0-9]+(?:-[a-z0-9]+)*$', maxLength: 100},
        variantMint: {type: 'string', pattern: '^[1-9A-HJ-NP-Za-km-z]{32,44}$', maxLength: 44}, amount: amountSchema},
    }},
  }, async (request, reply) => {
    if (!adapters) return problem(reply, request, 503, 'PAPER_TRADING_UNAVAILABLE', 'Paper trading is unavailable.');
    try {
      const account = await adapters.authenticate(request);
      if (!account) return problem(reply, request, 401, 'PAPER_TRADING_UNAUTHENTICATED', 'A verified account is required.');
      const body = request.body as Record<string, unknown>;
      const requestId = parsePaperUuid(body['requestId']);
      const action = parsePaperOrderAction(body['action']);
      const assetId = parsePaperAssetId(body['assetId']);
      const variantMint = parsePaperVariantMint(body['variantMint']);
      const amount = parsePaperOrderAmount(body['amount']);
      const requestHash = previewHash(action, assetId, variantMint, amount);
      const prior = await adapters.repository.findPreviewRequest(account.userId, requestId);
      if (prior) {
        if (prior.requestHash !== requestHash) {
          return problem(reply, request, 409, 'PAPER_IDEMPOTENCY_CONFLICT',
            'That request ID already belongs to another paper preview.');
        }
        return publicPreview(prior);
      }
      const price = await adapters.prices.read({assetId, variantMint});
      // Keep the immutable ledger's share-only sale contract. Translate a cash
      // target using this server-accepted price before creating the preview.
      // The request hash above retains the original intent for exact replay.
      const priceMicros = parsePaperFixed(price.pricePaperMicros, {positive: true});
      const ledgerAmount = action === 'sell' && amount.kind === 'paper_amount'
        ? parsePaperOrderAmount({kind: 'share_quantity', quantityMicros:
          ((BigInt(amount.paperMicros) * PAPER_FIXED_SCALE + priceMicros - 1n) / priceMicros).toString()})
        : amount;
      const created = await adapters.repository.createPreview(account.userId,
        {id: newId(), requestId, requestHash, action, amount: ledgerAmount, price});
      return publicPreview(created);
    } catch (error) {
      if (error instanceof GuestSessionError) {
        return guestAuthenticationProblem(error, reply, request, GUEST_RATE_WINDOW_SECONDS.paperPreview);
      }
      if (error instanceof DomainError || error instanceof PaperTradingRepositoryError) {
        return error instanceof PaperTradingRepositoryError
          ? repositoryProblem(error, reply, request)
          : problem(reply, request, 400, 'PAPER_INPUT_INVALID', 'Paper order request is invalid.');
      }
      if (error instanceof PaperPriceError) {
        const status = error.code === 'PAPER_PRICE_INVALID' ? 400
          : error.code === 'PAPER_ASSET_UNAVAILABLE' ? 409
            : error.failureKind === 'rate_limited' ? 429
              : error.failureKind === 'timeout' ? 504 : 503;
        return problem(reply, request, status, error.code, error.message);
      }
      if (error instanceof PracticeAuthenticationUnavailable) {
        return problem(reply, request, 503, 'PAPER_TRADING_UNAVAILABLE', 'Paper trading is unavailable.');
      }
      request.log.error({errorCode: 'PAPER_PREVIEW_FAILED'}, 'paper preview failed');
      return problem(reply, request, 503, 'PAPER_TRADING_UNAVAILABLE', 'Paper trading is unavailable. Try again.');
    }
  });

  app.post(PAPER_COMMIT_ROUTE, {
    bodyLimit: 1024,
    schema: {querystring: noQuery, body: {
      type: 'object', additionalProperties: false, required: ['schemaVersion', 'previewId', 'idempotencyKey'],
      properties: {schemaVersion: {const: 1}, previewId: uuid, idempotencyKey: uuid},
    }},
  }, async (request, reply) => {
    if (!adapters) return problem(reply, request, 503, 'PAPER_TRADING_UNAVAILABLE', 'Paper trading is unavailable.');
    try {
      const account = await adapters.authenticate(request);
      if (!account) return problem(reply, request, 401, 'PAPER_TRADING_UNAUTHENTICATED', 'A verified account is required.');
      const body = request.body as Record<string, unknown>;
      const previewId = parsePaperUuid(body['previewId']);
      const idempotencyKey = parsePaperUuid(body['idempotencyKey']);
      const committed = await adapters.repository.commit(account.userId,
        {orderId: newId(), previewId, idempotencyKey, requestHash: commitHash(previewId)});
      return publicOrder(committed);
    } catch (error) {
      if (error instanceof GuestSessionError) {
        return guestAuthenticationProblem(error, reply, request, GUEST_RATE_WINDOW_SECONDS.paperCommit);
      }
      if (error instanceof PaperTradingRepositoryError) return repositoryProblem(error, reply, request);
      if (error instanceof PracticeAuthenticationUnavailable) {
        return problem(reply, request, 503, 'PAPER_TRADING_UNAVAILABLE', 'Paper trading is unavailable.');
      }
      request.log.error({errorCode: 'PAPER_COMMIT_FAILED'}, 'paper commit failed');
      return problem(reply, request, 503, 'PAPER_TRADING_UNAVAILABLE', 'Paper trading is unavailable. Try again.');
    }
  });

  app.post(PAPER_RESET_ROUTE, {
    bodyLimit: 512,
    schema: {querystring: noQuery, body: {
      type: 'object', additionalProperties: false,
      required: ['schemaVersion', 'mutationId', 'baseRevision', 'confirm'],
      properties: {
        schemaVersion: {const: 1}, mutationId: uuid,
        baseRevision: {type: 'integer', minimum: 0, maximum: Number.MAX_SAFE_INTEGER},
        confirm: {type: 'string', maxLength: 64},
      },
    }},
  }, async (request, reply) => {
    if (!adapters || typeof adapters.repository.reset !== 'function') {
      return problem(reply, request, 503, 'PAPER_RESET_UNAVAILABLE', 'Paper reset is unavailable.');
    }
    try {
      const account = await adapters.authenticate(request);
      if (!account) {
        return problem(reply, request, 401, 'PAPER_TRADING_UNAUTHENTICATED',
          'An active guest session or verified account is required.');
      }
      const body = request.body as Record<string, unknown>;
      if (body['confirm'] !== PAPER_RESET_CONFIRMATION ||
          !Number.isSafeInteger(body['baseRevision']) || (body['baseRevision'] as number) < 0) {
        return problem(reply, request, 400, 'PAPER_INPUT_INVALID',
          'Paper reset requires its exact written confirmation and current revision.');
      }
      const mutationId = parsePaperUuid(body['mutationId']);
      const baseRevision = body['baseRevision'] as number;
      const receipt = await adapters.repository.reset(account.userId, {
        mutationId, baseRevision, requestHash: resetHash(baseRevision),
      });
      return publicReset(receipt);
    } catch (error) {
      if (error instanceof GuestSessionError) {
        return guestAuthenticationProblem(error, reply, request, GUEST_RATE_WINDOW_SECONDS.paperReset);
      }
      if (error instanceof PaperTradingRepositoryError) return resetRepositoryProblem(error, reply, request);
      if (error instanceof PracticeAuthenticationUnavailable) {
        return problem(reply, request, 503, 'PAPER_RESET_UNAVAILABLE', 'Paper reset is unavailable.');
      }
      request.log.error({errorCode: 'PAPER_RESET_FAILED'}, 'paper reset failed');
      return problem(reply, request, 503, 'PAPER_RESET_UNAVAILABLE', 'Paper reset is unavailable. Try again.');
    }
  });
}
