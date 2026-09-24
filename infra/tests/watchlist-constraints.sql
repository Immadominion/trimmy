-- Private integration cluster only; all test data/helpers roll back.
BEGIN;
CREATE TEMP TABLE watchlist_checks(label text PRIMARY KEY);
GRANT SELECT, INSERT ON pg_temp.watchlist_checks TO trimmy_watchlist_test_app;
CREATE FUNCTION pg_temp.watchlist_ok(condition boolean, label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF condition IS NOT TRUE THEN RAISE EXCEPTION 'Watchlist SQL check failed: %', label; END IF;
  INSERT INTO pg_temp.watchlist_checks VALUES(label);
END;
$$;
CREATE FUNCTION pg_temp.watchlist_fails(statement text, expected_state text, label text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE observed_state text;
BEGIN
  BEGIN EXECUTE statement;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS observed_state = RETURNED_SQLSTATE;
  END;
  PERFORM pg_temp.watchlist_ok(observed_state = expected_state, label);
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.watchlist_ok(boolean,text), pg_temp.watchlist_fails(text,text,text)
  TO trimmy_watchlist_test_app;
INSERT INTO trimmy.users(id,status) VALUES
  ('fb000000-0000-4000-a000-000000000001','active'),
  ('fb000000-0000-4000-a000-000000000002','restricted'),
  ('fb000000-0000-4000-a000-000000000003','closed');

SET LOCAL ROLE trimmy_watchlist_test_app;
SELECT set_config('trimmy.practice_user_id','',true);
SELECT pg_temp.watchlist_ok((SELECT count(*) = 0 FROM trimmy.watchlists), 'No context reads no watchlists');
SELECT pg_temp.watchlist_ok((SELECT count(*) = 0 FROM trimmy.watchlist_mutation_receipts), 'No context reads no receipts');
SELECT pg_temp.watchlist_fails(
  $q$INSERT INTO trimmy.watchlists VALUES ('fb000000-0000-4000-a000-000000000001',1,'[]','2026-09-14T12:00:00.000Z')$q$,
  '42501','No context cannot write a list');
SELECT pg_temp.watchlist_fails('SELECT id FROM trimmy.users','42501','Watchlist role cannot enumerate users');
SELECT pg_temp.watchlist_ok(
  NOT has_table_privilege(current_user,'trimmy.financial_intents','SELECT,INSERT,UPDATE,DELETE')
  AND NOT has_table_privilege(current_user,'trimmy.execution_attempts','SELECT,INSERT,UPDATE,DELETE')
  AND NOT has_table_privilege(current_user,'trimmy.practice_progress','SELECT,INSERT,UPDATE,DELETE'),
  'Dedicated watchlist role has no financial or practice-progress grants');
SELECT pg_temp.watchlist_ok(
  (SELECT count(*) = 2 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'trimmy' AND c.relname IN ('watchlists','watchlist_mutation_receipts')
      AND c.relrowsecurity AND c.relforcerowsecurity),
  'Both watchlist tables force RLS');
SELECT pg_temp.watchlist_ok(
  NOT EXISTS(SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace,
    LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
    WHERE n.nspname = 'trimmy' AND p.proname IN ('watchlist_asset_ids_valid','protect_watchlist_revision','check_watchlist_receipt_pair')
      AND a.grantee = 0 AND a.privilege_type = 'EXECUTE'),
  'Watchlist functions have no PUBLIC execution');
SELECT pg_temp.watchlist_ok(trimmy.watchlist_asset_ids_valid('[]'), 'An explicit empty list is valid');
SELECT pg_temp.watchlist_ok(NOT trimmy.watchlist_asset_ids_valid('["forma","forma"]'), 'Duplicate IDs rejected in SQL');
SELECT pg_temp.watchlist_ok(NOT trimmy.watchlist_asset_ids_valid('["FORMA"]'), 'Uppercase IDs rejected in SQL');
SELECT pg_temp.watchlist_ok(NOT trimmy.watchlist_asset_ids_valid('[null]'), 'Null IDs rejected in SQL');
SELECT pg_temp.watchlist_ok(NOT trimmy.watchlist_asset_ids_valid('{}'), 'Nonarray rejected in SQL');
SELECT pg_temp.watchlist_ok(NOT trimmy.watchlist_asset_ids_valid((SELECT jsonb_agg('asset-'||n) FROM generate_series(1,51) n)), 'More than fifty IDs rejected in SQL');
SELECT pg_temp.watchlist_ok(trimmy.watchlist_asset_ids_valid((SELECT jsonb_agg('asset-'||n) FROM generate_series(1,50) n)), 'Fifty unique IDs accepted in SQL');

SELECT set_config('trimmy.practice_user_id','fb000000-0000-4000-a000-000000000003',true);
SELECT pg_temp.watchlist_ok(NOT trimmy.practice_account_exists(), 'Closed account is unavailable');
SELECT set_config('trimmy.practice_user_id','fb000000-0000-4000-a000-000000000002',true);
SELECT pg_temp.watchlist_ok(trimmy.practice_account_exists(), 'Restricted account can keep a watchlist');
SELECT set_config('trimmy.practice_user_id','fb000000-0000-4000-a000-000000000001',true);
SELECT pg_temp.watchlist_fails(
  $q$INSERT INTO trimmy.watchlists VALUES ('fb000000-0000-4000-a000-000000000002',1,'[]','2026-09-14T12:00:00.000Z')$q$,
  '42501','Cannot write another account list');
SELECT pg_temp.watchlist_fails(
  $q$INSERT INTO trimmy.watchlists VALUES ('fb000000-0000-4000-a000-000000000001',1,'[]','2026-09-14T12:00:00.000Z'); SET CONSTRAINTS ALL IMMEDIATE$q$,
  '23514','A list without its receipt cannot commit');
SELECT pg_temp.watchlist_ok((SELECT count(*) = 0 FROM trimmy.watchlists), 'Failed paired write leaves no list');

INSERT INTO trimmy.watchlists VALUES ('fb000000-0000-4000-a000-000000000001',1,'["orbital","forma"]','2026-09-14T12:00:00.000Z');
INSERT INTO trimmy.watchlist_mutation_receipts
  SELECT user_id,'fb000000-0000-4000-b000-000000000001'::uuid,repeat('a',64),revision,asset_ids,updated_at FROM trimmy.watchlists;
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SELECT pg_temp.watchlist_ok((SELECT asset_ids = '["orbital","forma"]'::jsonb FROM trimmy.watchlists), 'Initial list preserves explicit order');
SELECT pg_temp.watchlist_fails('UPDATE trimmy.watchlists SET revision = 3','23514','Revision cannot skip');
SELECT pg_temp.watchlist_fails(
  $q$UPDATE trimmy.watchlists SET revision = 2,user_id = 'fb000000-0000-4000-a000-000000000002'$q$,
  '23514','List ownership is immutable');
SELECT pg_temp.watchlist_fails('DELETE FROM trimmy.watchlists','42501','Runtime cannot delete list records');
SELECT pg_temp.watchlist_fails('TRUNCATE trimmy.watchlists CASCADE','42501','Runtime cannot truncate');
SELECT pg_temp.watchlist_fails('UPDATE trimmy.watchlist_mutation_receipts SET request_hash = repeat(''b'',64)','42501','Runtime cannot update receipts');
SELECT pg_temp.watchlist_fails('DELETE FROM trimmy.watchlist_mutation_receipts','42501','Runtime cannot delete receipts');
SELECT pg_temp.watchlist_fails(
  $q$INSERT INTO trimmy.watchlist_mutation_receipts SELECT user_id,'fb000000-0000-4000-b000-000000000001'::uuid,repeat('b',64),revision,asset_ids,updated_at FROM trimmy.watchlists$q$,
  '23505','Mutation UUID is unique per account');
SELECT pg_temp.watchlist_fails(
  $q$INSERT INTO trimmy.watchlist_mutation_receipts SELECT user_id,'fb000000-0000-4000-b000-000000000002'::uuid,repeat('b',64),revision,asset_ids,updated_at FROM trimmy.watchlists$q$,
  '23505','Only one receipt can own a revision');
SELECT pg_temp.watchlist_fails(
  $q$UPDATE trimmy.watchlists SET revision = 2,asset_ids = '[]';
    INSERT INTO trimmy.watchlist_mutation_receipts SELECT user_id,'fb000000-0000-4000-b000-000000000002'::uuid,repeat('b',64),revision,'["forma"]'::jsonb,updated_at FROM trimmy.watchlists;
    SET CONSTRAINTS ALL IMMEDIATE$q$,
  '23514','Receipt must match exact saved list');
SELECT pg_temp.watchlist_ok((SELECT revision = 1 FROM trimmy.watchlists), 'Mismatched receipt rolls list revision back');

UPDATE trimmy.watchlists SET revision = 2,asset_ids = '[]';
INSERT INTO trimmy.watchlist_mutation_receipts
  SELECT user_id,'fb000000-0000-4000-b000-000000000002'::uuid,repeat('b',64),revision,asset_ids,updated_at FROM trimmy.watchlists;
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;
SELECT pg_temp.watchlist_ok((SELECT revision = 2 AND asset_ids = '[]'::jsonb FROM trimmy.watchlists), 'Clearing preserves an explicit empty saved list');
SELECT pg_temp.watchlist_ok((SELECT asset_ids = '["orbital","forma"]'::jsonb FROM trimmy.watchlist_mutation_receipts WHERE revision = 1), 'Clearing preserves original retry receipt');
SELECT set_config('trimmy.practice_user_id','fb000000-0000-4000-a000-000000000002',true);
SELECT pg_temp.watchlist_ok((SELECT count(*) = 0 FROM trimmy.watchlists), 'Second account cannot read first list');
SELECT pg_temp.watchlist_ok((SELECT count(*) = 0 FROM trimmy.watchlist_mutation_receipts), 'Second account cannot read first receipts');
SELECT pg_temp.watchlist_fails(
  $q$INSERT INTO trimmy.watchlist_mutation_receipts VALUES('fb000000-0000-4000-a000-000000000001','fb000000-0000-4000-b000-000000000003',repeat('c',64),3,'[]','2026-09-14T12:00:00.000Z')$q$,
  '42501','Cannot insert another account receipt');
SELECT set_config('trimmy.practice_user_id','',true);
SELECT pg_temp.watchlist_ok((SELECT count(*) = 0 FROM trimmy.watchlists), 'Cleared context cannot read saved lists');
RESET ROLE;
SELECT set_config('trimmy.practice_user_id','fb000000-0000-4000-a000-000000000001',true);
SELECT pg_temp.watchlist_fails('UPDATE trimmy.watchlist_mutation_receipts SET request_hash = repeat(''c'',64)','23514','Owner cannot rewrite receipt');
SELECT pg_temp.watchlist_fails('DELETE FROM trimmy.watchlist_mutation_receipts','23514','Owner cannot delete receipt');
SELECT pg_temp.watchlist_ok(
  (SELECT count(*) = 2 FROM pg_catalog.pg_constraint WHERE conname IN ('live_operations_disabled_in_foundation','mainnet_execution_disabled_in_foundation')),
  'Financial denial constraints remain present');
SELECT count(*) AS watchlist_sql_checks_passed FROM pg_temp.watchlist_checks;
ROLLBACK;
