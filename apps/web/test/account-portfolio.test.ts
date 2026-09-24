import assert from 'node:assert/strict';
import test from 'node:test';
import {setImmediate as tick} from 'node:timers/promises';
import {AccountDataClient} from '../src/account/account-data-client.js';
import {
  ACCOUNT_DATA_AAPLX_MINT,
  ACCOUNT_DATA_MAINNET_GENESIS,
  ACCOUNT_DATA_USDC_MINT,
} from '../src/account/account-data-models.js';
import {AccountPortfolioStore} from '../src/account/account-portfolio.js';

const SUBJECT = 'did:privy:portfolioSubject';
const OTHER_SUBJECT = 'did:privy:portfolioOther';
const ACCOUNT = '10000000-0000-4000-a000-000000000001';
const OTHER_ACCOUNT = '20000000-0000-4000-a000-000000000002';
const WALLET = 'FVen3X669xLzsi6N2V91DoiyzHzg1uAgqiT8jZ9nS96Z';
const OTHER_WALLET = 'FbP8bwmje245N5k3GTrx7BcKcDwbJNbfvEaEbF8eewY1';
const TOKEN = 'eyJhbGciOiJFUzI1NiJ9.eyJzdWIiOiJmaXh0dXJlIn0.c2lnbmF0dXJl'; // gitleaks:allow -- synthetic JWT fixture with deliberately invalid signature
const BASE_NOW = Date.parse('2026-09-14T18:00:01.000Z');

const context = (userId = ACCOUNT, wallet: string | 'missing' | 'ambiguous' = WALLET) => ({
  schemaVersion: 1, userId, xIdentity: {status: 'missing'},
  embeddedSolanaWallet: wallet === 'missing' || wallet === 'ambiguous' ? {status: wallet} :
    {status: 'candidate', address: wallet, verifiedAtUnixSeconds: 1_757_845_201},
});

const holdings = (userId = ACCOUNT, wallet = WALLET, observedAt = '2026-09-14T18:00:00.500Z') => ({
  schemaVersion: 1, userId,
  wallet: {address: wallet, source: 'privy_embedded_wallet_same_subject', possessionSignatureVerified: false},
  holdings: {network: 'solana:mainnet-beta', genesisHash: ACCOUNT_DATA_MAINNET_GENESIS, commitment: 'confirmed',
    observedAt, readOnly: true, transactionBuilt: false, transactionSigned: false, transactionBroadcast: false,
    balances: {
      nativeSol: {symbol: 'SOL', decimals: 9, amountRaw: '20000000', amountUnits: 'lamports', observedSlot: 100},
      usdc: {symbol: 'USDC', mint: ACCOUNT_DATA_USDC_MINT, decimals: 6, amountRaw: '10000000',
        amountUnits: 'raw_token_units', observedSlot: 101, accountCount: 1, accountTopology: 'associated_only',
        aggregation: 'all_valid_owner_token_accounts', hasFrozenAccounts: false},
      aaplx: {symbol: 'AAPLx', mint: ACCOUNT_DATA_AAPLX_MINT, decimals: 8, amountRaw: '2979490',
        amountUnits: 'raw_token_units', observedSlot: 102, accountCount: 1, accountTopology: 'associated_only',
        aggregation: 'all_valid_owner_token_accounts', hasFrozenAccounts: false,
        displayResolution: 'token_2022_scaled_ui_unresolved', displayAmount: null, shareAmount: null,
        eligibility: 'unverified', executionEnabled: false},
    }, consistency: {kind: 'independent_confirmed_reads', atomic: false,
      slots: {nativeSol: 100, usdc: 101, aaplx: 102}}},
});

const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), {
  status, headers: {'content-type': 'application/json'},
});
const error = (code: string, status: number) => json({error: {code, message: 'private detail', requestId: 'request-1'}}, status);

function harness(handler: (path: string, call: number) => Promise<Response> | Response,
  options: {now?: () => number; currentSubject?: () => string | null; maximumObservationAgeMs?: number;
    maximumFutureSkewMs?: number; setTimer?: (callback: () => void, milliseconds: number) => ReturnType<typeof setTimeout>;
    clearTimer?: (timer: ReturnType<typeof setTimeout>) => void} = {}) {
  let calls = 0, tokens = 0;
  const client = new AccountDataClient({apiOrigin: 'https://api.example', subject: SUBJECT, accountId: ACCOUNT,
    currentSubject: options.currentSubject ?? (() => SUBJECT), accessToken: async expected => {
      assert.equal(expected, SUBJECT); tokens++; return TOKEN;
    }, fetch: async input => handler(new URL(String(input)).pathname, ++calls), timeoutMs: 1_000});
  const store = new AccountPortfolioStore({client, now: options.now ?? (() => BASE_NOW),
    maximumObservationAgeMs: options.maximumObservationAgeMs ?? 1_000,
    maximumFutureSkewMs: options.maximumFutureSkewMs ?? 100,
    ...(options.setTimer ? {setTimer: options.setTimer} : {}),
    ...(options.clearTimer ? {clearTimer: options.clearTimer} : {})});
  return {store, get calls() {return calls;}, get tokens() {return tokens;}};
}

