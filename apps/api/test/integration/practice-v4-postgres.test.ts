import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { after, before, test } from 'node:test';
import { Pool } from 'pg';
import { canonicalPracticeProgress, parsePracticeProgress } from '@trimmy/domain';
import type { PracticeProgress } from '@trimmy/domain';
import { buildApp } from '../../src/app.js';
import { PostgresPracticeRepository } from '../../src/postgres-practice-repository.js';

const socket = process.env['TRIMMY_PRACTICE_TEST_SOCKET'];
assert.ok(socket?.endsWith('/infra/.practice-runtime/socket'), 'Only the exclusively owned private database runner is supported.');
assert.equal(process.env['TRIMMY_PRACTICE_TEST_PORT'], '65438');
const pool = new Pool({host: socket, port: 65438, database: 'postgres', user: 'trimmy_practice_test_app', max: 3});
const repository = new PostgresPracticeRepository(pool);
const seededUser = 'fc000000-0000-4000-a000-000000000001';
const seededMutation = 'fc000000-0000-4000-b000-000000000001';
let otherUser = '';
const app = buildApp({logger: false, practice: {repository, authenticate: async request => {
  if (request.headers.authorization === 'Bearer v4-fixture-seeded') return {userId: seededUser};
  if (request.headers.authorization === 'Bearer v4-fixture-other' && otherUser) return {userId: otherUser};
  return null;
}}});
function fixture(version: 3 | 4, name: string): PracticeProgress {
  const contract = JSON.parse(readFileSync(new URL(`../../../../contracts/practice-progress-v${version}.json`, import.meta.url), 'utf8')) as {cases: {name: string; progress: unknown}[]};
  const entry = contract.cases.find(item => item.name === name);
  assert.ok(entry, name);
  return parsePracticeProgress(entry.progress);
}
const historical = fixture(3, 'check-the-date-closed');
const upgraded = fixture(4, 'compare-company-value-closed');
function get(other = false) {
  return app.inject({method: 'GET', url: '/v1/practice/progress', headers: {authorization: `Bearer v4-fixture-${other ? 'other' : 'seeded'}`}});
}
function put(progress: PracticeProgress, baseRevision: number, mutationId = randomUUID(), other = false) {
  return app.inject({method: 'PUT', url: '/v1/practice/progress', headers: {authorization: `Bearer v4-fixture-${other ? 'other' : 'seeded'}`}, payload: {schemaVersion: 1, mutationId, baseRevision, progress}});
}
before(async () => {
  const result = await pool.query<{id: string}>("SELECT trimmy.practice_provision_account('v4-fixture-app','did:privy:versionFourOther') AS id");
  otherUser = result.rows[0]!.id;
  await app.ready();
});
after(async () => { await app.close(); await pool.end(); });

