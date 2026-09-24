-- Private integration cluster only; all test data/helpers roll back.
BEGIN;
CREATE TEMP TABLE review_checks(label text PRIMARY KEY);
GRANT SELECT, INSERT ON pg_temp.review_checks TO trimmy_practice_test_app;
CREATE FUNCTION pg_temp.review_ok(condition boolean, label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF condition IS NOT TRUE THEN RAISE EXCEPTION 'Wallet/review SQL check failed: %', label; END IF;
  INSERT INTO pg_temp.review_checks VALUES(label);
END;
$$;
CREATE FUNCTION pg_temp.review_fails(statement text, expected_state text, label text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE observed_state text;
BEGIN
  BEGIN EXECUTE statement;
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS observed_state = RETURNED_SQLSTATE;
  END;
  PERFORM pg_temp.review_ok(observed_state = expected_state, label);
END;
$$;
CREATE FUNCTION pg_temp.review_intent(message_hash text, tx_hash text, terms_hash text, digest text, taker text,
  signing text DEFAULT 'false', approval text DEFAULT 'required') RETURNS jsonb
LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_object('kind', 'reviewed_stock_order_intent', 'transactionMessageHash', message_hash,
    'transactionHash', tx_hash, 'candidateTermsHash', terms_hash, 'reviewDigestSha256', digest, 'taker', taker,
    'assessment', jsonb_build_object('signingEnabled', signing::boolean, 'broadcastEnabled', false),
    'approval', jsonb_build_object('status', approval))
$$;
GRANT EXECUTE ON FUNCTION pg_temp.review_ok(boolean,text), pg_temp.review_fails(text,text,text),
  pg_temp.review_intent(text,text,text,text,text,text,text) TO trimmy_practice_test_app;
INSERT INTO trimmy.users(id,status) VALUES
  ('7b000000-0000-4000-a000-000000000001','active'),
  ('7b000000-0000-4000-a000-000000000002','active'),
  ('7b000000-0000-4000-a000-000000000003','restricted');

SELECT pg_temp.review_ok(EXISTS(SELECT 1 FROM trimmy.schema_migrations WHERE version = '0007_wallet_possession_and_reviews'),
  'Migration 0007 is recorded');
SELECT pg_temp.review_ok(
  (SELECT count(*) = 2 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'trimmy' AND c.relname IN ('wallet_bindings','stock_order_reviews')
      AND c.relrowsecurity AND c.relforcerowsecurity),
  'Wallet bindings and reviews force RLS');

SET LOCAL ROLE trimmy_practice_test_app;
SELECT set_config('trimmy.practice_user_id','',true);
SELECT pg_temp.review_ok((SELECT count(*) = 0 FROM trimmy.wallet_bindings), 'No context reads no bindings');
SELECT pg_temp.review_ok((SELECT count(*) = 0 FROM trimmy.stock_order_reviews), 'No context reads no reviews');
SELECT pg_temp.review_fails(
  $q$INSERT INTO trimmy.wallet_bindings(user_id,network,address,verified_at) VALUES ('7b000000-0000-4000-a000-000000000001','mainnet-beta','9fYLFVrvqkGdNjJn6KW6Mpqz3XtHvUjcAbKRq8PoqYqC',now())$q$,
  '42501','No context cannot record a binding');
SELECT pg_temp.review_ok(
  NOT has_table_privilege(current_user,'trimmy.financial_intents','SELECT,INSERT,UPDATE,DELETE')
  AND NOT has_table_privilege(current_user,'trimmy.execution_attempts','SELECT,INSERT,UPDATE,DELETE')
  AND NOT has_table_privilege(current_user,'trimmy.wallet_bindings','UPDATE,DELETE')
  AND NOT has_table_privilege(current_user,'trimmy.stock_order_reviews','DELETE')
  AND NOT has_table_privilege(current_user,'trimmy.audit_events','SELECT,INSERT,UPDATE,DELETE')
  AND NOT has_table_privilege(current_user,'trimmy.users','SELECT'),
  'App role has no financial, binding-update, review-delete, audit or user grants');

-- Account one records a binding; account two cannot see or reuse it.
SELECT set_config('trimmy.practice_user_id','7b000000-0000-4000-a000-000000000001',true);
INSERT INTO trimmy.wallet_bindings(id,user_id,network,address,provider_wallet_id,verified_at)
  VALUES ('7b100000-0000-4000-a000-000000000001','7b000000-0000-4000-a000-000000000001','mainnet-beta','9fYLFVrvqkGdNjJn6KW6Mpqz3XtHvUjcAbKRq8PoqYqC','wallet-a',now());
SELECT pg_temp.review_ok((SELECT count(*) = 1 FROM trimmy.wallet_bindings), 'Owner reads own binding');
SELECT pg_temp.review_fails(
  $q$INSERT INTO trimmy.wallet_bindings(user_id,network,address,verified_at) VALUES ('7b000000-0000-4000-a000-000000000002','mainnet-beta','5DMGH4bkaN4ZYBHrF7DVaNo3bkp5QagP1tfVUjPu7UAY',now())$q$,
  '42501','Context cannot bind a wallet for another account');
SELECT pg_temp.review_fails(
  $q$INSERT INTO trimmy.wallet_bindings(user_id,network,address,verified_at,revoked_at) VALUES ('7b000000-0000-4000-a000-000000000001','mainnet-beta','5DMGH4bkaN4ZYBHrF7DVaNo3bkp5QagP1tfVUjPu7UAY',now(),now())$q$,
  '23514','A binding cannot start revoked');
SELECT pg_temp.review_fails(
  $q$INSERT INTO trimmy.wallet_bindings(user_id,network,address,verified_at) VALUES ('7b000000-0000-4000-a000-000000000001','mainnet-beta','5DMGH4bkaN4ZYBHrF7DVaNo3bkp5QagP1tfVUjPu7UAY',now() + interval '1 hour')$q$,
  '23514','A binding cannot be verified in the future');
SELECT set_config('trimmy.practice_user_id','7b000000-0000-4000-a000-000000000002',true);
SELECT pg_temp.review_ok((SELECT count(*) = 0 FROM trimmy.wallet_bindings), 'Another account sees no bindings');
SELECT pg_temp.review_fails(
  $q$INSERT INTO trimmy.wallet_bindings(user_id,network,address,verified_at) VALUES ('7b000000-0000-4000-a000-000000000002','mainnet-beta','9fYLFVrvqkGdNjJn6KW6Mpqz3XtHvUjcAbKRq8PoqYqC',now())$q$,
  '23505','The same address cannot bind to a second account');
SELECT set_config('trimmy.practice_user_id','7b000000-0000-4000-a000-000000000003',true);
SELECT pg_temp.review_fails(
  $q$INSERT INTO trimmy.wallet_bindings(user_id,network,address,verified_at) VALUES ('7b000000-0000-4000-a000-000000000003','mainnet-beta','6niM1u9GwNKLrcR2ZWiSMfk9KB2La6UkscrvF4bax7LX',now())$q$,
  '23514','A restricted account cannot bind a wallet');

-- Reviews: insertion rules.
SELECT set_config('trimmy.practice_user_id','7b000000-0000-4000-a000-000000000001',true);
INSERT INTO trimmy.stock_order_reviews(id,user_id,taker,network,request_id,transaction_message_hash,transaction_hash,candidate_terms_hash,review_digest,intent,unsigned_transaction,reviewed_at,expires_at)
  VALUES ('7b200000-0000-4000-a000-000000000001','7b000000-0000-4000-a000-000000000001','9fYLFVrvqkGdNjJn6KW6Mpqz3XtHvUjcAbKRq8PoqYqC','mainnet-beta','order-1',
    repeat('a',64),repeat('b',64),repeat('c',64),repeat('d',64),
    pg_temp.review_intent(repeat('a',64),repeat('b',64),repeat('c',64),repeat('d',64),'9fYLFVrvqkGdNjJn6KW6Mpqz3XtHvUjcAbKRq8PoqYqC'),
    decode(repeat('00',100),'hex'),'2026-09-15T08:00:00Z','2026-09-15T08:00:45Z');
SELECT pg_temp.review_ok((SELECT state = 'reviewed' AND version = 0 AND approved_at IS NULL AND wallet_binding_id IS NULL
  FROM trimmy.stock_order_reviews WHERE id = '7b200000-0000-4000-a000-000000000001'), 'A review starts reviewed at version zero');
SELECT pg_temp.review_fails(
  $q$INSERT INTO trimmy.stock_order_reviews(user_id,taker,network,request_id,transaction_message_hash,transaction_hash,candidate_terms_hash,review_digest,intent,unsigned_transaction,reviewed_at,expires_at)
    VALUES ('7b000000-0000-4000-a000-000000000001','9fYLFVrvqkGdNjJn6KW6Mpqz3XtHvUjcAbKRq8PoqYqC','mainnet-beta','order-2',repeat('a',64),repeat('b',64),repeat('c',64),repeat('d',64),
      pg_temp.review_intent(repeat('a',64),repeat('b',64),repeat('c',64),repeat('d',64),'9fYLFVrvqkGdNjJn6KW6Mpqz3XtHvUjcAbKRq8PoqYqC'),decode(repeat('00',100),'hex'),'2026-09-15T08:00:00Z','2026-09-15T08:00:45Z')$q$,
  '23505','One review per account and message');
SELECT pg_temp.review_fails(
  $q$INSERT INTO trimmy.stock_order_reviews(user_id,taker,network,request_id,transaction_message_hash,transaction_hash,candidate_terms_hash,review_digest,intent,unsigned_transaction,reviewed_at,expires_at)
    VALUES ('7b000000-0000-4000-a000-000000000001','9fYLFVrvqkGdNjJn6KW6Mpqz3XtHvUjcAbKRq8PoqYqC','mainnet-beta','order-3',repeat('e',64),repeat('b',64),repeat('c',64),repeat('d',64),
      pg_temp.review_intent(repeat('a',64),repeat('b',64),repeat('c',64),repeat('d',64),'9fYLFVrvqkGdNjJn6KW6Mpqz3XtHvUjcAbKRq8PoqYqC'),decode(repeat('00',100),'hex'),'2026-09-15T08:00:00Z','2026-09-15T08:00:45Z')$q$,
  '23514','Intent hashes must match the row');
SELECT pg_temp.review_fails(
  $q$INSERT INTO trimmy.stock_order_reviews(user_id,taker,network,request_id,transaction_message_hash,transaction_hash,candidate_terms_hash,review_digest,intent,unsigned_transaction,reviewed_at,expires_at)
    VALUES ('7b000000-0000-4000-a000-000000000001','9fYLFVrvqkGdNjJn6KW6Mpqz3XtHvUjcAbKRq8PoqYqC','mainnet-beta','order-4',repeat('f',64),repeat('b',64),repeat('c',64),repeat('d',64),
      pg_temp.review_intent(repeat('f',64),repeat('b',64),repeat('c',64),repeat('d',64),'9fYLFVrvqkGdNjJn6KW6Mpqz3XtHvUjcAbKRq8PoqYqC','true'),decode(repeat('00',100),'hex'),'2026-09-15T08:00:00Z','2026-09-15T08:00:45Z')$q$,
  '23514','An intent claiming signing is rejected');
SELECT pg_temp.review_fails(
  $q$INSERT INTO trimmy.stock_order_reviews(user_id,taker,network,request_id,transaction_message_hash,transaction_hash,candidate_terms_hash,review_digest,intent,unsigned_transaction,reviewed_at,expires_at)
    VALUES ('7b000000-0000-4000-a000-000000000001','9fYLFVrvqkGdNjJn6KW6Mpqz3XtHvUjcAbKRq8PoqYqC','mainnet-beta','order-5',repeat('1',64),repeat('b',64),repeat('c',64),repeat('d',64),
      pg_temp.review_intent(repeat('1',64),repeat('b',64),repeat('c',64),repeat('d',64),'9fYLFVrvqkGdNjJn6KW6Mpqz3XtHvUjcAbKRq8PoqYqC') || '{"unsignedTransaction":"AA=="}',decode(repeat('00',100),'hex'),'2026-09-15T08:00:00Z','2026-09-15T08:00:45Z')$q$,
  '23514','Raw bytes may not be smuggled into the intent');
SELECT pg_temp.review_fails(
  $q$INSERT INTO trimmy.stock_order_reviews(user_id,taker,network,request_id,transaction_message_hash,transaction_hash,candidate_terms_hash,review_digest,intent,unsigned_transaction,reviewed_at,expires_at)
    VALUES ('7b000000-0000-4000-a000-000000000001','9fYLFVrvqkGdNjJn6KW6Mpqz3XtHvUjcAbKRq8PoqYqC','mainnet-beta','order-6',repeat('2',64),repeat('b',64),repeat('c',64),repeat('d',64),
      pg_temp.review_intent(repeat('2',64),repeat('b',64),repeat('c',64),repeat('d',64),'9fYLFVrvqkGdNjJn6KW6Mpqz3XtHvUjcAbKRq8PoqYqC'),decode(repeat('00',10),'hex'),'2026-09-15T08:00:00Z','2026-09-15T08:00:45Z')$q$,
  '23514','Unsigned bytes must be a plausible transaction size');
SELECT pg_temp.review_fails(
  $q$INSERT INTO trimmy.stock_order_reviews(user_id,taker,network,request_id,transaction_message_hash,transaction_hash,candidate_terms_hash,review_digest,intent,unsigned_transaction,reviewed_at,expires_at,state)
    VALUES ('7b000000-0000-4000-a000-000000000001','9fYLFVrvqkGdNjJn6KW6Mpqz3XtHvUjcAbKRq8PoqYqC','mainnet-beta','order-7',repeat('3',64),repeat('b',64),repeat('c',64),repeat('d',64),
      pg_temp.review_intent(repeat('3',64),repeat('b',64),repeat('c',64),repeat('d',64),'9fYLFVrvqkGdNjJn6KW6Mpqz3XtHvUjcAbKRq8PoqYqC'),decode(repeat('00',100),'hex'),'2026-09-15T08:00:00Z','2026-09-15T08:00:45Z','approved')$q$,
  '23514','A review cannot be inserted already approved');

-- Reviews: update rules.
SELECT pg_temp.review_fails(
  $q$UPDATE trimmy.stock_order_reviews SET taker = '5DMGH4bkaN4ZYBHrF7DVaNo3bkp5QagP1tfVUjPu7UAY', version = 1, state = 'canceled' WHERE id = '7b200000-0000-4000-a000-000000000001'$q$,
  '23514','Reviewed terms are immutable');
SELECT pg_temp.review_fails(
  $q$UPDATE trimmy.stock_order_reviews SET state = 'canceled', version = 2 WHERE id = '7b200000-0000-4000-a000-000000000001'$q$,
  '23514','Version must advance by exactly one');
SELECT pg_temp.review_fails(
  $q$UPDATE trimmy.stock_order_reviews SET state = 'approved', version = 1, approved_at = '2026-09-15T08:00:10Z' WHERE id = '7b200000-0000-4000-a000-000000000001'$q$,
  '23514','Approval without a wallet binding is rejected');
SELECT pg_temp.review_fails(
  $q$UPDATE trimmy.stock_order_reviews SET state = 'approved', version = 1, approved_at = '2026-09-15T08:00:50Z', wallet_binding_id = '7b100000-0000-4000-a000-000000000001' WHERE id = '7b200000-0000-4000-a000-000000000001'$q$,
  '23514','Approval after expiry is rejected');
SELECT pg_temp.review_fails(
  $q$UPDATE trimmy.stock_order_reviews SET state = 'consumed', version = 1 WHERE id = '7b200000-0000-4000-a000-000000000001'$q$,
  '23514','A review cannot be consumed before approval');
UPDATE trimmy.stock_order_reviews SET state = 'approved', version = 1, approved_at = '2026-09-15T08:00:10Z',
  wallet_binding_id = '7b100000-0000-4000-a000-000000000001' WHERE id = '7b200000-0000-4000-a000-000000000001';
SELECT pg_temp.review_ok((SELECT state = 'approved' AND version = 1 AND wallet_binding_id = '7b100000-0000-4000-a000-000000000001'
  FROM trimmy.stock_order_reviews WHERE id = '7b200000-0000-4000-a000-000000000001'), 'Approval attaches the taker binding inside the window');
SELECT pg_temp.review_fails(
  $q$UPDATE trimmy.stock_order_reviews SET state = 'reviewed', version = 2 WHERE id = '7b200000-0000-4000-a000-000000000001'$q$,
  '23514','Approval cannot be undone');
UPDATE trimmy.stock_order_reviews SET state = 'consumed', version = 2 WHERE id = '7b200000-0000-4000-a000-000000000001';
SELECT pg_temp.review_fails(
  $q$UPDATE trimmy.stock_order_reviews SET state = 'canceled', version = 3 WHERE id = '7b200000-0000-4000-a000-000000000001'$q$,
  '23514','A consumed review is terminal');
SELECT pg_temp.review_fails(
  $q$DELETE FROM trimmy.stock_order_reviews WHERE id = '7b200000-0000-4000-a000-000000000001'$q$,
  '42501','App role cannot delete reviews');
SELECT set_config('trimmy.practice_user_id','7b000000-0000-4000-a000-000000000002',true);
SELECT pg_temp.review_ok((SELECT count(*) = 0 FROM trimmy.stock_order_reviews), 'Another account sees no reviews');

RESET ROLE;
SELECT pg_temp.review_ok(
  (SELECT count(*) = 1 FROM trimmy.audit_events
    WHERE entity_type = 'wallet_bindings' AND action = 'insert'
      AND entity_id = '7b100000-0000-4000-a000-000000000001'),
  'A binding the app role recorded left exactly one audit row it cannot write itself');
SELECT pg_temp.review_ok(
  (SELECT count(*) = 3 FROM trimmy.audit_events
    WHERE entity_type = 'stock_order_reviews' AND entity_id = '7b200000-0000-4000-a000-000000000001'),
  'The review insert, approval and consumption are all audited');
SELECT pg_temp.review_fails(
  $q$DELETE FROM trimmy.stock_order_reviews WHERE id = '7b200000-0000-4000-a000-000000000001'$q$,
  '23514','Even the owner cannot delete a review');
SELECT count(*) AS wallet_review_checks_passed FROM pg_temp.review_checks;
ROLLBACK;
