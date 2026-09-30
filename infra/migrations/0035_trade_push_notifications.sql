BEGIN;
CREATE TABLE trimmy.push_devices (
 installation_id uuid PRIMARY KEY,
 user_id uuid NOT NULL REFERENCES trimmy.users(id),
 token text NOT NULL UNIQUE CHECK(length(token) BETWEEN 20 AND 4096),
 platform text NOT NULL CHECK(platform IN ('android','ios')),
 revision uuid NOT NULL DEFAULT gen_random_uuid(),
 refreshed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE trimmy.push_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.push_devices FORCE ROW LEVEL SECURITY;
REVOKE ALL ON trimmy.push_devices FROM PUBLIC;

CREATE FUNCTION trimmy.push_device_set(viewer uuid, installation uuid, device_token text, device_platform text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
BEGIN
 IF trimmy.practice_current_user() IS DISTINCT FROM viewer OR NOT EXISTS(SELECT 1 FROM trimmy.users WHERE id=viewer AND status='active') THEN RAISE EXCEPTION 'ACCOUNT_REQUIRED'; END IF;
 IF installation IS NULL OR device_token IS NULL OR length(device_token) NOT BETWEEN 20 AND 4096 OR device_token !~ '^[A-Za-z0-9:_-]+$' OR device_platform IS NULL OR device_platform NOT IN ('android','ios') THEN RAISE EXCEPTION 'INVALID_DEVICE'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('trimmy.push-device',0));
 IF (SELECT count(*) FROM trimmy.push_devices WHERE user_id=viewer AND installation_id<>installation)>=10 THEN RAISE EXCEPTION 'DEVICE_LIMIT'; END IF;
 -- One token belongs to only one installation/account. Rotation or account
 -- change gets a new revision so queued work for the old identity is dropped.
 DELETE FROM trimmy.push_devices WHERE token=device_token AND installation_id<>installation;
 INSERT INTO trimmy.push_devices(installation_id,user_id,token,platform) VALUES(installation,viewer,device_token,device_platform)
 ON CONFLICT(installation_id) DO UPDATE SET user_id=excluded.user_id,token=excluded.token,platform=excluded.platform,
  revision=CASE WHEN push_devices.user_id=excluded.user_id AND push_devices.token=excluded.token THEN push_devices.revision ELSE gen_random_uuid() END,
  refreshed_at=clock_timestamp();
END; $$;
CREATE FUNCTION trimmy.push_device_remove(viewer uuid, installation uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
BEGIN
 IF trimmy.practice_current_user() IS DISTINCT FROM viewer THEN RAISE EXCEPTION 'ACCOUNT_REQUIRED'; END IF;
 DELETE FROM trimmy.push_devices WHERE installation_id=installation AND user_id=viewer;
END; $$;

CREATE FUNCTION trimmy.trade_push_enqueue() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
BEGIN
 IF OLD.status='pending' AND NEW.status IN ('confirmed','failed','expired') THEN
  INSERT INTO trimmy.outbox_events(topic,deduplication_key,aggregate_type,aggregate_id,payload)
   SELECT 'trade.push',NEW.id::text||':'||d.installation_id::text,'push_device',d.installation_id,
    jsonb_build_object('userId',NEW.user_id,'orderId',NEW.id,'status',NEW.status,'revision',d.revision)
   FROM trimmy.push_devices d JOIN trimmy.users u ON u.id=d.user_id
   WHERE d.user_id=NEW.user_id AND u.status='active' AND d.refreshed_at>clock_timestamp()-interval '30 days'
   ON CONFLICT(topic,deduplication_key) DO NOTHING;
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER trade_push_settled AFTER UPDATE OF status ON trimmy.live_stock_orders FOR EACH ROW EXECUTE FUNCTION trimmy.trade_push_enqueue();
CREATE FUNCTION trimmy.push_account_closed() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
BEGIN
 IF NEW.status<>'active' THEN DELETE FROM trimmy.push_devices WHERE user_id=NEW.id; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER push_account_closed AFTER UPDATE OF status ON trimmy.users FOR EACH ROW EXECUTE FUNCTION trimmy.push_account_closed();

-- Only this topic is claimable. Expiring leases allow recovery after a process
-- crash. No provider credential or token is copied into the durable payload.
CREATE FUNCTION trimmy.trade_push_claim(worker uuid, batch_size integer) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
DECLARE result jsonb;
BEGIN
 DELETE FROM trimmy.outbox_events WHERE topic='trade.push' AND state IN ('published','dead') AND created_at<clock_timestamp()-interval '7 days';
 IF worker IS NULL OR batch_size IS NULL OR batch_size<1 OR batch_size>20 THEN RAISE EXCEPTION 'INVALID_REQUEST'; END IF;
 UPDATE trimmy.outbox_events e SET state='dead',locked_by=NULL,locked_until=NULL
 WHERE e.topic='trade.push' AND e.state IN ('pending','processing')
 AND (e.created_at<clock_timestamp()-interval '24 hours' OR e.attempt_count>=6 OR NOT EXISTS(
  SELECT 1 FROM trimmy.push_devices d JOIN trimmy.users u ON u.id=d.user_id
  WHERE d.installation_id=e.aggregate_id AND u.status='active' AND d.user_id::text=e.payload->>'userId'
   AND d.revision::text=e.payload->>'revision' AND d.refreshed_at>clock_timestamp()-interval '30 days'))
 AND (e.state='pending' OR e.locked_until<clock_timestamp());
 WITH picked AS (
  SELECT id FROM trimmy.outbox_events WHERE topic='trade.push'
   AND ((state='pending' AND available_at<=clock_timestamp()) OR (state='processing' AND locked_until<clock_timestamp()))
  ORDER BY created_at FOR UPDATE SKIP LOCKED LIMIT batch_size
 ), claimed AS (
  UPDATE trimmy.outbox_events e SET state='processing',locked_by=worker::text,locked_until=clock_timestamp()+interval '2 minutes',attempt_count=attempt_count+1
  FROM picked WHERE e.id=picked.id RETURNING e.id,e.payload,e.aggregate_id
 ) SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'deviceId',aggregate_id,'userId',payload->>'userId','orderId',payload->>'orderId','status',payload->>'status')),'[]') INTO result FROM claimed;
 RETURN result;
