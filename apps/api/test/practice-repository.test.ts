import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { describe, it } from 'node:test';
import { canonicalPracticeProgress, parsePracticeProgress } from '@trimmy/domain';
import type { Pool, PoolClient } from 'pg';
import { PostgresPracticeRepository } from '../src/postgres-practice-repository.js';
import { PracticeRepositoryError, parsePracticeUserId, parsePracticeWrite } from '../src/practice-repository.js';
import type { PracticeWrite } from '../src/practice-repository.js';

const userId = '00000000-0000-4000-a000-000000000001';
const mutationId = 'AB000000-0000-4000-A000-000000000001';
const empty = parsePracticeProgress({version: 3, active: null, completions: {}});
const command: PracticeWrite = {mutationId, baseRevision: 0, progress: empty};
const timestamp = '2026-09-14T12:00:00.000Z';
const completed = parsePracticeProgress({version: 3, active: null, completions: {
  'check-the-date': {activityId: 'check-the-date', selectedChoiceId: 'add-year', corrected: false,
    completedAt: '2026-09-14T12:00:00.123456Z', importedFromLegacy: false},
}});

type Row = Record<string, unknown>;
class ScriptedConnection {
  readonly queries: {sql: string; parameters: readonly unknown[]}[] = [];
  readonly releases: (Error | undefined)[] = [];
  connections = 0;
  unsafeRole = false;
  accountExists = true;
  state: Row | undefined;
  receipt: Row | undefined;
  failReceipt = false;
  failCommit = false;
  failRollback = false;
  beforeCommit: (() => Promise<void>) | undefined;
  beforeConnect: (() => Promise<void>) | undefined;

  readonly pool = {connect: async () => {
    this.connections++;
    await this.beforeConnect?.();
    return {
      query: async (rawSql: string, parameters: unknown[] = []) => {
        const sql = rawSql.replace(/\s+/g, ' ').trim();
        this.queries.push({sql, parameters});
        if (sql.includes('AS unsafe_role')) return {rows: [{unsafe_role: this.unsafeRole}]};
        if (sql.includes('practice_account_exists')) return {rows: [{account_exists: this.accountExists}]};
        if (sql.startsWith('SELECT request_hash')) return {rows: this.receipt ? [this.receipt] : []};
        if (sql.startsWith('SELECT revision')) return {rows: this.state ? [this.state] : []};
        if (sql.startsWith('INSERT INTO trimmy.practice_progress')) {
          return {rows: [{revision: '1', progress: JSON.parse(parameters[1] as string) as unknown, updated_at: timestamp}]};
        }
        if (sql.startsWith('UPDATE trimmy.practice_progress')) {
          return {rows: [{revision: String(parameters[1]), progress: JSON.parse(parameters[2] as string) as unknown, updated_at: timestamp}]};
        }
        if (sql.startsWith('INSERT INTO trimmy.practice_mutation_receipts') && this.failReceipt) throw new Error('simulated receipt failure');
        if (sql === 'COMMIT') {
          await this.beforeCommit?.();
          if (this.failCommit) throw new Error('simulated commit failure');
        }
        if (sql === 'ROLLBACK' && this.failRollback) throw new Error('simulated rollback failure');
        return {rows: []};
      },
      release: (error?: Error) => { this.releases.push(error); },
    } as unknown as PoolClient;
  }} satisfies Pick<Pool, 'connect'>;
}

function code(expected: string): (error: unknown) => boolean {
  return error => error instanceof PracticeRepositoryError && error.code === expected;
}

function receiptHash(write: PracticeWrite): string {
  return createHash('sha256').update(`{"baseRevision":${write.baseRevision},"progress":${canonicalPracticeProgress(write.progress)}}`).digest('hex');
}

