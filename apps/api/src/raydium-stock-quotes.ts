import { address } from '@solana/kit';
import { parseRawAmount } from '@trimmy/domain';
import { MarketEstimateError } from './jupiter-quote-reader.js';
import { STOCK_ESTIMATE_ASSET, validateStockEstimateInput } from './stock-estimates.js';
import type { StockEstimateInput } from './stock-estimates.js';

export const RAYDIUM_STOCK_QUOTE_CONFIGURATION = Object.freeze({
  endpoint: 'https://transaction-v1.raydium.io/compute/swap-base-in',
  slippageBps: 50,
  transactionVersion: 'V0' as const,
  refreshWindowMs: 10_000,
  maximumRouteHops: 4,
});

const USDC = Object.freeze({
  symbol: 'USDC',
  mint: 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',
  decimals: 6,
});
const AAPLX = Object.freeze({
  symbol: 'AAPLx',
  mint: STOCK_ESTIMATE_ASSET.variantMint,
  decimals: STOCK_ESTIMATE_ASSET.decimals,
});

export interface RaydiumStockQuoteHop {
  readonly poolId: string;
  readonly inputMint: string;
  readonly outputMint: string;
  readonly fee: {
    readonly amountRaw: string;
    readonly mint: string;
    /** Raydium exposes an integer feeRate but does not define its unit in the inspected Trade API schema. */
    readonly providerRateRaw: number;
    readonly rateUnit: 'provider_integer_unverified';
  };
}

export interface RaydiumStockQuote {
  readonly schemaVersion: 1;
  readonly kind: 'indicative';
  readonly comparisonOnly: true;
  readonly network: 'solana:mainnet-beta';
  readonly provider: 'raydium-trade-api';
  readonly providerResponseVersion: 'V1';
  readonly providerEndpoint: 'compute/swap-base-in';
  readonly quoteMode: 'BaseIn';
  readonly transactionVersionRequested: 'V0';
  readonly assetId: 'apple';
  readonly variantMint: typeof STOCK_ESTIMATE_ASSET.variantMint;
  readonly side: 'buy' | 'sell';
  readonly executionEnabled: false;
  readonly executable: false;
  readonly eligibility: 'unverified';
  readonly walletChecked: false;
  readonly networkFees: null;
  readonly amountUnits: 'raw_token_units';
  readonly input: {
    readonly symbol: 'USDC' | 'AAPLx';
    readonly mint: string;
    readonly decimals: number;
    readonly amountRaw: string;
    /** Null when Raydium omits this optional observation. */
    readonly providerActualAmountRaw: string | null;
  };
  readonly output: {
    readonly symbol: 'USDC' | 'AAPLx';
    readonly mint: string;
    readonly decimals: number;
    readonly estimatedAmountRaw: string;
    readonly quotedMinimumAmountRaw: string;
  };
  readonly slippageBps: 50;
  readonly priceImpactPct: number;
  readonly referralAmountRaw: '0';
  readonly route: {
    readonly hopCount: number;
    readonly hops: readonly RaydiumStockQuoteHop[];
  };
  readonly requestedAt: string;
  readonly receivedAt: string;
  /** Trimmy's display deadline. It is not a transaction validity guarantee. */
  readonly refreshAfter: string;
  /** Raydium documents an approximate lifetime but returns no exact expiry here. */
  readonly providerExpiresAt: null;
}

export interface RaydiumStockQuotes {
  quote(input: StockEstimateInput): Promise<RaydiumStockQuote>;
}

export interface RaydiumStockQuoteOptions {
  readonly fetch?: typeof globalThis.fetch;
  readonly now?: () => number;
  readonly timeoutMs?: number;
}

const maximumBodyBytes = 65_536;
const requestSpacingMs = 1_100;
const providerCooldownMs = 60_000;
const zeroAddress = '11111111111111111111111111111111';
const uuidV4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const forbiddenExecutionKeys = new Set([
  'addresslookuptableaddresses', 'serializedtransaction', 'signedtransaction',
  'signature', 'signatures', 'swapresponse', 'transaction', 'transactions', 'tx', 'wallet',
]);

function invalid(): never {
  throw new MarketEstimateError('MARKET_RESPONSE_INVALID');
}

function record(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) invalid();
  return value as Record<string, unknown>;
}

function rawAmount(value: unknown, options: {positive?: boolean} = {}): string {
  if (typeof value !== 'string') invalid();
  try {
    const parsed = parseRawAmount(value);
    if (options.positive && parsed === 0n) invalid();
  } catch {
    invalid();
  }
  return value;
}

