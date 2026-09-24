import {createHash} from 'node:crypto';
import type {Pool, PoolClient, QueryResultRow} from 'pg';
import {
  CareerRepositoryError,
  parseCareerMissionBoard,
  parseCareerDayContext,
  parseCareerDayContextWrite,
  parseCareerPromotionReceipt,
  parseCareerPromotionWrite,
  parseCareerSummary,
  parseCareerTradeReasonReceipt,
  parseCareerTradeReasonWrite,
  parseCareerUserId,
} from './career-repository.js';
import type {
  CareerRepository,
  CareerDayContext,
  CareerDayContextWrite,
  CareerMissionBoard,
  CareerPromotionReceipt,
  CareerPromotionWrite,
  CareerSummary,
  CareerTradeReasonReceipt,
  CareerTradeReasonWrite,
} from './career-repository.js';

interface SummaryRow extends QueryResultRow {
  outcome: unknown;
  revision: unknown;
  trims_total: unknown;
  trims_today: unknown;
  trims_week: unknown;
  rank_id: unknown;
  rank_label: unknown;
  paper_limit: unknown;
  rank_threshold: unknown;
  next_rank_id: unknown;
  next_rank_label: unknown;
  next_rank_threshold: unknown;
  trims_remaining: unknown;
  promotion_required: unknown;
  streak_days: unknown;
  streak_status: unknown;
  last_active_date: unknown;
  server_date: unknown;
  updated_at: unknown;
  career_started: unknown;
  first_buy_order_id: unknown;
  first_buy_asset_id: unknown;
  first_buy_variant_mint: unknown;
  first_buy_symbol: unknown;
  first_buy_quantity_micros: unknown;
  first_buy_confirmed_at: unknown;
}

interface MissionRow extends QueryResultRow {
  outcome: unknown;
  career_revision: unknown;
  current_rank: unknown;
  mission_id: unknown;
  chapter_rank: unknown;
  mission_order: unknown;
  mission_kind: unknown;
  title: unknown;
  instruction: unknown;
  trims_reward: unknown;
  promotes_to_rank: unknown;
  mission_status: unknown;
  completed_at: unknown;
}

interface ReasonRow extends QueryResultRow {
  outcome: unknown;
  order_id: unknown;
  asset_id: unknown;
  variant_mint: unknown;
  note: unknown;
  trims_awarded: unknown;
  daily_award_number: unknown;
  saved_at: unknown;
}

interface PromotionRow extends QueryResultRow {
  outcome: unknown;
  mutation_id: unknown;
  from_rank: unknown;
  to_rank: unknown;
  career_revision: unknown;
  trims_awarded: unknown;
  promoted_at: unknown;
}

interface DayContextRow extends QueryResultRow {
  outcome: unknown;
  revision: unknown;
  time_zone: unknown;
  configured: unknown;
  server_date: unknown;
  next_day_at: unknown;
  created_at: unknown;
  updated_at: unknown;
}

function storageInvalid(): never {
  throw new CareerRepositoryError('CAREER_STORAGE_INVALID', 'Career storage failed.');
}

function safeInteger(value: unknown, minimum = 0): number {
  const parsed = typeof value === 'string' && /^(0|[1-9][0-9]*)$/.test(value)
    ? Number(value) : value;
  if (typeof parsed !== 'number' || !Number.isSafeInteger(parsed) || parsed < minimum) storageInvalid();
  return parsed;
}

function nullableInteger(value: unknown, minimum = 0): number | null {
  return value === null ? null : safeInteger(value, minimum);
}

function time(value: unknown): string {
  if (!(value instanceof Date) || !Number.isFinite(value.getTime())) storageInvalid();
  return value.toISOString();
}

function nullableTime(value: unknown): string | null { return value === null ? null : time(value); }

function date(value: unknown): string {
  const candidate = value instanceof Date ? value.toISOString().slice(0, 10) : value;
  if (typeof candidate !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(candidate)) storageInvalid();
  const parsed = new Date(`${candidate}T00:00:00.000Z`);
  if (!Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== candidate) storageInvalid();
  return candidate;
}

