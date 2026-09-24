import assert from 'node:assert/strict';
import {test} from 'node:test';
import {webcrypto} from 'node:crypto';
import {PracticeClient, PracticeError, PROFILE_MEDIA_TYPE} from '../src/product/practice-client.js';
import type {PracticeAccountAccess, PracticeAccountProof, GuestCredential, PaperPreview} from '../src/product/practice-client.js';
import {PracticeSession, practiceAccountStorageKey, practiceStorageKey} from '../src/product/practice-session.js';
import type {PracticeCrypto, PracticeStorage} from '../src/product/practice-session.js';
import {createProductAccountConnector} from '../src/product/product-account.js';

const GUEST = '11111111-1111-4111-8111-111111111111', ACCOUNT = '22222222-2222-4222-8222-222222222222';
const PREVIEW = '33333333-3333-4333-8333-333333333333', ORDER = '44444444-4444-4444-8444-444444444444';
const SUBJECT = 'did:privy:accountA', NOW = Date.parse('2026-09-24T12:00:00.000Z'), AT = new Date(NOW).toISOString();
const guest: GuestCredential = {guestId: GUEST, token: `tg1_${'A'.repeat(43)}`,
  expiresAt: '2026-10-24T12:00:00.000Z', hardExpiresAt: '2026-11-24T12:00:00.000Z'};
const intent = {action: 'buy' as const, assetId: 'apple', variantMint: '11111111111111111111111111111111',
  amount: {kind: 'paper_amount' as const, paperMicros: '100000000'}};
function preview(requestId: string): PaperPreview {return {id: PREVIEW, requestId, state: 'open', accountRevision: 0,
  ...intent, symbol: 'AAPL', pricePaperMicros: '50000000', quantityMicros: '2000000', cashDebitPaperMicros: '100000000',
  cashCreditPaperMicros: '0', cashAfterPaperMicros: '9900000000', positionQuantityAfterMicros: '2000000',
  positionCostBasisAfterPaperMicros: '100000000', realizedGainDeltaPaperMicros: '0', lockedGainDeltaPaperMicros: '0',
  source: {provider: 'tokens-xyz-v1', providerReference: '/v1/assets/apple', marketSource: null, metricsSource: null,
    observedAt: AT, acceptedAt: AT, providerTimestamps: {asOf: null, lastFetchedAt: null, lastTradeAt: null, unit: 'not_declared'}},
  expiresAt: new Date(NOW + 30000).toISOString(), committedAt: null};}
function receipt(p: PaperPreview) {const {requestId: _requestId, state: _state, amount: _amount, expiresAt: _expires, ...rest} = p;
  return {...rest, id: ORDER, previewId: PREVIEW, accountRevision: 1, committedAt: AT};}
function envelope(kind: string, value: unknown) {return {schemaVersion: 1, mode: 'paper', unit: {kind: 'paper', scaleDigits: 6},
  [kind]: value, fees: {paperMicros: '0'}, reward: {trimsAwarded: 0, reason: 'Trade completion alone does not award Trims.'},
  execution: {walletUsed: false, transactionBuilt: false, transactionSigned: false, transactionBroadcast: false}};}
function json(value: unknown, status = 200, media = 'application/json') {return new Response(JSON.stringify(value), {status, headers: {'content-type': media}});}
function problem(code: string, status = 409) {return json({error: {code}}, status);}
class Store implements PracticeStorage {
  values = new Map<string, string>(); fail = false;
  getItem(key: string) {return this.values.get(key) ?? null;}
  setItem(key: string, value: string) {if (this.fail) throw new Error('Quota'); this.values.set(key, value);}
}
interface Call {path: string; body: Record<string, unknown>; headers: Headers}
type Reply = (call: Call) => Response | Promise<Response>;
function make(reply?: Reply, timeoutMs = 1000) {
  const storage = new Store(), calls: Call[] = [];
  const client = new PracticeClient({baseUrl: '/api', timeoutMs, fetch: async (input, init = {}) => {
    const call = {path: String(input).slice(4), body: init.body ? JSON.parse(String(init.body)) as Record<string, unknown> : {}, headers: new Headers(init.headers)};
    calls.push(call); if (call.path === '/v1/guest/session') return json({schemaVersion: 1, requestId: call.body['requestId'], ...guest}, 201);
    if (reply) return reply(call);
    if (call.path === '/v1/guest/claim') return json({schemaVersion: 1, status: 'claimed', guestId: GUEST, claimedAt: AT});
    if (call.path === '/v1/practice/session') return json({schemaVersion: 1, userId: ACCOUNT});
    return json({schemaVersion: 2, profile: null}, 200, PROFILE_MEDIA_TYPE);
  }});
  const options = {client, storage, crypto: webcrypto as unknown as PracticeCrypto, now: () => NOW};
  const controller = new AbortController(); let tokenCount = 0;
  const proof: PracticeAccountProof = {subject: SUBJECT, signal: controller.signal, freshAccessToken: async () => `token.${++tokenCount}.safe`};
  const access: PracticeAccountAccess = {...proof, accountId: ACCOUNT};
  return {...options, calls, controller, proof, access, session: () => new PracticeSession(options),
    account: () => new PracticeSession({...options, account: access}), connect: createProductAccountConnector(options)};
}
async function rejects(p: Promise<unknown>, code: string) {await assert.rejects(p, (error: unknown) => error instanceof PracticeError && error.code === code);}

