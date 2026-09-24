import {
  calculatePaperOrder, parsePaperAssetId, parsePaperFixed, parsePaperOrderAction, parsePaperOrderAmount,
  parsePaperSignedFixed, parsePaperSymbol, parsePaperVariantMint,
} from '@trimmy/domain';
import type {PaperOrderAction, PaperOrderAmount} from '@trimmy/domain';

export type {PaperOrderAction, PaperOrderAmount};
export type PaperAmount = PaperOrderAmount;
export const PROFILE_MEDIA_TYPE = 'application/vnd.trimmy.product-profile.v2+json';
export const PORTFOLIO_MEDIA_TYPE = 'application/vnd.trimmy.paper-portfolio.v2+json';
export interface GuestCreationRequest {readonly schemaVersion: 1; readonly requestId: string; readonly replaySecret: string}
export interface GuestCredential {
  readonly guestId: string; readonly token: string; readonly expiresAt: string; readonly hardExpiresAt: string;
}
/** A live Privy identity epoch. Abort when the SDK identity changes or logs out. */
export interface PracticeAccountProof {
  readonly subject: string; readonly freshAccessToken: () => Promise<string | null>; readonly signal: AbortSignal;
}
export interface PracticeAccountAccess extends PracticeAccountProof {readonly accountId: string}
export type PracticeIdentity = GuestCredential | PracticeAccountProof;
export interface GuestClaimRequest {readonly schemaVersion: 1; readonly idempotencyKey: string}
export interface GuestClaimResult {readonly guestId: string; readonly claimedAt: string}
export function parsePracticeSubject(value: unknown): string {
  if (typeof value !== 'string' || !/^did:privy:[A-Za-z0-9]{1,128}$/u.test(value)) {
    throw new PracticeError('PRACTICE_ACCOUNT_INVALID', 'The signed-in account could not be verified.');
  }
  return value;
}
export interface ProductOnboarding {
  readonly goal: 'learn' | 'practice' | 'trade' | 'beat-friends' | null;
  readonly knowledge: 'nothing' | 'basics' | 'practice' | 'traded-before' | 'daily-trader' | null;
  readonly persona: 'wolf' | 'oracle' | 'shark' | null;
  readonly dailyGoal: 'show-up' | 'one-mission' | 'three-missions' | null;
  readonly handle: string | null;
}
export type LaunchCheckpoint = 'first-trade' | 'first-position' | 'streak' | 'save-desk' | 'app';
export type LaunchAction = 'paper-trade-confirmed' | 'first-position-collected' | 'day-one-seen' |
  'save-desk-later' | 'save-desk-saved' | 'introduction-skipped' | 'introduction-completed';
export interface ProductProfile {
  readonly revision: number; readonly onboarding: ProductOnboarding; readonly launchCheckpoint: LaunchCheckpoint;
  readonly hasConfirmedPaperTrade: boolean; readonly createdAt: string; readonly updatedAt: string;
}
export interface ProductProfileWrite {
  readonly schemaVersion: 2; readonly mutationId: string; readonly baseRevision: number;
  readonly onboarding: ProductOnboarding; readonly launchCheckpoint: LaunchCheckpoint;
}
export interface ProductLaunchWrite {
  readonly schemaVersion: 2; readonly mutationId: string; readonly baseRevision: number; readonly action: LaunchAction;
}
export interface PaperOrderIntent {
  readonly action: PaperOrderAction; readonly assetId: string; readonly variantMint: string; readonly amount: PaperAmount;
}
export interface PaperPreviewRequest extends PaperOrderIntent {readonly schemaVersion: 1; readonly requestId: string}
export interface PaperCommitRequest {readonly schemaVersion: 1; readonly previewId: string; readonly idempotencyKey: string}
export interface PaperPriceSource {
  readonly provider: 'tokens-xyz-v1'; readonly providerReference: string;
  readonly marketSource: string | null; readonly metricsSource: string | null;
  readonly providerTimestamps: {readonly asOf: string | null; readonly lastFetchedAt: string | null;
    readonly lastTradeAt: string | null; readonly unit: 'not_declared'};
  readonly observedAt: string; readonly acceptedAt: string;
}
interface PaperCalculation {
  readonly action: PaperOrderAction; readonly assetId: string; readonly variantMint: string; readonly symbol: string;
  readonly accountRevision: number; readonly pricePaperMicros: string; readonly quantityMicros: string;
  readonly cashDebitPaperMicros: string; readonly cashCreditPaperMicros: string; readonly cashAfterPaperMicros: string;
  readonly positionQuantityAfterMicros: string; readonly positionCostBasisAfterPaperMicros: string;
  readonly realizedGainDeltaPaperMicros: string; readonly lockedGainDeltaPaperMicros: string; readonly source: PaperPriceSource;
}
export interface PaperPreview extends PaperCalculation {
  readonly id: string; readonly requestId: string; readonly state: 'open' | 'committed'; readonly amount: PaperAmount;
  readonly expiresAt: string; readonly committedAt: string | null;
}
export interface PaperReceipt extends PaperCalculation {readonly id: string; readonly previewId: string; readonly committedAt: string}
export type PaperOrder = PaperReceipt;
export interface PaperPosition {
  readonly assetId: string; readonly variantMint: string; readonly symbol: string; readonly quantityMicros: string;
  readonly costBasisPaperMicros: string; readonly averageCostPricePaperMicros: string;
  readonly realizedGainPaperMicros: string; readonly lockedGainPaperMicros: string; readonly updatedAt: string;
}
export interface PaperPositionValuation {
  readonly assetId: string; readonly variantMint: string; readonly status: 'priced' | 'unavailable';
  readonly pricePaperMicros: string | null; readonly marketValuePaperMicros: string | null;
  readonly unrealizedGainPaperMicros: string | null; readonly observedAt: string | null;
  readonly acceptedAt: string | null; readonly expiresAt: string | null;
}
export interface PaperPortfolio {
  readonly schemaVersion: 2; readonly mode: 'paper'; readonly unit: {readonly kind: 'paper'; readonly scaleDigits: 6};
  readonly revision: number; readonly startingCashPaperMicros: string; readonly cashPaperMicros: string;
  readonly openedAt: string | null; readonly updatedAt: string | null;
  readonly positions: readonly PaperPosition[]; readonly recentOrders: readonly PaperReceipt[];
  readonly valuation: {readonly status: 'complete' | 'partial' | 'unavailable'; readonly portfolioRevision: number;
    readonly openPositionCount: number; readonly pricedPositionCount: number; readonly cashPaperMicros: string;
    readonly knownValuePaperMicros: string; readonly totalPaperMicros: string | null; readonly positions: readonly PaperPositionValuation[]};
}
export type CareerRank = 'rookie' | 'analyst' | 'trader' | 'senior-trader' | 'partner' | 'legend';
export interface CareerSummary {
  readonly revision: number; readonly trims: {readonly total: number; readonly today: number; readonly thisWeek: number};
  readonly rank: {readonly id: CareerRank; readonly label: string; readonly paperLimit: string; readonly threshold: number};
  readonly nextRank: {readonly id: CareerRank; readonly label: string; readonly threshold: number;
    readonly trimsRemaining: number; readonly promotionRequired: boolean} | null;
  readonly streak: {readonly days: number; readonly status: 'not-started' | 'active' | 'at-risk' | 'grace'; readonly lastActiveDate: string | null};
  readonly careerStarted: boolean;
  readonly firstConfirmedBuy: {readonly orderId: string; readonly assetId: string; readonly variantMint: string;
    readonly symbol: string; readonly quantityMicros: string; readonly confirmedAt: string} | null;
  readonly serverDate: string; readonly updatedAt: string | null;
}
export interface CareerMission {
  readonly id: 'first-paper-buy' | 'write-a-reason' | 'hold-through-red-day'; readonly chapterRank: CareerRank;
  readonly order: number; readonly kind: 'action' | 'promotion'; readonly title: string; readonly instruction: string;
  readonly trimsReward: 20; readonly promotesToRank: CareerRank | null;
  readonly status: 'locked' | 'ready' | 'complete'; readonly completedAt: string | null;
}
export interface CareerMissionBoard {readonly revision: number; readonly currentRank: CareerRank; readonly missions: readonly CareerMission[]}

