import {createHash} from 'node:crypto';
import type {Pool, PoolClient, QueryResultRow} from 'pg';
import {
  CareerReasonSharingError,
  isCareerReasonFriendsListItem,
  isCareerReasonInternalListItem,
  parseCareerReasonListItem,
  parseCareerReasonListQuery,
  parseCareerReasonPrivacy,
  parseCareerReasonPrivacyWrite,
  parseCareerReasonSocialId,
  parseCareerReasonUserId,
} from './career-reason-sharing.js';
import {DEFAULT_RELATIONSHIP_MODERATION_ROLE, parseRelationshipModerationRole} from
  './relationship-safety-config.js';
import type {
  CareerReasonListItem,
  CareerReasonListPage,
  CareerReasonListQuery,
  CareerReasonPrivacy,
  CareerReasonPrivacyWrite,
  CareerReasonSharingRepository,
} from './career-reason-sharing.js';

interface PrivacyRow extends QueryResultRow {
  outcome: unknown;
  revision: unknown;
  visibility: unknown;
  configured: unknown;
  created_at: unknown;
  updated_at: unknown;
}

interface ReasonListRow extends QueryResultRow {
  outcome: unknown;
  principal_social_id: unknown;
  reason_id: unknown;
  order_id: unknown;
  author_social_id: unknown;
  author_handle: unknown;
  author_persona: unknown;
  author_rank_id: unknown;
  asset_id: unknown;
  variant_mint: unknown;
  symbol: unknown;
  note: unknown;
  desk_cycle: unknown;
  saved_at: unknown;
  is_viewer: unknown;
}

const privacyColumns = `outcome, revision::text AS revision, visibility, configured,
  created_at, updated_at`;

const listColumns = `outcome, principal_social_id::text AS principal_social_id,
  reason_id::text AS reason_id, order_id::text AS order_id,
  author_social_id::text AS author_social_id, author_handle, author_persona,
  author_rank_id, asset_id, variant_mint, symbol, note, desk_cycle,
  saved_at, is_viewer`;

function storageInvalid(): never {
  throw new CareerReasonSharingError(
    'CAREER_REASON_SHARING_STORAGE_INVALID',
    'Career reason sharing storage is invalid.',
  );
}

function safeInteger(input: unknown): number {
  if (typeof input !== 'string' || !/^[1-9][0-9]{0,15}$/u.test(input)) storageInvalid();
  const value = Number(input);
  if (!Number.isSafeInteger(value) || value < 1) storageInvalid();
  return value;
}

function timestamp(input: unknown): string {
  if (!(input instanceof Date) || !Number.isFinite(input.getTime())) storageInvalid();
  return input.toISOString();
}

function socialId(input: unknown): string {
  try { return parseCareerReasonSocialId(input); }
  catch { return storageInvalid(); }
}

function privacy(row: PrivacyRow): CareerReasonPrivacy {
  return parseCareerReasonPrivacy({
    revision: safeInteger(row.revision),
    visibility: row.visibility,
    configured: row.configured,
    friendsSharing: 'unavailable',
    createdAt: timestamp(row.created_at),
    updatedAt: timestamp(row.updated_at),
  });
}

function reason(row: ReasonListRow, scope: CareerReasonListQuery['scope']): CareerReasonListItem {
  const base = {
    reasonId: row.reason_id,
    stock: {assetId: row.asset_id, variantMint: row.variant_mint, symbol: row.symbol},
    note: row.note,
    savedAt: timestamp(row.saved_at),
  };
  if (scope === 'friends') {
    if (row.order_id !== null || row.desk_cycle !== null) storageInvalid();
    return parseCareerReasonListItem({
      ...base,
      author: {
        socialId: row.author_social_id,
        handle: row.author_handle,
        persona: row.author_persona,
        rank: {id: row.author_rank_id, label: rankLabel(row.author_rank_id)},
        isViewer: row.is_viewer,
      },
    });
  }
  if (row.author_social_id !== null || row.author_persona !== null) storageInvalid();
  return parseCareerReasonListItem({
    ...base,
    orderId: row.order_id,
    author: {
      handle: row.author_handle,
      rank: {id: row.author_rank_id, label: rankLabel(row.author_rank_id)},
      isViewer: row.is_viewer,
    },
    deskCycle: row.desk_cycle,
  });
}

function rankLabel(input: unknown): string {
  const labels: Readonly<Record<string, string>> = Object.freeze({
    rookie: 'Rookie',
    analyst: 'Analyst',
    trader: 'Trader',
    'senior-trader': 'Senior Trader',
    partner: 'Partner',
    legend: 'Legend',
  });
  if (typeof input !== 'string' || !Object.hasOwn(labels, input)) storageInvalid();
  return labels[input]!;
}

