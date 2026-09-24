import assert from 'node:assert/strict';
import {test} from 'node:test';
import type {Pool, PoolClient} from 'pg';
import {InvitationRepositoryError} from '../src/invitations-repository.js';
import {PostgresInvitationsRepository} from '../src/postgres-invitations-repository.js';

const userId = '9f000000-0000-4000-8000-000000000001';
const invitationId = '11111111-1111-4111-8111-111111111111';
const secondInvitationId = '11111111-1111-4111-8111-111111111110';
const socialId = '33333333-3333-4333-8333-333333333333';
const mutationId = '22222222-2222-4222-8222-222222222222';

function invitationRow(overrides: Record<string, unknown> = {}) {
  return {
    outcome: 'found', principal_social_id: socialId, incoming_status: 'available',
    invitation_id: invitationId, state: 'offered', funding_kind: 'unfunded',
    sender_social_id: socialId, sender_handle: 'mira_trade', sender_persona: 'oracle',
    sender_rank_id: 'rookie', recipient_provider: 'x', recipient_handle_snapshot: 'ada_builds',
    expires_at: new Date('2026-10-01T10:00:00.000Z'),
    created_at: new Date('2026-09-20T10:00:00.000Z'), accepted_at: null,
    version: '2', party_role: 'recipient', retry_at: null, created: null,
    ...overrides,
  };
}

function harness(result: (sql: string, values?: readonly unknown[]) => {rows: unknown[]}) {
  const queries: Array<{sql: string; values?: readonly unknown[]}> = [];
  const releases: Array<Error | undefined> = [];
  const client = {
    query: async (raw: string, values?: readonly unknown[]) => {
      const sql = raw.replace(/\s+/gu, ' ').trim();
      queries.push(values === undefined ? {sql} : {sql, values});
      if (sql.includes('AS unsafe_role')) return {rows: [{unsafe_role: false}]};
      return result(sql, values);
    },
    release: (error?: Error) => { releases.push(error); },
  } as unknown as PoolClient;
  const pool = {connect: async () => client} satisfies Pick<Pool, 'connect'>;
  return {repository: new PostgresInvitationsRepository(pool,
    () => new Date('2026-09-20T12:00:00.000Z')), queries, releases};
}

test('a fixed identity conflict is returned by one atomic answer function without a bind side call', async () => {
  const queries: Array<{sql: string; values?: readonly unknown[]}> = [];
  const releases: Array<Error | undefined> = [];
  const client = {
    query: async (raw: string, values?: readonly unknown[]) => {
      const sql = raw.replace(/\s+/gu, ' ').trim();
      queries.push(values === undefined ? {sql} : {sql, values});
      if (sql.includes('AS unsafe_role')) return {rows: [{unsafe_role: false}]};
      if (sql.includes('social_invitation_answer')) return {rows: [{outcome: 'identity_conflict'}]};
      return {rows: []};
    },
    release: (error?: Error) => { releases.push(error); },
  } as unknown as PoolClient;
  const pool = {connect: async () => client} satisfies Pick<Pool, 'connect'>;
  const repository = new PostgresInvitationsRepository(pool);

  await assert.rejects(repository.answerV2(userId, invitationId, {
    action: 'decline',
    expectedVersion: 2,
    identity: {
      subject: '18446744073709551615',
      handleSnapshot: 'ada_builds',
      verifiedAt: '2026-09-20T12:00:00.000Z',
    },
  }), error => {
    assert.ok(error instanceof InvitationRepositoryError);
    assert.equal(error.code, 'SOCIAL_IDENTITY_CONFLICT');
    return true;
  });

  const answerCalls = queries.filter(query => query.sql.includes('social_invitation_answer'));
  assert.equal(answerCalls.length, 1);
  assert.deepEqual(answerCalls[0]?.values, [
    userId,
    invitationId,
    2,
    'decline',
    '18446744073709551615',
    'ada_builds',
    '2026-09-20T12:00:00.000Z',
  ]);
  assert.equal(queries.some(query => query.sql.includes('social_bind_verified_x_identity_internal')), false);
  assert.equal(queries.some(query => query.sql.includes('provider_identities')), true,
    'the only provider identity mention is the runtime role safety check');
  assert.deepEqual(queries.find(query => query.sql.includes('AS unsafe_role'))?.values,
    ['trimmy_social_moderator']);
  assert.equal(queries.at(-1)?.sql, 'COMMIT');
  assert.equal(queries.some(query => query.sql === 'ROLLBACK'), false);
  assert.deepEqual(releases, [undefined]);
});

