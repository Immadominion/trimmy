import assert from 'node:assert/strict';
import { it } from 'node:test';
import { address, getAddressDecoder, getAddressEncoder, getProgramDerivedAddress } from '@solana/kit';
import type { Address } from '@solana/kit';
import { JUPITER_QUOTE_ASSETS } from '../src/jupiter-quote-reader.js';
import {STOCK_TRADING_ASSETS} from '../src/stock-trading-catalog.js';
import {
  admitServerVerifiedStockOwner,
  SolanaStockHoldingsReader,
  STOCK_HOLDINGS_MAINNET_GENESIS,
  STOCK_HOLDINGS_TOKEN_PROGRAMS,
  StockHoldingsError,
} from '../src/stock-holdings.js';
import type { ServerVerifiedStockOwner, StockHoldingsReaderOptions } from '../src/stock-holdings.js';

const rpcUrl = 'https://rpc.example.test/solana?server-key=not-returned';
const userId = '12345678-1234-4567-8123-123456789abc';
const otherUserId = '22345678-1234-4567-8123-123456789abc';
const ownerAddress = address('9fYLFVoVqwH37C3dyPi6cpeobfbQ2jtLpN5HgAYDDdkm');
const otherOwnerAddress = address('FbP8bwmje245N5k3GTrx7BcKcDwbJNbfvEaEbF8eewY1');
const ancillaryOne = getAddressDecoder().decode(new Uint8Array(32).fill(7));
const ancillaryTwo = getAddressDecoder().decode(new Uint8Array(32).fill(8));
const observedAt = Date.parse('2026-09-14T20:00:00.000Z');
const errorIs = (code: string) => (error: unknown) =>
  error instanceof StockHoldingsError && error.code === code;

function verifiedOwner(changes: Readonly<{authenticatedUserId?: string; address?: Address}> = {}) {
  return admitServerVerifiedStockOwner({
    authenticatedUserId: changes.authenticatedUserId ?? userId,
    address: changes.address ?? ownerAddress,
    verification: 'authenticated_privy_embedded_wallet',
  });
}

async function associated(owner: Address, mint: Address, tokenProgram: Address): Promise<Address> {
  const encoder = getAddressEncoder();
  return (await getProgramDerivedAddress({
    programAddress: address(STOCK_HOLDINGS_TOKEN_PROGRAMS.associated),
    seeds: [encoder.encode(owner), encoder.encode(tokenProgram), encoder.encode(mint)],
  }))[0];
}

interface TokenAccountOptions {
  readonly pubkey: Address;
  readonly mint: Address;
  readonly tokenOwner?: Address;
  readonly tokenProgram: Address;
  readonly parsedProgram: 'spl-token' | 'spl-token-2022';
  readonly decimals: number;
  readonly amount: string;
  readonly state?: string;
  readonly space?: number;
}

function tokenAccount(options: TokenAccountOptions): Record<string, unknown> {
  const space = options.space ?? 165;
  return {
    pubkey: options.pubkey,
    account: {
      executable: false,
      lamports: 2_039_280,
      owner: options.tokenProgram,
      rentEpoch: 1,
      space,
      data: {
        program: options.parsedProgram,
        space,
        parsed: {
          type: 'account',
          info: {
            mint: options.mint,
            owner: options.tokenOwner ?? ownerAddress,
            isNative: false,
            state: options.state ?? 'initialized',
            tokenAmount: {
              amount: options.amount,
              decimals: options.decimals,
              uiAmount: 999_999,
              uiAmountString: 'poison-display-value',
            },
          },
        },
      },
    },
  };
}

interface TransportOptions {
  readonly genesis?: unknown;
  readonly sol?: unknown;
  readonly usdc?: readonly Record<string, unknown>[];
  readonly aaplx?: readonly Record<string, unknown>[];
  readonly token2022?: readonly Record<string, unknown>[];
  readonly legacy?: readonly Record<string, unknown>[];
  readonly envelope?: (request: RpcRequest, result: unknown) => unknown;
}

interface RpcRequest {
  readonly jsonrpc: string;
  readonly id: number;
  readonly method: string;
  readonly params: readonly unknown[];
}