function mapOutcome(outcome: unknown): never {
  const code = outcome === 'account_missing'
    ? 'CAREER_REASON_SHARING_ACCOUNT_NOT_FOUND'
    : outcome === 'revision_conflict'
      ? 'CAREER_REASON_PRIVACY_REVISION_CONFLICT'
      : outcome === 'idempotency_conflict'
        ? 'CAREER_REASON_SHARING_IDEMPOTENCY_CONFLICT'
        : outcome === 'revision_exhausted'
          ? 'CAREER_REASON_SHARING_REVISION_EXHAUSTED'
          : outcome === 'forbidden'
            ? 'CAREER_REASON_FRIENDS_ACCOUNT_REQUIRED'
          : outcome === 'invalid'
            ? 'CAREER_REASON_SHARING_INVALID_INPUT'
            : 'CAREER_REASON_SHARING_STORAGE_INVALID';
  throw new CareerReasonSharingError(code, 'Career reason sharing request was not accepted.');
}

function compareDesc(left: CareerReasonListItem, right: CareerReasonListItem): number {
  const leftKey = left.savedAt === right.savedAt ? left.reasonId : left.savedAt;
  const rightKey = left.savedAt === right.savedAt ? right.reasonId : right.savedAt;
  return leftKey > rightKey ? -1 : leftKey === rightKey ? 0 : 1;
}

function emptySentinel(row: ReasonListRow): boolean {
  return row.outcome === 'empty' && row.reason_id === null && row.order_id === null &&
    row.author_social_id === null && row.author_handle === null && row.author_persona === null &&
    row.author_rank_id === null &&
    row.asset_id === null && row.variant_mint === null && row.symbol === null &&
    row.note === null && row.desk_cycle === null && row.saved_at === null &&
    row.is_viewer === null;
}

export class PostgresCareerReasonSharingRepository implements CareerReasonSharingRepository {
  private readonly moderationRole: string;

  constructor(
    private readonly pool: Pick<Pool, 'connect'>,
    moderationRole = DEFAULT_RELATIONSHIP_MODERATION_ROLE,
  ) {
    this.moderationRole = parseRelationshipModerationRole(moderationRole);
  }

  async getPrivacy(inputUserId: string): Promise<CareerReasonPrivacy> {
    const userId = parseCareerReasonUserId(inputUserId);
    return this.transaction(userId, true, async client => {
      const result = await client.query<PrivacyRow>(
        `SELECT ${privacyColumns}
         FROM trimmy.career_reason_privacy_get($1::uuid)`,
        [userId],
      );
      if (result.rows.length !== 1 || result.rows[0]?.outcome !== 'found') {
        mapOutcome(result.rows[0]?.outcome);
      }
      return privacy(result.rows[0]);
    });
  }

  async savePrivacy(
    inputUserId: string,
    input: CareerReasonPrivacyWrite,
  ): Promise<CareerReasonPrivacy> {
    const userId = parseCareerReasonUserId(inputUserId);
    const command = parseCareerReasonPrivacyWrite(input);
    const requestHash = createHash('sha256').update(JSON.stringify({
      baseRevision: command.baseRevision,
      visibility: command.visibility,
    })).digest('hex');
    return this.transaction(userId, false, async client => {
      const result = await client.query<PrivacyRow>(
        `SELECT ${privacyColumns}
         FROM trimmy.career_reason_privacy_put(
           $1::uuid,$2::uuid,$3::text,$4::bigint,$5::text)`,
        [userId, command.mutationId, requestHash,
          command.baseRevision, command.visibility],
      );
      if (result.rows.length !== 1 || result.rows[0]?.outcome !== 'saved') {
        mapOutcome(result.rows[0]?.outcome);
      }
      return privacy(result.rows[0]);
    });
  }

