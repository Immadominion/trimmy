/**
 * Readiness for a hosted instance, as distinct from liveness.
 *
 * `/health` answers whether the process is running, which is the right question
 * for a container restart policy and the wrong one for a load balancer: an
 * instance whose database is unreachable is alive and must not receive traffic.
 *
 * This deliberately checks **only this instance's own storage**. It never calls
 * Privy, Tokens.xyz, Jupiter or any other provider, for two reasons: a probe on
 * a timer would spend a third party's rate limit and money forever, and a
 * degraded provider must not pull an instance out of rotation when every other
 * route still works. Provider state is reported as configuration, never as
 * liveness.
 */

export type ReadinessDatabaseState = 'ok' | 'not_configured' | 'unavailable';

export interface ReadinessReport {
  readonly schemaVersion: 1;
  readonly status: 'ready' | 'not_ready';
  readonly database: ReadinessDatabaseState;
  readonly checkedAt: string;
  /** Configured execution gate, not a claim of provider availability or settlement. */
  readonly financialOperationsEnabled: boolean;
}

/** One bounded round trip to this instance's own storage. Rejects when it fails. */
export interface ReadinessProbe {
  probe(): Promise<void>;
}

const MIN_TTL_MS = 0;
const MAX_TTL_MS = 60_000;
const DEFAULT_TTL_MS = 1_000;

export interface ReadinessReporterOptions {
  readonly probe?: ReadinessProbe;
  /** Report the same gate used by financial routes; this never enables a route. */
  readonly financialOperationsEnabled?: boolean;
  /** How long one answer is reused. Short, so recovery is noticed quickly. */
  readonly ttlMs?: number;
  readonly now?: () => number;
}

export class ReadinessConfigurationError extends Error {
  constructor() { super('Readiness configuration is invalid.'); this.name = 'ReadinessConfigurationError'; }
}

/**
 * Answers readiness without amplifying load onto a database that is already
 * struggling: concurrent probes collapse into one round trip, and both outcomes
 * are cached briefly. Platform routers probe every instance every few seconds,
 * so an uncached probe would turn a partial outage into a self-inflicted one.
 */
export class ReadinessReporter {
  readonly #probe: ReadinessProbe | null;
  readonly #ttlMs: number;
  readonly #now: () => number;
  readonly #financialOperationsEnabled: boolean;
  #cached: {report: ReadinessReport; at: number} | null = null;
  #inFlight: Promise<ReadinessReport> | null = null;

  constructor(options: ReadinessReporterOptions = {}) {
    const ttlMs = options.ttlMs ?? DEFAULT_TTL_MS;
    if (options === null || typeof options !== 'object' ||
        (options.probe !== undefined && typeof options.probe?.probe !== 'function') ||
        (options.now !== undefined && typeof options.now !== 'function') ||
        (options.financialOperationsEnabled !== undefined && typeof options.financialOperationsEnabled !== 'boolean') ||
        !Number.isInteger(ttlMs) || ttlMs < MIN_TTL_MS || ttlMs > MAX_TTL_MS) {
      throw new ReadinessConfigurationError();
    }
    this.#probe = options.probe ?? null;
    this.#ttlMs = ttlMs;
    this.#now = options.now ?? Date.now;
    this.#financialOperationsEnabled = options.financialOperationsEnabled ?? false;
  }

  async report(): Promise<ReadinessReport> {
    const probe = this.#probe;
    // No storage configured is a supported mode: the instance serves the
    // offline practice catalog and nothing it cannot back. Saying "ready" here
    // is honest, and the state field lets an operator see there is no database.
    if (!probe) return this.#build('not_configured');

    const cached = this.#cached;
    if (cached !== null && this.#within(cached.at)) return cached.report;

    const existing = this.#inFlight;
    if (existing !== null) return existing;

    const flight = this.#run(probe).finally(() => {
      if (this.#inFlight === flight) this.#inFlight = null;
    });
    this.#inFlight = flight;
    return flight;
  }

  async #run(probe: ReadinessProbe): Promise<ReadinessReport> {
    let state: ReadinessDatabaseState;
    try {
      await probe.probe();
      state = 'ok';
    } catch {
      // The reason is deliberately dropped: a connection error can carry a host,
      // a user name and occasionally a password, and this body is public.
      state = 'unavailable';
    }
    const report = this.#build(state);
    this.#cached = {report, at: this.#now()};
    return report;
  }

  #within(at: number): boolean {
    const now = this.#now();
    // A clock that moved backwards invalidates the cache rather than pinning it.
    return Number.isFinite(now) && now >= at && now - at < this.#ttlMs;
  }

  #build(database: ReadinessDatabaseState): ReadinessReport {
    const now = this.#now();
    const checkedAt = Number.isFinite(now) ? new Date(now).toISOString() : new Date(0).toISOString();
    return Object.freeze({
      schemaVersion: 1,
      status: database === 'unavailable' ? 'not_ready' : 'ready',
      database,
      checkedAt,
      financialOperationsEnabled: this.#financialOperationsEnabled,
    } as const);
  }
}
