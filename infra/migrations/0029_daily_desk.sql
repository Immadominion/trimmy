BEGIN;
CREATE TABLE trimmy.desk_story_cases (
 id text PRIMARY KEY, ordinal integer NOT NULL UNIQUE CHECK(ordinal BETWEEN 0 AND 6), payload jsonb NOT NULL
);
CREATE TABLE trimmy.daily_desk_shifts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES trimmy.users(id),
 shift_date date NOT NULL, case_id text NOT NULL REFERENCES trimmy.desk_story_cases(id),
 choice_id text NOT NULL, completed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(user_id,shift_date)
);
CREATE TRIGGER daily_shifts_append_only BEFORE UPDATE OR DELETE ON trimmy.daily_desk_shifts
 FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();
CREATE TRIGGER desk_stories_immutable BEFORE UPDATE OR DELETE ON trimmy.desk_story_cases
 FOR EACH ROW EXECUTE FUNCTION trimmy.reject_mutation();
ALTER TABLE trimmy.daily_desk_shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE trimmy.daily_desk_shifts FORCE ROW LEVEL SECURITY;
REVOKE ALL ON trimmy.daily_desk_shifts,trimmy.desk_story_cases FROM PUBLIC;
ALTER TABLE trimmy.career_activity_events DROP CONSTRAINT career_activity_events_activity_kind_check;
ALTER TABLE trimmy.career_activity_events ADD CONSTRAINT career_activity_events_activity_kind_check
 CHECK(activity_kind IN ('paper-order','trade-reason','mission','daily-shift'));
ALTER TABLE trimmy.career_trim_ledger DROP CONSTRAINT career_trim_ledger_kind_reward;
ALTER TABLE trimmy.career_trim_ledger ADD CONSTRAINT career_trim_ledger_kind_reward CHECK (
 (entry_kind IN ('paper-reason','daily-shift') AND trims=10) OR (entry_kind='mission' AND trims=20) OR (entry_kind='promotion' AND trims=100));
