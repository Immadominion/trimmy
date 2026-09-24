import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, before, describe, test } from 'node:test';
import { Pool } from 'pg';
import type { PoolClient } from 'pg';
import { buildApp } from '../../src/app.js';
import { PostgresWatchlistRepository } from '../../src/postgres-watchlist-repository.js';
import { WatchlistRepositoryError } from '../../src/watchlist-repository.js';

const socket = process.env['TRIMMY_PRACTICE_TEST_SOCKET'];
assert.ok(socket?.endsWith('/infra/.practice-runtime/socket'), 'Use the private test runner; never attach to an external database.');
assert.equal(process.env['TRIMMY_PRACTICE_TEST_PORT'], '65438');
const connection = {host: socket, port: 65438, database: 'postgres', connectionTimeoutMillis: 3000};
const pool = new Pool({...connection, user: 'trimmy_watchlist_test_app', max: 4});
const allowedAssetIds = new Set(['forma', 'orbital', 'grove', 'harbor', 'mesa', 'nori', 'pollen', 'helios']);
const repository = new PostgresWatchlistRepository(pool, {allowedAssetIds});
const users = ['00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-000000000003', '00000000-0000-4000-8000-000000000004', '00000000-0000-4000-8000-000000000005'] as const;
// Synthetic verifier exists only in the exclusively owned database tests.
// Real access-token verification is covered by the separate authentication suite.
const proofs = new Map(users.map((id, index) => [`Bearer test-watchlist-${index}`, id]));
const app = buildApp({logger: false, watchlist: {repository, allowedAssetIds, authenticate: async request => {
  const userId = proofs.get(request.headers.authorization ?? '');
  return userId ? {userId} : null;
}}});
const firstMutation = '00000000-0000-4000-8000-000000004001';
const firstAssets = ['orbital', 'forma'];
function get(index: number) {
  return app.inject({url: '/v1/watchlist', headers: {authorization: `Bearer test-watchlist-${index}`}});
}
function put(index: number, assetIds: readonly string[], baseRevision: number, mutationId = randomUUID()) {
  return app.inject({method: 'PUT', url: '/v1/watchlist', headers: {authorization: `Bearer test-watchlist-${index}`}, payload: {schemaVersion: 1, mutationId, baseRevision, assetIds}});
}

before(async () => { await app.ready(); });
after(async () => { await app.close(); await pool.end(); });

