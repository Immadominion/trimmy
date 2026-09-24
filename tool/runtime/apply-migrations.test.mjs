import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { promisify } from 'node:util';
import { createHash } from 'node:crypto';
import test from 'node:test';
import {
  MIGRATIONS, RED_DAY_CAPABILITY_ROLE, RED_DAY_WORKER_ROLE, SOCIAL_MODERATOR_ROLE,
} from './local-secure-runtime.mjs';
import {
  MIGRATION_DIGESTS, MigrationError, assertRelationshipApiDrained,
  parseOwnerDatabaseUrl, parseRuntimeRole,
  planMigrations, readCertificateBundle, readMigration, readMigrationConfig,
} from './apply-migrations.mjs';

const run = promisify(execFile);
const root = resolve(import.meta.dirname, '../..');
const url = 'postgresql://owner:secretpassword@db.example:5432/trimmy';
const throws = (fn, match) => assert.throws(fn, error => error instanceof MigrationError && match.test(error.message));

test('every ordered migration has a registered digest and no extra entries exist', () => {
  assert.deepEqual(Object.keys(MIGRATION_DIGESTS), [...MIGRATIONS]);
  for (const digest of Object.values(MIGRATION_DIGESTS)) assert.match(digest, /^[a-f0-9]{64}$/);
});

test('registered digests match the actual migration files on disk', async () => {
  for (const version of MIGRATIONS) {
    const raw = await readFile(join(root, 'infra', 'migrations', `${version}.sql`));
    assert.equal(createHash('sha256').update(raw).digest('hex'), MIGRATION_DIGESTS[version], version);
    // readMigration re-verifies and must return the file's text.
    assert.equal(await readMigration(version, {root}), raw.toString('utf8'));
  }
});

test('the local-day migration closes both online backfill write windows', async () => {
  const sql = await readFile(join(root, 'infra', 'migrations', '0019_career_local_day.sql'), 'utf8');
  const userTrigger = sql.indexOf('CREATE TRIGGER career_default_day_setting');
  const userBackfill = sql.indexOf('INSERT INTO trimmy.career_day_settings(', userTrigger);
  assert.ok(userTrigger >= 0 && userTrigger < userBackfill,
    'future-user trigger must lock users before the settings snapshot');

  const activityLock = sql.indexOf('LOCK TABLE trimmy.paper_orders, trimmy.career_trade_reasons');
  const activityBackfill = sql.indexOf(
    'INSERT INTO trimmy.career_activity_events(user_id', activityLock);
  const sourceTrigger = sql.indexOf('CREATE CONSTRAINT TRIGGER career_order_activity_pair');
  const commit = sql.lastIndexOf('COMMIT;');
  assert.ok(activityLock >= 0 && activityLock < activityBackfill,
    'source tables must be write-locked before the activity snapshot');
  assert.ok(activityBackfill < sourceTrigger && sourceTrigger < commit,
    'source pairing must be installed before the migration releases its locks');
});

