-- 0025: server-owned social relationships and safety. Invitations remain
-- unfunded. Fresh Privy X proof is consumed only by the atomic answer path.
BEGIN;

CREATE FUNCTION trimmy.social_x_subject_valid(selected text) RETURNS boolean
LANGUAGE sql IMMUTABLE
SET search_path = pg_catalog, trimmy AS $$
  SELECT selected IS NOT NULL
    AND selected ~ '^[1-9][0-9]{0,19}$'
    AND (length(selected) < 20
      OR (selected COLLATE "C") <= ('18446744073709551615' COLLATE "C"));
$$;
REVOKE ALL ON FUNCTION trimmy.social_x_subject_valid(text) FROM PUBLIC;

-- Refuse to choose an arbitrary historical identity or open invitation. These
-- checks intentionally run before any new unique object is installed.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM trimmy.provider_identities
    GROUP BY provider, user_id HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'Relationship migration found duplicate provider/user bindings'
      USING ERRCODE = '23514', CONSTRAINT = 'provider_identities_provider_user_preflight';
  END IF;
  IF EXISTS (
    SELECT 1 FROM trimmy.provider_identities
    GROUP BY provider, subject HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'Relationship migration found duplicate provider/subject bindings'
      USING ERRCODE = '23514', CONSTRAINT = 'provider_identities_provider_subject_preflight';
  END IF;
  IF EXISTS (
    SELECT 1 FROM trimmy.provider_identities
    WHERE provider <> 'x' OR NOT trimmy.social_x_subject_valid(subject)
      OR NOT isfinite(verified_at) OR NOT isfinite(created_at)
  ) THEN
    RAISE EXCEPTION 'Relationship migration found an invalid X binding'
      USING ERRCODE = '23514', CONSTRAINT = 'provider_identities_x_preflight';
  END IF;
  IF EXISTS (
    SELECT 1 FROM trimmy.invitations
    WHERE state IN ('addressed', 'offered')
    GROUP BY sender_user_id, recipient_provider, recipient_subject
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'Relationship migration found duplicate open invitation targets'
      USING ERRCODE = '23514', CONSTRAINT = 'invitation_open_target_preflight';
  END IF;
  IF EXISTS (
    SELECT 1 FROM trimmy.invitations i
    WHERE i.version >= 9007199254740991
      OR NOT isfinite(i.created_at) OR NOT isfinite(i.expires_at)
      OR i.accepted_at IS NOT NULL AND NOT isfinite(i.accepted_at)
      OR i.recipient_subject IS NOT NULL AND (
        i.recipient_provider <> 'x'
        OR NOT trimmy.social_x_subject_valid(i.recipient_subject)
        OR i.recipient_handle_snapshot IS NULL
        OR i.recipient_handle_snapshot <> lower(i.recipient_handle_snapshot)
        OR i.recipient_handle_snapshot !~ '^[a-z0-9_]{1,15}$')
      OR i.recipient_subject IS NULL AND (
        i.recipient_provider IS NOT NULL
        OR i.recipient_handle_snapshot IS NOT NULL
        OR i.recipient_user_id IS NOT NULL)
      OR i.state = 'draft' AND (
        i.recipient_subject IS NOT NULL OR i.recipient_user_id IS NOT NULL)
      OR i.state IN ('addressed', 'offered') AND i.recipient_user_id IS NOT NULL
      OR i.state IN ('accepted', 'declined') AND i.recipient_user_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Relationship migration found an invalid invitation history row'
      USING ERRCODE = '23514', CONSTRAINT = 'invitations_v2_preflight';
  END IF;
END;
$$;

ALTER TABLE trimmy.provider_identities
  ADD CONSTRAINT provider_identities_provider_user_key UNIQUE (provider, user_id);
CREATE UNIQUE INDEX invitation_open_target_key
  ON trimmy.invitations(sender_user_id, recipient_provider, recipient_subject)
  WHERE state IN ('addressed', 'offered');

CREATE TABLE trimmy.social_profiles (
  user_id uuid PRIMARY KEY REFERENCES trimmy.users(id),
  public_id uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  created_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp())
    CHECK (isfinite(created_at))
);

CREATE TABLE trimmy.social_invitation_create_receipts (
  sender_user_id uuid NOT NULL REFERENCES trimmy.users(id),
  mutation_id uuid NOT NULL,
  request_hash trimmy.sha256_hex NOT NULL,
  invitation_id uuid NOT NULL REFERENCES trimmy.invitations(id),
  created_at timestamptz NOT NULL CHECK (isfinite(created_at)),
  PRIMARY KEY (sender_user_id, mutation_id),
  UNIQUE (invitation_id)
);

CREATE TABLE trimmy.social_friendships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  public_id uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
  first_user_id uuid NOT NULL REFERENCES trimmy.users(id),
  second_user_id uuid NOT NULL REFERENCES trimmy.users(id),
  revision bigint NOT NULL CHECK (revision BETWEEN 1 AND 9007199254740991),
  state text COLLATE "C" NOT NULL CHECK (state IN ('active', 'removed')),
  source_invitation_id uuid NOT NULL REFERENCES trimmy.invitations(id),
  connected_at timestamptz NOT NULL CHECK (isfinite(connected_at)),
  ended_at timestamptz CHECK (ended_at IS NULL OR isfinite(ended_at)),
  created_at timestamptz NOT NULL CHECK (isfinite(created_at)),
  updated_at timestamptz NOT NULL CHECK (isfinite(updated_at) AND updated_at >= created_at),
  UNIQUE (first_user_id, second_user_id),
  CHECK (first_user_id < second_user_id),
  CHECK (connected_at >= created_at),
  CHECK ((state = 'active') = (ended_at IS NULL)),
  CHECK (ended_at IS NULL OR ended_at >= connected_at)
);
CREATE INDEX social_friendships_first_active
  ON trimmy.social_friendships(first_user_id, connected_at DESC, public_id DESC)
  WHERE state = 'active';
CREATE INDEX social_friendships_second_active
  ON trimmy.social_friendships(second_user_id, connected_at DESC, public_id DESC)
  WHERE state = 'active';

CREATE TABLE trimmy.social_friendship_events (
  friendship_id uuid NOT NULL REFERENCES trimmy.social_friendships(id),
  revision bigint NOT NULL CHECK (revision BETWEEN 1 AND 9007199254740991),
  event_kind text COLLATE "C" NOT NULL
    CHECK (event_kind IN ('accepted', 'removed', 'blocked', 'account_closed')),
  actor_user_id uuid REFERENCES trimmy.users(id),
  source_invitation_id uuid REFERENCES trimmy.invitations(id),
  resulting_state text COLLATE "C" NOT NULL CHECK (resulting_state IN ('active', 'removed')),
  created_at timestamptz NOT NULL CHECK (isfinite(created_at)),
  PRIMARY KEY (friendship_id, revision),
  CHECK ((event_kind = 'accepted') = (source_invitation_id IS NOT NULL)),
  CHECK ((event_kind = 'accepted') = (resulting_state = 'active')),
  CHECK (event_kind <> 'removed' OR actor_user_id IS NOT NULL),
  CHECK (event_kind <> 'blocked' OR actor_user_id IS NOT NULL),
  CHECK (event_kind <> 'account_closed' OR actor_user_id IS NOT NULL)
);

CREATE TABLE trimmy.social_friendship_receipts (
  actor_user_id uuid NOT NULL REFERENCES trimmy.users(id),
  mutation_id uuid NOT NULL,
  request_hash trimmy.sha256_hex NOT NULL,
  friendship_public_id uuid NOT NULL,
  base_revision bigint NOT NULL CHECK (base_revision BETWEEN 1 AND 9007199254740991),
  resulting_revision bigint NOT NULL CHECK (resulting_revision BETWEEN 2 AND 9007199254740991),
  created_at timestamptz NOT NULL CHECK (isfinite(created_at)),
  PRIMARY KEY (actor_user_id, mutation_id),
  FOREIGN KEY (friendship_public_id) REFERENCES trimmy.social_friendships(public_id)
);

CREATE TABLE trimmy.social_blocks (
  blocker_user_id uuid NOT NULL REFERENCES trimmy.users(id),
  blocked_user_id uuid NOT NULL REFERENCES trimmy.users(id),
  revision bigint NOT NULL CHECK (revision BETWEEN 1 AND 9007199254740991),
  state text COLLATE "C" NOT NULL CHECK (state IN ('active', 'inactive')),
  created_at timestamptz NOT NULL CHECK (isfinite(created_at)),
  updated_at timestamptz NOT NULL CHECK (isfinite(updated_at) AND updated_at >= created_at),
  PRIMARY KEY (blocker_user_id, blocked_user_id),
  CHECK (blocker_user_id <> blocked_user_id)
);
CREATE INDEX social_blocks_blocked_active
  ON trimmy.social_blocks(blocked_user_id, blocker_user_id)
  WHERE state = 'active';

CREATE TABLE trimmy.social_block_receipts (
  blocker_user_id uuid NOT NULL REFERENCES trimmy.users(id),
  mutation_id uuid NOT NULL,
  request_hash trimmy.sha256_hex NOT NULL,
  target_profile_id uuid NOT NULL REFERENCES trimmy.social_profiles(public_id),
  base_revision bigint NOT NULL CHECK (base_revision BETWEEN 0 AND 9007199254740991),
  requested_state text COLLATE "C" NOT NULL CHECK (requested_state IN ('active', 'inactive')),
  resulting_revision bigint NOT NULL CHECK (resulting_revision BETWEEN 1 AND 9007199254740991),
  created_at timestamptz NOT NULL CHECK (isfinite(created_at)),
  PRIMARY KEY (blocker_user_id, mutation_id)
);

CREATE TABLE trimmy.social_reason_reports (
  public_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_user_id uuid NOT NULL REFERENCES trimmy.users(id),
  mutation_id uuid NOT NULL,
  request_hash trimmy.sha256_hex NOT NULL,
  reason_public_id uuid NOT NULL REFERENCES trimmy.career_trade_reasons(public_id),
  category text COLLATE "C" NOT NULL
    CHECK (category IN ('spam', 'harassment', 'impersonation', 'unsafe', 'other')),
  created_at timestamptz NOT NULL CHECK (isfinite(created_at)),
  UNIQUE (reporter_user_id, mutation_id),
  UNIQUE (reporter_user_id, reason_public_id)
);

CREATE TABLE trimmy.social_reason_moderation (
  reason_public_id uuid PRIMARY KEY REFERENCES trimmy.career_trade_reasons(public_id),
  revision bigint NOT NULL CHECK (revision BETWEEN 1 AND 9007199254740991),
  state text COLLATE "C" NOT NULL CHECK (state IN ('visible', 'hidden')),
  decision_code text COLLATE "C" NOT NULL CHECK (decision_code IN (
    'spam', 'harassment', 'impersonation', 'unsafe', 'legal', 'other_reviewed',
    'appeal_granted', 'decision_corrected')),
  operator_reference text COLLATE "C" NOT NULL CHECK (
    length(operator_reference) BETWEEN 1 AND 100
    AND operator_reference ~ '^[\x20-\x7e]+$'),
  created_at timestamptz NOT NULL CHECK (isfinite(created_at)),
  updated_at timestamptz NOT NULL CHECK (isfinite(updated_at) AND updated_at >= created_at),
  CHECK ((state = 'hidden') = (decision_code IN (
    'spam', 'harassment', 'impersonation', 'unsafe', 'legal', 'other_reviewed')))
);

CREATE TABLE trimmy.social_reason_moderation_events (
  reason_public_id uuid NOT NULL REFERENCES trimmy.career_trade_reasons(public_id),
  revision bigint NOT NULL CHECK (revision BETWEEN 1 AND 9007199254740991),
  resulting_state text COLLATE "C" NOT NULL CHECK (resulting_state IN ('visible', 'hidden')),
  decision_code text COLLATE "C" NOT NULL CHECK (decision_code IN (
    'spam', 'harassment', 'impersonation', 'unsafe', 'legal', 'other_reviewed',
    'appeal_granted', 'decision_corrected')),
  operator_reference text COLLATE "C" NOT NULL CHECK (
    length(operator_reference) BETWEEN 1 AND 100
    AND operator_reference ~ '^[\x20-\x7e]+$'),
  created_at timestamptz NOT NULL CHECK (isfinite(created_at)),
  PRIMARY KEY (reason_public_id, revision)
);

CREATE TABLE trimmy.social_rate_windows (
  user_id uuid NOT NULL REFERENCES trimmy.users(id),
  action text COLLATE "C" NOT NULL CHECK (action IN (
    'invitation_create_day', 'friend_remove_10m', 'block_change_10m',
    'block_change_day', 'reason_report_day', 'social_list_read_minute')),
  window_started_at timestamptz NOT NULL CHECK (isfinite(window_started_at)),
  attempt_count integer NOT NULL CHECK (attempt_count BETWEEN 1 AND 1000000),
  window_ends_at timestamptz NOT NULL CHECK (
    isfinite(window_ends_at) AND window_ends_at > window_started_at),
  updated_at timestamptz NOT NULL CHECK (
    isfinite(updated_at) AND updated_at >= window_started_at),
  PRIMARY KEY (user_id, action, window_started_at)
);
CREATE INDEX social_rate_windows_expiry ON trimmy.social_rate_windows(window_ends_at);

-- Every social profile belongs to a saved account with an onboarding profile.
CREATE FUNCTION trimmy.social_profile_maybe_create() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE selected_user uuid := NEW.user_id;
BEGIN
  IF EXISTS (SELECT 1 FROM trimmy.product_profiles p WHERE p.user_id = selected_user)
      AND EXISTS (SELECT 1 FROM trimmy.practice_auth_identities a WHERE a.user_id = selected_user) THEN
    INSERT INTO trimmy.social_profiles(user_id) VALUES (selected_user)
      ON CONFLICT (user_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.social_profile_maybe_create() FROM PUBLIC;
CREATE TRIGGER social_profile_from_product
  AFTER INSERT ON trimmy.product_profiles
  FOR EACH ROW EXECUTE FUNCTION trimmy.social_profile_maybe_create();
CREATE TRIGGER social_profile_from_saved_identity
  AFTER INSERT ON trimmy.practice_auth_identities
  FOR EACH ROW EXECUTE FUNCTION trimmy.social_profile_maybe_create();

INSERT INTO trimmy.social_profiles(user_id, created_at)
SELECT p.user_id, date_trunc('milliseconds', statement_timestamp())
FROM trimmy.product_profiles p
JOIN trimmy.practice_auth_identities a ON a.user_id = p.user_id
ORDER BY p.user_id;

CREATE FUNCTION trimmy.social_snapshot_guard() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION '% history cannot be deleted', TG_TABLE_NAME
      USING ERRCODE = '23514', CONSTRAINT = 'social_history_preserved';
  END IF;
  IF TG_TABLE_NAME = 'social_profiles' THEN
    IF TG_OP = 'UPDATE' OR NOT isfinite(NEW.created_at) THEN
      RAISE EXCEPTION 'Social profile identity is immutable'
        USING ERRCODE = '23514', CONSTRAINT = 'social_profile_identity';
    END IF;
  ELSIF TG_TABLE_NAME = 'social_friendships' THEN
    IF TG_OP = 'INSERT' THEN
      IF NEW.revision <> 1 OR NEW.state <> 'active' OR NEW.ended_at IS NOT NULL
          OR NEW.connected_at <> NEW.created_at OR NEW.updated_at <> NEW.created_at THEN
        RAISE EXCEPTION 'Friendships begin active at revision one'
          USING ERRCODE = '23514', CONSTRAINT = 'social_friendship_initial_state';
      END IF;
    ELSIF (NEW.id, NEW.public_id, NEW.first_user_id, NEW.second_user_id, NEW.created_at)
        IS DISTINCT FROM
        (OLD.id, OLD.public_id, OLD.first_user_id, OLD.second_user_id, OLD.created_at)
        OR NEW.revision <> OLD.revision + 1 OR NEW.updated_at <= OLD.updated_at
        OR NEW.state = OLD.state
        OR NEW.state = 'active' AND NEW.connected_at <= OLD.updated_at
        OR NEW.state = 'removed' AND NEW.connected_at <> OLD.connected_at THEN
      RAISE EXCEPTION 'Friendship transition is invalid'
        USING ERRCODE = '23514', CONSTRAINT = 'social_friendship_transition';
    END IF;
  ELSIF TG_TABLE_NAME = 'social_blocks' THEN
    IF TG_OP = 'INSERT' THEN
      IF NEW.revision <> 1 OR NEW.state <> 'active' OR NEW.created_at <> NEW.updated_at THEN
        RAISE EXCEPTION 'Blocks begin active at revision one'
          USING ERRCODE = '23514', CONSTRAINT = 'social_block_initial_state';
      END IF;
    ELSIF (NEW.blocker_user_id, NEW.blocked_user_id, NEW.created_at)
        IS DISTINCT FROM (OLD.blocker_user_id, OLD.blocked_user_id, OLD.created_at)
        OR NEW.revision <> OLD.revision + 1 OR NEW.updated_at <= OLD.updated_at
        OR NEW.state = OLD.state THEN
      RAISE EXCEPTION 'Block transition is invalid'
        USING ERRCODE = '23514', CONSTRAINT = 'social_block_transition';
    END IF;
  ELSIF TG_TABLE_NAME = 'social_reason_moderation' THEN
    IF TG_OP = 'INSERT' THEN
      IF NEW.revision <> 1 OR NEW.created_at <> NEW.updated_at THEN
        RAISE EXCEPTION 'Moderation begins at revision one'
          USING ERRCODE = '23514', CONSTRAINT = 'social_moderation_initial_state';
      END IF;
    ELSIF (NEW.reason_public_id, NEW.created_at)
        IS DISTINCT FROM (OLD.reason_public_id, OLD.created_at)
        OR NEW.revision <> OLD.revision + 1 OR NEW.updated_at <= OLD.updated_at
        OR NEW.state = OLD.state THEN
      RAISE EXCEPTION 'Moderation transition is invalid'
        USING ERRCODE = '23514', CONSTRAINT = 'social_moderation_transition';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.social_snapshot_guard() FROM PUBLIC;
CREATE TRIGGER social_profiles_guard BEFORE INSERT OR UPDATE OR DELETE ON trimmy.social_profiles
  FOR EACH ROW EXECUTE FUNCTION trimmy.social_snapshot_guard();
CREATE TRIGGER social_friendships_guard BEFORE INSERT OR UPDATE OR DELETE ON trimmy.social_friendships
  FOR EACH ROW EXECUTE FUNCTION trimmy.social_snapshot_guard();
CREATE TRIGGER social_blocks_guard BEFORE INSERT OR UPDATE OR DELETE ON trimmy.social_blocks
  FOR EACH ROW EXECUTE FUNCTION trimmy.social_snapshot_guard();
CREATE TRIGGER social_reason_moderation_guard
  BEFORE INSERT OR UPDATE OR DELETE ON trimmy.social_reason_moderation
  FOR EACH ROW EXECUTE FUNCTION trimmy.social_snapshot_guard();

CREATE TRIGGER social_invitation_create_receipts_append_only
  BEFORE UPDATE OR DELETE ON trimmy.social_invitation_create_receipts
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();
CREATE TRIGGER social_friendship_events_append_only
  BEFORE UPDATE OR DELETE ON trimmy.social_friendship_events
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();
CREATE TRIGGER social_friendship_receipts_append_only
  BEFORE UPDATE OR DELETE ON trimmy.social_friendship_receipts
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();
CREATE TRIGGER social_block_receipts_append_only
  BEFORE UPDATE OR DELETE ON trimmy.social_block_receipts
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();
CREATE TRIGGER social_reason_reports_append_only
  BEFORE UPDATE OR DELETE ON trimmy.social_reason_reports
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();
CREATE TRIGGER social_reason_moderation_events_append_only
  BEFORE UPDATE OR DELETE ON trimmy.social_reason_moderation_events
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();

CREATE FUNCTION trimmy.social_friendship_event_pair() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE selected_id uuid;
DECLARE snapshot trimmy.social_friendships%ROWTYPE;
BEGIN
  -- The constraint function protects both sides of the snapshot/event pair.
  -- Their foreign-key columns have different names, so select the key from
  -- the row shape belonging to the table that fired the trigger.
  IF TG_TABLE_NAME = 'social_friendships' THEN
    selected_id := NEW.id;
  ELSE
    selected_id := NEW.friendship_id;
  END IF;
  SELECT f.* INTO snapshot FROM trimmy.social_friendships f WHERE f.id = selected_id;
  IF NOT FOUND OR NOT EXISTS (
    SELECT 1 FROM trimmy.social_friendship_events e
    WHERE e.friendship_id = snapshot.id AND e.revision = snapshot.revision
      AND e.resulting_state = snapshot.state AND e.created_at = snapshot.updated_at
      AND (e.source_invitation_id IS NOT DISTINCT FROM
        CASE WHEN e.event_kind = 'accepted' THEN snapshot.source_invitation_id ELSE NULL END)
  ) THEN
    RAISE EXCEPTION 'Friendship snapshot requires its matching event'
      USING ERRCODE = '23514', CONSTRAINT = 'social_friendship_event_pair';
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.social_friendship_event_pair() FROM PUBLIC;
CREATE CONSTRAINT TRIGGER social_friendship_snapshot_event_pair
  AFTER INSERT OR UPDATE ON trimmy.social_friendships
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
  EXECUTE FUNCTION trimmy.social_friendship_event_pair();
CREATE CONSTRAINT TRIGGER social_friendship_event_snapshot_pair
  AFTER INSERT ON trimmy.social_friendship_events
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
  EXECUTE FUNCTION trimmy.social_friendship_event_pair();

CREATE FUNCTION trimmy.social_moderation_event_pair() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE selected_reason uuid := coalesce(NEW.reason_public_id, OLD.reason_public_id);
DECLARE snapshot trimmy.social_reason_moderation%ROWTYPE;
BEGIN
  SELECT m.* INTO snapshot FROM trimmy.social_reason_moderation m
    WHERE m.reason_public_id = selected_reason;
  IF NOT FOUND OR NOT EXISTS (
    SELECT 1 FROM trimmy.social_reason_moderation_events e
    WHERE e.reason_public_id = snapshot.reason_public_id
      AND e.revision = snapshot.revision
      AND (e.resulting_state, e.decision_code, e.operator_reference, e.created_at)
          IS NOT DISTINCT FROM
          (snapshot.state, snapshot.decision_code, snapshot.operator_reference, snapshot.updated_at)
  ) THEN
    RAISE EXCEPTION 'Moderation snapshot requires its matching event'
      USING ERRCODE = '23514', CONSTRAINT = 'social_moderation_event_pair';
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.social_moderation_event_pair() FROM PUBLIC;
CREATE CONSTRAINT TRIGGER social_moderation_snapshot_event_pair
  AFTER INSERT OR UPDATE ON trimmy.social_reason_moderation
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
  EXECUTE FUNCTION trimmy.social_moderation_event_pair();
CREATE CONSTRAINT TRIGGER social_moderation_event_snapshot_pair
  AFTER INSERT ON trimmy.social_reason_moderation_events
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
  EXECUTE FUNCTION trimmy.social_moderation_event_pair();

-- All quotas use one locked row. The caller must already hold the user's
-- social-user advisory lock for relationship mutations.
CREATE FUNCTION trimmy.social_rate_take_internal(selected_user uuid, selected_action text)
RETURNS TABLE (allowed boolean, retry_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE observed_at timestamptz := date_trunc('milliseconds', clock_timestamp());
DECLARE started_at timestamptz;
DECLARE ends_at timestamptz;
DECLARE maximum integer;
DECLARE current_count integer;
BEGIN
  CASE selected_action
    WHEN 'invitation_create_day' THEN started_at := date_trunc('day', observed_at AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'; maximum := 10; ends_at := started_at + interval '1 day';
    WHEN 'friend_remove_10m' THEN started_at := to_timestamp(floor(extract(epoch FROM observed_at) / 600) * 600); maximum := 20; ends_at := started_at + interval '10 minutes';
    WHEN 'block_change_10m' THEN started_at := to_timestamp(floor(extract(epoch FROM observed_at) / 600) * 600); maximum := 30; ends_at := started_at + interval '10 minutes';
    WHEN 'block_change_day' THEN started_at := date_trunc('day', observed_at AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'; maximum := 100; ends_at := started_at + interval '1 day';
    WHEN 'reason_report_day' THEN started_at := date_trunc('day', observed_at AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'; maximum := 20; ends_at := started_at + interval '1 day';
    WHEN 'social_list_read_minute' THEN started_at := date_trunc('minute', observed_at); maximum := 120; ends_at := started_at + interval '1 minute';
    ELSE RETURN QUERY SELECT false, NULL::timestamptz; RETURN;
  END CASE;
  INSERT INTO trimmy.social_rate_windows(
    user_id, action, window_started_at, attempt_count, window_ends_at, updated_at)
  VALUES (selected_user, selected_action, started_at, 1, ends_at, observed_at)
  ON CONFLICT (user_id, action, window_started_at) DO UPDATE
    SET attempt_count = trimmy.social_rate_windows.attempt_count + 1,
        updated_at = EXCLUDED.updated_at
  RETURNING attempt_count INTO current_count;
  RETURN QUERY SELECT current_count <= maximum,
    CASE WHEN current_count <= maximum THEN NULL::timestamptz ELSE ends_at END;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.social_rate_take_internal(uuid, text) FROM PUBLIC;

CREATE FUNCTION trimmy.social_bind_verified_x_identity_internal(
  selected_user uuid,
  selected_subject text,
  selected_handle text,
  selected_verified_at timestamptz
) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE existing_user uuid;
DECLARE existing_subject text;
BEGIN
  IF selected_user IS NULL OR selected_subject IS NULL
      OR NOT trimmy.social_x_subject_valid(selected_subject)
      OR selected_handle IS NULL OR selected_handle <> lower(selected_handle)
      OR selected_handle !~ '^[a-z0-9_]{1,15}$'
      OR selected_verified_at IS NULL OR NOT isfinite(selected_verified_at)
      OR selected_verified_at > clock_timestamp() + interval '5 minutes' THEN
    RETURN 'invalid';
  END IF;
  SELECT p.user_id INTO existing_user FROM trimmy.provider_identities p
    WHERE p.provider = 'x' AND p.subject = selected_subject;
  IF FOUND AND existing_user <> selected_user THEN RETURN 'identity_conflict'; END IF;
  SELECT p.subject INTO existing_subject FROM trimmy.provider_identities p
    WHERE p.provider = 'x' AND p.user_id = selected_user;
  IF FOUND AND existing_subject <> selected_subject THEN RETURN 'identity_conflict'; END IF;
  INSERT INTO trimmy.provider_identities(
    user_id, provider, subject, handle_snapshot, verified_at)
  VALUES (selected_user, 'x', selected_subject, selected_handle, selected_verified_at)
  ON CONFLICT (provider, subject) DO UPDATE SET
    handle_snapshot = EXCLUDED.handle_snapshot,
    verified_at = greatest(trimmy.provider_identities.verified_at, EXCLUDED.verified_at)
  WHERE trimmy.provider_identities.user_id = EXCLUDED.user_id;
  RETURN 'saved';
END;
$$;
REVOKE ALL ON FUNCTION trimmy.social_bind_verified_x_identity_internal(
  uuid, text, text, timestamptz) FROM PUBLIC;

CREATE FUNCTION trimmy.social_activate_friendship_internal(
  selected_first uuid,
  selected_second uuid,
  selected_invitation uuid,
  selected_actor uuid
) RETURNS TABLE (
  outcome text, friendship_id uuid, friendship_public_id uuid,
  friendship_revision bigint, connected_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE first_id uuid := least(selected_first, selected_second);
DECLARE second_id uuid := greatest(selected_first, selected_second);
DECLARE current_row trimmy.social_friendships%ROWTYPE;
DECLARE observed_at timestamptz;
BEGIN
  IF selected_first IS NULL OR selected_second IS NULL OR selected_first = selected_second
      OR selected_invitation IS NULL OR selected_actor IS NULL THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::uuid, NULL::bigint, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT f.* INTO current_row FROM trimmy.social_friendships f
    WHERE f.first_user_id = first_id AND f.second_user_id = second_id FOR UPDATE;
  IF FOUND AND current_row.state = 'active' THEN
    RETURN QUERY SELECT 'already_friends'::text, current_row.id, current_row.public_id,
      current_row.revision, current_row.connected_at;
    RETURN;
  END IF;
  observed_at := date_trunc('milliseconds', clock_timestamp());
  IF NOT FOUND THEN
    INSERT INTO trimmy.social_friendships(
      first_user_id, second_user_id, revision, state, source_invitation_id,
      connected_at, ended_at, created_at, updated_at)
    VALUES (first_id, second_id, 1, 'active', selected_invitation,
      observed_at, NULL, observed_at, observed_at)
    RETURNING * INTO current_row;
  ELSE
    IF current_row.revision >= 9007199254740991 THEN
      RETURN QUERY SELECT 'revision_exhausted'::text, NULL::uuid, NULL::uuid,
        NULL::bigint, NULL::timestamptz;
      RETURN;
    END IF;
    observed_at := greatest(observed_at, current_row.updated_at + interval '1 millisecond');
    IF EXISTS (
      SELECT 1 FROM trimmy.invitations i
      WHERE i.id = selected_invitation AND i.accepted_at <= current_row.ended_at
    ) THEN
      RETURN QUERY SELECT 'revision_conflict'::text, current_row.id, current_row.public_id,
        current_row.revision, current_row.connected_at;
      RETURN;
    END IF;
    UPDATE trimmy.social_friendships SET
      revision = current_row.revision + 1,
      state = 'active', source_invitation_id = selected_invitation,
      connected_at = observed_at, ended_at = NULL, updated_at = observed_at
    WHERE id = current_row.id RETURNING * INTO current_row;
  END IF;
  INSERT INTO trimmy.social_friendship_events(
    friendship_id, revision, event_kind, actor_user_id, source_invitation_id,
    resulting_state, created_at)
  VALUES (current_row.id, current_row.revision, 'accepted', selected_actor,
    selected_invitation, 'active', current_row.updated_at);
  RETURN QUERY SELECT 'accepted'::text, current_row.id, current_row.public_id,
    current_row.revision, current_row.connected_at;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.social_activate_friendship_internal(
  uuid, uuid, uuid, uuid) FROM PUBLIC;

CREATE FUNCTION trimmy.social_invitation_create(
  selected_user uuid,
  selected_mutation uuid,
  selected_request_hash text,
  selected_expires_at timestamptz
) RETURNS TABLE (
  outcome text, created boolean, invitation_id uuid, state text,
  funding_kind text, sender_social_id uuid, sender_handle text,
  sender_persona text, sender_rank_id text, recipient_provider text,
  recipient_handle_snapshot text, expires_at timestamptz,
  created_at timestamptz, accepted_at timestamptz, version bigint,
  party_role text, retry_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE existing trimmy.social_invitation_create_receipts%ROWTYPE;
DECLARE invitation trimmy.invitations%ROWTYPE;
DECLARE allowed boolean;
DECLARE limited_until timestamptz;
DECLARE receipt_conflict boolean := false;
DECLARE observed_at timestamptz := date_trunc('milliseconds', clock_timestamp());
BEGIN
  IF selected_user IS NULL OR selected_mutation IS NULL
      OR selected_request_hash IS NULL OR selected_request_hash !~ '^[a-f0-9]{64}$'
      OR selected_expires_at IS NULL OR NOT isfinite(selected_expires_at)
      OR trimmy.practice_current_user() IS DISTINCT FROM selected_user THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::boolean, NULL::uuid, NULL::text,
      NULL::text, NULL::uuid, NULL::text, NULL::text, NULL::text, NULL::text,
      NULL::text, NULL::timestamptz, NULL::timestamptz, NULL::timestamptz,
      NULL::bigint, NULL::text, NULL::timestamptz;
    RETURN;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.social-user:' || selected_user::text, 0));
  SELECT r.* INTO existing FROM trimmy.social_invitation_create_receipts r
    WHERE r.sender_user_id = selected_user AND r.mutation_id = selected_mutation;
  IF FOUND THEN
    IF existing.request_hash <> selected_request_hash THEN
      receipt_conflict := true;
    ELSE
      SELECT i.* INTO invitation FROM trimmy.invitations i
        WHERE i.id = existing.invitation_id;
      RETURN QUERY SELECT 'saved'::text, false, invitation.id,
        invitation.state, invitation.funding_kind, social.public_id,
        profile.handle, profile.persona, coalesce(career.rank_id, 'rookie'),
        invitation.recipient_provider, invitation.recipient_handle_snapshot,
        invitation.expires_at, invitation.created_at, invitation.accepted_at,
        invitation.version, 'sender'::text, NULL::timestamptz
      FROM trimmy.social_profiles social
      JOIN trimmy.product_profiles profile ON profile.user_id = social.user_id
      LEFT JOIN trimmy.career_profiles career ON career.user_id = social.user_id
      WHERE social.user_id = selected_user;
    END IF;
    IF NOT receipt_conflict THEN RETURN; END IF;
  END IF;
  PERFORM 1 FROM trimmy.users u
    WHERE u.id = selected_user AND u.status = 'active' FOR UPDATE;
  IF NOT FOUND OR NOT EXISTS (
    SELECT 1 FROM trimmy.practice_auth_identities a WHERE a.user_id = selected_user
  ) THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::boolean, NULL::uuid,
      NULL::text, NULL::text, NULL::uuid, NULL::text, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz,
      NULL::timestamptz, NULL::bigint, NULL::text, NULL::timestamptz;
    RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM trimmy.social_profiles p WHERE p.user_id = selected_user) THEN
    RETURN QUERY SELECT 'profile_missing'::text, NULL::boolean, NULL::uuid,
      NULL::text, NULL::text, NULL::uuid, NULL::text, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz,
      NULL::timestamptz, NULL::bigint, NULL::text, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT r.allowed, r.retry_at INTO allowed, limited_until
    FROM trimmy.social_rate_take_internal(selected_user, 'invitation_create_day') r;
  IF NOT allowed THEN
    RETURN QUERY SELECT 'rate_limited'::text, NULL::boolean, NULL::uuid,
      NULL::text, NULL::text, NULL::uuid, NULL::text, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz,
      NULL::timestamptz, NULL::bigint, NULL::text, limited_until;
    RETURN;
  END IF;
  IF receipt_conflict THEN
    RETURN QUERY SELECT 'idempotency_conflict'::text, NULL::boolean,
      NULL::uuid, NULL::text, NULL::text, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::text, NULL::timestamptz,
      NULL::timestamptz, NULL::timestamptz, NULL::bigint, NULL::text,
      NULL::timestamptz;
    RETURN;
  END IF;
  IF selected_expires_at <= observed_at
      OR selected_expires_at > observed_at + interval '30 days' THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::boolean, NULL::uuid, NULL::text,
      NULL::text, NULL::uuid, NULL::text, NULL::text, NULL::text, NULL::text,
      NULL::text, NULL::timestamptz, NULL::timestamptz, NULL::timestamptz,
      NULL::bigint, NULL::text, NULL::timestamptz;
    RETURN;
  END IF;
  UPDATE trimmy.invitations i SET state = 'expired', version = i.version + 1
    WHERE i.sender_user_id = selected_user
      AND i.state IN ('draft', 'addressed', 'offered')
      AND i.expires_at <= observed_at;
  IF (SELECT count(*) FROM trimmy.invitations
      WHERE invitations.sender_user_id = selected_user
        AND invitations.state IN ('draft', 'addressed', 'offered')) >= 20 THEN
    RETURN QUERY SELECT 'open_limit'::text, NULL::boolean, NULL::uuid,
      NULL::text, NULL::text, NULL::uuid, NULL::text, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz,
      NULL::timestamptz, NULL::bigint, NULL::text, NULL::timestamptz;
    RETURN;
  END IF;
  INSERT INTO trimmy.invitations(
    sender_user_id, state, funding_kind, expires_at, version, created_at)
  VALUES (selected_user, 'draft', 'unfunded', selected_expires_at, 0, observed_at)
  RETURNING * INTO invitation;
  INSERT INTO trimmy.social_invitation_create_receipts(
    sender_user_id, mutation_id, request_hash, invitation_id, created_at)
  VALUES (selected_user, selected_mutation, selected_request_hash,
    invitation.id, observed_at);
  RETURN QUERY SELECT 'saved'::text, true, invitation.id, invitation.state,
    invitation.funding_kind, social.public_id, profile.handle, profile.persona,
    coalesce(career.rank_id, 'rookie'), invitation.recipient_provider,
    invitation.recipient_handle_snapshot, invitation.expires_at,
    invitation.created_at, invitation.accepted_at, invitation.version,
    'sender'::text, NULL::timestamptz
  FROM trimmy.social_profiles social
  JOIN trimmy.product_profiles profile ON profile.user_id = social.user_id
  LEFT JOIN trimmy.career_profiles career ON career.user_id = social.user_id
  WHERE social.user_id = selected_user;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.social_invitation_create(
  uuid, uuid, text, timestamptz) FROM PUBLIC;

CREATE FUNCTION trimmy.social_invitation_sender_action(
  selected_user uuid,
  selected_invitation uuid,
  selected_expected_version bigint,
  selected_action text,
  selected_resolved_x_subject text,
  selected_resolved_x_handle text
) RETURNS TABLE (
  outcome text, invitation_id uuid, state text, funding_kind text,
  recipient_provider text, recipient_handle_snapshot text,
  expires_at timestamptz, created_at timestamptz, accepted_at timestamptz,
  version bigint, sender_social_id uuid, sender_handle text,
  sender_persona text, sender_rank_id text, party_role text
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE invitation trimmy.invitations%ROWTYPE;
DECLARE target_user uuid;
DECLARE first_id uuid;
DECLARE second_id uuid;
DECLARE action_subject text;
DECLARE sender_social uuid;
DECLARE sender_handle_value text;
DECLARE sender_persona_value text;
DECLARE sender_rank_value text;
DECLARE block_barrier timestamptz;
DECLARE observed_at timestamptz := date_trunc('milliseconds', clock_timestamp());
BEGIN
  IF selected_user IS NULL OR selected_invitation IS NULL
      OR selected_expected_version IS NULL OR selected_expected_version < 0
      OR selected_action NOT IN ('address', 'offer', 'cancel')
      OR selected_action = 'address' AND (
        selected_resolved_x_subject IS NULL OR selected_resolved_x_handle IS NULL)
      OR selected_action <> 'address' AND (
        selected_resolved_x_subject IS NOT NULL OR selected_resolved_x_handle IS NOT NULL)
      OR selected_resolved_x_subject IS NOT NULL
        AND NOT trimmy.social_x_subject_valid(selected_resolved_x_subject)
      OR selected_resolved_x_handle IS NOT NULL AND (
        selected_resolved_x_handle <> lower(selected_resolved_x_handle)
        OR selected_resolved_x_handle !~ '^[a-z0-9_]{1,15}$')
      OR trimmy.practice_current_user() IS DISTINCT FROM selected_user THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz,
      NULL::timestamptz, NULL::bigint, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::text;
    RETURN;
  END IF;
  IF selected_action = 'address' THEN
    action_subject := selected_resolved_x_subject;
  ELSE
    SELECT i.recipient_subject INTO action_subject FROM trimmy.invitations i
      WHERE i.id = selected_invitation AND i.sender_user_id = selected_user;
  END IF;
  IF action_subject IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'trimmy.social-subject:x:' || action_subject, 0));
  END IF;
  SELECT p.user_id INTO target_user FROM trimmy.provider_identities p
    WHERE p.provider = 'x' AND p.subject = action_subject;
  IF target_user IS NOT NULL THEN
    first_id := least(selected_user, target_user);
    second_id := greatest(selected_user, target_user);
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'trimmy.social-user:' || first_id::text, 0));
    IF second_id <> first_id THEN
      PERFORM pg_advisory_xact_lock(hashtextextended(
        'trimmy.social-user:' || second_id::text, 0));
    END IF;
  ELSE
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'trimmy.social-user:' || selected_user::text, 0));
  END IF;
  PERFORM 1 FROM trimmy.users u
    WHERE u.id = selected_user OR u.id = target_user
    ORDER BY u.id FOR UPDATE;
  IF NOT EXISTS (SELECT 1 FROM trimmy.users u
      WHERE u.id = selected_user AND u.status = 'active') OR NOT EXISTS (
    SELECT 1 FROM trimmy.practice_auth_identities a WHERE a.user_id = selected_user
  ) THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz,
      NULL::timestamptz, NULL::bigint, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::text;
    RETURN;
  END IF;
  IF target_user IS NOT NULL AND target_user <> selected_user THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'trimmy.social-pair:' || first_id::text || ':' || second_id::text, 0));
  END IF;
  SELECT social.public_id, profile.handle, profile.persona,
      coalesce(career.rank_id, 'rookie')
    INTO sender_social, sender_handle_value, sender_persona_value, sender_rank_value
  FROM trimmy.social_profiles social
  JOIN trimmy.product_profiles profile ON profile.user_id = social.user_id
  LEFT JOIN trimmy.career_profiles career ON career.user_id = social.user_id
  WHERE social.user_id = selected_user;
  IF sender_social IS NULL THEN
    RETURN QUERY SELECT 'profile_missing'::text, NULL::uuid, NULL::text,
      NULL::text, NULL::text, NULL::text, NULL::timestamptz,
      NULL::timestamptz, NULL::timestamptz, NULL::bigint, NULL::uuid,
      NULL::text, NULL::text, NULL::text, NULL::text;
    RETURN;
  END IF;
  IF target_user IS NOT NULL AND target_user <> selected_user
      AND NOT EXISTS (SELECT 1 FROM trimmy.users u
        WHERE u.id = target_user AND u.status = 'active') THEN
    target_user := NULL;
  END IF;
  SELECT i.* INTO invitation FROM trimmy.invitations i
    WHERE i.id = selected_invitation FOR UPDATE;
  IF NOT FOUND OR invitation.sender_user_id <> selected_user THEN
    RETURN QUERY SELECT 'not_found'::text, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz,
      NULL::timestamptz, NULL::bigint, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::text;
    RETURN;
  END IF;
  IF invitation.state IN ('draft', 'addressed', 'offered')
      AND invitation.expires_at <= observed_at THEN
    UPDATE trimmy.invitations i SET state = 'expired', version = i.version + 1
      WHERE i.id = invitation.id RETURNING i.* INTO invitation;
    RETURN QUERY SELECT 'expired'::text, invitation.id, invitation.state,
      invitation.funding_kind, invitation.recipient_provider,
      invitation.recipient_handle_snapshot, invitation.expires_at,
      invitation.created_at, invitation.accepted_at, invitation.version,
      sender_social, sender_handle_value, sender_persona_value,
      sender_rank_value, 'sender'::text;
    RETURN;
  END IF;
  IF invitation.version <> selected_expected_version THEN
    RETURN QUERY SELECT 'revision_conflict'::text, invitation.id, invitation.state,
      invitation.funding_kind, invitation.recipient_provider,
      invitation.recipient_handle_snapshot, invitation.expires_at,
      invitation.created_at, invitation.accepted_at, invitation.version,
      sender_social, sender_handle_value, sender_persona_value,
      sender_rank_value, 'sender'::text;
    RETURN;
  END IF;
  IF selected_action <> 'address'
      AND invitation.recipient_subject IS DISTINCT FROM action_subject THEN
    RETURN QUERY SELECT 'revision_conflict'::text, invitation.id, invitation.state,
      invitation.funding_kind, invitation.recipient_provider,
      invitation.recipient_handle_snapshot, invitation.expires_at,
      invitation.created_at, invitation.accepted_at, invitation.version,
      sender_social, sender_handle_value, sender_persona_value,
      sender_rank_value, 'sender'::text;
    RETURN;
  END IF;
  IF selected_action = 'address' THEN
    IF invitation.state <> 'draft' THEN
      RETURN QUERY SELECT 'revision_conflict'::text, invitation.id, invitation.state,
        invitation.funding_kind, invitation.recipient_provider,
        invitation.recipient_handle_snapshot, invitation.expires_at,
        invitation.created_at, invitation.accepted_at, invitation.version,
        sender_social, sender_handle_value, sender_persona_value,
        sender_rank_value, 'sender'::text;
      RETURN;
    END IF;
    IF EXISTS (SELECT 1 FROM trimmy.provider_identities p
        WHERE p.provider = 'x' AND p.user_id = selected_user
          AND p.subject = selected_resolved_x_subject) THEN
      RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::text, NULL::text,
        NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz,
        NULL::timestamptz, NULL::bigint, NULL::uuid, NULL::text, NULL::text,
        NULL::text, NULL::text;
      RETURN;
    END IF;
    IF target_user IS NOT NULL THEN
      SELECT max(b.updated_at) INTO block_barrier FROM trimmy.social_blocks b
        WHERE (b.blocker_user_id, b.blocked_user_id) IN (
          (first_id, second_id), (second_id, first_id));
      IF EXISTS (SELECT 1 FROM trimmy.social_blocks b
          WHERE b.state = 'active' AND (b.blocker_user_id, b.blocked_user_id) IN (
            (first_id, second_id), (second_id, first_id)))
          OR block_barrier IS NOT NULL AND invitation.created_at <= block_barrier THEN
        UPDATE trimmy.invitations i SET state = 'canceled', version = i.version + 1
          WHERE i.id = invitation.id RETURNING i.* INTO invitation;
        RETURN QUERY SELECT 'blocked'::text,
          invitation.id, invitation.state, invitation.funding_kind,
          invitation.recipient_provider, invitation.recipient_handle_snapshot,
          invitation.expires_at, invitation.created_at, invitation.accepted_at,
          invitation.version, sender_social, sender_handle_value,
          sender_persona_value, sender_rank_value, 'sender'::text;
        RETURN;
      END IF;
      IF EXISTS (SELECT 1 FROM trimmy.social_friendships f
          WHERE f.first_user_id = first_id AND f.second_user_id = second_id
            AND f.state = 'active') THEN
        RETURN QUERY SELECT 'already_friends'::text,
          invitation.id, invitation.state, invitation.funding_kind,
          invitation.recipient_provider, invitation.recipient_handle_snapshot,
          invitation.expires_at, invitation.created_at, invitation.accepted_at,
          invitation.version, sender_social, sender_handle_value,
          sender_persona_value, sender_rank_value, 'sender'::text;
        RETURN;
      END IF;
    END IF;
    UPDATE trimmy.invitations i SET state = 'expired', version = i.version + 1
      WHERE i.sender_user_id = selected_user AND i.id <> invitation.id
        AND i.recipient_provider = 'x'
        AND i.recipient_subject = selected_resolved_x_subject
        AND i.state IN ('addressed', 'offered') AND i.expires_at <= observed_at;
    IF EXISTS (SELECT 1 FROM trimmy.invitations i
        WHERE i.sender_user_id = selected_user AND i.id <> invitation.id
          AND i.recipient_provider = 'x'
          AND i.recipient_subject = selected_resolved_x_subject
          AND i.state IN ('addressed', 'offered')) THEN
      RETURN QUERY SELECT 'revision_conflict'::text,
        invitation.id, invitation.state, invitation.funding_kind,
        invitation.recipient_provider, invitation.recipient_handle_snapshot,
        invitation.expires_at, invitation.created_at, invitation.accepted_at,
        invitation.version, sender_social, sender_handle_value,
        sender_persona_value, sender_rank_value, 'sender'::text;
      RETURN;
    END IF;
    UPDATE trimmy.invitations i SET state = 'addressed', recipient_provider = 'x',
      recipient_subject = selected_resolved_x_subject,
      recipient_handle_snapshot = selected_resolved_x_handle,
      version = i.version + 1
    WHERE i.id = invitation.id RETURNING i.* INTO invitation;
  ELSIF selected_action = 'offer' AND invitation.state = 'addressed' THEN
    IF target_user IS NOT NULL THEN
      SELECT max(b.updated_at) INTO block_barrier FROM trimmy.social_blocks b
        WHERE (b.blocker_user_id, b.blocked_user_id) IN (
          (first_id, second_id), (second_id, first_id));
      IF EXISTS (SELECT 1 FROM trimmy.social_blocks b
          WHERE b.state = 'active' AND (b.blocker_user_id, b.blocked_user_id) IN (
            (first_id, second_id), (second_id, first_id)))
          OR block_barrier IS NOT NULL AND invitation.created_at <= block_barrier THEN
        UPDATE trimmy.invitations i SET state = 'canceled', version = i.version + 1
          WHERE i.id = invitation.id RETURNING i.* INTO invitation;
        RETURN QUERY SELECT 'blocked'::text,
          invitation.id, invitation.state, invitation.funding_kind,
          invitation.recipient_provider, invitation.recipient_handle_snapshot,
          invitation.expires_at, invitation.created_at, invitation.accepted_at,
          invitation.version, sender_social, sender_handle_value,
          sender_persona_value, sender_rank_value, 'sender'::text;
        RETURN;
      END IF;
      IF EXISTS (SELECT 1 FROM trimmy.social_friendships f
          WHERE f.first_user_id = first_id AND f.second_user_id = second_id
            AND f.state = 'active') THEN
        RETURN QUERY SELECT 'already_friends'::text,
          invitation.id, invitation.state, invitation.funding_kind,
          invitation.recipient_provider, invitation.recipient_handle_snapshot,
          invitation.expires_at, invitation.created_at, invitation.accepted_at,
          invitation.version, sender_social, sender_handle_value,
          sender_persona_value, sender_rank_value, 'sender'::text;
        RETURN;
      END IF;
    END IF;
    UPDATE trimmy.invitations i SET state = 'offered', version = i.version + 1
      WHERE i.id = invitation.id RETURNING i.* INTO invitation;
  ELSIF selected_action = 'cancel' AND invitation.state IN ('draft', 'addressed', 'offered') THEN
    UPDATE trimmy.invitations i SET state = 'canceled', version = i.version + 1
      WHERE i.id = invitation.id RETURNING i.* INTO invitation;
  ELSE
    RETURN QUERY SELECT 'revision_conflict'::text, invitation.id, invitation.state,
      invitation.funding_kind, invitation.recipient_provider,
      invitation.recipient_handle_snapshot, invitation.expires_at,
      invitation.created_at, invitation.accepted_at, invitation.version,
      sender_social, sender_handle_value, sender_persona_value,
      sender_rank_value, 'sender'::text;
    RETURN;
  END IF;
  RETURN QUERY SELECT 'saved'::text, invitation.id, invitation.state,
    invitation.funding_kind, invitation.recipient_provider,
    invitation.recipient_handle_snapshot, invitation.expires_at,
    invitation.created_at, invitation.accepted_at, invitation.version,
    sender_social, sender_handle_value, sender_persona_value,
    sender_rank_value, 'sender'::text;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.social_invitation_sender_action(
  uuid, uuid, bigint, text, text, text) FROM PUBLIC;

