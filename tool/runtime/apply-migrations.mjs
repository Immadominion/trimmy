#!/usr/bin/env node
// Applies the ordered SQL migrations to a real (managed or self-hosted)
// PostgreSQL over a verified TLS connection. This is the deployment
// counterpart to local-secure-runtime.mjs, which only ever targets its own
// private local cluster.
//
// It needs OWNER credentials. The API's restricted runtime role deliberately
// cannot run DDL, so the owner URL is a separate variable and must never be
// given to the API process.
//
// Guarantees: TLS is verified and proven server-side before any DDL runs; the
// recorded history must be an exact ordered prefix of this build's migration
// list; a database already ahead of this build is refused rather than
// downgraded; concurrent deploys cannot migrate at the same time; and a
// released migration file whose bytes changed is refused.
import { readFile } from 'node:fs/promises';
import { createHash, X509Certificate } from 'node:crypto';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import pg from 'pg';
import {
  MIGRATIONS, RED_DAY_ACTIVATION_SQL, RED_DAY_API_DENIED_FUNCTIONS, RED_DAY_CAPABILITY_ROLE,
  RED_DAY_WORKER_FUNCTIONS, RED_DAY_WORKER_ROLE, RUNTIME_ROLE,
  SOCIAL_MODERATOR_FUNCTION, SOCIAL_MODERATOR_ROLE,
  redDayWorkerGrants, redDayWorkerLoginDenials, runtimeGrants,
  socialModeratorGrants,
} from './local-secure-runtime.mjs';

const projectDir = resolve(dirname(fileURLToPath(import.meta.url)), '../..');

// Append a new entry with every new migration. Never edit an existing digest:
// an applied migration's bytes are history, and a silent change would let a
// fresh database diverge from an already-migrated one.
export const MIGRATION_DIGESTS = Object.freeze({
  '0001_foundation': '50ea761a9dbdb527209eab6ea1d7e2ccb6603d7e441c7a2a1ddd7ad730634437',
  '0002_practice_progress': '340623556e60ab1d16a55ba7c63291f9b579ed01957f07ac408698d2936eed19',
  '0003_practice_accounts': '976b2a5450eafcca23690d3e8f71bbc3012d8acc5d6e0016ab3da2ef461a9661',
  '0004_watchlists': '94562705fc45126dd26f60927ffda8d0b20ca449c6118fee88fad46ceb578aa4',
  '0005_practice_payload_v4': 'b3eef439431f1c4087369f13196d00cedfe6b917633e779819272205cef52256',
  '0006_practice_payload_v5': '6d390781247adb63d87760ae725ed141e882f930e20b9916d46653a521b19c75',
  '0007_wallet_possession_and_reviews': '186384c6621661db310976cc245d310ed77fcb7e5f4515a1afa27aea3130f27c',
  '0008_practice_payload_v6': '5c3ae1e4d717575b6f5005d2795391da607125796f53f8d4fcf66f1a589376ba',
  '0009_invitations': '0fb74f1885d96d03f473e2a54df20f468700b466ceab67d50d485d14b5efc12b',
  '0010_account_closure': '1f0b1feba2737c7327fc1bdee8638154584f2cfbd2b1fc878a79a41c1e098bd3',
  '0011_wallet_possession_challenges': '46d0295e86c12209350bf01c1ce682595fb5a3e9dfd8637c345707c2b428b43d',
  '0012_followed_stocks': 'eb90759513351cab387488e90f095c693be3cbb0afe1895b5240a900ad882080',
  '0013_paper_trading': 'be8558f64dc12d54a74f2305a68e03a21c198a868fe7a668559c24aba1939d5e',
  '0014_guest_sessions': '5e3d4c14435e4e82318df4a6db91a719258318778c7705507c2ad0ef43e10f48',
  '0015_product_profiles': '39ff1bb3aef44f5135d438932b63d15e3292216657b7e1eaa412c076462ff7a3',
  '0016_guest_creation_idempotency': '56216e088337176b7b0db6c4d7d61f9e28633d28df6b1883f956e5f014907635',
  '0017_career_core': 'f3c3b58a96bc91c4d8296060ffc77c4d81d9352767a0831e536a716fc90a32d8',
  '0018_career_missions_and_promotions': 'e12792a2156f2f5e074670662edc694c1d1ac4735bde37fb8dc6c9dc5008041b',
  '0019_career_local_day': '73ae2a08990729e93d6362e64cacf2058c6c97a2d1777a6d349695fd179ac2bd',
  '0020_guest_creation_abuse_and_retention': '2b3f8748d729f9b6aa5207b0ff668925852a443df718f38d0c20219a53ff0e2c',
  '0021_career_red_day_evidence': '2d023b72a7d017caf0a0c42e8a660b1cfa38467b5cefd5e594488f1e03f43591',
  '0022_product_launch_evidence': 'de2272996d57ba649f80664bfcabfc820e5d49ec0247e5c47bc93e877c4eea49',
  '0023_paper_reset': 'a60d6959327407dd91b12c196044b0170063186ba7fb98bae997aaa397bee868',
  '0024_career_reason_sharing': 'f7d918cdcaad67049bc45df40af850cc131b151f61ed51be56d0e4cdfb4937c1',
  '0025_relationship_safety': '30c461cbe3ee88175697343c8a9a9a687441041df91779d44cbe3971dcb308fa',
  '0026_optional_introduction': '549f47a708a48bf40d0308eb5c2ca1823d763d01483aa2e841ea1e046e1f6d89',
  '0027_career_activity_week': '4803a012181a1736691791d65a71c1edbe3afa3fd001034cfdac9057eed37d8a',
  '0028_community_following': '4d5204e07be459430effb471b4490ffd829a53c06df489132c5c3f9a091b8c3f',
  '0029_daily_desk': '0a782c1f44982cacd6a681bb0fd078fa3cc497853456a2c513e1fdac15843986',
  '0030_intern_workdays': 'bb4e4ac4bc97915ddbe791961c7062caaf755d408a2b62a50c8458d5ba93539b',
  '0031_live_stock_orders': 'e89be7e4aeb4123d6befefe0d00cbde50033a4db8fa47ae546f65c8452f6493c',
});

