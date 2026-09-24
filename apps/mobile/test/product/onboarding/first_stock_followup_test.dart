import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/product/design/product_theme.dart';
import 'package:trimmy/product/onboarding/first_stock_followup.dart';
import 'package:trimmy/product/onboarding/onboarding_models.dart';
import 'package:trimmy/ui_review/review_feedback.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ReviewFeedback.shared.load();
    ReviewFeedback.shared.sound = false;
    ReviewFeedback.shared.haptics = false;
  });
  testWidgets('celebration hands off to account choice before reminders', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final accountChoice = Completer<void>();
    var handedOff = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: FirstStockFollowup(
          preferences: prefs,
          principal: 'tutorial',
          name: 'Apple',
          symbol: 'AAPLx',
          shares: '0.2',
          orderId: 'confirmed-order',
          onCelebrationContinue: () async {
            handedOff++;
            await accountChoice.future;
          },
          onFinish: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('You’ve placed your first order!'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(handedOff, 1);
    expect(find.byType(ReminderPreferencePage), findsNothing);
    accountChoice.complete();
    await tester.pumpAndSettle();
    expect(find.byType(ReminderPreferencePage), findsOneWidget);
  });

  for (final sameOrder in [true, false]) {
    testWidgets(
      'claimed tutorial preserves celebration only for its confirmed order ($sameOrder)',
      (tester) async {
        final prefs = await SharedPreferences.getInstance();
        await FirstStockFollowup.acknowledgeCelebration(
          prefs,
          'tutorial',
          'confirmed-order',
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: productTheme(),
            home: FirstStockFollowup(
              preferences: prefs,
              principal: 'signed-in-account',
              name: 'Apple',
              symbol: 'AAPLx',
              shares: '0.2',
              orderId: sameOrder ? 'confirmed-order' : 'another-order',
              onFinish: (_) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(ReminderPreferencePage),
          sameOrder ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('You’ve placed your first order!'),
          sameOrder ? findsNothing : findsOneWidget,
        );
        expect(ReminderPreferences.read(prefs, 'signed-in-account'), isNull);
      },
    );
  }

  testWidgets(
    'quiet choice never requests permission and saves for only this account',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      var requests = 0, finished = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: productTheme(),
          home: ReminderPreferencePage(
            preferences: prefs,
            principal: 'account-a',
            onDone: () async {
              finished++;
            },
            requestPermission: () async {
              requests++;
              return OnboardingNotificationStatus.granted;
            },
          ),
        ),
      );
      await tester.tap(find.text('Keep it quiet'));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(requests, 0);
      expect(finished, 1);
      expect(
        ReminderPreferences.read(prefs, 'account-a'),
        ReminderPreference.off,
      );
      expect(ReminderPreferences.read(prefs, 'account-b'), isNull);
    },
  );
  testWidgets(
    'denied permission keeps a usable Continue without prompting again',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      var requests = 0, finished = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: productTheme(),
          home: ReminderPreferencePage(
            preferences: prefs,
            principal: 'account-a',
            onDone: () async {
              finished++;
            },
            requestPermission: () async {
              requests++;
              return OnboardingNotificationStatus.denied;
            },
          ),
        ),
      );
      await tester.tap(find.text('Once a day'));
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(finished, 0);
      expect(requests, 1);
      expect(find.textContaining('Notifications are off.'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(finished, 1);
      expect(requests, 1);
    },
  );
  testWidgets(
    'funding choice waits for the final introduction save and blocks double taps',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(FirstStockFollowup.stepKey('account-a'), 2);
      final selections = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: productTheme(),
          home: FirstStockFollowup(
            preferences: prefs,
            principal: 'account-a',
            name: 'Apple',
            symbol: 'AAPLx',
            shares: '0.2',
            onFinish: (money) async {
              selections.add(money);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add money'));
      await tester.tap(find.text('Add money'));
      await tester.pumpAndSettle();
      expect(selections, [true]);
    },
  );
}
