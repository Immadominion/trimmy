import assert from 'node:assert/strict';
import test from 'node:test';
import {act, createElement} from 'react';
import {JSDOM} from 'jsdom';
import {CareerScreen, DailyEntry, DailyStoryScreen} from '../src/product/progress-screens.js';
import {useProgress, type ProgressState} from '../src/product/use-progress.js';
import type {CareerActivityWeek, CareerSummary, DailyDeskCompletion, DailyDeskShift} from '../src/product/practice-client.js';
import type {PracticeSession} from '../src/product/practice-session.js';

const date = '2026-09-24';
const week: CareerActivityWeek = {serverDate: date, weekStart: '2026-09-21', activeDates: ['2026-09-21', '2026-09-22']};
const career: CareerSummary = {revision: 3, trims: {total: 40, today: 0, thisWeek: 40},
  rank: {id: 'rookie', label: 'Rookie', paperLimit: '10000', threshold: 0},
  nextRank: {id: 'analyst', label: 'Analyst', threshold: 60, trimsRemaining: 20, promotionRequired: true},
  streak: {days: 2, status: 'at-risk', lastActiveDate: '2026-09-22'}, careerStarted: true,
  firstConfirmedBuy: null, serverDate: date, updatedAt: '2026-09-22T12:00:00Z'};
function shift(completedChoice: string | null = null): DailyDeskShift {
  const story = {id: 'rumour-at-the-desk', ordinal: 3, title: 'A rumour reaches your desk', speaker: 'sal' as const,
    body: 'Someone says a company is about to announce something big. How do you respond?', choices: [
      {id: 'rush', label: 'Rush into the trade', outcome: 'The price moves before the news arrives.', takeaway: 'A rumour is not a plan.'},
      {id: 'check', label: 'Check the source first', outcome: 'You find the original filing and pause.', takeaway: 'Evidence makes your decision clearer.'},
      {id: 'wait', label: 'Wait for confirmation', outcome: 'You leave room to decide when the facts arrive.', takeaway: 'Waiting is also a decision.'},
    ]};
  const completedAt = completedChoice ? `${date}T12:00:00Z` : null;
  return {date, story, completedChoice, completedAt, trimsEarned: completedChoice ? 10 : 0,
    history: [{date: '2026-09-22', caseId: 'previous-story', title: 'An earlier desk story', choiceId: 'check', completedAt: '2026-09-22T12:00:00Z'},
      ...(completedChoice ? [{date, caseId: story.id, title: story.title, choiceId: completedChoice, completedAt: completedAt!}] : [])]};
}
function deferred<T>() {let resolve!: (value: T) => void; const promise = new Promise<T>(done => {resolve = done;}); return {promise, resolve};}
type SessionPort = Pick<PracticeSession, 'readDailyDesk' | 'readActivityWeek' | 'completeDailyDesk' | 'retryPendingDailyDesk' | 'pendingDailyDesk'>;
function session(overrides: Partial<SessionPort> = {}): SessionPort {
  return {pendingDailyDesk: null, async readDailyDesk() {return shift();}, async readActivityWeek() {return week;},
    async completeDailyDesk(_shift, choice) {return shift(choice);}, async retryPendingDailyDesk() {return shift('check');}, ...overrides};
}
async function harness(port: SessionPort, initial: {enabled?: boolean; page?: string} = {}) {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {url: 'https://trimmy.example/#daily', pretendToBeVisual: true});
  const previous = new Map<string, PropertyDescriptor | undefined>();
  for (const [key, value] of Object.entries({window: dom.window, document: dom.window.document,
    navigator: dom.window.navigator, HTMLElement: dom.window.HTMLElement, IS_REACT_ACT_ENVIRONMENT: true})) {
    previous.set(key, Object.getOwnPropertyDescriptor(globalThis, key));
    Object.defineProperty(globalThis, key, {configurable: true, writable: true, value});
  }
  const {createRoot} = await import('react-dom/client');
  const root = createRoot(dom.window.document.getElementById('root')!);
  let latest!: ProgressState, completed = 0, back = 0;
  const onCompleted = async () => {completed++;};
  const onBack = () => {back++;};
  let props = {enabled: true, page: 'daily', ...initial};
  function View({enabled, page}: typeof props) {
    latest = useProgress(port as PracticeSession, enabled, page, onCompleted);
    if (page === 'career') return createElement(CareerScreen, {career, missions: null, progress: latest, error: null,
      onRetry() {}, onMarket() {}, onDaily() {}});
    if (page === 'desk') return createElement(DailyEntry, {progress: latest, onOpen() {}});
    return createElement(DailyStoryScreen, {progress: latest, onBack});
  }
  const render = async (update: Partial<typeof props> = {}) => {props = {...props, ...update}; await act(async () => {root.render(createElement(View, props));});};
  const button = (label: string) => [...dom.window.document.querySelectorAll<HTMLButtonElement>('button')].find(value => value.textContent?.trim() === label);
  const click = async (label: string) => {const target = button(label); assert.ok(target, `Button exists: ${label}`); await act(async () => {target.click();});};
  const choose = async (choice: string) => {const radio = dom.window.document.querySelector<HTMLInputElement>(`input[value="${choice}"]`); assert.ok(radio); await act(async () => {radio.click();});};
  const focus = async () => {await act(async () => {dom.window.dispatchEvent(new dom.window.Event('focus'));});};
  const close = async () => {await act(async () => {root.unmount();}); dom.window.close();
    for (const [key, descriptor] of previous) {if (descriptor) Object.defineProperty(globalThis, key, descriptor); else Reflect.deleteProperty(globalThis, key);}};
  await render();
  return {dom, render, button, click, choose, focus, close, progress: () => latest,
    completions: () => completed, backs: () => back, text: () => dom.window.document.body.textContent ?? ''};
}

