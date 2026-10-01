import type {ReminderChoice} from './journey-store.js';
import {t} from '../i18n/runtime.js';

/**
 * Browsers cannot wake a closed tab without a push service, and Trimmy has no
 * web push. Instead of requesting a notification permission it could not honour,
 * the web offers the same schedule as mobile ("Around 7 PM, your time" daily, or
 * Monday, Wednesday and Friday) as a calendar event the person adds themselves.
 * Floating local times keep "7 PM" in the calendar's own time zone. The event's
 * title, description, alarm text and file name are in the page's language.
 */
const days = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'] as const;
function pad(value: number): string {return String(value).padStart(2, '0');}
function localDate(date: Date): string {return `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}`;}
function utcStamp(date: Date): string {
  return `${date.getUTCFullYear()}${pad(date.getUTCMonth() + 1)}${pad(date.getUTCDate())}T${pad(date.getUTCHours())}${pad(date.getUTCMinutes())}${pad(date.getUTCSeconds())}Z`;
}
/**
 * RFC 5545 TEXT escaping (section 3.3.11) for catalog copy in any language and
 * an HTTPS URL: backslash, semicolon, comma and line breaks are escaped; the
 * file is UTF-8 and folding never splits a character (see `fold`).
 */
function text(value: string): string {return value.replace(/\\/gu, '\\\\').replace(/;/gu, '\\;').replace(/,/gu, '\\,').replace(/\r\n|\r|\n/gu, '\\n');}
/**
 * Lines longer than 75 octets continue on the next line after a single space.
 * Cuts fall between characters, never inside a UTF-8 sequence or a surrogate pair.
 */
function fold(line: string): string {
  const out: string[] = []; let rest = line;
  while (new TextEncoder().encode(rest).length > 75) {
    let cut = 75; while (new TextEncoder().encode(rest.slice(0, cut)).length > 75) cut--;
    const last = rest.charCodeAt(cut - 1); if (last >= 0xd800 && last <= 0xdbff) cut--;
    out.push(rest.slice(0, cut)); rest = ` ${rest.slice(cut)}`;
  }
  out.push(rest); return out.join('\r\n');
}
/** The first occurrence at or after now: today at 7 PM if it is still ahead, otherwise the next matching day. */
export function firstReminderDate(choice: Exclude<ReminderChoice, 'off'>, now: Date): Date {
  const candidate = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 19, 0, 0, 0);
  if (candidate.getTime() <= now.getTime()) candidate.setDate(candidate.getDate() + 1);
  if (choice === 'occasional') while (![1, 3, 5].includes(candidate.getDay())) candidate.setDate(candidate.getDate() + 1);
  return candidate;
}
export function reminderCalendar(choice: Exclude<ReminderChoice, 'off'>, options: {now: Date; url: string; uid: string}): string {
  const url = new URL(options.url);
  if (url.protocol !== 'https:' && url.hostname !== '127.0.0.1' && url.hostname !== 'localhost') throw new Error('Reminder links must use HTTPS.');
  const start = firstReminderDate(choice, options.now);
  const rule = choice === 'daily' ? 'FREQ=DAILY' : `FREQ=WEEKLY;BYDAY=${[1, 3, 5].map(day => days[day]).join(',')}`;
  const lines = [
    'BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Trimmy//Practice reminder//EN', 'CALSCALE:GREGORIAN', 'METHOD:PUBLISH',
    'BEGIN:VEVENT', `UID:${options.uid}@trimmy.xyz`, `DTSTAMP:${utcStamp(options.now)}`,
    `DTSTART:${localDate(start)}T190000`, 'DURATION:PT15M', `RRULE:${rule}`,
    `SUMMARY:${text(t('career.reminder.title'))}`,
    `DESCRIPTION:${text(t('career.reminder.description', {url: url.href}))}`,
    `URL:${url.href}`, 'TRANSP:TRANSPARENT',
    'BEGIN:VALARM', 'ACTION:DISPLAY', `DESCRIPTION:${text(t('career.reminder.alarm'))}`, 'TRIGGER:PT0M', 'END:VALARM',
    'END:VEVENT', 'END:VCALENDAR',
  ];
  return `${lines.map(fold).join('\r\n')}\r\n`;
}
/** The downloaded file's name in the page's language: plain ASCII, so every system keeps it. */
export function reminderFileName(choice: Exclude<ReminderChoice, 'off'>): string {
  const name = t(choice === 'daily' ? 'career.reminder.fileDaily' : 'career.reminder.fileWeekly');
  return /^[a-z0-9-]+\.ics$/u.test(name) ? name : choice === 'daily' ? 'trimmy-daily-reminder.ics' : 'trimmy-reminder-mon-wed-fri.ics';
}
/** Starts a local download. Nothing is sent to Trimmy or a calendar provider. */
export function downloadReminderCalendar(choice: Exclude<ReminderChoice, 'off'>): boolean {
  try {
    const url = `${window.location.origin}/#career`;
    const body = reminderCalendar(choice, {now: new Date(), url, uid: crypto.randomUUID()});
    const blob = new Blob([body], {type: 'text/calendar;charset=utf-8'});
    const href = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = href; link.download = reminderFileName(choice);
    link.rel = 'noopener'; document.body.append(link); link.click(); link.remove();
    window.setTimeout(() => URL.revokeObjectURL(href), 30_000);
    return true;
  } catch {return false;}
}
