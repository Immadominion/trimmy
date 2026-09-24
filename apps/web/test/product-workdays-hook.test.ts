import assert from 'node:assert/strict';
import test from 'node:test';
import {webcrypto} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {setTimeout as delay} from 'node:timers/promises';
import {act, createElement, StrictMode} from 'react';
import {createRoot} from 'react-dom/client';
import {JSDOM} from 'jsdom';
import {PracticeClient, PracticeError, parseWorkdayJourney} from '../src/product/practice-client.js';
import type {WorkdayJourney} from '../src/product/practice-client.js';
import {PracticeSession} from '../src/product/practice-session.js';
import type {PracticeCrypto} from '../src/product/practice-session.js';
import {useWorkdays} from '../src/product/use-workdays.js';
import type {WorkdaysState} from '../src/product/use-workdays.js';

const definitions = JSON.parse(readFileSync(new URL('../../../content/workdays/intern-v1.json', import.meta.url), 'utf8')).assignments.slice(0, 2);
function journey(step = 0, draft = '', revision = step): WorkdayJourney {
  return parseWorkdayJourney({contentVersion: 'intern-2026-09-24.1', date: '2026-09-24', completedCount: step === 3 ? 1 : 0,
    assignments: definitions.map((definition: Record<string, any>, index: number) => {
      const {requiredIds: evidenceIds, ...evidence} = definition.evidence, {requiredIds: fileIds, ...file} = definition.file;
      const {acceptedAnswers: _accepted, ...decision} = definition.decision;
      const stage = index === 0 ? step : 0;
      return {...definition, evidence: {...evidence, count: evidenceIds.length}, file: {...file, count: fileIds.length}, decision,
        step: stage, revision: index === 0 ? revision : 0, draft: index === 0 ? draft : '',
        answers: {...(stage > 0 ? {'0': {ids: [...evidenceIds].sort()}} : {}), ...(stage > 1 ? {'1': {value: '200'}} : {}),
          ...(stage > 2 ? {'2': {ids: [...fileIds].sort()}} : {})}, completedAt: stage === 3 ? '2026-09-24T20:00:00.123456+00:00' : null,
        artifact: stage === 3 ? `Saved brief.\n\n${draft}` : null, feedback: stage === 3 ? definition.feedback : null, contextNote: null};
    })});
}
function deferred<T>() {let resolve!: (value: T) => void; const promise = new Promise<T>(r => resolve = r); return {promise, resolve};}
interface Call {method: string; path: string; body: Record<string, any> | null}
async function harness(initial = journey(), completed: () => Promise<void> = async () => {}) {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {url: 'https://trimmy.example/#career', pretendToBeVisual: true});
  const original = new Map<string, PropertyDescriptor | undefined>();
  const expose = (key: string, value: unknown) => {original.set(key, Object.getOwnPropertyDescriptor(globalThis, key)); Object.defineProperty(globalThis, key, {configurable: true, value, writable: true});};
  expose('window', dom.window); expose('document', dom.window.document); expose('navigator', dom.window.navigator); expose('IS_REACT_ACT_ENVIRONMENT', true);
  const data = new Map<string, string>(), storage = {getItem: (key: string) => data.get(key) ?? null, setItem: (key: string, value: string) => {data.set(key, value);}};
  const calls: Call[] = []; let server = initial, intercept: ((call: Call) => Response | Promise<Response> | undefined) | undefined;
  const locks = {request: async (_key: string, _options: unknown, callback: () => unknown) => callback()} as Pick<LockManager, 'request'>;
  const client = new PracticeClient({baseUrl: '/api', fetch: async (input, options = {}) => {
    const call = {method: options.method ?? 'GET', path: String(input).slice(4), body: options.body ? JSON.parse(String(options.body)) : null}; calls.push(call);
    const intercepted = intercept?.(call); if (intercepted !== undefined) return intercepted;
    if (call.method === 'GET') return Response.json({journey: server});
    const body = call.body!, current = server.assignments[0]!;
    if (call.path.endsWith('/step') && current.step > body['step']) return Response.json({journey: server});
    if (body['revision'] !== current.revision) return Response.json({code: 'WORK_CHANGED'}, {status: 409});
    server = call.path.endsWith('/draft') ? journey(2, body['draft'], current.revision + 1) :
      journey(current.step + 1, body['draft'] ?? current.draft, current.revision + 1);
    return Response.json({journey: server});
  }});
  const makeSession = (subject = 'did:privy:accountA') => new PracticeSession({client, storage, locks, crypto: webcrypto as unknown as PracticeCrypto,
    account: {subject, accountId: '11111111-1111-4111-8111-111111111111', signal: new AbortController().signal, freshAccessToken: async () => 'test.proof'}});
  let session = makeSession(), state!: WorkdaysState;
  function Probe() {state = useWorkdays(session, true, 'work', completed); return createElement('div', null, state.journey?.completedCount ?? 'loading');}
  const root = createRoot(dom.window.document.getElementById('root')!);
  const render = async () => {await act(async () => {root.render(createElement(StrictMode, null, createElement(Probe))); await delay(0);});};
  await render();
  return {get state() {return state;}, get session() {return session;}, calls, makeSession,
    setServer(value: WorkdayJourney) {server = value;}, intercept(fn: typeof intercept) {intercept = fn;},
    async replaceSession(next: PracticeSession) {session = next; await render();},
    async focus() {await act(async () => {dom.window.dispatchEvent(new dom.window.Event('focus')); await delay(0);});},
    async flush() {await act(async () => {await delay(0);});},
    async close() {await act(async () => {root.unmount();}); dom.window.close(); for (const [key, descriptor] of original) {
      if (descriptor) Object.defineProperty(globalThis, key, descriptor); else Reflect.deleteProperty(globalThis, key);
    }},
  };
}
const first = (state: WorkdaysState) => state.journey!.assignments[0]!;
const evidence = {ids: ['before', 'after']}, handoff = {ids: ['fact-1', 'fact-2']};

