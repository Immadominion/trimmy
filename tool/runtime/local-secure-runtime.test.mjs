import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { after, test } from 'node:test';
import {
  DATABASE, MIGRATIONS, OWNER_ROLE, RED_DAY_API_DENIED_FUNCTIONS, RED_DAY_CAPABILITY_ROLE, RED_DAY_WORKER_FUNCTIONS,
  RED_DAY_WORKER_ROLE, RUNTIME_ROLE, SOCIAL_MODERATOR_FUNCTION, SOCIAL_MODERATOR_ROLE,
  RuntimeError,
  buildDatabaseUrl, escapeVerificationKey, parseApiEnv, readPublicVerifier,
  renderApiEnv, renderHba, renderManifest, renderPostgresConf, runtimeGrants, runtimePaths,
  configureWalletChecksEnvironment, assertWalletChecksStarted, parseFlags,
  configureRelationshipSafetyEnvironment, assertRelationshipSafetyStarted,
  ensureGuestSourceEnvironment, redDayWorkerGrants, redDayWorkerLoginDenials,
  socialModeratorGrants,
} from './local-secure-runtime.mjs';

const dir = mkdtempSync(join(tmpdir(), 'trimmy-runtime-tool-'));
after(() => rmSync(dir, {recursive: true, force: true}));

test('wallet checks are an explicit CLI flag and other runtime choices remain independent', () => {
  assert.deepEqual(parseFlags([]), {});
  assert.deepEqual(parseFlags(['--with-wallet-checks']), {withWalletChecks: true});
  assert.deepEqual(parseFlags(['--with-app-secret', '--with-market-reads', '--with-holdings-reads', '--with-wallet-checks', '--with-relationship-safety']),
    {withAppSecret: true, withMarketReads: true, withHoldingsReads: true,
      withWalletChecks: true, withRelationshipSafety: true});
  assert.throws(() => parseFlags(['--with-wallet-check']), /Unknown option/);
});

test('relationship safety is a child-process-only opt-in and stale stored values are removed', async () => {
  const base = Object.freeze({
    PRIVY_APP_ID: 'app',
    TRIMMY_RELATIONSHIP_SAFETY_ENABLED: 'true',
    X_BEARER_TOKEN: 'stale-stored-token',
  });
  const calls = [];
  assert.deepEqual(await configureRelationshipSafetyEnvironment(base, {}, {
    readSecret: async service => { calls.push(service); throw new Error('must not read'); },
  }), {PRIVY_APP_ID: 'app'});
  assert.deepEqual(calls, []);
  assert.deepEqual(await configureRelationshipSafetyEnvironment(base, {withRelationshipSafety: true}, {
    readSecret: async service => { calls.push(service); return 'fixture-x-bearer-token'; },
  }), {
    PRIVY_APP_ID: 'app',
    TRIMMY_RELATIONSHIP_SAFETY_ENABLED: 'true',
    X_BEARER_TOKEN: 'fixture-x-bearer-token',
  });
  assert.deepEqual(calls, ['trimmy-x-bearer-token']);
  assert.equal(base.TRIMMY_RELATIONSHIP_SAFETY_ENABLED, 'true');
  assert.equal(base.X_BEARER_TOKEN, 'stale-stored-token');
});

test('relationship safety reports missing or malformed Keychain tokens without leaking secret diagnostics', async () => {
  await assert.rejects(configureRelationshipSafetyEnvironment({}, {withRelationshipSafety: true}, {
    readSecret: async () => { throw new Error('private-command-output fixture-x-bearer-token'); },
  }), error => {
    assert.equal(error.message, 'Keychain item trimmy-x-bearer-token is unavailable.');
    assert.doesNotMatch(error.message, /private-command-output|fixture-x-bearer-token/);
    return true;
  });
  await assert.rejects(configureRelationshipSafetyEnvironment({}, {withRelationshipSafety: true}, {
    readSecret: async () => { throw new RuntimeError('Keychain secret is malformed.'); },
  }), {message: 'Keychain X bearer token is malformed.'});
  for (const bearerToken of ['', 'private token', 'private\ntoken', 'private-token\n',
    'x'.repeat(4097), null]) {
    await assert.rejects(configureRelationshipSafetyEnvironment({}, {withRelationshipSafety: true}, {
      readSecret: async () => bearerToken,
    }), {message: 'Keychain X bearer token is malformed.'});
  }
});