test('returning to the web reads a mobile-completed story and displays its exact saved response without another clock-out', async () => {
  let saved = shift(), reads = 0, writes = 0;
  const h = await harness(session({async readDailyDesk() {reads++; return saved;}, async completeDailyDesk(_shift, choice) {writes++; return shift(choice);}}));
  try {
    assert.equal(reads, 1); assert.equal(h.dom.window.document.querySelectorAll('input[type="radio"]').length, 3);
    await h.choose('rush'); // A local draft must not override the decision saved on mobile.
    saved = shift('wait'); await h.focus();
    assert.equal(reads, 2); assert.match(h.text(), /Your saved response/);
    assert.equal(h.dom.window.document.querySelector('.daily-outcome h2')?.textContent, 'Wait for confirmation');
    assert.match(h.text(), /Waiting is also a decision/); assert.match(h.text(), /Day completed · 10 Trims earned/);
    assert.equal(h.dom.window.document.querySelector('input[type="radio"]'), null);
    assert.equal(h.button('Clock out'), undefined); assert.equal(h.button('Check clock-out'), undefined);
    assert.equal(writes, 0); assert.equal(h.completions(), 0);
    await h.render({page: 'desk'}); assert.equal(h.dom.window.document.querySelector('.daily-entry'), null);
  } finally {await h.close();}
});

test('an older uncompleted response cannot overwrite a newer focused refresh that confirms the day', async () => {
  const first = deferred<DailyDeskShift>(), second = deferred<DailyDeskShift>();
  const signals: (AbortSignal | undefined)[] = [];
  const h = await harness(session({async readDailyDesk(signal) {signals.push(signal); return signals.length === 1 ? first.promise : second.promise;}}));
  try {
    await h.focus(); assert.equal(signals.length, 2); assert.equal(signals[0]?.aborted, true);
    await act(async () => {second.resolve(shift('check'));});
    assert.match(h.text(), /Your saved response/);
    await act(async () => {first.resolve(shift());});
    assert.equal(h.progress().shift?.completedChoice, 'check');
    assert.equal(h.dom.window.document.querySelector('.daily-outcome h2')?.textContent, 'Check the source first');
    assert.equal(h.button('Clock out'), undefined);
  } finally {await h.close();}
});

test('disabling account progress clears saved state and ignores its late response', async () => {
  const response = deferred<DailyDeskShift>();
  const h = await harness(session({async readDailyDesk() {return response.promise;}}));
  try {
    await h.render({enabled: false});
    await act(async () => {response.resolve(shift('check'));});
    assert.equal(h.progress().shift, null); assert.equal(h.progress().week, null);
    assert.doesNotMatch(h.text(), /Your saved response|Day completed/);
  } finally {await h.close();}
});

test('Career distinguishes a trade-active day from a completed desk story', async () => {
  const h = await harness(session(), {page: 'career'});
  try {
    const days = [...h.dom.window.document.querySelectorAll('.desk-day')];
    const monday = days.find(item => item.getAttribute('aria-label')?.startsWith('Monday 21'));
    const tuesday = days.find(item => item.getAttribute('aria-label')?.startsWith('Tuesday 22'));
    assert.ok(monday); assert.ok(tuesday);
    assert.match(monday.getAttribute('aria-label')!, /no desk story completed/); assert.equal(monday.querySelector('.completion-seal'), null);
    assert.match(tuesday.getAttribute('aria-label')!, /desk story completed/); assert.ok(tuesday.querySelector('.completion-seal'));
    const mondayActivity = h.dom.window.document.querySelector('.activity-week > span[title="2026-09-21: Active"]');
    assert.ok(mondayActivity?.classList.contains('active'));
    assert.equal(h.dom.window.document.querySelectorAll('.desk-week-days .completion-seal').length, 1);
    assert.match(h.dom.window.document.querySelector('.activity-week')!.getAttribute('aria-label')!, /trade, comment or desk story/);
  } finally {await h.close();}
});

