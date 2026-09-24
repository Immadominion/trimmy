import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {after, before, describe, test} from 'node:test';
import {Pool} from 'pg';
import {buildApp} from '../../src/app.js';
import {PostgresInvitationsRepository} from '../../src/postgres-invitations-repository.js';
import {PostgresSocialRelationshipsRepository} from '../../src/postgres-social-relationships-repository.js';
import type {PracticeIdentity} from '../../src/practice-identity.js';
import type {PrivyLinkedIdentityResolution} from '../../src/privy-linked-identities.js';

const socket = process.env['TRIMMY_PRACTICE_TEST_SOCKET'];
assert.ok(socket?.endsWith('/infra/.practice-runtime/socket'), 'Use the private test runner; never attach to an external database.');
assert.equal(process.env['TRIMMY_PRACTICE_TEST_PORT'], '65438');
const pool = new Pool({
  host: socket, port: 65438, database: 'postgres', user: 'trimmy_invitation_test_app',
  connectionTimeoutMillis: 3000, max: 4,
});

type Who = 'sender' | 'guest' | 'outsider';
interface TestAccount {
  readonly userId: string;
  readonly identity: PracticeIdentity;
  readonly x: Readonly<{subject: string; handleSnapshot: string}>;
}

// Seeded by the practice, invitation and relationship integration fixtures.
const accounts: Readonly<Record<Who, TestAccount>> = Object.freeze({
  sender: Object.freeze({
    userId: '00000000-0000-4000-8000-000000000001',
    identity: Object.freeze({provider: 'privy', appId: 'invitation-test-app', subject: 'did:privy:sender'}),
    x: Object.freeze({subject: '1001', handleSnapshot: 'sender_one'}),
  }),
  guest: Object.freeze({
    userId: '00000000-0000-4000-8000-000000000002',
    identity: Object.freeze({provider: 'privy', appId: 'invitation-test-app', subject: 'did:privy:guest'}),
    x: Object.freeze({subject: '1002', handleSnapshot: 'guest_two'}),
  }),
  outsider: Object.freeze({
    userId: '00000000-0000-4000-8000-000000000003',
    identity: Object.freeze({provider: 'privy', appId: 'invitation-test-app', subject: 'did:privy:outsider'}),
    x: Object.freeze({subject: '1003', handleSnapshot: 'other_three'}),
  }),
});
const accountByBearer = new Map<string, TestAccount>(Object.entries(accounts).map(([who, account]) =>
  [`Bearer ${who}`, account] as const));

function linked(account: TestAccount): PrivyLinkedIdentityResolution {
  return Object.freeze({
    provider: 'privy',
    subject: account.identity.subject,
    twitter: Object.freeze({
      status: 'verified',
      subject: account.x.subject,
      usernameSnapshot: account.x.handleSnapshot,
      verifiedAtUnixSeconds: Date.parse('2026-09-16T09:00:00.000Z') / 1000,
    }),
    embeddedSolanaWallet: Object.freeze({status: 'missing'}),
  });
}

function accountForIdentity(identity: PracticeIdentity): TestAccount {
  const account = Object.values(accounts).find(candidate =>
    candidate.identity.appId === identity.appId && candidate.identity.subject === identity.subject);
  assert.ok(account, `Unknown fixture identity: ${identity.subject}`);
  return account;
}

const repository = new PostgresInvitationsRepository(pool);
const relationships = new PostgresSocialRelationshipsRepository(pool);
const app = buildApp({
  logger: false,
  relationshipSafetyEnabled: true,
  relationshipSafetyReadiness: async () => true,
  invitations: {
    repository,
    authenticateContext: async request => {
      const account = accountByBearer.get(request.headers.authorization ?? '');
      return account ? {userId: account.userId, identity: account.identity} : null;
    },
    linkedIdentities: {
      resolve: async identity => linked(accountForIdentity(identity)),
      resolveFresh: async identity => linked(accountForIdentity(identity)),
    },
    xProfiles: {lookup: async handle => {
      const account = Object.values(accounts).find(candidate => candidate.x.handleSnapshot === handle.toLowerCase());
      assert.ok(account, `Unknown fixture X handle: ${handle}`);
      return Object.freeze({
        provider: 'x' as const,
        id: account.x.subject,
        username: account.x.handleSnapshot,
        name: account.x.handleSnapshot,
        lookedUpAt: '2026-09-20T12:00:00.000Z',
        ownershipVerified: false as const,
      });
    }},
    xLookupBudget: {run: async (_userId, operation) => operation()},
  },
});

