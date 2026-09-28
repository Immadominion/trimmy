import assert from 'node:assert/strict';
import {webcrypto} from 'node:crypto';
import test from 'node:test';
import {setTimeout as delay} from 'node:timers/promises';
import {act, createElement} from 'react';
import {JSDOM} from 'jsdom';
import type {ProductAuthSdkPort} from '../src/product/product-auth-sdk-loader.js';
import {PORTFOLIO_MEDIA_TYPE, PracticeClient, PROFILE_MEDIA_TYPE} from '../src/product/practice-client.js';
import {ProductMarketClient} from '../src/product/market-client.js';
import {searchFixture} from '../src/markets/fixtures.test-support.js';
import {moneyHarness} from './support/money-harness.js';
import {ACCOUNT_ID, SUBJECT} from './support/money-fixtures.js';

function token(subject = SUBJECT) {
  const at = Math.floor(Date.now() / 1000), encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString('base64url');
  return `${encode({alg: 'ES256', typ: 'JWT'})}.${encode({sub: subject, aud: 'testApp', iss: 'privy.io', sid: 'session', iat: at - 5, exp: at + 300})}.c3ludGhldGlj`;
}

async function signedInApp() {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {url: 'https://trimmy.example/#desk', pretendToBeVisual: true});
  const saved = new Map<string, PropertyDescriptor | undefined>();
  const expose = (name: string, value: unknown) => {saved.set(name, Object.getOwnPropertyDescriptor(globalThis, name));
    Object.defineProperty(globalThis, name, {configurable: true, writable: true, value});};
  expose('window', dom.window); expose('document', dom.window.document); expose('navigator', dom.window.navigator);
  expose('HTMLElement', dom.window.HTMLElement); expose('Event', dom.window.Event); expose('localStorage', dom.window.localStorage);
  expose('crypto', webcrypto); expose('IS_REACT_ACT_ENVIRONMENT', true);
  Object.defineProperty(dom.window, 'matchMedia', {value: () => ({matches: true, addEventListener() {}, removeEventListener() {}})});
  Object.defineProperty(dom.window, 'scrollTo', {value: () => {}});
  Object.defineProperty(dom.window.navigator, 'locks', {value: {request: async (_name: string, _options: unknown, callback: () => Promise<unknown>) => callback()}});
  const h = await moneyHarness();
  const at = new Date().toISOString();
  const profile = {revision: 3, onboarding: {goal: null, knowledge: null, persona: null, dailyGoal: null, handle: null}, launchCheckpoint: 'app',
    hasConfirmedPaperTrade: true, createdAt: at, updatedAt: at};
  const portfolio = {schemaVersion: 2, mode: 'paper', unit: {kind: 'paper', scaleDigits: 6}, revision: 0, startingCashPaperMicros: '10000000000',
    cashPaperMicros: '10000000000', openedAt: null, updatedAt: null, positions: [], recentOrders: [], valuation: {status: 'complete', portfolioRevision: 0,
      openPositionCount: 0, pricedPositionCount: 0, cashPaperMicros: '10000000000', knownValuePaperMicros: '10000000000', totalPaperMicros: '10000000000', positions: []}};
  const paperCalls: string[] = [];
  const paperFetch = (async (url: string | URL | Request) => {
    const path = new URL(String(url), 'https://trimmy.example').pathname.replace(/^\/api/, '');
    paperCalls.push(path);
    if (path === '/v1/product/profile') return Response.json({schemaVersion: 2, profile}, {headers: {'content-type': PROFILE_MEDIA_TYPE}});
    if (path === '/v1/account/paper/portfolio') return Response.json(portfolio, {headers: {'content-type': PORTFOLIO_MEDIA_TYPE}});
    if (path === '/v1/career/summary') return Response.json({schemaVersion: 1, career: {revision: 0, trims: {total: 0, today: 0, thisWeek: 0},
      rank: {id: 'rookie', label: 'Rookie', paperLimit: '10000', threshold: 0}, nextRank: {id: 'analyst', label: 'Analyst', threshold: 300, trimsRemaining: 300, promotionRequired: true},
      streak: {days: 0, status: 'not-started', lastActiveDate: null}, careerStarted: false, firstConfirmedBuy: null, serverDate: at.slice(0, 10), updatedAt: null}});
    if (path === '/v1/career/missions') return Response.json({schemaVersion: 1, career: {revision: 0, currentRank: 'rookie'}, missions: []});
    if (path.endsWith('/catalog')) {
      const discovery = {...searchFixture('catalog', 20), requestedAt: at, observedAt: at, refreshAfter: new Date(Date.now() + 60_000).toISOString()};
      return Response.json({discovery, cards: [{assetId: 'apple', name: 'Apple', symbol: 'AAPL', imageUrl: null, stock: null, primaryVariant: null}], offset: 0, total: 1, nextOffset: null});
    }
    return Response.json({error: {code: 'NOT_FOUND', message: 'Not in this test.', requestId: 'test'}}, {status: 404});
  }) as typeof fetch;
  const authSdk: ProductAuthSdkPort = {
    PrivyProvider: props => props.children as never,
    usePrivy: () => ({ready: true, authenticated: true, user: {id: SUBJECT}, error: false, getAccessToken: async () => token(), logout: async () => {}}),
    useLoginWithEmail: () => ({sendCode: async () => {}, loginWithCode: async () => {}}),
    useLoginWithOAuth: () => ({status: 'initial', initOAuth: async () => {}}),
  };
  const {createRoot} = await import('react-dom/client');
  const {ProductApp} = await import('../src/product/ProductApp.js');
  const root = createRoot(dom.window.document.getElementById('root')!);
  const flush = async (ms = 20) => {await act(async () => {await delay(ms);});};
  await act(async () => {root.render(createElement(ProductApp, {apiBase: '/api',
    practiceClient: new PracticeClient({baseUrl: '/api', fetch: paperFetch, timeoutMs: 1000}),
    marketClient: new ProductMarketClient({baseUrl: '/api', fetch: paperFetch, timeoutMs: 1000}),
    storage: {getItem: key => h.storage.getItem(key), setItem: (key, value) => h.storage.setItem(key, value)},
    authConfig: {kind: 'enabled', appId: 'testApp', apiBase: '/api'}, authSdk,
    connectAccount: async () => ({accountId: ACCOUNT_ID, guestDisposition: 'none' as const}),
    walletSdk: {useEmbeddedSolana: () => h.embedded()}, moneyFetch: h.fetch, moneyStorage: h.storage}));});
  await flush(60);
  const text = () => dom.window.document.body.textContent ?? '';
  const button = (label: string | RegExp) => [...dom.window.document.querySelectorAll<HTMLButtonElement>('button')].find(item => {
    const name = item.textContent?.trim() ?? '', aria = item.getAttribute('aria-label') ?? '';
    return typeof label === 'string' ? name === label || aria === label : label.test(name) || label.test(aria);
  });
  const click = async (label: string | RegExp) => {const target = button(label); assert.ok(target, `Button exists: ${label}\n${text().slice(0, 400)}`);
    await act(async () => {target.click();}); await flush();};
  const waitFor = async (check: () => boolean, label: string) => {
    const deadline = Date.now() + 3000;
    while (!check()) {if (Date.now() > deadline) throw new Error(`Timed out waiting for ${label}\n${text().slice(0, 600)}`); await flush(15);}
  };
  const close = async () => {await act(async () => {root.unmount();}); dom.window.close();
    for (const [name, descriptor] of saved) {if (descriptor) Object.defineProperty(globalThis, name, descriptor); else Reflect.deleteProperty(globalThis, name);}};
  return {...h, dom, text, button, click, waitFor, flush, close, paperCalls};
}

