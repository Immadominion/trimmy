import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../account/account_amounts.dart';
import 'market_models.dart';

const liveUsdcMint = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';

/// Bounds for one capabilities read. A multi-issuer catalog lists every
/// tradeable token, so these sit well above today's list but stay finite.
const liveCapabilitiesMaxAssets = 600;
const liveCapabilitiesMaxUnavailable = 1200;
const liveCapabilitiesMaxBytes = 524288;
const _maxIssuers = 16;

final _mintPattern = RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$');
final _rawLimitPattern = RegExp(r'^[1-9][0-9]{0,19}$');
final _assetIdPattern = RegExp(r'^[a-z0-9][a-z0-9_-]{0,127}$');
final _issuerIdPattern = RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$');
final _versionPattern = RegExp(r'^[^\s\x00-\x1f\x7f]{1,64}$');
final _reasonPattern = RegExp(r'^[a-z0-9_]{1,64}$');
final _controlCharacters = RegExp(r'[\x00-\x1f\x7f]');
final _proseControlCharacters = RegExp(r'[\x00-\x09\x0b-\x1f\x7f]');

String _text(Object? value, int max, String error) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.length > max ||
      _controlCharacters.hasMatch(value)) {
    throw FormatException(error);
  }
  return value;
}

/// Optional plain text that may run to a few sentences or lines. Missing or
/// null reads as empty; anything else that is not clean text is refused.
String _prose(Object? value, int max, String error) {
  if (value == null) return '';
  if (value is! String ||
      value.length > max ||
      _proseControlCharacters.hasMatch(value)) {
    throw FormatException(error);
  }
  return value.trim();
}

/// An issuer's eligibility statement. The version changes whenever the text or
/// terms change, and the server checks the accepted version on every quote.
@immutable
class LiveTradingAttestation {
  const LiveTradingAttestation({required this.version, required this.text});
  final String version, text;
}

/// Who issues a tradeable token and what a buyer accepts. Supplied by the
/// execution API and shown before any quote, never inferred from a symbol.
@immutable
class LiveTradingIssuer {
  const LiveTradingIssuer({
    required this.issuerId,
    required this.name,
    required this.termsUrl,
    required this.attestation,
    this.legalName = '',
    this.productType = '',
    this.summary = '',
    this.holderRights = '',
    this.warning = '',
    this.excludedRegions = const [],
    this.offered = true,
    this.notOfferedReason,
  });

  final String issuerId, name, legalName, productType, summary, holderRights;

  /// The issuer's key warning, shown above the eligibility tick. May be empty.
  final String warning;
  final List<String> excludedRegions;
  final Uri termsUrl;
  final LiveTradingAttestation attestation;

  /// Whether Trimmy offers this issuer's tokens. A tick or a trade is never
  /// offered for an issuer that is not.
  final bool offered;

  /// Why the issuer is not offered, in one plain sentence.
  final String? notOfferedReason;

  LiveTradingIssuer _offering(bool value) => LiveTradingIssuer(
    issuerId: issuerId,
    name: name,
    termsUrl: termsUrl,
    attestation: attestation,
    legalName: legalName,
    productType: productType,
    summary: summary,
    holderRights: holderRights,
    warning: warning,
    excludedRegions: excludedRegions,
    offered: value,
    notOfferedReason: notOfferedReason,
  );

  /// Parses an issuer. [offered] is null when an older server leaves it out;
  /// the capabilities then decide it from whether the issuer has tokens.
  static (LiveTradingIssuer, bool?) _fromJson(Object? value) {
    const error = 'Invalid trading issuer';
    final issuer = LiveTradingIssuer.fromJson(value);
    final offered = (value as Map)['offered'];
    if (offered != null && offered is! bool) throw const FormatException(error);
    return (issuer, offered as bool?);
  }

