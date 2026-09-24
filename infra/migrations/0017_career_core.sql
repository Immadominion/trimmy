-- 0017: the first server-owned Career slice. Paper activity starts and extends
-- a streak. A concise reason can be attached only to an owned paper buy while
-- the position is still held. The first three reasons per UTC day award ten
-- Trims each. Money execution is not represented anywhere in this schema.
BEGIN;

CREATE TABLE trimmy.career_profiles (
  user_id uuid PRIMARY KEY REFERENCES trimmy.users(id),
  revision bigint NOT NULL CHECK (revision BETWEEN 1 AND 9007199254740991),
  trims_total bigint NOT NULL CHECK (trims_total BETWEEN 0 AND 9007199254740991),
  rank_id text COLLATE "C" NOT NULL
    CHECK (rank_id IN ('rookie', 'analyst', 'trader', 'senior-trader', 'partner', 'legend')),
  streak_days integer NOT NULL CHECK (streak_days BETWEEN 1 AND 1000000),
  last_active_date date NOT NULL,
  created_at timestamptz NOT NULL CHECK (isfinite(created_at)),
  updated_at timestamptz NOT NULL CHECK (isfinite(updated_at) AND updated_at >= created_at)
);

CREATE TABLE trimmy.career_trim_ledger (
  user_id uuid NOT NULL REFERENCES trimmy.career_profiles(user_id),
  career_revision bigint NOT NULL CHECK (career_revision BETWEEN 1 AND 9007199254740991),
  entry_kind text COLLATE "C" NOT NULL CHECK (entry_kind IN ('paper-reason')),
  source_id uuid NOT NULL,
  trims integer NOT NULL CHECK (trims = 10),
  awarded_on date NOT NULL,
  created_at timestamptz NOT NULL CHECK (isfinite(created_at)),
  PRIMARY KEY (user_id, career_revision),
  UNIQUE (user_id, entry_kind, source_id)
);
CREATE INDEX career_trim_ledger_day
  ON trimmy.career_trim_ledger (user_id, awarded_on, created_at);

CREATE TABLE trimmy.career_trade_reasons (
  order_id uuid PRIMARY KEY,
  user_id uuid NOT NULL,
  asset_id text NOT NULL
    CHECK (asset_id ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND length(asset_id) <= 100),
  variant_mint trimmy.solana_address NOT NULL,
  note text NOT NULL CHECK (
    note = btrim(note) AND char_length(note) BETWEEN 1 AND 180 AND note !~ '[[:cntrl:]]'),
  trims_awarded integer NOT NULL CHECK (trims_awarded IN (0, 10)),
  daily_award_number smallint,
  saved_at timestamptz NOT NULL CHECK (isfinite(saved_at)),
  UNIQUE (order_id, user_id),
  FOREIGN KEY (order_id, user_id) REFERENCES trimmy.paper_orders(id, user_id),
  CHECK ((trims_awarded = 0) = (daily_award_number IS NULL)),
  CHECK (daily_award_number IS NULL OR daily_award_number BETWEEN 1 AND 3)
);
CREATE INDEX career_trade_reasons_asset
  ON trimmy.career_trade_reasons (asset_id, variant_mint, saved_at DESC, order_id DESC);
CREATE INDEX career_trade_reasons_user_day
  ON trimmy.career_trade_reasons (user_id, saved_at DESC, order_id DESC);

CREATE TABLE trimmy.career_reason_mutation_receipts (
  user_id uuid NOT NULL REFERENCES trimmy.users(id),
  mutation_id uuid NOT NULL,
  request_hash trimmy.sha256_hex NOT NULL,
  order_id uuid NOT NULL,
  asset_id text NOT NULL
    CHECK (asset_id ~ '^[a-z0-9]+(-[a-z0-9]+)*$' AND length(asset_id) <= 100),
  variant_mint trimmy.solana_address NOT NULL,
  note text NOT NULL CHECK (
    note = btrim(note) AND char_length(note) BETWEEN 1 AND 180 AND note !~ '[[:cntrl:]]'),
  trims_awarded integer NOT NULL CHECK (trims_awarded IN (0, 10)),
  daily_award_number smallint,
  saved_at timestamptz NOT NULL CHECK (isfinite(saved_at)),
  PRIMARY KEY (user_id, mutation_id),
  CHECK ((trims_awarded = 0) = (daily_award_number IS NULL)),
  CHECK (daily_award_number IS NULL OR daily_award_number BETWEEN 1 AND 3)
);