END; $$;
CREATE FUNCTION trimmy.trade_push_target(job uuid, worker uuid) RETURNS text
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
 SELECT d.token FROM trimmy.outbox_events e JOIN trimmy.push_devices d ON d.installation_id=e.aggregate_id JOIN trimmy.users u ON u.id=d.user_id
 WHERE e.id=job AND e.topic='trade.push' AND e.state='processing' AND e.locked_by=worker::text AND e.locked_until>clock_timestamp()
  AND u.status='active' AND d.user_id::text=e.payload->>'userId' AND d.revision::text=e.payload->>'revision'
  AND d.refreshed_at>clock_timestamp()-interval '30 days';
$$;
CREATE FUNCTION trimmy.trade_push_finish(job uuid, worker uuid, outcome text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
DECLARE selected trimmy.outbox_events%ROWTYPE;
BEGIN
 IF outcome IS NULL OR outcome NOT IN ('sent','retry','invalid_token','drop') THEN RAISE EXCEPTION 'INVALID_REQUEST'; END IF;
 SELECT * INTO selected FROM trimmy.outbox_events WHERE id=job AND topic='trade.push' AND state='processing' AND locked_by=worker::text AND locked_until>clock_timestamp() FOR UPDATE;
 IF selected.id IS NULL THEN RETURN false; END IF;
 IF outcome='invalid_token' THEN
  DELETE FROM trimmy.push_devices WHERE installation_id=selected.aggregate_id AND revision::text=selected.payload->>'revision';
 END IF;
 UPDATE trimmy.outbox_events SET state=CASE WHEN outcome='sent' THEN 'published' WHEN outcome='retry' AND attempt_count<6 THEN 'pending' ELSE 'dead' END,
  published_at=CASE WHEN outcome='sent' THEN clock_timestamp() ELSE NULL END,locked_by=NULL,locked_until=NULL,
  available_at=clock_timestamp()+make_interval(secs=>least(3600,60*power(2,attempt_count-1)::integer)) WHERE id=job;
 RETURN true;
END; $$;
-- Recovery reads already-submitted transactions. It never signs or submits.
ALTER TABLE trimmy.live_stock_orders ADD COLUMN recovery_after timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE INDEX live_order_recovery_due ON trimmy.live_stock_orders(recovery_after) WHERE status='pending';
CREATE FUNCTION trimmy.live_order_recovery_claim() RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
 WITH picked AS (
  SELECT o.id FROM trimmy.live_stock_orders o JOIN trimmy.users u ON u.id=o.user_id
  WHERE o.status='pending' AND o.recovery_after<=clock_timestamp() AND u.status='active'
  ORDER BY o.recovery_after FOR UPDATE OF o SKIP LOCKED LIMIT 1
 ), claimed AS (
  UPDATE trimmy.live_stock_orders o SET recovery_after=clock_timestamp()+interval '10 minutes'
  FROM picked WHERE o.id=picked.id RETURNING o.id,o.user_id
 ) SELECT coalesce(jsonb_agg(jsonb_build_object('id',id,'userId',user_id)),'[]') FROM claimed;
$$;
CREATE FUNCTION trimmy.live_order_recovery_release(selected_id uuid) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
 UPDATE trimmy.live_stock_orders SET recovery_after=clock_timestamp()+interval '30 seconds' WHERE id=selected_id AND status='pending';
$$;
REVOKE ALL ON FUNCTION trimmy.live_order_recovery_claim(),trimmy.live_order_recovery_release(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION trimmy.push_device_set(uuid,uuid,text,text),trimmy.push_device_remove(uuid,uuid),trimmy.trade_push_enqueue(),trimmy.push_account_closed(),trimmy.trade_push_claim(uuid,integer),trimmy.trade_push_target(uuid,uuid),trimmy.trade_push_finish(uuid,uuid,text) FROM PUBLIC;
INSERT INTO trimmy.schema_migrations(version) VALUES('0035_trade_push_notifications');
COMMIT;
