-- 0021: trusted, append-only canonical market evidence for the Rookie
-- hold-through-red-day mission. Only a separately granted worker capability
-- role can call the four bounded entry functions added here. It receives no
-- table privilege, and the public API role receives no new access.
BEGIN;

CREATE TABLE trimmy.career_red_day_provider_observations (
  observation_id uuid PRIMARY KEY,
  request_hash trimmy.sha256_hex NOT NULL,
  provider text COLLATE "C" NOT NULL CHECK (provider = 'tokens-xyz-v1'),
  verifier_version text COLLATE "C" NOT NULL
    CHECK (verifier_version = 'tokens-canonical-red-day-v1'),
  asset_id text COLLATE "C" NOT NULL CHECK (
    asset_id ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND length(asset_id) <= 100),
  listed_symbol text COLLATE "C" CHECK (
    listed_symbol ~ '^[A-Z][A-Z0-9.-]{0,14}$'),
  observation_status text COLLATE "C" NOT NULL CHECK (observation_status IN (
    'verified-red', 'verified-not-red', 'unavailable', 'rejected')),
  source text COLLATE "C" CHECK (source = 'clickhouse_stock'),
  previous_market_date date,
  market_date date,
  previous_close_text text COLLATE "C" CHECK (
    octet_length(previous_close_text) <= 128
    AND previous_close_text ~ '^(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?([0-9]{1,2}|100))?$'),
  current_close_text text COLLATE "C" CHECK (
    octet_length(current_close_text) <= 128
    AND current_close_text ~ '^(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?([0-9]{1,2}|100))?$'),
  provider_as_of timestamptz,
  provider_last_fetched_at timestamptz,
  reason_code text COLLATE "C" CHECK (reason_code IN (
    'provider-auth-failed', 'provider-rate-limited', 'provider-unavailable',
    'provider-timeout', 'response-invalid', 'identity-mismatch',
    'source-mismatch', 'stale-provider-data', 'no-new-market-session',
    'asset-not-in-catalog')),
  detail_request_id uuid NOT NULL,
  chart_request_id uuid,
  detail_provider_request_id text CHECK (
    length(detail_provider_request_id) BETWEEN 1 AND 160
    AND detail_provider_request_id = btrim(detail_provider_request_id)
    AND detail_provider_request_id !~ '[[:cntrl:]]'),
  chart_provider_request_id text CHECK (
    length(chart_provider_request_id) BETWEEN 1 AND 160
    AND chart_provider_request_id = btrim(chart_provider_request_id)
    AND chart_provider_request_id !~ '[[:cntrl:]]'),
  detail_path text COLLATE "C" NOT NULL CHECK (
    detail_path = '/v1/assets/' || asset_id),
  chart_path text COLLATE "C" CHECK (
    length(chart_path) BETWEEN 1 AND 300
    AND chart_path ~ ('^/v1/assets/' || asset_id
      || '/price-chart\?interval=1D&from=[1-9][0-9]{9}&to=[1-9][0-9]{9}$')),
  detail_response_sha256 trimmy.sha256_hex,
  chart_response_sha256 trimmy.sha256_hex,
  observed_at timestamptz NOT NULL CHECK (isfinite(observed_at)),
  CHECK ((observation_status IN ('verified-red', 'verified-not-red')) =
    (listed_symbol IS NOT NULL AND source IS NOT NULL
      AND previous_market_date IS NOT NULL AND market_date IS NOT NULL
      AND previous_close_text IS NOT NULL AND current_close_text IS NOT NULL
      AND provider_as_of IS NOT NULL AND isfinite(provider_as_of)
      AND provider_last_fetched_at IS NOT NULL AND isfinite(provider_last_fetched_at)
      AND reason_code IS NULL AND chart_request_id IS NOT NULL
      AND chart_path IS NOT NULL AND detail_response_sha256 IS NOT NULL
      AND chart_response_sha256 IS NOT NULL)),
  CHECK (observation_status IN ('verified-red', 'verified-not-red')
    OR source IS NULL AND previous_market_date IS NULL AND market_date IS NULL
      AND previous_close_text IS NULL AND current_close_text IS NULL
      AND provider_as_of IS NULL AND provider_last_fetched_at IS NULL
      AND reason_code IS NOT NULL),
  CHECK (chart_request_id IS NOT NULL OR chart_provider_request_id IS NULL
    AND chart_path IS NULL AND chart_response_sha256 IS NULL),
  CHECK (previous_market_date IS NULL OR previous_market_date < market_date),
  CHECK (previous_close_text IS NULL OR previous_close_text::numeric > 0),
  CHECK (current_close_text IS NULL OR current_close_text::numeric > 0),
  CHECK (observation_status <> 'verified-red'
    OR current_close_text::numeric < previous_close_text::numeric),
  CHECK (observation_status <> 'verified-not-red'
    OR current_close_text::numeric >= previous_close_text::numeric)
);

CREATE INDEX career_red_day_observations_asset_time
  ON trimmy.career_red_day_provider_observations(
    asset_id, observed_at DESC, observation_id);

CREATE TABLE trimmy.career_red_day_sessions (
  observation_id uuid PRIMARY KEY REFERENCES trimmy.career_red_day_provider_observations(observation_id),
  provider text COLLATE "C" NOT NULL CHECK (provider = 'tokens-xyz-v1'),
  verifier_version text COLLATE "C" NOT NULL
    CHECK (verifier_version = 'tokens-canonical-red-day-v1'),
  asset_id text COLLATE "C" NOT NULL CHECK (
    asset_id ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND length(asset_id) <= 100),
  market_date date NOT NULL,
  processing_cursor_user_id uuid,
  processing_cursor_variant_mint trimmy.solana_address,
  processing_complete boolean NOT NULL DEFAULT false,
  processing_completed_at timestamptz CHECK (
    processing_completed_at IS NULL OR isfinite(processing_completed_at)),
  CHECK ((processing_cursor_user_id IS NULL) =
    (processing_cursor_variant_mint IS NULL)),
  CHECK (processing_complete = (processing_completed_at IS NOT NULL)),
  UNIQUE (provider, asset_id, market_date, verifier_version)
);

CREATE INDEX career_red_day_pending_sessions
  ON trimmy.career_red_day_sessions(market_date, observation_id)
  WHERE processing_complete = false;

-- Mutable scheduling state is backed by the immutable observation it cites.
-- It keeps failed assets from growing the audit log on every scheduler tick
-- and rotates never-attempted assets ahead of previously attempted assets.
CREATE TABLE trimmy.career_red_day_asset_state (
  asset_id text COLLATE "C" PRIMARY KEY CHECK (
    asset_id ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND length(asset_id) <= 100),
  last_observation_id uuid NOT NULL
    REFERENCES trimmy.career_red_day_provider_observations(observation_id),
  last_attempt_at timestamptz NOT NULL CHECK (isfinite(last_attempt_at)),
  next_attempt_at timestamptz NOT NULL CHECK (
    isfinite(next_attempt_at) AND next_attempt_at >= last_attempt_at),
  consecutive_failures integer NOT NULL CHECK (
    consecutive_failures BETWEEN 0 AND 1000000),
  last_status text COLLATE "C" NOT NULL CHECK (last_status IN (
    'verified-red', 'verified-not-red', 'unavailable', 'rejected')),
  last_reason_code text COLLATE "C" CHECK (last_reason_code IN (
    'provider-auth-failed', 'provider-rate-limited', 'provider-unavailable',
    'provider-timeout', 'response-invalid', 'identity-mismatch',
    'source-mismatch', 'stale-provider-data', 'no-new-market-session',
    'asset-not-in-catalog')),
  updated_at timestamptz NOT NULL CHECK (isfinite(updated_at)),
  CHECK ((last_status IN ('unavailable', 'rejected')) =
    (last_reason_code IS NOT NULL))
);
CREATE INDEX career_red_day_asset_retry
  ON trimmy.career_red_day_asset_state(next_attempt_at, last_attempt_at, asset_id);

