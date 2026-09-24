import { createHash } from 'node:crypto';
import type { Pool, QueryResultRow } from 'pg';
import {
  ProductProfileRepositoryError, parseProductLaunchWrite, parseProductProfilePrincipal,
  parseProductProfileSnapshot, parseProductProfileUserId, parseProductProfileWrite,
} from './product-profile-repository.js';
import type {
  ProductLaunchWrite, ProductProfilePrincipal, ProductProfileRepository, ProductProfileSnapshot,
  ProductProfileWrite,
} from './product-profile-repository.js';

interface ProfileRow extends QueryResultRow {
  outcome: unknown;
  revision: unknown;
  goal: unknown;
  knowledge: unknown;
  persona: unknown;
  daily_goal: unknown;
  handle: unknown;
  launch_checkpoint: unknown;
  has_confirmed_paper_trade: unknown;
  created_at: unknown;
  updated_at: unknown;
}

function storageInvalid(): never {
  throw new ProductProfileRepositoryError(
    'PRODUCT_PROFILE_STORAGE_INVALID',
    'Stored product profile could not be read safely.',
  );
}

function time(value: unknown): string {
  if (!(value instanceof Date) || !Number.isFinite(value.getTime())) storageInvalid();
  return value.toISOString();
}

function snapshot(row: ProfileRow): ProductProfileSnapshot {
  if (typeof row.revision !== 'string' || !/^[1-9][0-9]{0,15}$/.test(row.revision)) storageInvalid();
  return parseProductProfileSnapshot({
    revision: Number(row.revision),
    onboarding: {
      goal: row.goal,
      knowledge: row.knowledge,
      persona: row.persona,
      dailyGoal: row.daily_goal,
      handle: row.handle,
    },
    launchCheckpoint: row.launch_checkpoint,
    hasConfirmedPaperTrade: row.has_confirmed_paper_trade,
    createdAt: time(row.created_at),
    updatedAt: time(row.updated_at),
  });
}

const columns = `outcome, revision::text AS revision, goal, knowledge, persona, daily_goal, handle,
  launch_checkpoint, created_at, updated_at,
  trimmy.product_profile_has_confirmed_paper_trade($1::uuid) AS has_confirmed_paper_trade`;

export class PostgresProductProfileRepository implements ProductProfileRepository {
  constructor(private readonly pool: Pick<Pool, 'connect'>) {}

  async get(inputUserId: string): Promise<ProductProfileSnapshot | null> {
    const userId = parseProductProfileUserId(inputUserId);
    return this.call(`SELECT ${columns} FROM trimmy.product_profile_get($1::uuid)`, [userId], false);
  }

  async put(inputUserId: string, input: ProductProfileWrite): Promise<ProductProfileSnapshot> {
    const userId = parseProductProfileUserId(inputUserId);
    const command = parseProductProfileWrite(input);
    const canonical = JSON.stringify({
      baseRevision: command.baseRevision,
      onboarding: command.onboarding,
      launchCheckpoint: command.launchCheckpoint,
    });
    const requestHash = createHash('sha256').update(canonical).digest('hex');
    const result = await this.call(`SELECT ${columns} FROM trimmy.product_profile_put(
        $1::uuid,$2::uuid,$3::text,$4::bigint,$5::text,$6::text,$7::text,$8::text,$9::text,$10::text)`,
      [userId, command.mutationId, requestHash, command.baseRevision, command.onboarding.goal,
        command.onboarding.knowledge, command.onboarding.persona, command.onboarding.dailyGoal,
        command.onboarding.handle, command.launchCheckpoint], true);
    if (result === null) storageInvalid();
    return result;
  }

  async advance(
    inputPrincipal: ProductProfilePrincipal,
    input: ProductLaunchWrite,
  ): Promise<ProductProfileSnapshot> {
    const principal = parseProductProfilePrincipal(inputPrincipal);
    const command = parseProductLaunchWrite(input);
    const canonical = JSON.stringify({
      operation: 'product-launch-v1',
      baseRevision: command.baseRevision,
      action: command.action,
    });
    const requestHash = createHash('sha256').update(canonical).digest('hex');
    const result = await this.call(`SELECT ${columns} FROM trimmy.product_launch_advance(
        $1::uuid,$2::uuid,$3::text,$4::bigint,$5::text,$6::uuid)`,
      [principal.userId, command.mutationId, requestHash, command.baseRevision, command.action,
        principal.kind === 'guest' ? principal.guestId : null], true);
    if (result === null) storageInvalid();
    return result;
  }

