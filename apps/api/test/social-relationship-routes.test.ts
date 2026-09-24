import assert from 'node:assert/strict';
import {test} from 'node:test';
import {buildApp} from '../src/app.js';
import {SocialRelationshipError} from '../src/social-relationships.js';
import type {
  SocialBlockCursor, SocialFriendCursor, SocialRelationshipsRepository,
} from '../src/social-relationships.js';
import type {SocialRelationshipAdapters} from '../src/social-relationship-routes.js';

const userId = '71000000-0000-4000-8000-000000000001';
const principalSocialId = '71000000-0000-4000-8000-000000000002';
const otherPrincipal = '71000000-0000-4000-8000-000000000003';
const friendshipId = '71000000-0000-4000-8000-000000000004';
const targetSocialId = '71000000-0000-4000-8000-000000000005';
const mutationId = '71000000-0000-4000-8000-000000000006';
const reasonId = '71000000-0000-4000-8000-000000000007';
const reportId = '71000000-0000-4000-8000-000000000008';
const instant = '2026-09-20T12:00:00.000Z';

function setup() {
  const calls: {
    friendCursors: Array<SocialFriendCursor | null>;
    blockCursors: Array<SocialBlockCursor | null>;
    mutations: unknown[];
  } = {friendCursors: [], blockCursors: [], mutations: []};
  let principal = principalSocialId;
  let authenticated = true;
  const repository: SocialRelationshipsRepository = {
    listFriends: async (_user, input) => {
      calls.friendCursors.push(input.cursor);
      return {principalSocialId: principal, hasMore: true, friends: [{
        friendshipId, revision: 1, connectedAt: instant,
        person: {socialId: targetSocialId, handle: 'ada_trade', persona: 'oracle',
          rank: {id: 'rookie', label: 'Rookie'}},
      }]};
    },
    removeFriend: async (_user, id, command) => {
      calls.mutations.push({kind: 'remove', id, command});
      return {mutationId: command.mutationId, friendshipId: id,
        appliedRevision: 2, state: 'removed', occurredAt: instant};
    },
    listBlocks: async (_user, input) => {
      calls.blockCursors.push(input.cursor);
      return {principalSocialId: principal, hasMore: true, blocks: [{
        socialId: targetSocialId, handle: null, revision: 2, blocked: true, updatedAt: instant,
      }]};
    },
    getBlock: async (_user, id) => ({
      socialId: id, revision: 0, blocked: false, updatedAt: null,
    }),
    putBlock: async (_user, id, command) => {
      calls.mutations.push({kind: 'block', id, command});
      return {mutationId: command.mutationId, appliedRevision: 3,
        block: {socialId: id, handle: null, revision: 4, blocked: command.blocked, updatedAt: instant}};
    },
    reportReason: async (_user, command) => {
      calls.mutations.push({kind: 'report', command});
      return {created: true, report: {reportId, reasonId: command.reasonId,
        category: command.category, receivedAt: instant}};
    },
  };
  const adapters: SocialRelationshipAdapters = {
    repository,
    authenticate: async () => authenticated ? {userId} : null,
  };
  return {adapters, calls,
    setPrincipal: (value: string) => { principal = value; },
    setAuthenticated: (value: boolean) => { authenticated = value; }};
}

test('friend and block lists are bounded, no-store and principal-bound', async () => {
  const s = setup();
  const app = buildApp({logger: false, socialRelationships: s.adapters});
  try {
    const friends = await app.inject('/v1/social/friends?limit=1');
    assert.equal(friends.statusCode, 200, friends.body);
    assert.equal(friends.headers['cache-control'], 'no-store');
    assert.deepEqual(friends.json().friends[0], {
      friendshipId, revision: 1, connectedAt: instant,
      person: {socialId: targetSocialId, handle: 'ada_trade', persona: 'oracle',
        rank: {id: 'rookie', label: 'Rookie'}},
    });
    const friendCursor = friends.json().nextCursor as string;
    assert.equal(typeof friendCursor, 'string');

    const blocks = await app.inject('/v1/social/blocks?limit=1');
    assert.equal(blocks.statusCode, 200, blocks.body);
    assert.deepEqual(blocks.json().blocks, [{socialId: targetSocialId, handle: null,
      revision: 2, updatedAt: instant}]);
    assert.equal(blocks.body.includes('blocked'), false);
    assert.equal(blocks.body.includes(userId), false);

    const wrongKind = await app.inject(`/v1/social/blocks?cursor=${friendCursor}`);
    assert.equal(wrongKind.statusCode, 400);
    s.setPrincipal(otherPrincipal);
    const rebound = await app.inject(`/v1/social/friends?cursor=${friendCursor}`);
    assert.equal(rebound.statusCode, 400);
  } finally { await app.close(); }
});