function transport(options: TransportOptions = {}) {
  const calls: RpcRequest[] = [];
  const fetch: typeof globalThis.fetch = async (url, init) => {
    assert.equal(String(url), rpcUrl);
    assert.equal(init?.method, 'POST');
    assert.equal(init?.redirect, 'error');
    assert.equal(new Headers(init?.headers).get('accept'), 'application/json');
    const request = JSON.parse(String(init?.body)) as RpcRequest;
    calls.push(request);
    let result: unknown;
    if (request.method === 'getGenesisHash') result = options.genesis ?? STOCK_HOLDINGS_MAINNET_GENESIS;
    else if (request.method === 'getBalance') result = {context: {slot: 101}, value: options.sol ?? 5_000_000};
    else if (request.method === 'getTokenAccountsByOwner') {
      const filter = request.params[1] as {mint?: string; programId?: string};
      const legacy = filter.mint === JUPITER_QUOTE_ASSETS.USDC.mint || filter.programId === STOCK_HOLDINGS_TOKEN_PROGRAMS.legacy;
      result = {context: {slot: legacy ? 102 : 103},
        value: filter.programId ? (legacy ? options.legacy ?? options.usdc ?? [] : options.token2022 ?? options.aaplx ?? [])
          : legacy ? options.usdc ?? [] : options.aaplx ?? []};
    } else throw new Error('Unexpected method in test transport.');
    const payload = options.envelope?.(request, result) ?? {jsonrpc: '2.0', id: request.id, result};
    return Response.json(payload);
  };
  return {fetch, calls};
}

function reader(fetch: typeof globalThis.fetch,
  changes: Readonly<Partial<Pick<StockHoldingsReaderOptions, 'timeoutMs' | 'now' | 'cacheTtlMs' |
    'rateLimitWindowMs' | 'perUserLimit' | 'globalLimit' | 'maxTrackedUsers' |
    'maxCachedAddresses' | 'maxConcurrentReads'>>> = {}) {
  return new SolanaStockHoldingsReader({rpcUrl, fetch, now: () => observedAt, ...changes});
}

it('returns exact raw mainnet holdings and explicitly aggregates canonical plus ancillary token accounts', async () => {
  const legacy = address(STOCK_HOLDINGS_TOKEN_PROGRAMS.legacy);
  const token2022 = address(STOCK_HOLDINGS_TOKEN_PROGRAMS.token2022);
  const usdcMint = address(JUPITER_QUOTE_ASSETS.USDC.mint);
  const aaplxMint = address(JUPITER_QUOTE_ASSETS.AAPLx.mint);
  const usdcAssociated = await associated(ownerAddress, usdcMint, legacy);
  const aaplxAssociated = await associated(ownerAddress, aaplxMint, token2022);
  const rpc = transport({
    sol: Number.MAX_SAFE_INTEGER,
    usdc: [tokenAccount({pubkey: usdcAssociated, mint: usdcMint, tokenProgram: legacy,
      parsedProgram: 'spl-token', decimals: 6, amount: '1234567'})],
    aaplx: [
      tokenAccount({pubkey: ancillaryOne, mint: aaplxMint, tokenProgram: token2022,
        parsedProgram: 'spl-token-2022', decimals: 8, amount: '7', space: 170}),
      tokenAccount({pubkey: aaplxAssociated, mint: aaplxMint, tokenProgram: token2022,
        parsedProgram: 'spl-token-2022', decimals: 8, amount: '9007199254740993', state: 'frozen', space: 170}),
    ],
  });
  const result = await reader(rpc.fetch).read(verifiedOwner());

  assert.equal(result.network, 'solana:mainnet-beta');
  assert.equal(result.genesisHash, STOCK_HOLDINGS_MAINNET_GENESIS);
  assert.equal(result.owner, ownerAddress);
  assert.equal(result.ownerBinding, 'trusted_server_capability');
  assert.equal(result.observedAt, '2026-09-14T20:00:00.000Z');
  assert.equal(result.balances.nativeSol.amountRaw, '9007199254740991');
  assert.equal(result.balances.usdc.amountRaw, '1234567');
  assert.equal(result.balances.usdc.accountTopology, 'associated_only');
  assert.equal(result.balances.usdc.associatedTokenAccount.status, 'present');
  assert.equal(result.balances.aaplx.amountRaw, '9007199254741000');
  assert.equal(result.balances.aaplx.accountTopology, 'associated_with_ancillary');
  assert.equal(result.balances.aaplx.hasFrozenAccounts, true);
  assert.equal(result.balances.aaplx.displayResolution, 'token_2022_scaled_ui_unresolved');
  assert.equal(result.balances.aaplx.displayAmount, null);
  assert.equal(result.balances.aaplx.shareAmount, null);
  assert.equal(result.balances.aaplx.eligibility, 'unverified');
  assert.equal(result.balances.aaplx.executionEnabled, false);
  assert.deepEqual(result.consistency.slots, {nativeSol: 101, usdc: 102, aaplx: 103});
  assert.equal(result.consistency.atomic, false);
  assert.equal(result.transactionBuilt, false);
  assert.equal(result.transactionSigned, false);
  assert.equal(result.transactionBroadcast, false);
  assert.ok(Object.isFrozen(result) && Object.isFrozen(result.balances.aaplx.accounts));
  assert.ok(!JSON.stringify(result).includes('poison-display-value'));

  assert.deepEqual(rpc.calls.map((call) => [call.id, call.method]), [
    [1, 'getGenesisHash'], [2, 'getBalance'], [3, 'getTokenAccountsByOwner'], [4, 'getTokenAccountsByOwner'],
  ]);
  assert.deepEqual(rpc.calls[1]?.params, [ownerAddress, {commitment: 'confirmed'}]);
  assert.deepEqual(rpc.calls[2]?.params, [ownerAddress, {mint: usdcMint},
    {encoding: 'jsonParsed', commitment: 'confirmed'}]);
  assert.deepEqual(rpc.calls[3]?.params, [ownerAddress, {mint: aaplxMint},
    {encoding: 'jsonParsed', commitment: 'confirmed'}]);
});

