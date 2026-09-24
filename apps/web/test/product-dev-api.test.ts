import assert from 'node:assert/strict';
import {createServer, request} from 'node:http';
import type {IncomingHttpHeaders} from 'node:http';
import test from 'node:test';
import type {TestContext} from 'node:test';
import {createDevelopmentRelay} from '../dev-api.js';

type Call = {url: string; options: RequestInit | undefined};
type Reply = {status: number; headers: IncomingHttpHeaders; body: string};
type Send = {method?: string; headers?: Record<string, string | string[] | undefined>; body?: string; incomplete?: boolean};

async function fixture(t: TestContext, bodyTimeoutMs = 5_000,
  response: () => Response = () => Response.json({ok: true})) {
  const calls: Call[] = [];
  const relay = createDevelopmentRelay('https://api.example', async (url, options) => {
    calls.push({url: String(url), options}); return response();
  }, {bodyTimeoutMs});
  const server = createServer((req, res) => {
    void relay(req, res, () => {res.writeHead(418); res.end('next');}).catch(error => {
      res.writeHead(500); res.end(String(error));
    });
  });
  await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(async () => {
    server.closeAllConnections();
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  });
  const address = server.address(); assert.ok(address && typeof address === 'object');
  const send = (path: string, options: Send = {}): Promise<Reply> => new Promise((resolve, reject) => {
    const headers: Record<string, string | string[] | undefined> = {host: '127.0.0.1:4174', origin: 'http://127.0.0.1:4174',
      ...(options.body === undefined ? {} : {'content-type': 'application/json'}), ...options.headers};
    for (const key of Object.keys(headers)) if (headers[key] === undefined) delete headers[key];
    const req = request({host: '127.0.0.1', port: address.port, path, method: options.method ?? 'GET', headers}, res => {
      const chunks: Buffer[] = [];
      res.on('data', (chunk: Buffer) => chunks.push(chunk));
      res.on('error', reject);
      res.on('end', () => resolve({status: res.statusCode!, headers: res.headers, body: Buffer.concat(chunks).toString('utf8')}));
    });
    req.on('error', reject);
    req.setTimeout(2_000, () => req.destroy(new Error('Test request timed out')));
    if (options.body !== undefined) req.write(options.body);
    if (!options.incomplete) req.end();
  });
  const abortUpload = (): Promise<void> => new Promise(resolve => {
    const req = request({host: '127.0.0.1', port: address.port, path: '/api/v1/guest/session', method: 'POST',
      headers: {host: '127.0.0.1:4174', origin: 'http://127.0.0.1:4174', 'content-type': 'application/json'}});
    req.on('error', () => {}); // Intentional client disconnect.
    server.once('request', incoming => {
      incoming.once('close', resolve);
      setImmediate(() => req.destroy());
    });
    req.write('{');
  });
  return {calls, send, abortUpload};
}

test('relay accepts only canonical HTTPS target origins', () => {
  for (const origin of ['http://api.example', '//api.example', 'https://api.example/', 'https://api.example/path',
    'https://user:secret@api.example', 'https://api.example?key=secret', 'https://api.example#fragment',
    'HTTPS://API.EXAMPLE', 'https://api.example:443']) assert.throws(() => createDevelopmentRelay(origin));
  assert.doesNotThrow(() => createDevelopmentRelay('https://api.example'));
});

test('relay dispatches allowlisted GET, POST and PUT paths and passes other middleware through', async t => {
  const {calls, send} = await fixture(t);
  for (const path of ['/v1/markets/stocks/catalog', '/v1/markets/stocks/search', '/v1/markets/stocks/cards',
    '/v1/markets/stocks/variants', '/v1/markets/stocks/facts', '/v1/markets/stocks/insight',
    '/v1/account/paper/portfolio', '/v1/career/summary', '/v1/career/missions', '/v1/product/profile']) {
    assert.equal((await send('/api'+path)).status, 200);
  }
  for (const path of ['/v1/guest/session', '/v1/guest/session/refresh', '/v1/practice/session', '/v1/guest/claim', '/v1/product/launch',
    '/v1/account/paper/orders/preview', '/v1/account/paper/orders/commit']) {
    assert.equal((await send('/api'+path, {method: 'POST', body: '{}'})).status, 200);
  }
  assert.equal((await send('/api/v1/product/profile', {method: 'PUT', body: '{"name":"Ada"}'})).status, 200);
  assert.equal(calls.length, 18);
  const other = await send('/assets/logo.png'); assert.equal(other.status, 418); assert.equal(other.body, 'next');
  assert.equal(calls.length, 18);
});