CREATE TABLE trimmy.career_red_day_provider_state (
  provider text COLLATE "C" PRIMARY KEY CHECK (provider = 'tokens-xyz-v1'),
  last_observation_id uuid NOT NULL
    REFERENCES trimmy.career_red_day_provider_observations(observation_id),
  last_attempt_at timestamptz NOT NULL CHECK (isfinite(last_attempt_at)),
  next_attempt_at timestamptz NOT NULL CHECK (
    isfinite(next_attempt_at) AND next_attempt_at >= last_attempt_at),
  cooldown_reason text COLLATE "C" CHECK (
    cooldown_reason IN ('provider-auth-failed', 'provider-rate-limited')),
  updated_at timestamptz NOT NULL CHECK (isfinite(updated_at))
);

CREATE TABLE trimmy.career_red_day_user_evidence (
  evidence_id uuid PRIMARY KEY,
  observation_id uuid NOT NULL REFERENCES trimmy.career_red_day_sessions(observation_id),
  user_id uuid NOT NULL REFERENCES trimmy.users(id),
  asset_id text COLLATE "C" NOT NULL CHECK (
    asset_id ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND length(asset_id) <= 100),
  variant_mint trimmy.solana_address NOT NULL,
  listed_symbol text COLLATE "C" NOT NULL CHECK (
    listed_symbol ~ '^[A-Z][A-Z0-9.-]{0,14}$'),
  market_date date NOT NULL,
  session_open_at timestamptz NOT NULL CHECK (isfinite(session_open_at)),
  session_close_at timestamptz NOT NULL CHECK (
    isfinite(session_close_at) AND session_close_at > session_open_at),
  opening_order_id uuid,
  opening_quantity_micros numeric(30,0) NOT NULL CHECK (
    opening_quantity_micros BETWEEN 0 AND 999999999999999),
  minimum_session_quantity_micros numeric(30,0) NOT NULL CHECK (
    minimum_session_quantity_micros BETWEEN 0 AND opening_quantity_micros),
  evidence_outcome text COLLATE "C" NOT NULL CHECK (
    evidence_outcome IN ('qualified', 'not-held-throughout')),
  reason_code text COLLATE "C" CHECK (
    reason_code IN ('not-positive-at-open', 'position-reached-zero')),
  recorded_at timestamptz NOT NULL CHECK (isfinite(recorded_at)),
  UNIQUE (observation_id, user_id, asset_id, variant_mint),
  FOREIGN KEY (opening_order_id, user_id) REFERENCES trimmy.paper_orders(id, user_id),
  CHECK ((evidence_outcome = 'qualified') =
    (opening_order_id IS NOT NULL AND opening_quantity_micros > 0
      AND minimum_session_quantity_micros > 0 AND reason_code IS NULL)),
  CHECK (evidence_outcome = 'qualified' OR reason_code IS NOT NULL)
);

CREATE TABLE trimmy.career_red_day_correction_reviews (
  review_observation_id uuid PRIMARY KEY
    REFERENCES trimmy.career_red_day_provider_observations(observation_id),
  canonical_observation_id uuid NOT NULL
    REFERENCES trimmy.career_red_day_sessions(observation_id),
  provider text COLLATE "C" NOT NULL CHECK (provider = 'tokens-xyz-v1'),
  asset_id text COLLATE "C" NOT NULL CHECK (
    asset_id ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND length(asset_id) <= 100),
  market_date date NOT NULL,
  identity_changed boolean NOT NULL,
  outcome_changed boolean NOT NULL,
  close_changed boolean NOT NULL,
  review_status text COLLATE "C" NOT NULL DEFAULT 'open' CHECK (review_status = 'open'),
  detected_at timestamptz NOT NULL CHECK (isfinite(detected_at)),
  CHECK (identity_changed OR outcome_changed OR close_changed),
  CHECK (review_observation_id <> canonical_observation_id)
);
CREATE INDEX career_red_day_open_corrections
  ON trimmy.career_red_day_correction_reviews(detected_at, review_observation_id)
  WHERE review_status = 'open';

CREATE UNIQUE INDEX career_red_day_one_qualification_per_user
  ON trimmy.career_red_day_user_evidence(user_id)
  WHERE evidence_outcome = 'qualified';
CREATE INDEX career_red_day_evidence_session_user
  ON trimmy.career_red_day_user_evidence(observation_id, user_id, variant_mint);
CREATE INDEX paper_orders_red_day_reconstruction
  ON trimmy.paper_orders(asset_id, user_id, variant_mint, committed_at, account_revision, id);

CREATE FUNCTION trimmy.career_red_day_session_open(selected_market_date date)
RETURNS timestamptz
LANGUAGE sql STABLE STRICT
SET search_path = pg_catalog, trimmy AS $$
  SELECT (selected_market_date::timestamp + time '09:30')
    AT TIME ZONE 'America/New_York';
$$;
REVOKE ALL ON FUNCTION trimmy.career_red_day_session_open(date) FROM PUBLIC;

CREATE FUNCTION trimmy.career_red_day_session_close(selected_market_date date)
RETURNS timestamptz
LANGUAGE sql STABLE STRICT
SET search_path = pg_catalog, trimmy AS $$
  SELECT (selected_market_date::timestamp + time '16:00')
    AT TIME ZONE 'America/New_York';
$$;
REVOKE ALL ON FUNCTION trimmy.career_red_day_session_close(date) FROM PUBLIC;

CREATE TRIGGER career_red_day_observations_append_only
  BEFORE UPDATE OR DELETE ON trimmy.career_red_day_provider_observations
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();
CREATE TRIGGER career_red_day_user_evidence_append_only
  BEFORE UPDATE OR DELETE ON trimmy.career_red_day_user_evidence
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();
CREATE TRIGGER career_red_day_correction_reviews_append_only
  BEFORE UPDATE OR DELETE ON trimmy.career_red_day_correction_reviews
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();

CREATE FUNCTION trimmy.guard_career_red_day_session_progress() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, trimmy AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'career_red_day_sessions rows are not deletable'
      USING ERRCODE = '55000';
  END IF;
  IF (NEW.observation_id, NEW.provider, NEW.verifier_version, NEW.asset_id,
      NEW.market_date) IS DISTINCT FROM
      (OLD.observation_id, OLD.provider, OLD.verifier_version, OLD.asset_id,
        OLD.market_date)
      OR OLD.processing_complete AND NOT NEW.processing_complete
      OR OLD.processing_completed_at IS NOT NULL
        AND NEW.processing_completed_at IS DISTINCT FROM OLD.processing_completed_at
      OR OLD.processing_cursor_user_id IS NOT NULL AND (
        NEW.processing_cursor_user_id IS NULL OR
        (NEW.processing_cursor_user_id, NEW.processing_cursor_variant_mint) <=
          (OLD.processing_cursor_user_id, OLD.processing_cursor_variant_mint)) THEN
    RAISE EXCEPTION 'career_red_day_sessions progress is immutable or non-monotonic'
      USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.guard_career_red_day_session_progress() FROM PUBLIC;
CREATE TRIGGER career_red_day_sessions_progress_only
  BEFORE UPDATE OR DELETE ON trimmy.career_red_day_sessions
  FOR EACH ROW EXECUTE FUNCTION trimmy.guard_career_red_day_session_progress();

CREATE FUNCTION trimmy.check_career_red_day_session_observation() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE observation_row trimmy.career_red_day_provider_observations%ROWTYPE;
BEGIN
  SELECT o.* INTO observation_row
  FROM trimmy.career_red_day_provider_observations o
  WHERE o.observation_id = NEW.observation_id;
  IF NOT FOUND OR observation_row.observation_status NOT IN ('verified-red', 'verified-not-red')
      OR (NEW.provider, NEW.verifier_version, NEW.asset_id, NEW.market_date)
        IS DISTINCT FROM
        (observation_row.provider, observation_row.verifier_version,
          observation_row.asset_id, observation_row.market_date) THEN
    RAISE EXCEPTION 'Canonical red-day session does not match its provider observation'
      USING ERRCODE = '23514', CONSTRAINT = 'career_red_day_session_observation';
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.check_career_red_day_session_observation() FROM PUBLIC;
CREATE CONSTRAINT TRIGGER career_red_day_session_observation_pair
  AFTER INSERT ON trimmy.career_red_day_sessions DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trimmy.check_career_red_day_session_observation();

