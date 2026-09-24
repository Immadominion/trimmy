import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/account/guest_session.dart';
import 'package:trimmy/product/career/career.dart';

const _mutation = '33333333-3333-4333-8333-333333333333';

void main() {
  test('bind exposes only a confirmed server mission board', () async {
    final controller = CareerMissionsController();
    addTearDown(controller.dispose);
    final repository = _CareerRepository()..boards.add(_board(2));

    await controller.bind(principalKey: 'guest:one', repository: repository);

    expect(controller.loading, isFalse);
    expect(controller.board?.revision, 2);
    expect(controller.board?.missions[1].status, CareerMissionStatus.ready);
    expect(controller.failure, isNull);
    expect(controller.stale, isFalse);
  });

  test('a previous principal late mission response is discarded', () async {
    final controller = CareerMissionsController();
    addTearDown(controller.dispose);
    final oldResult = Completer<CareerMissionBoard>();
    final oldRepository = _CareerRepository()..boards.add(oldResult.future);
    final currentRepository = _CareerRepository()..boards.add(_board(7));

    final oldBind = controller.bind(
      principalKey: 'account:old',
      repository: oldRepository,
    );
    await controller.bind(
      principalKey: 'account:current',
      repository: currentRepository,
    );
    oldResult.complete(_board(999));
    await oldBind;

    expect(controller.principalKey, 'account:current');
    expect(controller.board?.revision, 7);
  });

  test('a failed refresh preserves the confirmed board as stale', () async {
    final controller = CareerMissionsController();
    addTearDown(controller.dispose);
    final failedRefresh = Completer<CareerMissionBoard>();
    final repository = _CareerRepository()
      ..boards.add(_board(2))
      ..boards.add(failedRefresh.future);

    await controller.bind(principalKey: 'guest:one', repository: repository);
    final refresh = controller.refresh();
    failedRefresh.completeError(const CareerException(CareerFailure.offline));
    await refresh;

    expect(controller.board?.revision, 2);
    expect(controller.failure, CareerFailure.offline);
    expect(controller.stale, isTrue);
  });

  test(
    'promotion saves one receipt then refreshes the mission board',
    () async {
      final controller = CareerMissionsController();
      addTearDown(controller.dispose);
      final repository = _CareerRepository()
        ..boards.add(_board(2))
        ..boards.add(_board(18, currentRank: CareerRank.analyst))
        ..promotions.add(_promotion());
      await controller.bind(
        principalKey: 'account:one',
        repository: repository,
      );
      final command = CareerPromotionCommand(
        mutationId: _mutation,
        targetRank: CareerRank.analyst,
      );

      final receipt = await controller.promote(command);

      expect(receipt?.careerRevision, 18);
      expect(controller.lastPromotion, same(receipt));
      expect(controller.board?.currentRank, CareerRank.analyst);
      expect(controller.board?.revision, 18);
      expect(controller.promoting, isFalse);
      expect(controller.failure, isNull);
      expect(repository.writes, [command]);
      expect(repository.reads, 2);
    },
  );

  test('the same in-flight idempotent promotion is coalesced', () async {
    final controller = CareerMissionsController();
    addTearDown(controller.dispose);
    final pending = Completer<CareerPromotionReceipt>();
    final repository = _CareerRepository()
      ..boards.add(_board(2))
      ..boards.add(_board(18, currentRank: CareerRank.analyst))
      ..promotions.add(pending.future);
    await controller.bind(principalKey: 'account:one', repository: repository);
    final command = CareerPromotionCommand(
      mutationId: _mutation,
      targetRank: CareerRank.analyst,
    );

    final first = controller.promote(command);
    final second = controller.promote(
      CareerPromotionCommand(
        mutationId: _mutation,
        targetRank: CareerRank.analyst,
      ),
    );

    expect(identical(first, second), isTrue);
    expect(repository.writes, hasLength(1));
    pending.complete(_promotion());
    expect(await first, isNotNull);
    expect(await second, isNotNull);
  });

  test(
    'a synchronous listener cannot start a second promotion write',
    () async {
      final controller = CareerMissionsController();
      addTearDown(controller.dispose);
      final pending = Completer<CareerPromotionReceipt>();
      final repository = _CareerRepository()
        ..boards.add(_board(2))
        ..boards.add(_board(18, currentRank: CareerRank.analyst))
        ..promotions.add(pending.future);
      await controller.bind(
        principalKey: 'account:one',
        repository: repository,
      );
      final command = CareerPromotionCommand(
        mutationId: _mutation,
        targetRank: CareerRank.analyst,
      );
      Future<CareerPromotionReceipt?>? reentered;
      var attempted = false;
      controller.addListener(() {
        if (controller.promoting && !attempted) {
          attempted = true;
          reentered = controller.promote(command);
        }
      });

      final first = controller.promote(command);
      await Future<void>.delayed(Duration.zero);

      expect(reentered, same(first));
      expect(repository.writes, hasLength(1));
      pending.complete(_promotion());
      expect(await first, isNotNull);
      expect(await reentered, isNotNull);
    },
  );

  test('a completion listener still observes the active promotion', () async {
    final controller = CareerMissionsController();
    addTearDown(controller.dispose);
    final pending = Completer<CareerPromotionReceipt>();
    final repository = _CareerRepository()
      ..boards.add(_board(2))
      ..boards.add(_board(18, currentRank: CareerRank.analyst))
      ..promotions.add(pending.future);
    await controller.bind(principalKey: 'account:one', repository: repository);
    final command = CareerPromotionCommand(
      mutationId: _mutation,
      targetRank: CareerRank.analyst,
    );
    Future<CareerPromotionReceipt?>? reentered;
    var observedStart = false;
    var attempted = false;
    controller.addListener(() {
      if (controller.promoting) observedStart = true;
      if (observedStart && !controller.promoting && !attempted) {
        attempted = true;
        reentered = controller.promote(command);
      }
    });

    final first = controller.promote(command);
    pending.complete(_promotion());
    final receipt = await first;

    expect(reentered, same(first));
    expect(await reentered, same(receipt));
    expect(repository.writes, hasLength(1));
  });

  test('a late promotion receipt cannot cross an identity switch', () async {
    final controller = CareerMissionsController();
    addTearDown(controller.dispose);
    final pending = Completer<CareerPromotionReceipt>();
    final oldRepository = _CareerRepository()
      ..boards.add(_board(2))
      ..promotions.add(pending.future);
    final currentRepository = _CareerRepository()..boards.add(_board(9));
    await controller.bind(
      principalKey: 'account:old',
      repository: oldRepository,
    );

    final oldPromotion = controller.promote(
      CareerPromotionCommand(
        mutationId: _mutation,
        targetRank: CareerRank.analyst,
      ),
    );
    await controller.bind(
      principalKey: 'account:current',
      repository: currentRepository,
    );
    pending.complete(_promotion());

    expect(await oldPromotion, isNull);
    expect(controller.principalKey, 'account:current');
    expect(controller.board?.revision, 9);
    expect(controller.lastPromotion, isNull);
  });

  test('terminal guest promotion failure remains distinct', () async {
    final controller = CareerMissionsController();
    addTearDown(controller.dispose);
    final pending = Completer<CareerPromotionReceipt>();
    final repository = _CareerRepository()
      ..boards.add(_board(2))
      ..promotions.add(pending.future);
    await controller.bind(principalKey: 'guest:one', repository: repository);

    final promotion = controller.promote(
      CareerPromotionCommand(
        mutationId: _mutation,
        targetRank: CareerRank.analyst,
      ),
    );
    pending.completeError(
      const GuestSessionException(GuestSessionFailure.revoked),
    );
    final result = await promotion;

    expect(result, isNull);
    expect(controller.guestSessionFailure, GuestSessionFailure.revoked);
    expect(controller.failure, isNull);
    expect(controller.board?.revision, 2);
  });

  test('unbind prevents a pending board from restoring old state', () async {
    final controller = CareerMissionsController();
    addTearDown(controller.dispose);
    final pending = Completer<CareerMissionBoard>();
    final repository = _CareerRepository()..boards.add(pending.future);

    final bind = controller.bind(
      principalKey: 'guest:one',
      repository: repository,
    );
    controller.unbind();
    pending.complete(_board(2));
    await bind;

    expect(controller.principalKey, isNull);
    expect(controller.board, isNull);
    expect(controller.loading, isFalse);
  });
}

