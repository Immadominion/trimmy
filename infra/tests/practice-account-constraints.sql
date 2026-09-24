-- Apply 0001..0003 and runtime EXECUTE grants first. Uses synthetic identities.
-- Owner/runtime behavior is tested in one transaction and all fixtures roll back.
BEGIN;
CREATE TEMP TABLE practice_account_checks (label text PRIMARY KEY);
CREATE TEMP TABLE practice_account_ids (label text PRIMARY KEY, user_id uuid NOT NULL);
GRANT SELECT, INSERT ON pg_temp.practice_account_checks, pg_temp.practice_account_ids TO trimmy_practice_test_app;
CREATE FUNCTION pg_temp.account_ok(condition boolean, label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF condition IS NOT TRUE THEN RAISE EXCEPTION 'Practice identity SQL check failed: %', label; END IF;
  INSERT INTO pg_temp.practice_account_checks VALUES (label);
END;
$$;
CREATE FUNCTION pg_temp.account_fails(statement text, expected_state text, label text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE observed_state text;
BEGIN
  BEGIN EXECUTE statement;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS observed_state = RETURNED_SQLSTATE;
  END;
  PERFORM pg_temp.account_ok(observed_state = expected_state, label);
END;
$$;
GRANT EXECUTE ON FUNCTION pg_temp.account_ok(boolean,text), pg_temp.account_fails(text,text,text) TO trimmy_practice_test_app;

SET LOCAL ROLE trimmy_practice_test_app;
SELECT pg_temp.account_ok(
  NOT has_table_privilege(current_user, 'trimmy.users', 'SELECT,INSERT,UPDATE,DELETE')
  AND NOT has_table_privilege(current_user, 'trimmy.practice_auth_identities', 'SELECT,INSERT,UPDATE,DELETE')
  AND NOT has_table_privilege(current_user, 'trimmy.provider_identities', 'SELECT,INSERT,UPDATE,DELETE')
  AND NOT has_table_privilege(current_user, 'trimmy.financial_intents', 'SELECT,INSERT,UPDATE,DELETE'),
  'Runtime has no user, mapping, X identity or financial table grants');
SELECT pg_temp.account_fails('SELECT * FROM trimmy.practice_auth_identities', '42501', 'Runtime cannot enumerate identity mappings');
SELECT pg_temp.account_fails('INSERT INTO trimmy.users DEFAULT VALUES', '42501', 'Runtime cannot insert arbitrary users');
SELECT pg_temp.account_ok(
  trimmy.practice_find_account('trimmy-sql-test-app', 'did:privy:sqlFirstIdentity') IS NULL,
  'Lookup of unknown verified identity returns null');
SELECT pg_temp.account_fails(
  $q$SELECT trimmy.practice_find_account('trimmy-sql-test-app', 'wallet-address')$q$,
  '22023', 'Find validates Privy DID structure');
SELECT pg_temp.account_fails(
  $q$SELECT trimmy.practice_provision_account(NULL, 'did:privy:sqlFirstIdentity')$q$,
  '22023', 'Provision requires an app ID');
SELECT pg_temp.account_fails(
  $q$SELECT trimmy.practice_provision_account('trimmy-sql-test-app', 'did:privy:')$q$,
  '22023', 'Provision requires a nonempty DID suffix');
SELECT pg_temp.account_fails(
  $q$SELECT trimmy.practice_provision_account('trimmy-sql-test-app', E'did:privy:sqlFirstIdentity\n')$q$,
  '22023', 'Provision rejects newline-bearing identity');

-- Deliberately shadow names in the caller's temp schema. Definer calls must
-- still access their schema-qualified real relations and trusted search_path.
CREATE TEMP TABLE users(id uuid, status text);
CREATE TEMP TABLE practice_auth_identities(app_id text, subject text, user_id uuid);
INSERT INTO pg_temp.users VALUES ('bb000000-0000-4000-a000-000000000001', 'active');
INSERT INTO pg_temp.practice_auth_identities VALUES ('trimmy-sql-test-app', 'did:privy:sqlFirstIdentity', 'bb000000-0000-4000-a000-000000000001');
SELECT pg_temp.account_ok(trimmy.practice_find_account('trimmy-sql-test-app', 'did:privy:sqlFirstIdentity') IS NULL,
  'Temporary shadow tables cannot forge a lookup');
INSERT INTO pg_temp.practice_account_ids VALUES ('first', trimmy.practice_provision_account('trimmy-sql-test-app', 'did:privy:sqlFirstIdentity'));
SELECT pg_temp.account_ok(
  (SELECT user_id <> 'bb000000-0000-4000-a000-000000000001'::uuid FROM pg_temp.practice_account_ids WHERE label='first'),
  'Provision creates its own UUID despite caller shadow tables');
SELECT pg_temp.account_ok(
  trimmy.practice_find_account('trimmy-sql-test-app', 'did:privy:sqlFirstIdentity') =
  (SELECT user_id FROM pg_temp.practice_account_ids WHERE label='first'),
  'Find resolves the provisioned stable UUID');
SELECT pg_temp.account_ok(
  trimmy.practice_provision_account('trimmy-sql-test-app', 'did:privy:sqlFirstIdentity') =
  (SELECT user_id FROM pg_temp.practice_account_ids WHERE label='first'),
  'Sequential provisioning converges on the first UUID');
INSERT INTO pg_temp.practice_account_ids VALUES ('other-app', trimmy.practice_provision_account('trimmy-other-app', 'did:privy:sqlFirstIdentity'));
INSERT INTO pg_temp.practice_account_ids VALUES ('other-subject', trimmy.practice_provision_account('trimmy-sql-test-app', 'did:privy:sqlSecondIdentity'));
SELECT pg_temp.account_ok((SELECT count(DISTINCT user_id) = 3 FROM pg_temp.practice_account_ids),
  'Different app or subject gets a distinct account');
SELECT pg_temp.account_ok(
  trimmy.practice_find_account('trimmy-sql-test-app', 'did:privy:sqlfirstidentity') IS NULL,
  'Opaque subject case is preserved');

RESET ROLE;
SELECT pg_temp.account_ok(
  (SELECT count(*) = 2 FROM trimmy.practice_auth_identities WHERE app_id='trimmy-sql-test-app'),
  'Sequential retry did not leave a duplicate identity');
SELECT pg_temp.account_ok(
  (SELECT count(*) = 3 FROM trimmy.users u JOIN pg_temp.practice_account_ids i ON i.user_id = u.id),
  'Exactly the expected three real users exist');
SELECT pg_temp.account_ok(
  (SELECT count(*) = 0 FROM trimmy.practice_progress p JOIN pg_temp.practice_account_ids i ON i.user_id = p.user_id),
  'Account provision does not invent practice progress');
SELECT pg_temp.account_ok(
  (SELECT count(*) = 0 FROM trimmy.provider_identities p JOIN pg_temp.practice_account_ids i ON i.user_id = p.user_id),
  'Account provision creates no financial X identity');
SELECT pg_temp.account_ok(
  NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace,
    LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
    WHERE n.nspname='trimmy' AND p.proname IN ('practice_find_account','practice_provision_account')
      AND a.grantee=0 AND a.privilege_type='EXECUTE'),
  'Neither definer function is executable by PUBLIC');
SELECT pg_temp.account_ok(
  (SELECT relrowsecurity FROM pg_catalog.pg_class WHERE oid='trimmy.practice_auth_identities'::regclass),
  'Identity mapping has default-deny runtime RLS');
SELECT pg_temp.account_fails(
  $q$UPDATE trimmy.practice_auth_identities SET subject='did:privy:replacement' WHERE app_id='trimmy-sql-test-app'$q$,
  '23514', 'Provider subject cannot be rebound');
SELECT pg_temp.account_fails(
  $q$UPDATE trimmy.practice_auth_identities SET user_id='bb000000-0000-4000-a000-000000000001' WHERE app_id='trimmy-sql-test-app'$q$,
  '23514', 'Practice UUID binding cannot be replaced');
SELECT pg_temp.account_fails(
  $q$DELETE FROM trimmy.practice_auth_identities WHERE app_id='trimmy-sql-test-app'$q$,
  '23514', 'Identity mapping history cannot be deleted');
SELECT pg_temp.account_fails(
  $q$INSERT INTO trimmy.practice_auth_identities(app_id,subject,user_id)
    SELECT 'trimmy-sql-test-app','did:privy:sqlFirstIdentity',user_id FROM pg_temp.practice_account_ids WHERE label='other-app'$q$,
  '23505', 'App and subject binding is unique');

UPDATE trimmy.users SET status='closed' WHERE id=(SELECT user_id FROM pg_temp.practice_account_ids WHERE label='first');
UPDATE trimmy.users SET status='restricted' WHERE id=(SELECT user_id FROM pg_temp.practice_account_ids WHERE label='other-subject');
SET LOCAL ROLE trimmy_practice_test_app;
SELECT pg_temp.account_ok(trimmy.practice_find_account('trimmy-sql-test-app','did:privy:sqlFirstIdentity') IS NULL,
  'Closed account is unavailable on lookup');
SELECT pg_temp.account_ok(trimmy.practice_provision_account('trimmy-sql-test-app','did:privy:sqlFirstIdentity') IS NULL,
  'Closed account cannot reprovision a new UUID');
SELECT pg_temp.account_ok(trimmy.practice_find_account('trimmy-sql-test-app','did:privy:sqlSecondIdentity') =
  (SELECT user_id FROM pg_temp.practice_account_ids WHERE label='other-subject'),
  'Financially restricted account can still use practice');
SELECT pg_temp.account_ok(trimmy.practice_provision_account('trimmy-sql-test-app','did:privy:sqlSecondIdentity') =
  (SELECT user_id FROM pg_temp.practice_account_ids WHERE label='other-subject'),
  'Restricted account provisioning retains its UUID');
RESET ROLE;
SELECT pg_temp.account_ok(
  (SELECT count(*) = 2 FROM trimmy.practice_auth_identities WHERE app_id='trimmy-sql-test-app'),
  'Closed retry leaves the same number of mappings');
SELECT pg_temp.account_ok(
  (SELECT count(*) = 2 FROM pg_catalog.pg_constraint WHERE conname IN
    ('live_operations_disabled_in_foundation','mainnet_execution_disabled_in_foundation')),
  'Financial execution gates remain intact');
SELECT count(*) AS practice_account_sql_checks_passed FROM pg_temp.practice_account_checks;
ROLLBACK;
