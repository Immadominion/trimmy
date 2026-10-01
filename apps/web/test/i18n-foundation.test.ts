import assert from 'node:assert/strict';
import test from 'node:test';
import {
  LANGUAGE_STORAGE_KEY, LOCALES, LOCALE_NAMES, LOAD_FAILURE, matchLocale, readLanguageChoice, resolveFormatTag, resolveLocale,
  startupLanguage, writeLanguageChoice, type Locale,
} from '../src/i18n/locales.js';
import {MessageSyntaxError, Shown, formatParts, messageArguments, messageTags, parseMessage, segmentsToString} from '../src/i18n/icu.js';
import {chooseLocale, getSnapshot, loadCatalog, setLocale, t} from '../src/i18n/runtime.js';
import * as fmt from '../src/i18n/format.js';
import {AREAS, en} from '../src/i18n/messages/en/index.js';

class MemoryStorage {
  values = new Map<string, string>();
  getItem(key: string) {return this.values.get(key) ?? null;}
  setItem(key: string, value: string) {this.values.set(key, value);}
  removeItem(key: string) {this.values.delete(key);}
}
const throwing = {
  getItem(): string | null {throw new Error('SecurityError');},
  setItem(): void {throw new Error('QuotaExceededError');},
  removeItem(): void {throw new Error('SecurityError');},
};

test('browser languages map to the copy and the region keeps its number style', () => {
  const cases: [readonly string[], Locale, string][] = [
    [['es'], 'es-419', 'es-419'], [['es-MX'], 'es-419', 'es-MX'], [['es-AR', 'en'], 'es-419', 'es-AR'], [['es_ES'], 'es-419', 'es-ES'],
    [['pt'], 'pt-BR', 'pt-BR'], [['pt-PT'], 'pt-BR', 'pt-PT'], [['pt-br'], 'pt-BR', 'pt-BR'],
    [['FR'], 'fr', 'fr'], [['fr-CA'], 'fr', 'fr-CA'], [['de-DE', 'fr-CH'], 'fr', 'fr-CH'],
    [['en-GB', 'es'], 'en', 'en-US'], [['de', 'it'], 'en', 'en-US'], [[], 'en', 'en-US'], [['zh-Hant-TW', 'pt-Latn-BR'], 'pt-BR', 'pt-BR'],
  ];
  for (const [languages, locale, formatTag] of cases) {
    assert.equal(resolveLocale(languages), locale, languages.join());
    assert.equal(resolveFormatTag(locale, languages), formatTag, languages.join());
  }
  // A chosen language with no matching browser region formats in its default region.
  assert.equal(resolveFormatTag('fr', ['en-US']), 'fr');
  assert.equal(resolveFormatTag('es-419', ['en-US', 'es-CO']), 'es-CO');
  assert.equal(matchLocale('ca-ES'), null);
  assert.deepEqual(LOCALES, ['en', 'es-419', 'pt-BR', 'fr']);
  assert.deepEqual(Object.values(LOCALE_NAMES), ['English', 'Español (Latinoamérica)', 'Português (Brasil)', 'Français']);
  for (const locale of LOCALES) assert.ok(LOAD_FAILURE[locale].length > 10);
});

test('a saved choice wins, and blocked or throwing storage falls back to the browser without throwing', async () => {
  const storage = new MemoryStorage();
  assert.deepEqual(startupLanguage(storage, ['pt-PT']), {locale: 'pt-BR', formatTag: 'pt-PT', choice: null});
  assert.equal(writeLanguageChoice('fr', storage), true);
  assert.equal(storage.getItem(LANGUAGE_STORAGE_KEY), 'fr');
  assert.deepEqual(startupLanguage(storage, ['pt-PT']), {locale: 'fr', formatTag: 'fr', choice: 'fr'});
  storage.setItem(LANGUAGE_STORAGE_KEY, 'de');
  assert.equal(readLanguageChoice(storage), null, 'an unknown saved value is ignored');
  assert.equal(writeLanguageChoice(null, storage), true);
  assert.equal(storage.getItem(LANGUAGE_STORAGE_KEY), null);

  assert.equal(readLanguageChoice(throwing), null);
  assert.equal(writeLanguageChoice('fr', throwing), false);
  assert.equal(readLanguageChoice(null), null);
  assert.deepEqual(startupLanguage(throwing, ['es-MX']), {locale: 'es-419', formatTag: 'es-MX', choice: null});
  // The language still changes for this page when storage refuses to keep it.
  const result = await chooseLocale('fr', throwing, ['en-US']);
  assert.deepEqual(result, {locale: 'fr', saved: false});
  assert.equal(getSnapshot().locale, 'fr');
  assert.equal(getSnapshot().choice, 'fr');
  assert.equal(t('common.tryAgain'), 'Réessayer');
  await chooseLocale(null, throwing, ['en-US']);
  assert.equal(getSnapshot().locale, 'en');
  assert.equal(getSnapshot().choice, null);
  assert.equal(t('common.tryAgain'), 'Try again');
});

