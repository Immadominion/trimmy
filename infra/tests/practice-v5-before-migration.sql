-- Seed a complete, corrected v4 history immediately before migration0006.
-- The v5 checks verify that all eight first answers and the old receipt survive.
BEGIN;
INSERT INTO trimmy.users(id, status)
VALUES ('fd000000-0000-4000-a000-000000000001', 'active');
INSERT INTO trimmy.practice_progress(user_id, revision, progress, updated_at)
VALUES (
  'fd000000-0000-4000-a000-000000000001', 1,
  '{"version":4,"active":null,"completions":{"check-the-date":{"activityId":"check-the-date","selectedChoiceId":"keep-headline","corrected":true,"completedAt":"2026-09-14T10:20:30.123456Z","importedFromLegacy":false},"sales-and-profit":{"activityId":"sales-and-profit","selectedChoiceId":"sales-mean-profit","corrected":true,"completedAt":"2026-09-14T10:20:30.123456Z","importedFromLegacy":false},"check-the-sample":{"activityId":"check-the-sample","selectedChoiceId":"all-customers","corrected":true,"completedAt":"2026-09-14T10:20:30.123456Z","importedFromLegacy":false},"prepare-the-update":{"activityId":"prepare-the-update","selectedChoiceId":"lower-profit+trial-result+current-growth","corrected":true,"completedAt":"2026-09-14T10:20:30.123456Z","importedFromLegacy":false},"compare-company-value":{"activityId":"compare-company-value","selectedChoiceId":"lower-price-means-smaller","corrected":true,"completedAt":"2026-09-14T10:20:30.123456Z","importedFromLegacy":false},"count-the-fees":{"activityId":"count-the-fees","selectedChoiceId":"ten-dollars-invested","corrected":true,"completedAt":"2026-09-14T10:20:30.123456Z","importedFromLegacy":false},"check-concentration":{"activityId":"check-concentration","selectedChoiceId":"three-equal-companies","corrected":true,"completedAt":"2026-09-14T10:20:30.123456Z","importedFromLegacy":false},"prepare-the-comparison":{"activityId":"prepare-the-comparison","selectedChoiceId":"ignore-the-fee","corrected":true,"completedAt":"2026-09-14T10:20:30.123456Z","importedFromLegacy":false}}}'::jsonb,
  '2026-09-14T17:00:00.000Z');
INSERT INTO trimmy.practice_mutation_receipts
SELECT user_id, 'fd000000-0000-4000-b000-000000000001'::uuid,
  repeat('d', 64), revision, progress, updated_at
FROM trimmy.practice_progress
WHERE user_id = 'fd000000-0000-4000-a000-000000000001';
COMMIT;
