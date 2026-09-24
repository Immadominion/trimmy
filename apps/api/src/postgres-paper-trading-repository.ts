import { calculatePaperOrder, PAPER_FIXED_SCALE, PAPER_STARTING_CASH_MICROS,
  parsePaperFixed, parsePaperSignedFixed } from '@trimmy/domain';
import type { PaperOrderCalculation, PaperOrderAmount } from '@trimmy/domain';
import type { Pool, PoolClient, QueryResultRow } from 'pg';
import type { AcceptedPaperPrice } from './paper-price-reader.js';
import {
  PaperTradingRepositoryError, emptyPaperPortfolio, mapPaperDomainError, parsePaperHash, parsePaperUuid,
  validateAcceptedPaperPrice, validatePaperPreview,
} from './paper-trading-repository.js';
import type {
  PaperCommitCommand, PaperCommittedOrder, PaperOrderPreview, PaperPortfolio, PaperPosition,
  PaperPreviewCommand, PaperResetCommand, PaperResetReceipt, PaperTradingRepository,
} from './paper-trading-repository.js';

interface AccountRow extends QueryResultRow {
  revision: unknown; last_reset_revision: unknown; cash_micros: unknown; opened_at: unknown; updated_at: unknown;
}
interface PositionRow extends QueryResultRow {
  asset_id: unknown; variant_mint: unknown; symbol: unknown; quantity_micros: unknown; cost_basis_micros: unknown;
  realized_gain_micros: unknown; locked_gain_micros: unknown; updated_at: unknown;
}
interface PreviewRow extends QueryResultRow {
  id: unknown; request_id: unknown; request_hash: unknown; state: unknown; account_revision: unknown; action: unknown;
  input_kind: unknown; input_amount_micros: unknown; asset_id: unknown; variant_mint: unknown; symbol: unknown;
  price_micros: unknown; quantity_micros: unknown; cash_debit_micros: unknown; cash_credit_micros: unknown;
  cash_after_micros: unknown; position_quantity_after_micros: unknown; position_cost_basis_after_micros: unknown;
  realized_gain_delta_micros: unknown; locked_gain_delta_micros: unknown; price_source: unknown;
  accepted_at: unknown; expires_at: unknown; committed_at: unknown;
}
interface OrderRow extends QueryResultRow {
  id: unknown; preview_id: unknown; request_hash?: unknown; account_revision: unknown; action: unknown; asset_id: unknown;
  variant_mint: unknown; symbol: unknown; price_micros: unknown; quantity_micros: unknown;
  cash_debit_micros: unknown; cash_credit_micros: unknown; cash_after_micros: unknown;
  position_quantity_after_micros: unknown; position_cost_basis_after_micros: unknown;
  realized_gain_delta_micros: unknown; locked_gain_delta_micros: unknown; price_source: unknown; committed_at: unknown;
}
interface ResetRow extends QueryResultRow {
  outcome: unknown; mutation_id: unknown; previous_revision: unknown; revision: unknown;
  cash_micros: unknown; reset_at: unknown;
}
type ParsedResetOutcome =
  | {readonly kind: 'reset'; readonly receipt: PaperResetReceipt}
  | {readonly kind: 'not_needed'};

const instantSql = `to_char(%s AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')`;
const iso = (column: string) => instantSql.replace('%s', column);
const accountColumns = `revision::text AS revision, last_reset_revision::text AS last_reset_revision,
  cash_micros::text AS cash_micros,
  ${iso('opened_at')} AS opened_at, ${iso('updated_at')} AS updated_at`;
const positionColumns = `asset_id, variant_mint, symbol, quantity_micros::text AS quantity_micros,
  cost_basis_micros::text AS cost_basis_micros, realized_gain_micros::text AS realized_gain_micros,
  locked_gain_micros::text AS locked_gain_micros, ${iso('updated_at')} AS updated_at`;
const previewColumns = `id::text AS id, request_id::text AS request_id, request_hash, state,
  account_revision::text AS account_revision, action, input_kind, input_amount_micros::text AS input_amount_micros,
  asset_id, variant_mint, symbol, price_micros::text AS price_micros, quantity_micros::text AS quantity_micros,
  cash_debit_micros::text AS cash_debit_micros, cash_credit_micros::text AS cash_credit_micros,
  cash_after_micros::text AS cash_after_micros, position_quantity_after_micros::text AS position_quantity_after_micros,
  position_cost_basis_after_micros::text AS position_cost_basis_after_micros,
  realized_gain_delta_micros::text AS realized_gain_delta_micros,
  locked_gain_delta_micros::text AS locked_gain_delta_micros, price_source,
  ${iso('accepted_at')} AS accepted_at, ${iso('expires_at')} AS expires_at,
  CASE WHEN committed_at IS NULL THEN NULL ELSE ${iso('committed_at')} END AS committed_at`;
