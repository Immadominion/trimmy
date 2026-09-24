-- 0020: shared guest-creation abuse control and bounded authentication
-- material retention. The API supplies only a deployment-keyed HMAC of the
-- normalized network source. Raw network addresses never reach PostgreSQL.
BEGIN;

CREATE TABLE trimmy.guest_creation_attempts (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source_hash trimmy.sha256_hex NOT NULL,
  attempted_at timestamptz NOT NULL CHECK (isfinite(attempted_at)),
  admitted boolean NOT NULL,
  consumed_at timestamptz,
  CHECK (consumed_at IS NULL OR admitted AND isfinite(consumed_at)
    AND consumed_at >= attempted_at AND consumed_at <= attempted_at + interval '30 seconds')
);

CREATE INDEX guest_creation_attempts_source_time
  ON trimmy.guest_creation_attempts (source_hash, attempted_at DESC, id DESC);
CREATE INDEX guest_creation_attempts_retention
  ON trimmy.guest_creation_attempts (attempted_at, id);

CREATE FUNCTION trimmy.protect_guest_creation_attempt() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy AS $$
BEGIN
  IF TG_OP = 'DELETE'
      AND current_setting('trimmy.guest_retention', true) = 'on'
      AND OLD.attempted_at < clock_timestamp() - interval '24 hours' THEN
    RETURN OLD;
  END IF;
  IF TG_OP = 'UPDATE'
      AND current_setting('trimmy.guest_creation_consume', true) = 'on'
      AND OLD.admitted
      AND OLD.consumed_at IS NULL
      AND NEW.consumed_at IS NOT NULL
      AND (NEW.id, NEW.source_hash, NEW.attempted_at, NEW.admitted)
          IS NOT DISTINCT FROM
          (OLD.id, OLD.source_hash, OLD.attempted_at, OLD.admitted) THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'Guest creation attempts are append only'
    USING ERRCODE = '23514', CONSTRAINT = 'guest_creation_attempt_append_only';
END;
$$;
REVOKE ALL ON FUNCTION trimmy.protect_guest_creation_attempt() FROM PUBLIC;
CREATE TRIGGER guest_creation_attempt_append_only
  BEFORE UPDATE OR DELETE ON trimmy.guest_creation_attempts
  FOR EACH ROW EXECUTE FUNCTION trimmy.protect_guest_creation_attempt();

ALTER TABLE trimmy.guest_sessions
  ALTER COLUMN credential_hash DROP NOT NULL,
  ADD COLUMN auth_redacted_at timestamptz,
  ADD CONSTRAINT guest_session_auth_redaction CHECK (
    auth_redacted_at IS NULL
    OR (
      credential_hash IS NULL
      AND creation_request_hash IS NULL
      AND creation_replay_hash IS NULL
      AND isfinite(auth_redacted_at)
      AND auth_redacted_at >= hard_expires_at + interval '7 days'
    )
  );

-- Retention selects the oldest eligible rows in bounded batches. These index
-- prefixes match both the cutoff predicates and deterministic batch order, so
-- the job does not fall back to sorting all retained authentication history.
CREATE INDEX guest_rate_windows_retention
  ON trimmy.guest_rate_windows (window_started_at, guest_session_id, scope);
CREATE INDEX guest_sessions_auth_retention
  ON trimmy.guest_sessions (hard_expires_at, id)
  WHERE auth_redacted_at IS NULL;

