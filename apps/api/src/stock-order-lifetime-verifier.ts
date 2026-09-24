import {createHash} from 'node:crypto';
import {address} from '@solana/kit';
import {
  inspectStockDraftStructure,
  STOCK_DRAFT_MAINNET_GENESIS,
  StockOrderDraftError,
} from './stock-order-draft.js';
import type {
  StockDraftBinding,
  StockDraftStructuralInspection,
  StockOrderDraft,
} from './stock-order-draft.js';

export type StockOrderLifetimeVerificationErrorCode =
  | 'LIFETIME_CONFIGURATION_INVALID'
  | 'LIFETIME_BINDING_MISMATCH'
  | 'LIFETIME_DRAFT_INVALID'
  | 'LIFETIME_WRONG_NETWORK'
  | 'LIFETIME_RPC_TIMEOUT'
  | 'LIFETIME_RPC_UNAVAILABLE'
  | 'LIFETIME_RPC_RESPONSE_INVALID'
  | 'LIFETIME_BLOCKHASH_INVALID'
  | 'LIFETIME_OBSERVATION_CHANGED'
  | 'LIFETIME_EXPIRED'
  | 'LIFETIME_CONCURRENCY_LIMITED';

export class StockOrderLifetimeVerificationError extends Error {
  constructor(readonly code: StockOrderLifetimeVerificationErrorCode) {
    super('The Solana stock-order lifetime review could not be completed.');
    this.name = 'StockOrderLifetimeVerificationError';
  }
}

export interface StockOrderLifetimeVerifierOptions {
  readonly rpcUrl: string;
  readonly fetch?: typeof globalThis.fetch;
  readonly now?: () => number;
  readonly timeoutMs?: number;
  readonly maxConcurrentVerifications?: number;
}

