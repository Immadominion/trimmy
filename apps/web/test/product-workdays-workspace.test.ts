import assert from 'node:assert/strict';
import test from 'node:test';
import {webcrypto} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {setTimeout as delay} from 'node:timers/promises';
import {act, createElement} from 'react';
import {JSDOM} from 'jsdom';
import {ProductApp} from '../src/product/ProductApp.js';
import {ProductMarketClient} from '../src/product/market-client.js';
import {PracticeClient, PORTFOLIO_MEDIA_TYPE, PROFILE_MEDIA_TYPE, parseWorkdayJourney} from '../src/product/practice-client.js';
import type {WorkdayJourney} from '../src/product/practice-client.js';
import type {ProductAccountAccess} from '../src/product/product-auth.js';
import type {PracticeStorage} from '../src/product/practice-session.js';

const content = JSON.parse(readFileSync(new URL('../../../content/workdays/intern-v1.json', import.meta.url), 'utf8'));
const AT = '2026-09-24T20:00:00.000Z';
function journey(step = 0, draft = '', revision = step): WorkdayJourney {
  return parseWorkdayJourney({contentVersion: content.contentVersion, date: '2026-09-24', completedCount: 0,
    assignments: content.assignments.map((definition: Record<string, any>, index: number) => {
      const {context: _context, feedback: _feedback, ...rest} = definition;
      const {requiredIds: evidenceIds, ...evidence} = definition.evidence;
      const {requiredIds: fileIds, ...file} = definition.file;
      const {acceptedAnswers: _accepted, ...decision} = definition.decision;
      const currentStep = index === 0 ? step : 0;
      return {...rest, evidence: {...evidence, count: evidenceIds.length}, decision, file: {...file, count: fileIds.length},
        revision: index === 0 ? revision : 0, step: currentStep,
        answers: {...(currentStep > 0 ? {'0': {ids: [...evidenceIds].sort()}} : {}), ...(currentStep > 1 ? {'1': {value: '200'}} : {})},
        draft: index === 0 ? draft : '', completedAt: null, artifact: null, feedback: null, contextNote: null};
    })});
}
/** Saturday after filing day 1: no workday opens until Monday. */
function weekendJourney(): WorkdayJourney {
  const [first, second] = content.assignments as Record<string, any>[];
  const {context: _context, feedback: _feedback, ...rest} = first!;
  const {requiredIds: evidenceIds, ...evidence} = first!.evidence;
  const {requiredIds: fileIds, ...file} = first!.file;
  const {acceptedAnswers, ...decision} = first!.decision;
  const opensAt = '2026-09-28T04:00:00.000Z';
  return parseWorkdayJourney({contentVersion: content.contentVersion, date: '2026-09-26', completedCount: 1, total: 20,
    assignments: [{...rest, evidence: {...evidence, count: evidenceIds.length}, decision, file: {...file, count: fileIds.length},
      revision: 3, step: 3, answers: {'0': {ids: [...evidenceIds].sort()}, '1': {value: String(acceptedAnswers[0])}, '2': {ids: [...fileIds].sort()}},
      draft: '', completedAt: AT, artifact: 'Filed note.', feedback: 'Good work.', contextNote: null, trims: 20}],
    schedule: {today: '2026-09-26', deskOpen: false, holiday: null, state: 'closed', opensAt},
    upcoming: {id: second!.id, ordinal: 2, title: second!.title, speaker: second!.speaker, district: second!.district, art: second!.art, opensAt}});
}
const STORY = {id: 'the-weekend-note', ordinal: 6, title: 'A quieter desk.', speaker: 'sal', body: 'No rush today.',
  choices: ['company', 'risk', 'journal'].map(id => ({id, label: `Label ${id}`, outcome: `Outcome ${id}.`, takeaway: `Takeaway ${id}.`}))};
const storyShift = (done: boolean) => ({date: '2026-09-26', story: STORY, completedChoice: done ? 'risk' : null, completedAt: done ? AT : null,
  trimsEarned: done ? 10 : 0, history: done ? [{date: '2026-09-26', caseId: STORY.id, title: STORY.title, choiceId: 'risk', completedAt: AT}] : []});
