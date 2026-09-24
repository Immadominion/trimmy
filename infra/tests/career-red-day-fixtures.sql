-- Historical paper positions for migration 0021's real-PostgreSQL verifier.
-- Apply after 0017 and before 0018 so the authored action missions backfill
-- from the same immutable orders and reasons production uses.

CREATE FUNCTION pg_temp.red_day_make_user(selected_user uuid, first_order_at timestamptz)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO trimmy.users(id, created_at)
  VALUES (selected_user, first_order_at - interval '2 minutes');
  INSERT INTO trimmy.paper_accounts(user_id, opened_at, updated_at)
  VALUES (selected_user, first_order_at - interval '1 minute', first_order_at - interval '1 minute');
  INSERT INTO trimmy.paper_cash_ledger(
    user_id, account_revision, order_id, entry_kind, delta_micros,
    balance_after_micros, created_at)
  VALUES (selected_user, 0, NULL, 'initial', 10000000000, 10000000000,
    first_order_at - interval '1 minute');
END;
$$;

CREATE FUNCTION public.red_day_test_order(
  selected_user uuid,
  selected_asset text,
  selected_mint text,
  selected_action text,
  selected_quantity numeric,
  selected_committed_at timestamptz
) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE account_row trimmy.paper_accounts%ROWTYPE;
DECLARE position_row trimmy.paper_positions%ROWTYPE;
DECLARE preview_id uuid := gen_random_uuid(); order_id uuid := gen_random_uuid();
DECLARE accepted_at timestamptz := selected_committed_at - interval '1 second';
DECLARE before_quantity numeric := 0; before_basis numeric := 0;
DECLARE after_quantity numeric; after_basis numeric;
DECLARE debit numeric := 0; credit numeric := 0; after_cash numeric;
DECLARE next_revision bigint; source jsonb;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.paper:' || selected_user::text, 0));
  SELECT a.* INTO account_row FROM trimmy.paper_accounts a
    WHERE a.user_id = selected_user FOR UPDATE;
  IF NOT FOUND OR selected_action NOT IN ('buy', 'sell') OR selected_quantity <= 0 THEN
    RAISE EXCEPTION 'Invalid red-day paper fixture';
  END IF;
  SELECT p.* INTO position_row FROM trimmy.paper_positions p
    WHERE p.user_id = selected_user AND p.asset_id = selected_asset
      AND p.variant_mint = selected_mint;
  IF FOUND THEN
    before_quantity := position_row.quantity_micros;
    before_basis := position_row.cost_basis_micros;
  END IF;
  IF selected_action = 'buy' THEN
    debit := selected_quantity;
    after_quantity := before_quantity + selected_quantity;
    after_basis := before_basis + selected_quantity;
  ELSE
    IF before_quantity < selected_quantity THEN RAISE EXCEPTION 'Fixture oversell'; END IF;
    credit := selected_quantity;
    after_quantity := before_quantity - selected_quantity;
    after_basis := before_basis - selected_quantity;
  END IF;
  after_cash := account_row.cash_micros - debit + credit;
  next_revision := account_row.revision + 1;
  source := jsonb_build_object(
    'provider', 'tokens-xyz-v1',
    'providerReference', '/v1/assets/apple/variants#red-day-fixture',
    'marketSource', 'integration-fixture', 'metricsSource', NULL,
    'providerTimestamps', jsonb_build_object('asOf', NULL, 'lastFetchedAt', NULL,
      'lastTradeAt', NULL, 'unit', 'not_declared'),
    'observedAt', accepted_at, 'acceptedAt', accepted_at);
  INSERT INTO trimmy.paper_order_previews(
    id, user_id, request_id, request_hash, account_revision, action, input_kind,
    input_amount_micros, asset_id, variant_mint, symbol, price_micros,
    quantity_micros, cash_debit_micros, cash_credit_micros, cash_after_micros,
    position_quantity_after_micros, position_cost_basis_after_micros,
    realized_gain_delta_micros, locked_gain_delta_micros, price_source,
    accepted_at, expires_at, created_at)
  VALUES (preview_id, selected_user, gen_random_uuid(), repeat('a', 64),
    account_row.revision, selected_action,
    CASE WHEN selected_action = 'buy' THEN 'paper_amount' ELSE 'share_quantity' END,
    selected_quantity, selected_asset, selected_mint, 'AAPLx', 1000000,
    selected_quantity, debit, credit, after_cash, after_quantity, after_basis,
    0, 0, source, accepted_at, selected_committed_at + interval '20 seconds', accepted_at);
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
    next_revision, selected_action, selected_asset, selected_mint, 'AAPLx', 1000000,
    selected_quantity, debit, credit, account_row.cash_micros, after_cash,
    before_quantity, after_quantity, before_basis, after_basis, 0, 0, 0, 0, 0, 0,
    source, selected_committed_at);
  UPDATE trimmy.paper_accounts SET cash_micros = after_cash, revision = next_revision,
    updated_at = selected_committed_at WHERE user_id = selected_user;
  INSERT INTO trimmy.paper_positions(
    user_id, asset_id, variant_mint, symbol, quantity_micros, cost_basis_micros,
    realized_gain_micros, locked_gain_micros, last_order_revision, updated_at)
  VALUES (selected_user, selected_asset, selected_mint, 'AAPLx', after_quantity,
    after_basis, 0, 0, next_revision, selected_committed_at)
  ON CONFLICT (user_id, asset_id, variant_mint) DO UPDATE SET
    symbol = EXCLUDED.symbol, quantity_micros = EXCLUDED.quantity_micros,
    cost_basis_micros = EXCLUDED.cost_basis_micros,
    realized_gain_micros = EXCLUDED.realized_gain_micros,
    locked_gain_micros = EXCLUDED.locked_gain_micros,
    last_order_revision = EXCLUDED.last_order_revision,
    updated_at = EXCLUDED.updated_at;
  INSERT INTO trimmy.paper_cash_ledger(
    user_id, account_revision, order_id, entry_kind, delta_micros,
    balance_after_micros, created_at)
  VALUES (selected_user, next_revision, order_id, selected_action,
    credit - debit, after_cash, selected_committed_at);
  UPDATE trimmy.paper_order_previews SET state = 'committed',
    committed_at = selected_committed_at WHERE id = preview_id;
  RETURN order_id;
