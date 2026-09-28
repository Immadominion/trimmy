import {PracticeError, normalizePracticeApiBase, parsePracticeUuid} from './practice-client.js';
import type {CareerRank} from './practice-client.js';
import type {PracticeStorage} from './practice-session.js';
import {read} from './product-api.js';
import type {ProductApiClient, ProductIdentity} from './product-api.js';
import type {JourneyPrincipal} from './journey-store.js';

/* Contracts: apps/api/src/career-routes.ts, career-reason-sharing-routes.ts,
 * paper-trading-routes.ts (reset) and account-closure-route.ts. */

export type ReasonVisibility = 'nobody' | 'everyone' | 'friends';
export interface ReasonPrivacy {
  readonly revision: number; readonly visibility: ReasonVisibility; readonly configured: boolean;
  readonly friendsSharing: 'unavailable' | 'available'; readonly createdAt: string; readonly updatedAt: string;
}
export interface ReasonPrivacyWrite {readonly schemaVersion: 1; readonly mutationId: string; readonly baseRevision: number; readonly visibility: ReasonVisibility}
export interface TradeReasonWrite {readonly schemaVersion: 1; readonly mutationId: string; readonly orderId: string; readonly note: string}
export interface TradeReasonReceipt {
  readonly orderId: string; readonly assetId: string; readonly variantMint: string; readonly note: string;
  readonly trimsAwarded: number; readonly dailyAwardNumber: number | null; readonly savedAt: string;
}
export interface PromotionWrite {readonly schemaVersion: 1; readonly mutationId: string; readonly targetRank: Exclude<CareerRank, 'rookie'>}
export interface PromotionReceipt {
  readonly mutationId: string; readonly fromRank: CareerRank; readonly toRank: CareerRank;
  readonly careerRevision: number; readonly trimsAwarded: 100; readonly promotedAt: string;
}
export interface DayContext {
  readonly revision: number; readonly timeZone: string; readonly configured: boolean;
  readonly serverDate: string; readonly nextDayAt: string; readonly createdAt: string; readonly updatedAt: string;
}
export interface DayContextWrite {readonly schemaVersion: 1; readonly mutationId: string; readonly baseRevision: number; readonly timeZone: string}
export interface PaperResetWrite {readonly schemaVersion: 1; readonly mutationId: string; readonly baseRevision: number; readonly confirm: 'reset my paper desk'}
export interface PaperResetReceipt {
  readonly mutationId: string; readonly previousRevision: number; readonly revision: number; readonly resetAt: string;
  readonly cashPaperMicros: string;
}
export interface ReasonAuthor {
  readonly handle: string; readonly rank: {readonly id: CareerRank; readonly label: string}; readonly isViewer: boolean;
  readonly socialId?: string; readonly persona?: 'wolf' | 'oracle' | 'shark';
}
export interface SharedReason {
  readonly reasonId: string; readonly orderId: string | null; readonly author: ReasonAuthor;
  readonly stock: {readonly assetId: string; readonly variantMint: string; readonly symbol: string};
  readonly note: string; readonly savedAt: string; readonly deskCycle: 'current' | 'historical' | null;
}
export interface ReasonPage {readonly scope: 'self' | 'everyone' | 'friends'; readonly reasons: readonly SharedReason[]; readonly nextCursor: string | null}

export const PAPER_RESET_CONFIRMATION = 'reset my paper desk';
export const ACCOUNT_CLOSURE_CONFIRMATION = 'close my account';
const ranks = ['rookie', 'analyst', 'trader', 'senior-trader', 'partner', 'legend'] as const;
const rankLabels: Record<CareerRank, string> = {rookie: 'Rookie', analyst: 'Analyst', trader: 'Trader', 'senior-trader': 'Senior Trader', partner: 'Partner', legend: 'Legend'};
const assetPattern = /^[a-z0-9]+(?:-[a-z0-9]+)*$/u, mintPattern = /^[1-9A-HJ-NP-Za-km-z]{32,44}$/u;

