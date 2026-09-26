import assert from 'node:assert/strict';
import {inspect} from 'node:util';
import {test} from 'node:test';
import {buildApp} from '../src/app.js';
import {
  ACCOUNT_HOLDINGS_ROUTE,
} from '../src/account-holdings-route.js';
import type {
  AccountHoldingsAdapters,
  AccountHoldingsReader,
} from '../src/account-holdings-route.js';
import {JUPITER_QUOTE_ASSETS} from '../src/jupiter-quote-reader.js';
import {STOCK_TRADING_ASSETS} from '../src/stock-trading-catalog.js';
import type {PracticeIdentity} from '../src/practice-identity.js';
import {
  createPracticeAccountContextAuthenticator,
  PracticeAuthenticationUnavailable,
} from '../src/practice-session-routes.js';
import {PrivyLinkedIdentityError} from '../src/privy-linked-identities.js';
import type {
  PrivyLinkedIdentityErrorCode,
  PrivyLinkedIdentityResolution,
} from '../src/privy-linked-identities.js';
import {
  readSolanaStockHoldingsReader,
  STOCK_HOLDINGS_MAINNET_GENESIS,
  STOCK_HOLDINGS_TOKEN_PROGRAMS,
  StockHoldingsError,
} from '../src/stock-holdings.js';
import type {
  ServerVerifiedStockOwner,
  StockHoldingsErrorCode,
  StockHoldingsSnapshot,
} from '../src/stock-holdings.js';

const appId = 'trimmy_test_app';
const subject = 'did:privy:holdingssubject';
const userId = '10000000-0000-4000-a000-000000000001';
const otherUserId = '20000000-0000-4000-a000-000000000002';
const token = 'eyJhbGciOiJFUzI1NiJ9.eyJzdWIiOiJ0ZXN0In0.c2lnbmF0dXJl'; // gitleaks:allow -- synthetic JWT fixture with deliberately invalid signature
const walletAddress = 'FVen3X669xLzsi6N2V91DoiyzHzg1uAgqiT8jZ9nS96Z';
const otherWalletAddress = 'FbP8bwmje245N5k3GTrx7BcKcDwbJNbfvEaEbF8eewY1';
const identity: PracticeIdentity = {provider: 'privy', appId, subject};
const resolution: PrivyLinkedIdentityResolution = Object.freeze({
  provider: 'privy',
  subject,
  twitter: Object.freeze({status: 'missing'}),
  embeddedSolanaWallet: Object.freeze({
    status: 'candidate',
    address: walletAddress,
    verifiedAtUnixSeconds: 1_757_845_201,
  }),
});

function tokenBalance(symbol: 'USDC' | 'AAPLx') {
  const usdc = symbol === 'USDC';
  return Object.freeze({
    kind: 'spl_token' as const,
    symbol,
    mint: usdc ? JUPITER_QUOTE_ASSETS.USDC.mint : JUPITER_QUOTE_ASSETS.AAPLx.mint,
    tokenProgram: usdc ? STOCK_HOLDINGS_TOKEN_PROGRAMS.legacy : STOCK_HOLDINGS_TOKEN_PROGRAMS.token2022,
    decimals: usdc ? 6 as const : 8 as const,
    amountRaw: '0',
    amountUnits: 'raw_token_units' as const,
    observedSlot: usdc ? 101 : 102,
    accounts: Object.freeze([]),
    associatedTokenAccount: Object.freeze({address: walletAddress, status: 'absent' as const}),
    accountTopology: 'none' as const,
    aggregation: 'all_valid_owner_token_accounts' as const,
    hasFrozenAccounts: false,
  });
}

