import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {it} from 'node:test';
import {
  address,
  getAddressDecoder,
  getAddressEncoder,
  getCompiledTransactionMessageEncoder,
  getTransactionEncoder,
} from '@solana/kit';
import type {Address, CompiledTransactionMessage, TransactionMessageBytes} from '@solana/kit';
import {
  SolanaMainnetLookupTableResolver,
  STOCK_LOOKUP_MAINNET_GENESIS,
  STOCK_LOOKUP_TABLE_PROGRAM,
  StockLookupResolutionError,
} from '../src/stock-order-lookup-resolver.js';
import {STOCK_DRAFT_MAINNET_GENESIS} from '../src/stock-order-draft.js';
import {STOCK_HOLDINGS_MAINNET_GENESIS} from '../src/stock-holdings.js';
import {inspectUnsignedV0TransactionStructure} from '../src/stock-order-transaction-inspector.js';
import type {UnsignedV0TransactionStructure} from '../src/stock-order-transaction-inspector.js';

const rpcUrl = 'https://rpc.example.test/mainnet?server-key=not-returned';
const wallet = getAddressDecoder().decode(Buffer.from(
  'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a', 'hex'));
const program = address('11111111111111111111111111111111');
const lifetime = getAddressDecoder().decode(new Uint8Array(32).fill(9));
const lookupOne = getAddressDecoder().decode(new Uint8Array(32).fill(7));
const lookupTwo = getAddressDecoder().decode(new Uint8Array(32).fill(8));
const accountA = getAddressDecoder().decode(new Uint8Array(32).fill(11));
const accountB = getAddressDecoder().decode(new Uint8Array(32).fill(12));
const accountC = getAddressDecoder().decode(new Uint8Array(32).fill(13));
const accountD = getAddressDecoder().decode(new Uint8Array(32).fill(14));
const accountE = getAddressDecoder().decode(new Uint8Array(32).fill(15));
const observedAt = Date.parse('2026-09-14T21:00:00.000Z');
const errorIs = (code: string) => (error: unknown) =>
  error instanceof StockLookupResolutionError && error.code === code &&
  !error.message.includes('server-key') && !error.message.includes('private-upstream');

function structure(withLookups = true, repeatedReferences = 1): UnsignedV0TransactionStructure {
  const message: CompiledTransactionMessage & {lifetimeToken: string} = {
    version: 0,
    header: {numSignerAccounts: 1, numReadonlySignerAccounts: 0, numReadonlyNonSignerAccounts: 1},
    staticAccounts: [wallet, program],
    lifetimeToken: lifetime,
    instructions: withLookups ? [{programAddressIndex: 5, accountIndices: [0, 2, 3, 4],
      data: new Uint8Array([1, 2, 3])}] : [{programAddressIndex: 1, accountIndices: new Array<number>(repeatedReferences).fill(0), data: new Uint8Array()}],
    addressTableLookups: withLookups ? [
      {lookupTableAddress: lookupOne, writableIndexes: [0], readonlyIndexes: [2]},
      {lookupTableAddress: lookupTwo, writableIndexes: [1], readonlyIndexes: [0]},
    ] : [],
  } as CompiledTransactionMessage & {lifetimeToken: string};
  const messageBytes = getCompiledTransactionMessageEncoder().encode(message) as TransactionMessageBytes;
  const wire = getTransactionEncoder().encode({messageBytes, signatures: {[wallet]: null}});
  return inspectUnsignedV0TransactionStructure(Uint8Array.from(wire), wallet);
}

interface TableDataOptions {
  readonly deactivationSlot?: bigint;
  readonly lastExtendedSlot?: bigint;
  readonly lastExtendedSlotStartIndex?: number;
  readonly discriminator?: number;
  readonly padding?: number;
  readonly authority?: Address;
}

function tableData(addresses: readonly Address[], options: TableDataOptions = {}): Buffer {
  const data = Buffer.alloc(56 + addresses.length * 32);
  data.writeUInt32LE(options.discriminator ?? 1, 0);
  data.writeBigUInt64LE(options.deactivationSlot ?? ((1n << 64n) - 1n), 4);
  data.writeBigUInt64LE(options.lastExtendedSlot ?? 90n, 12);
  data[20] = options.lastExtendedSlotStartIndex ?? 0;
  if (options.authority) {
    data[21] = 1;
    Buffer.from(getAddressEncoder().encode(options.authority)).copy(data, 22);
  }
  data.writeUInt16LE(options.padding ?? 0, 54);
  addresses.forEach((item, index) => Buffer.from(getAddressEncoder().encode(item)).copy(data, 56 + index * 32));
  return data;
}

