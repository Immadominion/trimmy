import assert from 'node:assert/strict';
import test from 'node:test';
import {amountRaw} from '../src/product/money/amounts.js';
import {setLocale} from '../src/i18n/runtime.js';

test('an English amount typed on a comma keypad is a half, and an ambiguous comma is refused, never multiplied', async () => {
  await setLocale('en');
  assert.equal(amountRaw('0,5', 9), '500000000');
  assert.equal(amountRaw('7,50', 6), '7500000');
  assert.equal(amountRaw('1,000', 6), null);
  assert.equal(amountRaw('0.5', 9), '500000000');
});
