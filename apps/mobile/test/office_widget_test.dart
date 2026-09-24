import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:trimmy/main.dart';
import 'package:trimmy/features/office/sheets.dart';
import 'package:trimmy/features/journey/journey_catalog.dart';
import 'package:trimmy/features/journey/journey_screen.dart';
import 'package:trimmy/features/practice/practice_controller.dart';

class MemoryStore implements PracticeStore {
  String? data;
  @override
  Future<String?> read() async => data;
  @override
  Future<void> write(String value) async {
    data = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/manrope/Manrope-Variable.ttf'));
    await font.load();
  });
  testWidgets(
    'office, desk and journal fit a narrow phone at large text size',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = PracticeController(store: MemoryStore());
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: TrimmyApp(controller: controller),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final tab in [1, 2, 0]) {
        controller.setTab(tab);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'Tab $tab must not overflow at 200% text',
        );
      }
    },
  );

  testWidgets(
    'complete a session, earn once and restore its journal reflection',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = MemoryStore();
      final controller = PracticeController(store: store);
      addTearDown(controller.dispose);
      await tester.pumpWidget(TrimmyApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start session'));
      await tester.pumpAndSettle();
      expect(find.text('Pull up a chair.'), findsOneWidget);
      await tester.tap(find.text('Let’s get into it'));
      await tester.pumpAndSettle();
      for (final step in firstFloorChapter.steps.where(
        (step) => step.kind == JourneyStepKind.decision,
      )) {
        await tester.ensureVisible(find.text(step.choices.first.label));
        await tester.tap(find.text(step.choices.first.label));
        await tester.pumpAndSettle();
        expect(find.text(step.choices.first.feedback), findsOneWidget);
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
      }
      await tester.enterText(
        find.byType(TextField),
        'I want to understand the total fees before deciding.',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finish session'));
      await tester.pumpAndSettle();
      expect(controller.completedChapterIds, contains('first-floor'));
      expect(controller.learningPoints, 30);
      expect(controller.currentStreak, 1);
      expect(find.text('+30 learning points'), findsOneWidget);
      await tester.tap(find.text('Read my journal'));
      await tester.pumpAndSettle();
      expect(find.text('Your journal.'), findsOneWidget);
      expect(
        find.text('I want to understand the total fees before deciding.'),
        findsOneWidget,
      );
      final restored = await PracticeController.load(store: store);
      addTearDown(restored.dispose);
      expect(
        restored.chapterCompletions['first-floor']?.reflection,
        'I want to understand the total fees before deciding.',
      );
      expect(restored.nextChapter?.id, 'read-the-room');
      expect(restored.activeSession, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rapid opening stays one route and leaving resumes the same answer',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = PracticeController(store: MemoryStore());
      addTearDown(controller.dispose);
      await tester.pumpWidget(TrimmyApp(controller: controller));
      await tester.pumpAndSettle();
      final context = tester.element(find.text('Start session'));
      unawaited(openJourney(context, controller, firstFloorChapter.id));
      unawaited(openJourney(context, controller, firstFloorChapter.id));
      await tester.pumpAndSettle();
      expect(find.byType(JourneyScreen, skipOffstage: false), findsOneWidget);
      await tester.tap(find.text('Let’s get into it'));
      await tester.pumpAndSettle();
      final choice = firstFloorChapter.steps[1].choices.first;
      await tester.ensureVisible(find.text(choice.label));
      await tester.tap(find.text(choice.label));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Leave session'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave session'));
      await tester.pumpAndSettle();
      expect(find.byType(JourneyScreen), findsNothing);
      expect(find.text('Continue session'), findsOneWidget);
      await tester.tap(find.text('Continue session'));
      await tester.pumpAndSettle();
      expect(find.text(choice.feedback), findsOneWidget);
      expect(controller.activeSession?.stepIndex, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('offer form rejects an invalid handle and saves a local draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = PracticeController(store: MemoryStore());
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: InviteSheet(controller: controller)),
      ),
    );
    await tester.enterText(find.byType(TextFormField).first, '@not a handle');
    await tester.tap(find.text('Preview offer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Use an X handle'), findsOneWidget);
    expect(controller.drafts, isEmpty);
    await tester.enterText(find.byType(TextFormField).first, '@goodfriend');
    await tester.tap(find.text('Preview offer'));
    await tester.pumpAndSettle();
    expect(find.text('Dear @goodfriend,'), findsOneWidget);
    expect(find.text('Save draft'), findsOneWidget);
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();
    expect(controller.drafts.single.handle, '@goodfriend');
    expect(tester.takeException(), isNull);
  });
}