  factory LiveTradingIssuer.fromJson(Object? value) {
    const error = 'Invalid trading issuer';
    if (value is! Map) throw const FormatException(error);
    final issuerId = value['issuerId'];
    if (issuerId is! String || !_issuerIdPattern.hasMatch(issuerId)) {
      throw const FormatException(error);
    }
    final regions = value['excludedRegions'];
    if (regions is! List || regions.length > 250) {
      throw const FormatException(error);
    }
    final termsText = _text(value['termsUrl'], 2048, error);
    final terms = Uri.tryParse(termsText);
    if (terms == null ||
        terms.scheme != 'https' ||
        terms.host.isEmpty ||
        terms.userInfo.isNotEmpty) {
      throw const FormatException(error);
    }
    final attestation = value['attestation'];
    if (attestation is! Map) throw const FormatException(error);
    final version = attestation['version'];
    if (version is! String || !_versionPattern.hasMatch(version)) {
      throw const FormatException(error);
    }
    final offered = value['offered'];
    final reason = _prose(value['notOfferedReason'], 500, error);
    return LiveTradingIssuer(
      issuerId: issuerId,
      name: _text(value['name'], 80, error),
      legalName: _text(value['legalName'], 160, error),
      productType: _text(value['productType'], 80, error),
      summary: _text(value['summary'], 1000, error),
      holderRights: _text(value['holderRights'], 500, error),
      warning: _prose(value['warning'], 1000, error),
      excludedRegions: List.unmodifiable([
        for (final region in regions) _text(region, 80, error),
      ]),
      termsUrl: terms,
      attestation: LiveTradingAttestation(
        version: version,
        text: _text(attestation['text'], 500, error),
      ),
      offered: offered is bool ? offered : true,
      notOfferedReason: reason.isEmpty ? null : reason,
    );
  }

  /// Servers from before multi-issuer trading list only Backed xStocks and
  /// send no issuer section. They keep the Backed terms link and the generic
  /// eligibility statement.
  static final legacyXStocks = LiveTradingIssuer(
    issuerId: 'xstocks',
    name: 'xStocks',
    legalName: 'Backed Assets (JE) Limited',
    termsUrl: Uri.parse('https://assets.backed.fi/legal-documentation'),
    attestation: const LiveTradingAttestation(
      version: 'legacy',
      text: 'I’m eligible under the issuer’s terms.',
    ),
  );
}

/// Capabilities are supplied by the execution API, never inferred from a logo,
/// ticker or the discovery provider's choice of primary token.
@immutable
class LiveTradingAsset {
  const LiveTradingAsset({
    required this.assetId,
    required this.mint,
    required this.symbol,
    required this.name,
    required this.decimals,
    required this.maxBuyInputRaw,
    required this.maxSellInputRaw,
    this.issuerId = 'xstocks',
    this.transferFeeBps = 0,
  });

  /// The company id. Several tokens from different issuers can share it.
  final String assetId;
  final String mint, symbol, name, maxBuyInputRaw, maxSellInputRaw, issuerId;
  final int decimals;

  /// A Token-2022 transfer fee the issuer charges on every transfer.
  final int transferFeeBps;

  factory LiveTradingAsset.fromJson(Object? value, {required bool legacy}) {
    const error = 'Invalid trading asset';
    if (value is! Map) throw const FormatException(error);
    final assetId = value['assetId'], mint = value['mint'];
    final decimals = value['decimals'];
    if (assetId is! String ||
        !_assetIdPattern.hasMatch(assetId) ||
        mint is! String ||
        !_mintPattern.hasMatch(mint) ||
        mint == liveUsdcMint) {
      throw const FormatException(error);
    }
    if (decimals is! int || decimals < 0 || decimals > 18) {
      throw const FormatException('Invalid trading precision');
    }
    String limit(String key) {
      // Deployed legacy capabilities predate per-asset limits.
      final raw = value[key] ?? (legacy ? '100000000' : null);
      if (raw is! String || !_rawLimitPattern.hasMatch(raw)) {
        throw const FormatException('Invalid trading limit');
      }
      return raw;
    }

    final symbol = _text(value['symbol'], 32, error);
    final String issuerId;
    final int fee;
    if (legacy) {
      issuerId = 'xstocks';
      fee = 0;
    } else {
      final issuer = value['issuerId'], bps = value['transferFeeBps'];
      if (issuer is! String || !_issuerIdPattern.hasMatch(issuer)) {
        throw const FormatException(error);
      }
      if (bps is! int || bps < 0 || bps > 1000) {
        throw const FormatException('Invalid issuer fee');
      }
      issuerId = issuer;
      fee = bps;
    }
    return LiveTradingAsset(
      assetId: assetId,
      mint: mint,
      symbol: symbol,
      name: legacy && value['name'] is! String
          ? symbol
          : _text(value['name'], 160, error),
      decimals: decimals,
      maxBuyInputRaw: limit('maxBuyInputRaw'),
      maxSellInputRaw: limit('maxSellInputRaw'),
      issuerId: issuerId,
      transferFeeBps: fee,
    );
  }
}