CREATE FUNCTION trimmy.social_invitation_answer(
  selected_user uuid,
  selected_invitation uuid,
  selected_expected_version bigint,
  selected_action text,
  selected_fresh_x_subject text,
  selected_fresh_x_handle text,
  selected_fresh_x_verified_at timestamptz
) RETURNS TABLE (
  outcome text, invitation_id uuid, state text, funding_kind text,
  recipient_provider text, recipient_handle_snapshot text,
  expires_at timestamptz, created_at timestamptz, accepted_at timestamptz,
  version bigint, sender_social_id uuid, sender_handle text,
  sender_persona text, sender_rank_id text, party_role text,
  friendship_id uuid, friendship_revision bigint,
  connected_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE invitation trimmy.invitations%ROWTYPE;
DECLARE sender_id uuid;
DECLARE first_id uuid;
DECLARE second_id uuid;
DECLARE binding_outcome text;
DECLARE activation record;
DECLARE existing_identity uuid;
DECLARE existing_subject text;
DECLARE observed_at timestamptz := date_trunc('milliseconds', clock_timestamp());
DECLARE block_barrier timestamptz;
DECLARE sender_social uuid;
DECLARE sender_handle_value text;
DECLARE sender_persona_value text;
DECLARE sender_rank_value text;
BEGIN
  IF selected_user IS NULL OR selected_invitation IS NULL
      OR selected_expected_version IS NULL OR selected_expected_version < 0
      OR selected_action NOT IN ('accept', 'decline')
      OR selected_fresh_x_subject IS NULL
      OR NOT trimmy.social_x_subject_valid(selected_fresh_x_subject)
      OR selected_fresh_x_handle IS NULL
      OR selected_fresh_x_handle <> lower(selected_fresh_x_handle)
      OR selected_fresh_x_handle !~ '^[a-z0-9_]{1,15}$'
      OR selected_fresh_x_verified_at IS NULL
      OR NOT isfinite(selected_fresh_x_verified_at)
      OR selected_fresh_x_verified_at > clock_timestamp() + interval '5 minutes'
      OR trimmy.practice_current_user() IS DISTINCT FROM selected_user THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz,
      NULL::timestamptz, NULL::bigint, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::uuid, NULL::bigint, NULL::timestamptz;
    RETURN;
  END IF;

  -- Fresh proof is serialized before any account or pair lock. This first read
  -- does not lock the invitation, avoiding an invitation/user lock inversion.
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.social-subject:x:' || selected_fresh_x_subject, 0));
  SELECT i.sender_user_id INTO sender_id FROM trimmy.invitations i
    WHERE i.id = selected_invitation
      AND i.recipient_provider = 'x'
      AND i.recipient_subject = selected_fresh_x_subject;
  IF sender_id IS NULL OR sender_id = selected_user THEN
    RETURN QUERY SELECT 'not_found'::text, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz,
      NULL::timestamptz, NULL::bigint, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::uuid, NULL::bigint, NULL::timestamptz;
    RETURN;
  END IF;
  first_id := least(sender_id, selected_user);
  second_id := greatest(sender_id, selected_user);
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.social-user:' || first_id::text, 0));
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.social-user:' || second_id::text, 0));
  PERFORM 1 FROM trimmy.users u WHERE u.id IN (first_id, second_id)
    ORDER BY u.id FOR UPDATE;
  IF (SELECT count(*) FROM trimmy.users u
      WHERE u.id IN (first_id, second_id) AND u.status = 'active') <> 2
      OR NOT EXISTS (SELECT 1 FROM trimmy.practice_auth_identities a
        WHERE a.user_id = selected_user) THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz,
      NULL::timestamptz, NULL::bigint, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::uuid, NULL::bigint, NULL::timestamptz;
    RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM trimmy.social_profiles p WHERE p.user_id = selected_user)
      OR NOT EXISTS (SELECT 1 FROM trimmy.social_profiles p WHERE p.user_id = sender_id) THEN
    RETURN QUERY SELECT 'profile_missing'::text, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz,
      NULL::timestamptz, NULL::bigint, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::uuid, NULL::bigint, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT social.public_id, profile.handle, profile.persona,
      coalesce(career.rank_id, 'rookie')
    INTO sender_social, sender_handle_value, sender_persona_value, sender_rank_value
  FROM trimmy.social_profiles social
  JOIN trimmy.product_profiles profile ON profile.user_id = social.user_id
  LEFT JOIN trimmy.career_profiles career ON career.user_id = social.user_id
  WHERE social.user_id = sender_id;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.social-pair:' || first_id::text || ':' || second_id::text, 0));
  PERFORM 1 FROM trimmy.social_blocks b
    WHERE (b.blocker_user_id, b.blocked_user_id) IN (
      (first_id, second_id), (second_id, first_id))
    ORDER BY b.blocker_user_id, b.blocked_user_id FOR UPDATE;
  PERFORM 1 FROM trimmy.social_friendships f
    WHERE f.first_user_id = first_id AND f.second_user_id = second_id FOR UPDATE;
  SELECT i.* INTO invitation FROM trimmy.invitations i
    WHERE i.id = selected_invitation FOR UPDATE;
  IF NOT FOUND OR invitation.sender_user_id <> sender_id
      OR invitation.recipient_provider <> 'x'
      OR invitation.recipient_subject <> selected_fresh_x_subject THEN
    RETURN QUERY SELECT 'not_found'::text, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz,
      NULL::timestamptz, NULL::bigint, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::uuid, NULL::bigint, NULL::timestamptz;
    RETURN;
  END IF;

  SELECT p.user_id INTO existing_identity FROM trimmy.provider_identities p
    WHERE p.provider = 'x' AND p.subject = selected_fresh_x_subject;
  SELECT p.subject INTO existing_subject FROM trimmy.provider_identities p
    WHERE p.provider = 'x' AND p.user_id = selected_user;
  IF existing_identity IS NOT NULL AND existing_identity <> selected_user
      OR existing_subject IS NOT NULL AND existing_subject <> selected_fresh_x_subject THEN
    RETURN QUERY SELECT 'identity_conflict'::text, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz,
      NULL::timestamptz, NULL::bigint, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::uuid, NULL::bigint, NULL::timestamptz;
    RETURN;
  END IF;

  -- A terminal exact retry still requires fresh provider proof. It may refresh
  -- the harmless handle snapshot but creates no second transition event.
  IF invitation.state IN ('accepted', 'declined') THEN
    IF invitation.recipient_user_id = selected_user
        AND invitation.state = (CASE selected_action
          WHEN 'accept' THEN 'accepted' ELSE 'declined' END)
        AND invitation.version = selected_expected_version + 1 THEN
      binding_outcome := trimmy.social_bind_verified_x_identity_internal(
        selected_user, selected_fresh_x_subject, selected_fresh_x_handle,
        selected_fresh_x_verified_at);
      IF binding_outcome <> 'saved' THEN
        RETURN QUERY SELECT binding_outcome, NULL::uuid, NULL::text, NULL::text,
          NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz,
          NULL::timestamptz, NULL::bigint, NULL::uuid, NULL::text, NULL::text,
          NULL::text, NULL::text, NULL::uuid, NULL::bigint, NULL::timestamptz;
      ELSE
        RETURN QUERY SELECT
          CASE selected_action WHEN 'accept' THEN 'accepted' ELSE 'saved' END,
          invitation.id, invitation.state, invitation.funding_kind,
          invitation.recipient_provider, invitation.recipient_handle_snapshot,
          invitation.expires_at, invitation.created_at, invitation.accepted_at,
          invitation.version, sender_social, sender_handle_value,
          sender_persona_value, sender_rank_value, 'recipient'::text,
          friendship.public_id, friendship_event.revision,
          friendship_event.created_at
        FROM (SELECT 1) unit
        LEFT JOIN trimmy.social_friendships friendship
          ON friendship.first_user_id = first_id AND friendship.second_user_id = second_id
          AND invitation.state = 'accepted'
        LEFT JOIN trimmy.social_friendship_events friendship_event
          ON friendship_event.friendship_id = friendship.id
          AND friendship_event.source_invitation_id = invitation.id
          AND friendship_event.event_kind = 'accepted';
      END IF;
    ELSE
      RETURN QUERY SELECT 'revision_conflict'::text, invitation.id, invitation.state,
        invitation.funding_kind, invitation.recipient_provider,
        invitation.recipient_handle_snapshot, invitation.expires_at,
        invitation.created_at, invitation.accepted_at, invitation.version,
        sender_social, sender_handle_value, sender_persona_value,
        sender_rank_value, 'recipient'::text,
        NULL::uuid, NULL::bigint, NULL::timestamptz;
    END IF;
    RETURN;
  END IF;
  IF invitation.state <> 'offered' OR invitation.version <> selected_expected_version THEN
    RETURN QUERY SELECT 'revision_conflict'::text, invitation.id, invitation.state,
      invitation.funding_kind, invitation.recipient_provider,
      invitation.recipient_handle_snapshot, invitation.expires_at,
      invitation.created_at, invitation.accepted_at, invitation.version,
      sender_social, sender_handle_value, sender_persona_value,
      sender_rank_value, 'recipient'::text,
      NULL::uuid, NULL::bigint, NULL::timestamptz;
    RETURN;
  END IF;
  IF invitation.expires_at <= observed_at THEN
    UPDATE trimmy.invitations i SET state = 'expired', version = i.version + 1
      WHERE i.id = invitation.id RETURNING i.* INTO invitation;
    RETURN QUERY SELECT 'not_found'::text, invitation.id, invitation.state,
      invitation.funding_kind, invitation.recipient_provider,
      invitation.recipient_handle_snapshot, invitation.expires_at,
      invitation.created_at, invitation.accepted_at, invitation.version,
      sender_social, sender_handle_value, sender_persona_value,
      sender_rank_value, 'recipient'::text,
      NULL::uuid, NULL::bigint, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT max(b.updated_at) INTO block_barrier FROM trimmy.social_blocks b
    WHERE (b.blocker_user_id, b.blocked_user_id) IN (
      (first_id, second_id), (second_id, first_id));
  IF EXISTS (SELECT 1 FROM trimmy.social_blocks b
      WHERE b.state = 'active' AND (b.blocker_user_id, b.blocked_user_id) IN (
        (first_id, second_id), (second_id, first_id)))
      OR block_barrier IS NOT NULL AND invitation.created_at <= block_barrier THEN
    UPDATE trimmy.invitations i SET state = 'canceled', version = i.version + 1
      WHERE i.id = invitation.id RETURNING i.* INTO invitation;
    RETURN QUERY SELECT 'blocked'::text, invitation.id, invitation.state,
      invitation.funding_kind, invitation.recipient_provider,
      invitation.recipient_handle_snapshot, invitation.expires_at,
      invitation.created_at, invitation.accepted_at, invitation.version,
      sender_social, sender_handle_value, sender_persona_value,
      sender_rank_value, 'recipient'::text,
      NULL::uuid, NULL::bigint, NULL::timestamptz;
    RETURN;
  END IF;
  IF EXISTS (SELECT 1 FROM trimmy.social_friendships f
      WHERE f.first_user_id = first_id AND f.second_user_id = second_id
        AND f.state = 'active') THEN
    RETURN QUERY SELECT 'already_friends'::text, invitation.id, invitation.state,
      invitation.funding_kind, invitation.recipient_provider,
      invitation.recipient_handle_snapshot, invitation.expires_at,
      invitation.created_at, invitation.accepted_at, invitation.version,
      sender_social, sender_handle_value, sender_persona_value,
      sender_rank_value, 'recipient'::text, friendship.public_id,
      friendship.revision, friendship.connected_at
    FROM trimmy.social_friendships friendship
    WHERE friendship.first_user_id = first_id
      AND friendship.second_user_id = second_id;
    RETURN;
  END IF;
  IF selected_action = 'accept' AND (
      (SELECT count(*) FROM trimmy.social_friendships f
        WHERE f.state = 'active' AND (f.first_user_id = sender_id OR f.second_user_id = sender_id)) >= 500
      OR (SELECT count(*) FROM trimmy.social_friendships f
        WHERE f.state = 'active' AND (f.first_user_id = selected_user OR f.second_user_id = selected_user)) >= 500) THEN
    RETURN QUERY SELECT 'friend_limit'::text, invitation.id, invitation.state,
      invitation.funding_kind, invitation.recipient_provider,
      invitation.recipient_handle_snapshot, invitation.expires_at,
      invitation.created_at, invitation.accepted_at, invitation.version,
      sender_social, sender_handle_value, sender_persona_value,
      sender_rank_value, 'recipient'::text,
      NULL::uuid, NULL::bigint, NULL::timestamptz;
    RETURN;
  END IF;

  binding_outcome := trimmy.social_bind_verified_x_identity_internal(
    selected_user, selected_fresh_x_subject, selected_fresh_x_handle,
    selected_fresh_x_verified_at);
  IF binding_outcome <> 'saved' THEN
    RETURN QUERY SELECT binding_outcome, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::timestamptz, NULL::timestamptz,
      NULL::timestamptz, NULL::bigint, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::uuid, NULL::bigint, NULL::timestamptz;
    RETURN;
  END IF;
  UPDATE trimmy.invitations i SET
    state = CASE selected_action WHEN 'accept' THEN 'accepted' ELSE 'declined' END,
    recipient_user_id = selected_user,
    recipient_handle_snapshot = selected_fresh_x_handle,
    accepted_at = CASE selected_action WHEN 'accept' THEN observed_at ELSE NULL END,
    version = i.version + 1
  WHERE i.id = invitation.id RETURNING i.* INTO invitation;
  IF selected_action = 'accept' THEN
    SELECT * INTO activation FROM trimmy.social_activate_friendship_internal(
      first_id, second_id, invitation.id, selected_user);
    IF activation.outcome <> 'accepted' THEN
      RAISE EXCEPTION 'Friendship activation failed after invitation answer'
        USING ERRCODE = '23514', CONSTRAINT = 'social_invitation_friendship_atomic';
    END IF;
    RETURN QUERY SELECT 'accepted'::text, invitation.id, invitation.state,
      invitation.funding_kind, invitation.recipient_provider,
      invitation.recipient_handle_snapshot, invitation.expires_at,
      invitation.created_at, invitation.accepted_at, invitation.version,
      sender_social, sender_handle_value, sender_persona_value,
      sender_rank_value, 'recipient'::text,
      activation.friendship_public_id, activation.friendship_revision,
      activation.connected_at;
  ELSE
    RETURN QUERY SELECT 'saved'::text, invitation.id, invitation.state,
      invitation.funding_kind, invitation.recipient_provider,
      invitation.recipient_handle_snapshot, invitation.expires_at,
      invitation.created_at, invitation.accepted_at, invitation.version,
      sender_social, sender_handle_value, sender_persona_value,
      sender_rank_value, 'recipient'::text,
      NULL::uuid, NULL::bigint, NULL::timestamptz;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.social_invitation_answer(
  uuid, uuid, bigint, text, text, text, timestamptz) FROM PUBLIC;