const orderColumns = `id::text AS id, preview_id::text AS preview_id, request_hash,
  account_revision::text AS account_revision, action, asset_id, variant_mint, symbol,
  price_micros::text AS price_micros, quantity_micros::text AS quantity_micros,
  cash_debit_micros::text AS cash_debit_micros, cash_credit_micros::text AS cash_credit_micros,
  cash_after_micros::text AS cash_after_micros, position_quantity_after_micros::text AS position_quantity_after_micros,
  position_cost_basis_after_micros::text AS position_cost_basis_after_micros,
  realized_gain_delta_micros::text AS realized_gain_delta_micros,
  locked_gain_delta_micros::text AS locked_gain_delta_micros, price_source,
  ${iso('committed_at')} AS committed_at`;

function invalid(): never {
  throw new PaperTradingRepositoryError('PAPER_STORAGE_INVALID', 'Stored paper trading state is invalid.');
}
function revision(value: unknown, minimum = 0): number {
  if (typeof value !== 'string' || !/^(0|[1-9][0-9]{0,15})$/u.test(value)) invalid();
  const result = Number(value);
  if (!Number.isSafeInteger(result) || result < minimum) invalid();
  return result;
}
function text(value: unknown, max: number): string {
  if (typeof value !== 'string' || value.length < 1 || value.length > max || value.trim() !== value) invalid();
  return value;
}
function timestamp(value: unknown): string {
  if (typeof value !== 'string') invalid();
  try {
    if (new Date(value).toISOString() !== value) invalid();
  } catch { return invalid(); }
  return value;
}
function storedUuid(value: unknown): string {
  try { return parsePaperUuid(value); } catch { return invalid(); }
}
function storedFixed(value: unknown): string {
  try { return parsePaperFixed(value).toString(); } catch { return invalid(); }
}
function source(value: unknown, acceptedAt: string): AcceptedPaperPrice['source'] {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) invalid();
  const row = value as Record<string, unknown>;
  const stamps = row['providerTimestamps'];
  if (row['provider'] !== 'tokens-xyz-v1' || typeof row['providerReference'] !== 'string' ||
      row['providerReference'].length < 1 || row['providerReference'].length > 300 ||
      typeof row['observedAt'] !== 'string' || row['acceptedAt'] !== acceptedAt ||
      stamps === null || typeof stamps !== 'object' || Array.isArray(stamps)) invalid();
  const timing = stamps as Record<string, unknown>;
  const optionalSource = (field: 'marketSource' | 'metricsSource') => {
    const item = row[field];
    if (item !== null && (typeof item !== 'string' || item.length > 80)) invalid();
    return item as string | null;
  };
  const optionalStamp = (field: 'asOf' | 'lastFetchedAt' | 'lastTradeAt') => {
    const item = timing[field];
    if (item !== null && (typeof item !== 'string' || !/^(0|[1-9][0-9]{0,15})$/u.test(item))) invalid();
    return item as string | null;
  };
  const observedAt = timestamp(row['observedAt']);
  timestamp(acceptedAt);
  if (timing['unit'] !== 'not_declared') invalid();
  return Object.freeze({
    provider: 'tokens-xyz-v1', providerReference: row['providerReference'],
    marketSource: optionalSource('marketSource'), metricsSource: optionalSource('metricsSource'),
    providerTimestamps: Object.freeze({asOf: optionalStamp('asOf'), lastFetchedAt: optionalStamp('lastFetchedAt'),
      lastTradeAt: optionalStamp('lastTradeAt'), unit: 'not_declared'}), observedAt, acceptedAt,
  });
}
function amount(row: PreviewRow): PaperOrderAmount {
  const raw = parsePaperFixed(row.input_amount_micros, {positive: true}).toString();
  if (row.input_kind === 'paper_amount') return Object.freeze({kind: 'paper_amount', paperMicros: raw});
  if (row.input_kind === 'share_quantity') return Object.freeze({kind: 'share_quantity', quantityMicros: raw});
  return invalid();
}
function preview(row: PreviewRow): PaperOrderPreview {
  const acceptedAt = timestamp(row.accepted_at);
  return validatePaperPreview({
    id: storedUuid(row.id), requestId: storedUuid(row.request_id), requestHash: text(row.request_hash, 64),
    state: row.state as PaperOrderPreview['state'], accountRevision: revision(row.account_revision),
    action: row.action as PaperOrderPreview['action'], amount: amount(row), assetId: text(row.asset_id, 100),
    variantMint: text(row.variant_mint, 44), symbol: text(row.symbol, 30), pricePaperMicros: text(row.price_micros, 30),
    quantityMicros: text(row.quantity_micros, 30), cashDebitPaperMicros: text(row.cash_debit_micros, 30),
    cashCreditPaperMicros: text(row.cash_credit_micros, 30), cashAfterPaperMicros: text(row.cash_after_micros, 30),
    positionQuantityAfterMicros: text(row.position_quantity_after_micros, 30),
    positionCostBasisAfterPaperMicros: text(row.position_cost_basis_after_micros, 30),
    realizedGainDeltaPaperMicros: text(row.realized_gain_delta_micros, 31),
    lockedGainDeltaPaperMicros: text(row.locked_gain_delta_micros, 30), source: source(row.price_source, acceptedAt),
    expiresAt: timestamp(row.expires_at), committedAt: row.committed_at === null ? null : timestamp(row.committed_at),
  });
}
function order(row: OrderRow): PaperCommittedOrder {
  const committedAt = timestamp(row.committed_at);
  const acceptedAt = (() => {
    const value = row.price_source;
    if (value === null || typeof value !== 'object' || Array.isArray(value)) invalid();
    return timestamp((value as Record<string, unknown>)['acceptedAt']);
  })();
  const result: PaperCommittedOrder = {
    id: storedUuid(row.id), previewId: storedUuid(row.preview_id), accountRevision: revision(row.account_revision, 1),
    action: row.action as PaperCommittedOrder['action'], assetId: text(row.asset_id, 100),
    variantMint: text(row.variant_mint, 44), symbol: text(row.symbol, 30),
    pricePaperMicros: parsePaperFixed(row.price_micros, {positive: true}).toString(),
    quantityMicros: parsePaperFixed(row.quantity_micros, {positive: true}).toString(),
    cashDebitPaperMicros: parsePaperFixed(row.cash_debit_micros).toString(),
    cashCreditPaperMicros: parsePaperFixed(row.cash_credit_micros).toString(),
    cashAfterPaperMicros: parsePaperFixed(row.cash_after_micros).toString(),
    positionQuantityAfterMicros: parsePaperFixed(row.position_quantity_after_micros).toString(),
    positionCostBasisAfterPaperMicros: parsePaperFixed(row.position_cost_basis_after_micros).toString(),
    realizedGainDeltaPaperMicros: parsePaperSignedFixed(row.realized_gain_delta_micros).toString(),
    lockedGainDeltaPaperMicros: parsePaperFixed(row.locked_gain_delta_micros).toString(),
    source: source(row.price_source, acceptedAt), committedAt,
  };
  if (Date.parse(committedAt) < Date.parse(acceptedAt)) invalid();
  return Object.freeze(result);
}