CREATE FUNCTION trimmy.career_rank_number(selected text) RETURNS smallint
LANGUAGE sql IMMUTABLE STRICT
SET search_path = pg_catalog, trimmy AS $$
  SELECT CASE selected
    WHEN 'rookie' THEN 1 WHEN 'analyst' THEN 2 WHEN 'trader' THEN 3
    WHEN 'senior-trader' THEN 4 WHEN 'partner' THEN 5 WHEN 'legend' THEN 6
    ELSE 0
  END::smallint;
$$;
REVOKE ALL ON FUNCTION trimmy.career_rank_number(text) FROM PUBLIC;

CREATE FUNCTION trimmy.protect_career_profile() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'Career history cannot be deleted' USING ERRCODE = '23514';
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.revision <> 1 OR NEW.rank_id <> 'rookie' OR NEW.streak_days <> 1
        OR NEW.created_at <> NEW.updated_at THEN
      RAISE EXCEPTION 'Career profiles begin at rookie revision one with one active day'
        USING ERRCODE = '23514', CONSTRAINT = 'career_profile_initial_state';
    END IF;
  ELSE
    IF (NEW.user_id, NEW.created_at) IS DISTINCT FROM (OLD.user_id, OLD.created_at) THEN
      RAISE EXCEPTION 'Career identity is immutable'
        USING ERRCODE = '23514', CONSTRAINT = 'career_profile_identity';
    END IF;
    IF NEW.revision <> OLD.revision + 1 OR NEW.updated_at <= OLD.updated_at
        OR NEW.trims_total < OLD.trims_total OR NEW.last_active_date < OLD.last_active_date
        OR trimmy.career_rank_number(NEW.rank_id) < trimmy.career_rank_number(OLD.rank_id)
        OR trimmy.career_rank_number(NEW.rank_id) > trimmy.career_rank_number(OLD.rank_id) + 1 THEN
      RAISE EXCEPTION 'Career progress cannot move backwards or skip a rank'
        USING ERRCODE = '23514', CONSTRAINT = 'career_profile_progress';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.protect_career_profile() FROM PUBLIC;
CREATE TRIGGER career_profile_guard BEFORE INSERT OR UPDATE OR DELETE ON trimmy.career_profiles
  FOR EACH ROW EXECUTE FUNCTION trimmy.protect_career_profile();

CREATE TRIGGER career_trim_ledger_append_only
  BEFORE UPDATE OR DELETE ON trimmy.career_trim_ledger
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();
CREATE TRIGGER career_trade_reasons_append_only
  BEFORE UPDATE OR DELETE ON trimmy.career_trade_reasons
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();
CREATE TRIGGER career_reason_receipts_append_only
  BEFORE UPDATE OR DELETE ON trimmy.career_reason_mutation_receipts
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();

CREATE FUNCTION trimmy.check_career_trim_total() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE selected_user uuid := NEW.user_id;
DECLARE profile_total bigint; ledger_total bigint;
BEGIN
  SELECT p.trims_total INTO profile_total FROM trimmy.career_profiles p
    WHERE p.user_id = selected_user;
  SELECT coalesce(sum(l.trims), 0)::bigint INTO ledger_total
    FROM trimmy.career_trim_ledger l WHERE l.user_id = selected_user;
  IF profile_total IS NULL OR profile_total <> ledger_total THEN
    RAISE EXCEPTION 'Career profile and Trims ledger do not agree'
      USING ERRCODE = '23514', CONSTRAINT = 'career_trim_total';
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.check_career_trim_total() FROM PUBLIC;
CREATE CONSTRAINT TRIGGER career_profile_trim_total
  AFTER INSERT OR UPDATE ON trimmy.career_profiles DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trimmy.check_career_trim_total();
CREATE CONSTRAINT TRIGGER career_ledger_trim_total
  AFTER INSERT ON trimmy.career_trim_ledger DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trimmy.check_career_trim_total();

