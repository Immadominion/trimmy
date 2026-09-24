import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';
import {
  assertPracticeHistoryPreserved, canonicalPracticeProgress, parsePracticeProgress,
} from '../src/practice-progress.js';
import { practiceCatalogActivityIds as ids, practiceCatalogById as catalog } from '../src/practice-catalog.generated.js';
import type { PracticeActivityId, PracticeCompletion } from '../src/practice-progress.js';

function completedThrough(count: number) {
  return Object.fromEntries(ids.slice(0, count).map(id => [id, {
    activityId: id, selectedChoiceId: catalog[id].correctChoiceId, corrected: false,
    completedAt: '2026-09-14T10:20:30.123456Z', importedFromLegacy: false,
  } satisfies PracticeCompletion]));
}
const invalid = {code: 'INVALID_PRACTICE_PROGRESS'};

describe('practice version 4 catalog and historical compatibility', () => {
  it('preserves historical version 3 canonically and requires explicit version 4 for new content', () => {
    const v3 = parsePracticeProgress({version: 3, active: null, completions: completedThrough(4)});
    const v4 = parsePracticeProgress({...v3, version: 4});
    assert.equal(v3.version, 3);
    assert.equal(v4.version, 4);
    assert.notEqual(canonicalPracticeProgress(v3), canonicalPracticeProgress(v4));
    assertPracticeHistoryPreserved(v3, v4);
    assert.deepEqual(v3.completions, v4.completions);
    for (const version of [0, 1, 2, 7, '4', null]) {
      assert.throws(() => parsePracticeProgress({...v4, version}), invalid);
    }
  });

  for (const [offset, id] of ids.slice(4, 8).entries()) {
    it(`validates all ${id} choices and sequential unlocks in v4 only`, () => {
      const completions = completedThrough(offset + 4);
      const active = {activityId: id, stage: 2, selectedChoiceId: null as string | null, corrected: false, answerParts: {}};
      const draft = {version: 4, active, completions};
      assert.equal(parsePracticeProgress(draft).active?.activityId, id);
      assert.throws(() => parsePracticeProgress({...draft, version: 3}), invalid);
      assert.throws(() => parsePracticeProgress({...draft, completions: completedThrough(offset + 3)}), invalid);
      assert.throws(() => parsePracticeProgress({...draft, active: {...active, answerParts: {amount: 'all'}}}), invalid);
      for (const choice of catalog[id].choiceIds) {
        const corrected = choice !== catalog[id].correctChoiceId;
        const selected = {...active, selectedChoiceId: choice};
        assert.equal(parsePracticeProgress({...draft, active: selected}).active?.selectedChoiceId, choice);
        const correction = {...selected, stage: 3, corrected: true};
        if (corrected) assert.equal(parsePracticeProgress({...draft, active: correction}).active?.stage, 3);
        else assert.throws(() => parsePracticeProgress({...draft, active: correction}), invalid);
        const completion = {...completedThrough(offset + 5)[id]!, selectedChoiceId: choice, corrected};
        const done = {...draft, active: {...selected, stage: 4, corrected}, completions: {...completions, [id]: completion}};
        assert.deepEqual(parsePracticeProgress(done).completions[id], completion);
        assert.throws(() => parsePracticeProgress({...done, version: 3}), invalid);
        assert.throws(() => parsePracticeProgress({...done, active: {...done.active, corrected: !corrected}}), invalid);
      }
    });
  }

  it('keeps all eight first notes immutable while allowing an independent replay decision', () => {
    const before = parsePracticeProgress({version: 4, active: null, completions: completedThrough(8)});
    const id: PracticeActivityId = 'prepare-the-comparison';
    const replay = parsePracticeProgress({...before, active: {
      activityId: id, stage: 3, selectedChoiceId: 'ignore-the-fee', corrected: true, answerParts: {},
    }});
    assertPracticeHistoryPreserved(before, replay);
    assert.equal(replay.completions[id]?.selectedChoiceId, 'include-value-fees-and-risk');
    const changed = parsePracticeProgress({...before, completions: {...before.completions, [id]: {
      ...before.completions[id]!, selectedChoiceId: 'ignore-the-fee', corrected: true,
    }}});
    assert.throws(() => assertPracticeHistoryPreserved(before, changed), {code: 'PRACTICE_HISTORY_CONFLICT'});
  });

  it('requires canonical timestamps without trailing newline in either supported version', () => {
    for (const version of [3, 4]) {
      const completions = completedThrough(1);
      completions['check-the-date']!.completedAt += '\n';
      assert.throws(() => parsePracticeProgress({version, active: null, completions}), invalid);
    }
  });
});


it('round-trips all actual Dart v4 transitions while preserving the historical v3 fixtures', () => {
  for (const version of [3, 4]) {
    const contract = JSON.parse(readFileSync(new URL(`../../../contracts/practice-progress-v${version}.json`, import.meta.url), 'utf8')) as {schemaVersion: number; cases: {name: string; progress: unknown}[]};
    assert.equal(contract.schemaVersion, 1);
    assert.ok(contract.cases.length >= (version === 3 ? 38 : 66));
    for (const entry of contract.cases) {
      const parsed = parsePracticeProgress(entry.progress);
      assert.equal(parsed.version, version, entry.name);
      assert.deepEqual(parsed, entry.progress, entry.name);
      assert.deepEqual(JSON.parse(canonicalPracticeProgress(parsed)), entry.progress, entry.name);
    }
  }
});
