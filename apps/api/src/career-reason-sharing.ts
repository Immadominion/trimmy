import {Buffer} from 'node:buffer';
import {CAREER_RANKS} from './career-repository.js';
import type {CareerRank} from './career-repository.js';
import {PRODUCT_PERSONAS} from './product-profile-repository.js';
import type {ProductPersona} from './product-profile-repository.js';

export const CAREER_REASON_VISIBILITIES = Object.freeze([
  'friends',
  'everyone',
  'nobody',
] as const);

export const CAREER_REASON_LIST_SCOPES = Object.freeze(['self', 'everyone', 'friends'] as const);
export const CAREER_REASON_DESK_CYCLES = Object.freeze(['current', 'historical'] as const);

export type CareerReasonVisibility = typeof CAREER_REASON_VISIBILITIES[number];
export type CareerReasonListScope = typeof CAREER_REASON_LIST_SCOPES[number];
export type CareerReasonDeskCycle = typeof CAREER_REASON_DESK_CYCLES[number];

export interface CareerReasonPrivacy {
  readonly revision: number;
  readonly visibility: CareerReasonVisibility;
  readonly configured: boolean;
  readonly friendsSharing: 'unavailable' | 'available';
  readonly createdAt: string;
  readonly updatedAt: string;
}

export interface CareerReasonPrivacyWrite {
  readonly mutationId: string;
  readonly baseRevision: number;
  readonly visibility: CareerReasonVisibility;
}

export interface CareerReasonCursor {
  readonly savedAt: string;
  readonly reasonId: string;
  /** Present only on a friends cursor and always a public social UUID. */
  readonly principalSocialId?: string;
}

export interface CareerReasonListQuery {
  readonly scope: CareerReasonListScope;
  readonly limit: number;
  readonly assetId: string | null;
  readonly variantMint: string | null;
  readonly cursor: CareerReasonCursor | null;
}

interface CareerReasonListItemBase {
  /** Public reason identity. This is distinct from the paper order identity. */
  readonly reasonId: string;
  readonly stock: Readonly<{
    assetId: string;
    variantMint: string;
    symbol: string;
  }>;
  readonly note: string;
  readonly savedAt: string;
}

/** Internal self/everyone row. Shared HTTP output removes its private fields. */
export interface CareerReasonInternalListItem extends CareerReasonListItemBase {
  readonly orderId: string;
  readonly author: Readonly<{
    handle: string;
    rank: Readonly<{id: CareerRank; label: string}>;
    isViewer: boolean;
  }>;
  readonly deskCycle: CareerReasonDeskCycle;
}

/** Friends projection. It contains only stable public author identity. */
export interface CareerReasonFriendsListItem extends CareerReasonListItemBase {
  readonly orderId?: never;
  readonly deskCycle?: never;
  readonly author: Readonly<{
    socialId: string;
    handle: string;
    persona: ProductPersona;
    rank: Readonly<{id: CareerRank; label: string}>;
    isViewer: false;
  }>;
}

export type CareerReasonListItem = CareerReasonInternalListItem | CareerReasonFriendsListItem;

export interface CareerReasonListPage {
  readonly reasons: readonly CareerReasonListItem[];
  readonly hasMore: boolean;
  /** Present only for a successfully authorized friends page. */
  readonly principalSocialId?: string;
}

export interface CareerReasonSharingRepository {
  getPrivacy(userId: string): Promise<CareerReasonPrivacy>;
  savePrivacy(userId: string, command: CareerReasonPrivacyWrite): Promise<CareerReasonPrivacy>;
  listReasons(userId: string, query: CareerReasonListQuery): Promise<CareerReasonListPage>;
}

export type CareerReasonSharingErrorCode =
  | 'CAREER_REASON_SHARING_INVALID_INPUT'
  | 'CAREER_REASON_SHARING_ACCOUNT_NOT_FOUND'
  | 'CAREER_REASON_FRIENDS_ACCOUNT_REQUIRED'
  | 'CAREER_REASON_PRIVACY_REVISION_CONFLICT'
  | 'CAREER_REASON_SHARING_IDEMPOTENCY_CONFLICT'
  | 'CAREER_REASON_SHARING_REVISION_EXHAUSTED'
  | 'CAREER_REASON_SHARING_STORAGE_INVALID'
  | 'CAREER_REASON_SHARING_RUNTIME_ROLE_INVALID';

