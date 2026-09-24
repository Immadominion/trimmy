import assert from 'node:assert/strict';
import test from 'node:test';
import { setTimeout as delay } from 'node:timers/promises';
import { act, createElement, Fragment, useLayoutEffect } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { JSDOM } from 'jsdom';
import { App } from '../src/App.js';
import { PracticeAccountAuthContext, PracticeAccountProvider, type PracticeAccountAuth } from '../src/account/privy-provider.js';
import { parsePracticeWebConfig } from '../src/account/config.js';
import {
  ACCOUNT_DATA_AAPLX_MINT,
  ACCOUNT_DATA_MAINNET_GENESIS,
  ACCOUNT_DATA_USDC_MINT,
} from '../src/account/account-data-models.js';
import { STORAGE_KEY } from '../src/state.js';
import type { ExclusiveLockPort } from '../src/account/tab-lease.js';

const A = 'did:privy:accountA', B = 'did:privy:accountB';
const uuidA = 'aa000000-0000-4000-8000-000000000001';
const uuidB = 'bb000000-0000-4000-8000-000000000002';
const walletA = 'FVen3X669xLzsi6N2V91DoiyzHzg1uAgqiT8jZ9nS96Z';
const walletB = 'FbP8bwmje245N5k3GTrx7BcKcDwbJNbfvEaEbF8eewY1';
const tokenA = 'fixtureA.payload.signature';
const tokenB = 'fixtureB.payload.signature';
const time = '2026-09-14T12:00:00.000Z';
const snapshot = (assetIds: readonly string[], revision = 1) => ({schemaVersion: 1, revision, assetIds, updatedAt: revision ? time : null});
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {status, headers: {'content-type': 'application/json'}});
function deferred<T>() {let resolve!: (value: T) => void; const promise = new Promise<T>(yes => {resolve = yes;}); return {promise, resolve};}

class Locks implements ExclusiveLockPort {
  readonly active = new Set<string>();
  acquired = 0;
  released = 0;
  async request(name: string, options: {mode: 'exclusive'; signal: AbortSignal}, callback: (lock: unknown) => Promise<void>) {
    assert.equal(options.mode, 'exclusive');
    // Web Locks queues a replacement request until its previous callback has
    // settled, including the microtask after lease.release().
    while (this.active.has(name) && !options.signal.aborted) await delay(0);
    if (options.signal.aborted) throw new Error('Aborted');
    assert.ok(!this.active.has(name), 'same-account lease is released before reopening');
    this.active.add(name); this.acquired++;
    try {await callback({name});}
    finally {this.active.delete(name); this.released++;}
  }
}