const auth = (who: Who) => ({authorization: `Bearer ${who}`});
const list = (who: Who, box: 'open' | 'history' = 'open') =>
  app.inject({url: `/v1/invitations?box=${box}`, headers: auth(who)});
const create = (who: Who, expiresAt: string) => app.inject({
  method: 'POST', url: '/v1/invitations', headers: auth(who),
  payload: {schemaVersion: 2, mutationId: randomUUID(), expiresAt},
});
const act = (who: Who, id: string, action: string, expectedVersion: number, xHandle?: string) =>
  app.inject({
    method: 'POST', url: `/v1/invitations/${id}/actions`, headers: auth(who),
    payload: {
      schemaVersion: 2, action, expectedVersion,
      ...(xHandle === undefined ? {} : {xHandle}),
    },
  });

function future(minutes: number): string {
  return new Date(Date.now() + minutes * 60_000).toISOString().replace(/\.\d{3}Z$/, '.000Z');
}

/** Drive a fresh invitation to the requested state and return its id. */
async function invitationAt(state: 'draft' | 'addressed' | 'offered'): Promise<string> {
  const created = await create('sender', future(60));
  assert.equal(created.statusCode, 201, created.body);
  const id = created.json().id as string;
  if (state === 'draft') return id;
  const addressed = await act('sender', id, 'address', 0, accounts.guest.x.handleSnapshot);
  assert.equal(addressed.statusCode, 200, addressed.body);
  if (state === 'addressed') return id;
  const offered = await act('sender', id, 'offer', 1);
  assert.equal(offered.statusCode, 200, offered.body);
  return id;
}

async function removeAcceptedFriendship(): Promise<void> {
  const page = await relationships.listFriends(accounts.sender.userId, {limit: 20, cursor: null});
  assert.equal(page.friends.length, 1);
  const friendship = page.friends[0]!;
  const removed = await relationships.removeFriend(accounts.sender.userId, friendship.friendshipId, {
    mutationId: randomUUID(), expectedRevision: friendship.revision,
  });
  assert.equal(removed.state, 'removed');
}

before(async () => { await app.ready(); });
after(async () => { await app.close(); await pool.end(); });

