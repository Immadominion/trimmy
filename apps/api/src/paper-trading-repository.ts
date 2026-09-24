import {
  DomainError, PAPER_FIXED_SCALE_DIGITS, PAPER_STARTING_CASH_MICROS, parseInstant,
  parsePaperAssetId, parsePaperFixed, parsePaperOrderAction, parsePaperOrderAmount,
  parsePaperSignedFixed, parsePaperSymbol, parsePaperVariantMint,
} from '@trimmy/domain';
import type { PaperOrderAction, PaperOrderAmount } from '@trimmy/domain';
import type { AcceptedPaperPrice } from './paper-price-reader.js';

export interface PaperPosition {
  readonly assetId: string;
  readonly variantMint: string;
  readonly symbol: string;
  readonly quantityMicros: string;
  readonly costBasisPaperMicros: string;
  /** Display helper rounded down; costBasisPaperMicros remains authoritative. */
  readonly averageCostPricePaperMicros: string;
  readonly realizedGainPaperMicros: string;
  readonly lockedGainPaperMicros: string;
  readonly updatedAt: string;
}

export interface PaperOrderPreview {
  readonly id: string;
  readonly requestId: string;
  /** Internal idempotency binding. Routes omit this field from responses. */
  readonly requestHash: string;
  readonly state: 'open' | 'committed';
  readonly accountRevision: number;
  readonly action: PaperOrderAction;
  readonly amount: PaperOrderAmount;
  readonly assetId: string;
  readonly variantMint: string;
  readonly symbol: string;
  readonly pricePaperMicros: string;
  readonly quantityMicros: string;
  readonly cashDebitPaperMicros: string;
  readonly cashCreditPaperMicros: string;
  readonly cashAfterPaperMicros: string;
  readonly positionQuantityAfterMicros: string;
  readonly positionCostBasisAfterPaperMicros: string;
  readonly realizedGainDeltaPaperMicros: string;
  readonly lockedGainDeltaPaperMicros: string;
  readonly source: AcceptedPaperPrice['source'];
  readonly expiresAt: string;
  readonly committedAt: string | null;
}

export interface PaperCommittedOrder {
  readonly id: string;
  readonly previewId: string;
  readonly accountRevision: number;
  readonly action: PaperOrderAction;
  readonly assetId: string;
  readonly variantMint: string;
  readonly symbol: string;
  readonly pricePaperMicros: string;
  readonly quantityMicros: string;
  readonly cashDebitPaperMicros: string;
  readonly cashCreditPaperMicros: string;
  readonly cashAfterPaperMicros: string;
  readonly positionQuantityAfterMicros: string;
  readonly positionCostBasisAfterPaperMicros: string;
  readonly realizedGainDeltaPaperMicros: string;
  readonly lockedGainDeltaPaperMicros: string;
  readonly source: AcceptedPaperPrice['source'];
  readonly committedAt: string;
}

export interface PaperPortfolio {
  readonly revision: number;
  readonly scaleDigits: typeof PAPER_FIXED_SCALE_DIGITS;
  readonly startingCashPaperMicros: string;
  readonly cashPaperMicros: string;
  readonly openedAt: string | null;
  readonly updatedAt: string | null;
  readonly positions: readonly PaperPosition[];
  readonly recentOrders: readonly PaperCommittedOrder[];
}

export interface PaperPreviewCommand {
  readonly id: string;
  readonly requestId: string;
  readonly requestHash: string;
  readonly action: PaperOrderAction;
  readonly amount: PaperOrderAmount;
  readonly price: AcceptedPaperPrice;
}

export interface PaperCommitCommand {
  readonly orderId: string;
  readonly previewId: string;
  readonly idempotencyKey: string;
  readonly requestHash: string;
}

export interface PaperResetCommand {
  readonly mutationId: string;
  readonly requestHash: string;
  readonly baseRevision: number;
}

/** Immutable acknowledgement of one completed paper desk reset. */
export interface PaperResetReceipt {
  readonly mutationId: string;
  readonly previousRevision: number;
  readonly revision: number;
  readonly cashPaperMicros: string;
  readonly resetAt: string;
}

export interface PaperTradingRepository {
  getPortfolio(userId: string): Promise<PaperPortfolio>;
  findPreviewRequest(userId: string, requestId: string): Promise<PaperOrderPreview | null>;
  createPreview(userId: string, command: PaperPreviewCommand): Promise<PaperOrderPreview>;
  commit(userId: string, command: PaperCommitCommand): Promise<PaperCommittedOrder>;
  /** Optional while older adapters are upgraded. Core paper reads and orders remain available without it. */
  reset?(userId: string, command: PaperResetCommand): Promise<PaperResetReceipt>;
}

export type PaperTradingRepositoryErrorCode = 'PAPER_INPUT_INVALID' | 'PAPER_ACCOUNT_NOT_FOUND' |
  'PAPER_ACCOUNT_UNAVAILABLE' | 'PAPER_IDEMPOTENCY_CONFLICT' | 'PAPER_PREVIEW_NOT_FOUND' |
  'PAPER_PREVIEW_EXPIRED' | 'PAPER_PREVIEW_ALREADY_COMMITTED' | 'PAPER_PORTFOLIO_CHANGED' |
  'PAPER_STORAGE_INVALID' | 'PAPER_RUNTIME_ROLE_INVALID' | 'PAPER_CASH_INSUFFICIENT' |
  'PAPER_POSITION_INSUFFICIENT' | 'PAPER_TRIM_NOT_WINNING' | 'PAPER_TRIM_MUST_BE_PARTIAL' |
  'PAPER_ORDER_TOO_SMALL' | 'PAPER_LIMIT_REACHED' | 'PAPER_RESET_NOT_NEEDED' |
  'PAPER_REVISION_EXHAUSTED';

