#!/usr/bin/env node
/**
 * Local secure runtime for the configured Trimmy API.
 *
 * `init` creates a private PostgreSQL cluster that only accepts TLS with SCRAM
 * authentication, applies every registered migration as a separate owner, provisions
 * the narrow `trimmy_practice_runtime` role, issues a local CA plus database and
 * API certificates, and writes the API's private environment file. `start`
 * runs the compiled API over native HTTPS against that database. `status`
 * reports health and account counts without printing any secret. `stop` and
 * `reset --yes` tear down.
 *
 * Everything private lives under ~/.config/trimmy/runtime (mode 0700). Nothing
 * here enables financial operations; the API keeps them disabled regardless.
 */
import { execFile as execFileCallback, spawn } from 'node:child_process';
import { createPublicKey, randomBytes } from 'node:crypto';
import {
  appendFileSync, chmodSync, closeSync, existsSync, mkdirSync, openSync, readFileSync, rmSync, statSync, writeFileSync,
} from 'node:fs';
import { request as httpsRequest } from 'node:https';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

const execFile = promisify(execFileCallback);
const projectDir = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');

export const MIGRATIONS = Object.freeze([
  '0001_foundation', '0002_practice_progress', '0003_practice_accounts',
  '0004_watchlists', '0005_practice_payload_v4', '0006_practice_payload_v5',
  '0007_wallet_possession_and_reviews', '0008_practice_payload_v6',
  '0009_invitations', '0010_account_closure', '0011_wallet_possession_challenges',
  '0012_followed_stocks', '0013_paper_trading',
  '0014_guest_sessions', '0015_product_profiles', '0016_guest_creation_idempotency',
  '0017_career_core', '0018_career_missions_and_promotions', '0019_career_local_day',
  '0020_guest_creation_abuse_and_retention',
  '0021_career_red_day_evidence',
  '0022_product_launch_evidence',
  '0023_paper_reset',
  '0024_career_reason_sharing',
  '0025_relationship_safety',
  '0026_optional_introduction',
  '0027_career_activity_week',
  '0028_community_following',
  '0029_daily_desk',
  '0030_intern_workdays',
  '0031_live_stock_orders',
]);
export const OWNER_ROLE = 'trimmy_runtime_owner';
export const RUNTIME_ROLE = 'trimmy_practice_runtime';
export const RED_DAY_CAPABILITY_ROLE = 'trimmy_red_day_verifier';
export const RED_DAY_WORKER_ROLE = 'trimmy_red_day_worker';
export const SOCIAL_MODERATOR_ROLE = 'trimmy_social_moderator';
export const SOCIAL_MODERATOR_FUNCTION =
  'social_reason_moderation_put(uuid, bigint, text, text, text)';
export const RED_DAY_WORKER_FUNCTIONS = Object.freeze([
  'career_red_day_candidates(integer)',
  'career_red_day_pending_sessions(integer)',
  'career_red_day_process_session(uuid, integer)',
  'career_red_day_record_observation(uuid, text, text, text, text, text, date, date, text, text, timestamptz, timestamptz, text, text, uuid, uuid, text, text, text, text, text, text, timestamptz)',
]);
export const RED_DAY_API_DENIED_FUNCTIONS = Object.freeze([
  ...RED_DAY_WORKER_FUNCTIONS,
  'career_server_mission_complete(uuid, text, uuid, timestamptz)',
  'career_red_day_activate()',
]);
export const DATABASE = 'trimmy';
const DEFAULT_POSTGRES_PORT = 54329;
const DEFAULT_API_PORT = 4443;

export class RuntimeError extends Error {}
const fail = message => { throw new RuntimeError(message); };

export function runtimePaths(root) {
  const postgres = join(root, 'postgres');
  const tls = join(root, 'tls');
  return Object.freeze({
    root, postgres, tls,
    data: join(postgres, 'data'), socket: join(postgres, 'socket'), postgresLog: join(postgres, 'postgres.log'),
    ownerPassword: join(postgres, 'owner.password'),
    caKey: join(tls, 'ca.key'), caCert: join(tls, 'ca.crt'),
    dbKey: join(tls, 'db.key'), dbCert: join(tls, 'db.crt'),
    apiKey: join(tls, 'api.key'), apiCert: join(tls, 'api.crt'),
    apiEnv: join(root, 'api.env'), redDayWorkerEnv: join(root, 'red-day-worker.env'),
    apiPid: join(root, 'api.pid'), apiLog: join(root, 'api.log'),
    manifest: join(root, 'runtime.json'),
  });
}

/** Password bytes are hex so the URL form needs no escaping surprises, but we still encode. */
export function buildDatabaseUrl({user, password, host, port, database}) {
  for (const [name, value] of Object.entries({user, database})) {
    if (typeof value !== 'string' || !/^[a-zA-Z0-9_.-]{1,63}$/.test(value)) fail(`Invalid ${name}.`);
  }
  if (typeof password !== 'string' || password.length < 16 || /[\x00-\x1f\x7f]/.test(password)) fail('Invalid password.');
  if (!Number.isInteger(port) || port < 1 || port > 65535) fail('Invalid port.');
  return `postgresql://${encodeURIComponent(user)}:${encodeURIComponent(password)}@${host}:${port}/${encodeURIComponent(database)}`;
}

export function renderPostgresConf({port, socketDir, certFile, keyFile}) {
  return [
    '', '# Trimmy local secure runtime. Loopback TLS only; plaintext is rejected in pg_hba.conf.',
    `listen_addresses = '127.0.0.1'`, `port = ${port}`, `unix_socket_directories = '${socketDir}'`,
    'ssl = on', `ssl_cert_file = '${certFile}'`, `ssl_key_file = '${keyFile}'`, `ssl_min_protocol_version = 'TLSv1.2'`,
    'password_encryption = scram-sha-256', 'log_connections = on', 'log_min_messages = warning', 'max_connections = 40', '',
  ].join('\n');
}

/** Owner administers over the private socket; the runtime role only over verified TLS. */
export function renderHba({owner, runtimeRole, redDayWorkerRole = RED_DAY_WORKER_ROLE, database}) {
  return [
    '# TYPE  DATABASE  USER  ADDRESS  METHOD',
    `local   all       ${owner}                     scram-sha-256`,
    `hostssl ${database}  ${runtimeRole}  127.0.0.1/32  scram-sha-256`,
    `hostssl ${database}  ${redDayWorkerRole}  127.0.0.1/32  scram-sha-256`,
    `hostssl all       ${owner}        127.0.0.1/32  scram-sha-256`,
    'hostnossl all     all             127.0.0.1/32  reject',
    'hostnossl all     all             ::1/128       reject',
    'host    all       all             0.0.0.0/0     reject',
    'host    all       all             ::/0          reject', '',
  ].join('\n');
}

const envKey = /^[A-Z][A-Z0-9_]{0,63}$/;
export function renderApiEnv(entries) {
  const lines = ['# Private Trimmy API runtime configuration. Mode 0600. Never commit or paste this file.'];
  for (const [key, value] of Object.entries(entries)) {
    if (!envKey.test(key) || typeof value !== 'string' || /[\r\n\x00]/.test(value)) fail(`Invalid environment entry ${key}.`);
    lines.push(`${key}=${value}`);
  }
  return `${lines.join('\n')}\n`;
}

export function parseApiEnv(text) {
  if (typeof text !== 'string' || text.length > 65_536) fail('Environment file is invalid.');
  const entries = {};
  for (const raw of text.split('\n')) {
    const line = raw.replace(/\r$/, '');
    if (line === '' || line.startsWith('#')) continue;
    const index = line.indexOf('=');
    if (index < 1) fail('Environment file is invalid.');
    const key = line.slice(0, index);
    if (!envKey.test(key) || key in entries) fail('Environment file is invalid.');
    entries[key] = line.slice(index + 1);
  }
  return Object.freeze(entries);
}

/** Upgrade an existing private runtime without rotating a previously issued
 * source key. The generated key is written only to api.env and never logged. */
export function ensureGuestSourceEnvironment(paths, {randomKey = () => randomBytes(32).toString('base64url')} = {}) {
  const entries = {...parseApiEnv(readFileSync(paths.apiEnv, 'utf8'))};
  const mode = entries.TRIMMY_GUEST_SOURCE_MODE;
  const key = entries.TRIMMY_GUEST_SOURCE_HMAC_KEY;
  const cidrs = entries.TRIMMY_GUEST_TRUSTED_PROXY_CIDRS;
  if (!mode && !key && !cidrs) {
    const generated = randomKey();
    const bytes = typeof generated === 'string' && /^[A-Za-z0-9_-]+$/.test(generated)
      ? Buffer.from(generated, 'base64url') : Buffer.alloc(0);
    if (bytes.length !== 32 || bytes.toString('base64url') !== generated) {
      fail('Guest source key generation failed.');
    }
    entries.TRIMMY_GUEST_SOURCE_MODE = 'direct';
    entries.TRIMMY_GUEST_SOURCE_HMAC_KEY = generated;
    privateWrite(paths.apiEnv, renderApiEnv(entries));
    return true;
  }
  const bytes = typeof key === 'string' && /^[A-Za-z0-9_-]+$/.test(key)
    ? Buffer.from(key, 'base64url') : Buffer.alloc(0);
  if (!['direct', 'trusted_proxy'].includes(mode) || bytes.length !== 32 ||
      bytes.toString('base64url') !== key || (mode === 'direct' && cidrs) ||
      (mode === 'trusted_proxy' && !cidrs)) {
    fail('Guest source configuration in api.env is incomplete or invalid.');
  }
  return false;
}

