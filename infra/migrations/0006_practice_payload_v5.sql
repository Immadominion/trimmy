-- Apply as the original migration owner after 0005. Historical v3/v4
-- snapshots and receipts remain byte-equivalent JSONB values and replay with
-- their original request hashes.
BEGIN;

-- Match the repository's receipt-before-snapshot lock order so an in-flight
-- save finishes before the constraint replacement begins.
LOCK TABLE trimmy.practice_mutation_receipts, trimmy.practice_progress
  IN ACCESS EXCLUSIVE MODE;

ALTER TABLE trimmy.practice_progress
  DROP CONSTRAINT practice_progress_progress_check,
  ADD CONSTRAINT practice_progress_progress_check CHECK (
    jsonb_typeof(progress) = 'object'
    AND progress->'version' IN ('3'::jsonb, '4'::jsonb, '5'::jsonb)
    AND jsonb_typeof(progress->'completions') = 'object'
    AND jsonb_typeof(progress->'active') IN ('object', 'null')
    AND progress ?& ARRAY['version', 'active', 'completions']
    AND octet_length(progress::text) <= 32768);

ALTER TABLE trimmy.practice_mutation_receipts
  DROP CONSTRAINT practice_receipt_payload_version,
  ADD CONSTRAINT practice_receipt_payload_version CHECK (
    progress ? 'version'
    AND progress->'version' IN ('3'::jsonb, '4'::jsonb, '5'::jsonb));

-- The snapshot version can advance in one write when a dormant client returns,
-- but a fresh write can never move it backwards. Append-only old receipts are
-- intentionally outside this trigger.
CREATE OR REPLACE FUNCTION trimmy.protect_practice_payload_version()
RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  IF (OLD.progress->>'version')::integer >
      (NEW.progress->>'version')::integer THEN
    RAISE EXCEPTION 'Practice payload version cannot move backwards'
      USING ERRCODE = '23514',
        CONSTRAINT = 'practice_payload_version_monotonic';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.protect_practice_payload_version() FROM PUBLIC;

-- Existing RLS, grants, revision sequencing, first-completion preservation and
-- immutable receipt triggers stay in force.
INSERT INTO trimmy.schema_migrations(version)
VALUES ('0006_practice_payload_v5');
COMMIT;
