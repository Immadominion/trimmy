-- PostgreSQL 15+. Apply after 0001 using its dedicated migration owner.
-- No existing-table policy or grant is changed. Financial gates stay intact.
BEGIN;

CREATE TABLE trimmy.practice_progress (
  user_id uuid PRIMARY KEY REFERENCES trimmy.users(id),
  revision bigint NOT NULL CHECK (revision BETWEEN 1 AND 9007199254740991),
  progress jsonb NOT NULL CHECK (
    jsonb_typeof(progress) = 'object'
    AND progress->'version' = '3'::jsonb
    AND jsonb_typeof(progress->'completions') = 'object'
    AND jsonb_typeof(progress->'active') IN ('object', 'null')
    AND progress ?& ARRAY['version', 'active', 'completions']
    AND octet_length(progress::text) <= 32768),
  updated_at timestamptz NOT NULL CHECK (isfinite(updated_at))
);

CREATE TABLE trimmy.practice_mutation_receipts (
  user_id uuid NOT NULL REFERENCES trimmy.practice_progress(user_id),
  mutation_id uuid NOT NULL,
  request_hash text NOT NULL CHECK (request_hash ~ '^[a-f0-9]{64}$'),
  revision bigint NOT NULL CHECK (revision BETWEEN 1 AND 9007199254740991),
  progress jsonb NOT NULL CHECK (jsonb_typeof(progress) = 'object'),
  updated_at timestamptz NOT NULL CHECK (isfinite(updated_at)),
  PRIMARY KEY (user_id, mutation_id),
  UNIQUE (user_id, revision)
);

-- The runtime can ask only whether its already authenticated account exists.
-- This deliberately does not grant SELECT on users or change its deny-all RLS.
-- Owner must remain the 0001 migration owner, never the runtime role.
-- Trusted schemas precede pg_temp; every relation is schema-qualified.
CREATE FUNCTION trimmy.practice_account_exists() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
  SELECT EXISTS (
    SELECT 1 FROM trimmy.users
    WHERE id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid
      AND status <> 'closed'
  );
$$;
REVOKE ALL ON FUNCTION trimmy.practice_account_exists() FROM PUBLIC;

CREATE FUNCTION trimmy.protect_practice_progress() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.revision <> 1 THEN
      RAISE EXCEPTION 'Practice revisions begin at one' USING ERRCODE = '23514', CONSTRAINT = 'practice_revision_sequence';
    END IF;
  ELSE
    IF NEW.user_id <> OLD.user_id THEN
      RAISE EXCEPTION 'Practice account is immutable' USING ERRCODE = '23514', CONSTRAINT = 'practice_account_immutable';
    END IF;
    IF NEW.revision <> OLD.revision + 1 THEN
      RAISE EXCEPTION 'Practice revision must advance exactly once' USING ERRCODE = '23514', CONSTRAINT = 'practice_revision_sequence';
    END IF;
    IF EXISTS (
      SELECT 1 FROM jsonb_each(OLD.progress->'completions') AS saved
      WHERE NEW.progress->'completions'->saved.key IS DISTINCT FROM saved.value
    ) THEN
      RAISE EXCEPTION 'Saved first completions are immutable' USING ERRCODE = '23514', CONSTRAINT = 'practice_history_preserved';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.protect_practice_progress() FROM PUBLIC;

CREATE TRIGGER practice_revision_and_history BEFORE INSERT OR UPDATE ON trimmy.practice_progress
  FOR EACH ROW EXECUTE FUNCTION trimmy.protect_practice_progress();
CREATE TRIGGER practice_preserve_history BEFORE DELETE ON trimmy.practice_progress
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();
CREATE TRIGGER practice_receipt_append_only BEFORE UPDATE OR DELETE ON trimmy.practice_mutation_receipts
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();

-- Both sides must commit together. Deferred checks run after the receipt insert,
-- while preserving each intermediate committed revision if a transaction writes twice.
CREATE FUNCTION trimmy.check_practice_receipt_pair() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  IF TG_TABLE_NAME = 'practice_progress' THEN
    IF NOT EXISTS (
      SELECT 1 FROM trimmy.practice_mutation_receipts r
      WHERE r.user_id = NEW.user_id AND r.revision = NEW.revision
        AND r.progress = NEW.progress AND r.updated_at = NEW.updated_at
    ) THEN
      RAISE EXCEPTION 'Practice snapshot requires its matching receipt' USING ERRCODE = '23514', CONSTRAINT = 'practice_receipt_pair';
    END IF;
  ELSE
    IF NOT EXISTS (
      SELECT 1 FROM trimmy.practice_progress p
      WHERE p.user_id = NEW.user_id AND p.revision >= NEW.revision
    ) THEN
      RAISE EXCEPTION 'Practice receipt requires its account snapshot' USING ERRCODE = '23514', CONSTRAINT = 'practice_receipt_pair';
    END IF;
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.check_practice_receipt_pair() FROM PUBLIC;
CREATE CONSTRAINT TRIGGER practice_snapshot_receipt_pair AFTER INSERT OR UPDATE ON trimmy.practice_progress
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trimmy.check_practice_receipt_pair();
CREATE CONSTRAINT TRIGGER practice_receipt_snapshot_pair AFTER INSERT ON trimmy.practice_mutation_receipts
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trimmy.check_practice_receipt_pair();

ALTER TABLE trimmy.practice_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.practice_progress FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.practice_mutation_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.practice_mutation_receipts FORCE ROW LEVEL SECURITY;

CREATE POLICY practice_account_scope ON trimmy.practice_progress
  USING (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid)
  WITH CHECK (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid);
CREATE POLICY practice_receipt_scope ON trimmy.practice_mutation_receipts
  USING (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid)
  WITH CHECK (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid);

REVOKE ALL ON TABLE trimmy.practice_progress, trimmy.practice_mutation_receipts FROM PUBLIC;

-- Deployment grants, with a separately provisioned runtime role substituted:
--   GRANT USAGE ON SCHEMA trimmy TO trimmy_practice_runtime;
--   GRANT EXECUTE ON FUNCTION trimmy.practice_account_exists() TO trimmy_practice_runtime;
--   GRANT SELECT, INSERT, UPDATE ON trimmy.practice_progress TO trimmy_practice_runtime;
--   GRANT SELECT, INSERT ON trimmy.practice_mutation_receipts TO trimmy_practice_runtime;
-- No DELETE, TRUNCATE, REFERENCES, schema CREATE, role membership, or financial
-- table privileges. Runtime must be NOSUPERUSER NOBYPASSRLS and not an owner.
-- A server transaction sets trimmy.practice_user_id with set_config(..., true).
-- This context contains an identity verified by the server; it is not itself
-- authentication. Do not expose SQL credentials or context-setting to clients.
-- Receipts are retained with progress; pruning breaks the durable replay contract.
-- Sources: https://www.postgresql.org/docs/15/ddl-rowsecurity.html
--          https://www.postgresql.org/docs/15/sql-createfunction.html

INSERT INTO trimmy.schema_migrations (version) VALUES ('0002_practice_progress');
COMMIT;
