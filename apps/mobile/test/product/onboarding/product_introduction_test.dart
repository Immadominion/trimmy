import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/design/product_theme.dart';
import 'package:trimmy/product/onboarding/product_introduction.dart';
import 'package:trimmy/ui_review/review_feedback.dart';
import 'package:trimmy/ui_review/review_welcome_note.dart';

void main() {
  setUp(() async {
    await ReviewFeedback.shared.load();
    ReviewFeedback.shared.sound = false;
    ReviewFeedback.shared.haptics = false;
  });

  Future<void> open(
    WidgetTester tester, {
    required Future<void> Function() onContinue,
    required Future<void> Function() onSkip,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: ProductIntroduction(
          onContinue: onContinue,
          onSkip: onSkip,
          onHaveAccount: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start my first day'));
    await tester.pumpAndSettle();
  }

  testWidgets('welcome leads to approved note with no setup questions', (
    tester,
  ) async {
    var continued = 0;
    var skipped = 0;
    await open(
      tester,
      onContinue: () async {
        continued++;
      },
      onSkip: () async {
        skipped++;
      },
    );
    expect(find.byType(ReviewWelcomeNotePage), findsOneWidget);
    expect(
      find.text(
        'Your first day starts with practice.\n\nPick a company. It’s free.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Five quick questions'), findsNothing);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(continued, 1);
    expect(skipped, 0);
  });

  testWidgets('X and system Back skip the complete introduction', (
    tester,
  ) async {
    var skipped = 0;
    await open(
      tester,
      onContinue: () async {},
      onSkip: () async {
        skipped++;
      },
    );
    await tester.tap(find.byTooltip('Skip introduction'));
    await tester.pumpAndSettle();
    expect(skipped, 1);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(skipped, 2);
    expect(find.text('Start my first day'), findsNothing);
  });

  testWidgets(
    'failed persistence keeps note retryable and prevents duplicate submits',
    (tester) async {
      var writes = 0;
      final pending = Completer<void>();
      await open(
        tester,
        onContinue: () {
          writes++;
          return pending.future;
        },
        onSkip: () async {},
      );
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.tap(find.text('Continue'), warnIfMissed: false);
      await tester.pump();
      expect(writes, 1);
      pending.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Could not save that step. Try again.'), findsOneWidget);
      expect(find.byType(ReviewWelcomeNotePage), findsOneWidget);
    },
  );
}