it('represents zero and ancillary-only holdings without inventing a canonical account', async () => {
  const legacy = address(STOCK_HOLDINGS_TOKEN_PROGRAMS.legacy);
  const usdcMint = address(JUPITER_QUOTE_ASSETS.USDC.mint);
  const rpc = transport({
    usdc: [tokenAccount({pubkey: ancillaryOne, mint: usdcMint, tokenProgram: legacy,
      parsedProgram: 'spl-token', decimals: 6, amount: '0'})],
  });
  const result = await reader(rpc.fetch).read(verifiedOwner());
  assert.equal(result.balances.usdc.amountRaw, '0');
  assert.equal(result.balances.usdc.accountTopology, 'ancillary_only');
  assert.equal(result.balances.usdc.associatedTokenAccount.status, 'absent');
  assert.equal(result.balances.aaplx.amountRaw, '0');
  assert.equal(result.balances.aaplx.accountTopology, 'none');
  assert.equal(result.balances.aaplx.associatedTokenAccount.status, 'absent');
});

it('requires an in-process server-verified capability and rejects serialized or forged owner input before RPC', async () => {
  let calls = 0;
  const api = reader(async () => { calls++; return Response.json({}); });
  const accepted = verifiedOwner();
  const serialized = JSON.parse(JSON.stringify(accepted)) as ServerVerifiedStockOwner;
  const forged = Object.freeze({...accepted}) as ServerVerifiedStockOwner;
  for (const value of [serialized, forged, null as unknown as ServerVerifiedStockOwner]) {
    await assert.rejects(api.read(value), errorIs('STOCK_HOLDINGS_OWNER_UNVERIFIED'));
  }
  assert.equal(calls, 0);
  for (const input of [
    {authenticatedUserId: 'request-body-id', address: ownerAddress, verification: 'authenticated_privy_embedded_wallet'},
    {authenticatedUserId: userId, address: 'bad-wallet', verification: 'authenticated_privy_embedded_wallet'},
    {authenticatedUserId: userId, address: ownerAddress, verification: 'self_asserted'},
    {authenticatedUserId: userId, address: ownerAddress,
      verification: 'authenticated_privy_embedded_wallet', wallet: 'extra'},
  ]) {
    assert.throws(() => admitServerVerifiedStockOwner(input as never), errorIs('STOCK_HOLDINGS_OWNER_INVALID'));
  }
});

