import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/design_study.dart';
import 'package:trimmy/markets/stock_research.dart';

/// Refuses every read, so any request the office makes on its own would be
/// visible as a call rather than silently answered.
final class _CountingResearchClient implements StockResearchClient {
  var calls = 0;

  Never _refuse() {
    calls++;
    throw const StockResearchException('STOCK_SERVICE_UNAVAILABLE');
  }

  @override
  Future<StockSearchPage> search(
    String query, {
    int limit = 10,
    StockResearchCancellation? cancellation,
  }) async => _refuse();

  @override
  Future<StockVariantsPage> variants(
    String assetId, {
    StockResearchCancellation? cancellation,
  }) async => _refuse();

  @override
  Future<StockEstimate> estimate(
    StockEstimateRequest request, {
    StockResearchCancellation? cancellation,
  }) async => _refuse();
}

final class _UnusedHistoryClient implements StockHistoryClient {
  @override
  Future<StockHistoryPage> history(
    StockHistoryRequest request, {
    StockResearchCancellation? cancellation,
  }) async => throw StateError('The office must not request history.');
}

final class _UnusedRaydiumClient implements RaydiumQuoteClient {
  @override
  Future<RaydiumStockQuote> quote(
    RaydiumQuoteRequest request, {
    RaydiumQuoteCancellation? cancellation,
  }) async => throw StateError('The office must not request a venue quote.');
}

Future<_CountingResearchClient> _office(WidgetTester tester) async {
  if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final client = _CountingResearchClient();
  final controller = StockResearchController.withClients(
    researchClient: client,
    historyClient: _UnusedHistoryClient(),
    raydiumClient: _UnusedRaydiumClient(),
  );
  addTearDown(controller.dispose);
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // Exactly the production nesting: the runtime is hosted above the office.
  await tester.pumpWidget(
    StockResearchHost(
      controller: controller,
      child: OfficeStudy(preferences: preferences),
    ),
  );
  await tester.pumpAndSettle();
  return client;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in [('Manrope', 'manrope'), ('Rubik', 'rubik')]) {
      await (FontLoader(font.$1)..addFont(
            rootBundle.load('assets/fonts/${font.$2}/${font.$1}-Variable.ttf'),
          ))
          .load();
    }
  });

  testWidgets(
    'a guest can reach stock prices and nothing is read to get there',
    (tester) async {
      final client = await _office(tester);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      final entry = find.byKey(const ValueKey('settings-stock-prices'));
      expect(entry, findsOne, reason: 'no account is needed to look at prices');
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('stock-research-query')), findsOne);
      expect(find.text('Market data only. No trading here.'), findsOne);
      // Opening the office and the panel asks the provider for nothing.
      expect(client.calls, 0);
    },
  );

  testWidgets('Portfolio opens stock exploration without a Settings detour', (
    tester,
  ) async {
    final client = await _office(tester);
    await tester.tap(find.text('Portfolio').last);
    await tester.pumpAndSettle();
    final entry = find.byKey(const ValueKey('portfolio-stock-prices'));
    expect(entry, findsOne);
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stock-research-query')), findsOne);
    expect(find.text('Market data only. No trading here.'), findsOne);
    expect(client.calls, 0);
    await tester.tap(find.widgetWithText(ActionChip, 'Apple'));
    await tester.pumpAndSettle();
    expect(client.calls, 1);
    expect(find.byKey(const ValueKey('stock-research-failure')), findsOne);
  });

  testWidgets('a search from the office reaches the provider', (tester) async {
    final client = await _office(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    final entry = find.byKey(const ValueKey('settings-stock-prices'));
    await tester.ensureVisible(entry);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('stock-research-query')),
      'Apple',
    );
    await tester.tap(find.byKey(const ValueKey('stock-research-search')));
    await tester.pumpAndSettle();
    expect(client.calls, 1);
    // A refusing provider is explained, not swallowed.
    expect(find.byKey(const ValueKey('stock-research-failure')), findsOne);
    expect(find.textContaining('STOCK_'), findsNothing);
  });
}
