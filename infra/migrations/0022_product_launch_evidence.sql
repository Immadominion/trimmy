-- 0022: explicit, evidence-gated actions for the first-use launch sequence.
-- Existing checkpoints remain the resume contract. New clients can advance
-- them only through a narrowly typed action whose eligibility is rechecked in
-- PostgreSQL. Screen acknowledgements remain acknowledgements; immutable paper,
-- Career, guest-session and saved-identity facts determine when they are valid.
BEGIN;

CREATE TABLE trimmy.product_launch_action_receipts (
  user_id uuid NOT NULL REFERENCES trimmy.users(id),
  mutation_id uuid NOT NULL,
  request_hash trimmy.sha256_hex NOT NULL,
  base_revision bigint NOT NULL CHECK (base_revision BETWEEN 1 AND 9007199254740990),
  revision bigint NOT NULL CHECK (revision BETWEEN 2 AND 9007199254740991),
  action text COLLATE "C" NOT NULL CHECK (action IN (
    'paper-trade-confirmed', 'first-position-collected', 'day-one-seen',
    'save-desk-later', 'save-desk-saved')),
  from_checkpoint text COLLATE "C" NOT NULL CHECK (from_checkpoint IN (
    'first-trade', 'first-position', 'streak', 'save-desk')),
  launch_checkpoint text COLLATE "C" NOT NULL CHECK (launch_checkpoint IN (
    'first-position', 'streak', 'save-desk', 'app')),
  guest_session_id uuid REFERENCES trimmy.guest_sessions(id),
  occurred_at timestamptz NOT NULL CHECK (isfinite(occurred_at)),
  PRIMARY KEY (user_id, mutation_id),
  UNIQUE (user_id, revision),
  FOREIGN KEY (user_id, mutation_id)
    REFERENCES trimmy.product_profile_mutation_receipts(user_id, mutation_id)
    DEFERRABLE INITIALLY DEFERRED,
  FOREIGN KEY (user_id, revision)
    REFERENCES trimmy.product_profile_mutation_receipts(user_id, revision)
    DEFERRABLE INITIALLY DEFERRED,
  CHECK (revision = base_revision + 1),
  CHECK (
    (action = 'paper-trade-confirmed'
      AND from_checkpoint = 'first-trade' AND launch_checkpoint = 'first-position')
    OR (action = 'first-position-collected'
      AND from_checkpoint = 'first-position' AND launch_checkpoint = 'streak')
    OR (action = 'day-one-seen'
      AND from_checkpoint = 'streak' AND launch_checkpoint = 'save-desk')
    OR (action IN ('save-desk-later', 'save-desk-saved')
      AND from_checkpoint = 'save-desk' AND launch_checkpoint = 'app')
  ),
  CHECK (action <> 'save-desk-later' OR guest_session_id IS NOT NULL),
  CHECK (action <> 'save-desk-saved' OR guest_session_id IS NULL)
);

CREATE TRIGGER product_launch_action_receipt_append_only
  BEFORE UPDATE OR DELETE ON trimmy.product_launch_action_receipts
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();

ALTER TABLE trimmy.product_launch_action_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.product_launch_action_receipts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE trimmy.product_launch_action_receipts FROM PUBLIC;

-- Every new checkpoint transition must have both the existing immutable
-- profile snapshot receipt and the explicit action receipt introduced here.
-- Historical rows are untouched because their already-committed updates do not
-- fire this replacement constraint function.
CREATE OR REPLACE FUNCTION trimmy.check_product_profile_receipt_pair() RETURNS trigger
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
    IF TG_OP = 'UPDATE' AND NEW.launch_checkpoint IS DISTINCT FROM OLD.launch_checkpoint
        AND NOT EXISTS (
          SELECT 1 FROM trimmy.product_launch_action_receipts a
          WHERE a.user_id = NEW.user_id AND a.revision = NEW.revision
            AND a.base_revision = OLD.revision
            AND a.from_checkpoint = OLD.launch_checkpoint
            AND a.launch_checkpoint = NEW.launch_checkpoint
            AND a.occurred_at = NEW.updated_at
        ) THEN
      RAISE EXCEPTION 'Product checkpoint transition requires its launch action receipt'
        USING ERRCODE = '23514', CONSTRAINT = 'product_launch_action_pair';
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

