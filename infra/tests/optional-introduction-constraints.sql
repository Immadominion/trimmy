\set ON_ERROR_STOP on
BEGIN;

CREATE FUNCTION public.optional_intro_test_buy(
  selected_user uuid,
  selected_asset text,
  selected_mint text,
  selected_committed_at timestamptz
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE account_row trimmy.paper_accounts%ROWTYPE;
DECLARE position_row trimmy.paper_positions%ROWTYPE;
DECLARE preview_id uuid := gen_random_uuid();
DECLARE order_id uuid := gen_random_uuid();
DECLARE accepted_at timestamptz := selected_committed_at - interval '1 millisecond';
DECLARE before_quantity numeric := 0;
DECLARE before_basis numeric := 0;
DECLARE before_realized numeric := 0;
DECLARE before_locked numeric := 0;
DECLARE quantity numeric := 1000000;
DECLARE debit numeric := 1000000;
DECLARE after_cash numeric;
DECLARE next_revision bigint;
DECLARE source jsonb;
DECLARE selected_symbol text := upper(left(selected_asset, 20)) || 'x';
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.paper:' || selected_user::text, 0));
  SELECT a.* INTO account_row FROM trimmy.paper_accounts a
    WHERE a.user_id = selected_user FOR UPDATE;
  IF NOT FOUND THEN
    INSERT INTO trimmy.paper_accounts(user_id, opened_at, updated_at)
    VALUES (selected_user, selected_committed_at - interval '10 seconds',
      selected_committed_at - interval '10 seconds');
    INSERT INTO trimmy.paper_cash_ledger(
      user_id, account_revision, order_id, reset_mutation_id, entry_kind,
      delta_micros, balance_after_micros, created_at)
    VALUES (selected_user, 0, NULL, NULL, 'initial', 10000000000,
      10000000000, selected_committed_at - interval '10 seconds');
    SELECT a.* INTO STRICT account_row FROM trimmy.paper_accounts a
      WHERE a.user_id = selected_user FOR UPDATE;
  END IF;
  IF selected_committed_at <= account_row.updated_at THEN
    RAISE EXCEPTION 'Paper reset fixture time must move forwards';
  END IF;
  SELECT p.* INTO position_row FROM trimmy.paper_positions p
  WHERE p.user_id = selected_user AND p.asset_id = selected_asset
    AND p.variant_mint = selected_mint
    AND p.last_order_revision > account_row.last_reset_revision;
  IF FOUND THEN
    before_quantity := position_row.quantity_micros;
    before_basis := position_row.cost_basis_micros;
    before_realized := position_row.realized_gain_micros;
    before_locked := position_row.locked_gain_micros;
  END IF;
  next_revision := account_row.revision + 1;
  after_cash := account_row.cash_micros - debit;
  source := jsonb_build_object(
    'provider', 'tokens-xyz-v1',
    'providerReference', '/v1/assets/' || selected_asset || '/variants#reset-fixture',
    'marketSource', 'integration-fixture', 'metricsSource', NULL,
    'providerTimestamps', jsonb_build_object('asOf', NULL,
      'lastFetchedAt', NULL, 'lastTradeAt', NULL, 'unit', 'not_declared'),
    'observedAt', accepted_at, 'acceptedAt', accepted_at);
  INSERT INTO trimmy.paper_order_previews(
    id, user_id, request_id, request_hash, account_revision, action, input_kind,
    input_amount_micros, asset_id, variant_mint, symbol, price_micros,
    quantity_micros, cash_debit_micros, cash_credit_micros, cash_after_micros,
    position_quantity_after_micros, position_cost_basis_after_micros,
    realized_gain_delta_micros, locked_gain_delta_micros, price_source,
    accepted_at, expires_at, created_at)
  VALUES (preview_id, selected_user, gen_random_uuid(), repeat('a', 64),
    account_row.revision, 'buy', 'paper_amount', debit, selected_asset,
    selected_mint, selected_symbol, 1000000, quantity, debit, 0, after_cash,
    before_quantity + quantity, before_basis + debit, 0, 0, source,
    accepted_at, selected_committed_at + interval '20 seconds', accepted_at);
  INSERT INTO trimmy.paper_orders(
    id, user_id, preview_id, idempotency_key, request_hash, account_revision,
    action, asset_id, variant_mint, symbol, price_micros, quantity_micros,
    cash_debit_micros, cash_credit_micros, cash_before_micros, cash_after_micros,
    position_quantity_before_micros, position_quantity_after_micros,
    position_cost_basis_before_micros, position_cost_basis_after_micros,
    realized_gain_before_micros, realized_gain_delta_micros,
    realized_gain_after_micros, locked_gain_before_micros,
    locked_gain_delta_micros, locked_gain_after_micros, price_source, committed_at)
  VALUES (order_id, selected_user, preview_id, gen_random_uuid(), repeat('b', 64),
    next_revision, 'buy', selected_asset, selected_mint, selected_symbol,
    1000000, quantity, debit, 0, account_row.cash_micros, after_cash,
    before_quantity, before_quantity + quantity, before_basis,
    before_basis + debit, before_realized, 0, before_realized,
    before_locked, 0, before_locked, source, selected_committed_at);
  UPDATE trimmy.paper_accounts SET cash_micros = after_cash,
    revision = next_revision, updated_at = selected_committed_at
  WHERE user_id = selected_user;
  INSERT INTO trimmy.paper_positions(
    user_id, asset_id, variant_mint, symbol, quantity_micros,
    cost_basis_micros, realized_gain_micros, locked_gain_micros,
    last_order_revision, updated_at)
  VALUES (selected_user, selected_asset, selected_mint, selected_symbol,
    before_quantity + quantity, before_basis + debit, before_realized,
    before_locked, next_revision, selected_committed_at)
  ON CONFLICT (user_id, asset_id, variant_mint) DO UPDATE SET
    symbol = EXCLUDED.symbol, quantity_micros = EXCLUDED.quantity_micros,
    cost_basis_micros = EXCLUDED.cost_basis_micros,
    realized_gain_micros = EXCLUDED.realized_gain_micros,
    locked_gain_micros = EXCLUDED.locked_gain_micros,
    last_order_revision = EXCLUDED.last_order_revision,
    updated_at = EXCLUDED.updated_at;
  INSERT INTO trimmy.paper_cash_ledger(
    user_id, account_revision, order_id, reset_mutation_id, entry_kind,
    delta_micros, balance_after_micros, created_at)
  VALUES (selected_user, next_revision, order_id, NULL, 'buy', -debit,
    after_cash, selected_committed_at);
  UPDATE trimmy.paper_order_previews SET state = 'committed',
    committed_at = selected_committed_at WHERE id = preview_id;
  RETURN order_id;
END;
$$;
REVOKE ALL ON FUNCTION public.optional_intro_test_buy(
  uuid, text, text, timestamptz) FROM PUBLIC;

INSERT INTO trimmy.users(id) VALUES
  ('92600000-0000-4000-8000-000000000001'),
  ('92600000-0000-4000-8000-000000000002'),
  ('92600000-0000-4000-8000-000000000003'),
  ('92600000-0000-4000-8000-000000000004');
INSERT INTO trimmy.practice_auth_identities(app_id, subject, user_id) VALUES
  ('intro-test', 'did:privy:intro2', '92600000-0000-4000-8000-000000000002'),
  ('intro-test', 'did:privy:intro3', '92600000-0000-4000-8000-000000000003'),
  ('intro-test', 'did:privy:intro4', '92600000-0000-4000-8000-000000000004');
INSERT INTO trimmy.guest_sessions(
  id, user_id, credential_hash, created_at, expires_at, hard_expires_at, last_seen_at)
VALUES ('92600000-0000-4000-8000-000000000099',
  '92600000-0000-4000-8000-000000000001', repeat('d',64),
  statement_timestamp() - interval '1 hour', statement_timestamp() + interval '1 day',
  statement_timestamp() - interval '1 hour' + interval '90 days', statement_timestamp());

DO $$
DECLARE result_row record; original_row record;
BEGIN
  SELECT * INTO original_row FROM trimmy.product_profile_put(
    '92600000-0000-4000-8000-000000000001',
    '92600000-0000-4000-8000-000000000101', repeat('1',64), 0,
    NULL,NULL,NULL,NULL,NULL,'first-trade');
  IF original_row.outcome <> 'saved' OR original_row.revision <> 1
      OR original_row.goal IS NOT NULL OR original_row.handle IS NOT NULL THEN
    RAISE EXCEPTION 'All-null initial profile was not saved: %', original_row;
  END IF;
  SELECT * INTO result_row FROM trimmy.product_profile_put(
    '92600000-0000-4000-8000-000000000001',
    '92600000-0000-4000-8000-000000000101', repeat('1',64), 0,
    NULL,NULL,NULL,NULL,NULL,'first-trade');
  IF result_row IS DISTINCT FROM original_row THEN
    RAISE EXCEPTION 'Nullable profile retry changed its durable receipt';
  END IF;
  SELECT * INTO result_row FROM trimmy.product_profile_put(
    '92600000-0000-4000-8000-000000000001',
    '92600000-0000-4000-8000-000000000102', repeat('2',64), 1,
    NULL,NULL,NULL,NULL,NULL,'app');
  IF result_row.outcome <> 'checkpoint_conflict' THEN
    RAISE EXCEPTION 'Ordinary profile PUT advanced the introduction: %', result_row;
  END IF;
  SELECT * INTO result_row FROM trimmy.product_launch_advance(
    '92600000-0000-4000-8000-000000000001',
    '92600000-0000-4000-8000-000000000103', repeat('3',64), 1,
    'introduction-completed', '92600000-0000-4000-8000-000000000099');
  IF result_row.outcome <> 'evidence_required' THEN
    RAISE EXCEPTION 'Completion fabricated a confirmed buy: %', result_row;
  END IF;
  SELECT * INTO original_row FROM trimmy.product_launch_advance(
    '92600000-0000-4000-8000-000000000001',
    '92600000-0000-4000-8000-000000000104', repeat('4',64), 1,
    'introduction-skipped', '92600000-0000-4000-8000-000000000099');
  IF original_row.outcome <> 'saved' OR original_row.revision <> 2
      OR original_row.launch_checkpoint <> 'app' THEN
    RAISE EXCEPTION 'Guest skip did not reach app: %', original_row;
  END IF;
  SELECT * INTO result_row FROM trimmy.product_launch_advance(
    '92600000-0000-4000-8000-000000000001',
    '92600000-0000-4000-8000-000000000104', repeat('4',64), 1,
    'introduction-skipped', '92600000-0000-4000-8000-000000000099');
  IF result_row IS DISTINCT FROM original_row THEN
    RAISE EXCEPTION 'Guest skip retry changed its durable receipt';
  END IF;
  IF EXISTS (SELECT 1 FROM trimmy.paper_orders WHERE user_id='92600000-0000-4000-8000-000000000001')
      OR EXISTS (SELECT 1 FROM trimmy.paper_positions WHERE user_id='92600000-0000-4000-8000-000000000001')
      OR EXISTS (SELECT 1 FROM trimmy.career_starts WHERE user_id='92600000-0000-4000-8000-000000000001')
      OR EXISTS (SELECT 1 FROM trimmy.career_trim_ledger WHERE user_id='92600000-0000-4000-8000-000000000001')
      OR trimmy.product_profile_has_confirmed_paper_trade('92600000-0000-4000-8000-000000000001') THEN
    RAISE EXCEPTION 'Skipped introduction created trading or Career evidence';
  END IF;
END $$;

-- A second absent handle is valid, but real chosen handles remain unique.
DO $$
DECLARE result_row record;
BEGIN
  SELECT * INTO result_row FROM trimmy.product_profile_put(
    '92600000-0000-4000-8000-000000000002',
    '92600000-0000-4000-8000-000000000201', repeat('5',64), 0,
    NULL,NULL,NULL,NULL,NULL,'first-trade');
  IF result_row.outcome <> 'saved' THEN
    RAISE EXCEPTION 'Second null handle collided: %', result_row;
  END IF;
  SELECT * INTO result_row FROM trimmy.product_profile_put(
    '92600000-0000-4000-8000-000000000003',
    '92600000-0000-4000-8000-000000000301', repeat('6',64), 0,
    'learn','basics','oracle','one-mission','intro_legacy','first-trade');
  IF result_row.outcome <> 'saved' OR result_row.handle <> 'intro_legacy' THEN
    RAISE EXCEPTION 'Legacy full profile no longer saves: %', result_row;
  END IF;
  SELECT * INTO result_row FROM trimmy.product_profile_put(
    '92600000-0000-4000-8000-000000000004',
    '92600000-0000-4000-8000-000000000401', repeat('7',64), 0,
    NULL,NULL,NULL,NULL,'intro_legacy','first-trade');
  IF result_row.outcome <> 'handle_taken' THEN
    RAISE EXCEPTION 'Optional profile bypassed handle uniqueness: %', result_row;
  END IF;
  SELECT * INTO result_row FROM trimmy.product_profile_put(
    '92600000-0000-4000-8000-000000000004',
    '92600000-0000-4000-8000-000000000402', repeat('8',64), 0,
    NULL,NULL,'invalid-persona',NULL,NULL,'first-trade');
  IF result_row.outcome <> 'invalid' THEN
    RAISE EXCEPTION 'Optional profile accepted an invalid non-null choice: %', result_row;
  END IF;
END $$;

-- Use the actual preview/order/account/position transaction to create immutable
-- first-buy evidence. No fixture writes the Career evidence table directly.
SELECT public.optional_intro_test_buy(
  '92600000-0000-4000-8000-000000000002','apple',
  'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp',clock_timestamp());
SELECT public.optional_intro_test_buy(
  '92600000-0000-4000-8000-000000000003','apple',
  'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp',clock_timestamp());

DO $$
DECLARE result_row record; original_row record; selected_action text; next_revision bigint := 1;
BEGIN
  IF NOT trimmy.product_profile_has_confirmed_paper_trade('92600000-0000-4000-8000-000000000002') THEN
    RAISE EXCEPTION 'Confirmed buy helper missed immutable evidence';
  END IF;
  SELECT * INTO original_row FROM trimmy.product_launch_advance(
    '92600000-0000-4000-8000-000000000002',
    '92600000-0000-4000-8000-000000000202', repeat('9',64), 1,
    'introduction-completed',NULL);
  IF original_row.outcome <> 'saved' OR original_row.launch_checkpoint <> 'app' THEN
    RAISE EXCEPTION 'Confirmed buy could not complete introduction: %', original_row;
  END IF;
  SELECT * INTO result_row FROM trimmy.product_launch_advance(
    '92600000-0000-4000-8000-000000000002',
    '92600000-0000-4000-8000-000000000202', repeat('9',64), 1,
    'introduction-completed',NULL);
  IF result_row IS DISTINCT FROM original_row THEN
    RAISE EXCEPTION 'Completion retry changed its durable receipt';
  END IF;
  FOREACH selected_action IN ARRAY ARRAY[
    'paper-trade-confirmed','first-position-collected','day-one-seen','save-desk-saved']
  LOOP
    SELECT * INTO result_row FROM trimmy.product_launch_advance(
      '92600000-0000-4000-8000-000000000003', gen_random_uuid(), repeat('a',64),
      next_revision, selected_action,NULL);
    IF result_row.outcome <> 'saved' THEN
      RAISE EXCEPTION 'Legacy action failed (%): %',selected_action,result_row;
    END IF;
    next_revision := result_row.revision;
  END LOOP;
  IF result_row.launch_checkpoint <> 'app' OR result_row.revision <> 5 THEN
    RAISE EXCEPTION 'Legacy launch sequence changed: %',result_row;
  END IF;
END $$;

-- Deferred receipt/evidence triggers are part of the test, not bypassed by its rollback.
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
SELECT 'PASS: nullable profile, exact retry, honest skip/completion, real buy evidence and legacy sequence';