function solanaAddress(value: unknown): string {
  if (typeof value !== 'string' || value.length > 44 || value === zeroAddress) invalid();
  try {
    if (address(value) !== value) invalid();
  } catch {
    invalid();
  }
  return value;
}

function assertNoExecutionPayload(value: unknown): void {
  const pending: Array<{value: unknown; depth: number}> = [{value, depth: 0}];
  let nodes = 0;
  while (pending.length > 0) {
    const current = pending.pop();
    if (!current) invalid();
    nodes += 1;
    if (nodes > 2_048 || current.depth > 12) invalid();
    if (current.value === null || typeof current.value !== 'object') continue;
    for (const [key, child] of Object.entries(current.value)) {
      if (forbiddenExecutionKeys.has(key.toLowerCase())) invalid();
      pending.push({value: child, depth: current.depth + 1});
    }
  }
}

function parseRoute(data: Record<string, unknown>, fromMint: string, toMint: string,
  requestedInputRaw: string): readonly RaydiumStockQuoteHop[] {
  const raw = data['routePlan'];
  if (!Array.isArray(raw) || raw.length < 1 || raw.length > RAYDIUM_STOCK_QUOTE_CONFIGURATION.maximumRouteHops) invalid();
  const poolIds = new Set<string>();
  const visitedMints = new Set<string>([fromMint]);
  let expectedInputMint = fromMint;
  const hops: RaydiumStockQuoteHop[] = [];
  for (const [index, candidate] of raw.entries()) {
    const hop = record(candidate);
    const poolId = solanaAddress(hop['poolId']);
    const inputMint = solanaAddress(hop['inputMint']);
    const outputMint = solanaAddress(hop['outputMint']);
    const feeMint = solanaAddress(hop['feeMint']);
    const feeAmount = rawAmount(hop['feeAmount']);
    const feeRate = hop['feeRate'];
    if (poolIds.has(poolId) || inputMint !== expectedInputMint || inputMint === outputMint ||
        visitedMints.has(outputMint) || (feeMint !== inputMint && feeMint !== outputMint) ||
        typeof feeRate !== 'number' || !Number.isInteger(feeRate) || feeRate < 0 || feeRate > 10_000) invalid();
    if (index === 0 && feeMint === inputMint && BigInt(feeAmount) > BigInt(requestedInputRaw)) invalid();
    if (hop['remainingAccounts'] !== undefined) {
      const accounts = hop['remainingAccounts'];
      if (!Array.isArray(accounts) || accounts.length > 32) invalid();
      const seenAccounts = new Set<string>();
      for (const candidateAddress of accounts) {
        const parsed = solanaAddress(candidateAddress);
        if (seenAccounts.has(parsed)) invalid();
        seenAccounts.add(parsed);
      }
    }
    if (hop['lastPoolPriceX64'] !== undefined) {
      const price = hop['lastPoolPriceX64'];
      if (typeof price !== 'string' || /^(0|[1-9]\d{0,38})$/.exec(price)?.[0] !== price ||
          BigInt(price) > (1n << 128n) - 1n) invalid();
    }
    poolIds.add(poolId);
    visitedMints.add(outputMint);
    expectedInputMint = outputMint;
    hops.push(Object.freeze({
      poolId, inputMint, outputMint,
      fee: Object.freeze({amountRaw: feeAmount, mint: feeMint,
        providerRateRaw: feeRate, rateUnit: 'provider_integer_unverified' as const}),
    }));
  }
  if (expectedInputMint !== toMint) invalid();
  return Object.freeze(hops);
}

