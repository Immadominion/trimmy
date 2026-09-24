-- Committed role, grants and accounts for the followed-stocks integration test
-- (mirrors the deployment grants documented in migration 0012). Only the
-- exclusively owned test cluster uses these.
CREATE ROLE trimmy_following_test_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
GRANT USAGE ON SCHEMA trimmy TO trimmy_following_test_app;
GRANT EXECUTE ON FUNCTION trimmy.practice_account_exists() TO trimmy_following_test_app;
GRANT EXECUTE ON FUNCTION trimmy.followed_stock_ids_valid(jsonb) TO trimmy_following_test_app;
GRANT SELECT, INSERT, UPDATE ON trimmy.followed_stocks TO trimmy_following_test_app;
GRANT SELECT, INSERT ON trimmy.followed_stock_mutation_receipts TO trimmy_following_test_app;
-- Deliberately no privilege on the sample watchlist, so the test proves the two
-- lists are separate storage rather than two views of one.

INSERT INTO trimmy.users (id, status) VALUES
  ('00000000-0000-4000-8000-000000000041', 'active'),
  ('00000000-0000-4000-8000-000000000042', 'active');
INSERT INTO trimmy.provider_identities (user_id, provider, subject, handle_snapshot, verified_at) VALUES
  ('00000000-0000-4000-8000-000000000041', 'x', '4041', 'follower_one', '2026-09-17T09:00:00Z'),
  ('00000000-0000-4000-8000-000000000042', 'x', '4042', 'follower_two', '2026-09-17T09:00:00Z');
