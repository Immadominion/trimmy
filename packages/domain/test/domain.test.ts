import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  DomainError, U64_MAX, parseRawAmount, explanatoryScaledBalance, parseInstant,
  assertSameXSubject, evaluateEligibility, createUnfundedInvitation,
  addressUnfundedInvitation, transitionUnfundedInvitation, assertQuoteUsable,
  timeWeightedReturn, FOUNDATION_CAPABILITIES,
} from '../src/index.js';
import type { EligibilityAttestation, EligibilityContext, InvitationAction, UnfundedInvitation, ReviewedQuote } from '../src/index.js';

const now = '2026-09-13T12:00:00.000Z';
const later = '2026-09-13T13:00:00.000Z';
const recipient = {provider: 'x' as const, subject: '123456789', handleSnapshot: 'alice'};
const sender = 'user-sender';
const isCode = (code: string) => (error: unknown) => error instanceof DomainError && error.code === code;

describe('raw monetary amounts and explanatory display', () => {
  it('keeps u64 boundaries and values above Number precision exact', () => {
    assert.equal(parseRawAmount('0'), 0n);
    assert.equal(parseRawAmount('9007199254740993'), 9007199254740993n);
    assert.equal(parseRawAmount(U64_MAX.toString()), U64_MAX);
    assert.throws(() => parseRawAmount((U64_MAX + 1n).toString()), isCode('AMOUNT_OVERFLOW'));
  });
  it('rejects floats, signs, scientific notation, whitespace and noncanonical input', () => {
    for (const invalid of ['', '01', '-1', '+1', '1.0', '1e3', ' 1', '1 ', '1\n', '1\r\n', '1\u2028', 'NaN', '١', '9'.repeat(21)]) {
      assert.throws(() => parseRawAmount(invalid), isCode('INVALID_RAW_AMOUNT'));
    }
    assert.throws(() => parseRawAmount(10 as unknown as string), isCode('INVALID_RAW_AMOUNT'));
  });
  it('formats a scaled fractional balance with no binary floating-point loss', () => {
    assert.equal(explanatoryScaledBalance('123456789', 6, '1.008'), '124.444443312');
    assert.equal(explanatoryScaledBalance('1', 9, '4.032'), '0.000000004032');
    assert.equal(explanatoryScaledBalance('0', 6, '1.0'), '0');
    assert.equal(explanatoryScaledBalance(U64_MAX.toString(), 0, '1'), U64_MAX.toString());
    assert.equal(explanatoryScaledBalance('1000', 3, '2.000'), '2');
  });
  it('rejects invalid scales and multipliers', () => {
    for (const decimals of [-1, 1.2, 256, NaN, Infinity]) {
      assert.throws(() => explanatoryScaledBalance('1', decimals, '1'), isCode('INVALID_DECIMALS'));
    }
    for (const multiplier of ['0', '-1', 'NaN', 'Infinity', '1e6', '01', '.5']) {
      assert.throws(() => explanatoryScaledBalance('1', 6, multiplier), isCode('INVALID_MULTIPLIER'));
    }
  });
  it('rejects normalized invalid dates and ambiguous timestamps', () => {
    assert.equal(parseInstant(now), Date.parse(now));
    for (const invalid of ['2026-02-30T12:00:00.000Z', '2026-09-13', '2026-09-13T12:00:00Z', 'invalid']) {
      assert.throws(() => parseInstant(invalid), isCode('INVALID_TIMESTAMP'));
    }
  });
});

