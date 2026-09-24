import assert from 'node:assert/strict';
import { setImmediate as nextTurn } from 'node:timers/promises';
import test from 'node:test';
import { WatchlistSession, WatchlistSyncError } from '../src/account/watchlist-sync.js';
import type { WatchlistOptions, WatchlistSnapshot, WatchlistStorage } from '../src/account/watchlist-sync.js';

const ACCOUNT = 'aa000000-0000-4000-8000-000000000001';
const OTHER = 'bb000000-0000-4000-8000-000000000002';
const time = '2026-09-14T12:00:00.000Z';
const snap = (revision: number, assetIds: readonly string[] = []): WatchlistSnapshot => ({schemaVersion: 1, revision, assetIds, updatedAt: revision ? time : null});
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {status, headers: {'content-type': 'application/json'}});
const error = (code: string, status: number, currentSnapshot?: WatchlistSnapshot) => json({error: {code, message: 'Request failed.', requestId: 'request-1'}, ...(currentSnapshot ? {currentSnapshot} : {})}, status);
function deferred<T>() { let resolve!: (value: T) => void; let reject!: (error: unknown) => void; const promise = new Promise<T>((yes, no) => {resolve = yes; reject = no;}); return {promise, resolve, reject}; }
async function until(condition: () => boolean): Promise<void> { for (let i = 0; i < 100 && !condition(); i++) await nextTurn(); assert.ok(condition(), 'operation reached expected boundary'); }
const code = (expected: string) => (error: unknown) => error instanceof WatchlistSyncError && error.code === expected;

class Store implements WatchlistStorage {
  readonly values = new Map<string, string>();
  readonly writes: string[] = [];
  fail = false;
  getItem(key: string) { return this.values.get(key) ?? null; }
  setItem(key: string, value: string) { if (this.fail) throw new Error('Disk unavailable'); this.writes.push(value); this.values.set(key, value); }
}
class Events {
  readonly listeners = new Set<(event: StorageEvent) => void>();
  addEventListener(_type: 'storage', listener: (event: StorageEvent) => void) { this.listeners.add(listener); }
  removeEventListener(_type: 'storage', listener: (event: StorageEvent) => void) { this.listeners.delete(listener); }
  send(key: string | null, newValue: string | null) { for (const listener of this.listeners) listener({key, newValue} as StorageEvent); }
}
class Server {
  snapshot = snap(0);
  accountId = ACCOUNT;
  readonly requests: {method: string; body: string | null; headers: Headers; signal: AbortSignal | null}[] = [];
  readonly receipts = new Map<string, WatchlistSnapshot>();
  getOverride?: () => Promise<Response>;
  postOverride?: () => Promise<Response>;
  putOverride: ((body: Record<string, unknown>) => Promise<Response>) | undefined;
  readonly fetch: typeof fetch = async (_url, init) => {
    const method = init?.method ?? 'GET'; const body = typeof init?.body === 'string' ? init.body : null;
    this.requests.push({method, body, headers: new Headers(init?.headers), signal: init?.signal ?? null});
    assert.equal(init?.redirect, 'error'); assert.equal(init?.credentials, 'omit');
    if (method === 'POST') return this.postOverride ? this.postOverride() : json({schemaVersion: 1, userId: this.accountId});
    if (method === 'GET') return this.getOverride ? this.getOverride() : json(this.snapshot);
    const parsed = JSON.parse(body!) as Record<string, unknown>;
    return this.putOverride ? this.putOverride(parsed) : this.commit(parsed);
  };
  commit(body: Record<string, unknown>): Response {
    const id = String(body['mutationId']); const receipt = this.receipts.get(id);
    if (receipt) return json(receipt);
    if (body['baseRevision'] !== this.snapshot.revision) return error('WATCHLIST_REVISION_CONFLICT', 409, this.snapshot);
    this.snapshot = snap(this.snapshot.revision + 1, body['assetIds'] as string[]);
    this.receipts.set(id, this.snapshot); return json(this.snapshot);
  }
}
let sequence = 0;
function setup() {
  const store = new Store(); const server = new Server(); const events = new Events();
  let subject: string | null = 'did:privy:A';
  const options: WatchlistOptions = {subject, currentSubject: () => subject, accessToken: async () => 'test-token', storage: store,
    storageEvents: events, apiBaseUrl: 'https://api.example', fetch: server.fetch,
    mutationId: () => `10000000-0000-4000-8000-${String(++sequence).padStart(12, '0')}`};
  return {store, server, events, options, changeSubject: (value: string | null) => {subject = value;}};
}

