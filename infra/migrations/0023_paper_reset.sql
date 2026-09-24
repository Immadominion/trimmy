-- 0023: an idempotent paper-desk reset. Historical orders, previews, ledger
-- entries and every Career record remain append-only. A reset advances the
-- paper revision and records the boundary after which rows form the current
-- desk cycle.
BEGIN;

ALTER TABLE trimmy.paper_accounts
  ADD COLUMN last_reset_revision bigint NOT NULL DEFAULT 0;
ALTER TABLE trimmy.paper_accounts
  ADD CONSTRAINT paper_accounts_last_reset_revision_check CHECK (
    last_reset_revision BETWEEN 0 AND revision
    AND last_reset_revision <= 9007199254740991);

CREATE TABLE trimmy.paper_reset_receipts (
  user_id uuid NOT NULL REFERENCES trimmy.users(id),
  mutation_id uuid NOT NULL,
  request_hash trimmy.sha256_hex NOT NULL,
  outcome text COLLATE "C" NOT NULL CHECK (outcome IN ('reset', 'not_needed')),
  previous_revision bigint NOT NULL
    CHECK (previous_revision BETWEEN 0 AND 9007199254740991),
  revision bigint NOT NULL
    CHECK (revision BETWEEN 0 AND 9007199254740991),
  cash_micros numeric(30,0) NOT NULL CHECK (cash_micros = 10000000000),
  reset_at timestamptz CHECK (reset_at IS NULL OR isfinite(reset_at)),
  PRIMARY KEY (user_id, mutation_id),
  CHECK ((outcome = 'reset' AND revision = previous_revision + 1
      AND reset_at IS NOT NULL)
    OR (outcome = 'not_needed' AND revision = previous_revision
      AND reset_at IS NULL))
);
CREATE UNIQUE INDEX paper_reset_receipts_success_revision
  ON trimmy.paper_reset_receipts(user_id, revision)
  WHERE outcome = 'reset';

-- Current-cycle reads must be able to prove that an empty post-reset desk has
-- no newer order without scanning the user's complete immutable order history.
CREATE INDEX paper_orders_current_cycle
  ON trimmy.paper_orders(user_id, account_revision DESC);

ALTER TABLE trimmy.paper_cash_ledger
  ADD COLUMN reset_mutation_id uuid;
ALTER TABLE trimmy.paper_cash_ledger
  DROP CONSTRAINT paper_cash_ledger_entry_kind_check,
  DROP CONSTRAINT paper_cash_ledger_check;
ALTER TABLE trimmy.paper_cash_ledger
  ADD CONSTRAINT paper_cash_ledger_entry_kind_check
    CHECK (entry_kind IN ('initial', 'buy', 'sell', 'trim', 'reset')),
  ADD CONSTRAINT paper_cash_ledger_source_check CHECK (
    (account_revision = 0 AND order_id IS NULL AND reset_mutation_id IS NULL
      AND entry_kind = 'initial' AND delta_micros = 10000000000
      AND balance_after_micros = 10000000000)
    OR (account_revision > 0 AND order_id IS NOT NULL
      AND reset_mutation_id IS NULL AND entry_kind IN ('buy', 'sell', 'trim'))
    OR (account_revision > 0 AND order_id IS NULL
      AND reset_mutation_id IS NOT NULL AND entry_kind = 'reset'
      AND balance_after_micros = 10000000000)),
  ADD CONSTRAINT paper_cash_ledger_reset_receipt_fkey
    FOREIGN KEY (user_id, reset_mutation_id)
    REFERENCES trimmy.paper_reset_receipts(user_id, mutation_id);

CREATE TRIGGER paper_reset_receipts_append_only
  BEFORE UPDATE OR DELETE ON trimmy.paper_reset_receipts
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();

-- Account identity and opening remain immutable. A normal order leaves the
-- reset boundary unchanged; only the reset function may advance it to the
-- same revision the account is entering.
CREATE OR REPLACE FUNCTION trimmy.protect_paper_account() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, trimmy AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM trimmy.users WHERE id = NEW.user_id AND status = 'active') THEN
    RAISE EXCEPTION 'Paper trading requires an active account'
      USING ERRCODE = '23514', CONSTRAINT = 'paper_account_active';
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.revision <> 0 OR NEW.last_reset_revision <> 0
        OR NEW.cash_micros <> 10000000000 OR NEW.starting_cash_micros <> 10000000000
        OR NEW.updated_at <> NEW.opened_at THEN
      RAISE EXCEPTION 'Paper accounts begin at the exact initial grant'
        USING ERRCODE = '23514';
    END IF;
  ELSE
    IF (NEW.user_id, NEW.starting_cash_micros, NEW.opened_at)
        IS DISTINCT FROM (OLD.user_id, OLD.starting_cash_micros, OLD.opened_at) THEN
      RAISE EXCEPTION 'Paper account identity and opening are immutable'
        USING ERRCODE = '23514';
    END IF;
    IF NEW.revision <> OLD.revision + 1 OR NEW.updated_at <= OLD.updated_at
        OR NEW.last_reset_revision < OLD.last_reset_revision
        OR NEW.last_reset_revision NOT IN (OLD.last_reset_revision, NEW.revision) THEN
      RAISE EXCEPTION 'Paper account revision must advance exactly once'
        USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.protect_paper_account() FROM PUBLIC;

-- A first order in a new desk cycle may replace the previous cycle's
-- aggregate gains. Within one cycle, the original monotonic locked-gain rule
-- still applies. The deferred order pair proves the replacement values.
CREATE OR REPLACE FUNCTION trimmy.protect_paper_position() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy AS $$
DECLARE reset_revision bigint := 0;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF (NEW.user_id, NEW.asset_id, NEW.variant_mint)
        IS DISTINCT FROM (OLD.user_id, OLD.asset_id, OLD.variant_mint) THEN
      RAISE EXCEPTION 'Paper position identity is immutable' USING ERRCODE = '23514';
    END IF;
    SELECT a.last_reset_revision INTO reset_revision
      FROM trimmy.paper_accounts a WHERE a.user_id = NEW.user_id;
    IF NEW.last_order_revision <= OLD.last_order_revision OR NEW.updated_at <= OLD.updated_at
        OR (OLD.last_order_revision > coalesce(reset_revision, 0)
          AND NEW.locked_gain_micros < OLD.locked_gain_micros) THEN
      RAISE EXCEPTION 'Paper position history cannot move backwards' USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.protect_paper_position() FROM PUBLIC;