  async listReasons(
    inputUserId: string,
    input: CareerReasonListQuery,
  ): Promise<CareerReasonListPage> {
    const userId = parseCareerReasonUserId(inputUserId);
    const query = parseCareerReasonListQuery(input);
    return this.transaction(userId, true, async client => {
      const result = await client.query<ReasonListRow>(
        `SELECT ${listColumns}
         FROM trimmy.career_trade_reason_list(
           $1::uuid,$2::text,$3::text,$4::text,$5::timestamptz,$6::uuid,$7::integer)`,
        [userId, query.scope, query.assetId, query.variantMint,
          query.cursor?.savedAt ?? null, query.cursor?.reasonId ?? null, query.limit],
      );
      if (result.rows.length === 1 && result.rows[0] && emptySentinel(result.rows[0])) {
        if (query.scope === 'friends') {
          return Object.freeze({
            reasons: Object.freeze([]),
            hasMore: false,
            principalSocialId: socialId(result.rows[0].principal_social_id),
          });
        }
        if (result.rows[0].principal_social_id !== null) storageInvalid();
        return Object.freeze({reasons: Object.freeze([]), hasMore: false});
      }
      if (result.rows.length === 0 || result.rows.length > query.limit + 1 ||
          result.rows.some(row => row.outcome !== 'found')) {
        mapOutcome(result.rows[0]?.outcome);
      }
      const items = result.rows.map(row => reason(row, query.scope));
      const principalSocialId = query.scope === 'friends'
        ? socialId(result.rows[0]!.principal_social_id)
        : undefined;
      const internalItems = items.filter(isCareerReasonInternalListItem);
      if (new Set(items.map(item => item.reasonId)).size !== items.length ||
          new Set(internalItems.map(item => item.orderId)).size !== internalItems.length ||
          items.some((item, index) => index > 0 && compareDesc(items[index - 1]!, item) >= 0) ||
          items.some(item => query.scope === 'self' &&
            (!isCareerReasonInternalListItem(item) || !item.author.isViewer)) ||
          items.some(item => query.scope === 'everyone' &&
            (!isCareerReasonInternalListItem(item) || item.deskCycle !== 'current')) ||
          items.some(item => query.scope === 'friends' && !isCareerReasonFriendsListItem(item)) ||
          result.rows.some(row => query.scope === 'friends'
            ? row.principal_social_id !== principalSocialId
            : row.principal_social_id !== null) ||
          query.scope === 'friends' && query.cursor !== null &&
            query.cursor.principalSocialId !== principalSocialId ||
          items.some(item => query.assetId !== null &&
            (item.stock.assetId !== query.assetId || item.stock.variantMint !== query.variantMint)) ||
          items.some(item => query.cursor !== null &&
            (item.savedAt > query.cursor.savedAt ||
              (item.savedAt === query.cursor.savedAt &&
                item.reasonId >= query.cursor.reasonId)))) {
        storageInvalid();
      }
      return Object.freeze({
        reasons: Object.freeze(items.slice(0, query.limit)),
        hasMore: items.length > query.limit,
        ...(principalSocialId === undefined ? {} : {principalSocialId}),
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
            'users', 'product_profiles', 'career_profiles',
            'career_trade_reasons', 'career_reason_privacy',
            'career_reason_privacy_receipts', 'paper_orders', 'paper_accounts',
            'provider_identities', 'invitations', 'social_profiles',
            'social_invitation_create_receipts', 'social_friendships',
            'social_friendship_events', 'social_friendship_receipts',
            'social_blocks', 'social_block_receipts', 'social_reason_reports',
            'social_reason_moderation', 'social_reason_moderation_events',
            'social_rate_windows')
          AND pg_catalog.pg_has_role(current_user, c.relowner, 'MEMBER')) AS unsafe_role`,
      [this.moderationRole]);
    if (result.rows.length !== 1 || result.rows[0]?.unsafe_role !== false) {
      throw new CareerReasonSharingError(
        'CAREER_REASON_SHARING_RUNTIME_ROLE_INVALID',
        'Career reason sharing requires a dedicated runtime role.',
      );
    }
  }

  private async setPrincipal(client: PoolClient, userId: string): Promise<void> {
    const result = await client.query<{scoped_user: unknown}>(
      `SELECT set_config('trimmy.practice_user_id', $1, true) AS scoped_user`,
      [userId],
    );
    if (result.rows.length !== 1 || result.rows[0]?.scoped_user !== userId) storageInvalid();
  }

  private async transaction<T>(
    userId: string,
    readOnly: boolean,
    run: (client: PoolClient) => Promise<T>,
  ): Promise<T> {
    const client = await this.pool.connect();
    let releaseError: Error | undefined;
    try {
      await client.query(readOnly
        ? 'BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY'
        : 'BEGIN');
      await this.assertRuntimeRole(client);
      await this.setPrincipal(client, userId);
      const result = await run(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      try { await client.query('ROLLBACK'); }
      catch { releaseError = new Error('Career reason sharing transaction cleanup failed.'); }
      if (error instanceof CareerReasonSharingError) throw error;
      throw new CareerReasonSharingError(
        'CAREER_REASON_SHARING_STORAGE_INVALID',
        'Career reason sharing storage is invalid.',
      );
    } finally {
      client.release(releaseError);
    }
  }
}