test('relay keeps loopback4174 and browser origin boundaries', async t => {
  const {calls, send} = await fixture(t);
  assert.equal((await send('/api/v1/product/profile', {headers: {host: 'localhost:4174', origin: 'http://localhost:4174', 'sec-fetch-site': 'same-origin'}})).status, 200);
  assert.equal((await send('/api/v1/product/profile', {headers: {origin: undefined}})).status, 200, 'local non-browser requests may omit Origin');
  for (const headers of [
    {origin: 'https://evil.example'}, {origin: 'null'}, {origin: 'http://localhost:4174'},
    {host: 'evil.example:4174'}, {host: '127.0.0.1:4175'}, {host: 'localhost:4174.evil.example'},
    {'sec-fetch-site': 'cross-site'}, {'sec-fetch-site': 'same-site'},
  ]) assert.equal((await send('/api/v1/product/profile', {headers})).status, 403);
  assert.equal(calls.length, 2);
});

test('relay forwards explicit authorization and safe response headers without cookies or private headers', async t => {
  const {calls, send} = await fixture(t, 5_000, () => Response.json({ok: true}, {status: 429, headers: {
    'retry-after': '3', 'set-cookie': 'private=secret', 'x-upstream-secret': 'secret', 'access-control-allow-origin': '*',
  }}));
  const reply = await send('/api/v1/product/profile', {method: 'PUT', body: '{"name":"Ada"}', headers: {
    authorization: 'Bearer caller-token', cookie: 'session=must-not-leak', 'x-api-key': 'must-not-leak',
    'x-forwarded-for': '1.2.3.4', accept: 'application/json',
  }});
  const options = calls[0]!.options!;
  assert.deepEqual([...new Headers(options.headers)], [['accept', 'application/json'], ['authorization', 'Bearer caller-token'], ['content-type', 'application/json']]);
  assert.equal(options.method, 'PUT'); assert.equal(options.body, '{"name":"Ada"}');
  assert.equal(options.redirect, 'error'); assert.ok(options.signal instanceof AbortSignal);
  assert.equal(reply.status, 429); assert.equal(reply.headers['retry-after'], '3');
  assert.equal(reply.headers['cache-control'], 'no-store'); assert.equal(reply.headers['x-content-type-options'], 'nosniff');
  for (const header of ['set-cookie', 'x-upstream-secret', 'access-control-allow-origin']) assert.equal(reply.headers[header], undefined);
});

test('relay rejects unknown destinations, methods and encoded path escapes before fetching', async t => {
  const {calls, send} = await fixture(t);
  for (const path of ['/api//evil.example/v1/product/profile', '/api/v1/admin/accounts',
    '/api/v1/%2e%2e/product/profile', '/api/v1%2fproduct/profile', '/api/v1%5cproduct/profile',
    '/api/v1/product/profile/extra']) assert.equal((await send(path)).status, 404);
  assert.equal((await send('/api/v1/product/profile', {method: 'DELETE'})).status, 404);
  assert.equal((await send('/api/v1/guest/session', {method: 'GET'})).status, 404);
  assert.equal(calls.length, 0);
});

test('account lifecycle preserves the supplied bearer and exact guest claim request without credential leaks', async t => {
  const {calls, send} = await fixture(t);
  const bearer = 'Bearer exact.privy.access-token';
  const guest = 'tg1_'+'a'.repeat(43);
  const body = '{"schemaVersion":1,"idempotencyKey":"66ba0f9e-ce08-40b3-8a14-54bf68c06002"}'; // gitleaks:allow -- non-secret deterministic test value
  const privateHeaders = {authorization: bearer, 'x-trimmy-guest': guest, cookie: 'privy-token=do-not-forward',
    'privy-app-id': 'do-not-forward', 'privy-client-id': 'do-not-forward', 'x-api-key': 'do-not-forward'};
  assert.equal((await send('/api/v1/guest/claim', {method: 'POST', body, headers: privateHeaders})).status, 200);
  assert.equal(calls[0]!.url, 'https://api.example/v1/guest/claim');
  assert.equal(calls[0]!.options!.body, body);
  assert.deepEqual([...new Headers(calls[0]!.options!.headers)], [
    ['accept', 'application/json'], ['authorization', bearer], ['content-type', 'application/json'], ['x-trimmy-guest', guest],
  ]);
  assert.equal((await send('/api/v1/practice/session', {method: 'POST', body: '{}', headers: privateHeaders})).status, 200);
  assert.equal(calls[1]!.url, 'https://api.example/v1/practice/session');
  assert.equal(calls[1]!.options!.body, '{}');
  assert.deepEqual([...new Headers(calls[1]!.options!.headers)], [
    ['accept', 'application/json'], ['authorization', bearer], ['content-type', 'application/json'],
  ], 'guest proof is never sent to session provisioning or other account routes');
});

