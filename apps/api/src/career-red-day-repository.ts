import type {Pool} from 'pg';
import type {
  CanonicalRedDaySession,
  RedDayFailureCode,
  RedDayFailureStatus,
  RedDayRequestAudit,
} from './career-red-day-market.js';
import {RED_DAY_PROVIDER, RED_DAY_VERIFIER_VERSION} from './career-red-day-market.js';

export interface RedDayCandidate {
  readonly assetId: string;
  readonly afterMarketDate: string | null;
}

export interface RedDayPendingSession {
  readonly observationId: string;
  readonly assetId: string;
  readonly marketDate: string;
}

export interface RedDayFailureObservation {
  readonly observationId: string;
  readonly provider: typeof RED_DAY_PROVIDER;
  readonly verifierVersion: typeof RED_DAY_VERIFIER_VERSION;
  readonly assetId: string;
  readonly listedSymbol: string | null;
  readonly status: RedDayFailureStatus;
  readonly reasonCode: RedDayFailureCode | 'asset-not-in-catalog';
  readonly observedAt: string;
  readonly audit: RedDayRequestAudit;
}

export interface RedDayVerifiedObservation {
  readonly observationId: string;
  readonly session: CanonicalRedDaySession;
}

export type RedDayObservation = RedDayFailureObservation | RedDayVerifiedObservation;

export interface RedDayRecordResult {
  readonly outcome: 'recorded' | 'already-recorded' | 'correction-review' | 'already-reviewed' | 'idempotency-conflict';
  readonly observationId: string;
  readonly evidenceCount: number;
  readonly completedCount: number;
}

export interface RedDayProcessResult {
  readonly outcome: 'processed' | 'complete' | 'already-complete';
  readonly observationId: string;
  readonly evidenceCount: number;
  readonly completedCount: number;
  readonly processingComplete: boolean;
}

export interface CareerRedDayRepository {
  pendingSessions(limit: number): Promise<readonly RedDayPendingSession[]>;
  candidates(limit: number): Promise<readonly RedDayCandidate[]>;
  record(observation: RedDayObservation): Promise<RedDayRecordResult>;
  processSession(observationId: string, limit: number): Promise<RedDayProcessResult>;
}

type Queryable = Pick<Pool, 'query'>;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
const assetPattern = /^[a-z0-9]+(?:-[a-z0-9]+)*$/u;
const datePattern = /^\d{4}-\d{2}-\d{2}$/u;

function rowObject(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Red-day database response is invalid.');
  return value as Record<string, unknown>;
}
function exactKeys(row: Record<string, unknown>, expected: readonly string[]): void {
  const actual = Object.keys(row).sort();
  const keys = [...expected].sort();
  if (actual.length !== keys.length || actual.some((key, index) => key !== keys[index])) {
    throw new Error('Red-day database response is invalid.');
  }
}
function integer(value: unknown): number {
  const result = typeof value === 'number' ? value : typeof value === 'string' && /^\d+$/u.test(value) ? Number(value) : NaN;
  if (!Number.isSafeInteger(result) || result < 0) throw new Error('Red-day database response is invalid.');
  return result;
}
function date(value: unknown): string | null {
  if (value === null) return null;
  if (typeof value !== 'string' || !datePattern.test(value) ||
      new Date(`${value}T00:00:00.000Z`).toISOString().slice(0, 10) !== value) {
    throw new Error('Red-day database response is invalid.');
  }
  return value;
}
function pathOrNull(value: string | null): string | null { return value; }

/** Function-only PostgreSQL adapter for the dedicated worker role. */
export class PostgresCareerRedDayRepository implements CareerRedDayRepository {
  constructor(private readonly pool: Queryable) {
    if (!pool || typeof pool.query !== 'function') throw new TypeError('A PostgreSQL query adapter is required.');
  }

  async pendingSessions(limit: number): Promise<readonly RedDayPendingSession[]> {
    if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new TypeError('Red-day pending limit is invalid.');
    const result = await this.pool.query(
      `SELECT observation_id, asset_id, market_date::text AS market_date
       FROM trimmy.career_red_day_pending_sessions($1::integer)`, [limit]);
    if (!Array.isArray(result.rows) || result.rows.length > limit) throw new Error('Red-day database response is invalid.');
    const seen = new Set<string>();
    return Object.freeze(result.rows.map(raw => {
      const row = rowObject(raw);
      exactKeys(row, ['asset_id', 'market_date', 'observation_id']);
      const observationId = row['observation_id'];
      const assetId = row['asset_id'];
      const marketDate = date(row['market_date']);
      if (typeof observationId !== 'string' || !uuidPattern.test(observationId) || seen.has(observationId) ||
          typeof assetId !== 'string' || assetId.length > 100 || !assetPattern.test(assetId) || marketDate === null) {
        throw new Error('Red-day database response is invalid.');
      }
      seen.add(observationId);
      return Object.freeze({observationId: observationId.toLowerCase(), assetId, marketDate});
    }));
  }

