import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { describe, it } from 'node:test';
import { buildApp } from '../src/app.js';
import { EMPTY_WATCHLIST_SNAPSHOT, WatchlistRepositoryError } from '../src/watchlist-repository.js';
import type { WatchlistCatalog, WatchlistRepository, WatchlistSnapshot, WatchlistWrite } from '../src/watchlist-repository.js';
import { FOLLOWING_ROUTE, WATCHLIST_ROUTE } from '../src/watchlist-routes.js';

const ACCOUNT = '00000000-0000-4000-8000-0000000000aa';
const SAMPLE_IDS = ['forma', 'orbital', 'grove', 'harbor', 'mesa', 'nori', 'pollen', 'helios'];
const catalog: WatchlistCatalog = Object.freeze({kind: 'provider', reservedAssetIds: new Set(SAMPLE_IDS)});

/** Process-local list storage. Offline tests never reach a database. */
class MemoryList implements WatchlistRepository {
  #snapshot: WatchlistSnapshot = EMPTY_WATCHLIST_SNAPSHOT;

  async get(): Promise<WatchlistSnapshot> { return this.#snapshot; }

  async put(_userId: string, command: WatchlistWrite): Promise<WatchlistSnapshot> {
    if (command.baseRevision !== this.#snapshot.revision) {
      throw new WatchlistRepositoryError('WATCHLIST_REVISION_CONFLICT', 'changed', this.#snapshot);
    }
    this.#snapshot = Object.freeze({
      revision: command.baseRevision + 1, assetIds: command.assetIds,
      updatedAt: '2026-09-17T10:00:00.000Z',
    });
    return this.#snapshot;
  }
}

function configured(overrides: {route?: string} = {}) {
  return buildApp({
    logger: false,
    following: {
      repository: new MemoryList(), allowedAssetIds: catalog,
      route: overrides.route ?? FOLLOWING_ROUTE,
      authenticate: async request => (request.headers.authorization === 'Bearer ok' ? {userId: ACCOUNT} : null),
    },
  });
}

const write = (assetIds: readonly string[], baseRevision = 0) => ({
  schemaVersion: 1, mutationId: randomUUID(), baseRevision, assetIds,
});

describe('the real followed list', () => {
  it('is off by default and says so explicitly rather than looking absent', async () => {
    const app = buildApp({logger: false});
    try {
      assert.equal((await app.inject('/v1/config')).json().followedStocksEnabled, false);
      for (const method of ['GET', 'PUT'] as const) {
        const response = await app.inject({
          method, url: FOLLOWING_ROUTE, ...(method === 'PUT' ? {payload: write([])} : {}),
        });
        assert.equal(response.statusCode, 503, `${method} ${response.body}`);
        assert.equal(response.json().error.code, 'WATCHLIST_UNAVAILABLE');
      }
    } finally { await app.close(); }
  });

  it('keeps identifiers a provider could return and refuses the rest', async () => {
    const app = configured();
    try {
      assert.equal((await app.inject('/v1/config')).json().followedStocksEnabled, true);
      const saved = await app.inject({
        method: 'PUT', url: FOLLOWING_ROUTE, headers: {authorization: 'Bearer ok'},
        payload: write(['apple', '3m-company', 'a'.repeat(100)]),
      });
      assert.equal(saved.statusCode, 200, saved.body);
      assert.deepEqual(saved.json().assetIds, ['apple', '3m-company', 'a'.repeat(100)]);

      for (const bad of [['Apple'], ['apple '], ['-apple'], ['apple--x'], ['a'.repeat(101)], ['apple', 'apple'], [1], [null]]) {
        const response = await app.inject({
          method: 'PUT', url: FOLLOWING_ROUTE, headers: {authorization: 'Bearer ok'},
          payload: write(bad as readonly string[], 1),
        });
        assert.equal(response.statusCode, 400, JSON.stringify(bad));
      }
    } finally { await app.close(); }
  });

  it('refuses every fictional sample identifier', async () => {
    const app = configured();
    try {
      for (const sample of SAMPLE_IDS) {
        const response = await app.inject({
          method: 'PUT', url: FOLLOWING_ROUTE, headers: {authorization: 'Bearer ok'},
          payload: write([sample]),
        });
        // A sample ID stored here would later be read back as a real asset.
        assert.equal(response.statusCode, 400, sample);
        assert.equal(response.json().error.code, 'WATCHLIST_INVALID_INPUT');
      }
    } finally { await app.close(); }
  });

  it('requires a verified account', async () => {
    const app = configured();
    try {
      for (const method of ['GET', 'PUT'] as const) {
        const response = await app.inject({
          method, url: FOLLOWING_ROUTE, ...(method === 'PUT' ? {payload: write([])} : {}),
        });
        assert.equal(response.statusCode, 401);
        assert.equal(response.json().error.code, 'WATCHLIST_UNAUTHENTICATED');
      }
    } finally { await app.close(); }
  });

  it('is a separate list from the sample watchlist', async () => {
    const app = configured();
    try {
      await app.inject({
        method: 'PUT', url: FOLLOWING_ROUTE, headers: {authorization: 'Bearer ok'}, payload: write(['apple']),
      });
      // The sample watchlist was never configured here, so it stays unavailable
      // rather than returning what was written to the real list.
      const sample = await app.inject({method: 'GET', url: WATCHLIST_ROUTE, headers: {authorization: 'Bearer ok'}});
      assert.equal(sample.statusCode, 503);
      assert.equal(sample.json().error.code, 'WATCHLIST_UNAVAILABLE');
    } finally { await app.close(); }
  });

  it('allows only the list write, not other verbs', async () => {
    const app = configured();
    try {
      const allowed = await app.inject({
        method: 'PUT', url: FOLLOWING_ROUTE, headers: {authorization: 'Bearer ok'}, payload: write(['apple']),
      });
      assert.equal(allowed.statusCode, 200, allowed.body);
      for (const method of ['POST', 'PATCH', 'DELETE'] as const) {
        const response = await app.inject({method, url: FOLLOWING_ROUTE, headers: {authorization: 'Bearer ok'}, payload: {}});
        assert.equal(response.statusCode, 503, method);
        assert.equal(response.json().error.code, 'FINANCIAL_OPERATIONS_DISABLED');
      }
    } finally { await app.close(); }
  });

  it('fails closed when adapters name a different list than they are mounted on', async () => {
    // A miscomposed adapter must not serve one account list under another name.
    const app = configured({route: WATCHLIST_ROUTE});
    try {
      const response = await app.inject({method: 'GET', url: FOLLOWING_ROUTE, headers: {authorization: 'Bearer ok'}});
      assert.equal(response.statusCode, 503);
      // Config must not claim a list is available when its path refuses to serve.
      assert.equal((await app.inject('/v1/config')).json().followedStocksEnabled, false);
    } finally { await app.close(); }
  });

  it('following something is never a catalog approval', async () => {
    const app = configured();
    try {
      await app.inject({
        method: 'PUT', url: FOLLOWING_ROUTE, headers: {authorization: 'Bearer ok'}, payload: write(['apple']),
      });
      const catalogResponse = (await app.inject('/v1/catalog')).json();
      assert.deepEqual(catalogResponse.assets, []);
      assert.equal(catalogResponse.status, 'unverified');
      const config = (await app.inject('/v1/config')).json();
      assert.equal(config.capabilities.financialOperationsEnabled, false);
      assert.equal(config.moneyMode, 'practice_only');
    } finally { await app.close(); }
  });
});