  private async call(
    sql: string,
    values: readonly unknown[],
    writing: boolean,
  ): Promise<ProductProfileSnapshot | null> {
    const client = await this.pool.connect();
    let releaseError: Error | undefined;
    try {
      await client.query(writing ? 'BEGIN' : 'BEGIN READ ONLY');
      const role = await client.query<{unsafe_role: boolean}>(`
        SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_roles
          WHERE (rolsuper OR rolbypassrls) AND pg_catalog.pg_has_role(current_user, oid, 'MEMBER'))
          OR EXISTS (SELECT 1 FROM pg_catalog.pg_class c
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'trimmy'
              AND c.relname IN ('users', 'product_profiles', 'product_profile_mutation_receipts',
                'product_launch_action_receipts', 'paper_orders', 'guest_sessions',
                'practice_auth_identities', 'career_profiles', 'career_starts',
                'career_first_confirmed_buys')
              AND pg_catalog.pg_has_role(current_user, c.relowner, 'MEMBER')) AS unsafe_role`);
      if (role.rows.length !== 1 || role.rows[0]?.unsafe_role !== false) {
        throw new ProductProfileRepositoryError(
          'PRODUCT_PROFILE_RUNTIME_ROLE_INVALID',
          'Product profile storage requires a dedicated runtime role.',
        );
      }
      const result = await client.query<ProfileRow>(sql, [...values]);
      if (result.rows.length !== 1 || result.rows[0] === undefined || typeof result.rows[0].outcome !== 'string') {
        storageInvalid();
      }
      const row = result.rows[0];
      if (row.outcome === 'found' || row.outcome === 'saved') {
        const profile = snapshot(row);
        await client.query('COMMIT');
        return profile;
      }
      if (row.outcome === 'missing') {
        await client.query('COMMIT');
        return null;
      }
      const code = row.outcome === 'account_missing' ? 'PRODUCT_PROFILE_ACCOUNT_NOT_FOUND'
        : row.outcome === 'idempotency_conflict' ? 'PRODUCT_PROFILE_IDEMPOTENCY_CONFLICT'
        : row.outcome === 'revision_conflict' ? 'PRODUCT_PROFILE_REVISION_CONFLICT'
        : row.outcome === 'revision_exhausted' ? 'PRODUCT_PROFILE_REVISION_EXHAUSTED'
        : row.outcome === 'checkpoint_conflict' ? 'PRODUCT_PROFILE_CHECKPOINT_CONFLICT'
        : row.outcome === 'paper_trade_required' ? 'PRODUCT_PROFILE_PAPER_TRADE_REQUIRED'
        : row.outcome === 'evidence_required' ? 'PRODUCT_PROFILE_LAUNCH_EVIDENCE_REQUIRED'
        : row.outcome === 'principal_conflict' ? 'PRODUCT_PROFILE_PRINCIPAL_CONFLICT'
        : row.outcome === 'profile_missing' ? 'PRODUCT_PROFILE_MISSING'
        : row.outcome === 'handle_taken' ? 'PRODUCT_PROFILE_HANDLE_TAKEN'
        : row.outcome === 'invalid' ? 'PRODUCT_PROFILE_INVALID_INPUT'
        : 'PRODUCT_PROFILE_STORAGE_INVALID';
      const currentProfile = row.outcome === 'revision_conflict' && row.revision !== null
        ? snapshot(row) : row.outcome === 'revision_conflict' ? null : undefined;
      throw new ProductProfileRepositoryError(code, 'Product profile request was not accepted.',
        currentProfile);
    } catch (error) {
      try { await client.query('ROLLBACK'); }
      catch { releaseError = new Error('Product profile transaction cleanup failed.'); }
      if (error instanceof ProductProfileRepositoryError) throw error;
      throw new ProductProfileRepositoryError('PRODUCT_PROFILE_STORAGE_INVALID', 'Product profile storage failed.');
    } finally {
      client.release(releaseError);
    }
  }
}
