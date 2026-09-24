import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/design_study.dart';
import 'package:trimmy/design_study/craft.dart';
import 'package:trimmy/design_study/mission.dart';
import 'package:trimmy/design_study/office_scene.dart';
import 'package:trimmy/design_study/progress.dart';

class _Store {
  final values = <String, String>{};
  Completer<bool>? nextWrite;
  int writeCount = 0;

  late final repository = OfficeProgressRepository(
    read: (key) => values[key],
    write: (key, value) async {
      writeCount++;
      final gate = nextWrite;
      nextWrite = null;
      if (gate != null && !await gate.future) return false;
      values[key] = value;
      return true;
    },
    clock: () => DateTime.utc(2026, 9, 13, 20),
  );

  OfficeProgress? get saved {
    final raw = values[OfficeProgressRepository.saveKey];
    return raw == null
        ? null
        : OfficeProgress.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Completer<bool> holdNextWrite() {
    final gate = Completer<bool>();
    nextWrite = gate;
    return gate;
  }
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 44, bottom: 34);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
}

void _resumeLifecycle(WidgetTester tester) {
  if (tester.binding.lifecycleState == AppLifecycleState.paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

Finder get _activities => find.byType(ActivityStudy, skipOffstage: false);

Finder get _hotspot => find.bySemanticsLabel(RegExp(r'^Open activity$'));

Finder get _assignmentHeroes => find.byWidgetPredicate(
  (widget) =>
      widget is Hero &&
      widget.tag == 'assignment-${OfficeActivityIds.checkTheDate}',
  skipOffstage: false,
);

void _expectClosedEnvelope(WidgetTester tester) {
  final envelopes = tester.widgetList<StudyEnvelope>(
    find.byType(StudyEnvelope),
  );
  expect(envelopes, hasLength(1));
  expect(envelopes.single.openness, 0);
}

CraftButton _button(WidgetTester tester, String label) => tester.widget(
  find.byWidgetPredicate(
    (widget) => widget is CraftButton && widget.label == label,
  ),
);

Future<SharedPreferences> _mount(
  WidgetTester tester,
  _Store store, {
  bool reduceMotion = false,
  ValueNotifier<bool>? ticker,
}) async {
  SharedPreferences.setMockInitialValues({
    'trimmy.office-layout-study.reduce-motion.v1': reduceMotion,
  });
  final preferences = await SharedPreferences.getInstance();
  final app = OfficeStudy(
    preferences: preferences,
    progressRepository: store.repository,
  );
  await tester.pumpWidget(
    ticker == null
        ? app
        : ValueListenableBuilder<bool>(
            valueListenable: ticker,
            child: app,
            builder: (context, enabled, child) =>
                TickerMode(enabled: enabled, child: child!),
          ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return preferences;
}

Future<void> _start(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Start activity'));
  await tester.tap(find.text('Start activity'));
  await tester.pump();
}

void _expectSavedStartOnly(_Store store) {
  expect(store.saved, isNotNull);
  expect(store.saved!.active!.activityId, OfficeActivityIds.checkTheDate);
  expect(store.saved!.active!.stage, 0);
  expect(store.saved!.active!.selectedChoiceId, isNull);
  expect(store.saved!.completions, isEmpty);
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

  testWidgets('start acknowledgement gates a single mixed-tap handoff', (
    tester,
  ) async {
    _phone(tester);
    final store = _Store();
    await _mount(tester, store);
    final gate = store.holdNextWrite();

    // Both entry points can receive input before the next rebuild. Their shared
    // guard must prevent duplicate saves and routes even in that interval.
    await tester.tap(find.text('Start activity'));
    await tester.tap(_hotspot);
    await tester.tap(find.text('Start activity'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(store.writeCount, 1);
    expect(store.saved, isNull);
    expect(store.repository.state.active, isNull);
    expect(store.repository.state.completions, isEmpty);
    expect(_activities, findsNothing);
    expect(find.text('Opening…'), findsOneWidget);
    _expectClosedEnvelope(tester);

    gate.complete(true);
    // Flush acknowledgement/build microtasks without advancing the clock by
    // the flight duration. Navigation must not await decorative movement.
    await tester.pump();
    await tester.pump();
    expect(_activities, findsOneWidget);
    _expectSavedStartOnly(store);
    expect(store.writeCount, 1);
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_activities, findsNothing);
    expect(find.text('Your office'), findsOneWidget);
    expect(find.text('Continue activity'), findsOneWidget);
    _expectSavedStartOnly(store);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed start stays in the office and can retry without a reward',
    (tester) async {
      _phone(tester);
      final store = _Store();
      await _mount(tester, store);
      final gate = store.holdNextWrite();
      await _start(tester);
      gate.complete(false);
      await tester.pumpAndSettle();

      expect(_activities, findsNothing);
      expect(find.text('Your office'), findsOneWidget);
      expect(
        find.text('This activity could not be opened. Please try again.'),
        findsOneWidget,
      );
      expect(_button(tester, 'Start activity').onPressed, isNotNull);
      _expectClosedEnvelope(tester);
      expect(store.saved, isNull);
      expect(store.repository.state.active, isNull);
      expect(store.repository.state.completions, isEmpty);

      await _start(tester);
      await tester.pumpAndSettle();
      expect(_activities, findsOneWidget);
      _expectSavedStartOnly(store);
      expect(store.writeCount, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'switching tabs cancels a late launch but retains its saved start',
    (tester) async {
      _phone(tester);
      final store = _Store();
      await _mount(tester, store);
      final gate = store.holdNextWrite();
      await _start(tester);
      await tester.tap(find.text('Portfolio'));
      await tester.pumpAndSettle();
      expect(find.text('Your portfolio'), findsOneWidget);

      gate.complete(true);
      await tester.pumpAndSettle();
      expect(_activities, findsNothing);
      expect(find.text('Your portfolio'), findsOneWidget);
      _expectSavedStartOnly(store);

      await tester.tap(find.text('Office'));
      await tester.pumpAndSettle();
      expect(find.text('Continue activity'), findsOneWidget);
      await tester.tap(find.text('Continue activity'));
      await tester.pumpAndSettle();
      expect(_activities, findsOneWidget);
      _expectSavedStartOnly(store);
      expect(store.writeCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final destination in [
    (tooltip: 'Settings', close: 'Done', dismissBeforeAck: true),
    (
      tooltip: 'Your office floors',
      close: 'Back to your office',
      dismissBeforeAck: false,
    ),
  ]) {
    testWidgets('${destination.tooltip} cancels the pending launch intent', (
      tester,
    ) async {
      _phone(tester);
      final store = _Store();
      await _mount(tester, store);
      final gate = store.holdNextWrite();
      await _start(tester);
      await tester.tap(find.byTooltip(destination.tooltip));
      await tester.pumpAndSettle();
      expect(find.text(destination.close), findsOneWidget);

      if (destination.dismissBeforeAck) {
        // Closing Settings before storage responds must not revive the launch
        // intent merely because Office is the current route again.
        await tester.ensureVisible(find.text(destination.close));
        await tester.tap(find.text(destination.close));
        await tester.pumpAndSettle();
        expect(find.text('Your office'), findsOneWidget);
      }

      gate.complete(true);
      await tester.pumpAndSettle();
      expect(_activities, findsNothing);
      _expectSavedStartOnly(store);

      if (!destination.dismissBeforeAck) {
        expect(find.text(destination.close), findsOneWidget);
        await tester.ensureVisible(find.text(destination.close));
        await tester.tap(find.text(destination.close));
        await tester.pumpAndSettle();
      }
      expect(find.text('Continue activity'), findsOneWidget);
      expect(_button(tester, 'Continue activity').onPressed, isNotNull);
      expect(store.writeCount, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'disposal cancels late navigation without losing an accepted save',
    (tester) async {
      _phone(tester);
      final store = _Store();
      final preferences = await _mount(tester, store);
      final gate = store.holdNextWrite();
      await _start(tester);
      await tester.pumpWidget(const SizedBox.shrink());

      gate.complete(true);
      await tester.pumpAndSettle();
      expect(_activities, findsNothing);
      _expectSavedStartOnly(store);
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        OfficeStudy(
          preferences: preferences,
          progressRepository: store.repository,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Continue activity'), findsOneWidget);
      expect(_activities, findsNothing);
      expect(store.writeCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final preference in [
    (name: 'app reduced motion', reduced: true, accessible: false),
    (name: 'accessible navigation', reduced: false, accessible: true),
  ]) {
    testWidgets('${preference.name} opens the activity without a hero flight', (
      tester,
    ) async {
      _phone(tester);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(
            accessibleNavigation: preference.accessible,
          );
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final store = _Store();
      await _mount(tester, store, reduceMotion: preference.reduced);
      expect(_assignmentHeroes, findsNothing);
      final gate = store.holdNextWrite();
      await _start(tester);
      _expectClosedEnvelope(tester);
      expect(_activities, findsNothing);

      gate.complete(true);
      await tester.pump();
      await tester.pump();
      expect(_activities, findsOneWidget);
      expect(_assignmentHeroes, findsNothing);
      _expectSavedStartOnly(store);
      if (preference.reduced) {
        final route = ModalRoute.of(tester.element(_activities))!;
        expect(route.animation!.status, AnimationStatus.completed);
      }
      await tester.pumpAndSettle();
      expect(find.text('Open the report'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'background acknowledgement does not wait for a decorative timer',
    (tester) async {
      _phone(tester);
      addTearDown(() => _resumeLifecycle(tester));
      final store = _Store();
      await _mount(tester, store);
      final gate = store.holdNextWrite();
      await _start(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      gate.complete(true);
      await tester.pump();
      await tester.pump();

      expect(_activities, findsOneWidget);
      _expectSavedStartOnly(store);
      _resumeLifecycle(tester);
      await tester.pumpAndSettle();
      expect(_activities, findsOneWidget);
      expect(store.writeCount, 1);
      expect(find.text('Open the report'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('offstage acknowledgement opens once without awaiting a ticker', (
    tester,
  ) async {
    _phone(tester);
    final ticker = ValueNotifier(true);
    addTearDown(ticker.dispose);
    final store = _Store();
    await _mount(tester, store, ticker: ticker);
    final gate = store.holdNextWrite();
    await _start(tester);
    ticker.value = false;
    await tester.pump();
    gate.complete(true);
    await tester.pump();
    await tester.pump();

    expect(_activities, findsOneWidget);
    _expectSavedStartOnly(store);
    ticker.value = true;
    await tester.pumpAndSettle();
    expect(_activities, findsOneWidget);
    expect(store.writeCount, 1);
    expect(find.text('Open the report'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('back during the handoff restores the closed office envelope', (
    tester,
  ) async {
    _phone(tester);
    final store = _Store();
    await _mount(tester, store);
    await _start(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    final route = ModalRoute.of(tester.element(_activities))!;
    expect(route.animation!.value, greaterThan(0));
    expect(route.animation!.value, lessThan(1));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_activities, findsNothing);
    expect(find.text('Your office'), findsOneWidget);
    expect(find.text('Continue activity'), findsOneWidget);
    _expectClosedEnvelope(tester);
    _expectSavedStartOnly(store);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
