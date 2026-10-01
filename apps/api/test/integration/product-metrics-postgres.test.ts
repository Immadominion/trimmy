import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import pg from 'pg';
// @ts-expect-error The report tool is plain JavaScript run by operators.
import {collectMetrics, renderReport} from '../../../../tool/runtime/product-metrics.mjs';
const host = process.env['TRIMMY_WORKDAYS_TEST_SOCKET'];
assert.ok(host?.endsWith('/infra/.workdays-runtime/socket'));

// March 2027 keeps these players apart from the other suites' October 2026 players.
test('product metrics: weekday desk cadence, cohort return and first-run funnel from known activity', async () => {
 const owner = new pg.Pool({host, port: 65455, database: 'postgres', user: 'trimmy_daily_owner'});
 try {
  const content = JSON.parse(await readFile(new URL('../../../../content/workdays/intern-v1.json', import.meta.url), 'utf8'));
  const defs: Record<string, any>[] = content.assignments;
  const [a, b] = [randomUUID(), randomUUID()];
  await owner.query('INSERT INTO trimmy.users(id) VALUES ($1),($2)', [a, b]);
  const save = async (user: string, at: string, d: Record<string, any>, step: number, answer: unknown) => {
   const client = await owner.connect();
   try {
    await client.query('BEGIN'); await client.query("SELECT set_config('trimmy.practice_user_id',$1,true)", [user]);
    const journey = (await client.query('SELECT trimmy.workday_read_at($1,$2) AS j', [user, at])).rows[0].j;
    const entry = journey.assignments.find((e: Record<string, unknown>) => e['id'] === d['id']);
    await client.query('SELECT trimmy.workday_save_at($1,$2,$3,$4,$5,NULL,$6)', [user, d['id'], entry.revision, step, JSON.stringify(answer), at]);
    await client.query('COMMIT');
   } catch (error) { await client.query('ROLLBACK'); throw error; } finally { client.release(); }
  };
  const file = async (user: string, at: string, d: Record<string, any>) => {
   await save(user, at, d, 0, {ids: d['evidence'].requiredIds});
   await save(user, at, d, 1, {value: d['decision'].acceptedAnswers[0]});
   await save(user, at, d, 2, {ids: d['file'].requiredIds});
  };
  await file(a, '2027-03-01T10:00:00Z', defs[0]!); // Monday
  await file(a, '2027-03-02T10:00:00Z', defs[1]!); // Tuesday
  await file(a, '2027-03-04T10:00:00Z', defs[2]!); // Thursday, after a missed Wednesday
  await file(b, '2027-03-05T10:00:00Z', defs[0]!); // Friday, never back
  const [ia, ib, ic] = [randomUUID(), randomUUID(), randomUUID()];
  const event = (install: string, at: string, name: string, props: Record<string, unknown>) => owner.query(
   `INSERT INTO trimmy.product_events(id,install_id,session_id,platform,app_version,locale,name,props,occurred_at,received_at)
    VALUES ($1,$2,$2,'ios','0.1.0+4','es-419',$3,$4,$5,$5)`, [randomUUID(), install, name, JSON.stringify(props), at]);
  await event(ia, '2027-03-01T09:00:00Z', 'app_open', {source: 'launch'});
  for (const [i, step] of ['welcome', 'note', 'first_trade', 'review', 'first_order', 'celebration', 'gate', 'reminders', 'next_move', 'home'].entries())
   await event(ia, `2027-03-01T09:0${i}:30Z`, 'onboarding_step', {step});
  await event(ia, '2027-03-02T08:00:00Z', 'app_open', {source: 'reminder'});
  await event(ia, '2027-03-02T08:30:00Z', 'workday_waiting', {state: 'tomorrow'});
  await event(ib, '2027-03-03T09:00:00Z', 'onboarding_step', {step: 'welcome'});
  await event(ib, '2027-03-03T09:01:00Z', 'onboarding_skip', {step: 'note'});
  await event(ic, '2027-03-03T09:00:00Z', 'startup_failed', {stage: 'network'});
  await owner.query(`INSERT INTO trimmy.product_install_links VALUES ($1,$2,'2027-03-01T09:05:00Z','2027-03-02T08:00:00Z')`, [ia, a]);

  const client = await owner.connect();
  let results: Record<string, Record<string, any>[]>;
  try { results = await collectMetrics(client, {days: 30, at: new Date('2027-03-20T12:00:00Z')}); } finally { client.release(); }
  const week = (rows: Record<string, any>[], key: string) => rows.find(row => row[key] === '2027-03-01');
  // Four filer-days by two players, all first try; only Monday's filer filed again on the next desk day.
  assert.deepEqual({...week(results.cadence!, 'week'), week: undefined},
   {week: undefined, player_days: 4, filers: 2, filings: 4, first_try: 4, repeat_eligible: 4, filed_next_desk_day: 1});
  // Two new players: one back the next day (also the next desk day) and within the week; neither on day 7; day 30 not yet due.
  assert.deepEqual({...week(results.retention!, 'cohort_week'), cohort_week: undefined}, {cohort_week: undefined, players: 2,
   d1_eligible: 2, d1: 1, next_desk_day_eligible: 2, next_desk_day: 1, w1_eligible: 2, w1: 1, d7_eligible: 2, d7: 0, d30_eligible: 0, d30: 0});
  const funnel = new Map(results.funnel!.map(row => [row['stage'], row['installs']]));
  assert.deepEqual(Object.fromEntries(funnel), {'installs': 3, 'step:welcome': 2, 'step:note': 1, 'step:first_trade': 1, 'step:review': 1,
   'step:first_order': 1, 'step:celebration': 1, 'step:gate': 1, 'step:reminders': 1, 'step:next_move': 1, 'step:home': 1,
   'linked to a desk': 1, 'filed a workday (7 days)': 1, 'came back another day (7 days)': 1});
  assert.deepEqual(results.skips, [{step: 'note', installs: 1}]);
  assert.deepEqual(results.failures, [{stage: 'network', platform: 'ios', times: 1, installs: 1}]);
  assert.deepEqual(results.waiting, [{state: 'tomorrow', times: 1, installs: 1}]);
  assert.deepEqual(results.platforms, [{platform: 'ios', language: 'es', installs: 3}]);
  const report = renderReport(results, {days: 30, at: new Date('2027-03-20T12:00:00Z')});
  for (const section of ['## Overview', '## First run', '## Coming back', '## The weekday desk', '## Why the app was opened', '## Real money'])
   assert.ok(report.includes(section), section);
  assert.ok(!/undefined|NaN/.test(report));
  assert.match(report, /\| 2027-03-01 \| 2 \| 50% \| 50% \| 50% \| 0% \| n\/a \|/);
  // The report cannot write: its transaction is read-only.
  const writer = await owner.connect();
  try {
   await writer.query('BEGIN READ ONLY');
   await assert.rejects(writer.query("INSERT INTO trimmy.users(id) VALUES (gen_random_uuid())"), /read-only/);
  } finally { await writer.query('ROLLBACK'); writer.release(); }
 } finally { await owner.end(); }
});
