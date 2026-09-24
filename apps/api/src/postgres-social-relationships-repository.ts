import {createHash} from 'node:crypto';
import type {Pool, PoolClient, QueryResultRow} from 'pg';
import {parsePracticeUserId} from './practice-repository.js';
import {DEFAULT_RELATIONSHIP_MODERATION_ROLE, parseRelationshipModerationRole} from
  './relationship-safety-config.js';
import {
  SocialRelationshipError, parseSocialInstant, parseSocialLimit, parseSocialPersona,
  parseSocialHandle, parseSocialRank, parseSocialReportCategory, parseSocialRevision, parseSocialUuid,
  socialRankLabel,
} from './social-relationships.js';
import type {
  SocialBlock, SocialBlockCursor, SocialBlockMutation, SocialBlockPage, SocialBlockPutCommand,
  SocialBlockSnapshot,
  SocialFriend, SocialFriendCursor, SocialFriendPage, SocialFriendRemoval,
  SocialFriendRemoveCommand, SocialReasonReportCommand, SocialReasonReportResult,
  SocialRelationshipsRepository,
} from './social-relationships.js';

interface FriendRow extends QueryResultRow {
  outcome: unknown;
  principal_social_id: unknown;
  friendship_id: unknown;
  revision: unknown;
  connected_at: unknown;
  social_id: unknown;
  handle: unknown;
  persona: unknown;
  rank_id: unknown;
  retry_at: unknown;
}

interface FriendRemovalRow extends QueryResultRow {
  outcome: unknown;
  friendship_id: unknown;
  applied_revision: unknown;
  state: unknown;
  occurred_at: unknown;
  retry_at: unknown;
}

interface BlockRow extends QueryResultRow {
  outcome: unknown;
  principal_social_id: unknown;
  target_social_id: unknown;
  social_id: unknown;
  handle: unknown;
  applied_revision: unknown;
  revision: unknown;
  blocked: unknown;
  updated_at: unknown;
  retry_at: unknown;
}

interface ReportRow extends QueryResultRow {
  outcome: unknown;
  report_id: unknown;
  reason_id: unknown;
  category: unknown;
  received_at: unknown;
  retry_at: unknown;
}

class CommittedSocialOutcomeError extends SocialRelationshipError {}

function storageInvalid(): never {
  throw new SocialRelationshipError('SOCIAL_STORAGE_INVALID', 'Stored social data is unavailable.');
}

function inputInvalid(): never {
  throw new SocialRelationshipError('SOCIAL_INVALID_INPUT', 'Social request is invalid.');
}

function committedInvalid(): never {
  return committed('SOCIAL_INVALID_INPUT', 'Social request is invalid.');
}

function storedUuid(value: unknown): string {
  try { return parseSocialUuid(value); } catch { return storageInvalid(); }
}

function storedInstant(value: unknown): string {
  try {
    if (value instanceof Date && Number.isFinite(value.getTime())) return parseSocialInstant(value.toISOString());
    return parseSocialInstant(value);
  } catch { return storageInvalid(); }
}

function storedRevision(value: unknown, allowZero = false): number {
  if (typeof value !== 'string' || !/^(?:0|[1-9][0-9]{0,15})$/u.test(value)) storageInvalid();
  try { return parseSocialRevision(Number(value), allowZero); } catch { return storageInvalid(); }
}

function nullable(value: unknown): boolean { return value === null || value === undefined; }

function retryAfter(value: unknown): number | undefined {
  if (nullable(value)) return undefined;
  const retryAt = Date.parse(storedInstant(value));
  const seconds = Math.ceil((retryAt - Date.now()) / 1000);
  return Math.min(86_400, Math.max(1, seconds));
}

function committed(
  code: ConstructorParameters<typeof SocialRelationshipError>[0],
  message: string,
  retry?: number,
): never {
  throw new CommittedSocialOutcomeError(code, message, retry);
}

function commonOutcome(outcome: unknown, row: {readonly retry_at: unknown}): never {
  switch (outcome) {
    case 'invalid': return committed('SOCIAL_INVALID_INPUT', 'Social request is invalid.');
    case 'account_missing': return committed('SOCIAL_ACCOUNT_NOT_FOUND', 'The social account is unavailable.');
    case 'rate_limited': {
      const retry = retryAfter(row.retry_at);
      if (retry === undefined) storageInvalid();
      return committed('SOCIAL_RATE_LIMITED', 'Too many social requests.', retry);
    }
    case 'revision_exhausted':
      return committed('SOCIAL_STORAGE_INVALID', 'Stored social data is unavailable.');
    default: return storageInvalid();
  }
}

