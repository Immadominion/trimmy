\set ON_ERROR_STOP on
BEGIN;
INSERT INTO trimmy.users(id) VALUES ('cf350000-0000-4000-a000-000000000001'),('cf350000-0000-4000-a000-000000000002');
INSERT INTO trimmy.live_stock_orders(id,user_id,wallet,review,unsigned_transaction,expires_at,status,signature)
 SELECT ('cf350000-0000-4000-b000-'||lpad(n::text,12,'0'))::uuid,
 'cf350000-0000-4000-a000-000000000001',repeat('1',32),'{}',decode(repeat('00',65),'hex'),now()+interval '30 seconds','pending',repeat(n::text,88)
 FROM generate_series(1,3) n;
SET LOCAL ROLE trimmy_practice_runtime;
SELECT set_config('trimmy.practice_user_id','cf350000-0000-4000-a000-000000000001',true);
DO $$
DECLARE viewer uuid:='cf350000-0000-4000-a000-000000000001'; other_user uuid:='cf350000-0000-4000-a000-000000000002';
 device uuid:='cf350000-0000-4000-c000-000000000001'; worker uuid:=gen_random_uuid(); second_worker uuid:=gen_random_uuid(); jobs jsonb; job uuid; recovered jsonb;
BEGIN
 PERFORM trimmy.push_device_set(viewer,device,repeat('a',24),'android');
 BEGIN
  PERFORM trimmy.push_device_set(other_user,device,repeat('a',24),'android');RAISE EXCEPTION 'foreign identity accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'ACCOUNT_REQUIRED' THEN RAISE; END IF; END;
 BEGIN
  PERFORM trimmy.push_device_set(viewer,device,'invalid token with spaces','android');RAISE EXCEPTION 'invalid token accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'INVALID_DEVICE' THEN RAISE; END IF; END;
 recovered:=trimmy.live_order_recovery_claim();
 IF jsonb_array_length(recovered)<>1 OR recovered->0->>'userId'<>viewer::text THEN RAISE EXCEPTION 'pending recovery not claimed'; END IF;
 IF trimmy.live_order_recovery_claim()->0->>'id'=recovered->0->>'id' THEN RAISE EXCEPTION 'duplicate pending recovery claim'; END IF;
 PERFORM trimmy.live_order_recovery_release((recovered->0->>'id')::uuid);
 PERFORM trimmy.live_order_resolve(viewer,'cf350000-0000-4000-b000-000000000001','confirmed',500);
 PERFORM trimmy.live_order_resolve(viewer,'cf350000-0000-4000-b000-000000000001','confirmed',501);
 jobs:=trimmy.trade_push_claim(worker,5);
 IF jsonb_array_length(jobs)<>1 OR jobs->0->>'status'<>'confirmed' OR jobs->0 ? 'token' THEN RAISE EXCEPTION 'missing, duplicate or leaked push'; END IF;
 job:=(jobs->0->>'id')::uuid;
 IF trimmy.trade_push_claim(second_worker,5)<>'[]'::jsonb THEN RAISE EXCEPTION 'duplicate delivery lease'; END IF;
 IF trimmy.trade_push_target(job,second_worker) IS NOT NULL OR trimmy.trade_push_finish(job,second_worker,'sent') THEN RAISE EXCEPTION 'foreign lease accepted'; END IF;
 IF trimmy.trade_push_target(job,worker) IS DISTINCT FROM repeat('a',24) THEN RAISE EXCEPTION 'target missing'; END IF;
 -- A normal token heartbeat does not invalidate an in-flight update.
 PERFORM trimmy.push_device_set(viewer,device,repeat('a',24),'android');
 IF trimmy.trade_push_target(job,worker) IS NULL THEN RAISE EXCEPTION 'heartbeat changed revision'; END IF;
 -- Rebinding the installation must suppress queued work for the previous owner.
 PERFORM set_config('trimmy.practice_user_id',other_user::text,true);
 PERFORM trimmy.push_device_set(other_user,device,repeat('b',24),'android');
 IF trimmy.trade_push_target(job,worker) IS NOT NULL THEN RAISE EXCEPTION 'old account receives push'; END IF;
 PERFORM trimmy.trade_push_finish(job,worker,'invalid_token');
 PERFORM set_config('trimmy.practice_user_id',viewer::text,true);
 PERFORM trimmy.push_device_remove(viewer,device); -- cannot delete another account's binding
 PERFORM trimmy.push_device_set(viewer,device,repeat('c',24),'android');
 PERFORM trimmy.live_order_resolve(viewer,'cf350000-0000-4000-b000-000000000002','failed',502);
 jobs:=trimmy.trade_push_claim(worker,5);job:=(jobs->0->>'id')::uuid;
 IF NOT trimmy.trade_push_finish(job,worker,'retry') THEN RAISE EXCEPTION 'retry rejected'; END IF;
 IF trimmy.trade_push_claim(worker,5)<>'[]'::jsonb THEN RAISE EXCEPTION 'retry backoff ignored'; END IF;
 PERFORM trimmy.push_device_remove(viewer,device);
 IF trimmy.trade_push_target(job,worker) IS NOT NULL THEN RAISE EXCEPTION 'opt-out ignored'; END IF;
 -- No opt-in means no delivery, even after successful settlement.
 PERFORM trimmy.live_order_resolve(viewer,'cf350000-0000-4000-b000-000000000003','confirmed',503);
 IF trimmy.trade_push_claim(worker,5)<>'[]'::jsonb THEN RAISE EXCEPTION 'unsolicited notification'; END IF;
 BEGIN
  PERFORM token FROM trimmy.push_devices;RAISE EXCEPTION 'runtime can read token table';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END; $$;
