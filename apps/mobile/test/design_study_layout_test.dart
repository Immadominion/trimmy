import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/design_study.dart';

const _studyKey = 'trimmy.office-layout-study.v1';

void _phone(WidgetTester tester, {double textScale = 1}) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<SharedPreferences> _open(
  WidgetTester tester, {
  bool completed = false,
}) async {
  SharedPreferences.setMockInitialValues({
    if (completed)
      _studyKey: jsonEncode({
        'version': 1,
        'completed': true,
        'neededCorrection': false,
      }),
  });
  final preferences = await SharedPreferences.getInstance();
  await tester.pumpWidget(OfficeStudy(preferences: preferences));
  await tester.pumpAndSettle();
  return preferences;
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void _recordLayout(WidgetTester tester, List<String> failures, String stage) {
  Object? error;
  while ((error = tester.takeException()) != null) {
    failures.add('$stage: $error');
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

  testWidgets('office and settings fit a 390px phone at 200% text', (
    tester,
  ) async {
    _phone(tester, textScale: 2);
    final failures = <String>[];
    await _open(tester, completed: true);
    _recordLayout(tester, failures, 'Office must remain readable');
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    _recordLayout(tester, failures, 'Settings must be scrollable');
    await _tap(tester, 'Done');
    expect(find.byType(SwitchListTile), findsNothing);
    expect(failures, isEmpty);
  });

  testWidgets('completed journal and portfolio fit 200% text', (tester) async {
    _phone(tester, textScale: 2);
    final failures = <String>[];
    await _open(tester, completed: true);
    _recordLayout(tester, failures, 'Office');
    await _tap(tester, 'Journal');
    _recordLayout(tester, failures, 'Journal title must wrap');
    await _tap(tester, 'Portfolio');
    _recordLayout(tester, failures, 'Position must remain readable');
    expect(failures, isEmpty);
  });

  testWidgets('reduced motion survives relaunch and keeps source usable', (
    tester,
  ) async {
    _phone(tester);
    final preferences = await _open(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await _tap(tester, 'Reduce motion');
    await _tap(tester, 'Done');
    await tester.pumpWidget(const SizedBox.shrink());
    await preferences.reload();
    await tester.pumpWidget(OfficeStudy(preferences: preferences));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(
            find.ancestor(
              of: find.text('Reduce motion'),
              matching: find.byType(SwitchListTile),
            ),
          )
          .value,
      isTrue,
    );
    await _tap(tester, 'Done');
    expect(
      MediaQuery.disableAnimationsOf(
        tester.element(find.text('Start activity')),
      ),
      isTrue,
    );
    await _tap(tester, 'Start activity');
    await _tap(tester, 'Open the report');
    expect(find.text('180,000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('source and explicit choice flow remain usable at 200% text', (
    tester,
  ) async {
    _phone(tester, textScale: 2);
    final failures = <String>[];
    await _open(tester);
    _recordLayout(tester, failures, 'Office');
    await _tap(tester, 'Start activity');
    expect(tester.takeException(), isNull, reason: 'Headline report must fit');
    await _tap(tester, 'Open the report');
    expect(tester.takeException(), isNull, reason: 'Evidence rows must fit');
    expect(find.text('100,000'), findsOneWidget);
    expect(find.text('180,000'), findsOneWidget);
    await _tap(tester, 'Choose an answer');
    expect(tester.takeException(), isNull, reason: 'Decision must fit');
    await _tap(tester, 'Add the year');
    expect(
      find.text('Good catch.'),
      findsNothing,
      reason: 'Selecting an answer must not submit it',
    );
    await _tap(tester, 'Submit answer');
    expect(tester.takeException(), isNull, reason: 'Outcome must fit');
    expect(find.text('In 2025, users grew'), findsOneWidget);
    await _tap(tester, 'Back to your office');
    expect(find.text('Sales and profit'), findsOneWidget);
    expect(failures, isEmpty);
  });

  testWidgets(
    'system back saves a corrected brief and replay preserves its history',
    (tester) async {
      _phone(tester);
      final preferences = await _open(tester);
      await _tap(tester, 'Start activity');
      await _tap(tester, 'Open the report');
      await _tap(tester, 'Choose an answer');
      await _tap(tester, 'Keep the headline');
      expect(find.text('Let’s check one detail.'), findsNothing);
      await _tap(tester, 'Submit answer');
      expect(find.text('Let’s check one detail.'), findsOneWidget);
      expect(find.text('The year needs to be clear.'), findsOneWidget);
      expect(find.text('Good catch.'), findsNothing);
      await _tap(tester, 'Add the year');
      expect(find.text('Good catch.'), findsOneWidget);
      expect(find.text('In 2025, users grew'), findsOneWidget);

      // Platform back must retain a completed result without an abandon dialog.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Leave this brief?'), findsNothing);
      expect(find.text('Sales and profit'), findsOneWidget);
      final originalSave = preferences.getString('trimmy.office-progress.v1');
      expect(originalSave, isNotNull);
      final saved = jsonDecode(originalSave!) as Map<String, dynamic>;
      final completion = (saved['completions'] as Map)['check-the-date'] as Map;
      expect(completion['selectedChoiceId'], 'keep-headline');
      expect(completion['corrected'], isTrue);
      expect(DateTime.tryParse(completion['completedAt'] as String), isNotNull);

      const originalHistory =
          'You changed your answer after checking the explanation.';
      await _tap(tester, 'Journal');
      expect(find.text(originalHistory), findsOneWidget);
      await _tap(tester, 'Try again');
      await _tap(tester, 'Open the report');
      await _tap(tester, 'Choose an answer');
      await _tap(tester, 'Add the year');
      await _tap(tester, 'Submit answer');
      expect(find.text('Good catch.'), findsOneWidget);
      expect(find.text('Let’s check one detail.'), findsNothing);
      await _tap(tester, 'Back to your office');
      expect(find.text('Your office'), findsOneWidget);
      expect(find.text('Sales and profit'), findsOneWidget);
      await _tap(tester, 'Journal');
      expect(find.text(originalHistory), findsOneWidget);
      expect(
        preferences.getString('trimmy.office-progress.v1'),
        originalSave,
        reason:
            'Replay must preserve the original decision and completion time',
      );

      // Re-create the app to establish that this is saved history, not just UI state.
      await tester.pumpWidget(const SizedBox.shrink());
      await preferences.reload();
      await tester.pumpWidget(OfficeStudy(preferences: preferences));
      await tester.pumpAndSettle();
      await _tap(tester, 'Journal');
      expect(find.text(originalHistory), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
