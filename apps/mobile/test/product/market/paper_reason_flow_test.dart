import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/career/career_repository.dart';
import 'package:trimmy/product/market/paper_order_repository.dart';
import 'package:trimmy/product/market/paper_portfolio.dart';
import 'package:trimmy/product/market/paper_reason_flow.dart';

import 'market_test_support.dart';

const _secondOrderId = '77777777-7777-4777-8777-777777777777';
const _thirdOrderId = '88888888-8888-4888-8888-888888888888';
const _secondMint = 'So11111111111111111111111111111111111111112';

void main() {
  group('held paper reason target', () {
    test(
      'uses the immutable first buy only while its exact version is held',
      () {
        final target = selectPaperReasonTarget(
          portfolio: _portfolio(
            positions: [_position(assetId: 'apple', mint: testMint)],
            orders: [
              _order(
                orderId: testOrderId,
                assetId: 'apple',
                mint: testMint,
                symbol: 'AAPLx',
                committedAt: _confirmedAt,
              ),
              _order(
                orderId: _secondOrderId,
                assetId: 'tesla',
                mint: _secondMint,
                symbol: 'TSLAx',
                committedAt: DateTime.utc(2026, 9, 20, 13),
              ),
            ],
          ),
          firstConfirmedBuy: _firstBuy,
        );

        expect(target?.orderId, testOrderId);
        expect(target?.variantMint, testMint);
        expect(target?.heldShares, '2.1605');
      },
    );

    test('reset then rebuy selects the new current-cycle order', () {
      final rebuyAt = DateTime.utc(2026, 9, 20, 15);
      final target = selectPaperReasonTarget(
        portfolio: _portfolio(
          positions: [_position(assetId: 'apple', mint: testMint)],
          orders: [
            _order(
              orderId: _secondOrderId,
              assetId: 'apple',
              mint: testMint,
              symbol: 'AAPLx',
              committedAt: rebuyAt,
            ),
          ],
        ),
        firstConfirmedBuy: _firstBuy,
      );

      expect(target?.orderId, _secondOrderId);
      expect(target?.variantMint, testMint);
      expect(target?.confirmedAt, rebuyAt);
    });

    test('falls back to the newest confirmed buy that is still held', () {
      final target = selectPaperReasonTarget(
        portfolio: _portfolio(
          positions: [
            _position(assetId: 'tesla', mint: _secondMint, symbol: 'TSLAx'),
          ],
          orders: [
            _order(
              orderId: _secondOrderId,
              assetId: 'tesla',
              mint: _secondMint,
              symbol: 'TSLAx',
              committedAt: DateTime.utc(2026, 9, 20, 13),
            ),
            _order(
              orderId: _thirdOrderId,
              assetId: 'tesla',
              mint: _secondMint,
              symbol: 'TSLAx',
              committedAt: DateTime.utc(2026, 9, 20, 14),
            ),
          ],
        ),
        firstConfirmedBuy: _firstBuy,
      );

      expect(target?.orderId, _thirdOrderId);
      expect(target?.assetId, 'tesla');
    });

    test('does not return a sold, mismatched, or locally reasoned buy', () {
      final portfolio = _portfolio(
        positions: [
          _position(assetId: 'apple', mint: _secondMint),
          _position(assetId: 'tesla', mint: _secondMint, quantity: '0'),
        ],
        orders: [
          _order(
            orderId: _secondOrderId,
            assetId: 'apple',
            mint: _secondMint,
            symbol: 'AAPLx',
            committedAt: DateTime.utc(2026, 9, 20, 13),
          ),
        ],
      );

      expect(
        selectPaperReasonTarget(
          portfolio: portfolio,
          firstConfirmedBuy: _firstBuy,
          excludedOrderIds: const {_secondOrderId},
        ),
        isNull,
      );
    });
  });

  testWidgets(
    'saves against the existing buy without quoting or placing an order',
    (tester) async {
      final repository = FakePaperOrderRepository();
      PaperReasonReceipt? callbackReceipt;
      var mutationCalls = 0;
      await _pumpFlow(
        tester,
        repository: repository,
        mutationId: () {
          mutationCalls++;
          return testReasonMutationId;
        },
        onSaved: (receipt) => callbackReceipt = receipt,
      );

      await tester.enterText(
        find.byKey(const ValueKey('paper-reason-note')),
        '  Demand looks durable.  ',
      );
      await tester.tap(find.byKey(const ValueKey('paper-reason-save')));
      await tester.pumpAndSettle();

      expect(repository.intents, isEmpty);
      expect(repository.submissions, isEmpty);
      expect(repository.reasons, hasLength(1));
      expect(repository.reasons.single.orderId, testOrderId);
      expect(repository.reasons.single.note, 'Demand looks durable.');
      expect(repository.reasons.single.mutationId, testReasonMutationId);
      expect(mutationCalls, 1);
      expect(callbackReceipt?.orderId, testOrderId);
      expect(find.byKey(const ValueKey('paper-reason-reward')), findsOneWidget);
      expect(find.text('+10 Trims'), findsOneWidget);
    },
  );

  testWidgets('a retry reuses the same mutation and normalized reason', (
    tester,
  ) async {
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
    await _pumpFlow(
      tester,
      repository: repository,
      mutationId: () {
        mutationCalls++;
        return testReasonMutationId;
      },
    );

    await tester.enterText(
      find.byKey(const ValueKey('paper-reason-note')),
      'Long-term demand',
    );
    await tester.tap(find.byKey(const ValueKey('paper-reason-save')));
    await tester.pumpAndSettle();

    expect(find.text('Saving took too long. Try again.'), findsOneWidget);
    expect(find.text('Retry reason'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('paper-reason-note')))
          .readOnly,
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('paper-reason-save')));
    await tester.pumpAndSettle();

    expect(repository.reasons, hasLength(2));
    expect(repository.reasons.map((reason) => reason.mutationId).toSet(), {
      testReasonMutationId,
    });
    expect(repository.reasons.map((reason) => reason.note).toSet(), {
      'Long-term demand',
    });
    expect(mutationCalls, 1);
    expect(find.byKey(const ValueKey('paper-reason-reward')), findsOneWidget);
  });

  testWidgets('rejects a receipt for another stock version', (tester) async {
    var callbackCalls = 0;
    final repository = FakePaperOrderRepository()
      ..onSaveReason = (reason) async => PaperReasonReceipt(
        orderId: reason.orderId,
        assetId: 'apple',
        variantMint: _secondMint,
        note: reason.note,
        trimsAwarded: 20,
        dailyAwardNumber: 1,
        savedAt: DateTime.utc(2026, 9, 20, 15),
      );
    await _pumpFlow(
      tester,
      repository: repository,
      onSaved: (_) => callbackCalls++,
    );

    await tester.enterText(
      find.byKey(const ValueKey('paper-reason-note')),
      'The valuation is reasonable.',
    );
    await tester.tap(find.byKey(const ValueKey('paper-reason-save')));
    await tester.pumpAndSettle();

    expect(callbackCalls, 0);
    expect(find.text('Your reason was not saved. Try again.'), findsOneWidget);
    expect(find.byKey(const ValueKey('paper-reason-reward')), findsNothing);
  });

  testWidgets('an existing server reason cannot be submitted again', (
    tester,
  ) async {
    final repository = FakePaperOrderRepository()
      ..onSaveReason = (_) async {
        throw const CareerException(CareerFailure.reasonExists);
      };
    await _pumpFlow(tester, repository: repository);

    await tester.enterText(
      find.byKey(const ValueKey('paper-reason-note')),
      'A reason already saved elsewhere.',
    );
    await tester.tap(find.byKey(const ValueKey('paper-reason-save')));
    await tester.pumpAndSettle();

    expect(repository.reasons, hasLength(1));
    expect(
      find.text('This paper buy already has a reason. Refresh your Career.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('paper-reason-save')), findsNothing);
    expect(
      find.byKey(const ValueKey('paper-reason-close-existing')),
      findsOneWidget,
    );
  });

  testWidgets('reason entry remains usable at 320px and 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: PaperReasonFlow(
            target: _target,
            repository: FakePaperOrderRepository(),
            mutationId: () => testReasonMutationId,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Write your reason'), findsOneWidget);
    final action = find.byKey(const ValueKey('paper-reason-save'));
    for (var attempt = 0; attempt < 8; attempt++) {
      if (action.hitTestable().evaluate().isNotEmpty) break;
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -160));
      await tester.pumpAndSettle();
    }
    expect(action.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late save cannot update a disposed identity-bound route', (
    tester,
  ) async {
    final pending = Completer<PaperReasonReceipt>();
    var callbackCalls = 0;
    final repository = FakePaperOrderRepository()
      ..onSaveReason = (_) => pending.future;
    await _pumpFlow(
      tester,
      repository: repository,
      onSaved: (_) => callbackCalls++,
    );

    await tester.enterText(
      find.byKey(const ValueKey('paper-reason-note')),
      'I can explain the risk.',
    );
    await tester.tap(find.byKey(const ValueKey('paper-reason-save')));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: Text('New identity')));
    pending.complete(testReasonReceipt(repository.reasons.single));
    await tester.pumpAndSettle();

    expect(callbackCalls, 0);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpFlow(
  WidgetTester tester, {
  required FakePaperOrderRepository repository,
  String Function()? mutationId,
  ValueChanged<PaperReasonReceipt>? onSaved,
}) async {
  tester.view.physicalSize = const Size(430, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: PaperReasonFlow(
        target: _target,
        repository: repository,
        mutationId: mutationId ?? () => testReasonMutationId,
        onSaved: onSaved,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _target = PaperReasonTarget(
  orderId: testOrderId,
  assetId: 'apple',
  variantMint: testMint,
  symbol: 'AAPLx',
  heldShares: '2.1605',
  confirmedAt: _confirmedAt,
);

final _confirmedAt = DateTime.utc(2026, 9, 20, 12, 31);

final _firstBuy = CareerFirstConfirmedBuy(
  orderId: testOrderId,
  assetId: 'apple',
  variantMint: testMint,
  symbol: 'AAPLx',
  quantityMicros: '2160500',
  confirmedAt: _confirmedAt,
);

PaperPortfolioSnapshot _portfolio({
  required List<PaperPortfolioPosition> positions,
  required List<PaperPortfolioOrder> orders,
}) {
  const revision = 3;
  const cash = '9000';
  return PaperPortfolioSnapshot(
    revision: revision,
    startingCashPaper: '10000',
    cashPaper: cash,
    positions: positions,
    recentOrders: orders,
    valuation: PaperPortfolioValuation.notIncluded(
      portfolioRevision: revision,
      cashPaper: cash,
      openPositions: positions.where((position) => position.quantity != '0'),
    ),
    openedAt: DateTime.utc(2026, 9, 20, 12),
    updatedAt: DateTime.utc(2026, 9, 20, 15),
  );
}

PaperPortfolioPosition _position({
  required String assetId,
  required String mint,
  String symbol = 'AAPLx',
  String quantity = '2.1605',
}) => PaperPortfolioPosition(
  assetId: assetId,
  variantMint: mint,
  symbol: symbol,
  quantity: quantity,
  costBasisPaper: '500',
  averageCostPaper: '231.42',
  realizedGainPaper: '0',
  lockedGainPaper: '0',
  updatedAt: DateTime.utc(2026, 9, 20, 15),
);

PaperPortfolioOrder _order({
  required String orderId,
  required String assetId,
  required String mint,
  required String symbol,
  required DateTime committedAt,
}) => PaperPortfolioOrder(
  orderId: orderId,
  assetId: assetId,
  variantMint: mint,
  symbol: symbol,
  action: 'buy',
  pricePaper: '231.42',
  quantity: '2.1605',
  cashAfterPaper: '9500',
  committedAt: committedAt,
);
