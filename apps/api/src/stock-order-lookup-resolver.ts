import {createHash} from 'node:crypto';
import {
  address,
  getAddressDecoder,
  getAddressEncoder,
  getArrayDecoder,
  getArrayEncoder,
  getOptionDecoder,
  getOptionEncoder,
  getStructDecoder,
  getStructEncoder,
  getU16Decoder,
  getU16Encoder,
  getU32Decoder,
  getU32Encoder,
  getU64Decoder,
  getU64Encoder,
  getU8Decoder,
  getU8Encoder,
  isOffCurveAddress,
  isSome,
} from '@solana/kit';
import type {
  StockTransactionAccountReference,
  StockTransactionLookupDescriptor,
  UnsignedV0TransactionStructure,
} from './stock-order-transaction-inspector.js';

export const STOCK_LOOKUP_MAINNET_GENESIS = '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d';
export const STOCK_LOOKUP_TABLE_PROGRAM = 'AddressLookupTab1e1111111111111111111111111';

export type StockLookupResolutionErrorCode =
  | 'LOOKUP_CONFIGURATION_INVALID'
  | 'LOOKUP_STRUCTURE_INVALID'
  | 'LOOKUP_WRONG_NETWORK'
  | 'LOOKUP_RPC_TIMEOUT'
  | 'LOOKUP_RPC_UNAVAILABLE'
  | 'LOOKUP_RPC_RESPONSE_INVALID'
  | 'LOOKUP_TABLE_MISSING'
  | 'LOOKUP_TABLE_INVALID'
  | 'LOOKUP_TABLE_DEACTIVATED'
  | 'LOOKUP_INDEX_OUT_OF_RANGE'
  | 'LOOKUP_ACCOUNT_DUPLICATED'
  | 'LOOKUP_OBSERVATION_CHANGED'
  | 'LOOKUP_CONCURRENCY_LIMITED';

export class StockLookupResolutionError extends Error {
  constructor(readonly code: StockLookupResolutionErrorCode) {
    super('The Solana address-lookup-table review could not be completed.');
    this.name = 'StockLookupResolutionError';
  }
}

export type ResolvedStockAccountIndex = Readonly<{
  readonly accountIndex: number;
  readonly address: string;
  readonly signer: boolean;
  readonly writable: boolean;
  readonly source: 'static';
  readonly staticAccountIndex: number;
}> | Readonly<{
  readonly accountIndex: number;
  readonly address: string;
  readonly signer: false;
  readonly writable: boolean;
  readonly source: 'lookup_table';
  readonly lookupTablePosition: number;
  readonly lookupTableAddress: string;
  readonly lookupIndex: number;
  readonly tableDataSha256: string;
}>;

export interface StockLookupTableEvidence {
  readonly lookupTablePosition: number;
  readonly lookupTableAddress: string;
  readonly ownerProgram: typeof STOCK_LOOKUP_TABLE_PROGRAM;
  readonly accountDataLengthBytes: number;
  readonly accountDataSha256: string;
  readonly accountObservationSha256: string;
  readonly addressCount: number;
  readonly referencedAddressCount: number;
  readonly deactivationSlot: '18446744073709551615';
  readonly lastExtendedSlot: string;
  readonly lastExtendedSlotStartIndex: number;
  readonly authorityStatus: 'mutable' | 'frozen';
  readonly stableAcrossFinalizedReads: true;
}

export interface ResolvedStockTransactionAccounts {
  readonly schemaVersion: 1;
  readonly kind: 'solana_v0_resolved_account_indexes';
  readonly network: 'solana:mainnet-beta';
  readonly genesisHash: typeof STOCK_LOOKUP_MAINNET_GENESIS;
  readonly commitment: 'finalized';
  readonly transactionHash: string;
  readonly transactionMessageHash: string;
  readonly resolutionStartedAt: string;
  readonly observedAt: string;
  readonly firstObservationSlot: string | null;
  readonly secondObservationSlot: string | null;
  readonly accountIndexMap: readonly ResolvedStockAccountIndex[];
  readonly lookupTables: readonly StockLookupTableEvidence[];
  readonly provenance: Readonly<{
    readonly rpcMethods: readonly ['getGenesisHash'] | readonly ['getGenesisHash', 'getMultipleAccounts', 'getMultipleAccounts'];
    readonly tableAddressesRequested: readonly string[];
    readonly tableReadCount: 0 | 2;
    readonly rpcApiVersion: string | null;
    readonly retries: 0;
    readonly cacheUsed: false;
    readonly observationsStable: true;
    readonly digestSha256: string;
  }>;
  readonly assessment: Readonly<{
    readonly status: 'account_indexes_resolved_but_incomplete';
    readonly clusterGenesis: 'verified';
    readonly lookupTableAccounts: 'verified_stable_finalized' | 'not_applicable';
    readonly lookupTableFreshness: 'point_in_time_only';
    readonly revalidationRequired: true;
    readonly accountIndexResolution: 'complete';
    readonly recentBlockhash: 'unverified';
    readonly programOwnership: 'unverified';
    readonly instructionSemantics: 'unverified';
    readonly accountState: 'unverified';
    readonly transactionTerms: 'unverified';
    readonly simulation: 'not_run';
    readonly approvable: false;
    readonly readyForSimulation: false;
    readonly signingEnabled: false;
    readonly broadcastEnabled: false;
    readonly financialOperationsEnabled: false;
  }>;
}

export interface StockLookupResolverOptions {
  readonly rpcUrl: string;
  readonly fetch?: typeof globalThis.fetch;
  readonly now?: () => number;
  readonly timeoutMs?: number;
  readonly maxConcurrentResolutions?: number;
}

