import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, before, describe, test } from 'node:test';
import { Pool } from 'pg';
import { buildApp } from '../../src/app.js';
import { PostgresPaperTradingRepository } from '../../src/postgres-paper-trading-repository.js';
import { PaperTradingRepositoryError } from '../../src/paper-trading-repository.js';
import type { PaperPriceReader } from '../../src/paper-price-reader.js';
import {
  PAPER_COMMIT_ROUTE, PAPER_PORTFOLIO_ROUTE, PAPER_PREVIEW_ROUTE, PAPER_RESET_CONFIRMATION, PAPER_RESET_ROUTE,
} from '../../src/paper-trading-routes.js';

const socket = process.env['TRIMMY_PRACTICE_TEST_SOCKET'];
assert.ok(socket?.endsWith('/infra/.practice-runtime/socket'), 'Use the private test runner; never attach to an external database.');
assert.equal(process.env['TRIMMY_PRACTICE_TEST_PORT'], '65438');
const connection = {host: socket, port: 65438, database: 'postgres', connectionTimeoutMillis: 3000};
const pool = new Pool({...connection, user: 'trimmy_paper_test_app', max: 5});
const repository = new PostgresPaperTradingRepository(pool);
const users = ['00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002',
  '00000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000004'] as const;
const proofs = new Map(users.map((id, index) => [`Bearer test-paper-${index}`, id]));
const mint = 'XsP7xzNPvEHS1m6qfanPUGjNmdMVPckE3hER9uE7p6H';
const firstPreviewId = '13000000-0000-4000-8000-000000000001';
const firstOrderId = '13000000-0000-4000-8000-000000000002';
const firstRequestId = '13000000-0000-4000-8000-000000000003';
const firstCommitKey = '13000000-0000-4000-8000-000000000004';
const firstResetMutationId = '13000000-0000-4000-8000-000000000005';
let idCount = 0;
const firstIds = [firstPreviewId, firstOrderId];
let priceMicros = '200000000';
let acceptedOffsetMs = 0;
const prices: PaperPriceReader = {read: async ({assetId, variantMint}) => {
  const accepted = Date.now() + acceptedOffsetMs;
  const acceptedAt = new Date(accepted).toISOString();
  return {assetId, variantMint, symbol: 'AAPLx', pricePaperMicros: priceMicros,
    source: {provider: 'tokens-xyz-v1', providerReference: `/v1/assets/${assetId}/variants#fixture`,
      marketSource: 'integration-fixture', metricsSource: null,
      providerTimestamps: {asOf: null, lastFetchedAt: null, lastTradeAt: null, unit: 'not_declared'},
      observedAt: acceptedAt, acceptedAt}, expiresAt: new Date(accepted + 30_000).toISOString()};
}};
const app = buildApp({logger: false, paperTrading: {repository, prices,
  authenticate: async request => {
    const userId = proofs.get(request.headers.authorization ?? '');
    return userId ? {userId} : null;
  }, newId: () => firstIds[idCount++] ?? randomUUID()}});
const headers = (index: number) => ({authorization: `Bearer test-paper-${index}`});
const portfolio = (index: number) => app.inject({url: PAPER_PORTFOLIO_ROUTE, headers: headers(index)});
const preview = (index: number, action: 'buy' | 'sell' | 'trim', amount: Record<string, string>, requestId = randomUUID()) =>
  app.inject({method: 'POST', url: PAPER_PREVIEW_ROUTE, headers: headers(index),
    payload: {schemaVersion: 1, requestId, action, assetId: 'apple', variantMint: mint, amount}});
const commit = (index: number, previewId: string, idempotencyKey = randomUUID()) =>
  app.inject({method: 'POST', url: PAPER_COMMIT_ROUTE, headers: headers(index),
    payload: {schemaVersion: 1, previewId, idempotencyKey}});
const reset = (index: number, baseRevision: number, mutationId = randomUUID()) =>
  app.inject({method: 'POST', url: PAPER_RESET_ROUTE, headers: headers(index),
    payload: {schemaVersion: 1, mutationId, baseRevision, confirm: PAPER_RESET_CONFIRMATION}});

