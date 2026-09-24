-- Runs after migration 0008. Verifies the fourth-floor payload v6 is now an
-- accepted snapshot and receipt version, that the earlier v4 seed and its
-- receipt survived the constraint widening, and that version 7 is the new
-- rejected future while a fresh downgrade is still refused. Self-contained and
-- rolled back so it leaves no state behind.
BEGIN;
CREATE TEMP TABLE practice_v6_checks(label text PRIMARY KEY);
GRANT SELECT, INSERT ON pg_temp.practice_v6_checks TO trimmy_practice_test_app;
CREATE FUNCTION pg_temp.v6_ok(condition boolean, label text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF condition IS NOT TRUE THEN
    RAISE EXCEPTION 'Practice v6 SQL check failed: %', label;
  END IF;
  INSERT INTO pg_temp.practice_v6_checks VALUES(label);
END;
$$;
CREATE FUNCTION pg_temp.v6_fails(statement text, label text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE observed_state text;
BEGIN
  BEGIN EXECUTE statement;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS observed_state = RETURNED_SQLSTATE;
  END;
  PERFORM pg_temp.v6_ok(observed_state = '23514', label);
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.v6_ok(boolean,text),
  pg_temp.v6_fails(text,text) TO trimmy_practice_test_app;

SET LOCAL ROLE trimmy_practice_test_app;
SELECT set_config(
  'trimmy.practice_user_id',
  'fd000000-0000-4000-a000-000000000001',
  true
);
SELECT pg_temp.v6_ok((
  SELECT revision = 1
    AND progress->'version' = '4'::jsonb
    AND (SELECT count(*) FROM jsonb_object_keys(progress->'completions')) = 8
  FROM trimmy.practice_progress
), 'Widening to v6 preserves the earlier v4 snapshot untouched');
SELECT pg_temp.v6_ok((
  SELECT revision = 1 AND progress->'version' = '4'::jsonb
    AND request_hash = repeat('d', 64)
  FROM trimmy.practice_mutation_receipts
), 'Widening to v6 preserves the exact v4 receipt body and hash');

UPDATE trimmy.practice_progress
SET revision = 2,
    progress = jsonb_set(
      jsonb_set(progress, '{version}', '6'),
      '{completions,set-a-loss-limit}',
      '{"activityId":"set-a-loss-limit","selectedChoiceId":"commit-spare-only","corrected":false,"completedAt":"2026-09-15T18:00:00.123456Z","importedFromLegacy":false}'::jsonb
    ),
    updated_at = '2026-09-15T18:00:00.000Z';
INSERT INTO trimmy.practice_mutation_receipts
SELECT user_id, 'fd000000-0000-4000-b000-000000000006'::uuid,
  repeat('a', 64), revision, progress, updated_at
FROM trimmy.practice_progress
WHERE user_id = 'fd000000-0000-4000-a000-000000000001';
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SELECT pg_temp.v6_ok((
  SELECT progress->'version' = '6'::jsonb
    AND progress->'completions'->'set-a-loss-limit'->>'selectedChoiceId' = 'commit-spare-only'
  FROM trimmy.practice_progress
), 'A fourth-floor v6 snapshot is accepted');
SELECT pg_temp.v6_ok((
  SELECT count(*) = 2 AND count(*) FILTER (WHERE progress->'version' = '6'::jsonb) = 1
  FROM trimmy.practice_mutation_receipts
), 'The v6 write appends a v6 receipt without rewriting the v4 receipt');

SELECT pg_temp.v6_fails(
  $q$UPDATE trimmy.practice_progress SET revision=3,
    progress=jsonb_set(progress,'{version}','5')$q$,
  'Fresh v6 to v5 downgrade is rejected');
SELECT pg_temp.v6_fails(
  $q$UPDATE trimmy.practice_progress SET revision=3,
    progress=jsonb_set(progress,'{version}','3')$q$,
  'Fresh v6 to v3 downgrade is rejected');
SELECT pg_temp.v6_fails(
  $q$UPDATE trimmy.practice_progress SET revision=3,
    progress=jsonb_set(progress,'{version}','7')$q$,
  'A version 7 future snapshot is rejected');
SELECT pg_temp.v6_fails(
  $q$INSERT INTO trimmy.practice_mutation_receipts
    SELECT user_id, 'fd000000-0000-4000-b000-000000000007'::uuid,
      repeat('c',64), 3, jsonb_set(progress,'{version}','7'), updated_at
    FROM trimmy.practice_progress$q$,
  'A version 7 future receipt is rejected');
SELECT pg_temp.v6_ok((
  SELECT revision = 2 AND progress->'version' = '6'::jsonb
  FROM trimmy.practice_progress
), 'Rejected writes leave the saved v6 snapshot intact');
SELECT pg_temp.v6_ok((
  SELECT count(*)=2 FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='trimmy'
    AND c.relname IN ('practice_progress','practice_mutation_receipts')
    AND c.relrowsecurity AND c.relforcerowsecurity
), 'Both practice tables still force RLS');
SELECT pg_temp.v6_ok(
  NOT has_table_privilege(
    current_user,
    'trimmy.financial_intents',
    'SELECT,INSERT,UPDATE,DELETE'
  ),
  'Widening to v6 adds no financial privileges'
);
SELECT count(*) AS practice_v6_sql_checks_passed
FROM pg_temp.practice_v6_checks;
ROLLBACK;