INSERT INTO trimmy.desk_story_cases(id,ordinal,payload) VALUES ('the-group-chat',0,$story${"id": "the-group-chat", "ordinal": 0, "title": "The group chat is loud.", "speaker": "wolf", "body": "Everyone is talking about Aster. “It’s going up,” says Wolf. The screenshot has no source. Your coffee isn’t even cold yet.", "choices": [{"id": "ask", "label": "Ask for the source", "outcome": "Wolf sends the original post. It is three months old. You put the excitement on pause and open the company update.", "takeaway": "A screenshot is a starting point, not the whole story."}, {"id": "wait", "label": "Watch for a while", "outcome": "You leave Aster on your watchlist. Later, the chat gets quiet. You kept your options open without making a trade.", "takeaway": "Waiting is a decision too."}, {"id": "follow", "label": "Follow the crowd", "outcome": "In this story, you rush in. A second message contradicts the first. Now you have a position, but no reason you trust.", "takeaway": "Before following a crowd, write down what would change your mind."}]}$story$::jsonb);
INSERT INTO trimmy.desk_story_cases(id,ordinal,payload) VALUES ('a-red-morning',1,$story${"id": "a-red-morning", "ordinal": 1, "title": "A red morning.", "speaker": "sal", "body": "Aster is down 6% in this desk story. Sal drops a note beside your screen: “Price moved. What else changed?”", "choices": [{"id": "read", "label": "Read the company update", "outcome": "Revenue is steady, but costs rose. You now have a fact to compare with your original plan.", "takeaway": "Price and business performance are different pieces of evidence."}, {"id": "plan", "label": "Open my original plan", "outcome": "Your note says you would review after the next results. You set the headline beside that plan before making a new call.", "takeaway": "A plan gives you something to revisit when emotions get loud."}, {"id": "panic", "label": "Sell because it is red", "outcome": "You react to the colour before reading the update. The story pauses there; selling may fit a plan, but red alone does not explain one.", "takeaway": "Ask what changed before choosing your response."}]}$story$::jsonb);
INSERT INTO trimmy.desk_story_cases(id,ordinal,payload) VALUES ('one-big-position',2,$story${"id": "one-big-position", "ordinal": 2, "title": "One very big position.", "speaker": "oracle", "body": "One company now makes up 70% of your fictional desk. Oracle turns the monitor towards you: “A good week made this desk very lopsided.”", "choices": [{"id": "inspect", "label": "Look at the whole desk", "outcome": "You compare how much depends on this one company. A small move there could now dominate everything else.", "takeaway": "Look at position size as well as performance."}, {"id": "trim", "label": "Consider trimming it", "outcome": "You work through a smaller position on paper before acting. You are deciding how much uncertainty to carry.", "takeaway": "Reducing concentration is a risk decision, not a prediction."}, {"id": "leave", "label": "Leave it for now", "outcome": "You keep the position, and write down why you are comfortable with the concentration. You also choose when to review it.", "takeaway": "Keeping a position still deserves a deliberate reason."}]}$story$::jsonb);
INSERT INTO trimmy.desk_story_cases(id,ordinal,payload) VALUES ('the-cheap-share',3,$story${"id": "the-cheap-share", "ordinal": 3, "title": "“That share is cheaper.”", "speaker": "shark", "body": "Shark points at two fictional companies: one share costs 5, the other 100. “Five is a bargain, right?”", "choices": [{"id": "compare", "label": "Ask how many shares exist", "outcome": "The 5-priced company has far more shares. Share price alone did not tell you which whole business was cheaper.", "takeaway": "Price per share and the value of a company are different."}, {"id": "business", "label": "Look at the businesses", "outcome": "You put earnings, debt and expectations beside the price. There is more work to do before calling either a bargain.", "takeaway": "A low share price is not an investment case."}, {"id": "cheap", "label": "Pick the lower number", "outcome": "The low price catches your eye. Sal slides over the share counts; that single number was missing most of the comparison.", "takeaway": "The smallest number is not automatically the best value."}]}$story$::jsonb);
INSERT INTO trimmy.desk_story_cases(id,ordinal,payload) VALUES ('the-friday-close',4,$story${"id": "the-friday-close", "ordinal": 4, "title": "Before you close the laptop.", "speaker": "sal", "body": "It has been a noisy week. Sal leaves one empty note on your desk. You have time for one useful thing.", "choices": [{"id": "review", "label": "Review one decision", "outcome": "You compare your reason with what happened. A good result can follow a weak process, and a careful decision can still lose.", "takeaway": "Review the reasoning as well as the result."}, {"id": "write", "label": "Write next week’s plan", "outcome": "You note one company to research and one question you still cannot answer. Monday now has a starting point.", "takeaway": "An unanswered question can be a useful next step."}, {"id": "stop", "label": "Take the evening off", "outcome": "You close the desk without forcing one more trade. The market will still be there when you return.", "takeaway": "You do not need a trade for every visit."}]}$story$::jsonb);
INSERT INTO trimmy.desk_story_cases(id,ordinal,payload) VALUES ('know-what-you-hold',5,$story${"id": "know-what-you-hold", "ordinal": 5, "title": "Same company. Different token.", "speaker": "oracle", "body": "Two tokens follow the same company. Their names look familiar. Oracle puts their issuer pages side by side.", "choices": [{"id": "rights", "label": "Read the issuer terms", "outcome": "The pages describe different rights and redemption routes. You check the token itself, not just the company name.", "takeaway": "A token linked to a share does not automatically give you every shareholder right."}, {"id": "market", "label": "Compare the markets", "outcome": "You notice different liquidity and prices. You add issuer terms to your checks before treating them as interchangeable.", "takeaway": "Company identity, token terms and trading conditions all matter."}, {"id": "logo", "label": "Trust the matching logo", "outcome": "The logos match, but the contracts and terms do not. You stop before assuming that the pictures prove equivalence.", "takeaway": "A familiar logo does not verify an asset."}]}$story$::jsonb);
INSERT INTO trimmy.desk_story_cases(id,ordinal,payload) VALUES ('the-weekend-note',6,$story${"id": "the-weekend-note", "ordinal": 6, "title": "A quieter desk.", "speaker": "sal", "body": "No rush today. Sal asks you to pick one thing you want to understand better before the next busy day.", "choices": [{"id": "company", "label": "How one company makes money", "outcome": "You make a short list: who pays, what they buy, and what it costs to deliver. You have a research plan for your next visit.", "takeaway": "Start with the business behind the symbol."}, {"id": "risk", "label": "What could go wrong", "outcome": "You name one assumption in your plan and what evidence would challenge it. Uncertainty is easier to discuss when it is specific.", "takeaway": "A risk is more useful when you can explain it."}, {"id": "journal", "label": "What I changed my mind about", "outcome": "You reread an old reason and add what you see differently now. Changing your mind can be part of a careful process.", "takeaway": "Keep a record of how your thinking changes."}]}$story$::jsonb);
CREATE OR REPLACE FUNCTION trimmy.check_career_activity_source() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, trimmy, pg_temp AS $$
DECLARE selected_user uuid; selected_kind text; selected_source uuid; selected_at timestamptz;
BEGIN
  IF TG_TABLE_NAME = 'career_activity_events' THEN
    selected_user := NEW.user_id;
    selected_kind := NEW.activity_kind;
    selected_source := NEW.source_id;
    selected_at := NEW.observed_at;
  ELSIF TG_TABLE_NAME = 'paper_orders' THEN
    selected_user := NEW.user_id; selected_kind := 'paper-order';
    selected_source := NEW.id; selected_at := NEW.committed_at;
  ELSIF TG_TABLE_NAME = 'career_trade_reasons' THEN
    selected_user := NEW.user_id; selected_kind := 'trade-reason';
    selected_source := NEW.order_id; selected_at := NEW.saved_at;
  ELSIF TG_TABLE_NAME = 'daily_desk_shifts' THEN
    selected_user := NEW.user_id; selected_kind := 'daily-shift';
    selected_source := NEW.id; selected_at := NEW.completed_at;
  ELSE
    selected_user := NEW.user_id; selected_kind := 'mission';
    selected_source := NEW.completion_id; selected_at := NEW.completed_at;
  END IF;
  IF selected_kind = 'paper-order' THEN
    IF NOT EXISTS (SELECT 1 FROM trimmy.paper_orders o
      WHERE o.user_id = selected_user AND o.id = selected_source
        AND o.committed_at = selected_at) THEN
      RAISE EXCEPTION 'Career paper activity requires its order'
        USING ERRCODE = '23514', CONSTRAINT = 'career_activity_source_pair';
    END IF;
  ELSIF selected_kind = 'trade-reason' THEN
    IF NOT EXISTS (SELECT 1 FROM trimmy.career_trade_reasons r
      WHERE r.user_id = selected_user AND r.order_id = selected_source
        AND r.saved_at = selected_at) THEN
      RAISE EXCEPTION 'Career reason activity requires its reason'
        USING ERRCODE = '23514', CONSTRAINT = 'career_activity_source_pair';
    END IF;
  ELSIF selected_kind = 'mission' THEN
    IF NOT EXISTS (SELECT 1 FROM trimmy.career_mission_completions c
      WHERE c.user_id = selected_user AND c.completion_id = selected_source
        AND c.completed_at = selected_at) THEN
      RAISE EXCEPTION 'Career mission activity requires its completion'
        USING ERRCODE = '23514', CONSTRAINT = 'career_activity_source_pair';
    END IF;
  ELSIF selected_kind = 'daily-shift' THEN
    IF NOT EXISTS (SELECT 1 FROM trimmy.daily_desk_shifts s WHERE s.user_id=selected_user AND s.id=selected_source AND s.completed_at=selected_at) THEN RAISE EXCEPTION 'Daily activity requires its shift' USING ERRCODE='23514'; END IF;
  ELSE
    RAISE EXCEPTION 'Career activity kind is invalid'
      USING ERRCODE = '23514', CONSTRAINT = 'career_activity_source_pair';
  END IF;
  IF TG_TABLE_NAME <> 'career_activity_events' AND NOT EXISTS (
    SELECT 1 FROM trimmy.career_activity_events e
    WHERE e.user_id = selected_user AND e.activity_kind = selected_kind
      AND e.source_id = selected_source AND e.observed_at = selected_at
  ) THEN
    RAISE EXCEPTION 'Career activity source requires its event'
      USING ERRCODE = '23514', CONSTRAINT = 'career_activity_source_pair';
  END IF;
  RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER daily_shift_activity_pair AFTER INSERT ON trimmy.daily_desk_shifts
 DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trimmy.check_career_activity_source();

