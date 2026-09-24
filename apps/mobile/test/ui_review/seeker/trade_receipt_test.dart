import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/ui_review/review_first_play.dart';
import 'package:trimmy/ui_review/review_spotlight.dart';
import 'package:trimmy/ui_review/review_trade_ticket.dart';

void main() {
  testWidgets('guide keeps moving in both directions until removed', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ReviewGuideCue(text: 'Choose a company')),
      ),
    );
    double y() => tester
        .widget<Transform>(
          find.descendant(
            of: find.byType(ReviewGuideCue),
            matching: find.byType(Transform),
          ),
        )
        .transform
        .storage[13];
    await tester.pump(const Duration(milliseconds: 425));
    final forward = y();
    await tester.pump(const Duration(milliseconds: 425));
    final peak = y();
    await tester.pump(const Duration(milliseconds: 425));
    expect(peak, greaterThan(forward));
    expect(y(), lessThan(peak));
    await tester.pump(const Duration(milliseconds: 425));
    expect(y(), closeTo(0, .01));
    await tester.pump(const Duration(milliseconds: 425));
    expect(y(), greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion keeps the guide still', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const Scaffold(body: ReviewGuideCue(text: 'Choose a company')),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'confirmed position and reward share one receipt without extra labels',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: ReviewFirstDayResultPage(
            position: ReviewPracticePosition.example,
            onContinue: () {},
          ),
        ),
      );
      expect(find.byType(ReviewTradeTicket), findsOneWidget);
      expect(find.text('Your first position.'), findsOneWidget);
      expect(find.text('Day 1 complete'), findsOneWidget);
      expect(find.text('+20 Trims'), findsOneWidget);
      expect(find.text('Practice complete'), findsNothing);
      expect(find.text('Sample prices. Practice money only.'), findsNothing);
      expect(find.text('Go to my desk'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
