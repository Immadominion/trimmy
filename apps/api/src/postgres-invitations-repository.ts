import {createHash} from 'node:crypto';
import type { Pool, PoolClient, QueryResultRow } from 'pg';
import {
  addressUnfundedInvitation, createUnfundedInvitation, transitionUnfundedInvitation,
} from '@trimmy/domain';
import type { UnfundedInvitation, XRecipient } from '@trimmy/domain';
import {
  InvitationRepositoryError, MAX_INVITATION_WINDOW_MS, MAX_OPEN_INVITATIONS,
  invitationErrorFromDomain, parseInvitationBox, parseInvitationId, parseInvitationInstant,
  parseInvitationLimit, parseInvitationMutationId, parseInvitationRecord, parseInvitationUserId,
  parseInvitationV2Record, parseInvitationV2SenderAction, parseInvitationVersion, parseXSubject,
} from './invitations-repository.js';
import type {
  FreshVerifiedXIdentity, InvitationCommand, InvitationCreate, InvitationRecord,
  InvitationsRepository, InvitationsV2Repository, InvitationV2AnswerCommand,
  InvitationV2Create, InvitationV2CreateResult, InvitationV2ListInput, InvitationV2ListPage,
  InvitationV2Record, InvitationV2SenderCommand, ResolvedXRecipient,
} from './invitations-repository.js';
import {DEFAULT_RELATIONSHIP_MODERATION_ROLE, parseRelationshipModerationRole} from
  './relationship-safety-config.js';

interface InvitationRow extends QueryResultRow {
  id: unknown;
  sender_user_id: unknown;
  recipient_provider: unknown;
  recipient_subject: unknown;
  recipient_handle_snapshot: unknown;
  state: unknown;
  expires_at: unknown;
  created_at: unknown;
  accepted_at: unknown;
  version: unknown;
}

interface SocialInvitationRow extends QueryResultRow {
  outcome: unknown;
  principal_social_id: unknown;
  incoming_status: unknown;
  invitation_id: unknown;
  state: unknown;
  funding_kind: unknown;
  recipient_provider: unknown;
  recipient_handle_snapshot: unknown;
  expires_at: unknown;
  created_at: unknown;
  accepted_at: unknown;
  version: unknown;
  sender_social_id: unknown;
  sender_handle: unknown;
  sender_persona: unknown;
  sender_rank_id: unknown;
  party_role: unknown;
  created: unknown;
  retry_at: unknown;
  friendship_id: unknown;
  friendship_revision: unknown;
  connected_at: unknown;
}

const socialRankLabels: Readonly<Record<string, string>> = Object.freeze({
  rookie: 'Rookie', analyst: 'Analyst', trader: 'Trader',
  'senior-trader': 'Senior Trader', partner: 'Partner', legend: 'Legend',
});

const instant = (column: string) =>
  `to_char(${column} AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')`;
const columns = `id::text AS id, sender_user_id::text AS sender_user_id,
  recipient_provider, recipient_subject, recipient_handle_snapshot, state,
  ${instant('expires_at')} AS expires_at, ${instant('created_at')} AS created_at,
  ${instant('accepted_at')} AS accepted_at, version::text AS version`;

function storageInvalid(): never {
  throw new InvitationRepositoryError('INVITATION_STORAGE_INVALID', 'The stored invitation could not be read safely.');
}

function notFound(): never {
  throw new InvitationRepositoryError('INVITATION_NOT_FOUND', 'That invitation is unavailable.');
}

/** A fixed function outcome, safe to commit before it becomes an HTTP error. */
class SocialOutcomeError extends InvitationRepositoryError {}

