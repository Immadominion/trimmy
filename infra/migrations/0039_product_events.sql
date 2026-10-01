BEGIN;
-- First-party product events: how the apps are used, so the team can see where
-- new players stop, whether they come back, and whether reminders help. No
-- third party receives them.
--
-- An event carries a random per-install id the app makes for itself, a session
-- id, the platform, app version and language, an allowlisted name and a few
-- allowlisted properties. Never an account id, name, email, IP address, device
-- identifier, amount or free text. The API validates every property before it
-- reaches this table; the checks here are the last line.
--
-- Recording needs no sign-in (a new player's first screens come before any
-- account), so the API rate-limits it. An install is tied to an account only
-- through product_install_link, which needs the account's own credential.
-- Closing an account deletes its links, which leaves that install's events
-- anonymous. Events and links older than 400 days are deleted.
CREATE TABLE trimmy.product_events (
 id uuid PRIMARY KEY,
 install_id uuid NOT NULL,
 session_id uuid NOT NULL,
 platform text COLLATE "C" NOT NULL CHECK (platform IN ('android','ios','web')),
 app_version text COLLATE "C" NOT NULL CHECK (app_version ~ '^[0-9A-Za-z][0-9A-Za-z.+_-]{0,39}$'),
 locale text COLLATE "C" NOT NULL CHECK (locale ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8}){0,2}$'),
 name text COLLATE "C" NOT NULL CHECK (name ~ '^[a-z][a-z0-9_]{1,39}$'),
 props jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(props) = 'object' AND octet_length(props::text) <= 512),
 occurred_at timestamptz NOT NULL CHECK (isfinite(occurred_at)),
 received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK (occurred_at BETWEEN received_at - interval '7 days' AND received_at + interval '5 minutes')
);
CREATE INDEX product_events_occurred ON trimmy.product_events(occurred_at);
CREATE INDEX product_events_install ON trimmy.product_events(install_id, occurred_at);
CREATE INDEX product_events_name ON trimmy.product_events(name, occurred_at);

CREATE TABLE trimmy.product_install_links (
 install_id uuid NOT NULL,
 user_id uuid NOT NULL REFERENCES trimmy.users(id),
 first_seen_at timestamptz NOT NULL CHECK (isfinite(first_seen_at)),
 last_seen_at timestamptz NOT NULL CHECK (isfinite(last_seen_at)),
 PRIMARY KEY (install_id, user_id),
 CHECK (last_seen_at >= first_seen_at)
);
CREATE INDEX product_install_links_user ON trimmy.product_install_links(user_id);

ALTER TABLE trimmy.product_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.product_events FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.product_install_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.product_install_links FORCE ROW LEVEL SECURITY;
REVOKE ALL ON trimmy.product_events, trimmy.product_install_links FROM PUBLIC;

-- Records one validated batch. A retried batch is a no-op (event ids are the
-- client's), and an event outside the accepted time window is skipped rather
-- than failing the batch. Returns how many events were new.
CREATE FUNCTION trimmy.product_events_record(batch jsonb) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE observed_at timestamptz := clock_timestamp(); inserted integer;
BEGIN
 IF jsonb_typeof(batch) IS DISTINCT FROM 'array' OR jsonb_array_length(batch) NOT BETWEEN 1 AND 50 THEN
  RAISE EXCEPTION 'EVENTS_INVALID';
 END IF;
 INSERT INTO trimmy.product_events(id, install_id, session_id, platform, app_version, locale, name, props, occurred_at, received_at)
 SELECT (e->>'id')::uuid, (e->>'installId')::uuid, (e->>'sessionId')::uuid, e->>'platform', e->>'appVersion', e->>'locale',
  e->>'name', coalesce(e->'props', '{}'::jsonb), (e->>'occurredAt')::timestamptz, observed_at
 FROM jsonb_array_elements(batch) e
 WHERE (e->>'occurredAt')::timestamptz BETWEEN observed_at - interval '7 days' AND observed_at + interval '5 minutes'
 ON CONFLICT (id) DO NOTHING;
 GET DIAGNOSTICS inserted = ROW_COUNT;
 RETURN inserted;
END; $$;
REVOKE ALL ON FUNCTION trimmy.product_events_record(jsonb) FROM PUBLIC;

-- Ties an install to the signed-in account (or guest desk) using it.
CREATE FUNCTION trimmy.product_install_link(viewer uuid, install uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE observed_at timestamptz := date_trunc('milliseconds', clock_timestamp());
BEGIN
 IF viewer IS NULL OR install IS NULL OR trimmy.practice_current_user() IS DISTINCT FROM viewer
   OR NOT EXISTS (SELECT 1 FROM trimmy.users WHERE id = viewer AND status = 'active') THEN
  RAISE EXCEPTION 'ACCOUNT_REQUIRED';
 END IF;
 INSERT INTO trimmy.product_install_links(install_id, user_id, first_seen_at, last_seen_at)
 VALUES (install, viewer, observed_at, observed_at)
 ON CONFLICT (install_id, user_id) DO UPDATE SET last_seen_at = greatest(trimmy.product_install_links.last_seen_at, excluded.last_seen_at);
END; $$;
REVOKE ALL ON FUNCTION trimmy.product_install_link(uuid, uuid) FROM PUBLIC;

-- Deletes events and links older than 400 days, a bounded batch at a time.
CREATE FUNCTION trimmy.product_events_prune() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE cutoff timestamptz := clock_timestamp() - interval '400 days'; removed integer; unlinked integer;
BEGIN
 DELETE FROM trimmy.product_events WHERE id IN (
  SELECT id FROM trimmy.product_events WHERE occurred_at < cutoff ORDER BY occurred_at LIMIT 10000);
 GET DIAGNOSTICS removed = ROW_COUNT;
 DELETE FROM trimmy.product_install_links WHERE last_seen_at < cutoff;
 GET DIAGNOSTICS unlinked = ROW_COUNT;
 RETURN removed + unlinked;
END; $$;
REVOKE ALL ON FUNCTION trimmy.product_events_prune() FROM PUBLIC;

-- A closed account keeps no link to the installs that used it.
CREATE FUNCTION trimmy.product_install_unlink_closed() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
 DELETE FROM trimmy.product_install_links WHERE user_id = NEW.id;
 RETURN NULL;
END; $$;
REVOKE ALL ON FUNCTION trimmy.product_install_unlink_closed() FROM PUBLIC;
CREATE TRIGGER product_install_unlink_closed AFTER UPDATE OF status ON trimmy.users
 FOR EACH ROW WHEN (NEW.status = 'closed' AND OLD.status IS DISTINCT FROM 'closed')
 EXECUTE FUNCTION trimmy.product_install_unlink_closed();

INSERT INTO trimmy.schema_migrations(version) VALUES('0039_product_events');
COMMIT;
