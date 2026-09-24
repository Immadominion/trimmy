import assert from 'node:assert/strict';
import {test} from 'node:test';
import {webcrypto} from 'node:crypto';
import {
  PracticeClient, PracticeError, PORTFOLIO_MEDIA_TYPE, PROFILE_MEDIA_TYPE, parsePaperPortfolio,
} from '../src/product/practice-client.js';
import type {GuestCredential, PaperOrderIntent, PaperPreview, ProductProfile} from '../src/product/practice-client.js';
import {PracticeSession, practiceStorageKey} from '../src/product/practice-session.js';
import type {PracticeCrypto, PracticeStorage} from '../src/product/practice-session.js';

const UUID = '11111111-1111-4111-8111-111111111111';
const PREVIEW_ID = '22222222-2222-4222-8222-222222222222';
const ORDER_ID = '33333333-3333-4333-8333-333333333333';
const NOW = Date.parse('2026-09-24T12:00:00.000Z');
const AT = new Date(NOW).toISOString();
const MINT = '11111111111111111111111111111111';
const guest: GuestCredential = {guestId: UUID, token: `tg1_${'A'.repeat(43)}`,
  expiresAt: '2026-10-01T12:00:00.000Z', hardExpiresAt: '2026-11-01T12:00:00.000Z'};
const intent: PaperOrderIntent = {action: 'buy', assetId: 'apple', variantMint: MINT,
  amount: {kind: 'paper_amount', paperMicros: '100000000'}};
const profile: ProductProfile = {revision: 1, onboarding: {goal: null, knowledge: null, persona: null, dailyGoal: null, handle: null},
  launchCheckpoint: 'first-trade', hasConfirmedPaperTrade: false, createdAt: AT, updatedAt: AT};
function preview(requestId = UUID): PaperPreview {
  return {id: PREVIEW_ID, requestId, state: 'open', accountRevision: 0, ...intent, symbol: 'AAPL',
    pricePaperMicros: '50000000', quantityMicros: '2000000', cashDebitPaperMicros: '100000000', cashCreditPaperMicros: '0',
    cashAfterPaperMicros: '9900000000', positionQuantityAfterMicros: '2000000', positionCostBasisAfterPaperMicros: '100000000',
    realizedGainDeltaPaperMicros: '0', lockedGainDeltaPaperMicros: '0', source: {provider: 'tokens-xyz-v1',
      providerReference: '/v1/assets/apple', marketSource: null, metricsSource: null, observedAt: AT, acceptedAt: AT,
      providerTimestamps: {asOf: null, lastFetchedAt: null, lastTradeAt: null, unit: 'not_declared'}},
    expiresAt: new Date(NOW + 30_000).toISOString(), committedAt: null};
}
function receipt(p = preview()) {
  const {requestId: _request, state: _state, amount: _amount, expiresAt: _expires, ...rest} = p;
  return {...rest, id: ORDER_ID, previewId: p.id, accountRevision: p.accountRevision + 1, committedAt: AT};
}
function envelope(kind: 'preview' | 'order', value: unknown) {
  return {schemaVersion: 1, mode: 'paper', unit: {kind: 'paper', scaleDigits: 6}, [kind]: value,
    fees: {paperMicros: '0'}, reward: {trimsAwarded: 0, reason: 'Trade completion alone does not award Trims.'},
    execution: {walletUsed: false, transactionBuilt: false, transactionSigned: false, transactionBroadcast: false}};
}
function json(value: unknown, status = 200, media = 'application/json'): Response {
  return new Response(JSON.stringify(value), {status, headers: {'content-type': media}});
}
function problem(code: string, status = 409): Response {return json({error: {code, message: 'Not completed.', requestId: UUID}}, status);}
class MemoryStorage implements PracticeStorage {
  values = new Map<string, string>(); failRead = false; failWrite = false; discardWrite = false;
  getItem(key: string): string | null {if (this.failRead) throw new Error('Storage blocked'); return this.values.get(key) ?? null;}
  setItem(key: string, value: string): void {if (this.failWrite) throw new Error('Quota'); if (!this.discardWrite) this.values.set(key, value);}
}
interface Call {url: string; method: string; body: Record<string, unknown> | null; headers: Headers; init: RequestInit}
type Reply = (call: Call) => Response | Promise<Response>;
function harness(reply: Reply, storage = new MemoryStorage(), timeoutMs = 1_000) {
  const calls: Call[] = [];
  const fetcher: typeof fetch = async (input, init = {}) => {
    const call = {url: String(input), method: init.method ?? 'GET', body: init.body ? JSON.parse(String(init.body)) as Record<string, unknown> : null,
      headers: new Headers(init.headers), init}; calls.push(call); return reply(call);
  };
  const client = new PracticeClient({baseUrl: '/api', fetch: fetcher, timeoutMs});
  const make = () => new PracticeSession({client, storage, crypto: webcrypto as unknown as PracticeCrypto, now: () => NOW});
  return {client, storage, calls, make, session: make()};
}
function createReply(call: Call): Response {
  return json({schemaVersion: 1, requestId: call.body?.['requestId'], ...guest}, 201);
}
async function code(promise: Promise<unknown>, expected: string): Promise<void> {
  await assert.rejects(promise, (error: unknown) => error instanceof PracticeError && error.code === expected);
}
function emptyPortfolio() {
  return {schemaVersion: 2, mode: 'paper', unit: {kind: 'paper', scaleDigits: 6}, revision: 0,
    startingCashPaperMicros: '10000000000', cashPaperMicros: '10000000000', openedAt: null, updatedAt: null,
    positions: [] as Record<string, unknown>[], recentOrders: [], valuation: {status: 'complete', portfolioRevision: 0,
      openPositionCount: 0, pricedPositionCount: 0, cashPaperMicros: '10000000000', knownValuePaperMicros: '10000000000',
      totalPaperMicros: '10000000000', positions: [] as Record<string, unknown>[]}};
}