test('a signed-in desk switches Paper and Real together across Home, the nav, Fast buy and history', async () => {
  const app = await signedInApp();
  try {
    await app.waitFor(() => /Your desk\./.test(app.text()) && Boolean(app.button('Switch to real money mode')), 'paper desk');
    assert.match(app.text(), /Your paper (balance|cash)/); assert.doesNotMatch(app.text(), /Real money/);
    assert.equal(app.calls.some(call => call.path.startsWith('/v1/trading/preview')), false);
    await app.click('Switch to real money mode');
    await app.waitFor(() => /\$25\.00/.test(app.text()), 'real cash');
    assert.match(app.text(), /Cash balance/); assert.match(app.text(), /Real money/, 'the nav says Real money while Real is on');
    assert.doesNotMatch(app.text(), /Your paper balance/, 'paper and real balances are never shown as one');
    assert.equal(app.storage.getItem(`trimmy.money-mode.v1.${encodeURIComponent('/api')}.${ACCOUNT_ID}`), 'real', 'the mode belongs to this account');
    await app.click(/Fast buy/);
    await app.waitFor(() => /AAPLx · xStocks/.test(app.text()), 'real fast buy list');
    assert.ok(app.dom.window.document.querySelector('.fast-buy.real'));
    const search = app.dom.window.document.querySelector<HTMLInputElement>('.fast-buy-search')!;
    const setter = Object.getOwnPropertyDescriptor(app.dom.window.HTMLInputElement.prototype, 'value')!.set!;
    await act(async () => {setter.call(search, 'METAon'); search.dispatchEvent(new app.dom.window.Event('input', {bubbles: true}));}); await app.flush();
    await app.click(/METAon · Ondo/);
    await app.waitFor(() => app.dom.window.location.hash === '#market/meta?mint=fDxs5y12E7x7jBwCKBXGqt71uJmCWsAQ3Srkte6ondo', 'company route');
    app.dom.window.location.hash = '#history';
    await app.waitFor(() => /Your trades/.test(app.text()), 'history');
    app.dom.window.location.hash = '#desk';
    await app.waitFor(() => Boolean(app.button('Switch to paper mode')), 'real desk');
    await app.click('Switch to paper mode');
    await app.waitFor(() => /Your paper (balance|cash)/.test(app.text()), 'paper desk again');
    assert.doesNotMatch(app.text(), /Cash balance/);
  } finally {await app.close();}
});
