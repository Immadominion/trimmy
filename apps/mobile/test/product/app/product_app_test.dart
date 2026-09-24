import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/markets/config.dart';
import 'package:trimmy/markets/stock_research_host.dart';
import 'package:trimmy/product/app/product_app.dart';
import 'package:trimmy/product/account/product_sign_in_screen.dart';
import 'package:trimmy/product/onboarding/first_stock_followup.dart';
import 'package:trimmy/product/onboarding/onboarding_models.dart';
import 'package:trimmy/ui_review/review_welcome_note.dart';
import 'package:trimmy/ui_review/review_animated_splash.dart';
import 'package:trimmy/ui_review/review_feedback.dart';
import 'package:trimmy/ui_review/welcome_review_screen.dart';

void main() {
  setUp(() async {
    await ReviewFeedback.shared.load();
    ReviewFeedback.shared.sound = false;
    ReviewFeedback.shared.haptics = false;
  });

  testWidgets('a new install opens the product onboarding', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      StockResearchHost(
        config: StockResearchConfig.parse(apiUrl: ''),
        child: TrimmyProductApp(
          preferences: preferences,
          account: null,
          accountConfigurationFailed: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(WelcomeReviewScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('cast-portrait-sal')), findsNothing);
    expect(find.text('Start my first day'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final legacyWelcomeSeen in [false, true]) {
    testWidgets(
      'welcome keeps the paper note before purchase and sign-in (legacy seen: $legacyWelcomeSeen)',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          if (legacyWelcomeSeen) 'trimmy.entry.welcome-seen.v1': true,
        });
        final preferences = await SharedPreferences.getInstance();
        await tester.pumpWidget(
          StockResearchHost(
            config: StockResearchConfig.parse(apiUrl: ''),
            child: TrimmyProductApp(
              preferences: preferences,
              account: null,
              accountConfigurationFailed: false,
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(WelcomeReviewScreen), findsOneWidget);
        await tester.tap(find.text('Start my first day'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(ReviewWelcomeNotePage), findsOneWidget);
        expect(find.byType(ProductSignInScreen), findsNothing);
        await tester.tap(find.text('Continue'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Pick a company.'), findsOneWidget);
        expect(find.byType(ProductSignInScreen), findsNothing);
        expect(find.byType(ReviewWelcomeNotePage), findsNothing);
        expect(preferences.getBool('trimmy.entry.guest-chosen.v1'), isNull);
        expect(preferences.getBool('trimmy.product.first-trade.v1'), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'leaving the tutorial still requires an explicit account choice',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        StockResearchHost(
          config: StockResearchConfig.parse(apiUrl: ''),
          child: TrimmyProductApp(
            preferences: preferences,
            account: null,
            accountConfigurationFailed: false,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Start my first day'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final page = find.byType(IconButton);
      expect(page, findsWidgets);
      await tester.tap(find.byTooltip('Skip first trade'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey('startup-sign-in-gate')),
        findsOneWidget,
      );
      expect(preferences.getBool('trimmy.entry.guest-chosen.v1'), isNull);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('startup-sign-in-gate')),
        findsOneWidget,
      );
      expect(preferences.getBool('trimmy.entry.guest-chosen.v1'), isNull);
      await tester.tap(find.byKey(const ValueKey('sign-in-later')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(preferences.getBool('trimmy.entry.guest-chosen.v1'), isTrue);
      expect(find.byKey(const ValueKey('startup-sign-in-gate')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'after congratulations sign-in precedes reminders, including after restart',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'trimmy.product.profile.v1': jsonEncode(
          const OnboardingProfile().toJson(),
        ),
        'trimmy.product.first-trade.v1': true,
        FirstStockFollowup.stepKey('local'): 1,
      });
      final preferences = await SharedPreferences.getInstance();
      Widget app() => StockResearchHost(
        config: StockResearchConfig.parse(apiUrl: ''),
        child: TrimmyProductApp(
          preferences: preferences,
          account: null,
          accountConfigurationFailed: false,
        ),
      );
      for (var launch = 0; launch < 2; launch++) {
        await tester.pumpWidget(app());
        await tester.pump();
        expect(
          find.byKey(const ValueKey('startup-sign-in-gate')),
          findsOneWidget,
        );
        expect(find.byType(ReminderPreferencePage), findsNothing);
        expect(find.text('Pick a company.'), findsNothing);
        expect(preferences.getBool('trimmy.entry.guest-chosen.v1'), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('real startup initializes behind one finite splash', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    Widget app() => StockResearchHost(
      config: StockResearchConfig.parse(apiUrl: ''),
      child: TrimmyProductApp(
        preferences: preferences,
        account: null,
        accountConfigurationFailed: false,
        showStartupSplash: true,
      ),
    );

    await tester.pumpWidget(app());
    expect(find.byType(ProductExperience), findsOneWidget);
    expect(find.byType(ReviewColdLaunchPage), findsOneWidget);
    expect(find.byType(WelcomeReviewScreen), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.byType(ReviewColdLaunchPage), findsNothing);
    expect(find.byType(WelcomeReviewScreen), findsOneWidget);

    // Account-host rebuilds retain the app state and cannot replay startup.
    await tester.pumpWidget(app());
    expect(find.byType(ReviewColdLaunchPage), findsNothing);
    expect(find.byType(WelcomeReviewScreen), findsOneWidget);
    expect(preferences.containsKey('trimmy.product.profile.v1'), isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('first trade market does not invent a paper desk', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'trimmy.entry.guest-chosen.v1': true,
      'trimmy.product.profile.v1': jsonEncode({
        'version': 1,
        'goal': 'learn',
        'knowledge': 'nothing',
        'persona': 'oracle',
        'dailyGoal': 'one-mission',
        'handle': 'rookie_one',
      }),
      'trimmy.product.notifications.v1': 'notRequested',
    });
    final preferences = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      StockResearchHost(
        config: StockResearchConfig.parse(apiUrl: ''),
        child: TrimmyProductApp(
          preferences: preferences,
          account: null,
          accountConfigurationFailed: false,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Pick a company.'), findsOneWidget);
    expect(find.text('Select price'), findsOneWidget);
    expect(find.textContaining('paper desk is unavailable'), findsOneWidget);
    expect(find.textContaining("Here's 10,000 paper"), findsNothing);
    expect(find.byKey(const ValueKey('cast-portrait-sal')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'existing anonymous progress still requires an explicit guest choice',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'trimmy.product.profile.v1': jsonEncode({
          'version': 1,
          'goal': 'practice',
          'knowledge': 'basics',
          'persona': 'wolf',
          'dailyGoal': 'show-up',
          'handle': 'paperwolf',
        }),
        'trimmy.product.notifications.v1': 'denied',
        'trimmy.product.first-trade.v1': true,
        'trimmy.product.first-position.v1': true,
        'trimmy.product.day-one.v1': true,
      });
      final preferences = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        StockResearchHost(
          config: StockResearchConfig.parse(apiUrl: ''),
          child: TrimmyProductApp(
            preferences: preferences,
            account: null,
            accountConfigurationFailed: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('startup-sign-in-gate')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('sign-in-later')), findsOneWidget);
      expect(find.text('Continue as guest'), findsOneWidget);
      expect(find.text('Later'), findsNothing);
    },
  );
}
