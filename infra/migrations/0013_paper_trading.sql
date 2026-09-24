-- 0013: account-scoped paper cash, positions, short-lived price previews and
-- committed paper orders. No wallet, token amount, transaction or live-money
-- execution appears in this schema. Every amount is an exact six-decimal
-- integer and the initial paper grant is 10,000 units (10,000,000,000 micros).
BEGIN;

CREATE TABLE trimmy.paper_accounts (
  user_id uuid PRIMARY KEY REFERENCES trimmy.users(id),
  starting_cash_micros numeric(30,0) NOT NULL DEFAULT 10000000000
    CHECK (starting_cash_micros = 10000000000),
  cash_micros numeric(30,0) NOT NULL DEFAULT 10000000000
    CHECK (cash_micros BETWEEN 0 AND 999999999999999),
  revision bigint NOT NULL DEFAULT 0 CHECK (revision BETWEEN 0 AND 9007199254740991),
  opened_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL,
  CHECK (isfinite(opened_at) AND isfinite(updated_at) AND updated_at >= opened_at)
);

CREATE TABLE trimmy.paper_positions (
  user_id uuid NOT NULL REFERENCES trimmy.paper_accounts(user_id),
  asset_id text NOT NULL CHECK (asset_id ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND length(asset_id) <= 100),
  variant_mint trimmy.solana_address NOT NULL,
  symbol text NOT NULL CHECK (length(symbol) BETWEEN 1 AND 30 AND symbol = btrim(symbol)),
  quantity_micros numeric(30,0) NOT NULL CHECK (quantity_micros BETWEEN 0 AND 999999999999999),
  cost_basis_micros numeric(30,0) NOT NULL CHECK (cost_basis_micros BETWEEN 0 AND 999999999999999),
  realized_gain_micros numeric(30,0) NOT NULL DEFAULT 0
    CHECK (realized_gain_micros BETWEEN -999999999999999 AND 999999999999999),
  locked_gain_micros numeric(30,0) NOT NULL DEFAULT 0
    CHECK (locked_gain_micros BETWEEN 0 AND 999999999999999),
  last_order_revision bigint NOT NULL CHECK (last_order_revision BETWEEN 1 AND 9007199254740991),
  updated_at timestamptz NOT NULL CHECK (isfinite(updated_at)),
  PRIMARY KEY (user_id, asset_id, variant_mint),
  CHECK ((quantity_micros = 0) = (cost_basis_micros = 0))
);