-- Preview arithmetic projects only the current desk cycle. Historical
-- position snapshots remain stored but become an exact zero baseline after a
-- reset boundary.
CREATE OR REPLACE FUNCTION trimmy.protect_paper_preview() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy AS $$
DECLARE a trimmy.paper_accounts%ROWTYPE;
DECLARE position_quantity numeric := 0;
DECLARE position_basis numeric := 0;
DECLARE expected_quantity numeric;
DECLARE expected_debit numeric := 0;
DECLARE expected_credit numeric := 0;
DECLARE expected_cash numeric;
DECLARE expected_position_quantity numeric;
DECLARE expected_position_basis numeric;
DECLARE allocated_basis numeric := 0;
DECLARE expected_realized numeric := 0;
DECLARE expected_locked numeric := 0;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.state <> 'open' OR NEW.committed_at IS NOT NULL THEN
      RAISE EXCEPTION 'Paper previews begin open' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO a FROM trimmy.paper_accounts WHERE user_id = NEW.user_id;
    IF NOT FOUND OR a.revision <> NEW.account_revision THEN
      RAISE EXCEPTION 'Paper preview must use the current account revision' USING ERRCODE = '23514';
    END IF;
    SELECT quantity_micros, cost_basis_micros INTO position_quantity, position_basis
      FROM trimmy.paper_positions WHERE user_id = NEW.user_id
        AND asset_id = NEW.asset_id AND variant_mint = NEW.variant_mint
        AND last_order_revision > a.last_reset_revision;
    IF NOT FOUND THEN position_quantity := 0; position_basis := 0; END IF;
    IF NEW.action = 'buy' THEN
      expected_quantity := CASE WHEN NEW.input_kind = 'paper_amount'
        THEN floor(NEW.input_amount_micros * 1000000 / NEW.price_micros)
        ELSE NEW.input_amount_micros END;
      expected_debit := ceil(NEW.price_micros * expected_quantity / 1000000);
      IF expected_quantity <= 0 OR expected_debit > a.cash_micros
          OR NEW.input_kind = 'paper_amount' AND expected_debit > NEW.input_amount_micros THEN
        RAISE EXCEPTION 'Paper buy cannot be covered by this account' USING ERRCODE = '23514';
      END IF;
      expected_cash := a.cash_micros - expected_debit;
      expected_position_quantity := position_quantity + expected_quantity;
      expected_position_basis := position_basis + expected_debit;
    ELSE
      IF NEW.input_kind <> 'share_quantity' OR NEW.input_amount_micros > position_quantity THEN
        RAISE EXCEPTION 'Paper sale exceeds its position' USING ERRCODE = '23514';
      END IF;
      expected_quantity := NEW.input_amount_micros;
      IF NEW.action = 'trim' AND expected_quantity = position_quantity THEN
        RAISE EXCEPTION 'Paper trim must retain part of its position' USING ERRCODE = '23514';
      END IF;
      expected_credit := floor(NEW.price_micros * expected_quantity / 1000000);
      allocated_basis := CASE WHEN expected_quantity = position_quantity THEN position_basis
        ELSE floor(position_basis * expected_quantity / position_quantity) END;
      expected_realized := expected_credit - allocated_basis;
      IF expected_credit <= 0 OR NEW.action = 'trim' AND expected_realized <= 0 THEN
        RAISE EXCEPTION 'Paper sale is too small or trim is not profitable' USING ERRCODE = '23514';
      END IF;
      expected_locked := CASE WHEN NEW.action = 'trim' THEN expected_realized ELSE 0 END;
      expected_cash := a.cash_micros + expected_credit;
      expected_position_quantity := position_quantity - expected_quantity;
      expected_position_basis := position_basis - allocated_basis;
    END IF;
    IF (NEW.quantity_micros, NEW.cash_debit_micros, NEW.cash_credit_micros, NEW.cash_after_micros,
        NEW.position_quantity_after_micros, NEW.position_cost_basis_after_micros,
        NEW.realized_gain_delta_micros, NEW.locked_gain_delta_micros)
       IS DISTINCT FROM
       (expected_quantity, expected_debit, expected_credit, expected_cash,
        expected_position_quantity, expected_position_basis, expected_realized, expected_locked) THEN
      RAISE EXCEPTION 'Paper preview arithmetic does not match the account' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
  END IF;
  IF (to_jsonb(NEW) - 'state' - 'committed_at') IS DISTINCT FROM
      (to_jsonb(OLD) - 'state' - 'committed_at') THEN
    RAISE EXCEPTION 'Paper preview terms are immutable' USING ERRCODE = '23514';
  END IF;
  IF OLD.state <> 'open' OR NEW.state <> 'committed' OR NEW.committed_at IS NULL
      OR NEW.committed_at >= NEW.expires_at THEN
    RAISE EXCEPTION 'Paper preview can only commit once before expiry' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.protect_paper_preview() FROM PUBLIC;

