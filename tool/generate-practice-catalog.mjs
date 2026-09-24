#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const defaultRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const catalogOutputPaths = Object.freeze({
  typescript: 'packages/domain/src/practice-catalog.generated.ts',
  dart: 'apps/mobile/lib/design_study/practice_catalog.generated.dart',
});

// Append a new release when metadata changes. Never silently republish an
// existing contentVersion. This digest includes all validated metadata; JSON
// whitespace and object-key order are irrelevant. It is a review lock, not a
// remote-content signature or a substitute for a signed release process.
const releases = Object.freeze({
  '2026-09-14.2': '7400fbfa729b68207e5b3fd09e7d98536a1756a474e550bdaa58c82d85518c41',
  '2026-09-14.3': '5e3996212ad4f4f90ca187e6bd7eaa01844388c3fd4e3b3f5a12f93021559597',
  '2026-09-15.1': '1de12d831bf1611078968028c55cb03c66415758f0ad1a59acf5423499a1f88d',
});

function invalid(message) { throw new Error(`Invalid practice catalog: ${message}`); }
function object(value, keys, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      ![Object.prototype, null].includes(Object.getPrototypeOf(value))) invalid(`${label} must be an object`);
  const actual = Reflect.ownKeys(value);
  if (actual.length !== keys.length || actual.some(key => !keys.includes(key))) invalid(`${label} fields differ from schema`);
  for (const key of keys) {
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) invalid(`${label} fields must be plain data`);
  }
  return value;
}
function array(value, min, max, label) {
  if (!Array.isArray(value) || value.length < min || value.length > max ||
      Reflect.ownKeys(value).length !== value.length + 1) invalid(`${label} length or shape`);
  for (let index = 0; index < value.length; index++) {
    const descriptor = Object.getOwnPropertyDescriptor(value, String(index));
    if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) invalid(`${label} must be a dense data array`);
  }
  return value;
}
function integer(value, min, max, label) {
  if (!Number.isSafeInteger(value) || value < min || value > max) invalid(`${label} outside supported bounds`);
  return value;
}
function title(value) {
  if (typeof value !== 'string' || !value || value.length > 80 || value.trim() !== value || /[\u0000-\u001f\u007f\u2028\u2029]/.test(value)) invalid('invalid title');
  return value;
}
function identifier(value, compound = false) {
  const pattern = compound ? /^[a-z][a-z0-9-]*(?:\+[a-z][a-z0-9-]*)*$/ : /^[a-z][a-z0-9-]*$/;
  if (typeof value !== 'string' || value.length > 256 || pattern.exec(value)?.[0] !== value) invalid('invalid identifier');
  return value;
}

export function validateCatalog(input) {
  const source = object(input, ['schemaVersion', 'contentVersion', 'payloadVersion', 'floors', 'activities'], 'catalog');
  if (source.schemaVersion !== 2) invalid('unsupported schemaVersion');
  const version = source.contentVersion;
  if (typeof version !== 'string' || /^\d{4}-\d{2}-\d{2}\.[1-9]\d{0,5}$/.exec(version)?.[0] !== version) invalid('invalid contentVersion');
  const date = version.split('.')[0];
  if (!Number.isFinite(Date.parse(`${date}T00:00:00Z`)) || new Date(`${date}T00:00:00Z`).toISOString().slice(0, 10) !== date) invalid('invalid contentVersion date');
  const payloadVersion = integer(source.payloadVersion, 1, 255, 'payloadVersion');
  const floors = array(source.floors, 1, 16, 'floors').map((inputFloor, index) => {
    const floor = object(inputFloor, ['number', 'title'], 'floor');
    if (floor.number !== index + 1) invalid('floors must be contiguous, ordered and unique');
    return Object.freeze({number: floor.number, title: title(floor.title)});
  });
  const seen = new Set(); let previous = null, previousFloor = 1, previousVersion = 1;
  const activities = array(source.activities, 1, 128, 'activities').map(inputActivity => {
    const activity = object(inputActivity, ['id', 'floor', 'title', 'correctChoiceId', 'acceptedChoiceIds', 'choiceIds', 'introducedIn', 'prerequisiteId'], 'activity');
    const id = identifier(activity.id);
    if (seen.has(id)) invalid('duplicate activity ID');
    seen.add(id);
    const floor = integer(activity.floor, 1, floors.length, 'activity floor');
    if (floor < previousFloor || floor > previousFloor + 1 || (previous === null && floor !== 1)) invalid('activities must fill floors in order');
    const introducedIn = integer(activity.introducedIn, 1, payloadVersion, 'introducedIn');
    if (introducedIn < previousVersion) invalid('introducedIn must not go backwards');
    if (activity.prerequisiteId !== previous) invalid('each prerequisite must be the previous activity, first null');
    const choiceIds = array(activity.choiceIds, 2, 32, 'choiceIds').map(value => identifier(value, true));
    if (new Set(choiceIds).size !== choiceIds.length) invalid('duplicate choice ID');
    const correctChoiceId = identifier(activity.correctChoiceId, true);
    if (!choiceIds.includes(correctChoiceId)) invalid('correct choice is missing');
    const acceptedChoiceIds = array(activity.acceptedChoiceIds, 1, choiceIds.length, 'acceptedChoiceIds')
      .map(value => identifier(value, true));
    if (new Set(acceptedChoiceIds).size !== acceptedChoiceIds.length ||
        acceptedChoiceIds.some(value => !choiceIds.includes(value)) ||
        !acceptedChoiceIds.includes(correctChoiceId)) invalid('accepted choices must be unique registered choices including the correction target');
    previous = id; previousFloor = floor; previousVersion = introducedIn;
    return Object.freeze({id, floor, title: title(activity.title), correctChoiceId,
      acceptedChoiceIds: Object.freeze(acceptedChoiceIds), choiceIds: Object.freeze(choiceIds),
      introducedIn, prerequisiteId: activity.prerequisiteId});
  });
  if (previousFloor !== floors.length) invalid('every floor must contain an activity');
  if (previousVersion !== payloadVersion) invalid('payloadVersion must equal the newest introduction');
  return Object.freeze({schemaVersion: 2, contentVersion: version, payloadVersion,
    floors: Object.freeze(floors), activities: Object.freeze(activities)});
}

