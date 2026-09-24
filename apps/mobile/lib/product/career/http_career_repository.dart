import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../account/guest_session.dart';
import 'career_repository.dart';
import 'career_activity_week.dart';

const _summaryPath = '/v1/career/summary';
const _dayContextPath = '/v1/career/day-context';
const _missionsPath = '/v1/career/missions';
const _reasonPath = '/v1/career/trade-reasons';
const _promotionPath = '/v1/career/promotions';
const _maxResponseBytes = 65536;
const _maxSafeInteger = 9007199254740991;

typedef CareerAuthorizationProvider = Future<PaperAuthorization> Function();

/// Reads and writes only the server-owned Career contract. It never caches a
/// credential or creates local progress when the server cannot answer.
final class HttpCareerRepository
    implements CareerRepository, CareerActivityWeekReader {
  factory HttpCareerRepository({
    required http.Client client,
    required Uri baseUri,
    required CareerAuthorizationProvider authorizationProvider,
    void Function(GuestSessionFailure)? onGuestSessionFailure,
    Duration timeout = const Duration(seconds: 10),
    bool allowLoopbackForTests = false,
  }) {
    if (timeout <= Duration.zero || timeout > const Duration(seconds: 30)) {
      throw const CareerException(CareerFailure.unavailable);
    }
    return HttpCareerRepository._(
      client,
      _origin(baseUri, allowLoopbackForTests),
      authorizationProvider,
      onGuestSessionFailure,
      timeout,
    );
  }

  HttpCareerRepository._(
    this._client,
    this._baseUri,
    this._authorization,
    this._onGuestSessionFailure,
    this._timeout,
  );

  final http.Client _client;
  final Uri _baseUri;
  final CareerAuthorizationProvider _authorization;
  final void Function(GuestSessionFailure)? _onGuestSessionFailure;
  final Duration _timeout;
  bool _closed = false;

  @override
  Future<CareerActivityWeek> getActivityWeek() async {
    final envelope = _object(
      await _request('GET', '/v1/career/activity-week', expectedStatus: 200),
    );
    _keys(envelope, const {'schemaVersion', 'activityWeek'});
    if (envelope['schemaVersion'] != 1) _invalidResponse();
    return CareerActivityWeek.fromJson(envelope['activityWeek']);
  }

  @override
  Future<CareerSummary> getSummary() async {
    final decoded = await _request('GET', _summaryPath, expectedStatus: 200);
    final envelope = _object(decoded);
    _keys(envelope, const {'schemaVersion', 'career'});
    if (envelope['schemaVersion'] != 1) _invalidResponse();
    return _summary(envelope['career']);
  }

  @override
  Future<CareerDayContext> getDayContext() async {
    final decoded = await _request('GET', _dayContextPath, expectedStatus: 200);
    final envelope = _object(decoded);
    _keys(envelope, const {'schemaVersion', 'dayContext'});
    if (envelope['schemaVersion'] != 1) _invalidResponse();
    return _dayContext(envelope['dayContext']);
  }

  @override
  Future<CareerDayContextReceipt> putDayContext(
    CareerDayContextWrite write,
  ) async {
    final decoded = await _request(
      'PUT',
      _dayContextPath,
      expectedStatus: 200,
      body: {
        'schemaVersion': 1,
        'mutationId': write.mutationId,
        'baseRevision': write.baseRevision,
        'timeZone': write.timeZone,
      },
    );
    final envelope = _object(decoded);
    _keys(envelope, const {'schemaVersion', 'dayContext'});
    if (envelope['schemaVersion'] != 1) _invalidResponse();
    final dayContext = _dayContext(envelope['dayContext']);
    if (!dayContext.configured ||
        dayContext.timeZone != write.timeZone ||
        dayContext.revision != write.baseRevision &&
            dayContext.revision != write.baseRevision + 1) {
      _invalidResponse();
    }
    return CareerDayContextReceipt(
      mutationId: write.mutationId,
      baseRevision: write.baseRevision,
      timeZone: write.timeZone,
      dayContext: dayContext,
    );
  }

  @override
  Future<CareerMissionBoard> getMissions() async {
    final decoded = await _request('GET', _missionsPath, expectedStatus: 200);
    final envelope = _object(decoded);
    _keys(envelope, const {'schemaVersion', 'career', 'missions'});
    if (envelope['schemaVersion'] != 1) _invalidResponse();
    return _missionBoard(envelope['career'], envelope['missions']);
  }

  @override
  Future<CareerTradeReasonReceipt> saveTradeReason(
    CareerTradeReason reason,
  ) async {
    final decoded = await _request(
      'POST',
      _reasonPath,
      expectedStatus: 201,
      body: {
        'schemaVersion': 1,
        'mutationId': reason.mutationId,
        'orderId': reason.orderId,
        'note': reason.note,
      },
    );
    final envelope = _object(decoded);
    _keys(envelope, const {'schemaVersion', 'reason'});
    if (envelope['schemaVersion'] != 1) _invalidResponse();
    final receipt = _reasonReceipt(envelope['reason']);
    if (receipt.orderId != reason.orderId || receipt.note != reason.note) {
      _invalidResponse();
    }
    return receipt;
  }

  @override
  Future<CareerPromotionReceipt> promote(CareerPromotionCommand command) async {
    final decoded = await _request(
      'POST',
      _promotionPath,
      expectedStatus: 201,
      body: {
        'schemaVersion': 1,
        'mutationId': command.mutationId,
        'targetRank': _rankValue(command.targetRank),
      },
    );
    final envelope = _object(decoded);
    _keys(envelope, const {'schemaVersion', 'promotion'});
    if (envelope['schemaVersion'] != 1) _invalidResponse();
    final receipt = _promotionReceipt(envelope['promotion']);
    if (receipt.mutationId != command.mutationId ||
        receipt.toRank != command.targetRank) {
      _invalidResponse();
    }
    return receipt;
  }

  void close() => _closed = true;

  Future<Object?> _request(
    String method,
    String path, {
    required int expectedStatus,
    Map<String, Object?>? body,
  }) async {
    if (_closed) throw const CareerException(CareerFailure.unavailable);
    var timedOut = false;
    final abort = Completer<void>();
    StreamIterator<List<int>>? iterator;

    Future<Object?> perform() async {
      PaperAuthorization authorization;
      try {
        authorization = await _authorization();
      } on GuestSessionException catch (error) {
        if (_isTerminalGuestFailure(error.failure)) {
          _onGuestSessionFailure?.call(error.failure);
          rethrow;
        }
        throw const CareerException(CareerFailure.accountRequired);
      } catch (_) {
        throw const CareerException(CareerFailure.accountRequired);
      }
      if (timedOut || _closed) {
        throw const CareerException(CareerFailure.timeout);
      }
      final header = _authorizationHeader(authorization);
      final request =
          http.AbortableRequest(
              method,
              _baseUri.replace(path: path),
              abortTrigger: abort.future,
            )
            ..followRedirects = false
            ..maxRedirects = 0
            ..headers['accept'] = 'application/json'
            ..headers['authorization'] = header;
      if (body != null) {
        final encoded = utf8.encode(jsonEncode(body));
        if (encoded.length > 1024) {
          throw const CareerException(CareerFailure.invalidInput);
        }
        request
          ..headers['content-type'] = 'application/json'
          ..bodyBytes = encoded;
      }
      try {
        final response = await _client.send(request);
        if (timedOut || _closed) {
          await response.stream.listen(null).cancel();
          throw const CareerException(CareerFailure.timeout);
        }
        if (response.isRedirect ||
            response.statusCode >= 300 && response.statusCode < 400) {
          await response.stream.listen(null).cancel();
          throw const CareerException(CareerFailure.invalidResponse);
        }
        if ((response.contentLength ?? 0) > _maxResponseBytes) {
          await response.stream.listen(null).cancel();
          throw const CareerException(CareerFailure.invalidResponse);
        }
        _jsonContentType(response.headers['content-type']);
        final bytes = <int>[];
        iterator = StreamIterator(response.stream);
        while (await iterator!.moveNext()) {
          if (timedOut || _closed) {
            throw const CareerException(CareerFailure.timeout);
          }
          final chunk = iterator!.current;
          if (bytes.length + chunk.length > _maxResponseBytes) {
            throw const CareerException(CareerFailure.invalidResponse);
          }
          bytes.addAll(chunk);
        }
        iterator = null;
        Object? decoded;
        try {
          decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
        } catch (_) {
          _invalidResponse();
        }
        if (response.statusCode != expectedStatus) {
          final terminalGuest = _terminalGuestFailure(decoded);
          if (terminalGuest != null) {
            _onGuestSessionFailure?.call(terminalGuest);
            throw GuestSessionException(terminalGuest);
          }
          throw CareerException(_failure(response.statusCode, decoded));
        }
        return decoded;
      } on GuestSessionException {
        rethrow;
      } on CareerException {
        rethrow;
      } catch (_) {
        if (timedOut) throw const CareerException(CareerFailure.timeout);
        throw const CareerException(CareerFailure.offline);
      }
    }

    try {
      return await perform().timeout(
        _timeout,
        onTimeout: () {
          timedOut = true;
          if (!abort.isCompleted) abort.complete();
          final bodyIterator = iterator;
          if (bodyIterator != null) {
            unawaited(bodyIterator.cancel().catchError((Object _) {}));
          }
          throw const CareerException(CareerFailure.timeout);
        },
      );
    } finally {
      final bodyIterator = iterator;
      if (bodyIterator != null) {
        await bodyIterator.cancel().catchError((Object _) {});
      }
    }
  }
}