it('checks mainnet genesis before any owner balance read', async () => {
  const rpc = transport({genesis: 'EtWTRABZaYq6iMfeYKouRu166VU2xqa1'});
  await assert.rejects(reader(rpc.fetch).read(verifiedOwner()), errorIs('STOCK_HOLDINGS_WRONG_NETWORK'));
  assert.deepEqual(rpc.calls.map((call) => call.method), ['getGenesisHash']);
});

it('rejects wrong JSON-RPC versions, IDs, errors and missing results', async () => {
  const envelopes = [
    (request: RpcRequest, result: unknown) => ({jsonrpc: '2.0', id: request.id + 1, result}),
    (request: RpcRequest, result: unknown) => ({jsonrpc: '1.0', id: request.id, result}),
    (request: RpcRequest) => ({jsonrpc: '2.0', id: request.id, error: {code: -1, message: 'private upstream'}}),
    (request: RpcRequest, result: unknown) => ({jsonrpc: '2.0', id: request.id, result, error: null}),
    (request: RpcRequest) => ({jsonrpc: '2.0', id: request.id}),
  ];
  for (const envelope of envelopes) {
    const rpc = transport({envelope});
    await assert.rejects(reader(rpc.fetch).read(verifiedOwner()), (error: unknown) =>
      errorIs('STOCK_HOLDINGS_RPC_RESPONSE_INVALID')(error) && error instanceof Error &&
      !error.message.includes('private upstream') && !error.message.includes('server-key'));
    assert.equal(rpc.calls.length, 1);
  }
});

it('validates token account program, parsed mint, owner, state, decimals, space and raw amount', async () => {
  const legacy = address(STOCK_HOLDINGS_TOKEN_PROGRAMS.legacy);
  const token2022 = address(STOCK_HOLDINGS_TOKEN_PROGRAMS.token2022);
  const usdcMint = address(JUPITER_QUOTE_ASSETS.USDC.mint);
  const base = tokenAccount({pubkey: ancillaryOne, mint: usdcMint, tokenProgram: legacy,
    parsedProgram: 'spl-token', decimals: 6, amount: '1'});
  const changes: Array<(value: Record<string, unknown>) => void> = [
    (value) => { (value['account'] as Record<string, unknown>)['owner'] = token2022; },
    (value) => { (value['account'] as Record<string, unknown>)['executable'] = true; },
    (value) => { parsedData(value)['program'] = 'spl-token-2022'; },
    (value) => { parsed(value)['type'] = 'mint'; },
    (value) => { info(value)['mint'] = JUPITER_QUOTE_ASSETS.AAPLx.mint; },
    (value) => { info(value)['owner'] = ancillaryTwo; },
    (value) => { info(value)['isNative'] = true; },
    (value) => { info(value)['state'] = 'uninitialized'; },
    (value) => { tokenAmount(value)['decimals'] = 8; },
    (value) => { parsedData(value)['space'] = 166; },
    (value) => { (value['account'] as Record<string, unknown>)['space'] = 166; },
    (value) => { tokenAmount(value)['amount'] = '01'; },
    (value) => { tokenAmount(value)['amount'] = '18446744073709551616'; },
  ];
  for (const change of changes) {
    const candidate = structuredClone(base);
    change(candidate);
    const rpc = transport({usdc: [candidate]});
    await assert.rejects(reader(rpc.fetch).read(verifiedOwner()), errorIs('STOCK_HOLDINGS_RPC_RESPONSE_INVALID'));
  }
});

it('rejects duplicate accounts and aggregate raw balances beyond u64', async () => {
  const legacy = address(STOCK_HOLDINGS_TOKEN_PROGRAMS.legacy);
  const usdcMint = address(JUPITER_QUOTE_ASSETS.USDC.mint);
  const max = tokenAccount({pubkey: ancillaryOne, mint: usdcMint, tokenProgram: legacy,
    parsedProgram: 'spl-token', decimals: 6, amount: '18446744073709551615'});
  for (const accounts of [
    [max, structuredClone(max)],
    [max, tokenAccount({pubkey: ancillaryTwo, mint: usdcMint, tokenProgram: legacy,
      parsedProgram: 'spl-token', decimals: 6, amount: '1'})],
  ]) {
    const rpc = transport({usdc: accounts});
    await assert.rejects(reader(rpc.fetch).read(verifiedOwner()), errorIs('STOCK_HOLDINGS_RPC_RESPONSE_INVALID'));
  }
});