export interface VerifiedStockOrderLifetime {
  readonly schemaVersion: 1;
  readonly kind: 'solana_recent_blockhash_lifetime_evidence';
  readonly network: 'solana:mainnet-beta';
  readonly genesisHash: typeof STOCK_DRAFT_MAINNET_GENESIS;
  readonly commitment: 'finalized';
  readonly transactionHash: string;
  readonly transactionMessageHash: string;
  readonly draftBindingHash: string;
  readonly candidateTermsHash: string;
  readonly verificationStartedAt: string;
  readonly observedAt: string;
  readonly lifetime: Readonly<{
    readonly token: string;
    readonly tokenSha256: string;
    readonly semanticKind: 'verified_recent_blockhash';
    readonly mainnetRecency: 'verified_stable_finalized';
    readonly admittedAtBlockHeight: string;
    readonly providerLastValidBlockHeight: string;
    readonly firstObservedBlockHeight: string;
    readonly secondObservedBlockHeight: string;
    readonly remainingBlocksAtSecondObservation: string;
    readonly providerHeightAssociation: 'bound_not_rpc_derived';
  }>;
  readonly provenance: Readonly<{
    readonly rpcMethods: readonly [
      'getGenesisHash',
      'isBlockhashValid',
      'getBlockHeight',
      'isBlockhashValid',
      'getBlockHeight',
    ];
    readonly firstValidityContextSlot: string;
    readonly secondValidityContextSlot: string;
    readonly minimumContextSlots: Readonly<{
      readonly firstValidity: null;
      readonly firstBlockHeight: string;
      readonly secondValidity: string;
      readonly secondBlockHeight: string;
    }>;
    readonly rpcApiVersion: string | null;
    readonly retries: 0;
    readonly cacheUsed: false;
    readonly observationsStable: true;
    readonly digestSha256: string;
  }>;
  readonly assessment: Readonly<{
    readonly status: 'recent_blockhash_verified_but_incomplete';
    readonly clusterGenesis: 'verified';
    readonly structuralLifetimeBinding: 'verified';
    readonly admittedChainObservationBinding: 'verified';
    readonly blockhashValidity: 'verified_stable_finalized';
    readonly currentHeightWithinProviderBound: 'verified';
    readonly providerHeightAssociation: 'not_derived_from_rpc';
    readonly revalidationRequired: true;
    readonly lookupTableResolution: 'not_evaluated';
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

const MAX_JSON_BYTES = 32_768;
const MAX_CLOCK_MS = 8_639_999_999_999_999;
const U64_MAX = 18_446_744_073_709_551_615n;
const HASH = /^[0-9a-f]{64}$/;
const RAW_U64 = /^(?:0|[1-9][0-9]{0,19})$/;
const SAFE_API_VERSION = /^\d{1,5}\.\d{1,5}\.\d{1,5}(?:[-+][0-9A-Za-z.-]{1,32})?$/;
const ZERO_ADDRESS = '11111111111111111111111111111111';

const fail = (code: StockOrderLifetimeVerificationErrorCode): never => {
  throw new StockOrderLifetimeVerificationError(code);
};
const sha256 = (value: string): string => createHash('sha256').update(value).digest('hex');

function ownRecord(value: unknown, code: StockOrderLifetimeVerificationErrorCode,
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

function exactKeys(value: Record<string, unknown>, keys: readonly string[],
  code: StockOrderLifetimeVerificationErrorCode): void {
  if (Object.keys(value).length !== keys.length ||
      Object.keys(value).some(key => !keys.includes(key)) ||
      keys.some(key => !Object.hasOwn(value, key))) return fail(code);
}

function assertExactData(value: unknown, expected: unknown, depth = 0,
  budget: {remaining: number} = {remaining: 4_096}): void {
  budget.remaining -= 1;
  if (budget.remaining < 0 || depth > 16) return fail('LIFETIME_BINDING_MISMATCH');
  if (expected === null || typeof expected !== 'object') {
    if (value !== expected) return fail('LIFETIME_BINDING_MISMATCH');
    return;
  }
  if (Array.isArray(expected)) {
    if (!Array.isArray(value) || Object.getPrototypeOf(value) !== Array.prototype ||
        value.length !== expected.length) return fail('LIFETIME_BINDING_MISMATCH');
    const keys = Reflect.ownKeys(value);
    if (keys.length !== value.length + 1 || !keys.includes('length')) return fail('LIFETIME_BINDING_MISMATCH');
    for (let index = 0; index < expected.length; index++) {
      const descriptor = Object.getOwnPropertyDescriptor(value, String(index));
      if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) return fail('LIFETIME_BINDING_MISMATCH');
      assertExactData(descriptor.value, expected[index], depth + 1, budget);
    }
    return;
  }
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    return fail('LIFETIME_BINDING_MISMATCH');
  }
  const proto: unknown = Object.getPrototypeOf(value);
  if (proto !== Object.prototype && proto !== null) return fail('LIFETIME_BINDING_MISMATCH');
  const expectedKeys = Object.keys(expected);
  const actualKeys = Reflect.ownKeys(value);
  if (actualKeys.length !== expectedKeys.length || actualKeys.some(key => typeof key !== 'string' ||
      !expectedKeys.includes(key))) return fail('LIFETIME_BINDING_MISMATCH');
  for (const key of expectedKeys) {
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) return fail('LIFETIME_BINDING_MISMATCH');
    assertExactData(descriptor.value, (expected as Record<string, unknown>)[key], depth + 1, budget);
  }
}

function integer(value: unknown, minimum: number, maximum: number,
  code: StockOrderLifetimeVerificationErrorCode): number {
  if (!Number.isSafeInteger(value) || (value as number) < minimum || (value as number) > maximum) return fail(code);
  return value as number;
}

function u64(value: unknown, code: StockOrderLifetimeVerificationErrorCode): bigint {
  if (typeof value !== 'string' || RAW_U64.exec(value)?.[0] !== value) return fail(code);
  const parsed = BigInt(value);
  if (parsed < 0n || parsed > U64_MAX) return fail(code);
  return parsed;
}

