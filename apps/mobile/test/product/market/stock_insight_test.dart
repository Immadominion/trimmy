import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/design/product_theme.dart';
import 'package:trimmy/product/market/market.dart';
import 'package:trimmy/product/market/asset_price_chart.dart';
import 'package:trimmy/ui_review/review_animated_splash.dart';
import 'market_test_support.dart';
import '../../stock_facts_models_test.dart' as fixtures;

Map<String, Object?> payload(String period) => {
  ...fixtures.provenance(),
  'assetId': 'apple',
  'mint': testMint,
  'period': period,
  'symbol': 'AAPLx',
  'description': 'Apple makes computers.',
  'priceUsd': 231.42,
  'changePercent24h': -1.2,
  'asOfUnixSeconds': 1789900000,
  'volume24hUsd': 100000,
  'liquidityUsd': 200000,
  'tokenMarketCapUsd': 300000,
  'stockMarketCapUsd': 3e12,
  'holders': 1200,
  'chartStatus': 'observed',
  'points': [
    {'unixSeconds': 1789890000, 'close': 230},
    {'unixSeconds': 1789900000, 'close': 231.42},
  ],
};

class Reader implements StockFactsRepository, StockInsightReader {
  final calls = <String, Completer<StockInsight>>{};
  @override
  Future<StockInsight> insight(String assetId, String mint, String period) =>
      (calls[period] = Completer<StockInsight>()).future;
  @override
  Future<StockFacts> facts(String id) =>
      throw StateError('Must use mint-bound insight');
  @override
  Future<StockCardsPage> cards(String query, {int limit = 10}) =>
      throw UnimplementedError();
}

void main() {
  test(
    'rejects duplicate timestamps, non-integer holders and inconsistent empty status',
    () {
      for (final edit in [
        {'holders': 1.5},
        {'chartStatus': 'empty'},
        {
          'points': [
            {'unixSeconds': 100, 'close': 1},
            {'unixSeconds': 100, 'close': 2},
          ],
        },
      ]) {
        expect(
          () => StockInsight.fromJson({...payload('day'), ...edit}),
          throwsA(isA<StockFactsException>()),
        );
      }
      expect(
        StockInsight.fromJson({...payload('day'), 'holders': 0}).holders,
        0,
      );
    },
  );
  testWidgets(
    'range races cannot show the previous range and the chart uses token facts',
    (tester) async {
      final reader = Reader();
      final facts = MarketFactsController(repository: reader);
      addTearDown(facts.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: productTheme(),
          home: CompanyStockPage(
            details: MarketStockDetails(company: testCompany()),
            factsController: facts,
            orderRepository: FakePaperOrderRepository(),
            clientOrderId: () => 'test',
            availablePaper: '1000',
            availableShares: '0',
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(TrimmyLiquidMark), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('asset-period-week')));
      await tester.pump();
      reader.calls['week']!.complete(StockInsight.fromJson(payload('week')));
      await tester.pumpAndSettle();
      expect(find.byType(AssetPriceChart), findsOneWidget);
      expect(find.text('-1.20%'), findsOneWidget);
      reader.calls['day']!.complete(
        StockInsight.fromJson({...payload('day'), 'priceUsd': 999}),
      );
      await tester.pumpAndSettle();
      expect(find.text('\$999.00'), findsNothing);
      expect(find.byKey(const ValueKey('asset-chart-week')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('real insight layout fits narrow screens with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final reader = Reader();
    final facts = MarketFactsController(repository: reader);
    addTearDown(facts.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: CompanyStockPage(
          details: MarketStockDetails(company: testCompany()),
          factsController: facts,
          orderRepository: FakePaperOrderRepository(),
          clientOrderId: () => 'test',
          availablePaper: '1000',
          availableShares: '0',
        ),
      ),
    );
    reader.calls['day']!.complete(StockInsight.fromJson(payload('day')));
    await tester.pumpAndSettle();
    final error = tester.takeException();
    expect(error, isNull);
    for (var i = 0; i < 5; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets(
    'liquid loading respects reduced motion and uses the current asset',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: TrimmyLiquidMark(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.image(const AssetImage('assets/images/ui_review/trimmy-mark.png')),
        findsOneWidget,
      );
      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );
}