const snapshot = Object.freeze({
  schemaVersion: 1 as const,
  network: 'solana:mainnet-beta' as const,
  genesisHash: STOCK_HOLDINGS_MAINNET_GENESIS,
  commitment: 'confirmed' as const,
  owner: walletAddress,
  ownerBinding: 'trusted_server_capability' as const,
  observedAt: '2026-09-14T18:00:00.000Z',
  readOnly: true as const,
  transactionBuilt: false as const,
  transactionSigned: false as const,
  transactionBroadcast: false as const,
  balances: Object.freeze({
    nativeSol: Object.freeze({kind: 'native' as const, symbol: 'SOL' as const, decimals: 9 as const,
      amountRaw: '20000000', amountUnits: 'lamports' as const, observedSlot: 100}),
    usdc: tokenBalance('USDC'),
    aaplx: Object.freeze({...tokenBalance('AAPLx'),
      displayResolution: 'token_2022_scaled_ui_unresolved' as const,
      displayAmount: null,
      shareAmount: null,
      eligibility: 'unverified' as const,
      executionEnabled: false as const}),
  }),
  consistency: Object.freeze({kind: 'independent_confirmed_reads' as const, atomic: false as const,
    slots: Object.freeze({nativeSol: 100, usdc: 101, aaplx: 102})}),
}) as unknown as StockHoldingsSnapshot;

function adapters(
  holdings: AccountHoldingsReader = {read: async () => snapshot},
  linkedIdentities: AccountHoldingsAdapters['linkedIdentities'] = {resolve: async () => resolution},
  authenticate: AccountHoldingsAdapters['authenticate'] = async () => ({userId, identity}),
): AccountHoldingsAdapters {
  return {authenticate, linkedIdentities, holdings};
}

test('holdings are disabled by default and server RPC configuration is explicit', async () => {
  const instance = buildApp({logger: false});
  try {
    const response = await instance.inject(ACCOUNT_HOLDINGS_ROUTE);
    assert.equal(response.statusCode, 503);
    assert.equal(response.json().error.code, 'ACCOUNT_HOLDINGS_UNAVAILABLE');
    assert.equal(response.headers['cache-control'], 'no-store');
    assert.equal((await instance.inject('/v1/config')).json().accountHoldingsEnabled, false);
  } finally { await instance.close(); }

  const rpcUrl = 'https://mainnet.rpc.example/v1?api-key=server-only';
  for (const env of [{}, {SOLANA_MAINNET_RPC_URL: rpcUrl},
    {TRIMMY_STOCK_HOLDINGS: ''}, {TRIMMY_STOCK_HOLDINGS: 'disabled', SOLANA_MAINNET_RPC_URL: rpcUrl}]) {
    assert.equal(readSolanaStockHoldingsReader(env), undefined);
  }
  for (const env of [
    {TRIMMY_STOCK_HOLDINGS: 'solana_mainnet'},
    {TRIMMY_STOCK_HOLDINGS: 'mainnet', SOLANA_MAINNET_RPC_URL: rpcUrl},
    {TRIMMY_STOCK_HOLDINGS: 'solana_mainnet', SOLANA_MAINNET_RPC_URL: 'http://private.rpc.example'},
  ]) {
    assert.throws(() => readSolanaStockHoldingsReader(env), error => {
      assert.ok(error instanceof StockHoldingsError);
      assert.equal(error.code, 'STOCK_HOLDINGS_CONFIGURATION_INVALID');
      assert.ok(!inspect(error).includes('server-only'));
      return true;
    });
  }
  assert.ok(readSolanaStockHoldingsReader({
    TRIMMY_STOCK_HOLDINGS: 'solana_mainnet', SOLANA_MAINNET_RPC_URL: rpcUrl,
  }, {fetch: async () => { throw new Error('must not run during configuration'); }}));
});

