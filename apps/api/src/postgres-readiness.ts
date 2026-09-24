import type {Pool, PoolClient} from 'pg';
import type {ReadinessProbe} from './readiness.js';

/**
 * One bounded `SELECT 1` against the serving pool.
 *
 * Both waits are bounded separately, because they fail differently: acquiring a
 * client can block forever when the pool is exhausted, and a query can hang on
 * a database that accepted the connection and then stopped answering. A query
 * that timed out may still be running, so its connection is destroyed rather
 * than returned to the pool carrying an unfinished statement.
 */
export class PostgresReadinessProbe implements ReadinessProbe {
  readonly #pool: Pool;
  readonly #connectMs: number;
  readonly #queryMs: number;

  constructor(pool: Pool, options: {connectMs?: number; queryMs?: number} = {}) {
    const connectMs = options.connectMs ?? 2_000;
    const queryMs = options.queryMs ?? 2_000;
    if (typeof pool?.connect !== 'function' ||
        !Number.isInteger(connectMs) || connectMs < 1 || connectMs > 30_000 ||
        !Number.isInteger(queryMs) || queryMs < 1 || queryMs > 30_000) {
      throw new Error('Readiness probe configuration is invalid.');
    }
    this.#pool = pool;
    this.#connectMs = connectMs;
    this.#queryMs = queryMs;
  }

  async probe(): Promise<void> {
    const client = await this.#connect();
    let unfinished = true;
    try {
      await bounded(client.query('SELECT 1'), this.#queryMs);
      unfinished = false;
    } finally {
      client.release(unfinished);
    }
  }

  async #connect(): Promise<PoolClient> {
    const pending = this.#pool.connect();
    try {
      return await bounded(pending, this.#connectMs);
    } catch (error) {
      // A client that arrives after the deadline would otherwise be held for the
      // life of the process, so it is destroyed as soon as it appears.
      void pending.then(late => { late.release(true); }, () => {});
      throw error;
    }
  }
}

function bounded<T>(work: Promise<T>, ms: number): Promise<T> {
  let timer: NodeJS.Timeout | undefined;
  const deadline = new Promise<never>((_resolve, reject) => {
    timer = setTimeout(() => reject(new Error('Readiness probe timed out.')), ms);
    // A pending probe must never hold the process open during shutdown.
    timer.unref?.();
  });
  return Promise.race([work, deadline]).finally(() => { if (timer) clearTimeout(timer); });
}
