-- PostgreSQL 15+. Apply once as a dedicated migration owner, with ON_ERROR_STOP.
-- This creates records and invariants; it does not implement custody or escrow.
BEGIN;

CREATE SCHEMA trimmy;
REVOKE ALL ON SCHEMA trimmy FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA trimmy REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA trimmy REVOKE ALL ON SEQUENCES FROM PUBLIC;
-- Function defaults are global to the creating role, so revoke each function below.

-- Unconstrained numeric rejects fractions rather than silently rounding them.
CREATE DOMAIN trimmy.raw_amount AS numeric
  CHECK (VALUE >= 0 AND VALUE <= 18446744073709551615 AND VALUE = trunc(VALUE));
CREATE DOMAIN trimmy.solana_address AS text
  CHECK (VALUE ~ '^[1-9A-HJ-NP-Za-km-z]{32,44}$');
CREATE DOMAIN trimmy.sha256_hex AS text
  CHECK (VALUE ~ '^[a-f0-9]{64}$');

CREATE TABLE trimmy.schema_migrations (
  version text PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE trimmy.users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'restricted', 'closed')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE trimmy.provider_identities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES trimmy.users(id),
  provider text NOT NULL CHECK (provider = 'x'),
  subject text NOT NULL CHECK (subject ~ '^[0-9]{1,30}$'),
  handle_snapshot text CHECK (length(handle_snapshot) BETWEEN 1 AND 100),
  verified_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider, subject),
  UNIQUE (id, user_id),
  UNIQUE (provider, subject, user_id)
);

CREATE TABLE trimmy.wallet_bindings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES trimmy.users(id),
  network text NOT NULL CHECK (network IN ('mainnet-beta', 'devnet', 'localnet')),
  address trimmy.solana_address NOT NULL,
  provider_wallet_id text CHECK (length(provider_wallet_id) BETWEEN 1 AND 200),
  verified_at timestamptz NOT NULL,
  revoked_at timestamptz CHECK (revoked_at >= verified_at),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (network, address),
  UNIQUE (id, user_id)
);

CREATE TABLE trimmy.assets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  asset_key text NOT NULL UNIQUE CHECK (asset_key ~ '^[a-z0-9][a-z0-9_-]{1,79}$'),
  symbol text NOT NULL CHECK (length(symbol) BETWEEN 1 AND 30),
  legal_name text NOT NULL CHECK (length(legal_name) BETWEEN 1 AND 300),
  issuer text NOT NULL CHECK (length(issuer) BETWEEN 1 AND 200),
  network text NOT NULL CHECK (network IN ('mainnet-beta', 'devnet', 'localnet')),
  mint trimmy.solana_address NOT NULL,
  token_program trimmy.solana_address NOT NULL CHECK (token_program IN (
    'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA',
    'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb')),
  decimals smallint NOT NULL CHECK (decimals BETWEEN 0 AND 18),
  extensions jsonb NOT NULL DEFAULT '[]' CHECK (jsonb_typeof(extensions) = 'array'),
  status text NOT NULL DEFAULT 'disabled'
    CHECK (status IN ('disabled', 'reviewing', 'enabled', 'suspended', 'retired')),
  verified_at timestamptz,
  verification_reference text,
  extensions_reviewed_at timestamptz,
  legal_document_url text CHECK (legal_document_url ~ '^https://'),
  legal_document_version text,
  eligibility_policy_version text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (network, mint),
  CHECK (status <> 'enabled' OR (
    verified_at IS NOT NULL AND extensions_reviewed_at IS NOT NULL
    AND coalesce(length(verification_reference), 0) > 0
    AND legal_document_url IS NOT NULL
    AND coalesce(length(legal_document_version), 0) > 0
    AND coalesce(length(eligibility_policy_version), 0) > 0))
);
-- No asset rows are seeded. Catalog presence and enabled status are distinct.

