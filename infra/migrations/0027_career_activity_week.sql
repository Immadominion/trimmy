BEGIN;
-- Read the same timezone-based evidence that drives streaks. A grace day is
-- never painted as an active day. Existing summary contracts stay unchanged.
CREATE FUNCTION trimmy.career_activity_week_get(selected_user uuid)
RETURNS TABLE(outcome text, server_date text, week_start text, active_dates text[])
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE zone text; today date; start_day date;
BEGIN
  IF selected_user IS NULL OR NOT EXISTS (
    SELECT 1 FROM trimmy.users u WHERE u.id = selected_user AND u.status = 'active'
  ) THEN
    RETURN QUERY SELECT 'account_missing'::text, NULL::text, NULL::text, ARRAY[]::text[]; RETURN;
  END IF;
  zone := trimmy.career_time_zone(selected_user);
  today := (statement_timestamp() AT TIME ZONE zone)::date;
  start_day := date_trunc('week', today::timestamp)::date;
  RETURN QUERY SELECT 'found'::text, today::text, start_day::text,
    ARRAY(SELECT DISTINCT (e.observed_at AT TIME ZONE zone)::date::text
      FROM trimmy.career_activity_events e
      WHERE e.user_id = selected_user
        AND e.observed_at >= (start_day::timestamp AT TIME ZONE zone)
        AND e.observed_at < ((today + 1)::timestamp AT TIME ZONE zone)
      ORDER BY 1);
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_activity_week_get(uuid) FROM PUBLIC;
INSERT INTO trimmy.schema_migrations(version) VALUES ('0027_career_activity_week');
COMMIT;
