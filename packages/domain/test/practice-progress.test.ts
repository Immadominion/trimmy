import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';
import {
  DomainError, parsePracticeProgress, canonicalPracticeProgress, assertPracticeHistoryPreserved,
} from '../src/index.js';
import type { PracticeActivityId, PracticeProgress } from '../src/index.js';

const ids: readonly PracticeActivityId[] = ['check-the-date', 'sales-and-profit', 'check-the-sample', 'prepare-the-update'];
const factIds = ['dated-growth', 'lower-profit', 'trial-result', 'current-growth', 'all-customers'];
const correctChoices = ['add-year', 'check-costs', 'eight-of-ten-testers', 'dated-growth+lower-profit+trial-result'];
const time = '2026-09-14T12:34:56.123456Z';
const isCode = (code: string) => (error: unknown) => error instanceof DomainError && error.code === code;
const invalid = isCode('INVALID_PRACTICE_PROGRESS');
const conflict = isCode('PRACTICE_HISTORY_CONFLICT');

interface CompletionFixture {
  activityId: string;
  selectedChoiceId: string;
  corrected: boolean;
  completedAt: string | null;
  importedFromLegacy: boolean;
}
interface ActiveFixture {
  activityId: string;
  stage: number;
  selectedChoiceId: string | null;
  corrected: boolean;
  answerParts: Record<string, string>;
}
interface Fixture {
  version: number;
  active: ActiveFixture | null;
  completions: Record<string, CompletionFixture>;
}
function completion(id: PracticeActivityId): CompletionFixture {
  return {activityId: id, selectedChoiceId: correctChoices[ids.indexOf(id)]!, corrected: false, completedAt: time, importedFromLegacy: false};
}
function empty(): Fixture { return {version: 3, active: null, completions: {}}; }
function ready(id: PracticeActivityId): Fixture {
  const result = empty();
  for (const previous of ids.slice(0, ids.indexOf(id))) result.completions[previous] = completion(previous);
  result.active = {activityId: id, stage: 2, selectedChoiceId: null, corrected: false, answerParts: {}};
  return result;
}
function finished(id: PracticeActivityId): Fixture {
  const result = ready(id);
  result.active = null;
  result.completions[id] = completion(id);
  return result;
}
function updateDraft(chosen: readonly string[], stage = 2): Fixture {
  const result = ready('prepare-the-update');
  const selected = factIds.filter(id => chosen.includes(id));
  const choice = selected.length === 3 ? selected.join('+') : null;
  result.active = {
    activityId: 'prepare-the-update', stage,
    selectedChoiceId: choice,
    corrected: stage >= 3 && choice !== correctChoices[3],
    answerParts: Object.fromEntries(chosen.map(id => [id, 'included'])),
  };
  if (stage === 4) {
    result.completions['prepare-the-update'] = {
      ...completion('prepare-the-update'), selectedChoiceId: choice!, corrected: result.active.corrected,
    };
  }
  return result;
}
function mutable(input: unknown): Record<string, unknown> { return input as Record<string, unknown>; }
function clone<T>(input: T): T { return structuredClone(input); }

