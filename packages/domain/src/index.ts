import { DomainError } from './domain-error.js';

/** Pure rules only. These types do not authenticate a caller or authorize a transaction. */
export { DomainError };

export { PRACTICE_ASSET_IDS } from './practice-assets.js';
export type { PracticeAssetId } from './practice-assets.js';
export * from './practice-catalog.generated.js';

export {
  parsePracticeProgress, canonicalPracticeProgress, assertPracticeHistoryPreserved,
} from './practice-progress.js';
export type {
  PracticeActivityId, PracticeActivityProgress, PracticeCompletion, PracticeProgress,
} from './practice-progress.js';

export {
  PAPER_FIXED_SCALE, PAPER_FIXED_SCALE_DIGITS, PAPER_FIXED_MAX, PAPER_STARTING_CASH_MICROS,
  calculatePaperOrder, parsePaperAssetId, parsePaperFixed, parsePaperOrderAction,
  parsePaperOrderAmount, parsePaperSignedFixed, parsePaperSymbol, parsePaperVariantMint,
} from './paper-trading.js';
export type {
  PaperOrderAction, PaperOrderAmount, PaperOrderCalculation, PaperPositionState,
} from './paper-trading.js';

export const U64_MAX = 18_446_744_073_709_551_615n;

/** Canonical base-unit text. Never send JSON numbers for token amounts. */
export function parseRawAmount(value: string): bigint {
  if (typeof value !== 'string' || /^(0|[1-9]\d{0,19})$/.exec(value)?.[0] !== value) {
    throw new DomainError('INVALID_RAW_AMOUNT', 'Expected a canonical unsigned integer string.');
  }
  const amount = BigInt(value);
  if (amount > U64_MAX) throw new DomainError('AMOUNT_OVERFLOW', 'Amount exceeds the Solana u64 limit.');
  return amount;
}

function validDecimals(decimals: number): void {
  if (!Number.isInteger(decimals) || decimals < 0 || decimals > 255) {
    throw new DomainError('INVALID_DECIMALS', 'Mint decimals must be an integer between 0 and 255.');
  }
}

/**
 * Exact explanatory decimal arithmetic, not a replacement for Token-2022's SDK
 * conversion/rounding. Input must be an explicitly sourced decimal multiplier.
 * Do not invert this display string to construct a transaction.
 */
export function explanatoryScaledBalance(rawAmount: string, decimals: number, multiplier: string): string {
  const raw = parseRawAmount(rawAmount);
  validDecimals(decimals);
  if (typeof multiplier !== 'string' || !/^(0|[1-9]\d{0,29})(\.\d{1,30})?$/.test(multiplier)) {
    throw new DomainError('INVALID_MULTIPLIER', 'Expected a positive finite decimal multiplier.');
  }
  const [whole, fractional = ''] = multiplier.split('.');
  const coefficient = BigInt(`${whole}${fractional}`);
  if (coefficient <= 0n) throw new DomainError('INVALID_MULTIPLIER', 'Multiplier must be positive.');
  const scale = decimals + fractional.length;
  const product = raw * coefficient;
  if (scale === 0) return product.toString();
  const padded = product.toString().padStart(scale + 1, '0');
  const integer = padded.slice(0, -scale);
  const fraction = padded.slice(-scale).replace(/0+$/, '');
  return fraction.length ? `${integer}.${fraction}` : integer;
}

export function parseInstant(value: string): number {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value)) {
    throw new DomainError('INVALID_TIMESTAMP', 'Use a canonical UTC ISO timestamp including milliseconds.');
  }
  const epoch = Date.parse(value);
  if (!Number.isFinite(epoch) || new Date(epoch).toISOString() !== value) {
    throw new DomainError('INVALID_TIMESTAMP', 'Timestamp does not identify a valid instant.');
  }
  return epoch;
}

function nonempty(value: string, field: string): void {
  if (typeof value !== 'string' || value.length === 0 || value.trim() !== value || value.length > 256) {
    throw new DomainError('INVALID_IDENTIFIER', `${field} must be a bounded nonempty identifier.`);
  }
}

export interface XRecipient {
  readonly provider: 'x';
  readonly subject: string;
  readonly handleSnapshot: string;
}

