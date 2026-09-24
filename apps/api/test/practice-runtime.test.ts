import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { generateKeyPairSync } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, test } from 'node:test';
import { createPracticeRuntime, readPracticeRuntimeConfig } from '../src/practice-runtime.js';

const {publicKey} = generateKeyPairSync('ec', {namedCurve: 'prime256v1'});
const key = publicKey.export({type: 'spki', format: 'pem'}).toString().trim();
const guestSourceKey = Buffer.alloc(32, 9).toString('base64url');
const env = {PRIVY_APP_ID: 'test-app', PRIVY_VERIFICATION_KEY: key,
  PRACTICE_DATABASE_URL: 'postgresql://practice:example-password@db.example.com:6432/postgres',
  TRIMMY_GUEST_SOURCE_MODE: 'direct', TRIMMY_GUEST_SOURCE_HMAC_KEY: guestSourceKey};

test('empty runtime config keeps practice offline and partial configuration cannot silently downgrade', async () => {
  assert.equal(readPracticeRuntimeConfig({}), null);
  const runtime = createPracticeRuntime(null);
  assert.deepEqual(runtime.options, {});
  await runtime.close();
  for (const partial of [{PRIVY_APP_ID: 'test'}, {PRIVY_VERIFICATION_KEY: key}, {...env, PRACTICE_DATABASE_URL: ''}]) {
    assert.throws(() => readPracticeRuntimeConfig(partial), /incomplete or invalid/);
  }
});

test('database configuration uses explicit TLS verification and bounded connections without URL overrides', () => {
  const config = readPracticeRuntimeConfig(env)!;
  assert.equal(config.database.host, 'db.example.com');
  assert.equal(config.database.port, 6432);
  assert.equal(config.database.database, 'postgres');
  assert.equal(config.database.user, 'practice');
  assert.deepEqual(config.database.ssl, {rejectUnauthorized: true});
  assert.equal(config.database.connectionTimeoutMillis, 5000);
  assert.equal(config.database.connectionString, undefined);
  assert.equal(config.guestSource.mode, 'direct');
  assert.equal(config.relationshipModerationRole, 'trimmy_social_moderator');
  assert.equal(config.guestSource.hmacKey.toString('base64url'), guestSourceKey);
  assert.equal(readPracticeRuntimeConfig({...env, PRIVY_VERIFICATION_KEY: key.replaceAll('\n', '\\n')})!.verificationKey, key);
  assert.equal(readPracticeRuntimeConfig({...env, PRIVY_VERIFICATION_KEY: `${key}\n`})!.verificationKey, key);
});

test('moderation role configuration is bounded and explicit', () => {
  assert.equal(readPracticeRuntimeConfig({...env,
    TRIMMY_MIGRATION_SOCIAL_MODERATOR_ROLE: 'trimmy_review_ops'})!
    .relationshipModerationRole, 'trimmy_review_ops');
  for (const value of ['TrimmyModerator', 'bad-role', 'two roles', '', 'a'.repeat(64)]) {
    const configured = {...env, TRIMMY_MIGRATION_SOCIAL_MODERATOR_ROLE: value};
    if (value === '') {
      assert.equal(readPracticeRuntimeConfig(configured)!.relationshipModerationRole,
        'trimmy_social_moderator');
    } else {
      assert.throws(() => readPracticeRuntimeConfig(configured), /incomplete or invalid/u);
    }
  }
  assert.throws(() => readPracticeRuntimeConfig({
    TRIMMY_MIGRATION_SOCIAL_MODERATOR_ROLE: 'trimmy_review_ops',
  }), /incomplete or invalid/u);
});

test('configured account runtime requires complete guest source protection', () => {
  const {TRIMMY_GUEST_SOURCE_MODE: _mode, TRIMMY_GUEST_SOURCE_HMAC_KEY: _sourceKey, ...withoutSource} = env;
  assert.throws(() => readPracticeRuntimeConfig(withoutSource), /incomplete or invalid/);
  assert.throws(() => readPracticeRuntimeConfig({...env, TRIMMY_GUEST_SOURCE_HMAC_KEY: ''}), /incomplete or invalid/);
});

test('malformed database configuration never includes credentials in its failure', () => {
  for (const url of [
    'postgresql://practice:private-secret@db.example.com/postgres?sslmode=disable',
    'postgresql://practice:private-secret@db.example.com/postgres#fragment',
    'postgresql://practice@db.example.com/postgres',
    'postgresql://practice:private-secret@db.example.com:0/postgres',
    'https://practice:private-secret@db.example.com/postgres',
    'postgresql://practice:private-secret@db.example.com/one/two',
  ]) {
    assert.throws(() => readPracticeRuntimeConfig({...env, PRACTICE_DATABASE_URL: url}), error => {
      assert.ok(error instanceof Error);
      assert.equal(error.message.includes('private-secret'), false);
      return true;
    });
  }
});