it('rejects unsafe SOL numbers, invalid contexts and oversized account sets instead of rounding', async () => {
  const invalidResults: TransportOptions[] = [
    {sol: Number.MAX_SAFE_INTEGER + 1},
    {sol: -1},
    {sol: '1'},
    {envelope: (request, result) => ({jsonrpc: '2.0', id: request.id,
      result: request.method === 'getBalance' ? {context: {slot: -1}, value: 1} : result})},
    {usdc: Array.from({length: 129}, () => ({}))},
  ];
  for (const options of invalidResults) {
    const rpc = transport(options);
    await assert.rejects(reader(rpc.fetch).read(verifiedOwner()), errorIs('STOCK_HOLDINGS_RPC_RESPONSE_INVALID'));
  }
});

it('bounds fetch and body reads, and never retries an unavailable RPC', async () => {
  let calls = 0;
  const hangingFetch: typeof globalThis.fetch = async () => {
    calls++;
    return new Promise<Response>(() => undefined);
  };
  await assert.rejects(reader(hangingFetch, {timeoutMs: 10}).read(verifiedOwner()),
    errorIs('STOCK_HOLDINGS_RPC_TIMEOUT'));
  assert.equal(calls, 1);

  calls = 0;
  const stalledBody = new ReadableStream<Uint8Array>({
    pull: () => new Promise<void>(() => undefined),
    cancel: () => new Promise<void>(() => undefined),
  });
  await assert.rejects(reader(async () => {
    calls++;
    return new Response(stalledBody, {headers: {'content-type': 'application/json'}});
  }, {timeoutMs: 10}).read(verifiedOwner()), errorIs('STOCK_HOLDINGS_RPC_TIMEOUT'));
  assert.equal(calls, 1);

  calls = 0;
  await assert.rejects(reader(async () => {
    calls++;
    return Response.json({error: 'secret-provider-body'}, {status: 503});
  }).read(verifiedOwner()), (error: unknown) => errorIs('STOCK_HOLDINGS_RPC_UNAVAILABLE')(error) &&
    error instanceof Error && !error.message.includes('secret-provider-body'));
  assert.equal(calls, 1);
});

it('same-address holdings reads singleflight, cache, and refresh exactly at TTL expiry', async () => {
  const rpc = transport();
  let transportStarts = 0;
  let now = observedAt;
  let release: () => void = () => undefined;
  const gate = new Promise<void>(resolve => { release = resolve; });
  const delayedFetch: typeof globalThis.fetch = async (input, init) => {
    transportStarts += 1;
    if (transportStarts === 1) await gate;
    return rpc.fetch(input, init);
  };
  const api = reader(delayedFetch, {
    now: () => now,
    cacheTtlMs: 100,
    perUserLimit: 10,
    globalLimit: 10,
  });
  const first = api.read(verifiedOwner());
  const joined = api.read(verifiedOwner());
  assert.equal(transportStarts, 1);
  release();
  const [one, two] = await Promise.all([first, joined]);
  assert.strictEqual(one, two);
  assert.equal(rpc.calls.length, 4);

  now = observedAt + 99;
  assert.strictEqual(await api.read(verifiedOwner()), one);
  assert.equal(rpc.calls.length, 4);
  now = observedAt + 100;
  const refreshed = await api.read(verifiedOwner());
  assert.notStrictEqual(refreshed, one);
  assert.equal(rpc.calls.length, 8);
  assert.equal(refreshed.observedAt, new Date(now).toISOString());
});

