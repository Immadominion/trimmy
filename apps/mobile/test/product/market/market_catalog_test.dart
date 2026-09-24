import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/product/market/market_catalog.dart';
import '../../stock_facts_models_test.dart' as facts;
import '../../support/stock_research_fixtures.dart';

Map<String, Object?> payload() => {
  'discovery': stockSearchFixture(query: 'catalog', limit: 20),
  'cards': [facts.card()],
  'offset': 0,
  'total': 30,
  'nextOffset': 20,
};
void main() {
  test(
    'catalog pairs token price with token change and preserves pagination',
    () {
      final page = MarketCatalogPage.fromJson(payload(), offset: 0);
      expect(page.companies.single.priceUsd, 200.5);
      expect(page.companies.single.dayChangePercent, -.26);
      expect(page.companies.single.logoUrl, contains('AAPLx.png'));
      expect(page.nextOffset, 20);
    },
  );
  test(
    'catalog rejects mismatched identities and invalid continuation offsets',
    () {
      final mismatch = payload()
        ..['cards'] = [
          facts.card({'assetId': 'tesla'}),
        ];
      expect(
        () => MarketCatalogPage.fromJson(mismatch, offset: 0),
        throwsFormatException,
      );
      for (final offset in [0, 19, 40, -20]) {
        expect(
          () => MarketCatalogPage.fromJson(
            payload()..['nextOffset'] = offset,
            offset: 0,
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'catalog performs public API reads and surfaces errors without sample data',
    () async {
      final client = HttpMarketCatalogGateway(
        Uri.parse('https://api.trimmy.example'),
        client: MockClient((r) async {
          expect(r.url.path, '/v1/markets/stocks/catalog');
          expect(r.url.queryParameters, {'offset': '0'});
          expect(r.headers.containsKey('authorization'), false);
          return http.Response(jsonEncode(payload()), 200);
        }),
      );
      addTearDown(client.close);
      expect((await client.load()).companies.single.assetId, 'apple');
      final failure = HttpMarketCatalogGateway(
        Uri.parse('https://api.trimmy.example'),
        client: MockClient((_) async => http.Response('{}', 503)),
      );
      addTearDown(failure.close);
      await expectLater(failure.load(), throwsFormatException);
    },
  );
}