function friendListSentinel(row: FriendRow): boolean {
  return row.outcome === 'empty' && !nullable(row.principal_social_id) &&
    nullable(row.friendship_id) && nullable(row.revision) && nullable(row.connected_at) &&
    nullable(row.social_id) && nullable(row.handle) && nullable(row.persona) &&
    nullable(row.rank_id) && nullable(row.retry_at);
}

function blockListSentinel(row: BlockRow): boolean {
  return row.outcome === 'empty' && !nullable(row.principal_social_id) &&
    nullable(row.social_id) && nullable(row.handle) && nullable(row.revision) &&
    nullable(row.updated_at) && nullable(row.retry_at);
}

function friendListErrorSentinel(row: FriendRow): boolean {
  const retryExpected = row.outcome === 'rate_limited';
  return nullable(row.principal_social_id) && nullable(row.friendship_id) &&
    nullable(row.revision) && nullable(row.connected_at) && nullable(row.social_id) &&
    nullable(row.handle) && nullable(row.persona) && nullable(row.rank_id) &&
    (retryExpected ? !nullable(row.retry_at) : nullable(row.retry_at));
}

function blockListErrorSentinel(row: BlockRow): boolean {
  const retryExpected = row.outcome === 'rate_limited';
  return nullable(row.principal_social_id) && nullable(row.social_id) &&
    nullable(row.handle) && nullable(row.revision) && nullable(row.updated_at) &&
    (retryExpected ? !nullable(row.retry_at) : nullable(row.retry_at));
}

function removalNullError(row: FriendRemovalRow): boolean {
  const retryExpected = row.outcome === 'rate_limited';
  return nullable(row.friendship_id) && nullable(row.applied_revision) &&
    nullable(row.state) && nullable(row.occurred_at) &&
    (retryExpected ? !nullable(row.retry_at) : nullable(row.retry_at));
}

function blockNullError(row: BlockRow): boolean {
  const retryExpected = row.outcome === 'rate_limited';
  return nullable(row.target_social_id) && nullable(row.applied_revision) &&
    nullable(row.revision) && nullable(row.blocked) && nullable(row.updated_at) &&
    (retryExpected ? !nullable(row.retry_at) : nullable(row.retry_at));
}

function reportNullError(row: ReportRow): boolean {
  const retryExpected = row.outcome === 'rate_limited';
  return nullable(row.report_id) && nullable(row.reason_id) && nullable(row.category) &&
    nullable(row.received_at) &&
    (retryExpected ? !nullable(row.retry_at) : nullable(row.retry_at));
}

function friend(row: FriendRow): SocialFriend {
  try {
    const rank = parseSocialRank(row.rank_id);
    return Object.freeze({
      friendshipId: storedUuid(row.friendship_id),
      revision: storedRevision(row.revision),
      connectedAt: storedInstant(row.connected_at),
      person: Object.freeze({
        socialId: storedUuid(row.social_id),
        handle: parseSocialHandle(row.handle),
        persona: parseSocialPersona(row.persona),
        rank: Object.freeze({id: rank, label: socialRankLabel(rank)}),
      }),
    });
  } catch { return storageInvalid(); }
}

function listedBlock(row: BlockRow): SocialBlock {
  try {
    if (row.handle !== null && (typeof row.handle !== 'string' ||
        !/^[a-z][a-z0-9_]{2,17}$/u.test(row.handle))) storageInvalid();
    return Object.freeze({
      socialId: storedUuid(row.social_id),
      handle: row.handle,
      revision: storedRevision(row.revision),
      blocked: true,
      updatedAt: storedInstant(row.updated_at),
    });
  } catch { return storageInvalid(); }
}

function compareFriend(left: SocialFriend, right: SocialFriend): number {
  if (left.connectedAt !== right.connectedAt) return left.connectedAt > right.connectedAt ? -1 : 1;
  return left.friendshipId > right.friendshipId ? -1 : left.friendshipId === right.friendshipId ? 0 : 1;
}