CREATE FUNCTION trimmy.check_career_red_day_correction_review() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE canonical_row trimmy.career_red_day_provider_observations%ROWTYPE;
DECLARE review_row trimmy.career_red_day_provider_observations%ROWTYPE;
BEGIN
  SELECT o.* INTO canonical_row
  FROM trimmy.career_red_day_sessions s
  JOIN trimmy.career_red_day_provider_observations o
    ON o.observation_id = s.observation_id
  WHERE s.observation_id = NEW.canonical_observation_id;
  SELECT o.* INTO review_row
  FROM trimmy.career_red_day_provider_observations o
  WHERE o.observation_id = NEW.review_observation_id;
  IF canonical_row.observation_id IS NULL OR review_row.observation_id IS NULL
      OR canonical_row.observation_status NOT IN ('verified-red', 'verified-not-red')
      OR review_row.observation_status NOT IN ('verified-red', 'verified-not-red')
      OR (NEW.provider, NEW.asset_id, NEW.market_date) IS DISTINCT FROM
        (canonical_row.provider, canonical_row.asset_id, canonical_row.market_date)
      OR (review_row.provider, review_row.asset_id, review_row.market_date) IS DISTINCT FROM
        (canonical_row.provider, canonical_row.asset_id, canonical_row.market_date)
      OR NEW.identity_changed IS DISTINCT FROM (
        (canonical_row.listed_symbol, canonical_row.source,
          canonical_row.previous_market_date) IS DISTINCT FROM
        (review_row.listed_symbol, review_row.source,
          review_row.previous_market_date))
      OR NEW.outcome_changed IS DISTINCT FROM
        (canonical_row.observation_status <> review_row.observation_status)
      OR NEW.close_changed IS DISTINCT FROM
        (canonical_row.previous_close_text::numeric <>
          review_row.previous_close_text::numeric
        OR canonical_row.current_close_text::numeric <>
          review_row.current_close_text::numeric) THEN
    RAISE EXCEPTION 'Red-day correction review does not match its observations'
      USING ERRCODE = '23514', CONSTRAINT = 'career_red_day_correction_review';
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.check_career_red_day_correction_review() FROM PUBLIC;
CREATE CONSTRAINT TRIGGER career_red_day_correction_review_pair
  AFTER INSERT ON trimmy.career_red_day_correction_reviews
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trimmy.check_career_red_day_correction_review();

CREATE FUNCTION trimmy.check_career_red_day_user_evidence() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE observation_row trimmy.career_red_day_provider_observations%ROWTYPE;
DECLARE expected_open timestamptz; expected_close timestamptz;
DECLARE opening_row trimmy.paper_orders%ROWTYPE;
DECLARE expected_opening numeric := 0; expected_minimum numeric := 0;
DECLARE expected_outcome text; expected_reason text;
BEGIN
  SELECT o.* INTO observation_row
  FROM trimmy.career_red_day_sessions s
  JOIN trimmy.career_red_day_provider_observations o
    ON o.observation_id = s.observation_id
  WHERE s.observation_id = NEW.observation_id;
  IF NOT FOUND OR observation_row.observation_status <> 'verified-red'
      OR (NEW.asset_id, NEW.listed_symbol, NEW.market_date, NEW.recorded_at)
        IS DISTINCT FROM
        (observation_row.asset_id, observation_row.listed_symbol,
          observation_row.market_date, observation_row.observed_at) THEN
    RAISE EXCEPTION 'User red-day evidence does not match its market observation'
      USING ERRCODE = '23514', CONSTRAINT = 'career_red_day_user_evidence';
  END IF;
  expected_open := trimmy.career_red_day_session_open(NEW.market_date);
  expected_close := trimmy.career_red_day_session_close(NEW.market_date);
  IF (NEW.session_open_at, NEW.session_close_at)
      IS DISTINCT FROM (expected_open, expected_close) THEN
    RAISE EXCEPTION 'User red-day evidence has the wrong New York session window'
      USING ERRCODE = '23514', CONSTRAINT = 'career_red_day_user_evidence';
  END IF;
  SELECT o.* INTO opening_row
  FROM trimmy.paper_orders o
  WHERE o.user_id = NEW.user_id AND o.asset_id = NEW.asset_id
    AND o.variant_mint = NEW.variant_mint AND o.committed_at < expected_open
  ORDER BY o.committed_at DESC, o.account_revision DESC, o.id DESC
  LIMIT 1;
  IF FOUND THEN expected_opening := opening_row.position_quantity_after_micros; END IF;
  SELECT least(expected_opening, coalesce(min(o.position_quantity_after_micros), expected_opening))
    INTO expected_minimum
  FROM trimmy.paper_orders o
  WHERE o.user_id = NEW.user_id AND o.asset_id = NEW.asset_id
    AND o.variant_mint = NEW.variant_mint
    AND o.committed_at >= expected_open AND o.committed_at <= expected_close;
  IF expected_opening > 0 AND expected_minimum > 0 THEN
    expected_outcome := 'qualified'; expected_reason := NULL;
  ELSIF expected_opening <= 0 THEN
    expected_outcome := 'not-held-throughout'; expected_reason := 'not-positive-at-open';
  ELSE
    expected_outcome := 'not-held-throughout'; expected_reason := 'position-reached-zero';
  END IF;
  IF (NEW.opening_order_id, NEW.opening_quantity_micros,
      NEW.minimum_session_quantity_micros, NEW.evidence_outcome, NEW.reason_code)
      IS DISTINCT FROM
      (opening_row.id, expected_opening, expected_minimum, expected_outcome, expected_reason) THEN
    RAISE EXCEPTION 'User red-day evidence does not match immutable paper orders'
      USING ERRCODE = '23514', CONSTRAINT = 'career_red_day_user_evidence';
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.check_career_red_day_user_evidence() FROM PUBLIC;
CREATE CONSTRAINT TRIGGER career_red_day_user_evidence_proof
  AFTER INSERT ON trimmy.career_red_day_user_evidence DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trimmy.check_career_red_day_user_evidence();

CREATE FUNCTION trimmy.check_career_red_day_completion_pair() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE selected_user uuid; selected_evidence uuid;
BEGIN
  IF TG_TABLE_NAME = 'career_red_day_user_evidence' THEN
    IF NEW.evidence_outcome <> 'qualified' THEN RETURN NULL; END IF;
    selected_user := NEW.user_id; selected_evidence := NEW.evidence_id;
    IF NOT EXISTS (
      SELECT 1 FROM trimmy.career_mission_completions c
      WHERE c.user_id = selected_user AND c.mission_id = 'hold-through-red-day'
        AND c.evidence_kind = 'server-red-day-hold' AND c.evidence_id = selected_evidence
    ) THEN
      RAISE EXCEPTION 'Qualified red-day evidence requires its mission completion'
        USING ERRCODE = '23514', CONSTRAINT = 'career_red_day_completion_pair';
    END IF;
  ELSIF NEW.mission_id = 'hold-through-red-day'
      OR NEW.evidence_kind = 'server-red-day-hold' THEN
    IF NEW.mission_id <> 'hold-through-red-day'
        OR NEW.evidence_kind <> 'server-red-day-hold'
        OR NOT EXISTS (
          SELECT 1 FROM trimmy.career_red_day_user_evidence e
          WHERE e.evidence_id = NEW.evidence_id AND e.user_id = NEW.user_id
            AND e.evidence_outcome = 'qualified'
        ) THEN
      RAISE EXCEPTION 'Red-day mission completion requires qualified evidence'
        USING ERRCODE = '23514', CONSTRAINT = 'career_red_day_completion_pair';
    END IF;
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.check_career_red_day_completion_pair() FROM PUBLIC;
CREATE CONSTRAINT TRIGGER career_red_day_evidence_completion_pair
  AFTER INSERT ON trimmy.career_red_day_user_evidence DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trimmy.check_career_red_day_completion_pair();
