import type {AcceptedPaperPrice, PaperPriceReader} from './paper-price-reader.js';
import {validateAcceptedPaperPrice} from './paper-trading-repository.js';
import type {PaperPortfolio, PaperPosition} from './paper-trading-repository.js';

export const PAPER_PORTFOLIO_V2_MEDIA_TYPE =
  'application/vnd.trimmy.paper-portfolio.v2+json';

export const PAPER_PORTFOLIO_MAX_PRICE_READS = 8;
export const PAPER_PORTFOLIO_MAX_CONCURRENT_PRICE_READS = 6;
export const PAPER_PORTFOLIO_VALUATION_DEADLINE_MS = 8_000;

export type PaperPortfolioValuationStatus =
  | 'complete'
  | 'partial'
  | 'unavailable';

export interface PaperPositionValuation {
  readonly assetId: string;
  readonly variantMint: string;
  readonly status: 'priced' | 'unavailable';
  readonly pricePaperMicros: string | null;
  readonly marketValuePaperMicros: string | null;
  readonly unrealizedGainPaperMicros: string | null;
  readonly observedAt: string | null;
  readonly acceptedAt: string | null;
  readonly expiresAt: string | null;
}

export interface PaperPortfolioValuation {
  readonly status: PaperPortfolioValuationStatus;
  readonly portfolioRevision: number;
  readonly openPositionCount: number;
  readonly pricedPositionCount: number;
  readonly cashPaperMicros: string;
  /** Cash plus only the positions whose current price was accepted. */
  readonly knownValuePaperMicros: string;
  /** Present only when every open position was priced. */
  readonly totalPaperMicros: string | null;
  readonly positions: readonly PaperPositionValuation[];
}

export interface PaperPortfolioValuationOptions {
  readonly deadlineMs?: number;
  readonly maxPriceReads?: number;
  readonly now?: () => number;
}

const paperScale = 1_000_000n;
const stoppedResult = Symbol('paper-portfolio-valuation-stopped');
const unsignedStoredAmount = /^(0|[1-9][0-9]{0,29})$/u;

function configuredInteger(
  value: number,
  minimum: number,
  maximum: number,
  name: string,
): number {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    throw new TypeError(`${name} is invalid.`);
  }
  return value;
}

function timestamp(now: () => number): number {
  let value: number;
  try {
    value = now();
  } catch {
    throw new TypeError('Paper portfolio valuation clock is unavailable.');
  }
  if (!Number.isSafeInteger(value) || value < 0 || value > 8_639_999_999_000_000) {
    throw new TypeError('Paper portfolio valuation clock is invalid.');
  }
  return value;
}

class MonotonicValuationClock {
  readonly #now: () => number;
  #last: number | undefined;
  #failed = false;

