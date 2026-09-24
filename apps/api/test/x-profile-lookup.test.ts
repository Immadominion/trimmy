import assert from 'node:assert/strict';
import {test} from 'node:test';
import {XProfileLookup, XProfileLookupError, type XProfileLookupErrorCode} from '../src/x-profile-lookup.js';

const fakeToken = 'test-only-token%2Fvalue';
const now = Date.parse('2026-09-14T12:00:00Z');
const profile = {id: '1234567890123456789', username: 'TrimmyHQ', name: 'Trimmy'};
function json(value: unknown, status = 200, headers?: HeadersInit): Response {
  return new Response(JSON.stringify(value), {status, headers: {'content-type': 'application/json', ...headers}});
}
function code(expected: XProfileLookupErrorCode): (error: unknown) => boolean {
  return error => {
    assert.ok(error instanceof XProfileLookupError);
    assert.equal(error.code, expected);
    assert.equal('cause' in error, false);
    assert.ok(!String(error).includes(fakeToken));
    return true;
  };
}
function lookup(fetch: typeof globalThis.fetch, options: {timeoutMs?: number; now?: () => number} = {}): XProfileLookup {
  return new XProfileLookup({bearerToken: fakeToken, fetch, now: () => now, ...options});
}

test('resolves one fixed HTTPS GET to a frozen public profile, not an authenticated identity', async () => {
  let calls = 0;
  const result = await lookup(async (input, init) => {
    calls += 1;
    assert.equal(input, 'https://api.x.com/2/users/by/username/trimmyhq');
    assert.equal(init?.method, 'GET');
    assert.equal(init?.redirect, 'manual');
    assert.equal(new Headers(init?.headers).get('authorization'), `Bearer ${fakeToken}`);
    assert.equal(init?.body, undefined);
    return json({data: {...profile, description: 'ignored', secret: 'not returned'}, extra: 'ignored'});
  }).lookup('@trimmyhq');
  assert.deepEqual(result, {provider: 'x', ...profile, lookedUpAt: '2026-09-14T12:00:00.000Z', ownershipVerified: false});
  assert.equal(Object.isFrozen(result), true);
  assert.equal(calls, 1);
});

test('invalid usernames never reach the network', async () => {
  let calls = 0;
  const resolver = lookup(async () => { calls += 1; return json({data: profile}); });
  for (const handle of ['', '@', '@@trimmyhq', 'trimmyhq\n', ' trimmyhq', 'trimmyhq ', 'a'.repeat(16),
    '../users/me', 'name?field=id', '%74rimmyhq', 'https://x.com/trimmyhq', 'trímmyhq']) {
    await assert.rejects(resolver.lookup(handle), code('X_HANDLE_INVALID'));
  }
  assert.equal(calls, 0);
});

test('empty or unsafe credential/configuration inputs are rejected without echoing', () => {
  for (const bearerToken of ['', '\nsecret', 'secret\r\nheader:value', ' secret', 'secret ', 'Bearer secret', 'a'.repeat(4097)]) {
    assert.throws(() => new XProfileLookup({bearerToken}), code('X_LOOKUP_NOT_CONFIGURED'));
  }
  for (const timeoutMs of [0, -1, 10_001, 0.1, NaN]) {
    assert.throws(() => new XProfileLookup({bearerToken: fakeToken, timeoutMs}), code('X_LOOKUP_NOT_CONFIGURED'));
  }
});

for (const [status, expected] of [
  [401, 'X_PROVIDER_AUTH_FAILED'], [402, 'X_PROVIDER_PAYMENT_REQUIRED'], [403, 'X_PROVIDER_ACCESS_DENIED'],
  [404, 'X_PROFILE_NOT_FOUND'], [429, 'X_PROVIDER_RATE_LIMITED'], [500, 'X_PROVIDER_UNAVAILABLE'],
  [302, 'X_PROVIDER_UNAVAILABLE'],
] as const) {
  test(`HTTP ${status} is sanitized and makes no retry`, async () => {
    let calls = 0;
    const resolver = lookup(async () => {
      calls += 1;
      return new Response(`private diagnostic ${fakeToken}`, {status, headers: {location: 'https://untrusted.example/'}});
    });
    await assert.rejects(resolver.lookup('trimmyhq'), code(expected));
    assert.equal(calls, 1);
  });
}

