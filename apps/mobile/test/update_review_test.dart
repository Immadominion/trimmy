import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/design_study/activities.dart';
import 'package:trimmy/design_study/mission.dart';
import 'package:trimmy/design_study/progress.dart';
import 'package:trimmy/design_study/update_review.dart';

import 'sample_progress_test.dart' show storeState;
import 'update_progress_test.dart' show unlockedUpdate;

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(Widget child, {bool accessibleNavigation = false}) => MaterialApp(
  theme: ThemeData(fontFamily: 'Manrope'),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      // Keep the two platform preferences independent so this test cannot pass
      // merely because the reduced-motion branch happens to suppress motion.
      disableAnimations: false,
      accessibleNavigation: accessibleNavigation,
    ),
    child: child!,
  ),
  home: child,
);

Future<void> _tapWithoutElapsedTime(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  // Flush acknowledgement, rebuilding and disposal without advancing time.
  // Waiting for pumpAndSettle here would hide an unwanted finite transition.
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void _expectSettledContent(WidgetTester tester, String label) {
  final content = find.text(label);
  expect(content, findsOneWidget);
  final fades = tester.widgetList<FadeTransition>(
    find.ancestor(of: content, matching: find.byType(FadeTransition)),
  );
  final slides = tester.widgetList<SlideTransition>(
    find.ancestor(of: content, matching: find.byType(SlideTransition)),
  );
  expect(fades, isNotEmpty);
  expect(slides, isNotEmpty);
  for (final fade in fades) {
    expect(fade.opacity.value, 1, reason: '$label must already be readable');
  }
  for (final slide in slides) {
    expect(
      slide.position.value,
      Offset.zero,
      reason: '$label must already be settled',
    );
  }
  // A native tap ripple can still have a ticker here. Check the content's
  // actual transforms now, and check for leaked callbacks after disposal.
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

  testWidgets('a year-only wrong draft brings back the missing profit fact', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(
        const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(22),
            child: UpdateCorrection(
              choiceId: 'dated-growth+trial-result+current-growth',
            ),
          ),
        ),
      ),
    );
    expect(find.text('One claim goes beyond the notes.'), findsOneWidget);
    expect(find.text('Check the year'), findsOneWidget);
    expect(find.text('Keep the trial group'), findsNothing);
    expect(find.text('Bring these facts back'), findsOneWidget);
    expect(
      find.text(r'In 2025, profit fell from $400 to $200.'),
      findsOneWidget,
    );
    // These two facts were already in the submitted draft; the correction
    // should restore the missing fact rather than repeat every accepted line.
    expect(find.text('In 2025, users grew 80%.'), findsNothing);
    expect(find.text('8 of 10 beta testers liked Aster.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'accessible activity stages settle without elapsed animation time or leaked tickers',
    (tester) async {
      _phone(tester);
      final store = storeState(
        unlockedUpdate().startActivity(OfficeActivityIds.prepareTheUpdate),
      );
      final repository = store.repository();
      await tester.pumpWidget(
        _app(
          ActivityStudy(
            repository: repository,
            activity: prepareTheUpdateActivity,
          ),
          accessibleNavigation: true,
        ),
      );
      await tester.pumpAndSettle();

      await _tapWithoutElapsedTime(tester, 'Open your notes');
      expect(repository.state.active!.stage, 1);
      _expectSettledContent(tester, 'Aster user report');
      await _tapWithoutElapsedTime(tester, 'Build the update');
      expect(repository.state.active!.stage, 2);
      _expectSettledContent(tester, 'Build the update');
      expect(find.text('Read your notes'), findsNothing);
      await _tapWithoutElapsedTime(tester, 'Open your notes again');
      expect(repository.state.active!.stage, 1);
      _expectSettledContent(tester, 'Aster user report');
      expect(find.text('On your desk'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
