import { DomainError, validateXRecipient } from '@trimmy/domain';
import {CAREER_RANKS} from './career-repository.js';
import type { InvitationState, UnfundedInvitation, XRecipient } from '@trimmy/domain';
import type {CareerRank} from './career-repository.js';

/**
 * The storage port for unfunded invitations, plus the parsing that keeps
 * untrusted request data and stored rows from reaching the domain unchecked.
 *
 * An invitation carries social intent only. Nothing here funds, mints, holds or
 * delivers an asset, and accepting one never creates a financial obligation.
 */
export type InvitationAction = 'address' | 'offer' | 'accept' | 'decline' | 'cancel';

/** Which side of the invitation the requesting account is on. */
export type InvitationRole = 'sender' | 'recipient';

export interface InvitationRecord {
  readonly id: string;
  readonly state: InvitationState;
  readonly funding: 'unfunded';
  readonly recipient: XRecipient | null;
  readonly expiresAt: string;
  readonly createdAt: string;
  readonly acceptedAt: string | null;
  readonly version: number;
  readonly role: InvitationRole;
}

export interface InvitationCreate {
  readonly id: string;
  readonly expiresAt: string;
}

export interface InvitationCommand {
  readonly action: InvitationAction;
  readonly expectedVersion: number;
  /** Required for `address`, rejected for every other action. */
  readonly recipient: XRecipient | null;
}

export interface InvitationsRepository {
  list(userId: string): Promise<readonly InvitationRecord[]>;
  create(userId: string, input: InvitationCreate): Promise<InvitationRecord>;
  apply(userId: string, invitationId: string, command: InvitationCommand): Promise<InvitationRecord>;
}

export type InvitationBox = 'open' | 'history';
export type InvitationV2SenderAction = 'address' | 'offer' | 'cancel';
export type InvitationV2AnswerAction = 'accept' | 'decline';
export type IncomingInvitations = 'available' | 'x_link_required';

export interface InvitationPublicSender {
  readonly socialId: string;
  readonly handle: string;
  readonly persona: string;
  readonly rank: Readonly<{readonly id: CareerRank; readonly label: string}>;
}

export interface InvitationV2Record {
  readonly id: string;
  readonly state: InvitationState;
  readonly funding: 'unfunded';
  readonly sender: InvitationPublicSender;
  readonly recipient: Readonly<{readonly provider: 'x'; readonly handleSnapshot: string}> | null;
  readonly expiresAt: string;
  readonly createdAt: string;
  readonly acceptedAt: string | null;
  readonly version: number;
  readonly role: InvitationRole;
}

export interface InvitationV2Cursor {
  readonly principalSocialId: string;
  readonly createdAt: string;
  readonly invitationId: string;
}

export interface InvitationV2ListInput {
  readonly box: InvitationBox;
  readonly limit: number;
  readonly cursor: InvitationV2Cursor | null;
  /** A fresh or bounded-cache Privy projection for this request only. */
  readonly freshXSubject: string | null;
}

export interface InvitationV2ListPage {
  readonly principalSocialId: string;
  readonly invitations: readonly InvitationV2Record[];
  readonly hasMore: boolean;
  readonly incomingInvitations: IncomingInvitations;
}

export interface InvitationV2Create {
  readonly mutationId: string;
  readonly expiresAt: string;
}

export interface InvitationV2CreateResult {
  readonly invitation: InvitationV2Record;
  /** True only when this request created the receipt and draft. */
  readonly created: boolean;
}

export interface ResolvedXRecipient {
  readonly subject: string;
  readonly handleSnapshot: string;
}

export interface FreshVerifiedXIdentity extends ResolvedXRecipient {
  readonly verifiedAt: string;
}

export interface InvitationV2SenderCommand {
  readonly action: InvitationV2SenderAction;
  readonly expectedVersion: number;
  readonly recipient: ResolvedXRecipient | null;
}

export interface InvitationV2AnswerCommand {
  readonly action: InvitationV2AnswerAction;
  readonly expectedVersion: number;
  readonly identity: FreshVerifiedXIdentity;
}

/**
 * Version 2 is the production invitation authority. Identity proof and the
 * answer enter one database function call; there is no standalone bind step.
 */
export interface InvitationsV2Repository {
  listV2(userId: string, input: InvitationV2ListInput): Promise<InvitationV2ListPage>;
  createV2(userId: string, input: InvitationV2Create): Promise<InvitationV2CreateResult>;
  senderActionV2(
    userId: string,
    invitationId: string,
    command: InvitationV2SenderCommand,
  ): Promise<InvitationV2Record>;
  answerV2(
    userId: string,
    invitationId: string,
    command: InvitationV2AnswerCommand,
  ): Promise<InvitationV2Record>;
}