function nullableDate(value: unknown): string | null { return value === null ? null : date(value); }

function summary(row: SummaryRow): CareerSummary {
  if (typeof row.promotion_required !== 'boolean') storageInvalid();
  if (typeof row.career_started !== 'boolean') storageInvalid();
  const nextRank = row.next_rank_id === null && row.next_rank_label === null &&
      row.next_rank_threshold === null && row.trims_remaining === null
    ? null
    : {
        id: row.next_rank_id,
        label: row.next_rank_label,
        threshold: safeInteger(row.next_rank_threshold),
        trimsRemaining: safeInteger(row.trims_remaining),
        promotionRequired: row.promotion_required,
      };
  if (nextRank === null && row.promotion_required) storageInvalid();
  return parseCareerSummary({
    revision: safeInteger(row.revision),
    trims: {
      total: safeInteger(row.trims_total),
      today: safeInteger(row.trims_today),
      thisWeek: safeInteger(row.trims_week),
    },
    rank: {
      id: row.rank_id,
      label: row.rank_label,
      paperLimit: row.paper_limit,
      threshold: safeInteger(row.rank_threshold),
    },
    nextRank,
    streak: {
      days: safeInteger(row.streak_days),
      status: row.streak_status,
      lastActiveDate: nullableDate(row.last_active_date),
    },
    careerStarted: row.career_started,
    firstConfirmedBuy: row.first_buy_order_id === null && row.first_buy_asset_id === null &&
        row.first_buy_variant_mint === null && row.first_buy_symbol === null &&
        row.first_buy_quantity_micros === null && row.first_buy_confirmed_at === null
      ? null
      : {
          orderId: row.first_buy_order_id,
          assetId: row.first_buy_asset_id,
          variantMint: row.first_buy_variant_mint,
          symbol: row.first_buy_symbol,
          quantityMicros: row.first_buy_quantity_micros,
          confirmedAt: time(row.first_buy_confirmed_at),
        },
    serverDate: date(row.server_date),
    updatedAt: nullableTime(row.updated_at),
  });
}

function missionBoard(rows: readonly MissionRow[]): CareerMissionBoard {
  if (rows.length === 0) storageInvalid();
  const revision = safeInteger(rows[0]?.career_revision);
  const currentRank = rows[0]?.current_rank;
  if (rows.some(row => safeInteger(row.career_revision) !== revision || row.current_rank !== currentRank)) {
    storageInvalid();
  }
  return parseCareerMissionBoard({
    revision,
    currentRank,
    missions: rows.map(row => ({
      id: row.mission_id,
      chapterRank: row.chapter_rank,
      order: safeInteger(row.mission_order, 1),
      kind: row.mission_kind,
      title: row.title,
      instruction: row.instruction,
      trimsReward: safeInteger(row.trims_reward),
      promotesToRank: row.promotes_to_rank,
      status: row.mission_status,
      completedAt: nullableTime(row.completed_at),
    })),
  });
}

function reason(row: ReasonRow): CareerTradeReasonReceipt {
  return parseCareerTradeReasonReceipt({
    orderId: row.order_id,
    assetId: row.asset_id,
    variantMint: row.variant_mint,
    note: row.note,
    trimsAwarded: safeInteger(row.trims_awarded),
    dailyAwardNumber: nullableInteger(row.daily_award_number, 1),
    savedAt: time(row.saved_at),
  });
}

function promotion(row: PromotionRow): CareerPromotionReceipt {
  return parseCareerPromotionReceipt({
    mutationId: row.mutation_id,
    fromRank: row.from_rank,
    toRank: row.to_rank,
    careerRevision: safeInteger(row.career_revision, 1),
    trimsAwarded: safeInteger(row.trims_awarded),
    promotedAt: time(row.promoted_at),
  });
}

function dayContext(row: DayContextRow): CareerDayContext {
  if (typeof row.configured !== 'boolean') storageInvalid();
  return parseCareerDayContext({
    revision: safeInteger(row.revision, 1),
    timeZone: row.time_zone,
    configured: row.configured,
    serverDate: date(row.server_date),
    nextDayAt: time(row.next_day_at),
    createdAt: time(row.created_at),
    updatedAt: time(row.updated_at),
  });
}

