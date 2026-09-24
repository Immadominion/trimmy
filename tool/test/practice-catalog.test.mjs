import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { assertReleasedCatalog, catalogDigest, catalogOutputPaths, generateCatalog,
  renderDart, renderTypeScript, validateCatalog } from '../generate-practice-catalog.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const source = JSON.parse(await readFile(resolve(root, 'content/practice-catalog.json'), 'utf8'));
const change = mutation => {const value = structuredClone(source); mutation(value); return value;};

test('release contains the sequential fourteen-activity course and two accepted team branches', () => {
  const catalog = validateCatalog(source);
  assert.equal(catalog.schemaVersion, 2);
  assert.equal(catalog.contentVersion, '2026-09-15.1');
  assert.equal(catalog.payloadVersion, 6);
  assert.deepEqual(catalog.floors, [{number: 1, title: 'Read the evidence'},
    {number: 2, title: 'Understand the numbers'}, {number: 3, title: 'Work with the team'},
    {number: 4, title: 'Make the plan'}]);
  assert.deepEqual(catalog.activities.map(entry => entry.id), ['check-the-date', 'sales-and-profit',
    'check-the-sample', 'prepare-the-update', 'compare-company-value', 'count-the-fees',
    'check-concentration', 'prepare-the-comparison', 'review-team-update',
    'read-returned-costs', 'finish-team-update', 'set-a-loss-limit', 'plan-not-a-promise',
    'write-the-plan']);
  assert.deepEqual(catalog.activities.map(entry => entry.introducedIn), [1, 1, 2, 3, 4, 4, 4, 4, 5, 5, 5, 6, 6, 6]);
  assert.deepEqual(catalog.activities.map(entry => entry.floor), [1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 4, 4, 4]);
  assert.equal(catalog.activities[4].prerequisiteId, 'prepare-the-update');
  assert.deepEqual(catalog.activities.slice(4).map(entry => entry.correctChoiceId),
    ['compare-total-value', 'nine-dollars-invested', 'eighty-percent-aster', 'include-value-fees-and-risk',
      'share-qualified-sales', 'compare-sales-and-costs', 'apply-returned-figures',
      'commit-spare-only', 'state-actions-and-limits', 'keep-limit-and-no-promise']);
  assert.deepEqual(catalog.activities[8].acceptedChoiceIds,
    ['share-qualified-sales', 'request-missing-costs']);
  assert.ok(Object.isFrozen(catalog));
  assert.throws(() => catalog.activities[0].choiceIds.push('new-answer'), TypeError);
});

test('legacy compound choices remain the exact complete, canonically ordered combinations', () => {
  const sample = source.activities[2];
  assert.deepEqual(sample.choiceIds, ['eight-of-ten-testers', 'all-testers', 'eight-of-ten-customers', 'all-customers']);
  const facts = ['dated-growth', 'lower-profit', 'trial-result', 'current-growth', 'all-customers'];
  const combinations = [];
  for (let first = 0; first < facts.length; first++) {
    for (let second = first + 1; second < facts.length; second++) {
      for (let third = second + 1; third < facts.length; third++) combinations.push([facts[first], facts[second], facts[third]].join('+'));
    }
  }
  assert.deepEqual(source.activities[3].choiceIds, combinations);
  assert.equal(source.activities[3].correctChoiceId, combinations[0]);
});

test('schema rejects duplicates, missing correct choices, broken chains and invalid floor ordering', () => {
  for (const mutation of [
    value => {value.activities[1].id = value.activities[0].id;},
    value => {value.activities[0].choiceIds.push(value.activities[0].choiceIds[0]);},
    value => {value.activities[0].correctChoiceId = 'missing';},
    value => {value.activities[8].acceptedChoiceIds = ['share-qualified-sales', 'missing'];},
    value => {value.activities[8].acceptedChoiceIds = ['request-missing-costs'];},
    value => {value.activities[8].acceptedChoiceIds.push('request-missing-costs');},
    value => {value.activities[0].prerequisiteId = 'check-concentration';},
    value => {value.activities[4].prerequisiteId = 'sales-and-profit';},
    value => {value.activities[0].floor = 2;},
    value => {value.activities[5].floor = 1;},
    value => {value.activities[7].floor = 1;},
    value => {value.activities[8].floor = 1;},
    value => {value.floors[1].number = 1;},
    value => {value.floors.push({number: 4, title: 'Unused floor'});},
    value => {value.activities[0].choiceIds = ['add-year'];},
    value => {value.activities[0].id += '\n';},
    value => {value.activities[0].script = 'arbitrary executable metadata';},
  ]) assert.throws(() => validateCatalog(change(mutation)), /Invalid practice catalog/);
});

