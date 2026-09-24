import assert from 'node:assert/strict';
import test from 'node:test';
import {act, createElement} from 'react';
import {JSDOM} from 'jsdom';
import {ProductAuthContext, type ProductAuth} from '../src/product/product-auth.js';
import {SignInScreen} from '../src/product/sign-in-screen.js';

async function harness(initial: Partial<ProductAuth> = {}) {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {url: 'https://trimmy.example/#sign-in'});
  const previous = new Map<string, PropertyDescriptor | undefined>();
  for (const [key, value] of Object.entries({window: dom.window, document: dom.window.document,
    navigator: dom.window.navigator, HTMLElement: dom.window.HTMLElement, IS_REACT_ACT_ENVIRONMENT: true})) {
    previous.set(key, Object.getOwnPropertyDescriptor(globalThis, key)); Object.defineProperty(globalThis, key, {configurable: true, writable: true, value});
  }
  Object.defineProperty(dom.window, 'matchMedia', {value: () => ({matches: true, addEventListener() {}, removeEventListener() {}})});
  const {createRoot} = await import('react-dom/client');
  const root = createRoot(dom.window.document.getElementById('root')!);
  const calls = {send: [] as string[], verify: [] as string[], providers: [] as string[], back: 0, account: 0, cancel: 0, retry: 0, existing: 0, logout: 0};
  let auth: ProductAuth = {enabled: true, ready: true, busy: false, authenticated: false, phase: 'ready', subject: null,
    accountId: null, accountAccess: null, apiBase: '/api', email: null, errorCode: null, guestDisposition: null, lastSuccessfulMethod: null,
    async sendEmailCode(value) {calls.send.push(value);}, async verifyEmailCode(value) {calls.verify.push(value);},
    async loginWithProvider(value) {calls.providers.push(value);}, async freshAccessToken() {return null;},
    async openExistingAccount() {calls.existing++;}, async retry() {calls.retry++;}, async logout() {calls.logout++; return true;},
    cancel() {calls.cancel++;}, ...initial};
  const onBack = () => {calls.back++;}, onAccount = () => {calls.account++;};
  const render = async (update: Partial<ProductAuth> = {}) => {auth = {...auth, ...update}; await act(async () => {
    root.render(createElement(ProductAuthContext.Provider, {value: auth}, createElement(SignInScreen, {motion: false, hasDesk: true, onBack, onAccount})));
  });};
  const button = (label: string) => [...dom.window.document.querySelectorAll<HTMLButtonElement>('button')]
    .find(value => value.textContent?.trim() === label || value.getAttribute('aria-label') === label);
  const click = async (label: string) => {const target = button(label); assert.ok(target, `Button exists: ${label}`); await act(async () => {target.click();});};
  const input = async (id: string, value: string) => {
    const field = dom.window.document.getElementById(id) as HTMLInputElement; assert.ok(field);
    await act(async () => {Object.getOwnPropertyDescriptor(dom.window.HTMLInputElement.prototype, 'value')!.set!.call(field, value);
      field.dispatchEvent(new dom.window.Event('input', {bubbles: true}));});
  };
  const escape = async () => {await act(async () => {dom.window.dispatchEvent(new dom.window.KeyboardEvent('keydown', {key: 'Escape', bubbles: true}));});};
  const close = async () => {await act(async () => {root.unmount();}); dom.window.close();
    for (const [key, descriptor] of previous) {if (descriptor) Object.defineProperty(globalThis, key, descriptor); else Reflect.deleteProperty(globalThis, key);}};
  await render();
  return {dom, calls, render, button, click, input, escape, close, text: () => dom.window.document.body.textContent ?? ''};
}

test('last successful Google method leads the screen while email and X remain real accessible alternatives', async () => {
  const h = await harness({lastSuccessfulMethod: 'google'});
  try {
    assert.match(h.text(), /Last used on this browser/);
    assert.equal(h.dom.window.document.querySelector('.sign-in-preferred')?.textContent?.trim(), 'Continue with Google');
    assert.ok(h.button('Continue with email')); assert.ok(h.button('Continue with X')); assert.equal(h.button('Continue with Apple'), undefined);
    await h.click('Continue with Google'); await h.click('Continue with X'); assert.deepEqual(h.calls.providers, ['google', 'x']);
    assert.equal(h.calls.account, 0);
  } finally {await h.close();}
});

