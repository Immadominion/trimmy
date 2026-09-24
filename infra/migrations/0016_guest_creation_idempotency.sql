-- 0016: durable idempotency before an anonymous credential exists.
-- The API stores only domain-separated digests and derives the replayable
-- credential from a client-held 256-bit proof; neither the raw
-- request UUID, replay proof nor token reaches PostgreSQL.
BEGIN;

ALTER TABLE trimmy.guest_sessions
  ADD COLUMN creation_request_hash trimmy.sha256_hex,
  ADD COLUMN creation_replay_hash trimmy.sha256_hex;

CREATE UNIQUE INDEX guest_sessions_creation_request
  ON trimmy.guest_sessions (creation_request_hash)
  WHERE creation_request_hash IS NOT NULL;

CREATE UNIQUE INDEX guest_sessions_creation_replay
  ON trimmy.guest_sessions (creation_replay_hash)
  WHERE creation_replay_hash IS NOT NULL;

CREATE OR REPLACE FUNCTION trimmy.protect_guest_session() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Guest session history cannot be deleted' USING ERRCODE = '23514';
  END IF;
  IF (NEW.id, NEW.user_id, NEW.credential_hash, NEW.creation_request_hash, NEW.creation_replay_hash,
      NEW.created_at, NEW.hard_expires_at)
      IS DISTINCT FROM
      (OLD.id, OLD.user_id, OLD.credential_hash, OLD.creation_request_hash, OLD.creation_replay_hash,
      OLD.created_at, OLD.hard_expires_at) THEN
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

-- Remove the non-idempotent entry point. During a rolling release an old API
-- instance fails closed rather than creating sessions outside this contract.
DROP FUNCTION trimmy.guest_create_session(uuid, text);

CREATE FUNCTION trimmy.guest_create_session(
  selected_request_hash text,
  selected_replay_hash text,
  selected_id uuid,
  selected_credential_hash text
) RETURNS TABLE (outcome text, guest_id uuid, expires_at timestamptz, hard_expires_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE account_id uuid; session_row trimmy.guest_sessions%ROWTYPE;
DECLARE observed_at timestamptz := clock_timestamp();
BEGIN
  IF selected_request_hash IS NULL OR selected_request_hash !~ '^[a-f0-9]{64}$'
      OR selected_replay_hash IS NULL OR selected_replay_hash !~ '^[a-f0-9]{64}$'
      OR selected_id IS NULL
      OR selected_id::text !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      OR selected_credential_hash IS NULL OR selected_credential_hash !~ '^[a-f0-9]{64}$' THEN
    RAISE EXCEPTION 'Guest session input is invalid' USING ERRCODE = '22023';
  END IF;

  -- The lock prevents two first requests from each inserting a users row. It
  -- is keyed by the stored digest, so the raw installation UUID stays outside
  -- the database even in lock metadata.
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.guest.creation:' || selected_request_hash, 0));

  SELECT s.* INTO session_row FROM trimmy.guest_sessions s
    WHERE s.creation_request_hash = selected_request_hash FOR UPDATE;
  IF FOUND THEN
    IF session_row.creation_replay_hash <> selected_replay_hash
        OR session_row.id <> selected_id
        OR session_row.credential_hash <> selected_credential_hash THEN
      RETURN QUERY SELECT 'conflict'::text, NULL::uuid, NULL::timestamptz, NULL::timestamptz;
    ELSE
      RETURN QUERY SELECT 'created'::text, session_row.id,
        session_row.created_at + interval '30 days', session_row.hard_expires_at;
    END IF;
    RETURN;
  END IF;

  -- A collision in independently derived material is a server/configuration
  -- failure. Never attach a new request to an existing guest or credential.
  IF EXISTS (SELECT 1 FROM trimmy.guest_sessions s
      WHERE s.id = selected_id OR s.credential_hash = selected_credential_hash
        OR s.creation_replay_hash = selected_replay_hash) THEN
    RETURN QUERY SELECT 'conflict'::text, NULL::uuid, NULL::timestamptz, NULL::timestamptz;
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
    observed_at + interval '30 days', observed_at + interval '90 days';
END;
$$;
REVOKE ALL ON FUNCTION trimmy.guest_create_session(text, text, uuid, text) FROM PUBLIC;

INSERT INTO trimmy.schema_migrations(version) VALUES ('0016_guest_creation_idempotency');
COMMIT;
