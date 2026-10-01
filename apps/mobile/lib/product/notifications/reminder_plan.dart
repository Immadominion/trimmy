import '../../l10n/l10n.dart';
import '../workdays/workdays.dart';

/// One local nudge, never a repeating claim that work is still waiting.
/// The server owns unlock dates; this planner only chooses a delivery time.
class ReminderPlan {
  const ReminderPlan(this.at, this.title, this.body);
  final DateTime at;

  /// The notification's title and text, in the language the app showed when
  /// the reminder was planned. A workday's own title is the server's.
  final String title, body;

  /// The next reminder for [preference], written with [l10n] (English when
  /// left out).
  static ReminderPlan? next(
    String preference, {
    required DateTime now,
    WorkJourney? journey,
    AppLocalizations? l10n,
  }) {
    final copy = l10n ?? englishLocalizations;
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
      copy.reminderNotificationTitle,
      title == null || ordinal == null
          ? copy.reminderNotificationBody
          : copy.reminderNotificationDay(ordinal, title),
    );
  }
}
