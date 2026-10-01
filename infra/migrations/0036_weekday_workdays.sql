BEGIN;
-- Workdays follow Wall Street's week. A player may start at most one new
-- assignment per desk day: a weekday in their own time zone that is not a US
-- market holiday. Work already started can always be finished, and a player's
-- very first assignment opens on any day so a weekend install still has work.
-- Before this migration the only rule was "file the previous day first", so
-- the whole intern month could be finished in one sitting.
--
-- Wrong answers are now recorded instead of rolled back: a fully correct
-- workday earns 20 Trims, one with misses earns 10. Reads no longer carry each
-- choice's feedback (which revealed the right answer before the player chose);
-- the feedback for a missed choice comes back with the miss, and the chosen
-- choice's note once the decision is accepted.
--
-- The streak now counts desk days: only activity on a desk day extends it, and a
-- missed desk day ends it. Weekends and holidays pause it.

-- NYSE full-day closures, New York dates (https://www.nyse.com/markets/hours-calendars).
-- apps/api/src/us-equity-calendar.ts carries the same dates; a test keeps them equal.
-- Dates past the last entry fall back to weekdays only.
CREATE TABLE trimmy.us_market_holidays (
 day date PRIMARY KEY,
 holiday text COLLATE "C" NOT NULL CHECK (holiday IN ('new-years-day','martin-luther-king-jr-day','washingtons-birthday',
  'good-friday','memorial-day','juneteenth','independence-day','labor-day','thanksgiving-day','christmas-day'))
);
REVOKE ALL ON trimmy.us_market_holidays FROM PUBLIC;
INSERT INTO trimmy.us_market_holidays(day, holiday) VALUES
 ('2026-01-01','new-years-day'),('2026-01-19','martin-luther-king-jr-day'),('2026-02-16','washingtons-birthday'),
 ('2026-04-03','good-friday'),('2026-05-25','memorial-day'),('2026-06-19','juneteenth'),('2026-07-03','independence-day'),
 ('2026-09-07','labor-day'),('2026-11-26','thanksgiving-day'),('2026-12-25','christmas-day'),
 ('2027-01-01','new-years-day'),('2027-01-18','martin-luther-king-jr-day'),('2027-02-15','washingtons-birthday'),
 ('2027-03-26','good-friday'),('2027-05-31','memorial-day'),('2027-06-18','juneteenth'),('2027-07-05','independence-day'),
 ('2027-09-06','labor-day'),('2027-11-25','thanksgiving-day'),('2027-12-24','christmas-day'),
 ('2028-01-17','martin-luther-king-jr-day'),('2028-02-21','washingtons-birthday'),('2028-04-14','good-friday'),
 ('2028-05-29','memorial-day'),('2028-06-19','juneteenth'),('2028-07-04','independence-day'),('2028-09-04','labor-day'),
 ('2028-11-23','thanksgiving-day'),('2028-12-25','christmas-day');

CREATE FUNCTION trimmy.career_desk_day(selected_day date) RETURNS boolean
LANGUAGE sql STABLE STRICT SET search_path = pg_catalog, trimmy, pg_temp AS $$
 SELECT extract(isodow FROM selected_day) < 6
  AND NOT EXISTS (SELECT 1 FROM trimmy.us_market_holidays h WHERE h.day = selected_day);
$$;
REVOKE ALL ON FUNCTION trimmy.career_desk_day(date) FROM PUBLIC;

-- Desk days strictly between two dates.
CREATE FUNCTION trimmy.career_desk_days_between(earlier date, later date) RETURNS integer
LANGUAGE sql STABLE STRICT SET search_path = pg_catalog, trimmy, pg_temp AS $$
 SELECT count(*)::integer FROM generate_series(1, later - earlier - 1) AS o(n) WHERE trimmy.career_desk_day(earlier + o.n);
$$;
REVOKE ALL ON FUNCTION trimmy.career_desk_days_between(date, date) FROM PUBLIC;

-- The first instant of the next desk day after observed_at, in the player's zone.
CREATE FUNCTION trimmy.career_next_desk_day_at(selected_time_zone text, observed_at timestamptz) RETURNS timestamptz
LANGUAGE plpgsql STABLE STRICT SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE candidate timestamptz := observed_at;
BEGIN
 -- At most four days in a row are closed (a Friday holiday, a weekend and a Monday holiday).
 FOR attempt IN 1..14 LOOP
  candidate := trimmy.career_next_day_at(selected_time_zone, candidate);
  IF candidate IS NULL THEN RETURN NULL; END IF;
  IF trimmy.career_desk_day((candidate AT TIME ZONE selected_time_zone)::date) THEN RETURN candidate; END IF;
 END LOOP;
 RETURN NULL;
END; $$;
REVOKE ALL ON FUNCTION trimmy.career_next_desk_day_at(text, timestamptz) FROM PUBLIC;

-- Attempts made before this migration keep a null start; they have step >= 1
-- because a failed first save used to roll its row back.
ALTER TABLE trimmy.workday_attempts
 ADD COLUMN started_at timestamptz CHECK (isfinite(started_at)),
 ADD COLUMN started_date date,
 ADD COLUMN misses integer NOT NULL DEFAULT 0 CHECK (misses BETWEEN 0 AND 1000000),
 ADD CONSTRAINT workday_attempts_start_pair CHECK ((started_at IS NULL) = (started_date IS NULL));
CREATE INDEX workday_attempts_started ON trimmy.workday_attempts(user_id, started_date);
ALTER TABLE trimmy.workday_completions ADD COLUMN trims integer NOT NULL DEFAULT 20 CHECK (trims IN (10, 20));

ALTER TABLE trimmy.career_trim_ledger DROP CONSTRAINT career_trim_ledger_kind_reward;
ALTER TABLE trimmy.career_trim_ledger ADD CONSTRAINT career_trim_ledger_kind_reward CHECK(
 (entry_kind IN ('paper-reason','daily-shift') AND trims=10) OR (entry_kind='mission' AND trims=20)
 OR (entry_kind='workday' AND trims IN (10,20)) OR (entry_kind='promotion' AND trims=100));

CREATE OR REPLACE FUNCTION trimmy.check_workday_reward() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
BEGIN
 IF TG_TABLE_NAME='workday_completions' THEN
  IF NOT EXISTS(SELECT 1 FROM trimmy.career_trim_ledger l WHERE l.user_id=NEW.user_id AND l.entry_kind='workday' AND l.source_id=NEW.id AND l.trims=NEW.trims AND l.awarded_on=NEW.completed_date AND l.created_at=NEW.completed_at) THEN RAISE EXCEPTION 'Filed work requires its reward' USING ERRCODE='23514'; END IF;
  -- Full Trims only for work filed without a miss.
  IF NOT EXISTS(SELECT 1 FROM trimmy.workday_attempts a WHERE a.user_id=NEW.user_id AND a.assignment_id=NEW.assignment_id AND a.step=3 AND (a.misses=0)=(NEW.trims=20)) THEN RAISE EXCEPTION 'Filed work requires its completed attempt' USING ERRCODE='23514'; END IF;
 ELSIF NEW.entry_kind='workday' AND NOT EXISTS(SELECT 1 FROM trimmy.workday_completions c WHERE c.user_id=NEW.user_id AND c.id=NEW.source_id AND c.trims=NEW.trims AND c.completed_date=NEW.awarded_on AND c.completed_at=NEW.created_at) THEN
  RAISE EXCEPTION 'Workday reward requires filed work' USING ERRCODE='23514';
 END IF;
 RETURN NULL;
END; $$;
REVOKE ALL ON FUNCTION trimmy.check_workday_reward() FROM PUBLIC;

-- 'open' when this assignment may be worked on today; otherwise why not.
CREATE FUNCTION trimmy.workday_gate(viewer uuid, selected_id text, today date) RETURNS text
LANGUAGE sql STABLE SET search_path = pg_catalog, trimmy, pg_temp AS $$
 SELECT CASE
  WHEN EXISTS(SELECT 1 FROM trimmy.workday_attempts a WHERE a.user_id=viewer AND a.assignment_id=selected_id AND (a.started_date IS NOT NULL OR a.step>0)) THEN 'open'
  WHEN NOT EXISTS(SELECT 1 FROM trimmy.workday_attempts a WHERE a.user_id=viewer AND (a.started_date IS NOT NULL OR a.step>0))
   AND NOT EXISTS(SELECT 1 FROM trimmy.workday_completions c WHERE c.user_id=viewer) THEN 'open'
  WHEN NOT trimmy.career_desk_day(today) THEN 'closed'
  WHEN EXISTS(SELECT 1 FROM trimmy.workday_attempts a WHERE a.user_id=viewer AND a.started_date=today) THEN 'tomorrow'
  ELSE 'open' END;
$$;
REVOKE ALL ON FUNCTION trimmy.workday_gate(uuid, text, date) FROM PUBLIC;

CREATE FUNCTION trimmy.workday_read_at(viewer uuid, observed_at timestamptz) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
DECLARE entries jsonb; done_count integer; zone text; today date; holiday_id text; state text; opens_at timestamptz; upcoming jsonb; visible integer;
DECLARE next_work trimmy.workday_definitions%ROWTYPE;
BEGIN
 IF viewer IS NULL OR observed_at IS NULL OR NOT isfinite(observed_at) OR trimmy.practice_current_user() IS DISTINCT FROM viewer OR NOT EXISTS(SELECT 1 FROM trimmy.users WHERE id=viewer AND status='active') THEN RAISE EXCEPTION 'ACCOUNT_REQUIRED'; END IF;
 zone:=trimmy.career_time_zone(viewer); today:=(observed_at AT TIME ZONE zone)::date;
 SELECT h.holiday INTO holiday_id FROM trimmy.us_market_holidays h WHERE h.day=today;
 SELECT count(*) INTO done_count FROM trimmy.workday_completions WHERE user_id=viewer;
 SELECT d.* INTO next_work FROM trimmy.workday_definitions d WHERE NOT EXISTS(SELECT 1 FROM trimmy.workday_completions c WHERE c.user_id=viewer AND c.assignment_id=d.id) ORDER BY d.ordinal LIMIT 1;
 IF next_work.id IS NULL THEN state:='done'; visible:=2147483647;
 ELSE
  state:=trimmy.workday_gate(viewer,next_work.id,today);
  IF state='open' THEN state:='available'; visible:=next_work.ordinal;
  ELSE
   -- Unopened work stays out of the list, so installed apps that only know
   -- "first unfinished" never offer it early; the teaser travels separately.
   visible:=next_work.ordinal-1; opens_at:=trimmy.career_next_desk_day_at(zone,observed_at);
   upcoming:=jsonb_build_object('id',next_work.id,'ordinal',next_work.ordinal,'title',next_work.payload->>'title','speaker',next_work.payload->>'speaker',
    'district',next_work.payload->>'district','art',next_work.payload->>'art','opensAt',opens_at);
  END IF;
 END IF;
 SELECT jsonb_agg((d.payload-'feedback'-'context') || jsonb_build_object(
  'evidence',((d.payload->'evidence')-'requiredIds') || jsonb_build_object('count',jsonb_array_length(d.payload->'evidence'->'requiredIds')),
  'decision',((d.payload->'decision')-'acceptedAnswers') || jsonb_build_object('choices',coalesce((SELECT jsonb_agg(ch-'feedback' ORDER BY o)
   FROM jsonb_array_elements(d.payload->'decision'->'choices') WITH ORDINALITY AS x(ch,o)),'[]'::jsonb)),
  'file',((d.payload->'file')-'requiredIds') || jsonb_build_object('count',jsonb_array_length(d.payload->'file'->'requiredIds')),
  'revision',coalesce(a.revision,0),'step',coalesce(a.step,0),'answers',coalesce(a.answers,'{}'),'draft',coalesce(a.draft,''),'misses',coalesce(a.misses,0),
  'decisionNote',CASE WHEN coalesce(a.step,0)>=2 THEN (SELECT ch->>'feedback' FROM jsonb_array_elements(d.payload->'decision'->'choices') ch WHERE ch->>'id'=a.answers->'1'->>'value') END,
  'completedAt',c.completed_at,'artifact',c.artifact,'trims',c.trims,'feedback',CASE WHEN c.id IS NOT NULL THEN d.payload->>'feedback' ELSE NULL END,
  'contextNote',CASE WHEN d.payload->'context' IS NOT NULL THEN
   (d.payload->'context'->'responses')->>(SELECT p.answers->'1'->>'value' FROM trimmy.workday_attempts p WHERE p.user_id=viewer AND p.assignment_id=(d.payload->'context'->>'fromId')) ELSE NULL END
 ) ORDER BY d.ordinal) INTO entries
 FROM trimmy.workday_definitions d LEFT JOIN trimmy.workday_attempts a ON a.user_id=viewer AND a.assignment_id=d.id LEFT JOIN trimmy.workday_completions c ON c.user_id=viewer AND c.assignment_id=d.id
 WHERE d.ordinal<=visible;
 RETURN jsonb_build_object('contentVersion','intern-2026-09-24.1','date',today,'completedCount',done_count,'total',(SELECT count(*) FROM trimmy.workday_definitions),
  'assignments',coalesce(entries,'[]'::jsonb),
  'schedule',jsonb_build_object('today',today,'deskOpen',trimmy.career_desk_day(today),'holiday',holiday_id,'state',state,'opensAt',opens_at),
  'upcoming',upcoming);
END; $$;
REVOKE ALL ON FUNCTION trimmy.workday_read_at(uuid, timestamptz) FROM PUBLIC;

CREATE FUNCTION trimmy.workday_save_at(viewer uuid, selected_id text, expected_revision integer, selected_step integer, selected_answer jsonb, selected_draft text, observed_at timestamptz) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
DECLARE d trimmy.workday_definitions%ROWTYPE; a trimmy.workday_attempts%ROWTYPE; required_ids jsonb; answer jsonb; local_day date; rev bigint; completion uuid; artifact_text text;
DECLARE gate text; correct boolean; miss_code text; miss_feedback text; reward integer;
BEGIN
 IF viewer IS NULL OR observed_at IS NULL OR NOT isfinite(observed_at) OR trimmy.practice_current_user() IS DISTINCT FROM viewer OR NOT EXISTS(SELECT 1 FROM trimmy.users WHERE id=viewer AND status='active') THEN RAISE EXCEPTION 'ACCOUNT_REQUIRED'; END IF;
 IF expected_revision IS NULL OR expected_revision<0 OR selected_step IS NULL THEN RAISE EXCEPTION 'INVALID_WORK'; END IF;
 IF selected_draft IS NOT NULL AND (char_length(selected_draft)>280 OR selected_draft ~ '[\x00-\x08\x0B\x0C\x0E-\x1F]') THEN RAISE EXCEPTION 'INVALID_WORK'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('trimmy.career:'||viewer::text,0));
 SELECT * INTO d FROM trimmy.workday_definitions WHERE id=selected_id;
 IF d.id IS NULL THEN RAISE EXCEPTION 'INVALID_WORK'; END IF;
 IF EXISTS(SELECT 1 FROM trimmy.workday_definitions prev WHERE prev.ordinal<d.ordinal AND NOT EXISTS(SELECT 1 FROM trimmy.workday_completions c WHERE c.user_id=viewer AND c.assignment_id=prev.id)) THEN RAISE EXCEPTION 'WORK_LOCKED'; END IF;
 local_day:=trimmy.career_local_date(viewer,observed_at);
 INSERT INTO trimmy.workday_attempts(user_id,assignment_id) VALUES(viewer,selected_id) ON CONFLICT DO NOTHING;
 SELECT * INTO a FROM trimmy.workday_attempts WHERE user_id=viewer AND assignment_id=selected_id FOR UPDATE;
 IF selected_step=-1 THEN
  IF selected_draft IS NULL OR a.step<>2 THEN RAISE EXCEPTION 'WORK_CHANGED'; END IF;
  IF a.draft=selected_draft THEN RETURN trimmy.workday_read_at(viewer,observed_at); END IF;
  IF a.revision<>expected_revision THEN RAISE EXCEPTION 'WORK_CHANGED'; END IF;
  UPDATE trimmy.workday_attempts SET draft=selected_draft,revision=revision+1,updated_at=observed_at WHERE user_id=viewer AND assignment_id=selected_id;
  RETURN trimmy.workday_read_at(viewer,observed_at);
 END IF;
 -- A new assignment starts with its first submission, right or wrong.
 IF a.started_date IS NULL AND a.step=0 THEN
  gate:=trimmy.workday_gate(viewer,selected_id,local_day);
  IF gate='closed' THEN RAISE EXCEPTION 'WORK_CLOSED'; ELSIF gate='tomorrow' THEN RAISE EXCEPTION 'WORK_TOMORROW'; END IF;
  UPDATE trimmy.workday_attempts SET started_at=observed_at,started_date=local_day WHERE user_id=viewer AND assignment_id=selected_id RETURNING * INTO a;
 END IF;
 answer:=selected_answer;
 IF jsonb_typeof(answer) IS DISTINCT FROM 'object' OR selected_step NOT BETWEEN 0 AND 2 THEN RAISE EXCEPTION 'INVALID_WORK'; END IF;
 IF selected_step IN(0,2) THEN
  required_ids:=CASE WHEN selected_step=0 THEN d.payload->'evidence'->'requiredIds' ELSE d.payload->'file'->'requiredIds' END;
  IF jsonb_typeof(answer->'ids') IS DISTINCT FROM 'array' OR (SELECT count(*) FROM jsonb_object_keys(answer))<>1 THEN RAISE EXCEPTION 'INVALID_WORK'; END IF;
  correct:=(answer->'ids' @> required_ids AND required_ids @> (answer->'ids')) AND jsonb_array_length(answer->'ids')=jsonb_array_length(required_ids);
  -- Installed apps know this code for both pinning steps; 'step' tells new ones which.
  miss_code:='CHECK_EVIDENCE';
  IF correct THEN SELECT jsonb_build_object('ids',jsonb_agg(v ORDER BY v)) INTO answer FROM jsonb_array_elements(answer->'ids') v; END IF;
 ELSE
  IF jsonb_typeof(answer->'value') IS DISTINCT FROM 'string' OR (SELECT count(*) FROM jsonb_object_keys(answer))<>1 THEN RAISE EXCEPTION 'INVALID_WORK'; END IF;
  miss_code:='CHECK_DECISION';
  IF d.payload->'decision'->>'kind'='number' THEN
   correct:=answer->>'value' ~ '^-?[0-9]{1,9}(\.[0-9]{1,6})?$'
    AND EXISTS(SELECT 1 FROM jsonb_array_elements_text(d.payload->'decision'->'acceptedAnswers') v WHERE v::numeric=(answer->>'value')::numeric);
   IF correct THEN answer:=jsonb_build_object('value',trim_scale((answer->>'value')::numeric)::text); END IF;
  ELSE
   correct:=d.payload->'decision'->'acceptedAnswers' ? (answer->>'value');
   IF NOT correct THEN
    SELECT ch->>'feedback' INTO miss_feedback FROM jsonb_array_elements(d.payload->'decision'->'choices') ch WHERE ch->>'id'=answer->>'value';
    IF miss_feedback IS NULL THEN RAISE EXCEPTION 'INVALID_WORK'; END IF;
   END IF;
  END IF;
 END IF;
 IF correct AND a.step>selected_step AND a.answers->selected_step::text=answer AND (selected_step<>2 OR selected_draft IS NULL OR selected_draft=a.draft) THEN RETURN trimmy.workday_read_at(viewer,observed_at); END IF;
 IF a.revision<>expected_revision OR a.step<>selected_step THEN RAISE EXCEPTION 'WORK_CHANGED'; END IF;
 IF NOT correct THEN
  -- Record the miss; the step and revision stay where they are.
  UPDATE trimmy.workday_attempts SET misses=misses+1,updated_at=observed_at WHERE user_id=viewer AND assignment_id=selected_id;
  RETURN trimmy.workday_read_at(viewer,observed_at) || jsonb_build_object('miss',jsonb_build_object('code',miss_code,'step',selected_step,'feedback',miss_feedback));
 END IF;
 UPDATE trimmy.workday_attempts SET step=step+1,revision=revision+1,answers=answers||jsonb_build_object(selected_step::text,answer),draft=coalesce(selected_draft,draft),updated_at=observed_at WHERE user_id=viewer AND assignment_id=selected_id;
 IF selected_step=2 THEN
  SELECT string_agg(p->>'text',E'\n' ORDER BY ord) INTO artifact_text FROM jsonb_array_elements(d.payload->'file'->'parts') WITH ORDINALITY AS parts(p,ord) WHERE required_ids ? (p->>'id');
  IF length(btrim(coalesce(selected_draft,a.draft)))>0 THEN artifact_text:=artifact_text||E'\n\n'||btrim(coalesce(selected_draft,a.draft)); END IF;
  reward:=CASE WHEN a.misses=0 THEN 20 ELSE 10 END;
  rev:=trimmy.career_record_activity(viewer,local_day,reward,observed_at);
  INSERT INTO trimmy.workday_completions(user_id,assignment_id,artifact,completed_at,completed_date,trims) VALUES(viewer,selected_id,artifact_text,observed_at,local_day,reward) RETURNING id INTO completion;
  INSERT INTO trimmy.career_trim_ledger(user_id,career_revision,entry_kind,source_id,trims,awarded_on,created_at) VALUES(viewer,rev,'workday',completion,reward,local_day,observed_at);
  INSERT INTO trimmy.career_activity_events(user_id,activity_kind,source_id,observed_at) VALUES(viewer,'workday',completion,observed_at);
 END IF;
 RETURN trimmy.workday_read_at(viewer,observed_at);
