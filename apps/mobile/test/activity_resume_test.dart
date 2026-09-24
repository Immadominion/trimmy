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

class _Store {
  final values = <String, String>{};
  Completer<bool>? nextWrite;

  OfficeProgressRepository repository() => OfficeProgressRepository(
    read: (key) => values[key],
    write: (key, value) async {
      final gate = nextWrite;
      nextWrite = null;
      if (gate != null && !await gate.future) return false;
      values[key] = value;
      return true;
    },
    clock: () => DateTime.utc(2026, 9, 13, 12),
  );

  OfficeProgress get saved => OfficeProgress.fromJson(
    jsonDecode(values[OfficeProgressRepository.saveKey]!)
        as Map<String, dynamic>,
  );

  void completeFirst() {
    final state = OfficeProgress.empty()
        .startActivity(OfficeActivityIds.checkTheDate)
        .advance()
        .advance()
        .selectChoice('add-year')
        .submitChoice(DateTime.utc(2026, 9, 12, 12))
        .closeActivity();
    values[OfficeProgressRepository.saveKey] = jsonEncode(state.toJson());
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
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: 'After "$label"');
}

CraftButton _choice(WidgetTester tester, String label) => tester.widget(
  find.byWidgetPredicate(
    (widget) => widget is CraftButton && widget.label == label,
  ),
);

Future<void> _openSecondSource(WidgetTester tester) async {
  expect(find.text(salesAndProfitActivity.title), findsOneWidget);
  await _tap(tester, 'Start activity');
  await _tap(tester, 'Open the report');
  expect(find.text(salesAndProfitActivity.sourceTitle), findsOneWidget);
  for (final value in [
    r'$1,000',
    r'$600',
    r'$400',
    r'$1,500',
    r'$1,300',
    r'$200',
  ]) {
    expect(find.text(value), findsOneWidget);
  }
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
    'resume keeps a selected answer and failed submission cannot show a saved outcome',
    (tester) async {
      _phone(tester);
      final store = _Store();
      final preferences = await _preferences();
      var repository = store.repository();
      await _mount(tester, preferences, repository);
      await _tap(tester, 'Start activity');
      await _tap(tester, 'Open the report');
      await _tap(tester, 'Choose an answer');
      await _tap(tester, 'Add the year');
      expect(_choice(tester, 'Add the year').selected, isTrue);
      expect(repository.state.completions, isEmpty);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Continue activity'), findsOneWidget);
      expect(store.saved.active!.stage, 2);
      expect(store.saved.active!.selectedChoiceId, 'add-year');

      await tester.pumpWidget(const SizedBox.shrink());
      repository = store.repository();
      await _mount(tester, preferences, repository);
      await _tap(tester, 'Continue activity');
      expect(_choice(tester, 'Add the year').selected, isTrue);
      expect(find.text('Submit answer'), findsOneWidget);
      expect(find.text('Good catch.'), findsNothing);
      expect(repository.state.completions, isEmpty);

      final failedWrite = Completer<bool>();
      store.nextWrite = failedWrite;
      await tester.tap(find.text('Submit answer'));
      await tester.pump();
      expect(find.text('Saving…'), findsOneWidget);
      expect(find.text('Good catch.'), findsNothing);
      expect(store.saved.completions, isEmpty);
      expect(
        repository.state.isUnlocked(OfficeActivityIds.salesAndProfit),
        isFalse,
      );

      failedWrite.complete(false);
      await tester.pumpAndSettle();
      expect(
        find.text('Your progress could not be saved. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Good catch.'), findsNothing);
      expect(_choice(tester, 'Add the year').selected, isTrue);
      expect(store.saved.active!.stage, 2);
      expect(store.saved.completions, isEmpty);

      await _tap(tester, 'Submit answer');
      expect(find.text('Good catch.'), findsOneWidget);
      expect(
        find.text(
          'Your first answer and what you learned are in your journal.',
        ),
        findsOneWidget,
      );
      expect(
        store.saved.completions[OfficeActivityIds.checkTheDate],
        isNotNull,
      );
      expect(store.saved.active!.stage, 4);
      expect(
        repository.state.isUnlocked(OfficeActivityIds.salesAndProfit),
        isTrue,
      );
      await _tap(tester, 'Back to your office');
      expect(find.text('Sales and profit'), findsOneWidget);
      expect(find.text('Start activity'), findsOneWidget);
    },
  );

  testWidgets(
    'second activity can complete with readable evidence at 200% text',
    (tester) async {
      _phone(tester, scale: 2);
      final store = _Store()..completeFirst();
      final firstRecord = store
          .saved
          .completions[OfficeActivityIds.checkTheDate]!
          .toJson();
      final repository = store.repository();
      await _mount(tester, await _preferences(), repository);
      await _openSecondSource(tester);
      await _tap(tester, 'Choose an answer');
      await _tap(tester, 'Check costs');
      expect(find.text('Good catch.'), findsNothing);
      await _tap(tester, 'Submit answer');
      expect(find.text('Good catch.'), findsOneWidget);
      expect(find.text(salesAndProfitActivity.successFeedback), findsOneWidget);
      final completion =
          store.saved.completions[OfficeActivityIds.salesAndProfit]!;
      expect(completion.corrected, isFalse);
      expect(completion.selectedChoiceId, 'check-costs');
      expect(
        store.saved.completions[OfficeActivityIds.checkTheDate]!.toJson(),
        firstRecord,
      );
      await _tap(tester, 'Back to your office');
      expect(find.text('Check the sample'), findsOneWidget);
      expect(find.text('Start activity'), findsOneWidget);
      await _tap(tester, 'Costs checked');
      final record = find.byKey(const ValueKey('journal-sales-and-profit'));
      await tester.scrollUntilVisible(record, 450);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: record,
          matching: find.text(salesAndProfitActivity.journalEvidence),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: record,
          matching: find.text(salesAndProfitActivity.correctedHeadline),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'second activity correction resumes before completion at 200% text',
    (tester) async {
      _phone(tester, scale: 2);
      final store = _Store()..completeFirst();
      final preferences = await _preferences();
      var repository = store.repository();
      await _mount(tester, preferences, repository);
      await _openSecondSource(tester);
      await _tap(tester, 'Choose an answer');
      await _tap(tester, 'Use sales alone');
      await _tap(tester, 'Submit answer');
      expect(find.text(salesAndProfitActivity.challengeTitle), findsOneWidget);
      expect(find.text('Good catch.'), findsNothing);
      expect(store.saved.completions.length, 1);
      expect(store.saved.active!.stage, 3);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      repository = store.repository();
      await _mount(tester, preferences, repository);
      await _tap(tester, 'Continue activity');
      expect(find.text(salesAndProfitActivity.challengeTitle), findsOneWidget);
      expect(store.saved.completions.length, 1);
      await _tap(tester, 'Include the costs');
      expect(
        find.text(salesAndProfitActivity.correctedFeedback),
        findsOneWidget,
      );
      final completion =
          store.saved.completions[OfficeActivityIds.salesAndProfit]!;
      expect(completion.corrected, isTrue);
      expect(completion.selectedChoiceId, 'sales-mean-profit');
      expect(store.saved.completions.length, 2);
      await _tap(tester, 'Back to your office');
      expect(find.text('Check the sample'), findsOneWidget);
      expect(find.text('Start activity'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
