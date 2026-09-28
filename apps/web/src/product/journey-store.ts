import {normalizePracticeApiBase, parsePracticeUuid} from './practice-client.js';
import type {PracticeStorage} from './practice-session.js';

/**
 * Browser-local first-day choices, the web equivalent of mobile's
 * SharedPreferences keys (`trimmy.entry.guest-chosen.v1`,
 * `trimmy.first-stock-setup.v1.<principal>`, `trimmy.entry.celebrated-order.v1`,
 * `trimmy.reminders.v1.<principal>`). The server still owns the launch
 * checkpoint; nothing here claims a trade, an account or a permission.
 */
export type ReminderChoice = 'daily' | 'occasional' | 'off';
export interface ReminderRecord {readonly version: 1; readonly choice: ReminderChoice; readonly savedAt: string}
export type JourneyPrincipal = `guest:${string}` | `account:${string}`;
export type FollowupStep = 0 | 1 | 2;

export class JourneyStorageError extends Error {
  readonly code = 'JOURNEY_STORAGE_UNAVAILABLE';
  constructor() {super('Your choice could not be saved in this browser.'); this.name = 'JourneyStorageError';}
}

export function journeyPrincipal(identity: {readonly accountId: string} | {readonly guestId: string}): JourneyPrincipal {
  return 'accountId' in identity ? `account:${parsePracticeUuid(identity.accountId)}` : `guest:${parsePracticeUuid(identity.guestId)}`;
}

export class JourneyStore {
  readonly #storage: PracticeStorage;
  readonly #prefix: string;
  readonly #now: () => number;
  constructor(storage: PracticeStorage, apiBase: string, now: () => number = Date.now) {
    this.#storage = storage; this.#now = now;
    this.#prefix = `trimmy.journey.v1:${encodeURIComponent(normalizePracticeApiBase(apiBase))}`;
  }
  get guestChoiceKey(): string {return `${this.#prefix}:guest-chosen`;}
  #read(key: string): string | null {try {return this.#storage.getItem(key);} catch {return null;}}
  #write(key: string, value: string): void {
    try {this.#storage.setItem(key, value); if (this.#storage.getItem(key) !== value) throw new Error();}
    catch {throw new JourneyStorageError();}
  }
  /** Only the labelled "Continue as guest" action may write true. Unreadable storage asks again. */
  guestChosen(): boolean {return this.#read(this.guestChoiceKey) === '1';}
  chooseGuest(): void {this.#write(this.guestChoiceKey, '1');}
  /** Signing in or out makes the next anonymous start ask again, as on mobile. */
  forgetGuestChoice(): void {
    if (!this.guestChosen()) return;
    try {this.#write(this.guestChoiceKey, '0');} catch { /* Best effort: the earlier explicit choice stays valid. */ }
  }
  celebratedOrder(): string | null {
    const value = this.#read(`${this.#prefix}:celebrated-order`);
    try {return value ? parsePracticeUuid(value) : null;} catch {return null;}
  }
  step(principal: JourneyPrincipal): FollowupStep | null {
    const value = this.#read(`${this.#prefix}:step:${principal}`);
    return value === '0' || value === '1' || value === '2' ? Number(value) as FollowupStep : null;
  }
  setStep(principal: JourneyPrincipal, step: FollowupStep): void {this.#write(`${this.#prefix}:step:${principal}`, String(step));}
  /** Records the confirmed order that was celebrated, then opens the follow-up. */
  acknowledgeCelebration(principal: JourneyPrincipal, orderId: string): void {
    this.#write(`${this.#prefix}:celebrated-order`, parsePracticeUuid(orderId));
    if ((this.step(principal) ?? 0) < 1) this.setStep(principal, 1);
  }
  reminder(principal: JourneyPrincipal): ReminderRecord | null {
    const raw = this.#read(`${this.#prefix}:reminders:${principal}`);
    if (!raw || raw.length > 200) return null;
    try {
      const value: unknown = JSON.parse(raw);
      if (!value || typeof value !== 'object') return null;
      const record = value as Record<string, unknown>;
      if (record['version'] !== 1 || !['daily', 'occasional', 'off'].includes(String(record['choice'])) ||
        typeof record['savedAt'] !== 'string' || !Number.isFinite(Date.parse(record['savedAt']))) return null;
      return {version: 1, choice: record['choice'] as ReminderChoice, savedAt: record['savedAt']};
    } catch {return null;}
  }
  saveReminder(principal: JourneyPrincipal, choice: ReminderChoice): ReminderRecord {
    const record: ReminderRecord = {version: 1, choice, savedAt: new Date(this.#now()).toISOString()};
    this.#write(`${this.#prefix}:reminders:${principal}`, JSON.stringify(record));
    return record;
  }
  /** "Welcome back" for an existing account whose guest desk stayed separate is shown once per account. */
  preservedNoticeSeen(principal: JourneyPrincipal): boolean {return this.#read(`${this.#prefix}:preserved-seen:${principal}`) === '1';}
  acknowledgePreservedNotice(principal: JourneyPrincipal): void {
    try {this.#write(`${this.#prefix}:preserved-seen:${principal}`, '1');} catch { /* It may show again; nothing else changes. */ }
  }
  /**
   * Why sign-in was opened, carried across the account workspace remount, as
   * mobile's `_skipIntroAfterAuth` and `_openFunding` do. A short-lived hint only:
   * it holds no credential and never grants access by itself.
   */
  setSignInIntent(intent: SignInIntent | null): void {
    try {this.#write(`${this.#prefix}:sign-in-intent`, intent ? JSON.stringify({intent, at: this.#now()}) : '');} catch { /* Hint only. */ }
  }
  consumeSignInIntent(): SignInIntent | null {
    const raw = this.#read(`${this.#prefix}:sign-in-intent`);
    if (!raw) return null;
    this.setSignInIntent(null);
    try {
      const value: unknown = JSON.parse(raw);
      if (!value || typeof value !== 'object') return null;
      const {intent, at} = value as Record<string, unknown>;
      const age = typeof at === 'number' ? this.#now() - at : -1;
      return (intent === 'app' || intent === 'fund') && age >= 0 && age < 15 * 60_000 ? intent : null;
    } catch {return null;}
  }
  /** A one-time message that must outlive a sign-out, such as the account-closure note. */
  setOneTimeNotice(text: string): void {
    try {this.#write(`${this.#prefix}:notice`, JSON.stringify({text: text.slice(0, 400), at: this.#now()}));} catch { /* Informational only. */ }
  }
  consumeOneTimeNotice(): string | null {
    const raw = this.#read(`${this.#prefix}:notice`);
    if (!raw) return null;
    try {this.#write(`${this.#prefix}:notice`, '');} catch { /* Shown at most until storage recovers. */ }
    try {
      const value = JSON.parse(raw) as {text?: unknown; at?: unknown};
      return typeof value.text === 'string' && typeof value.at === 'number' && this.#now() - value.at < 10 * 60_000 ? value.text : null;
    } catch {return null;}
  }
}
/** 'app': signed in from the app, so an unfinished account introduction is skipped. 'fund': open deposits next. */
export type SignInIntent = 'app' | 'fund';