test('relationship safety startup matches the readiness-gated public config', () => {
  assert.doesNotThrow(() => assertRelationshipSafetyStarted(
    {relationshipSafetyEnabled: false}, {},
  ));
  assert.doesNotThrow(() => assertRelationshipSafetyStarted(
    {relationshipSafetyEnabled: true}, {withRelationshipSafety: true},
  ));
  assert.throws(() => assertRelationshipSafetyStarted(
    {relationshipSafetyEnabled: false}, {withRelationshipSafety: true},
  ), /live readiness dependencies/);
  assert.throws(() => assertRelationshipSafetyStarted(
    {relationshipSafetyEnabled: false}, {withRelationshipSafety: true}, {alreadyRunning: true},
  ), /running API.*readiness proof failed.*Stop the runtime/);
  assert.throws(() => assertRelationshipSafetyStarted(
    {relationshipSafetyEnabled: true}, {}, {alreadyRunning: true},
  ), /running API has relationship safety enabled.*without --with-relationship-safety/);
  assert.throws(() => assertRelationshipSafetyStarted(
    {relationshipSafetyEnabled: true}, {},
  ), /Default local startup did not keep relationship safety disabled/);
});

test('default startup removes stale wallet opt-ins without reading a secret or mutating stored config', async () => {
  const base = Object.freeze({PRIVY_APP_ID: 'app', TRIMMY_WALLET_POSSESSION: 'single_process', TRIMMY_WALLET_NETWORK: 'mainnet-beta'});
  const calls = [];
  const result = await configureWalletChecksEnvironment(base, {}, {readSecret: async service => {calls.push(service); throw new Error('must not read');}});
  assert.deepEqual(result, {PRIVY_APP_ID: 'app'});
  assert.deepEqual(calls, []);
  assert.equal(base.TRIMMY_WALLET_POSSESSION, 'single_process');
});

test('wallet opt-in loads exactly the existing Keychain app secret in memory and only the two proof settings', async () => {
  for (const withAppSecret of [false, true]) {
    const base = Object.freeze({PRIVY_APP_ID: 'app', PRIVY_VERIFICATION_KEY: 'public-key', PRACTICE_DATABASE_URL: 'private-db'});
    const calls = [];
    const result = await configureWalletChecksEnvironment(base, {withWalletChecks: true, withAppSecret}, {
      readSecret: async service => {calls.push(service); return 'fixture-private-secret';},
    });
    assert.deepEqual(calls, ['trimmy-privy-app-secret']);
    assert.deepEqual(result, {...base, PRIVY_APP_SECRET: 'fixture-private-secret',
      TRIMMY_WALLET_POSSESSION: 'single_process', TRIMMY_WALLET_NETWORK: 'mainnet-beta'});
    assert.equal(Object.hasOwn(base, 'PRIVY_APP_SECRET'), false);
    assert.equal(Object.hasOwn(base, 'TRIMMY_WALLET_POSSESSION'), false);
    assert.ok(!Object.keys(result).some(key => /TRAD|SWAP|TRANSFER|FUNDED|FINANCIAL/.test(key)));
  }
});

test('the existing app-secret flag does not also enable wallet proof', async () => {
  const result = await configureWalletChecksEnvironment({PRIVY_APP_ID: 'app'}, {withAppSecret: true}, {
    readSecret: async () => 'fixture-private-secret',
  });
  assert.deepEqual(result, {PRIVY_APP_ID: 'app', PRIVY_APP_SECRET: 'fixture-private-secret'});
});

test('missing or malformed Keychain values fail without leaking command output or secret bytes', async () => {
  await assert.rejects(configureWalletChecksEnvironment({}, {withWalletChecks: true}, {
    readSecret: async () => {throw new Error('private-command-output fixture-private-secret');},
  }), error => {
    assert.match(error.message, /Keychain item trimmy-privy-app-secret is unavailable/);
    assert.doesNotMatch(error.message, /private-command-output|fixture-private-secret/);
    return true;
  });
  for (const secret of ['', 'private\nsecret', 'private-secret\n', 'x'.repeat(4097), null]) {
    await assert.rejects(configureWalletChecksEnvironment({}, {withWalletChecks: true}, {readSecret: async () => secret}),
      {message: 'Keychain app secret is malformed.'});
  }
});