test('returns a strict public projection for the server-derived same-subject wallet', async () => {
  let resolvedIdentity: PracticeIdentity | undefined;
  let admittedOwner: ServerVerifiedStockOwner | undefined;
  const privateValue = 'private-adapter-diagnostic';
  const injectedSnapshot = {
    ...snapshot,
    rpcUrl: `https://rpc.example/?key=${privateValue}`,
    balances: {
      ...snapshot.balances,
      nativeSol: {...snapshot.balances.nativeSol, secret: privateValue},
      usdc: {...snapshot.balances.usdc, accounts: [], providerMetadata: privateValue},
      aaplx: {...snapshot.balances.aaplx, accounts: [], delegated: true},
    },
  } as unknown as StockHoldingsSnapshot;
  const instance = buildApp({logger: false, accountHoldings: adapters({
    read: async owner => {
      admittedOwner = owner;
      assert.ok(Object.isFrozen(owner));
      return injectedSnapshot;
    },
  }, {resolve: async value => {
    resolvedIdentity = value;
    return {...resolution, oauthToken: privateValue} as unknown as PrivyLinkedIdentityResolution;
  }})});
  try {
    const response = await instance.inject({
      url: ACCOUNT_HOLDINGS_ROUTE,
      headers: {authorization: `Bearer ${token}`, 'x-wallet-address': otherWalletAddress},
    });
    assert.equal(response.statusCode, 200, response.body);
    assert.deepEqual(resolvedIdentity, identity);
    assert.equal(admittedOwner?.authenticatedUserId, userId);
    assert.equal(admittedOwner?.address, walletAddress);
    assert.equal(admittedOwner?.verification, 'authenticated_privy_embedded_wallet');
    assert.deepEqual(response.json(), {
      schemaVersion: 1,
      userId,
      wallet: {address: walletAddress, source: 'privy_embedded_wallet_same_subject',
        possessionSignatureVerified: false},
      holdings: {
        network: 'solana:mainnet-beta', genesisHash: STOCK_HOLDINGS_MAINNET_GENESIS,
        commitment: 'confirmed', observedAt: '2026-09-14T18:00:00.000Z', readOnly: true,
        transactionBuilt: false, transactionSigned: false, transactionBroadcast: false,
        balances: {
          nativeSol: {symbol: 'SOL', decimals: 9, amountRaw: '20000000', amountUnits: 'lamports', observedSlot: 100},
          usdc: {symbol: 'USDC', mint: JUPITER_QUOTE_ASSETS.USDC.mint, decimals: 6, amountRaw: '0',
            amountUnits: 'raw_token_units', observedSlot: 101, accountCount: 0, accountTopology: 'none',
            aggregation: 'all_valid_owner_token_accounts', hasFrozenAccounts: false},
          aaplx: {symbol: 'AAPLx', mint: JUPITER_QUOTE_ASSETS.AAPLx.mint, decimals: 8, amountRaw: '0',
            amountUnits: 'raw_token_units', observedSlot: 102, accountCount: 0, accountTopology: 'none',
            aggregation: 'all_valid_owner_token_accounts', hasFrozenAccounts: false,
            displayResolution: 'token_2022_scaled_ui_unresolved', displayAmount: null, shareAmount: null,
            eligibility: 'unverified', executionEnabled: false},
        },
        consistency: {kind: 'independent_confirmed_reads', atomic: false,
          slots: {nativeSol: 100, usdc: 101, aaplx: 102}},
      },
    });
    assert.equal(response.headers['cache-control'], 'no-store');
    assert.equal((await instance.inject('/v1/config')).json().accountHoldingsEnabled, true);
    for (const forbidden of [subject, otherWalletAddress, privateValue, 'rpcUrl', 'oauthToken',
      'providerMetadata', 'delegated', 'associatedTokenAccount', 'ownerBinding']) {
      assert.ok(!response.body.includes(forbidden), forbidden);
    }
  } finally { await instance.close(); }
});

test('real existing-account authentication never provisions and preserves the exact Privy subject', async () => {
  let verifies = 0, finds = 0, provisions = 0, providerCalls = 0, holdingsCalls = 0;
  const authenticate = createPracticeAccountContextAuthenticator({
    verifier: {verify: async input => { verifies += 1; return input === token ? identity : null; }},
    accounts: {
      find: async value => { finds += 1; assert.deepEqual(value, identity); return {userId}; },
      provision: async () => { provisions += 1; return {userId: otherUserId}; },
    },
  });
  const instance = buildApp({logger: false, accountHoldings: adapters({
    read: async () => { holdingsCalls += 1; return snapshot; },
  }, {resolve: async value => {
    providerCalls += 1;
    assert.deepEqual(value, identity);
    return resolution;
  }}, authenticate)});
  try {
    const response = await instance.inject({url: ACCOUNT_HOLDINGS_ROUTE,
      headers: {authorization: `Bearer ${token}`}});
    assert.equal(response.statusCode, 200, response.body);
    assert.equal(verifies, 1);
    assert.equal(finds, 1);
    assert.equal(provisions, 0);
    assert.equal(providerCalls, 1);
    assert.equal(holdingsCalls, 1);
  } finally { await instance.close(); }
});