CareerSummary _summary(Object? input) {
  final value = _object(input);
  _keys(value, const {
    'revision',
    'trims',
    'rank',
    'nextRank',
    'streak',
    'careerStarted',
    'firstConfirmedBuy',
    'serverDate',
    'updatedAt',
  });
  final trims = _object(value['trims']);
  _keys(trims, const {'total', 'today', 'thisWeek'});
  final rank = _object(value['rank']);
  _keys(rank, const {'id', 'label', 'paperLimit', 'threshold'});
  final streak = _object(value['streak']);
  _keys(streak, const {'days', 'status', 'lastActiveDate'});

  final total = _integer(trims['total']);
  final today = _integer(trims['today']);
  final thisWeek = _integer(trims['thisWeek']);
  final rankId = _rank(rank['id']);
  final rankRule = _rankRules[rankId]!;
  final rankLabel = _text(rank['label'], 40);
  final paperLimit = _decimal(rank['paperLimit']);
  final threshold = _integer(rank['threshold']);
  if (rankLabel != rankRule.label ||
      paperLimit != rankRule.paperLimit ||
      threshold != rankRule.threshold ||
      threshold > total ||
      today > total ||
      thisWeek > total) {
    _invalidResponse();
  }

  final nextRank = _nextRank(value['nextRank'], total, rankRule.next);
  final days = _integer(streak['days']);
  final status = _streakStatus(streak['status']);
  final lastActiveDate = streak['lastActiveDate'] == null
      ? null
      : _date(streak['lastActiveDate']);
  if ((days == 0) != (lastActiveDate == null) ||
      (days == 0) != (status == CareerStreakStatus.notStarted)) {
    _invalidResponse();
  }
  final revision = _integer(value['revision']);
  final updatedAt = value['updatedAt'] == null
      ? null
      : _timestamp(value['updatedAt']);
  final careerStarted = value['careerStarted'];
  if (careerStarted is! bool) _invalidResponse();
  final firstConfirmedBuy = _firstConfirmedBuy(value['firstConfirmedBuy']);
  if ((revision == 0) != (updatedAt == null) ||
      (revision == 0) != !careerStarted ||
      firstConfirmedBuy != null && !careerStarted ||
      firstConfirmedBuy != null &&
          updatedAt != null &&
          firstConfirmedBuy.confirmedAt.isAfter(updatedAt)) {
    _invalidResponse();
  }

  return CareerSummary(
    revision: revision,
    trims: CareerTrims(total: total, today: today, thisWeek: thisWeek),
    rank: CareerRankProgress(
      id: rankId,
      label: rankLabel,
      paperLimit: paperLimit,
      threshold: threshold,
    ),
    nextRank: nextRank,
    streak: CareerStreak(
      days: days,
      status: status,
      lastActiveDate: lastActiveDate,
    ),
    careerStarted: careerStarted,
    firstConfirmedBuy: firstConfirmedBuy,
    serverDate: _date(value['serverDate']),
    updatedAt: updatedAt,
  );
}

