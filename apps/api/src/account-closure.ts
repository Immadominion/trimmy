import type { Pool, PoolClient } from 'pg';
import {DEFAULT_RELATIONSHIP_MODERATION_ROLE, parseRelationshipModerationRole} from
  './relationship-safety-config.js';

/**
 * Closing an account. This is a lockout, not an erasure: once closed, every
 * account-scoped lookup excludes the account, so practice sync, watchlists and
 * invitations all stop resolving and the person can no longer authenticate.
 *
 * Saved history is deliberately left intact, because this schema treats
 * practice completions, receipts and invitations as immutable records and
 * grants no DELETE to any role. Erasing or anonymising them is a separate
 * reviewed decision, and this module does not claim to do it.
 */
export type AccountClosureErrorCode =
  | 'ACCOUNT_CLOSURE_INVALID_INPUT' | 'ACCOUNT_CLOSURE_NOT_FOUND'
  | 'ACCOUNT_CLOSURE_RUNTIME_ROLE_INVALID' | 'ACCOUNT_CLOSURE_UNAVAILABLE';

export class AccountClosureError extends Error {
  constructor(readonly code: AccountClosureErrorCode, message: string) {
    super(message);
    this.name = 'AccountClosureError';
  }
}

export interface AccountClosureResult {
  /** True when this request performed the closure, false when already closed. */
  readonly closed: boolean;
  /** Open invitations involving this account, cancelled as part of closing. */
  readonly canceledInvitations: number;
}

export interface AccountClosureRepository {
  close(userId: string, freshXSubject?: string | null): Promise<AccountClosureResult>;
}

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const xSubject = /^[1-9][0-9]{0,19}$/;

function invalid(): never {
  throw new AccountClosureError('ACCOUNT_CLOSURE_INVALID_INPUT', 'Account closure request is invalid.');
}

export function parseClosureUserId(value: unknown): string {
  if (typeof value !== 'string' || uuid.exec(value)?.[0] !== value) invalid();
  return value;
}

function parseOptionalXSubject(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  try {
    if (typeof value !== 'string' || xSubject.exec(value)?.[0] !== value ||
        BigInt(value) > 18_446_744_073_709_551_615n) invalid();
  } catch { invalid(); }
  return value;
}

export class PostgresAccountClosure implements AccountClosureRepository {
  private readonly moderationRole: string;

  constructor(
    private readonly pool: Pick<Pool, 'connect'>,
    moderationRole = DEFAULT_RELATIONSHIP_MODERATION_ROLE,
  ) {
    this.moderationRole = parseRelationshipModerationRole(moderationRole);
  }

  async close(inputUserId: string, inputFreshXSubject: string | null = null): Promise<AccountClosureResult> {
    const userId = parseClosureUserId(inputUserId);
    const freshXSubject = parseOptionalXSubject(inputFreshXSubject);
    const client = await this.pool.connect();
    let releaseError: Error | undefined;
    try {
      await client.query('BEGIN');
      await this.assertSafeRole(client);
      await client.query("SELECT set_config('trimmy.practice_user_id', $1, true)", [userId]);

      // Social cleanup and account closure are one database-owned mutation.
      // The runtime has no direct invitation or provider-identity authority.
      const closure = await client.query<{
        outcome: unknown;
        closed: unknown;
        canceled_invitations: unknown;
        removed_friendships: unknown;
      }>('SELECT * FROM trimmy.social_close_current_account($1::text)', [freshXSubject]);
      if (closure.rows.length !== 1) {
        throw new AccountClosureError('ACCOUNT_CLOSURE_UNAVAILABLE', 'The account could not be closed.');
      }
      const row = closure.rows[0]!;
      if (row.outcome === 'invalid') invalid();
      if (row.outcome === 'account_missing') {
        throw new AccountClosureError('ACCOUNT_CLOSURE_NOT_FOUND', 'That account is unavailable.');
      }
      if (row.outcome !== 'saved' || typeof row.closed !== 'boolean' ||
          typeof row.canceled_invitations !== 'number' ||
          !Number.isSafeInteger(row.canceled_invitations) || row.canceled_invitations < 0 ||
          typeof row.removed_friendships !== 'number' ||
          !Number.isSafeInteger(row.removed_friendships) || row.removed_friendships < 0) {
        throw new AccountClosureError('ACCOUNT_CLOSURE_UNAVAILABLE', 'The account could not be closed.');
      }
      await client.query('COMMIT');
      return Object.freeze({closed: row.closed, canceledInvitations: row.canceled_invitations});
    } catch (error) {
      try { await client.query('ROLLBACK'); }
      catch { releaseError = new Error('Account closure cleanup failed.'); }
      if (error instanceof AccountClosureError) throw error;
      throw new AccountClosureError('ACCOUNT_CLOSURE_UNAVAILABLE', 'The account could not be closed.');
    } finally {
      client.release(releaseError);
    }
  }

  /** The same boundary the other repositories enforce before touching data. */
  private async assertSafeRole(client: PoolClient): Promise<void> {
    const role = await client.query<{unsafe_role: boolean}>(`
      SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_roles
        WHERE (rolsuper OR rolbypassrls) AND pg_catalog.pg_has_role(current_user, oid, 'MEMBER'))
        OR EXISTS (SELECT 1 FROM pg_catalog.pg_roles
          WHERE rolname = $1 AND pg_catalog.pg_has_role(current_user, oid, 'MEMBER'))
        OR EXISTS (SELECT 1 FROM pg_catalog.pg_class c
          JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'trimmy' AND c.relname IN (
            'users', 'invitations', 'provider_identities', 'social_profiles',
            'social_invitation_create_receipts', 'social_friendships',
            'social_friendship_events', 'social_friendship_receipts',
            'social_blocks', 'social_block_receipts', 'social_reason_reports',
            'social_reason_moderation', 'social_reason_moderation_events',
            'social_rate_windows')
            AND pg_catalog.pg_has_role(current_user, c.relowner, 'MEMBER')) AS unsafe_role`,
      [this.moderationRole]);
    if (role.rows.length !== 1 || role.rows[0]?.unsafe_role !== false) {
      throw new AccountClosureError('ACCOUNT_CLOSURE_RUNTIME_ROLE_INVALID',
        'Account closure requires a dedicated runtime role.');
    }
  }
}