const resetRowKeys = Object.freeze([
  'outcome', 'mutation_id', 'previous_revision', 'revision', 'cash_micros', 'reset_at',
]);

function resetOutcome(row: ResetRow, command: PaperResetCommand): ParsedResetOutcome {
  if (Reflect.ownKeys(row).length !== resetRowKeys.length ||
      !resetRowKeys.every(key => Object.hasOwn(row, key))) invalid();
  const outcome = text(row.outcome, 30);
  const mutationId = row.mutation_id === null ? null : storedUuid(row.mutation_id);
  const previousRevision = row.previous_revision === null ? null : revision(row.previous_revision);
  const currentRevision = row.revision === null ? null : revision(row.revision);
  const cashPaperMicros = row.cash_micros === null ? null : storedFixed(row.cash_micros);
  const resetAt = row.reset_at === null ? null : timestamp(row.reset_at);
  const emptyResult = mutationId === null && previousRevision === null && currentRevision === null &&
    cashPaperMicros === null && resetAt === null;

  if (outcome === 'invalid') {
    if (!emptyResult) invalid();
    throw new PaperTradingRepositoryError('PAPER_INPUT_INVALID', 'Paper reset request is invalid.');
  }
  if (outcome === 'account_missing') {
    if (!emptyResult) invalid();
    throw new PaperTradingRepositoryError('PAPER_ACCOUNT_NOT_FOUND', 'Paper account is unavailable.');
  }
  if (outcome === 'idempotency_conflict') {
    if (!emptyResult) invalid();
    throw new PaperTradingRepositoryError('PAPER_IDEMPOTENCY_CONFLICT', 'Paper reset key is already in use.');
  }
  if (outcome === 'stale_revision') {
    if (mutationId !== null || previousRevision === null || currentRevision !== previousRevision ||
        cashPaperMicros === null || resetAt !== null) invalid();
    throw new PaperTradingRepositoryError('PAPER_PORTFOLIO_CHANGED', 'Paper desk changed before reset.');
  }
  if (outcome === 'revision_exhausted') {
    if (mutationId !== null || previousRevision === null || currentRevision !== previousRevision ||
        cashPaperMicros === null || resetAt !== null) invalid();
    throw new PaperTradingRepositoryError('PAPER_REVISION_EXHAUSTED', 'Paper desk revision is exhausted.');
  }
  if (outcome === 'not_needed') {
    if (mutationId !== command.mutationId || previousRevision === null ||
        previousRevision !== command.baseRevision || currentRevision !== previousRevision ||
        cashPaperMicros !== PAPER_STARTING_CASH_MICROS.toString() ||
        resetAt !== null) invalid();
    return Object.freeze({kind: 'not_needed'});
  }
  if (outcome !== 'reset' || mutationId !== command.mutationId || previousRevision === null ||
      previousRevision !== command.baseRevision || currentRevision === null || currentRevision !== previousRevision + 1 ||
      currentRevision > Number.MAX_SAFE_INTEGER || cashPaperMicros !== PAPER_STARTING_CASH_MICROS.toString() ||
      resetAt === null) invalid();
  return Object.freeze({kind: 'reset', receipt: Object.freeze({
    mutationId, previousRevision, revision: currentRevision, cashPaperMicros, resetAt,
  })});
}

