-- 0024: server-owned Career reason reads and privacy. Reasons remain immutable
-- history across paper desk resets. Public sharing is opt-in and friendship
-- sharing remains unavailable until a real relationship model exists.
BEGIN;

CREATE TABLE trimmy.career_reason_privacy (
  user_id uuid PRIMARY KEY REFERENCES trimmy.users(id),
  revision bigint NOT NULL CHECK (revision BETWEEN 1 AND 9007199254740991),
  visibility text COLLATE "C" NOT NULL
    CHECK (visibility IN ('friends', 'everyone', 'nobody')),
  configured boolean NOT NULL,
  created_at timestamptz NOT NULL CHECK (isfinite(created_at)),
  updated_at timestamptz NOT NULL
    CHECK (isfinite(updated_at) AND updated_at >= created_at)
);

CREATE TABLE trimmy.career_reason_privacy_receipts (
  user_id uuid NOT NULL REFERENCES trimmy.users(id),
  mutation_id uuid NOT NULL,
  request_hash trimmy.sha256_hex NOT NULL,
  revision bigint NOT NULL CHECK (revision BETWEEN 2 AND 9007199254740991),
  visibility text COLLATE "C" NOT NULL
    CHECK (visibility IN ('friends', 'everyone', 'nobody')),
  configured boolean NOT NULL CHECK (configured),
  created_at timestamptz NOT NULL CHECK (isfinite(created_at)),
  updated_at timestamptz NOT NULL
    CHECK (isfinite(updated_at) AND updated_at > created_at),
  PRIMARY KEY (user_id, mutation_id),
  UNIQUE (user_id, revision)
);

CREATE FUNCTION trimmy.protect_career_reason_privacy() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Career reason privacy cannot be deleted'
      USING ERRCODE = '23514', CONSTRAINT = 'career_reason_privacy_identity';
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.revision <> 1 OR NEW.visibility <> 'nobody' OR NEW.configured
        OR NEW.created_at <> NEW.updated_at THEN
      RAISE EXCEPTION 'Career reason privacy begins private and unconfigured'
        USING ERRCODE = '23514', CONSTRAINT = 'career_reason_privacy_initial_state';
    END IF;
  ELSIF (NEW.user_id, NEW.created_at) IS DISTINCT FROM (OLD.user_id, OLD.created_at)
      OR NEW.revision <> OLD.revision + 1 OR NOT NEW.configured
      OR NEW.updated_at <= OLD.updated_at THEN
    RAISE EXCEPTION 'Career reason privacy revision is invalid'
      USING ERRCODE = '23514', CONSTRAINT = 'career_reason_privacy_revision';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.protect_career_reason_privacy() FROM PUBLIC;
CREATE TRIGGER career_reason_privacy_guard
  BEFORE INSERT OR UPDATE OR DELETE ON trimmy.career_reason_privacy
  FOR EACH ROW EXECUTE FUNCTION trimmy.protect_career_reason_privacy();
CREATE TRIGGER career_reason_privacy_receipts_append_only
  BEFORE UPDATE OR DELETE ON trimmy.career_reason_privacy_receipts
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();

CREATE FUNCTION trimmy.check_career_reason_privacy_receipt_pair() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  IF TG_TABLE_NAME = 'career_reason_privacy' THEN
    IF NEW.configured AND NOT EXISTS (
      SELECT 1 FROM trimmy.career_reason_privacy_receipts r
      WHERE r.user_id = NEW.user_id AND r.revision = NEW.revision
        AND (r.visibility, r.configured, r.created_at, r.updated_at)
            IS NOT DISTINCT FROM
            (NEW.visibility, NEW.configured, NEW.created_at, NEW.updated_at)
    ) THEN
      RAISE EXCEPTION 'Career reason privacy snapshot requires a receipt'
        USING ERRCODE = '23514', CONSTRAINT = 'career_reason_privacy_receipt_pair';
    END IF;
  ELSIF NOT EXISTS (
    SELECT 1 FROM trimmy.career_reason_privacy p
    WHERE p.user_id = NEW.user_id AND p.revision = NEW.revision
      AND (p.visibility, p.configured, p.created_at, p.updated_at)
          IS NOT DISTINCT FROM
          (NEW.visibility, NEW.configured, NEW.created_at, NEW.updated_at)
  ) THEN
    RAISE EXCEPTION 'Career reason privacy receipt requires its snapshot'
      USING ERRCODE = '23514', CONSTRAINT = 'career_reason_privacy_receipt_pair';
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.check_career_reason_privacy_receipt_pair() FROM PUBLIC;
CREATE CONSTRAINT TRIGGER career_reason_privacy_snapshot_receipt_pair
  AFTER INSERT OR UPDATE ON trimmy.career_reason_privacy
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trimmy.check_career_reason_privacy_receipt_pair();
CREATE CONSTRAINT TRIGGER career_reason_privacy_receipt_snapshot_pair
  AFTER INSERT ON trimmy.career_reason_privacy_receipts
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trimmy.check_career_reason_privacy_receipt_pair();