CREATE TABLE trimmy.paper_order_previews (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES trimmy.paper_accounts(user_id),
  request_id uuid NOT NULL,
  request_hash trimmy.sha256_hex NOT NULL,
  account_revision bigint NOT NULL CHECK (account_revision BETWEEN 0 AND 9007199254740990),
  action text NOT NULL CHECK (action IN ('buy', 'sell', 'trim')),
  input_kind text NOT NULL CHECK (input_kind IN ('paper_amount', 'share_quantity')),
  input_amount_micros numeric(30,0) NOT NULL CHECK (input_amount_micros BETWEEN 1 AND 999999999999999),
  asset_id text NOT NULL CHECK (asset_id ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND length(asset_id) <= 100),
  variant_mint trimmy.solana_address NOT NULL,
  symbol text NOT NULL CHECK (length(symbol) BETWEEN 1 AND 30 AND symbol = btrim(symbol)),
  price_micros numeric(30,0) NOT NULL CHECK (price_micros BETWEEN 1 AND 999999999999999),
  quantity_micros numeric(30,0) NOT NULL CHECK (quantity_micros BETWEEN 1 AND 999999999999999),
  cash_debit_micros numeric(30,0) NOT NULL CHECK (cash_debit_micros BETWEEN 0 AND 999999999999999),
  cash_credit_micros numeric(30,0) NOT NULL CHECK (cash_credit_micros BETWEEN 0 AND 999999999999999),
  cash_after_micros numeric(30,0) NOT NULL CHECK (cash_after_micros BETWEEN 0 AND 999999999999999),
  position_quantity_after_micros numeric(30,0) NOT NULL
    CHECK (position_quantity_after_micros BETWEEN 0 AND 999999999999999),
  position_cost_basis_after_micros numeric(30,0) NOT NULL
    CHECK (position_cost_basis_after_micros BETWEEN 0 AND 999999999999999),
  realized_gain_delta_micros numeric(30,0) NOT NULL
    CHECK (realized_gain_delta_micros BETWEEN -999999999999999 AND 999999999999999),
  locked_gain_delta_micros numeric(30,0) NOT NULL
    CHECK (locked_gain_delta_micros BETWEEN 0 AND 999999999999999),
  price_source jsonb NOT NULL CHECK (
    jsonb_typeof(price_source) = 'object'
    AND price_source->>'provider' = 'tokens-xyz-v1'
    AND jsonb_typeof(price_source->'providerTimestamps') = 'object'
    AND price_source->'providerTimestamps'->>'unit' = 'not_declared'
    AND length(price_source->>'providerReference') BETWEEN 1 AND 300),
  accepted_at timestamptz NOT NULL CHECK (isfinite(accepted_at)),
  expires_at timestamptz NOT NULL CHECK (isfinite(expires_at) AND expires_at > accepted_at
    AND expires_at <= accepted_at + interval '60 seconds'),
  state text NOT NULL DEFAULT 'open' CHECK (state IN ('open', 'committed')),
  committed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (id, user_id),
  UNIQUE (user_id, request_id),
  CHECK ((state = 'committed') = (committed_at IS NOT NULL)),
  CHECK (accepted_at BETWEEN created_at - interval '15 seconds' AND created_at + interval '5 seconds'),
  CHECK ((price_source->>'acceptedAt')::timestamptz = accepted_at),
  CHECK ((price_source->>'observedAt')::timestamptz
    BETWEEN accepted_at - interval '10 seconds' AND accepted_at + interval '5 seconds'),
  CHECK (committed_at IS NULL OR committed_at >= accepted_at),
  CHECK ((action = 'buy' AND cash_debit_micros > 0 AND cash_credit_micros = 0
      AND realized_gain_delta_micros = 0 AND locked_gain_delta_micros = 0)
    OR (action IN ('sell', 'trim') AND input_kind = 'share_quantity'
      AND cash_debit_micros = 0 AND cash_credit_micros > 0)),
  CHECK (action <> 'trim' OR locked_gain_delta_micros = realized_gain_delta_micros
    AND locked_gain_delta_micros > 0),
  CHECK ((position_quantity_after_micros = 0) = (position_cost_basis_after_micros = 0))
);
CREATE INDEX paper_previews_open ON trimmy.paper_order_previews (user_id, expires_at) WHERE state = 'open';

