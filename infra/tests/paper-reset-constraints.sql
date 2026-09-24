\set ON_ERROR_STOP on

-- Principal binding fails closed before any receipt or account state can leak.
DO $$
DECLARE result_row record;
BEGIN
  SELECT * INTO result_row FROM trimmy.paper_desk_reset(
    '92300000-0000-4000-8000-000000000001',
    '92300000-0000-4000-8000-000000000090', repeat('0', 64), 0);
  IF result_row.outcome <> 'invalid' OR result_row.mutation_id IS NOT NULL THEN
    RAISE EXCEPTION 'Reset accepted an absent transaction principal: %', result_row;
  END IF;
  PERFORM set_config('trimmy.practice_user_id', 'not-a-uuid', true);
  SELECT * INTO result_row FROM trimmy.paper_desk_reset(
    '92300000-0000-4000-8000-000000000001',
    '92300000-0000-4000-8000-000000000091', repeat('1', 64), 0);
  IF result_row.outcome <> 'invalid' THEN
    RAISE EXCEPTION 'Reset accepted a malformed transaction principal: %', result_row;
  END IF;
END $$;

INSERT INTO trimmy.users(id, created_at) VALUES
  ('92300000-0000-4000-8000-000000000001', clock_timestamp() - interval '1 day'),
  ('92300000-0000-4000-8000-000000000002', clock_timestamp() - interval '1 day'),
  ('92300000-0000-4000-8000-000000000003', clock_timestamp() - interval '1 day'),
  ('92300000-0000-4000-8000-000000000004', clock_timestamp() - interval '1 day');
INSERT INTO trimmy.practice_auth_identities(app_id, subject, user_id) VALUES
  ('paper-reset-test', 'did:privy:paperreset1', '92300000-0000-4000-8000-000000000001'),
  ('paper-reset-test', 'did:privy:paperreset2', '92300000-0000-4000-8000-000000000002'),
  ('paper-reset-test', 'did:privy:paperreset3', '92300000-0000-4000-8000-000000000003');

DO $$
DECLARE result_row record;
BEGIN
  PERFORM set_config('trimmy.practice_user_id',
    '92300000-0000-4000-8000-000000000001', true);
  SELECT * INTO result_row FROM trimmy.paper_desk_reset(
    '92300000-0000-4000-8000-000000000002',
    '92300000-0000-4000-8000-000000000092', repeat('2', 64), 0);
  IF result_row.outcome <> 'invalid' THEN
    RAISE EXCEPTION 'Cross-account reset did not fail closed: %', result_row;
  END IF;
  IF EXISTS (SELECT 1 FROM trimmy.paper_reset_receipts
      WHERE mutation_id = '92300000-0000-4000-8000-000000000092') THEN
    RAISE EXCEPTION 'Cross-account reset left a receipt';
  END IF;
END $$;

-- A terminal no-op is durable even if the account later starts trading.
DO $$
DECLARE result_row record;
BEGIN
  PERFORM set_config('trimmy.practice_user_id',
    '92300000-0000-4000-8000-000000000002', true);
  SELECT * INTO result_row FROM trimmy.paper_desk_reset(
    '92300000-0000-4000-8000-000000000002',
    '92300000-0000-4000-8000-000000000200', repeat('3', 64), 0);
  IF (result_row.outcome, result_row.previous_revision, result_row.revision,
      result_row.cash_micros, result_row.reset_at)
      IS DISTINCT FROM ('not_needed', 0::bigint, 0::bigint,
        10000000000::numeric, NULL::timestamptz) THEN
    RAISE EXCEPTION 'No-account no-op result is wrong: %', result_row;
  END IF;
END $$;
SELECT public.paper_reset_test_buy(
  '92300000-0000-4000-8000-000000000002', 'apple',
  'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', clock_timestamp() + interval '1 second');
DO $$
DECLARE result_row record;
BEGIN
  PERFORM set_config('trimmy.practice_user_id',
    '92300000-0000-4000-8000-000000000002', true);
  SELECT * INTO result_row FROM trimmy.paper_desk_reset(
    '92300000-0000-4000-8000-000000000002',
    '92300000-0000-4000-8000-000000000200', repeat('3', 64), 999);
  IF (result_row.outcome, result_row.previous_revision, result_row.revision,
      result_row.reset_at) IS DISTINCT FROM
      ('not_needed', 0::bigint, 0::bigint, NULL::timestamptz) THEN
    RAISE EXCEPTION 'Terminal no-op did not replay before mutable checks: %', result_row;
  END IF;
  SELECT * INTO result_row FROM trimmy.paper_desk_reset(
    '92300000-0000-4000-8000-000000000002',
    '92300000-0000-4000-8000-000000000200', repeat('4', 64), 1);
  IF result_row.outcome <> 'idempotency_conflict' THEN
    RAISE EXCEPTION 'No-op mutation accepted a different request hash: %', result_row;
  END IF;
