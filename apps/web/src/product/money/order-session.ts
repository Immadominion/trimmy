/**
 * One live order's lifecycle, ported from mobile's live_order_flow.dart:
 * preview → review → sign the exact reviewed transaction → remember the order
 * id → execute → reconcile. A lost reply after dispatch is reconciled by the
 * order id and never resent. Rendering lives in live-order-panel.tsx.
 */
import {LiveOrderError, uncertainNetwork, type LiveOrder, type LiveOrderClient} from './live-order-client.js';
import {USDC_MINT} from './amounts.js';
import type {TradingAsset, TradingIssuer} from './live-trading.js';
import type {PendingOrderStore} from './stores.js';
import {WalletSignError, type MoneyWallet} from './wallet-controller.js';

export type OrderPhase = 'checking' | 'entry' | 'previewing' | 'reviewed' | 'signing' | 'submitting' |
  'pending' | 'confirmed' | 'failed' | 'expired' | 'recovery-failed' | 'account-changed';
export interface OrderSessionState {
  readonly phase: OrderPhase;
  /** The reviewed or submitted order this screen is about. */
  readonly order: LiveOrder | null;
  /** Person-facing copy for the last problem, if any. */
  readonly notice: string | null;
  readonly noticeCode: string | null;
  /** The last refusal asked for USDC or SOL: offer Add money. */
  readonly fundingNeeded: boolean;
  /** The server wants a fresh eligibility tick (usually new issuer terms). */
  readonly termsRequired: boolean;
}
export interface PreviewRequest {
  readonly asset: TradingAsset; readonly issuer: TradingIssuer; readonly side: 'buy' | 'sell'; readonly amountRaw: string;
  /** Legacy servers list only xStocks and reject the terms field. */
  readonly legacy: boolean;
  /** Spendable USDC (buy) or token units (sell) from a fresh holdings read, or null when unknown. */
  readonly spendable: () => {readonly raw: string | null; readonly fresh: boolean};
}
export interface OrderSessionOptions {
  readonly client: LiveOrderClient; readonly wallet: MoneyWallet; readonly pending: PendingOrderStore;
  readonly now?: () => number; readonly pollMs?: number;
  /** Polling pauses while the page is hidden, as mobile pauses in the background. */
  readonly visible?: () => boolean;
}

/** Refusals the API returns before it dispatches anything; they cannot leave an order in flight. */
const REFUSED_BEFORE_DISPATCH = new Set(['INVALID_REVIEW', 'INVALID_SIGNATURE', 'QUOTE_EXPIRED', 'WALLET_REQUIRED', 'ACCOUNT_REQUIRED']);
const TERMINAL = new Set(['confirmed', 'failed', 'expired']);
const initial: OrderSessionState = Object.freeze({phase: 'checking', order: null, notice: null, noticeCode: null,
  fundingNeeded: false, termsRequired: false});