describe('native practice payload validation', () => {
  it('accepts empty progress and partial drafts without inventing completions', () => {
    assert.deepEqual(parsePracticeProgress(empty()), empty());
    for (const part of [{amount: 'eight-of-ten'}, {group: 'testers'}]) {
      const input = ready('check-the-sample');
      input.active!.answerParts = part as Record<string, string>;
      for (const stage of [0, 1, 2]) {
        input.active!.stage = stage;
        const parsed = parsePracticeProgress(input);
        assert.deepEqual(parsed.active!.answerParts, part);
        assert.equal(parsed.active!.selectedChoiceId, null);
        assert.deepEqual(Object.keys(parsed.completions), ids.slice(0, 2));
      }
    }
    const input = updateDraft(['trial-result']);
    input.active!.answerParts['current-growth'] = 'excluded';
    const parsed = parsePracticeProgress(input);
    assert.deepEqual(parsed.active!.answerParts, {'trial-result': 'included', 'current-growth': 'excluded'});
    assert.equal(parsed.active!.selectedChoiceId, null);
  });

  it('accepts each sample combination with correct correction and completion semantics', () => {
    for (const amount of ['eight-of-ten', 'all']) {
      for (const group of ['testers', 'customers']) {
        const choice = `${amount}-${group}`;
        const corrected = choice !== 'eight-of-ten-testers';
        const input = ready('check-the-sample');
        input.active = {activityId: 'check-the-sample', stage: corrected ? 3 : 4, selectedChoiceId: choice, corrected, answerParts: {group, amount}};
        if (!corrected) input.completions['check-the-sample'] = completion('check-the-sample');
        assert.deepEqual(parsePracticeProgress(input).active, input.active);
        if (corrected) {
          input.active.stage = 4;
          input.completions['check-the-sample'] = {...completion('check-the-sample'), selectedChoiceId: choice, corrected};
          assert.deepEqual(parsePracticeProgress(input).completions['check-the-sample'], input.completions['check-the-sample']);
        }
      }
    }
  });

  it('accepts every update combination while preserving authored order independently of tap order', () => {
    for (let a = 0; a < factIds.length; a++) {
      for (let b = a + 1; b < factIds.length; b++) {
        for (let c = b + 1; c < factIds.length; c++) {
          const chosen = [factIds[a]!, factIds[b]!, factIds[c]!];
          const choice = chosen.join('+');
          const input = updateDraft([...chosen].reverse());
          assert.equal(parsePracticeProgress(input).active!.selectedChoiceId, choice);
          input.active!.stage = choice === correctChoices[3] ? 4 : 3;
          input.active!.corrected = choice !== correctChoices[3];
          if (input.active!.stage === 4) input.completions['prepare-the-update'] = completion('prepare-the-update');
          assert.deepEqual(parsePracticeProgress(input).active!.answerParts, input.active!.answerParts);
          if (input.active!.stage === 3) {
            input.active!.stage = 4;
            input.completions['prepare-the-update'] = {...completion('prepare-the-update'), selectedChoiceId: choice, corrected: true};
            assert.equal(parsePracticeProgress(input).completions['prepare-the-update']!.selectedChoiceId, choice);
          }
        }
      }
    }
  });

  it('allows an active replay to differ from first completion and keeps both records intact', () => {
    const input = finished('prepare-the-update');
    const replay = updateDraft(['current-growth', 'lower-profit', 'all-customers'], 3);
    input.active = replay.active;
    assert.equal(parsePracticeProgress(input).active!.stage, 3);
    input.active!.stage = 4;
    const parsed = parsePracticeProgress(input);
    assert.equal(parsed.active!.corrected, true);
    assert.equal(parsed.completions['prepare-the-update']!.corrected, false);
    assert.equal(parsed.completions['prepare-the-update']!.selectedChoiceId, correctChoices[3]);
  });

  it('preserves legacy unknown time only for imported first-activity completions', () => {
    const input = finished('check-the-date');
    const record = input.completions['check-the-date']!;
    record.importedFromLegacy = true;
    record.completedAt = null;
    record.selectedChoiceId = 'keep-headline';
    record.corrected = true;
    assert.equal(parsePracticeProgress(input).completions['check-the-date']!.completedAt, null);
    record.completedAt = time;
    assert.equal(parsePracticeProgress(input).completions['check-the-date']!.completedAt, time);
    record.importedFromLegacy = false;
    record.completedAt = null;
    assert.throws(() => parsePracticeProgress(input), invalid);
    const second = finished('sales-and-profit');
    second.completions['sales-and-profit']!.importedFromLegacy = true;
    assert.throws(() => parsePracticeProgress(second), invalid);
  });

  it('rejects missing prerequisites in active assignments and completed histories', () => {
    for (const id of ids.slice(1)) {
      const missing = ids[ids.indexOf(id) - 1]!;
      for (const input of [ready(id), finished(id)]) {
        delete input.completions[missing];
        assert.throws(() => parsePracticeProgress(input), invalid);
      }
    }
  });

  it('rejects malformed shapes, versions, stages, answer maps and contradictory combined choices', () => {
    const mutations: Array<(input: Record<string, unknown>) => void> = [
      data => { data['version'] = 1; }, data => { data['version'] = 2; },
      data => { data['version'] = 7; }, data => { data['version'] = '3'; },
      data => { delete data['active']; }, data => { data['unknown'] = false; },
      data => { data['completions'] = []; }, data => { data['active'] = []; },
      data => { mutable(data['active'])['stage'] = 2.5; },
      data => { mutable(data['active'])['stage'] = NaN; },
      data => { mutable(data['active'])['stage'] = Infinity; },
      data => { mutable(data['active'])['stage'] = -1; },
      data => { mutable(data['active'])['stage'] = 5; },
      data => { mutable(data['active'])['stage'] = '2'; },
      data => { mutable(data['active'])['selectedChoiceId'] = undefined; },
      data => { mutable(data['active'])['selectedChoiceId'] = null; },
      data => { mutable(data['active'])['selectedChoiceId'] = 'trial-result+lower-profit+dated-growth'; },
      data => { mutable(data['active'])['selectedChoiceId'] = 'dated-growth+dated-growth+lower-profit'; },
      data => { mutable(data['active'])['corrected'] = true; },
      data => { mutable(data['active'])['activityId'] = 'unknown'; },
      data => { mutable(data['active'])['answerParts'] = null; },
      data => { mutable(data['active'])['answerParts'] = []; },
      data => { mutable(data['active'])['answerParts'] = {'dated-growth': 'included'}; },
      data => { mutable(mutable(data['active'])['answerParts'])['current-growth'] = 'included'; },
      data => { mutable(mutable(data['active'])['answerParts'])['dated-growth'] = 'excluded'; },
      data => { mutable(mutable(data['active'])['answerParts'])['dated-growth'] = true; },
      data => { mutable(mutable(data['active'])['answerParts'])['dated-growth'] = 'Included'; },
      data => { mutable(mutable(data['active'])['answerParts'])['extra'] = 'excluded'; },
    ];
    const valid = updateDraft(factIds.slice(0, 3));
    for (const [index, mutation] of mutations.entries()) {
      const candidate = mutable(clone(valid));
      mutation(candidate);
      assert.throws(() => parsePracticeProgress(candidate), invalid, `Mutation ${index}`);
    }
    const first = ready('check-the-date');
    first.active!.answerParts = {amount: 'all'};
    assert.throws(() => parsePracticeProgress(first), invalid);
    const partial = ready('check-the-sample');
    partial.active!.answerParts = {group: 'customers'};
    partial.active!.stage = 3;
    partial.active!.corrected = true;
    assert.throws(() => parsePracticeProgress(partial), invalid);
  });

  it('rejects premature outcomes and invalid first-completion flags without constraining replay identity', () => {
    const first = ready('check-the-date');
    first.active!.selectedChoiceId = 'add-year';
    first.active!.stage = 4;
    assert.throws(() => parsePracticeProgress(first), invalid);
    first.completions['check-the-date'] = completion('check-the-date');
    assert.doesNotThrow(() => parsePracticeProgress(first));
    first.active!.stage = 3;
    first.active!.corrected = true;
    assert.throws(() => parsePracticeProgress(first), invalid);
    const mutations: Array<(record: Record<string, unknown>) => void> = [
      record => { record['activityId'] = 'sales-and-profit'; },
      record => { record['selectedChoiceId'] = 'check-costs'; },
      record => { record['corrected'] = true; },
      record => { record['corrected'] = 0; },
      record => { record['completedAt'] = null; },
      record => { record['importedFromLegacy'] = 'false'; },
      record => { record['unexpected'] = true; },
    ];
    for (const mutation of mutations) {
      const input = finished('check-the-date');
      mutation(mutable(input.completions['check-the-date']));
      assert.throws(() => parsePracticeProgress(input), invalid);
    }
  });

  it('rejects unsafe object shapes without invoking getters or serialization hooks', () => {
    let invoked = 0;
    const accessor = empty();
    Object.defineProperty(accessor, 'active', {enumerable: true, get() { invoked++; throw new Error('getter ran'); }});
    const serializer = {...empty(), toJSON() { invoked++; return empty(); }};
    const inherited = Object.assign(Object.create({inherited: true}) as object, empty());
    const symbol = {...empty(), [Symbol('hidden')]: true};
    const hidden = empty();
    Object.defineProperty(hidden, 'active', {enumerable: false, value: null});
    const magicKey = JSON.parse('{"version":3,"active":null,"completions":{},"__proto__":{}}') as unknown;
    const cyclic = empty();
    mutable(cyclic)['active'] = cyclic;
    const revoked = Proxy.revocable({}, {});
    revoked.revoke();
    for (const unsafe of [undefined, null, [], '[]', new Date(), accessor, serializer, inherited, symbol, hidden, magicKey, cyclic, revoked.proxy]) {
      assert.throws(() => parsePracticeProgress(unsafe), invalid);
    }
    assert.equal(invoked, 0);
    const nested = ready('check-the-date');
    Object.defineProperty(nested.active!, 'answerParts', {enumerable: true, get() { invoked++; return {}; }});
    assert.throws(() => parsePracticeProgress(nested), invalid);
    assert.equal(invoked, 0);
    // A null-prototype data record has no inherited behavior and is safe.
    assert.deepEqual(parsePracticeProgress(Object.assign(Object.create(null) as object, empty())), empty());
  });

  it('returns a deep-frozen detached snapshot while leaving the input mutable', () => {
    const input = updateDraft(factIds.slice(0, 3), 4);
    const expected = clone(input);
    const result = parsePracticeProgress(input);
    assert.ok(Object.isFrozen(result));
    assert.ok(Object.isFrozen(result.active));
    assert.ok(Object.isFrozen(result.active!.answerParts));
    assert.ok(Object.isFrozen(result.completions));
    for (const saved of Object.values(result.completions)) assert.ok(Object.isFrozen(saved));
    assert.ok(!Object.isFrozen(input));
    input.active!.answerParts['dated-growth'] = 'excluded';
    input.completions['check-the-date']!.completedAt = '2000-01-01T00:00:00.000Z';
    assert.deepEqual(result, expected);
    assert.throws(() => { mutable(result.active!.answerParts)['dated-growth'] = 'excluded'; }, TypeError);
    assert.throws(() => { delete mutable(result.completions)['check-the-date']; }, TypeError);
  });
});