interface TableAccountOptions extends TableDataOptions {
  readonly owner?: string;
  readonly executable?: boolean;
  readonly lamports?: number;
  readonly rentEpoch?: number;
  readonly space?: number;
  readonly encoding?: string;
  readonly dataOverride?: string;
  readonly extra?: boolean;
}

function tableAccount(addresses: readonly Address[], options: TableAccountOptions = {}): Record<string, unknown> {
  const data = tableData(addresses, options);
  return {
    data: [options.dataOverride ?? data.toString('base64'), options.encoding ?? 'base64'],
    executable: options.executable ?? false,
    lamports: options.lamports ?? 1_000_000,
    owner: options.owner ?? STOCK_LOOKUP_TABLE_PROGRAM,
    rentEpoch: options.rentEpoch ?? 0,
    space: options.space ?? data.byteLength,
    ...(options.extra ? {privateProviderField: 'private-upstream'} : {}),
  };
}

interface RpcRequest {
  readonly jsonrpc: string;
  readonly id: number;
  readonly method: string;
  readonly params?: readonly unknown[];
}
interface TransportOptions {
  readonly genesis?: unknown;
  readonly firstSlot?: number;
  readonly secondSlot?: number;
  readonly firstTables?: readonly unknown[];
  readonly secondTables?: readonly unknown[];
  readonly envelope?: (request: RpcRequest, result: unknown, call: number) => unknown;
  readonly response?: (payload: unknown, request: RpcRequest, call: number) => Response;
}

function defaultTables(): readonly Record<string, unknown>[] {
  return [tableAccount([accountA, accountB, accountC]), tableAccount([accountD, accountE])];
}

function transport(options: TransportOptions = {}) {
  const calls: RpcRequest[] = [];
  let tableReads = 0;
  const fetch: typeof globalThis.fetch = async (input, init) => {
    assert.equal(String(input), rpcUrl);
    assert.equal(init?.method, 'POST');
    assert.equal(init?.redirect, 'error');
    assert.equal(new Headers(init?.headers).get('accept'), 'application/json');
    const request = JSON.parse(String(init?.body)) as RpcRequest;
    calls.push(request);
    let result: unknown;
    if (request.method === 'getGenesisHash') {
      result = Object.hasOwn(options, 'genesis') ? options.genesis : STOCK_LOOKUP_MAINNET_GENESIS;
    }
    else if (request.method === 'getMultipleAccounts') {
      tableReads += 1;
      result = {context: {slot: tableReads === 1 ? options.firstSlot ?? 100 : options.secondSlot ?? 101,
        apiVersion: '3.1.8'}, value: tableReads === 1 ? options.firstTables ?? defaultTables() :
        options.secondTables ?? options.firstTables ?? defaultTables()};
    } else throw new Error('Unexpected write or generic RPC method.');
    const payload = options.envelope?.(request, result, calls.length) ??
      {jsonrpc: '2.0', id: request.id, result};
    return options.response?.(payload, request, calls.length) ?? Response.json(payload);
  };
  return {fetch, calls};
}

it('shares the exact full mainnet genesis with draft admission and holdings reads', () => {
  assert.equal(STOCK_LOOKUP_MAINNET_GENESIS, STOCK_DRAFT_MAINNET_GENESIS);
  assert.equal(STOCK_LOOKUP_MAINNET_GENESIS, STOCK_HOLDINGS_MAINNET_GENESIS);
  assert.notEqual(STOCK_LOOKUP_MAINNET_GENESIS, '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp');
});

function resolver(fetch: typeof globalThis.fetch, changes: Readonly<{
  now?: () => number;
  timeoutMs?: number;
  maxConcurrentResolutions?: number;
}> = {}): SolanaMainnetLookupTableResolver {
  return new SolanaMainnetLookupTableResolver({rpcUrl, fetch, now: () => observedAt, ...changes});
}

