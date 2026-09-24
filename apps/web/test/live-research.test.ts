import assert from 'node:assert/strict';
import test from 'node:test';
import { setTimeout as delay } from 'node:timers/promises';
import { act, createElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { JSDOM } from 'jsdom';
import { StockResearchClient } from '../src/markets/client.js';
import { LiveResearchStore, researchIssueMessage } from '../src/markets/live-research.js';
import { LiveResearchPanel } from '../src/markets/live-research-panel.js';
import { searchFixture, variantsFixture, estimateFixture } from '../src/markets/fixtures.test-support.js';
import { FIXED_NOW, raydiumQuoteFixture, stockHistoryFixture } from '../src/markets/read-contracts.test-support.js';

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {status, headers: {'content-type': 'application/json; charset=utf-8'}});
const error = (code: string, status: number) => json({error: {code, message: 'Fixed message.', requestId: 'r1'}}, status);

function makeFetch(overrides: {history?: () => Response; estimate?: () => Response} = {}) {
  const calls: string[] = [];
  const fetch: typeof globalThis.fetch = async input => {
    const url = new URL(String(input));
    calls.push(url.pathname);
    switch (url.pathname) {
      case '/v1/markets/stocks/search': return json(searchFixture(url.searchParams.get('query') ?? '', Number(url.searchParams.get('limit'))));
      case '/v1/markets/stocks/variants': return json(variantsFixture(url.searchParams.get('assetId') ?? 'apple'));
      case '/v1/markets/stocks/history': {
        if (overrides.history) return overrides.history();
        const page = stockHistoryFixture();
        const from = url.searchParams.get('fromUnixSeconds') ?? page.fromUnixSeconds;
        const to = url.searchParams.get('toUnixSeconds') ?? page.toUnixSeconds;
        const interval = url.searchParams.get('interval') ?? page.interval;
        // Keep the recorded candles inside the requested window so the strict
        // parser accepts the page as this request's own observation.
        const start = Number(from);
        const candles = page.candles.map((candle, index) => ({...candle, startUnixSeconds: String(start + index * 3600)}));
        return json({...page, fromUnixSeconds: from, toUnixSeconds: to, interval, candles,
          provenance: {...page.provenance, sourceUrl: page.provenance.sourceUrl.replace(/interval=[^&]+&from=\d+&to=\d+/, `interval=${interval}&from=${from}&to=${to}`)}});
      }
      case '/v1/markets/stocks/estimate': return overrides.estimate ? overrides.estimate() : json(estimateFixture('buy', url.searchParams.get('amountRaw') ?? '10000000'));
      case '/v1/markets/stocks/quotes/raydium': return json(raydiumQuoteFixture('buy', url.searchParams.get('amountRaw') ?? '10000000'));
      default: return error('NOT_FOUND', 404);
    }
  };
  return {fetch, calls};
}

