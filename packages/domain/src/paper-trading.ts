import { DomainError } from './domain-error.js';

/** Paper balances, share quantities and accepted prices all use six decimal places. */
export const PAPER_FIXED_SCALE = 1_000_000n;
export const PAPER_FIXED_SCALE_DIGITS = 6;
export const PAPER_STARTING_CASH_MICROS = 10_000n * PAPER_FIXED_SCALE;
/** One billion whole units is deliberately beyond the game while bounding every product. */
export const PAPER_FIXED_MAX = 999_999_999_999_999n;

export type PaperOrderAction = 'buy' | 'sell' | 'trim';
export type PaperOrderAmount =
  | {readonly kind: 'paper_amount'; readonly paperMicros: string}
  | {readonly kind: 'share_quantity'; readonly quantityMicros: string};

export interface PaperPositionState {
  readonly quantityMicros: string;
  readonly costBasisPaperMicros: string;
}

export interface PaperOrderCalculation {
  readonly action: PaperOrderAction;
  readonly pricePaperMicros: string;
  readonly quantityMicros: string;
  readonly cashDebitPaperMicros: string;
  readonly cashCreditPaperMicros: string;
  readonly cashAfterPaperMicros: string;
  readonly positionQuantityAfterMicros: string;
  readonly positionCostBasisAfterPaperMicros: string;
  /** Signed decimal integer text. A loss starts with `-`; zero and gains do not. */
  readonly realizedGainDeltaPaperMicros: string;
  /** Only a profitable partial `trim` contributes here. Career rewards are separate. */
  readonly lockedGainDeltaPaperMicros: string;
}

function fail(code: string, message: string): never {
  throw new DomainError(code, message);
}

/** Canonical, exact fixed-point text. JSON numbers never cross this boundary. */
export function parsePaperFixed(value: unknown, options: {readonly positive?: boolean} = {}): bigint {
  if (typeof value !== 'string' || /^(0|[1-9][0-9]{0,14})$/u.exec(value)?.[0] !== value) {
    return fail('PAPER_AMOUNT_INVALID', 'Paper amounts must be canonical fixed-point integer strings.');
  }
  const parsed = BigInt(value);
  if (parsed > PAPER_FIXED_MAX || options.positive && parsed === 0n) {
    return fail('PAPER_AMOUNT_INVALID', 'Paper amount is outside the supported range.');
  }
  return parsed;
}

export function parsePaperSignedFixed(value: unknown): bigint {
  if (typeof value !== 'string' || /^-?(0|[1-9][0-9]{0,14})$/u.exec(value)?.[0] !== value || value === '-0') {
    return fail('PAPER_AMOUNT_INVALID', 'Signed paper amount is invalid.');
  }
  const parsed = BigInt(value);
  if (parsed < -PAPER_FIXED_MAX || parsed > PAPER_FIXED_MAX) {
    return fail('PAPER_AMOUNT_INVALID', 'Signed paper amount is outside the supported range.');
  }
  return parsed;
}

export function parsePaperAssetId(value: unknown): string {
  if (typeof value !== 'string' || value.length > 100 ||
      /^[a-z0-9]+(?:-[a-z0-9]+)*$/u.exec(value)?.[0] !== value) {
    return fail('PAPER_ASSET_INVALID', 'Paper stock identifier is invalid.');
  }
  return value;
}

/** Encoding and length only. Provider acceptance remains a server-side decision. */
export function parsePaperVariantMint(value: unknown): string {
  if (typeof value !== 'string' || value.length < 32 || value.length > 44 ||
      /^[1-9A-HJ-NP-Za-km-z]+$/u.exec(value)?.[0] !== value) {
    return fail('PAPER_ASSET_INVALID', 'Paper stock variant is invalid.');
  }
  return value;
}

export function parsePaperSymbol(value: unknown): string {
  if (typeof value !== 'string' || value.length < 1 || value.length > 30 || value.trim() !== value ||
      /[\u0000-\u001f\u007f]/u.test(value)) return fail('PAPER_ASSET_INVALID', 'Paper stock symbol is invalid.');
  return value;
}

export function parsePaperOrderAction(value: unknown): PaperOrderAction {
  if (value !== 'buy' && value !== 'sell' && value !== 'trim') {
    return fail('PAPER_ORDER_INVALID', 'Paper order action is invalid.');
  }
  return value;
}

export function parsePaperOrderAmount(value: unknown): PaperOrderAmount {
  if (value === null || typeof value !== 'object' || Array.isArray(value) || Object.getPrototypeOf(value) !== Object.prototype) {
    return fail('PAPER_ORDER_INVALID', 'Paper order amount is invalid.');
  }
  const record = value as Record<string, unknown>;
  const keys = Object.keys(record);
  if (record['kind'] === 'paper_amount' && keys.length === 2 && keys.includes('paperMicros')) {
    const amount = parsePaperFixed(record['paperMicros'], {positive: true});
    return Object.freeze({kind: 'paper_amount', paperMicros: amount.toString()});
  }
  if (record['kind'] === 'share_quantity' && keys.length === 2 && keys.includes('quantityMicros')) {
    const amount = parsePaperFixed(record['quantityMicros'], {positive: true});
    return Object.freeze({kind: 'share_quantity', quantityMicros: amount.toString()});
  }
  return fail('PAPER_ORDER_INVALID', 'Paper order amount is invalid.');
}

