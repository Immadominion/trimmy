import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtempSync, readFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {after, test} from 'node:test';
import {
  CareerRedDayRuntimeError, assertCareerRedDayDatabaseBoundary,
  readCareerRedDayRuntimeConfig,
} from './career-red-day-worker.mjs';
import {
  RED_DAY_CAPABILITY_ROLE, RED_DAY_WORKER_FUNCTIONS, RED_DAY_WORKER_ROLE,
} from './local-secure-runtime.mjs';

const directory = mkdtempSync(join(tmpdir(), 'trimmy-red-day-runner-'));
const certificate = join(directory, 'ca.crt');
execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes',
  '-keyout', join(directory, 'ca.key'), '-out', certificate, '-days', '1',
  '-subj', '/CN=trimmy-red-day-runner-test'], {stdio: 'ignore'});
const certificateText = readFileSync(certificate, 'utf8');
after(() => rmSync(directory, {recursive: true, force: true}));

const baseEnvironment = Object.freeze({
  TRIMMY_RED_DAY_DATABASE_URL:
    `postgresql://${RED_DAY_WORKER_ROLE}:fixture-secret@db.example:5432/trimmy`,
  TRIMMY_RED_DAY_DATABASE_CA_FILE: certificate,
  TRIMMY_RED_DAY_ASSET_CATALOG_JSON: '{"apple":"AAPL","tesla":"TSLA"}',
  TOKENS_API_KEY: 'fixture-key',
});

test('runtime configuration is bounded, pinned, and tied to the dedicated login', async () => {
  const config = await readCareerRedDayRuntimeConfig(baseEnvironment,
    async path => path === certificate ? certificateText : assert.fail('unexpected read'));
  assert.equal(config.database.user, RED_DAY_WORKER_ROLE);
  assert.equal(config.database.ssl.rejectUnauthorized, true);
  assert.equal(config.database.ssl.ca, certificateText);
  assert.equal(config.database.statement_timeout, 30_000);
  assert.equal(config.database.query_timeout, 35_000);
  assert.equal(config.workerRole, RED_DAY_WORKER_ROLE);
  assert.equal(config.capabilityRole, RED_DAY_CAPABILITY_ROLE);
  assert.deepEqual([...config.assets], [['apple', 'AAPL'], ['tesla', 'TSLA']]);
  assert.equal(config.candidateLimit, 20);
  assert.equal(config.evidenceBatchLimit, 50);
  assert.ok(Object.isFrozen(config) && Object.isFrozen(config.database));

  const custom = await readCareerRedDayRuntimeConfig({...baseEnvironment,
    TRIMMY_RED_DAY_CANDIDATE_LIMIT: '1', TRIMMY_RED_DAY_EVIDENCE_BATCH_LIMIT: '100'},
  async () => certificateText);
  assert.equal(custom.candidateLimit, 1);
  assert.equal(custom.evidenceBatchLimit, 100);
});

test('runtime configuration refuses role, URL, limit, key, catalog and certificate drift', async () => {
  const read = async () => certificateText;
  const rejects = async (change, pattern) => {
    await assert.rejects(readCareerRedDayRuntimeConfig({...baseEnvironment, ...change}, read), error => {
      assert.ok(error instanceof CareerRedDayRuntimeError);
      assert.match(error.message, pattern);
      return true;
    });
  };
  await rejects({TRIMMY_RED_DAY_DATABASE_URL:
    'postgresql://some_other_login:fixture-secret@db.example:5432/trimmy'}, /dedicated worker/);
  await rejects({TRIMMY_RED_DAY_CAPABILITY_ROLE: RED_DAY_WORKER_ROLE}, /dedicated worker/);
  await rejects({TRIMMY_RED_DAY_DATABASE_URL:
    `postgresql://${RED_DAY_WORKER_ROLE}:fixture-secret@db.example:5432/trimmy?sslmode=disable`}, /without query/);
  await rejects({TRIMMY_RED_DAY_CANDIDATE_LIMIT: '21'}, /from 1 to 20/);
  await rejects({TRIMMY_RED_DAY_EVIDENCE_BATCH_LIMIT: '0'}, /from 1 to 100/);
  await rejects({TOKENS_API_KEY: 'short'}, /TOKENS_API_KEY/);
  await rejects({TRIMMY_RED_DAY_ASSET_CATALOG_JSON: '{"apple":"bad symbol"}'}, /catalog/i);
  await assert.rejects(readCareerRedDayRuntimeConfig(baseEnvironment, async () => 'not a certificate'),
    /CA bundle is invalid/);
});