function canonicalInstant(value: unknown): number {
  if (typeof value !== 'string' ||
      /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.exec(value)?.[0] !== value) {
    return fail('LIFETIME_DRAFT_INVALID');
  }
  const parsed = Date.parse(value);
  if (!Number.isFinite(parsed) || new Date(parsed).toISOString() !== value) return fail('LIFETIME_DRAFT_INVALID');
  return parsed;
}

function clock(now: () => number): number {
  let value: unknown;
  try { value = now(); } catch { return fail('LIFETIME_CONFIGURATION_INVALID'); }
  return integer(value, 0, MAX_CLOCK_MS, 'LIFETIME_CONFIGURATION_INVALID');
}

function canonicalLifetimeToken(value: unknown): string {
  try {
    if (typeof value !== 'string' || value.length < 32 || value.length > 44 || value === ZERO_ADDRESS ||
        address(value) !== value) return fail('LIFETIME_BINDING_MISMATCH');
    return value;
  } catch {
    return fail('LIFETIME_BINDING_MISMATCH');
  }
}

interface LifetimeSnapshot {
  readonly transactionHash: string;
  readonly transactionMessageHash: string;
  readonly draftBindingHash: string;
  readonly candidateTermsHash: string;
  readonly token: string;
  readonly admittedAtBlockHeight: bigint;
  readonly lastValidBlockHeight: bigint;
  readonly receivedAt: number;
  readonly notAfter: number;
}