const MAX_TRANSACTION_BYTES = 1_232;
const MAX_ACCOUNT_INDEXES = 64;
const MAX_INSTRUCTIONS = 64;
const MAX_LOOKUP_TABLES = 16;
const MAX_TABLE_ADDRESSES = 256;
const MAX_TABLE_DATA_BYTES = 56 + MAX_TABLE_ADDRESSES * 32;
const MAX_JSON_BYTES = 262_144;
const U64_MAX = 18_446_744_073_709_551_615n;
const ZERO_ADDRESS = '11111111111111111111111111111111';
const HASH = /^[0-9a-f]{64}$/;
const SAFE_API_VERSION = /^\d{1,5}\.\d{1,5}\.\d{1,5}(?:[-+][0-9A-Za-z.-]{1,32})?$/;

const lookupTableDecoder = getStructDecoder([
  ['discriminator', getU32Decoder()],
  ['deactivationSlot', getU64Decoder()],
  ['lastExtendedSlot', getU64Decoder()],
  ['lastExtendedSlotStartIndex', getU8Decoder()],
  ['authority', getOptionDecoder(getAddressDecoder(), {noneValue: 'zeroes'})],
  ['padding', getU16Decoder()],
  ['addresses', getArrayDecoder(getAddressDecoder(), {size: 'remainder'})],
]);
const lookupTableEncoder = getStructEncoder([
  ['discriminator', getU32Encoder()],
  ['deactivationSlot', getU64Encoder()],
  ['lastExtendedSlot', getU64Encoder()],
  ['lastExtendedSlotStartIndex', getU8Encoder()],
  ['authority', getOptionEncoder(getAddressEncoder(), {noneValue: 'zeroes'})],
  ['padding', getU16Encoder()],
  ['addresses', getArrayEncoder(getAddressEncoder(), {size: 'remainder'})],
]);

const fail = (code: StockLookupResolutionErrorCode): never => {
  throw new StockLookupResolutionError(code);
};
const sha256 = (value: Uint8Array | string): string => createHash('sha256').update(value).digest('hex');

function ownRecord(value: unknown, code: StockLookupResolutionErrorCode,
  maximumKeys = 32): Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return fail(code);
  const proto: unknown = Object.getPrototypeOf(value);
  if (proto !== Object.prototype && proto !== null) return fail(code);
  const keys = Reflect.ownKeys(value);
  if (keys.length > maximumKeys) return fail(code);
  const copy: Record<string, unknown> = {};
  for (const key of keys) {
    if (typeof key !== 'string') return fail(code);
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) return fail(code);
    Object.defineProperty(copy, key, {value: descriptor.value, enumerable: true});
  }
  return copy;
}

function exactKeys(value: Record<string, unknown>, allowed: readonly string[],
  required = allowed): void {
  if (Object.keys(value).some(key => !allowed.includes(key)) ||
      required.some(key => !Object.hasOwn(value, key))) return fail('LOOKUP_STRUCTURE_INVALID');
}

function integer(value: unknown, minimum: number, maximum: number,
  code: StockLookupResolutionErrorCode): number {
  if (!Number.isSafeInteger(value) || (value as number) < minimum || (value as number) > maximum) return fail(code);
  return value as number;
}

function ownArray(value: unknown, minimum: number, maximum: number,
  code: StockLookupResolutionErrorCode): readonly unknown[] {
  if (!Array.isArray(value) || Object.getPrototypeOf(value) !== Array.prototype ||
      value.length < minimum || value.length > maximum) return fail(code);
  const keys = Reflect.ownKeys(value);
  if (keys.length !== value.length + 1 || !keys.includes('length')) return fail(code);
  const copy: unknown[] = [];
  for (let index = 0; index < value.length; index++) {
    const descriptor = Object.getOwnPropertyDescriptor(value, String(index));
    if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) return fail(code);
    copy.push(descriptor.value);
  }
  return copy;
}

function canonicalAddress(value: unknown, code: StockLookupResolutionErrorCode): string {
  try {
    if (typeof value !== 'string' || value.length < 32 || value.length > 44) return fail(code);
    const checked = address(value);
    if (checked !== value) return fail(code);
    return checked;
  } catch {
    return fail(code);
  }
}

function hexHash(value: unknown): string {
  if (typeof value !== 'string' || HASH.exec(value)?.[0] !== value) return fail('LOOKUP_STRUCTURE_INVALID');
  return value;
}

function boolFalse(value: unknown): false {
  if (value !== false) return fail('LOOKUP_STRUCTURE_INVALID');
  return false;
}

function expectedReference(index: number, staticAccounts: readonly string[],
  lookups: readonly StockTransactionLookupDescriptor[]): StockTransactionAccountReference {
  if (index < staticAccounts.length) {
    const resolved = staticAccounts[index];
    if (resolved === undefined) return fail('LOOKUP_STRUCTURE_INVALID');
    return {kind: 'static', accountIndex: index, address: resolved};
  }
  let offset = index - staticAccounts.length;
  for (const [position, table] of lookups.entries()) {
    if (offset < table.writableIndexes.length) {
      const lookupIndex = table.writableIndexes[offset];
      if (lookupIndex === undefined) return fail('LOOKUP_STRUCTURE_INVALID');
      return {kind: 'lookup', accountIndex: index, lookupTablePosition: position,
        lookupTableAddress: table.lookupTableAddress, lookupIndex, writable: true};
    }
    offset -= table.writableIndexes.length;
  }
  for (const [position, table] of lookups.entries()) {
    if (offset < table.readonlyIndexes.length) {
      const lookupIndex = table.readonlyIndexes[offset];
      if (lookupIndex === undefined) return fail('LOOKUP_STRUCTURE_INVALID');
      return {kind: 'lookup', accountIndex: index, lookupTablePosition: position,
        lookupTableAddress: table.lookupTableAddress, lookupIndex, writable: false};
    }
    offset -= table.readonlyIndexes.length;
  }
  return fail('LOOKUP_STRUCTURE_INVALID');
}

