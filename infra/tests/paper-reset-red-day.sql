\set ON_ERROR_STOP on

-- A future canonical session makes reset placement deterministic: account
-- updated_at controls the reset timestamp without relying on wall-clock sleeps.
CREATE TEMP TABLE paper_reset_red_day_users(
  timing text PRIMARY KEY,
  user_id uuid NOT NULL,
  handle text NOT NULL,
  first_order uuid,
  reset_at timestamptz
);
INSERT INTO paper_reset_red_day_users(timing, user_id, handle) VALUES
  ('before', '92310000-0000-4000-8000-000000000001', 'reset_before'),
  ('during', '92310000-0000-4000-8000-000000000002', 'reset_during'),
  ('after',  '92310000-0000-4000-8000-000000000003', 'reset_after');
INSERT INTO trimmy.users(id, created_at)
SELECT user_id, clock_timestamp() - interval '1 day' FROM paper_reset_red_day_users;

DO $$
DECLARE selected record; result_row record; suffix integer := 20;
BEGIN
  FOR selected IN SELECT * FROM paper_reset_red_day_users ORDER BY timing LOOP
    SELECT * INTO result_row FROM trimmy.product_profile_put(
      selected.user_id,
      ('92310000-0000-4000-8000-' || lpad(suffix::text, 12, '0'))::uuid,
      repeat(substr(selected.timing, 1, 1), 64), 0,
      'practice', 'basics', 'wolf', 'one-mission', selected.handle, 'first-trade');
    IF result_row.outcome <> 'saved' THEN
      RAISE EXCEPTION 'Could not create % red-day profile: %', selected.timing, result_row;
    END IF;
    suffix := suffix + 1;
  END LOOP;
END $$;

UPDATE paper_reset_red_day_users SET first_order = public.paper_reset_test_buy(
  user_id, 'reset-red-day', 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp',
  trimmy.career_red_day_session_open('2026-09-18') - interval '1 day');

DO $$
DECLARE selected record; suffix integer := 30;
BEGIN
  FOR selected IN SELECT * FROM paper_reset_red_day_users ORDER BY timing LOOP
    PERFORM public.paper_reset_test_historical_reason(selected.user_id,
      selected.first_order,
      ('92310000-0000-4000-8000-' || lpad(suffix::text, 12, '0'))::uuid,
      trimmy.career_red_day_session_open('2026-09-18') - interval '23 hours');
    suffix := suffix + 1;
  END LOOP;
END $$;

SELECT public.paper_reset_test_buy(
  '92310000-0000-4000-8000-000000000001', 'reset-clock-before',
  'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp',
  trimmy.career_red_day_session_open('2026-09-18') - interval '2 milliseconds');
SELECT public.paper_reset_test_buy(
  '92310000-0000-4000-8000-000000000002', 'reset-clock-during',
  'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp',
  trimmy.career_red_day_session_open('2026-09-18') + interval '1 hour' - interval '2 milliseconds');
SELECT public.paper_reset_test_buy(
  '92310000-0000-4000-8000-000000000003', 'reset-clock-after',
  'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp',
  trimmy.career_red_day_session_close('2026-09-18') + interval '1 hour' - interval '2 milliseconds');

DO $$
DECLARE selected record; selected_reset_at timestamptz; suffix integer := 40;
BEGIN
  FOR selected IN SELECT * FROM paper_reset_red_day_users ORDER BY timing LOOP
    selected_reset_at := CASE selected.timing
      WHEN 'before' THEN trimmy.career_red_day_session_open('2026-09-18') - interval '1 millisecond'
      WHEN 'during' THEN trimmy.career_red_day_session_open('2026-09-18') + interval '1 hour'
      ELSE trimmy.career_red_day_session_close('2026-09-18') + interval '1 hour'
    END;
    PERFORM public.paper_reset_test_historical_reset(selected.user_id,
      ('92310000-0000-4000-8000-' || lpad(suffix::text, 12, '0'))::uuid,
      repeat('e', 64), selected_reset_at);
    UPDATE paper_reset_red_day_users SET reset_at = selected_reset_at
      WHERE timing = selected.timing;
    suffix := suffix + 1;
  END LOOP;
