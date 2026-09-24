/**
 * Live mainnet evidence for the unsigned stock-order review. It fetches one
 * fresh Jupiter estimate and one real order for the funded research wallet,
 * binds the order as a draft, then runs the real review composition against
 * public mainnet RPC: structure, lookup tables, lifetime, semantics, terms
 * reconciliation and the isolated simulation.
 *
 * Nothing here can sign or send: the review modules have no such method and
 * this harness holds no signing interface. The record keeps digests, amounts
 * and addresses; it never contains transaction bytes or provider payload text.
 * The research wallet's local principal is not an application account, and
 * the record says so.
 */
import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { openStockResearchWallet, STOCK_WALLET_GENESIS } from './stock-order-wallet.mjs';
import { JupiterQuoteReader } from '../../apps/api/src/jupiter-quote-reader.ts';
import { JupiterStockEstimates, STOCK_ESTIMATE_ASSET } from '../../apps/api/src/stock-estimates.ts';
import { bindStockOrderDraft, StockOrderDraftError } from '../../apps/api/src/stock-order-draft.ts';
import { SolanaMainnetLookupTableResolver } from '../../apps/api/src/stock-order-lookup-resolver.ts';
import { SolanaMainnetStockOrderLifetimeVerifier } from '../../apps/api/src/stock-order-lifetime-verifier.ts';
import { SolanaMainnetStockOrderSemanticsReader } from '../../apps/api/src/stock-order-semantics.ts';
import { SolanaMainnetStockOrderSimulator } from '../../apps/api/src/stock-order-simulation.ts';
import { reviewStockOrder } from '../../apps/api/src/stock-order-review.ts';

export const DEFAULT_MAINNET_RPC = 'https://api.mainnet-beta.solana.com';
/**
 * The free public endpoint load-balances across nodes at different slots, which
 * the multi-read lifetime and account gates correctly refuse. Set
 * TRIMMY_MAINNET_RPC_URL to a single-node or keyed endpoint for a full pass.
 */
export const MAINNET_RPC = process.env.TRIMMY_MAINNET_RPC_URL ?? DEFAULT_MAINNET_RPC;
export const USDC_MINT = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
export const LIVE_REVIEW_INPUT_RAW = '1000000';
const ORDER_URL = 'https://api.jup.ag/swap/v2/order';
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const integer = value => Number.isSafeInteger(value) && value >= 0;
const sha256 = value => createHash('sha256').update(value).digest('hex');
const delay = ms => new Promise(done => setTimeout(done, ms));

export class LiveReviewError extends Error {
  constructor(code) { super(code); this.name = 'LiveReviewError'; this.code = code; }
}
const fail = code => { throw new LiveReviewError(code); };

/** Read-only chain observation for the binder's validity authority. */
class ObservationRpc {
  #id = 0;
  async call(method, params = []) {
    if (!['getGenesisHash', 'getBlockHeight'].includes(method)) fail('LIVE_REVIEW_RPC_METHOD_DENIED');
    const id = ++this.#id;
    const response = await fetch(MAINNET_RPC, {method: 'POST', redirect: 'error', signal: AbortSignal.timeout(8_000),
      headers: {'content-type': 'application/json'}, body: JSON.stringify({jsonrpc: '2.0', id, method, params})});
    if (!response.ok) fail('LIVE_REVIEW_RPC_UNAVAILABLE');
    const body = await response.json();
    if (!object(body) || body.id !== id || Object.hasOwn(body, 'error') || !Object.hasOwn(body, 'result')) fail('LIVE_REVIEW_RPC_INVALID');
    return body.result;
  }
  async observe(now) {
    const observedAt = now();
    if (await this.call('getGenesisHash') !== STOCK_WALLET_GENESIS) fail('LIVE_REVIEW_WRONG_NETWORK');
    const height = await this.call('getBlockHeight', [{commitment: 'confirmed'}]);
    if (!integer(height)) fail('LIVE_REVIEW_RPC_INVALID');
    return {genesisHash: STOCK_WALLET_GENESIS, blockHeight: String(height), observedAt: new Date(observedAt).toISOString()};
  }
}