CREATE TABLE trimmy.eligibility_attestations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES trimmy.users(id),
  identity_id uuid NOT NULL,
  asset_id uuid NOT NULL REFERENCES trimmy.assets(id),
  country_code text NOT NULL CHECK (country_code ~ '^[A-Z]{2}$'),
  policy_version text NOT NULL CHECK (length(policy_version) BETWEEN 1 AND 100),
  decision text NOT NULL CHECK (decision IN ('eligible', 'ineligible', 'pending')),
  reason_code text NOT NULL CHECK (length(reason_code) BETWEEN 1 AND 100),
  evidence_reference text NOT NULL CHECK (length(evidence_reference) BETWEEN 1 AND 500),
  issued_at timestamptz NOT NULL,
  expires_at timestamptz NOT NULL CHECK (expires_at > issued_at),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (identity_id, user_id) REFERENCES trimmy.provider_identities(id, user_id),
  UNIQUE (id, user_id, asset_id)
);
CREATE INDEX eligibility_lookup ON trimmy.eligibility_attestations
  (user_id, asset_id, policy_version, expires_at DESC);

-- Immutable signed decisions remain historical evidence; revocation is separate.
CREATE TABLE trimmy.eligibility_revocations (
  attestation_id uuid PRIMARY KEY REFERENCES trimmy.eligibility_attestations(id),
  reason_code text NOT NULL CHECK (length(reason_code) BETWEEN 1 AND 100),
  revoked_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE trimmy.invitations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_user_id uuid NOT NULL REFERENCES trimmy.users(id),
  recipient_provider text CHECK (recipient_provider = 'x'),
  recipient_subject text CHECK (recipient_subject ~ '^[0-9]{1,30}$'),
  recipient_handle_snapshot text,
  recipient_user_id uuid REFERENCES trimmy.users(id),
  state text NOT NULL DEFAULT 'draft' CHECK (state IN (
    'draft', 'addressed', 'offered', 'accepted', 'declined', 'expired', 'canceled')),
  funding_kind text NOT NULL DEFAULT 'unfunded' CHECK (funding_kind = 'unfunded'),
  asset_id uuid REFERENCES trimmy.assets(id),
  indicative_amount_raw trimmy.raw_amount CHECK (indicative_amount_raw > 0),
  expires_at timestamptz NOT NULL,
  accepted_at timestamptz,
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (expires_at > created_at),
  CHECK ((recipient_provider IS NULL) = (recipient_subject IS NULL)),
  CHECK (state IN ('draft', 'canceled', 'expired') OR recipient_subject IS NOT NULL),
  CHECK ((state = 'accepted') = (accepted_at IS NOT NULL)),
  CHECK (state <> 'accepted' OR (recipient_user_id IS NOT NULL AND accepted_at < expires_at)),
  CHECK (recipient_user_id IS NULL OR recipient_user_id <> sender_user_id),
  CHECK ((indicative_amount_raw IS NULL) OR asset_id IS NOT NULL),
  FOREIGN KEY (recipient_provider, recipient_subject, recipient_user_id)
    REFERENCES trimmy.provider_identities(provider, subject, user_id)
);
CREATE INDEX invitation_recipient_lookup ON trimmy.invitations (recipient_provider, recipient_subject, created_at DESC);
CREATE INDEX invitation_expiry_work ON trimmy.invitations (expires_at) WHERE state IN ('draft', 'addressed', 'offered');

CREATE TABLE trimmy.idempotency_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES trimmy.users(id),
  operation text NOT NULL CHECK (length(operation) BETWEEN 1 AND 100),
  idempotency_key text NOT NULL CHECK (length(idempotency_key) BETWEEN 1 AND 128),
  request_hash trimmy.sha256_hex NOT NULL,
  status text NOT NULL DEFAULT 'processing' CHECK (status IN ('processing', 'completed', 'failed')),
  response_status smallint CHECK (response_status BETWEEN 100 AND 599),
  response_body jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  CHECK (expires_at > created_at),
  CHECK (status = 'processing' OR response_status IS NOT NULL),
  UNIQUE (user_id, operation, idempotency_key),
  UNIQUE (id, user_id)
);