test('server identity scopes a separate durable account and restores its ordered remote watchlist', async () => {
  const h = setup(); h.server.snapshot = snap(4, ['grove', 'forma']);
  h.store.values.set('trimmy.web.workspace.v1', '{"version":1,"watchlist":["mesa"]}');
  const session = await WatchlistSession.open(h.options);
  assert.equal(session.accountId, ACCOUNT); assert.deepEqual(session.getSnapshot().assetIds, []);
  let changes = 0; const unsubscribe = session.subscribe(() => {changes++;});
  await session.synchronize(); assert.deepEqual(session.getSnapshot().assetIds, ['grove', 'forma']);
  assert.equal(session.getSnapshot().status, 'saved'); assert.equal(changes, 2);
  assert.equal(h.store.values.get('trimmy.web.workspace.v1'), '{"version":1,"watchlist":["mesa"]}');
  assert.ok(Object.isFrozen(session.getSnapshot())); assert.ok(Object.isFrozen(session.getSnapshot().assetIds));
  unsubscribe(); session.close();
});

test('storage failure cannot expose an edit or dispatch an unrecorded PUT', async () => {
  const h = setup(); const session = await WatchlistSession.open(h.options); await session.synchronize();
  h.store.fail = true; assert.throws(() => session.setAssetIds(['forma']), code('WATCHLIST_LOCAL_SAVE_FAILED'));
  assert.deepEqual(session.getSnapshot().assetIds, []);
  h.store.fail = false; session.setAssetIds(['forma']); h.store.fail = true;
  await assert.rejects(session.synchronize(), code('WATCHLIST_LOCAL_SAVE_FAILED'));
  assert.equal(h.server.requests.filter(item => item.method === 'PUT').length, 0);
  h.store.fail = false; await session.synchronize(); assert.deepEqual(h.server.snapshot.assetIds, ['forma']); session.close();
});

test('lost response after commit and a restart retry the identical persisted mutation', async () => {
  const h = setup(); let session = await WatchlistSession.open(h.options);
  session.setAssetIds(['forma']);
  h.server.putOverride = async body => {h.server.commit(body); throw new Error('Unknown reply');};
  await assert.rejects(session.synchronize(), code('WATCHLIST_NETWORK_ERROR'));
  const first = h.server.requests.find(item => item.method === 'PUT')!.body;
  assert.equal(session.getSnapshot().pending, true); assert.equal(h.server.snapshot.revision, 1);
  session.close(); h.server.putOverride = undefined;
  session = await WatchlistSession.open(h.options); const gets = h.server.requests.filter(item => item.method === 'GET').length;
  await session.synchronize();
  assert.equal(h.server.requests.filter(item => item.method === 'GET').length, gets);
  assert.equal(h.server.requests.filter(item => item.method === 'PUT').at(-1)!.body, first);
  assert.equal(h.server.snapshot.revision, 1); assert.equal(session.getSnapshot().pending, false); session.close();
});

test('a disk failure after server commit preserves the request until its receipt is acknowledged', async () => {
  const h = setup(); let session = await WatchlistSession.open(h.options); session.setAssetIds(['nori']);
  h.server.putOverride = async body => {const response = h.server.commit(body); h.store.fail = true; return response;};
  await assert.rejects(session.synchronize(), code('WATCHLIST_LOCAL_SAVE_FAILED'));
  const first = h.server.requests.find(item => item.method === 'PUT')!.body;
  session.close(); h.store.fail = false; h.server.putOverride = undefined;
  session = await WatchlistSession.open(h.options); await session.synchronize();
  assert.equal(h.server.requests.at(-1)!.body, first); assert.equal(h.server.snapshot.revision, 1); session.close();
});

