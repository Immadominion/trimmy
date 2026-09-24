-- Test-only helpers for migration 0023. The helpers use the same transaction
-- shape as the paper repository: paper advisory lock, immutable preview and
-- order, account/position projection, cash ledger, then preview finalization.

CREATE ROLE trimmy_paper_reset_test_runtime
  LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
CREATE ROLE trimmy_paper_reset_policy_probe
  LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
GRANT USAGE ON SCHEMA trimmy TO trimmy_paper_reset_test_runtime;
GRANT EXECUTE ON FUNCTION trimmy.paper_desk_reset(uuid, uuid, text, bigint)
  TO trimmy_paper_reset_test_runtime;
-- The real serving role already has these pre-0023 paper projection grants.
-- Deferred 0013 integrity triggers execute as the caller and re-read them.
GRANT SELECT ON trimmy.paper_accounts, trimmy.paper_cash_ledger
  TO trimmy_paper_reset_test_runtime;
GRANT USAGE ON SCHEMA trimmy TO trimmy_paper_reset_policy_probe;
GRANT SELECT ON trimmy.paper_reset_receipts TO trimmy_paper_reset_policy_probe;

CREATE FUNCTION public.paper_reset_test_buy(
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
REVOKE ALL ON FUNCTION public.paper_reset_test_buy(
  uuid, text, text, timestamptz) FROM PUBLIC;

CREATE FUNCTION public.paper_reset_test_preview(
  selected_user uuid,
  selected_asset text,
  selected_mint text,
  selected_accepted_at timestamptz
) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE account_row trimmy.paper_accounts%ROWTYPE;
DECLARE position_row trimmy.paper_positions%ROWTYPE;
DECLARE preview_id uuid := gen_random_uuid();
DECLARE before_quantity numeric := 0;
DECLARE before_basis numeric := 0;
DECLARE debit numeric := 1000000;
DECLARE quantity numeric := 1000000;
DECLARE source jsonb;
DECLARE selected_symbol text := upper(left(selected_asset, 20)) || 'x';
BEGIN
  SELECT a.* INTO STRICT account_row FROM trimmy.paper_accounts a
    WHERE a.user_id = selected_user;
  SELECT p.* INTO position_row FROM trimmy.paper_positions p
  WHERE p.user_id = selected_user AND p.asset_id = selected_asset
    AND p.variant_mint = selected_mint
    AND p.last_order_revision > account_row.last_reset_revision;
  IF FOUND THEN
    before_quantity := position_row.quantity_micros;
    before_basis := position_row.cost_basis_micros;
  END IF;
  source := jsonb_build_object(
    'provider', 'tokens-xyz-v1',
    'providerReference', '/v1/assets/' || selected_asset || '/variants#reset-preview',
    'marketSource', 'integration-fixture', 'metricsSource', NULL,
    'providerTimestamps', jsonb_build_object('asOf', NULL,
      'lastFetchedAt', NULL, 'lastTradeAt', NULL, 'unit', 'not_declared'),
    'observedAt', selected_accepted_at, 'acceptedAt', selected_accepted_at);
  INSERT INTO trimmy.paper_order_previews(
    id, user_id, request_id, request_hash, account_revision, action, input_kind,
    input_amount_micros, asset_id, variant_mint, symbol, price_micros,
    quantity_micros, cash_debit_micros, cash_credit_micros, cash_after_micros,
    position_quantity_after_micros, position_cost_basis_after_micros,
    realized_gain_delta_micros, locked_gain_delta_micros, price_source,
    accepted_at, expires_at, created_at)
  VALUES (preview_id, selected_user, gen_random_uuid(), repeat('c', 64),
    account_row.revision, 'buy', 'paper_amount', debit, selected_asset,
    selected_mint, selected_symbol, 1000000, quantity, debit, 0,
    account_row.cash_micros - debit, before_quantity + quantity,
    before_basis + debit, 0, 0, source, selected_accepted_at,
    selected_accepted_at + interval '60 seconds', selected_accepted_at);
  RETURN preview_id;
END;
$$;
REVOKE ALL ON FUNCTION public.paper_reset_test_preview(
  uuid, text, text, timestamptz) FROM PUBLIC;

-- Red-day fixtures need a historical boundary on each side of a closed market
-- session. Production never accepts a caller timestamp; this owner-only test
-- helper writes the same receipt/account/ledger triple at a fixed past instant.
CREATE FUNCTION public.paper_reset_test_historical_reset(
  selected_user uuid,
  selected_mutation uuid,
  selected_hash text,
  selected_reset_at timestamptz
) RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE account_row trimmy.paper_accounts%ROWTYPE;
DECLARE next_revision bigint;
BEGIN
  PERFORM set_config('trimmy.practice_user_id', selected_user::text, true);
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.paper:' || selected_user::text, 0));
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.career:' || selected_user::text, 0));
  SELECT * INTO STRICT account_row FROM trimmy.paper_accounts
    WHERE user_id = selected_user FOR UPDATE;
  IF selected_reset_at <= account_row.updated_at THEN
    RAISE EXCEPTION 'Historical reset must move account time forwards';
  END IF;
  next_revision := account_row.revision + 1;
  INSERT INTO trimmy.paper_reset_receipts(
    user_id, mutation_id, request_hash, outcome, previous_revision,
    revision, cash_micros, reset_at)
  VALUES (selected_user, selected_mutation, selected_hash, 'reset',
    account_row.revision, next_revision, 10000000000, selected_reset_at);
  UPDATE trimmy.paper_accounts SET cash_micros = 10000000000,
    revision = next_revision, last_reset_revision = next_revision,
    updated_at = selected_reset_at WHERE user_id = selected_user;
  INSERT INTO trimmy.paper_cash_ledger(
    user_id, account_revision, order_id, reset_mutation_id, entry_kind,
    delta_micros, balance_after_micros, created_at)
  VALUES (selected_user, next_revision, NULL, selected_mutation, 'reset',
    10000000000 - account_row.cash_micros, 10000000000, selected_reset_at);
  RETURN next_revision;
END;
$$;
REVOKE ALL ON FUNCTION public.paper_reset_test_historical_reset(
  uuid, uuid, text, timestamptz) FROM PUBLIC;

CREATE FUNCTION public.paper_reset_test_historical_reason(
  selected_user uuid,
  selected_order uuid,
  selected_mutation uuid,
  selected_saved_at timestamptz
) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE order_row trimmy.paper_orders%ROWTYPE;
DECLARE career_revision bigint;
DECLARE selected_note text :=
  'This verified paper thesis is retained for the canonical session.';
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.career:' || selected_user::text, 0));
  SELECT * INTO STRICT order_row FROM trimmy.paper_orders
    WHERE id = selected_order AND user_id = selected_user AND action = 'buy';
  career_revision := trimmy.career_record_activity(selected_user,
    (selected_saved_at AT TIME ZONE 'UTC')::date, 10, selected_saved_at);
  INSERT INTO trimmy.career_trade_reasons(
    order_id, user_id, asset_id, variant_mint, note, trims_awarded,
    daily_award_number, saved_at)
  VALUES (order_row.id, selected_user, order_row.asset_id,
    order_row.variant_mint, selected_note, 10, 1, selected_saved_at);
  INSERT INTO trimmy.career_trim_ledger(
    user_id, career_revision, entry_kind, source_id, trims, awarded_on, created_at)
  VALUES (selected_user, career_revision, 'paper-reason', order_row.id, 10,
    (selected_saved_at AT TIME ZONE 'UTC')::date, selected_saved_at);
  INSERT INTO trimmy.career_reason_mutation_receipts(
    user_id, mutation_id, request_hash, order_id, asset_id, variant_mint,
    note, trims_awarded, daily_award_number, saved_at)
  VALUES (selected_user, selected_mutation, repeat('f', 64), order_row.id,
    order_row.asset_id, order_row.variant_mint, selected_note, 10, 1,
    selected_saved_at);
END;
$$;
REVOKE ALL ON FUNCTION public.paper_reset_test_historical_reason(
  uuid, uuid, uuid, timestamptz) FROM PUBLIC;

CREATE FUNCTION public.paper_reset_test_commit_stale_preview(selected_preview uuid)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE p trimmy.paper_order_previews%ROWTYPE;
BEGIN
  SELECT * INTO STRICT p FROM trimmy.paper_order_previews WHERE id = selected_preview;
  INSERT INTO trimmy.paper_orders(
    id, user_id, preview_id, idempotency_key, request_hash, account_revision,
    action, asset_id, variant_mint, symbol, price_micros, quantity_micros,
    cash_debit_micros, cash_credit_micros, cash_before_micros, cash_after_micros,
    position_quantity_before_micros, position_quantity_after_micros,
    position_cost_basis_before_micros, position_cost_basis_after_micros,
    realized_gain_before_micros, realized_gain_delta_micros,
    realized_gain_after_micros, locked_gain_before_micros,
    locked_gain_delta_micros, locked_gain_after_micros, price_source, committed_at)
  VALUES (gen_random_uuid(), p.user_id, p.id, gen_random_uuid(), repeat('d', 64),
    p.account_revision + 1, p.action, p.asset_id, p.variant_mint, p.symbol,
    p.price_micros, p.quantity_micros, p.cash_debit_micros,
    p.cash_credit_micros, p.cash_after_micros + p.cash_debit_micros,
    p.cash_after_micros, 0, p.position_quantity_after_micros, 0,
    p.position_cost_basis_after_micros, 0, p.realized_gain_delta_micros,
    p.realized_gain_delta_micros, 0, p.locked_gain_delta_micros,
    p.locked_gain_delta_micros, p.price_source, p.accepted_at + interval '1 millisecond');
END;
$$;
REVOKE ALL ON FUNCTION public.paper_reset_test_commit_stale_preview(uuid) FROM PUBLIC;

CREATE FUNCTION public.paper_reset_test_immutable_snapshot(selected_user uuid)
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
    'career_profile', (SELECT to_jsonb(p) FROM trimmy.career_profiles p
      WHERE p.user_id = selected_user),
    'career_starts', (SELECT coalesce(jsonb_agg(to_jsonb(s) ORDER BY s.first_order_id), '[]')
      FROM trimmy.career_starts s WHERE s.user_id = selected_user),
    'first_buys', (SELECT coalesce(jsonb_agg(to_jsonb(b) ORDER BY b.order_id), '[]')
      FROM trimmy.career_first_confirmed_buys b WHERE b.user_id = selected_user),
    'trims', (SELECT coalesce(jsonb_agg(to_jsonb(l) ORDER BY l.career_revision), '[]')
      FROM trimmy.career_trim_ledger l WHERE l.user_id = selected_user),
    'reasons', (SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.order_id), '[]')
      FROM trimmy.career_trade_reasons r WHERE r.user_id = selected_user),
    'reason_receipts', (SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.mutation_id), '[]')
      FROM trimmy.career_reason_mutation_receipts r WHERE r.user_id = selected_user),
    'missions', (SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY c.mission_id), '[]')
      FROM trimmy.career_mission_completions c WHERE c.user_id = selected_user),
    'promotions', (SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.mutation_id), '[]')
      FROM trimmy.career_promotion_receipts r WHERE r.user_id = selected_user),
    'profile', (SELECT to_jsonb(p) FROM trimmy.product_profiles p
      WHERE p.user_id = selected_user),
    'profile_receipts', (SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.revision), '[]')
      FROM trimmy.product_profile_mutation_receipts r WHERE r.user_id = selected_user),
    'launch_receipts', (SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY r.revision), '[]')
      FROM trimmy.product_launch_action_receipts r WHERE r.user_id = selected_user)
  );
$$;
REVOKE ALL ON FUNCTION public.paper_reset_test_immutable_snapshot(uuid) FROM PUBLIC;