CREATE TABLE trimmy.financial_intents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES trimmy.users(id),
  idempotency_record_id uuid NOT NULL UNIQUE,
  invitation_id uuid REFERENCES trimmy.invitations(id),
  operation text NOT NULL CHECK (operation IN ('transfer', 'swap', 'refund')),
  execution_mode text NOT NULL DEFAULT 'practice' CHECK (execution_mode IN ('practice', 'testnet', 'live')),
  input_asset_id uuid NOT NULL REFERENCES trimmy.assets(id),
  output_asset_id uuid REFERENCES trimmy.assets(id),
  input_amount_raw trimmy.raw_amount NOT NULL CHECK (input_amount_raw > 0),
  minimum_output_raw trimmy.raw_amount CHECK (minimum_output_raw > 0),
  source_wallet_id uuid NOT NULL,
  destination_address trimmy.solana_address NOT NULL,
  authorization_attestation_id uuid,
  quote_reference text,
  quote_expires_at timestamptz,
  state text NOT NULL DEFAULT 'draft' CHECK (state IN (
    'draft', 'awaiting_authorization', 'authorized', 'submitted', 'confirmed', 'failed', 'expired', 'canceled')),
  version bigint NOT NULL DEFAULT 0 CHECK (version >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  FOREIGN KEY (idempotency_record_id, user_id) REFERENCES trimmy.idempotency_records(id, user_id),
  FOREIGN KEY (source_wallet_id, user_id) REFERENCES trimmy.wallet_bindings(id, user_id),
  FOREIGN KEY (authorization_attestation_id, user_id, input_asset_id)
    REFERENCES trimmy.eligibility_attestations(id, user_id, asset_id),
  CHECK (expires_at > created_at),
  CHECK (operation <> 'swap' OR (
    output_asset_id IS NOT NULL AND output_asset_id <> input_asset_id
    AND minimum_output_raw IS NOT NULL AND quote_reference IS NOT NULL
    AND quote_expires_at IS NOT NULL)),
  CHECK (execution_mode <> 'live' OR state NOT IN ('authorized', 'submitted', 'confirmed')
    OR authorization_attestation_id IS NOT NULL),
  -- Remove only in a reviewed release migration after live authorization exists.
  CONSTRAINT live_operations_disabled_in_foundation CHECK (execution_mode <> 'live')
);

CREATE TABLE trimmy.execution_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  intent_id uuid NOT NULL REFERENCES trimmy.financial_intents(id),
  attempt_number integer NOT NULL CHECK (attempt_number > 0),
  network text NOT NULL CHECK (network IN ('mainnet-beta', 'devnet', 'localnet')),
  state text NOT NULL DEFAULT 'prepared' CHECK (state IN (
    'prepared', 'submitted', 'confirmed', 'finalized', 'failed', 'expired')),
  transaction_message_hash trimmy.sha256_hex NOT NULL,
  transaction_signature text CHECK (transaction_signature ~ '^[1-9A-HJ-NP-Za-km-z]{64,88}$'),
  last_valid_block_height bigint CHECK (last_valid_block_height >= 0),
  observed_slot bigint CHECK (observed_slot >= 0),
  actual_output_raw trimmy.raw_amount,
  error_code text,
  submitted_at timestamptz,
  settled_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (intent_id, attempt_number),
  UNIQUE (network, transaction_signature),
  CHECK (state NOT IN ('submitted', 'confirmed', 'finalized') OR (
    transaction_signature IS NOT NULL AND submitted_at IS NOT NULL)),
  CHECK (state NOT IN ('confirmed', 'finalized') OR (
    observed_slot IS NOT NULL AND settled_at IS NOT NULL)),
  CHECK (settled_at IS NULL OR submitted_at IS NOT NULL AND settled_at >= submitted_at),
  CONSTRAINT mainnet_execution_disabled_in_foundation CHECK (network <> 'mainnet-beta')
);
CREATE UNIQUE INDEX one_unresolved_attempt_per_intent ON trimmy.execution_attempts (intent_id)
  WHERE state IN ('prepared', 'submitted', 'confirmed');