test('the reason-sharing migration installs the future-user default before backfill', async () => {
  const sql = await readFile(join(root, 'infra', 'migrations',
    '0024_career_reason_sharing.sql'), 'utf8');
  const trigger = sql.indexOf('CREATE TRIGGER career_default_reason_privacy');
  const backfill = sql.indexOf('INSERT INTO trimmy.career_reason_privacy(', trigger);
  assert.ok(trigger >= 0 && trigger < backfill,
    'future users must receive a private default before the migration snapshots existing users');
  assert.match(sql, /ALTER TABLE trimmy\.career_reason_privacy ENABLE ROW LEVEL SECURITY/u);
  assert.match(sql, /ALTER TABLE trimmy\.career_reason_privacy FORCE ROW LEVEL SECURITY/u);
  assert.match(sql, /CREATE FUNCTION trimmy\.career_trade_reason_list\(/u);
});

test('the relationship migration fails closed before installing social authority', async () => {
  const sql = await readFile(join(root, 'infra', 'migrations',
    '0025_relationship_safety.sql'), 'utf8');
  const preflight = sql.indexOf("CONSTRAINT = 'provider_identities_provider_user_preflight'");
  const subjectPreflight = sql.indexOf("CONSTRAINT = 'provider_identities_x_preflight'");
  const invitationPreflight = sql.indexOf("CONSTRAINT = 'invitations_v2_preflight'");
  const providerUnique = sql.indexOf(
    'ADD CONSTRAINT provider_identities_provider_user_key UNIQUE (provider, user_id)',
  );
  const openUnique = sql.indexOf('CREATE UNIQUE INDEX invitation_open_target_key');
  assert.ok(preflight >= 0 && subjectPreflight > preflight &&
      invitationPreflight > subjectPreflight && providerUnique > invitationPreflight,
    'provider ambiguity and malformed X subjects must fail before uniqueness is installed');
  assert.ok(openUnique > providerUnique,
    'the open-target preflight must precede its partial unique index');
  assert.match(sql, /selected ~ '\^\[1-9\]\[0-9\]\{0,19\}\$'/u);
  assert.match(sql, /18446744073709551615/u);
  assert.match(sql, /i\.version >= 9007199254740991/u);
  assert.match(sql, /CREATE FUNCTION trimmy\.social_invitation_answer\(/u);
  assert.match(sql, /CREATE FUNCTION trimmy\.social_friend_list\([\s\S]*?RETURNS TABLE \(\s*outcome text, principal_social_id uuid/u);
  assert.match(sql, /CREATE FUNCTION trimmy\.social_block_get\([\s\S]*?RETURN QUERY SELECT 'found'::text, selected_target_profile, 0::bigint/u);
  assert.match(sql, /CREATE FUNCTION trimmy\.social_block_list\([\s\S]*?RETURNS TABLE \(\s*outcome text, principal_social_id uuid/u);
  assert.match(sql, /DROP FUNCTION trimmy\.career_trade_reason_list\(/u);
  assert.match(sql, /principal_social_id uuid[\s\S]*author_social_id uuid[\s\S]*author_persona text/u);
  assert.match(sql, /'trimmy\.social-reason:' \|\| selected_reason::text/u);
  assert.match(sql, /CREATE FUNCTION trimmy\.social_close_current_account\(selected_fresh_x_subject text\)/u);
  assert.match(sql, /p\.subject = selected_fresh_x_subject[\s\S]*?p\.user_id <> selected_user/u);
  assert.match(sql, /DROP FUNCTION trimmy\.invitation_self_x_subject\(\)/u);
  assert.match(sql, /ALTER TABLE trimmy\.provider_identities FORCE ROW LEVEL SECURITY/u);
  assert.match(sql, /ALTER TABLE trimmy\.social_friendships FORCE ROW LEVEL SECURITY/u);
  assert.match(sql, /VALUES \('0025_relationship_safety'\);\s*COMMIT;/u);
});

test('a migration whose bytes changed is refused instead of applied', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'trimmy-migrate-'));
  try {
    const migrations = join(directory, 'infra', 'migrations');
    await run('mkdir', ['-p', migrations]);
    await writeFile(join(migrations, `${MIGRATIONS[0]}.sql`), '-- edited after release\nSELECT 1;\n');
    await assert.rejects(readMigration(MIGRATIONS[0], {root: directory}),
      error => error instanceof MigrationError && /does not match its registered digest/.test(error.message));
  } finally { await rm(directory, {recursive: true, force: true}); }
});

test('an unregistered migration name is refused', async () => {
  await assert.rejects(readMigration('0099_not_registered', {root}),
    error => error instanceof MigrationError && /no registered digest/.test(error.message));
});

test('owner URL parsing keeps TLS verification and explicit fields', () => {
  const config = parseOwnerDatabaseUrl(url);
  assert.equal(config.host, 'db.example');
  assert.equal(config.port, 5432);
  assert.equal(config.database, 'trimmy');
  assert.equal(config.user, 'owner');
  assert.equal(config.password, 'secretpassword');
  assert.equal(config.ssl.rejectUnauthorized, true);
  assert.equal(config.ssl.ca, undefined);
  assert.equal(config.application_name, 'trimmy-migrate');
  // A default port is supplied when the URL omits it.
  assert.equal(parseOwnerDatabaseUrl('postgresql://owner:pw@db.example/trimmy').port, 5432);
  // An IPv6 host keeps its brackets stripped for pg.
  assert.equal(parseOwnerDatabaseUrl('postgresql://owner:pw@[::1]:6000/trimmy').host, '::1');
  // A pinned bundle is attached without disabling verification.
  const pinned = parseOwnerDatabaseUrl(url, 'PEM');
  assert.equal(pinned.ssl.rejectUnauthorized, true);
  assert.equal(pinned.ssl.ca, 'PEM');
});

test('owner URL parsing rejects sslmode options, bad shapes and missing secrets', () => {
  // A query option must never be able to replace certificate verification.
  throws(() => parseOwnerDatabaseUrl(`${url}?sslmode=disable`), /query or fragment/);
  throws(() => parseOwnerDatabaseUrl(`${url}#fragment`), /query or fragment/);
  throws(() => parseOwnerDatabaseUrl('mysql://owner:pw@db.example/trimmy'), /postgresql:\/\/ URL/);
  throws(() => parseOwnerDatabaseUrl('postgresql:///trimmy'), /valid URL|with a host/);
  throws(() => parseOwnerDatabaseUrl('postgresql://owner@db.example/trimmy'), /password/);
  throws(() => parseOwnerDatabaseUrl('postgresql://owner:pw@db.example/'), /database name/);
  throws(() => parseOwnerDatabaseUrl('postgresql://owner:pw@db.example/bad name'), /database name/);
  throws(() => parseOwnerDatabaseUrl('postgresql://bad user:pw@db.example/trimmy'), /user/);
  throws(() => parseOwnerDatabaseUrl('postgresql://owner:pw@db.example:99999/trimmy'), /port|valid URL/);
  throws(() => parseOwnerDatabaseUrl(undefined), /missing or malformed/);
  throws(() => parseOwnerDatabaseUrl(''), /missing or malformed/);
  throws(() => parseOwnerDatabaseUrl(` ${url}`), /missing or malformed/);
  throws(() => parseOwnerDatabaseUrl(`postgresql://owner:${'p'.repeat(600)}@db.example/trimmy`), /password/);
  throws(() => parseOwnerDatabaseUrl('not a url'), /valid URL/);
});

test('the restricted role name must be a plain identifier', () => {
  assert.equal(parseRuntimeRole(undefined), undefined);
  assert.equal(parseRuntimeRole(''), undefined);
  assert.equal(parseRuntimeRole('trimmy_practice_runtime'), 'trimmy_practice_runtime');
  for (const bad of ['Trimmy', 'role; DROP TABLE x', 'role name', '1role', 'r'.repeat(64), 'role-name', '"role"']) {
    throws(() => parseRuntimeRole(bad), /identifier/);
  }
});

test('configuration is read from the environment as a frozen whole', () => {
  const config = readMigrationConfig({TRIMMY_MIGRATION_DATABASE_URL: url});
  assert.equal(config.database.host, 'db.example');
  assert.equal(config.runtimeRole, undefined);
  assert.equal(config.redDayCapabilityRole, RED_DAY_CAPABILITY_ROLE);
  assert.equal(config.redDayWorkerRole, RED_DAY_WORKER_ROLE);
  assert.equal(config.socialModeratorRole, SOCIAL_MODERATOR_ROLE);
  assert.equal(config.relationshipCutover, '');
  assert.equal(config.activateRedDay, false);
  assert.equal(config.grantsOnly, false);
  const explicit = readMigrationConfig({
    TRIMMY_MIGRATION_DATABASE_URL: url, TRIMMY_MIGRATION_RUNTIME_ROLE: 'app_role',
    TRIMMY_MIGRATION_RED_DAY_CAPABILITY_ROLE: 'red_day_capability',
    TRIMMY_MIGRATION_RED_DAY_WORKER_ROLE: 'red_day_login',
    TRIMMY_MIGRATION_SOCIAL_MODERATOR_ROLE: 'social_moderator',
    TRIMMY_MIGRATION_RELATIONSHIP_CUTOVER: 'drained-v2',
    TRIMMY_MIGRATION_ACTIVATE_RED_DAY: 'true',
    TRIMMY_MIGRATION_GRANTS_ONLY: 'true',
  });
  assert.equal(explicit.runtimeRole, 'app_role');
  assert.equal(explicit.redDayCapabilityRole, 'red_day_capability');
  assert.equal(explicit.redDayWorkerRole, 'red_day_login');
  assert.equal(explicit.socialModeratorRole, 'social_moderator');
  assert.equal(explicit.relationshipCutover, 'drained-v2');
  assert.equal(explicit.activateRedDay, true);
  assert.equal(explicit.grantsOnly, true);
  // Any value other than the exact string keeps DDL enabled.
  assert.equal(readMigrationConfig({TRIMMY_MIGRATION_DATABASE_URL: url, TRIMMY_MIGRATION_GRANTS_ONLY: '1'}).grantsOnly, false);
  for (const variable of ['TRIMMY_MIGRATION_RED_DAY_CAPABILITY_ROLE',
    'TRIMMY_MIGRATION_RED_DAY_WORKER_ROLE', 'TRIMMY_MIGRATION_SOCIAL_MODERATOR_ROLE']) {
    throws(() => readMigrationConfig({TRIMMY_MIGRATION_DATABASE_URL: url,
      [variable]: 'unsafe role'}), /identifier/);
  }
  throws(() => readMigrationConfig({TRIMMY_MIGRATION_DATABASE_URL: url,
    TRIMMY_MIGRATION_ACTIVATE_RED_DAY: '1'}), /must be true or false/);
  throws(() => readMigrationConfig({TRIMMY_MIGRATION_DATABASE_URL: url,
    TRIMMY_MIGRATION_RELATIONSHIP_CUTOVER: 'yes'}), /must be drained-v2/);
  assert.ok(Object.isFrozen(config) && Object.isFrozen(config.database));
});

test('relationship cutover needs an explicit acknowledgement and a drained API pool', async () => {
  const calls = [];
  const drained = {query: async sql => { calls.push(sql); return {rows: [{count: 0}]}; }};
  await assert.doesNotReject(assertRelationshipApiDrained(drained, 'drained-v2'));
  assert.equal(calls.length, 1);
  assert.match(calls[0], /application_name='trimmy-practice-api'/u);
  await assert.rejects(assertRelationshipApiDrained(drained, ''),
    error => error instanceof MigrationError && /acknowledged drained-v2/.test(error.message));
  const active = {query: async () => ({rows: [{count: 1}]})};
  await assert.rejects(assertRelationshipApiDrained(active, 'drained-v2'),
    error => error instanceof MigrationError && /session to be drained/.test(error.message));
});

test('an empty database plans every migration and a current one plans none', () => {
  const fresh = planMigrations([]);
  assert.deepEqual([...fresh.pending], [...MIGRATIONS]);
  assert.deepEqual([...fresh.applied], []);
  const current = planMigrations([...MIGRATIONS]);
  assert.deepEqual([...current.pending], []);
  assert.deepEqual([...current.applied], [...MIGRATIONS]);
  // A partially migrated database resumes at the exact next migration.
  const partial = planMigrations(MIGRATIONS.slice(0, 3));
  assert.deepEqual([...partial.applied], MIGRATIONS.slice(0, 3));
  assert.deepEqual([...partial.pending], MIGRATIONS.slice(3));
  assert.ok(Object.isFrozen(partial.pending));
});

test('a database ahead of this build, or recorded out of order, is refused', () => {
  throws(() => planMigrations([...MIGRATIONS, '0009_future_release']), /does not know/);
  throws(() => planMigrations(['0009_future_release']), /does not know/);
  // A gap means the schema is not a state this build can reason about.
  throws(() => planMigrations([MIGRATIONS[0], MIGRATIONS[2]]), /ordered prefix|out of order/);
  throws(() => planMigrations([MIGRATIONS[1]]), /ordered prefix|out of order/);
  throws(() => planMigrations([MIGRATIONS[0], MIGRATIONS[0]]), /duplicate/);
});

test('a CA bundle must contain parsable certificates', async () => {
  throws(() => readCertificateBundle('no certificate here'), /no usable certificate/);
  throws(() => readCertificateBundle('-----BEGIN CERTIFICATE-----\nnotbase64\n-----END CERTIFICATE-----'), /unparsable/);
  throws(() => readCertificateBundle('x'.repeat(70_000)), /too large/);
  // A real self-signed certificate is accepted unchanged.
  const directory = await mkdtemp(join(tmpdir(), 'trimmy-ca-'));
  try {
    const key = join(directory, 'ca.key'), cert = join(directory, 'ca.crt');
    await run('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', key,
      '-out', cert, '-days', '1', '-subj', '/CN=trimmy-test-ca']);
    const pem = await readFile(cert, 'utf8');
    assert.equal(readCertificateBundle(pem), pem);
  } finally { await rm(directory, {recursive: true, force: true}); }
});