CareerDayContext _dayContext(Object? input) {
  final value = _object(input);
  _keys(value, const {
    'revision',
    'timeZone',
    'configured',
    'serverDate',
    'nextDayAt',
    'createdAt',
    'updatedAt',
  });
  final revision = _integer(value['revision'], minimum: 1);
  final timeZone = _timeZone(value['timeZone']);
  final configured = value['configured'];
  if (configured is! bool) _invalidResponse();
  final createdAt = _timestamp(value['createdAt']);
  final updatedAt = _timestamp(value['updatedAt']);
  final nextDayAt = _timestamp(value['nextDayAt']);
  if (updatedAt.isBefore(createdAt) ||
      !nextDayAt.isAfter(updatedAt) ||
      !configured && timeZone != 'UTC' ||
      configured && revision < 2) {
    _invalidResponse();
  }
  return CareerDayContext(
    revision: revision,
    timeZone: timeZone,
    configured: configured,
    serverDate: _date(value['serverDate']),
    nextDayAt: nextDayAt,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

CareerFirstConfirmedBuy? _firstConfirmedBuy(Object? input) {
  if (input == null) return null;
  final value = _object(input);
  _keys(value, const {
    'orderId',
    'assetId',
    'variantMint',
    'symbol',
    'quantityMicros',
    'confirmedAt',
  });
  return CareerFirstConfirmedBuy(
    orderId: _uuid(value['orderId']),
    assetId: _assetId(value['assetId']),
    variantMint: _mint(value['variantMint']),
    symbol: _text(value['symbol'], 30),
    quantityMicros: _positiveIntegerText(value['quantityMicros']),
    confirmedAt: _timestamp(value['confirmedAt']),
  );
}

CareerNextRank? _nextRank(Object? input, int trims, CareerRank? expected) {
  if (input == null) {
    if (expected != null) _invalidResponse();
    return null;
  }
  if (expected == null) _invalidResponse();
  final value = _object(input);
  _keys(value, const {
    'id',
    'label',
    'threshold',
    'trimsRemaining',
    'promotionRequired',
  });
  final id = _rank(value['id']);
  final rule = _rankRules[id]!;
  final label = _text(value['label'], 40);
  final threshold = _integer(value['threshold']);
  final remaining = _integer(value['trimsRemaining']);
  final required = value['promotionRequired'];
  if (id != expected ||
      label != rule.label ||
      threshold != rule.threshold ||
      remaining != (threshold - trims).clamp(0, threshold) ||
      required is! bool ||
      required != (trims >= threshold)) {
    _invalidResponse();
  }
  return CareerNextRank(
    id: id,
    label: label,
    threshold: threshold,
    trimsRemaining: remaining,
    promotionRequired: required,
  );
}

CareerTradeReasonReceipt _reasonReceipt(Object? input) {
  final value = _object(input);
  _keys(value, const {
    'orderId',
    'assetId',
    'variantMint',
    'note',
    'trimsAwarded',
    'dailyAwardNumber',
    'savedAt',
  });
  final trims = _integer(value['trimsAwarded']);
  final awardNumber = value['dailyAwardNumber'] == null
      ? null
      : _integer(value['dailyAwardNumber'], minimum: 1);
  if ((trims == 0) != (awardNumber == null) ||
      trims != 0 && trims != 10 ||
      awardNumber != null && awardNumber > 3) {
    _invalidResponse();
  }
  return CareerTradeReasonReceipt(
    orderId: _uuid(value['orderId']),
    assetId: _assetId(value['assetId']),
    variantMint: _mint(value['variantMint']),
    note: _note(value['note']),
    trimsAwarded: trims,
    dailyAwardNumber: awardNumber,
    savedAt: _timestamp(value['savedAt']),
  );
}

CareerMissionBoard _missionBoard(Object? careerInput, Object? missionsInput) {
  final career = _object(careerInput);
  _keys(career, const {'revision', 'currentRank'});
  final revision = _integer(career['revision']);
  final currentRank = _rank(career['currentRank']);
  if (revision == 0 && currentRank != CareerRank.rookie) _invalidResponse();

  if (missionsInput is! List || missionsInput.length != _missionRules.length) {
    _invalidResponse();
  }
  final missions = <CareerMission>[];
  for (var index = 0; index < missionsInput.length; index++) {
    final mission = _object(missionsInput[index]);
    _keys(mission, const {
      'id',
      'chapterRank',
      'order',
      'kind',
      'title',
      'instruction',
      'trimsReward',
      'promotesToRank',
      'status',
      'completedAt',
    });
    final id = _missionId(mission['id']);
    final rule = _missionRules[id]!;
    final chapterRank = _rank(mission['chapterRank']);
    final order = _integer(mission['order'], minimum: 1);
    final kind = _missionKind(mission['kind']);
    final title = _text(mission['title'], 60);
    final instruction = _text(mission['instruction'], 120);
    final trimsReward = _integer(mission['trimsReward']);
    final promotesToRank = mission['promotesToRank'] == null
        ? null
        : _rank(mission['promotesToRank']);
    final status = _missionStatus(mission['status']);
    final completedAt = mission['completedAt'] == null
        ? null
        : _timestamp(mission['completedAt']);
    if (id != _missionOrder[index] ||
        chapterRank != rule.chapterRank ||
        order != rule.order ||
        kind != rule.kind ||
        title != rule.title ||
        instruction != rule.instruction ||
        trimsReward != 20 ||
        promotesToRank != rule.promotesToRank ||
        (status == CareerMissionStatus.complete) != (completedAt != null)) {
      _invalidResponse();
    }
    missions.add(
      CareerMission(
        id: id,
        chapterRank: chapterRank,
        order: order,
        kind: kind,
        title: title,
        instruction: instruction,
        trimsReward: trimsReward,
        promotesToRank: promotesToRank,
        status: status,
        completedAt: completedAt,
      ),
    );
  }

  if (missions
          .where((mission) => mission.status == CareerMissionStatus.ready)
          .length >
      1) {
    _invalidResponse();
  }
  for (var index = 0; index < missions.length; index++) {
    if (missions[index].status == CareerMissionStatus.complete &&
        missions
            .take(index)
            .any((mission) => mission.status != CareerMissionStatus.complete)) {
      _invalidResponse();
    }
  }
  return CareerMissionBoard(
    revision: revision,
    currentRank: currentRank,
    missions: missions,
  );
}

CareerPromotionReceipt _promotionReceipt(Object? input) {
  final value = _object(input);
  _keys(value, const {
    'mutationId',
    'fromRank',
    'toRank',
    'careerRevision',
    'trimsAwarded',
    'promotedAt',
  });
  final fromRank = _rank(value['fromRank']);
  final toRank = _rank(value['toRank']);
  final fromIndex = CareerRank.values.indexOf(fromRank);
  if (CareerRank.values.indexOf(toRank) != fromIndex + 1) _invalidResponse();
  final trimsAwarded = _integer(value['trimsAwarded']);
  if (trimsAwarded != 100) _invalidResponse();
  return CareerPromotionReceipt(
    mutationId: _uuid(value['mutationId']),
    fromRank: fromRank,
    toRank: toRank,
    careerRevision: _integer(value['careerRevision'], minimum: 1),
    trimsAwarded: trimsAwarded,
    promotedAt: _timestamp(value['promotedAt']),
  );
}

CareerFailure _failure(int status, Object? input) {
  if (status == 408 || status == 504) return CareerFailure.timeout;
  final envelope = _object(input);
  _keys(envelope, const {'error'});
  final error = _object(envelope['error']);
  _keys(error, const {'code', 'message', 'requestId'});
  final code = _text(error['code'], 100);
  _text(error['message'], 1024);
  _text(error['requestId'], 128);
  return switch (code) {
    'CAREER_INVALID_INPUT' || 'INVALID_REQUEST' => CareerFailure.invalidInput,
    'CAREER_UNAUTHENTICATED' ||
    'GUEST_SESSION_EXPIRED' ||
    'GUEST_SESSION_REVOKED' ||
    'GUEST_SESSION_UNAUTHENTICATED' => CareerFailure.accountRequired,
    'CAREER_PROFILE_REQUIRED' => CareerFailure.profileRequired,
    'CAREER_ORDER_NOT_FOUND' => CareerFailure.orderNotFound,
    'CAREER_BUY_ORDER_REQUIRED' => CareerFailure.buyOrderRequired,
    'CAREER_POSITION_REQUIRED' => CareerFailure.positionRequired,
    'CAREER_REASON_EXISTS' => CareerFailure.reasonExists,
    'CAREER_IDEMPOTENCY_CONFLICT' => CareerFailure.idempotencyConflict,
    'CAREER_DAY_CONTEXT_REVISION_CONFLICT' =>
      CareerFailure.dayContextRevisionConflict,
    'CAREER_TIME_ZONE_CHANGE_TOO_SOON' => CareerFailure.timeZoneChangeTooSoon,
    'CAREER_ACCOUNT_NOT_FOUND' => CareerFailure.accountRequired,
    'CAREER_PROMOTION_RANK_MISMATCH' => CareerFailure.invalidInput,
    'CAREER_PROMOTION_THRESHOLD_REQUIRED' ||
    'CAREER_PROMOTION_MISSION_REQUIRED' => CareerFailure.rejected,
    'CAREER_REVISION_EXHAUSTED' => CareerFailure.revisionExhausted,
    'GUEST_SESSION_RATE_LIMITED' => CareerFailure.rateLimited,
    'CAREER_UNAVAILABLE' => CareerFailure.unavailable,
    _ when status == 401 || status == 403 => CareerFailure.accountRequired,
    _ when status == 429 => CareerFailure.rateLimited,
    _ when status >= 500 => CareerFailure.unavailable,
    _ => CareerFailure.rejected,
  };
}

GuestSessionFailure? _terminalGuestFailure(Object? input) {
  String? code;
  if (input case {'error': final Map<String, dynamic> error}) {
    if (error['code'] case final String value) code = value;
  }
  return switch (code) {
    'GUEST_SESSION_EXPIRED' => GuestSessionFailure.expired,
    'GUEST_SESSION_REVOKED' => GuestSessionFailure.revoked,
    _ => null,
  };
}

bool _isTerminalGuestFailure(GuestSessionFailure failure) =>
    failure == GuestSessionFailure.expired ||
    failure == GuestSessionFailure.revoked;

const _rankRules = <CareerRank, _RankRule>{
  CareerRank.rookie: _RankRule('Rookie', '10000', 0, CareerRank.analyst),
  CareerRank.analyst: _RankRule('Analyst', '10000', 300, CareerRank.trader),
  CareerRank.trader: _RankRule('Trader', '10000', 900, CareerRank.seniorTrader),
  CareerRank.seniorTrader: _RankRule(
    'Senior Trader',
    '10000',
    2000,
    CareerRank.partner,
  ),
  CareerRank.partner: _RankRule('Partner', '10000', 4500, CareerRank.legend),
  CareerRank.legend: _RankRule('Legend', '10000', 10000, null),
};

const _missionOrder = <CareerMissionId>[
  CareerMissionId.firstPaperBuy,
  CareerMissionId.writeAReason,
  CareerMissionId.holdThroughRedDay,
];

const _missionRules = <CareerMissionId, _MissionRule>{
  CareerMissionId.firstPaperBuy: _MissionRule(
    chapterRank: CareerRank.rookie,
    order: 1,
    kind: CareerMissionKind.action,
    title: 'Buy your first stock',
    instruction: 'Complete one paper buy.',
    promotesToRank: null,
  ),
  CareerMissionId.writeAReason: _MissionRule(
    chapterRank: CareerRank.rookie,
    order: 2,
    kind: CareerMissionKind.action,
    title: 'Write your reason',
    instruction: 'Add a reason to a paper buy you still hold.',
    promotesToRank: null,
  ),
  CareerMissionId.holdThroughRedDay: _MissionRule(
    chapterRank: CareerRank.rookie,
    order: 3,
    kind: CareerMissionKind.promotion,
    title: 'Hold through a red day',
    instruction: 'Hold a stock through a verified red Wall Street day.',
    promotesToRank: CareerRank.analyst,
  ),
};

final class _RankRule {
  const _RankRule(this.label, this.paperLimit, this.threshold, this.next);
  final String label;
  final String paperLimit;
  final int threshold;
  final CareerRank? next;
}

final class _MissionRule {
  const _MissionRule({
    required this.chapterRank,
    required this.order,
    required this.kind,
    required this.title,
    required this.instruction,
    required this.promotesToRank,
  });

  final CareerRank chapterRank;
  final int order;
  final CareerMissionKind kind;
  final String title;
  final String instruction;
  final CareerRank? promotesToRank;
}

CareerRank _rank(Object? input) => switch (_text(input, 20)) {
  'rookie' => CareerRank.rookie,
  'analyst' => CareerRank.analyst,
  'trader' => CareerRank.trader,
  'senior-trader' => CareerRank.seniorTrader,
  'partner' => CareerRank.partner,
  'legend' => CareerRank.legend,
  _ => _invalidResponse(),
};

CareerStreakStatus _streakStatus(Object? input) => switch (_text(input, 20)) {
  'not-started' => CareerStreakStatus.notStarted,
  'active' => CareerStreakStatus.active,
  'at-risk' => CareerStreakStatus.atRisk,
  'grace' => CareerStreakStatus.grace,
  _ => _invalidResponse(),
};

CareerMissionId _missionId(Object? input) => switch (_text(input, 30)) {
  'first-paper-buy' => CareerMissionId.firstPaperBuy,
  'write-a-reason' => CareerMissionId.writeAReason,
  'hold-through-red-day' => CareerMissionId.holdThroughRedDay,
  _ => _invalidResponse(),
};

CareerMissionKind _missionKind(Object? input) => switch (_text(input, 20)) {
  'action' => CareerMissionKind.action,
  'promotion' => CareerMissionKind.promotion,
  _ => _invalidResponse(),
};

CareerMissionStatus _missionStatus(Object? input) => switch (_text(input, 20)) {
  'locked' => CareerMissionStatus.locked,
  'ready' => CareerMissionStatus.ready,
  'complete' => CareerMissionStatus.complete,
  _ => _invalidResponse(),
};

String _rankValue(CareerRank rank) => switch (rank) {
  CareerRank.rookie => 'rookie',
  CareerRank.analyst => 'analyst',
  CareerRank.trader => 'trader',
  CareerRank.seniorTrader => 'senior-trader',
  CareerRank.partner => 'partner',
  CareerRank.legend => 'legend',
};

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) _invalidResponse();
  return value;
}