END $$;

-- Build a complete paper/Career/product history that a reset must not alter.
DO $$
DECLARE result_row record;
BEGIN
  SELECT * INTO result_row FROM trimmy.product_profile_put(
    '92300000-0000-4000-8000-000000000001',
    '92300000-0000-4000-8000-000000000010', repeat('5', 64), 0,
    'practice', 'basics', 'wolf', 'one-mission', 'reset_user', 'first-trade');
  IF result_row.outcome <> 'saved' OR result_row.revision <> 1 THEN
    RAISE EXCEPTION 'Could not create reset fixture product profile: %', result_row;
  END IF;
END $$;

CREATE TEMP TABLE paper_reset_test_ids(
  name text PRIMARY KEY,
  id uuid NOT NULL
);
INSERT INTO paper_reset_test_ids VALUES
  ('reasoned', public.paper_reset_test_buy(
    '92300000-0000-4000-8000-000000000001', 'apple',
    'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp',
    clock_timestamp() - interval '10 minutes'));
INSERT INTO paper_reset_test_ids VALUES
  ('unreasoned', public.paper_reset_test_buy(
    '92300000-0000-4000-8000-000000000001', 'tesla',
    'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp',
    clock_timestamp() - interval '9 minutes'));
INSERT INTO paper_reset_test_ids VALUES
  ('preview', public.paper_reset_test_preview(
    '92300000-0000-4000-8000-000000000001', 'preview-only',
    'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp', clock_timestamp()));

DO $$
DECLARE result_row record;
DECLARE selected_order uuid;
BEGIN
  SELECT id INTO selected_order FROM paper_reset_test_ids WHERE name = 'reasoned';
  SELECT * INTO result_row FROM trimmy.career_trade_reason_put(
    '92300000-0000-4000-8000-000000000001',
    '92300000-0000-4000-8000-000000000011', repeat('6', 64), selected_order,
    'The verified company trend supports this paper position.');
  IF result_row.outcome <> 'saved' OR result_row.trims_awarded <> 10 THEN
    RAISE EXCEPTION 'Could not save pre-reset reason: %', result_row;
  END IF;
  SELECT * INTO result_row FROM trimmy.product_launch_advance(
    '92300000-0000-4000-8000-000000000001',
    '92300000-0000-4000-8000-000000000012', repeat('7', 64), 1,
    'paper-trade-confirmed', NULL);
  IF result_row.outcome <> 'saved' OR result_row.launch_checkpoint <> 'first-position' THEN
    RAISE EXCEPTION 'Could not create launch evidence before reset: %', result_row;
  END IF;
END $$;

CREATE TEMP TABLE paper_reset_before AS
SELECT a.opened_at, a.updated_at, a.revision, a.cash_micros,
  (SELECT count(*) FROM trimmy.paper_orders o WHERE o.user_id = a.user_id) AS order_count,
  (SELECT count(*) FROM trimmy.paper_positions p WHERE p.user_id = a.user_id) AS position_count,
  (SELECT count(*) FROM trimmy.paper_order_previews p WHERE p.user_id = a.user_id) AS preview_count,
  public.paper_reset_test_immutable_snapshot(a.user_id) AS immutable_snapshot
FROM trimmy.paper_accounts a
WHERE a.user_id = '92300000-0000-4000-8000-000000000001';