final class _CareerRepository implements CareerRepository {
  final boards = <FutureOr<CareerMissionBoard>>[];
  final promotions = <FutureOr<CareerPromotionReceipt>>[];
  final writes = <CareerPromotionCommand>[];
  var reads = 0;

  @override
  Future<CareerMissionBoard> getMissions() async {
    reads++;
    if (boards.isEmpty) throw StateError('No mission board queued.');
    return boards.removeAt(0);
  }

  @override
  Future<CareerPromotionReceipt> promote(CareerPromotionCommand command) async {
    writes.add(command);
    if (promotions.isEmpty) throw StateError('No promotion queued.');
    return promotions.removeAt(0);
  }

  @override
  Future<CareerSummary> getSummary() => throw UnimplementedError();

  @override
  Future<CareerDayContext> getDayContext() => throw UnimplementedError();

  @override
  Future<CareerDayContextReceipt> putDayContext(CareerDayContextWrite write) =>
      throw UnimplementedError();

  @override
  Future<CareerTradeReasonReceipt> saveTradeReason(CareerTradeReason reason) =>
      throw UnimplementedError();
}

CareerMissionBoard _board(
  int revision, {
  CareerRank currentRank = CareerRank.rookie,
}) => CareerMissionBoard(
  revision: revision,
  currentRank: currentRank,
  missions: [
    CareerMission(
      id: CareerMissionId.firstPaperBuy,
      chapterRank: CareerRank.rookie,
      order: 1,
      kind: CareerMissionKind.action,
      title: 'Buy your first stock',
      instruction: 'Complete one paper buy.',
      trimsReward: 20,
      promotesToRank: null,
      status: CareerMissionStatus.complete,
      completedAt: DateTime.utc(2026, 9, 20, 9),
    ),
    const CareerMission(
      id: CareerMissionId.writeAReason,
      chapterRank: CareerRank.rookie,
      order: 2,
      kind: CareerMissionKind.action,
      title: 'Write your reason',
      instruction: 'Add a reason to a paper buy you still hold.',
      trimsReward: 20,
      promotesToRank: null,
      status: CareerMissionStatus.ready,
      completedAt: null,
    ),
    const CareerMission(
      id: CareerMissionId.holdThroughRedDay,
      chapterRank: CareerRank.rookie,
      order: 3,
      kind: CareerMissionKind.promotion,
      title: 'Hold through a red day',
      instruction: 'Hold a stock through a verified red Wall Street day.',
      trimsReward: 20,
      promotesToRank: CareerRank.analyst,
      status: CareerMissionStatus.locked,
      completedAt: null,
    ),
  ],
);

CareerPromotionReceipt _promotion() => CareerPromotionReceipt(
  mutationId: _mutation,
  fromRank: CareerRank.rookie,
  toRank: CareerRank.analyst,
  careerRevision: 18,
  trimsAwarded: 100,
  promotedAt: DateTime.utc(2026, 9, 20, 12),
);
