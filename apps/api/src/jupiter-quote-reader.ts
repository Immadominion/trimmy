import { parseRawAmount } from '@trimmy/domain';

/** Pinned public mainnet research mints; this is not an approved trading catalog.
 * AAPLx issuer identity/8 decimals were inspected in STOCK_MINT_INSPECTION.json.
 * https://api.xstocks.fi/api/v2/public/assets/AAPLx
 * https://developers.circle.com/stablecoins/usdc-contract-addresses
 */
export const JUPITER_QUOTE_ASSETS = Object.freeze({
  SOL: Object.freeze({symbol: 'SOL', mint: 'So11111111111111111111111111111111111111112', decimals: 9, maxInputRaw: '1000000000'}),
  USDC: Object.freeze({symbol: 'USDC', mint: 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v', decimals: 6, maxInputRaw: '100000000'}),
  AAPLx: Object.freeze({symbol: 'AAPLx', mint: 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', decimals: 8, maxInputRaw: '100000000'}),
});
export interface JupiterQuoteInput {
  readonly inputAsset: keyof typeof JUPITER_QUOTE_ASSETS;
  readonly outputAsset: keyof typeof JUPITER_QUOTE_ASSETS;
  readonly amountRaw: string;
}
export interface MarketEstimate {
  readonly schemaVersion: 1;
  readonly kind: 'indicative';
  readonly network: 'solana:mainnet-beta';
  readonly provider: 'jupiter-swap-v2';
  readonly executable: false;
  readonly walletChecked: false;
  readonly networkFees: null;
  readonly input: {readonly symbol: string; readonly mint: string; readonly decimals: number; readonly amountRaw: string};
  readonly output: {readonly symbol: string; readonly mint: string; readonly decimals: number; readonly estimatedAmountRaw: string; readonly quotedMinimumAmountRaw: string};
  readonly slippageBps: number;
  readonly swapFee: {readonly basisPoints: number; readonly mint: string};
  readonly router: 'metis' | 'jupiterz' | 'dflow' | 'okx';
  readonly requestedAt: string;
  readonly receivedAt: string;
  /** Local display refresh deadline, NOT a transaction validity guarantee. */
  readonly refreshAfter: string;
  readonly providerExpiresAt: string | null;
}
export type MarketEstimateErrorCode = 'MARKET_INPUT_INVALID' | 'MARKET_UNAVAILABLE' | 'MARKET_RATE_LIMITED' | 'MARKET_PROVIDER_AUTH_FAILED' | 'MARKET_PROVIDER_UNAVAILABLE' | 'MARKET_RESPONSE_INVALID' | 'MARKET_TIMEOUT' | 'MARKET_ESTIMATE_STALE';
const messages: Record<MarketEstimateErrorCode, string> = {
  MARKET_INPUT_INVALID: 'Choose a supported pair and a valid amount.',
  MARKET_UNAVAILABLE: 'Market estimates are not configured.',
  MARKET_RATE_LIMITED: 'Wait before requesting another estimate.',
  MARKET_PROVIDER_AUTH_FAILED: 'The market provider configuration needs attention.',
  MARKET_PROVIDER_UNAVAILABLE: 'The market provider is unavailable. Try again later.',
  MARKET_RESPONSE_INVALID: 'The market provider returned an unusable estimate.',
  MARKET_TIMEOUT: 'The market estimate took too long. Request a fresh estimate.',
  MARKET_ESTIMATE_STALE: 'The estimate is stale. Request a fresh estimate.',
};
export class MarketEstimateError extends Error {
  constructor(readonly code: MarketEstimateErrorCode) { super(messages[code]); this.name = 'MarketEstimateError'; }
}
function invalid(): never { throw new MarketEstimateError('MARKET_RESPONSE_INVALID'); }
function validateJupiterQuoteInput(input: JupiterQuoteInput): void {
  if (!input || !Object.hasOwn(JUPITER_QUOTE_ASSETS, input.inputAsset) ||
      !Object.hasOwn(JUPITER_QUOTE_ASSETS, input.outputAsset) || input.inputAsset === input.outputAsset ||
      (input.inputAsset !== 'USDC' && input.outputAsset !== 'USDC') ||
      Object.keys(input).some((key) => !['inputAsset', 'outputAsset', 'amountRaw'].includes(key))) {
    throw new MarketEstimateError('MARKET_INPUT_INVALID');
  }
  try {
    const amount = parseRawAmount(input.amountRaw);
    if (amount <= 0n || amount > BigInt(JUPITER_QUOTE_ASSETS[input.inputAsset].maxInputRaw)) throw new Error();
  } catch { throw new MarketEstimateError('MARKET_INPUT_INVALID'); }
}

export type JupiterEstimateAccess = {readonly kind: 'keyless_research'} | {readonly kind: 'api_key'; readonly apiKey: string};
export interface JupiterEstimateOptions {
  readonly access: JupiterEstimateAccess;
  readonly fetch?: typeof globalThis.fetch;
  readonly now?: () => number;
  readonly timeoutMs?: number;
}
const endpoint = 'https://api.jup.ag/swap/v2/order';
/**
 * Every research quote asks for the same tolerance. Without it the provider
 * quotes zero slippage, the minimum output equals the estimate, and a fresh
 * order a few seconds later is refused for being one tick lower. Half a percent
 * makes the quoted minimum a real floor the order binder can hold to.
 */
export const JUPITER_RESEARCH_SLIPPAGE_BPS = 50;
const maxBytes = 262_144;
const refreshWindowMs = 10_000;

/** Quote-only GET: never sends a taker, accepts a transaction or calls execute.
 * https://developers.jup.ag/docs/swap/order-and-execute
 * https://developers.jup.ag/docs/portal/plans
 * Per-instance pacing is deliberately conservative; public deployment also needs
 * a shared gateway budget across processes and clients.
 */
export class JupiterQuoteReader {
  readonly #access: JupiterEstimateAccess;
  readonly #fetch: typeof globalThis.fetch;
  readonly #now: () => number;
  readonly #timeoutMs: number;
  #nextRequestAt = 0;
  #inFlight = false;
  constructor(options: JupiterEstimateOptions) {
    if (!['keyless_research', 'api_key'].includes(options.access.kind) ||
        (options.access.kind === 'api_key' && (typeof options.access.apiKey !== 'string' ||
          /^[A-Za-z0-9._~-]{8,512}$/.exec(options.access.apiKey)?.[0] !== options.access.apiKey))) {
      throw new MarketEstimateError('MARKET_UNAVAILABLE');
    }
    this.#access = Object.freeze({...options.access});
    this.#fetch = options.fetch ?? globalThis.fetch;
    this.#now = options.now ?? Date.now;
    this.#timeoutMs = options.timeoutMs ?? 6000;
    if (!Number.isInteger(this.#timeoutMs) || this.#timeoutMs < 1 || this.#timeoutMs > 8000) throw new MarketEstimateError('MARKET_UNAVAILABLE');
  }
  async estimate(input: JupiterQuoteInput): Promise<MarketEstimate> {
    validateJupiterQuoteInput(input);
    const request = Object.freeze({...input});
    const started = this.#now();
    if (!Number.isSafeInteger(started) || started < 0 || started > 8_639_999_999_990_000) throw new MarketEstimateError('MARKET_UNAVAILABLE');
    if (this.#inFlight || started < this.#nextRequestAt) throw new MarketEstimateError('MARKET_RATE_LIMITED');
    this.#inFlight = true;
    this.#nextRequestAt = started + 2100;
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
      const url = new URL(endpoint);
      url.search = new URLSearchParams({
        inputMint: JUPITER_QUOTE_ASSETS[request.inputAsset].mint,
        outputMint: JUPITER_QUOTE_ASSETS[request.outputAsset].mint,
        amount: request.amountRaw,
        slippageBps: String(JUPITER_RESEARCH_SLIPPAGE_BPS),
      }).toString();
      const headers: Record<string, string> = {accept: 'application/json'};
      if (this.#access.kind === 'api_key') headers['x-api-key'] = this.#access.apiKey;
      // Race fetch and every body read; abort alone cannot bound injected transports.
      const pending = this.#fetch(url, {method: 'GET', headers, redirect: 'error', signal: controller.signal});
      void pending.then((late) => {
        if (controller.signal.aborted) void late.body?.cancel().catch(() => undefined);
      }, () => undefined);
      response = await Promise.race([pending, deadline]);
      if (response.status === 401 || response.status === 403) throw new MarketEstimateError('MARKET_PROVIDER_AUTH_FAILED');
      if (response.status === 429) {
        this.#nextRequestAt = Math.max(this.#nextRequestAt, this.#now() + 60_000);
        throw new MarketEstimateError('MARKET_RATE_LIMITED');
      }
      if (!response.ok) throw new MarketEstimateError('MARKET_PROVIDER_UNAVAILABLE');
      if (!/^application\/json(?:\s*;|$)/i.test(response.headers.get('content-type') ?? '') || !response.body) invalid();
      const length = response.headers.get('content-length');
      if (length !== null && (!/^\d+$/.test(length) || Number(length) > maxBytes)) invalid();
      reader = response.body.getReader();
      const chunks: Uint8Array[] = [];
      let bytes = 0;
      while (true) {
        const part = await Promise.race([reader.read(), deadline]);
        if (part.done) break;
        bytes += part.value.byteLength;
        if (bytes > maxBytes) invalid();
        chunks.push(part.value);
      }
      const payload: unknown = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(Buffer.concat(chunks)));
      if (controller.signal.aborted) throw new MarketEstimateError('MARKET_TIMEOUT');
      return parseEstimate(payload, request, started, this.#now());
    } catch (error) {
      if (controller.signal.aborted) throw new MarketEstimateError('MARKET_TIMEOUT');
      if (error instanceof MarketEstimateError) throw error;
      // Provider errors and response text never enter logs or client responses.
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
export function parseEstimate(payload: unknown, input: JupiterQuoteInput, started: number, received: number): MarketEstimate {
  if (!Number.isSafeInteger(received) || received < started || received >= started + refreshWindowMs) throw new MarketEstimateError('MARKET_ESTIMATE_STALE');
  if (payload === null || typeof payload !== 'object' || Array.isArray(payload)) invalid();
  const data = payload as Record<string, unknown>;
  const from = JUPITER_QUOTE_ASSETS[input.inputAsset];
  const to = JUPITER_QUOTE_ASSETS[input.outputAsset];
  if (data['inputMint'] !== from.mint || data['outputMint'] !== to.mint || data['inAmount'] !== input.amountRaw ||
      data['swapMode'] !== 'ExactIn' || data['transaction'] !== null || data['taker'] !== null ||
      data['errorCode'] !== undefined || data['error'] !== undefined || data['errorMessage'] !== undefined) invalid();
  const out = data['outAmount']; const minimum = data['otherAmountThreshold'];
  try {
    if (typeof out !== 'string' || typeof minimum !== 'string' || parseRawAmount(out) <= 0n ||
        parseRawAmount(minimum) <= 0n || parseRawAmount(minimum) > parseRawAmount(out)) invalid();
  } catch { invalid(); }
  const slippage = data['slippageBps']; const fee = data['feeBps']; const feeMint = data['feeMint']; const router = data['router'];
  // The provider must echo the requested tolerance; any other value is not our floor.
  if (slippage !== JUPITER_RESEARCH_SLIPPAGE_BPS ||
      typeof fee !== 'number' || !Number.isInteger(fee) || fee < 0 || fee > 10_000 ||
      typeof feeMint !== 'string' || (feeMint !== from.mint && feeMint !== to.mint) ||
      typeof router !== 'string' || !['metis', 'jupiterz', 'dflow', 'okx'].includes(router)) invalid();
  // Both values are provider estimates, but an incoherent threshold cannot be shown.
  if (BigInt(minimum as string) < BigInt(out as string) * BigInt(10_000 - slippage) / 10_000n) invalid();
  let expires: number | null = null;
  if (data['expireAt'] !== undefined && data['expireAt'] !== null) {
    const raw = data['expireAt'];
    if (typeof raw !== 'string' || raw.length > 40 || !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,3})?Z$/.test(raw)) invalid();
    expires = Date.parse(raw);
    if (!Number.isFinite(expires)) invalid();
    const canonical = raw.includes('.') ? raw.replace(/\.(\d{1,3})Z$/, (_match, fraction: string) => `.${fraction.padEnd(3, '0')}Z`) : raw.replace('Z', '.000Z');
    if (new Date(expires).toISOString() !== canonical) invalid();
    if (expires <= received) throw new MarketEstimateError('MARKET_ESTIMATE_STALE');
  }
  return Object.freeze({
    schemaVersion: 1, kind: 'indicative', network: 'solana:mainnet-beta', provider: 'jupiter-swap-v2',
    executable: false, walletChecked: false, networkFees: null,
    input: Object.freeze({symbol: from.symbol, mint: from.mint, decimals: from.decimals, amountRaw: input.amountRaw}),
    output: Object.freeze({symbol: to.symbol, mint: to.mint, decimals: to.decimals, estimatedAmountRaw: out as string, quotedMinimumAmountRaw: minimum as string}),
    slippageBps: slippage, swapFee: Object.freeze({basisPoints: fee, mint: feeMint}), router: router as MarketEstimate['router'],
    requestedAt: new Date(started).toISOString(), receivedAt: new Date(received).toISOString(),
    refreshAfter: new Date(Math.min(started + refreshWindowMs, expires ?? Infinity)).toISOString(),
    providerExpiresAt: expires === null ? null : new Date(expires).toISOString(),
  });
}


export function readJupiterQuoteReader(env: Readonly<Record<string, string | undefined>>): JupiterQuoteReader | undefined {
  const mode = env['TRIMMY_MARKET_QUOTES'];
  if (mode === undefined || mode === '' || mode === 'disabled') return undefined;
  if (mode === 'keyless_research') {
    if (env['JUPITER_API_KEY']) throw new MarketEstimateError('MARKET_UNAVAILABLE');
    return new JupiterQuoteReader({access: {kind: 'keyless_research'}});
  }
  if (mode === 'api_key' && env['JUPITER_API_KEY']) return new JupiterQuoteReader({access: {kind: 'api_key', apiKey: env['JUPITER_API_KEY']}});
  throw new MarketEstimateError('MARKET_UNAVAILABLE');
}