function sequence(...responses: Array<Response | (() => Response)>): (path: string, call: number) => Response {
  return (_path, call) => {
    const entry = responses[call - 1];
    assert.ok(entry, `unexpected request ${call}`);
    return typeof entry === 'function' ? entry() : entry;
  };
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>(done => { resolve = done; });
  return {promise, resolve};
}

test('loads context before holdings, binds one account and wallet, and preserves raw balances', async () => {
  const paths: string[] = [];
  const h = harness((path, call) => {paths.push(path); return call === 1 ? json(context()) : json(holdings());});
  const notifications: string[] = [];
  const unsubscribe = h.store.subscribe(() => notifications.push(h.store.getSnapshot().phase));
  await h.store.refresh();
  const state = h.store.getSnapshot();
  assert.equal(state.phase, 'ready'); assert.equal(state.accountId, ACCOUNT); assert.equal(state.walletAddress, WALLET);
  assert.equal(state.portfolio?.subject, SUBJECT);
  assert.equal(state.portfolio?.holdings.holdings.balances.usdc.amountRaw, '10000000');
  assert.equal(typeof state.portfolio?.holdings.holdings.balances.aaplx.amountRaw, 'string');
  assert.equal(h.store.getReadyPortfolio(), state.portfolio);
  assert.deepEqual(paths, ['/v1/account/context', '/v1/account/holdings']);
  assert.equal(h.tokens, 2); assert.deepEqual(notifications, ['loading', 'loading', 'ready']);
  unsubscribe(); h.store.close();
});

test('ready expires on the observation deadline and delayed timers cannot make stale data ready', async () => {
  let now = BASE_NOW;
  let expiry: (() => void) | undefined;
  let delay = -1;
  const h = harness(sequence(json(context()), json(holdings())), {now: () => now,
    setTimer: (callback, milliseconds) => {expiry = callback; delay = milliseconds; return 1 as unknown as ReturnType<typeof setTimeout>;},
    clearTimer: () => {}});
  let notified = 0; h.store.subscribe(() => {notified++;});
  await h.store.refresh();
  assert.equal(delay, 500); assert.equal(h.store.getSnapshot().phase, 'ready');
  now += 500;
  const derivedStale = h.store.getSnapshot();
  assert.equal(derivedStale.phase, 'stale');
  assert.equal(derivedStale.issue, 'ACCOUNT_PORTFOLIO_OBSERVATION_EXPIRED');
  assert.equal(h.store.getSnapshot(), derivedStale, 'external-store snapshot remains referentially stable');
  assert.equal(h.store.getReadyPortfolio(), null);
  const before = notified; expiry?.();
  assert.equal(h.store.getSnapshot().phase, 'stale'); assert.equal(notified, before + 1);
  h.store.close();
});

test('expired and future observations never enter ready state', async () => {
  for (const [observedAt, issue, phase] of [
    ['2026-09-14T17:59:59.999Z', 'ACCOUNT_PORTFOLIO_OBSERVATION_EXPIRED', 'stale'],
    ['2026-09-14T18:00:01.101Z', 'ACCOUNT_PORTFOLIO_OBSERVATION_IN_FUTURE', 'error'],
  ] as const) {
    const h = harness(sequence(json(context()), json(holdings(ACCOUNT, WALLET, observedAt))));
    await h.store.refresh();
    assert.equal(h.store.getSnapshot().phase, phase); assert.equal(h.store.getSnapshot().issue, issue);
    assert.equal(h.store.getReadyPortfolio(), null); h.store.close();
  }
});

test('a Privy subject switch cancels in-flight work, clears data, and is terminal', async () => {
  const held = deferred<Response>();
  const h = harness(async () => held.promise);
  const pending = h.store.refresh(); await tick();
  h.store.observeSubject(OTHER_SUBJECT);
  assert.deepEqual(h.store.getSnapshot(), {phase: 'accountChanged', subject: SUBJECT, accountId: null,
    walletAddress: null, context: null, portfolio: null, issue: 'ACCOUNT_DATA_ACCOUNT_CHANGED'});
  await pending;
  held.resolve(json(context()));
  await assert.rejects(h.store.refresh(), {code: 'ACCOUNT_DATA_ACCOUNT_CHANGED'});
});

