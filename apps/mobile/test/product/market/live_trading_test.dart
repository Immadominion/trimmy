import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/product/market/live_trading.dart';
import 'market_test_support.dart';

Map<String, Object?> capabilities() => {
  'enabled': true,
  'network': 'solana:mainnet-beta',
  'minimumSolBalanceLamports': '5000',
  'assets': [
    {
      'assetId': 'apple',
      'mint': testMint,
      'name': 'Apple',
      'symbol': 'AAPLx',
      'decimals': 8,
      'maxBuyInputRaw': '100000000',
      'maxSellInputRaw': '100000000',
    },
  ],
};
void main() {
  test(
    'exact conversions retain small fractions and reject ambiguous input',
    () {
      expect(liveAmountRaw('0.00591613', 8), '591613');
      expect(liveAmountRaw('9007199254740993', 8), '900719925474099300000000');
      expect(liveAmountRaw('1.000001', 6), '1000001');
      expect(liveAmountRaw('0.0000001', 6), isNull);
      for (final text in ['-1', '0', 'NaN', '1e3', '1,000', '1.2.3']) {
        expect(liveAmountRaw(text, 8), isNull);
      }
      expect(liveDecimal('591613', 8), '0.00591613');
      expect(liveDecimal('100000000', 8), '1');
      expect(liveDecimal('0', 8), '0');
    },
  );
  test('capability must match both company and issuer mint', () {
    final caps = LiveTradingCapabilities.fromJson(capabilities());
    expect(caps.forCompany(testCompany())?.symbol, 'AAPLx');
    expect(caps.forCompany(testCompany(assetId: 'tesla')), isNull);
    expect(caps.forMint(testMint)?.maxBuyInputRaw, '100000000');
  });
  test(
    'invalid capability precision, duplicate mints and other networks fail closed',
    () {
      final raw = capabilities();
      final asset = (raw['assets'] as List).first as Map;
      asset['decimals'] = 19;
      expect(
        () => LiveTradingCapabilities.fromJson(raw),
        throwsFormatException,
      );
      final duplicate = capabilities();
      (duplicate['assets'] as List).add((duplicate['assets'] as List).first);
      expect(
        () => LiveTradingCapabilities.fromJson(duplicate),
        throwsFormatException,
      );
      expect(
        () => LiveTradingCapabilities.fromJson({
          ...capabilities(),
          'network': 'devnet',
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'capability request rejects redirects and distinguishes outage from disabled',
    () async {
      final client = MockClient((request) async {
        expect(request.followRedirects, isFalse);
        return http.Response(
          jsonEncode({...capabilities(), 'enabled': false}),
          200,
        );
      });
      final caps = await fetchLiveTradingCapabilities(
        Uri.parse('https://api.trimmy.test'),
        client: client,
      );
      expect(caps.enabled, isFalse);
      await expectLater(
        fetchLiveTradingCapabilities(
          Uri.parse('https://api.trimmy.test'),
          client: MockClient((_) async => http.Response('', 503)),
        ),
        throwsFormatException,
      );
      await expectLater(
        fetchLiveTradingCapabilities(
          Uri.parse('http://api.trimmy.test'),
          client: client,
        ),
        throwsArgumentError,
      );
    },
  );
}