DO $$
DECLARE result_row record;
DECLARE before_row paper_reset_before%ROWTYPE;
DECLARE receipt_row trimmy.paper_reset_receipts%ROWTYPE;
DECLARE ledger_row trimmy.paper_cash_ledger%ROWTYPE;
BEGIN
  SELECT * INTO STRICT before_row FROM paper_reset_before;
  PERFORM set_config('trimmy.practice_user_id',
    '92300000-0000-4000-8000-000000000001', true);
  SELECT * INTO result_row FROM trimmy.paper_desk_reset(
    '92300000-0000-4000-8000-000000000001',
    '92300000-0000-4000-8000-000000000100', repeat('8', 64), before_row.revision);
  IF result_row.outcome <> 'reset'
      OR result_row.mutation_id <> '92300000-0000-4000-8000-000000000100'
      OR result_row.previous_revision <> before_row.revision
      OR result_row.revision <> before_row.revision + 1
      OR result_row.cash_micros <> 10000000000 OR result_row.reset_at IS NULL THEN
    RAISE EXCEPTION 'Successful reset result is wrong: %', result_row;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM trimmy.paper_accounts a
    WHERE a.user_id = '92300000-0000-4000-8000-000000000001'
      AND a.opened_at = before_row.opened_at
      AND a.revision = result_row.revision
      AND a.last_reset_revision = result_row.revision
      AND a.cash_micros = 10000000000 AND a.updated_at = result_row.reset_at
  ) THEN RAISE EXCEPTION 'Reset account projection is wrong'; END IF;
  IF before_row.order_count <> (SELECT count(*) FROM trimmy.paper_orders
      WHERE user_id = '92300000-0000-4000-8000-000000000001')
      OR before_row.position_count <> (SELECT count(*) FROM trimmy.paper_positions
      WHERE user_id = '92300000-0000-4000-8000-000000000001')
      OR before_row.preview_count <> (SELECT count(*) FROM trimmy.paper_order_previews
      WHERE user_id = '92300000-0000-4000-8000-000000000001') THEN
    RAISE EXCEPTION 'Reset removed immutable paper history';
  END IF;
  IF EXISTS (
    SELECT 1 FROM trimmy.paper_accounts a JOIN trimmy.paper_orders o ON o.user_id = a.user_id
    WHERE a.user_id = '92300000-0000-4000-8000-000000000001'
      AND o.account_revision > a.last_reset_revision
  ) OR EXISTS (
    SELECT 1 FROM trimmy.paper_accounts a JOIN trimmy.paper_positions p ON p.user_id = a.user_id
    WHERE a.user_id = '92300000-0000-4000-8000-000000000001'
      AND p.last_order_revision > a.last_reset_revision
  ) THEN RAISE EXCEPTION 'Reset did not expose an empty current desk'; END IF;
  IF public.paper_reset_test_immutable_snapshot(
      '92300000-0000-4000-8000-000000000001') <> before_row.immutable_snapshot THEN
    RAISE EXCEPTION 'Reset changed Career, Trims, missions, reasons, rank/streak, or launch evidence';
  END IF;
  SELECT * INTO STRICT receipt_row FROM trimmy.paper_reset_receipts
    WHERE user_id = '92300000-0000-4000-8000-000000000001'
      AND mutation_id = '92300000-0000-4000-8000-000000000100';
  SELECT * INTO STRICT ledger_row FROM trimmy.paper_cash_ledger
    WHERE user_id = receipt_row.user_id AND account_revision = receipt_row.revision;
  IF receipt_row.request_hash <> repeat('8', 64)
      OR receipt_row.previous_revision <> before_row.revision
      OR ledger_row.entry_kind <> 'reset'
      OR ledger_row.reset_mutation_id <> receipt_row.mutation_id
      OR ledger_row.order_id IS NOT NULL
      OR ledger_row.delta_micros <> 10000000000 - before_row.cash_micros
      OR ledger_row.balance_after_micros <> 10000000000
      OR ledger_row.created_at <> receipt_row.reset_at THEN
    RAISE EXCEPTION 'Reset receipt and cash ledger are inconsistent';
  END IF;
END $$;

-- An open preview remains auditable but its old revision can never commit.
DO $$
DECLARE selected_preview uuid;
BEGIN
  SELECT id INTO selected_preview FROM paper_reset_test_ids WHERE name = 'preview';
  IF NOT EXISTS (SELECT 1 FROM trimmy.paper_order_previews
      WHERE id = selected_preview AND state = 'open') THEN
    RAISE EXCEPTION 'Reset removed or rewrote its pre-existing preview';
  END IF;
  BEGIN
    PERFORM public.paper_reset_test_commit_stale_preview(selected_preview);
    RAISE EXCEPTION 'A pre-reset preview committed after its revision was invalidated';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;

