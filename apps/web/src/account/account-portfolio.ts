import {AccountDataClient} from './account-data-client.js';
import {
  AccountDataError,
  type AccountContextSnapshot,
  type AccountDataErrorCode,
  type AccountHoldingsSnapshot,
} from './account-data-models.js';

export type AccountPortfolioPhase =
  | 'idle'
  | 'loading'
  | 'ready'
  | 'stale'
  | 'offline'
  | 'error'
  | 'cancelled'
  | 'accountChanged'
  | 'closed';

export type AccountPortfolioIssue = AccountDataErrorCode
  | 'ACCOUNT_PORTFOLIO_WALLET_CHANGED'
  | 'ACCOUNT_PORTFOLIO_OBSERVATION_EXPIRED'
  | 'ACCOUNT_PORTFOLIO_OBSERVATION_IN_FUTURE';

export interface AccountPortfolioSnapshot {
  readonly subject: string;
  readonly accountId: string;
  readonly walletAddress: string;
  readonly context: AccountContextSnapshot;
  readonly holdings: AccountHoldingsSnapshot;
  readonly acceptedAtMs: number;
  readonly freshUntilMs: number;
}

export interface AccountPortfolioState {
  readonly phase: AccountPortfolioPhase;
  readonly subject: string;
  readonly accountId: string | null;
  readonly walletAddress: string | null;
  readonly context: AccountContextSnapshot | null;
  /** May be retained for explicit stale/offline presentation; never implies readiness. */
  readonly portfolio: AccountPortfolioSnapshot | null;
  readonly issue: AccountPortfolioIssue | null;
}

export interface AccountPortfolioStoreOptions {
  readonly client: AccountDataClient;
  readonly maximumObservationAgeMs?: number;
  readonly maximumFutureSkewMs?: number;
  readonly now?: () => number;
  readonly setTimer?: (callback: () => void, milliseconds: number) => ReturnType<typeof setTimeout>;
  readonly clearTimer?: (timer: ReturnType<typeof setTimeout>) => void;
}

const OFFLINE_CODES = new Set<AccountDataErrorCode>([
  'ACCOUNT_DATA_NETWORK_ERROR', 'ACCOUNT_DATA_TIMEOUT', 'ACCOUNT_CONTEXT_UNAVAILABLE',
  'ACCOUNT_HOLDINGS_UNAVAILABLE', 'PRIVY_LINKED_IDENTITIES_NOT_CONFIGURED',
  'PRIVY_VERIFIED_IDENTITY_INVALID', 'PRIVY_USER_UNAVAILABLE', 'PRIVY_USER_TIMEOUT',
  'PRIVY_USER_RATE_LIMITED', 'STOCK_HOLDINGS_CONFIGURATION_INVALID',
  'STOCK_HOLDINGS_RPC_UNAVAILABLE', 'STOCK_HOLDINGS_RPC_TIMEOUT',
  'STOCK_HOLDINGS_WRONG_NETWORK', 'STOCK_HOLDINGS_RATE_LIMITED',
  'BROWSER_ORIGIN_DENIED', 'BROWSER_PREFLIGHT_DENIED', 'NOT_FOUND', 'INTERNAL_ERROR',
]);

const UNAUTHENTICATED_CODES = new Set<AccountDataErrorCode>([
  'ACCOUNT_DATA_TOKEN_UNAVAILABLE', 'ACCOUNT_CONTEXT_UNAUTHENTICATED', 'ACCOUNT_HOLDINGS_UNAUTHENTICATED',
]);

/**
 * Coordinates context then holdings into one account-and-wallet-bound snapshot.
 * The store retains no token and exposes no financial mutation operation.
 */
export class AccountPortfolioStore {
  readonly subject: string;
  readonly #client: AccountDataClient;
  readonly #maximumObservationAgeMs: number;
  readonly #maximumFutureSkewMs: number;
  readonly #now: () => number;
  readonly #setTimer: NonNullable<AccountPortfolioStoreOptions['setTimer']>;
  readonly #clearTimer: NonNullable<AccountPortfolioStoreOptions['clearTimer']>;
  readonly #listeners = new Set<() => void>();
  #state: AccountPortfolioState;
  #boundAccountId: string | null;
  #boundWalletAddress: string | null = null;
  #generation = 0;
  #active: Promise<void> | null = null;
  #expiryTimer: ReturnType<typeof setTimeout> | null = null;
  #derivedExpiredState: AccountPortfolioState | null = null;
  #closed = false;
  #identityInvalidated = false;

