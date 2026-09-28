/**
 * The live stock order contract: preview → reviewed order → exact-transaction
 * signing → execute → reconciliation, plus submitted-order history.
 * Contract: apps/api/src/live-stock-orders.ts and live-trade-history.ts; mobile
 * live_order_flow.dart and live_trade_history.dart. Nothing here signs.
 */
import {USDC_MINT} from './amounts.js';
import {MoneyHttpError, moneyApiBase, requestJson, responseCode, validBearer, type BearerSource} from './http.js';
import {CAPABILITIES_MAX_BYTES, parseTradingCapabilities, type TradingCapabilities} from './live-trading.js';

/** Carries a bounded code; its message is the person-facing copy for that code. */
export class LiveOrderError extends Error {
  constructor(readonly code: string, readonly retryAfterSeconds: number | null = null) {
    super(liveOrderMessage(code, retryAfterSeconds)); this.name = 'LiveOrderError';
  }
}

/** Mobile's copy for every code the API can return, plus local signing outcomes. */
export function liveOrderMessage(code: string, retryAfterSeconds: number | null = null): string {
  switch (code) {
    case 'LIVE_BUSY': return retryAfterSeconds !== null && retryAfterSeconds > 0
      ? `Quotes are busy. Try again in ${retryAfterSeconds} ${retryAfterSeconds === 1 ? 'second' : 'seconds'}.` : 'Quotes are busy. Try again in a moment.';
    case 'ADD_USDC': return 'Add USDC to your Solana wallet first.';
    case 'ADD_SOL': return 'Add SOL to cover network and account fees.';
    case 'INSUFFICIENT_HOLDINGS': return 'You don’t have enough of this token to sell.';
    case 'TRADE_LIMIT': return 'This order is above the current trade limit.';
    case 'TERMS_REQUIRED': return 'Confirm the issuer terms to continue.';
    case 'WALLET_REQUIRED': return 'Create your wallet to continue.';
    case 'ORDER_PENDING': return 'Your previous trade is still confirming.';
    case 'QUOTE_EXPIRED': return 'That price expired. Get a fresh quote.';
    case 'NO_ROUTE': return 'No route for this order right now. Try another amount.';
    case 'MARKET_CLOSED': return 'This stock trades while US markets are open. Try again then.';
    case 'BELOW_MINIMUM': return 'This order is under the market maker’s minimum. Try a larger amount.';
    case 'PRICE_OFF_MARKET': return 'That price is too far from the market right now. Try again shortly or a smaller amount.';
    case 'FEE_TOO_HIGH': return 'The fees are too high for this order. Try later.';
    case 'ACCOUNT_REQUIRED': return 'Sign in again to use your wallet.';
    case 'INVALID_REVIEW': case 'INVALID_SIGNATURE': return 'This order needs a fresh quote.';
    // The API checks the company and token pair on the spot and refuses one that does not qualify.
    case 'MARKET_INPUT_INVALID': return 'Trimmy can’t trade this token right now. Choose another version or company.';
    case 'LIVE_UNAVAILABLE': return 'Trading couldn’t connect. Try again.';
    default: return 'Couldn’t complete this step. Try again.';
  }
}

const KNOWN = new Set(['ACCOUNT_REQUIRED', 'WALLET_REQUIRED', 'ORDER_PENDING', 'QUOTE_EXPIRED', 'INVALID_REVIEW',
  'INVALID_SIGNATURE', 'ADD_USDC', 'ADD_SOL', 'INSUFFICIENT_HOLDINGS', 'NO_ROUTE', 'FEE_TOO_HIGH', 'LIVE_BUSY',
  'TRADE_LIMIT', 'TERMS_REQUIRED', 'MARKET_CLOSED', 'BELOW_MINIMUM', 'PRICE_OFF_MARKET', 'MARKET_INPUT_INVALID', 'LIVE_UNAVAILABLE']);