export function validateXRecipient(recipient: XRecipient): void {
  if (recipient.provider !== 'x' || !/^[1-9]\d{0,19}$/.test(recipient.subject)) {
    throw new DomainError('INVALID_X_SUBJECT', 'The X identity must have an authoritative numeric subject.');
  }
  if (!/^[A-Za-z0-9_]{1,15}$/.test(recipient.handleSnapshot)) {
    throw new DomainError('INVALID_X_HANDLE', 'The handle snapshot is invalid.');
  }
}

export function assertSameXSubject(addressed: XRecipient, authenticated: XRecipient): void {
  validateXRecipient(addressed);
  validateXRecipient(authenticated);
  if (addressed.subject !== authenticated.subject) {
    throw new DomainError('RECIPIENT_MISMATCH', 'Authenticated X identity is not the addressed recipient.');
  }
}

export interface EligibilityAttestation {
  readonly id: string;
  readonly userId: string;
  readonly providerIdentityId: string;
  readonly assetId: string;
  readonly countryCode: string;
  readonly policyVersion: string;
  readonly decision: 'eligible' | 'ineligible' | 'pending';
  readonly evidenceReference: string;
  readonly issuedAt: string;
  readonly expiresAt: string;
}

export interface EligibilityContext {
  readonly userId: string;
  readonly providerIdentityId: string;
  readonly assetId: string;
  readonly countryCode: string;
  readonly policyVersion: string;
  readonly now: string;
}

export type EligibilityResult =
  | { readonly eligible: true }
  | { readonly eligible: false; readonly reason: 'missing' | 'binding_mismatch' | 'policy_changed' | 'not_yet_valid' | 'expired' | 'ineligible' | 'pending' };

/** Evaluate only an authenticated provider result read from trusted storage, never client JSON. */
export function evaluateEligibility(attestation: EligibilityAttestation | null, context: EligibilityContext): EligibilityResult {
  const now = parseInstant(context.now);
  if (!attestation) return { eligible: false, reason: 'missing' };
  if (!['eligible', 'ineligible', 'pending'].includes(attestation.decision)) {
    throw new DomainError('INVALID_ELIGIBILITY_DECISION', 'Attestation decision is invalid.');
  }
  for (const field of ['id', 'userId', 'providerIdentityId', 'assetId', 'policyVersion', 'evidenceReference'] as const) {
    nonempty(attestation[field], field);
  }
  if (!/^[A-Z]{2}$/.test(attestation.countryCode) || !/^[A-Z]{2}$/.test(context.countryCode)) {
    throw new DomainError('INVALID_COUNTRY', 'Country must be an uppercase ISO alpha-2 code.');
  }
  if (attestation.userId !== context.userId || attestation.providerIdentityId !== context.providerIdentityId ||
      attestation.assetId !== context.assetId || attestation.countryCode !== context.countryCode) {
    return { eligible: false, reason: 'binding_mismatch' };
  }
  if (attestation.policyVersion !== context.policyVersion) return { eligible: false, reason: 'policy_changed' };
  const issued = parseInstant(attestation.issuedAt);
  const expires = parseInstant(attestation.expiresAt);
  if (expires <= issued) throw new DomainError('INVALID_ATTESTATION_WINDOW', 'Attestation must expire after issuance.');
  if (now < issued) return { eligible: false, reason: 'not_yet_valid' };
  if (now >= expires) return { eligible: false, reason: 'expired' };
  if (attestation.decision !== 'eligible') return { eligible: false, reason: attestation.decision };
  return { eligible: true };
}

export type InvitationState = 'draft' | 'addressed' | 'offered' | 'accepted' | 'declined' | 'expired' | 'canceled';
export interface UnfundedInvitation {
  readonly id: string;
  readonly senderUserId: string;
  readonly recipient: XRecipient | null;
  readonly state: InvitationState;
  readonly funding: 'unfunded';
  readonly expiresAt: string;
  readonly version: number;
}

export function createUnfundedInvitation(input: {id: string; senderUserId: string; now: string; expiresAt: string}): UnfundedInvitation {
  nonempty(input.id, 'id');
  nonempty(input.senderUserId, 'senderUserId');
  if (parseInstant(input.expiresAt) <= parseInstant(input.now)) {
    throw new DomainError('INVALID_INVITATION_WINDOW', 'Invitation expiry must be in the future.');
  }
  return Object.freeze({ id: input.id, senderUserId: input.senderUserId, recipient: null, state: 'draft', funding: 'unfunded', expiresAt: input.expiresAt, version: 0 });
}