  async candidates(limit: number): Promise<readonly RedDayCandidate[]> {
    if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new TypeError('Red-day candidate limit is invalid.');
    const result = await this.pool.query(
      `SELECT asset_id, after_market_date::text AS after_market_date
       FROM trimmy.career_red_day_candidates($1::integer)`, [limit]);
    if (!Array.isArray(result.rows) || result.rows.length > limit) throw new Error('Red-day database response is invalid.');
    const seen = new Set<string>();
    return Object.freeze(result.rows.map(raw => {
      const row = rowObject(raw);
      exactKeys(row, ['after_market_date', 'asset_id']);
      const assetId = row['asset_id'];
      if (typeof assetId !== 'string' || assetId.length > 100 || !assetPattern.test(assetId) || seen.has(assetId)) {
        throw new Error('Red-day database response is invalid.');
      }
      seen.add(assetId);
      return Object.freeze({assetId, afterMarketDate: date(row['after_market_date'])});
    }));
  }

  async record(observation: RedDayObservation): Promise<RedDayRecordResult> {
    if (!uuidPattern.test(observation.observationId)) throw new TypeError('Red-day observation ID is invalid.');
    const verified = 'session' in observation;
    const session = verified ? observation.session : null;
    const failure = verified ? null : observation;
    const audit = verified ? observation.session.audit : observation.audit;
    const payload = [
      session?.provider ?? failure?.provider,
      session?.verifierVersion ?? failure?.verifierVersion,
      session?.assetId ?? failure?.assetId,
      session?.listedSymbol ?? failure?.listedSymbol,
      session?.outcome ?? failure?.status,
      session?.previousMarketDate ?? null,
      session?.marketDate ?? null,
      session?.previousCloseText ?? null,
      session?.currentCloseText ?? null,
      session?.providerAsOf ?? null,
      session?.providerLastFetchedAt ?? null,
      session?.source ?? null,
      failure?.reasonCode ?? null,
      audit.detailRequestId,
      audit.chartRequestId,
      audit.detailProviderRequestId,
      audit.chartProviderRequestId,
      audit.detailPath,
      pathOrNull(audit.chartPath),
      audit.detailResponseSha256,
      audit.chartResponseSha256,
      session?.observedAt ?? failure?.observedAt,
    ] as const;
    const result = await this.pool.query(
      `SELECT outcome, observation_id, evidence_count, completed_count
       FROM trimmy.career_red_day_record_observation(
         $1::uuid, $2::text, $3::text, $4::text, $5::text,
         $6::text, $7::date, $8::date, $9::text, $10::text,
         $11::timestamptz, $12::timestamptz, $13::text, $14::text,
         $15::uuid, $16::uuid, $17::text, $18::text, $19::text, $20::text,
         $21::text, $22::text, $23::timestamptz
       )`, [observation.observationId, ...payload]);
    if (result.rows.length !== 1) throw new Error('Red-day database response is invalid.');
    const row = rowObject(result.rows[0]);
    exactKeys(row, ['completed_count', 'evidence_count', 'observation_id', 'outcome']);
    const outcome = row['outcome'];
    const observationId = row['observation_id'];
    if (!['recorded', 'already-recorded', 'correction-review', 'already-reviewed',
      'idempotency-conflict'].includes(String(outcome)) ||
        typeof observationId !== 'string' || !uuidPattern.test(observationId)) {
      throw new Error('Red-day database response is invalid.');
    }
    return Object.freeze({outcome: outcome as RedDayRecordResult['outcome'], observationId,
      evidenceCount: integer(row['evidence_count']), completedCount: integer(row['completed_count'])});
  }

  async processSession(observationId: string, limit: number): Promise<RedDayProcessResult> {
    if (!uuidPattern.test(observationId) || !Number.isInteger(limit) || limit < 1 || limit > 100) {
      throw new TypeError('Red-day processing input is invalid.');
    }
    const result = await this.pool.query(
      `SELECT outcome, observation_id, evidence_count, completed_count, processing_complete
       FROM trimmy.career_red_day_process_session($1::uuid, $2::integer)`,
      [observationId, limit]);
    if (result.rows.length !== 1) throw new Error('Red-day database response is invalid.');
    const row = rowObject(result.rows[0]);
    exactKeys(row, ['completed_count', 'evidence_count', 'observation_id', 'outcome', 'processing_complete']);
    const outcome = row['outcome'];
    const returnedId = row['observation_id'];
    const processingComplete = row['processing_complete'];
    if (!['processed', 'complete', 'already-complete'].includes(String(outcome)) ||
        typeof returnedId !== 'string' || !uuidPattern.test(returnedId) ||
        returnedId.toLowerCase() !== observationId.toLowerCase() || typeof processingComplete !== 'boolean' ||
        (outcome === 'processed' && processingComplete) ||
        (outcome !== 'processed' && !processingComplete)) {
      throw new Error('Red-day database response is invalid.');
    }
    return Object.freeze({outcome: outcome as RedDayProcessResult['outcome'],
      observationId: returnedId.toLowerCase(), evidenceCount: integer(row['evidence_count']),
      completedCount: integer(row['completed_count']), processingComplete});
  }
}