const walletConfig = () => ({walletPossessionEnabled: true, moneyMode: 'practice_only', capabilities: {
  financialOperationsEnabled: false, liveWalletsEnabled: false, fundedGiftsEnabled: false, swapsEnabled: false,
}});

test('an existing API with wallet checks disabled reports the requested-mode mismatch', () => {
  assert.throws(() => assertWalletChecksStarted({...walletConfig(), walletPossessionEnabled: false}, {withWalletChecks: true}, {alreadyRunning: true}),
    /running API.*disabled.*Stop the runtime.*--with-wallet-checks/);
  assert.throws(() => assertWalletChecksStarted({}, {withWalletChecks: true}), /API did not enable/);
  assert.doesNotThrow(() => assertWalletChecksStarted(walletConfig(), {withWalletChecks: true}, {alreadyRunning: true}));
  assert.doesNotThrow(() => assertWalletChecksStarted({}, {}));
});

test('a successful wallet opt-in must still report all financial capabilities disabled', () => {
  assert.doesNotThrow(() => assertWalletChecksStarted(walletConfig(), {withWalletChecks: true}));
  for (const key of Object.keys(walletConfig().capabilities)) {
    for (const value of [true, undefined]) {
      const config = walletConfig();
      config.capabilities[key] = value;
      assert.throws(() => assertWalletChecksStarted(config, {withWalletChecks: true}), /must not enable financial/);
    }
  }
  assert.throws(() => assertWalletChecksStarted({...walletConfig(), moneyMode: 'live'}, {withWalletChecks: true}), /must not enable financial/);
});

test('runtime paths keep every private artifact under one root', () => {
  const paths = runtimePaths('/private/root');
  for (const value of Object.values(paths)) assert.ok(value.startsWith('/private/root'), value);
  assert.equal(paths.apiEnv, '/private/root/api.env');
  assert.equal(paths.redDayWorkerEnv, '/private/root/red-day-worker.env');
  assert.equal(paths.caCert, '/private/root/tls/ca.crt');
});

test('database URL encodes the password and rejects weak or malformed parts', () => {
  const url = buildDatabaseUrl({user: RUNTIME_ROLE, password: 'a1b2c3d4e5f6a7b8c9d0#/?@', host: '127.0.0.1', port: 54329, database: DATABASE});
  const parsed = new URL(url);
  assert.equal(decodeURIComponent(parsed.password), 'a1b2c3d4e5f6a7b8c9d0#/?@');
  assert.equal(parsed.username, RUNTIME_ROLE);
  assert.equal(parsed.port, '54329');
  assert.equal(parsed.pathname, `/${DATABASE}`);
  assert.equal(parsed.search, '');
  assert.throws(() => buildDatabaseUrl({user: RUNTIME_ROLE, password: 'short', host: '127.0.0.1', port: 54329, database: DATABASE}), /Invalid password/);
  assert.throws(() => buildDatabaseUrl({user: 'bad role', password: 'a1b2c3d4e5f6a7b8c9d0', host: '127.0.0.1', port: 54329, database: DATABASE}), /Invalid user/); // gitleaks:allow -- non-secret deterministic test value
  assert.throws(() => buildDatabaseUrl({user: RUNTIME_ROLE, password: 'a1b2c3d4e5f6a7b8c9d0', host: '127.0.0.1', port: 0, database: DATABASE}), /Invalid port/); // gitleaks:allow -- non-secret deterministic test value
});