test('response preview does not write progress and only confirmed clock-out shows a completion seal', async () => {
  const response = deferred<DailyDeskShift>(); let saved = shift(), writes = 0;
  const h = await harness(session({async readDailyDesk() {return saved;}, async completeDailyDesk(original, choice) {
    assert.equal(original.story.id, saved.story.id); assert.equal(choice, 'check'); writes++; return response.promise;
  }}));
  try {
    assert.equal(h.button('See what happens')?.disabled, true);
    await h.choose('check'); await h.click('See what happens');
    assert.equal(writes, 0); assert.match(h.text(), /You find the original filing and pause/);
    assert.equal(h.dom.window.document.querySelector('.daily-saved'), null);
    await h.click('Clock out'); assert.equal(writes, 1); assert.equal(h.button('Saving…')?.disabled, true);
    assert.equal(h.button('← Back to my desk')?.disabled, true); assert.equal(h.dom.window.document.querySelector('.daily-saved'), null);
    saved = shift('check'); await act(async () => {response.resolve(saved);});
    assert.equal(h.completions(), 1); assert.match(h.text(), /Day completed · 10 Trims earned/);
    await h.click('Back to my desk'); assert.equal(h.backs(), 1);
  } finally {await h.close();}
});

test('an interrupted clock-out retains its selected response and retry confirms it without another choice or duplicate write', async () => {
  let pending: DailyDeskCompletion | null = null, saved = shift(), writes = 0, retries = 0;
  const response = deferred<DailyDeskShift>();
  const port: SessionPort = {get pendingDailyDesk() {return pending;}, async readDailyDesk() {return saved;}, async readActivityWeek() {return week;},
    async completeDailyDesk(original, choiceId) {writes++; pending = {date: original.date, caseId: original.story.id, choiceId}; throw new Error('connection lost');},
    async retryPendingDailyDesk() {retries++; assert.deepEqual(pending, {date, caseId: 'rumour-at-the-desk', choiceId: 'wait'});
      const result = await response.promise; pending = null; return result;}};
  const h = await harness(port);
  try {
    await h.choose('wait'); await h.click('See what happens'); await h.click('Clock out');
    assert.equal(writes, 1); assert.equal(h.dom.window.document.querySelector('.daily-outcome h2')?.textContent, 'Wait for confirmation');
    assert.equal(h.dom.window.document.querySelector('input[type="radio"]'), null);
    assert.equal(h.button('Change response'), undefined); assert.equal(h.button('Clock out'), undefined); assert.ok(h.button('Check clock-out'));
    assert.equal(h.dom.window.document.querySelector('.daily-saved'), null);
    const retry = h.button('Check clock-out')!;
    await act(async () => {retry.click(); retry.click();});
    assert.equal(retries, 1); assert.equal(h.button('Checking…')?.disabled, true);
    saved = shift('wait'); await act(async () => {response.resolve(saved);});
    assert.equal(writes, 1); assert.equal(retries, 1); assert.equal(h.completions(), 1);
    assert.equal(h.progress().pending, null); assert.match(h.text(), /Your saved response/);
    assert.match(h.text(), /Day completed · 10 Trims earned/);
  } finally {await h.close();}
});

test('a completed GET after a lost clock-out response keeps recovery accessible until the durable command is settled', async () => {
  let pending: DailyDeskCompletion | null = null, saved = shift(), writes = 0, retries = 0;
  const recovery = deferred<DailyDeskShift>();
  const port: SessionPort = {get pendingDailyDesk() {return pending;}, async readDailyDesk() {return saved;}, async readActivityWeek() {return week;},
    async completeDailyDesk(original, choiceId) {
      writes++; pending = {date: original.date, caseId: original.story.id, choiceId};
      saved = shift(choiceId); // The server committed, but this browser did not receive its response.
      throw new Error('response lost');
    },
    async retryPendingDailyDesk() {
      retries++; assert.deepEqual(pending, {date, caseId: 'rumour-at-the-desk', choiceId: 'wait'});
      const result = await recovery.promise; pending = null; return result;
    }};
  const h = await harness(port);
  try {
    await h.choose('wait'); await h.click('See what happens'); await h.click('Clock out');
    assert.equal(writes, 1); assert.equal(h.completions(), 0);
    assert.equal(h.progress().shift?.completedChoice, 'wait'); assert.ok(h.progress().pending);
    assert.match(h.text(), /Your saved response/); assert.match(h.text(), /Day completed · 10 Trims earned/);
    assert.equal(h.button('Clock out'), undefined); assert.equal(h.button('Change response'), undefined);
    assert.ok(h.button('Check clock-out'), 'Confirmed GET must not hide the unresolved journal recovery');
    await h.click('Check clock-out');
    assert.equal(retries, 1); assert.equal(h.button('Checking…')?.disabled, true);
    await h.click('Checking…'); assert.equal(retries, 1);
    await act(async () => {recovery.resolve(saved);});
    assert.equal(h.progress().pending, null); assert.equal(writes, 1); assert.equal(h.completions(), 1);
    assert.equal(h.button('Check clock-out'), undefined); assert.ok(h.button('Back to my desk'));
    assert.match(h.text(), /Day completed · 10 Trims earned/);
    await h.click('Back to my desk'); assert.equal(h.backs(), 1);
  } finally {await h.close();}
});