/** One fixed lock so two deploys cannot migrate the same database at once. */
const ADVISORY_LOCK_KEY = 8_143_072_509_411_002n;
const MAX_MIGRATION_BYTES = 512 * 1024;

export class MigrationError extends Error {
  constructor(message) { super(message); this.name = 'MigrationError'; }
}
function fail(message) { throw new MigrationError(message); }

/** A pinned certificate bundle for database TLS verification; every PEM block must parse. */
export function readCertificateBundle(text) {
  if (Buffer.byteLength(text, 'utf8') > 65_536) fail('The database CA bundle is too large.');
  const blocks = text.match(/-----BEGIN CERTIFICATE-----[^-]+-----END CERTIFICATE-----/g);
  if (!blocks || blocks.length > 16) fail('The database CA file contains no usable certificate.');
  try { for (const block of blocks) new X509Certificate(block); }
  catch { fail('The database CA file contains an unparsable certificate.'); }
  return text;
}

/**
 * Parse an owner connection URL with the same strict rules the API applies to
 * its runtime URL: explicit fields only, so no sslmode query option can
 * replace certificate verification.
 */
export function parseOwnerDatabaseUrl(raw, ca) {
  if (typeof raw !== 'string' || !raw || raw.length > 4096 || raw.trim() !== raw) {
    fail('TRIMMY_MIGRATION_DATABASE_URL is missing or malformed.');
  }
  let url;
  try { url = new URL(raw); } catch { return fail('TRIMMY_MIGRATION_DATABASE_URL is not a valid URL.'); }
  if (!['postgres:', 'postgresql:'].includes(url.protocol) || !url.hostname) {
    fail('TRIMMY_MIGRATION_DATABASE_URL must be a postgresql:// URL with a host.');
  }
  if (url.search || url.hash) {
    fail('TRIMMY_MIGRATION_DATABASE_URL must not carry query or fragment options; TLS is configured explicitly.');
  }
  const database = decodeURIComponent(url.pathname.slice(1));
  const user = decodeURIComponent(url.username);
  const password = decodeURIComponent(url.password);
  const port = url.port ? Number(url.port) : 5432;
  if (!/^[a-zA-Z0-9_.-]{1,63}$/.test(database)) fail('The migration database name is invalid.');
  if (!/^[a-zA-Z0-9_.@-]{1,128}$/.test(user)) fail('The migration database user is invalid.');
  if (!password || password.length > 512 || /[\u0000-\u001f\u007f]/.test(password)) {
    fail('The migration database password is missing or invalid.');
  }
  if (!Number.isInteger(port) || port < 1 || port > 65535) fail('The migration database port is invalid.');
  return Object.freeze({
    host: url.hostname.replace(/^\[|\]$/g, ''), port, database, user, password,
    ssl: Object.freeze(ca === undefined ? {rejectUnauthorized: true} : {rejectUnauthorized: true, ca}),
    connectionTimeoutMillis: 10_000,
    // Migrations take locks and rebuild constraints; no short statement timeout.
    application_name: 'trimmy-migrate',
  });
}

/** A restricted role name is an identifier, never interpolated user text. */
function parseRole(raw, variable) {
  if (raw === undefined || raw === '') return undefined;
  if (typeof raw !== 'string' || !/^[a-z_][a-z0-9_]{0,62}$/.test(raw)) {
    fail(`${variable} must be a lowercase PostgreSQL identifier.`);
  }
  return raw;
}

export function parseRuntimeRole(raw) {
  return parseRole(raw, 'TRIMMY_MIGRATION_RUNTIME_ROLE');
}