export interface CareerActivityWeek {
  readonly serverDate: string; readonly weekStart: string; readonly activeDates: readonly string[];
}
export interface DailyDeskChoice {readonly id: string; readonly label: string; readonly outcome: string; readonly takeaway: string}
export interface DailyDeskCompletion {readonly date: string; readonly caseId: string; readonly choiceId: string}
export interface DailyDeskHistory extends DailyDeskCompletion {readonly title: string; readonly completedAt: string}
export interface DailyDeskShift {
  readonly date: string;
  readonly story: {readonly id: string; readonly ordinal: number; readonly title: string;
    readonly speaker: 'sal' | 'wolf' | 'oracle' | 'shark'; readonly body: string; readonly choices: readonly DailyDeskChoice[]};
  readonly completedChoice: string | null; readonly completedAt: string | null;
  readonly trimsEarned: 0 | 10; readonly history: readonly DailyDeskHistory[];
}

export type WorkdayAnswer = {readonly ids: readonly string[]} | {readonly value: string};
export interface WorkdayStepWrite {
  readonly assignmentId: string; readonly revision: number; readonly step: 0 | 1 | 2;
  readonly answer: WorkdayAnswer; readonly draft?: string;
}
export interface WorkdayDraftWrite {readonly assignmentId: string; readonly revision: number; readonly draft: string}
export type WorkdayMutation = {readonly kind: 'step'; readonly body: WorkdayStepWrite} | {readonly kind: 'draft'; readonly body: WorkdayDraftWrite};
export interface WorkdayAssignment {
  readonly id: string; readonly ordinal: number; readonly title: string; readonly speaker: 'sal' | 'wolf' | 'oracle' | 'shark';
  readonly district: string; readonly brief: string; readonly sourceTitle: string; readonly sourceLabel: string; readonly art: string;
  readonly rows: readonly {readonly id: string; readonly label: string; readonly value: string; readonly detail: string}[];
  readonly evidence: {readonly prompt: string; readonly count: number};
  readonly decision: {readonly kind: 'number' | 'choice'; readonly prompt: string; readonly hint: string; readonly unit: string | null;
    readonly choices: readonly {readonly id: string; readonly label: string; readonly feedback: string}[]};
  readonly file: {readonly prompt: string; readonly count: number; readonly parts: readonly {readonly id: string; readonly text: string}[]};
  readonly revision: number; readonly step: 0 | 1 | 2 | 3; readonly answers: Readonly<Partial<Record<'0' | '1' | '2', WorkdayAnswer>>>;
  readonly draft: string; readonly completedAt: string | null; readonly artifact: string | null;
  readonly feedback: string | null; readonly contextNote: string | null;
}
export interface WorkdayJourney {readonly contentVersion: string; readonly date: string; readonly completedCount: number; readonly assignments: readonly WorkdayAssignment[]}

