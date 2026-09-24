import type { Pool, PoolClient } from 'pg';
import type { ReviewedStockOrderIntent } from './stock-order-review.js';

/**
 * Durable, account-scoped storage for completed unsigned-order reviews. The row
 * keeps the exact unsigned bytes so a later explicit approval and wallet
 * signature can be bound to that message; it never holds a signature, a key or
 * a submission result. Every call runs as the dedicated runtime role with the
 * account scope set for row-level security, exactly like the practice stores.
 */
export type StockOrderReviewStoreErrorCode =
  | 'REVIEW_STORE_INPUT_INVALID'
  | 'REVIEW_STORE_RUNTIME_ROLE_INVALID'
  | 'REVIEW_STORE_ACCOUNT_NOT_FOUND'
  | 'REVIEW_STORE_DUPLICATE'
  | 'REVIEW_STORE_NOT_FOUND'
  | 'REVIEW_STORE_VERSION_CONFLICT'
  | 'REVIEW_STORE_TRANSITION_INVALID'
  | 'REVIEW_STORE_STORAGE_INVALID';

export class StockOrderReviewStoreError extends Error {
  constructor(readonly code: StockOrderReviewStoreErrorCode) {
    super('The stock order review could not be stored or read.');
    this.name = 'StockOrderReviewStoreError';
  }
}
const fail = (code: StockOrderReviewStoreErrorCode): never => { throw new StockOrderReviewStoreError(code); };

export type StoredStockOrderReviewState = 'reviewed' | 'approved' | 'expired' | 'canceled' | 'consumed';

export interface StoredStockOrderReview {
  readonly id: string;
  readonly userId: string;
  readonly walletBindingId: string | null;
  readonly state: StoredStockOrderReviewState;
  readonly version: number;
  readonly intent: ReviewedStockOrderIntent;
  readonly reviewedAt: string;
  readonly expiresAt: string;
  readonly approvedAt: string | null;
}

export interface StockOrderReviewStore {
  save(input: {readonly intent: ReviewedStockOrderIntent; readonly unsignedTransaction: Uint8Array;
    readonly walletBindingId: string | null}): Promise<StoredStockOrderReview>;
  find(userId: string, reviewId: string): Promise<StoredStockOrderReview | null>;
  /** Approval binds a verified wallet binding of the taker to the review; it enables no signing. */
  approve(input: {readonly userId: string; readonly reviewId: string; readonly expectedVersion: number;
    readonly walletBindingId: string; readonly approvedAt: string}): Promise<StoredStockOrderReview>;
  transition(input: {readonly userId: string; readonly reviewId: string; readonly expectedVersion: number;
    readonly state: 'expired' | 'canceled' | 'consumed'}): Promise<StoredStockOrderReview>;
  /** Returns the exact unsigned bytes of an approved, unexpired review for the signing stage. */
  readApprovedBytes(userId: string, reviewId: string, now: string): Promise<{readonly review: StoredStockOrderReview; readonly bytes: Uint8Array} | null>;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const SHA256 = /^[0-9a-f]{64}$/;
const STATES: readonly StoredStockOrderReviewState[] = ['reviewed', 'approved', 'expired', 'canceled', 'consumed'];

interface Row {
  readonly id: unknown; readonly user_id: unknown; readonly wallet_binding_id: unknown; readonly state: unknown;
  readonly version: unknown; readonly intent: unknown; readonly reviewed_at: unknown; readonly expires_at: unknown;
  readonly approved_at: unknown; readonly unsigned_transaction?: unknown;
}

function isoOf(value: unknown): string {
  if (value instanceof Date && Number.isFinite(value.getTime())) return value.toISOString();
  if (typeof value === 'string' && Number.isFinite(Date.parse(value))) return new Date(value).toISOString();
  return fail('REVIEW_STORE_STORAGE_INVALID');
}

function rowToReview(row: Row): StoredStockOrderReview {
  const intent = row.intent;
  if (typeof row.id !== 'string' || !UUID.test(row.id) || typeof row.user_id !== 'string' || !UUID.test(row.user_id) ||
      (row.wallet_binding_id !== null && (typeof row.wallet_binding_id !== 'string' || !UUID.test(row.wallet_binding_id))) ||
      typeof row.state !== 'string' || !STATES.includes(row.state as StoredStockOrderReviewState) ||
      intent === null || typeof intent !== 'object' || Array.isArray(intent)) {
    return fail('REVIEW_STORE_STORAGE_INVALID');
  }
  const version = typeof row.version === 'string' ? Number(row.version) : row.version;
  if (typeof version !== 'number' || !Number.isSafeInteger(version) || version < 0) return fail('REVIEW_STORE_STORAGE_INVALID');
  const parsed = intent as ReviewedStockOrderIntent;
  if (parsed.kind !== 'reviewed_stock_order_intent' || parsed.userId !== row.user_id ||
      parsed.assessment?.signingEnabled !== false) {
    return fail('REVIEW_STORE_STORAGE_INVALID');
  }
  return Object.freeze({
    id: row.id, userId: row.user_id, walletBindingId: row.wallet_binding_id as string | null,
    state: row.state as StoredStockOrderReviewState, version, intent: parsed,
    reviewedAt: isoOf(row.reviewed_at), expiresAt: isoOf(row.expires_at),
    approvedAt: row.approved_at === null ? null : isoOf(row.approved_at),
  });
}

const SELECT_COLUMNS = 'id, user_id, wallet_binding_id, state, version::text AS version, intent, reviewed_at, expires_at, approved_at';
const CHECK_VIOLATION = '23514';
const UNIQUE_VIOLATION = '23505';
const INSUFFICIENT_PRIVILEGE = '42501';

/**
 * Database guards refuse a write with their own message; the store maps those to
 * its fixed codes so no SQL text, table name or row detail reaches a caller.
 */
async function mapped<T>(run: () => Promise<T>, onRefused: StockOrderReviewStoreErrorCode): Promise<T> {
  try {
    return await run();
  } catch (error) {
    if (error instanceof StockOrderReviewStoreError) throw error;
    const code = (error as {code?: unknown} | null)?.code;
    if (code === CHECK_VIOLATION || code === UNIQUE_VIOLATION || code === INSUFFICIENT_PRIVILEGE) fail(onRefused);
    throw error;
  }
}

export class PostgresStockOrderReviews implements StockOrderReviewStore {
  constructor(private readonly pool: Pick<Pool, 'connect'>) {}