  constructor(options: AccountPortfolioStoreOptions) {
    const age = options.maximumObservationAgeMs ?? 45_000;
    const future = options.maximumFutureSkewMs ?? 5_000;
    if (!Number.isSafeInteger(age) || age < 1 || age > 300_000 ||
        !Number.isSafeInteger(future) || future < 0 || future > 60_000) {
      throw new AccountDataError('ACCOUNT_DATA_INVALID_CONFIGURATION');
    }
    this.#client = options.client;
    this.subject = options.client.subject;
    this.#boundAccountId = options.client.accountId;
    this.#maximumObservationAgeMs = age;
    this.#maximumFutureSkewMs = future;
    this.#now = options.now ?? Date.now;
    this.#setTimer = options.setTimer ?? ((callback, milliseconds) => setTimeout(callback, milliseconds));
    this.#clearTimer = options.clearTimer ?? clearTimeout;
    this.#state = this.#makeState('idle', null, null, null);
  }

  /** Always derives expiry at read time, even if the browser delayed a timer. */
  getSnapshot(): AccountPortfolioState {
    if (this.#derivedExpiredState) return this.#derivedExpiredState;
    if (this.#state.phase === 'ready' && this.#state.portfolio) {
      let now: number;
      try { now = this.#validNow(); }
      catch {
        this.#derivedExpiredState = this.#makeState('error', this.#state.context, this.#state.portfolio,
          'ACCOUNT_DATA_RESPONSE_INVALID');
        return this.#derivedExpiredState;
      }
      if (now >= this.#state.portfolio.freshUntilMs) {
        this.#derivedExpiredState = this.#makeState('stale', this.#state.context, this.#state.portfolio,
          'ACCOUNT_PORTFOLIO_OBSERVATION_EXPIRED');
        return this.#derivedExpiredState;
      }
    }
    return this.#state;
  }

  getReadyPortfolio(): AccountPortfolioSnapshot | null {
    const current = this.getSnapshot();
    return current.phase === 'ready' ? current.portfolio : null;
  }

