-- 0018: immutable Career start and first-buy facts, two evidence-backed action
-- missions, and an idempotent rank-promotion write. Money activity cannot
-- complete a mission or award Trims. The paper ledger remains fixed at 10,000;
-- rank progression does not resize or fund it in this migration.
BEGIN;

ALTER TABLE trimmy.career_trim_ledger
  DROP CONSTRAINT career_trim_ledger_entry_kind_check,
  DROP CONSTRAINT career_trim_ledger_trims_check;
ALTER TABLE trimmy.career_trim_ledger
  ADD CONSTRAINT career_trim_ledger_kind_reward CHECK (
    (entry_kind = 'paper-reason' AND trims = 10)
    OR (entry_kind = 'mission' AND trims = 20)
    OR (entry_kind = 'promotion' AND trims = 100)
  );

CREATE TABLE trimmy.career_starts (
  user_id uuid PRIMARY KEY REFERENCES trimmy.users(id),
  first_order_id uuid NOT NULL UNIQUE,
  started_at timestamptz NOT NULL CHECK (isfinite(started_at)),
  FOREIGN KEY (first_order_id, user_id) REFERENCES trimmy.paper_orders(id, user_id)
);

CREATE TABLE trimmy.career_first_confirmed_buys (
  user_id uuid PRIMARY KEY REFERENCES trimmy.users(id),
  order_id uuid NOT NULL UNIQUE,
  confirmed_at timestamptz NOT NULL CHECK (isfinite(confirmed_at)),
  FOREIGN KEY (order_id, user_id) REFERENCES trimmy.paper_orders(id, user_id)
);

CREATE TABLE trimmy.career_mission_definitions (
  id text COLLATE "C" PRIMARY KEY
    CHECK (id ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND length(id) <= 80),
  chapter_rank text COLLATE "C" NOT NULL
    CHECK (chapter_rank IN ('rookie', 'analyst', 'trader', 'senior-trader', 'partner', 'legend')),
  mission_order smallint NOT NULL CHECK (mission_order BETWEEN 1 AND 100),
  mission_kind text COLLATE "C" NOT NULL CHECK (mission_kind IN ('action', 'promotion')),
  title text NOT NULL CHECK (title = btrim(title) AND char_length(title) BETWEEN 1 AND 60
    AND title !~ '[[:cntrl:]]'),
  instruction text NOT NULL CHECK (instruction = btrim(instruction)
    AND char_length(instruction) BETWEEN 1 AND 120 AND instruction !~ '[[:cntrl:]]'),
  trims_reward integer NOT NULL CHECK (trims_reward = 20),
  evidence_kind text COLLATE "C" NOT NULL
    CHECK (evidence_kind IN ('paper-first-buy', 'paper-first-reason', 'server-red-day-hold')),
  evidence_live boolean NOT NULL,
  promotes_to_rank text COLLATE "C"
    CHECK (promotes_to_rank IS NULL OR promotes_to_rank IN
      ('analyst', 'trader', 'senior-trader', 'partner', 'legend')),
  UNIQUE (chapter_rank, mission_order),
  UNIQUE (evidence_kind),
  UNIQUE (promotes_to_rank),
  CHECK ((mission_kind = 'promotion') = (promotes_to_rank IS NOT NULL))
);

INSERT INTO trimmy.career_mission_definitions(
  id, chapter_rank, mission_order, mission_kind, title, instruction,
  trims_reward, evidence_kind, evidence_live, promotes_to_rank)
VALUES
  ('first-paper-buy', 'rookie', 1, 'action', 'Buy your first stock',
    'Complete one paper buy.', 20, 'paper-first-buy', true, NULL),
  ('write-a-reason', 'rookie', 2, 'action', 'Write your reason',
    'Add a reason to a paper buy you still hold.', 20, 'paper-first-reason', true, NULL),
  ('hold-through-red-day', 'rookie', 3, 'promotion', 'Hold through a red day',
    'Hold a stock through a verified red Wall Street day.', 20,
    'server-red-day-hold', false, 'analyst');

