-- 0012: a real list of looked-up assets, separate from the fictional sample.
--
-- The existing watchlist stores only the eight fictional sample IDs, so a
-- person who looked up a real company through discovery had nowhere to keep it.
-- This is that list. It is deliberately a **second** table rather than a wider
-- allowlist on the first, so a sample list can never come to contain a real
-- asset and a real list can never contain a sample one.
--
-- Storing an identifier here is not an approval. Nothing reads this table as
-- evidence that an asset is verified, eligible, priced or tradeable; the live
-- catalog route still returns an empty, unverified list; and no money
-- capability changes. It holds identifiers only, with no price, quantity,
-- value or name snapshot, because a stored price or name would go stale and be
-- read as current.
BEGIN;

-- Wider than the sample slugs on purpose: a discovery identifier may begin with
-- a digit and run to 100 characters, so this accepts exactly that shape and
-- nothing else. Shape is all the database can check; it implies no approval.
CREATE FUNCTION trimmy.followed_stock_ids_valid(ids jsonb) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE STRICT SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE item jsonb; value text; seen text[] := ARRAY[]::text[];
BEGIN
  IF jsonb_typeof(ids) <> 'array' THEN RETURN false; END IF;
  IF jsonb_array_length(ids) > 50 OR octet_length(ids::text) > 6144 THEN RETURN false; END IF;
  FOR item IN SELECT jsonb_array_elements(ids) LOOP
    IF jsonb_typeof(item) <> 'string' THEN RETURN false; END IF;
    value := item #>> '{}';
    IF length(value) > 100 OR (value COLLATE "C") !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
      OR position(chr(10) in value) > 0 OR value = ANY(seen) THEN RETURN false; END IF;
    -- The eight fictional sample slugs are shaped like provider identifiers.
    -- Reserving them here keeps the real list and the sample list disjoint even
    -- if the application forgets to, so a fictional ID can never be stored and
    -- later read as a real asset.
    IF value = ANY(ARRAY['forma','orbital','grove','harbor','mesa','nori','pollen','helios']) THEN
      RETURN false;
    END IF;
    seen := array_append(seen, value);
  END LOOP;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.followed_stock_ids_valid(jsonb) FROM PUBLIC;

CREATE TABLE trimmy.followed_stocks (
  user_id uuid PRIMARY KEY REFERENCES trimmy.users(id),
  revision bigint NOT NULL CHECK (revision BETWEEN 1 AND 9007199254740991),
  asset_ids jsonb NOT NULL CHECK (trimmy.followed_stock_ids_valid(asset_ids)),
  updated_at timestamptz NOT NULL CHECK (isfinite(updated_at))
);
CREATE TABLE trimmy.followed_stock_mutation_receipts (
  user_id uuid NOT NULL REFERENCES trimmy.followed_stocks(user_id),
  mutation_id uuid NOT NULL,
  request_hash text NOT NULL CHECK (length(request_hash) = 64 AND request_hash ~ '^[a-f0-9]{64}$'),
  revision bigint NOT NULL CHECK (revision BETWEEN 1 AND 9007199254740991),
  asset_ids jsonb NOT NULL CHECK (trimmy.followed_stock_ids_valid(asset_ids)),
  updated_at timestamptz NOT NULL CHECK (isfinite(updated_at)),
  PRIMARY KEY (user_id, mutation_id),
  UNIQUE (user_id, revision)
);

CREATE FUNCTION trimmy.protect_followed_stock_revision() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.revision <> 1 THEN
      RAISE EXCEPTION 'Followed stock revisions begin at one' USING ERRCODE = '23514', CONSTRAINT = 'followed_stock_revision_sequence';
    END IF;
  ELSE
    IF NEW.user_id <> OLD.user_id THEN
      RAISE EXCEPTION 'Followed stock account is immutable' USING ERRCODE = '23514', CONSTRAINT = 'followed_stock_account_immutable';
    END IF;
    IF NEW.revision <> OLD.revision + 1 THEN
      RAISE EXCEPTION 'Followed stock revision must advance exactly once' USING ERRCODE = '23514', CONSTRAINT = 'followed_stock_revision_sequence';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.protect_followed_stock_revision() FROM PUBLIC;
CREATE TRIGGER followed_stock_revision_sequence BEFORE INSERT OR UPDATE ON trimmy.followed_stocks
  FOR EACH ROW EXECUTE FUNCTION trimmy.protect_followed_stock_revision();
CREATE TRIGGER followed_stock_no_delete BEFORE DELETE ON trimmy.followed_stocks
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();
CREATE TRIGGER followed_stock_receipt_append_only BEFORE UPDATE OR DELETE ON trimmy.followed_stock_mutation_receipts
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();

CREATE FUNCTION trimmy.check_followed_stock_receipt_pair() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  IF TG_TABLE_NAME = 'followed_stocks' THEN
    IF NOT EXISTS (
      SELECT 1 FROM trimmy.followed_stock_mutation_receipts r
      WHERE r.user_id = NEW.user_id AND r.revision = NEW.revision
        AND r.asset_ids = NEW.asset_ids AND r.updated_at = NEW.updated_at
    ) THEN
      RAISE EXCEPTION 'Followed stock snapshot requires its matching receipt' USING ERRCODE = '23514', CONSTRAINT = 'followed_stock_receipt_pair';
    END IF;
  ELSE
    IF NOT EXISTS (
      SELECT 1 FROM trimmy.followed_stocks w
      WHERE w.user_id = NEW.user_id AND w.revision >= NEW.revision
    ) THEN
      RAISE EXCEPTION 'Followed stock receipt requires its account snapshot' USING ERRCODE = '23514', CONSTRAINT = 'followed_stock_receipt_pair';
    END IF;
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.check_followed_stock_receipt_pair() FROM PUBLIC;
CREATE CONSTRAINT TRIGGER followed_stock_snapshot_receipt_pair AFTER INSERT OR UPDATE ON trimmy.followed_stocks
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trimmy.check_followed_stock_receipt_pair();
CREATE CONSTRAINT TRIGGER followed_stock_receipt_snapshot_pair AFTER INSERT ON trimmy.followed_stock_mutation_receipts
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trimmy.check_followed_stock_receipt_pair();

ALTER TABLE trimmy.followed_stocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.followed_stocks FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.followed_stock_mutation_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.followed_stock_mutation_receipts FORCE ROW LEVEL SECURITY;
CREATE POLICY followed_stock_account_scope ON trimmy.followed_stocks
  USING (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid)
  WITH CHECK (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid);
CREATE POLICY followed_stock_receipt_scope ON trimmy.followed_stock_mutation_receipts
  USING (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid)
  WITH CHECK (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid);
REVOKE ALL ON TABLE trimmy.followed_stocks, trimmy.followed_stock_mutation_receipts FROM PUBLIC;

-- Narrow deployment grants, applied by tool/runtime/apply-migrations.mjs:
--   GRANT EXECUTE ON FUNCTION trimmy.followed_stock_ids_valid(jsonb) TO trimmy_practice_runtime;
--   GRANT SELECT, INSERT, UPDATE ON trimmy.followed_stocks TO trimmy_practice_runtime;
--   GRANT SELECT, INSERT ON trimmy.followed_stock_mutation_receipts TO trimmy_practice_runtime;
-- No DELETE or TRUNCATE anywhere, exactly as for the sample watchlist: removing
-- an entry rewrites the list at the next revision and the receipt trail stays.
-- This adds no users, identity or financial privilege, and no catalog authority.

INSERT INTO trimmy.schema_migrations(version) VALUES ('0012_followed_stocks');
COMMIT;
