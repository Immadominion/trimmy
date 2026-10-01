import assert from 'node:assert/strict';
import test from 'node:test';
import {loadCatalog, setLocale} from '../src/i18n/runtime.js';
import {parseMessage, type MessagePart} from '../src/i18n/icu.js';
import {en} from '../src/i18n/messages/en/index.js';
import type {Locale} from '../src/i18n/locales.js';
import {JourneyStore} from '../src/product/journey-store.js';
import {findLeaks} from './support/i18n-leaks.js';
import {MemoryStorage, harness, type Harness} from './support/product-harness.js';

const AREAS = ['career.', 'market.', 'profile.', 'common.', 'shell.'];

function runs(parts: readonly MessagePart[], into: string[] = []): string[] {
  for (const part of parts) {
    if (part.kind === 'text') into.push(...part.text.replace(/<\/?[a-z]+\s*\/?>/gu, '\n').split('\n'));
    else if (part.kind === 'plural' || part.kind === 'select') for (const option of part.options.values()) runs(option, into);
  }
  return into;
}
/** The English of Market, Career and Profile (and the shell around them) that must not show in another language. */
async function areaFragments(locale: Exclude<Locale, 'en'>): Promise<Map<string, string>> {
  const catalog = await loadCatalog(locale);
  const fragments = new Map<string, string>();
  for (const [key, source] of Object.entries(en)) {
    if (!AREAS.some(area => key.startsWith(area))) continue;
    const translated = catalog[key as keyof typeof en];
    if (translated === source) continue;
    for (const run of runs(parseMessage(source))) {
      const text = run.trim().replace(/^[^\p{L}]+|[^\p{L}]+$/gu, '');
      if (text.split(/\s+/u).length < 2 || text.length < 8 || translated.includes(text)) continue;
      fragments.set(text, key);
    }
  }
  assert.ok(fragments.size > 300, 'the areas have English to look for');
  return fragments;
}
function chosenGuest() {const storage = new MemoryStorage(); new JourneyStore(storage, '/api').chooseGuest(); return storage;}
function assertNoLeaks(h: Harness, fragments: ReadonlyMap<string, string>, where: string, allow: readonly string[] = []) {
  const report = findLeaks(h.dom.window.document, fragments, allow);
  assert.deepEqual(report.fragments, [], `${where}: no English sentence`);
  assert.deepEqual(report.words, [], `${where}: no untranslated English words`);
}

/** Company and fixture names the server sends; they stay as they are in every language. */
const FIXTURE = ['Apple', 'Tesla', 'AAPLx', 'TSLAx', 'AAPL', 'TSLA'];
/** What the test server says about the company itself (provider text, not Trimmy's copy). */
const COMPANY_FIXTURE: string[] = [];

const TABS = {
  'fr': {market: 'Marché', career: 'Carrière', profile: 'Profil', settings: 'Réglages', marketTitle: /Marché/, rookie: 'Recrue', openApple: 'Ouvrir Apple'},
  'es-419': {market: 'Mercado', career: 'Carrera', profile: 'Perfil', settings: 'Configuración', marketTitle: /Mercado/, rookie: 'Novato', openApple: 'Abrir Apple'},
  'pt-BR': {market: 'Mercado', career: 'Carreira', profile: 'Perfil', settings: 'Configurações', marketTitle: /Mercado/, rookie: 'Novato', openApple: 'Abrir Apple'},
} as const;

for (const [locale, tab] of Object.entries(TABS) as [Exclude<Locale, 'en'>, (typeof TABS)[keyof typeof TABS]][]) {
  test(`Market, Career, Profile and Settings read in ${locale} with no English left`, async () => {
    await setLocale(locale);
    const fragments = await areaFragments(locale);
    const h = await harness({checkpoint: 'app', savedGuest: true, storage: chosenGuest()});
    try {
      await h.app();
      await h.click(tab.market); await h.flush(60);
      assert.match(h.text(), tab.marketTitle);
      assertNoLeaks(h, fragments, `${locale} Market`, FIXTURE);
      await h.click(tab.openApple); await h.flush(80);
      assert.ok(h.dom.window.document.querySelector('.trade-mode'), 'the paper order panel is on the company page');
      assertNoLeaks(h, fragments, `${locale} company page`, [...FIXTURE, ...COMPANY_FIXTURE]);
      await h.click(tab.market); await h.flush(60);
      await h.click(tab.career); await h.flush(60);
      assertNoLeaks(h, fragments, `${locale} Career`, FIXTURE);
      await h.click(tab.profile); await h.flush(60);
      // The server sends rank names in English; every screen shows the reader's own.
      assert.equal(h.dom.window.document.querySelector('.web-profile-rank')?.textContent, tab.rookie);
      assert.doesNotMatch(h.text(), /\b(?:Rookie|Analyst)\b/u);
      assertNoLeaks(h, fragments, `${locale} Profile`, FIXTURE);
      await h.click(tab.settings); await h.flush(60);
      assertNoLeaks(h, fragments, `${locale} Settings`, FIXTURE);
    } finally {await h.close(); await setLocale('en');}
  });
}

test('Career missions and ranks keep the API’s English and read in the reader’s language otherwise', async () => {
  const {missionText, rankName} = await import('../src/product/career-milestones.js');
  const mission = {id: 'hold-through-red-day', title: 'Hold through a red day', instruction: 'Hold a stock through a verified red Wall Street day.'} as const;
  try {
    await setLocale('en');
    assert.deepEqual(missionText(mission), {title: mission.title, instruction: mission.instruction});
    assert.equal(rankName({id: 'rookie', label: 'Rookie'}), 'Rookie');
    await setLocale('fr');
    assert.deepEqual(missionText(mission), {title: 'Tiens bon un jour dans le rouge', instruction: 'Garde une action pendant un jour dans le rouge confirmé à Wall Street.'});
    assert.equal(rankName({id: 'rookie', label: 'Rookie'}), 'Recrue');
    await setLocale('es-419');
    assert.equal(missionText({id: 'first-paper-buy', title: 'Buy your first stock', instruction: 'Complete one paper buy.'}).title, 'Compra tu primera acción');
  } finally {await setLocale('en');}
});
