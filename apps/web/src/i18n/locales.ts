/**
 * The languages Trimmy's web app speaks, and how a browser's languages map to
 * them. Mirrors the Flutter app (apps/mobile/lib/l10n/app_locale.dart):
 *
 * - English is the source and the fallback.
 * - Any Spanish reads the Latin American copy (es-419), any Portuguese the
 *   Brazilian copy (pt-BR), any French the French copy.
 * - Numbers and dates follow the browser's region whenever the browser lists
 *   the chosen language with a region: es-AR writes 1.234,56 and es-MX writes
 *   1,234.56, both with the es-419 copy. Without a region, Spanish and
 *   Portuguese format as es-419 and pt-BR.
 * - English formats exactly as the app always has, whatever the region.
 *
 * Small on purpose: the page entry imports it before any catalog loads.
 */
export const LOCALES = ['en', 'es-419', 'pt-BR', 'fr'] as const;
export type Locale = typeof LOCALES[number];
export const DEFAULT_LOCALE: Locale = 'en';

/** Where a person's explicit choice is kept. No value follows the browser. */
export const LANGUAGE_STORAGE_KEY = 'trimmy.web.language.v1';

/**
 * Each language in its own words, as the language selector shows it. Never
 * translated, so anyone can find their own language whatever the page shows.
 */
export const LOCALE_NAMES: Readonly<Record<Locale, string>> = Object.freeze({
  en: 'English',
  'es-419': 'Español (Latinoamérica)',
  'pt-BR': 'Português (Brasil)',
  fr: 'Français',
});

export function isLocale(value: unknown): value is Locale {
  return typeof value === 'string' && (LOCALES as readonly string[]).includes(value);
}

function parts(tag: string): {language: string; region: string | null} {
  const [language = '', ...rest] = tag.trim().replace(/_/gu, '-').split('-');
  // A region is two letters or three digits (419); scripts (Latn) and variants are skipped.
  const region = rest.find(part => /^(?:[A-Za-z]{2}|\d{3})$/u.test(part)) ?? null;
  return {language: language.toLowerCase(), region: region === null ? null : region.toUpperCase()};
}

/** One BCP 47 tag (`es-MX`, `pt_PT`, `FR`) to the copy it reads, or null when Trimmy has none. */
export function matchLocale(tag: string): Locale | null {
  switch (parts(tag).language) {
    case 'en': return 'en';
    case 'es': return 'es-419';
    case 'pt': return 'pt-BR';
    case 'fr': return 'fr';
    default: return null;
  }
}

/** The first browser language Trimmy speaks, in the browser's order; English otherwise. */
export function resolveLocale(languages: readonly unknown[]): Locale {
  for (const tag of languages) {
    if (typeof tag !== 'string') continue;
    const locale = matchLocale(tag);
    if (locale) return locale;
  }
  return DEFAULT_LOCALE;
}

const DEFAULT_FORMAT_TAG: Readonly<Record<Locale, string>> = {en: 'en-US', 'es-419': 'es-419', 'pt-BR': 'pt-BR', fr: 'fr'};
function supported(tag: string): boolean {
  try {return Intl.NumberFormat.supportedLocalesOf([tag]).length > 0 && Intl.DateTimeFormat.supportedLocalesOf([tag]).length > 0;}
  catch {return false;}
}

/**
 * The tag numbers and dates format with for `locale`. The browser's region
 * wins when the browser lists the same language with one (`es-AR`, `pt-PT`,
 * `fr-CA`); otherwise each language's default. English is always `en-US`:
 * English keeps the app's historical formatting and never reads this.
 */
export function resolveFormatTag(locale: Locale, languages: readonly unknown[]): string {
  if (locale === 'en') return 'en-US';
  const language = locale.slice(0, 2);
  for (const tag of languages) {
    if (typeof tag !== 'string') continue;
    const {language: candidate, region} = parts(tag);
    if (candidate !== language || region === null) continue;
    const formatTag = `${language}-${region}`;
    if (supported(formatTag)) return formatTag;
  }
  return DEFAULT_FORMAT_TAG[locale];
}

/** navigator.languages, else navigator.language, else nothing. Never throws. */
export function browserLanguages(): readonly string[] {
  try {
    if (typeof navigator === 'undefined') return [];
    if (Array.isArray(navigator.languages) && navigator.languages.length) return navigator.languages;
    return typeof navigator.language === 'string' && navigator.language ? [navigator.language] : [];
  } catch {return [];}
}

export type LanguageStorage = Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>;
/** The page's localStorage, or null when the browser blocks it. Never throws. */
export function pageStorage(): LanguageStorage | null {
  try {return typeof window === 'undefined' ? null : window.localStorage;} catch {return null;}
}
/** The saved choice, or null when there is none or storage cannot be read. Never throws. */
export function readLanguageChoice(storage: LanguageStorage | null = pageStorage()): Locale | null {
  try {
    const value = storage?.getItem(LANGUAGE_STORAGE_KEY) ?? null;
    return isLocale(value) ? value : null;
  } catch {return null;}
}
/** Saves (or with null, forgets) the choice. False when storage refused it. Never throws. */
export function writeLanguageChoice(locale: Locale | null, storage: LanguageStorage | null = pageStorage()): boolean {
  try {
    if (!storage) return false;
    if (locale) storage.setItem(LANGUAGE_STORAGE_KEY, locale); else storage.removeItem(LANGUAGE_STORAGE_KEY);
    return true;
  } catch {return false;}
}

export interface StartupLanguage {
  /** The copy the page reads. */
  readonly locale: Locale;
  /** The tag numbers and dates format with. */
  readonly formatTag: string;
  /** The saved choice, or null when the browser decides. */
  readonly choice: Locale | null;
}
/** The language to open with: a saved choice first, then the browser's languages. Never throws. */
export function startupLanguage(storage: LanguageStorage | null = pageStorage(), languages: readonly unknown[] = browserLanguages()): StartupLanguage {
  const choice = readLanguageChoice(storage);
  const locale = choice ?? resolveLocale(languages);
  return {locale, formatTag: resolveFormatTag(locale, languages), choice};
}

/** Sets `<html lang>`. Never throws. */
export function applyDocumentLanguage(locale: Locale): void {
  try {if (typeof document !== 'undefined' && document.documentElement) document.documentElement.lang = locale;} catch { /* Attribute only. */ }
}

/**
 * The one sentence shown when the app's own code cannot load, so it cannot
 * come from a catalog chunk. Kept here, in the page entry, in every language.
 */
export const LOAD_FAILURE: Readonly<Record<Locale, string>> = Object.freeze({
  en: 'Trimmy couldn’t load. Please reopen this page.',
  'es-419': 'Trimmy no pudo cargar. Vuelve a abrir esta página.',
  'pt-BR': 'O Trimmy não carregou. Abra esta página de novo.',
  fr: 'Trimmy n’a pas pu se charger. Rouvre cette page.',
});
