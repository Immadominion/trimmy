import assert from 'node:assert/strict';
import test from 'node:test';
import { FollowedStocksStore, isStorableAssetId } from '../src/account/followed-stocks.js';

const SUBJECT = 'did:privy:follower';

function body(revision: number, assetIds: readonly string[]): string {
  return JSON.stringify({
    schemaVersion: 1, revision, assetIds,
    updatedAt: revision === 0 ? null : '2026-09-19T10:00:00.000Z',
  });
}

const json = (text: string, status = 200): Response =>
  new Response(text, {status, headers: {'content-type': 'application/json'}});

function store(handler: (request: Request) => Promise<Response> | Response): FollowedStocksStore {
  return new FollowedStocksStore({
    subject: SUBJECT,
    currentSubject: () => SUBJECT,
    accessToken: async () => 'header.payload.signature',
    apiBaseUrl: 'https://api.example',
    fetch: (async (input: RequestInfo | URL, init?: RequestInit) =>
      handler(new Request(input as never, init))) as typeof fetch,
  });
}

test('nothing is read until something asks', async () => {
  let calls = 0;
  const followed = store(() => { calls += 1; return json(body(0, [])); });
  assert.equal(calls, 0);
  assert.deepEqual(followed.getSnapshot().assetIds, []);
  assert.equal(followed.getSnapshot().status, 'idle');
  await followed.refresh();
  assert.equal(calls, 1);
  assert.equal(followed.getSnapshot().status, 'ready');
  followed.close();
});

test('keeping an asset writes the whole list at the revision it saw', async () => {
  const seen: Array<{method: string; body?: unknown}> = [];
  let revision = 1;
  let stored: string[] = ['apple'];
  const followed = store(async request => {
    if (request.method === 'GET') {
      seen.push({method: 'GET'});
      return json(body(revision, stored));
    }
    const sent = await request.json() as Record<string, unknown>;
    seen.push({method: 'PUT', body: sent});
    assert.equal(sent['baseRevision'], revision);
    stored = sent['assetIds'] as string[];
    revision += 1;
    return json(body(revision, stored));
  });
  await followed.refresh();
  await followed.follow('tesla');
  assert.deepEqual(followed.getSnapshot().assetIds, ['apple', 'tesla']);
  assert.equal(followed.getSnapshot().errorCode, null);
  assert.deepEqual(seen.map(entry => entry.method), ['GET', 'PUT']);
  followed.close();
});

test('keeping something already kept writes nothing', async () => {
  let writes = 0;
  const followed = store(request => {
    if (request.method !== 'GET') writes += 1;
    return json(body(2, ['apple']));
  });
  await followed.refresh();
  await followed.follow('apple');
  assert.equal(writes, 0);
  assert.equal(followed.isFollowing('apple'), true);
  followed.close();
});

test('a concurrent change is reloaded and this tap is not lost', async () => {
  let serverRevision = 1;
  let stored: string[] = ['apple'];
  let refusals = 0;
  const followed = store(async request => {
    if (request.method === 'GET') return json(body(serverRevision, stored));
    const sent = await request.json() as Record<string, unknown>;
    if (sent['baseRevision'] !== serverRevision) {
      refusals += 1;
      return json(JSON.stringify({
        error: {code: 'WATCHLIST_REVISION_CONFLICT', message: 'x', requestId: 'r'},
        currentSnapshot: JSON.parse(body(serverRevision, stored)),
      }), 409);
    }
    stored = sent['assetIds'] as string[];
    serverRevision += 1;
    return json(body(serverRevision, stored));
  });
  await followed.refresh();
  // Another client adds one and moves the revision on.
  serverRevision = 6;
  stored = ['apple', 'nvidia'];
  await followed.follow('tesla');
  assert.equal(refusals, 1, 'the stale write must be refused once');
  assert.equal(followed.getSnapshot().errorCode, null, 'the retry succeeded');
  assert.deepEqual(followed.getSnapshot().assetIds, ['apple', 'nvidia', 'tesla'],
    'the other change survives and this one is applied on top');
  followed.close();
});

test('a full list is reported rather than silently dropping the tap', async () => {
  const full = Array.from({length: 50}, (_, index) => `asset-${index}`);
  const followed = store(request => {
    assert.equal(request.method, 'GET', 'a full list never writes');
    return json(body(3, full));
  });
  await followed.refresh();
  assert.equal(followed.getSnapshot().full, true);
  await followed.follow('tesla');
  assert.equal(followed.getSnapshot().errorCode, 'FOLLOWING_LIST_FULL');
  followed.close();
});

test('unkeeping removes exactly one asset', async () => {
  let stored: string[] = ['apple', 'tesla'];
  const followed = store(async request => {
    if (request.method === 'GET') return json(body(4, stored));
    stored = (await request.json() as Record<string, unknown>)['assetIds'] as string[];
    return json(body(5, stored));
  });
  await followed.refresh();
  await followed.unfollow('apple');
  assert.deepEqual(followed.getSnapshot().assetIds, ['tesla']);
  followed.close();
});

test('identifiers the server would refuse never reach the network', async () => {
  let calls = 0;
  const followed = store(() => { calls += 1; return json(body(0, [])); });
  for (const bad of ['Apple', 'apple ', '-apple', 'apple--x', 'a'.repeat(101), '']) {
    await followed.follow(bad);
    assert.equal(followed.getSnapshot().errorCode, 'FOLLOWING_INVALID_INPUT', bad);
  }
  assert.equal(calls, 0);
  assert.equal(isStorableAssetId('3m-company'), true);
  assert.equal(isStorableAssetId('Apple'), false);
  followed.close();
});

test('a malformed stored list is refused rather than shown', async () => {
  const followed = store(() => json(JSON.stringify({
    schemaVersion: 1, revision: 1, assetIds: ['Apple'], updatedAt: '2026-09-19T10:00:00.000Z',
  })));
  await followed.refresh();
  assert.equal(followed.getSnapshot().status, 'error');
  assert.deepEqual(followed.getSnapshot().assetIds, []);
  followed.close();
});