/// A token discovery lists that Trimmy cannot trade, with the server's
/// reason code. [issuerId] is null when no issuer could be matched.
@immutable
class LiveUnavailableVariant {
  const LiveUnavailableVariant({
    required this.mint,
    required this.issuerId,
    required this.reason,
  });
  final String mint, reason;
  final String? issuerId;
}

/// One of a company's tokens as Real mode sees it: tradeable with its asset,
/// or unavailable with a plain reason.
@immutable
class LiveVariantOption {
  const LiveVariantOption({
    required this.mint,
    required this.label,
    this.asset,
    this.reason,
  });
  final String mint, label;
  final LiveTradingAsset? asset;
  final String? reason;
  bool get tradeable => asset != null;
}

class LiveTradingCapabilities {
  LiveTradingCapabilities._({
    required this.schemaVersion,
    required this.enabled,
    required List<LiveTradingAsset> assets,
    required Map<String, LiveTradingIssuer> issuers,
    required Map<String, LiveUnavailableVariant> unavailable,
    required this.minimumSolBalanceLamports,
  }) : assets = List.unmodifiable(assets),
       issuers = Map.unmodifiable(issuers),
       unavailable = Map.unmodifiable(unavailable),
       _byMint = {for (final asset in assets) asset.mint: asset},
       _byAssetId = _group(assets);

  /// 1 for servers that predate issuer terms, 2 for issuer-aware servers.
  final int schemaVersion;
  final bool enabled;
  final List<LiveTradingAsset> assets;
  final Map<String, LiveTradingIssuer> issuers;

  /// Tokens that cannot be traded, by mint.
  final Map<String, LiveUnavailableVariant> unavailable;
  final String minimumSolBalanceLamports;
  final Map<String, LiveTradingAsset> _byMint;
  final Map<String, List<LiveTradingAsset>> _byAssetId;

  /// A legacy server lists only xStocks and has no issuer terms to check.
  bool get legacy => schemaVersion < 2;

  static Map<String, List<LiveTradingAsset>> _group(
    List<LiveTradingAsset> assets,
  ) {
    final groups = <String, List<LiveTradingAsset>>{};
    for (final asset in assets) {
      (groups[asset.assetId] ??= []).add(asset);
    }
    return groups;
  }

