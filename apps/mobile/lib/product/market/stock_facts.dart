import 'package:flutter/foundation.dart';

/// Display-only company facts read from the API's stock facts routes: the
/// listed stock's daily change, a logo, a short description and a seven-day
/// sparkline. None of it approves an asset, prices an order or moves paper.
/// Missing facts stay null; the parser never invents a movement or a picture.
enum StockFactsFailure {
  invalidInput,
  unavailable,
  rateLimited,
  timeout,
  invalidResponse,
  offline,
}

final class StockFactsException implements Exception {
  const StockFactsException(this.failure, {this.retryAfter});

  final StockFactsFailure failure;
  final Duration? retryAfter;

  @override
  String toString() => 'StockFactsException(${failure.name})';
}

/// Session facts about the listed stock itself, not the on-chain token.
@immutable
final class StockSessionFacts {
  const StockSessionFacts({
    required this.priceUsd,
    required this.changePercent24h,
    required this.asOf,
  });

  factory StockSessionFacts.fromJson(Object? value) {
    final data = _object(value, const {
      'priceUsd',
      'changePercent24h',
      'asOfUnixSeconds',
    });
    return StockSessionFacts(
      priceUsd: _optionalNumber(data['priceUsd'], 0, _maxNumber),
      changePercent24h: _optionalNumber(
        data['changePercent24h'],
        -_maxChange,
        _maxChange,
      ),
      asOf: _optionalUnixSeconds(data['asOfUnixSeconds']),
    );
  }

  final double? priceUsd;
  final double? changePercent24h;
  final DateTime? asOf;
}

@immutable
final class StockCardVariantFacts {
  const StockCardVariantFacts({
    required this.mint,
    required this.symbol,
    required this.logoUrl,
    required this.priceUsd,
    required this.changePercent24h,
  });

  factory StockCardVariantFacts.fromJson(Object? value) {
    final data = _object(value, const {
      'mint',
      'symbol',
      'logoUrl',
      'priceUsd',
      'changePercent24h',
    });
    return StockCardVariantFacts(
      mint: _mint(data['mint']),
      symbol: _optionalText(data['symbol'], 40),
      logoUrl: _imageUrl(data['logoUrl']),
      priceUsd: _optionalNumber(data['priceUsd'], 0, _maxNumber),
      changePercent24h: _optionalNumber(
        data['changePercent24h'],
        -_maxChange,
        _maxChange,
      ),
    );
  }

  final String mint;
  final String? symbol;
  final String? logoUrl;
  final double? priceUsd;
  final double? changePercent24h;
}

@immutable
final class StockCardFacts {
  const StockCardFacts({
    required this.assetId,
    required this.name,
    required this.symbol,
    required this.imageUrl,
    required this.stock,
    required this.primaryVariant,
  });

  factory StockCardFacts.fromJson(Object? value) {
    final data = _object(value, const {
      'assetId',
      'name',
      'symbol',
      'imageUrl',
      'stock',
      'primaryVariant',
    });
    return StockCardFacts(
      assetId: _assetId(data['assetId']),
      name: _optionalText(data['name'], 200),
      symbol: _optionalText(data['symbol'], 40),
      imageUrl: _imageUrl(data['imageUrl']),
      stock: data['stock'] == null
          ? null
          : StockSessionFacts.fromJson(data['stock']),
      primaryVariant: data['primaryVariant'] == null
          ? null
          : StockCardVariantFacts.fromJson(data['primaryVariant']),
    );
  }

  final String assetId;
  final String? name;
  final String? symbol;
  final String? imageUrl;
  final StockSessionFacts? stock;
  final StockCardVariantFacts? primaryVariant;

  /// The listed stock's session change first, then the token's own day.
  double? get changePercent =>
      stock?.changePercent24h ?? primaryVariant?.changePercent24h;

  String? get logoUrl => imageUrl ?? primaryVariant?.logoUrl;
}

@immutable
final class StockCardsPage {
  const StockCardsPage({
    required this.query,
    required this.limit,
    required this.observedAt,
    required this.refreshAfter,
    required this.results,
  });

  factory StockCardsPage.fromJson(Object? value) {
    final data = _object(value, const {
      ..._provenanceKeys,
      'sourceUrl',
      'query',
      'limit',
      'completeCatalog',
      'results',
    });
    final provenance = _provenance(data);
    if (data['completeCatalog'] != false) _reject();
    _text(data['sourceUrl'], 2048);
    final limit = data['limit'];
    if (limit is! int || limit < 1 || limit > 20) _reject();
    final rows = data['results'];
    if (rows is! List || rows.length > limit) _reject();
    final results = rows.map(StockCardFacts.fromJson).toList(growable: false);
    if (results.map((row) => row.assetId).toSet().length != results.length) {
      _reject();
    }
    return StockCardsPage(
      query: _text(data['query'], 80),
      limit: limit,
      observedAt: provenance.$1,
      refreshAfter: provenance.$2,
      results: List.unmodifiable(results),
    );
  }

  final String query;
  final int limit;
  final DateTime observedAt;
  final DateTime refreshAfter;
  final List<StockCardFacts> results;
}