function compareBlock(left: SocialBlock, right: SocialBlock): number {
  if (left.updatedAt !== right.updatedAt) return left.updatedAt > right.updatedAt ? -1 : 1;
  return left.socialId > right.socialId ? -1 : left.socialId === right.socialId ? 0 : 1;
}

export class PostgresSocialRelationshipsRepository implements SocialRelationshipsRepository {
  private readonly moderationRole: string;

  constructor(
    private readonly pool: Pick<Pool, 'connect'>,
    moderationRole = DEFAULT_RELATIONSHIP_MODERATION_ROLE,
  ) {
    this.moderationRole = parseRelationshipModerationRole(moderationRole);
  }

  async listFriends(inputUserId: string, input: Readonly<{
    limit: number;
    cursor: SocialFriendCursor | null;
  }>): Promise<SocialFriendPage> {
    const userId = parsePracticeUserId(inputUserId);
    const limit = parseSocialLimit(input.limit);
    const cursor = input.cursor;
    if (cursor !== null) {
      parseSocialUuid(cursor.principalSocialId);
      parseSocialInstant(cursor.connectedAt);
      parseSocialUuid(cursor.friendshipId);
    }
    return this.transaction(userId, async client => {
      const result = await client.query<FriendRow>(
        `SELECT * FROM trimmy.social_friend_list(
          $1::uuid,$2::timestamptz,$3::uuid,$4::integer)`,
        [userId, cursor?.connectedAt ?? null, cursor?.friendshipId ?? null, limit + 1],
      );
      if (result.rows.length === 1 && result.rows[0] && friendListSentinel(result.rows[0])) {
        const principalSocialId = storedUuid(result.rows[0].principal_social_id);
        if (cursor !== null && cursor.principalSocialId !== principalSocialId) committedInvalid();
        return Object.freeze({principalSocialId, friends: Object.freeze([]), hasMore: false});
      }
      if (result.rows.length === 0 || result.rows.length > limit + 1 ||
          result.rows.some(row => row.outcome !== 'found')) {
        if (result.rows.length !== 1 || !result.rows[0] || !friendListErrorSentinel(result.rows[0])) {
          storageInvalid();
        }
        return commonOutcome(result.rows[0]?.outcome, result.rows[0] ?? {retry_at: null});
      }
      const principalSocialId = storedUuid(result.rows[0]!.principal_social_id);
      if (cursor !== null && cursor.principalSocialId !== principalSocialId) committedInvalid();
      const friends = result.rows.map(row => {
        if (row.principal_social_id !== principalSocialId || !nullable(row.retry_at)) storageInvalid();
        return friend(row);
      });
      if (new Set(friends.map(item => item.friendshipId)).size !== friends.length ||
          new Set(friends.map(item => item.person.socialId)).size !== friends.length ||
          friends.some((item, index) => index > 0 && compareFriend(friends[index - 1]!, item) >= 0) ||
          friends.some(item => cursor !== null && (item.connectedAt > cursor.connectedAt ||
            item.connectedAt === cursor.connectedAt && item.friendshipId >= cursor.friendshipId))) storageInvalid();
      return Object.freeze({
        principalSocialId,
        friends: Object.freeze(friends.slice(0, limit)),
        hasMore: friends.length > limit,
      });
    });
  }

