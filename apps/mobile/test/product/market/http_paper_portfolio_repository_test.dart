import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/account/guest_session.dart';
import 'package:trimmy/product/market/market.dart';

const _mint = 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp';
const _preview = '33333333-3333-4333-8333-333333333333';
const _order = '44444444-4444-4444-8444-444444444444';

void main() {
  test(
    'restores a guest paper desk without treating cost as live value',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/account/paper/portfolio');
        expect(request.headers['authorization'], 'Guest tg1_safe-test-token');
        expect(
          request.headers['accept'],
          'application/vnd.trimmy.paper-portfolio.v2+json',
        );
        return _json(_portfolioEnvelope());
      });
      final repository = HttpPaperPortfolioRepository(
        transport: client,
        baseUri: Uri.parse('https://api.trimmy.test'),
        authorizationProvider: () async =>
            const GuestPaperAuthorization('tg1_safe-test-token'),
      );

      final desk = await repository.read();

      expect(desk.revision, 1);
      expect(desk.startingCashPaper, '10000');
      expect(desk.cashPaper, '9500');
      expect(desk.hasTraded, isTrue);
      expect(desk.positions, hasLength(1));
      expect(desk.positions.single.quantity, '1.5');
      expect(desk.positions.single.costBasisPaper, '500');
      expect(desk.recentOrders.single.pricePaper, '333.333333');
    },
  );

  test('parses a complete v2 exact-mint valuation', () async {
    final repository = HttpPaperPortfolioRepository(
      transport: MockClient(
        (_) async => _json(
          _v2Envelope(),
          contentType: 'application/vnd.trimmy.paper-portfolio.v2+json',
        ),
      ),
      baseUri: Uri.parse('https://api.trimmy.test'),
      authorizationProvider: () async =>
          const PrivyPaperAuthorization('safe.token'),
      now: () => DateTime.utc(2026, 9, 20, 12, 0, 30),
    );

    final desk = await repository.read();
    final valuation = desk.valuation;

    expect(valuation.sourceIncluded, isTrue);
    expect(valuation.status, PaperPortfolioValuationStatus.complete);
    expect(valuation.cashPaper, '9500');
    expect(valuation.knownValuePaper, '10100');
    expect(valuation.totalPaper, '10100');
    expect(valuation.pricedPositionCount, 1);
    expect(valuation.positionFor('apple', _mint)?.marketValuePaper, '600');
    expect(valuation.positionFor('apple', _mint)?.unrealizedGainPaper, '100');
    expect(
      () => valuation.positions.add(
        const PaperPositionValuation.unavailable(
          key: PaperPositionKey(assetId: 'other', variantMint: _mint),
        ),
      ),
      throwsUnsupportedError,
    );
  });

  test(
    'accepts the largest derived value produced by capped operands',
    () async {
      final envelope = _maximumDerivedEnvelope();

      final valuation = (await _v2Repository(envelope).read()).valuation;

      expect(valuation.status, PaperPortfolioValuationStatus.complete);
      expect(valuation.positions.single.marketValuePaper, '999999999999998000');
      expect(
        valuation.positions.single.unrealizedGainPaper,
        '999999999999988000.000001',
      );
      expect(valuation.knownValuePaper, '999999999999998000.000001');
      expect(valuation.totalPaper, '999999999999998000.000001');
    },
  );

  test('rejects 31-digit derived micros', () async {
    final envelope = _maximumDerivedEnvelope();
    final valuation = envelope['valuation']! as Map<String, Object?>;
    final row =
        (valuation['positions']! as List<Object?>).single!
            as Map<String, Object?>;
    row['marketValuePaperMicros'] = '1'.padRight(31, '0');

    await expectLater(
      _v2Repository(envelope).read(),
      throwsA(isA<PaperOrderException>()),
    );
  });

  test('keeps stored ledger micros capped at 15 digits', () async {
    final envelope = _maximumDerivedEnvelope();
    final position =
        (envelope['positions']! as List<Object?>).single!
            as Map<String, Object?>;
    position['quantityMicros'] = '1'.padRight(16, '0');

    await expectLater(
      _v2Repository(envelope).read(),
      throwsA(isA<PaperOrderException>()),
    );
  });

  test('keeps partial value separate from a total', () async {
    final envelope = _v2Envelope();
    final positions = envelope['positions']! as List<Object?>;
    const otherMint = 'So11111111111111111111111111111111111111112';
    positions.add({
      ...(positions.single! as Map<String, Object?>),
      'variantMint': otherMint,
      'symbol': 'AAPLon',
      'quantityMicros': '2000000',
      'costBasisPaperMicros': '100000000',
      'averageCostPricePaperMicros': '50000000',
    });
    envelope['valuation'] = {
      ...(envelope['valuation']! as Map<String, Object?>),
      'status': 'partial',
      'openPositionCount': 2,
      'pricedPositionCount': 1,
      'totalPaperMicros': null,
      'positions': <Object?>[
        ...((envelope['valuation']! as Map<String, Object?>)['positions']!
            as List<Object?>),
        {
          'assetId': 'apple',
          'variantMint': otherMint,
          'status': 'unavailable',
          'pricePaperMicros': null,
          'marketValuePaperMicros': null,
          'unrealizedGainPaperMicros': null,
          'observedAt': null,
          'acceptedAt': null,
          'expiresAt': null,
        },
      ],
    };
    final repository = _v2Repository(envelope);

    final valuation = (await repository.read()).valuation;

    expect(valuation.status, PaperPortfolioValuationStatus.partial);
    expect(valuation.knownValuePaper, '10100');
    expect(valuation.totalPaper, isNull);
    expect(
      valuation.positionFor('apple', otherMint)?.status,
      PaperPositionValuationStatus.unavailable,
    );
  });

  test('an expired v2 row cannot appear current', () async {
    final repository = _v2Repository(
      _v2Envelope(),
      now: DateTime.utc(2026, 9, 20, 12, 1),
    );

    final valuation = (await repository.read()).valuation;

    expect(valuation.status, PaperPortfolioValuationStatus.unavailable);
    expect(valuation.pricedPositionCount, 0);
    expect(valuation.knownValuePaper, '9500');
    expect(valuation.totalPaper, isNull);
  });

  test(
    'rejects inexact v2 arithmetic and arbitrary json media types',
    () async {
      final inexact = _v2Envelope();
      final row =
          ((inexact['valuation']! as Map<String, Object?>)['positions']!
                      as List<Object?>)
                  .single!
              as Map<String, Object?>;
      row['marketValuePaperMicros'] = '600000001';
      await expectLater(
        _v2Repository(inexact).read(),
        throwsA(isA<PaperOrderException>()),
      );

      final wrongMedia = HttpPaperPortfolioRepository(
        transport: MockClient(
          (_) async =>
              _json(_v2Envelope(), contentType: 'application/problem+json'),
        ),
        baseUri: Uri.parse('https://api.trimmy.test'),
        authorizationProvider: () async =>
            const PrivyPaperAuthorization('safe.token'),
        now: () => DateTime.utc(2026, 9, 20, 12, 0, 30),
      );
      await expectLater(wrongMedia.read(), throwsA(isA<PaperOrderException>()));
    },
  );

  test('binds each success schema to its negotiated media type', () async {
    final v2AsJson = HttpPaperPortfolioRepository(
      transport: MockClient((_) async => _json(_v2Envelope())),
      baseUri: Uri.parse('https://api.trimmy.test'),
      authorizationProvider: () async =>
          const PrivyPaperAuthorization('safe.token'),
      now: () => DateTime.utc(2026, 9, 20, 12, 0, 30),
    );
    await expectLater(v2AsJson.read(), throwsA(isA<PaperOrderException>()));

    final v1AsVendor = HttpPaperPortfolioRepository(
      transport: MockClient(
        (_) async => _json(
          _portfolioEnvelope(),
          contentType: 'application/vnd.trimmy.paper-portfolio.v2+json',
        ),
      ),
      baseUri: Uri.parse('https://api.trimmy.test'),
      authorizationProvider: () async =>
          const PrivyPaperAuthorization('safe.token'),
    );
    await expectLater(v1AsVendor.read(), throwsA(isA<PaperOrderException>()));
  });

  test('rejects a non-millisecond valuation timestamp', () async {
    final envelope = _v2Envelope();
    final row =
        ((envelope['valuation']! as Map<String, Object?>)['positions']!
                    as List<Object?>)
                .single!
            as Map<String, Object?>;
    row['observedAt'] = '2026-09-20T12:00:10.000001Z';

    await expectLater(
      _v2Repository(envelope).read(),
      throwsA(isA<PaperOrderException>()),
    );
  });

  test(
    'rejects a response that pretends to include a live valuation',
    () async {
      final envelope = _portfolioEnvelope();
      envelope['valuation'] = {'status': 'live', 'note': 'Trust this number.'};
      final repository = HttpPaperPortfolioRepository(
        transport: MockClient((_) async => _json(envelope)),
        baseUri: Uri.parse('https://api.trimmy.test'),
        authorizationProvider: () async =>
            const PrivyPaperAuthorization('safe.token'),
      );

      await expectLater(
        repository.read(),
        throwsA(
          isA<PaperOrderException>().having(
            (error) => error.failure,
            'failure',
            PaperOrderFailure.rejected,
          ),
        ),
      );
    },
  );

  test(
    'accepts a closed position and two issuer variants of one asset',
    () async {
      final envelope = _portfolioEnvelope();
      final positions = envelope['positions']! as List<Object?>;
      final closed = Map<String, Object?>.from(positions.single! as Map)
        ..['quantityMicros'] = '0'
        ..['costBasisPaperMicros'] = '0'
        ..['averageCostPricePaperMicros'] = '0';
      positions[0] = closed;
      positions.add({
        ...closed,
        'variantMint': 'So11111111111111111111111111111111111111112',
        'symbol': 'AAPLon',
      });
      final repository = HttpPaperPortfolioRepository(
        transport: MockClient((_) async => _json(envelope)),
        baseUri: Uri.parse('https://api.trimmy.test'),
        authorizationProvider: () async =>
            const PrivyPaperAuthorization('safe.token'),
      );

      final desk = await repository.read();
      expect(desk.positions, hasLength(2));
      expect(
        desk.positions.every((position) => position.quantity == '0'),
        isTrue,
      );
      expect(desk.positionFor('apple'), isNull);
      expect(desk.positionFor('apple', variantMint: _mint)?.variantMint, _mint);
    },
  );

  test(
    'accepts the same control-free symbol grammar as the paper domain',
    () async {
      final envelope = _portfolioEnvelope();
      final positions = envelope['positions']! as List<Object?>;
      positions[0] = Map<String, Object?>.from(positions.single! as Map)
        ..['symbol'] = 'BRK/B class';
      final orders = envelope['recentOrders']! as List<Object?>;
      orders[0] = Map<String, Object?>.from(orders.single! as Map)
        ..['symbol'] = 'BRK/B class';
      final repository = HttpPaperPortfolioRepository(
        transport: MockClient((_) async => _json(envelope)),
        baseUri: Uri.parse('https://api.trimmy.test'),
        authorizationProvider: () async =>
            const PrivyPaperAuthorization('safe.token'),
      );

      final desk = await repository.read();
      expect(desk.positions.single.symbol, 'BRK/B class');
      expect(desk.recentOrders.single.symbol, 'BRK/B class');
    },
  );

  test('rejects a duplicate asset and mint position', () async {
    final envelope = _portfolioEnvelope();
    final positions = envelope['positions']! as List<Object?>;
    positions.add(Map<String, Object?>.from(positions.single! as Map));
    final repository = HttpPaperPortfolioRepository(
      transport: MockClient((_) async => _json(envelope)),
      baseUri: Uri.parse('https://api.trimmy.test'),
      authorizationProvider: () async =>
          const PrivyPaperAuthorization('safe.token'),
    );

    await expectLater(repository.read(), throwsA(isA<PaperOrderException>()));
  });

  test('preserves terminal guest failures from a portfolio read', () async {
    for (final entry in const {
      'GUEST_SESSION_EXPIRED': GuestSessionFailure.expired,
      'GUEST_SESSION_REVOKED': GuestSessionFailure.revoked,
    }.entries) {
      final reported = <GuestSessionFailure>[];
      final repository = HttpPaperPortfolioRepository(
        transport: MockClient(
          (_) async => _json({
            'error': {
              'code': entry.key,
              'message': 'This guest session is unavailable.',
              'requestId': 'request-1',
            },
          }, status: 401),
        ),
        baseUri: Uri.parse('https://api.trimmy.test'),
        authorizationProvider: () async =>
            const GuestPaperAuthorization('tg1_safe-test-token'),
        onGuestSessionFailure: reported.add,
      );

      await expectLater(
        repository.read(),
        throwsA(
          isA<GuestSessionException>().having(
            (error) => error.failure,
            'failure',
            entry.value,
          ),
        ),
      );
      expect(reported, [entry.value]);
    }
  });
}