CREATE FUNCTION trimmy.career_default_reason_privacy() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE observed_at timestamptz := date_trunc('milliseconds', clock_timestamp());
BEGIN
  INSERT INTO trimmy.career_reason_privacy(
    user_id, revision, visibility, configured, created_at, updated_at)
  VALUES (NEW.id, 1, 'nobody', false, observed_at, observed_at);
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_default_reason_privacy() FROM PUBLIC;

-- Install the trigger before the set backfill so no account can cross the
-- migration boundary without a conservative privacy row.
CREATE TRIGGER career_default_reason_privacy
  AFTER INSERT ON trimmy.users
  FOR EACH ROW EXECUTE FUNCTION trimmy.career_default_reason_privacy();

INSERT INTO trimmy.career_reason_privacy(
  user_id, revision, visibility, configured, created_at, updated_at)
SELECT u.id, 1, 'nobody', false,
  date_trunc('milliseconds', statement_timestamp()),
  date_trunc('milliseconds', statement_timestamp())
FROM trimmy.users u
ORDER BY u.id;

-- Public reason identity is separate from the paper order identity. The
-- volatile default gives every historical row its own UUID during this table
-- rewrite and every future immutable reason receives one at insert time.
ALTER TABLE trimmy.career_trade_reasons
  ADD COLUMN public_id uuid NOT NULL DEFAULT gen_random_uuid(),
  ADD CONSTRAINT career_trade_reasons_public_id_key UNIQUE (public_id);
CREATE INDEX career_trade_reasons_public_page
  ON trimmy.career_trade_reasons(
    asset_id, variant_mint, saved_at DESC, public_id DESC);
CREATE INDEX career_trade_reasons_self_page
  ON trimmy.career_trade_reasons(user_id, saved_at DESC, public_id DESC);

CREATE FUNCTION trimmy.career_reason_runtime_user() RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE scoped_user uuid;
BEGIN
  BEGIN
    scoped_user := nullif(current_setting('trimmy.practice_user_id', true), '')::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RETURN NULL;
  END;
  RETURN scoped_user;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_reason_runtime_user() FROM PUBLIC;