test('unknown accounts and authentication failures cannot reach Privy or Solana', async () => {
  let providerCalls = 0, holdingsCalls = 0;
  const linked = {resolve: async () => { providerCalls += 1; return resolution; }};
  const holdings = {read: async () => { holdingsCalls += 1; return snapshot; }};
  for (const [authenticate, expectedStatus] of [
    [async () => null, 401],
    [async () => ({userId: 'caller-selected', identity}), 401],
    [async () => ({userId, identity: {...identity, subject: `${subject}\n`}}), 401],
    [async () => { throw new Error('private authentication diagnostic'); }, 401],
    [async () => { throw new PracticeAuthenticationUnavailable(); }, 503],
  ] as const) {
    const instance = buildApp({logger: false, accountHoldings: adapters(
      holdings, linked, authenticate as AccountHoldingsAdapters['authenticate'])});
    try {
      const response = await instance.inject(ACCOUNT_HOLDINGS_ROUTE);
      assert.equal(response.statusCode, expectedStatus);
      assert.ok(!response.body.includes('private authentication diagnostic'));
    } finally { await instance.close(); }
  }
  assert.equal(providerCalls, 0);
  assert.equal(holdingsCalls, 0);
});

test('missing, ambiguous, mismatched, and malformed linked wallets stop before Solana', async () => {
  let holdingsCalls = 0;
  const values: readonly [unknown, number, string][] = [
    [{...resolution, embeddedSolanaWallet: {status: 'missing'}}, 409, 'ACCOUNT_HOLDINGS_WALLET_MISSING'],
    [{...resolution, embeddedSolanaWallet: {status: 'ambiguous'}}, 409, 'ACCOUNT_HOLDINGS_WALLET_AMBIGUOUS'],
    [{...resolution, subject: 'did:privy:another-subject'}, 502, 'PRIVY_USER_RESPONSE_INVALID'],
    [{...resolution, embeddedSolanaWallet: {...resolution.embeddedSolanaWallet,
      address: '11111111111111111111111111111111'}}, 502, 'PRIVY_USER_RESPONSE_INVALID'],
    [{...resolution, embeddedSolanaWallet: {...resolution.embeddedSolanaWallet,
      address: 'not-a-wallet'}}, 502, 'PRIVY_USER_RESPONSE_INVALID'],
    [{...resolution, embeddedSolanaWallet: {...resolution.embeddedSolanaWallet,
      verifiedAtUnixSeconds: 0}}, 502, 'PRIVY_USER_RESPONSE_INVALID'],
    [{...resolution, provider: 'other'}, 502, 'PRIVY_USER_RESPONSE_INVALID'],
    [null, 502, 'PRIVY_USER_RESPONSE_INVALID'],
  ];
  for (const [value, status, code] of values) {
    const instance = buildApp({logger: false, accountHoldings: adapters({
      read: async () => { holdingsCalls += 1; return snapshot; },
    }, {resolve: async () => value as PrivyLinkedIdentityResolution})});
    try {
      const response = await instance.inject(ACCOUNT_HOLDINGS_ROUTE);
      assert.equal(response.statusCode, status, response.body);
      assert.equal(response.json().error.code, code);
    } finally { await instance.close(); }
  }
  assert.equal(holdingsCalls, 0);
});

