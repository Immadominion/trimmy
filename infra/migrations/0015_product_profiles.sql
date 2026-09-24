-- 0015: server-owned onboarding profile and first-use launch checkpoint.
-- The record belongs to the same users UUID used by guest paper trading, so a
-- guest claim preserves it without copying or rebinding any product data.
BEGIN;

CREATE FUNCTION trimmy.product_checkpoint_rank(selected text) RETURNS smallint
LANGUAGE sql IMMUTABLE STRICT
SET search_path = pg_catalog, trimmy AS $$
  SELECT CASE selected
    WHEN 'first-trade' THEN 1
    WHEN 'first-position' THEN 2
    WHEN 'streak' THEN 3
    WHEN 'save-desk' THEN 4
    WHEN 'app' THEN 5
    ELSE 0
  END::smallint;
$$;
REVOKE ALL ON FUNCTION trimmy.product_checkpoint_rank(text) FROM PUBLIC;

CREATE TABLE trimmy.product_profiles (
  user_id uuid PRIMARY KEY REFERENCES trimmy.users(id),
  revision bigint NOT NULL CHECK (revision BETWEEN 1 AND 9007199254740991),
  goal text COLLATE "C" NOT NULL CHECK (goal IN ('learn', 'practice', 'trade', 'beat-friends')),
  knowledge text COLLATE "C" NOT NULL
    CHECK (knowledge IN ('nothing', 'basics', 'practice', 'traded-before', 'daily-trader')),
  persona text COLLATE "C" NOT NULL CHECK (persona IN ('wolf', 'oracle', 'shark')),
  daily_goal text COLLATE "C" NOT NULL CHECK (daily_goal IN ('show-up', 'one-mission', 'three-missions')),
  handle text COLLATE "C" NOT NULL UNIQUE CHECK (handle ~ '^[a-z][a-z0-9_]{2,17}$'),
  launch_checkpoint text COLLATE "C" NOT NULL
    CHECK (launch_checkpoint IN ('first-trade', 'first-position', 'streak', 'save-desk', 'app')),
  created_at timestamptz NOT NULL CHECK (isfinite(created_at)),
  updated_at timestamptz NOT NULL CHECK (isfinite(updated_at) AND updated_at >= created_at)
);

CREATE TABLE trimmy.product_profile_mutation_receipts (
  user_id uuid NOT NULL REFERENCES trimmy.users(id),
  mutation_id uuid NOT NULL,
  request_hash trimmy.sha256_hex NOT NULL,
  revision bigint NOT NULL CHECK (revision BETWEEN 1 AND 9007199254740991),
  goal text COLLATE "C" NOT NULL CHECK (goal IN ('learn', 'practice', 'trade', 'beat-friends')),
  knowledge text COLLATE "C" NOT NULL
    CHECK (knowledge IN ('nothing', 'basics', 'practice', 'traded-before', 'daily-trader')),
  persona text COLLATE "C" NOT NULL CHECK (persona IN ('wolf', 'oracle', 'shark')),
  daily_goal text COLLATE "C" NOT NULL CHECK (daily_goal IN ('show-up', 'one-mission', 'three-missions')),
  handle text COLLATE "C" NOT NULL CHECK (handle ~ '^[a-z][a-z0-9_]{2,17}$'),
  launch_checkpoint text COLLATE "C" NOT NULL
    CHECK (launch_checkpoint IN ('first-trade', 'first-position', 'streak', 'save-desk', 'app')),
  created_at timestamptz NOT NULL CHECK (isfinite(created_at)),
  updated_at timestamptz NOT NULL CHECK (isfinite(updated_at) AND updated_at >= created_at),
  PRIMARY KEY (user_id, mutation_id),
  UNIQUE (user_id, revision)
);

