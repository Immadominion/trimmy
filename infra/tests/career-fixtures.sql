-- Career state is intentionally function-only for the nonprivileged API test
-- role. No Career table grant belongs in this fixture.
GRANT EXECUTE ON FUNCTION trimmy.career_summary_get(uuid), trimmy.career_activity_week_get(uuid),
  trimmy.career_missions_get(uuid),
  trimmy.career_trade_reason_put(uuid, uuid, text, uuid, text),
  trimmy.career_promote(uuid, uuid, text, text),
  trimmy.career_day_context_get(uuid),
  trimmy.career_day_context_put(uuid, uuid, text, bigint, text),
  trimmy.career_reason_privacy_get(uuid),
  trimmy.career_reason_privacy_put(uuid, uuid, text, bigint, text),
  trimmy.career_trade_reason_list(uuid, text, text, text, timestamptz, uuid, integer)
  TO trimmy_practice_test_app;
