import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { after, before, describe, test } from 'node:test';
import { Pool } from 'pg';
import { buildApp } from '../../src/app.js';
import {
  hashGuestCreationRequest, hashGuestCredential, hashGuestReplaySecret,
} from '../../src/guest-session-routes.js';
import { PostgresGuestSessionRepository } from '../../src/postgres-guest-session-repository.js';
import { PostgresPaperTradingRepository } from '../../src/postgres-paper-trading-repository.js';
import { PostgresPracticeAccounts } from '../../src/postgres-practice-accounts.js';
import { PostgresProductProfileRepository } from '../../src/postgres-product-profile-repository.js';
import {
  createProductProfileAuthenticator, PRODUCT_LAUNCH_ROUTE, PRODUCT_PROFILE_ROUTE,
} from '../../src/product-profile-routes.js';
import type { AcceptedPaperPrice } from '../../src/paper-price-reader.js';
import type { PracticeIdentity, PracticeIdentityVerifier } from '../../src/practice-identity.js';
import { requestPracticeBearerToken } from '../../src/practice-session-routes.js';
import { ProductProfileRepositoryError } from '../../src/product-profile-repository.js';

const socket = process.env['TRIMMY_PRACTICE_TEST_SOCKET'];
assert.ok(socket?.endsWith('/infra/.practice-runtime/socket'),
  'Use the private test runner; never attach to an external database.');
assert.equal(process.env['TRIMMY_PRACTICE_TEST_PORT'], '65438');
const connection = {host: socket, port: 65438, database: 'postgres', connectionTimeoutMillis: 3000};
const profilePool = new Pool({...connection, user: 'trimmy_practice_test_app', max: 5});
const paperPool = new Pool({...connection, user: 'trimmy_paper_test_app', max: 3});
const owner = new Pool({...connection, user: 'trimmy_test_owner', max: 2});
const guests = new PostgresGuestSessionRepository(profilePool);
const accounts = new PostgresPracticeAccounts(profilePool);
const profiles = new PostgresProductProfileRepository(profilePool);
const paper = new PostgresPaperTradingRepository(paperPool);

const guestId = '82000000-0000-4000-8000-000000000001';
const guestToken = `tg1_${'P'.repeat(43)}`;
const bearer = 'eyJhbGciOiJFUzI1NiJ9.eyJzdWIiOiJkaWQ6cHJpdnk6cHJvZmlsZSJ9.c2lnbmF0dXJl'; // gitleaks:allow -- synthetic JWT fixture with deliberately invalid signature
const identity: PracticeIdentity = {
  provider: 'privy', appId: 'profile-postgres-test', subject: 'did:privy:profilepostgres',
};
const mutationIds = {
  initial: '82000000-0000-4000-8000-000000000011',
  position: '82000000-0000-4000-8000-000000000012',
  streak: '82000000-0000-4000-8000-000000000013',
  save: '82000000-0000-4000-8000-000000000014',
  stale: '82000000-0000-4000-8000-000000000015',
  other: '82000000-0000-4000-8000-000000000016',
  appA: '82000000-0000-4000-8000-000000000017',
  appB: '82000000-0000-4000-8000-000000000018',
  accountLater: '82000000-0000-4000-8000-000000000019',
  unpairedSnapshot: '82000000-0000-4000-8000-000000000020',
} as const;
const onboarding = Object.freeze({goal: 'practice' as const, knowledge: 'basics' as const,
  persona: 'oracle' as const, dailyGoal: 'one-mission' as const, handle: 'profilepilot'});
const payload = (mutationId: string, baseRevision: number, launchCheckpoint: string,
  selectedOnboarding: object = onboarding) =>
  ({schemaVersion: 1, mutationId, baseRevision, onboarding: selectedOnboarding, launchCheckpoint});
const launchPayload = (mutationId: string, baseRevision: number, action: string) =>
  ({schemaVersion: 1, mutationId, baseRevision, action});