test('new account bootstraps with fresh bearer and never creates an implicit guest', async () => {
  const h = make(); assert.deepEqual(await h.connect(h.proof), {accountId: ACCOUNT, guestDisposition: 'none'});
  assert.deepEqual(h.calls.map(c => c.path), ['/v1/practice/session']);
  assert.equal(h.calls[0]!.headers.get('authorization'), 'Bearer token.1.safe');
  assert.equal(h.calls[0]!.headers.has('x-trimmy-guest'), false);
  assert.equal(h.storage.values.size, 0);
});

test('claim persists exact command before dispatch and precedes provision, retaining guest ledger', async () => {
  const h = make(); await h.session().ensureGuest();
  const result = await h.connect(h.proof); assert.equal(result.guestDisposition, 'claimed');
  assert.deepEqual(h.calls.map(c => c.path), ['/v1/guest/session', '/v1/guest/claim', '/v1/practice/session']);
  const raw = h.storage.getItem(practiceStorageKey('/api'))!, saved = JSON.parse(raw);
  assert.deepEqual(saved.claim.body, h.calls[1]!.body); assert.equal(saved.claim.subject, SUBJECT);
  assert.equal(saved.claim.status, 'claimed'); assert.deepEqual(saved.guest, guest);
  assert.equal(h.calls[1]!.headers.get('x-trimmy-guest'), guest.token);
  assert.equal(h.calls[1]!.headers.get('authorization'), 'Bearer token.1.safe');
  assert.equal(h.calls[2]!.headers.get('authorization'), 'Bearer token.2.safe');
  assert.equal(raw.includes('token.1.safe'), false);
  assert.equal(h.session().hasSavedIdentity, false); assert.equal(h.session().guest, null);
});

test('lost claim response replays the identical persisted key after reload, without premature provision', async () => {
  let attempts = 0, before: unknown;
  const h = make(call => {
    if (call.path === '/v1/guest/claim') {
      before = JSON.parse(h.storage.getItem(practiceStorageKey('/api'))!).claim.body;
      if (++attempts === 1) throw new Error('Lost response');
      return json({schemaVersion: 1, status: 'claimed', guestId: GUEST, claimedAt: AT});
    }
    return json({schemaVersion: 1, userId: ACCOUNT});
  });
  await h.session().ensureGuest(); await rejects(h.connect(h.proof), 'PRACTICE_NETWORK_ERROR');
  assert.equal(h.calls.some(c => c.path === '/v1/practice/session'), false);
  assert.deepEqual(before, h.calls[1]!.body);
  await h.connect(h.proof); assert.deepEqual(h.calls[1]!.body, h.calls[2]!.body);
  assert.equal(h.calls[3]!.path, '/v1/practice/session');
});

test('known existing or expired guest conflict requires explicit choice and preserves the guest record', async () => {
  for (const [code, status] of [['GUEST_CLAIM_ACCOUNT_EXISTS', 409], ['GUEST_SESSION_EXPIRED', 401]] as const) {
    const h = make(call => call.path === '/v1/guest/claim' ? problem(code, status) : json({schemaVersion: 1, userId: ACCOUNT}));
    await h.session().ensureGuest(); await rejects(h.connect(h.proof), code);
    await rejects(h.connect(h.proof), code); assert.equal(h.calls.length, 2);
    assert.equal(h.session().guest?.guestId, GUEST);
    const result = await h.connect({...h.proof, openExistingAccount: true}); assert.equal(result.guestDisposition, 'preserved');
    assert.equal(h.calls.at(-1)!.path, '/v1/practice/session');
    const saved = JSON.parse(h.storage.getItem(practiceStorageKey('/api'))!);
    assert.equal(saved.claim.status, 'preserved'); assert.deepEqual(saved.guest, guest);
  }
});

