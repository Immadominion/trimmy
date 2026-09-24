import {address, isOffCurveAddress} from '@solana/kit';
import type {Pool, PoolClient} from 'pg';
import {WalletPossessionError} from './wallet-possession.js';
import type {WalletBindingRecord, WalletBindingStore} from './wallet-possession.js';

type BindingInput = Parameters<WalletBindingStore['record']>[0];
interface Row {
  readonly id: unknown;
  readonly user_id: unknown;
  readonly network: unknown;
  readonly address: unknown;
  readonly provider_wallet_id: unknown;
  readonly verified_at: unknown;
}
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const COLUMNS = 'id, user_id, network, address, provider_wallet_id, verified_at';
const unavailable = (): never => { throw new WalletPossessionError('WALLET_POSSESSION_STORE_UNAVAILABLE'); };

function validate(input: BindingInput): void {
  try {
    if (!input || typeof input.userId !== 'string' || !UUID.test(input.userId) ||
        !['mainnet-beta', 'devnet', 'localnet'].includes(input.network) ||
        typeof input.address !== 'string' || isOffCurveAddress(address(input.address)) ||
        input.address === '11111111111111111111111111111111' ||
        (input.providerWalletId !== null && (typeof input.providerWalletId !== 'string' ||
          input.providerWalletId.length < 1 || input.providerWalletId.length > 200)) ||
        typeof input.verifiedAt !== 'string' || !Number.isFinite(Date.parse(input.verifiedAt)) ||
        new Date(input.verifiedAt).toISOString() !== input.verifiedAt) {
      throw new Error('Invalid binding.');
    }
  } catch { throw new WalletPossessionError('WALLET_POSSESSION_INPUT_INVALID'); }
}

function parseRow(row: Row | undefined, input: BindingInput): WalletBindingRecord {
  if (!row || typeof row.id !== 'string' || !UUID.test(row.id) || row.user_id !== input.userId ||
      row.network !== input.network || row.address !== input.address ||
      (row.provider_wallet_id !== null && (typeof row.provider_wallet_id !== 'string' ||
        row.provider_wallet_id.length < 1 || row.provider_wallet_id.length > 200)) ||
      !(row.verified_at instanceof Date) || !Number.isFinite(row.verified_at.getTime())) return unavailable();
  return Object.freeze({id: row.id, userId: input.userId, network: input.network, address: input.address,
    providerWalletId: row.provider_wallet_id as string | null, verifiedAt: row.verified_at.toISOString()});
}

/** Durable bindings only. This repository holds no wallet key or transaction. */
export class PostgresWalletBindingStore implements WalletBindingStore {
  constructor(private readonly pool: Pick<Pool, 'connect'>) {}

  async record(input: BindingInput): Promise<WalletBindingRecord> {
    validate(input);
    let client: PoolClient;
    try { client = await this.pool.connect(); } catch { return unavailable(); }
    let releaseError: Error | undefined;
    try {
      await client.query('BEGIN');
      const role = await client.query<{unsafe_role: boolean}>(`
        SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_roles
          WHERE (rolsuper OR rolbypassrls) AND pg_catalog.pg_has_role(current_user, oid, 'MEMBER'))
          OR EXISTS (SELECT 1 FROM pg_catalog.pg_class c
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'trimmy' AND c.relname IN ('users', 'wallet_bindings')
              AND pg_catalog.pg_has_role(current_user, c.relowner, 'MEMBER')) AS unsafe_role`);
      if (role.rows.length !== 1 || role.rows[0]?.unsafe_role !== false) return unavailable();
      await client.query("SELECT set_config('trimmy.practice_user_id', $1, true)", [input.userId]);
      const account = await client.query<{account_exists: boolean}>(
        'SELECT trimmy.practice_account_exists() AS account_exists');
      if (account.rows.length !== 1 || account.rows[0]?.account_exists !== true) return unavailable();

      // A concurrent proof may already have inserted this wallet. DO NOTHING
      // avoids aborting the transaction; a second read sees its committed row.
      // RLS hides another owner's row and revoked bindings are never resurrected.
      const inserted = await client.query<Row>(`
        INSERT INTO trimmy.wallet_bindings (user_id, network, address, provider_wallet_id, verified_at)
        VALUES ($1::uuid, $2, $3, $4, $5::timestamptz)
        ON CONFLICT (network, address) DO NOTHING RETURNING ${COLUMNS}`,
      [input.userId, input.network, input.address, input.providerWalletId, input.verifiedAt]);
      if (inserted.rows.length > 1) return unavailable();
      let row = inserted.rows[0];
      if (!row) {
        const existing = await client.query<Row>(`
          SELECT ${COLUMNS} FROM trimmy.wallet_bindings
          WHERE user_id = $1::uuid AND network = $2 AND address = $3 AND revoked_at IS NULL`,
        [input.userId, input.network, input.address]);
        if (existing.rows.length !== 1) return unavailable();
        row = existing.rows[0];
      }
      const result = parseRow(row, input);
      await client.query('COMMIT');
      return result;
    } catch {
      try { await client.query('ROLLBACK'); }
      catch { releaseError = new Error('Wallet binding transaction cleanup failed.'); }
      return unavailable();
    } finally { client.release(releaseError); }
  }
}
