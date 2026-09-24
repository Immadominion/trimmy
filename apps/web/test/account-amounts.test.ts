import assert from 'node:assert/strict';
import test from 'node:test';
import { formatClockTime, formatRawUnits, shortenAddress } from '../src/account/account-amounts.js';

test('raw units format exactly with grouping and trimmed fractions', () => {
  assert.equal(formatRawUnits('0', 9), '0');
  assert.equal(formatRawUnits('1', 9), '0.000000001');
  assert.equal(formatRawUnits('1000000000', 9), '1');
  assert.equal(formatRawUnits('1500000000', 9), '1.5');
  assert.equal(formatRawUnits('9007199254740991', 9), '9,007,199.254740991');
  assert.equal(formatRawUnits('18446744073709551615', 6), '18,446,744,073,709.551615');
  assert.equal(formatRawUnits('123456', 0), '123,456');
  assert.equal(formatRawUnits('10', 6), '0.00001');
});

test('malformed or unsafe raw units are refused rather than guessed', () => {
  for (const bad of ['', '-1', '01', '1.5', '1e9', ' 1', 'abc', '1'.repeat(41)]) {
    assert.equal(formatRawUnits(bad, 9), null, bad);
  }
  assert.equal(formatRawUnits('1', -1), null);
  assert.equal(formatRawUnits('1', 31), null);
  assert.equal(formatRawUnits('1', 1.5), null);
});

test('addresses shorten from both ends and clock times are two-digit local values', () => {
  assert.equal(shortenAddress('FVen3X669xLzsi6N2V91DoiyzHzg1uAgqiT8jZ9nS96Z'), 'FVen…S96Z');
  assert.equal(shortenAddress('short'), 'short');
  const local = new Date(2026, 8, 15, 7, 5);
  assert.equal(formatClockTime(local.toISOString()), '07:05');
  assert.equal(formatClockTime('not a date'), null);
});
