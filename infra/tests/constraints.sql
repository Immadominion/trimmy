\set ON_ERROR_STOP on
BEGIN;
CREATE TEMP TABLE checks (name text PRIMARY KEY);
CREATE FUNCTION pg_temp.assert_true(label text, actual boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF actual IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAILED: %', label; END IF;
  INSERT INTO checks VALUES (label);
END;
$$;
CREATE FUNCTION pg_temp.expect_failure(label text, statement text, expected_state text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE statement;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE <> expected_state THEN
      RAISE EXCEPTION 'FAILED: %, expected SQLSTATE %, received % (%)', label, expected_state, SQLSTATE, SQLERRM;
    END IF;
    INSERT INTO checks VALUES (label);
    RETURN;
  END;
  RAISE EXCEPTION 'FAILED: %, expected statement to fail', label;
END;
$$;

SELECT pg_temp.assert_true('catalog starts empty', NOT EXISTS (SELECT 1 FROM trimmy.assets));
SELECT pg_temp.assert_true('raw amount preserves exact u64 maximum',
  '18446744073709551615'::trimmy.raw_amount = 18446744073709551615::numeric);
SELECT pg_temp.expect_failure('fractional raw amounts rejected without rounding', $sql$SELECT 1.2::trimmy.raw_amount$sql$, '23514');
SELECT pg_temp.expect_failure('negative raw amounts rejected', $sql$SELECT (-1)::trimmy.raw_amount$sql$, '23514');
SELECT pg_temp.expect_failure('u64 overflow rejected', $sql$SELECT 18446744073709551616::trimmy.raw_amount$sql$, '23514');
SELECT pg_temp.expect_failure('NaN rejected', $sql$SELECT 'NaN'::trimmy.raw_amount$sql$, '23514');
SELECT pg_temp.expect_failure('infinite raw amounts rejected', $sql$SELECT 'Infinity'::trimmy.raw_amount$sql$, '23514');
SELECT pg_temp.expect_failure('malformed mint rejected', $sql$SELECT '0OIl'::trimmy.solana_address$sql$, '23514');

INSERT INTO trimmy.users (id) VALUES
  ('10000000-0000-4000-8000-000000000001'), ('10000000-0000-4000-8000-000000000002'),
  ('10000000-0000-4000-8000-000000000003');
INSERT INTO trimmy.provider_identities (id, user_id, provider, subject, handle_snapshot, verified_at) VALUES
  ('20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'x', '111', 'sender', now()),
  ('20000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000002', 'x', '222', 'recipient', now());
SELECT pg_temp.expect_failure('one user binding per provider subject', $sql$
  INSERT INTO trimmy.provider_identities (user_id, provider, subject, verified_at)
  VALUES ('10000000-0000-4000-8000-000000000002', 'x', '111', now())$sql$, '23505');
SELECT pg_temp.expect_failure('X subject cannot change with a handle rename', $sql$
  UPDATE trimmy.provider_identities SET subject = '333' WHERE subject = '111'$sql$, '23514');
UPDATE trimmy.provider_identities SET handle_snapshot = 'renamed' WHERE subject = '111';
SELECT pg_temp.assert_true('handle snapshots can refresh while identity remains stable',
  EXISTS (SELECT 1 FROM trimmy.provider_identities WHERE subject = '111' AND handle_snapshot = 'renamed'));
SELECT pg_temp.expect_failure('identity cannot be rebound to another user', $sql$
  UPDATE trimmy.provider_identities SET user_id = '10000000-0000-4000-8000-000000000002' WHERE subject = '111'$sql$, '23514');

INSERT INTO trimmy.wallet_bindings (id, user_id, network, address, verified_at) VALUES
  ('30000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'devnet', repeat('1', 32), now()),
  ('30000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000002', 'devnet', repeat('2', 32), now());
SELECT pg_temp.expect_failure('wallet ownership cannot be rebound', $sql$
  UPDATE trimmy.wallet_bindings SET user_id = '10000000-0000-4000-8000-000000000002'
  WHERE id = '30000000-0000-4000-8000-000000000001'$sql$, '23514');

INSERT INTO trimmy.assets (id, asset_key, symbol, legal_name, issuer, network, mint, token_program, decimals) VALUES
  ('40000000-0000-4000-8000-000000000001', 'test-one', 'TEST1', 'Test fixture only', 'Local fixture', 'devnet', repeat('3', 32), 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb', 9),
  ('40000000-0000-4000-8000-000000000002', 'test-two', 'TEST2', 'Test fixture only', 'Local fixture', 'devnet', repeat('4', 32), 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb', 6),
  ('40000000-0000-4000-8000-000000000003', 'test-other-network', 'TEST3', 'Test fixture only', 'Local fixture', 'mainnet-beta', repeat('5', 32), 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb', 6);
SELECT pg_temp.expect_failure('asset cannot enable without review evidence', $sql$
  UPDATE trimmy.assets SET status = 'enabled' WHERE asset_key = 'test-one'$sql$, '23514');
SELECT pg_temp.expect_failure('registry mint cannot be substituted', $sql$
  UPDATE trimmy.assets SET mint = repeat('6', 32) WHERE asset_key = 'test-one'$sql$, '23514');

INSERT INTO trimmy.eligibility_attestations
  (id, user_id, identity_id, asset_id, country_code, policy_version, decision, reason_code, evidence_reference, issued_at, expires_at)
VALUES ('60000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000001',
  'ZZ', 'test-policy', 'pending', 'TEST_ONLY', 'fixture:no-approval', now(), now() + interval '1 hour');
SELECT pg_temp.expect_failure('attestation identity must belong to user', $sql$
  INSERT INTO trimmy.eligibility_attestations
    (user_id, identity_id, asset_id, country_code, policy_version, decision, reason_code, evidence_reference, issued_at, expires_at)
  VALUES ('10000000-0000-4000-8000-000000000002', '20000000-0000-4000-8000-000000000001',
    '40000000-0000-4000-8000-000000000001', 'ZZ', 'test-policy', 'pending', 'TEST_ONLY', 'fixture', now(), now() + interval '1 hour')$sql$, '23503');
SELECT pg_temp.expect_failure('attestation decision cannot be rewritten', $sql$
  UPDATE trimmy.eligibility_attestations SET decision = 'eligible'$sql$, '23514');
INSERT INTO trimmy.eligibility_revocations (attestation_id, reason_code)
  VALUES ('60000000-0000-4000-8000-000000000001', 'TEST_REVOCATION');
SELECT pg_temp.expect_failure('revocation cannot be removed', $sql$
  DELETE FROM trimmy.eligibility_revocations$sql$, '23514');

INSERT INTO trimmy.invitations (id, sender_user_id, expires_at) VALUES
  ('50000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', now() + interval '1 day');
SELECT pg_temp.expect_failure('invitation cannot pretend to be funded', $sql$
  UPDATE trimmy.invitations SET funding_kind = 'escrow', version = version + 1$sql$, '23514');
SELECT pg_temp.expect_failure('invitation optimistic version is enforced', $sql$
  UPDATE trimmy.invitations SET state = 'canceled'$sql$, '23514');
SELECT pg_temp.expect_failure('draft cannot skip straight to offered', $sql$
  UPDATE trimmy.invitations SET state = 'offered', recipient_provider = 'x', recipient_subject = '222', version = version + 1$sql$, '23514');
UPDATE trimmy.invitations SET state = 'addressed', recipient_provider = 'x', recipient_subject = '222', version = version + 1;
SELECT pg_temp.expect_failure('addressed identity cannot be swapped', $sql$
  UPDATE trimmy.invitations SET recipient_subject = '333', version = version + 1$sql$, '23514');
UPDATE trimmy.invitations SET state = 'offered', version = version + 1;
SELECT pg_temp.expect_failure('wrong recipient cannot accept', $sql$
  UPDATE trimmy.invitations SET state = 'accepted', recipient_user_id = '10000000-0000-4000-8000-000000000003',
    accepted_at = now(), version = version + 1$sql$, '23503');
SELECT pg_temp.expect_failure('sender cannot self-accept another identity invitation', $sql$
  UPDATE trimmy.invitations SET state = 'accepted', recipient_user_id = '10000000-0000-4000-8000-000000000001',
    accepted_at = now(), version = version + 1$sql$, '23514');
UPDATE trimmy.invitations SET state = 'accepted', recipient_user_id = '10000000-0000-4000-8000-000000000002',
  accepted_at = clock_timestamp(), version = version + 1;
SELECT pg_temp.assert_true('eligible identity-addressed acceptance stays unfunded',
  EXISTS (SELECT 1 FROM trimmy.invitations WHERE state = 'accepted' AND funding_kind = 'unfunded' AND version = 3));
SELECT pg_temp.expect_failure('terminal invitation cannot be reopened', $sql$
  UPDATE trimmy.invitations SET state = 'offered', accepted_at = NULL, version = version + 1$sql$, '23514');
INSERT INTO trimmy.invitations (id, sender_user_id, created_at, expires_at) VALUES
  ('50000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001',
    now() - interval '2 days', now() - interval '1 day');
UPDATE trimmy.invitations SET state = 'addressed', recipient_provider = 'x', recipient_subject = '222', version = 1
  WHERE id = '50000000-0000-4000-8000-000000000002';
UPDATE trimmy.invitations SET state = 'offered', version = 2 WHERE id = '50000000-0000-4000-8000-000000000002';
SELECT pg_temp.expect_failure('expired invitation cannot be accepted using a forged earlier timestamp', $sql$
  UPDATE trimmy.invitations SET state = 'accepted', recipient_user_id = '10000000-0000-4000-8000-000000000002',
    accepted_at = now() - interval '36 hours', version = 3 WHERE id = '50000000-0000-4000-8000-000000000002'$sql$, '23514');

INSERT INTO trimmy.idempotency_records (id, user_id, operation, idempotency_key, request_hash, expires_at) VALUES
  ('70000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001', 'transfer', 'request-one', repeat('a', 64), now() + interval '1 day'),
  ('70000000-0000-4000-8000-000000000002', '10000000-0000-4000-8000-000000000001', 'swap', 'request-two', repeat('b', 64), now() + interval '1 day');
SELECT pg_temp.expect_failure('duplicate idempotency scope cannot create another command', $sql$
  INSERT INTO trimmy.idempotency_records (user_id, operation, idempotency_key, request_hash, expires_at)
  VALUES ('10000000-0000-4000-8000-000000000001', 'transfer', 'request-one', repeat('c', 64), now() + interval '1 day')$sql$, '23505');
SELECT pg_temp.expect_failure('idempotency request cannot change behind an existing key', $sql$
  UPDATE trimmy.idempotency_records SET request_hash = repeat('f', 64) WHERE idempotency_key = 'request-one'$sql$, '23514');

INSERT INTO trimmy.financial_intents (id, user_id, idempotency_record_id, operation, input_asset_id,
  input_amount_raw, source_wallet_id, destination_address, expires_at) VALUES
  ('80000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001',
    '70000000-0000-4000-8000-000000000001', 'transfer', '40000000-0000-4000-8000-000000000001',
    1000, '30000000-0000-4000-8000-000000000001', repeat('2', 32), now() + interval '1 hour');
SELECT pg_temp.expect_failure('cross-network swap cannot be recorded as same-chain intent', $sql$
  INSERT INTO trimmy.financial_intents (user_id, idempotency_record_id, operation, input_asset_id, output_asset_id,
    input_amount_raw, minimum_output_raw, source_wallet_id, destination_address, quote_reference, quote_expires_at, expires_at)
  VALUES ('10000000-0000-4000-8000-000000000001', '70000000-0000-4000-8000-000000000002', 'swap',
    '40000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000003', 1000, 900,
    '30000000-0000-4000-8000-000000000001', repeat('2', 32), 'fixture', now() + interval '1 minute', now() + interval '1 hour')$sql$, '23514');
SELECT pg_temp.expect_failure('intent cannot jump directly to settled', $sql$
  UPDATE trimmy.financial_intents SET state = 'confirmed', version = version + 1$sql$, '23514');
SELECT pg_temp.expect_failure('foundation refuses live financial operations', $sql$
  UPDATE trimmy.financial_intents SET execution_mode = 'live', version = version + 1$sql$, '23514');
UPDATE trimmy.financial_intents SET state = 'awaiting_authorization', version = version + 1;
UPDATE trimmy.financial_intents SET state = 'authorized', version = version + 1;
SELECT pg_temp.expect_failure('authorized amount cannot be changed', $sql$
  UPDATE trimmy.financial_intents SET input_amount_raw = 9999, version = version + 1$sql$, '23514');

INSERT INTO trimmy.execution_attempts (id, intent_id, attempt_number, network, transaction_message_hash)
VALUES ('90000000-0000-4000-8000-000000000001', '80000000-0000-4000-8000-000000000001', 1, 'devnet', repeat('a', 64));
SELECT pg_temp.expect_failure('unresolved execution cannot be duplicated', $sql$
  INSERT INTO trimmy.execution_attempts (intent_id, attempt_number, network, transaction_message_hash)
  VALUES ('80000000-0000-4000-8000-000000000001', 2, 'devnet', repeat('b', 64))$sql$, '23505');
SELECT pg_temp.expect_failure('submitted execution needs actual signature', $sql$
  UPDATE trimmy.execution_attempts SET state = 'submitted', submitted_at = now()$sql$, '23514');
UPDATE trimmy.execution_attempts SET state = 'submitted', transaction_signature = repeat('3', 88), submitted_at = now();
SELECT pg_temp.expect_failure('signature cannot be substituted after broadcast', $sql$
  UPDATE trimmy.execution_attempts SET transaction_signature = repeat('4', 88)$sql$, '23514');
UPDATE trimmy.execution_attempts SET state = 'finalized', observed_slot = 42, settled_at = clock_timestamp();
SELECT pg_temp.expect_failure('finalized intent cannot be broadcast again', $sql$
  INSERT INTO trimmy.execution_attempts (intent_id, attempt_number, network, transaction_message_hash)
  VALUES ('80000000-0000-4000-8000-000000000001', 2, 'devnet', repeat('b', 64))$sql$, '23514');

INSERT INTO trimmy.inbox_events (provider, provider_event_id, payload_hash, payload)
VALUES ('test-provider', 'event-one', repeat('d', 64), '{}');
SELECT pg_temp.expect_failure('duplicate provider delivery deduplicates', $sql$
  INSERT INTO trimmy.inbox_events (provider, provider_event_id, payload_hash, payload)
  VALUES ('test-provider', 'event-one', repeat('d', 64), '{}')$sql$, '23505');
SELECT pg_temp.expect_failure('unverified webhook cannot start processing', $sql$
  UPDATE trimmy.inbox_events SET state = 'processing'$sql$, '23514');
INSERT INTO trimmy.outbox_events (topic, deduplication_key, aggregate_type, aggregate_id, payload)
VALUES ('invitation.offered', 'test-one', 'invitation', '50000000-0000-4000-8000-000000000001', '{}');
SELECT pg_temp.expect_failure('outbox processing needs a bounded lease', $sql$
  UPDATE trimmy.outbox_events SET state = 'processing'$sql$, '23514');
SELECT pg_temp.expect_failure('outbox event deduplicates at transaction boundary', $sql$
  INSERT INTO trimmy.outbox_events (topic, deduplication_key, aggregate_type, aggregate_id, payload)
  VALUES ('invitation.offered', 'test-one', 'invitation', '50000000-0000-4000-8000-000000000001', '{}')$sql$, '23505');

SAVEPOINT transactional_outbox;
INSERT INTO trimmy.outbox_events (topic, deduplication_key, aggregate_type, aggregate_id, payload)
VALUES ('test.rollback', 'rollback-me', 'intent', '80000000-0000-4000-8000-000000000001', '{}');
ROLLBACK TO SAVEPOINT transactional_outbox;
SELECT pg_temp.assert_true('rolled-back work leaves no published intent',
  NOT EXISTS (SELECT 1 FROM trimmy.outbox_events WHERE deduplication_key = 'rollback-me'));
SELECT pg_temp.assert_true('business changes generated audit evidence',
  (SELECT count(*) FROM trimmy.audit_events WHERE entity_type = 'invitations'
    AND entity_id = '50000000-0000-4000-8000-000000000001') = 4);
SELECT pg_temp.expect_failure('audit cannot be rewritten', $sql$UPDATE trimmy.audit_events SET action = 'hidden'$sql$, '23514');
SELECT pg_temp.expect_failure('audit cannot be deleted', $sql$DELETE FROM trimmy.audit_events$sql$, '23514');
SELECT pg_temp.assert_true('all application tables have RLS enabled',
  NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'trimmy' AND c.relkind = 'r' AND NOT c.relrowsecurity));
SELECT pg_temp.assert_true('no public schema privilege',
  NOT EXISTS (SELECT 1 FROM pg_namespace n, LATERAL aclexplode(n.nspacl) a
    WHERE n.nspname = 'trimmy' AND a.grantee = 0));
SELECT pg_temp.assert_true('no public table privilege',
  NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace,
    LATERAL aclexplode(c.relacl) a WHERE n.nspname = 'trimmy' AND a.grantee = 0));
SELECT pg_temp.assert_true('no public function execution',
  NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
    LATERAL aclexplode(p.proacl) a WHERE n.nspname = 'trimmy' AND a.grantee = 0));

CREATE ROLE trimmy_constraint_test_client NOLOGIN;
GRANT USAGE ON SCHEMA trimmy TO trimmy_constraint_test_client;
GRANT SELECT, INSERT ON trimmy.users TO trimmy_constraint_test_client;
SET LOCAL ROLE trimmy_constraint_test_client;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM trimmy.users) THEN RAISE EXCEPTION 'RLS exposed users'; END IF;
  BEGIN
    INSERT INTO trimmy.users DEFAULT VALUES;
  EXCEPTION WHEN insufficient_privilege THEN RETURN;
  END;
  RAISE EXCEPTION 'RLS permitted unauthorized insertion';
END;
$$;
RESET ROLE;
SELECT pg_temp.assert_true('RLS denies rows and writes even after explicit table grant', true);
SELECT count(*) AS passed_checks FROM checks;
ROLLBACK;