CREATE FUNCTION trimmy.social_invitation_list(
  selected_user uuid,
  selected_fresh_x_subject text,
  selected_box text,
  selected_cursor_at timestamptz,
  selected_cursor_invitation uuid,
  selected_limit integer
) RETURNS TABLE (
  outcome text, principal_social_id uuid, incoming_status text,
  invitation_id uuid, state text,
  funding_kind text, sender_social_id uuid, sender_handle text,
  sender_persona text, sender_rank_id text, recipient_provider text,
  recipient_handle_snapshot text, expires_at timestamptz, created_at timestamptz,
  accepted_at timestamptz, version bigint, party_role text, retry_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE account_status text;
DECLARE allowed boolean;
DECLARE limited_until timestamptz;
DECLARE principal_profile uuid;
DECLARE incoming text := CASE WHEN selected_fresh_x_subject IS NULL
  THEN 'x_link_required' ELSE 'available' END;
DECLARE observed_at timestamptz := date_trunc('milliseconds', clock_timestamp());
BEGIN
  IF selected_user IS NULL OR selected_box NOT IN ('open', 'history')
      OR selected_limit IS NULL OR selected_limit < 1 OR selected_limit > 51
      OR (selected_cursor_at IS NULL) <> (selected_cursor_invitation IS NULL)
      OR selected_cursor_at IS NOT NULL AND NOT isfinite(selected_cursor_at)
      OR selected_fresh_x_subject IS NOT NULL
        AND NOT trimmy.social_x_subject_valid(selected_fresh_x_subject)
      OR trimmy.practice_current_user() IS DISTINCT FROM selected_user THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, incoming, NULL::uuid, NULL::text,
      NULL::text, NULL::uuid, NULL::text, NULL::text, NULL::text, NULL::text,
      NULL::text, NULL::timestamptz, NULL::timestamptz, NULL::timestamptz,
      NULL::bigint, NULL::text, NULL::timestamptz;
    RETURN;
  END IF;
  IF selected_fresh_x_subject IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'trimmy.social-subject:x:' || selected_fresh_x_subject, 0));
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.social-user:' || selected_user::text, 0));
  SELECT u.status INTO account_status FROM trimmy.users u
    WHERE u.id = selected_user FOR UPDATE;
  IF account_status IS DISTINCT FROM 'active'
      OR NOT EXISTS (SELECT 1 FROM trimmy.practice_auth_identities a
        WHERE a.user_id = selected_user) THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::uuid, incoming, NULL::uuid, NULL::text,
      NULL::text, NULL::uuid, NULL::text, NULL::text, NULL::text, NULL::text,
      NULL::text, NULL::timestamptz, NULL::timestamptz, NULL::timestamptz,
      NULL::bigint, NULL::text, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT p.public_id INTO principal_profile FROM trimmy.social_profiles p
    WHERE p.user_id = selected_user;
  IF principal_profile IS NULL THEN
    RETURN QUERY SELECT 'profile_missing'::text, NULL::uuid, incoming,
      NULL::uuid, NULL::text, NULL::text, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::text, NULL::timestamptz,
      NULL::timestamptz, NULL::timestamptz, NULL::bigint, NULL::text,
      NULL::timestamptz;
    RETURN;
  END IF;
  SELECT r.allowed, r.retry_at INTO allowed, limited_until
    FROM trimmy.social_rate_take_internal(selected_user, 'social_list_read_minute') r;
  IF NOT allowed THEN
    RETURN QUERY SELECT 'rate_limited'::text, principal_profile, incoming,
      NULL::uuid, NULL::text,
      NULL::text, NULL::uuid, NULL::text, NULL::text, NULL::text, NULL::text,
      NULL::text, NULL::timestamptz, NULL::timestamptz, NULL::timestamptz,
      NULL::bigint, NULL::text, limited_until;
    RETURN;
  END IF;
  IF selected_fresh_x_subject IS NOT NULL AND (
      EXISTS (SELECT 1 FROM trimmy.provider_identities p
        WHERE p.provider = 'x' AND p.subject = selected_fresh_x_subject
          AND p.user_id <> selected_user)
      OR EXISTS (SELECT 1 FROM trimmy.provider_identities p
        WHERE p.provider = 'x' AND p.user_id = selected_user
          AND p.subject <> selected_fresh_x_subject)) THEN
    RETURN QUERY SELECT 'identity_conflict'::text, principal_profile, incoming,
      NULL::uuid, NULL::text, NULL::text, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::text, NULL::timestamptz,
      NULL::timestamptz, NULL::timestamptz, NULL::bigint, NULL::text,
      NULL::timestamptz;
    RETURN;
  END IF;
  -- Fresh proof can resolve a previously external offer to this account. The
  -- caller's social-user lock freezes every block transition involving it while
  -- stale offers are canceled before any sender projection is returned.
  IF selected_fresh_x_subject IS NOT NULL THEN
    UPDATE trimmy.invitations i SET state = 'canceled', version = i.version + 1
      WHERE i.state = 'offered' AND i.recipient_provider = 'x'
        AND i.recipient_subject = selected_fresh_x_subject
        AND (EXISTS (SELECT 1 FROM trimmy.social_blocks b
          WHERE b.state = 'active' AND (
            (b.blocker_user_id = selected_user AND b.blocked_user_id = i.sender_user_id)
            OR (b.blocker_user_id = i.sender_user_id AND b.blocked_user_id = selected_user)))
          OR i.created_at <= (SELECT max(b.updated_at) FROM trimmy.social_blocks b
            WHERE (b.blocker_user_id = selected_user AND b.blocked_user_id = i.sender_user_id)
              OR (b.blocker_user_id = i.sender_user_id AND b.blocked_user_id = selected_user)));
  END IF;
  UPDATE trimmy.invitations i SET state = 'expired', version = i.version + 1
    WHERE i.state IN ('draft', 'addressed', 'offered') AND i.expires_at <= observed_at
      AND (i.sender_user_id = selected_user OR i.recipient_user_id = selected_user
        OR selected_fresh_x_subject IS NOT NULL AND i.state = 'offered'
          AND i.recipient_provider = 'x'
          AND i.recipient_subject = selected_fresh_x_subject);
  RETURN QUERY
  SELECT 'found'::text, principal_profile, incoming, i.id, i.state, i.funding_kind,
    sender_social.public_id, sender_profile.handle, sender_profile.persona,
    coalesce(sender_career.rank_id, 'rookie'), i.recipient_provider,
    i.recipient_handle_snapshot,
    i.expires_at, i.created_at, i.accepted_at, i.version,
    CASE WHEN i.sender_user_id = selected_user THEN 'sender' ELSE 'recipient' END,
    NULL::timestamptz
  FROM trimmy.invitations i
  JOIN trimmy.users sender ON sender.id = i.sender_user_id
  JOIN trimmy.social_profiles sender_social ON sender_social.user_id = i.sender_user_id
  JOIN trimmy.product_profiles sender_profile ON sender_profile.user_id = i.sender_user_id
  LEFT JOIN trimmy.career_profiles sender_career ON sender_career.user_id = i.sender_user_id
  WHERE (i.sender_user_id = selected_user
      OR i.recipient_user_id = selected_user
      OR selected_fresh_x_subject IS NOT NULL AND i.state = 'offered'
        AND i.recipient_provider = 'x'
        AND i.recipient_subject = selected_fresh_x_subject)
    AND (i.sender_user_id = selected_user OR sender.status = 'active')
    AND CASE selected_box
      WHEN 'open' THEN i.state IN ('draft', 'addressed', 'offered')
      ELSE i.state IN ('accepted', 'declined', 'expired', 'canceled')
    END
    AND (selected_cursor_at IS NULL OR
      (i.created_at, i.id) < (selected_cursor_at, selected_cursor_invitation))
  ORDER BY i.created_at DESC, i.id DESC
  LIMIT selected_limit;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'empty'::text, principal_profile, incoming,
      NULL::uuid, NULL::text,
      NULL::text, NULL::uuid, NULL::text, NULL::text, NULL::text, NULL::text,
      NULL::text, NULL::timestamptz, NULL::timestamptz, NULL::timestamptz,
      NULL::bigint, NULL::text, NULL::timestamptz;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.social_invitation_list(
  uuid, text, text, timestamptz, uuid, integer) FROM PUBLIC;