  async save(input: {intent: ReviewedStockOrderIntent; unsignedTransaction: Uint8Array; walletBindingId: string | null}): Promise<StoredStockOrderReview> {
    const intent = input?.intent;
    if (intent?.kind !== 'reviewed_stock_order_intent' || !UUID.test(intent.userId) || !SHA256.test(intent.transactionMessageHash) ||
        !SHA256.test(intent.transactionHash) || !SHA256.test(intent.candidateTermsHash) || !SHA256.test(intent.reviewDigestSha256) ||
        !(input.unsignedTransaction instanceof Uint8Array) || input.unsignedTransaction.byteLength < 64 ||
        input.unsignedTransaction.byteLength > 1_232 || (input.walletBindingId !== null && !UUID.test(input.walletBindingId)) ||
        intent.assessment.signingEnabled !== false) {
      return fail('REVIEW_STORE_INPUT_INVALID');
    }
    return this.transaction(intent.userId, false, async (client) => mapped(async () => {
      const inserted = await client.query<Row>(`
        INSERT INTO trimmy.stock_order_reviews
          (user_id, wallet_binding_id, taker, network, request_id, transaction_message_hash, transaction_hash,
           candidate_terms_hash, review_digest, intent, unsigned_transaction, reviewed_at, expires_at)
        VALUES ($1::uuid, $2::uuid, $3, 'mainnet-beta', $4, $5, $6, $7, $8, $9::jsonb, $10, $11::timestamptz, $12::timestamptz)
        ON CONFLICT (user_id, transaction_message_hash) DO NOTHING
        RETURNING ${SELECT_COLUMNS}`,
      [intent.userId, input.walletBindingId, intent.taker, intent.requestId, intent.transactionMessageHash, intent.transactionHash,
        intent.candidateTermsHash, intent.reviewDigestSha256, JSON.stringify(intent), Buffer.from(input.unsignedTransaction),
        intent.reviewedAt, intent.expiresAt]);
      if (inserted.rows.length === 0) return fail('REVIEW_STORE_DUPLICATE');
      if (inserted.rows.length !== 1) return fail('REVIEW_STORE_STORAGE_INVALID');
      return rowToReview(inserted.rows[0]!);
    }, 'REVIEW_STORE_INPUT_INVALID'));
  }

  async find(userId: string, reviewId: string): Promise<StoredStockOrderReview | null> {
    if (!UUID.test(userId) || !UUID.test(reviewId)) return fail('REVIEW_STORE_INPUT_INVALID');
    return this.transaction(userId, true, async (client) => {
      const result = await client.query<Row>(`SELECT ${SELECT_COLUMNS} FROM trimmy.stock_order_reviews WHERE id = $1::uuid`, [reviewId]);
      if (result.rows.length > 1) return fail('REVIEW_STORE_STORAGE_INVALID');
      return result.rows.length === 0 ? null : rowToReview(result.rows[0]!);
    });
  }

