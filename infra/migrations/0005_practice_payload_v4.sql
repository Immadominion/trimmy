-- Apply as the original migration owner. This does not rewrite any snapshot or
-- receipt: historical v3 retries must retain their exact payload and request hash.
BEGIN;

-- PUT reads its receipt before acquiring the snapshot lock. Match that order
-- explicitly so an in-flight save can finish before this migration validates
-- both tables, rather than deadlocking across opposite table-lock orders.
LOCK TABLE trimmy.practice_mutation_receipts, trimmy.practice_progress
  IN ACCESS EXCLUSIVE MODE;

ALTER TABLE trimmy.practice_progress
  DROP CONSTRAINT practice_progress_progress_check,
  ADD CONSTRAINT practice_progress_progress_check CHECK (
    jsonb_typeof(progress) = 'object'
    AND progress->'version' IN ('3'::jsonb, '4'::jsonb)
    AND jsonb_typeof(progress->'completions') = 'object'
    AND jsonb_typeof(progress->'active') IN ('object', 'null')
    AND progress ?& ARRAY['version', 'active', 'completions']
    AND octet_length(progress::text) <= 32768);

ALTER TABLE trimmy.practice_mutation_receipts
  ADD CONSTRAINT practice_receipt_payload_version CHECK (
    progress ? 'version' AND progress->'version' IN ('3'::jsonb, '4'::jsonb));

-- Keep the existing revision/history trigger. This independent guard applies
-- only to new snapshot updates, never to append-only historical receipts.
CREATE FUNCTION trimmy.protect_practice_payload_version() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  IF OLD.progress->'version' = '4'::jsonb AND NEW.progress->'version' = '3'::jsonb THEN
    RAISE EXCEPTION 'Practice payload version cannot move backwards'
      USING ERRCODE = '23514', CONSTRAINT = 'practice_payload_version_monotonic';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.protect_practice_payload_version() FROM PUBLIC;
CREATE TRIGGER practice_payload_version_monotonic BEFORE UPDATE ON trimmy.practice_progress
  FOR EACH ROW EXECUTE FUNCTION trimmy.protect_practice_payload_version();

-- RLS, runtime grants, first-history and receipt immutability stay in force.
INSERT INTO trimmy.schema_migrations(version) VALUES ('0005_practice_payload_v4');
COMMIT;
