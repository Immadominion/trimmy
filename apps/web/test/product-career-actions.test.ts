import assert from 'node:assert/strict';
import test from 'node:test';
import {act} from 'react';
import {ORDER_ID, MemoryStorage, harness} from './support/product-harness.js';
import type {Harness} from './support/product-harness.js';
import {JourneyStore} from '../src/product/journey-store.js';
import {browserTimeZone, careerDayRefreshDelay} from '../src/product/use-career-day-context.js';
import {eligiblePromotion, selectReasonTarget} from '../src/product/career-milestones.js';

const AT = '2026-09-27T09:00:00.000Z';
const mission = (id: string, kind: 'action' | 'promotion', status: 'locked' | 'ready' | 'complete', order: number, promotesToRank: string | null = null) => ({
  id, chapterRank: 'rookie', order, kind, title: {'first-paper-buy': 'Make your first paper buy', 'write-a-reason': 'Write a reason', 'hold-through-red-day': 'Hold through a red day'}[id],
  instruction: 'Follow the milestone.', trimsReward: 20, promotesToRank, status, completedAt: status === 'complete' ? AT : null});
function chosenGuest() {const storage = new MemoryStorage(); new JourneyStore(storage, '/api').chooseGuest(); return storage;}
async function openProgress(h: Harness, rank = 'Rookie') {await h.app(); await h.click('Career'); await h.click(rank);}
async function typeNote(h: Harness, value: string) {
  const field = h.dom.window.document.querySelector<HTMLInputElement>('#reason-note'); assert.ok(field);
  await act(async () => {Object.getOwnPropertyDescriptor(h.dom.window.HTMLInputElement.prototype, 'value')!.set!.call(field, value); field.dispatchEvent(new h.dom.window.Event('input', {bubbles: true}));});
  await h.flush();
}

test('an earned promotion is claimed on the web with a durable mutation and celebrated like mobile', async () => {
  const h = await harness({checkpoint: 'app', savedGuest: true, storage: chosenGuest()});
  try {
    h.api.state.career = {revision: 3, total: 300, rank: 'rookie', next: {id: 'analyst', label: 'Analyst', threshold: 300, trimsRemaining: 0, promotionRequired: true}};
    h.api.state.missions = [mission('first-paper-buy', 'action', 'complete', 1), mission('write-a-reason', 'action', 'complete', 2), mission('hold-through-red-day', 'promotion', 'complete', 3, 'analyst')];
    await openProgress(h);
    assert.doesNotMatch(h.text(), /Continue on mobile/);
    await h.click('Become Analyst');
    const promotion = h.api.calls.find(call => call.path === '/v1/career/promotions');
    assert.equal(promotion?.body?.['targetRank'], 'analyst'); assert.equal(promotion?.body?.['schemaVersion'], 1);
    assert.match(h.text(), /You’re an Analyst!/); assert.match(h.text(), /A new chapter on the floor\./); assert.match(h.text(), /100 Trims/);
    await h.click('Back to Career');
    await h.click('Analyst');
    assert.match(h.text(), /Analyst unlocked/); assert.match(h.text(), /\+100 Trims/);
    assert.equal(h.api.calls.filter(call => call.path === '/v1/career/promotions').length, 1);
  } finally {await h.close();}
});

test('Comment on your trade saves a one-line reason for the first confirmed buy still held', async () => {
  const h = await harness({checkpoint: 'app', savedGuest: true, storage: chosenGuest()});
  try {
    h.api.state.missions = [mission('first-paper-buy', 'action', 'complete', 1), mission('write-a-reason', 'action', 'ready', 2), mission('hold-through-red-day', 'promotion', 'locked', 3, 'analyst')];
    await openProgress(h);
    assert.match(h.text(), /Comment on your trade/);
    await h.click('Write a comment');
    assert.match(h.text(), /Write your reason/); assert.match(h.text(), /What made you buy\?/); assert.match(h.text(), /AAPLx · 2 shares held/);
    assert.equal(h.button('Save reason')?.disabled, true);
    await typeNote(h, 'I use their phone every day.');
    await h.click('Save reason');
    const saved = h.api.calls.find(call => call.path === '/v1/career/trade-reasons' && call.method === 'POST');
    assert.equal(saved?.body?.['orderId'], ORDER_ID); assert.equal(saved?.body?.['note'], 'I use their phone every day.');
    assert.match(h.text(), /Reason saved/); assert.match(h.text(), /\+20 Trims/);
  } finally {await h.close();}
});

