import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {describe, it} from 'node:test';
import {
  assertPracticeHistoryPreserved,
  canonicalPracticeProgress,
  parsePracticeProgress,
  practiceCatalogActivityIds as ids,
  practiceCatalogById as catalog,
} from '../src/index.js';
import type {PracticeActivityId, PracticeCompletion, PracticeProgress} from '../src/index.js';

const at = '2026-09-14T10:20:30.123456Z';
const invalid = {code: 'INVALID_PRACTICE_PROGRESS'};

function completedThrough(count: number): Record<string, PracticeCompletion> {
  return Object.fromEntries(ids.slice(0, count).map(id => [id, {
    activityId: id,
    selectedChoiceId: catalog[id].correctChoiceId,
    corrected: false,
    completedAt: at,
    importedFromLegacy: false,
  } satisfies PracticeCompletion]));
}

function completion(id: PracticeActivityId, selectedChoiceId: string = catalog[id].correctChoiceId,
  corrected = false): PracticeCompletion {
  return {activityId: id, selectedChoiceId, corrected, completedAt: at, importedFromLegacy: false};
}

describe('practice payload v5 persistent team decision', () => {
  for (const branch of ['share-qualified-sales', 'request-missing-costs']) {
    it(`accepts the defensible ${branch} branch without correction and gates later figures on its saved completion`, () => {
      const firstEight = completedThrough(8);
      const selected = {activityId: 'review-team-update', stage: 2, selectedChoiceId: branch,
        corrected: false, answerParts: {}};
      const draft = {version: 5, active: selected, completions: firstEight};
      assert.equal(parsePracticeProgress(draft).active?.selectedChoiceId, branch);
      assert.throws(() => parsePracticeProgress({...draft, version: 4}), invalid);
      assert.throws(() => parsePracticeProgress({...draft, active: {...selected, stage: 3, corrected: true}}), invalid);
      assert.throws(() => parsePracticeProgress({...draft, active: {
        activityId: 'read-returned-costs', stage: 0, selectedChoiceId: null, corrected: false, answerParts: {},
      }}), invalid);

      const saved = parsePracticeProgress({...draft, active: {...selected, stage: 4}, completions: {
        ...firstEight, 'review-team-update': completion('review-team-update', branch),
      }});
      assert.equal(saved.completions['review-team-update']?.selectedChoiceId, branch);
      assert.equal(saved.completions['review-team-update']?.corrected, false);
      assert.equal(parsePracticeProgress({...saved, active: {
        activityId: 'read-returned-costs', stage: 0, selectedChoiceId: null, corrected: false, answerParts: {},
      }}).active?.activityId, 'read-returned-costs');
    });
  }

  it('keeps the first branch immutable through returned figures, branch follow-up and opposite replay', () => {
    const firstEight = completedThrough(8);
    const firstBranch = parsePracticeProgress({version: 5, active: null, completions: {
      ...firstEight, 'review-team-update': completion('review-team-update', 'request-missing-costs'),
    }});
    const returned = parsePracticeProgress({...firstBranch, completions: {
      ...firstBranch.completions, 'read-returned-costs': completion('read-returned-costs'),
    }});
    const followedUp = parsePracticeProgress({...returned, completions: {
      ...returned.completions, 'finish-team-update': completion('finish-team-update'),
    }});
    assertPracticeHistoryPreserved(firstBranch, followedUp);
    assert.equal(followedUp.completions['review-team-update']?.selectedChoiceId, 'request-missing-costs');

    const replay = parsePracticeProgress({...followedUp, active: {
      activityId: 'review-team-update', stage: 4, selectedChoiceId: 'share-qualified-sales',
      corrected: false, answerParts: {},
    }});
    assertPracticeHistoryPreserved(followedUp, replay);
    assert.equal(replay.completions['review-team-update']?.selectedChoiceId, 'request-missing-costs');
    const rewritten = parsePracticeProgress({...followedUp, completions: {
      ...followedUp.completions,
      'review-team-update': completion('review-team-update', 'share-qualified-sales'),
    }});
    assert.throws(() => assertPracticeHistoryPreserved(followedUp, rewritten),
      {code: 'PRACTICE_HISTORY_CONFLICT'});
  });

  it('round-trips every Dart v6 transition while retaining exact v3, v4 and v5 fixtures', () => {
    for (const version of [3, 4, 5, 6] as const) {
      const contract = JSON.parse(readFileSync(new URL(
        `../../../contracts/practice-progress-v${version}.json`, import.meta.url), 'utf8')) as {
          schemaVersion: number;
          cases: {name: string; progress: unknown}[];
        };
      assert.equal(contract.schemaVersion, 1);
      for (const entry of contract.cases) {
        const parsed = parsePracticeProgress(entry.progress);
        assert.equal(parsed.version, version, entry.name);
        assert.deepEqual(JSON.parse(canonicalPracticeProgress(parsed)), entry.progress, entry.name);
      }
    }
  });

  it('exports the exact version union for repository callers', () => {
    const versions: PracticeProgress['version'][] = [3, 4, 5, 6];
    assert.deepEqual(versions.map(version => parsePracticeProgress({
      version, active: null, completions: {},
    }).version), versions);
  });
});