END $$;

DO $$
DECLARE session_open timestamptz := trimmy.career_red_day_session_open('2026-09-18');
DECLARE session_close timestamptz := trimmy.career_red_day_session_close('2026-09-18');
BEGIN
  IF NOT EXISTS (SELECT 1 FROM paper_reset_red_day_users
      WHERE timing = 'before' AND reset_at < session_open)
      OR NOT EXISTS (SELECT 1 FROM paper_reset_red_day_users
      WHERE timing = 'during' AND reset_at BETWEEN session_open AND session_close)
      OR NOT EXISTS (SELECT 1 FROM paper_reset_red_day_users
      WHERE timing = 'after' AND reset_at > session_close) THEN
    RAISE EXCEPTION 'Red-day fixture resets were not placed around the session';
  END IF;
END $$;

SELECT trimmy.career_red_day_activate();
INSERT INTO trimmy.career_red_day_provider_observations(
  observation_id, request_hash, provider, verifier_version, asset_id,
  listed_symbol, observation_status, source, previous_market_date, market_date,
  previous_close_text, current_close_text, provider_as_of,
  provider_last_fetched_at, reason_code, detail_request_id, chart_request_id,
  detail_provider_request_id, chart_provider_request_id, detail_path,
  chart_path, detail_response_sha256, chart_response_sha256, observed_at)
VALUES ('92310000-0000-4000-8000-000000000100', repeat('a', 64),
  'tokens-xyz-v1', 'tokens-canonical-red-day-v1', 'reset-red-day', 'RRDAY',
  'verified-red', 'clickhouse_stock', '2026-09-17', '2026-09-18', '100', '99',
  '2026-09-18T21:00:00Z', '2026-09-18T21:00:00Z', NULL,
  '92310000-0000-4000-8000-000000000101',
  '92310000-0000-4000-8000-000000000102',
  'reset-detail', 'reset-chart', '/v1/assets/reset-red-day',
  '/v1/assets/reset-red-day/price-chart?interval=1D&from=1900000000&to=1910000000',
  repeat('b', 64), repeat('c', 64), '2026-09-18T22:00:00Z');
INSERT INTO trimmy.career_red_day_sessions(
  observation_id, provider, verifier_version, asset_id, market_date)
VALUES ('92310000-0000-4000-8000-000000000100', 'tokens-xyz-v1',
  'tokens-canonical-red-day-v1', 'reset-red-day', '2026-09-18');

DO $$
DECLARE result_row record;
BEGIN
  SELECT * INTO result_row FROM trimmy.career_red_day_process_session(
    '92310000-0000-4000-8000-000000000100', 100);
  IF result_row.outcome <> 'complete' OR result_row.evidence_count <> 3
      OR result_row.completed_count <> 1 OR NOT result_row.processing_complete THEN
    RAISE EXCEPTION 'Reset-aware red-day processing result is wrong: %', result_row;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM trimmy.career_red_day_user_evidence e
    WHERE e.observation_id = '92310000-0000-4000-8000-000000000100'
      AND e.user_id = '92310000-0000-4000-8000-000000000001'
      AND e.opening_order_id IS NULL AND e.opening_quantity_micros = 0
      AND e.minimum_session_quantity_micros = 0
      AND e.evidence_outcome = 'not-held-throughout'
      AND e.reason_code = 'not-positive-at-open') THEN
    RAISE EXCEPTION 'A pre-open reset did not produce a zero opening position';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM trimmy.career_red_day_user_evidence e
    WHERE e.observation_id = '92310000-0000-4000-8000-000000000100'
      AND e.user_id = '92310000-0000-4000-8000-000000000002'
      AND e.opening_order_id IS NOT NULL AND e.opening_quantity_micros > 0
      AND e.minimum_session_quantity_micros = 0
      AND e.evidence_outcome = 'not-held-throughout'
      AND e.reason_code = 'position-reached-zero') THEN
    RAISE EXCEPTION 'An in-session reset did not contribute a zero minimum';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM trimmy.career_red_day_user_evidence e
    WHERE e.observation_id = '92310000-0000-4000-8000-000000000100'
      AND e.user_id = '92310000-0000-4000-8000-000000000003'
      AND e.opening_order_id IS NOT NULL AND e.opening_quantity_micros > 0
      AND e.minimum_session_quantity_micros > 0
      AND e.evidence_outcome = 'qualified' AND e.reason_code IS NULL) THEN
    RAISE EXCEPTION 'A post-close reset changed the completed session';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM trimmy.career_mission_completions
      WHERE user_id = '92310000-0000-4000-8000-000000000003'
        AND mission_id = 'hold-through-red-day') THEN
    RAISE EXCEPTION 'Qualified post-close history did not complete immutable evidence';
  END IF;
