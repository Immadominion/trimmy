BEGIN;
-- Keep the chain observation with settlement so a reopened order cannot lose
-- the minimum slot its next balance read must observe. Legacy rows stay null.
ALTER TABLE trimmy.live_stock_orders ADD COLUMN confirmed_slot bigint
 CHECK(confirmed_slot BETWEEN 1 AND 9007199254740991),
 ADD CONSTRAINT live_stock_orders_slot_settled
 CHECK(confirmed_slot IS NULL OR status IN ('confirmed','failed'));

CREATE OR REPLACE FUNCTION trimmy.live_order_read(viewer uuid, selected_id uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
DECLARE result jsonb;
BEGIN
 IF trimmy.practice_current_user() IS DISTINCT FROM viewer OR NOT EXISTS(SELECT 1 FROM trimmy.users WHERE id=viewer AND status='active') THEN RAISE EXCEPTION 'ACCOUNT_REQUIRED'; END IF;
 SELECT to_jsonb(o)-'unsigned_transaction'-'confirmed_slot'
  || jsonb_build_object('unsignedTransaction',encode(unsigned_transaction,'base64'))
  || CASE WHEN confirmed_slot IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('confirmedSlot',confirmed_slot) END INTO result
 FROM trimmy.live_stock_orders o WHERE user_id=viewer AND (selected_id IS NULL OR id=selected_id)
 ORDER BY CASE WHEN status='pending' THEN 0 ELSE 1 END,created_at DESC LIMIT 1;
 RETURN result;
END; $$;

-- Keep the three-argument entry point for rolling deployments. New servers
-- store status and its verified slot in the same transaction, not two writes.
CREATE FUNCTION trimmy.live_order_resolve(viewer uuid, selected_id uuid, selected_status text, observed_slot bigint) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
BEGIN
 IF trimmy.practice_current_user() IS DISTINCT FROM viewer OR NOT EXISTS(SELECT 1 FROM trimmy.users WHERE id=viewer AND status='active') THEN RAISE EXCEPTION 'ACCOUNT_REQUIRED'; END IF;
 IF selected_status IS NULL OR selected_status NOT IN('confirmed','failed','expired') THEN RAISE EXCEPTION 'INVALID_STATUS'; END IF;
 IF observed_slot IS NOT NULL AND (observed_slot<1 OR observed_slot>9007199254740991 OR selected_status='expired') THEN RAISE EXCEPTION 'INVALID_SLOT'; END IF;
 UPDATE trimmy.live_stock_orders SET status=selected_status,confirmed_slot=observed_slot,updated_at=clock_timestamp()
  WHERE id=selected_id AND user_id=viewer AND status='pending';
 RETURN trimmy.live_order_read(viewer,selected_id);
END; $$;
REVOKE ALL ON FUNCTION trimmy.live_order_resolve(uuid,uuid,text,bigint) FROM PUBLIC;
INSERT INTO trimmy.schema_migrations(version) VALUES('0034_live_order_confirmation_slot');
COMMIT;
