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
          lists: marketListsFor(asset, card),
          brandColor: marketCardColor(asset.assetId),
        ),
      );
    }
    return MarketCatalogPage(List.unmodifiable(companies), total, next as int?);
  }
}

/// The Market tags a company carries. Funds: the provider's fund and
/// commodity categories, plus funds it files as equities (named ETF or Fund).
/// Pre-IPO: a private company, traded only as PreStocks or Tessera tokens
/// and with no listed share price yet.
Set<MarketList> marketListsFor(
  StockDiscoveryAsset asset,
  StockCardFacts card,
) => {
  MarketList.all,
  if (asset.category == 'etf' ||
      asset.category == 'commodity' ||
      _fundName.hasMatch(asset.name ?? ''))
    MarketList.etfs,
  if (card.stock == null &&
      asset.variants.any(
        (variant) =>
            _privateIssuers.contains(variant.issuer) ||
            _privateIssuers.contains(variant.label),
      ))
    MarketList.preIpo,
};

final _fundName = RegExp(r'\b(ETF|ETN|Fund)\b');
const _privateIssuers = {'PreStocks', 'Tessera'};

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

  /// Funds and commodities come with `schema=2`. A server from before them
  /// refuses the parameter with 400, and its plain answer lists equities.
  bool _schema2 = true;

  Future<http.Response> _read(String path, Map<String, String> query) async {
    Future<http.Response> get(bool schema2) => _client
        .get(
          origin
              .resolve(path)
              .replace(queryParameters: {...query, if (schema2) 'schema': '2'}),
        )
        .timeout(const Duration(seconds: 12));
    final response = await get(_schema2);
    if (response.statusCode != 400 || !_schema2) return response;
    _schema2 = false;
    return get(false);
  }

  @override
  Future<MarketCatalogPage> load({int offset = 0}) async {
    final response = await _read('/v1/markets/stocks/catalog', {
      'offset': '$offset',
    });
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
    final response = await _read('/v1/markets/stocks/search', {
      'query': assetId.replaceAll('-', ' '),
      'limit': '20',
    });
    if (response.statusCode != 200) {
      throw const FormatException('company unavailable');
    }
    final page = StockSearchPage.fromJson(jsonDecode(response.body));
    final asset = page.results.where((a) => a.assetId == assetId).firstOrNull;
    if (asset == null) return null;
    StockCardFacts? card;
    try {
      final response = await _read('/v1/markets/stocks/cards', {
        'query': assetId.replaceAll('-', ' '),
        'limit': '20',
      });
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
