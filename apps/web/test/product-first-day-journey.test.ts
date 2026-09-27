import assert from 'node:assert/strict';
import test from 'node:test';
import {webcrypto} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import {act, createElement} from 'react';
import {createRoot} from 'react-dom/client';
import {JSDOM} from 'jsdom';
import {ProductApp} from '../src/product/ProductApp.js';
import {ProductMarketClient} from '../src/product/market-client.js';
import {PracticeClient, PORTFOLIO_MEDIA_TYPE, PROFILE_MEDIA_TYPE} from '../src/product/practice-client.js';
import type {LaunchCheckpoint} from '../src/product/practice-client.js';
import type {PracticeStorage} from '../src/product/practice-session.js';
import {practiceStorageKey} from '../src/product/practice-session.js';
import {JourneyStore, journeyPrincipal} from '../src/product/journey-store.js';
import {registerFundWalletOpener} from '../src/product/fund-wallet.js';
import type {FundWalletSource} from '../src/product/fund-wallet.js';
import {JourneyScreens} from '../src/product/journey-screens.js';
import {searchFixture, variantFixture} from '../src/markets/fixtures.test-support.js';
import {RESEARCH_AAPLX_MINT as MINT} from '../src/markets/estimate.js';

const GUEST_ID = '11111111-1111-4111-8111-111111111111';
const ACCOUNT_ID = '22222222-2222-4222-8222-222222222222';
const PREVIEW_ID = '44444444-4444-4444-8444-444444444444';
const ORDER_ID = '33333333-3333-4333-8333-333333333333';
class MemoryStorage implements PracticeStorage {
  readonly data = new Map<string, string>();
  getItem(key: string) {return this.data.get(key) ?? null;}
  setItem(key: string, value: string) {this.data.set(key, value);}
}
interface Call {path: string; method: string; body: Record<string, unknown> | null}
const json = (value: unknown, status = 200, media = 'application/json') => Response.json(value, {status, headers: {'content-type': media}});