const summaryColumns = `outcome, revision::text AS revision, trims_total::text AS trims_total,
  trims_today::text AS trims_today, trims_week::text AS trims_week, rank_id, rank_label, paper_limit,
  rank_threshold, next_rank_id, next_rank_label, next_rank_threshold,
  trims_remaining::text AS trims_remaining, promotion_required, streak_days, streak_status,
  last_active_date::text AS last_active_date, server_date::text AS server_date, updated_at,
  career_started, first_buy_order_id::text AS first_buy_order_id, first_buy_asset_id,
  first_buy_variant_mint, first_buy_symbol, first_buy_quantity_micros,
  first_buy_confirmed_at`;

const missionColumns = `outcome, career_revision::text AS career_revision, current_rank,
  mission_id, chapter_rank, mission_order, mission_kind, title, instruction, trims_reward,
  promotes_to_rank, mission_status, completed_at`;

const reasonColumns = `outcome, order_id::text AS order_id, asset_id, variant_mint, note,
  trims_awarded, daily_award_number, saved_at`;

const promotionColumns = `outcome, mutation_id::text AS mutation_id, from_rank, to_rank,
  career_revision::text AS career_revision, trims_awarded, promoted_at`;

const dayContextColumns = `outcome, revision::text AS revision, time_zone, configured,
  server_date::text AS server_date, next_day_at, created_at, updated_at`;

export class PostgresCareerRepository implements CareerRepository {
  constructor(private readonly pool: Pick<Pool, 'connect'>) {}

  async getActivityWeek(inputUserId: string) {
    const userId = parseCareerUserId(inputUserId);
    const client = await this.pool.connect();
    let releaseError: Error | undefined;
    try {
      await client.query('BEGIN READ ONLY');
      await this.assertRuntimeRole(client);
      const result = await client.query('SELECT * FROM trimmy.career_activity_week_get($1::uuid)', [userId]);
      const row = result.rows[0];
      if (result.rows.length !== 1 || row?.outcome !== 'found') {
        if (row?.outcome === 'account_missing') throw new CareerRepositoryError('CAREER_ACCOUNT_NOT_FOUND', 'Career account was not found.');
        storageInvalid();
      }
      const serverDate = date(row.server_date); const weekStart = date(row.week_start);
      if (!Array.isArray(row.active_dates) || row.active_dates.length > 7) storageInvalid();
      const activeDates: string[] = row.active_dates.map(date);
      if (new Set(activeDates).size !== activeDates.length || activeDates.some(day => day < weekStart || day > serverDate)) storageInvalid();
      await client.query('COMMIT');
      return {serverDate, weekStart, activeDates};
    } catch (error) {
      try {await client.query('ROLLBACK');} catch {releaseError = new Error('Career transaction cleanup failed.');}
      if (error instanceof CareerRepositoryError) throw error;
      throw new CareerRepositoryError('CAREER_STORAGE_INVALID', 'Activity could not be loaded.');
    } finally {client.release(releaseError);}
  }

  async getSummary(inputUserId: string): Promise<CareerSummary> {
    const userId = parseCareerUserId(inputUserId);
    return this.readSummary(userId);
  }

  async saveTradeReason(
    inputUserId: string,
    input: CareerTradeReasonWrite,
  ): Promise<CareerTradeReasonReceipt> {
    const userId = parseCareerUserId(inputUserId);
    const command = parseCareerTradeReasonWrite(input);
    const requestHash = createHash('sha256').update(JSON.stringify({
      orderId: command.orderId,
      note: command.note,
    })).digest('hex');
    return this.writeReason(userId, command, requestHash);
  }

  async getDayContext(inputUserId: string): Promise<CareerDayContext> {
    const userId = parseCareerUserId(inputUserId);
    return this.readDayContext(userId);
  }

