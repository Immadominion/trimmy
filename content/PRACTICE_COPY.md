# Authored practice copy

`practice-copy.json` records the actual values exported from the fourteen mobile `ActivityDefinition` objects. The scoped manifest is complete for metadata content version `2026-09-15.1`, copy revision `1`. Copy revisions do not change the native saved-progress payload version.

The schema-2 manifest contains 14 activities, 40 choices, 12 evidence tables, 54 evidence rows and 4 branch variants. Shared evidence is counted at each activity where it appears. SHA-256 covers every validated manifest value except `sha256` itself, with object keys sorted recursively. It preserves text, Unicode, line breaks and array order; Dart formatting and JSON indentation do not affect the digest.

## Coverage

The export captures all current public authored `ActivityDefinition` fields: titles, introductions, source descriptions, draft and corrected headlines, challenge text, activity-level correction and success feedback, and Journal evidence. It also captures choice IDs, labels and details; accepted choice IDs; `ActivityEvidence` titles, ordered label/value rows and explanations; both declared `presentationOrder` and the definition's effective `presentedChoiceIds`; and each branch variant’s intro, headlines, feedback, Journal evidence, outcome title and office consequence.

The second floor's source tables read `ActivityEvidence`, so their authored figures are included. The update activity's generated full-choice details and corrected headline include the `UpdateFact.text` values used there.

This manifest does **not** freeze all lesson screens or all historical answer meaning. In particular:

- The date and sales source widgets still contain separate dates, chart data, figures, labels and large-text variants.
- The sample widget defines its ten replies, positive/negative results, respondent details and survey date separately. Its two-part composer labels, order and tailored correction text are separate too.
- The update folder, three-of-five composer, tailored correction and Ada reply contain separate copy. `UpdateFact.sourceLabel` and supporting detail are outside this export.
- `presentedChoiceIds` describes the definition getter. The sample's two-part controls and update's fact composer do not display the four or ten full-choice entries as a simple list.
- Journal rendering, first-answer selection, progress rules, calculation behavior, layouts, animation, sound and visual assets remain covered by their own code and tests.

The frozen comparison detects an exported value changing; it does not judge factual accuracy, understand the intended meaning of a rewrite, or archive previous runtime copy. Any change that alters what an existing stable answer ID means requires an explicit content/history migration decision. A new digest alone does not make that safe.

## Check without writing

From `trimmy/`:

```sh
npm run check:content
```

`npm run check:content` verifies the generated catalog and both release digests, then runs 14 Node checks: eight catalog checks and six copy checks. It is also included in `npm run check`. For a focused copy check, use `node tool/check-practice-copy.mjs` and `node --test tool/test/practice-copy.test.mjs`.

From `trimmy/apps/mobile/`:

```sh
flutter test test/practice_copy_test.dart
```

Run the Node command and the Dart test. The Node check validates strict schema, metadata parity, answer IDs, evidence bounds, derived counts, presentation order, semantic hash and registered release. The Dart test compares the frozen manifest with the **actual imported definitions**, including their computed update choices. Node alone cannot detect changes to Dart content that has not been exported.

## Release a reviewed change

1. Review the authored diff and its effects on existing saved answers. Keep stable IDs and their original meaning. Changes to catalog metadata, correct-answer identity or supported history need the corresponding catalog/progress migration work; this copy export does not perform it.
2. For a copy-only release, increment `practiceCopyRevision` in `apps/mobile/tool/export_practice_copy.dart`. Keep `practiceCatalogContentVersion` unchanged unless metadata itself is released anew.
3. From `apps/mobile/`, export a candidate and calculate its digest without changing the manifest:

   ```sh
   dart run tool/export_practice_copy.dart > /tmp/trimmy-practice-copy-candidate.json
   node ../../tool/check-practice-copy.mjs --digest < /tmp/trimmy-practice-copy-candidate.json
   ```

4. Review the candidate's semantic JSON. Append the new `contentVersion/copyRevision` and digest to the `releases` registry in `tool/check-practice-copy.mjs`. Preserve every existing registry entry. The registry is a repository review check, not a cryptographic signature or remote-content permission.
5. Explicitly regenerate from the actual definitions, then run both checks:

   ```sh
   dart run tool/export_practice_copy.dart --write
   flutter test test/practice_copy_test.dart
   npm --prefix ../.. run check:content
   ```

   `flutter test test/practice_copy_test.dart --dart-define=UPDATE_PRACTICE_COPY=true` is the equivalent explicit regeneration path. Normal tests and the default Node command never rewrite the manifest. Changed content cannot be resealed under an already registered revision without failing the release check.

Keep the exporter, manifest, digest registration and verification changes together for review. This file documents schema 2's limited coverage; expanding the manifest to other authored sources requires an explicit schema/coverage update and tests against those real sources.