function v2OutcomeError(value: unknown, retryAfterSeconds?: number): never {
  switch (value) {
    case 'invalid':
      throw new SocialOutcomeError('INVITATION_INVALID_INPUT', 'Invitation request is invalid.');
    case 'account_missing':
      throw new SocialOutcomeError('INVITATION_ACCOUNT_NOT_FOUND', 'The invitation account is unavailable.');
    case 'profile_missing':
      throw new SocialOutcomeError('SOCIAL_PROFILE_MISSING', 'The social profile is unavailable.');
    case 'identity_missing':
    case 'identity_ambiguous':
      throw new SocialOutcomeError('SOCIAL_IDENTITY_UNAVAILABLE', 'A verified X link is required.');
    case 'identity_conflict':
      throw new SocialOutcomeError('SOCIAL_IDENTITY_CONFLICT', 'The verified X link conflicts with another account.');
    case 'not_found':
      throw new SocialOutcomeError('INVITATION_NOT_FOUND', 'That invitation is unavailable.');
    case 'forbidden':
      throw new SocialOutcomeError('INVITATION_FORBIDDEN', 'This account cannot perform that invitation action.');
    case 'blocked':
      throw new SocialOutcomeError('SOCIAL_PAIR_UNAVAILABLE', 'That social connection is unavailable.');
    case 'already_friends':
      throw new SocialOutcomeError('INVITATION_INVALID_TRANSITION', 'That invitation action is not available now.');
    case 'friend_limit':
      throw new SocialOutcomeError('SOCIAL_FRIEND_LIMIT_REACHED', 'A friendship limit has been reached.');
    case 'open_limit':
      throw new SocialOutcomeError('INVITATION_LIMIT_REACHED', 'This account has too many open invitations.');
    case 'rate_limited':
      throw new SocialOutcomeError('SOCIAL_RATE_LIMITED', 'Too many social requests.', retryAfterSeconds);
    case 'revision_conflict':
      throw new SocialOutcomeError('INVITATION_VERSION_CONFLICT', 'The invitation changed. Reload it before continuing.');
    case 'idempotency_conflict':
      throw new SocialOutcomeError('SOCIAL_INVITATION_IDEMPOTENCY_CONFLICT', 'That mutation identifier is already in use.');
    case 'expired':
      throw new SocialOutcomeError('INVITATION_EXPIRED', 'The invitation has expired.');
    case 'invalid_transition':
      throw new SocialOutcomeError('INVITATION_INVALID_TRANSITION', 'That invitation action is not available now.');
    case 'revision_exhausted':
    case 'storage_missing':
      return storageInvalid();
    default:
      return storageInvalid();
  }
}

/**
 * Account-scoped invitation storage. Every statement runs inside a transaction
 * whose `trimmy.practice_user_id` setting drives the row policy, so a query can
 * only ever see invitations the requesting account is a party to.
 *
 * The domain owns every transition rule; this class loads a row, asks the domain
 * for the next state and writes it under an exact version guard.
 */
export class PostgresInvitationsRepository implements InvitationsRepository, InvitationsV2Repository {
  private readonly moderationRole: string;

  constructor(
    private readonly pool: Pick<Pool, 'connect'>,
    private readonly now: () => Date = () => new Date(),
    moderationRole = DEFAULT_RELATIONSHIP_MODERATION_ROLE,
  ) {
    this.moderationRole = parseRelationshipModerationRole(moderationRole);
  }

  private record(row: InvitationRow, userId: string): InvitationRecord {
    if (typeof row.version !== 'string' || /^(0|[1-9][0-9]{0,15})$/.exec(row.version)?.[0] !== row.version) storageInvalid();
    if (typeof row.sender_user_id !== 'string') storageInvalid();
    const subject = row.recipient_subject;
    const handle = row.recipient_handle_snapshot;
    const addressed = subject !== null;
    if (addressed && (row.recipient_provider !== 'x' || typeof subject !== 'string' || typeof handle !== 'string')) storageInvalid();
    try {
      return parseInvitationRecord({
        id: row.id, state: row.state, funding: 'unfunded',
        recipient: addressed ? {provider: 'x', subject, handleSnapshot: handle} : null,
        expiresAt: row.expires_at, createdAt: row.created_at, acceptedAt: row.accepted_at,
        version: Number(row.version),
        role: row.sender_user_id === userId ? 'sender' : 'recipient',
      });
    } catch { return storageInvalid(); }
  }

