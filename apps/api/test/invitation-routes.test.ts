import assert from 'node:assert/strict';
import {test} from 'node:test';
import {buildApp} from '../src/app.js';
import {
  INVITATIONS_ROUTE,
  INVITATION_ACTION_ROUTE,
} from '../src/invitation-routes.js';
import type {InvitationsRepository} from '../src/invitations-repository.js';

const userId = '9f000000-0000-4000-8000-000000000001';
const invitationId = '11111111-1111-4111-8111-111111111111';

test('legacy direct-table invitation adapters are never route authority', async () => {
  const calls: string[] = [];
  const repository: InvitationsRepository = {
    list: async () => { calls.push('list'); return []; },
    create: async () => { calls.push('create'); throw new Error('must not run'); },
    apply: async () => { calls.push('apply'); throw new Error('must not run'); },
  };
  const app = buildApp({logger: false, relationshipSafetyEnabled: true, invitations: {
    repository,
    authenticate: async () => ({userId}),
    newId: () => invitationId,
  }});
  try {
    assert.equal((await app.inject('/v1/config')).json().invitationsEnabled, false);
    for (const request of [
      {method: 'GET' as const, url: INVITATIONS_ROUTE},
      {method: 'POST' as const, url: INVITATIONS_ROUTE,
        payload: {schemaVersion: 1, expiresAt: '2026-10-01T00:00:00.000Z'}},
      {method: 'POST' as const, url: `/v1/invitations/${invitationId}/actions`,
        payload: {schemaVersion: 1, action: 'cancel', expectedVersion: 0}},
    ]) {
      const response = await app.inject(request);
      assert.equal(response.statusCode, 503, response.body);
      assert.equal(response.json().error.code, 'INVITATION_UNAVAILABLE');
      assert.equal(response.headers['cache-control'], 'no-store');
    }
    assert.deepEqual(calls, []);
  } finally { await app.close(); }
});

test('invitation routes remain registered at the documented paths', () => {
  assert.equal(INVITATIONS_ROUTE, '/v1/invitations');
  assert.equal(INVITATION_ACTION_ROUTE, '/v1/invitations/:invitationId/actions');
});