/** The API accepts literal \n escapes for the multi-line SPKI key. */
export function escapeVerificationKey(pem) { return pem.trim().replace(/\r?\n/g, '\\n'); }

export function readPublicVerifier(path) {
  let data;
  try { data = JSON.parse(readFileSync(path, 'utf8')); } catch { fail('Public verifier configuration is unreadable.'); }
  const appId = data?.PRIVY_APP_ID;
  const rawKey = data?.PRIVY_VERIFICATION_KEY;
  if (typeof appId !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(appId) || typeof rawKey !== 'string' || rawKey.length > 8192) {
    fail('Public verifier configuration is invalid.');
  }
  const pem = rawKey.replace(/\\n/g, '\n').trim();
  try {
    const key = createPublicKey(pem);
    if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') throw new Error('curve');
  } catch { fail('Public verifier key is not a P-256 public key.'); }
  return Object.freeze({appId, verificationKey: `${pem}\n`});
}

export function renderManifest({appId, apiPort, postgresPort, caCert, createdAt}) {
  return `${JSON.stringify({
    schemaVersion: 1, createdAt, purpose: 'Trimmy local secure runtime (practice accounts only; financial operations disabled)',
    apiOrigin: `https://127.0.0.1:${apiPort}`, emulatorOrigin: `https://10.0.2.2:${apiPort}`, apiPort, postgresPort,
    database: DATABASE, ownerRole: OWNER_ROLE, runtimeRole: RUNTIME_ROLE,
    redDayCapabilityRole: RED_DAY_CAPABILITY_ROLE, redDayWorkerRole: RED_DAY_WORKER_ROLE,
    socialModeratorRole: SOCIAL_MODERATOR_ROLE,
    migrations: MIGRATIONS, tlsCertificateAuthority: caCert,
    privyAppId: appId, containsSecrets: false,
  }, null, 2)}\n`;
}

function postgresBin() {
  const configured = process.env.TRIMMY_POSTGRES_BIN;
  const candidates = [configured, '/opt/homebrew/opt/postgresql@15/bin', '/opt/homebrew/opt/postgresql@16/bin', '/usr/local/opt/postgresql@15/bin'].filter(Boolean);
  for (const dir of candidates) {
    if (['initdb', 'pg_ctl', 'psql'].every(name => existsSync(join(dir, name)))) return dir;
  }
  fail('PostgreSQL 15+ binaries not found. Set TRIMMY_POSTGRES_BIN.');
}

async function run(file, args, options = {}) {
  try {
    return await execFile(file, args, {maxBuffer: 4 * 1024 * 1024, ...options});
  } catch (error) {
    const stderr = typeof error?.stderr === 'string' ? error.stderr.trim().split('\n').slice(-3).join('\n') : '';
    fail(`${file} ${args[0]} failed${stderr ? `: ${stderr}` : '.'}`);
  }
}

/** Runs a command with private stdin so a secret never appears in argv or a file. */
function runWithInput(file, args, input, options = {}) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(file, args, {...options, stdio: ['pipe', 'pipe', 'pipe']});
    let stdout = '';
    let stderr = '';
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data', chunk => { stdout += chunk; });
    child.stderr.on('data', chunk => { stderr += chunk; });
    child.on('error', () => reject(new RuntimeError(`${file} could not start.`)));
    child.on('close', code => {
      if (code === 0) resolvePromise({stdout, stderr});
      else reject(new RuntimeError(`${file} ${args[0]} failed: ${stderr.trim().split('\n').slice(-3).join('\n')}`));
    });
    child.stdin.end(input);
  });
}

function privateWrite(path, content) {
  writeFileSync(path, content, {mode: 0o600});
  chmodSync(path, 0o600);
}

function privateDir(path) {
  mkdirSync(path, {recursive: true, mode: 0o700});
  chmodSync(path, 0o700);
}

async function openssl(args) { return run('openssl', args); }

async function issueCertificates(paths) {
  await openssl(['ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', paths.caKey]);
  chmodSync(paths.caKey, 0o600);
  await openssl(['req', '-x509', '-new', '-key', paths.caKey, '-out', paths.caCert, '-days', '825',
    '-subj', '/CN=Trimmy local runtime CA', '-addext', 'basicConstraints=critical,CA:TRUE', '-addext', 'keyUsage=critical,keyCertSign,cRLSign']);
  for (const [key, cert, san] of [
    [paths.dbKey, paths.dbCert, 'DNS:localhost,IP:127.0.0.1'],
    [paths.apiKey, paths.apiCert, 'DNS:localhost,IP:127.0.0.1,IP:10.0.2.2'],
  ]) {
    const csr = `${cert}.csr`;
    const ext = `${cert}.ext`;
    writeFileSync(ext, `subjectAltName=${san}\nbasicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\n`);
    await openssl(['ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', key]);
    chmodSync(key, 0o600);
    await openssl(['req', '-new', '-key', key, '-out', csr, '-subj', '/CN=localhost']);
    await openssl(['x509', '-req', '-in', csr, '-CA', paths.caCert, '-CAkey', paths.caKey, '-CAcreateserial', '-out', cert, '-days', '825', '-extfile', ext]);
    rmSync(csr, {force: true});
    rmSync(ext, {force: true});
  }
}

function pgctl(bin, paths, args, options = {}) {
  return run(join(bin, 'pg_ctl'), ['-D', paths.data, ...args], options);
}

async function clusterRunning(bin, paths) {
  try { await execFile(join(bin, 'pg_ctl'), ['-D', paths.data, 'status']); return true; } catch { return false; }
}

async function startCluster(bin, paths) {
  if (await clusterRunning(bin, paths)) return false;
  await pgctl(bin, paths, ['-l', paths.postgresLog, '-w', '-t', '30', 'start']);
  return true;
}

function ownerEnv(paths) {
  const password = readFileSync(paths.ownerPassword, 'utf8').trim();
  return {PATH: process.env.PATH, HOME: process.env.HOME, PGPASSWORD: password, PGSSLMODE: 'disable'};
}

const ownerArgs = paths => ['-X', '-v', 'ON_ERROR_STOP=1', '-h', paths.socket, '-p', String(postgresPort()), '-U', OWNER_ROLE];

function ownerPsql(bin, paths, args, options = {}) {
  return run(join(bin, 'psql'), [...ownerArgs(paths), ...args], {...options, env: ownerEnv(paths)});
}

/** Read-only owner query for harnesses and status; returns rows split on '|'. */
export async function ownerQueryRows(paths, sql) {
  const bin = postgresBin();
  const result = await ownerPsql(bin, paths, ['-d', DATABASE, '-Atc', sql]);
  return result.stdout.trim().split('\n').filter(Boolean).map(line => line.split('|'));
}

/** Scripts read from stdin interpolate psql variables; -c deliberately does not. */
function ownerPsqlScript(bin, paths, database, script) {
  return runWithInput(join(bin, 'psql'), [...ownerArgs(paths), '-d', database, '-f', '-'], script, {env: ownerEnv(paths)});
}

function redDayWorkerEnvironment(paths, password) {
  return renderApiEnv({
    TRIMMY_RED_DAY_DATABASE_URL: buildDatabaseUrl({user: RED_DAY_WORKER_ROLE,
      password, host: '127.0.0.1', port: postgresPort(), database: DATABASE}),
    TRIMMY_RED_DAY_DATABASE_CA_FILE: paths.caCert,
    TRIMMY_RED_DAY_CAPABILITY_ROLE: RED_DAY_CAPABILITY_ROLE,
    TRIMMY_RED_DAY_ASSET_CATALOG_JSON: '{"apple":"AAPL"}',
    TRIMMY_RED_DAY_CANDIDATE_LIMIT: '20',
    TRIMMY_RED_DAY_EVIDENCE_BATCH_LIMIT: '50',
  }).replace('Private Trimmy API runtime configuration',
    'Private Trimmy red-day worker configuration');
}

async function assertLocalRedDayRoleShape(paths) {
  const roles = await ownerQueryRows(paths, `SELECT rolname, rolcanlogin, rolinherit,
    rolsuper, rolcreatedb, rolcreaterole, rolreplication, rolbypassrls
    FROM pg_catalog.pg_roles
    WHERE rolname IN ('${RED_DAY_CAPABILITY_ROLE}','${RED_DAY_WORKER_ROLE}')
    ORDER BY rolname`);
  const expected = [
    [RED_DAY_CAPABILITY_ROLE, 'f', 'f', 'f', 'f', 'f', 'f', 'f'],
    [RED_DAY_WORKER_ROLE, 't', 'f', 'f', 'f', 'f', 'f', 'f'],
  ];
  if (JSON.stringify(roles) !== JSON.stringify(expected)) {
    fail('Red-day database roles do not have the required least-privilege shape.');
  }
  const membership = await ownerQueryRows(paths, `WITH RECURSIVE reachable(oid) AS (
      SELECT oid FROM pg_catalog.pg_roles WHERE rolname='${RED_DAY_WORKER_ROLE}'
      UNION
      SELECT membership.roleid FROM pg_catalog.pg_auth_members membership
      JOIN reachable reachable_role ON reachable_role.oid=membership.member
    )
    SELECT coalesce(string_agg(role_row.rolname, ',' ORDER BY role_row.rolname), '')
    FROM reachable JOIN pg_catalog.pg_roles role_row ON role_row.oid=reachable.oid
    WHERE role_row.rolname <> '${RED_DAY_WORKER_ROLE}'`);
  if (membership[0]?.[0] !== RED_DAY_CAPABILITY_ROLE) {
    fail('Red-day worker must belong directly and only to its capability role.');
  }
  const membershipEdge = await ownerQueryRows(paths, `SELECT count(*),
      coalesce(bool_or(m.admin_option),false),
      coalesce(bool_or(CASE WHEN to_jsonb(m) ? 'inherit_option'
        THEN (to_jsonb(m)->>'inherit_option')::boolean ELSE false END),false),
      coalesce(bool_and(CASE WHEN to_jsonb(m) ? 'set_option'
        THEN (to_jsonb(m)->>'set_option')::boolean ELSE true END),true)
    FROM pg_catalog.pg_auth_members m
    JOIN pg_catalog.pg_roles granted ON granted.oid=m.roleid
    JOIN pg_catalog.pg_roles member_role ON member_role.oid=m.member
    WHERE granted.rolname='${RED_DAY_CAPABILITY_ROLE}'
      AND member_role.rolname='${RED_DAY_WORKER_ROLE}'`);
  if (JSON.stringify(membershipEdge) !== JSON.stringify([['1', 'f', 'f', 't']])) {
    fail('Red-day worker membership must be one non-admin SET ROLE edge.');
  }
  const ingress = await ownerQueryRows(paths, `WITH RECURSIVE ingress(oid) AS (
      SELECT oid FROM pg_catalog.pg_roles WHERE rolname='${RED_DAY_CAPABILITY_ROLE}'
      UNION
      SELECT membership.member FROM pg_catalog.pg_auth_members membership
      JOIN ingress granted_role ON granted_role.oid=membership.roleid
    )
    SELECT coalesce(string_agg(role_row.rolname, ',' ORDER BY role_row.rolname), '')
    FROM ingress JOIN pg_catalog.pg_roles role_row ON role_row.oid=ingress.oid
    WHERE role_row.rolname <> '${RED_DAY_CAPABILITY_ROLE}'`);
  if (ingress[0]?.[0] !== RED_DAY_WORKER_ROLE) {
    fail('Only the dedicated red-day worker may reach the capability role.');
  }
  const owned = await ownerQueryRows(paths, `SELECT
    (SELECT count(*) FROM pg_catalog.pg_database d JOIN pg_catalog.pg_roles r ON r.oid=d.datdba
      WHERE r.rolname IN ('${RED_DAY_CAPABILITY_ROLE}','${RED_DAY_WORKER_ROLE}')) +
    (SELECT count(*) FROM pg_catalog.pg_namespace n JOIN pg_catalog.pg_roles r ON r.oid=n.nspowner
      WHERE r.rolname IN ('${RED_DAY_CAPABILITY_ROLE}','${RED_DAY_WORKER_ROLE}')) +
    (SELECT count(*) FROM pg_catalog.pg_class c JOIN pg_catalog.pg_roles r ON r.oid=c.relowner
      WHERE r.rolname IN ('${RED_DAY_CAPABILITY_ROLE}','${RED_DAY_WORKER_ROLE}')) +
    (SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
      WHERE r.rolname IN ('${RED_DAY_CAPABILITY_ROLE}','${RED_DAY_WORKER_ROLE}'))`);
  if (owned[0]?.[0] !== '0') fail('Red-day roles must not own database objects.');
}

async function ensureLocalRedDayRoles(bin, paths) {
  const present = await ownerQueryRows(paths, `SELECT rolname FROM pg_catalog.pg_roles
    WHERE rolname IN ('${RED_DAY_CAPABILITY_ROLE}','${RED_DAY_WORKER_ROLE}') ORDER BY rolname`);
  if (present.length === 1) fail('Red-day database role provisioning is partial.');
  if (present.length === 2) {
    if (!existsSync(paths.redDayWorkerEnv)) fail('Red-day worker configuration is missing.');
    await assertLocalRedDayRoleShape(paths);
    return false;
  }
  if (existsSync(paths.redDayWorkerEnv)) fail('Red-day worker configuration exists without its database roles.');
  const password = randomBytes(24).toString('hex');
  await ownerPsqlScript(bin, paths, DATABASE,
    `\\set pw '${password}'\n`
    + `CREATE ROLE ${RED_DAY_CAPABILITY_ROLE} NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;\n`
    + `CREATE ROLE ${RED_DAY_WORKER_ROLE} LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS PASSWORD :'pw';\n`
    + `GRANT ${RED_DAY_CAPABILITY_ROLE} TO ${RED_DAY_WORKER_ROLE};\n`);
  privateWrite(paths.redDayWorkerEnv, redDayWorkerEnvironment(paths, password));
  await assertLocalRedDayRoleShape(paths);
  return true;
}

async function ensureLocalSocialModeratorRole(bin, paths) {
  const roles = await ownerQueryRows(paths, `SELECT rolname, rolcanlogin, rolinherit,
      rolsuper, rolcreatedb, rolcreaterole, rolreplication, rolbypassrls
    FROM pg_catalog.pg_roles WHERE rolname='${SOCIAL_MODERATOR_ROLE}'`);
  if (roles.length === 0) {
    await ownerPsql(bin, paths, ['-d', DATABASE, '-c',
      `CREATE ROLE ${SOCIAL_MODERATOR_ROLE} NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS`]);
  } else if (JSON.stringify(roles) !== JSON.stringify([[
    SOCIAL_MODERATOR_ROLE, 'f', 'f', 'f', 'f', 'f', 'f', 'f',
  ]])) {
    fail('Social moderator role does not have the required least-privilege shape.');
  }
  const unsafe = await ownerQueryRows(paths, `SELECT
    pg_catalog.pg_has_role('${RUNTIME_ROLE}','${SOCIAL_MODERATOR_ROLE}','MEMBER'),
    (SELECT count(*) FROM pg_catalog.pg_auth_members m
      JOIN pg_catalog.pg_roles granted ON granted.oid=m.roleid
      WHERE granted.rolname='${SOCIAL_MODERATOR_ROLE}'),
    (SELECT count(*) FROM pg_catalog.pg_auth_members m
      JOIN pg_catalog.pg_roles member_role ON member_role.oid=m.member
      WHERE member_role.rolname='${SOCIAL_MODERATOR_ROLE}'),
    (SELECT count(*) FROM pg_catalog.pg_database d JOIN pg_catalog.pg_roles r ON r.oid=d.datdba
      WHERE r.rolname='${SOCIAL_MODERATOR_ROLE}') +
    (SELECT count(*) FROM pg_catalog.pg_namespace n JOIN pg_catalog.pg_roles r ON r.oid=n.nspowner
      WHERE r.rolname='${SOCIAL_MODERATOR_ROLE}') +
    (SELECT count(*) FROM pg_catalog.pg_class c JOIN pg_catalog.pg_roles r ON r.oid=c.relowner
      WHERE r.rolname='${SOCIAL_MODERATOR_ROLE}') +
    (SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
      WHERE r.rolname='${SOCIAL_MODERATOR_ROLE}')`);
  if (JSON.stringify(unsafe) !== JSON.stringify([['f', '0', '0', '0']])) {
    fail('Social moderator role must have no members, ownership or API reachability.');
  }
}

async function verifyLocalSocialModeratorBoundary(paths) {
  const result = await ownerQueryRows(paths, `SELECT
    has_schema_privilege('${SOCIAL_MODERATOR_ROLE}','trimmy','USAGE'),
    has_schema_privilege('${SOCIAL_MODERATOR_ROLE}','trimmy','CREATE'),
    (SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='trimmy' AND has_function_privilege('${SOCIAL_MODERATOR_ROLE}',p.oid,'EXECUTE')),
    (SELECT count(*) FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='trimmy' AND c.relkind IN ('r','p','v','m','f') AND (
        has_table_privilege('${SOCIAL_MODERATOR_ROLE}',c.oid,'SELECT') OR
        has_table_privilege('${SOCIAL_MODERATOR_ROLE}',c.oid,'INSERT') OR
        has_table_privilege('${SOCIAL_MODERATOR_ROLE}',c.oid,'UPDATE') OR
        has_table_privilege('${SOCIAL_MODERATOR_ROLE}',c.oid,'DELETE') OR
        has_table_privilege('${SOCIAL_MODERATOR_ROLE}',c.oid,'TRUNCATE') OR
        has_table_privilege('${SOCIAL_MODERATOR_ROLE}',c.oid,'REFERENCES') OR
        has_table_privilege('${SOCIAL_MODERATOR_ROLE}',c.oid,'TRIGGER'))),
    has_function_privilege('${SOCIAL_MODERATOR_ROLE}',
      'trimmy.${SOCIAL_MODERATOR_FUNCTION}','EXECUTE'),
    pg_catalog.pg_has_role('${RUNTIME_ROLE}','${SOCIAL_MODERATOR_ROLE}','MEMBER')`);
  if (JSON.stringify(result) !== JSON.stringify([['t', 'f', '1', '0', 't', 'f']])) {
    fail('Social moderator authority is not the exact function-only surface.');
  }
}

async function verifyLocalRedDayBoundary(bin, paths) {
  await assertLocalRedDayRoleShape(paths);
  const apiExposure = await ownerQueryRows(paths, `SELECT count(*) FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='trimmy' AND p.proname IN
      ('career_red_day_candidates','career_red_day_pending_sessions',
       'career_red_day_process_session','career_red_day_record_observation',
       'career_server_mission_complete','career_red_day_activate')
      AND has_function_privilege('${RUNTIME_ROLE}',p.oid,'EXECUTE')`);
  if (apiExposure[0]?.[0] !== '0') fail('API runtime role can execute red-day internal functions.');
  const entries = parseApiEnv(readFileSync(paths.redDayWorkerEnv, 'utf8'));
  const parsed = new URL(entries.TRIMMY_RED_DAY_DATABASE_URL);
  const password = decodeURIComponent(parsed.password);
  const env = {PATH: process.env.PATH, HOME: process.env.HOME, PGPASSWORD: password};
  const connection = `host=127.0.0.1 port=${postgresPort()} dbname=${DATABASE} user=${RED_DAY_WORKER_ROLE} sslmode=verify-full sslrootcert=${paths.caCert}`;
  const direct = await run(join(bin, 'psql'), ['-X', '-Atc',
    'SELECT ssl, session_user, current_user FROM pg_stat_ssl WHERE pid=pg_backend_pid()', connection], {env});
  if (direct.stdout.trim() !== `t|${RED_DAY_WORKER_ROLE}|${RED_DAY_WORKER_ROLE}`) {
    fail('Red-day worker did not connect over verified TLS as its dedicated login.');
  }
  const directPrivilegeSql = `SELECT
    has_schema_privilege(current_user,'trimmy','USAGE'),
    has_schema_privilege(current_user,'trimmy','CREATE'),
    (SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='trimmy' AND has_function_privilege(current_user,p.oid,'EXECUTE')),
    (SELECT count(*) FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='trimmy' AND c.relkind IN ('r','p','v','m','f') AND (
        has_table_privilege(current_user,c.oid,'SELECT') OR has_table_privilege(current_user,c.oid,'INSERT') OR
        has_table_privilege(current_user,c.oid,'UPDATE') OR has_table_privilege(current_user,c.oid,'DELETE') OR
        has_table_privilege(current_user,c.oid,'TRUNCATE') OR has_table_privilege(current_user,c.oid,'REFERENCES') OR
        has_table_privilege(current_user,c.oid,'TRIGGER'))),
    (SELECT count(*) FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='trimmy' AND c.relkind='S' AND (
        has_sequence_privilege(current_user,c.oid,'USAGE') OR
        has_sequence_privilege(current_user,c.oid,'SELECT') OR
        has_sequence_privilege(current_user,c.oid,'UPDATE')))`;
  const directPrivileges = await run(join(bin, 'psql'), ['-X', '-Atc', directPrivilegeSql, connection], {env});
  if (directPrivileges.stdout.trim() !== 'f|f|0|0|0') {
    fail('Red-day worker login has direct database privileges.');
  }
  let directExecuteDenied = false;
  try {
    await execFile(join(bin, 'psql'), ['-X', '-Atc',
      'SELECT * FROM trimmy.career_red_day_candidates(1)', connection], {env});
  } catch { directExecuteDenied = true; }
  if (!directExecuteDenied) fail('NOINHERIT red-day worker can execute before SET ROLE.');
  const expectedFunctions = RED_DAY_WORKER_FUNCTIONS
    .map(signature => `'trimmy.${signature}'`).join(',');
  const boundarySql = `SET ROLE ${RED_DAY_CAPABILITY_ROLE};
    SELECT
      has_schema_privilege(current_user,'trimmy','USAGE'),
      has_schema_privilege(current_user,'trimmy','CREATE'),
      (SELECT count(*) FROM pg_catalog.pg_proc p
        JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='trimmy' AND has_function_privilege(current_user,p.oid,'EXECUTE')),
      (SELECT count(*) FROM unnest(ARRAY[${expectedFunctions}]) AS expected(signature)
        WHERE pg_catalog.to_regprocedure(expected.signature) IS NOT NULL
          AND has_function_privilege(current_user,
            pg_catalog.to_regprocedure(expected.signature),'EXECUTE')),
      (SELECT count(*) FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='trimmy' AND c.relkind IN ('r','p','v','m','f') AND (
          has_table_privilege(current_user,c.oid,'SELECT') OR
          has_table_privilege(current_user,c.oid,'INSERT') OR
          has_table_privilege(current_user,c.oid,'UPDATE') OR
          has_table_privilege(current_user,c.oid,'DELETE') OR
          has_table_privilege(current_user,c.oid,'TRUNCATE') OR
          has_table_privilege(current_user,c.oid,'REFERENCES') OR
          has_table_privilege(current_user,c.oid,'TRIGGER'))),
      (SELECT count(*) FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='trimmy' AND c.relkind='S' AND (
          has_sequence_privilege(current_user,c.oid,'USAGE') OR
          has_sequence_privilege(current_user,c.oid,'SELECT') OR
          has_sequence_privilege(current_user,c.oid,'UPDATE')))`;
  // Quiet mode suppresses the command-status line emitted by the leading
  // `SET ROLE`; stdout then contains only the tuple we compare below.
  const boundary = await run(join(bin, 'psql'), ['-X', '-qAtc', boundarySql, connection], {env});
  if (boundary.stdout.trim() !== 't|f|4|4|0|0') {
    fail('Red-day capability does not have exactly four functions and zero table privileges.');
  }
  let plaintextRejected = false;
  try {
    await execFile(join(bin, 'psql'), ['-X', '-Atc', 'SELECT 1',
      connection.replace('sslmode=verify-full', 'sslmode=disable')], {env});
  } catch { plaintextRejected = true; }
  if (!plaintextRejected) fail('Plaintext red-day worker database access was not rejected.');
}

function postgresPort() {
  const raw = process.env.TRIMMY_RUNTIME_PG_PORT ?? String(DEFAULT_POSTGRES_PORT);
  if (!/^\d{4,5}$/.test(raw) || Number(raw) > 65535) fail('TRIMMY_RUNTIME_PG_PORT is invalid.');
  return Number(raw);
}

export const DEFAULT_MAINNET_RPC_URL = 'https://api.mainnet-beta.solana.com';

function apiPort() {
  const raw = process.env.TRIMMY_RUNTIME_API_PORT ?? String(DEFAULT_API_PORT);
  if (!/^\d{2,5}$/.test(raw) || Number(raw) > 65535) fail('TRIMMY_RUNTIME_API_PORT is invalid.');
  return Number(raw);
}

async function init(paths) {
  if (existsSync(paths.data)) fail('Runtime already initialized. Run "reset --yes" first to start over.');
  const bin = postgresBin();
  const verifier = readPublicVerifier(join(homedir(), '.config', 'trimmy', 'privy', 'public-verifier-config.json'));
  privateDir(paths.root);
  privateDir(paths.tls);
  privateDir(paths.postgres);
  privateDir(paths.socket);
  await issueCertificates(paths);

  const ownerPassword = randomBytes(24).toString('hex');
  const runtimePassword = randomBytes(24).toString('hex');
  privateWrite(paths.ownerPassword, `${ownerPassword}\n`);
  const pwfile = join(paths.postgres, 'init.pw');
  privateWrite(pwfile, `${ownerPassword}\n`);
  try {
    await run(join(bin, 'initdb'), ['-D', paths.data, '-A', 'scram-sha-256', `--pwfile=${pwfile}`, '-U', OWNER_ROLE, '--no-locale', '-E', 'UTF8']);
  } finally { rmSync(pwfile, {force: true}); }
  appendFileSync(join(paths.data, 'postgresql.conf'), renderPostgresConf({
    port: postgresPort(), socketDir: paths.socket, certFile: paths.dbCert, keyFile: paths.dbKey,
  }));
  writeFileSync(join(paths.data, 'pg_hba.conf'), renderHba({owner: OWNER_ROLE, runtimeRole: RUNTIME_ROLE, database: DATABASE}));

  await startCluster(bin, paths);
  try {
    await ownerPsql(bin, paths, ['-d', 'postgres', '-c', `CREATE DATABASE ${DATABASE}`]);
    // The password travels on stdin only: never in argv, a file or a log line.
    await ownerPsqlScript(bin, paths, DATABASE,
      `\\set pw '${runtimePassword}'\nCREATE ROLE ${RUNTIME_ROLE} LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS PASSWORD :'pw';\n`);
    await ensureLocalRedDayRoles(bin, paths);
    await ensureLocalSocialModeratorRole(bin, paths);
    for (const migration of MIGRATIONS) {
      await ownerPsql(bin, paths, ['-d', DATABASE, '-f', join(projectDir, 'infra', 'migrations', `${migration}.sql`)]);
    }
    await ownerPsql(bin, paths, ['-d', DATABASE, '-c', runtimeGrants()]);
    await ownerPsql(bin, paths, ['-d', DATABASE, '-c', redDayWorkerLoginDenials()]);
    await ownerPsql(bin, paths, ['-d', DATABASE, '-c', redDayWorkerGrants()]);
    await ownerPsql(bin, paths, ['-d', DATABASE, '-c', socialModeratorGrants()]);
    // Prove the runtime role's boundary before writing any configuration.
    const runtimeEnv = {PATH: process.env.PATH, HOME: process.env.HOME, PGPASSWORD: runtimePassword};
    const tlsConn = `host=127.0.0.1 port=${postgresPort()} dbname=${DATABASE} user=${RUNTIME_ROLE} sslmode=verify-full sslrootcert=${paths.caCert}`;
    const ok = await run(join(bin, 'psql'), ['-X', '-Atc', 'SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()', tlsConn], {env: runtimeEnv});
    if (ok.stdout.trim() !== 't') fail('Runtime role did not connect over TLS.');
    let plaintextRejected = false;
    try { await execFile(join(bin, 'psql'), ['-X', '-Atc', 'SELECT 1', `${tlsConn.replace('sslmode=verify-full', 'sslmode=disable')}`], {env: runtimeEnv}); }
    catch { plaintextRejected = true; }
    if (!plaintextRejected) fail('Plaintext database access was not rejected.');
    let usersDenied = false;
    try { await execFile(join(bin, 'psql'), ['-X', '-Atc', 'SELECT count(*) FROM trimmy.users', tlsConn], {env: runtimeEnv}); }
    catch { usersDenied = true; }
    if (!usersDenied) fail('Runtime role can read the users table; grants are too wide.');
    await verifyLocalRedDayBoundary(bin, paths);
    await verifyLocalSocialModeratorBoundary(paths);
    await ownerPsql(bin, paths, ['-d', DATABASE, '-c', RED_DAY_ACTIVATION_SQL]);
  } finally {
    await pgctl(bin, paths, ['-m', 'fast', '-w', 'stop']);
  }

  privateWrite(paths.apiEnv, renderApiEnv({
    HOST: '127.0.0.1', PORT: String(apiPort()), LOG_LEVEL: 'info',
    PRIVY_APP_ID: verifier.appId, PRIVY_VERIFICATION_KEY: escapeVerificationKey(verifier.verificationKey),
    PRACTICE_DATABASE_URL: buildDatabaseUrl({user: RUNTIME_ROLE, password: runtimePassword, host: '127.0.0.1', port: postgresPort(), database: DATABASE}),
    PRACTICE_DATABASE_CA_FILE: paths.caCert, TRIMMY_TLS_CERT_FILE: paths.apiCert, TRIMMY_TLS_KEY_FILE: paths.apiKey,
    TRIMMY_GUEST_SOURCE_MODE: 'direct', TRIMMY_GUEST_SOURCE_HMAC_KEY: randomBytes(32).toString('base64url'),
  }));
  writeFileSync(paths.manifest, renderManifest({appId: verifier.appId, apiPort: apiPort(), postgresPort: postgresPort(), caCert: paths.caCert, createdAt: new Date().toISOString()}));
  console.log(`Initialized ${paths.root}: ${MIGRATIONS.length} migrations applied, TLS-only PostgreSQL on 127.0.0.1:${postgresPort()}, API and red-day worker roles verified.`);
  console.log('Next: node tool/runtime/local-secure-runtime.mjs start');
}

function apiPid(paths) {
  if (!existsSync(paths.apiPid)) return null;
  const pid = Number(readFileSync(paths.apiPid, 'utf8').trim());
  if (!Number.isInteger(pid) || pid < 2) return null;
  try { process.kill(pid, 0); return pid; } catch { return null; }
}

function healthRequest(port, caCert, path) {
  return new Promise(resolvePromise => {
    const req = httpsRequest({host: '127.0.0.1', port, path, ca: readFileSync(caCert), servername: 'localhost', agent: false, timeout: 3000}, response => {
      let body = '';
      response.setEncoding('utf8');
      response.on('data', chunk => { if (body.length < 65_536) body += chunk; });
      response.on('end', () => resolvePromise({status: response.statusCode, body}));
    });
    req.on('timeout', () => { req.destroy(); resolvePromise(null); });
    req.on('error', () => resolvePromise(null));
    req.end();
  });
}

async function readKeychainSecret(service) {
  try {
    const result = await execFile('/usr/bin/security', ['find-generic-password', '-a', 'trimmy', '-s', service, '-w'], {timeout: 5000, maxBuffer: 16_384});
    const value = result.stdout.replace(/\r?\n$/, '');
    if (!/^[\x21-\x7e]{1,4096}$/.test(value)) fail('Keychain secret is malformed.');
    return value;
  } catch (error) {
    if (error instanceof RuntimeError) throw error;
    fail(`Keychain item ${service} is unavailable.`);
  }
}

/** Wallet proof is an explicit, nonfinancial local-process option. Secrets are
 * added only to this returned child environment, never to api.env/manifest. */
export async function configureWalletChecksEnvironment(baseEnv, flags, {readSecret = readKeychainSecret} = {}) {
  const env = {...baseEnv};
  // An old hand-edited runtime file must not silently opt a later start in.
  delete env.TRIMMY_WALLET_POSSESSION;
  delete env.TRIMMY_WALLET_NETWORK;
  if (flags.withAppSecret || flags.withWalletChecks) {
    let secret;
    try { secret = await readSecret('trimmy-privy-app-secret'); } catch {
      fail('Keychain item trimmy-privy-app-secret is unavailable.');
    }
    if (typeof secret !== 'string' || /^[\x21-\x7e]{1,4096}$/.exec(secret)?.[0] !== secret) fail('Keychain app secret is malformed.');
    env.PRIVY_APP_SECRET = secret;
  }
  if (flags.withWalletChecks) {
    env.TRIMMY_WALLET_POSSESSION = 'single_process';
    env.TRIMMY_WALLET_NETWORK = 'mainnet-beta';
  }
  return env;
}

/** Relationship activation is an explicit local-process option. Stored feature
 * or provider values cannot silently activate a later default start. The X
 * bearer exists only in the returned child environment. */
export async function configureRelationshipSafetyEnvironment(
  baseEnv, flags, {readSecret = readKeychainSecret} = {},
) {
  const env = {...baseEnv};
  delete env.TRIMMY_RELATIONSHIP_SAFETY_ENABLED;
  delete env.X_BEARER_TOKEN;
  if (flags.withRelationshipSafety) {
    let bearerToken;
    try {
      bearerToken = await readSecret('trimmy-x-bearer-token');
    } catch (error) {
      if (error instanceof RuntimeError && error.message === 'Keychain secret is malformed.') {
        fail('Keychain X bearer token is malformed.');
      }
      fail('Keychain item trimmy-x-bearer-token is unavailable.');
    }
    if (typeof bearerToken !== 'string' ||
        /^[\x21-\x7e]{1,4096}$/.exec(bearerToken)?.[0] !== bearerToken) {
      fail('Keychain X bearer token is malformed.');
    }
    env.TRIMMY_RELATIONSHIP_SAFETY_ENABLED = 'true';
    env.X_BEARER_TOKEN = bearerToken;
  }
  return env;
}

/** A start command cannot reconfigure an existing process. Verify the public
 * state instead of printing a requested option as though it were applied. */
export function assertWalletChecksStarted(config, flags, {alreadyRunning = false} = {}) {
  if (!flags.withWalletChecks) return;
  if (config?.walletPossessionEnabled !== true) {
    fail(alreadyRunning
      ? 'Wallet checks were requested, but the running API has them disabled or unavailable. Stop the runtime, then start it again with --with-wallet-checks and the other required options.'
      : 'Wallet checks were requested, but the API did not enable them. Check its account configuration before retrying.');
  }
  const capabilities = config?.capabilities;
  if (config.moneyMode !== 'practice_only' || !capabilities ||
      !['financialOperationsEnabled', 'liveWalletsEnabled', 'fundedGiftsEnabled', 'swapsEnabled']
        .every(key => capabilities[key] === false)) {
    fail('Wallet checks must not enable financial capabilities. The API did not report the required disabled state.');
  }
}

/** `/v1/config` reports relationship safety true only when the explicit flag
 * and the live provider, repository, function and grant readiness proof pass. */
export function assertRelationshipSafetyStarted(config, flags, {alreadyRunning = false} = {}) {
  const requested = flags.withRelationshipSafety === true;
  if (config?.relationshipSafetyEnabled === requested) return;
  if (requested) {
    fail(alreadyRunning
      ? 'Relationship safety was requested, but the running API has it disabled or its live readiness proof failed. Stop the runtime, then start it again with --with-relationship-safety and the required provider options.'
      : 'Relationship safety was requested, but the API did not enable it. Check its live readiness dependencies before retrying.');
  }
  fail(alreadyRunning
    ? 'The running API has relationship safety enabled. Stop the runtime, then start it again without --with-relationship-safety.'
    : 'Default local startup did not keep relationship safety disabled.');
}

/** Exactly the grants the migrations document for the runtime role, and no more. */
export function runtimeGrants(role = RUNTIME_ROLE) {
  if (!/^[a-z_][a-z0-9_]{0,62}$/.test(role)) fail('Invalid PostgreSQL role.');
  const redDayFunctions = RED_DAY_API_DENIED_FUNCTIONS.map(signature => `trimmy.${signature}`).join(', ');
  return [
    `GRANT USAGE ON SCHEMA trimmy TO ${role}`,
    `GRANT EXECUTE ON FUNCTION trimmy.practice_account_exists() TO ${role}`,
    `GRANT EXECUTE ON FUNCTION trimmy.practice_find_account(text, text), trimmy.practice_provision_account(text, text) TO ${role}`,
    `GRANT EXECUTE ON FUNCTION trimmy.guest_take_creation_attempt(text), trimmy.guest_create_session(text, bigint, text, text, uuid, text), trimmy.guest_authorize(text, text), trimmy.guest_refresh_session(text), trimmy.guest_claim_session(text, text, text, uuid) TO ${role}`,
    `GRANT EXECUTE ON FUNCTION trimmy.product_profile_get(uuid), trimmy.product_profile_has_confirmed_paper_trade(uuid), trimmy.product_profile_put(uuid, uuid, text, bigint, text, text, text, text, text, text), trimmy.product_launch_advance(uuid, uuid, text, bigint, text, uuid) TO ${role}`,
    // Career state is reachable only through definer functions. The serving
    // role receives no privilege on profiles, reasons, receipts or the ledger.
    `GRANT EXECUTE ON FUNCTION trimmy.live_order_read(uuid,uuid), trimmy.live_order_create(uuid,uuid,text,jsonb,bytea,timestamptz), trimmy.live_order_begin(uuid,uuid,text,text), trimmy.live_order_resolve(uuid,uuid,text), trimmy.workday_read(uuid), trimmy.workday_save(uuid,text,integer,integer,jsonb,text), trimmy.daily_desk_get(uuid), trimmy.daily_desk_complete(uuid,date,text,text), trimmy.community_feed_get(uuid,text,timestamptz,uuid), trimmy.community_follow_set(uuid,uuid,boolean,boolean), trimmy.career_activity_week_get(uuid), trimmy.career_summary_get(uuid), trimmy.career_missions_get(uuid), trimmy.career_trade_reason_put(uuid, uuid, text, uuid, text), trimmy.career_promote(uuid, uuid, text, text), trimmy.career_day_context_get(uuid), trimmy.career_day_context_put(uuid, uuid, text, bigint, text) TO ${role}`,
    `GRANT EXECUTE ON FUNCTION trimmy.career_reason_privacy_get(uuid), trimmy.career_reason_privacy_put(uuid, uuid, text, bigint, text), trimmy.career_trade_reason_list(uuid, text, text, text, timestamptz, uuid, integer) TO ${role}`,
    `REVOKE ALL ON TABLE trimmy.career_reason_privacy, trimmy.career_reason_privacy_receipts FROM ${role}`,
    `GRANT EXECUTE ON FUNCTION trimmy.paper_desk_reset(uuid, uuid, text, bigint) TO ${role}`,
    `REVOKE ALL ON TABLE trimmy.paper_reset_receipts FROM ${role}`,
    `GRANT SELECT, INSERT, UPDATE ON trimmy.practice_progress TO ${role}`,
    `GRANT SELECT, INSERT ON trimmy.practice_mutation_receipts TO ${role}`,
    `GRANT EXECUTE ON FUNCTION trimmy.watchlist_asset_ids_valid(jsonb) TO ${role}`,
    `GRANT SELECT, INSERT, UPDATE ON trimmy.watchlists TO ${role}`,
    `GRANT SELECT, INSERT ON trimmy.watchlist_mutation_receipts TO ${role}`,
    // The real list of looked-up assets. Same shape as the sample list on a
    // separate table, so the two can never merge, and still no DELETE.
    `GRANT EXECUTE ON FUNCTION trimmy.followed_stock_ids_valid(jsonb) TO ${role}`,
    `GRANT SELECT, INSERT, UPDATE ON trimmy.followed_stocks TO ${role}`,
    `GRANT SELECT, INSERT ON trimmy.followed_stock_mutation_receipts TO ${role}`,
    `GRANT SELECT, INSERT ON trimmy.wallet_bindings TO ${role}`,
    `GRANT SELECT, INSERT, UPDATE ON trimmy.stock_order_reviews TO ${role}`,
    // Social state is function-only. Fresh X proof is consumed only by the
    // atomic invitation-answer function, never through table authority.
    `REVOKE ALL ON TABLE trimmy.invitations, trimmy.provider_identities, trimmy.social_profiles, trimmy.social_invitation_create_receipts, trimmy.social_friendships, trimmy.social_friendship_events, trimmy.social_friendship_receipts, trimmy.social_blocks, trimmy.social_block_receipts, trimmy.social_reason_reports, trimmy.social_reason_moderation, trimmy.social_reason_moderation_events, trimmy.social_rate_windows FROM ${role}`,
    `REVOKE ALL ON FUNCTION trimmy.practice_current_user() FROM ${role}`,
    `REVOKE ALL ON FUNCTION trimmy.social_x_subject_valid(text), trimmy.social_profile_maybe_create(), trimmy.social_snapshot_guard(), trimmy.social_friendship_event_pair(), trimmy.social_moderation_event_pair(), trimmy.social_rate_take_internal(uuid, text), trimmy.social_bind_verified_x_identity_internal(uuid, text, text, timestamptz), trimmy.social_activate_friendship_internal(uuid, uuid, uuid, uuid), trimmy.social_rate_windows_prune(timestamptz, integer), trimmy.social_account_close_cleanup_internal(uuid, text), trimmy.scope_invitation_actor(), trimmy.${SOCIAL_MODERATOR_FUNCTION} FROM ${role}`,
    `GRANT EXECUTE ON FUNCTION trimmy.social_invitation_list(uuid, text, text, timestamptz, uuid, integer), trimmy.social_invitation_create(uuid, uuid, text, timestamptz), trimmy.social_invitation_sender_action(uuid, uuid, bigint, text, text, text), trimmy.social_invitation_answer(uuid, uuid, bigint, text, text, text, timestamptz) TO ${role}`,
    `GRANT EXECUTE ON FUNCTION trimmy.social_friend_list(uuid, timestamptz, uuid, integer), trimmy.social_friend_remove(uuid, uuid, uuid, text, bigint), trimmy.social_block_get(uuid, uuid), trimmy.social_block_list(uuid, timestamptz, uuid, integer), trimmy.social_block_put(uuid, uuid, uuid, text, bigint, text), trimmy.social_reason_report_create(uuid, uuid, text, uuid, text) TO ${role}`,
    // Closes only the account named by the verified transaction scope; this
    // adds no table privilege on trimmy.users.
    `GRANT EXECUTE ON FUNCTION trimmy.practice_close_current_account(), trimmy.social_close_current_account(text) TO ${role}`,
    // Durable single-use wallet challenges. Consuming one marks the row rather
    // than removing it, so the serving role still has no DELETE anywhere and
    // cannot erase the record of a challenge it used.
    `GRANT SELECT, INSERT ON trimmy.wallet_possession_challenges TO ${role}`,
    `GRANT UPDATE (consumed_at) ON trimmy.wallet_possession_challenges TO ${role}`,
    // Simulated paper only. These tables have no wallet, transaction or live
    // execution columns, and database triggers bind every commit to a preview.
    `GRANT SELECT, INSERT ON trimmy.paper_accounts TO ${role}`,
    `GRANT UPDATE (cash_micros, revision, updated_at) ON trimmy.paper_accounts TO ${role}`,
    `GRANT SELECT, INSERT ON trimmy.paper_positions TO ${role}`,
    `GRANT UPDATE (symbol, quantity_micros, cost_basis_micros, realized_gain_micros, locked_gain_micros, last_order_revision, updated_at) ON trimmy.paper_positions TO ${role}`,
    `GRANT SELECT, INSERT ON trimmy.paper_order_previews TO ${role}`,
    `GRANT UPDATE (state, committed_at) ON trimmy.paper_order_previews TO ${role}`,
    `GRANT SELECT, INSERT ON trimmy.paper_orders TO ${role}`,
    `GRANT SELECT, INSERT ON trimmy.paper_cash_ledger TO ${role}`,
    // The serving API must never record provider evidence or process a
    // red-day session, even if a previous deployment granted one by mistake.
    `REVOKE ALL ON FUNCTION ${redDayFunctions} FROM ${role}`,
  ].join('; ');
}

/**
 * Exact function-only authority for the NOLOGIN red-day capability role.
 * The worker login is NOINHERIT and must explicitly SET ROLE after proving
 * TLS, role shape and direct membership. No table privilege is necessary
 * because all four bounded functions are security definers.
 */
export function redDayWorkerGrants(role = RED_DAY_CAPABILITY_ROLE) {
  if (!/^[a-z_][a-z0-9_]{0,62}$/.test(role)) fail('Invalid PostgreSQL role.');
  const functions = RED_DAY_WORKER_FUNCTIONS.map(signature => `trimmy.${signature}`).join(', ');
  return [
    `REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA trimmy FROM ${role}`,
    `REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA trimmy FROM ${role}`,
    `REVOKE ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA trimmy FROM ${role}`,
    `REVOKE ALL ON SCHEMA trimmy FROM ${role}`,
    `GRANT USAGE ON SCHEMA trimmy TO ${role}`,
    `GRANT EXECUTE ON FUNCTION ${functions} TO ${role}`,
  ].join('; ');
}

export function redDayWorkerLoginDenials(role = RED_DAY_WORKER_ROLE) {
  if (!/^[a-z_][a-z0-9_]{0,62}$/.test(role)) fail('Invalid PostgreSQL role.');
  return [
    `REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA trimmy FROM ${role}`,
    `REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA trimmy FROM ${role}`,
    `REVOKE ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA trimmy FROM ${role}`,
    `REVOKE ALL ON SCHEMA trimmy FROM ${role}`,
  ].join('; ');
}

/** Exact function-only authority for the separate NOLOGIN moderation role. */
export function socialModeratorGrants(role = SOCIAL_MODERATOR_ROLE) {
  if (!/^[a-z_][a-z0-9_]{0,62}$/.test(role)) fail('Invalid PostgreSQL role.');
  return [
    `REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA trimmy FROM ${role}`,
    `REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA trimmy FROM ${role}`,
    `REVOKE ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA trimmy FROM ${role}`,
    `REVOKE ALL ON SCHEMA trimmy FROM ${role}`,
    `GRANT USAGE ON SCHEMA trimmy TO ${role}`,
    `GRANT EXECUTE ON FUNCTION trimmy.${SOCIAL_MODERATOR_FUNCTION} TO ${role}`,
  ].join('; ');
}

export const RED_DAY_ACTIVATION_SQL = 'SELECT trimmy.career_red_day_activate()';

/**
 * Applies any migration this tool knows about that the cluster has not recorded,
 * in order, then reasserts the documented runtime grants. It never reruns a
 * recorded migration and never drops anything.
 */
async function migrate(paths) {
  if (!existsSync(paths.data)) fail('Runtime is not initialized. Run "init" first.');
  const bin = postgresBin();
  const started = await startCluster(bin, paths);
  try {
    writeFileSync(join(paths.data, 'pg_hba.conf'), renderHba({owner: OWNER_ROLE,
      runtimeRole: RUNTIME_ROLE, database: DATABASE}));
    await pgctl(bin, paths, ['reload']);
      await ensureLocalRedDayRoles(bin, paths);
      await ensureLocalSocialModeratorRole(bin, paths);
    const recorded = new Set((await ownerQueryRows(paths, 'SELECT version FROM trimmy.schema_migrations')).map(row => row[0]));
    const pending = MIGRATIONS.filter(migration => !recorded.has(migration));
    if (pending.includes('0025_relationship_safety') && apiPid(paths)) {
      fail('Stop the local API before migration 0025 retires legacy invitation authority.');
    }
    for (const migration of pending) {
      await ownerPsql(bin, paths, ['-d', DATABASE, '-f', join(projectDir, 'infra', 'migrations', `${migration}.sql`)]);
    }
    await ownerPsql(bin, paths, ['-d', DATABASE, '-c', runtimeGrants()]);
    await ownerPsql(bin, paths, ['-d', DATABASE, '-c', redDayWorkerLoginDenials()]);
    await ownerPsql(bin, paths, ['-d', DATABASE, '-c', redDayWorkerGrants()]);
    await ownerPsql(bin, paths, ['-d', DATABASE, '-c', socialModeratorGrants()]);
    const guestSourceUpgraded = ensureGuestSourceEnvironment(paths);
    await verifyLocalRedDayBoundary(bin, paths);
    await verifyLocalSocialModeratorBoundary(paths);
    await ownerPsql(bin, paths, ['-d', DATABASE, '-c', RED_DAY_ACTIVATION_SQL]);
    const after = (await ownerQueryRows(paths, "SELECT string_agg(version, ',' ORDER BY version) FROM trimmy.schema_migrations"))[0]?.[0] ?? '';
    console.log(pending.length === 0
      ? `No pending migrations. Recorded: ${after}`
      : `Applied ${pending.length} migration(s): ${pending.join(', ')}. Recorded: ${after}`);
    if (guestSourceUpgraded) console.log('Added private guest-source protection to the local API runtime.');
  } finally {
    if (started) await pgctl(bin, paths, ['-m', 'fast', '-w', 'stop']);
  }
}

async function start(paths, flags) {
  if (!existsSync(paths.apiEnv) || !existsSync(paths.data)) fail('Runtime is not initialized. Run "init" first.');
  const bin = postgresBin();
  const startedDb = await startCluster(bin, paths);
  const dist = join(projectDir, 'apps', 'api', 'dist', 'index.js');
  if (!existsSync(dist) || flags.build) {
    await run(join(projectDir, 'node_modules', '.bin', 'tsc'), ['-b', 'packages/domain', 'apps/api'], {cwd: projectDir});
  }
  const existingApiPid = apiPid(paths);
  if (existingApiPid) {
    console.log(`API already running (pid ${existingApiPid}).`);
  } else {
    let env = await configureWalletChecksEnvironment(
      {PATH: process.env.PATH, HOME: process.env.HOME, ...parseApiEnv(readFileSync(paths.apiEnv, 'utf8'))}, flags);
    env = await configureRelationshipSafetyEnvironment(env, flags);
    if (flags.withMarketReads) {
      // Read-only research adapters: keyed Tokens.xyz discovery/history, keyless
      // Jupiter research estimates and keyless Raydium comparison quotes. None
      // enables a wallet, order or money operation.
      env.TOKENS_API_KEY = await readKeychainSecret('trimmy-tokens-xyz');
      env.TRIMMY_STOCK_DISCOVERY = 'tokens_xyz';
      env.TRIMMY_STOCK_HISTORY = 'tokens_xyz';
      env.TRIMMY_MARKET_QUOTES = 'keyless_research';
      env.TRIMMY_RAYDIUM_STOCK_QUOTES = 'read_only';
    }
    if (flags.withHoldingsReads) {
      // Read-only owner balance reads for the account's linked wallet over a
      // public mainnet RPC. No signing, sending or key material is involved.
      env.TRIMMY_STOCK_HOLDINGS = 'solana_mainnet';
      env.SOLANA_MAINNET_RPC_URL = process.env.SOLANA_MAINNET_RPC_URL || DEFAULT_MAINNET_RPC_URL;
    }
    if (flags.webOrigins) env.TRIMMY_WEB_ORIGINS = flags.webOrigins;
    const log = openSync(paths.apiLog, 'a', 0o600);
    const child = spawn(process.execPath, [dist], {cwd: projectDir, env, detached: true, stdio: ['ignore', log, log]});
    closeSync(log);
    child.unref();
    privateWrite(paths.apiPid, `${child.pid}\n`);
  }
  const port = apiPort();
  let health = null;
  for (let attempt = 0; attempt < 30 && !health; attempt++) {
    health = await healthRequest(port, paths.caCert, '/health');
    if (!health) await new Promise(r => setTimeout(r, 500));
  }
  if (!health || health.status !== 200) {
    const tail = existsSync(paths.apiLog) ? readFileSync(paths.apiLog, 'utf8').trim().split('\n').slice(-5).join('\n') : '';
    fail(`API did not become healthy over HTTPS on 127.0.0.1:${port}.${tail ? `\n${tail}` : ''}`);
  }
  const config = await healthRequest(port, paths.caCert, '/v1/config');
  const parsed = config?.status === 200 ? JSON.parse(config.body) : {};
  assertWalletChecksStarted(parsed, flags, {alreadyRunning: existingApiPid !== null});
  assertRelationshipSafetyStarted(parsed, flags, {alreadyRunning: existingApiPid !== null});
  console.log(`PostgreSQL ${startedDb ? 'started' : 'already running'} on 127.0.0.1:${postgresPort()} (TLS only).`);
  console.log(`API healthy at https://127.0.0.1:${port} (CA: ${paths.caCert}).`);
  console.log(`practiceAccountsEnabled=${parsed.practiceAccountsEnabled} practiceSyncEnabled=${parsed.practiceSyncEnabled} watchlistSyncEnabled=${parsed.watchlistSyncEnabled} accountContextEnabled=${parsed.accountContextEnabled} accountHoldingsEnabled=${parsed.accountHoldingsEnabled} walletPossessionEnabled=${parsed.walletPossessionEnabled} relationshipSafetyEnabled=${parsed.relationshipSafetyEnabled} financialOperationsEnabled=${parsed.capabilities?.financialOperationsEnabled}`);
  console.log(`stockDiscoveryEnabled=${parsed.stockDiscoveryEnabled} stockHistoryEnabled=${parsed.stockHistoryEnabled} stockEstimatesEnabled=${parsed.stockEstimatesEnabled} marketEstimatesEnabled=${parsed.marketEstimatesEnabled} raydiumStockQuotesEnabled=${parsed.raydiumStockQuotesEnabled}`);
}