describe('0025 unfunded invitation HTTP and PostgreSQL integration', () => {
  test('a sender drives the whole v2 path and the freshly proved recipient accepts it', async () => {
    const created = await create('sender', future(60));
    assert.equal(created.statusCode, 201, created.body);
    const draft = created.json();
    assert.equal(draft.schemaVersion, 2);
    assert.equal(draft.state, 'draft');
    assert.equal(draft.funding, 'unfunded');
    assert.equal(draft.recipient, null);
    assert.equal(draft.version, 0);
    assert.equal(draft.role, 'sender');
    const id = draft.id as string;

    assert.ok((await list('sender')).json().invitations.some((row: {id: string}) => row.id === id));
    assert.equal((await list('guest')).json().invitations.some((row: {id: string}) => row.id === id), false);

    const addressed = await act('sender', id, 'address', 0, accounts.guest.x.handleSnapshot);
    assert.equal(addressed.statusCode, 200, addressed.body);
    assert.equal(addressed.json().state, 'addressed');
    assert.equal(addressed.json().version, 1);
    assert.deepEqual(addressed.json().recipient,
      {provider: 'x', handleSnapshot: accounts.guest.x.handleSnapshot});
    assert.equal(addressed.body.includes(accounts.guest.x.subject), false);
    assert.equal((await list('guest')).json().invitations.some((row: {id: string}) => row.id === id), false);

    const offered = await act('sender', id, 'offer', 1);
    assert.equal(offered.statusCode, 200, offered.body);
    assert.equal(offered.json().state, 'offered');
    const guestView = (await list('guest')).json().invitations.find((row: {id: string}) => row.id === id);
    assert.ok(guestView, 'the freshly proved recipient must see the offered invitation');
    assert.equal(guestView.role, 'recipient');
    assert.equal((await list('outsider')).json().invitations.some((row: {id: string}) => row.id === id), false);

    const accepted = await act('guest', id, 'accept', 2);
    assert.equal(accepted.statusCode, 200, accepted.body);
    assert.equal(accepted.json().state, 'accepted');
    assert.equal(accepted.json().version, 3);
    assert.match(accepted.json().acceptedAt, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);

    const friends = await relationships.listFriends(accounts.sender.userId, {limit: 20, cursor: null});
    assert.equal(friends.friends.length, 1,
      'committing acceptance must satisfy the deferred event pair and expose one active friendship');
    assert.equal(friends.friends[0]?.person.handle, accounts.guest.x.handleSnapshot);

    // End the committed friendship through the same production function
    // boundary so every later test starts with a relationship-free pair.
    await removeAcceptedFriendship();

    for (const [who, action, version] of [['sender', 'cancel', 3], ['guest', 'decline', 3]] as const) {
      const afterTerminal = await act(who, id, action, version);
      assert.equal(afterTerminal.statusCode, 409, afterTerminal.body);
      assert.equal(afterTerminal.json().error.code, 'INVITATION_VERSION_CONFLICT');
    }
  });

  test('sender-only actions do not disclose a pre-offer invitation to another account', async () => {
    const addressed = await invitationAt('addressed');
    const guestOffer = await act('guest', addressed, 'offer', 1);
    assert.equal(guestOffer.statusCode, 404, guestOffer.body);
    assert.equal(guestOffer.json().error.code, 'INVITATION_NOT_FOUND');
    const guestCancel = await act('guest', addressed, 'cancel', 1);
    assert.equal(guestCancel.statusCode, 404, guestCancel.body);
    assert.equal(guestCancel.json().error.code, 'INVITATION_NOT_FOUND');
    const redirect = await act('guest', addressed, 'address', 1, accounts.outsider.x.handleSnapshot);
    assert.equal(redirect.statusCode, 404, redirect.body);
    assert.equal(redirect.json().error.code, 'INVITATION_NOT_FOUND');
    assert.equal((await act('sender', addressed, 'cancel', 1)).statusCode, 200);
  });

  test('only the freshly proved recipient may answer, and never before offer', async () => {
    const early = await invitationAt('addressed');
    const tooEarly = await act('guest', early, 'accept', 1);
    assert.equal(tooEarly.statusCode, 409, tooEarly.body);
    assert.equal(tooEarly.json().error.code, 'INVITATION_VERSION_CONFLICT');
    assert.equal((await act('sender', early, 'cancel', 1)).statusCode, 200);

    const offered = await invitationAt('offered');
    const selfAccept = await act('sender', offered, 'accept', 2);
    assert.equal(selfAccept.statusCode, 404, selfAccept.body);
    assert.equal(selfAccept.json().error.code, 'INVITATION_NOT_FOUND');
    const outsider = await act('outsider', offered, 'accept', 2);
    assert.equal(outsider.statusCode, 404, outsider.body);
    assert.equal(outsider.json().error.code, 'INVITATION_NOT_FOUND');
    const declined = await act('guest', offered, 'decline', 2);
    assert.equal(declined.statusCode, 200, declined.body);
    assert.equal(declined.json().state, 'declined');
    assert.equal(declined.json().acceptedAt, null);
  });

  test('a stale version is refused so a concurrent change is never overwritten', async () => {
    const id = await invitationAt('addressed');
    const stale = await act('sender', id, 'offer', 0);
    assert.equal(stale.statusCode, 409, stale.body);
    assert.equal(stale.json().error.code, 'INVITATION_VERSION_CONFLICT');
    const ahead = await act('sender', id, 'offer', 5);
    assert.equal(ahead.statusCode, 409, ahead.body);
    assert.equal((await act('sender', id, 'offer', 1)).statusCode, 200);
    assert.equal((await act('sender', id, 'cancel', 2)).statusCode, 200);
  });

  test('a draft can be cancelled and an unknown identifier is unavailable', async () => {
    const draft = await invitationAt('draft');
    const canceled = await act('sender', draft, 'cancel', 0);
    assert.equal(canceled.statusCode, 200, canceled.body);
    assert.equal(canceled.json().state, 'canceled');
    const missing = await act('sender', randomUUID(), 'offer', 0);
    assert.equal(missing.statusCode, 404, missing.body);
    assert.equal(missing.json().error.code, 'INVITATION_NOT_FOUND');
  });

  test('invalid invitation windows are rejected by the receipt-first database boundary', async () => {
    const past = await create('guest', '2020-01-01T00:00:00.000Z');
    assert.equal(past.statusCode, 400, past.body);
    assert.equal(past.json().error.code, 'INVITATION_INVALID_INPUT');
    const tooFar = await create('guest', future(60 * 24 * 365));
    assert.equal(tooFar.statusCode, 400, tooFar.body);
  });

  test('a passed invitation settles itself to expired and stops holding the quota', async () => {
    const soon = new Date(Date.now() + 1200).toISOString().replace(/\.\d{3}Z$/, '.000Z');
    const created = await create('sender', soon);
    assert.equal(created.statusCode, 201, created.body);
    const id = created.json().id as string;
    assert.equal((await act('sender', id, 'address', 0, accounts.guest.x.handleSnapshot)).statusCode, 200);
    assert.equal((await act('sender', id, 'offer', 1)).statusCode, 200);
    await new Promise(resolvePromise => setTimeout(resolvePromise, 1600));

    const listed = (await list('sender', 'history')).json().invitations.find((row: {id: string}) => row.id === id);
    assert.ok(listed, 'the sender still sees the expired invitation in history');
    assert.equal(listed.state, 'expired');
    const guestView = (await list('guest', 'history')).json().invitations.find((row: {id: string}) => row.id === id);
    assert.equal(guestView, undefined,
      'an unresolved external offer does not become durable recipient history');
    const late = await act('guest', id, 'accept', listed.version);
    assert.equal(late.statusCode, 409, late.body);
    assert.equal(late.json().error.code, 'INVITATION_VERSION_CONFLICT');

    const replacement = await create('sender', future(60));
    assert.equal(replacement.statusCode, 201, replacement.body);
    const replacementId = replacement.json().id as string;
    assert.equal((await act('sender', replacementId, 'address', 0,
      accounts.guest.x.handleSnapshot)).statusCode, 200,
    'the expired offer must no longer occupy the sender/recipient target');
    assert.equal((await act('sender', replacementId, 'cancel', 1)).statusCode, 200);
  });

  test('acting on a just-passed invitation reports expiry and stores history', async () => {
    const soon = new Date(Date.now() + 1200).toISOString().replace(/\.\d{3}Z$/, '.000Z');
    const created = await create('sender', soon);
    assert.equal(created.statusCode, 201, created.body);
    const id = created.json().id as string;
    await new Promise(resolvePromise => setTimeout(resolvePromise, 1600));
    const late = await act('sender', id, 'address', 0, accounts.guest.x.handleSnapshot);
    assert.equal(late.statusCode, 409, late.body);
    assert.equal(late.json().error.code, 'INVITATION_EXPIRED');
    const listed = (await list('sender', 'history')).json().invitations.find((row: {id: string}) => row.id === id);
    assert.equal(listed.state, 'expired');
  });

  test('the serving role cannot attach an asset or an amount to an invitation', async () => {
    const id = await invitationAt('draft');
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SELECT set_config('trimmy.practice_user_id', $1, true)", [accounts.sender.userId]);
      for (const column of ['indicative_amount_raw = 1', 'asset_id = gen_random_uuid()']) {
        await client.query('SAVEPOINT attempt');
        let code: string | undefined;
        try {
          await client.query(`UPDATE trimmy.invitations SET ${column}, version = version + 1 WHERE id = $1::uuid`, [id]);
        } catch (error) { code = (error as {code?: string}).code; }
        await client.query('ROLLBACK TO SAVEPOINT attempt');
        assert.equal(code, '42501', column);
      }
      await client.query('ROLLBACK');
    } finally {
      await client.query('ROLLBACK').catch(() => {});
      client.release();
    }
  });

  test('the serving role cannot reach a financial table or delete invitation history', async () => {
    const client = await pool.connect();
    try {
      await assert.rejects(client.query('SELECT * FROM trimmy.financial_intents'), {code: '42501'});
      await assert.rejects(client.query('DELETE FROM trimmy.invitations'), {code: '42501'});
    } finally { client.release(); }
  });
});
