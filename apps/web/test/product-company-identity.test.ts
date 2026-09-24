import assert from 'node:assert/strict';
import test from 'node:test';
import {act, createElement} from 'react';
import {JSDOM} from 'jsdom';
import {CompanyIdentityCache, useCompanyIdentities} from '../src/product/company-identity.js';
import type {CompanyIdentityClient} from '../src/product/company-identity.js';
import type {StockCard, StockCardsPage, StockFacts} from '../src/product/market-client.js';
import {CompanyLogo} from '../src/product/ui.js';

function facts(assetId: string, imageUrl: string | null = `https://api.tokens.xyz/${assetId}.webp`): StockFacts {
  return {schemaVersion: 1, provider: 'tokens-xyz-v1', requestedAt: '2026-09-24T12:00:00Z', observedAt: '2026-09-24T12:00:00Z',
    refreshAfter: '2026-09-24T12:01:00Z', displayOnly: true, executionEnabled: false, eligibility: 'unverified',
    assetId, name: `Company ${assetId}`, symbol: 'SAME', imageUrl, sourceUrls: ['https://api.tokens.xyz/'],
    description: null, stock: null, sparkline: null, sparklineStatus: 'unavailable'};
}
function deferred<T>() {let resolve!: (value: T) => void; const promise = new Promise<T>(done => {resolve = done;}); return {promise, resolve};}
function cards(query: string, results: readonly StockCard[]): StockCardsPage {
  const {assetId: _assetId, name: _name, symbol: _symbol, imageUrl: _imageUrl, sourceUrls: _sourceUrls,
    description: _description, stock: _stock, sparkline: _sparkline, sparklineStatus: _sparklineStatus, ...provenance} = facts('unused');
  return {...provenance, sourceUrl: 'https://api.tokens.xyz/', query, limit: 20, completeCatalog: false, results};
}
function card(assetId: string, imageUrl: string | null): StockCard {
  return {assetId, name: `Company ${assetId}`, symbol: 'SAME', imageUrl, stock: null, primaryVariant: null};
}

test('missing facts images fall back to the exact catalog asset, never the first result with a shared symbol', async () => {
  const calls: string[] = [];
  const cache = new CompanyIdentityCache({async facts(id) {return facts(id, null);}, async cards(query, options) {
    calls.push(query); assert.equal(options?.limit, 20);
    return cards(query, [card('other-hims', 'https://api.tokens.xyz/wrong.webp'), card('hims-and-hers', 'https://api.tokens.xyz/hims.webp')]);
  }});
  const signal = new AbortController().signal;
  assert.equal((await cache.read('hims-and-hers', signal)).imageUrl, 'https://api.tokens.xyz/hims.webp');
  await cache.read('hims-and-hers', signal); assert.deepEqual(calls, ['hims and hers']);
});

test('failed facts can recover the matching catalog primary-variant logo as mobile does', async () => {
  const cache = new CompanyIdentityCache({async facts() {throw new Error('facts unavailable');}, async cards(query) {
    return cards(query, [{...card('hims', null), primaryVariant: {mint: 'same-asset-primary-mint', symbol: 'HIMSx',
      logoUrl: 'https://api.tokens.xyz/hims-token.webp', priceUsd: null, changePercent24h: null}}]);
  }});
  const identity = await cache.read('hims', new AbortController().signal);
  assert.equal(identity.assetId, 'hims'); assert.equal(identity.imageUrl, 'https://api.tokens.xyz/hims-token.webp');
});

test('a catalog mismatch or missing image stays an honest fallback and can retry later', async () => {
  let calls = 0;
  const cache = new CompanyIdentityCache({async facts(id) {return facts(id, null);}, async cards(query) {
    calls++; return cards(query, calls === 1 ? [card('other-hims', 'https://api.tokens.xyz/wrong.webp')] : [card('hims', null)]);
  }});
  const signal = new AbortController().signal;
  assert.equal((await cache.read('hims', signal)).imageUrl, null);
  assert.equal((await cache.read('hims', signal)).imageUrl, null);
  assert.equal(cache.peek('hims'), undefined); assert.equal(calls, 2);
});