/** A small fake of the practice API with the server's real launch transition table. */
function server(options: {checkpoint?: LaunchCheckpoint | null; traded?: boolean} = {}) {
  const now = Date.now(), at = new Date(now).toISOString();
  const state = {
    profile: options.checkpoint === null || options.checkpoint === undefined ? null : {revision: 3,
      onboarding: {goal: null, knowledge: null, persona: null, dailyGoal: null, handle: null},
      launchCheckpoint: options.checkpoint, hasConfirmedPaperTrade: options.traded ?? options.checkpoint !== 'first-trade', createdAt: at, updatedAt: at},
    traded: options.traded ?? (options.checkpoint !== null && options.checkpoint !== undefined && options.checkpoint !== 'first-trade'),
    lastRequestId: GUEST_ID, launches: [] as string[],
  };
  const source = {provider: 'tokens-xyz-v1', providerReference: '/v1/assets/apple', marketSource: null, metricsSource: null,
    providerTimestamps: {asOf: null, lastFetchedAt: null, lastTradeAt: null, unit: 'not_declared'}, observedAt: at, acceptedAt: at};
  const calculation = {action: 'buy', assetId: 'apple', variantMint: MINT, symbol: 'AAPLx', accountRevision: 0, pricePaperMicros: '50000000',
    quantityMicros: '2000000', cashDebitPaperMicros: '100000000', cashCreditPaperMicros: '0', cashAfterPaperMicros: '9900000000',
    positionQuantityAfterMicros: '2000000', positionCostBasisAfterPaperMicros: '100000000', realizedGainDeltaPaperMicros: '0', lockedGainDeltaPaperMicros: '0', source};
  const envelope = (kind: string, value: unknown) => ({schemaVersion: 1, mode: 'paper', unit: {kind: 'paper', scaleDigits: 6}, [kind]: value,
    fees: {paperMicros: '0'}, reward: {trimsAwarded: 0, reason: 'Trade completion alone does not award Trims.'},
    execution: {walletUsed: false, transactionBuilt: false, transactionSigned: false, transactionBroadcast: false}});
  const portfolio = () => {
    const base = {schemaVersion: 2, mode: 'paper', unit: {kind: 'paper', scaleDigits: 6}, startingCashPaperMicros: '10000000000'};
    if (!state.traded) return {...base, revision: 0, cashPaperMicros: '10000000000', openedAt: null, updatedAt: null, positions: [], recentOrders: [],
      valuation: {status: 'complete', portfolioRevision: 0, openPositionCount: 0, pricedPositionCount: 0, cashPaperMicros: '10000000000',
        knownValuePaperMicros: '10000000000', totalPaperMicros: '10000000000', positions: []}};
    return {...base, revision: 1, cashPaperMicros: '9900000000', openedAt: at, updatedAt: at,
      positions: [{assetId: 'apple', variantMint: MINT, symbol: 'AAPLx', quantityMicros: '2000000', costBasisPaperMicros: '100000000',
        averageCostPricePaperMicros: '50000000', realizedGainPaperMicros: '0', lockedGainPaperMicros: '0', updatedAt: at}],
      recentOrders: [{...calculation, accountRevision: 1, id: ORDER_ID, previewId: PREVIEW_ID, committedAt: at}],
      valuation: {status: 'complete', portfolioRevision: 1, openPositionCount: 1, pricedPositionCount: 1, cashPaperMicros: '9900000000',
        knownValuePaperMicros: '10000000000', totalPaperMicros: '10000000000', positions: [{assetId: 'apple', variantMint: MINT, status: 'priced',
          pricePaperMicros: '50000000', marketValuePaperMicros: '100000000', unrealizedGainPaperMicros: '0', observedAt: at, acceptedAt: at,
          expiresAt: new Date(now + 600000).toISOString()}]}};
  };
  const guest = {guestId: GUEST_ID, token: `tg1_${'A'.repeat(43)}`, expiresAt: new Date(now + 30 * 86400000).toISOString(), hardExpiresAt: new Date(now + 60 * 86400000).toISOString()};
  const calls: Call[] = [];
  const fetcher: typeof fetch = async (url, init = {}) => {
    const parsed = new URL(String(url), 'https://trimmy.example');
    const call: Call = {path: parsed.pathname.replace(/^\/api/, ''), method: init.method ?? 'GET', body: init.body ? JSON.parse(String(init.body)) as Record<string, unknown> : null};
    calls.push(call);
    if (call.path === '/v1/guest/session') return json({schemaVersion: 1, requestId: call.body?.['requestId'], ...guest}, 201);
    if (call.path === '/v1/guest/session/refresh') return json({schemaVersion: 1, ...guest});
    if (call.path === '/v1/product/profile') {
      if (call.method === 'PUT') state.profile = {revision: Number(call.body?.['baseRevision']) + 1, onboarding: call.body?.['onboarding'] as never,
        launchCheckpoint: call.body?.['launchCheckpoint'] as LaunchCheckpoint, hasConfirmedPaperTrade: state.traded, createdAt: at, updatedAt: at};
      return json({schemaVersion: 2, profile: state.profile}, 200, PROFILE_MEDIA_TYPE);
    }
    if (call.path === '/v1/product/launch') {
      const action = String(call.body?.['action']), profile = state.profile;
      if (!profile || profile.launchCheckpoint === 'app' || call.body?.['baseRevision'] !== profile.revision ||
        (action === 'paper-trade-confirmed' && profile.launchCheckpoint !== 'first-trade')) {
        return json({error: {code: 'PRODUCT_PROFILE_CHECKPOINT_CONFLICT', message: 'Conflict.', requestId: GUEST_ID}}, 409);
      }
      if ((action === 'paper-trade-confirmed' || action === 'introduction-completed') && !state.traded) {
        return json({error: {code: 'PRODUCT_PROFILE_LAUNCH_EVIDENCE_REQUIRED', message: 'Trade required.', requestId: GUEST_ID}}, 409);
      }
      state.launches.push(action);
      state.profile = {...profile, revision: profile.revision + 1, launchCheckpoint: action === 'paper-trade-confirmed' ? 'first-position' : 'app', hasConfirmedPaperTrade: state.traded};
      return json({schemaVersion: 2, profile: state.profile}, 200, PROFILE_MEDIA_TYPE);
    }
    if (call.path === '/v1/account/paper/portfolio') return json(portfolio(), 200, PORTFOLIO_MEDIA_TYPE);
    if (call.path === '/v1/account/paper/orders/preview') {
      state.lastRequestId = String(call.body?.['requestId']);
      return json(envelope('preview', {...calculation, id: PREVIEW_ID, requestId: state.lastRequestId, state: 'open',
        amount: {kind: 'paper_amount', paperMicros: '100000000'}, expiresAt: new Date(Date.now() + 30000).toISOString(), committedAt: null}));
    }
    if (call.path === '/v1/account/paper/orders/commit') {
      state.traded = true; if (state.profile) state.profile = {...state.profile, hasConfirmedPaperTrade: true};
      return json(envelope('order', {...calculation, accountRevision: 1, id: ORDER_ID, previewId: PREVIEW_ID, committedAt: at}));
    }
    if (call.path === '/v1/career/summary') return json({schemaVersion: 1, career: {revision: 0, trims: {total: 0, today: 0, thisWeek: 0},
      rank: {id: 'rookie', label: 'Rookie', paperLimit: '10000', threshold: 0}, nextRank: {id: 'analyst', label: 'Analyst', threshold: 300, trimsRemaining: 300, promotionRequired: true},
      streak: {days: 0, status: 'not-started', lastActiveDate: null}, careerStarted: false,
      firstConfirmedBuy: state.traded ? {orderId: ORDER_ID, assetId: 'apple', variantMint: MINT, symbol: 'AAPLx', quantityMicros: '2000000', confirmedAt: at} : null,
      serverDate: at.slice(0, 10), updatedAt: null}});
    if (call.path === '/v1/career/missions') return json({schemaVersion: 1, career: {revision: 0, currentRank: 'rookie'}, missions: []});
    if (call.path.endsWith('/search')) {
      const page = {...searchFixture(parsed.searchParams.get('query')!, Number(parsed.searchParams.get('limit'))), requestedAt: at, observedAt: at,
        refreshAfter: new Date(now + 60000).toISOString()};
      page.results = [{...page.results[0]!, variants: [variantFixture()]}];
      return json(page);
    }
    if (call.path.endsWith('/facts')) return json({schemaVersion: 1, provider: 'tokens-xyz-v1', requestedAt: at, observedAt: at, refreshAfter: new Date(now + 60000).toISOString(),
      displayOnly: true, executionEnabled: false, eligibility: 'unverified', sourceUrls: ['https://api.tokens.xyz/v1/assets/apple'], assetId: 'apple', name: 'Apple', symbol: 'AAPL',
      imageUrl: null, description: null, stock: null, sparkline: null, sparklineStatus: 'unavailable'});
    return json({error: {code: 'NOT_IN_THIS_TEST', message: 'Not used by this test.', requestId: GUEST_ID}}, 404);
  };
  return {state, calls, fetcher};
}

