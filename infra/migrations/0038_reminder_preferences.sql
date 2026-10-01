BEGIN;
-- Guest claims keep users.id. Preferences follow that verified mapping without
-- copying consent to a different saved account.
CREATE TABLE trimmy.reminder_preferences (
 user_id uuid PRIMARY KEY REFERENCES trimmy.users(id),
 revision bigint NOT NULL CHECK(revision BETWEEN 1 AND 9007199254740991),
 frequency text NOT NULL CHECK(frequency IN('daily','occasional','off'))
);
CREATE TABLE trimmy.reminder_preference_receipts (
 user_id uuid NOT NULL REFERENCES trimmy.users(id), mutation_id uuid NOT NULL,
 base_revision bigint NOT NULL, frequency text NOT NULL,
 PRIMARY KEY(user_id,mutation_id)
);
ALTER TABLE trimmy.reminder_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.reminder_preferences FORCE ROW LEVEL SECURITY;
ALTER TABLE trimmy.reminder_preference_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.reminder_preference_receipts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON trimmy.reminder_preferences,trimmy.reminder_preference_receipts FROM PUBLIC;

CREATE FUNCTION trimmy.reminder_preference_scope(viewer uuid, guest uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
BEGIN
 IF trimmy.practice_current_user() IS DISTINCT FROM viewer OR NOT EXISTS(SELECT 1 FROM trimmy.users WHERE id=viewer AND status='active') THEN RAISE EXCEPTION 'ACCOUNT_REQUIRED'; END IF;
 IF guest IS NULL THEN
  IF NOT EXISTS(SELECT 1 FROM trimmy.practice_auth_identities WHERE user_id=viewer) THEN RAISE EXCEPTION 'ACCOUNT_REQUIRED'; END IF;
 ELSE
  -- Serialize guest writes/reads against claim and revocation.
  PERFORM 1 FROM trimmy.guest_sessions WHERE id=guest AND user_id=viewer AND state='active'
   AND expires_at>clock_timestamp() AND hard_expires_at>clock_timestamp() FOR SHARE;
  IF NOT FOUND OR EXISTS(SELECT 1 FROM trimmy.practice_auth_identities WHERE user_id=viewer) THEN RAISE EXCEPTION 'ACCOUNT_REQUIRED'; END IF;
 END IF;
END; $$;
CREATE FUNCTION trimmy.reminder_preference_get(viewer uuid, guest uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
DECLARE pref trimmy.reminder_preferences%ROWTYPE; claimed uuid;
BEGIN
 PERFORM trimmy.reminder_preference_scope(viewer,guest);
 SELECT * INTO pref FROM trimmy.reminder_preferences WHERE user_id=viewer;
 IF guest IS NULL THEN
  SELECT id INTO claimed FROM trimmy.guest_sessions WHERE user_id=viewer AND state='claimed' ORDER BY claimed_at DESC LIMIT 1;
 END IF;
 RETURN jsonb_build_object('schemaVersion',1,'revision',coalesce(pref.revision,0),'frequency',pref.frequency,'claimedGuestId',claimed);
END; $$;
CREATE FUNCTION trimmy.reminder_preference_put(viewer uuid, guest uuid, mutation uuid, base bigint, choice text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
DECLARE prior trimmy.reminder_preference_receipts%ROWTYPE; current_revision bigint;
BEGIN
 PERFORM trimmy.reminder_preference_scope(viewer,guest);
 IF mutation IS NULL OR base IS NULL OR base<0 OR base>9007199254740990 OR choice IS NULL OR choice NOT IN('daily','occasional','off') THEN RAISE EXCEPTION 'PREFERENCE_INVALID'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('trimmy.reminder:'||viewer::text,0));
 SELECT * INTO prior FROM trimmy.reminder_preference_receipts WHERE user_id=viewer AND mutation_id=mutation;
 IF FOUND THEN
  IF prior.base_revision<>base OR prior.frequency<>choice THEN RAISE EXCEPTION 'PREFERENCE_IDEMPOTENCY_CONFLICT'; END IF;
  RETURN trimmy.reminder_preference_get(viewer,guest)||jsonb_build_object('conflict',false);
 END IF;
 SELECT revision INTO current_revision FROM trimmy.reminder_preferences WHERE user_id=viewer;
 IF coalesce(current_revision,0)<>base THEN RETURN trimmy.reminder_preference_get(viewer,guest)||jsonb_build_object('conflict',true); END IF;
 INSERT INTO trimmy.reminder_preferences VALUES(viewer,base+1,choice)
 ON CONFLICT(user_id) DO UPDATE SET revision=excluded.revision,frequency=excluded.frequency;
 INSERT INTO trimmy.reminder_preference_receipts VALUES(viewer,mutation,base,choice);
 RETURN trimmy.reminder_preference_get(viewer,guest)||jsonb_build_object('conflict',false);
END; $$;
REVOKE ALL ON FUNCTION trimmy.reminder_preference_scope(uuid,uuid),trimmy.reminder_preference_get(uuid,uuid),trimmy.reminder_preference_put(uuid,uuid,uuid,bigint,text) FROM PUBLIC;
INSERT INTO trimmy.schema_migrations(version) VALUES('0038_reminder_preferences');
COMMIT;