function assertVersion(invitation: UnfundedInvitation, expectedVersion: number): void {
  nonempty(invitation.id, 'id');
  nonempty(invitation.senderUserId, 'senderUserId');
  parseInstant(invitation.expiresAt);
  if (!['draft', 'addressed', 'offered', 'accepted', 'declined', 'expired', 'canceled'].includes(invitation.state) ||
      invitation.funding !== 'unfunded' || !Number.isSafeInteger(invitation.version) || invitation.version < 0 || invitation.version >= Number.MAX_SAFE_INTEGER) {
    throw new DomainError('INVALID_INVITATION', 'Stored invitation is invalid.');
  }
  if (invitation.recipient !== null) validateXRecipient(invitation.recipient);
  if ((invitation.state === 'draft' && invitation.recipient !== null) ||
      (['addressed', 'offered', 'accepted', 'declined'].includes(invitation.state) && invitation.recipient === null)) {
    throw new DomainError('INVALID_INVITATION', 'Stored invitation recipient is inconsistent with its state.');
  }
  if (!Number.isSafeInteger(expectedVersion) || expectedVersion < 0 || invitation.version !== expectedVersion) {
    throw new DomainError('VERSION_CONFLICT', 'Invitation changed; reload it before continuing.');
  }
}

export function addressUnfundedInvitation(invitation: UnfundedInvitation, recipient: XRecipient, context: {actorUserId: string; expectedVersion: number; now: string}): UnfundedInvitation {
  assertVersion(invitation, context.expectedVersion);
  if (invitation.senderUserId !== context.actorUserId) throw new DomainError('FORBIDDEN', 'Only the sender can address this invitation.');
  if (invitation.state !== 'draft' || invitation.recipient !== null) throw new DomainError('INVALID_TRANSITION', 'An addressed invitation cannot be redirected.');
  if (parseInstant(context.now) >= parseInstant(invitation.expiresAt)) throw new DomainError('INVITATION_EXPIRED', 'The invitation has expired.');
  validateXRecipient(recipient);
  return Object.freeze({ ...invitation, recipient: Object.freeze({...recipient}), state: 'addressed', version: invitation.version + 1 });
}

export type InvitationAction = 'offer' | 'accept' | 'decline' | 'cancel' | 'expire';
export interface InvitationTransitionContext {
  readonly actorUserId: string | null;
  readonly authenticatedRecipient: XRecipient | null;
  readonly expectedVersion: number;
  readonly now: string;
}

export function transitionUnfundedInvitation(invitation: UnfundedInvitation, action: InvitationAction, context: InvitationTransitionContext): UnfundedInvitation {
  assertVersion(invitation, context.expectedVersion);
  if (!['offer', 'accept', 'decline', 'cancel', 'expire'].includes(action)) {
    throw new DomainError('INVALID_ACTION', 'Invitation action is not supported.');
  }
  if (['accepted', 'declined', 'expired', 'canceled'].includes(invitation.state)) {
    throw new DomainError('TERMINAL_INVITATION', 'A terminal invitation cannot change state.');
  }
  const hasExpired = parseInstant(context.now) >= parseInstant(invitation.expiresAt);
  let state: InvitationState;
  if (action === 'expire') {
    if (!hasExpired) throw new DomainError('NOT_EXPIRED', 'Expiry has not been reached.');
    state = 'expired';
  } else {
    if (hasExpired) throw new DomainError('INVITATION_EXPIRED', 'The invitation has expired.');
    if (action === 'offer' || action === 'cancel') {
      if (context.actorUserId !== invitation.senderUserId) throw new DomainError('FORBIDDEN', 'Only the sender may perform this action.');
      if (action === 'offer' && invitation.state !== 'addressed') throw new DomainError('INVALID_TRANSITION', 'Address the invitation before offering it.');
      state = action === 'offer' ? 'offered' : 'canceled';
    } else {
      if (invitation.state !== 'offered') throw new DomainError('INVALID_TRANSITION', 'Only an offered invitation can be accepted or declined.');
      if (!context.actorUserId || !invitation.recipient || !context.authenticatedRecipient) {
        throw new DomainError('RECIPIENT_REQUIRED', 'A verified recipient session is required.');
      }
      assertSameXSubject(invitation.recipient, context.authenticatedRecipient);
      state = action === 'accept' ? 'accepted' : 'declined';
    }
  }
  // Acceptance changes social intent only. It never invents funding or delivery.
  return Object.freeze({ ...invitation, state, version: invitation.version + 1 });
}