test('aborted catalog fallbacks cannot fill the image cache with a late result', async () => {
  const response = deferred<StockCardsPage>(); let started = false;
  const cache = new CompanyIdentityCache({async facts(id) {return facts(id, null);}, async cards() {started = true; return response.promise;}});
  const controller = new AbortController(), pending = cache.read('hims', controller.signal);
  await Promise.resolve(); assert.equal(started, true);
  controller.abort(); response.resolve(cards('hims', [card('hims', 'https://api.tokens.xyz/hims.webp')]));
  await assert.rejects(pending, {name: 'AbortError'}); assert.equal(cache.peek('hims'), undefined);
});

test('company identities use exact asset IDs even when tickers overlap, and cache successful images', async () => {
  const calls: string[] = [];
  const cache = new CompanyIdentityCache({async facts(id) {calls.push(id); return facts(id);}});
  const signal = new AbortController().signal;
  assert.equal((await cache.read('apple', signal)).imageUrl, 'https://api.tokens.xyz/apple.webp');
  assert.equal((await cache.read('other-apple', signal)).imageUrl, 'https://api.tokens.xyz/other-apple.webp');
  await cache.read('apple', signal);
  assert.deepEqual(calls, ['apple', 'other-apple']);
});

test('mismatched responses, failures and missing logos never poison a subsequent metadata retry', async () => {
  let attempt = 0;
  const cache = new CompanyIdentityCache({async facts(id) {
    attempt++;
    if (attempt === 1) return facts('wrong-company');
    if (attempt === 2) throw new Error('offline');
    return facts(id, attempt === 3 ? null : 'https://api.tokens.xyz/recovered.webp');
  }});
  const signal = new AbortController().signal;
  await assert.rejects(cache.read('apple', signal), /does not match/);
  await assert.rejects(cache.read('apple', signal), /offline/);
  assert.equal((await cache.read('apple', signal)).imageUrl, null);
  assert.equal(cache.peek('apple'), undefined);
  assert.equal((await cache.read('apple', signal)).imageUrl, 'https://api.tokens.xyz/recovered.webp');
  await cache.read('apple', signal); assert.equal(attempt, 4);
});

test('cancelled reads cannot enter the cache even when a transport completes after abort', async () => {
  const response = deferred<StockFacts>();
  const cache = new CompanyIdentityCache({facts: async () => response.promise});
  const controller = new AbortController();
  const read = cache.read('apple', controller.signal);
  controller.abort(); response.resolve(facts('apple'));
  await assert.rejects(read, {name: 'AbortError'}); assert.equal(cache.peek('apple'), undefined);
});

test('expired metadata is fetched again so changed provider artwork reaches the same asset', async () => {
  let time = 0, calls = 0;
  const cache = new CompanyIdentityCache({async facts(id) {return facts(id, `https://api.tokens.xyz/image-${++calls}.webp`);}}, () => time);
  const signal = new AbortController().signal;
  await cache.read('apple', signal); time = 15 * 60_000;
  assert.equal(cache.peek('apple'), undefined);
  assert.equal((await cache.read('apple', signal)).imageUrl, 'https://api.tokens.xyz/image-2.webp');
});

