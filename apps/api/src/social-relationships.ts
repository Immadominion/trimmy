import {CAREER_RANKS} from './career-repository.js';
import type {CareerRank} from './career-repository.js';

export type SocialPersona = 'wolf' | 'oracle' | 'shark';
export type SocialReportCategory = 'spam' | 'harassment' | 'impersonation' | 'unsafe' | 'other';

export interface SocialFriend {
  readonly friendshipId: string;
  readonly revision: number;
  readonly connectedAt: string;
  readonly person: Readonly<{
    readonly socialId: string;
    readonly handle: string;
    readonly persona: SocialPersona;
    readonly rank: Readonly<{readonly id: CareerRank; readonly label: string}>;
  }>;
}

export interface SocialFriendCursor {
  readonly principalSocialId: string;
  readonly connectedAt: string;
  readonly friendshipId: string;
}

export interface SocialFriendPage {
  readonly principalSocialId: string;
  readonly friends: readonly SocialFriend[];
  readonly hasMore: boolean;
}

export interface SocialBlock {
  readonly socialId: string;
  readonly handle: string | null;
  readonly revision: number;
  readonly blocked: boolean;
  readonly updatedAt: string;
}

export interface SocialBlockCursor {
  readonly principalSocialId: string;
  readonly updatedAt: string;
  readonly socialId: string;
}

export interface SocialBlockPage {
  readonly principalSocialId: string;
  readonly blocks: readonly SocialBlock[];
  readonly hasMore: boolean;
}

export interface SocialBlockSnapshot {
  readonly socialId: string;
  readonly revision: number;
  readonly blocked: boolean;
  readonly updatedAt: string | null;
}

export interface SocialFriendRemoveCommand {
  readonly mutationId: string;
  readonly expectedRevision: number;
}

export interface SocialFriendRemoval {
  readonly mutationId: string;
  readonly friendshipId: string;
  readonly appliedRevision: number;
  readonly state: 'removed';
  readonly occurredAt: string;
}

export interface SocialBlockPutCommand {
  readonly mutationId: string;
  readonly baseRevision: number;
  readonly blocked: boolean;
}

export interface SocialBlockMutation {
  readonly mutationId: string;
  readonly appliedRevision: number;
  readonly block: SocialBlock;
}

export interface SocialReasonReportCommand {
  readonly mutationId: string;
  readonly reasonId: string;
  readonly category: SocialReportCategory;
}

export interface SocialReasonReport {
  readonly reportId: string;
  readonly reasonId: string;
  readonly category: SocialReportCategory;
  readonly receivedAt: string;
}

export interface SocialReasonReportResult {
  readonly report: SocialReasonReport;
  readonly created: boolean;
}

export interface SocialRelationshipsRepository {
  listFriends(userId: string, input: Readonly<{
    limit: number;
    cursor: SocialFriendCursor | null;
  }>): Promise<SocialFriendPage>;
  removeFriend(userId: string, friendshipId: string,
    command: SocialFriendRemoveCommand): Promise<SocialFriendRemoval>;
  listBlocks(userId: string, input: Readonly<{
    limit: number;
    cursor: SocialBlockCursor | null;
  }>): Promise<SocialBlockPage>;
  getBlock(userId: string, socialId: string): Promise<SocialBlockSnapshot>;
  putBlock(userId: string, socialId: string,
    command: SocialBlockPutCommand): Promise<SocialBlockMutation>;
  reportReason(userId: string,
    command: SocialReasonReportCommand): Promise<SocialReasonReportResult>;
}

