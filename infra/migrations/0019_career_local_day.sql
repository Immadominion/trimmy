-- 0019: server-owned IANA timezone and local Career calendar. Existing and
-- future accounts begin on UTC until a client explicitly saves a validated
-- timezone. Career writes never accept an offset or timezone parameter.
BEGIN;

CREATE FUNCTION trimmy.career_time_zone_allowed(candidate text) RETURNS boolean
LANGUAGE sql STABLE
SET search_path = pg_catalog, trimmy AS $$
  SELECT candidate IS NOT NULL
    AND length(candidate) BETWEEN 1 AND 100
    AND (
      candidate = 'UTC'
      OR (
        (candidate COLLATE "C") ~ '^[A-Za-z][A-Za-z0-9._+-]*/[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)*$'
        AND candidate NOT LIKE 'posix/%'
        AND candidate NOT LIKE 'right/%'
      )
    )
    AND EXISTS (
      SELECT 1 FROM pg_catalog.pg_timezone_names names WHERE names.name = candidate
    );
$$;
REVOKE ALL ON FUNCTION trimmy.career_time_zone_allowed(text) FROM PUBLIC;

CREATE TABLE trimmy.career_day_settings (
  user_id uuid PRIMARY KEY REFERENCES trimmy.users(id),
  revision bigint NOT NULL CHECK (revision BETWEEN 1 AND 9007199254740991),
  time_zone text COLLATE "C" NOT NULL CHECK (
    length(time_zone) BETWEEN 1 AND 100
    AND (time_zone = 'UTC' OR
      time_zone ~ '^[A-Za-z][A-Za-z0-9._+-]*/[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)*$')
  ),
  configured boolean NOT NULL,
  created_at timestamptz NOT NULL CHECK (isfinite(created_at)),
  updated_at timestamptz NOT NULL CHECK (isfinite(updated_at) AND updated_at >= created_at)
);

CREATE TABLE trimmy.career_day_setting_receipts (
  user_id uuid NOT NULL REFERENCES trimmy.users(id),
  mutation_id uuid NOT NULL,
  request_hash trimmy.sha256_hex NOT NULL,
  revision bigint NOT NULL CHECK (revision BETWEEN 1 AND 9007199254740991),
  time_zone text COLLATE "C" NOT NULL CHECK (
    length(time_zone) BETWEEN 1 AND 100
    AND (time_zone = 'UTC' OR
      time_zone ~ '^[A-Za-z][A-Za-z0-9._+-]*/[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)*$')
  ),
  configured boolean NOT NULL CHECK (configured),
  server_date date NOT NULL,
  next_day_at timestamptz NOT NULL CHECK (isfinite(next_day_at)),
  created_at timestamptz NOT NULL CHECK (isfinite(created_at)),
  updated_at timestamptz NOT NULL CHECK (isfinite(updated_at) AND updated_at >= created_at),
  PRIMARY KEY (user_id, mutation_id)
);

CREATE FUNCTION trimmy.protect_career_day_setting() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Career day settings cannot be deleted'
      USING ERRCODE = '23514', CONSTRAINT = 'career_day_setting_identity';
  END IF;
  IF NOT trimmy.career_time_zone_allowed(NEW.time_zone) THEN
    RAISE EXCEPTION 'Career timezone is not a supported IANA identifier'
      USING ERRCODE = '23514', CONSTRAINT = 'career_day_setting_time_zone';
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.revision <> 1 OR NEW.time_zone <> 'UTC' OR NEW.configured
        OR NEW.created_at <> NEW.updated_at THEN
      RAISE EXCEPTION 'Career day settings begin on the UTC fallback'
        USING ERRCODE = '23514', CONSTRAINT = 'career_day_setting_initial_state';
    END IF;
  ELSE
    IF (NEW.user_id, NEW.created_at) IS DISTINCT FROM (OLD.user_id, OLD.created_at)
        OR NEW.revision <> OLD.revision + 1 OR NOT NEW.configured
        OR NEW.updated_at <= OLD.updated_at THEN
      RAISE EXCEPTION 'Career day setting revision is invalid'
        USING ERRCODE = '23514', CONSTRAINT = 'career_day_setting_revision';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.protect_career_day_setting() FROM PUBLIC;
CREATE TRIGGER career_day_setting_guard
  BEFORE INSERT OR UPDATE OR DELETE ON trimmy.career_day_settings
  FOR EACH ROW EXECUTE FUNCTION trimmy.protect_career_day_setting();
CREATE TRIGGER career_day_setting_receipt_append_only
  BEFORE UPDATE OR DELETE ON trimmy.career_day_setting_receipts
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();

CREATE FUNCTION trimmy.check_career_day_setting_receipt_pair() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  IF TG_TABLE_NAME = 'career_day_settings' THEN
    IF NEW.configured AND NOT EXISTS (
      SELECT 1 FROM trimmy.career_day_setting_receipts r
      WHERE r.user_id = NEW.user_id AND r.revision = NEW.revision
        AND (r.time_zone, r.configured, r.created_at, r.updated_at)
            IS NOT DISTINCT FROM
            (NEW.time_zone, NEW.configured, NEW.created_at, NEW.updated_at)
    ) THEN
      RAISE EXCEPTION 'Career day setting snapshot requires a receipt'
        USING ERRCODE = '23514', CONSTRAINT = 'career_day_setting_receipt_pair';
    END IF;
  ELSE
    IF NOT EXISTS (
      SELECT 1 FROM trimmy.career_day_settings s
      WHERE s.user_id = NEW.user_id AND s.revision = NEW.revision
        AND (s.time_zone, s.configured, s.created_at, s.updated_at)
            IS NOT DISTINCT FROM
            (NEW.time_zone, NEW.configured, NEW.created_at, NEW.updated_at)
    ) THEN
      RAISE EXCEPTION 'Career day setting receipt requires its snapshot'
        USING ERRCODE = '23514', CONSTRAINT = 'career_day_setting_receipt_pair';
    END IF;
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.check_career_day_setting_receipt_pair() FROM PUBLIC;
CREATE CONSTRAINT TRIGGER career_day_setting_snapshot_receipt_pair
  AFTER INSERT OR UPDATE ON trimmy.career_day_settings DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trimmy.check_career_day_setting_receipt_pair();