function parseQuote(payload: unknown, input: StockEstimateInput, started: number, received: number): RaydiumStockQuote {
  if (!Number.isSafeInteger(received) || received < started ||
      received >= started + RAYDIUM_STOCK_QUOTE_CONFIGURATION.refreshWindowMs) {
    throw new MarketEstimateError('MARKET_ESTIMATE_STALE');
  }
  const envelope = record(payload);
  assertNoExecutionPayload(envelope);
  if (typeof envelope['id'] !== 'string' || !uuidV4.test(envelope['id']) || envelope['version'] !== 'V1') invalid();
  if (envelope['success'] === false) {
    const message = envelope['msg'];
    if (typeof message !== 'string' || message.length < 1 || message.length > 512 ||
        envelope['data'] !== undefined && envelope['data'] !== null ||
        Object.keys(envelope).some((key) => !['id', 'success', 'version', 'msg', 'data'].includes(key))) invalid();
    throw new MarketEstimateError('MARKET_PROVIDER_UNAVAILABLE');
  }
  if (envelope['success'] !== true || Object.keys(envelope).length !== 4 ||
      Object.keys(envelope).some((key) => !['id', 'success', 'version', 'data'].includes(key))) invalid();
  const data = record(envelope['data']);
  const from = input.side === 'buy' ? USDC : AAPLX;
  const to = input.side === 'buy' ? AAPLX : USDC;
  if (data['swapType'] !== 'BaseIn' || data['inputMint'] !== from.mint ||
      data['outputMint'] !== to.mint || data['inputAmount'] !== input.amountRaw ||
      data['slippageBps'] !== RAYDIUM_STOCK_QUOTE_CONFIGURATION.slippageBps ||
      data['referrerAmount'] !== '0') invalid();
  const output = rawAmount(data['outputAmount'], {positive: true});
  const minimum = rawAmount(data['otherAmountThreshold'], {positive: true});
  const actualInput = data['actualInputAmount'] === undefined
    ? null : rawAmount(data['actualInputAmount'], {positive: true});
  if (BigInt(minimum) > BigInt(output) ||
      BigInt(minimum) < BigInt(output) * BigInt(10_000 - RAYDIUM_STOCK_QUOTE_CONFIGURATION.slippageBps) / 10_000n ||
      actualInput !== null && BigInt(actualInput) > BigInt(input.amountRaw)) invalid();
  const priceImpact = data['priceImpactPct'];
  if (typeof priceImpact !== 'number' || !Number.isFinite(priceImpact) || priceImpact < 0 || priceImpact > 100) invalid();
  const hops = parseRoute(data, from.mint, to.mint, input.amountRaw);
  return Object.freeze({
    schemaVersion: 1, kind: 'indicative', comparisonOnly: true,
    network: 'solana:mainnet-beta', provider: 'raydium-trade-api', providerResponseVersion: 'V1',
    providerEndpoint: 'compute/swap-base-in', quoteMode: 'BaseIn', transactionVersionRequested: 'V0',
    assetId: input.assetId, variantMint: input.variantMint, side: input.side,
    executionEnabled: false, executable: false, eligibility: 'unverified', walletChecked: false,
    networkFees: null, amountUnits: 'raw_token_units',
    input: Object.freeze({symbol: from.symbol, mint: from.mint, decimals: from.decimals,
      amountRaw: input.amountRaw, providerActualAmountRaw: actualInput}),
    output: Object.freeze({symbol: to.symbol, mint: to.mint, decimals: to.decimals,
      estimatedAmountRaw: output, quotedMinimumAmountRaw: minimum}),
    slippageBps: RAYDIUM_STOCK_QUOTE_CONFIGURATION.slippageBps,
    priceImpactPct: priceImpact, referralAmountRaw: '0',
    route: Object.freeze({hopCount: hops.length, hops}),
    requestedAt: new Date(started).toISOString(), receivedAt: new Date(received).toISOString(),
    refreshAfter: new Date(started + RAYDIUM_STOCK_QUOTE_CONFIGURATION.refreshWindowMs).toISOString(),
    providerExpiresAt: null,
  });
}

/**
 * Keyless quote-only reader. The fixed URL can reach only Raydium's compute GET;
 * no transaction builder URL, wallet parameter, signer or retry exists here.
 */
export class RaydiumStockQuoteReader implements RaydiumStockQuotes {
  readonly #fetch: typeof globalThis.fetch;
  readonly #now: () => number;
  readonly #timeoutMs: number;
  #nextRequestAt = 0;
  #inFlight = false;

