import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/account/guest_session.dart';
import 'package:trimmy/product/career/career.dart';
import 'package:trimmy/product/career/career_activity_week.dart';

const _mutation = '22222222-2222-4222-8222-222222222222';
const _dayMutation = '11111111-1111-4111-8111-111111111111';
const _promotionMutation = '33333333-3333-4333-8333-333333333333';
const _order = '44444444-4444-4444-8444-444444444444';
const _mint = 'XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp';

void main() {
  test(
    'reads sparse activity dates and rejects invented or invalid calendar days',
    () async {
      final data = {
        'serverDate': '2026-09-24',
        'weekStart': '2026-09-21',
        'activeDates': ['2026-09-21', '2026-09-24'],
      };
      final week = await _repository(
        MockClient((request) async {
          expect(request.url.path, '/v1/career/activity-week');
          expect(request.headers['authorization'], 'Bearer safe.token');
          return _json({'schemaVersion': 1, 'activityWeek': data});
        }),
      ).getActivityWeek();
      expect(week.activeDates, {'2026-09-21', '2026-09-24'});
      for (final dates in [
        ['2026-09-25'],
        ['2026-09-20'],
        ['2026-09-21', '2026-09-21'],
        ['2026-09-32'],
      ]) {
        expect(
          () => CareerActivityWeek.fromJson({...data, 'activeDates': dates}),
          throwsA(isA<CareerException>()),
        );
      }
    },
  );

  test('strictly reads the server-owned Career summary', () async {
    final repository = HttpCareerRepository(
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/career/summary');
        expect(
          request.headers['authorization'],
          'Guest tg1_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        );
        return _json({'schemaVersion': 1, 'career': _summary()});
      }),
      baseUri: Uri.parse('https://api.trimmy.test'),
      authorizationProvider: () async => const GuestPaperAuthorization(
        'tg1_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      ),
    );

    final summary = await repository.getSummary();

    expect(summary.revision, 2);
    expect(summary.trims.total, 10);
    expect(summary.rank.id, CareerRank.rookie);
    expect(summary.rank.paperLimit, '10000');
    expect(summary.nextRank?.id, CareerRank.analyst);
    expect(summary.nextRank?.trimsRemaining, 290);
    expect(summary.streak.status, CareerStreakStatus.active);
    expect(summary.streak.lastActiveDate, '2026-09-20');
    expect(summary.careerStarted, isTrue);
    expect(summary.firstConfirmedBuy?.orderId, _order);
    expect(summary.firstConfirmedBuy?.assetId, 'apple');
    expect(summary.firstConfirmedBuy?.variantMint, _mint);
    expect(summary.firstConfirmedBuy?.symbol, 'AAPLx');
    expect(summary.firstConfirmedBuy?.quantityMicros, '1498804');
    expect(summary.firstConfirmedBuy?.displayQuantity, '1.498804');
    expect(
      summary.firstConfirmedBuy?.confirmedAt,
      DateTime.utc(2026, 9, 20, 9),
    );
    expect(summary.updatedAt, DateTime.utc(2026, 9, 20, 10));
  });

  test(
    'strictly reads a Career that has started before its first buy',
    () async {
      final summary = _summary()..['firstConfirmedBuy'] = null;
      final result = await _repository(
        MockClient((_) async => _json({'schemaVersion': 1, 'career': summary})),
      ).getSummary();

      expect(result.careerStarted, isTrue);
      expect(result.firstConfirmedBuy, isNull);
    },
  );

  test('strictly reads a not-started Career without a first buy', () async {
    final summary = _summary()
      ..['revision'] = 0
      ..['trims'] = {'total': 0, 'today': 0, 'thisWeek': 0}
      ..['nextRank'] = {
        'id': 'analyst',
        'label': 'Analyst',
        'threshold': 300,
        'trimsRemaining': 300,
        'promotionRequired': false,
      }
      ..['streak'] = {
        'days': 0,
        'status': 'not-started',
        'lastActiveDate': null,
      }
      ..['careerStarted'] = false
      ..['firstConfirmedBuy'] = null
      ..['updatedAt'] = null;

    final result = await _repository(
      MockClient((_) async => _json({'schemaVersion': 1, 'career': summary})),
    ).getSummary();

    expect(result.revision, 0);
    expect(result.careerStarted, isFalse);
    expect(result.firstConfirmedBuy, isNull);
    expect(result.updatedAt, isNull);
  });

  test('accepts the enforceable 10000 paper limit after promotion', () async {
    final summary = _summary()
      ..['trims'] = {'total': 300, 'today': 10, 'thisWeek': 10}
      ..['rank'] = {
        'id': 'analyst',
        'label': 'Analyst',
        'paperLimit': '10000',
        'threshold': 300,
      }
      ..['nextRank'] = {
        'id': 'trader',
        'label': 'Trader',
        'threshold': 900,
        'trimsRemaining': 600,
        'promotionRequired': false,
      };

    final result = await _repository(
      MockClient((_) async => _json({'schemaVersion': 1, 'career': summary})),
    ).getSummary();

    expect(result.rank.id, CareerRank.analyst);
    expect(result.rank.paperLimit, '10000');
  });

  test('strictly reads an unconfigured server day context', () async {
    final repository = _repository(
      MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/career/day-context');
        expect(request.body, isEmpty);
        return _json({
          'schemaVersion': 1,
          'dayContext': _dayContext(
            revision: 1,
            timeZone: 'UTC',
            configured: false,
            updatedAt: '2026-09-20T10:00:00.000Z',
            nextDayAt: '2026-09-21T00:00:00.000Z',
          ),
        });
      }),
    );

    final context = await repository.getDayContext();

    expect(context.revision, 1);
    expect(context.timeZone, 'UTC');
    expect(context.configured, isFalse);
    expect(context.serverDate, '2026-09-20');
    expect(context.nextDayAt, DateTime.utc(2026, 9, 21));
    expect(context.createdAt, DateTime.utc(2026, 9, 20, 10));
    expect(context.updatedAt, context.createdAt);
  });

  test('puts one exact day-context command and binds its receipt', () async {
    final repository = _repository(
      MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, '/v1/career/day-context');
        expect(jsonDecode(request.body), {
          'schemaVersion': 1,
          'mutationId': _dayMutation,
          'baseRevision': 1,
          'timeZone': 'Africa/Lagos',
        });
        return _json({'schemaVersion': 1, 'dayContext': _dayContext()});
      }),
    );
    final write = CareerDayContextWrite(
      mutationId: _dayMutation.toUpperCase(),
      baseRevision: 1,
      timeZone: 'Africa/Lagos',
    );

    final receipt = await repository.putDayContext(write);

    expect(receipt.mutationId, _dayMutation);
    expect(receipt.baseRevision, 1);
    expect(receipt.timeZone, 'Africa/Lagos');
    expect(receipt.changed, isTrue);
    expect(receipt.dayContext.revision, 2);
    expect(receipt.dayContext.configured, isTrue);
    expect(receipt.dayContext.nextDayAt, DateTime.utc(2026, 9, 20, 23));
  });

  test('accepts a configured same-zone semantic no-op receipt', () async {
    final repository = _repository(
      MockClient(
        (_) async => _json({'schemaVersion': 1, 'dayContext': _dayContext()}),
      ),
    );

    final receipt = await repository.putDayContext(
      CareerDayContextWrite(
        mutationId: _dayMutation,
        baseRevision: 2,
        timeZone: 'Africa/Lagos',
      ),
    );

    expect(receipt.changed, isFalse);
    expect(receipt.dayContext.revision, 2);
  });

  test('rejects malformed and impossible day contexts', () async {
    final invalid = <Map<String, Object?>>[
      _dayContext()..['unexpected'] = true,
      _dayContext()..['timeZone'] = 'WAT',
      _dayContext()..['nextDayAt'] = '2026-09-20T10:00:00.000Z',
      _dayContext()..['configured'] = 'yes',
      _dayContext()..['revision'] = 1,
      _dayContext(
        revision: 2,
        timeZone: 'Africa/Lagos',
        configured: false,
        updatedAt: '2026-09-20T10:00:00.000Z',
        nextDayAt: '2026-09-21T00:00:00.000Z',
      ),
    ];

    for (final dayContext in invalid) {
      await expectLater(
        _repository(
          MockClient(
            (_) async => _json({'schemaVersion': 1, 'dayContext': dayContext}),
          ),
        ).getDayContext(),
        throwsA(_careerFailure(CareerFailure.invalidResponse)),
      );
    }
  });

  test('rejects day-context receipts that cannot prove the write', () async {
    final invalid = <Map<String, Object?>>[
      _dayContext()..['timeZone'] = 'America/New_York',
      _dayContext()..['configured'] = false,
      _dayContext()..['revision'] = 3,
    ];

    for (final dayContext in invalid) {
      await expectLater(
        _repository(
          MockClient(
            (_) async => _json({'schemaVersion': 1, 'dayContext': dayContext}),
          ),
        ).putDayContext(
          CareerDayContextWrite(
            mutationId: _dayMutation,
            baseRevision: 1,
            timeZone: 'Africa/Lagos',
          ),
        ),
        throwsA(_careerFailure(CareerFailure.invalidResponse)),
      );
    }
  });

  test('validates day-context writes before network access', () {
    for (final input in [
      () => CareerDayContextWrite(
        mutationId: 'not-a-uuid',
        baseRevision: 1,
        timeZone: 'Africa/Lagos',
      ),
      () => CareerDayContextWrite(
        mutationId: _dayMutation,
        baseRevision: 0,
        timeZone: 'Africa/Lagos',
      ),
      () => CareerDayContextWrite(
        mutationId: _dayMutation,
        baseRevision: 1,
        timeZone: 'WAT',
      ),
    ]) {
      expect(input, throwsA(_careerFailure(CareerFailure.invalidInput)));
    }
  });

  test('maps day-context conflicts without flattening their meaning', () async {
    for (final entry in const {
      'CAREER_DAY_CONTEXT_REVISION_CONFLICT':
          CareerFailure.dayContextRevisionConflict,
      'CAREER_TIME_ZONE_CHANGE_TOO_SOON': CareerFailure.timeZoneChangeTooSoon,
    }.entries) {
      await expectLater(
        _repository(
          MockClient(
            (_) async => _json({
              'error': {
                'code': entry.key,
                'message': 'Day context conflict.',
                'requestId': 'request-1',
              },
            }, status: 409),
          ),
        ).getDayContext(),
        throwsA(_careerFailure(entry.value)),
      );
    }
  });

  test('posts a typed reason and accepts the contract 201 response', () async {
    final repository = HttpCareerRepository(
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/career/trade-reasons');
        expect(request.headers['authorization'], 'Bearer safe.token');
        expect(jsonDecode(request.body), {
          'schemaVersion': 1,
          'mutationId': _mutation,
          'orderId': _order,
          'note': 'Margins are improving.',
        });
        return _json({'schemaVersion': 1, 'reason': _reason()}, status: 201);
      }),
      baseUri: Uri.parse('https://api.trimmy.test'),
      authorizationProvider: () async =>
          const PrivyPaperAuthorization('safe.token'),
    );

    final receipt = await repository.saveTradeReason(
      CareerTradeReason(
        mutationId: _mutation,
        orderId: _order,
        note: 'Margins are improving.',
      ),
    );

    expect(receipt.orderId, _order);
    expect(receipt.assetId, 'apple');
    expect(receipt.variantMint, _mint);
    expect(receipt.trimsAwarded, 10);
    expect(receipt.dailyAwardNumber, 1);
  });

  test('strictly reads the exact server-authored mission board', () async {
    final repository = _repository(
      MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/career/missions');
        expect(request.headers['authorization'], 'Bearer safe.token');
        return _json(_missionsEnvelope());
      }),
    );

    final board = await repository.getMissions();

    expect(board.revision, 2);
    expect(board.currentRank, CareerRank.rookie);
    expect(board.missions, hasLength(3));
    expect(board.missions[0].id, CareerMissionId.firstPaperBuy);
    expect(board.missions[0].status, CareerMissionStatus.complete);
    expect(board.missions[1].id, CareerMissionId.writeAReason);
    expect(board.missions[1].status, CareerMissionStatus.ready);
    expect(board.missions[2].kind, CareerMissionKind.promotion);
    expect(board.missions[2].promotesToRank, CareerRank.analyst);
    expect(
      () => board.missions.add(board.missions.first),
      throwsUnsupportedError,
    );
  });

  test(
    'posts one idempotent promotion command and verifies its receipt',
    () async {
      final repository = _repository(
        MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/v1/career/promotions');
          expect(jsonDecode(request.body), {
            'schemaVersion': 1,
            'mutationId': _promotionMutation,
            'targetRank': 'analyst',
          });
          return _json({
            'schemaVersion': 1,
            'promotion': _promotion(),
          }, status: 201);
        }),
      );

      final receipt = await repository.promote(
        CareerPromotionCommand(
          mutationId: _promotionMutation.toUpperCase(),
          targetRank: CareerRank.analyst,
        ),
      );

      expect(receipt.mutationId, _promotionMutation);
      expect(receipt.fromRank, CareerRank.rookie);
      expect(receipt.toRank, CareerRank.analyst);
      expect(receipt.careerRevision, 18);
      expect(receipt.trimsAwarded, 100);
      expect(receipt.promotedAt, DateTime.utc(2026, 9, 20, 12));
    },
  );

  test('rejects widened or internally impossible mission boards', () async {
    final widened = _missionsEnvelope();
    (widened['missions']! as List<Object?>)[1] = {
      ...(widened['missions']! as List<Object?>)[1]! as Map<String, Object?>,
      'title': 'Write anything',
    };
    final twoReady = _missionsEnvelope();
    ((twoReady['missions']! as List<Object?>)[2]!
            as Map<String, Object?>)['status'] =
        'ready';
    final skippedCompletion = _missionsEnvelope();
    ((skippedCompletion['missions']! as List<Object?>)[2]!
          as Map<String, Object?>)
      ..['status'] = 'complete'
      ..['completedAt'] = '2026-09-20T11:00:00.000Z';
    final completedWithoutTime = _missionsEnvelope();
    ((completedWithoutTime['missions']! as List<Object?>)[0]!
            as Map<String, Object?>)['completedAt'] =
        null;
    final wrongEmptyRank = _missionsEnvelope();
    (wrongEmptyRank['career']! as Map<String, Object?>)
      ..['revision'] = 0
      ..['currentRank'] = 'analyst';

    for (final envelope in [
      widened,
      twoReady,
      skippedCompletion,
      completedWithoutTime,
      wrongEmptyRank,
    ]) {
      await expectLater(
        _repository(MockClient((_) async => _json(envelope))).getMissions(),
        throwsA(_careerFailure(CareerFailure.invalidResponse)),
      );
    }
  });

  test('rejects a promotion receipt that does not prove the command', () async {
    for (final promotion in [
      _promotion()..['mutationId'] = _mutation,
      _promotion()..['toRank'] = 'trader',
      _promotion()..['trimsAwarded'] = 99,
      _promotion()..['careerRevision'] = 0,
    ]) {
      await expectLater(
        _repository(
          MockClient(
            (_) async => _json({
              'schemaVersion': 1,
              'promotion': promotion,
            }, status: 201),
          ),
        ).promote(
          CareerPromotionCommand(
            mutationId: _promotionMutation,
            targetRank: CareerRank.analyst,
          ),
        ),
        throwsA(_careerFailure(CareerFailure.invalidResponse)),
      );
    }
  });

  test('validates promotion commands before any request is sent', () async {
    var requests = 0;
    final repository = _repository(
      MockClient((_) async {
        requests++;
        return _json({});
      }),
    );

    for (final input in [
      () => CareerPromotionCommand(
        mutationId: 'not-a-uuid',
        targetRank: CareerRank.analyst,
      ),
      () => CareerPromotionCommand(
        mutationId: _promotionMutation,
        targetRank: CareerRank.rookie,
      ),
    ]) {
      expect(input, throwsA(_careerFailure(CareerFailure.invalidInput)));
    }
    expect(requests, 0);
    expect(
      CareerPromotionCommand(
        mutationId: _promotionMutation.toUpperCase(),
        targetRank: CareerRank.analyst,
      ).mutationId,
      _promotionMutation,
    );
    expect(repository, isNotNull);
  });

  test(
    'maps promotion state conflicts without trusting their messages',
    () async {
      for (final entry in const {
        'CAREER_PROMOTION_RANK_MISMATCH': CareerFailure.invalidInput,
        'CAREER_PROMOTION_THRESHOLD_REQUIRED': CareerFailure.rejected,
        'CAREER_PROMOTION_MISSION_REQUIRED': CareerFailure.rejected,
        'CAREER_IDEMPOTENCY_CONFLICT': CareerFailure.idempotencyConflict,
      }.entries) {
        final repository = _repository(
          MockClient(
            (_) async => _json({
              'error': {
                'code': entry.key,
                'message': 'Server-owned failure.',
                'requestId': 'request-1',
              },
            }, status: 409),
          ),
        );
        await expectLater(
          repository.promote(
            CareerPromotionCommand(
              mutationId: _promotionMutation,
              targetRank: CareerRank.analyst,
            ),
          ),
          throwsA(_careerFailure(entry.value)),
        );
      }
    },
  );

  test('rejects a summary whose rank rules were widened or forged', () async {
    final summary = _summary();
    (summary['rank'] as Map<String, Object?>)['paperLimit'] = '999999';
    final repository = _repository(
      MockClient((_) async => _json({'schemaVersion': 1, 'career': summary})),
    );

    await expectLater(
      repository.getSummary(),
      throwsA(_careerFailure(CareerFailure.invalidResponse)),
    );
  });

  test('rejects missing, extra, and partial first-buy shapes', () async {
    final missingSummaryField = _summary()..remove('careerStarted');
    final extraFirstField = _summary();
    (extraFirstField['firstConfirmedBuy'] as Map<String, Object?>)['side'] =
        'buy';
    final partialFirstBuy = _summary();
    (partialFirstBuy['firstConfirmedBuy'] as Map<String, Object?>).remove(
      'symbol',
    );

    for (final summary in [
      missingSummaryField,
      extraFirstField,
      partialFirstBuy,
    ]) {
      await expectLater(
        _repository(
          MockClient(
            (_) async => _json({'schemaVersion': 1, 'career': summary}),
          ),
        ).getSummary(),
        throwsA(_careerFailure(CareerFailure.invalidResponse)),
      );
    }
  });

  test('rejects invalid first confirmed buy fields', () async {
    final invalidFields = <String, Object?>{
      'orderId': 'not-a-uuid',
      'assetId': 'Apple',
      'variantMint': '0sbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp',
      'symbol': ' AAPLx',
      'quantityMicros': '01',
      'confirmedAt': '2026-09-20T09:00:00Z',
    };

    for (final entry in invalidFields.entries) {
      final summary = _summary();
      (summary['firstConfirmedBuy'] as Map<String, Object?>)[entry.key] =
          entry.value;
      await expectLater(
        _repository(
          MockClient(
            (_) async => _json({'schemaVersion': 1, 'career': summary}),
          ),
        ).getSummary(),
        throwsA(_careerFailure(CareerFailure.invalidResponse)),
        reason: entry.key,
      );
    }
  });

  test('rejects every noncanonical positive quantityMicros form', () async {
    for (final quantity in <Object?>[
      '0',
      '00',
      '+1',
      '1.0',
      '1000000000000000',
      1,
    ]) {
      final summary = _summary();
      final firstBuy = Map<String, Object?>.from(
        summary['firstConfirmedBuy']! as Map,
      )..['quantityMicros'] = quantity;
      summary['firstConfirmedBuy'] = firstBuy;
      await expectLater(
        _repository(
          MockClient(
            (_) async => _json({'schemaVersion': 1, 'career': summary}),
          ),
        ).getSummary(),
        throwsA(_careerFailure(CareerFailure.invalidResponse)),
        reason: '$quantity',
      );
    }
  });

  test('rejects impossible Career and first-buy consistency', () async {
    final notStartedWithRevision = _summary()
      ..['careerStarted'] = false
      ..['firstConfirmedBuy'] = null;
    final futureFirstBuy = _summary();
    (futureFirstBuy['firstConfirmedBuy']
            as Map<String, Object?>)['confirmedAt'] =
        '2026-09-20T10:00:00.001Z';

    for (final summary in [notStartedWithRevision, futureFirstBuy]) {
      await expectLater(
        _repository(
          MockClient(
            (_) async => _json({'schemaVersion': 1, 'career': summary}),
          ),
        ).getSummary(),
        throwsA(_careerFailure(CareerFailure.invalidResponse)),
      );
    }
  });

  test('rejects extra response fields and a non-201 reason response', () async {
    var calls = 0;
    final repository = _repository(
      MockClient((_) async {
        calls++;
        if (calls == 1) {
          final summary = _summary()..['wallet'] = 'not allowed';
          return _json({'schemaVersion': 1, 'career': summary});
        }
        return _json({'schemaVersion': 1, 'reason': _reason()});
      }),
    );

    await expectLater(
      repository.getSummary(),
      throwsA(_careerFailure(CareerFailure.invalidResponse)),
    );
    await expectLater(
      repository.saveTradeReason(
        CareerTradeReason(
          mutationId: _mutation,
          orderId: _order,
          note: 'Margins are improving.',
        ),
      ),
      throwsA(_careerFailure(CareerFailure.invalidResponse)),
    );
  });

  test('maps a position conflict without losing its meaning', () async {
    final repository = _repository(
      MockClient(
        (_) async => _json({
          'error': {
            'code': 'CAREER_POSITION_REQUIRED',
            'message': 'Hold this stock before adding a reason.',
            'requestId': 'request-1',
          },
        }, status: 409),
      ),
    );

    await expectLater(
      repository.saveTradeReason(
        CareerTradeReason(
          mutationId: _mutation,
          orderId: _order,
          note: 'Margins are improving.',
        ),
      ),
      throwsA(_careerFailure(CareerFailure.positionRequired)),
    );
  });

  test('preserves terminal guest failures from Career responses', () async {
    for (final entry in const {
      'GUEST_SESSION_EXPIRED': GuestSessionFailure.expired,
      'GUEST_SESSION_REVOKED': GuestSessionFailure.revoked,
    }.entries) {
      final reported = <GuestSessionFailure>[];
      final repository = HttpCareerRepository(
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
        authorizationProvider: () async => const GuestPaperAuthorization(
          'tg1_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        ),
        onGuestSessionFailure: reported.add,
      );

      await expectLater(
        repository.getSummary(),
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

  test(
    'times out a stalled mobile request and stays closed after close',
    () async {
      final pending = Completer<http.Response>();
      final repository = HttpCareerRepository(
        client: MockClient((_) => pending.future),
        baseUri: Uri.parse('https://api.trimmy.test'),
        authorizationProvider: () async =>
            const PrivyPaperAuthorization('safe.token'),
        timeout: const Duration(milliseconds: 5),
      );

      await expectLater(
        repository.getSummary(),
        throwsA(_careerFailure(CareerFailure.timeout)),
      );
      repository.close();
      await expectLater(
        repository.getSummary(),
        throwsA(_careerFailure(CareerFailure.unavailable)),
      );
    },
  );

  test('reason input requires UUIDs and at most 180 Unicode scalars', () {
    expect(
      CareerTradeReason(
        mutationId: _mutation,
        orderId: _order,
        note: List.filled(180, 'é').join(),
      ).note.runes.length,
      180,
    );
    expect(
      () => CareerTradeReason(
        mutationId: _mutation,
        orderId: _order,
        note: List.filled(181, 'é').join(),
      ),
      throwsA(_careerFailure(CareerFailure.invalidInput)),
    );
  });

  test(
    'rejects malformed credentials before sending a Career request',
    () async {
      var requests = 0;
      final repository = HttpCareerRepository(
        client: MockClient((_) async {
          requests++;
          return _json({'schemaVersion': 1, 'career': _summary()});
        }),
        baseUri: Uri.parse('https://api.trimmy.test'),
        authorizationProvider: () async =>
            const GuestPaperAuthorization('safe.token'),
      );

      await expectLater(
        repository.getSummary(),
        throwsA(_careerFailure(CareerFailure.accountRequired)),
      );
      expect(requests, 0);
    },
  );

  test('rejects an ambiguous trailing-dot API origin', () {
    expect(
      () => HttpCareerRepository(
        client: MockClient((_) async => _json({})),
        baseUri: Uri.parse('https://api.trimmy.test.'),
        authorizationProvider: () async =>
            const PrivyPaperAuthorization('safe.token'),
      ),
      throwsA(_careerFailure(CareerFailure.unavailable)),
    );
  });
}

HttpCareerRepository _repository(http.Client client) => HttpCareerRepository(
  client: client,
  baseUri: Uri.parse('https://api.trimmy.test'),
  authorizationProvider: () async =>
      const PrivyPaperAuthorization('safe.token'),
);

Matcher _careerFailure(CareerFailure failure) =>
    isA<CareerException>().having((error) => error.failure, 'failure', failure);

http.Response _json(Object value, {int status = 200}) => http.Response(
  jsonEncode(value),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object?> _summary() => {
  'revision': 2,
  'trims': {'total': 10, 'today': 10, 'thisWeek': 10},
  'rank': {
    'id': 'rookie',
    'label': 'Rookie',
    'paperLimit': '10000',
    'threshold': 0,
  },
  'nextRank': {
    'id': 'analyst',
    'label': 'Analyst',
    'threshold': 300,
    'trimsRemaining': 290,
    'promotionRequired': false,
  },
  'streak': {'days': 1, 'status': 'active', 'lastActiveDate': '2026-09-20'},
  'careerStarted': true,
  'firstConfirmedBuy': {
    'orderId': _order,
    'assetId': 'apple',
    'variantMint': _mint,
    'symbol': 'AAPLx',
    'quantityMicros': '1498804',
    'confirmedAt': '2026-09-20T09:00:00.000Z',
  },
  'serverDate': '2026-09-20',
  'updatedAt': '2026-09-20T10:00:00.000Z',
};

Map<String, Object?> _dayContext({
  int revision = 2,
  String timeZone = 'Africa/Lagos',
  bool configured = true,
  String updatedAt = '2026-09-20T10:00:01.000Z',
  String nextDayAt = '2026-09-20T23:00:00.000Z',
}) => {
  'revision': revision,
  'timeZone': timeZone,
  'configured': configured,
  'serverDate': '2026-09-20',
  'nextDayAt': nextDayAt,
  'createdAt': '2026-09-20T10:00:00.000Z',
  'updatedAt': updatedAt,
};

Map<String, Object?> _reason() => {
  'orderId': _order,
  'assetId': 'apple',
  'variantMint': _mint,
  'note': 'Margins are improving.',
  'trimsAwarded': 10,
  'dailyAwardNumber': 1,
  'savedAt': '2026-09-20T10:00:00.000Z',
};

Map<String, Object?> _missionsEnvelope() => {
  'schemaVersion': 1,
  'career': {'revision': 2, 'currentRank': 'rookie'},
  'missions': <Object?>[
    {
      'id': 'first-paper-buy',
      'chapterRank': 'rookie',
      'order': 1,
      'kind': 'action',
      'title': 'Buy your first stock',
      'instruction': 'Complete one paper buy.',
      'trimsReward': 20,
      'promotesToRank': null,
      'status': 'complete',
      'completedAt': '2026-09-20T09:00:00.000Z',
    },
    {
      'id': 'write-a-reason',
      'chapterRank': 'rookie',
      'order': 2,
      'kind': 'action',
      'title': 'Write your reason',
      'instruction': 'Add a reason to a paper buy you still hold.',
      'trimsReward': 20,
      'promotesToRank': null,
      'status': 'ready',
      'completedAt': null,
    },
    {
      'id': 'hold-through-red-day',
      'chapterRank': 'rookie',
      'order': 3,
      'kind': 'promotion',
      'title': 'Hold through a red day',
      'instruction': 'Hold a stock through a verified red Wall Street day.',
      'trimsReward': 20,
      'promotesToRank': 'analyst',
      'status': 'locked',
      'completedAt': null,
    },
  ],
};

Map<String, Object?> _promotion() => {
  'mutationId': _promotionMutation,
  'fromRank': 'rookie',
  'toRank': 'analyst',
  'careerRevision': 18,
  'trimsAwarded': 100,
  'promotedAt': '2026-09-20T12:00:00.000Z',
};
