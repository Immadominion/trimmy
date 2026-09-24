import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/market/stock_facts.dart';

const _mint = 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp';

Map<String, Object?> provenance() => {
  'schemaVersion': 1,
  'provider': 'tokens-xyz-v1',
  'requestedAt': '2026-09-20T15:00:00.000Z',
  'observedAt': '2026-09-20T15:00:01.000Z',
  'refreshAfter': '2026-09-20T15:01:00.000Z',
  'displayOnly': true,
  'executionEnabled': false,
  'eligibility': 'unverified',
};

Map<String, Object?> card([Map<String, Object?> overrides = const {}]) => {
  'assetId': 'apple',
  'name': 'Apple',
  'symbol': 'AAPL',
  'imageUrl': 'https://api.tokens.xyz/logos/xstocks/AAPLx.png',
  'stock': {
    'priceUsd': 334.79,
    'changePercent24h': -0.6557,
    'asOfUnixSeconds': 1789768429,
  },
  'primaryVariant': {
    'mint': _mint,
    'symbol': 'AAPLx',
    'logoUrl': 'https://xstocks-metadata.backed.fi/logos/tokens/AAPLx.png',
    'priceUsd': 333.73,
    'changePercent24h': -0.26,
  },
  ...overrides,
};

Map<String, Object?> cardsPage([List<Object?>? results]) => {
  ...provenance(),
  'sourceUrl': 'https://api.tokens.xyz/v1/assets/search?q=apple',
  'query': 'apple',
  'limit': 5,
  'completeCatalog': false,
  'results': results ?? [card()],
};

Map<String, Object?> facts([Map<String, Object?> overrides = const {}]) => {
  ...provenance(),
  'sourceUrls': ['https://api.tokens.xyz/v1/assets/apple'],
  'assetId': 'apple',
  'name': 'Apple',
  'symbol': 'AAPL',
  'imageUrl': 'https://api.tokens.xyz/logos/xstocks/AAPLx.png',
  'description': 'Apple designs phones and computers.',
  'stock': {
    'priceUsd': 334.79,
    'changePercent24h': -0.6557,
    'asOfUnixSeconds': 1789768429,
  },
  'sparkline': {
    'interval': '4H',
    'fromUnixSeconds': 1789300000,
    'toUnixSeconds': 1789904800,
    'points': [
      {'unixSeconds': 1789315200, 'close': 331.2},
      {'unixSeconds': 1789329600, 'close': 333.0},
    ],
  },
  'sparklineStatus': 'observed',
  ...overrides,
};

void main() {
  test('cards page parses change, logo and session facts exactly', () {
    final page = StockCardsPage.fromJson(cardsPage());
    expect(page.query, 'apple');
    expect(page.limit, 5);
    expect(page.refreshAfter, DateTime.utc(2026, 9, 20, 15, 1));
    final row = page.results.single;
    expect(row.assetId, 'apple');
    expect(row.changePercent, closeTo(-0.6557, 1e-9));
    expect(row.logoUrl, 'https://api.tokens.xyz/logos/xstocks/AAPLx.png');
    expect(row.stock!.asOf, DateTime.utc(2026, 9, 18, 21, 53, 49));
    expect(row.primaryVariant!.mint, _mint);
  });

  test('missing facts stay null and the token change is a fallback only', () {
    final row = StockCardFacts.fromJson(
      card({'imageUrl': null, 'stock': null}),
    );
    expect(row.imageUrl, isNull);
    expect(row.stock, isNull);
    expect(row.changePercent, closeTo(-0.26, 1e-9));
    expect(
      row.logoUrl,
      'https://xstocks-metadata.backed.fi/logos/tokens/AAPLx.png',
    );
    final bare = StockCardFacts.fromJson(
      card({
        'name': null,
        'symbol': null,
        'imageUrl': null,
        'stock': null,
        'primaryVariant': null,
      }),
    );
    expect(bare.changePercent, isNull);
    expect(bare.logoUrl, isNull);
  });

  test('untrusted image hosts and unsafe urls are dropped, not shown', () {
    for (final url in [
      'https://evil.example/logo.png',
      'http://api.tokens.xyz/logos/x.png',
      'https://api.tokens.xyz/logos/x.png?size=1',
      'https://user:pw@api.tokens.xyz/logos/x.png',
    ]) {
      expect(StockCardFacts.fromJson(card({'imageUrl': url})).imageUrl, isNull);
    }
  });

  test(
    'cards page rejects extra keys, bad numbers, bad mints and overflow',
    () {
      for (final payload in [
        cardsPage()..['extra'] = 1,
        cardsPage()..['completeCatalog'] = true,
        cardsPage()..['executionEnabled'] = true,
        cardsPage([
          card({
            'stock': {
              'priceUsd': -1,
              'changePercent24h': 0,
              'asOfUnixSeconds': 1,
            },
          }),
        ]),
        cardsPage([
          card({
            'stock': {
              'priceUsd': 1,
              'changePercent24h': 'down',
              'asOfUnixSeconds': 1,
            },
          }),
        ]),
        cardsPage([
          card({
            'primaryVariant': {
              'mint': 'not-a-mint',
              'symbol': null,
              'logoUrl': null,
              'priceUsd': null,
              'changePercent24h': null,
            },
          }),
        ]),
        cardsPage([card(), card()]),
        cardsPage(List.filled(6, card())),
        cardsPage([
          card({'assetId': 'Bad Id'}),
        ]),
      ]) {
        expect(
          () => StockCardsPage.fromJson(payload),
          throwsA(isA<StockFactsException>()),
          reason: payload.toString(),
        );
      }
    },
  );

  test('facts parse the description and an ordered sparkline', () {
    final parsed = StockFacts.fromJson(facts());
    expect(parsed.description, 'Apple designs phones and computers.');
    expect(parsed.closes, [331.2, 333.0]);
    expect(parsed.sparklineStatus, StockSparklineStatus.observed);
    expect(parsed.stock!.changePercent24h, closeTo(-0.6557, 1e-9));
    final empty = StockFacts.fromJson(
      facts({'sparkline': null, 'sparklineStatus': 'empty'}),
    );
    expect(empty.sparkline, isEmpty);
    expect(empty.sparklineStatus, StockSparklineStatus.empty);
  });

  test(
    'facts reject a status that disagrees with the sparkline and bad points',
    () {
      for (final payload in [
        facts({'sparklineStatus': 'empty'}),
        facts({'sparkline': null, 'sparklineStatus': 'observed'}),
        facts({'sparklineStatus': 'partial'}),
        facts({
          'sparkline': {
            'interval': '1D',
            'fromUnixSeconds': 1789300000,
            'toUnixSeconds': 1789904800,
            'points': [
              {'unixSeconds': 1789315200, 'close': 1},
            ],
          },
        }),
        facts({
          'sparkline': {
            'interval': '4H',
            'fromUnixSeconds': 1789300000,
            'toUnixSeconds': 1789904800,
            'points': [
              {'unixSeconds': 1789329600, 'close': 1},
              {'unixSeconds': 1789315200, 'close': 2},
            ],
          },
        }),
        facts({'description': 'x' * 401}),
        facts({'sourceUrls': <String>[]}),
      ]) {
        expect(
          () => StockFacts.fromJson(payload),
          throwsA(isA<StockFactsException>()),
          reason: payload.toString(),
        );
      }
    },
  );
}