-- Receipt lookup wins over stale revision/state and hash mismatch wins over it.
DO $$
DECLARE result_row record;
DECLARE current_revision bigint;
BEGIN
  SELECT revision INTO current_revision FROM trimmy.paper_accounts
    WHERE user_id = '92300000-0000-4000-8000-000000000001';
  PERFORM set_config('trimmy.practice_user_id',
    '92300000-0000-4000-8000-000000000001', true);
  SELECT * INTO result_row FROM trimmy.paper_desk_reset(
    '92300000-0000-4000-8000-000000000001',
    '92300000-0000-4000-8000-000000000100', repeat('8', 64), 0);
  IF result_row.outcome <> 'reset' OR result_row.revision <> current_revision THEN
    RAISE EXCEPTION 'Successful mutation did not replay before revision checks: %', result_row;
  END IF;
  SELECT * INTO result_row FROM trimmy.paper_desk_reset(
    '92300000-0000-4000-8000-000000000001',
    '92300000-0000-4000-8000-000000000100', repeat('9', 64), current_revision);
  IF result_row.outcome <> 'idempotency_conflict' THEN
    RAISE EXCEPTION 'Different hash did not conflict before desk checks: %', result_row;
  END IF;
  SELECT * INTO result_row FROM trimmy.paper_desk_reset(
    '92300000-0000-4000-8000-000000000001',
    '92300000-0000-4000-8000-000000000101', repeat('a', 64), current_revision - 1);
  IF result_row.outcome <> 'stale_revision' OR result_row.revision <> current_revision THEN
    RAISE EXCEPTION 'Stale base revision was not rejected: %', result_row;
  END IF;
  SELECT * INTO result_row FROM trimmy.paper_desk_reset(
    '92300000-0000-4000-8000-000000000001',
    '92300000-0000-4000-8000-000000000102', repeat('b', 64), current_revision);
  IF result_row.outcome <> 'not_needed' OR result_row.revision <> current_revision
      OR result_row.reset_at IS NOT NULL THEN
    RAISE EXCEPTION 'Empty current desk did not return terminal no-op: %', result_row;
  END IF;
END $$;

-- The first post-reset buy starts from zero and replaces the old snapshot.
INSERT INTO paper_reset_test_ids VALUES
  ('post-reset', public.paper_reset_test_buy(
    '92300000-0000-4000-8000-000000000001', 'tesla',
    'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp',
    (SELECT updated_at + interval '1 second' FROM trimmy.paper_accounts
      WHERE user_id = '92300000-0000-4000-8000-000000000001')));

DO $$
DECLARE old_order uuid; new_order uuid; result_row record;
DECLARE reset_revision bigint;
BEGIN
  SELECT id INTO old_order FROM paper_reset_test_ids WHERE name = 'unreasoned';
  SELECT id INTO new_order FROM paper_reset_test_ids WHERE name = 'post-reset';
  SELECT last_reset_revision INTO reset_revision FROM trimmy.paper_accounts
    WHERE user_id = '92300000-0000-4000-8000-000000000001';
  IF NOT EXISTS (SELECT 1 FROM trimmy.paper_orders
      WHERE id = new_order AND account_revision > reset_revision
        AND position_quantity_before_micros = 0
        AND position_cost_basis_before_micros = 0
        AND realized_gain_before_micros = 0
        AND locked_gain_before_micros = 0) THEN
    RAISE EXCEPTION 'Post-reset order accumulated an old position snapshot';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM trimmy.paper_positions
      WHERE user_id = '92300000-0000-4000-8000-000000000001'
        AND asset_id = 'tesla' AND last_order_revision > reset_revision
        AND quantity_micros = 1000000 AND cost_basis_micros = 1000000) THEN
    RAISE EXCEPTION 'Post-reset position projection is wrong';
  END IF;
  SELECT * INTO result_row FROM trimmy.career_trade_reason_put(
    '92300000-0000-4000-8000-000000000001',
    '92300000-0000-4000-8000-000000000111', repeat('c', 64), old_order,
    'This old paper order should no longer be eligible after reset.');
  IF result_row.outcome <> 'position_required' THEN
    RAISE EXCEPTION 'An unreasoned pre-reset order regained eligibility: %', result_row;
  END IF;
  SELECT * INTO result_row FROM trimmy.career_trade_reason_put(
    '92300000-0000-4000-8000-000000000001',
    '92300000-0000-4000-8000-000000000112', repeat('d', 64), new_order,
    'The new cycle position has a fresh verified paper thesis.');
  IF result_row.outcome <> 'saved' THEN
    RAISE EXCEPTION 'A post-reset buy was not reason eligible: %', result_row;
  END IF;
  SELECT id INTO old_order FROM paper_reset_test_ids WHERE name = 'reasoned';
  SELECT * INTO result_row FROM trimmy.career_trade_reason_put(
    '92300000-0000-4000-8000-000000000001',
    '92300000-0000-4000-8000-000000000011', repeat('6', 64), old_order,
    'The verified company trend supports this paper position.');
  IF result_row.outcome <> 'saved' THEN
    RAISE EXCEPTION 'Exact pre-reset reason replay stopped working: %', result_row;
  END IF;
  PERFORM set_config('trimmy.practice_user_id',
    '92300000-0000-4000-8000-000000000001', true);
  SELECT * INTO result_row FROM trimmy.paper_desk_reset(
    '92300000-0000-4000-8000-000000000001',
    '92300000-0000-4000-8000-000000000102', repeat('b', 64), 999);
  IF result_row.outcome <> 'not_needed' THEN
    RAISE EXCEPTION 'Terminal no-op changed meaning after later activity: %', result_row;
  END IF;
