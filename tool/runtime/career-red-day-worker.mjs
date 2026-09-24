#!/usr/bin/env node
/**
 * One bounded Career red-day worker pass. An external scheduler may invoke
 * this command, but this process never loops or retries on its own.
 */
import {X509Certificate} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import pg from 'pg';
import {TokensCanonicalRedDayReader} from '../../apps/api/dist/career-red-day-market.js';
import {PostgresCareerRedDayRepository} from '../../apps/api/dist/career-red-day-repository.js';
import {CareerRedDayWorker, parseRedDayAssetCatalog} from '../../apps/api/dist/career-red-day-worker.js';
import {
  RED_DAY_CAPABILITY_ROLE, RED_DAY_WORKER_FUNCTIONS, RED_DAY_WORKER_ROLE,
} from './local-secure-runtime.mjs';

export class CareerRedDayRuntimeError extends Error {
  constructor(message) { super(message); this.name = 'CareerRedDayRuntimeError'; }
}
const fail = message => { throw new CareerRedDayRuntimeError(message); };

function certificateBundle(text) {
  if (typeof text !== 'string' || Buffer.byteLength(text, 'utf8') > 65_536) {
    fail('The red-day database CA bundle is invalid.');
  }
  const blocks = text.match(/-----BEGIN CERTIFICATE-----[^-]+-----END CERTIFICATE-----/g);
  if (!blocks || blocks.length > 16) fail('The red-day database CA bundle is invalid.');
  try { for (const block of blocks) new X509Certificate(block); }
  catch { fail('The red-day database CA bundle is invalid.'); }
  return text;
}

function database(raw, ca) {
  if (typeof raw !== 'string' || raw.length < 1 || raw.length > 4_096 || raw.trim() !== raw) {
    fail('TRIMMY_RED_DAY_DATABASE_URL is missing or malformed.');
  }
  let url;
  try { url = new URL(raw); } catch { fail('TRIMMY_RED_DAY_DATABASE_URL is not a valid URL.'); }
  if (!['postgres:', 'postgresql:'].includes(url.protocol) || !url.hostname || url.search || url.hash) {
    fail('TRIMMY_RED_DAY_DATABASE_URL must be a PostgreSQL URL without query or fragment options.');
  }
  const name = decodeURIComponent(url.pathname.slice(1));
  const user = decodeURIComponent(url.username);
  const password = decodeURIComponent(url.password);
  const port = url.port === '' ? 5432 : Number(url.port);
  if (!/^[a-zA-Z0-9_.-]{1,63}$/u.test(name) || !/^[a-zA-Z0-9_.@-]{1,128}$/u.test(user) ||
      !password || password.length > 512 || /[\u0000-\u001f\u007f]/u.test(password) ||
      !Number.isInteger(port) || port < 1 || port > 65_535) {
    fail('TRIMMY_RED_DAY_DATABASE_URL is malformed.');
  }
  return Object.freeze({host: url.hostname.replace(/^\[|\]$/gu, ''), port, database: name, user, password,
    ssl: Object.freeze({rejectUnauthorized: true, ca}), connectionTimeoutMillis: 10_000,
    statement_timeout: 30_000, query_timeout: 35_000, application_name: 'trimmy-career-red-day-worker', max: 1});
}

function roleName(raw, fallback, variable) {
  const value = raw === undefined || raw === '' ? fallback : raw;
  if (typeof value !== 'string' || !/^[a-z_][a-z0-9_]{0,62}$/u.test(value)) {
    fail(`${variable} must be a lowercase PostgreSQL identifier.`);
  }
  return value;
}