export function readMigrationConfig(env, caText) {
  const ca = caText === undefined ? undefined : readCertificateBundle(caText);
  const activation = env['TRIMMY_MIGRATION_ACTIVATE_RED_DAY'] ?? 'false';
  if (!['true', 'false'].includes(activation)) {
    fail('TRIMMY_MIGRATION_ACTIVATE_RED_DAY must be true or false.');
  }
  const relationshipCutover = env['TRIMMY_MIGRATION_RELATIONSHIP_CUTOVER'] ?? '';
  if (!['', 'drained-v2'].includes(relationshipCutover)) {
    fail('TRIMMY_MIGRATION_RELATIONSHIP_CUTOVER must be drained-v2 when supplied.');
  }
  return Object.freeze({
    database: parseOwnerDatabaseUrl(env['TRIMMY_MIGRATION_DATABASE_URL'], ca),
    runtimeRole: parseRuntimeRole(env['TRIMMY_MIGRATION_RUNTIME_ROLE']),
    redDayCapabilityRole: parseRole(env['TRIMMY_MIGRATION_RED_DAY_CAPABILITY_ROLE'],
      'TRIMMY_MIGRATION_RED_DAY_CAPABILITY_ROLE') ?? RED_DAY_CAPABILITY_ROLE,
    redDayWorkerRole: parseRole(env['TRIMMY_MIGRATION_RED_DAY_WORKER_ROLE'],
      'TRIMMY_MIGRATION_RED_DAY_WORKER_ROLE') ?? RED_DAY_WORKER_ROLE,
    socialModeratorRole: parseRole(env['TRIMMY_MIGRATION_SOCIAL_MODERATOR_ROLE'],
      'TRIMMY_MIGRATION_SOCIAL_MODERATOR_ROLE') ?? SOCIAL_MODERATOR_ROLE,
    relationshipCutover,
    activateRedDay: activation === 'true',
    grantsOnly: env['TRIMMY_MIGRATION_GRANTS_ONLY'] === 'true',
  });
}

/** Migration 0025 retires the legacy invitation authority in one commit. The
 * deploy must stop every old and new API database pool, acknowledge the v2
 * cutover, apply the migration, then restart only the v2 build. */
export async function assertRelationshipApiDrained(client, acknowledgement) {
  if (acknowledgement !== 'drained-v2') {
    fail('Migration 0025 requires an acknowledged drained-v2 API cutover.');
  }
  const sessions = await client.query(`SELECT count(*)::integer AS count
    FROM pg_catalog.pg_stat_activity
    WHERE datid = (SELECT oid FROM pg_catalog.pg_database WHERE datname=current_database())
      AND pid <> pg_backend_pid() AND application_name='trimmy-practice-api'`);
  if (sessions.rows?.length !== 1 || Number(sessions.rows[0]?.count) !== 0) {
    fail('Migration 0025 requires every trimmy-practice-api database session to be drained.');
  }
}

/** Read and verify one migration's bytes against its registered release digest. */
export async function readMigration(version, {root = projectDir} = {}) {
  const expected = MIGRATION_DIGESTS[version];
  if (!expected) fail(`Migration ${version} has no registered digest.`);
  const raw = await readFile(join(root, 'infra', 'migrations', `${version}.sql`));
  if (raw.length > MAX_MIGRATION_BYTES) fail(`Migration ${version} is too large.`);
  const digest = createHash('sha256').update(raw).digest('hex');
  if (digest !== expected) {
    fail(`Migration ${version} does not match its registered digest. `
      + 'An applied migration must never be edited; add a new migration instead.');
  }
  return raw.toString('utf8');
}

/**
 * Compare the database's recorded history with this build's ordered list.
 * Returns the migrations still to apply.
 */
export function planMigrations(recorded, expected = MIGRATIONS) {
  const known = new Set(expected);
  const unknown = recorded.filter(version => !known.has(version));
  if (unknown.length) {
    fail(`The database has migrations this build does not know: ${unknown.join(', ')}. `
      + 'Deploy a newer build instead of downgrading the schema.');
  }
  // Recorded history must be an exact ordered prefix; a gap means someone
  // applied migrations out of order and the schema is not a known state.
  const applied = expected.filter(version => recorded.includes(version));
  if (applied.length !== recorded.length) fail('The database has duplicate recorded migrations.');
  const prefix = expected.slice(0, applied.length);
  if (prefix.some((version, index) => version !== applied[index])) {
    fail('The recorded migrations are not an ordered prefix of this build.');
  }
  const pending = expected.slice(applied.length);
  const outOfOrder = pending.filter(version => recorded.includes(version));
  if (outOfOrder.length) fail('The recorded migrations are out of order.');
  return Object.freeze({applied: Object.freeze(prefix), pending: Object.freeze(pending)});
}

async function recordedVersions(client) {
  try {
    const result = await client.query('SELECT version FROM trimmy.schema_migrations ORDER BY version');
    return result.rows.map(row => row.version);
  } catch (error) {
    // A fresh database has no schema yet; 0001 creates the table.
    if (error && (error.code === '42P01' || error.code === '3F000')) return [];
    throw error;
  }
}

/** Prove the session is actually encrypted before running any DDL. */
async function assertEncrypted(client) {
  const result = await client.query('SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()');
  if (result.rows[0]?.ssl !== true) {
    fail('The migration connection is not TLS encrypted. Refusing to migrate over plaintext.');
  }
}

function flag(value) { return value === true || value === 't'; }

/** Forced-RLS tables have no owner policy. Migration-owned definer functions
 * therefore require a superuser or BYPASSRLS owner to observe their rows. */
