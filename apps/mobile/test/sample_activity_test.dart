import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/design_study.dart';
import 'package:trimmy/design_study/activities.dart';
import 'package:trimmy/design_study/craft.dart';
import 'package:trimmy/design_study/progress.dart';

import 'sample_progress_test.dart' show sample, unlockedSample;

class _Store {
  _Store([OfficeProgress? state]) {
    values[OfficeProgressRepository.saveKey] = jsonEncode(
      (state ?? unlockedSample()).toJson(),
    );
  }

  final values = <String, String>{};
  Completer<bool>? nextWrite;
  int writes = 0;

  OfficeProgressRepository repository() => OfficeProgressRepository(
    read: (key) => values[key],
    write: (key, value) async {
      writes++;
      final gate = nextWrite;
      nextWrite = null;
      if (gate != null && !await gate.future) return false;
      values[key] = value;
      return true;
    },
    clock: () => DateTime.utc(2026, 9, 14, 12),
  );

  OfficeProgress get saved => OfficeProgress.fromJson(
    jsonDecode(values[OfficeProgressRepository.saveKey]!)
        as Map<String, dynamic>,
  );

  Completer<bool> holdNextWrite() {
    final gate = Completer<bool>();
    nextWrite = gate;
    return gate;
  }
}

void _phone(WidgetTester tester, {double scale = 1}) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<SharedPreferences> _preferences() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Future<void> _mount(
  WidgetTester tester,
  SharedPreferences preferences,
  OfficeProgressRepository repository,
) async {
  await tester.pumpWidget(
    OfficeStudy(preferences: preferences, progressRepository: repository),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: 'After "$label"');
}

Future<void> _tapPart(WidgetTester tester, String part, String value) async {
  final target = find.byKey(ValueKey('sample-$part-$value'));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: 'After $part=$value');
}

CraftButton _part(WidgetTester tester, String part, String value) =>
    tester.widget(find.byKey(ValueKey('sample-$part-$value')));

CraftButton _submit(WidgetTester tester) => tester.widget(
  find.byWidgetPredicate(
    (widget) => widget is CraftButton && widget.label == 'Submit answer',
  ),
);

Future<void> _openHeadline(WidgetTester tester) async {
  await _tap(tester, 'Start activity');
  await _tap(tester, 'Open the replies');
  await _tap(tester, 'Write the headline');
  expect(_submit(tester).onPressed, isNull);
}

