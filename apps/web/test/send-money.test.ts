import assert from 'node:assert/strict';
import test from 'node:test';
import {createElement, useEffect} from 'react';
import {useMoney} from '../src/product/money/money-api.js';
import {maxRaw, sendableAssets} from '../src/product/money/send-money-sheet.js';
import {parseTransferReview, TransferError} from '../src/product/money/wallet-transfer-client.js';
import {parseHoldings} from '../src/product/money/wallet-models.js';
import {moneyPage} from './support/money-dom.js';
import {apiVerifier} from './support/money-harness.js';
import {ACCOUNT_ID, holdingsJson, message, stockHolding, unsigned} from './support/money-fixtures.js';

const FRIEND = '9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM';
const USDC = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
const base64 = (bytes: Uint8Array) => Buffer.from(bytes).toString('base64');

function review(from: string, overrides: Record<string, unknown> = {}) {
  return {review: {asset: {kind: 'token', mint: USDC, symbol: 'USDC', decimals: 6, uiMultiplier: '1'}, from, destination: FRIEND,
    amountRaw: '5000000', receivedRaw: '5000000', createsAccount: true, accountRentLamports: '2039280', networkFeeLamports: '8000',
    expiresAt: new Date(Date.now() + 60_000).toISOString(), ...overrides},
    unsignedTransaction: base64(unsigned(message([from], {version: 0}), 1)), reviewToken: 'payload.mac'};
}

test('Send reviews on the server, signs once with the embedded wallet, sends and confirms', async () => {
  const page = await moneyPage();
  const verify = await apiVerifier();
  const unsignedWire = base64(unsigned(message([page.user.address], {version: 0}), 1));
  page.server.reply = call => {
    if (call.path === '/v1/wallet/transfers/preview') return Response.json({...review(page.user.address), unsignedTransaction: unsignedWire});
    if (call.path === '/v1/wallet/transfers/execute') {
      const signature = verify({wallet: page.user.address, unsignedTransaction: unsignedWire}, call.body!['signedTransaction'] as string);
      return Response.json({signature});
    }
    if (call.path.startsWith('/v1/wallet/transfers/status')) return Response.json({status: 'confirmed', slot: 9});
    return undefined;
  };
  function Open() {const money = useMoney(); useEffect(() => {money.openSend();}, []); return null;}
  try {
    await page.render(createElement(Open));
    await page.waitFor(() => page.dom.window.document.querySelector('[data-testid="send-destination"]') !== null, 'send form');
    await page.type('[data-testid="send-destination"]', page.user.address);
    await page.type('[data-testid="send-amount"]', '5');
    await page.click('Review send');
    assert.match(page.text(), /That’s your own wallet/);
    assert.equal(page.calls.some(call => call.path.startsWith('/v1/wallet/transfers')), false, 'checked before asking the server');
    await page.type('[data-testid="send-destination"]', FRIEND);
    await page.click('Review send');
    await page.waitFor(() => /Review|To this Solana wallet/.test(page.text()), 'review');
    const preview = page.calls.find(call => call.path === '/v1/wallet/transfers/preview')!;
    assert.deepEqual(preview.body, {asset: 'USDC', destination: FRIEND, amountRaw: '5000000'});
    assert.equal(preview.headers.get('authorization'), 'Bearer aaa.bbb.ccc');
    assert.equal(page.dom.window.document.querySelector('[data-testid="send-review-destination"]')?.textContent, FRIEND);
    assert.match(page.text(), /Opens their USDC account \(once\)/);
    await page.click('Send now');
    await page.waitFor(() => /^Sent$/.test(page.dom.window.document.querySelector('[data-testid="send-result"]')?.textContent ?? ''), 'confirmed', 6000);
    assert.equal(page.privy.signs, 1);
    const execute = page.calls.find(call => call.path === '/v1/wallet/transfers/execute')!;
    assert.equal(execute.body!['reviewToken'], 'payload.mac');
  } finally {await page.close();}
});

test('Send refuses a review for a different send than was asked, and never signs it', async () => {
  const page = await moneyPage();
  page.server.reply = call => call.path === '/v1/wallet/transfers/preview'
    ? Response.json(review(page.user.address, {destination: 'Xs3oZwbHvqis4NYcf4YKWmEia2eC84wSiVrcYcTqpH8'})) : undefined;
  function Open() {const money = useMoney(); useEffect(() => {money.openSend();}, []); return null;}
  try {
    await page.render(createElement(Open));
    await page.waitFor(() => page.dom.window.document.querySelector('[data-testid="send-destination"]') !== null, 'send form');
    await page.type('[data-testid="send-destination"]', FRIEND);
    await page.type('[data-testid="send-amount"]', '5');
    await page.click('Review send');
    await page.waitFor(() => page.dom.window.document.querySelector('[data-testid="send-message"]') !== null, 'refusal');
    assert.equal(page.button('Send now'), undefined);
    assert.equal(page.privy.signs, 0);
  } finally {await page.close();}
});

test('assets ready to send, stock tokens in shares, and SOL Max keeps a reserve', () => {
  const holdings = parseHoldings(holdingsJson('FVen3X669xLzsi6N2V91DoiyzHzg1uAgqiT8jZ9nS96Z', {lamports: '50000000', usdcAvailable: '20000000',
    tokens: [stockHolding()]}), ACCOUNT_ID);
  const assets = sendableAssets(holdings);
  assert.deepEqual(assets.map(asset => asset.id), ['USDC', 'SOL', 'Xs3oZwbHvqis4NYcf4YKWmEia2eC84wSiVrcYcTqpH8']);
  assert.equal(assets[0]!.availableRaw, '20000000');
  assert.equal(maxRaw(assets[1]!), '48000000');
  assert.equal(assets[2]!.scale.shares('150000000'), '1.501377');
  assert.throws(() => parseTransferReview({...review(FRIEND), reviewToken: 'no dots'}), TransferError);
  assert.throws(() => parseTransferReview(review(FRIEND, {amountRaw: '-1'})), TransferError);
});