CREATE FUNCTION trimmy.check_career_reason_receipt_pair() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  IF TG_TABLE_NAME = 'career_trade_reasons' THEN
    IF NOT EXISTS (
      SELECT 1 FROM trimmy.career_reason_mutation_receipts r
      WHERE r.user_id = NEW.user_id AND r.order_id = NEW.order_id
        AND (r.asset_id, r.variant_mint, r.note, r.trims_awarded,
             r.daily_award_number, r.saved_at)
            IS NOT DISTINCT FROM
            (NEW.asset_id, NEW.variant_mint, NEW.note, NEW.trims_awarded,
             NEW.daily_award_number, NEW.saved_at)
    ) THEN
      RAISE EXCEPTION 'A trade reason requires its mutation receipt'
        USING ERRCODE = '23514', CONSTRAINT = 'career_reason_receipt_pair';
    END IF;
  ELSE
    IF NOT EXISTS (
      SELECT 1 FROM trimmy.career_trade_reasons r
      WHERE r.user_id = NEW.user_id AND r.order_id = NEW.order_id
        AND (r.asset_id, r.variant_mint, r.note, r.trims_awarded,
             r.daily_award_number, r.saved_at)
            IS NOT DISTINCT FROM
            (NEW.asset_id, NEW.variant_mint, NEW.note, NEW.trims_awarded,
             NEW.daily_award_number, NEW.saved_at)
    ) THEN
      RAISE EXCEPTION 'A reason mutation receipt requires its trade reason'
        USING ERRCODE = '23514', CONSTRAINT = 'career_reason_receipt_pair';
    END IF;
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.check_career_reason_receipt_pair() FROM PUBLIC;
CREATE CONSTRAINT TRIGGER career_reason_receipt_pair
  AFTER INSERT ON trimmy.career_trade_reasons DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trimmy.check_career_reason_receipt_pair();
CREATE CONSTRAINT TRIGGER career_receipt_reason_pair
  AFTER INSERT ON trimmy.career_reason_mutation_receipts DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION trimmy.check_career_reason_receipt_pair();