CREATE CONSTRAINT TRIGGER career_red_day_completion_evidence_pair
  AFTER INSERT ON trimmy.career_mission_completions DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trimmy.check_career_red_day_completion_pair();

-- A production database cannot already contain this mission: it was locked in
-- every prior migration. Refuse activation if privileged manual data exists.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM trimmy.career_mission_completions
    WHERE mission_id = 'hold-through-red-day' OR evidence_kind = 'server-red-day-hold'
  ) THEN
    RAISE EXCEPTION 'Cannot activate red-day evidence over an existing unverified completion';
  END IF;
END;
$$;

-- Bind reason time after its serialization lock. This prevents a queued
-- request from later committing a pre-lock timestamp across a market close.
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
DECLARE observed_at timestamptz;
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
  observed_at := date_trunc('milliseconds', clock_timestamp());
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

CREATE OR REPLACE FUNCTION trimmy.career_server_mission_complete(
  selected_user uuid,
  selected_mission text,
  selected_evidence uuid,
  observed_at timestamptz
) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE evidence_row trimmy.career_red_day_user_evidence%ROWTYPE;
DECLARE evidence_type text; evidence_is_live boolean;
BEGIN
  IF selected_mission IS DISTINCT FROM 'hold-through-red-day' THEN RETURN 'locked'; END IF;
  SELECT d.evidence_kind, d.evidence_live INTO evidence_type, evidence_is_live
  FROM trimmy.career_mission_definitions d WHERE d.id = selected_mission;
  IF evidence_type IS DISTINCT FROM 'server-red-day-hold'
      OR evidence_is_live IS DISTINCT FROM true THEN RETURN 'locked'; END IF;
  SELECT e.* INTO evidence_row FROM trimmy.career_red_day_user_evidence e
  WHERE e.evidence_id = selected_evidence AND e.user_id = selected_user
    AND e.evidence_outcome = 'qualified';
  IF NOT FOUND OR evidence_row.recorded_at <> observed_at THEN RETURN 'evidence_missing'; END IF;
  RETURN trimmy.career_complete_mission(selected_user, selected_mission,
    evidence_type, selected_evidence, observed_at);
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_server_mission_complete(uuid, text, uuid, timestamptz) FROM PUBLIC;

CREATE FUNCTION trimmy.career_red_day_candidates(selected_limit integer)
RETURNS TABLE (asset_id text, after_market_date date)
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  IF selected_limit IS NULL OR selected_limit < 1 OR selected_limit > 100 THEN RETURN; END IF;
  RETURN QUERY
  WITH eligible_users AS (
    SELECT p.user_id
    FROM trimmy.career_profiles p
    JOIN trimmy.users u ON u.id = p.user_id AND u.status = 'active'
    WHERE p.rank_id = 'rookie'
      AND EXISTS (
        SELECT 1 FROM trimmy.career_mission_completions c
        WHERE c.user_id = p.user_id AND c.mission_id = 'first-paper-buy')
      AND EXISTS (
        SELECT 1 FROM trimmy.career_mission_completions c
        WHERE c.user_id = p.user_id AND c.mission_id = 'write-a-reason')
      AND NOT EXISTS (
        SELECT 1 FROM trimmy.career_mission_completions c
        WHERE c.user_id = p.user_id AND c.mission_id = 'hold-through-red-day')
  ), candidate_assets AS (
    SELECT DISTINCT o.asset_id
    FROM trimmy.paper_orders o JOIN eligible_users e ON e.user_id = o.user_id
  ), last_sessions AS (
    SELECT s.asset_id, max(s.market_date) AS market_date
    FROM trimmy.career_red_day_sessions s GROUP BY s.asset_id
  )
  -- Re-read the latest canonical session on every due pass so delayed provider
  -- corrections become visible. One calendar-day overlap includes the latest
  -- row even across weekends and exchange holidays.
  SELECT c.asset_id, CASE WHEN l.market_date IS NULL THEN NULL
    ELSE l.market_date - 1 END
  FROM candidate_assets c
  LEFT JOIN last_sessions l ON l.asset_id = c.asset_id
  LEFT JOIN trimmy.career_red_day_asset_state a ON a.asset_id = c.asset_id
  WHERE EXISTS (
      SELECT 1 FROM trimmy.career_mission_definitions mission
      WHERE mission.id = 'hold-through-red-day'
        AND mission.evidence_kind = 'server-red-day-hold'
        AND mission.evidence_live)
    AND (a.asset_id IS NULL OR a.next_attempt_at <= clock_timestamp())
    AND NOT EXISTS (
      SELECT 1 FROM trimmy.career_red_day_provider_state provider_state
      WHERE provider_state.provider = 'tokens-xyz-v1'
        AND provider_state.cooldown_reason IS NOT NULL
        AND provider_state.next_attempt_at > clock_timestamp())
    AND NOT EXISTS (
      SELECT 1 FROM trimmy.career_red_day_sessions pending
      WHERE pending.asset_id = c.asset_id AND NOT pending.processing_complete)
  ORDER BY (a.last_attempt_at IS NOT NULL), a.last_attempt_at NULLS FIRST, c.asset_id
  LIMIT selected_limit;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_red_day_candidates(integer) FROM PUBLIC;

CREATE FUNCTION trimmy.career_red_day_pending_sessions(selected_limit integer)
RETURNS TABLE (observation_id uuid, asset_id text, market_date date)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  IF selected_limit IS NULL OR selected_limit < 1 OR selected_limit > 100 THEN RETURN; END IF;
  RETURN QUERY
  SELECT s.observation_id, s.asset_id, s.market_date
  FROM trimmy.career_red_day_sessions s
  WHERE NOT s.processing_complete
  ORDER BY s.market_date, s.observation_id
  LIMIT selected_limit;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_red_day_pending_sessions(integer) FROM PUBLIC;