  async approve(input: {userId: string; reviewId: string; expectedVersion: number; walletBindingId: string; approvedAt: string}): Promise<StoredStockOrderReview> {
    if (!UUID.test(input?.userId) || !UUID.test(input.reviewId) || !UUID.test(input.walletBindingId) ||
        !Number.isSafeInteger(input.expectedVersion) || input.expectedVersion < 0 || !Number.isFinite(Date.parse(input.approvedAt))) {
      return fail('REVIEW_STORE_INPUT_INVALID');
    }
    return this.transaction(input.userId, false, async (client) => {
      const current = await this.lock(client, input.reviewId, input.expectedVersion);
      if (current.state !== 'reviewed' || Date.parse(input.approvedAt) >= Date.parse(current.expiresAt)) {
        return fail('REVIEW_STORE_TRANSITION_INVALID');
      }
      const updated = await mapped(() => client.query<Row>(`
        UPDATE trimmy.stock_order_reviews
        SET state = 'approved', version = version + 1, approved_at = $3::timestamptz, wallet_binding_id = $4::uuid
        WHERE id = $1::uuid AND version = $2 AND state = 'reviewed'
          AND (wallet_binding_id IS NULL OR wallet_binding_id = $4::uuid)
        RETURNING ${SELECT_COLUMNS}`,
      [input.reviewId, input.expectedVersion, input.approvedAt, input.walletBindingId]),
      'REVIEW_STORE_TRANSITION_INVALID');
      if (updated.rows.length !== 1) return fail('REVIEW_STORE_TRANSITION_INVALID');
      return rowToReview(updated.rows[0]!);
    });
  }

  async transition(input: {userId: string; reviewId: string; expectedVersion: number; state: 'expired' | 'canceled' | 'consumed'}): Promise<StoredStockOrderReview> {
    if (!UUID.test(input?.userId) || !UUID.test(input.reviewId) || !['expired', 'canceled', 'consumed'].includes(input.state) ||
        !Number.isSafeInteger(input.expectedVersion) || input.expectedVersion < 0) {
      return fail('REVIEW_STORE_INPUT_INVALID');
    }
    return this.transaction(input.userId, false, async (client) => {
      await this.lock(client, input.reviewId, input.expectedVersion);
      const updated = await mapped(() => client.query<Row>(`
        UPDATE trimmy.stock_order_reviews SET state = $3, version = version + 1
        WHERE id = $1::uuid AND version = $2 RETURNING ${SELECT_COLUMNS}`,
      [input.reviewId, input.expectedVersion, input.state]), 'REVIEW_STORE_TRANSITION_INVALID');
      if (updated.rows.length !== 1) return fail('REVIEW_STORE_TRANSITION_INVALID');
      return rowToReview(updated.rows[0]!);
    });
  }

  async readApprovedBytes(userId: string, reviewId: string, now: string): Promise<{review: StoredStockOrderReview; bytes: Uint8Array} | null> {
    if (!UUID.test(userId) || !UUID.test(reviewId) || !Number.isFinite(Date.parse(now))) return fail('REVIEW_STORE_INPUT_INVALID');
    return this.transaction(userId, true, async (client) => {
      const result = await client.query<Row>(`SELECT ${SELECT_COLUMNS}, unsigned_transaction FROM trimmy.stock_order_reviews WHERE id = $1::uuid`, [reviewId]);
      if (result.rows.length > 1) return fail('REVIEW_STORE_STORAGE_INVALID');
      if (result.rows.length === 0) return null;
      const review = rowToReview(result.rows[0]!);
      const raw = result.rows[0]!.unsigned_transaction;
      if (!(raw instanceof Uint8Array) || raw.byteLength < 64 || raw.byteLength > 1_232) return fail('REVIEW_STORE_STORAGE_INVALID');
      if (review.state !== 'approved' || Date.parse(now) >= Date.parse(review.expiresAt)) return null;
      return {review, bytes: Uint8Array.from(raw)};
    });
  }

  private async lock(client: PoolClient, reviewId: string, expectedVersion: number): Promise<StoredStockOrderReview> {
    const result = await client.query<Row>(`SELECT ${SELECT_COLUMNS} FROM trimmy.stock_order_reviews WHERE id = $1::uuid FOR UPDATE`, [reviewId]);
    if (result.rows.length === 0) return fail('REVIEW_STORE_NOT_FOUND');
    if (result.rows.length !== 1) return fail('REVIEW_STORE_STORAGE_INVALID');
    const current = rowToReview(result.rows[0]!);
    if (current.version !== expectedVersion) return fail('REVIEW_STORE_VERSION_CONFLICT');
    return current;
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
            WHERE n.nspname = 'trimmy' AND c.relname IN ('users', 'stock_order_reviews', 'wallet_bindings')
              AND pg_catalog.pg_has_role(current_user, c.relowner, 'MEMBER')) AS unsafe_role`);
      if (role.rows.length !== 1 || role.rows[0]?.unsafe_role !== false) fail('REVIEW_STORE_RUNTIME_ROLE_INVALID');
      await client.query("SELECT set_config('trimmy.practice_user_id', $1, true)", [userId]);
      const account = await client.query<{account_exists: boolean}>('SELECT trimmy.practice_account_exists() AS account_exists');
      if (account.rows.length !== 1 || typeof account.rows[0]?.account_exists !== 'boolean') fail('REVIEW_STORE_STORAGE_INVALID');
      if (!account.rows[0]!.account_exists) fail('REVIEW_STORE_ACCOUNT_NOT_FOUND');
      const outcome = await run(client);
      await client.query('COMMIT');
      return outcome;
    } catch (error) {
      try { await client.query('ROLLBACK'); } catch { releaseError = new Error('Review store transaction cleanup failed.'); }
      throw error;
    } finally {
      client.release(releaseError);
    }
  }
}