function validateReference(value: unknown, expected: StockTransactionAccountReference): void {
  const data = ownRecord(value, 'LOOKUP_STRUCTURE_INVALID', 8);
  const keys = expected.kind === 'static' ? ['kind', 'accountIndex', 'address'] :
    ['kind', 'accountIndex', 'lookupTablePosition', 'lookupTableAddress', 'lookupIndex', 'writable'];
  exactKeys(data, keys);
  for (const key of keys) if (data[key] !== expected[key as keyof typeof expected]) return fail('LOOKUP_STRUCTURE_INVALID');
}

function validateStructure(value: UnsignedV0TransactionStructure): Readonly<{
  transactionHash: string;
  transactionMessageHash: string;
  staticAccounts: readonly string[];
  lookups: readonly StockTransactionLookupDescriptor[];
  readonlyNonSigners: number;
  totalAccountIndexes: number;
}> {
  const root = ownRecord(value, 'LOOKUP_STRUCTURE_INVALID', 20);
  const required = ['schemaVersion', 'kind', 'transactionVersion', 'transactionSizeBytes', 'transactionHash',
    'transactionMessageHash', 'requiredSigner', 'signatures', 'header', 'lifetimeToken', 'staticAccountKeys',
    'addressTableLookups', 'accountIndexSpace', 'instructions', 'assessment'];
  exactKeys(root, [...required, 'networkContext', 'draftBindingHash', 'candidateTermsHash'], required);
  if (root['schemaVersion'] !== 1 || root['kind'] !== 'unsigned_solana_v0_structure' ||
      root['transactionVersion'] !== 0) return fail('LOOKUP_STRUCTURE_INVALID');
  integer(root['transactionSizeBytes'], 1, MAX_TRANSACTION_BYTES, 'LOOKUP_STRUCTURE_INVALID');
  const transactionHash = hexHash(root['transactionHash']);
  const transactionMessageHash = hexHash(root['transactionMessageHash']);
  if (Object.hasOwn(root, 'networkContext') && root['networkContext'] !== 'solana:mainnet-beta') {
    return fail('LOOKUP_STRUCTURE_INVALID');
  }
  for (const key of ['draftBindingHash', 'candidateTermsHash']) {
    if (Object.hasOwn(root, key)) hexHash(root[key]);
  }

  const signer = ownRecord(root['requiredSigner'], 'LOOKUP_STRUCTURE_INVALID', 3);
  exactKeys(signer, ['address', 'accountIndex', 'role']);
  const signerAddress = canonicalAddress(signer['address'], 'LOOKUP_STRUCTURE_INVALID');
  if (signer['accountIndex'] !== 0 || signer['role'] !== 'fee_payer_and_taker' || signerAddress === ZERO_ADDRESS) {
    return fail('LOOKUP_STRUCTURE_INVALID');
  }
  try {
    if (isOffCurveAddress(address(signerAddress))) return fail('LOOKUP_STRUCTURE_INVALID');
  } catch { return fail('LOOKUP_STRUCTURE_INVALID'); }
  const signatures = ownRecord(root['signatures'], 'LOOKUP_STRUCTURE_INVALID', 4);
  exactKeys(signatures, ['required', 'present', 'absent', 'unsigned']);
  if (signatures['required'] !== 1 || signatures['present'] !== 0 || signatures['absent'] !== 1 ||
      signatures['unsigned'] !== true) return fail('LOOKUP_STRUCTURE_INVALID');

  const header = ownRecord(root['header'], 'LOOKUP_STRUCTURE_INVALID', 3);
  exactKeys(header, ['numSignerAccounts', 'numReadonlySignerAccounts', 'numReadonlyNonSignerAccounts']);
  if (header['numSignerAccounts'] !== 1 || header['numReadonlySignerAccounts'] !== 0) {
    return fail('LOOKUP_STRUCTURE_INVALID');
  }
  const readonlyNonSigners = integer(header['numReadonlyNonSignerAccounts'], 0, MAX_ACCOUNT_INDEXES - 1,
    'LOOKUP_STRUCTURE_INVALID');

  const lifetime = ownRecord(root['lifetimeToken'], 'LOOKUP_STRUCTURE_INVALID', 4);
  exactKeys(lifetime, ['value', 'expectedUse', 'semanticKindVerified', 'mainnetRecencyVerified']);
  if (canonicalAddress(lifetime['value'], 'LOOKUP_STRUCTURE_INVALID') === ZERO_ADDRESS ||
      lifetime['expectedUse'] !== 'recent_blockhash' || lifetime['semanticKindVerified'] !== false ||
      lifetime['mainnetRecencyVerified'] !== false) return fail('LOOKUP_STRUCTURE_INVALID');

  const staticInput = ownArray(root['staticAccountKeys'], 2, MAX_ACCOUNT_INDEXES, 'LOOKUP_STRUCTURE_INVALID');
  const staticAccounts = staticInput.map(item => canonicalAddress(item, 'LOOKUP_STRUCTURE_INVALID'));
  if (staticAccounts[0] !== signerAddress || new Set(staticAccounts).size !== staticAccounts.length ||
      readonlyNonSigners > staticAccounts.length - 1) return fail('LOOKUP_STRUCTURE_INVALID');

  const lookupInput = ownArray(root['addressTableLookups'], 0, MAX_LOOKUP_TABLES, 'LOOKUP_STRUCTURE_INVALID');
  const tableAddresses = new Set<string>();
  let writableCount = 0;
  let readonlyCount = 0;
  const lookups: StockTransactionLookupDescriptor[] = lookupInput.map(item => {
    const data = ownRecord(item, 'LOOKUP_STRUCTURE_INVALID', 3);
    exactKeys(data, ['lookupTableAddress', 'writableIndexes', 'readonlyIndexes']);
    const tableAddress = canonicalAddress(data['lookupTableAddress'], 'LOOKUP_STRUCTURE_INVALID');
    if (tableAddress === ZERO_ADDRESS || tableAddresses.has(tableAddress)) return fail('LOOKUP_STRUCTURE_INVALID');
    const writableInput = ownArray(data['writableIndexes'], 0, MAX_ACCOUNT_INDEXES, 'LOOKUP_STRUCTURE_INVALID');
    const readonlyInput = ownArray(data['readonlyIndexes'], 0, MAX_ACCOUNT_INDEXES, 'LOOKUP_STRUCTURE_INVALID');
    if (writableInput.length + readonlyInput.length > MAX_ACCOUNT_INDEXES) {
      return fail('LOOKUP_STRUCTURE_INVALID');
    }
    const writable = writableInput.map(index => integer(index, 0, 255, 'LOOKUP_STRUCTURE_INVALID'));
    const readonly = readonlyInput.map(index => integer(index, 0, 255, 'LOOKUP_STRUCTURE_INVALID'));
    const all = [...writable, ...readonly];
    if (all.length < 1 || new Set(all).size !== all.length) return fail('LOOKUP_STRUCTURE_INVALID');
    tableAddresses.add(tableAddress);
    writableCount += writable.length;
    readonlyCount += readonly.length;
    return {lookupTableAddress: tableAddress, writableIndexes: writable, readonlyIndexes: readonly};
  });

  const indexSpace = ownRecord(root['accountIndexSpace'], 'LOOKUP_STRUCTURE_INVALID', 4);
  exactKeys(indexSpace, ['static', 'lookupWritable', 'lookupReadonly', 'total']);
  const total = staticAccounts.length + writableCount + readonlyCount;
  if (total > MAX_ACCOUNT_INDEXES || indexSpace['static'] !== staticAccounts.length ||
      indexSpace['lookupWritable'] !== writableCount || indexSpace['lookupReadonly'] !== readonlyCount ||
      indexSpace['total'] !== total) return fail('LOOKUP_STRUCTURE_INVALID');

  const instructionInput = ownArray(root['instructions'], 1, MAX_INSTRUCTIONS, 'LOOKUP_STRUCTURE_INVALID');
  instructionInput.forEach((item, instructionIndex) => {
    const instruction = ownRecord(item, 'LOOKUP_STRUCTURE_INVALID', 6);
    exactKeys(instruction, ['instructionIndex', 'programAddressIndex', 'program', 'accountIndices',
      'dataLengthBytes', 'dataSha256']);
    const programIndex = integer(instruction['programAddressIndex'], 1, total - 1, 'LOOKUP_STRUCTURE_INVALID');
    if (instruction['instructionIndex'] !== instructionIndex) return fail('LOOKUP_STRUCTURE_INVALID');
    // Instruction references may repeat an account across swap hops; the
    // unique address space remains capped independently at 64.
    const accountIndices = ownArray(instruction['accountIndices'], 0, 256,
      'LOOKUP_STRUCTURE_INVALID');
    accountIndices.forEach(index => integer(index, 0, total - 1, 'LOOKUP_STRUCTURE_INVALID'));
    integer(instruction['dataLengthBytes'], 0, MAX_TRANSACTION_BYTES, 'LOOKUP_STRUCTURE_INVALID');
    hexHash(instruction['dataSha256']);
    validateReference(instruction['program'], expectedReference(programIndex, staticAccounts, lookups));
  });

  const assessment = ownRecord(root['assessment'], 'LOOKUP_STRUCTURE_INVALID', 15);
  exactKeys(assessment, ['status', 'structuralIntegrity', 'requiredSignerBinding', 'staticAccountResolution',
    'lookupTableResolution', 'recentBlockhash', 'instructionSemantics', 'accountState', 'transactionTerms',
    'simulation', 'approvable', 'readyForSimulation', 'signingEnabled', 'broadcastEnabled',
    'financialOperationsEnabled']);
  if (assessment['status'] !== 'structurally_valid_but_incomplete' ||
      assessment['structuralIntegrity'] !== 'verified' || assessment['requiredSignerBinding'] !== 'verified' ||
      assessment['staticAccountResolution'] !== 'complete' ||
      assessment['lookupTableResolution'] !== (lookups.length ? 'required' : 'not_applicable') ||
      assessment['recentBlockhash'] !== 'unverified' || assessment['instructionSemantics'] !== 'unverified' ||
      assessment['accountState'] !== 'unverified' || assessment['transactionTerms'] !== 'unverified' ||
      assessment['simulation'] !== 'not_run') return fail('LOOKUP_STRUCTURE_INVALID');
  for (const key of ['approvable', 'readyForSimulation', 'signingEnabled', 'broadcastEnabled',
    'financialOperationsEnabled']) boolFalse(assessment[key]);

  return {transactionHash, transactionMessageHash, staticAccounts: Object.freeze(staticAccounts),
    lookups: Object.freeze(lookups.map(table => Object.freeze({lookupTableAddress: table.lookupTableAddress,
      writableIndexes: Object.freeze([...table.writableIndexes]),
      readonlyIndexes: Object.freeze([...table.readonlyIndexes])}))), readonlyNonSigners,
    totalAccountIndexes: total};
}