before(async () => { await app.ready(); });
after(async () => { await app.close(); await pool.end(); });

if (process.env['TRIMMY_PRACTICE_TEST_RECOVERY'] === '1') {
  test('a new process recovers the committed order and its idempotent receipt', async () => {
    const recovered = await portfolio(0);
    assert.equal(recovered.statusCode, 200, recovered.body);
    assert.equal(recovered.json().revision, 5);
    assert.equal(recovered.json().positions[0].quantityMicros, '100000');
    assert.equal(recovered.json().recentOrders.length, 1);
    assert.equal(recovered.json().recentOrders.some((row: {id: string}) => row.id === firstOrderId), false);
    const resetReplay = await reset(0, 3, firstResetMutationId);
    assert.equal(resetReplay.statusCode, 200, resetReplay.body);
    assert.deepEqual(Object.keys(resetReplay.json().reset),
      ['mutationId', 'previousRevision', 'revision', 'resetAt']);
    assert.equal(resetReplay.json().reset.revision, 4);
    const retry = await commit(0, firstPreviewId, firstCommitKey);
    assert.equal(retry.statusCode, 200, retry.body);
    assert.equal(retry.json().order.id, firstOrderId);
    assert.equal((await portfolio(0)).json().revision, 5);
  });
} else {
  describe('paper trading PostgreSQL integration', () => {
    test('opens at 10,000 paper only when the first preview is accepted, then commits idempotently', async () => {
      const empty = await portfolio(0);
      assert.equal(empty.statusCode, 200, empty.body);
      assert.equal(empty.json().cashPaperMicros, '10000000000');
      assert.equal(empty.json().openedAt, null);
      const before = await pool.query('SELECT count(*)::int AS count FROM trimmy.paper_accounts');
      assert.equal(before.rows[0].count, 0);

      const quoted = await preview(0, 'buy', {kind: 'paper_amount', paperMicros: '100000000'}, firstRequestId);
      assert.equal(quoted.statusCode, 200, quoted.body);
      assert.equal(quoted.json().preview.id, firstPreviewId);
      assert.equal(quoted.json().preview.quantityMicros, '500000');
      assert.equal(quoted.json().preview.cashAfterPaperMicros, '9900000000');
      const done = await commit(0, firstPreviewId, firstCommitKey);
      assert.equal(done.statusCode, 200, done.body);
      assert.equal(done.json().order.id, firstOrderId);
      assert.equal(done.json().order.accountRevision, 1);
      const retry = await commit(0, firstPreviewId, firstCommitKey);
      assert.deepEqual(retry.json(), done.json());
      const secondKey = await commit(0, firstPreviewId);
      assert.equal(secondKey.statusCode, 409);
      assert.equal(secondKey.json().error.code, 'PAPER_PREVIEW_ALREADY_COMMITTED');

      const desk = await portfolio(0);
      assert.equal(desk.json().revision, 1);
      assert.equal(desk.json().cashPaperMicros, '9900000000');
      assert.equal(desk.json().positions[0].quantityMicros, '500000');
      assert.equal(desk.json().positions[0].costBasisPaperMicros, '100000000');
      assert.equal(desk.json().recentOrders.length, 1);
    });

    test('applies buy, profitable trim and exact basis allocation as one ledger per revision', async () => {
      priceMicros = '300000000';
      const buy = await preview(0, 'buy', {kind: 'share_quantity', quantityMicros: '500000'});
      const bought = await commit(0, buy.json().preview.id);
      assert.equal(bought.statusCode, 200, bought.body);
      assert.equal(bought.json().order.accountRevision, 2);
      priceMicros = '400000000';
      const trim = await preview(0, 'trim', {kind: 'share_quantity', quantityMicros: '250000'});
      const trimmed = await commit(0, trim.json().preview.id);
      assert.equal(trimmed.statusCode, 200, trimmed.body);
      assert.equal(trimmed.json().order.accountRevision, 3);
      assert.equal(trimmed.json().order.realizedGainDeltaPaperMicros, '37500000');
      assert.equal(trimmed.json().order.lockedGainDeltaPaperMicros, '37500000');
      const desk = (await portfolio(0)).json();
      assert.equal(desk.revision, 3);
      assert.equal(desk.positions[0].quantityMicros, '750000');
      assert.equal(desk.positions[0].costBasisPaperMicros, '187500000');
      assert.equal(desk.positions[0].lockedGainPaperMicros, '37500000');
      const client = await pool.connect();
      try {
        await client.query('BEGIN READ ONLY');
        await client.query("SELECT set_config('trimmy.practice_user_id',$1,true)", [users[0]]);
        const ledger = await client.query('SELECT account_revision::text, entry_kind FROM trimmy.paper_cash_ledger ORDER BY account_revision');
        assert.deepEqual(ledger.rows, [{account_revision: '0', entry_kind: 'initial'},
          {account_revision: '1', entry_kind: 'buy'}, {account_revision: '2', entry_kind: 'buy'},
          {account_revision: '3', entry_kind: 'trim'}]);
        await client.query('COMMIT');
      } finally { client.release(); }
    });

    test('resets one cycle exactly, hides old holdings and preserves immutable order replay across restart', async () => {
      const first = await reset(0, 3, firstResetMutationId);
      assert.equal(first.statusCode, 200, first.body);
      assert.deepEqual(first.json(), {
        schemaVersion: 1, mode: 'paper', unit: {kind: 'paper', scaleDigits: 6},
        reset: {mutationId: firstResetMutationId, previousRevision: 3, revision: 4,
          resetAt: first.json().reset.resetAt},
        portfolioAtReset: {revision: 4, startingCashPaperMicros: '10000000000',
          cashPaperMicros: '10000000000', positions: [], recentOrders: []},
      });
      assert.match(first.json().reset.resetAt, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/u);
      const replay = await reset(0, 3, firstResetMutationId);
      assert.deepEqual(replay.json(), first.json());
      const rebound = await reset(0, 2, firstResetMutationId);
      assert.equal(rebound.statusCode, 409);
      assert.equal(rebound.json().error.code, 'PAPER_IDEMPOTENCY_CONFLICT');
      const stale = await reset(0, 3);
      assert.equal(stale.statusCode, 409);
      assert.equal(stale.json().error.code, 'PAPER_PORTFOLIO_CHANGED');

      const clean = await portfolio(0);
      assert.equal(clean.statusCode, 200, clean.body);
      assert.equal(clean.json().revision, 4);
      assert.equal(clean.json().cashPaperMicros, '10000000000');
      assert.deepEqual(clean.json().positions, []);
      assert.deepEqual(clean.json().recentOrders, []);

      priceMicros = '200000000';
      const quoted = await preview(0, 'buy', {kind: 'share_quantity', quantityMicros: '100000'});
      const bought = await commit(0, quoted.json().preview.id);
      assert.equal(bought.statusCode, 200, bought.body);
      assert.equal(bought.json().order.accountRevision, 5);
      const current = (await portfolio(0)).json();
      assert.equal(current.revision, 5);
      assert.equal(current.cashPaperMicros, '9980000000');
      assert.equal(current.positions.length, 1);
      assert.equal(current.positions[0].quantityMicros, '100000');
      assert.equal(current.positions[0].costBasisPaperMicros, '20000000');
      assert.equal(current.recentOrders.length, 1);
      assert.equal(current.recentOrders[0].accountRevision, 5);
      assert.equal(current.recentOrders.some((row: {id: string}) => row.id === firstOrderId), false);

      const oldReceipt = await commit(0, firstPreviewId, firstCommitKey);
      assert.equal(oldReceipt.statusCode, 200, oldReceipt.body);
      assert.equal(oldReceipt.json().order.id, firstOrderId);
      assert.equal((await portfolio(0)).json().revision, 5);

      const noOpMutation = randomUUID();
      const noOp = await reset(2, 0, noOpMutation);
      assert.equal(noOp.statusCode, 409);
      assert.equal(noOp.json().error.code, 'PAPER_RESET_NOT_NEEDED');
      const noOpReplay = await reset(2, 0, noOpMutation);
      assert.equal(noOpReplay.statusCode, 409);
      assert.equal(noOpReplay.json().error.code, 'PAPER_RESET_NOT_NEEDED');

      // A no-op receipt is still an immutable idempotency result. Later desk
      // activity cannot turn the same mutation into a reset or stale request.
      priceMicros = '200000000';
      const afterNoOp = await preview(2, 'buy',
        {kind: 'share_quantity', quantityMicros: '100000'});
      assert.equal((await commit(2, afterNoOp.json().preview.id)).statusCode, 200);
      const historicalNoOpReplay = await reset(2, 0, noOpMutation);
      assert.equal(historicalNoOpReplay.statusCode, 409);
      assert.equal(historicalNoOpReplay.json().error.code, 'PAPER_RESET_NOT_NEEDED');
      const reboundNoOp = await reset(2, 1, noOpMutation);
      assert.equal(reboundNoOp.statusCode, 409);
      assert.equal(reboundNoOp.json().error.code, 'PAPER_IDEMPOTENCY_CONFLICT');
      assert.equal((await reset(2, 1)).statusCode, 200);

      const client = await pool.connect();
      try {
        await client.query('BEGIN READ ONLY');
        await client.query("SELECT set_config('trimmy.practice_user_id',$1,true)", [users[0]]);
        const history = await client.query('SELECT count(*)::int AS count FROM trimmy.paper_orders');
        assert.equal(history.rows[0].count, 4);
        await assert.rejects(client.query('SELECT * FROM trimmy.paper_reset_receipts'),
          error => (error as {code?: string}).code === '42501');
        await client.query('ROLLBACK');
      } finally { client.release(); }
    });

    test('refuses a stale preview after another committed order and keeps accounts isolated', async () => {
      priceMicros = '410000000';
      const stale = await preview(1, 'buy', {kind: 'share_quantity', quantityMicros: '100000'});
      const winner = await preview(1, 'buy', {kind: 'share_quantity', quantityMicros: '200000'});
      assert.equal((await commit(1, winner.json().preview.id)).statusCode, 200);
      const conflict = await commit(1, stale.json().preview.id);
      assert.equal(conflict.statusCode, 409);
      assert.equal(conflict.json().error.code, 'PAPER_PORTFOLIO_CHANGED');
      assert.equal((await portfolio(1)).json().revision, 1);
      assert.equal((await portfolio(0)).json().revision, 5);
    });

    test('commits with a monotonic timestamp when the API acceptance clock is ahead of PostgreSQL', async () => {
      acceptedOffsetMs = 4_000;
      priceMicros = '200000000';
      try {
        const quoted = await preview(1, 'buy', {kind: 'paper_amount', paperMicros: '1000000'});
        assert.equal(quoted.statusCode, 200, quoted.body);
        const acceptedAt = quoted.json().preview.source.acceptedAt as string;
        const done = await commit(1, quoted.json().preview.id);
        assert.equal(done.statusCode, 200, done.body);
        assert.ok(Date.parse(done.json().order.committedAt) >= Date.parse(acceptedAt));
      } finally {
        acceptedOffsetMs = 0;
      }
    });

    test('refuses overselling, a losing trim and restricted accounts before any commit', async () => {
      priceMicros = '1';
      const oversell = await preview(2, 'sell', {kind: 'share_quantity', quantityMicros: '1'});
      assert.equal(oversell.statusCode, 409);
      assert.equal(oversell.json().error.code, 'PAPER_POSITION_INSUFFICIENT');
      const restricted = await preview(3, 'buy', {kind: 'paper_amount', paperMicros: '1000000'});
      assert.equal(restricted.statusCode, 403);
      assert.equal(restricted.json().error.code, 'PAPER_ACCOUNT_UNAVAILABLE');
      assert.equal((await portfolio(3)).json().openedAt, null);
    });

    test('cash sell, retry and exact-share close conserve the persisted ledger', async () => {
      priceMicros = '200000003';
      const before = (await portfolio(2)).json();
      const buy = await preview(2, 'buy', {kind: 'share_quantity', quantityMicros: '3000000'});
      assert.equal(buy.statusCode, 200, buy.body);
      const bought = await commit(2, buy.json().preview.id);
      assert.equal(bought.statusCode, 200, bought.body);
      const sale = await preview(2, 'sell', {kind: 'paper_amount', paperMicros: '100000000'});
      assert.equal(sale.statusCode, 200, sale.body);
      assert.equal(sale.json().preview.amount.kind, 'share_quantity');
      const key = randomUUID();
      const sold = await commit(2, sale.json().preview.id, key);
      assert.equal(sold.statusCode, 200, sold.body);
      const replay = await commit(2, sale.json().preview.id, key);
      assert.deepEqual(replay.json(), sold.json());
      const remaining = sold.json().order.positionQuantityAfterMicros;
      const oversell = await preview(2, 'sell', {kind: 'share_quantity', quantityMicros: (BigInt(remaining) + 1n).toString()});
      assert.equal(oversell.statusCode, 409);
      const close = await preview(2, 'sell', {kind: 'share_quantity', quantityMicros: remaining});
      assert.equal(close.statusCode, 200, close.body);
      const closed = await commit(2, close.json().preview.id);
      assert.equal(closed.statusCode, 200, closed.body);
      assert.equal(closed.json().order.positionQuantityAfterMicros, '0');
      assert.equal(closed.json().order.positionCostBasisAfterPaperMicros, '0');
      const after = (await portfolio(2)).json();
      assert.equal(after.revision, before.revision + 3);
      assert.equal(BigInt(after.cashPaperMicros), BigInt(before.cashPaperMicros)
        - BigInt(bought.json().order.cashDebitPaperMicros)
        + BigInt(sold.json().order.cashCreditPaperMicros)
        + BigInt(closed.json().order.cashCreditPaperMicros));
    });

    test('database policies and deferred ledger checks prevent direct cross-account or unbalanced changes', async () => {
      const client = await pool.connect();
      try {
        await assert.rejects(client.query('SELECT * FROM trimmy.financial_intents'),
          error => (error as {code?: string}).code === '42501');
        await client.query('BEGIN');
        await client.query("SELECT set_config('trimmy.practice_user_id',$1,true)", [users[1]]);
        const own = await client.query<{user_id: string}>('SELECT user_id FROM trimmy.paper_accounts');
        assert.deepEqual(own.rows.map(row => row.user_id), [users[1]]);
        await client.query('ROLLBACK');

        await client.query('BEGIN');
        await client.query("SELECT set_config('trimmy.practice_user_id',$1,true)", [users[0]]);
        await client.query("UPDATE trimmy.paper_accounts SET cash_micros = cash_micros + 1, revision = revision + 1, updated_at = clock_timestamp()");
        await assert.rejects(client.query('COMMIT'), error => (error as {code?: string}).code === '23514');
        await client.query('ROLLBACK').catch(() => {});

        await client.query('BEGIN');
        await client.query("SELECT set_config('trimmy.practice_user_id',$1,true)", [users[0]]);
        await client.query(`UPDATE trimmy.paper_positions SET quantity_micros = quantity_micros + 1,
          last_order_revision = last_order_revision + 1, updated_at = updated_at + interval '1 millisecond'`);
        await assert.rejects(client.query('COMMIT'), error => (error as {code?: string}).code === '23514');
        await client.query('ROLLBACK').catch(() => {});
        assert.equal((await portfolio(0)).json().revision, 5);
      } finally { client.release(); }
    });

    test('owner and bypass-role memberships are rejected by the repository guard', async () => {
      for (const user of ['trimmy_test_owner', 'trimmy_practice_test_unsafe']) {
        const privileged = new Pool({...connection, user, max: 1});
        try {
          await assert.rejects(new PostgresPaperTradingRepository(privileged).getPortfolio(users[0]), error =>
            error instanceof PaperTradingRepositoryError && error.code === 'PAPER_RUNTIME_ROLE_INVALID');
        } finally { await privileged.end(); }
      }
    });
  });
}
