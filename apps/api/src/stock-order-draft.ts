import { createHash } from 'node:crypto';
import { inspect } from 'node:util';
import { address, getAddressEncoder, isOffCurveAddress } from '@solana/kit';
import { parseRawAmount } from '@trimmy/domain';
import { findStockTradingAsset } from './stock-trading-catalog.js';
import { JUPITER_QUOTE_ASSETS } from './jupiter-quote-reader.js';
import { validateStockEstimateInput } from './stock-estimates.js';
import type { StockEstimate, StockEstimateInput } from './stock-estimates.js';
import { inspectUnsignedV0TransactionStructure, StockTransactionStructureError } from './stock-order-transaction-inspector.js';
import type { UnsignedV0TransactionStructure } from './stock-order-transaction-inspector.js';

export const STOCK_DRAFT_MAINNET_GENESIS = '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d';
export type StockOrderDraftErrorCode = 'STOCK_DRAFT_CONTEXT_INVALID' | 'STOCK_DRAFT_PROVIDER_ERROR' |
  'STOCK_DRAFT_TERMS_MISMATCH' | 'STOCK_DRAFT_TRANSACTION_INVALID' | 'STOCK_DRAFT_SIGNER_MISMATCH' |
  'STOCK_DRAFT_VALIDITY_INVALID' | 'STOCK_DRAFT_EXPIRED' | 'STOCK_DRAFT_BINDING_MISMATCH' | 'STOCK_DRAFT_REVIEW_REQUIRED';
export class StockOrderDraftError extends Error {
  constructor(readonly code: StockOrderDraftErrorCode) {
    super('The stock order draft cannot proceed.'); this.name = 'StockOrderDraftError';
  }
}
function fail(code: StockOrderDraftErrorCode): never { throw new StockOrderDraftError(code); }
const hash = (bytes: Uint8Array | string) => createHash('sha256').update(bytes).digest('hex');

export interface StockDraftChainObservation {
  readonly genesisHash: typeof STOCK_DRAFT_MAINNET_GENESIS;
  readonly blockHeight: string;
  readonly observedAt: string;
}
/** Trusted process dependencies captured with the draft. They must be backed by
 * the server clock and a mainnet-bound reader, never request fields. */
export interface StockDraftValidityAuthority {
  readonly now: () => number;
  readonly readChainObservation?: () => Promise<StockDraftChainObservation>;
}
/** Trusted server context, NOT a request-body identity or proof of ownership.
 * Future composition must authenticate the UUID and verify that its linked wallet
 * controls this exact taker. This offline parser performs neither verification.
 */