CREATE OR REPLACE FUNCTION trimmy.protect_paper_order() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy AS $$
DECLARE p trimmy.paper_order_previews%ROWTYPE;
DECLARE a trimmy.paper_accounts%ROWTYPE;
DECLARE position_quantity numeric := 0;
DECLARE position_basis numeric := 0;
DECLARE realized_before numeric := 0;
DECLARE locked_before numeric := 0;
BEGIN
  SELECT * INTO p FROM trimmy.paper_order_previews WHERE id = NEW.preview_id AND user_id = NEW.user_id;
  IF NOT FOUND OR p.state <> 'open' OR NEW.account_revision <> p.account_revision + 1
      OR NEW.committed_at >= p.expires_at
      OR (NEW.action, NEW.asset_id, NEW.variant_mint, NEW.symbol, NEW.price_micros, NEW.quantity_micros,
          NEW.cash_debit_micros, NEW.cash_credit_micros, NEW.cash_after_micros,
          NEW.position_quantity_after_micros, NEW.position_cost_basis_after_micros,
          NEW.realized_gain_delta_micros, NEW.locked_gain_delta_micros, NEW.price_source)
         IS DISTINCT FROM
         (p.action, p.asset_id, p.variant_mint, p.symbol, p.price_micros, p.quantity_micros,
          p.cash_debit_micros, p.cash_credit_micros, p.cash_after_micros,
          p.position_quantity_after_micros, p.position_cost_basis_after_micros,
          p.realized_gain_delta_micros, p.locked_gain_delta_micros, p.price_source) THEN
    RAISE EXCEPTION 'Paper order must exactly match its accepted preview' USING ERRCODE = '23514';
  END IF;
  SELECT * INTO a FROM trimmy.paper_accounts WHERE user_id = NEW.user_id;
  IF NOT FOUND OR a.revision <> p.account_revision OR a.cash_micros <> NEW.cash_before_micros THEN
    RAISE EXCEPTION 'Paper order must begin at the current account snapshot' USING ERRCODE = '23514';
  END IF;
  SELECT quantity_micros, cost_basis_micros, realized_gain_micros, locked_gain_micros
    INTO position_quantity, position_basis, realized_before, locked_before
    FROM trimmy.paper_positions WHERE user_id = NEW.user_id
      AND asset_id = NEW.asset_id AND variant_mint = NEW.variant_mint
      AND last_order_revision > a.last_reset_revision;
  IF NOT FOUND THEN
    position_quantity := 0; position_basis := 0; realized_before := 0; locked_before := 0;
  END IF;
  IF (NEW.position_quantity_before_micros, NEW.position_cost_basis_before_micros,
      NEW.realized_gain_before_micros, NEW.locked_gain_before_micros)
     IS DISTINCT FROM (position_quantity, position_basis, realized_before, locked_before) THEN
    RAISE EXCEPTION 'Paper order position start does not match storage' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.protect_paper_order() FROM PUBLIC;

CREATE OR REPLACE FUNCTION trimmy.check_paper_account_ledger() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy AS $$
DECLARE account_user uuid := NEW.user_id;
DECLARE a trimmy.paper_accounts%ROWTYPE;
DECLARE l trimmy.paper_cash_ledger%ROWTYPE;
DECLARE latest_reset bigint := 0;
BEGIN
  SELECT * INTO a FROM trimmy.paper_accounts WHERE user_id = account_user;
  SELECT * INTO l FROM trimmy.paper_cash_ledger WHERE user_id = account_user
    ORDER BY account_revision DESC LIMIT 1;
  SELECT coalesce(max(account_revision) FILTER (WHERE entry_kind = 'reset'), 0)
    INTO latest_reset FROM trimmy.paper_cash_ledger WHERE user_id = account_user;
  IF l.user_id IS NULL OR a.user_id IS NULL
      OR a.revision <> l.account_revision OR a.cash_micros <> l.balance_after_micros
      OR a.last_reset_revision <> latest_reset THEN
    RAISE EXCEPTION 'Paper cash snapshot and ledger do not agree' USING ERRCODE = '23514';
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.check_paper_account_ledger() FROM PUBLIC;

CREATE FUNCTION trimmy.check_paper_reset_pair() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  IF TG_TABLE_NAME = 'paper_reset_receipts' THEN
    IF NEW.outcome = 'reset' AND NOT EXISTS (
      SELECT 1 FROM trimmy.paper_cash_ledger l
      WHERE l.user_id = NEW.user_id AND l.account_revision = NEW.revision
        AND l.entry_kind = 'reset' AND l.order_id IS NULL
        AND l.reset_mutation_id = NEW.mutation_id
        AND l.balance_after_micros = NEW.cash_micros
        AND l.delta_micros = NEW.cash_micros - (
          SELECT previous.balance_after_micros
          FROM trimmy.paper_cash_ledger previous
          WHERE previous.user_id = NEW.user_id
            AND previous.account_revision = NEW.previous_revision)
        AND l.created_at = NEW.reset_at
    ) THEN
      RAISE EXCEPTION 'A paper reset receipt requires its cash ledger entry'
        USING ERRCODE = '23514', CONSTRAINT = 'paper_reset_ledger_pair';
    ELSIF NEW.outcome = 'not_needed' AND EXISTS (
      SELECT 1 FROM trimmy.paper_cash_ledger l
      WHERE l.user_id = NEW.user_id AND l.reset_mutation_id = NEW.mutation_id
    ) THEN
      RAISE EXCEPTION 'A no-op paper reset cannot have a cash ledger entry'
        USING ERRCODE = '23514', CONSTRAINT = 'paper_reset_ledger_pair';
    END IF;
  ELSIF NEW.entry_kind = 'reset' AND NOT EXISTS (
    SELECT 1 FROM trimmy.paper_reset_receipts r
    WHERE r.user_id = NEW.user_id AND r.mutation_id = NEW.reset_mutation_id
      AND r.outcome = 'reset' AND r.revision = NEW.account_revision
      AND r.cash_micros = NEW.balance_after_micros AND r.reset_at = NEW.created_at
  ) THEN
    RAISE EXCEPTION 'A paper reset cash entry requires its receipt'
      USING ERRCODE = '23514', CONSTRAINT = 'paper_reset_ledger_pair';
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.check_paper_reset_pair() FROM PUBLIC;
CREATE CONSTRAINT TRIGGER paper_reset_receipt_ledger_pair
  AFTER INSERT ON trimmy.paper_reset_receipts DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trimmy.check_paper_reset_pair();
CREATE CONSTRAINT TRIGGER paper_reset_ledger_receipt_pair
  AFTER INSERT ON trimmy.paper_cash_ledger DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trimmy.check_paper_reset_pair();