export function catalogDigest(catalog) {
  return createHash('sha256').update(JSON.stringify(validateCatalog(catalog))).digest('hex');
}
export function assertReleasedCatalog(catalog) {
  const expected = releases[catalog.contentVersion];
  if (!expected) invalid('contentVersion is not registered as an immutable release');
  if (catalogDigest(catalog) !== expected) invalid('released metadata changed; issue a new contentVersion and release digest');
}

const quote = value => JSON.stringify(value);
const dartQuote = value => `'${value.replaceAll('\\', '\\\\').replaceAll("'", "\\'").replaceAll('$', '\\$')}'`;

export function renderTypeScript(input) {
  const catalog = validateCatalog(input);
  const lines = [
    '// GENERATED by tool/generate-practice-catalog.mjs. Edit the versioned source catalog.',
    `// Source SHA-256: ${catalogDigest(catalog)}`,
    `export const practiceCatalogSchemaVersion = ${catalog.schemaVersion} as const;`,
    `export const practiceCatalogContentVersion = ${quote(catalog.contentVersion)} as const;`,
    `export const practiceCatalogPayloadVersion = ${catalog.payloadVersion} as const;`,
    'export const practiceCatalogFloors = Object.freeze({',
    ...catalog.floors.map(floor => `  ${floor.number}: ${quote(floor.title)},`),
    '} as const);',
    'export const practiceCatalogActivityIds = Object.freeze([',
    ...catalog.activities.map(activity => `  ${quote(activity.id)},`),
    '] as const);',
    'export type PracticeCatalogActivityId = typeof practiceCatalogActivityIds[number];',
    'export const practiceCatalogById = Object.freeze({',
  ];
  for (const activity of catalog.activities) {
    lines.push(`  ${quote(activity.id)}: Object.freeze({`,
      `    id: ${quote(activity.id)},`, `    floor: ${activity.floor},`, `    title: ${quote(activity.title)},`,
      `    correctChoiceId: ${quote(activity.correctChoiceId)},`, '    choiceIds: Object.freeze([',
      ...activity.choiceIds.map(choice => `      ${quote(choice)},`), '    ] as const),',
      '    acceptedChoiceIds: Object.freeze([',
      ...activity.acceptedChoiceIds.map(choice => `      ${quote(choice)},`), '    ] as const),',
      `    introducedIn: ${activity.introducedIn},`, `    prerequisiteId: ${quote(activity.prerequisiteId)},`,
      '  } as const),');
  }
  lines.push('} as const);', 'export type PracticeCatalogEntry = typeof practiceCatalogById[PracticeCatalogActivityId];', '');
  return lines.join('\n');
}