CREATE TABLE trimmy.paper_orders (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES trimmy.paper_accounts(user_id),
  preview_id uuid NOT NULL,
  idempotency_key uuid NOT NULL,
  request_hash trimmy.sha256_hex NOT NULL,
  account_revision bigint NOT NULL CHECK (account_revision BETWEEN 1 AND 9007199254740991),
  action text NOT NULL CHECK (action IN ('buy', 'sell', 'trim')),
  asset_id text NOT NULL CHECK (asset_id ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND length(asset_id) <= 100),
  variant_mint trimmy.solana_address NOT NULL,
  symbol text NOT NULL CHECK (length(symbol) BETWEEN 1 AND 30 AND symbol = btrim(symbol)),
  price_micros numeric(30,0) NOT NULL CHECK (price_micros BETWEEN 1 AND 999999999999999),
  quantity_micros numeric(30,0) NOT NULL CHECK (quantity_micros BETWEEN 1 AND 999999999999999),
  cash_debit_micros numeric(30,0) NOT NULL CHECK (cash_debit_micros BETWEEN 0 AND 999999999999999),
  cash_credit_micros numeric(30,0) NOT NULL CHECK (cash_credit_micros BETWEEN 0 AND 999999999999999),
  cash_before_micros numeric(30,0) NOT NULL CHECK (cash_before_micros BETWEEN 0 AND 999999999999999),
  cash_after_micros numeric(30,0) NOT NULL CHECK (cash_after_micros BETWEEN 0 AND 999999999999999),
  position_quantity_before_micros numeric(30,0) NOT NULL
    CHECK (position_quantity_before_micros BETWEEN 0 AND 999999999999999),
  position_quantity_after_micros numeric(30,0) NOT NULL
    CHECK (position_quantity_after_micros BETWEEN 0 AND 999999999999999),
  position_cost_basis_before_micros numeric(30,0) NOT NULL
    CHECK (position_cost_basis_before_micros BETWEEN 0 AND 999999999999999),
  position_cost_basis_after_micros numeric(30,0) NOT NULL
    CHECK (position_cost_basis_after_micros BETWEEN 0 AND 999999999999999),
  realized_gain_before_micros numeric(30,0) NOT NULL
    CHECK (realized_gain_before_micros BETWEEN -999999999999999 AND 999999999999999),
  realized_gain_delta_micros numeric(30,0) NOT NULL
    CHECK (realized_gain_delta_micros BETWEEN -999999999999999 AND 999999999999999),
  realized_gain_after_micros numeric(30,0) NOT NULL
    CHECK (realized_gain_after_micros BETWEEN -999999999999999 AND 999999999999999),
  locked_gain_before_micros numeric(30,0) NOT NULL
    CHECK (locked_gain_before_micros BETWEEN 0 AND 999999999999999),
  locked_gain_delta_micros numeric(30,0) NOT NULL
    CHECK (locked_gain_delta_micros BETWEEN 0 AND 999999999999999),
  locked_gain_after_micros numeric(30,0) NOT NULL
    CHECK (locked_gain_after_micros BETWEEN 0 AND 999999999999999),
  price_source jsonb NOT NULL CHECK (jsonb_typeof(price_source) = 'object'
    AND price_source->>'provider' = 'tokens-xyz-v1'),
  committed_at timestamptz NOT NULL CHECK (isfinite(committed_at)),
  UNIQUE (id, user_id),
  UNIQUE (preview_id),
  UNIQUE (user_id, idempotency_key),
  FOREIGN KEY (preview_id, user_id) REFERENCES trimmy.paper_order_previews(id, user_id),
  CHECK (account_revision > 0),
  CHECK (cash_after_micros = cash_before_micros - cash_debit_micros + cash_credit_micros),
  CHECK (realized_gain_after_micros = realized_gain_before_micros + realized_gain_delta_micros),
  CHECK (locked_gain_after_micros = locked_gain_before_micros + locked_gain_delta_micros),
  CHECK ((position_quantity_after_micros = 0) = (position_cost_basis_after_micros = 0))
);
CREATE INDEX paper_orders_recent ON trimmy.paper_orders (user_id, committed_at DESC, id DESC);

CREATE TABLE trimmy.paper_cash_ledger (
  user_id uuid NOT NULL REFERENCES trimmy.paper_accounts(user_id),
  account_revision bigint NOT NULL CHECK (account_revision BETWEEN 0 AND 9007199254740991),
  order_id uuid,
  entry_kind text NOT NULL CHECK (entry_kind IN ('initial', 'buy', 'sell', 'trim')),
  delta_micros numeric(30,0) NOT NULL
    CHECK (delta_micros BETWEEN -999999999999999 AND 999999999999999),
  balance_after_micros numeric(30,0) NOT NULL CHECK (balance_after_micros BETWEEN 0 AND 999999999999999),
  created_at timestamptz NOT NULL CHECK (isfinite(created_at)),
  PRIMARY KEY (user_id, account_revision),
  UNIQUE (order_id),
  FOREIGN KEY (order_id, user_id) REFERENCES trimmy.paper_orders(id, user_id),
  CHECK ((account_revision = 0 AND order_id IS NULL AND entry_kind = 'initial'
      AND delta_micros = 10000000000 AND balance_after_micros = 10000000000)
    OR (account_revision > 0 AND order_id IS NOT NULL AND entry_kind <> 'initial'))
);

