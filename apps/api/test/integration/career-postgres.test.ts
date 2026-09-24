import assert from 'node:assert/strict';
import {createHash, randomUUID} from 'node:crypto';
import {after, before, describe, test} from 'node:test';
import {Pool} from 'pg';
import {buildApp} from '../../src/app.js';
import {
  CAREER_ACTIVITY_WEEK_ROUTE,
  CAREER_DAY_CONTEXT_ROUTE,
  CAREER_MISSIONS_ROUTE,
  CAREER_PROMOTION_ROUTE,
  CAREER_REASON_ROUTE,
  CAREER_SUMMARY_ROUTE,
  createCareerAuthenticator,
} from '../../src/career-routes.js';
import {CareerRepositoryError} from '../../src/career-repository.js';
import {
  hashGuestCreationRequest,
  hashGuestCredential,
  hashGuestReplaySecret,
} from '../../src/guest-session-routes.js';
import {PostgresCareerRepository} from '../../src/postgres-career-repository.js';
import {PostgresCareerRedDayRepository} from '../../src/career-red-day-repository.js';
import {PostgresGuestSessionRepository} from '../../src/postgres-guest-session-repository.js';
import {PostgresPaperTradingRepository} from '../../src/postgres-paper-trading-repository.js';
import {PostgresPracticeAccounts} from '../../src/postgres-practice-accounts.js';
import {PostgresProductProfileRepository} from '../../src/postgres-product-profile-repository.js';
import type {AcceptedPaperPrice} from '../../src/paper-price-reader.js';
import type {PaperCommittedOrder} from '../../src/paper-trading-repository.js';
import type {PracticeIdentity} from '../../src/practice-identity.js';
import {requestPracticeBearerToken} from '../../src/practice-session-routes.js';

const socket = process.env['TRIMMY_PRACTICE_TEST_SOCKET'];
assert.ok(socket?.endsWith('/infra/.practice-runtime/socket'),
  'Use the private test runner; never attach to an external database.');
assert.equal(process.env['TRIMMY_PRACTICE_TEST_PORT'], '65438');
const connection = {host: socket, port: 65438, database: 'postgres', connectionTimeoutMillis: 3000};
const runtimePool = new Pool({...connection, user: 'trimmy_practice_test_app', max: 5});
const paperPool = new Pool({...connection, user: 'trimmy_paper_test_app', max: 3});
const owner = new Pool({...connection, user: 'trimmy_test_owner', max: 2});
const careers = new PostgresCareerRepository(runtimePool);
const redDays = new PostgresCareerRedDayRepository(owner);
const guests = new PostgresGuestSessionRepository(runtimePool);
const profiles = new PostgresProductProfileRepository(runtimePool);
const accounts = new PostgresPracticeAccounts(runtimePool);
const paper = new PostgresPaperTradingRepository(paperPool);

const mint = 'XsP7xzNPvEHS1m6qfanPUGjNmdMVPckE3hER9uE7p6H';
const normalGuestId = '92000000-0000-4000-8000-000000000001';
const normalGuestToken = `tg1_${'N'.repeat(43)}`;
const legacyGuestId = '92000000-0000-4000-8000-000000000002';
const legacyGuestToken = `tg1_${'L'.repeat(43)}`;
const normalReasonMutation = '92000000-0000-4000-8000-000000000011';
const legacyReasonMutation = '92000000-0000-4000-8000-000000000012';
const normalDayMutation = '92000000-0000-4000-8000-000000000013';
const normalFirstOrderId = '92000000-0000-4000-8000-000000000021';
const legacyOrderId = '92000000-0000-4000-8000-000000000022';
const backfilledUserId = '91800000-0000-4000-8000-000000000001';
const backfilledOrderId = '91800000-0000-4000-8000-000000000004';
const accountBearer = 'eyJhbGciOiJFUzI1NiJ9.eyJzdWIiOiJkaWQ6cHJpdnk6Y2FyZWVyIn0.c2lnbmF0dXJl'; // gitleaks:allow -- synthetic JWT fixture with deliberately invalid signature
const promotionBearer = 'eyJhbGciOiJFUzI1NiJ9.eyJzdWIiOiJkaWQ6cHJpdnk6cHJvbW90aW9uIn0.c2lnbmF0dXJl'; // gitleaks:allow -- synthetic JWT fixture with deliberately invalid signature
const accountIdentity: PracticeIdentity = {
  provider: 'privy', appId: 'career-postgres-test', subject: 'did:privy:careerpostgres',
};
const promotionIdentity: PracticeIdentity = {
  provider: 'privy', appId: 'career-postgres-test', subject: 'did:privy:careerpromotion',
};
const accountAuth = async (request: Parameters<ReturnType<typeof createCareerAuthenticator>>[0]) => {
  const bearer = requestPracticeBearerToken(request);
  const identity = bearer === accountBearer ? accountIdentity
    : bearer === promotionBearer ? promotionIdentity : null;
  if (!identity) return null;
  const account = await accounts.find(identity);
  return account ? {userId: account.userId} : null;
};
const app = buildApp({logger: false, career: {
  repository: careers,
  authenticate: createCareerAuthenticator(accountAuth, guests),
}});

before(async () => { await app.ready(); });
after(async () => {
  await app.close();
  await runtimePool.end();
  await paperPool.end();
  await owner.end();
});

const guestHeaders = (token: string) => ({authorization: `Guest ${token}`});
const summary = (token: string) => app.inject({url: CAREER_SUMMARY_ROUTE, headers: guestHeaders(token)});
const dayContext = (token: string) => app.inject({
  url: CAREER_DAY_CONTEXT_ROUTE, headers: guestHeaders(token),
});
const saveDayContext = (
  token: string,
  mutationId: string,
  baseRevision: number,
  timeZone: string,
) => app.inject({
  method: 'PUT', url: CAREER_DAY_CONTEXT_ROUTE, headers: guestHeaders(token),
  payload: {schemaVersion: 1, mutationId, baseRevision, timeZone},
});
const saveReason = (token: string, mutationId: string, orderId: string, note: string) => app.inject({
  method: 'POST', url: CAREER_REASON_ROUTE, headers: guestHeaders(token),
  payload: {schemaVersion: 1, mutationId, orderId, note},
});
const missionBoard = (token: string) => app.inject({url: CAREER_MISSIONS_ROUTE,
  headers: guestHeaders(token)});