CREATE FUNCTION trimmy.career_red_day_record_observation(
  selected_observation uuid,
  selected_provider text,
  selected_verifier_version text,
  selected_asset text,
  selected_symbol text,
  selected_status text,
  selected_previous_market_date date,
  selected_market_date date,
  selected_previous_close_text text,
  selected_current_close_text text,
  selected_provider_as_of timestamptz,
  selected_provider_last_fetched_at timestamptz,
  selected_source text,
  selected_reason_code text,
  selected_detail_request uuid,
  selected_chart_request uuid,
  selected_detail_provider_request text,
  selected_chart_provider_request text,
  selected_detail_path text,
  selected_chart_path text,
  selected_detail_hash text,
  selected_chart_hash text,
  selected_observed_at timestamptz
) RETURNS TABLE (
  outcome text,
  observation_id uuid,
  evidence_count bigint,
  completed_count bigint
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE existing_row trimmy.career_red_day_provider_observations%ROWTYPE;
DECLARE canonical_row trimmy.career_red_day_provider_observations%ROWTYPE;
DECLARE session_open timestamptz; session_close timestamptz;
DECLARE canonical_observation uuid; existing_correction uuid;
DECLARE database_observed_at timestamptz;
DECLARE chart_from bigint; chart_to bigint;
DECLARE computed_request_hash text;
DECLARE retry_delay interval;
DECLARE correction_detected boolean := false;
DECLARE previous_close numeric; current_close numeric;
BEGIN
  -- Bound every caller-controlled text value before JSON construction, hashing,
  -- regex work or numeric casts. The JavaScript reader applies tighter shape
  -- checks, but this security-definer boundary distrusts its caller.
  IF coalesce(octet_length(selected_provider), 0) > 64
      OR coalesce(octet_length(selected_verifier_version), 0) > 64
      OR coalesce(octet_length(selected_asset), 0) > 100
      OR coalesce(octet_length(selected_symbol), 0) > 15
      OR coalesce(octet_length(selected_status), 0) > 32
      OR coalesce(octet_length(selected_previous_close_text), 0) > 128
      OR coalesce(octet_length(selected_current_close_text), 0) > 128
      OR coalesce(octet_length(selected_source), 0) > 64
      OR coalesce(octet_length(selected_reason_code), 0) > 64
      OR coalesce(octet_length(selected_detail_provider_request), 0) > 160
      OR coalesce(octet_length(selected_chart_provider_request), 0) > 160
      OR coalesce(octet_length(selected_detail_path), 0) > 128
      OR coalesce(octet_length(selected_chart_path), 0) > 300
      OR coalesce(octet_length(selected_detail_hash), 0) > 64
      OR coalesce(octet_length(selected_chart_hash), 0) > 64 THEN
    RAISE EXCEPTION 'Red-day observation text is too large'
      USING ERRCODE = '22023', CONSTRAINT = 'career_red_day_observation_input';
  END IF;
  computed_request_hash := encode(sha256(convert_to(jsonb_build_array(
    'trimmy-career-red-day-observation-v1', selected_observation::text,
    selected_provider, selected_verifier_version, selected_asset, selected_symbol,
    selected_status, selected_previous_market_date::text, selected_market_date::text,
    selected_previous_close_text, selected_current_close_text,
    CASE WHEN selected_provider_as_of IS NULL THEN NULL
      ELSE extract(epoch FROM selected_provider_as_of)::text END,
    CASE WHEN selected_provider_last_fetched_at IS NULL THEN NULL
      ELSE extract(epoch FROM selected_provider_last_fetched_at)::text END,
    selected_source, selected_reason_code, selected_detail_request::text,
    selected_chart_request::text, selected_detail_provider_request,
    selected_chart_provider_request, selected_detail_path, selected_chart_path,
    selected_detail_hash, selected_chart_hash,
    CASE WHEN selected_observed_at IS NULL THEN NULL
      ELSE extract(epoch FROM selected_observed_at)::text END
  )::text, 'UTF8')), 'hex');
  IF selected_observation IS NULL THEN
    RETURN QUERY SELECT 'idempotency-conflict'::text, selected_observation, 0::bigint, 0::bigint;
    RETURN;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.red-day:observation:' || selected_observation::text, 0));
  SELECT o.* INTO existing_row FROM trimmy.career_red_day_provider_observations o
  WHERE o.observation_id = selected_observation;
  IF FOUND THEN
    IF existing_row.request_hash <> computed_request_hash THEN
      RETURN QUERY SELECT 'idempotency-conflict'::text, selected_observation, 0::bigint, 0::bigint;
    ELSE
      RETURN QUERY
      SELECT 'already-recorded'::text, selected_observation,
        count(e.evidence_id)::bigint,
        count(c.completion_id)::bigint
      FROM trimmy.career_red_day_user_evidence e
      LEFT JOIN trimmy.career_mission_completions c
        ON c.evidence_id = e.evidence_id AND c.user_id = e.user_id
          AND c.mission_id = 'hold-through-red-day'
      WHERE e.observation_id = selected_observation;
    END IF;
    RETURN;
  END IF;

  IF selected_provider IS DISTINCT FROM 'tokens-xyz-v1'
      OR selected_verifier_version IS DISTINCT FROM 'tokens-canonical-red-day-v1'
      OR selected_asset IS NULL OR selected_asset !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
      OR length(selected_asset) > 100
      OR selected_status IS NULL
      OR selected_status NOT IN ('verified-red', 'verified-not-red', 'unavailable', 'rejected')
      OR selected_detail_request IS NULL OR selected_detail_path IS DISTINCT FROM
        '/v1/assets/' || selected_asset
      OR selected_observed_at IS NULL OR NOT isfinite(selected_observed_at)
      OR selected_detail_provider_request IS NOT NULL AND (
        length(selected_detail_provider_request) NOT BETWEEN 1 AND 160
        OR selected_detail_provider_request <> btrim(selected_detail_provider_request)
        OR selected_detail_provider_request ~ '[[:cntrl:]]')
      OR selected_chart_provider_request IS NOT NULL AND (
        length(selected_chart_provider_request) NOT BETWEEN 1 AND 160
        OR selected_chart_provider_request <> btrim(selected_chart_provider_request)
        OR selected_chart_provider_request ~ '[[:cntrl:]]') THEN
    RAISE EXCEPTION 'Red-day provider observation is invalid'
      USING ERRCODE = '22023', CONSTRAINT = 'career_red_day_observation_input';
  END IF;

  IF selected_status IN ('unavailable', 'rejected') THEN
    database_observed_at := date_trunc('milliseconds', clock_timestamp());
    IF selected_observed_at < database_observed_at - interval '2 minutes'
        OR selected_observed_at > database_observed_at + interval '2 minutes'
        OR selected_reason_code NOT IN (
          'provider-auth-failed', 'provider-rate-limited', 'provider-unavailable',
          'provider-timeout', 'response-invalid', 'identity-mismatch',
          'source-mismatch', 'stale-provider-data', 'no-new-market-session',
          'asset-not-in-catalog')
        OR selected_source IS NOT NULL OR selected_previous_market_date IS NOT NULL
        OR selected_market_date IS NOT NULL OR selected_previous_close_text IS NOT NULL
        OR selected_current_close_text IS NOT NULL OR selected_provider_as_of IS NOT NULL
        OR selected_provider_last_fetched_at IS NOT NULL
        OR selected_reason_code = 'asset-not-in-catalog' AND selected_symbol IS NOT NULL
        OR selected_reason_code <> 'asset-not-in-catalog' AND (
          selected_symbol IS NULL OR selected_symbol !~ '^[A-Z][A-Z0-9.-]{0,14}$') THEN
      RAISE EXCEPTION 'Failed red-day observation contains untrusted market evidence'
        USING ERRCODE = '22023', CONSTRAINT = 'career_red_day_observation_input';
    END IF;
    INSERT INTO trimmy.career_red_day_provider_observations(
      observation_id, request_hash, provider, verifier_version, asset_id,
      listed_symbol, observation_status, reason_code, detail_request_id,
      chart_request_id, detail_provider_request_id, chart_provider_request_id,
      detail_path, chart_path, detail_response_sha256, chart_response_sha256,
      observed_at)
    VALUES (selected_observation, computed_request_hash, selected_provider,
      selected_verifier_version, selected_asset, selected_symbol, selected_status,
      selected_reason_code, selected_detail_request, selected_chart_request,
      selected_detail_provider_request, selected_chart_provider_request,
      selected_detail_path, selected_chart_path, selected_detail_hash,
      selected_chart_hash, database_observed_at);
    retry_delay := CASE selected_reason_code
      WHEN 'asset-not-in-catalog' THEN interval '24 hours'
      WHEN 'identity-mismatch' THEN interval '12 hours'
      WHEN 'source-mismatch' THEN interval '12 hours'
      WHEN 'response-invalid' THEN interval '12 hours'
      WHEN 'stale-provider-data' THEN interval '6 hours'
      WHEN 'no-new-market-session' THEN interval '6 hours'
      WHEN 'provider-auth-failed' THEN interval '1 hour'
      WHEN 'provider-rate-limited' THEN interval '30 minutes'
      ELSE interval '15 minutes'
    END;
    INSERT INTO trimmy.career_red_day_asset_state(
      asset_id, last_observation_id, last_attempt_at, next_attempt_at,
      consecutive_failures, last_status, last_reason_code, updated_at)
    VALUES (selected_asset, selected_observation, database_observed_at,
      database_observed_at + retry_delay, 1, selected_status,
      selected_reason_code, database_observed_at)
    ON CONFLICT (asset_id) DO UPDATE SET
      last_observation_id = EXCLUDED.last_observation_id,
      last_attempt_at = EXCLUDED.last_attempt_at,
      next_attempt_at = EXCLUDED.next_attempt_at,
      consecutive_failures = least(
        trimmy.career_red_day_asset_state.consecutive_failures + 1, 1000000),
      last_status = EXCLUDED.last_status,
      last_reason_code = EXCLUDED.last_reason_code,
      updated_at = EXCLUDED.updated_at;
    IF selected_reason_code IN ('provider-auth-failed', 'provider-rate-limited') THEN
      INSERT INTO trimmy.career_red_day_provider_state(
        provider, last_observation_id, last_attempt_at, next_attempt_at,
        cooldown_reason, updated_at)
      VALUES (selected_provider, selected_observation, database_observed_at,
        database_observed_at + retry_delay, selected_reason_code,
        database_observed_at)
      ON CONFLICT (provider) DO UPDATE SET
        last_observation_id = EXCLUDED.last_observation_id,
        last_attempt_at = EXCLUDED.last_attempt_at,
        next_attempt_at = EXCLUDED.next_attempt_at,
        cooldown_reason = EXCLUDED.cooldown_reason,
        updated_at = EXCLUDED.updated_at;
    END IF;
    RETURN QUERY SELECT 'recorded'::text, selected_observation, 0::bigint, 0::bigint;
    RETURN;
  END IF;

  IF selected_symbol IS NULL OR selected_symbol !~ '^[A-Z][A-Z0-9.-]{0,14}$'
      OR selected_source IS DISTINCT FROM 'clickhouse_stock'
      OR selected_previous_market_date IS NULL OR selected_market_date IS NULL
      OR selected_previous_market_date >= selected_market_date
      OR extract(isodow FROM selected_market_date) > 5
      OR extract(isodow FROM selected_previous_market_date) > 5
      OR selected_previous_close_text IS NULL
      OR selected_previous_close_text !~
        '^(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?([0-9]{1,2}|100))?$'
      OR selected_current_close_text IS NULL
      OR selected_current_close_text !~
        '^(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?([0-9]{1,2}|100))?$'
      OR selected_provider_as_of IS NULL OR NOT isfinite(selected_provider_as_of)
      OR selected_provider_last_fetched_at IS NULL
      OR NOT isfinite(selected_provider_last_fetched_at)
      OR selected_reason_code IS NOT NULL OR selected_chart_request IS NULL
      OR selected_chart_path IS NULL OR length(selected_chart_path) NOT BETWEEN 1 AND 300
      OR selected_chart_path !~ ('^/v1/assets/' || selected_asset
        || '/price-chart\?interval=1D&from=[1-9][0-9]{9}&to=[1-9][0-9]{9}$')
      OR selected_detail_hash IS NULL OR selected_detail_hash !~ '^[a-f0-9]{64}$'
      OR selected_chart_hash IS NULL OR selected_chart_hash !~ '^[a-f0-9]{64}$' THEN
    RAISE EXCEPTION 'Verified red-day observation is invalid'
      USING ERRCODE = '22023', CONSTRAINT = 'career_red_day_observation_input';
  END IF;
  BEGIN
    previous_close := selected_previous_close_text::numeric;
    current_close := selected_current_close_text::numeric;
  EXCEPTION WHEN numeric_value_out_of_range OR invalid_text_representation THEN
    RAISE EXCEPTION 'Verified red-day close is invalid'
      USING ERRCODE = '22023', CONSTRAINT = 'career_red_day_observation_input';
  END;
  IF previous_close <= 0 OR current_close <= 0
      OR selected_status = 'verified-red' AND current_close >= previous_close
      OR selected_status = 'verified-not-red' AND current_close < previous_close THEN
    RAISE EXCEPTION 'Verified red-day close is invalid'
      USING ERRCODE = '22023', CONSTRAINT = 'career_red_day_observation_input';
  END IF;
  session_open := trimmy.career_red_day_session_open(selected_market_date);
  session_close := trimmy.career_red_day_session_close(selected_market_date);
  chart_from := substring(selected_chart_path from '&from=([1-9][0-9]{9})&')::bigint;
  chart_to := substring(selected_chart_path from '&to=([1-9][0-9]{9})$')::bigint;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.red-day:session:' || selected_provider || ':' || selected_asset || ':' ||
      selected_market_date::text || ':' || selected_verifier_version, 0));
  database_observed_at := date_trunc('milliseconds', clock_timestamp());
  IF selected_observed_at < database_observed_at - interval '2 minutes'
      OR selected_observed_at > database_observed_at + interval '2 minutes'
      OR chart_to - chart_from <> 3024000
      OR to_timestamp(chart_to) < database_observed_at - interval '2 minutes'
      OR to_timestamp(chart_to) > database_observed_at + interval '2 minutes'
      OR database_observed_at < session_close
      OR database_observed_at > session_close + interval '14 days'
      OR selected_provider_as_of < session_close
      OR selected_provider_as_of > database_observed_at + interval '5 minutes'
      OR selected_provider_last_fetched_at < database_observed_at - interval '30 minutes'
      OR selected_provider_last_fetched_at > database_observed_at + interval '5 minutes' THEN
    RAISE EXCEPTION 'Verified red-day observation is stale or premature'
      USING ERRCODE = '22023', CONSTRAINT = 'career_red_day_observation_freshness';
  END IF;

  SELECT s.observation_id INTO canonical_observation
  FROM trimmy.career_red_day_sessions s
  WHERE s.provider = selected_provider AND s.asset_id = selected_asset
    AND s.market_date = selected_market_date
    AND s.verifier_version = selected_verifier_version;
  IF FOUND THEN
    SELECT o.* INTO STRICT canonical_row
    FROM trimmy.career_red_day_provider_observations o
    WHERE o.observation_id = canonical_observation;
    IF (canonical_row.observation_status, canonical_row.listed_symbol,
        canonical_row.source, canonical_row.previous_market_date,
        canonical_row.previous_close_text::numeric,
        canonical_row.current_close_text::numeric)
        IS NOT DISTINCT FROM
        (selected_status, selected_symbol, selected_source,
          selected_previous_market_date, selected_previous_close_text::numeric,
          selected_current_close_text::numeric) THEN
      INSERT INTO trimmy.career_red_day_asset_state(
        asset_id, last_observation_id, last_attempt_at, next_attempt_at,
        consecutive_failures, last_status, last_reason_code, updated_at)
      VALUES (selected_asset, canonical_observation, database_observed_at,
        database_observed_at + interval '6 hours', 0, selected_status, NULL,
        database_observed_at)
      ON CONFLICT (asset_id) DO UPDATE SET
        last_observation_id = EXCLUDED.last_observation_id,
        last_attempt_at = EXCLUDED.last_attempt_at,
        next_attempt_at = EXCLUDED.next_attempt_at,
        consecutive_failures = 0,
        last_status = EXCLUDED.last_status,
        last_reason_code = NULL,
        updated_at = EXCLUDED.updated_at;
      INSERT INTO trimmy.career_red_day_provider_state(
        provider, last_observation_id, last_attempt_at, next_attempt_at,
        cooldown_reason, updated_at)
      VALUES (selected_provider, canonical_observation, database_observed_at,
        database_observed_at, NULL, database_observed_at)
      ON CONFLICT (provider) DO UPDATE SET
        last_observation_id = EXCLUDED.last_observation_id,
        last_attempt_at = EXCLUDED.last_attempt_at,
        next_attempt_at = EXCLUDED.next_attempt_at,
        cooldown_reason = NULL,
        updated_at = EXCLUDED.updated_at;
      RETURN QUERY SELECT 'already-recorded'::text, selected_observation, 0::bigint, 0::bigint;
      RETURN;
    END IF;
    correction_detected := true;
    SELECT r.review_observation_id INTO existing_correction
    FROM trimmy.career_red_day_correction_reviews r
    JOIN trimmy.career_red_day_provider_observations o
      ON o.observation_id = r.review_observation_id
    WHERE r.canonical_observation_id = canonical_observation
      AND (o.observation_status, o.listed_symbol, o.source,
        o.previous_market_date, o.previous_close_text::numeric,
        o.current_close_text::numeric) IS NOT DISTINCT FROM
        (selected_status, selected_symbol, selected_source,
          selected_previous_market_date, selected_previous_close_text::numeric,
          selected_current_close_text::numeric)
    ORDER BY r.detected_at, r.review_observation_id
    LIMIT 1;
    IF FOUND THEN
      INSERT INTO trimmy.career_red_day_asset_state(
        asset_id, last_observation_id, last_attempt_at, next_attempt_at,
        consecutive_failures, last_status, last_reason_code, updated_at)
      VALUES (selected_asset, existing_correction, database_observed_at,
        database_observed_at + interval '6 hours', 0, selected_status, NULL,
        database_observed_at)
      ON CONFLICT (asset_id) DO UPDATE SET
        last_observation_id = EXCLUDED.last_observation_id,
        last_attempt_at = EXCLUDED.last_attempt_at,
        next_attempt_at = EXCLUDED.next_attempt_at,
        consecutive_failures = 0,
        last_status = EXCLUDED.last_status,
        last_reason_code = NULL,
        updated_at = EXCLUDED.updated_at;
      INSERT INTO trimmy.career_red_day_provider_state(
        provider, last_observation_id, last_attempt_at, next_attempt_at,
        cooldown_reason, updated_at)
      VALUES (selected_provider, existing_correction, database_observed_at,
        database_observed_at, NULL, database_observed_at)
      ON CONFLICT (provider) DO UPDATE SET
        last_observation_id = EXCLUDED.last_observation_id,
        last_attempt_at = EXCLUDED.last_attempt_at,
        next_attempt_at = EXCLUDED.next_attempt_at,
        cooldown_reason = NULL,
        updated_at = EXCLUDED.updated_at;
      RETURN QUERY SELECT 'already-reviewed'::text, selected_observation, 0::bigint, 0::bigint;
      RETURN;
    END IF;
  END IF;

  INSERT INTO trimmy.career_red_day_provider_observations(
    observation_id, request_hash, provider, verifier_version, asset_id,
    listed_symbol, observation_status, source, previous_market_date, market_date,
    previous_close_text, current_close_text, provider_as_of,
    provider_last_fetched_at, detail_request_id, chart_request_id,
    detail_provider_request_id, chart_provider_request_id, detail_path, chart_path,
    detail_response_sha256, chart_response_sha256, observed_at)
  VALUES (selected_observation, computed_request_hash, selected_provider,
    selected_verifier_version, selected_asset, selected_symbol, selected_status,
    selected_source, selected_previous_market_date, selected_market_date,
    selected_previous_close_text, selected_current_close_text, selected_provider_as_of,
    selected_provider_last_fetched_at, selected_detail_request, selected_chart_request,
    selected_detail_provider_request, selected_chart_provider_request,
    selected_detail_path, selected_chart_path, selected_detail_hash,
    selected_chart_hash, database_observed_at);
  IF correction_detected THEN
    INSERT INTO trimmy.career_red_day_correction_reviews(
      review_observation_id, canonical_observation_id, provider, asset_id,
      market_date, identity_changed, outcome_changed, close_changed, detected_at)
    VALUES (selected_observation, canonical_observation, selected_provider,
      selected_asset, selected_market_date,
      (canonical_row.listed_symbol, canonical_row.source,
        canonical_row.previous_market_date) IS DISTINCT FROM
        (selected_symbol, selected_source, selected_previous_market_date),
      canonical_row.observation_status <> selected_status,
      canonical_row.previous_close_text::numeric <> selected_previous_close_text::numeric
        OR canonical_row.current_close_text::numeric <> selected_current_close_text::numeric,
      database_observed_at);
  ELSE
    INSERT INTO trimmy.career_red_day_sessions(
      observation_id, provider, verifier_version, asset_id, market_date,
      processing_complete, processing_completed_at)
    VALUES (selected_observation, selected_provider, selected_verifier_version,
      selected_asset, selected_market_date, selected_status = 'verified-not-red',
      CASE WHEN selected_status = 'verified-not-red' THEN database_observed_at ELSE NULL END);
  END IF;

  INSERT INTO trimmy.career_red_day_asset_state(
    asset_id, last_observation_id, last_attempt_at, next_attempt_at,
    consecutive_failures, last_status, last_reason_code, updated_at)
  VALUES (selected_asset, selected_observation, database_observed_at,
    database_observed_at + interval '6 hours', 0, selected_status, NULL,
    database_observed_at)
  ON CONFLICT (asset_id) DO UPDATE SET
    last_observation_id = EXCLUDED.last_observation_id,
    last_attempt_at = EXCLUDED.last_attempt_at,
    next_attempt_at = EXCLUDED.next_attempt_at,
    consecutive_failures = 0,
    last_status = EXCLUDED.last_status,
    last_reason_code = NULL,
    updated_at = EXCLUDED.updated_at;
  INSERT INTO trimmy.career_red_day_provider_state(
    provider, last_observation_id, last_attempt_at, next_attempt_at,
    cooldown_reason, updated_at)
  VALUES (selected_provider, selected_observation, database_observed_at,
    database_observed_at, NULL, database_observed_at)
  ON CONFLICT (provider) DO UPDATE SET
    last_observation_id = EXCLUDED.last_observation_id,
    last_attempt_at = EXCLUDED.last_attempt_at,
    next_attempt_at = EXCLUDED.next_attempt_at,
    cooldown_reason = NULL,
    updated_at = EXCLUDED.updated_at;

  IF correction_detected THEN
    RETURN QUERY SELECT 'correction-review'::text, selected_observation, 0::bigint, 0::bigint;
  ELSE
    RETURN QUERY SELECT 'recorded'::text, selected_observation, 0::bigint, 0::bigint;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_red_day_record_observation(
  uuid, text, text, text, text, text, date, date, text, text,
  timestamptz, timestamptz, text, text, uuid, uuid, text, text, text,
  text, text, text, timestamptz) FROM PUBLIC;

