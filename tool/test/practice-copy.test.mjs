import assert from 'node:assert/strict';
import {mkdtemp, readFile, mkdir, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {resolve} from 'node:path';
import {test} from 'node:test';
import {assertReleasedPracticeCopy, checkPracticeCopy, sealPracticeCopy,
  validatePracticeCopy, practiceCopyMaxBytes} from '../check-practice-copy.mjs';

const catalog = JSON.parse(await readFile(new URL('../../content/practice-catalog.json', import.meta.url), 'utf8'));
const manifest = JSON.parse(await readFile(new URL('../../content/practice-copy.json', import.meta.url), 'utf8'));
const clone = value => structuredClone(value);
const payload = value => { const copy = clone(value); delete copy.sha256; return copy; };
const reverseKeys = value => Array.isArray(value) ? value.map(reverseKeys)
  : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).reverse().map(key => [key, reverseKeys(value[key])])) : value;

test('frozen release verifies evidence and authored answer meaning with immutable output', async () => {
  const actual = await checkPracticeCopy();
  assert.deepEqual(actual.activities.map(activity => activity.id), catalog.activities.map(activity => activity.id));
  assert.equal(actual.activities[4].choices.find(choice => choice.id === 'compare-total-value').detail,
    'Harbor: $5 × 400 = $2,000. Aster: $10 × 100 = $1,000.');
  assert.deepEqual(actual.activities[7].presentationOrder,
    ['ignore-the-fee', 'include-value-fees-and-risk', 'choose-cheapest-share']);
  assert.equal(actual.activities[5].evidence[0].rows[2].value, '$9');
  assert.deepEqual(actual.activities[8].acceptedChoiceIds,
    ['share-qualified-sales', 'request-missing-costs']);
  assert.match(actual.activities[10].branchVariants['request-missing-costs'].successFeedback,
    /earlier request remains/);
  assert.throws(() => { actual.activities[5].evidence[0].rows[2].value = '$10'; }, TypeError);
  assert.throws(() => actual.activities[7].presentationOrder.reverse(), TypeError);
  assert.throws(() => { actual.activities[10].branchVariants['request-missing-costs'].outcomeTitle = 'Changed'; }, TypeError);
  assert.throws(() => actual.scope.excluded.push('extra'), TypeError);
  const input = clone(manifest);
  const parsed = validatePracticeCopy(input, catalog);
  input.activities[0].choices[0].detail = 'Changed meaning';
  assert.equal(parsed.activities[0].choices[0].detail, 'In 2025, users grew 80%.');
});

test('formatting and object key order do not change semantic digest; Unicode and line breaks survive', () => {
  const reordered = reverseKeys(manifest);
  assert.equal(validatePracticeCopy(reordered, catalog).sha256, manifest.sha256);
  assert.equal(validatePracticeCopy(JSON.parse(JSON.stringify(manifest, null, 4)), catalog).sha256, manifest.sha256);
  const text = manifest.activities[3].choices[0].detail;
  assert.ok(text.includes('\n\n'));
  assert.equal(validatePracticeCopy(manifest, catalog).activities[3].choices[0].detail, text);
  const changed = payload(manifest);
  changed.activities[3].choices[0].detail = text.replaceAll('\n\n', ' ');
  assert.notEqual(sealPracticeCopy(changed, catalog).sha256, manifest.sha256);
});

test('evidence, feedback, correction and presentation changes cannot be silently resealed', () => {
  const changes = [
    data => { data.activities[0].correctedHeadline = 'In 2026, users grew 80%.'; },
    data => { data.activities[4].evidence[0].rows[0].value = '$11'; },
    data => { data.activities[5].correctedFeedback += ' The fee buys shares.'; },
    data => { data.activities[3].choices[0].detail += ' Every customer agreed.'; },
    data => { data.activities[4].evidence[0].rows.reverse(); },
    data => { data.activities[7].presentationOrder.reverse(); data.activities[7].presentedChoiceIds.reverse(); },
    data => { data.activities[10].branchVariants['request-missing-costs'].journalEvidence += ' Rewritten.'; },
  ];
  for (const change of changes) {
    const changed = clone(manifest); change(changed);
    assert.throws(() => validatePracticeCopy(changed, catalog), /digest/);
    const resealed = sealPracticeCopy(payload(changed), catalog);
    assert.notEqual(resealed.sha256, manifest.sha256);
    assert.throws(() => assertReleasedPracticeCopy(resealed), /released copy changed/);
  }
  const next = payload(manifest); next.copyRevision++;
  assert.throws(() => assertReleasedPracticeCopy(sealPracticeCopy(next, catalog)), /not been registered/);
});

