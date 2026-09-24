import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/design_study.dart';
import 'package:trimmy/design_study/activities.dart';
import 'package:trimmy/design_study/career.dart';
import 'package:trimmy/design_study/craft.dart';
import 'package:trimmy/design_study/mission.dart';
import 'package:trimmy/design_study/number_evidence.dart';
import 'package:trimmy/design_study/practice_catalog.generated.dart';
import 'package:trimmy/design_study/progress.dart';

final _now = DateTime.utc(2026, 9, 14, 12);
OfficeProgress _complete(OfficeProgress state, String id) {
  state = state.startActivity(id).advance().advance();
  if (id == 'check-the-sample') {
    state = state
        .selectAnswerPart('amount', 'eight-of-ten')
        .selectAnswerPart('group', 'testers');
  } else if (id == 'prepare-the-update') {
    for (final part in ['dated-growth', 'lower-profit', 'trial-result']) {
      state = state.selectAnswerPart(part, 'included');
    }
  } else {
    state = state.selectChoice(practiceCatalogById[id]!.correctChoiceId);
  }
  return state.submitChoice(_now).closeActivity();
}

OfficeProgress _before(String id) {
  var state = OfficeProgress.empty();
  for (final previous in practiceCatalogActivityIds) {
    if (previous == id) break;
    state = _complete(state, previous);
  }
  return state;
}

class _Store {
  _Store(OfficeProgress state) : raw = jsonEncode(state.toJson());
  String raw;
  Completer<bool>? hold;
  OfficeProgressRepository open() => OfficeProgressRepository(
    read: (key) => key == OfficeProgressRepository.saveKey ? raw : null,
    write: (key, value) async {
      final wait = hold;
      hold = null;
      if (wait != null && !await wait.future) return false;
      raw = value;
      return true;
    },
    clock: () => _now,
  );
}

void _phone(WidgetTester tester, {double scale = 1}) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _tap(WidgetTester tester, String text) async {
  final target = find.text(text);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: text);
}