if (process.env['TRIMMY_PRACTICE_TEST_RECOVERY'] === '1') {
  test('restart preserves current v4, pre-migration v3 retry identity and account isolation', async () => {
    const current = await get();
    assert.equal(current.statusCode, 200, current.body);
    assert.equal(current.json().revision, 3);
    assert.equal(current.json().progress.version, 4);
    assert.ok(current.json().progress.completions['count-the-fees']);
    assert.deepEqual(current.json().progress.completions['check-the-date'], historical.completions['check-the-date']);
    const replay = await put(historical, 0, seededMutation);
    assert.equal(replay.statusCode, 200, replay.body);
    assert.equal(replay.json().revision, 1);
    assert.equal(replay.json().updatedAt, '2026-09-14T12:00:00.000Z');
    assert.equal(canonicalPracticeProgress(replay.json().progress), canonicalPracticeProgress(historical));
    assert.deepEqual((await get()).json(), current.json());
    assert.equal((await get(true)).json().progress.version, 3);
  });
} else {
  test('migration preserves an actual pre-migration v3 snapshot and matching original receipt', async () => {
    const current = await get();
    assert.equal(current.statusCode, 200, current.body);
    assert.deepEqual(current.json(), {schemaVersion: 1, revision: 1, progress: historical, updatedAt: '2026-09-14T12:00:00.000Z'});
    const replay = await put(historical, 0, seededMutation);
    assert.equal(replay.statusCode, 200, replay.body);
    assert.deepEqual(replay.json(), current.json());
  });

  test('upgrades to v4 with the fifth activity while retaining the original corrected first answer', async () => {
    const saved = await put(upgraded, 1);
    assert.equal(saved.statusCode, 200, saved.body);
    assert.equal(saved.json().revision, 2);
    assert.deepEqual(saved.json().progress, upgraded);
    assert.deepEqual(saved.json().progress.completions['check-the-date'], historical.completions['check-the-date']);
  });

  test('an original v3 retry returns v3 after upgrade; the same UUID cannot bind a v4 body', async () => {
    const retry = await put(historical, 0, seededMutation);
    assert.equal(retry.statusCode, 200, retry.body);
    assert.equal(retry.json().revision, 1);
    assert.deepEqual(retry.json().progress, historical);
    const rebound = await put(parsePracticeProgress({...historical, version: 4}), 0, seededMutation);
    assert.equal(rebound.statusCode, 409, rebound.body);
    assert.equal(rebound.json().error.code, 'PRACTICE_IDEMPOTENCY_CONFLICT');
    assert.deepEqual((await get()).json().progress, upgraded);
  });

  test('a fresh downgrade is protected while a stale revision reports current v4 safely', async () => {
    const downgrade = await put(historical, 2);
    assert.equal(downgrade.statusCode, 409, downgrade.body);
    assert.equal(downgrade.json().error.code, 'PRACTICE_VERSION_DOWNGRADE');
    assert.equal(downgrade.json().currentSnapshot, undefined);
    const stale = await put(historical, 1);
    assert.equal(stale.statusCode, 409, stale.body);
    assert.equal(stale.json().error.code, 'PRACTICE_REVISION_CONFLICT');
    assert.equal(stale.json().currentSnapshot.progress.version, 4);
    assert.equal((await get()).json().revision, 2);
  });

  test('historical v3 cannot claim v4 content and future v7 is rejected before persistence', async () => {
    for (const version of [3, 7]) {
      const response = await put({...upgraded, version} as PracticeProgress, 2);
      assert.equal(response.statusCode, 400, response.body);
      assert.equal(response.json().error.code, 'PRACTICE_INVALID_INPUT');
    }
    assert.equal((await get()).json().revision, 2);
  });

  test('v4 first notes remain immutable, including precise completion time', async () => {
    const changed = parsePracticeProgress({...upgraded, completions: {...upgraded.completions,
      'compare-company-value': {...upgraded.completions['compare-company-value']!, completedAt: '2026-09-14T10:20:30.999999Z'},
    }});
    for (const progress of [changed, fixture(4, 'prepare-the-update-closed')]) {
      const denied = await put(progress, 2);
      assert.equal(denied.statusCode, 409, denied.body);
      assert.equal(denied.json().error.code, 'PRACTICE_HISTORY_CONFLICT');
    }
    assert.deepEqual((await get()).json().progress, upgraded);
  });

  test('concurrent v4 saves still commit once with an explicit current snapshot conflict', async () => {
    const responses = await Promise.all([
      put(fixture(4, 'count-the-fees-closed'), 2),
      put(fixture(4, 'check-concentration-closed'), 2),
    ]);
    assert.deepEqual(responses.map(response => response.statusCode).sort(), [200, 409]);
    const winner = responses.find(response => response.statusCode === 200)!;
    const conflict = responses.find(response => response.statusCode === 409)!;
    assert.equal(winner.json().revision, 3);
    assert.deepEqual(conflict.json().currentSnapshot, winner.json());
  });

  test('receipt UUID and upgrade status stay account scoped', async () => {
    assert.equal((await get(true)).json().revision, 0);
    const other = await put(historical, 0, seededMutation, true);
    assert.equal(other.statusCode, 200, other.body);
    assert.equal(other.json().revision, 1);
    assert.equal(other.json().progress.version, 3);
    assert.equal((await get()).json().progress.version, 4);
    assert.equal((await get()).json().revision, 3);
  });
}
