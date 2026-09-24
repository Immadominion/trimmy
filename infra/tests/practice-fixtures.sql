-- Only the exclusively owned integration cluster uses these identities/roles.
CREATE ROLE trimmy_practice_test_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
CREATE ROLE trimmy_practice_test_bypass NOLOGIN BYPASSRLS;
CREATE ROLE trimmy_practice_test_unsafe LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
GRANT trimmy_practice_test_bypass TO trimmy_practice_test_unsafe;
GRANT USAGE ON SCHEMA trimmy TO trimmy_practice_test_app;
GRANT EXECUTE ON FUNCTION trimmy.practice_account_exists() TO trimmy_practice_test_app;
GRANT EXECUTE ON FUNCTION trimmy.practice_find_account(text, text), trimmy.practice_provision_account(text, text) TO trimmy_practice_test_app;
GRANT SELECT, INSERT, UPDATE ON trimmy.practice_progress TO trimmy_practice_test_app;
GRANT SELECT, INSERT ON trimmy.practice_mutation_receipts TO trimmy_practice_test_app;
CREATE ROLE trimmy_watchlist_test_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
GRANT USAGE ON SCHEMA trimmy TO trimmy_watchlist_test_app;
GRANT EXECUTE ON FUNCTION trimmy.practice_account_exists() TO trimmy_watchlist_test_app;
GRANT EXECUTE ON FUNCTION trimmy.practice_find_account(text, text), trimmy.practice_provision_account(text, text) TO trimmy_watchlist_test_app;
GRANT EXECUTE ON FUNCTION trimmy.watchlist_asset_ids_valid(jsonb) TO trimmy_watchlist_test_app, trimmy_practice_test_app;
GRANT SELECT, INSERT, UPDATE ON trimmy.watchlists TO trimmy_watchlist_test_app, trimmy_practice_test_app;
GRANT SELECT, INSERT ON trimmy.watchlist_mutation_receipts TO trimmy_watchlist_test_app, trimmy_practice_test_app;
INSERT INTO trimmy.users (id, status) VALUES
  ('00000000-0000-4000-8000-000000000001', 'active'),
  ('00000000-0000-4000-8000-000000000002', 'active'),
  ('00000000-0000-4000-8000-000000000003', 'active'),
  ('00000000-0000-4000-8000-000000000004', 'restricted'),
  ('00000000-0000-4000-8000-000000000005', 'closed');
