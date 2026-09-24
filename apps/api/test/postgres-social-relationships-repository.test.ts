import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {test} from 'node:test';
import type {Pool, PoolClient} from 'pg';
import {PostgresSocialRelationshipsRepository} from
  '../src/postgres-social-relationships-repository.js';
import {SocialRelationshipError} from '../src/social-relationships.js';

const userId = '72000000-0000-4000-8000-000000000001';
const principalSocialId = '72000000-0000-4000-8000-000000000002';
const friendshipId = '72000000-0000-4000-8000-000000000003';
const secondFriendshipId = '72000000-0000-4000-8000-000000000004';
const targetSocialId = '72000000-0000-4000-8000-000000000005';
const secondSocialId = '72000000-0000-4000-8000-000000000006';
const mutationId = '72000000-0000-4000-8000-000000000007';
const reasonId = '72000000-0000-4000-8000-000000000008';
const reportId = '72000000-0000-4000-8000-000000000009';
const at = new Date('2026-09-20T12:00:00.000Z');

type Query = {readonly sql: string; readonly values?: readonly unknown[]};

function harness(result: (sql: string, values?: readonly unknown[]) => {rows: unknown[]},
  unsafeRole = false) {
  const queries: Query[] = [];
  const releases: Array<Error | undefined> = [];
  const client = {
    query: async (raw: string, values?: readonly unknown[]) => {
      const sql = raw.replace(/\s+/gu, ' ').trim();
      queries.push(values === undefined ? {sql} : {sql, values});
      if (sql.includes('AS unsafe_role')) return {rows: [{unsafe_role: unsafeRole}]};
      if (sql.includes("set_config('trimmy.practice_user_id'")) return {rows: [{scoped_user: values?.[0]}]};
      return result(sql, values);
    },
    release: (error?: Error) => { releases.push(error); },
  } as unknown as PoolClient;
  const pool = {connect: async () => client} satisfies Pick<Pool, 'connect'>;
  return {repository: new PostgresSocialRelationshipsRepository(pool), queries, releases};
}

function friendRow(overrides: Record<string, unknown> = {}) {
  return {outcome: 'found', principal_social_id: principalSocialId,
    friendship_id: friendshipId, revision: '1', connected_at: at,
    social_id: targetSocialId, handle: 'ada_trade', persona: 'oracle',
    rank_id: 'rookie', retry_at: null, ...overrides};
}

function blockRow(overrides: Record<string, unknown> = {}) {
  return {outcome: 'found', principal_social_id: principalSocialId,
    social_id: targetSocialId, handle: 'ada_trade', revision: '1',
    updated_at: at, retry_at: null, target_social_id: null,
    applied_revision: null, blocked: null, ...overrides};
}

test('friend list uses one lookahead row and preserves quota on cross-principal cursors', async () => {
  const h = harness(sql => sql.includes('social_friend_list') ? {rows: [
    friendRow(),
    friendRow({friendship_id: secondFriendshipId, social_id: secondSocialId,
      connected_at: new Date('2026-09-20T11:00:00.000Z')}),
  ]} : {rows: []});
  const page = await h.repository.listFriends(userId, {limit: 1, cursor: null});
  assert.equal(page.hasMore, true);
  assert.equal(page.friends.length, 1);
  assert.equal(page.principalSocialId, principalSocialId);
  assert.deepEqual(page.friends[0], {friendshipId, revision: 1,
    connectedAt: at.toISOString(), person: {socialId: targetSocialId,
      handle: 'ada_trade', persona: 'oracle', rank: {id: 'rookie', label: 'Rookie'}}});
  assert.equal(h.queries.find(query => query.sql.includes('social_friend_list'))?.values?.[3], 2);

  const mismatch = harness(sql => sql.includes('social_friend_list')
    ? {rows: [{outcome: 'empty', principal_social_id: principalSocialId,
      friendship_id: null, revision: null, connected_at: null, social_id: null,
      handle: null, persona: null, rank_id: null, retry_at: null}]}
    : {rows: []});
  await assert.rejects(mismatch.repository.listFriends(userId, {limit: 20, cursor: {
    principalSocialId: secondSocialId, connectedAt: at.toISOString(), friendshipId,
  }}), (error: unknown) => error instanceof SocialRelationshipError &&
    error.code === 'SOCIAL_INVALID_INPUT');
  assert.equal(mismatch.queries.at(-1)?.sql, 'COMMIT');
  assert.equal(mismatch.queries.some(query => query.sql === 'ROLLBACK'), false);
});

test('block list parses active and closed targets without returning reverse state', async () => {
  const h = harness(sql => sql.includes('social_block_list') ? {rows: [
    blockRow(),
    blockRow({social_id: secondSocialId, handle: null, revision: '3',
      updated_at: new Date('2026-09-20T11:00:00.000Z')}),
  ]} : {rows: []});
  const page = await h.repository.listBlocks(userId, {limit: 2, cursor: null});
  assert.deepEqual(page.blocks.map(block => block.handle), ['ada_trade', null]);
  assert.equal(page.blocks.every(block => block.blocked), true);
  assert.equal(page.hasMore, false);
  assert.equal(h.queries.at(-1)?.sql, 'COMMIT');
});