Future<void> _mount(WidgetTester tester, OfficeProgressRepository repo) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    OfficeStudy(
      preferences: await SharedPreferences.getInstance(),
      progressRepository: repo,
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in [('Manrope', 'manrope'), ('Rubik', 'rubik')]) {
      await (FontLoader(font.$1)..addFont(
            rootBundle.load('assets/fonts/${font.$2}/${font.$1}-Variable.ttf'),
          ))
          .load();
    }
  });

  test(
    'authored definitions agree with the released catalog and have bounded evidence',
    () {
      expect(studyActivities.map((a) => a.id), practiceCatalogActivityIds);
      for (final activity in studyActivities) {
        final entry = practiceCatalogById[activity.id]!;
        expect(activity.title, entry.title);
        expect(activity.correctChoiceId, entry.correctChoiceId);
        expect(activity.effectiveAcceptedChoiceIds, entry.acceptedChoiceIds);
        expect(activity.choices.map((a) => a.id), entry.choiceIds);
        expect(
          activity.presentedChoices.map((a) => a.id).toSet(),
          entry.choiceIds.toSet(),
        );
        expect(activity.presentedChoices.length, entry.choiceIds.length);
        if (entry.floor >= 2) {
          expect(activity.evidence, isNotEmpty);
          expect(activity.journalEvidence, isNotEmpty);
        }
      }
      expect(prepareTheComparisonActivity.evidence, [
        companyValueEvidence,
        feeEvidence,
        concentrationEvidence,
      ]);
    },
  );

  test('floor unlock and return-to-review follow acknowledged history', () {
    final almost = _before('prepare-the-update');
    expect(OfficeCareer(almost).isFloorUnlocked(2), isFalse);
    final floor2 = _complete(almost, 'prepare-the-update');
    expect(OfficeCareer(floor2).currentFloor, 2);
    expect(OfficeCareer(floor2).completedOn(1), 4);
    expect(OfficeCareer(floor2).nextActivityId, 'compare-company-value');
    final interrupted = floor2.startActivity('compare-company-value').advance();
    expect(OfficeCareer(interrupted).canOpen('check-the-date'), isFalse);
    final all = _complete(
      _before('prepare-the-comparison'),
      'prepare-the-comparison',
    );
    expect(OfficeCareer(all).isComplete, isFalse);
    expect(OfficeCareer(all).currentFloor, 3);
    expect(OfficeCareer(all).isFloorUnlocked(3), isTrue);
    expect(OfficeCareer(all).canOpen('check-the-date'), isTrue);

    final floor3Done = _before('set-a-loss-limit');
    expect(OfficeCareer(floor3Done).currentFloor, 4);
    expect(OfficeCareer(floor3Done).completedOn(3), 3);
    expect(OfficeCareer(floor3Done).isFloorUnlocked(4), isTrue);
    expect(OfficeCareer(floor3Done).nextActivityId, 'set-a-loss-limit');
    expect(OfficeCareer(floor3Done).isComplete, isFalse);
    final everything = _complete(_before('write-the-plan'), 'write-the-plan');
    expect(OfficeCareer(everything).isComplete, isTrue);
    expect(OfficeCareer(everything).completedOn(4), 3);
  });

  for (final activity in studyActivities.skip(4).take(4)) {
    testWidgets(
      '${activity.id}: correction, restart, Journal and immutable replay',
      (tester) async {
        _phone(tester);
        final store = _Store(_before(activity.id));
        var repo = store.open();
        await _mount(tester, repo);
        await _tap(tester, 'Start activity');
        await _tap(tester, 'Open the figures');
        expect(find.byType(NumberEvidence), findsOneWidget);
        expect(find.text(activity.evidence.first.title), findsOneWidget);
        await _tap(tester, 'Choose an answer');
        await _tap(tester, activity.choices.last.label);
        await _tap(tester, 'Submit answer');
        expect(repo.state.active!.stage, 3);
        expect(repo.state.completions.containsKey(activity.id), isFalse);
        final held = Completer<bool>();
        store.hold = held;
        await tester.tap(find.text('Save the corrected answer'));
        await tester.pump();
        expect(repo.state.completions.containsKey(activity.id), isFalse);
        held.complete(false);
        await tester.pumpAndSettle();
        expect(
          find.text('Your progress could not be saved. Please try again.'),
          findsOneWidget,
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        repo = store.open();
        await _mount(tester, repo);
        await _tap(tester, 'Continue activity');
        expect(repo.state.active!.selectedChoiceId, activity.choices.last.id);
        await _tap(tester, 'Save the corrected answer');
        final first = repo.state.completions[activity.id]!.toJson();
        await _tap(tester, 'Back to your office');
        await _tap(tester, 'Journal');
        final note = find.byKey(ValueKey('journal-${activity.id}'));
        expect(
          find.descendant(
            of: note,
            matching: find.text(activity.choices.last.detail),
          ),
          findsOneWidget,
        );
        final replay = find.byKey(ValueKey('replay-${activity.id}'));
        await tester.scrollUntilVisible(
          replay,
          300,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(replay);
        await tester.pumpAndSettle();
        await _tap(tester, 'Open the figures');
        await _tap(tester, 'Choose an answer');
        await _tap(tester, activity.choices.first.label);
        await _tap(tester, 'Submit answer');
        expect(repo.state.completions[activity.id]!.toJson(), first);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'floors expose unlocked work and resume without replacing unfinished work',
    (tester) async {
      _phone(tester);
      final store = _Store(_before('compare-company-value'));
      final repo = store.open();
      await _mount(tester, repo);
      expect(find.text('02'), findsOneWidget);
      await tester.tap(find.byTooltip('Your office floors'));
      await tester.pumpAndSettle();
      final open = find.byKey(
        const ValueKey('floor-activity-compare-company-value'),
      );
      final locked = find.byKey(
        const ValueKey('floor-activity-count-the-fees'),
      );
      expect(tester.widget<CraftButton>(open).onPressed, isNotNull);
      expect(tester.widget<CraftButton>(locked).onPressed, isNull);
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(find.byType(ActivityStudy), findsOneWidget);
      expect(repo.state.active!.activityId, 'compare-company-value');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Your office floors'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CraftButton>(
              find.byKey(const ValueKey('floor-activity-check-the-date')),
            )
            .onPressed,
        isNull,
      );
      expect(tester.widget<CraftButton>(open).onPressed, isNotNull);
    },
  );

  testWidgets(
    'floor hints distinguish an unfinished replay from unmet prerequisites',
    (tester) async {
      _phone(tester);
      final store = _Store(
        _before('compare-company-value').startActivity('check-the-date'),
      );
      final repo = store.open();
      await _mount(tester, repo);
      await tester.tap(find.byTooltip('Your office floors'));
      await tester.pumpAndSettle();
      CraftButton floorButton(String id) => tester.widget<CraftButton>(
        find.byKey(ValueKey('floor-activity-$id')),
      );
      expect(floorButton('check-the-date').detail, 'Continue activity');
      expect(
        floorButton('sales-and-profit').detail,
        'Saved · Finish your current activity first',
      );
      expect(floorButton('sales-and-profit').onPressed, isNull);
      expect(
        floorButton('compare-company-value').detail,
        'Finish your current activity first',
      );
      expect(floorButton('compare-company-value').onPressed, isNull);
      expect(
        floorButton('count-the-fees').detail,
        'Complete the previous activity first',
      );
      expect(floorButton('count-the-fees').onPressed, isNull);

      await _tap(tester, 'Back to your office');
      await _tap(tester, 'Continue activity');
      await _tap(tester, 'Open the report');
      await _tap(tester, 'Choose an answer');
      await _tap(tester, 'Add the year');
      await _tap(tester, 'Submit answer');
      await _tap(tester, 'Back to your office');
      expect(repo.state.completions, hasLength(4));
      expect(repo.state.active, isNull);
      await tester.tap(find.byTooltip('Your office floors'));
      await tester.pumpAndSettle();
      expect(floorButton('sales-and-profit').detail, 'Saved · Try again');
      expect(floorButton('sales-and-profit').onPressed, isNotNull);
      expect(floorButton('compare-company-value').detail, 'Ready to start');
      expect(floorButton('compare-company-value').onPressed, isNotNull);
      expect(floorButton('count-the-fees').onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'comparison sources and choices fit large text without hidden conclusions',
    (tester) async {
      _phone(tester, scale: 2);
      final repo = _Store(_before('prepare-the-comparison')).open();
      await _mount(tester, repo);
      await _tap(tester, 'Start activity');
      await _tap(tester, 'Open the figures');
      for (final source in prepareTheComparisonActivity.evidence) {
        await tester.ensureVisible(find.text(source.title));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(source.explanation), findsOneWidget);
      }
      await _tap(tester, 'Choose an answer');
      await _tap(tester, 'Keep all three checks');
      await _tap(tester, 'Submit answer');
      expect(repo.state.completions, hasLength(8));
    },
  );
}