export class PracticeError extends Error {
  readonly terminalGuest: boolean;
  constructor(readonly code: string, message: string, readonly status: number | null = null,
    readonly retryAfterSeconds: number | null = null) {
    super(message); this.name = 'PracticeError';
    this.terminalGuest = code === 'GUEST_SESSION_EXPIRED' || code === 'GUEST_SESSION_REVOKED' || status === 401;
  }
}
function invalid(): never {throw new PracticeError('PRACTICE_RESPONSE_INVALID', 'The server returned an invalid practice response.');}
function check(condition: unknown): asserts condition {if (!condition) invalid();}
function record(value: unknown): Record<string, unknown> {
  check(value !== null && typeof value === 'object' && !Array.isArray(value)); return value as Record<string, unknown>;
}
function integer(value: unknown, minimum = 0): number {check(typeof value === 'number' && Number.isSafeInteger(value) && value >= minimum); return value;}
function string(value: unknown, max = 300): string {
  check(typeof value === 'string' && value.length > 0 && value.length <= max && value.trim() === value && !/[\u0000-\u001f\u007f]/u.test(value)); return value;
}
function oneOf<const T extends readonly string[]>(value: unknown, choices: T): T[number] {check(typeof value === 'string' && choices.includes(value)); return value;}
function boolean(value: unknown): boolean {check(typeof value === 'boolean'); return value;}
export function parsePracticeUuid(value: unknown): string {
  check(typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu.test(value)); return value.toLowerCase();
}
function instant(value: unknown): string {
  const text = string(value, 32); check(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/u.test(text) && Number.isFinite(Date.parse(text)));
  check(new Date(text).toISOString().slice(0, 19) === text.slice(0, 19)); return text;
}
function nullable<T>(value: unknown, parse: (value: unknown) => T): T | null {return value === null ? null : parse(value);}
function array(value: unknown, maximum = 500): unknown[] {check(Array.isArray(value) && value.length <= maximum); return value;}
function decimal(value: unknown, signed = false, maxDigits = 15): string {
  check(typeof value === 'string' && new RegExp(`^${signed ? '-?' : ''}(0|[1-9][0-9]{0,${maxDigits - 1}})$`, 'u').test(value) && value !== '-0'); return value;
}
function fixed(value: unknown, positive = false): string {return parsePaperFixed(value, {positive}).toString();}
export function freezePracticeValue<T>(value: T): T {
  if (value !== null && typeof value === 'object') {for (const item of Object.values(value)) freezePracticeValue(item); Object.freeze(value);} return value;
}
function validated<T>(parse: () => T): T {
  try {return freezePracticeValue(parse());} catch (error) {if (error instanceof PracticeError) throw error; return invalid();}
}
export function normalizePracticeApiBase(value: string): string {
  if (value === '/api' || value === '/api/') return '/api';
  try {
    const url = new URL(value);
    if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash ||
      (url.pathname !== '/' && url.pathname !== '')) throw new Error();
    return url.origin;
  } catch {throw new PracticeError('PRACTICE_CONFIG_INVALID', 'Use an HTTPS API origin or the same-origin /api relay.');}
}
export function parseGuestCreation(value: unknown): GuestCreationRequest {
  return validated(() => {const v = record(value); check(v['schemaVersion'] === 1);
    const replaySecret = string(v['replaySecret'], 47); check(/^gr1_[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$/u.test(replaySecret));
    return {schemaVersion: 1, requestId: parsePracticeUuid(v['requestId']), replaySecret};});
}
export function parseGuest(value: unknown): GuestCredential {
  return validated(() => {const v = record(value), token = string(v['token'], 47);
    check(/^tg1_[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$/u.test(token));
    const expiresAt = instant(v['expiresAt']), hardExpiresAt = instant(v['hardExpiresAt']);
    check(Date.parse(expiresAt) <= Date.parse(hardExpiresAt));
    return {guestId: parsePracticeUuid(v['guestId']), token, expiresAt, hardExpiresAt};});
}
const checkpoints = ['first-trade', 'first-position', 'streak', 'save-desk', 'app'] as const;
const launchActions = ['paper-trade-confirmed', 'first-position-collected', 'day-one-seen', 'save-desk-later',
  'save-desk-saved', 'introduction-skipped', 'introduction-completed'] as const;
function onboarding(value: unknown): ProductOnboarding {
  const v = record(value), handle = nullable(v['handle'], x => string(x, 18));
  check(handle === null || /^[a-z][a-z0-9_]{2,17}$/u.test(handle));
  return {goal: nullable(v['goal'], x => oneOf(x, ['learn', 'practice', 'trade', 'beat-friends'])),
    knowledge: nullable(v['knowledge'], x => oneOf(x, ['nothing', 'basics', 'practice', 'traded-before', 'daily-trader'])),
    persona: nullable(v['persona'], x => oneOf(x, ['wolf', 'oracle', 'shark'])),
    dailyGoal: nullable(v['dailyGoal'], x => oneOf(x, ['show-up', 'one-mission', 'three-missions'])), handle};
}
export function parseProductProfile(value: unknown): ProductProfile {
  return validated(() => {const v = record(value), createdAt = instant(v['createdAt']), updatedAt = instant(v['updatedAt']);
    check(Date.parse(updatedAt) >= Date.parse(createdAt));
    return {revision: integer(v['revision'], 1), onboarding: onboarding(v['onboarding']),
    launchCheckpoint: oneOf(v['launchCheckpoint'], checkpoints), hasConfirmedPaperTrade: boolean(v['hasConfirmedPaperTrade']),
    createdAt, updatedAt};});
}
export function parseProfileWrite(value: unknown): ProductProfileWrite {
  return validated(() => {const v = record(value); check(v['schemaVersion'] === 2);
    return {schemaVersion: 2, mutationId: parsePracticeUuid(v['mutationId']), baseRevision: integer(v['baseRevision']),
      onboarding: onboarding(v['onboarding']), launchCheckpoint: oneOf(v['launchCheckpoint'], checkpoints)};});
}
export function parseLaunchWrite(value: unknown): ProductLaunchWrite {
  return validated(() => {const v = record(value); check(v['schemaVersion'] === 2);
    return {schemaVersion: 2, mutationId: parsePracticeUuid(v['mutationId']), baseRevision: integer(v['baseRevision'], 1), action: oneOf(v['action'], launchActions)};});
}
function profileResponse(value: unknown): ProductProfile | null {
  const v = record(value); check(v['schemaVersion'] === 2); return nullable(v['profile'], parseProductProfile);
}
function source(value: unknown): PaperPriceSource {
  const v = record(value), stamps = record(v['providerTimestamps']); check(v['provider'] === 'tokens-xyz-v1' && stamps['unit'] === 'not_declared');
  const providerReference = string(v['providerReference']); check(providerReference.startsWith('/v1/assets/'));
  return {provider: 'tokens-xyz-v1', providerReference, marketSource: nullable(v['marketSource'], x => string(x, 80)),
    metricsSource: nullable(v['metricsSource'], x => string(x, 80)), providerTimestamps: {unit: 'not_declared',
      asOf: nullable(stamps['asOf'], x => decimal(x, false, 16)), lastFetchedAt: nullable(stamps['lastFetchedAt'], x => decimal(x, false, 16)),
      lastTradeAt: nullable(stamps['lastTradeAt'], x => decimal(x, false, 16))},
    observedAt: instant(v['observedAt']), acceptedAt: instant(v['acceptedAt'])};
}
function asset(value: Record<string, unknown>) {
  return {assetId: parsePaperAssetId(value['assetId']), variantMint: parsePaperVariantMint(value['variantMint'])};
}
function calculation(value: Record<string, unknown>): PaperCalculation {
  const action = parsePaperOrderAction(value['action']);
  const result = {...asset(value), action, symbol: parsePaperSymbol(value['symbol']), accountRevision: integer(value['accountRevision']),
    pricePaperMicros: fixed(value['pricePaperMicros'], true), quantityMicros: fixed(value['quantityMicros'], true),
    cashDebitPaperMicros: fixed(value['cashDebitPaperMicros']), cashCreditPaperMicros: fixed(value['cashCreditPaperMicros']),
    cashAfterPaperMicros: fixed(value['cashAfterPaperMicros']), positionQuantityAfterMicros: fixed(value['positionQuantityAfterMicros']),
    positionCostBasisAfterPaperMicros: fixed(value['positionCostBasisAfterPaperMicros']),
    realizedGainDeltaPaperMicros: parsePaperSignedFixed(value['realizedGainDeltaPaperMicros']).toString(),
    lockedGainDeltaPaperMicros: fixed(value['lockedGainDeltaPaperMicros']), source: source(value['source'])};
  check((result.positionQuantityAfterMicros === '0') === (result.positionCostBasisAfterPaperMicros === '0'));
  if (action === 'buy') check(result.cashCreditPaperMicros === '0' && result.cashDebitPaperMicros !== '0' &&
    result.realizedGainDeltaPaperMicros === '0' && result.lockedGainDeltaPaperMicros === '0');
  else check(result.cashDebitPaperMicros === '0' && result.cashCreditPaperMicros !== '0');
  if (action === 'sell') check(result.lockedGainDeltaPaperMicros === '0');
  if (action === 'trim') check(BigInt(result.realizedGainDeltaPaperMicros) > 0n &&
    result.lockedGainDeltaPaperMicros === result.realizedGainDeltaPaperMicros && result.positionQuantityAfterMicros !== '0');
  // Derive the pre-trade ledger from the result and verify the shared exact-integer rules.
  const buy = action === 'buy', quantity = BigInt(result.quantityMicros);
  const priorCash = BigInt(result.cashAfterPaperMicros) + BigInt(result.cashDebitPaperMicros) - BigInt(result.cashCreditPaperMicros);
  const priorQuantity = BigInt(result.positionQuantityAfterMicros) + (buy ? -quantity : quantity);
  const priorBasis = BigInt(result.positionCostBasisAfterPaperMicros) + (buy ? -BigInt(result.cashDebitPaperMicros)
    : BigInt(result.cashCreditPaperMicros) - BigInt(result.realizedGainDeltaPaperMicros));
  const calculated = calculatePaperOrder({action, amount: {kind: 'share_quantity', quantityMicros: result.quantityMicros},
    pricePaperMicros: result.pricePaperMicros, cashPaperMicros: priorCash.toString(),
    position: {quantityMicros: priorQuantity.toString(), costBasisPaperMicros: priorBasis.toString()}});
  for (const key of Object.keys(calculated) as (keyof typeof calculated)[]) check(result[key] === calculated[key]);
  return result;
}
export function parsePaperPreview(value: unknown): PaperPreview {
  return validated(() => {const v = record(value), state = oneOf(v['state'], ['open', 'committed']);
    const committedAt = nullable(v['committedAt'], instant); check((state === 'committed') === (committedAt !== null));
    const result = calculation(v), amount = parsePaperOrderAmount(v['amount']);
    if (amount.kind === 'share_quantity') check(amount.quantityMicros === result.quantityMicros);
    else {check(result.action === 'buy'); check(BigInt(amount.paperMicros) * 1_000_000n / BigInt(result.pricePaperMicros) === BigInt(result.quantityMicros));}
    return {...result, id: parsePracticeUuid(v['id']), requestId: parsePracticeUuid(v['requestId']), state,
      amount, expiresAt: instant(v['expiresAt']), committedAt};});
}
export function parsePaperReceipt(value: unknown): PaperReceipt {
  return validated(() => {const v = record(value); integer(v['accountRevision'], 1);
    return {...calculation(v), id: parsePracticeUuid(v['id']), previewId: parsePracticeUuid(v['previewId']), committedAt: instant(v['committedAt'])};});
}
export function parsePaperCommit(value: unknown): PaperCommitRequest {
  return validated(() => {const v = record(value); check(v['schemaVersion'] === 1);
    return {schemaVersion: 1, previewId: parsePracticeUuid(v['previewId']), idempotencyKey: parsePracticeUuid(v['idempotencyKey'])};});
}
function paperEnvelope(value: unknown, version: number): Record<string, unknown> {
  const v = record(value), unit = record(v['unit']); check(v['schemaVersion'] === version && v['mode'] === 'paper' && unit['kind'] === 'paper' && unit['scaleDigits'] === 6); return v;
}
function orderEnvelope(value: unknown): Record<string, unknown> {
  const v = paperEnvelope(value, 1), fees = record(v['fees']), reward = record(v['reward']), execution = record(v['execution']);
  check(fees['paperMicros'] === '0' && reward['trimsAwarded'] === 0); string(reward['reason']);
  for (const key of ['walletUsed', 'transactionBuilt', 'transactionSigned', 'transactionBroadcast']) check(execution[key] === false);
  return v;
}
export function assertReceiptMatches(preview: PaperPreview, receipt: PaperReceipt): void {
  check(receipt.previewId === preview.id && receipt.accountRevision === preview.accountRevision + 1);
  for (const key of ['action', 'assetId', 'variantMint', 'symbol', 'pricePaperMicros', 'quantityMicros', 'cashDebitPaperMicros',
    'cashCreditPaperMicros', 'cashAfterPaperMicros', 'positionQuantityAfterMicros', 'positionCostBasisAfterPaperMicros',
    'realizedGainDeltaPaperMicros', 'lockedGainDeltaPaperMicros'] as const) check(receipt[key] === preview[key]);
}
export function parsePaperPortfolio(value: unknown): PaperPortfolio {
  return validated(() => {
    const v = paperEnvelope(value, 2), revision = integer(v['revision']), cash = fixed(v['cashPaperMicros']);
    const positions = array(v['positions']).map(item => {const p = record(item); return {...asset(p), symbol: parsePaperSymbol(p['symbol']),
      quantityMicros: fixed(p['quantityMicros']), costBasisPaperMicros: fixed(p['costBasisPaperMicros']),
      averageCostPricePaperMicros: decimal(p['averageCostPricePaperMicros'], false, 30), realizedGainPaperMicros: parsePaperSignedFixed(p['realizedGainPaperMicros']).toString(),
      lockedGainPaperMicros: fixed(p['lockedGainPaperMicros']), updatedAt: instant(p['updatedAt'])};});
    const identity = (p: {assetId: string; variantMint: string}) => `${p.assetId}:${p.variantMint}`;
    check(new Set(positions.map(identity)).size === positions.length);
    for (const p of positions) {
      check((p.quantityMicros === '0') === (p.costBasisPaperMicros === '0'));
      check(BigInt(p.averageCostPricePaperMicros) === (p.quantityMicros === '0' ? 0n : BigInt(p.costBasisPaperMicros) * 1_000_000n / BigInt(p.quantityMicros)));
    }
    const openPositions = positions.filter(p => p.quantityMicros !== '0');
    const byId = new Map(openPositions.map(p => [identity(p), p]));
    const val = record(v['valuation']); check(val['portfolioRevision'] === revision && val['cashPaperMicros'] === cash);
    const valuations = array(val['positions']).map(item => {const p = record(item), ids = asset(p), status = oneOf(p['status'], ['priced', 'unavailable']);
      const position = byId.get(identity(ids)); check(position);
      const result = {...ids, status, pricePaperMicros: nullable(p['pricePaperMicros'], x => fixed(x, true)),
        marketValuePaperMicros: nullable(p['marketValuePaperMicros'], x => decimal(x, false, 30)),
        unrealizedGainPaperMicros: nullable(p['unrealizedGainPaperMicros'], x => decimal(x, true, 30)),
        observedAt: nullable(p['observedAt'], instant), acceptedAt: nullable(p['acceptedAt'], instant), expiresAt: nullable(p['expiresAt'], instant)};
      const values = [result.pricePaperMicros, result.marketValuePaperMicros, result.unrealizedGainPaperMicros, result.observedAt, result.acceptedAt, result.expiresAt];
      check(values.every(x => status === 'priced' ? x !== null : x === null));
      if (status === 'priced') {check(BigInt(result.marketValuePaperMicros!) === BigInt(position.quantityMicros) * BigInt(result.pricePaperMicros!) / 1_000_000n);
        check(BigInt(result.unrealizedGainPaperMicros!) === BigInt(result.marketValuePaperMicros!) - BigInt(position.costBasisPaperMicros));
        check(Date.parse(result.expiresAt!) > Date.parse(result.acceptedAt!));}
      return result;});
    check(valuations.length === openPositions.length && new Set(valuations.map(identity)).size === openPositions.length);
    const priced = valuations.filter(p => p.status === 'priced').length;
    check(integer(val['openPositionCount']) === openPositions.length && integer(val['pricedPositionCount']) === priced);
    const status = oneOf(val['status'], ['complete', 'partial', 'unavailable']);
    check(status === (priced === openPositions.length ? 'complete' : priced === 0 ? 'unavailable' : 'partial'));
    const known = decimal(val['knownValuePaperMicros'], false, 30);
    check(BigInt(known) === BigInt(cash) + valuations.reduce((sum, p) => sum + BigInt(p.marketValuePaperMicros ?? '0'), 0n));
    const total = nullable(val['totalPaperMicros'], x => decimal(x, false, 30)); check(total === (status === 'complete' ? known : null));
    const orders = array(v['recentOrders'], 100).map(parsePaperReceipt);
    check(new Set(orders.map(o => o.id)).size === orders.length && orders.every(o => o.accountRevision <= revision));
    const openedAt = nullable(v['openedAt'], instant), updatedAt = nullable(v['updatedAt'], instant);
    check((openedAt === null) === (updatedAt === null));
    check(openedAt === null || Date.parse(updatedAt!) >= Date.parse(openedAt));
    check(orders.every((order, index) => index === 0 || Date.parse(order.committedAt) <= Date.parse(orders[index - 1]!.committedAt)));
    return {schemaVersion: 2, mode: 'paper', unit: {kind: 'paper', scaleDigits: 6}, revision,
      startingCashPaperMicros: fixed(v['startingCashPaperMicros']), cashPaperMicros: cash, openedAt, updatedAt, positions, recentOrders: orders,
      valuation: {status, portfolioRevision: revision, openPositionCount: openPositions.length, pricedPositionCount: priced,
        cashPaperMicros: cash, knownValuePaperMicros: known, totalPaperMicros: total, positions: valuations}};
  });
}
const ranks = ['rookie', 'analyst', 'trader', 'senior-trader', 'partner', 'legend'] as const;
function day(value: unknown): string {const result = string(value, 10); check(/^\d{4}-\d{2}-\d{2}$/u.test(result)); instant(`${result}T00:00:00Z`); return result;}
function storySlug(value: unknown): string {const result = string(value, 80); check(/^[a-z][a-z0-9-]*$/u.test(result)); return result;}
// Daily desk is raw PostgreSQL jsonb: timestamptz can carry six fractional digits and a UTC offset.
function storyInstant(value: unknown): string {
  const result = string(value, 40);
  const match = /^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$/u.exec(result);
  check(match && Number(match[2]) < 24 && Number(match[3]) < 60 && Number(match[4]) < 60);
  day(match[1]);
  if (match[5] !== 'Z') check(Number(match[5]!.slice(1, 3)) < 24 && Number(match[5]!.slice(4, 6)) < 60);
  check(Number.isFinite(Date.parse(result))); return result;
}
export function parseDailyDeskCompletion(value: unknown): DailyDeskCompletion {
  return validated(() => {const v = record(value);
    check(Object.keys(v).length === 3 && Object.keys(v).every(key => ['date', 'caseId', 'choiceId'].includes(key)));
    return {date: day(v['date']), caseId: storySlug(v['caseId']), choiceId: storySlug(v['choiceId'])};});
}
export function parseDailyDeskShift(value: unknown): DailyDeskShift {
  return validated(() => {
    const v = record(value), date = day(v['date']), story = record(v['story']);
    const choices = array(story['choices'], 3).map(item => {const c = record(item); return {id: storySlug(c['id']),
      label: string(c['label'], 240), outcome: string(c['outcome'], 1600), takeaway: string(c['takeaway'], 600)};});
    check(choices.length === 3 && new Set(choices.map(c => c.id)).size === 3);
    const completedChoice = nullable(v['completedChoice'], storySlug), completedAt = nullable(v['completedAt'], storyInstant);
    check((completedChoice === null) === (completedAt === null));
    check(completedChoice === null || choices.some(c => c.id === completedChoice));
    check(v['trimsEarned'] === (completedChoice === null ? 0 : 10));
    const id = storySlug(story['id']), title = string(story['title'], 240), ordinal = integer(story['ordinal']); check(ordinal <= 6);
    const history = array(v['history'], 7).map(item => {const h = record(item); return {date: day(h['date']), caseId: storySlug(h['caseId']),
      title: string(h['title'], 240), choiceId: storySlug(h['choiceId']), completedAt: storyInstant(h['completedAt'])};});
    const earliest = Date.parse(`${date}T00:00:00Z`) - 6 * 86_400_000;
    check(history.every((h, index) => Date.parse(`${h.date}T00:00:00Z`) >= earliest && h.date <= date &&
      (index === 0 || history[index - 1]!.date < h.date)));
    const today = history.find(h => h.date === date);
    check(completedChoice === null ? !today : today?.caseId === id && today.choiceId === completedChoice &&
      today.title === title && today.completedAt === completedAt);
    return {date, story: {id, ordinal, title, speaker: oneOf(story['speaker'], ['sal', 'wolf', 'oracle', 'shark']),
      body: string(story['body'], 4000), choices}, completedChoice, completedAt, history, trimsEarned: completedChoice === null ? 0 : 10};
  });
}
export function parseCareerActivityWeek(value: unknown): CareerActivityWeek {
  return validated(() => {
    const v = record(value), serverDate = day(v['serverDate']), weekStart = day(v['weekStart']);
    const start = Date.parse(`${weekStart}T00:00:00Z`), today = Date.parse(`${serverDate}T00:00:00Z`);
    check(new Date(start).getUTCDay() === 1 && today >= start && today - start <= 6 * 86_400_000);
    const activeDates = array(v['activeDates'], 7).map(day);
    check(new Set(activeDates).size === activeDates.length && activeDates.every(d => d >= weekStart && d <= serverDate));
    return {serverDate, weekStart, activeDates};
  });
}
export function assertDailyDeskCompletion(request: DailyDeskCompletion, shift: DailyDeskShift): void {
  check(shift.date >= request.date);
  const saved = shift.history.find(h => h.date === request.date);
  // The API returns today's shift even when an exact retry confirms a previous day's write.
  if (Date.parse(`${shift.date}T00:00:00Z`) - Date.parse(`${request.date}T00:00:00Z`) <= 6 * 86_400_000) {
    check(saved?.caseId === request.caseId && saved.choiceId === request.choiceId);
  }
}
function workdayText(value: unknown, maximum: number, empty = false): string {
  check(typeof value === 'string' && (empty || value.trim().length > 0) && Array.from(value).length <= maximum &&
    !/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/u.test(value)); return value;
}
function workdayRevision(value: unknown): number {const n = integer(value); check(n <= 2_147_483_646); return n;}
function exactKeys(v: Record<string, unknown>, required: readonly string[], optional: readonly string[] = []): void {
  check(required.every(key => Object.hasOwn(v, key)) && Object.keys(v).every(key => required.includes(key) || optional.includes(key)));
}
function workdayAnswer(value: unknown, step: number): WorkdayAnswer {
  const v = record(value);
  if (step === 1) {exactKeys(v, ['value']); return {value: workdayText(v['value'], 80)};}
  exactKeys(v, ['ids']); const ids = array(v['ids'], 6).map(storySlug);
  check(ids.length > 0 && new Set(ids).size === ids.length); return {ids};
}
export function parseWorkdayStepWrite(value: unknown): WorkdayStepWrite {
  return validated(() => {const v = record(value); exactKeys(v, ['assignmentId', 'revision', 'step', 'answer'], ['draft']);
    const step = integer(v['step']); check(step <= 2);
    return {assignmentId: storySlug(v['assignmentId']), revision: workdayRevision(v['revision']), step: step as 0 | 1 | 2,
      answer: workdayAnswer(v['answer'], step), ...(v['draft'] === undefined ? {} : {draft: workdayText(v['draft'], 280, true)})};
  });
}
export function parseWorkdayDraftWrite(value: unknown): WorkdayDraftWrite {
  return validated(() => {const v = record(value); exactKeys(v, ['assignmentId', 'revision', 'draft']);
    return {assignmentId: storySlug(v['assignmentId']), revision: workdayRevision(v['revision']), draft: workdayText(v['draft'], 280, true)};});
}
export function parseWorkdayMutation(value: unknown): WorkdayMutation {
  return validated(() => {const v = record(value); exactKeys(v, ['kind', 'body']);
    check(v['kind'] === 'step' || v['kind'] === 'draft');
    return v['kind'] === 'step' ? {kind: 'step', body: parseWorkdayStepWrite(v['body'])} : {kind: 'draft', body: parseWorkdayDraftWrite(v['body'])};});
}
export function parseWorkdayAssignment(value: unknown): WorkdayAssignment {
  return validated(() => {
    const v = record(value), evidence = record(v['evidence']), decision = record(v['decision']), file = record(v['file']);
    const rows = array(v['rows'], 30).map(item => {const row = record(item); return {id: storySlug(row['id']), label: string(row['label'], 240),
      value: workdayText(row['value'], 1600), detail: workdayText(row['detail'], 1600)};});
    const parts = array(file['parts'], 30).map(item => {const part = record(item); return {id: storySlug(part['id']), text: workdayText(part['text'], 1600)};});
    const evidenceCount = integer(evidence['count'], 1), fileCount = integer(file['count'], 1);
    check(rows.length > 0 && parts.length > 0 && evidenceCount <= 6 && fileCount <= 6 && evidenceCount <= rows.length && fileCount <= parts.length);
    check(new Set(rows.map(row => row.id)).size === rows.length && new Set(parts.map(part => part.id)).size === parts.length);
    const kind = oneOf(decision['kind'], ['number', 'choice']);
    const choices = array(decision['choices'], 30).map(item => {const choice = record(item); return {id: storySlug(choice['id']),
      label: workdayText(choice['label'], 400), feedback: workdayText(choice['feedback'], 1600)};});
    check(kind === 'number' ? choices.length === 0 : choices.length > 0);
    check(new Set(choices.map(choice => choice.id)).size === choices.length);
    const step = integer(v['step']); check(step <= 3);
    const revision = integer(v['revision']); check(revision >= step && revision <= 2_147_483_647);
    const saved = record(v['answers']), answers: Partial<Record<'0' | '1' | '2', WorkdayAnswer>> = {};
    check(Object.keys(saved).length === step && Object.keys(saved).every(key => ['0', '1', '2'].includes(key) && Number(key) < step));
    for (let index = 0; index < step; index++) {
      const key = String(index) as '0' | '1' | '2', answer = workdayAnswer(saved[key], index);
      if ('ids' in answer) {
        const source = index === 0 ? rows : parts, count = index === 0 ? evidenceCount : fileCount;
        check(answer.ids.length === count && answer.ids.every(id => source.some(item => item.id === id)));
      } else if (kind === 'choice') check(choices.some(choice => choice.id === answer.value));
      else check(/^-?(?:0|[1-9][0-9]{0,8})(?:\.[0-9]{1,6})?$/u.test(answer.value));
      answers[key] = answer;
    }
    const draft = workdayText(v['draft'], 280, true), completedAt = nullable(v['completedAt'], storyInstant);
    const artifact = nullable(v['artifact'], item => workdayText(item, 12_000)), feedback = nullable(v['feedback'], item => workdayText(item, 4000));
    check(step === 3 ? completedAt !== null && artifact !== null && feedback !== null : completedAt === null && artifact === null && feedback === null);
    return {id: storySlug(v['id']), ordinal: integer(v['ordinal'], 1), title: string(v['title'], 240), speaker: oneOf(v['speaker'], ['sal', 'wolf', 'oracle', 'shark']),
      district: string(v['district'], 240), brief: workdayText(v['brief'], 4000), sourceTitle: string(v['sourceTitle'], 400), sourceLabel: string(v['sourceLabel'], 240),
      art: storySlug(v['art']), rows, evidence: {prompt: workdayText(evidence['prompt'], 1600), count: evidenceCount},
      decision: {kind, prompt: workdayText(decision['prompt'], 1600), hint: workdayText(decision['hint'], 1600), choices, unit: nullable(decision['unit'], item => string(item, 40))},
      file: {prompt: workdayText(file['prompt'], 1600), count: fileCount, parts}, revision, step: step as 0 | 1 | 2 | 3, answers, draft, completedAt, artifact, feedback,
      contextNote: nullable(v['contextNote'], item => workdayText(item, 4000))};
  });
}
export function parseWorkdayJourney(value: unknown): WorkdayJourney {
  return validated(() => {const v = record(value), contentVersion = string(v['contentVersion'], 100); check(/^[a-z0-9.-]+$/u.test(contentVersion));
    const assignments = array(v['assignments'], 200).map(parseWorkdayAssignment); check(assignments.length > 0);
    check(new Set(assignments.map(item => item.id)).size === assignments.length && assignments.every((item, index) => item.ordinal === index + 1));
    const completedCount = integer(v['completedCount']); check(completedCount <= assignments.length);
    check(assignments.every((item, index) => (item.completedAt !== null) === (index < completedCount) &&
      (index <= completedCount || item.step === 0 && item.revision === 0)));
    return {contentVersion, date: day(v['date']), completedCount, assignments};
  });
}
function normalizedWorkdayAnswer(answer: WorkdayAnswer, kind: 'number' | 'choice'): string {
  if ('ids' in answer) return JSON.stringify([...answer.ids].sort());
  if (kind === 'choice') return answer.value;
  check(/^-?[0-9]{1,9}(?:\.[0-9]{1,6})?$/u.test(answer.value));
  const negative = answer.value.startsWith('-'), text = negative ? answer.value.slice(1) : answer.value;
  const [whole, fraction = ''] = text.split('.');
  const units = BigInt(whole!) * 1_000_000n + BigInt(fraction.padEnd(6, '0'));
  return (negative ? -units : units).toString();
}
function assertWorkdayMutation(mutation: WorkdayMutation, journey: WorkdayJourney): void {
  const assignment = journey.assignments.find(item => item.id === mutation.body.assignmentId); check(assignment);
  if (mutation.kind === 'draft') {
    check(assignment.step === 2 && assignment.draft === mutation.body.draft && assignment.revision >= mutation.body.revision);
  } else {
    check(assignment.step > mutation.body.step && assignment.revision > mutation.body.revision);
    const answer = assignment.answers[String(mutation.body.step) as '0' | '1' | '2']; check(answer);
    check(normalizedWorkdayAnswer(answer, assignment.decision.kind) === normalizedWorkdayAnswer(mutation.body.answer, assignment.decision.kind));
    if (mutation.body.step === 2 && mutation.body.draft !== undefined) check(assignment.draft === mutation.body.draft);
  }
}
function careerSummary(value: unknown): CareerSummary {
  const envelope = record(value); check(envelope['schemaVersion'] === 1);
  const v = record(envelope['career']), trims = record(v['trims']), rank = record(v['rank']), streak = record(v['streak']);
  return {revision: integer(v['revision']), trims: {total: integer(trims['total']), today: integer(trims['today']), thisWeek: integer(trims['thisWeek'])},
    rank: {id: oneOf(rank['id'], ranks), label: string(rank['label'], 80), paperLimit: decimal(rank['paperLimit']), threshold: integer(rank['threshold'])},
    nextRank: nullable(v['nextRank'], item => {const r = record(item); return {id: oneOf(r['id'], ranks), label: string(r['label'], 80),
      threshold: integer(r['threshold']), trimsRemaining: integer(r['trimsRemaining']), promotionRequired: boolean(r['promotionRequired'])};}),
    streak: {days: integer(streak['days']), status: oneOf(streak['status'], ['not-started', 'active', 'at-risk', 'grace']), lastActiveDate: nullable(streak['lastActiveDate'], day)},
    careerStarted: boolean(v['careerStarted']), firstConfirmedBuy: nullable(v['firstConfirmedBuy'], item => {const b = record(item);
      return {...asset(b), orderId: parsePracticeUuid(b['orderId']), symbol: parsePaperSymbol(b['symbol']), quantityMicros: fixed(b['quantityMicros'], true), confirmedAt: instant(b['confirmedAt'])};}),
    serverDate: day(v['serverDate']), updatedAt: nullable(v['updatedAt'], instant)};
}
function missions(value: unknown): CareerMissionBoard {
  const v = record(value), career = record(v['career']); check(v['schemaVersion'] === 1);
  const parsed = array(v['missions'], 30).map(item => {const m = record(item); check(m['trimsReward'] === 20);
    const status = oneOf(m['status'], ['locked', 'ready', 'complete']), completedAt = nullable(m['completedAt'], instant);
    check((status === 'complete') === (completedAt !== null));
    return {id: oneOf(m['id'], ['first-paper-buy', 'write-a-reason', 'hold-through-red-day']), chapterRank: oneOf(m['chapterRank'], ranks),
      order: integer(m['order'], 1), kind: oneOf(m['kind'], ['action', 'promotion']), title: string(m['title'], 160), instruction: string(m['instruction'], 600),
      trimsReward: 20 as const, promotesToRank: nullable(m['promotesToRank'], x => oneOf(x, ranks)), status, completedAt};});
  check(new Set(parsed.map(m => m.id)).size === parsed.length);
  return {revision: integer(career['revision']), currentRank: oneOf(career['currentRank'], ranks), missions: parsed};
}

export interface PracticeClientOptions {readonly baseUrl: string; readonly fetch?: typeof globalThis.fetch; readonly timeoutMs?: number}
export class PracticeClient {
  readonly apiBase: string;
  readonly #fetch: typeof globalThis.fetch;
  readonly #timeoutMs: number;
  constructor(options: PracticeClientOptions) {
    this.apiBase = normalizePracticeApiBase(options.baseUrl); this.#fetch = options.fetch ?? globalThis.fetch.bind(globalThis);
    this.#timeoutMs = options.timeoutMs ?? 15_000;
    if (!Number.isSafeInteger(this.#timeoutMs) || this.#timeoutMs < 1 || this.#timeoutMs > 120_000) throw new PracticeError('PRACTICE_CONFIG_INVALID', 'Invalid request timeout.');
  }
  async #request<T>(path: string, method: 'GET' | 'POST' | 'PUT', body: unknown, identity: PracticeIdentity | null,
    parse: (value: unknown) => T, signal?: AbortSignal, accept = 'application/json', expectedStatus = 200, claimGuest?: GuestCredential): Promise<T> {
    const account = identity && 'subject' in identity ? identity : null;
    if (signal?.aborted || account?.signal.aborted) throw new PracticeError('PRACTICE_ABORTED', 'Practice request cancelled.');
    const controller = new AbortController();
    let stop!: (reason: PracticeError) => void;
    const interrupted = new Promise<never>((_resolve, reject) => {stop = reject;});
    const abort = () => {controller.abort(); stop(new PracticeError('PRACTICE_ABORTED', 'Practice request cancelled.'));};
    signal?.addEventListener('abort', abort, {once: true});
    account?.signal.addEventListener('abort', abort, {once: true});
    const timer = setTimeout(() => {controller.abort(); stop(new PracticeError('PRACTICE_TIMEOUT', 'The request timed out. Retry to check its result.'));}, this.#timeoutMs);
    const task = async (): Promise<T> => {
      const headers: Record<string, string> = {Accept: accept};
      if (body !== undefined) headers['Content-Type'] = 'application/json';
      if (account) {
        parsePracticeSubject(account.subject);
        const token = await account.freshAccessToken();
        if (controller.signal.aborted) throw new PracticeError('PRACTICE_ABORTED', 'Practice request cancelled.');
        if (typeof token !== 'string' || !/^[A-Za-z0-9._~-]{1,16384}$/u.test(token)) {
          throw new PracticeError('PRACTICE_ACCOUNT_REQUIRED', 'Sign in again to access this desk.', 401);
        }
        headers['Authorization'] = `Bearer ${token}`;
      } else if (identity) headers['Authorization'] = `Guest ${parseGuest(identity).token}`;
      if (claimGuest) {check(path === '/v1/guest/claim' && account !== null); headers['x-trimmy-guest'] = parseGuest(claimGuest).token;}
      const response = await this.#fetch(`${this.apiBase}${path}`, {method, headers,
        ...(body === undefined ? {} : {body: JSON.stringify(body)}), signal: controller.signal, credentials: 'omit', cache: 'no-store', redirect: 'error'});
      if (response.redirected) invalid();
      const media = response.headers.get('content-type')?.split(';')[0]?.trim().toLowerCase();
      check(media === (response.ok ? accept : 'application/json'));
      const reader = response.body?.getReader(); check(reader);
      const cancelBody = () => {void reader.cancel().catch(() => undefined);};
      controller.signal.addEventListener('abort', cancelBody, {once: true});
      const chunks: Uint8Array[] = []; let size = 0;
      try {while (true) {const next = await reader.read(); if (next.done) break; size += next.value.byteLength;
        if (size > (path.startsWith('/v1/career/workdays') ? 524_288 : 262_144)) {void reader.cancel().catch(() => undefined); invalid();} chunks.push(next.value);}}
      finally {controller.signal.removeEventListener('abort', cancelBody); reader.releaseLock();}
      const bytes = new Uint8Array(size); let offset = 0;
      for (const chunk of chunks) {bytes.set(chunk, offset); offset += chunk.length;}
      let json: unknown; try {json = JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(bytes));} catch {return invalid();}
      if (!response.ok) {
        const envelope = record(json);
        const dailyRoute = path === '/v1/career/daily-desk' || path === '/v1/career/daily-desk/complete' ||
          ['/v1/career/workdays', '/v1/career/workdays/step', '/v1/career/workdays/draft'].includes(path);
        const error = dailyRoute && typeof envelope['code'] === 'string' ? envelope : record(envelope['error']);
        const code = string(error['code'], 100); check(/^[A-Z][A-Z0-9_]+$/u.test(code));
        const retry = response.headers.get('retry-after');
        throw new PracticeError(code, 'The practice request could not be completed.', response.status,
          retry && /^[0-9]{1,6}$/u.test(retry) ? Number(retry) : null);
      }
      check(response.status === expectedStatus); return validated(() => parse(json));
    };
    try {return await Promise.race([task(), interrupted]);}
    catch (error) {if (error instanceof PracticeError) throw error; throw new PracticeError('PRACTICE_NETWORK_ERROR', 'Could not reach your practice desk. Retry to check its result.');}
    finally {clearTimeout(timer); signal?.removeEventListener('abort', abort); account?.signal.removeEventListener('abort', abort); controller.abort();}
  }
  claimGuest(guest: GuestCredential, account: PracticeAccountProof, request: GuestClaimRequest, signal?: AbortSignal): Promise<GuestClaimResult> {
    check(request.schemaVersion === 1);
    const body = {schemaVersion: 1, idempotencyKey: parsePracticeUuid(request.idempotencyKey)};
    return this.#request('/v1/guest/claim', 'POST', body, account, value => {const v = record(value);
      check(v['schemaVersion'] === 1 && v['status'] === 'claimed' && v['guestId'] === guest.guestId);
      return {guestId: parsePracticeUuid(v['guestId']), claimedAt: instant(v['claimedAt'])};
    }, signal, 'application/json', 200, guest);
  }
  openAccount(account: PracticeAccountProof, signal?: AbortSignal): Promise<string> {
    return this.#request('/v1/practice/session', 'POST', {}, account, value => {const v = record(value);
      check(v['schemaVersion'] === 1); return parsePracticeUuid(v['userId']);}, signal);
  }
  createGuest(request: GuestCreationRequest, signal?: AbortSignal): Promise<GuestCredential> {
    const body = parseGuestCreation(request);
    return this.#request('/v1/guest/session', 'POST', body, null, value => {const v = record(value);
      check(v['schemaVersion'] === 1 && v['requestId'] === body.requestId); return parseGuest(v);}, signal, 'application/json', 201);
  }
  refreshGuest(guest: GuestCredential, signal?: AbortSignal): Promise<GuestCredential> {
    return this.#request('/v1/guest/session/refresh', 'POST', {schemaVersion: 1}, guest, value => {const v = record(value);
      check(v['schemaVersion'] === 1 && v['guestId'] === guest.guestId && v['hardExpiresAt'] === guest.hardExpiresAt);
      const refreshed = parseGuest({...v, token: guest.token}); check(Date.parse(refreshed.expiresAt) >= Date.parse(guest.expiresAt));
      return refreshed;}, signal);
  }
  readProfile(guest: PracticeIdentity, signal?: AbortSignal): Promise<ProductProfile | null> {
    return this.#request('/v1/product/profile', 'GET', undefined, guest, profileResponse, signal, PROFILE_MEDIA_TYPE);
  }
  writeProfile(guest: PracticeIdentity, request: ProductProfileWrite, signal?: AbortSignal): Promise<ProductProfile> {
    const body = parseProfileWrite(request);
    return this.#request('/v1/product/profile', 'PUT', body, guest, value => {const profile = profileResponse(value); check(profile); return profile;}, signal, PROFILE_MEDIA_TYPE);
  }
  advanceLaunch(guest: PracticeIdentity, request: ProductLaunchWrite, signal?: AbortSignal): Promise<ProductProfile> {
    return this.#request('/v1/product/launch', 'POST', parseLaunchWrite(request), guest, value => {const profile = profileResponse(value); check(profile); return profile;}, signal, PROFILE_MEDIA_TYPE);
  }
  readPortfolio(guest: PracticeIdentity, signal?: AbortSignal): Promise<PaperPortfolio> {
    return this.#request('/v1/account/paper/portfolio', 'GET', undefined, guest, parsePaperPortfolio, signal, PORTFOLIO_MEDIA_TYPE);
  }
  previewOrder(guest: PracticeIdentity, request: PaperPreviewRequest, signal?: AbortSignal): Promise<PaperPreview> {
    const body: PaperPreviewRequest = validated(() => ({schemaVersion: 1, requestId: parsePracticeUuid(request.requestId),
      action: parsePaperOrderAction(request.action), assetId: parsePaperAssetId(request.assetId), variantMint: parsePaperVariantMint(request.variantMint), amount: parsePaperOrderAmount(request.amount)}));
    return this.#request('/v1/account/paper/orders/preview', 'POST', body, guest, value => {
      const preview = parsePaperPreview(orderEnvelope(value)['preview']);
      check(preview.requestId === body.requestId && preview.action === body.action && preview.assetId === body.assetId && preview.variantMint === body.variantMint);
      check(preview.state === 'open');
      if (body.action === 'buy' || body.amount.kind === 'share_quantity') check(JSON.stringify(preview.amount) === JSON.stringify(body.amount));
      return preview;}, signal);
  }
  commitOrder(guest: PracticeIdentity, request: PaperCommitRequest, preview: PaperPreview, signal?: AbortSignal): Promise<PaperReceipt> {
    const body = parsePaperCommit(request); check(body.previewId === preview.id);
    return this.#request('/v1/account/paper/orders/commit', 'POST', body, guest, value => {
      const receipt = parsePaperReceipt(orderEnvelope(value)['order']); assertReceiptMatches(preview, receipt); return receipt;}, signal);
  }
  readCareerSummary(guest: PracticeIdentity, signal?: AbortSignal): Promise<CareerSummary> {
    return this.#request('/v1/career/summary', 'GET', undefined, guest, careerSummary, signal);
  }
  readWorkdays(identity: PracticeIdentity, signal?: AbortSignal): Promise<WorkdayJourney> {
    return this.#request('/v1/career/workdays', 'GET', undefined, identity, value => parseWorkdayJourney(record(value)['journey']), signal);
  }
  saveWorkdayStep(identity: PracticeIdentity, request: WorkdayStepWrite, signal?: AbortSignal): Promise<WorkdayJourney> {
    const body = parseWorkdayStepWrite(request);
    return this.#request('/v1/career/workdays/step', 'POST', body, identity, value => {
      const journey = parseWorkdayJourney(record(value)['journey']); assertWorkdayMutation({kind: 'step', body}, journey); return journey;
    }, signal);
  }
  saveWorkdayDraft(identity: PracticeIdentity, request: WorkdayDraftWrite, signal?: AbortSignal): Promise<WorkdayJourney> {
    const body = parseWorkdayDraftWrite(request);
    return this.#request('/v1/career/workdays/draft', 'POST', body, identity, value => {
      const journey = parseWorkdayJourney(record(value)['journey']); assertWorkdayMutation({kind: 'draft', body}, journey); return journey;
    }, signal);
  }
  readDailyDesk(identity: PracticeIdentity, signal?: AbortSignal): Promise<DailyDeskShift> {
    return this.#request('/v1/career/daily-desk', 'GET', undefined, identity, value => parseDailyDeskShift(record(value)['shift']), signal);
  }
  completeDailyDesk(identity: PracticeIdentity, request: DailyDeskCompletion, signal?: AbortSignal): Promise<DailyDeskShift> {
    const body = parseDailyDeskCompletion(request);
    return this.#request('/v1/career/daily-desk/complete', 'POST', body, identity, value => {
      const shift = parseDailyDeskShift(record(value)['shift']); assertDailyDeskCompletion(body, shift); return shift;
    }, signal);
  }
  readActivityWeek(identity: PracticeIdentity, signal?: AbortSignal): Promise<CareerActivityWeek> {
    return this.#request('/v1/career/activity-week', 'GET', undefined, identity, value => {
      const v = record(value); check(v['schemaVersion'] === 1); return parseCareerActivityWeek(v['activityWeek']);
    }, signal);
  }
  readMissions(guest: PracticeIdentity, signal?: AbortSignal): Promise<CareerMissionBoard> {
    return this.#request('/v1/career/missions', 'GET', undefined, guest, missions, signal);
  }
}
