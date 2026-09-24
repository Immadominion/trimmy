import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {after, before, describe, test} from 'node:test';
import {Pool} from 'pg';
import {buildApp} from '../../src/app.js';
import {PostgresAccountClosure} from '../../src/account-closure.js';
import {PostgresInvitationsRepository} from '../../src/postgres-invitations-repository.js';
import type {PracticeIdentity} from '../../src/practice-identity.js';
import type {PrivyLinkedIdentityResolution} from '../../src/privy-linked-identities.js';

const socket = process.env['TRIMMY_PRACTICE_TEST_SOCKET'];
assert.ok(socket?.endsWith('/infra/.practice-runtime/socket'), 'Use the private test runner; never attach to an external database.');
assert.equal(process.env['TRIMMY_PRACTICE_TEST_PORT'], '65438');
const pool = new Pool({
  host: socket, port: 65438, database: 'postgres', user: 'trimmy_closure_test_app',
  connectionTimeoutMillis: 3000, max: 4,
});
const owner = new Pool({
  host: socket, port: 65438, database: 'postgres', user: 'trimmy_test_owner',
  connectionTimeoutMillis: 3000, max: 2,
});

type Who = 'leaver' | 'guest';
interface TestAccount {
  readonly userId: string;
  readonly identity: PracticeIdentity;
  readonly x: Readonly<{subject: string; handleSnapshot: string}>;
}

// Seeded by closure-fixtures.sql and relationship-integration-fixtures.sql.
const accounts: Readonly<Record<Who, TestAccount>> = Object.freeze({
  leaver: Object.freeze({
    userId: '00000000-0000-4000-8000-000000000011',
    identity: Object.freeze({provider: 'privy', appId: 'closure-test-app', subject: 'did:privy:leaver'}),
    x: Object.freeze({subject: '2011', handleSnapshot: 'leaver_eleven'}),
  }),
  guest: Object.freeze({
    userId: '00000000-0000-4000-8000-000000000012',
    identity: Object.freeze({provider: 'privy', appId: 'closure-test-app', subject: 'did:privy:guest'}),
    x: Object.freeze({subject: '2012', handleSnapshot: 'guest_twelve'}),
  }),
});
const accountByBearer = new Map<string, TestAccount>(Object.entries(accounts).map(([who, account]) =>
  [`Bearer ${who}`, account] as const));

