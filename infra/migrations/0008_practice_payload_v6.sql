-- Apply as the original migration owner after 0007. Historical v3/v4/v5
-- snapshots and receipts remain byte-equivalent JSONB values and replay with
-- their original request hashes. This admits native payload v6, which the
-- fourth floor (Make the plan) introduces, without rewriting any stored row.
BEGIN;

-- Match the repository's receipt-before-snapshot lock order so an in-flight
-- save finishes before the constraint replacement begins.
LOCK TABLE trimmy.practice_mutation_receipts, trimmy.practice_progress
  IN ACCESS EXCLUSIVE MODE;

ALTER TABLE trimmy.practice_progress
  DROP CONSTRAINT practice_progress_progress_check,
  ADD CONSTRAINT practice_progress_progress_check CHECK (
    jsonb_typeof(progress) = 'object'
    AND progress->'version' IN ('3'::jsonb, '4'::jsonb, '5'::jsonb, '6'::jsonb)
    AND jsonb_typeof(progress->'completions') = 'object'
    AND jsonb_typeof(progress->'active') IN ('object', 'null')
    AND progress ?& ARRAY['version', 'active', 'completions']
    AND octet_length(progress::text) <= 32768);

ALTER TABLE trimmy.practice_mutation_receipts
  DROP CONSTRAINT practice_receipt_payload_version,
  ADD CONSTRAINT practice_receipt_payload_version CHECK (
    progress ? 'version'
    AND progress->'version' IN ('3'::jsonb, '4'::jsonb, '5'::jsonb, '6'::jsonb));

-- The monotonic-version trigger from 0005 compares native versions generically
-- and needs no change. Existing RLS, grants, revision sequencing,
-- first-completion preservation and immutable receipt triggers stay in force.
INSERT INTO trimmy.schema_migrations(version)
VALUES ('0008_practice_payload_v6');
COMMIT;
