import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { OpsAlerts, readOpsAlerts } from '../src/ops-alerts.js';
import { buildApp } from '../src/app.js';

function recorder() {
  const sent: {url: string; body: Record<string, unknown>}[] = [];
  const fetch = (async (url: URL, init: {body: string}) => {
    sent.push({url: String(url), body: JSON.parse(init.body) as Record<string, unknown>});
    return new Response(null, {status: 204});
  }) as unknown as typeof globalThis.fetch;
  return {sent, fetch};
}
const tick = () => new Promise(resolve => setImmediate(resolve));

describe('operator alerts', () => {
  it('posts once per window per kind, then the count of what it held back', async () => {
    const {sent, fetch} = recorder();
    let clock = 0;
    const alerts = new OpsAlerts({url: 'https://hooks.slack.com/services/T/B/x', fetch, now: () => clock, windowMs: 40});
    alerts.notify('server_error', 'GET /v1/a');
    alerts.notify('server_error', 'GET /v1/b');
    alerts.notify('server_error', 'GET /v1/c');
    alerts.notify('order_failed', 'order 1, AAPLx (xstocks), aggregator route');
    await tick();
    assert.equal(sent.length, 2);
    assert.deepEqual(sent[0]!.body, {text: '[trimmy-api] Server error: GET /v1/a'});
    clock = 40;
    await new Promise(resolve => setTimeout(resolve, 60));
    assert.equal(sent.length, 3);
    assert.equal(sent[2]!.body['text'], '[trimmy-api] Server error: GET /v1/c (and 2 more in the last 0 min)');
  });

  it('speaks Discord, strips anything that is not a plain detail, and never throws', async () => {
    const {sent, fetch} = recorder();
    const alerts = new OpsAlerts({url: 'https://discord.com/api/webhooks/1/x', fetch});
    alerts.notify('process_error', 'Error <@everyone> "quoted" \n next');
    await tick();
    assert.deepEqual(sent[0]!.body, {content: '[trimmy-api] Unhandled error in the API process: Error @everyone quoted  next',
      allowed_mentions: {parse: []}});
    const failing = new OpsAlerts({url: 'https://example.com/hook', fetch: (async () => { throw new Error('down'); }) as unknown as typeof fetch});
    assert.doesNotThrow(() => failing.notify('server_error', 'x'));
    assert.throws(() => new OpsAlerts({url: 'http://example.com/hook'}));
    assert.equal(readOpsAlerts({}), undefined);
  });

  it('reports a server error from any route, and nothing for handled failures', async () => {
    const {sent, fetch} = recorder();
    const app = buildApp({logger: false, alerts: new OpsAlerts({url: 'https://example.com/hook', fetch})});
    app.get('/boom', async () => { throw new Error('bug'); });
    try {
      assert.equal((await app.inject({method: 'GET', url: '/boom'})).statusCode, 500);
      assert.equal((await app.inject({method: 'GET', url: '/nowhere'})).statusCode, 404);
      await tick();
      assert.equal(sent.length, 1);
      assert.equal(sent[0]!.body['text'], '[trimmy-api] Server error: GET /boom');
    } finally { await app.close(); }
  });
});