class Store implements PracticeStorage {
  values = new Map<string, string>();
  getItem(key: string) {return this.values.get(key) ?? null;}
  setItem(key: string, value: string) {this.values.set(key, value);}
}
interface Call {path: string; method: string; body: Record<string, unknown> | null; headers: Headers}
const json = (value: unknown, status = 200, media = 'application/json') => Response.json(value, {status, headers: {'content-type': media}});
function deferred<T>() {let resolve!: (value: T) => void; const promise = new Promise<T>(done => {resolve = done;}); return {promise, resolve};}

async function harness(options: {hash?: string; initial?: WorkdayJourney; draftReply?: (call: Call) => Promise<Response> | Response} = {}) {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {url: `https://trimmy.example/${options.hash ?? '#career'}`, pretendToBeVisual: true});
  const previous = new Map<string, PropertyDescriptor | undefined>();
  for (const [key, value] of Object.entries({window: dom.window, document: dom.window.document, navigator: dom.window.navigator,
    HTMLElement: dom.window.HTMLElement, Event: dom.window.Event, localStorage: dom.window.localStorage,
    crypto: webcrypto, IS_REACT_ACT_ENVIRONMENT: true})) {
    previous.set(key, Object.getOwnPropertyDescriptor(globalThis, key)); Object.defineProperty(globalThis, key, {configurable: true, writable: true, value});
  }
  dom.window.localStorage.setItem('trimmy.web.workSound', 'off');
  Object.defineProperty(dom.window, 'matchMedia', {value: () => ({matches: true, addEventListener() {}, removeEventListener() {}})});
  Object.defineProperty(dom.window.navigator, 'locks', {value: {request: async (_key: string, _options: unknown, callback: () => Promise<unknown>) => callback()}});
  const calls: Call[] = [], storage = new Store(); let state = options.initial ?? journey(); let storyDone = false;
  const account: ProductAccountAccess = {subject: 'did:privy:workdayWorkspace', accountId: '22222222-2222-4222-8222-222222222222',
    signal: new AbortController().signal, freshAccessToken: async () => 'test.account.proof'};
  const fetcher: typeof fetch = async (input, init = {}) => {
    const call: Call = {path: new URL(String(input), 'https://trimmy.example').pathname.replace(/^\/api/, ''), method: init.method ?? 'GET',
      body: init.body ? JSON.parse(String(init.body)) as Record<string, unknown> : null, headers: new Headers(init.headers)};
    calls.push(call);
    if (call.path === '/v1/career/workdays') return json({journey: state});
    if (call.path === '/v1/career/daily-desk') return json({shift: storyShift(storyDone)});
    if (call.path === '/v1/career/daily-desk/complete') {storyDone = true; return json({shift: storyShift(true)});}
    if (call.path === '/v1/career/workdays/draft') {
      if (options.draftReply) return options.draftReply(call);
      state = journey(2, String(call.body?.['draft']), Number(call.body?.['revision']) + 1); return json({journey: state});
    }
    if (call.path === '/v1/product/profile') return json({schemaVersion: 2, profile: {revision: 1,
      onboarding: {goal: null, knowledge: null, persona: null, dailyGoal: null, handle: 'tester'}, launchCheckpoint: 'app',
      hasConfirmedPaperTrade: false, createdAt: AT, updatedAt: AT}}, 200, PROFILE_MEDIA_TYPE);
    if (call.path === '/v1/account/paper/portfolio') return json({schemaVersion: 2, mode: 'paper', unit: {kind: 'paper', scaleDigits: 6}, revision: 0,
      startingCashPaperMicros: '10000000000', cashPaperMicros: '10000000000', openedAt: null, updatedAt: null, positions: [], recentOrders: [],
      valuation: {status: 'complete', portfolioRevision: 0, openPositionCount: 0, pricedPositionCount: 0, cashPaperMicros: '10000000000',
        knownValuePaperMicros: '10000000000', totalPaperMicros: '10000000000', positions: []}}, 200, PORTFOLIO_MEDIA_TYPE);
    if (call.path === '/v1/career/summary') return json({schemaVersion: 1, career: {revision: 0, trims: {total: 0, today: 0, thisWeek: 0},
      rank: {id: 'rookie', label: 'Rookie', paperLimit: '10000', threshold: 0}, nextRank: {id: 'analyst', label: 'Analyst', threshold: 300, trimsRemaining: 300, promotionRequired: true},
      streak: {days: 0, status: 'not-started', lastActiveDate: null}, careerStarted: false, firstConfirmedBuy: null, serverDate: '2026-09-24', updatedAt: null}});
    if (call.path === '/v1/career/missions') return json({schemaVersion: 1, career: {revision: 0, currentRank: 'rookie'}, missions: []});
    if (call.path === '/v1/career/activity-week') return json({schemaVersion: 1, activityWeek: {serverDate: '2026-09-24', weekStart: '2026-09-21', activeDates: []}});
    throw new Error(`Unexpected request: ${call.method} ${call.path}`);
  };
  const client = new PracticeClient({baseUrl: '/api', fetch: fetcher, timeoutMs: 1000});
  const market = new ProductMarketClient({baseUrl: '/api', fetch: fetcher, timeoutMs: 1000});
  const {createRoot} = await import('react-dom/client'); const root = createRoot(dom.window.document.getElementById('root')!);
  const flush = async () => {await act(async () => {await delay(20);});};
  const app = async () => {await act(async () => {root.render(createElement(ProductApp, {apiBase: '/api', practiceClient: client,
    marketClient: market, storage, accountAccess: account, authConfig: {kind: 'disabled'}}));}); await flush();};
  const button = (label: string) => [...dom.window.document.querySelectorAll<HTMLButtonElement>('button')].find(item => item.textContent?.trim() === label || item.getAttribute('aria-label') === label);
  const click = async (label: string) => {const target = button(label); assert.ok(target, `Button exists: ${label}`); await act(async () => {target.click();}); await flush();};
  const inputNote = async (value: string) => {const textarea = dom.window.document.querySelector<HTMLTextAreaElement>('.workday-note textarea'); assert.ok(textarea);
    await act(async () => {Object.getOwnPropertyDescriptor(dom.window.HTMLTextAreaElement.prototype, 'value')!.set!.call(textarea, value); textarea.dispatchEvent(new dom.window.Event('input', {bubbles: true}));});};
  const route = async (hash: string) => {await act(async () => {dom.window.history.pushState(null, '', hash); dom.window.dispatchEvent(new dom.window.HashChangeEvent('hashchange'));}); await flush();};
  const close = async () => {await act(async () => {root.unmount();}); market.close(); dom.window.close();
    for (const [key, descriptor] of previous) {if (descriptor) Object.defineProperty(globalThis, key, descriptor); else Reflect.deleteProperty(globalThis, key);}};
  await app();
  return {dom, calls, flush, click, inputNote, route, close, setJourney(value: WorkdayJourney) {state = value;}, text: () => dom.window.document.body.textContent ?? ''};
}

