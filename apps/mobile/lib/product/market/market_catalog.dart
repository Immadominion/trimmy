import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../markets/discovery.dart';
import 'market_facts.dart';
import 'market_models.dart';
import 'stock_facts.dart';

class MarketCatalogPage {
  const MarketCatalogPage(this.companies, this.total, this.nextOffset);
  final List<MarketCompany> companies;
  final int total;
  final int? nextOffset;

  factory MarketCatalogPage.fromJson(Object? value, {required int offset}) {
    if (value is! Map<String, dynamic>) throw const FormatException('catalog');
    final page = StockSearchPage.fromJson(value['discovery']);
    final total = value['total'];
    final next = value['nextOffset'];
    final rows = value['cards'];
    if (page.query != 'catalog' ||
        value['offset'] != offset ||
        total is! int ||
        total < 0 ||
        total > 10000 ||
        next != null &&
            (next is! int || next != offset + 20 || next >= total) ||
        rows is! List ||
        rows.length != page.results.length) {
      throw const FormatException('catalog pagination');
    }
    final cards = rows.map(StockCardFacts.fromJson).toList();
    final companies = <MarketCompany>[];
    for (var i = 0; i < page.results.length; i++) {
      final asset = page.results[i];
      final card = cards[i];
      if (card.assetId != asset.assetId) {
        throw const FormatException('catalog identity');
      }
      companies.add(
        MarketCompany.fromDiscovery(
          asset,
          logoUrl: card.logoUrl,
          // Compare the token's price with the same token's change, not the
          // underlying exchange's different session price.
          dayChangePercent:
              card.primaryVariant?.mint == asset.providerPrimaryVariantMint
              ? card.primaryVariant?.changePercent24h
              : null,
          asOf: DateTime.tryParse(page.provenance.observedAt),
          lists: const {MarketList.all},
          brandColor: marketCardColor(asset.assetId),
        ),
      );
    }
    return MarketCatalogPage(List.unmodifiable(companies), total, next as int?);
  }
}

abstract interface class MarketCatalogGateway {
  Future<MarketCatalogPage> load({int offset = 0});
  Future<MarketCompany?> find(String assetId);
  void close();
}

class HttpMarketCatalogGateway implements MarketCatalogGateway {
  HttpMarketCatalogGateway(this.origin, {http.Client? client})
    : _client = client ?? http.Client();
  final Uri origin;
  final http.Client _client;

  @override
  Future<MarketCatalogPage> load({int offset = 0}) async {
    final response = await _client
        .get(
          origin
              .resolve('/v1/markets/stocks/catalog')
              .replace(queryParameters: {'offset': '$offset'}),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw const FormatException('catalog unavailable');
    }
    if (response.bodyBytes.length > 1500000) {
      throw const FormatException('catalog size');
    }
    return MarketCatalogPage.fromJson(
      jsonDecode(response.body),
      offset: offset,
    );
  }

  @override
  Future<MarketCompany?> find(String assetId) async {
    final response = await _client
        .get(
          origin
              .resolve('/v1/markets/stocks/search')
              .replace(
                queryParameters: {
                  'query': assetId.replaceAll('-', ' '),
                  'limit': '20',
                },
              ),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw const FormatException('company unavailable');
    }
    final page = StockSearchPage.fromJson(jsonDecode(response.body));
    final asset = page.results.where((a) => a.assetId == assetId).firstOrNull;
    if (asset == null) return null;
    StockCardFacts? card;
    try {
      final response = await _client
          .get(
            origin
                .resolve('/v1/markets/stocks/cards')
                .replace(
                  queryParameters: {
                    'query': assetId.replaceAll('-', ' '),
                    'limit': '20',
                  },
                ),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        card = StockCardsPage.fromJson(
          jsonDecode(response.body),
        ).results.where((c) => c.assetId == assetId).firstOrNull;
      }
    } catch (_) {
      /* Discovery remains usable when optional images are unavailable. */
    }
    return MarketCompany.fromDiscovery(
      asset,
      logoUrl: card?.logoUrl,
      dayChangePercent:
          card?.primaryVariant?.mint == asset.providerPrimaryVariantMint
          ? card?.primaryVariant?.changePercent24h
          : null,
      asOf: DateTime.tryParse(page.provenance.observedAt),
      brandColor: marketCardColor(assetId),
    );
  }

  @override
  void close() => _client.close();
}
