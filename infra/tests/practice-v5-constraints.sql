BEGIN;
CREATE TEMP TABLE practice_v5_checks(label text PRIMARY KEY);
GRANT SELECT, INSERT ON pg_temp.practice_v5_checks TO trimmy_practice_test_app;
CREATE FUNCTION pg_temp.v5_ok(condition boolean, label text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF condition IS NOT TRUE THEN
    RAISE EXCEPTION 'Practice v5 SQL check failed: %', label;
  END IF;
  INSERT INTO pg_temp.practice_v5_checks VALUES(label);
END;
$$;
CREATE FUNCTION pg_temp.v5_fails(statement text, label text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE observed_state text;
BEGIN
  BEGIN EXECUTE statement;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS observed_state = RETURNED_SQLSTATE;
  END;
  PERFORM pg_temp.v5_ok(observed_state = '23514', label);
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.v5_ok(boolean,text),
  pg_temp.v5_fails(text,text) TO trimmy_practice_test_app;

SET LOCAL ROLE trimmy_practice_test_app;
SELECT set_config(
  'trimmy.practice_user_id',
  'fd000000-0000-4000-a000-000000000001',
  true
);
SELECT pg_temp.v5_ok((
  SELECT revision = 1
    AND progress->'version' = '4'::jsonb
    AND (SELECT count(*) FROM jsonb_object_keys(progress->'completions')) = 8
    AND progress->'completions'->'check-the-date'->>'selectedChoiceId' = 'keep-headline'
    AND progress->'completions'->'prepare-the-comparison'->>'selectedChoiceId' = 'ignore-the-fee'
  FROM trimmy.practice_progress
), 'Migration preserves all eight corrected v4 first answers');
SELECT pg_temp.v5_ok((
  SELECT revision = 1 AND progress->'version' = '4'::jsonb
    AND request_hash = repeat('d', 64)
  FROM trimmy.practice_mutation_receipts
), 'Migration preserves the exact v4 receipt body and hash');

UPDATE trimmy.practice_progress
SET revision = 2,
    progress = jsonb_set(
      jsonb_set(progress, '{version}', '5'),
      '{completions,review-team-update}',
      '{"activityId":"review-team-update","selectedChoiceId":"request-missing-costs","corrected":false,"completedAt":"2026-09-14T18:00:00.123456Z","importedFromLegacy":false}'::jsonb
    ),
    updated_at = '2026-09-14T18:00:00.000Z';
INSERT INTO trimmy.practice_mutation_receipts
SELECT user_id, 'fd000000-0000-4000-b000-000000000002'::uuid,
  repeat('e', 64), revision, progress, updated_at
FROM trimmy.practice_progress
WHERE user_id = 'fd000000-0000-4000-a000-000000000001';
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SELECT pg_temp.v5_ok((
  SELECT progress->'version' = '5'::jsonb
    AND progress->'completions'->'review-team-update'->>'selectedChoiceId' = 'request-missing-costs'
    AND progress->'completions'->'review-team-update'->>'corrected' = 'false'
  FROM trimmy.practice_progress
), 'A v5 defensible request branch persists without correction');
SELECT pg_temp.v5_ok((
  SELECT count(*) = 2 AND count(*) FILTER (WHERE progress->'version' = '4'::jsonb) = 1
  FROM trimmy.practice_mutation_receipts
), 'The v5 write appends without rewriting the v4 receipt');

SELECT pg_temp.v5_fails(
  $q$UPDATE trimmy.practice_progress SET revision=3,
    progress=jsonb_set(progress,'{version}','4')$q$,
  'Fresh v5 to v4 downgrade is rejected');
SELECT pg_temp.v5_fails(
  $q$UPDATE trimmy.practice_progress SET revision=3,
    progress=jsonb_set(progress,'{version}','3')$q$,
  'Fresh v5 to v3 downgrade is rejected');
SELECT pg_temp.v5_fails(
  $q$UPDATE trimmy.practice_progress SET revision=3,
    progress=jsonb_set(progress,'{version}','6')$q$,
  'Future snapshot payload is rejected');
SELECT pg_temp.v5_fails(
  $q$UPDATE trimmy.practice_progress SET revision=3,
    progress=jsonb_set(progress,'{completions,review-team-update,selectedChoiceId}',
      '"share-qualified-sales"')$q$,
  'The first team branch cannot be replaced');
SELECT pg_temp.v5_fails(
  $q$UPDATE trimmy.practice_progress SET revision=3,
    progress=progress #- '{completions,review-team-update}'$q$,
  'The first team branch cannot be removed');
SELECT pg_temp.v5_fails(
  $q$INSERT INTO trimmy.practice_mutation_receipts
    SELECT user_id, 'fd000000-0000-4000-b000-000000000003'::uuid,
      repeat('f',64), 3, jsonb_set(progress,'{version}','6'), updated_at
    FROM trimmy.practice_progress$q$,
  'Future receipt payload is rejected');
SELECT pg_temp.v5_ok((
  SELECT revision=2
    AND progress->'completions'->'review-team-update'->>'selectedChoiceId'='request-missing-costs'
  FROM trimmy.practice_progress
), 'Rejected writes leave the saved branch intact');
SELECT pg_temp.v5_ok((
  SELECT count(*)=2 FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='trimmy'
    AND c.relname IN ('practice_progress','practice_mutation_receipts')
    AND c.relrowsecurity AND c.relforcerowsecurity
), 'Both practice tables still force RLS');
SELECT pg_temp.v5_ok(
  NOT has_table_privilege(
    current_user,
    'trimmy.financial_intents',
    'SELECT,INSERT,UPDATE,DELETE'
  ),
  'Migration adds no financial privileges'
);
SELECT count(*) AS practice_v5_sql_checks_passed
FROM pg_temp.practice_v5_checks;
ROLLBACK;