CREATE FUNCTION trimmy.social_friend_list(
  selected_user uuid,
  selected_cursor_at timestamptz,
  selected_cursor_friendship uuid,
  selected_limit integer
) RETURNS TABLE (
  outcome text, principal_social_id uuid, friendship_id uuid, revision bigint,
  connected_at timestamptz, social_id uuid, handle text, persona text,
  rank_id text, retry_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE account_status text;
DECLARE principal_profile uuid;
DECLARE allowed boolean;
DECLARE limited_until timestamptz;
BEGIN
  IF selected_user IS NULL OR selected_limit IS NULL OR selected_limit < 1
      OR selected_limit > 51
      OR (selected_cursor_at IS NULL) <> (selected_cursor_friendship IS NULL)
      OR selected_cursor_at IS NOT NULL AND NOT isfinite(selected_cursor_at)
      OR trimmy.practice_current_user() IS DISTINCT FROM selected_user THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::uuid,
      NULL::bigint, NULL::timestamptz, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::timestamptz;
    RETURN;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.social-user:' || selected_user::text, 0));
  SELECT u.status INTO account_status FROM trimmy.users u
    WHERE u.id = selected_user FOR UPDATE;
  SELECT p.public_id INTO principal_profile FROM trimmy.social_profiles p
    WHERE p.user_id = selected_user;
  IF account_status IS DISTINCT FROM 'active'
      OR NOT EXISTS (SELECT 1 FROM trimmy.practice_auth_identities a
        WHERE a.user_id = selected_user) OR principal_profile IS NULL THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::uuid, NULL::uuid,
      NULL::bigint, NULL::timestamptz, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT r.allowed, r.retry_at INTO allowed, limited_until
    FROM trimmy.social_rate_take_internal(selected_user, 'social_list_read_minute') r;
  IF NOT allowed THEN
    RETURN QUERY SELECT 'rate_limited'::text, NULL::uuid, NULL::uuid,
      NULL::bigint, NULL::timestamptz, NULL::uuid, NULL::text, NULL::text,
      NULL::text, limited_until;
    RETURN;
  END IF;
  RETURN QUERY
  SELECT 'found'::text, principal_profile, f.public_id, f.revision, f.connected_at,
    profile.public_id, product.handle, product.persona,
    coalesce(career.rank_id, 'rookie'),
    NULL::timestamptz
  FROM trimmy.social_friendships f
  JOIN LATERAL (SELECT CASE WHEN f.first_user_id = selected_user
    THEN f.second_user_id ELSE f.first_user_id END AS user_id) other ON true
  JOIN trimmy.users u ON u.id = other.user_id AND u.status = 'active'
  JOIN trimmy.social_profiles profile ON profile.user_id = other.user_id
  JOIN trimmy.product_profiles product ON product.user_id = other.user_id
  LEFT JOIN trimmy.career_profiles career ON career.user_id = other.user_id
  WHERE f.state = 'active'
    AND selected_user IN (f.first_user_id, f.second_user_id)
    AND NOT EXISTS (SELECT 1 FROM trimmy.social_blocks b
      WHERE b.state = 'active' AND (b.blocker_user_id, b.blocked_user_id) IN (
        (selected_user, other.user_id), (other.user_id, selected_user)))
    AND (selected_cursor_at IS NULL OR
      (f.connected_at, f.public_id) < (selected_cursor_at, selected_cursor_friendship))
  ORDER BY f.connected_at DESC, f.public_id DESC
  LIMIT selected_limit;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'empty'::text, principal_profile, NULL::uuid,
      NULL::bigint, NULL::timestamptz, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::timestamptz;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.social_friend_list(
  uuid, timestamptz, uuid, integer) FROM PUBLIC;

CREATE FUNCTION trimmy.social_friend_remove(
  selected_user uuid,
  selected_friendship_public uuid,
  selected_mutation uuid,
  selected_request_hash text,
  selected_base_revision bigint
) RETURNS TABLE (
  outcome text, friendship_id uuid, applied_revision bigint,
  state text, occurred_at timestamptz, retry_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE receipt trimmy.social_friendship_receipts%ROWTYPE;
DECLARE friendship trimmy.social_friendships%ROWTYPE;
DECLARE first_id uuid;
DECLARE second_id uuid;
DECLARE allowed boolean;
DECLARE limited_until timestamptz;
DECLARE observed_at timestamptz;
DECLARE receipt_conflict boolean := false;
BEGIN
  IF selected_user IS NULL OR selected_friendship_public IS NULL
      OR selected_mutation IS NULL OR selected_request_hash IS NULL
      OR selected_request_hash !~ '^[a-f0-9]{64}$'
      OR selected_base_revision IS NULL OR selected_base_revision < 1
      OR trimmy.practice_current_user() IS DISTINCT FROM selected_user THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::bigint,
      NULL::text, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT f.* INTO friendship FROM trimmy.social_friendships f
    WHERE f.public_id = selected_friendship_public;
  IF FOUND AND selected_user IN (friendship.first_user_id, friendship.second_user_id) THEN
    first_id := friendship.first_user_id;
    second_id := friendship.second_user_id;
  ELSE
    first_id := selected_user;
    second_id := selected_user;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.social-user:' || least(first_id, second_id)::text, 0));
  IF first_id <> second_id THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'trimmy.social-user:' || greatest(first_id, second_id)::text, 0));
  END IF;
  SELECT r.* INTO receipt FROM trimmy.social_friendship_receipts r
    WHERE r.actor_user_id = selected_user AND r.mutation_id = selected_mutation;
  IF FOUND THEN
    IF receipt.request_hash <> selected_request_hash
        OR receipt.friendship_public_id <> selected_friendship_public
        OR receipt.base_revision <> selected_base_revision THEN
      receipt_conflict := true;
    ELSE
      RETURN QUERY SELECT 'removed'::text, receipt.friendship_public_id,
        receipt.resulting_revision, 'removed'::text, receipt.created_at,
        NULL::timestamptz;
    END IF;
    IF NOT receipt_conflict THEN RETURN; END IF;
  END IF;
  PERFORM 1 FROM trimmy.users u WHERE u.id IN (first_id, second_id)
    ORDER BY u.id FOR UPDATE;
  IF NOT EXISTS (SELECT 1 FROM trimmy.users u
      WHERE u.id = selected_user AND u.status = 'active') OR NOT EXISTS (
    SELECT 1 FROM trimmy.practice_auth_identities a WHERE a.user_id = selected_user
  ) THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::uuid, NULL::bigint,
      NULL::text, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT r.allowed, r.retry_at INTO allowed, limited_until
    FROM trimmy.social_rate_take_internal(selected_user, 'friend_remove_10m') r;
  IF NOT allowed THEN
    RETURN QUERY SELECT 'rate_limited'::text, NULL::uuid, NULL::bigint,
      NULL::text, NULL::timestamptz, limited_until;
    RETURN;
  END IF;
  IF receipt_conflict THEN
    RETURN QUERY SELECT 'idempotency_conflict'::text, NULL::uuid, NULL::bigint,
      NULL::text, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  IF friendship.id IS NULL OR selected_user NOT IN (friendship.first_user_id, friendship.second_user_id) THEN
    RETURN QUERY SELECT 'not_found'::text, NULL::uuid, NULL::bigint,
      NULL::text, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.social-pair:' || friendship.first_user_id::text || ':' ||
      friendship.second_user_id::text, 0));
  SELECT f.* INTO friendship FROM trimmy.social_friendships f
    WHERE f.id = friendship.id FOR UPDATE;
  IF friendship.state <> 'active' OR friendship.revision <> selected_base_revision THEN
    RETURN QUERY SELECT 'revision_conflict'::text, friendship.public_id,
      friendship.revision, friendship.state, friendship.updated_at,
      NULL::timestamptz;
    RETURN;
  END IF;
  IF friendship.revision >= 9007199254740991 THEN
    RETURN QUERY SELECT 'revision_exhausted'::text, NULL::uuid, NULL::bigint,
      NULL::text, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  observed_at := greatest(date_trunc('milliseconds', clock_timestamp()),
    friendship.updated_at + interval '1 millisecond');
  UPDATE trimmy.social_friendships f SET revision = f.revision + 1,
    state = 'removed', ended_at = observed_at, updated_at = observed_at
    WHERE f.id = friendship.id RETURNING f.* INTO friendship;
  INSERT INTO trimmy.social_friendship_events(
    friendship_id, revision, event_kind, actor_user_id, source_invitation_id,
    resulting_state, created_at)
  VALUES (friendship.id, friendship.revision, 'removed', selected_user,
    NULL, 'removed', friendship.updated_at);
  INSERT INTO trimmy.social_friendship_receipts(
    actor_user_id, mutation_id, request_hash, friendship_public_id,
    base_revision, resulting_revision, created_at)
  VALUES (selected_user, selected_mutation, selected_request_hash,
    friendship.public_id, selected_base_revision, friendship.revision,
    friendship.updated_at);
  RETURN QUERY SELECT 'removed'::text, friendship.public_id,
    friendship.revision, friendship.state, friendship.updated_at,
    NULL::timestamptz;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.social_friend_remove(
  uuid, uuid, uuid, text, bigint) FROM PUBLIC;

