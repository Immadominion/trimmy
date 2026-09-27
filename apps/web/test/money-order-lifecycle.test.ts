import assert from 'node:assert/strict';
import test from 'node:test';
import {base64ToBytes, parseTransaction} from '../src/product/money/solana-wire.js';
import {MemoryStorage, moneyHarness, until} from './support/money-harness.js';
import {AAPLX} from './support/money-fixtures.js';

async function reviewed(h: Awaited<ReturnType<typeof moneyHarness>>, mint = AAPLX, side: 'buy' | 'sell' = 'buy', amountRaw = '5000000') {
  const session = h.session();
  await session.restore();
  assert.equal(session.getState().phase, 'entry');
  const asset = h.capabilities.forMint(mint)!, issuer = h.capabilities.issuerFor(asset);
  await session.preview({asset, issuer, side, amountRaw, legacy: false, spendable: () => ({raw: null, fresh: false})});
  return session;
}

test('an aggregator order is previewed with its issuer terms, signed exactly, remembered before execute, then reconciled', async () => {
  const h = await moneyHarness();
  h.server.settle.push('pending', 'pending', 'confirmed');
  let rememberedAtExecute: string | null = null;
  h.server.reply = call => {if (call.path === '/v1/trading/execute') rememberedAtExecute = h.pending.read(); return undefined;};
  const session = await reviewed(h);
  const preview = h.calls.find(call => call.path === '/v1/trading/preview')!;
  assert.deepEqual(preview.body, {assetId: 'apple', variantMint: AAPLX, side: 'buy', amountRaw: '5000000',
    termsAccepted: {issuerId: 'xstocks', version: '2026-09-27'}});
  const order = session.getState().order!;
  assert.equal(session.getState().phase, 'reviewed'); assert.equal(order.terms.route, 'aggregator');
  await session.confirm();
  assert.equal(rememberedAtExecute, order.id, 'the order id is stored before execute is sent');
  const execute = h.calls.filter(call => call.path === '/v1/trading/execute');
  assert.equal(execute.length, 1); assert.equal(execute[0]!.body!['reviewDigest'], order.reviewDigest);
  assert.ok(String(execute[0]!.body!['signedTransaction']).length <= 1644);
  assert.equal(session.getState().phase, 'pending');
  await until(() => session.getState().phase === 'confirmed', 'confirmation');
  assert.equal(h.pending.read(), null, 'a settled order is forgotten');
  await until(() => h.calls.some(call => call.path === '/v1/account/holdings' && call.headers.get('x-trimmy-holdings-min-slot') === '900'), 'post-trade holdings read');
  assert.equal(h.calls.filter(call => call.path === '/v1/trading/execute').length, 1);
  session.dispose();
});

test('an RFQ order is signed in the taker slot only and the review says the maker delivers at fill', async () => {
  const h = await moneyHarness({route: 'rfq'});
  h.server.settle.push('confirmed');
  const meta = h.capabilities.assets.find(asset => asset.symbol === 'METAon')!;
  const session = await reviewed(h, meta.mint, 'buy', '2000000');
  const order = session.getState().order!;
  assert.equal(order.terms.route, 'rfq'); assert.equal(order.terms.settlement, 'maker_delivers_at_fill');
  assert.equal(parseTransaction(base64ToBytes(order.transaction!)).signatures.length, 2);
  await session.confirm();
  const signed = String(h.calls.find(call => call.path === '/v1/trading/execute')!.body!['signedTransaction']);
  const parsed = parseTransaction(base64ToBytes(signed));
  assert.equal(parsed.signers[0], h.maker.address);
  assert.equal(parsed.signatures[0]!.every(byte => byte === 0), true, 'the market maker slot is left for the maker');
  assert.equal(parsed.signatures[1]!.some(byte => byte !== 0), true);
  assert.equal(session.getState().phase, 'confirmed', 'the API verifier accepted the web signature');
  session.dispose();
});

test('a lost execute reply is reconciled by id, never resent, including after a reload', async () => {
  const h = await moneyHarness();
  h.server.settle.push('pending');
  let drop = true;
  const realFetch = h.server.reply;
  h.server.reply = async call => {
    if (call.path === '/v1/trading/execute' && drop) {
      drop = false;
      // The API receives and dispatches the order, but the browser never sees the reply.
      const order = h.orders.get(String(call.body!['id']))!;
      order.json = {...order.json, status: 'pending', signature: '3'.repeat(88)};
      throw new TypeError('connection reset');
    }
    return realFetch?.(call);
  };
  const first = await reviewed(h);
  const id = first.getState().order!.id;
  await first.confirm();
  assert.equal(first.getState().phase, 'pending');
  assert.equal(first.getState().notice, 'Checking the result. Your order won’t be sent twice.');
  assert.equal(h.pending.read(), id);
  first.dispose(); // The tab closes before the result is known.
  h.server.settle.push('pending', 'failed');
  const reload = h.session();
  await reload.restore();
  assert.equal(reload.getState().phase, 'pending');
  assert.equal(h.calls.filter(call => call.path === `/v1/trading/order/${id}`).length >= 1, true);
  await until(() => reload.getState().phase === 'failed', 'failed settlement');
  assert.equal(h.pending.read(), null);
  assert.equal(h.calls.filter(call => call.path === '/v1/trading/execute').length, 1, 'recovery never dispatches again');
  reload.dispose();
});

test('an order that never reached the API shows as checking until its quote expires, then expires', async () => {
  const h = await moneyHarness();
  h.server.expiresInMs = 150;
  h.server.reply = call => call.path === '/v1/trading/execute' ? Promise.reject(new TypeError('offline')) : undefined;
  const session = await reviewed(h);
  await session.confirm();
  assert.equal(session.getState().phase, 'pending');
  await until(() => session.getState().phase === 'expired', 'expiry of the undelivered order', 3000);
  assert.equal(h.pending.read(), null);
  session.dispose();
});