-- Applies a qualifying activity and optional Trims award under the caller's
-- per-user advisory lock. This function is also safe when the paper-order
-- trigger is the first Career event for an account.
CREATE FUNCTION trimmy.career_record_activity(
  selected_user uuid,
  activity_date date,
  trims_delta integer,
  observed_at timestamptz
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE current_row trimmy.career_profiles%ROWTYPE;
DECLARE next_revision bigint; next_streak integer; next_updated timestamptz;
BEGIN
  IF selected_user IS NULL OR activity_date IS NULL OR observed_at IS NULL
      OR NOT isfinite(observed_at) OR activity_date > (observed_at AT TIME ZONE 'UTC')::date
      OR trims_delta NOT IN (0, 10) THEN
    RAISE EXCEPTION 'Career activity input is invalid' USING ERRCODE = '22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('trimmy.career:' || selected_user::text, 0));
  IF NOT EXISTS (SELECT 1 FROM trimmy.users u WHERE u.id = selected_user AND u.status = 'active') THEN
    RAISE EXCEPTION 'Career activity requires an active account' USING ERRCODE = '23514';
  END IF;
  SELECT p.* INTO current_row FROM trimmy.career_profiles p
    WHERE p.user_id = selected_user FOR UPDATE;
  IF NOT FOUND THEN
    INSERT INTO trimmy.career_profiles(
      user_id, revision, trims_total, rank_id, streak_days, last_active_date,
      created_at, updated_at)
    VALUES (selected_user, 1, trims_delta, 'rookie', 1, activity_date,
      observed_at, observed_at)
    RETURNING revision INTO next_revision;
    RETURN next_revision;
  END IF;
  IF current_row.revision >= 9007199254740991
      OR current_row.trims_total > 9007199254740991 - trims_delta THEN
    RAISE EXCEPTION 'Career revision is exhausted'
      USING ERRCODE = '22003', CONSTRAINT = 'career_revision_exhausted';
  END IF;
  IF activity_date <= current_row.last_active_date AND trims_delta = 0 THEN
    RETURN current_row.revision;
  END IF;
  next_streak := CASE
    WHEN activity_date <= current_row.last_active_date THEN current_row.streak_days
    WHEN activity_date <= current_row.last_active_date + 2 THEN current_row.streak_days + 1
    ELSE 1
  END;
  next_revision := current_row.revision + 1;
  next_updated := greatest(date_trunc('milliseconds', observed_at),
    current_row.updated_at + interval '1 millisecond');
  UPDATE trimmy.career_profiles SET
    revision = next_revision,
    trims_total = current_row.trims_total + trims_delta,
    streak_days = next_streak,
    last_active_date = greatest(current_row.last_active_date, activity_date),
    updated_at = next_updated
  WHERE user_id = selected_user;
  RETURN next_revision;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_record_activity(uuid, date, integer, timestamptz) FROM PUBLIC;

CREATE FUNCTION trimmy.career_paper_order_activity() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
BEGIN
  PERFORM trimmy.career_record_activity(
    NEW.user_id, (NEW.committed_at AT TIME ZONE 'UTC')::date, 0, NEW.committed_at);
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_paper_order_activity() FROM PUBLIC;
CREATE TRIGGER career_paper_order_activity
  AFTER INSERT ON trimmy.paper_orders
  FOR EACH ROW EXECUTE FUNCTION trimmy.career_paper_order_activity();

CREATE FUNCTION trimmy.career_summary_get(selected_user uuid)
RETURNS TABLE (
  outcome text,
  revision bigint,
  trims_total bigint,
  trims_today bigint,
  trims_week bigint,
  rank_id text,
  rank_label text,
  paper_limit text,
  rank_threshold integer,
  next_rank_id text,
  next_rank_label text,
  next_rank_threshold integer,
  trims_remaining bigint,
  promotion_required boolean,
  streak_days integer,
  streak_status text,
  last_active_date date,
  server_date date,
  updated_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE account_status text; current_row trimmy.career_profiles%ROWTYPE;
DECLARE today date := (clock_timestamp() AT TIME ZONE 'UTC')::date;
DECLARE week_start date := date_trunc('week', today::timestamp)::date;
DECLARE current_threshold integer; next_id text; next_label text; next_threshold integer;
DECLARE current_label text; current_limit text; effective_streak integer; effective_status text;
DECLARE total_today bigint; total_week bigint;
BEGIN
  IF selected_user IS NULL THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::bigint, NULL::bigint, NULL::bigint, NULL::bigint,
      NULL::text, NULL::text, NULL::text, NULL::integer, NULL::text, NULL::text, NULL::integer,
      NULL::bigint, NULL::boolean, NULL::integer, NULL::text, NULL::date, today, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT u.status INTO account_status FROM trimmy.users u WHERE u.id = selected_user;
  IF account_status IS DISTINCT FROM 'active' THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::bigint, NULL::bigint, NULL::bigint, NULL::bigint,
      NULL::text, NULL::text, NULL::text, NULL::integer, NULL::text, NULL::text, NULL::integer,
      NULL::bigint, NULL::boolean, NULL::integer, NULL::text, NULL::date, today, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT p.* INTO current_row FROM trimmy.career_profiles p WHERE p.user_id = selected_user;
  IF NOT FOUND THEN
    RETURN QUERY SELECT 'found'::text, 0::bigint, 0::bigint, 0::bigint, 0::bigint,
      'rookie'::text, 'Rookie'::text, '10000'::text, 0::integer,
      'analyst'::text, 'Analyst'::text, 300::integer, 300::bigint, false,
      0::integer, 'not-started'::text, NULL::date, today, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT coalesce(sum(l.trims) FILTER (WHERE l.awarded_on = today), 0)::bigint,
         coalesce(sum(l.trims) FILTER (WHERE l.awarded_on >= week_start AND l.awarded_on <= today), 0)::bigint
    INTO total_today, total_week
    FROM trimmy.career_trim_ledger l WHERE l.user_id = selected_user;
  SELECT
    CASE current_row.rank_id
      WHEN 'rookie' THEN 'Rookie' WHEN 'analyst' THEN 'Analyst' WHEN 'trader' THEN 'Trader'
      WHEN 'senior-trader' THEN 'Senior Trader' WHEN 'partner' THEN 'Partner' ELSE 'Legend' END,
    CASE current_row.rank_id
      WHEN 'rookie' THEN '10000' WHEN 'analyst' THEN '25000' WHEN 'trader' THEN '50000'
      WHEN 'senior-trader' THEN '100000' WHEN 'partner' THEN '250000' ELSE '1000000' END,
    CASE current_row.rank_id
      WHEN 'rookie' THEN 0 WHEN 'analyst' THEN 300 WHEN 'trader' THEN 900
      WHEN 'senior-trader' THEN 2000 WHEN 'partner' THEN 4500 ELSE 10000 END,
    CASE current_row.rank_id
      WHEN 'rookie' THEN 'analyst' WHEN 'analyst' THEN 'trader' WHEN 'trader' THEN 'senior-trader'
      WHEN 'senior-trader' THEN 'partner' WHEN 'partner' THEN 'legend' ELSE NULL END,
    CASE current_row.rank_id
      WHEN 'rookie' THEN 'Analyst' WHEN 'analyst' THEN 'Trader' WHEN 'trader' THEN 'Senior Trader'
      WHEN 'senior-trader' THEN 'Partner' WHEN 'partner' THEN 'Legend' ELSE NULL END,
    CASE current_row.rank_id
      WHEN 'rookie' THEN 300 WHEN 'analyst' THEN 900 WHEN 'trader' THEN 2000
      WHEN 'senior-trader' THEN 4500 WHEN 'partner' THEN 10000 ELSE NULL END
    INTO current_label, current_limit, current_threshold, next_id, next_label, next_threshold;
  IF current_row.last_active_date = today THEN
    effective_streak := current_row.streak_days; effective_status := 'active';
  ELSIF current_row.last_active_date = today - 1 THEN
    effective_streak := current_row.streak_days; effective_status := 'at-risk';
  ELSIF current_row.last_active_date = today - 2 THEN
    effective_streak := current_row.streak_days; effective_status := 'grace';
  ELSE
    effective_streak := 0; effective_status := 'not-started';
  END IF;
  RETURN QUERY SELECT 'found'::text, current_row.revision, current_row.trims_total,
    total_today, total_week, current_row.rank_id, current_label, current_limit,
    current_threshold, next_id, next_label, next_threshold,
    CASE WHEN next_threshold IS NULL THEN NULL::bigint
      ELSE greatest(0::bigint, next_threshold::bigint - current_row.trims_total) END,
    CASE WHEN next_threshold IS NULL THEN false
      ELSE current_row.trims_total >= next_threshold END,
    effective_streak, effective_status,
    CASE WHEN effective_streak = 0 THEN NULL::date ELSE current_row.last_active_date END,
    today, current_row.updated_at;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_summary_get(uuid) FROM PUBLIC;

CREATE FUNCTION trimmy.career_trade_reason_put(
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
DECLARE receipt_row trimmy.career_reason_mutation_receipts%ROWTYPE;
DECLARE observed_at timestamptz := date_trunc('milliseconds', clock_timestamp());
DECLARE today date; awarded_count integer; awarded integer; award_number smallint;
DECLARE career_revision bigint;
BEGIN
  today := (observed_at AT TIME ZONE 'UTC')::date;
  IF selected_user IS NULL OR selected_mutation IS NULL OR selected_order IS NULL
      OR selected_hash IS NULL OR selected_hash !~ '^[a-f0-9]{64}$'
      OR selected_note IS NULL OR selected_note <> btrim(selected_note)
      OR char_length(selected_note) NOT BETWEEN 1 AND 180 OR selected_note ~ '[[:cntrl:]]' THEN
    RETURN QUERY SELECT 'invalid'::text, NULL::uuid, NULL::text, NULL::text, NULL::text,
      NULL::integer, NULL::smallint, NULL::timestamptz;
    RETURN;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('trimmy.career:' || selected_user::text, 0));
  SELECT u.status INTO account_status FROM trimmy.users u WHERE u.id = selected_user FOR UPDATE;
  IF account_status IS DISTINCT FROM 'active' THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::uuid, NULL::text, NULL::text, NULL::text,
      NULL::integer, NULL::smallint, NULL::timestamptz;
    RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM trimmy.product_profiles p WHERE p.user_id = selected_user) THEN
    RETURN QUERY SELECT 'profile_required'::text, NULL::uuid, NULL::text, NULL::text, NULL::text,
      NULL::integer, NULL::smallint, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT r.* INTO receipt_row FROM trimmy.career_reason_mutation_receipts r
    WHERE r.user_id = selected_user AND r.mutation_id = selected_mutation;
  IF FOUND THEN
    IF receipt_row.request_hash <> selected_hash THEN
      RETURN QUERY SELECT 'idempotency_conflict'::text, NULL::uuid, NULL::text, NULL::text, NULL::text,
        NULL::integer, NULL::smallint, NULL::timestamptz;
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
      NULL::integer, NULL::smallint, NULL::timestamptz;
    RETURN;
  END IF;
  IF order_row.action <> 'buy' THEN
    RETURN QUERY SELECT 'buy_required'::text, NULL::uuid, NULL::text, NULL::text, NULL::text,
      NULL::integer, NULL::smallint, NULL::timestamptz;
    RETURN;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM trimmy.paper_positions p
    WHERE p.user_id = selected_user AND p.asset_id = order_row.asset_id
      AND p.variant_mint = order_row.variant_mint AND p.quantity_micros > 0
  ) THEN
    RETURN QUERY SELECT 'position_required'::text, NULL::uuid, NULL::text, NULL::text, NULL::text,
      NULL::integer, NULL::smallint, NULL::timestamptz;
    RETURN;
  END IF;
  IF EXISTS (SELECT 1 FROM trimmy.career_trade_reasons r WHERE r.order_id = selected_order) THEN
    RETURN QUERY SELECT 'reason_exists'::text, NULL::uuid, NULL::text, NULL::text, NULL::text,
      NULL::integer, NULL::smallint, NULL::timestamptz;
    RETURN;
  END IF;
  SELECT count(*)::integer INTO awarded_count FROM trimmy.career_trade_reasons r
    WHERE r.user_id = selected_user AND r.trims_awarded = 10
      AND (r.saved_at AT TIME ZONE 'UTC')::date = today;
  IF awarded_count < 3 THEN
    awarded := 10; award_number := (awarded_count + 1)::smallint;
  ELSE
    awarded := 0; award_number := NULL;
  END IF;
  BEGIN
    career_revision := trimmy.career_record_activity(selected_user, today, awarded, observed_at);
  EXCEPTION WHEN numeric_value_out_of_range THEN
    RETURN QUERY SELECT 'revision_exhausted'::text, NULL::uuid, NULL::text, NULL::text, NULL::text,
      NULL::integer, NULL::smallint, NULL::timestamptz;
    RETURN;
  END;
  INSERT INTO trimmy.career_trade_reasons(
    order_id, user_id, asset_id, variant_mint, note, trims_awarded, daily_award_number, saved_at)
  VALUES (selected_order, selected_user, order_row.asset_id, order_row.variant_mint,
    selected_note, awarded, award_number, observed_at);
  IF awarded > 0 THEN
    INSERT INTO trimmy.career_trim_ledger(
      user_id, career_revision, entry_kind, source_id, trims, awarded_on, created_at)
    VALUES (selected_user, career_revision, 'paper-reason', selected_order, awarded, today, observed_at);
  END IF;
  INSERT INTO trimmy.career_reason_mutation_receipts(
    user_id, mutation_id, request_hash, order_id, asset_id, variant_mint, note,
    trims_awarded, daily_award_number, saved_at)
  VALUES (selected_user, selected_mutation, selected_hash, selected_order,
    order_row.asset_id, order_row.variant_mint, selected_note, awarded, award_number, observed_at);
  RETURN QUERY SELECT 'saved'::text, selected_order, order_row.asset_id,
    order_row.variant_mint::text, selected_note, awarded, award_number, observed_at;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_trade_reason_put(uuid, uuid, text, uuid, text) FROM PUBLIC;

