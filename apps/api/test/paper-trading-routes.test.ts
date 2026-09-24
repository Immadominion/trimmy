import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { beforeEach, describe, test } from 'node:test';
import { buildApp } from '../src/app.js';
import { createGuestPaperAuthenticator } from '../src/guest-session-routes.js';
import { GuestSessionError } from '../src/guest-session-repository.js';
import type { GuestSessionRepository } from '../src/guest-session-repository.js';
import { PaperPriceError } from '../src/paper-price-reader.js';
import { PAPER_PORTFOLIO_V2_MEDIA_TYPE } from '../src/paper-portfolio-valuation.js';
import {
  PAPER_COMMIT_ROUTE, PAPER_PORTFOLIO_ROUTE, PAPER_PREVIEW_ROUTE, PAPER_RESET_CONFIRMATION, PAPER_RESET_ROUTE,
} from '../src/paper-trading-routes.js';
import { emptyPaperPortfolio, PaperTradingRepositoryError } from '../src/paper-trading-repository.js';
import type {
  PaperCommitCommand, PaperCommittedOrder, PaperOrderPreview, PaperPortfolio, PaperPosition,
  PaperPreviewCommand, PaperResetCommand, PaperResetReceipt, PaperTradingRepository,
} from '../src/paper-trading-repository.js';
import type { AcceptedPaperPrice, PaperPriceReader } from '../src/paper-price-reader.js';

const userId = '70000000-0000-4000-8000-000000000001';
const guestToken = `tg1_${'P'.repeat(43)}`;
const browserOrigin = 'https://trimmy.example';
const mint = 'XsP7xzNPvEHS1m6qfanPUGjNmdMVPckE3hER9uE7p6H';
const secondMint = 'So11111111111111111111111111111111111111112';
const source = {provider: 'tokens-xyz-v1' as const, providerReference: '/v1/assets/apple/variants#apple-xstocks',
  marketSource: 'market', metricsSource: null, providerTimestamps: {asOf: null, lastFetchedAt: null,
    lastTradeAt: null, unit: 'not_declared' as const}, observedAt: '2026-09-20T12:00:00.000Z',
  acceptedAt: '2026-09-20T12:00:00.000Z'};
const price: AcceptedPaperPrice = {assetId: 'apple', variantMint: mint, symbol: 'AAPLx', pricePaperMicros: '200000000',
  source, expiresAt: '2026-09-20T12:00:30.000Z'};

function paperPosition(overrides: Partial<PaperPosition> = {}): PaperPosition {
  return {
    assetId: 'apple', variantMint: mint, symbol: 'AAPLx', quantityMicros: '1500001',
    costBasisPaperMicros: '250000000', averageCostPricePaperMicros: '166666555',
    realizedGainPaperMicros: '0', lockedGainPaperMicros: '0', updatedAt: '2026-09-20T12:00:00.000Z',
    ...overrides,
  };
}

function freshPrice(assetId: string, variantMint: string, pricePaperMicros: string): AcceptedPaperPrice {
  const acceptedAt = Date.now();
  return {
    assetId, variantMint, symbol: variantMint === mint ? 'AAPLx' : 'AAPLz', pricePaperMicros,
    source: {
      ...source,
      providerReference: `/v1/assets/${assetId}/variants#${variantMint}`,
      observedAt: new Date(acceptedAt).toISOString(), acceptedAt: new Date(acceptedAt).toISOString(),
    },
    expiresAt: new Date(acceptedAt + 30_000).toISOString(),
  };
}