async function harness(options: {checkpoint?: LaunchCheckpoint | null; traded?: boolean; account?: boolean; savedGuest?: boolean; hash?: string; storage?: MemoryStorage} = {}) {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {url: `https://trimmy.example/${options.hash ?? ''}`, pretendToBeVisual: true});
  const saved = new Map<string, PropertyDescriptor | undefined>();
  const expose = (name: string, value: unknown) => {saved.set(name, Object.getOwnPropertyDescriptor(globalThis, name)); Object.defineProperty(globalThis, name, {configurable: true, writable: true, value});};
  expose('window', dom.window); expose('document', dom.window.document); expose('navigator', dom.window.navigator);
  expose('HTMLElement', dom.window.HTMLElement); expose('Event', dom.window.Event); expose('localStorage', dom.window.localStorage);
  expose('crypto', webcrypto); expose('IS_REACT_ACT_ENVIRONMENT', true);
  Object.defineProperty(dom.window, 'matchMedia', {value: () => ({matches: true, addEventListener() {}, removeEventListener() {}})});
  Object.defineProperty(dom.window.navigator, 'locks', {value: {request: async (_name: string, _options: unknown, callback: () => Promise<unknown>) => callback()}});
  const permission: string[] = [];
  Object.defineProperty(dom.window, 'Notification', {configurable: true, value: {permission: 'default', requestPermission: async () => {permission.push('asked'); return 'granted';}}});
  const api = server(options), storage = options.storage ?? new MemoryStorage();
  const practice = new PracticeClient({baseUrl: '/api', fetch: api.fetcher, timeoutMs: 1000});
  const market = new ProductMarketClient({baseUrl: '/api', fetch: api.fetcher, timeoutMs: 1000});
  const account = {subject: 'did:privy:journeyTester', accountId: ACCOUNT_ID, signal: new AbortController().signal, freshAccessToken: async () => 'test.account.proof'};
  const store = new JourneyStore(storage, '/api');
  if (options.savedGuest) {
    const {PracticeSession} = await import('../src/product/practice-session.js');
    await new PracticeSession({client: practice, storage}).ensureGuest();
  }
  const root = createRoot(dom.window.document.getElementById('root')!);
  const flush = async (ms = 25) => {await act(async () => {await delay(ms);});};
  const app = async () => {
    await act(async () => {root.render(createElement(ProductApp, {apiBase: '/api', practiceClient: practice, marketClient: market, storage,
      authConfig: {kind: 'disabled'}, ...(options.account ? {accountAccess: account} : {})}));});
    await flush();
  };
  const reload = async () => {await act(async () => {root.render(createElement('div', null, 'Reloading'));}); await flush(); await app();};
  const text = () => dom.window.document.body.textContent ?? '';
  const button = (label: string) => [...dom.window.document.querySelectorAll<HTMLButtonElement>('button')].find(item => item.textContent?.trim() === label || item.getAttribute('aria-label') === label);
  const click = async (label: string) => {const target = button(label); assert.ok(target, `Button exists: ${label}`); await act(async () => {target.click();}); await flush();};
  const pick = async (label: string) => {
    const target = [...dom.window.document.querySelectorAll<HTMLButtonElement>('.setup-choice')].find(item => item.querySelector('strong')?.textContent === label);
    assert.ok(target, `Choice exists: ${label}`); await act(async () => {target.click();}); await flush();
  };
  const back = async () => {await act(async () => {dom.window.dispatchEvent(new dom.window.PopStateEvent('popstate'));}); await flush();};
  const escape = async () => {await act(async () => {dom.window.dispatchEvent(new dom.window.KeyboardEvent('keydown', {key: 'Escape', bubbles: true}));}); await flush();};
  const close = async () => {await act(async () => {root.unmount();}); market.close(); dom.window.close();
    for (const [name, descriptor] of saved) {if (descriptor) Object.defineProperty(globalThis, name, descriptor); else Reflect.deleteProperty(globalThis, name);}};
  return {dom, api, storage, store, app, reload, text, button, click, pick, back, escape, flush, close, permission};
}
type Harness = Awaited<ReturnType<typeof harness>>;
async function buyFirstStock(h: Harness) {
  await h.app(); await h.click('Start my first day'); await h.click('Continue');
  await h.click('Choose Apple'); await h.click('Review paper buy'); await h.click('Confirm paper buy');
  assert.match(h.text(), /You’ve placed your first order!/);
}

