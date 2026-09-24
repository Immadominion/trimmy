import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/app/launch_moments.dart';
import 'package:trimmy/product/career/career.dart';
import 'package:trimmy/product/design/product_theme.dart';

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  final scrollable = find.byType(Scrollable).first;
  for (var attempt = 0; attempt < 20; attempt++) {
    if (finder.hitTestable().evaluate().isNotEmpty) return;
    await tester.drag(scrollable, const Offset(0, -220));
    await tester.pump();
  }
  expect(finder.hitTestable(), findsOneWidget);
}

void main() {
  final data = FirstPositionMomentData(
    symbol: 'AAPLx',
    quantity: '1.25',
    confirmedAt: DateTime.utc(2026, 9, 20, 14, 7),
  );
  final promotion = CareerPromotionReceipt(
    mutationId: '33333333-3333-4333-8333-333333333333',
    fromRank: CareerRank.rookie,
    toRank: CareerRank.analyst,
    careerRevision: 7,
    trimsAwarded: 100,
    promotedAt: DateTime.utc(2026, 9, 20, 12),
  );

  testWidgets(
    'first position uses confirmed facts and awards no trade points',
    (tester) async {
      var collected = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: productTheme(),
          home: FirstPositionMoment(data: data, onCollect: () => collected++),
        ),
      );

      expect(find.text('Your first position.'), findsOneWidget);
      expect(find.text('You’ve placed your first order!'), findsOneWidget);
      expect(find.text('AAPLx'), findsWidgets);
      expect(find.text('1.25'), findsOneWidget);
      expect(find.text('14:07 UTC'), findsOneWidget);
      expect(find.textContaining('Trims'), findsNothing);
      final collect = find.byKey(const ValueKey('first-position-collect'));
      await _reveal(tester, collect);
      await tester.tap(find.text('Continue').hitTestable());
      await tester.pump();
      expect(collected, 1);
    },
  );

  testWidgets('Day 1 is a separate full-screen moment', (tester) async {
    var continued = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: DayOneMoment(onContinue: () => continued++),
      ),
    );

    expect(find.text('Day 1, done.'), findsOneWidget);
    expect(find.text('See you on the floor tomorrow.'), findsOneWidget);
    final button = find.byKey(const ValueKey('day-one-continue'));
    await _reveal(tester, button);
    await tester.tap(find.text('Continue').hitTestable());
    await tester.pump();
    expect(continued, 1);
  });

  testWidgets('launch moments remain reachable on a small large-text phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: FirstPositionMoment(data: data, onCollect: () {}),
      ),
    );
    final collect = find.byKey(const ValueKey('first-position-collect'));
    await _reveal(tester, collect);

    expect(tester.takeException(), isNull);
    expect(collect, findsOneWidget);
  });

  testWidgets('promotion moment uses the confirmed receipt', (tester) async {
    var continued = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: PromotionMoment(
          receipt: promotion,
          onContinue: () => continued++,
        ),
      ),
    );

    expect(find.text('You’re an Analyst!'), findsOneWidget);
    expect(find.text('Rookie'), findsOneWidget);
    expect(find.text('Analyst'), findsOneWidget);
    expect(find.text('100 Trims'), findsOneWidget);
    final button = find.byKey(const ValueKey('promotion-continue'));
    await _reveal(tester, button);
    await tester.tap(button.hitTestable());
    expect(continued, 1);
  });

  testWidgets('promotion remains reachable on a small large-text phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: PromotionMoment(receipt: promotion, onContinue: () {}),
      ),
    );
    final button = find.byKey(const ValueKey('promotion-continue'));
    await _reveal(tester, button);

    expect(button.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
