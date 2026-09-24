import assert from 'node:assert/strict';
import test from 'node:test';
import {setImmediate as tick} from 'node:timers/promises';
import {AccountDataClient} from '../src/account/account-data-client.js';
import {
  ACCOUNT_DATA_AAPLX_MINT,
  ACCOUNT_DATA_MAINNET_GENESIS,
  ACCOUNT_DATA_USDC_MINT,
  AccountDataError,
  parseAccountContext,
  parseAccountHoldings,
} from '../src/account/account-data-models.js';

const SUBJECT = 'did:privy:accountDataSubject';
const OTHER_SUBJECT = 'did:privy:anotherSubject';
const ACCOUNT = '10000000-0000-4000-a000-000000000001';
const OTHER_ACCOUNT = '20000000-0000-4000-a000-000000000002';
const WALLET = 'FVen3X669xLzsi6N2V91DoiyzHzg1uAgqiT8jZ9nS96Z';
const TOKEN = 'eyJhbGciOiJFUzI1NiJ9.eyJzdWIiOiJmaXh0dXJlIn0.c2lnbmF0dXJl'; // gitleaks:allow -- synthetic JWT fixture with deliberately invalid signature

const contextFixture = (changes: Record<string, unknown> = {}) => ({
  schemaVersion: 1, userId: ACCOUNT,
  xIdentity: {status: 'verified', subject: '18446744073709551615', usernameSnapshot: 'trimmyhq',
    verifiedAtUnixSeconds: 1_757_845_200},
  embeddedSolanaWallet: {status: 'candidate', address: WALLET, verifiedAtUnixSeconds: 1_757_845_201},
  ...changes,
});

const tokenBalance = (symbol: 'USDC' | 'AAPLx', changes: Record<string, unknown> = {}) => ({
  symbol, mint: symbol === 'USDC' ? ACCOUNT_DATA_USDC_MINT : ACCOUNT_DATA_AAPLX_MINT,
  decimals: symbol === 'USDC' ? 6 : 8,
  amountRaw: symbol === 'USDC' ? '18446744073709551615' : '9007199254740993',
  amountUnits: 'raw_token_units', observedSlot: symbol === 'USDC' ? 101 : 102,
  accountCount: 1, accountTopology: 'associated_only', aggregation: 'all_valid_owner_token_accounts',
  hasFrozenAccounts: false, ...changes,
});

const holdingsFixture = (changes: Record<string, unknown> = {}) => ({
  schemaVersion: 1, userId: ACCOUNT,
  wallet: {address: WALLET, source: 'privy_embedded_wallet_same_subject', possessionSignatureVerified: false},
  holdings: {
    network: 'solana:mainnet-beta', genesisHash: ACCOUNT_DATA_MAINNET_GENESIS, commitment: 'confirmed',
    observedAt: '2026-09-14T18:00:00.000Z', readOnly: true, transactionBuilt: false,
    transactionSigned: false, transactionBroadcast: false,
    balances: {
      nativeSol: {symbol: 'SOL', decimals: 9, amountRaw: '9007199254740991', amountUnits: 'lamports', observedSlot: 100},
      usdc: tokenBalance('USDC'),
      aaplx: {...tokenBalance('AAPLx'), displayResolution: 'token_2022_scaled_ui_unresolved', displayAmount: null,
        shareAmount: null, eligibility: 'unverified', executionEnabled: false},
    },
    consistency: {kind: 'independent_confirmed_reads', atomic: false,
      slots: {nativeSol: 100, usdc: 101, aaplx: 102}},
  },
  ...changes,
});

const json = (value: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(value), {status, headers: {'content-type': 'application/json', ...headers}});
const serverError = (code: string, status: number) => json({error: {
  code, message: 'discard this server detail', requestId: 'aaaaaaaa-1234-5678-aaaa-123456789abc',
}}, status);

