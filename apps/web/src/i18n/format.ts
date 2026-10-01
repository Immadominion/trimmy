/**
 * The one place that decides how numbers, US dollar amounts, percents, dates
 * and times read in the page's language. Mirrors the Flutter app's
 * AppFormats (apps/mobile/lib/l10n/app_formats.dart).
 *
 * Amounts in Trimmy are computed exactly elsewhere (paper micros, raw token
 * units, BigInt cents) and arrive here already rounded, written the way the
 * English app shows them: `1,234.56`, `-0.25`, `+12`, `$1,234.56`. These
 * helpers only change how that text reads in the current language. They never
 * round, so an exact amount stays exact.
 *
 * English output is byte for byte what the app showed before localization,
 * whatever the browser's region: every helper returns English text unchanged
 * and every date helper runs the original English call. Spanish, Portuguese
 * and French follow the browser's region when it lists the same language
 * (es-MX writes 1,234.56, es-AR writes 1.234,56), otherwise the language's
 * default region (es-419, pt-BR, fr).
 *
 * Every amount in Trimmy is in US dollars, practice money included. Where a
 * language's own currencies also use "$" (Latin American pesos, the Brazilian
 * real's R$), the symbol is "US$" so nobody reads dollars as local money.
 * French writes "$US", the usual French form. A sign goes before the amount:
 * "-$12.30", "-US$ 12,30", "-12,30 $US".
 */
import {Shown} from './icu';
import {getSnapshot, t, type I18nSnapshot} from './runtime';

export {Shown};

interface Formats {
  readonly english: boolean;
  readonly tag: string;
  readonly decimal: string;
  readonly group: string;
  readonly dollarSymbol: string;
  readonly dollarFirst: boolean;
  readonly dollarGap: string;
  readonly percentFirst: boolean;
  readonly percentGap: string;
}

const ENGLISH: Formats = Object.freeze({english: true, tag: 'en-US', decimal: '.', group: ',', dollarSymbol: '$', dollarFirst: true, dollarGap: '', percentFirst: false, percentGap: ''});
const cache = new Map<string, Formats>();

function build(locale: string, tag: string): Formats {
  let number: Intl.NumberFormat, currency: Intl.NumberFormat, percent: Intl.NumberFormat;
  try {
    number = new Intl.NumberFormat(tag);
    currency = new Intl.NumberFormat(tag, {style: 'currency', currency: 'USD', currencyDisplay: 'narrowSymbol'});
    percent = new Intl.NumberFormat(tag, {style: 'percent'});
  } catch {
    number = new Intl.NumberFormat(locale);
    currency = new Intl.NumberFormat(locale, {style: 'currency', currency: 'USD', currencyDisplay: 'narrowSymbol'});
    percent = new Intl.NumberFormat(locale, {style: 'percent'});
  }
  const numberParts = number.formatToParts(1234567.5);
  const decimal = numberParts.find(part => part.type === 'decimal')?.value ?? '.';
  const group = numberParts.find(part => part.type === 'group')?.value ?? ',';
  // Where the dollar sign sits and what separates it from the digits, read from the locale's own pattern.
  const affix = (parts: Intl.NumberFormatPart[], type: 'currency' | 'percentSign') => {
    const at = parts.findIndex(part => part.type === type);
    const digits = parts.findIndex(part => part.type === 'integer');
    const first = at >= 0 && at < digits;
    const between = first ? parts.slice(at + 1, digits) : parts.slice(parts.findLastIndex(part => part.type === 'integer' || part.type === 'fraction') + 1, at);
    return {first, gap: between.filter(part => part.type === 'literal').map(part => part.value).join('')};
  };
  const dollar = affix(currency.formatToParts(1234.5), 'currency');
  const percentAffix = affix(percent.formatToParts(0.5), 'percentSign');
  return Object.freeze({english: false, tag, decimal, group, dollarSymbol: locale === 'fr' ? '$US' : 'US$',
    dollarFirst: dollar.first, dollarGap: dollar.gap, percentFirst: percentAffix.first, percentGap: percentAffix.gap});
}