END;
$$;
REVOKE ALL ON FUNCTION public.red_day_test_order(
  uuid, text, text, text, numeric, timestamptz) FROM PUBLIC;

CREATE FUNCTION pg_temp.red_day_reason(selected_user uuid, saved_at timestamptz)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE selected_order trimmy.paper_orders%ROWTYPE; next_revision bigint;
DECLARE selected_note text := 'The verified company trend supports this paper position.';
BEGIN
  SELECT o.* INTO selected_order FROM trimmy.paper_orders o
  WHERE o.user_id = selected_user AND o.action = 'buy'
  ORDER BY o.committed_at, o.account_revision, o.id LIMIT 1;
  next_revision := trimmy.career_record_activity(
    selected_user, (saved_at AT TIME ZONE 'UTC')::date, 10, saved_at);
  INSERT INTO trimmy.career_trade_reasons(
    order_id, user_id, asset_id, variant_mint, note, trims_awarded,
    daily_award_number, saved_at)
  VALUES (selected_order.id, selected_user, selected_order.asset_id,
    selected_order.variant_mint, selected_note, 10, 1, saved_at);
  INSERT INTO trimmy.career_trim_ledger(
    user_id, career_revision, entry_kind, source_id, trims, awarded_on, created_at)
  VALUES (selected_user, next_revision, 'paper-reason', selected_order.id, 10,
    (saved_at AT TIME ZONE 'UTC')::date, saved_at);
  INSERT INTO trimmy.career_reason_mutation_receipts(
    user_id, mutation_id, request_hash, order_id, asset_id, variant_mint,
    note, trims_awarded, daily_award_number, saved_at)
  VALUES (selected_user, gen_random_uuid(), repeat('c', 64), selected_order.id,
    selected_order.asset_id, selected_order.variant_mint, selected_note, 10, 1, saved_at);
END;
$$;