const accountHeaders = (token: string) => ({authorization: `Bearer ${token}`});
const accountSummary = (token: string) => app.inject({url: CAREER_SUMMARY_ROUTE,
  headers: accountHeaders(token)});
const accountMissionBoard = (token: string) => app.inject({url: CAREER_MISSIONS_ROUTE,
  headers: accountHeaders(token)});
const promoteAccount = (token: string, mutationId: string, targetRank: string) => app.inject({
  method: 'POST', url: CAREER_PROMOTION_ROUTE, headers: accountHeaders(token),
  payload: {schemaVersion: 1, mutationId, targetRank},
});

function acceptedPrice(assetId: string): AcceptedPaperPrice {
  const acceptedAt = new Date().toISOString();
  return Object.freeze({
    assetId, variantMint: mint, symbol: `${assetId.slice(0, 4).toUpperCase()}x`,
    pricePaperMicros: '200000000',
    source: Object.freeze({provider: 'tokens-xyz-v1' as const,
      providerReference: `/v1/assets/${assetId}/variants#career-test`,
      marketSource: 'integration-fixture', metricsSource: null,
      providerTimestamps: Object.freeze({asOf: null, lastFetchedAt: null, lastTradeAt: null,
        unit: 'not_declared' as const}), observedAt: acceptedAt, acceptedAt}),
    expiresAt: new Date(Date.now() + 30_000).toISOString(),
  });
}

async function commitOrder(
  userId: string,
  action: 'buy' | 'sell',
  assetId: string,
  amount: {kind: 'paper_amount'; paperMicros: string} | {kind: 'share_quantity'; quantityMicros: string},
  selectedOrderId = randomUUID(),
): Promise<PaperCommittedOrder> {
  const preview = await paper.createPreview(userId, {
    id: randomUUID(), requestId: randomUUID(), requestHash: 'a'.repeat(64), action, amount,
    price: acceptedPrice(assetId),
  });
  return paper.commit(userId, {orderId: selectedOrderId, previewId: preview.id,
    idempotencyKey: randomUUID(), requestHash: 'b'.repeat(64)});
}

async function createGuest(
  guestId: string,
  token: string,
  requestId: string,
  replayByte: number,
  handle: string,
): Promise<string> {
  const replaySecret = `gr1_${Buffer.alloc(32, replayByte).toString('base64url')}`;
  const sourceHash = createHash('sha256').update(`career:${requestId}`).digest('hex');
  const admission = await guests.takeCreationAttempt(sourceHash);
  await guests.create({...admission, requestHash: hashGuestCreationRequest(requestId),
    replayHash: hashGuestReplaySecret(replaySecret), guestId,
    credentialHash: hashGuestCredential(token)});
  const principal = await guests.authorize(hashGuestCredential(token), 'profile_write');
  await profiles.put(principal.userId, {
    mutationId: randomUUID(), baseRevision: 0,
    onboarding: {goal: 'practice', knowledge: 'basics', persona: 'oracle',
      dailyGoal: 'one-mission', handle},
    launchCheckpoint: 'first-trade',
  });
  return principal.userId;
}

