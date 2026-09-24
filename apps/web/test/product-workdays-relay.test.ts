import assert from 'node:assert/strict';
import {createServer, request} from 'node:http';
import test from 'node:test';
import {createDevelopmentRelay} from '../dev-api.js';

test('local relay permits only deployed workday methods and retains caller authentication', async t => {
  const calls: {url: string; init: RequestInit}[] = [];
  const relay = createDevelopmentRelay('https://api.example', async (input, init = {}) => {
    calls.push({url: String(input), init}); return Response.json({ok: true});
  });
  const server = createServer((req, res) => {void relay(req, res, () => {res.writeHead(404); res.end();});});
  await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(async () => {server.closeAllConnections(); await new Promise<void>(resolve => server.close(() => resolve()));});
  const address = server.address(); assert.ok(address && typeof address === 'object');
  const send = (path: string, method = 'GET', body?: string): Promise<number> => new Promise((resolve, reject) => {
    const req = request({host: '127.0.0.1', port: address.port, path: `/api${path}`, method, agent: false,
      headers: {host: 'localhost:4174', origin: 'http://localhost:4174', authorization: 'Bearer account.proof',
        'x-trimmy-guest': 'must-not-leak', cookie: 'must-not-leak', 'content-type': 'application/json'}}, response => {
      response.resume(); response.on('end', () => resolve(response.statusCode!));
    });
    req.on('error', reject); req.end(body);
  });
  assert.equal(await send('/v1/career/workdays'), 200);
  const body = JSON.stringify({assignmentId: 'morning-brief', revision: 2, step: 2, answer: {ids: ['fact-1', 'fact-2']}, draft: 'Saved note.'});
  assert.equal(await send('/v1/career/workdays/step', 'POST', body), 200);
  const draft = JSON.stringify({assignmentId: 'morning-brief', revision: 2, draft: 'Saved note.'});
  assert.equal(await send('/v1/career/workdays/draft', 'POST', draft), 200);
  for (const [path, method] of [['/v1/career/workdays', 'PUT'], ['/v1/career/workdays/step', 'GET'],
    ['/v1/career/workdays/draft', 'GET'], ['/v1/career/workdays/complete', 'POST']]) {
    assert.equal(await send(path!, method!, method === 'GET' ? undefined : '{}'), 404);
  }
  assert.equal(calls.length, 3); assert.equal(calls[1]!.init.body, body); assert.equal(calls[2]!.init.body, draft);
  for (const call of calls) {
    const headers = new Headers(call.init.headers);
    assert.equal(headers.get('authorization'), 'Bearer account.proof'); assert.equal(headers.has('cookie'), false);
    assert.equal(headers.has('x-trimmy-guest'), false); assert.equal(call.init.redirect, 'error');
  }
});