it('resolves the exact v0 account-index order from two stable finalized mainnet observations', async () => {
  const rpc = transport();
  const report = structure();
  const result = await resolver(rpc.fetch).resolve(report);

  assert.deepEqual(rpc.calls.map(call => [call.id, call.method]), [
    [1, 'getGenesisHash'], [2, 'getMultipleAccounts'], [3, 'getMultipleAccounts'],
  ]);
  assert.deepEqual(Object.keys(rpc.calls[0] ?? {}), ['jsonrpc', 'id', 'method']);
  assert.deepEqual(rpc.calls[1]?.params, [[lookupOne, lookupTwo], {encoding: 'base64', commitment: 'finalized'}]);
  assert.deepEqual(rpc.calls[2]?.params, [[lookupOne, lookupTwo],
    {encoding: 'base64', commitment: 'finalized', minContextSlot: 100}]);
  assert.equal(result.network, 'solana:mainnet-beta');
  assert.equal(result.genesisHash, STOCK_LOOKUP_MAINNET_GENESIS);
  assert.equal(result.commitment, 'finalized');
  assert.equal(result.transactionHash, report.transactionHash);
  assert.equal(result.transactionMessageHash, report.transactionMessageHash);
  assert.equal(result.firstObservationSlot, '100');
  assert.equal(result.secondObservationSlot, '101');
  assert.deepEqual(result.accountIndexMap.map(item => [item.accountIndex, item.address, item.writable, item.source]), [
    [0, wallet, true, 'static'],
    [1, program, false, 'static'],
    [2, accountA, true, 'lookup_table'],
    [3, accountE, true, 'lookup_table'],
    [4, accountC, false, 'lookup_table'],
    [5, accountD, false, 'lookup_table'],
  ]);
  assert.deepEqual(result.lookupTables.map(item => [item.lookupTableAddress, item.addressCount,
    item.referencedAddressCount, item.authorityStatus]), [
    [lookupOne, 3, 2, 'frozen'], [lookupTwo, 2, 2, 'frozen'],
  ]);
  assert.match(result.lookupTables[0]?.accountDataSha256 ?? '', /^[0-9a-f]{64}$/);
  assert.match(result.lookupTables[0]?.accountObservationSha256 ?? '', /^[0-9a-f]{64}$/);
  assert.deepEqual(result.provenance.rpcMethods,
    ['getGenesisHash', 'getMultipleAccounts', 'getMultipleAccounts']);
  assert.deepEqual(result.provenance.tableAddressesRequested, [lookupOne, lookupTwo]);
  assert.equal(result.provenance.tableReadCount, 2);
  assert.equal(result.provenance.rpcApiVersion, '3.1.8');
  assert.equal(result.provenance.retries, 0);
  assert.equal(result.provenance.cacheUsed, false);
  assert.equal(result.assessment.lookupTableAccounts, 'verified_stable_finalized');
  assert.equal(result.assessment.lookupTableFreshness, 'point_in_time_only');
  assert.equal(result.assessment.revalidationRequired, true);
  assert.equal(result.assessment.accountIndexResolution, 'complete');
  assert.equal(result.assessment.recentBlockhash, 'unverified');
  assert.equal(result.assessment.programOwnership, 'unverified');
  assert.equal(result.assessment.instructionSemantics, 'unverified');
  assert.equal(result.assessment.accountState, 'unverified');
  assert.equal(result.assessment.transactionTerms, 'unverified');
  assert.equal(result.assessment.simulation, 'not_run');
  assert.equal(result.assessment.approvable, false);
  assert.equal(result.assessment.readyForSimulation, false);
  assert.equal(result.assessment.signingEnabled, false);
  assert.equal(result.assessment.broadcastEnabled, false);
  assert.equal(result.assessment.financialOperationsEnabled, false);
  assert.ok(Object.isFrozen(result) && Object.isFrozen(result.accountIndexMap) &&
    result.accountIndexMap.every(Object.isFrozen) && Object.isFrozen(result.lookupTables) &&
    result.lookupTables.every(Object.isFrozen) && Object.isFrozen(result.provenance) &&
    Object.isFrozen(result.provenance.tableAddressesRequested) && Object.isFrozen(result.assessment));
  for (const raw of defaultTables().map(item => ((item['data'] as string[])[0] ?? ''))) {
    assert.ok(!JSON.stringify(result).includes(raw));
  }
});

