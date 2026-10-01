BEGIN;
CREATE TABLE trimmy.wallet_transfers (
 id uuid PRIMARY KEY,
 user_id uuid NOT NULL REFERENCES trimmy.users(id),
 wallet text NOT NULL,
 details jsonb NOT NULL,
 expires_at timestamptz NOT NULL,
 status text NOT NULL DEFAULT 'reviewed' CHECK(status IN('reviewed','pending','confirmed','failed','expired')),
 signature text UNIQUE CHECK(signature IS NULL OR signature ~ '^[1-9A-HJ-NP-Za-km-z]{64,88}$'),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK(status NOT IN('pending','confirmed','failed') OR signature IS NOT NULL)
);
CREATE INDEX wallet_transfers_user ON trimmy.wallet_transfers(user_id,created_at DESC);
CREATE UNIQUE INDEX wallet_transfers_pending ON trimmy.wallet_transfers(user_id) WHERE status='pending';
ALTER TABLE trimmy.wallet_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.wallet_transfers FORCE ROW LEVEL SECURITY;
REVOKE ALL ON trimmy.wallet_transfers FROM PUBLIC;

CREATE FUNCTION trimmy.wallet_transfer_read(viewer uuid, selected_id uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
DECLARE result jsonb;
BEGIN
 IF trimmy.practice_current_user() IS DISTINCT FROM viewer OR NOT EXISTS(SELECT 1 FROM trimmy.users WHERE id=viewer AND status='active') THEN RAISE EXCEPTION 'ACCOUNT_REQUIRED'; END IF;
 SELECT details || jsonb_build_object('id',id,'user_id',user_id,'wallet',wallet,'status',status,'signature',signature) INTO result
 FROM trimmy.wallet_transfers WHERE user_id=viewer AND (selected_id IS NULL OR id=selected_id)
 ORDER BY CASE WHEN status='pending' THEN 0 ELSE 1 END,created_at DESC LIMIT 1;
 RETURN result;
END; $$;

CREATE FUNCTION trimmy.wallet_transfer_create(viewer uuid, selected_id uuid, detail jsonb) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
DECLARE expiry timestamptz;
BEGIN
 IF trimmy.practice_current_user() IS DISTINCT FROM viewer OR NOT EXISTS(SELECT 1 FROM trimmy.users WHERE id=viewer AND status='active') THEN RAISE EXCEPTION 'ACCOUNT_REQUIRED'; END IF;
 expiry := (detail->'review'->>'expiresAt')::timestamptz;
 IF selected_id IS NULL OR detail->>'id' IS DISTINCT FROM selected_id::text OR detail->>'user_id' IS DISTINCT FROM viewer::text
 OR detail->>'wallet' IS NULL OR detail->>'wallet' !~ '^[1-9A-HJ-NP-Za-km-z]{32,44}$'
 OR detail->'review'->>'from' IS DISTINCT FROM detail->>'wallet'
 OR detail->>'status' IS DISTINCT FROM 'reviewed' OR detail->>'signature' IS NOT NULL
 OR expiry IS NULL OR expiry<=clock_timestamp() OR expiry>clock_timestamp()+interval '95 seconds'
 OR detail->>'unsignedTransaction' IS NULL OR length(detail->>'unsignedTransaction') NOT BETWEEN 88 AND 1644
 OR length(detail::text)>12000 THEN RAISE EXCEPTION 'INVALID_REVIEW'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('trimmy.transfer:'||viewer::text,0));
 IF EXISTS(SELECT 1 FROM trimmy.wallet_transfers WHERE user_id=viewer AND status='pending') THEN RAISE EXCEPTION 'TRANSFER_PENDING'; END IF;
 -- A replacement review invalidates the old one before it can be signed later.
 UPDATE trimmy.wallet_transfers SET status='expired',updated_at=clock_timestamp() WHERE user_id=viewer AND status='reviewed';
 INSERT INTO trimmy.wallet_transfers(id,user_id,wallet,details,expires_at) VALUES(selected_id,viewer,detail->>'wallet',detail,expiry);
 RETURN trimmy.wallet_transfer_read(viewer,selected_id);
END; $$;

CREATE FUNCTION trimmy.wallet_transfer_begin(viewer uuid, selected_id uuid, selected_signature text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
DECLARE selected trimmy.wallet_transfers%ROWTYPE;
BEGIN
 IF trimmy.practice_current_user() IS DISTINCT FROM viewer OR NOT EXISTS(SELECT 1 FROM trimmy.users WHERE id=viewer AND status='active') THEN RAISE EXCEPTION 'ACCOUNT_REQUIRED'; END IF;
 IF selected_signature IS NULL OR selected_signature !~ '^[1-9A-HJ-NP-Za-km-z]{64,88}$' THEN RAISE EXCEPTION 'INVALID_SIGNATURE'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('trimmy.transfer:'||viewer::text,0));
 SELECT * INTO selected FROM trimmy.wallet_transfers WHERE id=selected_id AND user_id=viewer FOR UPDATE;
 IF selected.id IS NULL THEN RAISE EXCEPTION 'INVALID_REVIEW'; END IF;
 IF selected.signature=selected_signature THEN RETURN trimmy.wallet_transfer_read(viewer,selected_id)||jsonb_build_object('dispatch',false); END IF;
 IF selected.status<>'reviewed' OR selected.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'REVIEW_EXPIRED'; END IF;
 IF EXISTS(SELECT 1 FROM trimmy.wallet_transfers WHERE user_id=viewer AND status='pending') THEN RAISE EXCEPTION 'TRANSFER_PENDING'; END IF;
 UPDATE trimmy.wallet_transfers SET status='pending',signature=selected_signature,updated_at=clock_timestamp() WHERE id=selected_id;
 RETURN trimmy.wallet_transfer_read(viewer,selected_id)||jsonb_build_object('dispatch',true);
END; $$;

CREATE FUNCTION trimmy.wallet_transfer_resolve(viewer uuid, selected_id uuid, selected_status text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
BEGIN
 IF trimmy.practice_current_user() IS DISTINCT FROM viewer OR NOT EXISTS(SELECT 1 FROM trimmy.users WHERE id=viewer AND status='active') THEN RAISE EXCEPTION 'ACCOUNT_REQUIRED'; END IF;
 IF selected_status IS NULL OR selected_status NOT IN('confirmed','failed','expired') THEN RAISE EXCEPTION 'INVALID_STATUS'; END IF;
 UPDATE trimmy.wallet_transfers SET status=selected_status,updated_at=clock_timestamp() WHERE id=selected_id AND user_id=viewer AND status='pending';
 RETURN trimmy.wallet_transfer_read(viewer,selected_id);
END; $$;
REVOKE ALL ON FUNCTION trimmy.wallet_transfer_read(uuid,uuid),trimmy.wallet_transfer_create(uuid,uuid,jsonb),trimmy.wallet_transfer_begin(uuid,uuid,text),trimmy.wallet_transfer_resolve(uuid,uuid,text) FROM PUBLIC;
INSERT INTO trimmy.schema_migrations(version) VALUES('0037_durable_wallet_transfers');
COMMIT;