class Server {
  readonly data = new Map([[A, snapshot(['forma'])], [B, snapshot(['grove'])]]);
  readonly holds = new Map<string, ReturnType<typeof deferred<Response>>>();
  readonly sessionHolds = new Map<string, ReturnType<typeof deferred<Response>>>();
  readonly requests: {subject: string; method: string; url: string; body: string | null}[] = [];
  deny = false;
  fetch: typeof fetch = async (url, init) => {
    const method = init?.method ?? 'GET';
    const authorization = new Headers(init?.headers).get('authorization');
    const subject = authorization === `Bearer ${tokenA}` ? A : authorization === `Bearer ${tokenB}` ? B : '';
    assert.ok(subject === A || subject === B, 'only the current test adapter supplies identity');
    assert.equal(init?.redirect, 'error');
    const body = typeof init?.body === 'string' ? init.body : null;
    this.requests.push({subject, method, url: String(url), body});
    const path = new URL(String(url)).pathname;
    const accountId = subject === A ? uuidA : uuidB;
    const wallet = subject === A ? walletA : walletB;
    if (method === 'POST') return this.sessionHolds.get(subject)?.promise ?? json({schemaVersion: 1, userId: accountId});
    if (method === 'GET' && path === '/v1/account/context') return json({
      schemaVersion: 1, userId: accountId, xIdentity: {status: 'missing'},
      embeddedSolanaWallet: {status: 'candidate', address: wallet, verifiedAtUnixSeconds: 1_757_845_201},
    });
    if (method === 'GET' && path === '/v1/account/holdings') return json({
      schemaVersion: 1, userId: accountId,
      wallet: {address: wallet, source: 'privy_embedded_wallet_same_subject', possessionSignatureVerified: false},
      holdings: {
        network: 'solana:mainnet-beta', genesisHash: ACCOUNT_DATA_MAINNET_GENESIS, commitment: 'confirmed',
        observedAt: new Date().toISOString(), readOnly: true, transactionBuilt: false,
        transactionSigned: false, transactionBroadcast: false,
        balances: {
          nativeSol: {symbol: 'SOL', decimals: 9, amountRaw: '20000000', amountUnits: 'lamports', observedSlot: 100},
          usdc: {symbol: 'USDC', mint: ACCOUNT_DATA_USDC_MINT, decimals: 6, amountRaw: '10000000',
            amountUnits: 'raw_token_units', observedSlot: 101, accountCount: 1,
            accountTopology: 'associated_only', aggregation: 'all_valid_owner_token_accounts', hasFrozenAccounts: false},
          aaplx: {symbol: 'AAPLx', mint: ACCOUNT_DATA_AAPLX_MINT, decimals: 8, amountRaw: '2979490',
            amountUnits: 'raw_token_units', observedSlot: 102, accountCount: 1,
            accountTopology: 'associated_only', aggregation: 'all_valid_owner_token_accounts', hasFrozenAccounts: false,
            displayResolution: 'token_2022_scaled_ui_unresolved', displayAmount: null, shareAmount: null,
            eligibility: 'unverified', executionEnabled: false},
        },
        consistency: {kind: 'independent_confirmed_reads', atomic: false,
          slots: {nativeSol: 100, usdc: 101, aaplx: 102}},
      },
    });
    if (this.deny) return json({error: {code: 'WATCHLIST_UNAUTHENTICATED', message: 'Sign in required.', requestId: 'fixture-request'}}, 401);
    if (method === 'GET') return this.holds.get(subject)?.promise ?? json(this.data.get(subject));
    const command = JSON.parse(body!) as {baseRevision: number; assetIds: string[]};
    const existing = this.data.get(subject)!;
    assert.equal(command.baseRevision, existing.revision);
    const next = snapshot(command.assetIds, command.baseRevision + 1);
    this.data.set(subject, next);
    return json(next);
  };
}

async function harness({sample = true}: {sample?: boolean} = {}) {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {url: 'https://trimmy.example', pretendToBeVisual: true});
  const descriptors = new Map<string, PropertyDescriptor | undefined>();
  function global(name: string, value: unknown) {
    descriptors.set(name, Object.getOwnPropertyDescriptor(globalThis, name));
    Object.defineProperty(globalThis, name, {configurable: true, writable: true, value});
  }
  const locks = new Locks(); const server = new Server();
  global('window', dom.window); global('document', dom.window.document); global('navigator', dom.window.navigator);
  global('HTMLElement', dom.window.HTMLElement); global('Event', dom.window.Event);
  global('IS_REACT_ACT_ENVIRONMENT', true); global('fetch', server.fetch);
  Object.defineProperty(dom.window.navigator, 'locks', {value: locks});
  Object.defineProperty(dom.window, 'matchMedia', {value: () => ({matches: false, addEventListener() {}, removeEventListener() {}})});
  dom.window.localStorage.setItem(STORAGE_KEY, JSON.stringify({version: 1, watchlist: ['mesa']}));
  const root: Root = createRoot(dom.window.document.getElementById('root')!);
  let current: string | null = null;
  const commits: {subject: string | null; watched: readonly string[]}[] = [];
  const watched = () => [...dom.window.document.querySelectorAll('tbody .watch-button[aria-pressed="true"]')]
    .map(button => button.getAttribute('aria-label')!);
  function Probe() {
    useLayoutEffect(() => {commits.push({subject: current, watched: watched()});});
    return null;
  }
  function tree(subject: string | null, apiOrigin = 'https://api.example') {
    current = subject;
    const auth: PracticeAccountAuth = {
      enabled: true, ready: true, authenticated: subject !== null, subject, apiOrigin, errorCode: null, busy: false,
      login() {},
      async logout() {root.render(tree(null));},
      async freshAccessToken(expected) {return current === expected ? expected === A ? tokenA : tokenB : null;},
    };
    return createElement(PracticeAccountAuthContext.Provider, {value: auth},
      createElement(Fragment, null, createElement(App), createElement(Probe)));
  }
  async function render(subject: string | null, apiOrigin?: string) {
    await act(async () => {root.render(tree(subject, apiOrigin));});
    if (sample && !dom.window.document.querySelector('.sample-workspace')) await click('Sample workspace');
  }
  async function until(check: () => boolean, description: string) {
    for (let attempt = 0; attempt < 100 && !check(); attempt++) await act(async () => {await delay(10);});
    assert.ok(check(), `${description}; ${dom.window.document.querySelector('.account-bar')?.textContent}; requests=${server.requests.map(request => request.method).join(',')}; leases=${locks.acquired}/${locks.released}`);
  }
  const button = (label: string) => {
    const result = [...dom.window.document.querySelectorAll('button')]
      .find(button => button.textContent === label || button.getAttribute('aria-label') === label);
    assert.ok(result, `button exists: ${label}`);
    return result;
  };
  const click = async (label: string) => {await act(async () => {button(label).click();});};
  const text = () => dom.window.document.body.textContent ?? '';
  async function close() {
    await act(async () => {root.unmount();});
    assert.equal(locks.active.size, 0, 'all account leases released on unmount');
    for (const [name, descriptor] of descriptors) {
      if (descriptor) Object.defineProperty(globalThis, name, descriptor);
      else Reflect.deleteProperty(globalThis, name);
    }
    dom.window.close();
  }
  return {dom, root, server, locks, render, until, button, click, text, watched, commits, close};
}

