-- Run after both migrations and the documented grants to trimmy_practice_test_app.
-- All fake accounts, progress and helper functions are rolled back at the end.
BEGIN;
CREATE TEMP TABLE practice_checks (label text PRIMARY KEY);
GRANT SELECT, INSERT ON pg_temp.practice_checks TO trimmy_practice_test_app;
CREATE FUNCTION pg_temp.practice_ok(condition boolean, label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF condition IS NOT TRUE THEN RAISE EXCEPTION 'Practice SQL check failed: %', label; END IF;
  INSERT INTO pg_temp.practice_checks VALUES (label);
END;
$$;
CREATE FUNCTION pg_temp.practice_fails(statement text, expected_state text, label text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE observed_state text;
BEGIN
  BEGIN
    EXECUTE statement;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS observed_state = RETURNED_SQLSTATE;
  END;
  PERFORM pg_temp.practice_ok(observed_state = expected_state, label);
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.practice_ok(boolean, text), pg_temp.practice_fails(text, text, text)
  TO trimmy_practice_test_app;

INSERT INTO trimmy.users(id, status) VALUES
  ('fa000000-0000-4000-a000-000000000001', 'active'),
  ('fa000000-0000-4000-a000-000000000002', 'restricted'),
  ('fa000000-0000-4000-a000-000000000003', 'closed');

SET LOCAL ROLE trimmy_practice_test_app;
SELECT set_config('trimmy.practice_user_id', '', true);
SELECT pg_temp.practice_ok(NOT trimmy.practice_account_exists(), 'No context cannot see an account');
SELECT pg_temp.practice_ok((SELECT count(*) = 0 FROM trimmy.practice_progress), 'No context reads no progress');
SELECT pg_temp.practice_ok((SELECT count(*) = 0 FROM trimmy.practice_mutation_receipts), 'No context reads no receipts');
SELECT pg_temp.practice_fails(
  $q$INSERT INTO trimmy.practice_progress VALUES ('fa000000-0000-4000-a000-000000000001', 1,
    '{"version":3,"active":null,"completions":{}}', '2026-09-14T12:00:00.000Z')$q$,
  '42501', 'No context cannot insert progress');
SELECT pg_temp.practice_fails('SELECT id FROM trimmy.users', '42501', 'Runtime cannot enumerate users');
SELECT pg_temp.practice_ok(
  NOT has_table_privilege(current_user, 'trimmy.financial_intents', 'SELECT,INSERT,UPDATE,DELETE')
  AND NOT has_table_privilege(current_user, 'trimmy.execution_attempts', 'SELECT,INSERT,UPDATE,DELETE'),
  'Runtime has no financial table grants');
SELECT pg_temp.practice_ok(
  (SELECT count(*) = 2 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'trimmy' AND c.relname IN ('practice_progress', 'practice_mutation_receipts')
      AND c.relrowsecurity AND c.relforcerowsecurity),
  'Both practice tables force RLS');
SELECT pg_temp.practice_ok(
  NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace,
    LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    WHERE n.nspname = 'trimmy' AND p.proname = 'practice_account_exists'
      AND a.grantee = 0 AND a.privilege_type = 'EXECUTE'),
  'Account existence function has no PUBLIC execution');

SELECT set_config('trimmy.practice_user_id', 'fa000000-0000-4000-a000-000000000003', true);
SELECT pg_temp.practice_ok(NOT trimmy.practice_account_exists(), 'Closed account cannot use backup');
SELECT set_config('trimmy.practice_user_id', 'fa000000-0000-4000-a000-000000000099', true);
SELECT pg_temp.practice_ok(NOT trimmy.practice_account_exists(), 'Unknown account cannot use backup');
SELECT set_config('trimmy.practice_user_id', 'fa000000-0000-4000-a000-000000000002', true);
SELECT pg_temp.practice_ok(trimmy.practice_account_exists(), 'Restricted financial account can still practice');
SELECT set_config('trimmy.practice_user_id', 'fa000000-0000-4000-a000-000000000001', true);
SELECT pg_temp.practice_ok(trimmy.practice_account_exists(), 'Existing active account can practice');

SELECT pg_temp.practice_fails(
  $q$INSERT INTO trimmy.practice_progress VALUES ('fa000000-0000-4000-a000-000000000002', 1,
    '{"version":3,"active":null,"completions":{}}', '2026-09-14T12:00:00.000Z')$q$,
  '42501', 'Account cannot write another account progress');
SELECT pg_temp.practice_fails(
  $q$INSERT INTO trimmy.practice_progress VALUES ('fa000000-0000-4000-a000-000000000001', 1,
    '{"version":3,"active":null,"completions":{}}', '2026-09-14T12:00:00.000Z'); SET CONSTRAINTS ALL IMMEDIATE$q$,
  '23514', 'Snapshot without receipt cannot commit');
SELECT pg_temp.practice_ok((SELECT count(*) = 0 FROM trimmy.practice_progress), 'Failed paired write leaves no snapshot');

INSERT INTO trimmy.practice_progress VALUES ('fa000000-0000-4000-a000-000000000001', 1,
  '{"version":3,"active":null,"completions":{"check-the-date":{"activityId":"check-the-date","selectedChoiceId":"add-year","corrected":false,"completedAt":"2026-09-14T12:00:00.123456Z","importedFromLegacy":false}}}',
  '2026-09-14T12:00:00.000Z');
INSERT INTO trimmy.practice_mutation_receipts
  SELECT user_id, 'fa000000-0000-4000-b000-000000000001'::uuid, repeat('a',64), revision, progress, updated_at
  FROM trimmy.practice_progress WHERE user_id = 'fa000000-0000-4000-a000-000000000001';
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SELECT pg_temp.practice_ok((SELECT count(*) = 1 FROM trimmy.practice_progress), 'Paired initial snapshot is accepted');
SELECT pg_temp.practice_ok((SELECT count(*) = 1 FROM trimmy.practice_mutation_receipts), 'Initial receipt is present');
SELECT pg_temp.practice_fails('UPDATE trimmy.practice_progress SET revision = 3', '23514', 'Revision cannot skip a number');
SELECT pg_temp.practice_fails(
  $q$UPDATE trimmy.practice_progress SET revision = 2, progress = '{"version":3,"active":null,"completions":{}}'$q$,
  '23514', 'First completion cannot be removed through SQL');
SELECT pg_temp.practice_fails(
  $q$UPDATE trimmy.practice_progress SET revision = 2,
    progress = jsonb_set(progress, '{completions,check-the-date,completedAt}', '"2026-09-14T12:00:00.123457Z"')$q$,
  '23514', 'First completion microseconds cannot be overwritten');
SELECT pg_temp.practice_fails(
  $q$UPDATE trimmy.practice_progress SET revision = 2, user_id = 'fa000000-0000-4000-a000-000000000002'$q$,
  '23514', 'Snapshot ownership is immutable');
SELECT pg_temp.practice_fails('DELETE FROM trimmy.practice_progress', '42501', 'Runtime lacks progress deletion');
SELECT pg_temp.practice_fails('UPDATE trimmy.practice_mutation_receipts SET request_hash = repeat(''b'',64)',
  '42501', 'Runtime lacks receipt modification');
SELECT pg_temp.practice_fails('DELETE FROM trimmy.practice_mutation_receipts', '42501', 'Runtime lacks receipt deletion');
SELECT pg_temp.practice_fails('TRUNCATE trimmy.practice_progress CASCADE', '42501', 'Runtime lacks truncate');
SELECT pg_temp.practice_fails(
  $q$INSERT INTO trimmy.practice_mutation_receipts SELECT user_id,
    'fa000000-0000-4000-b000-000000000001'::uuid, repeat('b',64), revision, progress, updated_at
    FROM trimmy.practice_progress$q$, '23505', 'Mutation key is unique within account');
SELECT pg_temp.practice_fails(
  $q$INSERT INTO trimmy.practice_mutation_receipts SELECT user_id,
    'fa000000-0000-4000-b000-000000000002'::uuid, repeat('b',64), revision, progress, updated_at
    FROM trimmy.practice_progress$q$, '23505', 'Only one receipt can claim a committed revision');
SELECT pg_temp.practice_fails(
  $q$UPDATE trimmy.practice_progress SET revision = 2;
    INSERT INTO trimmy.practice_mutation_receipts SELECT user_id,
      'fa000000-0000-4000-b000-000000000002'::uuid, repeat('b',64), revision,
      '{"version":3,"active":null,"completions":{}}'::jsonb, updated_at FROM trimmy.practice_progress;
    SET CONSTRAINTS ALL IMMEDIATE$q$, '23514', 'Receipt must exactly match its committed progress');
SELECT pg_temp.practice_ok((SELECT revision = 1 FROM trimmy.practice_progress), 'Mismatched receipt rolls revision back');
SELECT pg_temp.practice_ok((SELECT count(*) = 1 FROM trimmy.practice_mutation_receipts), 'Mismatched receipt leaves no orphan receipt');

SELECT set_config('trimmy.practice_user_id', 'fa000000-0000-4000-a000-000000000002', true);
SELECT pg_temp.practice_ok((SELECT count(*) = 0 FROM trimmy.practice_progress), 'Second account cannot read first snapshot');
SELECT pg_temp.practice_ok((SELECT count(*) = 0 FROM trimmy.practice_mutation_receipts), 'Second account cannot read first receipt');
SELECT pg_temp.practice_fails(
  $q$INSERT INTO trimmy.practice_mutation_receipts VALUES (
    'fa000000-0000-4000-a000-000000000001', 'fa000000-0000-4000-b000-000000000002', repeat('b',64), 2,
    '{"version":3,"active":null,"completions":{}}', '2026-09-14T12:00:01.000Z')$q$,
  '42501', 'Second account cannot insert a first-account receipt');
SELECT set_config('trimmy.practice_user_id', '', true);
SELECT pg_temp.practice_ok((SELECT count(*) = 0 FROM trimmy.practice_progress), 'Cleared context cannot read existing snapshot');

RESET ROLE;
SELECT set_config('trimmy.practice_user_id', 'fa000000-0000-4000-a000-000000000001', true);
SELECT pg_temp.practice_fails('UPDATE trimmy.practice_mutation_receipts SET request_hash = repeat(''b'',64)',
  '23514', 'Receipt append-only trigger also blocks owner updates');
SELECT pg_temp.practice_fails('DELETE FROM trimmy.practice_mutation_receipts',
  '23514', 'Receipt append-only trigger also blocks owner deletes');
SELECT pg_temp.practice_ok(
  (SELECT count(*) = 2 FROM pg_catalog.pg_constraint WHERE conname IN
    ('live_operations_disabled_in_foundation', 'mainnet_execution_disabled_in_foundation')),
  'Both financial safety constraints remain present');
SELECT count(*) AS practice_sql_checks_passed FROM pg_temp.practice_checks;
ROLLBACK;