it('failed holdings reads consume per-user budget before a safe rate-limit error', async () => {
  let calls = 0;
  const api = reader(async () => {
    calls += 1;
    throw new Error(`${rpcUrl} private RPC failure`);
  }, {
    cacheTtlMs: 1,
    rateLimitWindowMs: 1_000,
    perUserLimit: 2,
    globalLimit: 10,
  });
  await assert.rejects(api.read(verifiedOwner()), errorIs('STOCK_HOLDINGS_RPC_UNAVAILABLE'));
  await assert.rejects(api.read(verifiedOwner()), errorIs('STOCK_HOLDINGS_RPC_UNAVAILABLE'));
  await assert.rejects(api.read(verifiedOwner()), errorIs('STOCK_HOLDINGS_RATE_LIMITED'));
  assert.equal(calls, 2);
});

it('the global holdings budget protects RPC capacity across authenticated users', async () => {
  const rpc = transport();
  const api = reader(rpc.fetch, {perUserLimit: 10, globalLimit: 1});
  await api.read(verifiedOwner());
  await assert.rejects(api.read(verifiedOwner({
    authenticatedUserId: otherUserId,
    address: otherOwnerAddress,
  })), errorIs('STOCK_HOLDINGS_RATE_LIMITED'));
  assert.equal(rpc.calls.length, 4);
});

it('rejects oversized, mistyped and malformed JSON bodies without exposing their content', async () => {
  const responses = [
    () => new Response('{}', {headers: {'content-type': 'text/plain'}}),
    () => new Response('{"private":"provider-secret"', {headers: {'content-type': 'application/json'}}),
    () => new Response('{}', {headers: {'content-type': 'application/json', 'content-length': '262145'}}),
    () => new Response(new Uint8Array(262_145), {headers: {'content-type': 'application/json'}}),
  ];
  for (const create of responses) {
    let calls = 0;
    await assert.rejects(reader(async () => { calls++; return create(); }).read(verifiedOwner()),
      (error: unknown) => errorIs('STOCK_HOLDINGS_RPC_RESPONSE_INVALID')(error) && error instanceof Error &&
        !error.message.includes('provider-secret'));
    assert.equal(calls, 1);
  }
});

it('fails closed on invalid endpoint, timeout and clock configuration before network access', async () => {
  for (const options of [
    {rpcUrl: 'http://rpc.example.test'},
    {rpcUrl: 'https://user:password@rpc.example.test'},
    {rpcUrl: 'https://rpc.example.test/#fragment'},
    {rpcUrl: 'not-a-url'},
    {rpcUrl, timeoutMs: 0},
    {rpcUrl, timeoutMs: 8001},
    {rpcUrl, cacheTtlMs: 0},
    {rpcUrl, perUserLimit: 0},
    {rpcUrl, maxConcurrentReads: 0},
  ]) {
    assert.throws(() => new SolanaStockHoldingsReader(options),
      errorIs('STOCK_HOLDINGS_CONFIGURATION_INVALID'));
  }
  let calls = 0;
  const api = new SolanaStockHoldingsReader({rpcUrl, fetch: async () => {
    calls++;
    return Response.json({});
  }, now: () => Number.NaN});
  await assert.rejects(api.read(verifiedOwner()), errorIs('STOCK_HOLDINGS_CONFIGURATION_INVALID'));
  assert.equal(calls, 0);
});

function parsedData(value: Record<string, unknown>): Record<string, unknown> {
  return (value['account'] as Record<string, unknown>)['data'] as Record<string, unknown>;
}
function parsed(value: Record<string, unknown>): Record<string, unknown> {
  return parsedData(value)['parsed'] as Record<string, unknown>;
}
function info(value: Record<string, unknown>): Record<string, unknown> {
  return parsed(value)['info'] as Record<string, unknown>;
}
function tokenAmount(value: Record<string, unknown>): Record<string, unknown> {
  return info(value)['tokenAmount'] as Record<string, unknown>;
}

function stockAccount(assetId: string, pubkey: Address, amount: string, display: unknown) {
  const asset = STOCK_TRADING_ASSETS.find(item => item.assetId === assetId)!;
  const value = tokenAccount({pubkey, mint: address(asset.mint), tokenProgram: address(asset.tokenProgramAddress),
    parsedProgram: 'spl-token-2022', decimals: asset.decimals, amount, space: 170});
  tokenAmount(value)['uiAmountString'] = display;
  return value;
}

