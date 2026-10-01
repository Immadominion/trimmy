import type {CareerSummary, WorkdayHoliday, WorkdayJourney} from './practice-client';

const HOLIDAY_NAMES: Readonly<Record<WorkdayHoliday, string>> = {
  'new-years-day': 'New Year’s Day', 'martin-luther-king-jr-day': 'Martin Luther King Jr. Day', 'washingtons-birthday': 'Washington’s Birthday',
  'good-friday': 'Good Friday', 'memorial-day': 'Memorial Day', 'juneteenth': 'Juneteenth', 'independence-day': 'Independence Day',
  'labor-day': 'Labor Day', 'thanksgiving-day': 'Thanksgiving', 'christmas-day': 'Christmas',
};

/** "tomorrow", a weekday name within the week, or a short date after that. */
export function opensLabel(opensAt: string, now = Date.now()): string {
  const opens = new Date(opensAt), today = new Date(now);
  const startOfToday = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime();
  const days = Math.round((new Date(opens.getFullYear(), opens.getMonth(), opens.getDate()).getTime() - startOfToday) / 86_400_000);
  if (days <= 0) return 'soon';
  if (days === 1) return 'tomorrow';
  if (days < 7) return `on ${opens.toLocaleDateString(undefined, {weekday: 'long'})}`;
  return `on ${opens.toLocaleDateString(undefined, {weekday: 'long', month: 'long', day: 'numeric'})}`;
}

export interface ScheduleNotice {readonly title: string; readonly body: string}

/** What the desk says when no assignment is open right now. Null while one is open or the API predates the schedule. */
export function scheduleNotice(journey: WorkdayJourney | null, now = Date.now()): ScheduleNotice | null {
  const schedule = journey?.schedule, next = journey?.upcoming;
  if (!schedule || !next || schedule.state === 'available' || schedule.state === 'done') return null;
  const opens = `Day ${next.ordinal}, ${next.title}, opens ${opensLabel(next.opensAt, now)}.`;
  if (schedule.state === 'tomorrow') return {title: 'That’s today’s work.', body: `${opens} One new assignment each weekday, like Wall Street.`};
  if (schedule.holiday) return {title: `Wall Street is closed for ${HOLIDAY_NAMES[schedule.holiday]}.`, body: opens};
  return {title: 'Wall Street is closed for the weekend.', body: opens};
}

/** The streak counts days with filed work; only a missed weekday ends it. */
export function streakLine(streak: CareerSummary['streak']): {readonly days: string; readonly note: string} {
  const days = `${streak.days}-day streak`;
  switch (streak.status) {
    case 'active': return {days, note: 'Today’s work is in.'};
    case 'at-risk': return {days, note: 'File today’s assignment to keep it going.'};
    case 'grace': return {days, note: 'The market is closed today. Your streak is safe.'};
    default: return {days: 'No streak yet', note: 'File an assignment on a weekday to start one.'};
  }
}