CREATE FUNCTION trimmy.check_product_launch_action_pair() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM trimmy.product_profile_mutation_receipts r
    WHERE r.user_id = NEW.user_id AND r.mutation_id = NEW.mutation_id
      AND r.request_hash = NEW.request_hash AND r.revision = NEW.revision
      AND r.launch_checkpoint = NEW.launch_checkpoint AND r.updated_at = NEW.occurred_at
  ) THEN
    RAISE EXCEPTION 'Product launch action requires its exact profile receipt'
      USING ERRCODE = '23514', CONSTRAINT = 'product_launch_action_pair';
  END IF;
  IF NEW.guest_session_id IS NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM trimmy.practice_auth_identities i WHERE i.user_id = NEW.user_id
    ) THEN
      RAISE EXCEPTION 'Account launch action requires a saved identity'
        USING ERRCODE = '23514', CONSTRAINT = 'product_launch_principal';
    END IF;
  ELSE
    IF NOT EXISTS (
      SELECT 1 FROM trimmy.guest_sessions s
      WHERE s.id = NEW.guest_session_id AND s.user_id = NEW.user_id AND s.state = 'active'
        AND NEW.occurred_at < s.expires_at AND NEW.occurred_at < s.hard_expires_at
    ) THEN
      RAISE EXCEPTION 'Guest launch action requires its active guest session'
        USING ERRCODE = '23514', CONSTRAINT = 'product_launch_principal';
    END IF;
  END IF;
  IF NEW.action IN ('paper-trade-confirmed', 'first-position-collected')
      AND NOT EXISTS (
        SELECT 1 FROM trimmy.career_first_confirmed_buys b WHERE b.user_id = NEW.user_id
      ) THEN
    RAISE EXCEPTION 'Launch action requires an immutable first confirmed buy'
      USING ERRCODE = '23514', CONSTRAINT = 'product_launch_evidence';
  END IF;
  IF NEW.action IN ('first-position-collected', 'day-one-seen',
      'save-desk-later', 'save-desk-saved')
      AND NOT EXISTS (
        SELECT 1 FROM trimmy.career_starts s
        JOIN trimmy.career_profiles p ON p.user_id = s.user_id
        WHERE s.user_id = NEW.user_id AND p.streak_days >= 1
      ) THEN
    RAISE EXCEPTION 'Launch action requires immutable Career start evidence'
      USING ERRCODE = '23514', CONSTRAINT = 'product_launch_evidence';
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.check_product_launch_action_pair() FROM PUBLIC;
CREATE CONSTRAINT TRIGGER product_launch_action_profile_pair
  AFTER INSERT ON trimmy.product_launch_action_receipts DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trimmy.check_product_launch_action_pair();

