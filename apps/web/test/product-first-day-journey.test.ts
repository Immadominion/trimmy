import assert from 'node:assert/strict';
import test from 'node:test';
import {act, createElement} from 'react';
import {JSDOM} from 'jsdom';
import {ProductMarketClient} from '../src/product/market-client.js';
import {practiceStorageKey} from '../src/product/practice-session.js';
import {JourneyStore, journeyPrincipal} from '../src/product/journey-store.js';
import {registerFundWalletOpener} from '../src/product/fund-wallet.js';
import type {FundWalletSource} from '../src/product/fund-wallet.js';
import {JourneyScreens} from '../src/product/journey-screens.js';
import {GUEST_ID, ORDER_ID, MemoryStorage, harness, json} from './support/product-harness.js';
import type {Harness} from './support/product-harness.js';

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

test('a signed-in account opens Add money, or says plainly that deposits are not open yet', async () => {
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
  const {createRoot} = await import('react-dom/client');
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

test('the celebration names the company picked in the first day even before public facts load', async () => {
  const h = await harness({reply: call => call.path.endsWith('/facts') ? json({error: {code: 'STOCK_FACTS_UNAVAILABLE', message: 'Down.', requestId: 'x'}}, 503) : undefined});
  try {
    await buyFirstStock(h);
    assert.equal(h.dom.window.document.querySelector('.first-order-company strong')?.textContent, 'Apple');
    assert.equal(h.dom.window.document.querySelector('.first-order-company img')?.getAttribute('src'), '/trimmy/token-AAPLx.webp');
  } finally {await h.close();}
});

test('a lost first-order response is checked from the desk without skipping, then continues to the celebration', async () => {
  let lose = true;
  const h = await harness({reply: call => {
    if (call.path.endsWith('/orders/commit') && lose) {lose = false; throw new TypeError('Receipt lost');}
    return undefined;
  }});
  try {
    await h.app(); await h.click('Start my first day'); await h.click('Continue');
    await h.click('Choose Apple'); await h.click('Review paper buy'); await h.click('Confirm paper buy');
    assert.match(h.text(), /Your last order needs checking\./);
    await h.click('Check from desk');
    assert.deepEqual(h.api.state.launches, [], 'checking an order never records a skipped introduction');
    assert.match(h.text(), /Let’s check your last order\./);
    await h.click('Check order');
    assert.match(h.text(), /You’ve placed your first order!/);
    assert.equal(h.api.calls.filter(call => call.path.endsWith('/orders/commit')).length, 2, 'the same order is replayed, never bought twice');
    await h.click('Continue');
    assert.deepEqual(h.api.state.launches, ['paper-trade-confirmed']);
  } finally {await h.close();}
});