function clock(now: () => number): number {
  let value: unknown;
  try { value = now(); } catch { return fail('LOOKUP_CONFIGURATION_INVALID'); }
  return integer(value, 0, 8_639_999_999_999_999, 'LOOKUP_CONFIGURATION_INVALID');
}

interface RpcDeadline {
  readonly controller: AbortController;
  readonly expired: Promise<never>;
}

class LookupRpc {
  readonly #url: URL;
  readonly #fetch: typeof globalThis.fetch;
  #requestId = 0;

  constructor(url: URL, fetchImpl: typeof globalThis.fetch) {
    this.#url = url;
    this.#fetch = fetchImpl;
  }

  async genesis(deadline: RpcDeadline): Promise<unknown> {
    return this.#post({jsonrpc: '2.0', id: this.#nextId(), method: 'getGenesisHash'}, deadline);
  }

  async tables(tableAddresses: readonly string[], minimumContextSlot: number | undefined,
    deadline: RpcDeadline): Promise<unknown> {
    const configuration: Record<string, unknown> = {encoding: 'base64', commitment: 'finalized'};
    if (minimumContextSlot !== undefined) configuration['minContextSlot'] = minimumContextSlot;
    return this.#post({jsonrpc: '2.0', id: this.#nextId(), method: 'getMultipleAccounts',
      params: [tableAddresses, configuration]}, deadline);
  }

  #nextId(): number {
    this.#requestId += 1;
    if (!Number.isSafeInteger(this.#requestId)) return fail('LOOKUP_RPC_UNAVAILABLE');
    return this.#requestId;
  }

  async #post(request: Readonly<Record<string, unknown>>, deadline: RpcDeadline): Promise<unknown> {
    let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
    let response: Response | undefined;
    try {
      const pending = this.#fetch(this.#url, {
        method: 'POST',
        headers: {'content-type': 'application/json', accept: 'application/json'},
        redirect: 'error',
        signal: deadline.controller.signal,
        body: JSON.stringify(request),
      });
      void pending.then(late => {
        if (deadline.controller.signal.aborted) void late.body?.cancel().catch(() => undefined);
      }, () => undefined);
      response = await Promise.race([pending, deadline.expired]);
      if (deadline.controller.signal.aborted) return fail('LOOKUP_RPC_TIMEOUT');
      if (response.status !== 200) return fail('LOOKUP_RPC_UNAVAILABLE');
      if (response.redirected) return fail('LOOKUP_RPC_RESPONSE_INVALID');
      if (response.url !== '' && response.url !== this.#url.href) return fail('LOOKUP_RPC_RESPONSE_INVALID');
      if (!/^application\/json(?:\s*;|$)/i.test(response.headers.get('content-type') ?? '') || !response.body) {
        return fail('LOOKUP_RPC_RESPONSE_INVALID');
      }
      const declared = response.headers.get('content-length');
      if (declared !== null && (declared.length > 20 || /^(?:0|[1-9][0-9]*)$/.exec(declared)?.[0] !== declared ||
          BigInt(declared) > BigInt(MAX_JSON_BYTES))) return fail('LOOKUP_RPC_RESPONSE_INVALID');
      reader = response.body.getReader();
      const chunks: Uint8Array[] = [];
      let length = 0;
      while (true) {
        const part = await Promise.race([reader.read(), deadline.expired]);
        if (part.done) break;
        length += part.value.byteLength;
        if (length > MAX_JSON_BYTES) return fail('LOOKUP_RPC_RESPONSE_INVALID');
        chunks.push(part.value);
      }
      let decoded: unknown;
      try {
        decoded = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(Buffer.concat(chunks)));
      } catch {
        return fail('LOOKUP_RPC_RESPONSE_INVALID');
      }
      const envelope = ownRecord(decoded, 'LOOKUP_RPC_RESPONSE_INVALID', 3);
      if (Object.keys(envelope).length !== 3 || envelope['jsonrpc'] !== '2.0' ||
          envelope['id'] !== request['id'] || !Object.hasOwn(envelope, 'result')) {
        return fail('LOOKUP_RPC_RESPONSE_INVALID');
      }
      return envelope['result'];
    } catch (error) {
      if (deadline.controller.signal.aborted) return fail('LOOKUP_RPC_TIMEOUT');
      if (error instanceof StockLookupResolutionError) throw error;
      return fail('LOOKUP_RPC_UNAVAILABLE');
    } finally {
      if (reader) void reader.cancel().catch(() => undefined);
      else if (response?.body) void response.body.cancel().catch(() => undefined);
    }
  }
}