describe('practice repository boundaries and transaction cleanup', () => {
  it('upgrades v3 to v4 without changing first notes or historical receipt bodies', async () => {
    const connection = new ScriptedConnection();
    connection.state = {revision: '1', progress: completed, updated_at: timestamp};
    const upgraded = parsePracticeProgress({...completed, version: 4});
    const saved = await new PostgresPracticeRepository(connection.pool).put(userId, {...command, baseRevision: 1, progress: upgraded});
    assert.equal(saved.revision, 2);
    assert.equal(saved.progress?.version, 4);
    assert.deepEqual(saved.progress?.completions, completed.completions);
    const receipt = connection.queries.find(query => query.sql.startsWith('INSERT INTO trimmy.practice_mutation_receipts'))!;
    assert.equal(receipt.parameters[4], canonicalPracticeProgress(upgraded));
    assert.equal(connection.queries.some(query => query.sql.startsWith('UPDATE trimmy.practice_mutation_receipts')), false);
  });

  it('rejects a fresh downgrade but replays the exact v3 receipt before the current v4 snapshot', async () => {
    const connection = new ScriptedConnection();
    connection.state = {revision: '2', progress: parsePracticeProgress({...completed, version: 4}), updated_at: timestamp};
    const repository = new PostgresPracticeRepository(connection.pool);
    await assert.rejects(repository.put(userId, {...command, baseRevision: 2, progress: completed}), code('PRACTICE_VERSION_DOWNGRADE'));
    assert.equal(connection.queries.some(query => /^(UPDATE|INSERT INTO) trimmy.practice/.test(query.sql)), false);
    connection.queries.length = 0;
    connection.receipt = {request_hash: receiptHash(command), revision: '1', progress: empty, updated_at: timestamp};
    const replay = await repository.put(userId, command);
    assert.equal(replay.revision, 1);
    assert.equal(replay.progress?.version, 3);
    assert.equal(connection.queries.some(query => query.sql.startsWith('SELECT revision')), false);
    await assert.rejects(repository.put(userId, {...command, progress: parsePracticeProgress({...empty, version: 4})}), code('PRACTICE_IDEMPOTENCY_CONFLICT'));
  });

  it('normalizes UUIDs and rejects malformed direct inputs before connecting', async () => {
    assert.equal(parsePracticeUserId(mutationId), mutationId.toLowerCase());
    const connection = new ScriptedConnection();
    const repository = new PostgresPracticeRepository(connection.pool);
    await assert.rejects(repository.get("'; DROP TABLE trimmy.users; --"), code('PRACTICE_INVALID_INPUT'));
    for (const baseRevision of [-1, 0.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1, '0']) {
      await assert.rejects(repository.put(userId, {...command, baseRevision} as PracticeWrite), code('PRACTICE_INVALID_INPUT'));
    }
    for (const invalid of [null, [], {...command, mutationId: 'x'}, {...command, unexpected: true}, {...command, progress: {...empty, version: 7}}]) {
      await assert.rejects(repository.put(userId, invalid as PracticeWrite), code('PRACTICE_INVALID_INPUT'));
    }
    let getterCalled = false;
    const getter = {...command};
    Object.defineProperty(getter, 'progress', {get() { getterCalled = true; return empty; }, enumerable: true});
    assert.throws(() => parsePracticeWrite(getter), code('PRACTICE_INVALID_INPUT'));
    assert.equal(getterCalled, false);
    assert.equal(connection.connections, 0);
  });

  it('reads an empty existing account in a local-context read-only transaction', async () => {
    const connection = new ScriptedConnection();
    const result = await new PostgresPracticeRepository(connection.pool).get(userId);
    assert.deepEqual(result, {revision: 0, progress: null, updatedAt: null});
    assert.equal(connection.queries[0]!.sql, 'BEGIN READ ONLY');
    const context = connection.queries.find(query => query.sql.startsWith('SELECT set_config'))!;
    assert.match(context.sql, /, true\)/);
    assert.deepEqual(context.parameters, [userId]);
    assert.equal(connection.queries.at(-1)!.sql, 'COMMIT');
    assert.deepEqual(connection.releases, [undefined]);
    assert.equal(Object.isFrozen(result), true);
  });

  it('rejects privileged runtime roles and unavailable accounts with rollback/release', async () => {
    for (const kind of ['role', 'account']) {
      const connection = new ScriptedConnection();
      connection.unsafeRole = kind === 'role';
      connection.accountExists = kind !== 'account';
      await assert.rejects(new PostgresPracticeRepository(connection.pool).get(userId),
        code(kind === 'role' ? 'PRACTICE_RUNTIME_ROLE_INVALID' : 'PRACTICE_ACCOUNT_NOT_FOUND'));
      assert.equal(connection.queries.at(-1)!.sql, 'ROLLBACK');
      assert.deepEqual(connection.releases, [undefined]);
    }
  });

  it('replays the original receipt before consulting a newer current revision', async () => {
    const connection = new ScriptedConnection();
    connection.receipt = {request_hash: receiptHash(command), revision: '1', progress: empty, updated_at: timestamp};
    connection.state = {revision: '8', progress: completed, updated_at: timestamp};
    const result = await new PostgresPracticeRepository(connection.pool).put(userId, command);
    assert.equal(result.revision, 1);
    assert.deepEqual(result.progress, empty);
    assert.equal(connection.queries.some(query => query.sql.startsWith('SELECT revision')), false);
    assert.equal(connection.queries.some(query => query.sql.startsWith('INSERT')), false);
    const receipt = connection.queries.find(query => query.sql.startsWith('SELECT request_hash'))!;
    assert.deepEqual(receipt.parameters, [userId, mutationId.toLowerCase()]);
    assert.deepEqual(connection.releases, [undefined]);
  });

  it('rejects mutation UUID rebinding even when the new base revision matches', async () => {
    const connection = new ScriptedConnection();
    connection.receipt = {request_hash: receiptHash(command), revision: '1', progress: empty, updated_at: timestamp};
    await assert.rejects(new PostgresPracticeRepository(connection.pool).put(userId, {...command, baseRevision: 1}), code('PRACTICE_IDEMPOTENCY_CONFLICT'));
    assert.equal(connection.queries.at(-1)!.sql, 'ROLLBACK');
    assert.equal(connection.queries.some(query => query.sql.startsWith('INSERT')), false);
  });

  it('revision conflicts carry the validated current account snapshot', async () => {
    const connection = new ScriptedConnection();
    connection.state = {revision: '2', progress: completed, updated_at: timestamp};
    await assert.rejects(new PostgresPracticeRepository(connection.pool).put(userId, command), error => {
      assert.ok(error instanceof PracticeRepositoryError);
      assert.equal(error.code, 'PRACTICE_REVISION_CONFLICT');
      assert.deepEqual(error.currentSnapshot, {revision: 2, progress: completed, updatedAt: timestamp});
      assert.equal(Object.isFrozen(error.currentSnapshot!.progress!.completions), true);
      return true;
    });
  });

  it('refuses first completion removal and microsecond timestamp replacement', async () => {
    for (const progress of [empty, parsePracticeProgress({
      ...completed, completions: {'check-the-date': {...completed.completions['check-the-date'], completedAt: '2026-09-14T12:00:00.123457Z'}},
    })]) {
      const connection = new ScriptedConnection();
      connection.state = {revision: '1', progress: completed, updated_at: timestamp};
      await assert.rejects(new PostgresPracticeRepository(connection.pool).put(userId, {...command, baseRevision: 1, progress}), code('PRACTICE_HISTORY_CONFLICT'));
      assert.equal(connection.queries.some(query => query.sql.startsWith('UPDATE')), false);
    }
  });

  it('refuses safe-integer revision overflow without issuing an update', async () => {
    const connection = new ScriptedConnection();
    connection.state = {revision: String(Number.MAX_SAFE_INTEGER), progress: empty, updated_at: timestamp};
    await assert.rejects(new PostgresPracticeRepository(connection.pool).put(userId, {...command, baseRevision: Number.MAX_SAFE_INTEGER}), code('PRACTICE_REVISION_EXHAUSTED'));
    assert.equal(connection.queries.some(query => query.sql.startsWith('UPDATE')), false);
  });

  it('fails closed on malformed stored revisions, timestamps or progress', async () => {
    for (const invalid of [
      {revision: '9007199254740992', progress: empty, updated_at: timestamp},
      {revision: '1', progress: empty, updated_at: '2026-02-31T00:00:00.000Z'},
      {revision: '1', progress: {...empty, version: 8}, updated_at: timestamp},
    ]) {
      const connection = new ScriptedConnection(); connection.state = invalid;
      await assert.rejects(new PostgresPracticeRepository(connection.pool).get(userId), code('PRACTICE_STORAGE_INVALID'));
      assert.equal(connection.queries.at(-1)!.sql, 'ROLLBACK');
      assert.deepEqual(connection.releases, [undefined]);
    }
  });

  it('rolls back a receipt failure instead of acknowledging the earlier state write', async () => {
    const connection = new ScriptedConnection(); connection.failReceipt = true;
    await assert.rejects(new PostgresPracticeRepository(connection.pool).put(userId, command), /simulated receipt failure/);
    assert.equal(connection.queries.some(query => query.sql.startsWith('INSERT INTO trimmy.practice_progress')), true);
    assert.equal(connection.queries.some(query => query.sql === 'COMMIT'), false);
    assert.equal(connection.queries.at(-1)!.sql, 'ROLLBACK');
    assert.deepEqual(connection.releases, [undefined]);
  });

  it('destroys the pooled client if rollback cannot restore a known session state', async () => {
    const connection = new ScriptedConnection(); connection.failCommit = true; connection.failRollback = true;
    await assert.rejects(new PostgresPracticeRepository(connection.pool).put(userId, command), /simulated commit failure/);
    assert.equal(connection.releases.length, 1);
    assert.ok(connection.releases[0] instanceof Error);
    assert.equal(connection.releases[0]!.message, 'Practice transaction cleanup failed.');
  });

  it('clones before awaiting a connection and returns only after commit acknowledgement', async () => {
    const connection = new ScriptedConnection();
    let connect: () => void = () => { throw new Error('gate uninitialized'); };
    let commit: () => void = () => { throw new Error('gate uninitialized'); };
    let reachedCommit: () => void = () => { throw new Error('gate uninitialized'); };
    const atCommit = new Promise<void>(resolve => { reachedCommit = resolve; });
    connection.beforeConnect = () => new Promise<void>(resolve => { connect = resolve; });
    connection.beforeCommit = () => { reachedCommit(); return new Promise<void>(resolve => { commit = resolve; }); };
    const mutable = {version: 3, active: null, completions: {}};
    let resolved = false;
    const pending = new PostgresPracticeRepository(connection.pool).put(userId, {...command, progress: mutable as typeof empty}).then(result => { resolved = true; return result; });
    mutable.version = 999;
    connect();
    await atCommit;
    assert.equal(resolved, false);
    assert.equal(connection.releases.length, 0);
    commit();
    const result = await pending;
    assert.deepEqual(result, {revision: 1, progress: empty, updatedAt: timestamp});
    assert.equal(Object.isFrozen(result.progress), true);
    assert.deepEqual(connection.releases, [undefined]);
  });
});
