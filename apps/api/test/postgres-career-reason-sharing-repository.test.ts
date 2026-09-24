import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {describe, test} from 'node:test';
import type {Pool, PoolClient} from 'pg';
import {CareerReasonSharingError, isCareerReasonFriendsListItem,
  isCareerReasonInternalListItem} from '../src/career-reason-sharing.js';
import {PostgresCareerReasonSharingRepository} from
  '../src/postgres-career-reason-sharing-repository.js';

const userId = '74000000-0000-4000-8000-000000000001';
const mutationId = '74000000-0000-4000-8000-000000000002';
const firstOrder = '74000000-0000-4000-8000-000000000020';
const secondOrder = '74000000-0000-4000-8000-000000000010';
const thirdOrder = '74000000-0000-4000-8000-000000000009';
const firstReason = '75000000-0000-4000-8000-000000000020';
const authorSocialId = '76000000-0000-4000-8000-000000000020';
const variantMint = '11111111111111111111111111111111';
const createdAt = new Date('2026-09-20T12:00:00.000Z');

type Query = {readonly sql: string; readonly values?: readonly unknown[]};

function harness(
  result: (sql: string, values?: readonly unknown[]) => {rows: unknown[]},
  options: {readonly unsafeRole?: boolean; readonly wrongPrincipal?: boolean} = {},
) {
  const queries: Query[] = [];
  const releases: Array<Error | undefined> = [];
  const client = {
    query: async (raw: string, values?: readonly unknown[]) => {
      const sql = raw.replace(/\s+/gu, ' ').trim();
      queries.push(values === undefined ? {sql} : {sql, values});
      if (sql.includes('AS unsafe_role')) return {rows: [{unsafe_role: options.unsafeRole ?? false}]};
      if (sql.includes("set_config('trimmy.practice_user_id'")) {
        return {rows: [{scoped_user: options.wrongPrincipal ? 'other' : values?.[0]}]};
      }
      return result(sql, values);
    },
    release: (error?: Error) => { releases.push(error); },
  } as unknown as PoolClient;
  const pool = {connect: async () => client} satisfies Pick<Pool, 'connect'>;
  return {
    repository: new PostgresCareerReasonSharingRepository(pool),
    queries,
    releases,
  };
}

function emptyRow() {
  return {
    outcome: 'empty', principal_social_id: null, reason_id: null, order_id: null, author_social_id: null,
    author_handle: null, author_persona: null, author_rank_id: null,
    asset_id: null, variant_mint: null, symbol: null,
    note: null, desk_cycle: null, saved_at: null, is_viewer: null,
  };
}

function reasonRow(orderId: string, savedAt: string, overrides: Record<string, unknown> = {}) {
  return {
    outcome: 'found', principal_social_id: null, reason_id: orderId.replace(/^74/u, '75'),
    order_id: orderId, author_social_id: null, author_handle: 'ada_trade', author_persona: null,
    author_rank_id: 'analyst', asset_id: 'apple', variant_mint: variantMint,
    symbol: 'AAPLx', note: 'Margins improved for a second quarter.',
    desk_cycle: 'current', saved_at: new Date(savedAt), is_viewer: true,
    ...overrides,
  };
}