test('held PUT permits local edits, coalesces synchronization, and preserves newer local order', async () => {
  const h = setup(); const held = deferred<Response>();
  const session = await WatchlistSession.open(h.options); session.setAssetIds(['forma']);
  h.server.putOverride = async () => held.promise;
  const syncing = session.synchronize(); assert.equal(session.synchronize(), syncing);
  await until(() => h.server.requests.some(item => item.method === 'PUT'));
  session.setAssetIds(['grove', 'forma']);
  const first = JSON.parse(h.server.requests.at(-1)!.body!) as Record<string, unknown>;
  held.resolve(h.server.commit(first)); await syncing;
  assert.deepEqual(session.getSnapshot().assetIds, ['grove', 'forma']); assert.equal(session.getSnapshot().status, 'local');
  h.server.putOverride = undefined; await session.synchronize();
  assert.deepEqual(h.server.snapshot.assetIds, ['grove', 'forma']); assert.equal(h.server.snapshot.revision, 2); session.close();
});

test('remote changes during GET keep divergent local changes as a persisted explicit conflict', async () => {
  const h = setup(); const held = deferred<Response>(); const session = await WatchlistSession.open(h.options);
  h.server.getOverride = () => held.promise;
  const syncing = session.synchronize(); await until(() => h.server.requests.some(item => item.method === 'GET'));
  session.setAssetIds(['forma']); held.resolve(json(snap(1, ['grove'])));
  await assert.rejects(syncing, code('WATCHLIST_REVISION_CONFLICT'));
  assert.deepEqual(session.getSnapshot().assetIds, ['forma']); assert.deepEqual(session.getSnapshot().conflictAssetIds, ['grove']);
  session.close(); const restarted = await WatchlistSession.open(h.options);
  assert.equal(restarted.getSnapshot().status, 'conflict'); restarted.useRemote();
  assert.deepEqual(restarted.getSnapshot().assetIds, ['grove']); assert.equal(restarted.getSnapshot().status, 'saved'); restarted.close();
});

test('409 rejects only its pending intent; explicit local choice uses the new server revision', async () => {
  const h = setup(); const session = await WatchlistSession.open(h.options); session.setAssetIds(['forma']);
  h.server.putOverride = async () => {h.server.snapshot = snap(1, ['grove']); return error('WATCHLIST_REVISION_CONFLICT', 409, h.server.snapshot);};
  await assert.rejects(session.synchronize(), code('WATCHLIST_REVISION_CONFLICT'));
  assert.equal(session.getSnapshot().pending, false); assert.deepEqual(session.getSnapshot().assetIds, ['forma']);
  h.server.putOverride = undefined; session.useLocal(); await session.synchronize();
  assert.equal(h.server.snapshot.revision, 2); assert.deepEqual(h.server.snapshot.assetIds, ['forma']); session.close();
});

test('same-revision tampering is a conflict even when the local copy was clean', async () => {
  const h = setup(); h.server.snapshot = snap(2, ['forma']);
  const session = await WatchlistSession.open(h.options); await session.synchronize();
  h.server.snapshot = snap(2, ['grove']);
  await assert.rejects(session.synchronize(), code('WATCHLIST_REVISION_CONFLICT'));
  assert.deepEqual(session.getSnapshot().assetIds, ['forma']); session.close();
});