/** Caller owns this dedicated nonprivileged pool and its shutdown lifecycle. */
export class PostgresPaperTradingRepository implements PaperTradingRepository {
  constructor(private readonly pool: Pick<Pool, 'connect'>) {}

  async getPortfolio(inputUserId: string): Promise<PaperPortfolio> {
    const userId = parsePaperUuid(inputUserId);
    return this.transaction(userId, true, async client => {
      const account = await this.account(client, userId);
      if (!account) return emptyPaperPortfolio();
      const lastResetRevision = revision(account.last_reset_revision);
      const positions = await client.query<PositionRow>(
        `SELECT ${positionColumns} FROM trimmy.paper_positions WHERE user_id = $1::uuid
           AND last_order_revision > $2::bigint
         ORDER BY asset_id, variant_mint`, [userId, lastResetRevision]);
      const recent = await client.query<OrderRow>(
        `SELECT ${orderColumns} FROM trimmy.paper_orders WHERE user_id = $1::uuid
           AND account_revision > $2::bigint
         ORDER BY committed_at DESC, id DESC LIMIT 50`, [userId, lastResetRevision]);
      return Object.freeze({
        revision: revision(account.revision), scaleDigits: 6 as const,
        startingCashPaperMicros: PAPER_STARTING_CASH_MICROS.toString(),
        cashPaperMicros: parsePaperFixed(account.cash_micros).toString(), openedAt: timestamp(account.opened_at),
        updatedAt: timestamp(account.updated_at), positions: Object.freeze(positions.rows.map(row => this.position(row))),
        recentOrders: Object.freeze(recent.rows.map(order)),
      });
    });
  }

  async findPreviewRequest(inputUserId: string, inputRequestId: string): Promise<PaperOrderPreview | null> {
    const userId = parsePaperUuid(inputUserId), requestId = parsePaperUuid(inputRequestId);
    return this.transaction(userId, true, async client => {
      const result = await client.query<PreviewRow>(
        `SELECT ${previewColumns} FROM trimmy.paper_order_previews
         WHERE user_id = $1::uuid AND request_id = $2::uuid`, [userId, requestId]);
      if (result.rows.length > 1) invalid();
      return result.rows[0] ? preview(result.rows[0]) : null;
    });
  }