  async saveDayContext(
    inputUserId: string,
    input: CareerDayContextWrite,
  ): Promise<CareerDayContext> {
    const userId = parseCareerUserId(inputUserId);
    const command = parseCareerDayContextWrite(input);
    const requestHash = createHash('sha256').update(JSON.stringify({
      baseRevision: command.baseRevision,
      timeZone: command.timeZone,
    })).digest('hex');
    return this.writeDayContext(userId, command, requestHash);
  }

  async getMissions(inputUserId: string): Promise<CareerMissionBoard> {
    const userId = parseCareerUserId(inputUserId);
    return this.readMissions(userId);
  }

  async promote(
    inputUserId: string,
    input: CareerPromotionWrite,
  ): Promise<CareerPromotionReceipt> {
    const userId = parseCareerUserId(inputUserId);
    const command = parseCareerPromotionWrite(input);
    const requestHash = createHash('sha256').update(JSON.stringify({
      targetRank: command.targetRank,
    })).digest('hex');
    return this.writePromotion(userId, command, requestHash);
  }

  private async assertRuntimeRole(client: PoolClient) {
    const role = await client.query<{unsafe_role: boolean}>(`
      SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_roles
        WHERE (rolsuper OR rolbypassrls) AND pg_catalog.pg_has_role(current_user, oid, 'MEMBER'))
        OR EXISTS (SELECT 1 FROM pg_catalog.pg_class c
          JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'trimmy'
            AND c.relname IN ('users', 'product_profiles', 'paper_orders', 'paper_positions',
              'career_profiles', 'career_trim_ledger', 'career_trade_reasons',
              'career_reason_mutation_receipts', 'career_starts',
              'career_first_confirmed_buys', 'career_mission_definitions',
              'career_mission_completions', 'career_promotion_receipts',
              'career_day_settings', 'career_day_setting_receipts', 'career_activity_events')
            AND pg_catalog.pg_has_role(current_user, c.relowner, 'MEMBER')) AS unsafe_role`);
    if (role.rows.length !== 1 || role.rows[0]?.unsafe_role !== false) {
      throw new CareerRepositoryError(
        'CAREER_RUNTIME_ROLE_INVALID',
        'Career storage requires a dedicated runtime role.',
      );
    }
  }

  private async readMissions(userId: string): Promise<CareerMissionBoard> {
    const client = await this.pool.connect();
    let releaseError: Error | undefined;
    try {
      await client.query('BEGIN READ ONLY');
      await this.assertRuntimeRole(client);
      const result = await client.query<MissionRow>(
        `SELECT ${missionColumns} FROM trimmy.career_missions_get($1::uuid)`,
        [userId],
      );
      if (result.rows.length === 1 && result.rows[0]?.outcome === 'account_missing') {
        throw new CareerRepositoryError('CAREER_ACCOUNT_NOT_FOUND', 'Career account was not found.');
      }
      if (result.rows.some(row => row.outcome !== 'found')) storageInvalid();
      const value = missionBoard(result.rows);
      await client.query('COMMIT');
      return value;
    } catch (error) {
      try { await client.query('ROLLBACK'); } catch { releaseError = new Error('Career transaction cleanup failed.'); }
      if (error instanceof CareerRepositoryError) throw error;
      throw new CareerRepositoryError('CAREER_STORAGE_INVALID', 'Career storage failed.');
    } finally {
      client.release(releaseError);
    }
  }

  private async readSummary(userId: string): Promise<CareerSummary> {
    const client = await this.pool.connect();
    let releaseError: Error | undefined;
    try {
      await client.query('BEGIN READ ONLY');
      await this.assertRuntimeRole(client);
      const result = await client.query<SummaryRow>(
        `SELECT ${summaryColumns} FROM trimmy.career_summary_get($1::uuid)`,
        [userId],
      );
      if (result.rows.length !== 1 || result.rows[0]?.outcome !== 'found') {
        if (result.rows[0]?.outcome === 'account_missing') {
          throw new CareerRepositoryError('CAREER_ACCOUNT_NOT_FOUND', 'Career account was not found.');
        }
        storageInvalid();
      }
      const value = summary(result.rows[0]);
      await client.query('COMMIT');
      return value;
    } catch (error) {
      try { await client.query('ROLLBACK'); } catch { releaseError = new Error('Career transaction cleanup failed.'); }
      if (error instanceof CareerRepositoryError) throw error;
      throw new CareerRepositoryError('CAREER_STORAGE_INVALID', 'Career storage failed.');
    } finally {
      client.release(releaseError);
    }
  }