test('friend removal binds its receipt hash and commits fixed conflicts', async () => {
  const h = harness(sql => sql.includes('social_friend_remove') ? {rows: [{
    outcome: 'removed', friendship_id: friendshipId, applied_revision: '2',
    state: 'removed', occurred_at: at, retry_at: null,
  }]} : {rows: []});
  const result = await h.repository.removeFriend(userId, friendshipId,
    {mutationId, expectedRevision: 1});
  assert.equal(result.appliedRevision, 2);
  const call = h.queries.find(query => query.sql.includes('social_friend_remove'))!;
  assert.deepEqual(call.values, [userId, friendshipId, mutationId,
    createHash('sha256').update(JSON.stringify([
      'social-friend-remove-v1', friendshipId, 1,
    ])).digest('hex'), 1]);

  const conflict = harness(sql => sql.includes('social_friend_remove') ? {rows: [{
    outcome: 'idempotency_conflict', friendship_id: null, applied_revision: null,
    state: null, occurred_at: null, retry_at: null,
  }]} : {rows: []});
  await assert.rejects(conflict.repository.removeFriend(userId, friendshipId,
    {mutationId, expectedRevision: 1}), (error: unknown) =>
    error instanceof SocialRelationshipError &&
      error.code === 'SOCIAL_RELATIONSHIP_IDEMPOTENCY_CONFLICT');
  assert.equal(conflict.queries.at(-1)?.sql, 'COMMIT');
});

test('block receipt replay keeps immutable applied revision beside the current snapshot', async () => {
  const h = harness(sql => sql.includes('social_block_put') ? {rows: [{
    outcome: 'saved', target_social_id: targetSocialId, applied_revision: '1',
    revision: '3', blocked: true, updated_at: at, retry_at: null,
  }]} : {rows: []});
  const result = await h.repository.putBlock(userId, targetSocialId,
    {mutationId, baseRevision: 0, blocked: true});
  assert.equal(result.appliedRevision, 1);
  assert.equal(result.block.revision, 3);
  assert.equal(result.block.blocked, true);
  const call = h.queries.find(query => query.sql.includes('social_block_put'))!;
  assert.deepEqual(call.values?.slice(0, 3), [userId, targetSocialId, mutationId]);
  assert.match(call.values?.[3] as string, /^[a-f0-9]{64}$/u);
  assert.deepEqual(call.values?.slice(4), [0, 'active']);
});

test('target block snapshot distinguishes an absent row without revealing target profile data', async () => {
  const absent = harness(sql => sql.includes('social_block_get') ? {rows: [{
    outcome: 'found', target_social_id: targetSocialId, revision: '0',
    blocked: false, updated_at: null, retry_at: null,
  }]} : {rows: []});
  assert.deepEqual(await absent.repository.getBlock(userId, targetSocialId), {
    socialId: targetSocialId, revision: 0, blocked: false, updatedAt: null,
  });
  assert.deepEqual(absent.queries.find(query => query.sql.includes('social_block_get'))?.values,
    [userId, targetSocialId]);

  const existing = harness(sql => sql.includes('social_block_get') ? {rows: [{
    outcome: 'found', target_social_id: targetSocialId, revision: '4',
    blocked: false, updated_at: at, retry_at: null,
  }]} : {rows: []});
  assert.deepEqual(await existing.repository.getBlock(userId, targetSocialId), {
    socialId: targetSocialId, revision: 4, blocked: false, updatedAt: at.toISOString(),
  });
});

test('a second report mutation returns the original receipt category and commits its budget', async () => {
  const h = harness(sql => sql.includes('social_reason_report_create') ? {rows: [{
    outcome: 'found', report_id: reportId, reason_id: reasonId,
    category: 'spam', received_at: at, retry_at: null,
  }]} : {rows: []});
  const result = await h.repository.reportReason(userId,
    {mutationId, reasonId, category: 'harassment'});
  assert.equal(result.created, false);
  assert.equal(result.report.category, 'spam');
  assert.equal(h.queries.at(-1)?.sql, 'COMMIT');
});

test('rate outcomes commit durable budget while SQL failures roll back atomically', async () => {
  const limited = harness(sql => sql.includes('social_block_list') ? {rows: [{
    outcome: 'rate_limited', principal_social_id: null, social_id: null,
    handle: null, revision: null, updated_at: null,
    retry_at: new Date(Date.now() + 10_000),
  }]} : {rows: []});
  await assert.rejects(limited.repository.listBlocks(userId, {limit: 20, cursor: null}),
    (error: unknown) => error instanceof SocialRelationshipError &&
      error.code === 'SOCIAL_RATE_LIMITED' && error.retryAfterSeconds !== undefined);
  assert.equal(limited.queries.at(-1)?.sql, 'COMMIT');

  const failed = harness(sql => {
    if (sql.includes('social_reason_report_create')) throw new Error('database failure');
    return {rows: []};
  });
  await assert.rejects(failed.repository.reportReason(userId,
    {mutationId, reasonId, category: 'unsafe'}), (error: unknown) =>
    error instanceof SocialRelationshipError && error.code === 'SOCIAL_UNAVAILABLE');
  assert.equal(failed.queries.at(-1)?.sql, 'ROLLBACK');
});

test('unsafe runtime roles fail before any social function call', async () => {
  const h = harness(() => ({rows: []}), true);
  await assert.rejects(h.repository.listFriends(userId, {limit: 20, cursor: null}),
    (error: unknown) => error instanceof SocialRelationshipError &&
      error.code === 'SOCIAL_RUNTIME_ROLE_INVALID');
  assert.equal(h.queries.some(query => query.sql.includes('social_friend_list')), false);
  assert.equal(h.queries.at(-1)?.sql, 'ROLLBACK');
});
