import type { Pool, QueryResult, QueryResultRow } from 'pg';
import { parsePracticeIdentity } from './practice-identity.js';
import { GuestSessionError } from './guest-session-repository.js';
import type {
  GuestAuthorization, GuestClaimResult, GuestCreationAdmission, GuestPaperScope, GuestSessionRecord,
  GuestSessionRepository,
} from './guest-session-repository.js';

interface AdmissionRow extends QueryResultRow {
  outcome: unknown;
  attempt_id: unknown;
  retry_after_seconds: unknown;
}

interface SessionRow extends QueryResultRow {
  outcome: unknown;
  guest_id: unknown;
  expires_at: unknown;
  hard_expires_at: unknown;
  retry_after_seconds: unknown;
}
interface AuthorizationRow extends QueryResultRow {
  outcome: unknown;
  user_id: unknown;
  guest_id: unknown;
  expires_at: unknown;
}
interface ClaimRow extends QueryResultRow { outcome: unknown; guest_id: unknown; claimed_at: unknown }

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const sha256 = /^[a-f0-9]{64}$/;

function invalid(): never {
  throw new GuestSessionError('GUEST_SESSION_STORAGE_INVALID', 'Guest session storage returned invalid data.');
}
function parseUuid(value: unknown): string {
  if (typeof value !== 'string' || !uuid.test(value)) invalid();
  return value;
}
function parseHash(value: unknown): string {
  if (typeof value !== 'string' || !sha256.test(value)) invalid();
  return value;
}
function parseTime(value: unknown): string {
  if (!(value instanceof Date) || !Number.isFinite(value.getTime())) invalid();
  return value.toISOString();
}
function parseRetryAfter(value: unknown): number {
  const parsed = typeof value === 'bigint' ? Number(value)
    : typeof value === 'string' && /^\d+$/.test(value) ? Number(value)
      : typeof value === 'number' ? value : Number.NaN;
  if (!Number.isSafeInteger(parsed) || parsed < 1 || parsed > 86_400) invalid();
  return parsed;
}
function parseAttemptId(value: unknown): string {
  const text = typeof value === 'bigint' ? value.toString()
    : typeof value === 'number' && Number.isSafeInteger(value) ? String(value)
      : typeof value === 'string' ? value : '';
  if (!/^[1-9]\d{0,18}$/.test(text) || BigInt(text) > 9_223_372_036_854_775_807n) invalid();
  return text;
}

function sessionFailure(outcome: unknown): never {
  const code = outcome === 'expired' ? 'GUEST_SESSION_EXPIRED'
    : outcome === 'revoked' ? 'GUEST_SESSION_REVOKED'
    : outcome === 'rate_limited' ? 'GUEST_SESSION_RATE_LIMITED'
    : outcome === 'unavailable' ? 'GUEST_SESSION_UNAVAILABLE'
    : 'GUEST_SESSION_UNAUTHENTICATED';
  throw new GuestSessionError(code, 'Guest session is unavailable.');
}

/** Calls fixed SECURITY DEFINER functions through a dedicated runtime pool. */
export class PostgresGuestSessionRepository implements GuestSessionRepository {
  constructor(private readonly pool: Pick<Pool, 'connect'>) {}

  private async call<Row extends QueryResultRow>(sql: string, values: readonly unknown[]): Promise<QueryResult<Row>> {
    const client = await this.pool.connect();
    let releaseError: Error | undefined;
    try {
      await client.query('BEGIN');
      const role = await client.query<{unsafe_role: boolean}>(`
        SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_roles
          WHERE (rolsuper OR rolbypassrls) AND pg_catalog.pg_has_role(current_user, oid, 'MEMBER'))
          OR EXISTS (SELECT 1 FROM pg_catalog.pg_class c
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'trimmy'
              AND c.relname IN ('users', 'practice_auth_identities', 'guest_sessions', 'guest_rate_windows',
                'guest_creation_attempts')
              AND pg_catalog.pg_has_role(current_user, c.relowner, 'MEMBER')) AS unsafe_role`);
      if (role.rows.length !== 1 || role.rows[0]?.unsafe_role !== false) {
        throw new GuestSessionError('GUEST_SESSION_RUNTIME_ROLE_INVALID',
          'Guest session storage requires a dedicated runtime role.');
      }
      const result = await client.query<Row>(sql, [...values]);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      try { await client.query('ROLLBACK'); } catch {
        releaseError = new Error('Guest session transaction cleanup failed.');
      }
      throw error;
    } finally {
      client.release(releaseError);
    }
  }

  async takeCreationAttempt(sourceHash: string): Promise<GuestCreationAdmission> {
    const hash = parseHash(sourceHash);
    try {
      const result = await this.call<AdmissionRow>(
        'SELECT outcome, attempt_id, retry_after_seconds FROM trimmy.guest_take_creation_attempt($1::text)', [hash],
      );
      const row = result.rows[0];
      if (result.rows.length !== 1 || row === undefined) invalid();
      if (row.outcome === 'rate_limited') {
        throw new GuestSessionError('GUEST_SESSION_RATE_LIMITED', 'Guest session creation is rate limited.',
          parseRetryAfter(row.retry_after_seconds));
      }
      if (row.outcome !== 'admitted' || row.retry_after_seconds !== null) invalid();
      return Object.freeze({sourceHash: hash, attemptId: parseAttemptId(row.attempt_id)});
    } catch (error) {
      if (error instanceof GuestSessionError) throw error;
      throw new GuestSessionError('GUEST_SESSION_UNAVAILABLE', 'Guest sessions are unavailable.');
    }
  }