test('actual app starts portfolio reads only after the server verifies its account UUID', async () => {
  const h = await harness({sample: false});
  try {
    const session = deferred<Response>();
    h.server.sessionHolds.set(A, session);
    await h.render(A);
    await h.until(() => h.server.requests.some(request => request.subject === A &&
      request.method === 'POST' && request.url.endsWith('/v1/practice/session')), 'session verification started');
    assert.equal(h.server.requests.filter(request => request.url.includes('/v1/account/')).length, 0,
      'a Privy DID alone cannot start account reads');
    await act(async () => {session.resolve(json({schemaVersion: 1, userId: uuidA}));});
    await h.until(() => h.server.requests.some(request => request.url.endsWith('/v1/account/holdings')),
      'verified portfolio loaded');
    await h.until(() => h.text().includes('SOL0.02'), 'actual balances lead the normal portfolio');
    assert.equal(h.text().includes('Forma Studio'), false);
    assert.equal(h.text().includes('Portfolio value'), false);
    assert.equal(h.dom.window.document.querySelector('.portfolio-overview'), null);
    const ordered = h.server.requests.map(request => new URL(request.url).pathname);
    assert.ok(ordered.indexOf('/v1/practice/session') < ordered.indexOf('/v1/account/context'));
    assert.ok(ordered.indexOf('/v1/account/context') < ordered.indexOf('/v1/account/holdings'));
    await h.click('Sign out');
    const afterLogout = h.server.requests.length;
    await act(async () => {h.dom.window.dispatchEvent(new h.dom.window.Event('online')); await delay(5);});
    assert.equal(h.server.requests.length, afterLogout, 'logout removes portfolio reconnect listeners');
  } finally {await h.close();}
});

test('actual app masks a previous account immediately, rejects its late GET, and restores guest on logout', async () => {
  const h = await harness();
  try {
    await h.render(A);
    await h.until(() => h.text().includes('Watchlist saved to your account.'), 'account A loaded');
    assert.ok(h.watched().some(label => label.includes('Forma Studio')));
    const heldA = deferred<Response>(), heldB = deferred<Response>();
    h.server.holds.set(A, heldA); h.server.holds.set(B, heldB);
    await act(async () => {h.dom.window.dispatchEvent(new h.dom.window.Event('online'));});
    await h.until(() => h.server.requests.filter(request => request.subject === A && request.method === 'GET' &&
      request.url.endsWith('/v1/watchlist')).length === 2, 'A refresh in flight');
    await h.render(B);
    assert.deepEqual(h.commits.filter(commit => commit.subject === B)[0]?.watched, [], 'no old-account flash before passive effects');
    await h.until(() => h.server.requests.some(request => request.subject === B && request.method === 'GET' &&
      request.url.endsWith('/v1/watchlist')), 'B requested');
    await act(async () => {heldA.resolve(json(snapshot(['orbital'], 2))); heldB.resolve(json(snapshot(['grove'])));});
    await h.until(() => h.text().includes('Watchlist saved to your account.'), 'B loaded');
    assert.deepEqual(h.watched(), ['Remove Grove Energy from watchlist']);
    await h.click('Sign out');
    assert.deepEqual(h.watched(), ['Remove Mesa Collective from watchlist']);
    assert.equal(h.locks.active.size, 0);
    assert.equal(h.dom.window.localStorage.getItem(STORAGE_KEY), JSON.stringify({version: 1, watchlist: ['mesa']}));
  } finally {await h.close();}
});