CREATE FUNCTION trimmy.protect_paper_account() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, trimmy AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM trimmy.users WHERE id = NEW.user_id AND status = 'active') THEN
    RAISE EXCEPTION 'Paper trading requires an active account' USING ERRCODE = '23514', CONSTRAINT = 'paper_account_active';
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.revision <> 0 OR NEW.cash_micros <> 10000000000 OR NEW.starting_cash_micros <> 10000000000
        OR NEW.updated_at <> NEW.opened_at THEN
      RAISE EXCEPTION 'Paper accounts begin at the exact initial grant' USING ERRCODE = '23514';
    END IF;
  ELSE
    IF (NEW.user_id, NEW.starting_cash_micros, NEW.opened_at)
        IS DISTINCT FROM (OLD.user_id, OLD.starting_cash_micros, OLD.opened_at) THEN
      RAISE EXCEPTION 'Paper account identity and opening are immutable' USING ERRCODE = '23514';
    END IF;
    IF NEW.revision <> OLD.revision + 1 OR NEW.updated_at <= OLD.updated_at THEN
      RAISE EXCEPTION 'Paper account revision must advance exactly once' USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.protect_paper_account() FROM PUBLIC;
CREATE TRIGGER paper_account_guard BEFORE INSERT OR UPDATE ON trimmy.paper_accounts
  FOR EACH ROW EXECUTE FUNCTION trimmy.protect_paper_account();

CREATE FUNCTION trimmy.protect_paper_position() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy AS $$
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF (NEW.user_id, NEW.asset_id, NEW.variant_mint)
        IS DISTINCT FROM (OLD.user_id, OLD.asset_id, OLD.variant_mint) THEN
      RAISE EXCEPTION 'Paper position identity is immutable' USING ERRCODE = '23514';
    END IF;
    IF NEW.last_order_revision <= OLD.last_order_revision OR NEW.updated_at <= OLD.updated_at
        OR NEW.locked_gain_micros < OLD.locked_gain_micros THEN
      RAISE EXCEPTION 'Paper position history cannot move backwards' USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.protect_paper_position() FROM PUBLIC;
CREATE TRIGGER paper_position_guard BEFORE INSERT OR UPDATE ON trimmy.paper_positions
  FOR EACH ROW EXECUTE FUNCTION trimmy.protect_paper_position();

CREATE FUNCTION trimmy.protect_paper_preview() RETURNS trigger
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
        AND asset_id = NEW.asset_id AND variant_mint = NEW.variant_mint;
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
CREATE TRIGGER paper_preview_guard BEFORE INSERT OR UPDATE ON trimmy.paper_order_previews
  FOR EACH ROW EXECUTE FUNCTION trimmy.protect_paper_preview();

CREATE FUNCTION trimmy.protect_paper_order() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy AS $$
DECLARE p trimmy.paper_order_previews%ROWTYPE;
DECLARE a trimmy.paper_accounts%ROWTYPE;
DECLARE position_quantity numeric := 0;
DECLARE position_basis numeric := 0;
DECLARE realized_before numeric := 0;
DECLARE locked_before numeric := 0;
BEGIN
  SELECT * INTO p FROM trimmy.paper_order_previews WHERE id = NEW.preview_id AND user_id = NEW.user_id;
  IF NOT FOUND OR p.state <> 'open' OR NEW.account_revision <> p.account_revision + 1 OR NEW.committed_at >= p.expires_at
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
      AND asset_id = NEW.asset_id AND variant_mint = NEW.variant_mint;
  IF NOT FOUND THEN position_quantity := 0; position_basis := 0; realized_before := 0; locked_before := 0; END IF;
  IF (NEW.position_quantity_before_micros, NEW.position_cost_basis_before_micros,
      NEW.realized_gain_before_micros, NEW.locked_gain_before_micros)
     IS DISTINCT FROM (position_quantity, position_basis, realized_before, locked_before) THEN
    RAISE EXCEPTION 'Paper order position start does not match storage' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.protect_paper_order() FROM PUBLIC;