it('binds an all-static report to mainnet without making an unnecessary table request', async () => {
  const rpc = transport();
  const result = await resolver(rpc.fetch).resolve(structure(false));
  assert.deepEqual(rpc.calls.map(call => call.method), ['getGenesisHash']);
  assert.deepEqual(result.accountIndexMap.map(item => item.address), [wallet, program]);
  assert.deepEqual(result.lookupTables, []);
  assert.equal(result.firstObservationSlot, null);
  assert.equal(result.secondObservationSlot, null);
  assert.deepEqual(result.provenance.rpcMethods, ['getGenesisHash']);
  assert.equal(result.provenance.tableReadCount, 0);
  assert.equal(result.assessment.lookupTableAccounts, 'not_applicable');
  assert.equal(result.assessment.approvable, false);
});

it('requires the exact full mainnet genesis before reading any lookup-table account', async () => {
  for (const genesis of [
    '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp',
    'EtWTRABZaYq6iMfeYKouRu166VU2xqa1',
    '',
    7,
    null,
  ]) {
    const rpc = transport({genesis});
    await assert.rejects(resolver(rpc.fetch).resolve(structure()),
      errorIs(typeof genesis === 'string' ? 'LOOKUP_WRONG_NETWORK' : 'LOOKUP_RPC_RESPONSE_INVALID'));
    assert.deepEqual(rpc.calls.map(call => call.method), ['getGenesisHash']);
  }
});

it('strictly binds JSON-RPC version, ID, result-only envelopes and response identity', async () => {
  const cases: readonly [TransportOptions, string][] = [
    [{envelope: (request, result) => ({jsonrpc: '2.0', id: request.id + 1, result})}, 'LOOKUP_RPC_RESPONSE_INVALID'],
    [{envelope: (request, result) => ({jsonrpc: '1.0', id: request.id, result})}, 'LOOKUP_RPC_RESPONSE_INVALID'],
    [{envelope: request => ({jsonrpc: '2.0', id: request.id, error: {message: 'private-upstream'}})},
      'LOOKUP_RPC_RESPONSE_INVALID'],
    [{envelope: (request, result) => ({jsonrpc: '2.0', id: request.id, result, extra: true})},
      'LOOKUP_RPC_RESPONSE_INVALID'],
    [{response: payload => new Response(JSON.stringify(payload), {status: 503,
      headers: {'content-type': 'application/json'}})}, 'LOOKUP_RPC_UNAVAILABLE'],
    [{response: payload => new Response(JSON.stringify(payload), {headers: {'content-type': 'text/plain'}})},
      'LOOKUP_RPC_RESPONSE_INVALID'],
    [{response: payload => {
      const response = Response.json(payload);
      Object.defineProperty(response, 'redirected', {value: true});
      return response;
    }}, 'LOOKUP_RPC_RESPONSE_INVALID'],
    [{response: payload => {
      const response = Response.json(payload);
      Object.defineProperty(response, 'url', {value: 'https://other.example.test/mainnet'});
      return response;
    }}, 'LOOKUP_RPC_RESPONSE_INVALID'],
    [{response: payload => new Response(JSON.stringify(payload), {headers: {
      'content-type': 'application/json', 'content-length': '262145'}})}, 'LOOKUP_RPC_RESPONSE_INVALID'],
  ];
  for (const [options, code] of cases) {
    const rpc = transport(options);
    await assert.rejects(resolver(rpc.fetch).resolve(structure()), errorIs(code));
    assert.equal(rpc.calls.length, 1);
  }
});

it('rejects missing, incorrectly owned, executable and malformed lookup-table accounts', async () => {
  const malformed = tableData([accountA]);
  malformed[21] = 2; // Invalid fixed-option discriminator.
  const cases: readonly [unknown, string][] = [
    [null, 'LOOKUP_TABLE_MISSING'],
    [tableAccount([accountA], {owner: program}), 'LOOKUP_TABLE_INVALID'],
    [tableAccount([accountA], {executable: true}), 'LOOKUP_TABLE_INVALID'],
    [tableAccount([accountA], {lamports: 0}), 'LOOKUP_RPC_RESPONSE_INVALID'],
    [tableAccount([accountA], {encoding: 'base58'}), 'LOOKUP_TABLE_INVALID'],
    [tableAccount([accountA], {dataOverride: '!!!!'}), 'LOOKUP_TABLE_INVALID'],
    [tableAccount([accountA], {space: 56}), 'LOOKUP_TABLE_INVALID'],
    [tableAccount([accountA], {discriminator: 0}), 'LOOKUP_TABLE_INVALID'],
    [tableAccount([accountA], {padding: 1}), 'LOOKUP_TABLE_INVALID'],
    [tableAccount([accountA], {dataOverride: malformed.toString('base64')}), 'LOOKUP_TABLE_INVALID'],
    [tableAccount([accountA], {extra: true}), 'LOOKUP_RPC_RESPONSE_INVALID'],
  ];
  for (const [bad, code] of cases) {
    const rpc = transport({firstTables: [bad, defaultTables()[1]]});
    await assert.rejects(resolver(rpc.fetch).resolve(structure()), errorIs(code));
    assert.deepEqual(rpc.calls.map(call => call.method), ['getGenesisHash', 'getMultipleAccounts']);
  }
});