  factory LiveTradingCapabilities.fromJson(Object? value) {
    if (value is! Map ||
        value['enabled'] is! bool ||
        value['network'] != 'solana:mainnet-beta' ||
        value['assets'] is! List) {
      throw const FormatException('Invalid trading capabilities');
    }
    final version = value['schemaVersion'];
    final legacy =
        (version == null || version == 1) && !value.containsKey('issuers');
    if (!legacy && version != 2) {
      throw const FormatException('Unsupported trading capabilities');
    }
    final rows = value['assets'] as List;
    if (rows.length > liveCapabilitiesMaxAssets) {
      throw const FormatException('Too many assets');
    }
    final assets = [
      for (final row in rows) LiveTradingAsset.fromJson(row, legacy: legacy),
    ];
    if (assets.map((a) => a.mint).toSet().length != assets.length) {
      throw const FormatException('Duplicate trading mint');
    }
    final issuers = <String, LiveTradingIssuer>{};
    if (legacy) {
      issuers['xstocks'] = LiveTradingIssuer.legacyXStocks;
    } else {
      final list = value['issuers'];
      if (list is! List || list.length > _maxIssuers) {
        throw const FormatException('Invalid trading issuers');
      }
      for (final row in list) {
        final (issuer, offered) = LiveTradingIssuer._fromJson(row);
        if (issuers.containsKey(issuer.issuerId)) {
          throw const FormatException('Duplicate trading issuer');
        }
        // An older issuer-aware server does not say. An issuer with tokens
        // to trade is offered; one without is not.
        issuers[issuer.issuerId] = offered == null
            ? issuer._offering(
                assets.any((asset) => asset.issuerId == issuer.issuerId),
              )
            : issuer;
      }
    }
    if (assets.any((asset) => !issuers.containsKey(asset.issuerId))) {
      throw const FormatException('Unknown trading issuer');
    }
    final minimum = value['minimumSolBalanceLamports'];
    if (minimum is! String || !RegExp(r'^[0-9]{1,16}$').hasMatch(minimum)) {
      throw const FormatException('Invalid fee reserve');
    }
    return LiveTradingCapabilities._(
      schemaVersion: legacy ? 1 : 2,
      enabled: value['enabled'] as bool,
      assets: assets,
      issuers: issuers,
      unavailable: legacy ? const {} : _unavailable(value['unavailable']),
      minimumSolBalanceLamports: minimum,
    );
  }

  /// The list only words a reason, so a malformed row is skipped rather than
  /// taking all trading down. A mint that is also in [assets] is read as an
  /// asset first by [reasonFor] and [optionsFor].
  static Map<String, LiveUnavailableVariant> _unavailable(Object? value) {
    if (value == null) return const {};
    if (value is! List || value.length > liveCapabilitiesMaxUnavailable) {
      throw const FormatException('Invalid unavailable tokens');
    }
    final rows = <String, LiveUnavailableVariant>{};
    for (final row in value) {
      if (row is! Map) continue;
      final mint = row['mint'],
          issuer = row['issuerId'],
          reason = row['reason'];
      if (mint is! String ||
          !_mintPattern.hasMatch(mint) ||
          (issuer != null &&
              (issuer is! String || !_issuerIdPattern.hasMatch(issuer))) ||
          reason is! String ||
          !_reasonPattern.hasMatch(reason)) {
        continue;
      }
      rows.putIfAbsent(
        mint,
        () => LiveUnavailableVariant(
          mint: mint,
          issuerId: issuer as String?,
          reason: reason,
        ),
      );
    }
    return rows;
  }

  /// Every tradeable token of [company] that discovery also lists for it,
  /// most liquid first. Tokens without a liquidity reading come last, in the
  /// server's order. An issuer that is not offered never counts.
  List<LiveTradingAsset> variantsFor(MarketCompany company) {
    final candidates = _byAssetId[company.assetId];
    if (candidates == null) return const [];
    final liquidity = <String, num?>{
      for (final variant in company.asset.variants)
        variant.mint: variant.market?.liquidityUsd,
    };
    final matched = [
      for (final (index, asset) in candidates.indexed)
        if (liquidity.containsKey(asset.mint) &&
            issuers[asset.issuerId]?.offered == true)
          (index, asset),
    ];
    matched.sort((a, b) {
      final left = liquidity[a.$2.mint], right = liquidity[b.$2.mint];
      if (left != null && right != null && left != right) {
        return right.compareTo(left);
      }
      if ((left == null) != (right == null)) return left == null ? 1 : -1;
      return a.$1.compareTo(b.$1);
    });
    return List.unmodifiable([for (final row in matched) row.$2]);
  }

