-- Committed role, grants and accounts for the durable wallet-challenge
-- integration test (mirrors the deployment grants documented in migration
-- 0011). Only the exclusively owned test cluster uses these.
CREATE ROLE trimmy_wallet_challenge_test_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
GRANT USAGE ON SCHEMA trimmy TO trimmy_wallet_challenge_test_app;
GRANT EXECUTE ON FUNCTION trimmy.practice_account_exists() TO trimmy_wallet_challenge_test_app;
-- Exactly what migration 0011 documents: read, issue, and mark as used. No
-- DELETE, and no updatable column other than consumed_at.
GRANT SELECT, INSERT ON trimmy.wallet_possession_challenges
  TO trimmy_wallet_challenge_test_app;
GRANT UPDATE (consumed_at) ON trimmy.wallet_possession_challenges
  TO trimmy_wallet_challenge_test_app;

-- Two accounts, so the test can prove one account cannot take another's
-- challenge, plus one closed account that may not be issued one at all.
INSERT INTO trimmy.users (id, status) VALUES
  ('00000000-0000-4000-8000-000000000031', 'active'),
  ('00000000-0000-4000-8000-000000000032', 'active'),
  ('00000000-0000-4000-8000-000000000033', 'closed');
INSERT INTO trimmy.provider_identities (user_id, provider, subject, handle_snapshot, verified_at) VALUES
  ('00000000-0000-4000-8000-000000000031', 'x', '3031', 'holder_one', '2026-09-17T09:00:00Z'),
  ('00000000-0000-4000-8000-000000000032', 'x', '3032', 'holder_two', '2026-09-17T09:00:00Z');
