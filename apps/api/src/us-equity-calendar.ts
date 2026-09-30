/**
 * US equity trading sessions in New York time, as Ondo Global Markets runs them
 * (https://docs.ondo.finance/api-reference/status/get-current-market-status):
 * overnight 20:05 the evening before to 03:55, premarket 04:01 to 09:29, regular
 * 09:31 to 15:59 and postmarket 16:01 to 19:59, with short pauses between. NYSE
 * holidays close the day. Weekends and holidays are "offhours", which only some
 * tokens trade: from 20:05 after the last session until the next overnight
 * session opens. Early closes end regular trading at 13:00 and extended trading
 * at 17:00 (an assumption Ondo does not document; its live status overrides it).
 */
export type UsSession = 'overnight' | 'premarket' | 'regular' | 'postmarket' | 'offhours';
export const US_SESSIONS: readonly UsSession[] = Object.freeze(['overnight', 'premarket', 'regular', 'postmarket', 'offhours']);

/**
 * NYSE full-day closures, New York dates. https://www.nyse.com/markets/hours-calendars
 * infra/migrations/0036_weekday_workdays.sql seeds the same dates for the career desk; a test keeps them equal.
 */
export const HOLIDAYS: ReadonlySet<string> = new Set([
  '2026-01-01', '2026-01-19', '2026-02-16', '2026-04-03', '2026-05-25', '2026-06-19', '2026-07-03', '2026-09-07',
  '2026-11-26', '2026-12-25',
  '2027-01-01', '2027-01-18', '2027-02-15', '2027-03-26', '2027-05-31', '2027-06-18', '2027-07-05', '2027-09-06',
  '2027-11-25', '2027-12-24',
  '2028-01-17', '2028-02-21', '2028-04-14', '2028-05-29', '2028-06-19', '2028-07-04', '2028-09-04', '2028-11-23',
  '2028-12-25',
]);
/** NYSE 13:00 early closes. */
const EARLY_CLOSES = new Set(['2026-11-27', '2026-12-24', '2027-11-26', '2028-07-03', '2028-11-24']);
/** The last New York date the tables above cover; later dates fall back to weekends only. */
export const US_CALENDAR_COVERS_UNTIL = '2028-12-31';

export interface UsSessionInterval {
  readonly session: UsSession;
  readonly start: number;
  readonly end: number;
}

export interface UsMarketMoment {
  /** The session in force, or null between sessions. */
  readonly session: UsSession | null;
  /** Between two sessions: a pause (minutes long) or closed (longer, e.g. after an early close). */
  readonly gap: 'pause' | 'closed' | null;
  /** When the current session or gap ends. */
  readonly changesAt: number;
}

const MINUTE = 60_000;
const DAY = 86_400_000;
const PAUSE_LIMIT = 10 * MINUTE;
const newYork = new Intl.DateTimeFormat('en-US', {
  timeZone: 'America/New_York', hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit',
});

/** Minutes New York is behind UTC at this instant (240 in summer, 300 in winter). */
function newYorkOffsetMinutes(at: number): number {
  const parts = Object.fromEntries(newYork.formatToParts(new Date(at)).map(part => [part.type, part.value]));
  const wall = Date.UTC(Number(parts['year']), Number(parts['month']) - 1, Number(parts['day']), Number(parts['hour']), Number(parts['minute']));
  return Math.round((Math.floor(at / MINUTE) * MINUTE - wall) / MINUTE);
}

/** UTC milliseconds of a New York wall-clock time on a New York date (days since epoch). */
function newYorkTime(day: number, hour: number, minute: number): number {
  const wall = day * DAY + (hour * 60 + minute) * MINUTE;
  const first = wall + newYorkOffsetMinutes(wall + 5 * 60 * MINUTE) * MINUTE;
  return wall + newYorkOffsetMinutes(first) * MINUTE;
}

const isoDate = (day: number) => new Date(day * DAY).toISOString().slice(0, 10);
const weekday = (day: number) => new Date(day * DAY).getUTCDay();
export const isUsTradingDay = (day: number) => weekday(day) !== 0 && weekday(day) !== 6 && !HOLIDAYS.has(isoDate(day));