Future<void> _returnToOffice(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  expect(find.text('Your office'), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    for (final entry in [
      ('Manrope', 'assets/fonts/manrope/Manrope-Variable.ttf'),
      ('Rubik', 'assets/fonts/rubik/Rubik-Variable.ttf'),
    ]) {
      await (FontLoader(entry.$1)..addFont(rootBundle.load(entry.$2))).load();
    }
  });

  testWidgets(
    'a partial headline restores after restart and failed writes never select a group',
    (tester) async {
      _phone(tester);
      final store = _Store();
      final preferences = await _preferences();
      var repository = store.repository();
      await _mount(tester, preferences, repository);
      expect(find.text(checkTheSampleActivity.title), findsOneWidget);
      await _openHeadline(tester);
      await _tapPart(tester, 'amount', 'eight-of-ten');
      expect(_part(tester, 'amount', 'eight-of-ten').selected, isTrue);
      expect(_submit(tester).onPressed, isNull);
      expect(store.saved.active!.answerParts, {'amount': 'eight-of-ten'});

      final failedWrite = store.holdNextWrite();
      final group = find.byKey(const ValueKey('sample-group-testers'));
      await tester.ensureVisible(group);
      await tester.tap(group);
      await tester.pump();
      expect(_part(tester, 'group', 'testers').selected, isFalse);
      expect(repository.state.active!.selectedChoiceId, isNull);
      expect(store.saved.active!.answerParts, {'amount': 'eight-of-ten'});
      expect(find.text('Saving…'), findsOneWidget);
      failedWrite.complete(false);
      await tester.pumpAndSettle();
      expect(_part(tester, 'group', 'testers').selected, isFalse);
      expect(_submit(tester).onPressed, isNull);
      expect(
        find.text('Your progress could not be saved. Please try again.'),
        findsOneWidget,
      );

      await _returnToOffice(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      repository = store.repository();
      await _mount(tester, preferences, repository);
      await _tap(tester, 'Continue activity');
      expect(_part(tester, 'amount', 'eight-of-ten').selected, isTrue);
      expect(_part(tester, 'group', 'testers').selected, isFalse);
      expect(_submit(tester).onPressed, isNull);
      await _tapPart(tester, 'group', 'testers');
      expect(_submit(tester).onPressed, isNotNull);
      expect(store.saved.active!.selectedChoiceId, 'eight-of-ten-testers');
      expect(store.saved.completions, hasLength(2));
    },
  );

  testWidgets(
    'wrong group explains the mismatch and only acknowledged correction files the survey note',
    (tester) async {
      _phone(tester);
      final store = _Store();
      final repository = store.repository();
      await _mount(tester, await _preferences(), repository);
      await _openHeadline(tester);
      await _tapPart(tester, 'amount', 'eight-of-ten');
      await _tapPart(tester, 'group', 'customers');
      await _tap(tester, 'Submit answer');
      expect(find.text('The count fits. Check the group.'), findsOneWidget);
      expect(find.text('8 of 10 customers liked Aster.'), findsOneWidget);
      expect(store.saved.active!.stage, 3);
      expect(store.saved.completions, hasLength(2));

      final failedCorrection = store.holdNextWrite();
      await tester.tap(find.text('Use the trial results'));
      await tester.pump();
      expect(find.text('Good catch.'), findsNothing);
      expect(store.saved.completions, hasLength(2));
      failedCorrection.complete(false);
      await tester.pumpAndSettle();
      expect(find.text('The count fits. Check the group.'), findsOneWidget);
      await _returnToOffice(tester);
      expect(find.text('Costs checked'), findsOneWidget);
      expect(find.text('8 of 10 testers'), findsNothing);
      await _tap(tester, 'Continue activity');

      final acceptedCorrection = store.holdNextWrite();
      await tester.tap(find.text('Use the trial results'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Good catch.'), findsNothing);
      expect(store.saved.active!.stage, 3);
      expect(store.saved.completions, hasLength(2));
      acceptedCorrection.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('Good catch.'), findsOneWidget);
      expect(store.saved.completions[sample]!.corrected, isTrue);
      expect(
        store.saved.completions[sample]!.selectedChoiceId,
        'eight-of-ten-customers',
      );
      await _tap(tester, 'Back to your office');
      expect(find.text('8 of 10 testers'), findsOneWidget);
      expect(find.text('Prepare the update'), findsOneWidget);
      expect(
        find.text(
          'Ada: Three notes checked. Bring them together in our update.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a source slip and every headline control stay reachable at 200% text',
    (tester) async {
      _phone(tester, scale: 2);
      final store = _Store();
      final repository = store.repository();
      await _mount(tester, await _preferences(), repository);
      await _tap(tester, 'Start activity');
      await _tap(tester, 'Open the replies');
      final writesBeforeInspecting = store.writes;
      final lastSlip = find.byKey(const ValueKey('sample-slip-10'));
      await tester.ensureVisible(lastSlip);
      await tester.tap(lastSlip);
      await tester.pumpAndSettle();
      expect(find.text('Tester 10 · Not for me'), findsOneWidget);
      expect(store.writes, writesBeforeInspecting);
      expect(store.saved.active!.stage, 1);
      await _tap(tester, 'Write the headline');
      await _tapPart(tester, 'group', 'testers');
      expect(_submit(tester).onPressed, isNull);
      await _tapPart(tester, 'amount', 'eight-of-ten');
      expect(_submit(tester).onPressed, isNotNull);
      await _tap(tester, 'Submit answer');
      expect(find.text('Good catch.'), findsOneWidget);
      expect(find.text(checkTheSampleActivity.successFeedback), findsOneWidget);
      expect(store.saved.completions[sample]!.corrected, isFalse);
      await _tap(tester, 'Back to your office');
      expect(find.text('8 of 10 testers'), findsOneWidget);
      expect(find.text('Prepare the update'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Journal retains the first composed headline after a correct replay',
    (tester) async {
      _phone(tester);
      final firstSubmission = unlockedSample()
          .startActivity(sample)
          .advance()
          .advance()
          .selectAnswerPart('amount', 'all')
          .selectAnswerPart('group', 'customers')
          .submitChoice(DateTime.utc(2026, 9, 13, 14))
          .acceptCorrection(DateTime.utc(2026, 9, 13, 14))
          .closeActivity();
      final firstRecord = firstSubmission.completions[sample]!.toJson();
      final store = _Store(firstSubmission);
      await _mount(tester, await _preferences(), store.repository());
      await _tap(tester, 'Journal');
      final record = find.byKey(const ValueKey('journal-check-the-sample'));
      await tester.scrollUntilVisible(record, 450);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: record, matching: find.text('Your first headline')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: record,
          matching: find.text('All customers liked Aster.'),
        ),
        findsOneWidget,
      );
      final replay = find.byKey(const ValueKey('replay-check-the-sample'));
      await tester.scrollUntilVisible(replay, 450);
      await tester.tap(replay);
      await tester.pumpAndSettle();
      await _tap(tester, 'Open the replies');
      await _tap(tester, 'Write the headline');
      expect(_submit(tester).onPressed, isNull);
      await _tapPart(tester, 'amount', 'eight-of-ten');
      await _tapPart(tester, 'group', 'testers');
      await _tap(tester, 'Submit answer');
      expect(find.text('Good catch.'), findsOneWidget);
      expect(store.saved.active!.corrected, isFalse);
      expect(store.saved.completions[sample]!.toJson(), firstRecord);
      await _tap(tester, 'Back to your office');
      expect(find.text('Your office'), findsOneWidget);
      await _tap(tester, 'Journal');
      await tester.scrollUntilVisible(record, 450);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: record,
          matching: find.text('All customers liked Aster.'),
        ),
        findsOneWidget,
      );
      expect(store.saved.completions, hasLength(3));
    },
  );
}
