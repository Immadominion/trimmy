import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/practice_sync/http_transport.dart';
import 'package:trimmy/account/guest_session.dart';
import 'package:trimmy/product/market/market.dart';

const _account = '11111111-1111-4111-8111-111111111111';
const _request = '22222222-2222-4222-8222-222222222222';
const _preview = '33333333-3333-4333-8333-333333333333';
const _order = '44444444-4444-4444-8444-444444444444';
const _commit = '55555555-5555-4555-8555-555555555555';
const _reasonMutation = '66666666-6666-4666-8666-666666666666';
const _mint = 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp';

void main() {
  test(
    'maps accepted preview and committed server order without wallet use',
    () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(request.headers['authorization'], 'Bearer safe.token');
        expect(request.headers['content-type'], 'application/json');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (request.url.path.endsWith('/preview')) {
          expect(body, {
            'schemaVersion': 1,
            'requestId': _request,
            'action': 'buy',
            'assetId': 'apple',
            'variantMint': _mint,
            'amount': {'kind': 'paper_amount', 'paperMicros': '500000000'},
          });
          return _json(_previewEnvelope());
        }
        expect(request.url.path, '/v1/account/paper/orders/commit');
        expect(body, {
          'schemaVersion': 1,
          'previewId': _preview,
          'idempotencyKey': _commit,
        });
        return _json(_orderEnvelope());
      });
      final repository = HttpPaperOrderRepository(
        client: client,
        baseUri: Uri.parse('https://api.trimmy.test'),
        accessToken: () async =>
            const PracticeAccessToken(accountId: _account, token: 'safe.token'),
        requestId: () => _request,
      );

      final quote = await repository.quote(
        PaperOrderIntent(
          assetId: 'apple',
          variantMint: _mint,
          side: PaperOrderSide.buy,
          quantityUnit: PaperQuantityUnit.paper,
          quantity: '500',
        ),
      );
      expect(quote.quoteId, _preview);
      expect(quote.unitPricePaper, '333.599333');
      expect(quote.estimatedShares, '1.498804');
      expect(quote.totalPaper, '500');

      final receipt = await repository.submit(
        PaperOrderSubmission(quoteId: quote.quoteId, clientOrderId: _commit),
      );
      expect(receipt.orderId, _order);
      expect(receipt.accountRevision, 1);
      expect(receipt.assetId, 'apple');
      expect(receipt.variantMint, _mint);
      expect(receipt.symbol, 'AAPLx');
      expect(receipt.side, PaperOrderSide.buy);
      expect(receipt.filledPaper, '500');
      expect(receipt.positionShares, '1.498804');
      expect(receipt.positionCostBasisPaper, '500');
      expect(receipt.trimsEarned, 0);
      expect(calls, 2);
    },
  );

  test('maps an unauthenticated response to account required', () async {
    final repository = HttpPaperOrderRepository(
      client: MockClient(
        (_) async => _json({
          'error': {
            'code': 'PAPER_TRADING_UNAUTHENTICATED',
            'message': 'A verified account is required.',
            'requestId': 'request-1',
          },
        }, status: 401),
      ),
      baseUri: Uri.parse('https://api.trimmy.test'),
      accessToken: () async =>
          const PracticeAccessToken(accountId: _account, token: 'safe.token'),
      requestId: () => _request,
    );

    await expectLater(
      repository.quote(
        PaperOrderIntent(
          assetId: 'apple',
          variantMint: _mint,
          side: PaperOrderSide.buy,
          quantityUnit: PaperQuantityUnit.paper,
          quantity: '100',
        ),
      ),
      throwsA(
        isA<PaperOrderException>().having(
          (error) => error.failure,
          'failure',
          PaperOrderFailure.accountRequired,
        ),
      ),
    );
  });

  test('preserves terminal guest failures from paper order requests', () async {
    for (final entry in const {
      'GUEST_SESSION_EXPIRED': GuestSessionFailure.expired,
      'GUEST_SESSION_REVOKED': GuestSessionFailure.revoked,
    }.entries) {
      final reported = <GuestSessionFailure>[];
      final repository = HttpPaperOrderRepository(
        client: MockClient(
          (_) async => _json({
            'error': {
              'code': entry.key,
              'message': 'This guest session is unavailable.',
              'requestId': 'request-1',
            },
          }, status: 401),
        ),
        baseUri: Uri.parse('https://api.trimmy.test'),
        authorization: () async => const GuestPaperAuthorization(
          'tg1_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        ),
        requestId: () => _request,
        onGuestSessionFailure: reported.add,
      );

      await expectLater(
        repository.quote(
          PaperOrderIntent(
            assetId: 'apple',
            variantMint: _mint,
            side: PaperOrderSide.buy,
            quantityUnit: PaperQuantityUnit.paper,
            quantity: '100',
          ),
        ),
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

  test('rejects a response that claims wallet execution', () async {
    final response = _previewEnvelope();
    response['execution'] = {
      'walletUsed': true,
      'transactionBuilt': false,
      'transactionSigned': false,
      'transactionBroadcast': false,
    };
    final repository = HttpPaperOrderRepository(
      client: MockClient((_) async => _json(response)),
      baseUri: Uri.parse('https://api.trimmy.test'),
      accessToken: () async =>
          const PracticeAccessToken(accountId: _account, token: 'safe.token'),
      requestId: () => _request,
    );

    await expectLater(
      repository.quote(
        PaperOrderIntent(
          assetId: 'apple',
          variantMint: _mint,
          side: PaperOrderSide.buy,
          quantityUnit: PaperQuantityUnit.paper,
          quantity: '100',
        ),
      ),
      throwsA(
        isA<PaperOrderException>().having(
          (error) => error.failure,
          'failure',
          PaperOrderFailure.rejected,
        ),
      ),
    );
  });

  test(
    'sends a guest credential through the paper-only authorization port',
    () async {
      final repository = HttpPaperOrderRepository(
        client: MockClient((request) async {
          expect(
            request.headers['authorization'],
            'Guest tg1_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
          );
          return _json(_previewEnvelope());
        }),
        baseUri: Uri.parse('https://api.trimmy.test'),
        authorization: () async => const GuestPaperAuthorization(
          'tg1_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        ),
        requestId: () => _request,
      );
      expect(
        (await repository.quote(
          PaperOrderIntent(
            assetId: 'apple',
            variantMint: _mint,
            side: PaperOrderSide.buy,
            quantityUnit: PaperQuantityUnit.paper,
            quantity: '500',
          ),
        )).quoteId,
        _preview,
      );
    },
  );

  test('saves a written buy reason through the Career 201 contract', () async {
    final repository = HttpPaperOrderRepository(
      client: MockClient((request) async {
        expect(request.url.path, '/v1/career/trade-reasons');
        expect(request.headers['authorization'], 'Bearer safe.token');
        expect(jsonDecode(request.body), {
          'schemaVersion': 1,
          'mutationId': _reasonMutation,
          'orderId': _order,
          'note': 'The services margin is improving.',
        });
        return _json({
          'schemaVersion': 1,
          'reason': {
            'orderId': _order,
            'assetId': 'apple',
            'variantMint': _mint,
            'note': 'The services margin is improving.',
            'trimsAwarded': 10,
            'dailyAwardNumber': 1,
            'savedAt': '2026-09-20T10:00:00.000Z',
          },
        }, status: 201);
      }),
      baseUri: Uri.parse('https://api.trimmy.test'),
      accessToken: () async =>
          const PracticeAccessToken(accountId: _account, token: 'safe.token'),
      requestId: () => _request,
    );

    final receipt = await repository.saveReason(
      PaperOrderReason(
        mutationId: _reasonMutation,
        orderId: _order,
        note: 'The services margin is improving.',
      ),
    );

    expect(receipt.trimsAwarded, 10);
    expect(receipt.dailyAwardNumber, 1);
  });

  test('rejects Trims invented by the paper-order response', () async {
    final order = _orderEnvelope();
    (order['reward'] as Map<String, dynamic>)['trimsAwarded'] = 10;
    final repository = HttpPaperOrderRepository(
      client: MockClient(
        (request) async => request.url.path.endsWith('/preview')
            ? _json(_previewEnvelope())
            : _json(order),
      ),
      baseUri: Uri.parse('https://api.trimmy.test'),
      accessToken: () async =>
          const PracticeAccessToken(accountId: _account, token: 'safe.token'),
      requestId: () => _request,
    );
    final quote = await repository.quote(
      PaperOrderIntent(
        assetId: 'apple',
        variantMint: _mint,
        side: PaperOrderSide.buy,
        quantityUnit: PaperQuantityUnit.paper,
        quantity: '500',
      ),
    );

    await expectLater(
      repository.submit(
        PaperOrderSubmission(quoteId: quote.quoteId, clientOrderId: _commit),
      ),
      throwsA(
        isA<PaperOrderException>().having(
          (error) => error.failure,
          'failure',
          PaperOrderFailure.rejected,
        ),
      ),
    );
  });

  test('rejects a non-integer zero paper-order reward', () async {
    final order = _orderEnvelope();
    (order['reward'] as Map<String, dynamic>)['trimsAwarded'] = 0.0;
    final repository = HttpPaperOrderRepository(
      client: MockClient(
        (request) async => request.url.path.endsWith('/preview')
            ? _json(_previewEnvelope())
            : _json(order),
      ),
      baseUri: Uri.parse('https://api.trimmy.test'),
      accessToken: () async =>
          const PracticeAccessToken(accountId: _account, token: 'safe.token'),
      requestId: () => _request,
    );
    final quote = await repository.quote(
      PaperOrderIntent(
        assetId: 'apple',
        variantMint: _mint,
        side: PaperOrderSide.buy,
        quantityUnit: PaperQuantityUnit.paper,
        quantity: '500',
      ),
    );

    await expectLater(
      repository.submit(
        PaperOrderSubmission(quoteId: quote.quoteId, clientOrderId: _commit),
      ),
      throwsA(
        isA<PaperOrderException>().having(
          (error) => error.failure,
          'failure',
          PaperOrderFailure.rejected,
        ),
      ),
    );
  });
}

http.Response _json(Object value, {int status = 200}) => http.Response(
  jsonEncode(value),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> _previewEnvelope() => {
  'schemaVersion': 1,
  'mode': 'paper',
  'unit': {'kind': 'paper', 'scaleDigits': 6},
  'preview': {
    'id': _preview,
    'requestId': _request,
    'state': 'open',
    'accountRevision': 0,
    'action': 'buy',
    'amount': {'kind': 'paper_amount', 'paperMicros': '500000000'},
    'assetId': 'apple',
    'variantMint': _mint,
    'symbol': 'AAPLx',
    'pricePaperMicros': '333599333',
    'quantityMicros': '1498804',
    'cashDebitPaperMicros': '500000000',
    'cashCreditPaperMicros': '0',
    'cashAfterPaperMicros': '9500000000',
    'positionQuantityAfterMicros': '1498804',
    'positionCostBasisAfterPaperMicros': '500000000',
    'realizedGainDeltaPaperMicros': '0',
    'lockedGainDeltaPaperMicros': '0',
    'source': {
      'provider': 'tokens-xyz-v1',
      'providerReference': '/v1/assets/apple/variants',
      'observedAt': '2026-09-20T00:00:00.000Z',
      'acceptedAt': '2026-09-20T00:00:01.000Z',
      'providerTimestamps': {
        'asOf': null,
        'lastFetchedAt': null,
        'lastTradeAt': null,
        'unit': 'not_declared',
      },
    },
    'expiresAt': '2026-09-20T00:00:30.000Z',
    'committedAt': null,
  },
  'fees': {'paperMicros': '0'},
  'reward': {
    'trimsAwarded': 0,
    'reason': 'Trade completion alone does not award Trims.',
  },
  'execution': {
    'walletUsed': false,
    'transactionBuilt': false,
    'transactionSigned': false,
    'transactionBroadcast': false,
  },
};

Map<String, dynamic> _orderEnvelope() => {
  'schemaVersion': 1,
  'mode': 'paper',
  'unit': {'kind': 'paper', 'scaleDigits': 6},
  'order': {
    'id': _order,
    'previewId': _preview,
    'accountRevision': 1,
    'action': 'buy',
    'assetId': 'apple',
    'variantMint': _mint,
    'symbol': 'AAPLx',
    'pricePaperMicros': '333599333',
    'quantityMicros': '1498804',
    'cashDebitPaperMicros': '500000000',
    'cashCreditPaperMicros': '0',
    'cashAfterPaperMicros': '9500000000',
    'positionQuantityAfterMicros': '1498804',
    'positionCostBasisAfterPaperMicros': '500000000',
    'realizedGainDeltaPaperMicros': '0',
    'lockedGainDeltaPaperMicros': '0',
    'source': {
      'provider': 'tokens-xyz-v1',
      'providerReference': '/v1/assets/apple/variants',
      'observedAt': '2026-09-20T00:00:00.000Z',
      'acceptedAt': '2026-09-20T00:00:01.000Z',
      'providerTimestamps': {
        'asOf': null,
        'lastFetchedAt': null,
        'lastTradeAt': null,
        'unit': 'not_declared',
      },
    },
    'committedAt': '2026-09-20T00:00:05.000Z',
  },
  'fees': {'paperMicros': '0'},
  'reward': {
    'trimsAwarded': 0,
    'reason': 'Trade completion alone does not award Trims.',
  },
  'execution': {
    'walletUsed': false,
    'transactionBuilt': false,
    'transactionSigned': false,
    'transactionBroadcast': false,
  },
};