describe('identity and eligibility', () => {
  const attestation: EligibilityAttestation = {
    id: 'evidence-1', userId: 'user-1', providerIdentityId: 'identity-1', assetId: 'asset-1',
    countryCode: 'GB', policyVersion: 'policy-1', decision: 'eligible', evidenceReference: 'provider:reference-1',
    issuedAt: now, expiresAt: later,
  };
  const context: EligibilityContext = {userId: 'user-1', providerIdentityId: 'identity-1', assetId: 'asset-1', countryCode: 'GB', policyVersion: 'policy-1', now};
  it('accepts a rename of the addressed X subject and rejects handle reassignment', () => {
    assert.doesNotThrow(() => assertSameXSubject(recipient, {...recipient, handleSnapshot: 'renamed'}));
    assert.throws(() => assertSameXSubject(recipient, {...recipient, subject: '999'}), isCode('RECIPIENT_MISMATCH'));
  });
  it('requires a trusted attestation with all identity and asset bindings', () => {
    assert.deepEqual(evaluateEligibility(null, context), {eligible: false, reason: 'missing'});
    assert.deepEqual(evaluateEligibility(attestation, context), {eligible: true});
    for (const patch of [{userId: 'other'}, {providerIdentityId: 'other'}, {assetId: 'other'}, {countryCode: 'NG'}]) {
      assert.deepEqual(evaluateEligibility(attestation, {...context, ...patch}), {eligible: false, reason: 'binding_mismatch'});
    }
  });
  it('fails closed on expired, future, pending, denied or superseded evidence', () => {
    assert.deepEqual(evaluateEligibility(attestation, {...context, now: later}), {eligible: false, reason: 'expired'});
    assert.deepEqual(evaluateEligibility({...attestation, issuedAt: '2026-09-13T12:01:00.000Z'}, context), {eligible: false, reason: 'not_yet_valid'});
    assert.deepEqual(evaluateEligibility(attestation, {...context, policyVersion: 'policy-2'}), {eligible: false, reason: 'policy_changed'});
    for (const decision of ['pending', 'ineligible'] as const) {
      assert.deepEqual(evaluateEligibility({...attestation, decision}, context), {eligible: false, reason: decision});
    }
  });
  it('rejects invalid evidence decisions, empty references and impossible validity windows', () => {
    assert.throws(() => evaluateEligibility({...attestation, decision: 'approved' as 'eligible'}, context), isCode('INVALID_ELIGIBILITY_DECISION'));
    assert.throws(() => evaluateEligibility({...attestation, evidenceReference: ''}, context), isCode('INVALID_IDENTIFIER'));
    assert.throws(() => evaluateEligibility({...attestation, expiresAt: now}, context), isCode('INVALID_ATTESTATION_WINDOW'));
  });
});

function draft(): UnfundedInvitation {
  return createUnfundedInvitation({id: 'invite-1', senderUserId: sender, now, expiresAt: later});
}
function addressed(): UnfundedInvitation {
  return addressUnfundedInvitation(draft(), recipient, {actorUserId: sender, expectedVersion: 0, now});
}
function offered(): UnfundedInvitation {
  return transitionUnfundedInvitation(addressed(), 'offer', {actorUserId: sender, authenticatedRecipient: null, expectedVersion: 1, now});
}
const recipientContext = {actorUserId: 'recipient-user', authenticatedRecipient: recipient, expectedVersion: 2, now};

