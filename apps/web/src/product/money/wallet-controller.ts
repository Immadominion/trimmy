/**
 * One verified account's own-money wallet: the server's link to its Privy
 * embedded Solana wallet, holdings v2, explicit wallet setup, and the one
 * signing step. Every asynchronous boundary re-checks the account identity,
 * as mobile's account_controller.dart and privy_auth.dart do.
 */
import {AccountDataError} from '../../account/account-data-models.js';
import type {ProductAccountAccess} from '../product-auth.js';
import {checkSignedTransaction, planSigning, TransactionCheckError} from './solana-wire.js';
import type {AccountWalletClient} from './wallet-client.js';
import {holdingsSlots, type AccountContextSnapshot, type HoldingsSnapshot} from './wallet-models.js';
import type {EmbeddedSolanaSnapshot} from './wallet-sdk-loader.js';

export type WalletPhase = 'idle' | 'loading' | 'ready' | 'stale' | 'offline' | 'error' | 'closed';
export type WalletIssue = 'wallet-missing' | 'wallet-ambiguous' | 'wallet-changed' | 'unauthenticated' | 'observation-expired' |
  'unavailable' | 'invalid-response' | 'closed' | null;
export interface WalletState {
  readonly phase: WalletPhase; readonly issue: WalletIssue;
  /** The latest context the server returned for this account. */
  readonly context: AccountContextSnapshot | null;
  /** Holdings for the context's wallet; retained (and marked stale) when a later read fails. */
  readonly holdings: HoldingsSnapshot | null;
  readonly freshUntil: number | null;
  /** At least one read has finished, successfully or not. */
  readonly checked: boolean;
  readonly setupBusy: boolean;
  readonly signing: boolean;
}
export type WalletSetupOutcome = 'ready' | 'awaiting-server' | 'unavailable' | 'account-changed';
export class WalletSignError extends Error {
  constructor(readonly code: 'ACCOUNT_CHANGED' | 'QUOTE_EXPIRED' | 'WALLET_UNAVAILABLE' | 'WALLET_CHANGED' | 'WALLET_BUSY' |
    'SIGNING_CANCELLED' | 'SIGNING_TIMEOUT' | 'INVALID_TRANSACTION' | 'SIGNATURE_MISMATCH') {super(code); this.name = 'WalletSignError';}
}
class SetupError extends Error {constructor(readonly outcome: WalletSetupOutcome) {super(outcome);}}

const OBSERVATION_AGE_MS = 45_000, FUTURE_SKEW_MS = 5_000;
const initial: WalletState = Object.freeze({phase: 'idle', issue: null, context: null, holdings: null, freshUntil: null,
  checked: false, setupBusy: false, signing: false});

/** Holdings only when they belong to the wallet the server links to this account. */
export function coherentHoldings(state: WalletState): HoldingsSnapshot | null {
  const wallet = state.context?.embeddedSolanaWallet;
  return state.holdings && wallet?.status === 'candidate' && state.holdings.walletAddress === wallet.address ? state.holdings : null;
}
export function walletAddress(state: WalletState): string | null {
  const wallet = state.context?.embeddedSolanaWallet;
  return wallet?.status === 'candidate' ? wallet.address : null;
}

export interface MoneyWalletOptions {
  readonly access: ProductAccountAccess;
  readonly client: AccountWalletClient;
  /** The latest Privy snapshot, or null while the SDK is not mounted. */
  readonly embedded: () => EmbeddedSolanaSnapshot | null;
  readonly now?: () => number;
  readonly signingTimeoutMs?: number;
  readonly setupTimeoutMs?: number;
}

