BEGIN;
-- Trade-update pushes in the player's language. Each device keeps the
-- language its app last reported; devices that never report one, including
-- every app installed before this, stay English.
ALTER TABLE trimmy.push_devices
  ADD COLUMN language text NOT NULL DEFAULT 'en' CHECK (language IN ('en', 'es', 'pt', 'fr'));

-- Sets the language of the viewer's own device. A device of another account,
-- or one not registered yet, is left alone and reported as not found.
CREATE FUNCTION trimmy.push_device_language(viewer uuid, installation uuid, device_language text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
DECLARE changed integer;
BEGIN
 IF trimmy.practice_current_user() IS DISTINCT FROM viewer THEN RAISE EXCEPTION 'ACCOUNT_REQUIRED'; END IF;
 IF device_language IS NULL OR device_language NOT IN ('en', 'es', 'pt', 'fr') THEN RAISE EXCEPTION 'INVALID_REQUEST'; END IF;
 UPDATE trimmy.push_devices SET language=device_language WHERE installation_id=installation AND user_id=viewer;
 GET DIAGNOSTICS changed = ROW_COUNT;
 RETURN changed = 1;
END; $$;

-- The language for a claimed job's device, under the same conditions as
-- trade_push_target, so a worker reads it only for a job it holds.
CREATE FUNCTION trimmy.trade_push_language(job uuid, worker uuid) RETURNS text
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
 SELECT d.language FROM trimmy.outbox_events e JOIN trimmy.push_devices d ON d.installation_id=e.aggregate_id JOIN trimmy.users u ON u.id=d.user_id
 WHERE e.id=job AND e.topic='trade.push' AND e.state='processing' AND e.locked_by=worker::text AND e.locked_until>clock_timestamp()
  AND u.status='active' AND d.user_id::text=e.payload->>'userId' AND d.revision::text=e.payload->>'revision';
$$;

REVOKE ALL ON FUNCTION trimmy.push_device_language(uuid,uuid,text), trimmy.trade_push_language(uuid,uuid) FROM PUBLIC;
INSERT INTO trimmy.schema_migrations(version) VALUES('0040_push_language');
COMMIT;
