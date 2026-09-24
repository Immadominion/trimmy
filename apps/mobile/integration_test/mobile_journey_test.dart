import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/core/audio/practice_audio.dart';
import 'package:trimmy/features/journey/journey_catalog.dart';
import 'package:trimmy/features/practice/practice_controller.dart';
import 'package:trimmy/main.dart';

/// Uses native preferences, isolated from the real application's practice key.
class NativeJourneyTestStore implements PracticeStore {
  NativeJourneyTestStore(this.preferences);
  static const key = 'trimmy.integration.mobile_journey.v2';
  final SharedPreferencesAsync preferences;

  @override
  Future<String?> read() => preferences.getString(key);

  @override
  Future<void> write(String value) => preferences.setString(key, value);
}

Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native first chapter, journal, preferences reload and portfolio navigation',
    (tester) async {
      final preferences = SharedPreferencesAsync();
      final store = NativeJourneyTestStore(preferences);
      await preferences.remove(NativeJourneyTestStore.key);
      PracticeController? current;
      addTearDown(() async {
        await current?.close();
        await preferences.remove(NativeJourneyTestStore.key);
      });
      var controller = await PracticeController.load(
        store: store,
        audio: SilentPracticeAudio(),
      );
      current = controller;
      await tester.pumpWidget(TrimmyApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.text('Your daily office'), findsOneWidget);
      expect(controller.soundEnabled, isFalse);

      // Exercise the real settings UI, rather than assigning test-only flags.
      await tester.tap(find.byTooltip('Office settings'));
      await tester.pumpAndSettle();
      final motionTile = find.widgetWithText(SwitchListTile, 'Reduce motion');
      expect(motionTile, findsOneWidget);
      expect(tester.widget<SwitchListTile>(motionTile).value, isFalse);
      await tester.tap(motionTile);
      await tester.pumpAndSettle();
      await controller.flushPendingWrites();
      expect(controller.reduceMotion, isTrue);
      expect(tester.widget<SwitchListTile>(motionTile).value, isTrue);
      Navigator.of(tester.element(motionTile)).pop();
      await tester.pumpAndSettle();

      await tapText(tester, 'Start session');
      expect(find.text(firstFloorChapter.steps.first.title), findsOneWidget);
      final route = ModalRoute.of(
        tester.element(find.text(firstFloorChapter.steps.first.title)),
      );
      expect(
        (route as TransitionRoute<dynamic>).transitionDuration,
        Duration.zero,
      );
      await tapText(tester, 'Let’s get into it');

      final decisions = firstFloorChapter.steps
          .where((step) => step.kind == JourneyStepKind.decision)
          .toList();
      for (var index = 0; index < decisions.length; index++) {
        final step = decisions[index];
        final choice = step.choices[index];
        expect(find.text(step.title), findsOneWidget);
        expect(find.text(step.question), findsOneWidget);
        await tapText(tester, choice.label);
        expect(find.text(choice.feedback), findsOneWidget);
        expect(controller.activeSession?.answers[step.id], index);
        await tester.ensureVisible(find.text(choice.feedback));
        await tapText(tester, 'Continue');
      }

      expect(find.text(firstFloorChapter.steps.last.title), findsOneWidget);
      const reflection =
          'I will check the business, the total cost, and the risks behind the names.';
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), reflection);
      await tester.pumpAndSettle();
      await tapText(tester, 'Finish session');
      expect(find.text('+30 learning points'), findsOneWidget);
      expect(find.text('${firstFloorChapter.title} complete'), findsOneWidget);
      expect(
        controller.chapterCompletions[firstFloorChapter.id]?.reflection,
        reflection,
      );
      expect(controller.learningPoints, 30);
      expect(controller.currentStreak, 1);
      expect(controller.activeSession, isNull);
      expect(controller.storageWarning, isNull);
      await tapText(tester, 'Read my journal');
      expect(find.text('Your journal.'), findsOneWidget);
      await tester.ensureVisible(find.text(reflection));
      expect(find.text(reflection), findsOneWidget);

      await controller.flushPendingWrites();
      final persisted =
          jsonDecode((await store.read())!) as Map<String, dynamic>;
      expect(persisted['version'], 2);
      expect(persisted['reduceMotion'], isTrue);
      expect((persisted['journey'] as Map)['session'], isNull);

      // Rebuild with a fresh controller read through the native plugin.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await controller.close();
      controller = await PracticeController.load(
        store: store,
        audio: SilentPracticeAudio(),
      );
      current = controller;
      expect(controller.reduceMotion, isTrue);
      expect(controller.soundEnabled, isFalse);
      expect(controller.learningPoints, 30);
      expect(controller.nextChapter?.id, 'read-the-room');
      expect(
        controller.chapterCompletions[firstFloorChapter.id]?.reflection,
        reflection,
      );
      await tester.pumpWidget(TrimmyApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.text('Your journal.'), findsOneWidget);
      await tester.ensureVisible(find.text(reflection));
      expect(find.text(reflection), findsOneWidget);

      await tapText(tester, 'Portfolio');
      expect(find.text('Fictional portfolio'), findsOneWidget);
      expect(find.text(r'$10.24'), findsOneWidget);
      await tapText(tester, 'Season example');
      expect(
        tester
            .widget<ChoiceChip>(
              find.widgetWithText(ChoiceChip, 'Season example'),
            )
            .selected,
        isTrue,
      );
      await tapText(tester, 'Office');
      expect(find.text('Read the room'), findsWidgets);
      expect(find.text('Start session'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