CREATE CONSTRAINT TRIGGER career_day_setting_receipt_snapshot_pair
  AFTER INSERT ON trimmy.career_day_setting_receipts DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trimmy.check_career_day_setting_receipt_pair();

CREATE FUNCTION trimmy.career_default_day_setting() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE observed_at timestamptz := date_trunc('milliseconds', clock_timestamp());
BEGIN
  INSERT INTO trimmy.career_day_settings(
    user_id, revision, time_zone, configured, created_at, updated_at)
  VALUES (NEW.id, 1, 'UTC', false, observed_at, observed_at);
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_default_day_setting() FROM PUBLIC;

-- Install the future-user trigger before the set-based backfill. CREATE
-- TRIGGER's table lock is held through commit, so inserts that committed before
-- the lock appear in the following statement and later inserts run the trigger.
CREATE TRIGGER career_default_day_setting
  AFTER INSERT ON trimmy.users
  FOR EACH ROW EXECUTE FUNCTION trimmy.career_default_day_setting();

INSERT INTO trimmy.career_day_settings(
  user_id, revision, time_zone, configured, created_at, updated_at)
SELECT u.id, 1, 'UTC', false,
  date_trunc('milliseconds', statement_timestamp()),
  date_trunc('milliseconds', statement_timestamp())
FROM trimmy.users u
ORDER BY u.id;