if (process.env['TRIMMY_PRACTICE_TEST_RECOVERY'] === '1') {
  test('new process recovers explicit empty watchlist and original receipt after database restart', async () => {
    const current = await get(0);
    assert.equal(current.statusCode, 200, current.body);
    assert.equal(current.json().revision, 2);
    assert.deepEqual(current.json().assetIds, []);
    const retry = await put(0, firstAssets, 0, firstMutation);
    assert.equal(retry.statusCode, 200, retry.body);
    assert.equal(retry.json().revision, 1);
    assert.deepEqual(retry.json().assetIds, firstAssets);
    assert.deepEqual((await get(0)).json(), current.json());
  });
} else {
  describe('watchlist HTTP and PostgreSQL integration', () => {
    test('first save and repeated mutation produce one ordered durable list', async () => {
      const initial = await get(0);
      assert.equal(initial.statusCode, 200, initial.body);
      assert.deepEqual(initial.json(), {schemaVersion: 1, revision: 0, assetIds: [], updatedAt: null});
      const saved = await put(0, firstAssets, 0, firstMutation);
      assert.equal(saved.statusCode, 200, saved.body);
      assert.equal(saved.json().revision, 1);
      assert.deepEqual(saved.json().assetIds, firstAssets);
      const retry = await put(0, firstAssets, 0, firstMutation);
      assert.deepEqual(retry.json(), saved.json());
      assert.deepEqual((await get(0)).json(), saved.json());
    });

    test('clearing stays empty while the older receipt returns its original list', async () => {
      const cleared = await put(0, [], 1);
      assert.equal(cleared.statusCode, 200, cleared.body);
      assert.equal(cleared.json().revision, 2);
      assert.deepEqual(cleared.json().assetIds, []);
      const retry = await put(0, firstAssets, 0, firstMutation);
      assert.equal(retry.statusCode, 200);
      assert.equal(retry.json().revision, 1);
      assert.deepEqual(retry.json().assetIds, firstAssets);
      assert.deepEqual((await get(0)).json(), cleared.json());
      const rebound = await put(0, [], 2, firstMutation);
      assert.equal(rebound.statusCode, 409);
      assert.equal(rebound.json().error.code, 'WATCHLIST_IDEMPOTENCY_CONFLICT');
    });

    test('two concurrent devices get one winner and one current-snapshot conflict', async () => {
      const responses = await Promise.all([put(1, ['forma'], 0), put(1, ['grove'], 0)]);
      assert.deepEqual(responses.map(value => value.statusCode).sort(), [200, 409]);
      const winner = responses.find(value => value.statusCode === 200)!;
      const conflict = responses.find(value => value.statusCode === 409)!;
      assert.equal(conflict.json().error.code, 'WATCHLIST_REVISION_CONFLICT');
      assert.deepEqual(conflict.json().currentSnapshot, winner.json());
      assert.deepEqual((await get(1)).json(), winner.json());
    });

    test('parallel identical requests commit one revision and keep accounts isolated', async () => {
      // Reusing another account's UUID is permitted; receipts are account scoped.
      const responses = await Promise.all(Array.from({length: 5}, () => put(2, ['nori', 'helios'], 0, firstMutation)));
      for (const response of responses) {
        assert.equal(response.statusCode, 200, response.body);
        assert.deepEqual(response.json(), responses[0]!.json());
      }
      assert.equal((await get(2)).json().revision, 1);
      assert.deepEqual((await get(0)).json().assetIds, []);
      const forged = await app.inject({url: '/v1/watchlist', headers: {authorization: 'Bearer test-watchlist-2', 'x-user-id': users[0]}});
      assert.deepEqual(forged.json().assetIds, ['nori', 'helios']);
      const missing = await app.inject({url: '/v1/watchlist', headers: {authorization: 'Bearer arbitrary-token', 'x-user-id': users[0]}});
      assert.equal(missing.statusCode, 401);
    });

    test('receipt failure rolls back a real SQL write before it can be acknowledged', async () => {
      const before = await repository.get(users[3]);
      const failingPool = {connect: async () => {
        const client = await pool.connect();
        return {
          query: (sql: string, parameters?: unknown[]) => {
            if (sql.includes('INSERT INTO trimmy.watchlist_mutation_receipts')) return Promise.reject(new Error('controlled receipt failure'));
            return client.query(sql, parameters);
          },
          release: (error?: Error) => client.release(error),
        } as unknown as PoolClient;
      }} satisfies Pick<Pool, 'connect'>;
      const mutationId = randomUUID();
      await assert.rejects(new PostgresWatchlistRepository(failingPool, {allowedAssetIds}).put(users[3], {mutationId, baseRevision: 0, assetIds: ['mesa']}));
      assert.deepEqual(await repository.get(users[3]), before);
      const retry = await put(3, ['mesa'], 0, mutationId);
      assert.equal(retry.statusCode, 200, retry.body);
      assert.equal(retry.json().revision, 1);
    });

    test('restricted accounts can save while closed accounts and unknown assets fail safely', async () => {
      assert.equal((await get(3)).statusCode, 200);
      for (const request of [get(4), put(4, [], 0)]) {
        const response = await request;
        assert.equal(response.statusCode, 404);
        assert.equal(response.json().error.code, 'WATCHLIST_ACCOUNT_NOT_FOUND');
      }
      const unknown = await put(0, ['private-unknown-symbol'], 2);
      assert.equal(unknown.statusCode, 400);
      assert.ok(!unknown.body.includes('private-unknown-symbol'));
      assert.equal((await get(0)).json().revision, 2);
    });

    test('watchlist role cannot read financial tables or bypass account row policies', async () => {
      const client = await pool.connect();
      try {
        await assert.rejects(client.query('SELECT * FROM trimmy.financial_intents'), error => (error as {code?: string}).code === '42501');
        await assert.rejects(client.query('SELECT * FROM trimmy.practice_progress'), error => (error as {code?: string}).code === '42501');
        await client.query('BEGIN');
        await client.query("SELECT set_config('trimmy.practice_user_id',$1,true)", [users[2]]);
        const rows = await client.query<{user_id: string}>('SELECT user_id FROM trimmy.watchlists');
        assert.deepEqual(rows.rows.map(row => row.user_id), [users[2]]);
        await client.query('ROLLBACK');
        assert.equal((await client.query('SELECT * FROM trimmy.watchlists')).rows.length, 0);
      } finally { client.release(); }
    });

    test('owner and bypass-role memberships are rejected by the repository guard', async () => {
      for (const user of ['trimmy_test_owner', 'trimmy_practice_test_unsafe']) {
        const privileged = new Pool({...connection, user, max: 1});
        try {
          await assert.rejects(new PostgresWatchlistRepository(privileged, {allowedAssetIds}).get(users[0]), error =>
            error instanceof WatchlistRepositoryError && error.code === 'WATCHLIST_RUNTIME_ROLE_INVALID');
        } finally { await privileged.end(); }
      }
    });
  });
}