async function assertMigrationAuthority(client) {
  const result = await client.query(`SELECT session_user AS session_user_name,
      current_user AS current_user_name, r.rolsuper, r.rolbypassrls
    FROM pg_catalog.pg_roles r WHERE r.rolname=current_user`);
  const row = result.rows?.[0];
  if (result.rows?.length !== 1 || row?.session_user_name !== row?.current_user_name ||
      (!flag(row?.rolsuper) && !flag(row?.rolbypassrls))) {
    fail('The migration role must be SUPERUSER or BYPASSRLS because Trimmy uses FORCE RLS.');
  }
}

async function assertFunctionOwnerAuthority(client, runtimeRole) {
  const result = await client.query(`WITH internal(signature) AS (
      SELECT unnest($2::text[])
    ), surface(oid) AS (
      SELECT p.oid FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='trimmy'
        AND (p.prosecdef OR has_function_privilege($1,p.oid,'EXECUTE'))
      UNION
      SELECT pg_catalog.to_regprocedure('trimmy.' || signature)::oid FROM internal
    )
    SELECT p.oid::regprocedure::text AS signature, owner.rolname AS owner_name
    FROM surface
    LEFT JOIN pg_catalog.pg_proc p ON p.oid=surface.oid
    LEFT JOIN pg_catalog.pg_roles owner ON owner.oid=p.proowner
    WHERE p.oid IS NULL OR owner.oid IS NULL
      OR NOT (owner.rolsuper OR owner.rolbypassrls)
    ORDER BY signature NULLS FIRST`, [runtimeRole, RED_DAY_API_DENIED_FUNCTIONS]);
  if ((result.rows?.length ?? 0) !== 0) {
    fail('Every Trimmy security-definer, API or red-day internal function must be owned by a SUPERUSER or BYPASSRLS role.');
  }
}

/** Validate roles before any migration can make the mission reachable. */
export async function assertRedDayRoles(client, {runtimeRole = RUNTIME_ROLE,
  redDayCapabilityRole, redDayWorkerRole}) {
  if (new Set([runtimeRole, redDayCapabilityRole, redDayWorkerRole]).size !== 3) {
    fail('API, red-day worker and red-day capability roles must be distinct.');
  }
  const roles = await client.query(`SELECT rolname, rolcanlogin, rolinherit, rolsuper,
      rolcreatedb, rolcreaterole, rolreplication, rolbypassrls
    FROM pg_catalog.pg_roles WHERE rolname=ANY($1::text[]) ORDER BY rolname`,
  [[runtimeRole, redDayCapabilityRole, redDayWorkerRole]]);
  const byName = new Map((roles.rows ?? []).map(row => [row.rolname, row]));
  const worker = byName.get(redDayWorkerRole);
  const capability = byName.get(redDayCapabilityRole);
  if (!byName.has(runtimeRole)) fail('The configured API runtime role does not exist.');
  if (!worker || !flag(worker.rolcanlogin) || flag(worker.rolinherit) || flag(worker.rolsuper) ||
      flag(worker.rolcreatedb) || flag(worker.rolcreaterole) || flag(worker.rolreplication) ||
      flag(worker.rolbypassrls)) {
    fail('The red-day worker must be a safe NOINHERIT login role.');
  }
  if (!capability || flag(capability.rolcanlogin) || flag(capability.rolinherit) ||
      flag(capability.rolsuper) || flag(capability.rolcreatedb) || flag(capability.rolcreaterole) ||
      flag(capability.rolreplication) || flag(capability.rolbypassrls)) {
    fail('The red-day capability must be a safe NOLOGIN NOINHERIT role.');
  }
  const reachable = await client.query(`WITH RECURSIVE reachable(oid) AS (
      SELECT oid FROM pg_catalog.pg_roles WHERE rolname=$1
      UNION
      SELECT membership.roleid FROM pg_catalog.pg_auth_members membership
      JOIN reachable reachable_role ON reachable_role.oid=membership.member
    )
    SELECT role_row.rolname FROM reachable
    JOIN pg_catalog.pg_roles role_row ON role_row.oid=reachable.oid
    WHERE role_row.rolname<>$1 ORDER BY role_row.rolname`, [redDayWorkerRole]);
  if (reachable.rows?.length !== 1 || reachable.rows[0]?.rolname !== redDayCapabilityRole) {
    fail('The red-day worker must reach exactly its capability role and no other role.');
  }
  const membership = await client.query(`SELECT count(*)::integer AS count,
      coalesce(bool_or(m.admin_option),false) AS admin_option,
      coalesce(bool_or(CASE WHEN to_jsonb(m) ? 'inherit_option'
        THEN (to_jsonb(m)->>'inherit_option')::boolean ELSE false END),false) AS inherit_option,
      coalesce(bool_and(CASE WHEN to_jsonb(m) ? 'set_option'
        THEN (to_jsonb(m)->>'set_option')::boolean ELSE true END),true) AS set_option
    FROM pg_catalog.pg_auth_members m
    JOIN pg_catalog.pg_roles granted ON granted.oid=m.roleid
    JOIN pg_catalog.pg_roles member_role ON member_role.oid=m.member
    WHERE granted.rolname=$1 AND member_role.rolname=$2`,
  [redDayCapabilityRole, redDayWorkerRole]);
  const edge = membership.rows?.[0];
  if (membership.rows?.length !== 1 || Number(edge?.count) !== 1 || flag(edge?.admin_option) ||
      flag(edge?.inherit_option) || !flag(edge?.set_option)) {
    fail('The red-day worker membership must be one non-admin SET ROLE edge.');
  }
  const ingress = await client.query(`WITH RECURSIVE ingress(oid) AS (
      SELECT oid FROM pg_catalog.pg_roles WHERE rolname=$1
      UNION
      SELECT membership.member FROM pg_catalog.pg_auth_members membership
      JOIN ingress granted_role ON granted_role.oid=membership.roleid
    )
    SELECT role_row.rolname FROM ingress
    JOIN pg_catalog.pg_roles role_row ON role_row.oid=ingress.oid
    WHERE role_row.rolname<>$1 ORDER BY role_row.rolname`, [redDayCapabilityRole]);
  if (ingress.rows?.length !== 1 || ingress.rows[0]?.rolname !== redDayWorkerRole) {
    fail('Only the dedicated red-day worker may reach the capability role.');
  }
  const apiReach = await client.query(`WITH RECURSIVE reachable(oid) AS (
      SELECT oid FROM pg_catalog.pg_roles WHERE rolname=$1
      UNION
      SELECT membership.roleid FROM pg_catalog.pg_auth_members membership
      JOIN reachable reachable_role ON reachable_role.oid=membership.member
    ) SELECT count(*)::integer AS count FROM reachable
      JOIN pg_catalog.pg_roles role_row ON role_row.oid=reachable.oid
      WHERE role_row.rolname=ANY($2::text[])`,
  [runtimeRole, [redDayCapabilityRole, redDayWorkerRole]]);
  if (Number(apiReach.rows?.[0]?.count) !== 0) {
    fail('The API runtime role can reach a red-day worker role.');
  }
  const ownedPortable = await client.query(`SELECT
    (SELECT count(*) FROM pg_catalog.pg_database d JOIN pg_catalog.pg_roles r ON r.oid=d.datdba
      WHERE r.rolname=ANY($1::text[])) +
    (SELECT count(*) FROM pg_catalog.pg_namespace n JOIN pg_catalog.pg_roles r ON r.oid=n.nspowner
      WHERE r.rolname=ANY($1::text[])) +
    (SELECT count(*) FROM pg_catalog.pg_class c JOIN pg_catalog.pg_roles r ON r.oid=c.relowner
      WHERE r.rolname=ANY($1::text[])) +
    (SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
      WHERE r.rolname=ANY($1::text[])) AS count`, [[redDayCapabilityRole, redDayWorkerRole]]);
  if (Number(ownedPortable.rows?.[0]?.count) !== 0) {
    fail('Red-day roles must not own database objects.');
  }
}