  /// Every token discovery lists for [company]: tradeable ones first, most
  /// liquid first, then the rest in discovery's order with their reason.
  List<LiveVariantOption> optionsFor(MarketCompany company) {
    final tradeable = variantsFor(company);
    final mints = {for (final asset in tradeable) asset.mint};
    return List.unmodifiable([
      for (final asset in tradeable)
        LiveVariantOption(
          mint: asset.mint,
          label: variantLabel(asset),
          asset: asset,
        ),
      for (final variant in company.asset.variants)
        if (!mints.contains(variant.mint))
          LiveVariantOption(
            mint: variant.mint,
            label:
                '${_issuerName(variant.mint) ?? variant.issuer ?? variant.label ?? 'Other issuer'}'
                ' · ${_byMint[variant.mint]?.symbol ?? variant.symbol ?? variant.label ?? company.symbol}',
            reason: reasonFor(variant.mint),
          ),
    ]);
  }

  String? _issuerName(String mint) =>
      issuers[_byMint[mint]?.issuerId ?? unavailable[mint]?.issuerId]?.name;

  /// Why a token cannot be traded, in one short plain sentence.
  String reasonFor(String mint) {
    const notOffered = 'This issuer is not offered in Trimmy.';
    final asset = _byMint[mint];
    if (asset != null) {
      final issuer = issuers[asset.issuerId];
      return issuer == null || issuer.offered
          ? 'Not available to trade in Trimmy yet.'
          : issuer.notOfferedReason ?? notOffered;
    }
    final row = unavailable[mint];
    if (row == null) return 'Not available to trade in Trimmy yet.';
    return switch (row.reason) {
      'issuer_not_offered' =>
        issuers[row.issuerId]?.notOfferedReason ?? notOffered,
      'identity_unverified' =>
        'Trimmy could not confirm who issued this token.',
      'token_restricted' =>
        'The issuer has restrictions on this token that Trimmy cannot accept.',
      'low_liquidity' => 'Too little trading to buy and sell it safely.',
      'no_reviewed_route' => 'No order route passed Trimmy’s safety checks.',
      'price_off_market' => 'Its price is too far from the real share price.',
      'held_back' => 'Paused while Trimmy checks this token.',
      'not_reviewed' => 'Not checked yet.',
      _ => 'Not available to trade in Trimmy.',
    };
  }

  /// Tokens Real mode can list for sale: the issuer must be offered.
  List<LiveTradingAsset> get tradeableAssets => [
    for (final asset in assets)
      if (issuers[asset.issuerId]?.offered == true) asset,
  ];

  /// The default token for [company]: the most liquid tradeable one.
  LiveTradingAsset? forCompany(MarketCompany company) =>
      variantsFor(company).firstOrNull;

  LiveTradingAsset? forMint(String? mint) => _byMint[mint];

  /// Whether Real mode can trade [company] right now.
  bool tradeable(MarketCompany company) =>
      enabled && variantsFor(company).isNotEmpty;

  LiveTradingIssuer issuerFor(LiveTradingAsset asset) =>
      issuers[asset.issuerId] ??
      (throw ArgumentError('Unknown trading issuer'));

  /// A short label that tells two tokens of one company apart.
  String variantLabel(LiveTradingAsset asset) =>
      '${issuerFor(asset).name} · ${asset.symbol}';
}

Future<LiveTradingCapabilities> fetchLiveTradingCapabilities(
  Uri origin, {
  http.Client? client,
}) async {
  if (origin.scheme != 'https' || origin.userInfo.isNotEmpty) {
    throw ArgumentError('HTTPS required');
  }
  final transport = client ?? http.Client();
  try {
    final route = origin.resolve('/v1/trading/capabilities');
    return await _readCapabilities(
          transport,
          route.replace(queryParameters: {'schema': '2'}),
        ) ??
        // A server from before issuer terms rejects the unknown query with
        // 400. Its plain route still answers with the legacy shape.
        await _readCapabilities(transport, route) ??
        (throw const FormatException('Trading unavailable'));
  } finally {
    if (client == null) transport.close();
  }
}

