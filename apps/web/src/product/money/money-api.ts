/**
 * The money API every screen reads: `useMoney()`. It is the entry point for
 * other features (for example a first-day "fund wallet" step calls
 * `useMoney().openFundWallet()`). Guests get a Paper-only value.
 */
import {createContext, useContext} from 'react';
import type {LiveOrderClient} from './live-order-client.js';
import type {TradingCapabilities} from './live-trading.js';
import type {LiveOrderSession} from './order-session.js';
import type {IssuerTermsStore} from './stores.js';
import type {WalletSetupOutcome, WalletState} from './wallet-controller.js';
import type {TransferReview, WalletTransferClient} from './wallet-transfer-client.js';

/** Sending money out of the account's wallet (wallet-transfer-client.ts). */
export interface TransferPort {
  preview(input: {readonly asset: string; readonly destination: string; readonly amountRaw: string}): Promise<TransferReview>;
  /** Signs exactly the reviewed transfer with the embedded wallet, then sends it. Returns the transaction signature. */
  send(review: TransferReview): Promise<string>;
  status(signature: string): Promise<'pending' | 'confirmed' | 'failed' | 'expired'>;
  recovery: WalletTransferClient['recovery'];
  acknowledge():void;
}

export interface MoneyApi {
  /** A product API is configured and an account is signed in. */
  readonly available: boolean;
  readonly accountId: string | null;
  /** Real mode for this account. Always false for guests. */
  readonly real: boolean;
  setReal(real: boolean): void;
  readonly wallet: WalletState;
  /** Holdings read within the observation window and past any confirmed trade. */
  readonly walletFresh: boolean;
  readonly walletSdk: 'unavailable' | 'loading' | 'ready';
  readonly canSetUpWallet: boolean;
  setUpWallet(): Promise<WalletSetupOutcome>;
  refreshWallet(): Promise<void>;
  readonly capabilities: TradingCapabilities | null;
  readonly capabilitiesFailed: boolean;
  refreshCapabilities(force?: boolean): Promise<void>;
  readonly terms: IssuerTermsStore | null;
  readonly orders: LiveOrderClient | null;
  /** A new order lifecycle bound to this account, or null for guests. */
  createOrderSession(): LiveOrderSession | null;
  readonly fundWalletOpen: boolean;
  /** Opens Add money (crypto deposit). Switches this account to Real, as mobile does. */
  openFundWallet(): void;
  closeFundWallet(): void;
  /** Send, or null for guests. */
  readonly transfers: TransferPort | null;
  readonly sendOpen: boolean;
  openSend(): void;
  closeSend(): void;
}

export const closedWallet: WalletState = Object.freeze({phase: 'closed', issue: null, context: null, holdings: null, freshUntil: null,
  checked: false, setupBusy: false, signing: false});
const guest: MoneyApi = Object.freeze({available: false, accountId: null, real: false, setReal() {}, wallet: closedWallet,
  walletFresh: false, walletSdk: 'unavailable', canSetUpWallet: false, setUpWallet: async () => 'unavailable' as const,
  refreshWallet: async () => {}, capabilities: null, capabilitiesFailed: false, refreshCapabilities: async () => {},
  terms: null, orders: null, createOrderSession: () => null, fundWalletOpen: false, openFundWallet() {}, closeFundWallet() {},
  transfers: null, sendOpen: false, openSend() {}, closeSend() {}});
export const MoneyContext = createContext<MoneyApi>(guest);
export function useMoney(): MoneyApi {return useContext(MoneyContext);}

const INTENT_KEY = 'trimmy.money.real-after-sign-in.v1';
/** A guest asked for Real: remember it briefly so the signed-in desk opens in Real. */
export function requestRealAfterSignIn(): void {
  try {window.sessionStorage.setItem(INTENT_KEY, String(Date.now()));} catch { /* The person can switch again. */ }
}
export function consumeRealIntent(): boolean {
  try {
    const at = Number(window.sessionStorage.getItem(INTENT_KEY));
    window.sessionStorage.removeItem(INTENT_KEY);
    return Number.isFinite(at) && Date.now() - at >= 0 && Date.now() - at < 600_000;
  } catch {return false;}
}