  private async readDayContext(userId: string): Promise<CareerDayContext> {
    const client = await this.pool.connect();
    let releaseError: Error | undefined;
    try {
      await client.query('BEGIN READ ONLY');
      await this.assertRuntimeRole(client);
      const result = await client.query<DayContextRow>(
        `SELECT ${dayContextColumns} FROM trimmy.career_day_context_get($1::uuid)`,
        [userId],
      );
      if (result.rows.length !== 1 || result.rows[0]?.outcome !== 'found') {
        if (result.rows[0]?.outcome === 'account_missing') {
          throw new CareerRepositoryError('CAREER_ACCOUNT_NOT_FOUND', 'Career account was not found.');
        }
        storageInvalid();
      }
      const value = dayContext(result.rows[0]);
      await client.query('COMMIT');
      return value;
    } catch (error) {
      try { await client.query('ROLLBACK'); } catch { releaseError = new Error('Career transaction cleanup failed.'); }
      if (error instanceof CareerRepositoryError) throw error;
      throw new CareerRepositoryError('CAREER_STORAGE_INVALID', 'Career storage failed.');
    } finally {
      client.release(releaseError);
    }
  }

  private async writeDayContext(
    userId: string,
    command: CareerDayContextWrite,
    requestHash: string,
  ): Promise<CareerDayContext> {
    const client = await this.pool.connect();
    let releaseError: Error | undefined;
    try {
      await client.query('BEGIN');
      await this.assertRuntimeRole(client);
      const result = await client.query<DayContextRow>(
        `SELECT ${dayContextColumns} FROM trimmy.career_day_context_put(
          $1::uuid,$2::uuid,$3::text,$4::bigint,$5::text)`,
        [userId, command.mutationId, requestHash, command.baseRevision, command.timeZone],
      );
      if (result.rows.length !== 1 || typeof result.rows[0]?.outcome !== 'string') storageInvalid();
      const row = result.rows[0];
      if (row.outcome === 'saved') {
        const value = dayContext(row);
        await client.query('COMMIT');
        return value;
      }
      const code = row.outcome === 'account_missing' ? 'CAREER_ACCOUNT_NOT_FOUND'
        : row.outcome === 'revision_conflict' ? 'CAREER_DAY_CONTEXT_REVISION_CONFLICT'
        : row.outcome === 'idempotency_conflict' ? 'CAREER_IDEMPOTENCY_CONFLICT'
        : row.outcome === 'change_too_soon' ? 'CAREER_TIME_ZONE_CHANGE_TOO_SOON'
        : row.outcome === 'revision_exhausted' ? 'CAREER_REVISION_EXHAUSTED'
        : row.outcome === 'invalid' ? 'CAREER_INVALID_INPUT'
        : 'CAREER_STORAGE_INVALID';
      throw new CareerRepositoryError(code, 'Career day context request was not accepted.');
    } catch (error) {
      try { await client.query('ROLLBACK'); } catch { releaseError = new Error('Career transaction cleanup failed.'); }
      if (error instanceof CareerRepositoryError) throw error;
      throw new CareerRepositoryError('CAREER_STORAGE_INVALID', 'Career storage failed.');
    } finally {
      client.release(releaseError);
    }
  }