CREATE FUNCTION trimmy.career_reason_privacy_get(selected_user uuid)
RETURNS TABLE (
  outcome text,
  revision bigint,
  visibility text,
  configured boolean,
  created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE account_status text;
DECLARE current_row trimmy.career_reason_privacy%ROWTYPE;
BEGIN
  IF selected_user IS NULL
      OR trimmy.career_reason_runtime_user() IS DISTINCT FROM selected_user THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::bigint, NULL::text, NULL::boolean,
      NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT u.status INTO account_status FROM trimmy.users u WHERE u.id = selected_user;
  IF account_status IS DISTINCT FROM 'active' THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::bigint, NULL::text,
      NULL::boolean, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT p.* INTO current_row FROM trimmy.career_reason_privacy p
    WHERE p.user_id = selected_user;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'storage_missing'::text, NULL::bigint, NULL::text,
      NULL::boolean, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  RETURN QUERY SELECT 'found'::text, current_row.revision,
    current_row.visibility, current_row.configured,
    current_row.created_at, current_row.updated_at;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_reason_privacy_get(uuid) FROM PUBLIC;

CREATE FUNCTION trimmy.career_reason_privacy_put(
  selected_user uuid,
  selected_mutation uuid,
  selected_hash text,
  selected_base_revision bigint,
  selected_visibility text
) RETURNS TABLE (
  outcome text,
  revision bigint,
  visibility text,
  configured boolean,
  created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE account_status text;
DECLARE current_row trimmy.career_reason_privacy%ROWTYPE;
DECLARE receipt_row trimmy.career_reason_privacy_receipts%ROWTYPE;
DECLARE observed_at timestamptz;
DECLARE next_revision bigint;
BEGIN
  IF selected_user IS NULL OR selected_mutation IS NULL
      OR selected_hash IS NULL OR selected_hash !~ '^[a-f0-9]{64}$'
      OR selected_base_revision IS NULL OR selected_base_revision < 1
      OR selected_base_revision > 9007199254740991
      OR selected_visibility IS NULL
      OR selected_visibility NOT IN ('friends', 'everyone', 'nobody')
      OR trimmy.career_reason_runtime_user() IS DISTINCT FROM selected_user THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::bigint, NULL::text, NULL::boolean,
      NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.career-reason-privacy:' || selected_user::text, 0));

  -- The immutable receipt is checked first for mutation rebinding. An active
  -- account receives its current privacy truth after any later setting change.
  -- A closed account keeps the receipt but exposes no active privacy setting.
  SELECT r.* INTO receipt_row FROM trimmy.career_reason_privacy_receipts r
    WHERE r.user_id = selected_user AND r.mutation_id = selected_mutation;
  IF FOUND THEN
    IF receipt_row.request_hash <> selected_hash THEN
      RETURN QUERY SELECT 'idempotency_conflict'::text, NULL::bigint, NULL::text,
        NULL::boolean, NULL::timestamptz, NULL::timestamptz;
    ELSE
      SELECT u.status INTO account_status FROM trimmy.users u
        WHERE u.id = selected_user FOR UPDATE;
      IF account_status IS DISTINCT FROM 'active' THEN
        RETURN QUERY SELECT 'account_missing'::text, NULL::bigint, NULL::text,
          NULL::boolean, NULL::timestamptz, NULL::timestamptz;
        RETURN;
      END IF;
      SELECT p.* INTO current_row FROM trimmy.career_reason_privacy p
        WHERE p.user_id = selected_user;
      IF NOT FOUND THEN
        RETURN QUERY SELECT 'storage_missing'::text, NULL::bigint, NULL::text,
          NULL::boolean, NULL::timestamptz, NULL::timestamptz;
      ELSE
        RETURN QUERY SELECT 'saved'::text, current_row.revision,
          current_row.visibility, current_row.configured,
          current_row.created_at, current_row.updated_at;
      END IF;
    END IF;
    RETURN;
  END IF;

  SELECT u.status INTO account_status FROM trimmy.users u
    WHERE u.id = selected_user FOR UPDATE;
  IF account_status IS DISTINCT FROM 'active' THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::bigint, NULL::text,
      NULL::boolean, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT p.* INTO current_row FROM trimmy.career_reason_privacy p
    WHERE p.user_id = selected_user FOR UPDATE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'storage_missing'::text, NULL::bigint, NULL::text,
      NULL::boolean, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  IF current_row.revision <> selected_base_revision THEN
    RETURN QUERY SELECT 'revision_conflict'::text, current_row.revision,
      current_row.visibility, current_row.configured,
      current_row.created_at, current_row.updated_at;
    RETURN;
  END IF;
  IF current_row.revision >= 9007199254740991 THEN
    RETURN QUERY SELECT 'revision_exhausted'::text, NULL::bigint, NULL::text,
      NULL::boolean, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;

  next_revision := current_row.revision + 1;
  observed_at := greatest(date_trunc('milliseconds', clock_timestamp()),
    current_row.updated_at + interval '1 millisecond');
  UPDATE trimmy.career_reason_privacy SET
    revision = next_revision,
    visibility = selected_visibility,
    configured = true,
    updated_at = observed_at
  WHERE user_id = selected_user
  RETURNING * INTO current_row;
  INSERT INTO trimmy.career_reason_privacy_receipts(
    user_id, mutation_id, request_hash, revision, visibility, configured,
    created_at, updated_at)
  VALUES (selected_user, selected_mutation, selected_hash, current_row.revision,
    current_row.visibility, current_row.configured,
    current_row.created_at, current_row.updated_at);
  RETURN QUERY SELECT 'saved'::text, current_row.revision,
    current_row.visibility, current_row.configured,
    current_row.created_at, current_row.updated_at;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_reason_privacy_put(
  uuid, uuid, text, bigint, text) FROM PUBLIC;

CREATE FUNCTION trimmy.career_trade_reason_list(
  selected_user uuid,
  selected_scope text,
  selected_asset text,
  selected_mint text,
  selected_cursor_at timestamptz,
  selected_cursor_reason uuid,
  selected_limit integer
) RETURNS TABLE (
  outcome text,
  reason_id uuid,
  order_id uuid,
  author_handle text,
  author_rank_id text,
  asset_id text,
  variant_mint text,
  symbol text,
  note text,
  desk_cycle text,
  saved_at timestamptz,
  is_viewer boolean
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE account_status text;
BEGIN
  IF selected_user IS NULL OR selected_scope IS NULL
      OR selected_scope NOT IN ('self', 'everyone')
      OR selected_limit IS NULL OR selected_limit < 1 OR selected_limit > 50
      OR (selected_asset IS NULL) <> (selected_mint IS NULL)
      OR (selected_scope = 'everyone' AND selected_asset IS NULL)
      OR (selected_cursor_at IS NULL) <> (selected_cursor_reason IS NULL)
      OR selected_cursor_at IS NOT NULL AND NOT isfinite(selected_cursor_at)
      OR selected_asset IS NOT NULL AND (
        length(selected_asset) > 100
        OR selected_asset !~ '^[a-z0-9]+(-[a-z0-9]+)*$')
      OR selected_mint IS NOT NULL AND (
        length(selected_mint) NOT BETWEEN 32 AND 44
        OR selected_mint !~ '^[1-9A-HJ-NP-Za-km-z]+$')
      OR trimmy.career_reason_runtime_user() IS DISTINCT FROM selected_user THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::uuid,
      NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
      NULL::timestamptz, NULL::boolean;
    RETURN;
  END IF;
  SELECT u.status INTO account_status FROM trimmy.users u WHERE u.id = selected_user;
  IF account_status IS DISTINCT FROM 'active' THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::uuid, NULL::uuid,
      NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
      NULL::timestamptz, NULL::boolean;
    RETURN;
  END IF;

  RETURN QUERY
  SELECT 'found'::text, r.public_id, r.order_id, profile.handle, career.rank_id,
    r.asset_id, r.variant_mint::text, orders.symbol, r.note,
    CASE WHEN orders.account_revision > account.last_reset_revision
      THEN 'current'::text ELSE 'historical'::text END,
    r.saved_at, r.user_id = selected_user
  FROM trimmy.career_trade_reasons r
  JOIN trimmy.users author ON author.id = r.user_id AND author.status = 'active'
  JOIN trimmy.product_profiles profile ON profile.user_id = r.user_id
  JOIN trimmy.career_profiles career ON career.user_id = r.user_id
  JOIN trimmy.career_reason_privacy privacy ON privacy.user_id = r.user_id
  JOIN trimmy.paper_orders orders
    ON orders.id = r.order_id AND orders.user_id = r.user_id
  JOIN trimmy.paper_accounts account ON account.user_id = r.user_id
  WHERE CASE selected_scope
      WHEN 'self' THEN r.user_id = selected_user
      ELSE privacy.visibility = 'everyone'
    END
    AND (selected_scope = 'self'
      OR orders.account_revision > account.last_reset_revision)
    AND (selected_asset IS NULL OR
      (r.asset_id = selected_asset AND r.variant_mint::text = selected_mint))
    AND (selected_cursor_at IS NULL OR
      (r.saved_at, r.public_id) < (selected_cursor_at, selected_cursor_reason))
  ORDER BY r.saved_at DESC, r.public_id DESC
  LIMIT selected_limit + 1;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'empty'::text, NULL::uuid, NULL::uuid,
      NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
      NULL::timestamptz, NULL::boolean;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_trade_reason_list(
  uuid, text, text, text, timestamptz, uuid, integer) FROM PUBLIC;

-- Flush the backfill checks before enabling forced row security.
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

ALTER TABLE trimmy.career_reason_privacy ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_reason_privacy FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_reason_privacy_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_reason_privacy_receipts FORCE ROW LEVEL SECURITY;
CREATE POLICY career_reason_privacy_function_authority
  ON trimmy.career_reason_privacy
  USING (current_user = pg_catalog.pg_get_userbyid(
    (SELECT c.relowner FROM pg_catalog.pg_class c
      WHERE c.oid = 'trimmy.career_reason_privacy'::pg_catalog.regclass)))
  WITH CHECK (current_user = pg_catalog.pg_get_userbyid(
    (SELECT c.relowner FROM pg_catalog.pg_class c
      WHERE c.oid = 'trimmy.career_reason_privacy'::pg_catalog.regclass)));
CREATE POLICY career_reason_privacy_receipt_function_authority
  ON trimmy.career_reason_privacy_receipts
  USING (current_user = pg_catalog.pg_get_userbyid(
    (SELECT c.relowner FROM pg_catalog.pg_class c
      WHERE c.oid = 'trimmy.career_reason_privacy'::pg_catalog.regclass)))
  WITH CHECK (current_user = pg_catalog.pg_get_userbyid(
    (SELECT c.relowner FROM pg_catalog.pg_class c
      WHERE c.oid = 'trimmy.career_reason_privacy'::pg_catalog.regclass)));

-- The feed function needs a joined author snapshot and desk-cycle boundary.
-- Each policy is SELECT-only and admits the same trusted function owner. It
-- creates no direct runtime table capability.
CREATE POLICY career_reason_feed_reason_authority
  ON trimmy.career_trade_reasons FOR SELECT
  USING (current_user = pg_catalog.pg_get_userbyid(
    (SELECT c.relowner FROM pg_catalog.pg_class c
      WHERE c.oid = 'trimmy.career_reason_privacy'::pg_catalog.regclass)));
CREATE POLICY career_reason_feed_profile_authority
  ON trimmy.product_profiles FOR SELECT
  USING (current_user = pg_catalog.pg_get_userbyid(
    (SELECT c.relowner FROM pg_catalog.pg_class c
      WHERE c.oid = 'trimmy.career_reason_privacy'::pg_catalog.regclass)));
CREATE POLICY career_reason_feed_career_authority
  ON trimmy.career_profiles FOR SELECT
  USING (current_user = pg_catalog.pg_get_userbyid(
    (SELECT c.relowner FROM pg_catalog.pg_class c
      WHERE c.oid = 'trimmy.career_reason_privacy'::pg_catalog.regclass)));
CREATE POLICY career_reason_feed_order_authority
  ON trimmy.paper_orders FOR SELECT
  USING (current_user = pg_catalog.pg_get_userbyid(
    (SELECT c.relowner FROM pg_catalog.pg_class c
      WHERE c.oid = 'trimmy.career_reason_privacy'::pg_catalog.regclass)));
CREATE POLICY career_reason_feed_account_authority
  ON trimmy.paper_accounts FOR SELECT
  USING (current_user = pg_catalog.pg_get_userbyid(
    (SELECT c.relowner FROM pg_catalog.pg_class c
      WHERE c.oid = 'trimmy.career_reason_privacy'::pg_catalog.regclass)));
REVOKE ALL ON TABLE trimmy.career_reason_privacy,
  trimmy.career_reason_privacy_receipts FROM PUBLIC;

INSERT INTO trimmy.schema_migrations(version)
VALUES ('0024_career_reason_sharing');
COMMIT;