export type LiveOrderStatus = 'reviewed' | 'pending' | 'confirmed' | 'failed' | 'expired';
export interface LiveOrderTerms {
  readonly side: 'buy' | 'sell'; readonly inputMint: string; readonly outputMint: string;
  readonly inputAmountRaw: string; readonly quotedOutputAmountRaw: string; readonly minimumOutputAmountRaw: string;
  /** The most SOL the network and new accounts can cost this order. */
  readonly totalLamportsUpperBound: string;
  readonly platformFeeBps: number; readonly slippageBps: number | null;
  readonly simulatedOutputReceivedRaw: string | null;
  /** Can be negative: the order returns SOL, e.g. by closing a wrapped SOL account. */
  readonly simulatedTakerLamportsSpent: string | null;
  /** SOL a closed wrapped SOL account returns to the wallet; "0" or null when none. */
  readonly takerLamportsReturnUpperBound: string | null;
  readonly stockUiMultiplier: string | null;
  readonly route: 'aggregator' | 'rfq' | null;
  /**
   * `maker_delivers_at_fill`: an Ondo market maker mints just in time after the
   * user signs, and the fill is all or nothing. `simulated`: the review
   * simulated the delivery. Null from servers that do not say.
   */
  readonly settlement: 'simulated' | 'maker_delivers_at_fill' | null;
}
export interface LiveOrder {
  readonly id: string; readonly status: LiveOrderStatus; readonly wallet: string; readonly signature: string | null;
  readonly expiresAt: string; readonly reviewDigest: string; readonly confirmedSlot: number | null;
  readonly terms: LiveOrderTerms; readonly reviewFlags: readonly string[];
  /** The exact unsigned transaction, only while the order is reviewed. */
  readonly transaction: string | null;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const MINT = /^[1-9A-HJ-NP-Za-km-z]{32,44}$/;
const SIGNATURE = /^[1-9A-HJ-NP-Za-km-z]{64,88}$/;
const RAW = /^(?:0|[1-9][0-9]{0,19})$/;
const SIGNED_RAW = /^-?(?:0|[1-9][0-9]{0,19})$/;
const invalid = (): never => {throw new LiveOrderError('LIVE_UNAVAILABLE');};

function parseTerms(value: unknown): LiveOrderTerms {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) invalid();
  const t = value as Record<string, unknown>;
  const raw = (key: string) => typeof t[key] === 'string' && RAW.test(t[key] as string) ? t[key] as string : invalid();
  const optionalRaw = (key: string, pattern = RAW) => typeof t[key] === 'string' && pattern.test(t[key] as string) ? t[key] as string : null;
  const fee = t['platformFeeBps'];
  if (t['side'] !== 'buy' && t['side'] !== 'sell' || typeof t['inputMint'] !== 'string' || !MINT.test(t['inputMint']) ||
      typeof t['outputMint'] !== 'string' || !MINT.test(t['outputMint']) ||
      typeof fee !== 'number' || !Number.isInteger(fee) || fee < 0 || fee > 10000) invalid();
  const slippage = t['slippageBps'];
  const multiplier = t['stockUiMultiplier'];
  return Object.freeze({side: t['side'] as 'buy' | 'sell', inputMint: t['inputMint'] as string, outputMint: t['outputMint'] as string,
    inputAmountRaw: raw('inputAmountRaw'), quotedOutputAmountRaw: raw('quotedOutputAmountRaw'),
    minimumOutputAmountRaw: raw('minimumOutputAmountRaw'), totalLamportsUpperBound: raw('totalLamportsUpperBound'),
    platformFeeBps: fee as number, slippageBps: typeof slippage === 'number' && Number.isInteger(slippage) && slippage >= 0 && slippage <= 10000 ? slippage : null,
    simulatedOutputReceivedRaw: optionalRaw('simulatedOutputReceivedRaw'),
    simulatedTakerLamportsSpent: optionalRaw('simulatedTakerLamportsSpent', SIGNED_RAW),
    takerLamportsReturnUpperBound: optionalRaw('takerLamportsReturnUpperBound'),
    stockUiMultiplier: typeof multiplier === 'string' && multiplier.length <= 64 && /^[0-9]+(?:\.[0-9]+)?$/.test(multiplier) ? multiplier : null,
    route: t['route'] === 'rfq' || t['route'] === 'aggregator' ? t['route'] : null,
    settlement: t['settlement'] === 'simulated' || t['settlement'] === 'maker_delivers_at_fill' ? t['settlement'] : null});
}

