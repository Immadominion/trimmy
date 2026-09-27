import assert from 'node:assert/strict';
import test from 'node:test';
import {act} from 'react';
import {MemoryStorage, TESLA_MINT, harness} from './support/product-harness.js';
import type {Harness} from './support/product-harness.js';
import {JourneyStore} from '../src/product/journey-store.js';

const AT = '2026-09-27T09:00:00.000Z';
function chosenGuest() {const storage = new MemoryStorage(); new JourneyStore(storage, '/api').chooseGuest(); return storage;}
const names = (h: Harness) => [...h.dom.window.document.querySelectorAll('.stock-row strong')].map(node => node.textContent);
async function sortBy(h: Harness, value: string) {
  const select = h.dom.window.document.querySelector<HTMLSelectElement>('select[aria-label="Sort stocks"]'); assert.ok(select);
  await act(async () => {select.value = value; select.dispatchEvent(new h.dom.window.Event('change', {bubbles: true}));}); await h.flush();
}
async function search(h: Harness, value: string) {
  const field = h.dom.window.document.querySelector<HTMLInputElement>('#company-search'); assert.ok(field);
  await act(async () => {Object.getOwnPropertyDescriptor(h.dom.window.HTMLInputElement.prototype, 'value')!.set!.call(field, value); field.dispatchEvent(new h.dom.window.Event('input', {bubbles: true}));});
  await h.flush(450);
}
const reason = (id: string, handle: string, note: string, isViewer = false) => ({reasonId: id, author: {handle, rank: {id: 'rookie', label: 'Rookie'}, isViewer},
  stock: {assetId: 'tesla', variantMint: TESLA_MINT, symbol: 'TSLAx'}, note, savedAt: AT});

test('Market sorts the loaded stocks like mobile without changing what is loaded', async () => {
  const h = await harness({hash: '#market'});
  try {
    await h.app();
    assert.deepEqual(names(h), ['Apple', 'Tesla']);
    const options = [...h.dom.window.document.querySelectorAll('select[aria-label="Sort stocks"] option')].map(node => node.textContent);
    assert.deepEqual(options, ['Featured', 'Name', 'Highest price', 'Biggest gains', 'Biggest drops']);
    await sortBy(h, 'gains'); assert.deepEqual(names(h), ['Tesla', 'Apple']);
    await sortBy(h, 'drops'); assert.deepEqual(names(h), ['Apple', 'Tesla']);
    await sortBy(h, 'price'); assert.deepEqual(names(h), ['Tesla', 'Apple']);
    assert.equal(h.api.calls.filter(call => call.path.endsWith('/catalog')).length, 1);
  } finally {await h.close();}
});

test('a guest Follow asks to sign in and never writes a watchlist', async () => {
  const h = await harness({hash: '#market', checkpoint: 'app', savedGuest: true, storage: chosenGuest()});
  try {
    await h.app(); await h.click('Follow Tesla');
    assert.match(h.text(), /Sign in to save your watchlist\./);
    assert.equal(h.api.calls.some(call => call.path === '/v1/following'), false);
    await h.click('Sign in'); assert.equal(h.dom.window.location.hash, '#sign-in');
  } finally {await h.close();}
});

test('an account follows and unfollows through its real followed list, and the Following tab shows it', async () => {
  const h = await harness({hash: '#market', account: true, checkpoint: 'app'});
  try {
    await h.app();
    await h.click('Following');
    assert.match(h.text(), /Your watchlist starts here\./); assert.match(h.text(), /Tap Follow on a company to keep it here\./);
    await h.click('Find a company');
    await h.click('Follow Tesla');
    const put = h.api.calls.find(call => call.path === '/v1/following' && call.method === 'PUT');
    assert.deepEqual(put?.body?.['assetIds'], ['tesla']); assert.equal(put?.body?.['baseRevision'], 0);
    assert.match(h.text(), /Tesla added to Following\./);
    await h.click('Following'); assert.deepEqual(names(h), ['Tesla']);
    await h.click('Unfollow Tesla'); assert.match(h.text(), /Tesla removed from Following\./);
    assert.equal(h.api.calls.some(call => call.path === '/v1/watchlist'), false, 'the sample watchlist is never used for real follows');
  } finally {await h.close();}
});