/** Verify the exact effective grant surface after idempotent revokes/grants. */
export async function assertRedDayGrants(client, {runtimeRole = RUNTIME_ROLE,
  redDayCapabilityRole, redDayWorkerRole}) {
  // PostgreSQL's named-role has_* helpers include privileges reachable through
  // membership even for NOINHERIT roles. Inspect ACL grantees directly here so
  // the worker's deliberate membership in the capability role is not mistaken
  // for a direct login grant. PUBLIC is included because it is effective for
  // every login and therefore also part of the direct attack surface.
  const workerDirect = await client.query(`WITH target AS (
      SELECT oid FROM pg_catalog.pg_roles WHERE rolname=$1
    ) SELECT
      EXISTS (SELECT 1 FROM pg_catalog.pg_namespace n
        CROSS JOIN LATERAL pg_catalog.aclexplode(
          coalesce(n.nspacl, pg_catalog.acldefault('n',n.nspowner))) acl
        WHERE n.nspname='trimmy' AND acl.grantee IN (0,(SELECT oid FROM target))
          AND acl.privilege_type='USAGE') AS schema_usage,
      EXISTS (SELECT 1 FROM pg_catalog.pg_namespace n
        CROSS JOIN LATERAL pg_catalog.aclexplode(
          coalesce(n.nspacl, pg_catalog.acldefault('n',n.nspowner))) acl
        WHERE n.nspname='trimmy' AND acl.grantee IN (0,(SELECT oid FROM target))
          AND acl.privilege_type='CREATE') AS schema_create,
      (SELECT count(DISTINCT p.oid)::integer FROM pg_catalog.pg_proc p
        JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        CROSS JOIN LATERAL pg_catalog.aclexplode(
          coalesce(p.proacl, pg_catalog.acldefault('f',p.proowner))) acl
        WHERE n.nspname='trimmy' AND acl.grantee IN (0,(SELECT oid FROM target))
          AND acl.privilege_type='EXECUTE') AS functions,
      (SELECT count(DISTINCT c.oid)::integer FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        CROSS JOIN LATERAL pg_catalog.aclexplode(
          coalesce(c.relacl, pg_catalog.acldefault('r',c.relowner))) acl
        WHERE n.nspname='trimmy' AND c.relkind IN ('r','p','v','m','f')
          AND acl.grantee IN (0,(SELECT oid FROM target))) AS tables,
      (SELECT count(DISTINCT c.oid)::integer FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        CROSS JOIN LATERAL pg_catalog.aclexplode(
          coalesce(c.relacl, pg_catalog.acldefault('s',c.relowner))) acl
        WHERE n.nspname='trimmy' AND c.relkind='S'
          AND acl.grantee IN (0,(SELECT oid FROM target))) AS sequences`, [redDayWorkerRole]);
  const worker = workerDirect.rows?.[0];
  if (workerDirect.rows?.length !== 1 || flag(worker?.schema_usage) || flag(worker?.schema_create) ||
      Number(worker?.functions) !== 0 || Number(worker?.tables) !== 0 || Number(worker?.sequences) !== 0) {
    fail('The red-day worker login has direct database privileges.');
  }
  const capabilitySurface = await client.query(`SELECT
      has_schema_privilege($1,'trimmy','USAGE') AS schema_usage,
      has_schema_privilege($1,'trimmy','CREATE') AS schema_create,
      (SELECT count(*)::integer FROM pg_catalog.pg_proc p
        JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='trimmy' AND has_function_privilege($1,p.oid,'EXECUTE')) AS functions,
      (SELECT count(*)::integer FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='trimmy' AND c.relkind IN ('r','p','v','m','f') AND (
          has_table_privilege($1,c.oid,'SELECT') OR has_table_privilege($1,c.oid,'INSERT') OR
          has_table_privilege($1,c.oid,'UPDATE') OR has_table_privilege($1,c.oid,'DELETE') OR
          has_table_privilege($1,c.oid,'TRUNCATE') OR has_table_privilege($1,c.oid,'REFERENCES') OR
          has_table_privilege($1,c.oid,'TRIGGER'))) AS tables,
      (SELECT count(*)::integer FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='trimmy' AND c.relkind='S' AND (
          has_sequence_privilege($1,c.oid,'USAGE') OR
          has_sequence_privilege($1,c.oid,'SELECT') OR
          has_sequence_privilege($1,c.oid,'UPDATE'))) AS sequences`, [redDayCapabilityRole]);
  const capability = capabilitySurface.rows?.[0];
  if (capabilitySurface.rows?.length !== 1 || !flag(capability?.schema_usage) || flag(capability?.schema_create) ||
      Number(capability.functions) !== RED_DAY_WORKER_FUNCTIONS.length ||
      Number(capability.tables) !== 0 || Number(capability.sequences) !== 0) {
    fail('The red-day capability grant surface is not function-only.');
  }
  const expected = await client.query(`SELECT pg_catalog.to_regprocedure('trimmy.' || signature)::oid::text AS oid
    FROM unnest($1::text[]) expected(signature) ORDER BY oid`, [RED_DAY_WORKER_FUNCTIONS]);
  const actual = await client.query(`SELECT p.oid::text AS oid FROM pg_catalog.pg_proc p
    JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='trimmy' AND has_function_privilege($1,p.oid,'EXECUTE') ORDER BY p.oid`,
  [redDayCapabilityRole]);
  const expectedOids = (expected.rows ?? []).map(row => row.oid).sort();
  const actualOids = (actual.rows ?? []).map(row => row.oid).sort();
  if (expectedOids.some(value => typeof value !== 'string') ||
      JSON.stringify(expectedOids) !== JSON.stringify(actualOids)) {
    fail('The red-day capability does not have the exact four worker functions.');
  }
  const apiExposure = await client.query(`SELECT
      (SELECT count(*)::integer FROM unnest($2::text[]) expected(signature)
        WHERE has_function_privilege($1,
          pg_catalog.to_regprocedure('trimmy.' || expected.signature),'EXECUTE')) AS functions,
      (SELECT count(*)::integer FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='trimmy' AND c.relname=ANY($3::text[]) AND (
          has_table_privilege($1,c.oid,'SELECT') OR has_table_privilege($1,c.oid,'INSERT') OR
          has_table_privilege($1,c.oid,'UPDATE') OR has_table_privilege($1,c.oid,'DELETE') OR
          has_table_privilege($1,c.oid,'TRUNCATE') OR has_table_privilege($1,c.oid,'REFERENCES') OR
          has_table_privilege($1,c.oid,'TRIGGER'))) AS tables`,
  [runtimeRole, RED_DAY_API_DENIED_FUNCTIONS, [
    'career_red_day_provider_observations', 'career_red_day_sessions',
    'career_red_day_asset_state', 'career_red_day_provider_state',
    'career_red_day_user_evidence', 'career_red_day_correction_reviews',
  ]]);
  if (Number(apiExposure.rows?.[0]?.functions) !== 0 || Number(apiExposure.rows?.[0]?.tables) !== 0) {
    fail('The API runtime role can reach red-day evidence authority.');
  }
}