CREATE FUNCTION trimmy.career_time_zone(selected_user uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
  SELECT coalesce((
    SELECT s.time_zone FROM trimmy.career_day_settings s WHERE s.user_id = selected_user
  ), 'UTC'::text);
$$;
REVOKE ALL ON FUNCTION trimmy.career_time_zone(uuid) FROM PUBLIC;

CREATE FUNCTION trimmy.career_local_date(selected_user uuid, observed_at timestamptz) RETURNS date
LANGUAGE sql STABLE SECURITY DEFINER STRICT
SET search_path = pg_catalog, trimmy, pg_temp AS $$
  SELECT (observed_at AT TIME ZONE trimmy.career_time_zone(selected_user))::date;
$$;
REVOKE ALL ON FUNCTION trimmy.career_local_date(uuid, timestamptz) FROM PUBLIC;

CREATE FUNCTION trimmy.career_next_day_at(selected_time_zone text, observed_at timestamptz)
RETURNS timestamptz
LANGUAGE sql STABLE STRICT
SET search_path = pg_catalog, trimmy AS $$
  WITH current_day AS (
    SELECT (observed_at AT TIME ZONE selected_time_zone)::date AS local_date
  ), targets AS (
    -- A jurisdiction can skip a civil date when it changes its UTC side, as
    -- Pacific/Apia did in 2011. Search a bounded set for the next date that has
    -- a real instant instead of returning NULL for local_date + 1.
    SELECT current_day.local_date + candidate.day_offset::integer AS local_date
    FROM current_day CROSS JOIN generate_series(1, 3) AS candidate(day_offset)
  ), anchor AS (
    SELECT local_date,
      local_date::timestamp AT TIME ZONE selected_time_zone AS instant
    FROM targets
  ), offsets AS (
    -- PostgreSQL selects one side when local midnight is ambiguous. Probe both
    -- sides so a fall-back transition at midnight returns the first instant on
    -- the new date, while a spring gap returns its first representable instant.
    SELECT DISTINCT anchor.local_date, (probe AT TIME ZONE selected_time_zone) -
      (probe AT TIME ZONE 'UTC') AS utc_offset
    FROM anchor
    CROSS JOIN LATERAL unnest(ARRAY[
      instant - interval '36 hours', instant, instant + interval '36 hours'
    ]) AS samples(probe)
  ), candidates AS (
    SELECT (offsets.local_date::timestamp - offsets.utc_offset)
        AT TIME ZONE 'UTC' AS instant,
      offsets.local_date
    FROM offsets
  )
  SELECT min(candidates.instant)
  FROM candidates
  WHERE candidates.instant > observed_at
    AND (candidates.instant AT TIME ZONE selected_time_zone)::date = candidates.local_date;
$$;
REVOKE ALL ON FUNCTION trimmy.career_next_day_at(text, timestamptz) FROM PUBLIC;

-- Immutable activity instants let the server re-evaluate a streak correctly
-- after a legitimate timezone change. Calendar labels are derived, never sent
-- by the client and never stored as an untrusted offset.
CREATE TABLE trimmy.career_activity_events (
  user_id uuid NOT NULL REFERENCES trimmy.users(id),
  activity_kind text COLLATE "C" NOT NULL
    CHECK (activity_kind IN ('paper-order', 'trade-reason', 'mission')),
  source_id uuid NOT NULL,
  observed_at timestamptz NOT NULL CHECK (isfinite(observed_at)),
  PRIMARY KEY (user_id, activity_kind, source_id)
);
CREATE INDEX career_activity_events_time
  ON trimmy.career_activity_events(user_id, observed_at DESC, activity_kind, source_id);
CREATE TRIGGER career_activity_events_append_only
  BEFORE UPDATE OR DELETE ON trimmy.career_activity_events
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();

-- Freeze every activity source before taking the backfill snapshot. The locks
-- remain through COMMIT while the pairing triggers and event-producing writer
-- functions below are installed. A writer that committed before these locks is
-- visible here; one that was blocked resumes only after the new path is live.
LOCK TABLE trimmy.paper_orders, trimmy.career_trade_reasons,
  trimmy.career_mission_completions IN SHARE ROW EXCLUSIVE MODE;

INSERT INTO trimmy.career_activity_events(user_id, activity_kind, source_id, observed_at)
SELECT o.user_id, 'paper-order', o.id, o.committed_at
FROM trimmy.paper_orders o
UNION ALL
SELECT r.user_id, 'trade-reason', r.order_id, r.saved_at
FROM trimmy.career_trade_reasons r
UNION ALL
SELECT c.user_id, 'mission', c.completion_id, c.completed_at
FROM trimmy.career_mission_completions c;

CREATE FUNCTION trimmy.check_career_activity_source() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE selected_user uuid; selected_kind text; selected_source uuid; selected_at timestamptz;
BEGIN
  IF TG_TABLE_NAME = 'career_activity_events' THEN
    selected_user := NEW.user_id;
    selected_kind := NEW.activity_kind;
    selected_source := NEW.source_id;
    selected_at := NEW.observed_at;
  ELSIF TG_TABLE_NAME = 'paper_orders' THEN
    selected_user := NEW.user_id; selected_kind := 'paper-order';
    selected_source := NEW.id; selected_at := NEW.committed_at;
  ELSIF TG_TABLE_NAME = 'career_trade_reasons' THEN
    selected_user := NEW.user_id; selected_kind := 'trade-reason';
    selected_source := NEW.order_id; selected_at := NEW.saved_at;
  ELSE
    selected_user := NEW.user_id; selected_kind := 'mission';
    selected_source := NEW.completion_id; selected_at := NEW.completed_at;
  END IF;
  IF selected_kind = 'paper-order' THEN
    IF NOT EXISTS (SELECT 1 FROM trimmy.paper_orders o
      WHERE o.user_id = selected_user AND o.id = selected_source
        AND o.committed_at = selected_at) THEN
      RAISE EXCEPTION 'Career paper activity requires its order'
        USING ERRCODE = '23514', CONSTRAINT = 'career_activity_source_pair';
    END IF;
  ELSIF selected_kind = 'trade-reason' THEN
    IF NOT EXISTS (SELECT 1 FROM trimmy.career_trade_reasons r
      WHERE r.user_id = selected_user AND r.order_id = selected_source
        AND r.saved_at = selected_at) THEN
      RAISE EXCEPTION 'Career reason activity requires its reason'
        USING ERRCODE = '23514', CONSTRAINT = 'career_activity_source_pair';
    END IF;
  ELSIF selected_kind = 'mission' THEN
    IF NOT EXISTS (SELECT 1 FROM trimmy.career_mission_completions c
      WHERE c.user_id = selected_user AND c.completion_id = selected_source
        AND c.completed_at = selected_at) THEN
      RAISE EXCEPTION 'Career mission activity requires its completion'
        USING ERRCODE = '23514', CONSTRAINT = 'career_activity_source_pair';
    END IF;
  ELSE
    RAISE EXCEPTION 'Career activity kind is invalid'
      USING ERRCODE = '23514', CONSTRAINT = 'career_activity_source_pair';
  END IF;
  IF TG_TABLE_NAME <> 'career_activity_events' AND NOT EXISTS (
    SELECT 1 FROM trimmy.career_activity_events e
    WHERE e.user_id = selected_user AND e.activity_kind = selected_kind
      AND e.source_id = selected_source AND e.observed_at = selected_at
  ) THEN
    RAISE EXCEPTION 'Career activity source requires its event'
      USING ERRCODE = '23514', CONSTRAINT = 'career_activity_source_pair';
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.check_career_activity_source() FROM PUBLIC;
CREATE CONSTRAINT TRIGGER career_activity_event_source_pair
  AFTER INSERT ON trimmy.career_activity_events DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trimmy.check_career_activity_source();
CREATE CONSTRAINT TRIGGER career_order_activity_pair
  AFTER INSERT ON trimmy.paper_orders DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trimmy.check_career_activity_source();
CREATE CONSTRAINT TRIGGER career_reason_activity_pair
  AFTER INSERT ON trimmy.career_trade_reasons DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trimmy.check_career_activity_source();
CREATE CONSTRAINT TRIGGER career_mission_activity_pair
  AFTER INSERT ON trimmy.career_mission_completions DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trimmy.check_career_activity_source();

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
      OR NOT isfinite(observed_at)
      OR activity_date IS DISTINCT FROM trimmy.career_local_date(selected_user, observed_at)
      OR trims_delta NOT IN (0, 10, 20, 100) THEN
    RAISE EXCEPTION 'Career activity input is invalid' USING ERRCODE = '22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('trimmy.career:' || selected_user::text, 0));
  IF NOT EXISTS (SELECT 1 FROM trimmy.users u WHERE u.id = selected_user AND u.status = 'active') THEN
    RAISE EXCEPTION 'Career activity requires an active account' USING ERRCODE = '23514';
  END IF;
  SELECT p.* INTO current_row FROM trimmy.career_profiles p
    WHERE p.user_id = selected_user FOR UPDATE;
  IF current_row.user_id IS NULL THEN
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

CREATE OR REPLACE FUNCTION trimmy.career_paper_order_activity() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  PERFORM trimmy.career_record_activity(
    NEW.user_id, trimmy.career_local_date(NEW.user_id, NEW.committed_at), 0, NEW.committed_at);
  INSERT INTO trimmy.career_activity_events(user_id, activity_kind, source_id, observed_at)
  VALUES (NEW.user_id, 'paper-order', NEW.id, NEW.committed_at);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION trimmy.career_complete_mission(
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
      OR trimmy.career_local_date(selected_user, observed_at) >
        trimmy.career_local_date(selected_user, clock_timestamp()) THEN
    RETURN 'invalid';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('trimmy.career:' || selected_user::text, 0));
  SELECT d.* INTO definition_row FROM trimmy.career_mission_definitions d
    WHERE d.id = selected_mission;
  IF NOT FOUND OR definition_row.evidence_kind <> selected_evidence_kind THEN RETURN 'invalid'; END IF;
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
  ) THEN RETURN 'prerequisite_required'; END IF;
  IF definition_row.evidence_kind = 'paper-first-buy' THEN
    IF NOT EXISTS (SELECT 1 FROM trimmy.career_first_confirmed_buys b
        WHERE b.user_id = selected_user AND b.order_id = selected_evidence
          AND b.confirmed_at = observed_at) THEN RETURN 'evidence_missing'; END IF;
  ELSIF definition_row.evidence_kind = 'paper-first-reason' THEN
    IF NOT EXISTS (SELECT 1 FROM trimmy.career_trade_reasons r
        WHERE r.user_id = selected_user AND r.order_id = selected_evidence
          AND r.saved_at = observed_at) THEN RETURN 'evidence_missing'; END IF;
  ELSIF definition_row.evidence_kind <> 'server-red-day-hold' THEN RETURN 'invalid';
  END IF;
  completed_date := trimmy.career_local_date(selected_user, observed_at);
  BEGIN
    next_revision := trimmy.career_record_activity(selected_user, completed_date, 20, observed_at);
  EXCEPTION WHEN numeric_value_out_of_range THEN RETURN 'revision_exhausted';
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
  INSERT INTO trimmy.career_activity_events(user_id, activity_kind, source_id, observed_at)
  VALUES (selected_user, 'mission', generated_completion, observed_at);
  RETURN 'completed';
