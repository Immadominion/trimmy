/**
 * A small ICU MessageFormat subset, enough for Trimmy's copy and nothing more:
 *
 *   {name}                                      a value
 *   {count, plural, =0 {…} one {…} other {…}}   forms by Intl.PluralRules; # is the number
 *   {kind, select, buy {…} sell {…} other {…}}  a choice by exact value
 *
 * Braces are always syntax (there is no apostrophe quoting), so straight and
 * typographic apostrophes are plain text. Every plural and select needs
 * `other`, which also catches categories a language has but a message does
 * not spell out (CLDR's `many` for large numbers in Spanish, Portuguese and
 * French). Sentences are never built by concatenating fragments: each
 * language owns its whole sentence, including where each value goes.
 */
export type MessagePart =
  | {readonly kind: 'text'; readonly text: string}
  | {readonly kind: 'arg'; readonly name: string}
  | {readonly kind: 'pound'}
  | {readonly kind: 'plural' | 'select'; readonly name: string; readonly options: ReadonlyMap<string, readonly MessagePart[]>};

export class MessageSyntaxError extends Error {
  constructor(message: string, readonly source: string) {super(`${message} in “${source}”`); this.name = 'MessageSyntaxError';}
}

const IDENTIFIER = /[A-Za-z0-9_]/u;
const SELECTOR = /[A-Za-z0-9_=.-]/u;

export function parseMessage(source: string): readonly MessagePart[] {
  let at = 0;
  const fail = (why: string): never => {throw new MessageSyntaxError(`${why} at ${at}`, source);};
  const space = () => {while (at < source.length && /\s/u.test(source[at]!)) at++;};
  const expect = (char: string) => {if (source[at] !== char) fail(`Expected “${char}”`); at++;};
  const word = (pattern: RegExp) => {
    const start = at;
    while (at < source.length && pattern.test(source[at]!)) at++;
    if (at === start) fail('Expected a name');
    return source.slice(start, at);
  };
  function body(inPlural: boolean, nested: boolean): MessagePart[] {
    const parts: MessagePart[] = [];
    let text = '';
    const flush = () => {if (text) {parts.push({kind: 'text', text}); text = '';}};
    while (at < source.length) {
      const char = source[at]!;
      if (char === '{') {flush(); parts.push(argument(inPlural)); continue;}
      if (char === '}') {if (!nested) fail('Unmatched “}”'); break;}
      if (char === '#' && inPlural) {flush(); parts.push({kind: 'pound'}); at++; continue;}
      text += char; at++;
    }
    flush();
    return parts;
  }
  function argument(inPlural: boolean): MessagePart {
    expect('{'); space();
    const name = word(IDENTIFIER); space();
    if (source[at] === '}') {at++; return {kind: 'arg', name};}
    expect(','); space();
    const type = word(IDENTIFIER);
    if (type !== 'plural' && type !== 'select') fail(`Unsupported type “${type}”`);
    space(); expect(','); space();
    const options = new Map<string, readonly MessagePart[]>();
    while (source[at] !== '}') {
      if (at >= source.length) fail('Unclosed argument');
      const selector = word(SELECTOR); space();
      if (options.has(selector)) fail(`Repeated option “${selector}”`);
      expect('{');
      options.set(selector, body(type === 'plural' || inPlural, true));
      expect('}'); space();
    }
    at++;
    if (!options.has('other')) fail('Missing “other”');
    return {kind: type as 'plural' | 'select', name, options};
  }
  const parts = body(false, false);
  if (at !== source.length) fail('Unexpected text');
  return parts;
}

/** Every argument a message reads, including plural and select selectors. */
export function messageArguments(parts: readonly MessagePart[], into = new Set<string>()): Set<string> {
  for (const part of parts) {
    if (part.kind === 'arg') into.add(part.name);
    else if (part.kind === 'plural' || part.kind === 'select') {
      into.add(part.name);
      for (const option of part.options.values()) messageArguments(option, into);
    }
  }
  return into;
}
/** The rich-text tags a message uses, in order, for parity checks. */
export function messageTags(source: string): string[] {
  return [...source.matchAll(/<\/?([a-z]+)\s*\/?>/gu)].map(match => match[0].replace(/\s/gu, ''));
}

/**
 * A number as a message shows it, with the number kept for plural choice.
 * Made by the format module (`count`, `amount`) so the shown text follows
 * the page's language while `one` / `other` still read the real number.
 */
