import assert from 'node:assert/strict';
import test from 'node:test';
import {webcrypto} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import {act, createElement, StrictMode} from 'react';
import type {ReactElement} from 'react';
import {createRoot} from 'react-dom/client';
import {JSDOM} from 'jsdom';
import {ProductApp} from '../src/product/ProductApp.js';
import {StockScreen} from '../src/product/stock-screen.js';
import {MarketScreen} from '../src/product/market-screen.js';
import {MobileAppPrompt} from '../src/product/onboarding.js';
import {micros, shares} from '../src/product/ui.js';
import {ProductMarketClient} from '../src/product/market-client.js';
import {PracticeClient, PORTFOLIO_MEDIA_TYPE, PROFILE_MEDIA_TYPE} from '../src/product/practice-client.js';
import type {PaperPortfolio, PaperPreview, PaperReceipt} from '../src/product/practice-client.js';
import {PracticeSession, practiceStorageKey} from '../src/product/practice-session.js';
import type {PracticeStorage} from '../src/product/practice-session.js';
import {searchFixture, variantFixture, variantsFixture} from '../src/markets/fixtures.test-support.js';
import {RESEARCH_AAPLX_MINT as MINT, RESEARCH_USDC_MINT as OTHER_MINT} from '../src/markets/estimate.js';

const GUEST_ID = '11111111-1111-4111-8111-111111111111';
const PREVIEW_ID = '22222222-2222-4222-8222-222222222222';
const ORDER_ID = '33333333-3333-4333-8333-333333333333';
class MemoryStorage implements PracticeStorage {
  readonly data = new Map<string, string>();
  getItem(key: string) {return this.data.get(key) ?? null;}
  setItem(key: string, value: string) {this.data.set(key, value);}
}
interface Call {path: string; url: URL; method: string; body: Record<string, unknown> | null}
type Reply = (call: Call) => Promise<Response> | Response | undefined;
function deferred<T>() {let resolve!: (value: T) => void; const promise = new Promise<T>(done => {resolve = done;}); return {promise, resolve};}
const json = (value: unknown, status = 200, media = 'application/json') => Response.json(value, {status, headers: {'content-type': media}});
function envelope(kind: 'preview' | 'order', value: unknown) {
  return {schemaVersion: 1, mode: 'paper', unit: {kind: 'paper', scaleDigits: 6}, [kind]: value,
    fees: {paperMicros: '0'}, reward: {trimsAwarded: 0, reason: 'Trade completion alone does not award Trims.'},
    execution: {walletUsed: false, transactionBuilt: false, transactionSigned: false, transactionBroadcast: false}};
}
function fixtures() {
  const now = Date.now(), at = new Date(now).toISOString();
  const provenance = {schemaVersion: 1, provider: 'tokens-xyz-v1', requestedAt: at, observedAt: at,
    refreshAfter: new Date(now + 60000).toISOString(), displayOnly: true, executionEnabled: false, eligibility: 'unverified'};
  const guest = {guestId: GUEST_ID, token: `tg1_${'A'.repeat(43)}`, expiresAt: new Date(now + 86400000).toISOString(), hardExpiresAt: new Date(now + 7 * 86400000).toISOString()};
  const profile = {revision: 1, onboarding: {goal: null, knowledge: null, persona: null, dailyGoal: null, handle: null}, launchCheckpoint: 'first-trade', hasConfirmedPaperTrade: false, createdAt: at, updatedAt: at};
  const card = {assetId: 'apple', name: 'Apple', symbol: 'AAPL', imageUrl: null,
    stock: {priceUsd: 51, changePercent24h: -1, asOfUnixSeconds: Math.floor(now / 1000)},
    primaryVariant: {mint: MINT, symbol: 'AAPLx', logoUrl: null, priceUsd: 50, changePercent24h: -0.5}};
  const source = {provider: 'tokens-xyz-v1' as const, providerReference: '/v1/assets/apple', marketSource: null, metricsSource: null,
    providerTimestamps: {asOf: null, lastFetchedAt: null, lastTradeAt: null, unit: 'not_declared' as const}, observedAt: at, acceptedAt: at};
  const preview = (requestId: string, lifetimeMs = 30000, paperMicros = '100000000'): PaperPreview => ({id: PREVIEW_ID, requestId, state: 'open', accountRevision: 0,
    action: 'buy', assetId: 'apple', variantMint: MINT, amount: {kind: 'paper_amount', paperMicros}, symbol: 'AAPLx',
    pricePaperMicros: '50000000', quantityMicros: (BigInt(paperMicros) / 50n).toString(), cashDebitPaperMicros: paperMicros, cashCreditPaperMicros: '0',
    cashAfterPaperMicros: (10000000000n - BigInt(paperMicros)).toString(), positionQuantityAfterMicros: (BigInt(paperMicros) / 50n).toString(), positionCostBasisAfterPaperMicros: paperMicros,
    realizedGainDeltaPaperMicros: '0', lockedGainDeltaPaperMicros: '0', source,
    expiresAt: new Date(now + lifetimeMs).toISOString(), committedAt: null});
  const receipt = (p: PaperPreview): PaperReceipt => ({...p, id: ORDER_ID, previewId: p.id, accountRevision: 1, committedAt: at});
  const portfolio = () => ({schemaVersion: 2, mode: 'paper', unit: {kind: 'paper', scaleDigits: 6}, revision: 0,
    startingCashPaperMicros: '10000000000', cashPaperMicros: '10000000000', openedAt: null, updatedAt: null,
    positions: [], recentOrders: [], valuation: {status: 'complete', portfolioRevision: 0, openPositionCount: 0, pricedPositionCount: 0,
      cashPaperMicros: '10000000000', knownValuePaperMicros: '10000000000', totalPaperMicros: '10000000000', positions: []}});
  const portfolioAfterBuy = (p: PaperPreview) => ({...portfolio(), revision: 1, cashPaperMicros: '9900000000', openedAt: at, updatedAt: at,
    positions: [{assetId: 'apple', variantMint: MINT, symbol: 'AAPLx', quantityMicros: '2000000', costBasisPaperMicros: '100000000',
      averageCostPricePaperMicros: '50000000', realizedGainPaperMicros: '0', lockedGainPaperMicros: '0', updatedAt: at}], recentOrders: [receipt(p)],
    valuation: {status: 'complete', portfolioRevision: 1, openPositionCount: 1, pricedPositionCount: 1, cashPaperMicros: '9900000000',
      knownValuePaperMicros: '10000000000', totalPaperMicros: '10000000000', positions: [{assetId: 'apple', variantMint: MINT, status: 'priced',
        pricePaperMicros: '50000000', marketValuePaperMicros: '100000000', unrealizedGainPaperMicros: '0', observedAt: at, acceptedAt: at,
        expiresAt: new Date(now + 60000).toISOString()}]}});
  const insight = (selectedMint = MINT, period = 'day') => ({...provenance, assetId: 'apple', mint: selectedMint, period,
    symbol: selectedMint === MINT ? 'AAPLx' : 'AAPLalt', description: 'Apple makes computers.', priceUsd: selectedMint === MINT ? 50 : 72,
    changePercent24h: -0.5, asOfUnixSeconds: Math.floor(now / 1000), volume24hUsd: 1000, liquidityUsd: 2000,
    tokenMarketCapUsd: 1000000, stockMarketCapUsd: 10000000000, holders: 30,
    points: [{unixSeconds: Math.floor(now / 1000) - 3600, close: 49}, {unixSeconds: Math.floor(now / 1000), close: selectedMint === MINT ? 50 : 72}], chartStatus: 'observed'});
  const discovery = {...searchFixture('catalog', 20), requestedAt: at, observedAt: at, refreshAfter: provenance.refreshAfter};
  const variantPage = {...variantsFixture('apple'), requestedAt: at, observedAt: at, refreshAfter: provenance.refreshAfter,
    variants: [variantFixture(), {...variantFixture(), variantId: 'apple-other', mint: OTHER_MINT, symbol: 'AAPLalt', label: 'Apple alternate'}]};
  return {now, at, guest, profile, card, preview, receipt, portfolio, portfolioAfterBuy, insight, provenance, discovery, variantPage};
}