async function harness() {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {url: 'https://trimmy.example/'});
  const previous = new Map<string, PropertyDescriptor | undefined>();
  for (const [key, value] of Object.entries({window: dom.window, document: dom.window.document,
    navigator: dom.window.navigator, HTMLElement: dom.window.HTMLElement, IS_REACT_ACT_ENVIRONMENT: true})) {
    previous.set(key, Object.getOwnPropertyDescriptor(globalThis, key));
    Object.defineProperty(globalThis, key, {configurable: true, writable: true, value});
  }
  const {createRoot} = await import('react-dom/client');
  const root = createRoot(dom.window.document.getElementById('root')!);
  const render = async (element: ReturnType<typeof createElement>) => {await act(async () => {root.render(element);});};
  const close = async () => {await act(async () => {root.unmount();}); dom.window.close();
    for (const [key, descriptor] of previous) {if (descriptor) Object.defineProperty(globalThis, key, descriptor); else Reflect.deleteProperty(globalThis, key);}};
  return {dom, render, close};
}
function IdentityView({client, ids, revision = 0}: {client: CompanyIdentityClient; ids: readonly string[]; revision?: number}) {
  const identities = useCompanyIdentities(client, ids, revision);
  return createElement('div', {}, [...identities.values()].map(row => createElement('img', {key: row.assetId, 'data-asset-id': row.assetId, src: row.imageUrl ?? undefined, alt: row.name ?? row.assetId})));
}

test('identity hook discards removed asset responses and limits parallel optional metadata reads', async () => {
  const h = await harness();
  const requests: {id: string; signal?: AbortSignal; response: ReturnType<typeof deferred<StockFacts>>}[] = [];
  const client: CompanyIdentityClient = {async facts(id, options) {
    const response = deferred<StockFacts>(); requests.push({id, ...(options?.signal ? {signal: options.signal} : {}), response}); return response.promise;
  }};
  try {
    await h.render(createElement(IdentityView, {client, ids: ['a', 'b', 'c', 'd', 'e', 'a']}));
    assert.equal(requests.length, 4); assert.deepEqual(requests.map(row => row.id), ['a', 'b', 'c', 'd']);
    await h.render(createElement(IdentityView, {client, ids: ['new-company']}));
    assert.equal(requests.length, 5); assert.ok(requests.slice(0, 4).every(row => row.signal?.aborted));
    await act(async () => {for (const row of requests) row.response.resolve(facts(row.id));});
    assert.deepEqual([...h.dom.window.document.querySelectorAll('img')].map(row => row.dataset['assetId']), ['new-company']);
    assert.equal(requests.length, 5, 'the obsolete fifth request never starts');
  } finally {await h.close();}
});

test('portfolio refresh retries failed metadata and subsequent rerenders keep the cached image', async () => {
  const h = await harness(); let calls = 0;
  const client: CompanyIdentityClient = {async facts(id) {if (++calls === 1) throw new Error('offline'); return facts(id);}};
  try {
    await h.render(createElement(IdentityView, {client, ids: ['apple'], revision: 1}));
    assert.equal(h.dom.window.document.querySelector('img'), null);
    await h.render(createElement(IdentityView, {client, ids: ['apple'], revision: 2}));
    assert.equal(h.dom.window.document.querySelector('img')?.getAttribute('src'), 'https://api.tokens.xyz/apple.webp');
    await h.render(createElement(IdentityView, {client, ids: ['apple', 'apple'], revision: 3}));
    assert.equal(calls, 2);
  } finally {await h.close();}
});

test('company coin falls back on image failure and renders a changed source without retaining that failure', async () => {
  const h = await harness();
  try {
    await h.render(createElement(CompanyLogo, {name: ' Apple', url: 'https://api.tokens.xyz/old.webp'}));
    assert.ok(h.dom.window.document.querySelector('.company-logo-face > img'));
    await act(async () => {h.dom.window.document.querySelector('img')!.dispatchEvent(new h.dom.window.Event('error'));});
    assert.equal(h.dom.window.document.querySelector('img'), null);
    assert.equal(h.dom.window.document.querySelector('.company-logo-initial')?.textContent, 'A');
    await h.render(createElement(CompanyLogo, {name: ' Apple', url: 'https://api.tokens.xyz/new.webp', size: 36}));
    assert.equal(h.dom.window.document.querySelector('img')?.getAttribute('src'), 'https://api.tokens.xyz/new.webp');
    assert.equal((h.dom.window.document.querySelector('.company-coin') as HTMLElement).style.getPropertyValue('--company-coin-size'), '36px');
  } finally {await h.close();}
});
