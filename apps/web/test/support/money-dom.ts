/** A jsdom page for own-money UI tests, mounted inside a MoneyProvider bound to one account. */
import assert from 'node:assert/strict';
import {webcrypto} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import {act, createElement, StrictMode, type ReactElement} from 'react';
import {JSDOM} from 'jsdom';
import {MoneyProvider} from '../../src/product/money/money-context.js';
import type {ProductWalletSdkPort} from '../../src/product/money/wallet-sdk-loader.js';
import {ACCOUNT_ID, SUBJECT} from './money-fixtures.js';
import {moneyHarness} from './money-harness.js';

export async function moneyPage(options: Parameters<typeof moneyHarness>[0] & {signedIn?: boolean; strict?: boolean} = {}) {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {url: 'https://trimmy.example/#desk', pretendToBeVisual: true});
  const saved = new Map<string, PropertyDescriptor | undefined>();
  const expose = (name: string, value: unknown) => {saved.set(name, Object.getOwnPropertyDescriptor(globalThis, name));
    Object.defineProperty(globalThis, name, {configurable: true, writable: true, value});};
  expose('window', dom.window); expose('document', dom.window.document); expose('navigator', dom.window.navigator);
  expose('HTMLElement', dom.window.HTMLElement); expose('Event', dom.window.Event); expose('localStorage', dom.window.localStorage);
  expose('crypto', webcrypto); expose('IS_REACT_ACT_ENVIRONMENT', true);
  Object.defineProperty(dom.window, 'matchMedia', {value: () => ({matches: true, addEventListener() {}, removeEventListener() {}})});
  const copied: string[] = [];
  Object.defineProperty(dom.window.navigator, 'clipboard', {value: {writeText: async (value: string) => {copied.push(value);}}});
  const h = await moneyHarness(options);
  const walletSdk: ProductWalletSdkPort = {useEmbeddedSolana: () => h.embedded()};
  const access = {subject: SUBJECT, accountId: ACCOUNT_ID, signal: h.identity.signal,
    freshAccessToken: async () => h.identity.signal.aborted ? null : 'aaa.bbb.ccc'};
  // react-dom decides whether the page supports input events when it first loads: load it after the DOM exists.
  const {createRoot} = await import('react-dom/client');
  const root = createRoot(dom.window.document.getElementById('root')!);
  const flush = async (ms = 20) => {await act(async () => {await delay(ms);});};
  const render = async (children: ReactElement) => {
    const provider = createElement(MoneyProvider, {apiBase: '/api', accountAccess: options.signedIn === false ? null : access,
      walletSdk, fetch: h.fetch, storage: h.storage, orderPollMs: 5, children});
    await act(async () => {root.render(options.strict ? createElement(StrictMode, null, provider) : provider);});
    await flush();
  };
  const text = () => dom.window.document.body.textContent ?? '';
  const all = <T extends Element>(selector: string) => [...dom.window.document.querySelectorAll<T>(selector)];
  const button = (label: string | RegExp) => all<HTMLButtonElement>('button').find(item => {
    const name = item.textContent?.trim() ?? '', aria = item.getAttribute('aria-label') ?? '';
    return typeof label === 'string' ? name === label || aria === label : label.test(name) || label.test(aria);
  });
  const click = async (label: string | RegExp) => {
    const target = button(label); assert.ok(target, `Button exists: ${label}`);
    await act(async () => {target.click();}); await flush();
  };
  const type = async (selector: string, value: string) => {
    const input = dom.window.document.querySelector<HTMLInputElement>(selector); assert.ok(input, `Input exists: ${selector}`);
    const setter = Object.getOwnPropertyDescriptor(dom.window.HTMLInputElement.prototype, 'value')!.set!;
    await act(async () => {setter.call(input, value); input.dispatchEvent(new dom.window.Event('input', {bubbles: true}));}); await flush();
  };
  const tick = async (selector = '.issuer-tick input') => {
    const box = dom.window.document.querySelector<HTMLInputElement>(selector); assert.ok(box, 'Terms checkbox exists');
    await act(async () => {box.click();}); await flush();
  };
  const waitFor = async (check: () => boolean, label: string, ms = 2000) => {
    const deadline = Date.now() + ms;
    while (!check()) {if (Date.now() > deadline) throw new Error(`Timed out waiting for ${label}\n${text().slice(0, 600)}`); await flush(10);}
  };
  const close = async () => {
    await act(async () => {root.unmount();}); dom.window.close();
    for (const [name, descriptor] of saved) {if (descriptor) Object.defineProperty(globalThis, name, descriptor); else Reflect.deleteProperty(globalThis, name);}
  };
  return {...h, dom, root, render, flush, text, all, button, click, type, tick, waitFor, close, copied};
}
