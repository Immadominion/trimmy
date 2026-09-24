#!/usr/bin/env node
import {createHash} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {assertReleasedCatalog, validateCatalog} from './generate-practice-catalog.mjs';

const defaultRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const practiceCopyMaxBytes = 256 * 1024;
export const practiceCopyScope = Object.freeze({
  source: 'apps/mobile/lib/design_study/activities.dart',
  type: 'ActivityDefinition',
  covered: Object.freeze([
    'Authored public fields, including activity-level feedback and Journal evidence.',
    'Choice IDs, labels and details in canonical order.',
    'ActivityEvidence titles, ordered rows and explanations.',
    'ActivityDefinition presentationOrder and presentedChoiceIds; composite composer controls are separate.',
    'Accepted choice IDs and every authored branch consequence keyed by a catalog choice.',
  ]),
  excluded: Object.freeze([
    'Widget-local date, sales, sample and update source, composer and review strings.',
    'Widget-local source tables and chart data, sample response outcomes, and composer part labels and order.',
    'UpdateFact fields except text projected into ActivityDefinition headlines and choices.',
    'Other Journal and Ada narrative generated outside ActivityDefinition.',
    'Layouts, motion, sound, illustrations, fonts and gameplay or saved-progress behavior.',
  ]),
});

// Append reviewed revisions; do not replace an existing release digest. This is
// a repository review lock, not a signature or a remote-content authorization.
const releases = Object.freeze({
  '2026-09-14.2/1': '709f36c8356bc0ac5c16f980d883687f97557f8875ef92ba683a38e5b1acc8ab',
  '2026-09-14.3/1': '5eb6eb39ab21de76e4c70ce3740143e1e67aa375bc5b7fa0fbf35d53fa7f35d4',
  '2026-09-15.1/1': '24775dec2322bcbf6287650f5d2f43c375680fa06998c790ef374a6ef851480e',
});
const copyFields = ['schemaVersion', 'contentVersion', 'copyRevision', 'scope', 'counts', 'activities'];
const textFields = ['title', 'officeDescription', 'intro', 'sourceIntro', 'sourceTitle',
  'sourceExplanation', 'draftHeadline', 'correctedHeadline', 'challengeTitle', 'challengeText',
  'correctedFeedback', 'successFeedback', 'journalEvidence'];
const activityFields = ['id', ...textFields, 'correctChoiceId', 'choices', 'evidence',
  'presentationOrder', 'presentedChoiceIds', 'acceptedChoiceIds', 'branchVariants'];
const branchFields = ['intro', 'draftHeadline', 'correctedHeadline', 'correctedFeedback',
  'successFeedback', 'journalEvidence', 'outcomeTitle', 'officeConsequence'];

function invalid(message) { throw new Error(`Invalid practice copy: ${message}`); }
function object(value, keys, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      ![Object.prototype, null].includes(Object.getPrototypeOf(value))) invalid(`${label} must be a plain object`);
  const actual = Reflect.ownKeys(value);
  if (actual.length !== keys.length || actual.some(key => !keys.includes(key))) invalid(`${label} fields differ from schema`);
  for (const key of keys) {
    const property = Object.getOwnPropertyDescriptor(value, key);
    if (!property?.enumerable || !Object.hasOwn(property, 'value')) invalid(`${label} must contain plain data`);
  }
  return value;
}
function array(value, min, max, label) {
  if (!Array.isArray(value) || Object.getPrototypeOf(value) !== Array.prototype ||
      value.length < min || value.length > max || Reflect.ownKeys(value).length !== value.length + 1) invalid(`${label} length or shape`);
  for (let i = 0; i < value.length; i++) {
    const property = Object.getOwnPropertyDescriptor(value, String(i));
    if (!property?.enumerable || !Object.hasOwn(property, 'value')) invalid(`${label} must be dense plain data`);
  }
  return value;
}
function dictionary(value, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      ![Object.prototype, null].includes(Object.getPrototypeOf(value))) invalid(`${label} must be a plain object`);
  for (const key of Reflect.ownKeys(value)) {
    if (typeof key !== 'string' || !/^[a-z][a-z0-9-]*$/.test(key)) invalid(`${label} has an invalid key`);
    const property = Object.getOwnPropertyDescriptor(value, key);
    if (!property?.enumerable || !Object.hasOwn(property, 'value')) invalid(`${label} must contain plain data`);
  }
  return value;
}
function text(value, label, max = 4000) {
  if (typeof value !== 'string' || !value || value.length > max || value.trim() !== value ||
      !value.isWellFormed() || /[\u0000-\u0009\u000b-\u001f\u007f]/.test(value)) invalid(`${label} invalid text`);
  return value;
}
function equal(left, right) { return JSON.stringify(left) === JSON.stringify(right); }
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]));
  }
  return value;
}
function digest(data) {
  const bytes = JSON.stringify(canonical(data));
  if (Buffer.byteLength(bytes, 'utf8') > practiceCopyMaxBytes) invalid('semantic payload is too large');
  return createHash('sha256').update(bytes, 'utf8').digest('hex');
}