CREATE UNIQUE INDEX one_success_per_intent ON trimmy.execution_attempts (intent_id)
  WHERE state IN ('confirmed', 'finalized');

CREATE TABLE trimmy.inbox_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider text NOT NULL CHECK (length(provider) BETWEEN 1 AND 100),
  provider_event_id text NOT NULL CHECK (length(provider_event_id) BETWEEN 1 AND 200),
  payload_hash trimmy.sha256_hex NOT NULL,
  payload jsonb NOT NULL CHECK (jsonb_typeof(payload) = 'object'),
  signature_verified_at timestamptz,
  state text NOT NULL DEFAULT 'received' CHECK (state IN ('received', 'processing', 'processed', 'failed')),
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  received_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  UNIQUE (provider, provider_event_id),
  CHECK (state NOT IN ('processing', 'processed') OR signature_verified_at IS NOT NULL),
  CHECK ((state = 'processed') = (processed_at IS NOT NULL))
);

CREATE TABLE trimmy.outbox_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  topic text NOT NULL CHECK (length(topic) BETWEEN 1 AND 100),
  deduplication_key text NOT NULL CHECK (length(deduplication_key) BETWEEN 1 AND 200),
  aggregate_type text NOT NULL CHECK (length(aggregate_type) BETWEEN 1 AND 100),
  aggregate_id uuid NOT NULL,
  payload jsonb NOT NULL CHECK (jsonb_typeof(payload) = 'object'),
  state text NOT NULL DEFAULT 'pending' CHECK (state IN ('pending', 'processing', 'published', 'dead')),
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  available_at timestamptz NOT NULL DEFAULT now(),
  locked_by text,
  locked_until timestamptz,
  published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (topic, deduplication_key),
  CHECK ((locked_by IS NULL) = (locked_until IS NULL)),
  CHECK ((state = 'processing') = (locked_until IS NOT NULL)),
  CHECK ((state = 'published') = (published_at IS NOT NULL))
);
CREATE INDEX outbox_pending_work ON trimmy.outbox_events (available_at, created_at) WHERE state = 'pending';
CREATE INDEX outbox_expired_leases ON trimmy.outbox_events (locked_until) WHERE state = 'processing';

CREATE TABLE trimmy.audit_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  database_role name NOT NULL DEFAULT current_user,
  actor_user_id uuid REFERENCES trimmy.users(id),
  action text NOT NULL CHECK (length(action) BETWEEN 1 AND 150),
  entity_type text NOT NULL CHECK (length(entity_type) BETWEEN 1 AND 100),
  entity_id text NOT NULL,
  detail jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(detail) = 'object'),
  occurred_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX audit_entity_history ON trimmy.audit_events (entity_type, entity_id, occurred_at DESC);

CREATE FUNCTION trimmy.reject_mutation() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy AS $$
BEGIN
  RAISE EXCEPTION '% is append-only; write a new event or revocation', TG_TABLE_NAME USING ERRCODE = '23514';
END;
$$;