END; $$;
REVOKE ALL ON FUNCTION trimmy.workday_save_at(uuid,text,integer,integer,jsonb,text,timestamptz) FROM PUBLIC;

-- The serving role keeps exactly its two existing grants.
CREATE OR REPLACE FUNCTION trimmy.workday_read(viewer uuid) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
 SELECT trimmy.workday_read_at(viewer, clock_timestamp());
$$;
CREATE OR REPLACE FUNCTION trimmy.workday_save(viewer uuid, selected_id text, expected_revision integer, selected_step integer, selected_answer jsonb, selected_draft text DEFAULT NULL) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
 SELECT trimmy.workday_save_at(viewer, selected_id, expected_revision, selected_step, selected_answer, selected_draft, date_trunc('milliseconds', clock_timestamp()));
$$;

CREATE OR REPLACE FUNCTION trimmy.career_streak_get(
  selected_user uuid,
  selected_time_zone text,
  selected_today date
) RETURNS TABLE (streak_days integer, streak_status text, last_active_date date)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE activity_day date; later_day date; selected_last date; selected_days integer := 0;
BEGIN
  IF selected_user IS NULL OR selected_today IS NULL
      OR NOT trimmy.career_time_zone_allowed(selected_time_zone) THEN
    RETURN QUERY SELECT 0, 'not-started'::text, NULL::date; RETURN;
  END IF;
  -- Only desk days with career activity count. A desk day without activity
  -- ends the run; today is still open, so it never ends one.
  FOR activity_day IN
    SELECT DISTINCT (e.observed_at AT TIME ZONE selected_time_zone)::date
    FROM trimmy.career_activity_events e
    WHERE e.user_id = selected_user
      AND (e.observed_at AT TIME ZONE selected_time_zone)::date <= selected_today
      AND trimmy.career_desk_day((e.observed_at AT TIME ZONE selected_time_zone)::date)
    ORDER BY 1 DESC
  LOOP
    IF selected_last IS NULL THEN
      IF trimmy.career_desk_days_between(activity_day, selected_today) > 0 THEN
        RETURN QUERY SELECT 0, 'not-started'::text, NULL::date; RETURN;
      END IF;
      selected_last := activity_day; selected_days := 1;
    ELSIF trimmy.career_desk_days_between(activity_day, later_day) > 0 THEN
      EXIT;
    ELSE
      selected_days := selected_days + 1;
    END IF;
    later_day := activity_day;
  END LOOP;
  IF selected_last IS NULL THEN
    RETURN QUERY SELECT 0, 'not-started'::text, NULL::date;
  ELSIF selected_last = selected_today THEN
    RETURN QUERY SELECT selected_days, 'active'::text, selected_last;
  ELSIF trimmy.career_desk_day(selected_today) THEN
    -- Today's work is still to do.
    RETURN QUERY SELECT selected_days, 'at-risk'::text, selected_last;
  ELSE
    -- A weekend or market holiday: the streak is safe until the next desk day.
    RETURN QUERY SELECT selected_days, 'grace'::text, selected_last;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION trimmy.career_streak_get(uuid, text, date) FROM PUBLIC;

-- A serving process may verify its required schema without reading migration history.
CREATE FUNCTION trimmy.runtime_schema_has(required_version text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
 SELECT EXISTS(SELECT 1 FROM trimmy.schema_migrations WHERE version=required_version);
$$;
REVOKE ALL ON FUNCTION trimmy.runtime_schema_has(text) FROM PUBLIC;

INSERT INTO trimmy.schema_migrations(version) VALUES('0036_weekday_workdays');
COMMIT;