function validateData(input, catalogInput) {
  const data = object(input, copyFields, 'manifest');
  const catalog = validateCatalog(catalogInput);
  if (data.schemaVersion !== 2) invalid('unsupported schemaVersion');
  if (data.contentVersion !== catalog.contentVersion) invalid('contentVersion does not match metadata release');
  if (!Number.isSafeInteger(data.copyRevision) || data.copyRevision < 1 || data.copyRevision > 1_000_000) invalid('copyRevision outside supported bounds');
  const scope = object(data.scope, ['source', 'type', 'covered', 'excluded'], 'scope');
  array(scope.covered, 5, 5, 'scope covered');
  array(scope.excluded, 5, 5, 'scope excluded');
  if (scope.source !== practiceCopyScope.source || scope.type !== practiceCopyScope.type ||
      scope.covered.some((value, index) => value !== practiceCopyScope.covered[index]) ||
      scope.excluded.some((value, index) => value !== practiceCopyScope.excluded[index])) invalid('scope differs from schema2 coverage');
  const totals = {activities: 0, choices: 0, evidence: 0, evidenceRows: 0, branchVariants: 0};
  const activities = array(data.activities, catalog.activities.length, catalog.activities.length, 'activities')
    .map((value, index) => {
      const activity = object(value, activityFields, 'activity');
      const registry = catalog.activities[index];
      if (activity.id !== registry.id) invalid('activity IDs or order differ from catalog');
      if (activity.title !== registry.title) invalid('activity title differs from catalog');
      if (activity.correctChoiceId !== registry.correctChoiceId) invalid('correct answer differs from catalog');
      const accepted = array(activity.acceptedChoiceIds, registry.acceptedChoiceIds.length,
        registry.acceptedChoiceIds.length, 'acceptedChoiceIds');
      if (!equal(accepted, registry.acceptedChoiceIds)) invalid('accepted choices differ from catalog');
      const copy = Object.fromEntries(textFields.map(key => [key, text(activity[key], `${activity.id}.${key}`)]));
      const choices = array(activity.choices, registry.choiceIds.length, registry.choiceIds.length, 'choices')
        .map((value, choiceIndex) => {
          const choice = object(value, ['id', 'label', 'detail'], 'choice');
          if (choice.id !== registry.choiceIds[choiceIndex]) invalid('choice IDs or order differ from catalog');
          return Object.freeze({id: choice.id, label: text(choice.label, 'choice label', 160), detail: text(choice.detail, 'choice detail')});
        });
      const evidence = array(activity.evidence, 0, 8, 'evidence').map(value => {
        const source = object(value, ['title', 'rows', 'explanation'], 'evidence');
        const rows = array(source.rows, 1, 16, 'evidence rows').map(value => {
          const row = object(value, ['label', 'value'], 'evidence row');
          return Object.freeze({label: text(row.label, 'row label', 200), value: text(row.value, 'row value', 200)});
        });
        totals.evidenceRows += rows.length;
        return Object.freeze({title: text(source.title, 'evidence title', 200), rows: Object.freeze(rows), explanation: text(source.explanation, 'evidence explanation')});
      });
      const order = array(activity.presentationOrder, 0, choices.length, 'presentationOrder');
      if (order.length && (order.length !== choices.length || new Set(order).size !== choices.length ||
          order.some(id => !registry.choiceIds.includes(id)))) invalid('presentationOrder must be empty or a complete choice permutation');
      const presented = array(activity.presentedChoiceIds, choices.length, choices.length, 'presentedChoiceIds');
      if (!equal(presented, order.length ? order : registry.choiceIds)) invalid('presentedChoiceIds differs from effective definition order');
      const variants = dictionary(activity.branchVariants, 'branchVariants');
      const knownBranchKeys = new Set(catalog.activities.slice(0, index + 1)
        .flatMap(entry => entry.acceptedChoiceIds));
      const checkedVariants = Object.fromEntries(Object.entries(variants).map(([key, value]) => {
        if (!knownBranchKeys.has(key)) invalid('branch variant key is not an accepted choice available at this point');
        const variant = object(value, branchFields, 'branch variant');
        return [key, Object.freeze(Object.fromEntries(branchFields.map(field =>
          [field, text(variant[field], `${activity.id}.branchVariants.${key}.${field}`)])))];
      }));
      totals.activities++; totals.choices += choices.length; totals.evidence += evidence.length;
      totals.branchVariants += Object.keys(checkedVariants).length;
      return Object.freeze({id: activity.id, ...copy, correctChoiceId: activity.correctChoiceId,
        acceptedChoiceIds: Object.freeze([...accepted]),
        choices: Object.freeze(choices), evidence: Object.freeze(evidence),
        presentationOrder: Object.freeze([...order]), presentedChoiceIds: Object.freeze([...presented]),
        branchVariants: Object.freeze(checkedVariants)});
    });
  const counts = object(data.counts, Object.keys(totals), 'counts');
  for (const [key, value] of Object.entries(totals)) {
    if (!Number.isSafeInteger(counts[key]) || counts[key] !== value) invalid(`${key} count differs from authored entries`);
  }
  return Object.freeze({schemaVersion: 2, contentVersion: data.contentVersion, copyRevision: data.copyRevision,
    scope: practiceCopyScope, counts: Object.freeze(totals), activities: Object.freeze(activities)});
}