test('a changed server account or embedded wallet clears the prior portfolio and retires the store', async () => {
  for (const changed of ['account', 'context-wallet', 'holdings-wallet'] as const) {
    const responses: Response[] = [json(context()), json(holdings())];
    if (changed === 'account') responses.push(json(context(OTHER_ACCOUNT)));
    if (changed === 'context-wallet') responses.push(json(context(ACCOUNT, OTHER_WALLET)));
    if (changed === 'holdings-wallet') responses.push(json(context()), json(holdings(ACCOUNT, OTHER_WALLET)));
    const h = harness(sequence(...responses));
    await h.store.refresh(); await h.store.refresh();
    const state = h.store.getSnapshot();
    assert.equal(state.phase, 'accountChanged'); assert.equal(state.accountId, null);
    assert.equal(state.walletAddress, null); assert.equal(state.context, null); assert.equal(state.portfolio, null);
    assert.equal(state.issue, changed === 'account' ? 'ACCOUNT_DATA_ACCOUNT_CHANGED' : 'ACCOUNT_PORTFOLIO_WALLET_CHANGED');
    await assert.rejects(h.store.refresh(), {code: 'ACCOUNT_DATA_ACCOUNT_CHANGED'});
  }
});

test('missing and ambiguous wallets are explicit and holdings are never requested', async () => {
  for (const [wallet, issue] of [['missing', 'ACCOUNT_HOLDINGS_WALLET_MISSING'],
    ['ambiguous', 'ACCOUNT_HOLDINGS_WALLET_AMBIGUOUS']] as const) {
    const h = harness(sequence(json(context(ACCOUNT, wallet))));
    await h.store.refresh();
    assert.equal(h.calls, 1); assert.equal(h.store.getSnapshot().phase, 'error');
    assert.equal(h.store.getSnapshot().issue, issue); assert.equal(h.store.getReadyPortfolio(), null);
    h.store.close();
  }
});

test('transport outages retain same-wallet data explicitly offline, while authentication loss clears it', async () => {
  for (const [failure, status, expectedPhase, retains] of [
    ['STOCK_HOLDINGS_RPC_TIMEOUT', 504, 'offline', true],
    ['ACCOUNT_HOLDINGS_UNAUTHENTICATED', 401, 'error', false],
  ] as const) {
    const h = harness(sequence(json(context()), json(holdings()), json(context()), error(failure, status)));
    await h.store.refresh(); const first = h.store.getReadyPortfolio(); assert.ok(first);
    await h.store.refresh(); const state = h.store.getSnapshot();
    assert.equal(state.phase, expectedPhase); assert.equal(state.issue, failure);
    assert.equal(state.portfolio === first, retains); assert.equal(h.store.getReadyPortfolio(), null);
    if (!retains) {
      assert.equal(state.context, null);
      assert.equal(state.accountId, ACCOUNT);
      assert.equal(state.walletAddress, WALLET);
    }
    h.store.close();
  }
});

test('concurrent refreshes share one operation, cancellation masks late data, and close is terminal', async () => {
  const contextGate = deferred<Response>();
  const h = harness(async () => contextGate.promise);
  const first = h.store.refresh(); const second = h.store.refresh();
  assert.equal(first, second); await tick(); assert.equal(h.calls, 1);
  h.store.cancelRefresh();
  assert.equal(h.store.getSnapshot().phase, 'cancelled'); assert.equal(h.store.getReadyPortfolio(), null);
  await first; contextGate.resolve(json(context()));
  h.store.close(); assert.equal(h.store.getSnapshot().phase, 'closed');
  await assert.rejects(h.store.refresh(), {code: 'ACCOUNT_DATA_CLOSED'});
  assert.throws(() => h.store.subscribe(() => {}), {code: 'ACCOUNT_DATA_CLOSED'});
});

test('invalid freshness policy fails before any read', () => {
  const client = new AccountDataClient({apiOrigin: 'https://api.example', subject: SUBJECT, accountId: ACCOUNT,
    currentSubject: () => SUBJECT, accessToken: async () => TOKEN, fetch: async () => json(context())});
  for (const changes of [{maximumObservationAgeMs: 0}, {maximumObservationAgeMs: 300_001},
    {maximumFutureSkewMs: -1}, {maximumFutureSkewMs: 60_001}]) {
    assert.throws(() => new AccountPortfolioStore({client, ...changes}), {code: 'ACCOUNT_DATA_INVALID_CONFIGURATION'});
  }
  client.close();
});