  /** The domain's view of a stored row, independent of who is asking. */
  private invitation(row: InvitationRow, record: InvitationRecord): UnfundedInvitation {
    if (typeof row.sender_user_id !== 'string') storageInvalid();
    return Object.freeze({
      id: record.id, senderUserId: row.sender_user_id, recipient: record.recipient,
      state: record.state, funding: 'unfunded', expiresAt: record.expiresAt, version: record.version,
    });
  }

  /**
   * Expiry is a fact about the clock rather than an act by either party, so a
   * read settles it before reporting. Without this, a passed invitation would
   * keep describing itself as offered and would hold its sender's quota for
   * good. Row security confines the update to invitations the caller is a party
   * to, and the state machine already permits draft, addressed or offered to
   * become expired.
   */
  private async settleExpired(client: PoolClient, invitationId?: string): Promise<void> {
    const scope = invitationId === undefined ? '' : ' AND id = $1::uuid';
    await client.query(
      `UPDATE trimmy.invitations
          SET state = 'expired', version = version + 1
        WHERE state NOT IN ('accepted', 'declined', 'expired', 'canceled')
          AND expires_at <= now()${scope}`,
      invitationId === undefined ? [] : [invitationId],
    );
  }

  /**
   * @deprecated Pre-0025 integration fixture support only. Production route
   * composition requires listV2/createV2/senderActionV2/answerV2 and migration
   * 0025 deliberately revokes this method's direct-table authority.
   */
  async list(inputUserId: string): Promise<readonly InvitationRecord[]> {
    const userId = parseInvitationUserId(inputUserId);
    return this.transaction(userId, false, async client => {
      await this.settleExpired(client);
      const result = await client.query<InvitationRow>(
        `SELECT ${columns} FROM trimmy.invitations ORDER BY created_at DESC, id LIMIT $1`,
        [MAX_OPEN_INVITATIONS * 4],
      );
      return Object.freeze(result.rows.map(row => this.record(row, userId)));
    });
  }

  /** @deprecated Pre-0025 integration fixture support only. See list(). */
  async create(inputUserId: string, input: InvitationCreate): Promise<InvitationRecord> {
    const userId = parseInvitationUserId(inputUserId);
    const id = parseInvitationId(input.id);
    const expiresAt = parseInvitationInstant(input.expiresAt);
    const now = this.instant();
    if (Date.parse(expiresAt) - Date.parse(now) > MAX_INVITATION_WINDOW_MS) {
      throw new InvitationRepositoryError('INVITATION_INVALID_INPUT', 'That invitation window is too long.');
    }
    // The domain refuses a window that is not in the future.
    let draft: UnfundedInvitation;
    try { draft = createUnfundedInvitation({id, senderUserId: userId, now, expiresAt}); }
    catch (error) { throw invitationErrorFromDomain(error); }
    return this.transaction(userId, false, async client => {
      const open = await client.query<{open_count: unknown}>(
        `SELECT count(*)::text AS open_count FROM trimmy.invitations
          WHERE sender_user_id = $1::uuid AND expires_at > now()
            AND state NOT IN ('accepted', 'declined', 'expired', 'canceled')`,
        [userId],
      );
      const count = Number(open.rows[0]?.open_count);
      if (!Number.isSafeInteger(count)) storageInvalid();
      if (count >= MAX_OPEN_INVITATIONS) {
        throw new InvitationRepositoryError('INVITATION_LIMIT_REACHED', 'This account has too many open invitations.');
      }
      const saved = await client.query<InvitationRow>(
        `INSERT INTO trimmy.invitations (id, sender_user_id, state, funding_kind, expires_at, version)
         VALUES ($1::uuid, $2::uuid, 'draft', 'unfunded', $3::timestamptz, 0)
         RETURNING ${columns}`,
        [draft.id, userId, expiresAt],
      );
      if (saved.rows.length !== 1) storageInvalid();
      return this.record(saved.rows[0]!, userId);
    });
  }