test('construction and read-only exploration never create a guest', async () => {
  const h = harness(createReply);
  assert.equal(h.session.hasSavedGuest, false); assert.equal(h.session.guest, null);
  await code(h.session.readPortfolio(), 'PRACTICE_GUEST_REQUIRED');
  await code(h.session.readProfile(), 'PRACTICE_GUEST_REQUIRED');
  assert.equal(h.calls.length, 0); assert.equal(h.storage.values.size, 0);
});

test('guest issuance proof is saved before network and replayed exactly after response loss and reload', async () => {
  let savedBeforeRequest: unknown;
  const storage = new MemoryStorage(); let attempts = 0;
  const h = harness(call => {
    savedBeforeRequest = JSON.parse(storage.getItem(practiceStorageKey('/api'))!);
    if (++attempts === 1) throw new TypeError('Connection lost');
    return createReply(call);
  }, storage);
  await code(h.session.ensureGuest(), 'PRACTICE_NETWORK_ERROR');
  assert.equal(h.session.hasSavedGuest, true); assert.equal(h.session.guest, null);
  const pending = (savedBeforeRequest as {issuance: unknown}).issuance;
  assert.deepEqual(pending, h.calls[0]?.body);
  const restored = h.make(); const result = await restored.ensureGuest();
  assert.deepEqual(h.calls[0]?.body, h.calls[1]?.body);
  assert.equal(result.guestId, UUID); assert.equal(restored.guest?.token, guest.token);
  const saved = JSON.parse(storage.getItem(restored.storageKey)!) as {issuance: unknown; guest: unknown};
  assert.equal(saved.issuance, null); assert.deepEqual(saved.guest, guest);
});

test('blocked or silently discarded storage prevents a guest HTTP request', async () => {
  for (const failure of ['failWrite', 'discardWrite'] as const) {
    const storage = new MemoryStorage(); storage[failure] = true;
    const h = harness(createReply, storage); await code(h.session.ensureGuest(), 'PRACTICE_STORAGE_UNAVAILABLE');
    assert.equal(h.calls.length, 0);
  }
  const storage = new MemoryStorage(); storage.failRead = true;
  assert.throws(() => harness(createReply, storage), {code: 'PRACTICE_STORAGE_UNAVAILABLE'});
});

