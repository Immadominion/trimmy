import assert from 'node:assert/strict';
import test from 'node:test';
import {setTimeout as delay} from 'node:timers/promises';
import {act, createElement} from 'react';
import {createRoot, type Root} from 'react-dom/client';
import {JSDOM} from 'jsdom';
import {
  ACCOUNT_DATA_AAPLX_MINT,
  ACCOUNT_DATA_MAINNET_GENESIS,
  ACCOUNT_DATA_USDC_MINT,
} from '../src/account/account-data-models.js';
import {useAccountPortfolio, type AccountPortfolioLifecycleView} from '../src/account/use-account-portfolio.js';
import type {PracticeAccountAuth} from '../src/account/privy-provider.js';

const SUBJECT_A = 'did:privy:webPortfolioA';
const SUBJECT_B = 'did:privy:webPortfolioB';
const ACCOUNT_A = 'aa000000-0000-4000-8000-000000000001';
const ACCOUNT_B = 'bb000000-0000-4000-8000-000000000002';
const WALLET_A = 'FVen3X669xLzsi6N2V91DoiyzHzg1uAgqiT8jZ9nS96Z';
const WALLET_B = 'FbP8bwmje245N5k3GTrx7BcKcDwbJNbfvEaEbF8eewY1';
const TOKEN_A = 'fixtureA.payload.signature';
const TOKEN_B = 'fixtureB.payload.signature';
const API = 'https://api.example';

function context(accountId: string, wallet: string) {
  return {schemaVersion: 1, userId: accountId, xIdentity: {status: 'missing'},
    embeddedSolanaWallet: {status: 'candidate', address: wallet, verifiedAtUnixSeconds: 1_757_845_201}};
}

function holdings(accountId: string, wallet: string, amountRaw = '10000000') {
  return {
    schemaVersion: 1, userId: accountId,
    wallet: {address: wallet, source: 'privy_embedded_wallet_same_subject', possessionSignatureVerified: false},
    holdings: {
      network: 'solana:mainnet-beta', genesisHash: ACCOUNT_DATA_MAINNET_GENESIS, commitment: 'confirmed',
      observedAt: new Date().toISOString(), readOnly: true, transactionBuilt: false,
      transactionSigned: false, transactionBroadcast: false,
      balances: {
        nativeSol: {symbol: 'SOL', decimals: 9, amountRaw: '20000000', amountUnits: 'lamports', observedSlot: 100},
        usdc: {symbol: 'USDC', mint: ACCOUNT_DATA_USDC_MINT, decimals: 6, amountRaw,
          amountUnits: 'raw_token_units', observedSlot: 101, accountCount: 1, accountTopology: 'associated_only',
          aggregation: 'all_valid_owner_token_accounts', hasFrozenAccounts: false},
        aaplx: {symbol: 'AAPLx', mint: ACCOUNT_DATA_AAPLX_MINT, decimals: 8, amountRaw: '2979490',
          amountUnits: 'raw_token_units', observedSlot: 102, accountCount: 1, accountTopology: 'associated_only',
          aggregation: 'all_valid_owner_token_accounts', hasFrozenAccounts: false,
          displayResolution: 'token_2022_scaled_ui_unresolved', displayAmount: null, shareAmount: null,
          eligibility: 'unverified', executionEnabled: false},
      },
      consistency: {kind: 'independent_confirmed_reads', atomic: false,
        slots: {nativeSol: 100, usdc: 101, aaplx: 102}},
    },
  };
}

const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), {
  status, headers: {'content-type': 'application/json'},
});
const apiError = (code: string, status: number) => json({error: {
  code, message: 'private server detail', requestId: 'fixture-request',
}}, status);
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>(done => {resolve = done;});
  return {promise, resolve};
}