Future<LiveTradingCapabilities?> _readCapabilities(
  http.Client transport,
  Uri url,
) async {
  final request = http.Request('GET', url)..followRedirects = false;
  final response = await transport
      .send(request)
      .timeout(const Duration(seconds: 12));
  if (response.statusCode == 400) {
    await response.stream.listen(null).cancel();
    return null;
  }
  if (response.statusCode != 200) {
    throw const FormatException('Trading unavailable');
  }
  final bytes = <int>[];
  await for (final chunk in response.stream.timeout(
    const Duration(seconds: 12),
  )) {
    bytes.addAll(chunk);
    if (bytes.length > liveCapabilitiesMaxBytes) {
      throw const FormatException('Capabilities too large');
    }
  }
  return LiveTradingCapabilities.fromJson(jsonDecode(utf8.decode(bytes)));
}

/// Exact amount conversion. No floating-point rounding reaches a signed order.
String? liveAmountRaw(String text, int decimals) {
  text = text.trim();
  if (decimals < 0 ||
      decimals > 18 ||
      text.length > 40 ||
      !RegExp(r'^[0-9]+(?:\.[0-9]*)?$').hasMatch(text)) {
    return null;
  }
  final parts = text.split('.');
  final fraction = parts.length == 2 ? parts[1] : '';
  if (fraction.length > decimals) return null;
  final result =
      BigInt.parse(parts[0]) * BigInt.from(10).pow(decimals) +
      BigInt.parse(
        fraction.padRight(decimals, '0').isEmpty
            ? '0'
            : fraction.padRight(decimals, '0'),
      );
  return result > BigInt.zero ? result.toString() : null;
}

String liveDecimal(String raw, int decimals) {
  if (decimals == 0) return raw;
  final text = raw.padLeft(decimals + 1, '0');
  return '${text.substring(0, text.length - decimals)}.${text.substring(text.length - decimals)}'
      .replaceFirst(RegExp(r'\.?0+$'), '');
}

/// A plain decimal string with thousands separators and no trailing zeros.
/// Anything else is returned unchanged rather than guessed at.
String liveGroupedDecimal(String decimal) {
  final match = RegExp(r'^([0-9]+)(?:\.([0-9]+))?$').firstMatch(decimal);
  if (match == null) return decimal;
  final whole = match[1]!.replaceFirst(RegExp(r'^0+(?=[0-9])'), '');
  final fraction = (match[2] ?? '').replaceFirst(RegExp(r'0+$'), '');
  final grouped = whole.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
  return fraction.isEmpty ? grouped : '$grouped.$fraction';
}

/// Basis points as a short percentage: 300 is 3%, 20 is 0.2%.
String livePercent(int bps) {
  final whole = bps ~/ 100, rest = (bps % 100).abs();
  if (rest == 0) return '$whole%';
  final fraction = rest
      .toString()
      .padLeft(2, '0')
      .replaceFirst(RegExp(r'0$'), '');
  return '$whole.$fraction%';
}

final _decimalPattern = RegExp(r'^([0-9]+)(?:\.([0-9]+))?$');

/// Converts between exact raw token units and the shares people see.
///
/// Token-2022 scaled UI amounts make shares = raw / 10^decimals x multiplier.
/// The multiplier comes from the reviewed order, or from the wallet's own
/// display amount over its raw amount. It is kept as an exact fraction so no
/// floating point reaches an order. Without a reading the multiplier is 1.
@immutable
class LiveShareScale {
  const LiveShareScale._(this.decimals, this._numerator, this._denominator);

  factory LiveShareScale.plain(int decimals) =>
      LiveShareScale._(decimals, BigInt.one, BigInt.one);

  /// The multiplier the server read for this token at review time, as a
  /// decimal string such as `1.0009180758490996`. A missing or unusable value
  /// shows plain token units rather than a guessed share amount.
  factory LiveShareScale.fromMultiplier(int decimals, Object? multiplier) {
    final match = multiplier is String && multiplier.length <= 64
        ? _decimalPattern.firstMatch(multiplier)
        : null;
    if (match == null || decimals < 0 || decimals > 18) {
      return LiveShareScale.plain(decimals);
    }
    final fraction = match[2] ?? '';
    final numerator = BigInt.parse('${match[1]}$fraction');
    if (numerator <= BigInt.zero) return LiveShareScale.plain(decimals);
    final denominator = BigInt.from(10).pow(fraction.length);
    final divisor = numerator.gcd(denominator);
    return LiveShareScale._(
      decimals,
      numerator ~/ divisor,
      denominator ~/ divisor,
    );
  }

