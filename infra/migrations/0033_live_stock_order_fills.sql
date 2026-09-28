BEGIN;
-- What a confirmed order actually moved, read from its confirmed transaction:
-- the wallet's decrease in the input token and increase in the output token.
-- Reviewed quotes stay as they were; a fill is recorded once and never changed.
ALTER TABLE trimmy.live_stock_orders
 ADD COLUMN filled_input_raw text CHECK(filled_input_raw ~ '^(0|[1-9][0-9]{0,19})$'),
 ADD COLUMN filled_output_raw text CHECK(filled_output_raw ~ '^(0|[1-9][0-9]{0,19})$'),
 ADD CONSTRAINT live_stock_orders_fill_pair CHECK((filled_input_raw IS NULL)=(filled_output_raw IS NULL)),
 ADD CONSTRAINT live_stock_orders_fill_confirmed CHECK(filled_input_raw IS NULL OR status='confirmed');

CREATE FUNCTION trimmy.live_order_record_fill(viewer uuid, selected_id uuid, input_raw text, output_raw text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
BEGIN
 IF trimmy.practice_current_user() IS DISTINCT FROM viewer OR NOT EXISTS(SELECT 1 FROM trimmy.users WHERE id=viewer AND status='active') THEN RAISE EXCEPTION 'ACCOUNT_REQUIRED'; END IF;
 IF input_raw IS NULL OR output_raw IS NULL OR input_raw !~ '^(0|[1-9][0-9]{0,19})$' OR output_raw !~ '^(0|[1-9][0-9]{0,19})$'
 THEN RAISE EXCEPTION 'INVALID_REQUEST'; END IF;
 UPDATE trimmy.live_stock_orders SET filled_input_raw=input_raw,filled_output_raw=output_raw
  WHERE id=selected_id AND user_id=viewer AND status='confirmed' AND filled_input_raw IS NULL;
 RETURN FOUND;
END; $$;
REVOKE ALL ON FUNCTION trimmy.live_order_record_fill(uuid,uuid,text,text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION trimmy.live_order_history(viewer uuid, page_size integer DEFAULT 20,
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
  ),
  'fill',CASE WHEN o.filled_input_raw IS NULL THEN NULL
   ELSE jsonb_build_object('inputAmountRaw',o.filled_input_raw,'outputAmountRaw',o.filled_output_raw) END
 ) ORDER BY o.created_at DESC,o.id DESC),'[]'::jsonb) INTO result
 FROM (
  SELECT id,wallet,status,signature,created_at,updated_at,review,filled_input_raw,filled_output_raw
  FROM trimmy.live_stock_orders WHERE user_id=viewer AND signature IS NOT NULL
   AND (before_created_at IS NULL OR (created_at,id)<(before_created_at,before_id))
  ORDER BY created_at DESC,id DESC LIMIT page_size+1
 ) o;
 RETURN result;
END; $$;
REVOKE ALL ON FUNCTION trimmy.live_order_history(uuid,integer,timestamptz,uuid) FROM PUBLIC;
INSERT INTO trimmy.schema_migrations(version) VALUES('0033_live_stock_order_fills');
COMMIT;