test('PostgreSQL configuration is loopback, TLS-only and SCRAM with plaintext rejected', () => {
  const conf = renderPostgresConf({port: 54329, socketDir: '/private/root/postgres/socket', certFile: '/c.crt', keyFile: '/c.key'});
  assert.match(conf, /listen_addresses = '127\.0\.0\.1'/);
  assert.match(conf, /ssl = on/);
  assert.match(conf, /ssl_min_protocol_version = 'TLSv1\.2'/);
  assert.match(conf, /password_encryption = scram-sha-256/);
  const hba = renderHba({owner: OWNER_ROLE, runtimeRole: RUNTIME_ROLE, database: DATABASE});
  const lines = hba.trim().split('\n').filter(line => !line.startsWith('#'));
  assert.ok(lines.every(line => /scram-sha-256$|reject$/.test(line)), hba);
  assert.ok(lines.some(line => line.startsWith(`hostssl ${DATABASE}  ${RUNTIME_ROLE}`)));
  assert.ok(lines.some(line => line.startsWith(`hostssl ${DATABASE}  ${RED_DAY_WORKER_ROLE}`)));
  assert.ok(!lines.some(line => /\btrust\b|\bmd5\b|\bpassword\b/.test(line)));
  assert.ok(lines.some(line => line.startsWith('hostnossl') && line.endsWith('reject')));
});

test('API environment file round-trips and rejects malformed lines or multi-line values', () => {
  const {publicKey} = generateKeyPairSync('ec', {namedCurve: 'prime256v1'});
  const pem = publicKey.export({type: 'spki', format: 'pem'}).toString();
  const entries = {HOST: '127.0.0.1', PORT: '4443', PRIVY_VERIFICATION_KEY: escapeVerificationKey(pem), PRACTICE_DATABASE_URL: 'postgresql://u:p@127.0.0.1:1/db'};
  const text = renderApiEnv(entries);
  assert.ok(text.startsWith('# Private'));
  assert.deepEqual(parseApiEnv(text), entries);
  assert.equal(parseApiEnv(text).PRIVY_VERIFICATION_KEY.includes('\n'), false);
  assert.throws(() => renderApiEnv({BAD_KEY: 'line\nbreak'}), /Invalid environment entry/);
  assert.throws(() => renderApiEnv({'lower': 'x'}), /Invalid environment entry/);
  assert.throws(() => parseApiEnv('NOEQUALS\n'), /invalid/);
  assert.throws(() => parseApiEnv('A=1\nA=2\n'), /invalid/);
});

test('runtime migration upgrades an old private api.env once without printing or rotating its source key', () => {
  const root = join(dir, 'upgrade-runtime');
  mkdirSync(root, {recursive: true, mode: 0o700});
  const paths = runtimePaths(root);
  writeFileSync(paths.apiEnv, renderApiEnv({HOST: '127.0.0.1', PORT: '4443'}), {mode: 0o600});
  const key = Buffer.alloc(32, 23).toString('base64url');
  assert.equal(ensureGuestSourceEnvironment(paths, {randomKey: () => key}), true);
  const upgradedText = readFileSync(paths.apiEnv, 'utf8');
  const upgraded = parseApiEnv(upgradedText);
  assert.equal(upgraded.TRIMMY_GUEST_SOURCE_MODE, 'direct');
  assert.equal(upgraded.TRIMMY_GUEST_SOURCE_HMAC_KEY, key);
  assert.equal(upgraded.HOST, '127.0.0.1');
  assert.equal(statSync(paths.apiEnv).mode & 0o777, 0o600);
  assert.equal(ensureGuestSourceEnvironment(paths, {randomKey: () => { throw new Error('must not rotate'); }}), false);
  assert.equal(readFileSync(paths.apiEnv, 'utf8'), upgradedText);
});

test('runtime migration refuses partial guest-source configuration instead of replacing it', () => {
  const root = join(dir, 'partial-runtime');
  mkdirSync(root, {recursive: true, mode: 0o700});
  const paths = runtimePaths(root);
  writeFileSync(paths.apiEnv, renderApiEnv({HOST: '127.0.0.1', TRIMMY_GUEST_SOURCE_MODE: 'direct'}), {mode: 0o600});
  assert.throws(() => ensureGuestSourceEnvironment(paths), /incomplete or invalid/);

  writeFileSync(paths.apiEnv, renderApiEnv({HOST: '127.0.0.1',
    TRIMMY_GUEST_SOURCE_MODE: 'direct',
    TRIMMY_GUEST_SOURCE_HMAC_KEY: Buffer.alloc(33, 9).toString('base64url')}), {mode: 0o600});
  assert.throws(() => ensureGuestSourceEnvironment(paths), /incomplete or invalid/);
});