  async create(command: {readonly sourceHash: string; readonly requestHash: string; readonly replayHash: string; readonly guestId: string;
    readonly attemptId: string; readonly credentialHash: string}): Promise<GuestSessionRecord> {
    const sourceHash = parseHash(command.sourceHash);
    const attemptId = parseAttemptId(command.attemptId);
    const requestHash = parseHash(command.requestHash);
    const replayHash = parseHash(command.replayHash);
    const guestId = parseUuid(command.guestId);
    const credentialHash = parseHash(command.credentialHash);
    try {
      const result = await this.call<SessionRow>(
        `SELECT outcome, guest_id, expires_at, hard_expires_at, retry_after_seconds
          FROM trimmy.guest_create_session($1::text,$2::bigint,$3::text,$4::text,$5::uuid,$6::text)`,
        [sourceHash, attemptId, requestHash, replayHash, guestId, credentialHash],
      );
      const row = result.rows[0];
      if (result.rows.length !== 1 || row === undefined) invalid();
      if (row.outcome === 'unavailable') sessionFailure(row.outcome);
      if (row.outcome !== 'created' || row.retry_after_seconds !== null) invalid();
      return Object.freeze({guestId: parseUuid(row.guest_id), expiresAt: parseTime(row.expires_at),
        hardExpiresAt: parseTime(row.hard_expires_at)});
    } catch (error) {
      if (error instanceof GuestSessionError) throw error;
      throw new GuestSessionError('GUEST_SESSION_UNAVAILABLE', 'Guest sessions are unavailable.');
    }
  }

  async authorize(credentialHash: string, scope: GuestPaperScope): Promise<GuestAuthorization> {
    const hash = parseHash(credentialHash);
    try {
      const result = await this.call<AuthorizationRow>(
        'SELECT outcome, user_id, guest_id, expires_at FROM trimmy.guest_authorize($1::text,$2::text)',
        [hash, scope],
      );
      const row = result.rows[0];
      if (result.rows.length !== 1 || row === undefined) invalid();
      if (row.outcome !== 'authorized') sessionFailure(row.outcome);
      return Object.freeze({userId: parseUuid(row.user_id), guestId: parseUuid(row.guest_id),
        expiresAt: parseTime(row.expires_at)});
    } catch (error) {
      if (error instanceof GuestSessionError) throw error;
      throw new GuestSessionError('GUEST_SESSION_UNAVAILABLE', 'Guest sessions are unavailable.');
    }
  }

  async refresh(credentialHash: string): Promise<GuestSessionRecord> {
    const hash = parseHash(credentialHash);
    try {
      const result = await this.call<SessionRow>(
        'SELECT outcome, guest_id, expires_at, hard_expires_at FROM trimmy.guest_refresh_session($1::text)', [hash],
      );
      const row = result.rows[0];
      if (result.rows.length !== 1 || row === undefined) invalid();
      if (row.outcome !== 'refreshed') sessionFailure(row.outcome);
      return Object.freeze({guestId: parseUuid(row.guest_id), expiresAt: parseTime(row.expires_at),
        hardExpiresAt: parseTime(row.hard_expires_at)});
    } catch (error) {
      if (error instanceof GuestSessionError) throw error;
      throw new GuestSessionError('GUEST_SESSION_UNAVAILABLE', 'Guest sessions are unavailable.');
    }
  }

  async claim(command: {
    readonly credentialHash: string;
    readonly identity: import('./practice-identity.js').PracticeIdentity;
    readonly idempotencyKey: string;
  }): Promise<GuestClaimResult> {
    const credentialHash = parseHash(command.credentialHash);
    const identity = parsePracticeIdentity(command.identity);
    const idempotencyKey = parseUuid(command.idempotencyKey);
    try {
      const result = await this.call<ClaimRow>(
        `SELECT outcome, guest_id, claimed_at FROM trimmy.guest_claim_session(
          $1::text,$2::text,$3::text,$4::uuid)`,
        [credentialHash, identity.appId, identity.subject, idempotencyKey],
      );
      const row = result.rows[0];
      if (result.rows.length !== 1 || row === undefined) invalid();
      if (row.outcome !== 'claimed') {
        const code = row.outcome === 'identity_bound' ? 'GUEST_CLAIM_ACCOUNT_EXISTS'
          : row.outcome === 'claimed_elsewhere' || row.outcome === 'guest_bound' ? 'GUEST_CLAIM_ALREADY_USED'
          : row.outcome === 'idempotency_conflict' ? 'GUEST_CLAIM_IDEMPOTENCY_CONFLICT'
          : row.outcome === 'rate_limited' ? 'GUEST_SESSION_RATE_LIMITED'
          : row.outcome === 'expired' ? 'GUEST_SESSION_EXPIRED'
          : row.outcome === 'revoked' ? 'GUEST_SESSION_REVOKED'
          : row.outcome === 'unavailable' ? 'GUEST_SESSION_UNAVAILABLE'
          : 'GUEST_SESSION_UNAUTHENTICATED';
        throw new GuestSessionError(code, 'Guest desk could not be claimed.');
      }
      return Object.freeze({guestId: parseUuid(row.guest_id), claimedAt: parseTime(row.claimed_at)});
    } catch (error) {
      if (error instanceof GuestSessionError) throw error;
      throw new GuestSessionError('GUEST_SESSION_UNAVAILABLE', 'Guest sessions are unavailable.');
    }
  }
}