test('nothing is sent when the order id cannot be kept, the wallet declines, or the API refuses before dispatch', async () => {
  const blocked = new MemoryStorage();
  const h = await moneyHarness({storage: blocked});
  const session = await reviewed(h);
  blocked.blocked = true;
  await session.confirm();
  assert.equal(session.getState().phase, 'reviewed');
  assert.equal(session.getState().notice, 'Allow browser storage so Trimmy can keep track of this order. No order was sent.');
  assert.equal(h.calls.some(call => call.path === '/v1/trading/execute'), false);
  blocked.blocked = false;
  h.privy.sign = async () => {throw new Error('User rejected');};
  await session.confirm();
  assert.equal(session.getState().notice, 'Signing didn’t finish. No order was sent.');
  assert.equal(h.calls.some(call => call.path === '/v1/trading/execute'), false);
  h.privy.sign = null;
  h.server.reply = call => call.path === '/v1/trading/execute' ? Response.json({code: 'QUOTE_EXPIRED'}, {status: 409}) : undefined;
  await session.confirm();
  assert.equal(session.getState().phase, 'expired'); assert.equal(h.pending.read(), null);
  assert.equal(session.getState().notice, 'That price expired. Get a fresh quote.');
  session.dispose();
});

test('preview refusals map to mobile’s copy and the right next step', async () => {
  const h = await moneyHarness();
  const session = h.session();
  await session.restore();
  const asset = h.capabilities.forMint(AAPLX)!, issuer = h.capabilities.issuerFor(asset);
  const preview = () => session.preview({asset, issuer, side: 'buy', amountRaw: '5000000', legacy: false, spendable: () => ({raw: null, fresh: false})});
  const cases: [string, string, Partial<{fundingNeeded: boolean; termsRequired: boolean}>][] = [
    ['TERMS_REQUIRED', 'Confirm the issuer terms to continue.', {termsRequired: true}],
    ['MARKET_CLOSED', 'This stock trades while US markets are open. Try again then.', {}],
    ['BELOW_MINIMUM', 'This order is under the market maker’s minimum. Try a larger amount.', {}],
    ['ADD_SOL', 'Add SOL to cover network and account fees.', {fundingNeeded: true}],
    ['FEE_TOO_HIGH', 'The fees are too high for this order. Try later.', {}],
    ['NO_ROUTE', 'No route for this order right now. Try another amount.', {}],
  ];
  for (const [code, copy, flags] of cases) {
    h.server.reply = call => call.path === '/v1/trading/preview' ? Response.json({code}, {status: 409}) : undefined;
    await preview();
    const state = session.getState();
    assert.equal(state.phase, 'entry', code); assert.equal(state.notice, copy, code);
    assert.equal(state.fundingNeeded, flags.fundingNeeded ?? false, code); assert.equal(state.termsRequired, flags.termsRequired ?? false, code);
  }
  // A fresh balance below the amount is caught before any quote is requested.
  h.server.reply = null; h.server.usdc = '1000000';
  const before = h.calls.filter(call => call.path === '/v1/trading/preview').length;
  await session.preview({asset, issuer, side: 'buy', amountRaw: '5000000', legacy: false,
    spendable: () => ({raw: '1000000', fresh: true})});
  assert.equal(session.getState().notice, 'Add USDC to your Solana wallet first.'); assert.equal(session.getState().fundingNeeded, true);
  assert.equal(h.calls.filter(call => call.path === '/v1/trading/preview').length, before);
  session.dispose();
});

test('ORDER_PENDING on preview recovers the confirming order, and an identity change stops the flow', async () => {
  const h = await moneyHarness();
  const first = await reviewed(h);
  h.server.settle.push('pending', 'pending', 'pending', 'pending', 'pending', 'pending', 'pending', 'pending', 'pending', 'pending');
  await first.confirm();
  first.dispose();
  const second = h.session();
  // Another tab: the latest order is pending, so restore shows it before a new quote.
  await second.restore();
  assert.equal(second.getState().phase, 'pending');
  second.dispose();
  // A tab with no local record starts at entry; the API's ORDER_PENDING then brings the confirming order back.
  const third = h.session();
  h.pending.clear();
  let hidden = true;
  h.server.reply = call => {
    if (call.path === '/v1/trading/order' && hidden) return Response.json({order: null});
    if (call.path === '/v1/trading/preview') {hidden = false; return Response.json({code: 'ORDER_PENDING'}, {status: 409});}
    return undefined;
  };
  await third.restore();
  assert.equal(third.getState().phase, 'entry');
  const asset = h.capabilities.forMint(AAPLX)!;
  await third.preview({asset, issuer: h.capabilities.issuerFor(asset), side: 'buy', amountRaw: '5000000', legacy: false, spendable: () => ({raw: null, fresh: false})});
  assert.equal(third.getState().phase, 'pending', 'the latest pending order is shown even without a local record');
  h.identity.abort();
  await third.check();
  assert.equal(third.getState().phase, 'account-changed');
  third.dispose();
});

test('a reviewed quote expires on time and cannot be confirmed afterwards', async () => {
  const h = await moneyHarness();
  h.server.expiresInMs = 40;
  const session = await reviewed(h);
  await until(() => session.getState().phase === 'expired', 'quote expiry');
  await session.confirm();
  assert.equal(h.privy.signs, 0); assert.equal(h.calls.some(call => call.path === '/v1/trading/execute'), false);
  session.reset();
  assert.equal(session.getState().phase, 'entry');
  session.dispose();
});