test('mounted focus refresh reflects another device completion without any web write', async () => {
  const h = await harness();
  try {assert.equal(first(h.state).step, 0); h.setServer(journey(3)); await h.focus(); assert.equal(h.state.journey!.completedCount, 1);
    assert.equal(h.calls.filter(call => call.method === 'POST').length, 0);
  } finally {await h.close();}
});
test('queued local draft followed by filing uses the acknowledged draft revision once', async () => {
  let completions = 0; const h = await harness(journey(2), async () => {completions++;});
  try {
    const original = first(h.state); let draft!: Promise<boolean>, filed!: Promise<boolean>;
    await act(async () => {draft = h.state.saveDraft(original, 'Keep both periods.'); filed = h.state.saveStep(original, handoff, 'Keep both periods.');
      assert.deepEqual(await Promise.all([draft, filed]), [true, true]); await delay(0);});
    const posts = h.calls.filter(call => call.method === 'POST'); assert.deepEqual(posts.map(call => call.body!['revision']), [2, 3]);
    assert.equal(h.state.journey!.completedCount, 1); assert.equal(h.state.working, false); assert.equal(completions, 1);
  } finally {await h.close();}
});
test('remote revision changes require review instead of silently rebasing an older screen', async () => {
  const h = await harness(journey(2));
  try {
    const original = first(h.state); h.setServer(journey(2, 'Written on mobile.', 3)); await h.focus();
    await act(async () => {assert.equal(await h.state.saveStep(original, handoff), false); await delay(0);});
    assert.ok(h.state.error instanceof PracticeError && h.state.error.code === 'WORK_CHANGED');
    assert.equal(first(h.state).draft, 'Written on mobile.'); assert.equal(h.calls.filter(call => call.method === 'POST').length, 0);
    const reviewed = first(h.state); h.setServer(journey(2, 'Another mobile change.', 4));
    await act(async () => {assert.equal(await h.state.saveStep(reviewed, handoff), false); await delay(0);});
    assert.equal(first(h.state).revision, 4); assert.equal(h.state.pending, null);
  } finally {await h.close();}
});
test('lost final response survives remount and exact recovery confirms once', async () => {
  let completions = 0, lost = false; const h = await harness(journey(2), async () => {completions++;});
  try {
    h.intercept(call => {if (!lost && call.method === 'POST') {lost = true; h.setServer(journey(3, 'Final note.')); throw new Error('Lost response');} return undefined;});
    await act(async () => {assert.equal(await h.state.saveStep(first(h.state), handoff, 'Final note.'), false); await delay(0);});
    assert.equal(h.state.pending?.kind, 'step'); assert.equal(completions, 0);
    await h.replaceSession(h.makeSession());
    await act(async () => {assert.equal(await h.state.recover(), true); await delay(0);});
    const posts = h.calls.filter(call => call.method === 'POST'); assert.deepEqual(posts[0]!.body, posts[1]!.body);
    assert.equal(h.state.pending, null); assert.equal(h.state.journey!.completedCount, 1); assert.equal(completions, 1);
  } finally {await h.close();}
});
test('an aborted older read cannot regress a confirmed stage after its late response arrives', async () => {
  const h = await harness(), oldRead = deferred<Response>(); let held = false;
  try {
    h.intercept(call => {if (!held && call.method === 'GET') {held = true; return oldRead.promise;} return undefined;});
    await h.focus();
    await act(async () => {assert.equal(await h.state.saveStep(first(h.state), evidence), true); await delay(0);});
    await act(async () => {oldRead.resolve(Response.json({journey: journey()})); await delay(0);});
    assert.equal(first(h.state).step, 1); assert.equal(h.state.loading, false);
  } finally {await h.close();}
});
test('identity replacement rejects late writes and drops queued operations from the old account', async () => {
  const save = deferred<Response>(), dispatched = deferred<void>(); let completions = 0;
  const h = await harness(journey(2), async () => {completions++;});
  try {
    h.intercept(call => {if (call.method === 'POST') {dispatched.resolve(); return save.promise;} return undefined;});
    const original = first(h.state); let draft!: Promise<boolean>, file!: Promise<boolean>;
    await act(async () => {draft = h.state.saveDraft(original, 'Old account note.'); file = h.state.saveStep(original, handoff, 'Old account note.'); await dispatched.promise;});
    h.session.close(); h.setServer(journey()); await h.replaceSession(h.makeSession('did:privy:accountB'));
    await act(async () => {save.resolve(Response.json({journey: journey(2, 'Old account note.', 3)}));
      assert.deepEqual(await Promise.all([draft, file]), [false, false]); await delay(0);});
    assert.equal(first(h.state).step, 0); assert.equal(first(h.state).draft, ''); assert.equal(completions, 0);
    assert.equal(h.calls.filter(call => call.method === 'POST').length, 1);
  } finally {await h.close();}
});
test('identity replacement while post-completion refresh waits cannot report an old-account action successful', async () => {
  const refreshing = deferred<void>(), started = deferred<void>();
  const h = await harness(journey(2), async () => {started.resolve(); await refreshing.promise;});
  try {
    let file!: Promise<boolean>;
    await act(async () => {file = h.state.saveStep(first(h.state), handoff); await started.promise;});
    h.session.close(); h.setServer(journey()); await h.replaceSession(h.makeSession('did:privy:accountB'));
    await act(async () => {refreshing.resolve(); assert.equal(await file, false); await delay(0);});
    assert.equal(first(h.state).step, 0);
  } finally {await h.close();}
});