END;
$$;

CREATE OR REPLACE FUNCTION trimmy.check_career_mission_ledger_pair() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  IF TG_TABLE_NAME = 'career_mission_completions' THEN
    IF NOT EXISTS (SELECT 1 FROM trimmy.career_trim_ledger l
      WHERE l.user_id = NEW.user_id AND l.career_revision = NEW.career_revision
        AND l.entry_kind = 'mission' AND l.source_id = NEW.completion_id
        AND l.trims = NEW.trims_awarded
        AND l.awarded_on = trimmy.career_local_date(NEW.user_id, NEW.completed_at)
        AND l.created_at = NEW.completed_at) THEN
      RAISE EXCEPTION 'Mission completion and Trims ledger do not agree'
        USING ERRCODE = '23514', CONSTRAINT = 'career_mission_ledger_pair';
    END IF;
  ELSIF NEW.entry_kind = 'mission' AND NOT EXISTS (
    SELECT 1 FROM trimmy.career_mission_completions c
    WHERE c.user_id = NEW.user_id AND c.career_revision = NEW.career_revision
      AND c.completion_id = NEW.source_id AND c.trims_awarded = NEW.trims
      AND trimmy.career_local_date(c.user_id, c.completed_at) = NEW.awarded_on
      AND c.completed_at = NEW.created_at
  ) THEN
    RAISE EXCEPTION 'Mission Trims require a matching completion'
      USING ERRCODE = '23514', CONSTRAINT = 'career_mission_ledger_pair';
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION trimmy.career_reason_mission() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE completion_outcome text;
BEGIN
  INSERT INTO trimmy.career_activity_events(user_id, activity_kind, source_id, observed_at)
  VALUES (NEW.user_id, 'trade-reason', NEW.order_id, NEW.saved_at);
  SELECT trimmy.career_complete_mission(NEW.user_id, 'write-a-reason',
    'paper-first-reason', NEW.order_id, NEW.saved_at) INTO completion_outcome;
  IF completion_outcome NOT IN ('completed', 'already_completed') THEN
    RAISE EXCEPTION 'Written-reason mission could not be recorded'
      USING ERRCODE = '23514', CONSTRAINT = 'career_written_reason_mission';
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION trimmy.career_trade_reason_put(
  selected_user uuid,
  selected_mutation uuid,
  selected_hash text,
  selected_order uuid,
  selected_note text
) RETURNS TABLE (
  outcome text,
  order_id uuid,
  asset_id text,
  variant_mint text,
  note text,
  trims_awarded integer,
  daily_award_number smallint,
  saved_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE account_status text; order_row trimmy.paper_orders%ROWTYPE;
DECLARE receipt_row trimmy.career_reason_mutation_receipts%ROWTYPE;
DECLARE observed_at timestamptz := date_trunc('milliseconds', clock_timestamp());
DECLARE selected_time_zone text; today date; awarded_count integer; rolling_count integer;
DECLARE awarded integer; award_number smallint; career_revision bigint;
BEGIN
  IF selected_user IS NULL OR selected_mutation IS NULL OR selected_order IS NULL
      OR selected_hash IS NULL OR selected_hash !~ '^[a-f0-9]{64}$'
      OR selected_note IS NULL OR selected_note <> btrim(selected_note)
      OR char_length(selected_note) NOT BETWEEN 1 AND 180 OR selected_note ~ '[[:cntrl:]]' THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::text, NULL::text, NULL::text,
      NULL::integer, NULL::smallint, NULL::timestamptz;
    RETURN;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('trimmy.career:' || selected_user::text, 0));
  SELECT u.status INTO account_status FROM trimmy.users u WHERE u.id = selected_user FOR UPDATE;
  IF account_status IS DISTINCT FROM 'active' THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::uuid, NULL::text, NULL::text, NULL::text,
      NULL::integer, NULL::smallint, NULL::timestamptz; RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM trimmy.product_profiles p WHERE p.user_id = selected_user) THEN
    RETURN QUERY SELECT 'profile_required'::text, NULL::uuid, NULL::text, NULL::text, NULL::text,
      NULL::integer, NULL::smallint, NULL::timestamptz; RETURN;
  END IF;
  SELECT r.* INTO receipt_row FROM trimmy.career_reason_mutation_receipts r
    WHERE r.user_id = selected_user AND r.mutation_id = selected_mutation;
  IF FOUND THEN
    IF receipt_row.request_hash <> selected_hash THEN
      RETURN QUERY SELECT 'idempotency_conflict'::text, NULL::uuid, NULL::text, NULL::text,
        NULL::text, NULL::integer, NULL::smallint, NULL::timestamptz;
    ELSE
      RETURN QUERY SELECT 'saved'::text, receipt_row.order_id, receipt_row.asset_id,
        receipt_row.variant_mint::text, receipt_row.note, receipt_row.trims_awarded,
        receipt_row.daily_award_number, receipt_row.saved_at;
    END IF;
    RETURN;
  END IF;
  SELECT o.* INTO order_row FROM trimmy.paper_orders o
    WHERE o.user_id = selected_user AND o.id = selected_order;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'order_missing'::text, NULL::uuid, NULL::text, NULL::text, NULL::text,
      NULL::integer, NULL::smallint, NULL::timestamptz; RETURN;
  END IF;
  IF order_row.action <> 'buy' THEN
    RETURN QUERY SELECT 'buy_required'::text, NULL::uuid, NULL::text, NULL::text, NULL::text,
      NULL::integer, NULL::smallint, NULL::timestamptz; RETURN;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM trimmy.paper_positions p
    WHERE p.user_id = selected_user AND p.asset_id = order_row.asset_id
      AND p.variant_mint = order_row.variant_mint AND p.quantity_micros > 0
  ) THEN
    RETURN QUERY SELECT 'position_required'::text, NULL::uuid, NULL::text, NULL::text, NULL::text,
      NULL::integer, NULL::smallint, NULL::timestamptz; RETURN;
  END IF;
  IF EXISTS (SELECT 1 FROM trimmy.career_trade_reasons r WHERE r.order_id = selected_order) THEN
    RETURN QUERY SELECT 'reason_exists'::text, NULL::uuid, NULL::text, NULL::text, NULL::text,
      NULL::integer, NULL::smallint, NULL::timestamptz; RETURN;
  END IF;
  selected_time_zone := trimmy.career_time_zone(selected_user);
  today := (observed_at AT TIME ZONE selected_time_zone)::date;
  SELECT count(*) FILTER (
      WHERE (r.saved_at AT TIME ZONE selected_time_zone)::date = today
    )::integer,
    count(*) FILTER (WHERE r.saved_at > observed_at - interval '24 hours')::integer
    INTO awarded_count, rolling_count
    FROM trimmy.career_trade_reasons r
    WHERE r.user_id = selected_user AND r.trims_awarded = 10;
  IF awarded_count < 3 AND rolling_count < 3 THEN
    awarded := 10; award_number := (awarded_count + 1)::smallint;
  ELSE
    awarded := 0; award_number := NULL;
  END IF;
  BEGIN
    career_revision := trimmy.career_record_activity(selected_user, today, awarded, observed_at);
  EXCEPTION WHEN numeric_value_out_of_range THEN
    RETURN QUERY SELECT 'revision_exhausted'::text, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::integer, NULL::smallint, NULL::timestamptz; RETURN;
  END;
  INSERT INTO trimmy.career_trade_reasons(
    order_id, user_id, asset_id, variant_mint, note, trims_awarded, daily_award_number, saved_at)
  VALUES (selected_order, selected_user, order_row.asset_id, order_row.variant_mint,
    selected_note, awarded, award_number, observed_at);
  IF awarded > 0 THEN
    INSERT INTO trimmy.career_trim_ledger(
      user_id, career_revision, entry_kind, source_id, trims, awarded_on, created_at)
    VALUES (selected_user, career_revision, 'paper-reason', selected_order, awarded, today, observed_at);
  END IF;
  INSERT INTO trimmy.career_reason_mutation_receipts(
    user_id, mutation_id, request_hash, order_id, asset_id, variant_mint, note,
    trims_awarded, daily_award_number, saved_at)
  VALUES (selected_user, selected_mutation, selected_hash, selected_order,
    order_row.asset_id, order_row.variant_mint, selected_note, awarded, award_number, observed_at);
  RETURN QUERY SELECT 'saved'::text, selected_order, order_row.asset_id,
    order_row.variant_mint::text, selected_note, awarded, award_number, observed_at;
