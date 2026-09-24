import assert from 'node:assert/strict';
import test from 'node:test';
import {setTimeout as delay} from 'node:timers/promises';
import {act, createElement} from 'react';
import {createRoot} from 'react-dom/client';
import {JSDOM} from 'jsdom';
import {App} from '../src/App.js';
import {searchFixture} from '../src/markets/fixtures.test-support.js';
import type {StockResearchConfig} from '../src/markets/config.js';
import {STORAGE_KEY} from '../src/state.js';

async function harness(config?: StockResearchConfig, response?: (url: URL) => Response) {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {url: 'https://trimmy.example', pretendToBeVisual: true});
  const descriptors = new Map<string, PropertyDescriptor | undefined>();
  const calls: {url: string; method: string}[] = [];
  function expose(name: string, value: unknown) {
    descriptors.set(name, Object.getOwnPropertyDescriptor(globalThis, name));
    Object.defineProperty(globalThis, name, {configurable: true, writable: true, value});
  }
  expose('window', dom.window); expose('document', dom.window.document); expose('navigator', dom.window.navigator);
  expose('HTMLElement', dom.window.HTMLElement); expose('Event', dom.window.Event); expose('IS_REACT_ACT_ENVIRONMENT', true);
  expose('fetch', async (input: string | URL | Request, init?: RequestInit) => {
    const url = new URL(String(input));
    calls.push({url: url.href, method: init?.method ?? 'GET'});
    assert.equal(url.origin, 'https://api.trimmy.test');
    return response?.(url) ?? new Response('{}', {status: 503});
  });
  Object.defineProperty(dom.window, 'matchMedia', {value: () => ({matches: false, addEventListener() {}, removeEventListener() {}})});
  dom.window.localStorage.setItem(STORAGE_KEY, JSON.stringify({version: 1, watchlist: ['mesa']}));
  const root = createRoot(dom.window.document.getElementById('root')!);
  const render = async () => { await act(async () => {
    root.render(createElement(App, config ? {researchConfiguration: config} : {}));
  }); };
  const click = async (label: string) => {
    const button = [...dom.window.document.querySelectorAll('button')]
      .find(item => item.textContent?.trim() === label || item.getAttribute('aria-label') === label);
    assert.ok(button, `Button exists: ${label}`);
    await act(async () => { button.click(); });
  };
  const text = () => dom.window.document.body.textContent ?? '';
  const close = async () => {
    await act(async () => { root.unmount(); });
    for (const [name, descriptor] of descriptors) {
      if (descriptor) Object.defineProperty(globalThis, name, descriptor);
      else Reflect.deleteProperty(globalThis, name);
    }
    dom.window.close();
  };
  await render();
  return {dom, root, render, click, text, calls, close};
}

test('normal workspace starts with truthful account state and requires an explicit sample choice', async () => {
  const h = await harness();
  try {
    assert.equal(h.dom.window.document.querySelector('h1')?.textContent, 'Portfolio');
    assert.match(h.text(), /Account sign-in is not available in this build yet/);
    assert.equal(h.text().includes('Forma Studio'), false);
    assert.equal(h.text().includes('Market value'), false);
    assert.equal(h.text().includes('$'), false);
    assert.equal(h.dom.window.document.querySelector('table'), null);
    assert.equal(h.calls.length, 0);

    await h.click('Explore');
    assert.equal(h.dom.window.document.querySelector('h1')?.textContent, 'Explore');
    assert.match(h.text(), /Stock research is unavailable in this build/);
    assert.equal(h.text().includes('Forma Studio'), false);

    await h.click('Sample workspace');
    assert.equal(h.dom.window.document.querySelector('h1')?.textContent, 'Sample portfolio');
    assert.match(h.text(), /Fictional companies and sample prices/);
    assert.match(h.text(), /Forma Studio/);
    await h.click('Add Grove Energy to watchlist');
    const saved = h.dom.window.localStorage.getItem(STORAGE_KEY);
    assert.deepEqual(JSON.parse(saved!).watchlist, ['mesa', 'grove']);
    await h.click('Back to stocks');
    assert.equal(h.text().includes('Forma Studio'), false);
    assert.equal(h.text().includes('Grove Energy'), false);
    assert.equal(h.dom.window.document.querySelector('table'), null);
    assert.equal(h.dom.window.localStorage.getItem(STORAGE_KEY), saved);
    assert.equal(h.calls.length, 0, 'switching modes never migrates sample IDs or sends a financial request');
    await h.click('Sample workspace');
    assert.ok(h.dom.window.document.querySelector('[aria-label="Remove Grove Energy from watchlist"]'));
  } finally { await h.close(); }
});

test('normal Explore owns provider search, stays read-only and never falls back to fictional rows', async () => {
  let fail = false;
  const h = await harness({kind: 'enabled', apiOrigin: 'https://api.trimmy.test'}, url => {
    if (fail) return new Response(JSON.stringify({error: {code: 'STOCK_PROVIDER_UNAVAILABLE', message: 'Unavailable', requestId: 'r1'}}),
      {status: 502, headers: {'content-type': 'application/json'}});
    const now = Date.now();
    return new Response(JSON.stringify({...searchFixture(url.searchParams.get('query')!, Number(url.searchParams.get('limit'))),
      requestedAt: new Date(now - 1000).toISOString(), observedAt: new Date(now).toISOString(),
      refreshAfter: new Date(now + 59_000).toISOString()}), {headers: {'content-type': 'application/json'}});
  });
  const search = async () => {
    const input = h.dom.window.document.querySelector('[aria-label="Search listed equities"]') as HTMLInputElement;
    assert.ok(input);
    await act(async () => {
      Object.getOwnPropertyDescriptor(h.dom.window.HTMLInputElement.prototype, 'value')!.set!.call(input, 'Apple');
      input.dispatchEvent(new h.dom.window.Event('input', {bubbles: true}));
      await delay(500);
    });
  };
  try {
    await h.click('Explore');
    assert.match(h.text(), /Search listed equities/);
    assert.equal(h.text().includes('Forma Studio'), false);
    assert.equal(h.dom.window.document.querySelector('.portfolio-overview'), null);
    assert.equal(h.calls.length, 0, 'opening Explore does not spend provider quota');
    await search();
    assert.match(h.text(), /AppleAAPL · 1 listed variant/);
    assert.equal(h.calls.length, 1);
    assert.ok(h.calls.every(call => call.method === 'GET' && new URL(call.url).pathname === '/v1/markets/stocks/search'));
    assert.equal(h.dom.window.document.querySelector('li > li'), null, 'provider results use a valid list structure');
    await h.click('Portfolio');
    fail = true;
    await h.click('Explore');
    await search();
    assert.match(h.text(), /unavailable|could not/i);
    assert.equal(h.text().includes('Forma Studio'), false);
    assert.equal(h.dom.window.document.querySelector('.research-assets'), null);
    assert.ok(h.calls.every(call => call.method === 'GET'));
  } finally { await h.close(); }
});