ALTER TABLE trimmy.career_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_profiles FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_trim_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_trim_ledger FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_trade_reasons ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_trade_reasons FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_reason_mutation_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.career_reason_mutation_receipts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE trimmy.career_profiles, trimmy.career_trim_ledger,
  trimmy.career_trade_reasons, trimmy.career_reason_mutation_receipts FROM PUBLIC;

-- Guests can access only their own Career summary and paper-reason write. The
-- same credential still cannot reach wallets, money routes or another user.
ALTER TABLE trimmy.guest_rate_windows DROP CONSTRAINT guest_rate_windows_scope_check;
ALTER TABLE trimmy.guest_rate_windows ADD CONSTRAINT guest_rate_windows_scope_check
  CHECK (scope IN ('paper_read', 'paper_preview', 'paper_commit', 'refresh', 'claim',
    'profile_read', 'profile_write', 'career_read', 'career_write'));

CREATE OR REPLACE FUNCTION trimmy.guest_take_rate(
  selected_session uuid,
  selected_scope text,
  observed_at timestamptz
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE window_seconds integer; request_limit integer; window_start timestamptz; observed_count integer;
BEGIN
  IF selected_scope = 'paper_read' THEN window_seconds := 60; request_limit := 60;
  ELSIF selected_scope = 'paper_preview' THEN window_seconds := 600; request_limit := 20;
  ELSIF selected_scope = 'paper_commit' THEN window_seconds := 600; request_limit := 20;
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
  window_start := to_timestamp(floor(extract(epoch FROM observed_at) / window_seconds) * window_seconds);
  INSERT INTO trimmy.guest_rate_windows(guest_session_id, scope, window_started_at, request_count)
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
        'profile_read', 'profile_write', 'career_read', 'career_write') THEN
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
  SELECT u.status INTO account_status FROM trimmy.users u WHERE u.id = session_row.user_id FOR UPDATE;
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
  RETURN QUERY SELECT 'authorized'::text, session_row.user_id, session_row.id, session_row.expires_at;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.guest_authorize(text, text) FROM PUBLIC;

INSERT INTO trimmy.schema_migrations(version) VALUES ('0017_career_core');
COMMIT;