test('configured runtime composes real adapters without connecting until requested and closes cleanly', async () => {
  const runtime = createPracticeRuntime(readPracticeRuntimeConfig(env));
  try {
    assert.equal(typeof runtime.options.practice?.authenticate, 'function');
    assert.equal(typeof runtime.authenticate, 'function');
    assert.equal(typeof runtime.authenticateContext, 'function');
    assert.equal(typeof runtime.options.practiceSessions?.accounts.provision, 'function');
    assert.equal(typeof runtime.options.watchlist?.repository.put, 'function');
    assert.equal(typeof runtime.paperTradingRepository?.commit, 'function');
    assert.equal(typeof runtime.options.productProfile?.repository.get, 'function');
    assert.equal(typeof runtime.options.productProfile?.repository.put, 'function');
    assert.equal(typeof runtime.options.productProfile?.authenticate, 'function');
    assert.equal(typeof runtime.options.career?.repository.getSummary, 'function');
    assert.equal(typeof runtime.options.career?.repository.saveTradeReason, 'function');
    assert.equal(typeof runtime.options.career?.authenticate, 'function');
    assert.equal(typeof runtime.options.careerReasonSharing?.repository.getPrivacy, 'function');
    assert.equal(typeof runtime.options.careerReasonSharing?.repository.savePrivacy, 'function');
    assert.equal(typeof runtime.options.careerReasonSharing?.repository.listReasons, 'function');
    assert.equal(typeof runtime.options.careerReasonSharing?.authenticate, 'function');
    assert.equal(typeof runtime.options.socialRelationships?.repository.listFriends, 'function');
    assert.equal(typeof runtime.options.socialRelationships?.repository.getBlock, 'function');
    assert.equal(typeof runtime.options.socialRelationships?.repository.putBlock, 'function');
    assert.equal(typeof runtime.options.socialRelationships?.repository.reportReason, 'function');
    assert.equal(typeof runtime.options.socialRelationships?.authenticate, 'function');
    assert.equal(typeof runtime.relationshipSafetyReadiness, 'function');
    assert.deepEqual(runtime.options.browserOrigins, []);
  } finally { await runtime.close(); }
});

test('browser origins are explicit HTTPS JSON configuration and cannot bypass required account setup', () => {
  assert.deepEqual(readPracticeRuntimeConfig({...env, TRIMMY_WEB_ORIGINS: '["https://app.trimmy.test"]'})!.browserOrigins, ['https://app.trimmy.test']);
  for (const raw of ['*', '["*"]', '["null"]', '["http://app.trimmy.test"]', '["https://app.trimmy.test/"]', '{}']) {
    assert.throws(() => readPracticeRuntimeConfig({...env, TRIMMY_WEB_ORIGINS: raw}), /incomplete or invalid/);
  }
  assert.throws(() => readPracticeRuntimeConfig({TRIMMY_WEB_ORIGINS: '["https://app.trimmy.test"]'}), /incomplete or invalid/);
});

test('an optional pinned database CA bundle is validated and never widens or weakens verification', () => {
  const dir = mkdtempSync(join(tmpdir(), 'trimmy-db-ca-'));
  after(() => rmSync(dir, {recursive: true, force: true}));
  const ca = join(dir, 'ca.crt');
  let opensslAvailable = true;
  try {
    execFileSync('openssl', ['req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:prime256v1', '-nodes',
      '-keyout', join(dir, 'ca.key'), '-out', ca, '-subj', '/CN=Trimmy local CA', '-days', '2'], {stdio: 'ignore'});
  } catch { opensslAvailable = false; }
  if (opensslAvailable) {
    const config = readPracticeRuntimeConfig({...env, PRACTICE_DATABASE_CA_FILE: ca})!;
    assert.deepEqual(config.database.ssl, {rejectUnauthorized: true, ca: readFileSync(ca, 'utf8')});
  }
  const garbage = join(dir, 'garbage.crt');
  writeFileSync(garbage, '-----BEGIN CERTIFICATE-----\nnot-a-certificate\n-----END CERTIFICATE-----\n');
  for (const file of [garbage, join(dir, 'missing-private-path.crt'), ` ${ca}`]) {
    assert.throws(() => readPracticeRuntimeConfig({...env, PRACTICE_DATABASE_CA_FILE: file}), error => {
      assert.ok(error instanceof Error);
      assert.match(error.message, /incomplete or invalid/);
      assert.equal(error.message.includes('missing-private-path'), false);
      return true;
    });
  }
  // A CA file alone is not account configuration.
  assert.throws(() => readPracticeRuntimeConfig({PRACTICE_DATABASE_CA_FILE: ca}), /incomplete or invalid/);

  if (opensslAvailable) {
    // Hosted platforms often supply environment variables and no writable file.
    const inline = readFileSync(ca, 'utf8');
    const fromInline = readPracticeRuntimeConfig({...env, PRACTICE_DATABASE_CA: inline})!;
    assert.deepEqual(fromInline.database.ssl, {rejectUnauthorized: true, ca: inline});
    // A single-line variable with escaped newlines is the common shape.
    const escaped = inline.replace(/\n/g, '\\n');
    const fromEscaped = readPracticeRuntimeConfig({...env, PRACTICE_DATABASE_CA: escaped})!;
    assert.deepEqual(fromEscaped.database.ssl, {rejectUnauthorized: true, ca: inline});
    // Two sources would leave which one is trusted ambiguous.
    assert.throws(() => readPracticeRuntimeConfig({...env, PRACTICE_DATABASE_CA: inline, PRACTICE_DATABASE_CA_FILE: ca}),
      /incomplete or invalid/);
    // An inline CA alone is not account configuration either.
    assert.throws(() => readPracticeRuntimeConfig({PRACTICE_DATABASE_CA: inline}), /incomplete or invalid/);
  }
  for (const bad of ['-----BEGIN CERTIFICATE-----\nnot-a-certificate\n-----END CERTIFICATE-----\n', 'plain text']) {
    assert.throws(() => readPracticeRuntimeConfig({...env, PRACTICE_DATABASE_CA: bad}),
      /incomplete or invalid/, JSON.stringify(bad));
  }
  // An empty variable means unset here, as it does for every other value.
  assert.deepEqual(readPracticeRuntimeConfig({...env, PRACTICE_DATABASE_CA: ''})!.database.ssl,
    {rejectUnauthorized: true});
});
