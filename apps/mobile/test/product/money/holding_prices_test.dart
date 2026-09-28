import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/product/money/holding_prices.dart';

const _a = 'XsDoVfqeBukxuZHWhdvWHBhgEHjGNst4MLodqsJHzoB';
const _b = 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp';

void main() {
  test('reads trusted prices for held tokens only', () async {
    final requests = <Uri>[];
    final prices = HoldingPrices(
      Uri.parse('https://api.example'),
      client: MockClient((request) async {
        requests.add(request.url);
        return http.Response(
          jsonEncode({
            'schema': 1,
            'observedAt': '2026-09-28T17:40:00.000Z',
            'prices': [
              {
                'mint': _a,
                'usdPerShare': 54.235,
                'source': 'issuer',
                'asOf': '2026-09-28T17:35:20.786Z',
              },
            ],
          }),
          200,
        );
      }),
    );
    expect(await prices.read([_b, _a, _a, 'not a mint']), {_a: 54.235});
    expect(requests.single.path, '/v1/markets/stocks/prices');
    expect(requests.single.queryParameters['mints'], '$_a,$_b');
  });

  test('refuses answers it did not ask for or cannot trust', () {
    Map<String, double> parse(Object? row) => HoldingPrices.parse(
      {
        'schema': 1,
        'prices': [row],
      },
      {_a},
    );
    expect(parse({'mint': _a, 'usdPerShare': 10, 'source': 'market'}), {
      _a: 10.0,
    });
    for (final row in [
      {'mint': _b, 'usdPerShare': 10, 'source': 'issuer'},
      {'mint': _a, 'usdPerShare': 0, 'source': 'issuer'},
      {'mint': _a, 'usdPerShare': '10', 'source': 'issuer'},
      {'mint': _a, 'usdPerShare': 10, 'source': 'trade'},
    ]) {
      expect(() => parse(row), throwsFormatException);
    }
    expect(
      () => HoldingPrices.parse({'schema': 2, 'prices': []}, {_a}),
      throwsFormatException,
    );
  });

  test('a failed read throws so the app keeps showing no value', () async {
    final prices = HoldingPrices(
      Uri.parse('https://api.example'),
      client: MockClient((_) async => http.Response('busy', 503)),
    );
    await expectLater(prices.read([_a]), throwsFormatException);
  });
}