export type InvitationErrorCode =
  | 'INVITATION_INVALID_INPUT' | 'INVITATION_NOT_FOUND' | 'INVITATION_FORBIDDEN'
  | 'INVITATION_VERSION_CONFLICT' | 'INVITATION_INVALID_TRANSITION' | 'INVITATION_EXPIRED'
  | 'INVITATION_ACCOUNT_NOT_FOUND' | 'INVITATION_LIMIT_REACHED' | 'INVITATION_STORAGE_INVALID'
  | 'INVITATION_RUNTIME_ROLE_INVALID' | 'INVITATION_UNAVAILABLE'
  | 'SOCIAL_INVITATION_IDEMPOTENCY_CONFLICT' | 'SOCIAL_IDENTITY_UNAVAILABLE'
  | 'SOCIAL_IDENTITY_CONFLICT' | 'SOCIAL_PAIR_UNAVAILABLE' | 'SOCIAL_FRIEND_LIMIT_REACHED'
  | 'SOCIAL_RATE_LIMITED' | 'SOCIAL_PROFILE_MISSING';

export class InvitationRepositoryError extends Error {
  constructor(
    readonly code: InvitationErrorCode,
    message: string,
    readonly retryAfterSeconds?: number,
  ) {
    super(message);
    this.name = 'InvitationRepositoryError';
  }
}

function invalid(): never {
  throw new InvitationRepositoryError('INVITATION_INVALID_INPUT', 'Invitation request is invalid.');
}

/** At most this many invitations a sender can have that are not yet terminal. */
export const MAX_OPEN_INVITATIONS = 50;
export const MAX_INVITATION_WINDOW_MS = 30 * 24 * 60 * 60 * 1000;
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const millisecondInstant = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
const xSubject = /^[1-9][0-9]{0,19}$/;
const productHandle = /^[a-z][a-z0-9_]{2,17}$/;
const xHandle = /^[a-z0-9_]{1,15}$/;
const persona = /^[a-z][a-z0-9-]{0,30}$/;
const rankLabels: Readonly<Record<CareerRank, string>> = Object.freeze({
  rookie: 'Rookie', analyst: 'Analyst', trader: 'Trader',
  'senior-trader': 'Senior Trader', partner: 'Partner', legend: 'Legend',
});

/** Read data descriptors only: never invoke an input getter or its toJSON hook. */
export function invitationFields(input: unknown, allowed: readonly string[]): Record<string, unknown> {
  if (input === null || typeof input !== 'object' || Array.isArray(input)) invalid();
  const prototype: unknown = Object.getPrototypeOf(input);
  if (prototype !== Object.prototype && prototype !== null) invalid();
  const keys = Reflect.ownKeys(input);
  if (keys.length !== allowed.length) invalid();
  const copied: Record<string, unknown> = {};
  for (const key of keys) {
    if (typeof key !== 'string' || !allowed.includes(key)) invalid();
    const descriptor = Object.getOwnPropertyDescriptor(input, key);
    if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) invalid();
    copied[key] = descriptor.value;
  }
  return copied;
}

export function parseInvitationUserId(value: unknown): string {
  if (typeof value !== 'string' || uuid.exec(value)?.[0] !== value) invalid();
  return value;
}

export function parseInvitationId(value: unknown): string {
  if (typeof value !== 'string' || uuid.exec(value)?.[0] !== value) invalid();
  return value;
}

export const parseInvitationMutationId = parseInvitationId;

export function parseInvitationBox(value: unknown): InvitationBox {
  if (value !== 'open' && value !== 'history') invalid();
  return value;
}

export function parseInvitationLimit(value: unknown): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 1 || value > 50) invalid();
  return value;
}

export function parseInvitationXHandle(value: unknown): string {
  if (typeof value !== 'string' || /^[A-Za-z0-9_]{1,15}$/.exec(value)?.[0] !== value) invalid();
  return value;
}

export function parseXSubject(value: unknown): string {
  try {
    if (typeof value !== 'string' || xSubject.exec(value)?.[0] !== value ||
        BigInt(value) > 18_446_744_073_709_551_615n) invalid();
  } catch { invalid(); }
  return value;
}

/** Canonical millisecond UTC text; no other precision or offset is accepted. */
export function parseInvitationInstant(value: unknown): string {
  if (typeof value !== 'string' || millisecondInstant.exec(value)?.[0] !== value) invalid();
  const parsed = Date.parse(value);
  if (!Number.isFinite(parsed) || new Date(parsed).toISOString() !== value) invalid();
  return value;
}