-- A completion and its fixed reward must commit together, in both directions.
CREATE FUNCTION trimmy.check_daily_shift_reward() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
BEGIN
 IF TG_TABLE_NAME='daily_desk_shifts' THEN
  IF NOT EXISTS(SELECT 1 FROM trimmy.career_trim_ledger l WHERE l.user_id=NEW.user_id AND l.entry_kind='daily-shift' AND l.source_id=NEW.id AND l.trims=10 AND l.awarded_on=NEW.shift_date AND l.created_at=NEW.completed_at) THEN RAISE EXCEPTION 'Daily shift requires its reward' USING ERRCODE='23514'; END IF;
 ELSIF NEW.entry_kind='daily-shift' AND NOT EXISTS(SELECT 1 FROM trimmy.daily_desk_shifts s WHERE s.user_id=NEW.user_id AND s.id=NEW.source_id AND s.shift_date=NEW.awarded_on AND s.completed_at=NEW.created_at) THEN
  RAISE EXCEPTION 'Daily reward requires its shift' USING ERRCODE='23514';
 END IF;
 RETURN NULL;
END; $$;
REVOKE ALL ON FUNCTION trimmy.check_daily_shift_reward() FROM PUBLIC;
CREATE CONSTRAINT TRIGGER daily_shift_reward_pair AFTER INSERT ON trimmy.daily_desk_shifts DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trimmy.check_daily_shift_reward();
CREATE CONSTRAINT TRIGGER daily_reward_shift_pair AFTER INSERT ON trimmy.career_trim_ledger DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION trimmy.check_daily_shift_reward();

