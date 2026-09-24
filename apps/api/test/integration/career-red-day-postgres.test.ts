import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {after, describe, it} from 'node:test';
import {Pool} from 'pg';
import type {CanonicalRedDaySession, RedDayRequestAudit} from '../../src/career-red-day-market.js';
import {PostgresCareerRedDayRepository} from '../../src/career-red-day-repository.js';

const socket = process.env['TRIMMY_RED_DAY_TEST_SOCKET'];
assert.ok(socket?.endsWith('/infra/.red-day-runtime/socket'),
  'Use the private red-day PostgreSQL runner; never attach to another database.');
assert.equal(process.env['TRIMMY_RED_DAY_TEST_PORT'], '65447');
const connection = {host: socket, port: 65447, database: 'postgres', connectionTimeoutMillis: 3_000};
const owner = new Pool({...connection, user: 'trimmy_red_day_test_owner', max: 2});
const workerPool = new Pool({...connection, user: 'trimmy_red_day_test_worker',
  options: '-c role=trimmy_red_day_test_verifier', max: 3});
const workerLoginPool = new Pool({...connection, user: 'trimmy_red_day_test_worker', max: 1});
const apiPool = new Pool({...connection, user: 'trimmy_red_day_test_api', max: 1});
const repository = new PostgresCareerRedDayRepository(workerPool);

after(async () => { await Promise.all([
  owner.end(), workerPool.end(), workerLoginPool.end(), apiPool.end(),
]); });

function audit(assetId: string, observedAt: number): RedDayRequestAudit {
  const to = Math.floor(observedAt / 1000);
  return Object.freeze({detailRequestId: randomUUID(), chartRequestId: randomUUID(),
    detailProviderRequestId: 'provider-detail-fixture', chartProviderRequestId: 'provider-chart-fixture',
    detailPath: `/v1/assets/${assetId}`,
    chartPath: `/v1/assets/${assetId}/price-chart?interval=1D&from=${to - 35 * 86_400}&to=${to}`,
    detailResponseSha256: 'a'.repeat(64), chartResponseSha256: 'b'.repeat(64)});
}

function observation(input: {assetId?: string; symbol?: string; previousDate: string;
  date: string; previousClose: string; close: string; observedAt?: number}): CanonicalRedDaySession {
  const observedAt = input.observedAt ?? Date.now();
  return Object.freeze({provider: 'tokens-xyz-v1', source: 'clickhouse_stock',
    verifierVersion: 'tokens-canonical-red-day-v1', assetId: input.assetId ?? 'apple',
    listedSymbol: input.symbol ?? 'AAPL', previousMarketDate: input.previousDate,
    marketDate: input.date, previousCloseText: input.previousClose,
    currentCloseText: input.close,
    outcome: Number(input.close) < Number(input.previousClose) ? 'verified-red' : 'verified-not-red',
    providerAsOf: '2026-09-18T21:00:00.000Z',
    providerLastFetchedAt: new Date(observedAt - 5_000).toISOString(),
    observedAt: new Date(observedAt).toISOString(), audit: audit(input.assetId ?? 'apple', observedAt)});
}

function unavailable(assetId: string, observationId: string,
  reasonCode: 'asset-not-in-catalog' | 'provider-auth-failed' | 'provider-rate-limited' = 'asset-not-in-catalog') {
  const observedAt = new Date().toISOString();
  return Object.freeze({observationId, provider: 'tokens-xyz-v1' as const,
    verifierVersion: 'tokens-canonical-red-day-v1' as const, assetId,
    listedSymbol: reasonCode === 'asset-not-in-catalog' ? null : assetId.toUpperCase(),
    status: reasonCode === 'asset-not-in-catalog' ? 'rejected' as const : 'unavailable' as const,
    reasonCode, observedAt,
    audit: Object.freeze({detailRequestId: randomUUID(), chartRequestId: null,
      detailProviderRequestId: null, chartProviderRequestId: null,
      detailPath: `/v1/assets/${assetId}`, chartPath: null,
      detailResponseSha256: null, chartResponseSha256: null})});
}

