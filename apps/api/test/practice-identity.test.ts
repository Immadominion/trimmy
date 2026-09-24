import assert from 'node:assert/strict';
import { generateKeyPairSync, sign } from 'node:crypto';
import { describe, it } from 'node:test';
import type { Pool, PoolClient } from 'pg';
import {
  MAX_PRACTICE_BEARER_HEADER_LENGTH, PracticeIdentityError,
  isPracticeAccessToken, parsePracticeBearerToken, parsePracticeIdentity,
} from '../src/practice-identity.js';
import type { PracticeIdentity } from '../src/practice-identity.js';
import { PrivyPracticeIdentityVerifier } from '../src/privy-practice-auth.js';
import { PostgresPracticeAccounts } from '../src/postgres-practice-accounts.js';

// Synthetic keys only: actual SDK cryptographic verification, no Privy calls.
const keys = generateKeyPairSync('ec', {namedCurve: 'prime256v1'});
const verificationKey = keys.publicKey.export({format: 'pem', type: 'spki'}).toString();
const appId = 'trimmy-practice-test-app';
const subject = 'did:privy:cm3np4u9j001rc8b73seqmqqk';
const identity: PracticeIdentity = {provider: 'privy', appId, subject};
const verifier = new PrivyPracticeIdentityVerifier({appId, verificationKey});
const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString('base64url');
function claims(): Record<string, unknown> {
  const now = Math.floor(Date.now() / 1000);
  return {iss: 'privy.io', aud: appId, sub: subject, sid: 'test-session-01', iat: now - 10, exp: now + 300};
}
function jwt(payload: Record<string, unknown>, header: Record<string, unknown> = {alg: 'ES256', typ: 'JWT'}): string {
  const unsigned = `${encode(header)}.${encode(payload)}`;
  return `${unsigned}.${sign('sha256', Buffer.from(unsigned), {key: keys.privateKey, dsaEncoding: 'ieee-p1363'}).toString('base64url')}`;
}
const errorCode = (expected: string) => (error: unknown) => error instanceof PracticeIdentityError && error.code === expected;

