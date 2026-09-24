/**
 * Process-local protection for an outbound provider read. Cache and budget keys
 * must already be validated, bounded identifiers. Values are cached only after
 * the caller has projected and sanitized the provider response.
 */
export interface BoundedProviderReadConfiguration {
  readonly now: () => number;
  readonly cacheTtlMs: number;
  readonly rateLimitWindowMs: number;
  readonly perKeyLimit: number;
  readonly globalLimit: number;
  readonly maxTrackedKeys: number;
  readonly maxCacheEntries: number;
  readonly maxConcurrentReads: number;
}

interface BoundedProviderReadErrors {
  readonly configurationInvalid: () => Error;
  readonly rateLimited: () => Error;
}

interface CacheEntry<T> {
  readonly expiresAt: number;
  readonly value: T;
}

interface BudgetEntry {
  readonly windowStartedAt: number;
  count: number;
}

const positiveInteger = (value: number, maximum: number): boolean =>
  Number.isSafeInteger(value) && value > 0 && value <= maximum;

/**
 * Fixed-window budgets count admitted upstream attempts, including attempts
 * that later fail. Cache hits and callers joining an existing singleflight do
 * not create another provider attempt and therefore do not consume a unit.
 */
export class BoundedProviderRead<T> {
  readonly #configuration: BoundedProviderReadConfiguration;
  readonly #errors: BoundedProviderReadErrors;
  readonly #cache = new Map<string, CacheEntry<T>>();
  readonly #budgets = new Map<string, BudgetEntry>();
  readonly #inflight = new Map<string, Promise<T>>();
  // Superseded requests still consume capacity until they settle, even though
  // future callers must join only the newest request for their cache key.
  readonly #pending = new Set<Promise<T>>();
  #globalWindowStartedAt: number | undefined;
  #globalCount = 0;
  #lastTimestamp = 0;

  constructor(configuration: BoundedProviderReadConfiguration, errors: BoundedProviderReadErrors) {
    const invalid = errors !== null && typeof errors === 'object' &&
      typeof errors.configurationInvalid === 'function'
      ? errors.configurationInvalid : () => new Error('Provider read protection is not configured correctly.');
    if (configuration === null || typeof configuration !== 'object' ||
        typeof configuration.now !== 'function' ||
        !positiveInteger(configuration.cacheTtlMs, 60_000) ||
        !positiveInteger(configuration.rateLimitWindowMs, 3_600_000) ||
        !positiveInteger(configuration.perKeyLimit, 10_000) ||
        !positiveInteger(configuration.globalLimit, 1_000_000) ||
        !positiveInteger(configuration.maxTrackedKeys, 100_000) ||
        !positiveInteger(configuration.maxCacheEntries, 100_000) ||
        !positiveInteger(configuration.maxConcurrentReads, 1_000) ||
        errors === null || typeof errors !== 'object' ||
        typeof errors.configurationInvalid !== 'function' || typeof errors.rateLimited !== 'function') {
      throw invalid();
    }
    this.#configuration = Object.freeze({...configuration});
    this.#errors = Object.freeze({...errors});
  }