CREATE FUNCTION trimmy.paper_desk_reset(
  p_user_id uuid,
  p_mutation_id uuid,
  p_request_hash text,
  p_base_revision bigint
) RETURNS TABLE (
  outcome text,
  mutation_id uuid,
  previous_revision bigint,
  revision bigint,
  cash_micros numeric,
  reset_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE account_status text;
DECLARE account_row trimmy.paper_accounts%ROWTYPE;
DECLARE receipt_row trimmy.paper_reset_receipts%ROWTYPE;
DECLARE observed_at timestamptz;
DECLARE next_revision bigint;
DECLARE scoped_user uuid;
BEGIN
  IF p_user_id IS NULL OR p_mutation_id IS NULL OR p_request_hash IS NULL
      OR p_request_hash !~ '^[a-f0-9]{64}$' OR p_base_revision IS NULL
      OR p_base_revision < 0 OR p_base_revision > 9007199254740991 THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::bigint, NULL::bigint,
      NULL::numeric, NULL::timestamptz;
    RETURN;
  END IF;
  BEGIN
    scoped_user := nullif(current_setting('trimmy.practice_user_id', true), '')::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::bigint, NULL::bigint,
      NULL::numeric, NULL::timestamptz;
    RETURN;
  END;
  IF scoped_user IS DISTINCT FROM p_user_id THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::bigint, NULL::bigint,
      NULL::numeric, NULL::timestamptz;
    RETURN;
  END IF;

  -- Paper commits already acquire paper then Career through their triggers.
  -- Match that order so reset, commit, reasons and red-day reconstruction form
  -- one serial history without a lock cycle.
  PERFORM pg_advisory_xact_lock(hashtextextended('trimmy.paper:' || p_user_id::text, 0));
  PERFORM pg_advisory_xact_lock(hashtextextended('trimmy.career:' || p_user_id::text, 0));

  -- Replay is deliberately before every mutable account, revision and desk
  -- check. Closure or later activity cannot change a completed mutation.
  SELECT r.* INTO receipt_row FROM trimmy.paper_reset_receipts r
    WHERE r.user_id = p_user_id AND r.mutation_id = p_mutation_id;
  IF FOUND THEN
    IF receipt_row.request_hash <> p_request_hash THEN
      RETURN QUERY SELECT 'idempotency_conflict'::text, NULL::uuid, NULL::bigint,
        NULL::bigint, NULL::numeric, NULL::timestamptz;
    ELSE
      RETURN QUERY SELECT receipt_row.outcome, receipt_row.mutation_id,
        receipt_row.previous_revision, receipt_row.revision,
        receipt_row.cash_micros, receipt_row.reset_at;
    END IF;
    RETURN;
  END IF;

  SELECT u.status INTO account_status FROM trimmy.users u
    WHERE u.id = p_user_id FOR UPDATE;
  IF account_status IS DISTINCT FROM 'active' THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::uuid, NULL::bigint,
      NULL::bigint, NULL::numeric, NULL::timestamptz;
    RETURN;
  END IF;

  SELECT a.* INTO account_row FROM trimmy.paper_accounts a
    WHERE a.user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    IF p_base_revision <> 0 THEN
      RETURN QUERY SELECT 'stale_revision'::text, NULL::uuid, 0::bigint, 0::bigint,
        10000000000::numeric, NULL::timestamptz;
      RETURN;
    END IF;
    INSERT INTO trimmy.paper_reset_receipts(
      user_id, mutation_id, request_hash, outcome, previous_revision,
      revision, cash_micros, reset_at)
    VALUES (p_user_id, p_mutation_id, p_request_hash, 'not_needed', 0, 0,
      10000000000, NULL);
    RETURN QUERY SELECT 'not_needed'::text, p_mutation_id, 0::bigint, 0::bigint,
      10000000000::numeric, NULL::timestamptz;
    RETURN;
  END IF;

  IF account_row.revision <> p_base_revision THEN
    RETURN QUERY SELECT 'stale_revision'::text, NULL::uuid, account_row.revision,
      account_row.revision, account_row.cash_micros, NULL::timestamptz;
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM trimmy.paper_orders o
    WHERE o.user_id = p_user_id
      AND o.account_revision > account_row.last_reset_revision
  ) THEN
    INSERT INTO trimmy.paper_reset_receipts(
      user_id, mutation_id, request_hash, outcome, previous_revision,
      revision, cash_micros, reset_at)
    VALUES (p_user_id, p_mutation_id, p_request_hash, 'not_needed',
      account_row.revision, account_row.revision, 10000000000, NULL);
    RETURN QUERY SELECT 'not_needed'::text, p_mutation_id, account_row.revision,
      account_row.revision, 10000000000::numeric, NULL::timestamptz;
    RETURN;
  END IF;

  IF account_row.revision >= 9007199254740991 THEN
    RETURN QUERY SELECT 'revision_exhausted'::text, NULL::uuid,
      account_row.revision, account_row.revision, account_row.cash_micros,
      NULL::timestamptz;
    RETURN;
  END IF;

  next_revision := account_row.revision + 1;
  observed_at := greatest(date_trunc('milliseconds', clock_timestamp()),
    account_row.updated_at + interval '1 millisecond');
  INSERT INTO trimmy.paper_reset_receipts(
    user_id, mutation_id, request_hash, outcome, previous_revision,
    revision, cash_micros, reset_at)
  VALUES (p_user_id, p_mutation_id, p_request_hash, 'reset',
    account_row.revision, next_revision, 10000000000, observed_at);
  UPDATE trimmy.paper_accounts SET
    cash_micros = 10000000000,
    revision = next_revision,
    last_reset_revision = next_revision,
    updated_at = observed_at
  WHERE paper_accounts.user_id = p_user_id
    AND paper_accounts.revision = account_row.revision;
  INSERT INTO trimmy.paper_cash_ledger(
    user_id, account_revision, order_id, reset_mutation_id, entry_kind,
    delta_micros, balance_after_micros, created_at)
  VALUES (p_user_id, next_revision, NULL, p_mutation_id, 'reset',
    10000000000 - account_row.cash_micros, 10000000000, observed_at);
  RETURN QUERY SELECT 'reset'::text, p_mutation_id, account_row.revision,
    next_revision, 10000000000::numeric, observed_at;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.paper_desk_reset(uuid, uuid, text, bigint) FROM PUBLIC;

ALTER TABLE trimmy.paper_reset_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.paper_reset_receipts FORCE ROW LEVEL SECURITY;
CREATE POLICY paper_reset_receipt_scope ON trimmy.paper_reset_receipts
  USING (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid)
  WITH CHECK (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid);
REVOKE ALL ON TABLE trimmy.paper_reset_receipts FROM PUBLIC;

-- Guests receive a deliberately small reset budget. Authorization remains
-- bound to the same guest credential and account checks as the other paper
-- routes.
ALTER TABLE trimmy.guest_rate_windows
  DROP CONSTRAINT guest_rate_windows_scope_check;
ALTER TABLE trimmy.guest_rate_windows
  ADD CONSTRAINT guest_rate_windows_scope_check CHECK (scope IN (
    'paper_read', 'paper_preview', 'paper_commit', 'paper_reset',
    'refresh', 'claim', 'profile_read', 'profile_write',
    'career_read', 'career_write'));