test('plural forms follow each language through Intl.PluralRules, never concatenation', () => {
  const source = '{count, plural, =0 {none} one {# one} many {# many} other {# other}}';
  const parts = parseMessage(source);
  const say = (locale: string, value: unknown) => segmentsToString(formatParts(parts, {count: value}, locale, String));
  assert.equal(say('en', 0), 'none');
  assert.equal(say('en', 1), '1 one');
  assert.equal(say('en', 2), '2 other');
  assert.equal(say('en', '1.5'), '1.5 other');
  // Portuguese and French: zero to under two is singular.
  assert.equal(say('pt-BR', 1.5), '1.5 one');
  assert.equal(say('fr', 1.5), '1.5 one');
  assert.equal(say('es-419', 1.5), '1.5 other');
  // CLDR's `many` for a million in Spanish, Portuguese and French; English stays `other`.
  for (const locale of ['es-419', 'pt-BR', 'fr']) assert.equal(say(locale, 1_000_000), '1000000 many');
  assert.equal(say('en', 1_000_000), '1000000 other');
  // `many` falls back to `other` when a message does not spell it out.
  const plain = parseMessage('{n, plural, one {# action} other {# actions}}');
  assert.equal(segmentsToString(formatParts(plain, {n: 1_000_000}, 'fr', String)), '1000000 actions');
  // A Shown number picks its form from the number and shows its own text.
  assert.equal(segmentsToString(formatParts(plain, {n: new Shown(1234, '1 234')}, 'fr', String)), '1 234 actions');
  assert.equal(segmentsToString(formatParts(plain, {n: new Shown(1, '1')}, 'fr', String)), '1 action');
  const select = parseMessage('{side, select, buy {Bought} sell {Sold} other {Moved}} {name}');
  assert.equal(segmentsToString(formatParts(select, {side: 'sell', name: 'Apple'}, 'en', String)), 'Sold Apple');
  assert.equal(segmentsToString(formatParts(select, {side: 'x', name: 'Apple'}, 'en', String)), 'Moved Apple');
  assert.deepEqual([...messageArguments(select)].sort(), ['name', 'side']);
  assert.throws(() => parseMessage('{n, plural, one {x}}'), MessageSyntaxError);
  assert.throws(() => parseMessage('Missing {brace'), MessageSyntaxError);
  assert.deepEqual(messageTags('Enter <strong>{email}</strong>.<br/>'), ['<strong>', '</strong>', '<br/>']);
});

test('English formatting is byte for byte the input, whatever the helper', async () => {
  await setLocale('en');
  for (const value of ['1,234.56', '-0.25', '−3.00', '+12', '<0.01']) assert.equal(fmt.number(value), value);
  for (const value of ['$1,234.56', '-$0.25', '$1.2B', '$0.0001']) assert.equal(fmt.usd(value), value);
  assert.equal(fmt.percent('+1.23%'), '+1.23%');
  assert.equal(fmt.decimalInput('12.5'), '12.5');
  for (const value of ['12,5', '1,000', ' 12.5 ', '1.234,5']) assert.equal(fmt.normalizeDecimalInput(value), value);
  assert.equal(fmt.amountCharacters('1,2a.3'), '12.3');
  assert.equal(fmt.count(1234, 'en-US').text, '1,234');
  assert.equal(fmt.count(1234, 'raw').text, '1234');
  assert.equal(fmt.count(1234).text, (1234).toLocaleString());
  const day = Date.UTC(2026, 8, 30, 12);
  assert.equal(fmt.date(day, 'en-US', {month: 'short', day: 'numeric', timeZone: 'UTC'}), 'Sep 30');
  assert.equal(fmt.date(day, 'en-GB', {day: 'numeric', month: 'short', timeZone: 'UTC'}), '30 Sept');
});