enum StockSparklineStatus { observed, empty, unavailable }

@immutable
final class StockSparklinePoint {
  const StockSparklinePoint({required this.at, required this.close});

  final DateTime at;
  final double close;
}

@immutable
final class StockFacts {
  const StockFacts({
    required this.assetId,
    required this.name,
    required this.symbol,
    required this.imageUrl,
    required this.description,
    required this.stock,
    required this.sparkline,
    required this.sparklineStatus,
    required this.observedAt,
    required this.refreshAfter,
  });

  factory StockFacts.fromJson(Object? value) {
    final data = _object(value, const {
      ..._provenanceKeys,
      'sourceUrls',
      'assetId',
      'name',
      'symbol',
      'imageUrl',
      'description',
      'stock',
      'sparkline',
      'sparklineStatus',
    });
    final provenance = _provenance(data);
    final sources = data['sourceUrls'];
    if (sources is! List || sources.isEmpty || sources.length > 2) _reject();
    for (final source in sources) {
      _text(source, 2048);
    }
    final statusName = _text(data['sparklineStatus'], 20);
    final status = StockSparklineStatus.values
        .where((item) => item.name == statusName)
        .firstOrNull;
    if (status == null) _reject();
    final sparkline = data['sparkline'] == null
        ? const <StockSparklinePoint>[]
        : _sparkline(data['sparkline']);
    if ((status == StockSparklineStatus.observed) != sparkline.isNotEmpty) {
      _reject();
    }
    return StockFacts(
      assetId: _assetId(data['assetId']),
      name: _optionalText(data['name'], 200),
      symbol: _optionalText(data['symbol'], 40),
      imageUrl: _imageUrl(data['imageUrl']),
      description: _optionalText(data['description'], 400),
      stock: data['stock'] == null
          ? null
          : StockSessionFacts.fromJson(data['stock']),
      sparkline: List.unmodifiable(sparkline),
      sparklineStatus: status,
      observedAt: provenance.$1,
      refreshAfter: provenance.$2,
    );
  }

  final String assetId;
  final String? name;
  final String? symbol;
  final String? imageUrl;
  final String? description;
  final StockSessionFacts? stock;
  final List<StockSparklinePoint> sparkline;
  final StockSparklineStatus sparklineStatus;
  final DateTime observedAt;
  final DateTime refreshAfter;

  List<double> get closes =>
      List.unmodifiable(sparkline.map((point) => point.close));
}

abstract interface class StockFactsRepository {
  Future<StockCardsPage> cards(String query, {int limit = 10});
  Future<StockFacts> facts(String assetId);
}

const _provenanceKeys = <String>{
  'schemaVersion',
  'provider',
  'requestedAt',
  'observedAt',
  'refreshAfter',
  'displayOnly',
  'executionEnabled',
  'eligibility',
};
const _maxNumber = 9007199254740991.0;
const _maxChange = 1000000.0;
const _imageHosts = <String>{
  'api.tokens.xyz',
  'xstocks-metadata.backed.fi',
  'cdn.ondo.finance',
};

Never _reject() =>
    throw const StockFactsException(StockFactsFailure.invalidResponse);

Map<String, Object?> _object(Object? value, Set<String> keys) {
  if (value is! Map<String, Object?>) _reject();
  if (value.keys.toSet().length != keys.length ||
      !value.keys.every(keys.contains)) {
    _reject();
  }
  return value;
}

(DateTime, DateTime) _provenance(Map<String, Object?> data) {
  if (data['schemaVersion'] != 1 ||
      data['provider'] != 'tokens-xyz-v1' ||
      data['displayOnly'] != true ||
      data['executionEnabled'] != false ||
      data['eligibility'] != 'unverified') {
    _reject();
  }
  final requestedAt = _utc(data['requestedAt']);
  final observedAt = _utc(data['observedAt']);
  final refreshAfter = _utc(data['refreshAfter']);
  if (observedAt.isBefore(requestedAt) ||
      !refreshAfter.isAfter(observedAt) ||
      refreshAfter.difference(requestedAt) > const Duration(minutes: 1)) {
    _reject();
  }
  return (observedAt, refreshAfter);
}

DateTime _utc(Object? value) {
  if (value is! String) _reject();
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc || !value.endsWith('Z')) _reject();
  return parsed;
}

String _text(Object? value, int max) {
  if (value is! String ||
      value.isEmpty ||
      value.length > max ||
      value.trim() != value ||
      value.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
    _reject();
  }
  return value;
}

String? _optionalText(Object? value, int max) =>
    value == null ? null : _text(value, max);

double? _optionalNumber(Object? value, double minimum, double maximum) {
  if (value == null) return null;
  if (value is! num) _reject();
  final number = value.toDouble();
  if (!number.isFinite || number < minimum || number > maximum) _reject();
  return number;
}

DateTime? _optionalUnixSeconds(Object? value) {
  if (value == null) return null;
  if (value is! int || value < 0 || value > 8640000000000) _reject();
  return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
}

String _assetId(Object? value) {
  final id = _text(value, 100);
  if (!RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(id)) _reject();
  return id;
}