export function parseInvitationRecipient(value: unknown): XRecipient {
  const fields = invitationFields(value, ['provider', 'subject', 'handleSnapshot']);
  if (fields['provider'] !== 'x' || typeof fields['subject'] !== 'string' ||
      typeof fields['handleSnapshot'] !== 'string') invalid();
  // The domain owns the authoritative subject and handle rules.
  const recipient: XRecipient = Object.freeze({
    provider: 'x', subject: fields['subject'], handleSnapshot: fields['handleSnapshot'],
  });
  try { validateXRecipient(recipient); } catch { invalid(); }
  return recipient;
}

export function parseInvitationVersion(value: unknown): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0 || value >= Number.MAX_SAFE_INTEGER) invalid();
  return value;
}

export function parseInvitationAction(value: unknown): InvitationAction {
  if (value !== 'address' && value !== 'offer' && value !== 'accept' &&
      value !== 'decline' && value !== 'cancel') invalid();
  return value;
}

export function parseInvitationV2SenderAction(value: unknown): InvitationV2SenderAction {
  if (value !== 'address' && value !== 'offer' && value !== 'cancel') invalid();
  return value;
}

export function parseInvitationV2AnswerAction(value: unknown): InvitationV2AnswerAction {
  if (value !== 'accept' && value !== 'decline') invalid();
  return value;
}

function parsePublicSender(value: unknown): InvitationPublicSender {
  const sender = invitationFields(value, ['socialId', 'handle', 'persona', 'rank']);
  const rank = invitationFields(sender['rank'], ['id', 'label']);
  const rankId = rank['id'];
  if (typeof sender['handle'] !== 'string' || productHandle.exec(sender['handle'])?.[0] !== sender['handle'] ||
      typeof sender['persona'] !== 'string' || persona.exec(sender['persona'])?.[0] !== sender['persona'] ||
      typeof rankId !== 'string' || !CAREER_RANKS.includes(rankId as CareerRank) ||
      rank['label'] !== rankLabels[rankId as CareerRank]) invalid();
  return Object.freeze({
    socialId: parseInvitationId(sender['socialId']),
    handle: sender['handle'],
    persona: sender['persona'],
    rank: Object.freeze({id: rankId as CareerRank, label: rank['label'] as string}),
  });
}

function parsePublicRecipient(value: unknown): InvitationV2Record['recipient'] {
  if (value === null) return null;
  const recipient = invitationFields(value, ['provider', 'handleSnapshot']);
  if (recipient['provider'] !== 'x' || typeof recipient['handleSnapshot'] !== 'string' ||
      xHandle.exec(recipient['handleSnapshot'])?.[0] !== recipient['handleSnapshot']) invalid();
  return Object.freeze({provider: 'x', handleSnapshot: recipient['handleSnapshot']});
}

export function parseInvitationV2Record(input: unknown): InvitationV2Record {
  try {
    const fields = invitationFields(input, [
      'id', 'state', 'funding', 'sender', 'recipient', 'expiresAt', 'createdAt',
      'acceptedAt', 'version', 'role',
    ]);
    const state = fields['state'];
    const role = fields['role'];
    if (fields['funding'] !== 'unfunded' ||
        !['draft', 'addressed', 'offered', 'accepted', 'declined', 'expired', 'canceled'].includes(state as string) ||
        (role !== 'sender' && role !== 'recipient')) invalid();
    const acceptedAt = fields['acceptedAt'];
    const recipient = parsePublicRecipient(fields['recipient']);
    if ((state === 'accepted') !== (acceptedAt !== null) || state === 'draft' && recipient !== null ||
        ['addressed', 'offered', 'accepted', 'declined'].includes(state as string) && recipient === null) invalid();
    return Object.freeze({
      id: parseInvitationId(fields['id']),
      state: state as InvitationState,
      funding: 'unfunded',
      sender: parsePublicSender(fields['sender']),
      recipient,
      expiresAt: parseInvitationInstant(fields['expiresAt']),
      createdAt: parseInvitationInstant(fields['createdAt']),
      acceptedAt: acceptedAt === null ? null : parseInvitationInstant(acceptedAt),
      version: parseInvitationVersion(fields['version']),
      role,
    });
  } catch (error) {
    if (error instanceof InvitationRepositoryError && error.code === 'INVITATION_STORAGE_INVALID') throw error;
    throw new InvitationRepositoryError('INVITATION_STORAGE_INVALID', 'Stored invitation data is unavailable.');
  }
}

export function parseInvitationV2Cursor(input: unknown): InvitationV2Cursor {
  try {
    const fields = invitationFields(input, ['principalSocialId', 'createdAt', 'invitationId']);
    return Object.freeze({
      principalSocialId: parseInvitationId(fields['principalSocialId']),
      createdAt: parseInvitationInstant(fields['createdAt']),
      invitationId: parseInvitationId(fields['invitationId']),
    });
  } catch { return invalid(); }
}