END;
$$;

CREATE OR REPLACE FUNCTION trimmy.career_promote(
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
      NULL::bigint, NULL::integer, NULL::timestamptz; RETURN;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('trimmy.career:' || selected_user::text, 0));
  SELECT u.status INTO account_status FROM trimmy.users u WHERE u.id = selected_user FOR UPDATE;
  IF account_status IS DISTINCT FROM 'active' THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::uuid, NULL::text, NULL::text,
      NULL::bigint, NULL::integer, NULL::timestamptz; RETURN;
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
      NULL::bigint, NULL::integer, NULL::timestamptz; RETURN;
  END IF;
  IF trimmy.career_rank_number(selected_target) <> trimmy.career_rank_number(current_row.rank_id) + 1 THEN
    RETURN QUERY SELECT 'rank_mismatch'::text, NULL::uuid, NULL::text, NULL::text,
      NULL::bigint, NULL::integer, NULL::timestamptz; RETURN;
  END IF;
  required_threshold := CASE selected_target
    WHEN 'analyst' THEN 300 WHEN 'trader' THEN 900 WHEN 'senior-trader' THEN 2000
    WHEN 'partner' THEN 4500 WHEN 'legend' THEN 10000 END;
  IF current_row.trims_total < required_threshold THEN
    RETURN QUERY SELECT 'threshold_required'::text, NULL::uuid, NULL::text, NULL::text,
      NULL::bigint, NULL::integer, NULL::timestamptz; RETURN;
  END IF;
  SELECT d.id INTO required_mission FROM trimmy.career_mission_definitions d
    WHERE d.mission_kind = 'promotion' AND d.chapter_rank = current_row.rank_id
      AND d.promotes_to_rank = selected_target;
  IF required_mission IS NULL OR NOT EXISTS (
    SELECT 1 FROM trimmy.career_mission_completions c
    WHERE c.user_id = selected_user AND c.mission_id = required_mission
  ) THEN
    RETURN QUERY SELECT 'mission_required'::text, NULL::uuid, NULL::text, NULL::text,
      NULL::bigint, NULL::integer, NULL::timestamptz; RETURN;
  END IF;
  IF current_row.revision >= 9007199254740991
      OR current_row.trims_total > 9007199254740991 - 100 THEN
    RETURN QUERY SELECT 'revision_exhausted'::text, NULL::uuid, NULL::text, NULL::text,
      NULL::bigint, NULL::integer, NULL::timestamptz; RETURN;
  END IF;
  observed_at := greatest(date_trunc('milliseconds', clock_timestamp()),
    current_row.updated_at + interval '1 millisecond');
  next_revision := current_row.revision + 1;
  UPDATE trimmy.career_profiles SET revision = next_revision,
    trims_total = current_row.trims_total + 100,
    rank_id = selected_target, updated_at = observed_at
  WHERE user_id = selected_user;
  INSERT INTO trimmy.career_trim_ledger(
    user_id, career_revision, entry_kind, source_id, trims, awarded_on, created_at)
  VALUES (selected_user, next_revision, 'promotion', selected_mutation, 100,
    trimmy.career_local_date(selected_user, observed_at), observed_at);
  INSERT INTO trimmy.career_promotion_receipts(
    user_id, mutation_id, request_hash, from_rank, to_rank, mission_id,
    career_revision, trims_awarded, promoted_at)
  VALUES (selected_user, selected_mutation, selected_hash, current_row.rank_id,
    selected_target, required_mission, next_revision, 100, observed_at);
  RETURN QUERY SELECT 'promoted'::text, selected_mutation, current_row.rank_id,
    selected_target, next_revision, 100, observed_at;