  async createPreview(inputUserId: string, raw: PaperPreviewCommand): Promise<PaperOrderPreview> {
    const userId = parsePaperUuid(inputUserId);
    const command = Object.freeze({
      id: parsePaperUuid(raw.id), requestId: parsePaperUuid(raw.requestId), requestHash: parsePaperHash(raw.requestHash),
      action: raw.action, amount: raw.amount, price: validateAcceptedPaperPrice(raw.price),
    });
    return this.transaction(userId, false, async client => {
      await this.lock(client, userId);
      const existing = await client.query<PreviewRow>(
        `SELECT ${previewColumns} FROM trimmy.paper_order_previews
         WHERE user_id = $1::uuid AND request_id = $2::uuid`, [userId, command.requestId]);
      if (existing.rows[0]) {
        const stored = preview(existing.rows[0]);
        if (stored.requestHash !== command.requestHash) {
          throw new PaperTradingRepositoryError('PAPER_IDEMPOTENCY_CONFLICT', 'Paper preview request ID is already in use.');
        }
        return stored;
      }
      await client.query(
        `WITH instant AS (SELECT date_trunc('milliseconds', clock_timestamp()) AS at), opened AS (
           INSERT INTO trimmy.paper_accounts (user_id, opened_at, updated_at)
           SELECT $1::uuid, at, at FROM instant
           ON CONFLICT (user_id) DO NOTHING RETURNING user_id, opened_at
         )
         INSERT INTO trimmy.paper_cash_ledger
           (user_id, account_revision, order_id, entry_kind, delta_micros, balance_after_micros, created_at)
         SELECT user_id, 0, NULL, 'initial', 10000000000, 10000000000, opened_at FROM opened`, [userId]);
      const account = await this.account(client, userId, true);
      if (!account) throw new PaperTradingRepositoryError('PAPER_ACCOUNT_UNAVAILABLE', 'Paper account is unavailable.');
      const current = await this.currentPosition(client, userId, command.price.assetId, command.price.variantMint,
        revision(account.last_reset_revision), true);
      let calculated: PaperOrderCalculation;
      try {
        calculated = calculatePaperOrder({action: command.action, amount: command.amount,
          pricePaperMicros: command.price.pricePaperMicros, cashPaperMicros: text(account.cash_micros, 30),
          position: {quantityMicros: current.quantity, costBasisPaperMicros: current.basis}});
      } catch (error) { throw mapPaperDomainError(error); }
      const inputAmount = command.amount.kind === 'paper_amount' ? command.amount.paperMicros : command.amount.quantityMicros;
      const saved = await client.query<PreviewRow>(
        `INSERT INTO trimmy.paper_order_previews
          (id, user_id, request_id, request_hash, account_revision, action, input_kind, input_amount_micros,
           asset_id, variant_mint, symbol, price_micros, quantity_micros, cash_debit_micros, cash_credit_micros,
           cash_after_micros, position_quantity_after_micros, position_cost_basis_after_micros,
           realized_gain_delta_micros, locked_gain_delta_micros, price_source, accepted_at, expires_at)
         SELECT $1::uuid, $2::uuid, $3::uuid, $4, $5, $6, $7, $8::numeric,
           $9, $10, $11, $12::numeric, $13::numeric, $14::numeric, $15::numeric, $16::numeric,
           $17::numeric, $18::numeric, $19::numeric, $20::numeric, $21::jsonb, $22::timestamptz, $23::timestamptz
         WHERE $23::timestamptz > clock_timestamp()
         RETURNING ${previewColumns}`,
        [command.id, userId, command.requestId, command.requestHash, revision(account.revision), command.action,
          command.amount.kind, inputAmount, command.price.assetId, command.price.variantMint, command.price.symbol,
          calculated.pricePaperMicros, calculated.quantityMicros, calculated.cashDebitPaperMicros,
          calculated.cashCreditPaperMicros, calculated.cashAfterPaperMicros, calculated.positionQuantityAfterMicros,
          calculated.positionCostBasisAfterPaperMicros, calculated.realizedGainDeltaPaperMicros,
          calculated.lockedGainDeltaPaperMicros, JSON.stringify(command.price.source), command.price.source.acceptedAt,
          command.price.expiresAt]);
      if (saved.rows.length !== 1) throw new PaperTradingRepositoryError('PAPER_PREVIEW_EXPIRED', 'Paper price expired before it could be previewed.');
      return preview(saved.rows[0]!);
    });
  }