describe('unfunded invitations', () => {
  it('accepts an invitation while remaining explicitly unfunded', () => {
    const invitation = offered();
    const accepted = transitionUnfundedInvitation(invitation, 'accept', recipientContext);
    assert.equal(accepted.state, 'accepted');
    assert.equal(accepted.funding, 'unfunded');
    assert.equal(accepted.version, 3);
    assert.equal(invitation.state, 'offered');
    assert.equal(Object.isFrozen(accepted), true);
    assert.equal(Object.isFrozen(accepted.recipient), true);
  });
  it('freezes recipient subject after addressing', () => {
    assert.throws(() => addressUnfundedInvitation(addressed(), {...recipient, subject: '987'}, {actorUserId: sender, expectedVersion: 1, now}), isCode('INVALID_TRANSITION'));
  });
  it('requires sender authority to address, offer and cancel', () => {
    assert.throws(() => addressUnfundedInvitation(draft(), recipient, {actorUserId: 'other', expectedVersion: 0, now}), isCode('FORBIDDEN'));
    for (const action of ['offer', 'cancel'] as const) {
      assert.throws(() => transitionUnfundedInvitation(addressed(), action, {...recipientContext, expectedVersion: 1}), isCode('FORBIDDEN'));
    }
  });
  it('cannot accept through a reassigned handle or without a recipient session', () => {
    assert.throws(() => transitionUnfundedInvitation(offered(), 'accept', {...recipientContext, authenticatedRecipient: {...recipient, subject: '987'}}), isCode('RECIPIENT_MISMATCH'));
    assert.throws(() => transitionUnfundedInvitation(offered(), 'accept', {...recipientContext, actorUserId: null}), isCode('RECIPIENT_REQUIRED'));
    assert.throws(() => transitionUnfundedInvitation(offered(), 'accept', {...recipientContext, authenticatedRecipient: null}), isCode('RECIPIENT_REQUIRED'));
  });
  it('permits renamed recipients with the same verified subject', () => {
    const accepted = transitionUnfundedInvitation(offered(), 'accept', {...recipientContext, authenticatedRecipient: {...recipient, handleSnapshot: 'newname'}});
    assert.equal(accepted.state, 'accepted');
  });
  it('rejects stale versions, skipped steps and unknown runtime actions', () => {
    assert.throws(() => transitionUnfundedInvitation(offered(), 'accept', {...recipientContext, expectedVersion: 1}), isCode('VERSION_CONFLICT'));
    assert.throws(() => transitionUnfundedInvitation(draft(), 'offer', {actorUserId: sender, authenticatedRecipient: null, expectedVersion: 0, now}), isCode('INVALID_TRANSITION'));
    assert.throws(() => transitionUnfundedInvitation(offered(), 'refund' as InvitationAction, recipientContext), isCode('INVALID_ACTION'));
  });
  it('makes expiry and terminal decisions exclusive', () => {
    assert.throws(() => transitionUnfundedInvitation(offered(), 'expire', recipientContext), isCode('NOT_EXPIRED'));
    assert.throws(() => transitionUnfundedInvitation(offered(), 'accept', {...recipientContext, now: later}), isCode('INVITATION_EXPIRED'));
    const expired = transitionUnfundedInvitation(offered(), 'expire', {...recipientContext, actorUserId: null, now: later});
    assert.equal(expired.state, 'expired');
    const accepted = transitionUnfundedInvitation(offered(), 'accept', recipientContext);
    const declined = transitionUnfundedInvitation(offered(), 'decline', recipientContext);
    const canceled = transitionUnfundedInvitation(offered(), 'cancel', {...recipientContext, actorUserId: sender});
    for (const terminal of [expired, accepted, declined, canceled]) {
      for (const action of ['accept', 'cancel', 'expire'] as const) {
        assert.throws(() => transitionUnfundedInvitation(terminal, action, {...recipientContext, expectedVersion: 3, now: later}), isCode('TERMINAL_INVITATION'));
      }
    }
  });
  it('rejects corrupt storage records before performing a transition', () => {
    for (const patch of [{version: Infinity}, {version: -1}, {version: 0.5}, {state: 'funded'}, {funding: 'funded'}, {recipient: null}]) {
      const corrupted = {...offered(), ...patch} as UnfundedInvitation;
      assert.throws(() => transitionUnfundedInvitation(corrupted, 'accept', recipientContext), isCode('INVALID_INVITATION'));
    }
  });
});

