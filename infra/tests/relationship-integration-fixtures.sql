-- Current 0025 invitation and closure authority for the private integration
-- cluster. Earlier fixtures build the real upgrade state. This final fixture
-- removes their retired table grants and exposes only reviewed definer
-- functions to the nonprivileged test roles.
BEGIN;

REVOKE ALL ON TABLE trimmy.invitations, trimmy.provider_identities,
  trimmy.social_profiles, trimmy.social_invitation_create_receipts,
  trimmy.social_friendships, trimmy.social_friendship_events,
  trimmy.social_friendship_receipts, trimmy.social_blocks,
  trimmy.social_block_receipts, trimmy.social_reason_reports,
  trimmy.social_reason_moderation, trimmy.social_reason_moderation_events,
  trimmy.social_rate_windows
  FROM trimmy_invitation_test_app, trimmy_closure_test_app;
REVOKE ALL ON TABLE trimmy.invitations
  FROM trimmy_practice_test_app;

GRANT EXECUTE ON FUNCTION
  trimmy.social_invitation_create(uuid, uuid, text, timestamptz),
  trimmy.social_invitation_sender_action(uuid, uuid, bigint, text, text, text),
  trimmy.social_invitation_answer(uuid, uuid, bigint, text, text, text, timestamptz),
  trimmy.social_invitation_list(uuid, text, text, timestamptz, uuid, integer)
  TO trimmy_invitation_test_app, trimmy_closure_test_app;
GRANT EXECUTE ON FUNCTION
  trimmy.social_friend_list(uuid, timestamptz, uuid, integer),
  trimmy.social_friend_remove(uuid, uuid, uuid, text, bigint)
  TO trimmy_invitation_test_app;
GRANT EXECUTE ON FUNCTION trimmy.social_close_current_account(text)
  TO trimmy_closure_test_app;

-- 0025 creates a social profile only for an authenticated account that has
-- finished onboarding. These fixture profiles make the HTTP tests exercise
-- the same invariant instead of bypassing it with direct social-table writes.
SELECT set_config('trimmy.practice_user_id',
  '00000000-0000-4000-8000-000000000001', true);
SELECT * FROM trimmy.product_profile_put(
  '00000000-0000-4000-8000-000000000001',
  '92500000-0000-4000-8000-000000000001', repeat('1', 64), 0,
  'learn', 'basics', 'wolf', 'one-mission', 'sender_one', 'first-trade');
SELECT set_config('trimmy.practice_user_id',
  '00000000-0000-4000-8000-000000000002', true);
SELECT * FROM trimmy.product_profile_put(
  '00000000-0000-4000-8000-000000000002',
  '92500000-0000-4000-8000-000000000002', repeat('2', 64), 0,
  'practice', 'basics', 'oracle', 'one-mission', 'guest_two', 'first-trade');
SELECT set_config('trimmy.practice_user_id',
  '00000000-0000-4000-8000-000000000003', true);
SELECT * FROM trimmy.product_profile_put(
  '00000000-0000-4000-8000-000000000003',
  '92500000-0000-4000-8000-000000000003', repeat('3', 64), 0,
  'learn', 'nothing', 'shark', 'one-mission', 'other_three', 'first-trade');
SELECT set_config('trimmy.practice_user_id',
  '00000000-0000-4000-8000-000000000011', true);
SELECT * FROM trimmy.product_profile_put(
  '00000000-0000-4000-8000-000000000011',
  '92500000-0000-4000-8000-000000000011', repeat('a', 64), 0,
  'practice', 'basics', 'wolf', 'one-mission', 'leaver_eleven', 'first-trade');
SELECT set_config('trimmy.practice_user_id',
  '00000000-0000-4000-8000-000000000012', true);
SELECT * FROM trimmy.product_profile_put(
  '00000000-0000-4000-8000-000000000012',
  '92500000-0000-4000-8000-000000000012', repeat('b', 64), 0,
  'learn', 'nothing', 'oracle', 'one-mission', 'guest_twelve', 'first-trade');

COMMIT;
