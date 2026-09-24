import { DomainError } from './index.js';
import { practiceCatalogActivityIds, practiceCatalogById } from './practice-catalog.generated.js';
import type { PracticeCatalogActivityId } from './practice-catalog.generated.js';

export type PracticeActivityId = PracticeCatalogActivityId;

export interface PracticeActivityProgress {
  readonly activityId: PracticeActivityId;
  readonly stage: 0 | 1 | 2 | 3 | 4;
  readonly selectedChoiceId: string | null;
  readonly corrected: boolean;
  readonly answerParts: Readonly<Record<string, string>>;
}

export interface PracticeCompletion {
  readonly activityId: PracticeActivityId;
  /** Original submitted choice, even when the learner subsequently corrected it. */
  readonly selectedChoiceId: string;
  readonly corrected: boolean;
  /** Canonical native UTC text; microseconds must never be rounded to milliseconds. */
  readonly completedAt: string | null;
  readonly importedFromLegacy: boolean;
}

/** Wire versions remain exact so historical mutation receipts can be replayed. */
export interface PracticeProgress {
  readonly version: 3 | 4 | 5 | 6;
  readonly active: PracticeActivityProgress | null;
  readonly completions: Readonly<Partial<Record<PracticeActivityId, PracticeCompletion>>>;
}

const activityIds = practiceCatalogActivityIds;
const updateFacts = Object.freeze([
  'dated-growth', 'lower-profit', 'trial-result', 'current-growth', 'all-customers',
]);
const sampleParts: Readonly<Record<string, readonly string[]>> = Object.freeze({
  amount: Object.freeze(['eight-of-ten', 'all']),
  group: Object.freeze(['testers', 'customers']),
});
const progressFields = Object.freeze(['version', 'active', 'completions']);
const activityFields = Object.freeze(['activityId', 'stage', 'selectedChoiceId', 'corrected', 'answerParts']);
const completionFields = Object.freeze(['activityId', 'selectedChoiceId', 'corrected', 'completedAt', 'importedFromLegacy']);
const maxBytes = 32_768;

function invalid(): never {
  throw new DomainError('INVALID_PRACTICE_PROGRESS', 'Practice progress is not a valid supported payload.');
}

/** Read data descriptors only: never invoke an input getter or its toJSON hook. */
function record(input: unknown, fields: readonly string[], exact = true): Record<string, unknown> {
  if (input === null || typeof input !== 'object' || Array.isArray(input)) invalid();
  const prototype: unknown = Object.getPrototypeOf(input);
  if (prototype !== Object.prototype && prototype !== null) invalid();
  const keys = Reflect.ownKeys(input);
  if (keys.length > fields.length || (exact && keys.length !== fields.length)) invalid();
  const copied: Record<string, unknown> = {};
  for (const key of keys) {
    if (typeof key !== 'string' || !fields.includes(key)) invalid();
    const descriptor = Object.getOwnPropertyDescriptor(input, key);
    if (!descriptor || !descriptor.enumerable || !Object.hasOwn(descriptor, 'value')) invalid();
    copied[key] = descriptor.value;
  }
  return copied;
}

function activityId(value: unknown, version: PracticeProgress['version']): PracticeActivityId {
  if (typeof value !== 'string' || !activityIds.includes(value as PracticeActivityId)) invalid();
  const id = value as PracticeActivityId;
  if (practiceCatalogById[id].introducedIn > version) invalid();
  return id;
}

function choiceId(id: PracticeActivityId, value: unknown): string {
  if (typeof value !== 'string' || !(practiceCatalogById[id].choiceIds as readonly string[]).includes(value)) invalid();
  return value;
}

function accepted(id: PracticeActivityId, choice: string): boolean {
  return (practiceCatalogById[id].acceptedChoiceIds as readonly string[]).includes(choice);
}

/** Match Dart DateTime.toUtc().toIso8601String(), including native microseconds. */
function nativeTimestamp(value: unknown): string {
  if (typeof value !== 'string') invalid();
  const match = /^(-?\d{4}|[+-]\d{6})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})\.(\d{3})(\d{3})?Z$/.exec(value);
  if (!match || match[0] !== value) invalid();
  const year = Number(match[1]);
  const yearText = Math.abs(year) <= 9999
    ? `${year < 0 ? '-' : ''}${Math.abs(year).toString().padStart(4, '0')}`
    : `${year < 0 ? '-' : '+'}${Math.abs(year).toString().padStart(6, '0')}`;
  if (match[1] !== yearText || match[8] === '000') invalid();
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4]);
  const minute = Number(match[5]);
  const second = Number(match[6]);
  const milliseconds = Number(match[7]);
  const microseconds = Number(match[8] ?? '0');
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (month < 1 || month > 12 || day < 1 || day > days[month - 1]! ||
      hour > 23 || minute > 59 || second > 59) invalid();
  // setUTCFullYear avoids Date.UTC's special interpretation of years 00–99.
  const date = new Date(0);
  date.setUTCFullYear(year, month - 1, day);
  date.setUTCHours(hour, minute, second, milliseconds);
  const epoch = date.getTime();
  if (!Number.isFinite(epoch) || (epoch === 8_640_000_000_000_000 && microseconds !== 0)) invalid();
  return value;
}

