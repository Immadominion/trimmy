import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/market/asset_price_chart.dart';
import 'package:trimmy/product/market/stock_facts.dart';

void main() {
  testWidgets(
    'chart fills the viewport and only marks confirmed trades in range',
    (tester) async {
      final start = DateTime.utc(2026, 9, 24, 10);
      final end = start.add(const Duration(hours: 2));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AssetPriceChart(
              points: [
                StockSparklinePoint(at: start, close: 100),
                StockSparklinePoint(at: end, close: 105),
              ],
              trades: [
                AssetChartTrade(
                  id: 'buy',
                  at: start.add(const Duration(minutes: 30)),
                  price: 101,
                  shares: '0.4',
                  buy: true,
                ),
                AssetChartTrade(
                  id: 'sell',
                  at: start.add(const Duration(minutes: 90)),
                  price: 104,
                  shares: '0.2',
                  buy: false,
                ),
                AssetChartTrade(
                  id: 'old',
                  at: start.subtract(const Duration(days: 1)),
                  price: 50,
                  shares: '1',
                  buy: true,
                ),
              ],
            ),
          ),
        ),
      );
      final chart = tester.getRect(
        find.byKey(const ValueKey('asset-chart-paint')),
      );
      expect(chart.left, 0);
      expect(chart.right, 800);
      expect(find.byKey(const ValueKey('chart-trade-old')), findsNothing);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('S'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chart-trade-sell')));
      await tester.pump();
      expect(find.textContaining('Sold 0.2'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
