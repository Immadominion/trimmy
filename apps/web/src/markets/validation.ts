export class StockResearchError extends Error {
  constructor(readonly code: string) { super(code); this.name = 'StockResearchError'; }
}
export function invalid(): never { throw new StockResearchError('STOCK_RESPONSE_INVALID'); }
export function record(value: unknown, keys: readonly string[]): Record<string, unknown> {
  if (value === null || typeof value !== 'object' || Array.isArray(value) || Object.getPrototypeOf(value) !== Object.prototype) invalid();
  const own = Reflect.ownKeys(value);
  if (own.length !== keys.length || own.some(key => typeof key !== 'string' || !keys.includes(key))) invalid();
  const descriptors = Object.getOwnPropertyDescriptors(value);
  if (Object.values(descriptors).some(descriptor => !Object.hasOwn(descriptor, 'value'))) invalid();
  return value as Record<string, unknown>;
}
export function text(value: unknown, max = 160): string {
  if (typeof value !== 'string' || !value.length || value.length > max || value.trim() !== value || /[\u0000-\u001f\u007f]/u.test(value)) invalid();
  return value;
}
export const optionalText = (value: unknown, max = 160): string | null => value === null ? null : text(value, max);
export function matches(value: string, pattern: RegExp): boolean { return pattern.exec(value)?.[0] === value; }
export function assetId(value: unknown): string {
  const result = text(value, 100); if (!matches(result, /^[a-z0-9]+(?:-[a-z0-9]+)*$/u)) invalid(); return result;
}
export function variantId(value: unknown): string {
  const result = text(value); if (!matches(result, /^[A-Za-z0-9][A-Za-z0-9._:-]*$/u)) invalid(); return result;
}
export function mint(value: unknown): string {
  const result = text(value, 44); if (result.length < 32) invalid();
  const alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  let number = 0n; let zeroes = 0;
  for (let i = 0; i < result.length; i++) {
    const digit = alphabet.indexOf(result[i]!); if (digit < 0) invalid();
    number = number * 58n + BigInt(digit); if (i === zeroes && result[i] === '1') zeroes++;
  }
  let bytes = 0; while (number > 0n) { bytes++; number >>= 8n; }
  if (bytes + zeroes !== 32) invalid(); return result;
}
export function integer(value: unknown, min: number, max: number): number {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < min || value > max) invalid(); return value;
}
export function metric(value: unknown): number | null {
  if (value === null) return null;
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 || value > Number.MAX_SAFE_INTEGER) invalid(); return value;
}
export function timestamp(value: unknown): string {
  const result = text(value, 32);
  if (!matches(result, /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/u)) invalid();
  const date = Date.parse(result); if (!Number.isFinite(date) || new Date(date).toISOString() !== result) invalid(); return result;
}
export function sourceUrl(value: unknown): string {
  const result = text(value, 2048);
  try {
    const url = new URL(result);
    if (url.protocol !== 'https:' || !url.hostname || url.username || url.password || url.hash) invalid();
  } catch { invalid(); }
  return result;
}
export function list<T>(value: unknown, max: number, parse: (item: unknown) => T): readonly T[] {
  if (!Array.isArray(value) || Object.getPrototypeOf(value) !== Array.prototype || value.length > max ||
      Reflect.ownKeys(value).length !== value.length + 1) invalid();
  for (let i = 0; i < value.length; i++) {
    const descriptor = Object.getOwnPropertyDescriptor(value, i);
    if (!descriptor || !Object.hasOwn(descriptor, 'value')) invalid();
  }
  return Object.freeze(value.map(parse));
}
export function unique<T>(items: Iterable<T>): void {
  const array = [...items]; if (new Set(array).size !== array.length) invalid();
}
export function schema(value: unknown): void {
  if (!Number.isInteger(value)) invalid(); if (value !== 1) throw new StockResearchError('STOCK_UNSUPPORTED_SCHEMA');
}
export function rawAmount(value: unknown): string {
  const result = text(value, 20);
  if (!matches(result, /^[1-9][0-9]*$/u) || BigInt(result) > 18446744073709551615n) invalid(); return result;
}
/** Exact decimal placement for raw token units, never a scaled share conversion. */
export function formatRawTokenUnits(raw: string, decimals: number): string {
  rawAmount(raw); integer(decimals, 0, 255); if (decimals === 0) return raw;
  const padded = raw.padStart(decimals + 1, '0'); return padded.slice(0, -decimals) + '.' + padded.slice(-decimals);
}