function makeClient(fetch: typeof globalThis.fetch, options: {timeoutMs?: number; currentSubject?: () => string | null;
  accessToken?: (expected: string) => Promise<string | null>; accountId?: string} = {}) {
  return new AccountDataClient({apiOrigin: 'https://api.example', subject: SUBJECT,
    accountId: options.accountId ?? ACCOUNT,
    currentSubject: options.currentSubject ?? (() => SUBJECT),
    accessToken: options.accessToken ?? (async () => TOKEN), fetch, timeoutMs: options.timeoutMs ?? 1_000});
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>(done => { resolve = done; });
  return {promise, resolve};
}

test('dispatches only the two fixed authenticated GETs and gets a fresh subject-bound token for each', async () => {
  const requests: Array<{url: string; init: RequestInit | undefined}> = [];
  const tokenSubjects: string[] = [];
  const api = makeClient(async (input, init) => {
    requests.push({url: String(input), init});
    return String(input).endsWith('/context') ? json(contextFixture()) : json(holdingsFixture());
  }, {accessToken: async expected => { tokenSubjects.push(expected); return TOKEN; }});
  const context = await api.readContext();
  const holdings = await api.readHoldings();
  assert.equal(context.userId, ACCOUNT);
  assert.deepEqual(tokenSubjects, [SUBJECT, SUBJECT]);
  assert.deepEqual(requests.map(value => value.url), [
    'https://api.example/v1/account/context', 'https://api.example/v1/account/holdings',
  ]);
  for (const {init} of requests) {
    assert.equal(init?.method, 'GET');
    assert.deepEqual(init?.headers, {accept: 'application/json', authorization: `Bearer ${TOKEN}`});
    assert.equal(init?.body, undefined); assert.equal(init?.credentials, 'omit');
    assert.equal(init?.cache, 'no-store'); assert.equal(init?.redirect, 'error');
    assert.equal(init?.referrerPolicy, 'no-referrer');
  }
  assert.equal(holdings.holdings.balances.usdc.amountRaw, '18446744073709551615');
  assert.equal(holdings.holdings.balances.aaplx.amountRaw, '9007199254740993');
  assert.equal(typeof holdings.holdings.balances.aaplx.amountRaw, 'string');
  assert.equal(holdings.holdings.balances.aaplx.displayAmount, null);
  assert.ok(Object.isFrozen(holdings) && Object.isFrozen(holdings.holdings.balances));
});

test('configuration and current subject fail closed before token or network access', async () => {
  let tokenCalls = 0, fetchCalls = 0;
  for (const apiOrigin of ['http://api.example', 'https://name:secret@api.example', 'https://api.example/path',
    'https://api.example?token=x', 'https://api.example#x', 'https://api.example\n']) {
    assert.throws(() => new AccountDataClient({apiOrigin, subject: SUBJECT, accountId: ACCOUNT,
      currentSubject: () => SUBJECT,
      accessToken: async () => TOKEN}), {code: 'ACCOUNT_DATA_INVALID_CONFIGURATION'});
  }
  const api = makeClient(async () => { fetchCalls++; return json(contextFixture()); }, {
    currentSubject: () => OTHER_SUBJECT,
    accessToken: async () => { tokenCalls++; return TOKEN; },
  });
  await assert.rejects(api.readContext(), {code: 'ACCOUNT_DATA_ACCOUNT_CHANGED'});
  assert.equal(tokenCalls, 0); assert.equal(fetchCalls, 0);
  await assert.rejects(makeClient(async () => json(contextFixture()), {
    currentSubject: () => {throw new Error('private auth state');},
  }).readContext(), {code: 'ACCOUNT_DATA_ACCOUNT_CHANGED'});
  await assert.rejects(makeClient(async () => json(contextFixture({userId: OTHER_ACCOUNT}))).readContext(),
    {code: 'ACCOUNT_DATA_ACCOUNT_CHANGED'});
  assert.throws(() => makeClient(async () => json({}), {accountId: OTHER_ACCOUNT.toUpperCase()}),
    {code: 'ACCOUNT_DATA_INVALID_CONFIGURATION'});
});