interface ParsedTable {
  readonly tableAddress: string;
  readonly bytes: Uint8Array;
  readonly addresses: readonly string[];
  readonly deactivationSlot: bigint;
  readonly lastExtendedSlot: bigint;
  readonly lastExtendedSlotStartIndex: number;
  readonly authorityStatus: 'mutable' | 'frozen';
  readonly observationSha256: string;
}
interface TableBatch {
  readonly slot: number;
  readonly apiVersion: string | null;
  readonly tables: readonly ParsedTable[];
}

function canonicalBase64(value: unknown): Uint8Array {
  if (typeof value !== 'string' || value.length < 4 || value.length > 11_000 || value.length % 4 !== 0 ||
      !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(value)) {
    return fail('LOOKUP_TABLE_INVALID');
  }
  const bytes = Buffer.from(value, 'base64');
  if (bytes.toString('base64') !== value || bytes.byteLength < 56 || bytes.byteLength > MAX_TABLE_DATA_BYTES ||
      (bytes.byteLength - 56) % 32 !== 0) return fail('LOOKUP_TABLE_INVALID');
  return Uint8Array.from(bytes);
}

function rpcNumeric(value: unknown, positive: boolean): void {
  if (typeof value !== 'number' || !Number.isFinite(value) || !Number.isInteger(value) ||
      value < (positive ? 1 : 0)) return fail('LOOKUP_RPC_RESPONSE_INVALID');
}