  /** @deprecated Pre-0025 integration fixture support only. See list(). */
  async apply(inputUserId: string, inputId: string, command: InvitationCommand): Promise<InvitationRecord> {
    const userId = parseInvitationUserId(inputUserId);
    const invitationId = parseInvitationId(inputId);
    const {action, expectedVersion} = command;
    const recipient = command.recipient;
    if ((action === 'address') !== (recipient !== null)) {
      throw new InvitationRepositoryError('INVITATION_INVALID_INPUT', 'Only addressing an invitation takes a recipient.');
    }
    const now = this.instant();
    return this.transaction(userId, false, async client => {
      const loaded = await client.query<InvitationRow>(
        `SELECT ${columns} FROM trimmy.invitations WHERE id = $1::uuid FOR UPDATE`, [invitationId],
      );
      if (loaded.rows.length === 0) notFound();
      if (loaded.rows.length !== 1) storageInvalid();
      const row = loaded.rows[0]!;
      const record = this.record(row, userId);
      const current = this.invitation(row, record);

      // Settle a passed invitation before refusing, so the stored state stops
      // claiming to be open and the caller learns the actual reason.
      const terminal = ['accepted', 'declined', 'expired', 'canceled'];
      if (!terminal.includes(record.state) && Date.parse(record.expiresAt) <= Date.parse(now)) {
        await this.settleExpired(client, invitationId);
        throw new InvitationRepositoryError('INVITATION_EXPIRED', 'The invitation has expired.');
      }

      if (action === 'address') {
        const next = this.addressed(current, recipient!, userId, expectedVersion, now);
        const saved = await client.query<InvitationRow>(
          `UPDATE trimmy.invitations
              SET state = 'addressed', recipient_provider = 'x', recipient_subject = $2,
                  recipient_handle_snapshot = $3, version = $4
            WHERE id = $1::uuid AND version = $5 RETURNING ${columns}`,
          [invitationId, recipient!.subject, recipient!.handleSnapshot, next.version, current.version],
        );
        return this.committed(saved, userId, next);
      }

      // Accepting or declining is only open to the addressed person, which the
      // database confirms independently through its own identity lookup.
      const authenticatedRecipient = action === 'accept' || action === 'decline'
        ? await this.selfRecipient(client, record)
        : null;
      let next: UnfundedInvitation;
      try {
        next = transitionUnfundedInvitation(current, action, {
          actorUserId: userId, authenticatedRecipient, expectedVersion, now,
        });
      } catch (error) { throw invitationErrorFromDomain(error); }
      // Answering binds the account that answered, whichever way it went, so
      // the record shows who declined as well as who accepted. Only acceptance
      // records a time, which the table's own constraint also requires.
      const answered = next.state === 'accepted' || next.state === 'declined';
      const accepted = next.state === 'accepted';
      const saved = await client.query<InvitationRow>(
        `UPDATE trimmy.invitations
            SET state = $2, version = $3,
                recipient_user_id = CASE WHEN $4 THEN $5::uuid ELSE recipient_user_id END,
                accepted_at = CASE WHEN $6 THEN $7::timestamptz ELSE accepted_at END
          WHERE id = $1::uuid AND version = $8 RETURNING ${columns}`,
        [invitationId, next.state, next.version, answered, userId, accepted, now, current.version],
      );
      return this.committed(saved, userId, next);
    });
  }