test('subject changes before token completion, after fetch, and on explicit observation invalidate late results', async () => {
  for (const stage of ['token', 'fetch', 'observed'] as const) {
    let current = SUBJECT;
    const tokenGate = deferred<string | null>();
    const fetchGate = deferred<Response>();
    const api = makeClient(async () => fetchGate.promise, {
      currentSubject: () => current,
      accessToken: async () => stage === 'token' ? tokenGate.promise : TOKEN,
    });
    const pending = api.readContext();
    if (stage === 'token') { current = OTHER_SUBJECT; tokenGate.resolve(TOKEN); }
    if (stage === 'fetch') { await tick(); current = OTHER_SUBJECT; fetchGate.resolve(json(contextFixture())); }
    if (stage === 'observed') { await tick(); api.observeSubject(null); fetchGate.resolve(json(contextFixture())); }
    await assert.rejects(pending, {code: 'ACCOUNT_DATA_ACCOUNT_CHANGED'}, stage);
    api.observeSubject(SUBJECT);
    await assert.rejects(api.readContext(), {code: 'ACCOUNT_DATA_ACCOUNT_CHANGED'});
  }
});

test('timeout, caller cancellation, cancelPending and close stop token, fetch and streamed-body work', async () => {
  const never = new Promise<string | null>(() => {});
  const timeout = makeClient(async () => json(contextFixture()), {timeoutMs: 5, accessToken: async () => never});
  await assert.rejects(timeout.readContext(), {code: 'ACCOUNT_DATA_TIMEOUT'});

  for (const action of ['signal', 'cancel', 'close'] as const) {
    const held = deferred<Response>();
    const api = makeClient(async () => held.promise);
    const controller = new AbortController();
    const pending = api.readContext({signal: controller.signal});
    await tick();
    if (action === 'signal') controller.abort();
    if (action === 'cancel') api.cancelPending();
    if (action === 'close') api.close();
    await assert.rejects(pending, {code: action === 'close' ? 'ACCOUNT_DATA_CLOSED' : 'ACCOUNT_DATA_CANCELLED'});
    held.resolve(json(contextFixture()));
  }
});

test('redirects, cross-origin response URLs, media types, UTF-8 and declared or streamed limits are rejected', async () => {
  const redirected = json(contextFixture());
  Object.defineProperty(redirected, 'redirected', {value: true});
  const crossed = json(contextFixture());
  Object.defineProperty(crossed, 'url', {value: 'https://other.example/v1/account/context'});
  const oversizedStream = new ReadableStream<Uint8Array>({start(controller) {
    controller.enqueue(new Uint8Array(65_537)); controller.close();
  }});
  const cases: ReadonlyArray<readonly [Response, string]> = [
    [new Response('', {status: 302, headers: {location: 'https://other.example'}}), 'ACCOUNT_DATA_REDIRECT_REJECTED'],
    [redirected, 'ACCOUNT_DATA_REDIRECT_REJECTED'], [crossed, 'ACCOUNT_DATA_REDIRECT_REJECTED'],
    [new Response('{}', {headers: {'content-type': 'text/html'}}), 'ACCOUNT_DATA_RESPONSE_INVALID'],
    [new Response('{}', {headers: {'content-type': 'application/json; charset=utf-8; profile=x'}}), 'ACCOUNT_DATA_RESPONSE_INVALID'],
    [new Response(new Uint8Array([255]), {headers: {'content-type': 'application/json'}}), 'ACCOUNT_DATA_RESPONSE_INVALID'],
    [new Response('{', {headers: {'content-type': 'application/json'}}), 'ACCOUNT_DATA_RESPONSE_INVALID'],
    [json(contextFixture(), 200, {'content-length': '65537'}), 'ACCOUNT_DATA_RESPONSE_TOO_LARGE'],
    [new Response(oversizedStream, {headers: {'content-type': 'application/json'}}), 'ACCOUNT_DATA_RESPONSE_TOO_LARGE'],
  ];
  for (const [response, code] of cases) {
    await assert.rejects(makeClient(async () => response).readContext(), {code});
  }
});

