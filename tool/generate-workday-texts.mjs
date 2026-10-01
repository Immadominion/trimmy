#!/usr/bin/env node
/**
 * Workday text per language.
 *
 * The released workdays (content/workdays/intern-v1.json, seeded by migration
 * 0030) stay the single source of structure, ids and answers. Each language
 * file in content/workdays/i18n/ overlays text only: English edits (hints that
 * no longer give the answer away, no em dashes) and complete Spanish (Latin
 * America), Brazilian Portuguese and French text.
 *
 *   node tool/generate-workday-texts.mjs          writes apps/api/src/workday-texts.generated.ts
 *   node tool/generate-workday-texts.mjs --check  fails if that file is stale or a translation is wrong
 *
 * Checks: every id and field exists in the seed (no new ids, no answers),
 * Spanish, Portuguese and French cover every field, no text is empty or has a
 * dash used as punctuation, and every translated field carries exactly the
 * same numbers as the English (separators and currency placement may differ,
 * the digits may not), so a figure cannot be mistranslated.
 */
import {readFile, writeFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

const defaultRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const LOCALES = Object.freeze(['en', 'es', 'pt', 'fr']);
export const OUTPUT = 'apps/api/src/workday-texts.generated.ts';
const SEED = 'content/workdays/intern-v1.json';

function fail(message) { throw new Error(`Workday text: ${message}`); }

/** The translatable text of one seeded assignment, keyed by stable ids. */
export function textOf(assignment) {
  const tree = {
    title: assignment.title, brief: assignment.brief, district: assignment.district,
    sourceTitle: assignment.sourceTitle, sourceLabel: assignment.sourceLabel, feedback: assignment.feedback,
    rows: Object.fromEntries(assignment.rows.map(row => [row.id, {label: row.label, value: row.value, detail: row.detail}])),
    evidence: {prompt: assignment.evidence.prompt},
    decision: {prompt: assignment.decision.prompt, hint: assignment.decision.hint,
      choices: Object.fromEntries(assignment.decision.choices.map(choice => [choice.id, {label: choice.label, feedback: choice.feedback}]))},
    file: {prompt: assignment.file.prompt, parts: Object.fromEntries(assignment.file.parts.map(part => [part.id, part.text]))},
  };
  if (assignment.context) tree.context = {...assignment.context.responses};
  return tree;
}

/** Overlays `edit` on `base`. Every key in `edit` must exist in `base`. */
export function overlay(base, edit, path, complete) {
  if (typeof base === 'string') {
    if (edit === undefined) { if (complete) fail(`${path} is missing`); return base; }
    if (typeof edit !== 'string' || !edit.trim() || edit !== edit.trim()) fail(`${path} must be trimmed, non-empty text`);
    if (/[—–]|\s-\s/u.test(edit)) fail(`${path} uses a dash as punctuation`);
    if (/[\u0000-\u001f\u007f]/u.test(edit)) fail(`${path} has a control character`);
    return edit;
  }
  if (edit === undefined) { if (complete) fail(`${path} is missing`); return structuredClone(base); }
  if (!edit || typeof edit !== 'object' || Array.isArray(edit)) fail(`${path} must be an object`);
  for (const key of Object.keys(edit)) if (!Object.hasOwn(base, key)) fail(`${path}.${key} is not in the released workday`);
  return Object.fromEntries(Object.keys(base).map(key => [key, overlay(base[key], edit[key], `${path}.${key}`, complete)]));
}

/** Every number in a text, as its digits: "$1,500.50" and "1.500,50 US$" are both "150050". */
export function numbersOf(text) {
  return [...text.matchAll(/\d(?:[\d.,   ]*\d)?/gu)].map(match => match[0].replace(/[^\d]/g, '')).sort();
}
export function sameNumbers(english, translated, path) {
  if (typeof english === 'string') {
    const a = numbersOf(english), b = numbersOf(translated);
    if (a.join(' ') !== b.join(' ')) fail(`${path} has numbers ${JSON.stringify(b)}; the English has ${JSON.stringify(a)}`);
    return;
  }
  for (const key of Object.keys(english)) sameNumbers(english[key], translated[key], `${path}.${key}`);
}

export async function buildWorkdayTexts(root = defaultRoot) {
  const seed = JSON.parse(await readFile(resolve(root, SEED), 'utf8'));
  const base = Object.fromEntries(seed.assignments.map(assignment => [assignment.id, textOf(assignment)]));
  const texts = {};
  for (const locale of LOCALES) {
    const file = JSON.parse(await readFile(resolve(root, `content/workdays/i18n/intern-v1.${locale}.json`), 'utf8'));
    if (file.schemaVersion !== 1 || file.locale !== locale || file.contentVersion !== seed.contentVersion) fail(`${locale}: header does not match the seed`);
    const known = Object.keys(file.assignments ?? {});
    for (const id of known) if (!Object.hasOwn(base, id)) fail(`${locale}: ${id} is not a released workday`);
    // English edits are partial and apply over the seed; the others overlay the edited English and must be complete.
    const from = locale === 'en' ? base : texts.en;
    texts[locale] = Object.fromEntries(Object.keys(base).map(id =>
      [id, overlay(from[id], file.assignments?.[id], `${locale}.${id}`, locale !== 'en')]));
    if (locale !== 'en') for (const id of Object.keys(base)) sameNumbers(texts.en[id], texts[locale][id], `${locale}.${id}`);
  }
  return {contentVersion: seed.contentVersion, texts};
}

export function render({contentVersion, texts}) {
  return `// Generated by tool/generate-workday-texts.mjs from content/workdays/. Do not edit.
// Text only: ids, structure and answers come from the released workdays in the database.
export type WorkdayLanguage = ${LOCALES.map(locale => `'${locale}'`).join(' | ')};
export interface WorkdayText {
  readonly title: string; readonly brief: string; readonly district: string; readonly sourceTitle: string;
  readonly sourceLabel: string; readonly feedback: string;
  readonly rows: Readonly<Record<string, {readonly label: string; readonly value: string; readonly detail: string}>>;
  readonly evidence: {readonly prompt: string};
  readonly decision: {readonly prompt: string; readonly hint: string;
    readonly choices: Readonly<Record<string, {readonly label: string; readonly feedback: string}>>};
  readonly file: {readonly prompt: string; readonly parts: Readonly<Record<string, string>>};
  readonly context?: Readonly<Record<string, string>>;
}
export const WORKDAY_TEXT_CONTENT_VERSION = ${JSON.stringify(contentVersion)};
export const WORKDAY_TEXTS: Readonly<Record<WorkdayLanguage, Readonly<Record<string, WorkdayText>>>> = ${JSON.stringify(texts, null, 1)};
`;
}

async function main() {
  const check = process.argv.includes('--check');
  const built = render(await buildWorkdayTexts());
  const path = resolve(defaultRoot, OUTPUT);
  if (check) {
    const current = await readFile(path, 'utf8').catch(() => '');
    if (current !== built) fail(`${OUTPUT} is stale; run node tool/generate-workday-texts.mjs`);
    process.stdout.write(`Workday text checked: ${LOCALES.join(', ')}.\n`);
  } else {
    await writeFile(path, built);
    process.stdout.write(`Wrote ${OUTPUT}.\n`);
  }
}
if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main().catch(error => { process.stderr.write(`${error.message}\n`); process.exitCode = 1; });
}
