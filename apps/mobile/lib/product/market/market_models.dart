import 'package:flutter/material.dart';

import '../../markets/discovery.dart';

enum MarketList {
  all('All stocks'),
  starterPicks('Starter picks'),
  trending('Trending'),
  movers('Movers'),
  mostHeld('Most held'),
  following('Following'),
  newOnChain('New on chain'),
  tech('Tech'),
  finance('Finance'),
  energy('Energy'),
  health('Health'),
  consumer('Consumer'),
  etfs('ETFs'),
  preIpo('Pre-IPO');

  const MarketList(this.label);
  final String label;
}

enum MarketSort {
  featured('Featured'),
  name('Name'),
  dayChange('Biggest gains'),
  dayLoss('Biggest drops'),
  price('Highest price'),
  floorHolders('Most held');

  const MarketSort(this.label);
  final String label;
}

@immutable
final class MarketFriendFace {
  const MarketFriendFace({required this.handle, required this.initials});

  final String handle;
  final String initials;
}

/// The presentation data that the current discovery response does not carry.
///
/// Identity, variants and provider prices always come from [asset]. The host
/// may enrich a company with a verified logo, change, description and social
/// counts. Missing enrichment stays visibly missing; this model never invents
/// a movement or holder.
@immutable
final class MarketCompany {
  MarketCompany({
    required this.asset,
    this.logoUrl,
    this.preferredVariantMint,
    this.description,
    this.sector,
    this.priceUsd,
    this.dayChangePercent,
    this.asOf,
    this.weekTrend = const <double>[],
    this.floorHolders,
    this.friendFaces = const <MarketFriendFace>[],
    this.lists = const <MarketList>{},
    this.brandColor = const Color(0xFFE7E0FA),
  }) : assert(weekTrend.every((point) => point.isFinite)),
       assert(dayChangePercent == null || dayChangePercent.isFinite),
       assert(floorHolders == null || floorHolders >= 0);

  factory MarketCompany.fromDiscovery(
    StockDiscoveryAsset asset, {
    String? logoUrl,
    String? description,
    String? sector,
    double? dayChangePercent,
    DateTime? asOf,
    List<double> weekTrend = const <double>[],
    int? floorHolders,
    List<MarketFriendFace> friendFaces = const <MarketFriendFace>[],
    Set<MarketList> lists = const <MarketList>{},
    Color brandColor = const Color(0xFFE7E0FA),
  }) {
    final primaryMint = asset.providerPrimaryVariantMint;
    final primary = primaryMint == null
        ? asset.variants.firstOrNull
        : asset.variants
              .where((variant) => variant.mint == primaryMint)
              .firstOrNull;
    return MarketCompany(
      asset: asset,
      logoUrl: logoUrl,
      description: description,
      sector: sector,
      priceUsd: primary?.market?.priceUsd?.toDouble(),
      dayChangePercent: dayChangePercent,
      asOf: asOf,
      weekTrend: List<double>.unmodifiable(weekTrend),
      floorHolders: floorHolders,
      friendFaces: List<MarketFriendFace>.unmodifiable(friendFaces),
      lists: Set<MarketList>.unmodifiable(lists),
      brandColor: brandColor,
    );
  }

  final StockDiscoveryAsset asset;
  final String? preferredVariantMint;
  final String? logoUrl;
  final String? description;
  final String? sector;
  final double? priceUsd;
  final double? dayChangePercent;
  final DateTime? asOf;
  final List<double> weekTrend;
  final int? floorHolders;
  final List<MarketFriendFace> friendFaces;
  final Set<MarketList> lists;
  final Color brandColor;

  String get assetId => asset.assetId;
  String get name => asset.name ?? asset.assetId;
  String get symbol => asset.symbol ?? asset.assetId.toUpperCase();