function parseTableAccount(value: unknown, tableAddress: string, observationSlot: number): ParsedTable {
  if (value === null) return fail('LOOKUP_TABLE_MISSING');
  const account = ownRecord(value, 'LOOKUP_RPC_RESPONSE_INVALID', 6);
  exactRpcKeys(account, ['data', 'executable', 'lamports', 'owner', 'rentEpoch', 'space']);
  if (account['owner'] !== STOCK_LOOKUP_TABLE_PROGRAM || account['executable'] !== false) {
    return fail('LOOKUP_TABLE_INVALID');
  }
  // These RPC fields are JSON numbers, including u64 rentEpoch values that may
  // exceed Number.MAX_SAFE_INTEGER. Validate their wire type but do not claim
  // lossless provenance or use them for table-resolution stability.
  rpcNumeric(account['lamports'], true);
  rpcNumeric(account['rentEpoch'], false);
  const encodedData = ownArray(account['data'], 2, 2, 'LOOKUP_TABLE_INVALID');
  if (encodedData[1] !== 'base64') return fail('LOOKUP_TABLE_INVALID');
  const bytes = canonicalBase64(encodedData[0]);
  if (integer(account['space'], 56, MAX_TABLE_DATA_BYTES, 'LOOKUP_RPC_RESPONSE_INVALID') !== bytes.byteLength) {
    return fail('LOOKUP_TABLE_INVALID');
  }
  try {
    const decoded = lookupTableDecoder.decode(bytes);
    const reencoded = lookupTableEncoder.encode(decoded);
    if (!Buffer.from(reencoded).equals(Buffer.from(bytes)) || decoded.discriminator !== 1 || decoded.padding !== 0 ||
        decoded.addresses.length > MAX_TABLE_ADDRESSES ||
        decoded.lastExtendedSlotStartIndex > decoded.addresses.length) return fail('LOOKUP_TABLE_INVALID');
    if (decoded.deactivationSlot !== U64_MAX) return fail('LOOKUP_TABLE_DEACTIVATED');
    if (decoded.lastExtendedSlot >= BigInt(observationSlot)) return fail('LOOKUP_TABLE_INVALID');
    const observationSha256 = sha256(JSON.stringify({tableAddress, owner: account['owner'], executable: false,
      space: bytes.byteLength, dataSha256: sha256(bytes)}));
    return {tableAddress, bytes, addresses: Object.freeze([...decoded.addresses]),
      deactivationSlot: decoded.deactivationSlot, lastExtendedSlot: decoded.lastExtendedSlot,
      lastExtendedSlotStartIndex: decoded.lastExtendedSlotStartIndex,
      authorityStatus: isSome(decoded.authority) ? 'mutable' : 'frozen', observationSha256};
  } catch (error) {
    if (error instanceof StockLookupResolutionError) throw error;
    return fail('LOOKUP_TABLE_INVALID');
  }
}

function exactRpcKeys(value: Record<string, unknown>, keys: readonly string[]): void {
  if (Object.keys(value).length !== keys.length || Object.keys(value).some(key => !keys.includes(key)) ||
      keys.some(key => !Object.hasOwn(value, key))) return fail('LOOKUP_RPC_RESPONSE_INVALID');
}

function parseBatch(value: unknown, tableAddresses: readonly string[]): TableBatch {
  const result = ownRecord(value, 'LOOKUP_RPC_RESPONSE_INVALID', 2);
  exactRpcKeys(result, ['context', 'value']);
  const context = ownRecord(result['context'], 'LOOKUP_RPC_RESPONSE_INVALID', 2);
  if (Object.keys(context).some(key => !['slot', 'apiVersion'].includes(key)) || !Object.hasOwn(context, 'slot')) {
    return fail('LOOKUP_RPC_RESPONSE_INVALID');
  }
  const slot = integer(context['slot'], 1, Number.MAX_SAFE_INTEGER, 'LOOKUP_RPC_RESPONSE_INVALID');
  if (Object.hasOwn(context, 'apiVersion') &&
      (typeof context['apiVersion'] !== 'string' || SAFE_API_VERSION.exec(context['apiVersion'])?.[0] !== context['apiVersion'])) {
    return fail('LOOKUP_RPC_RESPONSE_INVALID');
  }
  const accounts = ownArray(result['value'], tableAddresses.length, tableAddresses.length,
    'LOOKUP_RPC_RESPONSE_INVALID');
  return {slot, apiVersion: Object.hasOwn(context, 'apiVersion') ? context['apiVersion'] as string : null,
    tables: Object.freeze(accounts.map((accountInfo, position) => {
    const tableAddress = tableAddresses[position];
    if (tableAddress === undefined) return fail('LOOKUP_RPC_RESPONSE_INVALID');
    return parseTableAccount(accountInfo, tableAddress, slot);
  }))};
}

function staticWritable(index: number, staticCount: number, readonlyNonSigners: number): boolean {
  return index === 0 || index < staticCount - readonlyNonSigners;
}

