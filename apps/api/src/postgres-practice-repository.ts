import { createHash } from 'node:crypto';
import { assertPracticeHistoryPreserved, canonicalPracticeProgress, parsePracticeProgress } from '@trimmy/domain';
import type { Pool, PoolClient, QueryResultRow } from 'pg';
import {
  EMPTY_PRACTICE_SNAPSHOT, PracticeRepositoryError, parsePracticeUserId, parsePracticeWrite,
} from './practice-repository.js';
import type { PracticeRepository, PracticeSnapshot, PracticeWrite } from './practice-repository.js';

interface SnapshotRow extends QueryResultRow {
  revision: unknown;
  progress: unknown;
  updated_at: unknown;
}

// Use explicit UTC milliseconds rather than global pg type-parser changes.
const snapshotColumns = `revision::text AS revision, progress,
  to_char(updated_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS updated_at`;

function storageInvalid(): never {
  throw new PracticeRepositoryError('PRACTICE_STORAGE_INVALID', 'Stored practice progress could not be read safely.');
}

function snapshot(row: SnapshotRow): PracticeSnapshot {
  if (typeof row.revision !== 'string' || !/^[1-9][0-9]{0,15}$/.test(row.revision)) storageInvalid();
  const revision = Number(row.revision);
  if (!Number.isSafeInteger(revision) || revision < 1) storageInvalid();
  const updatedAt = row.updated_at;
  if (typeof updatedAt !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(updatedAt) ||
      !Number.isFinite(Date.parse(updatedAt)) || new Date(updatedAt).toISOString() !== updatedAt) storageInvalid();
  try {
    return Object.freeze({revision, progress: parsePracticeProgress(row.progress), updatedAt});
  } catch {
    return storageInvalid();
  }
}

async function currentSnapshot(client: PoolClient, userId: string, lock = false): Promise<PracticeSnapshot> {
  const result = await client.query<SnapshotRow>(
    `SELECT ${snapshotColumns} FROM trimmy.practice_progress WHERE user_id = $1::uuid${lock ? ' FOR UPDATE' : ''}`,
    [userId],
  );
  if (result.rows.length > 1) storageInvalid();
  return result.rows[0] ? snapshot(result.rows[0]) : EMPTY_PRACTICE_SNAPSHOT;
}

/**
 * The caller owns this dedicated, nonprivileged pool and its shutdown lifecycle.
 * No environment lookup or in-memory fallback is permitted here.
 * Every transaction stays on one checked-out client:
 * https://node-postgres.com/features/transactions
 */
export class PostgresPracticeRepository implements PracticeRepository {
  constructor(private readonly pool: Pick<Pool, 'connect'>) {}

  async get(inputUserId: string): Promise<PracticeSnapshot> {
    const userId = parsePracticeUserId(inputUserId);
    return this.transaction(userId, true, client => currentSnapshot(client, userId));
  }