test('provider and holdings failures are reconstructed without private messages', async () => {
  const privateValue = 'private-provider-or-rpc-diagnostic';
  for (const [code, status] of [
    ['PRIVY_LINKED_IDENTITIES_NOT_CONFIGURED', 503],
    ['PRIVY_VERIFIED_IDENTITY_INVALID', 503],
    ['PRIVY_USER_RESPONSE_INVALID', 502],
    ['PRIVY_USER_UNAVAILABLE', 502],
    ['PRIVY_USER_TIMEOUT', 504],
    ['PRIVY_USER_RATE_LIMITED', 429],
  ] as const satisfies readonly (readonly [PrivyLinkedIdentityErrorCode, number])[]) {
    const error = new PrivyLinkedIdentityError(code);
    error.message = privateValue;
    const instance = buildApp({logger: false, accountHoldings: adapters(undefined, {
      resolve: async () => { throw error; },
    })});
    try {
      const response = await instance.inject(ACCOUNT_HOLDINGS_ROUTE);
      assert.equal(response.statusCode, status);
      assert.equal(response.json().error.code, code);
      assert.ok(!response.body.includes(privateValue));
    } finally { await instance.close(); }
  }
  for (const [code, status] of [
    ['STOCK_HOLDINGS_OWNER_INVALID', 502],
    ['STOCK_HOLDINGS_OWNER_UNVERIFIED', 502],
    ['STOCK_HOLDINGS_CONFIGURATION_INVALID', 503],
    ['STOCK_HOLDINGS_RPC_UNAVAILABLE', 502],
    ['STOCK_HOLDINGS_RPC_TIMEOUT', 504],
    ['STOCK_HOLDINGS_RPC_RESPONSE_INVALID', 502],
    ['STOCK_HOLDINGS_WRONG_NETWORK', 503],
    ['STOCK_HOLDINGS_RATE_LIMITED', 429],
  ] as const satisfies readonly (readonly [StockHoldingsErrorCode, number])[]) {
    const error = new StockHoldingsError(code);
    error.message = privateValue;
    const instance = buildApp({logger: false, accountHoldings: adapters({
      read: async () => { throw error; },
    })});
    try {
      const response = await instance.inject(ACCOUNT_HOLDINGS_ROUTE);
      assert.equal(response.statusCode, status);
      assert.equal(response.json().error.code, code);
      assert.ok(!response.body.includes(privateValue));
    } finally { await instance.close(); }
  }
});

test('malformed reader snapshots fail closed instead of crossing HTTP', async () => {
  const invalid = [
    {...snapshot, owner: otherWalletAddress},
    {...snapshot, readOnly: false},
    {...snapshot, transactionSigned: true},
    {...snapshot, observedAt: 'not-a-date'},
    {...snapshot, balances: {...snapshot.balances,
      nativeSol: {...snapshot.balances.nativeSol, amountRaw: '01'}}},
    {...snapshot, balances: {...snapshot.balances,
      usdc: {...snapshot.balances.usdc, mint: JUPITER_QUOTE_ASSETS.AAPLx.mint}}},
    {...snapshot, balances: {...snapshot.balances,
      aaplx: {...snapshot.balances.aaplx, displayAmount: '0'}}},
    {...snapshot, consistency: {...snapshot.consistency,
      slots: {...snapshot.consistency.slots, nativeSol: 999}}},
    null,
  ];
  for (const value of invalid) {
    const instance = buildApp({logger: false, accountHoldings: adapters({
      read: async () => value as StockHoldingsSnapshot,
    })});
    try {
      const response = await instance.inject(ACCOUNT_HOLDINGS_ROUTE);
      assert.equal(response.statusCode, 502, response.body);
      assert.equal(response.json().error.code, 'STOCK_HOLDINGS_RPC_RESPONSE_INVALID');
    } finally { await instance.close(); }
  }
});

test('query, body, HEAD, and mutation attempts cannot authenticate, resolve, or read', async () => {
  let authCalls = 0, providerCalls = 0, holdingsCalls = 0;
  const instance = buildApp({logger: false, accountHoldings: adapters({
    read: async () => { holdingsCalls += 1; return snapshot; },
  }, {resolve: async () => { providerCalls += 1; return resolution; }},
  async () => { authCalls += 1; return {userId, identity}; })});
  try {
    for (const url of [
      `${ACCOUNT_HOLDINGS_ROUTE}?wallet=${otherWalletAddress}`,
      `${ACCOUNT_HOLDINGS_ROUTE}?address=${otherWalletAddress}`,
      `${ACCOUNT_HOLDINGS_ROUTE}?userId=${otherUserId}`,
      `${ACCOUNT_HOLDINGS_ROUTE}?token=private-token`,
      `${ACCOUNT_HOLDINGS_ROUTE}?x=1&x=2`,
    ]) {
      const response = await instance.inject(url);
      assert.equal(response.statusCode, 400, url);
      assert.equal(response.json().error.code, 'ACCOUNT_HOLDINGS_INVALID_REQUEST');
      assert.ok(!response.body.includes('private-token'));
    }
    assert.equal((await instance.inject({method: 'GET', url: ACCOUNT_HOLDINGS_ROUTE,
      headers: {'content-type': 'application/json'}, payload: {wallet: otherWalletAddress}})).statusCode, 400);
    assert.equal((await instance.inject({method: 'HEAD', url: ACCOUNT_HOLDINGS_ROUTE})).statusCode, 404);
    assert.equal((await instance.inject({method: 'POST', url: ACCOUNT_HOLDINGS_ROUTE,
      payload: {wallet: otherWalletAddress}})).statusCode, 503);
    assert.equal((await instance.inject({method: 'PUT', url: ACCOUNT_HOLDINGS_ROUTE,
      payload: {wallet: otherWalletAddress}})).statusCode, 503);
    assert.equal(authCalls, 0);
    assert.equal(providerCalls, 0);
    assert.equal(holdingsCalls, 0);
  } finally { await instance.close(); }
});