CREATE FUNCTION trimmy.career_red_day_process_session(
  selected_observation uuid,
  selected_limit integer
) RETURNS TABLE (
  outcome text,
  observation_id uuid,
  evidence_count bigint,
  completed_count bigint,
  processing_complete boolean
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE session_row trimmy.career_red_day_sessions%ROWTYPE;
DECLARE observation_row trimmy.career_red_day_provider_observations%ROWTYPE;
DECLARE candidate record; opening_row trimmy.paper_orders%ROWTYPE;
DECLARE session_open timestamptz; session_close timestamptz;
DECLARE opening_quantity numeric; minimum_quantity numeric;
DECLARE evidence_outcome text; evidence_reason text; completion_outcome text;
DECLARE selected_evidence uuid; last_user uuid; last_variant text;
DECLARE recorded_evidence bigint := 0; recorded_completions bigint := 0;
DECLARE work_remaining boolean := false;
DECLARE account_status text;
BEGIN
  IF selected_observation IS NULL OR selected_limit IS NULL
      OR selected_limit < 1 OR selected_limit > 100 THEN
    RAISE EXCEPTION 'Red-day processing request is invalid'
      USING ERRCODE = '22023', CONSTRAINT = 'career_red_day_processing_input';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.red-day:processing:' || selected_observation::text, 0));
  SELECT s.* INTO session_row FROM trimmy.career_red_day_sessions s
  WHERE s.observation_id = selected_observation FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Red-day session does not exist'
      USING ERRCODE = '22023', CONSTRAINT = 'career_red_day_processing_input';
  END IF;
  IF session_row.processing_complete THEN
    RETURN QUERY SELECT 'already-complete'::text, selected_observation,
      0::bigint, 0::bigint, true;
    RETURN;
  END IF;
  SELECT o.* INTO STRICT observation_row
  FROM trimmy.career_red_day_provider_observations o
  WHERE o.observation_id = selected_observation;
  IF observation_row.observation_status <> 'verified-red' OR NOT EXISTS (
      SELECT 1 FROM trimmy.career_mission_definitions d
      WHERE d.id = 'hold-through-red-day' AND d.evidence_kind = 'server-red-day-hold'
        AND d.evidence_live) THEN
    RAISE EXCEPTION 'Red-day processing is not activated for this session'
      USING ERRCODE = '55000', CONSTRAINT = 'career_red_day_processing_activation';
  END IF;
  session_open := trimmy.career_red_day_session_open(session_row.market_date);
  session_close := trimmy.career_red_day_session_close(session_row.market_date);

  FOR candidate IN
    SELECT DISTINCT o.user_id, o.variant_mint
    FROM trimmy.paper_orders o
    JOIN trimmy.users u ON u.id = o.user_id AND u.status = 'active'
    JOIN trimmy.career_profiles p ON p.user_id = o.user_id AND p.rank_id = 'rookie'
    WHERE o.asset_id = session_row.asset_id
      AND (session_row.processing_cursor_user_id IS NULL OR
        (o.user_id, o.variant_mint) >
          (session_row.processing_cursor_user_id, session_row.processing_cursor_variant_mint))
    ORDER BY o.user_id, o.variant_mint
    LIMIT selected_limit
  LOOP
    last_user := candidate.user_id;
    last_variant := candidate.variant_mint;
    -- Paper commits take this lock before their Career activity lock. Match
    -- that order so an in-flight sell cannot be missed by reconstruction.
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'trimmy.paper:' || candidate.user_id::text, 0));
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'trimmy.career:' || candidate.user_id::text, 0));
    -- Account closure serializes on the users row. Lock and re-read it after
    -- the paper and Career locks so an uncommitted closure cannot be observed
    -- as active evidence.
    SELECT u.status INTO account_status FROM trimmy.users u
    WHERE u.id = candidate.user_id FOR UPDATE;
    IF account_status IS DISTINCT FROM 'active'
        OR NOT EXISTS (
          SELECT 1 FROM trimmy.career_profiles p
          WHERE p.user_id = candidate.user_id AND p.rank_id = 'rookie')
        OR NOT EXISTS (
          SELECT 1 FROM trimmy.career_mission_completions c
          WHERE c.user_id = candidate.user_id AND c.mission_id = 'first-paper-buy'
            AND c.completed_at <= session_close)
        OR NOT EXISTS (
          SELECT 1 FROM trimmy.career_mission_completions c
          WHERE c.user_id = candidate.user_id AND c.mission_id = 'write-a-reason'
            AND c.completed_at <= session_close)
        OR EXISTS (
          SELECT 1 FROM trimmy.career_mission_completions c
          WHERE c.user_id = candidate.user_id AND c.mission_id = 'hold-through-red-day') THEN
      CONTINUE;
    END IF;
    opening_row := NULL;
    SELECT o.* INTO opening_row
    FROM trimmy.paper_orders o
    WHERE o.user_id = candidate.user_id AND o.asset_id = session_row.asset_id
      AND o.variant_mint = candidate.variant_mint AND o.committed_at < session_open
    ORDER BY o.committed_at DESC, o.account_revision DESC, o.id DESC
    LIMIT 1;
    opening_quantity := CASE WHEN FOUND
      THEN opening_row.position_quantity_after_micros ELSE 0 END;
    SELECT least(opening_quantity,
      coalesce(min(o.position_quantity_after_micros), opening_quantity))
    INTO minimum_quantity
    FROM trimmy.paper_orders o
    WHERE o.user_id = candidate.user_id AND o.asset_id = session_row.asset_id
      AND o.variant_mint = candidate.variant_mint
      AND o.committed_at >= session_open AND o.committed_at <= session_close;
    IF opening_quantity > 0 AND minimum_quantity > 0 THEN
      evidence_outcome := 'qualified'; evidence_reason := NULL;
    ELSIF opening_quantity <= 0 THEN
      evidence_outcome := 'not-held-throughout'; evidence_reason := 'not-positive-at-open';
    ELSE
      evidence_outcome := 'not-held-throughout'; evidence_reason := 'position-reached-zero';
    END IF;
    selected_evidence := gen_random_uuid();
    INSERT INTO trimmy.career_red_day_user_evidence(
      evidence_id, observation_id, user_id, asset_id, variant_mint,
      listed_symbol, market_date, session_open_at, session_close_at,
      opening_order_id, opening_quantity_micros, minimum_session_quantity_micros,
      evidence_outcome, reason_code, recorded_at)
    VALUES (selected_evidence, selected_observation, candidate.user_id,
      session_row.asset_id, candidate.variant_mint, observation_row.listed_symbol,
      session_row.market_date, session_open, session_close, opening_row.id,
      opening_quantity, minimum_quantity, evidence_outcome, evidence_reason,
      observation_row.observed_at);
    recorded_evidence := recorded_evidence + 1;
    IF evidence_outcome = 'qualified' THEN
      SELECT trimmy.career_server_mission_complete(candidate.user_id,
        'hold-through-red-day', selected_evidence, observation_row.observed_at)
      INTO completion_outcome;
      IF completion_outcome <> 'completed' THEN
        RAISE EXCEPTION 'Qualified red-day mission could not be completed: %', completion_outcome
          USING ERRCODE = '23514', CONSTRAINT = 'career_red_day_completion';
      END IF;
      recorded_completions := recorded_completions + 1;
    END IF;
  END LOOP;

  IF last_user IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1
      FROM trimmy.paper_orders o
      JOIN trimmy.users u ON u.id = o.user_id AND u.status = 'active'
      JOIN trimmy.career_profiles p ON p.user_id = o.user_id AND p.rank_id = 'rookie'
      WHERE o.asset_id = session_row.asset_id
        AND (o.user_id, o.variant_mint) > (last_user, last_variant)
    ) INTO work_remaining;
  END IF;
  UPDATE trimmy.career_red_day_sessions SET
    processing_cursor_user_id = coalesce(last_user, processing_cursor_user_id),
    processing_cursor_variant_mint = coalesce(last_variant, processing_cursor_variant_mint),
    processing_complete = NOT work_remaining,
    processing_completed_at = CASE WHEN work_remaining THEN NULL
      ELSE date_trunc('milliseconds', clock_timestamp()) END
  WHERE career_red_day_sessions.observation_id = selected_observation;
  RETURN QUERY SELECT CASE WHEN work_remaining THEN 'processed' ELSE 'complete' END,
    selected_observation, recorded_evidence, recorded_completions, NOT work_remaining;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_red_day_process_session(uuid, integer) FROM PUBLIC;