test('the account choice follows the celebration; Back, Escape and reload never count as choosing guest', async () => {
  const h = await harness();
  try {
    await buyFirstStock(h); await h.click('Continue');
    assert.match(h.text(), /Your desk awaits\./); assert.equal(h.button('Close sign in'), undefined, 'the gate has no close action');
    await h.back(); await h.escape();
    assert.match(h.text(), /Your desk awaits\./); assert.equal(h.store.guestChosen(), false);
    await h.reload();
    assert.match(h.text(), /Your desk awaits\./, 'the gate survives reload');
    assert.equal(h.api.state.profile?.launchCheckpoint, 'first-position');
    assert.equal(h.api.calls.filter(call => call.path.endsWith('/commit')).length, 1);
    await h.click('Continue as guest');
    assert.match(h.text(), /A little nudge\?/); assert.equal(h.store.guestChosen(), true);
    await h.reload();
    assert.match(h.text(), /A little nudge\?/, 'the saved guest choice survives reload');
  } finally {await h.close();}
});

test('reminder and money steps survive reload, finish once and never request a notification permission', async () => {
  const h = await harness();
  try {
    await buyFirstStock(h); await h.click('Continue'); await h.click('Continue as guest');
    await h.pick('Once a day'); await h.click('Continue');
    assert.match(h.text(), /Your preference is saved\. Browsers can’t send Trimmy reminders while it’s closed/);
    assert.ok(h.button('Add to calendar')); assert.deepEqual(h.permission, [], 'no browser permission prompt');
    const guest = journeyPrincipal({guestId: GUEST_ID});
    assert.equal(h.store.reminder(guest)?.choice, 'daily');
    await h.reload();
    assert.match(h.text(), /A little nudge\?/);
    assert.equal(h.dom.window.document.querySelector('.setup-choice[aria-checked="true"] strong')?.textContent, 'Once a day');
    await h.click('Continue'); await h.click('Continue');
    assert.match(h.text(), /Your next move\./);
    await h.reload();
    assert.match(h.text(), /Your next move\./, 'the money choice survives reload');
    await h.escape();
    assert.deepEqual(h.api.state.launches, ['paper-trade-confirmed', 'introduction-completed'], 'Back keeps free money and finishes once');
    assert.match(h.text(), /Your desk\./);
    await h.reload();
    assert.match(h.text(), /Your desk\./); assert.deepEqual(h.api.state.launches, ['paper-trade-confirmed', 'introduction-completed']);
  } finally {await h.close();}
});

