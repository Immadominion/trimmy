import assert from 'node:assert/strict';
import test from 'node:test';
import {webcrypto} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {PracticeClient, PracticeError, parseWorkdayJourney, parseWorkdayMutation} from '../src/product/practice-client.js';
import type {WorkdayAnswer, WorkdayJourney, PracticeAccountAccess} from '../src/product/practice-client.js';
import {PracticeSession} from '../src/product/practice-session.js';
import type {PracticeCrypto, PracticeStorage} from '../src/product/practice-session.js';

const content = JSON.parse(readFileSync(new URL('../../../content/workdays/intern-v1.json', import.meta.url), 'utf8'));
const AT = '2026-09-24T20:00:00.123456+00:00', NOW = Date.parse('2026-09-24T20:00:00Z');
const GUEST = '11111111-1111-4111-8111-111111111111', ACCOUNT = '22222222-2222-4222-8222-222222222222';
const guest = {guestId: GUEST, token: `tg1_${'A'.repeat(43)}`, expiresAt: '2026-10-24T20:00:00.000Z', hardExpiresAt: '2026-11-24T20:00:00.000Z'};
function journey(step = 0, draft = '', revision = step): WorkdayJourney {
  return {contentVersion: content.contentVersion, date: '2026-09-24', completedCount: step === 3 ? 1 : 0,
    assignments: content.assignments.map((definition: Record<string, any>, index: number) => {
      const {context: _context, feedback, ...rest} = definition;
      const {requiredIds: evidenceIds, ...evidence} = definition.evidence;
      const {requiredIds: fileIds, ...file} = definition.file;
      const {acceptedAnswers: _accepted, ...decision} = definition.decision;
      const activeStep = index === 0 ? step : 0;
      return {...rest, evidence: {...evidence, count: evidenceIds.length}, decision, file: {...file, count: fileIds.length},
        revision: index === 0 ? revision : 0, step: activeStep,
        answers: {...(activeStep > 0 ? {'0': {ids: [...evidenceIds].sort()}} : {}), ...(activeStep > 1 ? {'1': {value: '200'}} : {}),
          ...(activeStep > 2 ? {'2': {ids: [...fileIds].sort()}} : {})}, draft: index === 0 ? draft : '',
        completedAt: activeStep === 3 ? AT : null, artifact: activeStep === 3 ? `Sales rose. Profit fell.\n\n${draft}` : null,
        feedback: activeStep === 3 ? feedback : null, contextNote: null};
    })};
}
function json(value: unknown, status = 200) {return new Response(JSON.stringify(value), {status, headers: {'content-type': 'application/json'}});}
class Store implements PracticeStorage {
  values = new Map<string, string>(); fail = false;
  getItem(key: string) {return this.values.get(key) ?? null;}
  setItem(key: string, value: string) {if (this.fail) throw new Error('Quota'); this.values.set(key, value);}
}
interface Call {path: string; method: string; body: Record<string, unknown> | null; headers: Headers}
function setup(reply: (call: Call) => Response | Promise<Response>, timeoutMs = 1000) {
  const storage = new Store(), calls: Call[] = [], controller = new AbortController(); let tokens = 0;
  const account: PracticeAccountAccess = {subject: 'did:privy:workdayAccount', accountId: ACCOUNT, signal: controller.signal,
    freshAccessToken: async () => `fresh.proof.${++tokens}`};
  const client = new PracticeClient({baseUrl: '/api', timeoutMs, fetch: async (input, init = {}) => {
    const call = {path: String(input).slice(4), method: init.method ?? 'GET', body: init.body ? JSON.parse(String(init.body)) : null, headers: new Headers(init.headers)};
    calls.push(call); if (call.path === '/v1/guest/session') return json({schemaVersion: 1, requestId: call.body?.['requestId'], ...guest}, 201);
    return reply(call);
  }});
  const make = (signedIn = true) => new PracticeSession({client, storage, ...(signedIn ? {account} : {}), crypto: webcrypto as unknown as PracticeCrypto, now: () => NOW});
  return {client, storage, calls, controller, account, make};
}
async function rejects(task: Promise<unknown>, code: string) {await assert.rejects(task, (e: unknown) => e instanceof PracticeError && e.code === code);}
function invalid(value: unknown) {assert.throws(() => parseWorkdayJourney(value), (e: unknown) => e instanceof PracticeError && e.code === 'PRACTICE_RESPONSE_INVALID');}
function deferred<T>() {let resolve!: (value: T) => void; const promise = new Promise<T>(r => resolve = r); return {promise, resolve};}
const first = (value: WorkdayJourney) => value.assignments[0]!;
const evidence: WorkdayAnswer = {ids: ['before', 'after']};
const handoff: WorkdayAnswer = {ids: ['fact-2', 'fact-1']};

