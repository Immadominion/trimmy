BEGIN;
-- The runtime gets one owner-scoped read function, never table access or wires.
CREATE INDEX live_stock_orders_history ON trimmy.live_stock_orders(user_id,created_at DESC,id DESC)
 WHERE signature IS NOT NULL;

CREATE FUNCTION trimmy.live_order_history(viewer uuid, page_size integer DEFAULT 20,
 before_created_at timestamptz DEFAULT NULL, before_id uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
DECLARE result jsonb;
BEGIN
 IF trimmy.practice_current_user() IS DISTINCT FROM viewer OR NOT EXISTS(
  SELECT 1 FROM trimmy.users WHERE id=viewer AND status='active'
 ) THEN RAISE EXCEPTION 'ACCOUNT_REQUIRED'; END IF;
 IF page_size IS NULL OR page_size<1 OR page_size>50 OR
  (before_created_at IS NULL)<>(before_id IS NULL) OR
  (before_created_at IS NOT NULL AND NOT isfinite(before_created_at))
 THEN RAISE EXCEPTION 'INVALID_REQUEST'; END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'id',o.id,'wallet',o.wallet,'status',o.status,'signature',o.signature,
  -- Preserve microseconds: rounding to JavaScript milliseconds would skip rows.
  'createdAt',to_char(o.created_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'updatedAt',to_char(o.updated_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
  'terms',jsonb_build_object(
   'side',o.review->'terms'->>'side',
   'inputMint',o.review->'terms'->>'inputMint','outputMint',o.review->'terms'->>'outputMint',
   'inputAmountRaw',o.review->'terms'->>'inputAmountRaw',
   'quotedOutputAmountRaw',o.review->'terms'->>'quotedOutputAmountRaw',
   'minimumOutputAmountRaw',o.review->'terms'->>'minimumOutputAmountRaw'
  )
 ) ORDER BY o.created_at DESC,o.id DESC),'[]'::jsonb) INTO result
 FROM (
  SELECT id,wallet,status,signature,created_at,updated_at,review
  FROM trimmy.live_stock_orders WHERE user_id=viewer AND signature IS NOT NULL
   AND (before_created_at IS NULL OR (created_at,id)<(before_created_at,before_id))
  ORDER BY created_at DESC,id DESC LIMIT page_size+1
 ) o;
 RETURN result;
END; $$;
REVOKE ALL ON FUNCTION trimmy.live_order_history(uuid,integer,timestamptz,uuid) FROM PUBLIC;
INSERT INTO trimmy.schema_migrations(version) VALUES('0032_live_stock_order_history');
COMMIT;
