import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// What one displayed share of each held stock token is worth, from the
/// server's trusted prices: the issuer's price, else a liquid market's. A
/// token's last trade is not used on its own, because a token that barely
/// trades can show many times its share price. A token the server cannot price
/// stays unpriced, and the app then shows no value rather than a wrong one.
class HoldingPrices {
  HoldingPrices(this.origin, {http.Client? client})
    : _client = client ?? http.Client();

  final Uri origin;
  final http.Client _client;

  static final _mint = RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$');
  static const _perRequest = 50;

  /// Prices per displayed share by mint. Throws when the server cannot answer.
  Future<Map<String, double>> read(Iterable<String> mints) async {
    final ids = {...mints.where(_mint.hasMatch)}.toList()..sort();
    final prices = <String, double>{};
    for (var start = 0; start < ids.length; start += _perRequest) {
      final part = ids.sublist(
        start,
        start + _perRequest > ids.length ? ids.length : start + _perRequest,
      );
      final response = await _client
          .get(
            origin
                .resolve('/v1/markets/stocks/prices')
                .replace(queryParameters: {'mints': part.join(',')}),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200 || response.bodyBytes.length > 65536) {
        throw const FormatException('prices unavailable');
      }
      prices.addAll(parse(jsonDecode(response.body), part.toSet()));
    }
    return prices;
  }

  /// Only the asked-for mints, with a positive, finite price per share.
  static Map<String, double> parse(Object? body, Set<String> asked) {
    if (body is! Map<String, dynamic> ||
        body['schema'] != 1 ||
        body['prices'] is! List) {
      throw const FormatException('prices');
    }
    final prices = <String, double>{};
    for (final row in body['prices'] as List) {
      if (row is! Map<String, dynamic>) throw const FormatException('price');
      final mint = row['mint'], usd = row['usdPerShare'];
      final source = row['source'];
      if (mint is! String ||
          !asked.contains(mint) ||
          usd is! num ||
          !usd.isFinite ||
          usd <= 0 ||
          (source != 'issuer' && source != 'market')) {
        throw const FormatException('price');
      }
      prices[mint] = usd.toDouble();
    }
    return prices;
  }

  void close() => _client.close();
}
