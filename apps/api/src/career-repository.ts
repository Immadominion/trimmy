export const CAREER_RANKS = Object.freeze([
  'rookie',
  'analyst',
  'trader',
  'senior-trader',
  'partner',
  'legend',
] as const);

export const CAREER_STREAK_STATUSES = Object.freeze([
  'not-started',
  'active',
  'at-risk',
  'grace',
] as const);

export type CareerRank = typeof CAREER_RANKS[number];
export type CareerStreakStatus = typeof CAREER_STREAK_STATUSES[number];

const rankRules: Readonly<Record<CareerRank, Readonly<{
  label: string;
  paperLimit: string;
  threshold: number;
  next: CareerRank | null;
}>>> = Object.freeze({
  rookie: Object.freeze({label: 'Rookie', paperLimit: '10000', threshold: 0, next: 'analyst'}),
  analyst: Object.freeze({label: 'Analyst', paperLimit: '10000', threshold: 300, next: 'trader'}),
  trader: Object.freeze({label: 'Trader', paperLimit: '10000', threshold: 900, next: 'senior-trader'}),
  'senior-trader': Object.freeze({
    label: 'Senior Trader', paperLimit: '10000', threshold: 2000, next: 'partner',
  }),
  partner: Object.freeze({label: 'Partner', paperLimit: '10000', threshold: 4500, next: 'legend'}),
  legend: Object.freeze({label: 'Legend', paperLimit: '10000', threshold: 10000, next: null}),
});

export const CAREER_MISSION_IDS = Object.freeze([
  'first-paper-buy',
  'write-a-reason',
  'hold-through-red-day',
] as const);
export const CAREER_MISSION_STATUSES = Object.freeze(['locked', 'ready', 'complete'] as const);
export const CAREER_MISSION_KINDS = Object.freeze(['action', 'promotion'] as const);

export type CareerMissionId = typeof CAREER_MISSION_IDS[number];
export type CareerMissionStatus = typeof CAREER_MISSION_STATUSES[number];
export type CareerMissionKind = typeof CAREER_MISSION_KINDS[number];

const missionRules: Readonly<Record<CareerMissionId, Readonly<{
  chapterRank: CareerRank;
  order: number;
  kind: CareerMissionKind;
  title: string;
  instruction: string;
  promotesToRank: CareerRank | null;
}>>> = Object.freeze({
  'first-paper-buy': Object.freeze({chapterRank: 'rookie', order: 1, kind: 'action',
    title: 'Buy your first stock', instruction: 'Complete one paper buy.', promotesToRank: null}),
  'write-a-reason': Object.freeze({chapterRank: 'rookie', order: 2, kind: 'action',
    title: 'Write your reason', instruction: 'Add a reason to a paper buy you still hold.',
    promotesToRank: null}),
  'hold-through-red-day': Object.freeze({chapterRank: 'rookie', order: 3, kind: 'promotion',
    title: 'Hold through a red day',
    instruction: 'Hold a stock through a verified red Wall Street day.', promotesToRank: 'analyst'}),
});

export interface CareerRankProgress {
  readonly id: CareerRank;
  readonly label: string;
  readonly paperLimit: string;
  readonly threshold: number;
}

export interface CareerNextRank {
  readonly id: CareerRank;
  readonly label: string;
  readonly threshold: number;
  readonly trimsRemaining: number;
  readonly promotionRequired: boolean;
}

export interface CareerStreak {
  readonly days: number;
  readonly status: CareerStreakStatus;
  readonly lastActiveDate: string | null;
}

export interface CareerSummary {
  readonly revision: number;
  readonly trims: Readonly<{
    total: number;
    today: number;
    thisWeek: number;
  }>;
  readonly rank: CareerRankProgress;
  readonly nextRank: CareerNextRank | null;
  readonly streak: CareerStreak;
  readonly careerStarted: boolean;
  readonly firstConfirmedBuy: Readonly<{
    orderId: string;
    assetId: string;
    variantMint: string;
    symbol: string;
    quantityMicros: string;
    confirmedAt: string;
  }> | null;
  readonly serverDate: string;
  readonly updatedAt: string | null;
}

export interface CareerMission {
  readonly id: CareerMissionId;
  readonly chapterRank: CareerRank;
  readonly order: number;
  readonly kind: CareerMissionKind;
  readonly title: string;
  readonly instruction: string;
  readonly trimsReward: 20;
  readonly promotesToRank: CareerRank | null;
  readonly status: CareerMissionStatus;
  readonly completedAt: string | null;
}

