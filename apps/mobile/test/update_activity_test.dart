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

import 'package:trimmy/design_study/update_assignment.dart';
import 'package:trimmy/design_study/update_review.dart';

const update = OfficeActivityIds.prepareTheUpdate;

OfficeProgress unlockedUpdate() {
  var state = OfficeProgress.empty();
  for (final step in [
    ('check-the-date', 'add-year'),
    ('sales-and-profit', 'check-costs'),
  ]) {
    state = state
        .startActivity(step.$1)
        .advance()
        .advance()
        .selectChoice(step.$2)
        .submitChoice(DateTime.utc(2026, 9, 14))
        .closeActivity();
  }
  return state
      .startActivity('check-the-sample')
      .advance()
      .advance()
      .selectAnswerPart('amount', 'eight-of-ten')
      .selectAnswerPart('group', 'testers')
      .submitChoice(DateTime.utc(2026, 9, 14))
      .closeActivity();
}

class _Store {
  _Store([OfficeProgress? state]) {
    values[OfficeProgressRepository.saveKey] = jsonEncode(
      (state ?? unlockedUpdate()).toJson(),
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

Future<void> _pin(WidgetTester tester, String factId) async {
  final finder = find.byKey(ValueKey('update-fact-$factId'));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

CraftButton _submit(WidgetTester tester) => tester.widget(
  find.byWidgetPredicate(
    (widget) => widget is CraftButton && widget.label == 'Review with Ada',
  ),
);

Future<void> _openUpdate(WidgetTester tester) async {
  await _tap(tester, 'Start activity');
  await _tap(tester, 'Open your notes');
  await _tap(tester, 'Build the update');
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
    'partial update restores; failed pin never changes the paper or enables review',
    (tester) async {
      _phone(tester);
      final store = _Store();
      final prefs = await _preferences();
      var repository = store.repository();
      await _mount(tester, prefs, repository);
      expect(find.text(prepareTheUpdateActivity.title), findsOneWidget);
      await _openUpdate(tester);
      await _pin(tester, 'dated-growth');
      expect(store.saved.active!.answerParts, {'dated-growth': 'included'});
      final gate = store.holdNextWrite();
      final second = find.byKey(const ValueKey('update-fact-lower-profit'));
      await tester.ensureVisible(second);
      await tester.tap(second);
      await tester.pump();
      expect(repository.state.active!.answerParts, {
        'dated-growth': 'included',
      });
      expect(find.text('Saving…'), findsOneWidget);
      gate.complete(false);
      await tester.pumpAndSettle();
      expect(repository.state.active!.answerParts, {
        'dated-growth': 'included',
      });
      expect(_submit(tester).onPressed, isNull);
      expect(
        find.text('Your progress could not be saved. Please try again.'),
        findsOneWidget,
      );
      await _returnToOffice(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      repository = store.repository();
      await _mount(tester, prefs, repository);
      await _tap(tester, 'Continue activity');
      expect(repository.state.active!.answerParts, {
        'dated-growth': 'included',
      });
      expect(_submit(tester).onPressed, isNull);
      await _pin(tester, 'lower-profit');
      await _pin(tester, 'trial-result');
      expect(_submit(tester).onPressed, isNotNull);
      expect(store.saved.active!.selectedChoiceId, updateCorrectChoiceId);
      await _pin(tester, 'dated-growth');
      expect(store.saved.active!.answerParts['dated-growth'], 'excluded');
      expect(_submit(tester).onPressed, isNull);
    },
  );

  testWidgets(
    'correction must save before filing; original draft and Ada reply survive restart',
    (tester) async {
      _phone(tester);
      final store = _Store();
      final prefs = await _preferences();
      await _mount(tester, prefs, store.repository());
      await _openUpdate(tester);
      for (final id in ['dated-growth', 'lower-profit', 'all-customers']) {
        await _pin(tester, id);
      }
      await _tap(tester, 'Review with Ada');
      expect(find.text('Keep the trial group'), findsOneWidget);
      expect(find.text('Check the year'), findsNothing);
      expect(store.saved.completions, hasLength(3));
      final failed = store.holdNextWrite();
      await tester.tap(find.text('File the corrected update'));
      await tester.pump();
      expect(find.text('Update filed.'), findsNothing);
      failed.complete(false);
      await tester.pumpAndSettle();
      expect(store.saved.completions, hasLength(3));
      final accepted = store.holdNextWrite();
      await tester.tap(find.text('File the corrected update'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Update filed.'), findsNothing);
      expect(store.saved.completions, hasLength(3));
      accepted.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('Update filed.'), findsOneWidget);
      expect(store.saved.completions, hasLength(4));
      await _tap(tester, 'Back to your office');
      expect(find.text('Update filed'), findsOneWidget);
      final first = store.saved.completions[update]!.toJson();
      final reply = updateOfficeReply(first['selectedChoiceId']! as String);
      expect(find.textContaining('Ada: $reply'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await _mount(tester, prefs, store.repository());
      expect(find.textContaining('Ada: $reply'), findsOneWidget);
      await _tap(tester, 'Update filed');
      expect(find.text('Your notes'), findsOneWidget);
      expect(find.text('Your first draft'), findsOneWidget);
      expect(find.text('Everyone who uses Aster likes it.'), findsOneWidget);
      expect(store.saved.completions[update]!.toJson(), first);
    },
  );

  testWidgets(
    'folder and all update actions remain reachable at 200 percent text',
    (tester) async {
      _phone(tester, scale: 2);
      final store = _Store();
      await _mount(tester, await _preferences(), store.repository());
      await _tap(tester, 'Start activity');
      await _tap(tester, 'Open your notes');
      final writes = store.writes;
      for (final tab in ['profit', 'trial', 'growth']) {
        final finder = find.byKey(ValueKey('update-tab-$tab'));
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(store.writes, writes);
      await _tap(tester, 'Build the update');
      for (final fact in updateFacts.take(3)) {
        await _pin(tester, fact.id);
      }
      await _tap(tester, 'Review with Ada');
      expect(find.text('Update filed.'), findsOneWidget);
      expect(store.saved.completions[update]!.corrected, isFalse);
      await _tap(tester, 'Back to your office');
      expect(find.text('Compare company value'), findsOneWidget);
      expect(find.text('02'), findsOneWidget);
      expect(find.text('Update filed'), findsOneWidget);
      await _tap(tester, 'Update filed');
      await tester.ensureVisible(find.text('Ada’s reply'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'correct replay cannot replace the first draft or change Ada remembered correction',
    (tester) async {
      _phone(tester);
      var state = unlockedUpdate().startActivity(update).advance().advance();
      for (final id in ['lower-profit', 'current-growth', 'all-customers']) {
        state = state.selectAnswerPart(id, 'included');
      }
      state = state
          .submitChoice(DateTime.utc(2026, 9, 14))
          .acceptCorrection(DateTime.utc(2026, 9, 14))
          .closeActivity();
      final original = state.completions[update]!.toJson();
      final store = _Store(state);
      await _mount(tester, await _preferences(), store.repository());
      final reply = updateOfficeReply(
        state.completions[update]!.selectedChoiceId,
      );
      expect(find.textContaining('Ada: $reply'), findsOneWidget);
      await _tap(tester, 'Journal');
      final replay = find.byKey(const ValueKey('replay-prepare-the-update'));
      await tester.scrollUntilVisible(replay, 450);
      await tester.tap(replay);
      await tester.pumpAndSettle();
      await _tap(tester, 'Open your notes');
      await _tap(tester, 'Build the update');
      for (final fact in updateFacts.take(3)) {
        await _pin(tester, fact.id);
      }
      await _tap(tester, 'Review with Ada');
      expect(store.saved.active!.corrected, isFalse);
      expect(store.saved.completions[update]!.toJson(), original);
      await _tap(tester, 'Back to your office');
      expect(find.textContaining('Ada: $reply'), findsOneWidget);
    },
  );
}