export class MoneyWallet {
  readonly #options: MoneyWalletOptions; readonly #now: () => number;
  #state: WalletState = initial;
  readonly #listeners = new Set<() => void>();
  #inFlight: Promise<void> | null = null; #queued: Promise<void> | null = null;
  #generation = 0; #slotFloor = 0; #closed = false; #sdkBusy = false;
  constructor(options: MoneyWalletOptions) {this.#options = options; this.#now = options.now ?? Date.now;}

  get state(): WalletState {return this.#state;}
  subscribe = (listener: () => void): (() => void) => {this.#listeners.add(listener); return () => {this.#listeners.delete(listener);};};
  getState = (): WalletState => this.#state;
  get current(): boolean {return !this.#closed && !this.#options.access.signal.aborted;}
  /** Fresh only while ready, inside the observation window, and past any confirmed trade's slot. */
  fresh(at = this.#now()): boolean {
    const state = this.#state;
    return state.phase === 'ready' && state.freshUntil !== null && at < state.freshUntil &&
      (state.holdings === null || this.#observesFloor(state.holdings));
  }
  get canSetUpWallet(): boolean {
    const embedded = this.#options.embedded();
    return this.current && !this.#state.setupBusy && !this.#sdkBusy && embedded?.ready === true &&
      embedded.subject === this.#options.access.subject;
  }

  close(): void {
    if (this.#closed) return;
    this.#closed = true; this.#generation++;
    this.#publish({...initial, phase: 'closed', issue: 'closed'});
    this.#listeners.clear();
  }

  #publish(next: WalletState): void {
    if (this.#closed && next.phase !== 'closed') return;
    this.#state = Object.freeze(next);
    for (const listener of [...this.#listeners]) listener();
  }
  #patch(patch: Partial<WalletState>): void {this.#publish({...this.#state, ...patch});}
  #observesFloor(holdings: HoldingsSnapshot): boolean {return holdingsSlots(holdings).every(slot => slot >= this.#slotFloor);}

  /** Concurrent refreshes share one context-then-holdings read. */
  refresh(): Promise<void> {
    if (!this.current) return Promise.resolve();
    if (this.#inFlight) return this.#inFlight;
    const generation = ++this.#generation;
    const run = this.#read(generation).finally(() => {if (this.#inFlight === run) this.#inFlight = null;});
    this.#inFlight = run;
    return run;
  }

  /** A confirmation never reuses a read begun before it; later reads keep the slot floor. */
  refreshAfterTrade(confirmedSlot: number | null): Promise<void> {
    if (confirmedSlot !== null && Number.isSafeInteger(confirmedSlot) && confirmedSlot > this.#slotFloor) {
      this.#slotFloor = confirmedSlot;
      if (this.#state.holdings && !this.#observesFloor(this.#state.holdings) && this.#state.phase === 'ready') {
        this.#patch({phase: 'stale', issue: 'observation-expired'});
      }
    }
    if (this.#queued) return this.#queued;
    const previous = this.#inFlight;
    const queued: Promise<void> = (previous ? previous.catch(() => {}) : Promise.resolve()).then(() => {
      if (this.#queued === queued) this.#queued = null;
      return this.refresh();
    });
    this.#queued = queued;
    return queued;
  }

  async #read(generation: number): Promise<void> {
    const live = () => this.current && generation === this.#generation;
    let context = this.#state.context, retained = this.#state.holdings;
    this.#patch({phase: 'loading'});
    try {
      context = await this.#options.client.readContext({signal: this.#options.access.signal});
      if (!live()) return;
      const wallet = context.embeddedSolanaWallet;
      if (wallet.status !== 'candidate') {
        this.#publish({...this.#state, phase: 'error', issue: wallet.status === 'missing' ? 'wallet-missing' : 'wallet-ambiguous',
          context, holdings: null, freshUntil: null, checked: true});
        return;
      }
      if (retained?.walletAddress !== wallet.address) retained = null;
      this.#publish({...this.#state, phase: 'loading', context, holdings: retained});
      const holdings = await this.#options.client.readHoldings({minimumObservedSlot: this.#slotFloor || null, signal: this.#options.access.signal});
      if (!live()) return;
      if (holdings.walletAddress !== wallet.address) {retained = null; throw new WalletReadIssue('wallet-changed');}
      if (!this.#observesFloor(holdings)) throw new WalletReadIssue('observation-expired');
      const acceptedAt = this.#now(), observed = Date.parse(holdings.observedAt);
      if (observed > acceptedAt + FUTURE_SKEW_MS) throw new WalletReadIssue('invalid-response');
      const freshUntil = Math.min(observed + OBSERVATION_AGE_MS, acceptedAt + OBSERVATION_AGE_MS);
      if (acceptedAt >= freshUntil) throw new WalletReadIssue('observation-expired');
      this.#publish({...this.#state, phase: 'ready', issue: null, context, holdings, freshUntil, checked: true});
    } catch (error) {
      if (!live()) return;
      const issue: WalletIssue = error instanceof WalletReadIssue ? error.issue : error instanceof AccountDataError
        ? error.code === 'ACCOUNT_DATA_ACCOUNT_CHANGED' ? 'closed'
          : /UNAUTHENTICATED|TOKEN_UNAVAILABLE/.test(error.code) ? 'unauthenticated'
          : error.code === 'ACCOUNT_HOLDINGS_WALLET_MISSING' ? 'wallet-missing'
          : error.code === 'ACCOUNT_HOLDINGS_WALLET_AMBIGUOUS' ? 'wallet-ambiguous'
          : error.code === 'ACCOUNT_DATA_RESPONSE_INVALID' ? 'invalid-response' : 'unavailable' : 'unavailable';
      if (issue === 'closed') {this.close(); return;}
      const clear = issue === 'unauthenticated';
      const offline = issue === 'unavailable';
      this.#publish({...this.#state, phase: issue === 'observation-expired' ? 'stale' : offline ? 'offline' : 'error', issue,
        context: clear ? null : context, holdings: clear ? null : retained, checked: true});
    }
  }

  /**
   * The person's explicit "Create wallet". Privy ensures exactly one embedded
   * Solana wallet; the server must then independently report that address as
   * this account's wallet before the app treats it as the account's wallet.
   */
  async setUpWallet(): Promise<WalletSetupOutcome> {
    if (!this.canSetUpWallet) return 'unavailable';
    const {access} = this.#options, subject = access.subject;
    const current = () => this.current && this.#options.embedded()?.subject === subject;
    this.#sdkBusy = true; this.#patch({setupBusy: true});
    let providerMayHaveRun = false;
    try {
      // A fresh bearer comes before the provider mutation; a cached session alone is not enough.
      if (await access.freshAccessToken() === null || !current()) return 'account-changed';
      providerMayHaveRun = true;
      const address = await this.#withTimeout(this.#ensureSolanaWallet(subject), this.#options.setupTimeoutMs ?? 30_000, () => new SetupError('awaiting-server'));
      if (!current()) return 'account-changed';
      const context = await this.#options.client.readContext({fresh: true, signal: access.signal});
      if (!current()) return 'account-changed';
      if (context.embeddedSolanaWallet.status !== 'candidate' || context.embeddedSolanaWallet.address !== address) return 'awaiting-server';
      // An older cached read must not overwrite setup with its "missing wallet" observation.
      this.#generation++; this.#inFlight = null;
      await this.refresh();
      if (!current()) return 'account-changed';
      return walletAddress(this.#state) === address ? 'ready' : 'awaiting-server';
    } catch (error) {
      if (error instanceof SetupError) return error.outcome;
      return !current() ? 'account-changed' : providerMayHaveRun ? 'awaiting-server' : 'unavailable';
    } finally {
      this.#sdkBusy = false;
      if (!this.#closed) this.#patch({setupBusy: false});
    }
  }

  async #ensureSolanaWallet(subject: string): Promise<string> {
    const read = () => {
      const snapshot = this.#options.embedded();
      if (!snapshot?.ready || snapshot.subject !== subject) throw new SetupError('account-changed');
      return snapshot;
    };
    // Refresh before deciding to create: a lost reply may already have created it, or another device did.
    const refreshed = await read().refreshUser();
    if (refreshed.subject !== subject || read().subject !== subject) throw new SetupError('account-changed');
    if (refreshed.wallets === null || refreshed.wallets.length > 1) throw new SetupError('unavailable');
    const address = refreshed.wallets[0]?.address ?? await read().createWallet();
    const after = await read().refreshUser();
    if (after.subject !== subject || after.wallets?.length !== 1 || after.wallets[0]?.address !== address) throw new SetupError('unavailable');
    return address;
  }

  /**
   * Signs the exact reviewed transaction with the matching embedded wallet. The
   * quote must still be valid before and after, the account and wallet must be
   * unchanged across the wallet call, and the result must fill only the user's
   * signer slot of the same message (an RFQ maker's slot stays empty).
   */
  async signReviewedTransaction(input: {readonly wallet: string; readonly transaction: string; readonly expiresAt: string;
    readonly route: 'aggregator' | 'rfq' | null}): Promise<string> {
    const {access} = this.#options, subject = access.subject;
    const expires = Date.parse(input.expiresAt);
    if (!this.current || !Number.isFinite(expires)) throw new WalletSignError('ACCOUNT_CHANGED');
    if (this.#now() >= expires) throw new WalletSignError('QUOTE_EXPIRED');
    if (this.#sdkBusy) throw new WalletSignError('WALLET_BUSY');
    const linked = walletAddress(this.#state);
    if (linked !== null && linked !== input.wallet) throw new WalletSignError('WALLET_CHANGED');
    let plan;
    try {plan = planSigning(input.transaction, input.wallet, input.route);}
    catch (error) {throw new WalletSignError(error instanceof TransactionCheckError && error.code === 'WALLET_NOT_SIGNER' ? 'WALLET_CHANGED' : 'INVALID_TRANSACTION');}
    this.#sdkBusy = true; this.#patch({signing: true});
    let settled = true;
    try {
      if (await access.freshAccessToken() === null || !this.current) throw new WalletSignError('ACCOUNT_CHANGED');
      const matching = (): EmbeddedSolanaSnapshot => {
        const snapshot = this.#options.embedded();
        if (!snapshot?.ready || snapshot.subject !== subject || !this.current) throw new WalletSignError('ACCOUNT_CHANGED');
        if (snapshot.wallets?.length !== 1 || snapshot.wallets[0]?.address !== input.wallet) throw new WalletSignError('WALLET_CHANGED');
        return snapshot;
      };
      const before = matching();
      if (!before.signable.includes(input.wallet)) throw new WalletSignError('WALLET_UNAVAILABLE');
      settled = false;
      const request = before.signTransaction(input.wallet, plan.bytes.slice());
      // A caller's timeout does not cancel the wallet request: stay locked until it settles.
      void request.then(() => {}, () => {}).finally(() => {settled = true; this.#sdkBusy = false; if (!this.#closed) this.#patch({signing: false});});
      let signed: Uint8Array;
      try {signed = await this.#withTimeout(request, this.#options.signingTimeoutMs ?? 45_000, () => new WalletSignError('SIGNING_TIMEOUT'));}
      catch (error) {throw error instanceof WalletSignError ? error : new WalletSignError('SIGNING_CANCELLED');}
      matching();
      let encoded: string;
      try {encoded = await checkSignedTransaction(plan, signed, input.wallet);}
      catch {throw new WalletSignError('SIGNATURE_MISMATCH');}
      if (!this.current) throw new WalletSignError('ACCOUNT_CHANGED');
      if (this.#now() >= expires) throw new WalletSignError('QUOTE_EXPIRED');
      return encoded;
    } finally {
      if (settled) {this.#sdkBusy = false; if (!this.#closed) this.#patch({signing: false});}
    }
  }

  #withTimeout<T>(work: Promise<T>, ms: number, error: () => Error): Promise<T> {
    let timer: ReturnType<typeof setTimeout> | undefined;
    return Promise.race([work, new Promise<never>((_, reject) => {timer = setTimeout(() => reject(error()), ms);})])
      .finally(() => clearTimeout(timer));
  }
}
class WalletReadIssue extends Error {constructor(readonly issue: Exclude<WalletIssue, null>) {super(issue);}}