const ceilDiv = (numerator: bigint, denominator: bigint) => (numerator + denominator - 1n) / denominator;
function bounded(value: bigint): bigint {
  if (value < 0n || value > PAPER_FIXED_MAX) return fail('PAPER_LIMIT_REACHED', 'Paper account limit has been reached.');
  return value;
}

/**
 * Deterministic ledger math.
 *
 * Buys round their debit up and sales round their credit down. A buy followed
 * by an unchanged-price sale therefore cannot manufacture paper from rounding.
 * Cost basis allocated to a partial sale rounds down; a final sale takes the
 * entire remainder, so basis is conserved exactly over the position lifetime.
 */
export function calculatePaperOrder(input: {
  readonly action: PaperOrderAction;
  readonly amount: PaperOrderAmount;
  readonly pricePaperMicros: string;
  readonly cashPaperMicros: string;
  readonly position: PaperPositionState;
}): PaperOrderCalculation {
  const action = parsePaperOrderAction(input.action);
  const amount = parsePaperOrderAmount(input.amount);
  const price = parsePaperFixed(input.pricePaperMicros, {positive: true});
  const cash = parsePaperFixed(input.cashPaperMicros);
  const oldQuantity = parsePaperFixed(input.position.quantityMicros);
  const oldBasis = parsePaperFixed(input.position.costBasisPaperMicros);
  if ((oldQuantity === 0n) !== (oldBasis === 0n)) {
    return fail('PAPER_POSITION_INVALID', 'Stored paper position is inconsistent.');
  }

  if (action === 'buy') {
    const quantity = amount.kind === 'paper_amount'
      ? parsePaperFixed(amount.paperMicros, {positive: true}) * PAPER_FIXED_SCALE / price
      : parsePaperFixed(amount.quantityMicros, {positive: true});
    if (quantity === 0n) return fail('PAPER_ORDER_TOO_SMALL', 'Paper order is too small at this price.');
    const debit = bounded(ceilDiv(price * quantity, PAPER_FIXED_SCALE));
    if (amount.kind === 'paper_amount' && debit > BigInt(amount.paperMicros)) {
      return fail('PAPER_ORDER_INVALID', 'Paper amount cannot cover its calculated quantity.');
    }
    if (debit > cash) return fail('PAPER_CASH_INSUFFICIENT', 'There is not enough paper on this desk.');
    const nextQuantity = bounded(oldQuantity + quantity);
    const nextBasis = bounded(oldBasis + debit);
    return Object.freeze({
      action, pricePaperMicros: price.toString(), quantityMicros: quantity.toString(),
      cashDebitPaperMicros: debit.toString(), cashCreditPaperMicros: '0',
      cashAfterPaperMicros: (cash - debit).toString(), positionQuantityAfterMicros: nextQuantity.toString(),
      positionCostBasisAfterPaperMicros: nextBasis.toString(), realizedGainDeltaPaperMicros: '0',
      lockedGainDeltaPaperMicros: '0',
    });
  }

  if (amount.kind !== 'share_quantity') {
    return fail('PAPER_ORDER_INVALID', 'Sales and trims require a share quantity.');
  }
  const quantity = parsePaperFixed(amount.quantityMicros, {positive: true});
  if (oldQuantity === 0n || quantity > oldQuantity) {
    return fail('PAPER_POSITION_INSUFFICIENT', 'There are not enough paper shares on this desk.');
  }
  if (action === 'trim' && quantity === oldQuantity) {
    return fail('PAPER_TRIM_MUST_BE_PARTIAL', 'A trim keeps part of the position. Use sell to close it.');
  }
  const credit = bounded(price * quantity / PAPER_FIXED_SCALE);
  if (credit === 0n) return fail('PAPER_ORDER_TOO_SMALL', 'Paper order is too small at this price.');
  const allocatedBasis = quantity === oldQuantity ? oldBasis : oldBasis * quantity / oldQuantity;
  const realized = credit - allocatedBasis;
  if (action === 'trim' && realized <= 0n) {
    return fail('PAPER_TRIM_NOT_WINNING', 'Trim is available only for a profitable part of a position.');
  }
  const nextQuantity = oldQuantity - quantity;
  const nextBasis = oldBasis - allocatedBasis;
  const nextCash = bounded(cash + credit);
  if ((nextQuantity === 0n) !== (nextBasis === 0n)) {
    return fail('PAPER_POSITION_INVALID', 'Paper position could not be settled exactly.');
  }
  return Object.freeze({
    action, pricePaperMicros: price.toString(), quantityMicros: quantity.toString(),
    cashDebitPaperMicros: '0', cashCreditPaperMicros: credit.toString(),
    cashAfterPaperMicros: nextCash.toString(), positionQuantityAfterMicros: nextQuantity.toString(),
    positionCostBasisAfterPaperMicros: nextBasis.toString(), realizedGainDeltaPaperMicros: realized.toString(),
    lockedGainDeltaPaperMicros: action === 'trim' ? realized.toString() : '0',
  });
}