describe('Privy practice access-token verification', () => {
  it('accepts a bounded single Bearer JWT and refuses ambiguous or control-bearing input', () => {
    const token = jwt(claims());
    assert.equal(parsePracticeBearerToken(`Bearer ${token}`), token);
    assert.equal(parsePracticeBearerToken(`bearer ${token}`), token);
    for (const header of [undefined, null, [], [`Bearer ${token}`], token, `Basic ${token}`, `Bearer  ${token}`,
      `Bearer\t${token}`, `Bearer ${token}\n`, `Bearer ${token}\r\n`, `Bearer ${token}, Bearer ${token}`,
      ` Bearer ${token}`, `Bearer ${token} `, 'Bearer aaa.bbb.', 'Bearer aaa.bbb.ccc=']) {
      assert.equal(parsePracticeBearerToken(header), null);
    }
    assert.equal(parsePracticeBearerToken(`Bearer ${'a'.repeat(MAX_PRACTICE_BEARER_HEADER_LENGTH)}.b.c`), null);
    assert.equal(isPracticeAccessToken(`${token}\n`), false);
  });

  it('extracts only the SDK-verified Privy DID, app and provider', async () => {
    const result = await verifier.verify(jwt({...claims(), userId: 'client-selected-uuid', wallet: 'untrusted-wallet', linked_accounts: []}));
    assert.deepEqual(result, identity);
    assert.equal(Object.isFrozen(result), true);
    assert.deepEqual(await verifier.verify(jwt({...claims(), sub: 'did:privy:CaseSensitiveID'})), {...identity, subject: 'did:privy:CaseSensitiveID'});
  });

  it('rejects wrong signatures, algorithm, JWT type, issuer and app audience', async () => {
    const token = jwt(claims());
    const segments = token.split('.');
    segments[2] = `${segments[2]![0] === 'A' ? 'B' : 'A'}${segments[2]!.slice(1)}`;
    assert.equal(await verifier.verify(segments.join('.')), null);
    for (const header of [{alg: 'HS256', typ: 'JWT'}, {alg: 'ES384', typ: 'JWT'}, {alg: 'none', typ: 'JWT'}, {alg: 'ES256', typ: 'at+jwt'}]) {
      assert.equal(await verifier.verify(jwt(claims(), header)), null);
    }
    assert.equal(await verifier.verify(jwt({...claims(), iss: 'attacker.invalid'})), null);
    assert.equal(await verifier.verify(jwt({...claims(), aud: 'different-privy-app'})), null);
    assert.equal(await verifier.verify(jwt({...claims(), aud: [appId, 'other']})), null);
  });

  it('rejects expiry, not-before and invalid mandatory timestamp values', async () => {
    const now = Math.floor(Date.now() / 1000);
    for (const payload of [
      {...claims(), exp: now - 1}, {...claims(), nbf: now + 60},
      {...claims(), iat: now + 60}, {...claims(), iat: now - 10.5},
      {...claims(), exp: now + 100.5}, {...claims(), exp: String(now + 100)},
      {...claims(), iat: 0}, {...claims(), iat: null},
    ]) assert.equal(await verifier.verify(jwt(payload)), null);
  });

  it('requires every access-token claim and a bounded Privy subject/session', async () => {
    for (const field of ['iss', 'aud', 'sub', 'sid', 'iat', 'exp']) {
      const missing = claims(); delete missing[field];
      assert.equal(await verifier.verify(jwt(missing)), null, `Missing ${field}`);
    }
    for (const sub of ['', '00000000-0000-4000-a000-000000000001', 'wallet-address', 'did:privy:', `${subject}\n`, 'did:other:abc', `did:privy:${'a'.repeat(129)}`]) {
      assert.equal(await verifier.verify(jwt({...claims(), sub})), null);
    }
    for (const sid of ['', null, 123, 'session\n', 'a'.repeat(257)]) {
      assert.equal(await verifier.verify(jwt({...claims(), sid})), null);
    }
  });

  it('defaults closed and rejects partial, wrong-curve or private-key configuration', async () => {
    assert.equal(await new PrivyPracticeIdentityVerifier().verify(jwt(claims())), null);
    assert.equal(await verifier.verify('not-a-token'), null);
    const wrongCurve = generateKeyPairSync('ed25519').publicKey.export({format: 'pem', type: 'spki'}).toString();
    const privatePem = keys.privateKey.export({format: 'pem', type: 'pkcs8'}).toString();
    for (const config of [{appId, verificationKey: ''}, {appId: '', verificationKey},
      {appId: `${appId}\n`, verificationKey}, {appId, verificationKey: wrongCurve},
      {appId, verificationKey: privatePem}, {appId, verificationKey: 'invalid public key'}]) {
      assert.throws(() => new PrivyPracticeIdentityVerifier(config), errorCode('PRACTICE_IDENTITY_CONFIGURATION_INVALID'));
    }
  });

  it('identity parsing clones safe fields and refuses implicit identity sources/getters', () => {
    const source = {...identity};
    const parsed = parsePracticeIdentity(source);
    source.subject = 'did:privy:changed';
    assert.deepEqual(parsed, identity);
    for (const bad of [null, [], {...identity, provider: 'x'}, {...identity, userId: 'chosen'}, {...identity, appId: `${appId}\n`}, {...identity, subject: `${subject}\r`}]) {
      assert.throws(() => parsePracticeIdentity(bad), errorCode('PRACTICE_IDENTITY_INVALID'));
    }
    let invoked = false;
    const accessor = {...identity};
    Object.defineProperty(accessor, 'subject', {get() { invoked = true; return subject; }, enumerable: true});
    assert.throws(() => parsePracticeIdentity(accessor), errorCode('PRACTICE_IDENTITY_INVALID'));
    assert.equal(invoked, false);
  });
});

