import assert from 'node:assert/strict';
import {test} from 'node:test';
import {buildApp} from '../src/app.js';
import type {InvitationAdapters} from '../src/invitation-routes.js';
import {PrivyLinkedIdentityError} from '../src/privy-linked-identities.js';
import type {PrivyLinkedIdentityResolution} from '../src/privy-linked-identities.js';
import {InvitationRepositoryError} from '../src/invitations-repository.js';
import type {
  InvitationCommand,
  InvitationCreate,
  InvitationRecord,
  InvitationsRepository,
  InvitationsV2Repository,
  InvitationV2AnswerCommand,
  InvitationV2Create,
  InvitationV2ListInput,
  InvitationV2Record,
  InvitationV2SenderCommand,
} from '../src/invitations-repository.js';

const userId = '9f000000-0000-4000-8000-000000000001';
const invitationId = '11111111-1111-4111-8111-111111111111';
const mutationId = '22222222-2222-4222-8222-222222222222';
const socialId = '33333333-3333-4333-8333-333333333333';
const otherSocialId = '44444444-4444-4444-8444-444444444444';
const expiresAt = '2026-10-01T10:00:00.000Z';
const createdAt = '2026-09-20T10:00:00.000Z';
const privySubject = 'did:privy:invitationv2test';
const xSubject = '18446744073709551615';
const identity = {provider: 'privy' as const, appId: 'trimmy_test', subject: privySubject};

function v2Record(overrides: Partial<InvitationV2Record> = {}): InvitationV2Record {
  return Object.freeze({
    id: invitationId,
    state: 'offered',
    funding: 'unfunded',
    sender: Object.freeze({
      socialId,
      handle: 'mira_trade',
      persona: 'oracle',
      rank: Object.freeze({id: 'rookie', label: 'Rookie'}),
    }),
    recipient: Object.freeze({provider: 'x', handleSnapshot: 'ada_builds'}),
    expiresAt,
    createdAt,
    acceptedAt: null,
    version: 2,
    role: 'recipient',
    ...overrides,
  });
}

function linked(status: 'verified' | 'missing' | 'ambiguous' = 'verified'): PrivyLinkedIdentityResolution {
  return Object.freeze({
    provider: 'privy',
    subject: privySubject,
    twitter: status === 'verified'
      ? Object.freeze({status, subject: xSubject, usernameSnapshot: 'ada_builds', verifiedAtUnixSeconds: 1_758_369_600})
      : Object.freeze({status}),
    embeddedSolanaWallet: Object.freeze({status: 'missing'}),
  });
}

interface Calls {
  lists: InvitationV2ListInput[];
  creates: InvitationV2Create[];
  sender: InvitationV2SenderCommand[];
  answers: InvitationV2AnswerCommand[];
  resolved: number;
  fresh: number;
  lookedUp: string[];
}

function adapters(options: Readonly<{
  resolution?: PrivyLinkedIdentityResolution;
  resolveError?: Error;
  answerError?: InvitationRepositoryError;
  principalSocialId?: string;
  hasMore?: boolean;
}> = {}): {value: InvitationAdapters; calls: Calls} {
  const calls: Calls = {lists: [], creates: [], sender: [], answers: [], resolved: 0, fresh: 0, lookedUp: []};
  const legacy: InvitationsRepository = {
    list: async () => [],
    create: async (_userId: string, _input: InvitationCreate): Promise<InvitationRecord> => {
      throw new Error('legacy create must not run');
    },
    apply: async (_userId: string, _id: string, _command: InvitationCommand): Promise<InvitationRecord> => {
      throw new Error('legacy apply must not run');
    },
  };
  const v2: InvitationsV2Repository = {
    listV2: async (_userId, input) => {
      calls.lists.push(input);
      return Object.freeze({
        principalSocialId: options.principalSocialId ?? socialId,
        invitations: Object.freeze([v2Record()]),
        hasMore: options.hasMore ?? false,
        incomingInvitations: input.freshXSubject === null ? 'x_link_required' : 'available',
      });
    },
    createV2: async (_userId, input) => {
      calls.creates.push(input);
      return Object.freeze({invitation: v2Record({state: 'draft', recipient: null, version: 0, role: 'sender'}), created: true});
    },
    senderActionV2: async (_userId, _id, command) => {
      calls.sender.push(command);
      return v2Record({state: command.action === 'address' ? 'addressed' : command.action === 'cancel' ? 'canceled' : 'offered'});
    },
    answerV2: async (_userId, _id, command) => {
      calls.answers.push(command);
      if (options.answerError) throw options.answerError;
      return v2Record({
        state: command.action === 'accept' ? 'accepted' : 'declined',
        acceptedAt: command.action === 'accept' ? '2026-09-20T10:01:00.000Z' : null,
        version: 3,
      });
    },
  };
  const value: InvitationAdapters = {
    repository: Object.assign(legacy, v2),
    authenticate: async () => ({userId}),
    authenticateContext: async () => ({userId, identity}),
    newId: () => mutationId,
    linkedIdentities: {
      resolve: async () => {
        calls.resolved++;
        if (options.resolveError) throw options.resolveError;
        return options.resolution ?? linked();
      },
      resolveFresh: async () => {
        calls.fresh++;
        if (options.resolveError) throw options.resolveError;
        return options.resolution ?? linked();
      },
    },
    xProfiles: {lookup: async handle => {
      calls.lookedUp.push(handle);
      return Object.freeze({provider: 'x', id: '987654321', username: handle,
        name: 'Ada', lookedUpAt: createdAt, ownershipVerified: false});
    }},
    xLookupBudget: {run: async (_user, operation) => operation()},
  };
  return {value, calls};
}

