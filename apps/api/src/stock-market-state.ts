import { BoundedSolanaRpc } from './solana-rpc-client.js';
import { AccountStateError, decodeAccountState, parseObservedAccount } from './solana-account-state.js';
import { usTradingState } from './us-equity-calendar.js';
import type { UsSession } from './us-equity-calendar.js';
import type { OndoMarketStatus, OndoMarketStatusReader } from './ondo-market-status.js';

/**
 * Whether a stock token can trade right now, and if not, why and until when.
 * Most tokens trade around the clock on Solana. Ondo's trade only in the US
 * sessions Ondo lists for each token: its live status decides, with the
 * published session calendar as the fallback. Any issuer can pause a mint on
 * chain (Token-2022 Pausable), which stops every transfer until it resumes.
 */
export type StockMarketStatus = 'open' | 'paused' | 'closed';
export type StockMarketReason = 'outside_sessions' | 'session_break' | 'market_paused' | 'issuer_paused';

export interface StockMarketState {
  /** 'always': trades around the clock. 'us_sessions': only in `sessions`. */
  readonly hours: 'always' | 'us_sessions';
  readonly sessions: readonly UsSession[] | null;
  readonly status: StockMarketStatus;
  readonly reason: StockMarketReason | null;
  /** The US session in force now, for context; null between sessions or for 'always' tokens. */
  readonly session: UsSession | null;
  readonly nextOpenAt: string | null;
  readonly closesAt: string | null;
  /** What decided a 'us_sessions' state: Ondo's live status or the calendar alone. */
  readonly source: 'ondo_status' | 'calendar' | null;
}

/** Sessions assumed for an Ondo token Ondo's live status does not list: the common 24/5. */
const ONDO_DEFAULT_SESSIONS: ReadonlySet<UsSession> = new Set(['overnight', 'premarket', 'regular', 'postmarket']);
const SESSION_ORDER: readonly UsSession[] = ['overnight', 'premarket', 'regular', 'postmarket', 'offhours'];
const iso = (value: number | null) => value === null ? null : new Date(value).toISOString();

export interface StockMarketStateInput {
  readonly issuerId: string;
  readonly symbol: string;
  readonly now: number;
  /** On-chain Pausable state of the mint; null when unknown. */
  readonly mintPaused: boolean | null;
  readonly ondo: OndoMarketStatus | null;
}

export function stockMarketState(input: StockMarketStateInput): StockMarketState {
  const {issuerId, symbol, now, mintPaused, ondo} = input;
  const usHours = issuerId === 'ondo';
  const listed = usHours ? ondo?.sessions.get(symbol) : undefined;
  const sessions = usHours ? listed ?? ONDO_DEFAULT_SESSIONS : null;
  const sessionList = sessions === null ? null : Object.freeze(SESSION_ORDER.filter(session => sessions.has(session)));
  const base = {hours: usHours ? 'us_sessions' as const : 'always' as const, sessions: sessionList,
    source: usHours ? (listed !== undefined ? 'ondo_status' as const : 'calendar' as const) : null};
  if (mintPaused === true) {
    return Object.freeze({...base, status: 'paused', reason: 'issuer_paused', session: null, nextOpenAt: null, closesAt: null});
  }
  if (sessions === null) {
    return Object.freeze({...base, status: 'open', reason: null, session: null, nextOpenAt: null, closesAt: null});
  }
  const computed = usTradingState(now, sessions);
  const liveNextOpen = ondo?.nextOpen !== null && ondo?.nextOpen !== undefined && ondo.nextOpen > now ? ondo.nextOpen : null;
  const closed = (reason: StockMarketReason, nextOpenAt: number | null) => Object.freeze({...base, status: 'closed' as const,
    reason, session: computed.session, nextOpenAt: iso(nextOpenAt), closesAt: null});
  if (ondo !== null) {
    const offhoursNow = computed.status === 'open' && computed.session === 'offhours';
    // An unscheduled pause of Ondo's whole market.
    if (ondo.reasonCode === 'MARKET_PAUSED' && !(offhoursNow && ondo.offhoursOpen)) {
      return Object.freeze({...base, status: 'paused', reason: 'market_paused', session: computed.session,
        nextOpenAt: iso(liveNextOpen ?? computed.nextOpenAt), closesAt: null});
    }
    // Ondo is closed although the calendar has a session (an unlisted holiday or closure).
    if (computed.status === 'open' && !offhoursNow && !ondo.isOpen) {
      if (!(sessions.has('offhours') && ondo.offhoursOpen)) return closed('outside_sessions', liveNextOpen ?? computed.nextOpenAt);
      return Object.freeze({...base, status: 'open', reason: null, session: 'offhours', nextOpenAt: null, closesAt: null});
    }
    // Off-hours trading switched off for now.
    if (offhoursNow && !ondo.offhoursOpen) return closed('outside_sessions', liveNextOpen ?? computed.nextOpenAt);
  }
  if (computed.status === 'open') {
    return Object.freeze({...base, status: 'open', reason: null, session: computed.session, nextOpenAt: null, closesAt: iso(computed.closesAt)});
  }
  if (computed.status === 'paused') {
    return Object.freeze({...base, status: 'paused', reason: 'session_break', session: computed.session,
      nextOpenAt: iso(computed.nextOpenAt), closesAt: null});
  }
  return closed('outside_sessions', computed.nextOpenAt);
}

