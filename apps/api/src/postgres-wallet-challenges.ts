import type {Pool, PoolClient} from 'pg';
import {composeWalletPossessionMessage, WalletPossessionError} from './wallet-possession.js';
import type {WalletNetwork, WalletPossessionChallenge, WalletPossessionChallengeStore} from './wallet-possession.js';

interface Row {
  readonly id: unknown;
  readonly user_id: unknown;
  readonly wallet_address: unknown;
  readonly network: unknown;
  readonly provider_wallet_id: unknown;
  readonly nonce: unknown;
  readonly issued_at: unknown;
  readonly expires_at: unknown;
  readonly message: unknown;
}

const COLUMNS = 'id, user_id, wallet_address, network, provider_wallet_id, nonce, issued_at, expires_at, message';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const NETWORKS: readonly WalletNetwork[] = ['mainnet-beta', 'devnet', 'localnet'];
const DEFAULT_OUTSTANDING_LIMIT = 5;

const unavailable = (): never => { throw new WalletPossessionError('WALLET_POSSESSION_STORE_UNAVAILABLE'); };

/**
 * Durable, single-use wallet possession challenges.
 *
 * The in-memory store ties the feature to one process: a proof that reaches a
 * second instance cannot find a challenge that instance never issued, so the
 * wallet check fails rather than merely losing a rate limit. Taking a challenge
 * here is one `DELETE ... RETURNING`, so consumption is atomic across every
 * instance and two concurrent proofs cannot both succeed.
 */
export class PostgresWalletPossessionChallengeStore implements WalletPossessionChallengeStore {
  readonly #pool: Pick<Pool, 'connect'>;
  readonly #outstandingLimit: number;

  constructor(pool: Pick<Pool, 'connect'>, options: {outstandingLimit?: number} = {}) {
    const outstandingLimit = options.outstandingLimit ?? DEFAULT_OUTSTANDING_LIMIT;
    if (typeof pool?.connect !== 'function' ||
        !Number.isInteger(outstandingLimit) || outstandingLimit < 1 || outstandingLimit > 10) {
      throw new WalletPossessionError('WALLET_POSSESSION_CONFIGURATION_INVALID');
    }
    this.#pool = pool;
    this.#outstandingLimit = outstandingLimit;
  }

  async put(challenge: WalletPossessionChallenge): Promise<void> {
    const valid = validate(challenge);
    await this.#scoped(valid.userId, async client => {
      // Serialize issuing per account so the outstanding count is exact rather
      // than racing between instances. The database keeps a higher backstop.
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [valid.userId]);
      const outstanding = await client.query<{total: string}>(
        `SELECT count(*)::text AS total FROM trimmy.wallet_possession_challenges
         WHERE user_id = $1::uuid AND consumed_at IS NULL AND expires_at > now()`,
        [valid.userId]);
      const total = Number(outstanding.rows[0]?.total);
      if (!Number.isInteger(total) || total < 0) return unavailable();
      if (total >= this.#outstandingLimit) throw new WalletPossessionError('WALLET_POSSESSION_RATE_LIMITED');
      const inserted = await client.query(`
        INSERT INTO trimmy.wallet_possession_challenges
          (id, user_id, wallet_address, network, provider_wallet_id, nonce, issued_at, expires_at, message)
        VALUES ($1::uuid, $2::uuid, $3, $4, $5, $6, $7::timestamptz, $8::timestamptz, $9)`,
      [valid.challengeId, valid.userId, valid.walletAddress, valid.network, valid.providerWalletId,
        valid.nonce, valid.issuedAt, valid.expiresAt, valid.message]);
      if (inserted.rowCount !== 1) return unavailable();
    });
  }

  async take(userId: string, challengeId: string): Promise<WalletPossessionChallenge | null> {
    if (typeof userId !== 'string' || !UUID.test(userId) ||
        typeof challengeId !== 'string' || !UUID.test(challengeId)) {
      throw new WalletPossessionError('WALLET_POSSESSION_INPUT_INVALID');
    }
    return this.#scoped(userId, async client => {
      // Marking is the single-use gate: the row lock serializes two writers, so
      // only the update that finds consumed_at still null returns a row. The
      // record of the challenge survives, because the serving role cannot
      // delete anything in this schema.
      const taken = await client.query<Row>(`
        UPDATE trimmy.wallet_possession_challenges SET consumed_at = now()
        WHERE user_id = $1::uuid AND id = $2::uuid AND consumed_at IS NULL
        RETURNING ${COLUMNS}`, [userId, challengeId]);
      if (taken.rowCount === 0) return null;
      if (taken.rowCount !== 1) return unavailable();
      return parseRow(taken.rows[0], userId);
    });
  }

  async #scoped<T>(userId: string, work: (client: PoolClient) => Promise<T>): Promise<T> {
    let client: PoolClient;
    try { client = await this.#pool.connect(); } catch { return unavailable(); }
    try {
      await client.query('BEGIN');
      const role = await client.query<{unsafe_role: boolean}>(`
        SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_roles
          WHERE (rolsuper OR rolbypassrls) AND pg_catalog.pg_has_role(current_user, oid, 'MEMBER'))
          OR EXISTS (SELECT 1 FROM pg_catalog.pg_class c
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'trimmy' AND c.relname IN ('users', 'wallet_possession_challenges')
              AND pg_catalog.pg_has_role(current_user, c.relowner, 'MEMBER')) AS unsafe_role`);
      if (role.rows.length !== 1 || role.rows[0]?.unsafe_role !== false) return unavailable();
      await client.query("SELECT set_config('trimmy.practice_user_id', $1, true)", [userId]);
      const account = await client.query<{account_exists: boolean}>(
        'SELECT trimmy.practice_account_exists() AS account_exists');
      if (account.rows.length !== 1 || account.rows[0]?.account_exists !== true) return unavailable();
      const result = await work(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      try { await client.query('ROLLBACK'); } catch { /* the connection is released below */ }
      throw error instanceof WalletPossessionError ? error : new WalletPossessionError('WALLET_POSSESSION_STORE_UNAVAILABLE');
    } finally {
      client.release();
    }
  }
}

