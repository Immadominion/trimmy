import type {AreaMessages} from '../types';

/**
 * Career: the Career tab (intern street, next assignment, progress dialog,
 * milestones, promotion and trade comments), one workday assignment, the
 * daily desk story and desk week, the weekday schedule, and the downloadable
 * calendar reminder. Workday titles, briefs, prompts, choices, story text,
 * districts and mission titles come from the server and are not here.
 */
export default {
  // Shared across Career screens.
  'career.title': 'Career',
  /** "Day 3 · First days": a day number and a server-authored district or assignment title. */
  'career.dayWith': 'Day {day} · {name}',
  'career.day': 'Day {day}',
  'career.retry': 'Retry',
  'career.saving': 'Saving…',
  'career.backToCareer': 'Back to Career',
  /** A back link with an arrow. */
  'career.backToCareerArrow': '← Back to Career',
  /** Trims are Trimmy's points; the name is never translated. */
  'career.trims': '{count} Trims',
  'career.trimsGained': '+{count} Trims',

  // Rank names, in the order players reach them.
  'career.rank.rookie': 'Rookie',
  'career.rank.analyst': 'Analyst',
  'career.rank.trader': 'Trader',
  'career.rank.seniorTrader': 'Senior Trader',
  'career.rank.partner': 'Partner',
  'career.rank.legend': 'Legend',

  // Assignments on the desk and the Career tab.
  'career.assignments.loading': 'Opening your assignments…',
  'career.assignments.loadFailed': 'Your assignments couldn’t load.',
  'career.assignments.refreshFailed': 'Your assignments couldn’t refresh.',
  'career.assignments.start': 'Start assignment',
  'career.assignments.continue': 'Continue assignment',
  'career.assignments.pendingSave': 'An earlier save needs checking.',
  'career.assignments.checkSaved': 'Check saved work',

  // Career tab header.
  'career.sound.mute': 'Mute Career sounds',
  'career.sound.enable': 'Enable Career sounds',
  'career.sound.on': 'Sound on',
  'career.sound.off': 'Sound off',

  // The next-assignment panel beside the street.
  'career.next.label': 'Your next assignment',
  'career.next.stagePin': 'Pin the evidence',
  'career.next.stageCall': 'Make your call',
  'career.next.stageFile': 'File your update',
  /** Read by screen readers after a finished stage. */
  'career.next.stageSaved': ', saved',
  'career.next.allFiled': 'All filed.',
  'career.next.allFiledBody': 'Your {count} assignments are saved. Open a completed day to revisit your work.',
  'career.next.loading': 'Opening your path…',
  'career.next.filedCount': '{done} of {total} assignments filed',

  // The progress dialog (rank, Trims, streak, activity, milestones).
  'career.progress.title': 'Your progress',
  'career.progress.close': 'Close progress',
  'career.progress.rankStale': 'Your rank couldn’t refresh.',
  'career.progress.rankStaleShowing': 'Your rank couldn’t refresh. Showing the last confirmed progress.',
  'career.progress.loading': 'Getting your progress…',
  /** The player's Trims total in bold. */
  'career.progress.trimsTotal': '<strong>{count}</strong> Trims',
  'career.progress.meter': 'Trims toward next rank',
  /** {rank} is the next rank's name. */
  'career.progress.toNextRank': '{count} Trims to {rank}',
  'career.progress.finishPromotion': 'Finish your promotion milestone.',
  'career.progress.soFar': 'Your career so far',
  'career.activity.title': 'Activity this week',
  'career.activity.recorded': 'Days with recorded activity',
  /** Tooltip on one day of the week; {date} is that day. */
  'career.activity.dayActive': '{date}: Active',
  'career.activity.dayInactive': '{date}: No recorded activity',

  // Streak, under the Trims meter.
  'career.streak.days': '{days}-day streak',
  'career.streak.none': 'No streak yet',
  'career.streak.active': 'Today’s work is in.',
  'career.streak.atRisk': 'File today’s assignment to keep it going.',
  'career.streak.grace': 'The market is closed today. Your streak is safe.',
  'career.streak.start': 'File an assignment on a weekday to start one.',

  // Career milestones and promotion.
  'career.milestones.title': 'Career milestones',
  'career.milestones.commentTitle': 'Comment on your trade',
  'career.milestones.writeComment': 'Write a comment',
  'career.milestones.findStock': 'Find a stock',
  'career.milestones.confirming': 'Confirming…',
  /** Button that claims a promotion; {rank} is the new rank's name. */
  'career.milestones.become': 'Become {rank}',
  'career.milestones.complete': 'Complete',
  'career.milestones.locked': 'Locked',
  'career.milestones.ready': 'Ready',
  'career.milestones.refreshBeforePromotion': 'Refresh Career before claiming this promotion.',
  'career.milestones.promotionNotPrepared': 'Your promotion could not be prepared. Try again.',
  'career.milestones.careerChanged': 'Your career changed. Refresh Career and try again.',
  'career.milestones.promotionNotSaved': 'Your promotion could not be saved. Try again.',
  'career.milestones.needsHeldBuy': 'This mission needs a confirmed paper buy you still hold. Choose a stock when you are ready.',
  /** The three Career missions, by id; the English is exactly what the API sends. "How" is the instruction under the title. */
  'career.mission.firstPaperBuy': 'Buy your first stock',
  'career.mission.firstPaperBuyHow': 'Complete one paper buy.',
  'career.mission.writeAReason': 'Write your reason',
  'career.mission.writeAReasonHow': 'Add a reason to a paper buy you still hold.',
  'career.mission.holdThroughRedDay': 'Hold through a red day',
  'career.mission.holdThroughRedDayHow': 'Hold a stock through a verified red Wall Street day.',
  /** {rank} is the new rank's name. */
  'career.promotion.unlocked': '{rank} unlocked',
  /** {rank} is the rank id (analyst, trader, senior-trader, partner, legend); {name} its name. */
  'career.promotion.title': '{rank, select, analyst {You’re an {name}!} other {You’re a {name}!}}',
  'career.promotion.subtitle': 'A new chapter on the floor.',
  'career.promotion.from': 'From',
  'career.promotion.newRank': 'New rank',
  'career.promotion.earned': 'Earned',

  // Comment on a paper buy (the trade reason).
  'career.reason.close': 'Close',
  /** {name} is a company name or token symbol; {shares} the shares still held. */
  'career.reason.held': '{name} · {shares} shares held',
  'career.reason.title': 'Write your reason',
  'career.reason.savedTitle': 'Reason saved',
  'career.reason.missionRecorded': 'Mission recorded',
  'career.reason.prompt': 'What made you buy?',
  'career.reason.placeholder': 'Your take on this stock…',
  'career.reason.closeRefresh': 'Close and refresh',
  'career.reason.retry': 'Retry reason',
  'career.reason.save': 'Save reason',
  'career.reason.disclosure': 'Paper trade comment. Who can see it follows your comment privacy in Settings.',
  'career.reason.error.invalid': 'Use one line and 180 characters or fewer.',
  'career.reason.error.offline': 'You are offline. Your reason was not saved. Try again.',
  'career.reason.error.timeout': 'Saving took too long. Try again.',
  'career.reason.error.session': 'Refresh your session before saving this reason.',
  'career.reason.error.profile': 'Finish setting up your profile before saving this reason.',
  'career.reason.error.orderMissing': 'This paper buy was not found. Refresh your desk.',
  'career.reason.error.buyRequired': 'A reason can be added only to a confirmed paper buy.',
  'career.reason.error.positionRequired': 'You need to still hold this stock before saving a reason.',
  'career.reason.error.exists': 'This paper buy already has a reason. Refresh your Career.',
  'career.reason.error.conflict': 'This retry could not be matched. Refresh your Career.',
  'career.reason.error.busy': 'Reasons are busy right now. Try again shortly.',
  'career.reason.error.default': 'Your reason was not saved. Try again.',

  // When the next workday opens. {when} is soon, tomorrow, weekday (on Monday) or date (on Monday, October 5);
  // {date} is the weekday or the date, already written in the reader's language.
  'career.schedule.todayDone': 'That’s today’s work.',
  'career.schedule.weekend': 'Wall Street is closed for the weekend.',
  /** US market holidays, by id. */
  'career.schedule.holiday': '{holiday, select, new-years-day {Wall Street is closed for New Year’s Day.} martin-luther-king-jr-day {Wall Street is closed for Martin Luther King Jr. Day.} washingtons-birthday {Wall Street is closed for Washington’s Birthday.} good-friday {Wall Street is closed for Good Friday.} memorial-day {Wall Street is closed for Memorial Day.} juneteenth {Wall Street is closed for Juneteenth.} independence-day {Wall Street is closed for Independence Day.} labor-day {Wall Street is closed for Labor Day.} thanksgiving-day {Wall Street is closed for Thanksgiving.} christmas-day {Wall Street is closed for Christmas.} other {Wall Street is closed for the holiday.}}',
  /** {day} is the day number, {title} the assignment's title. */
  'career.schedule.opens': '{when, select, soon {Day {day}, {title}, opens soon.} tomorrow {Day {day}, {title}, opens tomorrow.} other {Day {day}, {title}, opens on {date}.}}',
  'career.schedule.opensWeekday': '{when, select, soon {Day {day}, {title}, opens soon. One new assignment each weekday, like Wall Street.} tomorrow {Day {day}, {title}, opens tomorrow. One new assignment each weekday, like Wall Street.} other {Day {day}, {title}, opens on {date}. One new assignment each weekday, like Wall Street.}}',

  // The intern street (one stop per assignment).
  'career.world.label': 'Your career path',
  'career.world.nodeFiled': 'Day {day}, {title}, filed',
  'career.world.nodeCurrent': 'Day {day}, {title}, current assignment',
  'career.world.nodeLocked': 'Day {day}, {title}, locked',
  'career.world.nodeOpens': '{when, select, soon {Day {day}, {title}, opens soon} tomorrow {Day {day}, {title}, opens tomorrow} other {Day {day}, {title}, opens on {date}}}',
  'career.world.comingLater': 'Coming later',
  /** {label} is one of the node labels above. */
  'career.world.previewLabel': '{label}. Preview assignment.',
  'career.world.opensPreview': '{when, select, soon {Opens soon. One new assignment each weekday.} tomorrow {Opens tomorrow. One new assignment each weekday.} other {Opens on {date}. One new assignment each weekday.}}',
  /** {day} is the earlier day's number. */
  'career.world.completeEarlier': 'Complete day {day} to open this desk.',
  'career.world.continue': 'Continue',
  'career.world.startHere': 'Start here',
  'career.world.opens': '{when, select, soon {Opens soon} tomorrow {Opens tomorrow} other {Opens on {date}}}',
  'career.world.filed': 'Filed',
  'career.world.beyondFirstMonth': 'Beyond the first month',
  'career.world.cityGrows': 'The city keeps growing',

  // One workday assignment: evidence, decision, handoff.
  'career.workday.stages': 'Assignment progress',
  'career.workday.stage.evidence': 'Evidence',
  'career.workday.stage.decision': 'Decision',
  'career.workday.stage.handoff': 'Handoff',
  /** Read by screen readers after each stage name. */
  'career.workday.stage.confirmed': ', confirmed',
  'career.workday.stage.current': ', current',
  'career.workday.stage.notCompleted': ', not completed',
  /** Alt text for the speaker's portrait; {speaker} is sal, wolf, oracle or shark. Names are never translated. */
  'career.workday.speaker': '{speaker, select, sal {Sal} wolf {The Wolf} oracle {The Oracle} shark {The Shark} other {The {speaker}}}',
  'career.workday.pinRow': 'Pin {label}: {value}',
  'career.workday.unpinRow': 'Unpin {label}: {value}',
  'career.workday.answer': 'Your answer',
  /** {kind} is dollars, percent or other; {unit} is the unit sign ($, %). */
  'career.workday.answerIn': '{kind, select, other {Your answer in {unit}}}',
  'career.workday.chooseDecision': 'Choose your decision',
  'career.workday.hint': 'Hint?',
  'career.workday.hideHint': 'Hide hint',
  'career.workday.chooseFacts': '{count, plural, =2 {Choose the two facts the source supports.} other {Choose the # facts the source supports.}}',
  'career.workday.note': 'Your note',
  'career.workday.optional': 'Optional',
  'career.workday.notePlaceholder': 'Anything you’d add to the handoff?',
  'career.workday.draft.saved': 'Saved',
  'career.workday.draft.unsaved': 'Unsaved changes',
  'career.workday.draft.notSaved': 'Not saved yet',
  'career.workday.filed': 'Filed.',
  'career.workday.trimsEarned': '{count} Trims earned',
  'career.workday.review': 'Your confirmed work',
  /** One pinned source row: its label and value (server text). */
  'career.workday.rowValue': '{label}: {value}',
  'career.workday.unsent': 'Your unsent note',
  'career.workday.unsentBody': 'These edits weren’t included in the filed update.',
  'career.workday.removedNote': 'You had removed the note.',
  'career.workday.discardEdits': 'Discard these edits',
  'career.workday.conflictLabel': 'Review the changed note',
  'career.workday.conflictTitle': 'This note changed on another device.',
  'career.workday.conflictBody': 'Your edits are still in the note above.',
  'career.workday.savedNote': 'Saved note',
  'career.workday.noSavedNote': 'No saved note.',
  'career.workday.useSaved': 'Use saved note',
  'career.workday.keepMine': 'Keep my edits',
  'career.workday.pending': 'Check your last save before making another change.',
  'career.workday.checkLastSave': 'Check last save',
  'career.workday.checkEvidence': 'Check the evidence',
  'career.workday.sendDecision': 'Send your decision',
  'career.workday.fileUpdate': 'File update',
  'career.workday.trimsWhenFiled': '{count} Trims when filed',
  'career.workday.leaveEditsTitle': 'Leave these edits?',
  'career.workday.leaveNoteTitle': 'Leave this note?',
  'career.workday.leaveNoteBody': 'Your latest edits haven’t saved yet.',
  'career.workday.keepReading': 'Keep reading',
  'career.workday.keepWriting': 'Keep writing',
  'career.workday.discardAndLeave': 'Discard edits and leave',
  'career.workday.leaveWithoutSaving': 'Leave without saving',
  'career.workday.error.evidence': 'Check the source again. Those details don’t support this update.',
  'career.workday.error.decision': 'Take another look at the figures.',
  'career.workday.error.changed': 'Your work changed on another screen. Review the refreshed assignment before continuing.',
  'career.workday.error.locked': 'File the earlier assignment first.',
  'career.workday.error.tomorrow': 'You’ve already started today’s assignment. The next one opens on the next weekday.',
  'career.workday.error.closed': 'Wall Street is closed today. The next assignment opens on the next weekday.',
  'career.workday.error.session': 'Your account changed. Open your desk again.',
  'career.workday.error.default': 'Couldn’t save yet. Your work is still here. Try again.',

  // The daily desk story and the desk week.
  'career.daily.loading': 'Opening today’s desk…',
  'career.daily.loadFailed': 'Today’s desk couldn’t load.',
  'career.daily.today': 'Today at your desk',
  'career.daily.checkClockOut': 'Check your clock-out',
  'career.daily.reviewToday': 'Review today',
  'career.daily.stepInside': 'Step inside',
  'career.daily.storyStale': 'Today’s story couldn’t refresh.',
  'career.daily.completedToday': 'Completed today',
  'career.daily.decisionSaved': 'Your decision is saved.',
  /** {name} is Sal, Wolf, Oracle or Shark. */
  'career.daily.momentWith': 'A moment with {name}.',
  'career.daily.back': '← Back to my desk',
  'career.daily.backToDesk': 'Back to my desk',
  'career.daily.savedResponse': 'Your saved response',
  'career.daily.response': 'Your response',
  'career.daily.question': 'What do you do?',
  'career.daily.pendingError': 'The connection ended before confirmation. Check your clock-out before trying another response.',
  'career.daily.updateError': 'Your desk couldn’t update. Refresh today’s story and try again.',
  'career.daily.dayCompleted': 'Day completed',
  'career.daily.dayCompletedTrims': 'Day completed · {count} Trims earned',
  'career.daily.checkClockOutShort': 'Check clock-out',
  'career.daily.clockOut': 'Clock out',
  'career.daily.changeResponse': 'Change response',
  'career.daily.seeWhatHappens': 'See what happens',
  'career.daily.refreshStory': 'Refresh today’s story',
  'career.week.progressStale': 'Progress couldn’t refresh.',
  'career.week.title': 'Your desk week',
  'career.week.loading': 'Getting your week…',
  'career.week.loadFailed': 'Your week couldn’t load.',
  'career.week.refreshFailed': 'Your week couldn’t refresh.',
  /**
   * One day of the desk week for screen readers. {day} is "Monday 21";
   * {today} is yes or no; {state} is done, upcoming or missed.
   */
  'career.week.dayLabel': '{day}{today, select, yes {, today} other {}}{state, select, done {, desk story completed} upcoming {, upcoming} other {, no desk story completed}}',
  'career.week.rankActivity': 'Your rank and activity',
  'career.week.streak': '{days} day streak',
  'career.week.activityLabel': 'Days with a trade, comment or desk story',
  'career.week.active': ', active',
  'career.week.noActivity': ', no activity',
  'career.week.activityLoading': 'Getting activity…',
  'career.week.activityUnavailable': 'Activity unavailable.',
  'career.week.retryActivity': 'Retry activity',
  'career.week.storySaved': 'Today’s desk story is saved.',
  'career.week.retryProgress': 'Retry progress',
  'career.week.tradingMilestones': 'Trading milestones',
  'career.week.milestoneCount': '{done} of {total}',
  'career.week.browseMarket': 'Browse market',
  'career.week.continueOnMobile': 'Continue on mobile',

  // The downloadable calendar reminder (.ics). Plain text: no tags.
  'career.reminder.title': 'Trimmy: your desk is waiting',
  /** {url} is the link back to Trimmy. */
  'career.reminder.description': 'A few minutes on your practice desk. {url}',
  'career.reminder.alarm': 'Trimmy practice',
  /** File names: lowercase ASCII letters, digits and hyphens only. */
  'career.reminder.fileDaily': 'trimmy-daily-reminder.ics',
  'career.reminder.fileWeekly': 'trimmy-reminder-mon-wed-fri.ics',
} as const satisfies AreaMessages<'career'>;