describe('native canonical timestamps and canonical JSON', () => {
  it('preserves milliseconds and microseconds including valid leap days and native year boundaries', () => {
    const valid = [
      '2026-09-14T12:34:56.123Z', time, '2026-09-14T12:34:56.000001Z',
      '2000-02-29T23:59:59.999999Z', '2024-02-29T00:00:00.000Z',
      '0000-02-29T00:00:00.000Z', '0099-01-01T00:00:00.000Z',
      '-0001-12-31T23:59:59.999999Z', '-9999-01-01T00:00:00.000Z',
      '+010000-01-01T00:00:00.000Z', '-010000-01-01T00:00:00.000Z',
      '-271821-04-20T00:00:00.000Z', '-271821-04-20T00:00:00.000001Z',
      '+275760-09-13T00:00:00.000Z',
    ];
    for (const timestamp of valid) {
      const input = finished('check-the-date');
      input.completions['check-the-date']!.completedAt = timestamp;
      const result = parsePracticeProgress(input);
      assert.equal(result.completions['check-the-date']!.completedAt, timestamp);
      assert.ok(canonicalPracticeProgress(result).includes(JSON.stringify(timestamp)));
    }
  });

  it('rejects calendar overflow, aliases, precision loss, ambiguous zones and out-of-range instants', () => {
    const invalidTimes = [
      '1900-02-29T00:00:00.000Z', '2026-02-29T00:00:00.000Z', '2026-04-31T00:00:00.000Z',
      '2026-00-01T00:00:00.000Z', '2026-13-01T00:00:00.000Z', '2026-01-00T00:00:00.000Z',
      '2026-01-01T24:00:00.000Z', '2026-01-01T00:60:00.000Z', '2026-01-01T00:00:60.000Z',
      '2026-01-01T00:00:00Z', '2026-01-01T00:00:00.12Z', '2026-01-01T00:00:00.1234Z',
      '2026-01-01T00:00:00.1234567Z', '2026-01-01T00:00:00.123000Z',
      '2026-01-01T00:00:00.000+00:00', '2026-01-01T00:00:00.000',
      '2026-01-01t00:00:00.000z', ' 2026-01-01T00:00:00.000Z',
      '+002026-01-01T00:00:00.000Z', '-000001-01-01T00:00:00.000Z', '-0000-01-01T00:00:00.000Z',
      '+275760-09-13T00:00:00.000001Z', '+275760-09-13T00:00:00.001Z',
      '-271821-04-19T23:59:59.999999Z', '+999999-01-01T00:00:00.000Z',
    ];
    for (const timestamp of invalidTimes) {
      const input = finished('check-the-date');
      input.completions['check-the-date']!.completedAt = timestamp;
      assert.throws(() => parsePracticeProgress(input), invalid, timestamp);
    }
  });

  it('canonicalizes every object order but preserves exclusions and individual microseconds', () => {
    const input = updateDraft(['trial-result', 'lower-profit', 'dated-growth']);
    input.active!.answerParts['all-customers'] = 'excluded';
    const parsed = parsePracticeProgress(input);
    function reverse(value: unknown): unknown {
      if (value === null || typeof value !== 'object') return value;
      return Object.fromEntries(Object.entries(value).reverse().map(([key, item]) => [key, reverse(item)]));
    }
    const reordered = parsePracticeProgress(reverse(input));
    const text = canonicalPracticeProgress(parsed);
    assert.equal(text, canonicalPracticeProgress(reordered));
    assert.equal(text, canonicalPracticeProgress(parsePracticeProgress(JSON.parse(text))));
    assert.deepEqual(JSON.parse(text), parsed);
    assert.equal(canonicalPracticeProgress(parsePracticeProgress(empty())), '{"active":null,"completions":{},"version":3}');
    const next = clone(input);
    next.completions['check-the-date']!.completedAt = '2026-09-14T12:34:56.123457Z';
    assert.notEqual(canonicalPracticeProgress(parsePracticeProgress(next)), text);
    delete next.active!.answerParts['all-customers'];
    next.completions['check-the-date']!.completedAt = time;
    assert.notEqual(canonicalPracticeProgress(parsePracticeProgress(next)), text);
  });

  it('revalidates typed callers instead of serializing forged or oversized values', () => {
    const forged = {...empty(), extra: '💡'.repeat(32_769)} as unknown as PracticeProgress;
    assert.throws(() => canonicalPracticeProgress(forged), invalid);
    assert.throws(() => parsePracticeProgress(forged), invalid);
    const unsafe = {...empty(), toJSON() { throw new Error('do not invoke'); }} as unknown as PracticeProgress;
    assert.throws(() => canonicalPracticeProgress(unsafe), invalid);
  });
});

