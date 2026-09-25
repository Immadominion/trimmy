import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import { buildApp } from '../src/app.js';
import { ReadinessConfigurationError, ReadinessReporter } from '../src/readiness.js';
import type { ReadinessProbe } from '../src/readiness.js';
import type { LiveStockAdapters } from '../src/live-stock-orders.js';

function counting(behaviour: (call: number) => Promise<void>): ReadinessProbe & {calls: number} {
  const probe = {
    calls: 0,
    async probe(): Promise<void> {
      probe.calls += 1;
      return behaviour(probe.calls);
    },
  };
  return probe;
}

describe('readiness is separate from liveness', () => {
  it('says ready without a database, because that is a supported mode', async () => {
    const reporter = new ReadinessReporter({now: () => 1_700_000_000_000});
    assert.deepEqual(await reporter.report(), {
      schemaVersion: 1, status: 'ready', database: 'not_configured',
      checkedAt: '2023-11-14T22:13:20.000Z', financialOperationsEnabled: false,
    });
  });

  it('reports storage failure as not ready and never repeats its reason', async () => {
    const probe = counting(async () => { throw new Error('password=hunter2 host=db.internal'); });
    const reporter = new ReadinessReporter({probe, ttlMs: 0});
    const report = await reporter.report();
    assert.equal(report.status, 'not_ready');
    assert.equal(report.database, 'unavailable');
    // The body is public, and a driver error can carry host and credentials.
    assert.ok(!JSON.stringify(report).includes('hunter2'));
    assert.ok(!JSON.stringify(report).includes('db.internal'));
  });

  it('collapses concurrent probes into one round trip', async () => {
    let release = (): void => {};
    const gate = new Promise<void>(resolve => { release = resolve; });
    const probe = counting(async () => gate);
    const reporter = new ReadinessReporter({probe, ttlMs: 0});
    const all = Promise.all([reporter.report(), reporter.report(), reporter.report()]);
    release();
    const reports = await all;
    // A router probing every instance must not multiply load on a failing database.
    assert.equal(probe.calls, 1);
    for (const report of reports) assert.equal(report.status, 'ready');
  });

  it('reuses one answer for its window, then asks again', async () => {
    let now = 1_000;
    const probe = counting(async () => {});
    const reporter = new ReadinessReporter({probe, ttlMs: 1_000, now: () => now});
    await reporter.report();
    now = 1_500;
    await reporter.report();
    assert.equal(probe.calls, 1, 'within the window one answer is reused');
    now = 2_500;
    await reporter.report();
    assert.equal(probe.calls, 2, 'after the window it checks again');
  });

  it('caches a failure too, then notices recovery', async () => {
    let now = 1_000;
    const probe = counting(async call => { if (call === 1) throw new Error('down'); });
    const reporter = new ReadinessReporter({probe, ttlMs: 1_000, now: () => now});
    assert.equal((await reporter.report()).status, 'not_ready');
    now = 1_200;
    assert.equal((await reporter.report()).status, 'not_ready', 'a struggling database is not re-probed at once');
    assert.equal(probe.calls, 1);
    now = 2_200;
    assert.equal((await reporter.report()).status, 'ready', 'recovery is noticed within one window');
  });

  it('a clock that moves backwards invalidates the answer rather than pinning it', async () => {
    let now = 5_000;
    const probe = counting(async () => {});
    const reporter = new ReadinessReporter({probe, ttlMs: 10_000, now: () => now});
    await reporter.report();
    now = 1_000;
    await reporter.report();
    assert.equal(probe.calls, 2);
  });

  it('refuses a configuration it cannot honour', () => {
    assert.throws(() => new ReadinessReporter({ttlMs: -1}), ReadinessConfigurationError);
    assert.throws(() => new ReadinessReporter({ttlMs: 60_001}), ReadinessConfigurationError);
    assert.throws(() => new ReadinessReporter({ttlMs: 1.5}), ReadinessConfigurationError);
    assert.throws(() => new ReadinessReporter({probe: {} as ReadinessProbe}), ReadinessConfigurationError);
    assert.throws(() => new ReadinessReporter({financialOperationsEnabled: 'true' as unknown as boolean}), ReadinessConfigurationError);
  });
});

describe('GET /ready', () => {
  it('reports the same execution gate as health and trading capabilities without calling a provider', async () => {
    for (const enabled of [true, false]) {
      let probes = 0;
      const liveStocks = {
        executionEnabled: enabled,
        authenticate: async () => { throw new Error('Readiness must not authenticate'); },
        identities: {resolveFresh: async () => { throw new Error('Readiness must not call identity providers'); }},
        service: {},
      } as unknown as LiveStockAdapters;
      const app = buildApp({logger: false, liveStocks, readiness: {probe: async () => {probes++;}}});
      try {
        const ready = await app.inject('/ready');
        assert.equal(ready.statusCode, 200);
        assert.equal(ready.json().database, 'ok');
        assert.equal(ready.json().financialOperationsEnabled, enabled);
        assert.equal((await app.inject('/health')).json().financialOperationsEnabled, enabled);
        assert.equal((await app.inject('/v1/trading/capabilities')).json().enabled, enabled);
        assert.equal(probes, 1);
      } finally { await app.close(); }
    }
  });

  it('answers 200 with no database configured, and refuses a query string', async () => {
    const app = buildApp({logger: false});
    try {
      const response = await app.inject({method: 'GET', url: '/ready'});
      assert.equal(response.statusCode, 200);
      assert.equal(response.json().database, 'not_configured');
      assert.equal(response.json().financialOperationsEnabled, false);
      assert.equal(response.headers['cache-control'], 'no-store');
      assert.equal((await app.inject({method: 'GET', url: '/ready?verbose=1'})).statusCode, 400);
    } finally { await app.close(); }
  });

  it('answers 503 when this instance cannot reach its own storage', async () => {
    const app = buildApp({logger: false, readiness: {probe: async () => { throw new Error('refused'); }}});
    try {
      const response = await app.inject({method: 'GET', url: '/ready'});
      assert.equal(response.statusCode, 503, 'a load balancer must stop sending traffic here');
      assert.equal(response.json().status, 'not_ready');
      assert.equal(response.json().database, 'unavailable');
    } finally { await app.close(); }
  });

  it('answers 200 when storage responds', async () => {
    const app = buildApp({logger: false, readiness: {probe: async () => {}}});
    try {
      const response = await app.inject({method: 'GET', url: '/ready'});
      assert.equal(response.statusCode, 200);
      assert.equal(response.json().database, 'ok');
    } finally { await app.close(); }
  });

  it('stays a read: no verb other than GET is served', async () => {
    const app = buildApp({logger: false, readiness: {probe: async () => {}}});
    try {
      for (const method of ['POST', 'PUT', 'PATCH', 'DELETE'] as const) {
        const response = await app.inject({method, url: '/ready'});
        // The money gate refuses every unallowlisted verb before routing, so the
        // new route cannot become a write even by a later mistake.
        assert.equal(response.statusCode, 503, `${method} /ready returned ${response.statusCode}`);
        assert.equal(response.json().error.code, 'FINANCIAL_OPERATIONS_DISABLED');
      }
    } finally { await app.close(); }
  });

  it('liveness still answers while readiness reports a failure', async () => {
    const app = buildApp({logger: false, readiness: {probe: async () => { throw new Error('down'); }}});
    try {
      assert.equal((await app.inject({method: 'GET', url: '/health'})).statusCode, 200);
      assert.equal((await app.inject({method: 'GET', url: '/ready'})).statusCode, 503);
    } finally { await app.close(); }
  });
});
