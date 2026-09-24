-- Seed an actual v3 snapshot/receipt before migration0005. The later HTTP test
-- retries this exact historical command after upgrading to v4 and after restart.
BEGIN;
INSERT INTO trimmy.users(id, status) VALUES ('fc000000-0000-4000-a000-000000000001', 'active');
INSERT INTO trimmy.practice_progress(user_id, revision, progress, updated_at) VALUES (
  'fc000000-0000-4000-a000-000000000001', 1,
  '{"active":null,"completions":{"check-the-date":{"activityId":"check-the-date","completedAt":"2026-09-14T10:20:30.123456Z","corrected":true,"importedFromLegacy":false,"selectedChoiceId":"keep-headline"}},"version":3}'::jsonb, '2026-09-14T12:00:00.000Z');
INSERT INTO trimmy.practice_mutation_receipts(user_id, mutation_id, request_hash, revision, progress, updated_at)
SELECT user_id, 'fc000000-0000-4000-b000-000000000001'::uuid,
  'cfe99b9b6d056d41dde7d1467c27bd404e7d839fbd8f3ab63a0a6a8efeaa131d', revision, progress, updated_at
FROM trimmy.practice_progress WHERE user_id = 'fc000000-0000-4000-a000-000000000001';
COMMIT;
