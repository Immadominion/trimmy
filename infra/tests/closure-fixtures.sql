-- Committed role, grants and identities for the closure integration test
-- (mirrors the deployment grants documented in migration 0010). Only the
-- exclusively owned test cluster uses these.
CREATE ROLE trimmy_closure_test_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
GRANT USAGE ON SCHEMA trimmy TO trimmy_closure_test_app;
GRANT EXECUTE ON FUNCTION trimmy.practice_account_exists() TO trimmy_closure_test_app;
GRANT EXECUTE ON FUNCTION trimmy.practice_current_user(),
  trimmy.invitation_self_x_subject() TO trimmy_closure_test_app;
-- The closure capability itself. It can only close the account named by the
-- verified transaction scope and adds no privilege on trimmy.users.
GRANT EXECUTE ON FUNCTION trimmy.practice_close_current_account()
  TO trimmy_closure_test_app, trimmy_practice_test_app;
GRANT SELECT ON trimmy.invitations TO trimmy_closure_test_app;
GRANT INSERT (id, sender_user_id, state, funding_kind, expires_at, version)
  ON trimmy.invitations TO trimmy_closure_test_app;
GRANT UPDATE (state, recipient_provider, recipient_subject, recipient_handle_snapshot, recipient_user_id, accepted_at, version)
  ON trimmy.invitations TO trimmy_closure_test_app;

-- Two accounts used only by the closure test, kept apart from the invitation
-- fixtures so one test closing an account cannot disturb the other.
INSERT INTO trimmy.users (id, status) VALUES
  ('00000000-0000-4000-8000-000000000011', 'active'),
  ('00000000-0000-4000-8000-000000000012', 'active');
INSERT INTO trimmy.provider_identities (user_id, provider, subject, handle_snapshot, verified_at) VALUES
  ('00000000-0000-4000-8000-000000000011', 'x', '2011', 'leaver_eleven', '2026-09-16T09:00:00Z'),
  ('00000000-0000-4000-8000-000000000012', 'x', '2012', 'guest_twelve', '2026-09-16T09:00:00Z');
-- A verified sign-in mapping, so the test can prove a closed account no longer
-- resolves through the same lookup the production authenticator uses.
INSERT INTO trimmy.practice_auth_identities (app_id, subject, user_id) VALUES
  ('closure-test-app', 'did:privy:leaver', '00000000-0000-4000-8000-000000000011'),
  ('closure-test-app', 'did:privy:guest', '00000000-0000-4000-8000-000000000012');
