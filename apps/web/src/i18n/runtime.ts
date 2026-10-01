/**
 * The active language for the whole page, readable from any module.
 *
 * English ships with the app; the other catalogs are separate chunks loaded
 * once, before the first render when the browser or a saved choice asks for
 * them, and on demand from Settings. A person's explicit choice is kept in
 * localStorage; when storage is blocked or throws, the browser's languages
 * decide and the app keeps working. Nothing here fetches from another origin.
 */
import {
  DEFAULT_LOCALE, LANGUAGE_STORAGE_KEY, applyDocumentLanguage, browserLanguages, pageStorage, resolveFormatTag, resolveLocale,
  startupLanguage, writeLanguageChoice, type LanguageStorage, type Locale, type StartupLanguage,
} from './locales';
import {formatParts, parseMessage, segmentsToString, type MessagePart, type MessageParams, type Segment} from './icu';
import {en, type Catalog, type MessageKey} from './messages/en';

export type {Catalog, MessageKey, MessageParams};

export interface I18nSnapshot {
  /** The copy the page reads. */
  readonly locale: Locale;
  /** The tag numbers and dates format with (`es-AR`, `pt-BR`, `fr-CA`); `en-US` in English. */
  readonly formatTag: string;
  readonly messages: Catalog;
  /** The saved choice from Settings, or null when the browser decides. */
  readonly choice: Locale | null;
}

let snapshot: I18nSnapshot = Object.freeze({locale: DEFAULT_LOCALE, formatTag: 'en-US', messages: en, choice: null});
const listeners = new Set<() => void>();
const catalogs = new Map<Locale, Catalog>([['en', en]]);
const loaders: Readonly<Record<Exclude<Locale, 'en'>, () => Promise<{readonly default: Catalog}>>> = {
  'es-419': () => import('./messages/es-419/index'),
  'pt-BR': () => import('./messages/pt-BR/index'),
  fr: () => import('./messages/fr/index'),
};
let requested = 0;

export function getSnapshot(): I18nSnapshot {return snapshot;}
export function getLocale(): Locale {return snapshot.locale;}
export function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => {listeners.delete(listener);};
}

/** The catalog for `locale`, loading its chunk the first time. */
export async function loadCatalog(locale: Locale): Promise<Catalog> {
  const cached = catalogs.get(locale);
  if (cached) return cached;
  const catalog = (await loaders[locale as Exclude<Locale, 'en'>]()).default;
  catalogs.set(locale, catalog);
  return catalog;
}

function activate(next: I18nSnapshot): void {
  const current = snapshot;
  if (current.locale === next.locale && current.formatTag === next.formatTag && current.messages === next.messages && current.choice === next.choice) return;
  snapshot = Object.freeze({...next});
  applyDocumentLanguage(next.locale);
  for (const listener of [...listeners]) {
    try {listener();} catch { /* One listener never stops the others. */ }
  }
}

/**
 * Switches the page to a language. A catalog that cannot load leaves the page
 * in English rather than half translated. The latest request wins.
 */
export async function setLocale(locale: Locale, options: {choice?: Locale | null; languages?: readonly unknown[]} = {}): Promise<Locale> {
  const turn = ++requested;
  let messages: Catalog = en, applied: Locale = DEFAULT_LOCALE;
  try {messages = await loadCatalog(locale); applied = locale;} catch { /* English stays usable. */ }
  const languages = options.languages ?? browserLanguages();
  if (turn === requested) {
    activate({locale: applied, formatTag: resolveFormatTag(applied, languages), messages,
      choice: options.choice === undefined ? snapshot.choice : options.choice});
  }
  return applied;
}

/**
 * Settings: remember this language on this browser (best effort) and switch
 * now. Null forgets the choice and follows the browser again. The language
 * changes for this page even when storage refuses to keep it.
 */
export async function chooseLocale(choice: Locale | null, storage: LanguageStorage | null = pageStorage(), languages: readonly unknown[] = browserLanguages()): Promise<{locale: Locale; saved: boolean}> {
  const saved = writeLanguageChoice(choice, storage);
  const locale = await setLocale(choice ?? resolveLocale(languages), {choice, languages});
  return {locale, saved};
}

let watching = false;
/** Another tab changed the saved language: follow it. */
function watchOtherTabs(): void {
  if (watching || typeof window === 'undefined') return;
  watching = true;
  try {
    window.addEventListener('storage', event => {
      if (event.key !== LANGUAGE_STORAGE_KEY && event.key !== null) return;
      const next = startupLanguage();
      if (next.locale !== snapshot.locale || next.choice !== snapshot.choice) void setLocale(next.locale, {choice: next.choice});
    });
  } catch { /* Other tabs simply keep their language until reload. */ }
}

/** Called once before the first render. It never rejects. */
export async function initI18n(startup: StartupLanguage = startupLanguage()): Promise<Locale> {
  watchOtherTabs();
  try {return await setLocale(startup.locale, {choice: startup.choice});} catch {return DEFAULT_LOCALE;}
}

const parsed = new Map<string, readonly MessagePart[] | null>();
function partsFor(source: string): readonly MessagePart[] | null {
  let parts = parsed.get(source);
  if (parts === undefined) {
    try {parts = parseMessage(source);} catch {parts = null;}
    parsed.set(source, parts);
  }
  return parts;
}

const numberFormats = new Map<string, Intl.NumberFormat>();
/** Plain numbers in messages: as a template literal wrote them in English, grouped in the locale's style elsewhere. */
export function messageNumber(state: I18nSnapshot = snapshot): (value: number) => string {
  if (state.locale === 'en') return value => String(value);
  let format = numberFormats.get(state.formatTag);
  if (!format) {
    try {format = new Intl.NumberFormat(state.formatTag, {maximumFractionDigits: 6});}
    catch {format = new Intl.NumberFormat(state.locale, {maximumFractionDigits: 6});}
    numberFormats.set(state.formatTag, format);
  }
  return value => format.format(value);
}

/** A message as segments: catalog text and values in place. */
export function formatSegments(key: MessageKey, params: MessageParams = {}, state: I18nSnapshot = snapshot): Segment[] {
  const source = state.messages[key] ?? en[key] ?? key;
  const parts = partsFor(source);
  if (!parts) return [{kind: 'text', text: source}];
  return formatParts(parts, params, state.locale, messageNumber(state));
}

/** The non-React accessor: the message in the current language, as plain text. */
export function t(key: MessageKey, params?: MessageParams): string {
  return segmentsToString(formatSegments(key, params));
}