CREATE OR REPLACE FUNCTION trimmy.protect_guest_session() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Guest session history cannot be deleted' USING ERRCODE = '23514';
  END IF;

  -- The owner-only retention function may perform one narrowly shaped,
  -- one-way transition. All history and account identity columns stay put.
  IF current_setting('trimmy.guest_retention', true) = 'on'
      AND OLD.auth_redacted_at IS NULL
      AND NEW.auth_redacted_at IS NOT NULL
      AND NEW.credential_hash IS NULL
      AND NEW.creation_request_hash IS NULL
      AND NEW.creation_replay_hash IS NULL
      AND NEW.auth_redacted_at >= OLD.hard_expires_at + interval '7 days'
      AND clock_timestamp() >= OLD.hard_expires_at + interval '7 days'
      AND NEW.auth_redacted_at <= clock_timestamp()
      AND NEW.expires_at IS NOT DISTINCT FROM OLD.expires_at
      AND (NEW.id, NEW.user_id, NEW.created_at, NEW.hard_expires_at,
           NEW.last_seen_at, NEW.claimed_app_id, NEW.claimed_subject,
           NEW.claim_idempotency_key, NEW.claimed_at)
          IS NOT DISTINCT FROM
          (OLD.id, OLD.user_id, OLD.created_at, OLD.hard_expires_at,
           OLD.last_seen_at, OLD.claimed_app_id, OLD.claimed_subject,
           OLD.claim_idempotency_key, OLD.claimed_at)
      AND (
        (OLD.state = 'active' AND NEW.state = 'revoked'
          AND NEW.revoked_at = OLD.hard_expires_at)
        OR (OLD.state <> 'active' AND (NEW.state, NEW.revoked_at)
          IS NOT DISTINCT FROM (OLD.state, OLD.revoked_at))
      ) THEN
    RETURN NEW;
  END IF;

  IF (NEW.id, NEW.user_id, NEW.credential_hash, NEW.creation_request_hash,
      NEW.creation_replay_hash, NEW.auth_redacted_at, NEW.created_at, NEW.hard_expires_at)
      IS DISTINCT FROM
      (OLD.id, OLD.user_id, OLD.credential_hash, OLD.creation_request_hash,
      OLD.creation_replay_hash, OLD.auth_redacted_at, OLD.created_at, OLD.hard_expires_at) THEN
    RAISE EXCEPTION 'Guest session identity is immutable' USING ERRCODE = '23514';
  END IF;
  IF OLD.state <> 'active' AND NEW IS DISTINCT FROM OLD THEN
    RAISE EXCEPTION 'A finished guest session is immutable' USING ERRCODE = '23514';
  END IF;
  IF NEW.expires_at < OLD.expires_at OR NEW.last_seen_at < OLD.last_seen_at THEN
    RAISE EXCEPTION 'Guest session time cannot move backwards' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.protect_guest_session() FROM PUBLIC;

-- The old entry point cannot enforce a pre-credential source limit. A rolling
-- deploy therefore fails closed until the API uses the admission-bound form.
DROP FUNCTION trimmy.guest_create_session(text, text, uuid, text);

CREATE FUNCTION trimmy.guest_take_creation_attempt(selected_source_hash text)
RETURNS TABLE (outcome text, attempt_id bigint, retry_after_seconds bigint)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE observed_at timestamptz;
DECLARE selected_attempt_id bigint; ten_minute_count integer; daily_count integer;
DECLARE ten_minute_release timestamptz; daily_release timestamptz; retry_at timestamptz;
BEGIN
  IF selected_source_hash IS NULL OR selected_source_hash !~ '^[a-f0-9]{64}$' THEN
    RAISE EXCEPTION 'Guest creation source is invalid' USING ERRCODE = '22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.guest.creation.source:' || selected_source_hash, 0));
  -- Take time after the potentially blocking lock. A queued replica must see
  -- attempts committed by the lock holder and evaluate the real current window.
  observed_at := clock_timestamp();

  SELECT count(*)::integer + 1 INTO ten_minute_count
    FROM trimmy.guest_creation_attempts a
    WHERE a.source_hash = selected_source_hash
      AND a.attempted_at > observed_at - interval '10 minutes'
      AND a.attempted_at <= observed_at;
  SELECT count(*)::integer + 1 INTO daily_count
    FROM trimmy.guest_creation_attempts a
    WHERE a.source_hash = selected_source_hash
      AND a.attempted_at > observed_at - interval '24 hours'
      AND a.attempted_at <= observed_at;

  INSERT INTO trimmy.guest_creation_attempts(source_hash, attempted_at, admitted)
    VALUES (selected_source_hash, observed_at, ten_minute_count <= 6 AND daily_count <= 20)
    RETURNING id INTO selected_attempt_id;

  IF ten_minute_count > 6 THEN
    -- OFFSET limit-1 is intentional. A future retry is itself inserted before
    -- evaluation, so admission needs at most five existing 10-minute attempts.
    SELECT ranked.attempted_at + interval '10 minutes' INTO ten_minute_release
      FROM (
        SELECT a.attempted_at, a.id
        FROM trimmy.guest_creation_attempts a
        WHERE a.source_hash = selected_source_hash
          AND a.attempted_at > observed_at - interval '10 minutes'
          AND a.attempted_at <= observed_at
        ORDER BY a.attempted_at DESC, a.id DESC
        OFFSET 5 LIMIT 1
      ) ranked;
  END IF;
  IF daily_count > 20 THEN
    -- The same rule needs at most nineteen existing 24-hour attempts.
    SELECT ranked.attempted_at + interval '24 hours' INTO daily_release
      FROM (
        SELECT a.attempted_at, a.id
        FROM trimmy.guest_creation_attempts a
        WHERE a.source_hash = selected_source_hash
          AND a.attempted_at > observed_at - interval '24 hours'
          AND a.attempted_at <= observed_at
        ORDER BY a.attempted_at DESC, a.id DESC
        OFFSET 19 LIMIT 1
      ) ranked;
  END IF;
  retry_at := greatest(ten_minute_release, daily_release);
  IF retry_at IS NOT NULL THEN
    RETURN QUERY SELECT 'rate_limited'::text, NULL::bigint,
      greatest(1, ceil(extract(epoch FROM retry_at - observed_at)))::bigint;
    RETURN;
  END IF;
  RETURN QUERY SELECT 'admitted'::text, selected_attempt_id, NULL::bigint;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.guest_take_creation_attempt(text) FROM PUBLIC;