export class CareerReasonSharingError extends Error {
  constructor(readonly code: CareerReasonSharingErrorCode, message: string) {
    super(message);
    this.name = 'CareerReasonSharingError';
  }
}

const rankLabels: Readonly<Record<CareerRank, string>> = Object.freeze({
  rookie: 'Rookie',
  analyst: 'Analyst',
  trader: 'Trader',
  'senior-trader': 'Senior Trader',
  partner: 'Partner',
  legend: 'Legend',
});

const maximumSafeInteger = Number.MAX_SAFE_INTEGER;
const cursorVersion = 1;
const friendsCursorVersion = 2;
const friendsCursorKind = 'career-reasons';
const defaultLimit = 20;
const maximumLimit = 50;

function invalid(): never {
  throw new CareerReasonSharingError(
    'CAREER_REASON_SHARING_INVALID_INPUT',
    'Career reason sharing input is invalid.',
  );
}

function storageInvalid(): never {
  throw new CareerReasonSharingError(
    'CAREER_REASON_SHARING_STORAGE_INVALID',
    'Career reason sharing storage is invalid.',
  );
}

function object(
  input: unknown,
  required: readonly string[],
  optional: readonly string[] = [],
): Readonly<Record<string, unknown>> {
  if (input === null || typeof input !== 'object' || Array.isArray(input)) invalid();
  const prototype: unknown = Object.getPrototypeOf(input);
  if (prototype !== Object.prototype && prototype !== null) invalid();
  const keys = Reflect.ownKeys(input);
  if (keys.some(key => typeof key !== 'string' ||
      (!required.includes(key) && !optional.includes(key))) ||
      required.some(key => !keys.includes(key))) invalid();
  const result: Record<string, unknown> = Object.create(null) as Record<string, unknown>;
  for (const key of keys) {
    const descriptor = Object.getOwnPropertyDescriptor(input, key);
    if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) invalid();
    result[key as string] = descriptor.value;
  }
  return Object.freeze(result);
}

function exactObject(input: unknown, expected: readonly string[]): Readonly<Record<string, unknown>> {
  const value = object(input, expected);
  if (Reflect.ownKeys(value).length !== expected.length) invalid();
  return value;
}

function member<T extends string>(input: unknown, values: readonly T[]): T {
  if (typeof input !== 'string' || !values.includes(input as T)) invalid();
  return input as T;
}

function integer(input: unknown, minimum: number, maximum = maximumSafeInteger): number {
  if (typeof input !== 'number' || !Number.isSafeInteger(input) || input < minimum || input > maximum) invalid();
  return input;
}

function uuid(input: unknown): string {
  if (typeof input !== 'string' ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu.test(input)) {
    invalid();
  }
  return input.toLowerCase();
}

function timestamp(input: unknown): string {
  if (typeof input !== 'string' ||
      !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/u.test(input)) invalid();
  try {
    if (new Date(input).toISOString() !== input) invalid();
  } catch { invalid(); }
  return input;
}

function text(input: unknown, minimum: number, maximum: number): string {
  if (typeof input !== 'string' || input !== input.trim() ||
      [...input].length < minimum || [...input].length > maximum ||
      /[\u0000-\u001F\u007F-\u009F]/u.test(input)) invalid();
  return input;
}

function assetId(input: unknown): string {
  if (typeof input !== 'string' || input.length > 100 ||
      !/^[a-z0-9]+(?:-[a-z0-9]+)*$/u.test(input)) invalid();
  return input;
}

function solanaAddress(input: unknown): string {
  if (typeof input !== 'string' || !/^[1-9A-HJ-NP-Za-km-z]{32,44}$/u.test(input)) invalid();
  return input;
}

function handle(input: unknown): string {
  if (typeof input !== 'string' || !/^[a-z][a-z0-9_]{2,17}$/u.test(input)) invalid();
  return input;
}