  async removeFriend(inputUserId: string, inputFriendshipId: string,
    input: SocialFriendRemoveCommand): Promise<SocialFriendRemoval> {
    const userId = parsePracticeUserId(inputUserId);
    const friendshipId = parseSocialUuid(inputFriendshipId);
    const mutationId = parseSocialUuid(input.mutationId);
    const expectedRevision = parseSocialRevision(input.expectedRevision);
    const requestHash = createHash('sha256').update(JSON.stringify([
      'social-friend-remove-v1', friendshipId, expectedRevision,
    ]), 'utf8').digest('hex');
    return this.transaction(userId, async client => {
      const result = await client.query<FriendRemovalRow>(
        `SELECT * FROM trimmy.social_friend_remove(
          $1::uuid,$2::uuid,$3::uuid,$4::text,$5::bigint)`,
        [userId, friendshipId, mutationId, requestHash, expectedRevision],
      );
      if (result.rows.length !== 1) storageInvalid();
      const row = result.rows[0]!;
      if (row.outcome !== 'removed') {
        if (row.outcome === 'revision_conflict') {
          if (storedUuid(row.friendship_id) !== friendshipId ||
              !['active', 'removed'].includes(row.state as string) ||
              !nullable(row.retry_at)) storageInvalid();
          storedRevision(row.applied_revision);
          storedInstant(row.occurred_at);
        } else if (!removalNullError(row)) storageInvalid();
        switch (row.outcome) {
          case 'not_found': return committed('SOCIAL_RELATIONSHIP_NOT_FOUND', 'That relationship is unavailable.');
          case 'idempotency_conflict': return committed('SOCIAL_RELATIONSHIP_IDEMPOTENCY_CONFLICT', 'That mutation identifier is already in use.');
          case 'revision_conflict':
            return committed(row.state === 'removed'
              ? 'SOCIAL_RELATIONSHIP_NOT_ACTIVE'
              : 'SOCIAL_RELATIONSHIP_REVISION_CONFLICT', 'That relationship changed.');
          default: return commonOutcome(row.outcome, row);
        }
      }
      const returnedId = storedUuid(row.friendship_id);
      if (returnedId !== friendshipId || row.state !== 'removed' || !nullable(row.retry_at)) storageInvalid();
      return Object.freeze({
        mutationId,
        friendshipId: returnedId,
        appliedRevision: storedRevision(row.applied_revision),
        state: 'removed' as const,
        occurredAt: storedInstant(row.occurred_at),
      });
    });
  }

  async listBlocks(inputUserId: string, input: Readonly<{
    limit: number;
    cursor: SocialBlockCursor | null;
  }>): Promise<SocialBlockPage> {
    const userId = parsePracticeUserId(inputUserId);
    const limit = parseSocialLimit(input.limit);
    const cursor = input.cursor;
    if (cursor !== null) {
      parseSocialUuid(cursor.principalSocialId);
      parseSocialInstant(cursor.updatedAt);
      parseSocialUuid(cursor.socialId);
    }
    return this.transaction(userId, async client => {
      const result = await client.query<BlockRow>(
        `SELECT * FROM trimmy.social_block_list(
          $1::uuid,$2::timestamptz,$3::uuid,$4::integer)`,
        [userId, cursor?.updatedAt ?? null, cursor?.socialId ?? null, limit + 1],
      );
      if (result.rows.length === 1 && result.rows[0] && blockListSentinel(result.rows[0])) {
        const principalSocialId = storedUuid(result.rows[0].principal_social_id);
        if (cursor !== null && cursor.principalSocialId !== principalSocialId) committedInvalid();
        return Object.freeze({principalSocialId, blocks: Object.freeze([]), hasMore: false});
      }
      if (result.rows.length === 0 || result.rows.length > limit + 1 ||
          result.rows.some(row => row.outcome !== 'found')) {
        if (result.rows.length !== 1 || !result.rows[0] || !blockListErrorSentinel(result.rows[0])) {
          storageInvalid();
        }
        return commonOutcome(result.rows[0]?.outcome, result.rows[0] ?? {retry_at: null});
      }
      const principalSocialId = storedUuid(result.rows[0]!.principal_social_id);
      if (cursor !== null && cursor.principalSocialId !== principalSocialId) committedInvalid();
      const blocks = result.rows.map(row => {
        if (row.principal_social_id !== principalSocialId || !nullable(row.retry_at)) storageInvalid();
        return listedBlock(row);
      });
      if (new Set(blocks.map(item => item.socialId)).size !== blocks.length ||
          blocks.some((item, index) => index > 0 && compareBlock(blocks[index - 1]!, item) >= 0) ||
          blocks.some(item => cursor !== null && (item.updatedAt > cursor.updatedAt ||
            item.updatedAt === cursor.updatedAt && item.socialId >= cursor.socialId))) storageInvalid();
      return Object.freeze({
        principalSocialId,
        blocks: Object.freeze(blocks.slice(0, limit)),
        hasMore: blocks.length > limit,
      });
    });
  }

