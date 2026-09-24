-- 0007: wallet possession bindings and expiring reviewed stock-order intents.
--
-- The runtime role may record a wallet binding for its scoped account after the
-- API verified an ed25519 possession signature, and may store the outcome of a
-- completed unsigned-order review. Neither table holds money, key material or a
-- signed transaction. The reviewed intent keeps the exact unsigned bytes only so
-- a later explicit approval and signature can be bound to that message and
-- nothing else. The foundation constraints from 0001 (no live intents, no
-- mainnet execution attempts) are untouched.
BEGIN;

-- The audit trigger from 0001 writes to trimmy.audit_events with the invoker's
-- rights, so an actor without INSERT on that table could not change an audited
-- row at all. Definer rights make the trail unavoidable instead of optional:
-- the runtime role still cannot write or read audit rows directly, and every
-- audited change now records one. The body is unchanged.
CREATE OR REPLACE FUNCTION trimmy.record_change() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, trimmy AS $$
DECLARE row_data jsonb := to_jsonb(NEW);
BEGIN
  INSERT INTO trimmy.audit_events (action, entity_type, entity_id, detail)
  VALUES (lower(TG_OP), TG_TABLE_NAME, coalesce(row_data->>'id', row_data->>'attestation_id'),
    jsonb_strip_nulls(jsonb_build_object('state', row_data->>'state', 'status', row_data->>'status')));
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.record_change() FROM PUBLIC;

-- Wallet bindings become account-scoped for the runtime role. 0001 enabled RLS
-- without policies, which kept every role except the owner out entirely.
ALTER TABLE trimmy.wallet_bindings FORCE ROW LEVEL SECURITY;
CREATE POLICY wallet_binding_account_scope ON trimmy.wallet_bindings
  USING (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid)
  WITH CHECK (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid);

-- A binding may only be inserted for an existing, active account, at the
-- verification instant, never pre-revoked and never for a future instant.
-- Definer rights: the account-status check must read trimmy.users, which no
-- runtime role may select. The function reads nothing else and returns no row
-- data, so it grants no visibility into that table.
CREATE FUNCTION trimmy.protect_new_binding() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, trimmy AS $$
BEGIN
  IF NEW.revoked_at IS NOT NULL THEN
    RAISE EXCEPTION 'A new wallet binding cannot start revoked' USING ERRCODE = '23514';
  END IF;
  IF NEW.verified_at > now() + interval '5 minutes' THEN
    RAISE EXCEPTION 'Wallet binding verification time is in the future' USING ERRCODE = '23514';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM trimmy.users WHERE id = NEW.user_id AND status = 'active') THEN
    RAISE EXCEPTION 'Wallet bindings require an active account' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.protect_new_binding() FROM PUBLIC;
CREATE TRIGGER wallet_bindings_insert_guard BEFORE INSERT ON trimmy.wallet_bindings
  FOR EACH ROW EXECUTE FUNCTION trimmy.protect_new_binding();

-- Reviewed intents: one row per completed review, scoped to the account.
CREATE TABLE trimmy.stock_order_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES trimmy.users(id),
  wallet_binding_id uuid,
  taker trimmy.solana_address NOT NULL,
  network text NOT NULL CHECK (network = 'mainnet-beta'),
  request_id text NOT NULL CHECK (length(request_id) BETWEEN 1 AND 128),
  transaction_message_hash trimmy.sha256_hex NOT NULL,
  transaction_hash trimmy.sha256_hex NOT NULL,
  candidate_terms_hash trimmy.sha256_hex NOT NULL,
  review_digest trimmy.sha256_hex NOT NULL,
  intent jsonb NOT NULL,
  unsigned_transaction bytea NOT NULL CHECK (octet_length(unsigned_transaction) BETWEEN 64 AND 1232),
  state text NOT NULL DEFAULT 'reviewed' CHECK (state IN ('reviewed', 'approved', 'expired', 'canceled', 'consumed')),
  approved_at timestamptz,
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  reviewed_at timestamptz NOT NULL,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id, user_id),
  UNIQUE (user_id, transaction_message_hash),
  FOREIGN KEY (wallet_binding_id, user_id) REFERENCES trimmy.wallet_bindings(id, user_id),
  CHECK (expires_at > reviewed_at),
  CHECK (approved_at IS NULL OR (approved_at >= reviewed_at AND approved_at < expires_at)),
  CHECK (state <> 'approved' OR approved_at IS NOT NULL),
  CHECK (jsonb_typeof(intent) = 'object'
    AND intent->>'kind' = 'reviewed_stock_order_intent'
    AND intent->>'transactionMessageHash' = transaction_message_hash
    AND intent->>'transactionHash' = transaction_hash
    AND intent->>'candidateTermsHash' = candidate_terms_hash
    AND intent->>'reviewDigestSha256' = review_digest
    AND intent->>'taker' = taker
    AND intent->'assessment'->>'signingEnabled' = 'false'
    AND intent->'assessment'->>'broadcastEnabled' = 'false'
    AND intent->'approval'->>'status' = 'required'
    AND NOT (intent ? 'unsignedTransaction')
    AND NOT (intent ? 'transactionBase64'))
);

