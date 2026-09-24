import test from 'node:test';
import assert from 'node:assert/strict';
import {recheckXProfile} from './x-profile-recheck.mjs';

test('profile recheck projects one successful public lookup without claiming login', async () => {
  let calls = 0;
  const record = await recheckXProfile({bearerToken: 'test-only-token', fetchImpl: async (url, init) => {
    calls++; assert.equal(url, 'https://api.x.com/2/users/by/username/trimmyhq');
    assert.equal(init.method, 'GET'); assert.equal(init.redirect, 'manual');
    return Response.json({data: {id: '123456789', username: 'trimmyhq', name: 'Trimmy'}});
  }});
  assert.equal(calls, 1); assert.equal(record.attempts, 1); assert.equal(record.passed, true);
  assert.equal(record.loginVerified, false); assert.equal(record.ownershipVerified, false);
  assert.equal(record.precedingObservation, 'X_PROFILE_LOOKUP_SMOKE.json');
  assert.equal(JSON.stringify(record).includes('test-only-token'), false);
});
test('profile recheck never retries 402/429 or returns raw diagnostics', async () => {
  for (const status of [402, 429]) {
    let calls = 0;
    const record = await recheckXProfile({bearerToken: 'test-only-token', fetchImpl: async () => {
      calls++; return new Response('private diagnostic', {status});
    }});
    assert.equal(calls, 1); assert.equal(record.httpStatus, status); assert.equal(record.profile, null);
    assert.equal(record.passed, false); assert.equal(JSON.stringify(record).includes('private diagnostic'), false);
  }
});
