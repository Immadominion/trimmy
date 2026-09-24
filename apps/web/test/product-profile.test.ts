import assert from 'node:assert/strict';
import test from 'node:test';
import {act, createElement} from 'react';
import {JSDOM} from 'jsdom';
import {WebProfile, type WebProfileProps, type TraderPersona} from '../src/product/web-profile.js';
import type {CareerMissionBoard, CareerSummary, ProductProfile} from '../src/product/practice-client.js';

const profile: ProductProfile = {revision: 2,
  onboarding: {goal: null, knowledge: null, persona: 'oracle', dailyGoal: null, handle: 'ada'},
  launchCheckpoint: 'app', hasConfirmedPaperTrade: true, createdAt: '2026-09-24T10:00:00Z', updatedAt: '2026-09-24T10:00:00Z'};
const career: CareerSummary = {revision: 3, trims: {total: 40, today: 10, thisWeek: 40},
  rank: {id: 'rookie', label: 'Rookie', paperLimit: '10000', threshold: 0},
  nextRank: {id: 'analyst', label: 'Analyst', threshold: 60, trimsRemaining: 20, promotionRequired: true},
  streak: {days: 3, status: 'active', lastActiveDate: '2026-09-24'}, careerStarted: true, firstConfirmedBuy: null,
  serverDate: '2026-09-24', updatedAt: '2026-09-24T10:00:00Z'};
const missions: CareerMissionBoard = {revision: 2, currentRank: 'rookie', missions: [
  {id: 'first-paper-buy', chapterRank: 'rookie', order: 1, kind: 'action', title: 'First paper buy', instruction: 'Pick a company.',
    trimsReward: 20, promotesToRank: null, status: 'complete', completedAt: '2026-09-24T10:00:00Z'},
  {id: 'write-a-reason', chapterRank: 'rookie', order: 2, kind: 'action', title: 'Write a reason', instruction: 'Write down your thinking.',
    trimsReward: 20, promotesToRank: null, status: 'ready', completedAt: null},
]};

async function harness(initial: Partial<WebProfileProps> = {}) {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {url: 'https://trimmy.example/#profile'});
  const previous = new Map<string, PropertyDescriptor | undefined>();
  for (const [key, value] of Object.entries({window: dom.window, document: dom.window.document,
    navigator: dom.window.navigator, HTMLElement: dom.window.HTMLElement, IS_REACT_ACT_ENVIRONMENT: true})) {
    previous.set(key, Object.getOwnPropertyDescriptor(globalThis, key)); Object.defineProperty(globalThis, key, {configurable: true, writable: true, value});
  }
  const {createRoot} = await import('react-dom/client');
  const root = createRoot(dom.window.document.getElementById('root')!);
  const calls = {career: 0, signIn: 0, signOut: 0, retry: 0, motion: [] as boolean[], persona: [] as TraderPersona[]};
  let props: WebProfileProps = {profile, career, missions, hasIdentity: true, signedIn: true, motion: true,
    onMotion: value => {calls.motion.push(value);}, onCareer: () => {calls.career++;},
    onSignIn: () => {calls.signIn++;}, onSignOut: () => {calls.signOut++;}, onRetry: () => {calls.retry++;},
    onPersona: async value => {calls.persona.push(value);}, ...initial};
  const render = async (update: Partial<WebProfileProps> = {}) => {props = {...props, ...update}; await act(async () => {root.render(createElement(WebProfile, props));});};
  const button = (label: string) => [...dom.window.document.querySelectorAll<HTMLButtonElement>('button')].find(item => item.textContent?.trim() === label);
  const click = async (label: string) => {const target = button(label); assert.ok(target, `Button exists: ${label}`); await act(async () => {target.click();});};
  const choose = async (value: TraderPersona) => {const radio = dom.window.document.querySelector<HTMLInputElement>(`input[value="${value}"]`); assert.ok(radio); await act(async () => {radio.click();});};
  const close = async () => {await act(async () => {root.unmount();}); dom.window.close();
    for (const [key, descriptor] of previous) {if (descriptor) Object.defineProperty(globalThis, key, descriptor); else Reflect.deleteProperty(globalThis, key);}};
  await render();
  return {dom, calls, render, click, choose, button, close, text: () => dom.window.document.body.textContent ?? ''};
}