CREATE FUNCTION trimmy.social_block_put(
  selected_user uuid,
  selected_target_profile uuid,
  selected_mutation uuid,
  selected_request_hash text,
  selected_base_revision bigint,
  selected_state text
) RETURNS TABLE (
  outcome text, target_social_id uuid, applied_revision bigint,
  revision bigint, blocked boolean, updated_at timestamptz, retry_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE target_user uuid;
DECLARE first_id uuid;
DECLARE second_id uuid;
DECLARE receipt trimmy.social_block_receipts%ROWTYPE;
DECLARE block_row trimmy.social_blocks%ROWTYPE;
DECLARE friendship trimmy.social_friendships%ROWTYPE;
DECLARE allowed boolean;
DECLARE limited_until timestamptz;
DECLARE allowed_day boolean;
DECLARE limited_day timestamptz;
DECLARE observed_at timestamptz;
DECLARE receipt_conflict boolean := false;
DECLARE target_active boolean := false;
DECLARE block_exists boolean := false;
BEGIN
  IF selected_user IS NULL OR selected_target_profile IS NULL
      OR selected_mutation IS NULL OR selected_request_hash IS NULL
      OR selected_request_hash !~ '^[a-f0-9]{64}$'
      OR selected_base_revision IS NULL OR selected_base_revision < 0
      OR selected_state NOT IN ('active', 'inactive')
      OR trimmy.practice_current_user() IS DISTINCT FROM selected_user THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::bigint,
      NULL::bigint, NULL::boolean, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT p.user_id INTO target_user FROM trimmy.social_profiles p
    WHERE p.public_id = selected_target_profile;
  first_id := CASE WHEN target_user IS NULL
    THEN selected_user ELSE least(selected_user, target_user) END;
  second_id := CASE WHEN target_user IS NULL
    THEN NULL ELSE greatest(selected_user, target_user) END;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.social-user:' || first_id::text, 0));
  IF second_id IS NOT NULL AND second_id <> first_id THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'trimmy.social-user:' || second_id::text, 0));
  END IF;
  SELECT r.* INTO receipt FROM trimmy.social_block_receipts r
    WHERE r.blocker_user_id = selected_user AND r.mutation_id = selected_mutation;
  IF FOUND THEN
    IF receipt.request_hash <> selected_request_hash
        OR receipt.target_profile_id <> selected_target_profile
        OR receipt.base_revision <> selected_base_revision
        OR receipt.requested_state <> selected_state THEN
      receipt_conflict := true;
    ELSE
      SELECT b.* INTO block_row FROM trimmy.social_blocks b
        WHERE b.blocker_user_id = selected_user AND b.blocked_user_id = target_user;
      RETURN QUERY SELECT 'saved'::text, selected_target_profile,
        receipt.resulting_revision, block_row.revision,
        block_row.state = 'active', block_row.updated_at, NULL::timestamptz;
    END IF;
    IF NOT receipt_conflict THEN RETURN; END IF;
  END IF;
  PERFORM 1 FROM trimmy.users u WHERE u.id = first_id OR u.id = second_id
    ORDER BY u.id FOR UPDATE;
  IF NOT EXISTS (SELECT 1 FROM trimmy.users u
      WHERE u.id = selected_user AND u.status = 'active')
      OR NOT EXISTS (SELECT 1 FROM trimmy.practice_auth_identities a
        WHERE a.user_id = selected_user) THEN
    RETURN QUERY SELECT 'not_found'::text, NULL::uuid, NULL::bigint,
      NULL::bigint, NULL::boolean, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT r.allowed, r.retry_at INTO allowed, limited_until
    FROM trimmy.social_rate_take_internal(selected_user, 'block_change_10m') r;
  SELECT r.allowed, r.retry_at INTO allowed_day, limited_day
    FROM trimmy.social_rate_take_internal(selected_user, 'block_change_day') r;
  IF NOT allowed OR NOT allowed_day THEN
    RETURN QUERY SELECT 'rate_limited'::text, NULL::uuid, NULL::bigint,
      NULL::bigint, NULL::boolean, NULL::timestamptz,
      greatest(limited_until, limited_day);
    RETURN;
  END IF;
  IF receipt_conflict THEN
    RETURN QUERY SELECT 'idempotency_conflict'::text, NULL::uuid,
      NULL::bigint, NULL::bigint, NULL::boolean, NULL::timestamptz,
      NULL::timestamptz;
    RETURN;
  END IF;
  IF target_user IS NULL THEN
    RETURN QUERY SELECT 'not_found'::text, NULL::uuid, NULL::bigint,
      NULL::bigint, NULL::boolean, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  IF target_user = selected_user THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::bigint,
      NULL::bigint, NULL::boolean, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT u.status = 'active' INTO target_active FROM trimmy.users u
    WHERE u.id = target_user;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.social-pair:' || first_id::text || ':' || second_id::text, 0));
  SELECT b.* INTO block_row FROM trimmy.social_blocks b
    WHERE b.blocker_user_id = selected_user AND b.blocked_user_id = target_user
    FOR UPDATE;
  block_exists := FOUND;
  -- A closed target can still be unblocked. It cannot receive a new block or
  -- acquire a block snapshot that did not already exist.
  IF NOT target_active AND (selected_state <> 'inactive' OR NOT block_exists) THEN
    RETURN QUERY SELECT 'not_found'::text, NULL::uuid, NULL::bigint,
      NULL::bigint, NULL::boolean, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  IF NOT block_exists THEN
    IF selected_base_revision <> 0 OR selected_state <> 'active' THEN
      RETURN QUERY SELECT 'revision_conflict'::text, selected_target_profile,
        NULL::bigint, 0::bigint, false, NULL::timestamptz, NULL::timestamptz;
      RETURN;
    END IF;
    observed_at := date_trunc('milliseconds', clock_timestamp());
    INSERT INTO trimmy.social_blocks(
      blocker_user_id, blocked_user_id, revision, state, created_at, updated_at)
    VALUES (selected_user, target_user, 1, 'active', observed_at, observed_at)
    RETURNING * INTO block_row;
  ELSE
    IF block_row.revision <> selected_base_revision
        OR block_row.state = selected_state THEN
      RETURN QUERY SELECT 'revision_conflict'::text, selected_target_profile,
        NULL::bigint, block_row.revision, block_row.state = 'active',
        block_row.updated_at, NULL::timestamptz;
      RETURN;
    END IF;
    IF block_row.revision >= 9007199254740991 THEN
      RETURN QUERY SELECT 'revision_exhausted'::text, NULL::uuid,
        NULL::bigint, NULL::bigint, NULL::boolean, NULL::timestamptz,
        NULL::timestamptz;
      RETURN;
    END IF;
    observed_at := greatest(date_trunc('milliseconds', clock_timestamp()),
      block_row.updated_at + interval '1 millisecond');
    UPDATE trimmy.social_blocks b SET revision = b.revision + 1,
      state = selected_state, updated_at = observed_at
      WHERE b.blocker_user_id = selected_user AND b.blocked_user_id = target_user
      RETURNING b.* INTO block_row;
  END IF;
  IF selected_state = 'active' THEN
    SELECT f.* INTO friendship FROM trimmy.social_friendships f
      WHERE f.first_user_id = first_id AND f.second_user_id = second_id FOR UPDATE;
    IF FOUND AND friendship.state = 'active' THEN
      IF friendship.revision >= 9007199254740991 THEN
        RAISE EXCEPTION 'Friendship revision exhausted during block'
          USING ERRCODE = '23514', CONSTRAINT = 'social_block_friendship_revision';
      END IF;
      observed_at := greatest(block_row.updated_at,
        friendship.updated_at + interval '1 millisecond');
      UPDATE trimmy.social_friendships f SET revision = f.revision + 1,
        state = 'removed', ended_at = observed_at, updated_at = observed_at
        WHERE f.id = friendship.id RETURNING f.* INTO friendship;
      INSERT INTO trimmy.social_friendship_events(
        friendship_id, revision, event_kind, actor_user_id,
        source_invitation_id, resulting_state, created_at)
      VALUES (friendship.id, friendship.revision, 'blocked', selected_user,
        NULL, 'removed', friendship.updated_at);
    END IF;
    UPDATE trimmy.invitations i SET state = 'canceled', version = i.version + 1
      WHERE i.state IN ('draft', 'addressed', 'offered')
        AND ((i.sender_user_id = selected_user AND (
            i.recipient_user_id = target_user OR EXISTS (
              SELECT 1 FROM trimmy.provider_identities p
              WHERE p.user_id = target_user AND p.provider = i.recipient_provider
                AND p.subject = i.recipient_subject)))
          OR (i.sender_user_id = target_user AND (
            i.recipient_user_id = selected_user OR EXISTS (
              SELECT 1 FROM trimmy.provider_identities p
              WHERE p.user_id = selected_user AND p.provider = i.recipient_provider
                AND p.subject = i.recipient_subject))));
  END IF;
  INSERT INTO trimmy.social_block_receipts(
    blocker_user_id, mutation_id, request_hash, target_profile_id,
    base_revision, requested_state, resulting_revision, created_at)
  VALUES (selected_user, selected_mutation, selected_request_hash,
    selected_target_profile, selected_base_revision, selected_state,
    block_row.revision, block_row.updated_at);
  RETURN QUERY SELECT 'saved'::text, selected_target_profile,
    block_row.revision, block_row.revision, block_row.state = 'active',
    block_row.updated_at, NULL::timestamptz;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.social_block_put(
  uuid, uuid, uuid, text, bigint, text) FROM PUBLIC;

