import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {after, before, test} from 'node:test';
import {Pool} from 'pg';
import {parsePracticeProgress} from '@trimmy/domain';
import type {PracticeProgress} from '@trimmy/domain';
import {buildApp} from '../../src/app.js';
import {PostgresPracticeRepository} from '../../src/postgres-practice-repository.js';

const socket = process.env['TRIMMY_PRACTICE_TEST_SOCKET'];
assert.ok(socket?.endsWith('/infra/.practice-runtime/socket'),
  'Only the exclusively owned private database runner is supported.');
assert.equal(process.env['TRIMMY_PRACTICE_TEST_PORT'], '65438');
const pool = new Pool({host: socket, port: 65438, database: 'postgres',
  user: 'trimmy_practice_test_app', max: 2});
const repository = new PostgresPracticeRepository(pool);
const userId = 'fd000000-0000-4000-a000-000000000001';
const branchMutation = 'fd000000-0000-4000-b000-000000000010';
const returnedMutation = 'fd000000-0000-4000-b000-000000000011';
const followUpMutation = 'fd000000-0000-4000-b000-000000000012';
const app = buildApp({logger: false, practice: {repository, authenticate: async request =>
  request.headers.authorization === 'Bearer v5-fixture' ? {userId} : null}});

function v4History(): PracticeProgress {
  const contract = JSON.parse(readFileSync(new URL(
    '../../../../contracts/practice-progress-v4.json', import.meta.url), 'utf8')) as {
      cases: {name: string; progress: unknown}[];
    };
  return parsePracticeProgress(contract.cases.find(
    item => item.name === 'prepare-the-comparison-closed')!.progress);
}
const historical = v4History();
const completedAt = '2026-09-14T18:00:00.123456Z';
function addCompletion(progress: PracticeProgress, activityId: string,
  selectedChoiceId: string, corrected = false): PracticeProgress {
  return parsePracticeProgress({...progress, version: 5, active: null, completions: {
    ...progress.completions,
    [activityId]: {activityId, selectedChoiceId, corrected, completedAt, importedFromLegacy: false},
  }});
}
const branch = addCompletion(historical, 'review-team-update', 'request-missing-costs');
const returned = addCompletion(branch, 'read-returned-costs', 'compare-sales-and-costs');
const finished = addCompletion(returned, 'finish-team-update', 'apply-returned-figures');

function get() {
  return app.inject({method: 'GET', url: '/v1/practice/progress',
    headers: {authorization: 'Bearer v5-fixture'}});
}
function put(progress: PracticeProgress, baseRevision: number, mutationId: string) {
  return app.inject({method: 'PUT', url: '/v1/practice/progress',
    headers: {authorization: 'Bearer v5-fixture'},
    payload: {schemaVersion: 1, mutationId, baseRevision, progress}});
}

before(async () => { await app.ready(); });
after(async () => { await app.close(); await pool.end(); });

if (process.env['TRIMMY_PRACTICE_TEST_RECOVERY'] === '1') {
  test('restart retains the original v4 receipt, first team branch and completed branch follow-up', async () => {
    const current = await get();
    assert.equal(current.statusCode, 200, current.body);
    assert.equal(current.json().revision, 4);
    assert.deepEqual(current.json().progress, finished);
    assert.equal(current.json().progress.completions['review-team-update'].selectedChoiceId,
      'request-missing-costs');
    assert.deepEqual(current.json().progress.completions['check-the-date'],
      historical.completions['check-the-date']);
    const replay = await put(branch, 1, branchMutation);
    assert.equal(replay.statusCode, 200, replay.body);
    assert.equal(replay.json().revision, 2);
    assert.deepEqual(replay.json().progress, branch);
    const client = await pool.connect();
    try {
      await client.query('BEGIN READ ONLY');
      await client.query("SELECT set_config('trimmy.practice_user_id', $1, true)", [userId]);
      const oldReceipt = await client.query<{version: unknown; request_hash: unknown}>(
        `SELECT progress->'version' AS version, request_hash
         FROM trimmy.practice_mutation_receipts
         WHERE user_id=$1::uuid AND mutation_id='fd000000-0000-4000-b000-000000000001'::uuid`,
        [userId]);
      assert.deepEqual(oldReceipt.rows, [{version: 4, request_hash: 'd'.repeat(64)}]);
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  });
} else {
  test('migration exposes the complete v4 history unchanged before the first v5 write', async () => {
    const current = await get();
    assert.equal(current.statusCode, 200, current.body);
    assert.equal(current.json().revision, 1);
    assert.deepEqual(current.json().progress, historical);
  });

  test('persists a defensible request before returning it and follows that exact branch to rejoin', async () => {
    const savedBranch = await put(branch, 1, branchMutation);
    assert.equal(savedBranch.statusCode, 200, savedBranch.body);
    assert.equal(savedBranch.json().revision, 2);
    assert.equal(savedBranch.json().progress.completions['review-team-update'].corrected, false);
    assert.deepEqual(savedBranch.json().progress.completions['check-the-date'],
      historical.completions['check-the-date']);

    const savedReturned = await put(returned, 2, returnedMutation);
    assert.equal(savedReturned.statusCode, 200, savedReturned.body);
    assert.equal(savedReturned.json().revision, 3);
    const savedFollowUp = await put(finished, 3, followUpMutation);
    assert.equal(savedFollowUp.statusCode, 200, savedFollowUp.body);
    assert.equal(savedFollowUp.json().revision, 4);
    assert.deepEqual(savedFollowUp.json().progress, finished);

    const replay = await put(branch, 1, branchMutation);
    assert.equal(replay.statusCode, 200, replay.body);
    assert.equal(replay.json().revision, 2);
    assert.deepEqual((await get()).json().progress, finished);
  });

  test('rejects rebinding or replacing the first team branch after its consequence', async () => {
    const opposite = addCompletion(historical, 'review-team-update', 'share-qualified-sales');
    const rebound = await put(opposite, 1, branchMutation);
    assert.equal(rebound.statusCode, 409, rebound.body);
    assert.equal(rebound.json().error.code, 'PRACTICE_IDEMPOTENCY_CONFLICT');
    const rewrite = await put(parsePracticeProgress({...finished, completions: {
      ...finished.completions,
      'review-team-update': opposite.completions['review-team-update'],
    }}), 4, 'fd000000-0000-4000-b000-000000000013');
    assert.equal(rewrite.statusCode, 409, rewrite.body);
    assert.equal(rewrite.json().error.code, 'PRACTICE_HISTORY_CONFLICT');
    assert.equal((await get()).json().progress.completions['review-team-update'].selectedChoiceId,
      'request-missing-costs');
  });
}