  async listV2(inputUserId: string, input: InvitationV2ListInput): Promise<InvitationV2ListPage> {
    const userId = parseInvitationUserId(inputUserId);
    const box = parseInvitationBox(input.box);
    const limit = parseInvitationLimit(input.limit);
    const freshXSubject = input.freshXSubject === null ? null : parseXSubject(input.freshXSubject);
    const cursor = input.cursor;
    if (cursor !== null) {
      parseInvitationId(cursor.principalSocialId);
      parseInvitationInstant(cursor.createdAt);
      parseInvitationId(cursor.invitationId);
    }
    return this.socialTransaction(userId, async client => {
      const result = await client.query<SocialInvitationRow>(
        `SELECT * FROM trimmy.social_invitation_list(
          $1::uuid, $2::text, $3::text, $4::timestamptz, $5::uuid, $6::integer)`,
        [userId, freshXSubject, box, cursor?.createdAt ?? null, cursor?.invitationId ?? null, limit + 1],
      );
      if (result.rows.length === 0) storageInvalid();
      const first = result.rows[0]!;
      if (first.outcome === 'empty') {
        if (result.rows.length !== 1) storageInvalid();
        const incoming = freshXSubject === null ? 'x_link_required' : 'available';
        if (first.incoming_status !== incoming) storageInvalid();
        const principalSocialId = parseInvitationId(first.principal_social_id);
        if (cursor !== null && cursor.principalSocialId !== principalSocialId) {
          throw new SocialOutcomeError('INVITATION_INVALID_INPUT', 'Invitation cursor is invalid.');
        }
        return Object.freeze({
          principalSocialId,
          invitations: Object.freeze([]),
          hasMore: false,
          incomingInvitations: incoming,
        });
      }
      if (first.outcome !== 'found') v2OutcomeError(first.outcome, this.retryAfter(first.retry_at));
      if (result.rows.length > limit + 1) storageInvalid();
      const principalSocialId = parseInvitationId(first.principal_social_id);
      if (cursor !== null && cursor.principalSocialId !== principalSocialId) {
        throw new SocialOutcomeError('INVITATION_INVALID_INPUT', 'Invitation cursor is invalid.');
      }
      const incoming = freshXSubject === null ? 'x_link_required' : 'available';
      if (first.incoming_status !== incoming) storageInvalid();
      const parsedRows = result.rows.map(row => {
        if (row.outcome !== 'found' || row.principal_social_id !== principalSocialId ||
            row.incoming_status !== incoming) {
          storageInvalid();
        }
        const invitation = this.v2Record(row);
        const isOpen = ['draft', 'addressed', 'offered'].includes(invitation.state);
        if ((box === 'open') !== isOpen ||
            box === 'open' && invitation.role === 'recipient' && invitation.state !== 'offered') {
          storageInvalid();
        }
        return invitation;
      });
      for (let index = 1; index < parsedRows.length; index++) {
        const previous = parsedRows[index - 1]!;
        const current = parsedRows[index]!;
        if (previous.createdAt < current.createdAt ||
            previous.createdAt === current.createdAt && previous.id <= current.id) storageInvalid();
      }
      const hasMore = parsedRows.length > limit;
      const invitations = parsedRows.slice(0, limit);
      return Object.freeze({
        principalSocialId,
        invitations: Object.freeze(invitations),
        hasMore,
        incomingInvitations: incoming,
      });
    });
  }

  async createV2(inputUserId: string, input: InvitationV2Create): Promise<InvitationV2CreateResult> {
    const userId = parseInvitationUserId(inputUserId);
    const mutationId = parseInvitationMutationId(input.mutationId);
    const expiresAt = parseInvitationInstant(input.expiresAt);
    // Semantic expiry validation belongs to the receipt-first database
    // function. An exact retry must still reach its durable receipt after the
    // wall clock passes the original expiry.
    const requestHash = createHash('sha256')
      .update(JSON.stringify(['social-invitation-create-v2', expiresAt]), 'utf8').digest('hex');
    return this.socialTransaction(userId, async client => {
      const result = await client.query<SocialInvitationRow>(
        `SELECT * FROM trimmy.social_invitation_create($1::uuid, $2::uuid, $3::text, $4::timestamptz)`,
        [userId, mutationId, requestHash, expiresAt],
      );
      const row = this.oneV2Row(result.rows);
      if (row.outcome !== 'saved') v2OutcomeError(row.outcome, this.retryAfter(row.retry_at));
      if (typeof row.created !== 'boolean') storageInvalid();
      const invitation = this.v2Record(row);
      if (invitation.role !== 'sender' || row.created &&
          (invitation.state !== 'draft' || invitation.version !== 0 || invitation.recipient !== null)) {
        storageInvalid();
      }
      return Object.freeze({invitation, created: row.created});
    });
  }