CREATE FUNCTION trimmy.social_block_get(
  selected_user uuid,
  selected_target_profile uuid
) RETURNS TABLE (
  outcome text, target_social_id uuid, revision bigint,
  blocked boolean, updated_at timestamptz, retry_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE target_user uuid;
DECLARE target_status text;
DECLARE first_id uuid;
DECLARE second_id uuid;
DECLARE block_row trimmy.social_blocks%ROWTYPE;
DECLARE allowed boolean;
DECLARE limited_until timestamptz;
BEGIN
  IF selected_user IS NULL OR selected_target_profile IS NULL
      OR trimmy.practice_current_user() IS DISTINCT FROM selected_user THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::bigint,
      NULL::boolean, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;

  -- Resolve only enough to acquire the same canonical account locks as a
  -- mutation. Missing and self targets are classified after the read budget.
  SELECT p.user_id INTO target_user FROM trimmy.social_profiles p
    WHERE p.public_id = selected_target_profile;
  first_id := CASE WHEN target_user IS NULL
    THEN selected_user ELSE least(selected_user, target_user) END;
  second_id := CASE WHEN target_user IS NULL
    THEN NULL ELSE greatest(selected_user, target_user) END;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.social-user:' || first_id::text, 0));
  IF second_id IS NOT NULL AND second_id <> first_id THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'trimmy.social-user:' || second_id::text, 0));
  END IF;
  PERFORM 1 FROM trimmy.users u WHERE u.id = first_id OR u.id = second_id
    ORDER BY u.id FOR UPDATE;
  IF NOT EXISTS (SELECT 1 FROM trimmy.users u
      WHERE u.id = selected_user AND u.status = 'active')
      OR NOT EXISTS (SELECT 1 FROM trimmy.practice_auth_identities a
        WHERE a.user_id = selected_user)
      OR NOT EXISTS (SELECT 1 FROM trimmy.social_profiles p
        WHERE p.user_id = selected_user) THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::uuid, NULL::bigint,
      NULL::boolean, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT r.allowed, r.retry_at INTO allowed, limited_until
    FROM trimmy.social_rate_take_internal(selected_user, 'social_list_read_minute') r;
  IF NOT allowed THEN
    RETURN QUERY SELECT 'rate_limited'::text, NULL::uuid, NULL::bigint,
      NULL::boolean, NULL::timestamptz, limited_until;
    RETURN;
  END IF;
  IF target_user IS NULL THEN
    RETURN QUERY SELECT 'not_found'::text, NULL::uuid, NULL::bigint,
      NULL::boolean, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  IF target_user = selected_user THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::bigint,
      NULL::boolean, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT u.status INTO target_status FROM trimmy.users u WHERE u.id = target_user;
  SELECT b.* INTO block_row FROM trimmy.social_blocks b
    WHERE b.blocker_user_id = selected_user AND b.blocked_user_id = target_user;
  IF FOUND THEN
    RETURN QUERY SELECT 'found'::text, selected_target_profile,
      block_row.revision, block_row.state = 'active', block_row.updated_at,
      NULL::timestamptz;
    RETURN;
  END IF;
  IF target_status IS DISTINCT FROM 'active' THEN
    RETURN QUERY SELECT 'not_found'::text, NULL::uuid, NULL::bigint,
      NULL::boolean, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  RETURN QUERY SELECT 'found'::text, selected_target_profile, 0::bigint,
    false, NULL::timestamptz, NULL::timestamptz;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.social_block_get(uuid, uuid) FROM PUBLIC;

