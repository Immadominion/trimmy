-- Function-only access for the dedicated nonprivileged integration-test role.
GRANT EXECUTE ON FUNCTION trimmy.guest_take_creation_attempt(text),
  trimmy.guest_create_session(text, bigint, text, text, uuid, text),
  trimmy.guest_authorize(text, text), trimmy.guest_refresh_session(text),
  trimmy.guest_claim_session(text, text, text, uuid) TO trimmy_practice_test_app;