function bindLifetimeInput(draft: StockOrderDraft, binding: StockDraftBinding,
  structuralReport: StockDraftStructuralInspection): LifetimeSnapshot {
  let canonical: StockDraftStructuralInspection;
  try { canonical = inspectStockDraftStructure(draft, binding); }
  catch (error) {
    if (error instanceof StockOrderDraftError) return fail('LIFETIME_BINDING_MISMATCH');
    return fail('LIFETIME_BINDING_MISMATCH');
  }

  // The report is caller-held, so compare every data property to a freshly
  // regenerated report without invoking accessors. Only canonical draft data is
  // copied into the async snapshot below.
  assertExactData(structuralReport, canonical);

  const report = ownRecord(structuralReport, 'LIFETIME_BINDING_MISMATCH', 18);
  exactKeys(report, ['schemaVersion', 'kind', 'transactionVersion', 'transactionSizeBytes', 'transactionHash',
    'transactionMessageHash', 'requiredSigner', 'signatures', 'header', 'lifetimeToken', 'staticAccountKeys',
    'addressTableLookups', 'accountIndexSpace', 'instructions', 'assessment', 'networkContext',
    'draftBindingHash', 'candidateTermsHash'], 'LIFETIME_BINDING_MISMATCH');
  if (report['schemaVersion'] !== 1 || report['kind'] !== 'unsigned_solana_v0_structure' ||
      report['transactionVersion'] !== 0 || report['transactionSizeBytes'] !== canonical.transactionSizeBytes ||
      report['transactionHash'] !== canonical.transactionHash ||
      report['transactionMessageHash'] !== canonical.transactionMessageHash ||
      report['networkContext'] !== 'solana:mainnet-beta' ||
      report['draftBindingHash'] !== canonical.draftBindingHash ||
      report['candidateTermsHash'] !== canonical.candidateTermsHash) return fail('LIFETIME_BINDING_MISMATCH');

  const lifetime = ownRecord(report['lifetimeToken'], 'LIFETIME_BINDING_MISMATCH', 4);
  exactKeys(lifetime, ['value', 'expectedUse', 'semanticKindVerified', 'mainnetRecencyVerified'],
    'LIFETIME_BINDING_MISMATCH');
  const token = canonicalLifetimeToken(lifetime['value']);
  if (token !== canonical.lifetimeToken.value || lifetime['expectedUse'] !== 'recent_blockhash' ||
      lifetime['semanticKindVerified'] !== false || lifetime['mainnetRecencyVerified'] !== false) {
    return fail('LIFETIME_BINDING_MISMATCH');
  }

  const assessment = ownRecord(report['assessment'], 'LIFETIME_BINDING_MISMATCH', 15);
  exactKeys(assessment, ['status', 'structuralIntegrity', 'requiredSignerBinding', 'staticAccountResolution',
    'lookupTableResolution', 'recentBlockhash', 'instructionSemantics', 'accountState', 'transactionTerms',
    'simulation', 'approvable', 'readyForSimulation', 'signingEnabled', 'broadcastEnabled',
    'financialOperationsEnabled'], 'LIFETIME_BINDING_MISMATCH');
  if (assessment['status'] !== 'structurally_valid_but_incomplete' ||
      assessment['structuralIntegrity'] !== 'verified' || assessment['requiredSignerBinding'] !== 'verified' ||
      assessment['recentBlockhash'] !== 'unverified' || assessment['instructionSemantics'] !== 'unverified' ||
      assessment['accountState'] !== 'unverified' || assessment['transactionTerms'] !== 'unverified' ||
      assessment['simulation'] !== 'not_run' || assessment['approvable'] !== false ||
      assessment['readyForSimulation'] !== false || assessment['signingEnabled'] !== false ||
      assessment['broadcastEnabled'] !== false || assessment['financialOperationsEnabled'] !== false) {
    return fail('LIFETIME_BINDING_MISMATCH');
  }

  const summary = draft.summary;
  if (summary.network !== 'solana:mainnet-beta' || summary.transactionHash !== canonical.transactionHash ||
      summary.transactionMessageHash !== canonical.transactionMessageHash || summary.bindingHash !== canonical.draftBindingHash ||
      summary.userApproval.candidateTermsHash !== canonical.candidateTermsHash || summary.lifetimeToken !== token ||
      summary.lastValidBlockHeight === null || summary.admittedAtBlockHeight === null ||
      summary.review.status !== 'unreviewed' || summary.review.blockhashVerified !== false ||
      summary.readyForSimulation !== false || summary.signingEnabled !== false || summary.executionEnabled !== false) {
    return fail('LIFETIME_DRAFT_INVALID');
  }
  const admitted = u64(summary.admittedAtBlockHeight, 'LIFETIME_DRAFT_INVALID');
  const lastValid = u64(summary.lastValidBlockHeight, 'LIFETIME_DRAFT_INVALID');
  if (admitted === 0n || lastValid <= admitted || lastValid - admitted > 150n) return fail('LIFETIME_DRAFT_INVALID');
  const receivedAt = canonicalInstant(summary.receivedAt);
  const notAfter = canonicalInstant(summary.notAfter);
  if (notAfter <= receivedAt) return fail('LIFETIME_DRAFT_INVALID');
  for (const value of [canonical.transactionHash, canonical.transactionMessageHash,
    canonical.draftBindingHash, canonical.candidateTermsHash]) {
    if (HASH.exec(value)?.[0] !== value) return fail('LIFETIME_BINDING_MISMATCH');
  }
  return Object.freeze({transactionHash: canonical.transactionHash,
    transactionMessageHash: canonical.transactionMessageHash, draftBindingHash: canonical.draftBindingHash,
    candidateTermsHash: canonical.candidateTermsHash, token, admittedAtBlockHeight: admitted,
    lastValidBlockHeight: lastValid, receivedAt, notAfter});
}

interface RpcDeadline {
  readonly controller: AbortController;
  readonly expired: Promise<never>;
}

interface RpcRequest {
  readonly jsonrpc: '2.0';
  readonly id: number;
  readonly method: 'getGenesisHash' | 'isBlockhashValid' | 'getBlockHeight';
  readonly params?: readonly unknown[];
}

class LifetimeRpc {
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

