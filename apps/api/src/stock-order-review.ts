import { createHash } from 'node:crypto';
import { StockOrderDraftError, inspectStockDraftStructure } from './stock-order-draft.js';
import type { StockDraftBinding, StockDraftStructuralInspection, StockOrderDraft } from './stock-order-draft.js';
import type { ResolvedStockTransactionAccounts, SolanaMainnetLookupTableResolver } from './stock-order-lookup-resolver.js';
import type { SolanaMainnetStockOrderLifetimeVerifier, VerifiedStockOrderLifetime } from './stock-order-lifetime-verifier.js';
import type { SolanaMainnetStockOrderSemanticsReader, StockOrderSemantics } from './stock-order-semantics.js';
import { reconcileStockOrderTerms, reconciliationDigest } from './stock-order-terms-reconciliation.js';
import type { ReconciledStockOrderTerms } from './stock-order-terms-reconciliation.js';
import type { SolanaMainnetStockOrderSimulator, StockOrderSimulation } from './stock-order-simulation.js';

/**
 * Composes gates 2 to 7 into one reviewed intent: structure, lookup tables,
 * lifetime, semantics, reconciliation and simulation, in that order, every
 * stage bound to the same transaction message hash and candidate terms. The
 * result is an expiring, evidence-bearing record that still requires explicit
 * user approval bound to its terms hash, and that enables no signing, sending
 * or broadcasting. Persisting it is the repository's job; nothing here stores
 * raw transaction bytes.
 */
export type StockOrderReviewErrorCode = 'REVIEW_INPUT_INVALID' | 'REVIEW_EVIDENCE_MISMATCH' | 'REVIEW_EXPIRED';
export class StockOrderReviewError extends Error {
  constructor(readonly code: StockOrderReviewErrorCode) {
    super('The stock order review could not be completed.');
    this.name = 'StockOrderReviewError';
  }
}
const fail = (code: StockOrderReviewErrorCode): never => { throw new StockOrderReviewError(code); };
const sha256 = (value: string) => createHash('sha256').update(value).digest('hex');

/** How long a completed review stays usable before every time-sensitive stage must run again. */
export const REVIEW_VALIDITY_MS = 45_000;

export interface StockOrderReviewStages {
  readonly lookupResolver: Pick<SolanaMainnetLookupTableResolver, 'resolve'>;
  readonly lifetimeVerifier: Pick<SolanaMainnetStockOrderLifetimeVerifier, 'verify'>;
  readonly semanticsReader: Pick<SolanaMainnetStockOrderSemanticsReader, 'read'>;
  readonly simulator: Pick<SolanaMainnetStockOrderSimulator, 'simulate'>;
  readonly now?: () => number;
}

export interface StockOrderReviewEvidence {
  readonly structure: StockDraftStructuralInspection;
  readonly resolvedAccounts: ResolvedStockTransactionAccounts;
  readonly lifetime: VerifiedStockOrderLifetime;
  readonly semantics: StockOrderSemantics;
  readonly reconciliation: ReconciledStockOrderTerms;
  readonly simulation: StockOrderSimulation;
}

export interface ReviewedStockOrderIntent {
  readonly schemaVersion: 1;
  readonly kind: 'reviewed_stock_order_intent';
  readonly network: 'solana:mainnet-beta';
  readonly userId: string;
  readonly taker: string;
  readonly requestId: string;
  readonly transactionHash: string;
  readonly transactionMessageHash: string;
  readonly draftBindingHash: string;
  readonly candidateTermsHash: string;
  readonly reviewedAt: string;
  readonly expiresAt: string;
  readonly terms: Readonly<{
    readonly side: 'buy' | 'sell';
    readonly inputMint: string;
    readonly outputMint: string;
    readonly inputAmountRaw: string;
    readonly quotedOutputAmountRaw: string;
    readonly minimumOutputAmountRaw: string;
    readonly slippageBps: number;
    readonly platformFeeBps: number;
    readonly totalLamportsUpperBound: string;
    readonly simulatedOutputReceivedRaw: string;
    readonly simulatedTakerLamportsSpent: string;
  }>;
  readonly evidence: Readonly<{
    readonly structureSha256: string;
    readonly lookupResolutionSha256: string;
    readonly lifetimeSha256: string;
    readonly semanticsSha256: string;
    readonly reconciliationSha256: string;
    readonly simulationSha256: string;
    readonly observationSlot: string;
    readonly simulationSlot: string;
    readonly lastValidBlockHeight: string;
  }>;
  readonly reviewFlags: readonly string[];
  readonly reviewDigestSha256: string;
  readonly approval: Readonly<{
    readonly status: 'required';
    readonly method: 'explicit_user_confirmation_bound_to_review_digest';
    readonly walletPossession: 'required_before_signing';
  }>;
  readonly assessment: Readonly<{
    readonly status: 'reviewed_pending_approval';
    readonly stagesCompleted: readonly ['structure', 'lookup_tables', 'lifetime', 'semantics', 'reconciliation', 'simulation'];
    readonly revalidationRequired: true;
    readonly signingEnabled: false;
    readonly broadcastEnabled: false;
    readonly financialOperationsEnabled: false;
  }>;
}

export interface StockOrderReviewOutcome {
  readonly intent: ReviewedStockOrderIntent;
  readonly evidence: StockOrderReviewEvidence;
}