async function harness(fetch: typeof globalThis.fetch) {
  const dom = new JSDOM('<!doctype html><div id="root"></div>', {
    url: 'https://trimmy.example', pretendToBeVisual: true,
  });
  const descriptors = new Map<string, PropertyDescriptor | undefined>();
  function setGlobal(name: string, value: unknown) {
    descriptors.set(name, Object.getOwnPropertyDescriptor(globalThis, name));
    Object.defineProperty(globalThis, name, {configurable: true, writable: true, value});
  }
  setGlobal('window', dom.window);
  setGlobal('document', dom.window.document);
  setGlobal('navigator', dom.window.navigator);
  setGlobal('Event', dom.window.Event);
  setGlobal('IS_REACT_ACT_ENVIRONMENT', true);
  setGlobal('fetch', fetch);
  let online = true;
  let hidden = false;
  Object.defineProperty(dom.window.navigator, 'onLine', {configurable: true, get: () => online});
  Object.defineProperty(dom.window.document, 'hidden', {configurable: true, get: () => hidden});
  const root: Root = createRoot(dom.window.document.getElementById('root')!);
  let liveSubject: string | null = null;
  let latest: AccountPortfolioLifecycleView | null = null;
  const commits: Array<AccountPortfolioLifecycleView> = [];

  function Probe({auth, accountId, verificationEpoch, requestReverification}: {
    auth: PracticeAccountAuth; accountId: string | null; verificationEpoch: number;
    requestReverification: () => void;
  }) {
    const value = useAccountPortfolio(auth, accountId, {verificationEpoch, requestReverification});
    latest = value;
    commits.push(value);
    return createElement('span', {'data-phase': value.snapshot?.phase ?? 'unbound'});
  }
  function makeAuth(subject: string | null, options: {errorCode?: string | null; apiOrigin?: string} = {}): PracticeAccountAuth {
    const apiOrigin = options.apiOrigin ?? API;
    return {
      enabled: true, ready: true, authenticated: subject !== null, subject, apiOrigin,
      errorCode: options.errorCode ?? null, busy: false, login() {}, logout: async () => {},
      freshAccessToken: async expected => expected === liveSubject
        ? expected === SUBJECT_A ? TOKEN_A : TOKEN_B : null,
    };
  }
  async function render(subject: string | null, accountId: string | null,
    options: {errorCode?: string | null; apiOrigin?: string; verificationEpoch?: number;
      requestReverification?: () => void} = {}) {
    liveSubject = subject;
    await act(async () => {root.render(createElement(Probe, {
      auth: makeAuth(subject, options), accountId, verificationEpoch: options.verificationEpoch ?? 1,
      requestReverification: options.requestReverification ?? (() => {}),
    }));});
  }
  async function until(check: () => boolean, description: string) {
    for (let attempt = 0; attempt < 100 && !check(); attempt++) {
      await act(async () => {await delay(5);});
    }
    assert.ok(check(), `${description}; phase=${latest?.snapshot?.phase ?? 'unbound'}`);
  }
  async function close() {
    await act(async () => {root.unmount();});
    for (const [name, descriptor] of descriptors) {
      if (descriptor) Object.defineProperty(globalThis, name, descriptor);
      else Reflect.deleteProperty(globalThis, name);
    }
    dom.window.close();
  }
  return {
    dom, commits, render, until, close,
    latest: () => latest,
    setOnline(value: boolean) {online = value;},
    setHidden(value: boolean) {hidden = value;},
  };
}