  async commit(inputUserId: string, raw: PaperCommitCommand): Promise<PaperCommittedOrder> {
    const userId = parsePaperUuid(inputUserId);
    const command = Object.freeze({orderId: parsePaperUuid(raw.orderId), previewId: parsePaperUuid(raw.previewId),
      idempotencyKey: parsePaperUuid(raw.idempotencyKey), requestHash: parsePaperHash(raw.requestHash)});
    return this.transaction(userId, false, async client => {
      await this.lock(client, userId);
      const replay = await client.query<OrderRow>(
        `SELECT ${orderColumns} FROM trimmy.paper_orders
         WHERE user_id = $1::uuid AND idempotency_key = $2::uuid`, [userId, command.idempotencyKey]);
      if (replay.rows[0]) {
        if (replay.rows[0].request_hash !== command.requestHash) {
          throw new PaperTradingRepositoryError('PAPER_IDEMPOTENCY_CONFLICT', 'Paper order key is already in use.');
        }
        return order(replay.rows[0]);
      }
      const found = await client.query<PreviewRow>(
        `SELECT ${previewColumns} FROM trimmy.paper_order_previews
         WHERE user_id = $1::uuid AND id = $2::uuid FOR UPDATE`, [userId, command.previewId]);
      if (!found.rows[0]) throw new PaperTradingRepositoryError('PAPER_PREVIEW_NOT_FOUND', 'Paper preview was not found.');
      const accepted = preview(found.rows[0]);
      if (accepted.state !== 'open') {
        throw new PaperTradingRepositoryError('PAPER_PREVIEW_ALREADY_COMMITTED', 'Paper preview has already been used.');
      }
      const account = await this.account(client, userId, true);
      if (!account) throw new PaperTradingRepositoryError('PAPER_ACCOUNT_UNAVAILABLE', 'Paper account is unavailable.');
      const currentRevision = revision(account.revision);
      if (currentRevision !== accepted.accountRevision) {
        throw new PaperTradingRepositoryError('PAPER_PORTFOLIO_CHANGED', 'Paper desk changed. Review a new order.');
      }
      const current = await this.currentPosition(client, userId, accepted.assetId, accepted.variantMint,
        revision(account.last_reset_revision), true);
      let calculated: PaperOrderCalculation;
      try {
        calculated = calculatePaperOrder({action: accepted.action, amount: accepted.amount,
          pricePaperMicros: accepted.pricePaperMicros, cashPaperMicros: text(account.cash_micros, 30),
          position: {quantityMicros: current.quantity, costBasisPaperMicros: current.basis}});
      } catch (error) { throw mapPaperDomainError(error); }
      for (const field of ['pricePaperMicros', 'quantityMicros', 'cashDebitPaperMicros', 'cashCreditPaperMicros',
        'cashAfterPaperMicros', 'positionQuantityAfterMicros', 'positionCostBasisAfterPaperMicros',
        'realizedGainDeltaPaperMicros', 'lockedGainDeltaPaperMicros'] as const) {
        if (calculated[field] !== accepted[field]) {
          throw new PaperTradingRepositoryError('PAPER_PORTFOLIO_CHANGED', 'Paper desk changed. Review a new order.');
        }
      }
      const nowResult = await client.query<{now: unknown}>(
        `SELECT ${iso("greatest(date_trunc('milliseconds', clock_timestamp()), updated_at + interval '1 millisecond', $2::timestamptz)")} AS now
         FROM trimmy.paper_accounts WHERE user_id = $1::uuid`, [userId, accepted.source.acceptedAt]);
      const committedAt = timestamp(nowResult.rows[0]?.now);
      if (Date.parse(committedAt) >= Date.parse(accepted.expiresAt)) {
        throw new PaperTradingRepositoryError('PAPER_PREVIEW_EXPIRED', 'Paper price expired. Review a new order.');
      }
      const nextRevision = currentRevision + 1;
      const realizedAfter = parsePaperSignedFixed((BigInt(current.realized) + BigInt(calculated.realizedGainDeltaPaperMicros)).toString()).toString();
      const lockedAfter = parsePaperFixed((BigInt(current.locked) + BigInt(calculated.lockedGainDeltaPaperMicros)).toString()).toString();
      const inserted = await client.query<OrderRow>(
        `INSERT INTO trimmy.paper_orders
          (id, user_id, preview_id, idempotency_key, request_hash, account_revision, action, asset_id, variant_mint,
           symbol, price_micros, quantity_micros, cash_debit_micros, cash_credit_micros, cash_before_micros,
           cash_after_micros, position_quantity_before_micros, position_quantity_after_micros,
           position_cost_basis_before_micros, position_cost_basis_after_micros, realized_gain_before_micros,
           realized_gain_delta_micros, realized_gain_after_micros, locked_gain_before_micros,
           locked_gain_delta_micros, locked_gain_after_micros, price_source, committed_at)
         VALUES ($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5,$6,$7,$8,$9,$10,$11::numeric,$12::numeric,
           $13::numeric,$14::numeric,$15::numeric,$16::numeric,$17::numeric,$18::numeric,$19::numeric,$20::numeric,
           $21::numeric,$22::numeric,$23::numeric,$24::numeric,$25::numeric,$26::numeric,$27::jsonb,$28::timestamptz)
         RETURNING ${orderColumns}`,
        [command.orderId, userId, command.previewId, command.idempotencyKey, command.requestHash, nextRevision,
          accepted.action, accepted.assetId, accepted.variantMint, accepted.symbol, accepted.pricePaperMicros,
          accepted.quantityMicros, accepted.cashDebitPaperMicros, accepted.cashCreditPaperMicros, account.cash_micros,
          accepted.cashAfterPaperMicros, current.quantity, accepted.positionQuantityAfterMicros, current.basis,
          accepted.positionCostBasisAfterPaperMicros, current.realized, accepted.realizedGainDeltaPaperMicros,
          realizedAfter, current.locked, accepted.lockedGainDeltaPaperMicros, lockedAfter,
          JSON.stringify(accepted.source), committedAt]);
      if (inserted.rows.length !== 1) invalid();
      const accountSaved = await client.query(
        `UPDATE trimmy.paper_accounts SET cash_micros = $2::numeric, revision = $3,
           updated_at = $4::timestamptz WHERE user_id = $1::uuid AND revision = $5`,
        [userId, accepted.cashAfterPaperMicros, nextRevision, committedAt, currentRevision]);
      if (accountSaved.rowCount !== 1) {
        throw new PaperTradingRepositoryError('PAPER_PORTFOLIO_CHANGED', 'Paper desk changed. Review a new order.');
      }
      await client.query(
        `INSERT INTO trimmy.paper_positions
          (user_id, asset_id, variant_mint, symbol, quantity_micros, cost_basis_micros,
           realized_gain_micros, locked_gain_micros, last_order_revision, updated_at)
         VALUES ($1::uuid,$2,$3,$4,$5::numeric,$6::numeric,$7::numeric,$8::numeric,$9,$10::timestamptz)
         ON CONFLICT (user_id, asset_id, variant_mint) DO UPDATE SET symbol = EXCLUDED.symbol,
           quantity_micros = EXCLUDED.quantity_micros, cost_basis_micros = EXCLUDED.cost_basis_micros,
           realized_gain_micros = EXCLUDED.realized_gain_micros, locked_gain_micros = EXCLUDED.locked_gain_micros,
           last_order_revision = EXCLUDED.last_order_revision, updated_at = EXCLUDED.updated_at`,
        [userId, accepted.assetId, accepted.variantMint, accepted.symbol, accepted.positionQuantityAfterMicros,
          accepted.positionCostBasisAfterPaperMicros, realizedAfter, lockedAfter, nextRevision, committedAt]);
      await client.query(
        `INSERT INTO trimmy.paper_cash_ledger
          (user_id, account_revision, order_id, entry_kind, delta_micros, balance_after_micros, created_at)
         VALUES ($1::uuid,$2,$3::uuid,$4,$5::numeric,$6::numeric,$7::timestamptz)`,
        [userId, nextRevision, command.orderId, accepted.action,
          (BigInt(accepted.cashCreditPaperMicros) - BigInt(accepted.cashDebitPaperMicros)).toString(),
          accepted.cashAfterPaperMicros, committedAt]);
      const marked = await client.query(
        `UPDATE trimmy.paper_order_previews SET state = 'committed', committed_at = $3::timestamptz
         WHERE user_id = $1::uuid AND id = $2::uuid AND state = 'open'`, [userId, command.previewId, committedAt]);
      if (marked.rowCount !== 1) invalid();
      return order(inserted.rows[0]!);
    });
  }

