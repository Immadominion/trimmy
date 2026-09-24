import 'validation.dart';

const discoveryKeys = {
  'schemaVersion',
  'provider',
  'sourceUrl',
  'requestedAt',
  'observedAt',
  'providerAsOf',
  'providerFreshness',
  'refreshAfter',
  'executionEnabled',
  'eligibility',
  'mintVerification',
};

class StockDiscoveryProvenance {
  StockDiscoveryProvenance._(
    this.sourceUrl,
    this.requestedAt,
    this.observedAt,
    this.refreshAfter,
  );
  factory StockDiscoveryProvenance.fromJson(Map<String, Object?> data) {
    researchSchema(data['schemaVersion']);
    if (data['provider'] != 'tokens-xyz-v1' ||
        data['providerAsOf'] != null ||
        data['providerFreshness'] != 'not_verified' ||
        data['executionEnabled'] != false ||
        data['eligibility'] != 'unverified' ||
        data['mintVerification'] != 'not_checked') {
      researchInvalid();
    }
    final requested = researchTimestamp(data['requestedAt']);
    final observed = researchTimestamp(data['observedAt']);
    final refresh = researchTimestamp(data['refreshAfter']);
    if (DateTime.parse(observed).isBefore(DateTime.parse(requested)) ||
        !DateTime.parse(refresh).isAfter(DateTime.parse(observed)) ||
        DateTime.parse(refresh).difference(DateTime.parse(requested)) >
            const Duration(seconds: 60)) {
      researchInvalid();
    }
    return StockDiscoveryProvenance._(
      researchSource(data['sourceUrl']),
      requested,
      observed,
      refresh,
    );
  }
  final Uri sourceUrl;
  final String requestedAt, observedAt, refreshAfter;
  String get provider => 'tokens-xyz-v1';
  String get eligibility => 'unverified';
  String get mintVerification => 'not_checked';
  String get providerFreshness => 'not_verified';
  bool get executionEnabled => false;
  bool needsRefresh(DateTime now) =>
      !now.isBefore(DateTime.parse(refreshAfter));
}

enum StockAdvisoryStatus { caution, compromised, blocked, unknown }

class StockAdvisory {
  StockAdvisory._(
    this.status,
    this.wireStatus,
    this.providerStatus,
    this.reason,
    this.since,
  );
  factory StockAdvisory.fromJson(Object? value) {
    final data = researchObject(value, const {
      'status',
      'providerStatus',
      'reason',
      'since',
    });
    return StockAdvisory.fromFields(data);
  }
  factory StockAdvisory.fromFields(Map<String, Object?> data) {
    final wire = researchText(data['status'], 60);
    final status =
        StockAdvisoryStatus.values
            .where((value) => value.name == wire)
            .firstOrNull ??
        StockAdvisoryStatus.unknown;
    return StockAdvisory._(
      status,
      wire,
      researchText(data['providerStatus'], 60),
      researchText(data['reason'], 1000),
      researchTimestamp(data['since']),
    );
  }
  final StockAdvisoryStatus status;

  /// Unknown future statuses stay visible and conservative, never treated as clear.
  final String wireStatus, providerStatus, reason, since;
}

class StockAssetAdvisory {
  StockAssetAdvisory._(this.mint, this.variantId, this.advisory);
  factory StockAssetAdvisory.fromJson(Object? value) {
    final data = researchObject(value, const {
      'mint',
      'variantId',
      'status',
      'providerStatus',
      'reason',
      'since',
    });
    return StockAssetAdvisory._(
      researchMint(data['mint']),
      researchVariantId(data['variantId']),
      StockAdvisory.fromFields(data),
    );
  }
  final String mint, variantId;
  final StockAdvisory advisory;
}

class StockVariantMarket {
  StockVariantMarket._(
    this.priceUsd,
    this.liquidityUsd,
    this.volume24hUsd,
    this.decimals,
    this.source,
    this.metricsSource,
    this.providerTimestamps,
  );
  factory StockVariantMarket.fromJson(Object? value) {
    final data = researchObject(value, const {
      'displayOnly',
      'priceUsd',
      'liquidityUsd',
      'volume24hUsd',
      'decimals',
      'source',
      'metricsSource',
      'providerTimestamps',
    });
    if (data['displayOnly'] != true) researchInvalid();
    final times = researchObject(data['providerTimestamps'], const {
      'asOf',
      'lastFetchedAt',
      'lastTradeAt',
      'unit',
    });
    if (times['unit'] != 'not_declared') researchInvalid();
    return StockVariantMarket._(
      researchMetric(data['priceUsd']),
      researchMetric(data['liquidityUsd']),
      researchMetric(data['volume24hUsd']),
      data['decimals'] == null
          ? null
          : researchInteger(data['decimals'], 0, 255),
      researchNullableText(data['source'], 80),
      researchNullableText(data['metricsSource'], 80),
      Map.unmodifiable({
        for (final key in const ['asOf', 'lastFetchedAt', 'lastTradeAt'])
          key: times[key] == null
              ? null
              : researchInteger(times[key], 0, 9007199254740991),
      }),
    );
  }
  final num? priceUsd, liquidityUsd, volume24hUsd;
  final int? decimals;
  final String? source, metricsSource;

