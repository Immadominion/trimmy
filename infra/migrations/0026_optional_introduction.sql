-- 0026: optional profile preferences and an explicit short introduction.
-- Skipping records a navigation acknowledgement only. Completing requires an
-- immutable confirmed buy. Neither action creates paper or Career evidence.
BEGIN;

ALTER TABLE trimmy.product_profiles
  ALTER COLUMN goal DROP NOT NULL,
  ALTER COLUMN knowledge DROP NOT NULL,
  ALTER COLUMN persona DROP NOT NULL,
  ALTER COLUMN daily_goal DROP NOT NULL,
  ALTER COLUMN handle DROP NOT NULL;
ALTER TABLE trimmy.product_profile_mutation_receipts
  ALTER COLUMN goal DROP NOT NULL,
  ALTER COLUMN knowledge DROP NOT NULL,
  ALTER COLUMN persona DROP NOT NULL,
  ALTER COLUMN daily_goal DROP NOT NULL,
  ALTER COLUMN handle DROP NOT NULL;

-- Keep all existing enum, handle, identity, uniqueness and revision checks.
-- Replace only the two checks that enumerate launch actions/transitions.
DO $$
DECLARE check_row record;
BEGIN
  FOR check_row IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'trimmy.product_launch_action_receipts'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) LIKE '%paper-trade-confirmed%'
  LOOP
    EXECUTE format('ALTER TABLE trimmy.product_launch_action_receipts DROP CONSTRAINT %I', check_row.conname);
  END LOOP;
END;
$$;
ALTER TABLE trimmy.product_launch_action_receipts
  ADD CONSTRAINT product_launch_action_known CHECK (action IN (
    'paper-trade-confirmed', 'first-position-collected', 'day-one-seen',
    'save-desk-later', 'save-desk-saved', 'introduction-skipped', 'introduction-completed')),
  ADD CONSTRAINT product_launch_action_transition CHECK (
    (action = 'paper-trade-confirmed'
      AND from_checkpoint = 'first-trade' AND launch_checkpoint = 'first-position')
    OR (action = 'first-position-collected'
      AND from_checkpoint = 'first-position' AND launch_checkpoint = 'streak')
    OR (action = 'day-one-seen'
      AND from_checkpoint = 'streak' AND launch_checkpoint = 'save-desk')
    OR (action IN ('save-desk-later', 'save-desk-saved')
      AND from_checkpoint = 'save-desk' AND launch_checkpoint = 'app')
    OR (action IN ('introduction-skipped', 'introduction-completed')
      AND from_checkpoint IN ('first-trade', 'first-position', 'streak', 'save-desk')
      AND launch_checkpoint = 'app')
  );

-- The existing deferred profile/action receipt pair remains mandatory for
-- every checkpoint change, including the newly allowed direct app transition.
CREATE OR REPLACE FUNCTION trimmy.protect_product_profile() RETURNS trigger
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
    IF new_rank < old_rank
        OR (new_rank > old_rank + 1 AND NEW.launch_checkpoint <> 'app') THEN
      RAISE EXCEPTION 'Product launch checkpoint must advance one step or finish introduction'
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
CREATE OR REPLACE FUNCTION trimmy.check_product_launch_action_pair() RETURNS trigger
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
  IF NEW.action IN ('paper-trade-confirmed', 'first-position-collected', 'introduction-completed')
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
      OR (selected_goal IS NOT NULL AND selected_goal NOT IN ('learn', 'practice', 'trade', 'beat-friends'))
      OR (selected_knowledge IS NOT NULL
        AND selected_knowledge NOT IN ('nothing', 'basics', 'practice', 'traded-before', 'daily-trader'))
      OR (selected_persona IS NOT NULL AND selected_persona NOT IN ('wolf', 'oracle', 'shark'))
      OR (selected_daily_goal IS NOT NULL
        AND selected_daily_goal NOT IN ('show-up', 'one-mission', 'three-missions'))
      OR (selected_handle IS NOT NULL
        AND (selected_handle COLLATE "C") !~ '^[a-z][a-z0-9_]{2,17}$')
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

CREATE OR REPLACE FUNCTION trimmy.product_launch_advance(
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
DECLARE previous_checkpoint text; next_checkpoint text; next_revision bigint; observed_at timestamptz;
BEGIN
  IF selected_user IS NULL OR selected_mutation IS NULL
      OR selected_hash IS NULL OR selected_hash !~ '^[a-f0-9]{64}$'
      OR selected_base_revision IS NULL OR selected_base_revision < 1
      OR selected_base_revision > 9007199254740991
      OR selected_action IS NULL OR selected_action NOT IN (
        'paper-trade-confirmed', 'first-position-collected', 'day-one-seen',
        'save-desk-later', 'save-desk-saved', 'introduction-skipped', 'introduction-completed') THEN
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

  previous_checkpoint := current_row.launch_checkpoint;
  next_checkpoint := CASE selected_action
    WHEN 'paper-trade-confirmed' THEN 'first-position'
    WHEN 'first-position-collected' THEN 'streak'
    WHEN 'day-one-seen' THEN 'save-desk'
    WHEN 'save-desk-later' THEN 'app'
    WHEN 'save-desk-saved' THEN 'app'
    WHEN 'introduction-skipped' THEN 'app'
    WHEN 'introduction-completed' THEN 'app'
  END;
  IF (selected_action = 'paper-trade-confirmed' AND current_row.launch_checkpoint <> 'first-trade')
      OR (selected_action = 'first-position-collected'
        AND current_row.launch_checkpoint <> 'first-position')
      OR (selected_action = 'day-one-seen' AND current_row.launch_checkpoint <> 'streak')
      OR (selected_action IN ('save-desk-later', 'save-desk-saved')
        AND current_row.launch_checkpoint <> 'save-desk')
      OR (selected_action IN ('introduction-skipped', 'introduction-completed')
        AND current_row.launch_checkpoint = 'app') THEN
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
  IF selected_action IN ('paper-trade-confirmed', 'first-position-collected', 'introduction-completed')
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
    previous_checkpoint,
    next_checkpoint, selected_guest_session, current_row.updated_at);
  RETURN QUERY SELECT 'saved'::text, current_row.revision, current_row.goal, current_row.knowledge,
    current_row.persona, current_row.daily_goal, current_row.handle, current_row.launch_checkpoint,
    current_row.created_at, current_row.updated_at;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.product_launch_advance(uuid, uuid, text, bigint, text, uuid) FROM PUBLIC;

CREATE FUNCTION trimmy.product_profile_has_confirmed_paper_trade(selected_user uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
  SELECT EXISTS (
    SELECT 1 FROM trimmy.users u
    JOIN trimmy.career_first_confirmed_buys b ON b.user_id = u.id
    WHERE u.id = selected_user AND u.status = 'active'
  );
$$;
REVOKE ALL ON FUNCTION trimmy.product_profile_has_confirmed_paper_trade(uuid) FROM PUBLIC;

INSERT INTO trimmy.schema_migrations(version) VALUES ('0026_optional_introduction');
COMMIT;