export interface StockOrderDraftContext {
  readonly authenticatedUserId: string;
  readonly verifiedTaker: string;
  readonly expected: StockEstimate;
  readonly requestStartedAt: string;
  readonly chainObservation?: StockDraftChainObservation;
  readonly validityAuthority: StockDraftValidityAuthority;
}
export interface StockDraftBinding {
  readonly authenticatedUserId: string;
  readonly verifiedTaker: string;
  readonly requestId: string;
  readonly transactionMessageHash: string;
  readonly bindingHash: string;
}
export interface StockDraftLookup {
  readonly address: string;
  readonly writableIndexes: readonly number[];
  readonly readonlyIndexes: readonly number[];
}
export interface StockDraftSummary {
  readonly schemaVersion: 2;
  readonly kind: 'stock_order_draft';
  readonly network: 'solana:mainnet-beta';
  readonly userId: string;
  readonly taker: string;
  readonly assetId: StockEstimateInput['assetId'];
  readonly variantMint: string;
  readonly side: 'buy' | 'sell';
  readonly input: StockEstimate['input'];
  readonly output: StockEstimate['output'];
  readonly slippageBps: number;
  readonly swapFee: StockEstimate['swapFee'];
  readonly router: StockEstimate['router'];
  readonly orderMode: 'manual';
  readonly referenceEstimate: {
    readonly output: StockEstimate['output'];
    readonly swapFee: StockEstimate['swapFee'];
    readonly router: StockEstimate['router'];
    readonly receivedAt: string;
    readonly refreshAfter: string;
    readonly providerExpiresAt: string | null;
  };
  readonly approvalPolicy: {
    readonly minimumOutputAmountRaw: string;
    readonly maximumFeeBasisPoints: number;
  };
  readonly termChanges: readonly {
    readonly field: 'output.estimatedAmountRaw' | 'output.quotedMinimumAmountRaw' | 'swapFee.basisPoints' |
      'swapFee.mint' | 'router' | 'providerExpiresAt';
    readonly before: string | number | null;
    readonly after: string | number | null;
  }[];
  readonly userApproval: {
    readonly status: 'required';
    readonly reason: 'fresh_provider_order';
    readonly candidateTermsHash: string;
  };
  readonly requestId: string;
  readonly requestStartedAt: string;
  readonly receivedAt: string;
  /** Conservative cutoff for this newly returned order. */
  readonly notAfter: string;
  readonly providerExpiresAt: string | null;
  readonly lastValidBlockHeight: string | null;
  readonly admittedAtBlockHeight: string | null;
  /** This decoded token is not yet verified to be a recent mainnet blockhash. */
  readonly lifetimeToken: string;
  readonly transactionMessageHash: string;
  readonly transactionHash: string;
  readonly bindingHash: string;
  readonly transactionVersion: 0;
  readonly transactionSizeBytes: number;
  readonly staticAccounts: readonly string[];
  readonly lookupTables: readonly StockDraftLookup[];
  readonly programAddresses: readonly (string | null)[];
  readonly instructionCount: number;
  readonly review: {
    readonly status: 'unreviewed';
    readonly addressResolution: 'lookup_tables_required' | 'static_addresses_only';
    readonly accountState: 'required';
    readonly programSemantics: 'required';
    readonly instructionTermsVerified: false;
    readonly blockhashVerified: false;
    readonly simulation: 'not_run';
  };
  readonly readyForSimulation: false;
  readonly signingEnabled: false;
  readonly executionEnabled: false;
  readonly eligibility: 'unverified';
}
/** Opaque in-memory draft. Serialization/log inspection omits raw transaction bytes. */
export interface StockOrderDraft { readonly summary: StockDraftSummary }
const stored = new WeakMap<StockOrderDraft, {readonly bytes: Uint8Array; readonly authority: StockDraftValidityAuthority}>();
export interface StockDraftStructuralInspection extends UnsignedV0TransactionStructure {
  readonly networkContext: 'solana:mainnet-beta';
  readonly draftBindingHash: string;
  readonly candidateTermsHash: string;
}

