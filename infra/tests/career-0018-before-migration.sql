-- One complete paper buy and its written reason committed while 0017 is the
-- latest schema. Migration 0018 must derive immutable Career start/first-buy
-- facts and both action missions without relying on a new trigger firing.
BEGIN;

INSERT INTO trimmy.users(id, created_at)
VALUES ('91800000-0000-4000-8000-000000000001', '2026-09-17T11:59:00.000Z');

INSERT INTO trimmy.paper_accounts(user_id, opened_at, updated_at)
VALUES ('91800000-0000-4000-8000-000000000001',
  '2026-09-17T12:00:00.000Z', '2026-09-17T12:00:00.000Z');
INSERT INTO trimmy.paper_cash_ledger(
  user_id, account_revision, order_id, entry_kind, delta_micros, balance_after_micros, created_at)
VALUES ('91800000-0000-4000-8000-000000000001', 0, NULL, 'initial',
  10000000000, 10000000000, '2026-09-17T12:00:00.000Z');

INSERT INTO trimmy.paper_order_previews(
  id, user_id, request_id, request_hash, account_revision, action, input_kind,
  input_amount_micros, asset_id, variant_mint, symbol, price_micros,
  quantity_micros, cash_debit_micros, cash_credit_micros, cash_after_micros,
  position_quantity_after_micros, position_cost_basis_after_micros,
  realized_gain_delta_micros, locked_gain_delta_micros, price_source,
  accepted_at, expires_at, created_at)
VALUES (
  '91800000-0000-4000-8000-000000000002',
  '91800000-0000-4000-8000-000000000001',
  '91800000-0000-4000-8000-000000000003', repeat('a', 64), 0,
  'buy', 'paper_amount', 1000000, 'backfill-stock',
  'XsP7xzNPvEHS1m6qfanPUGjNmdMVPckE3hER9uE7p6H', 'BACKx', 200000000,
  5000, 1000000, 0, 9999000000, 5000, 1000000, 0, 0,
  '{"provider":"tokens-xyz-v1","providerReference":"/v1/assets/backfill-stock/variants#fixture","marketSource":"integration-fixture","metricsSource":null,"providerTimestamps":{"asOf":null,"lastFetchedAt":null,"lastTradeAt":null,"unit":"not_declared"},"observedAt":"2026-09-17T12:00:00.000Z","acceptedAt":"2026-09-17T12:00:00.000Z"}'::jsonb,
  '2026-09-17T12:00:00.000Z', '2026-09-17T12:01:00.000Z',
  '2026-09-17T12:00:00.000Z');

INSERT INTO trimmy.paper_orders(
  id, user_id, preview_id, idempotency_key, request_hash, account_revision,
  action, asset_id, variant_mint, symbol, price_micros, quantity_micros,
  cash_debit_micros, cash_credit_micros, cash_before_micros, cash_after_micros,
  position_quantity_before_micros, position_quantity_after_micros,
  position_cost_basis_before_micros, position_cost_basis_after_micros,
  realized_gain_before_micros, realized_gain_delta_micros,
  realized_gain_after_micros, locked_gain_before_micros,
  locked_gain_delta_micros, locked_gain_after_micros, price_source, committed_at)
SELECT
  '91800000-0000-4000-8000-000000000004', user_id, id,
  '91800000-0000-4000-8000-000000000005', repeat('b', 64), 1,
  action, asset_id, variant_mint, symbol, price_micros, quantity_micros,
  cash_debit_micros, cash_credit_micros, 10000000000, cash_after_micros,
  0, position_quantity_after_micros, 0, position_cost_basis_after_micros,
  0, realized_gain_delta_micros, 0, 0, locked_gain_delta_micros, 0,
  price_source, '2026-09-17T12:00:01.000Z'
FROM trimmy.paper_order_previews
WHERE id = '91800000-0000-4000-8000-000000000002';

UPDATE trimmy.paper_accounts SET cash_micros = 9999000000, revision = 1,
  updated_at = '2026-09-17T12:00:01.000Z'
WHERE user_id = '91800000-0000-4000-8000-000000000001';
INSERT INTO trimmy.paper_positions(
  user_id, asset_id, variant_mint, symbol, quantity_micros, cost_basis_micros,
  realized_gain_micros, locked_gain_micros, last_order_revision, updated_at)
VALUES ('91800000-0000-4000-8000-000000000001', 'backfill-stock',
  'XsP7xzNPvEHS1m6qfanPUGjNmdMVPckE3hER9uE7p6H', 'BACKx', 5000, 1000000,
  0, 0, 1, '2026-09-17T12:00:01.000Z');
INSERT INTO trimmy.paper_cash_ledger(
  user_id, account_revision, order_id, entry_kind, delta_micros,
  balance_after_micros, created_at)
VALUES ('91800000-0000-4000-8000-000000000001', 1,
  '91800000-0000-4000-8000-000000000004', 'buy', -1000000, 9999000000,
  '2026-09-17T12:00:01.000Z');
UPDATE trimmy.paper_order_previews SET state = 'committed',
  committed_at = '2026-09-17T12:00:01.000Z'
WHERE id = '91800000-0000-4000-8000-000000000002';

DO $$
DECLARE selected_outcome text; career_revision bigint;
BEGIN
  SELECT result.outcome INTO selected_outcome
  FROM trimmy.product_profile_put(
    '91800000-0000-4000-8000-000000000001',
    '91800000-0000-4000-8000-000000000006', repeat('c', 64), 0,
    'practice', 'basics', 'oracle', 'one-mission', 'backfillcareer', 'first-trade') result;
  IF selected_outcome <> 'saved' THEN
    RAISE EXCEPTION 'Could not create the pre-0018 product profile: %', selected_outcome;
  END IF;

  -- Keep the reason before the following New York session so migration 0021's
  -- production verifier can prove the combined 0018 -> 0021 upgrade path.
  career_revision := trimmy.career_record_activity(
    '91800000-0000-4000-8000-000000000001', '2026-09-17', 10,
    '2026-09-17T12:05:00.000Z');
  INSERT INTO trimmy.career_trade_reasons(
    order_id, user_id, asset_id, variant_mint, note, trims_awarded,
    daily_award_number, saved_at)
  VALUES ('91800000-0000-4000-8000-000000000004',
    '91800000-0000-4000-8000-000000000001', 'backfill-stock',
    'XsP7xzNPvEHS1m6qfanPUGjNmdMVPckE3hER9uE7p6H',
    'The first report shows improving customer retention.', 10, 1,
    '2026-09-17T12:05:00.000Z');
  INSERT INTO trimmy.career_trim_ledger(
    user_id, career_revision, entry_kind, source_id, trims, awarded_on, created_at)
  VALUES ('91800000-0000-4000-8000-000000000001', career_revision,
    'paper-reason', '91800000-0000-4000-8000-000000000004', 10,
    '2026-09-17', '2026-09-17T12:05:00.000Z');
  INSERT INTO trimmy.career_reason_mutation_receipts(
    user_id, mutation_id, request_hash, order_id, asset_id, variant_mint,
    note, trims_awarded, daily_award_number, saved_at)
  VALUES ('91800000-0000-4000-8000-000000000001',
    '91800000-0000-4000-8000-000000000007', repeat('d', 64),
    '91800000-0000-4000-8000-000000000004', 'backfill-stock',
    'XsP7xzNPvEHS1m6qfanPUGjNmdMVPckE3hER9uE7p6H',
    'The first report shows improving customer retention.', 10, 1,
    '2026-09-17T12:05:00.000Z');
END;
$$;

COMMIT;