CREATE TRIGGER paper_order_guard BEFORE INSERT ON trimmy.paper_orders
  FOR EACH ROW EXECUTE FUNCTION trimmy.protect_paper_order();

CREATE TRIGGER paper_accounts_no_delete BEFORE DELETE ON trimmy.paper_accounts
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();
CREATE TRIGGER paper_positions_no_delete BEFORE DELETE ON trimmy.paper_positions
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();
CREATE TRIGGER paper_previews_no_delete BEFORE DELETE ON trimmy.paper_order_previews
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();
CREATE TRIGGER paper_orders_append_only BEFORE UPDATE OR DELETE ON trimmy.paper_orders
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();
CREATE TRIGGER paper_cash_ledger_append_only BEFORE UPDATE OR DELETE ON trimmy.paper_cash_ledger
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();

-- Deferred cross-table checks let one database transaction update the snapshot,
-- append the order and ledger entry, then prove they agree before commit.
CREATE FUNCTION trimmy.check_paper_account_ledger() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy AS $$
DECLARE account_user uuid := CASE WHEN TG_TABLE_NAME = 'paper_accounts' THEN NEW.user_id ELSE NEW.user_id END;
DECLARE a trimmy.paper_accounts%ROWTYPE;
DECLARE l trimmy.paper_cash_ledger%ROWTYPE;
BEGIN
  SELECT * INTO a FROM trimmy.paper_accounts WHERE user_id = account_user;
  SELECT * INTO l FROM trimmy.paper_cash_ledger WHERE user_id = account_user ORDER BY account_revision DESC LIMIT 1;
  IF NOT FOUND OR a.revision <> l.account_revision OR a.cash_micros <> l.balance_after_micros THEN
    RAISE EXCEPTION 'Paper cash snapshot and ledger do not agree' USING ERRCODE = '23514';
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.check_paper_account_ledger() FROM PUBLIC;
CREATE CONSTRAINT TRIGGER paper_account_ledger_pair AFTER INSERT OR UPDATE ON trimmy.paper_accounts
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trimmy.check_paper_account_ledger();
CREATE CONSTRAINT TRIGGER paper_ledger_account_pair AFTER INSERT ON trimmy.paper_cash_ledger
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trimmy.check_paper_account_ledger();

CREATE FUNCTION trimmy.check_paper_position_order() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy AS $$
DECLARE o trimmy.paper_orders%ROWTYPE;
BEGIN
  SELECT * INTO o FROM trimmy.paper_orders WHERE user_id = NEW.user_id
    AND account_revision = NEW.last_order_revision AND asset_id = NEW.asset_id
    AND variant_mint = NEW.variant_mint;
  IF NOT FOUND OR o.symbol <> NEW.symbol
      OR (o.position_quantity_after_micros, o.position_cost_basis_after_micros,
          o.realized_gain_after_micros, o.locked_gain_after_micros)
        IS DISTINCT FROM
         (NEW.quantity_micros, NEW.cost_basis_micros, NEW.realized_gain_micros, NEW.locked_gain_micros) THEN
    RAISE EXCEPTION 'Paper position must match its committed order' USING ERRCODE = '23514';
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.check_paper_position_order() FROM PUBLIC;
CREATE CONSTRAINT TRIGGER paper_position_order_pair AFTER INSERT OR UPDATE ON trimmy.paper_positions
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trimmy.check_paper_position_order();