test('skipping reminders with Back saves Keep it quiet instead of a silent default', async () => {
  const h = await harness();
  try {
    await buyFirstStock(h); await h.click('Continue'); await h.click('Continue as guest');
    await h.back();
    assert.match(h.text(), /Your next move\./);
    assert.equal(h.store.reminder(journeyPrincipal({guestId: GUEST_ID}))?.choice, 'off');
  } finally {await h.close();}
});

test('Skip from the note reaches the account choice, which survives reload until the explicit guest choice', async () => {
  const h = await harness();
  try {
    await h.app(); await h.click('Start my first day'); await h.click('Skip first day');
    assert.deepEqual(h.api.state.launches, ['introduction-skipped']);
    assert.match(h.text(), /Your desk awaits\./);
    await h.reload(); assert.match(h.text(), /Your desk awaits\./);
    await h.back(); assert.match(h.text(), /Your desk awaits\./); assert.equal(h.store.guestChosen(), false);
    await h.click('Continue as guest');
    assert.match(h.text(), /Your desk\./); assert.doesNotMatch(h.text(), /A little nudge|Your next move/);
    assert.equal(h.api.calls.some(call => call.path.includes('/orders/')), false);
  } finally {await h.close();}
});

test('existing anonymous progress asks once, and the saved choice then opens the desk directly', async () => {
  const h = await harness({checkpoint: 'app', savedGuest: true});
  try {
    await h.app(); assert.match(h.text(), /Your desk awaits\./);
    await h.click('Continue as guest'); assert.match(h.text(), /Your desk\./);
    await h.reload(); assert.match(h.text(), /Your desk\./); assert.doesNotMatch(h.text(), /Your desk awaits/);
  } finally {await h.close();}
});