CREATE OR REPLACE FUNCTION trimmy.guest_take_rate(
  selected_session uuid,
  selected_scope text,
  observed_at timestamptz
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE window_seconds integer; request_limit integer;
DECLARE window_start timestamptz; observed_count integer;
BEGIN
  IF selected_scope = 'paper_read' THEN window_seconds := 60; request_limit := 60;
  ELSIF selected_scope = 'paper_preview' THEN window_seconds := 600; request_limit := 20;
  ELSIF selected_scope = 'paper_commit' THEN window_seconds := 600; request_limit := 20;
  ELSIF selected_scope = 'paper_reset' THEN window_seconds := 3600; request_limit := 6;
  ELSIF selected_scope = 'profile_read' THEN window_seconds := 60; request_limit := 60;
  ELSIF selected_scope = 'profile_write' THEN window_seconds := 600; request_limit := 20;
  ELSIF selected_scope = 'career_read' THEN window_seconds := 60; request_limit := 60;
  ELSIF selected_scope = 'career_write' THEN window_seconds := 600; request_limit := 20;
  ELSIF selected_scope = 'refresh' THEN window_seconds := 3600; request_limit := 6;
  ELSIF selected_scope = 'claim' THEN window_seconds := 3600; request_limit := 6;
  ELSE RAISE EXCEPTION 'Guest rate scope is invalid' USING ERRCODE = '22023';
  END IF;
  IF selected_session IS NULL OR observed_at IS NULL OR NOT isfinite(observed_at) THEN
    RAISE EXCEPTION 'Guest rate input is invalid' USING ERRCODE = '22023';
  END IF;
  window_start := to_timestamp(
    floor(extract(epoch FROM observed_at) / window_seconds) * window_seconds);
  INSERT INTO trimmy.guest_rate_windows(
    guest_session_id, scope, window_started_at, request_count)
  VALUES (selected_session, selected_scope, window_start, 1)
  ON CONFLICT (guest_session_id, scope, window_started_at)
  DO UPDATE SET request_count = trimmy.guest_rate_windows.request_count + 1
  RETURNING request_count INTO observed_count;
  RETURN observed_count <= request_limit;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.guest_take_rate(uuid, text, timestamptz) FROM PUBLIC;

CREATE OR REPLACE FUNCTION trimmy.guest_authorize(selected_hash text, selected_scope text)
RETURNS TABLE (outcome text, user_id uuid, guest_id uuid, expires_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE session_row trimmy.guest_sessions%ROWTYPE; account_status text;
DECLARE observed_at timestamptz := clock_timestamp();
BEGIN
  IF selected_hash IS NULL OR selected_hash !~ '^[a-f0-9]{64}$'
      OR selected_scope NOT IN ('paper_read', 'paper_preview', 'paper_commit',
        'paper_reset', 'profile_read', 'profile_write', 'career_read', 'career_write') THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::uuid, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT s.* INTO session_row FROM trimmy.guest_sessions s
    WHERE s.credential_hash = selected_hash FOR UPDATE;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::uuid, NULL::timestamptz;
    RETURN;
  END IF;
  IF session_row.state <> 'active' THEN
    RETURN QUERY SELECT 'revoked'::text, NULL::uuid, session_row.id, session_row.expires_at;
    RETURN;
  END IF;
  IF observed_at >= session_row.expires_at OR observed_at >= session_row.hard_expires_at THEN
    UPDATE trimmy.guest_sessions SET state = 'revoked', revoked_at = observed_at,
      last_seen_at = greatest(last_seen_at, observed_at) WHERE id = session_row.id;
    RETURN QUERY SELECT 'expired'::text, NULL::uuid, session_row.id, session_row.expires_at;
    RETURN;
  END IF;
  SELECT u.status INTO account_status FROM trimmy.users u
    WHERE u.id = session_row.user_id FOR UPDATE;
  IF account_status IS DISTINCT FROM 'active' THEN
    RETURN QUERY SELECT 'unavailable'::text, NULL::uuid, session_row.id, session_row.expires_at;
    RETURN;
  END IF;
  IF NOT trimmy.guest_take_rate(session_row.id, selected_scope, observed_at) THEN
    RETURN QUERY SELECT 'rate_limited'::text, NULL::uuid, session_row.id, session_row.expires_at;
    RETURN;
  END IF;
  UPDATE trimmy.guest_sessions SET last_seen_at = greatest(last_seen_at, observed_at)
    WHERE id = session_row.id;
  RETURN QUERY SELECT 'authorized'::text, session_row.user_id,
    session_row.id, session_row.expires_at;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.guest_authorize(text, text) FROM PUBLIC;

-- A saved reason remains immutable and its exact mutation replay remains
-- valid. A new reason must cite a buy and held position from the current desk
-- cycle, so an unreasoned order cannot regain eligibility after a reset.
CREATE OR REPLACE FUNCTION trimmy.career_trade_reason_put(
  selected_user uuid,
  selected_mutation uuid,
  selected_hash text,
  selected_order uuid,
  selected_note text
) RETURNS TABLE (
  outcome text,
  order_id uuid,
  asset_id text,
  variant_mint text,
  note text,
  trims_awarded integer,
  daily_award_number smallint,
  saved_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE account_status text; order_row trimmy.paper_orders%ROWTYPE;
DECLARE paper_account trimmy.paper_accounts%ROWTYPE;
DECLARE receipt_row trimmy.career_reason_mutation_receipts%ROWTYPE;
DECLARE observed_at timestamptz;
DECLARE selected_time_zone text; today date; awarded_count integer; rolling_count integer;
DECLARE awarded integer; award_number smallint; career_revision bigint;
BEGIN
  IF selected_user IS NULL OR selected_mutation IS NULL OR selected_order IS NULL
      OR selected_hash IS NULL OR selected_hash !~ '^[a-f0-9]{64}$'
      OR selected_note IS NULL OR selected_note <> btrim(selected_note)
      OR char_length(selected_note) NOT BETWEEN 1 AND 180 OR selected_note ~ '[[:cntrl:]]' THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::text, NULL::text, NULL::text,
      NULL::integer, NULL::smallint, NULL::timestamptz;
    RETURN;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('trimmy.career:' || selected_user::text, 0));
  observed_at := date_trunc('milliseconds', clock_timestamp());
  SELECT u.status INTO account_status FROM trimmy.users u
    WHERE u.id = selected_user FOR UPDATE;
  IF account_status IS DISTINCT FROM 'active' THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::uuid, NULL::text, NULL::text, NULL::text,
      NULL::integer, NULL::smallint, NULL::timestamptz; RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM trimmy.product_profiles p WHERE p.user_id = selected_user) THEN
    RETURN QUERY SELECT 'profile_required'::text, NULL::uuid, NULL::text, NULL::text, NULL::text,
      NULL::integer, NULL::smallint, NULL::timestamptz; RETURN;
  END IF;
  SELECT r.* INTO receipt_row FROM trimmy.career_reason_mutation_receipts r
    WHERE r.user_id = selected_user AND r.mutation_id = selected_mutation;
  IF FOUND THEN
    IF receipt_row.request_hash <> selected_hash THEN
      RETURN QUERY SELECT 'idempotency_conflict'::text, NULL::uuid, NULL::text, NULL::text,
        NULL::text, NULL::integer, NULL::smallint, NULL::timestamptz;
    ELSE
      RETURN QUERY SELECT 'saved'::text, receipt_row.order_id, receipt_row.asset_id,
        receipt_row.variant_mint::text, receipt_row.note, receipt_row.trims_awarded,
        receipt_row.daily_award_number, receipt_row.saved_at;
    END IF;
    RETURN;
  END IF;
  SELECT o.* INTO order_row FROM trimmy.paper_orders o
    WHERE o.user_id = selected_user AND o.id = selected_order;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'order_missing'::text, NULL::uuid, NULL::text, NULL::text, NULL::text,
      NULL::integer, NULL::smallint, NULL::timestamptz; RETURN;
  END IF;
  IF order_row.action <> 'buy' THEN
    RETURN QUERY SELECT 'buy_required'::text, NULL::uuid, NULL::text, NULL::text, NULL::text,
      NULL::integer, NULL::smallint, NULL::timestamptz; RETURN;
  END IF;
  SELECT a.* INTO paper_account FROM trimmy.paper_accounts a
    WHERE a.user_id = selected_user;
  IF NOT FOUND OR order_row.account_revision <= paper_account.last_reset_revision
      OR NOT EXISTS (
        SELECT 1 FROM trimmy.paper_positions p
        WHERE p.user_id = selected_user AND p.asset_id = order_row.asset_id
          AND p.variant_mint = order_row.variant_mint
          AND p.last_order_revision > paper_account.last_reset_revision
          AND p.quantity_micros > 0
      ) THEN
    RETURN QUERY SELECT 'position_required'::text, NULL::uuid, NULL::text, NULL::text, NULL::text,
      NULL::integer, NULL::smallint, NULL::timestamptz; RETURN;
  END IF;
  IF EXISTS (SELECT 1 FROM trimmy.career_trade_reasons r WHERE r.order_id = selected_order) THEN
    RETURN QUERY SELECT 'reason_exists'::text, NULL::uuid, NULL::text, NULL::text, NULL::text,
      NULL::integer, NULL::smallint, NULL::timestamptz; RETURN;
  END IF;
  selected_time_zone := trimmy.career_time_zone(selected_user);
  today := (observed_at AT TIME ZONE selected_time_zone)::date;
  SELECT count(*) FILTER (
      WHERE (r.saved_at AT TIME ZONE selected_time_zone)::date = today
    )::integer,
    count(*) FILTER (WHERE r.saved_at > observed_at - interval '24 hours')::integer
    INTO awarded_count, rolling_count
    FROM trimmy.career_trade_reasons r
    WHERE r.user_id = selected_user AND r.trims_awarded = 10;
  IF awarded_count < 3 AND rolling_count < 3 THEN
    awarded := 10; award_number := (awarded_count + 1)::smallint;
  ELSE
    awarded := 0; award_number := NULL;
  END IF;
  BEGIN
    career_revision := trimmy.career_record_activity(selected_user, today, awarded, observed_at);
  EXCEPTION WHEN numeric_value_out_of_range THEN
    RETURN QUERY SELECT 'revision_exhausted'::text, NULL::uuid, NULL::text, NULL::text,
      NULL::text, NULL::integer, NULL::smallint, NULL::timestamptz; RETURN;
  END;
  INSERT INTO trimmy.career_trade_reasons(
    order_id, user_id, asset_id, variant_mint, note, trims_awarded,
    daily_award_number, saved_at)
  VALUES (selected_order, selected_user, order_row.asset_id, order_row.variant_mint,
    selected_note, awarded, award_number, observed_at);
  IF awarded > 0 THEN
    INSERT INTO trimmy.career_trim_ledger(
      user_id, career_revision, entry_kind, source_id, trims, awarded_on, created_at)
    VALUES (selected_user, career_revision, 'paper-reason', selected_order,
      awarded, today, observed_at);
  END IF;
  INSERT INTO trimmy.career_reason_mutation_receipts(
    user_id, mutation_id, request_hash, order_id, asset_id, variant_mint, note,
    trims_awarded, daily_award_number, saved_at)
  VALUES (selected_user, selected_mutation, selected_hash, selected_order,
    order_row.asset_id, order_row.variant_mint, selected_note,
    awarded, award_number, observed_at);
  RETURN QUERY SELECT 'saved'::text, selected_order, order_row.asset_id,
    order_row.variant_mint::text, selected_note, awarded, award_number, observed_at;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_trade_reason_put(uuid, uuid, text, uuid, text) FROM PUBLIC;

-- Reset-aware historical projections used by red-day evidence. A reset before
-- the open replaces the opening position with zero until a later order. A
-- reset at or before the close contributes an explicit zero to the session
-- minimum; a reset after the close is irrelevant.
CREATE FUNCTION trimmy.paper_cycle_position_before(
  selected_user uuid,
  selected_asset text,
  selected_variant trimmy.solana_address,
  boundary_at timestamptz
) RETURNS TABLE (order_id uuid, quantity_micros numeric)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
  WITH latest_reset AS (
    SELECT max(r.reset_at) AS reset_at
    FROM trimmy.paper_reset_receipts r
    WHERE r.user_id = selected_user AND r.outcome = 'reset'
      AND r.reset_at < boundary_at
  )
  SELECT o.id, o.position_quantity_after_micros
  FROM trimmy.paper_orders o CROSS JOIN latest_reset r
  WHERE o.user_id = selected_user AND o.asset_id = selected_asset
    AND o.variant_mint = selected_variant AND o.committed_at < boundary_at
    AND (r.reset_at IS NULL OR o.committed_at > r.reset_at)
  ORDER BY o.committed_at DESC, o.account_revision DESC, o.id DESC
  LIMIT 1;
$$;
REVOKE ALL ON FUNCTION trimmy.paper_cycle_position_before(
  uuid, text, trimmy.solana_address, timestamptz) FROM PUBLIC;

CREATE FUNCTION trimmy.paper_cycle_minimum_during(
  selected_user uuid,
  selected_asset text,
  selected_variant trimmy.solana_address,
  opening_quantity numeric,
  session_open timestamptz,
  session_close timestamptz
) RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
  SELECT least(opening_quantity,
    coalesce(min(change.quantity_micros), opening_quantity))
  FROM (
    SELECT o.position_quantity_after_micros AS quantity_micros
    FROM trimmy.paper_orders o
    WHERE o.user_id = selected_user AND o.asset_id = selected_asset
      AND o.variant_mint = selected_variant
      AND o.committed_at >= session_open AND o.committed_at <= session_close
    UNION ALL
    SELECT 0::numeric
    FROM trimmy.paper_reset_receipts r
    WHERE r.user_id = selected_user AND r.outcome = 'reset'
      AND r.reset_at >= session_open AND r.reset_at <= session_close
  ) change;
$$;
REVOKE ALL ON FUNCTION trimmy.paper_cycle_minimum_during(
  uuid, text, trimmy.solana_address, numeric, timestamptz, timestamptz) FROM PUBLIC;

CREATE OR REPLACE FUNCTION trimmy.check_career_red_day_user_evidence() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE observation_row trimmy.career_red_day_provider_observations%ROWTYPE;
DECLARE expected_open timestamptz; expected_close timestamptz;
DECLARE expected_opening_order uuid;
DECLARE expected_opening numeric := 0; expected_minimum numeric := 0;
DECLARE expected_outcome text; expected_reason text;
BEGIN
  SELECT o.* INTO observation_row
  FROM trimmy.career_red_day_sessions s
  JOIN trimmy.career_red_day_provider_observations o
    ON o.observation_id = s.observation_id
  WHERE s.observation_id = NEW.observation_id;
  IF NOT FOUND OR observation_row.observation_status <> 'verified-red'
      OR (NEW.asset_id, NEW.listed_symbol, NEW.market_date, NEW.recorded_at)
        IS DISTINCT FROM
        (observation_row.asset_id, observation_row.listed_symbol,
          observation_row.market_date, observation_row.observed_at) THEN
    RAISE EXCEPTION 'User red-day evidence does not match its market observation'
      USING ERRCODE = '23514', CONSTRAINT = 'career_red_day_user_evidence';
  END IF;
  expected_open := trimmy.career_red_day_session_open(NEW.market_date);
  expected_close := trimmy.career_red_day_session_close(NEW.market_date);
  IF (NEW.session_open_at, NEW.session_close_at)
      IS DISTINCT FROM (expected_open, expected_close) THEN
    RAISE EXCEPTION 'User red-day evidence has the wrong New York session window'
      USING ERRCODE = '23514', CONSTRAINT = 'career_red_day_user_evidence';
  END IF;
  SELECT p.order_id, p.quantity_micros
    INTO expected_opening_order, expected_opening
  FROM trimmy.paper_cycle_position_before(
    NEW.user_id, NEW.asset_id, NEW.variant_mint, expected_open) p;
  IF NOT FOUND THEN
    expected_opening_order := NULL;
    expected_opening := 0;
  END IF;
  expected_minimum := trimmy.paper_cycle_minimum_during(
    NEW.user_id, NEW.asset_id, NEW.variant_mint, expected_opening,
    expected_open, expected_close);
  IF expected_opening > 0 AND expected_minimum > 0 THEN
    expected_outcome := 'qualified'; expected_reason := NULL;
  ELSIF expected_opening <= 0 THEN
    expected_outcome := 'not-held-throughout'; expected_reason := 'not-positive-at-open';
  ELSE
    expected_outcome := 'not-held-throughout'; expected_reason := 'position-reached-zero';
  END IF;
  IF (NEW.opening_order_id, NEW.opening_quantity_micros,
      NEW.minimum_session_quantity_micros, NEW.evidence_outcome, NEW.reason_code)
      IS DISTINCT FROM
      (expected_opening_order, expected_opening, expected_minimum,
        expected_outcome, expected_reason) THEN
    RAISE EXCEPTION 'User red-day evidence does not match immutable paper history'
      USING ERRCODE = '23514', CONSTRAINT = 'career_red_day_user_evidence';
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.check_career_red_day_user_evidence() FROM PUBLIC;

CREATE OR REPLACE FUNCTION trimmy.career_red_day_process_session(
  selected_observation uuid,
  selected_limit integer
) RETURNS TABLE (
  outcome text,
  observation_id uuid,
  evidence_count bigint,
  completed_count bigint,
  processing_complete boolean
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE session_row trimmy.career_red_day_sessions%ROWTYPE;
DECLARE observation_row trimmy.career_red_day_provider_observations%ROWTYPE;
DECLARE candidate record; opening_order uuid;
DECLARE session_open timestamptz; session_close timestamptz;
DECLARE opening_quantity numeric; minimum_quantity numeric;
DECLARE evidence_outcome text; evidence_reason text; completion_outcome text;
DECLARE selected_evidence uuid; last_user uuid; last_variant text;
DECLARE recorded_evidence bigint := 0; recorded_completions bigint := 0;
DECLARE work_remaining boolean := false;
DECLARE account_status text;
BEGIN
  IF selected_observation IS NULL OR selected_limit IS NULL
      OR selected_limit < 1 OR selected_limit > 100 THEN
    RAISE EXCEPTION 'Red-day processing request is invalid'
      USING ERRCODE = '22023', CONSTRAINT = 'career_red_day_processing_input';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'trimmy.red-day:processing:' || selected_observation::text, 0));
  SELECT s.* INTO session_row FROM trimmy.career_red_day_sessions s
  WHERE s.observation_id = selected_observation FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Red-day session does not exist'
      USING ERRCODE = '22023', CONSTRAINT = 'career_red_day_processing_input';
  END IF;
  IF session_row.processing_complete THEN
    RETURN QUERY SELECT 'already-complete'::text, selected_observation,
      0::bigint, 0::bigint, true;
    RETURN;
  END IF;
  SELECT o.* INTO STRICT observation_row
  FROM trimmy.career_red_day_provider_observations o
  WHERE o.observation_id = selected_observation;
  IF observation_row.observation_status <> 'verified-red' OR NOT EXISTS (
      SELECT 1 FROM trimmy.career_mission_definitions d
      WHERE d.id = 'hold-through-red-day' AND d.evidence_kind = 'server-red-day-hold'
        AND d.evidence_live) THEN
    RAISE EXCEPTION 'Red-day processing is not activated for this session'
      USING ERRCODE = '55000', CONSTRAINT = 'career_red_day_processing_activation';
  END IF;
  session_open := trimmy.career_red_day_session_open(session_row.market_date);
  session_close := trimmy.career_red_day_session_close(session_row.market_date);

  FOR candidate IN
    SELECT DISTINCT o.user_id, o.variant_mint
    FROM trimmy.paper_orders o
    JOIN trimmy.users u ON u.id = o.user_id AND u.status = 'active'
    JOIN trimmy.career_profiles p ON p.user_id = o.user_id AND p.rank_id = 'rookie'
    WHERE o.asset_id = session_row.asset_id
      AND (session_row.processing_cursor_user_id IS NULL OR
        (o.user_id, o.variant_mint) >
          (session_row.processing_cursor_user_id, session_row.processing_cursor_variant_mint))
    ORDER BY o.user_id, o.variant_mint
    LIMIT selected_limit
  LOOP
    last_user := candidate.user_id;
    last_variant := candidate.variant_mint;
    -- Paper commits and resets both take paper before Career. Match them so
    -- reconstruction observes one complete serial history.
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'trimmy.paper:' || candidate.user_id::text, 0));
    PERFORM pg_advisory_xact_lock(hashtextextended(
      'trimmy.career:' || candidate.user_id::text, 0));
    SELECT u.status INTO account_status FROM trimmy.users u
    WHERE u.id = candidate.user_id FOR UPDATE;
    IF account_status IS DISTINCT FROM 'active'
        OR NOT EXISTS (
          SELECT 1 FROM trimmy.career_profiles p
          WHERE p.user_id = candidate.user_id AND p.rank_id = 'rookie')
        OR NOT EXISTS (
          SELECT 1 FROM trimmy.career_mission_completions c
          WHERE c.user_id = candidate.user_id AND c.mission_id = 'first-paper-buy'
            AND c.completed_at <= session_close)
        OR NOT EXISTS (
          SELECT 1 FROM trimmy.career_mission_completions c
          WHERE c.user_id = candidate.user_id AND c.mission_id = 'write-a-reason'
            AND c.completed_at <= session_close)
        OR EXISTS (
          SELECT 1 FROM trimmy.career_mission_completions c
          WHERE c.user_id = candidate.user_id AND c.mission_id = 'hold-through-red-day') THEN
      CONTINUE;
    END IF;
    opening_order := NULL;
    opening_quantity := 0;
    SELECT p.order_id, p.quantity_micros
      INTO opening_order, opening_quantity
    FROM trimmy.paper_cycle_position_before(candidate.user_id,
      session_row.asset_id, candidate.variant_mint, session_open) p;
    IF NOT FOUND THEN
      opening_order := NULL;
      opening_quantity := 0;
    END IF;
    minimum_quantity := trimmy.paper_cycle_minimum_during(candidate.user_id,
      session_row.asset_id, candidate.variant_mint, opening_quantity,
      session_open, session_close);
    IF opening_quantity > 0 AND minimum_quantity > 0 THEN
      evidence_outcome := 'qualified'; evidence_reason := NULL;
    ELSIF opening_quantity <= 0 THEN
      evidence_outcome := 'not-held-throughout'; evidence_reason := 'not-positive-at-open';
    ELSE
      evidence_outcome := 'not-held-throughout'; evidence_reason := 'position-reached-zero';
    END IF;
    selected_evidence := gen_random_uuid();
    INSERT INTO trimmy.career_red_day_user_evidence(
      evidence_id, observation_id, user_id, asset_id, variant_mint,
      listed_symbol, market_date, session_open_at, session_close_at,
      opening_order_id, opening_quantity_micros, minimum_session_quantity_micros,
      evidence_outcome, reason_code, recorded_at)
    VALUES (selected_evidence, selected_observation, candidate.user_id,
      session_row.asset_id, candidate.variant_mint, observation_row.listed_symbol,
      session_row.market_date, session_open, session_close, opening_order,
      opening_quantity, minimum_quantity, evidence_outcome, evidence_reason,
      observation_row.observed_at);
    recorded_evidence := recorded_evidence + 1;
    IF evidence_outcome = 'qualified' THEN
      SELECT trimmy.career_server_mission_complete(candidate.user_id,
        'hold-through-red-day', selected_evidence, observation_row.observed_at)
      INTO completion_outcome;
      IF completion_outcome <> 'completed' THEN
        RAISE EXCEPTION 'Qualified red-day mission could not be completed: %', completion_outcome
          USING ERRCODE = '23514', CONSTRAINT = 'career_red_day_completion';
      END IF;
      recorded_completions := recorded_completions + 1;
    END IF;
  END LOOP;

  IF last_user IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1
      FROM trimmy.paper_orders o
      JOIN trimmy.users u ON u.id = o.user_id AND u.status = 'active'
      JOIN trimmy.career_profiles p ON p.user_id = o.user_id AND p.rank_id = 'rookie'
      WHERE o.asset_id = session_row.asset_id
        AND (o.user_id, o.variant_mint) > (last_user, last_variant)
    ) INTO work_remaining;
  END IF;
  UPDATE trimmy.career_red_day_sessions SET
    processing_cursor_user_id = coalesce(last_user, processing_cursor_user_id),
    processing_cursor_variant_mint = coalesce(last_variant, processing_cursor_variant_mint),
    processing_complete = NOT work_remaining,
    processing_completed_at = CASE WHEN work_remaining THEN NULL
      ELSE date_trunc('milliseconds', clock_timestamp()) END
  WHERE career_red_day_sessions.observation_id = selected_observation;
  RETURN QUERY SELECT CASE WHEN work_remaining THEN 'processed' ELSE 'complete' END,
    selected_observation, recorded_evidence, recorded_completions, NOT work_remaining;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_red_day_process_session(uuid, integer) FROM PUBLIC;

INSERT INTO trimmy.schema_migrations(version) VALUES ('0023_paper_reset');
COMMIT;