function frozenStaticIndexes(staticAccounts: readonly string[], readonlyNonSigners: number): ResolvedStockAccountIndex[] {
  return staticAccounts.map((accountAddress, index) => Object.freeze({accountIndex: index, address: accountAddress,
    signer: index === 0, writable: staticWritable(index, staticAccounts.length, readonlyNonSigners),
    source: 'static' as const, staticAccountIndex: index}));
}

function stableTable(first: ParsedTable, second: ParsedTable): void {
  if (first.tableAddress !== second.tableAddress || first.observationSha256 !== second.observationSha256 ||
      !Buffer.from(first.bytes).equals(Buffer.from(second.bytes))) return fail('LOOKUP_OBSERVATION_CHANGED');
}

export class SolanaMainnetLookupTableResolver {
  readonly #rpc!: LookupRpc;
  readonly #now!: () => number;
  readonly #timeoutMs!: number;
  readonly #maxConcurrent!: number;
  #active = 0;

  constructor(options: StockLookupResolverOptions) {
    try {
      const input = ownRecord(options, 'LOOKUP_CONFIGURATION_INVALID', 5);
      exactOptionKeys(input);
      if (typeof input['rpcUrl'] !== 'string' || input['rpcUrl'].length < 1 || input['rpcUrl'].length > 2_048 ||
          /[\u0000-\u0020\u007f]/.test(input['rpcUrl']) ||
          (input['fetch'] !== undefined && typeof input['fetch'] !== 'function') ||
          (input['now'] !== undefined && typeof input['now'] !== 'function')) return fail('LOOKUP_CONFIGURATION_INVALID');
      const url = new URL(input['rpcUrl']);
      if (url.protocol !== 'https:' || url.username !== '' || url.password !== '' || url.hash !== '') {
        return fail('LOOKUP_CONFIGURATION_INVALID');
      }
      this.#timeoutMs = integer(input['timeoutMs'] ?? 6_000, 1, 8_000, 'LOOKUP_CONFIGURATION_INVALID');
      this.#maxConcurrent = integer(input['maxConcurrentResolutions'] ?? 2, 1, 8,
        'LOOKUP_CONFIGURATION_INVALID');
      this.#now = (input['now'] as (() => number) | undefined) ?? Date.now;
      this.#rpc = new LookupRpc(url, (input['fetch'] as typeof globalThis.fetch | undefined) ?? globalThis.fetch);
    } catch (error) {
      if (error instanceof StockLookupResolutionError) throw error;
      return fail('LOOKUP_CONFIGURATION_INVALID');
    }
  }

  async resolve(structure: UnsignedV0TransactionStructure): Promise<ResolvedStockTransactionAccounts> {
    const validated = validateStructure(structure);
    const started = clock(this.#now);
    if (this.#active >= this.#maxConcurrent) return fail('LOOKUP_CONCURRENCY_LIMITED');
    this.#active += 1;
    const controller = new AbortController();
    let rejectExpiry: (reason: StockLookupResolutionError) => void = () => undefined;
    const expired = new Promise<never>((_resolve, reject) => { rejectExpiry = reject; });
    const timer = setTimeout(() => {
      controller.abort();
      rejectExpiry(new StockLookupResolutionError('LOOKUP_RPC_TIMEOUT'));
    }, this.#timeoutMs);
    const deadline: RpcDeadline = {controller, expired};
    try {
      const genesis = await this.#rpc.genesis(deadline);
      if (typeof genesis !== 'string') return fail('LOOKUP_RPC_RESPONSE_INVALID');
      if (genesis !== STOCK_LOOKUP_MAINNET_GENESIS) return fail('LOOKUP_WRONG_NETWORK');

      const tableAddresses = validated.lookups.map(table => table.lookupTableAddress);
      let first: TableBatch | undefined;
      let second: TableBatch | undefined;
      if (tableAddresses.length) {
        first = parseBatch(await this.#rpc.tables(tableAddresses, undefined, deadline), tableAddresses);
        second = parseBatch(await this.#rpc.tables(tableAddresses, first.slot, deadline), tableAddresses);
        if (second.slot < first.slot || second.apiVersion !== first.apiVersion) {
          return fail('LOOKUP_OBSERVATION_CHANGED');
        }
        for (let position = 0; position < first.tables.length; position++) {
          const firstTable = first.tables[position];
          const secondTable = second.tables[position];
          if (!firstTable || !secondTable) return fail('LOOKUP_RPC_RESPONSE_INVALID');
          stableTable(firstTable, secondTable);
        }
      }

      const map: ResolvedStockAccountIndex[] = frozenStaticIndexes(validated.staticAccounts,
        validated.readonlyNonSigners);
      const evidence: StockLookupTableEvidence[] = [];
      const selected = new Set<string>(validated.staticAccounts);
      if (second) {
        for (const [position, descriptor] of validated.lookups.entries()) {
          const table = second.tables[position];
          if (!table) return fail('LOOKUP_RPC_RESPONSE_INVALID');
          const referenced = [...descriptor.writableIndexes, ...descriptor.readonlyIndexes];
          for (const index of referenced) if (index >= table.addresses.length) return fail('LOOKUP_INDEX_OUT_OF_RANGE');
          evidence.push(Object.freeze({lookupTablePosition: position, lookupTableAddress: descriptor.lookupTableAddress,
            ownerProgram: STOCK_LOOKUP_TABLE_PROGRAM, accountDataLengthBytes: table.bytes.byteLength,
            accountDataSha256: sha256(table.bytes), accountObservationSha256: table.observationSha256,
            addressCount: table.addresses.length, referencedAddressCount: referenced.length,
            deactivationSlot: String(table.deactivationSlot) as '18446744073709551615',
            lastExtendedSlot: String(table.lastExtendedSlot),
            lastExtendedSlotStartIndex: table.lastExtendedSlotStartIndex,
            authorityStatus: table.authorityStatus, stableAcrossFinalizedReads: true}));
        }
        for (const [position, descriptor] of validated.lookups.entries()) {
          const table = second.tables[position];
          const tableEvidence = evidence[position];
          if (!table || !tableEvidence) return fail('LOOKUP_RPC_RESPONSE_INVALID');
          for (const lookupIndex of descriptor.writableIndexes) {
            appendLookup(map, selected, table, tableEvidence, position, lookupIndex, true);
          }
        }
        for (const [position, descriptor] of validated.lookups.entries()) {
          const table = second.tables[position];
          const tableEvidence = evidence[position];
          if (!table || !tableEvidence) return fail('LOOKUP_RPC_RESPONSE_INVALID');
          for (const lookupIndex of descriptor.readonlyIndexes) {
            appendLookup(map, selected, table, tableEvidence, position, lookupIndex, false);
          }
        }
      }
      if (map.length !== validated.totalAccountIndexes) return fail('LOOKUP_STRUCTURE_INVALID');
      const finished = clock(this.#now);
      if (finished < started) return fail('LOOKUP_CONFIGURATION_INVALID');
      if (finished - started > this.#timeoutMs) return fail('LOOKUP_RPC_TIMEOUT');
      const frozenMap = Object.freeze(map);
      const frozenEvidence = Object.freeze(evidence);
      const methods = tableAddresses.length ?
        Object.freeze(['getGenesisHash', 'getMultipleAccounts', 'getMultipleAccounts'] as const) :
        Object.freeze(['getGenesisHash'] as const);
      const provenanceInput = JSON.stringify({transactionHash: validated.transactionHash,
        transactionMessageHash: validated.transactionMessageHash, genesisHash: STOCK_LOOKUP_MAINNET_GENESIS,
        firstSlot: first?.slot ?? null, secondSlot: second?.slot ?? null, tableAddresses,
        rpcApiVersion: second?.apiVersion ?? null,
        observations: frozenEvidence.map(table => table.accountObservationSha256),
        accounts: frozenMap.map(item => [item.accountIndex, item.address, item.writable, item.source])});
      return Object.freeze({schemaVersion: 1, kind: 'solana_v0_resolved_account_indexes',
        network: 'solana:mainnet-beta', genesisHash: STOCK_LOOKUP_MAINNET_GENESIS, commitment: 'finalized',
        transactionHash: validated.transactionHash, transactionMessageHash: validated.transactionMessageHash,
        resolutionStartedAt: new Date(started).toISOString(), observedAt: new Date(finished).toISOString(),
        firstObservationSlot: first ? String(first.slot) : null,
        secondObservationSlot: second ? String(second.slot) : null,
        accountIndexMap: frozenMap, lookupTables: frozenEvidence,
        provenance: Object.freeze({rpcMethods: methods, tableAddressesRequested: Object.freeze(tableAddresses),
          tableReadCount: tableAddresses.length ? 2 : 0, rpcApiVersion: second?.apiVersion ?? null,
          retries: 0, cacheUsed: false,
          observationsStable: true, digestSha256: sha256(provenanceInput)}),
        assessment: Object.freeze({status: 'account_indexes_resolved_but_incomplete', clusterGenesis: 'verified',
          lookupTableAccounts: tableAddresses.length ? 'verified_stable_finalized' : 'not_applicable',
          lookupTableFreshness: 'point_in_time_only', revalidationRequired: true,
          accountIndexResolution: 'complete', recentBlockhash: 'unverified', programOwnership: 'unverified',
          instructionSemantics: 'unverified', accountState: 'unverified', transactionTerms: 'unverified',
          simulation: 'not_run', approvable: false, readyForSimulation: false, signingEnabled: false,
          broadcastEnabled: false, financialOperationsEnabled: false})});
    } catch (error) {
      if (controller.signal.aborted) return fail('LOOKUP_RPC_TIMEOUT');
      if (error instanceof StockLookupResolutionError) throw error;
      return fail('LOOKUP_RPC_UNAVAILABLE');
    } finally {
      clearTimeout(timer);
      controller.abort();
      this.#active -= 1;
    }
  }
}

function exactOptionKeys(value: Record<string, unknown>): void {
  const allowed = ['rpcUrl', 'fetch', 'now', 'timeoutMs', 'maxConcurrentResolutions'];
  if (!Object.hasOwn(value, 'rpcUrl') || Object.keys(value).some(key => !allowed.includes(key))) {
    return fail('LOOKUP_CONFIGURATION_INVALID');
  }
}

function appendLookup(map: ResolvedStockAccountIndex[], selected: Set<string>, table: ParsedTable,
  evidence: StockLookupTableEvidence, position: number, lookupIndex: number, writable: boolean): void {
  const resolvedAddress = table.addresses[lookupIndex];
  if (resolvedAddress === undefined) return fail('LOOKUP_INDEX_OUT_OF_RANGE');
  if (selected.has(resolvedAddress)) return fail('LOOKUP_ACCOUNT_DUPLICATED');
  selected.add(resolvedAddress);
  map.push(Object.freeze({accountIndex: map.length, address: resolvedAddress, signer: false, writable,
    source: 'lookup_table', lookupTablePosition: position, lookupTableAddress: table.tableAddress,
    lookupIndex, tableDataSha256: evidence.accountDataSha256}));
}