CREATE FUNCTION trimmy.social_block_list(
  selected_user uuid,
  selected_cursor_at timestamptz,
  selected_cursor_profile uuid,
  selected_limit integer
) RETURNS TABLE (
  outcome text, principal_social_id uuid, social_id uuid, handle text,
  revision bigint, updated_at timestamptz, retry_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE account_status text;
DECLARE principal_profile uuid;
DECLARE allowed boolean;
DECLARE limited_until timestamptz;
BEGIN
  IF selected_user IS NULL OR selected_limit IS NULL OR selected_limit < 1
      OR selected_limit > 51
      OR (selected_cursor_at IS NULL) <> (selected_cursor_profile IS NULL)
      OR selected_cursor_at IS NOT NULL AND NOT isfinite(selected_cursor_at)
      OR trimmy.practice_current_user() IS DISTINCT FROM selected_user THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::uuid, NULL::text,
      NULL::bigint, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.social-user:' || selected_user::text, 0));
  SELECT u.status INTO account_status FROM trimmy.users u
    WHERE u.id = selected_user FOR UPDATE;
  SELECT p.public_id INTO principal_profile FROM trimmy.social_profiles p
    WHERE p.user_id = selected_user;
  IF account_status IS DISTINCT FROM 'active'
      OR NOT EXISTS (SELECT 1 FROM trimmy.practice_auth_identities a
        WHERE a.user_id = selected_user) OR principal_profile IS NULL THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::uuid, NULL::uuid,
      NULL::text, NULL::bigint, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT r.allowed, r.retry_at INTO allowed, limited_until
    FROM trimmy.social_rate_take_internal(selected_user, 'social_list_read_minute') r;
  IF NOT allowed THEN
    RETURN QUERY SELECT 'rate_limited'::text, NULL::uuid, NULL::uuid,
      NULL::text, NULL::bigint, NULL::timestamptz, limited_until;
    RETURN;
  END IF;
  RETURN QUERY
  SELECT 'found'::text, principal_profile, profile.public_id,
    CASE WHEN target.status = 'active' THEN product.handle ELSE NULL END,
    b.revision, b.updated_at, NULL::timestamptz
  FROM trimmy.social_blocks b
  JOIN trimmy.social_profiles profile ON profile.user_id = b.blocked_user_id
  JOIN trimmy.users target ON target.id = b.blocked_user_id
  LEFT JOIN trimmy.product_profiles product
    ON product.user_id = b.blocked_user_id AND target.status = 'active'
  WHERE b.blocker_user_id = selected_user AND b.state = 'active'
    AND (selected_cursor_at IS NULL OR
      (b.updated_at, profile.public_id) < (selected_cursor_at, selected_cursor_profile))
  ORDER BY b.updated_at DESC, profile.public_id DESC
  LIMIT selected_limit;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'empty'::text, principal_profile, NULL::uuid,
      NULL::text, NULL::bigint, NULL::timestamptz, NULL::timestamptz;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.social_block_list(
  uuid, timestamptz, uuid, integer) FROM PUBLIC;

CREATE FUNCTION trimmy.social_reason_report_create(
  selected_user uuid,
  selected_mutation uuid,
  selected_request_hash text,
  selected_reason uuid,
  selected_category text
) RETURNS TABLE (
  outcome text, report_id uuid, reason_id uuid, category text,
  received_at timestamptz, retry_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE existing trimmy.social_reason_reports%ROWTYPE;
DECLARE reason_row trimmy.career_trade_reasons%ROWTYPE;
DECLARE author_id uuid;
DECLARE first_id uuid;
DECLARE second_id uuid;
DECLARE allowed boolean;
DECLARE limited_until timestamptz;
DECLARE report_id_value uuid;
DECLARE observed_at timestamptz := date_trunc('milliseconds', clock_timestamp());
DECLARE visible_to_reporter boolean;
DECLARE receipt_conflict boolean := false;
BEGIN
  IF selected_user IS NULL OR selected_mutation IS NULL
      OR selected_request_hash IS NULL OR selected_request_hash !~ '^[a-f0-9]{64}$'
      OR selected_reason IS NULL
      OR selected_category NOT IN ('spam', 'harassment', 'impersonation', 'unsafe', 'other')
      OR trimmy.practice_current_user() IS DISTINCT FROM selected_user THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::uuid, NULL::text,
      NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;

  -- Resolve without locking, then take every account lock in canonical order.
  -- The reason is immutable; all mutable visibility inputs are re-read below
  -- after their owning locks have been acquired.
  SELECT r.* INTO reason_row FROM trimmy.career_trade_reasons r
    WHERE r.public_id = selected_reason;
  author_id := CASE WHEN FOUND THEN reason_row.user_id ELSE selected_user END;
  first_id := least(selected_user, author_id);
  second_id := greatest(selected_user, author_id);
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.social-user:' || first_id::text, 0));
  IF second_id <> first_id THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'trimmy.social-user:' || second_id::text, 0));
  END IF;
  PERFORM 1 FROM trimmy.users u WHERE u.id IN (first_id, second_id)
    ORDER BY u.id FOR UPDATE;
  IF NOT EXISTS (SELECT 1 FROM trimmy.users u
      WHERE u.id = selected_user AND u.status = 'active') OR NOT EXISTS (
    SELECT 1 FROM trimmy.practice_auth_identities a WHERE a.user_id = selected_user
  ) THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::uuid, NULL::uuid,
      NULL::text, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;

  -- Recheck the immutable receipt under the reporter lock. Exact replay remains
  -- available without consuming another budget unit; rebinding consumes one.
  SELECT r.* INTO existing FROM trimmy.social_reason_reports r
    WHERE r.reporter_user_id = selected_user AND r.mutation_id = selected_mutation;
  IF FOUND THEN
    IF existing.request_hash = selected_request_hash
        AND existing.reason_public_id = selected_reason
        AND existing.category = selected_category THEN
      RETURN QUERY SELECT 'found'::text, existing.public_id,
        existing.reason_public_id, existing.category, existing.created_at,
        NULL::timestamptz;
      RETURN;
    END IF;
    receipt_conflict := true;
  END IF;

  SELECT r.allowed, r.retry_at INTO allowed, limited_until
    FROM trimmy.social_rate_take_internal(selected_user, 'reason_report_day') r;
  IF NOT allowed THEN
    RETURN QUERY SELECT 'rate_limited'::text, NULL::uuid, NULL::uuid,
      NULL::text, NULL::timestamptz, limited_until;
    RETURN;
  END IF;
  IF receipt_conflict THEN
    RETURN QUERY SELECT 'idempotency_conflict'::text, NULL::uuid, NULL::uuid,
      NULL::text, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT r.* INTO existing FROM trimmy.social_reason_reports r
    WHERE r.reporter_user_id = selected_user AND r.reason_public_id = selected_reason;
  IF FOUND THEN
    RETURN QUERY SELECT 'found'::text, existing.public_id,
      existing.reason_public_id, existing.category, existing.created_at,
      NULL::timestamptz;
    RETURN;
  END IF;
  IF reason_row.public_id IS NULL THEN
    RETURN QUERY SELECT 'not_found'::text, NULL::uuid, NULL::uuid,
      NULL::text, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  IF reason_row.user_id = selected_user THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::uuid,
      NULL::text, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM trimmy.users u
      WHERE u.id = reason_row.user_id AND u.status = 'active') THEN
    RETURN QUERY SELECT 'not_found'::text, NULL::uuid, NULL::uuid,
      NULL::text, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.social-pair:' || first_id::text || ':' || second_id::text, 0));
  PERFORM 1 FROM trimmy.social_blocks b
    WHERE (b.blocker_user_id, b.blocked_user_id) IN (
      (first_id, second_id), (second_id, first_id))
    ORDER BY b.blocker_user_id, b.blocked_user_id FOR UPDATE;
  PERFORM 1 FROM trimmy.social_friendships f
    WHERE f.first_user_id = first_id AND f.second_user_id = second_id FOR UPDATE;
  PERFORM 1 FROM trimmy.career_reason_privacy p
    WHERE p.user_id = reason_row.user_id FOR UPDATE;
  PERFORM 1 FROM trimmy.paper_accounts a
    WHERE a.user_id = reason_row.user_id FOR UPDATE;
  PERFORM 1 FROM trimmy.paper_orders o
    WHERE o.id = reason_row.order_id AND o.user_id = reason_row.user_id FOR UPDATE;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.social-reason:' || selected_reason::text, 0));
  PERFORM 1 FROM trimmy.social_reason_moderation m
    WHERE m.reason_public_id = selected_reason FOR UPDATE;

  SELECT EXISTS (
    SELECT 1
    FROM trimmy.users author
    JOIN trimmy.career_reason_privacy privacy ON privacy.user_id = author.id
    JOIN trimmy.paper_orders orders
      ON orders.id = reason_row.order_id AND orders.user_id = author.id
    JOIN trimmy.paper_accounts account ON account.user_id = author.id
    WHERE author.id = reason_row.user_id AND author.status = 'active'
      AND orders.account_revision > account.last_reset_revision
      AND NOT EXISTS (SELECT 1 FROM trimmy.social_reason_moderation m
        WHERE m.reason_public_id = selected_reason AND m.state = 'hidden')
      AND NOT EXISTS (SELECT 1 FROM trimmy.social_blocks b
        WHERE b.state = 'active' AND (b.blocker_user_id, b.blocked_user_id) IN (
          (selected_user, reason_row.user_id), (reason_row.user_id, selected_user)))
      AND (privacy.visibility = 'everyone' OR privacy.visibility = 'friends'
        AND EXISTS (SELECT 1 FROM trimmy.social_profiles viewer_profile
          WHERE viewer_profile.user_id = selected_user)
        AND EXISTS (SELECT 1 FROM trimmy.social_profiles author_profile
          WHERE author_profile.user_id = reason_row.user_id)
        AND EXISTS (SELECT 1 FROM trimmy.social_friendships f
          WHERE f.state = 'active'
            AND f.first_user_id = least(selected_user, reason_row.user_id)
            AND f.second_user_id = greatest(selected_user, reason_row.user_id)))
  ) INTO visible_to_reporter;
  IF NOT visible_to_reporter THEN
    RETURN QUERY SELECT 'not_found'::text, NULL::uuid, NULL::uuid,
      NULL::text, NULL::timestamptz, NULL::timestamptz;
    RETURN;
  END IF;
  INSERT INTO trimmy.social_reason_reports(
    reporter_user_id, mutation_id, request_hash, reason_public_id,
    category, created_at)
  VALUES (selected_user, selected_mutation, selected_request_hash,
    selected_reason, selected_category, observed_at)
  RETURNING public_id INTO report_id_value;
  RETURN QUERY SELECT 'reported'::text, report_id_value, selected_reason,
    selected_category, observed_at, NULL::timestamptz;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.social_reason_report_create(
  uuid, uuid, text, uuid, text) FROM PUBLIC;