function record(value: unknown, code: StockOrderDraftErrorCode): Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) fail(code);
  const proto: unknown = Object.getPrototypeOf(value);
  if (proto !== Object.prototype && proto !== null) fail(code);
  const result: Record<string, unknown> = {};
  const keys = Reflect.ownKeys(value);
  if (keys.length > 100) fail(code);
  for (const key of keys) {
    if (typeof key !== 'string') fail(code);
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) fail(code);
    Object.defineProperty(result, key, {value: descriptor.value, enumerable: true});
  }
  return result;
}
function instant(value: unknown, code: StockOrderDraftErrorCode): number {
  if (typeof value !== 'string' || /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,3})?Z$/.exec(value)?.[0] !== value) fail(code);
  const parsed = Date.parse(value);
  const canonical = value.includes('.') ? value.replace(/\.(\d{1,3})Z$/, (_m, f: string) => `.${f.padEnd(3, '0')}Z`) : value.replace('Z', '.000Z');
  if (!Number.isFinite(parsed) || new Date(parsed).toISOString() !== canonical) fail(code);
  return parsed;
}
function trustedAuthority(value: unknown): StockDraftValidityAuthority {
  const data = record(value, 'STOCK_DRAFT_CONTEXT_INVALID');
  if (Object.keys(data).some(key => !['now', 'readChainObservation'].includes(key)) ||
      typeof data['now'] !== 'function' ||
      data['readChainObservation'] !== undefined && typeof data['readChainObservation'] !== 'function') {
    fail('STOCK_DRAFT_CONTEXT_INVALID');
  }
  return Object.freeze({
    now: data['now'] as () => number,
    ...(data['readChainObservation'] === undefined ? {} : {
      readChainObservation: data['readChainObservation'] as () => Promise<StockDraftChainObservation>,
    }),
  });
}
function authorityNow(authority: StockDraftValidityAuthority, code: StockOrderDraftErrorCode): number {
  let value: unknown;
  try { value = authority.now(); } catch { return fail(code); }
  if (!Number.isSafeInteger(value) || (value as number) < 0 || (value as number) > 8_639_999_999_990_000) fail(code);
  return value as number;
}
function raw(value: unknown, code: StockOrderDraftErrorCode): string {
  try { if (typeof value !== 'string' || parseRawAmount(value) <= 0n) fail(code); return value; }
  catch { return fail(code); }
}
function userId(value: unknown): string {
  if (typeof value !== 'string' || /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.exec(value)?.[0] !== value) fail('STOCK_DRAFT_CONTEXT_INVALID');
  return value;
}
function taker(value: unknown): string {
  try {
    if (typeof value !== 'string' || value.length > 44) fail('STOCK_DRAFT_CONTEXT_INVALID');
    const key = address(value);
    if (isOffCurveAddress(key) || getAddressEncoder().encode(key).every(byte => byte === 0)) fail('STOCK_DRAFT_CONTEXT_INVALID');
    return key;
  } catch { return fail('STOCK_DRAFT_CONTEXT_INVALID'); }
}
function identifier(value: unknown): string {
  if (typeof value !== 'string' || /^[A-Za-z0-9._:-]{1,128}$/.exec(value)?.[0] !== value) fail('STOCK_DRAFT_PROVIDER_ERROR');
  return value;
}
function observation(value: StockDraftChainObservation | undefined, now: number): bigint {
  const data = record(value, 'STOCK_DRAFT_VALIDITY_INVALID');
  if (data['genesisHash'] !== STOCK_DRAFT_MAINNET_GENESIS) fail('STOCK_DRAFT_VALIDITY_INVALID');
  const at = instant(data['observedAt'], 'STOCK_DRAFT_VALIDITY_INVALID');
  if (at > now || now - at > 10_000) fail('STOCK_DRAFT_VALIDITY_INVALID');
  return BigInt(raw(data['blockHeight'], 'STOCK_DRAFT_VALIDITY_INVALID'));
}
function expectedTerms(input: StockEstimate, requestStarted: number): StockEstimate {
  const q = record(input, 'STOCK_DRAFT_CONTEXT_INVALID');
  const from = record(q['input'], 'STOCK_DRAFT_CONTEXT_INVALID');
  const to = record(q['output'], 'STOCK_DRAFT_CONTEXT_INVALID');
  const fee = record(q['swapFee'], 'STOCK_DRAFT_CONTEXT_INVALID');
  if (Object.keys(from).some(key => !['symbol', 'mint', 'decimals', 'amountRaw'].includes(key)) ||
      Object.keys(to).some(key => !['symbol', 'mint', 'decimals', 'estimatedAmountRaw', 'quotedMinimumAmountRaw'].includes(key)) ||
      Object.keys(fee).some(key => !['basisPoints', 'mint'].includes(key))) fail('STOCK_DRAFT_CONTEXT_INVALID');
  try { validateStockEstimateInput({assetId: q['assetId'], variantMint: q['variantMint'], side: q['side'], amountRaw: from['amountRaw']} as StockEstimateInput); }
  catch { fail('STOCK_DRAFT_CONTEXT_INVALID'); }
  const buying = q['side'] === 'buy';
  const stock = findStockTradingAsset(q['assetId'], q['variantMint'])!;
  const source = buying ? JUPITER_QUOTE_ASSETS.USDC : stock;
  const target = buying ? stock : JUPITER_QUOTE_ASSETS.USDC;
  if (q['schemaVersion'] !== 1 || q['kind'] !== 'indicative' || q['provider'] !== 'jupiter-swap-v2' || q['network'] !== 'solana:mainnet-beta' ||
      q['executionEnabled'] !== false || q['executable'] !== false || q['eligibility'] !== 'unverified' || q['walletChecked'] !== false ||
      q['networkFees'] !== null || q['amountUnits'] !== 'raw_token_units' ||
      from['mint'] !== source.mint || from['symbol'] !== source.symbol || from['decimals'] !== source.decimals ||
      to['mint'] !== target.mint || to['symbol'] !== target.symbol || to['decimals'] !== target.decimals) fail('STOCK_DRAFT_CONTEXT_INVALID');
  const amount = BigInt(raw(to['estimatedAmountRaw'], 'STOCK_DRAFT_CONTEXT_INVALID'));
  const minimum = BigInt(raw(to['quotedMinimumAmountRaw'], 'STOCK_DRAFT_CONTEXT_INVALID'));
  const slip = q['slippageBps']; const bps = fee['basisPoints'];
  if (typeof slip !== 'number' || !Number.isInteger(slip) || slip < 0 || slip > 10_000 ||
      typeof bps !== 'number' || !Number.isInteger(bps) || bps < 0 || bps > 10_000 ||
      (fee['mint'] !== source.mint && fee['mint'] !== target.mint) || minimum > amount ||
      minimum < amount * BigInt(10_000 - slip) / 10_000n ||
      !['metis', 'jupiterz', 'dflow', 'okx'].includes(q['router'] as string)) fail('STOCK_DRAFT_CONTEXT_INVALID');
  const requested = instant(q['requestedAt'], 'STOCK_DRAFT_CONTEXT_INVALID');
  const quoted = instant(q['receivedAt'], 'STOCK_DRAFT_CONTEXT_INVALID');
  const refresh = instant(q['refreshAfter'], 'STOCK_DRAFT_CONTEXT_INVALID');
  if (quoted < requested || requestStarted < quoted || refresh <= quoted || refresh - requested > 10_000) fail('STOCK_DRAFT_CONTEXT_INVALID');
  if (requestStarted >= refresh) fail('STOCK_DRAFT_EXPIRED');
  if (q['providerExpiresAt'] !== null && instant(q['providerExpiresAt'], 'STOCK_DRAFT_CONTEXT_INVALID') < refresh) fail('STOCK_DRAFT_CONTEXT_INVALID');
  // Fresh detached objects: a caller mutating its estimate cannot rewrite a bound draft.
  return Object.freeze({...input, input: Object.freeze({...input.input}), output: Object.freeze({...input.output}), swapFee: Object.freeze({...input.swapFee})});
}