  async senderActionV2(inputUserId: string, inputId: string,
    command: InvitationV2SenderCommand): Promise<InvitationV2Record> {
    const userId = parseInvitationUserId(inputUserId);
    const invitationId = parseInvitationId(inputId);
    const action = parseInvitationV2SenderAction(command.action);
    const expectedVersion = parseInvitationVersion(command.expectedVersion);
    const recipient = action === 'address' ? this.resolvedRecipient(command.recipient) : null;
    if ((action === 'address') !== (command.recipient !== null)) {
      throw new InvitationRepositoryError('INVITATION_INVALID_INPUT', 'Invitation request is invalid.');
    }
    return this.socialTransaction(userId, async client => {
      const result = await client.query<SocialInvitationRow>(
        `SELECT * FROM trimmy.social_invitation_sender_action(
          $1::uuid, $2::uuid, $3::bigint, $4::text, $5::text, $6::text)`,
        [userId, invitationId, expectedVersion, action, recipient?.subject ?? null,
          recipient?.handleSnapshot ?? null],
      );
      const row = this.oneV2Row(result.rows);
      if (row.outcome !== 'saved') v2OutcomeError(row.outcome);
      const invitation = this.v2Record(row);
      const expectedState = action === 'address' ? 'addressed' : action === 'offer' ? 'offered' : 'canceled';
      if (invitation.role !== 'sender' || invitation.state !== expectedState) storageInvalid();
      return invitation;
    });
  }

  async answerV2(inputUserId: string, inputId: string,
    command: InvitationV2AnswerCommand): Promise<InvitationV2Record> {
    const userId = parseInvitationUserId(inputUserId);
    const invitationId = parseInvitationId(inputId);
    if (command.action !== 'accept' && command.action !== 'decline') {
      throw new InvitationRepositoryError('INVITATION_INVALID_INPUT', 'Invitation request is invalid.');
    }
    const expectedVersion = parseInvitationVersion(command.expectedVersion);
    const identity = this.freshIdentity(command.identity);
    return this.socialTransaction(userId, async client => {
      const result = await client.query<SocialInvitationRow>(
        `SELECT * FROM trimmy.social_invitation_answer(
          $1::uuid, $2::uuid, $3::bigint, $4::text, $5::text, $6::text, $7::timestamptz)`,
        [userId, invitationId, expectedVersion, command.action, identity.subject,
          identity.handleSnapshot, identity.verifiedAt],
      );
      const row = this.oneV2Row(result.rows);
      const expectedOutcome = command.action === 'accept' ? 'accepted' : 'saved';
      if (row.outcome !== expectedOutcome) {
        if (row.outcome === 'accepted' || row.outcome === 'saved') storageInvalid();
        v2OutcomeError(row.outcome);
      }
      const invitation = this.v2Record(row);
      const expectedState = command.action === 'accept' ? 'accepted' : 'declined';
      if (invitation.role !== 'recipient' || invitation.state !== expectedState) storageInvalid();
      return invitation;
    });
  }

  private oneV2Row(rows: SocialInvitationRow[]): SocialInvitationRow {
    if (rows.length !== 1) storageInvalid();
    return rows[0]!;
  }

  private resolvedRecipient(input: ResolvedXRecipient | null): ResolvedXRecipient {
    if (input === null || typeof input.handleSnapshot !== 'string' ||
        /^[a-z0-9_]{1,15}$/.exec(input.handleSnapshot)?.[0] !== input.handleSnapshot) {
      throw new InvitationRepositoryError('INVITATION_INVALID_INPUT', 'Invitation request is invalid.');
    }
    return Object.freeze({subject: parseXSubject(input.subject), handleSnapshot: input.handleSnapshot});
  }

