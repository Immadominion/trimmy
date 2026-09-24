import assert from 'node:assert/strict';
import test from 'node:test';
import { act, createElement } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { JSDOM } from 'jsdom';
import { parsePreStocksCatalog, preStocksIssueMessage, premiumLabel, StockResearchError } from '../src/markets/prestocks.js';
import { PreStocksPanel } from '../src/markets/prestocks-panel.js';
import { StockResearchClient } from '../src/markets/client.js';

const anduril = 'PresTj4Yc2bAR197Er7wz4UUKSfqt6FryBEdAriBoQB';
const other = 'So11111111111111111111111111111111111111112';

function listing(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    name: 'Anduril PreStocks', symbol: 'ANDURIL', description: 'AI-driven defense systems.\n\nBacked 1:1.',
    imageUrl: 'https://www.prestocks.com/logos/anduril.png', externalUrl: 'https://www.prestocks.com/anduril',
    contractAddress: anduril, markPrice: '153.08544444', markValuation: '124426543782',
    tokenPrice: '160.0797154335478', impliedValuation: '130111427601', supply: '11805.98739435',
    premiumBasisPoints: 457, ...overrides,
  };
}
function catalog(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    schemaVersion: 1, kind: 'prestocks_catalog', provider: 'prestocks-v1',
    sourceUrl: 'https://prestocks.com/api/prestocks', requestedAt: '2026-09-15T15:00:00.000Z',
    observedAt: '2026-09-15T15:00:00.100Z', refreshAfter: '2026-09-15T15:01:00.000Z',
    providerFreshness: 'not_verified', priceKind: 'indicative', executionEnabled: false, eligibility: 'unverified',
    mintVerification: 'not_checked', notice: 'Indicative marks. No buying or selling here.', listings: [listing()],
    ...overrides,
  };
}

test('parses a valid catalog and preserves figure strings exactly', () => {
  const parsed = parsePreStocksCatalog(catalog());
  assert.equal(parsed.kind, 'prestocks_catalog');
  assert.equal(parsed.executionEnabled, false);
  assert.equal(parsed.listings.length, 1);
  const row = parsed.listings[0]!;
  assert.equal(row.symbol, 'ANDURIL');
  assert.equal(row.markPrice, '153.08544444');
  assert.equal(row.tokenPrice, '160.0797154335478');
  assert.equal(row.premiumBasisPoints, 457);
  assert.ok(Object.isFrozen(parsed) && Object.isFrozen(parsed.listings) && Object.isFrozen(row));
});

test('rejects a wrong shape, an extra key, a bad figure and duplicates', () => {
  const bad = (value: unknown) => assert.throws(() => parsePreStocksCatalog(value),
    (error: unknown) => error instanceof StockResearchError && error.code === 'STOCK_RESPONSE_INVALID');
  bad(catalog({executionEnabled: true}));
  bad(catalog({kind: 'other'}));
  bad(catalog({listings: []}));
  bad(catalog({extra: 1}));
  bad(catalog({listings: [listing({markPrice: '1.2.3'})]}));
  bad(catalog({listings: [listing({markPrice: -1})]}));
  bad(catalog({listings: [listing({symbol: 'lower'})]}));
  bad(catalog({listings: [listing({contractAddress: 'short'})]}));
  bad(catalog({listings: [listing({imageUrl: 'http://insecure.example/x.png'})]}));
  bad(catalog({listings: [listing(), listing({symbol: 'OTHER'})]})); // duplicate mint
  bad(catalog({listings: [listing(), listing({contractAddress: other})]})); // duplicate symbol
});

test('premium and issue-message helpers are safe', () => {
  assert.equal(premiumLabel(457), '+4.57%');
  assert.equal(premiumLabel(-120), '-1.20%');
  assert.equal(premiumLabel(0), '0.00%');
  assert.equal(premiumLabel(null), null);
  assert.equal(preStocksIssueMessage('PRESTOCKS_RATE_LIMITED'), 'Too many checks. Try again in a minute.');
  assert.match(preStocksIssueMessage('anything-else'), /unavailable/);
});

async function render(fetchImpl: typeof globalThis.fetch): Promise<{root: Root; dom: JSDOM; container: HTMLElement}> {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {url: 'https://workspace.example', pretendToBeVisual: true});
  const set = (name: string, value: unknown) =>
    Object.defineProperty(globalThis, name, {configurable: true, writable: true, value});
  set('window', dom.window); set('document', dom.window.document); set('navigator', dom.window.navigator);
  set('HTMLElement', dom.window.HTMLElement); set('Event', dom.window.Event); set('IS_REACT_ACT_ENVIRONMENT', true);
  const container = dom.window.document.getElementById('root') as unknown as HTMLElement;
  const client = new StockResearchClient({apiOrigin: 'https://api.example', fetch: fetchImpl});
  const root = createRoot(container);
  const config = {kind: 'enabled', apiOrigin: 'https://api.example'} as const;
  await act(async () => { root.render(createElement(PreStocksPanel, {config, client})); });
  return {root, dom, container};
}

test('the panel loads on demand and renders indicative listings without a buy control', async () => {
  const response = () => new Response(JSON.stringify(catalog({observedAt: new Date().toISOString(),
    refreshAfter: new Date(Date.now() + 60_000).toISOString(), requestedAt: new Date().toISOString()})),
  {status: 200, headers: {'content-type': 'application/json'}});
  const {root, container} = await render(async () => response());
  try {
    assert.match(container.textContent ?? '', /Pre-IPO stocks/);
    assert.match(container.textContent ?? '', /Read-only/);
    // Nothing is fetched until the reader is asked.
    assert.doesNotMatch(container.textContent ?? '', /ANDURIL/);
    const button = container.querySelector('button.prestocks-load') as HTMLButtonElement;
    assert.ok(button);
    await act(async () => { button.dispatchEvent(new (container.ownerDocument.defaultView as unknown as {MouseEvent: typeof MouseEvent}).MouseEvent('click', {bubbles: true})); });
    await act(async () => { for (let i = 0; i < 5; i++) await Promise.resolve(); });
    assert.match(container.textContent ?? '', /ANDURIL/);
    assert.match(container.textContent ?? '', /No buying or selling/);
    assert.match(container.textContent ?? '', /\+4\.57%/);
    // No buy, sell, amount or price-input control exists.
    assert.equal(container.querySelector('input'), null);
    assert.doesNotMatch((container.textContent ?? '').toLowerCase(), /\bbuy\b|\bsell\b/);
  } finally { await act(async () => { root.unmount(); }); }
});

test('the panel shows a safe message when the read fails', async () => {
  const {root, container} = await render(async () => new Response(JSON.stringify({error: {code: 'PRESTOCKS_RATE_LIMITED', message: 'slow down', requestId: 'r1'}}),
    {status: 429, headers: {'content-type': 'application/json'}}));
  try {
    const button = container.querySelector('button.prestocks-load') as HTMLButtonElement;
    await act(async () => { button.dispatchEvent(new (container.ownerDocument.defaultView as unknown as {MouseEvent: typeof MouseEvent}).MouseEvent('click', {bubbles: true})); });
    await act(async () => { for (let i = 0; i < 5; i++) await Promise.resolve(); });
    assert.match(container.textContent ?? '', /Too many checks/);
  } finally { await act(async () => { root.unmount(); }); }
});