test('an intentionally emptied account watchlist survives restart and uploads an empty ordered list', async () => {
  const h = setup(); h.server.snapshot = snap(1, ['forma']);
  let session = await WatchlistSession.open(h.options); await session.synchronize();
  const draft = ['grove']; session.setAssetIds(draft); draft.push('forma');
  assert.deepEqual(session.getSnapshot().assetIds, ['grove']);
  const before = h.store.values.get(session.storageKey);
  const unsafe = ['forma']; let getterCalled = false;
  Object.defineProperty(unsafe, '0', {get() {getterCalled = true; return 'grove';}, enumerable: true});
  assert.throws(() => session.setAssetIds(unsafe), code('WATCHLIST_INVALID_PROTOCOL'));
  assert.equal(getterCalled, false); assert.equal(h.store.values.get(session.storageKey), before);
  session.setAssetIds([]); session.close();
  session = await WatchlistSession.open(h.options); assert.deepEqual(session.getSnapshot().assetIds, []);
  await session.synchronize(); assert.equal(h.server.snapshot.revision, 2);
  assert.deepEqual(h.server.snapshot.assetIds, []); session.close();
});

test('future, malformed and wrong-account durable records remain unchanged and protected', async () => {
  for (const raw of ['{broken', '{"schemaVersion":2}', JSON.stringify({schemaVersion: 1, accountId: OTHER, local: [], base: null, pending: null, conflict: null}),
    JSON.stringify({schemaVersion: 1, accountId: ACCOUNT, local: ['unknown'], base: null, pending: null, conflict: null}),
    JSON.stringify({schemaVersion: 1, accountId: ACCOUNT, local: [], base: null, pending: {schemaVersion: 1, mutationId: ACCOUNT, baseRevision: 0, assetIds: []}, conflict: null})]) {
    const h = setup(); h.store.values.set(WatchlistSession.storageKey(ACCOUNT), raw);
    const session = await WatchlistSession.open(h.options);
    assert.equal(session.getSnapshot().status, 'protected'); assert.equal(h.store.writes.length, 0);
    assert.throws(() => session.setAssetIds(['forma']), WatchlistSyncError);
    await assert.rejects(session.synchronize(), WatchlistSyncError);
    assert.equal(h.store.values.get(session.storageKey), raw); assert.equal(h.server.requests.length, 1); session.close();
  }
});

test('out-of-band storage changes are detected before writing, with or without a storage event', async () => {
  for (const event of [false, true]) {
    const h = setup(); const session = await WatchlistSession.open(h.options);
    const replacement = JSON.stringify({schemaVersion: 1, accountId: ACCOUNT, local: ['grove'], base: null, pending: null, conflict: null});
    h.store.values.set(session.storageKey, replacement);
    if (event) h.events.send(session.storageKey, replacement);
    assert.throws(() => session.setAssetIds(['forma']), code('WATCHLIST_STORAGE_CHANGED'));
    assert.equal(h.store.values.get(session.storageKey), replacement);
    assert.equal(session.getSnapshot().status, 'protected'); session.reload();
    assert.deepEqual(session.getSnapshot().assetIds, ['grove']); session.close(); assert.equal(h.events.listeners.size, 0);
  }
});

test('same-window duplicate owners are rejected and separate accounts retain separate records', async () => {
  const h = setup(); const a = await WatchlistSession.open(h.options);
  await assert.rejects(WatchlistSession.open(h.options), code('WATCHLIST_OWNER_EXISTS'));
  h.server.accountId = OTHER; const b = await WatchlistSession.open(h.options);
  a.setAssetIds(['forma']); b.setAssetIds(['grove']);
  assert.notEqual(a.storageKey, b.storageKey); assert.deepEqual(a.getSnapshot().assetIds, ['forma']);
  assert.deepEqual(b.getSnapshot().assetIds, ['grove']); a.close(); b.close();
});

