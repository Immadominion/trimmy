BEGIN;
CREATE TABLE trimmy.live_stock_orders (
 id uuid PRIMARY KEY,
 user_id uuid NOT NULL REFERENCES trimmy.users(id),
 wallet text NOT NULL,
 review jsonb NOT NULL,
 unsigned_transaction bytea NOT NULL CHECK(octet_length(unsigned_transaction) BETWEEN 65 AND 1232),
 expires_at timestamptz NOT NULL,
 status text NOT NULL DEFAULT 'reviewed' CHECK(status IN('reviewed','pending','confirmed','failed','expired')),
 signature text UNIQUE,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 CHECK((status='reviewed' AND signature IS NULL) OR status IN('expired') OR signature IS NOT NULL)
);
CREATE INDEX live_stock_orders_user ON trimmy.live_stock_orders(user_id,created_at DESC);
ALTER TABLE trimmy.live_stock_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.live_stock_orders FORCE ROW LEVEL SECURITY;
REVOKE ALL ON trimmy.live_stock_orders FROM PUBLIC;

CREATE FUNCTION trimmy.live_order_read(viewer uuid, selected_id uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
DECLARE result jsonb;
BEGIN
 IF trimmy.practice_current_user() IS DISTINCT FROM viewer OR NOT EXISTS(SELECT 1 FROM trimmy.users WHERE id=viewer AND status='active') THEN RAISE EXCEPTION 'ACCOUNT_REQUIRED'; END IF;
 SELECT to_jsonb(o)-'unsigned_transaction' || jsonb_build_object('unsignedTransaction',encode(unsigned_transaction,'base64')) INTO result
 FROM trimmy.live_stock_orders o WHERE user_id=viewer AND (selected_id IS NULL OR id=selected_id)
 ORDER BY CASE WHEN status='pending' THEN 0 ELSE 1 END,created_at DESC LIMIT 1;
 RETURN result;
END; $$;

CREATE FUNCTION trimmy.live_order_create(viewer uuid, selected_id uuid, selected_wallet text, selected_review jsonb, wire bytea, expiry timestamptz) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
BEGIN
 IF trimmy.practice_current_user() IS DISTINCT FROM viewer OR NOT EXISTS(SELECT 1 FROM trimmy.users WHERE id=viewer AND status='active') THEN RAISE EXCEPTION 'ACCOUNT_REQUIRED'; END IF;
 IF selected_wallet IS NULL OR selected_wallet !~ '^[1-9A-HJ-NP-Za-km-z]{32,44}$' OR selected_review->>'userId' IS DISTINCT FROM viewer::text OR selected_review->>'taker' IS DISTINCT FROM selected_wallet OR expiry<=clock_timestamp() OR expiry>clock_timestamp()+interval '45 seconds' THEN RAISE EXCEPTION 'INVALID_REVIEW'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('trimmy.live:'||viewer::text,0));
 IF EXISTS(SELECT 1 FROM trimmy.live_stock_orders WHERE user_id=viewer AND status='pending') THEN RAISE EXCEPTION 'ORDER_PENDING'; END IF;
 INSERT INTO trimmy.live_stock_orders(id,user_id,wallet,review,unsigned_transaction,expires_at) VALUES(selected_id,viewer,selected_wallet,selected_review,wire,expiry);
 RETURN trimmy.live_order_read(viewer,selected_id);
END; $$;

CREATE FUNCTION trimmy.live_order_begin(viewer uuid, selected_id uuid, digest text, selected_signature text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
DECLARE selected trimmy.live_stock_orders%ROWTYPE;
BEGIN
 IF trimmy.practice_current_user() IS DISTINCT FROM viewer OR NOT EXISTS(SELECT 1 FROM trimmy.users WHERE id=viewer AND status='active') THEN RAISE EXCEPTION 'ACCOUNT_REQUIRED'; END IF;
 IF selected_signature IS NULL OR selected_signature !~ '^[1-9A-HJ-NP-Za-km-z]{64,88}$' THEN RAISE EXCEPTION 'INVALID_SIGNATURE'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('trimmy.live:'||viewer::text,0));
 SELECT * INTO selected FROM trimmy.live_stock_orders WHERE id=selected_id AND user_id=viewer FOR UPDATE;
 IF selected.id IS NULL OR selected.review->>'reviewDigestSha256' IS DISTINCT FROM digest THEN RAISE EXCEPTION 'INVALID_REVIEW'; END IF;
 IF selected.status<>'reviewed' THEN
  IF selected.signature=selected_signature THEN RETURN trimmy.live_order_read(viewer,selected_id)||jsonb_build_object('dispatch',false); END IF;
  RAISE EXCEPTION 'INVALID_REVIEW';
 END IF;
 IF selected.expires_at<=clock_timestamp() THEN RAISE EXCEPTION 'QUOTE_EXPIRED'; END IF;
 IF EXISTS(SELECT 1 FROM trimmy.live_stock_orders WHERE user_id=viewer AND status='pending') THEN RAISE EXCEPTION 'ORDER_PENDING'; END IF;
 UPDATE trimmy.live_stock_orders SET status='pending',signature=selected_signature,updated_at=clock_timestamp() WHERE id=selected_id;
 RETURN trimmy.live_order_read(viewer,selected_id)||jsonb_build_object('dispatch',true);
END; $$;

CREATE FUNCTION trimmy.live_order_resolve(viewer uuid, selected_id uuid, selected_status text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
BEGIN
 IF trimmy.practice_current_user() IS DISTINCT FROM viewer OR NOT EXISTS(SELECT 1 FROM trimmy.users WHERE id=viewer AND status='active') THEN RAISE EXCEPTION 'ACCOUNT_REQUIRED'; END IF;
 IF selected_status IS NULL OR selected_status NOT IN('confirmed','failed','expired') THEN RAISE EXCEPTION 'INVALID_STATUS'; END IF;
 UPDATE trimmy.live_stock_orders SET status=selected_status,updated_at=clock_timestamp() WHERE id=selected_id AND user_id=viewer AND status='pending';
 RETURN trimmy.live_order_read(viewer,selected_id);
END; $$;
REVOKE ALL ON FUNCTION trimmy.live_order_read(uuid,uuid),trimmy.live_order_create(uuid,uuid,text,jsonb,bytea,timestamptz),trimmy.live_order_begin(uuid,uuid,text,text),trimmy.live_order_resolve(uuid,uuid,text) FROM PUBLIC;
INSERT INTO trimmy.schema_migrations(version) VALUES('0031_live_stock_orders');
COMMIT;
