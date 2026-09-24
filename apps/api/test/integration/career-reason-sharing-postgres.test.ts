import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {after, before, describe, test} from 'node:test';
import {Pool} from 'pg';
import {CareerReasonSharingError} from '../../src/career-reason-sharing.js';
import {PostgresCareerReasonSharingRepository} from
  '../../src/postgres-career-reason-sharing-repository.js';

const socket = process.env['TRIMMY_REASON_SHARING_TEST_SOCKET'];
assert.ok(socket?.endsWith('/infra/.crs-runtime/socket'),
  'Use the private Career reason sharing runner; never attach to another database.');
assert.equal(process.env['TRIMMY_REASON_SHARING_TEST_PORT'], '65452');
const connection = {
  host: socket, port: 65452, database: 'postgres', connectionTimeoutMillis: 3_000,
};
const owner = new Pool({...connection, user: 'trimmy_reason_share_test_owner', max: 2});
const runtime = new Pool({...connection, user: 'trimmy_reason_share_test_runtime', max: 4});
const repository = new PostgresCareerReasonSharingRepository(runtime);

const backfilledUser = '92400000-0000-4000-8000-000000000001';
const viewer = '92400000-0000-4000-8000-000000000002';
const publicAuthor = '92400000-0000-4000-8000-000000000003';
const friendAuthor = '92400000-0000-4000-8000-000000000004';
const privateAuthor = '92400000-0000-4000-8000-000000000005';
const closedAuthor = '92400000-0000-4000-8000-000000000006';
const firstMint = 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp';
const secondMint = 'So11111111111111111111111111111111111111112';
const base = Date.now() - 3_600_000;
const at = (minutes: number) => new Date(base + minutes * 60_000).toISOString();

const ids: {
  viewerHistorical?: string;
  viewerCurrent?: string;
  publicFirst?: string;
  publicSecond?: string;
  friend?: string;
  private?: string;
  closed?: string;
  closedPrivacyMutation?: string;
} = {};

after(async () => { await Promise.all([owner.end(), runtime.end()]); });

async function createProfile(userId: string, handle: string): Promise<void> {
  const result = await owner.query<{outcome: string}>(`
    SELECT outcome FROM trimmy.product_profile_put(
      $1::uuid,$2::uuid,repeat('a',64),0,
      'practice','basics','wolf','one-mission',$3,'first-trade')`,
  [userId, randomUUID(), handle]);
  assert.equal(result.rows[0]?.outcome, 'saved');
}

async function createUser(userId: string, handle: string): Promise<void> {
  await owner.query('INSERT INTO trimmy.users(id) VALUES ($1::uuid)', [userId]);
  await createProfile(userId, handle);
}

async function buy(userId: string, assetId: string, mint: string, instant: string): Promise<string> {
  const result = await owner.query<{order_id: string}>(`
    SELECT public.paper_reset_test_buy(
      $1::uuid,$2::text,$3::text,$4::timestamptz)::text AS order_id`,
  [userId, assetId, mint, instant]);
  assert.match(result.rows[0]?.order_id ?? '', /^[0-9a-f-]{36}$/u);
  return result.rows[0]!.order_id;
}

async function saveReason(
  userId: string,
  orderId: string,
  instant: string,
): Promise<void> {
  await owner.query(`SELECT public.paper_reset_test_historical_reason(
    $1::uuid,$2::uuid,$3::uuid,$4::timestamptz)`,
  [userId, orderId, randomUUID(), instant]);
}

async function createReason(
  userId: string,
  assetId: string,
  mint: string,
  orderAt: string,
  reasonAt: string,
): Promise<string> {
  const orderId = await buy(userId, assetId, mint, orderAt);
  await saveReason(userId, orderId, reasonAt);
  return orderId;
}