it('v2 aggregates multiple supported stocks, using exact mint-adjusted display strings and keeping cash separate', async () => {
  const apple = STOCK_TRADING_ASSETS.find(item => item.assetId === 'apple')!;
  const appleAta = await associated(ownerAddress, address(apple.mint), address(apple.tokenProgramAddress));
  const unknown = stockAccount('apple', getAddressDecoder().decode(new Uint8Array(32).fill(9)), '100', '1');
  info(unknown)['mint'] = ancillaryTwo;
  const rpc = transport({token2022: [
    stockAccount('apple', appleAta, '9007199254740993', '90366425.48085670000001'),
    stockAccount('apple', ancillaryOne, '7', '0.00000007'),
    stockAccount('netflix', ancillaryTwo, '123456789', '12.3456789'),
    stockAccount('tesla', getAddressDecoder().decode(new Uint8Array(32).fill(10)), '0', '0'),
    unknown,
  ]});
  const result = await reader(rpc.fetch).read(verifiedOwner(), 2);
  assert.deepEqual(result.balances.tokens?.map(token => token.assetId), ['apple', 'netflix']);
  const [aapl, netflix] = result.balances.tokens!;
  assert.equal(aapl?.amountRaw, '9007199254741000');
  assert.equal(aapl?.displayAmount, '90366425.48085677');
  assert.equal(aapl?.displayResolution, 'rpc_ui_amount');
  assert.equal(aapl?.displayUnits, 'token_units');
  assert.equal(aapl?.accountTopology, 'associated_with_ancillary');
  assert.equal(netflix?.amountRaw, '123456789');
  assert.equal(netflix?.displayAmount, '12.3456789');
  assert.equal(result.balances.usdc.amountRaw, '0');
  assert.equal(result.balances.aaplx.amountRaw, aapl?.amountRaw);
  assert.equal(result.balances.aaplx.displayAmount, null);
  assert.deepEqual(rpc.calls.slice(2).map(call => call.params[1]), [
    {programId: STOCK_HOLDINGS_TOKEN_PROGRAMS.legacy}, {programId: STOCK_HOLDINGS_TOKEN_PROGRAMS.token2022},
  ]);
});

it('v2 keeps verified raw holdings when optional UI amounts are unavailable instead of inventing zero', async () => {
  for (const display of [undefined, null, 'NaN', '-1', '1e4', 'secret-provider-text']) {
    const rpc = transport({token2022: [stockAccount('netflix', ancillaryOne, '123456789', display)]});
    const result = await reader(rpc.fetch).read(verifiedOwner(), 2);
    assert.equal(result.balances.tokens?.[0]?.amountRaw, '123456789');
    assert.equal(result.balances.tokens?.[0]?.displayAmount, null);
    assert.equal(result.balances.tokens?.[0]?.displayResolution, 'unavailable');
    assert.ok(!JSON.stringify(result).includes('secret-provider-text'));
  }
});

it('v2 rejects duplicate accounts, incorrect owner/program and false catalog decimals', async () => {
  const base = stockAccount('netflix', ancillaryOne, '123', '0.0000123');
  for (const change of [
    (value: Record<string, unknown>) => { info(value)['owner'] = otherOwnerAddress; },
    (value: Record<string, unknown>) => { tokenAmount(value)['decimals'] = 6; },
    (value: Record<string, unknown>) => { (value['account'] as Record<string, unknown>)['owner'] = STOCK_HOLDINGS_TOKEN_PROGRAMS.legacy; },
  ]) {
    const candidate = structuredClone(base);
    change(candidate);
    await assert.rejects(reader(transport({token2022: [candidate]}).fetch).read(verifiedOwner(), 2),
      errorIs('STOCK_HOLDINGS_RPC_RESPONSE_INVALID'));
  }
  await assert.rejects(reader(transport({token2022: [base, structuredClone(base)]}).fetch).read(verifiedOwner(), 2),
    errorIs('STOCK_HOLDINGS_RPC_RESPONSE_INVALID'));
});