export interface CareerMissionBoard {
  readonly revision: number;
  readonly currentRank: CareerRank;
  readonly missions: readonly CareerMission[];
}

export interface CareerTradeReasonWrite {
  readonly mutationId: string;
  readonly orderId: string;
  readonly note: string;
}

export interface CareerTradeReasonReceipt {
  readonly orderId: string;
  readonly assetId: string;
  readonly variantMint: string;
  readonly note: string;
  readonly trimsAwarded: number;
  readonly dailyAwardNumber: number | null;
  readonly savedAt: string;
}

export interface CareerPromotionWrite {
  readonly mutationId: string;
  readonly targetRank: CareerRank;
}

export interface CareerPromotionReceipt {
  readonly mutationId: string;
  readonly fromRank: CareerRank;
  readonly toRank: CareerRank;
  readonly careerRevision: number;
  readonly trimsAwarded: 100;
  readonly promotedAt: string;
}

export interface CareerDayContext {
  readonly revision: number;
  readonly timeZone: string;
  readonly configured: boolean;
  readonly serverDate: string;
  readonly nextDayAt: string;
  readonly createdAt: string;
  readonly updatedAt: string;
}

export interface CareerDayContextWrite {
  readonly mutationId: string;
  readonly baseRevision: number;
  readonly timeZone: string;
}

export interface CareerActivityWeek { readonly serverDate: string; readonly weekStart: string; readonly activeDates: readonly string[] }

export interface CareerRepository {
  getActivityWeek?(userId: string): Promise<CareerActivityWeek>;
  getSummary(userId: string): Promise<CareerSummary>;
  getMissions(userId: string): Promise<CareerMissionBoard>;
  getDayContext(userId: string): Promise<CareerDayContext>;
  saveDayContext(userId: string, command: CareerDayContextWrite): Promise<CareerDayContext>;
  saveTradeReason(userId: string, command: CareerTradeReasonWrite): Promise<CareerTradeReasonReceipt>;
  promote(userId: string, command: CareerPromotionWrite): Promise<CareerPromotionReceipt>;
}

export type CareerRepositoryErrorCode =
  | 'CAREER_INVALID_INPUT'
  | 'CAREER_ACCOUNT_NOT_FOUND'
  | 'CAREER_PROFILE_REQUIRED'
  | 'CAREER_ORDER_NOT_FOUND'
  | 'CAREER_BUY_ORDER_REQUIRED'
  | 'CAREER_POSITION_REQUIRED'
  | 'CAREER_REASON_EXISTS'
  | 'CAREER_IDEMPOTENCY_CONFLICT'
  | 'CAREER_DAY_CONTEXT_REVISION_CONFLICT'
  | 'CAREER_TIME_ZONE_CHANGE_TOO_SOON'
  | 'CAREER_PROMOTION_RANK_MISMATCH'
  | 'CAREER_PROMOTION_THRESHOLD_REQUIRED'
  | 'CAREER_PROMOTION_MISSION_REQUIRED'
  | 'CAREER_REVISION_EXHAUSTED'
  | 'CAREER_STORAGE_INVALID'
  | 'CAREER_RUNTIME_ROLE_INVALID';

export class CareerRepositoryError extends Error {
  constructor(readonly code: CareerRepositoryErrorCode, message: string) {
    super(message);
    this.name = 'CareerRepositoryError';
  }
}

function invalid(): never {
  throw new CareerRepositoryError('CAREER_INVALID_INPUT', 'Career input is invalid.');
}

function fields(input: unknown, expected: readonly string[]): Readonly<Record<string, unknown>> {
  if (input === null || typeof input !== 'object' || Array.isArray(input)) invalid();
  const prototype: unknown = Object.getPrototypeOf(input);
  if (prototype !== Object.prototype && prototype !== null) invalid();
  const keys = Reflect.ownKeys(input);
  if (keys.length !== expected.length ||
      keys.some(key => typeof key !== 'string' || !expected.includes(key))) invalid();
  const result: Record<string, unknown> = Object.create(null) as Record<string, unknown>;
  for (const key of keys) {
    const descriptor = Object.getOwnPropertyDescriptor(input, key);
    if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) invalid();
    result[key as string] = descriptor.value;
  }
  return Object.freeze(result);
}

function uuid(input: unknown): string {
  if (typeof input !== 'string' ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(input)) invalid();
  return input.toLowerCase();
}

function integer(input: unknown, minimum = 0): number {
  if (typeof input !== 'number' || !Number.isSafeInteger(input) || input < minimum) invalid();
  return input;
}

