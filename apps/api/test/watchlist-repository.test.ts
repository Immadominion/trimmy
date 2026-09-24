import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { describe, it } from 'node:test';
import type { Pool, PoolClient } from 'pg';
import { PostgresWatchlistRepository } from '../src/postgres-watchlist-repository.js';
import {
  WatchlistRepositoryError, parseWatchlistAssetIds, parseWatchlistSnapshot,
  parseWatchlistUserId, parseWatchlistWrite,
} from '../src/watchlist-repository.js';
import type { WatchlistWrite } from '../src/watchlist-repository.js';

const userId = '00000000-0000-4000-a000-000000000001';
const mutationId = 'AB000000-0000-4000-A000-000000000001';
const allowedAssetIds = new Set(['forma', 'orbital', 'grove']);
const command: WatchlistWrite = {mutationId, baseRevision: 0, assetIds: ['forma', 'orbital']};
const timestamp = '2026-09-14T12:00:00.000Z';
type Row = Record<string, unknown>;

class Connection {
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
  loseCompareAndSwap = false;
  beforeConnect: (() => Promise<void>) | undefined;
  beforeCommit: (() => Promise<void>) | undefined;
  readonly pool = {connect: async () => {
    this.connections++;
    await this.beforeConnect?.();
    return {
      query: async (raw: string, parameters: unknown[] = []) => {
        const sql = raw.replace(/\s+/g, ' ').trim();
        this.queries.push({sql, parameters});
        if (sql.includes('AS unsafe_role')) return {rows: [{unsafe_role: this.unsafeRole}]};
        if (sql.includes('practice_account_exists')) return {rows: [{account_exists: this.accountExists}]};
        if (sql.startsWith('SELECT request_hash')) return {rows: this.receipt ? [this.receipt] : []};
        if (sql.startsWith('SELECT revision')) return {rows: this.state ? [this.state] : []};
        if (sql.startsWith('INSERT INTO trimmy.watchlists')) return {rows: this.loseCompareAndSwap ? [] : [{revision: '1', asset_ids: JSON.parse(parameters[1] as string) as unknown, updated_at: timestamp}]};
        if (sql.startsWith('UPDATE trimmy.watchlists')) return {rows: this.loseCompareAndSwap ? [] : [{revision: String(parameters[1]), asset_ids: JSON.parse(parameters[2] as string) as unknown, updated_at: timestamp}]};
        if (sql.startsWith('INSERT INTO trimmy.watchlist_mutation_receipts') && this.failReceipt) throw new Error('receipt failed');
        if (sql === 'COMMIT') { await this.beforeCommit?.(); if (this.failCommit) throw new Error('commit failed'); }
        if (sql === 'ROLLBACK' && this.failRollback) throw new Error('rollback failed');
        return {rows: []};
      },
      release: (error?: Error) => { this.releases.push(error); },
    } as unknown as PoolClient;
  }} satisfies Pick<Pool, 'connect'>;
  repository() { return new PostgresWatchlistRepository(this.pool, {allowedAssetIds}); }
}

const code = (expected: string) => (error: unknown) => error instanceof WatchlistRepositoryError && error.code === expected;
const hash = (value: WatchlistWrite) => createHash('sha256').update(`{"baseRevision":${value.baseRevision},"assetIds":${JSON.stringify(value.assetIds)}}`).digest('hex');

