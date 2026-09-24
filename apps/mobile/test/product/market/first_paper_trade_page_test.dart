import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/market/market.dart';
import 'package:trimmy/ui_review/review_feedback.dart';

import 'market_test_support.dart';

void main() {
  setUp(() async {
    await ReviewFeedback.shared.load();
    ReviewFeedback.shared.sound = false;
    ReviewFeedback.shared.haptics = false;
  });

  Widget app({
    required PaperOrderRepository? repository,
    String? availablePaper = '10000',
    ValueChanged<PaperOrderReceipt>? onConfirmed,
    Future<void> Function()? onFinished,
    Future<void> Function()? onExit,
    double scale = 1,
  }) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: true, textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: FirstPaperTradePage(
      companies: [testCompany()],
      repository: repository,
      availablePaper: availablePaper,
      clientOrderId: () => 'first-client-order',
      onConfirmed: onConfirmed ?? (_) {},
      onFinished: onFinished ?? () async {},
      onExit: onExit ?? () async {},
    ),
  );

  Future<void> chooseAndReview(WidgetTester tester) async {
    await tester.tap(find.text('Apple'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review buy'));
    await tester.pumpAndSettle();
  }

  testWidgets('skip leaves an empty flow without issuing an order', (
    tester,
  ) async {
    final repository = FakePaperOrderRepository();
    var exits = 0;
    await tester.pumpWidget(
      app(
        repository: repository,
        onExit: () async {
          exits++;
        },
      ),
    );
    await tester.tap(find.byTooltip('Skip first trade'));
    await tester.pumpAndSettle();
    expect(exits, 1);
    expect(repository.intents, isEmpty);
    expect(repository.submissions, isEmpty);
    expect(find.text('You’ve placed your first order!'), findsNothing);
    expect(find.text('+20 Trims'), findsNothing);
  });

  testWidgets('unready paper balance cannot request a quote', (tester) async {
    final repository = FakePaperOrderRepository();
    await tester.pumpWidget(app(repository: repository, availablePaper: null));
    await tester.tap(find.text('Apple'));
    await tester.pumpAndSettle();
    expect(find.textContaining('paper desk is unavailable'), findsOneWidget);
    expect(repository.intents, isEmpty);
    expect(repository.submissions, isEmpty);
  });

  testWidgets(
    'real quote and receipt own confirmation and finishing is explicit',
    (tester) async {
      final quote = Completer<PaperOrderQuote>();
      final submit = Completer<PaperOrderReceipt>();
      final repository = FakePaperOrderRepository()
        ..onQuote = ((_) => quote.future)
        ..onSubmit = ((_) => submit.future);
      PaperOrderReceipt? confirmed;
      var finished = 0;
      await tester.pumpWidget(
        app(
          repository: repository,
          onConfirmed: (receipt) => confirmed = receipt,
          onFinished: () async {
            finished++;
          },
        ),
      );
      await chooseAndReview(tester);
      expect(repository.intents.single.quantity, '100');
      expect(find.text('Checking price…'), findsOneWidget);
      expect(find.text('Confirm buy'), findsNothing);
      expect(find.text('You’ve placed your first order!'), findsNothing);

      quote.complete(
        PaperOrderQuote(
          quoteId: 'server-quote',
          intent: repository.intents.single,
          unitPricePaper: '231.42',
          estimatedShares: '0.4321',
          feePaper: '0',
          totalPaper: '100',
          expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 2)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sample price'), findsNothing);
      final confirm = find.byKey(const ValueKey('paper-order-confirm-button'));
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pump();
      expect(confirmed, isNull);
      expect(find.text('You’ve placed your first order!'), findsNothing);

      submit.complete(testReceipt());
      await tester.pumpAndSettle();
      expect(confirmed?.filledShares, '2.1605');
      expect(find.text('You’ve placed your first order!'), findsOneWidget);
      expect(
        find.text('Now let’s create your trader profile.'),
        findsOneWidget,
      );
      expect(find.text('Shares  2.1605'), findsOneWidget);
      expect(find.text('Day 1 complete'), findsNothing);
      expect(find.text('+20 Trims'), findsNothing);
      expect(finished, 0);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(finished, 1);
    },
  );

  testWidgets('sheet Back edits the retained choice and X skips the task', (
    tester,
  ) async {
    final repository = FakePaperOrderRepository();
    var exits = 0;
    await tester.pumpWidget(
      app(
        repository: repository,
        onExit: () async {
          exits++;
        },
      ),
    );
    await chooseAndReview(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Review your buy.'), findsNothing);
    expect(find.text('Review buy'), findsOneWidget);
    expect(exits, 0);
    await tester.tap(find.text('Review buy'));
    await tester.pumpAndSettle();
    expect(repository.intents.length, 2);
    expect(repository.intents.first, repository.intents.last);
    await tester.tap(find.byTooltip('Skip first trade').last);
    await tester.pumpAndSettle();
    expect(exits, 1);
    expect(repository.submissions, isEmpty);
  });
  testWidgets('an open quote survives host readiness changes', (tester) async {
    final repository = FakePaperOrderRepository();
    var ready = true;
    late StateSetter updateHost;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          updateHost = setState;
          return app(
            repository: ready ? repository : null,
            availablePaper: ready ? '10000' : null,
            scale: ready ? 1 : 1.1,
          );
        },
      ),
    );
    await chooseAndReview(tester);
    expect(find.text('Review your buy.'), findsOneWidget);
    updateHost(() => ready = false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Review your buy.'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(repository.submissions, isEmpty);
  });
}
