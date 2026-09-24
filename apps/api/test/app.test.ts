import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { buildApp } from '../src/app.js';

describe('foundation HTTP boundary', () => {
  it('reports process liveness without promising provider readiness', async () => {
    const app = buildApp({logger: false});
    try {
      const response = await app.inject({method: 'GET', url: '/health'});
      assert.equal(response.statusCode, 200);
      assert.deepEqual(response.json(), {status: 'ok', service: 'trimmy-api', mode: 'foundation', financialOperationsEnabled: false});
      assert.equal(response.headers['cache-control'], 'no-store');
      assert.equal(response.headers['x-content-type-options'], 'nosniff');
      assert.ok(response.headers['x-request-id']);
    } finally { await app.close(); }
  });
  it('exposes only disabled capabilities and an empty live catalog', async () => {
    const app = buildApp({logger: false});
    try {
      const config = (await app.inject('/v1/config')).json();
      assert.equal(config.moneyMode, 'practice_only');
      assert.equal(config.capabilities.financialOperationsEnabled, false);
      assert.equal(config.capabilities.persistenceEnabled, false);
      assert.deepEqual(config.capabilities.supportedAssetIds, []);
      assert.equal(config.stockHistoryEnabled, false);
      assert.equal(config.raydiumStockQuotesEnabled, false);
      const catalog = (await app.inject('/v1/catalog')).json();
      assert.deepEqual(catalog.assets, []);
      assert.equal(catalog.status, 'unverified');
    } finally { await app.close(); }
  });
  it('reports optional stock-history and Raydium readers without enabling money operations', async () => {
    const app = buildApp({
      logger: false,
      stockHistory: {history: async () => { throw new Error('unused'); }},
      raydiumStockQuotes: {quote: async () => { throw new Error('unused'); }},
    });
    try {
      const config = (await app.inject('/v1/config')).json();
      assert.equal(config.stockHistoryEnabled, true);
      assert.equal(config.raydiumStockQuotesEnabled, true);
      assert.equal(config.capabilities.financialOperationsEnabled, false);
      assert.equal(config.moneyMode, 'practice_only');
    } finally { await app.close(); }
  });
  it('rejects every mutation even with pretend credentials or enable flags', async () => {
    const app = buildApp({logger: false});
    try {
      for (const method of ['POST', 'PUT', 'PATCH', 'DELETE'] as const) {
        for (const url of ['/v1/quotes', '/v1/execute', '/api/sponsor', '/api/recipient', '/v1/config', '/unknown']) {
          const response = await app.inject({method, url, headers: {authorization: 'Bearer pretend-secret'}, payload: {financialOperationsEnabled: true, signedTransaction: 'not-a-real-transaction'}});
          assert.equal(response.statusCode, 503, `${method} ${url}`);
          assert.equal(response.json().error.code, 'FINANCIAL_OPERATIONS_DISABLED');
          assert.ok(!response.body.includes('pretend-secret'));
          assert.ok(!response.body.includes('not-a-real-transaction'));
        }
      }
    } finally { await app.close(); }
  });
  it('treats unfunded invitations as a social route without opening a financial verb', async () => {
    const app = buildApp({logger: false});
    try {
      // Only POST is allowlisted, and only because invitations are unfunded by
      // database constraint. Every other verb stays behind the money gate.
      for (const method of ['PUT', 'PATCH', 'DELETE'] as const) {
        for (const url of ['/v1/invitations', '/v1/invitations/x/actions']) {
          const response = await app.inject({method, url, headers: {authorization: 'Bearer pretend-secret'},
            payload: {financialOperationsEnabled: true, signedTransaction: 'not-a-real-transaction'}});
          assert.equal(response.statusCode, 503, `${method} ${url}`);
          assert.equal(response.json().error.code, 'FINANCIAL_OPERATIONS_DISABLED');
        }
      }
      // With no adapter configured the POST is simply unavailable, and it still
      // echoes nothing back and enables no money capability.
      for (const url of ['/v1/invitations', '/v1/invitations/x/actions']) {
        const response = await app.inject({method: 'POST', url, headers: {authorization: 'Bearer pretend-secret'},
          payload: {financialOperationsEnabled: true, signedTransaction: 'not-a-real-transaction'}});
        assert.equal(response.statusCode, 503, url);
        assert.equal(response.json().error.code, 'INVITATION_UNAVAILABLE');
        assert.ok(!response.body.includes('pretend-secret'));
        assert.ok(!response.body.includes('not-a-real-transaction'));
      }
      const config = (await app.inject('/v1/config')).json();
      assert.equal(config.invitationsEnabled, false);
      assert.equal(config.capabilities.financialOperationsEnabled, false);
      assert.equal(config.moneyMode, 'practice_only');
    } finally { await app.close(); }
  });
  it('refuses oversized attempted mutations before parsing or executing them', async () => {
    const app = buildApp({logger: false});
    try {
      const response = await app.inject({method: 'POST', url: '/v1/execute', payload: {transaction: 'x'.repeat(20_000)}});
      assert.equal(response.statusCode, 503);
      assert.equal(response.json().error.code, 'FINANCIAL_OPERATIONS_DISABLED');
    } finally { await app.close(); }
  });
  it('rejects unknown query parameters instead of silently stripping them', async () => {
    const app = buildApp({logger: false});
    try {
      for (const path of ['/health', '/v1/config', '/v1/catalog']) {
        const response = await app.inject(`${path}?secret=do-not-echo&enableMoney=true`);
        assert.equal(response.statusCode, 400);
        assert.equal(response.json().error.code, 'INVALID_REQUEST');
        assert.ok(!response.body.includes('do-not-echo'));
        assert.ok(!response.body.includes('enableMoney'));
      }
    } finally { await app.close(); }
  });
  it('returns opaque not-found errors and generates its own request IDs', async () => {
    const app = buildApp({logger: false});
    try {
      const response = await app.inject({url: '/secret-claim-link', headers: {'x-request-id': 'attacker-controlled'}});
      assert.equal(response.statusCode, 404);
      assert.equal(response.json().error.code, 'NOT_FOUND');
      assert.notEqual(response.headers['x-request-id'], 'attacker-controlled');
      assert.equal(response.json().error.requestId, response.headers['x-request-id']);
      assert.ok(!response.body.includes('secret-claim-link'));
      assert.equal(response.headers['access-control-allow-origin'], undefined);
    } finally { await app.close(); }
  });
});