function validate(challenge: WalletPossessionChallenge): WalletPossessionChallenge {
  if (!challenge || typeof challenge !== 'object' ||
      challenge.schemaVersion !== 1 || challenge.kind !== 'wallet_possession_challenge' ||
      typeof challenge.challengeId !== 'string' || !UUID.test(challenge.challengeId) ||
      typeof challenge.userId !== 'string' || !UUID.test(challenge.userId) ||
      typeof challenge.walletAddress !== 'string' ||
      !/^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(challenge.walletAddress) ||
      !NETWORKS.includes(challenge.network) ||
      (challenge.providerWalletId !== null && (typeof challenge.providerWalletId !== 'string' ||
        challenge.providerWalletId.length < 1 || challenge.providerWalletId.length > 200)) ||
      typeof challenge.nonce !== 'string' || !/^[0-9a-f]{64}$/.test(challenge.nonce) ||
      typeof challenge.message !== 'string' || challenge.message.length < 1 || challenge.message.length > 4000 ||
      !instant(challenge.issuedAt) || !instant(challenge.expiresAt) ||
      Date.parse(challenge.expiresAt) <= Date.parse(challenge.issuedAt) ||
      // The stored text must be the text these fields produce, so a row can
      // never present different signed bytes than the fields that scope it.
      composeWalletPossessionMessage(challenge) !== challenge.message) {
    throw new WalletPossessionError('WALLET_POSSESSION_INPUT_INVALID');
  }
  return challenge;
}

function instant(value: unknown): boolean {
  return typeof value === 'string' && value.endsWith('Z') && Number.isFinite(Date.parse(value));
}

function parseRow(row: Row | undefined, userId: string): WalletPossessionChallenge {
  if (!row || typeof row.id !== 'string' || !UUID.test(row.id) || row.user_id !== userId ||
      typeof row.wallet_address !== 'string' || typeof row.nonce !== 'string' ||
      typeof row.message !== 'string' ||
      !NETWORKS.includes(row.network as WalletNetwork) ||
      (row.provider_wallet_id !== null && typeof row.provider_wallet_id !== 'string') ||
      !(row.issued_at instanceof Date) || !Number.isFinite(row.issued_at.getTime()) ||
      !(row.expires_at instanceof Date) || !Number.isFinite(row.expires_at.getTime())) {
    return unavailable();
  }
  const challenge: WalletPossessionChallenge = Object.freeze({
    schemaVersion: 1, kind: 'wallet_possession_challenge',
    challengeId: row.id, userId,
    walletAddress: row.wallet_address, network: row.network as WalletNetwork,
    providerWalletId: (row.provider_wallet_id as string | null) ?? null,
    nonce: row.nonce,
    issuedAt: row.issued_at.toISOString(),
    expiresAt: row.expires_at.toISOString(),
    message: row.message,
  });
  // Re-derive the signed text from the stored fields. A row whose message and
  // fields disagree is refused rather than used to verify a signature.
  if (composeWalletPossessionMessage(challenge) !== challenge.message) return unavailable();
  return challenge;
}