it('rejects deactivated, just-extended, oversized and out-of-range tables', async () => {
  const oversizedAddresses = Array.from({length: 257}, (_, index) =>
    getAddressDecoder().decode(new Uint8Array(32).fill((index % 250) + 1)));
  const cases: readonly [Record<string, unknown>, string, number][] = [
    [tableAccount([accountA, accountB, accountC], {deactivationSlot: 99n}),
      'LOOKUP_TABLE_DEACTIVATED', 2],
    [tableAccount([accountA, accountB, accountC], {lastExtendedSlot: 100n}), 'LOOKUP_TABLE_INVALID', 2],
    [tableAccount(oversizedAddresses), 'LOOKUP_TABLE_INVALID', 2],
    [tableAccount([accountA, accountB]), 'LOOKUP_INDEX_OUT_OF_RANGE', 3],
  ];
  for (const [bad, code, expectedCalls] of cases) {
    const rpc = transport({firstTables: [bad, defaultTables()[1]], secondTables: [bad, defaultTables()[1]]});
    await assert.rejects(resolver(rpc.fetch).resolve(structure()), errorIs(code));
    assert.equal(rpc.calls.length, expectedCalls);
  }
});

it('rejects any changed account observation or finalized-slot regression', async () => {
  const changedData = tableAccount([accountA, accountB, accountD]);
  for (const changes of [
    {secondTables: [changedData, defaultTables()[1]]},
    {firstSlot: 101, secondSlot: 100},
  ]) {
    const rpc = transport(changes);
    await assert.rejects(resolver(rpc.fetch).resolve(structure()), errorIs('LOOKUP_OBSERVATION_CHANGED'));
    assert.equal(rpc.calls.length, 3);
  }

  let tableRead = 0;
  const changingVersion: typeof globalThis.fetch = async (_input, init) => {
    const request = JSON.parse(String(init?.body)) as RpcRequest;
    if (request.method === 'getGenesisHash') {
      return Response.json({jsonrpc: '2.0', id: request.id, result: STOCK_LOOKUP_MAINNET_GENESIS});
    }
    tableRead += 1;
    return Response.json({jsonrpc: '2.0', id: request.id, result: {
      context: {slot: 100 + tableRead, apiVersion: tableRead === 1 ? '3.1.8' : '3.1.9'},
      value: defaultTables(),
    }});
  };
  await assert.rejects(resolver(changingVersion).resolve(structure()),
    errorIs('LOOKUP_OBSERVATION_CHANGED'));
  assert.equal(tableRead, 2);

  const lossyNumericMetadata = transport({secondTables: [
    {...defaultTables()[0], lamports: 1_000_001, rentEpoch: 18_446_744_073_709_552_000},
    {...defaultTables()[1], lamports: 1_000_002, rentEpoch: 18_446_744_073_709_552_000},
  ]});
  const resolved = await resolver(lossyNumericMetadata.fetch).resolve(structure());
  assert.equal(resolved.provenance.observationsStable, true);
  assert.equal(lossyNumericMetadata.calls.length, 3);
});

it('rejects resolved address collisions across tables and with static accounts', async () => {
  for (const tables of [
    [tableAccount([accountA, accountB, accountC]), tableAccount([accountD, accountA])],
    [tableAccount([wallet, accountB, accountC]), tableAccount([accountD, accountE])],
  ]) {
    const rpc = transport({firstTables: tables, secondTables: tables});
    await assert.rejects(resolver(rpc.fetch).resolve(structure()), errorIs('LOOKUP_ACCOUNT_DUPLICATED'));
    assert.equal(rpc.calls.length, 3);
  }
});