CREATE FUNCTION trimmy.protect_binding() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy AS $$
BEGIN
  IF NEW.id <> OLD.id OR NEW.user_id <> OLD.user_id THEN
    RAISE EXCEPTION 'Binding identity and owner are immutable' USING ERRCODE = '23514';
  END IF;
  IF TG_TABLE_NAME = 'provider_identities' THEN
    IF (NEW.provider, NEW.subject) IS DISTINCT FROM (OLD.provider, OLD.subject) THEN
      RAISE EXCEPTION 'Provider subject is immutable' USING ERRCODE = '23514';
    END IF;
  ELSE
    IF (NEW.network, NEW.address) IS DISTINCT FROM (OLD.network, OLD.address) THEN
      RAISE EXCEPTION 'Wallet address and network are immutable' USING ERRCODE = '23514';
    END IF;
    IF OLD.revoked_at IS NOT NULL AND NEW.revoked_at IS DISTINCT FROM OLD.revoked_at THEN
      RAISE EXCEPTION 'A revoked binding cannot be silently reactivated' USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE FUNCTION trimmy.protect_invitation() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.state <> 'draft' OR NEW.version <> 0 THEN
      RAISE EXCEPTION 'Invitations start as unfunded drafts at version zero' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.id <> OLD.id OR NEW.sender_user_id <> OLD.sender_user_id OR NEW.created_at <> OLD.created_at THEN
    RAISE EXCEPTION 'Invitation identity and sender are immutable' USING ERRCODE = '23514';
  END IF;
  IF NEW.version <> OLD.version + 1 THEN
    RAISE EXCEPTION 'Invitation update must advance version exactly once' USING ERRCODE = '23514';
  END IF;
  IF OLD.recipient_subject IS NOT NULL AND (NEW.recipient_provider, NEW.recipient_subject)
      IS DISTINCT FROM (OLD.recipient_provider, OLD.recipient_subject) THEN
    RAISE EXCEPTION 'Addressed recipient is immutable' USING ERRCODE = '23514';
  END IF;
  IF OLD.state IN ('accepted', 'declined', 'expired', 'canceled') THEN
    RAISE EXCEPTION 'Invitation is terminal' USING ERRCODE = '23514';
  END IF;
  IF OLD.state <> 'draft' AND (NEW.asset_id, NEW.indicative_amount_raw, NEW.expires_at)
      IS DISTINCT FROM (OLD.asset_id, OLD.indicative_amount_raw, OLD.expires_at) THEN
    RAISE EXCEPTION 'Addressed invitation terms are immutable' USING ERRCODE = '23514';
  END IF;
  IF NEW.state <> OLD.state AND NOT (
    OLD.state = 'draft' AND NEW.state IN ('addressed', 'canceled', 'expired') OR
    OLD.state = 'addressed' AND NEW.state IN ('offered', 'canceled', 'expired') OR
    OLD.state = 'offered' AND NEW.state IN ('accepted', 'declined', 'canceled', 'expired')) THEN
    RAISE EXCEPTION 'Invalid invitation transition: % -> %', OLD.state, NEW.state USING ERRCODE = '23514';
  END IF;
  IF NEW.state = 'accepted' AND (clock_timestamp() >= NEW.expires_at OR NEW.accepted_at < NEW.created_at) THEN
    RAISE EXCEPTION 'Cannot accept an expired invitation or backdate acceptance before creation' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE FUNCTION trimmy.protect_asset() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy AS $$
BEGIN
  IF (NEW.id, NEW.asset_key, NEW.network, NEW.mint, NEW.token_program, NEW.decimals)
      IS DISTINCT FROM (OLD.id, OLD.asset_key, OLD.network, OLD.mint, OLD.token_program, OLD.decimals) THEN
    RAISE EXCEPTION 'An asset binding is immutable; create a new registry record' USING ERRCODE = '23514';
  END IF;
  IF NEW.extensions IS DISTINCT FROM OLD.extensions AND NEW.status = 'enabled' THEN
    RAISE EXCEPTION 'Changed extensions require disabling and reviewing the asset again' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE FUNCTION trimmy.protect_intent() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy AS $$
