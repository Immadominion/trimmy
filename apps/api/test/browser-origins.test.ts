import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { buildApp } from '../src/app.js';
import { BrowserOriginsConfigurationError, parseBrowserOrigins } from '../src/browser-origins.js';
import type { WatchlistAdapters } from '../src/watchlist-routes.js';

const origin = 'https://stocks.example';
const other = 'https://review.example:8443';
const userId = '11111111-1111-4111-8111-111111111111';
const mutationId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const payload = {schemaVersion: 1, mutationId, baseRevision: 0, assetIds: ['forma']};

function watchlist(onCall: () => void = () => {}): WatchlistAdapters {
  return {
    allowedAssetIds: new Set(['forma']),
    authenticate: async request => { onCall(); return request.headers.authorization === 'Bearer test-proof' ? {userId} : null; },
    repository: {
      get: async () => { onCall(); return {revision: 0, assetIds: [], updatedAt: null}; },
      put: async (_id, command) => { onCall(); return {revision: command.baseRevision + 1, assetIds: command.assetIds, updatedAt: '2026-09-14T12:00:00.000Z'}; },
    },
  };
}

describe('explicit browser origin configuration and preflight', () => {
  it('accepts only finite canonical HTTPS origin arrays and detaches the input', () => {
    const input = [origin, other, 'https://xn--bcher-kva.example', 'https://127.0.0.1', 'https://[::1]'];
    const parsed = parseBrowserOrigins(input);
    input.push('https://later.example');
    assert.equal(parsed.length, 5);
    assert.ok(Object.isFrozen(parsed));
    assert.deepEqual(parseBrowserOrigins([]), []);
    for (const invalid of [
      null, undefined, origin, {}, [null], ['*'], ['null'], ['http://localhost:4173'],
      ['https://*.example'], ['https://stocks.example/'], ['https://stocks.example.'],
      ['https://STOCKS.example'], ['HTTPS://stocks.example'], ['https://stocks.example:443'],
      ['https://user:private-password@stocks.example'], ['https://@stocks.example'],
      ['https://stocks.example/path'], ['https://stocks.example?private-query'], ['https://stocks.example#private-fragment'],
      ['https://bücher.example'], ['https://127.1'], ['https://0x7f000001'], [origin, origin],
      [`${origin}\n`], new Array(1), Array.from({length: 33}, (_, i) => `https://host-${i}.example`),
    ]) {
      assert.throws(() => parseBrowserOrigins(invalid), error => {
        assert.ok(error instanceof BrowserOriginsConfigurationError);
        assert.equal(error.code, 'BROWSER_ORIGINS_INVALID');
        assert.ok(!error.message.includes('private-'));
        return true;
      });
    }
    let called = false;
    const accessor = [origin];
    Object.defineProperty(accessor, '0', {get() { called = true; return origin; }, enumerable: true});
    assert.throws(() => parseBrowserOrigins(accessor), BrowserOriginsConfigurationError);
    assert.equal(called, false);
  });

  it('denies all browser origins by default while originless mobile requests keep working', async () => {
    const app = buildApp({logger: false, watchlist: watchlist()});
    try {
      const mobile = await app.inject({url: '/v1/watchlist', headers: {authorization: 'Bearer test-proof'}});
      assert.equal(mobile.statusCode, 200);
      assert.equal(mobile.headers['access-control-allow-origin'], undefined);
      for (const url of ['/v1/config', '/v1/watchlist']) {
        const browser = await app.inject({url, headers: {origin, authorization: 'Bearer test-proof'}});
        assert.equal(browser.statusCode, 403);
        assert.equal(browser.json().error.code, 'BROWSER_ORIGIN_DENIED');
        assert.equal(browser.headers['access-control-allow-origin'], undefined);
        assert.equal(browser.headers['cache-control'], 'no-store');
        assert.equal(browser.headers['x-content-type-options'], 'nosniff');
        assert.equal(browser.json().error.requestId, browser.headers['x-request-id']);
      }
    } finally { await app.close(); }
  });

  it('responds only to permitted route/method preflights before auth or body parsing', async () => {
    let calls = 0;
    const app = buildApp({logger: false, browserOrigins: [origin], watchlist: watchlist(() => { calls++; })});
    try {
      for (const [url, method] of [
        ['/v1/watchlist', 'GET'], ['/v1/watchlist', 'PUT'], ['/v1/practice/session', 'POST'],
        ['/v1/practice/progress', 'GET'], ['/v1/practice/progress', 'PUT'], ['/v1/config', 'GET'],
        ['/v1/career/summary', 'GET'], ['/v1/career/missions', 'GET'],
        ['/v1/career/trade-reasons?scope=everyone', 'GET'],
        ['/v1/career/trade-reasons', 'POST'], ['/v1/career/promotions', 'POST'],
        ['/v1/career/reason-privacy', 'GET'], ['/v1/career/reason-privacy', 'PUT'],
        ['/v1/career/day-context', 'GET'], ['/v1/career/day-context', 'PUT'],
        ['/v1/account/paper/reset', 'POST'],
        ['/v1/markets/stocks/history?assetId=apple', 'GET'],
        ['/v1/markets/stocks/quotes/raydium?assetId=apple', 'GET'],
      ]) {
        const response = await app.inject({method: 'OPTIONS', url: url!, headers: {
          origin, 'access-control-request-method': method!, 'access-control-request-headers': 'Authorization, Content-Type',
          'content-type': 'application/json',
        }, payload: '{deliberately-invalid-body'});
        assert.equal(response.statusCode, 204, `${url} ${method}: ${response.body}`);
        assert.equal(response.body, '');
        assert.equal(response.headers['access-control-allow-origin'], origin);
        assert.ok(String(response.headers['access-control-allow-methods']).split(', ').includes(method!));
        assert.equal(response.headers['access-control-allow-headers'], 'authorization, content-type');
        assert.equal(response.headers['access-control-allow-credentials'], undefined);
        assert.equal(response.headers['vary'], 'Origin, Access-Control-Request-Method, Access-Control-Request-Headers');
        assert.equal(response.headers['cache-control'], 'no-store');
      }
      assert.equal(calls, 0);
    } finally { await app.close(); }
  });

  it('allows absent requested headers and still requires a genuine preflight origin/method', async () => {
    const app = buildApp({logger: false, browserOrigins: [origin]});
    try {
      const response = await app.inject({method: 'OPTIONS', url: '/v1/config', headers: {origin, 'access-control-request-method': 'GET'}});
      assert.equal(response.statusCode, 204);
      assert.equal(response.headers['access-control-allow-headers'], undefined);
      const missingOrigin = await app.inject({method: 'OPTIONS', url: '/v1/config', headers: {'access-control-request-method': 'GET'}});
      assert.equal(missingOrigin.statusCode, 400);
      assert.equal(missingOrigin.headers['access-control-allow-origin'], undefined);
      const missingMethod = await app.inject({method: 'OPTIONS', url: '/v1/config', headers: {origin}});
      assert.equal(missingMethod.statusCode, 403);
      assert.equal(missingMethod.json().error.code, 'BROWSER_PREFLIGHT_DENIED');
    } finally { await app.close(); }
  });

  it('allows the explicit guest claim header only on an allowed claim preflight', async () => {
    const app = buildApp({logger: false, browserOrigins: [origin]});
    try {
      const response = await app.inject({method: 'OPTIONS', url: '/v1/guest/claim', headers: {
        origin,
        'access-control-request-method': 'POST',
        'access-control-request-headers': 'Authorization, Content-Type, X-Trimmy-Guest',
      }});
      assert.equal(response.statusCode, 204, response.body);
      assert.equal(response.headers['access-control-allow-origin'], origin);
      assert.equal(
        response.headers['access-control-allow-headers'],
        'authorization, content-type, x-trimmy-guest',
      );

      const wrongRoute = await app.inject({method: 'OPTIONS', url: '/v1/watchlist', headers: {
        origin,
        'access-control-request-method': 'PUT',
        'access-control-request-headers': 'X-Trimmy-Guest',
      }});
      assert.equal(wrongRoute.statusCode, 403);
      assert.equal(wrongRoute.json().error.code, 'BROWSER_PREFLIGHT_DENIED');
      assert.equal(wrongRoute.headers['access-control-allow-headers'], undefined);
    } finally { await app.close(); }
  });

  it('permits the holdings version header only on the exact read-only holdings route', async () => {
    const app = buildApp({logger: false, browserOrigins: [origin]});
    const headers = {origin, 'access-control-request-method': 'GET',
      'access-control-request-headers': 'Authorization, Content-Type, X-Trimmy-Holdings-Version'};
    try {
      const accepted = await app.inject({method: 'OPTIONS', url: '/v1/account/holdings', headers});
      assert.equal(accepted.statusCode, 204, accepted.body);
      assert.equal(accepted.headers['access-control-allow-headers'], 'authorization, content-type, x-trimmy-holdings-version');
      assert.equal(accepted.headers['access-control-allow-methods'], 'GET');
      assert.equal(accepted.headers['vary'], 'Origin, Access-Control-Request-Method, Access-Control-Request-Headers');
      for (const [url, method] of [
        ['/v1/account/context', 'GET'], ['/v1/config', 'GET'], ['/v1/watchlist', 'PUT'],
        ['/v1/account/holdings?wallet=x', 'GET'], ['/v1/account/holdings', 'POST'],
        ['/v1/guest/claim', 'POST'], ['/v1/account/paper/orders/commit', 'POST'],
      ]) {
        const response = await app.inject({method: 'OPTIONS', url: url!,
          headers: {...headers, 'access-control-request-method': method!}});
        assert.equal(response.statusCode, 403, `${url} ${method}: ${response.body}`);
        assert.equal(response.json().error.code, 'BROWSER_PREFLIGHT_DENIED');
        assert.equal(response.headers['access-control-allow-headers'], undefined);
      }
      for (const names of ['X-Trimmy-Holdings-Version, x-trimmy-holdings-version',
        'Authorization, Content-Type, X-Trimmy-Guest, X-Trimmy-Holdings-Version']) {
        const response = await app.inject({method: 'OPTIONS', url: '/v1/account/holdings',
          headers: {...headers, 'access-control-request-headers': names}});
        assert.equal(response.statusCode, 403, response.body);
      }
    } finally { await app.close(); }
  });

  it('rejects unknown or alias origins without reflecting them or calling authentication', async () => {
    let calls = 0;
    const app = buildApp({logger: false, browserOrigins: [origin], watchlist: watchlist(() => { calls++; })});
    try {
      for (const invalid of ['null', '*', 'https://private-attacker.example', 'https://child.stocks.example', 'https://stocks.example.evil', 'https://stocks.example.', 'https://STOCKS.example', `${origin}:443`, `${origin}/`, `https://private-user@stocks.example`, `${origin}, ${other}`]) {
        for (const method of ['PUT', 'OPTIONS'] as const) {
          const response = await app.inject({method, url: '/v1/watchlist', headers: {origin: invalid, authorization: 'Bearer test-proof', 'access-control-request-method': 'PUT'}, ...(method === 'PUT' ? {payload} : {})});
          assert.equal(response.statusCode, 403);
          assert.equal(response.headers['access-control-allow-origin'], undefined);
          assert.equal(response.headers['vary'], 'Origin');
          assert.ok(!response.body.includes('private-'));
        }
      }
      assert.equal(calls, 0);
    } finally { await app.close(); }
  });

  it('denies preflight method/header/path expansion and does not grant financial operations', async () => {
    let calls = 0;
    const app = buildApp({logger: false, browserOrigins: [origin], watchlist: watchlist(() => { calls++; })});
    try {
      const invalid: {url: string; method: string; headers?: string; privateNetwork?: string}[] = [
        {url: '/v1/watchlist', method: 'POST'}, {url: '/v1/watchlist', method: 'DELETE'},
        {url: '/v1/practice/session', method: 'PUT'}, {url: '/v1/config', method: 'PUT'},
        {url: '/v1/watchlist', method: 'put'}, {url: '/v1/watchlist', method: 'PUT, DELETE'},
        {url: '/v1/orders', method: 'POST'}, {url: '/v1/catalog', method: 'GET'},
        {url: '/v1/watchlist/', method: 'PUT'}, {url: '/v1/watchlist/execute', method: 'PUT'},
        {url: '/v1/watchlist?private-query=x', method: 'PUT'},
        {url: '/v1/watchlist', method: 'PUT', headers: 'authorization, cookie'},
        {url: '/v1/watchlist', method: 'PUT', headers: 'x-user-id'},
        {url: '/v1/watchlist', method: 'PUT', headers: 'authorization, authorization'},
        {url: '/v1/watchlist', method: 'PUT', headers: ''},
        {url: '/v1/watchlist', method: 'PUT', headers: 'authorization,'},
        {url: '/v1/watchlist', method: 'PUT', privateNetwork: 'true'},
      ];
      for (const item of invalid) {
        const response = await app.inject({method: 'OPTIONS', url: item.url, headers: {
          origin, 'access-control-request-method': item.method,
          ...(item.headers === undefined ? {} : {'access-control-request-headers': item.headers}),
          ...(item.privateNetwork === undefined ? {} : {'access-control-request-private-network': item.privateNetwork}),
        }});
        assert.equal(response.statusCode, 403, `${item.url} ${item.method}`);
        assert.equal(response.json().error.code, 'BROWSER_PREFLIGHT_DENIED');
        assert.equal(response.headers['access-control-allow-methods'], undefined);
        assert.equal(response.headers['access-control-allow-headers'], undefined);
        assert.ok(!response.body.includes('private-'));
      }
      const financial = await app.inject({method: 'POST', url: '/v1/orders', headers: {origin}, payload: {}});
      assert.equal(financial.statusCode, 503);
      assert.equal(financial.json().error.code, 'FINANCIAL_OPERATIONS_DISABLED');
      assert.equal(financial.headers['access-control-allow-origin'], origin);
      assert.equal(calls, 0);
    } finally { await app.close(); }
  });

  it('keeps exact allowed origins on authenticated successes and safe errors without cookies', async () => {
    const configured = [origin, other];
    const app = buildApp({logger: false, browserOrigins: configured, watchlist: watchlist()});
    configured.push('https://late.example');
    try {
      for (const allowed of [origin, other]) {
        const saved = await app.inject({method: 'PUT', url: '/v1/watchlist', headers: {origin: allowed, authorization: 'Bearer test-proof'}, payload});
        assert.equal(saved.statusCode, 200);
        assert.equal(saved.headers['access-control-allow-origin'], allowed);
        assert.equal(saved.headers['vary'], 'Origin');
        assert.equal(saved.headers['access-control-allow-credentials'], undefined);
        assert.equal(saved.headers['set-cookie'], undefined);
        const denied = await app.inject({method: 'PUT', url: '/v1/watchlist', headers: {origin: allowed}, payload});
        assert.equal(denied.statusCode, 401);
        assert.equal(denied.headers['access-control-allow-origin'], allowed);
        const malformed = await app.inject({method: 'PUT', url: '/v1/watchlist', headers: {origin: allowed, authorization: 'Bearer test-proof', 'content-type': 'application/json'}, payload: '{private-body'});
        assert.equal(malformed.statusCode, 400);
        assert.equal(malformed.headers['access-control-allow-origin'], allowed);
        assert.ok(!malformed.body.includes('private-body'));
        const unavailable = await app.inject({url: '/v1/practice/progress', headers: {origin: allowed}});
        assert.equal(unavailable.statusCode, 503);
        assert.equal(unavailable.headers['access-control-allow-origin'], allowed);
      }
      const late = await app.inject({url: '/v1/config', headers: {origin: 'https://late.example'}});
      assert.equal(late.statusCode, 403);
    } finally { await app.close(); }
  });
});
