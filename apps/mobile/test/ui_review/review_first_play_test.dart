import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/ui_review/review_feedback.dart';
import 'package:trimmy/ui_review/review_first_play.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ReviewFeedback.shared.sound = false;
    ReviewFeedback.shared.haptics = false;
  });

  testWidgets('practice buy uses the selection and requires confirmation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ReviewPracticePosition? completed;
    var confirmations = 0;
    await tester.pumpWidget(
      _host(
        ReviewFirstPlayPage(
          onExit: () {},
          onComplete: (position) {
            completed = position;
            confirmations++;
          },
        ),
      ),
    );

    expect(find.textContaining('A share is a small piece'), findsOneWidget);
    await tester.tap(find.text('Hint'));
    await tester.pump();
    expect(find.textContaining('A share is a small piece'), findsNothing);
    await tester.tap(find.text('Hint'));
    await tester.pump();
    expect(find.textContaining('A share is a small piece'), findsOneWidget);

    await tester.tap(find.text('Nvidia'));
    await tester.pump();
    await tester.ensureVisible(find.text('\$50'));
    await tester.tap(find.text('\$50'));
    await tester.pump();
    expect(
      find.textContaining('0.4 NVDA shares', findRichText: true),
      findsNothing,
    );

    await tester.tap(find.text('Review buy'));
    await tester.pumpAndSettle();
    expect(completed, isNull);
    expect(find.text('\$125.00'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(completed, isNull);

    await tester.tap(find.text('Review buy'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Confirm buy'));
    await tester.tap(find.text('Confirm buy'));
    await tester.pumpAndSettle();
    expect(confirmations, 1);
    expect(completed?.company, 'Nvidia');
    expect(completed?.symbol, 'NVDA');
    expect(completed?.amount, 50);
    expect(completed?.price, 125);
    expect(completed?.shares, .4);
    expect(tester.takeException(), isNull);
  });

  testWidgets('practice and result stay usable at 200 percent text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ReviewPracticePosition? completed;
    await tester.pumpWidget(
      _host(
        ReviewFirstPlayPage(
          onExit: () {},
          onComplete: (position) => completed = position,
          initialPosition: const ReviewPracticePosition(
            company: 'Microsoft',
            symbol: 'MSFT',
            price: 400,
            amount: 25,
          ),
        ),
        textScale: 2,
      ),
    );
    await tester.tap(find.text('Review buy'));
    await tester.pumpAndSettle();
    expect(find.text('Microsoft'), findsWidgets);
    await tester.ensureVisible(find.text('Confirm buy'));
    await tester.tap(find.text('Confirm buy'));
    await tester.pumpAndSettle();
    expect(completed?.amount, 25);
    expect(completed?.shares, .0625);
    expect(tester.takeException(), isNull);

    var continues = 0;
    await tester.pumpWidget(
      _host(
        ReviewFirstDayResultPage(
          position: completed!,
          onContinue: () => continues++,
        ),
        textScale: 2,
      ),
    );
    expect(find.text('Day 1 complete'), findsOneWidget);
    expect(find.text('+20 Trims'), findsOneWidget);
    expect(find.text('0.0625'), findsOneWidget);
    await tester.tap(find.text('Go to my desk'));
    expect(continues, 1);
    expect(tester.takeException(), isNull);
  });
}

Widget _host(Widget child, {double textScale = 1}) => MaterialApp(
  theme: ThemeData(useMaterial3: true, fontFamily: 'Dejanire Sans'),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(textScale),
      disableAnimations: true,
      padding: const EdgeInsets.only(top: 24, bottom: 24),
    ),
    child: child!,
  ),
  home: child,
);