async function harness(options: {storage?: MemoryStorage; reply?: Reply; hash?: string; profileMissing?: boolean} = {}) {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {url: `https://trimmy.example/${options.hash ?? ''}`, pretendToBeVisual: true});
  const saved = new Map<string, PropertyDescriptor | undefined>();
  function expose(name: string, value: unknown) {saved.set(name, Object.getOwnPropertyDescriptor(globalThis, name)); Object.defineProperty(globalThis, name, {configurable: true, writable: true, value});}
  expose('window', dom.window); expose('document', dom.window.document); expose('navigator', dom.window.navigator);
  expose('HTMLElement', dom.window.HTMLElement); expose('Event', dom.window.Event); expose('localStorage', dom.window.localStorage);
  expose('crypto', webcrypto); expose('IS_REACT_ACT_ENVIRONMENT', true);
  Object.defineProperty(dom.window, 'matchMedia', {value: () => ({matches: true, addEventListener() {}, removeEventListener() {}})});
  Object.defineProperty(dom.window, 'scrollTo', {value: () => {}});
  const locks = {request: async (_name: string, _options: unknown, callback: () => Promise<unknown>) => callback()} as Pick<LockManager, 'request'>;
  Object.defineProperty(dom.window.navigator, 'locks', {value: locks});
  const f = fixtures(), calls: Call[] = [], storage = options.storage ?? new MemoryStorage();
  let profileExists = !options.profileMissing, committed = false;
  if (profileExists) f.profile.launchCheckpoint = 'app';
  let lastPreview = f.preview(GUEST_ID);
  const fetcher: typeof fetch = async (url, init = {}) => {
    const parsed = new URL(String(url), 'https://trimmy.example');
    const call = {path: parsed.pathname.replace(/^\/api/, ''), url: parsed, method: init.method ?? 'GET', body: init.body ? JSON.parse(String(init.body)) as Record<string, unknown> : null};
    calls.push(call); const override = options.reply?.(call); if (override !== undefined) return override;
    if (call.path === '/v1/guest/session') return json({schemaVersion: 1, requestId: call.body?.['requestId'], ...f.guest}, 201);
    if (call.path === '/v1/guest/session/refresh') return json({schemaVersion: 1, ...f.guest});
    if (call.path === '/v1/product/profile') {
      if (call.method === 'PUT') {profileExists = true; Object.assign(f.profile, {revision: Number(call.body?.['baseRevision']) + 1,
        onboarding: call.body?.['onboarding'], launchCheckpoint: call.body?.['launchCheckpoint']});}
      return json({schemaVersion: 2, profile: profileExists ? f.profile : null}, 200, PROFILE_MEDIA_TYPE);
    }
    if (call.path === '/v1/product/launch') {
      if (!profileExists || f.profile.launchCheckpoint === 'app' || call.body?.['baseRevision'] !== f.profile.revision) {
        return json({error: {code: 'PRODUCT_PROFILE_CHECKPOINT_CONFLICT', message: 'Checkpoint conflict.', requestId: GUEST_ID}}, 409);
      }
      if (call.body?.['action'] === 'introduction-completed' && !f.profile.hasConfirmedPaperTrade) {
        return json({error: {code: 'PRODUCT_PROFILE_LAUNCH_EVIDENCE_REQUIRED', message: 'Trade required.', requestId: GUEST_ID}}, 409);
      }
      f.profile.revision++; f.profile.launchCheckpoint = 'app';
      return json({schemaVersion: 2, profile: f.profile}, 200, PROFILE_MEDIA_TYPE);
    }
    if (call.path === '/v1/account/paper/portfolio') return json(committed ? f.portfolioAfterBuy(lastPreview) : f.portfolio(), 200, PORTFOLIO_MEDIA_TYPE);
    if (call.path === '/v1/account/paper/orders/preview') {
      const amount = call.body?.['amount'] as {paperMicros?: string} | undefined;
      lastPreview = f.preview(String(call.body?.['requestId']), 30000, amount?.paperMicros ?? '100000000');
      return json(envelope('preview', lastPreview));
    }
    if (call.path === '/v1/account/paper/orders/commit') {committed = true; f.profile.hasConfirmedPaperTrade = true; return json(envelope('order', f.receipt(lastPreview)));}
    if (call.path === '/v1/career/summary') return json({schemaVersion: 1, career: {revision: 0, trims: {total: 0, today: 0, thisWeek: 0},
      rank: {id: 'rookie', label: 'Rookie', paperLimit: '10000', threshold: 0}, nextRank: {id: 'analyst', label: 'Analyst', threshold: 300, trimsRemaining: 300, promotionRequired: true},
      streak: {days: 0, status: 'not-started', lastActiveDate: null}, careerStarted: false, firstConfirmedBuy: null, serverDate: f.at.slice(0, 10), updatedAt: null}});
    if (call.path === '/v1/career/missions') return json({schemaVersion: 1, career: {revision: 0, currentRank: 'rookie'}, missions: []});
    if (call.path.endsWith('/catalog')) return json({discovery: f.discovery, cards: [f.card], offset: 0, total: 1, nextOffset: null});
    if (call.path.endsWith('/search')) {
      const page = {...searchFixture(parsed.searchParams.get('query')!, Number(parsed.searchParams.get('limit'))),
        requestedAt: f.at, observedAt: f.at, refreshAfter: f.provenance.refreshAfter};
      const apple = page.results[0]!;
      page.results = [apple, ...[{assetId: 'tesla', name: 'Tesla', symbol: 'TSLA', mint: OTHER_MINT},
        {assetId: 'meta', name: 'Meta', symbol: 'META', mint: '11111111111111111111111111111111'}].map(company => ({...apple,
          assetId: company.assetId, name: company.name, symbol: company.symbol, providerPrimaryVariantMint: company.mint,
          variants: [{...variantFixture(), variantId: `${company.assetId}-xstock`, mint: company.mint,
            name: `${company.name} xStock`, label: `${company.name} xStock`, symbol: `${company.symbol}x`}]}))];
      return json(page);
    }
    if (call.path.endsWith('/cards')) return json({...f.provenance, sourceUrl: 'https://api.tokens.xyz/v1/assets/search', query: parsed.searchParams.get('query'), limit: 20, completeCatalog: false, results: [f.card]});
    if (call.path.endsWith('/facts')) return json({...f.provenance, sourceUrls: ['https://api.tokens.xyz/v1/assets/apple'], assetId: 'apple', name: 'Apple', symbol: 'AAPL', imageUrl: null, description: 'Apple makes computers.', stock: f.card.stock, sparkline: null, sparklineStatus: 'unavailable'});
    if (call.path.endsWith('/variants')) return json(f.variantPage);
    if (call.path.endsWith('/insight')) return json(f.insight(parsed.searchParams.get('mint')!, parsed.searchParams.get('period')!));
    throw new Error(`Unexpected test request: ${call.method} ${call.path}`);
  };
  const practice = new PracticeClient({baseUrl: '/api', fetch: fetcher, timeoutMs: 1000});
  const market = new ProductMarketClient({baseUrl: '/api', fetch: fetcher, timeoutMs: 1000});
  const session = new PracticeSession({client: practice, storage});
  const root = createRoot(dom.window.document.getElementById('root')!);
  const flush = async (ms = 25) => {await act(async () => {await delay(ms);});};
  const render = async (element: ReactElement) => {await act(async () => {root.render(element);}); await flush();};
  const app = (strict = false) => {const element = createElement(ProductApp, {apiBase: '/api', practiceClient: practice, marketClient: market, storage}); return render(strict ? createElement(StrictMode, null, element) : element);};
  const text = () => dom.window.document.body.textContent ?? '';
  const button = (label: string) => [...dom.window.document.querySelectorAll<HTMLButtonElement>('button')].find(item => item.textContent?.trim() === label || item.getAttribute('aria-label') === label);
  const click = async (label: string) => {const target = button(label); assert.ok(target, `Button exists: ${label}`); await act(async () => {target.click();}); await flush();};
  const stock = (callbacks: {onCommitted?: (receipt: PaperReceipt) => Promise<void>; onPending?: () => void; portfolio?: PaperPortfolio} = {}) => render(createElement(StockScreen, {
    assetId: 'apple', card: f.card, selectedMint: MINT, market, session, portfolio: callbacks.portfolio ?? null,
    ensureDesk: async () => {if (!session.guest) await session.ensureGuest(); await session.ensureProfile();},
    onBack() {}, onDesk() {}, onCommitted: callbacks.onCommitted ?? (async () => {}), onPending: callbacks.onPending ?? (() => {}),
  }));
  const close = async () => {await act(async () => {root.unmount();}); market.close(); dom.window.close(); for (const [name, descriptor] of saved) {if (descriptor) Object.defineProperty(globalThis, name, descriptor); else Reflect.deleteProperty(globalThis, name);}};
  return {dom, f, root, storage, session, practice, market, calls, flush, render, app, stock, text, button, click, close};
}