http.Response _json(
  Object value, {
  int status = 200,
  String contentType = 'application/json; charset=utf-8',
}) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': contentType},
);

HttpPaperPortfolioRepository _v2Repository(
  Map<String, dynamic> envelope, {
  DateTime? now,
}) => HttpPaperPortfolioRepository(
  transport: MockClient(
    (_) async => _json(
      envelope,
      contentType: 'application/vnd.trimmy.paper-portfolio.v2+json',
    ),
  ),
  baseUri: Uri.parse('https://api.trimmy.test'),
  authorizationProvider: () async =>
      const PrivyPaperAuthorization('safe.token'),
  now: () => now ?? DateTime.utc(2026, 9, 20, 12, 0, 30),
);

Map<String, dynamic> _v2Envelope() {
  final value = _portfolioEnvelope();
  value['schemaVersion'] = 2;
  value['valuation'] = {
    'status': 'complete',
    'portfolioRevision': 1,
    'openPositionCount': 1,
    'pricedPositionCount': 1,
    'cashPaperMicros': '9500000000',
    'knownValuePaperMicros': '10100000000',
    'totalPaperMicros': '10100000000',
    'positions': <Object?>[
      {
        'assetId': 'apple',
        'variantMint': _mint,
        'status': 'priced',
        'pricePaperMicros': '400000000',
        'marketValuePaperMicros': '600000000',
        'unrealizedGainPaperMicros': '100000000',
        'observedAt': '2026-09-20T12:00:10.000Z',
        'acceptedAt': '2026-09-20T12:00:10.000Z',
        'expiresAt': '2026-09-20T12:01:00.000Z',
      },
    ],
  };
  return value;
}