export async function readCareerRedDayRuntimeConfig(env, read = readFile) {
  const caPath = env['TRIMMY_RED_DAY_DATABASE_CA_FILE'];
  if (typeof caPath !== 'string' || caPath.length < 1 || caPath.length > 4_096 ||
      caPath.trim() !== caPath || /[\u0000-\u001f\u007f]/u.test(caPath)) {
    fail('TRIMMY_RED_DAY_DATABASE_CA_FILE is missing or malformed.');
  }
  let ca;
  try { ca = certificateBundle(await read(caPath, 'utf8')); }
  catch (error) {
    if (error instanceof CareerRedDayRuntimeError) throw error;
    fail('TRIMMY_RED_DAY_DATABASE_CA_FILE could not be read.');
  }
  const apiKey = env['TOKENS_API_KEY'];
  if (typeof apiKey !== 'string' || apiKey.length < 8 || apiKey.length > 512 || !/^[\x21-\x7e]+$/u.test(apiKey)) {
    fail('TOKENS_API_KEY is missing or malformed.');
  }
  const catalogRaw = env['TRIMMY_RED_DAY_ASSET_CATALOG_JSON'];
  if (catalogRaw === undefined) fail('TRIMMY_RED_DAY_ASSET_CATALOG_JSON is missing.');
  let assets;
  try { assets = parseRedDayAssetCatalog(catalogRaw); }
  catch { fail('TRIMMY_RED_DAY_ASSET_CATALOG_JSON is malformed.'); }
  const rawLimit = env['TRIMMY_RED_DAY_CANDIDATE_LIMIT'] ?? '20';
  if (!/^(?:[1-9]|1[0-9]|20)$/u.test(rawLimit)) fail('TRIMMY_RED_DAY_CANDIDATE_LIMIT must be from 1 to 20.');
  const rawEvidenceLimit = env['TRIMMY_RED_DAY_EVIDENCE_BATCH_LIMIT'] ?? '50';
  if (!/^(?:[1-9]|[1-9][0-9]|100)$/u.test(rawEvidenceLimit)) {
    fail('TRIMMY_RED_DAY_EVIDENCE_BATCH_LIMIT must be from 1 to 100.');
  }
  const parsedDatabase = database(env['TRIMMY_RED_DAY_DATABASE_URL'], ca);
  const workerRole = roleName(env['TRIMMY_RED_DAY_WORKER_ROLE'], RED_DAY_WORKER_ROLE,
    'TRIMMY_RED_DAY_WORKER_ROLE');
  const capabilityRole = roleName(env['TRIMMY_RED_DAY_CAPABILITY_ROLE'], RED_DAY_CAPABILITY_ROLE,
    'TRIMMY_RED_DAY_CAPABILITY_ROLE');
  if (parsedDatabase.user !== workerRole || workerRole === capabilityRole) {
    fail('The red-day database URL must use the dedicated worker login.');
  }
  return Object.freeze({database: parsedDatabase, workerRole, capabilityRole,
    apiKey, assets, candidateLimit: Number(rawLimit), evidenceBatchLimit: Number(rawEvidenceLimit)});
}

const workerLock = '8143072509411021';

function boolean(value) { return value === true || value === 't'; }