test('the actual Career route reads the shared workday journey and retires new daily-story entries', async () => {
  const h = await harness();
  try {
    assert.ok(h.calls.some(call => call.path === '/v1/career/workdays' && call.method === 'GET'));
    assert.equal(h.calls.some(call => call.path.startsWith('/v1/career/daily-desk')), false);
    assert.equal(h.dom.window.document.querySelectorAll('[data-assignment-id]').length, 20);
    assert.ok(h.dom.window.document.querySelector('.career-world-scroll'));
    assert.doesNotMatch(h.text(), /Step inside|Clock out|Review today/);
    await h.click('Desk'); assert.ok(h.dom.window.document.querySelector('.workday-entry'));
    assert.match(h.text(), /Start assignment/); assert.doesNotMatch(h.text(), /Step inside|Clock out/);
    await h.route('#daily'); assert.ok(h.dom.window.document.querySelector('.career-world-scroll'));
    assert.equal(h.dom.window.document.querySelector('.daily-story-screen'), null);
    assert.equal(h.calls.some(call => call.path.startsWith('/v1/career/daily-desk')), false);
    assert.equal(h.calls.some(call => call.method !== 'GET'), false);
    assert.ok(h.calls.filter(call => call.path === '/v1/career/workdays').every(call => call.headers.get('authorization') === 'Bearer test.account.proof'));
  } finally {await h.close();}
});