it('rejects forged structural claims and accessors before making any RPC call', async () => {
  const valid = structure();
  const variants: UnsignedV0TransactionStructure[] = [];
  const wrongCount = structuredClone(valid) as unknown as {accountIndexSpace: {total: number}};
  wrongCount.accountIndexSpace.total += 1;
  variants.push(wrongCount as unknown as UnsignedV0TransactionStructure);
  const ready = structuredClone(valid) as unknown as {assessment: {approvable: boolean}};
  ready.assessment.approvable = true;
  variants.push(ready as unknown as UnsignedV0TransactionStructure);
  const wrongProgram = structuredClone(valid) as unknown as {instructions: {program: {lookupIndex: number}}[]};
  if (wrongProgram.instructions[0]) wrongProgram.instructions[0].program.lookupIndex = 1;
  variants.push(wrongProgram as unknown as UnsignedV0TransactionStructure);
  const duplicateTable = structuredClone(valid) as unknown as
    {addressTableLookups: {lookupTableAddress: string}[]};
  if (duplicateTable.addressTableLookups[1] && duplicateTable.addressTableLookups[0]) {
    duplicateTable.addressTableLookups[1].lookupTableAddress =
      duplicateTable.addressTableLookups[0].lookupTableAddress;
  }
  variants.push(duplicateTable as unknown as UnsignedV0TransactionStructure);
  let getterReads = 0;
  const accessor = {...valid};
  Object.defineProperty(accessor, 'transactionHash', {enumerable: true, get() { getterReads += 1; return '0'.repeat(64); }});
  variants.push(accessor);
  const nestedAccessor = structuredClone(valid) as unknown as
    {addressTableLookups: {writableIndexes: number[]}[]};
  const writableIndexes = nestedAccessor.addressTableLookups[0]?.writableIndexes;
  assert.ok(writableIndexes);
  Object.defineProperty(writableIndexes, '0', {configurable: true, enumerable: true,
    get() { getterReads += 1; return 0; }});
  variants.push(nestedAccessor as unknown as UnsignedV0TransactionStructure);

  for (const candidate of variants) {
    let calls = 0;
    await assert.rejects(resolver(async () => { calls += 1; return Response.json({}); }).resolve(candidate),
      errorIs('LOOKUP_STRUCTURE_INVALID'));
    assert.equal(calls, 0);
  }
  assert.equal(getterReads, 0);
});

it('uses only the validated structure snapshot after asynchronous RPC work begins', async () => {
  const candidate = structuredClone(structure()) as UnsignedV0TransactionStructure;
  const rpc = transport();
  let release: () => void = () => undefined;
  const gate = new Promise<void>(resolve => { release = resolve; });
  let starts = 0;
  const delayed: typeof globalThis.fetch = async (input, init) => {
    starts += 1;
    if (starts === 1) await gate;
    return rpc.fetch(input, init);
  };
  const pending = resolver(delayed).resolve(candidate);
  assert.equal(starts, 1);
  let lateReads = 0;
  Object.defineProperty(candidate, 'accountIndexSpace', {configurable: true, enumerable: true,
    get() { lateReads += 1; throw new Error('late untrusted getter'); }});
  release();
  const result = await pending;
  assert.equal(result.accountIndexMap.length, 6);
  assert.equal(lateReads, 0);
  assert.equal(starts, 3);
});

it('caps lookup-table count before RPC even when the transaction wire remains bounded', async () => {
  const tableAddresses = Array.from({length: 17}, (_, index) =>
    getAddressDecoder().decode(new Uint8Array(32).fill(index + 30)));
  const message: CompiledTransactionMessage & {lifetimeToken: string} = {
    version: 0,
    header: {numSignerAccounts: 1, numReadonlySignerAccounts: 0, numReadonlyNonSignerAccounts: 1},
    staticAccounts: [wallet, program],
    lifetimeToken: lifetime,
    instructions: [{programAddressIndex: 1, accountIndices: [0], data: new Uint8Array()}],
    addressTableLookups: tableAddresses.map(lookupTableAddress =>
      ({lookupTableAddress, writableIndexes: [0], readonlyIndexes: []})),
  } as CompiledTransactionMessage & {lifetimeToken: string};
  const messageBytes = getCompiledTransactionMessageEncoder().encode(message) as TransactionMessageBytes;
  const wire = getTransactionEncoder().encode({messageBytes, signatures: {[wallet]: null}});
  const report = inspectUnsignedV0TransactionStructure(Uint8Array.from(wire), wallet);
  let calls = 0;
  await assert.rejects(resolver(async () => { calls += 1; return Response.json({}); }).resolve(report),
    errorIs('LOOKUP_STRUCTURE_INVALID'));
  assert.equal(calls, 0);
});