-- Activation stays separate from schema installation. Deployment tooling grants
-- the dedicated worker capability exactly its four bounded functions, verifies
-- that it has no table access and that the API cannot invoke them,
-- and invokes this owner-only function last.
CREATE FUNCTION trimmy.career_red_day_activate() RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  UPDATE trimmy.career_mission_definitions
  SET evidence_live = true
  WHERE id = 'hold-through-red-day' AND evidence_kind = 'server-red-day-hold'
    AND evidence_live = false;
  IF NOT EXISTS (
    SELECT 1 FROM trimmy.career_mission_definitions
    WHERE id = 'hold-through-red-day' AND evidence_kind = 'server-red-day-hold'
      AND evidence_live = true
  ) THEN
    RAISE EXCEPTION 'Red-day mission definition could not be activated';
  END IF;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_red_day_activate() FROM PUBLIC;

ALTER TABLE trimmy.career_red_day_provider_observations ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_red_day_provider_observations FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_red_day_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_red_day_sessions FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_red_day_asset_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_red_day_asset_state FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_red_day_provider_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_red_day_provider_state FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_red_day_user_evidence ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_red_day_user_evidence FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_red_day_correction_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_red_day_correction_reviews FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE trimmy.career_red_day_provider_observations,
  trimmy.career_red_day_sessions, trimmy.career_red_day_asset_state,
  trimmy.career_red_day_provider_state,
  trimmy.career_red_day_user_evidence,
  trimmy.career_red_day_correction_reviews FROM PUBLIC;

INSERT INTO trimmy.schema_migrations(version) VALUES ('0021_career_red_day_evidence');
COMMIT;