test('an open-existing flag cannot bypass a new or ambiguous claim; unrelated failures never provision', async () => {
  for (const [code, status] of [['GUEST_CLAIM_ALREADY_USED', 409], ['GUEST_SESSION_REVOKED', 401],
    ['AUTH_INVALID', 401], ['GUEST_SESSION_RATE_LIMITED', 429]] as const) {
    const h = make(() => problem(code, status)); await h.session().ensureGuest();
    await rejects(h.connect({...h.proof, openExistingAccount: true}), code);
    assert.equal(h.calls.some(c => c.path === '/v1/practice/session'), false);
    const saved = JSON.parse(h.storage.getItem(practiceStorageKey('/api'))!); assert.equal(saved.claim.status, 'pending');
  }
});

test('unknown claim belongs to the original subject and blocks guest orders and another account', async () => {
  const h = make(() => {throw new Error('Lost');}); await h.session().ensureGuest();
  await rejects(h.connect(h.proof), 'PRACTICE_NETWORK_ERROR'); const before = h.storage.getItem(practiceStorageKey('/api'));
  await rejects(h.connect({...h.proof, subject: 'did:privy:accountB'}), 'PRACTICE_CLAIM_PENDING');
  await rejects(h.session().previewOrder(intent), 'PRACTICE_CLAIM_PENDING');
  assert.equal(h.calls.length, 2); assert.equal(h.storage.getItem(practiceStorageKey('/api')), before);
});

test('failed persistence prevents claim dispatch, and failed receipt retention keeps the exact claim pending', async () => {
  const h = make(); await h.session().ensureGuest(); h.storage.fail = true;
  await rejects(h.connect(h.proof), 'PRACTICE_STORAGE_UNAVAILABLE'); assert.equal(h.calls.length, 1);
  const j = make(call => {if (call.path === '/v1/guest/claim') {j.storage.fail = true;
    return json({schemaVersion: 1, status: 'claimed', guestId: GUEST, claimedAt: AT});} return json({schemaVersion: 1, userId: ACCOUNT});});
  await j.session().ensureGuest(); await rejects(j.connect(j.proof), 'PRACTICE_STORAGE_UNAVAILABLE');
  assert.equal(JSON.parse(j.storage.getItem(practiceStorageKey('/api'))!).claim.status, 'pending');
  assert.equal(j.calls.length, 2);
});

test('pending guest profile or paper commit blocks account linking without altering either command', async () => {
  for (const kind of ['profile', 'commit']) {
    const h = make(call => {
      if (call.path === '/v1/product/profile' && !call.body['mutationId']) return json({schemaVersion: 2, profile: null}, 200, PROFILE_MEDIA_TYPE);
      if (call.path.endsWith('/preview')) return json(envelope('preview', preview(String(call.body['requestId']))));
      throw new Error('Lost mutation');
    });
    const session = h.session(); await session.ensureGuest();
    if (kind === 'profile') await rejects(session.ensureProfile(), 'PRACTICE_NETWORK_ERROR');
    else {const quote = await session.previewOrder(intent); await rejects(session.commitOrder(quote), 'PRACTICE_NETWORK_ERROR');}
    const before = h.storage.getItem(session.storageKey), count = h.calls.length;
    await rejects(h.connect(h.proof), kind === 'profile' ? 'PRACTICE_PROFILE_PENDING' : 'PRACTICE_COMMIT_PENDING');
    assert.equal(h.calls.length, count); assert.equal(h.storage.getItem(session.storageKey), before);
  }
});

test('claimed guest stays retired on logout; explicit new practice archives its complete journal first', async () => {
  const h = make(); await h.session().ensureGuest(); await h.connect(h.proof);
  const key = practiceStorageKey('/api'), old = h.storage.getItem(key), signedOut = h.session();
  assert.equal(signedOut.hasSavedIdentity, false); assert.equal(signedOut.hasIdentity, false);
  await rejects(signedOut.readProfile(), 'PRACTICE_GUEST_REQUIRED');
  await signedOut.ensureGuest(); assert.equal(h.storage.getItem(`${key}:claimed:${GUEST}`), old);
  assert.equal(signedOut.hasIdentity, true); assert.equal(h.calls.at(-1)!.path, '/v1/guest/session');
});

