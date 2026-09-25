import 'dart:convert';
import 'package:http/http.dart' as http;
import 'market_models.dart';

const liveUsdcMint = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';

/// Capabilities are supplied by the execution API, never inferred from a logo,
/// ticker or the discovery provider's choice of primary token.
class LiveTradingAsset {
  const LiveTradingAsset({
    required this.assetId,
    required this.mint,
    required this.symbol,
    required this.name,
    required this.decimals,
    required this.maxBuyInputRaw,
    required this.maxSellInputRaw,
  });
  final String assetId, mint, symbol, name, maxBuyInputRaw, maxSellInputRaw;
  final int decimals;
  factory LiveTradingAsset.fromJson(Object? value) {
    if (value is! Map) throw const FormatException('Invalid trading asset');
    String field(String key, int length) {
      final result = value[key];
      if (result is! String || result.isEmpty || result.length > length) {
        throw const FormatException('Invalid trading asset');
      }
      return result;
    }

    final mint = field('mint', 44), decimals = value['decimals'];
    if (!RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$').hasMatch(mint) ||
        decimals is! int ||
        decimals < 0 ||
        decimals > 18) {
      throw const FormatException('Invalid trading precision');
    }
    String limit(String key) {
      final raw = value[key] ?? '100000000'; // deployed v1 capabilities
      if (raw is! String || !RegExp(r'^[1-9][0-9]{0,19}$').hasMatch(raw)) {
        throw const FormatException('Invalid trading limit');
      }
      return raw;
    }

    final symbol = field('symbol', 32);
    return LiveTradingAsset(
      assetId: field('assetId', 128),
      mint: mint,
      symbol: symbol,
      name: value['name'] is String ? field('name', 160) : symbol,
      decimals: decimals,
      maxBuyInputRaw: limit('maxBuyInputRaw'),
      maxSellInputRaw: limit('maxSellInputRaw'),
    );
  }
}

class LiveTradingCapabilities {
  const LiveTradingCapabilities({
    required this.enabled,
    required this.assets,
    required this.minimumSolBalanceLamports,
  });
  final bool enabled;
  final List<LiveTradingAsset> assets;
  final String minimumSolBalanceLamports;
  factory LiveTradingCapabilities.fromJson(Object? value) {
    if (value is! Map ||
        value['enabled'] is! bool ||
        value['network'] != 'solana:mainnet-beta' ||
        value['assets'] is! List) {
      throw const FormatException('Invalid trading capabilities');
    }
    final rows = value['assets'] as List;
    if (rows.length > 128) throw const FormatException('Too many assets');
    final assets = rows.map(LiveTradingAsset.fromJson).toList();
    if (assets.map((a) => a.mint).toSet().length != assets.length) {
      throw const FormatException('Duplicate trading mint');
    }
    final minimum = value['minimumSolBalanceLamports'];
    if (minimum is! String || !RegExp(r'^[0-9]{1,16}$').hasMatch(minimum)) {
      throw const FormatException('Invalid fee reserve');
    }
    return LiveTradingCapabilities(
      enabled: value['enabled'] as bool,
      assets: List.unmodifiable(assets),
      minimumSolBalanceLamports: minimum,
    );
  }
  LiveTradingAsset? forCompany(MarketCompany company) {
    for (final asset in assets) {
      if (asset.assetId == company.assetId &&
          company.asset.variants.any((v) => v.mint == asset.mint)) {
        return asset;
      }
    }
    return null;
  }

  LiveTradingAsset? forMint(String? mint) {
    for (final asset in assets) {
      if (asset.mint == mint) return asset;
    }
    return null;
  }
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
    final request = http.Request(
      'GET',
      origin.resolve('/v1/trading/capabilities'),
    )..followRedirects = false;
    final response = await transport
        .send(request)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw const FormatException('Trading unavailable');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 12),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > 65536) {
        throw const FormatException('Capabilities too large');
      }
    }
    return LiveTradingCapabilities.fromJson(jsonDecode(utf8.decode(bytes)));
  } finally {
    if (client == null) transport.close();
  }
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