  async put(inputUserId: string, input: PracticeWrite): Promise<PracticeSnapshot> {
    const userId = parsePracticeUserId(inputUserId);
    // Parse and clone before the first await; a caller cannot mutate the command
    // while a connection or account lock is pending.
    const command = parsePracticeWrite(input);
    const progressJson = canonicalPracticeProgress(command.progress);
    const hash = createHash('sha256')
      .update(`{"baseRevision":${command.baseRevision},"progress":${progressJson}}`)
      .digest('hex');

    return this.transaction(userId, false, async client => {
      // Hash collisions only serialize unrelated accounts; they never share data.
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1::text, 0))', [`trimmy.practice:${userId}`]);
      const receipt = await client.query<SnapshotRow & {request_hash: unknown}>(
        `SELECT request_hash, ${snapshotColumns} FROM trimmy.practice_mutation_receipts
         WHERE user_id = $1::uuid AND mutation_id = $2::uuid`,
        [userId, command.mutationId],
      );
      if (receipt.rows.length > 1) storageInvalid();
      if (receipt.rows[0]) {
        if (typeof receipt.rows[0].request_hash !== 'string' || !/^[a-f0-9]{64}$/.test(receipt.rows[0].request_hash)) storageInvalid();
        if (receipt.rows[0].request_hash !== hash) {
          throw new PracticeRepositoryError('PRACTICE_IDEMPOTENCY_CONFLICT', 'Mutation ID already belongs to a different request.');
        }
        // Replay precedes revision/history checks and returns the original result,
        // even after subsequent writes have advanced this account.
        return snapshot(receipt.rows[0]);
      }

      const current = await currentSnapshot(client, userId, true);
      if (current.revision !== command.baseRevision) {
        throw new PracticeRepositoryError('PRACTICE_REVISION_CONFLICT', 'Practice progress changed. Review the current snapshot.', current);
      }
      if (current.progress !== null) {
        if (command.progress.version < current.progress.version) {
          throw new PracticeRepositoryError('PRACTICE_VERSION_DOWNGRADE', 'Practice payload version cannot move backwards.');
        }
        try {
          assertPracticeHistoryPreserved(current.progress, command.progress);
        } catch {
          throw new PracticeRepositoryError('PRACTICE_HISTORY_CONFLICT', 'A saved first completion cannot be removed or replaced.');
        }
      }
      if (current.revision === Number.MAX_SAFE_INTEGER) {
        throw new PracticeRepositoryError('PRACTICE_REVISION_EXHAUSTED', 'Practice revision limit has been reached.');
      }
      const nextRevision = current.revision + 1;
      const saved = current.revision === 0
        ? await client.query<SnapshotRow>(
          `INSERT INTO trimmy.practice_progress (user_id, revision, progress, updated_at)
           VALUES ($1::uuid, 1, $2::jsonb, date_trunc('milliseconds', clock_timestamp()))
           ON CONFLICT (user_id) DO NOTHING RETURNING ${snapshotColumns}`,
          [userId, progressJson],
        )
        : await client.query<SnapshotRow>(
          `UPDATE trimmy.practice_progress
           SET revision = $2, progress = $3::jsonb, updated_at = date_trunc('milliseconds', clock_timestamp())
           WHERE user_id = $1::uuid AND revision = $4 RETURNING ${snapshotColumns}`,
          [userId, nextRevision, progressJson, current.revision],
        );
      if (saved.rows.length === 0) {
        throw new PracticeRepositoryError('PRACTICE_REVISION_CONFLICT', 'Practice progress changed. Review the current snapshot.', await currentSnapshot(client, userId));
      }
      if (saved.rows.length !== 1) storageInvalid();
      const committed = snapshot(saved.rows[0]!);
      if (committed.revision !== nextRevision || canonicalPracticeProgress(committed.progress!) !== progressJson) storageInvalid();
      await client.query(
        `INSERT INTO trimmy.practice_mutation_receipts
         (user_id, mutation_id, request_hash, revision, progress, updated_at)
         VALUES ($1::uuid, $2::uuid, $3, $4, $5::jsonb, $6::timestamptz)`,
        [userId, command.mutationId, hash, committed.revision, progressJson, committed.updatedAt],
      );
      return committed;
    });
  }

  private async transaction<T>(userId: string, readOnly: boolean, run: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.pool.connect();
    let releaseError: Error | undefined;
    try {
      await client.query(readOnly ? 'BEGIN READ ONLY' : 'BEGIN');
      // Include memberships: SET ROLE must not offer a path around account RLS.
      const role = await client.query<{unsafe_role: boolean}>(`
        SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_roles
          WHERE (rolsuper OR rolbypassrls) AND pg_catalog.pg_has_role(current_user, oid, 'MEMBER'))
          OR EXISTS (SELECT 1 FROM pg_catalog.pg_class c
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'trimmy' AND c.relname IN ('users', 'practice_progress', 'practice_mutation_receipts')
              AND pg_catalog.pg_has_role(current_user, c.relowner, 'MEMBER')) AS unsafe_role`);
      if (role.rows.length !== 1 || role.rows[0]?.unsafe_role !== false) {
        throw new PracticeRepositoryError('PRACTICE_RUNTIME_ROLE_INVALID', 'Practice storage requires a dedicated runtime role.');
      }
      await client.query("SELECT set_config('trimmy.practice_user_id', $1, true)", [userId]);
      const account = await client.query<{account_exists: boolean}>('SELECT trimmy.practice_account_exists() AS account_exists');
      if (account.rows.length !== 1 || typeof account.rows[0]?.account_exists !== 'boolean') storageInvalid();
      if (!account.rows[0].account_exists) {
        throw new PracticeRepositoryError('PRACTICE_ACCOUNT_NOT_FOUND', 'Practice account is unavailable.');
      }
      const result = await run(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      try {
        await client.query('ROLLBACK');
      } catch {
        // Never return a client with unknown transaction/session state to the pool.
        releaseError = new Error('Practice transaction cleanup failed.');
      }
      throw error;
    } finally {
      client.release(releaseError);
    }
  }
}