  async validity(token: string, minimumContextSlot: number | undefined,
    deadline: RpcDeadline): Promise<unknown> {
    const configuration: Record<string, unknown> = {commitment: 'finalized'};
    if (minimumContextSlot !== undefined) configuration['minContextSlot'] = minimumContextSlot;
    return this.#post({jsonrpc: '2.0', id: this.#nextId(), method: 'isBlockhashValid',
      params: [token, configuration]}, deadline);
  }

  async blockHeight(minimumContextSlot: number, deadline: RpcDeadline): Promise<unknown> {
    return this.#post({jsonrpc: '2.0', id: this.#nextId(), method: 'getBlockHeight',
      params: [{commitment: 'finalized', minContextSlot: minimumContextSlot}]}, deadline);
  }

  #nextId(): number {
    this.#requestId += 1;
    if (!Number.isSafeInteger(this.#requestId)) return fail('LIFETIME_RPC_UNAVAILABLE');
    return this.#requestId;
  }

  async #post(request: RpcRequest, deadline: RpcDeadline): Promise<unknown> {
    let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
    let response: Response | undefined;
    try {
      const pending = this.#fetch(this.#url, {
        method: 'POST', headers: {'content-type': 'application/json', accept: 'application/json'},
        redirect: 'error', signal: deadline.controller.signal, body: JSON.stringify(request),
      });
      void pending.then(late => {
        if (deadline.controller.signal.aborted) void late.body?.cancel().catch(() => undefined);
      }, () => undefined);
      response = await Promise.race([pending, deadline.expired]);
      if (deadline.controller.signal.aborted) return fail('LIFETIME_RPC_TIMEOUT');
      if (!(response instanceof Response)) return fail('LIFETIME_RPC_RESPONSE_INVALID');
      if (response.status !== 200) return fail('LIFETIME_RPC_UNAVAILABLE');
      if (response.redirected || response.url !== '' && response.url !== this.#url.href) {
        return fail('LIFETIME_RPC_RESPONSE_INVALID');
      }
      if (!/^application\/json(?:\s*;|$)/i.test(response.headers.get('content-type') ?? '') || !response.body) {
        return fail('LIFETIME_RPC_RESPONSE_INVALID');
      }
      const declared = response.headers.get('content-length');
      if (declared !== null && (declared.length > 20 || /^(?:0|[1-9][0-9]*)$/.exec(declared)?.[0] !== declared ||
          BigInt(declared) > BigInt(MAX_JSON_BYTES))) return fail('LIFETIME_RPC_RESPONSE_INVALID');
      reader = response.body.getReader();
      const chunks: Uint8Array[] = [];
      let length = 0;
      while (true) {
        const part = await Promise.race([reader.read(), deadline.expired]);
        if (part.done) break;
        length += part.value.byteLength;
        if (length > MAX_JSON_BYTES) return fail('LIFETIME_RPC_RESPONSE_INVALID');
        chunks.push(part.value);
      }
      let decoded: unknown;
      try { decoded = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(Buffer.concat(chunks))); }
      catch { return fail('LIFETIME_RPC_RESPONSE_INVALID'); }
      const envelope = ownRecord(decoded, 'LIFETIME_RPC_RESPONSE_INVALID', 3);
      exactKeys(envelope, ['jsonrpc', 'id', 'result'], 'LIFETIME_RPC_RESPONSE_INVALID');
      if (envelope['jsonrpc'] !== '2.0' || envelope['id'] !== request.id) {
        return fail('LIFETIME_RPC_RESPONSE_INVALID');
      }
      return envelope['result'];
    } catch (error) {
      if (deadline.controller.signal.aborted) return fail('LIFETIME_RPC_TIMEOUT');
      if (error instanceof StockOrderLifetimeVerificationError) throw error;
      return fail('LIFETIME_RPC_UNAVAILABLE');
    } finally {
      if (reader) void reader.cancel().catch(() => undefined);
      else if (response?.body) void response.body.cancel().catch(() => undefined);
    }
  }
}

