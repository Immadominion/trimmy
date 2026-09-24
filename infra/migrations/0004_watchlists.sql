-- Apply as the existing migration owner after 0003. This is a saved list of
-- catalog IDs, not holdings, orders, market data or permission to move money.
BEGIN;

CREATE FUNCTION trimmy.watchlist_asset_ids_valid(ids jsonb) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE STRICT SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE item jsonb; value text; seen text[] := ARRAY[]::text[];
BEGIN
  IF jsonb_typeof(ids) <> 'array' THEN RETURN false; END IF;
  IF jsonb_array_length(ids) > 50 OR octet_length(ids::text) > 4096 THEN RETURN false; END IF;
  FOR item IN SELECT jsonb_array_elements(ids) LOOP
    IF jsonb_typeof(item) <> 'string' THEN RETURN false; END IF;
    value := item #>> '{}';
    IF length(value) > 64 OR (value COLLATE "C") !~ '^[a-z][a-z0-9]*(-[a-z0-9]+)*$'
      OR position(chr(10) in value) > 0 OR value = ANY(seen) THEN RETURN false; END IF;
    seen := array_append(seen, value);
  END LOOP;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.watchlist_asset_ids_valid(jsonb) FROM PUBLIC;

CREATE TABLE trimmy.watchlists (
  user_id uuid PRIMARY KEY REFERENCES trimmy.users(id),
  revision bigint NOT NULL CHECK (revision BETWEEN 1 AND 9007199254740991),
  asset_ids jsonb NOT NULL CHECK (trimmy.watchlist_asset_ids_valid(asset_ids)),
  updated_at timestamptz NOT NULL CHECK (isfinite(updated_at))
);
CREATE TABLE trimmy.watchlist_mutation_receipts (
  user_id uuid NOT NULL REFERENCES trimmy.watchlists(user_id),
  mutation_id uuid NOT NULL,
  request_hash text NOT NULL CHECK (length(request_hash) = 64 AND request_hash ~ '^[a-f0-9]{64}$'),
  revision bigint NOT NULL CHECK (revision BETWEEN 1 AND 9007199254740991),
  asset_ids jsonb NOT NULL CHECK (trimmy.watchlist_asset_ids_valid(asset_ids)),
  updated_at timestamptz NOT NULL CHECK (isfinite(updated_at)),
  PRIMARY KEY (user_id, mutation_id),
  UNIQUE (user_id, revision)
);

CREATE FUNCTION trimmy.protect_watchlist_revision() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.revision <> 1 THEN
      RAISE EXCEPTION 'Watchlist revisions begin at one' USING ERRCODE = '23514', CONSTRAINT = 'watchlist_revision_sequence';
    END IF;
  ELSE
    IF NEW.user_id <> OLD.user_id THEN
      RAISE EXCEPTION 'Watchlist account is immutable' USING ERRCODE = '23514', CONSTRAINT = 'watchlist_account_immutable';
    END IF;
    IF NEW.revision <> OLD.revision + 1 THEN
      RAISE EXCEPTION 'Watchlist revision must advance exactly once' USING ERRCODE = '23514', CONSTRAINT = 'watchlist_revision_sequence';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.protect_watchlist_revision() FROM PUBLIC;
CREATE TRIGGER watchlist_revision_sequence BEFORE INSERT OR UPDATE ON trimmy.watchlists
  FOR EACH ROW EXECUTE FUNCTION trimmy.protect_watchlist_revision();
CREATE TRIGGER watchlist_no_delete BEFORE DELETE ON trimmy.watchlists
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();
CREATE TRIGGER watchlist_receipt_append_only BEFORE UPDATE OR DELETE ON trimmy.watchlist_mutation_receipts
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();

CREATE FUNCTION trimmy.check_watchlist_receipt_pair() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  IF TG_TABLE_NAME = 'watchlists' THEN
    IF NOT EXISTS (
      SELECT 1 FROM trimmy.watchlist_mutation_receipts r
      WHERE r.user_id = NEW.user_id AND r.revision = NEW.revision
        AND r.asset_ids = NEW.asset_ids AND r.updated_at = NEW.updated_at
    ) THEN
      RAISE EXCEPTION 'Watchlist snapshot requires its matching receipt' USING ERRCODE = '23514', CONSTRAINT = 'watchlist_receipt_pair';
    END IF;
  ELSE
    IF NOT EXISTS (
      SELECT 1 FROM trimmy.watchlists w
      WHERE w.user_id = NEW.user_id AND w.revision >= NEW.revision
    ) THEN
      RAISE EXCEPTION 'Watchlist receipt requires its account snapshot' USING ERRCODE = '23514', CONSTRAINT = 'watchlist_receipt_pair';
    END IF;
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.check_watchlist_receipt_pair() FROM PUBLIC;
CREATE CONSTRAINT TRIGGER watchlist_snapshot_receipt_pair AFTER INSERT OR UPDATE ON trimmy.watchlists
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trimmy.check_watchlist_receipt_pair();
CREATE CONSTRAINT TRIGGER watchlist_receipt_snapshot_pair AFTER INSERT ON trimmy.watchlist_mutation_receipts
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trimmy.check_watchlist_receipt_pair();

ALTER TABLE trimmy.watchlists ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.watchlists FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.watchlist_mutation_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.watchlist_mutation_receipts FORCE ROW LEVEL SECURITY;
CREATE POLICY watchlist_account_scope ON trimmy.watchlists
  USING (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid)
  WITH CHECK (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid);
CREATE POLICY watchlist_receipt_scope ON trimmy.watchlist_mutation_receipts
  USING (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid)
  WITH CHECK (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid);
REVOKE ALL ON TABLE trimmy.watchlists, trimmy.watchlist_mutation_receipts FROM PUBLIC;

-- Narrow deployment grants to a separately provisioned runtime role:
--   GRANT USAGE ON SCHEMA trimmy TO trimmy_watchlist_runtime;
--   GRANT EXECUTE ON FUNCTION trimmy.practice_account_exists(),
--     trimmy.watchlist_asset_ids_valid(jsonb) TO trimmy_watchlist_runtime;
--   GRANT SELECT, INSERT, UPDATE ON trimmy.watchlists TO trimmy_watchlist_runtime;
--   GRANT SELECT, INSERT ON trimmy.watchlist_mutation_receipts TO trimmy_watchlist_runtime;
-- Account IDs come from the existing server-verified authentication adapter;
-- transaction-local practice_user_id is isolation context, not authentication.
-- Runtime must be NOSUPERUSER NOBYPASSRLS and not an owner or owner member.
-- No DELETE/TRUNCATE/schema CREATE, users, identity or financial table grants.
-- Keep receipts: deleting them would break durable idempotent replay.
-- Database validates stable ID syntax, limits and uniqueness; the API/repository
-- additionally enforce an injected catalog allowlist (currently fictional IDs).

INSERT INTO trimmy.schema_migrations(version) VALUES ('0004_watchlists');
COMMIT;