test('corrupt, mismatched API, and foreign pending-order storage fail closed without replacement', () => {
  const key = practiceStorageKey('/api');
  for (const raw of ['not json', JSON.stringify({version: 1, apiBase: 'https://other.example'})]) {
    const storage = new MemoryStorage(); storage.setItem(key, raw);
    assert.throws(() => harness(createReply, storage), {code: 'PRACTICE_STORAGE_INVALID'});
    assert.equal(storage.getItem(key), raw);
  }
  assert.notEqual(key, practiceStorageKey('https://api.example'));
});

test('expired guest remains saved and never falls back to guest creation', async () => {
  const h = harness(call => json({schemaVersion: 1, requestId: call.body?.['requestId'], ...guest,
    expiresAt: '2026-09-23T12:00:00.000Z'}, 201));
  await h.session.ensureGuest();
  const restored = h.make(); await code(restored.ensureGuest(), 'GUEST_SESSION_EXPIRED');
  assert.equal(restored.guest?.guestId, UUID); assert.equal(h.calls.length, 1);
});

test('revocation is retained across reload and refresh cannot manufacture a new desk', async () => {
  const h = harness(call => call.url.endsWith('/refresh') ? problem('GUEST_SESSION_REVOKED', 401) : createReply(call));
  await h.session.ensureGuest(); await code(h.session.ensureGuest(), 'GUEST_SESSION_REVOKED');
  const restored = h.make(); await code(restored.ensureGuest(), 'GUEST_SESSION_REVOKED');
  assert.equal(h.calls.length, 2); assert.equal(restored.guest?.guestId, UUID);
});

test('reopening a guest outside the seven-day refresh window reuses its credential without requests or writes', async () => {
  const freshGuest = {...guest, expiresAt: new Date(NOW + 7 * 86400000 + 1).toISOString()};
  const h = harness(call => json({schemaVersion: 1, requestId: call.body?.['requestId'], ...freshGuest}, 201));
  await h.session.ensureGuest(); const saved = h.storage.getItem(h.session.storageKey);
  h.storage.failWrite = true;
  for (let reopen = 0; reopen < 12; reopen++) {
    const restored = h.make(); assert.deepEqual(await restored.ensureGuest(), freshGuest);
    assert.equal(restored.guest?.guestId, UUID);
  }
  assert.equal(h.calls.length, 1); assert.equal(h.storage.getItem(h.session.storageKey), saved);
  h.storage.values.set(h.session.storageKey, `${saved} `);
  await code(h.session.ensureGuest(), 'PRACTICE_SESSION_CHANGED');
  assert.equal(h.calls.length, 1);
});

test('at or inside the seven-day boundary refresh extends the same guest and later reopen stays local', async () => {
  for (const remaining of [7 * 86400000, 7 * 86400000 - 1]) {
    const dueGuest = {...guest, expiresAt: new Date(NOW + remaining).toISOString()};
    const renewed = {...guest, expiresAt: new Date(NOW + 14 * 86400000).toISOString()};
    const h = harness(call => call.url.endsWith('/refresh') ? json({schemaVersion: 1, guestId: UUID,
      expiresAt: renewed.expiresAt, hardExpiresAt: renewed.hardExpiresAt})
      : json({schemaVersion: 1, requestId: call.body?.['requestId'], ...dueGuest}, 201));
    await h.session.ensureGuest();
    assert.deepEqual(await h.make().ensureGuest(), renewed);
    assert.deepEqual(await h.make().ensureGuest(), renewed);
    assert.equal(h.calls.length, 2);
    assert.equal(h.calls[1]?.url, '/api/v1/guest/session/refresh');
    assert.equal(h.calls[1]?.headers.get('authorization'), `Guest ${guest.token}`);
    assert.deepEqual(h.calls[1]?.body, {schemaVersion: 1});
  }
});