  async reset(inputUserId: string, raw: PaperResetCommand): Promise<PaperResetReceipt> {
    const userId = parsePaperUuid(inputUserId);
    if (!Number.isSafeInteger(raw.baseRevision) || raw.baseRevision < 0) {
      throw new PaperTradingRepositoryError('PAPER_INPUT_INVALID', 'Paper reset revision is invalid.');
    }
    const command = Object.freeze({
      mutationId: parsePaperUuid(raw.mutationId), requestHash: parsePaperHash(raw.requestHash),
      baseRevision: raw.baseRevision,
    });
    const outcome = await this.transaction(userId, false, async client => {
      const result = await client.query<ResetRow>(
        `SELECT outcome, mutation_id::text AS mutation_id,
           previous_revision::text AS previous_revision, revision::text AS revision,
           cash_micros::text AS cash_micros,
           CASE WHEN reset_at IS NULL THEN NULL ELSE ${iso('reset_at')} END AS reset_at
         FROM trimmy.paper_desk_reset($1::uuid,$2::uuid,$3::text,$4::bigint)`,
        [userId, command.mutationId, command.requestHash, command.baseRevision],
      );
      if (result.rows.length !== 1 || !result.rows[0]) invalid();
      return resetOutcome(result.rows[0], command);
    }, false);
    // A no-op is an immutable idempotency result too. Let its receipt commit
    // before exposing the existing conflict-shaped API response to callers.
    if (outcome.kind === 'not_needed') {
      throw new PaperTradingRepositoryError('PAPER_RESET_NOT_NEEDED', 'Paper desk is already fresh.');
    }
    return outcome.receipt;
  }