  async putBlock(inputUserId: string, inputSocialId: string,
    input: SocialBlockPutCommand): Promise<SocialBlockMutation> {
    const userId = parsePracticeUserId(inputUserId);
    const socialId = parseSocialUuid(inputSocialId);
    const mutationId = parseSocialUuid(input.mutationId);
    const baseRevision = parseSocialRevision(input.baseRevision, true);
    if (typeof input.blocked !== 'boolean') inputInvalid();
    const requestHash = createHash('sha256').update(JSON.stringify([
      'social-block-put-v1', socialId, baseRevision, input.blocked,
    ]), 'utf8').digest('hex');
    return this.transaction(userId, async client => {
      const result = await client.query<BlockRow>(
        `SELECT * FROM trimmy.social_block_put(
          $1::uuid,$2::uuid,$3::uuid,$4::text,$5::bigint,$6::text)`,
        [userId, socialId, mutationId, requestHash, baseRevision,
          input.blocked ? 'active' : 'inactive'],
      );
      if (result.rows.length !== 1) storageInvalid();
      const row = result.rows[0]!;
      if (row.outcome !== 'saved') {
        if (row.outcome === 'revision_conflict') {
          if (storedUuid(row.target_social_id) !== socialId || !nullable(row.applied_revision) ||
              typeof row.blocked !== 'boolean' || !nullable(row.retry_at)) storageInvalid();
          const revision = storedRevision(row.revision, true);
          if ((revision === 0) !== nullable(row.updated_at)) storageInvalid();
          if (revision > 0) storedInstant(row.updated_at);
        } else if (!blockNullError(row)) storageInvalid();
        switch (row.outcome) {
          case 'not_found': return committed('SOCIAL_PAIR_UNAVAILABLE', 'That social connection is unavailable.');
          case 'idempotency_conflict': return committed('SOCIAL_BLOCK_IDEMPOTENCY_CONFLICT', 'That mutation identifier is already in use.');
          case 'revision_conflict': return committed('SOCIAL_BLOCK_REVISION_CONFLICT', 'That block changed.');
          default: return commonOutcome(row.outcome, row);
        }
      }
      const returnedSocialId = storedUuid(row.target_social_id);
      if (returnedSocialId !== socialId || typeof row.blocked !== 'boolean' || !nullable(row.retry_at)) storageInvalid();
      const block = Object.freeze({
        socialId: returnedSocialId,
        handle: null,
        revision: storedRevision(row.revision),
        blocked: row.blocked,
        updatedAt: storedInstant(row.updated_at),
      });
      const appliedRevision = storedRevision(row.applied_revision);
      if (appliedRevision > block.revision) storageInvalid();
      return Object.freeze({
        mutationId,
        appliedRevision,
        block,
      });
    });
  }

  async getBlock(inputUserId: string, inputSocialId: string): Promise<SocialBlockSnapshot> {
    const userId = parsePracticeUserId(inputUserId);
    const socialId = parseSocialUuid(inputSocialId);
    return this.transaction(userId, async client => {
      const result = await client.query<BlockRow>(
        `SELECT * FROM trimmy.social_block_get($1::uuid,$2::uuid)`,
        [userId, socialId],
      );
      if (result.rows.length !== 1) storageInvalid();
      const row = result.rows[0]!;
      if (row.outcome !== 'found') {
        if (!blockNullError(row)) storageInvalid();
        if (row.outcome === 'not_found') {
          return committed('SOCIAL_RELATIONSHIP_NOT_FOUND', 'That social item is unavailable.');
        }
        return commonOutcome(row.outcome, row);
      }
      const returnedSocialId = storedUuid(row.target_social_id);
      const revision = storedRevision(row.revision, true);
      if (returnedSocialId !== socialId || typeof row.blocked !== 'boolean' ||
          !nullable(row.retry_at) || revision === 0 &&
            (row.blocked || !nullable(row.updated_at)) || revision > 0 && nullable(row.updated_at)) {
        storageInvalid();
      }
      return Object.freeze({
        socialId: returnedSocialId,
        revision,
        blocked: row.blocked,
        updatedAt: revision === 0 ? null : storedInstant(row.updated_at),
      });
    });
  }

