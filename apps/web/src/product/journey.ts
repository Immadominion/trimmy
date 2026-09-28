import type {CareerSummary, LaunchCheckpoint, PaperReceipt, ProductProfile} from './practice-client.js';
import type {FollowupStep} from './journey-store.js';

/**
 * The first-day order, as mobile's ProductExperience builds it:
 * Welcome → note → first practice trade → confirmed receipt → explicit sign-in
 * or "Continue as guest" → reminders → practice money or fund wallet → Home.
 * Skip reaches the same account choice. This module is pure so reload, Skip
 * and restore rules can be tested without a browser.
 */
export interface FirstTradeEvidence {
  readonly orderId: string; readonly assetId: string; readonly variantMint: string; readonly symbol: string;
  readonly quantityMicros: string;
  /** Only the receipt of this exact order carries the amount spent. */
  readonly cashDebitPaperMicros: string | null;
}
export type JourneyView =
  | {readonly kind: 'outside'}
  | {readonly kind: 'gate'}
  | {readonly kind: 'practice'}
  | {readonly kind: 'celebration'; readonly evidence: FirstTradeEvidence | null}
  | {readonly kind: 'reminders'}
  | {readonly kind: 'money'}
  | {readonly kind: 'app'};
export interface JourneyInput {
  readonly identity: 'none' | 'guest' | 'account';
  /** undefined while the server profile is unknown; null when it does not exist yet. */
  readonly profile: ProductProfile | null | undefined;
  readonly guestChosen: boolean;
  /** Mobile's `_entryAccountGateOpen`: once shown, only a choice or sign-in closes it. */
  readonly gateOpen: boolean;
  readonly step: FollowupStep | null;
  readonly celebratedOrder: string | null;
  readonly evidence: FirstTradeEvidence | null;
}

export function firstTradeEvidence(career: CareerSummary | null, receipt: PaperReceipt | null): FirstTradeEvidence | null {
  const first = career?.firstConfirmedBuy ?? null;
  const buy = receipt?.action === 'buy' ? receipt : null;
  if (first) return {orderId: first.orderId, assetId: first.assetId, variantMint: first.variantMint, symbol: first.symbol,
    quantityMicros: first.quantityMicros, cashDebitPaperMicros: buy?.id === first.orderId ? buy.cashDebitPaperMicros : null};
  return buy ? {orderId: buy.id, assetId: buy.assetId, variantMint: buy.variantMint, symbol: buy.symbol,
    quantityMicros: buy.quantityMicros, cashDebitPaperMicros: buy.cashDebitPaperMicros} : null;
}

function initialStep(checkpoint: LaunchCheckpoint): FollowupStep {
  return checkpoint === 'save-desk' ? 2 : checkpoint === 'streak' ? 1 : 0;
}
/** Stored step first; a claimed desk keeps the same celebrated order under its new principal. */
export function followupStep(input: Pick<JourneyInput, 'step' | 'celebratedOrder' | 'evidence'>, checkpoint: LaunchCheckpoint): FollowupStep {
  if (input.step !== null) return input.step;
  const initial = initialStep(checkpoint);
  return initial === 0 && input.evidence && input.celebratedOrder === input.evidence.orderId ? 1 : initial;
}
export function needsAccountChoice(input: JourneyInput): boolean {
  if (input.identity !== 'guest' || input.guestChosen) return false;
  if (input.gateOpen) return true;
  const checkpoint = input.profile?.launchCheckpoint;
  if (!checkpoint || checkpoint === 'first-trade') return false;
  if (checkpoint === 'first-position') return followupStep(input, checkpoint) >= 1;
  return true;
}
export function journeyView(input: JourneyInput): JourneyView {
  if (input.identity === 'none' || input.profile === undefined) return {kind: 'outside'};
  if (needsAccountChoice(input)) return {kind: 'gate'};
  const profile = input.profile;
  if (!profile) return {kind: 'outside'};
  const checkpoint = profile.launchCheckpoint;
  if (checkpoint === 'app') return {kind: 'app'};
  if (checkpoint === 'first-trade') {
    // A confirmed order is never bought again to resume the introduction.
    return input.evidence || profile.hasConfirmedPaperTrade ? {kind: 'celebration', evidence: input.evidence} : {kind: 'practice'};
  }
  const step = followupStep(input, checkpoint);
  return step === 0 ? {kind: 'celebration', evidence: input.evidence} : step === 1 ? {kind: 'reminders'} : {kind: 'money'};
}
export function isJourneyScreen(view: JourneyView): view is Extract<JourneyView, {kind: 'gate' | 'celebration' | 'reminders' | 'money'}> {
  return view.kind === 'gate' || view.kind === 'celebration' || view.kind === 'reminders' || view.kind === 'money';
}