test('catalog identity and effective presentation order are validated independently of the hash', () => {
  const changes = [
    data => { data.contentVersion = '2026-09-14.2'; },
    data => { data.activities.reverse(); },
    data => { data.activities[0].correctChoiceId = 'keep-headline'; },
    data => { data.activities[8].acceptedChoiceIds.pop(); },
    data => { data.activities[0].choices.reverse(); },
    data => { data.activities[0].title = 'A renamed lesson'; },
    data => { data.activities[7].presentationOrder = ['ignore-the-fee']; },
    data => { data.activities[7].presentationOrder[1] = 'ignore-the-fee'; },
    data => { data.activities[7].presentedChoiceIds.reverse(); },
    data => { data.activities[0].presentedChoiceIds.reverse(); },
  ];
  for (const change of changes) {
    const data = payload(manifest); change(data);
    assert.throws(() => sealPracticeCopy(data, catalog), /Invalid practice copy/);
  }
});

test('strict schema, derived counts, scope, text bounds and data shapes reject malformed records', () => {
  const changes = [
    data => { data.schemaVersion = 1; },
    data => { data.schemaVersion = 3; },
    data => { data.copyRevision = 0; },
    data => { data.copyRevision = 1.1; },
    data => { data.extra = true; },
    data => { delete data.activities[0].sourceExplanation; },
    data => { data.activities[0].choices[0].rating = 1; },
    data => { data.activities[4].evidence[0].rows[0].unit = 'dollar'; },
    data => { data.activities[10].branchVariants['not-a-branch'] = data.activities[10].branchVariants['request-missing-costs']; },
    data => { data.counts.evidenceRows++; },
    data => { data.counts.choices--; },
    data => { data.counts.activities = '8'; },
    data => { data.scope.excluded.pop(); },
    data => { data.scope.covered[0] = 'All mobile UI and first-answer meaning.'; },
    data => { data.activities[0].intro = 'x'.repeat(4001); },
    data => { data.activities[0].intro = 'text\rbreak'; },
    data => { data.activities[0].intro = '\ud800'; },
    data => { delete data.activities[0]; },
    data => { data.activities.extra = 'surprise'; },
    data => { data.activities[0] = Object.create(data.activities[0]); },
    data => { Object.defineProperty(data.activities[0], 'intro', {get() { throw new Error('getter invoked'); }}); },
  ];
  for (const change of changes) {
    const data = payload(manifest); change(data);
    assert.throws(() => sealPracticeCopy(data, catalog), /Invalid practice copy/);
  }
  for (const sha256 of ['0'.repeat(64), manifest.sha256.toUpperCase(), `${manifest.sha256}\n`, null]) {
    assert.throws(() => validatePracticeCopy({...manifest, sha256}, catalog), /Invalid practice copy/);
  }
});

test('checks are read-only and reject oversized or malformed UTF-8 files', async () => {
  const root = await mkdtemp(resolve(tmpdir(), 'trimmy-copy-'));
  try {
    await mkdir(resolve(root, 'content'));
    await writeFile(resolve(root, 'content/practice-catalog.json'), JSON.stringify(catalog));
    const path = resolve(root, 'content/practice-copy.json');
    const raw = JSON.stringify(reverseKeys(manifest), null, 4);
    await writeFile(path, raw);
    await checkPracticeCopy({root});
    assert.equal(await readFile(path, 'utf8'), raw);
    for (const malformed of [' '.repeat(practiceCopyMaxBytes + 1), Buffer.from([0xc3, 0x28]), '{broken']) {
      await writeFile(path, malformed);
      const before = await readFile(path);
      await assert.rejects(checkPracticeCopy({root}));
      assert.deepEqual(await readFile(path), before);
    }
  } finally { await rm(root, {recursive: true, force: true}); }
});