/** Canonical UTF-8 semantic content, excluding only the digest field. */
export function sealPracticeCopy(input, catalog) {
  const data = validateData(input, catalog);
  return Object.freeze({...data, sha256: digest(data)});
}
export function validatePracticeCopy(input, catalog) {
  const manifest = object(input, [...copyFields, 'sha256'], 'manifest');
  if (typeof manifest.sha256 !== 'string' || /^[a-f0-9]{64}$/.exec(manifest.sha256)?.[0] !== manifest.sha256) invalid('malformed SHA-256');
  const {sha256, ...data} = manifest;
  const sealed = sealPracticeCopy(data, catalog);
  if (sealed.sha256 !== sha256) invalid('semantic digest does not match authored content');
  return sealed;
}
export function assertReleasedPracticeCopy(manifest) {
  const registered = releases[`${manifest.contentVersion}/${manifest.copyRevision}`];
  if (!registered) invalid('copy revision has not been registered as an immutable release');
  if (registered !== manifest.sha256) invalid('released copy changed; review and issue a new copyRevision');
}
async function readBounded(file) {
  const raw = await readFile(file);
  if (raw.length > practiceCopyMaxBytes) invalid('source file is too large');
  return JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(raw));
}
export async function checkPracticeCopy({root = defaultRoot} = {}) {
  const catalog = await readBounded(resolve(root, 'content/practice-catalog.json'));
  assertReleasedCatalog(catalog);
  const manifest = validatePracticeCopy(await readBounded(resolve(root, 'content/practice-copy.json')), catalog);
  assertReleasedPracticeCopy(manifest);
  return manifest;
}
async function stdinData() {
  const chunks = []; let size = 0;
  for await (const chunk of process.stdin) {
    size += chunk.length;
    if (size > practiceCopyMaxBytes) invalid('input is too large');
    chunks.push(chunk);
  }
  return JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(Buffer.concat(chunks)));
}
async function main() {
  const args = process.argv.slice(2);
  if (args.length > 1 || (args.length && !['--check', '--write', '--digest'].includes(args[0]))) {
    throw new Error('Usage: node tool/check-practice-copy.mjs [--check|--write|--digest]');
  }
  if (args[0] === '--write' || args[0] === '--digest') {
    const catalog = await readBounded(resolve(defaultRoot, 'content/practice-catalog.json'));
    assertReleasedCatalog(catalog);
    const manifest = sealPracticeCopy(await stdinData(), catalog);
    if (args[0] === '--digest') { process.stdout.write(`${manifest.sha256}\n`); return; }
    assertReleasedPracticeCopy(manifest);
    await writeFile(resolve(defaultRoot, 'content/practice-copy.json'), `${JSON.stringify(manifest, null, 2)}\n`);
  }
  const manifest = await checkPracticeCopy();
  process.stdout.write(`Practice copy ${manifest.contentVersion}/${manifest.copyRevision}: ${manifest.counts.activities} activities verified (${manifest.sha256}).\n`);
}
if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main().catch(error => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
}
