-- Committed role, grants and identities for the private integration cluster
-- (mirrors the deployment grants documented in migration 0009). Only the
-- exclusively owned test cluster uses these.
CREATE ROLE trimmy_invitation_test_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
GRANT USAGE ON SCHEMA trimmy TO trimmy_invitation_test_app;
GRANT EXECUTE ON FUNCTION trimmy.practice_account_exists() TO trimmy_invitation_test_app;
GRANT EXECUTE ON FUNCTION trimmy.practice_current_user(),
  trimmy.invitation_self_x_subject() TO trimmy_invitation_test_app, trimmy_practice_test_app;
GRANT SELECT ON trimmy.invitations TO trimmy_invitation_test_app, trimmy_practice_test_app;
GRANT INSERT (id, sender_user_id, state, funding_kind, expires_at, version)
  ON trimmy.invitations TO trimmy_invitation_test_app, trimmy_practice_test_app;
GRANT UPDATE (state, recipient_provider, recipient_subject, recipient_handle_snapshot, recipient_user_id, accepted_at, version)
  ON trimmy.invitations TO trimmy_invitation_test_app, trimmy_practice_test_app;

-- Verified X identities for the three active accounts seeded by
-- practice-fixtures.sql. A recipient is recognised by the authoritative numeric
-- subject, never by the handle snapshot.
INSERT INTO trimmy.provider_identities (user_id, provider, subject, handle_snapshot, verified_at) VALUES
  ('00000000-0000-4000-8000-000000000001', 'x', '1001', 'sender_one', '2026-09-16T09:00:00Z'),
  ('00000000-0000-4000-8000-000000000002', 'x', '1002', 'guest_two', '2026-09-16T09:00:00Z'),
  ('00000000-0000-4000-8000-000000000003', 'x', '1003', 'other_three', '2026-09-16T09:00:00Z');
INSERT INTO trimmy.practice_auth_identities (app_id, subject, user_id) VALUES
  ('invitation-test-app', 'did:privy:sender', '00000000-0000-4000-8000-000000000001'),
  ('invitation-test-app', 'did:privy:guest', '00000000-0000-4000-8000-000000000002'),
  ('invitation-test-app', 'did:privy:outsider', '00000000-0000-4000-8000-000000000003');
