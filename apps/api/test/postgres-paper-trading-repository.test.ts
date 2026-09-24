import assert from 'node:assert/strict';
import { test } from 'node:test';
import type { Pool, PoolClient } from 'pg';
import { PostgresPaperTradingRepository } from '../src/postgres-paper-trading-repository.js';
import { PaperTradingRepositoryError } from '../src/paper-trading-repository.js';

const userId = '70000000-0000-4000-8000-000000000001';
const instant = '2026-09-20T12:00:00.000Z';

test('reads every portfolio table in one repeatable-read snapshot', async () => {
  const queries: string[] = [];
  const releases: (Error | undefined)[] = [];
  const client = {
    query: async (raw: string) => {
      const sql = raw.replace(/\s+/gu, ' ').trim();
      queries.push(sql);
      if (sql.includes('AS unsafe_role')) return {rows: [{unsafe_role: false}]};
      if (sql.includes('practice_account_exists')) return {rows: [{account_exists: true}]};
      if (sql.startsWith('SELECT revision::text AS revision')) {
        return {rows: [{revision: '7', last_reset_revision: '5', cash_micros: '9500000000',
          opened_at: instant, updated_at: instant}]};
      }
      return {rows: []};
    },
    release: (error?: Error) => { releases.push(error); },
  } as unknown as PoolClient;
  const pool = {connect: async () => client} satisfies Pick<Pool, 'connect'>;

  const result = await new PostgresPaperTradingRepository(pool).getPortfolio(userId);

  assert.equal(queries[0], 'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY');
  assert.equal(queries.some(sql => sql.startsWith('SELECT asset_id, variant_mint')), true);
  assert.equal(queries.some(sql => sql.startsWith('SELECT id::text AS id')), true);
  assert.equal(queries.some(sql => sql.includes('last_order_revision > $2::bigint')), true);
  assert.equal(queries.some(sql => sql.includes('account_revision > $2::bigint')), true);
  assert.equal(queries.at(-1), 'COMMIT');
  assert.deepEqual(releases, [undefined]);
  assert.equal(result.revision, 7);
  assert.equal(result.cashPaperMicros, '9500000000');
});

const mutationId = '80000000-0000-4000-8000-000000000001';
const requestHash = 'a'.repeat(64);

function resetPool(row: Record<string, unknown>) {
  const queries: Array<{readonly sql: string; readonly values?: readonly unknown[]}> = [];
  const releases: (Error | undefined)[] = [];
  const client = {
    query: async (raw: string, values?: readonly unknown[]) => {
      const sql = raw.replace(/\s+/gu, ' ').trim();
      queries.push(values === undefined ? {sql} : {sql, values});
      if (sql.includes('AS unsafe_role')) return {rows: [{unsafe_role: false}]};
      if (sql.includes('paper_desk_reset')) return {rows: [row]};
      return {rows: []};
    },
    release: (error?: Error) => { releases.push(error); },
  } as unknown as PoolClient;
  return {pool: {connect: async () => client} satisfies Pick<Pool, 'connect'>, queries, releases};
}

test('calls the security-definer reset once and validates its exact immutable receipt', async () => {
  const fixture = resetPool({
    outcome: 'reset', mutation_id: mutationId, previous_revision: '4', revision: '5',
    cash_micros: '10000000000', reset_at: instant,
  });
  const result = await new PostgresPaperTradingRepository(fixture.pool).reset(userId,
    {mutationId, requestHash, baseRevision: 4});

  assert.deepEqual(result, {mutationId, previousRevision: 4, revision: 5,
    cashPaperMicros: '10000000000', resetAt: instant});
  assert.equal(fixture.queries[0]?.sql, 'BEGIN');
  assert.equal(fixture.queries.some(({sql}) => sql.includes('practice_account_exists')), false);
  const call = fixture.queries.find(({sql}) => sql.includes('paper_desk_reset'));
  assert.deepEqual(call?.values, [userId, mutationId, requestHash, 4]);
  assert.equal(fixture.queries.some(({sql}) =>
    sql.includes('AS unsafe_role') && sql.includes("'paper_reset_receipts'")), true);
  assert.equal(fixture.queries.at(-1)?.sql, 'COMMIT');
  assert.deepEqual(fixture.releases, [undefined]);
});

test('maps every reset terminal outcome and rejects malformed storage output', async () => {
  const cases = [
    [{outcome: 'not_needed', mutation_id: mutationId, previous_revision: '4', revision: '4',
      cash_micros: '10000000000', reset_at: null}, 'PAPER_RESET_NOT_NEEDED'],
    [{outcome: 'stale_revision', mutation_id: null, previous_revision: '5', revision: '5',
      cash_micros: '9000000000', reset_at: null}, 'PAPER_PORTFOLIO_CHANGED'],
    [{outcome: 'revision_exhausted', mutation_id: null, previous_revision: '9007199254740991',
      revision: '9007199254740991', cash_micros: '9000000000', reset_at: null}, 'PAPER_REVISION_EXHAUSTED'],
    [{outcome: 'idempotency_conflict', mutation_id: null, previous_revision: null, revision: null,
      cash_micros: null, reset_at: null}, 'PAPER_IDEMPOTENCY_CONFLICT'],
    [{outcome: 'account_missing', mutation_id: null, previous_revision: null, revision: null,
      cash_micros: null, reset_at: null}, 'PAPER_ACCOUNT_NOT_FOUND'],
    [{outcome: 'invalid', mutation_id: null, previous_revision: null, revision: null,
      cash_micros: null, reset_at: null}, 'PAPER_INPUT_INVALID'],
  ] as const;
  for (const [row, code] of cases) {
    const fixture = resetPool(row);
    await assert.rejects(
      new PostgresPaperTradingRepository(fixture.pool).reset(userId, {mutationId, requestHash, baseRevision: 4}),
      error => error instanceof PaperTradingRepositoryError && error.code === code,
    );
    assert.equal(
      fixture.queries.at(-1)?.sql,
      code === 'PAPER_RESET_NOT_NEEDED' ? 'COMMIT' : 'ROLLBACK',
    );
  }

  for (const malformed of [
    {outcome: 'reset', mutation_id: mutationId, previous_revision: '4', revision: '6',
      cash_micros: '10000000000', reset_at: instant},
    {outcome: 'reset', mutation_id: mutationId, previous_revision: '4', revision: '5',
      cash_micros: '10000000000', reset_at: instant, extra: 'not allowed'},
  ]) {
    const fixture = resetPool(malformed);
    await assert.rejects(
      new PostgresPaperTradingRepository(fixture.pool).reset(userId, {mutationId, requestHash, baseRevision: 4}),
      error => error instanceof PaperTradingRepositoryError && error.code === 'PAPER_STORAGE_INVALID',
    );
  }
});
