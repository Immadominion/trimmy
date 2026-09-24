import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  DomainError, PAPER_FIXED_MAX, PAPER_FIXED_SCALE, PAPER_STARTING_CASH_MICROS,
  calculatePaperOrder, parsePaperFixed, parsePaperOrderAmount,
} from '../src/index.js';

const fails = (code: string) => (error: unknown) => error instanceof DomainError && error.code === code;
const empty = {quantityMicros: '0', costBasisPaperMicros: '0'} as const;

describe('paper fixed-point parsing', () => {
  it('keeps the starting balance and maximum exact', () => {
    assert.equal(PAPER_FIXED_SCALE, 1_000_000n);
    assert.equal(PAPER_STARTING_CASH_MICROS, 10_000_000_000n);
    assert.equal(parsePaperFixed(PAPER_FIXED_MAX.toString()), PAPER_FIXED_MAX);
  });

  it('rejects JSON numbers, signs, fractions, whitespace and noncanonical text', () => {
    for (const value of [1, '', '01', '-1', '+1', '1.0', '1e6', ' 1', '1 ', '9'.repeat(16)]) {
      assert.throws(() => parsePaperFixed(value), fails('PAPER_AMOUNT_INVALID'));
    }
    assert.throws(() => parsePaperOrderAmount({kind: 'share_quantity', quantityMicros: '1', extra: true}),
      fails('PAPER_ORDER_INVALID'));
  });
});

describe('paper order accounting', () => {
  it('buys from a paper budget and rounds the debit up without exceeding it', () => {
    const result = calculatePaperOrder({
      action: 'buy', amount: {kind: 'paper_amount', paperMicros: '100000000'},
      pricePaperMicros: '3000000', cashPaperMicros: PAPER_STARTING_CASH_MICROS.toString(), position: empty,
    });
    assert.equal(result.quantityMicros, '33333333');
    assert.equal(result.cashDebitPaperMicros, '99999999');
    assert.equal(result.cashAfterPaperMicros, '9900000001');
    assert.equal(result.positionCostBasisAfterPaperMicros, '99999999');
  });

  it('conservatively rounds a round trip so it cannot create paper', () => {
    const bought = calculatePaperOrder({
      action: 'buy', amount: {kind: 'share_quantity', quantityMicros: '1'},
      pricePaperMicros: '1500001', cashPaperMicros: '100', position: empty,
    });
    assert.equal(bought.cashDebitPaperMicros, '2');
    const sold = calculatePaperOrder({
      action: 'sell', amount: {kind: 'share_quantity', quantityMicros: '1'},
      pricePaperMicros: '1500001', cashPaperMicros: bought.cashAfterPaperMicros,
      position: {quantityMicros: bought.positionQuantityAfterMicros,
        costBasisPaperMicros: bought.positionCostBasisAfterPaperMicros},
    });
    assert.equal(sold.cashCreditPaperMicros, '1');
    assert.equal(sold.cashAfterPaperMicros, '99');
    assert.equal(sold.realizedGainDeltaPaperMicros, '-1');
  });

  it('allocates partial basis and conserves the final remainder exactly', () => {
    const first = calculatePaperOrder({
      action: 'sell', amount: {kind: 'share_quantity', quantityMicros: '333333'},
      pricePaperMicros: '2000000', cashPaperMicros: '0',
      position: {quantityMicros: '1000000', costBasisPaperMicros: '1000001'},
    });
    assert.equal(first.positionCostBasisAfterPaperMicros, '666668');
    const final = calculatePaperOrder({
      action: 'sell', amount: {kind: 'share_quantity', quantityMicros: first.positionQuantityAfterMicros},
      pricePaperMicros: '2000000', cashPaperMicros: first.cashAfterPaperMicros,
      position: {quantityMicros: first.positionQuantityAfterMicros,
        costBasisPaperMicros: first.positionCostBasisAfterPaperMicros},
    });
    assert.equal(final.positionQuantityAfterMicros, '0');
    assert.equal(final.positionCostBasisAfterPaperMicros, '0');
  });

  it('requires trims to be profitable and partial', () => {
    const position = {quantityMicros: '2000000', costBasisPaperMicros: '4000000'} as const;
    assert.throws(() => calculatePaperOrder({action: 'trim', amount: {kind: 'share_quantity', quantityMicros: '2000000'},
      pricePaperMicros: '3000000', cashPaperMicros: '0', position}), fails('PAPER_TRIM_MUST_BE_PARTIAL'));
    assert.throws(() => calculatePaperOrder({action: 'trim', amount: {kind: 'share_quantity', quantityMicros: '1000000'},
      pricePaperMicros: '1000000', cashPaperMicros: '0', position}), fails('PAPER_TRIM_NOT_WINNING'));
    const result = calculatePaperOrder({action: 'trim', amount: {kind: 'share_quantity', quantityMicros: '1000000'},
      pricePaperMicros: '3000000', cashPaperMicros: '0', position});
    assert.equal(result.realizedGainDeltaPaperMicros, '1000000');
    assert.equal(result.lockedGainDeltaPaperMicros, '1000000');
  });

  it('refuses overspending, overselling and unsupported amount modes', () => {
    assert.throws(() => calculatePaperOrder({action: 'buy', amount: {kind: 'share_quantity', quantityMicros: '1000000'},
      pricePaperMicros: '2', cashPaperMicros: '1', position: empty}), fails('PAPER_CASH_INSUFFICIENT'));
    assert.throws(() => calculatePaperOrder({action: 'sell', amount: {kind: 'share_quantity', quantityMicros: '2'},
      pricePaperMicros: '1000000', cashPaperMicros: '0', position: {quantityMicros: '1', costBasisPaperMicros: '1'}}),
    fails('PAPER_POSITION_INSUFFICIENT'));
    assert.throws(() => calculatePaperOrder({action: 'sell', amount: {kind: 'paper_amount', paperMicros: '1'},
      pricePaperMicros: '1000000', cashPaperMicros: '0', position: {quantityMicros: '1', costBasisPaperMicros: '1'}}),
    fails('PAPER_ORDER_INVALID'));
  });
});