test('CORS grants only the exact read-only holdings preflight', async () => {
  let authCalls = 0, providerCalls = 0, holdingsCalls = 0;
  const origin = 'https://app.trimmy.example';
  const instance = buildApp({logger: false, browserOrigins: [origin], accountHoldings: adapters({
    read: async () => { holdingsCalls += 1; return snapshot; },
  }, {resolve: async () => { providerCalls += 1; return resolution; }},
  async () => { authCalls += 1; return {userId, identity}; })});
  const headers = {origin, 'access-control-request-method': 'GET',
    'access-control-request-headers': 'authorization'};
  try {
    const preflight = await instance.inject({method: 'OPTIONS', url: ACCOUNT_HOLDINGS_ROUTE, headers});
    assert.equal(preflight.statusCode, 204);
    assert.equal(preflight.headers['access-control-allow-origin'], origin);
    assert.equal(preflight.headers['access-control-allow-methods'], 'GET');
    assert.equal((await instance.inject({method: 'OPTIONS', url: `${ACCOUNT_HOLDINGS_ROUTE}?wallet=x`, headers})).statusCode, 403);
    assert.equal((await instance.inject({method: 'OPTIONS', url: ACCOUNT_HOLDINGS_ROUTE,
      headers: {...headers, 'access-control-request-method': 'POST'}})).statusCode, 403);
    assert.equal((await instance.inject({url: ACCOUNT_HOLDINGS_ROUTE,
      headers: {origin: 'https://unknown.example'}})).statusCode, 403);
    assert.equal(authCalls, 0);
    assert.equal(providerCalls, 0);
    assert.equal(holdingsCalls, 0);
    const response = await instance.inject({url: ACCOUNT_HOLDINGS_ROUTE, headers: {origin}});
    assert.equal(response.statusCode, 200, response.body);
    assert.equal(response.headers['access-control-allow-origin'], origin);
    assert.equal(authCalls, 1);
    assert.equal(providerCalls, 1);
    assert.equal(holdingsCalls, 1);
  } finally { await instance.close(); }
});

function portfolioSnapshot() {
  const asset = STOCK_TRADING_ASSETS.find(item => item.assetId === 'netflix')!;
  const stock = {
    ...tokenBalance('AAPLx'), assetId: asset.assetId, name: asset.name, symbol: asset.symbol, mint: asset.mint,
    amountRaw: '123456789',
    accounts: [{address: otherWalletAddress, amountRaw: '123456789', state: 'initialized', associated: false,
      displayAmount: '12.3456789'}],
    accountTopology: 'ancillary_only', displayAmount: '12.3456789', displayResolution: 'rpc_ui_amount',
    displayUnits: 'token_units',
  };
  return {...snapshot, balances: {...snapshot.balances, tokens: [stock]}} as unknown as StockHoldingsSnapshot;
}