test('account bearers cross only existing product routes and guest proof stays claim-only', async t => {
  const {calls, send} = await fixture(t);
  const paths = [
    ['GET', '/v1/product/profile'], ['PUT', '/v1/product/profile'], ['POST', '/v1/product/launch'],
    ['GET', '/v1/account/paper/portfolio'], ['POST', '/v1/account/paper/orders/preview'],
    ['POST', '/v1/account/paper/orders/commit'], ['GET', '/v1/career/summary'], ['GET', '/v1/career/missions'],
  ] as const;
  for (const [method, path] of paths) {
    assert.equal((await send('/api'+path, {method, ...(method === 'GET' ? {} : {body: '{}'}),
      headers: {authorization: 'Bearer account-token', 'x-trimmy-guest': 'must-not-leak'}})).status, 200);
    const headers = new Headers(calls.at(-1)!.options!.headers);
    assert.equal(headers.get('authorization'), 'Bearer account-token');
    assert.equal(headers.has('x-trimmy-guest'), false);
  }
  for (const path of ['/api/v1/practice/session', '/api/v1/guest/claim']) {
    assert.equal((await send(path)).status, 404);
    assert.equal((await send(path, {method: 'DELETE'})).status, 404);
  }
  for (const path of ['/api/v1/logout', '/api/v1/auth/login', '/api/v1/account/closure', '/api/v1/guest/claim/extra']) {
    assert.equal((await send(path, {method: 'POST', body: '{}'})).status, 404);
  }
  assert.equal(calls.length, paths.length, 'no arbitrary account or SDK proxy surface');
});

test('duplicate physical bearer or guest claim fields cannot be collapsed into an authorized request', async t => {
  const {calls, send} = await fixture(t);
  for (const headers of [
    {authorization: ['Bearer first', 'Bearer second'], 'x-trimmy-guest': 'tg1_'+'a'.repeat(43)},
    {authorization: 'Bearer first', 'x-trimmy-guest': ['tg1_'+'a'.repeat(43), 'tg1_'+'b'.repeat(43)]},
  ]) {
    const reply = await send('/api/v1/guest/claim', {method: 'POST', body: '{}', headers});
    assert.equal(reply.status, 400);
    assert.equal(JSON.parse(reply.body).error.code, 'LOCAL_AUTH_HEADERS_INVALID');
  }
  assert.equal((await send('/api/v1/product/profile', {headers: {authorization: ['Bearer first', 'Guest second']}})).status, 400);
  assert.equal(calls.length, 0);
});

test('relay preserves encoded search values without treating query data as path traversal', async t => {
  const {calls, send} = await fixture(t);
  const path = '/api/v1/markets/stocks/search?q=A%2FB%5CC%2ED&limit=8';
  assert.equal((await send(path)).status, 200);
  assert.equal(calls[0]!.url, 'https://api.example/v1/markets/stocks/search?q=A%2FB%5CC%2ED&limit=8');
  assert.equal(new URL(calls[0]!.url).searchParams.get('q'), 'A/B\\C.D');
});

test('relay enforces JSON media type and actual streamed byte limit', async t => {
  const {calls, send} = await fixture(t);
  const wrong = await send('/api/v1/guest/session', {method: 'POST', body: '{}', headers: {'content-type': 'text/plain'}});
  assert.equal(wrong.status, 415); assert.equal(JSON.parse(wrong.body).error.code, 'LOCAL_JSON_REQUIRED');
  const oversized = await send('/api/v1/guest/session', {method: 'POST', body: 'é'.repeat(4097)});
  assert.equal(oversized.status, 413); assert.equal(JSON.parse(oversized.body).error.code, 'LOCAL_REQUEST_TOO_LARGE');
  assert.equal(oversized.headers.connection, 'close'); assert.equal(calls.length, 0);
  const exact = '{"v":"'+'x'.repeat(8192-8)+'"}'; assert.equal(Buffer.byteLength(exact), 8192);
  assert.equal((await send('/api/v1/guest/session', {method: 'POST', body: exact})).status, 200);
  assert.equal(calls.length, 1);
});

test('incomplete bodies get a bounded408 response without an upstream call, then the relay still works', async t => {
  const {calls, send} = await fixture(t, 30);
  const started = Date.now();
  const reply = await send('/api/v1/guest/session', {method: 'POST', body: '{', incomplete: true});
  assert.equal(reply.status, 408); assert.equal(JSON.parse(reply.body).error.code, 'LOCAL_REQUEST_TIMEOUT');
  assert.equal(reply.headers.connection, 'close'); assert.ok(Date.now()-started < 1_000);
  assert.equal(calls.length, 0);
  assert.equal((await send('/api/v1/guest/session', {method: 'POST', body: '{}'})).status, 200);
  assert.equal(calls.length, 1);
});

test('oversized upstream bodies produce a bounded failure without leaking partial data', async t => {
  const {send} = await fixture(t, 5_000, () => new Response('x'.repeat(2_097_153)));
  const reply = await send('/api/v1/markets/stocks/catalog');
  assert.equal(reply.status, 502); assert.equal(JSON.parse(reply.body).error.code, 'LOCAL_API_UNAVAILABLE');
  assert.ok(reply.body.length < 200);
});

test('a disconnected body causes no unhandled request error or upstream call', async t => {
  const {calls, send, abortUpload} = await fixture(t, 30);
  await abortUpload();
  assert.equal(calls.length, 0);
  assert.equal((await send('/api/v1/guest/session', {method: 'POST', body: '{}'})).status, 200);
  assert.equal(calls.length, 1);
});