test('actual app rejects a failed account disk write without changing stars or announcing success', async () => {
  const h = await harness();
  try {
    await h.render(A);
    await h.until(() => h.text().includes('Watchlist saved to your account.'), 'account loaded');
    const prototype = h.dom.window.Storage.prototype;
    const original = prototype.setItem;
    prototype.setItem = function (key, value) {
      if (key.startsWith('trimmy.watchlist-sync.')) throw new Error('Synthetic disk failure');
      original.call(this, key, value);
    };
    await h.click('Add Grove Energy to watchlist');
    assert.ok(h.text().includes('That watchlist change could not be saved.'));
    assert.deepEqual(h.watched(), ['Remove Forma Studio from watchlist']);
    assert.equal(h.dom.window.document.querySelector('[aria-live="polite"]')?.textContent, '');
    assert.equal(h.server.requests.filter(request => request.method === 'PUT').length, 0);
    prototype.setItem = original;
  } finally {await h.close();}
});

test('a locally acknowledged star is sent through the real session protocol and cached across reopening', async () => {
  const h = await harness();
  try {
    await h.render(A);
    await h.until(() => h.text().includes('Watchlist saved to your account.'), 'account loaded');
    await h.click('Add Grove Energy to watchlist');
    assert.ok(h.watched().some(label => label.includes('Grove Energy')));
    await h.until(() => h.server.requests.some(request => request.method === 'PUT'), 'debounced PUT completed');
    await h.until(() => h.text().includes('Watchlist saved to your account.'), 'ACK displayed');
    const body = JSON.parse(h.server.requests.find(request => request.method === 'PUT')!.body!) as Record<string, unknown>;
    assert.equal(body['schemaVersion'], 1);
    assert.equal(typeof body['mutationId'], 'string');
    assert.deepEqual(body['assetIds'], ['forma', 'grove']);
    await h.render(null);
    await h.render(A);
    await h.until(() => h.text().includes('Watchlist saved to your account.'), 'same account reopened');
    assert.deepEqual(h.watched().sort(), ['Remove Forma Studio from watchlist', 'Remove Grove Energy from watchlist'].sort());
    assert.equal(h.locks.acquired, 2);
    assert.equal(h.locks.released, 1);
  } finally {await h.close();}
});

test('same DID under a changed API origin masks the previous snapshot before new effects', async () => {
  const h = await harness();
  try {
    await h.render(A);
    await h.until(() => h.text().includes('Watchlist saved to your account.'), 'initial origin loaded');
    const before = h.commits.length;
    await h.render(A, 'https://other-api.example');
    assert.deepEqual(h.commits[before]?.watched, [], 'previous API snapshot masked on first commit');
  } finally {await h.close();}
});

test('an explicit retry recovers a 401 session instead of remaining blocked by scheduling guard', async () => {
  const h = await harness();
  try {
    h.server.deny = true;
    await h.render(A);
    await h.until(() => h.text().includes('reconnect') || h.text().includes('Sign in again'), 'authentication failure displayed');
    const posts = h.server.requests.filter(request => request.method === 'POST').length;
    h.server.deny = false;
    await h.click('Try again');
    await h.until(() => h.text().includes('Watchlist saved to your account.'), 'new session refresh recovered');
    assert.equal(h.server.requests.filter(request => request.method === 'POST').length, posts + 1);
  } finally {await h.close();}
});

test('partial configuration keeps the actual workspace usable without a dead sign-in button', async () => {
  const h = await harness();
  try {
    await act(async () => {h.root.render(createElement(PracticeAccountProvider,
      {config: parsePracticeWebConfig({appId: 'partial'}), children: createElement(App)}));});
    assert.ok(h.text().includes('Sign-in is unavailable. You can still explore stocks.'));
    await h.click('Sample workspace');
    assert.ok(h.text().includes('Sample watchlist:'));
    assert.ok(h.text().includes('Sign-in is unavailable. Your local workspace is ready.'));
    assert.ok(![...h.dom.window.document.querySelectorAll('button')].some(button => button.textContent === 'Continue with X'));
    await h.click('Add Grove Energy to watchlist');
    assert.ok(h.watched().some(label => label.includes('Grove Energy')));
    assert.equal(h.server.requests.length, 0);
    assert.equal(h.locks.acquired, 0);
  } finally {await h.close();}
});