  factory LiveShareScale.fromDisplay({
    required int decimals,
    required String amountRaw,
    required String? displayAmount,
  }) {
    final raw = BigInt.tryParse(amountRaw);
    final display = displayAmount == null
        ? null
        : _decimalPattern.firstMatch(displayAmount);
    if (decimals < 0 ||
        decimals > 18 ||
        raw == null ||
        raw <= BigInt.zero ||
        display == null ||
        displayAmount!.length > 80) {
      return LiveShareScale.plain(decimals);
    }
    final fraction = display[2] ?? '';
    final shown = BigInt.parse('${display[1]}$fraction');
    if (shown <= BigInt.zero) return LiveShareScale.plain(decimals);
    // (shown / 10^fraction) / (raw / 10^decimals), as one reduced fraction.
    final numerator = shown * BigInt.from(10).pow(decimals);
    final denominator = raw * BigInt.from(10).pow(fraction.length);
    final divisor = numerator.gcd(denominator);
    return LiveShareScale._(
      decimals,
      numerator ~/ divisor,
      denominator ~/ divisor,
    );
  }

  final int decimals;
  final BigInt _numerator, _denominator;

  /// Whether shares differ from plain token units.
  bool get scaled => _numerator != _denominator;

  /// Share figures show at most six decimal places. A millionth of a share is
  /// below a cent for any listed stock, and the cap hides the last-digit noise
  /// of converting through a multiplier, so a typed 0.5 reads back as 0.5.
  static const shareDigits = 6;

  /// Shares as (units, digits): raw x multiplier in units of 10^-digits.
  /// Balances and minimums round down; quoted figures round to nearest. Dust
  /// too small for six places keeps full precision rather than reading 0.
  (BigInt, int) _scaledShares(String raw, {bool nearest = false}) {
    final value = BigInt.tryParse(raw);
    if (value == null || value <= BigInt.zero) return (BigInt.zero, 0);
    (BigInt, int) at(int digits) {
      final top = value * _numerator;
      final bottom = _denominator * BigInt.from(10).pow(decimals - digits);
      final two = BigInt.two;
      return (
        nearest ? (top * two + bottom) ~/ (bottom * two) : top ~/ bottom,
        digits,
      );
    }

    final short = at(decimals < shareDigits ? decimals : shareDigits);
    return short.$1 > BigInt.zero ? short : at(decimals);
  }

  static String _plain((BigInt, int) shares) =>
      liveDecimal(shares.$1.toString(), shares.$2);

  static String _read((BigInt, int) shares) =>
      formatRawUnits(shares.$1.toString(), shares.$2) ?? _plain(shares);

  /// Shares for an amount field: rounded down, no separators.
  String shares(String raw) => _plain(_scaledShares(raw));

  /// Shares for reading a balance or a minimum: rounded down, grouped.
  String label(String raw) => _read(_scaledShares(raw));

  /// Shares for reading a quoted figure: rounded to the nearest place, so an
  /// amount someone typed reads back the same. Grouped.
  String approx(String raw) => _read(_scaledShares(raw, nearest: true));

  /// Shares to the token's full precision, rounded down, grouped. For records
  /// such as trade history, where nothing is typed back.
  String exact(String raw) {
    final value = BigInt.tryParse(raw);
    if (value == null || value <= BigInt.zero) return '0';
    return _read((value * _numerator ~/ _denominator, decimals));
  }

  /// Raw units for shares someone typed, to the nearest raw unit. Null when
  /// the text is invalid or rounds to zero.
  String? raw(String shares) {
    final typed = liveAmountRaw(shares, decimals);
    if (typed == null) return null;
    final two = BigInt.two;
    final result =
        (BigInt.parse(typed) * _denominator * two + _numerator) ~/
        (_numerator * two);
    return result > BigInt.zero ? result.toString() : null;
  }
}