before(async () => {
  if (process.env['TRIMMY_REASON_SHARING_TEST_RECOVERY'] === '1') return;
  await createUser(viewer, 'reason_viewer');
  await createUser(publicAuthor, 'reason_public');
  await createUser(friendAuthor, 'reason_friend');
  await createUser(privateAuthor, 'reason_private');
  await createUser(closedAuthor, 'reason_closed');

  ids.viewerHistorical = await createReason(
    viewer, 'apple', firstMint, at(1), at(2));
  await owner.query(`SELECT public.paper_reset_test_historical_reset(
    $1::uuid,$2::uuid,repeat('b',64),$3::timestamptz)`,
  [viewer, randomUUID(), at(3)]);
  ids.viewerCurrent = await createReason(
    viewer, 'apple', firstMint, at(4), at(5));

  ids.publicFirst = await buy(publicAuthor, 'apple', secondMint, at(6));
  ids.publicSecond = await buy(publicAuthor, 'apple', secondMint, at(7));
  await saveReason(publicAuthor, ids.publicFirst, at(8));
  await saveReason(publicAuthor, ids.publicSecond, at(8));
  ids.friend = await createReason(friendAuthor, 'apple', firstMint, at(9), at(10));
  ids.private = await createReason(privateAuthor, 'apple', firstMint, at(11), at(12));
  ids.closed = await createReason(closedAuthor, 'apple', firstMint, at(13), at(14));

  await repository.savePrivacy(publicAuthor, {
    mutationId: randomUUID(), baseRevision: 1, visibility: 'everyone',
  });
  await repository.savePrivacy(friendAuthor, {
    mutationId: randomUUID(), baseRevision: 1, visibility: 'friends',
  });
  ids.closedPrivacyMutation = randomUUID();
  await repository.savePrivacy(closedAuthor, {
    mutationId: ids.closedPrivacyMutation, baseRevision: 1, visibility: 'everyone',
  });
  await owner.query("UPDATE trimmy.users SET status='closed' WHERE id=$1::uuid", [closedAuthor]);
});