describe('watchlist validation and durable repository boundary', () => {
  it('validates IDs, limits, uniqueness and revisions before acquiring a connection', async () => {
    assert.equal(parseWatchlistUserId(mutationId), mutationId.toLowerCase());
    const connection = new Connection();
    const repository = connection.repository();
    await assert.rejects(repository.get(`${userId}\n`), code('WATCHLIST_INVALID_INPUT'));
    for (const baseRevision of [-1, 0.1, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1, '0']) {
      await assert.rejects(repository.put(userId, {...command, baseRevision} as WatchlistWrite), code('WATCHLIST_INVALID_INPUT'));
    }
    for (const assetIds of [null, {}, ['forma', 'forma'], ['unknown'], ['FORMA'], ['forma\r'], ['forma\n'], new Array(2), Array(51).fill('forma')]) {
      await assert.rejects(repository.put(userId, {...command, assetIds} as WatchlistWrite), code('WATCHLIST_INVALID_INPUT'));
    }
    for (const invalid of [null, [], {...command, mutationId: 'x'}, {...command, owner: userId}, {...command, [Symbol('hidden')]: 'secret'}]) {
      await assert.rejects(repository.put(userId, invalid as WatchlistWrite), code('WATCHLIST_INVALID_INPUT'));
    }
    assert.equal(connection.connections, 0);
    const fifty = Array.from({length: 50}, (_, i) => `asset-${i}`);
    assert.deepEqual(parseWatchlistAssetIds(fifty, new Set(fifty)), fifty);
  });

  it('rejects accessors and sparse/augmented arrays without executing caller getters', () => {
    let called = false;
    const input = {...command};
    Object.defineProperty(input, 'assetIds', {get() { called = true; return []; }, enumerable: true});
    assert.throws(() => parseWatchlistWrite(input, allowedAssetIds), code('WATCHLIST_INVALID_INPUT'));
    const items = ['forma'];
    Object.defineProperty(items, '0', {get() { called = true; return 'forma'; }, enumerable: true});
    assert.throws(() => parseWatchlistWrite({...command, assetIds: items}, allowedAssetIds), code('WATCHLIST_INVALID_INPUT'));
    assert.throws(() => parseWatchlistWrite({...command, assetIds: Object.assign(['forma'], {extra: true})}, allowedAssetIds), code('WATCHLIST_INVALID_INPUT'));
    assert.equal(called, false);
  });

  it('clones commands and catalog configuration before awaiting a connection', async () => {
    const connection = new Connection();
    const catalog = new Set(allowedAssetIds);
    const input = {...command, assetIds: ['forma']};
    connection.beforeConnect = async () => { input.assetIds.push('grove'); input.baseRevision = 50; catalog.clear(); };
    const result = await new PostgresWatchlistRepository(connection.pool, {allowedAssetIds: catalog}).put(userId, input);
    assert.deepEqual(result.assetIds, ['forma']);
    assert.equal(result.revision, 1);
    assert.ok(Object.isFrozen(result));
    assert.ok(Object.isFrozen(result.assetIds));
    assert.throws(() => (result.assetIds as string[]).push('grove'));
  });

  it('distinguishes no saved list from an explicit empty saved list', async () => {
    const connection = new Connection();
    const repository = connection.repository();
    const initial = await repository.get(userId);
    assert.deepEqual(initial, {revision: 0, assetIds: [], updatedAt: null});
    assert.equal(connection.queries[0]!.sql, 'BEGIN READ ONLY');
    const context = connection.queries.find(query => query.sql.startsWith('SELECT set_config'))!;
    assert.match(context.sql, /, true\)/);
    assert.deepEqual(context.parameters, [userId]);
    const saved = await repository.put(userId, {...command, assetIds: []});
    assert.deepEqual(saved, {revision: 1, assetIds: [], updatedAt: timestamp});
    assert.equal(connection.queries.at(-1)!.sql, 'COMMIT');
    assert.deepEqual(connection.releases, [undefined, undefined]);
  });

  it('returns an original retry receipt before reading a newer watchlist', async () => {
    const connection = new Connection();
    connection.receipt = {request_hash: hash(command), revision: '1', asset_ids: command.assetIds, updated_at: timestamp};
    connection.state = {revision: '8', asset_ids: [], updated_at: timestamp};
    const result = await connection.repository().put(userId, command);
    assert.equal(result.revision, 1);
    assert.deepEqual(result.assetIds, ['forma', 'orbital']);
    assert.equal(connection.queries.some(query => query.sql.startsWith('SELECT revision')), false);
    assert.equal(connection.queries.some(query => query.sql.startsWith('INSERT')), false);
    const receipt = connection.queries.find(query => query.sql.startsWith('SELECT request_hash'))!;
    assert.deepEqual(receipt.parameters, [userId, mutationId.toLowerCase()]);
  });

  it('rejects mutation reuse with changed order, contents or base revision', async () => {
    for (const changed of [{...command, assetIds: ['orbital', 'forma']}, {...command, assetIds: []}, {...command, baseRevision: 1}]) {
      const connection = new Connection();
      connection.receipt = {request_hash: hash(command), revision: '1', asset_ids: command.assetIds, updated_at: timestamp};
      await assert.rejects(connection.repository().put(userId, changed), code('WATCHLIST_IDEMPOTENCY_CONFLICT'));
      assert.equal(connection.queries.at(-1)!.sql, 'ROLLBACK');
    }
  });

  it('reports the authenticated current snapshot on revision mismatch and lost CAS', async () => {
    const connection = new Connection();
    connection.state = {revision: '2', asset_ids: ['grove'], updated_at: timestamp};
    await assert.rejects(connection.repository().put(userId, command), error => {
      assert.ok(error instanceof WatchlistRepositoryError);
      assert.equal(error.code, 'WATCHLIST_REVISION_CONFLICT');
      assert.deepEqual(error.currentSnapshot, {revision: 2, assetIds: ['grove'], updatedAt: timestamp});
      return true;
    });
    connection.loseCompareAndSwap = true;
    await assert.rejects(connection.repository().put(userId, {...command, baseRevision: 2}), code('WATCHLIST_REVISION_CONFLICT'));
    assert.equal(connection.queries.some(query => query.sql.startsWith('INSERT INTO trimmy.watchlist_mutation_receipts')), false);
  });

  it('never increments beyond the JavaScript safe revision limit', async () => {
    const connection = new Connection();
    connection.state = {revision: String(Number.MAX_SAFE_INTEGER), asset_ids: [], updated_at: timestamp};
    await assert.rejects(connection.repository().put(userId, {...command, baseRevision: Number.MAX_SAFE_INTEGER}), code('WATCHLIST_REVISION_EXHAUSTED'));
  });

  it('rejects malformed storage and valid-looking receipts unrelated to their request', async () => {
    for (const state of [
      {revision: '01', asset_ids: [], updated_at: timestamp},
      {revision: '1\n', asset_ids: [], updated_at: timestamp},
      {revision: String(Number.MAX_SAFE_INTEGER + 1), asset_ids: [], updated_at: timestamp},
      {revision: '1', asset_ids: ['unknown'], updated_at: timestamp},
      {revision: '1', asset_ids: [], updated_at: '2026-02-30T12:00:00.000Z'},
      {revision: '1', asset_ids: [], updated_at: '2026-09-14T12:00:00.000000Z'},
    ]) {
      const connection = new Connection(); connection.state = state;
      await assert.rejects(connection.repository().get(userId), code('WATCHLIST_STORAGE_INVALID'));
    }
    for (const receipt of [
      {request_hash: hash(command), revision: '2', asset_ids: command.assetIds, updated_at: timestamp},
      {request_hash: hash(command), revision: '1', asset_ids: [], updated_at: timestamp},
      {request_hash: 'malformed', revision: '1', asset_ids: command.assetIds, updated_at: timestamp},
      {request_hash: `${hash(command)}\n`, revision: '1', asset_ids: command.assetIds, updated_at: timestamp},
    ]) {
      const connection = new Connection(); connection.receipt = receipt;
      await assert.rejects(connection.repository().put(userId, command), code('WATCHLIST_STORAGE_INVALID'));
    }
    assert.throws(() => parseWatchlistSnapshot({revision: 0, assetIds: ['forma'], updatedAt: null}, allowedAssetIds), code('WATCHLIST_STORAGE_INVALID'));
  });

  it('rejects owner/bypass roles and unavailable accounts before reading user data', async () => {
    for (const role of [true, false]) {
      const connection = new Connection();
      connection.unsafeRole = role; connection.accountExists = false;
      await assert.rejects(connection.repository().get(userId), code(role ? 'WATCHLIST_RUNTIME_ROLE_INVALID' : 'WATCHLIST_ACCOUNT_NOT_FOUND'));
      assert.equal(connection.queries.some(query => query.sql.startsWith('SELECT revision')), false);
      assert.equal(connection.queries.at(-1)!.sql, 'ROLLBACK');
      assert.deepEqual(connection.releases, [undefined]);
    }
  });

  it('awaits commit and pairs the immutable receipt with the exact saved list', async () => {
    const connection = new Connection();
    let finish!: () => void;
    const committing = new Promise<void>(resolve => { finish = resolve; });
    let entered!: () => void;
    const entry = new Promise<void>(resolve => { entered = resolve; });
    connection.beforeCommit = async () => { entered(); await committing; };
    let resolved = false;
    const saving = connection.repository().put(userId, command).then(value => { resolved = true; return value; });
    await entry;
    assert.equal(resolved, false);
    const receipt = connection.queries.find(query => query.sql.startsWith('INSERT INTO trimmy.watchlist_mutation_receipts'))!;
    assert.deepEqual(receipt.parameters, [userId, mutationId.toLowerCase(), hash(command), 1, JSON.stringify(command.assetIds), timestamp]);
    finish(); await saving;
    assert.equal(resolved, true);
  });

  it('rolls back failed receipts/commits and evicts clients after failed cleanup', async () => {
    for (const failure of ['receipt', 'commit', 'rollback']) {
      const connection = new Connection();
      connection.failReceipt = failure !== 'commit';
      connection.failCommit = failure === 'commit';
      connection.failRollback = failure === 'rollback';
      await assert.rejects(connection.repository().put(userId, command));
      assert.equal(connection.queries.at(-1)!.sql, 'ROLLBACK');
      assert.equal(connection.releases.length, 1);
      assert.equal(connection.releases[0] instanceof Error, failure === 'rollback');
    }
  });
});
