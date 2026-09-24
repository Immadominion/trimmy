import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import type { PracticeProgress } from '@trimmy/domain';
import { buildApp } from '../src/app.js';
import { PracticeRepositoryError } from '../src/practice-repository.js';
import type { PracticeRepository, PracticeRepositoryErrorCode, PracticeSnapshot, PracticeWrite } from '../src/practice-repository.js';
import type { PracticeSyncAdapters } from '../src/practice-routes.js';

const path = '/v1/practice/progress';
const userA = '11111111-1111-4111-8111-111111111111';
const userB = '22222222-2222-4222-8222-222222222222';
const mutationId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const time = '2026-09-14T02:03:04.005Z';
const progress: PracticeProgress = {version: 3, active: null, completions: {}};
const empty: PracticeSnapshot = {revision: 0, progress: null, updatedAt: null};
const payload = () => ({schemaVersion: 1, mutationId, baseRevision: 0, progress});
const wrapped = (snapshot: PracticeSnapshot) => ({schemaVersion: 1, ...snapshot});

function repository(overrides: Partial<PracticeRepository> = {}): PracticeRepository {
  return {
    get: async () => empty,
    put: async (_userId, command) => ({revision: command.baseRevision + 1, progress: command.progress, updatedAt: time}),
    ...overrides,
  };
}

// Only a test verifier. Production bootstrap supplies no authentication adapter.
const verifiedA: PracticeSyncAdapters['authenticate'] = async () => ({userId: userA});