END;
$$;

CREATE OR REPLACE FUNCTION trimmy.check_career_promotion_pairs() RETURNS trigger
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
        AND l.awarded_on = trimmy.career_local_date(NEW.user_id, NEW.promoted_at)) THEN
      RAISE EXCEPTION 'Promotion receipt and Trims ledger do not agree'
        USING ERRCODE = '23514', CONSTRAINT = 'career_promotion_ledger_pair';
    END IF;
  ELSIF NEW.entry_kind = 'promotion' AND NOT EXISTS (
    SELECT 1 FROM trimmy.career_promotion_receipts r
    WHERE r.user_id = NEW.user_id AND r.career_revision = NEW.career_revision
      AND r.mutation_id = NEW.source_id AND r.trims_awarded = NEW.trims
      AND r.promoted_at = NEW.created_at
      AND trimmy.career_local_date(r.user_id, r.promoted_at) = NEW.awarded_on
  ) THEN
    RAISE EXCEPTION 'Promotion Trims require a matching receipt'
      USING ERRCODE = '23514', CONSTRAINT = 'career_promotion_ledger_pair';
  END IF;
  RETURN NULL;
END;
$$;

CREATE FUNCTION trimmy.career_streak_get(
  selected_user uuid,
  selected_time_zone text,
  selected_today date
) RETURNS TABLE (streak_days integer, streak_status text, last_active_date date)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE activity_day date; previous_day date; selected_last date; selected_days integer := 0;
BEGIN
  IF selected_user IS NULL OR selected_today IS NULL
      OR NOT trimmy.career_time_zone_allowed(selected_time_zone) THEN
    RETURN QUERY SELECT 0, 'not-started'::text, NULL::date; RETURN;
  END IF;
  FOR activity_day IN
    SELECT DISTINCT (e.observed_at AT TIME ZONE selected_time_zone)::date
    FROM trimmy.career_activity_events e
    WHERE e.user_id = selected_user
      AND (e.observed_at AT TIME ZONE selected_time_zone)::date <= selected_today
    ORDER BY 1 DESC
  LOOP
    IF selected_last IS NULL THEN
      selected_last := activity_day;
      IF selected_last < selected_today - 2 THEN
        RETURN QUERY SELECT 0, 'not-started'::text, NULL::date; RETURN;
      END IF;
      selected_days := 1; previous_day := activity_day;
    ELSIF previous_day - activity_day <= 2 THEN
      selected_days := selected_days + 1; previous_day := activity_day;
    ELSE
      EXIT;
    END IF;
  END LOOP;
  IF selected_last IS NULL THEN
    RETURN QUERY SELECT 0, 'not-started'::text, NULL::date;
  ELSIF selected_last = selected_today THEN
    RETURN QUERY SELECT selected_days, 'active'::text, selected_last;
  ELSIF selected_last = selected_today - 1 THEN
    RETURN QUERY SELECT selected_days, 'at-risk'::text, selected_last;
  ELSE
    RETURN QUERY SELECT selected_days, 'grace'::text, selected_last;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_streak_get(uuid, text, date) FROM PUBLIC;