export function parseLiveOrder(value: unknown): LiveOrder {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) invalid();
  const o = value as Record<string, unknown>;
  const status = o['status'];
  const slot = o['confirmedSlot'];
  const flags = o['reviewFlags'] ?? [];
  if (typeof o['id'] !== 'string' || !UUID.test(o['id']) ||
      !['reviewed', 'pending', 'confirmed', 'failed', 'expired'].includes(status as string) ||
      typeof o['wallet'] !== 'string' || !MINT.test(o['wallet']) || typeof o['expiresAt'] !== 'string' ||
      !Number.isFinite(Date.parse(o['expiresAt'])) || o['signature'] !== null && o['signature'] !== undefined &&
      (typeof o['signature'] !== 'string' || !SIGNATURE.test(o['signature'])) ||
      slot !== undefined && slot !== null && (typeof slot !== 'number' || !Number.isSafeInteger(slot) || slot < 1) ||
      !Array.isArray(flags) || flags.length > 64 || flags.some(flag => typeof flag !== 'string' || !/^[a-z0-9_]{1,80}$/.test(flag))) invalid();
  const digest = o['reviewDigest'];
  const transaction = o['transaction'];
  if (typeof digest !== 'string' || !/^[0-9a-f]{64}$/.test(digest)) invalid();
  if (status === 'reviewed' && (typeof transaction !== 'string' || transaction.length > 2048 || !/^[A-Za-z0-9+/]+={0,2}$/.test(transaction))) invalid();
  const terms = parseTerms(o['terms']);
  const stockMint = terms.side === 'buy' ? terms.outputMint : terms.inputMint;
  if ((terms.side === 'buy' ? terms.inputMint : terms.outputMint) !== USDC_MINT || stockMint === USDC_MINT) invalid();
  return Object.freeze({id: o['id'] as string, status: status as LiveOrderStatus, wallet: o['wallet'] as string,
    signature: typeof o['signature'] === 'string' ? o['signature'] : null, expiresAt: o['expiresAt'] as string,
    reviewDigest: digest as string, confirmedSlot: typeof slot === 'number' ? slot : null, terms,
    reviewFlags: Object.freeze([...flags as string[]]),
    transaction: status === 'reviewed' ? transaction as string : null});
}

export type TradeStatus = 'pending' | 'confirmed' | 'failed' | 'expired';
export interface TradeRecord {
  readonly id: string; readonly wallet: string; readonly status: TradeStatus; readonly signature: string;
  readonly createdAt: string; readonly updatedAt: string; readonly assetId: string; readonly mint: string;
  readonly symbol: string; readonly name: string; readonly decimals: number; readonly buy: boolean;
  /** Filled by a market maker: the transaction id is the maker's signature, not this one. */
  readonly rfq: boolean;
  readonly inputAmountRaw: string; readonly quotedOutputAmountRaw: string; readonly minimumOutputAmountRaw: string;
  /** What the confirmed transaction actually moved, once the server recorded it. */
  readonly fill: {readonly inputAmountRaw: string; readonly outputAmountRaw: string} | null;
}
export interface TradeHistoryPage {readonly orders: readonly TradeRecord[]; readonly nextCursor: string | null}

export function explorerUrl(order: {readonly rfq: boolean; readonly wallet: string; readonly signature: string}): string {
  return order.rfq ? `https://solscan.io/account/${order.wallet}` : `https://solscan.io/tx/${order.signature}`;
}

function historyRecord(value: unknown): TradeRecord {
  const fault = (): never => {throw new LiveOrderError('HISTORY_UNAVAILABLE');};
  if (value === null || typeof value !== 'object' || Array.isArray(value)) fault();
  const row = value as Record<string, unknown>;
  const asset = row['asset'] as Record<string, unknown> | undefined, terms = row['terms'] as Record<string, unknown> | undefined;
  const date = (key: string) => typeof row[key] === 'string' && (row[key] as string).length <= 40 && /Z$/.test(row[key] as string) &&
    Number.isFinite(Date.parse(row[key] as string)) ? row[key] as string : fault();
  const amount = (key: string) => typeof terms?.[key] === 'string' && RAW.test(terms[key] as string) &&
    BigInt(terms[key] as string) <= 18_446_744_073_709_551_615n ? terms[key] as string : fault();
  if (!asset || typeof asset !== 'object' || !terms || typeof terms !== 'object' ||
      !['pending', 'confirmed', 'failed', 'expired'].includes(row['status'] as string) ||
      row['amountUnits'] !== 'raw_token_units' || row['amountsStatus'] !== 'reviewed_quote' ||
      typeof asset['decimals'] !== 'number' || !Number.isInteger(asset['decimals']) || asset['decimals'] < 0 || asset['decimals'] > 18 ||
      terms['side'] !== 'buy' && terms['side'] !== 'sell' || typeof asset['mint'] !== 'string' || !MINT.test(asset['mint'])) fault();
  const buy = terms!['side'] === 'buy', mint = asset!['mint'] as string;
  if (terms!['inputMint'] !== (buy ? USDC_MINT : mint) || terms!['outputMint'] !== (buy ? mint : USDC_MINT)) fault();
  const input = amount('inputAmountRaw'), output = amount('quotedOutputAmountRaw'), minimum = amount('minimumOutputAmountRaw');
  if (input === '0' || output === '0' || BigInt(minimum) > BigInt(output)) fault();
  const field = (source: Record<string, unknown>, key: string, pattern: RegExp) =>
    typeof source[key] === 'string' && pattern.test(source[key] as string) ? source[key] as string : fault();
  // A fill arrives only for confirmed orders; anything else is ignored.
  const fillRow = row['fill'] !== null && typeof row['fill'] === 'object' && !Array.isArray(row['fill']) && row['status'] === 'confirmed'
    ? row['fill'] as Record<string, unknown> : null;
  const filled = (key: string) => typeof fillRow?.[key] === 'string' && /^[1-9][0-9]{0,19}$/.test(fillRow[key] as string) &&
    BigInt(fillRow[key] as string) <= 18_446_744_073_709_551_615n ? fillRow[key] as string : null;
  const fillInput = filled('inputAmountRaw'), fillOutput = filled('outputAmountRaw');
  return Object.freeze({id: field(row, 'id', /^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$/), wallet: field(row, 'wallet', MINT),
    status: row['status'] as TradeStatus, signature: field(row, 'signature', SIGNATURE), createdAt: date('createdAt'),
    updatedAt: date('updatedAt'), assetId: field(asset!, 'assetId', /^[a-z0-9_-]{1,128}$/), mint,
    symbol: field(asset!, 'symbol', /^[^\x00-\x1f\x7f]{1,32}$/), name: field(asset!, 'name', /^[^\x00-\x1f\x7f]{1,160}$/),
    decimals: asset!['decimals'] as number, buy, rfq: asset!['route'] === 'rfq', inputAmountRaw: input,
    quotedOutputAmountRaw: output, minimumOutputAmountRaw: minimum,
    fill: fillInput && fillOutput ? Object.freeze({inputAmountRaw: fillInput, outputAmountRaw: fillOutput}) : null});
}