class MemoryRepository implements PaperTradingRepository {
  readonly previews = new Map<string, PaperOrderPreview>();
  readonly orders = new Map<string, PaperCommittedOrder>();
  readonly resets = new Map<string, {readonly requestHash: string; readonly receipt: PaperResetReceipt}>();
  resetFailure: PaperTradingRepositoryError | undefined;
  portfolio: PaperPortfolio = emptyPaperPortfolio();
  async getPortfolio() { return this.portfolio; }
  async findPreviewRequest(_user: string, requestId: string) {
    return [...this.previews.values()].find(value => value.requestId === requestId) ?? null;
  }
  async createPreview(_user: string, command: PaperPreviewCommand) {
    const amount = command.amount.kind === 'paper_amount' ? command.amount.paperMicros : command.amount.quantityMicros;
    const value: PaperOrderPreview = {id: command.id, requestId: command.requestId, requestHash: command.requestHash,
      state: 'open', accountRevision: 0, action: command.action, amount: command.amount, assetId: 'apple', variantMint: mint,
      symbol: 'AAPLx', pricePaperMicros: '200000000', quantityMicros: amount === '100000000' ? '500000' : amount,
      cashDebitPaperMicros: command.action === 'buy' ? '100000000' : '0',
      cashCreditPaperMicros: command.action === 'buy' ? '0' : '100000000', cashAfterPaperMicros: '9900000000',
      positionQuantityAfterMicros: '500000', positionCostBasisAfterPaperMicros: '100000000',
      realizedGainDeltaPaperMicros: '0', lockedGainDeltaPaperMicros: '0', source, expiresAt: price.expiresAt, committedAt: null};
    this.previews.set(value.id, value); return value;
  }
  async commit(_user: string, command: PaperCommitCommand) {
    const replay = this.orders.get(command.idempotencyKey); if (replay) return replay;
    const preview = this.previews.get(command.previewId);
    if (!preview) throw new PaperTradingRepositoryError('PAPER_PREVIEW_NOT_FOUND', 'missing');
    const value: PaperCommittedOrder = {id: command.orderId, previewId: preview.id, accountRevision: 1,
      action: preview.action, assetId: preview.assetId, variantMint: preview.variantMint, symbol: preview.symbol,
      pricePaperMicros: preview.pricePaperMicros, quantityMicros: preview.quantityMicros,
      cashDebitPaperMicros: preview.cashDebitPaperMicros, cashCreditPaperMicros: preview.cashCreditPaperMicros,
      cashAfterPaperMicros: preview.cashAfterPaperMicros, positionQuantityAfterMicros: preview.positionQuantityAfterMicros,
      positionCostBasisAfterPaperMicros: preview.positionCostBasisAfterPaperMicros,
      realizedGainDeltaPaperMicros: preview.realizedGainDeltaPaperMicros,
      lockedGainDeltaPaperMicros: preview.lockedGainDeltaPaperMicros, source, committedAt: '2026-09-20T12:00:10.000Z'};
    this.orders.set(command.idempotencyKey, value); return value;
  }
  async reset(_user: string, command: PaperResetCommand) {
    if (this.resetFailure) throw this.resetFailure;
    const replay = this.resets.get(command.mutationId);
    if (replay) {
      if (replay.requestHash !== command.requestHash) {
        throw new PaperTradingRepositoryError('PAPER_IDEMPOTENCY_CONFLICT', 'rebound');
      }
      return replay.receipt;
    }
    const receipt: PaperResetReceipt = {
      mutationId: command.mutationId, previousRevision: command.baseRevision, revision: command.baseRevision + 1,
      cashPaperMicros: '10000000000', resetAt: '2026-09-20T12:00:20.000Z',
    };
    this.resets.set(command.mutationId, {requestHash: command.requestHash, receipt});
    this.portfolio = {...emptyPaperPortfolio(), revision: receipt.revision,
      openedAt: this.portfolio.openedAt, updatedAt: receipt.resetAt};
    return receipt;
  }
}

let repository: MemoryRepository;
let priceReads: number;
let prices: PaperPriceReader;
beforeEach(() => {
  repository = new MemoryRepository(); priceReads = 0;
  prices = {read: async () => { priceReads++; return price; }};
});
function app(authenticated = true, browserOrigins: readonly string[] = []) {
  return buildApp({logger: false, browserOrigins, paperTrading: {repository, prices,
    authenticate: async () => authenticated ? {userId} : null, newId: randomUUID}});
}
const previewBody = (requestId = randomUUID()) => ({schemaVersion: 1, requestId, action: 'buy', assetId: 'apple',
  variantMint: mint, amount: {kind: 'paper_amount', paperMicros: '100000000'}});
const resetBody = (mutationId = randomUUID(), baseRevision = 4) => ({
  schemaVersion: 1, mutationId, baseRevision, confirm: PAPER_RESET_CONFIRMATION,
});