/** Parse/bind only. Provider quote metadata is NOT proof of instruction semantics. */
export function bindStockOrderDraft(payload: unknown, context: StockOrderDraftContext): StockOrderDraft {
  try {
    const ctx = record(context, 'STOCK_DRAFT_CONTEXT_INVALID');
    if (Object.keys(ctx).some(key => !['authenticatedUserId', 'verifiedTaker', 'expected', 'requestStartedAt',
      'chainObservation', 'validityAuthority'].includes(key))) fail('STOCK_DRAFT_CONTEXT_INVALID');
    const owner = userId(ctx['authenticatedUserId']); const wallet = taker(ctx['verifiedTaker']);
    const authority = trustedAuthority(ctx['validityAuthority']);
    const received = authorityNow(authority, 'STOCK_DRAFT_CONTEXT_INVALID');
    const started = instant(ctx['requestStartedAt'], 'STOCK_DRAFT_CONTEXT_INVALID');
    const expected = expectedTerms(ctx['expected'] as StockEstimate, started);
    if (started > received || received - started > 8000) fail('STOCK_DRAFT_CONTEXT_INVALID');
    const data = record(payload, 'STOCK_DRAFT_PROVIDER_ERROR');
    if (['error', 'errorCode', 'errorMessage'].some(key => Object.hasOwn(data, key))) fail('STOCK_DRAFT_PROVIDER_ERROR');
    const requestId = identifier(data['requestId']);
    if (data['taker'] !== wallet) fail('STOCK_DRAFT_SIGNER_MISMATCH');
    for (const [key, value] of Object.entries({inputMint: expected.input.mint, outputMint: expected.output.mint,
      inAmount: expected.input.amountRaw, swapMode: 'ExactIn', slippageBps: expected.slippageBps, mode: 'manual'})) {
      if (data[key] !== value) fail('STOCK_DRAFT_TERMS_MISMATCH');
    }
    const outAmount = raw(data['outAmount'], 'STOCK_DRAFT_TERMS_MISMATCH');
    const minimumAmount = raw(data['otherAmountThreshold'], 'STOCK_DRAFT_TERMS_MISMATCH');
    const output = BigInt(outAmount); const minimum = BigInt(minimumAmount);
    if (minimum > output || minimum < output * BigInt(10_000 - expected.slippageBps) / 10_000n ||
        minimum < BigInt(expected.output.quotedMinimumAmountRaw)) fail('STOCK_DRAFT_TERMS_MISMATCH');
    const feeBps = data['feeBps']; const feeMint = data['feeMint']; const router = data['router'];
    if (typeof feeBps !== 'number' || !Number.isInteger(feeBps) || feeBps < 0 || feeBps > expected.swapFee.basisPoints ||
        feeMint !== expected.input.mint && feeMint !== expected.output.mint ||
        typeof router !== 'string' || !['metis', 'jupiterz', 'dflow', 'okx'].includes(router)) fail('STOCK_DRAFT_TERMS_MISMATCH');
    // These paths introduce different recipients, signers or fee routing; review separately.
    for (const key of ['receiver', 'payer', 'referralAccount']) if (data[key] !== undefined && data[key] !== null) fail('STOCK_DRAFT_TERMS_MISMATCH');
    if (data['gasless'] !== undefined && data['gasless'] !== false) fail('STOCK_DRAFT_SIGNER_MISMATCH');
    for (const key of ['signatureFeePayer', 'prioritizationFeePayer', 'rentFeePayer']) {
      if (data[key] !== undefined && data[key] !== null && data[key] !== wallet) fail('STOCK_DRAFT_SIGNER_MISMATCH');
    }
    let expires: number | null = null;
    if (data['expireAt'] !== undefined && data['expireAt'] !== null) expires = instant(data['expireAt'], 'STOCK_DRAFT_VALIDITY_INVALID');
    if (expires !== null && (expires <= received || expires > received + 120_000)) fail('STOCK_DRAFT_VALIDITY_INVALID');
    const admittedHeight = ctx['chainObservation'] === undefined ? null : observation(context.chainObservation, received);
    let lastHeight: string | null = null;
    if (data['lastValidBlockHeight'] !== undefined && data['lastValidBlockHeight'] !== null) {
      lastHeight = raw(data['lastValidBlockHeight'], 'STOCK_DRAFT_VALIDITY_INVALID');
      if (admittedHeight === null || authority.readChainObservation === undefined) fail('STOCK_DRAFT_VALIDITY_INVALID');
      // Conservative local admission cap, not a derivation of blockhash lifetime.
      if (BigInt(lastHeight) <= admittedHeight || BigInt(lastHeight) - admittedHeight > 150n) fail('STOCK_DRAFT_VALIDITY_INVALID');
    }
    if (expires === null && lastHeight === null) fail('STOCK_DRAFT_VALIDITY_INVALID');
    const base64 = data['transaction'];
    if (typeof base64 !== 'string' || base64.length === 0 || base64.length > 1644 ||
        !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(base64)) fail('STOCK_DRAFT_TRANSACTION_INVALID');
    const wire = Buffer.from(base64, 'base64');
    if (wire.length > 1232 || wire.toString('base64') !== base64) fail('STOCK_DRAFT_TRANSACTION_INVALID');
    let structure: UnsignedV0TransactionStructure;
    try {
      structure = inspectUnsignedV0TransactionStructure(wire, wallet);
    } catch (error) {
      if (error instanceof StockTransactionStructureError && error.code === 'SIGNER_MISMATCH') {
        return fail('STOCK_DRAFT_SIGNER_MISMATCH');
      }
      return fail('STOCK_DRAFT_TRANSACTION_INVALID');
    }
    const providerExpiresAt = expires === null ? null : new Date(expires).toISOString();
    const actualOutput = Object.freeze({...expected.output, estimatedAmountRaw: outAmount, quotedMinimumAmountRaw: minimumAmount});
    const actualFee = Object.freeze({basisPoints: feeBps, mint: feeMint as string});
    const actualRouter = router as StockEstimate['router'];
    const termChanges: Array<StockDraftSummary['termChanges'][number]> = [];
    const changed = (field: StockDraftSummary['termChanges'][number]['field'], before: string | number | null,
      after: string | number | null) => { if (before !== after) termChanges.push(Object.freeze({field, before, after})); };
    changed('output.estimatedAmountRaw', expected.output.estimatedAmountRaw, outAmount);
    changed('output.quotedMinimumAmountRaw', expected.output.quotedMinimumAmountRaw, minimumAmount);
    changed('swapFee.basisPoints', expected.swapFee.basisPoints, feeBps);
    changed('swapFee.mint', expected.swapFee.mint, feeMint as string);
    changed('router', expected.router, actualRouter);
    changed('providerExpiresAt', expected.providerExpiresAt, providerExpiresAt);
    const transactionMessageHash = structure.transactionMessageHash; const transactionHash = structure.transactionHash;
    const approvalPolicy = Object.freeze({minimumOutputAmountRaw: expected.output.quotedMinimumAmountRaw,
      maximumFeeBasisPoints: expected.swapFee.basisPoints});
    const requestStartedAt = new Date(started).toISOString(); const receivedAt = new Date(received).toISOString();
    const notAfter = new Date(Math.min(received + 10_000, expires ?? Infinity)).toISOString();
    const admittedAtBlockHeight = admittedHeight?.toString() ?? null;
    const candidateTermsHash = hash(JSON.stringify({
      userId: owner, taker: wallet, requestId, assetId: expected.assetId, variantMint: expected.variantMint, side: expected.side,
      input: expected.input, output: actualOutput, slippageBps: expected.slippageBps, swapFee: actualFee, router: actualRouter,
      orderMode: 'manual', approvalPolicy, requestStartedAt, receivedAt, notAfter, providerExpiresAt,
      lastValidBlockHeight: lastHeight, admittedAtBlockHeight,
      lifetimeToken: structure.lifetimeToken.value, transactionMessageHash, transactionHash,
    }));
    const withoutHash = {
      schemaVersion: 2 as const, kind: 'stock_order_draft' as const, network: 'solana:mainnet-beta' as const, userId: owner, taker: wallet,
      assetId: expected.assetId, variantMint: expected.variantMint, side: expected.side, input: expected.input, output: actualOutput,
      slippageBps: expected.slippageBps, swapFee: actualFee, router: actualRouter, orderMode: 'manual' as const,
      referenceEstimate: Object.freeze({output: expected.output, swapFee: expected.swapFee, router: expected.router,
        receivedAt: expected.receivedAt, refreshAfter: expected.refreshAfter, providerExpiresAt: expected.providerExpiresAt}),
      approvalPolicy,
      termChanges: Object.freeze(termChanges),
      userApproval: Object.freeze({status: 'required' as const, reason: 'fresh_provider_order' as const, candidateTermsHash}),
      requestId, requestStartedAt, receivedAt, notAfter,
      providerExpiresAt, lastValidBlockHeight: lastHeight,
      admittedAtBlockHeight,
      lifetimeToken: structure.lifetimeToken.value, transactionMessageHash, transactionHash,
      transactionVersion: 0 as const, transactionSizeBytes: structure.transactionSizeBytes,
      staticAccounts: structure.staticAccountKeys,
      lookupTables: Object.freeze(structure.addressTableLookups.map(table => Object.freeze({address: table.lookupTableAddress,
        writableIndexes: Object.freeze([...table.writableIndexes]), readonlyIndexes: Object.freeze([...table.readonlyIndexes])}))),
      programAddresses: Object.freeze(structure.instructions.map(ix => ix.program.kind === 'static' ? ix.program.address : null)),
      instructionCount: structure.instructions.length,
      review: Object.freeze({status: 'unreviewed' as const,
        addressResolution: structure.addressTableLookups.length ? 'lookup_tables_required' as const : 'static_addresses_only' as const,
        accountState: 'required' as const, programSemantics: 'required' as const, instructionTermsVerified: false as const, blockhashVerified: false as const, simulation: 'not_run' as const}),
      readyForSimulation: false as const, signingEnabled: false as const, executionEnabled: false as const, eligibility: 'unverified' as const,
    };
    const summary: StockDraftSummary = Object.freeze({...withoutHash, bindingHash: hash(JSON.stringify(withoutHash))});
    const draft = Object.freeze({summary, [inspect.custom]: () => ({kind: 'stock_order_draft', status: 'unreviewed', transactionMessageHash: summary.transactionMessageHash}),
      toJSON: () => ({kind: 'stock_order_draft', status: 'unreviewed', transactionMessageHash: summary.transactionMessageHash})});
    stored.set(draft, Object.freeze({bytes: Uint8Array.from(wire), authority})); return draft;
  } catch (error) {
    if (error instanceof StockOrderDraftError) throw error;
    return fail('STOCK_DRAFT_CONTEXT_INVALID');
  }
}