const verifier: PracticeIdentityVerifier = {verify: async token => token === bearer ? identity : null};
const httpSource = {hash: () => createHash('sha256').update('product-profile-http-source').digest('hex')};
const accountAuth = async (request: Parameters<ReturnType<typeof createProductProfileAuthenticator>>[0]) => {
  if (requestPracticeBearerToken(request) !== bearer) return null;
  const account = await accounts.find(identity);
  return account ? {userId: account.userId} : null;
};
const app = buildApp({logger: false,
  guestSessions: {repository: guests, verifier, source: httpSource},
  productProfile: {repository: profiles, authenticate: createProductProfileAuthenticator(accountAuth, guests)},
});

before(async () => { await app.ready(); });
after(async () => { await app.close(); await profilePool.end(); await paperPool.end(); await owner.end(); });

function acceptedPrice(): AcceptedPaperPrice {
  const acceptedAt = new Date().toISOString();
  return Object.freeze({
    assetId: 'apple', variantMint: 'XsP7xzNPvEHS1m6qfanPUGjNmdMVPckE3hER9uE7p6H', symbol: 'AAPLx',
    pricePaperMicros: '200000000',
    source: Object.freeze({provider: 'tokens-xyz-v1',
      providerReference: '/v1/assets/apple/variants#product-profile-test',
      marketSource: 'integration-fixture', metricsSource: null,
      providerTimestamps: Object.freeze({asOf: null, lastFetchedAt: null, lastTradeAt: null,
        unit: 'not_declared'}), observedAt: acceptedAt, acceptedAt}),
    expiresAt: new Date(Date.now() + 30_000).toISOString(),
  });
}

async function createGuestSession(command: {
  requestHash: string; replayHash: string; guestId: string; credentialHash: string;
}): Promise<void> {
  const sourceHash = createHash('sha256').update(`product-profile:${command.guestId}`).digest('hex');
  const admission = await guests.takeCreationAttempt(sourceHash);
  await guests.create({...command, ...admission});
}