test('version 2 exposes validated multi-stock holdings only to opted-in clients', async () => {
  const versions: unknown[] = [];
  const value = portfolioSnapshot();
  const instance = buildApp({logger: false, accountHoldings: adapters({
    read: async (_owner, version) => { versions.push(version); return value; },
  })});
  try {
    const legacy = await instance.inject(ACCOUNT_HOLDINGS_ROUTE);
    assert.equal(legacy.statusCode, 200, legacy.body);
    assert.equal(legacy.json().schemaVersion, 1);
    assert.deepEqual(Object.keys(legacy.json().holdings.balances), ['nativeSol', 'usdc', 'aaplx']);
    const response = await instance.inject({url: ACCOUNT_HOLDINGS_ROUTE,
      headers: {'x-trimmy-holdings-version': '2'}});
    assert.equal(response.statusCode, 200, response.body);
    const body = response.json();
    assert.equal(body.schemaVersion, 2);
    assert.deepEqual(body.holdings.balances.tokens, [{
      assetId: 'netflix', name: STOCK_TRADING_ASSETS.find(item => item.assetId === 'netflix')!.name,
      symbol: 'NFLXx', mint: STOCK_TRADING_ASSETS.find(item => item.assetId === 'netflix')!.mint,
      decimals: 8, amountRaw: '123456789', amountUnits: 'raw_token_units', observedSlot: 102,
      accountCount: 1, accountTopology: 'ancillary_only', aggregation: 'all_valid_owner_token_accounts',
      hasFrozenAccounts: false, displayAmount: '12.3456789', displayResolution: 'rpc_ui_amount', displayUnits: 'token_units',
      availableToTradeRaw: '0',
    }]);
    assert.equal(body.holdings.balances.usdc.availableToTradeRaw, '0');
    assert.equal(response.headers['vary'], 'Origin, X-Trimmy-Holdings-Version, X-Trimmy-Holdings-Min-Slot');
    assert.deepEqual(versions, [1, 2]);
    for (const forbidden of ['accounts', 'associatedTokenAccount', 'tokenProgram', otherWalletAddress]) {
      assert.ok(!response.body.includes(`"${forbidden}"`), forbidden);
    }
  } finally { await instance.close(); }
});

test('version 2 rejects fabricated stock metadata, double-counts and unverified display totals', async () => {
  const original = portfolioSnapshot();
  const tokens = original.balances.tokens!;
  const first = tokens[0]!;
  for (const changedTokens of [
    undefined, [first, first], [{...first, assetId: 'caller-stock'}], [{...first, name: 'Fake Netflix'}],
    [{...first, decimals: 6}], [{...first, displayAmount: '123.456789'}],
    [{...first, displayResolution: 'unavailable'}], [{...first, displayUnits: 'shares'}],
    [{...first, mint: JUPITER_QUOTE_ASSETS.USDC.mint}],
    [{...first, amountRaw: '0', accounts: []}],
  ]) {
    const value = {...original, balances: {...original.balances, tokens: changedTokens}} as unknown as StockHoldingsSnapshot;
    const instance = buildApp({logger: false, accountHoldings: adapters({read: async () => value})});
    try {
      const response = await instance.inject({url: ACCOUNT_HOLDINGS_ROUTE,
        headers: {'x-trimmy-holdings-version': '2'}});
      assert.equal(response.statusCode, 502, response.body);
      assert.equal(response.json().error.code, 'STOCK_HOLDINGS_RPC_RESPONSE_INVALID');
    } finally { await instance.close(); }
  }
});

test('unknown holdings versions stop before authentication and provider reads', async () => {
  let called = false;
  const instance = buildApp({logger: false, accountHoldings: adapters(undefined, undefined,
    async () => { called = true; return {userId, identity}; })});
  try {
    for (const version of ['3', '02', '2, 1', '']) {
      const response = await instance.inject({url: ACCOUNT_HOLDINGS_ROUTE,
        headers: {'x-trimmy-holdings-version': version}});
      assert.equal(response.statusCode, 400, response.body);
    }
    assert.equal(called, false);
  } finally { await instance.close(); }
});

test('v2 distinguishes a known empty stock portfolio from an unavailable display amount', async () => {
  const original = portfolioSnapshot();
  const first = original.balances.tokens![0]!;
  for (const tokens of [[], [{...first, displayAmount: null, displayResolution: 'unavailable',
    accounts: first.accounts.map(account => ({...account, displayAmount: null}))}]]) {
    const value = {...original, balances: {...original.balances, tokens}} as unknown as StockHoldingsSnapshot;
    const instance = buildApp({logger: false, accountHoldings: adapters({read: async () => value})});
    try {
      const response = await instance.inject({url: ACCOUNT_HOLDINGS_ROUTE,
        headers: {'x-trimmy-holdings-version': '2'}});
      assert.equal(response.statusCode, 200, response.body);
      const actual = response.json().holdings.balances.tokens;
      assert.equal(actual.length, tokens.length);
      if (actual.length) {
        assert.equal(actual[0].amountRaw, '123456789');
        assert.equal(actual[0].displayAmount, null);
        assert.equal(actual[0].displayResolution, 'unavailable');
      }
    } finally { await instance.close(); }
  }
});