DECLARE asset_network text; wallet_network text; output_network text;
BEGIN
  SELECT network INTO asset_network FROM trimmy.assets WHERE id = NEW.input_asset_id;
  SELECT network INTO wallet_network FROM trimmy.wallet_bindings WHERE id = NEW.source_wallet_id;
  SELECT network INTO output_network FROM trimmy.assets WHERE id = NEW.output_asset_id;
  IF asset_network <> wallet_network OR output_network <> asset_network THEN
    RAISE EXCEPTION 'Intent assets and source wallet must use the same network' USING ERRCODE = '23514';
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.state <> 'draft' OR NEW.version <> 0 THEN
      RAISE EXCEPTION 'Financial intents start as drafts at version zero' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
  END IF;
  IF (NEW.id, NEW.user_id, NEW.idempotency_record_id, NEW.created_at)
      IS DISTINCT FROM (OLD.id, OLD.user_id, OLD.idempotency_record_id, OLD.created_at) THEN
    RAISE EXCEPTION 'Intent identity and request binding are immutable' USING ERRCODE = '23514';
  END IF;
  IF NEW.version <> OLD.version + 1 THEN
    RAISE EXCEPTION 'Intent update must advance version exactly once' USING ERRCODE = '23514';
  END IF;
  IF OLD.state IN ('confirmed', 'failed', 'expired', 'canceled') THEN
    RAISE EXCEPTION 'Intent is terminal' USING ERRCODE = '23514';
  END IF;
  IF OLD.state IN ('authorized', 'submitted') AND
      (to_jsonb(NEW) - 'state' - 'version') IS DISTINCT FROM (to_jsonb(OLD) - 'state' - 'version') THEN
    RAISE EXCEPTION 'Authorized financial terms are immutable' USING ERRCODE = '23514';
  END IF;
  IF NEW.state <> OLD.state AND NOT (
    OLD.state = 'draft' AND NEW.state IN ('awaiting_authorization', 'canceled', 'expired') OR
    OLD.state = 'awaiting_authorization' AND NEW.state IN ('authorized', 'canceled', 'expired', 'failed') OR
    OLD.state = 'authorized' AND NEW.state IN ('submitted', 'canceled', 'expired', 'failed') OR
    OLD.state = 'submitted' AND NEW.state IN ('confirmed', 'expired', 'failed')) THEN
    RAISE EXCEPTION 'Invalid intent transition' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE FUNCTION trimmy.protect_execution() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy AS $$
DECLARE asset_network text;
BEGIN
  -- Serialize attempts for an intent, including checks spanning existing attempts.
  PERFORM 1 FROM trimmy.financial_intents WHERE id = NEW.intent_id FOR UPDATE;
  SELECT a.network INTO asset_network FROM trimmy.financial_intents i
    JOIN trimmy.assets a ON a.id = i.input_asset_id WHERE i.id = NEW.intent_id;
  IF NEW.network <> asset_network THEN
    RAISE EXCEPTION 'Execution network does not match intent asset' USING ERRCODE = '23514';
  END IF;
  IF EXISTS (SELECT 1 FROM trimmy.execution_attempts
      WHERE intent_id = NEW.intent_id AND id <> NEW.id AND state = 'finalized') THEN
    RAISE EXCEPTION 'A finalized intent cannot acquire another execution attempt' USING ERRCODE = '23514';
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.state <> 'prepared' THEN
      RAISE EXCEPTION 'Execution attempts start as prepared' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
  END IF;
  IF (NEW.id, NEW.intent_id, NEW.attempt_number, NEW.network, NEW.transaction_message_hash)
      IS DISTINCT FROM (OLD.id, OLD.intent_id, OLD.attempt_number, OLD.network, OLD.transaction_message_hash) THEN
    RAISE EXCEPTION 'Execution identity and message are immutable' USING ERRCODE = '23514';
  END IF;
  IF OLD.transaction_signature IS NOT NULL AND NEW.transaction_signature IS DISTINCT FROM OLD.transaction_signature THEN
    RAISE EXCEPTION 'Submitted transaction signature is immutable' USING ERRCODE = '23514';
  END IF;
  IF OLD.state IN ('finalized', 'failed', 'expired') THEN
    RAISE EXCEPTION 'Execution attempt is terminal' USING ERRCODE = '23514';
  END IF;
  IF NEW.state <> OLD.state AND NOT (
    OLD.state = 'prepared' AND NEW.state IN ('submitted', 'failed', 'expired') OR
    OLD.state = 'submitted' AND NEW.state IN ('confirmed', 'finalized', 'failed', 'expired') OR
    OLD.state = 'confirmed' AND NEW.state IN ('finalized', 'failed')) THEN
    RAISE EXCEPTION 'Invalid execution transition' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE FUNCTION trimmy.protect_idempotency() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy AS $$