export function parseTradeHistory(value: unknown): TradeHistoryPage {
  const fault = (): never => {throw new LiveOrderError('HISTORY_UNAVAILABLE');};
  if (value === null || typeof value !== 'object' || Array.isArray(value)) fault();
  const data = value as Record<string, unknown>;
  const rows = data['orders'], cursor = data['nextCursor'];
  if (data['schemaVersion'] !== 1 || data['network'] !== 'solana:mainnet-beta' || !Array.isArray(rows) || rows.length > 50 ||
      cursor !== null && cursor !== undefined && (typeof cursor !== 'string' || !cursor || cursor.length > 1024)) fault();
  const orders = (rows as unknown[]).map(historyRecord);
  if (new Set(orders.map(order => order.id)).size !== orders.length || orders.length === 0 && typeof cursor === 'string') fault();
  return Object.freeze({orders: Object.freeze(orders), nextCursor: typeof cursor === 'string' ? cursor : null});
}

export interface PreviewInput {
  readonly assetId: string; readonly variantMint: string; readonly side: 'buy' | 'sell'; readonly amountRaw: string;
  /** Required by issuer-aware servers; legacy servers reject the unknown field. */
  readonly termsAccepted?: {readonly issuerId: string; readonly version: string};
}
export interface LiveOrderClientOptions {
  readonly baseUrl: string; readonly bearer: BearerSource; readonly fetch?: typeof fetch;
  /** Aborted when the signed-in identity changes; every call then fails closed. */
  readonly signal?: AbortSignal;
  readonly timeoutMs?: number;
}

