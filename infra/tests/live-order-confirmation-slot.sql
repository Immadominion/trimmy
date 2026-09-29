\set ON_ERROR_STOP on
BEGIN;
INSERT INTO trimmy.users(id) VALUES
 ('cf340000-0000-4000-a000-000000000001'),('cf340000-0000-4000-a000-000000000002');
INSERT INTO trimmy.live_stock_orders(id,user_id,wallet,review,unsigned_transaction,expires_at,status,signature)
 SELECT ('cf340000-0000-4000-b000-'||lpad(n::text,12,'0'))::uuid,
 'cf340000-0000-4000-a000-000000000001',repeat('1',32),'{}',decode(repeat('00',65),'hex'),now()+interval '30 seconds','pending',repeat(n::text,88)
 FROM generate_series(1,4) n;
SET LOCAL ROLE trimmy_practice_runtime;
SELECT set_config('trimmy.practice_user_id','cf340000-0000-4000-a000-000000000001',true);
DO $$
DECLARE viewer uuid := 'cf340000-0000-4000-a000-000000000001';
 target uuid := 'cf340000-0000-4000-b000-000000000001'; result jsonb;
BEGIN
 result:=trimmy.live_order_resolve(viewer,target,'confirmed',501);
 IF result->>'status'<>'confirmed' OR (result->>'confirmedSlot')::bigint<>501 THEN RAISE EXCEPTION 'settlement lost slot'; END IF;
 -- A later request, including a conflicting retry, must retain the first result.
 result:=trimmy.live_order_read(viewer,target);
 IF (result->>'confirmedSlot')::bigint IS DISTINCT FROM 501::bigint THEN RAISE EXCEPTION 'reload lost slot'; END IF;
 result:=trimmy.live_order_resolve(viewer,target,'failed',999);
 IF result->>'status'<>'confirmed' OR (result->>'confirmedSlot')::bigint<>501 THEN RAISE EXCEPTION 'retry overwrote settlement'; END IF;
 result:=trimmy.live_order_resolve(viewer,'cf340000-0000-4000-b000-000000000002','failed',502);
 IF result->>'status'<>'failed' OR (result->>'confirmedSlot')::bigint<>502 THEN RAISE EXCEPTION 'failed outcome lost slot'; END IF;
 result:=trimmy.live_order_resolve(viewer,'cf340000-0000-4000-b000-000000000003','expired',NULL);
 IF result->>'status'<>'expired' OR result ? 'confirmedSlot' THEN RAISE EXCEPTION 'expiry invented slot'; END IF;
 -- The previous API remains usable during rolling deployment.
 result:=trimmy.live_order_resolve(viewer,'cf340000-0000-4000-b000-000000000004','confirmed');
 IF result->>'status'<>'confirmed' OR result ? 'confirmedSlot' THEN RAISE EXCEPTION 'legacy resolution changed'; END IF;
 BEGIN
  PERFORM trimmy.live_order_resolve(viewer,target,'confirmed',0);
  RAISE EXCEPTION 'invalid slot accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'INVALID_SLOT' THEN RAISE; END IF; END;
 BEGIN
  PERFORM trimmy.live_order_resolve(viewer,target,'expired',501);
  RAISE EXCEPTION 'expiry slot accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'INVALID_SLOT' THEN RAISE; END IF; END;
 PERFORM set_config('trimmy.practice_user_id','cf340000-0000-4000-a000-000000000002',true);
 BEGIN
  PERFORM trimmy.live_order_resolve(viewer,target,'failed',502);
  RAISE EXCEPTION 'foreign identity accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'ACCOUNT_REQUIRED' THEN RAISE; END IF; END;
 IF trimmy.live_order_resolve('cf340000-0000-4000-a000-000000000002',target,'failed',502) IS NOT NULL THEN
  RAISE EXCEPTION 'foreign order visible';
 END IF;
END; $$;
ROLLBACK;
