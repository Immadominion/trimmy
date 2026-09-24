import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { after, describe, test } from 'node:test';
import { Pool } from 'pg';
import { buildApp } from '../../src/app.js';
import { PostgresWatchlistRepository } from '../../src/postgres-watchlist-repository.js';
import { FOLLOWING_ROUTE } from '../../src/watchlist-routes.js';
import type { WatchlistCatalog } from '../../src/watchlist-repository.js';

const socket = process.env['TRIMMY_PRACTICE_TEST_SOCKET'];
assert.ok(socket?.endsWith('/infra/.practice-runtime/socket'), 'Use the private test runner; never attach to an external database.');
assert.equal(process.env['TRIMMY_PRACTICE_TEST_PORT'], '65438');

const ONE = '00000000-0000-4000-8000-000000000041';
const TWO = '00000000-0000-4000-8000-000000000042';
const proofs = new Map([['Bearer one', ONE], ['Bearer two', TWO]]);

const pool = new Pool({
  host: socket, port: 65438, database: 'postgres', user: 'trimmy_following_test_app',
  connectionTimeoutMillis: 3000, max: 4,
});
const owner = new Pool({
  host: socket, port: 65438, database: 'postgres', user: 'trimmy_test_owner',
  connectionTimeoutMillis: 3000, max: 2,
});
for (const created of [pool, owner]) created.on('error', () => {});
after(async () => { for (const created of [pool, owner]) await created.end().catch(() => {}); });

/** Sample slugs are reserved, so the real list and the sample list stay disjoint. */
const catalog: WatchlistCatalog = Object.freeze({
  kind: 'provider', reservedAssetIds: new Set(['forma', 'orbital', 'grove', 'harbor', 'mesa', 'nori', 'pollen', 'helios']),
});

const app = buildApp({
  logger: false,
  following: {
    repository: new PostgresWatchlistRepository(pool, {allowedAssetIds: catalog, tables: 'followed_stocks'}),
    allowedAssetIds: catalog,
    route: FOLLOWING_ROUTE,
    authenticate: async request => {
      const userId = proofs.get(String(request.headers.authorization ?? ''));
      return userId ? {userId} : null;
    },
  },
});
after(async () => { await app.close(); });

const put = (token: string, body: unknown) =>
  app.inject({method: 'PUT', url: FOLLOWING_ROUTE, headers: {authorization: token}, payload: body as never});
const get = (token: string) =>
  app.inject({method: 'GET', url: FOLLOWING_ROUTE, headers: {authorization: token}});

describe('following a real looked-up asset', () => {
  test('a discovered asset is kept and read back', async () => {
    const empty = await get('Bearer one');
    assert.equal(empty.statusCode, 200);
    assert.deepEqual(empty.json(), {schemaVersion: 1, revision: 0, assetIds: [], updatedAt: null});

    // Exactly the identifier shape discovery returns, including a leading digit
    // and a length the sample catalog would have refused.
    const saved = await put('Bearer one', {
      schemaVersion: 1, mutationId: randomUUID(), baseRevision: 0,
      assetIds: ['apple', 'example-company', '3m-company'],
    });
    assert.equal(saved.statusCode, 200, saved.body);
    assert.equal(saved.json().revision, 1);
    assert.deepEqual(saved.json().assetIds, ['apple', 'example-company', '3m-company']);

    const reread = await get('Bearer one');
    assert.deepEqual(reread.json().assetIds, ['apple', 'example-company', '3m-company']);
  });

  test('a fictional sample slug is refused by the database as well as the API', async () => {
    const refused = await put('Bearer two', {
      schemaVersion: 1, mutationId: randomUUID(), baseRevision: 0, assetIds: ['forma'],
    });
    assert.equal(refused.statusCode, 400, refused.body);
    assert.equal(refused.json().error.code, 'WATCHLIST_INVALID_INPUT');
    // The same value is refused by the stored constraint, so the boundary holds
    // even if the API validation were bypassed.
    await assert.rejects(owner.query(
      `INSERT INTO trimmy.followed_stocks (user_id, revision, asset_ids, updated_at)
       VALUES ($1::uuid, 1, '["forma"]'::jsonb, now())`, [TWO]), /followed_stock/);
  });

  test('each account keeps its own list and cannot see another', async () => {
    const mine = await get('Bearer one');
    const theirs = await get('Bearer two');
    assert.ok(mine.json().assetIds.includes('apple'));
    assert.deepEqual(theirs.json().assetIds, [], 'another account must see nothing of mine');
  });

  test('a stale revision is refused with the current list', async () => {
    const conflict = await put('Bearer one', {
      schemaVersion: 1, mutationId: randomUUID(), baseRevision: 0, assetIds: ['apple'],
    });
    assert.equal(conflict.statusCode, 409);
    assert.equal(conflict.json().error.code, 'WATCHLIST_REVISION_CONFLICT');
    assert.equal(conflict.json().currentSnapshot.revision, 1);
  });

  test('the same mutation replayed returns the first outcome', async () => {
    const mutationId = randomUUID();
    const body = {schemaVersion: 1, mutationId, baseRevision: 1, assetIds: ['apple']};
    const first = await put('Bearer one', body);
    assert.equal(first.statusCode, 200, first.body);
    const replay = await put('Bearer one', body);
    assert.equal(replay.statusCode, 200);
    assert.deepEqual(replay.json(), first.json());
  });

  test('the two lists are separate storage, not two views of one', async () => {
    // This role was granted nothing on the sample watchlist on purpose.
    await assert.rejects(pool.query('SELECT 1 FROM trimmy.watchlists'), /permission denied/i);
    const {rows} = await owner.query<{total: string}>(
      'SELECT count(*)::text AS total FROM trimmy.watchlists WHERE user_id = $1::uuid', [ONE]);
    assert.equal(rows[0]?.total, '0', 'following an asset must not write the sample list');
  });

  test('the serving role can never delete a followed list or its receipts', async () => {
    for (const table of ['followed_stocks', 'followed_stock_mutation_receipts']) {
      await assert.rejects(pool.query(`DELETE FROM trimmy.${table}`), /permission denied/i);
    }
  });

  test('following grants no catalog authority', async () => {
    const catalogResponse = await app.inject({method: 'GET', url: '/v1/catalog'});
    assert.deepEqual(catalogResponse.json().assets, [], 'a followed asset is not an approved asset');
    assert.equal(catalogResponse.json().status, 'unverified');
    assert.equal(catalogResponse.json().financialOperationsEnabled, false);
  });
});