if (process.env['TRIMMY_REASON_SHARING_TEST_RECOVERY'] === '1') {
  test('recovers function-only reads and immutable privacy after owner demotion and restart', async () => {
    const role = await owner.query<{rolsuper: boolean; rolbypassrls: boolean}>(`
      SELECT rolsuper, rolbypassrls FROM pg_catalog.pg_roles
      WHERE rolname='trimmy_reason_share_test_owner'`);
    assert.deepEqual(role.rows, [{rolsuper: false, rolbypassrls: false}]);
    assert.deepEqual(await repository.getPrivacy(publicAuthor), {
      revision: 2, visibility: 'everyone', configured: true,
      friendsSharing: 'unavailable',
      createdAt: (await owner.query(`SELECT created_at FROM trimmy.career_reason_privacy
        WHERE user_id=$1`, [publicAuthor])).rows[0].created_at.toISOString(),
      updatedAt: (await owner.query(`SELECT updated_at FROM trimmy.career_reason_privacy
        WHERE user_id=$1`, [publicAuthor])).rows[0].updated_at.toISOString(),
    });
    const feed = await repository.listReasons(viewer, {
      scope: 'everyone', limit: 20, assetId: 'apple', variantMint: secondMint,
      cursor: null,
    });
    assert.equal(feed.reasons.length, 2);
    assert.deepEqual(new Set(feed.reasons.map(item => item.author.handle)),
      new Set(['reason_public']));
    assert.ok(feed.reasons.every(item => item.deskCycle === 'current'));
    await assert.rejects(runtime.query('SELECT * FROM trimmy.career_reason_privacy'),
      (error: unknown) => (error as {code?: unknown}).code === '42501');
  });
} else describe('Career reason sharing PostgreSQL contract', () => {
  test('backfills old accounts and defaults future accounts to nobody', async () => {
    for (const userId of [backfilledUser, viewer]) {
      assert.deepEqual(await repository.getPrivacy(userId), {
        revision: 1, visibility: 'nobody', configured: false,
        friendsSharing: 'unavailable',
        createdAt: (await owner.query(`SELECT created_at FROM trimmy.career_reason_privacy
          WHERE user_id=$1`, [userId])).rows[0].created_at.toISOString(),
        updatedAt: (await owner.query(`SELECT updated_at FROM trimmy.career_reason_privacy
          WHERE user_id=$1`, [userId])).rows[0].updated_at.toISOString(),
      });
    }
  });

  test('revisions every choice and replays only the current active privacy truth', async () => {
    const firstMutation = randomUUID();
    const first = await repository.savePrivacy(viewer, {
      mutationId: firstMutation, baseRevision: 1, visibility: 'friends',
    });
    assert.equal(first.revision, 2);
    assert.equal(first.visibility, 'friends');
    assert.deepEqual(await repository.savePrivacy(viewer, {
      mutationId: firstMutation, baseRevision: 1, visibility: 'friends',
    }), first);
    await assert.rejects(repository.savePrivacy(viewer, {
      mutationId: firstMutation, baseRevision: 1, visibility: 'everyone',
    }), (error: unknown) => error instanceof CareerReasonSharingError &&
      error.code === 'CAREER_REASON_SHARING_IDEMPOTENCY_CONFLICT');
    await assert.rejects(repository.savePrivacy(viewer, {
      mutationId: randomUUID(), baseRevision: 1, visibility: 'everyone',
    }), (error: unknown) => error instanceof CareerReasonSharingError &&
      error.code === 'CAREER_REASON_PRIVACY_REVISION_CONFLICT');
    const everyone = await repository.savePrivacy(viewer, {
      mutationId: randomUUID(), baseRevision: 2, visibility: 'everyone',
    });
    const sameChoice = await repository.savePrivacy(viewer, {
      mutationId: randomUUID(), baseRevision: 3, visibility: 'everyone',
    });
    assert.equal(everyone.revision, 3);
    assert.equal(sameChoice.revision, 4);
    assert.ok(sameChoice.updatedAt > everyone.updatedAt);
    const oldReplay = await repository.savePrivacy(viewer, {
      mutationId: firstMutation, baseRevision: 1, visibility: 'friends',
    });
    assert.deepEqual(oldReplay, sameChoice);

    await assert.rejects(repository.savePrivacy(closedAuthor, {
      mutationId: ids.closedPrivacyMutation!, baseRevision: 1, visibility: 'everyone',
    }), (error: unknown) => error instanceof CareerReasonSharingError &&
      error.code === 'CAREER_REASON_SHARING_ACCOUNT_NOT_FOUND');
    const retainedReceipt = await owner.query<{
      revision: string; visibility: string;
    }>(`SELECT revision::text, visibility
      FROM trimmy.career_reason_privacy_receipts
      WHERE user_id=$1::uuid AND mutation_id=$2::uuid`,
    [closedAuthor, ids.closedPrivacyMutation]);
    assert.deepEqual(retainedReceipt.rows, [{revision: '2', visibility: 'everyone'}]);
    await assert.rejects(repository.getPrivacy(closedAuthor),
      (error: unknown) => error instanceof CareerReasonSharingError &&
      error.code === 'CAREER_REASON_SHARING_ACCOUNT_NOT_FOUND');
  });

  test('serializes the same privacy mutation into one durable receipt', async () => {
    const mutationId = randomUUID();
    const command = {mutationId, baseRevision: 1, visibility: 'nobody' as const};
    const [first, second] = await Promise.all([
      repository.savePrivacy(privateAuthor, command),
      repository.savePrivacy(privateAuthor, command),
    ]);
    assert.deepEqual(second, first);
    assert.equal(first.revision, 2);
    const receipts = await owner.query<{count: number}>(`
      SELECT count(*)::integer AS count
      FROM trimmy.career_reason_privacy_receipts
      WHERE user_id=$1::uuid AND mutation_id=$2::uuid`,
    [privateAuthor, mutationId]);
    assert.equal(receipts.rows[0]?.count, 1);
  });

  test('linearizes an old replay behind account closure', async () => {
    const raceUser = randomUUID();
    const raceMutation = randomUUID();
    await owner.query('INSERT INTO trimmy.users(id) VALUES ($1::uuid)', [raceUser]);
    await repository.savePrivacy(raceUser, {
      mutationId: raceMutation, baseRevision: 1, visibility: 'everyone',
    });

    const closer = await owner.connect();
    let committed = false;
    try {
      await closer.query('BEGIN');
      await closer.query("SELECT set_config('trimmy.practice_user_id',$1,true)", [raceUser]);
      assert.equal((await closer.query(
        'SELECT trimmy.practice_close_current_account() AS closed')).rows[0]?.closed, true);

      const replay = repository.savePrivacy(raceUser, {
        mutationId: raceMutation, baseRevision: 1, visibility: 'everyone',
      }).then(value => ({value, error: null}), error => ({value: null, error}));
      let waiting = false;
      for (let attempt = 0; attempt < 100 && !waiting; attempt++) {
        waiting = (await owner.query<{waiting: boolean}>(`SELECT EXISTS (
          SELECT 1 FROM pg_catalog.pg_stat_activity
          WHERE pid <> pg_backend_pid()
            AND usename='trimmy_reason_share_test_runtime'
            AND state='active' AND wait_event_type='Lock'
            AND query LIKE '%career_reason_privacy_put%') AS waiting`)).rows[0]!.waiting;
        if (!waiting) await new Promise(resolve => setTimeout(resolve, 10));
      }
      assert.equal(waiting, true, 'privacy replay did not queue behind the closing user row');
      await closer.query('COMMIT');
      committed = true;

      const result = await replay;
      assert.equal(result.value, null);
      assert.ok(result.error instanceof CareerReasonSharingError);
      assert.equal(result.error.code, 'CAREER_REASON_SHARING_ACCOUNT_NOT_FOUND');
    } finally {
      if (!committed) await closer.query('ROLLBACK');
      closer.release();
    }

    const durable = await owner.query<{status: string; receipts: number}>(`
      SELECT u.status,
        (SELECT count(*)::integer FROM trimmy.career_reason_privacy_receipts r
          WHERE r.user_id=u.id AND r.mutation_id=$2::uuid) AS receipts
      FROM trimmy.users u WHERE u.id=$1::uuid`, [raceUser, raceMutation]);
    assert.deepEqual(durable.rows, [{status: 'closed', receipts: 1}]);
  });

  test('keeps self history across resets and labels each desk cycle', async () => {
    const page = await repository.listReasons(viewer, {
      scope: 'self', limit: 20, assetId: null, variantMint: null, cursor: null,
    });
    assert.equal(page.hasMore, false);
    assert.deepEqual(page.reasons.map(item => [item.orderId, item.deskCycle]), [
      [ids.viewerCurrent, 'current'],
      [ids.viewerHistorical, 'historical'],
    ]);
    assert.ok(page.reasons.every(item => item.author.isViewer));
  });

  test('shares only everyone authors with active accounts', async () => {
    const page = await repository.listReasons(viewer, {
      scope: 'everyone', limit: 20, assetId: 'apple', variantMint: secondMint,
      cursor: null,
    });
    assert.deepEqual(new Set(page.reasons.map(item => item.author.handle)),
      new Set(['reason_public']));
    assert.equal(page.reasons.filter(item => item.author.handle === 'reason_public').length, 2);
    assert.equal(page.reasons.some(item => item.author.handle === 'reason_friend'), false);
    assert.equal(page.reasons.some(item => item.author.handle === 'reason_private'), false);
    assert.equal(page.reasons.some(item => item.author.handle === 'reason_closed'), false);

    const viewerPage = await repository.listReasons(viewer, {
      scope: 'everyone', limit: 20, assetId: 'apple', variantMint: firstMint,
      cursor: null,
    });
    assert.deepEqual(viewerPage.reasons.map(item => [item.orderId, item.deskCycle]), [
      [ids.viewerCurrent, 'current'],
    ]);
  });

  test('filters an exact mint and paginates equal timestamps by public reason ID', async () => {
    const exact = await repository.listReasons(viewer, {
      scope: 'everyone', limit: 20, assetId: 'apple', variantMint: secondMint,
      cursor: null,
    });
    assert.deepEqual(new Set(exact.reasons.map(item => item.orderId)),
      new Set([ids.publicFirst, ids.publicSecond]));

    const publicRows = (await repository.listReasons(viewer, {
      scope: 'everyone', limit: 20, assetId: 'apple', variantMint: secondMint,
      cursor: null,
    })).reasons;
    assert.equal(publicRows.length, 2);
    assert.equal(publicRows[0]?.savedAt, publicRows[1]?.savedAt);
    const first = await repository.listReasons(viewer, {
      scope: 'everyone', limit: 1, assetId: 'apple', variantMint: null as never,
      cursor: null,
    }).catch(error => error);
    assert.ok(first instanceof CareerReasonSharingError);

    const fullPage = await repository.listReasons(viewer, {
      scope: 'everyone', limit: 1, assetId: 'apple', variantMint: secondMint,
      cursor: null,
    });
    assert.equal(fullPage.hasMore, true);
    const nextPage = await repository.listReasons(viewer, {
      scope: 'everyone', limit: 20, assetId: 'apple', variantMint: secondMint,
      cursor: {savedAt: fullPage.reasons[0]!.savedAt,
        reasonId: fullPage.reasons[0]!.reasonId},
    });
    assert.equal(nextPage.reasons.some(item =>
      item.orderId === fullPage.reasons[0]!.orderId), false);
    assert.ok(nextPage.reasons.every(item =>
      item.savedAt < fullPage.reasons[0]!.savedAt ||
      (item.savedAt === fullPage.reasons[0]!.savedAt &&
        item.reasonId < fullPage.reasons[0]!.reasonId)));
  });

  test('rejects missing principals, cross-account calls, malformed filters and direct tables', async () => {
    const client = await runtime.connect();
    try {
      const missing = await client.query(`SELECT outcome FROM
        trimmy.career_reason_privacy_get($1::uuid)`, [viewer]);
      assert.equal(missing.rows[0]?.outcome, 'invalid');
      await client.query('BEGIN');
      await client.query("SELECT set_config('trimmy.practice_user_id',$1,true)", [viewer]);
      const cross = await client.query(`SELECT outcome FROM
        trimmy.career_reason_privacy_get($1::uuid)`, [publicAuthor]);
      assert.equal(cross.rows[0]?.outcome, 'invalid');
      const nullVisibility = await client.query(`SELECT outcome FROM
        trimmy.career_reason_privacy_put(
          $1::uuid,$2::uuid,repeat('f',64),1,NULL)`,
      [viewer, randomUUID()]);
      assert.equal(nullVisibility.rows[0]?.outcome, 'invalid');
      for (const values of [
        [viewer, null, null, null, null, null, 20],
        [viewer, 'friends', null, null, null, null, 20],
        [viewer, 'everyone', null, null, null, null, 20],
        [viewer, 'everyone', 'apple', null, null, null, 20],
        [viewer, 'everyone', null, null, null, null, 51],
      ]) {
        const malformed = await client.query(`SELECT outcome FROM
          trimmy.career_trade_reason_list(
            $1::uuid,$2::text,$3::text,$4::text,$5::timestamptz,$6::uuid,$7::integer)`,
        values);
        assert.equal(malformed.rows[0]?.outcome, 'invalid');
      }
      await client.query('ROLLBACK');
    } finally { client.release(); }
    await assert.rejects(runtime.query('SELECT * FROM trimmy.career_reason_privacy'),
      (error: unknown) => (error as {code?: unknown}).code === '42501');
    await assert.rejects(runtime.query('SELECT * FROM trimmy.career_trade_reasons'),
      (error: unknown) => (error as {code?: unknown}).code === '42501');
    await assert.rejects(runtime.query('SELECT trimmy.career_reason_runtime_user()'),
      (error: unknown) => (error as {code?: unknown}).code === '42501');

    const policies = await owner.query<{policyname: string; cmd: string}>(`
      SELECT policyname, cmd FROM pg_catalog.pg_policies
      WHERE schemaname='trimmy' AND policyname IN (
        'career_reason_privacy_function_authority',
        'career_reason_privacy_receipt_function_authority',
        'career_reason_feed_reason_authority',
        'career_reason_feed_profile_authority',
        'career_reason_feed_career_authority',
        'career_reason_feed_order_authority',
        'career_reason_feed_account_authority')
      ORDER BY policyname`);
    assert.deepEqual(policies.rows, [
      {policyname: 'career_reason_feed_account_authority', cmd: 'SELECT'},
      {policyname: 'career_reason_feed_career_authority', cmd: 'SELECT'},
      {policyname: 'career_reason_feed_order_authority', cmd: 'SELECT'},
      {policyname: 'career_reason_feed_profile_authority', cmd: 'SELECT'},
      {policyname: 'career_reason_feed_reason_authority', cmd: 'SELECT'},
      {policyname: 'career_reason_privacy_function_authority', cmd: 'ALL'},
      {policyname: 'career_reason_privacy_receipt_function_authority', cmd: 'ALL'},
    ]);
  });
});