function symbol(input: unknown): string { return text(input, 1, 30); }

export function parseCareerReasonUserId(input: unknown): string { return uuid(input); }
export function parseCareerReasonSocialId(input: unknown): string { return uuid(input); }

export function parseCareerReasonPrivacy(input: unknown): CareerReasonPrivacy {
  try {
    const value = exactObject(input, [
      'revision', 'visibility', 'configured', 'friendsSharing', 'createdAt', 'updatedAt',
    ]);
    if (typeof value['configured'] !== 'boolean' ||
        (value['friendsSharing'] !== 'unavailable' && value['friendsSharing'] !== 'available')) invalid();
    const result: CareerReasonPrivacy = Object.freeze({
      revision: integer(value['revision'], 1),
      visibility: member(value['visibility'], CAREER_REASON_VISIBILITIES),
      configured: value['configured'],
      friendsSharing: value['friendsSharing'],
      createdAt: timestamp(value['createdAt']),
      updatedAt: timestamp(value['updatedAt']),
    });
    if (result.updatedAt < result.createdAt || (!result.configured &&
        (result.revision !== 1 || result.visibility !== 'nobody' ||
          result.updatedAt !== result.createdAt)) || (result.configured &&
        (result.revision < 2 || result.updatedAt <= result.createdAt))) invalid();
    return result;
  } catch (error) {
    if (error instanceof CareerReasonSharingError &&
        error.code === 'CAREER_REASON_SHARING_STORAGE_INVALID') throw error;
    storageInvalid();
  }
}

export function parseCareerReasonPrivacyWrite(input: unknown): CareerReasonPrivacyWrite {
  const value = exactObject(input, ['mutationId', 'baseRevision', 'visibility']);
  return Object.freeze({
    mutationId: uuid(value['mutationId']),
    baseRevision: integer(value['baseRevision'], 1),
    visibility: member(value['visibility'], CAREER_REASON_VISIBILITIES),
  });
}

export function parseCareerReasonListQuery(input: unknown): CareerReasonListQuery {
  const value = exactObject(input, ['scope', 'limit', 'assetId', 'variantMint', 'cursor']);
  const scope = member(value['scope'], CAREER_REASON_LIST_SCOPES);
  const parsedAsset = value['assetId'] === null ? null : assetId(value['assetId']);
  const parsedMint = value['variantMint'] === null ? null : solanaAddress(value['variantMint']);
  if ((parsedAsset === null) !== (parsedMint === null) ||
      (scope !== 'self' && parsedAsset === null)) invalid();
  const parsedCursor = value['cursor'] === null ? null : (() => {
    const cursor = exactObject(value['cursor'], scope === 'friends'
      ? ['principalSocialId', 'savedAt', 'reasonId']
      : ['savedAt', 'reasonId']);
    return Object.freeze({
      ...(scope === 'friends'
        ? {principalSocialId: uuid(cursor['principalSocialId'])}
        : {}),
      savedAt: timestamp(cursor['savedAt']),
      reasonId: uuid(cursor['reasonId']),
    });
  })();
  return Object.freeze({
    scope,
    limit: integer(value['limit'], 1, maximumLimit),
    assetId: parsedAsset,
    variantMint: parsedMint,
    cursor: parsedCursor,
  });
}

export function parseCareerReasonListHttpQuery(input: unknown): CareerReasonListQuery {
  const value = object(input, ['scope'], ['limit', 'assetId', 'variantMint', 'cursor']);
  const parsedAsset = value['assetId'] === undefined ? null : assetId(value['assetId']);
  const parsedMint = value['variantMint'] === undefined ? null : solanaAddress(value['variantMint']);
  const scope = member(value['scope'], CAREER_REASON_LIST_SCOPES);
  if ((parsedAsset === null) !== (parsedMint === null) ||
      (scope !== 'self' && parsedAsset === null)) invalid();
  let limit = defaultLimit;
  if (value['limit'] !== undefined) {
    if (typeof value['limit'] !== 'string' || !/^(?:[1-9]|[1-4][0-9]|50)$/u.test(value['limit'])) invalid();
    limit = Number(value['limit']);
  }
  const cursor = value['cursor'] === undefined ? null
    : decodeCareerReasonCursor(value['cursor'], {scope, assetId: parsedAsset, variantMint: parsedMint});
  return parseCareerReasonListQuery({
    scope,
    limit,
    assetId: parsedAsset,
    variantMint: parsedMint,
    cursor,
  });
}