function boundState(draft: StockOrderDraft, binding: StockDraftBinding):
  {readonly bytes: Uint8Array; readonly authority: StockDraftValidityAuthority} {
  const state = stored.get(draft);
  if (state === undefined) fail('STOCK_DRAFT_BINDING_MISMATCH');
  try {
    const data = record(binding, 'STOCK_DRAFT_BINDING_MISMATCH');
    if (Object.keys(data).some(key => !['authenticatedUserId', 'verifiedTaker', 'requestId',
      'transactionMessageHash', 'bindingHash'].includes(key))) fail('STOCK_DRAFT_BINDING_MISMATCH');
    const s = draft.summary;
    if (data['authenticatedUserId'] !== s.userId || data['verifiedTaker'] !== s.taker || data['requestId'] !== s.requestId ||
        data['transactionMessageHash'] !== s.transactionMessageHash || data['bindingHash'] !== s.bindingHash) fail('STOCK_DRAFT_BINDING_MISMATCH');
    return state;
  } catch (error) {
    if (error instanceof StockOrderDraftError) throw error;
    return fail('STOCK_DRAFT_BINDING_MISMATCH');
  }
}

/** Rechecks account, exact draft identity and both expiry constraints using only
 * the server authority captured when the draft was created. */
export async function assertStockDraftBinding(draft: StockOrderDraft, binding: StockDraftBinding): Promise<void> {
  const state = boundState(draft, binding);
  try {
    const s = draft.summary;
    let now = authorityNow(state.authority, 'STOCK_DRAFT_VALIDITY_INVALID');
    if (now < Date.parse(s.receivedAt) || now >= Date.parse(s.notAfter)) fail('STOCK_DRAFT_EXPIRED');
    if (s.lastValidBlockHeight !== null) {
      if (state.authority.readChainObservation === undefined) fail('STOCK_DRAFT_VALIDITY_INVALID');
      const current = await state.authority.readChainObservation();
      now = authorityNow(state.authority, 'STOCK_DRAFT_VALIDITY_INVALID');
      if (now < Date.parse(s.receivedAt) || now >= Date.parse(s.notAfter)) fail('STOCK_DRAFT_EXPIRED');
      const height = observation(current, now);
      if (s.admittedAtBlockHeight === null || height < BigInt(s.admittedAtBlockHeight)) fail('STOCK_DRAFT_VALIDITY_INVALID');
      if (height >= BigInt(s.lastValidBlockHeight)) fail('STOCK_DRAFT_EXPIRED');
    }
  } catch (error) {
    if (error instanceof StockOrderDraftError) throw error;
    return fail('STOCK_DRAFT_VALIDITY_INVALID');
  }
}

