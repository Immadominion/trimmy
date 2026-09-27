import assert from 'node:assert/strict';
import test from 'node:test';
import {act} from 'react';
import {MINT, MemoryStorage, ORDER_ID, harness} from './support/product-harness.js';
import type {Harness} from './support/product-harness.js';
import {JourneyStore} from '../src/product/journey-store.js';

const AT = '2026-09-27T09:00:00.000Z';
function chosenGuest() {const storage = new MemoryStorage(); new JourneyStore(storage, '/api').chooseGuest(); return storage;}
async function type(h: Harness, selector: string, value: string) {
  const field = h.dom.window.document.querySelector<HTMLInputElement>(selector); assert.ok(field, selector);
  await act(async () => {Object.getOwnPropertyDescriptor(h.dom.window.HTMLInputElement.prototype, 'value')!.set!.call(field, value); field.dispatchEvent(new h.dom.window.Event('input', {bubbles: true}));});
  await h.flush();
}
const post = (id: string, socialId: string, handle: string, following = false) => ({reasonId: id, socialId, handle, persona: 'wolf', assetId: 'apple', variantMint: MINT,
  symbol: 'AAPLx', note: `${handle} likes the new phone.`, savedAt: AT, following, notifications: following, isViewer: false});

test('compact Fast buy reviews, confirms and receipts a practice buy, then saves an optional reason', async () => {
  const h = await harness({checkpoint: 'app', savedGuest: true, storage: chosenGuest(), traded: false});
  try {
    await h.app();
    assert.match(h.text(), /Your desk\./);
    await h.click('Fast buy');
    assert.match(h.text(), /Fast buy/); await h.flush(50);
    await h.click('Buy Apple');
    assert.match(h.text(), /Buy Apple/); assert.match(h.text(), /10,000\.00 paper available/);
    await h.click('Review buy');
    assert.equal(h.api.calls.filter(call => call.path.endsWith('/preview')).length, 1);
    assert.equal(h.api.calls.some(call => call.path.endsWith('/commit')), false, 'review never commits');
    assert.match(h.text(), /Review your buy\./);
    await h.click('Confirm buy');
    assert.equal(h.api.calls.filter(call => call.path.endsWith('/commit')).length, 1);
    assert.match(h.text(), /Buy confirmed/); assert.match(h.text(), /Bought 2 shares of Apple\./); assert.match(h.text(), /No real money was moved\./);
    await type(h, '#fast-buy-reason', 'Everyone I know uses one.');
    await h.click('Save reason');
    const reason = h.api.calls.find(call => call.path === '/v1/career/trade-reasons' && call.method === 'POST');
    assert.equal(reason?.body?.['orderId'], ORDER_ID); assert.equal(reason?.body?.['note'], 'Everyone I know uses one.');
    assert.match(h.text(), /Reason saved · \+20 Trims/);
    await h.click('Done');
    assert.equal(h.dom.window.document.querySelector('.fast-buy'), null);
  } finally {await h.close();}
});

test('a guest Home invites a trader choice and points Community at sign-in, without an Updates inbox', async () => {
  const h = await harness({checkpoint: 'app', savedGuest: true, storage: chosenGuest()});
  try {
    await h.app();
    assert.match(h.text(), /Pick your trader/); assert.match(h.text(), /Make this desk yours\./);
    assert.equal(h.button('Updates'), undefined);
    assert.match(h.text(), /See what traders are saying/);
    assert.equal(h.api.calls.some(call => call.path === '/v1/community'), false, 'guests never read the account-only feed');
    await h.click('Pick your trader'); assert.equal(h.dom.window.location.hash, '#profile');
  } finally {await h.close();}
});

test('an account Home previews Community, opens it, and the Updates inbox is the notifications scope', async () => {
  const h = await harness({account: true, checkpoint: 'app'});
  try {
    h.api.state.community = [post('77777777-7777-4777-8777-777777777777', '99999999-9999-4999-8999-999999999999', 'tradermia')];
    await h.app();
    assert.match(h.text(), /@tradermia on \$AAPLx/);
    await h.click('Updates');
    assert.equal(h.dom.window.location.hash, '#updates');
    assert.match(h.text(), /Updates/); assert.match(h.text(), /You’re all caught up/); assert.match(h.text(), /New comments from people you follow appear here\./);
    assert.ok(h.api.calls.some(call => call.path === '/v1/community' && call.url.includes('scope=notifications')));
  } finally {await h.close();}
});

test('Community follows, mutes, reports and blocks traders through the account routes', async () => {
  const socialId = '99999999-9999-4999-8999-999999999999';
  const h = await harness({account: true, checkpoint: 'app', hash: '#community'});
  try {
    h.api.state.community = [post('77777777-7777-4777-8777-777777777777', socialId, 'tradermia')];
    await h.app();
    assert.match(h.text(), /Community/); assert.match(h.text(), /tradermia likes the new phone\./);
    await h.click('+ Follow');
    const follow = h.api.calls.find(call => call.path === `/v1/community/following/${socialId}`);
    assert.deepEqual(follow?.body, {following: true, notifications: true});
    await h.click('Following', );
    await h.click('Comment options'); await h.click('Mute updates');
    assert.deepEqual(h.api.calls.filter(call => call.path === `/v1/community/following/${socialId}`).at(-1)?.body, {following: true, notifications: false});
    await h.click('Everyone'); await h.click('Comment options'); await h.click('Block trader');
    assert.deepEqual(h.api.state.blocks, [socialId]); assert.match(h.text(), /@tradermia is blocked\./);
    assert.doesNotMatch(h.text(), /tradermia likes the new phone\./);
  } finally {await h.close();}
});

test('a guest opening Community is asked to sign in instead of seeing an empty feed', async () => {
  const h = await harness({checkpoint: 'app', savedGuest: true, storage: chosenGuest(), hash: '#community'});
  try {
    await h.app();
    assert.match(h.text(), /Sign in to join the Trimmy community\./);
    assert.equal(h.api.calls.some(call => call.path === '/v1/community'), false);
  } finally {await h.close();}
});
