-- Function-only access for the dedicated nonprivileged integration-test role.
GRANT EXECUTE ON FUNCTION trimmy.product_profile_get(uuid),
  trimmy.product_profile_has_confirmed_paper_trade(uuid),
  trimmy.product_profile_put(uuid, uuid, text, bigint, text, text, text, text, text, text)
  TO trimmy_practice_test_app;