CREATE OR REPLACE FUNCTION trimmy.career_summary_get(selected_user uuid)
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
DECLARE selected_time_zone text; today date; week_start date;
DECLARE current_threshold integer; next_id text; next_label text; next_threshold integer;
DECLARE current_label text; effective_streak integer; effective_status text; effective_last date;
DECLARE total_today bigint; total_week bigint; started boolean;
DECLARE first_buy trimmy.paper_orders%ROWTYPE;
BEGIN
  selected_time_zone := trimmy.career_time_zone(selected_user);
  today := (clock_timestamp() AT TIME ZONE selected_time_zone)::date;
  week_start := date_trunc('week', today::timestamp)::date;
  IF selected_user IS NULL THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::bigint, NULL::bigint, NULL::bigint, NULL::bigint,
      NULL::text, NULL::text, NULL::text, NULL::integer, NULL::text, NULL::text, NULL::integer,
      NULL::bigint, NULL::boolean, NULL::integer, NULL::text, NULL::date, today, NULL::timestamptz,
      NULL::boolean, NULL::uuid, NULL::text, NULL::text, NULL::text, NULL::text,
      NULL::timestamptz; RETURN;
  END IF;
  SELECT u.status INTO account_status FROM trimmy.users u WHERE u.id = selected_user;
  IF account_status IS DISTINCT FROM 'active' THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::bigint, NULL::bigint, NULL::bigint, NULL::bigint,
      NULL::text, NULL::text, NULL::text, NULL::integer, NULL::text, NULL::text, NULL::integer,
      NULL::bigint, NULL::boolean, NULL::integer, NULL::text, NULL::date, today, NULL::timestamptz,
      NULL::boolean, NULL::uuid, NULL::text, NULL::text, NULL::text, NULL::text,
      NULL::timestamptz; RETURN;
  END IF;
  SELECT EXISTS (SELECT 1 FROM trimmy.career_starts s WHERE s.user_id = selected_user) INTO started;
  SELECT o.* INTO first_buy FROM trimmy.career_first_confirmed_buys b
    JOIN trimmy.paper_orders o ON o.id = b.order_id AND o.user_id = b.user_id
    WHERE b.user_id = selected_user;
  SELECT p.* INTO current_row FROM trimmy.career_profiles p WHERE p.user_id = selected_user;
  SELECT s.streak_days, s.streak_status, s.last_active_date
    INTO effective_streak, effective_status, effective_last
    FROM trimmy.career_streak_get(selected_user, selected_time_zone, today) s;
  IF current_row.user_id IS NULL THEN
    RETURN QUERY SELECT 'found'::text, 0::bigint, 0::bigint, 0::bigint, 0::bigint,
      'rookie'::text, 'Rookie'::text, '10000'::text, 0::integer,
      'analyst'::text, 'Analyst'::text, 300::integer, 300::bigint, false,
      effective_streak, effective_status, effective_last, today, NULL::timestamptz,
      started, first_buy.id, first_buy.asset_id, first_buy.variant_mint::text,
      first_buy.symbol, first_buy.quantity_micros::text, first_buy.committed_at; RETURN;
  END IF;
  SELECT coalesce(sum(l.trims) FILTER (
      WHERE (l.created_at AT TIME ZONE selected_time_zone)::date = today), 0)::bigint,
    coalesce(sum(l.trims) FILTER (
      WHERE (l.created_at AT TIME ZONE selected_time_zone)::date BETWEEN week_start AND today), 0)::bigint
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
  RETURN QUERY SELECT 'found'::text, current_row.revision, current_row.trims_total,
    total_today, total_week, current_row.rank_id, current_label, '10000'::text,
    current_threshold, next_id, next_label, next_threshold,
    CASE WHEN next_threshold IS NULL THEN NULL::bigint
      ELSE greatest(0::bigint, next_threshold::bigint - current_row.trims_total) END,
    CASE WHEN next_threshold IS NULL THEN false
      ELSE current_row.trims_total >= next_threshold END,
    effective_streak, effective_status, effective_last, today, current_row.updated_at,
    started, first_buy.id, first_buy.asset_id, first_buy.variant_mint::text,
    first_buy.symbol, first_buy.quantity_micros::text, first_buy.committed_at;
END;
$$;