async function firstDayPractice(h: Awaited<ReturnType<typeof harness>>) {
  await h.app(); await h.click('Start my first day'); await h.click('Continue');
  assert.ok(h.button('Choose Apple'), 'the real starter company choices are shown');
}

test('first-day Welcome opens the short note locally without creating a desk or profile', async () => {
  const h = await harness({profileMissing: true});
  try {
    await h.app(); await h.click('Start my first day');
    assert.match(h.text(), /Welcome to the floor\./);
    assert.match(h.text(), /Your first day starts with practice/);
    assert.equal(h.calls.some(call => call.method !== 'GET'), false);
    assert.equal(h.storage.data.size, 0);
    assert.equal(h.button('Choose Apple'), undefined);
  } finally {await h.close();}
});

test('Skip waits for its saved app checkpoint before opening an empty Desk and awards no fake progress', async () => {
  const pending = deferred<Response>();
  const h = await harness({profileMissing: true, reply: call => call.path === '/v1/product/launch' ? pending.promise : undefined});
  try {
    await h.app(); await h.click('Start my first day');
    const skip = h.button('Skip first day'); assert.ok(skip);
    await act(async () => {skip.click(); skip.click();}); await h.flush();
    assert.match(h.text(), /Welcome to the floor\./);
    assert.equal(h.dom.window.document.querySelector('.balance-card'), null);
    const launch = h.calls.filter(call => call.path === '/v1/product/launch');
    assert.equal(launch.length, 1); assert.equal(launch[0]?.body?.['action'], 'introduction-skipped');
    assert.equal(launch[0]?.body?.['baseRevision'], 1);
    assert.equal(h.calls.some(call => call.path.includes('/orders/')), false);
    Object.assign(h.f.profile, {revision: 2, launchCheckpoint: 'app'});
    pending.resolve(json({schemaVersion: 2, profile: h.f.profile}, 200, PROFILE_MEDIA_TYPE)); await h.flush();
    assert.match(h.text(), /Your desk\./); assert.match(h.text(), /10,000\.00/);
    assert.equal(h.dom.window.document.querySelector('.position-row'), null);
    assert.equal(h.dom.window.document.querySelector('.activity-row'), null);
    assert.doesNotMatch(h.text(), /Buy confirmed|Your first move is made|\+20 Trims|day streak/);
  } finally {pending.resolve(json({schemaVersion: 2, profile: {...h.f.profile, launchCheckpoint: 'app'}}, 200, PROFILE_MEDIA_TYPE)); await h.close();}
});

test('Continue creates nullable profile v2 and shows three server companies without silently selecting one', async () => {
  const h = await harness({profileMissing: true});
  try {
    await firstDayPractice(h);
    for (const name of ['Apple', 'Tesla', 'Meta']) assert.equal(h.button(`Choose ${name}`)?.getAttribute('aria-pressed'), 'false');
    assert.equal(h.button('Review paper buy')?.disabled, true);
    const writes = h.calls.filter(call => call.path === '/v1/product/profile' && call.method === 'PUT');
    assert.equal(writes.length, 1);
    assert.equal(writes[0]?.body?.['schemaVersion'], 2); assert.equal(writes[0]?.body?.['baseRevision'], 0);
    assert.deepEqual(writes[0]?.body?.['onboarding'], {goal: null, knowledge: null, persona: null, dailyGoal: null, handle: null});
    assert.equal(writes[0]?.body?.['launchCheckpoint'], 'first-trade');
    assert.equal(h.calls.some(call => call.path.includes('/orders/') || call.path === '/v1/product/launch'), false);
    assert.equal(h.calls.filter(call => call.path === '/v1/guest/session').length, 1);
  } finally {await h.close();}
});

test('review Edit and Escape retain the selected company and amount without committing', async () => {
  const h = await harness({profileMissing: true});
  try {
    await firstDayPractice(h); await h.click('Choose Apple'); await h.click('50'); await h.click('Review paper buy');
    assert.match(h.text(), /Review your first move\./);
    const first = h.calls.find(call => call.path.endsWith('/preview'))!;
    assert.deepEqual(first.body?.['amount'], {kind: 'paper_amount', paperMicros: '50000000'});
    await h.click('Edit amount');
    assert.equal(h.button('Choose Apple')?.getAttribute('aria-pressed'), 'true');
    assert.equal(h.dom.window.document.querySelector<HTMLInputElement>('input[inputmode="decimal"]')?.value, '50');
    await h.click('Review paper buy');
    await act(async () => {h.dom.window.dispatchEvent(new h.dom.window.KeyboardEvent('keydown', {key: 'Escape', bubbles: true}));}); await h.flush();
    assert.equal(h.button('Choose Apple')?.getAttribute('aria-pressed'), 'true');
    assert.equal(h.dom.window.document.querySelector<HTMLInputElement>('input[inputmode="decimal"]')?.value, '50');
    assert.equal(h.calls.filter(call => call.path.endsWith('/preview')).length, 2);
    assert.equal(h.calls.some(call => call.path.endsWith('/commit') || call.path === '/v1/product/launch'), false);
  } finally {await h.close();}
});

