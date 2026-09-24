import assert from 'node:assert/strict';
import {test} from 'node:test';
import {
  GuestRetentionError, parseGuestRetentionRow, parseRetentionArguments,
  readGuestRetentionConfig, runGuestRetention,
} from './run-guest-retention.mjs';

const ownerUrl = 'postgresql://owner:owner-secret@db.example:5432/trimmy';
const throws = (fn, match) => assert.throws(fn,
  error => error instanceof GuestRetentionError && match.test(error.message));

test('retention arguments keep every invocation bounded', () => {
  assert.deepEqual(parseRetentionArguments([]), {batch: 500});
  assert.deepEqual(parseRetentionArguments(['--batch', '1']), {batch: 1});
  assert.deepEqual(parseRetentionArguments(['--batch', '1000']), {batch: 1000});
  for (const args of [['--batch'], ['--batch', '0'], ['--batch', '1001'], ['--batch', '1.5'],
    ['--drain'], ['--batch', '5', '--batch', '6']]) {
    throws(() => parseRetentionArguments(args), /Usage|batch size/);
  }
});

test('retention config reuses strict owner TLS parsing without weakening it', () => {
  const config = readGuestRetentionConfig({TRIMMY_MIGRATION_DATABASE_URL: ownerUrl});
  assert.equal(config.database.user, 'owner');
  assert.equal(config.database.ssl.rejectUnauthorized, true);
  assert.equal(config.database.application_name, 'trimmy-guest-retention');
  assert.equal(config.database.lock_timeout, 5_000);
  assert.equal(config.database.statement_timeout, 30_000);
  assert.equal(config.database.query_timeout, 35_000);
  assert.throws(() => readGuestRetentionConfig({
    TRIMMY_MIGRATION_DATABASE_URL: `${ownerUrl}?sslmode=disable`,
  }), /query or fragment/);
});

test('retention results enforce bounded counts and the busy-lock shape', () => {
  assert.deepEqual(parseGuestRetentionRow({lock_acquired: true, source_attempts_deleted: 7,
    rate_windows_deleted: 6, sessions_redacted: 5, has_more: false}, 7), {
    lockAcquired: true, sourceAttemptsDeleted: 7, rateWindowsDeleted: 6,
    sessionsRedacted: 5, hasMore: false,
  });
  assert.deepEqual(parseGuestRetentionRow({lock_acquired: false, source_attempts_deleted: 0,
    rate_windows_deleted: 0, sessions_redacted: 0, has_more: true}, 7), {
    lockAcquired: false, sourceAttemptsDeleted: 0, rateWindowsDeleted: 0,
    sessionsRedacted: 0, hasMore: true,
  });
  throws(() => parseGuestRetentionRow({lock_acquired: true, source_attempts_deleted: 8,
    rate_windows_deleted: 0, sessions_redacted: 0, has_more: false}, 7), /source-attempt/);
  throws(() => parseGuestRetentionRow({lock_acquired: false, source_attempts_deleted: 0,
    rate_windows_deleted: 0, sessions_redacted: 0, has_more: false}, 7), /lock result/);
});

test('operator makes exactly one parameterized retention call after proving TLS', async () => {
  const queries = [];
  class Client {
    constructor(config) { this.config = config; }
    async connect() { this.connected = true; }
    async query(sql, values) {
      queries.push({sql, values});
      if (sql.startsWith('SELECT ssl')) return {rows: [{ssl: true}]};
      return {rows: [{lock_acquired: true, source_attempts_deleted: 2,
        rate_windows_deleted: 1, sessions_redacted: 0, has_more: true}]};
    }
    async end() { this.ended = true; }
  }
  const result = await runGuestRetention(readGuestRetentionConfig({
    TRIMMY_MIGRATION_DATABASE_URL: ownerUrl,
  }), 2, {Client});
  assert.equal(result.hasMore, true);
  assert.equal(queries.length, 2);
  assert.deepEqual(queries[1].values, [2]);
  assert.match(queries[1].sql, /guest_auth_retention\(\$1::integer\)/);
});

test('operator refuses a plaintext database session before retention', async () => {
  let retentionCalled = false;
  let ended = false;
  class Client {
    async connect() {}
    async query(sql) {
      if (sql.startsWith('SELECT ssl')) return {rows: [{ssl: false}]};
      retentionCalled = true;
      return {rows: []};
    }
    async end() { ended = true; }
  }
  await assert.rejects(runGuestRetention(readGuestRetentionConfig({
    TRIMMY_MIGRATION_DATABASE_URL: ownerUrl,
  }), 5, {Client}), error => error instanceof GuestRetentionError && /not TLS/.test(error.message));
  assert.equal(retentionCalled, false);
  assert.equal(ended, true);
});