void _keys(Map<String, dynamic> value, Set<String> expected) {
  if (value.length != expected.length || !expected.every(value.containsKey)) {
    _invalidResponse();
  }
}

int _integer(Object? value, {int minimum = 0}) {
  if (value is! int || value < minimum || value > _maxSafeInteger) {
    _invalidResponse();
  }
  return value;
}

String _text(Object? value, int maximum) {
  if (value is! String ||
      value.isEmpty ||
      value.length > maximum ||
      value.trim() != value ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    _invalidResponse();
  }
  return value;
}

String _note(Object? value) {
  final text = _text(value, 360);
  if (text.runes.length > 180) _invalidResponse();
  return text;
}

String _uuid(Object? value) {
  final text = _text(value, 36).toLowerCase();
  if (!RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  ).hasMatch(text)) {
    _invalidResponse();
  }
  return text;
}

String _assetId(Object? value) {
  final text = _text(value, 100);
  if (!RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(text)) {
    _invalidResponse();
  }
  return text;
}

String _mint(Object? value) {
  final text = _text(value, 44);
  if (!RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$').hasMatch(text)) {
    _invalidResponse();
  }
  return text;
}

String _timeZone(Object? value) {
  final text = _text(value, 255);
  if (text == 'UTC') return text;
  final segments = text.split('/');
  if (segments.length < 2 ||
      !segments.every(
        (segment) => RegExp(r'^[A-Za-z0-9][A-Za-z0-9._+-]*$').hasMatch(segment),
      )) {
    _invalidResponse();
  }
  return text;
}