test('a due refresh rate limit preserves the active credential and paper reads still work', async () => {
  const h = harness(call => call.url.endsWith('/refresh') ? problem('GUEST_SESSION_RATE_LIMITED', 429)
    : call.url.endsWith('/portfolio') ? json(emptyPortfolio(), 200, PORTFOLIO_MEDIA_TYPE) : createReply(call));
  await h.session.ensureGuest(); const saved = h.storage.getItem(h.session.storageKey);
  await code(h.make().ensureGuest(), 'GUEST_SESSION_RATE_LIMITED');
  assert.equal(h.storage.getItem(h.session.storageKey), saved);
  const restored = h.make(); assert.deepEqual(restored.guest, guest);
  assert.equal((await restored.readPortfolio()).cashPaperMicros, '10000000000');
  assert.equal(h.calls.filter(call => call.url === '/api/v1/guest/session').length, 1);
  assert.equal(h.calls.length, 3);
});

test('nullable profile initialization uses schema 2 and persists exact write across unknown outcome', async () => {
  let writes = 0;
  const h = harness(call => {
    if (call.url.endsWith('/guest/session')) return createReply(call);
    if (call.method === 'GET') return json({schemaVersion: 2, profile: null}, 200, PROFILE_MEDIA_TYPE);
    if (++writes === 1) throw new TypeError('Lost acknowledgement');
    return json({schemaVersion: 2, profile}, 200, PROFILE_MEDIA_TYPE);
  });
  await h.session.ensureGuest(); await code(h.session.ensureProfile(), 'PRACTICE_NETWORK_ERROR');
  const result = await h.make().ensureProfile(); assert.deepEqual(result, profile);
  const puts = h.calls.filter(c => c.method === 'PUT'); assert.equal(puts.length, 2); assert.deepEqual(puts[0]?.body, puts[1]?.body);
  assert.deepEqual(puts[0]?.body?.['onboarding'], profile.onboarding);
  assert.equal(puts[0]?.body?.['schemaVersion'], 2); assert.equal(puts[0]?.body?.['baseRevision'], 0);
  assert.equal(puts[0]?.body?.['launchCheckpoint'], 'first-trade');
  assert.equal(puts[0]?.headers.get('accept'), PROFILE_MEDIA_TYPE);
});

test('launch actions require a real profile revision and do not change it locally', async () => {
  const h = harness(call => {
    if (call.url.endsWith('/guest/session')) return createReply(call);
    if (call.method === 'GET') return json({schemaVersion: 2, profile}, 200, PROFILE_MEDIA_TYPE);
    return problem('PRODUCT_PROFILE_PAPER_TRADE_REQUIRED');
  });
  await h.session.ensureGuest(); await code(h.session.advanceLaunch('introduction-completed'), 'PRODUCT_PROFILE_PAPER_TRADE_REQUIRED');
  const write = h.calls.at(-1)!;
  assert.equal(write.url, '/api/v1/product/launch'); assert.equal(write.body?.['baseRevision'], 1);
  assert.equal(write.body?.['schemaVersion'], 2); assert.equal(write.body?.['action'], 'introduction-completed');
  assert.equal(h.session.lastReceipt, null);
});