export function parseReasonPrivacy(value: unknown): ReasonPrivacy {
  const v = read.record(value, ['revision', 'visibility', 'configured', 'friendsSharing', 'createdAt', 'updatedAt']);
  const result: ReasonPrivacy = {revision: read.integer(v['revision'], 1), visibility: read.oneOf(v['visibility'], ['nobody', 'everyone', 'friends']),
    configured: read.boolean(v['configured']), friendsSharing: read.oneOf(v['friendsSharing'], ['unavailable', 'available']),
    createdAt: read.instant(v['createdAt']), updatedAt: read.instant(v['updatedAt'])};
  if (!result.configured && (result.revision !== 1 || result.visibility !== 'nobody')) read.invalid();
  return Object.freeze(result);
}
function envelope(value: unknown, key: string): unknown {const v = read.record(value); if (v['schemaVersion'] !== 1) read.invalid(); return v[key];}
function stockId(value: unknown): string {const text = read.string(value, 100); if (!assetPattern.test(text)) read.invalid(); return text;}
function mint(value: unknown): string {const text = read.string(value, 44); if (!mintPattern.test(text)) read.invalid(); return text;}
function note(value: unknown): string {const text = read.string(value, 180); if (text.trim() !== text) read.invalid(); return text;}
export function parseReasonItem(value: unknown): SharedReason {
  const v = read.record(value), internal = Object.hasOwn(v, 'orderId') || Object.hasOwn(v, 'deskCycle');
  read.record(v, internal ? ['reasonId', 'orderId', 'author', 'stock', 'note', 'deskCycle', 'savedAt'] : ['reasonId', 'author', 'stock', 'note', 'savedAt']);
  const hasSocial = Object.hasOwn(read.record(v['author']), 'socialId');
  const a = read.record(v['author'], hasSocial ? ['socialId', 'handle', 'persona', 'rank', 'isViewer'] : ['handle', 'rank', 'isViewer']);
  const rank = read.record(a['rank'], ['id', 'label']), rankId = read.oneOf(rank['id'], ranks);
  if (rank['label'] !== rankLabels[rankId]) read.invalid();
  const handle = read.string(a['handle'], 18); if (!/^[a-z][a-z0-9_]{2,17}$/u.test(handle)) read.invalid();
  const s = read.record(v['stock'], ['assetId', 'variantMint', 'symbol']);
  return Object.freeze({reasonId: read.uuid(v['reasonId']), orderId: internal ? read.uuid(v['orderId']) : null,
    author: Object.freeze({handle, rank: Object.freeze({id: rankId, label: rankLabels[rankId]}), isViewer: read.boolean(a['isViewer']),
      ...(hasSocial ? {socialId: read.uuid(a['socialId']), persona: read.oneOf(a['persona'], ['wolf', 'oracle', 'shark'])} : {})}),
    stock: Object.freeze({assetId: stockId(s['assetId']), variantMint: mint(s['variantMint']), symbol: read.string(s['symbol'], 30)}),
    note: note(v['note']), savedAt: read.instant(v['savedAt']), deskCycle: internal ? read.oneOf(v['deskCycle'], ['current', 'historical']) : null});
}
export function parseReasonPage(value: unknown, expected: {scope: ReasonPage['scope']; assetId?: string; variantMint?: string}): ReasonPage {
  const v = read.record(value, ['schemaVersion', 'scope', 'filter', 'reasons', 'page']);
  if (v['schemaVersion'] !== 1 || v['scope'] !== expected.scope) read.invalid();
  const filter = v['filter'] === null ? null : read.record(v['filter'], ['assetId', 'variantMint']);
  if ((filter?.['assetId'] ?? undefined) !== expected.assetId || (filter?.['variantMint'] ?? undefined) !== expected.variantMint) read.invalid();
  const reasons = read.array(v['reasons'], 50).map(parseReasonItem);
  if (reasons.some(reason => expected.assetId !== undefined && (reason.stock.assetId !== expected.assetId || reason.stock.variantMint !== expected.variantMint))) read.invalid();
  if (new Set(reasons.map(reason => reason.reasonId)).size !== reasons.length) read.invalid();
  const page = read.record(v['page'], ['limit', 'nextCursor']);
  read.integer(page['limit'], 1, 50);
  const cursor = read.nullable(page['nextCursor'], item => {const text = read.string(item, 512); if (!/^[A-Za-z0-9_-]+$/u.test(text)) read.invalid(); return text;});
  return Object.freeze({scope: expected.scope, reasons, nextCursor: cursor});
}
export function parseTradeReasonReceipt(value: unknown): TradeReasonReceipt {
  const v = read.record(value, ['orderId', 'assetId', 'variantMint', 'note', 'trimsAwarded', 'dailyAwardNumber', 'savedAt']);
  return Object.freeze({orderId: read.uuid(v['orderId']), assetId: stockId(v['assetId']), variantMint: mint(v['variantMint']), note: note(v['note']),
    trimsAwarded: read.integer(v['trimsAwarded'], 0, 1000), dailyAwardNumber: read.nullable(v['dailyAwardNumber'], item => read.integer(item, 1, 1000)),
    savedAt: read.instant(v['savedAt'])});
}
export function parsePromotionReceipt(value: unknown): PromotionReceipt {
  const v = read.record(value, ['mutationId', 'fromRank', 'toRank', 'careerRevision', 'trimsAwarded', 'promotedAt']);
  if (v['trimsAwarded'] !== 100) read.invalid();
  const fromRank = read.oneOf(v['fromRank'], ranks), toRank = read.oneOf(v['toRank'], ranks);
  if (ranks.indexOf(toRank) !== ranks.indexOf(fromRank) + 1) read.invalid();
  return Object.freeze({mutationId: read.uuid(v['mutationId']), fromRank, toRank, careerRevision: read.integer(v['careerRevision'], 1),
    trimsAwarded: 100, promotedAt: read.instant(v['promotedAt'])});
}
export function parseDayContext(value: unknown): DayContext {
  const v = read.record(value, ['revision', 'timeZone', 'configured', 'serverDate', 'nextDayAt', 'createdAt', 'updatedAt']);
  const result = {revision: read.integer(v['revision'], 1), timeZone: read.string(v['timeZone'], 100), configured: read.boolean(v['configured']),
    serverDate: read.day(v['serverDate']), nextDayAt: read.instant(v['nextDayAt']), createdAt: read.instant(v['createdAt']), updatedAt: read.instant(v['updatedAt'])};
  return Object.freeze(result);
}
function parseResetReceipt(value: unknown, write: PaperResetWrite): PaperResetReceipt {
  const v = read.record(value, ['schemaVersion', 'mode', 'unit', 'reset', 'portfolioAtReset']);
  const unit = read.record(v['unit'], ['kind', 'scaleDigits']);
  if (v['schemaVersion'] !== 1 || v['mode'] !== 'paper' || unit['kind'] !== 'paper' || unit['scaleDigits'] !== 6) read.invalid();
  const reset = read.record(v['reset'], ['mutationId', 'previousRevision', 'revision', 'resetAt']);
  const portfolio = read.record(v['portfolioAtReset'], ['revision', 'startingCashPaperMicros', 'cashPaperMicros', 'positions', 'recentOrders']);
  const revision = read.integer(reset['revision'], 1), previousRevision = read.integer(reset['previousRevision']);
  const cash = read.string(portfolio['cashPaperMicros'], 30); if (!/^(?:0|[1-9][0-9]{0,29})$/u.test(cash)) read.invalid();
  if (read.uuid(reset['mutationId']) !== write.mutationId || revision <= previousRevision || portfolio['revision'] !== revision ||
    read.array(portfolio['positions']).length !== 0 || read.array(portfolio['recentOrders']).length !== 0) read.invalid();
  return Object.freeze({mutationId: write.mutationId, previousRevision, revision, resetAt: read.instant(reset['resetAt']), cashPaperMicros: cash});
}

