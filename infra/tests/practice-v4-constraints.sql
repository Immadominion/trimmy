-- Historical seed was committed under migration0002 before applying0005.
-- All changes below are rolled back, retaining it for the real HTTP upgrade.
BEGIN;
CREATE TEMP TABLE practice_v4_checks(label text PRIMARY KEY);
GRANT SELECT, INSERT ON pg_temp.practice_v4_checks TO trimmy_practice_test_app;
CREATE FUNCTION pg_temp.v4_ok(condition boolean, label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF condition IS NOT TRUE THEN RAISE EXCEPTION 'Practice v4 SQL check failed: %', label; END IF;
  INSERT INTO pg_temp.practice_v4_checks VALUES(label);
END;
$$;
CREATE FUNCTION pg_temp.v4_fails(statement text, label text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE observed_state text;
BEGIN
  BEGIN EXECUTE statement;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS observed_state = RETURNED_SQLSTATE;
  END;
  PERFORM pg_temp.v4_ok(observed_state = '23514', label);
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.v4_ok(boolean,text), pg_temp.v4_fails(text,text) TO trimmy_practice_test_app;
SET LOCAL ROLE trimmy_practice_test_app;
SELECT set_config('trimmy.practice_user_id', 'fc000000-0000-4000-a000-000000000001', true);
SELECT pg_temp.v4_ok((SELECT revision=1 AND progress->'version'='3'::jsonb
  AND progress->'completions'->'check-the-date'->>'completedAt'='2026-09-14T10:20:30.123456Z'
  FROM trimmy.practice_progress), 'Migration preserves the old snapshot and precise first note');
SELECT pg_temp.v4_ok((SELECT revision=1 AND progress->'version'='3'::jsonb
  AND updated_at='2026-09-14T12:00:00.000Z' FROM trimmy.practice_mutation_receipts),
  'Migration preserves the original version3 receipt');

UPDATE trimmy.practice_progress SET revision=2, progress=jsonb_set(progress, '{version}', '4');
INSERT INTO trimmy.practice_mutation_receipts
SELECT user_id, 'fc000000-0000-4000-b000-000000000002'::uuid, repeat('b',64), revision, progress, updated_at
FROM trimmy.practice_progress;
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SELECT pg_temp.v4_ok((SELECT revision=2 AND progress->'version'='4'::jsonb FROM trimmy.practice_progress), 'Version3 upgrades to version4');
SELECT pg_temp.v4_ok((SELECT count(*)=2 FROM trimmy.practice_mutation_receipts), 'Upgrade appends one receipt');
SELECT pg_temp.v4_ok((SELECT progress->'version'='3'::jsonb FROM trimmy.practice_mutation_receipts WHERE revision=1), 'Upgrade does not rewrite the old receipt');
SELECT pg_temp.v4_fails($q$UPDATE trimmy.practice_progress SET revision=3, progress=jsonb_set(progress,'{version}','3')$q$, 'Fresh downgrade blocked through direct SQL');
SELECT pg_temp.v4_fails($q$UPDATE trimmy.practice_progress SET revision=3, progress=jsonb_set(progress,'{version}','5')$q$, 'Future payload blocked through direct SQL');
SELECT pg_temp.v4_fails($q$UPDATE trimmy.practice_progress SET revision=3, progress=progress-'version'$q$, 'Missing payload version rejected');
SELECT pg_temp.v4_fails($q$UPDATE trimmy.practice_progress SET revision=3, progress=jsonb_set(progress,'{version}','"4"')$q$, 'String payload version rejected');
SELECT pg_temp.v4_fails($q$UPDATE trimmy.practice_progress SET revision=3, progress=jsonb_set(progress,'{completions}','{}')$q$, 'First history remains immutable after upgrade');
SELECT pg_temp.v4_fails($q$INSERT INTO trimmy.practice_mutation_receipts
  SELECT user_id, 'fc000000-0000-4000-b000-000000000003'::uuid, repeat('c',64), 3,
    jsonb_set(progress,'{version}','5'), updated_at FROM trimmy.practice_progress$q$, 'Receipt cannot contain a future payload');
SELECT pg_temp.v4_ok((SELECT revision=2 AND progress->'version'='4'::jsonb FROM trimmy.practice_progress), 'Rejected writes leave the upgraded snapshot intact');
SELECT pg_temp.v4_ok((SELECT count(*)=2 FROM trimmy.practice_mutation_receipts), 'Rejected writes leave no orphan receipt');
SELECT pg_temp.v4_ok((SELECT count(*)=2 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='trimmy' AND c.relname IN ('practice_progress','practice_mutation_receipts')
  AND c.relrowsecurity AND c.relforcerowsecurity), 'Both practice tables still force RLS');
SELECT pg_temp.v4_ok(NOT has_table_privilege(current_user,'trimmy.financial_intents','SELECT,INSERT,UPDATE,DELETE'), 'Migration adds no financial privileges');
SELECT set_config('trimmy.practice_user_id','00000000-0000-4000-8000-000000000002',true);
SELECT pg_temp.v4_ok((SELECT count(*)=0 FROM trimmy.practice_progress), 'Other account cannot read the upgraded snapshot');
SELECT pg_temp.v4_ok((SELECT count(*)=0 FROM trimmy.practice_mutation_receipts), 'Other account cannot read either receipt version');
SELECT count(*) AS practice_v4_sql_checks_passed FROM pg_temp.practice_v4_checks;
ROLLBACK;