test('first-day receipt is confirmed before its separate Finish action and opens the real resulting Desk', async () => {
  const h = await harness({profileMissing: true});
  try {
    await firstDayPractice(h); await h.click('Choose Apple'); await h.click('Review paper buy');
    assert.equal(h.calls.some(call => call.path.endsWith('/commit')), false);
    await h.click('Confirm paper buy');
    assert.match(h.text(), /Your first move is made\./); assert.match(h.text(), /100\.00/);
    assert.equal(h.calls.filter(call => call.path.endsWith('/commit')).length, 1);
    assert.equal(h.calls.some(call => call.path === '/v1/product/launch'), false, 'receipt stays visible before Finish');
    assert.doesNotMatch(h.text(), /\+20 Trims|Day 1 earned/);
    const saved = JSON.parse(h.storage.getItem(practiceStorageKey('/api'))!) as {lastReceipt: {id: string}; pendingCommit: unknown};
    assert.equal(saved.lastReceipt.id, ORDER_ID); assert.equal(saved.pendingCommit, null);
    await h.click('Go to my desk');
    const launches = h.calls.filter(call => call.path === '/v1/product/launch');
    assert.equal(launches.length, 1); assert.equal(launches[0]?.body?.['action'], 'introduction-completed');
    assert.match(h.text(), /Your desk\./);
    assert.match(h.dom.window.document.querySelector('.position-row')?.textContent ?? '', /AppleAAPLx · 2 shares/);
    assert.match(h.dom.window.document.querySelector('.balance-details')?.textContent ?? '', /9,900\.00/);
    assert.equal(h.calls.filter(call => call.path.endsWith('/commit')).length, 1);
  } finally {await h.close();}
});

test('an in-flight first-day confirmation blocks duplicate submit, Skip and Back until its receipt arrives', async () => {
  const pending = deferred<Response>(); let confirmed = false;
  const h = await harness({profileMissing: true, reply: call => {
    if (call.path.endsWith('/commit')) return pending.promise;
    if (call.path.endsWith('/portfolio') && confirmed) return json(h.f.portfolioAfterBuy(h.f.preview(GUEST_ID)), 200, PORTFOLIO_MEDIA_TYPE);
    return undefined;
  }});
  try {
    await firstDayPractice(h); await h.click('Choose Apple'); await h.click('Review paper buy');
    const confirm = h.button('Confirm paper buy'); assert.ok(confirm);
    await act(async () => {confirm.click(); confirm.click();}); await h.flush();
    assert.equal(h.calls.filter(call => call.path.endsWith('/commit')).length, 1);
    assert.equal(h.button('Skip first day')?.disabled, true);
    await h.click('Skip first day');
    await act(async () => {
      h.dom.window.dispatchEvent(new h.dom.window.KeyboardEvent('keydown', {key: 'Escape', bubbles: true}));
      h.dom.window.dispatchEvent(new h.dom.window.PopStateEvent('popstate'));
    }); await h.flush();
    assert.match(h.text(), /Review your first move\./);
    assert.equal(h.calls.some(call => call.path === '/v1/product/launch'), false);
    confirmed = true; h.f.profile.hasConfirmedPaperTrade = true;
    pending.resolve(json(envelope('order', h.f.receipt(h.f.preview(GUEST_ID))))); await h.flush();
    assert.match(h.text(), /Your first move is made\./);
    assert.equal(h.calls.filter(call => call.path.endsWith('/commit')).length, 1);
  } finally {pending.resolve(json(envelope('order', h.f.receipt(h.f.preview(GUEST_ID))))); await h.close();}
});

test('a failed Finish keeps its confirmed receipt and retries the exact saved exit without buying again', async () => {
  let failed = false;
  const h = await harness({profileMissing: true, reply: call => {
    if (call.path === '/v1/product/launch' && !failed) {failed = true; throw new TypeError('Finish response lost');}
    return undefined;
  }});
  try {
    await firstDayPractice(h); await h.click('Choose Apple'); await h.click('Review paper buy'); await h.click('Confirm paper buy');
    await h.click('Go to my desk');
    assert.match(h.text(), /Your first move is made\./);
    const first = h.calls.find(call => call.path === '/v1/product/launch')!.body;
    assert.equal(first?.['action'], 'introduction-completed');
    await h.click('Go to my desk');
    assert.match(h.text(), /Your desk\./);
    const exits = h.calls.filter(call => call.path === '/v1/product/launch');
    assert.equal(exits.length, 2); assert.deepEqual(exits[1]?.body, first);
    assert.equal(h.calls.filter(call => call.path.endsWith('/commit')).length, 1);
    assert.match(h.dom.window.document.querySelector('.position-row')?.textContent ?? '', /AppleAAPLx · 2 shares/);
  } finally {await h.close();}
});

test('practice Back exits the entire introduction without sending an order', async () => {
  const h = await harness({profileMissing: true});
  try {
    await firstDayPractice(h); await h.click('Choose Apple'); await h.click('50');
    await act(async () => {h.dom.window.dispatchEvent(new h.dom.window.PopStateEvent('popstate'));}); await h.flush();
    assert.match(h.text(), /Your desk\./);
    assert.equal(h.calls.find(call => call.path === '/v1/product/launch')?.body?.['action'], 'introduction-skipped');
    assert.equal(h.calls.some(call => call.path.includes('/orders/')), false);
    assert.equal(h.dom.window.document.querySelector('.position-row'), null);
  } finally {await h.close();}
});

test('an interrupted Skip keeps the note and reload replays the same exit before opening Desk', async () => {
  let failed = false;
  const h = await harness({profileMissing: true, reply: call => {
    if (call.path === '/v1/product/launch' && !failed) {failed = true; throw new TypeError('Lost exit response');}
    return undefined;
  }});
  try {
    await h.app(); await h.click('Start my first day'); await h.click('Skip first day');
    assert.match(h.text(), /Welcome to the floor\./); assert.equal(h.dom.window.document.querySelector('.balance-card'), null);
    const first = h.calls.find(call => call.path === '/v1/product/launch')!.body;
    await h.render(createElement('div', null, 'Reloading')); await h.app();
    assert.match(h.text(), /Your desk\./);
    const launches = h.calls.filter(call => call.path === '/v1/product/launch');
    assert.equal(launches.length, 2); assert.deepEqual(launches[1]?.body, first);
    assert.equal(h.calls.some(call => call.path.includes('/orders/')), false);
  } finally {await h.close();}
});

test('confirmed-buy evidence bypasses first-day reentry even when its finish checkpoint was not saved', async () => {
  for (const hash of ['', '#start']) {
    const h = await harness({hash, reply: call => call.path.endsWith('/portfolio')
      ? json(h.f.portfolioAfterBuy(h.f.preview(GUEST_ID)), 200, PORTFOLIO_MEDIA_TYPE) : undefined});
    try {
      h.f.profile.launchCheckpoint = 'first-trade'; h.f.profile.hasConfirmedPaperTrade = true;
      await h.session.ensureGuest(); await h.app();
      assert.match(h.text(), /Your desk\./); assert.equal(h.button('Choose Apple'), undefined);
      assert.equal(h.button('Confirm paper buy'), undefined); assert.equal(h.button('Start my first day'), undefined);
      assert.equal(h.calls.some(call => call.path.includes('/orders/')), false);
      assert.equal(h.calls.filter(call => call.path === '/v1/guest/session').length, 1);
    } finally {await h.close();}
  }
});