test('a day with no workday offers the short desk story on Career, and saving it hides the offer', async () => {
  const h = await harness({initial: weekendJourney()});
  try {
    const doc = h.dom.window.document;
    assert.match(h.text(), /No workday today\. A short story instead\./);
    assert.match(h.text(), /A quieter desk\./);
    assert.ok(h.calls.some(call => call.path === '/v1/career/daily-desk' && call.method === 'GET'));
    const open = doc.querySelector<HTMLButtonElement>('.daily-entry .text-button');
    assert.match(open?.textContent ?? '', /Step inside/);
    await act(async () => {open!.click();}); await h.flush();
    assert.ok(doc.querySelector('.daily-story-screen'), 'the story opens');
    const choice = doc.querySelector<HTMLInputElement>('.daily-story-screen input[value="risk"]');
    assert.ok(choice, 'the three choices are shown');
    await act(async () => {choice.click();}); await h.flush();
    await h.click('See what happens'); await h.click('Clock out');
    const saved = h.calls.find(call => call.path === '/v1/career/daily-desk/complete');
    assert.deepEqual(saved?.body, {date: '2026-09-26', caseId: 'the-weekend-note', choiceId: 'risk'});
    assert.match(h.text(), /Day completed · 10 Trims earned/);
    await h.click('Back to my desk');
    assert.doesNotMatch(h.text(), /No workday today/, 'a finished story is not offered again');
  } finally {await h.close();}
});

test('a shared assignment URL resumes the exact server stage and mobile note, while locked or missing IDs do not open another day', async () => {
  const h = await harness({hash: '#work/morning-brief', initial: journey(2, 'Saved on my phone.', 5)});
  try {
    assert.equal(h.dom.window.location.hash, '#work/morning-brief');
    assert.equal(h.dom.window.document.querySelector<HTMLTextAreaElement>('.workday-note textarea')?.value, 'Saved on my phone.');
    assert.match(h.dom.window.document.querySelector('.workday-stages [aria-current="step"]')!.textContent!, /Handoff/);
    assert.equal(h.dom.window.document.querySelectorAll('.workday-stages li.complete').length, 2);
    assert.equal(h.calls.some(call => call.method !== 'GET'), false);
    await h.route(`#work/${content.assignments[1].id}`);
    assert.equal(h.dom.window.document.querySelector('.workday-screen'), null); assert.match(h.text(), /File day 1 to open this assignment/);
    await h.route('#work/missing-assignment'); assert.match(h.text(), /Your assignment couldn’t open/);
    assert.equal(h.dom.window.document.querySelector('.workday-note'), null);
  } finally {await h.close();}
});

test('sidebar navigation waits for the exact dirty note to save before leaving the assignment', async () => {
  const response = deferred<Response>();
  const h = await harness({hash: '#work/morning-brief', initial: journey(2, 'Earlier mobile note.', 5), draftReply: () => response.promise});
  try {
    await h.inputNote('Keep this updated note.'); await h.click('Desk');
    assert.equal(h.dom.window.location.hash, '#work/morning-brief'); assert.ok(h.dom.window.document.querySelector('.workday-note'));
    const writes = h.calls.filter(call => call.path === '/v1/career/workdays/draft');
    assert.equal(writes.length, 1); assert.deepEqual(writes[0]!.body, {assignmentId: 'morning-brief', revision: 5, draft: 'Keep this updated note.'});
    const saved = journey(2, 'Keep this updated note.', 6); h.setJourney(saved); response.resolve(json({journey: saved})); await h.flush();
    assert.equal(h.dom.window.location.hash, '#desk'); assert.equal(h.dom.window.document.querySelector('.workday-note'), null);
    await h.click('Continue assignment');
    assert.equal(h.dom.window.location.hash, '#work/morning-brief');
    assert.equal(h.dom.window.document.querySelector<HTMLTextAreaElement>('.workday-note textarea')?.value, 'Keep this updated note.');
  } finally {response.resolve(json({journey: journey(2, 'Keep this updated note.', 6)})); await h.close();}
});

test('a failed note save keeps sidebar navigation on the assignment until the user explicitly chooses to leave', async () => {
  const h = await harness({hash: '#work/morning-brief', initial: journey(2, 'Saved note.', 5), draftReply: () => json({code: 'INVALID_WORK'}, 400)});
  try {
    await h.inputNote('Unsaved details.'); await h.click('Desk');
    assert.equal(h.dom.window.location.hash, '#work/morning-brief'); assert.ok(h.dom.window.document.querySelector('[role="alertdialog"]'));
    await h.click('Keep writing');
    assert.equal(h.dom.window.document.querySelector<HTMLTextAreaElement>('.workday-note textarea')?.value, 'Unsaved details.');
    assert.equal(h.dom.window.location.hash, '#work/morning-brief');
    await h.click('Desk'); await h.click('Leave without saving');
    assert.equal(h.dom.window.location.hash, '#desk');
    assert.equal(h.calls.some(call => call.path.endsWith('/step') || call.path.endsWith('/complete')), false);
  } finally {await h.close();}
});
