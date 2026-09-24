import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/ui_review/review_animated_splash.dart';
import 'package:trimmy/ui_review/review_components.dart';
import 'package:trimmy/ui_review/review_first_desk.dart';
import 'package:trimmy/ui_review/review_journey.dart';
import 'package:trimmy/ui_review/welcome_review_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final page in ReviewPageId.values) {
    testWidgets('${page.label} renders at 360 by 800', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(useMaterial3: true, fontFamily: 'Manrope'),
          home: ReviewJourney(initialPage: page.index),
        ),
      );
      await tester.pump(const Duration(milliseconds: 950));

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Welcome note leads directly to practice and Back leaves startup',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: ReviewJourney(initialPage: ReviewPageId.welcomeNote.index),
        ),
      );
      await tester.pump();
      expect(find.text('Welcome to\nthe floor.'), findsOneWidget);
      expect(find.text('Meet the floor'), findsNothing);
      expect(find.byTooltip('Skip introduction'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Your first move.'), findsOneWidget);
      expect(find.text('Pick your persona.'), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Your desk.'), findsOneWidget);
      expect(find.text('Why are you here?'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Start my first day'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Welcome note keeps Continue available with large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
            padding: const EdgeInsets.only(top: 30, bottom: 24),
          ),
          child: child!,
        ),
        home: ReviewJourney(initialPage: ReviewPageId.welcomeNote.index),
      ),
    );
    await tester.pump();
    expect(find.text('Continue'), findsOneWidget);
    expect(find.byTooltip('Skip introduction'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Archived question X leaves the whole introduction', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: ReviewJourney(initialPage: ReviewPageId.goal.index)),
    );
    await tester.pump();
    expect(find.text('Why are you here?'), findsOneWidget);
    expect(find.text('No answer is wrong.'), findsOneWidget);
    await tester.tap(find.byTooltip('Skip questions'));
    await tester.pumpAndSettle();
    expect(find.text('Your desk.'), findsOneWidget);
    expect(find.text('Why are you here?'), findsNothing);
  });

  testWidgets(
    'first play carries the decision and persona to one result and Desk',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: ReviewJourney(initialPage: ReviewPageId.persona.index),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('The Shark'));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Your desk.'), findsOneWidget);
      await tester.ensureVisible(find.text('Try a trade'));
      await tester.tap(find.text('Try a trade'));
      await tester.pumpAndSettle();
      expect(find.text('Your first move.'), findsOneWidget);
      expect(find.text('What should we call you?'), findsNothing);
      expect(find.textContaining('A share is a small piece'), findsOneWidget);
      await tester.tap(find.text('Hint'));
      await tester.pumpAndSettle();
      expect(find.textContaining('A share is a small piece'), findsNothing);
      await tester.tap(find.text('Nvidia'));
      await tester.pump();
      await tester.ensureVisible(find.text(r'$50'));
      await tester.tap(find.text(r'$50'));
      await tester.pump();
      await tester.tap(find.text('Review buy'));
      await tester.pumpAndSettle();
      expect(find.text('Review your buy.'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Your first position.'), findsNothing);
      await tester.tap(find.text('Review buy'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Confirm buy'));
      await tester.tap(find.text('Confirm buy'));
      await tester.pumpAndSettle();
      expect(find.text('Day 1 complete'), findsOneWidget);
      expect(find.text('+20 Trims'), findsOneWidget);
      expect(find.textContaining('50'), findsWidgets);
      await tester.tap(find.text('Go to my desk'));
      await tester.pumpAndSettle();
      final desk = tester.widget<ReviewFirstDeskPage>(
        find.byType(ReviewFirstDeskPage),
      );
      expect(desk.position!.symbol, 'NVDA');
      expect(desk.position!.amount, 50);
      expect(desk.position!.shares, .4);
      expect(desk.persona, 'shark');
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(
        find.byType(TextField),
        'I want to understand this company.',
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Save my reason'));
      await tester.tap(find.text('Save my reason'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save progress'));
      await tester.tap(find.text('Save progress'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'joel');
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back to my desk'));
      await tester.pumpAndSettle();
      final returned = tester.widget<ReviewFirstDeskPage>(
        find.byType(ReviewFirstDeskPage),
      );
      expect(returned.position!.symbol, 'NVDA');
      expect(returned.username, 'joel');
      expect(returned.initialReason, 'I want to understand this company.');

      expect(find.text('Allow notifications'), findsNothing);
      expect(find.text('Why are you here?'), findsNothing);
      expect(find.text('What should we call you?'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('persona cancellation returns to Desk without forcing a trade', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ReviewJourney(initialPage: ReviewPageId.persona.index)),
    );
    await tester.pump();
    await tester.tap(find.text('Choose later'));
    await tester.pumpAndSettle();
    expect(find.byType(ReviewFirstDeskPage), findsOneWidget);
    expect(find.text('Why are you here?'), findsNothing);
  });

  testWidgets('username is optional save setup and has basic validation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ReviewJourney(initialPage: ReviewPageId.handle.index)),
    );
    await tester.pump();
    expect(
      tester
          .widget<ReviewPrimaryButton>(find.byType(ReviewPrimaryButton))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), 'joel');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Keep your career with you.'), findsOneWidget);
    expect(find.text('@joel'), findsOneWidget);
    await tester.tap(find.text('Back to my desk'));
    await tester.pumpAndSettle();
    expect(find.text('Your desk.'), findsOneWidget);
    expect(find.text('Allow notifications'), findsNothing);
  });

  testWidgets(
    'reminders and widget are optional and never fake native success',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewJourney(initialPage: ReviewPageId.notifications.index),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Allow notifications'));
      await tester.pumpAndSettle();
      expect(find.text('Notification permission preview'), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('Your desk.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final page in [
    ReviewPageId.persona,
    ReviewPageId.starterMarket,
    ReviewPageId.firstPosition,
    ReviewPageId.widgetSetup,
  ]) {
    testWidgets('${page.label} remains usable with 200 percent text', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: ReviewJourney(initialPage: page.index),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the username preview changes with the field', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: ReviewJourney(initialPage: ReviewPageId.handle.index)),
    );
    await tester.pump();
    expect(find.text('YOUR FLOOR CARD'), findsNothing);
    expect(find.text('Username'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'joel');
    await tester.pump();
    expect(find.text('@joel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'closing entry sign-in restores the settled welcome without replay',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewJourney(initialPage: ReviewPageId.welcome.index),
        ),
      );
      await tester.pump(const Duration(milliseconds: 2300));
      expect(
        tester
            .widget<WelcomeReviewScreen>(find.byType(WelcomeReviewScreen))
            .playEntrance,
        isTrue,
      );
      await tester.tap(find.text('Sign in or create account'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byTooltip('Close sign in'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester
            .widget<WelcomeReviewScreen>(find.byType(WelcomeReviewScreen))
            .playEntrance,
        isFalse,
      );
      expect(find.text('Start my first day'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Welcome remains usable at 200 percent text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 800),
          textScaler: TextScaler.linear(2),
        ),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(useMaterial3: true, fontFamily: 'Manrope'),
          home: ReviewJourney(initialPage: ReviewPageId.welcome.index),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 950));

    expect(
      find.bySemanticsLabel(
        'Start your Wall Street career. Tokenized stocks orbit the invitation.',
      ),
      findsOneWidget,
    );
    expect(find.text('Start my first day'), findsOneWidget);
    expect(find.text('Sign in or create account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Review startup holds the splash until local audio is ready', (
    tester,
  ) async {
    final prepared = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(home: ReviewJourney(startupReady: prepared.future)),
    );
    await tester.pump(const Duration(milliseconds: 2100));
    expect(find.text('Start my first day'), findsNothing);
    prepared.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Start my first day'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Welcome actions clear iPhone inset and remain above the art', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var starts = 0;
    var accounts = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: WelcomeReviewScreen(
          onStart: () => starts++,
          onHaveAccount: () => accounts++,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('trimmy'), findsNothing);
    expect(
      tester.getBottomRight(find.byType(TextButton)).dy,
      lessThanOrEqualTo(852 - 34),
    );
    await tester.tap(find.text('Sign in or create account'));
    // Re-enter Welcome as a fresh visitor to exercise its other navigation.
    await tester.pumpWidget(
      MaterialApp(
        home: WelcomeReviewScreen(
          key: const ValueKey('fresh-welcome'),
          onStart: () => starts++,
          onHaveAccount: () => accounts++,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text('Start my first day'));
    await tester.pump();
    expect(accounts, 1);
    expect(starts, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Welcome interruption cancels entrance and resumes quietly', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WelcomeReviewScreen(onStart: () {}, onHaveAccount: () {}),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 3));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Start my first day').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Splash settles once and holds until startup is ready', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final ready = Completer<void>();
    var continueCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, fontFamily: 'Manrope'),
        home: ReviewColdLaunchPage(
          ready: ready.future,
          onContinue: () => continueCount++,
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.text('trimmy'), findsOneWidget);
    expect(continueCount, 0);

    ready.complete();
    await tester.pump();
    expect(continueCount, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(continueCount, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Splash reduces to a short fade when motion is disabled', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var continueCount = 0;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(360, 800),
          disableAnimations: true,
        ),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(useMaterial3: true, fontFamily: 'Manrope'),
          home: ReviewColdLaunchPage(onContinue: () => continueCount++),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 1150));
    expect(continueCount, 1);
    expect(tester.takeException(), isNull);
  });
}