test('public verifier configuration must be a P-256 public key and a bounded app ID', () => {
  const {publicKey} = generateKeyPairSync('ec', {namedCurve: 'prime256v1'});
  const good = join(dir, 'good.json');
  writeFileSync(good, JSON.stringify({PRIVY_APP_ID: 'app-id_1', PRIVY_VERIFICATION_KEY: publicKey.export({type: 'spki', format: 'pem'}).toString().replaceAll('\n', '\\n')}));
  const verifier = readPublicVerifier(good);
  assert.equal(verifier.appId, 'app-id_1');
  assert.match(verifier.verificationKey, /^-----BEGIN PUBLIC KEY-----\n[\s\S]+-----END PUBLIC KEY-----\n$/);
  const wrongCurve = join(dir, 'wrong.json');
  writeFileSync(wrongCurve, JSON.stringify({PRIVY_APP_ID: 'app', PRIVY_VERIFICATION_KEY: generateKeyPairSync('ed25519').publicKey.export({type: 'spki', format: 'pem'}).toString()}));
  assert.throws(() => readPublicVerifier(wrongCurve), /P-256/);
  const badId = join(dir, 'bad-id.json');
  writeFileSync(badId, JSON.stringify({PRIVY_APP_ID: 'bad id', PRIVY_VERIFICATION_KEY: publicKey.export({type: 'spki', format: 'pem'}).toString()}));
  assert.throws(() => readPublicVerifier(badId), /invalid/);
  assert.throws(() => readPublicVerifier(join(dir, 'missing.json')), /unreadable/);
});

test('the public manifest names ports, roles and migrations but no secret', () => {
  const manifest = JSON.parse(renderManifest({appId: 'app', apiPort: 4443, postgresPort: 54329, caCert: '/root/tls/ca.crt', createdAt: '2026-09-15T00:00:00.000Z'}));
  assert.equal(manifest.containsSecrets, false);
  assert.deepEqual(manifest.migrations, [...MIGRATIONS]);
  assert.equal(manifest.apiOrigin, 'https://127.0.0.1:4443');
  assert.equal(manifest.emulatorOrigin, 'https://10.0.2.2:4443');
  assert.equal(manifest.redDayCapabilityRole, RED_DAY_CAPABILITY_ROLE);
  assert.equal(manifest.redDayWorkerRole, RED_DAY_WORKER_ROLE);
  assert.equal(manifest.socialModeratorRole, SOCIAL_MODERATOR_ROLE);
  assert.equal(JSON.stringify(manifest).includes('password'), false);
});

test('the migration list is ordered and ends at the newest released migration', () => {
  assert.deepEqual([...MIGRATIONS], [...MIGRATIONS].sort());
  assert.equal(MIGRATIONS.at(-1), '0031_live_stock_orders');
  assert.equal(new Set(MIGRATIONS).size, MIGRATIONS.length);
});