RESET ROLE;
-- Expired leases are recoverable, capped, and never retain a deleted target.
DO $$
DECLARE viewer uuid:='cf350000-0000-4000-a000-000000000001'; device uuid:='cf350000-0000-4000-c000-000000000001';
 worker uuid:=gen_random_uuid(); jobs jsonb; job uuid; i integer;
BEGIN
 PERFORM set_config('trimmy.practice_user_id',viewer::text,true);
 PERFORM trimmy.push_device_set(viewer,device,repeat('d',24),'android');
 INSERT INTO trimmy.outbox_events(topic,deduplication_key,aggregate_type,aggregate_id,payload)
 SELECT 'trade.push','retry-test','push_device',device,jsonb_build_object('userId',viewer,'orderId',gen_random_uuid(),'status','confirmed','revision',revision) FROM trimmy.push_devices WHERE installation_id=device;
 jobs:=trimmy.trade_push_claim(worker,5);job:=(jobs->0->>'id')::uuid;
 UPDATE trimmy.outbox_events SET locked_until=clock_timestamp()-interval '1 second' WHERE id=job;
 jobs:=trimmy.trade_push_claim(worker,5);
 IF jsonb_array_length(jobs)<>1 THEN RAISE EXCEPTION 'crash lease not recovered'; END IF;
 FOR i IN 2..6 LOOP
  PERFORM trimmy.trade_push_finish(job,worker,'retry');
  UPDATE trimmy.outbox_events SET available_at=clock_timestamp()-interval '1 second' WHERE id=job;
  jobs:=trimmy.trade_push_claim(worker,5);
 END LOOP;
 IF jobs<>'[]'::jsonb OR (SELECT state FROM trimmy.outbox_events WHERE id=job)<>'dead' THEN RAISE EXCEPTION 'unbounded retries'; END IF;
 UPDATE trimmy.users SET status='closed' WHERE id=viewer;
 IF EXISTS(SELECT 1 FROM trimmy.push_devices WHERE user_id=viewer) THEN RAISE EXCEPTION 'closure retained device'; END IF;
END; $$;
ROLLBACK;