CREATE FUNCTION trimmy.protect_product_profile() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE old_rank smallint; new_rank smallint;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Product profile history cannot be deleted' USING ERRCODE = '23514';
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.revision <> 1 OR NEW.launch_checkpoint <> 'first-trade'
        OR NEW.created_at <> NEW.updated_at THEN
      RAISE EXCEPTION 'Product profiles begin at first trade and revision one'
        USING ERRCODE = '23514', CONSTRAINT = 'product_profile_initial_state';
    END IF;
  ELSE
    IF (NEW.user_id, NEW.created_at) IS DISTINCT FROM (OLD.user_id, OLD.created_at) THEN
      RAISE EXCEPTION 'Product profile identity is immutable'
        USING ERRCODE = '23514', CONSTRAINT = 'product_profile_identity';
    END IF;
    old_rank := trimmy.product_checkpoint_rank(OLD.launch_checkpoint);
    new_rank := trimmy.product_checkpoint_rank(NEW.launch_checkpoint);
    IF NEW.revision <> OLD.revision + 1 OR NEW.updated_at <= OLD.updated_at THEN
      RAISE EXCEPTION 'Product profile revision must advance exactly once'
        USING ERRCODE = '23514', CONSTRAINT = 'product_profile_revision';
    END IF;
    IF new_rank < old_rank OR new_rank > old_rank + 1 THEN
      RAISE EXCEPTION 'Product launch checkpoint must advance one step'
        USING ERRCODE = '23514', CONSTRAINT = 'product_profile_checkpoint';
    END IF;
    IF OLD.launch_checkpoint = 'first-trade' AND NEW.launch_checkpoint = 'first-position'
        AND NOT EXISTS (SELECT 1 FROM trimmy.paper_orders o WHERE o.user_id = NEW.user_id) THEN
      RAISE EXCEPTION 'First position requires a committed paper order'
        USING ERRCODE = '23514', CONSTRAINT = 'product_profile_paper_order';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.protect_product_profile() FROM PUBLIC;
CREATE TRIGGER product_profile_guard BEFORE INSERT OR UPDATE OR DELETE ON trimmy.product_profiles
  FOR EACH ROW EXECUTE FUNCTION trimmy.protect_product_profile();
CREATE TRIGGER product_profile_receipt_append_only
  BEFORE UPDATE OR DELETE ON trimmy.product_profile_mutation_receipts
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();

CREATE FUNCTION trimmy.check_product_profile_receipt_pair() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  IF TG_TABLE_NAME = 'product_profiles' THEN
    IF NOT EXISTS (
      SELECT 1 FROM trimmy.product_profile_mutation_receipts r
       WHERE r.user_id = NEW.user_id AND r.revision = NEW.revision
         AND (r.goal, r.knowledge, r.persona, r.daily_goal, r.handle, r.launch_checkpoint,
              r.created_at, r.updated_at)
             IS NOT DISTINCT FROM
             (NEW.goal, NEW.knowledge, NEW.persona, NEW.daily_goal, NEW.handle, NEW.launch_checkpoint,
              NEW.created_at, NEW.updated_at)
    ) THEN
      RAISE EXCEPTION 'Product profile snapshot requires its matching receipt'
        USING ERRCODE = '23514', CONSTRAINT = 'product_profile_receipt_pair';
    END IF;
  ELSE
    IF NOT EXISTS (
      SELECT 1 FROM trimmy.product_profiles p
       WHERE p.user_id = NEW.user_id AND p.revision >= NEW.revision
    ) THEN
      RAISE EXCEPTION 'Product profile receipt requires its account snapshot'
        USING ERRCODE = '23514', CONSTRAINT = 'product_profile_receipt_pair';
    END IF;
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.check_product_profile_receipt_pair() FROM PUBLIC;
CREATE CONSTRAINT TRIGGER product_profile_snapshot_receipt_pair
  AFTER INSERT OR UPDATE ON trimmy.product_profiles DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trimmy.check_product_profile_receipt_pair();
CREATE CONSTRAINT TRIGGER product_profile_receipt_snapshot_pair
  AFTER INSERT ON trimmy.product_profile_mutation_receipts DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trimmy.check_product_profile_receipt_pair();

ALTER TABLE trimmy.product_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.product_profiles FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.product_profile_mutation_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.product_profile_mutation_receipts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE trimmy.product_profiles, trimmy.product_profile_mutation_receipts FROM PUBLIC;