  async reportReason(inputUserId: string,
    input: SocialReasonReportCommand): Promise<SocialReasonReportResult> {
    const userId = parsePracticeUserId(inputUserId);
    const mutationId = parseSocialUuid(input.mutationId);
    const reasonId = parseSocialUuid(input.reasonId);
    const category = parseSocialReportCategory(input.category);
    const requestHash = createHash('sha256').update(JSON.stringify([
      'social-reason-report-v1', reasonId, category,
    ]), 'utf8').digest('hex');
    return this.transaction(userId, async client => {
      const result = await client.query<ReportRow>(
        `SELECT * FROM trimmy.social_reason_report_create(
          $1::uuid,$2::uuid,$3::text,$4::uuid,$5::text)`,
        [userId, mutationId, requestHash, reasonId, category],
      );
      if (result.rows.length !== 1) storageInvalid();
      const row = result.rows[0]!;
      if (row.outcome !== 'reported' && row.outcome !== 'found') {
        if (!reportNullError(row)) storageInvalid();
        switch (row.outcome) {
          case 'not_found': return committed('SOCIAL_RELATIONSHIP_NOT_FOUND', 'That social item is unavailable.');
          case 'idempotency_conflict': return committed('SOCIAL_REPORT_IDEMPOTENCY_CONFLICT', 'That mutation identifier is already in use.');
          default: return commonOutcome(row.outcome, row);
        }
      }
      let returnedCategory;
      try { returnedCategory = parseSocialReportCategory(row.category); }
      catch { return storageInvalid(); }
      if (storedUuid(row.reason_id) !== reasonId ||
          row.outcome === 'reported' && returnedCategory !== category || !nullable(row.retry_at)) {
        storageInvalid();
      }
      return Object.freeze({
        report: Object.freeze({
          reportId: storedUuid(row.report_id), reasonId, category: returnedCategory,
          receivedAt: storedInstant(row.received_at),
        }),
        created: row.outcome === 'reported',
      });
    });
  }

  private async assertRuntimeRole(client: PoolClient): Promise<void> {
    const result = await client.query<{unsafe_role: boolean}>(`
      SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_roles
        WHERE (rolsuper OR rolbypassrls)
          AND pg_catalog.pg_has_role(current_user, oid, 'MEMBER'))
        OR EXISTS (SELECT 1 FROM pg_catalog.pg_roles
          WHERE rolname = $1 AND pg_catalog.pg_has_role(current_user, oid, 'MEMBER'))
        OR EXISTS (SELECT 1 FROM pg_catalog.pg_class c
          JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'trimmy' AND c.relname IN (
            'users', 'product_profiles', 'career_profiles', 'career_trade_reasons',
            'career_reason_privacy', 'career_reason_privacy_receipts',
            'paper_orders', 'paper_accounts', 'provider_identities', 'invitations',
            'social_profiles', 'social_invitation_create_receipts',
            'social_friendships', 'social_friendship_events',
            'social_friendship_receipts', 'social_blocks', 'social_block_receipts',
            'social_reason_reports', 'social_reason_moderation',
            'social_reason_moderation_events', 'social_rate_windows')
          AND pg_catalog.pg_has_role(current_user, c.relowner, 'MEMBER')) AS unsafe_role`,
      [this.moderationRole],
    );
    if (result.rows.length !== 1 || result.rows[0]?.unsafe_role !== false) {
      throw new SocialRelationshipError(
        'SOCIAL_RUNTIME_ROLE_INVALID', 'Social storage requires a dedicated runtime role.',
      );
    }
  }

  private async transaction<T>(userId: string, run: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.pool.connect();
    let releaseError: Error | undefined;
    try {
      await client.query('BEGIN');
      await this.assertRuntimeRole(client);
      const scoped = await client.query<{scoped_user: unknown}>(
        `SELECT set_config('trimmy.practice_user_id', $1, true) AS scoped_user`, [userId],
      );
      if (scoped.rows.length !== 1 || scoped.rows[0]?.scoped_user !== userId) storageInvalid();
      const value = await run(client);
      await client.query('COMMIT');
      return value;
    } catch (error) {
      if (error instanceof CommittedSocialOutcomeError) {
        try { await client.query('COMMIT'); }
        catch {
          try { await client.query('ROLLBACK'); }
          catch { releaseError = new Error('Social transaction cleanup failed.'); }
          throw new SocialRelationshipError('SOCIAL_UNAVAILABLE', 'Social storage is unavailable.');
        }
        throw error;
      }
      try { await client.query('ROLLBACK'); }
      catch { releaseError = new Error('Social transaction cleanup failed.'); }
      if (error instanceof SocialRelationshipError) throw error;
      throw new SocialRelationshipError('SOCIAL_UNAVAILABLE', 'Social storage is unavailable.');
    } finally {
      client.release(releaseError);
    }
  }
}