String _decimal(Object? value) {
  final text = _text(value, 30);
  if (!RegExp(r'^(?:0|[1-9][0-9]*)(?:\.[0-9]{1,6})?$').hasMatch(text)) {
    _invalidResponse();
  }
  return text;
}

String _positiveIntegerText(Object? value) {
  if (value is! String || !RegExp(r'^[1-9][0-9]{0,14}$').hasMatch(value)) {
    _invalidResponse();
  }
  return value;
}

String _date(Object? value) {
  final text = _text(value, 10);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) _invalidResponse();
  final parsed = DateTime.tryParse('${text}T00:00:00.000Z');
  if (parsed == null || parsed.toIso8601String().substring(0, 10) != text) {
    _invalidResponse();
  }
  return text;
}

DateTime _timestamp(Object? value) {
  final text = _text(value, 24);
  if (!RegExp(
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
  ).hasMatch(text)) {
    _invalidResponse();
  }
  final parsed = DateTime.tryParse(text);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != text) {
    _invalidResponse();
  }
  return parsed;
}

Uri _origin(Uri uri, bool allowLoopbackForTests) {
  final loopback =
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      (uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1');
  if (!uri.hasScheme ||
      uri.host.isEmpty ||
      uri.host.endsWith('.') ||
      uri.userInfo.isNotEmpty ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty ||
      uri.path != '' && uri.path != '/' ||
      uri.scheme != 'https' && !(allowLoopbackForTests && loopback)) {
    throw const CareerException(CareerFailure.unavailable);
  }
  return uri.replace(path: '');
}

String _authorizationHeader(PaperAuthorization value) {
  return switch (value) {
    PrivyPaperAuthorization(:final token) =>
      _validBearer(token) ? 'Bearer $token' : _invalidAuthorization(),
    GuestPaperAuthorization(:final token) =>
      RegExp(r'^tg1_[A-Za-z0-9_-]{43}$').hasMatch(token)
          ? 'Guest $token'
          : _invalidAuthorization(),
  };
}

bool _validBearer(String value) {
  final match = RegExp(r'[A-Za-z0-9\-._~+/]+=*').firstMatch(value);
  return value.isNotEmpty &&
      value.length <= 8192 &&
      match?.start == 0 &&
      match?.end == value.length;
}

Never _invalidAuthorization() =>
    throw const CareerException(CareerFailure.accountRequired);

void _jsonContentType(String? value) {
  final parts = value?.toLowerCase().split(';').map((part) => part.trim());
  if (parts == null ||
      parts.first != 'application/json' ||
      parts
          .skip(1)
          .any(
            (part) => part != 'charset=utf-8' && part != 'charset="utf-8"',
          )) {
    _invalidResponse();
  }
}

Never _invalidResponse() =>
    throw const CareerException(CareerFailure.invalidResponse);