test('guest and unverified sessions cannot read; verified offline sessions wait for reconnect and foreground', async () => {
  const paths: string[] = [];
  const h = await harness(async input => {
    const path = new URL(String(input)).pathname;
    paths.push(path);
    return path.endsWith('/context') ? json(context(ACCOUNT_A, WALLET_A)) : json(holdings(ACCOUNT_A, WALLET_A));
  });
  try {
    await h.render(null, null);
    await h.render(SUBJECT_A, null);
    assert.equal(paths.length, 0);
    assert.equal(h.latest()?.binding, null);

    h.setOnline(false);
    await h.render(SUBJECT_A, ACCOUNT_A);
    await act(async () => {await delay(10);});
    assert.equal(paths.length, 0);
    assert.equal(h.latest()?.binding?.accountId, ACCOUNT_A);
    assert.equal(h.latest()?.snapshot?.phase, 'offline');
    h.setOnline(true);
    await act(async () => {h.dom.window.dispatchEvent(new h.dom.window.Event('online'));});
    await h.until(() => h.latest()?.snapshot?.phase === 'ready', 'reconnect loaded the verified account');
    assert.deepEqual(paths, ['/v1/account/context', '/v1/account/holdings']);
    assert.equal(h.latest()?.snapshot?.portfolio?.holdings.holdings.balances.aaplx.displayAmount, null);
    assert.ok(Object.isFrozen(h.latest()) && Object.isFrozen(h.latest()?.binding) &&
      Object.isFrozen(h.latest()?.snapshot) && Object.isFrozen(h.latest()?.snapshot?.portfolio));

    h.setHidden(true);
    await act(async () => {h.dom.window.dispatchEvent(new h.dom.window.Event('online'));});
    assert.equal(paths.length, 2);
    h.setHidden(false);
    await act(async () => {h.dom.window.document.dispatchEvent(new h.dom.window.Event('visibilitychange'));});
    await h.until(() => paths.length === 4, 'foreground refreshed the exact verified account');
  } finally {await h.close();}
});

test('subject and account switches mask old data immediately and discard a late old-subject callback', async () => {
  const heldA = deferred<Response>();
  const requests: Array<{subject: string; path: string; signal: AbortSignal | null}> = [];
  const h = await harness(async (input, init) => {
    const path = new URL(String(input)).pathname;
    const token = new Headers(init?.headers).get('authorization');
    const subject = token === `Bearer ${TOKEN_A}` ? SUBJECT_A : SUBJECT_B;
    requests.push({subject, path, signal: init?.signal ?? null});
    if (subject === SUBJECT_A) return heldA.promise;
    return path.endsWith('/context') ? json(context(ACCOUNT_B, WALLET_B))
      : json(holdings(ACCOUNT_B, WALLET_B, '20000000'));
  });
  try {
    await h.render(SUBJECT_A, ACCOUNT_A);
    await h.until(() => requests.length === 1, 'old context request started');
    const beforeSwitch = h.commits.length;
    await h.render(SUBJECT_B, ACCOUNT_B);
    assert.equal(h.latest()?.binding?.subject, SUBJECT_B);
    assert.equal(h.commits[beforeSwitch]?.binding?.subject, SUBJECT_B);
    assert.equal(h.commits[beforeSwitch]?.snapshot, null,
      'the previous snapshot is not visible during the first switch render');
    assert.equal(requests[0]?.signal?.aborted, true);
    await h.until(() => h.latest()?.snapshot?.phase === 'ready', 'new account became ready');
    assert.equal(h.latest()?.snapshot?.portfolio?.accountId, ACCOUNT_B);
    assert.equal(h.latest()?.snapshot?.portfolio?.walletAddress, WALLET_B);
    assert.equal(h.latest()?.snapshot?.portfolio?.holdings.holdings.balances.usdc.amountRaw, '20000000');
    await act(async () => {heldA.resolve(json(context(ACCOUNT_A, WALLET_A))); await delay(5);});
    assert.equal(requests.filter(request => request.subject === SUBJECT_A &&
      request.path.endsWith('/holdings')).length, 0);
    assert.equal(h.latest()?.snapshot?.portfolio?.accountId, ACCOUNT_B);
  } finally {await h.close();}
});

