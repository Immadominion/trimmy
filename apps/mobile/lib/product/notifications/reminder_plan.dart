import '../workdays/workdays.dart';

/// One local nudge, never a repeating claim that work is still waiting.
/// The server owns unlock dates; this planner only chooses a delivery time.
class ReminderPlan {
  const ReminderPlan(this.at, this.body);
  final DateTime at;
  final String body;

  static ReminderPlan? next(
    String preference, {
    required DateTime now,
    WorkJourney? journey,
  }) {
    if (preference == 'off') return null;
    final current = journey?.current;
    final upcoming = journey?.upcoming;
    if (journey != null && current == null && upcoming == null) return null;
    final local = now.toLocal();
    var candidate = DateTime(local.year, local.month, local.day, 19);
    final opens = upcoming?.opensAt.toLocal();
    // Date constructors preserve wall-clock time across daylight-saving changes.
    while (!candidate.isAfter(local) ||
        (opens != null && candidate.isBefore(opens)) ||
        candidate.weekday > DateTime.friday ||
        (preference == 'occasional' &&
            !const [1, 3, 5].contains(candidate.weekday))) {
      candidate = DateTime(
        candidate.year,
        candidate.month,
        candidate.day + 1,
        19,
      );
    }
    final title = current?.title ?? upcoming?.title;
    final ordinal = current?.ordinal ?? upcoming?.ordinal;
    return ReminderPlan(
      candidate,
      title == null
          ? 'Your next assignment is waiting at your desk.'
          : 'Day $ordinal: $title',
    );
  }
}