Map<String, dynamic> _maximumDerivedEnvelope() {
  final value = _v2Envelope();
  value['cashPaperMicros'] = '1';
  final position =
      (value['positions']! as List<Object?>).single! as Map<String, Object?>;
  position
    ..['quantityMicros'] = '999999999999999'
    ..['costBasisPaperMicros'] = '9999999999'
    ..['averageCostPricePaperMicros'] = '10';
  final order =
      (value['recentOrders']! as List<Object?>).single! as Map<String, Object?>;
  order
    ..['pricePaperMicros'] = '10'
    ..['quantityMicros'] = '999999999999999'
    ..['cashDebitPaperMicros'] = '9999999999'
    ..['cashAfterPaperMicros'] = '1'
    ..['positionQuantityAfterMicros'] = '999999999999999'
    ..['positionCostBasisAfterPaperMicros'] = '9999999999';
  value['valuation'] = {
    'status': 'complete',
    'portfolioRevision': 1,
    'openPositionCount': 1,
    'pricedPositionCount': 1,
    'cashPaperMicros': '1',
    'knownValuePaperMicros': '999999999999998000000001',
    'totalPaperMicros': '999999999999998000000001',
    'positions': <Object?>[
      {
        'assetId': 'apple',
        'variantMint': _mint,
        'status': 'priced',
        'pricePaperMicros': '999999999999999',
        'marketValuePaperMicros': '999999999999998000000000',
        'unrealizedGainPaperMicros': '999999999999988000000001',
        'observedAt': '2026-09-20T12:00:10.000Z',
        'acceptedAt': '2026-09-20T12:00:10.000Z',
        'expiresAt': '2026-09-20T12:01:00.000Z',
      },
    ],
  };
  return value;
}