CREATE FUNCTION trimmy.product_profile_get(selected_user uuid)
RETURNS TABLE (
  outcome text, revision bigint, goal text, knowledge text, persona text, daily_goal text,
  handle text, launch_checkpoint text, created_at timestamptz, updated_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE account_status text; current_row trimmy.product_profiles%ROWTYPE;
BEGIN
  IF selected_user IS NULL THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::bigint, NULL::text, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT u.status INTO account_status FROM trimmy.users u WHERE u.id = selected_user;
  IF account_status IS NULL OR account_status = 'closed' THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::bigint, NULL::text, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT p.* INTO current_row FROM trimmy.product_profiles p WHERE p.user_id = selected_user;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'missing'::text, NULL::bigint, NULL::text, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  RETURN QUERY SELECT 'found'::text, current_row.revision, current_row.goal, current_row.knowledge,
    current_row.persona, current_row.daily_goal, current_row.handle, current_row.launch_checkpoint,
    current_row.created_at, current_row.updated_at;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.product_profile_get(uuid) FROM PUBLIC;

CREATE FUNCTION trimmy.product_profile_put(
  selected_user uuid, selected_mutation uuid, selected_hash text, selected_base_revision bigint,
  selected_goal text, selected_knowledge text, selected_persona text, selected_daily_goal text,
  selected_handle text, selected_checkpoint text
) RETURNS TABLE (
  outcome text, revision bigint, goal text, knowledge text, persona text, daily_goal text,
  handle text, launch_checkpoint text, created_at timestamptz, updated_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE account_status text; current_row trimmy.product_profiles%ROWTYPE;
DECLARE receipt_row trimmy.product_profile_mutation_receipts%ROWTYPE;
DECLARE next_revision bigint; observed_at timestamptz;
BEGIN
  IF selected_user IS NULL OR selected_mutation IS NULL
      OR selected_hash IS NULL OR selected_hash !~ '^[a-f0-9]{64}$'
      OR selected_base_revision IS NULL OR selected_base_revision < 0
      OR selected_base_revision > 9007199254740991
      OR selected_goal IS NULL OR selected_goal NOT IN ('learn', 'practice', 'trade', 'beat-friends')
      OR selected_knowledge IS NULL
      OR selected_knowledge NOT IN ('nothing', 'basics', 'practice', 'traded-before', 'daily-trader')
      OR selected_persona IS NULL OR selected_persona NOT IN ('wolf', 'oracle', 'shark')
      OR selected_daily_goal IS NULL
      OR selected_daily_goal NOT IN ('show-up', 'one-mission', 'three-missions')
      OR selected_handle IS NULL OR (selected_handle COLLATE "C") !~ '^[a-z][a-z0-9_]{2,17}$'
      OR selected_checkpoint IS NULL
      OR selected_checkpoint NOT IN ('first-trade', 'first-position', 'streak', 'save-desk', 'app') THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::bigint, NULL::text, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('trimmy.product.profile:' || selected_user::text, 0));
  SELECT u.status INTO account_status FROM trimmy.users u WHERE u.id = selected_user FOR UPDATE;
  IF account_status IS NULL OR account_status = 'closed' THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::bigint, NULL::text, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT r.* INTO receipt_row FROM trimmy.product_profile_mutation_receipts r
    WHERE r.user_id = selected_user AND r.mutation_id = selected_mutation;
  IF FOUND THEN
    IF receipt_row.request_hash <> selected_hash THEN
      RETURN QUERY SELECT 'idempotency_conflict'::text, NULL::bigint, NULL::text, NULL::text, NULL::text,
        NULL::text, NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz;
    ELSE
      RETURN QUERY SELECT 'saved'::text, receipt_row.revision, receipt_row.goal, receipt_row.knowledge,
        receipt_row.persona, receipt_row.daily_goal, receipt_row.handle, receipt_row.launch_checkpoint,
        receipt_row.created_at, receipt_row.updated_at;
    END IF;
    RETURN;
  END IF;
  SELECT p.* INTO current_row FROM trimmy.product_profiles p WHERE p.user_id = selected_user FOR UPDATE;
  IF NOT FOUND THEN
    IF selected_base_revision <> 0 THEN
      RETURN QUERY SELECT 'revision_conflict'::text, NULL::bigint, NULL::text, NULL::text, NULL::text,
        NULL::text, NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz;
      RETURN;
    END IF;
    IF selected_checkpoint <> 'first-trade' THEN
      RETURN QUERY SELECT 'checkpoint_conflict'::text, NULL::bigint, NULL::text, NULL::text, NULL::text,
        NULL::text, NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz;
      RETURN;
    END IF;
    next_revision := 1;
    observed_at := date_trunc('milliseconds', clock_timestamp());
    BEGIN
      INSERT INTO trimmy.product_profiles(
        user_id, revision, goal, knowledge, persona, daily_goal, handle, launch_checkpoint,
        created_at, updated_at)
      VALUES (selected_user, next_revision, selected_goal, selected_knowledge, selected_persona,
        selected_daily_goal, selected_handle, selected_checkpoint, observed_at, observed_at)
      RETURNING * INTO current_row;
    EXCEPTION WHEN unique_violation THEN
      RETURN QUERY SELECT 'handle_taken'::text, NULL::bigint, NULL::text, NULL::text, NULL::text,
        NULL::text, NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz;
      RETURN;
    END;
  ELSE
    IF current_row.revision <> selected_base_revision THEN
      RETURN QUERY SELECT 'revision_conflict'::text, current_row.revision, current_row.goal,
        current_row.knowledge, current_row.persona, current_row.daily_goal, current_row.handle,
        current_row.launch_checkpoint, current_row.created_at, current_row.updated_at;
      RETURN;
    END IF;
    IF current_row.revision >= 9007199254740991 THEN
      RETURN QUERY SELECT 'revision_exhausted'::text, NULL::bigint, NULL::text, NULL::text, NULL::text,
        NULL::text, NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz;
      RETURN;
    END IF;
    IF trimmy.product_checkpoint_rank(selected_checkpoint) < trimmy.product_checkpoint_rank(current_row.launch_checkpoint)
        OR trimmy.product_checkpoint_rank(selected_checkpoint) >
          trimmy.product_checkpoint_rank(current_row.launch_checkpoint) + 1 THEN
      RETURN QUERY SELECT 'checkpoint_conflict'::text, NULL::bigint, NULL::text, NULL::text, NULL::text,
        NULL::text, NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz;
      RETURN;
    END IF;
    IF current_row.launch_checkpoint = 'first-trade' AND selected_checkpoint = 'first-position'
        AND NOT EXISTS (SELECT 1 FROM trimmy.paper_orders o WHERE o.user_id = selected_user) THEN
      RETURN QUERY SELECT 'paper_trade_required'::text, NULL::bigint, NULL::text, NULL::text, NULL::text,
        NULL::text, NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz;
      RETURN;
    END IF;
    next_revision := current_row.revision + 1;
    observed_at := greatest(date_trunc('milliseconds', clock_timestamp()),
      current_row.updated_at + interval '1 millisecond');
    BEGIN
      UPDATE trimmy.product_profiles SET revision = next_revision, goal = selected_goal,
        knowledge = selected_knowledge, persona = selected_persona, daily_goal = selected_daily_goal,
        handle = selected_handle, launch_checkpoint = selected_checkpoint, updated_at = observed_at
      WHERE user_id = selected_user RETURNING * INTO current_row;
    EXCEPTION WHEN unique_violation THEN
      RETURN QUERY SELECT 'handle_taken'::text, NULL::bigint, NULL::text, NULL::text, NULL::text,
        NULL::text, NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz;
      RETURN;
    END;
  END IF;
  INSERT INTO trimmy.product_profile_mutation_receipts(
    user_id, mutation_id, request_hash, revision, goal, knowledge, persona, daily_goal, handle,
    launch_checkpoint, created_at, updated_at)
  VALUES (selected_user, selected_mutation, selected_hash, current_row.revision, current_row.goal,
    current_row.knowledge, current_row.persona, current_row.daily_goal, current_row.handle,
    current_row.launch_checkpoint, current_row.created_at, current_row.updated_at);
  RETURN QUERY SELECT 'saved'::text, current_row.revision, current_row.goal, current_row.knowledge,
    current_row.persona, current_row.daily_goal, current_row.handle, current_row.launch_checkpoint,
    current_row.created_at, current_row.updated_at;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.product_profile_put(
  uuid, uuid, text, bigint, text, text, text, text, text, text) FROM PUBLIC;

-- Guest credentials gain only product-profile read and write scopes. They still
-- have no authority over wallets, money, provider identities or other routes.
ALTER TABLE trimmy.guest_rate_windows DROP CONSTRAINT guest_rate_windows_scope_check;
ALTER TABLE trimmy.guest_rate_windows ADD CONSTRAINT guest_rate_windows_scope_check
  CHECK (scope IN ('paper_read', 'paper_preview', 'paper_commit', 'refresh', 'claim',
    'profile_read', 'profile_write'));

CREATE OR REPLACE FUNCTION trimmy.guest_take_rate(
  selected_session uuid,
  selected_scope text,
  observed_at timestamptz
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE window_seconds integer; request_limit integer; window_start timestamptz; observed_count integer;
BEGIN
  IF selected_scope = 'paper_read' THEN window_seconds := 60; request_limit := 60;
  ELSIF selected_scope = 'paper_preview' THEN window_seconds := 600; request_limit := 20;
  ELSIF selected_scope = 'paper_commit' THEN window_seconds := 600; request_limit := 20;
  ELSIF selected_scope = 'profile_read' THEN window_seconds := 60; request_limit := 60;
  ELSIF selected_scope = 'profile_write' THEN window_seconds := 600; request_limit := 20;
  ELSIF selected_scope = 'refresh' THEN window_seconds := 3600; request_limit := 6;
  ELSIF selected_scope = 'claim' THEN window_seconds := 3600; request_limit := 6;
  ELSE RAISE EXCEPTION 'Guest rate scope is invalid' USING ERRCODE = '22023';
  END IF;
  IF selected_session IS NULL OR observed_at IS NULL OR NOT isfinite(observed_at) THEN
    RAISE EXCEPTION 'Guest rate input is invalid' USING ERRCODE = '22023';
  END IF;
  window_start := to_timestamp(floor(extract(epoch FROM observed_at) / window_seconds) * window_seconds);
  INSERT INTO trimmy.guest_rate_windows(guest_session_id, scope, window_started_at, request_count)
    VALUES (selected_session, selected_scope, window_start, 1)
    ON CONFLICT (guest_session_id, scope, window_started_at)
    DO UPDATE SET request_count = trimmy.guest_rate_windows.request_count + 1
    RETURNING request_count INTO observed_count;
  RETURN observed_count <= request_limit;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.guest_take_rate(uuid, text, timestamptz) FROM PUBLIC;

CREATE OR REPLACE FUNCTION trimmy.guest_authorize(selected_hash text, selected_scope text)
RETURNS TABLE (outcome text, user_id uuid, guest_id uuid, expires_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE session_row trimmy.guest_sessions%ROWTYPE; account_status text;
DECLARE observed_at timestamptz := clock_timestamp();
BEGIN
  IF selected_hash IS NULL OR selected_hash !~ '^[a-f0-9]{64}$'
      OR selected_scope NOT IN ('paper_read', 'paper_preview', 'paper_commit', 'profile_read', 'profile_write') THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::uuid, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT s.* INTO session_row FROM trimmy.guest_sessions s
    WHERE s.credential_hash = selected_hash FOR UPDATE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::uuid, NULL::timestamptz;
    RETURN;
  END IF;
  IF session_row.state <> 'active' THEN
    RETURN QUERY SELECT 'revoked'::text, NULL::uuid, session_row.id, session_row.expires_at;
    RETURN;
  END IF;
  IF observed_at >= session_row.expires_at OR observed_at >= session_row.hard_expires_at THEN
    UPDATE trimmy.guest_sessions SET state = 'revoked', revoked_at = observed_at,
      last_seen_at = greatest(last_seen_at, observed_at) WHERE id = session_row.id;
    RETURN QUERY SELECT 'expired'::text, NULL::uuid, session_row.id, session_row.expires_at;
    RETURN;
  END IF;
  SELECT u.status INTO account_status FROM trimmy.users u WHERE u.id = session_row.user_id FOR UPDATE;
  IF account_status IS DISTINCT FROM 'active' THEN
    RETURN QUERY SELECT 'unavailable'::text, NULL::uuid, session_row.id, session_row.expires_at;
    RETURN;
  END IF;
  IF NOT trimmy.guest_take_rate(session_row.id, selected_scope, observed_at) THEN
    RETURN QUERY SELECT 'rate_limited'::text, NULL::uuid, session_row.id, session_row.expires_at;
    RETURN;
  END IF;
  UPDATE trimmy.guest_sessions SET last_seen_at = greatest(last_seen_at, observed_at)
    WHERE id = session_row.id;
  RETURN QUERY SELECT 'authorized'::text, session_row.user_id, session_row.id, session_row.expires_at;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.guest_authorize(text, text) FROM PUBLIC;

INSERT INTO trimmy.schema_migrations(version) VALUES ('0015_product_profiles');
COMMIT;