export async function assertSocialModeratorRole(client, {runtimeRole = RUNTIME_ROLE,
  socialModeratorRole = SOCIAL_MODERATOR_ROLE, otherRoles = []} = {}) {
  if (new Set([runtimeRole, socialModeratorRole, ...otherRoles]).size !== 2 + otherRoles.length) {
    fail('API, moderation and worker roles must be distinct.');
  }
  const result = await client.query(`SELECT rolcanlogin, rolinherit, rolsuper,
      rolcreatedb, rolcreaterole, rolreplication, rolbypassrls
    FROM pg_catalog.pg_roles WHERE rolname=$1`, [socialModeratorRole]);
  const role = result.rows?.[0];
  if (result.rows?.length !== 1 || flag(role?.rolcanlogin) || flag(role?.rolinherit) ||
      flag(role?.rolsuper) || flag(role?.rolcreatedb) || flag(role?.rolcreaterole) ||
      flag(role?.rolreplication) || flag(role?.rolbypassrls)) {
    fail('The social moderator must be a safe NOLOGIN NOINHERIT role.');
  }
  const boundary = await client.query(`SELECT
    (SELECT count(*)::integer FROM unnest($2::text[]) protected(role_name)
      WHERE pg_catalog.pg_has_role(protected.role_name,$1,'MEMBER')) AS protected_reachable,
    (SELECT count(*)::integer FROM pg_catalog.pg_auth_members membership
      JOIN pg_catalog.pg_roles member_role ON member_role.oid=membership.member
      WHERE member_role.rolname=$1) AS outbound_memberships,
    (SELECT count(*) FROM pg_catalog.pg_database d JOIN pg_catalog.pg_roles r ON r.oid=d.datdba
      WHERE r.rolname=$1) +
    (SELECT count(*) FROM pg_catalog.pg_namespace n JOIN pg_catalog.pg_roles r ON r.oid=n.nspowner
      WHERE r.rolname=$1) +
    (SELECT count(*) FROM pg_catalog.pg_class c JOIN pg_catalog.pg_roles r ON r.oid=c.relowner
      WHERE r.rolname=$1) +
    (SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
      WHERE r.rolname=$1) AS owned`,
  [socialModeratorRole, [runtimeRole, ...otherRoles]]);
  if (boundary.rows?.length !== 1 || Number(boundary.rows[0]?.protected_reachable) !== 0 ||
      Number(boundary.rows[0]?.outbound_memberships) !== 0 || Number(boundary.rows[0]?.owned) !== 0) {
    fail('The social moderator role has unsafe membership, reachability or ownership.');
  }
}