describe('reviewed quotes', () => {
  const quote: ReviewedQuote = {
    id: 'quote-1', userId: 'user-1', inputMint: 'So11111111111111111111111111111111111111112',
    outputMint: 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v', inputAmountRaw: '10000000', minimumOutputRaw: '10',
    quotedAt: now, expiresAt: '2026-09-13T12:00:30.000Z', transactionMessageHash: 'a'.repeat(64),
  };
  const context = {now, userId: quote.userId, inputMint: quote.inputMint, outputMint: quote.outputMint, inputAmountRaw: quote.inputAmountRaw, transactionMessageHash: quote.transactionMessageHash, maxAgeMs: 30_000};
  it('accepts a current quote bound to the reviewed user, amounts, mints and message', () => {
    assert.doesNotThrow(() => assertQuoteUsable(quote, context));
  });
  it('rejects expiry at the exact boundary and stale/future quotes', () => {
    assert.throws(() => assertQuoteUsable(quote, {...context, now: quote.expiresAt}), isCode('QUOTE_EXPIRED'));
    assert.throws(() => assertQuoteUsable(quote, {...context, now: '2026-09-13T12:00:02.000Z', maxAgeMs: 1000}), isCode('QUOTE_EXPIRED'));
    assert.throws(() => assertQuoteUsable(quote, {...context, now: '2026-09-13T11:59:59.000Z'}), isCode('QUOTE_EXPIRED'));
  });
  it('rejects changes after review', () => {
    for (const patch of [{userId: 'other'}, {inputAmountRaw: '10000001'}, {inputMint: quote.outputMint}, {outputMint: quote.inputMint}, {transactionMessageHash: 'b'.repeat(64)}]) {
      assert.throws(() => assertQuoteUsable(quote, {...context, ...patch}), isCode('QUOTE_BINDING_MISMATCH'));
    }
  });
  it('rejects empty matching fields, bad addresses/hash and zero protection', () => {
    assert.throws(() => assertQuoteUsable({...quote, userId: ''}, {...context, userId: ''}), isCode('INVALID_IDENTIFIER'));
    assert.throws(() => assertQuoteUsable({...quote, inputMint: quote.outputMint}, context), isCode('INVALID_QUOTE_MINTS'));
    assert.throws(() => assertQuoteUsable({...quote, inputMint: 'invalid'}, context), isCode('INVALID_QUOTE_MINTS'));
    assert.throws(() => assertQuoteUsable({...quote, transactionMessageHash: 'a'}, context), isCode('INVALID_MESSAGE_HASH'));
    assert.throws(() => assertQuoteUsable({...quote, minimumOutputRaw: '0'}, context), isCode('INVALID_QUOTE_AMOUNT'));
  });
});

describe('season return and foundation capabilities', () => {
  it('excludes an external deposit from performance', () => {
    // Grow 100 -> 110, add 90 externally, then grow 200 -> 220: 21%, not 120%.
    assert.deepEqual(timeWeightedReturn([{openingValue: 100n, closingValue: 110n}, {openingValue: 200n, closingValue: 220n}]), {numerator: 21n, denominator: 100n});
    assert.deepEqual(timeWeightedReturn([{openingValue: 100n, closingValue: 110n}, {openingValue: 110n, closingValue: 121n}]), {numerator: 21n, denominator: 100n});
  });
  it('does not reward pure deposits and withdrawals', () => {
    assert.deepEqual(timeWeightedReturn([{openingValue: 100n, closingValue: 100n}, {openingValue: 500n, closingValue: 500n}, {openingValue: 20n, closingValue: 20n}]), {numerator: 0n, denominator: 1n});
  });
  it('keeps losses and total loss visible', () => {
    assert.deepEqual(timeWeightedReturn([{openingValue: 100n, closingValue: 80n}]), {numerator: -1n, denominator: 5n});
    assert.deepEqual(timeWeightedReturn([{openingValue: 100n, closingValue: 0n}]), {numerator: -1n, denominator: 1n});
  });
  it('rejects missing or invalid valuation intervals', () => {
    assert.throws(() => timeWeightedReturn([]), isCode('MISSING_VALUATIONS'));
    assert.throws(() => timeWeightedReturn([{openingValue: 0n, closingValue: 5n}]), isCode('INVALID_VALUATION'));
    assert.throws(() => timeWeightedReturn([{openingValue: 5n, closingValue: -1n}]), isCode('INVALID_VALUATION'));
  });
  it('cannot enable live assets by mutating capability objects', () => {
    assert.equal(FOUNDATION_CAPABILITIES.financialOperationsEnabled, false);
    assert.deepEqual(FOUNDATION_CAPABILITIES.supportedAssetIds, []);
    assert.throws(() => { (FOUNDATION_CAPABILITIES as unknown as {financialOperationsEnabled: boolean}).financialOperationsEnabled = true; }, TypeError);
    assert.throws(() => { (FOUNDATION_CAPABILITIES.supportedAssetIds as string[]).push('fake-mint'); }, TypeError);
  });
});