String _mint(Object? value) {
  final mint = _text(value, 44);
  if (mint.length < 32 || !RegExp(r'^[1-9A-HJ-NP-Za-km-z]+$').hasMatch(mint)) {
    _reject();
  }
  return mint;
}

/// Only the server's allowed image hosts are shown; anything else is dropped
/// here too, so a changed server cannot make the app load an arbitrary image.
String? _imageUrl(Object? value) {
  if (value == null) return null;
  final raw = _text(value, 2048);
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      !(_imageHosts.contains(uri.host) ||
          uri.host == 'storage.googleapis.com' &&
              RegExp(
                r'^/tokens-asset-logos-prd/solana/[1-9A-HJ-NP-Za-km-z]{32,44}\.webp$',
              ).hasMatch(uri.path))) {
    return null;
  }
  return raw;
}

List<StockSparklinePoint> _sparkline(Object? value) {
  final data = _object(value, const {
    'interval',
    'fromUnixSeconds',
    'toUnixSeconds',
    'points',
  });
  if (data['interval'] != '4H') _reject();
  final from = _optionalUnixSeconds(data['fromUnixSeconds']);
  final to = _optionalUnixSeconds(data['toUnixSeconds']);
  final rows = data['points'];
  if (from == null || to == null || !to.isAfter(from)) _reject();
  if (rows is! List || rows.isEmpty || rows.length > 64) _reject();
  final points = <StockSparklinePoint>[];
  for (final row in rows) {
    final point = _object(row, const {'unixSeconds', 'close'});
    final at = _optionalUnixSeconds(point['unixSeconds']);
    final close = _optionalNumber(point['close'], 0, _maxNumber);
    if (at == null || close == null) _reject();
    if (points.isNotEmpty && !at.isAfter(points.last.at)) _reject();
    points.add(StockSparklinePoint(at: at, close: close));
  }
  return points;
}

/// A single on-chain version. Never merges its chart or change with the stock.
abstract interface class StockInsightReader {
  Future<StockInsight> insight(String assetId, String mint, String period);
}

final class StockInsight {
  StockInsight.fromJson(Object? value) {
    final data = _object(value, const {
      ..._provenanceKeys,
      'assetId',
      'mint',
      'period',
      'symbol',
      'description',
      'priceUsd',
      'changePercent24h',
      'asOfUnixSeconds',
      'volume24hUsd',
      'liquidityUsd',
      'tokenMarketCapUsd',
      'stockMarketCapUsd',
      'holders',
      'points',
      'chartStatus',
    });
    final dates = _provenance(data);
    observedAt = dates.$1;
    refreshAfter = dates.$2;
    assetId = _assetId(data['assetId']);
    mint = _mint(data['mint']);
    period = _text(data['period'], 10);
    if (!const ['day', 'week', 'month', 'year'].contains(period)) _reject();
    symbol = _optionalText(data['symbol'], 40);
    description = _optionalText(data['description'], 400);
    priceUsd = _optionalNumber(data['priceUsd'], 0, _maxNumber);
    changePercent24h = _optionalNumber(
      data['changePercent24h'],
      -_maxChange,
      _maxChange,
    );
    asOf = _optionalUnixSeconds(data['asOfUnixSeconds']);
    volume24hUsd = _optionalNumber(data['volume24hUsd'], 0, _maxNumber);
    liquidityUsd = _optionalNumber(data['liquidityUsd'], 0, _maxNumber);
    tokenMarketCapUsd = _optionalNumber(
      data['tokenMarketCapUsd'],
      0,
      _maxNumber,
    );
    stockMarketCapUsd = _optionalNumber(
      data['stockMarketCapUsd'],
      0,
      _maxNumber,
    );
    final count = _optionalNumber(data['holders'], 0, _maxNumber);
    if (count != null && count != count.roundToDouble()) _reject();
    holders = count?.toInt();
    chartStatus = _text(data['chartStatus'], 20);
    if (!const ['observed', 'empty', 'unavailable'].contains(chartStatus)) {
      _reject();
    }
    final raw = data['points'];
    if (raw is! List || raw.length > 400) _reject();
    points = List.unmodifiable(
      raw.map((item) {
        final row = _object(item, const {'unixSeconds', 'close'});
        final at = _optionalUnixSeconds(row['unixSeconds']);
        final close = _optionalNumber(row['close'], 0, _maxNumber);
        if (at == null || close == null) _reject();
        return StockSparklinePoint(at: at, close: close);
      }),
    );
    for (var i = 1; i < points.length; i++) {
      if (!points[i].at.isAfter(points[i - 1].at)) _reject();
    }
    if ((chartStatus == 'observed') != points.isNotEmpty) _reject();
  }
  late final DateTime observedAt, refreshAfter;
  late final String assetId, mint, period, chartStatus;
  late final String? symbol, description;
  late final double? priceUsd,
      changePercent24h,
      volume24hUsd,
      liquidityUsd,
      tokenMarketCapUsd,
      stockMarketCapUsd;
  late final int? holders;
  late final DateTime? asOf;
  late final List<StockSparklinePoint> points;
}