export async function assertSocialModeratorGrants(client, {runtimeRole = RUNTIME_ROLE,
  socialModeratorRole = SOCIAL_MODERATOR_ROLE} = {}) {
  const result = await client.query(`SELECT
      has_schema_privilege($1,'trimmy','USAGE') AS schema_usage,
      has_schema_privilege($1,'trimmy','CREATE') AS schema_create,
      (SELECT count(*)::integer FROM pg_catalog.pg_proc p
        JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='trimmy' AND has_function_privilege($1,p.oid,'EXECUTE')) AS functions,
      (SELECT count(*)::integer FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='trimmy' AND c.relkind IN ('r','p','v','m','f') AND (
          has_table_privilege($1,c.oid,'SELECT') OR has_table_privilege($1,c.oid,'INSERT') OR
          has_table_privilege($1,c.oid,'UPDATE') OR has_table_privilege($1,c.oid,'DELETE') OR
          has_table_privilege($1,c.oid,'TRUNCATE') OR has_table_privilege($1,c.oid,'REFERENCES') OR
          has_table_privilege($1,c.oid,'TRIGGER'))) AS tables,
      has_function_privilege($1,pg_catalog.to_regprocedure('trimmy.' || $3),'EXECUTE') AS expected,
      has_function_privilege($2,pg_catalog.to_regprocedure('trimmy.' || $3),'EXECUTE') AS api_execute`,
  [socialModeratorRole, runtimeRole, SOCIAL_MODERATOR_FUNCTION]);
  const row = result.rows?.[0];
  if (result.rows?.length !== 1 || !flag(row?.schema_usage) || flag(row?.schema_create) ||
      Number(row?.functions) !== 1 || Number(row?.tables) !== 0 || !flag(row?.expected) ||
      flag(row?.api_execute)) {
    fail('The social moderator grant surface is not one function only.');
  }
}