export function invitationV2Body(record: InvitationV2Record): Record<string, unknown> {
  const parsed = parseInvitationV2Record(record);
  return {
    schemaVersion: 2,
    id: parsed.id,
    state: parsed.state,
    funding: parsed.funding,
    sender: {
      socialId: parsed.sender.socialId,
      handle: parsed.sender.handle,
      persona: parsed.sender.persona,
      rank: {...parsed.sender.rank},
    },
    recipient: parsed.recipient === null ? null : {...parsed.recipient},
    expiresAt: parsed.expiresAt,
    createdAt: parsed.createdAt,
    acceptedAt: parsed.acceptedAt,
    version: parsed.version,
    role: parsed.role,
  };
}

/**
 * Validates a record on its way out of storage. Any failure here is a storage
 * fault rather than bad client input, so it never reports as a 400.
 */
export function parseInvitationRecord(input: unknown): InvitationRecord {
  try { return readRecord(input); }
  catch {
    throw new InvitationRepositoryError('INVITATION_STORAGE_INVALID', 'The stored invitation could not be read safely.');
  }
}

function readRecord(input: unknown): InvitationRecord {
  const fields = invitationFields(input,
    ['id', 'state', 'funding', 'recipient', 'expiresAt', 'createdAt', 'acceptedAt', 'version', 'role']);
  const state = fields['state'];
  const role = fields['role'];
  if (fields['funding'] !== 'unfunded' ||
      !['draft', 'addressed', 'offered', 'accepted', 'declined', 'expired', 'canceled'].includes(state as string) ||
      (role !== 'sender' && role !== 'recipient')) invalid();
  const acceptedAt = fields['acceptedAt'];
  const recipient = fields['recipient'];
  // Acceptance time exists exactly when the invitation was accepted.
  if ((state === 'accepted') !== (acceptedAt !== null)) invalid();
  // A draft is never addressed; an addressed or answered invitation always is.
  // Cancelled and expired may be either, because a draft can end that way.
  if (state === 'draft' && recipient !== null) invalid();
  if (['addressed', 'offered', 'accepted', 'declined'].includes(state as string) && recipient === null) invalid();
  return Object.freeze({
    id: parseInvitationId(fields['id']),
    state: state as InvitationState,
    funding: 'unfunded',
    recipient: recipient === null ? null : parseInvitationRecipient(recipient),
    expiresAt: parseInvitationInstant(fields['expiresAt']),
    createdAt: parseInvitationInstant(fields['createdAt']),
    acceptedAt: acceptedAt === null ? null : parseInvitationInstant(acceptedAt),
    version: parseInvitationVersion(fields['version']),
    role,
  });
}

/** Translate a domain rule failure into the repository's fixed error codes. */
export function invitationErrorFromDomain(error: unknown): InvitationRepositoryError {
  if (!(error instanceof DomainError)) {
    return new InvitationRepositoryError('INVITATION_UNAVAILABLE', 'The invitation could not be updated.');
  }
  switch (error.code) {
    case 'FORBIDDEN':
    case 'RECIPIENT_MISMATCH':
    case 'RECIPIENT_REQUIRED':
      return new InvitationRepositoryError('INVITATION_FORBIDDEN', 'This account cannot perform that invitation action.');
    case 'VERSION_CONFLICT':
      return new InvitationRepositoryError('INVITATION_VERSION_CONFLICT', 'The invitation changed. Reload it before continuing.');
    case 'INVITATION_EXPIRED':
      return new InvitationRepositoryError('INVITATION_EXPIRED', 'The invitation has expired.');
    case 'INVALID_TRANSITION':
    case 'TERMINAL_INVITATION':
    case 'NOT_EXPIRED':
    case 'INVALID_ACTION':
      return new InvitationRepositoryError('INVITATION_INVALID_TRANSITION', 'That invitation action is not available now.');
    case 'INVALID_X_SUBJECT':
    case 'INVALID_X_HANDLE':
    case 'INVALID_INVITATION_WINDOW':
      return new InvitationRepositoryError('INVITATION_INVALID_INPUT', 'Invitation request is invalid.');
    default:
      return new InvitationRepositoryError('INVITATION_STORAGE_INVALID', 'The stored invitation could not be read safely.');
  }
}

/** The wire body for one invitation. The sender's account id is never exposed. */
export function invitationBody(record: InvitationRecord): Record<string, unknown> {
  const parsed = parseInvitationRecord(record);
  return {
    schemaVersion: 1, id: parsed.id, state: parsed.state, funding: parsed.funding,
    recipient: parsed.recipient === null ? null : {...parsed.recipient},
    expiresAt: parsed.expiresAt, createdAt: parsed.createdAt, acceptedAt: parsed.acceptedAt,
    version: parsed.version, role: parsed.role,
  };
}

export type { UnfundedInvitation, XRecipient };
