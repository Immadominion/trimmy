\set ON_ERROR_STOP on
-- Migration 0040: a device's push language, set only by its own account and
-- read only by a worker holding that device's job.
BEGIN;
INSERT INTO trimmy.users(id) VALUES ('c4040000-0000-4000-a000-000000000001'),('c4040000-0000-4000-a000-000000000002');
SET LOCAL ROLE trimmy_practice_runtime;
DO $$
DECLARE viewer uuid:='c4040000-0000-4000-a000-000000000001'; other_user uuid:='c4040000-0000-4000-a000-000000000002';
 device uuid:='c4040000-0000-4000-c000-000000000001'; worker uuid:=gen_random_uuid(); other_worker uuid:=gen_random_uuid(); jobs jsonb; job uuid;
BEGIN
 PERFORM set_config('trimmy.practice_user_id',viewer::text,true);
 IF trimmy.push_device_language(viewer,device,'fr') THEN RAISE EXCEPTION 'an unregistered device took a language'; END IF;
 PERFORM trimmy.push_device_set(viewer,device,repeat('a',24),'android');
 BEGIN
  PERFORM trimmy.push_device_language(other_user,device,'es');RAISE EXCEPTION 'foreign identity accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'ACCOUNT_REQUIRED' THEN RAISE; END IF; END;
 BEGIN
  PERFORM trimmy.push_device_language(viewer,device,'de');RAISE EXCEPTION 'unknown language accepted';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM<>'INVALID_REQUEST' THEN RAISE; END IF; END;
 IF NOT trimmy.push_device_language(viewer,device,'fr') THEN RAISE EXCEPTION 'own device language not set'; END IF;
 -- A token heartbeat keeps the language.
 PERFORM trimmy.push_device_set(viewer,device,repeat('a',24),'android');
 BEGIN
  PERFORM language FROM trimmy.push_devices;RAISE EXCEPTION 'runtime can read the device table';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END; $$;
RESET ROLE;
-- As the owner: the stored value, and a queued update for the device.
DO $$
DECLARE viewer uuid:='c4040000-0000-4000-a000-000000000001'; device uuid:='c4040000-0000-4000-c000-000000000001';
BEGIN
 IF (SELECT language FROM trimmy.push_devices WHERE installation_id=device)<>'fr' THEN RAISE EXCEPTION 'language not stored'; END IF;
 INSERT INTO trimmy.outbox_events(topic,deduplication_key,aggregate_type,aggregate_id,payload)
 SELECT 'trade.push','language-test','push_device',device,jsonb_build_object('userId',viewer,'orderId',gen_random_uuid(),'status','confirmed','revision',revision)
 FROM trimmy.push_devices WHERE installation_id=device;
 BEGIN
  UPDATE trimmy.push_devices SET language='de' WHERE installation_id=device;RAISE EXCEPTION 'unknown language stored';
 EXCEPTION WHEN check_violation THEN NULL; END;
END; $$;
-- As the serving role, as the worker runs: only the lease holder reads the language.
SET LOCAL ROLE trimmy_practice_runtime;
DO $$
DECLARE worker uuid:=gen_random_uuid(); other_worker uuid:=gen_random_uuid(); jobs jsonb; job uuid;
BEGIN
 jobs:=trimmy.trade_push_claim(worker,5);job:=(jobs->0->>'id')::uuid;
 IF job IS NULL THEN RAISE EXCEPTION 'job not claimed'; END IF;
 IF trimmy.trade_push_language(job,other_worker) IS NOT NULL THEN RAISE EXCEPTION 'a worker without the lease read the language'; END IF;
 IF trimmy.trade_push_language(job,worker) IS DISTINCT FROM 'fr' THEN RAISE EXCEPTION 'job language missing'; END IF;
 PERFORM set_config('trimmy_test.job',job::text,true);
 PERFORM set_config('trimmy_test.worker',worker::text,true);
END; $$;
RESET ROLE;
-- Devices that never report a language stay English.
UPDATE trimmy.push_devices SET language=DEFAULT WHERE installation_id='c4040000-0000-4000-c000-000000000001';
SET LOCAL ROLE trimmy_practice_runtime;
DO $$
BEGIN
 IF trimmy.trade_push_language(current_setting('trimmy_test.job')::uuid,current_setting('trimmy_test.worker')::uuid) IS DISTINCT FROM 'en' THEN
  RAISE EXCEPTION 'default is not English';
 END IF;
END; $$;
RESET ROLE;
ROLLBACK;