export class LiveOrderClient {
  readonly #base: string; readonly #bearer: BearerSource; readonly #fetch: typeof fetch;
  readonly #signal: AbortSignal | undefined; readonly #timeout: number;
  constructor(options: LiveOrderClientOptions) {
    this.#base = moneyApiBase(options.baseUrl);
    this.#bearer = options.bearer;
    this.#fetch = options.fetch ?? globalThis.fetch.bind(globalThis);
    this.#signal = options.signal;
    this.#timeout = options.timeoutMs ?? 45_000;
  }
  get current(): boolean {return !this.#signal?.aborted;}

  /**
   * Public read. Schema 3 lists every tradeable token; an older server answers
   * 400 and is asked for schema 2, then for the plain legacy shape.
   */
  async capabilities(): Promise<TradingCapabilities> {
    for (const path of ['/v1/trading/capabilities?schema=3', '/v1/trading/capabilities?schema=2', '/v1/trading/capabilities']) {
      let response;
      try {
        response = await requestJson(this.#fetch, `${this.#base}${path}`, {timeoutMs: 12_000, maxBytes: CAPABILITIES_MAX_BYTES, signal: this.#signal});
      } catch {throw new LiveOrderError('LIVE_UNAVAILABLE');}
      if (response.status === 400 && path.includes('schema')) continue;
      if (response.status !== 200) throw new LiveOrderError('LIVE_UNAVAILABLE');
      try {return parseTradingCapabilities(response.body);} catch {throw new LiveOrderError('LIVE_UNAVAILABLE');}
    }
    throw new LiveOrderError('LIVE_UNAVAILABLE');
  }

  preview(input: PreviewInput): Promise<LiveOrder> {
    return this.#order('POST', '/v1/trading/preview', {assetId: input.assetId, variantMint: input.variantMint, side: input.side,
      amountRaw: input.amountRaw, ...(input.termsAccepted ? {termsAccepted: {issuerId: input.termsAccepted.issuerId, version: input.termsAccepted.version}} : {})})
      .then(order => order ?? invalid());
  }
  execute(input: {readonly id: string; readonly reviewDigest: string; readonly signedTransaction: string}): Promise<LiveOrder> {
    return this.#order('POST', '/v1/trading/execute', {id: input.id, reviewDigest: input.reviewDigest, signedTransaction: input.signedTransaction})
      .then(order => order ?? invalid());
  }
  /** One order by id, or the account's latest order. Reading never dispatches. */
  order(id?: string): Promise<LiveOrder | null> {
    if (id !== undefined && !UUID.test(id)) return Promise.reject(new LiveOrderError('LIVE_UNAVAILABLE'));
    return this.#order('GET', id === undefined ? '/v1/trading/order' : `/v1/trading/order/${id}`);
  }

  async history(cursor?: string): Promise<TradeHistoryPage> {
    if (cursor !== undefined && (!cursor || cursor.length > 1024)) throw new LiveOrderError('HISTORY_UNAVAILABLE');
    const query = new URLSearchParams({limit: '20', ...(cursor ? {cursor} : {})});
    const response = await this.#send('GET', `/v1/trading/history?${query}`, undefined, 131_072, 15_000, 'HISTORY_UNAVAILABLE');
    if (response.status !== 200) throw new LiveOrderError(response.status === 401 ? 'ACCOUNT_REQUIRED' : 'HISTORY_UNAVAILABLE');
    const page = parseTradeHistory(response.body);
    if (cursor !== undefined && page.nextCursor === cursor) throw new LiveOrderError('HISTORY_UNAVAILABLE');
    return page;
  }

  async #order(method: 'GET' | 'POST', path: string, body?: unknown): Promise<LiveOrder | null> {
    const response = await this.#send(method, path, body, 32_768, this.#timeout, 'LIVE_UNAVAILABLE');
    if (response.status !== 200) {
      const code = responseCode(response.body);
      throw new LiveOrderError(response.status === 401 ? 'ACCOUNT_REQUIRED' : code && KNOWN.has(code) ? code : 'LIVE_UNAVAILABLE', response.retryAfter);
    }
    const data = response.body;
    if (data === null || typeof data !== 'object' || Array.isArray(data) || !('order' in data)) invalid();
    const order = (data as {order: unknown}).order;
    return order === null ? null : parseLiveOrder(order);
  }

  async #send(method: 'GET' | 'POST', path: string, body: unknown, maxBytes: number, timeoutMs: number, fallback: string) {
    if (!this.current) throw new LiveOrderError('ACCOUNT_REQUIRED');
    let token: string | null;
    try {token = await this.#bearer();} catch {token = null;}
    if (!this.current || !validBearer(token)) throw new LiveOrderError('ACCOUNT_REQUIRED');
    try {
      const response = await requestJson(this.#fetch, `${this.#base}${path}`, {method, headers: {authorization: `Bearer ${token}`},
        body, timeoutMs, maxBytes, signal: this.#signal});
      if (!this.current) throw new LiveOrderError('ACCOUNT_REQUIRED');
      return response;
    } catch (error) {
      if (error instanceof LiveOrderError) throw error;
      throw new LiveOrderError(!this.current ? 'ACCOUNT_REQUIRED' : error instanceof MoneyHttpError && error.code === 'TIMEOUT' ? 'NETWORK_TIMEOUT' : fallback === 'LIVE_UNAVAILABLE' ? 'NETWORK_UNCERTAIN' : fallback);
    }
  }
}

/** A lost reply after dispatch: the order may exist, so it is reconciled, never resent. */
export function uncertainNetwork(error: unknown): boolean {
  return error instanceof LiveOrderError && (error.code === 'NETWORK_UNCERTAIN' || error.code === 'NETWORK_TIMEOUT');
}