test('an unconfirmed reason keeps the exact command and Retry reason replays it', async () => {
  let lose = true;
  const h = await harness({checkpoint: 'app', savedGuest: true, storage: chosenGuest(), reply: call => {
    if (call.path === '/v1/career/trade-reasons' && call.method === 'POST' && lose) {lose = false; throw new TypeError('Lost');}
    return undefined;
  }});
  try {
    h.api.state.missions = [mission('write-a-reason', 'action', 'ready', 1)];
    await openProgress(h); await h.click('Write a comment'); await typeNote(h, 'Long-term hold.'); await h.click('Save reason');
    assert.match(h.text(), /You are offline\. Your reason was not saved\. Try again\./);
    await h.click('Retry reason');
    const posts = h.api.calls.filter(call => call.path === '/v1/career/trade-reasons' && call.method === 'POST');
    assert.equal(posts.length, 2); assert.deepEqual(posts[1]?.body, posts[0]?.body);
    assert.match(h.text(), /Reason saved/);
  } finally {await h.close();}
});

test('a ready first-buy milestone opens the Market instead of sending people to mobile', async () => {
  const h = await harness({checkpoint: 'app', savedGuest: true, storage: chosenGuest()});
  try {
    h.api.state.missions = [mission('first-paper-buy', 'action', 'ready', 1)];
    await openProgress(h); await h.click('Find a stock');
    assert.equal(h.dom.window.location.hash, '#market');
  } finally {await h.close();}
});

test('a web-first desk configures its Career day once with this browser’s time zone', async () => {
  const h = await harness({checkpoint: 'app', savedGuest: true, storage: chosenGuest()});
  try {
    await h.app(); await h.flush(50);
    const zone = browserTimeZone(), puts = h.api.calls.filter(call => call.path === '/v1/career/day-context' && call.method === 'PUT');
    if (zone) {
      assert.equal(puts.length, 1); assert.equal(puts[0]?.body?.['timeZone'], zone); assert.equal(puts[0]?.body?.['baseRevision'], 1);
      assert.equal(h.api.state.dayContext['configured'], true);
    } else assert.equal(puts.length, 0, 'no IANA zone is invented');
    await h.reload(); await h.flush(50);
    assert.equal(h.api.calls.filter(call => call.path === '/v1/career/day-context' && call.method === 'PUT').length, zone ? 1 : 0, 'a configured day is never changed');
  } finally {await h.close();}
});

test('Career rules: promotion eligibility, reason targets and the next-day refresh match mobile', () => {
  const summary = {revision: 3, rank: {id: 'rookie'}, nextRank: {id: 'analyst', trimsRemaining: 0, promotionRequired: true}} as never;
  const board = (revision: number, status: string) => ({revision, currentRank: 'rookie', missions: [{id: 'hold-through-red-day', kind: 'promotion', chapterRank: 'rookie', promotesToRank: 'analyst', status}]}) as never;
  assert.equal(eligiblePromotion(summary, board(3, 'complete'))?.id, 'hold-through-red-day');
  assert.equal(eligiblePromotion(summary, board(2, 'complete')), null, 'an incoherent board never promotes');
  assert.equal(eligiblePromotion(summary, board(3, 'ready')), null);
  const portfolio = {positions: [{assetId: 'apple', variantMint: 'm', quantityMicros: '1'}, {assetId: 'tesla', variantMint: 't', quantityMicros: '0'}],
    recentOrders: [{id: 'b', action: 'buy', assetId: 'tesla', variantMint: 't', symbol: 'TSLAx', committedAt: AT}, {id: 'a', action: 'buy', assetId: 'apple', variantMint: 'm', symbol: 'AAPLx', committedAt: '2026-09-26T09:00:00.000Z'}]} as never;
  assert.equal(selectReasonTarget(portfolio, null)?.orderId, 'a', 'a sold position is skipped for the newest held buy');
  assert.equal(selectReasonTarget(portfolio, null, new Set(['a'])), null);
  const now = Date.parse(AT);
  assert.equal(careerDayRefreshDelay(now, new Date(now + 60_000).toISOString()), 62_000);
  assert.equal(careerDayRefreshDelay(now, new Date(now - 60_000).toISOString()), 15 * 60_000);
  assert.equal(careerDayRefreshDelay(now, null), 15 * 60_000);
});
