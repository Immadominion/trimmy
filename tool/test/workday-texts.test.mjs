import assert from 'node:assert/strict';
import {cp, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {resolve} from 'node:path';
import {test} from 'node:test';
import {buildWorkdayTexts, numbersOf, render, OUTPUT} from '../generate-workday-texts.mjs';

const root = resolve(new URL('../..', import.meta.url).pathname);

test('the released translations build, match the committed module and keep every figure', async () => {
  const built = await buildWorkdayTexts(root);
  assert.deepEqual(Object.keys(built.texts), ['en', 'es', 'pt', 'fr']);
  assert.equal(Object.keys(built.texts.fr).length, 20);
  assert.equal(render(built), await readFile(resolve(root, OUTPUT), 'utf8'));
  assert.deepEqual(numbersOf('$1,500.50 and 10%'), ['10', '150050']);
  assert.deepEqual(numbersOf('1 500,50 $ et 10 %'), ['10', '150050']);
  assert.deepEqual(numbersOf('US$ 1.500,50 y 10 %'), ['10', '150050']);
});

async function withChange(locale, change, expected) {
  const dir = await mkdtemp(resolve(tmpdir(), 'workday-texts-'));
  try {
    await cp(resolve(root, 'content/workdays'), resolve(dir, 'content/workdays'), {recursive: true});
    const path = resolve(dir, `content/workdays/i18n/intern-v1.${locale}.json`);
    const file = JSON.parse(await readFile(path, 'utf8'));
    change(file.assignments);
    await writeFile(path, JSON.stringify(file));
    await assert.rejects(buildWorkdayTexts(dir), expected);
  } finally { await rm(dir, {recursive: true, force: true}); }
}

test('a wrong figure, a missing or unknown field, a new id or a dash is refused', async () => {
  await withChange('es', a => { a['morning-brief'].file.parts['fact-2'] = 'La ganancia bajó de US$ 400 a US$ 300.'; }, /numbers/);
  await withChange('pt', a => { delete a['spread'].decision.hint; }, /spread\.decision\.hint is missing/);
  await withChange('fr', a => { a['spread'].decision.choices = {extra: {label: 'x', feedback: 'y'}}; }, /not in the released workday/);
  await withChange('fr', a => { a['a-new-day'] = {title: 'Nouveau'}; }, /not a released workday/);
  await withChange('es', a => { a['spread'].title = 'Dos lados — una cotización'; }, /dash/);
  await withChange('en', a => { a['spread'] = {decision: {hint: ' padded '}}; }, /trimmed/);
});
