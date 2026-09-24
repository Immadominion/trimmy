import type {Pool, QueryResultRow} from 'pg';
import {DEFAULT_RELATIONSHIP_MODERATION_ROLE, parseRelationshipModerationRole} from
  './relationship-safety-config.js';

interface ReadinessRow extends QueryResultRow { ready: unknown }

const requiredFunctions = Object.freeze([
  'trimmy.social_invitation_list(uuid,text,text,timestamptz,uuid,integer)',
  'trimmy.social_invitation_create(uuid,uuid,text,timestamptz)',
  'trimmy.social_invitation_sender_action(uuid,uuid,bigint,text,text,text)',
  'trimmy.social_invitation_answer(uuid,uuid,bigint,text,text,text,timestamptz)',
  'trimmy.social_friend_list(uuid,timestamptz,uuid,integer)',
  'trimmy.social_friend_remove(uuid,uuid,uuid,text,bigint)',
  'trimmy.social_block_list(uuid,timestamptz,uuid,integer)',
  'trimmy.social_block_get(uuid,uuid)',
  'trimmy.social_block_put(uuid,uuid,uuid,text,bigint,text)',
  'trimmy.social_reason_report_create(uuid,uuid,text,uuid,text)',
  'trimmy.career_trade_reason_list(uuid,text,text,text,timestamptz,uuid,integer)',
  'trimmy.career_reason_privacy_get(uuid)',
  'trimmy.career_reason_privacy_put(uuid,uuid,text,bigint,text)',
  'trimmy.social_close_current_account(text)',
] as const);

const forbiddenFunctions = Object.freeze([
  'trimmy.practice_current_user()',
  'trimmy.social_x_subject_valid(text)',
  'trimmy.social_rate_take_internal(uuid,text)',
  'trimmy.social_bind_verified_x_identity_internal(uuid,text,text,timestamptz)',
  'trimmy.social_activate_friendship_internal(uuid,uuid,uuid,uuid)',
  'trimmy.social_rate_windows_prune(timestamptz,integer)',
  'trimmy.social_account_close_cleanup_internal(uuid,text)',
  'trimmy.social_reason_moderation_put(uuid,bigint,text,text,text)',
] as const);

const protectedTables = Object.freeze([
  'invitations', 'provider_identities', 'social_profiles',
  'social_invitation_create_receipts', 'social_friendships',
  'social_friendship_events', 'social_friendship_receipts', 'social_blocks',
  'social_block_receipts', 'social_reason_reports', 'social_reason_moderation',
  'social_reason_moderation_events', 'social_rate_windows',
] as const);

/**
 * Live deployment proof for the relationship capability. The feature flag is
 * evaluated separately, so probing can never activate the retained runtime.
 */
export class PostgresRelationshipSafetyReadiness {
  private readonly moderationRole: string;

  constructor(
    private readonly pool: Pick<Pool, 'query'>,
    moderationRole = DEFAULT_RELATIONSHIP_MODERATION_ROLE,
  ) {
    this.moderationRole = parseRelationshipModerationRole(moderationRole);
  }