test('email and code inputs send their entered values through the auth context and do not invent a receipt', async () => {
  const h = await harness();
  try {
    await h.click('Continue with email'); await h.input('sign-in-email', 'person@example.com');
    await h.click('Continue with email'); assert.deepEqual(h.calls.send, ['person@example.com']); assert.equal(h.calls.account, 0);
    await h.render({phase: 'code-sent', email: 'person@example.com'});
    assert.match(h.text(), /Check your inbox/); assert.equal(h.button('Continue')?.disabled, true);
    await h.input('sign-in-code', '123456'); await h.click('Continue');
    assert.deepEqual(h.calls.verify, ['123456']); assert.equal(h.calls.account, 0);
    await h.render({phase: 'connecting', busy: true}); assert.match(h.text(), /Restoring your progress/); assert.equal(h.calls.account, 0);
    await h.render({phase: 'authenticated', busy: false, authenticated: true}); assert.equal(h.calls.account, 1);
  } finally {await h.close();}
});

test('pending authentication blocks close, Escape and all provider actions', async () => {
  const h = await harness({phase: 'authenticating', busy: true});
  try {
    assert.equal(h.button('Close sign in')?.disabled, true);
    await h.click('Close sign in'); await h.escape(); await h.click('Continue with Google');
    await act(async () => {h.dom.window.history.replaceState(null, '', '#welcome');
      h.dom.window.dispatchEvent(new h.dom.window.PopStateEvent('popstate'));});
    assert.equal(h.dom.window.location.hash, '#sign-in');
    assert.equal(h.calls.back, 0); assert.equal(h.calls.cancel, 0); assert.deepEqual(h.calls.providers, []);
  } finally {await h.close();}
});

test('failed sign-out keeps the screen open and its explicit retry only leaves after SDK sign-out succeeds', async () => {
  let attempts = 0;
  const h = await harness({phase: 'error', subject: 'did:privy:accountA', errorCode: 'PRACTICE_NETWORK_ERROR',
    async logout() {attempts++; return false;}});
  try {
    await h.click('Close sign in'); assert.equal(attempts, 1); assert.equal(h.calls.back, 0);
    await h.render({subject: null, errorCode: 'PRODUCT_SIGN_OUT_FAILED', async logout() {attempts++; return true;}});
    assert.ok(h.button('Try signing out again')); await h.click('Try signing out again');
    assert.equal(attempts, 2); assert.equal(h.calls.back, 1);
  } finally {await h.close();}
});

test('claim conflict shows an explicit saved-account action and keeps both accounts unconfirmed until completion', async () => {
  const h = await harness({phase: 'account-choice', subject: 'did:privy:accountA', errorCode: 'GUEST_CLAIM_ACCOUNT_EXISTS'});
  try {
    assert.match(h.text(), /guest progress stays in this browser/); assert.equal(h.calls.existing, 0); assert.equal(h.calls.account, 0);
    await h.click('Open my account'); assert.equal(h.calls.existing, 1); assert.equal(h.calls.account, 0);
  } finally {await h.close();}
});

test('disabled sign-in keeps its actions disabled and email Back clears only the local form', async () => {
  const h = await harness({enabled: false, phase: 'unconfigured'});
  try {
    assert.match(h.text(), /Sign-in isn’t available here yet/); assert.equal(h.button('Continue with email')?.disabled, true);
    await h.click('Continue with email'); assert.equal(h.dom.window.document.getElementById('sign-in-email'), null);
    await h.render({enabled: true, phase: 'ready'}); await h.click('Continue with email');
    await h.escape(); assert.equal(h.calls.cancel, 1); assert.equal(h.calls.back, 0);
    assert.equal(h.dom.window.document.getElementById('sign-in-email'), null);
    await h.click('Close sign in'); assert.equal(h.calls.back, 1);
  } finally {await h.close();}
});
