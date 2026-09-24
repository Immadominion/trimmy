#!/usr/bin/env node
// Runs one bounded owner-only guest authentication-retention batch. Schedule
// this command with release credentials in a separate job; never place those
// credentials on the serving API process.
import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import pg from 'pg';
import {parseOwnerDatabaseUrl, readCertificateBundle} from './apply-migrations.mjs';

export class GuestRetentionError extends Error {
  constructor(message) { super(message); this.name = 'GuestRetentionError'; }
}

function fail(message) { throw new GuestRetentionError(message); }

export function parseRetentionArguments(args) {
  if (!Array.isArray(args)) fail('Guest retention arguments are invalid.');
  let batch = 500;
  let seenBatch = false;
  for (let index = 0; index < args.length; index++) {
    const argument = args[index];
    if (argument !== '--batch' || seenBatch || index + 1 >= args.length) {
      fail('Usage: node tool/runtime/run-guest-retention.mjs [--batch 1..1000]');
    }
    seenBatch = true;
    const value = args[++index];
    if (!/^[1-9][0-9]{0,3}$/.test(value ?? '')) {
      fail('Guest retention batch size must be an integer from 1 to 1000.');
    }
    batch = Number(value);
    if (batch > 1000) fail('Guest retention batch size must be an integer from 1 to 1000.');
  }
  return Object.freeze({batch});
}

export function readGuestRetentionConfig(env, caText) {
  try {
    const ca = caText === undefined ? undefined : readCertificateBundle(caText);
    const database = parseOwnerDatabaseUrl(env['TRIMMY_MIGRATION_DATABASE_URL'], ca);
    return Object.freeze({database: Object.freeze({
      ...database,
      application_name: 'trimmy-guest-retention',
      // One scheduled run must finish or fail before the next one. The SQL is
      // already row-bounded; these caps also bound lock and transport stalls.
      lock_timeout: 5_000,
      statement_timeout: 30_000,
      query_timeout: 35_000,
    })});
  } catch (error) {
    fail(error instanceof Error ? error.message : 'Guest retention configuration is invalid.');
  }
}

function count(value, name, batch) {
  if (!Number.isSafeInteger(value) || value < 0 || value > batch) {
    fail(`Guest retention returned an invalid ${name}.`);
  }
  return value;
}

export function parseGuestRetentionRow(row, batch) {
  if (row === null || typeof row !== 'object' || Array.isArray(row) ||
      typeof row.lock_acquired !== 'boolean' || typeof row.has_more !== 'boolean') {
    fail('Guest retention returned an invalid result.');
  }
  const result = Object.freeze({
    lockAcquired: row.lock_acquired,
    sourceAttemptsDeleted: count(row.source_attempts_deleted, 'source-attempt count', batch),
    rateWindowsDeleted: count(row.rate_windows_deleted, 'rate-window count', batch),
    sessionsRedacted: count(row.sessions_redacted, 'session count', batch),
    hasMore: row.has_more,
  });
  if (!result.lockAcquired && (result.sourceAttemptsDeleted !== 0 || result.rateWindowsDeleted !== 0 ||
      result.sessionsRedacted !== 0 || !result.hasMore)) {
    fail('Guest retention returned an invalid lock result.');
  }
  return result;
}

export async function runGuestRetention(config, batch, {Client = pg.Client} = {}) {
  if (!Number.isSafeInteger(batch) || batch < 1 || batch > 1000) {
    fail('Guest retention batch size must be an integer from 1 to 1000.');
  }
  const client = new Client(config.database);
  await client.connect();
  try {
    const encrypted = await client.query('SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()');
    if (encrypted.rows?.length !== 1 || encrypted.rows[0]?.ssl !== true) {
      fail('The guest retention connection is not TLS encrypted.');
    }
    const response = await client.query(
      `SELECT lock_acquired, source_attempts_deleted, rate_windows_deleted,
        sessions_redacted, has_more FROM trimmy.guest_auth_retention($1::integer)`, [batch]);
    if (response.rows?.length !== 1) fail('Guest retention returned an invalid result.');
    return parseGuestRetentionRow(response.rows[0], batch);
  } finally {
    await client.end();
  }
}

async function main() {
  const {batch} = parseRetentionArguments(process.argv.slice(2));
  const caFile = process.env['TRIMMY_MIGRATION_DATABASE_CA_FILE'];
  let caText;
  if (caFile !== undefined && caFile !== '') {
    if (caFile.length > 4096 || caFile.trim() !== caFile || /[\u0000-\u001f\u007f]/.test(caFile)) {
      fail('TRIMMY_MIGRATION_DATABASE_CA_FILE is malformed.');
    }
    try { caText = await readFile(caFile, 'utf8'); }
    catch { fail('TRIMMY_MIGRATION_DATABASE_CA_FILE could not be read.'); }
  }
  const config = readGuestRetentionConfig(process.env, caText);
  const redact = text => text.split(config.database.password).join('[redacted]');
  let result;
  try { result = await runGuestRetention(config, batch); }
  catch (error) {
    if (error instanceof GuestRetentionError) throw error;
    const code = typeof error?.code === 'string' ? ` [${error.code}]` : '';
    const detail = typeof error?.message === 'string' ? redact(error.message) : 'unknown driver error';
    throw new GuestRetentionError(`Guest retention failed${code}: ${detail}`);
  }
  const lock = result.lockAcquired ? 'acquired' : 'busy';
  process.stdout.write(`Guest retention: lock=${lock} sourceAttemptsDeleted=${result.sourceAttemptsDeleted} `
    + `rateWindowsDeleted=${result.rateWindowsDeleted} sessionsRedacted=${result.sessionsRedacted} `
    + `hasMore=${result.hasMore}.\n`);
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main().catch(error => {
    process.stderr.write(`${error instanceof GuestRetentionError ? error.message : 'Guest retention failed.'}\n`);
    process.exitCode = 1;
  });
}