test('v2 keeps total ownership while limiting trading availability to an initialized canonical account', async () => {
  for (const state of ['initialized', 'frozen'] as const) {
    const original = portfolioSnapshot();
    const first = original.balances.tokens![0]!;
    const stock = {...first, amountRaw: '100000000', displayAmount: '10',
      accountTopology: 'associated_with_ancillary', hasFrozenAccounts: state === 'frozen',
      associatedTokenAccount: {address: walletAddress, status: 'present'},
      // A forged availability claim from an adapter must never cross HTTP.
      availableToTradeRaw: '100000000',
      accounts: [
        {address: walletAddress, amountRaw: '60000000', state, associated: true, displayAmount: '6'},
        {address: otherWalletAddress, amountRaw: '40000000', state: 'initialized', associated: false, displayAmount: '4'},
      ].sort((a, b) => a.address.localeCompare(b.address))};
    const usdc = {...original.balances.usdc, amountRaw: '100000000',
      accountTopology: 'associated_with_ancillary', hasFrozenAccounts: state === 'frozen',
      associatedTokenAccount: {address: JUPITER_QUOTE_ASSETS.USDC.mint, status: 'present'},
      availableToTradeRaw: '100000000',
      accounts: [
        {address: JUPITER_QUOTE_ASSETS.USDC.mint, amountRaw: '60000000', state, associated: true},
        {address: JUPITER_QUOTE_ASSETS.AAPLx.mint, amountRaw: '40000000', state: 'initialized', associated: false},
      ].sort((a, b) => a.address.localeCompare(b.address))};
    const value = {...original, balances: {...original.balances, usdc, tokens: [stock]}} as unknown as StockHoldingsSnapshot;
    const instance = buildApp({logger: false, accountHoldings: adapters({read: async () => value})});
    try {
      const response = await instance.inject({url: ACCOUNT_HOLDINGS_ROUTE, headers: {'x-trimmy-holdings-version': '2'}});
      assert.equal(response.statusCode, 200, response.body);
      const balances = response.json().holdings.balances;
      assert.equal(balances.usdc.amountRaw, '100000000');
      assert.equal(balances.tokens[0].amountRaw, '100000000');
      assert.equal(balances.tokens[0].displayAmount, '10');
      const available = state === 'initialized' ? '60000000' : '0';
      assert.equal(balances.usdc.availableToTradeRaw, available);
      assert.equal(balances.tokens[0].availableToTradeRaw, available);
      const legacy = await instance.inject(ACCOUNT_HOLDINGS_ROUTE);
      assert.equal(legacy.statusCode, 200, legacy.body);
      assert.equal(legacy.json().holdings.balances.usdc.availableToTradeRaw, undefined);
    } finally { await instance.close(); }
  }
});

test('the minimum-slot header is bounded, passed to the authenticated reader and enforced on its projection', async () => {
  const slots:unknown[]=[];
  const instance=buildApp({logger:false,accountHoldings:adapters({read:async(_owner,_version,minSlot)=>{
    slots.push(minSlot);return portfolioSnapshot();
  }})});
  try {
    const fresh=await instance.inject({url:ACCOUNT_HOLDINGS_ROUTE,headers:{'x-trimmy-holdings-version':'2','x-trimmy-holdings-min-slot':'100'}});
    assert.equal(fresh.statusCode,200,fresh.body);assert.deepEqual(slots,[100]);
    const stale=await instance.inject({url:ACCOUNT_HOLDINGS_ROUTE,headers:{'x-trimmy-holdings-version':'2','x-trimmy-holdings-min-slot':'999'}});
    assert.equal(stale.statusCode,502,stale.body);
    for(const value of ['0','-1','1.2','01','1, 2','9007199254740992','Infinity','']){
      const response=await instance.inject({url:ACCOUNT_HOLDINGS_ROUTE,headers:{'x-trimmy-holdings-min-slot':value}});
      assert.equal(response.statusCode,400,value);assert.equal(response.json().error.code,'ACCOUNT_HOLDINGS_INVALID_REQUEST');
    }
    assert.deepEqual(slots,[100,999]);
  } finally {await instance.close();}
});