describe('paper trading routes', () => {
  test('stay unavailable without all three account, storage and live-price adapters', async () => {
    const instance = buildApp({logger: false});
    try {
      assert.equal((await instance.inject('/v1/config')).json().paperTradingEnabled, false);
      assert.equal((await instance.inject(PAPER_PORTFOLIO_ROUTE)).statusCode, 503);
      assert.equal((await instance.inject({method: 'POST', url: PAPER_PREVIEW_ROUTE, payload: previewBody()})).statusCode, 503);
      assert.equal((await instance.inject({method: 'POST', url: PAPER_RESET_ROUTE, payload: resetBody()})).statusCode, 503);
    } finally { await instance.close(); }
  });

  test('keeps existing paper routes enabled while an older adapter has no reset capability', async () => {
    Object.defineProperty(repository, 'reset', {value: undefined});
    const instance = app();
    try {
      assert.equal((await instance.inject('/v1/config')).json().paperTradingEnabled, true);
      assert.equal((await instance.inject(PAPER_PORTFOLIO_ROUTE)).statusCode, 200);
      const reset = await instance.inject({method: 'POST', url: PAPER_RESET_ROUTE, payload: resetBody()});
      assert.equal(reset.statusCode, 503);
      assert.equal(reset.json().error.code, 'PAPER_RESET_UNAVAILABLE');
    } finally { await instance.close(); }
  });

  test('authenticates before reading a live price or touching paper storage', async () => {
    const instance = app(false);
    try {
      const response = await instance.inject({method: 'POST', url: PAPER_PREVIEW_ROUTE, payload: previewBody()});
      assert.equal(response.statusCode, 401);
      const reset = await instance.inject({method: 'POST', url: PAPER_RESET_ROUTE, payload: resetBody()});
      assert.equal(reset.statusCode, 401);
      assert.equal(priceReads, 0);
      assert.equal(repository.previews.size, 0);
      assert.equal(repository.resets.size, 0);
    } finally { await instance.close(); }
  });

  test('previews once, replays by request ID without another provider read, then commits once', async () => {
    const instance = app();
    try {
      const body = previewBody();
      const first = await instance.inject({method: 'POST', url: PAPER_PREVIEW_ROUTE, payload: body});
      assert.equal(first.statusCode, 200, first.body);
      assert.equal(first.json().mode, 'paper');
      assert.deepEqual(first.json().unit, {kind: 'paper', scaleDigits: 6});
      assert.equal(first.json().reward.trimsAwarded, 0);
      assert.equal(first.json().execution.transactionBuilt, false);
      assert.equal(first.body.includes('$'), false);
      const retry = await instance.inject({method: 'POST', url: PAPER_PREVIEW_ROUTE, payload: body});
      assert.deepEqual(retry.json(), first.json());
      assert.equal(priceReads, 1);

      const idempotencyKey = randomUUID();
      const commit = {schemaVersion: 1, previewId: first.json().preview.id, idempotencyKey};
      const done = await instance.inject({method: 'POST', url: PAPER_COMMIT_ROUTE, payload: commit});
      assert.equal(done.statusCode, 200, done.body);
      assert.equal(done.json().order.accountRevision, 1);
      const repeated = await instance.inject({method: 'POST', url: PAPER_COMMIT_ROUTE, payload: commit});
      assert.deepEqual(repeated.json(), done.json());
      assert.equal(repository.orders.size, 1);
    } finally { await instance.close(); }
  });

  test('cash-denominated sells normalize to server-priced shares and replay the original intent', async () => {
    const instance = app();
    try {
      const body = {...previewBody(), action: 'sell', amount: {kind: 'paper_amount', paperMicros: '100000001'}};
      const first = await instance.inject({method: 'POST', url: PAPER_PREVIEW_ROUTE, payload: body});
      assert.equal(first.statusCode, 200, first.body);
      // 100.000001 / 200 rounds up at six share decimals.
      assert.deepEqual(first.json().preview.amount, {kind: 'share_quantity', quantityMicros: '500001'});
      const replay = await instance.inject({method: 'POST', url: PAPER_PREVIEW_ROUTE, payload: body});
      assert.deepEqual(replay.json(), first.json());
      assert.equal(priceReads, 1);
      const rebound = await instance.inject({method: 'POST', url: PAPER_PREVIEW_ROUTE,
        payload: {...body, amount: {kind: 'share_quantity', quantityMicros: '500001'}}});
      assert.equal(rebound.statusCode, 409);
    } finally { await instance.close(); }
  });

  test('resets once with an exact immutable receipt and a cash-only desk snapshot', async () => {
    repository.portfolio = {
      ...emptyPaperPortfolio(), revision: 4, cashPaperMicros: '9750000000', positions: [paperPosition()],
    };
    const instance = app(true, [browserOrigin]);
    try {
      const payload = resetBody();
      const first = await instance.inject({method: 'POST', url: PAPER_RESET_ROUTE,
        headers: {origin: browserOrigin}, payload});
      assert.equal(first.statusCode, 200, first.body);
      assert.equal(first.headers['access-control-allow-origin'], browserOrigin);
      assert.deepEqual(first.json(), {
        schemaVersion: 1, mode: 'paper', unit: {kind: 'paper', scaleDigits: 6},
        reset: {mutationId: payload.mutationId, previousRevision: 4, revision: 5,
          resetAt: '2026-09-20T12:00:20.000Z'},
        portfolioAtReset: {revision: 5, startingCashPaperMicros: '10000000000',
          cashPaperMicros: '10000000000', positions: [], recentOrders: []},
      });
      assert.deepEqual(Object.keys(first.json().reset),
        ['mutationId', 'previousRevision', 'revision', 'resetAt']);
      const replay = await instance.inject({method: 'POST', url: PAPER_RESET_ROUTE, payload});
      assert.deepEqual(replay.json(), first.json());
      assert.equal(repository.resets.size, 1);
      assert.equal(repository.resets.get(payload.mutationId)?.requestHash,
        createHash('sha256').update('{"baseRevision":4,"confirm":"reset my paper desk"}').digest('hex'));
      assert.equal(priceReads, 0);

      const rebound = await instance.inject({method: 'POST', url: PAPER_RESET_ROUTE,
        payload: {...payload, baseRevision: 3}});
      assert.equal(rebound.statusCode, 409);
      assert.equal(rebound.json().error.code, 'PAPER_IDEMPOTENCY_CONFLICT');
      assert.equal(repository.resets.size, 1);
    } finally { await instance.close(); }
  });

  test('requires the exact reset confirmation and a strict bounded request', async () => {
    const instance = app();
    try {
      const mutationId = randomUUID();
      for (const payload of [
        {...resetBody(mutationId), confirm: 'Reset my paper desk'},
        {...resetBody(mutationId), confirm: `${PAPER_RESET_CONFIRMATION} `},
        {...resetBody(mutationId), baseRevision: -1},
        {...resetBody(mutationId), baseRevision: 1.5},
        {...resetBody(mutationId), baseRevision: Number.MAX_SAFE_INTEGER + 1},
        {...resetBody(mutationId), extra: true},
        {schemaVersion: 1, mutationId, baseRevision: 4},
      ]) {
        const response = await instance.inject({method: 'POST', url: PAPER_RESET_ROUTE, payload});
        assert.equal(response.statusCode, 400, response.body);
      }
      assert.equal(repository.resets.size, 0);
      assert.equal(priceReads, 0);
    } finally { await instance.close(); }
  });

  test('maps reset conflicts and terminal no-op without exposing repository detail', async () => {
    const cases = [
      ['PAPER_RESET_NOT_NEEDED', 409], ['PAPER_PORTFOLIO_CHANGED', 409],
      ['PAPER_REVISION_EXHAUSTED', 409], ['PAPER_ACCOUNT_NOT_FOUND', 404],
      ['PAPER_ACCOUNT_UNAVAILABLE', 403], ['PAPER_STORAGE_INVALID', 503],
    ] as const;
    for (const [code, status] of cases) {
      repository.resetFailure = new PaperTradingRepositoryError(code, `private ${code} storage detail`);
      const instance = app();
      try {
        const response = await instance.inject({method: 'POST', url: PAPER_RESET_ROUTE, payload: resetBody()});
        assert.equal(response.statusCode, status, response.body);
        assert.equal(response.json().error.code,
          code === 'PAPER_STORAGE_INVALID' ? 'PAPER_RESET_UNAVAILABLE' : code);
        assert.equal(response.body.includes('private'), false);
      } finally { await instance.close(); }
    }
  });

  test('rejects an idempotency key rebound and malformed or unsupported requests', async () => {
    const instance = app();
    try {
      const requestId = randomUUID();
      assert.equal((await instance.inject({method: 'POST', url: PAPER_PREVIEW_ROUTE, payload: previewBody(requestId)})).statusCode, 200);
      const rebound = previewBody(requestId); rebound.amount.paperMicros = '200000000';
      const conflict = await instance.inject({method: 'POST', url: PAPER_PREVIEW_ROUTE, payload: rebound});
      assert.equal(conflict.statusCode, 409);
      assert.equal(conflict.json().error.code, 'PAPER_IDEMPOTENCY_CONFLICT');
      for (const payload of [{...previewBody(), mode: 'money'}, {...previewBody(), amount: {kind: 'paper_amount', paperMicros: 1}},
        {...previewBody(), action: 'swap'}]) {
        assert.equal((await instance.inject({method: 'POST', url: PAPER_PREVIEW_ROUTE, payload})).statusCode, 400);
      }
      const live = await instance.inject({method: 'POST', url: '/v1/account/money/orders/commit', payload: {}});
      assert.equal(live.statusCode, 503);
      assert.equal(live.json().error.code, 'FINANCIAL_OPERATIONS_DISABLED');
    } finally { await instance.close(); }
  });

  test('returns the empty paper desk without pretending it has a market valuation', async () => {
    const instance = app();
    try {
      const response = await instance.inject(PAPER_PORTFOLIO_ROUTE);
      assert.equal(response.statusCode, 200, response.body);
      assert.equal(response.json().schemaVersion, 1);
      assert.equal(response.json().cashPaperMicros, '10000000000');
      assert.equal(response.json().valuation.status, 'not_included');
      assert.deepEqual(response.json().positions, []);
      assert.deepEqual(new Set(String(response.headers['vary']).toLowerCase().split(', ')),
        new Set(['origin', 'accept']));
      assert.equal(priceReads, 0);
    } finally { await instance.close(); }
  });

  test('keeps a populated portfolio on v1 without spending a current-price read', async () => {
    repository.portfolio = {
      ...emptyPaperPortfolio(), revision: 4, cashPaperMicros: '9750000000', positions: [paperPosition()],
    };
    const instance = app();
    try {
      const response = await instance.inject({method: 'GET', url: PAPER_PORTFOLIO_ROUTE,
        headers: {accept: 'application/json'}});
      assert.equal(response.statusCode, 200, response.body);
      assert.equal(response.json().schemaVersion, 1);
      assert.equal(response.json().revision, 4);
      assert.equal(response.json().positions.length, 1);
      assert.deepEqual(response.json().valuation, {
        status: 'not_included',
        note: 'Position value needs a fresh market read; stored cost basis is not a current price.',
      });
      assert.equal(priceReads, 0);
    } finally { await instance.close(); }
  });

  test('opts in to an exact-mint v2 portfolio valuation while preserving the ledger snapshot', async () => {
    repository.portfolio = {
      ...emptyPaperPortfolio(), revision: 7, cashPaperMicros: '9000000000',
      positions: [
        paperPosition(),
        paperPosition({variantMint: secondMint, symbol: 'AAPLz', quantityMicros: '250000',
          costBasisPaperMicros: '90000000', averageCostPricePaperMicros: '360000000'}),
      ],
    };
    const requests: Array<{assetId: string; variantMint: string; signal?: AbortSignal}> = [];
    prices = {read: async input => {
      requests.push(input);
      return freshPrice(input.assetId, input.variantMint, input.variantMint === mint ? '200000001' : '400000000');
    }};
    const instance = app(true, [browserOrigin]);
    try {
      const response = await instance.inject({method: 'GET', url: PAPER_PORTFOLIO_ROUTE,
        headers: {accept: PAPER_PORTFOLIO_V2_MEDIA_TYPE, origin: browserOrigin}});
      assert.equal(response.statusCode, 200, response.body);
      assert.match(response.headers['content-type'] ?? '',
        new RegExp(`^${PAPER_PORTFOLIO_V2_MEDIA_TYPE.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&')}`));
      assert.equal(response.headers['access-control-allow-origin'], browserOrigin);
      assert.deepEqual(new Set(String(response.headers['vary']).toLowerCase().split(', ')),
        new Set(['origin', 'accept']));
      assert.deepEqual(requests.map(({assetId, variantMint}) => ({assetId, variantMint})), [
        {assetId: 'apple', variantMint: mint},
        {assetId: 'apple', variantMint: secondMint},
      ]);
      assert.equal(requests.every(request => request.signal?.aborted === true), true);
      const body = response.json();
      assert.equal(body.schemaVersion, 2);
      assert.equal(body.revision, 7);
      assert.equal(body.positions[1].variantMint, secondMint);
      assert.deepEqual(body.valuation, {
        status: 'complete', portfolioRevision: 7, openPositionCount: 2, pricedPositionCount: 2,
        cashPaperMicros: '9000000000', knownValuePaperMicros: '9400000201',
        totalPaperMicros: '9400000201',
        positions: [
          {
            assetId: 'apple', variantMint: mint, status: 'priced', pricePaperMicros: '200000001',
            marketValuePaperMicros: '300000201', unrealizedGainPaperMicros: '50000201',
            observedAt: body.valuation.positions[0].observedAt,
            acceptedAt: body.valuation.positions[0].acceptedAt,
            expiresAt: body.valuation.positions[0].expiresAt,
          },
          {
            assetId: 'apple', variantMint: secondMint, status: 'priced', pricePaperMicros: '400000000',
            marketValuePaperMicros: '100000000', unrealizedGainPaperMicros: '10000000',
            observedAt: body.valuation.positions[1].observedAt,
            acceptedAt: body.valuation.positions[1].acceptedAt,
            expiresAt: body.valuation.positions[1].expiresAt,
          },
        ],
      });
      for (const row of body.valuation.positions) {
        for (const field of ['pricePaperMicros', 'marketValuePaperMicros', 'unrealizedGainPaperMicros',
          'observedAt', 'acceptedAt', 'expiresAt']) assert.notEqual(row[field], null);
      }
    } finally { await instance.close(); }
  });

  test('returns the exact v2 ledger with an honest unavailable valuation when prices fail', async () => {
    repository.portfolio = {
      ...emptyPaperPortfolio(), revision: 3, cashPaperMicros: '9750000000', positions: [paperPosition()],
    };
    prices = {read: async () => {
      throw new Error('private provider failure');
    }};
    const instance = app();
    try {
      const response = await instance.inject({method: 'GET', url: PAPER_PORTFOLIO_ROUTE,
        headers: {accept: PAPER_PORTFOLIO_V2_MEDIA_TYPE}});
      assert.equal(response.statusCode, 200, response.body);
      assert.equal(response.json().revision, 3);
      assert.equal(response.json().positions.length, 1);
      assert.deepEqual(response.json().valuation, {
        status: 'unavailable', portfolioRevision: 3, openPositionCount: 1, pricedPositionCount: 0,
        cashPaperMicros: '9750000000', knownValuePaperMicros: '9750000000', totalPaperMicros: null,
        positions: [{assetId: 'apple', variantMint: mint, status: 'unavailable',
          pricePaperMicros: null, marketValuePaperMicros: null, unrealizedGainPaperMicros: null,
          observedAt: null, acceptedAt: null, expiresAt: null}],
      });
      assert.equal(response.body.includes('private provider failure'), false);
    } finally { await instance.close(); }
  });

  test('uses the database window for each guest paper scope without exposing repository detail', async () => {
    const instance = buildApp({logger: false, paperTrading: {repository, prices,
      authenticate: async () => { throw new GuestSessionError('GUEST_SESSION_RATE_LIMITED', 'secret rate row'); },
      newId: randomUUID}});
    try {
      for (const request of [
        {method: 'GET' as const, url: PAPER_PORTFOLIO_ROUTE, expected: '60'},
        {method: 'POST' as const, url: PAPER_PREVIEW_ROUTE, payload: previewBody(), expected: '600'},
        {method: 'POST' as const, url: PAPER_COMMIT_ROUTE,
          payload: {schemaVersion: 1, previewId: randomUUID(), idempotencyKey: randomUUID()}, expected: '600'},
        {method: 'POST' as const, url: PAPER_RESET_ROUTE, payload: resetBody(), expected: '3600'},
      ]) {
        const response = await instance.inject(request);
        assert.equal(response.statusCode, 429, response.body);
        assert.equal(response.headers['retry-after'], request.expected);
        assert.equal(response.body.includes('secret'), false);
      }
    } finally { await instance.close(); }
  });

  test('authorizes a guest reset with only the exact paper_reset scope', async () => {
    const scopes: string[] = [];
    const guests: GuestSessionRepository = {
      takeCreationAttempt: async () => { throw new Error('not used'); },
      create: async () => { throw new Error('not used'); },
      refresh: async () => { throw new Error('not used'); },
      claim: async () => { throw new Error('not used'); },
      authorize: async (_hash, scope) => {
        scopes.push(scope);
        return {userId, guestId: '70000000-0000-4000-8000-000000000002',
          expiresAt: '2026-09-20T13:00:00.000Z'};
      },
    };
    const instance = buildApp({logger: false, paperTrading: {repository, prices,
      authenticate: createGuestPaperAuthenticator(async () => null, guests), newId: randomUUID}});
    try {
      const response = await instance.inject({method: 'POST', url: PAPER_RESET_ROUTE,
        headers: {authorization: `Guest ${guestToken}`}, payload: resetBody()});
      assert.equal(response.statusCode, 200, response.body);
      assert.deepEqual(scopes, ['paper_reset']);
      assert.equal(priceReads, 0);
    } finally { await instance.close(); }
  });

  test('preserves server-expired and server-revoked guest codes on every paper route', async () => {
    for (const code of ['GUEST_SESSION_EXPIRED', 'GUEST_SESSION_REVOKED'] as const) {
      const guests: GuestSessionRepository = {
        takeCreationAttempt: async () => { throw new Error('not used'); },
        create: async () => { throw new Error('not used'); },
        refresh: async () => { throw new Error('not used'); },
        claim: async () => { throw new Error('not used'); },
        authorize: async () => { throw new GuestSessionError(code, `private ${code} database detail`); },
      };
      const instance = buildApp({logger: false, paperTrading: {repository, prices,
        authenticate: createGuestPaperAuthenticator(async () => null, guests), newId: randomUUID}});
      try {
        const headers = {authorization: `Guest ${guestToken}`};
        for (const request of [
          {method: 'GET' as const, url: PAPER_PORTFOLIO_ROUTE, headers},
          {method: 'POST' as const, url: PAPER_PREVIEW_ROUTE, headers, payload: previewBody()},
          {method: 'POST' as const, url: PAPER_COMMIT_ROUTE, headers,
            payload: {schemaVersion: 1, previewId: randomUUID(), idempotencyKey: randomUUID()}},
          {method: 'POST' as const, url: PAPER_RESET_ROUTE, headers, payload: resetBody()},
        ]) {
          const response = await instance.inject(request);
          assert.equal(response.statusCode, 401, response.body);
          assert.equal(response.json().error.code, code);
          assert.equal(response.body.includes('private'), false);
        }
      } finally { await instance.close(); }
    }
    assert.equal(priceReads, 0);
    assert.equal(repository.previews.size, 0);
    assert.equal(repository.orders.size, 0);
  });

  test('maps paper price saturation and timeouts without exposing provider details', async () => {
    for (const [failureKind, status, retryAfter] of [
      ['rate_limited', 429, undefined],
      ['timeout', 504, undefined],
      ['default', 503, undefined],
    ] as const) {
      prices = {read: async () => { throw new PaperPriceError('PAPER_PRICE_UNAVAILABLE', failureKind); }};
      const instance = app();
      try {
        const response = await instance.inject({method: 'POST', url: PAPER_PREVIEW_ROUTE, payload: previewBody()});
        assert.equal(response.statusCode, status, response.body);
        assert.equal(response.json().error.code, 'PAPER_PRICE_UNAVAILABLE');
        assert.equal(response.headers['retry-after'], retryAfter);
        assert.equal(response.body.includes('tokens'), false);
      } finally { await instance.close(); }
    }
  });
});