test('an SQL failure inside the atomic answer function rolls the whole transaction back', async () => {
  const queries: string[] = [];
  const client = {
    query: async (raw: string) => {
      const sql = raw.replace(/\s+/gu, ' ').trim();
      queries.push(sql);
      if (sql.includes('AS unsafe_role')) return {rows: [{unsafe_role: false}]};
      if (sql.includes('social_invitation_answer')) throw new Error('atomic function failed');
      return {rows: []};
    },
    release: () => {},
  } as unknown as PoolClient;
  const pool = {connect: async () => client} satisfies Pick<Pool, 'connect'>;
  const repository = new PostgresInvitationsRepository(pool);

  await assert.rejects(repository.answerV2(userId, invitationId, {
    action: 'accept',
    expectedVersion: 2,
    identity: {
      subject: '18446744073709551615',
      handleSnapshot: 'ada_builds',
      verifiedAt: '2026-09-20T12:00:00.000Z',
    },
  }), /atomic function failed/);

  assert.equal(queries.filter(sql => sql.includes('social_invitation_answer')).length, 1);
  assert.equal(queries.at(-1), 'ROLLBACK');
  assert.equal(queries.includes('COMMIT'), false);
});

test('accept succeeds through the one atomic function without a preseeded identity side call', async () => {
  const h = harness(sql => sql.includes('social_invitation_answer') ? {rows: [invitationRow({
    outcome: 'accepted', state: 'accepted', accepted_at: new Date('2026-09-20T12:01:00.000Z'),
    version: '3', party_role: 'recipient', friendship_id: '55555555-5555-4555-8555-555555555555',
    friendship_revision: '1', connected_at: new Date('2026-09-20T12:01:00.000Z'),
  })]} : {rows: []});

  const accepted = await h.repository.answerV2(userId, invitationId, {
    action: 'accept',
    expectedVersion: 2,
    identity: {
      subject: '18446744073709551615',
      handleSnapshot: 'ada_builds',
      verifiedAt: '2026-09-20T12:00:00.000Z',
    },
  });

  assert.equal(accepted.state, 'accepted');
  assert.equal(accepted.role, 'recipient');
  assert.equal(JSON.stringify(accepted).includes('18446744073709551615'), false);
  assert.equal(h.queries.filter(query => query.sql.includes('social_invitation_answer')).length, 1);
  assert.equal(h.queries.some(query => query.sql.includes('social_bind_verified_x_identity_internal')), false);
  assert.equal(h.queries.at(-1)?.sql, 'COMMIT');
});

test('create passes one canonical request hash and distinguishes an exact receipt replay', async () => {
  const h = harness(sql => sql.includes('social_invitation_create(') ? {rows: [invitationRow({
    outcome: 'saved', created: false, state: 'draft', recipient_provider: null,
    recipient_handle_snapshot: null, version: '0', party_role: 'sender',
  })]} : {rows: []});

  const result = await h.repository.createV2(userId, {
    mutationId,
    expiresAt: '2026-09-27T12:00:00.000Z',
  });

  assert.equal(result.created, false);
  assert.equal(result.invitation.state, 'draft');
  assert.equal(result.invitation.recipient, null);
  const call = h.queries.find(query => query.sql.includes('social_invitation_create('));
  assert.deepEqual(call?.values?.slice(0, 2), [userId, mutationId]);
  assert.match(call?.values?.[2] as string, /^[a-f0-9]{64}$/);
  assert.equal(call?.values?.[3], '2026-09-27T12:00:00.000Z');
  assert.equal(h.queries.at(-1)?.sql, 'COMMIT');
});

