import {Fragment, createElement, useCallback, useEffect, useSyncExternalStore, type ReactNode} from 'react';
import type {Locale} from './locales';
import {RICH_TAG, segmentsToString, type Segment} from './icu';
import {chooseLocale, formatSegments, getSnapshot, subscribe, type I18nSnapshot, type MessageKey, type MessageParams} from './runtime';

/**
 * Messages with <strong>, <em>, <small> or <br/> in the catalog text, and
 * React nodes as values, rendered as React children. Only the catalog's own
 * text is read for tags: a value (a handle, a company name) never becomes
 * markup, whatever it contains.
 */
export function richSegments(segments: readonly Segment[]): ReactNode {
  type Frame = {tag: string | null; children: ReactNode[]};
  const stack: Frame[] = [{tag: null, children: []}];
  let key = 0;
  const top = () => stack[stack.length - 1]!;
  for (const segment of segments) {
    if (segment.kind === 'value') {
      const value = segment.value;
      top().children.push(typeof value === 'string' || typeof value === 'number' ? String(value) : createElement(Fragment, {key: key++}, value as ReactNode));
      continue;
    }
    const text = segment.text;
    let last = 0;
    for (const match of text.matchAll(RICH_TAG)) {
      const [whole, closing, name, selfClosing] = match;
      if (match.index > last) top().children.push(text.slice(last, match.index));
      last = match.index + whole.length;
      if (name === 'br' || selfClosing) top().children.push(createElement('br', {key: key++}));
      else if (!closing) stack.push({tag: name!, children: []});
      else if (stack.length > 1 && top().tag === name) {
        const done = stack.pop()!;
        top().children.push(createElement(done.tag!, {key: key++}, ...done.children));
      }
    }
    if (last < text.length) top().children.push(text.slice(last));
  }
  while (stack.length > 1) {const open = stack.pop()!; top().children.push(createElement(open.tag!, {key: key++}, ...open.children));}
  return createElement(Fragment, null, ...stack[0]!.children);
}

export interface Translator {
  /** The message as plain text (rich-text tags dropped). */
  (key: MessageKey, params?: MessageParams): string;
  /** The message as React children, for markup in the catalog or React nodes as values. */
  rich(key: MessageKey, params?: MessageParams): ReactNode;
  readonly locale: Locale;
}
const translators = new WeakMap<I18nSnapshot, Translator>();
export function translatorFor(state: I18nSnapshot): Translator {
  let translator = translators.get(state);
  if (!translator) {
    const bound = ((key: MessageKey, params?: MessageParams) => segmentsToString(formatSegments(key, params, state))) as Translator;
    Object.defineProperties(bound, {
      rich: {value: (key: MessageKey, params?: MessageParams) => richSegments(formatSegments(key, params, state))},
      locale: {value: state.locale},
    });
    translator = bound;
    translators.set(state, translator);
  }
  return translator;
}

function useSnapshot(): I18nSnapshot {return useSyncExternalStore(subscribe, getSnapshot, getSnapshot);}

/** The translator for the current language. The component renders again when the language changes. */
export function useT(): Translator {return translatorFor(useSnapshot());}
export function useLocale(): Locale {return useSnapshot().locale;}

/** Settings: the saved choice (null follows the browser) and a way to change it. */
export function useLanguageChoice(): {readonly locale: Locale; readonly choice: Locale | null; readonly choose: (choice: Locale | null) => Promise<{locale: Locale; saved: boolean}>} {
  const state = useSnapshot();
  const choose = useCallback((choice: Locale | null) => chooseLocale(choice), []);
  return {locale: state.locale, choice: state.choice, choose};
}

/**
 * Wraps a page. The child is a function, so the whole tree renders again on a
 * language change: text formatted outside components (errors, amounts, dates)
 * follows without remounting or losing state. `title` keeps the document
 * title in the page's language.
 */
export function I18nRoot({children, title}: {children: (locale: Locale) => ReactNode; title?: MessageKey}) {
  const state = useSnapshot();
  useEffect(() => {
    if (!title) return;
    try {document.title = translatorFor(state)(title);} catch { /* Title only. */ }
  }, [state, title]);
  return <>{children(state.locale)}</>;
}