async function redDay(paths, flags) {
  if (!existsSync(paths.redDayWorkerEnv) || !existsSync(paths.data)) {
    fail('Runtime red-day worker is not initialized. Run "migrate" first.');
  }
  if (Object.keys(flags).some(key => key !== 'build')) {
    fail('The red-day command accepts only --build.');
  }
  const bin = postgresBin();
  const started = await startCluster(bin, paths);
  try {
    const worker = join(projectDir, 'tool', 'runtime', 'career-red-day-worker.mjs');
    const dist = join(projectDir, 'apps', 'api', 'dist', 'career-red-day-worker.js');
    if (!existsSync(dist) || flags.build) {
      await run(join(projectDir, 'node_modules', '.bin', 'tsc'),
        ['-b', 'packages/domain', 'apps/api'], {cwd: projectDir});
    }
    const env = {PATH: process.env.PATH, HOME: process.env.HOME,
      ...parseApiEnv(readFileSync(paths.redDayWorkerEnv, 'utf8')),
      TOKENS_API_KEY: await readKeychainSecret('trimmy-tokens-xyz')};
    const result = await run(process.execPath, [worker, '--once'], {cwd: projectDir, env});
    process.stdout.write(result.stdout);
  } finally {
    if (started) await pgctl(bin, paths, ['-m', 'fast', '-w', 'stop']);
  }
}

