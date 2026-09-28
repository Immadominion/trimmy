import assert from 'node:assert/strict';
import test from 'node:test';
import {holdingValue, stocksValue} from '../src/product/money/holding-values.js';
import type {HoldingsSnapshot, WalletStockBalance} from '../src/product/money/wallet-models.js';

const holding = (mint: string, displayAmount: string | null) => ({mint, assetId: 'apple', name: 'Apple', symbol: 'AAPLx', decimals: 8,
  amountRaw: '2934100', availableToTradeRaw: '2934100', displayAmount}) as unknown as WalletStockBalance;

test('a holding is worth its tokens times that exact token\'s price', () => {
  const prices = new Map([['AAPLx', 340.5]]);
  assert.equal(holdingValue(holding('AAPLx', '0.029341'), prices), 0.029341 * 340.5);
  assert.equal(holdingValue(holding('AAPLon', '1'), prices), null, 'another token of the same company is never used');
  assert.equal(holdingValue(holding('AAPLx', null), prices), null, 'no display amount, no value');
});

test('the stocks total waits until every holding has a price', () => {
  const holdings = {stockTokens: [holding('AAPLx', '0.5'), holding('TSLAx', '0.25')]} as unknown as HoldingsSnapshot;
  assert.equal(stocksValue(holdings, new Map([['AAPLx', 300]])), null);
  assert.equal(stocksValue(holdings, new Map([['AAPLx', 300], ['TSLAx', 400]])), 250);
});