test('only documented status and error-code pairs cross the transport boundary', async () => {
  for (const [method, code, status] of [
    ['context', 'PRIVY_USER_RATE_LIMITED', 429],
    ['context', 'PRIVY_USER_TIMEOUT', 504],
    ['holdings', 'ACCOUNT_HOLDINGS_WALLET_AMBIGUOUS', 409],
    ['holdings', 'STOCK_HOLDINGS_RATE_LIMITED', 429],
    ['holdings', 'STOCK_HOLDINGS_RPC_RESPONSE_INVALID', 502],
  ] as const) {
    const api = makeClient(async () => serverError(code, status));
    const result = method === 'context' ? api.readContext() : api.readHoldings();
    await assert.rejects(result, {code});
  }
  for (const response of [serverError('PRIVY_USER_TIMEOUT', 502), serverError('PRIVATE_PROVIDER_ERROR', 502),
    json({error: {code: 'PRIVY_USER_TIMEOUT', message: 'x', requestId: 'id', debug: 'private'}}, 504),
    new Response('', {status: 500, headers: {'content-type': 'application/json'}})]) {
    await assert.rejects(makeClient(async () => response).readContext(), {code: 'ACCOUNT_DATA_RESPONSE_INVALID'});
  }
});

test('strict parsers bind the account, wallet, mainnet, mints, raw amounts and independent slots', () => {
  const context = parseAccountContext(contextFixture());
  assert.equal(context.userId, ACCOUNT);
  assert.equal(context.embeddedSolanaWallet.status, 'candidate');
  assert.equal(parseAccountHoldings(holdingsFixture(), ACCOUNT).wallet.address, WALLET);
  assert.throws(() => parseAccountHoldings(holdingsFixture({userId: OTHER_ACCOUNT}), ACCOUNT),
    {code: 'ACCOUNT_DATA_ACCOUNT_CHANGED'});
  const mutations: Array<(value: ReturnType<typeof holdingsFixture>) => void> = [
    value => {value.wallet.address = '11111111111111111111111111111111';},
    value => {value.holdings.network = 'solana:devnet';},
    value => {value.holdings.genesisHash = 'wrong';},
    value => {value.holdings.balances.usdc.mint = ACCOUNT_DATA_AAPLX_MINT;},
    value => {value.holdings.balances.usdc.amountRaw = '01';},
    value => {(value.holdings.balances.aaplx as Record<string, unknown>)['displayAmount'] = '1';},
    value => {value.holdings.consistency.slots.aaplx = 101;},
    value => {Object.assign(value.holdings, {privateRpcUrl: 'https://rpc/?key=private'});},
  ];
  for (const mutate of mutations) {
    const value = structuredClone(holdingsFixture()); mutate(value);
    assert.throws(() => parseAccountHoldings(value, ACCOUNT), {code: 'ACCOUNT_DATA_RESPONSE_INVALID'});
  }
  for (const value of [contextFixture({schemaVersion: 2}), contextFixture({userId: ACCOUNT.toUpperCase()}),
    contextFixture({embeddedSolanaWallet: {status: 'candidate', address: '11111111111111111111111111111111',
      verifiedAtUnixSeconds: 1}}), contextFixture({xIdentity: {status: 'verified', subject: '0',
      usernameSnapshot: 'trimmyhq', verifiedAtUnixSeconds: 1}})]) {
    assert.throws(() => parseAccountContext(value), {code: 'ACCOUNT_DATA_RESPONSE_INVALID'});
  }
});

test('token failures are sanitized and close is terminal', async () => {
  const privateDetail = 'provider secret detail';
  for (const accessToken of [async () => null, async () => 'opaque', async () => `${TOKEN}\n`,
    async () => {throw new Error(privateDetail); }]) {
    await assert.rejects(makeClient(async () => json(contextFixture()), {accessToken}).readContext(), error => {
      assert.ok(error instanceof AccountDataError);
      assert.equal(error.code, 'ACCOUNT_DATA_TOKEN_UNAVAILABLE');
      assert.ok(!error.message.includes(privateDetail));
      return true;
    });
  }
  const api = makeClient(async () => json(contextFixture())); api.close();
  await assert.rejects(api.readContext(), {code: 'ACCOUNT_DATA_CLOSED'});
  api.observeSubject(SUBJECT);
  await assert.rejects(api.readContext(), {code: 'ACCOUNT_DATA_CLOSED'});
});