  #configurationInvalid(): never {
    throw this.#errors.configurationInvalid();
  }

  #rateLimited(): never {
    throw this.#errors.rateLimited();
  }

  #timestamp(): number {
    let value: number;
    try { value = this.#configuration.now(); }
    catch { return this.#configurationInvalid(); }
    if (!Number.isSafeInteger(value) || value < 0 || value > 8_639_999_999_999_999) {
      return this.#configurationInvalid();
    }
    // A wall-clock correction must not revive expired cache entries or reset a
    // budget. Clamp it until the clock catches up.
    if (value < this.#lastTimestamp) return this.#lastTimestamp;
    this.#lastTimestamp = value;
    return value;
  }

  #prune(timestamp: number): void {
    for (const [key, entry] of this.#cache) {
      if (entry.expiresAt <= timestamp) this.#cache.delete(key);
    }
    for (const [key, entry] of this.#budgets) {
      if (timestamp - entry.windowStartedAt >= this.#configuration.rateLimitWindowMs) {
        this.#budgets.delete(key);
      }
    }
    if (this.#globalWindowStartedAt === undefined ||
        timestamp - this.#globalWindowStartedAt >= this.#configuration.rateLimitWindowMs) {
      this.#globalWindowStartedAt = timestamp;
      this.#globalCount = 0;
    }
  }

  #admit(key: string, timestamp: number): void {
    if (this.#pending.size >= this.#configuration.maxConcurrentReads) return this.#rateLimited();
    let budget = this.#budgets.get(key);
    if (!budget && this.#budgets.size >= this.#configuration.maxTrackedKeys) return this.#rateLimited();
    if (budget && budget.count >= this.#configuration.perKeyLimit ||
        this.#globalCount >= this.#configuration.globalLimit) return this.#rateLimited();
    if (!budget) {
      budget = {windowStartedAt: timestamp, count: 0};
      this.#budgets.set(key, budget);
    }
    budget.count += 1;
    this.#globalCount += 1;
  }

  #cacheValue(key: string, value: T, timestamp: number): void {
    this.#cache.delete(key);
    while (this.#cache.size >= this.#configuration.maxCacheEntries) {
      const oldest = this.#cache.keys().next().value as string | undefined;
      if (oldest === undefined) return this.#configurationInvalid();
      this.#cache.delete(oldest);
    }
    this.#cache.set(key, {expiresAt: timestamp + this.#configuration.cacheTtlMs, value});
  }

  async read(cacheKey: string, budgetKey: string,
    load: (admittedAt: number) => Promise<T>): Promise<T> {
    if (typeof cacheKey !== 'string' || cacheKey.length === 0 || cacheKey.length > 256 ||
        typeof budgetKey !== 'string' || budgetKey.length === 0 || budgetKey.length > 256 ||
        typeof load !== 'function') return this.#configurationInvalid();
    const timestamp = this.#timestamp();
    this.#prune(timestamp);
    const cached = this.#cache.get(cacheKey);
    if (cached) {
      // Refresh insertion order for bounded least-recently-used eviction. The
      // absolute expiry is deliberately unchanged.
      this.#cache.delete(cacheKey);
      this.#cache.set(cacheKey, cached);
      return cached.value;
    }
    const existing = this.#inflight.get(cacheKey);
    if (existing) return existing;
    this.#admit(budgetKey, timestamp);
    return this.#start(cacheKey, timestamp, load);
  }

  #start(cacheKey: string, timestamp: number, load: (admittedAt: number) => Promise<T>): Promise<T> {
    // The first await yields before this promise is compared or cleaned up.
    let pending!: Promise<T>;
    pending = (async () => {
      const value = await load(timestamp);
      // A fresh request supersedes every earlier snapshot for this key. An old
      // response can finish its own caller, but may never refill the cache.
      if (this.#inflight.get(cacheKey) === pending) this.#cacheValue(cacheKey, value, this.#timestamp());
      return value;
    })().finally(() => {
      this.#pending.delete(pending);
      if (this.#inflight.get(cacheKey) === pending) this.#inflight.delete(cacheKey);
    });
    this.#inflight.set(cacheKey, pending);
    this.#pending.add(pending);
    return pending;
  }

  /** Authorization-sensitive reads cannot reuse a cached value or an earlier
   * in-flight snapshot. They replace the normal join target and populate its
   * sanitized cache so subsequent account/holdings reads see the fresh link.
   * Each attempt still shares all rate/concurrency limits. */
  async readFresh(cacheKey: string, budgetKey: string, load: (admittedAt: number) => Promise<T>): Promise<T> {
    if (typeof cacheKey !== 'string' || cacheKey.length === 0 || cacheKey.length > 256 ||
        typeof budgetKey !== 'string' || budgetKey.length === 0 || budgetKey.length > 256 ||
        typeof load !== 'function') return this.#configurationInvalid();
    const timestamp = this.#timestamp();
    this.#prune(timestamp);
    this.#admit(budgetKey, timestamp);
    this.#cache.delete(cacheKey);
    return this.#start(cacheKey, timestamp, load);
  }
}