async function stop(paths) {
  const pid = apiPid(paths);
  if (pid) {
    process.kill(pid, 'SIGTERM');
    for (let attempt = 0; attempt < 20 && apiPid(paths); attempt++) await new Promise(r => setTimeout(r, 250));
    if (apiPid(paths)) process.kill(pid, 'SIGKILL');
    console.log(`API stopped (pid ${pid}).`);
  } else {
    console.log('API not running.');
  }
  rmSync(paths.apiPid, {force: true});
  if (existsSync(paths.data)) {
    const bin = postgresBin();
    if (await clusterRunning(bin, paths)) {
      await pgctl(bin, paths, ['-m', 'fast', '-w', 'stop']);
      console.log('PostgreSQL stopped.');
    } else {
      console.log('PostgreSQL not running.');
    }
  }
}

async function status(paths) {
  if (!existsSync(paths.data)) { console.log('Runtime not initialized.'); return; }
  const bin = postgresBin();
  const running = await clusterRunning(bin, paths);
  console.log(`PostgreSQL: ${running ? 'running' : 'stopped'} (127.0.0.1:${postgresPort()}, TLS only)`);
  const pid = apiPid(paths);
  const health = pid ? await healthRequest(apiPort(), paths.caCert, '/health') : null;
  console.log(`API: ${pid ? `pid ${pid}, health ${health?.status ?? 'unreachable'}` : 'stopped'} (https://127.0.0.1:${apiPort()})`);
  if (pid) {
    const config = await healthRequest(apiPort(), paths.caCert, '/v1/config');
    if (config?.status === 200) {
      const parsed = JSON.parse(config.body);
      console.log(`Config: practiceAccountsEnabled=${parsed.practiceAccountsEnabled} accountContextEnabled=${parsed.accountContextEnabled} accountHoldingsEnabled=${parsed.accountHoldingsEnabled} walletPossessionEnabled=${parsed.walletPossessionEnabled} relationshipSafetyEnabled=${parsed.relationshipSafetyEnabled} moneyMode=${parsed.moneyMode}`);
    }
  }
  if (running) {
    const query = [
      "SELECT 'migrations' AS item, string_agg(version, ',' ORDER BY version) AS value FROM trimmy.schema_migrations",
      "UNION ALL SELECT 'users', count(*)::text FROM trimmy.users",
      "UNION ALL SELECT 'practice_identities', count(*)::text FROM trimmy.practice_auth_identities",
      "UNION ALL SELECT 'progress_rows', count(*)::text FROM trimmy.practice_progress",
      "UNION ALL SELECT 'progress_receipts', count(*)::text FROM trimmy.practice_mutation_receipts",
      "UNION ALL SELECT 'watchlists', count(*)::text FROM trimmy.watchlists",
      "UNION ALL SELECT 'career_profiles', count(*)::text FROM trimmy.career_profiles",
      "UNION ALL SELECT 'career_reasons', count(*)::text FROM trimmy.career_trade_reasons",
      "UNION ALL SELECT 'progress_detail', coalesce(string_agg(format('%s rev=%s v=%s at=%s', left(user_id::text, 8), revision, progress->>'version', to_char(updated_at AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS\"Z\"')), '; '), '') FROM trimmy.practice_progress",
    ].join(' ');
    const result = await ownerPsql(bin, paths, ['-d', DATABASE, '-Atc', query]);
    for (const line of result.stdout.trim().split('\n')) console.log(`DB ${line.replace('|', ': ')}`);
  }
}

