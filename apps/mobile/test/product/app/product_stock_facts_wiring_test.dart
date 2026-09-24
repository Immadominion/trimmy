import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/markets/stock_research.dart';
import 'package:trimmy/product/app/product_app.dart';
import 'package:trimmy/product/market/market.dart';
import 'package:trimmy/product/market/market_craft.dart';

import '../../stock_facts_models_test.dart' as facts_fixtures;
import '../../support/stock_research_fixtures.dart';

final class _FactsRepository implements StockFactsRepository {
  _FactsRepository({this.cardsHandler});

  final Future<StockCardsPage> Function(String query, int limit)? cardsHandler;
  int cardCalls = 0;
  int detailCalls = 0;

  @override
  Future<StockCardsPage> cards(String query, {int limit = 10}) {
    cardCalls++;
    final handler = cardsHandler;
    if (handler != null) return handler(query, limit);
    final payload = facts_fixtures.cardsPage()
      ..['query'] = query
      ..['limit'] = limit;
    return Future.value(StockCardsPage.fromJson(payload));
  }

  @override
  Future<StockFacts> facts(String assetId) {
    detailCalls++;
    return Future.value(StockFacts.fromJson(facts_fixtures.facts()));
  }
}

StockResearchController _configuredResearch() => StockResearchController.create(
  config: StockResearchConfig.parse(apiUrl: 'https://stocks.example'),
  httpClientFactory: () => MockClient((request) async {
    if (request.url.path == '/v1/markets/stocks/search') {
      final query = request.url.queryParameters['query']!;
      final limit = int.parse(request.url.queryParameters['limit']!);
      return http.Response(
        jsonEncode(stockSearchFixture(query: query, limit: limit)),
        200,
        headers: const {'content-type': 'application/json'},
      );
    }
    return http.Response(
      jsonEncode({'code': 'unavailable'}),
      503,
      headers: const {'content-type': 'application/json'},
    );
  }),
  clock: () => DateTime.parse('2026-09-14T18:00:02.000Z'),
);

Future<SharedPreferences> _preferences() async {
  SharedPreferences.setMockInitialValues({
    'trimmy.entry.guest-chosen.v1': true,
    'trimmy.product.introduction-exited.v1': true,
    'trimmy.product.profile.v1': jsonEncode({
      'version': 1,
      'goal': 'learn',
      'knowledge': 'nothing',
      'persona': 'oracle',
      'dailyGoal': 'one-mission',
      'handle': 'rookie_one',
    }),
    'trimmy.product.notifications.v1': 'notRequested',
  });
  return SharedPreferences.getInstance();
}

Widget _app({
  required SharedPreferences preferences,
  required StockResearchController research,
  required StockFactsRepository facts,
}) => StockResearchHost(
  controller: research,
  child: TrimmyProductApp(
    preferences: preferences,
    account: null,
    accountConfigurationFailed: false,
    stockFactsRepository: facts,
  ),
);

void main() {
  testWidgets(
    'configured ProductApp enriches search and lazily loads company facts',
    (tester) async {
      final preferences = await _preferences();
      final research = _configuredResearch();
      final facts = _FactsRepository();
      addTearDown(research.dispose);

      await tester.pumpWidget(
        _app(preferences: preferences, research: research, facts: facts),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('product-tab-market')));
      await tester.pumpAndSettle();

      // The catalog uses a separate HTTP boundary; this fixture supplies search.
      expect(find.byKey(const ValueKey('market-open-search')), findsOneWidget);
      expect(facts.cardCalls, 1);
      expect(facts.detailCalls, 0);

      await tester.tap(find.byKey(const ValueKey('market-open-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('market-search-field')),
        'Apple',
      );
      await tester.pump(const Duration(milliseconds: 281));
      await tester.pumpAndSettle();

      final result = find.byKey(const ValueKey('market-search-result-apple'));
      expect(result, findsOneWidget);
      expect(facts.cardCalls, 2);
      final logo = tester.widget<CompanyLogo>(
        find.descendant(of: result, matching: find.byType(CompanyLogo)),
      );
      expect(logo.logoUrl, 'https://api.tokens.xyz/logos/xstocks/AAPLx.png');

      await tester.tap(result);
      await tester.pumpAndSettle();

      expect(facts.detailCalls, 1);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('stock-company-description')),
        250,
      );
      expect(find.text('Apple designs phones and computers.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('stock-facts-sparkline')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('stock-buy-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('stock-sell-button')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      research.dispose();
    },
  );

  testWidgets('an unconfigured public API never starts a facts read', (
    tester,
  ) async {
    final preferences = await _preferences();
    final research = StockResearchController.create(
      config: StockResearchConfig.parse(apiUrl: ''),
    );
    final facts = _FactsRepository();
    addTearDown(research.dispose);

    await tester.pumpWidget(
      _app(preferences: preferences, research: research, facts: facts),
    );
    await tester.pumpAndSettle();

    expect(facts.cardCalls, 0);
    expect(facts.detailCalls, 0);
    expect(find.text('Market'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    research.dispose();
  });

  testWidgets('a pending card response cannot notify the disposed app', (
    tester,
  ) async {
    final preferences = await _preferences();
    final research = _configuredResearch();
    final response = Completer<StockCardsPage>();
    final facts = _FactsRepository(cardsHandler: (_, _) => response.future);
    addTearDown(research.dispose);

    await tester.pumpWidget(
      _app(preferences: preferences, research: research, facts: facts),
    );
    await tester.pump();
    await tester.pump();
    expect(facts.cardCalls, 1);

    await tester.pumpWidget(const SizedBox());
    final payload = facts_fixtures.cardsPage()
      ..['query'] = 'a'
      ..['limit'] = 20;
    response.complete(StockCardsPage.fromJson(payload));
    await tester.pump();

    expect(tester.takeException(), isNull);
    research.dispose();
  });
}