END $$;

CREATE TEMP TABLE completed_red_day_snapshot AS
SELECT
  (SELECT to_jsonb(e) FROM trimmy.career_red_day_user_evidence e
    WHERE e.observation_id = '92310000-0000-4000-8000-000000000100'
      AND e.user_id = '92310000-0000-4000-8000-000000000003') AS evidence,
  (SELECT to_jsonb(c) FROM trimmy.career_mission_completions c
    WHERE c.user_id = '92310000-0000-4000-8000-000000000003'
      AND c.mission_id = 'hold-through-red-day') AS completion;

SELECT public.paper_reset_test_buy(
  '92310000-0000-4000-8000-000000000003', 'post-evidence-cycle',
  'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp',
  (SELECT updated_at + interval '1 second' FROM trimmy.paper_accounts
    WHERE user_id = '92310000-0000-4000-8000-000000000003'));
DO $$
DECLARE result_row record; before_row completed_red_day_snapshot%ROWTYPE;
BEGIN
  SELECT * INTO STRICT before_row FROM completed_red_day_snapshot;
  PERFORM set_config('trimmy.practice_user_id',
    '92310000-0000-4000-8000-000000000003', true);
  SELECT * INTO result_row FROM trimmy.paper_desk_reset(
    '92310000-0000-4000-8000-000000000003',
    '92310000-0000-4000-8000-000000000050', repeat('d', 64),
    (SELECT revision FROM trimmy.paper_accounts
      WHERE user_id = '92310000-0000-4000-8000-000000000003'));
  IF result_row.outcome <> 'reset' THEN
    RAISE EXCEPTION 'Post-evidence reset failed: %', result_row;
  END IF;
  IF before_row.evidence <> (SELECT to_jsonb(e)
      FROM trimmy.career_red_day_user_evidence e
      WHERE e.observation_id = '92310000-0000-4000-8000-000000000100'
        AND e.user_id = '92310000-0000-4000-8000-000000000003')
      OR before_row.completion <> (SELECT to_jsonb(c)
      FROM trimmy.career_mission_completions c
      WHERE c.user_id = '92310000-0000-4000-8000-000000000003'
        AND c.mission_id = 'hold-through-red-day') THEN
    RAISE EXCEPTION 'Completed red-day evidence changed after a later reset';
  END IF;
  BEGIN
    UPDATE trimmy.career_red_day_user_evidence SET reason_code = 'position-reached-zero'
    WHERE observation_id = '92310000-0000-4000-8000-000000000100'
      AND user_id = '92310000-0000-4000-8000-000000000003';
    RAISE EXCEPTION 'Completed red-day evidence accepted an update';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;

SELECT 'PASS: resets before/during sessions count as zero, post-close resets are irrelevant, and completed evidence stays immutable.';
