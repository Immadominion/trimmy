import assert from 'node:assert/strict';
import {describe, test} from 'node:test';
import type {Pool, PoolClient} from 'pg';
import {CareerRepositoryError} from '../src/career-repository.js';
import {PostgresCareerRepository} from '../src/postgres-career-repository.js';

const userId = '73000000-0000-4000-8000-000000000001';
const mutationId = '73000000-0000-4000-8000-000000000002';
const orderId = '73000000-0000-4000-8000-000000000003';
const instant = '2026-09-20T12:00:00.000Z';

type Query = {sql: string; values?: readonly unknown[]};

function harness(result: (sql: string, values?: readonly unknown[]) => {rows: unknown[]}) {
  const queries: Query[] = [];
  const releases: Array<Error | undefined> = [];
  const client = {
    query: async (raw: string, values?: readonly unknown[]) => {
      const sql = raw.replace(/\s+/gu, ' ').trim();
      queries.push(values === undefined ? {sql} : {sql, values});
      if (sql.includes('AS unsafe_role')) return {rows: [{unsafe_role: false}]};
      return result(sql, values);
    },
    release: (error?: Error) => { releases.push(error); },
  } as unknown as PoolClient;
  const pool = {connect: async () => client} satisfies Pick<Pool, 'connect'>;
  return {repository: new PostgresCareerRepository(pool), queries, releases};
}

