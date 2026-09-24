import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/market/market.dart';

import 'market_test_support.dart';

void main() {
  Widget app(Widget home, {double textScale = 1}) => MaterialApp(
    theme: ThemeData(useMaterial3: true, fontFamily: 'Manrope'),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: home,
  );

  PaperOrderFlow flow(FakePaperOrderRepository repository) => PaperOrderFlow(
    company: testCompany(),
    side: PaperOrderSide.buy,
    repository: repository,
    clientOrderId: () => 'client-order-1',
    reasonMutationId: () => testReasonMutationId,
    availablePaper: '10000',
    availableShares: '0',
  );

  testWidgets(
    'cash and shares stay connected and Max sells the exact position',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakePaperOrderRepository();
      await tester.pumpWidget(
        app(
          PaperOrderFlow(
            company: testCompany(),
            side: PaperOrderSide.sell,
            repository: repository,
            clientOrderId: () => 'sale-1',
            availablePaper: '9950',
            availableShares: '0.132042',
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('paper-unit-paper')));
      await tester.tap(find.byKey(const ValueKey('paper-key-1')));
      await tester.tap(find.byKey(const ValueKey('paper-key-0')));
      await tester.pump();
      expect(find.text('≈ 0.043212 shares'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('paper-preset-Max')));
      await tester.tap(find.byKey(const ValueKey('paper-order-review-button')));
      await tester.pumpAndSettle();
      expect(repository.intents.single.quantityUnit, PaperQuantityUnit.shares);
      expect(repository.intents.single.quantity, '0.132042');
    },
  );

  testWidgets(
    'notices expire, can close, and do not clear the entered amount',
    (tester) async {
      final repository = FakePaperOrderRepository()
        ..onQuote = (_) async => throw const PaperOrderException(
          PaperOrderFailure.insufficientPaper,
        );
      await tester.pumpWidget(app(flow(repository)));
      await tester.tap(find.byKey(const ValueKey('paper-preset-500')));
      await tester.tap(find.byKey(const ValueKey('paper-order-review-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('paper-order-message')), findsOneWidget);
      await tester.pump(const Duration(seconds: 7));
      expect(find.byKey(const ValueKey('paper-order-message')), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('order-amount-value')))
            .data,
        '500',
      );
      await tester.tap(find.byKey(const ValueKey('paper-order-review-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Dismiss message'));
      await tester.pump();
      expect(find.byKey(const ValueKey('paper-order-message')), findsNothing);
    },
  );

  testWidgets('never shows review or report before repository confirmation', (
    tester,
  ) async {
    final quote = Completer<PaperOrderQuote>();
    final submit = Completer<PaperOrderReceipt>();
    final repository = FakePaperOrderRepository();
    repository.onQuote = (intent) => quote.future;
    repository.onSubmit = (_) => submit.future;
    await tester.pumpWidget(app(flow(repository)));

    await tester.tap(find.byKey(const ValueKey('paper-preset-500')));
    await tester.tap(find.byKey(const ValueKey('paper-order-review-button')));
    await tester.pump();
    expect(find.byKey(const ValueKey('paper-order-review')), findsNothing);
    expect(find.byKey(const ValueKey('paper-order-report')), findsNothing);

    quote.complete(
      PaperOrderQuote(
        quoteId: 'quote-1',
        intent: repository.intents.single,
        unitPricePaper: '231.42',
        estimatedShares: '2.1605',
        feePaper: '0',
        totalPaper: '500',
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 2)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('paper-order-review')), findsOneWidget);
    expect(find.text('Review your buy'), findsOneWidget);
    expect(
      find.text(
        'This is a paper trade at the latest provider price. No money moves.',
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('paper-order-confirm-button')));
    await tester.pump();
    expect(find.byKey(const ValueKey('paper-order-report')), findsNothing);

    submit.complete(testReceipt());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('paper-order-report')), findsOneWidget);
    expect(find.text('AAPL is on your desk.'), findsOneWidget);
    expect(repository.submissions.single.clientOrderId, 'client-order-1');
  });

  testWidgets('failed submit stays out of done state and explains it', (
    tester,
  ) async {
    final repository = FakePaperOrderRepository()
      ..onSubmit = (_) async =>
          throw const PaperOrderException(PaperOrderFailure.insufficientPaper);
    await tester.pumpWidget(app(flow(repository)));
    await tester.tap(find.byKey(const ValueKey('paper-preset-500')));
    await tester.tap(find.byKey(const ValueKey('paper-order-review-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('paper-order-confirm-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('paper-order-report')), findsNothing);
    expect(find.textContaining('not enough paper'), findsOneWidget);
  });

  testWidgets('an ambiguous submit retry reuses the quote idempotency key', (
    tester,
  ) async {
    var attempts = 0;
    var idCalls = 0;
    final repository = FakePaperOrderRepository()
      ..onSubmit = (submission) async {
        attempts++;
        if (attempts == 1) {
          throw const PaperOrderException(PaperOrderFailure.timeout);
        }
        return testReceipt();
      };
    await tester.pumpWidget(
      app(
        PaperOrderFlow(
          company: testCompany(),
          side: PaperOrderSide.buy,
          repository: repository,
          clientOrderId: () => 'client-order-${++idCalls}',
          availablePaper: '10000',
          availableShares: '0',
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('paper-preset-500')));
    await tester.tap(find.byKey(const ValueKey('paper-order-review-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('paper-order-confirm-button')));
    await tester.pumpAndSettle();
    expect(find.text('That took too long. Try again.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('paper-order-confirm-button')));
    await tester.pumpAndSettle();

    expect(repository.submissions, hasLength(2));
    expect(repository.submissions.map((item) => item.clientOrderId).toSet(), {
      'client-order-1',
    });
    expect(idCalls, 1);
    expect(find.byKey(const ValueKey('paper-order-report')), findsOneWidget);
  });

  testWidgets('order flow survives 320px width and 200% text', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakePaperOrderRepository();
    await tester.pumpWidget(app(flow(repository), textScale: 2));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('paper-order-review-button')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('paper-key-backspace')), findsOneWidget);
  });

  testWidgets('review and report survive 320px width and 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakePaperOrderRepository();
    await tester.pumpWidget(app(flow(repository), textScale: 2));
    await tester.tap(find.byKey(const ValueKey('paper-preset-500')));
    await tester.tap(find.byKey(const ValueKey('paper-order-review-button')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('paper-order-confirm-button')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final report = find.byType(ListView).first;
    for (var index = 0; index < 3; index++) {
      await tester.drag(report, const Offset(0, -400));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('reason is not treated as saved until repository returns', (
    tester,
  ) async {
    final saving = Completer<PaperReasonReceipt>();
    final repository = FakePaperOrderRepository()
      ..onSaveReason = (_) => saving.future;
    await tester.pumpWidget(app(flow(repository)));
    await tester.tap(find.byKey(const ValueKey('paper-preset-500')));
    await tester.tap(find.byKey(const ValueKey('paper-order-review-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('paper-order-confirm-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('paper-order-reason')),
      'I expect steady demand.',
    );
    await tester.tap(find.byKey(const ValueKey('paper-order-save-reason')));
    await tester.pump();
    expect(find.byKey(const ValueKey('paper-order-report')), findsOneWidget);
    expect(repository.reasons.single.note, 'I expect steady demand.');
    saving.complete(testReasonReceipt(repository.reasons.single));
    await tester.pumpAndSettle();
    expect(find.text('+10 Trims'), findsOneWidget);
    expect(find.text('“I expect steady demand.”'), findsOneWidget);
  });

  testWidgets(
    'failed reason save keeps the trade confirmed and retries one mutation',
    (tester) async {
      var attempts = 0;
      var mutationCalls = 0;
      final repository = FakePaperOrderRepository()
        ..onSaveReason = (reason) async {
          attempts++;
          if (attempts == 1) {
            throw const CareerException(CareerFailure.timeout);
          }
          return testReasonReceipt(reason);
        };
      await tester.pumpWidget(
        app(
          PaperOrderFlow(
            company: testCompany(),
            side: PaperOrderSide.buy,
            repository: repository,
            clientOrderId: () => 'client-order-1',
            reasonMutationId: () {
              mutationCalls++;
              return testReasonMutationId;
            },
            availablePaper: '10000',
            availableShares: '0',
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('paper-preset-500')));
      await tester.tap(find.byKey(const ValueKey('paper-order-review-button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('paper-order-confirm-button')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('paper-order-reason')),
        'I expect steady demand.',
      );
      await tester.tap(find.byKey(const ValueKey('paper-order-save-reason')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('paper-order-report')), findsOneWidget);
      expect(find.text('AAPL is on your desk.'), findsOneWidget);
      expect(
        find.text(
          'Trade confirmed. Saving the reason took too long. Try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry reason'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('paper-order-save-reason')));
      await tester.pumpAndSettle();

      expect(repository.reasons, hasLength(2));
      expect(repository.reasons.map((reason) => reason.mutationId).toSet(), {
        testReasonMutationId,
      });
      expect(repository.reasons.map((reason) => reason.note).toSet(), {
        'I expect steady demand.',
      });
      expect(mutationCalls, 1);
      expect(find.text('+10 Trims'), findsOneWidget);
    },
  );

  testWidgets(
    'saved reason shows the note without inventing Trims at the daily cap',
    (tester) async {
      final repository = FakePaperOrderRepository()
        ..onSaveReason = (reason) async =>
            testReasonReceipt(reason, trimsAwarded: 0);
      await tester.pumpWidget(app(flow(repository)));
      await tester.tap(find.byKey(const ValueKey('paper-preset-500')));
      await tester.tap(find.byKey(const ValueKey('paper-order-review-button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('paper-order-confirm-button')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('paper-order-reason')),
        'The valuation leaves room for growth.',
      );
      await tester.tap(find.byKey(const ValueKey('paper-order-save-reason')));
      await tester.pumpAndSettle();

      expect(find.text('Reason saved'), findsOneWidget);
      expect(
        find.text('“The valuation leaves room for growth.”'),
        findsOneWidget,
      );
      expect(find.textContaining('+10'), findsNothing);
    },
  );

  testWidgets('rejects a reason receipt for another stock version', (
    tester,
  ) async {
    var callbackCalls = 0;
    final repository = FakePaperOrderRepository()
      ..onSaveReason = (reason) async => CareerTradeReasonReceipt(
        orderId: reason.orderId,
        assetId: 'apple',
        variantMint: '7XSvf7L8hJhzgUKQBx7bdvzPfbFnQnPdP3zVLjUd9P5Q',
        note: reason.note,
        trimsAwarded: 10,
        dailyAwardNumber: 1,
        savedAt: DateTime.utc(2026, 9, 20, 12, 31),
      );
    await tester.pumpWidget(
      app(
        PaperOrderFlow(
          company: testCompany(),
          side: PaperOrderSide.buy,
          repository: repository,
          clientOrderId: () => 'client-order-1',
          reasonMutationId: () => testReasonMutationId,
          availablePaper: '10000',
          availableShares: '0',
          onReasonSaved: (_) => callbackCalls++,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('paper-preset-500')));
    await tester.tap(find.byKey(const ValueKey('paper-order-review-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('paper-order-confirm-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('paper-order-reason')),
      'I expect steady demand.',
    );
    await tester.tap(find.byKey(const ValueKey('paper-order-save-reason')));
    await tester.pumpAndSettle();

    expect(find.text('+10 Trims'), findsNothing);
    expect(
      find.text('Trade confirmed. Your reason was not saved. Try again.'),
      findsOneWidget,
    );
    expect(callbackCalls, 0);
  });

  testWidgets('a confirmed sell never offers the written buy reason', (
    tester,
  ) async {
    final repository = FakePaperOrderRepository()
      ..onSubmit = (_) async => PaperOrderReceipt(
        orderId: testOrderId,
        accountRevision: 1,
        assetId: 'apple',
        variantMint: testMint,
        symbol: 'AAPLx',
        side: PaperOrderSide.sell,
        filledShares: '1',
        filledPaper: '231.42',
        cashAfterPaper: '10231.42',
        positionShares: '1.1605',
        positionCostBasisPaper: '268.58',
        positionValuePaper: '268.58',
        trimsEarned: 0,
        confirmedAt: DateTime.utc(2026, 9, 20, 12, 31),
      );
    await tester.pumpWidget(
      app(
        PaperOrderFlow(
          company: testCompany(),
          side: PaperOrderSide.sell,
          repository: repository,
          clientOrderId: () => 'client-order-1',
          reasonMutationId: () => testReasonMutationId,
          availablePaper: '10000',
          availableShares: '2.1605',
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('paper-preset-50%')));
    await tester.tap(find.byKey(const ValueKey('paper-order-review-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('paper-order-confirm-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('paper-order-report')), findsOneWidget);
    expect(find.byKey(const ValueKey('paper-order-reason')), findsNothing);
    expect(find.byKey(const ValueKey('paper-order-done')), findsOneWidget);
    expect(repository.reasons, isEmpty);
  });

  testWidgets('confirmed buy is honest when reason capture is unavailable', (
    tester,
  ) async {
    final repository = FakePaperOrderRepository();
    await tester.pumpWidget(
      app(
        PaperOrderFlow(
          company: testCompany(),
          side: PaperOrderSide.buy,
          repository: repository,
          clientOrderId: () => 'client-order-1',
          availablePaper: '10000',
          availableShares: '0',
          reasonCaptureAvailable: false,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('paper-preset-500')));
    await tester.tap(find.byKey(const ValueKey('paper-order-review-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('paper-order-confirm-button')));
    await tester.pumpAndSettle();

    final copy = find.text(
      'Your trade is confirmed. Saving a reason is unavailable right now.',
    );
    await tester.scrollUntilVisible(copy, 250);
    expect(copy, findsOneWidget);
    expect(find.textContaining('Career system'), findsNothing);
  });

  testWidgets('refuses a quote for a different intent', (tester) async {
    final repository = FakePaperOrderRepository()
      ..onQuote = (_) async {
        final other = PaperOrderIntent(
          assetId: 'nvidia',
          variantMint: testMint,
          side: PaperOrderSide.buy,
          quantityUnit: PaperQuantityUnit.paper,
          quantity: '500',
        );
        return PaperOrderQuote(
          quoteId: 'quote-wrong',
          intent: other,
          unitPricePaper: '231.42',
          estimatedShares: '2.1605',
          feePaper: '0',
          totalPaper: '500',
          expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 2)),
        );
      };
    await tester.pumpWidget(app(flow(repository)));
    await tester.tap(find.byKey(const ValueKey('paper-preset-500')));
    await tester.tap(find.byKey(const ValueKey('paper-order-review-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('paper-order-review')), findsNothing);
    expect(find.text('The order was not accepted.'), findsOneWidget);
  });

  testWidgets('confirmed receipt survives a throwing host callback', (
    tester,
  ) async {
    final repository = FakePaperOrderRepository();
    await tester.pumpWidget(
      app(
        PaperOrderFlow(
          company: testCompany(),
          side: PaperOrderSide.buy,
          repository: repository,
          clientOrderId: () => 'client-order-1',
          availablePaper: '10000',
          availableShares: '0',
          onConfirmed: (_) => throw StateError('host refresh failed'),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('paper-preset-500')));
    await tester.tap(find.byKey(const ValueKey('paper-order-review-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('paper-order-confirm-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('paper-order-report')), findsOneWidget);
    expect(find.text('AAPL is on your desk.'), findsOneWidget);
    expect(find.text('The order did not go through. Try again.'), findsNothing);
  });

  test('reason is one line and rejects control characters', () {
    expect(
      () => PaperOrderReason(
        mutationId: testReasonMutationId,
        orderId: testOrderId,
        note: 'First line\nSecond',
      ),
      throwsA(
        isA<CareerException>().having(
          (error) => error.failure,
          'failure',
          CareerFailure.invalidInput,
        ),
      ),
    );
  });
}