  /// Display the exact executable token, without borrowing another issuer's price.
  MarketCompany withVariant(String mint) {
    if (primaryVariant?.mint == mint) return this;
    final variant = asset.variants.where((v) => v.mint == mint).firstOrNull;
    if (variant == null) throw ArgumentError('Unknown stock variant');
    return MarketCompany(
      asset: asset,
      preferredVariantMint: mint,
      logoUrl: logoUrl,
      description: description,
      sector: sector,
      priceUsd: variant.market?.priceUsd?.toDouble(),
      asOf: asOf,
      lists: lists,
      brandColor: brandColor,
    );
  }

  StockVariant? get primaryVariant {
    final mint = preferredVariantMint ?? asset.providerPrimaryVariantMint;
    if (mint == null) return asset.variants.firstOrNull;
    return asset.variants.where((variant) => variant.mint == mint).firstOrNull;
  }
}

@immutable
final class MarketPosition {
  MarketPosition({
    required this.shares,
    required this.valuePaper,
    required this.averageCostPaper,
    required this.gainPercent,
    this.exactValuePaper,
    this.exactAverageCostPaper,
  }) : assert(valuePaper == null || valuePaper >= 0),
       assert(averageCostPaper >= 0),
       assert(gainPercent == null || gainPercent.isFinite);

  final String shares;
  final int? valuePaper;
  final int averageCostPaper;
  final double? gainPercent;
  final String? exactValuePaper;
  final String? exactAverageCostPaper;
}

@immutable
final class MarketReason {
  MarketReason({
    required this.handle,
    required this.initials,
    required this.note,
    required this.entryPrice,
    required this.performancePercent,
    required this.createdAt,
    this.isFriend = false,
  }) : assert(performancePercent.isFinite);

  final String handle;
  final String initials;
  final String note;
  final String entryPrice;
  final double performancePercent;
  final DateTime createdAt;
  final bool isFriend;
}

@immutable
final class MarketHolder {
  MarketHolder({
    required this.handle,
    required this.initials,
    required this.rank,
    required this.averageEntry,
    required this.performancePercent,
    this.isFriend = false,
  }) : assert(performancePercent.isFinite);

  final String handle;
  final String initials;
  final String rank;
  final String averageEntry;
  final double performancePercent;
  final bool isFriend;
}

enum MarketVersionStatus { verified, paused, risky, unknown }

@immutable
final class MarketVersionInfo {
  const MarketVersionInfo({
    required this.symbol,
    required this.issuer,
    required this.mint,
    required this.backingDisclosure,
    required this.tradingHours,
    required this.status,
  });

  final String symbol;
  final String issuer;
  final String mint;
  final String backingDisclosure;
  final String tradingHours;
  final MarketVersionStatus status;
}

@immutable
final class MarketStockDetails {
  const MarketStockDetails({
    required this.company,
    this.position,
    this.reasons = const <MarketReason>[],
    this.holders = const <MarketHolder>[],
    this.marketCap,
    this.yearRange,
    this.versions = const <MarketVersionInfo>[],
  });

  final MarketCompany company;
  final MarketPosition? position;
  final List<MarketReason> reasons;
  final List<MarketHolder> holders;
  final String? marketCap;
  final String? yearRange;
  final List<MarketVersionInfo> versions;
}

/// Session recents for the full-screen search. Persistence can hydrate and
/// observe this controller without coupling search UI to a storage package.
final class MarketRecentsController extends ChangeNotifier {
  MarketRecentsController([Iterable<MarketCompany> initial = const []])
    : _companies = List<MarketCompany>.of(initial).take(8).toList();

  final List<MarketCompany> _companies;

  List<MarketCompany> get companies => List.unmodifiable(_companies);

  void record(MarketCompany company) {
    _companies.removeWhere((item) => item.assetId == company.assetId);
    _companies.insert(0, company);
    if (_companies.length > 8) _companies.removeRange(8, _companies.length);
    notifyListeners();
  }

  void replace(Iterable<MarketCompany> companies) {
    _companies
      ..clear()
      ..addAll(companies.take(8));
    notifyListeners();
  }

  void clear() {
    if (_companies.isEmpty) return;
    _companies.clear();
    notifyListeners();
  }
}