export interface ReviewedQuote {
  readonly id: string;
  readonly userId: string;
  readonly inputMint: string;
  readonly outputMint: string;
  readonly inputAmountRaw: string;
  readonly minimumOutputRaw: string;
  readonly quotedAt: string;
  readonly expiresAt: string;
  readonly transactionMessageHash: string;
}

export function assertQuoteUsable(quote: ReviewedQuote, context: {now: string; userId: string; inputMint: string; outputMint: string; inputAmountRaw: string; transactionMessageHash: string; maxAgeMs: number}): void {
  for (const field of ['id', 'userId', 'inputMint', 'outputMint', 'transactionMessageHash'] as const) {
    nonempty(quote[field], field);
  }
  if (!/^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(quote.inputMint) || !/^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(quote.outputMint) || quote.inputMint === quote.outputMint) {
    throw new DomainError('INVALID_QUOTE_MINTS', 'Quote needs two distinct base58 mint addresses.');
  }
  // Format validation is not onchain mint verification or transaction decoding.
  if (!/^[a-f0-9]{64}$/.test(quote.transactionMessageHash)) {
    throw new DomainError('INVALID_MESSAGE_HASH', 'Expected a canonical SHA-256 message digest.');
  }
  const now = parseInstant(context.now);
  const quoted = parseInstant(quote.quotedAt);
  const expires = parseInstant(quote.expiresAt);
  if (!Number.isSafeInteger(context.maxAgeMs) || context.maxAgeMs <= 0 || expires <= quoted) {
    throw new DomainError('INVALID_QUOTE_WINDOW', 'Quote validity is invalid.');
  }
  if (quoted > now || now >= expires || now - quoted >= context.maxAgeMs) {
    throw new DomainError('QUOTE_EXPIRED', 'Request a new quote and review it again.');
  }
  if (parseRawAmount(quote.inputAmountRaw) <= 0n || parseRawAmount(quote.minimumOutputRaw) <= 0n) {
    throw new DomainError('INVALID_QUOTE_AMOUNT', 'Quote amounts must be positive.');
  }
  if (quote.userId !== context.userId || quote.inputMint !== context.inputMint || quote.outputMint !== context.outputMint ||
      quote.inputAmountRaw !== context.inputAmountRaw || quote.transactionMessageHash !== context.transactionMessageHash) {
    throw new DomainError('QUOTE_BINDING_MISMATCH', 'Quote does not match the reviewed transaction intent.');
  }
}

export interface ValuationSubperiod {
  /** Value immediately after the preceding external flow, or at season start. */
  readonly openingValue: bigint;
  /** Value immediately before the next external flow, or at season end. */
  readonly closingValue: bigint;
}
export interface RationalReturn { readonly numerator: bigint; readonly denominator: bigint }
function gcd(a: bigint, b: bigint): bigint {
  while (b !== 0n) { const remainder = a % b; a = b; b = remainder; }
  return a < 0n ? -a : a;
}

/** Exact time-weighted return. Valuations use one currency; fees count as performance. */
export function timeWeightedReturn(periods: readonly ValuationSubperiod[]): RationalReturn {
  if (periods.length === 0) throw new DomainError('MISSING_VALUATIONS', 'At least one valuation subperiod is required.');
  let numerator = 1n;
  let denominator = 1n;
  for (const period of periods) {
    if (period.openingValue <= 0n || period.closingValue < 0n) {
      throw new DomainError('INVALID_VALUATION', 'Subperiod opening must be positive and closing cannot be negative.');
    }
    numerator *= period.closingValue;
    denominator *= period.openingValue;
    const divisor = gcd(numerator, denominator);
    numerator /= divisor;
    denominator /= divisor;
  }
  const returnNumerator = numerator - denominator;
  const divisor = gcd(returnNumerator, denominator);
  return Object.freeze({ numerator: returnNumerator / divisor, denominator: denominator / divisor });
}

/** This build cannot enable live money through environment variables or an API request. */
export const FOUNDATION_CAPABILITIES = Object.freeze({
  mode: 'foundation' as const,
  financialOperationsEnabled: false as const,
  liveWalletsEnabled: false as const,
  fundedGiftsEnabled: false as const,
  swapsEnabled: false as const,
  persistenceEnabled: false as const,
  supportedAssetIds: Object.freeze([] as string[]),
});