  private position(row: PositionRow): PaperPosition {
    const quantity = parsePaperFixed(row.quantity_micros);
    const basis = parsePaperFixed(row.cost_basis_micros);
    return Object.freeze({
      assetId: text(row.asset_id, 100), variantMint: text(row.variant_mint, 44), symbol: text(row.symbol, 30),
      quantityMicros: quantity.toString(), costBasisPaperMicros: basis.toString(),
      averageCostPricePaperMicros: quantity === 0n ? '0' : (basis * PAPER_FIXED_SCALE / quantity).toString(),
      realizedGainPaperMicros: parsePaperSignedFixed(row.realized_gain_micros).toString(),
      lockedGainPaperMicros: parsePaperFixed(row.locked_gain_micros).toString(), updatedAt: timestamp(row.updated_at),
    });
  }

  private async account(client: PoolClient, userId: string, lock = false): Promise<AccountRow | null> {
    const result = await client.query<AccountRow>(
      `SELECT ${accountColumns} FROM trimmy.paper_accounts WHERE user_id = $1::uuid${lock ? ' FOR UPDATE' : ''}`, [userId]);
    if (result.rows.length > 1) invalid();
    return result.rows[0] ?? null;
  }

  private async currentPosition(client: PoolClient, userId: string, assetId: string, variantMint: string,
    lastResetRevision: number, lock: boolean) {
    const result = await client.query<PositionRow>(
      `SELECT ${positionColumns} FROM trimmy.paper_positions
       WHERE user_id = $1::uuid AND asset_id = $2 AND variant_mint = $3
         AND last_order_revision > $4::bigint${lock ? ' FOR UPDATE' : ''}`,
      [userId, assetId, variantMint, lastResetRevision]);
    if (result.rows.length > 1) invalid();
    const row = result.rows[0];
    return row ? {quantity: parsePaperFixed(row.quantity_micros).toString(),
      basis: parsePaperFixed(row.cost_basis_micros).toString(),
      realized: parsePaperSignedFixed(row.realized_gain_micros).toString(),
      locked: parsePaperFixed(row.locked_gain_micros).toString()}
      : {quantity: '0', basis: '0', realized: '0', locked: '0'};
  }

  private lock(client: PoolClient, userId: string) {
    return client.query('SELECT pg_advisory_xact_lock(hashtextextended($1::text, 0))', [`trimmy.paper:${userId}`]);
  }

  private async transaction<T>(userId: string, readOnly: boolean, run: (client: PoolClient) => Promise<T>,
    requireAccount = true): Promise<T> {
    const client = await this.pool.connect();
    let releaseError: Error | undefined;
    try {
      await client.query(
        readOnly
          ? 'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY'
          : 'BEGIN',
      );
      const role = await client.query<{unsafe_role: boolean}>(`
        SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_roles
          WHERE (rolsuper OR rolbypassrls) AND pg_catalog.pg_has_role(current_user, oid, 'MEMBER'))
          OR EXISTS (SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'trimmy' AND c.relname IN
              ('users','paper_accounts','paper_positions','paper_order_previews','paper_orders','paper_cash_ledger',
               'paper_reset_receipts')
              AND pg_catalog.pg_has_role(current_user, c.relowner, 'MEMBER')) AS unsafe_role`);
      if (role.rows.length !== 1 || role.rows[0]?.unsafe_role !== false) {
        throw new PaperTradingRepositoryError('PAPER_RUNTIME_ROLE_INVALID', 'Paper storage requires a dedicated runtime role.');
      }
      await client.query("SELECT set_config('trimmy.practice_user_id', $1, true)", [userId]);
      if (requireAccount) {
        const account = await client.query<{account_exists: boolean}>('SELECT trimmy.practice_account_exists() AS account_exists');
        if (account.rows.length !== 1 || typeof account.rows[0]?.account_exists !== 'boolean') invalid();
        if (!account.rows[0].account_exists) {
          throw new PaperTradingRepositoryError('PAPER_ACCOUNT_NOT_FOUND', 'Paper account is unavailable.');
        }
      }
      const result = await run(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      try { await client.query('ROLLBACK'); }
      catch { releaseError = new Error('Paper trading transaction cleanup failed.'); }
      if (error instanceof PaperTradingRepositoryError) throw error;
      if ((error as {constraint?: unknown}).constraint === 'paper_account_active') {
        throw new PaperTradingRepositoryError('PAPER_ACCOUNT_UNAVAILABLE', 'Paper account is unavailable.');
      }
      throw error;
    } finally { client.release(releaseError); }
  }
}