test('Add money as a guest finishes the introduction, then asks the guest to sign in before any deposit', async () => {
  const opened: FundWalletSource[] = [];
  const release = registerFundWalletOpener(source => {opened.push(source);});
  const h = await harness();
  try {
    await buyFirstStock(h); await h.click('Continue'); await h.click('Continue as guest'); await h.pick('Keep it quiet'); await h.click('Continue');
    await h.pick('Add money');
    assert.deepEqual(h.api.state.launches, ['paper-trade-confirmed', 'introduction-completed']);
    assert.match(h.text(), /Make this desk yours\./, 'a guest signs in first, as on mobile');
    assert.deepEqual(opened, [], 'no deposit opens for a guest');
    await h.click('Close sign in');
    assert.match(h.text(), /Your desk\./); assert.equal(h.store.consumeSignInIntent(), null, 'closing sign-in forgets the funding request');
  } finally {release(); await h.close();}
});

test('a signed-in account opens the fund-wallet merge point, or says plainly that deposits are not open yet', async () => {
  const storage = new MemoryStorage(), celebrated = new JourneyStore(storage, '/api');
  celebrated.acknowledgeCelebration(journeyPrincipal({guestId: GUEST_ID}), ORDER_ID);
  const opened: FundWalletSource[] = [];
  for (const wired of [true, false]) {
    const release = wired ? registerFundWalletOpener(source => {opened.push(source);}) : () => {};
    const h = await harness({account: true, checkpoint: 'first-position', storage: wired ? storage : (() => {const next = new MemoryStorage(); new JourneyStore(next, '/api').acknowledgeCelebration(journeyPrincipal({guestId: GUEST_ID}), ORDER_ID); return next;})()});
    try {
      await h.app();
      assert.match(h.text(), /A little nudge\?/, 'a claimed desk continues after the same celebrated order without a gate');
      assert.doesNotMatch(h.text(), /Continue as guest/);
      await h.pick('Keep it quiet'); await h.click('Continue'); await h.pick('Add money');
      assert.match(h.text(), /Your desk\./);
      if (wired) assert.deepEqual(opened, ['first-day']);
      else assert.match(h.text(), /Adding money isn’t available on the web yet\. You can keep practicing with free money\./);
    } finally {release(); await h.close();}
  }
});

test('an existing account at the app checkpoint restores straight to its desk; guests never inherit its choice', async () => {
  const storage = new MemoryStorage(); new JourneyStore(storage, '/api').chooseGuest();
  const h = await harness({account: true, checkpoint: 'app', storage});
  try {
    await h.app(); assert.match(h.text(), /Your desk\./);
    assert.doesNotMatch(h.text(), /Your desk awaits|A little nudge|Your next move/);
    assert.equal(h.store.guestChosen(), false, 'signing in asks again after a later sign-out, as on mobile');
  } finally {await h.close();}
});

test('signing in from the app skips an unfinished account introduction instead of replaying it', async () => {
  const storage = new MemoryStorage(); new JourneyStore(storage, '/api').setSignInIntent('app');
  const h = await harness({account: true, checkpoint: 'first-trade', traded: false, storage});
  try {
    await h.app();
    assert.deepEqual(h.api.state.launches, ['introduction-skipped']);
    assert.match(h.text(), /Your desk\./); assert.equal(h.button('Choose Apple'), undefined);
  } finally {await h.close();}
});

test('a new account signed in from Welcome starts its own first practice trade', async () => {
  const h = await harness({account: true, checkpoint: null});
  try {
    await h.app();
    assert.ok(h.button('Choose Apple'), 'the account continues at practice rather than an empty desk');
    assert.deepEqual(h.api.state.launches, []);
  } finally {await h.close();}
});