test('schema rejects unsupported versions, impossible dates and unsafe numeric bounds', () => {
  for (const mutation of [
    value => {value.schemaVersion = 1;},
    value => {value.schemaVersion = 3;},
    value => {value.contentVersion = '2026-02-30.1';},
    value => {value.contentVersion = '2026-09-14.0';},
    value => {value.contentVersion += '\n';},
    value => {value.payloadVersion = 0;},
    value => {value.payloadVersion = 4.1;},
    value => {value.payloadVersion = Number.MAX_SAFE_INTEGER + 1;},
    value => {value.payloadVersion = 256;},
    value => {value.payloadVersion = 7;},
    value => {value.activities[0].introducedIn = 0;},
    value => {value.activities[4].introducedIn = 5;},
    value => {value.activities[7].introducedIn = 3;},
    value => {value.activities[10].introducedIn = 4;},
  ]) assert.throws(() => validateCatalog(change(mutation)), /Invalid practice catalog/);
});

test('validation never invokes accessors or accepts sparse and extra-property data', () => {
  const getter = structuredClone(source);
  Object.defineProperty(getter.activities[0], 'id', {enumerable: true, get() {throw new Error('getter was invoked');}});
  assert.throws(() => validateCatalog(getter), /fields must be plain data/);
  const sparse = structuredClone(source); delete sparse.activities[0].choiceIds[0];
  assert.throws(() => validateCatalog(sparse), /length or shape/);
  const added = structuredClone(source); added.activities.extra = 1;
  assert.throws(() => validateCatalog(added), /length or shape/);
});

test('release digest ignores JSON formatting but forbids silently changing a published release', () => {
  assertReleasedCatalog(source);
  const reordered = Object.fromEntries(Object.entries(source).reverse());
  assert.equal(catalogDigest(source), catalogDigest(reordered));
  const altered = change(value => {value.activities[4].title = 'Changed published title';});
  assert.throws(() => assertReleasedCatalog(altered), /released metadata changed/);
  const newVersion = change(value => {value.contentVersion = '2026-09-14.4';});
  assert.throws(() => assertReleasedCatalog(newVersion), /not registered/);
});

test('generated TS and Dart expose identical canonical metadata and safe string literals', () => {
  const typescript = renderTypeScript(source), dart = renderDart(source);
  const digest = catalogDigest(source);
  assert.ok(typescript.includes(digest)); assert.ok(dart.includes(digest));
  for (const entry of source.activities) {
    assert.ok(typescript.includes(`id: "${entry.id}"`));
    assert.ok(dart.includes(`id: '${entry.id}'`));
    for (const choice of entry.choiceIds) {assert.ok(typescript.includes(`"${choice}"`)); assert.ok(dart.includes(`'${choice}'`));}
  }
  const quoted = change(value => {value.activities[4].title = "Ada's $10 \\ note";});
  assert.ok(renderDart(quoted).includes("title: 'Ada\\'s \\$10 \\\\ note'"));
  assert.equal(renderTypeScript(source), renderTypeScript(structuredClone(source)));
  assert.equal(renderDart(source), renderDart(structuredClone(source)));
});

test('--check verifies current outputs without writing and reports both edited and missing outputs', async () => {
  await generateCatalog({root, check: true});
  const temporary = await mkdtemp(resolve(tmpdir(), 'trimmy-catalog-test-'));
  try {
    await mkdir(resolve(temporary, 'content'));
    await writeFile(resolve(temporary, 'content/practice-catalog.json'), JSON.stringify(source));
    await generateCatalog({root: temporary});
    const file = resolve(temporary, catalogOutputPaths.typescript);
    const before = await stat(file);
    await generateCatalog({root: temporary, check: true});
    assert.equal((await stat(file)).mtimeMs, before.mtimeMs);
    await writeFile(file, 'MANUALLY EDITED OUTPUT\n');
    await rm(resolve(temporary, catalogOutputPaths.dart));
    const command = spawnSync(process.execPath, [resolve(root, 'tool/generate-practice-catalog.mjs'), '--check', '--root', temporary], {encoding: 'utf8'});
    assert.equal(command.status, 1);
    assert.ok(command.stderr.includes(catalogOutputPaths.typescript));
    assert.ok(command.stderr.includes(catalogOutputPaths.dart));
    assert.equal(await readFile(file, 'utf8'), 'MANUALLY EDITED OUTPUT\n');
    await assert.rejects(readFile(resolve(temporary, catalogOutputPaths.dart)), {code: 'ENOENT'});
  } finally {await rm(temporary, {recursive: true, force: true});}
});