test('all20 published workdays parse from the exact public projection without answer keys or invented progress', () => {
  const parsed = parseWorkdayJourney(journey()); assert.equal(parsed.assignments.length, 20); assert.equal(parsed.completedCount, 0);
  assert.equal(parsed.assignments[0]!.step, 0); assert.ok(Object.isFrozen(parsed.assignments[0]!.rows));
  assert.equal('requiredIds' in parsed.assignments[0]!.evidence, false); assert.equal('acceptedAnswers' in parsed.assignments[0]!.decision, false);
  const completed = parseWorkdayJourney(journey(3, 'My saved note.')); assert.equal(completed.completedCount, 1);
  assert.equal(first(completed).completedAt, AT); assert.equal(first(completed).draft, 'My saved note.');
});
test('workday parser rejects mismatched stage, reordered unlocks, fabricated completion, invalid dates and duplicate evidence', () => {
  const good = journey(), item = first(good);
  for (const override of [{step: 3}, {revision: -1}, {step: 1, revision: 1, answers: {}},
    {completedAt: AT}, {rows: [item.rows[0], item.rows[0]]}, {evidence: {...item.evidence, count: 7}},
    {decision: {...item.decision, kind: 'invented'}}, {draft: '\u0000'}]) {
    invalid({...good, assignments: [{...item, ...override}, ...good.assignments.slice(1)]});
  }
  invalid({...good, date: '2026-02-31'}); invalid({...good, completedCount: 1});
  invalid({...good, assignments: [...good.assignments].reverse()});
  const later = {...good.assignments[1]!, step: 1, revision: 1, answers: {'0': {ids: ['aster', 'helio']}}};
  invalid({...good, assignments: [item, later, ...good.assignments.slice(2)]});
});
test('write parser accepts Unicode notes and exact schemas but rejects ambiguous answer bodies', () => {
  assert.equal(parseWorkdayMutation({kind: 'draft', body: {assignmentId: 'morning-brief', revision: 2, draft: '😀'.repeat(280)}}).kind, 'draft');
  for (const value of [
    {kind: 'draft', body: {assignmentId: 'morning-brief', revision: 2, draft: 'x'.repeat(281)}},
    {kind: 'step', body: {assignmentId: 'morning-brief', revision: 0, step: 0, answer: {ids: ['before', 'before']}}},
    {kind: 'step', body: {assignmentId: 'morning-brief', revision: 0, step: 0, answer: {ids: ['before'], value: '200'}}},
    {kind: 'step', body: {assignmentId: 'morning-brief', revision: 0, step: 3, answer: evidence}},
    {kind: 'draft', body: {assignmentId: 'morning-brief', revision: 2147483647, draft: ''}},
  ]) assert.throws(() => parseWorkdayMutation(value));
});
test('guest and account read fresh shared work without issuing a new guest or persisting server snapshots', async () => {
  let state = journey(); const h = setup(() => json({journey: state})), session = h.make();
  assert.equal(first(await session.readWorkdays()).step, 0); state = journey(2, 'Written on mobile.', 5);
  assert.equal(first(await session.readWorkdays()).draft, 'Written on mobile.'); assert.equal(h.storage.values.size, 0);
  assert.deepEqual(h.calls.map(c => c.headers.get('authorization')), ['Bearer fresh.proof.1', 'Bearer fresh.proof.2']);
  const local = h.make(false); await local.ensureGuest(); await local.readWorkdays();
  assert.equal(h.calls.at(-1)!.headers.get('authorization'), `Guest ${guest.token}`);
});
test('client accepts bounded published journeys over256KB up to mobile512KB', async () => {
  const base = first(journey());
  const expanded = {...journey(), assignments: Array.from({length: 200}, (_, index) => ({...base, id: `assignment-${index + 1}`, ordinal: index + 1,
    brief: 'A'.repeat(700)}))};
  const size = Buffer.byteLength(JSON.stringify({journey: expanded})); assert.ok(size > 262144 && size < 524288, `Fixture size ${size}`);
  const h = setup(() => json({journey: expanded})); assert.equal((await h.make().readWorkdays()).assignments.length, 200);
});
test('evidence, normalized numeric decision, draft and final filing use exact server revisions and routes', async () => {
  let request = 0;
  const responses = [journey(1), journey(2), journey(2, 'Keep the source.', 3), journey(3, 'Keep the source.', 4)];
  const h = setup(() => json({journey: responses[request++]})), session = h.make();
  let result = await session.saveWorkdayStep(first(journey()), evidence);
  result = await session.saveWorkdayStep(first(result), {value: '000200.00'});
  result = await session.saveWorkdayDraft(first(result), 'Keep the source.');
  result = await session.saveWorkdayStep(first(result), handoff, {draft: 'Keep the source.'});
  assert.equal(result.completedCount, 1); assert.equal(first(result).step, 3); assert.equal(session.pendingWorkdayMutation, null);
  assert.deepEqual(h.calls.map(c => c.path), ['/v1/career/workdays/step', '/v1/career/workdays/step', '/v1/career/workdays/draft', '/v1/career/workdays/step']);
  assert.deepEqual(h.calls.map(c => c.body?.['revision']), [0, 1, 2, 3]);
});
test('lost draft or step response survives reload and replays the exact command before any new edit', async () => {
  for (const kind of ['draft', 'step'] as const) {
    let attempts = 0;
    const result = kind === 'draft' ? journey(2, 'Saved draft.', 3) : journey(3, 'Final note.', 3);
    const h = setup(call => {assert.deepEqual(JSON.parse(h.storage.getItem(h.make().storageKey)!).pendingWorkdayMutation.body, call.body);
      if (++attempts === 1) throw new Error('Response lost'); return json({journey: result});});
    const session = h.make();
    await rejects(kind === 'draft' ? session.saveWorkdayDraft(first(journey(2)), 'Saved draft.') :
      session.saveWorkdayStep(first(journey(2)), handoff, {draft: 'Final note.'}), 'PRACTICE_NETWORK_ERROR');
    await rejects(session.saveWorkdayDraft(first(journey(2)), 'Different draft.'), 'PRACTICE_WORKDAY_PENDING');
    const restored = h.make(); await restored.retryPendingWorkday(); assert.deepEqual(h.calls[0]!.body, h.calls[1]!.body);
    assert.equal(restored.pendingWorkdayMutation, null); assert.equal(h.storage.getItem(restored.storageKey)!.includes('fresh.proof'), false);
  }
});
test('known conflicts and evidence rejection clear the rejected command and require explicit server refresh', async () => {
  for (const [code, status] of [['WORK_CHANGED', 409], ['WORK_LOCKED', 409], ['CHECK_EVIDENCE', 400], ['CHECK_DECISION', 400], ['INVALID_WORK', 400]] as const) {
    const h = setup(call => call.method === 'POST' ? json({code}, status) : json({journey: journey(2, 'Mobile update.', 5)}));
    const session = h.make(); await rejects(session.saveWorkdayStep(first(journey()), evidence), code);
    assert.equal(session.pendingWorkdayMutation, null);
    assert.equal(first(await session.readWorkdays()).draft, 'Mobile update.');
    assert.equal(h.calls.length, 2, 'no automatic revised write');
  }
});
test('unknown failure, malformed success, timeout and abort retain pending commands for exact retry', async () => {
  for (const reply of [() => json({code: 'WORK_UNAVAILABLE'}, 503), () => json({journey: journey()}), () => json({code: 'UNKNOWN'}, 409)]) {
    const h = setup(reply), session = h.make(); await assert.rejects(session.saveWorkdayStep(first(journey()), evidence));
    assert.equal(h.make().pendingWorkdayMutation?.kind, 'step');
  }
  const never = deferred<Response>(), h = setup(() => never.promise, 10), session = h.make();
  await rejects(session.saveWorkdayStep(first(journey()), evidence), 'PRACTICE_TIMEOUT'); assert.equal(h.make().pendingWorkdayMutation?.kind, 'step');
  never.resolve(json({journey: journey(1)}));
});
test('old reads and refreshes during writing observe the confirmed newer stage instead of resetting it', async () => {
  const old = deferred<Response>(), saved = deferred<Response>();
  const h = setup(call => call.method === 'GET' ? old.promise : saved.promise), session = h.make();
  const initial = session.readWorkdays(), write = session.saveWorkdayStep(first(journey()), evidence), during = session.readWorkdays();
  saved.resolve(json({journey: journey(1)})); await write; old.resolve(json({journey: journey()}));
  assert.equal(first(await initial).step, 1); assert.equal(first(await during).step, 1); assert.equal(h.calls.length, 2);
});
test('cancelled refresh does not cancel a save, while closed/changed identities cannot accept delayed writes', async () => {
  const saved = deferred<Response>(), started = deferred<void>();
  const h = setup(() => {started.resolve(); return saved.promise;}), session = h.make(), abort = new AbortController();
  const write = session.saveWorkdayStep(first(journey()), evidence); await started.promise;
  const read = session.readWorkdays(abort.signal); abort.abort(); await rejects(read, 'PRACTICE_ABORTED');
  session.close(); saved.resolve(json({journey: journey(1)})); await rejects(write, 'PRACTICE_SESSION_CHANGED');
  assert.equal(h.make().pendingWorkdayMutation?.kind, 'step');
});
test('pending workdays guard guest claim, and legacy daily journals still recover before workday writes', async () => {
  const h = setup(() => {throw new Error('Offline');}), local = h.make(false); await local.ensureGuest();
  await rejects(local.saveWorkdayStep(first(journey()), evidence), 'PRACTICE_NETWORK_ERROR');
  await rejects(local.claimForAccount(h.account), 'PRACTICE_WORKDAY_PENDING');
  const other = setup(() => json({journey: journey(1)})), old = other.make();
  // Existing version1 journals migrate the new optional command without deleting prior daily recovery.
  const raw = {version: 1, apiBase: '/api', issuance: null, guest: null, pendingCommit: null, lastReceipt: null, pendingProfile: null,
    terminalGuestCode: null, account: {subject: other.account.subject, accountId: ACCOUNT},
    pendingDailyDesk: {date: '2026-09-24', caseId: 'the-cheap-share', choiceId: 'compare'}};
  other.storage.setItem(old.storageKey, JSON.stringify(raw)); const restored = other.make();
  assert.equal(restored.pendingDailyDesk?.choiceId, 'compare'); await rejects(restored.saveWorkdayStep(first(journey()), evidence), 'PRACTICE_DAILY_DESK_PENDING');
  assert.equal(other.calls.length, 0); assert.equal(restored.pendingDailyDesk?.choiceId, 'compare');
});
test('account, origin and cross-tab binding isolate pending work; corrupt commands are never replaced', async () => {
  const h = setup(() => {throw new Error('Offline');}), session = h.make();
  await rejects(session.saveWorkdayStep(first(journey()), evidence), 'PRACTICE_NETWORK_ERROR');
  const other = new PracticeSession({client: h.client, storage: h.storage, account: {...h.account, subject: 'did:privy:different'}});
  assert.equal(other.pendingWorkdayMutation, null);
  const raw = JSON.parse(h.storage.getItem(session.storageKey)!); raw.pendingWorkdayMutation.body.answer = {ids: ['before', 'before']};
  h.storage.setItem(session.storageKey, JSON.stringify(raw)); assert.throws(h.make, (e: unknown) => e instanceof PracticeError && e.code === 'PRACTICE_STORAGE_INVALID');
});
test('quota or lost receipt persistence prevents reporting success while keeping the original command recoverable', async () => {
  const h = setup(() => {h.storage.fail = true; return json({journey: journey(1)});}), session = h.make();
  h.storage.fail = true; await rejects(session.saveWorkdayStep(first(journey()), evidence), 'PRACTICE_STORAGE_UNAVAILABLE'); assert.equal(h.calls.length, 0);
  h.storage.fail = false; await rejects(session.saveWorkdayStep(first(journey()), evidence), 'PRACTICE_STORAGE_UNAVAILABLE');
  h.storage.fail = false; assert.equal(h.make().pendingWorkdayMutation?.kind, 'step');
});