test('partial v2 composition fails closed instead of restoring legacy authority', async () => {
  let legacyReads = 0;
  const legacy: InvitationsRepository = {
    list: async () => { legacyReads++; return []; },
    create: async () => { throw new Error('legacy create must not run'); },
    apply: async () => { throw new Error('legacy apply must not run'); },
  };
  const partial = Object.assign(legacy, {listV2: async () => { throw new Error('partial v2 must not run'); }});
  const app = buildApp({logger: false, relationshipSafetyEnabled: true, invitations: {
    repository: partial,
    authenticate: async () => ({userId}),
    newId: () => mutationId,
  }});
  try {
    const config = await app.inject('/v1/config');
    assert.equal(config.json().invitationsEnabled, false);
    const response = await app.inject('/v1/invitations');
    assert.equal(response.statusCode, 503);
    assert.equal(response.headers['cache-control'], 'no-store');
    assert.equal(legacyReads, 0);
  } finally { await app.close(); }
});

test('relationship kill switch blocks activation but preserves reads, decline and cancel', async () => {
  const setup = adapters();
  const app = buildApp({logger: false, invitations: setup.value});
  try {
    const config = await app.inject('/v1/config');
    assert.equal(config.json().relationshipSafetyEnabled, false);
    assert.equal(config.json().invitationsEnabled, true);
    assert.equal((await app.inject('/v1/invitations')).statusCode, 200);

    const create = await app.inject({method: 'POST', url: '/v1/invitations', payload: {
      schemaVersion: 2, mutationId, expiresAt,
    }});
    assert.equal(create.statusCode, 503, create.body);
    for (const [action, body] of [
      ['address', {schemaVersion: 2, action: 'address', expectedVersion: 0, xHandle: 'ada_builds'}],
      ['offer', {schemaVersion: 2, action: 'offer', expectedVersion: 1}],
      ['accept', {schemaVersion: 2, action: 'accept', expectedVersion: 2}],
    ] as const) {
      const response = await app.inject({method: 'POST',
        url: `/v1/invitations/${invitationId}/actions`, payload: body});
      assert.equal(response.statusCode, 503, action);
    }
    for (const [action, version] of [['decline', 2], ['cancel', 1]] as const) {
      const response = await app.inject({method: 'POST',
        url: `/v1/invitations/${invitationId}/actions`,
        payload: {schemaVersion: 2, action, expectedVersion: version}});
      assert.equal(response.statusCode, 200, response.body);
    }
    assert.equal(setup.calls.creates.length, 0);
    assert.equal(setup.calls.lookedUp.length, 0);
    assert.deepEqual(setup.calls.answers.map(call => call.action), ['decline']);
    assert.deepEqual(setup.calls.sender.map(call => call.action), ['cancel']);
  } finally { await app.close(); }
});

