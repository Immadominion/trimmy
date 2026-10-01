/**
 * Finds English copy on a page that should be showing another language.
 *
 * Every English catalog message whose translation differs is split into its
 * literal text runs (placeholders, plural syntax and rich tags removed); any
 * run of two or more words that shows up in the page's text or in its
 * accessible attributes, and that the translation does not itself contain,
 * is a leak. A second check looks for common English function words in the
 * page text, which catches copy that never made it into a catalog.
 */
import {parseMessage, type MessagePart} from '../../src/i18n/icu.js';
import {loadCatalog} from '../../src/i18n/runtime.js';
import {en} from '../../src/i18n/messages/en/index.js';
import type {Locale} from '../../src/i18n/locales.js';

function runs(parts: readonly MessagePart[], into: string[] = []): string[] {
  for (const part of parts) {
    if (part.kind === 'text') into.push(...part.text.replace(/<\/?[a-z]+\s*\/?>/gu, '\n').split('\n'));
    else if (part.kind === 'plural' || part.kind === 'select') for (const option of part.options.values()) runs(option, into);
  }
  return into;
}

export async function englishFragments(locale: Exclude<Locale, 'en'>): Promise<Map<string, string>> {
  const catalog = await loadCatalog(locale);
  const fragments = new Map<string, string>();
  for (const [key, source] of Object.entries(en)) {
    const translated = catalog[key as keyof typeof en];
    if (translated === source) continue;
    for (const run of runs(parseMessage(source))) {
      const text = run.trim().replace(/^[^\p{L}]+|[^\p{L}]+$/gu, '');
      if (text.split(/\s+/u).length < 2 || text.length < 8 || translated.includes(text)) continue;
      fragments.set(text, key);
    }
  }
  return fragments;
}

/** The page's visible text and the attributes assistive technology reads. */
export function pageStrings(document: Document): string[] {
  const strings = [document.body.textContent ?? ''];
  for (const element of document.querySelectorAll('[aria-label], [title], [placeholder], [alt], [aria-valuetext], [aria-description]')) {
    for (const name of ['aria-label', 'title', 'placeholder', 'alt', 'aria-valuetext', 'aria-description']) {
      const value = element.getAttribute(name);
      if (value) strings.push(value);
    }
  }
  if (document.title) strings.push(document.title);
  return strings;
}

const ENGLISH_WORDS = /\b(?:the|your|you|and|with|this|that|from|isn’t|can’t|couldn’t|won’t|don’t|here|there|more|again|before|after|while|until|into)\b/giu;

export interface LeakReport {readonly fragments: readonly string[]; readonly words: readonly string[]}
/**
 * Leaks on the page. `allow` lists text the page may legitimately show in
 * English in this test (server-authored fixture content, names).
 */
export function findLeaks(document: Document, fragments: ReadonlyMap<string, string>, allow: readonly string[] = []): LeakReport {
  let strings = pageStrings(document);
  for (const allowed of allow) strings = strings.map(value => value.split(allowed).join(' '));
  const found: string[] = [];
  for (const [fragment, key] of fragments) if (strings.some(value => value.includes(fragment))) found.push(`${key}: ${fragment}`);
  const words = new Set<string>();
  for (const value of strings) for (const match of value.matchAll(ENGLISH_WORDS)) {
    const at = match.index, context = value.slice(Math.max(0, at - 30), at + match[0].length + 30).replace(/\s+/gu, ' ');
    words.add(`${match[0]} … ${context}`);
  }
  return {fragments: found, words: [...words]};
}