test('an immediate reconnect replaces the cancelled offline read and rejects its late body', async () => {
  const first = deferred<Response>();
  let firstSignal: AbortSignal | null = null;
  let calls = 0;
  const h = await harness(async (input, init) => {
    const path = new URL(String(input)).pathname;
    calls++;
    if (calls === 1) {firstSignal = init?.signal ?? null; return first.promise;}
    return path.endsWith('/context') ? json(context(ACCOUNT_A, WALLET_A)) : json(holdings(ACCOUNT_A, WALLET_A));
  });
  try {
    await h.render(SUBJECT_A, ACCOUNT_A);
    await h.until(() => calls === 1, 'initial read started');
    await act(async () => {
      h.dom.window.dispatchEvent(new h.dom.window.Event('offline'));
      h.dom.window.dispatchEvent(new h.dom.window.Event('online'));
    });
    assert.equal((firstSignal as AbortSignal | null)?.aborted, true);
    await h.until(() => h.latest()?.snapshot?.phase === 'ready', 'reconnect replacement became ready');
    assert.equal(calls, 3);
    await act(async () => {first.resolve(json(context(ACCOUNT_B, WALLET_B))); await delay(5);});
    assert.equal(h.latest()?.snapshot?.portfolio?.accountId, ACCOUNT_A);
    assert.equal(calls, 3);
  } finally {await h.close();}
});

test('cross-account context and cross-wallet holdings retire the binding without retaining portfolio data', async () => {
  for (const mismatch of ['account', 'wallet'] as const) {
    const paths: string[] = [];
    const h = await harness(async input => {
      const path = new URL(String(input)).pathname;
      paths.push(path);
      if (path.endsWith('/context')) return json(context(mismatch === 'account' ? ACCOUNT_B : ACCOUNT_A, WALLET_A));
      return json(holdings(ACCOUNT_A, WALLET_B));
    });
    try {
      await h.render(SUBJECT_A, ACCOUNT_A);
      await h.until(() => h.latest()?.snapshot?.phase === 'accountChanged', `${mismatch} mismatch rejected`);
      assert.equal(h.latest()?.snapshot?.portfolio, null);
      assert.equal(h.latest()?.snapshot?.context, null);
      assert.equal(h.latest()?.errorCode, mismatch === 'account'
        ? 'ACCOUNT_DATA_ACCOUNT_CHANGED' : 'ACCOUNT_PORTFOLIO_WALLET_CHANGED');
      assert.equal(paths.filter(path => path.endsWith('/holdings')).length, mismatch === 'account' ? 0 : 1);
      const count = paths.length;
      await act(async () => {h.dom.window.dispatchEvent(new h.dom.window.Event('online'));});
      await act(async () => {await delay(5);});
      assert.equal(paths.length, count, 'a retired mismatched binding cannot refresh');
    } finally {await h.close();}
  }
});

test('an account authentication failure is terminal until reverified, and logout aborts pending work', async () => {
  let mode: 'unauthenticated' | 'held' = 'unauthenticated';
  let heldSignal: AbortSignal | null = null;
  const held = deferred<Response>();
  let calls = 0;
  let reverifications = 0;
  const requestReverification = () => {reverifications++;};
  const h = await harness(async (_input, init) => {
    calls++;
    if (mode === 'unauthenticated') return apiError('ACCOUNT_CONTEXT_UNAUTHENTICATED', 401);
    heldSignal = init?.signal ?? null;
    return held.promise;
  });
  try {
    await h.render(SUBJECT_A, ACCOUNT_A, {verificationEpoch: 1, requestReverification});
    await h.until(() => h.latest()?.errorCode === 'ACCOUNT_CONTEXT_UNAUTHENTICATED', 'authentication failure published');
    const terminalCalls = calls;
    assert.equal(h.latest()?.retry(), true);
    assert.equal(h.latest()?.retry(), false, 'one verification epoch can request at most one replacement');
    assert.equal(reverifications, 1);
    assert.equal(calls, terminalCalls);

    mode = 'held';
    await h.render(SUBJECT_A, ACCOUNT_A, {verificationEpoch: 2, requestReverification});
    await h.until(() => heldSignal !== null, 'newly verified request started');
    await h.render(null, null);
    assert.equal((heldSignal as AbortSignal | null)?.aborted, true);
    assert.equal(h.latest()?.snapshot, null);
    held.resolve(json(context(ACCOUNT_A, WALLET_A)));
  } finally {await h.close();}
});