test('profile shows the chosen mobile trader and actual career values, and refresh replaces them', async () => {
  const h = await harness();
  try {
    assert.equal(h.dom.window.document.querySelector('.web-profile-name h2')?.textContent, '@ada');
    assert.match(h.dom.window.document.querySelector('.web-profile-avatar img')!.getAttribute('src')!, /persona-oracle-avatar-v1/);
    assert.deepEqual([...h.dom.window.document.querySelectorAll('.web-profile-stats dd')].map(item => item.textContent), ['40', '3', '1 / 2']);
    assert.match(h.text(), /20 more Trims to Analyst/);
    await h.render({career: {...career, trims: {...career.trims, total: 50}, streak: {...career.streak, days: 4}}});
    assert.deepEqual([...h.dom.window.document.querySelectorAll('.web-profile-stats dd')].map(item => item.textContent), ['50', '4', '1 / 2']);
    await h.click('Career →'); assert.equal(h.calls.career, 1);
  } finally {await h.close();}
});

test('missing persona and progress do not create a Wolf, rank, zero balance or zero Trims', async () => {
  const h = await harness({profile: {...profile, onboarding: {...profile.onboarding, persona: null, handle: null}}, career: null, missions: null, signedIn: false});
  try {
    assert.equal(h.dom.window.document.querySelector('.web-profile-avatar.chosen'), null);
    assert.equal(h.dom.window.document.querySelector('.web-profile-stats'), null);
    assert.equal(h.dom.window.document.querySelector('.web-profile-rank'), null);
    assert.match(h.text(), /Your progress is unavailable/); assert.ok(h.button('Choose your trader'));
    await h.click('Try again'); assert.equal(h.calls.retry, 1);
    await h.click('Sign in or create account'); assert.equal(h.calls.signIn, 1);
    assert.equal(h.button('Sign out'), undefined);
  } finally {await h.close();}
});

test('failed persona saves preserve the selected draft and leave the saved avatar unchanged for exact retry', async () => {
  let attempts = 0;
  const chosen: TraderPersona[] = [];
  const h = await harness({onPersona: async persona => {chosen.push(persona); if (++attempts === 1) throw new Error('Offline');}});
  try {
    await h.click('Change your trader'); await h.choose('shark'); await h.click('Save trader');
    assert.match(h.text(), /Couldn’t save your trader/);
    assert.equal(h.dom.window.document.querySelector<HTMLInputElement>('input[value="shark"]')?.checked, true);
    assert.match(h.dom.window.document.querySelector('.web-profile-avatar img')!.getAttribute('src')!, /persona-oracle-avatar-v1/);
    await h.click('Save trader'); assert.deepEqual(chosen, ['shark', 'shark']);
    assert.equal(h.dom.window.document.querySelector('.web-profile-persona-editor'), null);
  } finally {await h.close();}
});

test('persona save disables repeat submission and cancel while awaiting server confirmation', async () => {
  let finish!: () => void;
  let saves = 0;
  const h = await harness({onPersona: () => {saves++; return new Promise(resolve => {finish = resolve;});}});
  try {
    await h.click('Change your trader'); await h.choose('wolf'); await h.click('Save trader');
    assert.equal(h.button('Saving…')?.disabled, true); assert.equal(h.button('Cancel')?.disabled, true);
    assert.equal(h.dom.window.document.querySelector<HTMLFieldSetElement>('fieldset')?.disabled, true);
    await h.click('Saving…'); assert.equal(saves, 1);
    assert.match(h.dom.window.document.querySelector('.web-profile-avatar img')!.getAttribute('src')!, /persona-oracle-avatar-v1/);
    await act(async () => {finish();});
    assert.equal(h.dom.window.document.querySelector('.web-profile-persona-editor'), null);
  } finally {await h.close();}
});

test('cancel does not write a persona, motion uses the supplied preference action and sign out uses the real callback', async () => {
  const h = await harness();
  try {
    await h.click('Change your trader'); await h.choose('wolf'); await h.click('Cancel');
    assert.deepEqual(h.calls.persona, []);
    await act(async () => {h.dom.window.document.querySelector<HTMLInputElement>('[role="switch"]')!.click();});
    assert.deepEqual(h.calls.motion, [false]);
    await h.click('Sign out'); assert.equal(h.calls.signOut, 1);
  } finally {await h.close();}
});

test('stale career retains its last server values with a retry instead of showing a fabricated empty record', async () => {
  const h = await harness({progressError: true});
  try {
    assert.match(h.text(), /Progress couldn’t refresh/);
    assert.equal(h.dom.window.document.querySelector('.web-profile-stats dd')?.textContent, '40');
    await h.click('Retry'); assert.equal(h.calls.retry, 1);
  } finally {await h.close();}
});