function answerParts(id: PracticeActivityId, input: unknown): Readonly<Record<string, string>> {
  const fields = id === 'check-the-sample' ? Object.keys(sampleParts)
    : id === 'prepare-the-update' ? updateFacts : [];
  const source = record(input, fields, false);
  const parts: Record<string, string> = {};
  for (const key of Object.keys(source)) {
    const value = source[key];
    if (typeof value !== 'string' || (id === 'check-the-sample'
      ? !sampleParts[key]!.includes(value)
      : value !== 'included' && value !== 'excluded')) invalid();
    parts[key] = value;
  }
  if (id === 'prepare-the-update' && Object.values(parts).filter(value => value === 'included').length > 3) invalid();
  return Object.freeze(parts);
}

function combinedChoice(id: PracticeActivityId, parts: Readonly<Record<string, string>>): string | null {
  if (id === 'check-the-sample') {
    return Object.keys(parts).length === 2 ? `${parts['amount']}-${parts['group']}` : null;
  }
  const included = updateFacts.filter(fact => parts[fact] === 'included');
  return included.length === 3 ? included.join('+') : null;
}

function unlocked(id: PracticeActivityId, completions: PracticeProgress['completions']): boolean {
  const prerequisite = practiceCatalogById[id].prerequisiteId;
  return prerequisite === null || Object.hasOwn(completions, prerequisite);
}

function parse(input: unknown): PracticeProgress {
  const source = record(input, progressFields);
  const version = source['version'];
  if (version !== 3 && version !== 4 && version !== 5 && version !== 6) invalid();
  const records = record(source['completions'], activityIds, false);
  const completions: Partial<Record<PracticeActivityId, PracticeCompletion>> = {};
  for (const key of Object.keys(records)) {
    const item = record(records[key], completionFields);
    const id = activityId(item['activityId'], version);
    const choice = choiceId(id, item['selectedChoiceId']);
    const corrected = item['corrected'];
    const imported = item['importedFromLegacy'];
    if (id !== key || typeof corrected !== 'boolean' || corrected === accepted(id, choice) ||
        typeof imported !== 'boolean' || (imported && id !== 'check-the-date')) invalid();
    const time = item['completedAt'];
    if (time === null && !imported) invalid();
    completions[id] = Object.freeze({
      activityId: id, selectedChoiceId: choice, corrected,
      completedAt: time === null ? null : nativeTimestamp(time), importedFromLegacy: imported,
    });
  }
  for (const id of activityIds) {
    if (Object.hasOwn(completions, id) && !unlocked(id, completions)) invalid();
  }
  let active: PracticeActivityProgress | null = null;
  if (source['active'] !== null) {
    const task = record(source['active'], activityFields);
    const id = activityId(task['activityId'], version);
    const stage = task['stage'];
    const corrected = task['corrected'];
    const choice = task['selectedChoiceId'] === null ? null : choiceId(id, task['selectedChoiceId']);
    if (typeof stage !== 'number' || !Number.isInteger(stage) || stage < 0 || stage > 4 ||
        typeof corrected !== 'boolean' || !unlocked(id, completions)) invalid();
    const parts = answerParts(id, task['answerParts']);
    if ((id === 'check-the-sample' || id === 'prepare-the-update') && combinedChoice(id, parts) !== choice) invalid();
    if ((stage <= 2 && corrected) || (stage >= 3 && choice === null) ||
        (stage === 3 && (!corrected || accepted(id, choice!))) ||
        (stage === 4 && (corrected === accepted(id, choice!) || !Object.hasOwn(completions, id)))) invalid();
    // An active replay may differ from its immutable first completion.
    active = Object.freeze({activityId: id, stage: stage as PracticeActivityProgress['stage'], selectedChoiceId: choice, corrected, answerParts: parts});
  }
  const progress = Object.freeze({version, active, completions: Object.freeze(completions)});
  if (new TextEncoder().encode(canonical(progress)).byteLength > maxBytes) invalid();
  return progress;
}

/**
 * Parse an already-decoded JSON value; never modify or freeze caller-owned data.
 * A transport must separately bound raw bytes and reject duplicate JSON keys if
 * it requires that guarantee: duplicate keys are lost before this function runs.
 */
export function parsePracticeProgress(input: unknown): PracticeProgress {
  try {
    return parse(input);
  } catch (error) {
    if (error instanceof DomainError && error.code === 'INVALID_PRACTICE_PROGRESS') throw error;
    // Reflection on a hostile/revoked object must not leak implementation errors.
    return invalid();
  }
}

function canonical(value: unknown): string {
  if (value === null || typeof value !== 'object') return JSON.stringify(value)!;
  const fields = Object.keys(value).sort().map(key =>
    `${JSON.stringify(key)}:${canonical((value as Record<string, unknown>)[key])}`);
  return `{${fields.join(',')}}`;
}

/** Deterministic JSON: sorted object keys, exact string escaping, no timestamp coercion. */
export function canonicalPracticeProgress(progress: PracticeProgress): string {
  return canonical(parsePracticeProgress(progress));
}

/** New completions and replay state may change; prior first-completion evidence may not. */
export function assertPracticeHistoryPreserved(previous: PracticeProgress, next: PracticeProgress): void {
  const before = parsePracticeProgress(previous);
  const after = parsePracticeProgress(next);
  for (const id of activityIds) {
    const prior = before.completions[id];
    if (prior && (!after.completions[id] || canonical(prior) !== canonical(after.completions[id]))) {
      throw new DomainError('PRACTICE_HISTORY_CONFLICT', 'A saved first completion cannot be removed or replaced.');
    }
  }
}