test('an old lifecycle draft reply cannot authorize rebasing a different account remote edit', async () => {
  const save = deferred<Response>(), dispatched = deferred<void>(); const h = await harness(journey(2)); let held = false;
  try {
    h.intercept(call => {if (!held && call.method === 'POST') {held = true; dispatched.resolve(); return save.promise;} return undefined;});
    let oldDraft!: Promise<boolean>;
    await act(async () => {oldDraft = h.state.saveDraft(first(h.state), 'Old account note.'); await dispatched.promise;});
    // The parent may retire a hook before the old session request settles. Its local revision chain still belongs to that lifecycle.
    await h.replaceSession(h.makeSession('did:privy:accountB')); const originalNewAccount = first(h.state);
    h.setServer(journey(2, 'New account mobile edit.', 3)); await h.focus();
    await act(async () => {save.resolve(Response.json({journey: journey(2, 'Old account note.', 3)})); assert.equal(await oldDraft, false); await delay(0);});
    await act(async () => {assert.equal(await h.state.saveStep(originalNewAccount, handoff), false); await delay(0);});
    assert.ok(h.state.error instanceof PracticeError && h.state.error.code === 'WORK_CHANGED');
    assert.equal(first(h.state).draft, 'New account mobile edit.'); assert.equal(h.calls.filter(call => call.method === 'POST').length, 1);
  } finally {await h.close();}
});