  subscribe(listener: () => void): () => void {
    if (this.#closed) throw new AccountDataError('ACCOUNT_DATA_CLOSED');
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  }

  /** Concurrent consumers share the exact context-then-holdings read. */
  refresh(): Promise<void> {
    if (this.#closed) return Promise.reject(new AccountDataError('ACCOUNT_DATA_CLOSED'));
    if (this.#identityInvalidated) return Promise.reject(new AccountDataError('ACCOUNT_DATA_ACCOUNT_CHANGED'));
    if (this.#active) return this.#active;
    const generation = ++this.#generation;
    const retained = this.#state.portfolio;
    if (!this.#publish('loading', this.#state.context, retained, null)) return Promise.resolve();
    let operation: Promise<void>;
    operation = this.#runRefresh(generation, retained).finally(() => {
      if (this.#active === operation) this.#active = null;
    });
    this.#active = operation;
    return operation;
  }

  cancelRefresh(): void {
    if (this.#closed || this.#identityInvalidated || !this.#active) return;
    ++this.#generation;
    this.#client.cancelPending();
    this.#active = null;
    this.#publish('cancelled', this.#state.context, this.#state.portfolio, 'ACCOUNT_DATA_CANCELLED');
  }

  /** Marks the current observation unusable without starting a network read. */
  observeConnectivity(online: boolean): void {
    if (this.#closed || this.#identityInvalidated || online) return;
    if (this.#active) {
      ++this.#generation;
      this.#client.cancelPending();
      this.#active = null;
    }
    this.#publish('offline', this.#state.context, this.#state.portfolio, 'ACCOUNT_DATA_NETWORK_ERROR');
  }

  /** The owning auth bridge must call this whenever its current DID changes. */
  observeSubject(activeSubject: string | null): void {
    if (this.#closed || this.#identityInvalidated || activeSubject === this.subject) return;
    this.#client.observeSubject(activeSubject);
    this.#identityInvalidated = true;
    ++this.#generation;
    this.#boundAccountId = null;
    this.#boundWalletAddress = null;
    this.#publish('accountChanged', null, null, 'ACCOUNT_DATA_ACCOUNT_CHANGED');
  }

  close(): void {
    if (this.#closed) return;
    this.#closed = true;
    ++this.#generation;
    this.#clearExpiry();
    this.#client.close();
    this.#boundAccountId = null;
    this.#boundWalletAddress = null;
    this.#state = this.#makeState('closed', null, null, 'ACCOUNT_DATA_CLOSED');
    for (const listener of [...this.#listeners]) { try { listener(); } catch { /* terminal cleanup continues */ } }
    this.#listeners.clear();
  }

  async #runRefresh(generation: number, previous: AccountPortfolioSnapshot | null): Promise<void> {
    let context: AccountContextSnapshot | null = this.#state.context;
    let retained = previous;
    try {
      context = await this.#client.readContext();
      if (!this.#current(generation)) return;
      if (this.#boundAccountId !== null && context.userId !== this.#boundAccountId) {
        this.#invalidateIdentity('ACCOUNT_DATA_ACCOUNT_CHANGED');
        return;
      }
      this.#boundAccountId ??= context.userId;
      const wallet = context.embeddedSolanaWallet;
      if (wallet.status !== 'candidate') {
        if (this.#boundWalletAddress !== null) {
          this.#invalidateIdentity('ACCOUNT_PORTFOLIO_WALLET_CHANGED');
          return;
        }
        this.#publish('error', context, null, wallet.status === 'missing'
          ? 'ACCOUNT_HOLDINGS_WALLET_MISSING' : 'ACCOUNT_HOLDINGS_WALLET_AMBIGUOUS');
        return;
      }
      if (this.#boundWalletAddress !== null && wallet.address !== this.#boundWalletAddress) {
        this.#invalidateIdentity('ACCOUNT_PORTFOLIO_WALLET_CHANGED');
        return;
      }
      this.#boundWalletAddress ??= wallet.address;
      if (retained?.accountId !== context.userId || retained.walletAddress !== wallet.address) retained = null;
      if (!this.#publish('loading', context, retained, null)) return;

      const holdings = await this.#client.readHoldings();
      if (!this.#current(generation)) return;
      if (holdings.userId !== context.userId) {
        this.#invalidateIdentity('ACCOUNT_DATA_ACCOUNT_CHANGED');
        return;
      }
      if (holdings.wallet.address !== wallet.address) {
        this.#invalidateIdentity('ACCOUNT_PORTFOLIO_WALLET_CHANGED');
        return;
      }
      const acceptedAtMs = this.#validNow();
      const observedAtMs = Date.parse(holdings.holdings.observedAt);
      if (observedAtMs > acceptedAtMs + this.#maximumFutureSkewMs) {
        this.#publish('error', context, retained, 'ACCOUNT_PORTFOLIO_OBSERVATION_IN_FUTURE');
        return;
      }
      const freshUntilMs = Math.min(observedAtMs + this.#maximumObservationAgeMs,
        acceptedAtMs + this.#maximumObservationAgeMs);
      if (!Number.isSafeInteger(freshUntilMs) || acceptedAtMs >= freshUntilMs) {
        this.#publish('stale', context, retained, 'ACCOUNT_PORTFOLIO_OBSERVATION_EXPIRED');
        return;
      }
      const portfolio = Object.freeze({subject: this.subject, accountId: context.userId,
        walletAddress: wallet.address, context, holdings, acceptedAtMs, freshUntilMs});
      this.#publish('ready', context, portfolio, null);
    } catch (error) {
      if (!this.#current(generation)) return;
      const issue = error instanceof AccountDataError ? error.code : 'ACCOUNT_DATA_NETWORK_ERROR';
      if (issue === 'ACCOUNT_DATA_ACCOUNT_CHANGED') {
        this.#invalidateIdentity(issue);
      } else if (issue === 'ACCOUNT_DATA_CLOSED') {
        this.#closed = true;
        this.#publish('closed', null, null, issue);
      } else if (UNAUTHENTICATED_CODES.has(issue)) {
        this.#publish('error', null, null, issue);
      } else if (issue === 'ACCOUNT_DATA_CANCELLED') {
        this.#publish('cancelled', context, retained, issue);
      } else {
        this.#publish(OFFLINE_CODES.has(issue) ? 'offline' : 'error', context, retained, issue);
      }
    }
  }

  #validNow(): number {
    let value: number;
    try { value = this.#now(); }
    catch { throw new AccountDataError('ACCOUNT_DATA_RESPONSE_INVALID'); }
    if (!Number.isSafeInteger(value) || value < 0 || value > Number.MAX_SAFE_INTEGER - 360_000) {
      throw new AccountDataError('ACCOUNT_DATA_RESPONSE_INVALID');
    }
    return value;
  }

  #current(generation: number): boolean {
    return !this.#closed && !this.#identityInvalidated && generation === this.#generation;
  }

  #invalidateIdentity(issue: 'ACCOUNT_DATA_ACCOUNT_CHANGED' | 'ACCOUNT_PORTFOLIO_WALLET_CHANGED'): void {
    this.#identityInvalidated = true;
    ++this.#generation;
    this.#client.close();
    this.#boundAccountId = null;
    this.#boundWalletAddress = null;
    this.#publish('accountChanged', null, null, issue);
  }

  #makeState(phase: AccountPortfolioPhase, context: AccountContextSnapshot | null,
    portfolio: AccountPortfolioSnapshot | null, issue: AccountPortfolioIssue | null): AccountPortfolioState {
    return Object.freeze({phase, subject: this.subject, accountId: this.#boundAccountId,
      walletAddress: this.#boundWalletAddress, context, portfolio, issue});
  }

  #publish(phase: AccountPortfolioPhase, context: AccountContextSnapshot | null,
    portfolio: AccountPortfolioSnapshot | null, issue: AccountPortfolioIssue | null): boolean {
    const timerCleared = this.#clearExpiry();
    let usable = timerCleared;
    if (!timerCleared && phase !== 'closed' && phase !== 'accountChanged') {
      phase = 'error';
      issue = 'ACCOUNT_DATA_RESPONSE_INVALID';
    }
    this.#derivedExpiredState = null;
    this.#state = this.#makeState(phase, context, portfolio, issue);
    if (phase === 'ready' && portfolio) {
      try {
        if (!this.#scheduleExpiry(portfolio)) {
          this.#state = this.#makeState('stale', context, portfolio, 'ACCOUNT_PORTFOLIO_OBSERVATION_EXPIRED');
        }
      } catch {
        usable = false;
        this.#state = this.#makeState('error', context, portfolio, 'ACCOUNT_DATA_RESPONSE_INVALID');
      }
    }
    for (const listener of [...this.#listeners]) { try { listener(); } catch { /* subscribers cannot alter state */ } }
    return usable;
  }

  #scheduleExpiry(portfolio: AccountPortfolioSnapshot): boolean {
    const remaining = portfolio.freshUntilMs - this.#validNow();
    if (remaining <= 0) return false;
    let scheduling = true;
    let firedSynchronously = false;
    let timer: ReturnType<typeof setTimeout>;
    try {
      timer = this.#setTimer(() => {
        if (scheduling) { firedSynchronously = true; return; }
        this.#expire(portfolio);
      }, remaining);
    } finally {
      scheduling = false;
    }
    if (firedSynchronously) {
      try { this.#clearTimer(timer!); } catch { /* the state below remains failed closed */ }
      throw new AccountDataError('ACCOUNT_DATA_RESPONSE_INVALID');
    }
    this.#expiryTimer = timer;
    return true;
  }

  #expire(portfolio: AccountPortfolioSnapshot): void {
    this.#expiryTimer = null;
    if (this.#closed || this.#identityInvalidated || this.#state.phase !== 'ready' ||
        this.#state.portfolio !== portfolio) return;
    let now: number;
    try { now = this.#validNow(); }
    catch {
      this.#publish('error', this.#state.context, portfolio, 'ACCOUNT_DATA_RESPONSE_INVALID');
      return;
    }
    if (now < portfolio.freshUntilMs) {
      try {
        if (!this.#scheduleExpiry(portfolio)) {
          this.#publish('stale', this.#state.context, portfolio, 'ACCOUNT_PORTFOLIO_OBSERVATION_EXPIRED');
        }
      } catch { this.#publish('error', this.#state.context, portfolio, 'ACCOUNT_DATA_RESPONSE_INVALID'); }
      return;
    }
    this.#publish('stale', this.#state.context, portfolio, 'ACCOUNT_PORTFOLIO_OBSERVATION_EXPIRED');
  }

  #clearExpiry(): boolean {
    if (this.#expiryTimer === null) return true;
    const timer = this.#expiryTimer;
    this.#expiryTimer = null;
    try { this.#clearTimer(timer); return true; }
    catch { return false; }
  }
}