  private freshIdentity(input: FreshVerifiedXIdentity): FreshVerifiedXIdentity {
    const recipient = this.resolvedRecipient(input);
    return Object.freeze({...recipient, verifiedAt: parseInvitationInstant(input.verifiedAt)});
  }

  private v2Record(row: SocialInvitationRow): InvitationV2Record {
    if (typeof row.version !== 'string' || /^(0|[1-9][0-9]{0,15})$/.exec(row.version)?.[0] !== row.version) {
      storageInvalid();
    }
    const rankLabel = typeof row.sender_rank_id === 'string' ? socialRankLabels[row.sender_rank_id] : undefined;
    const hasRecipient = row.recipient_provider !== null || row.recipient_handle_snapshot !== null;
    if (rankLabel === undefined || row.funding_kind !== 'unfunded' ||
        hasRecipient && (row.recipient_provider !== 'x' || typeof row.recipient_handle_snapshot !== 'string') ||
        !hasRecipient && (row.recipient_provider !== null || row.recipient_handle_snapshot !== null)) {
      storageInvalid();
    }
    try {
      return parseInvitationV2Record({
        id: row.invitation_id,
        state: row.state,
        funding: 'unfunded',
        sender: {
          socialId: row.sender_social_id,
          handle: row.sender_handle,
          persona: row.sender_persona,
          rank: {id: row.sender_rank_id, label: rankLabel},
        },
        recipient: !hasRecipient ? null : {
          provider: 'x', handleSnapshot: row.recipient_handle_snapshot,
        },
        expiresAt: this.databaseInstant(row.expires_at),
        createdAt: this.databaseInstant(row.created_at),
        acceptedAt: row.accepted_at === null ? null : this.databaseInstant(row.accepted_at),
        version: Number(row.version),
        role: row.party_role,
      });
    } catch { return storageInvalid(); }
  }

  private addressed(current: UnfundedInvitation, recipient: XRecipient, userId: string,
    expectedVersion: number, now: string): UnfundedInvitation {
    try {
      return addressUnfundedInvitation(current, recipient, {actorUserId: userId, expectedVersion, now});
    } catch (error) { throw invitationErrorFromDomain(error); }
  }

  /**
   * The caller's own verified X identity, but only when it is the one this
   * invitation was addressed to. The subject comes from the database rather
   * than the request, so a client cannot claim to be someone else.
   */
  private async selfRecipient(client: PoolClient, record: InvitationRecord): Promise<XRecipient | null> {
    const result = await client.query<{self_subject: unknown}>(
      'SELECT trimmy.invitation_self_x_subject() AS self_subject');
    if (result.rows.length !== 1) storageInvalid();
    const subject = result.rows[0]?.self_subject;
    if (subject === null || subject === undefined) return null;
    if (typeof subject !== 'string') storageInvalid();
    if (!record.recipient || record.recipient.subject !== subject) return null;
    return record.recipient;
  }

  private committed(saved: {rows: InvitationRow[]}, userId: string, expected: UnfundedInvitation): InvitationRecord {
    if (saved.rows.length === 0) {
      throw new InvitationRepositoryError('INVITATION_VERSION_CONFLICT', 'The invitation changed. Reload it before continuing.');
    }
    if (saved.rows.length !== 1) storageInvalid();
    const record = this.record(saved.rows[0]!, userId);
    if (record.version !== expected.version || record.state !== expected.state) storageInvalid();
    return record;
  }

  private instant(): string {
    const value = this.now();
    if (!(value instanceof Date) || !Number.isFinite(value.getTime())) storageInvalid();
    return parseInvitationInstant(value.toISOString());
  }

  private databaseInstant(value: unknown): string {
    if (value instanceof Date && Number.isFinite(value.getTime())) return parseInvitationInstant(value.toISOString());
    return parseInvitationInstant(value);
  }

