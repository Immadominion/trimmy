import assert from 'node:assert/strict';
import test from 'node:test';
import {webcrypto} from 'node:crypto';
import {PracticeClient, PracticeError, PROFILE_MEDIA_TYPE, parseDailyDeskShift, parseDailyDeskCompletion,
  parseCareerActivityWeek} from '../src/product/practice-client.js';
import type {DailyDeskShift, PracticeAccountAccess, ProductProfile} from '../src/product/practice-client.js';
import {PracticeSession} from '../src/product/practice-session.js';
import type {PracticeCrypto, PracticeStorage} from '../src/product/practice-session.js';

const UUID = '11111111-1111-4111-8111-111111111111', ACCOUNT = '22222222-2222-4222-8222-222222222222';
const NOW = Date.parse('2026-09-24T12:00:00Z'), AT = '2026-09-24T12:00:00.123456+00:00';
const guest = {guestId: UUID, token: `tg1_${'A'.repeat(43)}`, expiresAt: '2026-10-24T12:00:00.000Z', hardExpiresAt: '2026-11-24T12:00:00.000Z'};
const week = {serverDate: '2026-09-24', weekStart: '2026-09-21', activeDates: ['2026-09-21', '2026-09-24']};
const profile: ProductProfile = {revision: 3, onboarding: {goal: 'learn', knowledge: 'basics', persona: 'oracle', dailyGoal: 'show-up', handle: 'ada'},
  launchCheckpoint: 'app', hasConfirmedPaperTrade: true, createdAt: '2026-09-20T12:00:00.000Z', updatedAt: '2026-09-24T12:00:00.000Z'};
function shift(done = false): DailyDeskShift {
  return {date: '2026-09-24', story: {id: 'the-cheap-share', ordinal: 3, title: 'That share is cheaper.', speaker: 'shark', body: 'Compare two companies.',
    choices: ['compare', 'business', 'cheap'].map(id => ({id, label: id, outcome: `Outcome ${id}.`, takeaway: `Takeaway ${id}.`}))},
    completedChoice: done ? 'compare' : null, completedAt: done ? AT : null, trimsEarned: done ? 10 : 0,
    history: done ? [{date: '2026-09-24', caseId: 'the-cheap-share', title: 'That share is cheaper.', choiceId: 'compare', completedAt: AT}] : []};
}
function json(value: unknown, status = 200, media = 'application/json') {return new Response(JSON.stringify(value), {status, headers: {'content-type': media}});}
class Store implements PracticeStorage {
  values = new Map<string, string>(); fail = false;
  getItem(key: string) {return this.values.get(key) ?? null;}
  setItem(key: string, value: string) {if (this.fail) throw new Error('Quota'); this.values.set(key, value);}
}
interface Call {path: string; method: string; body: Record<string, unknown> | null; headers: Headers}
type Reply = (call: Call) => Response | Promise<Response>;
function setup(reply: Reply, timeoutMs = 1000) {
  const calls: Call[] = [], storage = new Store(), controller = new AbortController(); let tokens = 0;
  const account: PracticeAccountAccess = {subject: 'did:privy:existingAccount', accountId: ACCOUNT,
    freshAccessToken: async () => `test.token.${++tokens}`, signal: controller.signal};
  const client = new PracticeClient({baseUrl: '/api', timeoutMs, fetch: async (input, init = {}) => {
    const call = {path: String(input).slice(4), method: init.method ?? 'GET', body: init.body ? JSON.parse(String(init.body)) as Record<string, unknown> : null,
      headers: new Headers(init.headers)}; calls.push(call);
    if (call.path === '/v1/guest/session') return json({schemaVersion: 1, requestId: call.body?.['requestId'], ...guest}, 201);
    return reply(call);
  }});
  const make = (signedIn = true) => new PracticeSession({client, storage, ...(signedIn ? {account} : {}), crypto: webcrypto as unknown as PracticeCrypto, now: () => NOW});
  return {calls, storage, client, controller, account, make};
}
async function rejects(promise: Promise<unknown>, code: string) {
  await assert.rejects(promise, (error: unknown) => error instanceof PracticeError && error.code === code);
}
function invalid(value: unknown, parse: (value: unknown) => unknown) {assert.throws(() => parse(value), (error: unknown) => error instanceof PracticeError && error.code === 'PRACTICE_RESPONSE_INVALID');}
function deferred<T>() {let resolve!: (value: T) => void; const promise = new Promise<T>(r => resolve = r); return {promise, resolve};}