export class Shown {
  constructor(readonly value: number, readonly text: string) {}
  toString(): string {return this.text;}
}

/** A formatted message: catalog text, and values (strings, numbers, React nodes) in place. */
export type Segment =
  | {readonly kind: 'text'; readonly text: string}
  | {readonly kind: 'value'; readonly value: unknown};
export type MessageParams = Readonly<Record<string, unknown>>;

function numeric(value: unknown): number | null {
  if (value instanceof Shown) return Number.isFinite(value.value) ? value.value : null;
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (typeof value === 'bigint') return Number(value);
  if (typeof value === 'string' && /^-?\d+(?:\.\d+)?$/u.test(value)) return Number(value);
  return null;
}
/** Visible fraction digits decide plural forms: `1 share`, but `1.5 shares` in English. */
function fractionDigits(value: unknown): number {
  const text = value instanceof Shown ? String(value.value) : typeof value === 'string' ? value : typeof value === 'number' ? String(value) : '';
  const match = /\.(\d+)$/u.exec(text);
  return match ? Math.min(match[1]!.length, 20) : 0;
}
const pluralRules = new Map<string, Intl.PluralRules>();
export function pluralCategory(locale: string, value: number, digits = 0): string {
  const key = `${locale}:${digits}`;
  let rules = pluralRules.get(key);
  if (!rules) {
    try {rules = new Intl.PluralRules(locale, {minimumFractionDigits: digits});} catch {rules = new Intl.PluralRules('en', {minimumFractionDigits: digits});}
    pluralRules.set(key, rules);
  }
  return rules.select(value);
}

/**
 * Fills a parsed message. `locale` chooses plural forms; `formatNumber` writes
 * plain numbers (a `Shown` keeps its own text). Missing values show as
 * `{name}` so a wrong call is visible rather than silently blank.
 */
export function formatParts(parts: readonly MessagePart[], params: MessageParams, locale: string,
  formatNumber: (value: number) => string, pound: unknown = undefined): Segment[] {
  const out: Segment[] = [];
  const text = (value: string) => {
    const last = out[out.length - 1];
    if (last?.kind === 'text') out[out.length - 1] = {kind: 'text', text: last.text + value}; else out.push({kind: 'text', text: value});
  };
  const insert = (value: unknown, name: string) => {
    if (value === undefined || value === null) text(`{${name}}`);
    else if (typeof value === 'number') out.push({kind: 'value', value: formatNumber(value)});
    else if (value instanceof Shown) out.push({kind: 'value', value: value.text});
    else if (typeof value === 'bigint' || typeof value === 'boolean') out.push({kind: 'value', value: String(value)});
    else out.push({kind: 'value', value});
  };
  for (const part of parts) {
    if (part.kind === 'text') text(part.text);
    else if (part.kind === 'arg') insert(params[part.name], part.name);
    else if (part.kind === 'pound') insert(pound, '#');
    else {
      const value = params[part.name];
      let chosen: readonly MessagePart[] | undefined;
      if (part.kind === 'select') chosen = part.options.get(String(value)) ?? part.options.get('other');
      else {
        const number = numeric(value);
        if (number !== null) chosen = part.options.get(`=${number}`) ?? part.options.get(pluralCategory(locale, number, fractionDigits(value)));
        chosen ??= part.options.get('other');
      }
      out.push(...formatParts(chosen!, params, locale, formatNumber, part.kind === 'plural' ? value : pound));
    }
  }
  // Join neighbouring text so tags split by a value-free option still pair up.
  return out.reduce<Segment[]>((joined, segment) => {
    const last = joined[joined.length - 1];
    if (segment.kind === 'text' && last?.kind === 'text') joined[joined.length - 1] = {kind: 'text', text: last.text + segment.text};
    else joined.push(segment);
    return joined;
  }, []);
}

/** Plain text. Rich-text tags in catalog text are dropped; values are never read for tags. */
export function segmentsToString(segments: readonly Segment[]): string {
  return segments.map(segment => segment.kind === 'text' ? segment.text.replace(RICH_TAG, '') : String(segment.value)).join('');
}
/** The tags a message may carry for rich text. */
export const RICH_TAG = /<(\/?)(strong|em|small|br)\s*(\/?)>/gu;