-- New York regular session on 18 September 2026 is 13:30Z through 20:00Z.
SELECT pg_temp.red_day_make_user('92100000-0000-4000-8000-000000000001', '2026-09-17T12:00:00Z');
SELECT public.red_day_test_order('92100000-0000-4000-8000-000000000001',
  'apple', 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', 'buy', 1000000, '2026-09-17T12:00:00Z');
SELECT public.red_day_test_order('92100000-0000-4000-8000-000000000001',
  'alpha', 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', 'buy', 1000000, '2026-09-17T12:00:01Z');
SELECT public.red_day_test_order('92100000-0000-4000-8000-000000000001',
  'beta', 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', 'buy', 1000000, '2026-09-17T12:00:02Z');
SELECT public.red_day_test_order('92100000-0000-4000-8000-000000000001',
  'gamma', 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', 'buy', 1000000, '2026-09-17T12:00:03Z');
SELECT public.red_day_test_order('92100000-0000-4000-8000-000000000001',
  'delta', 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', 'buy', 1000000, '2026-09-17T12:00:04Z');
SELECT public.red_day_test_order('92100000-0000-4000-8000-000000000001',
  'omega', 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', 'buy', 1000000, '2026-09-17T12:00:05Z');
SELECT pg_temp.red_day_reason('92100000-0000-4000-8000-000000000001', '2026-09-17T12:05:00Z');

SELECT pg_temp.red_day_make_user('92100000-0000-4000-8000-000000000002', '2026-09-18T13:30:00Z');
SELECT public.red_day_test_order('92100000-0000-4000-8000-000000000002',
  'apple', 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', 'buy', 1000000, '2026-09-18T13:30:00Z');
SELECT pg_temp.red_day_reason('92100000-0000-4000-8000-000000000002', '2026-09-18T13:31:00Z');

SELECT pg_temp.red_day_make_user('92100000-0000-4000-8000-000000000003', '2026-09-18T14:00:00Z');
SELECT public.red_day_test_order('92100000-0000-4000-8000-000000000003',
  'apple', 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', 'buy', 1000000, '2026-09-18T14:00:00Z');
SELECT pg_temp.red_day_reason('92100000-0000-4000-8000-000000000003', '2026-09-18T14:01:00Z');

SELECT pg_temp.red_day_make_user('92100000-0000-4000-8000-000000000004', '2026-09-17T12:00:00Z');
SELECT public.red_day_test_order('92100000-0000-4000-8000-000000000004',
  'apple', 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', 'buy', 1000000, '2026-09-17T12:00:00Z');
SELECT pg_temp.red_day_reason('92100000-0000-4000-8000-000000000004', '2026-09-17T12:05:00Z');
SELECT public.red_day_test_order('92100000-0000-4000-8000-000000000004',
  'apple', 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', 'sell', 500000, '2026-09-18T15:00:00Z');

SELECT pg_temp.red_day_make_user('92100000-0000-4000-8000-000000000005', '2026-09-17T12:00:00Z');
SELECT public.red_day_test_order('92100000-0000-4000-8000-000000000005',
  'apple', 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', 'buy', 1000000, '2026-09-17T12:00:00Z');
SELECT pg_temp.red_day_reason('92100000-0000-4000-8000-000000000005', '2026-09-17T12:05:00Z');
SELECT public.red_day_test_order('92100000-0000-4000-8000-000000000005',
  'apple', 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', 'sell', 1000000, '2026-09-18T15:00:00Z');
SELECT public.red_day_test_order('92100000-0000-4000-8000-000000000005',
  'apple', 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', 'buy', 1000000, '2026-09-18T15:01:00Z');

SELECT pg_temp.red_day_make_user('92100000-0000-4000-8000-000000000006', '2026-09-17T12:00:00Z');
SELECT public.red_day_test_order('92100000-0000-4000-8000-000000000006',
  'apple', 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', 'buy', 1000000, '2026-09-17T12:00:00Z');
SELECT pg_temp.red_day_reason('92100000-0000-4000-8000-000000000006', '2026-09-17T12:05:00Z');
SELECT public.red_day_test_order('92100000-0000-4000-8000-000000000006',
  'apple', 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', 'sell', 1000000, '2026-09-18T20:00:00Z');

SELECT pg_temp.red_day_make_user('92100000-0000-4000-8000-000000000007', '2026-09-17T12:00:00Z');
SELECT public.red_day_test_order('92100000-0000-4000-8000-000000000007',
  'apple', 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', 'buy', 1000000, '2026-09-17T12:00:00Z');
SELECT pg_temp.red_day_reason('92100000-0000-4000-8000-000000000007', '2026-09-17T12:05:00Z');
SELECT public.red_day_test_order('92100000-0000-4000-8000-000000000007',
  'apple', 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', 'sell', 1000000, '2026-09-18T20:00:00.001Z');

SELECT pg_temp.red_day_make_user('92100000-0000-4000-8000-000000000008', '2026-09-17T12:00:00Z');
SELECT public.red_day_test_order('92100000-0000-4000-8000-000000000008',
  'apple', 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', 'buy', 1000000, '2026-09-17T12:00:00Z');
SELECT pg_temp.red_day_reason('92100000-0000-4000-8000-000000000008', '2026-09-17T12:05:00Z');
SELECT public.red_day_test_order('92100000-0000-4000-8000-000000000008',
  'apple', 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', 'sell', 1000000, '2026-09-18T13:00:00Z');
SELECT public.red_day_test_order('92100000-0000-4000-8000-000000000008',
  'apple', '123mYEnRLM2LLYsJW3K6oyYh8uP1fngj732iG638ondo', 'buy', 1000000, '2026-09-18T14:00:00Z');

-- A broad-cursor user without a reason, used to prove prerequisites are
-- rechecked under the Career lock rather than filtered before it.
SELECT pg_temp.red_day_make_user('92100000-0000-4000-8000-000000000010', '2026-09-17T12:00:00Z');
SELECT public.red_day_test_order('92100000-0000-4000-8000-000000000010',
  'apple', 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', 'buy', 1000000, '2026-09-17T12:00:00Z');

-- The verifier race user receives an uncommitted sell from the Node test.
SELECT pg_temp.red_day_make_user('92100000-0000-4000-8000-000000000011', '2026-09-17T12:00:00Z');
SELECT public.red_day_test_order('92100000-0000-4000-8000-000000000011',
  'apple', 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', 'buy', 1000000, '2026-09-17T12:00:00Z');
SELECT pg_temp.red_day_reason('92100000-0000-4000-8000-000000000011', '2026-09-17T12:05:00Z');

-- The account-closure race user holds omega so its verifier session can be
-- isolated after the main Apple session has completed without adding another
-- scheduler candidate to the fairness fixture.
SELECT pg_temp.red_day_make_user('92100000-0000-4000-8000-000000000012', '2026-09-17T12:00:00Z');
SELECT public.red_day_test_order('92100000-0000-4000-8000-000000000012',
  'omega', 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', 'buy', 1000000, '2026-09-17T12:00:00Z');
SELECT pg_temp.red_day_reason('92100000-0000-4000-8000-000000000012', '2026-09-17T12:05:00Z');
