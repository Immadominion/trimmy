import assert from 'node:assert/strict';
import test from 'node:test';
import {act, createElement, useEffect} from 'react';
import {useMoney} from '../src/product/money/money-api.js';
import {maxRaw, recipientAddress, sendableAssets} from '../src/product/money/send-money-sheet.js';
import {parseTransferReview, TransferError, WalletTransferClient} from '../src/product/money/wallet-transfer-client.js';
import {parseHoldings} from '../src/product/money/wallet-models.js';
import {moneyPage} from './support/money-dom.js';
import {apiVerifier} from './support/money-harness.js';
import {ACCOUNT_ID, holdingsJson, message, stockHolding, unsigned} from './support/money-fixtures.js';

const fixtureModule = new URL('../../../tool/testing/client-send-fixtures.mjs', import.meta.url).href;
const {buildSendReview} = await import(fixtureModule);

const FRIEND = '9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM';
const USDC = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
const base64 = (bytes: Uint8Array) => Buffer.from(bytes).toString('base64');

function review(from: string, overrides: Record<string, unknown> = {}) {
  return {id:'77777777-7777-4777-8777-777777777777',review: {asset: {kind: 'token', mint: USDC, symbol: 'USDC', decimals: 6, uiMultiplier: '1'}, from, destination: FRIEND,
    amountRaw: '5000000', receivedRaw: '5000000', createsAccount: true, accountRentLamports: '2039280', networkFeeLamports: '8000',
    expiresAt: new Date(Date.now() + 60_000).toISOString(), ...overrides},
    unsignedTransaction: base64(unsigned(message([from], {version: 0}), 1)), reviewToken: 'payload.mac'};
}

