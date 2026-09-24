import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/ui_review/review_animated_splash.dart';
import 'package:trimmy/ui_review/review_feedback.dart';
import 'package:trimmy/ui_review/review_amount_picker.dart';
import 'package:trimmy/ui_review/review_first_desk.dart';
import 'package:trimmy/ui_review/review_first_play.dart';
import 'package:trimmy/ui_review/review_journey.dart';
import 'package:trimmy/ui_review/review_market_pages.dart';
import 'package:trimmy/ui_review/welcome_review_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ReviewFeedback.shared.sound = false;
    ReviewFeedback.shared.haptics = false;
  });

  testWidgets('the short welcome note leads directly to company choices', (
    tester,
  ) async {
    await _mount(tester, ReviewPageId.welcomeNote);

    expect(
      find.text(
        'Your first day starts with practice.\n\nPick a company. It’s free.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Nothing to deposit'), findsNothing);
    await _tap(tester, find.text('Continue'));

    expect(find.byType(ReviewFirstPlayPage), findsOneWidget);
    expect(find.text('Pick a company.'), findsOneWidget);
    expect(find.text('Pick your persona.'), findsNothing);
    await _back(tester);
    _expectEmptyDesk(tester);
  });

  testWidgets('note X skips to an empty Desk and Back never replays startup', (
    tester,
  ) async {
    await _mount(tester, ReviewPageId.welcome);
    await _tap(tester, find.text('Start my first day'));
    await _tap(tester, find.byTooltip('Skip introduction'));

    _expectEmptyDesk(tester);
    for (var i = 0; i < 3; i++) {
      await _back(tester);
      _expectNoStartup();
      expect(find.byType(ReviewFirstPlayPage), findsNothing);
    }
  });

  testWidgets('skipped first trade can be retried and confirmed exactly once', (
    tester,
  ) async {
    await _mount(tester, ReviewPageId.starterMarket);
    await _tap(tester, find.byTooltip('Skip first trade'));
    _expectEmptyDesk(tester);

    await _tap(tester, find.text('Try a trade'));
    await _selectNvidia50(tester);
    await _tap(tester, find.text('Review buy'));
    final confirm = find.text('Confirm buy');
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    // A second tap before the next frame must not create another completion.
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(find.byType(ReviewFirstDayResultPage), findsOneWidget);
    expect(find.bySemanticsLabel('Buy confirmed'), findsOneWidget);
    expect(find.text('Day 1 complete'), findsOneWidget);
    expect(find.text('+20 Trims'), findsOneWidget);
    final result = tester.widget<ReviewFirstDayResultPage>(
      find.byType(ReviewFirstDayResultPage),
    );
    _expectNvidia50(result.position);

    await _back(tester);
    _expectNvidia50(_desk(tester).position!);
    expect(find.byType(ReviewFirstDayResultPage), findsNothing);
    await _back(tester);
    _expectNoStartup();
    expect(tester.takeException(), isNull);
  });

  testWidgets('review edit and system Back preserve the unconfirmed choice', (
    tester,
  ) async {
    await _mount(tester, ReviewPageId.starterMarket);
    await _selectNvidia50(tester);

    for (final useSystemBack in [false, true]) {
      await _tap(tester, find.text('Review buy'));
      expect(find.text('Review your buy.'), findsOneWidget);
      expect(find.bySemanticsLabel('Buy confirmed'), findsNothing);
      expect(find.text(r'$125.00'), findsOneWidget);
      if (useSystemBack) {
        await _back(tester);
      } else {
        await tester.tapAt(const Offset(12, 30));
        await tester.pumpAndSettle();
      }

      expect(find.text('Review your buy.'), findsNothing);
      expect(find.byType(ReviewFirstPlayPage), findsOneWidget);
      final picker = tester.widget<ReviewAmountPicker>(
        find.byType(ReviewAmountPicker),
      );
      expect(picker.value, 50);
      _expectNoCompletion();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('review X skips the complete trade without granting rewards', (
    tester,
  ) async {
    await _mount(tester, ReviewPageId.starterMarket);
    await _selectNvidia50(tester);
    await _tap(tester, find.text('Review buy'));
    // The sheet and the obscured page both expose this action; tap the sheet.
    await _tap(tester, find.byTooltip('Skip first trade').hitTestable());

    _expectEmptyDesk(tester);
    expect(find.text('Review your buy.'), findsNothing);
    expect(find.byType(ReviewFirstPlayPage), findsNothing);
    await _back(tester);
    _expectNoStartup();
    _expectNoCompletion();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'persona commits on Continue and all cancellation paths discard drafts',
    (tester) async {
      await _mount(tester, ReviewPageId.desk);
      await _tap(tester, find.byTooltip('Change persona'));
      await _tap(tester, find.text('The Shark'));
      await _tap(tester, find.text('Continue'));
      expect(_desk(tester).persona, 'shark');

      for (final cancel in ['x', 'later', 'back']) {
        await _tap(tester, find.byTooltip('Change persona'));
        await _tap(tester, find.text('The Wolf'));
        switch (cancel) {
          case 'x':
            await _tap(tester, find.byTooltip('Skip persona'));
          case 'later':
            await _tap(tester, find.text('Choose later'));
          case 'back':
            await _back(tester);
        }

        expect(_desk(tester).persona, 'shark');
        _expectEmptyDesk(tester);
        _expectNoStartup();
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing confirmation falls back to an empty Desk with stock browsing',
    (tester) async {
      await _mount(tester, ReviewPageId.firstPosition);
      _expectEmptyDesk(tester);
      expect(find.text('Try a trade'), findsOneWidget);

      await _tap(tester, find.text('Browse stocks'));
      expect(
        tester.widget<ReviewMarketPage>(find.byType(ReviewMarketPage)).mode,
        ReviewMarketMode.browse,
      );
      expect(find.byType(ReviewFirstPlayPage), findsNothing);
      await _back(tester);
      _expectEmptyDesk(tester);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _mount(WidgetTester tester, ReviewPageId page) async {
  await tester.binding.setSurfaceSize(const Size(393, 852));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true, fontFamily: 'Dejanire Sans'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          padding: const EdgeInsets.only(top: 24, bottom: 24),
        ),
        child: child!,
      ),
      home: ReviewJourney(initialPage: page.index),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

Future<void> _selectNvidia50(WidgetTester tester) async {
  await _tap(tester, find.text('Nvidia'));
  await _tap(tester, find.text(r'$50'));
}

ReviewFirstDeskPage _desk(WidgetTester tester) =>
    tester.widget<ReviewFirstDeskPage>(find.byType(ReviewFirstDeskPage));

void _expectEmptyDesk(WidgetTester tester) {
  expect(find.byType(ReviewFirstDeskPage), findsOneWidget);
  expect(_desk(tester).position, isNull);
  _expectNoCompletion();
}

void _expectNoCompletion() {
  expect(find.byType(ReviewFirstDayResultPage), findsNothing);
  expect(find.text('Day 1 complete'), findsNothing);
  expect(find.text('+20 Trims'), findsNothing);
  expect(find.text('Practice buy confirmed'), findsNothing);
  expect(find.bySemanticsLabel('Buy confirmed'), findsNothing);
}

void _expectNoStartup() {
  expect(find.byType(WelcomeReviewScreen), findsNothing);
  expect(find.byType(ReviewColdLaunchPage), findsNothing);
}

void _expectNvidia50(ReviewPracticePosition position) {
  expect(position.company, 'Nvidia');
  expect(position.symbol, 'NVDA');
  expect(position.amount, 50);
  expect(position.price, 125);
  expect(position.shares, .4);
}
