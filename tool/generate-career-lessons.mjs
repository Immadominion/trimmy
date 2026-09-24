#!/usr/bin/env node
import {createHash} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const sourcePath = resolve(root, 'content/career-lessons-v1.json');
const typescriptPath = resolve(root, 'apps/api/src/career-lessons-catalog.generated.ts');
const migrationPath = resolve(root, 'infra/migrations/0026_career_lessons.sql');
export const START = '-- BEGIN GENERATED CAREER LESSON CATALOG';
export const END = '-- END GENERATED CAREER LESSON CATALOG';
const releases = Object.freeze({
  '2026-09-20.1': 'c4017578fdb9e9a7768ffc52c1a2fb67a7ad0bbf3316e666beff438b8df03895',
});

function invalid(message) { throw new Error(`Invalid Career lesson catalog: ${message}`); }
function record(value, keys, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      ![Object.prototype, null].includes(Object.getPrototypeOf(value))) invalid(`${label} must be an object`);
  const actual = Reflect.ownKeys(value);
  if (actual.length !== keys.length || actual.some(key => !keys.includes(key))) invalid(`${label} fields differ`);
  for (const key of keys) {
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value')) invalid(`${label} must contain plain data`);
  }
  return value;
}
function array(value, minimum, maximum, label) {
  if (!Array.isArray(value) || value.length < minimum || value.length > maximum ||
      Reflect.ownKeys(value).length !== value.length + 1) invalid(`${label} length or shape`);
  return value;
}
function identifier(value, label) {
  if (typeof value !== 'string' || value.length > 80 || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(value)) {
    invalid(`${label} is invalid`);
  }
  return value;
}
function copy(value, minimum, maximum, label) {
  if (typeof value !== 'string' || value.trim() !== value || [...value].length < minimum ||
      [...value].length > maximum || /[\u0000-\u001f\u007f\u2013\u2014\u2028\u2029]/u.test(value)) {
    invalid(`${label} is invalid`);
  }
  return value;
}
function integer(value, minimum, maximum, label) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) invalid(`${label} is invalid`);
  return value;
}

export function validateCareerLessons(input) {
  const source = record(input, ['schemaVersion', 'contentVersion', 'lessons'], 'catalog');
  if (source.schemaVersion !== 1 || typeof source.contentVersion !== 'string' ||
      !/^\d{4}-\d{2}-\d{2}\.[1-9]\d*$/.test(source.contentVersion)) invalid('version is invalid');
  const lessons = array(source.lessons, 5, 5, 'lessons');
  const lessonIds = new Set(); const stepIds = new Set();
  lessons.forEach((candidate, lessonIndex) => {
    const lesson = record(candidate, [
      'id', 'order', 'title', 'summary', 'salIntro', 'salComplete', 'rewardTrims', 'steps',
    ], 'lesson');
    identifier(lesson.id, 'lesson id');
    if (lessonIds.has(lesson.id)) invalid('duplicate lesson id');
    lessonIds.add(lesson.id);
    if (integer(lesson.order, 1, 5, 'lesson order') !== lessonIndex + 1 || lesson.rewardTrims !== 10) {
      invalid('lesson order or reward differs');
    }
    copy(lesson.title, 1, 60, 'lesson title');
    copy(lesson.summary, 1, 140, 'lesson summary');
    copy(lesson.salIntro, 1, 100, 'Sal intro');
    copy(lesson.salComplete, 1, 100, 'Sal completion');
    array(lesson.steps, 4, 6, 'lesson steps').forEach((stepCandidate, stepIndex) => {
      const step = record(stepCandidate, ['id', 'order', 'prompt', 'choices', 'correctChoiceId',
        'correctFeedback', 'incorrectFeedback'], 'step');
      identifier(step.id, 'step id');
      if (stepIds.has(step.id)) invalid('duplicate step id');
      stepIds.add(step.id);
      if (integer(step.order, 1, 6, 'step order') !== stepIndex + 1) invalid('step order differs');
      copy(step.prompt, 1, 180, 'step prompt');
      copy(step.correctFeedback, 1, 220, 'correct feedback');
      copy(step.incorrectFeedback, 1, 220, 'incorrect feedback');
      const choices = array(step.choices, 2, 4, 'choices');
      const choiceIds = new Set();
      choices.forEach((choiceCandidate, choiceIndex) => {
        const choice = record(choiceCandidate, ['id', 'label'], 'choice');
        identifier(choice.id, 'choice id');
        if (choiceIds.has(choice.id)) invalid('duplicate choice id');
        choiceIds.add(choice.id);
        copy(choice.label, 1, 100, `choice ${choiceIndex + 1}`);
      });
      if (!choiceIds.has(step.correctChoiceId)) invalid('correct choice is missing');
    });
  });
  return source;
}