export function parseCareerReasonListItem(input: unknown): CareerReasonListItem {
  try {
    if (input === null || typeof input !== 'object' || Array.isArray(input)) invalid();
    const keys = Reflect.ownKeys(input);
    const internal = keys.includes('orderId') || keys.includes('deskCycle');
    const value = exactObject(input, internal
      ? ['reasonId', 'orderId', 'author', 'stock', 'note', 'deskCycle', 'savedAt']
      : ['reasonId', 'author', 'stock', 'note', 'savedAt']);
    const author = exactObject(value['author'], internal
      ? ['handle', 'rank', 'isViewer']
      : ['socialId', 'handle', 'persona', 'rank', 'isViewer']);
    const rank = exactObject(author['rank'], ['id', 'label']);
    const rankId = member(rank['id'], CAREER_RANKS);
    if (rank['label'] !== rankLabels[rankId] || typeof author['isViewer'] !== 'boolean') invalid();
    const stock = exactObject(value['stock'], ['assetId', 'variantMint', 'symbol']);
    const base = {
      reasonId: uuid(value['reasonId']),
      stock: Object.freeze({
        assetId: assetId(stock['assetId']),
        variantMint: solanaAddress(stock['variantMint']),
        symbol: symbol(stock['symbol']),
      }),
      note: text(value['note'], 1, 180),
      savedAt: timestamp(value['savedAt']),
    } as const;
    if (internal) {
      const deskCycle = member(value['deskCycle'], CAREER_REASON_DESK_CYCLES);
      if (author['isViewer'] === false && deskCycle !== 'current') invalid();
      return Object.freeze({
        ...base,
        orderId: uuid(value['orderId']),
        author: Object.freeze({
          handle: handle(author['handle']),
          rank: Object.freeze({id: rankId, label: rank['label'] as string}),
          isViewer: author['isViewer'],
        }),
        deskCycle,
      });
    }
    if (author['isViewer'] !== false) invalid();
    return Object.freeze({
      ...base,
      author: Object.freeze({
        socialId: uuid(author['socialId']),
        handle: handle(author['handle']),
        persona: member(author['persona'], PRODUCT_PERSONAS),
        rank: Object.freeze({id: rankId, label: rank['label'] as string}),
        isViewer: false as const,
      }),
    });
  } catch (error) {
    if (error instanceof CareerReasonSharingError &&
        error.code === 'CAREER_REASON_SHARING_STORAGE_INVALID') throw error;
    storageInvalid();
  }
}

export function parseCareerReasonListPage(input: unknown): CareerReasonListPage {
  try {
    const value = object(input, ['reasons', 'hasMore'], ['principalSocialId']);
    if (!Array.isArray(value['reasons']) ||
        value['reasons'].length > maximumLimit ||
        typeof value['hasMore'] !== 'boolean') invalid();
    const reasons = value['reasons'].map(parseCareerReasonListItem);
    if (value['hasMore'] && reasons.length === 0 ||
        new Set(reasons.map(reason => reason.reasonId)).size !== reasons.length ||
        (() => {
          const orders = reasons.filter(isCareerReasonInternalListItem).map(reason => reason.orderId);
          return new Set(orders).size !== orders.length;
        })() ||
        reasons.some((reason, index) => index > 0 && (() => {
          const previous = reasons[index - 1]!;
          return previous.savedAt < reason.savedAt ||
            (previous.savedAt === reason.savedAt && previous.reasonId <= reason.reasonId);
        })())) invalid();
    return Object.freeze({
      reasons: Object.freeze(reasons),
      hasMore: value['hasMore'],
      ...(Object.hasOwn(value, 'principalSocialId')
        ? {principalSocialId: uuid(value['principalSocialId'])}
        : {}),
    });
  } catch (error) {
    if (error instanceof CareerReasonSharingError &&
        error.code === 'CAREER_REASON_SHARING_STORAGE_INVALID') throw error;
    storageInvalid();
  }
}