if (process.env['TRIMMY_PRACTICE_TEST_RECOVERY'] === '1') {
  test('a new process restores the claimed profile and stable mutation receipt', async () => {
    const mapped = await accounts.find(identity);
    assert.ok(mapped);
    const response = await app.inject({url: PRODUCT_PROFILE_ROUTE,
      headers: {authorization: `Bearer ${bearer}`}});
    assert.equal(response.statusCode, 200, response.body);
    assert.equal(response.json().profile.revision, 5);
    assert.equal(response.json().profile.launchCheckpoint, 'app');
    assert.equal(response.json().profile.onboarding.handle, onboarding.handle);

    const retry = await app.inject({method: 'POST', url: PRODUCT_LAUNCH_ROUTE,
      headers: {authorization: `Bearer ${bearer}`},
      payload: launchPayload(mutationIds.position, 1, 'paper-trade-confirmed')});
    assert.equal(retry.statusCode, 200, retry.body);
    assert.equal(retry.json().profile.revision, 2);
    assert.equal(retry.json().profile.launchCheckpoint, 'first-position');

    const guestDenied = await app.inject({url: PRODUCT_PROFILE_ROUTE,
      headers: {authorization: `Guest ${guestToken}`}});
    assert.equal(guestDenied.statusCode, 401);
    assert.equal(guestDenied.json().error.code, 'GUEST_SESSION_REVOKED');
    assert.equal((await owner.query('SELECT count(*)::int AS count FROM trimmy.product_profiles WHERE user_id=$1',
      [mapped.userId])).rows[0].count, 1);
  });
} else describe('product profile PostgreSQL integration', () => {
  test('preserves ordered guest onboarding and launch state through a one-time account claim', async () => {
    await createGuestSession({requestHash: hashGuestCreationRequest('82000000-0000-4000-8000-000000000003'),
      replayHash: hashGuestReplaySecret(`gr1_${Buffer.alloc(32, 11).toString('base64url')}`), guestId,
      credentialHash: hashGuestCredential(guestToken)});
    const guestHeaders = {authorization: `Guest ${guestToken}`};
    const empty = await app.inject({url: PRODUCT_PROFILE_ROUTE, headers: guestHeaders});
    assert.deepEqual(empty.json(), {schemaVersion: 1, profile: null});

    const initial = await app.inject({method: 'PUT', url: PRODUCT_PROFILE_ROUTE, headers: guestHeaders,
      payload: payload(mutationIds.initial, 0, 'first-trade')});
    assert.equal(initial.statusCode, 200, initial.body);
    assert.equal(initial.json().profile.revision, 1);

    const genericAdvance = await app.inject({method: 'PUT', url: PRODUCT_PROFILE_ROUTE, headers: guestHeaders,
      payload: payload(mutationIds.position, 1, 'first-position')});
    assert.equal(genericAdvance.statusCode, 409, genericAdvance.body);
    assert.equal(genericAdvance.json().error.code, 'PRODUCT_PROFILE_CHECKPOINT_CONFLICT');
    const noTrade = await app.inject({method: 'POST', url: PRODUCT_LAUNCH_ROUTE, headers: guestHeaders,
      payload: launchPayload(mutationIds.position, 1, 'paper-trade-confirmed')});
    assert.equal(noTrade.statusCode, 409, noTrade.body);
    assert.equal(noTrade.json().error.code, 'PRODUCT_PROFILE_LAUNCH_EVIDENCE_REQUIRED');

    const principal = await guests.authorize(hashGuestCredential(guestToken), 'paper_preview');
    const price = acceptedPrice();
    const preview = await paper.createPreview(principal.userId, {
      id: '82000000-0000-4000-8000-000000000021',
      requestId: '82000000-0000-4000-8000-000000000022', requestHash: 'a'.repeat(64),
      action: 'buy', amount: {kind: 'paper_amount', paperMicros: '100000000'}, price,
    });
    await paper.commit(principal.userId, {
      orderId: '82000000-0000-4000-8000-000000000023', previewId: preview.id,
      idempotencyKey: '82000000-0000-4000-8000-000000000024',
      requestHash: createHash('sha256').update(`{"previewId":"${preview.id}"}`).digest('hex'),
    });

    const position = await app.inject({method: 'POST', url: PRODUCT_LAUNCH_ROUTE, headers: guestHeaders,
      payload: launchPayload(mutationIds.position, 1, 'paper-trade-confirmed')});
    assert.equal(position.statusCode, 200, position.body);
    assert.equal(position.json().profile.revision, 2);

    const stale = await app.inject({method: 'POST', url: PRODUCT_LAUNCH_ROUTE, headers: guestHeaders,
      payload: launchPayload(mutationIds.stale, 1, 'first-position-collected')});
    assert.equal(stale.statusCode, 409, stale.body);
    assert.equal(stale.json().error.code, 'PRODUCT_PROFILE_REVISION_CONFLICT');
    assert.equal(stale.json().error.currentProfile.revision, 2);

    const streak = await app.inject({method: 'POST', url: PRODUCT_LAUNCH_ROUTE, headers: guestHeaders,
      payload: launchPayload(mutationIds.streak, 2, 'first-position-collected')});
    assert.equal(streak.statusCode, 200, streak.body);
    const oldRetry = await app.inject({method: 'POST', url: PRODUCT_LAUNCH_ROUTE, headers: guestHeaders,
      payload: launchPayload(mutationIds.position, 1, 'paper-trade-confirmed')});
    assert.equal(oldRetry.statusCode, 200, oldRetry.body);
    assert.equal(oldRetry.json().profile.revision, 2);

    const rebound = await app.inject({method: 'POST', url: PRODUCT_LAUNCH_ROUTE, headers: guestHeaders,
      payload: launchPayload(mutationIds.position, 2, 'first-position-collected')});
    assert.equal(rebound.statusCode, 409, rebound.body);
    assert.equal(rebound.json().error.code, 'PRODUCT_PROFILE_IDEMPOTENCY_CONFLICT');

    const skipped = await app.inject({method: 'POST', url: PRODUCT_LAUNCH_ROUTE, headers: guestHeaders,
      payload: launchPayload(mutationIds.other, 3, 'save-desk-later')});
    assert.equal(skipped.statusCode, 409, skipped.body);
    assert.equal(skipped.json().error.code, 'PRODUCT_PROFILE_CHECKPOINT_CONFLICT');

    const saved = await app.inject({method: 'POST', url: PRODUCT_LAUNCH_ROUTE, headers: guestHeaders,
      payload: launchPayload(mutationIds.save, 3, 'day-one-seen')});
    assert.equal(saved.statusCode, 200, saved.body);
    assert.equal(saved.json().profile.revision, 4);

    const guestCannotClaimSaved = await app.inject({method: 'POST', url: PRODUCT_LAUNCH_ROUTE,
      headers: guestHeaders, payload: launchPayload(mutationIds.other, 4, 'save-desk-saved')});
    assert.equal(guestCannotClaimSaved.statusCode, 409, guestCannotClaimSaved.body);
    assert.equal(guestCannotClaimSaved.json().error.code, 'PRODUCT_PROFILE_PRINCIPAL_CONFLICT');

    const secondId = '83000000-0000-4000-8000-000000000001';
    const secondToken = `tg1_${'Q'.repeat(43)}`;
    await createGuestSession({requestHash: hashGuestCreationRequest('83000000-0000-4000-8000-000000000003'),
      replayHash: hashGuestReplaySecret(`gr1_${Buffer.alloc(32, 12).toString('base64url')}`), guestId: secondId,
      credentialHash: hashGuestCredential(secondToken)});
    const duplicateHandle = await app.inject({method: 'PUT', url: PRODUCT_PROFILE_ROUTE,
      headers: {authorization: `Guest ${secondToken}`},
      payload: payload('83000000-0000-4000-8000-000000000002', 0, 'first-trade')});
    assert.equal(duplicateHandle.statusCode, 409, duplicateHandle.body);
    assert.equal(duplicateHandle.json().error.code, 'PRODUCT_PROFILE_HANDLE_TAKEN');

    const secondHeaders = {authorization: `Guest ${secondToken}`};
    const secondOnboarding = {...onboarding, handle: 'laterguest'};
    const secondInitial = await app.inject({method: 'PUT', url: PRODUCT_PROFILE_ROUTE,
      headers: secondHeaders,
      payload: payload('83000000-0000-4000-8000-000000000002', 0, 'first-trade', secondOnboarding)});
    assert.equal(secondInitial.statusCode, 200, secondInitial.body);
    const secondPrincipal = await guests.authorize(hashGuestCredential(secondToken), 'paper_preview');
    const secondPreview = await paper.createPreview(secondPrincipal.userId, {
      id: '83000000-0000-4000-8000-000000000011',
      requestId: '83000000-0000-4000-8000-000000000012', requestHash: 'd'.repeat(64),
      action: 'buy', amount: {kind: 'paper_amount', paperMicros: '100000000'}, price: acceptedPrice(),
    });
    await paper.commit(secondPrincipal.userId, {
      orderId: '83000000-0000-4000-8000-000000000013', previewId: secondPreview.id,
      idempotencyKey: '83000000-0000-4000-8000-000000000014',
      requestHash: createHash('sha256').update(`{"previewId":"${secondPreview.id}"}`).digest('hex'),
    });
    const secondActions = [
      ['83000000-0000-4000-8000-000000000021', 1, 'paper-trade-confirmed'],
      ['83000000-0000-4000-8000-000000000022', 2, 'first-position-collected'],
      ['83000000-0000-4000-8000-000000000023', 3, 'day-one-seen'],
    ] as const;
    for (const [mutationId, baseRevision, action] of secondActions) {
      const response = await app.inject({method: 'POST', url: PRODUCT_LAUNCH_ROUTE,
        headers: secondHeaders, payload: launchPayload(mutationId, baseRevision, action)});
      assert.equal(response.statusCode, 200, response.body);
    }
    const secondSavedRejected = await app.inject({method: 'POST', url: PRODUCT_LAUNCH_ROUTE,
      headers: secondHeaders,
      payload: launchPayload('83000000-0000-4000-8000-000000000024', 4, 'save-desk-saved')});
    assert.equal(secondSavedRejected.statusCode, 409, secondSavedRejected.body);
    assert.equal(secondSavedRejected.json().error.code, 'PRODUCT_PROFILE_PRINCIPAL_CONFLICT');
    const secondLater = await app.inject({method: 'POST', url: PRODUCT_LAUNCH_ROUTE,
      headers: secondHeaders,
      payload: launchPayload('83000000-0000-4000-8000-000000000025', 4, 'save-desk-later')});
    assert.equal(secondLater.statusCode, 200, secondLater.body);
    assert.equal(secondLater.json().profile.launchCheckpoint, 'app');

    const claim = await app.inject({method: 'POST', url: '/v1/guest/claim',
      headers: {authorization: `Bearer ${bearer}`, 'x-trimmy-guest': guestToken},
      payload: {schemaVersion: 1, idempotencyKey: '82000000-0000-4000-8000-000000000031'}});
    assert.equal(claim.statusCode, 200, claim.body);
    const mapped = await accounts.find(identity);
    assert.equal(mapped?.userId, principal.userId);

    const restored = await app.inject({url: PRODUCT_PROFILE_ROUTE,
      headers: {authorization: `Bearer ${bearer}`}});
    assert.equal(restored.statusCode, 200, restored.body);
    assert.deepEqual(restored.json().profile, saved.json().profile);

    const accountHeaders = {authorization: `Bearer ${bearer}`};
    const unpaired = await owner.connect();
    try {
      await unpaired.query('BEGIN');
      await unpaired.query(`UPDATE trimmy.product_profiles
        SET revision=revision+1, launch_checkpoint='app', updated_at=updated_at+interval '1 millisecond'
        WHERE user_id=$1`, [principal.userId]);
      await unpaired.query(`INSERT INTO trimmy.product_profile_mutation_receipts(
        user_id, mutation_id, request_hash, revision, goal, knowledge, persona, daily_goal, handle,
        launch_checkpoint, created_at, updated_at)
        SELECT user_id, $2::uuid, repeat('e', 64), revision, goal, knowledge, persona, daily_goal,
          handle, launch_checkpoint, created_at, updated_at
        FROM trimmy.product_profiles WHERE user_id=$1`,
      [principal.userId, mutationIds.unpairedSnapshot]);
      await assert.rejects(unpaired.query('COMMIT'),
        (error: unknown) => typeof error === 'object' && error !== null &&
          (error as {constraint?: unknown}).constraint === 'product_launch_action_pair');
    } finally {
      await unpaired.query('ROLLBACK');
      unpaired.release();
    }

    const accountCannotLater = await app.inject({method: 'POST', url: PRODUCT_LAUNCH_ROUTE,
      headers: accountHeaders,
      payload: launchPayload(mutationIds.accountLater, 4, 'save-desk-later')});
    assert.equal(accountCannotLater.statusCode, 409, accountCannotLater.body);
    assert.equal(accountCannotLater.json().error.code, 'PRODUCT_PROFILE_PRINCIPAL_CONFLICT');
    const competing = await Promise.all([mutationIds.appA, mutationIds.appB].map(mutationId =>
      app.inject({method: 'POST', url: PRODUCT_LAUNCH_ROUTE, headers: accountHeaders,
        payload: launchPayload(mutationId, 4, 'save-desk-saved')})));
    assert.deepEqual(competing.map(response => response.statusCode).sort(), [200, 409]);
    const conflict = competing.find(response => response.statusCode === 409)!;
    assert.equal(conflict.json().error.code, 'PRODUCT_PROFILE_REVISION_CONFLICT');
    assert.equal(conflict.json().error.currentProfile.revision, 5);
    const launched = await app.inject({url: PRODUCT_PROFILE_ROUTE, headers: accountHeaders});
    assert.equal(launched.json().profile.revision, 5);
    assert.equal(launched.json().profile.launchCheckpoint, 'app');

    assert.deepEqual((await owner.query(`SELECT revision::int, action, guest_session_id::text
      FROM trimmy.product_launch_action_receipts WHERE user_id=$1 ORDER BY revision`,
    [principal.userId])).rows, [
      {revision: 2, action: 'paper-trade-confirmed', guest_session_id: guestId},
      {revision: 3, action: 'first-position-collected', guest_session_id: guestId},
      {revision: 4, action: 'day-one-seen', guest_session_id: guestId},
      {revision: 5, action: 'save-desk-saved', guest_session_id: null},
    ]);

    const deniedGuest = await app.inject({url: PRODUCT_PROFILE_ROUTE, headers: guestHeaders});
    assert.equal(deniedGuest.statusCode, 401);
  });

  test('runtime access is function-only and a privileged repository is refused', async () => {
    for (const table of [
      'product_profiles', 'product_profile_mutation_receipts', 'product_launch_action_receipts',
    ]) {
      await assert.rejects(profilePool.query(`SELECT * FROM trimmy.${table}`), {code: '42501'});
    }
    const privileged = new PostgresProductProfileRepository(owner);
    await assert.rejects(privileged.get('82000000-0000-4000-8000-000000000001'),
      error => error instanceof ProductProfileRepositoryError &&
        error.code === 'PRODUCT_PROFILE_RUNTIME_ROLE_INVALID');
  });

  test('uses post-lock guest time and reports the terminal revision boundary exactly', async () => {
    const expiringUser = '85000000-0000-4000-8000-000000000001';
    const expiringGuest = '85000000-0000-4000-8000-000000000002';
    await owner.query('INSERT INTO trimmy.users(id,status) VALUES($1,$2)', [expiringUser, 'active']);
    const expiry = (await owner.query<{expires_at: Date}>(`WITH observed AS (
        SELECT clock_timestamp() AS value
      )
      INSERT INTO trimmy.guest_sessions(
        id,user_id,credential_hash,created_at,expires_at,hard_expires_at,last_seen_at)
      SELECT $1::uuid,$2::uuid,repeat('c',64),value,value+interval '3 seconds',
        value+interval '90 days',value FROM observed
      RETURNING expires_at`, [expiringGuest, expiringUser])).rows[0]!.expires_at;

    const blocker = await owner.connect();
    const runtime = await profilePool.connect();
    let released = false;
    try {
      await blocker.query('BEGIN');
      await blocker.query('SELECT 1 FROM trimmy.users WHERE id=$1 FOR UPDATE', [expiringUser]);
      const pending = runtime.query(`SELECT outcome FROM trimmy.product_launch_advance(
        $1::uuid,$2::uuid,$3::text,$4::bigint,$5::text,$6::uuid)`,
      [expiringUser, '85000000-0000-4000-8000-000000000003', 'c'.repeat(64), 1,
        'paper-trade-confirmed', expiringGuest]);
      let waiting = false;
      for (let attempt = 0; attempt < 100 && !waiting; attempt++) {
        waiting = (await owner.query<{waiting: boolean}>(`SELECT EXISTS (
          SELECT 1 FROM pg_catalog.pg_stat_activity
          WHERE pid <> pg_backend_pid() AND usename='trimmy_practice_test_app'
            AND state='active' AND wait_event_type='Lock'
            AND query LIKE '%product_launch_advance%') AS waiting`)).rows[0]!.waiting;
        if (!waiting) await new Promise(resolve => setTimeout(resolve, 10));
      }
      assert.equal(waiting, true, 'launch call did not queue behind the user lock');
      await new Promise(resolve => setTimeout(resolve,
        Math.max(0, expiry.getTime() - Date.now() + 150)));
      await blocker.query('COMMIT');
      released = true;
      assert.equal((await pending).rows[0].outcome, 'principal_conflict');
    } finally {
      if (!released) await blocker.query('ROLLBACK');
      blocker.release();
      runtime.release();
    }

    const maxUser = '86000000-0000-4000-8000-000000000001';
    const maxMutation = '86000000-0000-4000-8000-000000000002';
    await owner.query('INSERT INTO trimmy.users(id,status) VALUES($1,$2)', [maxUser, 'active']);
    await owner.query(`INSERT INTO trimmy.practice_auth_identities(app_id,subject,user_id)
      VALUES('profile-max-test','did:privy:profilemax',$1)`, [maxUser]);
    const maxSetup = await owner.connect();
    let maxCommitted = false;
    try {
      await maxSetup.query('BEGIN');
      await maxSetup.query('ALTER TABLE trimmy.product_profiles DISABLE TRIGGER product_profile_guard');
      await maxSetup.query(`INSERT INTO trimmy.product_profiles(
        user_id,revision,goal,knowledge,persona,daily_goal,handle,launch_checkpoint,created_at,updated_at)
        VALUES($1,9007199254740991,'practice','basics','oracle','one-mission','maxrevision',
          'first-trade','2026-09-20T10:00:00.000Z','2026-09-20T10:00:00.000Z')`, [maxUser]);
      await maxSetup.query(`INSERT INTO trimmy.product_profile_mutation_receipts(
        user_id,mutation_id,request_hash,revision,goal,knowledge,persona,daily_goal,handle,
        launch_checkpoint,created_at,updated_at)
        VALUES($1,$2,repeat('f',64),9007199254740991,'practice','basics','oracle','one-mission',
          'maxrevision','first-trade','2026-09-20T10:00:00.000Z','2026-09-20T10:00:00.000Z')`,
      [maxUser, maxMutation]);
      await maxSetup.query('COMMIT');
      maxCommitted = true;
    } finally {
      if (!maxCommitted) await maxSetup.query('ROLLBACK');
      await maxSetup.query('ALTER TABLE trimmy.product_profiles ENABLE TRIGGER product_profile_guard');
      maxSetup.release();
    }
    const exhausted = await profilePool.query(`SELECT outcome FROM trimmy.product_launch_advance(
      $1::uuid,$2::uuid,$3::text,$4::bigint,$5::text,NULL::uuid)`,
    [maxUser, '86000000-0000-4000-8000-000000000003', 'f'.repeat(64),
      '9007199254740991', 'paper-trade-confirmed']);
    assert.equal(exhausted.rows[0].outcome, 'revision_exhausted');
  });

  test('database guards reject malformed function calls and unmatched or rewritten history', async () => {
    const userId = (await owner.query('SELECT user_id FROM trimmy.guest_sessions WHERE id=$1', [guestId])).rows[0].user_id;
    const malformed = await profilePool.query(`SELECT outcome FROM trimmy.product_profile_put(
      $1::uuid,$2::uuid,$3::text,$4::bigint,$5::text,$6::text,$7::text,$8::text,$9::text,$10::text)`,
    // Migration 0026 permits omitted introduction fields; use an invalid enum.
    [userId, '82000000-0000-4000-8000-000000000041', 'b'.repeat(64), 5, 'not-a-goal', 'basics', 'oracle',
      'one-mission', 'profilepilot', 'app']);
    assert.equal(malformed.rows[0].outcome, 'invalid');
    const malformedLaunch = await profilePool.query(`SELECT outcome FROM trimmy.product_launch_advance(
      $1::uuid,$2::uuid,$3::text,$4::bigint,$5::text,$6::uuid)`,
    [userId, '82000000-0000-4000-8000-000000000043', 'b'.repeat(64), 5, 'wrong-action', null]);
    assert.equal(malformedLaunch.rows[0].outcome, 'invalid');
    const wrongGuest = await profilePool.query(`SELECT outcome FROM trimmy.product_launch_advance(
      $1::uuid,$2::uuid,$3::text,$4::bigint,$5::text,$6::uuid)`,
    [userId, '82000000-0000-4000-8000-000000000044', 'b'.repeat(64), 5,
      'save-desk-saved', '83000000-0000-4000-8000-000000000001']);
    assert.equal(wrongGuest.rows[0].outcome, 'principal_conflict');
    const guestOnlyUser = (await owner.query(
      `SELECT user_id FROM trimmy.guest_sessions WHERE id='83000000-0000-4000-8000-000000000001'`,
    )).rows[0].user_id;
    const guestAsAccount = await profilePool.query(`SELECT outcome FROM trimmy.product_launch_advance(
      $1::uuid,$2::uuid,$3::text,$4::bigint,$5::text,NULL::uuid)`,
    [guestOnlyUser, '82000000-0000-4000-8000-000000000045', 'b'.repeat(64), 5,
      'save-desk-saved']);
    assert.equal(guestAsAccount.rows[0].outcome, 'principal_conflict');

    await assert.rejects(owner.query(`UPDATE trimmy.product_profile_mutation_receipts
      SET handle='rewritten' WHERE user_id=$1 AND mutation_id=$2`, [userId, mutationIds.initial]),
    (error: unknown) => typeof error === 'object' && error !== null && (error as {code?: unknown}).code === '23514');
    await assert.rejects(owner.query(`UPDATE trimmy.product_launch_action_receipts
      SET action=action WHERE user_id=$1`, [userId]),
    (error: unknown) => typeof error === 'object' && error !== null && (error as {code?: unknown}).code === '23514');

    const snapshotClient = await owner.connect();
    try {
      await snapshotClient.query('BEGIN');
      await snapshotClient.query(`UPDATE trimmy.product_profiles
        SET revision=revision+1, updated_at=updated_at+interval '1 millisecond' WHERE user_id=$1`, [userId]);
      await assert.rejects(snapshotClient.query('COMMIT'),
        (error: unknown) => typeof error === 'object' && error !== null &&
          (error as {constraint?: unknown}).constraint === 'product_profile_receipt_pair');
    } finally {
      await snapshotClient.query('ROLLBACK');
      snapshotClient.release();
    }

    const receiptClient = await owner.connect();
    try {
      await receiptClient.query('BEGIN');
      await receiptClient.query(`INSERT INTO trimmy.product_profile_mutation_receipts(
        user_id, mutation_id, request_hash, revision, goal, knowledge, persona, daily_goal, handle,
        launch_checkpoint, created_at, updated_at)
        SELECT user_id, $2::uuid, repeat('c', 64), revision+1, goal, knowledge, persona, daily_goal,
          handle, launch_checkpoint, created_at, updated_at+interval '1 millisecond'
        FROM trimmy.product_profiles WHERE user_id=$1`,
      [userId, '82000000-0000-4000-8000-000000000042']);
      await assert.rejects(receiptClient.query('COMMIT'),
        (error: unknown) => typeof error === 'object' && error !== null &&
          (error as {constraint?: unknown}).constraint === 'product_profile_receipt_pair');
    } finally {
      await receiptClient.query('ROLLBACK');
      receiptClient.release();
    }

    assert.deepEqual((await owner.query(`SELECT revision::int, launch_checkpoint
      FROM trimmy.product_profiles WHERE user_id=$1`, [userId])).rows[0],
    {revision: 5, launch_checkpoint: 'app'});
  });
});
