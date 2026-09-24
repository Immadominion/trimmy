import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/account/guest_session.dart';
import 'package:trimmy/product/career/career.dart';

void main() {
  test('bind exposes only a confirmed server summary', () async {
    final controller = CareerController();
    addTearDown(controller.dispose);
    final repository = _CareerRepository()..summaries.add(_summary(10));

    await controller.bind(principalKey: 'guest:one', repository: repository);

    expect(controller.loading, isFalse);
    expect(controller.summary?.trims.total, 10);
    expect(controller.failure, isNull);
  });

  test('an old principal late response is discarded', () async {
    final controller = CareerController();
    addTearDown(controller.dispose);
    final oldResult = Completer<CareerSummary>();
    final oldRepository = _CareerRepository()..summaries.add(oldResult.future);
    final currentRepository = _CareerRepository()..summaries.add(_summary(30));

    final oldBind = controller.bind(
      principalKey: 'account:old',
      repository: oldRepository,
    );
    await controller.bind(
      principalKey: 'account:current',
      repository: currentRepository,
    );
    oldResult.complete(_summary(999));
    await oldBind;

    expect(controller.principalKey, 'account:current');
    expect(controller.summary?.trims.total, 30);
  });

  test(
    'a refresh failure preserves the last confirmed summary as stale',
    () async {
      final controller = CareerController();
      addTearDown(controller.dispose);
      final failedRefresh = Completer<CareerSummary>();
      final repository = _CareerRepository()
        ..summaries.add(_summary(20))
        ..summaries.add(failedRefresh.future);

      await controller.bind(principalKey: 'guest:one', repository: repository);
      final refresh = controller.refresh();
      failedRefresh.completeError(const CareerException(CareerFailure.offline));
      await refresh;

      expect(controller.summary?.trims.total, 20);
      expect(controller.failure, CareerFailure.offline);
      expect(controller.stale, isTrue);
      expect(controller.message, contains('offline'));
    },
  );

  test(
    'overlapping refreshes coalesce into one trailing server read',
    () async {
      final controller = CareerController();
      addTearDown(controller.dispose);
      final activeRefresh = Completer<CareerSummary>();
      final trailingRefresh = Completer<CareerSummary>();
      final repository = _CareerRepository()
        ..summaries.add(_summary(10))
        ..summaries.add(activeRefresh.future)
        ..summaries.add(trailingRefresh.future);

      await controller.bind(principalKey: 'guest:one', repository: repository);
      final first = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(repository.reads, 2);
      expect(controller.loading, isTrue);

      await Future.wait([controller.refresh(), controller.refresh()]);
      expect(repository.reads, 2);

      activeRefresh.complete(_summary(20));
      await first;
      await Future<void>.delayed(Duration.zero);
      expect(repository.reads, 3);
      expect(controller.loading, isTrue);

      final settled = Completer<void>();
      void observe() {
        if (!controller.loading && controller.summary?.trims.total == 30) {
          settled.complete();
        }
      }

      controller.addListener(observe);
      addTearDown(() => controller.removeListener(observe));
      trailingRefresh.complete(_summary(30));
      await settled.future;

      expect(repository.reads, 3);
      expect(controller.failure, isNull);
    },
  );

  test('unbind prevents a pending response from restoring old state', () async {
    final controller = CareerController();
    addTearDown(controller.dispose);
    final result = Completer<CareerSummary>();
    final repository = _CareerRepository()..summaries.add(result.future);

    final bind = controller.bind(
      principalKey: 'guest:one',
      repository: repository,
    );
    controller.unbind();
    result.complete(_summary(10));
    await bind;

    expect(controller.principalKey, isNull);
    expect(controller.summary, isNull);
    expect(controller.loading, isFalse);
  });

  test('terminal guest failure stays distinct from Career failure', () async {
    final controller = CareerController();
    addTearDown(controller.dispose);
    final repository = _CareerRepository()
      ..summaries.add(
        Future<CareerSummary>.error(
          const GuestSessionException(GuestSessionFailure.expired),
        ),
      );

    await controller.bind(principalKey: 'guest:one', repository: repository);

    expect(controller.guestSessionFailure, GuestSessionFailure.expired);
    expect(controller.failure, isNull);
    expect(controller.summary, isNull);
  });
}

final class _CareerRepository implements CareerRepository {
  final summaries = <FutureOr<CareerSummary>>[];
  var reads = 0;

  @override
  Future<CareerSummary> getSummary() async {
    reads++;
    if (summaries.isEmpty) throw StateError('No summary queued.');
    return summaries.removeAt(0);
  }

  @override
  Future<CareerDayContext> getDayContext() => throw UnimplementedError();

  @override
  Future<CareerDayContextReceipt> putDayContext(CareerDayContextWrite write) =>
      throw UnimplementedError();

  @override
  Future<CareerMissionBoard> getMissions() => throw UnimplementedError();

  @override
  Future<CareerPromotionReceipt> promote(CareerPromotionCommand command) =>
      throw UnimplementedError();

  @override
  Future<CareerTradeReasonReceipt> saveTradeReason(CareerTradeReason reason) =>
      throw UnimplementedError();
}

CareerSummary _summary(int trims) => CareerSummary(
  revision: trims + 1,
  trims: CareerTrims(total: trims, today: trims, thisWeek: trims),
  rank: const CareerRankProgress(
    id: CareerRank.rookie,
    label: 'Rookie',
    paperLimit: '10000',
    threshold: 0,
  ),
  nextRank: CareerNextRank(
    id: CareerRank.analyst,
    label: 'Analyst',
    threshold: 300,
    trimsRemaining: 300 - trims,
    promotionRequired: false,
  ),
  streak: const CareerStreak(
    days: 1,
    status: CareerStreakStatus.active,
    lastActiveDate: '2026-09-20',
  ),
  careerStarted: true,
  firstConfirmedBuy: null,
  serverDate: '2026-09-20',
  updatedAt: DateTime.utc(2026, 9, 20, 12),
);
