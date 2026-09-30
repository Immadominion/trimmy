import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/notifications/reminder_plan.dart';
import 'package:trimmy/product/workdays/workdays.dart';

WorkJourney journey({bool filed = false, String? opensAt, bool done = false}) =>
    WorkJourney.fromJson({
      'assignments': [
        {
          'id': 'one',
          'ordinal': 1,
          'title': 'Read the business',
          'completedAt': filed ? '2026-10-01T10:00:00Z' : null,
        },
      ],
      'schedule': {
        'state': done
            ? 'done'
            : filed
            ? 'tomorrow'
            : 'available',
      },
      if (opensAt != null)
        'upcoming': {
          'id': 'two',
          'ordinal': 2,
          'title': 'Check the figures',
          'art': 'ticker',
          'opensAt': opensAt,
        },
    });

void main() {
  test('one reminder names the current assignment and stays in local time', () {
    final now = DateTime(2026, 10, 1, 9);
    final plan = ReminderPlan.next('daily', now: now, journey: journey())!;
    expect(plan.at, DateTime(2026, 10, 1, 19));
    expect(plan.body, 'Day 1: Read the business');
    expect(ReminderPlan.next('off', now: now, journey: journey()), isNull);
  });

  test(
    'filing work removes today and waits for the server opening, including a holiday',
    () {
      final now = DateTime(2026, 10, 1, 10);
      final plan = ReminderPlan.next(
        'daily',
        now: now,
        journey: journey(
          filed: true,
          opensAt: DateTime(2026, 10, 5).toUtc().toIso8601String(),
        ),
      )!;
      expect(plan.at, DateTime(2026, 10, 5, 19));
      expect(plan.body, 'Day 2: Check the figures');
      expect(
        ReminderPlan.next(
          'daily',
          now: now,
          journey: journey(filed: true, done: true),
        ),
        isNull,
      );
      // An older server with no next-assignment evidence must not invent work.
      expect(
        ReminderPlan.next('daily', now: now, journey: journey(filed: true)),
        isNull,
      );
    },
  );

  test('weekends and elapsed delivery times are skipped', () {
    expect(
      ReminderPlan.next('daily', now: DateTime(2026, 10, 2, 19))!.at,
      DateTime(2026, 10, 5, 19),
    );
    expect(
      ReminderPlan.next('daily', now: DateTime(2026, 10, 3, 10))!.at,
      DateTime(2026, 10, 5, 19),
    );
    expect(
      ReminderPlan.next('occasional', now: DateTime(2026, 10, 1, 10))!.at,
      DateTime(2026, 10, 2, 19),
    );
    expect(
      ReminderPlan.next('occasional', now: DateTime(2026, 10, 5, 20))!.at,
      DateTime(2026, 10, 7, 19),
    );
  });

  test('an opening after 7 PM is never announced early', () {
    final plan = ReminderPlan.next(
      'daily',
      now: DateTime(2026, 10, 1, 10),
      journey: journey(
        filed: true,
        opensAt: DateTime(2026, 10, 2, 21).toUtc().toIso8601String(),
      ),
    )!;
    expect(plan.at, DateTime(2026, 10, 5, 19));
  });
}