describe('Postgres career repository', () => {
  test('reads actual activity dates without filling grace days', async () => {
    const h = harness(sql => sql.includes('career_activity_week_get') ? {rows: [{
      outcome: 'found', server_date: '2026-09-24', week_start: '2026-09-21',
      active_dates: ['2026-09-21', '2026-09-24'],
    }]} : {rows: []});
    assert.deepEqual(await h.repository.getActivityWeek(userId), {
      serverDate: '2026-09-24', weekStart: '2026-09-21', activeDates: ['2026-09-21', '2026-09-24'],
    });
    assert.equal(h.queries[0]?.sql, 'BEGIN READ ONLY');
    assert.equal(h.queries.at(-1)?.sql, 'COMMIT');
  });

  test('reads a strict empty summary in one read-only transaction', async () => {
    const h = harness(sql => sql.includes('career_summary_get') ? {rows: [{
      outcome: 'found', revision: '0', trims_total: '0', trims_today: '0', trims_week: '0',
      rank_id: 'rookie', rank_label: 'Rookie', paper_limit: '10000', rank_threshold: 0,
      next_rank_id: 'analyst', next_rank_label: 'Analyst', next_rank_threshold: 300,
      trims_remaining: '300', promotion_required: false, streak_days: 0,
      streak_status: 'not-started', last_active_date: null, server_date: '2026-09-20', updated_at: null,
      career_started: false, first_buy_order_id: null, first_buy_asset_id: null,
      first_buy_variant_mint: null, first_buy_symbol: null, first_buy_quantity_micros: null,
      first_buy_confirmed_at: null,
    }]} : {rows: []});

    const summary = await h.repository.getSummary(userId);

    assert.equal(h.queries[0]?.sql, 'BEGIN READ ONLY');
    assert.equal(h.queries.at(-1)?.sql, 'COMMIT');
    assert.deepEqual(h.releases, [undefined]);
    assert.equal(summary.revision, 0);
    assert.equal(summary.nextRank?.trimsRemaining, 300);
    assert.equal(summary.streak.status, 'not-started');
  });

  test('reads the strict server-authored mission path', async () => {
    const h = harness(sql => sql.includes('career_missions_get') ? {rows: [
      {outcome: 'found', career_revision: '2', current_rank: 'rookie',
        mission_id: 'first-paper-buy', chapter_rank: 'rookie', mission_order: 1,
        mission_kind: 'action', title: 'Buy your first stock', instruction: 'Complete one paper buy.',
        trims_reward: 20, promotes_to_rank: null, mission_status: 'complete',
        completed_at: new Date('2026-09-20T09:00:00.000Z')},
      {outcome: 'found', career_revision: '2', current_rank: 'rookie',
        mission_id: 'write-a-reason', chapter_rank: 'rookie', mission_order: 2,
        mission_kind: 'action', title: 'Write your reason',
        instruction: 'Add a reason to a paper buy you still hold.', trims_reward: 20,
        promotes_to_rank: null, mission_status: 'ready', completed_at: null},
      {outcome: 'found', career_revision: '2', current_rank: 'rookie',
        mission_id: 'hold-through-red-day', chapter_rank: 'rookie', mission_order: 3,
        mission_kind: 'promotion', title: 'Hold through a red day',
        instruction: 'Hold a stock through a verified red Wall Street day.', trims_reward: 20,
        promotes_to_rank: 'analyst', mission_status: 'locked', completed_at: null},
    ]} : {rows: []});

    const board = await h.repository.getMissions(userId);

    assert.equal(board.revision, 2);
    assert.deepEqual(board.missions.map(mission => mission.status), ['complete', 'ready', 'locked']);
    assert.equal(h.queries[0]?.sql, 'BEGIN READ ONLY');
    assert.equal(h.queries.at(-1)?.sql, 'COMMIT');
  });

  test('hashes the canonical reason command and commits its exact receipt', async () => {
    const h = harness(sql => sql.includes('career_trade_reason_put') ? {rows: [{
      outcome: 'saved', order_id: orderId, asset_id: 'apple',
      variant_mint: '11111111111111111111111111111111', note: 'Margins are improving.',
      trims_awarded: 10, daily_award_number: 1, saved_at: new Date(instant),
    }]} : {rows: []});

    const receipt = await h.repository.saveTradeReason(userId, {
      mutationId, orderId, note: 'Margins are improving.',
    });

    const call = h.queries.find(query => query.sql.includes('career_trade_reason_put'));
    assert.deepEqual(call?.values?.slice(0, 2), [userId, mutationId]);
    assert.match(String(call?.values?.[2]), /^[a-f0-9]{64}$/u);
    assert.deepEqual(call?.values?.slice(3), [orderId, 'Margins are improving.']);
    assert.equal(receipt.trimsAwarded, 10);
    assert.equal(h.queries.at(-1)?.sql, 'COMMIT');
    assert.deepEqual(h.releases, [undefined]);
  });

  test('reads and writes the strict server-owned day context', async () => {
    const row = {outcome: 'found', revision: '1', time_zone: 'UTC', configured: false,
      server_date: '2026-09-20', next_day_at: new Date('2026-09-21T00:00:00.000Z'),
      created_at: new Date(instant), updated_at: new Date(instant)};
    const h = harness(sql => sql.includes('career_day_context_get') ? {rows: [row]}
      : sql.includes('career_day_context_put') ? {rows: [{...row, outcome: 'saved', revision: '2',
          time_zone: 'Africa/Lagos', configured: true,
          next_day_at: new Date('2026-09-20T23:00:00.000Z'),
          updated_at: new Date('2026-09-20T12:01:00.000Z')}]}
        : {rows: []});
    const initial = await h.repository.getDayContext(userId);
    assert.deepEqual(initial, {
      revision: 1, timeZone: 'UTC', configured: false, serverDate: '2026-09-20',
      nextDayAt: '2026-09-21T00:00:00.000Z',
      createdAt: instant, updatedAt: instant,
    });
    const saved = await h.repository.saveDayContext(userId, {
      mutationId, baseRevision: 1, timeZone: 'Africa/Lagos',
    });
    assert.equal(saved.timeZone, 'Africa/Lagos');
    assert.equal(saved.revision, 2);
    const call = h.queries.find(query => query.sql.includes('career_day_context_put'));
    assert.deepEqual(call?.values?.slice(0, 2), [userId, mutationId]);
    assert.match(String(call?.values?.[2]), /^[a-f0-9]{64}$/u);
    assert.deepEqual(call?.values?.slice(3), [1, 'Africa/Lagos']);
  });

  test('rolls back a stale day-context revision with a bounded code', async () => {
    const h = harness(sql => sql.includes('career_day_context_put')
      ? {rows: [{outcome: 'revision_conflict'}]} : {rows: []});
    await assert.rejects(h.repository.saveDayContext(userId, {
      mutationId, baseRevision: 1, timeZone: 'Africa/Lagos',
    }), (error: unknown) => error instanceof CareerRepositoryError &&
      error.code === 'CAREER_DAY_CONTEXT_REVISION_CONFLICT');
    assert.equal(h.queries.at(-1)?.sql, 'ROLLBACK');
  });

  test('rolls back and maps a reason conflict without exposing storage detail', async () => {
    const h = harness(sql => sql.includes('career_trade_reason_put')
      ? {rows: [{outcome: 'reason_exists'}]} : {rows: []});

    await assert.rejects(
      h.repository.saveTradeReason(userId, {mutationId, orderId, note: 'Margins are improving.'}),
      (error: unknown) => error instanceof CareerRepositoryError && error.code === 'CAREER_REASON_EXISTS',
    );

    assert.equal(h.queries.at(-1)?.sql, 'ROLLBACK');
    assert.deepEqual(h.releases, [undefined]);
  });

  test('hashes and commits an exact adjacent-rank promotion receipt', async () => {
    const h = harness(sql => sql.includes('career_promote') ? {rows: [{
      outcome: 'promoted', mutation_id: mutationId, from_rank: 'rookie', to_rank: 'analyst',
      career_revision: '18', trims_awarded: 100, promoted_at: new Date(instant),
    }]} : {rows: []});

    const receipt = await h.repository.promote(userId, {mutationId, targetRank: 'analyst'});

    const call = h.queries.find(query => query.sql.includes('career_promote'));
    assert.deepEqual(call?.values?.slice(0, 2), [userId, mutationId]);
    assert.match(String(call?.values?.[2]), /^[a-f0-9]{64}$/u);
    assert.equal(call?.values?.[3], 'analyst');
    assert.equal(receipt.trimsAwarded, 100);
    assert.equal(h.queries.at(-1)?.sql, 'COMMIT');
  });

  test('refuses an owner or RLS-bypass runtime before any career read', async () => {
    const queries: string[] = [];
    const client = {
      query: async (raw: string) => {
        const sql = raw.replace(/\s+/gu, ' ').trim();
        queries.push(sql);
        return sql.includes('AS unsafe_role') ? {rows: [{unsafe_role: true}]} : {rows: []};
      },
      release: () => {},
    } as unknown as PoolClient;
    const repository = new PostgresCareerRepository({connect: async () => client});

    await assert.rejects(repository.getSummary(userId),
      (error: unknown) => error instanceof CareerRepositoryError &&
        error.code === 'CAREER_RUNTIME_ROLE_INVALID');
    assert.equal(queries.some(sql => sql.includes('career_summary_get')), false);
    assert.equal(queries.at(-1), 'ROLLBACK');
  });
});
