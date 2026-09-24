import { createHash } from 'node:crypto';
import type { Pool, PoolClient, QueryResultRow } from 'pg';
import {
  EMPTY_WATCHLIST_SNAPSHOT, WatchlistRepositoryError,
  parseWatchlistSnapshot, parseWatchlistUserId, parseWatchlistWrite, watchlistCatalog,
} from './watchlist-repository.js';
import type { WatchlistCatalog, WatchlistRepository, WatchlistSnapshot, WatchlistWrite } from './watchlist-repository.js';

interface SnapshotRow extends QueryResultRow {
  revision: unknown;
  asset_ids: unknown;
  updated_at: unknown;
}

const columns = `revision::text AS revision, asset_ids,
  to_char(updated_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') AS updated_at`;

/**
 * The two lists this storage engine serves, by name.
 *
 * They share identical semantics (one row per account, a revision, idempotent
 * receipts, a per-account advisory lock), so they share this proven
 * implementation rather than a second copy of its concurrency handling. Only
 * these names are accepted, so no caller can put an identifier into the SQL.
 *
 * They are separate tables on purpose: a fictional sample list and a list of
 * real looked-up assets must never be able to merge into one another.
 */
const TABLES = Object.freeze({
  watchlists: Object.freeze({list: 'watchlists', receipts: 'watchlist_mutation_receipts', lock: 'trimmy.watchlist'}),
  followed_stocks: Object.freeze({
    list: 'followed_stocks', receipts: 'followed_stock_mutation_receipts', lock: 'trimmy.followed_stocks',
  }),
});
export type WatchlistTableSet = keyof typeof TABLES;

function storageInvalid(): never {
  throw new WatchlistRepositoryError('WATCHLIST_STORAGE_INVALID', 'Stored watchlist could not be read safely.');
}

/** Caller owns a dedicated nonprivileged pool and its shutdown lifecycle. */
export class PostgresWatchlistRepository implements WatchlistRepository {
  private readonly allowedAssetIds: WatchlistCatalog;
  private readonly tables: {readonly list: string; readonly receipts: string; readonly lock: string};

  constructor(private readonly pool: Pick<Pool, 'connect'>, options: {
    readonly allowedAssetIds: ReadonlySet<string> | WatchlistCatalog;
    /** Defaults to the sample watchlist, so every existing caller is unchanged. */
    readonly tables?: WatchlistTableSet;
  }) {
    this.allowedAssetIds = watchlistCatalog(options.allowedAssetIds);
    const tables = TABLES[options.tables ?? 'watchlists'];
    if (!tables) {
      throw new WatchlistRepositoryError('WATCHLIST_INVALID_INPUT', 'Watchlist storage target is invalid.');
    }
    this.tables = tables;
  }

  private snapshot(row: SnapshotRow): WatchlistSnapshot {
    if (typeof row.revision !== 'string' || /^[1-9][0-9]{0,15}$/.exec(row.revision)?.[0] !== row.revision) storageInvalid();
    return parseWatchlistSnapshot({revision: Number(row.revision), assetIds: row.asset_ids, updatedAt: row.updated_at}, this.allowedAssetIds);
  }

  private async current(client: PoolClient, userId: string, lock = false): Promise<WatchlistSnapshot> {
    const result = await client.query<SnapshotRow>(
      `SELECT ${columns} FROM trimmy.${this.tables.list} WHERE user_id = $1::uuid${lock ? ' FOR UPDATE' : ''}`, [userId],
    );
    if (result.rows.length > 1) storageInvalid();
    return result.rows[0] ? this.snapshot(result.rows[0]) : EMPTY_WATCHLIST_SNAPSHOT;
  }

  async get(inputUserId: string): Promise<WatchlistSnapshot> {
    const userId = parseWatchlistUserId(inputUserId);
    return this.transaction(userId, true, client => this.current(client, userId));
  }