test('Send reviews on the server, signs once with the embedded wallet, sends and confirms', async () => {
  const page = await moneyPage();
  const verify = await apiVerifier();
  const unsignedWire = (await buildSendReview({wallet: page.user.address})).unsignedTransaction;
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
    assert.equal(page.calls.some(call => call.path.startsWith('/v1/wallet/transfers') && call.method==='POST'), false, 'checked before asking the server');
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

test('a lost send reply recovers its persisted review, including after closing and reopening',async()=>{
 const page=await moneyPage();let broadcasts=0;
 const id='77777777-7777-4777-8777-777777777777',signature='5'.repeat(88);
 const valid = {...review(page.user.address), unsignedTransaction:(await buildSendReview({wallet:page.user.address})).unsignedTransaction};
 const saved={...valid,status:'pending',signature};
 page.server.reply=call=>{
  if(call.path.startsWith('/v1/wallet/transfers/recovery'))return Response.json({transfer:broadcasts?saved:null});
  if(call.path==='/v1/wallet/transfers/preview')return Response.json(valid);
  if(call.path==='/v1/wallet/transfers/execute'){broadcasts++;throw Error('reply lost after submission');}
  if(call.path.startsWith('/v1/wallet/transfers/status'))return Response.json({status:'pending',slot:null});
  return undefined;
 };
 function Open(){const money=useMoney();useEffect(()=>money.openSend(),[]);return createElement('button',{onClick:()=>money.openSend()},'Reopen send');}
 try {
  await page.render(createElement(Open));
  await page.waitFor(()=>page.button('Review send')?.disabled===false,'recovery complete');
  await page.type('[data-testid="send-destination"]',FRIEND);await page.type('[data-testid="send-amount"]','5');
  await page.click('Review send');await page.waitFor(()=>!!page.button('Send now'),'review');await page.click('Send now');
  await page.waitFor(()=>page.dom.window.document.querySelector('[data-testid="send-result"]')?.textContent === 'Sending','recovered send');
  assert.equal(broadcasts,1);assert.equal(page.privy.signs,1);
  assert.ok(page.calls.some(call=>call.path===`/v1/wallet/transfers/recovery?id=${id}`));
  await page.click('Close');await page.click('Reopen send');
  await page.waitFor(()=>page.dom.window.document.querySelector('[data-testid="send-result"]')?.textContent === 'Sending','restored send');
  assert.equal(broadcasts,1);assert.equal(page.privy.signs,1);
  assert.equal(page.button('Send now'),undefined);
 }finally{await page.close();}
});


test('send storage failures prevent submission and recovery ids stay scoped to the account', async () => {
  const saved = new Map<string, string>();
  const storage = {getItem: (key: string) => saved.get(key) ?? null,
    setItem: (key: string, value: string) => {saved.set(key, value);},
    removeItem: (key: string) => {saved.delete(key);}};
  const calls: string[] = [];
  const options = {baseUrl: 'https://api.example', bearer: async () => 'aaa.bbb.ccc', storage,
    fetch: (async (url: string | URL | Request) => {
      calls.push(String(url));
      if (String(url).endsWith('/execute')) return Response.json({signature: '5'.repeat(88)});
      return Response.json({transfer: null});
    }) as typeof fetch};
  const client = new WalletTransferClient({...options, accountId: 'account-a'});
  const other = new WalletTransferClient({...options, accountId: 'account-b'});
  const parsed = parseTransferReview(review(FRIEND));
  const blocked = new WalletTransferClient({...options, accountId: 'account-a', storage: {...storage,
    setItem: () => {throw Error('storage full');}}});
  await assert.rejects(blocked.execute(parsed, 'signed'), {code: 'TRANSFER_STORAGE'});
  assert.equal(calls.length, 0);
  await client.execute(parsed, 'signed');
  assert.equal(saved.size, 1);
  await other.recovery();
  assert.ok(calls.at(-1)?.endsWith('/recovery'), 'the other account never asks for this review id');
  await assert.rejects(client.recovery(), {code: 'TRANSFER_UNAVAILABLE'}, 'a missing saved send does not permit an unsafe retry');
  assert.ok(calls.at(-1)?.endsWith(`/recovery?id=${parsed.id}`));
  client.acknowledge();
  assert.equal(saved.size, 0);
});


test('wallet refreshes do not restart the pending send observation window', async () => {
  const page = await moneyPage();
  let poll: (() => void) | undefined, watches = 0;
  const interval = page.dom.window.setInterval.bind(page.dom.window);
  const clear = page.dom.window.clearInterval.bind(page.dom.window);
  page.dom.window.setInterval = ((callback: () => void, ms: number) => {
    if (ms !== 2000) return interval(callback, ms);
    watches += 1; poll = callback; return -1;
  }) as typeof page.dom.window.setInterval;
  page.dom.window.clearInterval = (id: number | undefined) => {if (id === -1) poll = undefined; else clear(id);};
  page.server.reply = call => {
    if (call.path.startsWith('/v1/wallet/transfers/recovery')) return Response.json({transfer: {
      ...review(page.user.address), status: 'pending', signature: '5'.repeat(88)}});
    if (call.path.startsWith('/v1/wallet/transfers/status')) return Response.json({status: 'pending', slot: null});
    return undefined;
  };
  function Open() {
    const money = useMoney(); useEffect(() => money.openSend(), []);
    return createElement('button', {onClick: () => money.setReal(!money.real)}, 'Refresh provider');
  }
  try {
    await page.render(createElement(Open));
    await page.waitFor(() => !!poll, 'pending watch');
    for (let i = 0; i < 30; i += 1) {
      await page.click('Refresh provider');
      await act(async () => {poll?.();}); await page.flush();
    }
    assert.equal(watches, 1);
    assert.match(page.text(), /Still confirming/);
    assert.match(page.text(), /Don’t send it again/);
  } finally {await page.close();}
});


test('a send with hidden extra outflow is refused before the SDK can sign', async () => {
  const page = await moneyPage();
  const changed = await buildSendReview({wallet: page.user.address, mutation: 'extra-sol'});
  const response = {...review(page.user.address), unsignedTransaction: changed.unsignedTransaction};
  page.server.reply = call => call.path === '/v1/wallet/transfers/preview' ? Response.json(response) : undefined;
  function Open() {const money = useMoney(); useEffect(() => money.openSend(), []); return null;}
  try {
    await page.render(createElement(Open));
    await page.waitFor(() => page.button('Review send')?.disabled === false, 'send ready');
    await page.type('[data-testid="send-destination"]', FRIEND); await page.type('[data-testid="send-amount"]', '5');
    await page.click('Review send'); await page.waitFor(() => !!page.button('Send now'), 'review');
    await page.click('Send now');
    assert.match(page.text(), /doesn’t match your review/);
    assert.equal(page.privy.signs, 0);
    assert.equal(page.calls.some(call => call.path.endsWith('/execute')), false);
  } finally {await page.close();}
});

test('a pasted address is trimmed and read exactly, never cut or stripped into a different address', () => {
  assert.equal(recipientAddress(` ${FRIEND}\n`), FRIEND, 'a leading space or line break no longer costs the last character');
  assert.equal(recipientAddress(`solana:${FRIEND}`), FRIEND, 'a plain payment link gives its address');
  assert.equal(recipientAddress(`solana:${FRIEND}?amount=1`), `solana:${FRIEND}?amount=1`, 'a link that asks for more is refused, not half-read');
  assert.equal(recipientAddress(`${FRIEND}l`), `${FRIEND}l`, 'a character outside the address alphabet stays, so the address is refused');
  assert.equal(recipientAddress(FRIEND.toLowerCase()), FRIEND.toLowerCase());
});