export const careerApi = {
  readReasonPrivacy: (api: ProductApiClient, identity: ProductIdentity, signal?: AbortSignal) =>
    api.request({path: '/v1/career/reason-privacy', identity, signal, parse: value => parseReasonPrivacy(envelope(value, 'reasonPrivacy'))}),
  saveReasonPrivacy: (api: ProductApiClient, identity: ProductIdentity, body: ReasonPrivacyWrite, signal?: AbortSignal) =>
    api.request({path: '/v1/career/reason-privacy', method: 'PUT', body, identity, signal, parse: value => {
      const privacy = parseReasonPrivacy(envelope(value, 'reasonPrivacy'));
      if (privacy.visibility !== body.visibility || privacy.revision <= body.baseRevision) read.invalid();
      return privacy;
    }}),
  listReasons: (api: ProductApiClient, identity: ProductIdentity, query: {scope: ReasonPage['scope']; assetId?: string; variantMint?: string; limit?: number; cursor?: string}, signal?: AbortSignal) =>
    api.request({path: '/v1/career/trade-reasons', identity, signal, query: {scope: query.scope, assetId: query.assetId, variantMint: query.variantMint,
      limit: query.limit === undefined ? undefined : String(query.limit), cursor: query.cursor},
      parse: value => parseReasonPage(value, {scope: query.scope, ...(query.assetId ? {assetId: query.assetId, variantMint: query.variantMint!} : {})})}),
  saveTradeReason: (api: ProductApiClient, identity: ProductIdentity, body: TradeReasonWrite, signal?: AbortSignal) =>
    api.request({path: '/v1/career/trade-reasons', method: 'POST', body, identity, signal, expectedStatus: [201], parse: value => {
      const receipt = parseTradeReasonReceipt(envelope(value, 'reason'));
      if (receipt.orderId !== body.orderId || receipt.note !== body.note) read.invalid();
      return receipt;
    }}),
  promote: (api: ProductApiClient, identity: ProductIdentity, body: PromotionWrite, signal?: AbortSignal) =>
    api.request({path: '/v1/career/promotions', method: 'POST', body, identity, signal, expectedStatus: [201], parse: value => {
      const receipt = parsePromotionReceipt(envelope(value, 'promotion'));
      if (receipt.mutationId !== body.mutationId || receipt.toRank !== body.targetRank) read.invalid();
      return receipt;
    }}),
  readDayContext: (api: ProductApiClient, identity: ProductIdentity, signal?: AbortSignal) =>
    api.request({path: '/v1/career/day-context', identity, signal, parse: value => parseDayContext(envelope(value, 'dayContext'))}),
  saveDayContext: (api: ProductApiClient, identity: ProductIdentity, body: DayContextWrite, signal?: AbortSignal) =>
    api.request({path: '/v1/career/day-context', method: 'PUT', body, identity, signal, parse: value => {
      const context = parseDayContext(envelope(value, 'dayContext'));
      if (!context.configured || context.timeZone !== body.timeZone) read.invalid();
      return context;
    }}),
  resetPaper: (api: ProductApiClient, identity: ProductIdentity, body: PaperResetWrite, signal?: AbortSignal) =>
    api.request({path: '/v1/account/paper/reset', method: 'POST', body, identity, signal, parse: value => parseResetReceipt(value, body)}),
  closeAccount: (api: ProductApiClient, identity: ProductIdentity & {readonly subject: string}, signal?: AbortSignal) =>
    api.request({path: '/v1/account/closure', method: 'POST', identity, signal, body: {schemaVersion: 1, confirm: ACCOUNT_CLOSURE_CONFIRMATION},
      parse: value => {
        const v = read.record(value, ['schemaVersion', 'closed', 'canceledInvitations', 'note']);
        if (v['schemaVersion'] !== 1 || v['closed'] !== true) read.invalid();
        return Object.freeze({canceledInvitations: read.integer(v['canceledInvitations']), note: read.string(v['note'], 400)});
      }}),
};