CREATE FUNCTION trimmy.guest_create_session(
  selected_source_hash text,
  selected_attempt_id bigint,
  selected_request_hash text,
  selected_replay_hash text,
  selected_id uuid,
  selected_credential_hash text
) RETURNS TABLE (
  outcome text,
  guest_id uuid,
  expires_at timestamptz,
  hard_expires_at timestamptz,
  retry_after_seconds bigint
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE account_id uuid; session_row trimmy.guest_sessions%ROWTYPE;
DECLARE observed_at timestamptz := clock_timestamp();
DECLARE attempt_row trimmy.guest_creation_attempts%ROWTYPE;
BEGIN
  IF selected_source_hash IS NULL OR selected_source_hash !~ '^[a-f0-9]{64}$'
      OR selected_attempt_id IS NULL OR selected_attempt_id < 1
      OR selected_request_hash IS NULL OR selected_request_hash !~ '^[a-f0-9]{64}$'
      OR selected_replay_hash IS NULL OR selected_replay_hash !~ '^[a-f0-9]{64}$'
      OR selected_id IS NULL
      OR selected_id::text !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      OR selected_credential_hash IS NULL OR selected_credential_hash !~ '^[a-f0-9]{64}$' THEN
    RAISE EXCEPTION 'Guest session input is invalid' USING ERRCODE = '22023';
  END IF;

  SELECT a.* INTO attempt_row FROM trimmy.guest_creation_attempts a
    WHERE a.id = selected_attempt_id AND a.source_hash = selected_source_hash FOR UPDATE;
  IF NOT FOUND OR NOT attempt_row.admitted OR attempt_row.consumed_at IS NOT NULL
      OR observed_at >= attempt_row.attempted_at + interval '30 seconds' THEN
    RETURN QUERY SELECT 'unavailable'::text, NULL::uuid, NULL::timestamptz,
      NULL::timestamptz, NULL::bigint;
    RETURN;
  END IF;
  PERFORM set_config('trimmy.guest_creation_consume', 'on', true);
  UPDATE trimmy.guest_creation_attempts SET consumed_at = observed_at
    WHERE id = attempt_row.id;
  PERFORM set_config('trimmy.guest_creation_consume', 'off', true);

  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.guest.creation:' || selected_request_hash, 0));

  SELECT s.* INTO session_row FROM trimmy.guest_sessions s
    WHERE s.creation_request_hash = selected_request_hash FOR UPDATE;
  IF FOUND THEN
    IF session_row.creation_replay_hash <> selected_replay_hash
        OR session_row.id <> selected_id
        OR session_row.credential_hash <> selected_credential_hash THEN
      RETURN QUERY SELECT 'conflict'::text, NULL::uuid, NULL::timestamptz,
        NULL::timestamptz, NULL::bigint;
    ELSE
      RETURN QUERY SELECT 'created'::text, session_row.id,
        session_row.created_at + interval '30 days', session_row.hard_expires_at,
        NULL::bigint;
    END IF;
    RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM trimmy.guest_sessions s
      WHERE s.id = selected_id OR s.credential_hash = selected_credential_hash
        OR s.creation_replay_hash = selected_replay_hash) THEN
    RETURN QUERY SELECT 'conflict'::text, NULL::uuid, NULL::timestamptz,
      NULL::timestamptz, NULL::bigint;
    RETURN;
  END IF;

  INSERT INTO trimmy.users DEFAULT VALUES RETURNING id INTO account_id;
  INSERT INTO trimmy.guest_sessions(
    id, user_id, credential_hash, creation_request_hash, creation_replay_hash,
    created_at, expires_at, hard_expires_at, last_seen_at)
  VALUES (
    selected_id, account_id, selected_credential_hash, selected_request_hash, selected_replay_hash,
    observed_at, observed_at + interval '30 days', observed_at + interval '90 days', observed_at);
  RETURN QUERY SELECT 'created'::text, selected_id,
    observed_at + interval '30 days', observed_at + interval '90 days', NULL::bigint;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.guest_create_session(text, bigint, text, text, uuid, text) FROM PUBLIC;