test('explicit Welcome lets a saved app desk meet Trimmy and Continue returns without a new trade or rewrite', async () => {
  const h = await harness({hash: '#welcome'});
  try {
    // A routine restoration is outside the refresh window, like a newly saved real guest.
    h.f.guest.expiresAt = new Date(h.f.now + 30 * 86400000).toISOString();
    h.f.guest.hardExpiresAt = new Date(h.f.now + 60 * 86400000).toISOString();
    await h.session.ensureGuest();
    const saved = h.storage.getItem(practiceStorageKey('/api')), callCount = h.calls.length;
    await h.app(); assert.match(h.text(), /Your first day starts here\./);
    await h.click('Start my first day'); assert.match(h.text(), /Welcome to the floor\./);
    await h.click('Continue'); assert.match(h.text(), /Your desk\./);
    assert.equal(h.button('Choose Apple'), undefined); assert.equal(h.button('Confirm paper buy'), undefined);
    assert.equal(h.calls.slice(callCount).some(call => call.method !== 'GET'), false);
    assert.equal(h.calls.some(call => call.path.includes('/orders/')), false);
    assert.equal(h.storage.getItem(practiceStorageKey('/api')), saved);
    assert.equal(h.dom.window.location.hash, '#desk');
  } finally {await h.close();}
});

test('saved guest Profile opens sign-in without replaying onboarding or changing progress', async () => {
  const h = await harness();
  try {
    h.f.guest.expiresAt = new Date(h.f.now + 30 * 86400000).toISOString();
    h.f.guest.hardExpiresAt = new Date(h.f.now + 60 * 86400000).toISOString();
    await h.session.ensureGuest(); await h.app(); await h.click('Profile');
    assert.ok(h.button('Sign in or create account')); assert.equal(h.button('Meet Trimmy'), undefined);
    assert.equal(h.button('Start my first day'), undefined);
    const saved = h.storage.getItem(h.session.storageKey), callCount = h.calls.length;
    await h.click('Sign in or create account'); await h.flush();
    assert.match(h.text(), /Make this desk yours\./);
    assert.ok(h.dom.window.document.querySelector('section[aria-label="Sign in"]'));
    assert.equal(h.button('Continue with email')?.disabled, true, 'an unconfigured test never starts provider auth');
    assert.equal(h.calls.length, callCount); assert.equal(h.storage.getItem(h.session.storageKey), saved);
    await h.click('Close sign in'); assert.match(h.text(), /Your desk\./);
    assert.equal(h.f.profile.launchCheckpoint, 'app');
    assert.ok(h.calls.slice(callCount).every(call => call.method === 'GET'), 'returning to Desk revalidates shared progress without writing'); assert.equal(h.storage.getItem(h.session.storageKey), saved);
  } finally {await h.close();}
});

test('fresh root shows onboarding without rewriting its URL or opening authentication', async () => {
  const h = await harness({profileMissing: true});
  try {
    await h.app();
    assert.match(h.text(), /Your first day starts here\./);
    assert.ok(h.button('Start my first day')); assert.ok(h.button('Sign in'));
    assert.equal(h.dom.window.location.pathname, '/'); assert.equal(h.dom.window.location.hash, '');
    assert.equal(h.dom.window.document.querySelector('section[aria-label="Sign in"]'), null);
    assert.equal(h.dom.window.document.querySelector('.auth-restore'), null);
    assert.equal(h.calls.length, 0); assert.equal(h.storage.data.size, 0);
  } finally {await h.close();}
});

test('main pages retain navigation without removed breadcrumbs, badges or manual refresh chrome', async () => {
  const h = await harness();
  try {
    await h.session.ensureGuest(); await h.app();
    for (const page of ['Desk', 'Career', 'Market', 'Profile']) {
      await h.click(page);
      const nav = h.dom.window.document.querySelector('nav[aria-label="Main navigation"]'); assert.ok(nav);
      assert.deepEqual([...nav.querySelectorAll('button')].map(button => button.textContent?.trim()), ['Desk', 'Market', 'Career', 'Profile']);
      assert.equal(nav.querySelector('[aria-current="page"]')?.textContent?.trim(), page);
      assert.equal(h.dom.window.document.querySelector('.product-topbar, .topbar-path, .practice-pill, .guest-button, .nav-foot'), null);
      for (const label of ['Your guest profile', 'Refresh desk', 'Refresh progress', 'Refresh prices', 'Meet Trimmy']) assert.equal(h.button(label), undefined);
      assert.doesNotMatch(h.text(), /Your Wall Street starts here\.|Real market prices\.|Guest desk/);
    }
  } finally {await h.close();}
});

test('Market results form a labelled keyboard-focusable region below the fixed search and column labels', async () => {
  const h = await harness({hash: '#market'});
  try {
    await h.app();
    const doc = h.dom.window.document;
    const section = doc.querySelector('section[aria-label="Market"]'); assert.ok(section);
    const results = section.querySelector<HTMLElement>('[role="region"][aria-label="Companies"]'); assert.ok(results);
    const search = section.querySelector<HTMLInputElement>('#company-search'); assert.ok(search);
    const columns = section.querySelector('.stock-list-head'); assert.ok(columns);
    assert.equal(results.tabIndex, 0);
    assert.equal(results.contains(search), false); assert.equal(results.contains(columns), false);
    assert.ok(results.querySelector('button[aria-label="Open Apple"]'));
    assert.equal(results.querySelector('nav, h1, #company-search'), null);
    assert.ok(doc.querySelector('.product-shell.market-shell'));
    results.focus(); assert.equal(doc.activeElement, results);
    assert.equal(h.calls.some(call => call.method !== 'GET'), false); assert.equal(h.storage.data.size, 0);
  } finally {await h.close();}
});

