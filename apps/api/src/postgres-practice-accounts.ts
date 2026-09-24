import type { Pool } from 'pg';
import { PracticeIdentityError, parsePracticeIdentity } from './practice-identity.js';
import type { PracticeAccount, PracticeAccountRepository, PracticeIdentity } from './practice-identity.js';

/** Inject a dedicated nonprivileged pool; no environment or production fallback. */
export class PostgresPracticeAccounts implements PracticeAccountRepository {
  constructor(private readonly pool: Pick<Pool, 'connect'>) {}

  async find(identity: PracticeIdentity): Promise<PracticeAccount | null> {
    return this.call(identity, false);
  }

  async provision(identity: PracticeIdentity): Promise<PracticeAccount> {
    const account = await this.call(identity, true);
    if (account === null) {
      throw new PracticeIdentityError('PRACTICE_ACCOUNT_UNAVAILABLE', 'Practice account is unavailable.');
    }
    return account;
  }

  private async call(input: PracticeIdentity, provision: boolean): Promise<PracticeAccount | null> {
    const identity = parsePracticeIdentity(input);
    const client = await this.pool.connect();
    let releaseError: Error | undefined;
    try {
      await client.query(provision ? 'BEGIN' : 'BEGIN READ ONLY');
      const role = await client.query<{unsafe_role: boolean}>(`
        SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_roles
          WHERE (rolsuper OR rolbypassrls) AND pg_catalog.pg_has_role(current_user, oid, 'MEMBER'))
          OR EXISTS (SELECT 1 FROM pg_catalog.pg_class c
            JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'trimmy' AND c.relname IN ('users', 'practice_auth_identities')
              AND pg_catalog.pg_has_role(current_user, c.relowner, 'MEMBER')) AS unsafe_role`);
      if (role.rows.length !== 1 || role.rows[0]?.unsafe_role !== false) {
        throw new PracticeIdentityError('PRACTICE_IDENTITY_RUNTIME_ROLE_INVALID', 'Practice identity storage requires a dedicated runtime role.');
      }
      const result = await client.query<{user_id: unknown}>(provision
        ? 'SELECT trimmy.practice_provision_account($1::text, $2::text) AS user_id'
        : 'SELECT trimmy.practice_find_account($1::text, $2::text) AS user_id',
      [identity.appId, identity.subject]);
      const userId = result.rows[0]?.user_id;
      if (result.rows.length !== 1 || (userId !== null &&
          (typeof userId !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(userId)))) {
        throw new PracticeIdentityError('PRACTICE_IDENTITY_STORAGE_INVALID', 'Practice identity mapping could not be read safely.');
      }
      await client.query('COMMIT');
      return userId === null ? null : Object.freeze({userId});
    } catch (error) {
      try { await client.query('ROLLBACK'); } catch {
        releaseError = new Error('Practice identity transaction cleanup failed.');
      }
      throw error;
    } finally {
      client.release(releaseError);
    }
  }
}