function boundaryResponses(overrides = {}) {
  const safeRole = Object.freeze({rolinherit: false, rolsuper: false, rolcreatedb: false,
    rolcreaterole: false, rolreplication: false, rolbypassrls: false, owns_objects: false});
  const rows = [
    [{ssl: true}],
    [{session_user_name: RED_DAY_WORKER_ROLE, current_user_name: RED_DAY_WORKER_ROLE,
      rolcanlogin: true, ...safeRole}],
    [{schema_usage: false, schema_create: false, functions: 0, tables: 0, sequences: 0}],
    [{rolname: RED_DAY_CAPABILITY_ROLE, rolcanlogin: false, ...safeRole}],
    [{count: 1, admin_option: false, inherit_option: false, set_option: true}],
    [{rolname: RED_DAY_WORKER_ROLE}],
    [],
    [{session_user_name: RED_DAY_WORKER_ROLE, current_user_name: RED_DAY_CAPABILITY_ROLE}],
    [{schema_usage: true, schema_create: false}],
    [{oid: '11'}, {oid: '12'}, {oid: '13'}, {oid: '14'}],
    [{oid: '11'}, {oid: '12'}, {oid: '13'}, {oid: '14'}],
    [{count: 0}],
    [{count: 0}],
  ];
  for (const [index, value] of Object.entries(overrides)) rows[Number(index)] = value;
  return rows;
}

function fakeClient(responses) {
  const calls = [];
  return Object.freeze({calls, query: async (sql, params) => {
    calls.push({sql, params});
    if (responses.length === 0) assert.fail(`unexpected query: ${sql}`);
    return {rows: responses.shift()};
  }});
}

const boundaryConfig = Object.freeze({workerRole: RED_DAY_WORKER_ROLE,
  capabilityRole: RED_DAY_CAPABILITY_ROLE});

test('database boundary proves TLS, exclusive ingress and the exact function-only capability', async () => {
  const responses = boundaryResponses();
  const client = fakeClient(responses);
  await assertCareerRedDayDatabaseBoundary(client, boundaryConfig);
  assert.equal(responses.length, 0);
  assert.equal(client.calls.length, 13);
  assert.match(client.calls[2].sql, /has_schema_privilege\(current_user/);
  assert.doesNotMatch(client.calls[2].sql, /has_schema_privilege\(session_user/);
  assert.deepEqual(client.calls[4].params, [RED_DAY_CAPABILITY_ROLE, RED_DAY_WORKER_ROLE]);
  assert.deepEqual(client.calls[5].params, [RED_DAY_CAPABILITY_ROLE]);
  assert.match(client.calls[6].sql, /^SET ROLE /);
  assert.deepEqual(client.calls[10].params, [RED_DAY_WORKER_FUNCTIONS]);
});

test('database boundary fails closed for plaintext, leaked direct grants and extra ingress', async () => {
  await assert.rejects(assertCareerRedDayDatabaseBoundary(
    fakeClient(boundaryResponses({0: [{ssl: false}]})), boundaryConfig), /not TLS encrypted/);
  await assert.rejects(assertCareerRedDayDatabaseBoundary(fakeClient(boundaryResponses({
    2: [{schema_usage: true, schema_create: false, functions: 0, tables: 0, sequences: 0}],
  })), boundaryConfig), /direct database privileges/);
  await assert.rejects(assertCareerRedDayDatabaseBoundary(fakeClient(boundaryResponses({
    5: [{rolname: RED_DAY_WORKER_ROLE}, {rolname: 'rogue_login'}],
  })), boundaryConfig), /Only the dedicated/);
});

test('database boundary rejects admin or inherited capability membership', async () => {
  await assert.rejects(assertCareerRedDayDatabaseBoundary(fakeClient(boundaryResponses({
    4: [{count: 1, admin_option: true, inherit_option: false, set_option: true}],
  })), boundaryConfig), /non-admin SET ROLE edge/);
  await assert.rejects(assertCareerRedDayDatabaseBoundary(fakeClient(boundaryResponses({
    4: [{count: 1, admin_option: false, inherit_option: true, set_option: true}],
  })), boundaryConfig), /non-admin SET ROLE edge/);
  await assert.rejects(assertCareerRedDayDatabaseBoundary(fakeClient(boundaryResponses({
    4: [{count: 1, admin_option: false, inherit_option: false, set_option: false}],
  })), boundaryConfig), /non-admin SET ROLE edge/);
});

test('database boundary rejects a missing or extra executable function by resolved OID', async () => {
  await assert.rejects(assertCareerRedDayDatabaseBoundary(fakeClient(boundaryResponses({
    9: [{oid: '11'}, {oid: '12'}, {oid: '13'}],
  })), boundaryConfig), /exact four-function/);
  await assert.rejects(assertCareerRedDayDatabaseBoundary(fakeClient(boundaryResponses({
    9: [{oid: '11'}, {oid: '12'}, {oid: '13'}, {oid: '14'}, {oid: '99'}],
  })), boundaryConfig), /exact four-function/);
});