test('numbers, dollars and percents read in each language and region', async () => {
  const cases: [Locale, string, Record<string, string>][] = [
    ['es-419', 'es-419', {n: '1,234,567.5', neg: '-1,234.56', usd: 'US$1,234.56', usdNeg: '-US$0.25', big: 'US$1.2\u00A0mil\u00A0M', pct: '+1.23%', small: '<0.01'}],
    ['es-419', 'es-AR', {n: '1.234.567,5', neg: '-1.234,56', usd: 'US$\u00A01.234,56', usdNeg: '-US$\u00A00,25', big: 'US$\u00A01,2\u00A0mil\u00A0M', pct: '+1,23%', small: '<0,01'}],
    ['es-419', 'es-ES', {n: '1.234.567,5', neg: '-1.234,56', usd: '1.234,56\u00A0US$', usdNeg: '-0,25\u00A0US$', big: '1,2\u00A0mil\u00A0M\u00A0US$', pct: '+1,23\u00A0%', small: '<0,01'}],
    ['pt-BR', 'pt-BR', {n: '1.234.567,5', neg: '-1.234,56', usd: 'US$\u00A01.234,56', usdNeg: '-US$\u00A00,25', big: 'US$\u00A01,2\u00A0bi', pct: '+1,23%', small: '<0,01'}],
    ['fr', 'fr', {n: '1\u202F234\u202F567,5', neg: '-1\u202F234,56', usd: '1\u202F234,56\u00A0$US', usdNeg: '-0,25\u00A0$US', big: '1,2\u00A0Md\u00A0$US', pct: '+1,23\u00A0%', small: '<0,01'}],
    ['fr', 'fr-CA', {n: '1\u00A0234\u00A0567,5', neg: '-1\u00A0234,56', usd: '1\u00A0234,56\u00A0$US', usdNeg: '-0,25\u00A0$US', big: '1,2\u00A0Md\u00A0$US', pct: '+1,23\u00A0%', small: '<0,01'}],
  ];
  for (const [locale, region, expected] of cases) {
    await setLocale(locale, {languages: [region]});
    assert.equal(getSnapshot().formatTag, region);
    const actual = {n: fmt.number('1,234,567.5'), neg: fmt.number('-1,234.56'), usd: fmt.usd('$1,234.56'), usdNeg: fmt.usd('-$0.25'),
      big: fmt.usd('$1.2B'), pct: fmt.percent('+1.23%'), small: fmt.number('<0.01')};
    assert.deepEqual(actual, expected, `${locale} ${region}`);
    assert.equal(fmt.number('Apple'), 'Apple', 'text that is not a number is left alone');
  }
  await setLocale('fr', {languages: ['fr-FR']});
  assert.equal(fmt.decimalInput('12.5'), '12,5');
  assert.equal(fmt.count(1234567).text, '1\u202F234\u202F567');
  assert.equal(fmt.date(Date.UTC(2026, 8, 30, 12), 'en-US', {month: 'short', day: 'numeric', timeZone: 'UTC'}), '30 sept.');
  await setLocale('en');
});

test('typed amounts accept either decimal mark outside English and never multiply', async () => {
  for (const locale of ['es-419', 'pt-BR', 'fr'] as const) {
    await setLocale(locale);
    const cases: Record<string, string> = {
      '12,5': '12.5', '12.5': '12.5', '1.250': '1.250', '1,250': '1.250', '1.234,5': '1234.5', '1,234.5': '1234.5',
      '1 234,5': '1234.5', '1 234,5': '1234.5', '1.000.000': '1000000', '1,000,000': '1000000', '100': '100', ' 7 ': '7',
      '12,': '12.', ',5': '.5', '1,2,3': '1,2,3', '1.2.3': '1.2.3', '12,5.3': '12,5.3', 'abc': 'abc',
    };
    for (const [typed, plain] of Object.entries(cases)) assert.equal(fmt.normalizeDecimalInput(typed), plain, `${locale} ${typed}`);
    assert.equal(fmt.amountCharacters('1,2a.3'), '1,2.3');
  }
  await setLocale('en');
});

test('every catalog has every key, the same placeholders and tags, and no em dashes', async () => {
  const enKeys = Object.keys(en).sort();
  for (const [area, messages] of Object.entries(AREAS)) {
    for (const key of Object.keys(messages)) assert.ok(key.startsWith(`${area}.`), `${key} lives in ${area}`);
  }
  assert.equal(new Set(enKeys).size, Object.values(AREAS).reduce<number>((sum, area) => sum + Object.keys(area).length, 0), 'no key repeats across areas');
  for (const locale of ['es-419', 'pt-BR', 'fr'] as const) {
    const catalog = await loadCatalog(locale);
    assert.deepEqual(Object.keys(catalog).sort(), enKeys, `${locale} has exactly the English keys`);
    for (const key of enKeys) {
      const source = en[key as keyof typeof en], translated = catalog[key as keyof typeof en];
      const sourceArgs = [...messageArguments(parseMessage(source))].sort();
      const translatedArgs = [...messageArguments(parseMessage(translated))].sort();
      assert.deepEqual(translatedArgs, sourceArgs, `${locale} ${key} placeholders`);
      assert.deepEqual(messageTags(translated).sort(), messageTags(source).sort(), `${locale} ${key} tags`);
      assert.ok(!translated.includes('—'), `${locale} ${key} has no em dash`);
      assert.ok(translated.trim().length > 0 || source.trim().length === 0, `${locale} ${key} is not empty`);
    }
  }
  for (const key of enKeys) parseMessage(en[key as keyof typeof en]);
});

test('rich messages read tags only from the catalog, never from values', async () => {
  const {richSegments} = await import('../src/i18n/react.js');
  const {renderToStaticMarkup} = await import('react-dom/server');
  const parts = parseMessage('Enter the code sent to <strong>{email}</strong>.');
  const html = renderToStaticMarkup(richSegments(formatParts(parts, {email: '<strong>x</strong>@example.com'}, 'en', String)) as never);
  assert.equal(html, 'Enter the code sent to <strong>&lt;strong&gt;x&lt;/strong&gt;@example.com</strong>.');
  assert.equal(segmentsToString(formatParts(parts, {email: 'a@b.co'}, 'en', String)), 'Enter the code sent to a@b.co.');
});
