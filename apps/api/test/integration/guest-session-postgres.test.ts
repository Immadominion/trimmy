import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import { after, before, describe, test } from 'node:test';
import { Pool } from 'pg';
import { buildApp } from '../../src/app.js';
import {
  createGuestPaperAuthenticator, deriveGuestCreation, hashGuestCreationRequest, hashGuestCredential,
  hashGuestReplaySecret,
} from '../../src/guest-session-routes.js';
import { GuestSessionError } from '../../src/guest-session-repository.js';
import type {GuestCreationSource} from '../../src/guest-creation-source.js';
import { PostgresGuestSessionRepository } from '../../src/postgres-guest-session-repository.js';
import { PostgresPaperTradingRepository } from '../../src/postgres-paper-trading-repository.js';
import { PostgresPracticeAccounts } from '../../src/postgres-practice-accounts.js';
import type { PaperPriceReader } from '../../src/paper-price-reader.js';
import type { PracticeIdentity, PracticeIdentityVerifier } from '../../src/practice-identity.js';
import { PAPER_COMMIT_ROUTE, PAPER_PREVIEW_ROUTE } from '../../src/paper-trading-routes.js';

const socket = process.env['TRIMMY_PRACTICE_TEST_SOCKET'];
assert.ok(socket?.endsWith('/infra/.practice-runtime/socket'),
  'Use the private test runner; never attach to an external database.');
assert.equal(process.env['TRIMMY_PRACTICE_TEST_PORT'], '65438');
const connection = {host: socket, port: 65438, database: 'postgres', connectionTimeoutMillis: 3000};
const guestPool = new Pool({...connection, user: 'trimmy_practice_test_app', max: 5});
const guestReplicaPool = new Pool({...connection, user: 'trimmy_practice_test_app', max: 3});
const paperPool = new Pool({...connection, user: 'trimmy_paper_test_app', max: 5});
const owner = new Pool({...connection, user: 'trimmy_test_owner', max: 2});
const guests = new PostgresGuestSessionRepository(guestPool);
const guestReplica = new PostgresGuestSessionRepository(guestReplicaPool);
const accounts = new PostgresPracticeAccounts(guestPool);
const paper = new PostgresPaperTradingRepository(paperPool);

const creationRequestId = '74000000-0000-4000-8000-000000000001';
const replaySecret = `gr1_${Buffer.alloc(32, 2).toString('base64url')}`;
const creation = deriveGuestCreation(creationRequestId, replaySecret);
const guestId = creation.guestId;
const previewId = '74000000-0000-4000-8000-000000000002';
const orderId = '74000000-0000-4000-8000-000000000003';
const requestId = '74000000-0000-4000-8000-000000000004';
const commitId = '74000000-0000-4000-8000-000000000005';
const claimId = '74000000-0000-4000-8000-000000000006';
const guestToken = creation.credential;
const bearer = 'eyJhbGciOiJFUzI1NiJ9.eyJzdWIiOiJkaWQ6cHJpdnk6Z3Vlc3QifQ.c2lnbmF0dXJl'; // gitleaks:allow -- synthetic JWT fixture with deliberately invalid signature
const identity: PracticeIdentity = {provider: 'privy', appId: 'guest-postgres-test', subject: 'did:privy:guestpostgres'};
const mint = 'XsP7xzNPvEHS1m6qfanPUGjNmdMVPckE3hER9uE7p6H';
const verifier: PracticeIdentityVerifier = {verify: async token => token === bearer ? identity : null};
const prices: PaperPriceReader = {read: async ({assetId, variantMint}) => {
  const acceptedAt = new Date().toISOString();
  return {assetId, variantMint, symbol: 'AAPLx', pricePaperMicros: '200000000',
    source: {provider: 'tokens-xyz-v1', providerReference: `/v1/assets/${assetId}/variants#guest-test`,
      marketSource: 'integration-fixture', metricsSource: null,
      providerTimestamps: {asOf: null, lastFetchedAt: null, lastTradeAt: null, unit: 'not_declared'},
      observedAt: acceptedAt, acceptedAt}, expiresAt: new Date(Date.now() + 30_000).toISOString()};
}};
let idIndex = 0;
const paperIds = [previewId, orderId];
const accountAuth = async () => null;
const sourceHash = (label: string) => createHash('sha256').update(`guest-source:${label}`).digest('hex');
const creationHeaders = (label: string) => ({'x-test-source': label});
const source: GuestCreationSource = {hash: request => {
  const value = request.headers?.['x-test-source'];
  return sourceHash(typeof value === 'string' ? value : 'default');
}};
const app = buildApp({logger: false,
  guestSessions: {repository: guests, verifier, source},
  paperTrading: {repository: paper, prices, authenticate: createGuestPaperAuthenticator(accountAuth, guests),
    newId: () => paperIds[idIndex++]!}});