test('invalid, partial, wrong-username and non-canonical IDs cannot produce a profile', async () => {
  for (const payload of [null, [], {}, {data: null}, {data: []},
    {data: {...profile, id: 123}}, {data: {...profile, id: '0'}}, {data: {...profile, id: '01'}},
    {data: {...profile, id: '123\n'}}, {data: {...profile, id: '18446744073709551616'}},
    {data: {...profile, username: 'someone_else'}}, {data: {...profile, username: 'trimmyhq\n'}},
    {data: {...profile, name: ''}}, {data: {...profile, name: ' \t'}},
    {data: {...profile, name: 'a'.repeat(101)}}, {data: {...profile, name: 'unsafe\u0000name'}},
    {data: profile, errors: [{detail: fakeToken}]}, {data: profile, errors: null}]) {
    await assert.rejects(lookup(async () => json(payload)).lookup('trimmyhq'), code('X_RESPONSE_INVALID'));
  }
});

test('allows decimal IDs beyond JS safe integer range without number conversion', async () => {
  const id = '18446744073709551615';
  const result = await lookup(async () => json({data: {...profile, id}, errors: []})).lookup('trimmyhq');
  assert.equal(result.id, id);
});

test('invalid content type, JSON, UTF8 and declared lengths fail safely', async () => {
  const responses = [
    new Response(JSON.stringify({data: profile}), {headers: {'content-type': 'text/html'}}),
    new Response('{bad json', {headers: {'content-type': 'application/json'}}),
    new Response(new Uint8Array([0xff, 0xfe]), {headers: {'content-type': 'application/json'}}),
    json({data: profile}, 200, {'content-length': '16385'}),
    json({data: profile}, 200, {'content-length': '-1'}),
    new Response(null, {status: 200, headers: {'content-type': 'application/json'}}),
  ];
  for (const response of responses) {
    await assert.rejects(lookup(async () => response).lookup('trimmyhq'), code('X_RESPONSE_INVALID'));
  }
});

test('actual chunked bytes are bounded even without content-length and cancel the stream', async () => {
  let cancelled = false;
  let pulls = 0;
  const body = new ReadableStream<Uint8Array>({
    pull(controller) { pulls += 1; controller.enqueue(new Uint8Array(10_000)); },
    cancel() { cancelled = true; },
  });
  await assert.rejects(lookup(async () => new Response(body, {headers: {'content-type': 'application/json'}}))
    .lookup('trimmyhq'), code('X_RESPONSE_INVALID'));
  assert.equal(cancelled, true);
  assert.ok(pulls <= 3);
});

test('fetch deadline settles and aborts even if an injected transport ignores cancellation', async () => {
  let signal: AbortSignal | undefined;
  const resolver = lookup(async (_input, init) => {
    signal = init?.signal ?? undefined;
    return await new Promise<Response>(() => {});
  }, {timeoutMs: 10});
  await assert.rejects(resolver.lookup('trimmyhq'), code('X_LOOKUP_TIMEOUT'));
  assert.equal(signal?.aborted, true);
});

test('slow response body is inside the deadline and gets cancelled', async () => {
  let cancelled = false;
  const body = new ReadableStream<Uint8Array>({cancel() { cancelled = true; }});
  await assert.rejects(lookup(async () => new Response(body, {headers: {'content-type': 'application/json'}}),
    {timeoutMs: 10}).lookup('trimmyhq'), code('X_LOOKUP_TIMEOUT'));
  assert.equal(cancelled, true);
});

test('transport errors and clock errors cannot leak request secrets or create misleading observations', async () => {
  await assert.rejects(lookup(async () => { throw new Error(`request authorization ${fakeToken}`); })
    .lookup('trimmyhq'), code('X_PROVIDER_UNAVAILABLE'));
  await assert.rejects(lookup(async () => json({data: profile}), {now: () => NaN})
    .lookup('trimmyhq'), code('X_LOOKUP_NOT_CONFIGURED'));
});
