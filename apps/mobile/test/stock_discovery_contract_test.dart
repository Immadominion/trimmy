import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/markets/stock_research.dart';
import 'package:trimmy/markets/stock_research_panel.dart';

/// One real response from the API's own discovery reader, frozen by
/// `tool/generate-discovery-contract.mjs`.
///
/// The server and the app were tested independently, against different
/// fixtures, and the app's parser requires an exact key set. Nothing proved the
/// two agreed, so a renamed or added server field would have broken every
/// search in production with both suites still green. This reads the server's
/// actual output.
Map<String, Object?> _contract() {
  final file = File('../../contracts/stock-discovery-v1.json');
  expect(
    file.existsSync(),
    isTrue,
    reason: 'the discovery contract is missing',
  );
  final data = jsonDecode(file.readAsStringSync());
  return (data as Map).cast<String, Object?>();
}

final class _ContractClient implements StockResearchClient {
  _ContractClient(this.contract);

  final Map<String, Object?> contract;

  @override
  Future<StockSearchPage> search(
    String query, {
    int limit = 10,
    StockResearchCancellation? cancellation,
  }) async => StockSearchPage.fromJson(contract['search']);

  @override
  Future<StockVariantsPage> variants(
    String assetId, {
    StockResearchCancellation? cancellation,
  }) async => StockVariantsPage.fromJson(contract['variants']);

  @override
  Future<StockEstimate> estimate(
    StockEstimateRequest request, {
    StockResearchCancellation? cancellation,
  }) async => throw StateError('The contract covers discovery only.');
}

final class _UnusedHistoryClient implements StockHistoryClient {
  @override
  Future<StockHistoryPage> history(
    StockHistoryRequest request, {
    StockResearchCancellation? cancellation,
  }) async => throw StateError('unused');
}

final class _UnusedRaydiumClient implements RaydiumQuoteClient {
  @override
  Future<RaydiumStockQuote> quote(
    RaydiumQuoteRequest request, {
    RaydiumQuoteCancellation? cancellation,
  }) async => throw StateError('unused');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the app parses a real server search response', () {
    final contract = _contract();
    expect(contract['schemaVersion'], 1);
    final page = StockSearchPage.fromJson(contract['search']);
    expect(page.query, 'Example Company');
    expect(page.limit, 5);
    // The server declares all of these, and the panel repeats them.
    expect(page.completeCatalog, isFalse);
    expect(page.provenance.executionEnabled, isFalse);
    expect(page.provenance.eligibility, 'unverified');
    expect(page.provenance.mintVerification, 'not_checked');
    expect(page.provenance.providerFreshness, 'not_verified');

    final asset = page.results.single;
    expect(asset.assetId, 'example-company');
    expect(asset.symbol, 'EX');
    expect(asset.variants, hasLength(2));

    final priced = asset.variants.first;
    expect(priced.chain, 'solana');
    expect(priced.issuer, 'Fixture Issuer A');
    expect(priced.market?.priceUsd, 101.25);
    expect(priced.market?.displayOnly, isTrue);
    // Provider timestamp units are undeclared, so nothing may read them as time.
    expect(priced.market?.timestampUnit, 'not_declared');

    // A flagged variant and its asset-level advisory must agree, and the app
    // checks that agreement, so this proves the server's pairing satisfies it.
    final flagged = asset.variants.last;
    expect(flagged.advisory?.status, StockAdvisoryStatus.caution);
    expect(asset.advisories.single.mint, flagged.mint);
    expect(asset.advisories.single.variantId, flagged.variantId);
  });

  test('the app parses a real server variants response', () {
    final page = StockVariantsPage.fromJson(_contract()['variants']);
    expect(page.assetId, 'example-company');
    expect(page.variants.map((variant) => variant.variantId), [
      'fixture-issuer-a',
      'fixture-issuer-b',
    ]);
  });

  testWidgets('the panel renders a real server response', (tester) async {
    final contract = _contract();
    final controller = StockResearchController.withClients(
      researchClient: _ContractClient(contract),
      historyClient: _UnusedHistoryClient(),
      raydiumClient: _UnusedRaydiumClient(),
      // Inside the response's own refresh window, so the reading is fresh.
      clock: () => DateTime.parse('2026-09-14T16:00:02.000Z'),
      timerFactory: (delay, callback) => _HeldTimer(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StockResearchPanel(controller: controller),
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('stock-research-query')),
      'Example Company',
    );
    await tester.tap(find.byKey(const ValueKey('stock-research-search')));
    await tester.pumpAndSettle();
    expect(find.text('Example Company (EX)'), findsOne);
    expect(find.text('Fixture A'), findsOne);
    expect(find.text('Price \$101.25'), findsOne);
    expect(find.text('Liquidity \$8,000'), findsOne);
    expect(
      find.text('The provider flags this one for caution.'),
      findsOne,
      reason: 'a flagged version must be shown as flagged',
    );
    expect(find.byKey(const ValueKey('stock-research-failure')), findsNothing);
  });
}

final class _HeldTimer implements Timer {
  var active = true;

  @override
  void cancel() => active = false;

  @override
  bool get isActive => active;

  @override
  int get tick => active ? 0 : 1;
}