async function fetchOrder(taker, slippageBps) {
  const url = new URL(ORDER_URL);
  url.search = new URLSearchParams({inputMint: USDC_MINT, outputMint: STOCK_ESTIMATE_ASSET.variantMint,
    amount: LIVE_REVIEW_INPUT_RAW, taker, slippageBps: String(slippageBps)}).toString();
  const response = await fetch(url, {method: 'GET', headers: {accept: 'application/json'}, redirect: 'error',
    signal: AbortSignal.timeout(8_000)});
  if (!response.ok) fail(response.status === 429 ? 'LIVE_REVIEW_ORDER_RATE_LIMITED' : 'LIVE_REVIEW_ORDER_UNAVAILABLE');
  const text = await response.text();
  if (text.length > 262_144) fail('LIVE_REVIEW_ORDER_TOO_LARGE');
  return JSON.parse(text);
}

/** Wraps a stage so its timing and outcome are recorded without changing its behavior. */
function timed(name, stage, method, log) {
  return {[method]: async (...args) => {
    const startedAt = Date.now();
    try {
      const result = await stage[method](...args);
      log.push({stage: name, outcome: 'passed', ms: Date.now() - startedAt});
      return result;
    } catch (error) {
      log.push({stage: name, outcome: 'failed', code: error?.code ?? 'unknown', ms: Date.now() - startedAt});
      throw error;
    }
  }};
}

function safeSummary(summary) {
  return {
    requestId: summary.requestId, side: summary.side, input: summary.input, output: summary.output,
    slippageBps: summary.slippageBps, swapFee: summary.swapFee, router: summary.router,
    termChanges: summary.termChanges, approvalPolicy: summary.approvalPolicy, notAfter: summary.notAfter,
    providerExpiresAt: summary.providerExpiresAt, lastValidBlockHeight: summary.lastValidBlockHeight,
    admittedAtBlockHeight: summary.admittedAtBlockHeight, transactionMessageHash: summary.transactionMessageHash,
    transactionHash: summary.transactionHash, bindingHash: summary.bindingHash,
    candidateTermsHash: summary.userApproval.candidateTermsHash, transactionSizeBytes: summary.transactionSizeBytes,
    staticAccountCount: summary.staticAccounts.length, lookupTableCount: summary.lookupTables.length,
    instructionCount: summary.instructionCount, review: summary.review,
    readyForSimulation: summary.readyForSimulation, signingEnabled: summary.signingEnabled,
    executionEnabled: summary.executionEnabled,
  };
}