test('remove, block and report stay available while relationship activation is disabled', async () => {
  const s = setup();
  const app = buildApp({logger: false, relationshipSafetyEnabled: false,
    socialRelationships: s.adapters});
  try {
    const removed = await app.inject({method: 'POST',
      url: `/v1/social/friends/${friendshipId}/actions`, payload: {
        schemaVersion: 1, action: 'remove', mutationId, expectedRevision: 1,
      }});
    assert.equal(removed.statusCode, 200, removed.body);
    assert.deepEqual(removed.json(), {schemaVersion: 1, mutationId, friendshipId,
      appliedRevision: 2, state: 'removed', occurredAt: instant});

    const blocked = await app.inject({method: 'PUT', url: `/v1/social/blocks/${targetSocialId}`,
      payload: {schemaVersion: 1, mutationId, baseRevision: 2, blocked: false}});
    assert.equal(blocked.statusCode, 200, blocked.body);
    assert.deepEqual(blocked.json(), {schemaVersion: 1, mutationId, appliedRevision: 3,
      block: {socialId: targetSocialId, revision: 4, blocked: false, updatedAt: instant}});

    const snapshot = await app.inject(`/v1/social/blocks/${targetSocialId}`);
    assert.equal(snapshot.statusCode, 200, snapshot.body);
    assert.deepEqual(snapshot.json(), {schemaVersion: 1,
      block: {socialId: targetSocialId, revision: 0, blocked: false, updatedAt: null}});

    const reported = await app.inject({method: 'POST', url: '/v1/social/reason-reports',
      payload: {schemaVersion: 1, mutationId, reasonId, category: 'harassment'}});
    assert.equal(reported.statusCode, 202, reported.body);
    assert.deepEqual(reported.json(), {schemaVersion: 1,
      report: {reportId, reasonId, category: 'harassment', receivedAt: instant}});
    s.adapters.repository.reportReason = async (_user, command) => ({created: false,
      report: {reportId, reasonId: command.reasonId, category: 'spam', receivedAt: instant}});
    const replay = await app.inject({method: 'POST', url: '/v1/social/reason-reports',
      payload: {schemaVersion: 1, mutationId, reasonId, category: 'harassment'}});
    assert.equal(replay.statusCode, 200, replay.body);
    assert.equal(replay.json().report.category, 'spam');
    for (const response of [removed, blocked, snapshot, reported, replay]) {
      assert.equal(response.headers['cache-control'], 'no-store');
    }
    assert.equal(s.calls.mutations.length, 3);
  } finally { await app.close(); }
});

test('strict bodies reject old, extra and malformed request shapes before storage', async () => {
  const s = setup();
  const app = buildApp({logger: false, socialRelationships: s.adapters});
  try {
    const invalidRequests = [
      {method: 'POST', url: `/v1/social/friends/${friendshipId}/actions`, payload: {
        schemaVersion: 1, action: 'remove', mutationId, expectedRevision: 1, subject: '123'},
      },
      {method: 'PUT', url: `/v1/social/blocks/${targetSocialId}`, payload: {
        schemaVersion: 1, mutationId, baseRevision: -1, blocked: true},
      },
      {method: 'POST', url: '/v1/social/reason-reports', payload: {
        schemaVersion: 2, mutationId, reasonId, category: 'legal'},
      },
    ] as const;
    for (const request of invalidRequests) {
      const response = await app.inject(request);
      assert.equal(response.statusCode, 400, response.body);
      assert.equal(response.headers['cache-control'], 'no-store');
    }
    assert.equal(s.calls.mutations.length, 0);
  } finally { await app.close(); }
});

test('widened adapter output is rejected before private fields can cross HTTP', async () => {
  const s = setup();
  s.adapters.repository.getBlock = async (_user, id) => ({
    socialId: id, revision: 0, blocked: false, updatedAt: null,
    internalUserId: userId,
  } as never);
  const app = buildApp({logger: false, socialRelationships: s.adapters});
  try {
    const response = await app.inject(`/v1/social/blocks/${targetSocialId}`);
    assert.equal(response.statusCode, 500, response.body);
    assert.equal(response.json().error.code, 'SOCIAL_STORAGE_INVALID');
    assert.equal(response.body.includes(userId), false);
  } finally { await app.close(); }
});

test('authentication, adapter and database outcomes keep stable no-store errors', async () => {
  const missing = setup();
  missing.setAuthenticated(false);
  const noAuth = buildApp({logger: false, socialRelationships: missing.adapters});
  const offline = buildApp({logger: false});
  const limited = setup();
  limited.adapters.repository.removeFriend = async () => {
    throw new SocialRelationshipError('SOCIAL_RATE_LIMITED', 'limited', 17);
  };
  const limitedApp = buildApp({logger: false, socialRelationships: limited.adapters});
  const hidden = setup();
  hidden.adapters.repository.getBlock = async () => {
    throw new SocialRelationshipError('SOCIAL_RELATIONSHIP_NOT_FOUND', 'private detail');
  };
  const hiddenApp = buildApp({logger: false, socialRelationships: hidden.adapters});
  try {
    const unauthorized = await noAuth.inject('/v1/social/friends');
    assert.equal(unauthorized.statusCode, 401);
    assert.equal(unauthorized.headers['cache-control'], 'no-store');
    const unavailable = await offline.inject('/v1/social/blocks');
    assert.equal(unavailable.statusCode, 503);
    assert.equal(unavailable.headers['cache-control'], 'no-store');
    const response = await limitedApp.inject({method: 'POST',
      url: `/v1/social/friends/${friendshipId}/actions`, payload: {
        schemaVersion: 1, action: 'remove', mutationId, expectedRevision: 1,
      }});
    assert.equal(response.statusCode, 429);
    assert.equal(response.headers['retry-after'], '17');
    assert.equal(response.json().error.code, 'SOCIAL_RATE_LIMITED');
    const unavailableTarget = await hiddenApp.inject(`/v1/social/blocks/${targetSocialId}`);
    assert.equal(unavailableTarget.statusCode, 404);
    assert.equal(unavailableTarget.json().error.code, 'SOCIAL_RELATIONSHIP_NOT_FOUND');
    assert.equal(unavailableTarget.body.includes('private detail'), false);
  } finally {
    await Promise.all([noAuth.close(), offline.close(), limitedApp.close(), hiddenApp.close()]);
  }
});
