-- Migration-0022-only function access for the dedicated nonprivileged
-- integration-test role. The serving surface is function-only; the action
-- receipt table remains behind forced RLS with no direct runtime grant.
GRANT EXECUTE ON FUNCTION trimmy.product_launch_advance(
  uuid, uuid, text, bigint, text, uuid) TO trimmy_practice_test_app;