/** Prove TLS and the complete login -> NOLOGIN capability boundary, then SET ROLE. */
export async function assertCareerRedDayDatabaseBoundary(client, config) {
  const encrypted = await client.query('SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()');
  if (encrypted.rows?.length !== 1 || encrypted.rows[0]?.ssl !== true) {
    fail('The red-day worker connection is not TLS encrypted.');
  }
  const login = await client.query(`SELECT session_user AS session_user_name,
      current_user AS current_user_name, r.rolcanlogin, r.rolinherit, r.rolsuper,
      r.rolcreatedb, r.rolcreaterole, r.rolreplication, r.rolbypassrls,
      EXISTS (SELECT 1 FROM pg_catalog.pg_database d WHERE d.datdba=r.oid) OR
      EXISTS (SELECT 1 FROM pg_catalog.pg_namespace n WHERE n.nspowner=r.oid) OR
      EXISTS (SELECT 1 FROM pg_catalog.pg_class c WHERE c.relowner=r.oid) OR
      EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.proowner=r.oid) AS owns_objects
    FROM pg_catalog.pg_roles r WHERE r.rolname=session_user`);
  const loginRow = login.rows?.[0];
  if (login.rows?.length !== 1 || loginRow?.session_user_name !== config.workerRole ||
      loginRow?.current_user_name !== config.workerRole || !boolean(loginRow.rolcanlogin) ||
      boolean(loginRow.rolinherit) || boolean(loginRow.rolsuper) || boolean(loginRow.rolcreatedb) ||
      boolean(loginRow.rolcreaterole) || boolean(loginRow.rolreplication) ||
      boolean(loginRow.rolbypassrls) || boolean(loginRow.owns_objects)) {
    fail('The red-day worker login does not have the required least-privilege shape.');
  }
  const directPrivileges = await client.query(`SELECT
      has_schema_privilege(current_user,'trimmy','USAGE') AS schema_usage,
      has_schema_privilege(current_user,'trimmy','CREATE') AS schema_create,
      (SELECT count(*)::integer FROM pg_catalog.pg_proc p
        JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='trimmy' AND has_function_privilege(current_user,p.oid,'EXECUTE')) AS functions,
      (SELECT count(*)::integer FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='trimmy' AND c.relkind IN ('r','p','v','m','f') AND (
          has_table_privilege(current_user,c.oid,'SELECT') OR
          has_table_privilege(current_user,c.oid,'INSERT') OR
          has_table_privilege(current_user,c.oid,'UPDATE') OR
          has_table_privilege(current_user,c.oid,'DELETE') OR
          has_table_privilege(current_user,c.oid,'TRUNCATE') OR
          has_table_privilege(current_user,c.oid,'REFERENCES') OR
          has_table_privilege(current_user,c.oid,'TRIGGER'))) AS tables,
      (SELECT count(*)::integer FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
        WHERE n.nspname='trimmy' AND c.relkind='S' AND (
          has_sequence_privilege(current_user,c.oid,'USAGE') OR
          has_sequence_privilege(current_user,c.oid,'SELECT') OR
          has_sequence_privilege(current_user,c.oid,'UPDATE'))) AS sequences`);
  const directRow = directPrivileges.rows?.[0];
  if (directPrivileges.rows?.length !== 1 || boolean(directRow?.schema_usage) ||
      boolean(directRow?.schema_create) || Number(directRow?.functions) !== 0 ||
      Number(directRow?.tables) !== 0 || Number(directRow?.sequences) !== 0) {
    fail('The red-day worker login has direct database privileges.');
  }
  const reachable = await client.query(`WITH RECURSIVE reachable(oid) AS (
      SELECT oid FROM pg_catalog.pg_roles WHERE rolname=session_user
      UNION
      SELECT membership.roleid FROM pg_catalog.pg_auth_members membership
      JOIN reachable reachable_role ON reachable_role.oid=membership.member
    )
    SELECT r.rolname, r.rolcanlogin, r.rolinherit, r.rolsuper, r.rolcreatedb,
      r.rolcreaterole, r.rolreplication, r.rolbypassrls,
      EXISTS (SELECT 1 FROM pg_catalog.pg_database d WHERE d.datdba=r.oid) OR
      EXISTS (SELECT 1 FROM pg_catalog.pg_namespace n WHERE n.nspowner=r.oid) OR
      EXISTS (SELECT 1 FROM pg_catalog.pg_class c WHERE c.relowner=r.oid) OR
      EXISTS (SELECT 1 FROM pg_catalog.pg_proc p WHERE p.proowner=r.oid) AS owns_objects
    FROM reachable JOIN pg_catalog.pg_roles r ON r.oid=reachable.oid
    WHERE r.rolname <> session_user ORDER BY r.rolname`);
  const capability = reachable.rows?.[0];
  if (reachable.rows?.length !== 1 || capability?.rolname !== config.capabilityRole ||
      boolean(capability.rolcanlogin) || boolean(capability.rolinherit) ||
      boolean(capability.rolsuper) || boolean(capability.rolcreatedb) ||
      boolean(capability.rolcreaterole) || boolean(capability.rolreplication) ||
      boolean(capability.rolbypassrls) || boolean(capability.owns_objects)) {
    fail('The red-day worker must reach exactly one safe NOLOGIN capability role.');
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
  [config.capabilityRole, config.workerRole]);
  const edge = membership.rows?.[0];
  if (membership.rows?.length !== 1 || Number(edge?.count) !== 1 || boolean(edge?.admin_option) ||
      boolean(edge?.inherit_option) || !boolean(edge?.set_option)) {
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
    WHERE role_row.rolname<>$1 ORDER BY role_row.rolname`, [config.capabilityRole]);
  if (ingress.rows?.length !== 1 || ingress.rows[0]?.rolname !== config.workerRole) {
    fail('Only the dedicated red-day worker may reach the capability role.');
  }
  await client.query(`SET ROLE ${config.capabilityRole}`);
  const identity = await client.query('SELECT session_user AS session_user_name, current_user AS current_user_name');
  if (identity.rows?.length !== 1 || identity.rows[0]?.session_user_name !== config.workerRole ||
      identity.rows[0]?.current_user_name !== config.capabilityRole) {
    fail('The red-day worker could not enter its capability role.');
  }
  const capabilitySchema = await client.query(`SELECT
    has_schema_privilege(current_user,'trimmy','USAGE') AS schema_usage,
    has_schema_privilege(current_user,'trimmy','CREATE') AS schema_create`);
  if (capabilitySchema.rows?.length !== 1 || !boolean(capabilitySchema.rows[0]?.schema_usage) ||
      boolean(capabilitySchema.rows[0]?.schema_create)) {
    fail('The red-day capability must have schema usage without create authority.');
  }
  const functions = await client.query(`SELECT p.oid::text AS oid
    FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='trimmy' AND has_function_privilege(current_user,p.oid,'EXECUTE')
    ORDER BY p.oid`);
  const resolved = await client.query(`SELECT pg_catalog.to_regprocedure('trimmy.' || signature)::oid::text AS oid
    FROM unnest($1::text[]) AS expected(signature) ORDER BY oid`, [RED_DAY_WORKER_FUNCTIONS]);
  const actualFunctions = (functions.rows ?? []).map(row => row.oid).sort();
  const expectedFunctions = (resolved.rows ?? []).map(row => row.oid).sort();
  if (expectedFunctions.some(value => typeof value !== 'string')) {
    fail('A required red-day worker function is missing.');
  }
  if (JSON.stringify(actualFunctions) !== JSON.stringify(expectedFunctions)) {
    fail('The red-day capability does not have its exact four-function grant set.');
  }
  const tablePrivileges = await client.query(`SELECT count(*)::integer AS count
    FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='trimmy' AND c.relkind IN ('r','p','v','m','f') AND (
      has_table_privilege(current_user,c.oid,'SELECT') OR
      has_table_privilege(current_user,c.oid,'INSERT') OR
      has_table_privilege(current_user,c.oid,'UPDATE') OR
      has_table_privilege(current_user,c.oid,'DELETE') OR
      has_table_privilege(current_user,c.oid,'TRUNCATE') OR
      has_table_privilege(current_user,c.oid,'REFERENCES') OR
      has_table_privilege(current_user,c.oid,'TRIGGER'))`);
  if (tablePrivileges.rows?.length !== 1 || Number(tablePrivileges.rows[0]?.count) !== 0) {
    fail('The red-day capability has table privileges.');
  }
  const sequencePrivileges = await client.query(`SELECT count(*)::integer AS count
    FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='trimmy' AND c.relkind='S' AND (
      has_sequence_privilege(current_user,c.oid,'USAGE') OR
      has_sequence_privilege(current_user,c.oid,'SELECT') OR
      has_sequence_privilege(current_user,c.oid,'UPDATE'))`);
  if (sequencePrivileges.rows?.length !== 1 || Number(sequencePrivileges.rows[0]?.count) !== 0) {
    fail('The red-day capability has sequence privileges.');
  }
}

export async function runCareerRedDayWorker(config, {Pool = pg.Pool} = {}) {
  const pool = new Pool(config.database);
  const client = await pool.connect();
  let lockHeld = false;
  try {
    await assertCareerRedDayDatabaseBoundary(client, config);
    const lock = await client.query('SELECT pg_try_advisory_lock($1::bigint) AS held', [workerLock]);
    lockHeld = lock.rows[0]?.held === true;
    if (!lockHeld) return Object.freeze({skipped: true, reason: 'worker-already-running'});
    const repository = new PostgresCareerRedDayRepository(client);
    const market = new TokensCanonicalRedDayReader({apiKey: config.apiKey});
    const result = await new CareerRedDayWorker({repository, market, assets: config.assets,
      candidateLimit: config.candidateLimit,
      evidenceBatchLimit: config.evidenceBatchLimit}).runOnce();
    return Object.freeze({skipped: false, ...result});
  } finally {
    if (lockHeld) await client.query('SELECT pg_advisory_unlock($1::bigint)', [workerLock]).catch(() => {});
    client.release();
    await pool.end();
  }
}

async function main() {
  if (process.argv.length !== 3 || process.argv[2] !== '--once') {
    fail('Usage: node tool/runtime/career-red-day-worker.mjs --once');
  }
  const config = await readCareerRedDayRuntimeConfig(process.env);
  const result = await runCareerRedDayWorker(config);
  process.stdout.write(`${JSON.stringify(result)}\n`);
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main().catch(error => {
    const suffix = typeof error?.code === 'string' && /^[A-Z0-9]{5}$/u.test(error.code)
      ? ` [${error.code}]` : '';
    process.stderr.write(`${error instanceof CareerRedDayRuntimeError ? error.message : `Red-day worker failed${suffix}.`}\n`);
    process.exitCode = 1;
  });
}