// The same payload returned to mobile must be readable here, including PostgreSQL timestamp precision.
test('daily and activity parsers preserve confirmed server progress and freeze their complete trees', () => {
  const result = parseDailyDeskShift(shift(true)); assert.deepEqual(result, shift(true));
  assert.ok(Object.isFrozen(result.story.choices[0])); assert.ok(Object.isFrozen(result.history));
  assert.deepEqual(parseCareerActivityWeek(week), week);
  assert.deepEqual(parseDailyDeskCompletion({date: '2026-09-24', caseId: 'the-cheap-share', choiceId: 'compare'}),
    {date: '2026-09-24', caseId: 'the-cheap-share', choiceId: 'compare'});
});
test('daily parser rejects fabricated rewards, missing history, duplicate choices and invalid calendar dates', () => {
  for (const value of [{...shift(), date: '2026-02-31'}, {...shift(), trimsEarned: 10}, {...shift(true), history: []},
    {...shift(true), completedChoice: 'invented'}, {...shift(true), completedAt: '2026-09-24T25:00:00Z'},
    {...shift(), story: {...shift().story, choices: Array(3).fill(shift().story.choices[0])}},
    {...shift(), story: {...shift().story, speaker: 'invented'}}, {...shift(true), history: [...shift(true).history, ...shift(true).history]}]) invalid(value, parseDailyDeskShift);
  invalid({date: '2026-09-24', caseId: '../attack', choiceId: 'compare'}, parseDailyDeskCompletion);
  invalid({date: '2026-09-24', caseId: 'case', choiceId: 'compare', reward: 10}, parseDailyDeskCompletion);
});
test('week parser rejects non-Monday anchors, future/duplicate activity and impossible dates', () => {
  for (const value of [{...week, weekStart: '2026-09-22'}, {...week, serverDate: '2026-09-28'},
    {...week, activeDates: ['2026-09-25']}, {...week, activeDates: ['2026-09-20']}, {...week, activeDates: ['2026-09-21', '2026-09-21']},
    {...week, serverDate: '2026-02-31'}]) invalid(value, parseCareerActivityWeek);
});
test('guest and signed-in reads use the exact deployed mobile endpoints and live identity', async () => {
  const h = setup(call => call.path.endsWith('activity-week') ? json({schemaVersion: 1, activityWeek: week}) : json({shift: shift(true)}));
  const account = h.make(); assert.equal((await account.readDailyDesk()).completedChoice, 'compare');
  assert.deepEqual(await account.readActivityWeek(), week);
  assert.deepEqual(h.calls.map(c => c.headers.get('authorization')), ['Bearer test.token.1', 'Bearer test.token.2']);
  const local = h.make(false); await local.ensureGuest(); await local.readDailyDesk(); await local.readActivityWeek();
  assert.equal(h.calls.at(-1)!.headers.get('authorization'), `Guest ${guest.token}`);
  assert.equal(h.calls.at(-2)!.path, '/v1/career/daily-desk');
  assert.equal(h.storage.values.size, 1, 'read-only account usage creates no local write journal');
});
test('a later mobile completion is reflected by the next web server read with no browser completion flag', async () => {
  let mobileCompleted = false;
  const h = setup(() => json({shift: shift(mobileCompleted)})); const session = h.make();
  assert.equal((await session.readDailyDesk()).completedChoice, null); mobileCompleted = true;
  assert.equal((await session.readDailyDesk()).completedChoice, 'compare'); assert.equal(h.storage.values.size, 0);
});
test('daily completion is durable before dispatch and replays the exact decision after lost response/reload', async () => {
  let attempts = 0;
  const h = setup(call => {
    const raw = h.storage.getItem(h.make().storageKey)!;
    assert.deepEqual(JSON.parse(raw).pendingDailyDesk, call.body);
    if (++attempts === 1) throw new Error('Lost response');
    return json({shift: shift(true)});
  });
  const session = h.make(); await rejects(session.completeDailyDesk(shift(), 'compare'), 'PRACTICE_NETWORK_ERROR');
  assert.equal(session.pendingDailyDesk?.choiceId, 'compare');
  const reloaded = h.make(); assert.equal((await reloaded.retryPendingDailyDesk()).completedChoice, 'compare');
  assert.deepEqual(h.calls[0]!.body, h.calls[1]!.body); assert.equal(reloaded.pendingDailyDesk, null);
  assert.equal(h.storage.getItem(reloaded.storageKey)!.includes('test.token'), false);
});
test('another choice cannot replace an ambiguous command and guest claim waits for it', async () => {
  const h = setup(() => {throw new Error('Offline');}); const session = h.make(false); await session.ensureGuest();
  await rejects(session.completeDailyDesk(shift(), 'compare'), 'PRACTICE_NETWORK_ERROR');
  const before = h.calls.length;
  await rejects(session.completeDailyDesk(shift(), 'business'), 'PRACTICE_DAILY_DESK_PENDING');
  await rejects(session.claimForAccount(h.account), 'PRACTICE_DAILY_DESK_PENDING');
  assert.equal(h.calls.length, before); assert.equal(session.pendingDailyDesk?.choiceId, 'compare');
});
test('known midnight and conflicting completion errors clear only the rejected command for a server refresh', async () => {
  for (const [code, status] of [['DAY_CHANGED', 409], ['SHIFT_ALREADY_COMPLETE', 409], ['INVALID_CHOICE', 400]] as const) {
    const h = setup(call => call.method === 'POST' ? json({code}, status) : json({shift: shift(code === 'SHIFT_ALREADY_COMPLETE')}));
    const session = h.make(); await rejects(session.completeDailyDesk(shift(), 'compare'), code);
    assert.equal(session.pendingDailyDesk, null); assert.equal((await session.readDailyDesk()).completedChoice, code === 'SHIFT_ALREADY_COMPLETE' ? 'compare' : null);
  }
});
test('outage, unrecognized failure, invalid success and request abort never erase an unknown write', async () => {
  const responses = [() => json({code: 'DAILY_DESK_UNAVAILABLE'}, 503), () => json({code: 'UNKNOWN_FAILURE'}, 409), () => json({shift: shift()})];
  for (const reply of responses) {
    const h = setup(reply); const session = h.make(); await assert.rejects(session.completeDailyDesk(shift(), 'compare'));
    assert.equal(h.make().pendingDailyDesk?.choiceId, 'compare');
  }
  const waiting = deferred<Response>(), dispatched = deferred<void>(), h = setup(() => {dispatched.resolve(); return waiting.promise;}), session = h.make(), abort = new AbortController();
  const save = session.completeDailyDesk(shift(), 'compare', abort.signal); await dispatched.promise; abort.abort(); await rejects(save, 'PRACTICE_ABORTED');
  assert.equal(h.make().pendingDailyDesk?.choiceId, 'compare'); waiting.resolve(json({shift: shift(true)}));
});
test('a read begun before completion cannot overwrite the newer confirmed result', async () => {
  const old = deferred<Response>(); const h = setup(call => call.method === 'GET' ? old.promise : json({shift: shift(true)}));
  const session = h.make(), read = session.readDailyDesk();
  await session.completeDailyDesk(shift(), 'compare'); old.resolve(json({shift: shift()}));
  assert.equal((await read).completedChoice, 'compare');
});
test('a refresh during completion waits for confirmation and its cancellation does not cancel saving', async () => {
  const saved = deferred<Response>(), h = setup(() => saved.promise), session = h.make();
  const write = session.completeDailyDesk(shift(), 'compare'); const readAbort = new AbortController();
  const read = session.readDailyDesk(readAbort.signal); readAbort.abort(); await rejects(read, 'PRACTICE_ABORTED');
  saved.resolve(json({shift: shift(true)})); assert.equal((await write).completedChoice, 'compare'); assert.equal(h.calls.length, 1);
});
test('closed session and account identity changes reject delayed completion without clearing pending recovery', async () => {
  for (const mode of ['closed', 'identity'] as const) {
    const saved = deferred<Response>(), h = setup(() => saved.promise), session = h.make();
    const write = session.completeDailyDesk(shift(), 'compare');
    if (mode === 'closed') session.close(); else h.controller.abort();
    saved.resolve(json({shift: shift(true)})); await rejects(write, 'PRACTICE_SESSION_CHANGED');
    assert.equal(h.make().pendingDailyDesk?.choiceId, 'compare');
  }
});
test('journal write failure prevents completion dispatch; another tab invalidates a pending response', async () => {
  const saved = deferred<Response>(), h = setup(() => saved.promise); const session = h.make();
  h.storage.fail = true; await rejects(session.completeDailyDesk(shift(), 'compare'), 'PRACTICE_STORAGE_UNAVAILABLE'); assert.equal(h.calls.length, 0);
  h.storage.fail = false; const write = session.completeDailyDesk(shift(), 'compare');
  const current = h.storage.getItem(session.storageKey)!; h.storage.setItem(session.storageKey, current + ' ');
  saved.resolve(json({shift: shift(true)})); await rejects(write, 'PRACTICE_SESSION_CHANGED');
});
test('exact retry across midnight confirms yesterday through returned server history without completing today', async () => {
  const next = {...shift(), date: '2026-09-25', history: shift(true).history};
  const h = setup(() => json({shift: next})), session = h.make();
  const result = await session.completeDailyDesk(shift(), 'compare');
  assert.equal(result.completedChoice, null); assert.equal(result.date, '2026-09-25'); assert.equal(session.pendingDailyDesk, null);
});
test('account journals remain isolated and malformed durable decisions fail closed', async () => {
  const h = setup(() => {throw new Error('Offline');}), session = h.make();
  await rejects(session.completeDailyDesk(shift(), 'compare'), 'PRACTICE_NETWORK_ERROR');
  const other = new PracticeSession({client: h.client, storage: h.storage, account: {...h.account, subject: 'did:privy:anotherAccount'}});
  assert.equal(other.pendingDailyDesk, null);
  const raw = JSON.parse(h.storage.getItem(session.storageKey)!); raw.pendingDailyDesk.date = '2026-02-31';
  h.storage.setItem(session.storageKey, JSON.stringify(raw)); assert.throws(h.make, (e: unknown) => e instanceof PracticeError && e.code === 'PRACTICE_STORAGE_INVALID');
});
test('persona edit uses current server revision and preserves all other mobile profile fields', async () => {
  const h = setup(call => call.method === 'GET' ? json({schemaVersion: 2, profile}, 200, PROFILE_MEDIA_TYPE) :
    json({schemaVersion: 2, profile: {...profile, revision: 4, onboarding: {...profile.onboarding, persona: 'wolf'}}}, 200, PROFILE_MEDIA_TYPE));
  const session = h.make(); assert.equal((await session.updatePersona('wolf')).onboarding.persona, 'wolf');
  assert.equal(h.calls[1]!.body?.['baseRevision'], profile.revision);
  assert.deepEqual(h.calls[1]!.body?.['onboarding'], {...profile.onboarding, persona: 'wolf'});
  assert.equal(h.calls[1]!.body?.['launchCheckpoint'], 'app');
});
test('lost persona save retries its mutation before a new edit; revision conflict requires explicit retry', async () => {
  let attempts = 0;
  const h = setup(call => {
    if (call.method === 'GET') return json({schemaVersion: 2, profile}, 200, PROFILE_MEDIA_TYPE);
    if (++attempts === 1) throw new Error('Lost');
    return json({error: {code: 'PRODUCT_PROFILE_REVISION_CONFLICT'}}, 409);
  });
  const first = h.make(); await rejects(first.updatePersona('wolf'), 'PRACTICE_NETWORK_ERROR');
  const reloaded = h.make(); await rejects(reloaded.updatePersona('shark'), 'PRODUCT_PROFILE_REVISION_CONFLICT');
  assert.deepEqual(h.calls[1]!.body, h.calls[2]!.body);
  assert.equal(JSON.parse(h.storage.getItem(reloaded.storageKey)!).pendingProfile, null);
  await rejects(reloaded.updatePersona('shark'), 'PRODUCT_PROFILE_REVISION_CONFLICT');
  assert.equal(h.calls[3]!.method, 'GET'); assert.equal((h.calls[4]!.body?.['onboarding'] as {persona: string}).persona, 'shark');
});