-- The profile endpoint continues to create and edit onboarding state and still
-- replays every historical mutation exactly. It can no longer author a new
-- checkpoint transition; only product_launch_advance can do that.
CREATE OR REPLACE FUNCTION trimmy.product_profile_put(
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
    IF selected_checkpoint <> current_row.launch_checkpoint THEN
      RETURN QUERY SELECT 'checkpoint_conflict'::text, NULL::bigint, NULL::text, NULL::text, NULL::text,
        NULL::text, NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz;
      RETURN;
    END IF;
    next_revision := current_row.revision + 1;
    observed_at := greatest(date_trunc('milliseconds', clock_timestamp()),
      current_row.updated_at + interval '1 millisecond');
    BEGIN
      UPDATE trimmy.product_profiles SET revision = next_revision, goal = selected_goal,
        knowledge = selected_knowledge, persona = selected_persona, daily_goal = selected_daily_goal,
        handle = selected_handle, updated_at = observed_at
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

CREATE FUNCTION trimmy.product_launch_advance(
  selected_user uuid, selected_mutation uuid, selected_hash text, selected_base_revision bigint,
  selected_action text, selected_guest_session uuid
) RETURNS TABLE (
  outcome text, revision bigint, goal text, knowledge text, persona text, daily_goal text,
  handle text, launch_checkpoint text, created_at timestamptz, updated_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE account_status text; current_row trimmy.product_profiles%ROWTYPE;
DECLARE receipt_row trimmy.product_profile_mutation_receipts%ROWTYPE;
DECLARE action_row trimmy.product_launch_action_receipts%ROWTYPE;
DECLARE guest_row trimmy.guest_sessions%ROWTYPE;
DECLARE next_checkpoint text; next_revision bigint; observed_at timestamptz;
BEGIN
  IF selected_user IS NULL OR selected_mutation IS NULL
      OR selected_hash IS NULL OR selected_hash !~ '^[a-f0-9]{64}$'
      OR selected_base_revision IS NULL OR selected_base_revision < 1
      OR selected_base_revision > 9007199254740991
      OR selected_action IS NULL OR selected_action NOT IN (
        'paper-trade-confirmed', 'first-position-collected', 'day-one-seen',
        'save-desk-later', 'save-desk-saved') THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::bigint, NULL::text, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('trimmy.product.profile:' || selected_user::text, 0));

  IF selected_guest_session IS NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM trimmy.practice_auth_identities i WHERE i.user_id = selected_user
    ) THEN
      RETURN QUERY SELECT 'principal_conflict'::text, NULL::bigint, NULL::text, NULL::text,
        NULL::text, NULL::text, NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz;
      RETURN;
    END IF;
  ELSE
    SELECT s.* INTO guest_row FROM trimmy.guest_sessions s
      WHERE s.id = selected_guest_session AND s.user_id = selected_user FOR UPDATE;
    IF NOT FOUND THEN
      RETURN QUERY SELECT 'principal_conflict'::text, NULL::bigint, NULL::text, NULL::text,
        NULL::text, NULL::text, NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz;
      RETURN;
    END IF;
  END IF;
  SELECT u.status INTO account_status FROM trimmy.users u WHERE u.id = selected_user FOR UPDATE;
  -- The timestamp belongs after every principal lock. A request queued behind
  -- an account operation must not reuse the pre-wait time to admit an expired
  -- guest session.
  observed_at := date_trunc('milliseconds', clock_timestamp());
  IF selected_guest_session IS NOT NULL
      AND (guest_row.state <> 'active' OR observed_at >= guest_row.expires_at
        OR observed_at >= guest_row.hard_expires_at) THEN
    RETURN QUERY SELECT 'principal_conflict'::text, NULL::bigint, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  IF account_status IS DISTINCT FROM 'active' THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::bigint, NULL::text, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT a.* INTO action_row FROM trimmy.product_launch_action_receipts a
    WHERE a.user_id = selected_user AND a.mutation_id = selected_mutation;
  IF FOUND THEN
    IF action_row.request_hash <> selected_hash THEN
      RETURN QUERY SELECT 'idempotency_conflict'::text, NULL::bigint, NULL::text, NULL::text,
        NULL::text, NULL::text, NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz;
      RETURN;
    END IF;
    SELECT r.* INTO receipt_row FROM trimmy.product_profile_mutation_receipts r
      WHERE r.user_id = selected_user AND r.mutation_id = selected_mutation;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Product launch receipt lost its profile receipt'
        USING ERRCODE = '23514', CONSTRAINT = 'product_launch_action_pair';
    END IF;
    RETURN QUERY SELECT 'saved'::text, receipt_row.revision, receipt_row.goal, receipt_row.knowledge,
      receipt_row.persona, receipt_row.daily_goal, receipt_row.handle, receipt_row.launch_checkpoint,
      receipt_row.created_at, receipt_row.updated_at;
    RETURN;
  END IF;
  IF EXISTS (
    SELECT 1 FROM trimmy.product_profile_mutation_receipts r
    WHERE r.user_id = selected_user AND r.mutation_id = selected_mutation
  ) THEN
    RETURN QUERY SELECT 'idempotency_conflict'::text, NULL::bigint, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;

  SELECT p.* INTO current_row FROM trimmy.product_profiles p
    WHERE p.user_id = selected_user FOR UPDATE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'profile_missing'::text, NULL::bigint, NULL::text, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
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

  next_checkpoint := CASE selected_action
    WHEN 'paper-trade-confirmed' THEN 'first-position'
    WHEN 'first-position-collected' THEN 'streak'
    WHEN 'day-one-seen' THEN 'save-desk'
    WHEN 'save-desk-later' THEN 'app'
    WHEN 'save-desk-saved' THEN 'app'
  END;
  IF (selected_action = 'paper-trade-confirmed' AND current_row.launch_checkpoint <> 'first-trade')
      OR (selected_action = 'first-position-collected'
        AND current_row.launch_checkpoint <> 'first-position')
      OR (selected_action = 'day-one-seen' AND current_row.launch_checkpoint <> 'streak')
      OR (selected_action IN ('save-desk-later', 'save-desk-saved')
        AND current_row.launch_checkpoint <> 'save-desk') THEN
    RETURN QUERY SELECT 'checkpoint_conflict'::text, NULL::bigint, NULL::text, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  IF (selected_action = 'save-desk-later' AND selected_guest_session IS NULL)
      OR (selected_action = 'save-desk-saved' AND selected_guest_session IS NOT NULL) THEN
    RETURN QUERY SELECT 'principal_conflict'::text, NULL::bigint, NULL::text, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  IF selected_action IN ('paper-trade-confirmed', 'first-position-collected')
      AND NOT EXISTS (
        SELECT 1 FROM trimmy.career_first_confirmed_buys b WHERE b.user_id = selected_user
      ) THEN
    RETURN QUERY SELECT 'evidence_required'::text, NULL::bigint, NULL::text, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  IF selected_action IN ('first-position-collected', 'day-one-seen',
      'save-desk-later', 'save-desk-saved')
      AND NOT EXISTS (
        SELECT 1 FROM trimmy.career_starts s
        JOIN trimmy.career_profiles p ON p.user_id = s.user_id
        WHERE s.user_id = selected_user AND p.streak_days >= 1
      ) THEN
    RETURN QUERY SELECT 'evidence_required'::text, NULL::bigint, NULL::text, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;

  next_revision := current_row.revision + 1;
  observed_at := greatest(observed_at, current_row.updated_at + interval '1 millisecond');
  UPDATE trimmy.product_profiles SET revision = next_revision,
    launch_checkpoint = next_checkpoint, updated_at = observed_at
  WHERE user_id = selected_user RETURNING * INTO current_row;
  INSERT INTO trimmy.product_profile_mutation_receipts(
    user_id, mutation_id, request_hash, revision, goal, knowledge, persona, daily_goal, handle,
    launch_checkpoint, created_at, updated_at)
  VALUES (selected_user, selected_mutation, selected_hash, current_row.revision, current_row.goal,
    current_row.knowledge, current_row.persona, current_row.daily_goal, current_row.handle,
    current_row.launch_checkpoint, current_row.created_at, current_row.updated_at);
  INSERT INTO trimmy.product_launch_action_receipts(
    user_id, mutation_id, request_hash, base_revision, revision, action, from_checkpoint,
    launch_checkpoint, guest_session_id, occurred_at)
  VALUES (selected_user, selected_mutation, selected_hash, selected_base_revision, next_revision,
    selected_action,
    CASE selected_action
      WHEN 'paper-trade-confirmed' THEN 'first-trade'
      WHEN 'first-position-collected' THEN 'first-position'
      WHEN 'day-one-seen' THEN 'streak'
      ELSE 'save-desk'
    END,
    next_checkpoint, selected_guest_session, current_row.updated_at);
  RETURN QUERY SELECT 'saved'::text, current_row.revision, current_row.goal, current_row.knowledge,
    current_row.persona, current_row.daily_goal, current_row.handle, current_row.launch_checkpoint,
    current_row.created_at, current_row.updated_at;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.product_launch_advance(uuid, uuid, text, bigint, text, uuid) FROM PUBLIC;

-- Deployment grants this function, and no table access, to the serving role:
--   GRANT EXECUTE ON FUNCTION trimmy.product_launch_advance(
--     uuid, uuid, text, bigint, text, uuid) TO trimmy_practice_runtime;

INSERT INTO trimmy.schema_migrations(version) VALUES ('0022_product_launch_evidence');
COMMIT;
