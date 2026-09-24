-- 0011: durable, single-use wallet possession challenges.
--
-- Challenges lived in one process's memory, which made the feature depend on a
-- single replica: a proof submitted to a second instance could not find the
-- challenge that instance never issued, so the wallet check failed outright.
-- That is a correctness problem, not only a scaling one.
--
-- Consumption is a one-way UPDATE rather than a DELETE. The serving role has no
-- DELETE privilege anywhere in this schema, and a security-relevant table is
-- the worst place to make the first exception: a compromised serving process
-- must not be able to erase the record of a challenge it used. Marking the row
-- is equally atomic, because the row lock serializes the two writers.
--
-- A challenge authorizes nothing by itself. It holds no key material, no
-- signature and no transaction, and the text it carries is the same text the
-- person is shown before signing.
BEGIN;

CREATE TABLE trimmy.wallet_possession_challenges (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES trimmy.users (id),
  wallet_address text NOT NULL,
  network text NOT NULL,
  provider_wallet_id text,
  nonce text NOT NULL,
  issued_at timestamptz NOT NULL,
  expires_at timestamptz NOT NULL,
  message text NOT NULL,
  consumed_at timestamptz,
  CONSTRAINT wallet_challenge_network_supported
    CHECK (network IN ('mainnet-beta', 'devnet', 'localnet')),
  CONSTRAINT wallet_challenge_address_shape
    CHECK (wallet_address ~ '^[1-9A-HJ-NP-Za-km-z]{32,44}$'),
  CONSTRAINT wallet_challenge_nonce_shape
    CHECK (nonce ~ '^[0-9a-f]{64}$'),
  CONSTRAINT wallet_challenge_provider_id_shape
    CHECK (provider_wallet_id IS NULL OR length(provider_wallet_id) BETWEEN 1 AND 200),
  CONSTRAINT wallet_challenge_message_bounded
    CHECK (length(message) BETWEEN 1 AND 4000),
  -- The signed text carries its own validity window, so the row may not claim a
  -- different or unbounded one.
  CONSTRAINT wallet_challenge_window
    CHECK (expires_at > issued_at AND expires_at <= issued_at + interval '15 minutes'),
  CONSTRAINT wallet_challenge_consumed_after_issue
    CHECK (consumed_at IS NULL OR consumed_at >= issued_at)
);

-- The only lookup that matters: what does this account still have outstanding.
CREATE INDEX wallet_possession_challenges_outstanding
  ON trimmy.wallet_possession_challenges (user_id, expires_at) WHERE consumed_at IS NULL;

-- 0001 enables row security on its own tables; this table is new, so it opts in
-- here and forces the rule on the owner too.
ALTER TABLE trimmy.wallet_possession_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.wallet_possession_challenges FORCE ROW LEVEL SECURITY;
CREATE POLICY wallet_challenge_account_scope ON trimmy.wallet_possession_challenges
  USING (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid)
  WITH CHECK (user_id = nullif(current_setting('trimmy.practice_user_id', true), '')::uuid);

-- A challenge may only be issued to an existing active account, may not start
-- expired or consumed, and may not be stockpiled. The app keeps a lower
-- operating limit; this is the backstop that holds even if the app is wrong.
-- Definer rights: the status check reads trimmy.users, which no runtime role may
-- select. It returns no row data, so it grants no visibility into that table.
CREATE FUNCTION trimmy.protect_new_wallet_challenge() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, trimmy AS $$
BEGIN
  IF NEW.consumed_at IS NOT NULL THEN
    RAISE EXCEPTION 'A wallet challenge cannot start consumed' USING ERRCODE = '23514';
  END IF;
  IF NEW.expires_at <= now() THEN
    RAISE EXCEPTION 'A wallet challenge cannot start expired' USING ERRCODE = '23514';
  END IF;
  IF NEW.issued_at > now() + interval '5 minutes' THEN
    RAISE EXCEPTION 'Wallet challenge issue time is in the future' USING ERRCODE = '23514';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM trimmy.users WHERE id = NEW.user_id AND status = 'active') THEN
    RAISE EXCEPTION 'Wallet challenges require an active account' USING ERRCODE = '23514';
  END IF;
  IF (SELECT count(*) FROM trimmy.wallet_possession_challenges
        WHERE user_id = NEW.user_id AND consumed_at IS NULL AND expires_at > now()) >= 10 THEN
    RAISE EXCEPTION 'Too many outstanding wallet challenges' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.protect_new_wallet_challenge() FROM PUBLIC;
CREATE TRIGGER wallet_challenges_insert_guard BEFORE INSERT ON trimmy.wallet_possession_challenges
  FOR EACH ROW EXECUTE FUNCTION trimmy.protect_new_wallet_challenge();

-- The single permitted change is unconsumed to consumed, once. Rewriting the
-- wallet, nonce or window of an outstanding challenge would change what a
-- person already agreed to sign, and un-consuming one would defeat single use.
-- The serving role is additionally restricted to the consumed_at column by
-- grant; this trigger is the backstop that holds for any writer.
CREATE FUNCTION trimmy.protect_wallet_challenge_use() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy AS $$
BEGIN
  IF OLD.consumed_at IS NOT NULL THEN
    RAISE EXCEPTION 'A wallet challenge is single use' USING ERRCODE = '23514';
  END IF;
  IF NEW.consumed_at IS NULL THEN
    RAISE EXCEPTION 'A wallet challenge change must record its use' USING ERRCODE = '23514';
  END IF;
  IF NEW.id <> OLD.id OR NEW.user_id <> OLD.user_id OR NEW.wallet_address <> OLD.wallet_address
      OR NEW.network <> OLD.network OR NEW.nonce <> OLD.nonce OR NEW.message <> OLD.message
      OR NEW.issued_at <> OLD.issued_at OR NEW.expires_at <> OLD.expires_at
      OR NEW.provider_wallet_id IS DISTINCT FROM OLD.provider_wallet_id THEN
    RAISE EXCEPTION 'A wallet challenge cannot be rewritten' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.protect_wallet_challenge_use() FROM PUBLIC;
CREATE TRIGGER wallet_challenges_use_guard BEFORE UPDATE ON trimmy.wallet_possession_challenges
  FOR EACH ROW EXECUTE FUNCTION trimmy.protect_wallet_challenge_use();

-- Issuance and use both join the same audit trail as the binding they may
-- authorize, so a challenge leaves a record even though its row is never
-- removed by the serving role.
CREATE TRIGGER audit_change AFTER INSERT OR UPDATE ON trimmy.wallet_possession_challenges
  FOR EACH ROW EXECUTE FUNCTION trimmy.record_change();

-- Runtime privileges for this table, applied by the deployment grant step:
--   GRANT SELECT, INSERT ON trimmy.wallet_possession_challenges TO trimmy_practice_runtime;
--   GRANT UPDATE (consumed_at) ON trimmy.wallet_possession_challenges TO trimmy_practice_runtime;
-- No DELETE and no other updatable column. Pruning consumed or long-expired
-- rows is an owner operation, exactly like the mutation-receipt tables.

INSERT INTO trimmy.schema_migrations(version) VALUES ('0011_wallet_possession_challenges');
COMMIT;
