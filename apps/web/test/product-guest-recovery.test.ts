import assert from 'node:assert/strict';
import test from 'node:test';
import {webcrypto} from 'node:crypto';
import {practiceStorageKey, PracticeSession} from '../src/product/practice-session.js';
import {PracticeClient} from '../src/product/practice-client.js';
import {GUEST_ID, MemoryStorage, harness, json, server} from './support/product-harness.js';

test('a locally expired guest desk opens recovery instead of a retry loop, and issues no new guest', async () => {
  const h = await harness({checkpoint: 'app', savedGuest: true, expireSavedGuest: true});
  try {
    const before = h.storage.getItem(practiceStorageKey('/api')), guestsBefore = h.api.calls.filter(call => call.path === '/v1/guest/session').length;
    await h.app();
    assert.match(h.text(), /Guest session expired/);
    assert.match(h.text(), /Your guest records are preserved\. This desk can no longer trade or be saved to an account\./);
    assert.match(h.text(), /Sign in to open your saved account\. Your guest desk stays untouched\./);
    assert.doesNotMatch(h.text(), /Your desk needs a moment|Try again/);
    assert.equal(h.button('Sign in')?.disabled, true); assert.match(h.text(), /Sign-in is unavailable right now\./);
    assert.equal(h.api.calls.filter(call => call.path === '/v1/guest/session').length, guestsBefore);
    assert.equal(h.storage.getItem(practiceStorageKey('/api')), before, 'nothing is replaced by opening the app');
  } finally {await h.close();}
});

test('starting over is two steps deep; Keep this desk and Escape change nothing', async () => {
  const h = await harness({checkpoint: 'app', savedGuest: true, expireSavedGuest: true});
  try {
    const before = h.storage.getItem(practiceStorageKey('/api'));
    await h.app(); await h.click('Start a new guest desk');
    assert.match(h.text(), /Start fresh\?/); assert.match(h.text(), /This removes this browser’s access to your old desk\. You can’t undo it\./);
    assert.match(h.text(), /Your balance, positions and history won’t move to the new desk\./);
    await h.click('Keep this desk'); assert.match(h.text(), /Guest session expired/);
    await h.click('Start a new guest desk'); await h.escape(); assert.match(h.text(), /Guest session expired/);
    assert.equal(h.storage.getItem(practiceStorageKey('/api')), before);
    assert.equal(h.api.calls.filter(call => call.path === '/v1/guest/session').length, 1);
  } finally {await h.close();}
});

test('a confirmed new desk archives the expired record whole before issuing a fresh guest', async () => {
  const h = await harness({checkpoint: 'app', savedGuest: true, expireSavedGuest: true});
  try {
    const before = h.storage.getItem(practiceStorageKey('/api'))!;
    await h.app(); await h.click('Start a new guest desk'); await h.click('Start a new desk');
    assert.equal(h.storage.getItem(`${practiceStorageKey('/api')}:expired:${GUEST_ID}`), before, 'the old desk is preserved byte for byte');
    assert.equal(h.api.calls.filter(call => call.path === '/v1/guest/session').length, 2);
    assert.match(h.text(), /Your first day starts here\./);
    assert.doesNotMatch(h.text(), /Guest session expired/);
  } finally {await h.close();}
});

test('an API-ended guest desk shows the ended copy and never offers an automatic retry', async () => {
  const h = await harness({checkpoint: 'app', savedGuest: true, reply: call => call.path === '/v1/account/paper/portfolio'
    ? json({error: {code: 'GUEST_SESSION_REVOKED', message: 'Revoked.', requestId: GUEST_ID}}, 401) : undefined});
  try {
    await h.app();
    assert.match(h.text(), /Guest session ended/);
    assert.match(h.text(), /Your guest records are preserved, but this browser can no longer open the desk\./);
  } finally {await h.close();}
});

test('signing in with an expired guest desk keeps it preserved without sending a claim the API must refuse', async () => {
  Object.defineProperty(globalThis, 'crypto', {configurable: true, writable: true, value: webcrypto});
  const api = server({checkpoint: 'app'}), storage = new MemoryStorage();
  const client = new PracticeClient({baseUrl: '/api', fetch: api.fetcher, timeoutMs: 1000});
  const locks = {request: async (_name: string, _options: unknown, callback: () => Promise<unknown>) => callback()} as Pick<LockManager, 'request'>;
  const guest = new PracticeSession({client, storage, locks}); await guest.ensureGuest();
  const key = practiceStorageKey('/api'), record = JSON.parse(storage.getItem(key)!) as {guest: {expiresAt: string; hardExpiresAt: string}};
  record.guest.expiresAt = new Date(Date.now() - 86400000).toISOString(); record.guest.hardExpiresAt = new Date(Date.now() - 1000).toISOString();
  storage.setItem(key, JSON.stringify(record));
  const session = new PracticeSession({client, storage, locks});
  assert.equal(session.guestRecovery, 'expired');
  const account = {subject: 'did:privy:recoveryTester', freshAccessToken: async () => 'token', signal: new AbortController().signal};
  assert.equal(await session.claimForAccount(account), 'preserved');
  assert.equal(api.calls.some(call => call.path === '/v1/guest/claim'), false);
  assert.equal(session.claimFailureCode, 'GUEST_SESSION_EXPIRED');
});

test('an active guest desk can never be replaced through the recovery boundary', async () => {
  Object.defineProperty(globalThis, 'crypto', {configurable: true, writable: true, value: webcrypto});
  const api = server({checkpoint: 'app'}), storage = new MemoryStorage();
  const client = new PracticeClient({baseUrl: '/api', fetch: api.fetcher, timeoutMs: 1000});
  const locks = {request: async (_name: string, _options: unknown, callback: () => Promise<unknown>) => callback()} as Pick<LockManager, 'request'>;
  const session = new PracticeSession({client, storage, locks}); await session.ensureGuest();
  const before = storage.getItem(practiceStorageKey('/api'));
  assert.equal(session.guestRecovery, null);
  await assert.rejects(session.startNewGuestDesk(), {code: 'PRACTICE_GUEST_ACTIVE'});
  assert.equal(storage.getItem(practiceStorageKey('/api')), before);
});