test('clock failures become fixed local errors in reads and timer callbacks', async () => {
  let clockFails = false;
  let expiry: (() => void) | undefined;
  const h = harness(sequence(json(context()), json(holdings())), {
    now: () => {if (clockFails) throw new Error('private clock detail'); return BASE_NOW;},
    setTimer: callback => {expiry = callback; return 1 as unknown as ReturnType<typeof setTimeout>;},
    clearTimer: () => {},
  });
  await h.store.refresh(); assert.equal(h.store.getSnapshot().phase, 'ready');
  clockFails = true;
  const failedSnapshot = h.store.getSnapshot();
  assert.equal(failedSnapshot.phase, 'error');
  assert.equal(failedSnapshot.issue, 'ACCOUNT_DATA_RESPONSE_INVALID');
  assert.equal(failedSnapshot.portfolio, h.store.getSnapshot().portfolio);
  assert.equal(h.store.getReadyPortfolio(), null);
  assert.equal(h.store.getSnapshot(), failedSnapshot, 'derived clock failure is referentially stable');
  assert.doesNotThrow(() => expiry?.());
  assert.equal(h.store.getSnapshot().phase, 'error');
  assert.equal(h.store.getSnapshot().issue, 'ACCOUNT_DATA_RESPONSE_INVALID');
  h.store.close();
});

test('offline connectivity is explicit, performs no read, retains only an unusable prior observation', async () => {
  const h = harness(sequence(json(context()), json(holdings())));
  h.store.observeConnectivity(false);
  assert.equal(h.calls, 0);
  assert.deepEqual(h.store.getSnapshot(), {phase: 'offline', subject: SUBJECT, accountId: ACCOUNT,
    walletAddress: null, context: null, portfolio: null, issue: 'ACCOUNT_DATA_NETWORK_ERROR'});
  await h.store.refresh();
  const ready = h.store.getReadyPortfolio();
  assert.ok(ready);
  h.store.observeConnectivity(false);
  assert.equal(h.calls, 2);
  assert.equal(h.store.getSnapshot().phase, 'offline');
  assert.equal(h.store.getSnapshot().portfolio, ready);
  assert.equal(h.store.getReadyPortfolio(), null);
  h.store.close();
});

test('throwing setTimer and synchronous timer callbacks fail closed without escaping refresh', async () => {
  for (const setTimer of [
    () => {throw new Error('private timer detail');},
    (callback: () => void) => {callback(); return 1 as unknown as ReturnType<typeof setTimeout>;},
  ]) {
    const h = harness(sequence(json(context()), json(holdings())), {setTimer, clearTimer: () => {}});
    await assert.doesNotReject(h.store.refresh());
    assert.equal(h.store.getSnapshot().phase, 'error');
    assert.equal(h.store.getSnapshot().issue, 'ACCOUNT_DATA_RESPONSE_INVALID');
    assert.equal(h.store.getReadyPortfolio(), null);
    assert.doesNotThrow(() => h.store.close());
  }
});

test('throwing clearTimer cannot escape refresh, subject invalidation, connectivity, or close', async () => {
  for (const action of ['refresh', 'subject', 'offline', 'close'] as const) {
    const h = harness(sequence(json(context()), json(holdings())), {
      setTimer: () => 1 as unknown as ReturnType<typeof setTimeout>,
      clearTimer: () => {throw new Error('private timer cleanup detail');},
    });
    await h.store.refresh();
    assert.equal(h.store.getSnapshot().phase, 'ready');
    if (action === 'refresh') {
      await assert.doesNotReject(h.store.refresh());
      assert.equal(h.store.getSnapshot().phase, 'error');
      assert.equal(h.store.getSnapshot().issue, 'ACCOUNT_DATA_RESPONSE_INVALID');
      assert.equal(h.calls, 2, 'timer cleanup failure stops the next network read');
    }
    if (action === 'subject') {
      assert.doesNotThrow(() => h.store.observeSubject(OTHER_SUBJECT));
      assert.equal(h.store.getSnapshot().phase, 'accountChanged');
    }
    if (action === 'offline') {
      assert.doesNotThrow(() => h.store.observeConnectivity(false));
      assert.equal(h.store.getSnapshot().phase, 'error');
      assert.equal(h.store.getSnapshot().issue, 'ACCOUNT_DATA_RESPONSE_INVALID');
    }
    assert.doesNotThrow(() => h.store.close());
    assert.equal(h.store.getSnapshot().phase, 'closed');
  }
});