test('the runtime grants stay narrow and never touch financial or user tables', () => {
  const grants = runtimeGrants();
  for (const table of ['trimmy.practice_progress', 'trimmy.practice_mutation_receipts', 'trimmy.watchlists',
    'trimmy.watchlist_mutation_receipts', 'trimmy.wallet_bindings', 'trimmy.stock_order_reviews',
    'trimmy.wallet_possession_challenges']) {
    assert.ok(grants.includes(table), table);
  }
  for (const forbidden of ['trimmy.users', 'trimmy.financial_intents', 'trimmy.execution_attempts',
    'trimmy.audit_events', 'ALL TABLES', 'ALL PRIVILEGES', 'PUBLIC']) {
    assert.ok(!grants.includes(forbidden), forbidden);
  }
  // Relationship state is reachable only through bounded definer functions.
  assert.ok(grants.includes('REVOKE ALL ON TABLE trimmy.invitations, trimmy.provider_identities'));
  assert.ok(grants.includes('trimmy.social_invitation_answer(uuid, uuid, bigint, text, text, text, timestamptz)'));
  assert.ok(grants.includes('trimmy.social_friend_remove(uuid, uuid, uuid, text, bigint)'));
  assert.ok(grants.includes('trimmy.social_block_get(uuid, uuid)'));
  assert.ok(grants.includes('trimmy.social_block_put(uuid, uuid, uuid, text, bigint, text)'));
  assert.ok(grants.includes('trimmy.social_reason_report_create(uuid, uuid, text, uuid, text)'));
  assert.ok(grants.includes(`REVOKE ALL ON FUNCTION trimmy.practice_current_user() FROM ${RUNTIME_ROLE}`));
  assert.ok(grants.includes(
    'trimmy.social_bind_verified_x_identity_internal(uuid, text, text, timestamptz)',
  ));
  assert.ok(grants.includes(`trimmy.${SOCIAL_MODERATOR_FUNCTION} FROM ${RUNTIME_ROLE}`));
  assert.ok(!grants.includes(`GRANT EXECUTE ON FUNCTION trimmy.practice_current_user() TO ${RUNTIME_ROLE}`));
  assert.ok(grants.includes('trimmy.social_close_current_account(text)'));
  const invitationGrants = grants.split('; ').filter(statement => statement.includes('trimmy.invitations'));
  assert.equal(invitationGrants.length, 1);
  assert.ok(invitationGrants[0].startsWith('REVOKE ALL ON TABLE'));
  // Closing an account is a definer function, never a privilege on users.
  assert.ok(grants.includes('trimmy.practice_close_current_account()'));
  assert.ok(!/(SELECT|INSERT|UPDATE|DELETE)[^;]*ON trimmy\.users/.test(grants));
  assert.ok(grants.includes('trimmy.career_summary_get(uuid)'));
  assert.ok(grants.includes('trimmy.career_trade_reason_put(uuid, uuid, text, uuid, text)'));
  assert.ok(grants.includes('trimmy.paper_desk_reset(uuid, uuid, text, bigint)'));
  assert.ok(grants.includes('REVOKE ALL ON TABLE trimmy.paper_reset_receipts'));
  assert.ok(grants.includes('trimmy.career_missions_get(uuid)'));
  assert.ok(grants.includes('trimmy.career_promote(uuid, uuid, text, text)'));
  assert.ok(grants.includes('trimmy.career_day_context_get(uuid)'));
  assert.ok(grants.includes('trimmy.career_day_context_put(uuid, uuid, text, bigint, text)'));
  assert.ok(grants.includes('trimmy.career_reason_privacy_get(uuid)'));
  assert.ok(grants.includes('trimmy.career_reason_privacy_put(uuid, uuid, text, bigint, text)'));
  assert.ok(grants.includes(
    'trimmy.career_trade_reason_list(uuid, text, text, text, timestamptz, uuid, integer)',
  ));
  assert.ok(grants.includes(
    'REVOKE ALL ON TABLE trimmy.career_reason_privacy, trimmy.career_reason_privacy_receipts',
  ));
  assert.ok(grants.includes('trimmy.guest_take_creation_attempt(text)'));
  assert.ok(grants.includes('trimmy.guest_create_session(text, bigint, text, text, uuid, text)'));
  assert.ok(grants.includes('trimmy.product_launch_advance(uuid, uuid, text, bigint, text, uuid)'));
  assert.ok(!grants.includes('trimmy.guest_auth_retention'));
  assert.ok(!/(SELECT|INSERT|UPDATE|DELETE)[^;]*ON trimmy\.product_launch_action_receipts/.test(grants));
  for (const table of ['career_profiles', 'career_trim_ledger', 'career_trade_reasons',
    'career_reason_mutation_receipts', 'career_starts', 'career_first_confirmed_buys',
    'career_mission_definitions', 'career_mission_completions', 'career_promotion_receipts',
    'career_day_settings', 'career_day_setting_receipts', 'career_activity_events',
    'career_reason_privacy', 'career_reason_privacy_receipts']) {
    assert.ok(!new RegExp(`(SELECT|INSERT|UPDATE|DELETE)[^;]*ON trimmy\\.${table}`).test(grants), table);
  }
  const grantStatements = grants.split('; ').filter(statement => statement.startsWith('GRANT '));
  for (const signature of RED_DAY_API_DENIED_FUNCTIONS) {
    assert.ok(!grantStatements.some(statement => statement.includes(`trimmy.${signature}`)), signature);
    assert.match(grants, new RegExp(`REVOKE ALL ON FUNCTION [^;]*trimmy\\.${signature.replace(/[()]/g, '\\$&')}`));
  }
  // Bindings and reviews are never deletable, and bindings are never updatable.
  assert.ok(grants.includes(`GRANT SELECT, INSERT ON trimmy.wallet_bindings TO ${RUNTIME_ROLE}`));
  // A wallet challenge is consumed by marking one column, never by removing the
  // row, so the serving role still has no DELETE anywhere in this schema.
  assert.ok(grants.includes(`GRANT SELECT, INSERT ON trimmy.wallet_possession_challenges TO ${RUNTIME_ROLE}`));
  assert.ok(grants.includes(`GRANT UPDATE (consumed_at) ON trimmy.wallet_possession_challenges TO ${RUNTIME_ROLE}`));
  const challengeGrants = grants.split('; ').filter(statement => statement.includes('wallet_possession_challenges'));
  assert.equal(challengeGrants.length, 2);
  // The real followed list is its own storage, granted exactly like the sample
  // one, so a fictional list and a real one can never become the same rows.
  assert.ok(grants.includes(`GRANT SELECT, INSERT, UPDATE ON trimmy.followed_stocks TO ${RUNTIME_ROLE}`));
  assert.ok(grants.includes(`GRANT SELECT, INSERT ON trimmy.followed_stock_mutation_receipts TO ${RUNTIME_ROLE}`));
  assert.ok(grants.includes('trimmy.followed_stock_ids_valid(jsonb)'));
  for (const column of ['wallet_address', 'nonce', 'message', 'expires_at', 'user_id']) {
    assert.ok(!challengeGrants.some(statement => statement.includes(`(${column}`) || statement.includes(` ${column},`)), column);
  }
  assert.ok(!/DELETE/.test(grants));
});