it('uses one total deadline, makes no retry, and releases the concurrency permit after timeout', async () => {
  let calls = 0;
  const never: typeof globalThis.fetch = async (_input, init) => {
    calls += 1;
    return new Promise<Response>((_resolve, reject) => {
      init?.signal?.addEventListener('abort', () => reject(new Error('private-upstream')), {once: true});
    });
  };
  const api = resolver(never, {timeoutMs: 10, maxConcurrentResolutions: 1});
  await assert.rejects(api.resolve(structure()), errorIs('LOOKUP_RPC_TIMEOUT'));
  await assert.rejects(api.resolve(structure()), errorIs('LOOKUP_RPC_TIMEOUT'));
  assert.equal(calls, 2);
});

it('enforces the concurrency bound without starting another network read', async () => {
  const rpc = transport();
  let release: () => void = () => undefined;
  const gate = new Promise<void>(resolve => { release = resolve; });
  let starts = 0;
  const delayed: typeof globalThis.fetch = async (input, init) => {
    starts += 1;
    if (starts === 1) await gate;
    return rpc.fetch(input, init);
  };
  const api = resolver(delayed, {maxConcurrentResolutions: 1});
  const first = api.resolve(structure());
  await Promise.resolve();
  await assert.rejects(api.resolve(structure()), errorIs('LOOKUP_CONCURRENCY_LIMITED'));
  assert.equal(starts, 1);
  release();
  await first;
  assert.equal(starts, 3);
});

it('fails closed on invalid endpoint, bounds, clock and response bodies', async () => {
  const invalidOptions = [
    {rpcUrl: 'http://rpc.example.test'},
    {rpcUrl: 'https://user:password@rpc.example.test'},
    {rpcUrl: 'https://rpc.example.test/#fragment'},
    {rpcUrl: 'not-a-url'},
    {rpcUrl, timeoutMs: 0},
    {rpcUrl, timeoutMs: 8_001},
    {rpcUrl, maxConcurrentResolutions: 0},
    {rpcUrl, extra: true},
  ];
  for (const options of invalidOptions) {
    assert.throws(() => new SolanaMainnetLookupTableResolver(options as never),
      errorIs('LOOKUP_CONFIGURATION_INVALID'));
  }
  let calls = 0;
  await assert.rejects(new SolanaMainnetLookupTableResolver({rpcUrl, now: () => Number.NaN,
    fetch: async () => { calls += 1; return Response.json({}); }}).resolve(structure()),
  errorIs('LOOKUP_CONFIGURATION_INVALID'));
  assert.equal(calls, 0);

  let clockRead = 0;
  const elapsed = transport();
  await assert.rejects(resolver(elapsed.fetch, {timeoutMs: 10, now: () => {
    clockRead += 1;
    return observedAt + (clockRead === 1 ? 0 : 11);
  }}).resolve(structure()), errorIs('LOOKUP_RPC_TIMEOUT'));
  assert.equal(elapsed.calls.length, 3);

  const huge = transport({response: () => new Response(new Uint8Array(262_145),
    {headers: {'content-type': 'application/json'}})});
  await assert.rejects(resolver(huge.fetch).resolve(structure()), errorIs('LOOKUP_RPC_RESPONSE_INVALID'));
  assert.equal(huge.calls.length, 1);

  const digest = createHash('sha256').update(tableData([accountA, accountB, accountC])).digest('hex');
  assert.match(digest, /^[0-9a-f]{64}$/); // Fixture itself stays public and deterministic.
});

it('allows repeated instruction references without increasing the unique account space', async () => {
  const rpc = transport();
  const result = await resolver(rpc.fetch).resolve(structure(false, 80));
  assert.equal(result.accountIndexMap.length, 2);
  await assert.rejects(resolver(rpc.fetch).resolve(structure(false, 257)), errorIs('LOOKUP_STRUCTURE_INVALID'));
});