interface ValidityObservation {
  readonly slot: number;
  readonly apiVersion: string | null;
  readonly valid: boolean;
}

function parseValidity(value: unknown): ValidityObservation {
  const result = ownRecord(value, 'LIFETIME_RPC_RESPONSE_INVALID', 2);
  exactKeys(result, ['context', 'value'], 'LIFETIME_RPC_RESPONSE_INVALID');
  if (typeof result['value'] !== 'boolean') return fail('LIFETIME_RPC_RESPONSE_INVALID');
  const context = ownRecord(result['context'], 'LIFETIME_RPC_RESPONSE_INVALID', 2);
  if (!Object.hasOwn(context, 'slot') || Object.keys(context).some(key => !['slot', 'apiVersion'].includes(key))) {
    return fail('LIFETIME_RPC_RESPONSE_INVALID');
  }
  const slot = integer(context['slot'], 1, Number.MAX_SAFE_INTEGER, 'LIFETIME_RPC_RESPONSE_INVALID');
  let apiVersion: string | null = null;
  if (Object.hasOwn(context, 'apiVersion')) {
    if (typeof context['apiVersion'] !== 'string' ||
        SAFE_API_VERSION.exec(context['apiVersion'])?.[0] !== context['apiVersion']) {
      return fail('LIFETIME_RPC_RESPONSE_INVALID');
    }
    apiVersion = context['apiVersion'];
  }
  return Object.freeze({slot, apiVersion, valid: result['value']});
}

function parseBlockHeight(value: unknown): bigint {
  const height = integer(value, 1, Number.MAX_SAFE_INTEGER, 'LIFETIME_RPC_RESPONSE_INVALID');
  return BigInt(height);
}

function exactOptionKeys(value: Record<string, unknown>): void {
  const allowed = ['rpcUrl', 'fetch', 'now', 'timeoutMs', 'maxConcurrentVerifications'];
  if (!Object.hasOwn(value, 'rpcUrl') || Object.keys(value).some(key => !allowed.includes(key))) {
    return fail('LIFETIME_CONFIGURATION_INVALID');
  }
}

/**
 * Read-only point-in-time verification of the exact recent blockhash and
 * provider height bound already captured by an opaque stock-order draft.
 * This class has no simulation, signing, sending or approval transition.
 */
export class SolanaMainnetStockOrderLifetimeVerifier {
  readonly #rpc!: LifetimeRpc;
  readonly #now!: () => number;
  readonly #timeoutMs!: number;
  readonly #maxConcurrent!: number;
  #active = 0;