describe('Postgres Career reason sharing repository', () => {
  test('reads the conservative privacy snapshot under the exact principal', async () => {
    const h = harness(sql => sql.includes('career_reason_privacy_get') ? {rows: [{
      outcome: 'found', revision: '1', visibility: 'nobody', configured: false,
      created_at: createdAt, updated_at: createdAt,
    }]} : {rows: []});

    const privacy = await h.repository.getPrivacy(userId.toUpperCase());

    assert.deepEqual(privacy, {
      revision: 1, visibility: 'nobody', configured: false,
      friendsSharing: 'unavailable',
      createdAt: createdAt.toISOString(), updatedAt: createdAt.toISOString(),
    });
    assert.equal(h.queries[0]?.sql, 'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
    assert.deepEqual(h.queries.find(query => query.sql.includes('set_config'))?.values, [userId]);
    assert.deepEqual(h.queries.find(query => query.sql.includes('privacy_get'))?.values, [userId]);
    assert.equal(h.queries.at(-1)?.sql, 'COMMIT');
    assert.deepEqual(h.releases, [undefined]);
    assert.deepEqual(h.queries.find(query => query.sql.includes('AS unsafe_role'))?.values,
      ['trimmy_social_moderator']);
  });

  test('writes every explicit privacy choice with a canonical hash', async () => {
    const updatedAt = new Date('2026-09-20T12:00:00.001Z');
    const h = harness(sql => sql.includes('career_reason_privacy_put') ? {rows: [{
      outcome: 'saved', revision: '2', visibility: 'friends', configured: true,
      created_at: createdAt, updated_at: updatedAt,
    }]} : {rows: []});

    const privacy = await h.repository.savePrivacy(userId, {
      mutationId, baseRevision: 1, visibility: 'friends',
    });

    const call = h.queries.find(query => query.sql.includes('privacy_put'));
    const expectedHash = createHash('sha256').update(
      '{"baseRevision":1,"visibility":"friends"}',
    ).digest('hex');
    assert.deepEqual(call?.values, [userId, mutationId, expectedHash, 1, 'friends']);
    assert.equal(privacy.revision, 2);
    assert.equal(privacy.visibility, 'friends');
    assert.equal(privacy.friendsSharing, 'unavailable');
    assert.equal(h.queries.at(-1)?.sql, 'COMMIT');
  });

  test('returns current privacy truth when an older mutation is replayed', async () => {
    const currentAt = new Date('2026-09-20T12:00:00.003Z');
    const h = harness(sql => sql.includes('career_reason_privacy_put') ? {rows: [{
      outcome: 'saved', revision: '4', visibility: 'nobody', configured: true,
      created_at: createdAt, updated_at: currentAt,
    }]} : {rows: []});

    const current = await h.repository.savePrivacy(userId, {
      mutationId, baseRevision: 1, visibility: 'friends',
    });

    assert.equal(current.revision, 4);
    assert.equal(current.visibility, 'nobody');
    assert.equal(current.updatedAt, currentAt.toISOString());
  });

  test('lists a bounded stable page and keeps the extra row only as continuation evidence', async () => {
    const h = harness(sql => sql.includes('career_trade_reason_list') ? {rows: [
      reasonRow(firstOrder, '2026-09-20T12:00:02.000Z'),
      reasonRow(secondOrder, '2026-09-20T12:00:01.000Z', {
        author_handle: 'sal_trade', author_rank_id: 'rookie', is_viewer: false,
        desk_cycle: 'current',
      }),
      reasonRow(thirdOrder, '2026-09-20T12:00:00.000Z'),
    ]} : {rows: []});

    const page = await h.repository.listReasons(userId, {
      scope: 'everyone', limit: 2, assetId: 'apple', variantMint, cursor: null,
    });

    assert.equal(page.hasMore, true);
    assert.equal(page.reasons.every(isCareerReasonInternalListItem), true);
    assert.deepEqual(page.reasons.map(item => isCareerReasonInternalListItem(item) && item.orderId),
      [firstOrder, secondOrder]);
    assert.equal(isCareerReasonInternalListItem(page.reasons[1]!) && page.reasons[1].deskCycle,
      'current');
    assert.deepEqual(h.queries.find(query => query.sql.includes('reason_list'))?.values,
      [userId, 'everyone', 'apple', variantMint, null, null, 2]);
    assert.equal(h.queries.at(-1)?.sql, 'COMMIT');
  });

  test('parses the friends projection and rejects private-field or author-identity drift', async () => {
    const friendRow = reasonRow(firstOrder, '2026-09-20T12:00:01.000Z', {
      order_id: null,
      principal_social_id: authorSocialId,
      author_social_id: authorSocialId,
      author_persona: 'oracle',
      desk_cycle: null,
      is_viewer: false,
    });
    const h = harness(sql => sql.includes('career_trade_reason_list')
      ? {rows: [friendRow]} : {rows: []});
    const page = await h.repository.listReasons(userId, {
      scope: 'friends', limit: 20, assetId: 'apple', variantMint, cursor: null,
    });
    assert.equal(page.reasons.length, 1);
    assert.equal(page.principalSocialId, authorSocialId);
    assert.equal(isCareerReasonFriendsListItem(page.reasons[0]!), true);
    if (isCareerReasonFriendsListItem(page.reasons[0]!)) {
      assert.equal(page.reasons[0].author.socialId, authorSocialId);
      assert.equal(page.reasons[0].author.persona, 'oracle');
      assert.equal('orderId' in page.reasons[0], false);
      assert.equal('deskCycle' in page.reasons[0], false);
    }

    for (const overrides of [
      {order_id: firstOrder},
      {desk_cycle: 'current'},
      {author_social_id: null},
      {author_persona: null},
      {author_persona: 'spark'},
      {is_viewer: true},
      {principal_social_id: null},
    ]) {
      const malformed = harness(sql => sql.includes('career_trade_reason_list')
        ? {rows: [{...friendRow, ...overrides}]} : {rows: []});
      await assert.rejects(malformed.repository.listReasons(userId, {
        scope: 'friends', limit: 20, assetId: 'apple', variantMint, cursor: null,
      }), (error: unknown) => error instanceof CareerReasonSharingError &&
        error.code === 'CAREER_REASON_SHARING_STORAGE_INVALID');
    }
  });

  test('accepts only one exact all-null empty sentinel', async () => {
    const h = harness(sql => sql.includes('career_trade_reason_list')
      ? {rows: [emptyRow()]} : {rows: []});
    assert.deepEqual(await h.repository.listReasons(userId, {
      scope: 'self', limit: 20, assetId: null, variantMint: null, cursor: null,
    }), {reasons: [], hasMore: false});

    const malformed = harness(sql => sql.includes('career_trade_reason_list')
      ? {rows: [{...emptyRow(), note: 'hidden data'}]} : {rows: []});
    await assert.rejects(malformed.repository.listReasons(userId, {
      scope: 'self', limit: 20, assetId: null, variantMint: null, cursor: null,
    }), (error: unknown) => error instanceof CareerReasonSharingError &&
      error.code === 'CAREER_REASON_SHARING_STORAGE_INVALID');
    assert.equal(malformed.queries.at(-1)?.sql, 'ROLLBACK');

    const friends = harness(sql => sql.includes('career_trade_reason_list')
      ? {rows: [{...emptyRow(), principal_social_id: authorSocialId}]} : {rows: []});
    assert.deepEqual(await friends.repository.listReasons(userId, {
      scope: 'friends', limit: 20, assetId: 'apple', variantMint, cursor: null,
    }), {reasons: [], hasMore: false, principalSocialId: authorSocialId});
  });

  test('rejects a friends cursor rebound to another public principal', async () => {
    const h = harness(sql => sql.includes('career_trade_reason_list') ? {rows: [reasonRow(
      firstOrder, '2026-09-20T12:00:00.000Z', {
        principal_social_id: authorSocialId,
        order_id: null,
        author_social_id: '76000000-0000-4000-8000-000000000021',
        author_persona: 'wolf',
        desk_cycle: null,
        is_viewer: false,
      },
    )]} : {rows: []});
    await assert.rejects(h.repository.listReasons(userId, {
      scope: 'friends', limit: 20, assetId: 'apple', variantMint,
      cursor: {principalSocialId: '76000000-0000-4000-8000-000000000099',
        savedAt: '2026-09-20T12:00:01.000Z', reasonId: firstReason},
    }), (error: unknown) => error instanceof CareerReasonSharingError &&
      error.code === 'CAREER_REASON_SHARING_STORAGE_INVALID');
  });

  test('rejects disorder, filter drift, cursor rebound and false self authorship', async () => {
    const cases = [
      [
        reasonRow(secondOrder, '2026-09-20T12:00:01.000Z'),
        reasonRow(firstOrder, '2026-09-20T12:00:02.000Z'),
      ],
      [reasonRow(firstOrder, '2026-09-20T12:00:01.000Z', {asset_id: 'tesla'})],
      [reasonRow(firstOrder, '2026-09-20T12:00:03.000Z')],
      [reasonRow(firstOrder, '2026-09-20T12:00:01.000Z', {is_viewer: false})],
    ];
    for (const [index, rows] of cases.entries()) {
      const h = harness(sql => sql.includes('career_trade_reason_list') ? {rows} : {rows: []});
      await assert.rejects(h.repository.listReasons(userId, {
        scope: index === 0 ? 'everyone' : 'self',
        limit: 20,
        assetId: index <= 1 ? 'apple' : null,
        variantMint: index <= 1 ? variantMint : null,
        cursor: index === 2
          ? {savedAt: '2026-09-20T12:00:02.000Z', reasonId: firstReason}
          : null,
      }), (error: unknown) => error instanceof CareerReasonSharingError &&
        error.code === 'CAREER_REASON_SHARING_STORAGE_INVALID');
    }

    const historicalPublic = harness(sql => sql.includes('career_trade_reason_list')
      ? {rows: [reasonRow(firstOrder, '2026-09-20T12:00:01.000Z', {
        desk_cycle: 'historical',
      })]} : {rows: []});
    await assert.rejects(historicalPublic.repository.listReasons(userId, {
      scope: 'everyone', limit: 20, assetId: 'apple', variantMint, cursor: null,
    }), (error: unknown) => error instanceof CareerReasonSharingError &&
      error.code === 'CAREER_REASON_SHARING_STORAGE_INVALID');
  });

  test('maps privacy conflicts and account loss to bounded public codes', async () => {
    for (const [outcome, code] of [
      ['revision_conflict', 'CAREER_REASON_PRIVACY_REVISION_CONFLICT'],
      ['idempotency_conflict', 'CAREER_REASON_SHARING_IDEMPOTENCY_CONFLICT'],
      ['revision_exhausted', 'CAREER_REASON_SHARING_REVISION_EXHAUSTED'],
      ['account_missing', 'CAREER_REASON_SHARING_ACCOUNT_NOT_FOUND'],
      ['forbidden', 'CAREER_REASON_FRIENDS_ACCOUNT_REQUIRED'],
    ] as const) {
      const h = harness(sql => sql.includes('career_reason_privacy_put')
        ? {rows: [{outcome}]} : {rows: []});
      await assert.rejects(h.repository.savePrivacy(userId, {
        mutationId, baseRevision: 1, visibility: 'everyone',
      }), (error: unknown) => error instanceof CareerReasonSharingError && error.code === code);
      assert.equal(h.queries.at(-1)?.sql, 'ROLLBACK');
    }
  });

  test('stops before a function call for privileged roles or failed principal binding', async () => {
    for (const options of [{unsafeRole: true}, {wrongPrincipal: true}]) {
      const h = harness(() => ({rows: []}), options);
      await assert.rejects(h.repository.getPrivacy(userId),
        (error: unknown) => error instanceof CareerReasonSharingError &&
          error.code === (options.unsafeRole
            ? 'CAREER_REASON_SHARING_RUNTIME_ROLE_INVALID'
            : 'CAREER_REASON_SHARING_STORAGE_INVALID'));
      assert.equal(h.queries.some(query => query.sql.includes('privacy_get')), false);
      assert.equal(h.queries.at(-1)?.sql, 'ROLLBACK');
    }
  });
});