test('an ambiguous commit survives reload; exact retry is the only allowed order operation', async () => {
  let current = preview(); let commitAttempts = 0; let savedAtCommit: unknown;
  const storage = new MemoryStorage();
  const h = harness(call => {
    if (call.url.endsWith('/guest/session')) return createReply(call);
    if (call.url.endsWith('/preview')) {current = preview(String(call.body?.['requestId'])); return json(envelope('preview', current));}
    savedAtCommit = JSON.parse(storage.getItem(practiceStorageKey('/api'))!);
    if (++commitAttempts === 1) throw new TypeError('Response lost after server commit');
    return json(envelope('order', receipt(current)));
  }, storage);
  await h.session.ensureGuest(); const quote = await h.session.previewOrder(intent);
  await code(h.session.commitOrder(quote), 'PRACTICE_NETWORK_ERROR');
  const pending = h.session.pendingCommit!; assert.deepEqual((savedAtCommit as {pendingCommit: unknown}).pendingCommit, pending);
  const restored = h.make(); assert.deepEqual(restored.pendingCommit, pending);
  await code(restored.previewOrder({...intent, assetId: 'tesla'}), 'PRACTICE_COMMIT_PENDING');
  await code(restored.commitOrder(quote), 'PRACTICE_COMMIT_PENDING');
  assert.equal(h.calls.length, 3);
  const result = await restored.retryPendingCommit();
  assert.equal(result.id, ORDER_ID); assert.equal(restored.pendingCommit, null);
  assert.deepEqual(h.calls[2]?.body, h.calls[3]?.body);
  assert.deepEqual(h.make().lastReceipt, result);
  assert.equal(h.calls[3]?.headers.get('authorization'), `Guest ${guest.token}`);
  assert.equal(h.calls[3]?.init.credentials, 'omit'); assert.equal(h.calls[3]?.init.redirect, 'error');
});

test('storage failure before commit means no order is sent', async () => {
  const h = harness(call => call.url.endsWith('/preview') ? json(envelope('preview', preview(String(call.body?.['requestId'])))) : createReply(call));
  await h.session.ensureGuest(); const quote = await h.session.previewOrder(intent); h.storage.failWrite = true;
  await code(h.session.commitOrder(quote), 'PRACTICE_STORAGE_UNAVAILABLE');
  assert.equal(h.calls.length, 2);
});

test('a received receipt is not reported successful if it cannot be retained; retry recovers it', async () => {
  let current = preview(); let commits = 0;
  const h = harness(call => {
    if (call.url.endsWith('/guest/session')) return createReply(call);
    if (call.url.endsWith('/preview')) {current = preview(String(call.body?.['requestId'])); return json(envelope('preview', current));}
    if (++commits === 1) h.storage.failWrite = true;
    return json(envelope('order', receipt(current)));
  });
  await h.session.ensureGuest(); const quote = await h.session.previewOrder(intent);
  await code(h.session.commitOrder(quote), 'PRACTICE_STORAGE_UNAVAILABLE');
  assert.ok(h.session.pendingCommit); assert.equal(h.session.lastReceipt, null);
  h.storage.failWrite = false; assert.equal((await h.make().retryPendingCommit()).id, ORDER_ID);
  assert.deepEqual(h.calls[2]?.body, h.calls[3]?.body);
});

test('definitive expired-quote rejection clears pending but never shows a receipt', async () => {
  const h = harness(call => call.url.endsWith('/guest/session') ? createReply(call) : call.url.endsWith('/preview')
    ? json(envelope('preview', preview(String(call.body?.['requestId'])))) : problem('PAPER_PREVIEW_EXPIRED'));
  await h.session.ensureGuest(); const quote = await h.session.previewOrder(intent);
  await code(h.session.commitOrder(quote), 'PAPER_PREVIEW_EXPIRED');
  assert.equal(h.session.pendingCommit, null); assert.equal(h.session.lastReceipt, null);
  await h.session.previewOrder(intent); assert.equal(h.calls.length, 4);
});

test('a foreign or altered receipt is not success and preserves exact pending order', async () => {
  const h = harness(call => call.url.endsWith('/guest/session') ? createReply(call) : call.url.endsWith('/preview')
    ? json(envelope('preview', preview(String(call.body?.['requestId'])))) : json(envelope('order', {...receipt(), assetId: 'tesla'})));
  await h.session.ensureGuest(); const quote = await h.session.previewOrder(intent);
  await code(h.session.commitOrder(quote), 'PRACTICE_RESPONSE_INVALID');
  assert.ok(h.session.pendingCommit); assert.equal(h.session.lastReceipt, null);
});