function arraysEqual<T>(left: readonly T[], right: readonly T[]): boolean {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}

/**
 * Re-decodes only the privately retained bytes and returns a redacted structural
 * report. It intentionally performs no clock, RPC, lookup-table or account read.
 */
export function inspectStockDraftStructure(draft: StockOrderDraft,
  binding: StockDraftBinding): StockDraftStructuralInspection {
  const state = boundState(draft, binding);
  const summary = draft.summary;
  let structure: UnsignedV0TransactionStructure;
  try { structure = inspectUnsignedV0TransactionStructure(state.bytes, summary.taker); }
  catch (error) {
    if (error instanceof StockTransactionStructureError && error.code === 'SIGNER_MISMATCH') {
      return fail('STOCK_DRAFT_SIGNER_MISMATCH');
    }
    return fail('STOCK_DRAFT_TRANSACTION_INVALID');
  }
  const programAddresses = structure.instructions.map(instruction =>
    instruction.program.kind === 'static' ? instruction.program.address : null);
  const lookupsMatch = structure.addressTableLookups.length === summary.lookupTables.length &&
    structure.addressTableLookups.every((table, index) => {
      const expected = summary.lookupTables[index];
      return expected !== undefined && table.lookupTableAddress === expected.address &&
        arraysEqual(table.writableIndexes, expected.writableIndexes) &&
        arraysEqual(table.readonlyIndexes, expected.readonlyIndexes);
    });
  if (structure.transactionVersion !== summary.transactionVersion ||
      structure.transactionSizeBytes !== summary.transactionSizeBytes ||
      structure.transactionHash !== summary.transactionHash ||
      structure.transactionMessageHash !== summary.transactionMessageHash ||
      structure.requiredSigner.address !== summary.taker || structure.lifetimeToken.value !== summary.lifetimeToken ||
      !arraysEqual(structure.staticAccountKeys, summary.staticAccounts) || !lookupsMatch ||
      !arraysEqual(programAddresses, summary.programAddresses) || structure.instructions.length !== summary.instructionCount ||
      summary.readyForSimulation !== false || summary.signingEnabled !== false || summary.executionEnabled !== false) {
    fail('STOCK_DRAFT_BINDING_MISMATCH');
  }
  return Object.freeze({...structure, networkContext: 'solana:mainnet-beta', draftBindingHash: summary.bindingHash,
    candidateTermsHash: summary.userApproval.candidateTermsHash});
}