export async function runLiveReview({now = Date.now, notify = () => {}} = {}) {
  const wallet = await openStockResearchWallet({mode: 'reopen'});
  const observation = new ObservationRpc();
  const record = {
    schemaVersion: 1, kind: 'stock_order_live_review', startedAt: new Date(now()).toISOString(),
    network: 'solana:mainnet-beta', rpc: MAINNET_RPC, taker: wallet.publicAddress,
    accountVerification: 'local_research_principal_not_an_app_account',
    inputAmountRaw: LIVE_REVIEW_INPUT_RAW, stages: [], signed: false, submitted: false, broadcast: false,
  };
  record.rpcIsDefaultPublic = MAINNET_RPC === DEFAULT_MAINNET_RPC;
  const estimates = new JupiterStockEstimates(new JupiterQuoteReader({access: {kind: 'keyless_research'}, now}));
  const freshEstimate = async () => {
    // The provider occasionally answers a research quote with a shape the strict
    // reader refuses; one spaced retry is taken rather than failing the attempt.
    for (let inner = 0; inner < 4; inner++) {
      try {
        return await estimates.estimate({assetId: 'apple', variantMint: STOCK_ESTIMATE_ASSET.variantMint,
          side: 'buy', amountRaw: LIVE_REVIEW_INPUT_RAW});
      } catch (error) {
        record.estimateRejections = (record.estimateRejections ?? 0) + 1;
        if (inner === 3 || (error?.code !== 'MARKET_RESPONSE_INVALID' && error?.code !== 'MARKET_ESTIMATE_STALE')) throw error;
        await delay(2_500);
      }
    }
    return fail('LIVE_REVIEW_ESTIMATE_UNAVAILABLE');
  };

  // A draft's blockhash-bound cutoff is about ten seconds, and the free public
  // RPC (api.mainnet-beta) load-balances across nodes at different slots, so a
  // multi-read gate can legitimately see an inconsistent view. That is
  // infrastructure flakiness, not a real inconsistency in the transaction, so a
  // fresh order and review are attempted a bounded number of times. Each attempt
  // is recorded; the review gates themselves are never loosened.
  const RETRYABLE = new Set(['LIFETIME_OBSERVATION_CHANGED', 'LOOKUP_OBSERVATION_CHANGED',
    'LIFETIME_EXPIRED', 'SEMANTICS_OBSERVATION_INCONSISTENT',
    'LIFETIME_RPC_TIMEOUT', 'LOOKUP_RPC_TIMEOUT', 'SEMANTICS_RPC_TIMEOUT', 'SIMULATION_RPC_TIMEOUT',
    'LIFETIME_RPC_UNAVAILABLE', 'LOOKUP_RPC_UNAVAILABLE', 'SEMANTICS_RPC_UNAVAILABLE', 'SIMULATION_RPC_UNAVAILABLE',
    'SIMULATION_OBSERVATION_STALE', 'STOCK_DRAFT_EXPIRED', 'REVIEW_EXPIRED']);
  const MAX_ATTEMPTS = 6;
  record.attempts = [];
  let outcome = null;

  for (let attempt = 1; attempt <= MAX_ATTEMPTS && outcome === null; attempt++) {
    // Keyless research access is spaced; each attempt takes a fresh estimate and order.
    await delay(2_200);
    const expected = await freshEstimate();
    if (attempt === 1) {
      record.estimate = {router: expected.router, estimatedAmountRaw: expected.output.estimatedAmountRaw,
        quotedMinimumAmountRaw: expected.output.quotedMinimumAmountRaw, slippageBps: expected.slippageBps,
        swapFee: expected.swapFee, receivedAt: expected.receivedAt, refreshAfter: expected.refreshAfter};
      notify('estimate received');
    }
    await delay(2_200);
    const admitted = await observation.observe(now);
    const requestStartedAt = new Date(now()).toISOString();
    const order = await fetchOrder(wallet.publicAddress, expected.slippageBps);
    if (attempt === 1) {
      record.order = {
        keys: Object.keys(order).sort(), router: order.router,
        hasTransaction: typeof order.transaction === 'string' && order.transaction.length > 0,
        transactionBase64Length: typeof order.transaction === 'string' ? order.transaction.length : 0,
        lastValidBlockHeight: order.lastValidBlockHeight ?? null, expireAt: order.expireAt ?? null,
        errorCode: order.errorCode ?? null, gasless: order.gasless ?? null,
        signatureFeePayer: order.signatureFeePayer ?? null, prioritizationFeePayer: order.prioritizationFeePayer ?? null,
        rentFeePayer: order.rentFeePayer ?? null, inAmount: order.inAmount ?? null, outAmount: order.outAmount ?? null,
        otherAmountThreshold: order.otherAmountThreshold ?? null, feeBps: order.feeBps ?? null,
        prioritizationFeeLamports: order.prioritizationFeeLamports ?? null, rentFeeLamports: order.rentFeeLamports ?? null,
        signatureFeeLamports: order.signatureFeeLamports ?? null,
      };
    }
    notify(`order received (attempt ${attempt})`);

    let draft;
    try {
      draft = bindStockOrderDraft(order, {
        authenticatedUserId: wallet.localResearchPrincipalId, verifiedTaker: wallet.publicAddress, expected,
        requestStartedAt, chainObservation: admitted,
        validityAuthority: {now, readChainObservation: () => observation.observe(now)},
      });
    } catch (error) {
      const code = error instanceof StockOrderDraftError ? error.code : 'unknown';
      record.attempts.push({attempt, stage: 'binding', code});
      if (RETRYABLE.has(code)) continue;
      record.binding = {outcome: 'failed', code};
      record.finishedAt = new Date(now()).toISOString();
      record.passed = false;
      return record;
    }
    const attemptLog = [];
    const stages = {
      lookupResolver: timed('lookup_tables', new SolanaMainnetLookupTableResolver({rpcUrl: MAINNET_RPC, now}), 'resolve', attemptLog),
      lifetimeVerifier: timed('lifetime', new SolanaMainnetStockOrderLifetimeVerifier({rpcUrl: MAINNET_RPC, now}), 'verify', attemptLog),
      semanticsReader: timed('semantics', new SolanaMainnetStockOrderSemanticsReader({rpcUrl: MAINNET_RPC, now}), 'read', attemptLog),
      simulator: timed('simulation', new SolanaMainnetStockOrderSimulator({rpcUrl: MAINNET_RPC, now}), 'simulate', attemptLog),
      now,
    };
    try {
      const reviewed = await reviewStockOrder(draft, {authenticatedUserId: wallet.localResearchPrincipalId,
        verifiedTaker: wallet.publicAddress, requestId: draft.summary.requestId,
        transactionMessageHash: draft.summary.transactionMessageHash, bindingHash: draft.summary.bindingHash}, stages);
      record.binding = {outcome: 'passed'};
      record.draft = safeSummary(draft.summary);
      record.stages = attemptLog;
      record.attempts.push({attempt, stage: 'review', code: 'passed'});
      outcome = reviewed;
    } catch (error) {
      const code = error?.code ?? 'unknown';
      record.attempts.push({attempt, stage: 'review', code, stages: attemptLog});
      if (!RETRYABLE.has(code)) {
        record.binding = {outcome: 'passed'};
        record.draft = safeSummary(draft.summary);
        record.stages = attemptLog;
        record.review = {outcome: 'failed', code, name: error?.name ?? 'unknown', failure: error?.failure ?? null};
        record.passed = false;
        record.finishedAt = new Date(now()).toISOString();
        return record;
      }
      notify(`retrying after ${code} (attempt ${attempt})`);
    }
  }

  if (outcome === null) {
    record.review = {outcome: 'exhausted', code: 'LIVE_REVIEW_RETRIES_EXHAUSTED'};
    record.passed = false;
    record.finishedAt = new Date(now()).toISOString();
    return record;
  }

  {
    const {intent, evidence} = outcome;
    record.review = {outcome: 'passed'};
    record.structure = {status: evidence.structure.assessment.status, lookupTableResolution: evidence.structure.assessment.lookupTableResolution,
      accountIndexSpace: evidence.structure.accountIndexSpace, instructionCount: evidence.structure.instructions.length};
    record.lookupTables = {tables: evidence.resolvedAccounts.lookupTables.map(table => ({
      address: table.lookupTableAddress, addressCount: table.addressCount, referencedAddressCount: table.referencedAddressCount,
      authorityStatus: table.authorityStatus})), rpcMethods: evidence.resolvedAccounts.provenance.rpcMethods,
    firstObservationSlot: evidence.resolvedAccounts.firstObservationSlot, secondObservationSlot: evidence.resolvedAccounts.secondObservationSlot,
    digestSha256: evidence.resolvedAccounts.provenance.digestSha256};
    record.lifetime = evidence.lifetime.lifetime;
    record.semantics = {observationSlot: evidence.semantics.observationSlot, rpcApiVersion: evidence.semantics.rpcApiVersion,
      programs: evidence.semantics.programs, instructions: evidence.semantics.instructions.map(item => ({
        index: item.instructionIndex, program: item.programName, kind: item.decoded.kind,
        ...(item.decoded.program === 'jupiter_v6' ? {inAmount: item.decoded.inAmount, quotedOutAmount: item.decoded.quotedOutAmount,
          slippageBps: item.decoded.slippageBps, platformFeeBps: item.decoded.platformFeeBps,
          routePlanStepCount: item.decoded.routePlanStepCount, routeAccounts: item.decoded.routeAccounts.length} : {}),
      })), accountsObserved: evidence.semantics.provenance.accountsObserved, computeBudget: evidence.semantics.computeBudget,
      feeEstimate: evidence.semantics.feeEstimate, digestSha256: evidence.semantics.provenance.digestSha256};
    record.reconciliation = {swap: evidence.reconciliation.swap, candidate: evidence.reconciliation.candidate,
      accountState: evidence.reconciliation.accountState, effects: evidence.reconciliation.effects,
      cost: evidence.reconciliation.cost, reviewFlags: evidence.reconciliation.reviewFlags,
      checks: evidence.reconciliation.checks, assessment: evidence.reconciliation.assessment};
    record.simulation = {simulationSlot: evidence.simulation.simulationSlot, request: evidence.simulation.request,
      outcome: evidence.simulation.outcome, effects: evidence.simulation.effects, terms: evidence.simulation.terms,
      assessment: evidence.simulation.assessment, digestSha256: evidence.simulation.provenance.digestSha256};
    record.intent = intent;
    record.passed = true;
  }
  record.finishedAt = new Date(now()).toISOString();
  return record;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.argv.length !== 3 || process.argv[2] !== '--live-review') {
    console.log(JSON.stringify({passed: false, errorCode: 'LIVE_REVIEW_ARGUMENTS_INVALID'}));
    process.exitCode = 1;
  } else {
    try {
      let record;
      try {
        record = await runLiveReview({notify: message => console.error(`[live review] ${message}`)});
      } catch (runError) {
        // Record even a hard failure so the artifact shows what the run reached.
        record = {schemaVersion: 1, kind: 'stock_order_live_review', passed: false,
          errorCode: runError?.code ?? runError?.message ?? 'LIVE_REVIEW_FAILED',
          finishedAt: new Date().toISOString()};
      }
      const sourcePaths = ['apps/api/src/stock-order-draft.ts', 'apps/api/src/stock-order-lookup-resolver.ts',
        'apps/api/src/stock-order-lifetime-verifier.ts', 'apps/api/src/stock-order-semantics.ts',
        'apps/api/src/stock-order-terms-reconciliation.ts', 'apps/api/src/stock-order-simulation.ts',
        'apps/api/src/stock-order-review.ts', 'tool/testing/stock-order-live-review.mjs'];
      record.sourceSha256 = {};
      for (const path of sourcePaths) {
        record.sourceSha256[path] = sha256(await readFile(new URL(`../../${path}`, import.meta.url)));
      }
      const serialized = JSON.stringify(record, null, 2);
      if (record.order?.transactionBase64Length > 0 && serialized.includes('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')) {
        throw new LiveReviewError('LIVE_REVIEW_RECORD_CONTAINS_BYTES');
      }
      await writeFile(new URL('../../artifacts/verification/STOCK_ORDER_LIVE_REVIEW.json', import.meta.url), `${serialized}\n`);
      console.log(JSON.stringify({passed: record.passed, binding: record.binding?.outcome, review: record.review?.outcome ?? null,
        reviewCode: record.review?.code ?? null, stages: record.stages,
        intentDigest: record.intent?.reviewDigestSha256 ?? null}));
      if (!record.passed) process.exitCode = 1;
    } catch (error) {
      console.log(JSON.stringify({passed: false, errorCode: error?.code ?? 'LIVE_REVIEW_FAILED'}));
      process.exitCode = 1;
    }
  }
}
