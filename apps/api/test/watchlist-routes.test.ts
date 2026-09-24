import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { buildApp } from '../src/app.js';
import { PracticeAuthenticationUnavailable } from '../src/practice-session-routes.js';
import { WatchlistRepositoryError } from '../src/watchlist-repository.js';
import type { WatchlistRepository, WatchlistRepositoryErrorCode, WatchlistSnapshot } from '../src/watchlist-repository.js';
import type { WatchlistAdapters } from '../src/watchlist-routes.js';

const path = '/v1/watchlist';
const userA = '11111111-1111-4111-8111-111111111111';
const userB = '22222222-2222-4222-8222-222222222222';
const mutationId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const time = '2026-09-14T02:03:04.005Z';
const allowedAssetIds = new Set(['forma', 'orbital', 'grove']);
const empty: WatchlistSnapshot = {revision: 0, assetIds: [], updatedAt: null};
const payload = () => ({schemaVersion: 1, mutationId, baseRevision: 0, assetIds: ['forma', 'orbital']});
const wrap = (value: WatchlistSnapshot) => ({schemaVersion: 1, ...value});
function repository(overrides: Partial<WatchlistRepository> = {}): WatchlistRepository {
  return {get: async () => empty, put: async (_id, command) => ({revision: command.baseRevision + 1, assetIds: command.assetIds, updatedAt: time}), ...overrides};
}
const verifiedA: WatchlistAdapters['authenticate'] = async () => ({userId: userA});
function adapters(overrides: Partial<WatchlistAdapters> = {}): WatchlistAdapters {
  return {repository: repository(), authenticate: verifiedA, allowedAssetIds, ...overrides};
}