export function careerLessonsDigest(catalog) {
  return createHash('sha256').update(JSON.stringify(validateCareerLessons(catalog))).digest('hex');
}
function sql(value) { return `'${value.replaceAll("'", "''")}'`; }
export function renderSeed(input) {
  const catalog = validateCareerLessons(input);
  const digest = careerLessonsDigest(catalog);
  const lines = [START,
    `INSERT INTO trimmy.career_lesson_releases(content_version, source_digest, status, published_at)`,
    `VALUES (${sql(catalog.contentVersion)}, ${sql(digest)}, 'published', '2026-09-20T00:00:00.000Z');`, '',
  ];
  for (const lesson of catalog.lessons) {
    lines.push('INSERT INTO trimmy.career_lesson_definitions(',
      '  content_version, id, lesson_order, title, summary, sal_intro, sal_complete,',
      '  estimated_interactions, reward_trims)',
      `VALUES (${sql(catalog.contentVersion)}, ${sql(lesson.id)}, ${lesson.order}, ${sql(lesson.title)},`,
      `  ${sql(lesson.summary)}, ${sql(lesson.salIntro)}, ${sql(lesson.salComplete)},`,
      `  ${lesson.steps.length}, ${lesson.rewardTrims});`, '');
    for (const step of lesson.steps) {
      lines.push('INSERT INTO trimmy.career_lesson_steps(',
        '  content_version, lesson_id, id, step_order, prompt, correct_choice_id,',
        '  correct_feedback, incorrect_feedback)',
        `VALUES (${sql(catalog.contentVersion)}, ${sql(lesson.id)}, ${sql(step.id)}, ${step.order},`,
        `  ${sql(step.prompt)}, ${sql(step.correctChoiceId)},`,
        `  ${sql(step.correctFeedback)}, ${sql(step.incorrectFeedback)});`);
      for (let index = 0; index < step.choices.length; index++) {
        const choice = step.choices[index];
        lines.push('INSERT INTO trimmy.career_lesson_choices(',
          '  content_version, lesson_id, step_id, id, choice_order, label)',
          `VALUES (${sql(catalog.contentVersion)}, ${sql(lesson.id)}, ${sql(step.id)},`,
          `  ${sql(choice.id)}, ${index + 1}, ${sql(choice.label)});`);
      }
      lines.push('');
    }
  }
  lines.push(END);
  return lines.join('\n');
}
export function renderTypescript(input) {
  const catalog = validateCareerLessons(input);
  return `// GENERATED by tool/generate-career-lessons.mjs. Edit content/career-lessons-v1.json.\n` +
    `// Source SHA-256: ${careerLessonsDigest(catalog)}\n` +
    `export const careerLessonsCatalog = ${JSON.stringify(catalog, null, 2)} as const;\n`;
}

export async function generateCareerLessons({check = false} = {}) {
  const sourceText = await readFile(sourcePath, 'utf8');
  if (Buffer.byteLength(sourceText) > 64_000) invalid('source is too large');
  const catalog = validateCareerLessons(JSON.parse(sourceText));
  const digest = careerLessonsDigest(catalog);
  if (releases[catalog.contentVersion] !== digest) invalid('released content changed or version is unregistered');
  const expectedTypeScript = renderTypescript(catalog);
  const migration = await readFile(migrationPath, 'utf8');
  const start = migration.indexOf(START); const end = migration.indexOf(END);
  if (start < 0 || end < start || migration.indexOf(START, start + 1) >= 0 || migration.indexOf(END, end + 1) >= 0) {
    invalid('migration seed markers are missing or duplicated');
  }
  const expectedSeed = renderSeed(catalog);
  const actualSeed = migration.slice(start, end + END.length);
  if (check) {
    const actualTypeScript = await readFile(typescriptPath, 'utf8').catch(() => '');
    if (actualTypeScript !== expectedTypeScript || actualSeed !== expectedSeed) {
      throw new Error('Career lesson generated content drift. Run node tool/generate-career-lessons.mjs.');
    }
  } else {
    await writeFile(typescriptPath, expectedTypeScript);
    await writeFile(migration, `${migration.slice(0, start)}${expectedSeed}${migration.slice(end + END.length)}`);
  }
  return catalog;
}

async function main() {
  const args = process.argv.slice(2);
  if (args.some(argument => argument !== '--check')) {
    throw new Error('Usage: node tool/generate-career-lessons.mjs [--check]');
  }
  const catalog = await generateCareerLessons({check: args.includes('--check')});
  process.stdout.write(`Career lessons ${catalog.contentVersion}: ${catalog.lessons.length} lessons verified.\n`);
}
if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main().catch(error => {process.stderr.write(`${error.message}\n`); process.exitCode = 1;});
}