test('close or subject switch during token retrieval never sends the queued credentials', async () => {
  const h = setup(); const token = deferred<string | null>();
  let hold = false;
  const session = await WatchlistSession.open({...h.options, accessToken: () => hold ? token.promise : Promise.resolve('test-token')});
  hold = true;
  const syncing = session.synchronize(); const rejected = assert.rejects(syncing, code('WATCHLIST_CLOSED'));
  session.close(); token.resolve('test-token'); await rejected;
  assert.equal(h.server.requests.length, 1);
  const second = setup(); const held = deferred<string | null>();
  const opening = WatchlistSession.open({...second.options, accessToken: () => held.promise});
  second.changeSubject('did:privy:B'); held.resolve('test-token');
  await assert.rejects(opening, code('WATCHLIST_SESSION_CHANGED')); assert.equal(second.server.requests.length, 0);
});

test('a late committed response after close cannot clear the persisted pending request', async () => {
  const h = setup(); const held = deferred<Response>(); const session = await WatchlistSession.open(h.options);
  session.setAssetIds(['forma']); h.server.putOverride = () => held.promise;
  const syncing = session.synchronize(); const rejected = assert.rejects(syncing, code('WATCHLIST_CLOSED'));
  await until(() => h.server.requests.some(item => item.method === 'PUT'));
  const pendingRaw = h.store.values.get(session.storageKey);
  session.close(); held.resolve(h.server.commit(JSON.parse(h.server.requests.at(-1)!.body!) as Record<string, unknown>)); await rejected;
  await nextTurn(); assert.equal(h.store.values.get(session.storageKey), pendingRaw);
  assert.throws(() => session.setAssetIds([]), code('WATCHLIST_CLOSED'));
});

test('request timeout cancels an unbounded body stream and leaves progress protected from malformed replies', async () => {
  const h = setup(); let cancelled = false;
  h.server.postOverride = async () => new Response(new ReadableStream<Uint8Array>({cancel() {cancelled = true;}}), {headers: {'content-type': 'application/json'}});
  await assert.rejects(WatchlistSession.open({...h.options, timeoutMs: 15}), code('WATCHLIST_TIMEOUT'));
  await until(() => cancelled);
  assert.equal(h.store.writes.length, 0); assert.equal(h.server.requests[0]!.signal!.aborted, true);
});

test('strict URL, redirect, JSON and protocol validation rejects unsafe input without repairing data', async () => {
  for (const url of ['http://api.example', 'https://user:pass@api.example', 'https://api.example/path', 'https://api.example/?token=secret']) {
    const h = setup(); await assert.rejects(WatchlistSession.open({...h.options, apiBaseUrl: url}), code('WATCHLIST_INVALID_CONFIGURATION'));
    assert.equal(h.server.requests.length, 0);
  }
  for (const response of [new Response('', {status: 302}), new Response('<html>oops</html>', {headers: {'content-type': 'text/html'}}),
    json({schemaVersion: 1, userId: `${ACCOUNT}\n`}), json({schemaVersion: 1, userId: ACCOUNT, token: 'extra'}),
    new Response(new Uint8Array([0xc3, 0x28]), {headers: {'content-type': 'application/json'}}),
    new Response('x'.repeat(16_385), {headers: {'content-type': 'application/json'}})]) {
    const h = setup(); h.server.postOverride = async () => response;
    await assert.rejects(WatchlistSession.open(h.options), WatchlistSyncError); assert.equal(h.store.writes.length, 0);
  }
});

test('401 and malformed acknowledgments retain the exact mutation for later authentication or recovery', async () => {
  for (const response of [error('WATCHLIST_UNAUTHENTICATED', 401), json(snap(9, ['forma'])), json(snap(1, ['grove']))]) {
    const h = setup(); const session = await WatchlistSession.open(h.options); session.setAssetIds(['forma']);
    h.server.putOverride = async () => response;
    await assert.rejects(session.synchronize(), WatchlistSyncError);
    const raw = h.store.values.get(session.storageKey)!;
    assert.equal(session.getSnapshot().pending, true); session.close(); h.server.putOverride = undefined;
    const restarted = await WatchlistSession.open(h.options); assert.equal(h.store.values.get(restarted.storageKey), raw);
    await restarted.synchronize(); assert.equal(h.server.snapshot.revision, 1); restarted.close();
  }
});