CREATE FUNCTION trimmy.protect_stock_order_review() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.state <> 'reviewed' OR NEW.version <> 0 OR NEW.approved_at IS NOT NULL THEN
      RAISE EXCEPTION 'Reviews start in the reviewed state at version zero' USING ERRCODE = '23514';
    END IF;
    IF NEW.wallet_binding_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM trimmy.wallet_bindings b
        WHERE b.id = NEW.wallet_binding_id AND b.user_id = NEW.user_id AND b.address = NEW.taker
          AND b.network = NEW.network AND b.revoked_at IS NULL) THEN
      RAISE EXCEPTION 'A review may only cite an unrevoked binding of its own taker' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
  END IF;
  IF (to_jsonb(NEW) - 'state' - 'version' - 'approved_at' - 'wallet_binding_id')
      IS DISTINCT FROM (to_jsonb(OLD) - 'state' - 'version' - 'approved_at' - 'wallet_binding_id') THEN
    RAISE EXCEPTION 'Reviewed terms, evidence and bytes are immutable' USING ERRCODE = '23514';
  END IF;
  IF NEW.wallet_binding_id IS DISTINCT FROM OLD.wallet_binding_id AND (NEW.state <> 'approved' OR OLD.wallet_binding_id IS NOT NULL) THEN
    RAISE EXCEPTION 'A binding may only be attached by approval' USING ERRCODE = '23514';
  END IF;
  IF NEW.version <> OLD.version + 1 THEN
    RAISE EXCEPTION 'Review update must advance version exactly once' USING ERRCODE = '23514';
  END IF;
  IF OLD.state IN ('expired', 'canceled', 'consumed') THEN
    RAISE EXCEPTION 'Review is terminal' USING ERRCODE = '23514';
  END IF;
  IF NEW.state = OLD.state THEN
    RAISE EXCEPTION 'Review update must change state' USING ERRCODE = '23514';
  END IF;
  IF NOT (
    OLD.state = 'reviewed' AND NEW.state IN ('approved', 'expired', 'canceled') OR
    OLD.state = 'approved' AND NEW.state IN ('consumed', 'expired', 'canceled')) THEN
    RAISE EXCEPTION 'Invalid review transition' USING ERRCODE = '23514';
  END IF;
  IF NEW.state = 'approved' THEN
    IF NEW.approved_at IS NULL OR NEW.approved_at >= NEW.expires_at OR NEW.approved_at > now() + interval '5 minutes' THEN
      RAISE EXCEPTION 'Approval must happen inside the review validity window' USING ERRCODE = '23514';
    END IF;
    IF NEW.wallet_binding_id IS NULL OR NOT EXISTS (
        SELECT 1 FROM trimmy.wallet_bindings b
        WHERE b.id = NEW.wallet_binding_id AND b.user_id = NEW.user_id AND b.address = NEW.taker
          AND b.network = NEW.network AND b.revoked_at IS NULL) THEN
      RAISE EXCEPTION 'Approval requires an unrevoked wallet binding of the taker' USING ERRCODE = '23514';
    END IF;
  ELSIF NEW.approved_at IS DISTINCT FROM OLD.approved_at THEN
    RAISE EXCEPTION 'Only approval sets the approval time' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.protect_stock_order_review() FROM PUBLIC;
CREATE TRIGGER stock_order_reviews_guard BEFORE INSERT OR UPDATE ON trimmy.stock_order_reviews
  FOR EACH ROW EXECUTE FUNCTION trimmy.protect_stock_order_review();
CREATE TRIGGER stock_order_reviews_no_delete BEFORE DELETE ON trimmy.stock_order_reviews
  FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();
CREATE TRIGGER stock_order_reviews_audit AFTER INSERT OR UPDATE ON trimmy.stock_order_reviews
  FOR EACH ROW EXECUTE FUNCTION trimmy.record_change();
CREATE INDEX stock_order_reviews_open ON trimmy.stock_order_reviews (user_id, expires_at)
  WHERE state IN ('reviewed', 'approved');

ALTER TABLE trimmy.stock_order_reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.stock_order_reviews FORCE ROW LEVEL SECURITY;
CREATE POLICY stock_order_review_account_scope ON trimmy.stock_order_reviews
  USING (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid)
  WITH CHECK (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid);

-- Runtime role grants belong to the deployment, for example:
--   GRANT SELECT, INSERT ON trimmy.wallet_bindings TO trimmy_practice_runtime;
--   GRANT SELECT, INSERT, UPDATE ON trimmy.stock_order_reviews TO trimmy_practice_runtime;
-- No role other than the owner may read trimmy.users, and nothing here grants
-- access to financial_intents or execution_attempts.
INSERT INTO trimmy.schema_migrations(version) VALUES ('0007_wallet_possession_and_reviews');
COMMIT;