export class PaperTradingRepositoryError extends Error {
  constructor(readonly code: PaperTradingRepositoryErrorCode, message: string) {
    super(message); this.name = 'PaperTradingRepositoryError';
  }
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;
export function parsePaperUuid(value: unknown): string {
  if (typeof value !== 'string' || uuidPattern.exec(value)?.[0] !== value) {
    throw new PaperTradingRepositoryError('PAPER_INPUT_INVALID', 'Paper request identifier is invalid.');
  }
  return value.toLowerCase();
}

export function parsePaperHash(value: unknown): string {
  if (typeof value !== 'string' || /^[a-f0-9]{64}$/u.exec(value)?.[0] !== value) {
    throw new PaperTradingRepositoryError('PAPER_INPUT_INVALID', 'Paper request binding is invalid.');
  }
  return value;
}

export function mapPaperDomainError(error: unknown): PaperTradingRepositoryError {
  const code = error instanceof DomainError ? error.code : 'PAPER_STORAGE_INVALID';
  const supported = new Set<PaperTradingRepositoryErrorCode>([
    'PAPER_CASH_INSUFFICIENT', 'PAPER_POSITION_INSUFFICIENT', 'PAPER_TRIM_NOT_WINNING',
    'PAPER_TRIM_MUST_BE_PARTIAL', 'PAPER_ORDER_TOO_SMALL', 'PAPER_LIMIT_REACHED',
  ]);
  return new PaperTradingRepositoryError(
    supported.has(code as PaperTradingRepositoryErrorCode) ? code as PaperTradingRepositoryErrorCode : 'PAPER_STORAGE_INVALID',
    'Paper order could not be calculated.',
  );
}

export function validateAcceptedPaperPrice(value: AcceptedPaperPrice): AcceptedPaperPrice {
  try {
    const assetId = parsePaperAssetId(value.assetId);
    const variantMint = parsePaperVariantMint(value.variantMint);
    const symbol = parsePaperSymbol(value.symbol);
    const pricePaperMicros = parsePaperFixed(value.pricePaperMicros, {positive: true}).toString();
    parseInstant(value.expiresAt); parseInstant(value.source.observedAt); parseInstant(value.source.acceptedAt);
    if (!value.source || value.source.provider !== 'tokens-xyz-v1' ||
        typeof value.source.providerReference !== 'string' || value.source.providerReference.length > 300 ||
        !value.source.providerReference.startsWith('/v1/assets/') ||
        !value.source.providerTimestamps || value.source.providerTimestamps.unit !== 'not_declared') {
      throw new Error();
    }
    for (const item of [value.source.marketSource, value.source.metricsSource]) {
      if (item !== null && (typeof item !== 'string' || item.length > 80 || item.trim() !== item)) throw new Error();
    }
    for (const stamp of [value.source.providerTimestamps.asOf, value.source.providerTimestamps.lastFetchedAt,
      value.source.providerTimestamps.lastTradeAt]) {
      if (stamp !== null && !/^(0|[1-9][0-9]{0,15})$/u.test(stamp)) throw new Error();
    }
    return Object.freeze({...value, assetId, variantMint, symbol, pricePaperMicros});
  } catch {
    throw new PaperTradingRepositoryError('PAPER_INPUT_INVALID', 'Accepted paper price is invalid.');
  }
}

export function emptyPaperPortfolio(): PaperPortfolio {
  return Object.freeze({
    revision: 0, scaleDigits: PAPER_FIXED_SCALE_DIGITS,
    startingCashPaperMicros: PAPER_STARTING_CASH_MICROS.toString(),
    cashPaperMicros: PAPER_STARTING_CASH_MICROS.toString(), openedAt: null, updatedAt: null,
    positions: Object.freeze([]), recentOrders: Object.freeze([]),
  });
}

/** Re-validates a storage projection before it crosses the repository boundary. */
export function validatePaperPreview(value: PaperOrderPreview): PaperOrderPreview {
  try {
    const id = parsePaperUuid(value.id), requestId = parsePaperUuid(value.requestId), requestHash = parsePaperHash(value.requestHash);
    if (!Number.isSafeInteger(value.accountRevision) || value.accountRevision < 0 ||
        (value.state !== 'open' && value.state !== 'committed') || (value.state === 'committed') !== (value.committedAt !== null)) throw new Error();
    const action = parsePaperOrderAction(value.action), amount = parsePaperOrderAmount(value.amount);
    parsePaperAssetId(value.assetId); parsePaperVariantMint(value.variantMint); parsePaperSymbol(value.symbol);
    for (const field of ['pricePaperMicros', 'quantityMicros', 'cashDebitPaperMicros', 'cashCreditPaperMicros',
      'cashAfterPaperMicros', 'positionQuantityAfterMicros', 'positionCostBasisAfterPaperMicros',
      'lockedGainDeltaPaperMicros'] as const) parsePaperFixed(value[field]);
    parsePaperSignedFixed(value.realizedGainDeltaPaperMicros);
    parseInstant(value.source.observedAt); parseInstant(value.source.acceptedAt); parseInstant(value.expiresAt);
    if (value.committedAt !== null) parseInstant(value.committedAt);
    return Object.freeze({...value, id, requestId, requestHash, action, amount});
  } catch {
    throw new PaperTradingRepositoryError('PAPER_STORAGE_INVALID', 'Stored paper preview is invalid.');
  }
}
