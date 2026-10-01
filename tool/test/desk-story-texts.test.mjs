import assert from 'node:assert/strict';
import {cp, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {resolve} from 'node:path';
import {test} from 'node:test';
import {buildDeskStoryTexts, renderDeskStories, DESK_OUTPUT} from '../generate-desk-story-texts.mjs';

const root = resolve(new URL('../..', import.meta.url).pathname);

test('the desk story translations build, match the committed module and cover all seven stories', async () => {
  const built = await buildDeskStoryTexts(root);
  assert.deepEqual(Object.keys(built.texts), ['en', 'es', 'pt', 'fr']);
  for (const locale of ['es', 'pt', 'fr']) assert.equal(Object.keys(built.texts[locale]).length, 7, locale);
  assert.equal(renderDeskStories(built), await readFile(resolve(root, DESK_OUTPUT), 'utf8'));
});

async function withChange(locale, change, expected) {
  const dir = await mkdtemp(resolve(tmpdir(), 'desk-texts-'));
  try {
    await cp(resolve(root, 'content'), resolve(dir, 'content'), {recursive: true});
    const path = resolve(dir, `content/desk-stories/i18n/desk-stories-v1.${locale}.json`);
    const file = JSON.parse(await readFile(path, 'utf8'));
    change(file.stories);
    await writeFile(path, JSON.stringify(file));
    await assert.rejects(buildDeskStoryTexts(dir), expected);
  } finally { await rm(dir, {recursive: true, force: true}); }
}

test('a wrong figure, a missing field, an unknown story or choice, or a dash is refused', async () => {
  await withChange('es', s => { s['a-red-morning'].body = s['a-red-morning'].body.replace('6%', '60%'); }, /numbers/);
  await withChange('pt', s => { delete s['the-group-chat'].choices.ask.takeaway; }, /takeaway is missing/);
  await withChange('fr', s => { s['the-group-chat'].choices.extra = {label: 'x', outcome: 'y', takeaway: 'z'}; }, /not in the released desk story/);
  await withChange('fr', s => { s['a-new-story'] = {title: 'Nouveau'}; }, /not a released desk story/);
  await withChange('es', s => { s['the-weekend-note'].title = 'Un escritorio — más tranquilo.'; }, /dash/);
});