  constructor(options: StockOrderLifetimeVerifierOptions) {
    try {
      const input = ownRecord(options, 'LIFETIME_CONFIGURATION_INVALID', 5);
      exactOptionKeys(input);
      if (typeof input['rpcUrl'] !== 'string' || input['rpcUrl'].length < 1 || input['rpcUrl'].length > 2_048 ||
          /[\u0000-\u0020\u007f]/.test(input['rpcUrl']) ||
          input['fetch'] !== undefined && typeof input['fetch'] !== 'function' ||
          input['now'] !== undefined && typeof input['now'] !== 'function') {
        return fail('LIFETIME_CONFIGURATION_INVALID');
      }
      const url = new URL(input['rpcUrl']);
      if (url.protocol !== 'https:' || url.username !== '' || url.password !== '' || url.hash !== '') {
        return fail('LIFETIME_CONFIGURATION_INVALID');
      }
      this.#timeoutMs = integer(input['timeoutMs'] ?? 6_000, 1, 8_000, 'LIFETIME_CONFIGURATION_INVALID');
      this.#maxConcurrent = integer(input['maxConcurrentVerifications'] ?? 2, 1, 8,
        'LIFETIME_CONFIGURATION_INVALID');
      this.#now = (input['now'] as (() => number) | undefined) ?? Date.now;
      this.#rpc = new LifetimeRpc(url, (input['fetch'] as typeof globalThis.fetch | undefined) ?? globalThis.fetch);
    } catch (error) {
      if (error instanceof StockOrderLifetimeVerificationError) throw error;
      return fail('LIFETIME_CONFIGURATION_INVALID');
    }
  }

  async verify(draft: StockOrderDraft, binding: StockDraftBinding,
    structuralReport: StockDraftStructuralInspection): Promise<VerifiedStockOrderLifetime> {
    // All values used after this point are local primitives copied before the
    // first await. Caller mutation cannot redirect or rewrite the review.
    const snapshot = bindLifetimeInput(draft, binding, structuralReport);
    const started = clock(this.#now);
    if (started < snapshot.receivedAt) return fail('LIFETIME_CONFIGURATION_INVALID');
    if (started >= snapshot.notAfter) return fail('LIFETIME_EXPIRED');
    if (this.#active >= this.#maxConcurrent) return fail('LIFETIME_CONCURRENCY_LIMITED');
    this.#active += 1;
    let controller: AbortController | undefined;
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      controller = new AbortController();
      let rejectExpiry: (reason: StockOrderLifetimeVerificationError) => void = () => undefined;
      const expired = new Promise<never>((_resolve, reject) => { rejectExpiry = reject; });
      try {
        timer = setTimeout(() => {
          controller?.abort();
          rejectExpiry(new StockOrderLifetimeVerificationError('LIFETIME_RPC_TIMEOUT'));
        }, this.#timeoutMs);
      } catch {
        return fail('LIFETIME_CONFIGURATION_INVALID');
      }
      const deadline: RpcDeadline = {controller, expired};
      const genesis = await this.#rpc.genesis(deadline);
      if (typeof genesis !== 'string') return fail('LIFETIME_RPC_RESPONSE_INVALID');
      if (genesis !== STOCK_DRAFT_MAINNET_GENESIS) return fail('LIFETIME_WRONG_NETWORK');

      const firstValidity = parseValidity(await this.#rpc.validity(snapshot.token, undefined, deadline));
      if (!firstValidity.valid) return fail('LIFETIME_BLOCKHASH_INVALID');
      const firstHeight = parseBlockHeight(await this.#rpc.blockHeight(firstValidity.slot, deadline));
      if (firstHeight < snapshot.admittedAtBlockHeight) return fail('LIFETIME_OBSERVATION_CHANGED');
      if (firstHeight >= snapshot.lastValidBlockHeight) return fail('LIFETIME_EXPIRED');

      const secondValidity = parseValidity(await this.#rpc.validity(snapshot.token, firstValidity.slot, deadline));
      if (!secondValidity.valid || secondValidity.slot < firstValidity.slot ||
          secondValidity.apiVersion !== firstValidity.apiVersion) return fail('LIFETIME_OBSERVATION_CHANGED');
      const secondHeight = parseBlockHeight(await this.#rpc.blockHeight(secondValidity.slot, deadline));
      if (secondHeight < firstHeight) return fail('LIFETIME_OBSERVATION_CHANGED');
      if (secondHeight >= snapshot.lastValidBlockHeight) return fail('LIFETIME_EXPIRED');

      const finished = clock(this.#now);
      if (finished < started) return fail('LIFETIME_CONFIGURATION_INVALID');
      if (finished - started >= this.#timeoutMs) return fail('LIFETIME_RPC_TIMEOUT');
      if (finished >= snapshot.notAfter) return fail('LIFETIME_EXPIRED');

      const methods = Object.freeze(['getGenesisHash', 'isBlockhashValid', 'getBlockHeight',
        'isBlockhashValid', 'getBlockHeight'] as const);
      const minimumContextSlots = Object.freeze({firstValidity: null, firstBlockHeight: String(firstValidity.slot),
        secondValidity: String(firstValidity.slot), secondBlockHeight: String(secondValidity.slot)});
      const digestInput = JSON.stringify({transactionHash: snapshot.transactionHash,
        transactionMessageHash: snapshot.transactionMessageHash, draftBindingHash: snapshot.draftBindingHash,
        candidateTermsHash: snapshot.candidateTermsHash, genesisHash: STOCK_DRAFT_MAINNET_GENESIS,
        commitment: 'finalized', token: snapshot.token,
        admittedAtBlockHeight: String(snapshot.admittedAtBlockHeight),
        providerLastValidBlockHeight: String(snapshot.lastValidBlockHeight),
        firstValiditySlot: firstValidity.slot, secondValiditySlot: secondValidity.slot,
        firstHeight: String(firstHeight), secondHeight: String(secondHeight),
        rpcApiVersion: secondValidity.apiVersion, methods});
      const lifetime = Object.freeze({token: snapshot.token, tokenSha256: sha256(snapshot.token),
        semanticKind: 'verified_recent_blockhash' as const, mainnetRecency: 'verified_stable_finalized' as const,
        admittedAtBlockHeight: String(snapshot.admittedAtBlockHeight),
        providerLastValidBlockHeight: String(snapshot.lastValidBlockHeight),
        firstObservedBlockHeight: String(firstHeight), secondObservedBlockHeight: String(secondHeight),
        remainingBlocksAtSecondObservation: String(snapshot.lastValidBlockHeight - secondHeight),
        providerHeightAssociation: 'bound_not_rpc_derived' as const});
      const provenance = Object.freeze({rpcMethods: methods,
        firstValidityContextSlot: String(firstValidity.slot),
        secondValidityContextSlot: String(secondValidity.slot), minimumContextSlots,
        rpcApiVersion: secondValidity.apiVersion, retries: 0 as const, cacheUsed: false as const,
        observationsStable: true as const, digestSha256: sha256(digestInput)});
      const assessment = Object.freeze({status: 'recent_blockhash_verified_but_incomplete' as const,
        clusterGenesis: 'verified' as const, structuralLifetimeBinding: 'verified' as const,
        admittedChainObservationBinding: 'verified' as const,
        blockhashValidity: 'verified_stable_finalized' as const,
        currentHeightWithinProviderBound: 'verified' as const,
        providerHeightAssociation: 'not_derived_from_rpc' as const, revalidationRequired: true as const,
        lookupTableResolution: 'not_evaluated' as const, programOwnership: 'unverified' as const,
        instructionSemantics: 'unverified' as const, accountState: 'unverified' as const,
        transactionTerms: 'unverified' as const, simulation: 'not_run' as const,
        approvable: false as const, readyForSimulation: false as const, signingEnabled: false as const,
        broadcastEnabled: false as const, financialOperationsEnabled: false as const});
      return Object.freeze({schemaVersion: 1, kind: 'solana_recent_blockhash_lifetime_evidence',
        network: 'solana:mainnet-beta', genesisHash: STOCK_DRAFT_MAINNET_GENESIS, commitment: 'finalized',
        transactionHash: snapshot.transactionHash, transactionMessageHash: snapshot.transactionMessageHash,
        draftBindingHash: snapshot.draftBindingHash, candidateTermsHash: snapshot.candidateTermsHash,
        verificationStartedAt: new Date(started).toISOString(), observedAt: new Date(finished).toISOString(),
        lifetime, provenance, assessment});
    } catch (error) {
      if (controller?.signal.aborted) return fail('LIFETIME_RPC_TIMEOUT');
      if (error instanceof StockOrderLifetimeVerificationError) throw error;
      return fail('LIFETIME_RPC_UNAVAILABLE');
    } finally {
      // Runtime timer and abort hooks are outside this verifier's trust
      // boundary. A cleanup exception must never strand the concurrency slot.
      try {
        if (timer !== undefined) clearTimeout(timer);
      } catch {
        // Cleanup was attempted; there is no safe recovery through this API.
      } finally {
        try { controller?.abort(); } catch { /* keep releasing the slot */ }
        this.#active -= 1;
      }
    }
  }
}