  private retryAfter(value: unknown): number | undefined {
    if (value === null || value === undefined) return undefined;
    let retryAt: number;
    if (value instanceof Date && Number.isFinite(value.getTime())) retryAt = value.getTime();
    else {
      try { retryAt = Date.parse(parseInvitationInstant(value)); }
      catch { return storageInvalid(); }
    }
    const current = Date.parse(this.instant());
    if (retryAt <= current) return 1;
    return Math.min(86_400, Math.max(1, Math.ceil((retryAt - current) / 1000)));
  }

  private async socialTransaction<T>(userId: string, run: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.pool.connect();
    let releaseError: Error | undefined;
    try {
      await client.query('BEGIN');
      await this.assertRuntimeRole(client);
      await client.query("SELECT set_config('trimmy.practice_user_id', $1, true)", [userId]);
      const result = await run(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      if (error instanceof SocialOutcomeError) {
        try { await client.query('COMMIT'); }
        catch {
          try { await client.query('ROLLBACK'); }
          catch { releaseError = new Error('Invitation transaction cleanup failed.'); }
          throw new InvitationRepositoryError('INVITATION_UNAVAILABLE', 'Invitation storage is unavailable.');
        }
        throw error;
      }
      try { await client.query('ROLLBACK'); }
      catch { releaseError = new Error('Invitation transaction cleanup failed.'); }
      throw error;
    } finally {
      client.release(releaseError);
    }
  }

  private async assertRuntimeRole(client: PoolClient): Promise<void> {
    const role = await client.query<{unsafe_role: boolean}>(`
      SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_roles
        WHERE (rolsuper OR rolbypassrls) AND pg_catalog.pg_has_role(current_user, oid, 'MEMBER'))
        OR EXISTS (SELECT 1 FROM pg_catalog.pg_roles
          WHERE rolname = $1 AND pg_catalog.pg_has_role(current_user, oid, 'MEMBER'))
        OR EXISTS (SELECT 1 FROM pg_catalog.pg_class c
          JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'trimmy' AND c.relname IN (
            'users', 'invitations', 'provider_identities', 'product_profiles',
            'career_profiles', 'social_profiles', 'social_invitation_create_receipts',
            'social_friendships', 'social_friendship_events', 'social_friendship_receipts',
            'social_blocks', 'social_block_receipts', 'social_reason_reports',
            'social_reason_moderation', 'social_reason_moderation_events',
            'social_rate_windows')
            AND pg_catalog.pg_has_role(current_user, c.relowner, 'MEMBER')) AS unsafe_role`,
      [this.moderationRole]);
    if (role.rows.length !== 1 || role.rows[0]?.unsafe_role !== false) {
      throw new InvitationRepositoryError('INVITATION_RUNTIME_ROLE_INVALID', 'Invitation storage requires a dedicated runtime role.');
    }
  }

  private async transaction<T>(userId: string, readOnly: boolean, run: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.pool.connect();
    let releaseError: Error | undefined;
    try {
      await client.query(readOnly ? 'BEGIN READ ONLY' : 'BEGIN');
      await this.assertRuntimeRole(client);
      await client.query("SELECT set_config('trimmy.practice_user_id', $1, true)", [userId]);
      const account = await client.query<{account_exists: boolean}>('SELECT trimmy.practice_account_exists() AS account_exists');
      if (account.rows.length !== 1 || typeof account.rows[0]?.account_exists !== 'boolean') storageInvalid();
      if (!account.rows[0].account_exists) {
        throw new InvitationRepositoryError('INVITATION_ACCOUNT_NOT_FOUND', 'The invitation account is unavailable.');
      }
      const result = await run(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      try { await client.query('ROLLBACK'); }
      catch { releaseError = new Error('Invitation transaction cleanup failed.'); }
      throw error;
    } finally {
      client.release(releaseError);
    }
  }
}