it('v1 and v2 caches cannot substitute different response coverage', async () => {
  const rpc = transport({token2022: [stockAccount('netflix', ancillaryOne, '100000000', '10')]});
  const api = reader(rpc.fetch);
  const legacy = await api.read(verifiedOwner());
  const portfolio = await api.read(verifiedOwner(), 2);
  assert.equal(legacy.balances.tokens, undefined);
  assert.equal(portfolio.balances.tokens?.[0]?.assetId, 'netflix');
  assert.equal(rpc.calls.length, 8);
  assert.equal(await api.read(verifiedOwner()), legacy);
  assert.equal(await api.read(verifiedOwner(), 2), portfolio);
  assert.equal(rpc.calls.length, 8);
});

it('a settled-slot read bypasses an older snapshot and asks every balance RPC for that minimum slot', async () => {
  const stub = transport({envelope: (request, result) => {
    const config = request.params.at(-1) as {minContextSlot?: number}|undefined;
    if (config?.minContextSlot !== undefined && typeof result === 'object' && result !== null) {
      return {jsonrpc:'2.0',id:request.id,result:{...result,context:{slot:config.minContextSlot}}};
    }
    return {jsonrpc:'2.0',id:request.id,result};
  }});
  const service = reader(stub.fetch);
  const before = await service.read(verifiedOwner(),2);
  assert.equal(before.balances.nativeSol.observedSlot,101);
  const after = await service.read(verifiedOwner(),2,200);
  assert.equal(after.balances.nativeSol.observedSlot,200);
  assert.equal(after.balances.usdc.observedSlot,200);
  assert.equal(after.balances.aaplx.observedSlot,200);
  const slotCalls = stub.calls.filter(call => (call.params.at(-1) as {minContextSlot?:number}|undefined)?.minContextSlot===200);
  assert.deepEqual(slotCalls.map(call=>call.method).sort(),['getBalance','getTokenAccountsByOwner','getTokenAccountsByOwner']);
  assert.equal(await service.read(verifiedOwner(),2,200),after);
  assert.equal(stub.calls.length,8,'same post-confirmation bound still benefits from the cache');
});

it('a provider cannot satisfy a settled-slot read using an older balance, and fresh reads retain budgets', async () => {
  for (const version of [1,2] as const) {
    const stub=transport(),service=reader(stub.fetch);
    await assert.rejects(service.read(verifiedOwner(),version,104),errorIs('STOCK_HOLDINGS_RPC_RESPONSE_INVALID'));
  }
  const stub=transport(),service=reader(stub.fetch,{perUserLimit:1});
  await service.read(verifiedOwner(),2);
  await assert.rejects(service.read(verifiedOwner(),2,100),errorIs('STOCK_HOLDINGS_RATE_LIMITED'));
  assert.equal(stub.calls.length,4);
});

it('a settled-slot read never joins the pre-confirmation in-flight snapshot', async () => {
  let release!:()=>void;
  const blocked = new Promise<void>(resolve=>{release=resolve;});
  const stub=transport({envelope:(request,result)=>{
    const minimum=(request.params.at(-1) as {minContextSlot?:number}|undefined)?.minContextSlot;
    return {jsonrpc:'2.0',id:request.id,result:minimum!==undefined && typeof result==='object' && result!==null
      ? {...result,context:{slot:minimum}}:result};
  }});
  let started!:()=>void;const didStart=new Promise<void>(resolve=>{started=resolve;});
  const service=reader(async(url,init)=>{
    const request=JSON.parse(String(init?.body));
    if(request.method==='getBalance' && request.params[1].minContextSlot===undefined){started();await blocked;}
    return stub.fetch(url,init);
  });
  const older=service.read(verifiedOwner(),2);await didStart;
  const fresh=await service.read(verifiedOwner(),2,200);
  assert.equal(fresh.balances.nativeSol.observedSlot,200);
  release();assert.equal((await older).balances.nativeSol.observedSlot,101);
  assert.equal((await service.read(verifiedOwner(),2,200)).balances.nativeSol.observedSlot,200);
});

it('invalid minimum slots never consume an upstream request', async () => {
  const stub=transport(),service=reader(stub.fetch);
  for(const slot of [0,-1,1.5,Infinity,Number.MAX_SAFE_INTEGER+1]) {
    await assert.rejects(service.read(verifiedOwner(),2,slot),errorIs('STOCK_HOLDINGS_CONFIGURATION_INVALID'));
  }
  assert.equal(stub.calls.length,0);
});