  /// Provider units are not declared. These values are not converted to dates.
  final Map<String, int?> providerTimestamps;
  String get timestampUnit => 'not_declared';
  bool get displayOnly => true;
}

class StockVariant {
  StockVariant._(
    this.variantId,
    this.mint,
    this.kind,
    this.issuer,
    this.label,
    this.name,
    this.symbol,
    this.providerRedemptionTier,
    this.advisory,
    this.market,
  );
  factory StockVariant.fromJson(Object? value) {
    final data = researchObject(value, const {
      'variantId',
      'mint',
      'chain',
      'kind',
      'issuer',
      'label',
      'name',
      'symbol',
      'providerRedemptionTier',
      'advisory',
      'market',
    });
    if (data['chain'] != 'solana') researchInvalid();
    return StockVariant._(
      researchVariantId(data['variantId']),
      researchMint(data['mint']),
      researchText(data['kind'], 60),
      researchNullableText(data['issuer']),
      researchNullableText(data['label']),
      researchNullableText(data['name']),
      researchNullableText(data['symbol'], 40),
      researchNullableText(data['providerRedemptionTier'], 80),
      data['advisory'] == null
          ? null
          : StockAdvisory.fromJson(data['advisory']),
      data['market'] == null
          ? null
          : StockVariantMarket.fromJson(data['market']),
    );
  }
  final String variantId, mint, kind;
  final String? issuer, label, name, symbol, providerRedemptionTier;
  final StockAdvisory? advisory;
  final StockVariantMarket? market;
  String get chain => 'solana';
}

List<StockVariant> _variants(Object? value) {
  final rows = researchList(value, 64, StockVariant.fromJson);
  researchUnique(rows.map((row) => row.mint));
  researchUnique(rows.map((row) => row.variantId));
  return rows;
}

class StockDiscoveryAsset {
  StockDiscoveryAsset._(
    this.assetId,
    this.name,
    this.symbol,
    this.providerPrimaryVariantMint,
    this.variants,
    this.advisories,
  );
  factory StockDiscoveryAsset.fromJson(Object? value) {
    final data = researchObject(value, const {
      'assetId',
      'name',
      'symbol',
      'category',
      'providerPrimaryVariantMint',
      'variants',
      'advisories',
    });
    if (data['category'] != 'equity') researchInvalid();
    final variants = _variants(data['variants']);
    final primary = data['providerPrimaryVariantMint'] == null
        ? null
        : researchMint(data['providerPrimaryVariantMint']);
    if (primary != null &&
        !variants.any((variant) => variant.mint == primary)) {
      researchInvalid();
    }
    final flags = researchList(
      data['advisories'],
      64,
      StockAssetAdvisory.fromJson,
    );
    researchUnique(flags.map((flag) => flag.mint));
    for (final row in variants) {
      final flag = flags.where((flag) => flag.mint == row.mint).firstOrNull;
      if ((row.advisory != null) != (flag != null)) researchInvalid();
      if (flag != null &&
          (flag.variantId != row.variantId ||
              flag.advisory.wireStatus != row.advisory!.wireStatus ||
              flag.advisory.providerStatus != row.advisory!.providerStatus ||
              flag.advisory.reason != row.advisory!.reason ||
              flag.advisory.since != row.advisory!.since)) {
        researchInvalid();
      }
    }
    return StockDiscoveryAsset._(
      researchAssetId(data['assetId']),
      researchNullableText(data['name']),
      researchNullableText(data['symbol'], 40),
      primary,
      variants,
      flags,
    );
  }
  final String assetId;
  final String? name, symbol, providerPrimaryVariantMint;
  final List<StockVariant> variants;

  /// Includes flagged siblings omitted from the search variants.
  final List<StockAssetAdvisory> advisories;
  String get category => 'equity';
}

class StockSearchPage {
  StockSearchPage._(this.provenance, this.query, this.limit, this.results);
  factory StockSearchPage.fromJson(Object? value) {
    final data = researchObject(value, {
      ...discoveryKeys,
      'query',
      'limit',
      'completeCatalog',
      'results',
    });
    final provenance = StockDiscoveryProvenance.fromJson(data);
    if (data['completeCatalog'] != false) researchInvalid();
    final limit = researchInteger(data['limit'], 1, 20);
    final rows = researchList(
      data['results'],
      limit,
      StockDiscoveryAsset.fromJson,
    );
    researchUnique(rows.map((row) => row.assetId));
    researchUnique(
      rows.expand((row) => row.variants.map((variant) => variant.mint)),
    );
    return StockSearchPage._(
      provenance,
      researchText(data['query'], 80),
      limit,
      rows,
    );
  }
  final StockDiscoveryProvenance provenance;
  final String query;
  final int limit;
  final List<StockDiscoveryAsset> results;
  bool get completeCatalog => false;
}

class StockVariantsPage {
  StockVariantsPage._(this.provenance, this.assetId, this.variants);
  factory StockVariantsPage.fromJson(Object? value) {
    final data = researchObject(value, {
      ...discoveryKeys,
      'assetId',
      'variants',
    });
    return StockVariantsPage._(
      StockDiscoveryProvenance.fromJson(data),
      researchAssetId(data['assetId']),
      _variants(data['variants']),
    );
  }
  final StockDiscoveryProvenance provenance;
  final String assetId;
  final List<StockVariant> variants;
}
