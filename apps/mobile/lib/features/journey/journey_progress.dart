import 'package:flutter/widgets.dart' show StringCharacters;

import 'journey_catalog.dart';

/// Calendar arithmetic uses UTC date-only values so DST cannot shorten a day.
String localDateKey(DateTime moment) {
  final date = moment.toLocal();
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

DateTime? parseDateKey(Object? value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return null;
  }
  final parsed = DateTime.tryParse('${value}T00:00:00.000Z');
  if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
    return null;
  }
  return parsed;
}

DateTime? parseCompletionTime(Object? value) {
  if (value is! String) return null;
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
    return null;
  }
  return parsed;
}

class RestoredJourneyProgress {
  RestoredJourneyProgress({
    required this.session,
    required this.completions,
    required this.activityByChapter,
    required this.repaired,
  });
  final JourneySession? session;
  final Map<String, JourneyCompletion> completions;
  final Map<String, String> activityByChapter;
  final bool repaired;
}

RestoredJourneyProgress restoreJourneyProgress(Object? raw) {
  var repaired = false;
  final completions = <String, JourneyCompletion>{};
  final activity = <String, String>{};
  JourneySession? session;
  if (raw is! Map<String, dynamic>) {
    return RestoredJourneyProgress(
      session: null,
      completions: completions,
      activityByChapter: activity,
      repaired: true,
    );
  }
  final records = raw['completions'];
  final candidates = <String, JourneyCompletion>{};
  if (records is List) {
    for (final record in records) {
      if (record is! Map<String, dynamic>) {
        repaired = true;
        continue;
      }
      final id = record['chapterId'];
      final reflection = record['reflection'];
      final time = parseCompletionTime(record['completedAt']);
      if (id is! String ||
          journeyChapterById(id) == null ||
          candidates.containsKey(id) ||
          reflection is! String ||
          reflection.trim().isEmpty ||
          reflection.characters.length > 500 ||
          time == null) {
        repaired = true;
        continue;
      }
      candidates[id] = JourneyCompletion(
        chapterId: id,
        reflection: reflection.trim(),
        completedAt: time,
      );
    }
    // A later chapter cannot unlock itself from an isolated malformed record.
    var prefixComplete = true;
    for (final chapter in journeyChapters) {
      final completion = candidates[chapter.id];
      if (prefixComplete && completion != null) {
        completions[chapter.id] = completion;
      } else {
        prefixComplete = false;
        if (completion != null) repaired = true;
      }
    }
  } else {
    repaired = true;
  }

  final rawActivity = raw['activityByChapter'];
  if (rawActivity is Map<String, dynamic>) {
    for (final entry in rawActivity.entries) {
      final completion = completions[entry.key];
      final date = parseDateKey(entry.value);
      // A completion can cross a UTC/local boundary, never an arbitrary month.
      final utcDay = completion == null
          ? null
          : DateTime.utc(
              completion.completedAt.year,
              completion.completedAt.month,
              completion.completedAt.day,
            );
      if (date == null ||
          utcDay == null ||
          date.difference(utcDay).inDays.abs() > 1) {
        repaired = true;
        continue;
      }
      activity[entry.key] = entry.value as String;
    }
  } else {
    repaired = true;
  }

  final rawSession = raw['session'];
  if (rawSession != null) {
    if (rawSession is! Map<String, dynamic>) {
      repaired = true;
    } else {
      final id = rawSession['chapterId'];
      final index = rawSession['stepIndex'];
      final chapter = id is String ? journeyChapterById(id) : null;
      final chapterIndex = journeyChapters.indexWhere(
        (entry) => entry.id == id,
      );
      final unlocked =
          chapterIndex == 0 ||
          (chapterIndex > 0 &&
              completions.containsKey(journeyChapters[chapterIndex - 1].id));
      if (chapter == null ||
          !unlocked ||
          index is! int ||
          index < 0 ||
          index >= chapter.steps.length) {
        repaired = true;
      } else {
        var safeIndex = index;
        final answers = <String, int>{};
        final rawAnswers = rawSession['answers'];
        if (rawAnswers is Map<String, dynamic>) {
          for (var i = 0; i <= index; i++) {
            final step = chapter.steps[i];
            if (step.kind != JourneyStepKind.decision) continue;
            final answer = rawAnswers[step.id];
            if (answer is int && answer >= 0 && answer < step.choices.length) {
              answers[step.id] = answer;
            } else if (i < index) {
              safeIndex = i;
              repaired = true;
              break;
            } else if (answer != null) {
              repaired = true;
            }
          }
          if (rawAnswers.length != answers.length) repaired = true;
        } else {
          safeIndex = index > 1 ? 1 : index;
          repaired = true;
        }
        final rawReflection = rawSession['reflection'];
        final reflection =
            rawReflection is String && rawReflection.characters.length <= 500
            ? rawReflection
            : '';
        if (rawReflection != reflection) repaired = true;
        session = JourneySession(
          chapterId: chapter.id,
          stepIndex: safeIndex,
          answers: answers,
          reflection: reflection,
        );
      }
    }
  }
  return RestoredJourneyProgress(
    session: session,
    completions: completions,
    activityByChapter: activity,
    repaired: repaired,
  );
}