export function renderDart(input) {
  const catalog = validateCatalog(input);
  const lines = [
    '// GENERATED by tool/generate-practice-catalog.mjs. Edit the versioned source catalog.',
    `// Source SHA-256: ${catalogDigest(catalog)}`,
    '',
    `const practiceCatalogSchemaVersion = ${catalog.schemaVersion};`,
    `const practiceCatalogContentVersion = ${dartQuote(catalog.contentVersion)};`,
    `const practiceCatalogPayloadVersion = ${catalog.payloadVersion};`,
    '',
    'class PracticeCatalogEntry {',
    '  const PracticeCatalogEntry({',
    '    required this.id,', '    required this.floor,', '    required this.title,',
    '    required this.correctChoiceId,', '    required this.choiceIds,',
    '    required this.acceptedChoiceIds,',
    '    required this.introducedIn,', '    required this.prerequisiteId,', '  });', '',
    '  final String id;', '  final int floor;', '  final String title;',
    '  final String correctChoiceId;', '  final List<String> choiceIds;',
    '  final List<String> acceptedChoiceIds;',
    '  final int introducedIn;', '  final String? prerequisiteId;', '}', '',
    'const practiceCatalogFloors = <int, String>{',
    ...catalog.floors.map(floor => `  ${floor.number}: ${dartQuote(floor.title)},`), '};', '',
    'const practiceCatalogActivityIds = <String>[',
    ...catalog.activities.map(activity => `  ${dartQuote(activity.id)},`), '];', '',
    'const practiceCatalogById = <String, PracticeCatalogEntry>{',
  ];
  for (const activity of catalog.activities) {
    const compactChoices = `    choiceIds: [${activity.choiceIds.map(dartQuote).join(', ')}],`;
    const choices = compactChoices.length <= 80 ? [compactChoices]
      : ['    choiceIds: [', ...activity.choiceIds.map(choice => `      ${dartQuote(choice)},`), '    ],'];
    lines.push(`  ${dartQuote(activity.id)}: PracticeCatalogEntry(`,
      `    id: ${dartQuote(activity.id)},`, `    floor: ${activity.floor},`, `    title: ${dartQuote(activity.title)},`,
      `    correctChoiceId: ${dartQuote(activity.correctChoiceId)},`, ...choices,
      `    acceptedChoiceIds: [${activity.acceptedChoiceIds.map(dartQuote).join(', ')}],`,
      `    introducedIn: ${activity.introducedIn},`,
      `    prerequisiteId: ${activity.prerequisiteId === null ? 'null' : dartQuote(activity.prerequisiteId)},`, '  ),');
  }
  lines.push('};', '');
  return lines.join('\n');
}

export async function generateCatalog({root = defaultRoot, check = false} = {}) {
  const source = await readFile(resolve(root, 'content/practice-catalog.json'), 'utf8');
  if (Buffer.byteLength(source) > 128_000) invalid('source file is too large');
  const catalog = validateCatalog(JSON.parse(source));
  assertReleasedCatalog(catalog);
  const outputs = [[catalogOutputPaths.typescript, renderTypeScript(catalog)],
    [catalogOutputPaths.dart, renderDart(catalog)]];
  const drift = [];
  for (const [relativePath, expected] of outputs) {
    const file = resolve(root, relativePath);
    if (check) {
      let actual;
      try {actual = await readFile(file, 'utf8');}
      catch (error) {if (error.code !== 'ENOENT') throw error;}
      if (actual !== expected) drift.push(relativePath);
    } else {
      await mkdir(dirname(file), {recursive: true});
      await writeFile(file, expected);
    }
  }
  if (drift.length) throw new Error(`Practice catalog output drift: ${drift.join(', ')}. Run node tool/generate-practice-catalog.mjs.`);
  return catalog;
}

async function main() {
  const args = process.argv.slice(2);
  let root = defaultRoot, check = false;
  for (let index = 0; index < args.length; index++) {
    if (args[index] === '--check') check = true;
    else if (args[index] === '--root' && args[index + 1]) root = resolve(args[++index]);
    else throw new Error('Usage: node tool/generate-practice-catalog.mjs [--check] [--root path]');
  }
  const catalog = await generateCatalog({root, check});
  process.stdout.write(`Practice catalog ${catalog.contentVersion}: ${catalog.activities.length} activities ${check ? 'verified' : 'generated'}.\n`);
}
if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main().catch(error => {process.stderr.write(`${error.message}\n`); process.exitCode = 1;});
}