test('a Follow that meets a newer list keeps that change and applies this one once', async () => {
  const h = await harness({hash: '#market', account: true, checkpoint: 'app'});
  try {
    await h.app();
    h.api.state.following = {revision: 4, assetIds: ['apple'], updatedAt: AT};
    await h.click('Follow Tesla');
    const puts = h.api.calls.filter(call => call.path === '/v1/following' && call.method === 'PUT');
    assert.equal(puts.length, 2); assert.deepEqual(puts[1]?.body?.['assetIds'], ['apple', 'tesla']); assert.equal(puts[1]?.body?.['baseRevision'], 4);
    assert.deepEqual(h.api.state.following.assetIds, ['apple', 'tesla']);
  } finally {await h.close();}
});

test('companies opened from search become Recently viewed until cleared', async () => {
  const h = await harness({hash: '#market'});
  try {
    await h.app(); await search(h, 'tes');
    await h.click('Open Tesla'); await h.click('← Back to Market');
    assert.match(h.text(), /Recently viewed/);
    assert.ok([...h.dom.window.document.querySelectorAll('.market-recent strong')].some(node => node.textContent === 'Tesla'));
    await h.click('Clear'); assert.doesNotMatch(h.text(), /Recently viewed/);
  } finally {await h.close();}
});

test('the company Holders section shows the public largest-account sample honestly', async () => {
  const h = await harness({hash: `#market/tesla?mint=${TESLA_MINT}`, checkpoint: 'app', savedGuest: true, storage: chosenGuest()});
  const copied: string[] = [];
  Object.defineProperty(h.dom.window.navigator, 'clipboard', {configurable: true, value: {writeText: async (text: string) => {copied.push(text);}}});
  try {
    await h.app(); await h.click('Holders');
    assert.equal(h.api.calls.find(call => call.path === '/v1/markets/stocks/holders')?.method, 'GET');
    assert.match(h.text(), /bigholder\.sol/); assert.match(h.text(), /1,250\.5/); assert.match(h.text(), /Vote…1111/);
    assert.match(h.text(), /Balances from the largest 20 token accounts\. Not the full holder list\./);
    await h.click('Copy address So11111111111111111111111111111111111111112');
    assert.deepEqual(copied, ['So11111111111111111111111111111111111111112']); assert.match(h.text(), /Address copied/);
  } finally {await h.close();}
});

test('company Comments show shared reasons, explain a private own comment and link to Settings', async () => {
  const h = await harness({hash: `#market/tesla?mint=${TESLA_MINT}`, checkpoint: 'app', savedGuest: true, storage: chosenGuest()});
  try {
    h.api.state.sharedReasons = [reason('77777777-7777-4777-8777-777777777777', 'tradermia', 'Deliveries look strong.')];
    h.api.state.ownReasons = [{...reason('88888888-8888-4888-8888-888888888888', 'mydesk', 'My own view.', true), orderId: '33333333-3333-4333-8333-333333333333', deskCycle: 'current'}];
    await h.app();
    assert.match(h.text(), /@tradermia/); assert.match(h.text(), /Deliveries look strong\./); assert.match(h.text(), /Saved 27 Sep 2026/);
    assert.match(h.text(), /Your comment is private\./);
    const everyone = h.api.calls.find(call => call.path === '/v1/career/trade-reasons' && call.url?.includes('scope=everyone'));
    assert.ok(everyone, 'reads the stock-filtered everyone scope');
    assert.equal(h.button('Report'), undefined, 'guests cannot report');
    await h.click('Settings'); assert.equal(h.dom.window.location.hash, '#settings');
  } finally {await h.close();}
});

test('a signed-in account can report a comment, which then leaves the page', async () => {
  const h = await harness({hash: `#market/tesla?mint=${TESLA_MINT}`, account: true, checkpoint: 'app'});
  try {
    h.api.state.sharedReasons = [reason('77777777-7777-4777-8777-777777777777', 'tradermia', 'Buy now!!!')];
    await h.app(); await h.click('Report');
    assert.match(h.text(), /Why are you reporting this\?/); assert.match(h.text(), /The author will not see who reported it\./);
    await h.pick('Spam');
    assert.match(h.text(), /Trimmy will review @tradermia’s comment as spam\./);
    const report = [...h.dom.window.document.querySelectorAll<HTMLButtonElement>('[role="dialog"] button')].find(item => item.textContent === 'Report')!;
    await act(async () => {report.click();}); await h.flush();
    assert.equal(h.api.state.reports[0]?.['category'], 'spam'); assert.equal(h.api.state.reports[0]?.['reasonId'], '77777777-7777-4777-8777-777777777777');
    assert.match(h.text(), /Report received\./); assert.doesNotMatch(h.text(), /Buy now!!!/);
  } finally {await h.close();}
});