CREATE FUNCTION trimmy.check_paper_order_commit() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy AS $$
DECLARE p trimmy.paper_order_previews%ROWTYPE;
DECLARE a trimmy.paper_accounts%ROWTYPE;
DECLARE pos trimmy.paper_positions%ROWTYPE;
DECLARE ledger trimmy.paper_cash_ledger%ROWTYPE;
BEGIN
  SELECT * INTO p FROM trimmy.paper_order_previews WHERE id = NEW.preview_id AND user_id = NEW.user_id;
  SELECT * INTO a FROM trimmy.paper_accounts WHERE user_id = NEW.user_id;
  SELECT * INTO pos FROM trimmy.paper_positions WHERE user_id = NEW.user_id
    AND asset_id = NEW.asset_id AND variant_mint = NEW.variant_mint;
  SELECT * INTO ledger FROM trimmy.paper_cash_ledger WHERE user_id = NEW.user_id
    AND account_revision = NEW.account_revision;
  IF p.id IS NULL OR a.user_id IS NULL OR pos.user_id IS NULL OR ledger.user_id IS NULL
      OR p.state <> 'committed' OR p.committed_at <> NEW.committed_at
      OR a.revision <> NEW.account_revision OR a.cash_micros <> NEW.cash_after_micros
      OR pos.last_order_revision <> NEW.account_revision OR pos.symbol <> NEW.symbol
      OR (pos.quantity_micros, pos.cost_basis_micros, pos.realized_gain_micros, pos.locked_gain_micros)
        IS DISTINCT FROM
        (NEW.position_quantity_after_micros, NEW.position_cost_basis_after_micros,
         NEW.realized_gain_after_micros, NEW.locked_gain_after_micros)
      OR ledger.order_id <> NEW.id OR ledger.entry_kind <> NEW.action
      OR ledger.balance_after_micros <> NEW.cash_after_micros
      OR ledger.delta_micros <> NEW.cash_credit_micros - NEW.cash_debit_micros THEN
    RAISE EXCEPTION 'Paper order commit is incomplete or inconsistent' USING ERRCODE = '23514';
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.check_paper_order_commit() FROM PUBLIC;
CREATE CONSTRAINT TRIGGER paper_order_commit_complete AFTER INSERT ON trimmy.paper_orders
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trimmy.check_paper_order_commit();

ALTER TABLE trimmy.paper_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.paper_accounts FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.paper_positions ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.paper_positions FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.paper_order_previews ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.paper_order_previews FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.paper_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.paper_orders FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.paper_cash_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.paper_cash_ledger FORCE ROW LEVEL SECURITY;
CREATE POLICY paper_account_scope ON trimmy.paper_accounts
  USING (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid)
  WITH CHECK (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid);
CREATE POLICY paper_position_scope ON trimmy.paper_positions
  USING (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid)
  WITH CHECK (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid);
CREATE POLICY paper_preview_scope ON trimmy.paper_order_previews
  USING (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid)
  WITH CHECK (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid);
CREATE POLICY paper_order_scope ON trimmy.paper_orders
  USING (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid)
  WITH CHECK (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid);
CREATE POLICY paper_ledger_scope ON trimmy.paper_cash_ledger
  USING (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid)
  WITH CHECK (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid);

REVOKE ALL ON TABLE trimmy.paper_accounts, trimmy.paper_positions,
  trimmy.paper_order_previews, trimmy.paper_orders, trimmy.paper_cash_ledger FROM PUBLIC;

-- Deployment grants are applied separately by local-secure-runtime.mjs. They
-- permit only this paper ledger and still grant no access to financial_intents,
-- execution_attempts, assets, eligibility or wallet tables beyond existing use.
INSERT INTO trimmy.schema_migrations(version) VALUES ('0013_paper_trading');
COMMIT;