export type SocialRelationshipErrorCode =
  | 'SOCIAL_INVALID_INPUT'
  | 'SOCIAL_ACCOUNT_NOT_FOUND'
  | 'SOCIAL_RELATIONSHIP_NOT_FOUND'
  | 'SOCIAL_RELATIONSHIP_FORBIDDEN'
  | 'SOCIAL_RELATIONSHIP_REVISION_CONFLICT'
  | 'SOCIAL_RELATIONSHIP_IDEMPOTENCY_CONFLICT'
  | 'SOCIAL_RELATIONSHIP_NOT_ACTIVE'
  | 'SOCIAL_BLOCK_REVISION_CONFLICT'
  | 'SOCIAL_BLOCK_IDEMPOTENCY_CONFLICT'
  | 'SOCIAL_PAIR_UNAVAILABLE'
  | 'SOCIAL_REPORT_IDEMPOTENCY_CONFLICT'
  | 'SOCIAL_RATE_LIMITED'
  | 'SOCIAL_STORAGE_INVALID'
  | 'SOCIAL_RUNTIME_ROLE_INVALID'
  | 'SOCIAL_UNAVAILABLE';

export class SocialRelationshipError extends Error {
  constructor(
    readonly code: SocialRelationshipErrorCode,
    message: string,
    readonly retryAfterSeconds?: number,
  ) {
    super(message);
    this.name = 'SocialRelationshipError';
  }
}

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u;
const instant = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/u;
const handle = /^[a-z][a-z0-9_]{2,17}$/u;
const rankLabels: Readonly<Record<CareerRank, string>> = Object.freeze({
  rookie: 'Rookie', analyst: 'Analyst', trader: 'Trader',
  'senior-trader': 'Senior Trader', partner: 'Partner', legend: 'Legend',
});

export function socialInvalid(): never {
  throw new SocialRelationshipError('SOCIAL_INVALID_INPUT', 'Social request is invalid.');
}

/** Copies only own enumerable data descriptors and rejects every extra key. */
export function socialFields(input: unknown, allowed: readonly string[]): Record<string, unknown> {
  if (input === null || typeof input !== 'object' || Array.isArray(input)) socialInvalid();
  const prototype: unknown = Object.getPrototypeOf(input);
  if (prototype !== Object.prototype && prototype !== null) socialInvalid();
  const keys = Reflect.ownKeys(input);
  if (keys.length !== allowed.length) socialInvalid();
  const copied: Record<string, unknown> = Object.create(null) as Record<string, unknown>;
  for (const key of keys) {
    if (typeof key !== 'string' || !allowed.includes(key)) socialInvalid();
    const descriptor = Object.getOwnPropertyDescriptor(input, key);
    if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) socialInvalid();
    copied[key] = descriptor.value;
  }
  return copied;
}

export function parseSocialUuid(value: unknown): string {
  if (typeof value !== 'string' || uuid.exec(value)?.[0] !== value) socialInvalid();
  return value;
}

export function parseSocialInstant(value: unknown): string {
  if (typeof value !== 'string' || instant.exec(value)?.[0] !== value) socialInvalid();
  const milliseconds = Date.parse(value);
  if (!Number.isFinite(milliseconds) || new Date(milliseconds).toISOString() !== value) socialInvalid();
  return value;
}

export function parseSocialRevision(value: unknown, allowZero = false): number {
  const minimum = allowZero ? 0 : 1;
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < minimum ||
      value > Number.MAX_SAFE_INTEGER) socialInvalid();
  return value;
}

export function parseSocialLimit(value: unknown): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 1 || value > 50) socialInvalid();
  return value;
}

export function parseSocialHandle(value: unknown): string {
  if (typeof value !== 'string' || handle.exec(value)?.[0] !== value) socialInvalid();
  return value;
}

export function parseSocialPersona(value: unknown): SocialPersona {
  if (value !== 'wolf' && value !== 'oracle' && value !== 'shark') socialInvalid();
  return value;
}

export function parseSocialRank(value: unknown): CareerRank {
  if (typeof value !== 'string' || !CAREER_RANKS.includes(value as CareerRank)) socialInvalid();
  return value as CareerRank;
}

export function socialRankLabel(rank: CareerRank): string { return rankLabels[rank]; }

export function parseSocialReportCategory(value: unknown): SocialReportCategory {
  if (value !== 'spam' && value !== 'harassment' && value !== 'impersonation' &&
      value !== 'unsafe' && value !== 'other') socialInvalid();
  return value;
}