describe('authenticated practice HTTP boundary', () => {
  it('fails closed without adapters, including pretend credentials and malformed writes', async () => {
    const app = buildApp({logger: false});
    try {
      for (const method of ['GET', 'PUT'] as const) {
        const response = await app.inject({method, url: path,
          headers: {authorization: 'Bearer arbitrary-secret', 'x-user-id': userA, 'content-type': 'application/json'},
          ...(method === 'PUT' ? {payload: '{invalid-secret-json'} : {}),
        });
        assert.equal(response.statusCode, 503);
        assert.equal(response.json().error.code, 'PRACTICE_SYNC_UNAVAILABLE');
        assert.ok(!response.body.includes('secret'));
      }
      const config = (await app.inject('/v1/config')).json();
      assert.equal(config.practiceSyncEnabled, false);
      assert.equal(config.capabilities.persistenceEnabled, false);
    } finally { await app.close(); }
  });

  it('requires both storage methods and a verifier before advertising availability', async () => {
    const incomplete = {repository: {get: async () => empty}, authenticate: verifiedA} as unknown as PracticeSyncAdapters;
    const app = buildApp({logger: false, practice: incomplete});
    try {
      assert.equal((await app.inject(path)).statusCode, 503);
      assert.equal((await app.inject('/v1/config')).json().practiceSyncEnabled, false);
    } finally { await app.close(); }
  });

  it('rejects missing, invalid and failed identity verification before parsing or storage', async () => {
    const verifiers: PracticeSyncAdapters['authenticate'][] = [
      async () => null,
      async () => ({userId: 'not-a-server-uuid'}),
      async () => { throw new Error('private-provider-token'); },
    ];
    for (const authenticate of verifiers) {
      let calls = 0;
      const app = buildApp({logger: false, practice: {authenticate, repository: repository({
        get: async () => { calls++; return empty; },
        put: async () => { calls++; return empty; },
      })}});
      try {
        for (const method of ['GET', 'PUT'] as const) {
          const response = await app.inject({method, url: path,
            headers: {authorization: 'Bearer pretend', 'x-user-id': userA, 'content-type': 'application/json'},
            ...(method === 'PUT' ? {payload: '{not valid JSON private-provider-token'} : {}),
          });
          assert.equal(response.statusCode, 401);
          assert.equal(response.json().error.code, 'PRACTICE_UNAUTHENTICATED');
          assert.ok(!response.body.includes('private-provider-token'));
        }
        assert.equal(calls, 0);
      } finally { await app.close(); }
    }
  });

  it('keeps concurrent authenticated reads and writes scoped to their verified accounts', async () => {
    const calls: [string, string][] = [];
    const states = new Map<string, PracticeSnapshot>([[userA, empty], [userB, {revision: 7, progress, updatedAt: time}]]);
    const app = buildApp({logger: false, practice: {
      authenticate: async request => request.headers.authorization === 'test-proof-a' ? {userId: userA}
        : request.headers.authorization === 'test-proof-b' ? {userId: userB} : null,
      repository: repository({
        get: async id => { calls.push(['get', id]); await Promise.resolve(); return states.get(id)!; },
        put: async (id, command) => {
          calls.push(['put', id]);
          assert.equal(command.mutationId, mutationId);
          assert.equal(command.baseRevision, 0);
          const saved = {revision: 1, progress: command.progress, updatedAt: time};
          states.set(id, saved); return saved;
        },
      }),
    }});
    try {
      const [a, b] = await Promise.all([
        app.inject({url: path, headers: {authorization: 'test-proof-a', 'x-user-id': userB}}),
        app.inject({url: path, headers: {authorization: 'test-proof-b', 'x-user-id': userA}}),
      ]);
      assert.deepEqual(a.json(), wrapped(empty));
      assert.deepEqual(b.json(), wrapped(states.get(userB)!));
      const saved = await app.inject({method: 'PUT', url: path, payload: payload(), headers: {authorization: 'test-proof-a', 'x-user-id': userB}});
      assert.equal(saved.statusCode, 200);
      assert.equal(saved.json().revision, 1);
      assert.equal(states.get(userB)!.revision, 7);
      assert.deepEqual(calls, [['get', userA], ['get', userB], ['put', userA]]);
      assert.equal(saved.headers['cache-control'], 'no-store');
      assert.equal(saved.headers['x-content-type-options'], 'nosniff');
      assert.equal(saved.headers['access-control-allow-origin'], undefined);
    } finally { await app.close(); }
  });

  it('passes the normalized write to storage and preserves native timestamp precision', async () => {
    const completionTime = '2026-09-14T02:03:04.005678Z';
    const complete: PracticeProgress = {version: 3, active: null, completions: {
      'check-the-date': {activityId: 'check-the-date', selectedChoiceId: 'add-year', corrected: false, completedAt: completionTime, importedFromLegacy: false},
    }};
    const received: PracticeWrite[] = [];
    const app = buildApp({logger: false, practice: {authenticate: verifiedA, repository: repository({
      put: async (id, command) => {
        assert.equal(id, userA); received.push(command);
        return {revision: 2, progress: command.progress, updatedAt: time};
      },
    })}});
    try {
      for (let repeat = 0; repeat < 2; repeat++) {
        const response = await app.inject({method: 'PUT', url: path, payload: {...payload(), mutationId: mutationId.toUpperCase(), baseRevision: 1, progress: complete}});
        assert.equal(response.statusCode, 200);
        assert.deepEqual(response.json(), wrapped({revision: 2, progress: complete, updatedAt: time}));
      }
      assert.equal(received.length, 2);
      assert.deepEqual(received[0], {mutationId, baseRevision: 1, progress: complete});
      assert.deepEqual(received[1], received[0]);
      assert.ok(!Object.hasOwn(received[0]!, 'schemaVersion'));
    } finally { await app.close(); }
  });

  it('strictly rejects wrapper/progress changes, account hints and unknown queries without echoing them', async () => {
    let calls = 0;
    const app = buildApp({logger: false, practice: {authenticate: verifiedA, repository: repository({
      get: async () => { calls++; return empty; },
      put: async () => { calls++; return empty; },
    })}});
    try {
      const invalid = [
        null, [], {...payload(), userId: userB}, {...payload(), schemaVersion: '1'},
        {...payload(), schemaVersion: 2}, {...payload(), baseRevision: '0'},
        {...payload(), baseRevision: -1}, {...payload(), baseRevision: Number.MAX_SAFE_INTEGER + 1},
        {...payload(), mutationId: 'private-unverified-mutation'},
        {...payload(), progress: {...progress, version: 2}},
        {...payload(), progress: {...progress, wallet: 'private-wallet-secret'}},
        {...payload(), progress: {...progress, active: {activityId: 'unknown-private-activity'}}},
      ];
      for (const value of invalid) {
        const response = await app.inject({method: 'PUT', url: path, headers: {'content-type': 'application/json'}, payload: JSON.stringify(value)});
        assert.equal(response.statusCode, 400);
        assert.ok(!response.body.includes('private-'));
        assert.ok(!response.body.includes(userB));
      }
      for (const method of ['GET', 'PUT'] as const) {
        const response = await app.inject({method, url: `${path}?userId=${userB}&token=private-query-secret`, ...(method === 'PUT' ? {payload: payload()} : {})});
        assert.equal(response.statusCode, 400);
        assert.equal(response.json().error.code, 'INVALID_REQUEST');
        assert.ok(!response.body.includes('private-query-secret'));
      }
      assert.equal(calls, 0);
    } finally { await app.close(); }
  });

  it('uses a bounded JSON envelope, a separate UTF-8 progress limit and safe parse errors', async () => {
    let writes = 0;
    const app = buildApp({logger: false, practice: {authenticate: verifiedA, repository: repository({put: async () => { writes++; return {revision: 1, progress, updatedAt: time}; }})}});
    try {
      // More than the global 16KB limit but within this route's 36KB envelope.
      const padded = await app.inject({method: 'PUT', url: path, headers: {'content-type': 'application/json'}, payload: ' '.repeat(18_000) + JSON.stringify(payload())});
      assert.equal(padded.statusCode, 200);
      const oversized = await app.inject({method: 'PUT', url: path, payload: {...payload(), progress: 'private-' + 'x'.repeat(37_000)}});
      assert.equal(oversized.statusCode, 413);
      assert.equal(oversized.json().error.code, 'PAYLOAD_TOO_LARGE');
      const multibyte = await app.inject({method: 'PUT', url: path, payload: {...payload(), progress: 'é'.repeat(17_000)}});
      assert.equal(multibyte.statusCode, 400);
      assert.equal(multibyte.json().error.code, 'PRACTICE_INVALID_INPUT');
      const malformed = await app.inject({method: 'PUT', url: path, headers: {'content-type': 'application/json'}, payload: '{private-invalid-json'});
      assert.equal(malformed.statusCode, 400);
      assert.ok(!malformed.body.includes('private-invalid-json'));
      const unsupported = await app.inject({method: 'PUT', url: path, headers: {'content-type': 'application/octet-stream'}, payload: 'private-binary-body'});
      assert.equal(unsupported.statusCode, 415);
      assert.equal(unsupported.json().error.code, 'UNSUPPORTED_MEDIA_TYPE');
      assert.ok(!unsupported.body.includes('private-binary-body'));
      assert.equal(writes, 1);
    } finally { await app.close(); }
  });

  it('returns only the current authenticated snapshot on a revision conflict', async () => {
    const current: PracticeSnapshot = {revision: 9, progress, updatedAt: time};
    const app = buildApp({logger: false, practice: {authenticate: verifiedA, repository: repository({
      put: async id => { assert.equal(id, userA); throw new PracticeRepositoryError('PRACTICE_REVISION_CONFLICT', 'postgres-password-secret', current); },
    })}});
    try {
      const response = await app.inject({method: 'PUT', url: path, payload: payload(), headers: {'x-user-id': userB, 'x-request-id': 'client-controlled'}});
      assert.equal(response.statusCode, 409);
      assert.equal(response.json().error.code, 'PRACTICE_REVISION_CONFLICT');
      assert.deepEqual(response.json().currentSnapshot, wrapped(current));
      assert.equal(response.json().error.requestId, response.headers['x-request-id']);
      assert.notEqual(response.headers['x-request-id'], 'client-controlled');
      assert.ok(!response.body.includes('postgres-password-secret'));
      assert.ok(!response.body.includes(userB));
    } finally { await app.close(); }
  });

  it('maps repository failures to fixed safe errors without provider details', async () => {
    const cases: [PracticeRepositoryErrorCode, number][] = [
      ['PRACTICE_INVALID_INPUT', 400], ['PRACTICE_ACCOUNT_NOT_FOUND', 404],
      ['PRACTICE_VERSION_DOWNGRADE', 409], ['PRACTICE_IDEMPOTENCY_CONFLICT', 409], ['PRACTICE_HISTORY_CONFLICT', 409],
      ['PRACTICE_REVISION_EXHAUSTED', 503], ['PRACTICE_STORAGE_INVALID', 500], ['PRACTICE_RUNTIME_ROLE_INVALID', 500],
    ];
    for (const [code, status] of cases) {
      const app = buildApp({logger: false, practice: {authenticate: verifiedA, repository: repository({put: async () => { throw new PracticeRepositoryError(code, 'private-db-connection-and-token'); }})}});
      try {
        const response = await app.inject({method: 'PUT', url: path, payload: payload()});
        assert.equal(response.statusCode, status);
        assert.equal(response.json().error.code, code);
        assert.ok(!response.body.includes('private-db-connection-and-token'));
        assert.equal(response.json().currentSnapshot, undefined);
      } finally { await app.close(); }
    }
  });

  it('fails safely on malformed repository output and unclassified failures', async () => {
    const malformed = {revision: 1, progress: {...progress, privateToken: 'private-stored-token'}, updatedAt: time} as unknown as PracticeSnapshot;
    for (const failure of ['output', 'conflict', 'missing-conflict', 'unknown'] as const) {
      const app = buildApp({logger: false, practice: {authenticate: verifiedA, repository: repository({get: async () => {
        if (failure === 'output') return malformed;
        if (failure === 'conflict') throw new PracticeRepositoryError('PRACTICE_REVISION_CONFLICT', 'private-message', malformed);
        if (failure === 'missing-conflict') throw new PracticeRepositoryError('PRACTICE_REVISION_CONFLICT', 'private-message');
        throw new Error('private-storage-password');
      }})}});
      try {
        const response = await app.inject(path);
        assert.equal(response.statusCode, failure === 'unknown' ? 503 : 500);
        assert.ok(!response.body.includes('private-'));
      } finally { await app.close(); }
    }
  });

  it('keeps every financial mutation and practice route variant disabled with adapters installed', async () => {
    let calls = 0;
    const app = buildApp({logger: false, practice: {authenticate: async () => { calls++; return {userId: userA}; }, repository: repository()}});
    try {
      const config = (await app.inject('/v1/config')).json();
      assert.equal(config.practiceSyncEnabled, true);
      assert.equal(config.capabilities.persistenceEnabled, false);
      assert.equal(config.capabilities.financialOperationsEnabled, false);
      const blocked: ['POST' | 'PUT' | 'PATCH' | 'DELETE', string][] = [
        ['POST', path], ['PATCH', path], ['DELETE', path], ['PUT', `${path}/`],
        ['PUT', `${path}/execute`], ['PUT', `${path}-extra`], ['PUT', '/v1/practice'],
        ['PUT', '/v1/execute'], ['PUT', '/v1/invitations'], ['DELETE', '/v1/invitations'],
        ['POST', '/v1/quotes'],
        ['POST', '/api/sponsor'], ['POST', '/api/recipient'], ['DELETE', '/v1/config'],
      ];
      for (const [method, url] of blocked) {
        const response = await app.inject({method, url, payload: {financialOperationsEnabled: true, transaction: 'private-fake-signature'}});
        assert.equal(response.statusCode, 503, `${method} ${url}`);
        assert.equal(response.json().error.code, 'FINANCIAL_OPERATIONS_DISABLED');
        assert.ok(!response.body.includes('private-fake-signature'));
      }
      assert.equal(calls, 0);
    } finally { await app.close(); }
  });
});