/** Byte copy for a later internal reviewer only; no HTTP serializer exposes it. */
export async function copyStockDraftBytesForReview(draft: StockOrderDraft, binding: StockDraftBinding): Promise<Uint8Array> {
  await assertStockDraftBinding(draft, binding); return Uint8Array.from(stored.get(draft)!.bytes);
}
/** Without reconciliation evidence there is still no transition to reviewed,
 * even for all-static messages. The evidence-bearing path is
 * {@link admitStockDraftForSimulation}. */
export function assertStockDraftReadyForSimulation(draft: StockOrderDraft): never {
  if (!stored.has(draft)) fail('STOCK_DRAFT_BINDING_MISMATCH');
  return fail('STOCK_DRAFT_REVIEW_REQUIRED');
}

/** The exact gate 6 outcome that may admit a draft to the simulation boundary. */
export interface StockDraftSimulationAdmission {
  readonly transactionMessageHash: string;
  readonly draftBindingHash: string;
  readonly candidateTermsHash: string;
  readonly status: 'terms_reconciled_but_unsimulated';
  readonly readyForSimulation: true;
}

/**
 * Byte copy for the isolated simulation boundary only. It requires the exact
 * draft identity, the caller's binding and a reconciliation admission whose
 * hashes match this draft, and it re-checks both expiry constraints through the
 * captured server authority. It still enables no signing or sending.
 */
export async function admitStockDraftForSimulation(draft: StockOrderDraft, binding: StockDraftBinding,
  admission: StockDraftSimulationAdmission): Promise<Uint8Array> {
  if (!stored.has(draft)) fail('STOCK_DRAFT_BINDING_MISMATCH');
  const summary = draft.summary;
  if (admission === null || typeof admission !== 'object' || admission.status !== 'terms_reconciled_but_unsimulated' ||
      admission.readyForSimulation !== true || admission.transactionMessageHash !== summary.transactionMessageHash ||
      admission.draftBindingHash !== summary.bindingHash || admission.candidateTermsHash !== summary.userApproval.candidateTermsHash ||
      summary.readyForSimulation !== false || summary.signingEnabled !== false || summary.executionEnabled !== false) {
    fail('STOCK_DRAFT_REVIEW_REQUIRED');
  }
  await assertStockDraftBinding(draft, binding);
  return Uint8Array.from(stored.get(draft)!.bytes);
}