const heldUsers = [
  '92100000-0000-4000-8000-000000000001',
  '92100000-0000-4000-8000-000000000004',
  '92100000-0000-4000-8000-000000000007',
];

if (process.env['TRIMMY_RED_DAY_TEST_RECOVERY'] === '1') {
  it('recovers canonical evidence, completions and rewards after PostgreSQL restart', async () => {
    assert.equal((await owner.query(`SELECT count(*)::integer AS count
      FROM trimmy.career_red_day_sessions WHERE asset_id='apple'`)).rows[0]?.count, 2);
    assert.equal((await owner.query(`SELECT count(*)::integer AS count
      FROM trimmy.career_red_day_user_evidence WHERE evidence_outcome='qualified'`)).rows[0]?.count, 3);
    assert.deepEqual((await owner.query(`SELECT user_id::text AS user_id
      FROM trimmy.career_mission_completions WHERE mission_id='hold-through-red-day'
      ORDER BY user_id`)).rows.map(row => row.user_id), heldUsers);
    for (const userId of heldUsers) {
      const profile = (await owner.query(`SELECT trims_total::integer AS trims
        FROM trimmy.career_profiles WHERE user_id=$1`, [userId])).rows[0];
      assert.equal(profile?.trims, 70);
    }
  });
} else describe('Career red-day PostgreSQL evidence', () => {
  it('keeps New York session instants correct in standard and daylight time', async () => {
    const result = await owner.query(`SELECT
      trimmy.career_red_day_session_open('2026-01-15') AS winter_open,
      trimmy.career_red_day_session_close('2026-01-15') AS winter_close,
      trimmy.career_red_day_session_open('2026-07-15') AS summer_open,
      trimmy.career_red_day_session_close('2026-07-15') AS summer_close`);
    const row = result.rows[0];
    assert.equal(row.winter_open.toISOString(), '2026-01-15T14:30:00.000Z');
    assert.equal(row.winter_close.toISOString(), '2026-01-15T21:00:00.000Z');
    assert.equal(row.summer_open.toISOString(), '2026-07-15T13:30:00.000Z');
    assert.equal(row.summer_close.toISOString(), '2026-07-15T20:00:00.000Z');
  });

  it('gives the API no evidence access and gives the worker only fixed functions', async () => {
    for (const query of [
      'SELECT * FROM trimmy.career_red_day_candidates(1)',
      'SELECT * FROM trimmy.career_red_day_pending_sessions(1)',
      `SELECT * FROM trimmy.career_red_day_provider_observations`,
      `SELECT trimmy.career_server_mission_complete(
        '92100000-0000-4000-8000-000000000001','hold-through-red-day',
        '92100000-0000-4000-8000-000000000099',clock_timestamp())`,
    ]) await assert.rejects(apiPool.query(query), {code: '42501'});
    for (const query of [
      'SELECT * FROM trimmy.career_red_day_provider_observations',
      'SELECT * FROM trimmy.career_red_day_user_evidence',
      `SELECT trimmy.career_server_mission_complete(
        '92100000-0000-4000-8000-000000000001','hold-through-red-day',
        '92100000-0000-4000-8000-000000000099',clock_timestamp())`,
    ]) await assert.rejects(workerPool.query(query), {code: '42501'});
    for (const query of [
      'SELECT * FROM trimmy.career_red_day_candidates(1)',
      'SELECT * FROM trimmy.career_red_day_provider_observations',
    ]) await assert.rejects(workerLoginPool.query(query), {code: '42501'});
    assert.deepEqual((await owner.query(`WITH RECURSIVE reachable(oid) AS (
        SELECT oid FROM pg_catalog.pg_roles WHERE rolname='trimmy_red_day_test_worker'
        UNION SELECT membership.roleid FROM pg_catalog.pg_auth_members membership
          JOIN reachable reachable_role ON reachable_role.oid=membership.member)
      SELECT r.rolname, r.rolcanlogin, r.rolinherit, r.rolsuper, r.rolbypassrls
      FROM reachable JOIN pg_catalog.pg_roles r ON r.oid=reachable.oid
      ORDER BY r.rolname`)).rows, [
      {rolname: 'trimmy_red_day_test_verifier', rolcanlogin: false,
        rolinherit: false, rolsuper: false, rolbypassrls: false},
      {rolname: 'trimmy_red_day_test_worker', rolcanlogin: true,
        rolinherit: false, rolsuper: false, rolbypassrls: false},
    ]);
    assert.deepEqual((await owner.query(`WITH RECURSIVE ingress(oid) AS (
        SELECT oid FROM pg_catalog.pg_roles WHERE rolname='trimmy_red_day_test_verifier'
        UNION SELECT membership.member FROM pg_catalog.pg_auth_members membership
          JOIN ingress granted_role ON granted_role.oid=membership.roleid)
      SELECT r.rolname FROM ingress JOIN pg_catalog.pg_roles r ON r.oid=ingress.oid
      WHERE r.rolname<>'trimmy_red_day_test_verifier' ORDER BY r.rolname`)).rows,
    [{rolname: 'trimmy_red_day_test_worker'}]);
    const exactFunctions = await owner.query(`SELECT count(*)::integer AS count
      FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='trimmy'
        AND has_function_privilege('trimmy_red_day_test_verifier',p.oid,'EXECUTE')`);
    assert.equal(exactFunctions.rows[0]?.count, 4);
    assert.deepEqual(await repository.candidates(20), [
      {assetId: 'alpha', afterMarketDate: null},
      {assetId: 'apple', afterMarketDate: null},
      {assetId: 'beta', afterMarketDate: null},
      {assetId: 'delta', afterMarketDate: null},
      {assetId: 'gamma', afterMarketDate: null},
      {assetId: 'omega', afterMarketDate: null},
    ]);
    assert.deepEqual(await repository.pendingSessions(20), []);
  });

  it('backs off failures, bounds audit growth and rotates unattempted assets through a small limit', async () => {
    assert.deepEqual(await repository.candidates(1), [{assetId: 'alpha', afterMarketDate: null}]);
    const alphaId = randomUUID();
    const alphaFailure = unavailable('alpha', alphaId);
    assert.equal((await repository.record(alphaFailure)).outcome, 'recorded');
    assert.deepEqual(await repository.candidates(2), [
      {assetId: 'apple', afterMarketDate: null}, {assetId: 'beta', afterMarketDate: null},
    ]);
    assert.equal((await repository.record(unavailable('apple', randomUUID()))).outcome, 'recorded');
    assert.equal((await repository.record(unavailable('beta', randomUUID()))).outcome, 'recorded');
    assert.deepEqual(await repository.candidates(2), [
      {assetId: 'delta', afterMarketDate: null}, {assetId: 'gamma', afterMarketDate: null},
    ]);
    assert.equal((await repository.record(alphaFailure)).outcome, 'already-recorded');
    assert.equal((await owner.query(`SELECT count(*)::integer AS count
      FROM trimmy.career_red_day_provider_observations
      WHERE asset_id='alpha'`)).rows[0]?.count, 1);
    assert.equal((await owner.query(`SELECT consecutive_failures AS count
      FROM trimmy.career_red_day_asset_state WHERE asset_id='alpha'`)).rows[0]?.count, 1);

    assert.equal((await repository.record(unavailable('delta', randomUUID(),
      'provider-auth-failed'))).outcome, 'recorded');
    assert.deepEqual(await repository.candidates(20), []);
    await repository.record({observationId: randomUUID(), session: observation({
      assetId: 'delta', symbol: 'DELTA', previousDate: '2026-09-16', date: '2026-09-17',
      previousClose: '100', close: '101',
    })});
    assert.deepEqual(await repository.candidates(20), [
      {assetId: 'gamma', afterMarketDate: null}, {assetId: 'omega', afterMarketDate: null},
    ]);
    assert.equal((await repository.record(unavailable('gamma', randomUUID(),
      'provider-rate-limited'))).outcome, 'recorded');
    assert.deepEqual(await repository.candidates(20), []);
    await repository.record({observationId: randomUUID(), session: observation({
      assetId: 'gamma', symbol: 'GAMMA', previousDate: '2026-09-16', date: '2026-09-17',
      previousClose: '100', close: '101',
    })});
    assert.deepEqual(await repository.candidates(20), [{assetId: 'omega', afterMarketDate: null}]);
  });

  it('records a green provider session without user evidence or Trims', async () => {
    const cashBefore = (await owner.query(`SELECT user_id::text, cash_micros::text
      FROM trimmy.paper_accounts WHERE user_id::text LIKE '92100000-%' ORDER BY user_id`)).rows;
    const result = await repository.record({observationId: randomUUID(), session: observation({
      previousDate: '2026-09-16', date: '2026-09-17', previousClose: '330', close: '337',
    })});
    assert.deepEqual(result, {outcome: 'recorded', observationId: result.observationId,
      evidenceCount: 0, completedCount: 0});
    assert.deepEqual((await owner.query(`SELECT o.observation_status AS status,
      s.processing_complete AS complete
      FROM trimmy.career_red_day_sessions s
      JOIN trimmy.career_red_day_provider_observations o USING (observation_id)
      WHERE s.observation_id=$1`, [result.observationId])).rows,
    [{status: 'verified-not-red', complete: true}]);
    assert.equal((await owner.query(`SELECT count(*)::integer AS count
      FROM trimmy.career_red_day_user_evidence`)).rows[0]?.count, 0);
    const cashAfter = (await owner.query(`SELECT user_id::text, cash_micros::text
      FROM trimmy.paper_accounts WHERE user_id::text LIKE '92100000-%' ORDER BY user_id`)).rows;
    assert.deepEqual(cashAfter, cashBefore);
  });

  it('reconstructs every variant through the inclusive close and rewards only continuous holds', async () => {
    const cashBefore = (await owner.query(`SELECT user_id::text, cash_micros::text
      FROM trimmy.paper_accounts WHERE user_id::text = ANY($1::text[]) ORDER BY user_id`, [heldUsers])).rows;
    const observationId = randomUUID();
    const red = observation({previousDate: '2026-09-17', date: '2026-09-18',
      previousClose: '337', close: '334.79'});
    const result = await repository.record({observationId, session: red});
    assert.deepEqual(result, {outcome: 'recorded', observationId, evidenceCount: 0, completedCount: 0});
    assert.deepEqual(await repository.pendingSessions(20), [
      {observationId, assetId: 'apple', marketDate: '2026-09-18'},
    ]);
    const firstBatch = await repository.processSession(observationId, 3);
    const secondBatch = await repository.processSession(observationId, 3);
    const thirdBatch = await repository.processSession(observationId, 3);
    const seller = await owner.connect();
    let fourthSettled = false;
    try {
      await seller.query('BEGIN');
      await seller.query(`SELECT public.red_day_test_order(
        '92100000-0000-4000-8000-000000000011'::uuid, 'apple',
        'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', 'sell', 1000000,
        '2026-09-18T15:00:00Z'::timestamptz)`);
      const fourthPromise = repository.processSession(observationId, 3)
        .then(value => { fourthSettled = true; return value; });
      await new Promise(resolve => setTimeout(resolve, 150));
      assert.equal(fourthSettled, false, 'verifier must wait for the in-flight paper transaction');
      await seller.query('COMMIT');
      const fourthBatch = await fourthPromise;
      assert.deepEqual([firstBatch.outcome, secondBatch.outcome, thirdBatch.outcome, fourthBatch.outcome],
        ['processed', 'processed', 'processed', 'complete']);
      assert.deepEqual([firstBatch.evidenceCount, secondBatch.evidenceCount,
        thirdBatch.evidenceCount, fourthBatch.evidenceCount], [3, 3, 3, 1]);
      assert.equal(firstBatch.completedCount + secondBatch.completedCount +
        thirdBatch.completedCount + fourthBatch.completedCount, 3);
    } finally {
      await seller.query('ROLLBACK').catch(() => {});
      seller.release();
    }
    assert.deepEqual(await repository.pendingSessions(20), []);
    const qualified = (await owner.query(`SELECT user_id::text AS user_id,
      opening_quantity_micros::text AS opening, minimum_session_quantity_micros::text AS minimum,
      session_open_at, session_close_at
      FROM trimmy.career_red_day_user_evidence WHERE evidence_outcome='qualified'
      ORDER BY user_id`)).rows;
    assert.deepEqual(qualified.map(row => row.user_id), heldUsers);
    assert.deepEqual(qualified.map(row => [row.opening, row.minimum]),
      [['1000000', '1000000'], ['1000000', '500000'], ['1000000', '1000000']]);
    assert.ok(qualified.every(row => row.session_open_at.toISOString() === '2026-09-18T13:30:00.000Z'));
    assert.ok(qualified.every(row => row.session_close_at.toISOString() === '2026-09-18T20:00:00.000Z'));
    const rejected = (await owner.query(`SELECT user_id::text AS user_id, reason_code, count(*)::integer AS count
      FROM trimmy.career_red_day_user_evidence WHERE evidence_outcome='not-held-throughout'
      GROUP BY user_id, reason_code ORDER BY user_id, reason_code`)).rows;
    assert.deepEqual(rejected, [
      {user_id: '92100000-0000-4000-8000-000000000002', reason_code: 'not-positive-at-open', count: 1},
      {user_id: '92100000-0000-4000-8000-000000000003', reason_code: 'not-positive-at-open', count: 1},
      {user_id: '92100000-0000-4000-8000-000000000005', reason_code: 'position-reached-zero', count: 1},
      {user_id: '92100000-0000-4000-8000-000000000006', reason_code: 'position-reached-zero', count: 1},
      {user_id: '92100000-0000-4000-8000-000000000008', reason_code: 'not-positive-at-open', count: 2},
      {user_id: '92100000-0000-4000-8000-000000000011', reason_code: 'position-reached-zero', count: 1},
    ]);
    assert.deepEqual((await owner.query(`SELECT user_id::text AS user_id
      FROM trimmy.career_mission_completions WHERE mission_id='hold-through-red-day'
      ORDER BY user_id`)).rows.map(row => row.user_id), heldUsers);
    for (const userId of heldUsers) {
      assert.equal((await owner.query(`SELECT trims_total::integer AS trims
        FROM trimmy.career_profiles WHERE user_id=$1`, [userId])).rows[0]?.trims, 70);
    }
    assert.deepEqual((await owner.query(`SELECT user_id::text, cash_micros::text
      FROM trimmy.paper_accounts WHERE user_id::text = ANY($1::text[]) ORDER BY user_id`, [heldUsers])).rows, cashBefore);

    const replay = await repository.record({observationId, session: red});
    assert.deepEqual(replay, {outcome: 'already-recorded', observationId,
      evidenceCount: 10, completedCount: 3});
    assert.deepEqual(await repository.processSession(observationId, 3), {
      outcome: 'already-complete', observationId, evidenceCount: 0,
      completedCount: 0, processingComplete: true,
    });
    const duplicateId = randomUUID();
    const duplicate = await repository.record({observationId: duplicateId,
      session: {...red, observedAt: new Date().toISOString(), audit: audit('apple', Date.now())}});
    assert.deepEqual(duplicate, {outcome: 'already-recorded', observationId: duplicateId,
      evidenceCount: 0, completedCount: 0});
    assert.equal((await owner.query(`SELECT count(*)::integer AS count
      FROM trimmy.career_red_day_provider_observations
      WHERE asset_id='apple' AND market_date='2026-09-18'`)).rows[0]?.count, 1);

    const greenCorrectionId = randomUUID();
    const greenCorrection = await repository.record({observationId: greenCorrectionId,
      session: {...red, outcome: 'verified-not-red', currentCloseText: '338',
        observedAt: new Date().toISOString(), audit: audit('apple', Date.now())}});
    assert.equal(greenCorrection.outcome, 'correction-review');
    const repeatedGreen = await repository.record({observationId: randomUUID(),
      session: {...red, outcome: 'verified-not-red', currentCloseText: '338',
        observedAt: new Date().toISOString(), audit: audit('apple', Date.now())}});
    assert.equal(repeatedGreen.outcome, 'already-reviewed');
    assert.equal((await owner.query(`SELECT count(*)::integer AS count
      FROM trimmy.career_red_day_provider_observations
      WHERE asset_id='apple' AND market_date='2026-09-18'`)).rows[0]?.count, 2);
    assert.equal((await owner.query(`SELECT count(*)::integer AS count
      FROM trimmy.career_red_day_correction_reviews
      WHERE canonical_observation_id=$1`, [observationId])).rows[0]?.count, 1);
    const closeCorrectionId = randomUUID();
    const closeCorrection = await repository.record({observationId: closeCorrectionId,
      session: {...red, currentCloseText: '333', observedAt: new Date().toISOString(),
        audit: audit('apple', Date.now())}});
    assert.equal(closeCorrection.outcome, 'correction-review');
    assert.deepEqual((await owner.query(`SELECT review_observation_id::text AS id,
      identity_changed, outcome_changed, close_changed, review_status
      FROM trimmy.career_red_day_correction_reviews
      WHERE canonical_observation_id=$1 ORDER BY review_observation_id`, [observationId])).rows,
    [
      {id: [greenCorrectionId, closeCorrectionId].sort()[0], identity_changed: false,
        outcome_changed: greenCorrectionId < closeCorrectionId, close_changed: true, review_status: 'open'},
      {id: [greenCorrectionId, closeCorrectionId].sort()[1], identity_changed: false,
        outcome_changed: !(greenCorrectionId < closeCorrectionId), close_changed: true, review_status: 'open'},
    ]);
    assert.deepEqual((await owner.query(`SELECT user_id::text AS user_id
      FROM trimmy.career_mission_completions WHERE mission_id='hold-through-red-day'
      ORDER BY user_id`)).rows.map(row => row.user_id), heldUsers);
    for (const userId of heldUsers) {
      assert.equal((await owner.query(`SELECT trims_total::integer AS trims
        FROM trimmy.career_profiles WHERE user_id=$1`, [userId])).rows[0]?.trims, 70);
    }
    assert.equal((await owner.query(`SELECT count(*)::integer AS count
      FROM trimmy.career_red_day_sessions
      WHERE asset_id='apple' AND market_date='2026-09-18'`)).rows[0]?.count, 1);
  });

  it('serializes concurrent canonical sessions without growing unchanged recheck rows', async () => {
    const shared = observation({assetId: 'microsoft', symbol: 'MSFT',
      previousDate: '2026-09-17', date: '2026-09-18', previousClose: '100', close: '101'});
    const first = randomUUID(), second = randomUUID();
    const results = await Promise.all([
      repository.record({observationId: first, session: shared}),
      repository.record({observationId: second, session: {...shared,
        observedAt: new Date().toISOString(), audit: audit('microsoft', Date.now())}}),
    ]);
    assert.deepEqual(results.map(value => value.outcome).sort(), ['already-recorded', 'recorded']);
    assert.equal((await owner.query(`SELECT count(*)::integer AS count
      FROM trimmy.career_red_day_provider_observations WHERE asset_id='microsoft'`)).rows[0]?.count, 1);
    assert.equal((await owner.query(`SELECT count(*)::integer AS count
      FROM trimmy.career_red_day_sessions WHERE asset_id='microsoft'`)).rows[0]?.count, 1);
  });

  it('captures a queued reason timestamp only after its Career lock is acquired', async () => {
    const profile = await owner.query(`SELECT outcome FROM trimmy.product_profile_put(
      $1,$2,$3,0,'learn','basics','wolf','one-mission','queued_reason','first-trade')`, [
      '92100000-0000-4000-8000-000000000010', randomUUID(), 'e'.repeat(64),
    ]);
    assert.equal(profile.rows[0]?.outcome, 'saved');
    const blocker = await owner.connect();
    const caller = await owner.connect();
    let settled = false;
    try {
      const order = (await caller.query(`SELECT id FROM trimmy.paper_orders
        WHERE user_id='92100000-0000-4000-8000-000000000010' AND action='buy'
        ORDER BY committed_at, id LIMIT 1`)).rows[0]?.id;
      assert.ok(order);
      await blocker.query('BEGIN');
      await blocker.query(`SELECT pg_advisory_xact_lock(hashtextextended(
        'trimmy.career:92100000-0000-4000-8000-000000000010', 0))`);
      const reasonPromise = caller.query(`SELECT outcome, saved_at
        FROM trimmy.career_trade_reason_put($1,$2,$3,$4,$5)`, [
        '92100000-0000-4000-8000-000000000010', randomUUID(), 'd'.repeat(64), order,
        'The verified trend supports keeping this paper position.',
      ]).then(value => { settled = true; return value; });
      await new Promise(resolve => setTimeout(resolve, 150));
      assert.equal(settled, false);
      const releaseFloor = (await blocker.query('SELECT clock_timestamp() AS now')).rows[0]?.now as Date;
      await blocker.query('COMMIT');
      const result = await reasonPromise;
      assert.equal(result.rows[0]?.outcome, 'saved');
      assert.ok(result.rows[0]?.saved_at.getTime() >= releaseFloor.getTime());
    } finally {
      await blocker.query('ROLLBACK').catch(() => {});
      blocker.release();
      caller.release();
    }
  });

  it('waits for an in-flight account closure and records no evidence for the closed user', async () => {
    const observationId = randomUUID();
    const result = await repository.record({observationId, session: observation({
      assetId: 'omega', symbol: 'OMEGA', previousDate: '2026-09-17',
      date: '2026-09-18', previousClose: '100', close: '99',
    })});
    assert.equal(result.outcome, 'recorded');
    const closer = await owner.connect();
    let settled = false;
    try {
      await closer.query('BEGIN');
      await closer.query("SELECT set_config('trimmy.practice_user_id',$1,true)", [
        '92100000-0000-4000-8000-000000000012',
      ]);
      assert.equal((await closer.query(
        'SELECT trimmy.practice_close_current_account() AS closed')).rows[0]?.closed, true);
      const pending = repository.processSession(observationId, 100)
        .then(value => { settled = true; return value; });
      await new Promise(resolve => setTimeout(resolve, 150));
      assert.equal(settled, false, 'verifier must wait for the in-flight closure row lock');
      await closer.query('COMMIT');
      const processed = await pending;
      assert.deepEqual(processed, {outcome: 'complete', observationId,
        evidenceCount: 0, completedCount: 0, processingComplete: true});
    } finally {
      await closer.query('ROLLBACK').catch(() => {});
      closer.release();
    }
    assert.equal((await owner.query(`SELECT count(*)::integer AS count
      FROM trimmy.career_red_day_user_evidence WHERE observation_id=$1`,
    [observationId])).rows[0]?.count, 0);
    assert.equal((await owner.query(`SELECT status FROM trimmy.users
      WHERE id='92100000-0000-4000-8000-000000000012'`)).rows[0]?.status, 'closed');
  });

  it('recaptures database time after a queued session lock and rejects stale evidence', async () => {
    const blocker = await owner.connect();
    let settled = false;
    try {
      await blocker.query('BEGIN');
      await blocker.query(`SELECT pg_advisory_xact_lock(hashtextextended(
        'trimmy.red-day:session:tokens-xyz-v1:queue-test:2026-09-18:tokens-canonical-red-day-v1', 0))`);
      const startedAt = Date.now() - 119_500;
      const pending = repository.record({observationId: randomUUID(), session: observation({
        assetId: 'queue-test', symbol: 'QUEUE', previousDate: '2026-09-17',
        date: '2026-09-18', previousClose: '100', close: '99', observedAt: startedAt,
      })}).then(value => { settled = true; return value; }, error => { settled = true; throw error; });
      await new Promise(resolve => setTimeout(resolve, 1_200));
      assert.equal(settled, false);
      await blocker.query('COMMIT');
      await assert.rejects(pending, {code: '22023'});
    } finally {
      await blocker.query('ROLLBACK').catch(() => {});
      blocker.release();
    }
  });

  it('rejects stale clocks, noncanonical paths and an observation UUID rebound', async () => {
    const base = observation({assetId: 'nvidia', symbol: 'NVDA', previousDate: '2026-09-17',
      date: '2026-09-18', previousClose: '100', close: '99'});
    await assert.rejects(repository.record({observationId: randomUUID(), session: {
      ...base, observedAt: '2026-09-18T21:00:00.000Z',
    }}), {code: '22023'});
    const missingProviderSymbol = unavailable('symbol-check', randomUUID(), 'provider-auth-failed');
    await assert.rejects(repository.record({...missingProviderSymbol, listedSymbol: null}), {code: '22023'});
    const inventedCatalogSymbol = unavailable('catalog-check', randomUUID());
    await assert.rejects(repository.record({...inventedCatalogSymbol, listedSymbol: 'FAKE'}), {code: '22023'});
    await assert.rejects(repository.record({observationId: randomUUID(), session: {
      ...base, audit: {...base.audit,
        chartPath: '/v1/assets/nvidia/price-chart?interval=1D&from=1&to=2&mint=secret'},
    }}), {code: '22023'});
    await assert.rejects(repository.record({observationId: randomUUID(), session: {
      ...base, previousCloseText: '9'.repeat(129),
    }}), {code: '22023'});
    await assert.rejects(repository.record({observationId: randomUUID(), session: {
      ...base, previousCloseText: `9e${'9'.repeat(100)}`,
    }}), {code: '22023', constraint: 'career_red_day_observation_input'});
    const recordUnchecked = (value: unknown) => repository.record(
      value as Parameters<typeof repository.record>[0]);
    const oversizedSessions: unknown[] = [
      {...base, provider: 'p'.repeat(65)},
      {...base, verifierVersion: 'v'.repeat(65)},
      {...base, assetId: 'a'.repeat(101)},
      {...base, listedSymbol: 'S'.repeat(16)},
      {...base, outcome: 's'.repeat(33)},
      {...base, currentCloseText: '9'.repeat(129)},
      {...base, source: 's'.repeat(65)},
      {...base, audit: {...base.audit, detailProviderRequestId: 'd'.repeat(161)}},
      {...base, audit: {...base.audit, chartProviderRequestId: 'c'.repeat(161)}},
      {...base, audit: {...base.audit, detailPath: `/${'d'.repeat(128)}`}},
      {...base, audit: {...base.audit, chartPath: `/${'c'.repeat(300)}`}},
      {...base, audit: {...base.audit, detailResponseSha256: 'a'.repeat(65)}},
      {...base, audit: {...base.audit, chartResponseSha256: 'b'.repeat(65)}},
    ];
    for (const session of oversizedSessions) {
      await assert.rejects(recordUnchecked({observationId: randomUUID(), session}),
        {code: '22023', constraint: 'career_red_day_observation_input'});
    }
    const failed = unavailable('failure-bounds', randomUUID(), 'provider-auth-failed');
    await assert.rejects(recordUnchecked({...failed, reasonCode: 'r'.repeat(65)}),
      {code: '22023', constraint: 'career_red_day_observation_input'});
    await assert.rejects(recordUnchecked({...failed, observationId: randomUUID(), status: null}),
      {code: '22023', constraint: 'career_red_day_observation_input'});
    const observationId = randomUUID();
    const accepted = await repository.record({observationId, session: base});
    assert.equal(accepted.outcome, 'recorded');
    const rebound = await repository.record({observationId, session: {...base, currentCloseText: '98'}});
    assert.equal(rebound.outcome, 'idempotency-conflict');
  });
});