export function isCareerReasonInternalListItem(
  item: CareerReasonListItem,
): item is CareerReasonInternalListItem {
  return Object.hasOwn(item, 'orderId') && Object.hasOwn(item, 'deskCycle');
}

export function isCareerReasonFriendsListItem(
  item: CareerReasonListItem,
): item is CareerReasonFriendsListItem {
  return !isCareerReasonInternalListItem(item) && Object.hasOwn(item.author, 'socialId');
}

function cursorPayload(
  query: Pick<CareerReasonListQuery, 'scope' | 'assetId' | 'variantMint'>,
  cursor: CareerReasonCursor,
): readonly unknown[] {
  if (query.scope === 'friends') {
    return Object.freeze([
      friendsCursorVersion,
      friendsCursorKind,
      cursor.principalSocialId,
      query.scope,
      query.assetId,
      query.variantMint,
      cursor.savedAt,
      cursor.reasonId,
    ]);
  }
  return Object.freeze([
    cursorVersion,
    query.scope,
    query.assetId,
    query.variantMint,
    cursor.savedAt,
    cursor.reasonId,
  ]);
}

export function encodeCareerReasonCursor(
  query: Pick<CareerReasonListQuery, 'scope' | 'assetId' | 'variantMint'>,
  item: Pick<CareerReasonListItem, 'savedAt' | 'reasonId'>,
  principalSocialId?: string,
): string {
  const normalized = parseCareerReasonListQuery({
    ...query,
    limit: 1,
    cursor: query.scope === 'friends'
      ? {principalSocialId, savedAt: item.savedAt, reasonId: item.reasonId}
      : {savedAt: item.savedAt, reasonId: item.reasonId},
  });
  return Buffer.from(JSON.stringify(cursorPayload(normalized, normalized.cursor!)), 'utf8').toString('base64url');
}

export function decodeCareerReasonCursor(
  input: unknown,
  expected: Pick<CareerReasonListQuery, 'scope' | 'assetId' | 'variantMint'>,
): CareerReasonCursor {
  if (typeof input !== 'string' || input.length < 1 || input.length > 512 ||
      !/^[A-Za-z0-9_-]+$/u.test(input)) invalid();
  let raw: Buffer;
  let decoded: unknown;
  try {
    raw = Buffer.from(input, 'base64url');
    if (raw.length > 384 || raw.toString('base64url') !== input) invalid();
    decoded = JSON.parse(raw.toString('utf8')) as unknown;
  } catch { invalid(); }
  if (!Array.isArray(decoded)) invalid();
  const friends = expected.scope === 'friends';
  if (friends
    ? decoded.length !== 8 || decoded[0] !== friendsCursorVersion || decoded[1] !== friendsCursorKind
    : decoded.length !== 6 || decoded[0] !== cursorVersion) invalid();
  const query = parseCareerReasonListQuery({
    scope: friends ? decoded[3] : decoded[1],
    limit: 1,
    assetId: friends ? decoded[4] : decoded[2],
    variantMint: friends ? decoded[5] : decoded[3],
    cursor: friends
      ? {principalSocialId: decoded[2], savedAt: decoded[6], reasonId: decoded[7]}
      : {savedAt: decoded[4], reasonId: decoded[5]},
  });
  const normalizedExpected = parseCareerReasonListQuery({...expected, limit: 1, cursor: null});
  if (query.scope !== normalizedExpected.scope || query.assetId !== normalizedExpected.assetId ||
      query.variantMint !== normalizedExpected.variantMint || query.cursor === null ||
      JSON.stringify(cursorPayload(query, query.cursor)) !== raw.toString('utf8')) invalid();
  return query.cursor;
}

export function careerReasonRankLabel(rankId: unknown): string {
  const id = member(rankId, CAREER_RANKS);
  return rankLabels[id];
}