test('live research panel loads nothing until asked and renders every read honestly', async () => {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {url: 'https://trimmy.example', pretendToBeVisual: true});
  const descriptors = new Map<string, PropertyDescriptor | undefined>();
  function global(name: string, value: unknown) {
    descriptors.set(name, Object.getOwnPropertyDescriptor(globalThis, name));
    Object.defineProperty(globalThis, name, {configurable: true, writable: true, value});
  }
  global('window', dom.window); global('document', dom.window.document); global('navigator', dom.window.navigator);
  global('HTMLElement', dom.window.HTMLElement); global('Event', dom.window.Event); global('IS_REACT_ACT_ENVIRONMENT', true);
  const root: Root = createRoot(dom.window.document.getElementById('root')!);
  const text = () => dom.window.document.body.textContent ?? '';
  const click = async (label: string) => {
    const button = [...dom.window.document.querySelectorAll('button')].find(item => item.textContent === label);
    assert.ok(button, `button ${label}; visible: ${text().slice(0, 300)}`);
    await act(async () => { button.dispatchEvent(new dom.window.MouseEvent('click', {bubbles: true})); });
  };
  const settle = async () => { for (let index = 0; index < 6; index++) await act(async () => { await delay(0); }); };
  let nowValue = FIXED_NOW;
  const now = () => nowValue;
  let online = true;
  const isOnline = () => online;
  const overrides: {history?: () => Response} = {};
  const {fetch, calls} = makeFetch(overrides);
  const client = new StockResearchClient({apiOrigin: 'http://127.0.0.1:4100', fetch, now, allowLoopbackForTests: true});
  const config = {kind: 'enabled', apiOrigin: 'http://127.0.0.1:4100'} as const;
  const render = async () => { await act(async () => { root.render(createElement(LiveResearchPanel, {config, client, now, online: isOnline})); }); };
  try {
    await render();
    assert.match(text(), /Live researchReal provider data, checked only when you ask\. Not a price you can trade at\.Read-only/);
    assert.equal(calls.length, 0, 'mounting must not spend provider quota');
    assert.match(text(), /Load hourly history/);
    assert.match(text(), /Load estimates/);

    await click('Load estimates');
    await settle();
    assert.deepEqual(calls, ['/v1/markets/stocks/estimate', '/v1/markets/stocks/quotes/raydium']);
    assert.match(text(), /Jupiter \(indicative\)10 USDC → about 184467440737\.09551615 AAPLx, minimum 184467440737\.09551614\./);
    assert.match(text(), /Raydium \(comparison only\)10 USDC → about 0\.02976495 AAPLx, minimum 0\.02961612\./);
    assert.match(text(), /neither chosen over the other, and neither executable/);
    assert.equal(text().includes('$'), false, 'no currency values');

    await click('Load hourly history');
    await settle();
    assert.equal(calls.at(-1), '/v1/markets/stocks/history');
    assert.match(text(), /2 hourly candles for the AAPLx mint/);
    assert.match(text(), /Last close value 201\.5\./);
    assert.match(text(), /not canonical Apple stock history/);
    assert.ok(dom.window.document.querySelector('.research-chart'), 'chart drawn from close values');

    const input = dom.window.document.querySelector('input[type=search]') as HTMLInputElement;
    await act(async () => {
      const setter = Object.getOwnPropertyDescriptor(dom.window.HTMLInputElement.prototype, 'value')!.set!;
      setter.call(input, 'Apple');
      input.dispatchEvent(new dom.window.Event('input', {bubbles: true}));
    });
    assert.equal(calls.filter(path => path.endsWith('/search')).length, 0, 'search is debounced');
    await act(async () => { await delay(500); });
    await settle();
    assert.equal(calls.filter(path => path.endsWith('/search')).length, 1);
    assert.match(text(), /AppleAAPL · 1 listed variant/);
    assert.match(text(), /Listing is not eligibility, ownership or a complete catalog\./);
    await click('See variants');
    await settle();
    assert.equal(calls.at(-1), '/v1/markets/stocks/variants');
    assert.match(text(), /AAPLxBacked · xstock/);
    assert.match(text(), /Provider figure 200\.5 \(display only, no timestamp\)/);

    // Freshness deadlines are read at render time.
    nowValue = Date.parse('2026-09-14T18:00:20.000Z');
    await render();
    assert.match(text(), /Jupiter \(indicative\)Out of date\. Check again\./);
    assert.match(text(), /Raydium \(comparison only\)Out of date\. Check again\./);
    assert.match(text(), /Out of date\. Check again\.2 hourly candles/);

    // A failed refresh keeps the last result visible and says why.
    overrides.history = () => error('STOCK_HISTORY_UNAVAILABLE', 503);
    nowValue = FIXED_NOW;
    await click('Check history again');
    await settle();
    assert.match(text(), /Not available on this server\. Showing the last result\./);
    assert.match(text(), /2 hourly candles/);

    // Offline never spends quota.
    online = false;
    const before = calls.length;
    await click('Check estimates again');
    await settle();
    assert.equal(calls.length, before);
    assert.match(text(), /You're offline\. Nothing was checked\./);
  } finally {
    await act(async () => { root.unmount(); });
    for (const [name, descriptor] of descriptors) {
      if (descriptor) Object.defineProperty(globalThis, name, descriptor);
      else delete (globalThis as Record<string, unknown>)[name];
    }
    dom.window.close();
  }
});

test('disabled and invalid research configuration render nothing or a plain reason', async () => {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {url: 'https://trimmy.example', pretendToBeVisual: true});
  const descriptors = new Map<string, PropertyDescriptor | undefined>();
  function global(name: string, value: unknown) {
    descriptors.set(name, Object.getOwnPropertyDescriptor(globalThis, name));
    Object.defineProperty(globalThis, name, {configurable: true, writable: true, value});
  }
  global('window', dom.window); global('document', dom.window.document); global('navigator', dom.window.navigator);
  global('HTMLElement', dom.window.HTMLElement); global('Event', dom.window.Event); global('IS_REACT_ACT_ENVIRONMENT', true);
  const root: Root = createRoot(dom.window.document.getElementById('root')!);
  try {
    await act(async () => { root.render(createElement(LiveResearchPanel, {config: {kind: 'disabled', apiOrigin: null}, client: null})); });
    assert.equal(dom.window.document.body.textContent, '');
    await act(async () => { root.render(createElement(LiveResearchPanel, {config: {kind: 'invalid', apiOrigin: null}, client: null})); });
    assert.match(dom.window.document.body.textContent ?? '', /Live research is not configured correctly for this workspace\./);
  } finally {
    await act(async () => { root.unmount(); });
    for (const [name, descriptor] of descriptors) {
      if (descriptor) Object.defineProperty(globalThis, name, descriptor);
      else delete (globalThis as Record<string, unknown>)[name];
    }
    dom.window.close();
  }
});

test('the store single-flights each read, aborts replacements and closes its client', async () => {
  const {fetch, calls} = makeFetch();
  const client = new StockResearchClient({apiOrigin: 'http://127.0.0.1:4100', fetch, now: () => FIXED_NOW, allowLoopbackForTests: true});
  const store = new LiveResearchStore({client, now: () => FIXED_NOW, online: () => true});
  const states: string[] = [];
  store.subscribe(() => states.push(store.getSnapshot().search.phase));
  const first = store.search('App');
  const second = store.search('Apple');
  await Promise.all([first, second]);
  assert.equal(store.getSnapshot().search.value?.query, 'Apple');
  assert.equal(store.getSnapshot().search.phase, 'ready');
  assert.equal(calls.filter(path => path.endsWith('/search')).length, 2);
  await store.search('   ');
  assert.equal(store.getSnapshot().search.phase, 'idle');
  assert.equal(store.getSnapshot().query, '');
  store.close();
  await store.history();
  assert.equal(store.getSnapshot().history.phase, 'idle', 'a closed store ignores reads');
  assert.equal(researchIssueMessage('STOCK_RATE_LIMITED'), 'Too many checks. Try again in a minute.');
  assert.equal(researchIssueMessage('anything-else'), 'This could not be checked.');
});
