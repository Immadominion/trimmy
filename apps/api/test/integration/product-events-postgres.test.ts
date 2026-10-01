import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {Pool} from 'pg';
import {postgresProductEvents, type ProductEvent} from '../../src/product-events.js';
const host = process.env['TRIMMY_WORKDAYS_TEST_SOCKET'];
assert.ok(host?.endsWith('/infra/.workdays-runtime/socket'));

test('product events: idempotent append-only batches, account-bound links that closure removes, 400-day pruning', async () => {
 const owner = new Pool({host, port: 65455, database: 'postgres', user: 'trimmy_daily_owner'});
 let runtime: Pool | undefined;
 try {
  await owner.query(`CREATE ROLE events_test_runtime LOGIN NOSUPERUSER NOBYPASSRLS;
   GRANT USAGE ON SCHEMA trimmy TO events_test_runtime;
   GRANT EXECUTE ON FUNCTION trimmy.product_events_record(jsonb), trimmy.product_install_link(uuid,uuid), trimmy.product_events_prune() TO events_test_runtime`);
  runtime = new Pool({host, port: 65455, database: 'postgres', user: 'events_test_runtime'});
  const store = postgresProductEvents(runtime);
  const install = randomUUID(), session = randomUUID();
  const event = (name: string, props: ProductEvent['props'], occurredAt = new Date().toISOString()): ProductEvent =>
   ({id: randomUUID(), installId: install, sessionId: session, platform: 'android', appVersion: '0.1.0+2026100101', locale: 'pt-BR', name, props, occurredAt});
  const batch = [event('app_open', {source: 'launch'}), event('onboarding_step', {step: 'welcome'}), event('tab_view', {tab: 'desk'})];
  assert.equal(await store.record(batch), 3);
  assert.equal(await store.record(batch), 0, 'a retried batch adds nothing');
  // An event outside the database's own window is skipped, not stored and not fatal.
  assert.equal(await store.record([event('app_open', {source: 'resume'}, new Date(Date.now() - 8 * 86_400_000).toISOString()), event('app_open', {source: 'resume'})]), 1);
  const stored = (await owner.query('SELECT name, props, locale, platform FROM trimmy.product_events WHERE install_id=$1 ORDER BY occurred_at, name', [install])).rows;
  assert.equal(stored.length, 4);
  assert.deepEqual(stored.find(row => row.name === 'onboarding_step')?.props, {step: 'welcome'});
  // The database refuses what the API would never send.
  await assert.rejects(runtime.query('SELECT trimmy.product_events_record($1::jsonb)', ['[]']), /EVENTS_INVALID/);
  await assert.rejects(store.record([{...event('app_open', {source: 'launch'}), name: 'Bad Name'}]), /check/i);
  await assert.rejects(store.record([{...event('app_open', {source: 'launch'}), props: {note: 'x'.repeat(600)}}]), /check/i);
  await assert.rejects(runtime.query('SELECT * FROM trimmy.product_events'), /permission denied/);
  await assert.rejects(runtime.query('SELECT * FROM trimmy.product_install_links'), /permission denied/);
  await assert.rejects(runtime.query('DELETE FROM trimmy.product_events'), /permission denied/);

  const [user, other] = [randomUUID(), randomUUID()];
  await owner.query('INSERT INTO trimmy.users(id) VALUES ($1),($2)', [user, other]);
  await store.link(user, install);
  await store.link(user, install);
  await store.link(other, install);
  assert.equal((await owner.query('SELECT count(*)::int AS n FROM trimmy.product_install_links WHERE install_id=$1', [install])).rows[0].n, 2);
  // Linking needs the caller's own scope: a request scoped to one account cannot link another.
  const client = await runtime.connect();
  try {
   await client.query('BEGIN'); await client.query("SELECT set_config('trimmy.practice_user_id',$1,true)", [other]);
   await assert.rejects(client.query('SELECT trimmy.product_install_link($1,$2)', [user, randomUUID()]), /ACCOUNT_REQUIRED/);
  } finally { await client.query('ROLLBACK'); client.release(); }
  // Closing an account removes its links; the install's events stay, anonymous.
  await owner.query("UPDATE trimmy.users SET status='closed' WHERE id=$1", [user]);
  assert.deepEqual((await owner.query('SELECT user_id FROM trimmy.product_install_links WHERE install_id=$1', [install])).rows.map(row => row.user_id), [other]);
  await assert.rejects(store.link(user, install), /ACCOUNT_REQUIRED/);
  assert.equal((await owner.query('SELECT count(*)::int AS n FROM trimmy.product_events WHERE install_id=$1', [install])).rows[0].n, 4);

  // Pruning: rows older than 400 days go, recent ones stay.
  const old = randomUUID();
  await owner.query(`INSERT INTO trimmy.product_events(id,install_id,session_id,platform,app_version,locale,name,props,occurred_at,received_at)
   VALUES ($1,$2,$2,'web','web-1','en','app_open','{"source":"launch"}',now()-interval '401 days',now()-interval '401 days')`, [randomUUID(), old]);
  await owner.query(`INSERT INTO trimmy.product_install_links VALUES ($1,$2,now()-interval '402 days',now()-interval '401 days')`, [old, other]);
  assert.equal(await store.prune(), 2);
  assert.equal((await owner.query('SELECT count(*)::int AS n FROM trimmy.product_events WHERE install_id=$1', [install])).rows[0].n, 4);
  assert.equal((await owner.query('SELECT count(*)::int AS n FROM trimmy.product_install_links WHERE install_id=$1', [install])).rows[0].n, 1);
 } finally { await runtime?.end(); await owner.end(); }
});
