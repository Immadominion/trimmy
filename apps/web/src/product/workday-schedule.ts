import type {CareerSummary, WorkdayJourney} from './practice-client';
import {t} from '../i18n/runtime';
import * as fmt from '../i18n/format';

/**
 * When an assignment opens, as message values: `when` is soon, tomorrow,
 * weekday (within the week) or date (after that), and `date` is the weekday
 * or the short date in the reader's language. Every sentence that says when
 * something opens is one whole message per language, choosing on `when`.
 */
export type OpensWhen = {readonly when: 'soon' | 'tomorrow' | 'weekday' | 'date'; readonly date: string};
export function opensWhen(opensAt: string, now = Date.now()): OpensWhen {
  const opens = new Date(opensAt), today = new Date(now);
  const startOfToday = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();
  const days = Math.round((new Date(opens.getFullYear(), opens.getMonth(), opens.getDate()).getTime() - startOfToday) / 86_400_000);
  if (days <= 0) return {when: 'soon', date: ''};
  if (days === 1) return {when: 'tomorrow', date: ''};
  if (days < 7) return {when: 'weekday', date: fmt.date(opens, undefined, {weekday: 'long'})};
  return {when: 'date', date: fmt.date(opens, undefined, {weekday: 'long', month: 'long', day: 'numeric'})};
}

export interface ScheduleNotice {readonly title: string; readonly body: string}

/** What the desk says when no assignment is open right now. Null while one is open or the API predates the schedule. */
export function scheduleNotice(journey: WorkdayJourney | null, now = Date.now()): ScheduleNotice | null {
  const schedule = journey?.schedule, next = journey?.upcoming;
  if (!schedule || !next || schedule.state === 'available' || schedule.state === 'done') return null;
  const values = {day: next.ordinal, title: next.title, ...opensWhen(next.opensAt, now)};
  if (schedule.state === 'tomorrow') return {title: t('career.schedule.todayDone'), body: t('career.schedule.opensWeekday', values)};
  const body = t('career.schedule.opens', values);
  if (schedule.holiday) return {title: t('career.schedule.holiday', {holiday: schedule.holiday}), body};
  return {title: t('career.schedule.weekend'), body};
}

/** The streak counts days with filed work; only a missed weekday ends it. */
export function streakLine(streak: CareerSummary['streak']): {readonly days: string; readonly note: string} {
  const days = t('career.streak.days', {days: streak.days});
  switch (streak.status) {
    case 'active': return {days, note: t('career.streak.active')};
    case 'at-risk': return {days, note: t('career.streak.atRisk')};
    case 'grace': return {days, note: t('career.streak.grace')};
    default: return {days: t('career.streak.none'), note: t('career.streak.start')};
  }
}
