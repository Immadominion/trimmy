import assert from 'node:assert/strict';
import { test } from 'node:test';
import { acquireAccountLease } from '../src/account/tab-lease';
import type { ExclusiveLockPort } from '../src/account/tab-lease';

test('exclusive account lease is retained until its session explicitly releases it', async () => {
  let released = false;
  const locks: ExclusiveLockPort = {request: async (name, options, callback) => {
    assert.equal(name, 'trimmy.watchlist.v1.did:privy:accountA');
    assert.equal(options.mode, 'exclusive');
    await callback({name});
    released = true;
  }};
  const lease = await acquireAccountLease('did:privy:accountA', {locks, signal: new AbortController().signal});
  assert.equal(released, false);
  lease.release();
  lease.release();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(released, true);
});

test('a busy tab times out without stealing a lock, and account switches cancel queued requests', async () => {
  const locks: ExclusiveLockPort = {request: async (_name, {signal}) => new Promise((_resolve, reject) => {
    if (signal.aborted) reject(new Error('aborted'));
    signal.addEventListener('abort', () => reject(new Error('aborted')), {once: true});
  })};
  await assert.rejects(acquireAccountLease('did:privy:accountA', {locks, signal: new AbortController().signal, timeoutMs: 5}), {code: 'WATCHLIST_TAB_BUSY'});
  const abort = new AbortController();
  const pending = acquireAccountLease('did:privy:accountA', {locks, signal: abort.signal});
  abort.abort();
  await assert.rejects(pending, {code: 'WATCHLIST_SESSION_CHANGED'});
});

test('unavailable browser coordination cannot silently create an unprotected account writer', async () => {
  await assert.rejects(acquireAccountLease('did:privy:accountA', {locks: undefined, signal: new AbortController().signal}), {code: 'WATCHLIST_TAB_UNAVAILABLE'});
  await assert.rejects(acquireAccountLease('did:privy:accountA', {locks: {request: async () => {throw new Error('browser denied');}}, signal: new AbortController().signal}), {code: 'WATCHLIST_TAB_UNAVAILABLE'});
});