/** The New York calendar day (days since epoch) containing this instant. */
function newYorkDay(at: number): number {
  return Math.floor((at - newYorkOffsetMinutes(at) * MINUTE) / DAY);
}

/** Every session interval that touches [from, to], in order. */
export function usSessionIntervals(from: number, to: number): readonly UsSessionInterval[] {
  const intervals: UsSessionInterval[] = [];
  const first = newYorkDay(from) - 4;
  const last = newYorkDay(to) + 4;
  for (let day = first; day <= last; day += 1) {
    if (!isUsTradingDay(day)) continue;
    const early = EARLY_CLOSES.has(isoDate(day));
    intervals.push(
      {session: 'overnight', start: newYorkTime(day - 1, 20, 5), end: newYorkTime(day, 3, 55)},
      {session: 'premarket', start: newYorkTime(day, 4, 1), end: newYorkTime(day, 9, 29)},
      {session: 'regular', start: newYorkTime(day, 9, 31), end: early ? newYorkTime(day, 13, 0) : newYorkTime(day, 15, 59)},
      {session: 'postmarket', start: early ? newYorkTime(day, 13, 1) : newYorkTime(day, 16, 1), end: early ? newYorkTime(day, 17, 0) : newYorkTime(day, 19, 59)},
    );
    // Offhours: from 20:05 after this trading day until the next overnight session,
    // when the following day does not trade.
    if (!isUsTradingDay(day + 1)) {
      let next = day + 1;
      while (!isUsTradingDay(next) && next <= last + 7) next += 1;
      intervals.push({session: 'offhours', start: newYorkTime(day, 20, 5), end: newYorkTime(next - 1, 20, 5)});
    }
  }
  return intervals.sort((a, b) => a.start - b.start).filter(item => item.end > from && item.start <= to);
}

/** The session in force at an instant, or the gap it falls in. */
export function usMarketMoment(at: number): UsMarketMoment {
  const intervals = usSessionIntervals(at - 7 * DAY, at + 14 * DAY);
  const current = intervals.find(item => item.start <= at && at < item.end);
  if (current) return {session: current.session, gap: null, changesAt: current.end};
  const next = intervals.find(item => item.start > at);
  const previous = [...intervals].reverse().find(item => item.end <= at);
  const changesAt = next?.start ?? at + DAY;
  const length = changesAt - (previous?.end ?? at);
  return {session: null, gap: length <= PAUSE_LIMIT ? 'pause' : 'closed', changesAt};
}

export interface UsTradingState {
  readonly status: 'open' | 'paused' | 'closed';
  /** The session in force, whether or not this asset trades in it. */
  readonly session: UsSession | null;
  /** When this asset can next trade (null while open). */
  readonly nextOpenAt: number | null;
  /** When the session this asset trades in ends (null unless open). */
  readonly closesAt: number | null;
}

/** Whether an asset that trades only in these sessions can trade at this instant, and when it next can. */
export function usTradingState(at: number, sessions: ReadonlySet<UsSession>): UsTradingState {
  const intervals = usSessionIntervals(at - 7 * DAY, at + 14 * DAY);
  const moment = usMarketMoment(at);
  const current = intervals.find(item => item.start <= at && at < item.end);
  if (current && sessions.has(current.session)) return {status: 'open', session: current.session, nextOpenAt: null, closesAt: current.end};
  const next = intervals.find(item => item.start > at && sessions.has(item.session));
  const nextOpenAt = next?.start ?? null;
  // A short pause between two sessions this asset trades in reads as paused, not closed.
  const paused = moment.gap === 'pause' && nextOpenAt === moment.changesAt &&
    intervals.some(item => item.end <= at && item.end >= at - PAUSE_LIMIT && sessions.has(item.session));
  return {status: paused ? 'paused' : 'closed', session: moment.session, nextOpenAt, closesAt: null};
}