CREATE TABLE trimmy.career_mission_completions (
  completion_id uuid NOT NULL,
  user_id uuid NOT NULL REFERENCES trimmy.career_profiles(user_id),
  mission_id text COLLATE "C" NOT NULL REFERENCES trimmy.career_mission_definitions(id),
  evidence_kind text COLLATE "C" NOT NULL,
  evidence_id uuid NOT NULL,
  career_revision bigint NOT NULL CHECK (career_revision BETWEEN 1 AND 9007199254740991),
  trims_awarded integer NOT NULL CHECK (trims_awarded = 20),
  completed_at timestamptz NOT NULL CHECK (isfinite(completed_at)),
  PRIMARY KEY (completion_id),
  UNIQUE (user_id, mission_id),
  UNIQUE (user_id, evidence_kind, evidence_id),
  UNIQUE (user_id, career_revision),
  FOREIGN KEY (user_id, career_revision)
    REFERENCES trimmy.career_trim_ledger(user_id, career_revision)
    DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE trimmy.career_promotion_receipts (
  user_id uuid NOT NULL REFERENCES trimmy.career_profiles(user_id),
  mutation_id uuid NOT NULL,
  request_hash trimmy.sha256_hex NOT NULL,
  from_rank text COLLATE "C" NOT NULL
    CHECK (from_rank IN ('rookie', 'analyst', 'trader', 'senior-trader', 'partner')),
  to_rank text COLLATE "C" NOT NULL
    CHECK (to_rank IN ('analyst', 'trader', 'senior-trader', 'partner', 'legend')),
  mission_id text COLLATE "C" NOT NULL REFERENCES trimmy.career_mission_definitions(id),
  career_revision bigint NOT NULL CHECK (career_revision BETWEEN 1 AND 9007199254740991),
  trims_awarded integer NOT NULL CHECK (trims_awarded = 100),
  promoted_at timestamptz NOT NULL CHECK (isfinite(promoted_at)),
  PRIMARY KEY (user_id, mutation_id),
  UNIQUE (user_id, to_rank),
  UNIQUE (user_id, career_revision),
  FOREIGN KEY (user_id, career_revision)
    REFERENCES trimmy.career_trim_ledger(user_id, career_revision)
    DEFERRABLE INITIALLY DEFERRED,
  CHECK (trimmy.career_rank_number(to_rank) = trimmy.career_rank_number(from_rank) + 1)
);

CREATE FUNCTION trimmy.protect_career_start() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE selected_order trimmy.paper_orders%ROWTYPE;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'Career start history is append-only' USING ERRCODE = '23514';
  END IF;
  SELECT o.* INTO selected_order FROM trimmy.paper_orders o
    WHERE o.id = NEW.first_order_id AND o.user_id = NEW.user_id;
  IF NOT FOUND OR selected_order.committed_at <> NEW.started_at OR EXISTS (
    SELECT 1 FROM trimmy.paper_orders earlier WHERE earlier.user_id = NEW.user_id
      AND (earlier.committed_at, earlier.id) < (selected_order.committed_at, selected_order.id)
  ) THEN
    RAISE EXCEPTION 'Career start must be the first committed paper order'
      USING ERRCODE = '23514', CONSTRAINT = 'career_start_first_order';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.protect_career_start() FROM PUBLIC;
CREATE TRIGGER career_start_guard
  BEFORE INSERT OR UPDATE OR DELETE ON trimmy.career_starts
  FOR EACH ROW EXECUTE FUNCTION trimmy.protect_career_start();

CREATE FUNCTION trimmy.protect_career_first_buy() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE selected_order trimmy.paper_orders%ROWTYPE;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'First-buy history is append-only' USING ERRCODE = '23514';
  END IF;
  SELECT o.* INTO selected_order FROM trimmy.paper_orders o
    WHERE o.id = NEW.order_id AND o.user_id = NEW.user_id;
  IF NOT FOUND OR selected_order.action <> 'buy'
      OR selected_order.committed_at <> NEW.confirmed_at OR EXISTS (
    SELECT 1 FROM trimmy.paper_orders earlier WHERE earlier.user_id = NEW.user_id
      AND earlier.action = 'buy'
      AND (earlier.committed_at, earlier.id) < (selected_order.committed_at, selected_order.id)
  ) THEN
    RAISE EXCEPTION 'First confirmed buy must match the earliest committed paper buy'
      USING ERRCODE = '23514', CONSTRAINT = 'career_first_confirmed_buy';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.protect_career_first_buy() FROM PUBLIC;
CREATE TRIGGER career_first_buy_guard
  BEFORE INSERT OR UPDATE OR DELETE ON trimmy.career_first_confirmed_buys
  FOR EACH ROW EXECUTE FUNCTION trimmy.protect_career_first_buy();

CREATE TRIGGER career_mission_completion_append_only
  BEFORE UPDATE OR DELETE ON trimmy.career_mission_completions
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();
CREATE TRIGGER career_promotion_receipt_append_only
  BEFORE UPDATE OR DELETE ON trimmy.career_promotion_receipts
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();

CREATE OR REPLACE FUNCTION trimmy.career_record_activity(
  selected_user uuid,
  activity_date date,
  trims_delta integer,
  observed_at timestamptz
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE current_row trimmy.career_profiles%ROWTYPE;
DECLARE next_revision bigint; next_streak integer; next_updated timestamptz;
BEGIN
  IF selected_user IS NULL OR activity_date IS NULL OR observed_at IS NULL
      OR NOT isfinite(observed_at) OR activity_date > (observed_at AT TIME ZONE 'UTC')::date
      OR trims_delta NOT IN (0, 10, 20, 100) THEN
    RAISE EXCEPTION 'Career activity input is invalid' USING ERRCODE = '22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('trimmy.career:' || selected_user::text, 0));
  IF NOT EXISTS (SELECT 1 FROM trimmy.users u WHERE u.id = selected_user AND u.status = 'active') THEN
    RAISE EXCEPTION 'Career activity requires an active account' USING ERRCODE = '23514';
  END IF;
  SELECT p.* INTO current_row FROM trimmy.career_profiles p
    WHERE p.user_id = selected_user FOR UPDATE;
  IF NOT FOUND THEN
    INSERT INTO trimmy.career_profiles(
      user_id, revision, trims_total, rank_id, streak_days, last_active_date,
      created_at, updated_at)
    VALUES (selected_user, 1, trims_delta, 'rookie', 1, activity_date,
      observed_at, observed_at)
    RETURNING revision INTO next_revision;
    RETURN next_revision;
  END IF;
  IF current_row.revision >= 9007199254740991
      OR current_row.trims_total > 9007199254740991 - trims_delta THEN
    RAISE EXCEPTION 'Career revision is exhausted'
      USING ERRCODE = '22003', CONSTRAINT = 'career_revision_exhausted';
  END IF;
  IF activity_date <= current_row.last_active_date AND trims_delta = 0 THEN
    RETURN current_row.revision;
  END IF;
  next_streak := CASE
    WHEN activity_date <= current_row.last_active_date THEN current_row.streak_days
    WHEN activity_date <= current_row.last_active_date + 2 THEN current_row.streak_days + 1
    ELSE 1
  END;
  next_revision := current_row.revision + 1;
  next_updated := greatest(date_trunc('milliseconds', observed_at),
    current_row.updated_at + interval '1 millisecond');
  UPDATE trimmy.career_profiles SET
    revision = next_revision,
    trims_total = current_row.trims_total + trims_delta,
    streak_days = next_streak,
    last_active_date = greatest(current_row.last_active_date, activity_date),
    updated_at = next_updated
  WHERE user_id = selected_user;
  RETURN next_revision;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_record_activity(uuid, date, integer, timestamptz) FROM PUBLIC;

CREATE FUNCTION trimmy.career_complete_mission(
  selected_user uuid,
  selected_mission text,
  selected_evidence_kind text,
  selected_evidence uuid,
  observed_at timestamptz
) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE definition_row trimmy.career_mission_definitions%ROWTYPE;
DECLARE next_revision bigint; generated_completion uuid; completed_date date;
BEGIN
  IF selected_user IS NULL OR selected_mission IS NULL OR selected_evidence_kind IS NULL
      OR selected_evidence IS NULL OR observed_at IS NULL OR NOT isfinite(observed_at)
      OR (observed_at AT TIME ZONE 'UTC')::date > (clock_timestamp() AT TIME ZONE 'UTC')::date THEN
    RETURN 'invalid';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('trimmy.career:' || selected_user::text, 0));
  SELECT d.* INTO definition_row FROM trimmy.career_mission_definitions d
    WHERE d.id = selected_mission;
  IF NOT FOUND OR definition_row.evidence_kind <> selected_evidence_kind THEN
    RETURN 'invalid';
  END IF;
  IF EXISTS (SELECT 1 FROM trimmy.career_mission_completions c
      WHERE c.user_id = selected_user AND c.mission_id = selected_mission) THEN
    RETURN 'already_completed';
  END IF;
  IF NOT definition_row.evidence_live THEN RETURN 'locked'; END IF;
  IF EXISTS (
    SELECT 1 FROM trimmy.career_mission_definitions previous
    WHERE previous.chapter_rank = definition_row.chapter_rank
      AND previous.mission_order < definition_row.mission_order
      AND NOT EXISTS (
        SELECT 1 FROM trimmy.career_mission_completions completion
        WHERE completion.user_id = selected_user AND completion.mission_id = previous.id
      )
  ) THEN
    RETURN 'prerequisite_required';
  END IF;
  IF definition_row.evidence_kind = 'paper-first-buy' THEN
    IF NOT EXISTS (SELECT 1 FROM trimmy.career_first_confirmed_buys b
        WHERE b.user_id = selected_user AND b.order_id = selected_evidence
          AND b.confirmed_at = observed_at) THEN
      RETURN 'evidence_missing';
    END IF;
  ELSIF definition_row.evidence_kind = 'paper-first-reason' THEN
    IF NOT EXISTS (SELECT 1 FROM trimmy.career_trade_reasons r
        WHERE r.user_id = selected_user AND r.order_id = selected_evidence
          AND r.saved_at = observed_at) THEN
      RETURN 'evidence_missing';
    END IF;
  ELSIF definition_row.evidence_kind <> 'server-red-day-hold' THEN
    RETURN 'invalid';
  END IF;
  completed_date := (observed_at AT TIME ZONE 'UTC')::date;
  BEGIN
    next_revision := trimmy.career_record_activity(selected_user, completed_date, 20, observed_at);
  EXCEPTION WHEN numeric_value_out_of_range THEN
    RETURN 'revision_exhausted';
  END;
  generated_completion := gen_random_uuid();
  INSERT INTO trimmy.career_trim_ledger(
    user_id, career_revision, entry_kind, source_id, trims, awarded_on, created_at)
  VALUES (selected_user, next_revision, 'mission', generated_completion, 20,
    completed_date, observed_at);
  INSERT INTO trimmy.career_mission_completions(
    completion_id, user_id, mission_id, evidence_kind, evidence_id,
    career_revision, trims_awarded, completed_at)
  VALUES (generated_completion, selected_user, selected_mission, selected_evidence_kind,
    selected_evidence, next_revision, 20, observed_at);
  RETURN 'completed';
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_complete_mission(uuid, text, text, uuid, timestamptz) FROM PUBLIC;

CREATE FUNCTION trimmy.check_career_mission_ledger_pair() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  IF TG_TABLE_NAME = 'career_mission_completions' THEN
    IF NOT EXISTS (SELECT 1 FROM trimmy.career_trim_ledger l
      WHERE l.user_id = NEW.user_id AND l.career_revision = NEW.career_revision
        AND l.entry_kind = 'mission' AND l.source_id = NEW.completion_id
        AND l.trims = NEW.trims_awarded
        AND l.awarded_on = (NEW.completed_at AT TIME ZONE 'UTC')::date
        AND l.created_at = NEW.completed_at) THEN
      RAISE EXCEPTION 'Mission completion and Trims ledger do not agree'
        USING ERRCODE = '23514', CONSTRAINT = 'career_mission_ledger_pair';
    END IF;
  ELSIF NEW.entry_kind = 'mission' AND NOT EXISTS (
    SELECT 1 FROM trimmy.career_mission_completions c
    WHERE c.user_id = NEW.user_id AND c.career_revision = NEW.career_revision
      AND c.completion_id = NEW.source_id AND c.trims_awarded = NEW.trims
      AND (c.completed_at AT TIME ZONE 'UTC')::date = NEW.awarded_on
      AND c.completed_at = NEW.created_at
  ) THEN
    RAISE EXCEPTION 'Mission Trims require a matching completion'
      USING ERRCODE = '23514', CONSTRAINT = 'career_mission_ledger_pair';
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.check_career_mission_ledger_pair() FROM PUBLIC;
CREATE CONSTRAINT TRIGGER career_completion_ledger_pair
  AFTER INSERT ON trimmy.career_mission_completions DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trimmy.check_career_mission_ledger_pair();
CREATE CONSTRAINT TRIGGER career_ledger_completion_pair
  AFTER INSERT ON trimmy.career_trim_ledger DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trimmy.check_career_mission_ledger_pair();

-- Reconstruct facts from every committed paper order that predates this
-- migration before enabling the future-order trigger.
INSERT INTO trimmy.career_starts(user_id, first_order_id, started_at)
SELECT DISTINCT ON (o.user_id) o.user_id, o.id, o.committed_at
FROM trimmy.paper_orders o
ORDER BY o.user_id, o.committed_at, o.id;

INSERT INTO trimmy.career_first_confirmed_buys(user_id, order_id, confirmed_at)
SELECT DISTINCT ON (o.user_id) o.user_id, o.id, o.committed_at
FROM trimmy.paper_orders o
WHERE o.action = 'buy'
ORDER BY o.user_id, o.committed_at, o.id;

DO $$
DECLARE selected record;
BEGIN
  FOR selected IN
    SELECT b.user_id, b.order_id, b.confirmed_at
    FROM trimmy.career_first_confirmed_buys b
    ORDER BY b.user_id
  LOOP
    PERFORM trimmy.career_complete_mission(selected.user_id, 'first-paper-buy',
      'paper-first-buy', selected.order_id, selected.confirmed_at);
  END LOOP;
  FOR selected IN
    SELECT DISTINCT ON (r.user_id) r.user_id, r.order_id, r.saved_at
    FROM trimmy.career_trade_reasons r
    ORDER BY r.user_id, r.saved_at, r.order_id
  LOOP
    PERFORM trimmy.career_complete_mission(selected.user_id, 'write-a-reason',
      'paper-first-reason', selected.order_id, selected.saved_at);
  END LOOP;
END;
$$;

CREATE FUNCTION trimmy.career_paper_order_milestones_and_mission() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE completion_outcome text;
BEGIN
  INSERT INTO trimmy.career_starts(user_id, first_order_id, started_at)
    SELECT NEW.user_id, NEW.id, NEW.committed_at
    WHERE NOT EXISTS (SELECT 1 FROM trimmy.career_starts s WHERE s.user_id = NEW.user_id);
  IF EXISTS (SELECT 1 FROM trimmy.career_starts s WHERE s.user_id = NEW.user_id
      AND (s.started_at, s.first_order_id) > (NEW.committed_at, NEW.id)) THEN
    RAISE EXCEPTION 'A committed order cannot predate immutable Career start history'
      USING ERRCODE = '23514', CONSTRAINT = 'career_start_first_order';
  END IF;
  IF NEW.action = 'buy' THEN
    INSERT INTO trimmy.career_first_confirmed_buys(user_id, order_id, confirmed_at)
      SELECT NEW.user_id, NEW.id, NEW.committed_at
      WHERE NOT EXISTS (
        SELECT 1 FROM trimmy.career_first_confirmed_buys b WHERE b.user_id = NEW.user_id);
    IF EXISTS (SELECT 1 FROM trimmy.career_first_confirmed_buys b WHERE b.user_id = NEW.user_id
        AND (b.confirmed_at, b.order_id) > (NEW.committed_at, NEW.id)) THEN
      RAISE EXCEPTION 'A committed buy cannot predate immutable first-buy history'
        USING ERRCODE = '23514', CONSTRAINT = 'career_first_confirmed_buy';
    END IF;
    SELECT trimmy.career_complete_mission(NEW.user_id, 'first-paper-buy',
      'paper-first-buy', NEW.id, NEW.committed_at) INTO completion_outcome;
    IF completion_outcome NOT IN ('completed', 'already_completed') THEN
      RAISE EXCEPTION 'First-buy mission could not be recorded'
        USING ERRCODE = '23514', CONSTRAINT = 'career_first_buy_mission';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_paper_order_milestones_and_mission() FROM PUBLIC;
CREATE TRIGGER career_paper_order_milestones_and_mission
  AFTER INSERT ON trimmy.paper_orders
  FOR EACH ROW EXECUTE FUNCTION trimmy.career_paper_order_milestones_and_mission();

CREATE FUNCTION trimmy.career_reason_mission() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE completion_outcome text;
BEGIN
  SELECT trimmy.career_complete_mission(NEW.user_id, 'write-a-reason',
    'paper-first-reason', NEW.order_id, NEW.saved_at) INTO completion_outcome;
  IF completion_outcome NOT IN ('completed', 'already_completed') THEN
    RAISE EXCEPTION 'Written-reason mission could not be recorded'
      USING ERRCODE = '23514', CONSTRAINT = 'career_written_reason_mission';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_reason_mission() FROM PUBLIC;
CREATE TRIGGER career_reason_mission
  AFTER INSERT ON trimmy.career_trade_reasons
  FOR EACH ROW EXECUTE FUNCTION trimmy.career_reason_mission();

-- Trusted server seam for future provider-backed evidence. It is deliberately
-- not granted to the API role, and the documented red-day mission stays locked
-- until a later migration enables its evidence source.
CREATE FUNCTION trimmy.career_server_mission_complete(
  selected_user uuid,
  selected_mission text,
  selected_evidence uuid,
  observed_at timestamptz
) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE evidence_type text; evidence_is_live boolean;
BEGIN
  SELECT d.evidence_kind, d.evidence_live INTO evidence_type, evidence_is_live
    FROM trimmy.career_mission_definitions d WHERE d.id = selected_mission;
  IF evidence_type IS DISTINCT FROM 'server-red-day-hold' OR evidence_is_live IS DISTINCT FROM true THEN
    RETURN 'locked';
  END IF;
  RETURN trimmy.career_complete_mission(selected_user, selected_mission,
    evidence_type, selected_evidence, observed_at);
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_server_mission_complete(uuid, text, uuid, timestamptz) FROM PUBLIC;

CREATE FUNCTION trimmy.career_promote(
  selected_user uuid,
  selected_mutation uuid,
  selected_hash text,
  selected_target text
) RETURNS TABLE (
  outcome text,
  mutation_id uuid,
  from_rank text,
  to_rank text,
  career_revision bigint,
  trims_awarded integer,
  promoted_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE account_status text; current_row trimmy.career_profiles%ROWTYPE;
DECLARE receipt_row trimmy.career_promotion_receipts%ROWTYPE;
DECLARE required_threshold integer; required_mission text;
DECLARE next_revision bigint; observed_at timestamptz;
BEGIN
  IF selected_user IS NULL OR selected_mutation IS NULL OR selected_hash IS NULL
      OR selected_hash !~ '^[a-f0-9]{64}$'
      OR selected_target NOT IN ('analyst', 'trader', 'senior-trader', 'partner', 'legend') THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::text, NULL::text,
      NULL::bigint, NULL::integer, NULL::timestamptz;
    RETURN;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('trimmy.career:' || selected_user::text, 0));
  SELECT u.status INTO account_status FROM trimmy.users u WHERE u.id = selected_user FOR UPDATE;
  IF account_status IS DISTINCT FROM 'active' THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::uuid, NULL::text, NULL::text,
      NULL::bigint, NULL::integer, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT r.* INTO receipt_row FROM trimmy.career_promotion_receipts r
    WHERE r.user_id = selected_user AND r.mutation_id = selected_mutation;
  IF FOUND THEN
    IF receipt_row.request_hash <> selected_hash THEN
      RETURN QUERY SELECT 'idempotency_conflict'::text, NULL::uuid, NULL::text, NULL::text,
        NULL::bigint, NULL::integer, NULL::timestamptz;
    ELSE
      RETURN QUERY SELECT 'promoted'::text, receipt_row.mutation_id, receipt_row.from_rank,
        receipt_row.to_rank, receipt_row.career_revision, receipt_row.trims_awarded,
        receipt_row.promoted_at;
    END IF;
    RETURN;
  END IF;
  SELECT p.* INTO current_row FROM trimmy.career_profiles p
    WHERE p.user_id = selected_user FOR UPDATE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'profile_required'::text, NULL::uuid, NULL::text, NULL::text,
      NULL::bigint, NULL::integer, NULL::timestamptz;
    RETURN;
  END IF;
  IF trimmy.career_rank_number(selected_target) <> trimmy.career_rank_number(current_row.rank_id) + 1 THEN
    RETURN QUERY SELECT 'rank_mismatch'::text, NULL::uuid, NULL::text, NULL::text,
      NULL::bigint, NULL::integer, NULL::timestamptz;
    RETURN;
  END IF;
  required_threshold := CASE selected_target
    WHEN 'analyst' THEN 300 WHEN 'trader' THEN 900 WHEN 'senior-trader' THEN 2000
    WHEN 'partner' THEN 4500 WHEN 'legend' THEN 10000 END;
  IF current_row.trims_total < required_threshold THEN
    RETURN QUERY SELECT 'threshold_required'::text, NULL::uuid, NULL::text, NULL::text,
      NULL::bigint, NULL::integer, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT d.id INTO required_mission FROM trimmy.career_mission_definitions d
    WHERE d.mission_kind = 'promotion' AND d.chapter_rank = current_row.rank_id
      AND d.promotes_to_rank = selected_target;
  IF required_mission IS NULL OR NOT EXISTS (
    SELECT 1 FROM trimmy.career_mission_completions c
    WHERE c.user_id = selected_user AND c.mission_id = required_mission
  ) THEN
    RETURN QUERY SELECT 'mission_required'::text, NULL::uuid, NULL::text, NULL::text,
      NULL::bigint, NULL::integer, NULL::timestamptz;
    RETURN;
  END IF;
  IF current_row.revision >= 9007199254740991
      OR current_row.trims_total > 9007199254740991 - 100 THEN
    RETURN QUERY SELECT 'revision_exhausted'::text, NULL::uuid, NULL::text, NULL::text,
      NULL::bigint, NULL::integer, NULL::timestamptz;
    RETURN;
  END IF;
  observed_at := greatest(date_trunc('milliseconds', clock_timestamp()),
    current_row.updated_at + interval '1 millisecond');
  next_revision := current_row.revision + 1;
  UPDATE trimmy.career_profiles SET revision = next_revision,
    trims_total = current_row.trims_total + 100,
    rank_id = selected_target,
    updated_at = observed_at
  WHERE user_id = selected_user;
  INSERT INTO trimmy.career_trim_ledger(
    user_id, career_revision, entry_kind, source_id, trims, awarded_on, created_at)
  VALUES (selected_user, next_revision, 'promotion', selected_mutation, 100,
    (observed_at AT TIME ZONE 'UTC')::date, observed_at);
  INSERT INTO trimmy.career_promotion_receipts(
    user_id, mutation_id, request_hash, from_rank, to_rank, mission_id,
    career_revision, trims_awarded, promoted_at)
  VALUES (selected_user, selected_mutation, selected_hash, current_row.rank_id,
    selected_target, required_mission, next_revision, 100, observed_at);
  RETURN QUERY SELECT 'promoted'::text, selected_mutation, current_row.rank_id,
    selected_target, next_revision, 100, observed_at;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_promote(uuid, uuid, text, text) FROM PUBLIC;

CREATE FUNCTION trimmy.check_career_promotion_pairs() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  IF TG_TABLE_NAME = 'career_profiles' THEN
    IF NEW.rank_id <> OLD.rank_id AND NOT EXISTS (
      SELECT 1 FROM trimmy.career_promotion_receipts r
      WHERE r.user_id = NEW.user_id AND r.career_revision = NEW.revision
        AND r.from_rank = OLD.rank_id AND r.to_rank = NEW.rank_id
        AND r.trims_awarded = NEW.trims_total - OLD.trims_total
        AND r.promoted_at = NEW.updated_at
    ) THEN
      RAISE EXCEPTION 'A rank change requires its promotion receipt'
        USING ERRCODE = '23514', CONSTRAINT = 'career_profile_promotion_pair';
    END IF;
  ELSIF TG_TABLE_NAME = 'career_promotion_receipts' THEN
    IF NOT EXISTS (SELECT 1 FROM trimmy.career_trim_ledger l
      WHERE l.user_id = NEW.user_id AND l.career_revision = NEW.career_revision
        AND l.entry_kind = 'promotion' AND l.source_id = NEW.mutation_id
        AND l.trims = NEW.trims_awarded AND l.created_at = NEW.promoted_at
        AND l.awarded_on = (NEW.promoted_at AT TIME ZONE 'UTC')::date) THEN
      RAISE EXCEPTION 'Promotion receipt and Trims ledger do not agree'
        USING ERRCODE = '23514', CONSTRAINT = 'career_promotion_ledger_pair';
    END IF;
  ELSIF NEW.entry_kind = 'promotion' AND NOT EXISTS (
    SELECT 1 FROM trimmy.career_promotion_receipts r
    WHERE r.user_id = NEW.user_id AND r.career_revision = NEW.career_revision
      AND r.mutation_id = NEW.source_id AND r.trims_awarded = NEW.trims
      AND r.promoted_at = NEW.created_at
      AND (r.promoted_at AT TIME ZONE 'UTC')::date = NEW.awarded_on
  ) THEN
    RAISE EXCEPTION 'Promotion Trims require a matching receipt'
      USING ERRCODE = '23514', CONSTRAINT = 'career_promotion_ledger_pair';
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.check_career_promotion_pairs() FROM PUBLIC;
CREATE CONSTRAINT TRIGGER career_profile_promotion_pair
  AFTER UPDATE ON trimmy.career_profiles DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trimmy.check_career_promotion_pairs();
CREATE CONSTRAINT TRIGGER career_promotion_ledger_pair
  AFTER INSERT ON trimmy.career_promotion_receipts DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trimmy.check_career_promotion_pairs();
CREATE CONSTRAINT TRIGGER career_ledger_promotion_pair
  AFTER INSERT ON trimmy.career_trim_ledger DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trimmy.check_career_promotion_pairs();

DROP FUNCTION trimmy.career_summary_get(uuid);
CREATE FUNCTION trimmy.career_summary_get(selected_user uuid)
RETURNS TABLE (
  outcome text,
  revision bigint,
  trims_total bigint,
  trims_today bigint,
  trims_week bigint,
  rank_id text,
  rank_label text,
  paper_limit text,
  rank_threshold integer,
  next_rank_id text,
  next_rank_label text,
  next_rank_threshold integer,
  trims_remaining bigint,
  promotion_required boolean,
  streak_days integer,
  streak_status text,
  last_active_date date,
  server_date date,
  updated_at timestamptz,
  career_started boolean,
  first_buy_order_id uuid,
  first_buy_asset_id text,
  first_buy_variant_mint text,
  first_buy_symbol text,
  first_buy_quantity_micros text,
  first_buy_confirmed_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE account_status text; current_row trimmy.career_profiles%ROWTYPE;
DECLARE today date := (clock_timestamp() AT TIME ZONE 'UTC')::date;
DECLARE week_start date := date_trunc('week', today::timestamp)::date;
DECLARE current_threshold integer; next_id text; next_label text; next_threshold integer;
DECLARE current_label text; effective_streak integer; effective_status text;
DECLARE total_today bigint; total_week bigint; started boolean;
DECLARE first_buy trimmy.paper_orders%ROWTYPE;
BEGIN
  IF selected_user IS NULL THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::bigint, NULL::bigint, NULL::bigint, NULL::bigint,
      NULL::text, NULL::text, NULL::text, NULL::integer, NULL::text, NULL::text, NULL::integer,
      NULL::bigint, NULL::boolean, NULL::integer, NULL::text, NULL::date, today, NULL::timestamptz,
      NULL::boolean, NULL::uuid, NULL::text, NULL::text, NULL::text, NULL::text,
      NULL::timestamptz;
    RETURN;
  END IF;
  SELECT u.status INTO account_status FROM trimmy.users u WHERE u.id = selected_user;
  IF account_status IS DISTINCT FROM 'active' THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::bigint, NULL::bigint, NULL::bigint, NULL::bigint,
      NULL::text, NULL::text, NULL::text, NULL::integer, NULL::text, NULL::text, NULL::integer,
      NULL::bigint, NULL::boolean, NULL::integer, NULL::text, NULL::date, today, NULL::timestamptz,
      NULL::boolean, NULL::uuid, NULL::text, NULL::text, NULL::text, NULL::text,
      NULL::timestamptz;
    RETURN;
  END IF;
  SELECT EXISTS (SELECT 1 FROM trimmy.career_starts s WHERE s.user_id = selected_user)
    INTO started;
  SELECT o.* INTO first_buy FROM trimmy.career_first_confirmed_buys b
    JOIN trimmy.paper_orders o ON o.id = b.order_id AND o.user_id = b.user_id
    WHERE b.user_id = selected_user;
  SELECT p.* INTO current_row FROM trimmy.career_profiles p WHERE p.user_id = selected_user;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'found'::text, 0::bigint, 0::bigint, 0::bigint, 0::bigint,
      'rookie'::text, 'Rookie'::text, '10000'::text, 0::integer,
      'analyst'::text, 'Analyst'::text, 300::integer, 300::bigint, false,
      0::integer, 'not-started'::text, NULL::date, today, NULL::timestamptz,
      started, first_buy.id, first_buy.asset_id, first_buy.variant_mint::text,
      first_buy.symbol, first_buy.quantity_micros::text, first_buy.committed_at;
    RETURN;
  END IF;
  SELECT coalesce(sum(l.trims) FILTER (WHERE l.awarded_on = today), 0)::bigint,
         coalesce(sum(l.trims) FILTER (WHERE l.awarded_on >= week_start AND l.awarded_on <= today), 0)::bigint
    INTO total_today, total_week
    FROM trimmy.career_trim_ledger l WHERE l.user_id = selected_user;
  SELECT
    CASE current_row.rank_id
      WHEN 'rookie' THEN 'Rookie' WHEN 'analyst' THEN 'Analyst' WHEN 'trader' THEN 'Trader'
      WHEN 'senior-trader' THEN 'Senior Trader' WHEN 'partner' THEN 'Partner' ELSE 'Legend' END,
    CASE current_row.rank_id
      WHEN 'rookie' THEN 0 WHEN 'analyst' THEN 300 WHEN 'trader' THEN 900
      WHEN 'senior-trader' THEN 2000 WHEN 'partner' THEN 4500 ELSE 10000 END,
    CASE current_row.rank_id
      WHEN 'rookie' THEN 'analyst' WHEN 'analyst' THEN 'trader' WHEN 'trader' THEN 'senior-trader'
      WHEN 'senior-trader' THEN 'partner' WHEN 'partner' THEN 'legend' ELSE NULL END,
    CASE current_row.rank_id
      WHEN 'rookie' THEN 'Analyst' WHEN 'analyst' THEN 'Trader' WHEN 'trader' THEN 'Senior Trader'
      WHEN 'senior-trader' THEN 'Partner' WHEN 'partner' THEN 'Legend' ELSE NULL END,
    CASE current_row.rank_id
      WHEN 'rookie' THEN 300 WHEN 'analyst' THEN 900 WHEN 'trader' THEN 2000
      WHEN 'senior-trader' THEN 4500 WHEN 'partner' THEN 10000 ELSE NULL END
    INTO current_label, current_threshold, next_id, next_label, next_threshold;
  IF current_row.last_active_date = today THEN
    effective_streak := current_row.streak_days; effective_status := 'active';
  ELSIF current_row.last_active_date = today - 1 THEN
    effective_streak := current_row.streak_days; effective_status := 'at-risk';
  ELSIF current_row.last_active_date = today - 2 THEN
    effective_streak := current_row.streak_days; effective_status := 'grace';
  ELSE
    effective_streak := 0; effective_status := 'not-started';
  END IF;
  RETURN QUERY SELECT 'found'::text, current_row.revision, current_row.trims_total,
    total_today, total_week, current_row.rank_id, current_label, '10000'::text,
    current_threshold, next_id, next_label, next_threshold,
    CASE WHEN next_threshold IS NULL THEN NULL::bigint
      ELSE greatest(0::bigint, next_threshold::bigint - current_row.trims_total) END,
    CASE WHEN next_threshold IS NULL THEN false
      ELSE current_row.trims_total >= next_threshold END,
    effective_streak, effective_status,
    CASE WHEN effective_streak = 0 THEN NULL::date ELSE current_row.last_active_date END,
    today, current_row.updated_at, started, first_buy.id, first_buy.asset_id,
    first_buy.variant_mint::text, first_buy.symbol, first_buy.quantity_micros::text,
    first_buy.committed_at;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_summary_get(uuid) FROM PUBLIC;

CREATE FUNCTION trimmy.career_missions_get(selected_user uuid)
RETURNS TABLE (
  outcome text,
  career_revision bigint,
  current_rank text,
  mission_id text,
  chapter_rank text,
  mission_order smallint,
  mission_kind text,
  title text,
  instruction text,
  trims_reward integer,
  promotes_to_rank text,
  mission_status text,
  completed_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE account_status text; selected_revision bigint := 0; selected_rank text := 'rookie';
BEGIN
  IF selected_user IS NULL THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::bigint, NULL::text, NULL::text,
      NULL::text, NULL::smallint, NULL::text, NULL::text, NULL::text,
      NULL::integer, NULL::text, NULL::text, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT u.status INTO account_status FROM trimmy.users u WHERE u.id = selected_user;
  IF account_status IS DISTINCT FROM 'active' THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::bigint, NULL::text, NULL::text,
      NULL::text, NULL::smallint, NULL::text, NULL::text, NULL::text,
      NULL::integer, NULL::text, NULL::text, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT p.revision, p.rank_id INTO selected_revision, selected_rank
    FROM trimmy.career_profiles p WHERE p.user_id = selected_user;
  IF NOT FOUND THEN selected_revision := 0; selected_rank := 'rookie'; END IF;
  RETURN QUERY
    SELECT 'found'::text, selected_revision, selected_rank, d.id, d.chapter_rank,
      d.mission_order, d.mission_kind, d.title, d.instruction, d.trims_reward,
      d.promotes_to_rank,
      CASE
        WHEN c.mission_id IS NOT NULL THEN 'complete'::text
        WHEN NOT d.evidence_live THEN 'locked'::text
        WHEN d.chapter_rank <> selected_rank THEN 'locked'::text
        WHEN EXISTS (
          SELECT 1 FROM trimmy.career_mission_definitions previous
          WHERE previous.chapter_rank = d.chapter_rank
            AND previous.mission_order < d.mission_order
            AND NOT EXISTS (
              SELECT 1 FROM trimmy.career_mission_completions prior_completion
              WHERE prior_completion.user_id = selected_user
                AND prior_completion.mission_id = previous.id
            )
        ) THEN 'locked'::text
        ELSE 'ready'::text
      END,
      c.completed_at
    FROM trimmy.career_mission_definitions d
    LEFT JOIN trimmy.career_mission_completions c
      ON c.user_id = selected_user AND c.mission_id = d.id
    ORDER BY trimmy.career_rank_number(d.chapter_rank), d.mission_order;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_missions_get(uuid) FROM PUBLIC;

-- Flush the deferred backfill checks before changing table security metadata.
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

ALTER TABLE trimmy.career_starts ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_starts FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_first_confirmed_buys ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_first_confirmed_buys FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_mission_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_mission_definitions FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_mission_completions ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_mission_completions FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_promotion_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_promotion_receipts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE trimmy.career_starts, trimmy.career_first_confirmed_buys,
  trimmy.career_mission_definitions, trimmy.career_mission_completions,
  trimmy.career_promotion_receipts FROM PUBLIC;

INSERT INTO trimmy.schema_migrations(version)
VALUES ('0018_career_missions_and_promotions');
COMMIT;