  constructor(now: () => number) { this.#now = now; }
  get failed(): boolean { return this.#failed; }

  read(): number {
    if (this.#failed) throw new TypeError('Paper portfolio valuation clock is unavailable.');
    let value: number;
    try { value = timestamp(this.#now); }
    catch (error) { this.#failed = true; throw error; }
    if (this.#last !== undefined && value < this.#last) {
      this.#failed = true;
      throw new TypeError('Paper portfolio valuation clock regressed.');
    }
    this.#last = value;
    return value;
  }
}

function amount(value: string): bigint {
  if (!unsignedStoredAmount.test(value)) {
    throw new TypeError('Paper portfolio amount is invalid.');
  }
  return BigInt(value);
}

function canonicalInstant(value: string): number | null {
  const parsed = Date.parse(value);
  return Number.isSafeInteger(parsed) && new Date(parsed).toISOString() === value
    ? parsed
    : null;
}

function unavailable(position: PaperPosition): PaperPositionValuation {
  return Object.freeze({
    assetId: position.assetId,
    variantMint: position.variantMint,
    status: 'unavailable' as const,
    pricePaperMicros: null,
    marketValuePaperMicros: null,
    unrealizedGainPaperMicros: null,
    observedAt: null,
    acceptedAt: null,
    expiresAt: null,
  });
}

async function readPrice(
  position: PaperPosition,
  prices: PaperPriceReader,
  clock: MonotonicValuationClock,
  admittedAt: number,
  signal: AbortSignal,
): Promise<AcceptedPaperPrice | null> {
  try {
    const value = await prices.read({
      assetId: position.assetId,
      variantMint: position.variantMint,
      signal,
    });
    if (signal.aborted) return null;
    const accepted = validateAcceptedPaperPrice(value);
    if (accepted.assetId !== position.assetId || accepted.variantMint !== position.variantMint) {
      return null;
    }
    const observedAt = canonicalInstant(accepted.source.observedAt);
    const acceptedAt = canonicalInstant(accepted.source.acceptedAt);
    const expiresAt = canonicalInstant(accepted.expiresAt);
    const readAt = clock.read();
    if (observedAt === null || acceptedAt === null || expiresAt === null ||
        acceptedAt > readAt + 5_000 ||
        observedAt < acceptedAt - 10_000 || observedAt > acceptedAt + 5_000 ||
        expiresAt <= acceptedAt || expiresAt > acceptedAt + 60_000 ||
        admittedAt >= expiresAt || readAt >= expiresAt) {
      return null;
    }
    return accepted;
  } catch {
    // A market read can degrade this display projection, never the ledger read.
    return null;
  }
}

function pricePosition(
  position: PaperPosition,
  accepted: AcceptedPaperPrice,
): PaperPositionValuation | null {
  try {
    const quantity = amount(position.quantityMicros);
    const costBasis = amount(position.costBasisPaperMicros);
    const price = amount(accepted.pricePaperMicros);
    const marketValue = quantity * price / paperScale;
    const unrealizedGain = marketValue - costBasis;
    return Object.freeze({
      assetId: position.assetId,
      variantMint: position.variantMint,
      status: 'priced' as const,
      pricePaperMicros: price.toString(),
      marketValuePaperMicros: marketValue.toString(),
      unrealizedGainPaperMicros: unrealizedGain.toString(),
      observedAt: accepted.source.observedAt,
      acceptedAt: accepted.source.acceptedAt,
      expiresAt: accepted.expiresAt,
    });
  } catch {
    return null;
  }
}

/**
 * Composes an exact ledger snapshot with bounded, display-only current prices.
 * It never writes a price, balance, position or Career event.
 */
export async function valuePaperPortfolio(
  portfolio: PaperPortfolio,
  prices: PaperPriceReader,
  options: PaperPortfolioValuationOptions = {},
): Promise<PaperPortfolioValuation> {
  const deadlineMs = configuredInteger(
    options.deadlineMs ?? PAPER_PORTFOLIO_VALUATION_DEADLINE_MS,
    1,
    30_000,
    'Paper portfolio valuation deadline',
  );
  const maxPriceReads = configuredInteger(
    options.maxPriceReads ?? PAPER_PORTFOLIO_MAX_PRICE_READS,
    1,
    PAPER_PORTFOLIO_MAX_PRICE_READS,
    'Paper portfolio price-read limit',
  );
  const clock = new MonotonicValuationClock(options.now ?? Date.now);
  const admittedAt = clock.read();
  const cash = amount(portfolio.cashPaperMicros);
  const openPositions = portfolio.positions.filter(position =>
    amount(position.quantityMicros) > 0n);
  const valuations = openPositions.map(unavailable);

  if (openPositions.length > 0) {
    const groups: Array<{position: PaperPosition; indexes: number[]}> = [];
    const groupsByKey = new Map<string, {position: PaperPosition; indexes: number[]}>();
    for (let index = 0; index < openPositions.length; index++) {
      const position = openPositions[index]!;
      const key = JSON.stringify([position.assetId, position.variantMint]);
      const existing = groupsByKey.get(key);
      if (existing) {
        existing.indexes.push(index);
      } else if (groups.length < maxPriceReads) {
        const group = {position, indexes: [index]};
        groupsByKey.set(key, group);
        groups.push(group);
      }
    }

    const controller = new AbortController();
    let stopped = false;
    let resolveStopped!: (value: typeof stoppedResult) => void;
    const stoppedPromise = new Promise<typeof stoppedResult>(resolve => {
      resolveStopped = resolve;
    });
    const stopReads = () => {
      if (stopped) return;
      stopped = true;
      controller.abort();
      resolveStopped(stoppedResult);
    };
    const timer = setTimeout(stopReads, deadlineMs);
    try {
      let nextGroup = 0;
      const worker = async () => {
        while (!controller.signal.aborted) {
          const group = groups[nextGroup++];
          if (!group) return;
          const result = await Promise.race([
            readPrice(group.position, prices, clock, admittedAt, controller.signal),
            stoppedPromise,
          ]);
          if (result === stoppedResult || controller.signal.aborted) return;
          if (clock.failed) {
            stopReads();
            return;
          }
          if (result !== null) {
            for (const index of group.indexes) {
              const valued = pricePosition(openPositions[index]!, result);
              if (valued !== null) valuations[index] = valued;
            }
          }
        }
      };
      const workerCount = Math.min(PAPER_PORTFOLIO_MAX_CONCURRENT_PRICE_READS, groups.length);
      await Promise.all(Array.from({length: workerCount}, worker));
    } finally {
      clearTimeout(timer);
      stopReads();
    }
  }

  let completionAt: number | null = null;
  try { completionAt = clock.read(); }
  catch { /* A regressing or invalid clock invalidates every display price. */ }
  for (let index = 0; index < valuations.length; index++) {
    const row = valuations[index]!;
    const expiresAt = row.expiresAt === null ? null : canonicalInstant(row.expiresAt);
    if (clock.failed || completionAt === null ||
        row.status === 'priced' && (expiresAt === null || completionAt >= expiresAt)) {
      valuations[index] = unavailable(openPositions[index]!);
    }
  }

  const priced = valuations.filter(row => row.status === 'priced');
  const knownValue = priced.reduce(
    (total, row) => total + BigInt(row.marketValuePaperMicros!),
    cash,
  );
  const status: PaperPortfolioValuationStatus = priced.length === openPositions.length
    ? 'complete'
    : priced.length === 0 ? 'unavailable' : 'partial';
  return Object.freeze({
    status,
    portfolioRevision: portfolio.revision,
    openPositionCount: openPositions.length,
    pricedPositionCount: priced.length,
    cashPaperMicros: cash.toString(),
    knownValuePaperMicros: knownValue.toString(),
    totalPaperMicros: status === 'complete' ? knownValue.toString() : null,
    positions: Object.freeze(valuations),
  });
}

/** Old clients receive their exact v1 response unless they explicitly opt in. */
export function acceptsPaperPortfolioV2(accept: unknown): boolean {
  if (typeof accept !== 'string' || accept.length === 0 || accept.length > 2048 ||
      /["\\\u0000-\u001f\u007f]/u.test(accept)) return false;
  let accepted = false;
  for (const rawPart of accept.split(',')) {
    const part = rawPart.trim();
    if (part.length === 0) return false;
    const semicolon = part.indexOf(';');
    const mediaRange = (semicolon < 0 ? part : part.slice(0, semicolon)).trim().toLowerCase();
    if (mediaRange !== PAPER_PORTFOLIO_V2_MEDIA_TYPE) continue;
    if (accepted) return false;
    accepted = true;
    if (semicolon < 0) continue;
    const parameter = part.slice(semicolon + 1).trim();
    const match = /^q=(0(?:\.[0-9]{0,3})?|1(?:\.0{0,3})?)$/iu.exec(parameter);
    if (!match || Number(match[1]) <= 0) return false;
  }
  return accepted;
}