CREATE FUNCTION trimmy.career_day_context_get(selected_user uuid)
RETURNS TABLE (
  outcome text,
  revision bigint,
  time_zone text,
  configured boolean,
  server_date date,
  next_day_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE account_status text; current_row trimmy.career_day_settings%ROWTYPE;
DECLARE observed_at timestamptz := date_trunc('milliseconds', clock_timestamp());
BEGIN
  IF selected_user IS NULL THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::bigint, NULL::text, NULL::boolean,
      NULL::date, NULL::timestamptz, NULL::timestamptz, NULL::timestamptz; RETURN;
  END IF;
  SELECT u.status INTO account_status FROM trimmy.users u WHERE u.id = selected_user;
  IF account_status IS DISTINCT FROM 'active' THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::bigint, NULL::text, NULL::boolean,
      NULL::date, NULL::timestamptz, NULL::timestamptz, NULL::timestamptz; RETURN;
  END IF;
  SELECT s.* INTO current_row FROM trimmy.career_day_settings s WHERE s.user_id = selected_user;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'storage_missing'::text, NULL::bigint, NULL::text, NULL::boolean,
      NULL::date, NULL::timestamptz, NULL::timestamptz, NULL::timestamptz; RETURN;
  END IF;
  RETURN QUERY SELECT 'found'::text, current_row.revision, current_row.time_zone,
    current_row.configured, (observed_at AT TIME ZONE current_row.time_zone)::date,
    trimmy.career_next_day_at(current_row.time_zone, observed_at),
    current_row.created_at, current_row.updated_at;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_day_context_get(uuid) FROM PUBLIC;

CREATE FUNCTION trimmy.career_day_context_put(
  selected_user uuid,
  selected_mutation uuid,
  selected_hash text,
  selected_base_revision bigint,
  selected_time_zone text
) RETURNS TABLE (
  outcome text,
  revision bigint,
  time_zone text,
  configured boolean,
  server_date date,
  next_day_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE account_status text; current_row trimmy.career_day_settings%ROWTYPE;
DECLARE receipt_row trimmy.career_day_setting_receipts%ROWTYPE;
DECLARE observed_at timestamptz := date_trunc('milliseconds', clock_timestamp());
DECLARE next_revision bigint; response_date date;
BEGIN
  IF selected_user IS NULL OR selected_mutation IS NULL
      OR selected_hash IS NULL OR selected_hash !~ '^[a-f0-9]{64}$'
      OR selected_base_revision IS NULL OR selected_base_revision < 1
      OR selected_base_revision > 9007199254740991
      OR NOT trimmy.career_time_zone_allowed(selected_time_zone) THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::bigint, NULL::text, NULL::boolean,
      NULL::date, NULL::timestamptz, NULL::timestamptz, NULL::timestamptz; RETURN;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('trimmy.career:' || selected_user::text, 0));
  SELECT u.status INTO account_status FROM trimmy.users u WHERE u.id = selected_user FOR UPDATE;
  IF account_status IS DISTINCT FROM 'active' THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::bigint, NULL::text, NULL::boolean,
      NULL::date, NULL::timestamptz, NULL::timestamptz, NULL::timestamptz; RETURN;
  END IF;
  SELECT r.* INTO receipt_row FROM trimmy.career_day_setting_receipts r
    WHERE r.user_id = selected_user AND r.mutation_id = selected_mutation;
  IF FOUND THEN
    IF receipt_row.request_hash <> selected_hash THEN
      RETURN QUERY SELECT 'idempotency_conflict'::text, NULL::bigint, NULL::text, NULL::boolean,
        NULL::date, NULL::timestamptz, NULL::timestamptz, NULL::timestamptz;
    ELSE
      RETURN QUERY SELECT 'saved'::text, receipt_row.revision, receipt_row.time_zone,
        receipt_row.configured, receipt_row.server_date, receipt_row.next_day_at, receipt_row.created_at,
        receipt_row.updated_at;
    END IF;
    RETURN;
  END IF;
  SELECT s.* INTO current_row FROM trimmy.career_day_settings s
    WHERE s.user_id = selected_user FOR UPDATE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'storage_missing'::text, NULL::bigint, NULL::text, NULL::boolean,
      NULL::date, NULL::timestamptz, NULL::timestamptz, NULL::timestamptz; RETURN;
  END IF;
  IF current_row.revision <> selected_base_revision THEN
    RETURN QUERY SELECT 'revision_conflict'::text, current_row.revision, current_row.time_zone,
      current_row.configured, (observed_at AT TIME ZONE current_row.time_zone)::date,
      trimmy.career_next_day_at(current_row.time_zone, observed_at),
      current_row.created_at, current_row.updated_at; RETURN;
  END IF;
  IF current_row.configured AND current_row.time_zone <> selected_time_zone
      AND current_row.updated_at > observed_at - interval '24 hours' THEN
    RETURN QUERY SELECT 'change_too_soon'::text, current_row.revision, current_row.time_zone,
      current_row.configured, (observed_at AT TIME ZONE current_row.time_zone)::date,
      trimmy.career_next_day_at(current_row.time_zone, observed_at),
      current_row.created_at, current_row.updated_at; RETURN;
  END IF;
  IF current_row.configured AND current_row.time_zone = selected_time_zone THEN
    response_date := (observed_at AT TIME ZONE current_row.time_zone)::date;
  ELSE
    IF current_row.revision >= 9007199254740991 THEN
      RETURN QUERY SELECT 'revision_exhausted'::text, NULL::bigint, NULL::text, NULL::boolean,
        NULL::date, NULL::timestamptz, NULL::timestamptz, NULL::timestamptz; RETURN;
    END IF;
    next_revision := current_row.revision + 1;
    observed_at := greatest(observed_at, current_row.updated_at + interval '1 millisecond');
    UPDATE trimmy.career_day_settings SET revision = next_revision,
      time_zone = selected_time_zone, configured = true, updated_at = observed_at
    WHERE user_id = selected_user RETURNING * INTO current_row;
    response_date := (observed_at AT TIME ZONE selected_time_zone)::date;
  END IF;
  INSERT INTO trimmy.career_day_setting_receipts(
    user_id, mutation_id, request_hash, revision, time_zone, configured,
    server_date, next_day_at, created_at, updated_at)
  VALUES (selected_user, selected_mutation, selected_hash, current_row.revision,
    current_row.time_zone, current_row.configured, response_date,
    trimmy.career_next_day_at(current_row.time_zone, observed_at),
    current_row.created_at, current_row.updated_at);
  RETURN QUERY SELECT 'saved'::text, current_row.revision, current_row.time_zone,
    current_row.configured, response_date,
    trimmy.career_next_day_at(current_row.time_zone, observed_at),
    current_row.created_at, current_row.updated_at;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_day_context_put(uuid, uuid, text, bigint, text) FROM PUBLIC;

-- Flush backfill and default-setting pair checks before changing table
-- security metadata.
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

ALTER TABLE trimmy.career_day_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_day_settings FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_day_setting_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_day_setting_receipts FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_activity_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_activity_events FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE trimmy.career_day_settings, trimmy.career_day_setting_receipts,
  trimmy.career_activity_events FROM PUBLIC;

INSERT INTO trimmy.schema_migrations(version) VALUES ('0019_career_local_day');
COMMIT;