test('pending commit storage rejects a different guest binding', async () => {
  const h = harness(call => call.url.endsWith('/guest/session') ? createReply(call) : call.url.endsWith('/preview')
    ? json(envelope('preview', preview(String(call.body?.['requestId'])))) : problem('PAPER_TRADING_UNAVAILABLE', 503));
  await h.session.ensureGuest(); await code(h.session.commitOrder(await h.session.previewOrder(intent)), 'PAPER_TRADING_UNAVAILABLE');
  const saved = JSON.parse(h.storage.getItem(h.session.storageKey)!) as {pendingCommit: {guestId: string}};
  saved.pendingCommit.guestId = ORDER_ID; h.storage.setItem(h.session.storageKey, JSON.stringify(saved));
  assert.throws(() => h.make(), {code: 'PRACTICE_STORAGE_INVALID'});
});

test('storage identity change during await rejects the response without overwriting another tab', async () => {
  let release!: (response: Response) => void;
  const h = harness(() => new Promise<Response>(resolve => {release = resolve;}));
  const creating = h.session.ensureGuest();
  const replacement = 'other-tab-state'; h.storage.setItem(h.session.storageKey, replacement);
  release(createReply(h.calls[0]!)); await code(creating, 'PRACTICE_SESSION_CHANGED');
  assert.equal(h.storage.getItem(h.session.storageKey), replacement); assert.equal(h.session.guest, null);
});

test('concurrent confirmation and stale copied previews cannot create another commit', async () => {
  let release!: (response: Response) => void; let current = preview();
  const h = harness(call => {
    if (call.url.endsWith('/guest/session')) return createReply(call);
    if (call.url.endsWith('/preview')) {current = preview(String(call.body?.['requestId'])); return json(envelope('preview', current));}
    return new Promise<Response>(resolve => {release = resolve;});
  });
  await h.session.ensureGuest(); const quote = await h.session.previewOrder(intent);
  await code(h.session.commitOrder({...quote}), 'PRACTICE_PREVIEW_CHANGED');
  const first = h.session.commitOrder(quote);
  await code(h.session.commitOrder(quote), 'PRACTICE_BUSY');
  release(json(envelope('order', receipt(current)))); await first;
  await code(h.session.commitOrder(quote), 'PRACTICE_PREVIEW_CHANGED'); assert.equal(h.calls.length, 3);
});

test('timeout and AbortSignal bound even an uncooperative fetch implementation', async () => {
  let requests = 0; let started!: () => void;
  const secondStarted = new Promise<void>(resolve => {started = resolve;});
  const h = harness(() => {if (++requests === 2) started(); return new Promise<Response>(() => undefined);}, new MemoryStorage(), 15);
  await code(h.session.ensureGuest(), 'PRACTICE_TIMEOUT'); assert.equal(h.session.hasSavedGuest, true);
  const controller = new AbortController(); const pending = h.session.ensureGuest(controller.signal); await secondStarted; controller.abort();
  await code(pending, 'PRACTICE_ABORTED'); assert.equal(h.calls.length, 2);
  assert.deepEqual(h.calls[0]?.body, h.calls[1]?.body);
});

test('quote rejects widened execution/reward and noncanonical monetary values', async () => {
  for (const mutate of [
    (v: ReturnType<typeof envelope>) => {v.execution.transactionSigned = true;},
    (v: ReturnType<typeof envelope>) => {v.reward.trimsAwarded = 20;},
    (v: ReturnType<typeof envelope>) => {(v['preview'] as Record<string, unknown>)['quantityMicros'] = 2_000_000;},
    (v: ReturnType<typeof envelope>) => {(v['preview'] as Record<string, unknown>)['cashAfterPaperMicros'] = '09900000000';},
    (v: ReturnType<typeof envelope>) => {(v['preview'] as Record<string, unknown>)['cashDebitPaperMicros'] = '100000001';},
  ]) {
    const h = harness(call => {const value = envelope('preview', preview(String(call.body?.['requestId']))); mutate(value); return json(value);});
    await code(h.client.previewOrder(guest, {schemaVersion: 1, requestId: UUID, ...intent}), 'PRACTICE_RESPONSE_INVALID');
  }
});

