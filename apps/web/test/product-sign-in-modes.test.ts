import assert from 'node:assert/strict';
import test from 'node:test';
import {act, createElement} from 'react';
import {JSDOM} from 'jsdom';
import {ProductAuthContext, type ProductAuth} from '../src/product/product-auth.js';
import {SignInScreen} from '../src/product/sign-in-screen.js';

async function harness(props: {entryGate?: boolean; expiredGuestRecovery?: boolean; onGuest?: () => Promise<void>}, initial: Partial<ProductAuth> = {}) {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {url: 'https://trimmy.example/#desk'});
  const previous = new Map<string, PropertyDescriptor | undefined>();
  for (const [key, value] of Object.entries({window: dom.window, document: dom.window.document, navigator: dom.window.navigator, HTMLElement: dom.window.HTMLElement, IS_REACT_ACT_ENVIRONMENT: true})) {
    previous.set(key, Object.getOwnPropertyDescriptor(globalThis, key)); Object.defineProperty(globalThis, key, {configurable: true, writable: true, value});
  }
  Object.defineProperty(dom.window, 'matchMedia', {value: () => ({matches: true, addEventListener() {}, removeEventListener() {}})});
  const {createRoot} = await import('react-dom/client');
  const root = createRoot(dom.window.document.getElementById('root')!);
  const calls = {back: 0, cancel: 0, logout: 0};
  const auth: ProductAuth = {enabled: true, ready: true, busy: false, authenticated: false, phase: 'ready', subject: null, accountId: null, accountAccess: null,
    apiBase: '/api', email: null, errorCode: null, guestDisposition: null, lastSuccessfulMethod: null, logins: [], async sendEmailCode() {}, async verifyEmailCode() {},
    async loginWithProvider() {}, async freshAccessToken() {return null;}, async openExistingAccount() {}, async retry() {},
    async logout() {calls.logout++; return true;}, cancel() {calls.cancel++;}, ...initial};
  await act(async () => {root.render(createElement(ProductAuthContext.Provider, {value: auth}, createElement(SignInScreen, {motion: false, hasDesk: true,
    onBack: () => {calls.back++;}, onAccount() {}, ...props})));});
  const button = (label: string) => [...dom.window.document.querySelectorAll<HTMLButtonElement>('button')].find(item => item.textContent?.trim() === label || item.getAttribute('aria-label') === label);
  const close = async () => {await act(async () => {root.unmount();}); dom.window.close();
    for (const [key, descriptor] of previous) {if (descriptor) Object.defineProperty(globalThis, key, descriptor); else Reflect.deleteProperty(globalThis, key);}};
  return {dom, calls, button, close, text: () => dom.window.document.body.textContent ?? ''};
}

test('the entry gate has no close action and Back or Escape never grant guest access', async () => {
  let guests = 0;
  const h = await harness({entryGate: true, onGuest: async () => {guests++;}});
  try {
    assert.match(h.text(), /Your desk awaits\./); assert.match(h.text(), /Sign in or create your account\./);
    assert.equal(h.button('Close sign in'), undefined);
    await act(async () => {
      h.dom.window.dispatchEvent(new h.dom.window.KeyboardEvent('keydown', {key: 'Escape', bubbles: true}));
      h.dom.window.dispatchEvent(new h.dom.window.PopStateEvent('popstate'));
    });
    assert.equal(guests, 0); assert.equal(h.calls.back, 0); assert.equal(h.dom.window.location.hash, '#desk', 'the gate does not rewrite the address');
    await act(async () => {h.button('Continue as guest')!.click();});
    assert.equal(guests, 1);
  } finally {await h.close();}
});

test('a guest choice that cannot be saved says so and can be retried', async () => {
  let attempts = 0;
  const h = await harness({entryGate: true, onGuest: async () => {if (++attempts === 1) throw new Error('quota');}});
  try {
    await act(async () => {h.button('Continue as guest')!.click();});
    assert.match(h.text(), /Couldn’t save your choice\. Try again\./);
    await act(async () => {h.button('Continue as guest')!.click();});
    assert.equal(attempts, 2); assert.doesNotMatch(h.text(), /Couldn’t save your choice/);
  } finally {await h.close();}
});

test('the gate keeps working when sign-in is not configured, as mobile keeps Continue as guest', async () => {
  let guests = 0;
  const h = await harness({entryGate: true, onGuest: async () => {guests++;}}, {enabled: false, phase: 'unconfigured'});
  try {
    assert.equal(h.button('Continue with email')?.disabled, true);
    assert.equal(h.button('Continue as guest')?.disabled, false);
    await act(async () => {h.button('Continue as guest')!.click();}); assert.equal(guests, 1);
  } finally {await h.close();}
});

test('sign-in from an expired guest desk explains that the desk stays separate', async () => {
  const h = await harness({expiredGuestRecovery: true});
  try {
    assert.match(h.text(), /Sign in to Trimmy\./); assert.match(h.text(), /Open your account desk\. The expired guest desk stays separate\./);
    assert.match(h.text(), /Closing sign-in keeps the expired guest desk preserved\./);
    assert.ok(h.button('Close sign in')); assert.equal(h.button('Continue as guest'), undefined);
  } finally {await h.close();}
});