test('the Welcome back notice for a preserved guest desk shows the expired variant and continues', async () => {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {url: 'https://trimmy.example/'});
  const saved = new Map<string, PropertyDescriptor | undefined>();
  for (const [key, value] of Object.entries({window: dom.window, document: dom.window.document, navigator: dom.window.navigator, HTMLElement: dom.window.HTMLElement, IS_REACT_ACT_ENVIRONMENT: true})) {
    saved.set(key, Object.getOwnPropertyDescriptor(globalThis, key)); Object.defineProperty(globalThis, key, {configurable: true, writable: true, value});
  }
  const root = createRoot(dom.window.document.getElementById('root')!);
  let acknowledged = 0;
  const market = new ProductMarketClient({baseUrl: '/api', fetch: async () => json({}), timeoutMs: 1000});
  try {
    const journey = {preservedNotice: true, view: {kind: 'app'}, acknowledgePreserved() {acknowledged++;}} as never;
    await act(async () => {root.render(createElement(JourneyScreens, {journey, market, career: null, portfolio: null, careerLoading: false, motion: false,
      preservedExpired: true, onGuest: async () => {}, onAccount() {}, onRetryEvidence() {}, onFinish: async () => {}}));});
    const text = dom.window.document.body.textContent ?? '';
    assert.match(text, /Welcome back/); assert.match(text, /Your saved trades and progress are ready\./);
    assert.match(text, /Your expired guest desk is preserved separately\. It can no longer trade or merge\./);
    const go = [...dom.window.document.querySelectorAll('button')].find(item => item.textContent === 'Go to my desk')!;
    await act(async () => {go.click();}); assert.equal(acknowledged, 1);
  } finally {
    await act(async () => {root.unmount();}); market.close(); dom.window.close();
    for (const [key, descriptor] of saved) {if (descriptor) Object.defineProperty(globalThis, key, descriptor); else Reflect.deleteProperty(globalThis, key);}
  }
});

test('the practice storage journal is untouched by first-day choices', async () => {
  const h = await harness();
  try {
    await buyFirstStock(h); await h.click('Continue');
    const journal = h.storage.getItem(practiceStorageKey('/api'));
    await h.click('Continue as guest'); await h.pick('Keep it quiet'); await h.click('Continue');
    const after = JSON.parse(h.storage.getItem(practiceStorageKey('/api'))!) as {lastReceipt: {id: string}; pendingProfile: unknown};
    assert.equal(after.lastReceipt.id, ORDER_ID); assert.equal(after.pendingProfile, null);
    assert.equal(h.storage.getItem(practiceStorageKey('/api')), journal, 'local choices live beside, not inside, the practice journal');
  } finally {await h.close();}
});

test('Add to calendar downloads the matching recurring event locally and sends nothing to a server', async () => {
  const h = await harness();
  const downloads: {name: string; href: string}[] = [];
  const originalCreate = URL.createObjectURL, originalRevoke = URL.revokeObjectURL;
  let body = '';
  URL.createObjectURL = (blob: Blob) => {void blob.text().then(value => {body = value;}); return 'blob:https://trimmy.example/reminder';};
  URL.revokeObjectURL = () => {};
  Object.defineProperty(h.dom.window.HTMLAnchorElement.prototype, 'click', {configurable: true, value(this: HTMLAnchorElement) {downloads.push({name: this.download, href: this.href});}});
  try {
    await buyFirstStock(h); await h.click('Continue'); await h.click('Continue as guest');
    await h.pick('A few times a week'); await h.click('Continue');
    const before = h.api.calls.length;
    await h.click('Add to calendar'); await h.flush();
    assert.deepEqual(downloads, [{name: 'trimmy-reminder-mon-wed-fri.ics', href: 'blob:https://trimmy.example/reminder'}]);
    assert.match(body, /RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR/); assert.match(body, /URL:https:\/\/trimmy\.example\/#career/);
    assert.equal(h.api.calls.length, before); assert.deepEqual(h.permission, []);
  } finally {URL.createObjectURL = originalCreate; URL.revokeObjectURL = originalRevoke; await h.close();}
});
