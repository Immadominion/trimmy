-- Run after 0025 and deployment grants. All fixture state is rolled back.
BEGIN;

CREATE FUNCTION pg_temp.social_ok(condition boolean, label text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF condition IS NOT TRUE THEN
    RAISE EXCEPTION 'Relationship safety check failed: %', label;
  END IF;
END;
$$;

SELECT pg_temp.social_ok(NOT trimmy.social_x_subject_valid('0'),
  'X subject zero is rejected');
SELECT pg_temp.social_ok(NOT trimmy.social_x_subject_valid('123456789012345678901'),
  'X subject with 21 digits is rejected');
SELECT pg_temp.social_ok(trimmy.social_x_subject_valid('18446744073709551615'),
  'X uint64 maximum is accepted');
SELECT pg_temp.social_ok(NOT trimmy.social_x_subject_valid('18446744073709551616'),
  'X uint64 overflow is rejected');
SELECT pg_temp.social_ok(NOT trimmy.social_x_subject_valid('01'),
  'X subject leading zero is rejected');

SELECT pg_temp.social_ok((
  SELECT count(*) = 11
  FROM pg_catalog.pg_class c
  JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'trimmy' AND c.relname IN (
    'social_profiles', 'social_invitation_create_receipts',
    'social_friendships', 'social_friendship_events',
    'social_friendship_receipts', 'social_blocks', 'social_block_receipts',
    'social_reason_reports', 'social_reason_moderation',
    'social_reason_moderation_events', 'social_rate_windows')
    AND c.relrowsecurity AND c.relforcerowsecurity
), 'Every relationship table forces row security');

SELECT pg_temp.social_ok(NOT has_table_privilege(
  'trimmy_practice_runtime', 'trimmy.invitations', 'SELECT,INSERT,UPDATE,DELETE'),
  'Runtime has no direct invitation authority');
SELECT pg_temp.social_ok(NOT has_table_privilege(
  'trimmy_practice_runtime', 'trimmy.provider_identities', 'SELECT,INSERT,UPDATE,DELETE'),
  'Runtime has no direct provider identity authority');
SELECT pg_temp.social_ok(has_function_privilege(
  'trimmy_practice_runtime',
  'trimmy.social_invitation_answer(uuid,uuid,bigint,text,text,text,timestamptz)',
  'EXECUTE'), 'Runtime can call only the outer invitation answer boundary');
SELECT pg_temp.social_ok(has_function_privilege(
  'trimmy_practice_runtime', 'trimmy.social_block_get(uuid,uuid)', 'EXECUTE'),
  'Runtime can read one caller-owned block snapshot through its outer boundary');
SELECT pg_temp.social_ok(NOT has_function_privilege(
  'trimmy_practice_runtime',
  'trimmy.social_bind_verified_x_identity_internal(uuid,text,text,timestamptz)',
  'EXECUTE'), 'Runtime cannot call the verified X binding helper');
SELECT pg_temp.social_ok(NOT has_function_privilege(
  'trimmy_practice_runtime',
  'trimmy.social_account_close_cleanup_internal(uuid,text)',
  'EXECUTE'), 'Runtime cannot call account cleanup for another user');
SELECT pg_temp.social_ok(NOT has_function_privilege(
  'trimmy_practice_runtime', 'trimmy.practice_current_user()', 'EXECUTE'),
  'Runtime cannot call the internal current-principal helper');

DO $$
DECLARE
  sender uuid := '25000000-0000-4000-8000-000000000001';
  recipient uuid := '25000000-0000-4000-8000-000000000002';
  blocker uuid := '25000000-0000-4000-8000-000000000003';
  blocked_user uuid := '25000000-0000-4000-8000-000000000004';
  made record;
  reciprocal record;
  barrier_draft record;
  reverse_addressed record;
  received_open record;
  foreign_invitation record;
  duplicate_target record;
  replay record;
  changed record;
  answered record;
  removed record;
  block_result record;
  block_snapshot record;
  reverse_block record;
  closure record;
  list_row record;
  recipient_social uuid;
  blocker_social uuid;
  blocked_social uuid;
  first_friendship uuid;
  historical_invitation uuid;
  activity_at timestamptz := date_trunc('milliseconds', clock_timestamp());
BEGIN
  INSERT INTO trimmy.users(id) VALUES
    (sender), (recipient), (blocker), (blocked_user);
  INSERT INTO trimmy.practice_auth_identities(app_id, subject, user_id) VALUES
    ('relationship-test', 'did:privy:relationshipSender', sender),
    ('relationship-test', 'did:privy:relationshipRecipient', recipient),
    ('relationship-test', 'did:privy:relationshipBlocker', blocker),
    ('relationship-test', 'did:privy:relationshipBlocked', blocked_user);

  PERFORM * FROM trimmy.product_profile_put(sender,
    '25000000-0000-4000-9000-000000000001', repeat('1', 64), 0,
    'learn', 'basics', 'wolf', 'show-up', 'sender25', 'first-trade');
  PERFORM * FROM trimmy.product_profile_put(recipient,
    '25000000-0000-4000-9000-000000000002', repeat('2', 64), 0,
    'learn', 'basics', 'oracle', 'show-up', 'recipient25', 'first-trade');
  PERFORM * FROM trimmy.product_profile_put(blocker,
    '25000000-0000-4000-9000-000000000003', repeat('3', 64), 0,
    'learn', 'basics', 'shark', 'show-up', 'blocker25', 'first-trade');
  PERFORM * FROM trimmy.product_profile_put(blocked_user,
    '25000000-0000-4000-9000-000000000004', repeat('4', 64), 0,
    'learn', 'basics', 'wolf', 'show-up', 'blocked25', 'first-trade');
  -- Fixture activity uses the player calendar, independent of the host timezone.
  PERFORM trimmy.career_record_activity(sender,
    trimmy.career_local_date(sender, activity_at), 0, activity_at);
  PERFORM trimmy.career_record_activity(recipient,
    trimmy.career_local_date(recipient, activity_at), 0, activity_at);
  PERFORM trimmy.career_record_activity(blocker,
    trimmy.career_local_date(blocker, activity_at), 0, activity_at);
  PERFORM trimmy.career_record_activity(blocked_user,
    trimmy.career_local_date(blocked_user, activity_at), 0, activity_at);
  SELECT public_id INTO recipient_social FROM trimmy.social_profiles
    WHERE user_id = recipient;
  SELECT public_id INTO blocker_social FROM trimmy.social_profiles
    WHERE user_id = blocker;
  SELECT public_id INTO blocked_social FROM trimmy.social_profiles
    WHERE user_id = blocked_user;
  PERFORM pg_temp.social_ok((SELECT count(*) = 4 FROM trimmy.social_profiles),
    'Saved product accounts receive one social profile');

  PERFORM set_config('trimmy.practice_user_id', blocker::text, true);
  SELECT * INTO list_row FROM trimmy.social_friend_list(
    blocker, NULL, NULL, 21);
  PERFORM pg_temp.social_ok(list_row.outcome = 'empty'
      AND list_row.principal_social_id = (
        SELECT public_id FROM trimmy.social_profiles WHERE user_id = blocker),
    'An empty friend page returns its public cursor principal');
  SELECT * INTO list_row FROM trimmy.social_block_list(
    blocker, NULL, NULL, 21);
  PERFORM pg_temp.social_ok(list_row.outcome = 'empty'
      AND list_row.principal_social_id = (
        SELECT public_id FROM trimmy.social_profiles WHERE user_id = blocker),
    'An empty block page returns its public cursor principal');
  SELECT * INTO block_snapshot FROM trimmy.social_block_get(
    blocker, blocked_social);
  PERFORM pg_temp.social_ok(block_snapshot.outcome = 'found'
      AND block_snapshot.target_social_id = blocked_social
      AND block_snapshot.revision = 0 AND NOT block_snapshot.blocked
      AND block_snapshot.updated_at IS NULL,
    'A known active target with no directed snapshot returns revision zero');
  SELECT * INTO block_snapshot FROM trimmy.social_block_get(
    blocker, '25000000-0000-4000-8000-000000000099');
  PERFORM pg_temp.social_ok(block_snapshot.outcome = 'not_found',
    'An unknown target snapshot is unavailable after bounded lookup');

  -- A target's reverse block is never exposed as the caller's directed state.
  PERFORM set_config('trimmy.practice_user_id', blocked_user::text, true);
  SELECT * INTO reverse_block FROM trimmy.social_block_put(blocked_user,
    blocker_social, '25000000-0000-4000-a000-000000000090', repeat('a', 64),
    0, 'active');
  PERFORM set_config('trimmy.practice_user_id', blocker::text, true);
  SELECT * INTO block_snapshot FROM trimmy.social_block_get(
    blocker, blocked_social);
  PERFORM pg_temp.social_ok(block_snapshot.outcome = 'found'
      AND block_snapshot.revision = 0 AND NOT block_snapshot.blocked,
    'A target snapshot never reveals the other account block direction');
  PERFORM set_config('trimmy.practice_user_id', blocked_user::text, true);
  SELECT * INTO reverse_block FROM trimmy.social_block_put(blocked_user,
    blocker_social, '25000000-0000-4000-a000-000000000091', repeat('b', 64),
    reverse_block.revision, 'inactive');
  PERFORM pg_temp.social_ok(reverse_block.outcome = 'saved'
      AND NOT reverse_block.blocked,
    'The reverse-direction fixture is removed before invitation checks');
  PERFORM pg_sleep(0.01);
  PERFORM set_config('trimmy.practice_user_id', blocker::text, true);
  SELECT * INTO block_result FROM trimmy.social_block_put(blocker,
    '25000000-0000-4000-8000-000000000099',
    '25000000-0000-4000-a000-000000000099', repeat('9', 64), 0, 'active');
  PERFORM pg_temp.social_ok(block_result.outcome = 'not_found' AND EXISTS (
      SELECT 1 FROM trimmy.social_rate_windows w
      WHERE w.user_id = blocker AND w.action = 'block_change_10m'
        AND w.attempt_count = 1),
    'A well-formed missing block target consumes database quota');
  SELECT * INTO block_result FROM trimmy.social_block_put(blocker,
    (SELECT public_id FROM trimmy.social_profiles WHERE user_id = blocker),
    '25000000-0000-4000-a000-000000000098', repeat('8', 64), 0, 'active');
  PERFORM pg_temp.social_ok(block_result.outcome = 'invalid' AND EXISTS (
      SELECT 1 FROM trimmy.social_rate_windows w
      WHERE w.user_id = blocker AND w.action = 'block_change_10m'
        AND w.attempt_count = 2),
    'A self-block is invalid after consuming database quota');
  SELECT * INTO list_row FROM trimmy.career_trade_reason_list(
    blocker, 'friends', 'apple', repeat('1', 32), NULL, NULL, 20);
  PERFORM pg_temp.social_ok(list_row.outcome = 'empty'
      AND list_row.principal_social_id = (
        SELECT public_id FROM trimmy.social_profiles WHERE user_id = blocker),
    'An empty friends-reason page returns its public cursor principal');
  SELECT * INTO made FROM trimmy.social_invitation_create(blocker,
    '25000000-0000-4000-a000-000000000097', repeat('7', 64),
    clock_timestamp() - interval '1 minute');
  PERFORM pg_temp.social_ok(made.outcome = 'invalid' AND EXISTS (
      SELECT 1 FROM trimmy.social_rate_windows w
      WHERE w.user_id = blocker AND w.action = 'invitation_create_day'
        AND w.attempt_count = 1),
    'A semantic invitation expiry failure consumes database quota');

  PERFORM set_config('trimmy.practice_user_id', sender::text, true);
  SELECT * INTO made FROM trimmy.social_invitation_create(sender,
    '25000000-0000-4000-a000-000000000001', repeat('a', 64),
    clock_timestamp() + interval '7 days');
  PERFORM pg_temp.social_ok(made.outcome = 'saved' AND made.created
    AND made.sender_social_id IS NOT NULL AND made.party_role = 'sender',
    'Invitation draft returns its full sender projection');
  historical_invitation := made.invitation_id;
  SELECT * INTO replay FROM trimmy.social_invitation_create(sender,
    '25000000-0000-4000-a000-000000000001', repeat('a', 64), made.expires_at);
  PERFORM pg_temp.social_ok(replay.outcome = 'saved' AND NOT replay.created
    AND replay.invitation_id = made.invitation_id,
    'Invitation create replay is stable and marked as a replay');

  SELECT * INTO changed FROM trimmy.social_invitation_sender_action(
    sender, made.invitation_id, 0, 'address', '12345', 'recipient_x');
  PERFORM pg_temp.social_ok(changed.outcome = 'saved' AND changed.version = 1,
    'Sender addresses the server-resolved X subject');
  SELECT * INTO changed FROM trimmy.social_invitation_sender_action(
    sender, made.invitation_id, 1, 'offer', NULL, NULL);
  PERFORM pg_temp.social_ok(changed.outcome = 'saved' AND changed.version = 2,
    'Sender offers the addressed invitation');
  SELECT * INTO duplicate_target FROM trimmy.social_invitation_create(sender,
    '25000000-0000-4000-a000-000000000017', repeat('7', 64),
    clock_timestamp() + interval '7 days');
  SELECT * INTO changed FROM trimmy.social_invitation_sender_action(
    sender, duplicate_target.invitation_id, 0, 'address', '12345', 'recipient_x');
  PERFORM pg_temp.social_ok(changed.outcome = 'revision_conflict'
    AND changed.state = 'draft',
    'A duplicate live target returns a bounded conflict before the unique index');

  -- A reciprocal offer can exist before either invitation is accepted. Once
  -- the first answer creates the pair, answering the other must be a bounded
  -- conflict with no identity or invitation mutation.
  INSERT INTO trimmy.provider_identities(
    user_id, provider, subject, handle_snapshot, verified_at)
  VALUES (sender, 'x', '54321', 'sender_x', clock_timestamp());
  PERFORM set_config('trimmy.practice_user_id', recipient::text, true);
  SELECT * INTO reciprocal FROM trimmy.social_invitation_create(recipient,
    '25000000-0000-4000-a000-000000000007', repeat('7', 64),
    clock_timestamp() + interval '7 days');
  PERFORM * FROM trimmy.social_invitation_sender_action(
    recipient, reciprocal.invitation_id, 0, 'address', '54321', 'sender_x');
  PERFORM * FROM trimmy.social_invitation_sender_action(
    recipient, reciprocal.invitation_id, 1, 'offer', NULL, NULL);

  SELECT * INTO list_row FROM trimmy.social_invitation_list(
    recipient, NULL, 'open', NULL, NULL, 21);
  PERFORM pg_temp.social_ok(list_row.principal_social_id = recipient_social
    AND list_row.incoming_status = 'x_link_required'
    AND list_row.invitation_id = reciprocal.invitation_id
    AND list_row.party_role = 'sender',
    'Missing current X proof returns metadata and only the caller outgoing offer');
  SELECT * INTO answered FROM trimmy.social_invitation_answer(
    recipient, made.invitation_id, 2, 'accept', '12345', 'recipient_x',
    clock_timestamp());
  first_friendship := answered.friendship_id;
  PERFORM pg_temp.social_ok(answered.outcome = 'accepted'
    AND answered.party_role = 'recipient' AND first_friendship IS NOT NULL,
    'Fresh X proof atomically accepts and creates a friendship');
  PERFORM pg_temp.social_ok(EXISTS (
    SELECT 1 FROM trimmy.provider_identities p
    WHERE p.user_id = recipient AND p.provider = 'x' AND p.subject = '12345'),
    'Acceptance durably binds the freshly proved X subject');
  SELECT * INTO replay FROM trimmy.social_invitation_answer(
    recipient, made.invitation_id, 2, 'accept', '12345', 'recipient_x',
    clock_timestamp());
  PERFORM pg_temp.social_ok(replay.outcome = 'accepted'
    AND (SELECT count(*) FROM trimmy.social_friendship_events
      WHERE friendship_id = (SELECT id FROM trimmy.social_friendships
        WHERE public_id = first_friendship)) = 1,
    'Exact accept replay creates no second transition event');

  PERFORM set_config('trimmy.practice_user_id', sender::text, true);
  SELECT * INTO replay FROM trimmy.social_invitation_answer(
    sender, reciprocal.invitation_id, 2, 'accept', '54321', 'sender_x',
    clock_timestamp());
  PERFORM pg_temp.social_ok(replay.outcome = 'already_friends'
    AND (SELECT state = 'offered' AND recipient_user_id IS NULL
      FROM trimmy.invitations WHERE id = reciprocal.invitation_id),
    'A second offer cannot mutate identity or invitation state for an active pair');

  SELECT * INTO removed FROM trimmy.social_friend_remove(sender,
    first_friendship, '25000000-0000-4000-a000-000000000002',
    repeat('b', 64), 1);
  PERFORM pg_temp.social_ok(removed.outcome = 'removed'
    AND removed.applied_revision = 2,
    'Either friend can remove the active friendship');
  SELECT * INTO replay FROM trimmy.social_friend_remove(sender,
    first_friendship, '25000000-0000-4000-a000-000000000002',
    repeat('b', 64), 1);
  PERFORM pg_temp.social_ok(replay.outcome = 'removed'
    AND replay.applied_revision = 2,
    'Friend removal replay returns the immutable receipt');
  PERFORM pg_temp.social_ok((SELECT state = 'accepted' FROM trimmy.invitations
      WHERE id = made.invitation_id),
    'Removing a friendship preserves accepted invitation history');
  SELECT * INTO received_open FROM trimmy.social_invitation_create(sender,
    '25000000-0000-4000-a000-000000000015', repeat('5', 64),
    clock_timestamp() + interval '7 days');
  PERFORM * FROM trimmy.social_invitation_sender_action(
    sender, received_open.invitation_id, 0, 'address', '12345', 'recipient_x');
  PERFORM * FROM trimmy.social_invitation_sender_action(
    sender, received_open.invitation_id, 1, 'offer', NULL, NULL);
  PERFORM set_config('trimmy.practice_user_id', recipient::text, true);
  SELECT * INTO replay FROM trimmy.social_invitation_answer(
    recipient, historical_invitation, 2, 'accept', '12345', 'recipient_x',
    clock_timestamp());
  PERFORM pg_temp.social_ok(replay.outcome = 'accepted'
    AND replay.friendship_revision = 1,
    'Accept replay returns the original friendship event after later removal');
  PERFORM set_config('trimmy.practice_user_id', sender::text, true);
  SELECT * INTO replay FROM trimmy.social_invitation_answer(
    sender, reciprocal.invitation_id, 2, 'accept', '54321', 'sender_x',
    clock_timestamp());
  PERFORM pg_temp.social_ok(replay.outcome = 'accepted'
    AND replay.friendship_revision = 3,
    'The still-open reciprocal invitation can reactivate a removed friendship');

  PERFORM set_config('trimmy.practice_user_id', blocker::text, true);
  SELECT * INTO made FROM trimmy.social_invitation_create(blocker,
    '25000000-0000-4000-a000-000000000003', repeat('c', 64),
    clock_timestamp() + interval '7 days');
  PERFORM * FROM trimmy.social_invitation_sender_action(
    blocker, made.invitation_id, 0, 'address', '67890', 'blocked_x');
  PERFORM * FROM trimmy.social_invitation_sender_action(
    blocker, made.invitation_id, 1, 'offer', NULL, NULL);
  PERFORM set_config('trimmy.practice_user_id', blocked_user::text, true);
  SELECT * INTO reverse_addressed FROM trimmy.social_invitation_create(blocked_user,
    '25000000-0000-4000-a000-000000000016', repeat('6', 64),
    clock_timestamp() + interval '7 days');
  PERFORM * FROM trimmy.social_invitation_sender_action(
    blocked_user, reverse_addressed.invitation_id, 0, 'address', '77777', 'blocker_x');
  PERFORM set_config('trimmy.practice_user_id', blocker::text, true);
  SELECT * INTO block_result FROM trimmy.social_block_put(blocker,
    blocked_social, '25000000-0000-4000-a000-000000000004', repeat('d', 64),
    0, 'active');
  PERFORM pg_temp.social_ok(block_result.outcome = 'saved'
    AND block_result.blocked
    AND (SELECT state = 'offered' FROM trimmy.invitations
      WHERE id = made.invitation_id),
    'An unresolved X offer is not guessed during a block mutation');
  PERFORM set_config('trimmy.practice_user_id', blocked_user::text, true);
  SELECT * INTO list_row FROM trimmy.social_invitation_list(
    blocked_user, '67890', 'open', NULL, NULL, 21);
  PERFORM pg_temp.social_ok(list_row.outcome = 'found'
    AND list_row.invitation_id = reverse_addressed.invitation_id
    AND list_row.party_role = 'sender'
    AND (SELECT state = 'canceled' FROM trimmy.invitations
      WHERE id = made.invitation_id),
    'Fresh list proof cancels and hides an unresolved offer under an active block');

  PERFORM set_config('trimmy.practice_user_id', blocker::text, true);
  SELECT * INTO block_result FROM trimmy.social_block_put(blocker,
    blocked_social, '25000000-0000-4000-a000-000000000005', repeat('e', 64),
    1, 'inactive');
  PERFORM pg_temp.social_ok(block_result.outcome = 'saved'
    AND NOT block_result.blocked,
    'The first block can be removed without restoring its canceled offer');
  SELECT * INTO block_snapshot FROM trimmy.social_block_get(
    blocker, blocked_social);
  PERFORM pg_temp.social_ok(block_snapshot.outcome = 'found'
      AND block_snapshot.revision = block_result.revision
      AND NOT block_snapshot.blocked AND block_snapshot.updated_at IS NOT NULL,
    'A new device can read the exact inactive revision before re-blocking');

  SELECT * INTO barrier_draft FROM trimmy.social_invitation_create(blocker,
    '25000000-0000-4000-a000-000000000008', repeat('8', 64),
    clock_timestamp() + interval '7 days');
  SELECT * INTO made FROM trimmy.social_invitation_create(blocker,
    '25000000-0000-4000-a000-000000000009', repeat('9', 64),
    clock_timestamp() + interval '7 days');
  PERFORM * FROM trimmy.social_invitation_sender_action(
    blocker, made.invitation_id, 0, 'address', '67890', 'blocked_x');
  PERFORM * FROM trimmy.social_invitation_sender_action(
    blocker, made.invitation_id, 1, 'offer', NULL, NULL);
  SELECT * INTO block_result FROM trimmy.social_block_put(blocker,
    blocked_social, '25000000-0000-4000-a000-000000000010', repeat('0', 64),
    block_snapshot.revision, 'active');
  SELECT * INTO block_result FROM trimmy.social_block_put(blocker,
    blocked_social, '25000000-0000-4000-a000-000000000011', repeat('1', 64),
    3, 'inactive');
  INSERT INTO trimmy.provider_identities(
    user_id, provider, subject, handle_snapshot, verified_at)
  VALUES (blocked_user, 'x', '67890', 'blocked_x', clock_timestamp());

  SELECT * INTO changed FROM trimmy.social_invitation_sender_action(
    blocker, barrier_draft.invitation_id, 0, 'address', '67890', 'blocked_x');
  PERFORM pg_temp.social_ok(changed.outcome = 'blocked' AND changed.state = 'canceled',
    'Addressing cancels a pre-block draft once its durable target is resolvable');
  PERFORM set_config('trimmy.practice_user_id', blocked_user::text, true);
  SELECT * INTO list_row FROM trimmy.social_invitation_list(
    blocked_user, '67890', 'open', NULL, NULL, 21);
  PERFORM pg_temp.social_ok(list_row.outcome = 'found'
    AND list_row.invitation_id = reverse_addressed.invitation_id
    AND list_row.party_role = 'sender'
    AND (SELECT state = 'canceled' FROM trimmy.invitations
      WHERE id = made.invitation_id),
    'List proof enforces a removed-block barrier for an unresolved old offer');

  PERFORM set_config('trimmy.practice_user_id', recipient::text, true);
  SELECT * INTO list_row FROM trimmy.social_invitation_list(
    recipient, '99999', 'open', NULL, NULL, 21);
  PERFORM pg_temp.social_ok(list_row.outcome = 'identity_conflict',
    'List proof cannot replace the caller durable X binding');
  PERFORM set_config('trimmy.practice_user_id', blocker::text, true);
  SELECT * INTO list_row FROM trimmy.social_invitation_list(
    blocker, '67890', 'open', NULL, NULL, 21);
  PERFORM pg_temp.social_ok(list_row.outcome = 'identity_conflict',
    'List proof cannot claim an X subject durably bound to another account');
  INSERT INTO trimmy.provider_identities(
    user_id, provider, subject, handle_snapshot, verified_at)
  VALUES (blocker, 'x', '77777', 'blocker_x', clock_timestamp());
  PERFORM set_config('trimmy.practice_user_id', blocked_user::text, true);
  SELECT * INTO changed FROM trimmy.social_invitation_sender_action(
    blocked_user, reverse_addressed.invitation_id, 1, 'offer', NULL, NULL);
  PERFORM pg_temp.social_ok(changed.outcome = 'blocked' AND changed.state = 'canceled',
    'Offering cancels a pre-block addressed invitation after target resolution');

  -- A new invitation created strictly after unblock may establish the pair.
  PERFORM set_config('trimmy.practice_user_id', blocker::text, true);
  PERFORM pg_sleep(0.01);
  SELECT * INTO made FROM trimmy.social_invitation_create(blocker,
    '25000000-0000-4000-a000-000000000012', repeat('2', 64),
    clock_timestamp() + interval '7 days');
  PERFORM pg_temp.social_ok(made.outcome = 'saved',
    'Post-unblock invitation draft is created: ' || coalesce(made.outcome, 'null'));
  SELECT * INTO changed FROM trimmy.social_invitation_sender_action(
    blocker, made.invitation_id, 0, 'address', '67890', 'blocked_x');
  PERFORM pg_temp.social_ok(changed.outcome = 'saved',
    'Post-unblock invitation is addressed: ' || coalesce(changed.outcome, 'null'));
  SELECT * INTO changed FROM trimmy.social_invitation_sender_action(
    blocker, made.invitation_id, 1, 'offer', NULL, NULL);
  PERFORM pg_temp.social_ok(changed.outcome = 'saved',
    'Post-unblock invitation is offered: ' || coalesce(changed.outcome, 'null'));
  PERFORM set_config('trimmy.practice_user_id', blocked_user::text, true);
  SELECT * INTO answered FROM trimmy.social_invitation_answer(
    blocked_user, made.invitation_id, 2, 'accept', '67890', 'blocked_x',
    clock_timestamp());
  PERFORM pg_temp.social_ok(answered.outcome = 'accepted',
    'An invitation created after unblock establishes an active friendship: '
      || coalesce(answered.outcome, 'null'));
  PERFORM set_config('trimmy.practice_user_id', blocker::text, true);
  SELECT * INTO block_result FROM trimmy.social_block_put(blocker,
    blocked_social, '25000000-0000-4000-a000-000000000013', repeat('3', 64),
    4, 'active');
  PERFORM pg_temp.social_ok(block_result.outcome = 'saved'
    AND block_result.blocked AND NOT EXISTS (
      SELECT 1 FROM trimmy.social_friendships f
      WHERE f.public_id = answered.friendship_id AND f.state = 'active'),
    'Blocking removes an active friendship');
  SELECT * INTO block_result FROM trimmy.social_block_put(blocker,
    blocked_social, '25000000-0000-4000-a000-000000000014', repeat('4', 64),
    5, 'inactive');
  PERFORM pg_temp.social_ok(block_result.outcome = 'saved'
    AND NOT block_result.blocked AND NOT EXISTS (
      SELECT 1 FROM trimmy.social_friendships f
      WHERE f.public_id = answered.friendship_id AND f.state = 'active'),
    'Unblocking restores no friendship');

  SELECT * INTO block_result FROM trimmy.social_block_put(blocker,
    blocked_social, '25000000-0000-4000-a000-000000000015', repeat('5', 64),
    block_result.revision, 'active');
  PERFORM pg_temp.social_ok(block_result.outcome = 'saved' AND block_result.blocked,
    'A second block is active before target closure');
  PERFORM set_config('trimmy.practice_user_id', blocked_user::text, true);
  SELECT * INTO closure FROM trimmy.social_close_current_account('67890');
  PERFORM pg_temp.social_ok(closure.outcome = 'saved' AND closure.closed,
    'Blocked target closes its account');
  PERFORM set_config('trimmy.practice_user_id', blocker::text, true);
  SELECT * INTO block_snapshot FROM trimmy.social_block_get(
    blocker, blocked_social);
  PERFORM pg_temp.social_ok(block_snapshot.outcome = 'found'
      AND block_snapshot.revision = block_result.revision
      AND block_snapshot.blocked AND block_snapshot.updated_at IS NOT NULL,
    'A caller can read its directed block after the target closes');
  SELECT * INTO block_result FROM trimmy.social_block_put(blocker,
    blocked_social, '25000000-0000-4000-a000-000000000016', repeat('6', 64),
    block_snapshot.revision, 'inactive');
  PERFORM pg_temp.social_ok(block_result.outcome = 'saved' AND NOT block_result.blocked,
    'A caller can unblock a closed target');

  -- A fresh closure projection may conflict with another account's durable X
  -- binding. It must never expand cleanup authority across that boundary.
  SELECT * INTO foreign_invitation FROM trimmy.social_invitation_create(blocker,
    '25000000-0000-4000-a000-000000000018', repeat('8', 64),
    clock_timestamp() + interval '7 days');
  PERFORM * FROM trimmy.social_invitation_sender_action(
    blocker, foreign_invitation.invitation_id, 0, 'address', '54321', 'sender_x');
  PERFORM * FROM trimmy.social_invitation_sender_action(
    blocker, foreign_invitation.invitation_id, 1, 'offer', NULL, NULL);

  PERFORM set_config('trimmy.practice_user_id', recipient::text, true);
  SELECT * INTO made FROM trimmy.social_invitation_create(recipient,
    '25000000-0000-4000-a000-000000000006', repeat('f', 64),
    clock_timestamp() + interval '7 days');
  SELECT * INTO closure FROM trimmy.social_close_current_account('54321');
  PERFORM pg_temp.social_ok(closure.outcome = 'saved' AND closure.closed
    AND closure.canceled_invitations = 2
    AND closure.removed_friendships = 1
    AND (SELECT state = 'canceled' FROM trimmy.invitations
      WHERE id = made.invitation_id)
    AND (SELECT state = 'canceled' FROM trimmy.invitations
      WHERE id = received_open.invitation_id),
    'Account closure atomically returns and applies social cleanup counts');
  PERFORM pg_temp.social_ok((SELECT state = 'offered' FROM trimmy.invitations
      WHERE id = foreign_invitation.invitation_id),
    'Closure ignores a fresh X subject durably owned by another account');
  PERFORM pg_temp.social_ok((SELECT state = 'accepted' FROM trimmy.invitations
      WHERE id = historical_invitation),
    'Closure preserves historical accepted invitation state');
END;
$$;

SELECT pg_temp.social_ok((SELECT count(*) = 0
  FROM trimmy.social_reason_reports),
  'Relationship fixture creates no synthetic reports');

ROLLBACK;
