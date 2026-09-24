import assert from 'node:assert/strict';
import { after, describe, test } from 'node:test';
import { Pool } from 'pg';
import { buildApp } from '../../src/app.js';
import { PostgresReadinessProbe } from '../../src/postgres-readiness.js';

const socket = process.env['TRIMMY_PRACTICE_TEST_SOCKET'];
assert.ok(socket?.endsWith('/infra/.practice-runtime/socket'), 'Use the private test runner; never attach to an external database.');
assert.equal(process.env['TRIMMY_PRACTICE_TEST_PORT'], '65438');

const base = {host: socket, port: 65438, database: 'postgres', connectionTimeoutMillis: 3000} as const;
const pools: Pool[] = [];
function pool(config: Record<string, unknown>): Pool {
  const created = new Pool({...base, ...config});
  // An idle-client error would otherwise reach the process as an unhandled event.
  created.on('error', () => {});
  pools.push(created);
  return created;
}

after(async () => { for (const created of pools) await created.end().catch(() => {}); });

describe('readiness against a real database', () => {
  test('a reachable database answers ready through the real route', async () => {
    const serving = pool({user: 'trimmy_practice_test_app', max: 4});
    const app = buildApp({logger: false, readiness: new PostgresReadinessProbe(serving)});
    try {
      const response = await app.inject({method: 'GET', url: '/ready'});
      assert.equal(response.statusCode, 200);
      assert.equal(response.json().database, 'ok');
      // The probe returns its connection, so it does not consume the pool.
      assert.equal(serving.idleCount, 1);
      assert.equal(serving.totalCount, 1);
    } finally { await app.close(); }
  });

  test('an unreachable database answers not ready and leaks no credential', async () => {
    const missing = pool({user: 'trimmy_no_such_role', max: 2});
    const app = buildApp({logger: false, readiness: new PostgresReadinessProbe(missing)});
    try {
      const response = await app.inject({method: 'GET', url: '/ready'});
      assert.equal(response.statusCode, 503);
      assert.equal(response.json().database, 'unavailable');
      assert.equal(response.json().status, 'not_ready');
      const body = response.body;
      for (const secret of ['trimmy_no_such_role', 'socket', '65438', 'postgres']) {
        assert.ok(!body.includes(secret), `the public body must not carry ${secret}`);
      }
    } finally { await app.close(); }
  });

  test('an exhausted pool is bounded, does not hang, and recovers', async () => {
    const tight = pool({user: 'trimmy_practice_test_app', max: 1});
    const probe = new PostgresReadinessProbe(tight, {connectMs: 150, queryMs: 1_000});
    // Hold the only connection, which is how pool exhaustion looks in production.
    const held = await tight.connect();
    const started = Date.now();
    await assert.rejects(probe.probe(), /timed out/);
    const waited = Date.now() - started;
    assert.ok(waited < 1_500, `a readiness probe must not hang; waited ${waited}ms`);

    held.release();
    // The connection is usable again, so the failed probe destroyed nothing it owned.
    await probe.probe();
    assert.equal(tight.totalCount, 1, 'the timed-out probe left no extra connection behind');
    assert.equal(tight.idleCount, 1);
  });

  test('repeated probes neither accumulate connections nor change session state', async () => {
    const serving = pool({user: 'trimmy_practice_test_app', max: 3});
    const probe = new PostgresReadinessProbe(serving);
    for (let round = 0; round < 12; round += 1) await probe.probe();
    assert.ok(serving.totalCount <= 1, `expected one reused connection, saw ${serving.totalCount}`);
    const {rows} = await serving.query('SHOW statement_timeout');
    // The probe must not have left a timeout on the pooled session.
    assert.equal(rows[0]['statement_timeout'], '0');
  });
});