CREATE FUNCTION trimmy.social_reason_moderation_put(
  selected_reason uuid,
  selected_expected_revision bigint,
  selected_state text,
  selected_reason_code text,
  selected_operator_reference text
) RETURNS TABLE (
  outcome text, reason_id uuid, revision bigint, state text,
  decision_code text, operator_reference text, updated_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE current_row trimmy.social_reason_moderation%ROWTYPE;
DECLARE observed_at timestamptz := date_trunc('milliseconds', clock_timestamp());
BEGIN
  IF selected_reason IS NULL OR selected_expected_revision IS NULL
      OR selected_expected_revision < 0
      OR selected_state NOT IN ('visible', 'hidden')
      OR selected_operator_reference IS NULL
      OR length(selected_operator_reference) NOT BETWEEN 1 AND 100
      OR selected_operator_reference !~ '^[\x20-\x7e]+$'
      OR selected_state = 'hidden' AND selected_reason_code NOT IN (
        'spam', 'harassment', 'impersonation', 'unsafe', 'legal', 'other_reviewed')
      OR selected_state = 'visible' AND selected_reason_code NOT IN (
        'appeal_granted', 'decision_corrected') THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::bigint, NULL::text,
      NULL::text, NULL::text, NULL::timestamptz;
    RETURN;
  END IF;
  -- A first moderation snapshot has no row for FOR UPDATE to lock. Share the
  -- reason-scoped advisory lock with report creation so a hide/restore and a
  -- report authorization have one deterministic winner.
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.social-reason:' || selected_reason::text, 0));
  IF NOT EXISTS (SELECT 1 FROM trimmy.career_trade_reasons r
      WHERE r.public_id = selected_reason) THEN
    RETURN QUERY SELECT 'not_found'::text, NULL::uuid, NULL::bigint, NULL::text,
      NULL::text, NULL::text, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT m.* INTO current_row FROM trimmy.social_reason_moderation m
    WHERE m.reason_public_id = selected_reason FOR UPDATE;
  IF NOT FOUND THEN
    IF selected_expected_revision <> 0 OR selected_state <> 'hidden' THEN
      RETURN QUERY SELECT 'revision_conflict'::text, selected_reason,
        0::bigint, 'visible'::text, NULL::text, NULL::text, NULL::timestamptz;
      RETURN;
    END IF;
    INSERT INTO trimmy.social_reason_moderation(
      reason_public_id, revision, state, decision_code, operator_reference,
      created_at, updated_at)
    VALUES (selected_reason, 1, selected_state, selected_reason_code,
      selected_operator_reference, observed_at, observed_at)
    RETURNING * INTO current_row;
  ELSE
    IF current_row.revision <> selected_expected_revision
        OR current_row.state = selected_state THEN
      RETURN QUERY SELECT 'revision_conflict'::text, current_row.reason_public_id,
        current_row.revision, current_row.state, current_row.decision_code,
        current_row.operator_reference, current_row.updated_at;
      RETURN;
    END IF;
    IF current_row.revision >= 9007199254740991 THEN
      RETURN QUERY SELECT 'revision_exhausted'::text, NULL::uuid, NULL::bigint,
        NULL::text, NULL::text, NULL::text, NULL::timestamptz;
      RETURN;
    END IF;
    observed_at := greatest(observed_at, current_row.updated_at + interval '1 millisecond');
    UPDATE trimmy.social_reason_moderation m SET
      revision = m.revision + 1, state = selected_state,
      decision_code = selected_reason_code,
      operator_reference = selected_operator_reference,
      updated_at = observed_at
    WHERE m.reason_public_id = selected_reason RETURNING m.* INTO current_row;
  END IF;
  INSERT INTO trimmy.social_reason_moderation_events(
    reason_public_id, revision, resulting_state, decision_code,
    operator_reference, created_at)
  VALUES (current_row.reason_public_id, current_row.revision, current_row.state,
    current_row.decision_code, current_row.operator_reference,
    current_row.updated_at);
  RETURN QUERY SELECT 'saved'::text, current_row.reason_public_id,
    current_row.revision, current_row.state, current_row.decision_code,
    current_row.operator_reference, current_row.updated_at;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.social_reason_moderation_put(
  uuid, bigint, text, text, text) FROM PUBLIC;

-- The argument signature stays stable for a rolling API deployment. Dropping
-- and recreating inside this migration transaction permits the additive result
-- columns while callers selecting the historical named columns remain valid.
DROP FUNCTION trimmy.career_trade_reason_list(
  uuid, text, text, text, timestamptz, uuid, integer);
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
  principal_social_id uuid,
  reason_id uuid,
  order_id uuid,
  author_social_id uuid,
  author_handle text,
  author_persona text,
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
DECLARE principal_social uuid;
BEGIN
  IF selected_user IS NULL OR selected_scope IS NULL
      OR selected_scope NOT IN ('self', 'everyone', 'friends')
      OR selected_limit IS NULL OR selected_limit < 1 OR selected_limit > 50
      OR (selected_asset IS NULL) <> (selected_mint IS NULL)
      OR (selected_scope IN ('everyone', 'friends') AND selected_asset IS NULL)
      OR (selected_cursor_at IS NULL) <> (selected_cursor_reason IS NULL)
      OR selected_cursor_at IS NOT NULL AND NOT isfinite(selected_cursor_at)
      OR selected_asset IS NOT NULL AND (
        length(selected_asset) > 100
        OR selected_asset !~ '^[a-z0-9]+(-[a-z0-9]+)*$')
      OR selected_mint IS NOT NULL AND (
        length(selected_mint) NOT BETWEEN 32 AND 44
        OR selected_mint !~ '^[1-9A-HJ-NP-Za-km-z]+$')
      OR trimmy.career_reason_runtime_user() IS DISTINCT FROM selected_user THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::uuid, NULL::uuid, NULL::uuid,
      NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::timestamptz, NULL::boolean;
    RETURN;
  END IF;
  SELECT u.status INTO account_status FROM trimmy.users u WHERE u.id = selected_user;
  IF account_status IS DISTINCT FROM 'active' THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::uuid, NULL::uuid, NULL::uuid, NULL::uuid,
      NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::timestamptz, NULL::boolean;
    RETURN;
  END IF;
  IF selected_scope = 'friends' THEN
    SELECT viewer_social.public_id INTO principal_social
      FROM trimmy.social_profiles viewer_social
      WHERE viewer_social.user_id = selected_user;
    IF NOT EXISTS (SELECT 1 FROM trimmy.practice_auth_identities a
        WHERE a.user_id = selected_user) OR principal_social IS NULL THEN
      RETURN QUERY SELECT 'forbidden'::text, NULL::uuid, NULL::uuid,
        NULL::uuid, NULL::uuid, NULL::text, NULL::text, NULL::text, NULL::text,
        NULL::text, NULL::text, NULL::text, NULL::text, NULL::timestamptz,
        NULL::boolean;
      RETURN;
    END IF;
  END IF;

  RETURN QUERY
  SELECT 'found'::text,
    CASE WHEN selected_scope = 'friends' THEN principal_social ELSE NULL::uuid END,
    r.public_id,
    CASE WHEN selected_scope = 'friends' THEN NULL::uuid ELSE r.order_id END,
    CASE WHEN selected_scope = 'friends' THEN author_social.public_id ELSE NULL::uuid END,
    profile.handle,
    CASE WHEN selected_scope = 'friends' THEN profile.persona ELSE NULL::text END,
    career.rank_id, r.asset_id, r.variant_mint::text, orders.symbol, r.note,
    CASE WHEN selected_scope = 'friends' THEN NULL::text
      WHEN orders.account_revision > account.last_reset_revision
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
  LEFT JOIN trimmy.social_profiles author_social ON author_social.user_id = r.user_id
  WHERE CASE selected_scope
      WHEN 'self' THEN r.user_id = selected_user
      WHEN 'everyone' THEN privacy.visibility = 'everyone'
      ELSE privacy.visibility IN ('friends', 'everyone') AND EXISTS (
        SELECT 1 FROM trimmy.social_friendships f
        WHERE f.state = 'active'
          AND f.first_user_id = least(selected_user, r.user_id)
          AND f.second_user_id = greatest(selected_user, r.user_id))
        AND author_social.user_id IS NOT NULL
    END
    AND (selected_scope = 'self'
      OR orders.account_revision > account.last_reset_revision)
    AND (selected_asset IS NULL OR
      (r.asset_id = selected_asset AND r.variant_mint::text = selected_mint))
    AND (selected_cursor_at IS NULL OR
      (r.saved_at, r.public_id) < (selected_cursor_at, selected_cursor_reason))
    AND (selected_scope = 'self' OR NOT EXISTS (
      SELECT 1 FROM trimmy.social_reason_moderation m
      WHERE m.reason_public_id = r.public_id AND m.state = 'hidden'))
    AND (selected_scope = 'self' OR NOT EXISTS (
      SELECT 1 FROM trimmy.social_reason_reports report
      WHERE report.reporter_user_id = selected_user
        AND report.reason_public_id = r.public_id))
    AND (selected_scope = 'self' OR NOT EXISTS (
      SELECT 1 FROM trimmy.social_blocks b
      WHERE b.state = 'active' AND (b.blocker_user_id, b.blocked_user_id) IN (
        (selected_user, r.user_id), (r.user_id, selected_user))))
  ORDER BY r.saved_at DESC, r.public_id DESC
  LIMIT selected_limit + 1;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'empty'::text,
      CASE WHEN selected_scope = 'friends' THEN principal_social ELSE NULL::uuid END,
      NULL::uuid, NULL::uuid, NULL::uuid,
      NULL::text, NULL::text, NULL::text, NULL::text, NULL::text, NULL::text,
      NULL::text, NULL::text, NULL::timestamptz, NULL::boolean;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_trade_reason_list(
  uuid, text, text, text, timestamptz, uuid, integer) FROM PUBLIC;

CREATE FUNCTION trimmy.social_rate_windows_prune(
  selected_before timestamptz,
  selected_limit integer
) RETURNS TABLE (deleted_count integer, has_more boolean)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE affected integer;
BEGIN
  IF selected_before IS NULL OR NOT isfinite(selected_before)
      OR selected_before > clock_timestamp() - interval '1 day'
      OR selected_limit IS NULL OR selected_limit < 1 OR selected_limit > 10000 THEN
    RAISE EXCEPTION 'Social rate-window retention arguments are invalid'
      USING ERRCODE = '22023';
  END IF;
  WITH victims AS (
    SELECT user_id, action, window_started_at FROM trimmy.social_rate_windows
    WHERE window_ends_at < selected_before
    ORDER BY window_ends_at, user_id, action
    LIMIT selected_limit
    FOR UPDATE SKIP LOCKED
  )
  DELETE FROM trimmy.social_rate_windows w USING victims v
    WHERE (w.user_id, w.action, w.window_started_at)
      = (v.user_id, v.action, v.window_started_at);
  GET DIAGNOSTICS affected = ROW_COUNT;
  RETURN QUERY SELECT affected, EXISTS (
    SELECT 1 FROM trimmy.social_rate_windows WHERE window_ends_at < selected_before);
END;
$$;
REVOKE ALL ON FUNCTION trimmy.social_rate_windows_prune(timestamptz, integer) FROM PUBLIC;

CREATE FUNCTION trimmy.social_account_close_cleanup_internal(
  selected_user uuid,
  selected_fresh_x_subject text
) RETURNS TABLE (canceled_invitations integer, removed_friendships integer)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE selected_subject text;
DECLARE canceled_count integer := 0;
DECLARE removed_count integer := 0;
DECLARE friendship trimmy.social_friendships%ROWTYPE;
DECLARE observed_at timestamptz;
BEGIN
  IF selected_user IS NULL OR selected_fresh_x_subject IS NOT NULL
      AND NOT trimmy.social_x_subject_valid(selected_fresh_x_subject) THEN
    RAISE EXCEPTION 'Social account cleanup arguments are invalid'
      USING ERRCODE = '22023';
  END IF;
  FOR selected_subject IN
    SELECT subject FROM (
      SELECT p.subject FROM trimmy.provider_identities p
        WHERE p.user_id = selected_user AND p.provider = 'x'
      UNION SELECT selected_fresh_x_subject WHERE selected_fresh_x_subject IS NOT NULL
    ) subjects ORDER BY subject
  LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'trimmy.social-subject:x:' || selected_subject, 0));
  END LOOP;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.social-user:' || selected_user::text, 0));
  PERFORM 1 FROM trimmy.users u WHERE u.id = selected_user FOR UPDATE;

  UPDATE trimmy.invitations i SET state = 'canceled', version = i.version + 1
    WHERE i.state IN ('draft', 'addressed', 'offered')
      AND (i.sender_user_id = selected_user OR i.recipient_user_id = selected_user
        OR i.recipient_provider = 'x' AND i.recipient_subject IN (
          SELECT p.subject FROM trimmy.provider_identities p
            WHERE p.user_id = selected_user AND p.provider = 'x'
          UNION SELECT selected_fresh_x_subject
            WHERE selected_fresh_x_subject IS NOT NULL
              AND NOT EXISTS (
                SELECT 1 FROM trimmy.provider_identities p
                WHERE p.provider = 'x'
                  AND p.subject = selected_fresh_x_subject
                  AND p.user_id <> selected_user)));
  GET DIAGNOSTICS canceled_count = ROW_COUNT;

  FOR friendship IN
    SELECT f.* FROM trimmy.social_friendships f
    WHERE f.state = 'active'
      AND selected_user IN (f.first_user_id, f.second_user_id)
    ORDER BY f.id FOR UPDATE
  LOOP
    IF friendship.revision >= 9007199254740991 THEN
      RAISE EXCEPTION 'Friendship revision exhausted during account closure'
        USING ERRCODE = '23514', CONSTRAINT = 'social_close_friendship_revision';
    END IF;
    observed_at := greatest(date_trunc('milliseconds', clock_timestamp()),
      friendship.updated_at + interval '1 millisecond');
    UPDATE trimmy.social_friendships f SET revision = f.revision + 1,
      state = 'removed', ended_at = observed_at, updated_at = observed_at
      WHERE f.id = friendship.id RETURNING f.* INTO friendship;
    INSERT INTO trimmy.social_friendship_events(
      friendship_id, revision, event_kind, actor_user_id,
      source_invitation_id, resulting_state, created_at)
    VALUES (friendship.id, friendship.revision, 'account_closed', selected_user,
      NULL, 'removed', friendship.updated_at);
    removed_count := removed_count + 1;
  END LOOP;
  RETURN QUERY SELECT canceled_count, removed_count;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.social_account_close_cleanup_internal(uuid, text) FROM PUBLIC;

CREATE FUNCTION trimmy.social_close_current_account(selected_fresh_x_subject text)
RETURNS TABLE (
  outcome text, closed boolean, canceled_invitations integer,
  removed_friendships integer
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE scoped_user uuid := trimmy.practice_current_user();
DECLARE account_status text;
DECLARE cleanup record;
DECLARE affected integer;
BEGIN
  IF scoped_user IS NULL OR selected_fresh_x_subject IS NOT NULL
      AND NOT trimmy.social_x_subject_valid(selected_fresh_x_subject) THEN
    RETURN QUERY SELECT 'invalid'::text, false, 0, 0;
    RETURN;
  END IF;
  SELECT u.status INTO account_status FROM trimmy.users u WHERE u.id = scoped_user;
  IF account_status IS NULL THEN
    RETURN QUERY SELECT 'account_missing'::text, false, 0, 0;
    RETURN;
  END IF;
  IF account_status = 'closed' THEN
    RETURN QUERY SELECT 'saved'::text, false, 0, 0;
    RETURN;
  END IF;
  SELECT * INTO cleanup FROM trimmy.social_account_close_cleanup_internal(
    scoped_user, selected_fresh_x_subject);
  UPDATE trimmy.users u SET status = 'closed'
    WHERE u.id = scoped_user AND u.status <> 'closed';
  GET DIAGNOSTICS affected = ROW_COUNT;
  RETURN QUERY SELECT 'saved'::text, affected = 1,
    cleanup.canceled_invitations, cleanup.removed_friendships;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.social_close_current_account(text) FROM PUBLIC;

-- Preserve the released zero-argument function for older clients while
-- routing all work through the counted atomic closure boundary.
CREATE OR REPLACE FUNCTION trimmy.practice_close_current_account() RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE closure record;
BEGIN
  SELECT * INTO closure FROM trimmy.social_close_current_account(NULL);
  IF closure.outcome = 'invalid' THEN
    RAISE EXCEPTION 'An account scope is required to close an account'
      USING ERRCODE = '22023';
  END IF;
  RETURN coalesce(closure.closed, false);
END;
$$;
REVOKE ALL ON FUNCTION trimmy.practice_close_current_account() FROM PUBLIC;

-- Direct invitation table authority is retired. The replacement trigger owns
-- only structural proof: an answered row must match its durable X binding.
DROP POLICY invitation_party_scope ON trimmy.invitations;
DROP TRIGGER scope_invitation_actor ON trimmy.invitations;
DROP FUNCTION trimmy.scope_invitation_actor();
DROP FUNCTION trimmy.invitation_self_x_subject();

CREATE FUNCTION trimmy.scope_invitation_actor() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.state <> 'draft' OR NEW.recipient_subject IS NOT NULL
        OR NEW.recipient_user_id IS NOT NULL OR NEW.accepted_at IS NOT NULL THEN
      RAISE EXCEPTION 'A new invitation must be an unaddressed draft'
        USING ERRCODE = '23514', CONSTRAINT = 'invitation_initial_state';
    END IF;
  ELSIF NEW.state IN ('accepted', 'declined') AND NEW.state <> OLD.state THEN
    IF NEW.recipient_user_id IS NULL OR NEW.recipient_provider <> 'x'
        OR NOT EXISTS (
          SELECT 1 FROM trimmy.provider_identities p
          WHERE p.user_id = NEW.recipient_user_id
            AND p.provider = NEW.recipient_provider
            AND p.subject = NEW.recipient_subject) THEN
      RAISE EXCEPTION 'Invitation answer requires its verified X binding'
        USING ERRCODE = '23514', CONSTRAINT = 'invitation_recipient_binding';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.scope_invitation_actor() FROM PUBLIC;
CREATE TRIGGER scope_invitation_actor BEFORE INSERT OR UPDATE ON trimmy.invitations
  FOR EACH ROW EXECUTE FUNCTION trimmy.scope_invitation_actor();

ALTER TABLE trimmy.provider_identities ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.provider_identities FORCE ROW LEVEL SECURITY;

ALTER TABLE trimmy.social_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.social_profiles FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.social_invitation_create_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.social_invitation_create_receipts FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.social_friendships ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.social_friendships FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.social_friendship_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.social_friendship_events FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.social_friendship_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.social_friendship_receipts FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.social_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.social_blocks FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.social_block_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.social_block_receipts FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.social_reason_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.social_reason_reports FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.social_reason_moderation ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.social_reason_moderation FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.social_reason_moderation_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.social_reason_moderation_events FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.social_rate_windows ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.social_rate_windows FORCE ROW LEVEL SECURITY;

CREATE POLICY provider_identity_function_authority ON trimmy.provider_identities
  USING (current_user = pg_catalog.pg_get_userbyid(
    (SELECT c.relowner FROM pg_catalog.pg_class c
      WHERE c.oid = 'trimmy.provider_identities'::pg_catalog.regclass)))
  WITH CHECK (current_user = pg_catalog.pg_get_userbyid(
    (SELECT c.relowner FROM pg_catalog.pg_class c
      WHERE c.oid = 'trimmy.provider_identities'::pg_catalog.regclass)));
CREATE POLICY invitation_function_authority ON trimmy.invitations
  USING (current_user = pg_catalog.pg_get_userbyid(
    (SELECT c.relowner FROM pg_catalog.pg_class c
      WHERE c.oid = 'trimmy.invitations'::pg_catalog.regclass)))
  WITH CHECK (current_user = pg_catalog.pg_get_userbyid(
    (SELECT c.relowner FROM pg_catalog.pg_class c
      WHERE c.oid = 'trimmy.invitations'::pg_catalog.regclass)));

DO $$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'social_profiles', 'social_invitation_create_receipts',
    'social_friendships', 'social_friendship_events',
    'social_friendship_receipts', 'social_blocks', 'social_block_receipts',
    'social_reason_reports', 'social_reason_moderation',
    'social_reason_moderation_events', 'social_rate_windows'
  ] LOOP
    EXECUTE format(
      'CREATE POLICY social_function_authority ON trimmy.%I USING '
      || '(current_user = pg_catalog.pg_get_userbyid((SELECT c.relowner '
      || 'FROM pg_catalog.pg_class c WHERE c.oid = %L::pg_catalog.regclass))) '
      || 'WITH CHECK (current_user = pg_catalog.pg_get_userbyid((SELECT c.relowner '
      || 'FROM pg_catalog.pg_class c WHERE c.oid = %L::pg_catalog.regclass)))',
      table_name, 'trimmy.' || table_name, 'trimmy.' || table_name);
  END LOOP;
END;
$$;

REVOKE ALL ON TABLE trimmy.provider_identities, trimmy.invitations,
  trimmy.social_profiles, trimmy.social_invitation_create_receipts,
  trimmy.social_friendships, trimmy.social_friendship_events,
  trimmy.social_friendship_receipts, trimmy.social_blocks,
  trimmy.social_block_receipts, trimmy.social_reason_reports,
  trimmy.social_reason_moderation, trimmy.social_reason_moderation_events,
  trimmy.social_rate_windows FROM PUBLIC;

INSERT INTO trimmy.schema_migrations(version)
VALUES ('0025_relationship_safety');
COMMIT;