test('v2 create keeps mutation identity and returns a subject-free public invitation', async () => {
  const setup = adapters();
  const app = buildApp({logger: false, relationshipSafetyEnabled: true,
    relationshipSafetyReadiness: async () => true, invitations: setup.value});
  try {
    assert.equal((await app.inject('/v1/config')).json().relationshipSafetyEnabled, true);
    const response = await app.inject({method: 'POST', url: '/v1/invitations', payload: {
      schemaVersion: 2, mutationId, expiresAt,
    }});
    assert.equal(response.statusCode, 201, response.body);
    assert.equal(response.headers['cache-control'], 'no-store');
    assert.deepEqual(setup.calls.creates, [{mutationId, expiresAt}]);
    assert.equal(response.json().schemaVersion, 2);
    assert.equal(response.json().sender.socialId, socialId);
    for (const forbidden of [xSubject, privySubject, userId, 'subject', 'senderUserId']) {
      assert.equal(response.body.includes(forbidden), false, forbidden);
    }
    const legacy = await app.inject({method: 'POST', url: '/v1/invitations', payload: {
      schemaVersion: 1, expiresAt,
    }});
    assert.equal(legacy.statusCode, 400, legacy.body);
    assert.equal(setup.calls.creates.length, 1);
  } finally { await app.close(); }
});

test('addressing accepts only a handle and the server resolves its numeric subject', async () => {
  const setup = adapters();
  const app = buildApp({logger: false, relationshipSafetyEnabled: true,
    relationshipSafetyReadiness: async () => true, invitations: setup.value});
  try {
    const response = await app.inject({method: 'POST', url: `/v1/invitations/${invitationId}/actions`, payload: {
      schemaVersion: 2, action: 'address', expectedVersion: 0, xHandle: 'ada_builds',
    }});
    assert.equal(response.statusCode, 200, response.body);
    assert.deepEqual(setup.calls.lookedUp, ['ada_builds']);
    assert.deepEqual(setup.calls.sender, [{
      action: 'address', expectedVersion: 0,
      recipient: {subject: '987654321', handleSnapshot: 'ada_builds'},
    }]);
    assert.equal(response.body.includes('987654321'), false);
    const smuggled = await app.inject({method: 'POST', url: `/v1/invitations/${invitationId}/actions`, payload: {
      schemaVersion: 2, action: 'address', expectedVersion: 0, xHandle: 'ada_builds', subject: xSubject,
    }});
    assert.equal(smuggled.statusCode, 400);
  } finally { await app.close(); }
});

test('staged v1 address ignores the supplied subject and resolves the handle again', async () => {
  const setup = adapters();
  const app = buildApp({logger: false, relationshipSafetyEnabled: true,
    relationshipSafetyReadiness: async () => true, invitations: setup.value});
  try {
    const response = await app.inject({method: 'POST', url: `/v1/invitations/${invitationId}/actions`, payload: {
      schemaVersion: 1,
      action: 'address',
      expectedVersion: 0,
      recipient: {provider: 'x', subject: '123', handleSnapshot: 'ada_builds'},
    }});
    assert.equal(response.statusCode, 200, response.body);
    assert.equal(setup.calls.sender[0]?.recipient?.subject, '987654321');
    assert.equal(response.json().schemaVersion, 2);
    assert.equal(response.body.includes('987654321'), false);
    assert.equal(response.body.includes('"123"'), false);
  } finally { await app.close(); }
});

test('accept and decline each require a fresh verified Privy X projection', async () => {
  const setup = adapters();
  const app = buildApp({logger: false, relationshipSafetyEnabled: true,
    relationshipSafetyReadiness: async () => true, invitations: setup.value});
  try {
    for (const action of ['accept', 'decline'] as const) {
      const response = await app.inject({method: 'POST', url: `/v1/invitations/${invitationId}/actions`, payload: {
        schemaVersion: 2, action, expectedVersion: 2,
      }});
      assert.equal(response.statusCode, 200, response.body);
      assert.equal(response.body.includes(xSubject), false);
    }
    assert.equal(setup.calls.fresh, 2);
    assert.equal(setup.calls.resolved, 0);
    assert.deepEqual(setup.calls.answers.map(call => call.action), ['accept', 'decline']);
    assert.deepEqual(setup.calls.answers[0]?.identity, {
      subject: xSubject,
      handleSnapshot: 'ada_builds',
      verifiedAt: '2025-09-20T12:00:00.000Z',
    });
    const smuggled = await app.inject({method: 'POST', url: `/v1/invitations/${invitationId}/actions`, payload: {
      schemaVersion: 2, action: 'accept', expectedVersion: 2, subject: xSubject,
    }});
    assert.equal(smuggled.statusCode, 400);
    assert.equal(setup.calls.fresh, 2);
  } finally { await app.close(); }
});