  constructor(options: RaydiumStockQuoteOptions = {}) {
    this.#fetch = options.fetch ?? globalThis.fetch;
    this.#now = options.now ?? Date.now;
    this.#timeoutMs = options.timeoutMs ?? 6_000;
    if (typeof this.#fetch !== 'function' || typeof this.#now !== 'function' ||
        !Number.isInteger(this.#timeoutMs) || this.#timeoutMs < 1 || this.#timeoutMs > 8_000) {
      throw new MarketEstimateError('MARKET_UNAVAILABLE');
    }
  }

  async quote(input: StockEstimateInput): Promise<RaydiumStockQuote> {
    validateStockEstimateInput(input);
    const request = Object.freeze({...input});
    const started = this.#now();
    if (!Number.isSafeInteger(started) || started < 0 || started > 8_639_999_999_990_000) {
      throw new MarketEstimateError('MARKET_UNAVAILABLE');
    }
    if (this.#inFlight || started < this.#nextRequestAt) throw new MarketEstimateError('MARKET_RATE_LIMITED');
    this.#inFlight = true;
    this.#nextRequestAt = started + requestSpacingMs;
    const controller = new AbortController();
    let rejectDeadline: (error: Error) => void = () => undefined;
    const deadline = new Promise<never>((_resolve, reject) => { rejectDeadline = reject; });
    const timer = setTimeout(() => {
      controller.abort();
      rejectDeadline(new MarketEstimateError('MARKET_TIMEOUT'));
    }, this.#timeoutMs);
    let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
    let response: Response | undefined;
    try {
      const from = request.side === 'buy' ? USDC : AAPLX;
      const to = request.side === 'buy' ? AAPLX : USDC;
      const url = new URL(RAYDIUM_STOCK_QUOTE_CONFIGURATION.endpoint);
      url.search = new URLSearchParams({
        inputMint: from.mint,
        outputMint: to.mint,
        amount: request.amountRaw,
        slippageBps: String(RAYDIUM_STOCK_QUOTE_CONFIGURATION.slippageBps),
        txVersion: RAYDIUM_STOCK_QUOTE_CONFIGURATION.transactionVersion,
      }).toString();
      const pending = this.#fetch(url, {
        method: 'GET', redirect: 'error', signal: controller.signal,
        headers: {accept: 'application/json', 'user-agent': 'Trimmy-ReadOnly-Research/1.0'},
      });
      void pending.then((late) => {
        if (controller.signal.aborted) void late.body?.cancel().catch(() => undefined);
      }, () => undefined);
      response = await Promise.race([pending, deadline]);
      if (response.redirected) invalid();
      if (response.url !== '') {
        let finalUrl: URL;
        try { finalUrl = new URL(response.url); }
        catch { invalid(); }
        if (finalUrl.origin !== 'https://transaction-v1.raydium.io' ||
            finalUrl.pathname !== '/compute/swap-base-in') invalid();
      }
      if (response.status === 429) {
        const observed = this.#now();
        const cooldownBase = Number.isSafeInteger(observed) && observed >= started ? observed : started;
        this.#nextRequestAt = Math.max(this.#nextRequestAt, cooldownBase + providerCooldownMs);
        throw new MarketEstimateError('MARKET_RATE_LIMITED');
      }
      if (!response.ok) throw new MarketEstimateError('MARKET_PROVIDER_UNAVAILABLE');
      if (!/^application\/json(?:\s*;|$)/i.test(response.headers.get('content-type') ?? '') || !response.body) invalid();
      const contentLength = response.headers.get('content-length');
      if (contentLength !== null && (/^(0|[1-9]\d*)$/.exec(contentLength)?.[0] !== contentLength ||
          Number(contentLength) > maximumBodyBytes)) invalid();
      reader = response.body.getReader();
      const chunks: Uint8Array[] = [];
      let bytes = 0;
      while (true) {
        const part = await Promise.race([reader.read(), deadline]);
        if (part.done) break;
        bytes += part.value.byteLength;
        if (bytes > maximumBodyBytes) invalid();
        chunks.push(part.value);
      }
      const payload: unknown = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(Buffer.concat(chunks)));
      if (controller.signal.aborted) throw new MarketEstimateError('MARKET_TIMEOUT');
      return parseQuote(payload, request, started, this.#now());
    } catch (error) {
      if (controller.signal.aborted) throw new MarketEstimateError('MARKET_TIMEOUT');
      if (error instanceof MarketEstimateError) throw error;
      if (error instanceof SyntaxError || error instanceof TypeError && reader !== undefined) invalid();
      throw new MarketEstimateError('MARKET_PROVIDER_UNAVAILABLE');
    } finally {
      clearTimeout(timer);
      controller.abort();
      if (reader) void reader.cancel().catch(() => undefined);
      else if (response?.body) void response.body.cancel().catch(() => undefined);
      this.#inFlight = false;
    }
  }
}

export function readRaydiumStockQuotes(env: Readonly<Record<string, string | undefined>>): RaydiumStockQuoteReader | undefined {
  const mode = env['TRIMMY_RAYDIUM_STOCK_QUOTES'];
  if (mode === undefined || mode === '' || mode === 'disabled') return undefined;
  if (mode !== 'read_only' || env['RAYDIUM_API_KEY'] || env['RAYDIUM_API_URL']) {
    throw new MarketEstimateError('MARKET_UNAVAILABLE');
  }
  return new RaydiumStockQuoteReader();
}