export async function applyMigrations(config, {root = projectDir, log = () => {}} = {}) {
  const client = new pg.Client(config.database);
  await client.connect();
  try {
    await assertEncrypted(client);
    await assertMigrationAuthority(client);
    const locked = await client.query('SELECT pg_try_advisory_lock($1) AS held', [String(ADVISORY_LOCK_KEY)]);
    if (locked.rows[0]?.held !== true) {
      fail('Another migration run holds the deployment lock. Wait for it to finish.');
    }
    try {
      const role = config.runtimeRole ?? RUNTIME_ROLE;
      const redDayRoles = Object.freeze({runtimeRole: role,
        redDayCapabilityRole: config.redDayCapabilityRole,
        redDayWorkerRole: config.redDayWorkerRole});
      await assertRedDayRoles(client, redDayRoles);
      const moderatorRoles = Object.freeze({runtimeRole: role,
        socialModeratorRole: config.socialModeratorRole,
        otherRoles: [config.redDayCapabilityRole, config.redDayWorkerRole]});
      await assertSocialModeratorRole(client, moderatorRoles);
      const recorded = await recordedVersions(client);
      const plan = planMigrations(recorded, MIGRATIONS);
      if (!config.grantsOnly && plan.pending.includes('0025_relationship_safety')) {
        await assertRelationshipApiDrained(client, config.relationshipCutover);
      }
      const applied = [];
      if (!config.grantsOnly) {
        for (const version of plan.pending) {
          const sql = await readMigration(version, {root});
          log(`Applying ${version}`);
          // Each file owns its own BEGIN/COMMIT and records its own version.
          await client.query(sql);
          applied.push(version);
        }
      }
      // Grants are idempotent and kept outside the migrations so the restricted
      // role name can differ per deployment.
      await client.query(runtimeGrants(role));
      await client.query(redDayWorkerLoginDenials(config.redDayWorkerRole));
      await client.query(redDayWorkerGrants(config.redDayCapabilityRole));
      await client.query(socialModeratorGrants(config.socialModeratorRole));
      await assertRedDayGrants(client, redDayRoles);
      await assertSocialModeratorGrants(client, moderatorRoles);
      await assertFunctionOwnerAuthority(client, role);
      const after = await recordedVersions(client);
      const finalPlan = planMigrations(after, MIGRATIONS);
      if (!config.grantsOnly && finalPlan.pending.length) {
        fail(`Migrations did not fully record: still pending ${finalPlan.pending.join(', ')}.`);
      }
      const liveBefore = await client.query(`SELECT evidence_live FROM trimmy.career_mission_definitions
        WHERE id='hold-through-red-day' AND evidence_kind='server-red-day-hold'`);
      if (liveBefore.rows?.length !== 1 || typeof liveBefore.rows[0]?.evidence_live !== 'boolean') {
        fail('The red-day mission definition is missing or invalid.');
      }
      let redDayEvidenceLive = liveBefore.rows[0].evidence_live;
      // This is the final deployment mutation. Public environments set the
      // explicit flag only after the Tokens.xyz terms decision is recorded.
      if (config.activateRedDay) {
        await client.query(RED_DAY_ACTIVATION_SQL);
        redDayEvidenceLive = true;
      }
      return Object.freeze({
        alreadyApplied: plan.applied, applied: Object.freeze(applied),
        recorded: Object.freeze(after), grantedRole: role,
        redDayCapabilityRole: config.redDayCapabilityRole,
        redDayWorkerRole: config.redDayWorkerRole,
        socialModeratorRole: config.socialModeratorRole,
        redDayEvidenceLive,
      });
    } finally {
      await client.query('SELECT pg_advisory_unlock($1)', [String(ADVISORY_LOCK_KEY)]);
    }
  } finally {
    await client.end();
  }
}

async function main() {
  const args = process.argv.slice(2);
  const unknown = args.filter(arg => !['--grants-only', '--quiet'].includes(arg));
  if (unknown.length) throw new MigrationError('Usage: node tool/runtime/apply-migrations.mjs [--grants-only] [--quiet]');
  const quiet = args.includes('--quiet');
  const log = quiet ? () => {} : message => process.stdout.write(`${message}\n`);
  const caFile = process.env['TRIMMY_MIGRATION_DATABASE_CA_FILE'];
  let caText;
  if (caFile !== undefined && caFile !== '') {
    if (caFile.length > 4096 || caFile.trim() !== caFile || /[\u0000-\u001f\u007f]/.test(caFile)) {
      throw new MigrationError('TRIMMY_MIGRATION_DATABASE_CA_FILE is malformed.');
    }
    try { caText = await readFile(caFile, 'utf8'); }
    catch { throw new MigrationError('TRIMMY_MIGRATION_DATABASE_CA_FILE could not be read.'); }
  }
  const config = readMigrationConfig(process.env, caText);
  const grantsOnly = config.grantsOnly || args.includes('--grants-only');
  // An operator needs the real reason a deploy failed, with the credential
  // stripped out of whatever the driver reported.
  const redact = text => text.split(config.database.password).join('[redacted]');
  let result;
  try {
    result = await applyMigrations({...config, grantsOnly}, {log});
  } catch (error) {
    if (error instanceof MigrationError) throw error;
    const code = typeof error?.code === 'string' ? ` [${error.code}]` : '';
    const detail = typeof error?.message === 'string' ? redact(error.message) : 'unknown driver error';
    throw new MigrationError(`Migration failed${code}: ${detail}`);
  }
  const summary = grantsOnly
    ? `Grants refreshed for ${result.grantedRole}.`
    : result.applied.length === 0
      ? `No pending migrations. Recorded: ${result.recorded.join(', ')}.`
      : `Applied ${result.applied.length} migration(s): ${result.applied.join(', ')}.`;
  process.stdout.write(`${summary} Red-day evidence is ${result.redDayEvidenceLive ? 'active' : 'locked'}.\n`);
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main().catch(error => {
    process.stderr.write(`${error instanceof MigrationError ? error.message : 'Migration failed.'}\n`);
    process.exitCode = 1;
  });
}