class MintPauseReadError extends Error {}
const RPC_ERRORS = Object.freeze({
  configuration: () => new MintPauseReadError('configuration'), timeout: () => new MintPauseReadError('timeout'),
  unavailable: () => new MintPauseReadError('unavailable'), responseInvalid: () => new MintPauseReadError('response'),
  methodNotAllowed: () => new MintPauseReadError('method'),
});

/** Cached reads of each mint's on-chain pause flag. `read` never throws; unknown mints are absent. */
export class StockMintPauseReader {
  readonly #rpc: BoundedSolanaRpc<'getMultipleAccounts', MintPauseReadError>;
  readonly #now: () => number;
  readonly #ttlMs: number;
  #value = new Map<string, boolean>();
  #checkedAt = Number.NEGATIVE_INFINITY;
  #inflight: Promise<ReadonlyMap<string, boolean>> | null = null;

  constructor(options: {rpcUrl: string; fetch?: typeof globalThis.fetch; now?: () => number; ttlMs?: number}) {
    this.#rpc = new BoundedSolanaRpc({rpcUrl: options.rpcUrl, methods: ['getMultipleAccounts'], errors: RPC_ERRORS,
      maxBodyBytes: 2_097_152, ...(options.fetch ? {fetch: options.fetch} : {})});
    this.#now = options.now ?? Date.now;
    this.#ttlMs = options.ttlMs ?? 60_000;
  }

  async read(mints: readonly string[]): Promise<ReadonlyMap<string, boolean>> {
    if (this.#now() - this.#checkedAt < this.#ttlMs) return this.#value;
    this.#inflight ??= this.#load(mints).finally(() => { this.#inflight = null; });
    return this.#inflight;
  }

  peek(): ReadonlyMap<string, boolean> { return this.#value; }

  async #load(mints: readonly string[]): Promise<ReadonlyMap<string, boolean>> {
    const next = new Map<string, boolean>();
    try {
      for (let index = 0; index < mints.length; index += 100) {
        const part = mints.slice(index, index + 100);
        const outcome = await this.#rpc.call('getMultipleAccounts', [part, {encoding: 'base64', commitment: 'confirmed'}]);
        const values = (outcome.result as {value?: unknown} | null)?.value;
        if (!Array.isArray(values) || values.length !== part.length) return this.#value;
        part.forEach((mint, position) => {
          try {
            const state = decodeAccountState(parseObservedAccount(mint, values[position]));
            if (state.kind === 'mint') next.set(mint, state.paused === true);
          } catch (error) {
            if (!(error instanceof AccountStateError)) throw error;
          }
        });
      }
      this.#value = next;
      return next;
    } catch {
      return this.#value;
    } finally {
      this.#checkedAt = this.#now();
    }
  }
}

export type StockMarketStateOf = (issuerId: string, symbol: string, mint: string) => StockMarketState;

/** States from the calendar alone: no live status and no pause reads. */
export function calendarMarketStates(now: number): StockMarketStateOf {
  return (issuerId, symbol) => stockMarketState({issuerId, symbol, now, mintPaused: null, ondo: null});
}

/** Live inputs for market states, bounded so a slow provider never delays a response for long. */
export class StockMarketStates {
  readonly #ondo: OndoMarketStatusReader | null;
  readonly #pauses: StockMintPauseReader | null;
  readonly #mints: () => readonly string[];
  readonly #now: () => number;
  readonly #waitMs: number;

  constructor(options: {ondo: OndoMarketStatusReader | null; pauses: StockMintPauseReader | null;
    /** The tradeable mints to watch; a function when the list grows. */
    mints: readonly string[] | (() => readonly string[]);
    now?: () => number; waitMs?: number}) {
    this.#ondo = options.ondo;
    this.#pauses = options.pauses;
    const mints = options.mints;
    this.#mints = typeof mints === 'function' ? mints : () => mints;
    this.#now = options.now ?? Date.now;
    this.#waitMs = options.waitMs ?? 2_500;
  }

  /** A state function over the freshest inputs available within the wait bound. */
  async snapshot(): Promise<StockMarketStateOf> {
    const wait = <T>(work: Promise<T>, fallback: () => T) => Promise.race([work,
      new Promise<T>(resolve => { setTimeout(() => resolve(fallback()), this.#waitMs).unref?.(); })]);
    const [ondo, pauses] = await Promise.all([
      this.#ondo === null ? Promise.resolve(null) : wait(this.#ondo.read(), () => this.#ondo!.peek()),
      this.#pauses === null ? Promise.resolve(new Map<string, boolean>()) : wait(this.#pauses.read(this.#mints()), () => this.#pauses!.peek()),
    ]);
    const now = this.#now();
    return (issuerId, symbol, mint) => stockMarketState({issuerId, symbol, now, mintPaused: pauses.get(mint) ?? null, ondo});
  }
}