  private async writeReason(
    userId: string,
    command: CareerTradeReasonWrite,
    requestHash: string,
  ): Promise<CareerTradeReasonReceipt> {
    const client = await this.pool.connect();
    let releaseError: Error | undefined;
    try {
      await client.query('BEGIN');
      await this.assertRuntimeRole(client);
      const result = await client.query<ReasonRow>(
        `SELECT ${reasonColumns} FROM trimmy.career_trade_reason_put(
          $1::uuid,$2::uuid,$3::text,$4::uuid,$5::text)`,
        [userId, command.mutationId, requestHash, command.orderId, command.note],
      );
      if (result.rows.length !== 1 || typeof result.rows[0]?.outcome !== 'string') storageInvalid();
      const row = result.rows[0];
      if (row.outcome === 'saved') {
        const value = reason(row);
        await client.query('COMMIT');
        return value;
      }
      const code = row.outcome === 'account_missing' ? 'CAREER_ACCOUNT_NOT_FOUND'
        : row.outcome === 'profile_required' ? 'CAREER_PROFILE_REQUIRED'
        : row.outcome === 'order_missing' ? 'CAREER_ORDER_NOT_FOUND'
        : row.outcome === 'buy_required' ? 'CAREER_BUY_ORDER_REQUIRED'
        : row.outcome === 'position_required' ? 'CAREER_POSITION_REQUIRED'
        : row.outcome === 'reason_exists' ? 'CAREER_REASON_EXISTS'
        : row.outcome === 'idempotency_conflict' ? 'CAREER_IDEMPOTENCY_CONFLICT'
        : row.outcome === 'revision_exhausted' ? 'CAREER_REVISION_EXHAUSTED'
        : row.outcome === 'invalid' ? 'CAREER_INVALID_INPUT'
        : 'CAREER_STORAGE_INVALID';
      throw new CareerRepositoryError(code, 'Career reason request was not accepted.');
    } catch (error) {
      try { await client.query('ROLLBACK'); } catch { releaseError = new Error('Career transaction cleanup failed.'); }
      if (error instanceof CareerRepositoryError) throw error;
      throw new CareerRepositoryError('CAREER_STORAGE_INVALID', 'Career storage failed.');
    } finally {
      client.release(releaseError);
    }
  }

  private async writePromotion(
    userId: string,
    command: CareerPromotionWrite,
    requestHash: string,
  ): Promise<CareerPromotionReceipt> {
    const client = await this.pool.connect();
    let releaseError: Error | undefined;
    try {
      await client.query('BEGIN');
      await this.assertRuntimeRole(client);
      const result = await client.query<PromotionRow>(
        `SELECT ${promotionColumns} FROM trimmy.career_promote(
          $1::uuid,$2::uuid,$3::text,$4::text)`,
        [userId, command.mutationId, requestHash, command.targetRank],
      );
      if (result.rows.length !== 1 || typeof result.rows[0]?.outcome !== 'string') storageInvalid();
      const row = result.rows[0];
      if (row.outcome === 'promoted') {
        const value = promotion(row);
        await client.query('COMMIT');
        return value;
      }
      const code = row.outcome === 'account_missing' ? 'CAREER_ACCOUNT_NOT_FOUND'
        : row.outcome === 'profile_required' ? 'CAREER_PROFILE_REQUIRED'
        : row.outcome === 'idempotency_conflict' ? 'CAREER_IDEMPOTENCY_CONFLICT'
        : row.outcome === 'rank_mismatch' ? 'CAREER_PROMOTION_RANK_MISMATCH'
        : row.outcome === 'threshold_required' ? 'CAREER_PROMOTION_THRESHOLD_REQUIRED'
        : row.outcome === 'mission_required' ? 'CAREER_PROMOTION_MISSION_REQUIRED'
        : row.outcome === 'revision_exhausted' ? 'CAREER_REVISION_EXHAUSTED'
        : row.outcome === 'invalid' ? 'CAREER_INVALID_INPUT'
        : 'CAREER_STORAGE_INVALID';
      throw new CareerRepositoryError(code, 'Career promotion request was not accepted.');
    } catch (error) {
      try { await client.query('ROLLBACK'); } catch { releaseError = new Error('Career transaction cleanup failed.'); }
      if (error instanceof CareerRepositoryError) throw error;
      throw new CareerRepositoryError('CAREER_STORAGE_INVALID', 'Career storage failed.');
    } finally {
      client.release(releaseError);
    }
  }
}