async function appendOwnerReasonAward(
  userId: string,
  order: PaperCommittedOrder,
  awardNumber: number,
): Promise<void> {
  const client = await owner.connect();
  try {
    await client.query('BEGIN');
    const progress = (await client.query<{revision: string; trims_total: string; updated_at: Date}>(
      `SELECT revision::text, trims_total::text, updated_at
       FROM trimmy.career_profiles WHERE user_id=$1 FOR UPDATE`, [userId])).rows[0];
    assert.ok(progress);
    const nextRevision = Number(progress.revision) + 1;
    const savedAt = new Date(Math.max(Date.now(), progress.updated_at.getTime() + 1));
    const mutationId = randomUUID();
    const note = `Server fixture reason ${awardNumber} has durable evidence.`;
    await client.query(`INSERT INTO trimmy.career_trade_reasons(
      order_id, user_id, asset_id, variant_mint, note, trims_awarded,
      daily_award_number, saved_at)
      VALUES ($1,$2,$3,$4,$5,10,$6,$7)`,
    [order.id, userId, order.assetId, order.variantMint, note,
      ((awardNumber - 1) % 3) + 1, savedAt]);
    await client.query(`INSERT INTO trimmy.career_reason_mutation_receipts(
      user_id, mutation_id, request_hash, order_id, asset_id, variant_mint,
      note, trims_awarded, daily_award_number, saved_at)
      VALUES ($1,$2,repeat('d',64),$3,$4,$5,$6,10,$7,$8)`,
    [userId, mutationId, order.id, order.assetId, order.variantMint, note,
      ((awardNumber - 1) % 3) + 1, savedAt]);
    await client.query(`INSERT INTO trimmy.career_trim_ledger(
      user_id, career_revision, entry_kind, source_id, trims, awarded_on, created_at)
      VALUES ($1,$2,'paper-reason',$3,10,($4::timestamptz AT TIME ZONE 'UTC')::date,$4)`,
    [userId, nextRevision, order.id, savedAt]);
    await client.query(`UPDATE trimmy.career_profiles SET revision=$2,
      trims_total=trims_total+10, updated_at=$3 WHERE user_id=$1`,
    [userId, nextRevision, savedAt]);
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally { client.release(); }
}

if (process.env['TRIMMY_PRACTICE_TEST_RECOVERY'] === '1') {
  test('a new process recovers Career totals and the exact reason receipt', async () => {
    const normal = await summary(normalGuestToken);
    assert.equal(normal.statusCode, 200, normal.body);
    assert.equal(normal.json().career.revision, 6);
    assert.equal(normal.json().career.trims.total, 70);
    assert.equal(normal.json().career.rank.id, 'rookie');
    assert.equal(normal.json().career.rank.paperLimit, '10000');
    assert.equal(normal.json().career.streak.status, 'active');
    const recoveredDay = await dayContext(normalGuestToken);
    assert.equal(recoveredDay.statusCode, 200, recoveredDay.body);
    assert.equal(recoveredDay.json().dayContext.revision, 2);
    assert.equal(recoveredDay.json().dayContext.timeZone, 'Pacific/Honolulu');
    assert.equal(recoveredDay.json().dayContext.configured, true);

    const replay = await saveReason(normalGuestToken, normalReasonMutation, normalFirstOrderId,
      'The recurring revenue trend is improving.');
    assert.equal(replay.statusCode, 201, replay.body);
    assert.equal(replay.json().reason.trimsAwarded, 10);
    assert.equal(replay.json().reason.dailyAwardNumber, 1);
    assert.equal((await summary(normalGuestToken)).json().career.revision, 6);

    const promoted = await accountSummary(promotionBearer);
    assert.equal(promoted.statusCode, 200, promoted.body);
    assert.equal(promoted.json().career.revision, 32);
    assert.equal(promoted.json().career.trims.total, 420);
    assert.equal(promoted.json().career.rank.id, 'analyst');
    assert.equal(promoted.json().career.rank.paperLimit, '10000');

    const legacy = await summary(legacyGuestToken);
    assert.equal(legacy.statusCode, 200, legacy.body);
    assert.equal(legacy.json().career.revision, 4);
    assert.equal(legacy.json().career.trims.total, 50);

    const backfilled = await careers.getSummary(backfilledUserId);
    assert.equal(backfilled.careerStarted, true);
    assert.equal(backfilled.firstConfirmedBuy?.orderId, backfilledOrderId);
    assert.equal(backfilled.trims.total, 420);
  });
} else describe('Career PostgreSQL integration', () => {
  test('supports account and guest reads while exact route scopes stay isolated', async () => {
    const account = await accounts.provision(accountIdentity);
    const accountResponse = await app.inject({url: CAREER_SUMMARY_ROUTE,
      headers: {authorization: `Bearer ${accountBearer}`}});
    assert.equal(accountResponse.statusCode, 200, accountResponse.body);
    assert.equal(accountResponse.json().career.revision, 0);
    assert.equal(accountResponse.json().career.streak.status, 'not-started');
    assert.equal(accountResponse.json().career.careerStarted, false);
    assert.equal(accountResponse.json().career.firstConfirmedBuy, null);
    assert.equal(accountResponse.json().career.serverDate,
      new Date().toISOString().slice(0, 10));

    const accountDay = await app.inject({url: CAREER_DAY_CONTEXT_ROUTE,
      headers: {authorization: `Bearer ${accountBearer}`}});
    assert.equal(accountDay.statusCode, 200, accountDay.body);
    assert.deepEqual(accountDay.json(), {
      schemaVersion: 1,
      dayContext: {
        revision: 1,
        timeZone: 'UTC',
        configured: false,
        serverDate: accountResponse.json().career.serverDate,
        nextDayAt: accountDay.json().dayContext.nextDayAt,
        createdAt: accountDay.json().dayContext.createdAt,
        updatedAt: accountDay.json().dayContext.updatedAt,
      },
    });
    assert.equal(accountDay.json().dayContext.updatedAt, accountDay.json().dayContext.createdAt);
    assert.match(accountDay.json().dayContext.nextDayAt,
      /^\d{4}-\d{2}-\d{2}T00:00:00\.000Z$/);

    const timezoneClient = await runtimePool.connect();
    try {
      await timezoneClient.query("SET TIME ZONE 'Pacific/Honolulu'");
      const utcSummary = await timezoneClient.query<{server_date: string}>(
        'SELECT server_date::text FROM trimmy.career_summary_get($1::uuid)', [account.userId]);
      assert.equal(utcSummary.rows[0]?.server_date, new Date().toISOString().slice(0, 10));
    } finally {
      await timezoneClient.query('RESET TIME ZONE').catch(() => {});
      timezoneClient.release();
    }

    const wrongRoute = await app.inject({url: '/v1/config', headers: guestHeaders(normalGuestToken)});
    assert.equal(wrongRoute.statusCode, 200);
    assert.equal((await careers.getSummary(account.userId)).revision, 0);

    const emptyMissions = await careers.getMissions(account.userId);
    assert.deepEqual(emptyMissions.missions.map(mission => mission.status),
      ['ready', 'locked', 'locked']);
    const backfilled = await careers.getSummary(backfilledUserId);
    assert.equal(backfilled.revision, 4);
    assert.equal(backfilled.trims.total, 50);
    assert.equal(backfilled.careerStarted, true);
    assert.deepEqual(backfilled.firstConfirmedBuy, {
      orderId: backfilledOrderId,
      assetId: 'backfill-stock',
      variantMint: mint,
      symbol: 'BACKx',
      quantityMicros: '5000',
      confirmedAt: '2026-09-17T12:00:01.000Z',
    });
    await assert.rejects(owner.query(`UPDATE trimmy.career_first_confirmed_buys
      SET confirmed_at=confirmed_at+interval '1 millisecond' WHERE user_id=$1`, [backfilledUserId]),
    {code: '23514'});
    await assert.rejects(owner.query(
      'DELETE FROM trimmy.career_starts WHERE user_id=$1', [backfilledUserId]), {code: '23514'});
    assert.deepEqual((await careers.getMissions(backfilledUserId)).missions.map(mission => mission.status),
      ['complete', 'complete', 'locked']);
  });

  test('owns a validated IANA timezone with exact retries, concurrency and DST midnight', async () => {
    const zoneToken = `tg1_${'Z'.repeat(43)}`;
    await createGuest('92000000-0000-4000-8000-000000000041', zoneToken,
      '92000000-0000-4000-8000-000000000042', 41, 'careerzone');

    const initial = await dayContext(zoneToken);
    assert.equal(initial.statusCode, 200, initial.body);
    assert.equal(initial.json().dayContext.revision, 1);
    assert.equal(initial.json().dayContext.timeZone, 'UTC');
    assert.equal(initial.json().dayContext.configured, false);

    const mutationId = randomUUID();
    const saved = await saveDayContext(zoneToken, mutationId, 1, 'Pacific/Honolulu');
    assert.equal(saved.statusCode, 200, saved.body);
    assert.equal(saved.json().dayContext.revision, 2);
    assert.equal(saved.json().dayContext.timeZone, 'Pacific/Honolulu');
    assert.equal(saved.json().dayContext.configured, true);
    assert.ok(Date.parse(saved.json().dayContext.nextDayAt) >
      Date.parse(saved.json().dayContext.updatedAt));

    const replay = await saveDayContext(zoneToken, mutationId, 1, 'Pacific/Honolulu');
    assert.equal(replay.statusCode, 200, replay.body);
    assert.deepEqual(replay.json(), saved.json());

    const rebound = await saveDayContext(zoneToken, mutationId, 1, 'Africa/Lagos');
    assert.equal(rebound.statusCode, 409, rebound.body);
    assert.equal(rebound.json().error.code, 'CAREER_IDEMPOTENCY_CONFLICT');

    const stale = await saveDayContext(zoneToken, randomUUID(), 1, 'Pacific/Honolulu');
    assert.equal(stale.statusCode, 409, stale.body);
    assert.equal(stale.json().error.code, 'CAREER_DAY_CONTEXT_REVISION_CONFLICT');

    const sameZone = await saveDayContext(zoneToken, randomUUID(), 2, 'Pacific/Honolulu');
    assert.equal(sameZone.statusCode, 200, sameZone.body);
    assert.equal(sameZone.json().dayContext.revision, 2);
    assert.equal(sameZone.json().dayContext.updatedAt, saved.json().dayContext.updatedAt);

    const tooSoon = await saveDayContext(zoneToken, randomUUID(), 2, 'Asia/Tokyo');
    assert.equal(tooSoon.statusCode, 409, tooSoon.body);
    assert.equal(tooSoon.json().error.code, 'CAREER_TIME_ZONE_CHANGE_TOO_SOON');

    const offset = await saveDayContext(zoneToken, randomUUID(), 2, '+01:00');
    assert.equal(offset.statusCode, 400, offset.body);
    assert.equal(offset.json().error.code, 'CAREER_INVALID_INPUT');

    const unknown = await saveDayContext(zoneToken, randomUUID(), 2, 'America/Not_A_Zone');
    assert.equal(unknown.statusCode, 400, unknown.body);
    assert.equal(unknown.json().error.code, 'CAREER_INVALID_INPUT');

    const daylightSaving = await owner.query<{
      new_york_spring: Date;
      new_york_fall: Date;
      havana_spring: Date;
      havana_fall: Date;
      azores_fall: Date;
      apia_skip: Date;
    }>(`
      SELECT trimmy.career_next_day_at('America/New_York',
          '2026-03-08T05:30:00Z'::timestamptz) AS new_york_spring,
        trimmy.career_next_day_at('America/New_York',
          '2026-11-01T04:30:00Z'::timestamptz) AS new_york_fall,
        trimmy.career_next_day_at('America/Havana',
          '2026-03-07T12:00:00Z'::timestamptz) AS havana_spring,
        trimmy.career_next_day_at('America/Havana',
          '2026-10-31T12:00:00Z'::timestamptz) AS havana_fall,
        trimmy.career_next_day_at('Atlantic/Azores',
          '2026-10-24T12:00:00Z'::timestamptz) AS azores_fall,
        trimmy.career_next_day_at('Pacific/Apia',
          '2011-12-29T12:00:00Z'::timestamptz) AS apia_skip`);
    assert.equal(daylightSaving.rows[0]?.new_york_spring.toISOString(),
      '2026-03-09T04:00:00.000Z');
    assert.equal(daylightSaving.rows[0]?.new_york_fall.toISOString(),
      '2026-11-02T05:00:00.000Z');
    assert.equal(daylightSaving.rows[0]?.havana_spring.toISOString(),
      '2026-03-08T05:00:00.000Z');
    assert.equal(daylightSaving.rows[0]?.havana_fall.toISOString(),
      '2026-11-01T04:00:00.000Z');
    assert.equal(daylightSaving.rows[0]?.azores_fall.toISOString(),
      '2026-10-25T00:00:00.000Z');
    assert.equal(daylightSaving.rows[0]?.apia_skip.toISOString(),
      '2011-12-30T10:00:00.000Z');

    const concurrentToken = `tg1_${'Y'.repeat(43)}`;
    await createGuest('92000000-0000-4000-8000-000000000043', concurrentToken,
      '92000000-0000-4000-8000-000000000044', 42, 'careerzone2');
    const concurrent = await Promise.all([
      saveDayContext(concurrentToken, randomUUID(), 1, 'Africa/Lagos'),
      saveDayContext(concurrentToken, randomUUID(), 1, 'Asia/Tokyo'),
    ]);
    assert.deepEqual(concurrent.map(response => response.statusCode).sort(), [200, 409]);
    const rejected = concurrent.find(response => response.statusCode === 409);
    assert.equal(rejected?.json().error.code, 'CAREER_DAY_CONTEXT_REVISION_CONFLICT');
  });

  test('caps a local calendar day and keeps the rolling guard across a timezone change', async () => {
    const capToken = `tg1_${'R'.repeat(43)}`;
    const capUser = await createGuest('92000000-0000-4000-8000-000000000051', capToken,
      '92000000-0000-4000-8000-000000000052', 51, 'careercap');
    const zones = (await owner.query<{initial_zone: string; alternate_zone: string}>(`
      SELECT CASE
          WHEN (clock_timestamp() AT TIME ZONE 'UTC')::time >= time '10:00'
            THEN 'Pacific/Kiritimati' ELSE 'Etc/GMT+12'
        END AS initial_zone,
        CASE
          WHEN (clock_timestamp() AT TIME ZONE 'UTC')::time >= time '10:00'
            THEN 'Etc/GMT+12' ELSE 'Pacific/Kiritimati'
        END AS alternate_zone`)).rows[0];
    assert.ok(zones);

    const initialMutation = randomUUID();
    const initialZone = await saveDayContext(capToken, initialMutation, 1, zones.initial_zone);
    assert.equal(initialZone.statusCode, 200, initialZone.body);
    assert.equal(initialZone.json().dayContext.revision, 2);

    let firstAward: {savedAt: string} | undefined;
    for (let index = 1; index <= 4; index++) {
      const order = await commitOrder(capUser, 'buy', `edge-cap-stock-${index}`,
        {kind: 'paper_amount', paperMicros: '1000000'});
      const response = await saveReason(capToken, randomUUID(), order.id,
        `Edge reason ${index} uses evidence from the company's durable cash generation.`);
      assert.equal(response.statusCode, 201, response.body);
      assert.equal(response.json().reason.trimsAwarded, index <= 3 ? 10 : 0);
      assert.equal(response.json().reason.dailyAwardNumber, index <= 3 ? index : null);
      if (index === 1) firstAward = response.json().reason;
    }
    assert.ok(firstAward);
    const beforeTravel = (await summary(capToken)).json().career;
    assert.notEqual(firstAward.savedAt.slice(0, 10), beforeTravel.serverDate,
      'fixture must straddle a UTC/local calendar boundary');

    const fixture = await owner.connect();
    try {
      await fixture.query('BEGIN');
      await fixture.query("SET LOCAL session_replication_role = 'replica'");
      const aged = await fixture.query(`UPDATE trimmy.career_day_settings
        SET created_at=created_at-interval '25 hours',
          updated_at=updated_at-interval '25 hours'
        WHERE user_id=$1`, [capUser]);
      assert.equal(aged.rowCount, 1);
      await fixture.query('COMMIT');
    } catch (error) {
      await fixture.query('ROLLBACK').catch(() => {});
      throw error;
    } finally { fixture.release(); }

    const changed = await saveDayContext(capToken, randomUUID(), 2, zones.alternate_zone);
    assert.equal(changed.statusCode, 200, changed.body);
    assert.equal(changed.json().dayContext.revision, 3);
    assert.equal(changed.json().dayContext.timeZone, zones.alternate_zone);
    assert.notEqual(changed.json().dayContext.serverDate, beforeTravel.serverDate);

    const oldReplay = await saveDayContext(capToken, initialMutation, 1, zones.initial_zone);
    assert.equal(oldReplay.statusCode, 200, oldReplay.body);
    assert.deepEqual(oldReplay.json(), initialZone.json());

    const afterTravelOrder = await commitOrder(capUser, 'buy', 'edge-cap-after-travel',
      {kind: 'paper_amount', paperMicros: '1000000'});
    const afterTravel = await saveReason(capToken, randomUUID(), afterTravelOrder.id,
      'The new local date does not erase the rolling reward limit.');
    assert.equal(afterTravel.statusCode, 201, afterTravel.body);
    assert.equal(afterTravel.json().reason.trimsAwarded, 0);
    assert.equal(afterTravel.json().reason.dailyAwardNumber, null);
  });

  test('activity calendar reads only this principal’s recorded local dates', async () => {
    // Distinct from the profile suite's Q fixture in the shared test database.
    const calendarToken = `tg1_${createHash('sha256').update('career-calendar-fixture').digest('base64url')}`;
    const calendarUser = await createGuest('92000000-0000-4000-8000-000000000071', calendarToken,
      '92000000-0000-4000-8000-000000000072', 71, 'calendar');
    await commitOrder(calendarUser, 'buy', 'calendar-stock', {kind: 'paper_amount', paperMicros: '1000000'});
    const response = await app.inject({url: CAREER_ACTIVITY_WEEK_ROUTE,
      headers: guestHeaders(calendarToken)});
    assert.equal(response.statusCode, 200, response.body);
    const week = response.json().activityWeek;
    assert.ok(week.activeDates.length > 0);
    const auth = await guests.authorize(hashGuestCredential(calendarToken), 'career_read');
    const expected = await owner.query(`SELECT DISTINCT
      (observed_at AT TIME ZONE trimmy.career_time_zone($1))::date::text AS day
      FROM trimmy.career_activity_events WHERE user_id=$1
      AND (observed_at AT TIME ZONE trimmy.career_time_zone($1))::date
        BETWEEN $2::date AND $3::date ORDER BY day`,
      [auth.userId, week.weekStart, week.serverDate]);
    assert.deepEqual(week.activeDates, expected.rows.map(row => row.day));
    assert.equal((await app.inject({url: CAREER_ACTIVITY_WEEK_ROUTE})).statusCode, 401);
  });

  test('recomputes streak status from immutable instants when the timezone changes', async () => {
    const streakToken = `tg1_${'W'.repeat(43)}`;
    const streakUser = await createGuest('92000000-0000-4000-8000-000000000061', streakToken,
      '92000000-0000-4000-8000-000000000062', 61, 'careerstreak');
    await commitOrder(streakUser, 'buy', 'streak-profile-stock',
      {kind: 'paper_amount', paperMicros: '1000000'});
    const fixture = await owner.connect();
    try {
      const storedBefore = (await fixture.query(`SELECT revision::text, streak_days,
        last_active_date::text FROM trimmy.career_profiles WHERE user_id=$1`, [streakUser])).rows[0];
      assert.ok(storedBefore);
      await fixture.query('BEGIN');
      await fixture.query("SET LOCAL session_replication_role = 'replica'");
      await fixture.query(`INSERT INTO trimmy.career_activity_events(
        user_id, activity_kind, source_id, observed_at) VALUES
        ($1,'paper-order',$2,'2040-01-08T00:30:00Z'::timestamptz),
        ($1,'paper-order',$3,'2040-01-10T00:30:00Z'::timestamptz)`,
      [streakUser, randomUUID(), randomUUID()]);

      const readStreak = async (timeZone: string, today: string) =>
        (await fixture.query(`SELECT streak_days, streak_status,
          last_active_date::text AS last_active_date
          FROM trimmy.career_streak_get($1,$2,$3::date)`,
        [streakUser, timeZone, today])).rows[0];
      assert.deepEqual(await readStreak('UTC', '2040-01-10'), {
        streak_days: 2, streak_status: 'active', last_active_date: '2040-01-10',
      });
      assert.deepEqual(await readStreak('America/Los_Angeles', '2040-01-10'), {
        streak_days: 2, streak_status: 'at-risk', last_active_date: '2040-01-09',
      });
      assert.deepEqual(await readStreak('UTC', '2040-01-11'), {
        streak_days: 2, streak_status: 'at-risk', last_active_date: '2040-01-10',
      });
      assert.deepEqual(await readStreak('UTC', '2040-01-12'), {
        streak_days: 2, streak_status: 'grace', last_active_date: '2040-01-10',
      });
      assert.deepEqual(await readStreak('UTC', '2040-01-13'), {
        streak_days: 0, streak_status: 'not-started', last_active_date: null,
      });
      const storedAfter = (await fixture.query(`SELECT revision::text, streak_days,
        last_active_date::text FROM trimmy.career_profiles WHERE user_id=$1`, [streakUser])).rows[0];
      assert.deepEqual(storedAfter, storedBefore);
      await fixture.query('ROLLBACK');
    } catch (error) {
      await fixture.query('ROLLBACK').catch(() => {});
      throw error;
    } finally { fixture.release(); }
  });

  test('preserves initial and existing-profile deferred invariants and caps reason awards', async () => {
    const legacyUser = await createGuest(legacyGuestId, legacyGuestToken,
      '92000000-0000-4000-8000-000000000031', 21, 'careerlegacy');
    await commitOrder(legacyUser, 'buy', 'legacy-stock',
      {kind: 'paper_amount', paperMicros: '1000000'}, legacyOrderId);
    const legacyTrade = (await summary(legacyGuestToken)).json().career;
    assert.equal(legacyTrade.revision, 2);
    assert.equal(legacyTrade.trims.total, 20);
    const legacyReason = await saveReason(legacyGuestToken, legacyReasonMutation, legacyOrderId,
      'The customer base is growing without a matching cost spike.');
    assert.equal(legacyReason.statusCode, 201, legacyReason.body);
    assert.equal(legacyReason.json().reason.trimsAwarded, 10);
    assert.equal((await summary(legacyGuestToken)).json().career.revision, 4);
    assert.equal((await summary(legacyGuestToken)).json().career.trims.total, 50);

    const normalUser = await createGuest(normalGuestId, normalGuestToken,
      '92000000-0000-4000-8000-000000000032', 22, 'careernormal');
    assert.equal((await summary(normalGuestToken)).json().career.revision, 0);
    const localDay = await saveDayContext(
      normalGuestToken, normalDayMutation, 1, 'Pacific/Honolulu');
    assert.equal(localDay.statusCode, 200, localDay.body);
    assert.equal(localDay.json().dayContext.revision, 2);
    await commitOrder(normalUser, 'buy', 'stock-one',
      {kind: 'paper_amount', paperMicros: '1000000'}, normalFirstOrderId);
    const afterTrade = (await summary(normalGuestToken)).json().career;
    assert.equal(afterTrade.revision, 2);
    assert.equal(afterTrade.trims.total, 20);
    assert.equal(afterTrade.streak.days, 1);
    assert.equal(afterTrade.streak.status, 'active');
    assert.equal(afterTrade.careerStarted, true);
    assert.deepEqual(afterTrade.firstConfirmedBuy, {
      orderId: normalFirstOrderId,
      assetId: 'stock-one',
      variantMint: mint,
      symbol: 'STOCx',
      quantityMicros: '5000',
      confirmedAt: afterTrade.firstConfirmedBuy.confirmedAt,
    });
    assert.deepEqual((await missionBoard(normalGuestToken)).json().missions.map(
      (mission: {status: string}) => mission.status), ['complete', 'ready', 'locked']);

    const first = await saveReason(normalGuestToken, normalReasonMutation, normalFirstOrderId,
      'The recurring revenue trend is improving.');
    assert.equal(first.statusCode, 201, first.body);
    assert.equal(first.json().reason.trimsAwarded, 10);
    assert.equal(first.json().reason.dailyAwardNumber, 1);
    assert.deepEqual((await missionBoard(normalGuestToken)).json().missions.map(
      (mission: {status: string}) => mission.status), ['complete', 'complete', 'locked']);
    const firstReplay = await saveReason(normalGuestToken, normalReasonMutation, normalFirstOrderId,
      'The recurring revenue trend is improving.');
    assert.deepEqual(firstReplay.json(), first.json());
    const conflict = await saveReason(normalGuestToken, normalReasonMutation, normalFirstOrderId,
      'A different note cannot reuse the same mutation.');
    assert.equal(conflict.statusCode, 409, conflict.body);
    assert.equal(conflict.json().error.code, 'CAREER_IDEMPOTENCY_CONFLICT');

    for (let index = 2; index <= 4; index++) {
      const order = await commitOrder(normalUser, 'buy', `stock-${index}`,
        {kind: 'paper_amount', paperMicros: '1000000'});
      const response = await saveReason(normalGuestToken, randomUUID(), order.id,
        `Reason ${index} is based on the company's improving cash generation.`);
      assert.equal(response.statusCode, 201, response.body);
      assert.equal(response.json().reason.trimsAwarded, index <= 3 ? 10 : 0);
      assert.equal(response.json().reason.dailyAwardNumber, index <= 3 ? index : null);
    }
    const final = (await summary(normalGuestToken)).json().career;
    assert.equal(final.revision, 6);
    assert.deepEqual(final.trims, {total: 70, today: 70, thisWeek: 70});
    assert.equal(final.streak.days, 1);
    const currentDay = await dayContext(normalGuestToken);
    assert.equal(currentDay.statusCode, 200, currentDay.body);
    assert.equal(final.serverDate, currentDay.json().dayContext.serverDate);

    const sold = await commitOrder(normalUser, 'sell', 'stock-one',
      {kind: 'share_quantity', quantityMicros: '5000'});
    const sellReason = await saveReason(normalGuestToken, randomUUID(), sold.id,
      'A sell cannot earn reason Trims.');
    assert.equal(sellReason.statusCode, 409, sellReason.body);
    assert.equal(sellReason.json().error.code, 'CAREER_BUY_ORDER_REQUIRED');
    const closedBuy = await saveReason(normalGuestToken, randomUUID(), normalFirstOrderId,
      'A closed position cannot receive a first reason twice.');
    assert.equal(closedBuy.statusCode, 409, closedBuy.body);
    // Existing reason takes precedence for this order; a distinct closed buy
    // below proves the position requirement itself.
    const closingBuy = await commitOrder(normalUser, 'buy', 'closed-stock',
      {kind: 'paper_amount', paperMicros: '1000000'});
    await commitOrder(normalUser, 'sell', 'closed-stock',
      {kind: 'share_quantity', quantityMicros: '5000'});
    const noPosition = await saveReason(normalGuestToken, randomUUID(), closingBuy.id,
      'This position is already closed.');
    assert.equal(noPosition.statusCode, 409, noPosition.body);
    assert.equal(noPosition.json().error.code, 'CAREER_POSITION_REQUIRED');
    assert.equal((await summary(normalGuestToken)).json().career.revision, 6);
  });

  test('requires server evidence and threshold, promotes once, and leaves paper funding unchanged', async () => {
    const promotionUser = backfilledUserId;
    await owner.query(`INSERT INTO trimmy.practice_auth_identities(provider, app_id, subject, user_id)
      VALUES ('privy',$1,$2,$3)`,
    [promotionIdentity.appId, promotionIdentity.subject, promotionUser]);
    const earlyMutation = randomUUID();
    const tooEarly = await promoteAccount(promotionBearer, earlyMutation, 'analyst');
    assert.equal(tooEarly.statusCode, 409, tooEarly.body);
    assert.equal(tooEarly.json().error.code, 'CAREER_PROMOTION_THRESHOLD_REQUIRED');

    for (let index = 1; index <= 25; index++) {
      const order = await commitOrder(promotionUser, 'buy', `promotion-stock-${index}`,
        {kind: 'paper_amount', paperMicros: '1000000'});
      await appendOwnerReasonAward(promotionUser, order, index);
    }
    const thresholdResponse = await accountSummary(promotionBearer);
    assert.equal(thresholdResponse.statusCode, 200, thresholdResponse.body);
    const atThreshold = thresholdResponse.json().career;
    assert.equal(atThreshold.revision, 30);
    assert.equal(atThreshold.trims.total, 300);
    assert.equal(atThreshold.nextRank.promotionRequired, true);

    const missionMissing = await promoteAccount(promotionBearer, randomUUID(), 'analyst');
    assert.equal(missionMissing.statusCode, 409, missionMissing.body);
    assert.equal(missionMissing.json().error.code, 'CAREER_PROMOTION_MISSION_REQUIRED');
    assert.equal((await accountMissionBoard(promotionBearer)).json().missions[2].status, 'locked');

    await owner.query(`UPDATE trimmy.career_mission_definitions
      SET evidence_live=true WHERE id='hold-through-red-day'`);
    try {
      const observedAt = Date.now();
      const chartTo = Math.floor(observedAt / 1000);
      const observationId = randomUUID();
      const recorded = await redDays.record({
        observationId,
        session: Object.freeze({
          provider: 'tokens-xyz-v1' as const,
          source: 'clickhouse_stock' as const,
          verifierVersion: 'tokens-canonical-red-day-v1' as const,
          assetId: 'backfill-stock', listedSymbol: 'BACK',
          previousMarketDate: '2026-09-17', marketDate: '2026-09-18',
          previousCloseText: '100', currentCloseText: '90', outcome: 'verified-red' as const,
          providerAsOf: new Date(observedAt - 10_000).toISOString(),
          providerLastFetchedAt: new Date(observedAt - 5_000).toISOString(),
          observedAt: new Date(observedAt).toISOString(),
          audit: Object.freeze({
            detailRequestId: randomUUID(), chartRequestId: randomUUID(),
            detailProviderRequestId: 'career-promotion-detail',
            chartProviderRequestId: 'career-promotion-chart',
            detailPath: '/v1/assets/backfill-stock',
            chartPath: `/v1/assets/backfill-stock/price-chart?interval=1D&from=${chartTo - 35 * 86_400}&to=${chartTo}`,
            detailResponseSha256: 'a'.repeat(64), chartResponseSha256: 'b'.repeat(64),
          }),
        }),
      });
      assert.equal(recorded.outcome, 'recorded');
      const evidence = await redDays.processSession(observationId, 10);
      assert.deepEqual(evidence, {
        outcome: 'complete', observationId, evidenceCount: 1,
        completedCount: 1, processingComplete: true,
      });
    } finally {
      await owner.query(`UPDATE trimmy.career_mission_definitions
        SET evidence_live=false WHERE id='hold-through-red-day'`);
    }
    const ready = (await accountSummary(promotionBearer)).json().career;
    assert.equal(ready.revision, 31);
    assert.equal(ready.trims.total, 320);
    assert.deepEqual((await accountMissionBoard(promotionBearer)).json().missions.map(
      (mission: {status: string}) => mission.status), ['complete', 'complete', 'complete']);
    const paperBeforePromotion = (await owner.query<{
      starting_cash_micros: string; cash_micros: string; revision: string;
    }>(`SELECT starting_cash_micros::text, cash_micros::text, revision::text
        FROM trimmy.paper_accounts WHERE user_id=$1`, [promotionUser])).rows[0];
    assert.ok(paperBeforePromotion);

    const mutationId = randomUUID();
    const [promoted, concurrentReplay] = await Promise.all([
      promoteAccount(promotionBearer, mutationId, 'analyst'),
      promoteAccount(promotionBearer, mutationId, 'analyst'),
    ]);
    assert.equal(promoted.statusCode, 201, promoted.body);
    assert.equal(concurrentReplay.statusCode, 201, concurrentReplay.body);
    assert.deepEqual(promoted.json().promotion, {
      mutationId,
      fromRank: 'rookie',
      toRank: 'analyst',
      careerRevision: 32,
      trimsAwarded: 100,
      promotedAt: promoted.json().promotion.promotedAt,
    });
    assert.deepEqual(concurrentReplay.json(), promoted.json());
    const replay = await promoteAccount(promotionBearer, mutationId, 'analyst');
    assert.deepEqual(replay.json(), promoted.json());
    const rebound = await promoteAccount(promotionBearer, mutationId, 'trader');
    assert.equal(rebound.statusCode, 409, rebound.body);
    assert.equal(rebound.json().error.code, 'CAREER_IDEMPOTENCY_CONFLICT');

    const after = (await accountSummary(promotionBearer)).json().career;
    assert.equal(after.revision, 32);
    assert.equal(after.trims.total, 420);
    assert.equal(after.rank.id, 'analyst');
    assert.equal(after.rank.paperLimit, '10000');
    assert.equal(after.nextRank.id, 'trader');
    assert.equal(after.nextRank.trimsRemaining, 480);
    const paperAfterPromotion = (await owner.query<{
      starting_cash_micros: string; cash_micros: string; revision: string;
    }>(`SELECT starting_cash_micros::text, cash_micros::text, revision::text
        FROM trimmy.paper_accounts WHERE user_id=$1`, [promotionUser])).rows[0];
    assert.deepEqual(paperAfterPromotion, paperBeforePromotion);
    assert.equal(paperAfterPromotion?.starting_cash_micros, '10000000000');
  });

  test('keeps runtime access function-only and rejects privileged repositories', async () => {
    for (const table of ['career_profiles', 'career_trim_ledger', 'career_trade_reasons',
      'career_reason_mutation_receipts', 'career_starts', 'career_first_confirmed_buys',
      'career_mission_definitions', 'career_mission_completions', 'career_promotion_receipts',
      'career_day_settings', 'career_day_setting_receipts', 'career_activity_events']) {
      await assert.rejects(runtimePool.query(`SELECT * FROM trimmy.${table}`), {code: '42501'});
    }
    await assert.rejects(new PostgresCareerRepository(owner).getSummary(
      '92000000-0000-4000-8000-000000000099'),
    error => error instanceof CareerRepositoryError && error.code === 'CAREER_RUNTIME_ROLE_INVALID');
  });

  test('deferred guards reject unmatched reason, mission, promotion and total history', async () => {
    const normalUser = (await owner.query('SELECT user_id FROM trimmy.guest_sessions WHERE id=$1',
      [normalGuestId])).rows[0].user_id as string;
    const unmatched = await owner.connect();
    try {
      await unmatched.query('BEGIN');
      await unmatched.query(`INSERT INTO trimmy.career_reason_mutation_receipts(
        user_id, mutation_id, request_hash, order_id, asset_id, variant_mint, note,
        trims_awarded, daily_award_number, saved_at)
        VALUES ($1,$2,repeat('c',64),$3,'stock-one',$4,'Unmatched receipt',0,NULL,clock_timestamp())`,
      [normalUser, randomUUID(), normalFirstOrderId, mint]);
      await assert.rejects(unmatched.query('COMMIT'),
        (error: unknown) => typeof error === 'object' && error !== null &&
          (error as {constraint?: unknown}).constraint === 'career_reason_receipt_pair');
    } finally {
      await unmatched.query('ROLLBACK').catch(() => {});
      unmatched.release();
    }

    const unmatchedDayReceipt = await owner.connect();
    try {
      await unmatchedDayReceipt.query('BEGIN');
      await unmatchedDayReceipt.query(`INSERT INTO trimmy.career_day_setting_receipts(
        user_id, mutation_id, request_hash, revision, time_zone, configured,
        server_date, next_day_at, created_at, updated_at)
        SELECT s.user_id, $2, repeat('e',64), s.revision, 'Asia/Tokyo', true,
          (clock_timestamp() AT TIME ZONE 'Asia/Tokyo')::date,
          trimmy.career_next_day_at('Asia/Tokyo', clock_timestamp()),
          s.created_at, s.updated_at
        FROM trimmy.career_day_settings s WHERE s.user_id=$1`,
      [normalUser, randomUUID()]);
      await assert.rejects(unmatchedDayReceipt.query('COMMIT'),
        (error: unknown) => typeof error === 'object' && error !== null &&
          (error as {constraint?: unknown}).constraint === 'career_day_setting_receipt_pair');
    } finally {
      await unmatchedDayReceipt.query('ROLLBACK').catch(() => {});
      unmatchedDayReceipt.release();
    }

    const unmatchedActivity = await owner.connect();
    try {
      await unmatchedActivity.query('BEGIN');
      await unmatchedActivity.query(`INSERT INTO trimmy.career_activity_events(
        user_id, activity_kind, source_id, observed_at)
        VALUES ($1,'paper-order',$2,clock_timestamp())`, [normalUser, randomUUID()]);
      await assert.rejects(unmatchedActivity.query('COMMIT'),
        (error: unknown) => typeof error === 'object' && error !== null &&
          (error as {constraint?: unknown}).constraint === 'career_activity_source_pair');
    } finally {
      await unmatchedActivity.query('ROLLBACK').catch(() => {});
      unmatchedActivity.release();
    }

    const unbalanced = await owner.connect();
    try {
      await unbalanced.query('BEGIN');
      await unbalanced.query(`UPDATE trimmy.career_profiles SET revision=revision+1,
        trims_total=trims_total+10, updated_at=updated_at+interval '1 millisecond' WHERE user_id=$1`,
      [normalUser]);
      await assert.rejects(unbalanced.query('COMMIT'),
        (error: unknown) => typeof error === 'object' && error !== null &&
          (error as {constraint?: unknown}).constraint === 'career_trim_total');
    } finally {
      await unbalanced.query('ROLLBACK').catch(() => {});
      unbalanced.release();
    }

    const unmatchedMission = await owner.connect();
    try {
      await unmatchedMission.query('BEGIN');
      const progress = (await unmatchedMission.query<{revision: string; updated_at: Date}>(
        `SELECT revision::text, updated_at FROM trimmy.career_profiles
         WHERE user_id=$1 FOR UPDATE`, [normalUser])).rows[0];
      assert.ok(progress);
      const nextRevision = Number(progress.revision) + 1;
      const observedAt = new Date(progress.updated_at.getTime() + 1);
      await unmatchedMission.query(`UPDATE trimmy.career_profiles SET revision=$2,
        trims_total=trims_total+20, updated_at=$3 WHERE user_id=$1`,
      [normalUser, nextRevision, observedAt]);
      await unmatchedMission.query(`INSERT INTO trimmy.career_trim_ledger(
        user_id, career_revision, entry_kind, source_id, trims, awarded_on, created_at)
        VALUES ($1,$2,'mission',$3,20,($4::timestamptz AT TIME ZONE 'UTC')::date,$4)`,
      [normalUser, nextRevision, randomUUID(), observedAt]);
      await assert.rejects(unmatchedMission.query('COMMIT'),
        (error: unknown) => typeof error === 'object' && error !== null &&
          (error as {constraint?: unknown}).constraint === 'career_mission_ledger_pair');
    } finally {
      await unmatchedMission.query('ROLLBACK').catch(() => {});
      unmatchedMission.release();
    }

    const unmatchedPromotion = await owner.connect();
    try {
      await unmatchedPromotion.query('BEGIN');
      const progress = (await unmatchedPromotion.query<{revision: string; updated_at: Date}>(
        `SELECT revision::text, updated_at FROM trimmy.career_profiles
         WHERE user_id=$1 FOR UPDATE`, [normalUser])).rows[0];
      assert.ok(progress);
      const nextRevision = Number(progress.revision) + 1;
      const observedAt = new Date(progress.updated_at.getTime() + 1);
      await unmatchedPromotion.query(`UPDATE trimmy.career_profiles SET revision=$2,
        trims_total=trims_total+100, rank_id='analyst', updated_at=$3 WHERE user_id=$1`,
      [normalUser, nextRevision, observedAt]);
      await unmatchedPromotion.query(`INSERT INTO trimmy.career_trim_ledger(
        user_id, career_revision, entry_kind, source_id, trims, awarded_on, created_at)
        VALUES ($1,$2,'promotion',$3,100,($4::timestamptz AT TIME ZONE 'UTC')::date,$4)`,
      [normalUser, nextRevision, randomUUID(), observedAt]);
      await assert.rejects(unmatchedPromotion.query('COMMIT'),
        (error: unknown) => typeof error === 'object' && error !== null &&
          new Set(['career_profile_promotion_pair', 'career_promotion_ledger_pair'])
            .has(String((error as {constraint?: unknown}).constraint)));
    } finally {
      await unmatchedPromotion.query('ROLLBACK').catch(() => {});
      unmatchedPromotion.release();
    }
    assert.equal((await careers.getSummary(normalUser)).trims.total, 70);
  });
});