function formats(state: I18nSnapshot = getSnapshot()): Formats {
  if (state.locale === 'en') return ENGLISH;
  const key = `${state.locale}|${state.formatTag}`;
  let value = cache.get(key);
  if (!value) {value = build(state.locale, state.formatTag); cache.set(key, value);}
  return value;
}

/** True while the page reads English. */
export function isEnglish(): boolean {return getSnapshot().locale === 'en';}
/** The tag dates and numbers use in the current language (`en-US` in English). */
export function formatTag(): string {return formats().tag;}
/** The decimal mark readers expect: `.` or `,`. */
export function decimalSeparator(): string {return formats().decimal;}

const ENGLISH_NUMBER = /^([+\-−]?)([<>~≈]?)([0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\.([0-9]+))?$/u;

/**
 * Rewrites a number already written the English way (`1,234.5`, `-0.25`,
 * `+12`, `<0.01`, `−3.00`) with the locale's separators: `1.234,5` in
 * pt-BR, `1 234,5` in French. Grouping follows the English text: an
 * ungrouped figure stays ungrouped. The sign character is kept. English
 * text and anything that is not a plain number come back unchanged.
 */
export function number(english: string): string {
  const f = formats();
  if (f.english) return english;
  const match = ENGLISH_NUMBER.exec(english);
  if (!match) return english;
  const [, sign = '', mark = '', whole = '', fraction] = match;
  return `${sign}${mark}${whole.replaceAll(',', f.group)}${fraction === undefined ? '' : `${f.decimal}${fraction}`}`;
}

function dollars(sign: string, digits: string, f: Formats): string {
  return f.dollarFirst ? `${sign}${f.dollarSymbol}${f.dollarGap}${digits}` : `${sign}${digits}${f.dollarGap}${f.dollarSymbol}`;
}
const ENGLISH_DOLLARS = /^([+\-−]?)\$([0-9][0-9,]*(?:\.[0-9]+)?)([KMBT]?)$/u;
const COMPACT_KEYS = {K: 'common.compactThousand', M: 'common.compactMillion', B: 'common.compactBillion', T: 'common.compactTrillion'} as const;

/**
 * A US dollar amount as the English app printed it (`$1,234.56`, `-$0.25`,
 * `+$5`, `$1.2B`) in the current language: `US$ 1.234,56` in pt-BR,
 * `1 234,56 $US` in French, `US$1.2 mil M` in es-419. English and anything
 * that is not a plain dollar amount come back unchanged.
 */
export function usd(english: string): string {
  const f = formats();
  if (f.english) return english;
  const match = ENGLISH_DOLLARS.exec(english);
  if (!match) return english;
  const [, sign = '', figure = '', unit = ''] = match;
  const digits = number(figure);
  if (!unit) return dollars(sign, digits, f);
  return dollars(sign, t(COMPACT_KEYS[unit as keyof typeof COMPACT_KEYS], {value: digits}), f);
}

/**
 * A percent as the English app printed it (`+1.23%`, `-0.50%`, `3%`) in the
 * current language: `+1,23 %` in French, `+1,23%` in pt-BR.
 */
export function percent(english: string): string {
  const f = formats();
  if (f.english) return english;
  const match = /^(.*)%$/u.exec(english);
  if (!match) return english;
  const digits = number(match[1]!);
  return f.percentFirst ? `%${f.percentGap}${digits}` : `${digits}${f.percentGap}%`;
}

/**
 * A count for a message: English text exactly as the English code wrote it
 * (`n.toLocaleString()` by default, so pass `'en-US'` or `'raw'` to match
 * other English calls), grouped in the locale's style elsewhere. Plural
 * choice still reads the number.
 */
export function count(value: number, english: string | readonly string[] | 'raw' | undefined = undefined): Shown {
  const f = formats();
  if (f.english) return new Shown(value, english === 'raw' ? String(value) : value.toLocaleString(english as string | string[] | undefined));
  return new Shown(value, number(value.toLocaleString('en-US', {maximumFractionDigits: 20})));
}
/** A whole number with grouping, as plain text (see `count` for the English argument). */
export function integer(value: number, english: string | readonly string[] | 'raw' | undefined = undefined): string {
  return count(value, english).text;
}

type DateInput = string | number | Date;
type EnglishLocales = string | readonly string[] | undefined;
const asDate = (value: DateInput) => value instanceof Date ? value : new Date(value);
/**
 * `toLocaleDateString` in the current language. English runs exactly the
 * original call (`englishLocales` is what the English code passed: `'en-US'`,
 * `'en-GB'`, `[]` or undefined for the browser's own style). Other languages
 * use the same options with their format tag.
 */
export function date(value: DateInput, englishLocales: EnglishLocales, options?: Intl.DateTimeFormatOptions): string {
  const f = formats();
  return asDate(value).toLocaleDateString(f.english ? englishLocales as string | string[] | undefined : f.tag, options);
}
/** `toLocaleTimeString` in the current language (see `date`). */
export function time(value: DateInput, englishLocales: EnglishLocales, options?: Intl.DateTimeFormatOptions): string {
  const f = formats();
  return asDate(value).toLocaleTimeString(f.english ? englishLocales as string | string[] | undefined : f.tag, options);
}
/** `toLocaleString` for a date and time in the current language (see `date`). */
export function dateTime(value: DateInput, englishLocales: EnglishLocales, options?: Intl.DateTimeFormatOptions): string {
  const f = formats();
  return asDate(value).toLocaleString(f.english ? englishLocales as string | string[] | undefined : f.tag, options);
}

// Typed amounts.

/**
 * A plain decimal (`12.5`, no grouping) for an amount field, in the reader's
 * decimal mark: `12.5` in English, `12,5` in French.
 */
export function decimalInput(plain: string): string {
  const f = formats();
  return f.english || f.decimal === '.' ? plain : plain.replace('.', f.decimal);
}

/**
 * Turns a typed amount into the plain `1234.5` form the exact parsers read.
 * English text comes back unchanged, so English parsing behaves exactly as
 * before. Elsewhere both decimal marks are accepted:
 *
 * - one mark on its own is the decimal mark: `12,5` and `12.5` are both
 *   twelve and a half, and `1.250` is 1.25, never 1250 (a typed amount is
 *   never silently multiplied);
 * - with both marks, the last is the decimal mark and the other must group
 *   thousands properly: `1.234,5` and `1,234.5` are both 1234.5;
 * - the same mark repeated must group thousands: `1.000.000` is a million;
 * - spaces (including no-break spaces) are ignored.
 *
 * Anything unclear comes back as typed, so the caller's own validation
 * rejects it rather than guessing.
 */
export function normalizeDecimalInput(typed: string): string {
  if (formats().english) return typed;
  const text = typed.trim().replace(/[\s  ]/gu, '');
  const commas = text.split(',').length - 1, dots = text.split('.').length - 1;
  if (!commas && !dots) return text;
  const grouped = (value: string, mark: string) => new RegExp(`^[0-9]{1,3}(?:[${mark}][0-9]{3})+$`, 'u').test(value);
  if (commas && dots) {
    const decimal = text.lastIndexOf(',') > text.lastIndexOf('.') ? ',' : '.';
    const group = decimal === ',' ? '.' : ',';
    const [whole = '', fraction = '', ...rest] = text.split(decimal);
    if (rest.length || !grouped(whole, group) || !/^[0-9]*$/u.test(fraction)) return typed;
    return `${whole.replaceAll(group, '')}.${fraction}`;
  }
  const mark = commas ? ',' : '.';
  if (commas + dots > 1) return grouped(text, mark) ? text.replaceAll(mark, '') : typed;
  const [whole = '', fraction = ''] = text.split(mark);
  if (!/^[0-9]*$/u.test(whole) || !/^[0-9]*$/u.test(fraction)) return typed;
  return `${whole}.${fraction}`;
}

/**
 * Removes the characters an amount field must not hold, keeping the
 * locale's decimal mark as well as `.` (English keeps exactly `[^0-9.]`).
 */
export function amountCharacters(typed: string): string {
  return formats().english ? typed.replace(/[^0-9.]/gu, '') : typed.replace(/[^0-9.,]/gu, '');
}