test('account storage is bound to API, subject and server account UUID; no guest is fabricated', async () => {
  const h = make(), account = h.account();
  assert.equal(account.isAccount, true); assert.equal(account.hasSavedIdentity, true); assert.equal(account.hasIdentity, true);
  assert.equal(account.guest, null); assert.equal(account.hasSavedGuest, false);
  await account.ensureActive(); assert.equal(h.calls.length, 0);
  await rejects(account.ensureGuest(), 'PRACTICE_ACCOUNT_ACTIVE');
  assert.notEqual(account.storageKey, practiceStorageKey('/api'));
  assert.notEqual(account.storageKey, practiceAccountStorageKey('/api', {...h.access, subject: 'did:privy:B'}));
  assert.notEqual(account.storageKey, practiceAccountStorageKey('https://api.example', h.access));
  assert.notEqual(account.storageKey, practiceAccountStorageKey('/api', {...h.access, accountId: ORDER}));
});

test('signed-in paper commit replays the exact durable command with a fresh bearer after reload', async () => {
  let quote: PaperPreview, commits = 0;
  const h = make(call => {
    if (call.path.endsWith('/preview')) {quote = preview(String(call.body['requestId'])); return json(envelope('preview', quote));}
    if (++commits === 1) throw new Error('Lost commit');
    return json(envelope('order', receipt(quote)));
  });
  const session = h.account(), offered = await session.previewOrder(intent);
  await rejects(session.commitOrder(offered), 'PRACTICE_NETWORK_ERROR');
  const saved = JSON.parse(h.storage.getItem(session.storageKey)!);
  assert.equal(saved.pendingCommit.guestId, null); assert.equal(saved.pendingCommit.accountId, ACCOUNT);
  assert.equal(saved.account.subject, SUBJECT); assert.equal(saved.guest, null);
  const restored = h.account(); assert.equal((await restored.retryPendingCommit()).id, ORDER);
  assert.deepEqual(h.calls[1]!.body, h.calls[2]!.body); assert.equal(restored.pendingCommit, null);
  assert.deepEqual(h.calls.map(c => c.headers.get('authorization')), ['Bearer token.1.safe', 'Bearer token.2.safe', 'Bearer token.3.safe']);
  assert.equal([...h.storage.values.values()].some(raw => raw.includes('token.')), false);
});

test('abort during token acquisition dispatches no request even if the old token eventually resolves', async () => {
  const h = make(); let release!: (token: string) => void;
  const proof = {...h.proof, freshAccessToken: () => new Promise<string>(resolve => {release = resolve;})};
  const request = h.client.openAccount(proof); h.controller.abort(); await rejects(request, 'PRACTICE_ABORTED');
  release('old.account.token'); await new Promise(resolve => setTimeout(resolve, 0)); assert.equal(h.calls.length, 0);
});

test('old A epoch cannot complete after A to B to A, and cancelled claim remains exactly retryable', async () => {
  let release!: (response: Response) => void;
  const h = make(() => new Promise<Response>(resolve => {release = resolve;}));
  await h.session().ensureGuest(); const request = h.connect(h.proof);
  while (!release) await new Promise(resolve => setTimeout(resolve, 0));
  h.controller.abort(); await rejects(request, 'PRACTICE_ABORTED');
  release(json({schemaVersion: 1, status: 'claimed', guestId: GUEST, claimedAt: AT}));
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.equal(h.calls.length, 2); assert.equal(JSON.parse(h.storage.getItem(practiceStorageKey('/api'))!).claim.status, 'pending');
  await rejects(h.account().readProfile(), 'PRACTICE_SESSION_CHANGED');
});

test('account unauthorized responses do not poison guest storage; invalid saved account binding fails closed', async () => {
  const h = make(() => problem('AUTH_INVALID', 401)), session = h.account();
  await rejects(session.readPortfolio(), 'AUTH_INVALID'); assert.equal(h.storage.values.size, 0);
  h.storage.setItem(session.storageKey, JSON.stringify({version: 1, apiBase: '/api', issuance: null, guest: null,
    pendingCommit: null, lastReceipt: null, pendingProfile: null, terminalGuestCode: null,
    account: {subject: 'did:privy:other', accountId: ACCOUNT}}));
  assert.throws(() => h.account(), {code: 'PRACTICE_STORAGE_INVALID'});
});

test('closing a session masks a late account response without deleting persisted commands', async () => {
  let release!: (response: Response) => void;
  const h = make(() => new Promise<Response>(resolve => {release = resolve;})), session = h.account();
  const request = session.readProfile(); while (!release) await new Promise(resolve => setTimeout(resolve, 0));
  session.close(); release(json({schemaVersion: 2, profile: null}, 200, PROFILE_MEDIA_TYPE));
  await rejects(request, 'PRACTICE_SESSION_CHANGED'); assert.equal(session.hasIdentity, false);
});