async function reset(paths, flags) {
  if (!flags.yes) fail('reset removes the local cluster, keys and API configuration. Re-run with --yes to confirm.');
  await stop(paths);
  for (const path of [paths.postgres, paths.tls, paths.apiEnv, paths.redDayWorkerEnv,
    paths.apiPid, paths.apiLog, paths.manifest]) rmSync(path, {recursive: true, force: true});
  console.log(`Removed runtime under ${paths.root}.`);
}

export function parseFlags(args) {
  const flags = {};
  for (let index = 0; index < args.length; index++) {
    const arg = args[index];
    if (arg === '--yes') flags.yes = true;
    else if (arg === '--with-app-secret') flags.withAppSecret = true;
    else if (arg === '--with-market-reads') flags.withMarketReads = true;
    else if (arg === '--with-holdings-reads') flags.withHoldingsReads = true;
    else if (arg === '--with-wallet-checks') flags.withWalletChecks = true;
    else if (arg === '--with-relationship-safety') flags.withRelationshipSafety = true;
    else if (arg === '--build') flags.build = true;
    else if (arg === '--web-origins') flags.webOrigins = args[++index] ?? fail('--web-origins needs a JSON array.');
    else fail(`Unknown option ${arg}.`);
  }
  return flags;
}

async function main() {
  const [command, ...rest] = process.argv.slice(2);
  const paths = runtimePaths(process.env.TRIMMY_RUNTIME_DIR ?? join(homedir(), '.config', 'trimmy', 'runtime'));
  const flags = parseFlags(rest);
  if (existsSync(paths.root) && (statSync(paths.root).mode & 0o077) !== 0) fail(`${paths.root} must be private (mode 0700).`);
  switch (command) {
    case 'init': return init(paths);
    case 'start': return start(paths, flags);
    case 'stop': return stop(paths);
    case 'migrate': return migrate(paths);
    case 'red-day': return redDay(paths, flags);
    case 'status': return status(paths);
    case 'reset': return reset(paths, flags);
    default: fail('Usage: local-secure-runtime.mjs <init|migrate|red-day [--build]|start [--with-app-secret] [--with-market-reads] [--with-holdings-reads] [--with-wallet-checks] [--with-relationship-safety] [--web-origins JSON] [--build]|stop|status|reset --yes>');
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => {
    console.error(error instanceof RuntimeError ? error.message : 'Runtime command failed.');
    process.exitCode = 1;
  });
}
