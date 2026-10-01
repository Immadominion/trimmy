import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {buildApp} from '../src/app.js';
import {localizeJourney, localizeMissFeedback, normalizeDecimal} from '../src/workday-localization.js';

const seed = JSON.parse(await readFile(new URL('../../../content/workdays/intern-v1.json', import.meta.url), 'utf8'));
/** One assignment the way the database serves it: no answers, no choice feedback. */
function served(definition: Record<string, any>, state: Record<string, unknown> = {}) {
 const {context: _context, feedback: _feedback, ...rest} = definition;
 return {...rest, evidence: {prompt: definition.evidence.prompt, count: definition.evidence.requiredIds.length},
  decision: {kind: definition.decision.kind, prompt: definition.decision.prompt, hint: definition.decision.hint, unit: definition.decision.unit,
   choices: definition.decision.choices.map((c: Record<string, string>) => ({id: c['id'], label: c['label']}))},
  file: {prompt: definition.file.prompt, count: definition.file.requiredIds.length, parts: definition.file.parts},
  revision: 0, step: 0, answers: {}, draft: '', misses: 0, decisionNote: null, completedAt: null, artifact: null, trims: null, feedback: null, contextNote: null, ...state};
}
const def = (id: string) => seed.assignments.find((a: Record<string, unknown>) => a['id'] === id);

test('workdays read in the requested language by id, and English gets hints that no longer give the answer', () => {
 const twoCompanies = def('two-companies'), followUp = def('the-follow-up'), brief = def('morning-brief');
 const filedArtifact = `${brief.file.parts[0].text}\n${brief.file.parts[1].text}\n\nMy own note.`;
 const journey = {contentVersion: seed.contentVersion, date: '2026-10-05', completedCount: 1, total: 20, schedule: {state: 'tomorrow'},
  upcoming: {id: 'two-companies', ordinal: 2, title: twoCompanies.title, speaker: 'shark', district: twoCompanies.district, art: 'balance', opensAt: '2026-10-06T00:00:00Z'},
  assignments: [
   served(brief, {step: 3, answers: {'0': {ids: ['after', 'before']}, '1': {value: '200'}, '2': {ids: ['fact-1', 'fact-2']}}, draft: 'My own note.',
    completedAt: '2026-10-05T10:00:00Z', artifact: filedArtifact, trims: 20, feedback: brief.feedback}),
   served(twoCompanies, {step: 2, answers: {'0': {ids: ['aster', 'helio']}, '1': {value: 'helio'}}, decisionNote: twoCompanies.decision.choices[1].feedback}),
   served(followUp, {contextNote: followUp.context.responses.ask}),
  ]};
 const es = localizeJourney(journey, 'es') as any;
 const [first, second, third] = es.assignments;
 assert.equal(first.title, 'El informe de la mañana');
 assert.equal(first.rows[1].value, 'US$ 1500 en ventas · US$ 1300 en costos');
 assert.equal(first.feedback.startsWith('Las ventas subieron.'), true);
 assert.equal(first.artifact, 'Las ventas subieron de US$ 1000 a US$ 1500.\nLa ganancia bajó de US$ 400 a US$ 200.\n\nMy own note.', 'the player keeps their own note');
 assert.deepEqual(second.decision.choices.map((c: any) => c.label), ['Aster', 'Helio', 'Valen lo mismo']);
 assert.ok(second.decision.choices.every((c: any) => !('feedback' in c)), 'no feedback appears that the database did not send');
 assert.equal(second.decisionNote, 'Exacto: US$ 100 × 100 000 = US$ 10 millones.');
 assert.equal(third.contextNote, 'Le pediste los costos a Wolf. Ya te mandó el reporte.');
 assert.equal(es.upcoming.title, 'Dos empresas, una decisión'); assert.equal(es.upcoming.opensAt, '2026-10-06T00:00:00Z');
 // Structure, ids, answers and state pass through untouched.
 assert.deepEqual(second.answers, journey.assignments[1]!.answers); assert.equal(second.step, 2); assert.equal(es.schedule.state, 'tomorrow');
 // English: the seed's answer-giving hint is replaced; everything else is the released text.
 const en = localizeJourney(journey, 'en') as any;
 assert.equal(twoCompanies.decision.hint, 'Aster: $50 million. Helio: $10 million.');
 assert.equal(en.assignments[1].decision.hint, 'Multiply each company’s share price by its number of shares, then compare the totals.');
 assert.equal(en.assignments[0].artifact, filedArtifact);
 assert.equal(en.assignments[0].title, brief.title);
 for (const language of ['en', 'es', 'pt', 'fr'] as const) {
  assert.ok(!JSON.stringify(localizeJourney(journey, language)).includes('—'), `${language} has no em dash`);
 }
 // An artifact that is not exactly the released English plus the note is left alone.
 const odd = localizeJourney({assignments: [{...journey.assignments[0], artifact: 'Something else'}]}, 'fr') as any;
 assert.equal(odd.assignments[0].artifact, 'Something else');
 // Unknown assignments pass through.
 assert.deepEqual(localizeJourney({assignments: [{id: 'not-released', title: 'X'}]}, 'pt'), {assignments: [{id: 'not-released', title: 'X'}]});
});