CREATE FUNCTION trimmy.daily_desk_get(viewer uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
DECLARE today date; story jsonb; done trimmy.daily_desk_shifts%ROWTYPE; history jsonb;
BEGIN
 IF viewer IS NULL OR trimmy.practice_current_user() IS DISTINCT FROM viewer OR NOT EXISTS(SELECT 1 FROM trimmy.users WHERE id=viewer AND status='active') THEN RAISE EXCEPTION 'ACCOUNT_REQUIRED'; END IF;
 today:=trimmy.career_local_date(viewer,clock_timestamp());
 SELECT payload INTO story FROM trimmy.desk_story_cases WHERE ordinal=mod(mod(today-date '2026-09-21',7)+7,7);
 SELECT * INTO done FROM trimmy.daily_desk_shifts WHERE user_id=viewer AND shift_date=today;
 SELECT coalesce(jsonb_agg(jsonb_build_object('date',s.shift_date,'caseId',s.case_id,'title',c.payload->>'title','choiceId',s.choice_id,'completedAt',s.completed_at) ORDER BY s.shift_date),'[]') INTO history
 FROM trimmy.daily_desk_shifts s JOIN trimmy.desk_story_cases c ON c.id=s.case_id WHERE s.user_id=viewer AND s.shift_date>=today-6 AND s.shift_date<=today;
 RETURN jsonb_build_object('date',today,'story',story,'completedChoice',done.choice_id,'completedAt',done.completed_at,'history',history,'trimsEarned',CASE WHEN done.id IS NULL THEN 0 ELSE 10 END);
END; $$;
REVOKE ALL ON FUNCTION trimmy.daily_desk_get(uuid) FROM PUBLIC;

CREATE FUNCTION trimmy.daily_desk_complete(viewer uuid, selected_date date, selected_case text, selected_choice text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,trimmy,pg_temp AS $$
DECLARE today date; story jsonb; existing trimmy.daily_desk_shifts%ROWTYPE; row_id uuid; at_time timestamptz; rev bigint;
BEGIN
 IF viewer IS NULL OR trimmy.practice_current_user() IS DISTINCT FROM viewer OR NOT EXISTS(SELECT 1 FROM trimmy.users WHERE id=viewer AND status='active') THEN RAISE EXCEPTION 'ACCOUNT_REQUIRED'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('trimmy.career:'||viewer::text,0));
 SELECT * INTO existing FROM trimmy.daily_desk_shifts WHERE user_id=viewer AND shift_date=selected_date;
 IF existing.id IS NOT NULL THEN
   IF (existing.case_id,existing.choice_id) IS DISTINCT FROM (selected_case,selected_choice) THEN RAISE EXCEPTION 'SHIFT_ALREADY_COMPLETE'; END IF;
   RETURN trimmy.daily_desk_get(viewer);
 END IF;
 at_time:=clock_timestamp(); today:=trimmy.career_local_date(viewer,at_time);
 IF selected_date IS DISTINCT FROM today THEN RAISE EXCEPTION 'DAY_CHANGED'; END IF;
 SELECT payload INTO story FROM trimmy.desk_story_cases WHERE id=selected_case AND ordinal=mod(mod(today-date '2026-09-21',7)+7,7);
 IF story IS NULL OR selected_choice IS NULL OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(story->'choices') c WHERE c->>'id'=selected_choice) THEN RAISE EXCEPTION 'INVALID_CHOICE'; END IF;
 rev:=trimmy.career_record_activity(viewer,today,10,at_time);
 INSERT INTO trimmy.daily_desk_shifts(user_id,shift_date,case_id,choice_id,completed_at)
 VALUES(viewer,today,selected_case,selected_choice,at_time) RETURNING id INTO row_id;
 INSERT INTO trimmy.career_trim_ledger(user_id,career_revision,entry_kind,source_id,trims,awarded_on,created_at)
 VALUES(viewer,rev,'daily-shift',row_id,10,today,at_time);
 INSERT INTO trimmy.career_activity_events(user_id,activity_kind,source_id,observed_at)
 VALUES(viewer,'daily-shift',row_id,at_time);
 RETURN trimmy.daily_desk_get(viewer);
END; $$;
REVOKE ALL ON FUNCTION trimmy.daily_desk_complete(uuid,date,text,text) FROM PUBLIC;
INSERT INTO trimmy.schema_migrations(version) VALUES ('0029_daily_desk');
COMMIT;