test('portfolio is server-owned exact money; zero positions and closed history have valid coverage', () => {
  const empty = parsePaperPortfolio(emptyPortfolio()); assert.equal(empty.valuation.totalPaperMicros, '10000000000');
  const closed = emptyPortfolio(); closed.positions.push({assetId: 'apple', variantMint: MINT, symbol: 'AAPL',
    quantityMicros: '0', costBasisPaperMicros: '0', averageCostPricePaperMicros: '0', realizedGainPaperMicros: '-1000', lockedGainPaperMicros: '0', updatedAt: AT});
  assert.equal(parsePaperPortfolio(closed).positions.length, 1);
  assert.equal(parsePaperPortfolio(closed).valuation.openPositionCount, 0);
  assert.throws(() => parsePaperPortfolio({...closed, cashPaperMicros: 10000000000}), {code: 'PRACTICE_RESPONSE_INVALID'});
});

test('portfolio rejects fabricated complete value and incorrect position valuation arithmetic', () => {
  const v = emptyPortfolio();
  v.positions.push({assetId: 'apple', variantMint: MINT, symbol: 'AAPL', quantityMicros: '2000000', costBasisPaperMicros: '100000000',
    averageCostPricePaperMicros: '50000000', realizedGainPaperMicros: '0', lockedGainPaperMicros: '0', updatedAt: AT});
  v.valuation.openPositionCount = 1; v.valuation.pricedPositionCount = 1;
  v.valuation.positions.push({assetId: 'apple', variantMint: MINT, status: 'priced', pricePaperMicros: '60000000',
    marketValuePaperMicros: '120000000', unrealizedGainPaperMicros: '20000000', observedAt: AT, acceptedAt: AT, expiresAt: preview().expiresAt});
  v.valuation.knownValuePaperMicros = '10120000000'; v.valuation.totalPaperMicros = '10120000000';
  assert.equal(parsePaperPortfolio(v).valuation.totalPaperMicros, '10120000000');
  v.valuation.positions[0]!['marketValuePaperMicros'] = '120000001';
  assert.throws(() => parsePaperPortfolio(v), {code: 'PRACTICE_RESPONSE_INVALID'});
});

test('profile and portfolio require negotiated v2 media and schema', async () => {
  const h = harness(() => json(emptyPortfolio()));
  await code(h.client.readPortfolio(guest), 'PRACTICE_RESPONSE_INVALID');
  assert.equal(h.calls[0]?.headers.get('accept'), PORTFOLIO_MEDIA_TYPE);
  const p = harness(() => json({schemaVersion: 1, profile}, 200, PROFILE_MEDIA_TYPE));
  await code(p.client.readProfile(guest), 'PRACTICE_RESPONSE_INVALID');
});

test('API configuration prohibits insecure origins, URL credentials and arbitrary relative routes', () => {
  for (const baseUrl of ['http://api.example', 'https://user:pass@api.example', '/other', '//evil.example', 'https://api.example?token=secret']) {
    assert.throws(() => new PracticeClient({baseUrl}), {code: 'PRACTICE_CONFIG_INVALID'});
  }
  assert.equal(new PracticeClient({baseUrl: 'https://API.example/'}).apiBase, 'https://api.example');
});

test('rate-limit metadata remains available without treating it as a lost guest', async () => {
  const h = harness(() => new Response(JSON.stringify({error: {code: 'GUEST_SESSION_RATE_LIMITED'}}),
    {status: 429, headers: {'content-type': 'application/json', 'retry-after': '60'}}));
  await assert.rejects(h.session.ensureGuest(), (error: unknown) => error instanceof PracticeError &&
    error.code === 'GUEST_SESSION_RATE_LIMITED' && error.retryAfterSeconds === 60 && !error.terminalGuest);
  assert.equal(h.session.hasSavedGuest, true);
});