describe('verified watchlist HTTP boundary', () => {
  it('fails closed with no adapters, malformed writes and arbitrary bearer credentials', async () => {
    const app = buildApp({logger: false});
    try {
      for (const method of ['GET', 'PUT'] as const) {
        const response = await app.inject({method, url: path, headers: {authorization: 'Bearer private-token', 'x-user-id': userA, 'content-type': 'application/json'}, ...(method === 'PUT' ? {payload: '{private-invalid-json'} : {})});
        assert.equal(response.statusCode, 503);
        assert.equal(response.json().error.code, 'WATCHLIST_UNAVAILABLE');
        assert.ok(!response.body.includes('private-'));
      }
    } finally { await app.close(); }
  });

  it('authenticates before parsing bodies and distinguishes unavailable verification', async () => {
    for (const kind of ['null', 'invalid', 'throws', 'unavailable'] as const) {
      let calls = 0;
      const app = buildApp({logger: false, watchlist: adapters({
        authenticate: async () => {
          if (kind === 'unavailable') throw new PracticeAuthenticationUnavailable();
          if (kind === 'throws') throw new Error('private-provider-token');
          return kind === 'null' ? null : {userId: 'unverified'};
        }, repository: repository({put: async () => { calls++; return empty; }}),
      })});
      try {
        const response = await app.inject({method: 'PUT', url: path, headers: {'content-type': 'application/json'}, payload: '{private-invalid-json'});
        assert.equal(response.statusCode, kind === 'unavailable' ? 503 : 401);
        assert.ok(!response.body.includes('private-'));
        assert.equal(calls, 0);
      } finally { await app.close(); }
    }
  });

  it('scopes concurrent requests to verified identity and preserves ordered/empty lists', async () => {
    const states = new Map<string, WatchlistSnapshot>([[userA, empty], [userB, {revision: 7, assetIds: ['grove'], updatedAt: time}]]);
    const seen: string[] = [];
    const app = buildApp({logger: false, watchlist: adapters({
      authenticate: async request => request.headers.authorization === 'test-proof-a' ? {userId: userA.toUpperCase()} : request.headers.authorization === 'test-proof-b' ? {userId: userB} : null,
      repository: repository({
        get: async id => { seen.push(id); await Promise.resolve(); return states.get(id)!; },
        put: async (id, command) => {
          seen.push(id); assert.ok(Object.isFrozen(command)); assert.ok(Object.isFrozen(command.assetIds));
          assert.equal(command.mutationId, mutationId);
          const next = {revision: command.baseRevision + 1, assetIds: command.assetIds, updatedAt: time};
          states.set(id, next); return next;
        },
      }),
    })});
    try {
      const [a, b] = await Promise.all([
        app.inject({url: path, headers: {authorization: 'test-proof-a', 'x-user-id': userB}}),
        app.inject({url: path, headers: {authorization: 'test-proof-b', 'x-user-id': userA}}),
      ]);
      assert.deepEqual(a.json(), wrap(empty));
      assert.deepEqual(b.json(), wrap(states.get(userB)!));
      for (const [index, assetIds] of [['orbital', 'forma'], []].entries()) {
        const saved = await app.inject({method: 'PUT', url: path, headers: {authorization: 'test-proof-a', 'x-user-id': userB}, payload: {...payload(), mutationId: mutationId.toUpperCase(), baseRevision: index, assetIds}});
        assert.equal(saved.statusCode, 200, saved.body);
        assert.deepEqual(saved.json().assetIds, assetIds);
        assert.equal(saved.json().revision, index + 1);
        assert.equal(saved.headers['cache-control'], 'no-store');
      }
      assert.equal(states.get(userB)!.revision, 7);
      assert.deepEqual(seen, [userA, userB, userA, userA]);
    } finally { await app.close(); }
  });

  it('rejects strict envelope violations, unknown assets and all query identity hints', async () => {
    let calls = 0;
    const app = buildApp({logger: false, watchlist: adapters({repository: repository({get: async () => { calls++; return empty; }, put: async () => { calls++; return empty; }})})});
    try {
      for (const value of [null, [], {...payload(), userId: userB}, {...payload(), schemaVersion: 2}, {...payload(), schemaVersion: '1'}, {...payload(), baseRevision: -1}, {...payload(), baseRevision: Number.MAX_SAFE_INTEGER + 1}, {...payload(), mutationId: 'private-id'}, {...payload(), assetIds: ['private-unknown']}, {...payload(), assetIds: ['forma', 'forma']}, {...payload(), assetIds: Array(51).fill('forma')}, {...payload(), assetIds: null}]) {
        const response = await app.inject({method: 'PUT', url: path, headers: {'content-type': 'application/json'}, payload: JSON.stringify(value)});
        assert.equal(response.statusCode, 400);
        assert.ok(!response.body.includes('private-'));
        assert.ok(!response.body.includes(userB));
      }
      for (const method of ['GET', 'PUT'] as const) {
        const response = await app.inject({method, url: `${path}?userId=${userB}&secret=private-query`, ...(method === 'PUT' ? {payload: payload()} : {})});
        assert.equal(response.statusCode, 400);
        assert.ok(!response.body.includes('private-query'));
      }
      assert.equal(calls, 0);
    } finally { await app.close(); }
  });

  it('limits JSON body bytes and safely handles parser/media errors', async () => {
    const app = buildApp({logger: false, watchlist: adapters()});
    try {
      const oversized = await app.inject({method: 'PUT', url: path, payload: {...payload(), assetIds: ['é'.repeat(5000)]}});
      assert.equal(oversized.statusCode, 413);
      assert.equal(oversized.json().error.code, 'PAYLOAD_TOO_LARGE');
      const malformed = await app.inject({method: 'PUT', url: path, headers: {'content-type': 'application/json'}, payload: '{private-payload'});
      assert.equal(malformed.statusCode, 400);
      const media = await app.inject({method: 'PUT', url: path, headers: {'content-type': 'application/octet-stream'}, payload: 'private-payload'});
      assert.equal(media.statusCode, 415);
      assert.ok(!malformed.body.includes('private-payload'));
      assert.ok(!media.body.includes('private-payload'));
    } finally { await app.close(); }
  });

  it('returns validated conflict snapshots and fixed safe storage errors', async () => {
    const current = {revision: 4, assetIds: ['grove'], updatedAt: time};
    const cases: [WatchlistRepositoryErrorCode, number][] = [
      ['WATCHLIST_INVALID_INPUT', 400], ['WATCHLIST_ACCOUNT_NOT_FOUND', 404], ['WATCHLIST_IDEMPOTENCY_CONFLICT', 409],
      ['WATCHLIST_REVISION_CONFLICT', 409], ['WATCHLIST_REVISION_EXHAUSTED', 503], ['WATCHLIST_STORAGE_INVALID', 500], ['WATCHLIST_RUNTIME_ROLE_INVALID', 500],
    ];
    for (const [code, status] of cases) {
      const app = buildApp({logger: false, watchlist: adapters({repository: repository({put: async id => {
        assert.equal(id, userA); throw new WatchlistRepositoryError(code, 'private-database-password', current);
      }})})});
      try {
        const response = await app.inject({method: 'PUT', url: path, payload: payload(), headers: {'x-user-id': userB}});
        assert.equal(response.statusCode, status);
        assert.equal(response.json().error.code, code);
        assert.ok(!response.body.includes('private-'));
        assert.deepEqual(response.json().currentSnapshot, code === 'WATCHLIST_REVISION_CONFLICT' ? wrap(current) : undefined);
      } finally { await app.close(); }
    }
  });

  it('rejects malformed storage, mismatched success receipts and missing conflict data', async () => {
    for (const kind of ['unknown-error', 'bad-list', 'extra-field', 'bad-ack', 'missing-conflict', 'bad-conflict'] as const) {
      const app = buildApp({logger: false, watchlist: adapters({repository: repository({put: async () => {
        if (kind === 'unknown-error') throw new Error('private-driver-error');
        if (kind === 'missing-conflict') throw new WatchlistRepositoryError('WATCHLIST_REVISION_CONFLICT', 'private-message');
        const bad = {revision: 1, assetIds: ['private-asset'], updatedAt: time};
        if (kind === 'bad-conflict') throw new WatchlistRepositoryError('WATCHLIST_REVISION_CONFLICT', 'private-message', bad);
        if (kind === 'extra-field') return {...empty, privateToken: 'private-token'};
        if (kind === 'bad-ack') return {revision: 1, assetIds: [], updatedAt: time};
        return bad;
      }})})});
      try {
        const response = await app.inject({method: 'PUT', url: path, payload: payload()});
        assert.equal(response.statusCode, kind === 'unknown-error' ? 503 : 500);
        assert.ok(!response.body.includes('private-'));
      } finally { await app.close(); }
    }
  });

  it('keeps financial writes and every nonexact watchlist route blocked', async () => {
    let calls = 0;
    const app = buildApp({logger: false, watchlist: adapters({authenticate: async () => { calls++; return {userId: userA}; }})});
    try {
      for (const [method, url] of [['POST', path], ['PATCH', path], ['DELETE', path], ['PUT', `${path}/`], ['PUT', `${path}/execute`], ['PUT', `${path}-extra`], ['POST', '/v1/orders'], ['PUT', '/v1/execute']] as const) {
        const response = await app.inject({method, url, payload: payload()});
        assert.equal(response.statusCode, 503, `${method} ${url}`);
        assert.equal(response.json().error.code, 'FINANCIAL_OPERATIONS_DISABLED');
      }
      const config = (await app.inject('/v1/config')).json();
      assert.equal(config.capabilities.financialOperationsEnabled, false);
      assert.equal(calls, 0);
    } finally { await app.close(); }
  });
});
