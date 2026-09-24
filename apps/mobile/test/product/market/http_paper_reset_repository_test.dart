import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/account/guest_session.dart';
import 'package:trimmy/product/market/market.dart';

const _mutation = '81000000-0000-4000-8000-000000000001';
const _guestToken = 'tg1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'sends the exact reset payload and parses a strict cash-only receipt',
    () async {
      final repository = HttpPaperResetRepository(
        transport: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/v1/account/paper/reset');
          expect(request.headers['authorization'], 'Guest $_guestToken');
          expect(request.headers['accept'], 'application/json');
          expect(request.headers['content-type'], 'application/json');
          expect(jsonDecode(request.body), {
            'schemaVersion': 1,
            'mutationId': _mutation,
            'baseRevision': 3,
            'confirm': 'reset my paper desk',
          });
          return _json(_success());
        }),
        baseUri: Uri.parse('https://api.trimmy.test'),
        authorizationProvider: () async =>
            const GuestPaperAuthorization(_guestToken),
      );

      final result = await repository.reset(
        PaperResetRequest(mutationId: _mutation, baseRevision: 3),
      );

      expect(result.receipt.previousRevision, 3);
      expect(result.receipt.revision, 4);
      expect(result.receipt.resetAt, DateTime.utc(2026, 9, 20, 12));
      expect(result.portfolio.startingCashPaper, '10000');
      expect(result.portfolio.cashPaper, '10000');
      expect(result.portfolio.toSnapshot().positions, isEmpty);
      expect(result.portfolio.toSnapshot().recentOrders, isEmpty);
    },
  );

  test('rejects widened envelopes and incoherent reset revisions', () async {
    final widened = _success()..['extra'] = true;
    await expectLater(
      _repository(widened).reset(_request()),
      throwsA(_failure(PaperResetFailure.unavailable)),
    );

    final wrongRevision = _success();
    (wrongRevision['reset']! as Map<String, Object?>)['revision'] = 5;
    await expectLater(
      _repository(wrongRevision).reset(_request()),
      throwsA(_failure(PaperResetFailure.unavailable)),
    );

    final nonCanonicalTime = _success();
    (nonCanonicalTime['reset']! as Map<String, Object?>)['resetAt'] =
        '2026-09-20T12:00:00Z';
    await expectLater(
      _repository(nonCanonicalTime).reset(_request()),
      throwsA(_failure(PaperResetFailure.unavailable)),
    );
  });

  test('rejects nonempty reset portfolios and mismatched cash', () async {
    final order = _success();
    (order['portfolioAtReset']! as Map<String, Object?>)['recentOrders'] = [
      {'id': 'old'},
    ];
    await expectLater(
      _repository(order).reset(_request()),
      throwsA(_failure(PaperResetFailure.unavailable)),
    );

    final cash = _success();
    (cash['portfolioAtReset']! as Map<String, Object?>)['cashPaperMicros'] =
        '9999999999';
    await expectLater(
      _repository(cash).reset(_request()),
      throwsA(_failure(PaperResetFailure.unavailable)),
    );
  });

  test(
    'malformed success retains and replays the exact durable mutation',
    () async {
      final bodies = <Map<String, dynamic>>[];
      var attempts = 0;
      final repository = HttpPaperResetRepository(
        transport: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          attempts++;
          if (attempts == 1) {
            return http.Response(
              '{',
              200,
              headers: const {'content-type': 'application/json'},
            );
          }
          return _json(_success());
        }),
        baseUri: Uri.parse('https://api.trimmy.test'),
        authorizationProvider: () async =>
            const PrivyPaperAuthorization('safe.token'),
      );
      final preferences = await SharedPreferences.getInstance();
      final controller = PaperResetController(
        principalKey: '71000000-0000-4000-8000-000000000001',
        repository: repository,
        store: PreferencesPaperResetMutationStore(preferences),
        mutationId: () => _mutation,
      );
      await controller.initialize();

      await expectLater(
        controller.submit(baseRevision: 3),
        throwsA(_failure(PaperResetFailure.unavailable)),
      );
      expect(controller.state.hasPendingMutation, isTrue);

      final result = await controller.submit(baseRevision: 99);

      expect(result.receipt.revision, 4);
      expect(bodies, hasLength(2));
      expect(bodies[1], bodies[0]);
      expect(bodies[1]['baseRevision'], 3);
      expect(bodies[1]['mutationId'], _mutation);
    },
  );

  test(
    'maps stale, no-op and rate limit without losing their meaning',
    () async {
      for (final entry in const [
        ('PAPER_PORTFOLIO_CHANGED', 409, PaperResetFailure.staleRevision),
        ('PAPER_RESET_NOT_NEEDED', 409, PaperResetFailure.notNeeded),
        ('GUEST_SESSION_RATE_LIMITED', 429, PaperResetFailure.rateLimited),
      ]) {
        final repository = HttpPaperResetRepository(
          transport: MockClient(
            (_) async => _json({
              'error': {
                'code': entry.$1,
                'message': 'safe',
                'requestId': 'req-1',
              },
            }, status: entry.$2),
          ),
          baseUri: Uri.parse('https://api.trimmy.test'),
          authorizationProvider: () async =>
              const PrivyPaperAuthorization('safe.token'),
        );
        await expectLater(
          repository.reset(_request()),
          throwsA(_failure(entry.$3)),
        );
      }
    },
  );

  test('does not trust a definitive error code on the wrong status', () async {
    final repository = HttpPaperResetRepository(
      transport: MockClient(
        (_) async => _json({
          'error': {
            'code': 'PAPER_INPUT_INVALID',
            'message': 'safe',
            'requestId': 'req-2',
          },
        }, status: 503),
      ),
      baseUri: Uri.parse('https://api.trimmy.test'),
      authorizationProvider: () async =>
          const PrivyPaperAuthorization('safe.token'),
    );

    await expectLater(
      repository.reset(_request()),
      throwsA(_failure(PaperResetFailure.unavailable)),
    );
  });

  test('malformed definitive error retains the durable mutation', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = PreferencesPaperResetMutationStore(preferences);
    final repository = HttpPaperResetRepository(
      transport: MockClient(
        (_) async => _json({
          'error': {
            'code': 'PAPER_PORTFOLIO_CHANGED',
            'message': 'safe',
            'requestId': 'req-3',
            'extra': true,
          },
        }, status: 409),
      ),
      baseUri: Uri.parse('https://api.trimmy.test'),
      authorizationProvider: () async =>
          const PrivyPaperAuthorization('safe.token'),
    );
    final controller = PaperResetController(
      principalKey: '71000000-0000-4000-8000-000000000001',
      repository: repository,
      store: store,
      mutationId: () => _mutation,
    );
    await controller.initialize();

    await expectLater(
      controller.submit(baseRevision: 3),
      throwsA(_failure(PaperResetFailure.unavailable)),
    );

    expect(controller.state.hasPendingMutation, isTrue);
    expect((await store.read(controller.principalKey))?.mutationId, _mutation);
  });

  test(
    'malformed unauthorized response does not claim session expiry',
    () async {
      GuestSessionFailure? observed;
      final repository = HttpPaperResetRepository(
        transport: MockClient(
          (_) async => _json({
            'error': {'code': 'GUEST_SESSION_EXPIRED', 'message': 'expired'},
          }, status: 401),
        ),
        baseUri: Uri.parse('https://api.trimmy.test'),
        authorizationProvider: () async =>
            const GuestPaperAuthorization(_guestToken),
        onGuestSessionFailure: (failure) => observed = failure,
      );

      await expectLater(
        repository.reset(_request()),
        throwsA(_failure(PaperResetFailure.unavailable)),
      );
      expect(observed, isNull);
    },
  );

  test('routes terminal guest failures through account recovery', () async {
    GuestSessionFailure? observed;
    final repository = HttpPaperResetRepository(
      transport: MockClient(
        (_) async => _json({
          'error': {
            'code': 'GUEST_SESSION_EXPIRED',
            'message': 'expired',
            'requestId': 'req-4',
          },
        }, status: 401),
      ),
      baseUri: Uri.parse('https://api.trimmy.test'),
      authorizationProvider: () async =>
          const GuestPaperAuthorization(_guestToken),
      onGuestSessionFailure: (failure) => observed = failure,
    );

    await expectLater(
      repository.reset(_request()),
      throwsA(isA<GuestSessionException>()),
    );
    expect(observed, GuestSessionFailure.expired);
  });
}

HttpPaperResetRepository _repository(Map<String, Object?> body) =>
    HttpPaperResetRepository(
      transport: MockClient((_) async => _json(body)),
      baseUri: Uri.parse('https://api.trimmy.test'),
      authorizationProvider: () async =>
          const PrivyPaperAuthorization('safe.token'),
    );

PaperResetRequest _request() =>
    PaperResetRequest(mutationId: _mutation, baseRevision: 3);

Matcher _failure(PaperResetFailure failure) => isA<PaperResetException>()
    .having((error) => error.failure, 'failure', failure);

Map<String, Object?> _success() => {
  'schemaVersion': 1,
  'mode': 'paper',
  'unit': {'kind': 'paper', 'scaleDigits': 6},
  'reset': {
    'mutationId': _mutation,
    'previousRevision': 3,
    'revision': 4,
    'resetAt': '2026-09-20T12:00:00.000Z',
  },
  'portfolioAtReset': {
    'revision': 4,
    'startingCashPaperMicros': '10000000000',
    'cashPaperMicros': '10000000000',
    'positions': <Object?>[],
    'recentOrders': <Object?>[],
  },
};

http.Response _json(Map<String, Object?> value, {int status = 200}) =>
    http.Response(
      jsonEncode(value),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