BEGIN
  IF (NEW.id, NEW.user_id, NEW.operation, NEW.idempotency_key, NEW.request_hash, NEW.created_at)
      IS DISTINCT FROM (OLD.id, OLD.user_id, OLD.operation, OLD.idempotency_key, OLD.request_hash, OLD.created_at) THEN
    RAISE EXCEPTION 'An idempotency key is permanently bound to its original request' USING ERRCODE = '23514';
  END IF;
  IF OLD.status IN ('completed', 'failed') THEN
    RAISE EXCEPTION 'A completed idempotency response cannot be rewritten' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE FUNCTION trimmy.record_change() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, trimmy AS $$
DECLARE row_data jsonb := to_jsonb(NEW);
BEGIN
  INSERT INTO trimmy.audit_events (action, entity_type, entity_id, detail)
  VALUES (lower(TG_OP), TG_TABLE_NAME, coalesce(row_data->>'id', row_data->>'attestation_id'),
    jsonb_strip_nulls(jsonb_build_object('state', row_data->>'state', 'status', row_data->>'status')));
  RETURN NEW;
END;
$$;

CREATE TRIGGER identity_binding_immutable BEFORE UPDATE ON trimmy.provider_identities
  FOR EACH ROW EXECUTE FUNCTION trimmy.protect_binding();
CREATE TRIGGER wallet_binding_immutable BEFORE UPDATE ON trimmy.wallet_bindings
  FOR EACH ROW EXECUTE FUNCTION trimmy.protect_binding();
CREATE TRIGGER invitation_transition BEFORE INSERT OR UPDATE ON trimmy.invitations
  FOR EACH ROW EXECUTE FUNCTION trimmy.protect_invitation();
CREATE TRIGGER asset_binding_immutable BEFORE UPDATE ON trimmy.assets
  FOR EACH ROW EXECUTE FUNCTION trimmy.protect_asset();
CREATE TRIGGER intent_transition BEFORE INSERT OR UPDATE ON trimmy.financial_intents
  FOR EACH ROW EXECUTE FUNCTION trimmy.protect_intent();
CREATE TRIGGER execution_transition BEFORE INSERT OR UPDATE ON trimmy.execution_attempts
  FOR EACH ROW EXECUTE FUNCTION trimmy.protect_execution();
CREATE TRIGGER idempotency_binding_immutable BEFORE UPDATE ON trimmy.idempotency_records
  FOR EACH ROW EXECUTE FUNCTION trimmy.protect_idempotency();

DO $$
DECLARE table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY['provider_identities', 'wallet_bindings', 'assets',
    'eligibility_attestations', 'eligibility_revocations', 'invitations', 'financial_intents', 'execution_attempts']
  LOOP
    EXECUTE format('CREATE TRIGGER audit_change AFTER INSERT OR UPDATE ON trimmy.%I FOR EACH ROW EXECUTE FUNCTION trimmy.record_change()', table_name);
  END LOOP;
  FOREACH table_name IN ARRAY ARRAY['eligibility_attestations', 'eligibility_revocations', 'audit_events']
  LOOP
    EXECUTE format('CREATE TRIGGER append_only BEFORE UPDATE OR DELETE ON trimmy.%I FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation()', table_name);
  END LOOP;
  FOREACH table_name IN ARRAY ARRAY['provider_identities', 'wallet_bindings', 'assets', 'invitations',
    'financial_intents', 'execution_attempts']
  LOOP
    EXECUTE format('CREATE TRIGGER preserve_history BEFORE DELETE ON trimmy.%I FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation()', table_name);
  END LOOP;
  FOR table_name IN SELECT tablename FROM pg_tables WHERE schemaname = 'trimmy'
  LOOP
    EXECUTE format('ALTER TABLE trimmy.%I ENABLE ROW LEVEL SECURITY', table_name);
  END LOOP;
END;
$$;

REVOKE ALL ON ALL TABLES IN SCHEMA trimmy FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA trimmy FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA trimmy FROM PUBLIC;
REVOKE ALL ON DOMAIN trimmy.raw_amount, trimmy.solana_address, trimmy.sha256_hex FROM PUBLIC;

INSERT INTO trimmy.schema_migrations (version) VALUES ('0001_foundation');
COMMIT;