export async function reviewStockOrder(draft: StockOrderDraft, binding: StockDraftBinding,
  stages: StockOrderReviewStages): Promise<StockOrderReviewOutcome> {
  if (draft?.summary?.kind !== 'stock_order_draft' || binding === null || typeof binding !== 'object' ||
      stages === null || typeof stages !== 'object' || (stages.now !== undefined && typeof stages.now !== 'function')) {
    return fail('REVIEW_INPUT_INVALID');
  }
  const now = stages.now ?? Date.now;
  const summary = draft.summary;
  // An expired candidate never reaches the network stages.
  const cutoff = Date.parse(summary.notAfter);
  if (!Number.isFinite(cutoff) || now() >= cutoff) return fail('REVIEW_EXPIRED');
  let structure: StockDraftStructuralInspection;
  try {
    structure = inspectStockDraftStructure(draft, binding);
  } catch (error) {
    if (error instanceof StockOrderDraftError && error.code === 'STOCK_DRAFT_EXPIRED') return fail('REVIEW_EXPIRED');
    return fail('REVIEW_EVIDENCE_MISMATCH');
  }
  const resolvedAccounts = await stages.lookupResolver.resolve(structure);
  const lifetime = await stages.lifetimeVerifier.verify(draft, binding, structure);
  const semantics = await stages.semanticsReader.read({draft, binding, structure, resolvedAccounts});
  const reconciliation = reconcileStockOrderTerms({summary, semantics, now: now()});
  const simulation = await stages.simulator.simulate({draft, binding, semantics, reconciliation});
  const hashes = [structure, resolvedAccounts, lifetime, semantics, reconciliation, simulation].map(stage => stage.transactionMessageHash);
  if (hashes.some(hash => hash !== summary.transactionMessageHash) ||
      lifetime.draftBindingHash !== summary.bindingHash || lifetime.candidateTermsHash !== summary.userApproval.candidateTermsHash ||
      simulation.reconciliationDigestSha256 !== reconciliationDigest(reconciliation) ||
      reconciliation.semanticsDigestSha256 !== semantics.provenance.digestSha256) {
    return fail('REVIEW_EVIDENCE_MISMATCH');
  }
  const reviewedAtMs = now();
  const notAfter = Date.parse(summary.notAfter);
  if (!Number.isFinite(notAfter) || reviewedAtMs >= notAfter) return fail('REVIEW_EXPIRED');
  const expiresAtMs = Math.min(notAfter, reviewedAtMs + REVIEW_VALIDITY_MS);
  const evidence: StockOrderReviewEvidence = Object.freeze({structure, resolvedAccounts, lifetime, semantics, reconciliation, simulation});
  const evidenceDigests = Object.freeze({
    structureSha256: sha256(JSON.stringify(structure)),
    lookupResolutionSha256: resolvedAccounts.provenance.digestSha256,
    lifetimeSha256: sha256(JSON.stringify(lifetime)),
    semanticsSha256: semantics.provenance.digestSha256,
    reconciliationSha256: reconciliationDigest(reconciliation),
    simulationSha256: simulation.provenance.digestSha256,
    observationSlot: semantics.observationSlot,
    simulationSlot: simulation.simulationSlot,
    lastValidBlockHeight: lifetime.lifetime.providerLastValidBlockHeight,
  });
  const terms = Object.freeze({
    side: summary.side, inputMint: summary.input.mint, outputMint: summary.output.mint,
    inputAmountRaw: reconciliation.swap.inputAmountRaw, quotedOutputAmountRaw: reconciliation.swap.quotedOutputAmountRaw,
    minimumOutputAmountRaw: reconciliation.swap.minimumOutputAmountRaw, slippageBps: reconciliation.swap.slippageBps,
    platformFeeBps: reconciliation.swap.platformFeeBps, totalLamportsUpperBound: reconciliation.cost.totalLamportsUpperBound,
    simulatedOutputReceivedRaw: simulation.effects.outputReceivedRaw, simulatedTakerLamportsSpent: simulation.effects.takerLamportsSpent,
  });
  const reviewedAt = new Date(reviewedAtMs).toISOString();
  const expiresAt = new Date(expiresAtMs).toISOString();
  const reviewDigestSha256 = sha256(JSON.stringify({
    userId: summary.userId, taker: summary.taker, transactionMessageHash: summary.transactionMessageHash,
    candidateTermsHash: summary.userApproval.candidateTermsHash, terms, evidence: evidenceDigests, reviewedAt, expiresAt,
  }));
  const intent: ReviewedStockOrderIntent = Object.freeze({
    schemaVersion: 1, kind: 'reviewed_stock_order_intent', network: 'solana:mainnet-beta',
    userId: summary.userId, taker: summary.taker, requestId: summary.requestId,
    transactionHash: summary.transactionHash, transactionMessageHash: summary.transactionMessageHash,
    draftBindingHash: summary.bindingHash, candidateTermsHash: summary.userApproval.candidateTermsHash,
    reviewedAt, expiresAt, terms, evidence: evidenceDigests, reviewFlags: Object.freeze([...reconciliation.reviewFlags]),
    reviewDigestSha256,
    approval: Object.freeze({status: 'required', method: 'explicit_user_confirmation_bound_to_review_digest',
      walletPossession: 'required_before_signing'}),
    assessment: Object.freeze({
      status: 'reviewed_pending_approval',
      stagesCompleted: Object.freeze(['structure', 'lookup_tables', 'lifetime', 'semantics', 'reconciliation', 'simulation'] as const),
      revalidationRequired: true, signingEnabled: false, broadcastEnabled: false, financialOperationsEnabled: false,
    }),
  });
  return Object.freeze({intent, evidence});
}

/** True while the reviewed intent is inside its validity window. */
export function reviewedIntentUsable(intent: ReviewedStockOrderIntent, now: number): boolean {
  const reviewedAt = Date.parse(intent.reviewedAt);
  const expiresAt = Date.parse(intent.expiresAt);
  return Number.isFinite(reviewedAt) && Number.isFinite(expiresAt) && now >= reviewedAt && now < expiresAt &&
    intent.assessment.status === 'reviewed_pending_approval' && intent.assessment.signingEnabled === false;
}