test('red-day authority is an exact function-only capability with a grant-free login', () => {
  const capability = redDayWorkerGrants();
  assert.ok(capability.includes(`REVOKE ALL ON SCHEMA trimmy FROM ${RED_DAY_CAPABILITY_ROLE}`));
  assert.ok(capability.includes(`GRANT USAGE ON SCHEMA trimmy TO ${RED_DAY_CAPABILITY_ROLE}`));
  assert.ok(capability.includes('REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA trimmy'));
  assert.ok(capability.includes('REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA trimmy'));
  assert.ok(capability.includes('REVOKE ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA trimmy'));
  const execute = capability.split('; ').filter(statement => statement.startsWith('GRANT EXECUTE'));
  assert.equal(execute.length, 1);
  for (const signature of RED_DAY_WORKER_FUNCTIONS) {
    assert.ok(execute[0].includes(`trimmy.${signature}`), signature);
  }
  assert.equal((execute[0].match(/trimmy\.career_red_day_/g) ?? []).length,
    RED_DAY_WORKER_FUNCTIONS.length);

  const login = redDayWorkerLoginDenials();
  assert.ok(login.includes(`FROM ${RED_DAY_WORKER_ROLE}`));
  assert.ok(login.includes('ALL TABLES IN SCHEMA trimmy'));
  assert.ok(login.includes('ALL SEQUENCES IN SCHEMA trimmy'));
  assert.ok(login.includes('ALL FUNCTIONS IN SCHEMA trimmy'));
  assert.ok(login.includes('ALL ON SCHEMA trimmy'));
  assert.doesNotMatch(login, /\bGRANT\b/);
});

test('moderation authority is one function on a separate non-login role', () => {
  const grants = socialModeratorGrants();
  assert.ok(grants.includes(`REVOKE ALL ON SCHEMA trimmy FROM ${SOCIAL_MODERATOR_ROLE}`));
  assert.ok(grants.includes(`GRANT USAGE ON SCHEMA trimmy TO ${SOCIAL_MODERATOR_ROLE}`));
  assert.ok(grants.includes('REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA trimmy'));
  assert.ok(grants.includes('REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA trimmy'));
  assert.ok(grants.includes('REVOKE ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA trimmy'));
  const execute = grants.split('; ').filter(statement => statement.startsWith('GRANT EXECUTE'));
  assert.deepEqual(execute, [
    `GRANT EXECUTE ON FUNCTION trimmy.${SOCIAL_MODERATOR_FUNCTION} TO ${SOCIAL_MODERATOR_ROLE}`,
  ]);
  assert.doesNotMatch(grants, new RegExp(`TO ${RUNTIME_ROLE}`));
});