test('create always reaches receipt-first SQL after expiry and for semantic-invalid windows', async () => {
  const replay = harness(sql => sql.includes('social_invitation_create(') ? {rows: [invitationRow({
    outcome: 'saved', created: false, state: 'draft', recipient_provider: null,
    recipient_handle_snapshot: null, version: '0', party_role: 'sender',
    expires_at: new Date('2026-09-20T11:00:00.000Z'),
  })]} : {rows: []});
  const result = await replay.repository.createV2(userId, {
    mutationId, expiresAt: '2026-09-20T11:00:00.000Z',
  });
  assert.equal(result.created, false);
  assert.equal(replay.queries.filter(query => query.sql.includes('social_invitation_create(')).length, 1);

  const invalid = harness(sql => sql.includes('social_invitation_create(')
    ? {rows: [invitationRow({outcome: 'invalid'})]} : {rows: []});
  await assert.rejects(invalid.repository.createV2(userId, {
    mutationId, expiresAt: '2027-09-20T12:00:00.000Z',
  }), (error: unknown) => error instanceof InvitationRepositoryError &&
    error.code === 'INVITATION_INVALID_INPUT');
  assert.equal(invalid.queries.filter(query => query.sql.includes('social_invitation_create(')).length, 1);
  assert.equal(invalid.queries.at(-1)?.sql, 'COMMIT');
});

test('the open invitation cap is a 409 limit conflict without a fake retry window', async () => {
  const h = harness(sql => sql.includes('social_invitation_create(')
    ? {rows: [invitationRow({outcome: 'open_limit'})]} : {rows: []});

  await assert.rejects(h.repository.createV2(userId, {
    mutationId,
    expiresAt: '2026-09-27T12:00:00.000Z',
  }), error => {
    assert.ok(error instanceof InvitationRepositoryError);
    assert.equal(error.code, 'INVITATION_LIMIT_REACHED');
    assert.equal(error.retryAfterSeconds, undefined);
    return true;
  });
  assert.equal(h.queries.at(-1)?.sql, 'COMMIT');
});

test('list asks SQL for one lookahead row and returns a bounded deterministic page', async () => {
  const h = harness(sql => sql.includes('social_invitation_list') ? {rows: [
    invitationRow(),
    invitationRow({invitation_id: secondInvitationId, created_at: new Date('2026-09-20T09:00:00.000Z')}),
  ]} : {rows: []});

  const page = await h.repository.listV2(userId, {
    box: 'open',
    limit: 1,
    cursor: null,
    freshXSubject: '18446744073709551615',
  });

  assert.equal(page.invitations.length, 1);
  assert.equal(page.invitations[0]?.id, invitationId);
  assert.equal(page.hasMore, true);
  assert.equal(page.principalSocialId, socialId);
  assert.equal(page.incomingInvitations, 'available');
  const call = h.queries.find(query => query.sql.includes('social_invitation_list'));
  assert.equal(call?.values?.[5], 2);
});

test('cross-principal invitation cursor rejection commits the database read budget', async () => {
  const h = harness(sql => sql.includes('social_invitation_list') ? {rows: [{
    outcome: 'empty', principal_social_id: socialId, incoming_status: 'available',
  }]} : {rows: []});
  await assert.rejects(h.repository.listV2(userId, {
    box: 'open', limit: 20, freshXSubject: '18446744073709551615',
    cursor: {principalSocialId: '44444444-4444-4444-8444-444444444444',
      createdAt: '2026-09-20T13:00:00.000Z', invitationId},
  }), (error: unknown) => error instanceof InvitationRepositoryError &&
    error.code === 'INVITATION_INVALID_INPUT');
  assert.equal(h.queries.at(-1)?.sql, 'COMMIT');
  assert.equal(h.queries.some(query => query.sql === 'ROLLBACK'), false);
});