class AccountConnection {
  readonly calls: {sql: string; parameters: unknown[]}[] = [];
  readonly releases: (Error | undefined)[] = [];
  connections = 0;
  result: unknown = '00000000-0000-4000-a000-000000000001';
  unsafe = false;
  queryFails = false;
  rollbackFails = false;
  readonly pool = {connect: async () => {
    this.connections++;
    return {
      query: async (sql: string, parameters: unknown[] = []) => {
        this.calls.push({sql, parameters});
        if (sql.includes('AS unsafe_role')) return {rows: [{unsafe_role: this.unsafe}]};
        if (sql.includes('SELECT trimmy.practice_')) {
          if (this.queryFails) throw new Error('simulated database query failure');
          return {rows: [{user_id: this.result}]};
        }
        if (sql === 'ROLLBACK' && this.rollbackFails) throw new Error('simulated rollback failure');
        return {rows: []};
      },
      release: (error?: Error) => { this.releases.push(error); },
    } as unknown as PoolClient;
  }} satisfies Pick<Pool, 'connect'>;
}

describe('PostgreSQL practice account port', () => {
  it('lookup never provisions and passes only validated exact app/subject parameters', async () => {
    const connection = new AccountConnection(); connection.result = null;
    assert.equal(await new PostgresPracticeAccounts(connection.pool).find(identity), null);
    assert.equal(connection.calls[0]!.sql, 'BEGIN READ ONLY');
    assert.equal(connection.calls.some(call => call.sql.includes('practice_provision_account')), false);
    assert.deepEqual(connection.calls.find(call => call.sql.includes('practice_find_account'))!.parameters, [appId, subject]);
    assert.equal(connection.calls.at(-1)!.sql, 'COMMIT');
    assert.deepEqual(connection.releases, [undefined]);
  });

  it('provision exposes only the database UUID and closed mappings stay unavailable', async () => {
    const connection = new AccountConnection();
    const repository = new PostgresPracticeAccounts(connection.pool);
    const result = await repository.provision(identity);
    assert.deepEqual(result, {userId: connection.result});
    assert.equal(Object.isFrozen(result), true);
    connection.result = null;
    await assert.rejects(repository.provision(identity), errorCode('PRACTICE_ACCOUNT_UNAVAILABLE'));
  });

  it('invalid direct identities never acquire a database connection', async () => {
    const connection = new AccountConnection();
    await assert.rejects(new PostgresPracticeAccounts(connection.pool).find({...identity, subject: 'wallet-address'}), errorCode('PRACTICE_IDENTITY_INVALID'));
    assert.equal(connection.connections, 0);
  });

  it('rejects privileged runtime roles and malformed UUID responses', async () => {
    const connection = new AccountConnection(); connection.unsafe = true;
    const repository = new PostgresPracticeAccounts(connection.pool);
    await assert.rejects(repository.provision(identity), errorCode('PRACTICE_IDENTITY_RUNTIME_ROLE_INVALID'));
    assert.equal(connection.calls.some(call => call.sql.includes('practice_provision_account')), false);
    connection.unsafe = false; connection.result = 'did:privy:not-a-database-uuid';
    await assert.rejects(repository.find(identity), errorCode('PRACTICE_IDENTITY_STORAGE_INVALID'));
    assert.equal(connection.calls.at(-1)!.sql, 'ROLLBACK');
  });

  it('rolls back query failure and destroys a client with failed transaction cleanup', async () => {
    const connection = new AccountConnection(); connection.queryFails = true; connection.rollbackFails = true;
    await assert.rejects(new PostgresPracticeAccounts(connection.pool).provision(identity), /simulated database query failure/);
    assert.equal(connection.calls.at(-1)!.sql, 'ROLLBACK');
    assert.equal(connection.releases.length, 1);
    assert.ok(connection.releases[0] instanceof Error);
    assert.equal(connection.releases[0]!.message, 'Practice identity transaction cleanup failed.');
  });
});