test('career summary and missions use the guest identity and preserve actual reward/status fields', async () => {
  const summary = {schemaVersion: 1, career: {revision: 0, trims: {total: 0, today: 0, thisWeek: 0},
    rank: {id: 'rookie', label: 'Rookie', paperLimit: '10000', threshold: 0},
    nextRank: {id: 'analyst', label: 'Analyst', threshold: 300, trimsRemaining: 300, promotionRequired: true},
    streak: {days: 0, status: 'not-started', lastActiveDate: null}, careerStarted: false, firstConfirmedBuy: null,
    serverDate: '2026-09-24', updatedAt: null}};
  const board = {schemaVersion: 1, career: {revision: 0, currentRank: 'rookie'}, missions: [{id: 'first-paper-buy', chapterRank: 'rookie',
    order: 1, kind: 'action', title: 'Buy your first stock', instruction: 'Complete one paper buy.', trimsReward: 20,
    promotesToRank: null, status: 'ready', completedAt: null}]};
  const h = harness(call => call.url.endsWith('/guest/session') ? createReply(call) : json(call.url.endsWith('/summary') ? summary : board));
  await h.session.ensureGuest();
  const [career, missions] = await Promise.all([h.session.readCareerSummary(), h.session.readMissions()]);
  assert.equal(career.trims.total, 0); assert.equal(career.careerStarted, false);
  assert.equal(missions.missions[0]?.trimsReward, 20); assert.equal(missions.missions[0]?.status, 'ready');
  for (const call of h.calls.slice(1)) {assert.equal(call.method, 'GET'); assert.equal(call.headers.get('authorization'), `Guest ${guest.token}`);}
  assert.ok(Object.isFrozen(career.trims)); assert.ok(Object.isFrozen(missions.missions));
});

test('guest refresh preserves identity and refuses a substituted credential owner', async () => {
  const h = harness(() => json({schemaVersion: 1, guestId: ORDER_ID, expiresAt: guest.expiresAt, hardExpiresAt: guest.hardExpiresAt}));
  await code(h.client.refreshGuest(guest), 'PRACTICE_RESPONSE_INVALID');
  assert.deepEqual(h.calls[0]?.body, {schemaVersion: 1});
  assert.equal(h.calls[0]?.headers.get('authorization'), `Guest ${guest.token}`);
});

test('response body size and read duration are bounded', async () => {
  const large = harness(() => new Response(' '.repeat(262_145), {headers: {'content-type': 'application/json'}}));
  await code(large.session.ensureGuest(), 'PRACTICE_RESPONSE_INVALID');
  const neverEnding = harness(() => new Response(new ReadableStream<Uint8Array>({start(controller) {
    controller.enqueue(new TextEncoder().encode('{'));
  }}), {headers: {'content-type': 'application/json'}}), new MemoryStorage(), 10);
  await code(neverEnding.session.ensureGuest(), 'PRACTICE_TIMEOUT');
  assert.equal(neverEnding.session.hasSavedGuest, true);
});

test('a browser without cross-tab locks refuses a mutation before persistence or HTTP', async () => {
  const oldWindow = Object.getOwnPropertyDescriptor(globalThis, 'window');
  const oldNavigator = Object.getOwnPropertyDescriptor(globalThis, 'navigator');
  try {
    Object.defineProperty(globalThis, 'window', {value: {}, configurable: true});
    Object.defineProperty(globalThis, 'navigator', {value: {}, configurable: true});
    const h = harness(createReply); await code(h.session.ensureGuest(), 'PRACTICE_COORDINATION_UNAVAILABLE');
    assert.equal(h.calls.length, 0); assert.equal(h.storage.values.size, 0);
  } finally {
    if (oldWindow) Object.defineProperty(globalThis, 'window', oldWindow); else Reflect.deleteProperty(globalThis, 'window');
    if (oldNavigator) Object.defineProperty(globalThis, 'navigator', oldNavigator); else Reflect.deleteProperty(globalThis, 'navigator');
  }
});