test('missed-choice feedback and decimal commas', () => {
 assert.equal(localizeMissFeedback('two-companies', 'aster', 'Count all the shares, not just the price of one.', 'fr'), 'Compte toutes les actions, pas seulement le prix d’une seule.');
 assert.equal(localizeMissFeedback('two-companies', 'nope', 'fallback', 'fr'), 'fallback');
 assert.equal(localizeMissFeedback('two-companies', 'aster', null, 'fr'), null);
 for (const [input, output] of [['0,2', '0.2'], ['-1,5', '-1.5'], ['0.2', '0.2'], ['200', '200'], ['1,000,5', '1,000,5'], ['aster', 'aster']])
  assert.equal(normalizeDecimal(input!), output);
});

test('the routes take an optional language, refuse others, and pass a decimal comma as a point', async () => {
 const inputs: unknown[] = [];
 const brief = def('morning-brief');
 const app = buildApp({logger: false, workdays: {authenticate: async () => ({userId: 'u'}),
  read: async () => ({assignments: [served(brief)]}),
  save: async (_user, input) => {inputs.push(input); return {assignments: [served(brief)], miss: {code: 'CHECK_DECISION', step: 1, feedback: 'Their share counts are different.'}};}}});
 try {
  assert.equal((await app.inject({url: '/v1/career/workdays?lang=fr'})).json().journey.assignments[0].title, 'Le point du matin');
  assert.equal((await app.inject({url: '/v1/career/workdays'})).json().journey.assignments[0].title, 'The morning brief');
  assert.equal((await app.inject({url: '/v1/career/workdays?lang=de'})).statusCode, 400);
  const miss = await app.inject({method: 'POST', url: '/v1/career/workdays/step?lang=pt', payload: {assignmentId: 'two-companies', revision: 1, step: 1, answer: {value: 'equal'}}});
  assert.equal(miss.statusCode, 400); assert.equal(miss.json().feedback, 'As quantidades de ações são diferentes.');
  await app.inject({method: 'POST', url: '/v1/career/workdays/step', payload: {assignmentId: 'spread', revision: 1, step: 1, answer: {value: '0,20'}}});
  assert.deepEqual((inputs.at(-1) as any).answer, {value: '0.20'});
 } finally { await app.close(); }
});

test('a browser may ask for workdays in its language: the preflight allows ?lang=', async () => {
  const origin = 'https://app.trimmy.example';
  const app = buildApp({logger: false, browserOrigins: [origin]});
  try {
    for (const [url, method] of [['/v1/career/workdays?lang=fr', 'GET'], ['/v1/career/workdays/step?lang=es', 'POST'], ['/v1/career/workdays/draft?lang=pt', 'POST']] as const) {
      const preflight = await app.inject({method: 'OPTIONS', url, headers: {origin, 'access-control-request-method': method, 'access-control-request-headers': 'authorization,content-type'}});
      assert.equal(preflight.statusCode, 204, url);
      assert.equal(preflight.headers['access-control-allow-origin'], origin, url);
    }
    for (const url of ['/v1/career/workdays?lang=de', '/v1/career/workdays?lang=fr&userId=x', '/v1/career/workdays?userId=x']) {
      const preflight = await app.inject({method: 'OPTIONS', url, headers: {origin, 'access-control-request-method': 'GET', 'access-control-request-headers': 'authorization'}});
      assert.equal(preflight.statusCode, 403, `${url} stays refused`);
    }
  } finally {await app.close();}
});
