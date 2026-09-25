import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/market/fast_buy_sheet.dart';
import 'package:trimmy/product/market/market_models.dart';
import 'market_test_support.dart';

void main() {
  testWidgets(
    'real fast buy filters both catalog and search to supported assets',
    (tester) async {
      final apple = testCompany();
      final unavailable = testCompany(
        assetId: 'hims',
        name: 'Hims',
        symbol: 'HIMS',
      );
      final gateway = FakeMarketSearchGateway(
        results: {
          'hims': [unavailable],
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FastBuySheet(
              gateway: gateway,
              companies: [apple, unavailable],
              canSelect: (company) => company.assetId == 'apple',
              loadAvailableCompanies: () async => [apple, unavailable],
              orderBuilder: (company, back) => Text('Order ${company.name}'),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Apple'), findsOneWidget);
      expect(find.text('Hims'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('fast-buy-search')),
        'hims',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('Hims'), findsNothing);
      expect(
        find.text('This stock isn’t available to buy yet.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      gateway.dispose();
    },
  );
  testWidgets('catalog connection failure offers a functioning retry', (
    tester,
  ) async {
    var calls = 0;
    final gateway = FakeMarketSearchGateway();
    Future<List<MarketCompany>> load() async {
      calls++;
      if (calls == 1) throw StateError('offline');
      return [testCompany()];
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FastBuySheet(
            gateway: gateway,
            companies: const [],
            loadAvailableCompanies: load,
            orderBuilder: (company, back) => Text(company.name),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Trading could not connect.'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(calls, 2);
    expect(find.text('Apple'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    gateway.dispose();
  });
}