-- One call processes at most selected_batch_size rows from each category. It
-- never deletes a guest, user, paper row or Career row. The fixed seven-day
-- grace keeps uncertain creation/claim retries available after hard expiry.
CREATE FUNCTION trimmy.guest_auth_retention(selected_batch_size integer DEFAULT 500)
RETURNS TABLE (
  lock_acquired boolean,
  source_attempts_deleted integer,
  rate_windows_deleted integer,
  sessions_redacted integer,
  has_more boolean
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE observed_at timestamptz := clock_timestamp();
DECLARE source_count integer := 0; rate_count integer := 0; session_count integer := 0;
DECLARE more_rows boolean := false;
BEGIN
  IF selected_batch_size IS NULL OR selected_batch_size < 1 OR selected_batch_size > 1000 THEN
    RAISE EXCEPTION 'Guest retention batch size is invalid' USING ERRCODE = '22023';
  END IF;
  IF NOT pg_try_advisory_xact_lock(hashtextextended('trimmy.guest.auth.retention.v1', 0)) THEN
    RETURN QUERY SELECT false, 0, 0, 0, true;
    RETURN;
  END IF;

  PERFORM set_config('trimmy.guest_retention', 'on', true);
  WITH selected AS (
    SELECT a.id FROM trimmy.guest_creation_attempts a
    WHERE a.attempted_at < observed_at - interval '24 hours'
    ORDER BY a.attempted_at, a.id
    LIMIT selected_batch_size
  ), removed AS (
    DELETE FROM trimmy.guest_creation_attempts a USING selected
    WHERE a.id = selected.id RETURNING 1
  ) SELECT count(*)::integer INTO source_count FROM removed;

  WITH selected AS (
    SELECT r.ctid FROM trimmy.guest_rate_windows r
    WHERE r.window_started_at < observed_at - interval '48 hours'
    ORDER BY r.window_started_at, r.guest_session_id, r.scope
    LIMIT selected_batch_size
  ), removed AS (
    DELETE FROM trimmy.guest_rate_windows r USING selected
    WHERE r.ctid = selected.ctid RETURNING 1
  ) SELECT count(*)::integer INTO rate_count FROM removed;

  WITH selected AS (
    SELECT s.id FROM trimmy.guest_sessions s
    WHERE s.auth_redacted_at IS NULL
      AND s.hard_expires_at <= observed_at - interval '7 days'
    ORDER BY s.hard_expires_at, s.id
    LIMIT selected_batch_size
    FOR UPDATE SKIP LOCKED
  ), changed AS (
    UPDATE trimmy.guest_sessions s SET
      credential_hash = NULL,
      creation_request_hash = NULL,
      creation_replay_hash = NULL,
      auth_redacted_at = observed_at,
      state = CASE WHEN s.state = 'active' THEN 'revoked' ELSE s.state END,
      revoked_at = CASE WHEN s.state = 'active' THEN s.hard_expires_at ELSE s.revoked_at END
    FROM selected WHERE s.id = selected.id RETURNING 1
  ) SELECT count(*)::integer INTO session_count FROM changed;
  PERFORM set_config('trimmy.guest_retention', 'off', true);

  SELECT EXISTS (
    SELECT 1 FROM trimmy.guest_creation_attempts a
      WHERE a.attempted_at < observed_at - interval '24 hours'
    UNION ALL
    SELECT 1 FROM trimmy.guest_rate_windows r
      WHERE r.window_started_at < observed_at - interval '48 hours'
    UNION ALL
    SELECT 1 FROM trimmy.guest_sessions s
      WHERE s.auth_redacted_at IS NULL
        AND s.hard_expires_at <= observed_at - interval '7 days'
  ) INTO more_rows;
  RETURN QUERY SELECT true, source_count, rate_count, session_count, more_rows;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.guest_auth_retention(integer) FROM PUBLIC;

ALTER TABLE trimmy.guest_creation_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.guest_creation_attempts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE trimmy.guest_creation_attempts FROM PUBLIC;
REVOKE ALL ON SEQUENCE trimmy.guest_creation_attempts_id_seq FROM PUBLIC;

INSERT INTO trimmy.schema_migrations(version)
  VALUES ('0020_guest_creation_abuse_and_retention');
COMMIT;