test('an unconfigured mobile download prompt does not invent an APK link', async () => {
  const h = await harness();
  try {
    await h.render(createElement(MobileAppPrompt));
    assert.match(h.text(), /Better on mobile\./); assert.match(h.text(), /Download coming soon/);
    assert.doesNotMatch(h.text(), /Download for Android|APK download/);
    const downloadLinks = [...h.dom.window.document.querySelectorAll<HTMLAnchorElement>('a')]
      .filter(anchor => /download|\.apk(?:$|[?#])/i.test(`${anchor.textContent ?? ''} ${anchor.href}`));
    assert.equal(downloadLinks.length, 0); assert.equal(h.calls.length, 0);
  } finally {await h.close();}
});

test('exploring companies never silently creates a guest or displays invented holdings', async () => {
  const h = await harness();
  try {
    await h.app(); assert.match(h.text(), /Your first day starts here/); assert.equal(h.calls.length, 0); assert.equal(h.storage.data.size, 0);
    await h.click('Take a look around'); assert.match(h.text(), /Apple/); assert.match(h.text(), /\$51\.00/);
    await h.click('Open Apple'); assert.match(h.text(), /Selected token · USD reference/); assert.match(h.text(), /\$50\.00/);
    assert.equal(h.calls.some(call => call.method !== 'GET'), false); assert.equal(h.storage.data.size, 0);
    assert.doesNotMatch(h.text(), /Forma Studio|Grove Energy|Sample portfolio/);
  } finally {await h.close();}
});

test('restoration reads the existing server desk and does not issue a second guest', async () => {
  const h = await harness();
  try {
    await h.session.ensureGuest(); const created = h.calls.length;
    await h.app(); assert.match(h.text(), /Your desk\./); assert.match(h.text(), /10,000\.00/);
    assert.equal(h.calls.slice(created).some(call => call.path === '/v1/guest/session'), false);
    assert.equal(h.calls.some(call => call.path === '/v1/guest/session/refresh'), true);
    assert.equal(h.calls.some(call => call.path === '/v1/account/paper/portfolio'), true);
  } finally {await h.close();}
});

test('StrictMode effect replay restores an existing guest rather than stranding a busy session', async () => {
  const h = await harness();
  try {
    await h.session.ensureGuest(); await h.app(true); await h.flush();
    assert.match(h.text(), /Your desk\./); assert.match(h.text(), /10,000\.00/);
    assert.doesNotMatch(h.text(), /Your desk needs a moment/);
    assert.equal(h.calls.filter(call => call.path === '/v1/guest/session').length, 1);
  } finally {await h.close();}
});

test('corrupt saved credentials are preserved and cannot be replaced by first-day navigation', async () => {
  const storage = new MemoryStorage(); storage.setItem(practiceStorageKey('/api'), 'corrupt saved data');
  // ProductApp owns the recovery state; avoid constructing the harness's independent session from corrupt storage.
  const h = await harness();
  try {
    await h.render(createElement(ProductApp, {apiBase: '/api', practiceClient: h.practice, marketClient: h.market, storage}));
    assert.match(h.text(), /Your desk needs a moment/);
    if (h.button('Start my first day')) {await h.click('Start my first day'); if (h.button('Continue')) await h.click('Continue');}
    else await h.click('Try again');
    assert.equal(storage.getItem(practiceStorageKey('/api')), 'corrupt saved data'); assert.equal(h.calls.length, 0);
  } finally {await h.close();}
});

test('paper trading requires a separate review then explicit confirmation through the real boundary', async () => {
  const h = await harness(); let confirmed: PaperReceipt | null = null;
  try {
    await h.stock({onCommitted: async receipt => {confirmed = receipt;}});
    assert.equal(h.calls.some(call => call.method !== 'GET'), false);
    await h.click('Review paper buy'); assert.match(h.text(), /Review your buy/); assert.match(h.text(), /100\.00/);
    assert.equal(h.calls.filter(call => call.path.endsWith('/preview')).length, 1);
    assert.equal(h.calls.filter(call => call.path.endsWith('/commit')).length, 0);
    await h.click('Confirm paper buy'); assert.match(h.text(), /Your move is made/);
    assert.equal((confirmed as PaperReceipt | null)?.id, ORDER_ID); assert.equal(h.session.lastReceipt?.id, ORDER_ID);
    assert.equal(h.calls.filter(call => call.path.endsWith('/commit')).length, 1);
  } finally {await h.close();}
});

test('expired review disables confirmation and never dispatches a commit', async () => {
  const h = await harness(); const originalNow = Date.now;
  try {
    await h.stock(); await h.click('Review paper buy');
    Date.now = () => h.f.now + 31000; await h.flush(1050);
    assert.match(h.text(), /Quote expired/); assert.equal(h.button('Confirm paper buy')?.disabled, true);
    await h.click('Confirm paper buy'); assert.equal(h.calls.some(call => call.path.endsWith('/commit')), false);
  } finally {Date.now = originalNow; await h.close();}
});

test('a lost commit acknowledgement restores a pending command; Check order replays its exact body', async () => {
  let lose = true;
  const h = await harness({reply: call => {if (call.path.endsWith('/commit') && lose) {lose = false; throw new TypeError('Receipt lost');} return undefined;}});
  try {
    await h.session.ensureGuest(); const preview = await h.session.previewOrder({action: 'buy', assetId: 'apple', variantMint: MINT, amount: {kind: 'paper_amount', paperMicros: '100000000'}});
    await assert.rejects(h.session.commitOrder(preview), {code: 'PRACTICE_NETWORK_ERROR'});
    const firstBody = h.calls.find(call => call.path.endsWith('/commit'))!.body;
    await h.app(); assert.match(h.text(), /Let’s check your last order/); assert.doesNotMatch(h.text(), /Your order is confirmed/);
    await h.click('Check order'); assert.match(h.text(), /Your order is confirmed/);
    const commits = h.calls.filter(call => call.path.endsWith('/commit')); assert.equal(commits.length, 2); assert.deepEqual(commits[1]!.body, firstBody);
    const saved = JSON.parse(h.storage.getItem(practiceStorageKey('/api'))!) as {pendingCommit: unknown; lastReceipt: {id: string}};
    assert.equal(saved.pendingCommit, null); assert.equal(saved.lastReceipt.id, ORDER_ID);
  } finally {await h.close();}
});

test('token selection cannot accept an older token response or keep its old order review', async () => {
  const pending = deferred<Response>(); let delayed = false;
  const h = await harness({reply: call => {if (call.path.endsWith('/insight') && call.url.searchParams.get('mint') === MINT && !delayed) {delayed = true; return pending.promise;} return undefined;}});
  try {
    await h.stock(); await h.click('Review paper buy'); assert.match(h.text(), /Review your buy/);
    const select = h.dom.window.document.querySelector<HTMLSelectElement>('#token-version')!; assert.ok(select);
    await act(async () => {select.value = OTHER_MINT; select.dispatchEvent(new h.dom.window.Event('change', {bubbles: true}));}); await h.flush();
    assert.doesNotMatch(h.text(), /Review your buy/); assert.match(h.text(), /\$72\.00/);
    pending.resolve(json({...h.f.insight(MINT), priceUsd: 999})); await h.flush();
    assert.doesNotMatch(h.text(), /\$999\.00/); assert.match(h.text(), /\$72\.00/);
    assert.equal(h.calls.some(call => call.path.endsWith('/commit')), false);
  } finally {await h.close();}
});

test('storage identity changes immediately mask the desk and trading controls', async () => {
  const h = await harness();
  try {
    await h.session.ensureGuest(); await h.app(); assert.match(h.text(), /10,000\.00/);
    h.storage.setItem(h.session.storageKey, 'changed elsewhere');
    await act(async () => {h.dom.window.dispatchEvent(new h.dom.window.StorageEvent('storage', {key: h.session.storageKey, newValue: 'changed elsewhere'}));});
    assert.match(h.text(), /Your desk changed in another tab/); assert.doesNotMatch(h.text(), /10,000\.00|Your positions/);
    await h.click('Market'); assert.equal(h.button('Review paper buy'), undefined); assert.match(h.text(), /Reload your desk/);
    assert.equal(h.calls.filter(call => call.path === '/v1/guest/session').length, 1);
  } finally {await h.close();}
});

test('Market refreshes visible prices on its timer and focus while retaining the list and suppressing hidden or offline reads', async () => {
  const pending = deferred<Response>(); let hold = false;
  const h = await harness({reply: call => call.path.endsWith('/catalog') && hold ? pending.promise : undefined});
  const originalNow = Date.now, timers = new Map<number, () => void>();
  Object.defineProperty(h.dom.window, 'setInterval', {configurable: true, value: (callback: () => void, ms: number) => {
    timers.set(ms, callback); return timers.size;
  }});
  try {
    await h.render(createElement(MarketScreen, {client: h.market, onSelect() {}}));
    assert.match(h.text(), /\$51\.00/); assert.doesNotMatch(h.text(), /Checked|Updating prices|Refresh prices/);
    const results = h.dom.window.document.querySelector<HTMLElement>('[role="region"][aria-label="Companies"]')!;
    results.scrollTop = 180; results.focus();
    const count = h.calls.length; Date.now = () => h.f.now + 61000;
    await act(async () => {timers.get(5000)!();});
    assert.match(h.text(), /Updating prices…/); assert.equal(h.calls.length, count);
    hold = true;
    await act(async () => {timers.get(30000)!();});
    assert.equal(h.calls.length, count + 1); assert.match(h.text(), /\$51\.00/);
    await act(async () => {
      h.dom.window.dispatchEvent(new h.dom.window.Event('focus'));
      h.dom.window.document.dispatchEvent(new h.dom.window.Event('visibilitychange'));
    });
    assert.equal(h.calls.length, count + 1, 'an in-flight refresh is not duplicated by focus');
    assert.equal(h.dom.window.document.querySelector('.market-results'), results);
    assert.equal(results.scrollTop, 180); assert.equal(h.dom.window.document.activeElement, results);
    const at = new Date(Date.now()).toISOString();
    pending.resolve(json({discovery: {...h.f.discovery, requestedAt: at, observedAt: at,
      refreshAfter: new Date(Date.now() + 60000).toISOString()},
      cards: [{...h.f.card, stock: {...h.f.card.stock, priceUsd: 52}}], offset: 0, total: 1, nextOffset: null}));
    await h.flush();
    assert.match(h.text(), /\$52\.00/); assert.doesNotMatch(h.text(), /Updating prices/);
    assert.equal(h.dom.window.document.querySelector('.market-results'), results); assert.equal(results.scrollTop, 180);
    Object.defineProperty(h.dom.window.document, 'visibilityState', {configurable: true, value: 'hidden'});
    await act(async () => {timers.get(30000)!(); h.dom.window.dispatchEvent(new h.dom.window.Event('focus'));});
    assert.equal(h.calls.length, count + 1, 'background tabs do not poll');
    Object.defineProperty(h.dom.window.navigator, 'onLine', {configurable: true, value: false});
    Object.defineProperty(h.dom.window.document, 'visibilityState', {configurable: true, value: 'visible'});
    await act(async () => {h.dom.window.dispatchEvent(new h.dom.window.Event('offline')); timers.get(30000)!();});
    assert.match(h.text(), /Offline/); assert.equal(h.calls.length, count + 1);
    Object.defineProperty(h.dom.window.navigator, 'onLine', {configurable: true, value: true});
    hold = false;
    await act(async () => {h.dom.window.dispatchEvent(new h.dom.window.Event('focus'));}); await h.flush();
    assert.equal(h.calls.length, count + 2, 'returning to a visible online tab refreshes without a manual control');
  } finally {Date.now = originalNow; pending.resolve(json({})); await h.close();}
});

test('a late background Market refresh cannot discard a page loaded by More or rewind its next offset', async () => {
  const pending = deferred<Response>(); let firstPageReads = 0;
  let page!: (offset: number) => Response;
  const h = await harness({reply: call => {
    if (!call.path.endsWith('/catalog')) return undefined;
    const offset = Number(call.url.searchParams.get('offset'));
    if (offset === 0 && ++firstPageReads === 2) return pending.promise;
    return page(offset);
  }});
  page = offset => {
    const companies = [
      {assetId: 'apple', name: 'Apple', symbol: 'AAPL', mint: MINT},
      {assetId: 'tesla', name: 'Tesla', symbol: 'TSLA', mint: OTHER_MINT},
      {assetId: 'meta', name: 'Meta', symbol: 'META', mint: '11111111111111111111111111111111'},
    ];
    const company = companies[offset / 20]; assert.ok(company, `Expected catalog offset ${offset}`);
    const variant = {...variantFixture(), variantId: `${company.assetId}-xstock`, mint: company.mint,
      name: `${company.name} xStock`, label: `${company.name} xStock`, symbol: `${company.symbol}x`};
    return json({discovery: {...h.f.discovery, results: [{...h.f.discovery.results[0]!,
      assetId: company.assetId, name: company.name, symbol: company.symbol,
      providerPrimaryVariantMint: company.mint, variants: [variant]}]},
      cards: [{...h.f.card, assetId: company.assetId, name: company.name, symbol: company.symbol,
        primaryVariant: {...h.f.card.primaryVariant, mint: company.mint, symbol: variant.symbol}}],
      offset, total: 41, nextOffset: offset < 40 ? offset + 20 : null});
  };
  try {
    await h.render(createElement(MarketScreen, {client: h.market, onSelect() {}}));
    assert.ok(h.button('Open Apple')); assert.ok(h.button('More companies'));
    await act(async () => {h.dom.window.dispatchEvent(new h.dom.window.Event('focus'));});
    assert.equal(firstPageReads, 2, 'background refresh has requested the original first page');
    await h.click('More companies');
    assert.ok(h.button('Open Apple')); assert.ok(h.button('Open Tesla'));
    assert.equal(h.dom.window.document.querySelectorAll('.stock-row').length, 2);
    pending.resolve(page(0)); await h.flush();
    assert.ok(h.button('Open Apple')); assert.ok(h.button('Open Tesla'), 'late page-zero refresh retains the appended page');
    assert.equal(h.dom.window.document.querySelectorAll('.stock-row').length, 2);
    await h.click('More companies');
    assert.deepEqual(h.calls.filter(call => call.path.endsWith('/catalog')).map(call => Number(call.url.searchParams.get('offset'))), [0, 0, 20, 40]);
    assert.ok(h.button('Open Meta')); assert.equal(h.dom.window.document.querySelectorAll('.stock-row').length, 3);
    assert.equal(h.button('More companies'), undefined);
  } finally {pending.resolve(json({})); await h.close();}
});

test('a confirmed receipt masks old balances until a server portfolio reaches its revision', async () => {
  const delayedPortfolio = deferred<Response>(); let phase: 'before' | 'pending' | 'caught-up' = 'before';
  const h = await harness({reply: call => {
    if (call.path.endsWith('/commit')) phase = 'pending';
    if (call.path.endsWith('/portfolio') && phase === 'pending') return delayedPortfolio.promise;
    if (call.path.endsWith('/portfolio') && phase === 'caught-up') return json(h.f.portfolioAfterBuy(h.f.preview(GUEST_ID)), 200, PORTFOLIO_MEDIA_TYPE);
    return undefined;
  }});
  try {
    h.f.profile.launchCheckpoint = 'app';
    await h.session.ensureGuest(); await h.app(); assert.ok(h.dom.window.document.querySelector('.balance-card'));
    await h.click('Market'); await h.click('Open Apple'); await h.click('Review paper buy'); await h.click('Confirm paper buy');
    assert.match(h.text(), /Your move is made/); await h.click('Back to your desk');
    assert.equal(h.dom.window.document.querySelector('.balance-card'), null, 'receipt invalidates pre-commit balances immediately');
    delayedPortfolio.resolve(json(h.f.portfolio(), 200, PORTFOLIO_MEDIA_TYPE)); await h.flush();
    assert.equal(h.dom.window.document.querySelector('.balance-card'), null, 'revision 0 must not replace a revision 1 receipt');
    assert.match(h.text(), /Your desk needs a moment/);
    phase = 'caught-up'; await h.click('Try again');
    assert.ok(h.dom.window.document.querySelector('.balance-card'));
    assert.match(h.dom.window.document.querySelector('.balance-details')?.textContent ?? '', /9,900\.00/);
    assert.match(h.dom.window.document.querySelector('.position-row')?.textContent ?? '', /AppleAAPLx · 2 shares/);
    assert.equal(h.calls.filter(call => call.path.endsWith('/commit')).length, 1);
  } finally {await h.close();}
});

test('a fully closed position from the server cannot enable Sell', async () => {
  const h = await harness({reply: call => {
    if (call.path.endsWith('/portfolio')) return json({...h.f.portfolio(), revision: 2,
      positions: [{assetId: 'apple', variantMint: MINT, symbol: 'AAPLx', quantityMicros: '0', costBasisPaperMicros: '0',
        averageCostPricePaperMicros: '0', realizedGainPaperMicros: '0', lockedGainPaperMicros: '0', updatedAt: h.f.at}],
      valuation: {...h.f.portfolio().valuation, portfolioRevision: 2}}, 200, PORTFOLIO_MEDIA_TYPE);
    return undefined;
  }});
  try {
    await h.session.ensureGuest(); const portfolio = await h.session.readPortfolio();
    assert.equal(portfolio.positions[0]?.quantityMicros, '0'); await h.stock({portfolio});
    assert.equal(h.button('Sell')?.disabled, true); await h.click('Sell');
    assert.equal(h.button('Review paper sell'), undefined); assert.equal(h.calls.some(call => call.path.endsWith('/preview')), false);
  } finally {await h.close();}
});

test('a known guest with an unavailable portfolio never gets a fresh 10000-paper fallback', async () => {
  const h = await harness({hash: `#market/apple?mint=${MINT}`, reply: call => call.path.endsWith('/portfolio')
    ? json({error: {code: 'PAPER_TRADING_UNAVAILABLE', message: 'Unavailable.', requestId: GUEST_ID}}, 503) : undefined});
  try {
    await h.session.ensureGuest(); await h.app();
    assert.match(h.text(), /Paper balance unavailable\. Refresh your desk/);
    assert.doesNotMatch(h.text(), /Start with 10,000|10,000\.00 paper available/);
    assert.equal(h.calls.filter(call => call.path === '/v1/guest/session').length, 1);
  } finally {await h.close();}
});

test('reviewing during restoration waits for the same guest refresh before requesting a quote', async () => {
  const pendingRefresh = deferred<Response>();
  const h = await harness({hash: `#market/apple?mint=${MINT}`, reply: call => call.path === '/v1/guest/session/refresh' ? pendingRefresh.promise : undefined});
  try {
    await h.session.ensureGuest(); await h.app(true); await h.click('Review paper buy');
    assert.equal(h.calls.some(call => call.path === '/v1/product/profile' || call.path.endsWith('/preview')), false);
    assert.doesNotMatch(h.text(), /Your desk needs a moment/);
    pendingRefresh.resolve(json({schemaVersion: 1, ...h.f.guest})); await h.flush();
    assert.match(h.text(), /Review your buy/); assert.equal(h.calls.filter(call => call.path === '/v1/guest/session/refresh').length, 1);
    assert.equal(h.calls.filter(call => call.path.endsWith('/preview')).length, 1);
    assert.equal(h.calls.filter(call => call.path === '/v1/guest/session').length, 1);
  } finally {await h.close();}
});

test('a transient restore failure can retry its guest refresh without replacing the desk', async () => {
  let attempts = 0;
  const h = await harness({reply: call => {if (call.path === '/v1/guest/session/refresh' && ++attempts === 1) throw new TypeError('Temporary outage'); return undefined;}});
  try {
    await h.session.ensureGuest(); await h.app(); assert.match(h.text(), /Your desk needs a moment/);
    await h.click('Try again'); assert.match(h.text(), /Your desk\./); assert.match(h.text(), /10,000\.00/);
    assert.doesNotMatch(h.text(), /Your desk needs a moment/);
    assert.equal(attempts, 2); assert.equal(h.calls.filter(call => call.path === '/v1/guest/session').length, 1);
  } finally {await h.close();}
});

test('retrying a failed initial profile read resumes an unfinished first day without placing an order', async () => {
  let profileReads = 0;
  const h = await harness({hash: '#desk', reply: call => {
    if (call.path === '/v1/product/profile' && call.method === 'GET' && ++profileReads === 1) {
      throw new TypeError('Temporary profile outage');
    }
    return undefined;
  }});
  try {
    h.f.profile.launchCheckpoint = 'first-trade';
    h.f.guest.expiresAt = new Date(Date.now() + 30 * 86400000).toISOString();
    h.f.guest.hardExpiresAt = new Date(Date.now() + 60 * 86400000).toISOString();
    await h.session.ensureGuest();
    const savedGuest = h.storage.getItem(h.session.storageKey), beforeRestore = h.calls.length;
    await h.app();
    assert.equal(profileReads, 1); assert.match(h.text(), /Your desk needs a moment/);
    assert.equal(h.button('Choose Apple'), undefined);
    await h.click('Try again');
    assert.ok(profileReads > 1); assert.ok(h.button('Choose Apple')); assert.ok(h.button('Choose Tesla')); assert.ok(h.button('Choose Meta'));
    assert.equal(h.button('Choose Apple')?.getAttribute('aria-pressed'), 'false');
    assert.equal(h.button('Review paper buy')?.disabled, true);
    assert.doesNotMatch(h.text(), /Your desk needs a moment/);
    assert.equal(h.dom.window.location.hash, '#start');
    assert.equal(h.f.profile.launchCheckpoint, 'first-trade'); assert.equal(h.f.profile.hasConfirmedPaperTrade, false);
    assert.ok(h.calls.slice(beforeRestore).every(call => call.method === 'GET'));
    assert.equal(h.calls.some(call => call.path.includes('/orders/')), false);
    assert.equal(h.calls.filter(call => call.path === '/v1/guest/session').length, 1);
    assert.equal(h.storage.getItem(h.session.storageKey), savedGuest);
  } finally {await h.close();}
});

test('leaving a restoring workspace prevents late profile reads and navigation', async () => {
  const pendingRefresh = deferred<Response>();
  const h = await harness({reply: call => call.path === '/v1/guest/session/refresh' ? pendingRefresh.promise : undefined});
  try {
    await h.session.ensureGuest(); await h.app();
    await h.render(createElement(ProductApp, {apiBase: null})); assert.match(h.text(), /Your desk is almost ready/);
    pendingRefresh.resolve(json({schemaVersion: 1, ...h.f.guest})); await h.flush();
    assert.match(h.text(), /Your desk is almost ready/); assert.equal(h.dom.window.location.hash, '');
    assert.equal(h.calls.some(call => call.path === '/v1/product/profile' || call.path.endsWith('/portfolio')), false);
  } finally {await h.close();}
});

test('paper money rounds in integer micros while six-place share quantities stay exact', () => {
  assert.equal(micros('99999000'), '100.00');
  assert.equal(micros('99994000'), '99.99');
  assert.equal(micros('-99999000'), '−100.00');
  assert.equal(micros('999999999999999'), '1,000,000,000.00');
  assert.equal(micros('99999000', 6), '99.999000');
  assert.equal(shares('99999000'), '99.999');
  assert.equal(shares('1'), '0.000001');
});
