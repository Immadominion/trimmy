-- 0014: anonymous guest credentials and one-time practice identity claim.
-- Guest credentials can reach the simulated paper ledger only. The database
-- stores a SHA-256 digest, never the opaque credential returned to a client.
BEGIN;

CREATE TABLE trimmy.guest_sessions (
  id uuid PRIMARY KEY CHECK (id::text ~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'),
  user_id uuid NOT NULL UNIQUE REFERENCES trimmy.users(id),
  credential_hash trimmy.sha256_hex NOT NULL UNIQUE,
  state text NOT NULL DEFAULT 'active' CHECK (state IN ('active', 'claimed', 'revoked')),
  created_at timestamptz NOT NULL,
  expires_at timestamptz NOT NULL,
  hard_expires_at timestamptz NOT NULL,
  last_seen_at timestamptz NOT NULL,
  revoked_at timestamptz,
  claimed_app_id text COLLATE "C" CHECK (claimed_app_id ~ '^[A-Za-z0-9_-]{1,128}$'),
  claimed_subject text COLLATE "C" CHECK (claimed_subject ~ '^did:privy:[A-Za-z0-9]{1,128}$'),
  claim_idempotency_key uuid,
  claimed_at timestamptz,
  CHECK (isfinite(created_at) AND isfinite(expires_at) AND isfinite(hard_expires_at)
    AND isfinite(last_seen_at) AND expires_at > created_at
    AND hard_expires_at = created_at + interval '90 days'
    AND expires_at <= hard_expires_at AND last_seen_at >= created_at),
  CHECK ((state = 'active' AND revoked_at IS NULL AND claimed_app_id IS NULL
      AND claimed_subject IS NULL AND claim_idempotency_key IS NULL AND claimed_at IS NULL)
    OR (state = 'claimed' AND revoked_at IS NOT NULL AND claimed_app_id IS NOT NULL
      AND claimed_subject IS NOT NULL AND claim_idempotency_key IS NOT NULL
      AND claimed_at IS NOT NULL AND revoked_at = claimed_at)
    OR (state = 'revoked' AND revoked_at IS NOT NULL AND claimed_app_id IS NULL
      AND claimed_subject IS NULL AND claim_idempotency_key IS NULL AND claimed_at IS NULL)),
  CHECK (revoked_at IS NULL OR isfinite(revoked_at) AND revoked_at >= created_at),
  CHECK (claimed_at IS NULL OR isfinite(claimed_at) AND claimed_at >= created_at)
);

CREATE TABLE trimmy.guest_rate_windows (
  guest_session_id uuid NOT NULL REFERENCES trimmy.guest_sessions(id),
  scope text NOT NULL CHECK (scope IN ('paper_read', 'paper_preview', 'paper_commit', 'refresh', 'claim')),
  window_started_at timestamptz NOT NULL CHECK (isfinite(window_started_at)),
  request_count integer NOT NULL CHECK (request_count BETWEEN 1 AND 1000000),
  PRIMARY KEY (guest_session_id, scope, window_started_at)
);

CREATE INDEX guest_sessions_expiry ON trimmy.guest_sessions (hard_expires_at)
  WHERE state = 'active';

CREATE FUNCTION trimmy.protect_guest_session() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Guest session history cannot be deleted' USING ERRCODE = '23514';
  END IF;
  IF (NEW.id, NEW.user_id, NEW.credential_hash, NEW.created_at, NEW.hard_expires_at)
      IS DISTINCT FROM
      (OLD.id, OLD.user_id, OLD.credential_hash, OLD.created_at, OLD.hard_expires_at) THEN
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
CREATE TRIGGER guest_session_guard BEFORE UPDATE OR DELETE ON trimmy.guest_sessions
  FOR EACH ROW EXECUTE FUNCTION trimmy.protect_guest_session();

CREATE FUNCTION trimmy.guest_take_rate(
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

CREATE FUNCTION trimmy.guest_create_session(selected_id uuid, selected_hash text)
RETURNS TABLE (outcome text, guest_id uuid, expires_at timestamptz, hard_expires_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE account_id uuid; observed_at timestamptz := clock_timestamp();
BEGIN
  IF selected_id IS NULL OR selected_id::text !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      OR selected_hash IS NULL OR selected_hash !~ '^[a-f0-9]{64}$' THEN
    RAISE EXCEPTION 'Guest session input is invalid' USING ERRCODE = '22023';
  END IF;
  INSERT INTO trimmy.users DEFAULT VALUES RETURNING id INTO account_id;
  INSERT INTO trimmy.guest_sessions(
    id, user_id, credential_hash, created_at, expires_at, hard_expires_at, last_seen_at)
  VALUES (
    selected_id, account_id, selected_hash, observed_at,
    observed_at + interval '30 days', observed_at + interval '90 days', observed_at);
  RETURN QUERY SELECT 'created'::text, selected_id,
    observed_at + interval '30 days', observed_at + interval '90 days';
END;
$$;
REVOKE ALL ON FUNCTION trimmy.guest_create_session(uuid, text) FROM PUBLIC;

CREATE FUNCTION trimmy.guest_authorize(selected_hash text, selected_scope text)
RETURNS TABLE (outcome text, user_id uuid, guest_id uuid, expires_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE session_row trimmy.guest_sessions%ROWTYPE; account_status text;
DECLARE observed_at timestamptz := clock_timestamp();
BEGIN
  IF selected_hash IS NULL OR selected_hash !~ '^[a-f0-9]{64}$'
      OR selected_scope NOT IN ('paper_read', 'paper_preview', 'paper_commit') THEN
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

CREATE FUNCTION trimmy.guest_refresh_session(selected_hash text)
RETURNS TABLE (outcome text, guest_id uuid, expires_at timestamptz, hard_expires_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE session_row trimmy.guest_sessions%ROWTYPE; observed_at timestamptz := clock_timestamp();
DECLARE next_expiry timestamptz;
BEGIN
  IF selected_hash IS NULL OR selected_hash !~ '^[a-f0-9]{64}$' THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT s.* INTO session_row FROM trimmy.guest_sessions s
    WHERE s.credential_hash = selected_hash FOR UPDATE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  IF session_row.state <> 'active' THEN
    RETURN QUERY SELECT 'revoked'::text, session_row.id, session_row.expires_at, session_row.hard_expires_at;
    RETURN;
  END IF;
  IF observed_at >= session_row.expires_at OR observed_at >= session_row.hard_expires_at THEN
    UPDATE trimmy.guest_sessions SET state = 'revoked', revoked_at = observed_at,
      last_seen_at = greatest(last_seen_at, observed_at) WHERE id = session_row.id;
    RETURN QUERY SELECT 'expired'::text, session_row.id, session_row.expires_at, session_row.hard_expires_at;
    RETURN;
  END IF;
  IF NOT trimmy.guest_take_rate(session_row.id, 'refresh', observed_at) THEN
    RETURN QUERY SELECT 'rate_limited'::text, session_row.id, session_row.expires_at, session_row.hard_expires_at;
    RETURN;
  END IF;
  next_expiry := least(session_row.hard_expires_at,
    greatest(session_row.expires_at, observed_at + interval '30 days'));
  UPDATE trimmy.guest_sessions SET expires_at = next_expiry,
    last_seen_at = greatest(last_seen_at, observed_at) WHERE id = session_row.id;
  DELETE FROM trimmy.guest_rate_windows WHERE guest_session_id = session_row.id
    AND window_started_at < observed_at - interval '2 days';
  RETURN QUERY SELECT 'refreshed'::text, session_row.id, next_expiry, session_row.hard_expires_at;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.guest_refresh_session(text) FROM PUBLIC;

CREATE FUNCTION trimmy.guest_claim_session(
  selected_hash text,
  verified_app_id text,
  verified_subject text,
  selected_idempotency_key uuid
) RETURNS TABLE (outcome text, guest_id uuid, claimed_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE session_row trimmy.guest_sessions%ROWTYPE; observed_at timestamptz := clock_timestamp();
DECLARE mapped_user uuid; mapped_app text; mapped_subject text; account_status text;
BEGIN
  IF selected_hash IS NULL OR selected_hash !~ '^[a-f0-9]{64}$'
      OR verified_app_id IS NULL OR (verified_app_id COLLATE "C") !~ '^[A-Za-z0-9_-]{1,128}$'
      OR verified_subject IS NULL OR (verified_subject COLLATE "C") !~ '^did:privy:[A-Za-z0-9]{1,128}$'
      OR selected_idempotency_key IS NULL THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::timestamptz;
    RETURN;
  END IF;
  -- This is exactly the identity lock used by practice_provision_account, so a
  -- first sign-in and a guest claim cannot create competing account mappings.
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.practice.identity:' || verified_app_id || ':' || verified_subject, 0));
  SELECT s.* INTO session_row FROM trimmy.guest_sessions s
    WHERE s.credential_hash = selected_hash FOR UPDATE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::timestamptz;
    RETURN;
  END IF;
  IF session_row.state = 'claimed' THEN
    IF session_row.claimed_app_id = verified_app_id
        AND session_row.claimed_subject = verified_subject
        AND session_row.claim_idempotency_key = selected_idempotency_key THEN
      RETURN QUERY SELECT 'claimed'::text, session_row.id, session_row.claimed_at;
    ELSIF session_row.claimed_app_id = verified_app_id
        AND session_row.claimed_subject = verified_subject THEN
      RETURN QUERY SELECT 'idempotency_conflict'::text, session_row.id, session_row.claimed_at;
    ELSE
      RETURN QUERY SELECT 'claimed_elsewhere'::text, session_row.id, session_row.claimed_at;
    END IF;
    RETURN;
  END IF;
  IF session_row.state <> 'active' THEN
    RETURN QUERY SELECT 'revoked'::text, session_row.id, NULL::timestamptz;
    RETURN;
  END IF;
  IF observed_at >= session_row.expires_at OR observed_at >= session_row.hard_expires_at THEN
    UPDATE trimmy.guest_sessions SET state = 'revoked', revoked_at = observed_at,
      last_seen_at = greatest(last_seen_at, observed_at) WHERE id = session_row.id;
    RETURN QUERY SELECT 'expired'::text, session_row.id, NULL::timestamptz;
    RETURN;
  END IF;
  IF NOT trimmy.guest_take_rate(session_row.id, 'claim', observed_at) THEN
    RETURN QUERY SELECT 'rate_limited'::text, session_row.id, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT u.status INTO account_status FROM trimmy.users u WHERE u.id = session_row.user_id FOR UPDATE;
  IF account_status IS DISTINCT FROM 'active' THEN
    RETURN QUERY SELECT 'unavailable'::text, session_row.id, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT m.user_id INTO mapped_user FROM trimmy.practice_auth_identities m
    WHERE m.app_id = verified_app_id AND m.subject = verified_subject;
  IF mapped_user IS NOT NULL AND mapped_user <> session_row.user_id THEN
    RETURN QUERY SELECT 'identity_bound'::text, session_row.id, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT m.app_id, m.subject INTO mapped_app, mapped_subject
    FROM trimmy.practice_auth_identities m WHERE m.user_id = session_row.user_id;
  IF mapped_app IS NOT NULL AND (mapped_app <> verified_app_id OR mapped_subject <> verified_subject) THEN
    RETURN QUERY SELECT 'guest_bound'::text, session_row.id, NULL::timestamptz;
    RETURN;
  END IF;
  IF mapped_user IS NULL THEN
    INSERT INTO trimmy.practice_auth_identities(app_id, subject, user_id)
      VALUES (verified_app_id, verified_subject, session_row.user_id);
  END IF;
  UPDATE trimmy.guest_sessions SET state = 'claimed', revoked_at = observed_at,
    claimed_app_id = verified_app_id, claimed_subject = verified_subject,
    claim_idempotency_key = selected_idempotency_key, claimed_at = observed_at,
    last_seen_at = greatest(last_seen_at, observed_at)
    WHERE id = session_row.id;
  RETURN QUERY SELECT 'claimed'::text, session_row.id, observed_at;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.guest_claim_session(text, text, text, uuid) FROM PUBLIC;

ALTER TABLE trimmy.guest_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.guest_sessions FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.guest_rate_windows ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.guest_rate_windows FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE trimmy.guest_sessions, trimmy.guest_rate_windows FROM PUBLIC;

-- Deployment grants expose only fixed SECURITY DEFINER functions to the API
-- role. No guest table, users table, identity table, wallet table or financial
-- table is granted directly.
INSERT INTO trimmy.schema_migrations(version) VALUES ('0014_guest_sessions');
COMMIT;