describe('first-completion history preservation', () => {
  it('permits new completions and changing or closing active replay drafts', () => {
    const before = parsePracticeProgress(finished('check-the-date'));
    const next = finished('sales-and-profit');
    next.active = {activityId: 'check-the-date', stage: 2, selectedChoiceId: 'keep-headline', corrected: false, answerParts: {}};
    assert.doesNotThrow(() => assertPracticeHistoryPreserved(before, parsePracticeProgress(next)));
    next.active = null;
    assert.doesNotThrow(() => assertPracticeHistoryPreserved(before, parsePracticeProgress(next)));
  });

  it('rejects deletion or any replacement of the original choice, correction, time or import status', () => {
    const previous = finished('prepare-the-update');
    previous.completions['check-the-date']!.importedFromLegacy = true;
    const before = parsePracticeProgress(previous);
    const mutations: Array<(candidate: Fixture) => void> = [
      candidate => { delete candidate.completions['prepare-the-update']; },
      candidate => {
        candidate.completions['check-the-date']!.selectedChoiceId = 'keep-headline';
        candidate.completions['check-the-date']!.corrected = true;
      },
      candidate => { candidate.completions['check-the-date']!.completedAt = '2026-09-14T12:34:56.123457Z'; },
      candidate => { candidate.completions['check-the-date']!.completedAt = '2026-09-14T12:34:56.123Z'; },
      candidate => { candidate.completions['check-the-date']!.completedAt = null; },
      candidate => { candidate.completions['check-the-date']!.importedFromLegacy = false; },
    ];
    for (const mutation of mutations) {
      const candidate = clone(previous);
      mutation(candidate);
      const parsed = parsePracticeProgress(candidate);
      assert.throws(() => assertPracticeHistoryPreserved(before, parsed), conflict);
    }
    assert.doesNotThrow(() => assertPracticeHistoryPreserved(before, parsePracticeProgress(clone(previous))));
  });

  it('validates both snapshots before comparing history', () => {
    const valid = parsePracticeProgress(empty());
    const bad = {...empty(), version: 7} as unknown as PracticeProgress;
    assert.throws(() => assertPracticeHistoryPreserved(bad, valid), invalid);
    assert.throws(() => assertPracticeHistoryPreserved(valid, bad), invalid);
  });
});

describe('Dart-generated practice payload contract', () => {
  it('preserves every native fixture through parsing and canonical JSON round trips', () => {
    const contract = JSON.parse(readFileSync(new URL('../../../contracts/practice-progress-v3.json', import.meta.url), 'utf8')) as {
      schemaVersion: number;
      cases: Array<{name: string; progress: PracticeProgress}>;
    };
    assert.equal(contract.schemaVersion, 1);
    assert.ok(contract.cases.some(item => item.name.includes('replay')));
    assert.ok(contract.cases.some(item => item.progress.completions['check-the-date']?.completedAt?.endsWith('123456Z')));
    for (const fixture of contract.cases) {
      const parsed = parsePracticeProgress(fixture.progress);
      assert.deepEqual(parsed, fixture.progress, fixture.name);
      const text = canonicalPracticeProgress(parsed);
      assert.equal(canonicalPracticeProgress(parsePracticeProgress(JSON.parse(text))), text, fixture.name);
      assert.deepEqual(JSON.parse(text), fixture.progress, fixture.name);
      for (const id of ids) {
        assert.equal(parsed.completions[id]?.completedAt, fixture.progress.completions[id]?.completedAt, `${fixture.name}/${id}`);
      }
    }
  });
});