  async put(inputUserId: string, input: WatchlistWrite): Promise<WatchlistSnapshot> {
    const userId = parseWatchlistUserId(inputUserId);
    // Snapshot mutable caller input before connection acquisition or any await.
    const command = parseWatchlistWrite(input, this.allowedAssetIds);
    const assetJson = JSON.stringify(command.assetIds);
    const hash = createHash('sha256').update(`{"baseRevision":${command.baseRevision},"assetIds":${assetJson}}`).digest('hex');
    return this.transaction(userId, false, async client => {
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1::text, 0))', [`${this.tables.lock}:${userId}`]);
      const receipt = await client.query<SnapshotRow & {request_hash: unknown}>(
        `SELECT request_hash, ${columns} FROM trimmy.${this.tables.receipts}
         WHERE user_id = $1::uuid AND mutation_id = $2::uuid`, [userId, command.mutationId],
      );
      if (receipt.rows.length > 1) storageInvalid();
      if (receipt.rows[0]) {
        if (typeof receipt.rows[0].request_hash !== 'string' || receipt.rows[0].request_hash.length !== 64 ||
            !/^[a-f0-9]{64}$/.test(receipt.rows[0].request_hash)) storageInvalid();
        if (receipt.rows[0].request_hash !== hash) {
          throw new WatchlistRepositoryError('WATCHLIST_IDEMPOTENCY_CONFLICT', 'Mutation ID already belongs to a different request.');
        }
        const original = this.snapshot(receipt.rows[0]);
        if (command.baseRevision === Number.MAX_SAFE_INTEGER || original.revision !== command.baseRevision + 1 ||
            JSON.stringify(original.assetIds) !== assetJson) storageInvalid();
        return original;
      }
      const current = await this.current(client, userId, true);
      if (current.revision !== command.baseRevision) {
        throw new WatchlistRepositoryError('WATCHLIST_REVISION_CONFLICT', 'Watchlist changed. Review the current snapshot.', current);
      }
      if (current.revision === Number.MAX_SAFE_INTEGER) {
        throw new WatchlistRepositoryError('WATCHLIST_REVISION_EXHAUSTED', 'Watchlist revision limit has been reached.');
      }
      const nextRevision = current.revision + 1;
      const saved = current.revision === 0
        ? await client.query<SnapshotRow>(
          `INSERT INTO trimmy.${this.tables.list} (user_id, revision, asset_ids, updated_at)
           VALUES ($1::uuid, 1, $2::jsonb, date_trunc('milliseconds', clock_timestamp()))
           ON CONFLICT (user_id) DO NOTHING RETURNING ${columns}`, [userId, assetJson],
        )
        : await client.query<SnapshotRow>(
          `UPDATE trimmy.${this.tables.list} SET revision = $2, asset_ids = $3::jsonb,
           updated_at = date_trunc('milliseconds', clock_timestamp())
           WHERE user_id = $1::uuid AND revision = $4 RETURNING ${columns}`,
          [userId, nextRevision, assetJson, current.revision],
        );
      if (saved.rows.length === 0) {
        throw new WatchlistRepositoryError('WATCHLIST_REVISION_CONFLICT', 'Watchlist changed. Review the current snapshot.', await this.current(client, userId));
      }
      if (saved.rows.length !== 1) storageInvalid();
      const committed = this.snapshot(saved.rows[0]!);
      if (committed.revision !== nextRevision || JSON.stringify(committed.assetIds) !== assetJson) storageInvalid();
      await client.query(
        `INSERT INTO trimmy.${this.tables.receipts}
         (user_id, mutation_id, request_hash, revision, asset_ids, updated_at)
         VALUES ($1::uuid, $2::uuid, $3, $4, $5::jsonb, $6::timestamptz)`,
        [userId, command.mutationId, hash, committed.revision, assetJson, committed.updatedAt],
      );
      return committed;
    });
  }

  private async transaction<T>(userId: string, readOnly: boolean, run: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.pool.connect();
    let releaseError: Error | undefined;
    try {
      await client.query(readOnly ? 'BEGIN READ ONLY' : 'BEGIN');
      const role = await client.query<{unsafe_role: boolean}>(`
        SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_roles
          WHERE (rolsuper OR rolbypassrls) AND pg_catalog.pg_has_role(current_user, oid, 'MEMBER'))
          OR EXISTS (SELECT 1 FROM pg_catalog.pg_class c
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'trimmy' AND c.relname IN ('users', $1, $2)
              AND pg_catalog.pg_has_role(current_user, c.relowner, 'MEMBER')) AS unsafe_role`,
      [this.tables.list, this.tables.receipts]);
      if (role.rows.length !== 1 || role.rows[0]?.unsafe_role !== false) {
        throw new WatchlistRepositoryError('WATCHLIST_RUNTIME_ROLE_INVALID', 'Watchlist storage requires a dedicated runtime role.');
      }
      await client.query("SELECT set_config('trimmy.practice_user_id', $1, true)", [userId]);
      const account = await client.query<{account_exists: boolean}>('SELECT trimmy.practice_account_exists() AS account_exists');
      if (account.rows.length !== 1 || typeof account.rows[0]?.account_exists !== 'boolean') storageInvalid();
      if (!account.rows[0].account_exists) {
        throw new WatchlistRepositoryError('WATCHLIST_ACCOUNT_NOT_FOUND', 'Watchlist account is unavailable.');
      }
      const result = await run(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      try { await client.query('ROLLBACK'); }
      catch { releaseError = new Error('Watchlist transaction cleanup failed.'); }
      throw error;
    } finally {
      client.release(releaseError);
    }
  }
}