  async ready(): Promise<boolean> {
    const result = await this.pool.query<ReadinessRow>(`
      WITH required(signature) AS (SELECT unnest($1::text[])),
      forbidden(signature) AS (SELECT unnest($2::text[])),
      protected(name) AS (SELECT unnest($3::text[])),
      moderator AS (
        SELECT oid, rolcanlogin, rolinherit, rolsuper, rolcreatedb,
          rolcreaterole, rolreplication, rolbypassrls
        FROM pg_catalog.pg_roles WHERE rolname = $4
      ), protected_relations AS (
        SELECT c.oid FROM pg_catalog.pg_class c
        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
        JOIN protected p ON p.name = c.relname
        WHERE n.nspname = 'trimmy'
      )
      SELECT
        NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles r
          WHERE (r.rolsuper OR r.rolbypassrls)
            AND pg_catalog.pg_has_role(current_user, r.oid, 'MEMBER'))
        AND (SELECT count(*) = cardinality($3::text[]) FROM protected_relations)
        AND (SELECT bool_and(pg_catalog.to_regprocedure(signature) IS NOT NULL
          AND coalesce(pg_catalog.has_function_privilege(
            current_user, pg_catalog.to_regprocedure(signature), 'EXECUTE'), false))
          FROM required)
        AND (SELECT bool_and(pg_catalog.to_regprocedure(signature) IS NULL
          OR NOT coalesce(pg_catalog.has_function_privilege(
            current_user, pg_catalog.to_regprocedure(signature), 'EXECUTE'), false))
          FROM forbidden)
        AND NOT EXISTS (SELECT 1 FROM protected_relations r WHERE
          pg_catalog.has_table_privilege(current_user, r.oid, 'SELECT')
          OR pg_catalog.has_table_privilege(current_user, r.oid, 'INSERT')
          OR pg_catalog.has_table_privilege(current_user, r.oid, 'UPDATE')
          OR pg_catalog.has_table_privilege(current_user, r.oid, 'DELETE')
          OR pg_catalog.has_table_privilege(current_user, r.oid, 'TRUNCATE')
          OR pg_catalog.has_table_privilege(current_user, r.oid, 'REFERENCES')
          OR pg_catalog.has_table_privilege(current_user, r.oid, 'TRIGGER')
          OR pg_catalog.has_any_column_privilege(current_user, r.oid, 'SELECT')
          OR pg_catalog.has_any_column_privilege(current_user, r.oid, 'INSERT')
          OR pg_catalog.has_any_column_privilege(current_user, r.oid, 'UPDATE')
          OR pg_catalog.has_any_column_privilege(current_user, r.oid, 'REFERENCES'))
        AND (SELECT count(*) = 1 AND bool_and(
          NOT rolcanlogin AND NOT rolinherit AND NOT rolsuper AND NOT rolcreatedb
          AND NOT rolcreaterole AND NOT rolreplication AND NOT rolbypassrls
          AND NOT pg_catalog.pg_has_role(current_user, oid, 'MEMBER')) FROM moderator)
        AND pg_catalog.has_schema_privilege($4, 'trimmy', 'USAGE')
        AND NOT pg_catalog.has_schema_privilege($4, 'trimmy', 'CREATE')
        AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c
          JOIN moderator m ON m.oid = c.relowner)
        AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p
          JOIN moderator m ON m.oid = p.proowner)
        AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_namespace n
          JOIN moderator m ON m.oid = n.nspowner)
        AND NOT EXISTS (SELECT 1 FROM protected_relations r
          JOIN moderator m ON true WHERE
            pg_catalog.has_table_privilege(m.oid, r.oid, 'SELECT')
            OR pg_catalog.has_table_privilege(m.oid, r.oid, 'INSERT')
            OR pg_catalog.has_table_privilege(m.oid, r.oid, 'UPDATE')
            OR pg_catalog.has_table_privilege(m.oid, r.oid, 'DELETE')
            OR pg_catalog.has_table_privilege(m.oid, r.oid, 'TRUNCATE')
            OR pg_catalog.has_table_privilege(m.oid, r.oid, 'REFERENCES')
            OR pg_catalog.has_table_privilege(m.oid, r.oid, 'TRIGGER')
            OR pg_catalog.has_any_column_privilege(m.oid, r.oid, 'SELECT')
            OR pg_catalog.has_any_column_privilege(m.oid, r.oid, 'INSERT')
            OR pg_catalog.has_any_column_privilege(m.oid, r.oid, 'UPDATE')
            OR pg_catalog.has_any_column_privilege(m.oid, r.oid, 'REFERENCES'))
        AND (SELECT count(*) = 1 FROM pg_catalog.pg_proc p
          JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
          JOIN moderator m ON true
          WHERE n.nspname = 'trimmy'
            AND pg_catalog.has_function_privilege(m.oid, p.oid, 'EXECUTE'))
        AND pg_catalog.has_function_privilege(
          $4, 'trimmy.social_reason_moderation_put(uuid,bigint,text,text,text)', 'EXECUTE')
        AS ready`,
      [requiredFunctions, forbiddenFunctions, protectedTables, this.moderationRole],
    );
    return result.rows.length === 1 && result.rows[0]?.ready === true;
  }
}