function linked(account: TestAccount): PrivyLinkedIdentityResolution {
  return Object.freeze({
    provider: 'privy',
    subject: account.identity.subject,
    twitter: Object.freeze({
      status: 'verified', subject: account.x.subject,
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

const authenticate = async (authorization: string | undefined) => {
  const account = accountByBearer.get(authorization ?? '');
  return account ? {userId: account.userId} : null;
};
const authenticateContext = async (authorization: string | undefined) => {
  const account = accountByBearer.get(authorization ?? '');
  return account ? {userId: account.userId, identity: account.identity} : null;
};
const linkedIdentities = {
  resolve: async (identity: PracticeIdentity) => linked(accountForIdentity(identity)),
  resolveFresh: async (identity: PracticeIdentity) => linked(accountForIdentity(identity)),
};

const app = buildApp({
  logger: false,
  relationshipSafetyEnabled: true,
  relationshipSafetyReadiness: async () => true,
  accountClosure: {
    repository: new PostgresAccountClosure(pool),
    authenticate: request => authenticate(request.headers.authorization),
    authenticateContext: request => authenticateContext(request.headers.authorization),
    linkedIdentities,
  },
  invitations: {
    repository: new PostgresInvitationsRepository(pool),
    authenticateContext: request => authenticateContext(request.headers.authorization),
    linkedIdentities,
    xProfiles: {lookup: async handle => {
      const account = Object.values(accounts).find(candidate => candidate.x.handleSnapshot === handle.toLowerCase());
      assert.ok(account, `Unknown fixture X handle: ${handle}`);
      return Object.freeze({
        provider: 'x' as const, id: account.x.subject,
        username: account.x.handleSnapshot, name: account.x.handleSnapshot,
        lookedUpAt: '2026-09-20T12:00:00.000Z', ownershipVerified: false as const,
      });
    }},
    xLookupBudget: {run: async (_userId, operation) => operation()},
  },
});

const auth = (who: Who) => ({authorization: `Bearer ${who}`});
const close = (who: Who, confirm = 'close my account') =>
  app.inject({method: 'POST', url: '/v1/account/closure', headers: auth(who), payload: {schemaVersion: 1, confirm}});

function future(minutes: number): string {
  return new Date(Date.now() + minutes * 60_000).toISOString().replace(/\.\d{3}Z$/, '.000Z');
}

async function status(userId: string): Promise<string> {
  const result = await owner.query<{status: string}>('SELECT status FROM trimmy.users WHERE id = $1::uuid', [userId]);
  return result.rows[0]?.status ?? 'missing';
}

before(async () => { await app.ready(); });
after(async () => { await app.close(); await pool.end(); await owner.end(); });

describe('0025 account closure HTTP and PostgreSQL integration', () => {
  test('closing locks the account, cancels its offer and is audited', async () => {
    const created = await app.inject({
      method: 'POST', url: '/v1/invitations', headers: auth('leaver'),
      payload: {schemaVersion: 2, mutationId: randomUUID(), expiresAt: future(120)},
    });
    assert.equal(created.statusCode, 201, created.body);
    const id = created.json().id as string;
    const addressed = await app.inject({
      method: 'POST', url: `/v1/invitations/${id}/actions`, headers: auth('leaver'),
      payload: {schemaVersion: 2, action: 'address', expectedVersion: 0, xHandle: accounts.guest.x.handleSnapshot},
    });
    assert.equal(addressed.statusCode, 200, addressed.body);
    const offered = await app.inject({
      method: 'POST', url: `/v1/invitations/${id}/actions`, headers: auth('leaver'),
      payload: {schemaVersion: 2, action: 'offer', expectedVersion: 1},
    });
    assert.equal(offered.statusCode, 200, offered.body);
    const beforeClosure = (await app.inject({url: '/v1/invitations?box=open', headers: auth('guest')})).json();
    assert.equal(beforeClosure.invitations.find((row: {id: string}) => row.id === id).state, 'offered');
    assert.equal(await status(accounts.leaver.userId), 'active');

    const auditBefore = await owner.query<{count: string}>(
      "SELECT count(*)::text AS count FROM trimmy.audit_events WHERE entity_type = 'users' AND entity_id = $1",
      [accounts.leaver.userId]);

    const closed = await close('leaver');
    assert.equal(closed.statusCode, 200, closed.body);
    assert.equal(closed.json().closed, true);
    assert.equal(closed.json().canceledInvitations, 1);
    assert.equal(await status(accounts.leaver.userId), 'closed');

    const stored = await owner.query<{state: string}>(
      'SELECT state FROM trimmy.invitations WHERE id = $1::uuid', [id]);
    assert.equal(stored.rows[0]?.state, 'canceled');
    const guestHistory = (await app.inject({url: '/v1/invitations?box=history', headers: auth('guest')})).json();
    assert.equal(guestHistory.invitations.some((row: {id: string}) => row.id === id), false,
      'recipient history must not project a closed sender');

    const auditAfter = await owner.query<{count: string}>(
      "SELECT count(*)::text AS count FROM trimmy.audit_events WHERE entity_type = 'users' AND entity_id = $1",
      [accounts.leaver.userId]);
    assert.equal(Number(auditAfter.rows[0]!.count), Number(auditBefore.rows[0]!.count) + 1);
  });

  test('a closed account can no longer reach any account-scoped data', async () => {
    const listed = await app.inject({url: '/v1/invitations?box=open', headers: auth('leaver')});
    assert.equal(listed.statusCode, 404, listed.body);
    assert.equal(listed.json().error.code, 'INVITATION_ACCOUNT_NOT_FOUND');
    const creating = await app.inject({
      method: 'POST', url: '/v1/invitations', headers: auth('leaver'),
      payload: {schemaVersion: 2, mutationId: randomUUID(), expiresAt: future(120)},
    });
    assert.equal(creating.statusCode, 404, creating.body);
  });

  test('closing again reports that nothing was left to do', async () => {
    const again = await close('leaver');
    assert.equal(again.statusCode, 200, again.body);
    assert.equal(again.json().closed, false);
    assert.equal(again.json().canceledInvitations, 0);
    assert.equal(await status(accounts.leaver.userId), 'closed');
  });

  test('a real identity lookup refuses a closed account, so it cannot sign in again', async () => {
    const found = await owner.query<{account: string | null}>(
      'SELECT trimmy.practice_find_account($1, $2) AS account',
      [accounts.leaver.identity.appId, accounts.leaver.identity.subject]);
    assert.equal(found.rows[0]?.account, null, 'a closed account must not resolve');
  });

  test('the serving role still cannot touch the users table directly', async () => {
    const client = await pool.connect();
    try {
      await assert.rejects(client.query('SELECT status FROM trimmy.users'), {code: '42501'});
      await assert.rejects(client.query("UPDATE trimmy.users SET status = 'active'"), {code: '42501'});
    } finally { client.release(); }
  });
});
