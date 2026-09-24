# Publishing more workdays

The app reads published assignments from the API. New days using the current activity types and bundled scenery do not need a mobile release.

1. Copy the content structure in `intern-v1.json` into a new version. Give each new assignment a new ID and the next consecutive ordinal. Keep the three activities: inspect evidence, decide, file a supported hand-off. Include feedback and a hint. Use a character and scenery that ship in the app.
2. Run `node tool/check-workdays.mjs path/to/new-version.json`. Existing Day 1–20 definitions are immutable: do not rewrite `0030_intern_workdays.sql` or repurpose a completed assignment ID.
3. Add a new migration inserting the new definitions (ID, ordinal, content version, full JSON payload). Register its ordered version and digest in the runtime migration tools. Test the new content through all three stages using the disposable PostgreSQL harness before deployment.
4. Back up, apply the new migration, verify the authenticated read. The new assignment appears on refresh and unlocks when its predecessor is filed. Existing completions, drafts and Trims stay intact.

Current delivery is bounded to 200 published definitions / 512 KB per journey. Add API pagination before publishing beyond that; the visual map already builds lazily without an end. New activity types or new unbundled illustration names require a mobile update. Real market trades are separate from these fictional office cases.