END $$;

-- Receipt history is append-only and its serving role is function-only.
DO $$
BEGIN
  BEGIN
    UPDATE trimmy.paper_reset_receipts SET request_hash = repeat('f', 64)
    WHERE user_id = '92300000-0000-4000-8000-000000000001'
      AND mutation_id = '92300000-0000-4000-8000-000000000100';
    RAISE EXCEPTION 'Reset receipt accepted an update';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  IF NOT (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class
      WHERE oid = 'trimmy.paper_reset_receipts'::regclass) THEN
    RAISE EXCEPTION 'Reset receipts do not force RLS';
  END IF;
  IF has_table_privilege('trimmy_paper_reset_test_runtime',
      'trimmy.paper_reset_receipts', 'SELECT')
      OR has_table_privilege('trimmy_paper_reset_test_runtime',
        'trimmy.paper_reset_receipts', 'INSERT')
      OR has_table_privilege('trimmy_paper_reset_test_runtime',
        'trimmy.paper_reset_receipts', 'UPDATE')
      OR has_table_privilege('trimmy_paper_reset_test_runtime',
        'trimmy.paper_reset_receipts', 'DELETE') THEN
    RAISE EXCEPTION 'Reset runtime has direct receipt authority';
  END IF;
  IF NOT has_function_privilege('trimmy_paper_reset_test_runtime',
      'trimmy.paper_desk_reset(uuid,uuid,text,bigint)', 'EXECUTE')
      OR has_function_privilege('public',
        'trimmy.paper_desk_reset(uuid,uuid,text,bigint)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Reset function grants are unsafe';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid =
      'trimmy.paper_desk_reset(uuid,uuid,text,bigint)'::regprocedure
      AND p.prosecdef) THEN
    RAISE EXCEPTION 'Reset entry point is not SECURITY DEFINER';
  END IF;
END $$;

-- Guest authorization admits exactly six reset requests per fixed hour.
INSERT INTO trimmy.guest_sessions(
  id, user_id, credential_hash, state, created_at, expires_at,
  hard_expires_at, last_seen_at)
SELECT '92300000-0000-4000-8000-000000000404',
  '92300000-0000-4000-8000-000000000004', repeat('e', 64), 'active',
  observed_at, observed_at + interval '30 days',
  observed_at + interval '90 days', observed_at
FROM (SELECT clock_timestamp() AS observed_at) clock;
DO $$
DECLARE result_row record; attempt integer;
BEGIN
  FOR attempt IN 1..7 LOOP
    SELECT * INTO result_row FROM trimmy.guest_authorize(repeat('e', 64), 'paper_reset');
    IF attempt <= 6 AND result_row.outcome <> 'authorized' THEN
      RAISE EXCEPTION 'Guest reset attempt % was unexpectedly denied: %', attempt, result_row;
    ELSIF attempt = 7 AND result_row.outcome <> 'rate_limited' THEN
      RAISE EXCEPTION 'Guest reset cap did not stop attempt seven: %', result_row;
    END IF;
  END LOOP;
END $$;

SELECT 'PASS: reset semantics, replay/conflict, projection, history, Career, reason, guest and security constraints.';