export class LiveOrderSession {
  readonly #options: OrderSessionOptions; readonly #now: () => number;
  #state: OrderSessionState = initial;
  readonly #listeners = new Set<() => void>();
  #busy = false; #restoring = false; #polling = false; #disposed = false;
  #uncertainId: string | null = null;
  #poll: ReturnType<typeof setTimeout> | null = null; #expiry: ReturnType<typeof setTimeout> | null = null;
  constructor(options: OrderSessionOptions) {this.#options = options; this.#now = options.now ?? Date.now;}

  subscribe = (listener: () => void): (() => void) => {this.#listeners.add(listener); return () => {this.#listeners.delete(listener);};};
  getState = (): OrderSessionState => this.#state;
  get busy(): boolean {return this.#busy;}
  get current(): boolean {return !this.#disposed && this.#options.client.current && this.#options.wallet.current;}

  dispose(): void {
    this.#disposed = true;
    if (this.#poll) clearTimeout(this.#poll);
    if (this.#expiry) clearTimeout(this.#expiry);
    this.#listeners.clear();
  }
  #set(patch: Partial<OrderSessionState>): void {
    if (this.#disposed) return;
    this.#state = Object.freeze({...this.#state, ...patch});
    for (const listener of [...this.#listeners]) listener();
  }
  #guard(): boolean {
    if (this.current) return true;
    this.#stopTimers();
    this.#set({phase: 'account-changed', order: null, notice: 'Sign in again to use your wallet.', noticeCode: 'ACCOUNT_REQUIRED'});
    return false;
  }
  #stopTimers(): void {
    if (this.#poll) {clearTimeout(this.#poll); this.#poll = null;}
    if (this.#expiry) {clearTimeout(this.#expiry); this.#expiry = null;}
  }
  notice(message: string | null, code: string | null = null): void {this.#set({notice: message, noticeCode: code});}

  /** Shows an order as the person should read it: an uncertain reviewed order is still being checked. */
  #display(order: LiveOrder): LiveOrder {
    return order.status === 'reviewed' && this.#uncertainId === order.id ? {...order, status: 'pending'} : order;
  }
  async #settled(order: LiveOrder): Promise<void> {
    this.#options.pending.clear(order.id);
    this.#uncertainId = null;
    if (order.status === 'confirmed') await this.#options.wallet.refreshAfterTrade(order.confirmedSlot).catch(() => {});
  }
  #phaseFor(order: LiveOrder): OrderPhase {
    const shown = this.#display(order).status;
    return shown === 'reviewed' ? 'reviewed' : shown === 'pending' ? 'pending' : shown;
  }

  /** Reads any order whose result is unknown before a new one can start. */
  async restore(): Promise<void> {
    if (this.#restoring || !this.#guard()) return;
    this.#restoring = true; this.#stopTimers();
    this.#set({phase: 'checking', notice: null, noticeCode: null});
    try {
      this.#uncertainId = this.#options.pending.read();
      const order = await this.#options.client.order(this.#uncertainId ?? undefined);
      if (!this.#guard()) return;
      if (order === null && this.#uncertainId !== null) throw new LiveOrderError('ORDER_PENDING');
      if (order && (order.status === 'pending' || this.#uncertainId === order.id)) {
        const shown = this.#display(order);
        this.#set({phase: this.#phaseFor(order), order: shown});
        if (shown.status === 'pending') this.#schedule();
        else await this.#settled(order);
        return;
      }
      this.#set({phase: 'entry', order: null});
    } catch (error) {
      if (this.#guard()) this.#set({phase: 'recovery-failed', notice: null, noticeCode: error instanceof LiveOrderError ? error.code : null});
    } finally {this.#restoring = false;}
  }

  async preview(request: PreviewRequest): Promise<void> {
    if (this.#busy || !this.#guard() || !['entry', 'expired', 'failed'].includes(this.#state.phase)) return;
    const {asset, issuer, side, amountRaw} = request;
    this.#busy = true;
    this.#set({phase: 'previewing', order: null, notice: null, noticeCode: null, fundingNeeded: false, termsRequired: false});
    try {
      await this.#options.wallet.refresh().catch(() => {});
      if (!this.#guard()) return;
      const balance = request.spendable();
      if (balance.fresh && balance.raw !== null && BigInt(amountRaw) > BigInt(balance.raw)) {
        throw new LiveOrderError(side === 'sell' ? 'INSUFFICIENT_HOLDINGS' : 'ADD_USDC');
      }
      const order = await this.#options.client.preview({assetId: asset.assetId, variantMint: asset.mint, side, amountRaw,
        ...(request.legacy ? {} : {termsAccepted: {issuerId: issuer.issuerId, version: issuer.attestation.version}})});
      if (!this.#guard()) return;
      const terms = order.terms;
      if (order.status !== 'reviewed' || terms.side !== side || terms.inputAmountRaw !== amountRaw ||
          terms.inputMint !== (side === 'sell' ? asset.mint : USDC_MINT) || terms.outputMint !== (side === 'sell' ? USDC_MINT : asset.mint)) {
        throw new LiveOrderError('INVALID_REVIEW');
      }
      this.#set({phase: 'reviewed', order});
      this.#watchQuote();
    } catch (error) {
      if (!this.#guard()) return;
      const code = error instanceof LiveOrderError ? error.code : 'PREVIEW_FAILED';
      this.#set({phase: 'entry', fundingNeeded: code === 'ADD_USDC' || code === 'ADD_SOL', termsRequired: code === 'TERMS_REQUIRED',
        notice: error instanceof LiveOrderError && code !== 'NETWORK_UNCERTAIN' && code !== 'NETWORK_TIMEOUT'
          ? error.message : 'Couldn’t get a verified quote. Try again.', noticeCode: code});
      if (code === 'ORDER_PENDING') {this.#busy = false; await this.restore();}
    } finally {this.#busy = false;}
  }

  #watchQuote(): void {
    if (this.#expiry) clearTimeout(this.#expiry);
    const order = this.#state.order;
    if (!order) return;
    const delay = Math.max(0, Date.parse(order.expiresAt) - this.#now());
    this.#expiry = setTimeout(() => this.expireQuote(), Math.min(delay, 2_147_000_000));
  }
  /** A reviewed quote past its expiry can only be refreshed, never confirmed. */
  expireQuote(): void {
    const order = this.#state.order;
    if (!order || this.#state.phase !== 'reviewed' || this.#busy) return;
    if (this.#now() >= Date.parse(order.expiresAt)) this.#set({phase: 'expired', order: {...order, status: 'expired'}});
    // A timer can fire a moment before the clock reaches the deadline: check again then.
    else this.#watchQuote();
  }

  /** Back to the amount, dropping the reviewed quote. */
  edit(): void {
    if (this.#busy || this.#state.phase !== 'reviewed' && this.#state.phase !== 'expired') return;
    this.#stopTimers();
    this.#set({phase: 'entry', order: null, notice: null, noticeCode: null});
  }
  /** After a finished or failed order: a new entry, keeping nothing of the old quote. */
  reset(): void {
    if (this.#busy || !TERMINAL.has(this.#state.phase)) return;
    this.#stopTimers();
    this.#set({phase: 'entry', order: null, notice: null, noticeCode: null, fundingNeeded: false, termsRequired: false});
  }

  async confirm(): Promise<void> {
    const order = this.#state.order;
    if (!order || this.#busy || this.#state.phase !== 'reviewed' || !order.transaction || !this.#guard()) return;
    if (this.#now() >= Date.parse(order.expiresAt)) {this.expireQuote(); return;}
    this.#busy = true;
    this.#set({phase: 'signing', notice: null, noticeCode: null});
    let dispatched = false;
    try {
      const signed = await this.#options.wallet.signReviewedTransaction({wallet: order.wallet, transaction: order.transaction,
        expiresAt: order.expiresAt, route: order.terms.route});
      if (!this.#guard()) return;
      // Remember the id before dispatch: a lost reply can then only be reconciled, never resent.
      if (!this.#options.pending.remember(order.id)) throw new LiveOrderError('STORAGE_REQUIRED');
      this.#uncertainId = order.id;
      dispatched = true;
      this.#set({phase: 'submitting'});
      const result = await this.#options.client.execute({id: order.id, reviewDigest: order.reviewDigest, signedTransaction: signed});
      if (!this.#guard()) return;
      if (result.id !== order.id) throw new LiveOrderError('LIVE_UNAVAILABLE');
      const shown = this.#display(result);
      this.#set({phase: this.#phaseFor(result), order: shown});
      if (shown.status === 'pending') this.#schedule(); else await this.#settled(result);
    } catch (error) {
      if (!this.#guard()) return;
      if (dispatched && error instanceof LiveOrderError && REFUSED_BEFORE_DISPATCH.has(error.code) && !uncertainNetwork(error)) {
        // The API refused this request before sending anything.
        this.#options.pending.clear(order.id); this.#uncertainId = null;
        const expired = error.code === 'QUOTE_EXPIRED';
        this.#set({phase: expired ? 'expired' : 'entry', order: expired ? {...order, status: 'expired'} : null,
          notice: error.message, noticeCode: error.code});
      } else if (dispatched) {
        this.#set({phase: 'pending', order: {...order, status: 'pending'}, notice: 'Checking the result. Your order won’t be sent twice.',
          noticeCode: error instanceof LiveOrderError ? error.code : 'UNKNOWN'});
        this.#schedule();
      } else {
        const code = error instanceof WalletSignError || error instanceof LiveOrderError ? error.code : 'SIGNING_FAILED';
        const expired = code === 'QUOTE_EXPIRED' || this.#now() >= Date.parse(order.expiresAt);
        this.#set({phase: expired ? 'expired' : 'reviewed', order: expired ? {...order, status: 'expired'} : order, noticeCode: code,
          notice: code === 'STORAGE_REQUIRED' ? 'Allow browser storage so Trimmy can keep track of this order. No order was sent.'
            : expired ? 'That price expired. Get a fresh quote. No order was sent.'
            : code === 'ACCOUNT_CHANGED' ? 'Your account changed. No order was sent.'
            : code === 'WALLET_UNAVAILABLE' ? 'Your wallet is still connecting. Try again in a moment. No order was sent.'
            : code === 'WALLET_CHANGED' ? 'Your wallet changed. Get a fresh quote. No order was sent.'
            : code === 'SIGNING_TIMEOUT' ? 'Your wallet didn’t answer in time. No order was sent.'
            : 'Signing didn’t finish. No order was sent.'});
      }
    } finally {this.#busy = false;}
  }

  #schedule(): void {
    if (this.#poll) clearTimeout(this.#poll);
    if (this.#disposed) return;
    this.#poll = setTimeout(() => {this.#poll = null; void this.check();}, this.#options.pollMs ?? 3000);
  }
  /** Call when the page becomes visible again. */
  resume(): void {if (this.#state.phase === 'pending' && !this.#poll) void this.check();}

  async check(): Promise<void> {
    const order = this.#state.order;
    if (this.#polling || this.#state.phase !== 'pending' || !order || !this.#guard()) return;
    if (this.#options.visible && !this.#options.visible()) return;
    this.#polling = true;
    try {
      const result = await this.#options.client.order(order.id);
      if (!this.#guard() || this.#state.order?.id !== order.id) return;
      if (result === null || result.id !== order.id) throw new LiveOrderError('ORDER_PENDING');
      const shown = this.#display(result);
      this.#set({phase: this.#phaseFor(result), order: shown, notice: null, noticeCode: null});
      if (shown.status !== 'pending') await this.#settled(result);
    } catch {
      if (this.#guard()) this.#set({notice: 'Reconnecting to check your order…', noticeCode: 'RECONNECTING'});
    } finally {
      this.#polling = false;
      if (this.#state.phase === 'pending') this.#schedule();
    }
  }
}