function member<T extends string>(input: unknown, values: readonly T[]): T {
  if (typeof input !== 'string' || !values.includes(input as T)) invalid();
  return input as T;
}

function timestamp(input: unknown): string {
  if (typeof input !== 'string' ||
      !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(input) ||
      new Date(input).toISOString() !== input) invalid();
  return input;
}

function date(input: unknown): string {
  if (typeof input !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(input)) invalid();
  const parsed = new Date(`${input}T00:00:00.000Z`);
  if (!Number.isFinite(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== input) invalid();
  return input;
}

function decimal(input: unknown): string {
  if (typeof input !== 'string' || !/^(0|[1-9][0-9]*)(\.[0-9]{1,6})?$/.test(input)) invalid();
  return input;
}

function positiveIntegerText(input: unknown): string {
  if (typeof input !== 'string' || !/^[1-9][0-9]{0,14}$/.test(input)) invalid();
  return input;
}

function assetId(input: unknown): string {
  if (typeof input !== 'string' || input.length > 100 ||
      !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(input)) invalid();
  return input;
}

function solanaAddress(input: unknown): string {
  if (typeof input !== 'string' || !/^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(input)) invalid();
  return input;
}

function text(input: unknown, minimum: number, maximum: number): string {
  if (typeof input !== 'string' || input !== input.trim() ||
      [...input].length < minimum || [...input].length > maximum ||
      /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/u.test(input)) invalid();
  return input;
}

function timeZone(input: unknown): string {
  if (typeof input !== 'string' || input.length > 100 || input !== input.trim() ||
      (input !== 'UTC' && !/^[A-Za-z][A-Za-z0-9._+-]*\/[A-Za-z0-9._+-]+(?:\/[A-Za-z0-9._+-]+)*$/u.test(input)) ||
      input.startsWith('posix/') || input.startsWith('right/')) invalid();
  return input;
}

function optional<T>(input: unknown, parse: (value: unknown) => T): T | null {
  return input === null ? null : parse(input);
}

export function parseCareerUserId(input: unknown): string { return uuid(input); }

export function parseCareerTradeReasonWrite(input: unknown): CareerTradeReasonWrite {
  const value = fields(input, ['mutationId', 'orderId', 'note']);
  return Object.freeze({
    mutationId: uuid(value['mutationId']),
    orderId: uuid(value['orderId']),
    note: text(value['note'], 1, 180),
  });
}

export function parseCareerPromotionWrite(input: unknown): CareerPromotionWrite {
  const value = fields(input, ['mutationId', 'targetRank']);
  const targetRank = member(value['targetRank'], CAREER_RANKS);
  if (targetRank === 'rookie') invalid();
  return Object.freeze({mutationId: uuid(value['mutationId']), targetRank});
}

export function parseCareerDayContextWrite(input: unknown): CareerDayContextWrite {
  const value = fields(input, ['mutationId', 'baseRevision', 'timeZone']);
  return Object.freeze({
    mutationId: uuid(value['mutationId']),
    baseRevision: integer(value['baseRevision'], 1),
    timeZone: timeZone(value['timeZone']),
  });
}

export function parseCareerDayContext(input: unknown): CareerDayContext {
  try {
    const value = fields(input, [
      'revision', 'timeZone', 'configured', 'serverDate', 'nextDayAt', 'createdAt', 'updatedAt',
    ]);
    if (typeof value['configured'] !== 'boolean') invalid();
    const parsed: CareerDayContext = Object.freeze({
      revision: integer(value['revision'], 1),
      timeZone: timeZone(value['timeZone']),
      configured: value['configured'],
      serverDate: date(value['serverDate']),
      nextDayAt: timestamp(value['nextDayAt']),
      createdAt: timestamp(value['createdAt']),
      updatedAt: timestamp(value['updatedAt']),
    });
    if (parsed.updatedAt < parsed.createdAt || parsed.nextDayAt <= parsed.updatedAt ||
        (!parsed.configured && (parsed.revision !== 1 || parsed.timeZone !== 'UTC' ||
          parsed.createdAt !== parsed.updatedAt))) invalid();
    return parsed;
  } catch {
    throw new CareerRepositoryError(
      'CAREER_STORAGE_INVALID',
      'Stored Career day context could not be read safely.',
    );
  }
}

export function parseCareerSummary(input: unknown): CareerSummary {
  try {
    const value = fields(input, [
      'revision', 'trims', 'rank', 'nextRank', 'streak', 'careerStarted',
      'firstConfirmedBuy', 'serverDate', 'updatedAt',
    ]);
    const trims = fields(value['trims'], ['total', 'today', 'thisWeek']);
    const rank = fields(value['rank'], ['id', 'label', 'paperLimit', 'threshold']);
    const nextRank = optional(value['nextRank'], candidate => {
      const next = fields(candidate, [
        'id', 'label', 'threshold', 'trimsRemaining', 'promotionRequired',
      ]);
      if (typeof next['promotionRequired'] !== 'boolean') invalid();
      return Object.freeze({
        id: member(next['id'], CAREER_RANKS),
        label: text(next['label'], 1, 40),
        threshold: integer(next['threshold']),
        trimsRemaining: integer(next['trimsRemaining']),
        promotionRequired: next['promotionRequired'],
      });
    });
    const streak = fields(value['streak'], ['days', 'status', 'lastActiveDate']);
    if (typeof value['careerStarted'] !== 'boolean') invalid();
    const firstConfirmedBuy = optional(value['firstConfirmedBuy'], candidate => {
      const first = fields(candidate, [
        'orderId', 'assetId', 'variantMint', 'symbol', 'quantityMicros', 'confirmedAt',
      ]);
      return Object.freeze({
        orderId: uuid(first['orderId']),
        assetId: assetId(first['assetId']),
        variantMint: solanaAddress(first['variantMint']),
        symbol: text(first['symbol'], 1, 30),
        quantityMicros: positiveIntegerText(first['quantityMicros']),
        confirmedAt: timestamp(first['confirmedAt']),
      });
    });
    const updatedAt = optional(value['updatedAt'], timestamp);
    const parsed: CareerSummary = Object.freeze({
      revision: integer(value['revision']),
      trims: Object.freeze({
        total: integer(trims['total']),
        today: integer(trims['today']),
        thisWeek: integer(trims['thisWeek']),
      }),
      rank: Object.freeze({
        id: member(rank['id'], CAREER_RANKS),
        label: text(rank['label'], 1, 40),
        paperLimit: decimal(rank['paperLimit']),
        threshold: integer(rank['threshold']),
      }),
      nextRank,
      streak: Object.freeze({
        days: integer(streak['days']),
        status: member(streak['status'], CAREER_STREAK_STATUSES),
        lastActiveDate: optional(streak['lastActiveDate'], date),
      }),
      careerStarted: value['careerStarted'],
      firstConfirmedBuy,
      serverDate: date(value['serverDate']),
      updatedAt,
    });
    const rankRule = rankRules[parsed.rank.id];
    const expectedNextId = rankRule.next;
    const expectedNextRule = expectedNextId === null ? null : rankRules[expectedNextId];
    if (parsed.rank.label !== rankRule.label || parsed.rank.paperLimit !== rankRule.paperLimit ||
        parsed.rank.threshold !== rankRule.threshold ||
        (expectedNextRule === null) !== (nextRank === null) ||
        (nextRank !== null && expectedNextRule !== null &&
          (nextRank.id !== expectedNextId || nextRank.label !== expectedNextRule.label ||
            nextRank.threshold !== expectedNextRule.threshold ||
            nextRank.trimsRemaining !== Math.max(0, expectedNextRule.threshold - parsed.trims.total) ||
            nextRank.promotionRequired !== (parsed.trims.total >= expectedNextRule.threshold))) ||
        parsed.trims.today > parsed.trims.total || parsed.trims.thisWeek > parsed.trims.total ||
        parsed.rank.threshold > parsed.trims.total ||
        (parsed.revision === 0) !== (parsed.updatedAt === null) ||
        (parsed.revision === 0) !== !parsed.careerStarted ||
        (parsed.firstConfirmedBuy !== null && !parsed.careerStarted) ||
        (parsed.firstConfirmedBuy !== null && parsed.updatedAt !== null &&
          parsed.firstConfirmedBuy.confirmedAt > parsed.updatedAt) ||
        (parsed.streak.days === 0) !== (parsed.streak.lastActiveDate === null) ||
        (parsed.streak.days === 0) !== (parsed.streak.status === 'not-started')) invalid();
    return parsed;
  } catch (error) {
    if (error instanceof CareerRepositoryError && error.code === 'CAREER_STORAGE_INVALID') throw error;
    throw new CareerRepositoryError('CAREER_STORAGE_INVALID', 'Stored career summary could not be read safely.');
  }
}

export function parseCareerMissionBoard(input: unknown): CareerMissionBoard {
  try {
    const value = fields(input, ['revision', 'currentRank', 'missions']);
    const revision = integer(value['revision']);
    const currentRank = member(value['currentRank'], CAREER_RANKS);
    if (!Array.isArray(value['missions']) || value['missions'].length !== CAREER_MISSION_IDS.length) invalid();
    const missions = value['missions'].map((candidate, index): CareerMission => {
      const mission = fields(candidate, [
        'id', 'chapterRank', 'order', 'kind', 'title', 'instruction', 'trimsReward',
        'promotesToRank', 'status', 'completedAt',
      ]);
      const id = member(mission['id'], CAREER_MISSION_IDS);
      const rule = missionRules[id];
      const parsed: CareerMission = Object.freeze({
        id,
        chapterRank: member(mission['chapterRank'], CAREER_RANKS),
        order: integer(mission['order'], 1),
        kind: member(mission['kind'], CAREER_MISSION_KINDS),
        title: text(mission['title'], 1, 60),
        instruction: text(mission['instruction'], 1, 120),
        trimsReward: integer(mission['trimsReward']) as 20,
        promotesToRank: optional(mission['promotesToRank'], rank => member(rank, CAREER_RANKS)),
        status: member(mission['status'], CAREER_MISSION_STATUSES),
        completedAt: optional(mission['completedAt'], timestamp),
      });
      if (id !== CAREER_MISSION_IDS[index] || parsed.chapterRank !== rule.chapterRank ||
          parsed.order !== rule.order || parsed.kind !== rule.kind || parsed.title !== rule.title ||
          parsed.instruction !== rule.instruction || parsed.trimsReward !== 20 ||
          parsed.promotesToRank !== rule.promotesToRank ||
          (parsed.status === 'complete') !== (parsed.completedAt !== null)) invalid();
      return parsed;
    });
    if ((revision === 0 && currentRank !== 'rookie') ||
        missions.some((mission, index) => mission.status === 'complete' &&
          missions.slice(0, index).some(previous => previous.status !== 'complete')) ||
        missions.filter(mission => mission.status === 'ready').length > 1) invalid();
    return Object.freeze({revision, currentRank, missions: Object.freeze(missions)});
  } catch {
    throw new CareerRepositoryError('CAREER_STORAGE_INVALID', 'Stored Career missions could not be read safely.');
  }
}

export function parseCareerTradeReasonReceipt(input: unknown): CareerTradeReasonReceipt {
  try {
    const value = fields(input, [
      'orderId', 'assetId', 'variantMint', 'note', 'trimsAwarded', 'dailyAwardNumber', 'savedAt',
    ]);
    const trimsAwarded = integer(value['trimsAwarded']);
    const dailyAwardNumber = optional(value['dailyAwardNumber'], candidate => integer(candidate, 1));
    if ((trimsAwarded === 0) !== (dailyAwardNumber === null) || trimsAwarded !== 0 && trimsAwarded !== 10 ||
        dailyAwardNumber !== null && dailyAwardNumber > 3) invalid();
    return Object.freeze({
      orderId: uuid(value['orderId']),
      assetId: assetId(value['assetId']),
      variantMint: solanaAddress(value['variantMint']),
      note: text(value['note'], 1, 180),
      trimsAwarded,
      dailyAwardNumber,
      savedAt: timestamp(value['savedAt']),
    });
  } catch {
    throw new CareerRepositoryError('CAREER_STORAGE_INVALID', 'Stored trade reason could not be read safely.');
  }
}

export function parseCareerPromotionReceipt(input: unknown): CareerPromotionReceipt {
  try {
    const value = fields(input, [
      'mutationId', 'fromRank', 'toRank', 'careerRevision', 'trimsAwarded', 'promotedAt',
    ]);
    const fromRank = member(value['fromRank'], CAREER_RANKS);
    const toRank = member(value['toRank'], CAREER_RANKS);
    const trimsAwarded = integer(value['trimsAwarded']);
    if (CAREER_RANKS.indexOf(toRank) !== CAREER_RANKS.indexOf(fromRank) + 1 || trimsAwarded !== 100) invalid();
    return Object.freeze({
      mutationId: uuid(value['mutationId']),
      fromRank,
      toRank,
      careerRevision: integer(value['careerRevision'], 1),
      trimsAwarded: trimsAwarded as 100,
      promotedAt: timestamp(value['promotedAt']),
    });
  } catch {
    throw new CareerRepositoryError('CAREER_STORAGE_INVALID', 'Stored Career promotion could not be read safely.');
  }
}
