import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/account/guest_session.dart';
import 'package:trimmy/product/app/http_product_profile_repository.dart';
import 'package:trimmy/product/app/product_profile_repository.dart';
import 'package:trimmy/product/onboarding/onboarding.dart';

const _mutation = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _profile = OnboardingProfile(
  goal: OnboardingGoal.learn,
  knowledge: TradingKnowledge.basics,
  persona: TraderPersona.oracle,
  dailyGoal: OnboardingDailyGoal.oneMission,
  handle: 'mira_7',
);

void main() {
  test(
    'reads a guest profile without retaining or changing its authority',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/product/profile');
        expect(request.headers['authorization'], 'Guest tg1_safe-profile');
        return _json({'schemaVersion': 1, 'profile': _snapshot()});
      });
      final repository = HttpProductProfileRepository(
        transport: client,
        baseUri: Uri.parse('https://api.trimmy.test'),
        authorizationProvider: () async =>
            const GuestPaperAuthorization('tg1_safe-profile'),
      );

      final result = await repository.read();
      expect(result?.revision, 2);
      expect(result?.onboarding, _profile);
      expect(result?.launchCheckpoint, ProductProfileCheckpoint.firstPosition);
    },
  );

  test('unchosen preferences remain null through the server boundary', () async {
    const partial = OnboardingProfile();
    final response = _snapshot();
    response['onboarding'] = {
      'goal': null,
      'knowledge': null,
      'persona': null,
      'dailyGoal': null,
      'handle': null,
    };
    response['launchCheckpoint'] = 'first-trade';
    response['hasConfirmedPaperTrade'] = false;
    final repository = HttpProductProfileRepository(
      transport: MockClient((request) async {
        expect(
          (jsonDecode(request.body) as Map)['onboarding'],
          response['onboarding'],
        );
        return http.Response(
          jsonEncode({'schemaVersion': 2, 'profile': response}),
          200,
          headers: {
            'content-type':
                'application/vnd.trimmy.product-profile.v2+json; charset=utf-8',
          },
        );
      }),
      baseUri: Uri.parse('https://api.trimmy.test'),
      authorizationProvider: () async =>
          const GuestPaperAuthorization('tg1_safe-profile'),
    );
    final result = await repository.write(
      mutationId: _mutation,
      baseRevision: 0,
      onboarding: partial,
      launchCheckpoint: ProductProfileCheckpoint.firstTrade,
    );
    expect(result.onboarding, partial);
    expect(result.onboarding.handle, isNull);
    expect(result.onboarding.persona, isNull);
  });

  test(
    'v2 reads require independent trade evidence, including skipped desks',
    () async {
      for (final evidence in [false, true, null]) {
        final response = _snapshot()..['launchCheckpoint'] = 'app';
        if (evidence != null) response['hasConfirmedPaperTrade'] = evidence;
        final repository = HttpProductProfileRepository(
          transport: MockClient((request) async {
            expect(
              request.headers['accept'],
              'application/vnd.trimmy.product-profile.v2+json',
            );
            return http.Response(
              jsonEncode({'schemaVersion': 2, 'profile': response}),
              200,
              headers: {
                'content-type':
                    'application/vnd.trimmy.product-profile.v2+json; charset=utf-8',
              },
            );
          }),
          baseUri: Uri.parse('https://api.trimmy.test'),
          authorizationProvider: () async =>
              const GuestPaperAuthorization('tg1_safe-profile'),
        );
        if (evidence == null) {
          await expectLater(
            repository.read(),
            throwsA(isA<ProductProfileException>()),
          );
        } else {
          expect((await repository.read())?.hasConfirmedPaperTrade, evidence);
        }
      }
    },
  );

  test('v2 null profile accepts the deployed vendor JSON content type', () async {
    final repository = HttpProductProfileRepository(
      transport: MockClient(
        (_) async => http.Response(
          '{"schemaVersion":2,"profile":null}',
          200,
          headers: {
            'content-type':
                'application/vnd.trimmy.product-profile.v2+json; charset=utf-8',
          },
        ),
      ),
      baseUri: Uri.parse('https://api.trimmy.test'),
      authorizationProvider: () async =>
          const GuestPaperAuthorization('tg1_safe-profile'),
    );
    expect(await repository.read(), isNull);
  });

  test('a missing profile is an explicit successful read', () async {
    final repository = HttpProductProfileRepository(
      transport: MockClient(
        (_) async => _json({'schemaVersion': 1, 'profile': null}),
      ),
      baseUri: Uri.parse('https://api.trimmy.test'),
      authorizationProvider: () async =>
          const PrivyPaperAuthorization('safe.token'),
    );

    expect(await repository.read(), isNull);
  });

  test('writes the exact versioned checkpoint command', () async {
    final client = MockClient((request) async {
      expect(request.method, 'PUT');
      expect(request.headers['authorization'], 'Bearer safe.token');
      expect(jsonDecode(request.body), {
        'schemaVersion': 2,
        'mutationId': _mutation,
        'baseRevision': 1,
        'onboarding': {
          'goal': 'learn',
          'knowledge': 'basics',
          'persona': 'oracle',
          'dailyGoal': 'one-mission',
          'handle': 'mira_7',
        },
        'launchCheckpoint': 'first-position',
      });
      return _json({'schemaVersion': 1, 'profile': _snapshot()});
    });
    final repository = HttpProductProfileRepository(
      transport: client,
      baseUri: Uri.parse('https://api.trimmy.test'),
      authorizationProvider: () async =>
          const PrivyPaperAuthorization('safe.token'),
    );

    final result = await repository.write(
      mutationId: _mutation,
      baseRevision: 1,
      onboarding: _profile,
      launchCheckpoint: ProductProfileCheckpoint.firstPosition,
    );
    expect(result.revision, 2);
  });

  test('advances launch through the explicit action endpoint', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/product/launch');
      expect(request.headers['authorization'], 'Guest tg1_safe-profile');
      expect(jsonDecode(request.body), {
        'schemaVersion': 2,
        'mutationId': _mutation,
        'baseRevision': 1,
        'action': 'paper-trade-confirmed',
      });
      return _json({'schemaVersion': 1, 'profile': _snapshot()});
    });
    final repository = HttpProductProfileRepository(
      transport: client,
      baseUri: Uri.parse('https://api.trimmy.test'),
      authorizationProvider: () async =>
          const GuestPaperAuthorization('tg1_safe-profile'),
    );

    final result = await repository.advance(
      mutationId: _mutation,
      baseRevision: 1,
      action: ProductLaunchAction.paperTradeConfirmed,
    );

    expect(result.revision, 2);
    expect(result.launchCheckpoint, ProductProfileCheckpoint.firstPosition);
  });

  test('keeps evidence and principal launch failures distinct', () async {
    for (final entry in const {
      'PRODUCT_PROFILE_LAUNCH_EVIDENCE_REQUIRED':
          ProductProfileFailure.notReady,
      'PRODUCT_PROFILE_PRINCIPAL_CONFLICT':
          ProductProfileFailure.principalChanged,
    }.entries) {
      final repository = HttpProductProfileRepository(
        transport: MockClient(
          (_) async => _json({
            'error': {
              'code': entry.key,
              'message': 'Not accepted.',
              'requestId': 'request-1',
            },
          }, status: 409),
        ),
        baseUri: Uri.parse('https://api.trimmy.test'),
        authorizationProvider: () async =>
            const GuestPaperAuthorization('tg1_safe-profile'),
      );

      await expectLater(
        repository.advance(
          mutationId: _mutation,
          baseRevision: 1,
          action: ProductLaunchAction.paperTradeConfirmed,
        ),
        throwsA(
          isA<ProductProfileException>().having(
            (error) => error.failure,
            'failure',
            entry.value,
          ),
        ),
      );
    }
  });

  test('revision conflict carries only a validated current profile', () async {
    final repository = HttpProductProfileRepository(
      transport: MockClient(
        (_) async => _json({
          'error': {
            'code': 'PRODUCT_PROFILE_REVISION_CONFLICT',
            'message': 'Changed.',
            'requestId': 'request-1',
            'currentProfile': _snapshot(),
          },
        }, status: 409),
      ),
      baseUri: Uri.parse('https://api.trimmy.test'),
      authorizationProvider: () async =>
          const PrivyPaperAuthorization('safe.token'),
    );

    await expectLater(
      repository.write(
        mutationId: _mutation,
        baseRevision: 1,
        onboarding: _profile,
        launchCheckpoint: ProductProfileCheckpoint.firstPosition,
      ),
      throwsA(
        isA<ProductProfileException>()
            .having(
              (error) => error.failure,
              'failure',
              ProductProfileFailure.conflict,
            )
            .having(
              (error) => error.currentProfile?.revision,
              'current revision',
              2,
            ),
      ),
    );
  });

  test('future fields and non-JSON responses fail closed', () async {
    final extra = _snapshot()..['future'] = true;
    for (final response in [
      _json({'schemaVersion': 1, 'profile': extra}),
      http.Response('hello', 200, headers: {'content-type': 'text/plain'}),
    ]) {
      final repository = HttpProductProfileRepository(
        transport: MockClient((_) async => response),
        baseUri: Uri.parse('https://api.trimmy.test'),
        authorizationProvider: () async =>
            const PrivyPaperAuthorization('safe.token'),
      );
      await expectLater(
        repository.read(),
        throwsA(
          isA<ProductProfileException>().having(
            (error) => error.failure,
            'failure',
            ProductProfileFailure.rejected,
          ),
        ),
      );
    }
  });

  test(
    'preserves terminal guest failures and reports them to the host',
    () async {
      for (final entry in const {
        'GUEST_SESSION_EXPIRED': GuestSessionFailure.expired,
        'GUEST_SESSION_REVOKED': GuestSessionFailure.revoked,
      }.entries) {
        final reported = <GuestSessionFailure>[];
        final repository = HttpProductProfileRepository(
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
              const GuestPaperAuthorization('tg1_safe-profile'),
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
    },
  );
}

http.Response _json(Object value, {int status = 200}) => http.Response(
  jsonEncode(value),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> _snapshot() => {
  'revision': 2,
  'onboarding': {
    'goal': 'learn',
    'knowledge': 'basics',
    'persona': 'oracle',
    'dailyGoal': 'one-mission',
    'handle': 'mira_7',
  },
  'launchCheckpoint': 'first-position',
  'createdAt': '2026-09-20T12:00:00.000Z',
  'updatedAt': '2026-09-20T12:00:01.000Z',
};