test('missing and ambiguous X links cannot answer and require linking for incoming lists', async () => {
  for (const status of ['missing', 'ambiguous'] as const) {
    const answerSetup = adapters({resolution: linked(status)});
    const answerApp = buildApp({logger: false, relationshipSafetyEnabled: true,
      relationshipSafetyReadiness: async () => true, invitations: answerSetup.value});
    try {
      const response = await answerApp.inject({method: 'POST', url: `/v1/invitations/${invitationId}/actions`, payload: {
        schemaVersion: 2, action: 'accept', expectedVersion: 2,
      }});
      assert.equal(response.statusCode, 409, response.body);
      assert.equal(response.json().error.code, 'SOCIAL_IDENTITY_UNAVAILABLE');
      assert.equal(answerSetup.calls.answers.length, 0);
      const list = await answerApp.inject('/v1/invitations?box=open');
      assert.equal(list.statusCode, 200, list.body);
      assert.equal(list.json().incomingInvitations, 'x_link_required');
      assert.equal(answerSetup.calls.lists[0]?.freshXSubject, null);
    } finally { await answerApp.close(); }
  }
});

test('provider failures and durable identity conflicts keep distinct bounded errors', async () => {
  const providerSetup = adapters({resolveError: new PrivyLinkedIdentityError('PRIVY_USER_UNAVAILABLE')});
  const providerApp = buildApp({logger: false, relationshipSafetyEnabled: true,
    relationshipSafetyReadiness: async () => true, invitations: providerSetup.value});
  try {
    const response = await providerApp.inject('/v1/invitations');
    assert.equal(response.statusCode, 502, response.body);
    assert.equal(response.headers['cache-control'], 'no-store');
    assert.equal(response.json().error.code, 'PRIVY_USER_UNAVAILABLE');
  } finally { await providerApp.close(); }

  const conflictSetup = adapters({answerError: new InvitationRepositoryError(
    'SOCIAL_IDENTITY_CONFLICT', 'private database detail',
  )});
  const conflictApp = buildApp({logger: false, relationshipSafetyEnabled: true,
    relationshipSafetyReadiness: async () => true, invitations: conflictSetup.value});
  try {
    const response = await conflictApp.inject({method: 'POST', url: `/v1/invitations/${invitationId}/actions`, payload: {
      schemaVersion: 2, action: 'decline', expectedVersion: 2,
    }});
    assert.equal(response.statusCode, 409, response.body);
    assert.equal(response.json().error.code, 'SOCIAL_IDENTITY_CONFLICT');
    assert.equal(response.body.includes('private database detail'), false);
  } finally { await conflictApp.close(); }
});

test('bounded cursors bind list kind, box and current public principal', async () => {
  const firstSetup = adapters({hasMore: true});
  const firstApp = buildApp({logger: false, relationshipSafetyEnabled: true,
    relationshipSafetyReadiness: async () => true, invitations: firstSetup.value});
  let cursor: string;
  try {
    const first = await firstApp.inject('/v1/invitations?box=open&limit=1');
    assert.equal(first.statusCode, 200, first.body);
    cursor = first.json().nextCursor as string;
    assert.match(cursor, /^[A-Za-z0-9_-]+$/);
    const wrongBox = await firstApp.inject(`/v1/invitations?box=history&limit=1&cursor=${cursor}`);
    assert.equal(wrongBox.statusCode, 400);
    const decoded = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8')) as unknown[];
    const noncanonical = Buffer.from(JSON.stringify(decoded, null, 1), 'utf8').toString('base64url');
    const widened = await firstApp.inject(`/v1/invitations?box=open&limit=1&cursor=${noncanonical}`);
    assert.equal(widened.statusCode, 400);
  } finally { await firstApp.close(); }

  const otherSetup = adapters({principalSocialId: otherSocialId});
  const otherApp = buildApp({logger: false, relationshipSafetyEnabled: true,
    relationshipSafetyReadiness: async () => true, invitations: otherSetup.value});
  try {
    const crossed = await otherApp.inject(`/v1/invitations?box=open&limit=1&cursor=${cursor!}`);
    assert.equal(crossed.statusCode, 400, crossed.body);
    assert.equal(crossed.json().error.code, 'INVITATION_INVALID_INPUT');
  } finally { await otherApp.close(); }
});