Map<String, dynamic> _portfolioEnvelope() => {
  'schemaVersion': 1,
  'mode': 'paper',
  'unit': {'kind': 'paper', 'scaleDigits': 6},
  'revision': 1,
  'startingCashPaperMicros': '10000000000',
  'cashPaperMicros': '9500000000',
  'openedAt': '2026-09-20T12:00:00.000Z',
  'updatedAt': '2026-09-20T12:00:05.000Z',
  'positions': <Object?>[
    {
      'assetId': 'apple',
      'variantMint': _mint,
      'symbol': 'AAPLx',
      'quantityMicros': '1500000',
      'costBasisPaperMicros': '500000000',
      'averageCostPricePaperMicros': '333333333',
      'realizedGainPaperMicros': '0',
      'lockedGainPaperMicros': '0',
      'updatedAt': '2026-09-20T12:00:05.000Z',
    },
  ],
  'recentOrders': <Object?>[
    {
      'id': _order,
      'previewId': _preview,
      'accountRevision': 1,
      'action': 'buy',
      'assetId': 'apple',
      'variantMint': _mint,
      'symbol': 'AAPLx',
      'pricePaperMicros': '333333333',
      'quantityMicros': '1500000',
      'cashDebitPaperMicros': '500000000',
      'cashCreditPaperMicros': '0',
      'cashAfterPaperMicros': '9500000000',
      'positionQuantityAfterMicros': '1500000',
      'positionCostBasisAfterPaperMicros': '500000000',
      'realizedGainDeltaPaperMicros': '0',
      'lockedGainDeltaPaperMicros': '0',
      'source': {
        'provider': 'tokens-xyz-v1',
        'providerReference': '/v1/assets/apple/variants#apple-xstocks',
        'marketSource': 'market',
        'metricsSource': null,
        'providerTimestamps': {
          'asOf': null,
          'lastFetchedAt': null,
          'lastTradeAt': null,
          'unit': 'not_declared',
        },
        'observedAt': '2026-09-20T12:00:00.000Z',
        'acceptedAt': '2026-09-20T12:00:00.000Z',
      },
      'committedAt': '2026-09-20T12:00:05.000Z',
    },
  ],
  'valuation': {
    'status': 'not_included',
    'note':
        'Position value needs a fresh market read; stored cost basis is not a current price.',
  },
};
