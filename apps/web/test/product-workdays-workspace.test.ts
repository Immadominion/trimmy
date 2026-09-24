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
  const calls: Call[] = [], storage = new Store(); let state = options.initial ?? journey();
  const account: ProductAccountAccess = {subject: 'did:privy:workdayWorkspace', accountId: '22222222-2222-4222-8222-222222222222',
    signal: new AbortController().signal, freshAccessToken: async () => 'test.account.proof'};
  const fetcher: typeof fetch = async (input, init = {}) => {
    const call: Call = {path: new URL(String(input), 'https://trimmy.example').pathname.replace(/^\/api/, ''), method: init.method ?? 'GET',
      body: init.body ? JSON.parse(String(init.body)) as Record<string, unknown> : null, headers: new Headers(init.headers)};
    calls.push(call);
    if (call.path === '/v1/career/workdays') return json({journey: state});
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