const replicaApp = buildApp({logger: false,
  guestSessions: {repository: guestReplica, verifier, source},
});

before(async () => { await app.ready(); await replicaApp.ready(); });
after(async () => {
  await app.close(); await replicaApp.close(); await guestPool.end(); await guestReplicaPool.end();
  await paperPool.end(); await owner.end();
});

async function createStoredGuest(command: {
  requestHash: string; replayHash: string; guestId: string; credentialHash: string;
}, label: string): Promise<void> {
  const admission = await guests.takeCreationAttempt(sourceHash(label));
  await guests.create({...command, ...admission});
}

async function exactRetryAfter(label: string, offset: number, windowMilliseconds: number): Promise<number> {
  const rows = (await owner.query<{attempted_at: Date}>(
    `SELECT attempted_at FROM trimmy.guest_creation_attempts
     WHERE source_hash=$1 ORDER BY attempted_at DESC, id DESC`, [sourceHash(label)])).rows;
  const latest = rows[0]?.attempted_at;
  const boundary = rows[offset]?.attempted_at;
  assert.ok(latest && boundary);
  return Math.max(1, Math.ceil((boundary.getTime() + windowMilliseconds - latest.getTime()) / 1000));
}

if (process.env['TRIMMY_PRACTICE_TEST_RECOVERY'] === '1') {
  test('a new process recovers the claimed identity and original paper order', async () => {
    const creationReplay = await app.inject({method: 'POST', url: '/v1/guest/session',
      headers: creationHeaders('recovery'),
      payload: {schemaVersion: 1, requestId: creationRequestId, replaySecret}});
    assert.equal(creationReplay.statusCode, 201, creationReplay.body);
    assert.equal(creationReplay.json().requestId, creationRequestId);
    assert.equal(creationReplay.json().guestId, guestId);
    assert.equal(creationReplay.json().token, guestToken);
    const mapped = await accounts.find(identity);
    const guest = await owner.query('SELECT user_id, state FROM trimmy.guest_sessions WHERE id=$1', [guestId]);
    assert.equal(guest.rows[0].state, 'claimed');
    assert.equal(mapped?.userId, guest.rows[0].user_id);
    assert.equal((await owner.query('SELECT count(*)::int AS count FROM trimmy.paper_orders WHERE user_id=$1 AND id=$2',
      [mapped!.userId, orderId])).rows[0].count, 1);
    assert.deepEqual(await guests.claim({credentialHash: hashGuestCredential(guestToken), identity,
      idempotencyKey: claimId}), {guestId, claimedAt: (await owner.query(
        'SELECT claimed_at FROM trimmy.guest_sessions WHERE id=$1', [guestId])).rows[0].claimed_at.toISOString()});
    await assert.rejects(guests.authorize(hashGuestCredential(guestToken), 'paper_read'),
      error => error instanceof GuestSessionError && error.code === 'GUEST_SESSION_REVOKED');
  });
} else describe('guest session PostgreSQL integration', () => {
  test('creates a hash-only guest account and completes the first server-confirmed paper trade', async () => {
    const usersBefore = Number((await owner.query('SELECT count(*) AS count FROM trimmy.users')).rows[0].count);
    const payload = {schemaVersion: 1, requestId: creationRequestId, replaySecret};
    const headers = creationHeaders('primary');
    const opened = await app.inject({method: 'POST', url: '/v1/guest/session', headers, payload});
    assert.equal(opened.statusCode, 201, opened.body);
    assert.equal(opened.json().token, guestToken);
    assert.equal(opened.json().requestId, creationRequestId);
    const retried = await app.inject({method: 'POST', url: '/v1/guest/session', headers, payload});
    assert.equal(retried.statusCode, 201, retried.body);
    assert.deepEqual(retried.json(), opened.json());
    await guests.refresh(hashGuestCredential(guestToken));
    const replayedAfterRefresh = await app.inject({method: 'POST', url: '/v1/guest/session', headers, payload});
    assert.deepEqual(replayedAfterRefresh.json(), opened.json());
    const stored = await owner.query(`SELECT user_id, credential_hash, creation_request_hash, creation_replay_hash
      FROM trimmy.guest_sessions WHERE id=$1`, [guestId]);
    assert.equal(stored.rows.length, 1);
    assert.equal(stored.rows[0].credential_hash, hashGuestCredential(guestToken));
    assert.equal(stored.rows[0].creation_request_hash, hashGuestCreationRequest(creationRequestId));
    assert.equal(stored.rows[0].creation_replay_hash, hashGuestReplaySecret(replaySecret));
    assert.equal(JSON.stringify(stored.rows).includes(guestToken), false);
    assert.equal(JSON.stringify(stored.rows).includes(replaySecret), false);
    assert.equal(JSON.stringify(stored.rows).includes(creationRequestId), false);
    assert.equal(Number((await owner.query('SELECT count(*) AS count FROM trimmy.users')).rows[0].count), usersBefore + 1);

    const guestHeaders = {authorization: `Guest ${guestToken}`};
    const preview = await app.inject({method: 'POST', url: PAPER_PREVIEW_ROUTE, headers: guestHeaders,
      payload: {schemaVersion: 1, requestId, action: 'buy', assetId: 'apple', variantMint: mint,
        amount: {kind: 'paper_amount', paperMicros: '100000000'}}});
    assert.equal(preview.statusCode, 200, preview.body);
    assert.equal(preview.json().preview.id, previewId);
    const committed = await app.inject({method: 'POST', url: PAPER_COMMIT_ROUTE, headers: guestHeaders,
      payload: {schemaVersion: 1, previewId, idempotencyKey: commitId}});
    assert.equal(committed.statusCode, 200, committed.body);
    assert.equal(committed.json().order.id, orderId);
    assert.equal(committed.json().order.cashAfterPaperMicros, '9900000000');
    assert.equal(committed.json().execution.walletUsed, false);
    assert.equal((await owner.query('SELECT count(*)::int AS count FROM trimmy.wallet_bindings WHERE user_id=$1',
      [stored.rows[0].user_id])).rows[0].count, 0);
  });

  test('concurrent replay creates one row and a wrong replay proof cannot recover its token', async () => {
    const concurrentRequestId = '74500000-0000-4000-8000-000000000001';
    const concurrentSecret = `gr1_${Buffer.alloc(32, 3).toString('base64url')}`;
    const payload = {schemaVersion: 1, requestId: concurrentRequestId, replaySecret: concurrentSecret};
    const usersBefore = Number((await owner.query('SELECT count(*) AS count FROM trimmy.users')).rows[0].count);
    const headers = creationHeaders('concurrent-idempotency');
    const responses = await Promise.all(Array.from({length: 4}, () =>
      app.inject({method: 'POST', url: '/v1/guest/session', headers, payload})));
    for (const response of responses) {
      assert.equal(response.statusCode, 201, response.body);
      assert.deepEqual(response.json(), responses[0]!.json());
    }
    assert.equal(Number((await owner.query('SELECT count(*) AS count FROM trimmy.users')).rows[0].count), usersBefore + 1);
    const rows = await owner.query('SELECT count(*)::int AS count FROM trimmy.guest_sessions WHERE creation_request_hash=$1',
      [hashGuestCreationRequest(concurrentRequestId)]);
    assert.equal(rows.rows[0].count, 1);

    const wrong = await app.inject({method: 'POST', url: '/v1/guest/session', payload: {
      schemaVersion: 1, requestId: concurrentRequestId,
      replaySecret: `gr1_${Buffer.alloc(32, 4).toString('base64url')}`,
    }, headers});
    assert.equal(wrong.statusCode, 503, wrong.body);
    assert.equal(wrong.body.includes(responses[0]!.json().token), false);
    const recovered = await app.inject({method: 'POST', url: '/v1/guest/session', headers, payload});
    assert.deepEqual(recovered.json(), responses[0]!.json());
  });

  test('creation limits are shared across replicas, count invalid bodies and return the exact successful-retry delay', async () => {
    const invalidLabel = 'invalid-body';
    const invalid = await app.inject({method: 'POST', url: '/v1/guest/session',
      headers: creationHeaders(invalidLabel),
      payload: {schemaVersion: 1, requestId: '74600000-0000-4000-8000-000000000001'}});
    assert.equal(invalid.statusCode, 400, invalid.body);
    const invalidAttempt = await owner.query(`SELECT admitted, consumed_at
      FROM trimmy.guest_creation_attempts WHERE source_hash=$1`, [sourceHash(invalidLabel)]);
    assert.deepEqual(invalidAttempt.rows, [{admitted: true, consumed_at: null}]);

    const label = 'shared-replica-limit';
    const payload = {schemaVersion: 1, requestId: '74700000-0000-4000-8000-000000000001',
      replaySecret: `gr1_${Buffer.alloc(32, 14).toString('base64url')}`};
    const allowed = [];
    for (let index = 0; index < 6; index++) {
      const selected = index % 2 === 0 ? app : replicaApp;
      allowed.push(await selected.inject({method: 'POST', url: '/v1/guest/session',
        headers: creationHeaders(label), payload}));
    }
    for (const response of allowed) {
      assert.equal(response.statusCode, 201, response.body);
      assert.deepEqual(response.json(), allowed[0]!.json());
    }
    const seventh = await replicaApp.inject({method: 'POST', url: '/v1/guest/session',
      headers: creationHeaders(label), payload});
    assert.equal(seventh.statusCode, 429, seventh.body);
    assert.equal(Number(seventh.headers['retry-after']), await exactRetryAfter(label, 5, 10 * 60_000));

    // A blocked retry is itself durable. Its advertised delay moves to the
    // next boundary so retrying at the header value can actually be admitted.
    const eighth = await app.inject({method: 'POST', url: '/v1/guest/session',
      headers: creationHeaders(label), payload});
    assert.equal(eighth.statusCode, 429, eighth.body);
    assert.equal(Number(eighth.headers['retry-after']), await exactRetryAfter(label, 5, 10 * 60_000));
    const attempts = await owner.query(`SELECT count(*)::int AS total,
      count(*) FILTER (WHERE admitted)::int AS admitted,
      count(*) FILTER (WHERE consumed_at IS NOT NULL)::int AS consumed
      FROM trimmy.guest_creation_attempts WHERE source_hash=$1`, [sourceHash(label)]);
    assert.deepEqual(attempts.rows[0], {total: 8, admitted: 6, consumed: 6});
  });

  test('a queued replica evaluates the source window after acquiring the database lock', async () => {
    const label = 'queued-source-lock';
    const hash = sourceHash(label);
    const holder = await owner.connect();
    let committed = false;
    try {
      await holder.query('BEGIN');
      await holder.query(`SELECT pg_advisory_xact_lock(
        hashtextextended('trimmy.guest.creation.source:' || $1,0))`, [hash]);
      const pending = guestReplica.takeCreationAttempt(hash).then(
        value => ({value, error: null}), error => ({value: null, error}),
      );
      let waiting = false;
      for (let index = 0; index < 40 && !waiting; index++) {
        const state = await owner.query(`SELECT EXISTS (
          SELECT 1 FROM pg_stat_activity
          WHERE wait_event='advisory' AND query LIKE '%guest_take_creation_attempt%') AS waiting`);
        waiting = state.rows[0].waiting === true;
        if (!waiting) await new Promise(resolve => setTimeout(resolve, 10));
      }
      assert.equal(waiting, true, 'the second repository call did not queue on the source lock');
      await holder.query(`INSERT INTO trimmy.guest_creation_attempts(source_hash,attempted_at,admitted)
        SELECT $1, clock_timestamp(), false FROM generate_series(0,5)`, [hash]);
      await holder.query('COMMIT');
      committed = true;
      const result = await pending;
      assert.equal(result.value, null);
      assert.ok(result.error instanceof GuestSessionError);
      assert.equal(result.error.code, 'GUEST_SESSION_RATE_LIMITED');
      assert.equal(result.error.retryAfterSeconds, await exactRetryAfter(label, 5, 10 * 60_000));
      const stored = await owner.query(`SELECT count(*)::int AS count,
        bool_and(NOT admitted)::boolean AS all_blocked
        FROM trimmy.guest_creation_attempts WHERE source_hash=$1`, [hash]);
      assert.deepEqual(stored.rows[0], {count: 7, all_blocked: true});
    } finally {
      if (!committed) await holder.query('ROLLBACK').catch(() => {});
      holder.release();
    }
  });

  test('the rolling 24-hour boundary rejects attempt 21 and advances after another blocked retry', async () => {
    const label = 'daily-limit';
    const hash = sourceHash(label);
    await owner.query(`INSERT INTO trimmy.guest_creation_attempts(source_hash, attempted_at, admitted)
      SELECT $1, clock_timestamp() - interval '23 hours' + series * interval '1 hour', false
      FROM generate_series(0, 19) AS series`, [hash]);
    const payload = {schemaVersion: 1, requestId: '74800000-0000-4000-8000-000000000001',
      replaySecret: `gr1_${Buffer.alloc(32, 15).toString('base64url')}`};
    const twentyFirst = await app.inject({method: 'POST', url: '/v1/guest/session',
      headers: creationHeaders(label), payload});
    assert.equal(twentyFirst.statusCode, 429, twentyFirst.body);
    const firstDelay = Number(twentyFirst.headers['retry-after']);
    assert.equal(firstDelay, await exactRetryAfter(label, 19, 24 * 60 * 60_000));

    const twentySecond = await replicaApp.inject({method: 'POST', url: '/v1/guest/session',
      headers: creationHeaders(label), payload});
    assert.equal(twentySecond.statusCode, 429, twentySecond.body);
    const secondDelay = Number(twentySecond.headers['retry-after']);
    assert.equal(secondDelay, await exactRetryAfter(label, 19, 24 * 60 * 60_000));
    assert.ok(secondDelay > firstDelay + 3500, `${firstDelay} -> ${secondDelay}`);
  });

  test('claims that exact guest UUID once, retries idempotently, then revokes guest paper access', async () => {
    const headers = {authorization: `Bearer ${bearer}`, 'x-trimmy-guest': guestToken};
    const payload = {schemaVersion: 1, idempotencyKey: claimId};
    const claimed = await app.inject({method: 'POST', url: '/v1/guest/claim', headers, payload});
    assert.equal(claimed.statusCode, 200, claimed.body);
    const retry = await app.inject({method: 'POST', url: '/v1/guest/claim', headers, payload});
    assert.deepEqual(retry.json(), claimed.json());

    const mapped = await accounts.find(identity);
    const guestUser = (await owner.query('SELECT user_id FROM trimmy.guest_sessions WHERE id=$1', [guestId])).rows[0].user_id;
    assert.equal(mapped?.userId, guestUser);
    const denied = await app.inject({method: 'POST', url: PAPER_PREVIEW_ROUTE,
      headers: {authorization: `Guest ${guestToken}`},
      payload: {schemaVersion: 1, requestId: '74000000-0000-4000-8000-000000000007', action: 'buy',
        assetId: 'apple', variantMint: mint, amount: {kind: 'paper_amount', paperMicros: '1000000'}}});
    assert.equal(denied.statusCode, 401);
    assert.equal(denied.json().error.code, 'GUEST_SESSION_REVOKED');
  });

  test('an identity with another saved account cannot consume a guest and failure leaves it usable', async () => {
    const secondId = '75000000-0000-4000-8000-000000000001';
    const secondToken = `tg1_${'C'.repeat(43)}`;
    await createStoredGuest({requestHash: hashGuestCreationRequest('75000000-0000-4000-8000-000000000003'),
      replayHash: hashGuestReplaySecret(`gr1_${Buffer.alloc(32, 5).toString('base64url')}`), guestId: secondId,
      credentialHash: hashGuestCredential(secondToken)}, 'existing-account');
    const existing: PracticeIdentity = {provider: 'privy', appId: 'guest-postgres-test', subject: 'did:privy:existingdesk'};
    const existingAccount = await accounts.provision(existing);
    await assert.rejects(guests.claim({credentialHash: hashGuestCredential(secondToken), identity: existing,
      idempotencyKey: '75000000-0000-4000-8000-000000000002'}),
    error => error instanceof GuestSessionError && error.code === 'GUEST_CLAIM_ACCOUNT_EXISTS');
    const stillGuest = await guests.authorize(hashGuestCredential(secondToken), 'paper_read');
    assert.notEqual(stillGuest.userId, existingAccount.userId);
    const row = await owner.query('SELECT state, revoked_at FROM trimmy.guest_sessions WHERE id=$1', [secondId]);
    assert.deepEqual(row.rows[0], {state: 'active', revoked_at: null});
  });

  test('guest preview rate is enforced in PostgreSQL across repository calls', async () => {
    const rateId = '76000000-0000-4000-8000-000000000001';
    const rateToken = `tg1_${'D'.repeat(43)}`;
    const hash = hashGuestCredential(rateToken);
    await createStoredGuest({requestHash: hashGuestCreationRequest('76000000-0000-4000-8000-000000000003'),
      replayHash: hashGuestReplaySecret(`gr1_${Buffer.alloc(32, 6).toString('base64url')}`),
      guestId: rateId, credentialHash: hash}, 'preview-rate');
    for (let index = 0; index < 20; index++) {
      assert.equal((await guests.authorize(hash, 'paper_preview')).guestId, rateId);
    }
    await assert.rejects(guests.authorize(hash, 'paper_preview'),
      error => error instanceof GuestSessionError && error.code === 'GUEST_SESSION_RATE_LIMITED');
    const count = await owner.query(`SELECT request_count FROM trimmy.guest_rate_windows
      WHERE guest_session_id=$1 AND scope='paper_preview'`, [rateId]);
    assert.equal(count.rows[0].request_count, 21);
  });

  test('owner-only retention is locked, bounded, idempotent and preserves paper and Career history', async () => {
    const userIds = ['78100000-0000-4000-8000-000000000001', '78100000-0000-4000-8000-000000000002'];
    const sessionIds = ['78000000-0000-4000-8000-000000000001', '78000000-0000-4000-8000-000000000002'];
    const earlyUserId = '78100000-0000-4000-8000-000000000003';
    const earlySessionId = '78000000-0000-4000-8000-000000000003';
    for (let index = 0; index < 2; index++) {
      await owner.query('INSERT INTO trimmy.users(id) VALUES ($1)', [userIds[index]]);
      await owner.query(`INSERT INTO trimmy.guest_sessions(
        id,user_id,credential_hash,creation_request_hash,creation_replay_hash,
        state,created_at,expires_at,hard_expires_at,last_seen_at)
        SELECT $1,$2,$3,$4,$5,'active',observed_at-interval '100 days',
          observed_at-interval '70 days',observed_at-interval '10 days',
          observed_at-interval '100 days' FROM (SELECT clock_timestamp() AS observed_at) observed`,
      [sessionIds[index], userIds[index], String(index + 7).repeat(64),
        String(index + 5).repeat(64), String(index + 3).repeat(64)]);
      await owner.query(`INSERT INTO trimmy.guest_rate_windows(
        guest_session_id,scope,window_started_at,request_count)
        VALUES ($1,'paper_read',clock_timestamp()-interval '3 days'-$2*interval '1 minute',1)`,
      [sessionIds[index], index]);
    }
    await owner.query('INSERT INTO trimmy.users(id) VALUES ($1)', [earlyUserId]);
    await owner.query(`INSERT INTO trimmy.guest_sessions(
      id,user_id,credential_hash,creation_request_hash,creation_replay_hash,
      state,created_at,expires_at,hard_expires_at,last_seen_at)
      SELECT $1,$2,repeat('a',64),repeat('b',64),repeat('c',64),'active',
        observed_at,observed_at+interval '30 days',observed_at+interval '90 days',observed_at
      FROM (SELECT clock_timestamp() AS observed_at) observed`, [earlySessionId, earlyUserId]);
    await owner.query(`WITH observed AS (SELECT clock_timestamp() AS at), opened AS (
      INSERT INTO trimmy.paper_accounts(user_id,opened_at,updated_at)
      SELECT $1,at,at FROM observed RETURNING user_id,opened_at
    ) INSERT INTO trimmy.paper_cash_ledger(
      user_id,account_revision,order_id,entry_kind,delta_micros,balance_after_micros,created_at)
      SELECT user_id,0,NULL,'initial',10000000000,10000000000,opened_at FROM opened`, [userIds[0]]);
    await owner.query(`INSERT INTO trimmy.career_profiles(
      user_id,revision,trims_total,rank_id,streak_days,last_active_date,created_at,updated_at)
      SELECT $1,1,0,'rookie',1,current_date,observed_at,observed_at
      FROM (SELECT clock_timestamp() AS observed_at) observed`, [userIds[0]]);
    const oldSource = sourceHash('retention-old');
    const freshSource = sourceHash('retention-fresh');
    await owner.query(`INSERT INTO trimmy.guest_creation_attempts(source_hash,attempted_at,admitted)
      VALUES ($1,clock_timestamp()-interval '26 hours',false),
             ($1,clock_timestamp()-interval '25 hours',false),
             ($2,clock_timestamp(),false)`, [oldSource, freshSource]);

    const bypassClient = await owner.connect();
    try {
      await bypassClient.query('BEGIN');
      await bypassClient.query("SELECT set_config('trimmy.guest_retention','on',true)");
      await bypassClient.query('SAVEPOINT fresh_attempt');
      await assert.rejects(bypassClient.query(`DELETE FROM trimmy.guest_creation_attempts
        WHERE source_hash=$1`, [freshSource]), {code: '23514'});
      await bypassClient.query('ROLLBACK TO SAVEPOINT fresh_attempt');
      await bypassClient.query('SAVEPOINT early_session');
      await assert.rejects(bypassClient.query(`UPDATE trimmy.guest_sessions SET
        credential_hash=NULL,creation_request_hash=NULL,creation_replay_hash=NULL,
        auth_redacted_at=hard_expires_at+interval '7 days',state='revoked',
        revoked_at=hard_expires_at WHERE id=$1`, [earlySessionId]), {code: '23514'});
      await bypassClient.query('ROLLBACK TO SAVEPOINT early_session');
      await bypassClient.query('SAVEPOINT future_redaction');
      await assert.rejects(bypassClient.query(`UPDATE trimmy.guest_sessions SET
        credential_hash=NULL,creation_request_hash=NULL,creation_replay_hash=NULL,
        auth_redacted_at=clock_timestamp()+interval '1 day',state='revoked',
        revoked_at=hard_expires_at WHERE id=$1`, [sessionIds[0]]), {code: '23514'});
      await bypassClient.query('ROLLBACK TO SAVEPOINT future_redaction');
      await assert.rejects(bypassClient.query(`UPDATE trimmy.guest_sessions SET
        credential_hash=NULL,creation_request_hash=NULL,creation_replay_hash=NULL,
        auth_redacted_at=hard_expires_at+interval '7 days',state='revoked',
        revoked_at=hard_expires_at,expires_at=expires_at+interval '1 second'
        WHERE id=$1`, [sessionIds[0]]), {code: '23514'});
    } finally {
      await bypassClient.query('ROLLBACK').catch(() => {});
      bypassClient.release();
    }

    const lockClient = await owner.connect();
    try {
      await lockClient.query('BEGIN');
      await lockClient.query(`SELECT pg_advisory_xact_lock(
        hashtextextended('trimmy.guest.auth.retention.v1',0))`);
      const skipped = await owner.query('SELECT * FROM trimmy.guest_auth_retention(1)');
      assert.deepEqual(skipped.rows[0], {lock_acquired: false, source_attempts_deleted: 0,
        rate_windows_deleted: 0, sessions_redacted: 0, has_more: true});
    } finally {
      await lockClient.query('ROLLBACK').catch(() => {});
      lockClient.release();
    }

    const first = (await owner.query('SELECT * FROM trimmy.guest_auth_retention(1)')).rows[0];
    assert.deepEqual(first, {lock_acquired: true, source_attempts_deleted: 1,
      rate_windows_deleted: 1, sessions_redacted: 1, has_more: true});
    const second = (await owner.query('SELECT * FROM trimmy.guest_auth_retention(1)')).rows[0];
    assert.deepEqual(second, {lock_acquired: true, source_attempts_deleted: 1,
      rate_windows_deleted: 1, sessions_redacted: 1, has_more: false});
    const third = (await owner.query('SELECT * FROM trimmy.guest_auth_retention(1)')).rows[0];
    assert.deepEqual(third, {lock_acquired: true, source_attempts_deleted: 0,
      rate_windows_deleted: 0, sessions_redacted: 0, has_more: false});

    const retained = await owner.query(`SELECT
      (SELECT count(*)::int FROM trimmy.guest_creation_attempts WHERE source_hash=$1) AS fresh_attempts,
      (SELECT count(*)::int FROM trimmy.guest_creation_attempts WHERE source_hash=$2) AS old_attempts,
      (SELECT count(*)::int FROM trimmy.guest_rate_windows WHERE guest_session_id=ANY($3::uuid[])) AS old_rates`,
    [freshSource, oldSource, sessionIds]);
    assert.deepEqual(retained.rows[0], {fresh_attempts: 1, old_attempts: 0, old_rates: 0});
    const early = await owner.query(`SELECT credential_hash,creation_request_hash,
      creation_replay_hash,auth_redacted_at,state FROM trimmy.guest_sessions WHERE id=$1`, [earlySessionId]);
    assert.deepEqual(early.rows[0], {credential_hash: 'a'.repeat(64), creation_request_hash: 'b'.repeat(64),
      creation_replay_hash: 'c'.repeat(64), auth_redacted_at: null, state: 'active'});

    const sessions = await owner.query(`SELECT id,credential_hash,creation_request_hash,
      creation_replay_hash,auth_redacted_at IS NOT NULL AS redacted,state,
      revoked_at=hard_expires_at AS revoked_at_hard_expiry
      FROM trimmy.guest_sessions WHERE id=ANY($1::uuid[]) ORDER BY id`, [sessionIds]);
    assert.equal(sessions.rows.length, 2);
    for (const row of sessions.rows) {
      assert.equal(row.credential_hash, null);
      assert.equal(row.creation_request_hash, null);
      assert.equal(row.creation_replay_hash, null);
      assert.equal(row.redacted, true);
      assert.equal(row.state, 'revoked');
      assert.equal(row.revoked_at_hard_expiry, true);
    }
    assert.equal((await owner.query('SELECT count(*)::int AS count FROM trimmy.users WHERE id=ANY($1::uuid[])',
      [userIds])).rows[0].count, 2);
    assert.equal((await owner.query('SELECT count(*)::int AS count FROM trimmy.paper_accounts WHERE user_id=$1',
      [userIds[0]])).rows[0].count, 1);
    assert.equal((await owner.query('SELECT count(*)::int AS count FROM trimmy.paper_cash_ledger WHERE user_id=$1',
      [userIds[0]])).rows[0].count, 1);
    assert.equal((await owner.query('SELECT count(*)::int AS count FROM trimmy.career_profiles WHERE user_id=$1',
      [userIds[0]])).rows[0].count, 1);
    const retentionIndexes = await owner.query(`SELECT indexname,indexdef FROM pg_indexes
      WHERE schemaname='trimmy' AND indexname IN ('guest_rate_windows_retention','guest_sessions_auth_retention')
      ORDER BY indexname`);
    assert.equal(retentionIndexes.rows.length, 2);
    assert.match(retentionIndexes.rows[0].indexdef, /window_started_at, guest_session_id, scope/);
    assert.match(retentionIndexes.rows[1].indexdef, /hard_expires_at, id.*auth_redacted_at IS NULL/);
    await assert.rejects(owner.query(`UPDATE trimmy.guest_sessions SET credential_hash=repeat('f',64)
      WHERE id=$1`, [sessionIds[0]]), {code: '23514'});
  });

  test('runtime has function-only guest access and unsafe roles are rejected', async () => {
    for (const table of ['guest_sessions', 'guest_rate_windows', 'guest_creation_attempts', 'users',
      'practice_auth_identities']) {
      await assert.rejects(guestPool.query(`SELECT * FROM trimmy.${table}`), {code: '42501'});
    }
    await assert.rejects(guestPool.query('SELECT * FROM trimmy.guest_auth_retention(1)'), {code: '42501'});
    const privileged = new Pool({...connection, user: 'trimmy_test_owner', max: 1});
    try {
      await assert.rejects(new PostgresGuestSessionRepository(privileged).takeCreationAttempt(sourceHash('unsafe')),
        error => error instanceof GuestSessionError && error.code === 'GUEST_SESSION_RUNTIME_ROLE_INVALID');
    } finally { await privileged.end(); }
  });
});