/**
 * Exact commands saved before dispatch. An ambiguous result replays the same
 * mutation ID; only a definitive answer clears it (mobile's pending stores).
 */
export type PendingKind = 'reason-privacy' | 'paper-reset' | 'promotion' | 'day-context' | 'trade-reason';
export class PendingMutations {
  readonly #storage: PracticeStorage; readonly #prefix: string;
  constructor(storage: PracticeStorage, apiBase: string) {
    this.#storage = storage; this.#prefix = `trimmy.pending.v1:${encodeURIComponent(normalizePracticeApiBase(apiBase))}`;
  }
  #key(kind: PendingKind, principal: JourneyPrincipal) {return `${this.#prefix}:${kind}:${principal}`;}
  read<T extends {mutationId: string}>(kind: PendingKind, principal: JourneyPrincipal): T | null {
    try {
      const raw = this.#storage.getItem(this.#key(kind, principal));
      if (!raw || raw.length > 4096) return null;
      const value = JSON.parse(raw) as T; parsePracticeUuid(value.mutationId); return value;
    } catch {return null;}
  }
  save<T extends {mutationId: string}>(kind: PendingKind, principal: JourneyPrincipal, value: T): void {
    const raw = JSON.stringify(value);
    try {this.#storage.setItem(this.#key(kind, principal), raw); if (this.#storage.getItem(this.#key(kind, principal)) !== raw) throw new Error();}
    catch {throw new PracticeError('PRACTICE_STORAGE_UNAVAILABLE', 'This change could not be saved safely before sending.');}
  }
  clear(kind: PendingKind, principal: JourneyPrincipal): void {
    try {this.#storage.setItem(this.#key(kind, principal), '');} catch { /* A stale command only replays an idempotent write. */ }
  }
}
/**
 * Transport failures, 5xx, rate limits and expired sessions leave the exact
 * command pending for a safe retry; a definitive 4xx answer settled it.
 */
export function ambiguous(error: unknown): boolean {
  return !(error instanceof PracticeError) || error.status === null || error.status >= 500 || error.status === 429 || error.status === 401 ||
    ['PRACTICE_NETWORK_ERROR', 'PRACTICE_TIMEOUT', 'PRACTICE_ABORTED', 'PRODUCT_RESPONSE_INVALID'].includes(error.code);
}
export function newMutationId(): string {return parsePracticeUuid(crypto.randomUUID());}
