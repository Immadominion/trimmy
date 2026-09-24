import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/core/device_time_zone.dart';
import 'package:trimmy/product/career/career.dart';

const _mutation = '11111111-1111-4111-8111-111111111111';
const _otherMutation = '22222222-2222-4222-8222-222222222222';

void main() {
  test(
    'configures only a fresh context, persists first, then reads a fresh boundary',
    () async {
      final store = _MutationStore();
      final provider = _TimeZoneProvider('Africa/Lagos');
      final receiptContext = _context(
        configured: true,
        revision: 2,
        nextDayAt: DateTime.utc(2026, 9, 20, 23),
      );
      final refreshedContext = _context(
        configured: true,
        revision: 2,
        nextDayAt: DateTime.utc(2026, 9, 21, 23),
        serverDate: '2026-09-21',
      );
      final repository = _Repository()
        ..reads.add(_context())
        ..reads.add(refreshedContext)
        ..onPut = (write) async {
          expect(store.values['account:one']?.mutationId, write.mutationId);
          return _receipt(write, receiptContext);
        };
      final controller = CareerDayContextController(
        deviceTimeZone: provider,
        mutationStore: store,
        mutationId: () => _mutation,
      );
      addTearDown(controller.dispose);

      final configured = await controller.bind(
        principalKey: 'account:one',
        repository: repository,
      );

      expect(configured, isTrue);
      expect(repository.readCount, 2);
      expect(repository.writes.single.mutationId, _mutation);
      expect(repository.writes.single.baseRevision, 1);
      expect(repository.writes.single.timeZone, 'Africa/Lagos');
      expect(controller.context, same(refreshedContext));
      expect(controller.context?.nextDayAt, DateTime.utc(2026, 9, 21, 23));
      expect(controller.deviceTimeZone, 'Africa/Lagos');
      expect(controller.failure, isNull);
      expect(store.values, isEmpty);
      expect(store.events, [
        'read:account:one',
        'write:account:one:$_mutation',
        'remove:account:one',
      ]);
    },
  );

  test('never changes an already configured server time zone', () async {
    final store = _MutationStore()
      ..values['account:one'] = CareerDayContextWrite(
        mutationId: _mutation,
        baseRevision: 1,
        timeZone: 'Africa/Lagos',
      );
    final provider = _TimeZoneProvider('America/New_York');
    final repository = _Repository()..reads.add(_context(configured: true));
    final controller = CareerDayContextController(
      deviceTimeZone: provider,
      mutationStore: store,
      mutationId: () => _otherMutation,
    );
    addTearDown(controller.dispose);

    expect(
      await controller.bind(
        principalKey: 'account:one',
        repository: repository,
      ),
      isFalse,
    );

    expect(provider.reads, 1);
    expect(controller.deviceTimeZone, 'America/New_York');
    expect(controller.context?.timeZone, 'Africa/Lagos');
    expect(repository.writes, isEmpty);
    expect(store.values, isEmpty);
  });

  test(
    'a missing native time zone does not block the confirmed read',
    () async {
      final repository = _Repository()..reads.add(_context());
      final controller = CareerDayContextController(
        deviceTimeZone: _TimeZoneProvider(null),
        mutationStore: _MutationStore(),
        mutationId: () => _mutation,
      );
      addTearDown(controller.dispose);

      await controller.bind(principalKey: 'guest:one', repository: repository);

      expect(controller.context?.configured, isFalse);
      expect(controller.deviceTimeZone, isNull);
      expect(controller.failure, isNull);
      expect(repository.writes, isEmpty);
    },
  );

  test(
    'a timeout and process restart reuse the persisted mutation ID',
    () async {
      final store = _MutationStore();
      var generated = 0;
      final firstRepository = _Repository()
        ..reads.add(_context())
        ..onPut = (_) => Future<CareerDayContextReceipt>.error(
          const CareerException(CareerFailure.timeout),
        );
      final first = CareerDayContextController(
        deviceTimeZone: _TimeZoneProvider('Africa/Lagos'),
        mutationStore: store,
        mutationId: () {
          generated++;
          return _mutation;
        },
      );

      expect(
        await first.bind(
          principalKey: 'account:one',
          repository: firstRepository,
        ),
        isFalse,
      );
      expect(first.failure, CareerFailure.timeout);
      expect(store.values['account:one']?.mutationId, _mutation);
      first.dispose();

      final configured = _context(configured: true, revision: 2);
      final secondRepository = _Repository()
        ..reads.add(_context())
        ..reads.add(configured)
        ..onPut = (write) => _receipt(write, configured);
      final second = CareerDayContextController(
        deviceTimeZone: _TimeZoneProvider('Africa/Lagos'),
        mutationStore: store,
        mutationId: () {
          generated++;
          return _otherMutation;
        },
      );
      addTearDown(second.dispose);

      expect(
        await second.bind(
          principalKey: 'account:one',
          repository: secondRepository,
        ),
        isTrue,
      );
      expect(firstRepository.writes.single.mutationId, _mutation);
      expect(secondRepository.writes.single.mutationId, _mutation);
      expect(generated, 1);
      expect(store.values, isEmpty);
    },
  );

  test(
    'restart replaces a pending command whose zone no longer matches',
    () async {
      final store = _MutationStore()
        ..values['account:one'] = CareerDayContextWrite(
          mutationId: _mutation,
          baseRevision: 1,
          timeZone: 'Africa/Lagos',
        );
      final configured = _context(
        configured: true,
        revision: 2,
        timeZone: 'America/New_York',
      );
      final repository = _Repository()
        ..reads.add(_context())
        ..reads.add(configured)
        ..onPut = (write) => _receipt(write, configured);
      final controller = CareerDayContextController(
        deviceTimeZone: _TimeZoneProvider('America/New_York'),
        mutationStore: store,
        mutationId: () => _otherMutation,
      );
      addTearDown(controller.dispose);

      expect(
        await controller.bind(
          principalKey: 'account:one',
          repository: repository,
        ),
        isTrue,
      );
      expect(repository.writes.single.mutationId, _otherMutation);
      expect(repository.writes.single.timeZone, 'America/New_York');
    },
  );

  test(
    'restart replaces a pending command whose base revision is stale',
    () async {
      final store = _MutationStore()
        ..values['account:one'] = CareerDayContextWrite(
          mutationId: _mutation,
          baseRevision: 2,
          timeZone: 'Africa/Lagos',
        );
      final configured = _context(configured: true, revision: 2);
      final repository = _Repository()
        ..reads.add(_context())
        ..reads.add(configured)
        ..onPut = (write) => _receipt(write, configured);
      final controller = CareerDayContextController(
        deviceTimeZone: _TimeZoneProvider('Africa/Lagos'),
        mutationStore: store,
        mutationId: () => _otherMutation,
      );
      addTearDown(controller.dispose);

      await controller.bind(
        principalKey: 'account:one',
        repository: repository,
      );

      expect(repository.writes.single.mutationId, _otherMutation);
      expect(repository.writes.single.baseRevision, 1);
    },
  );

  test(
    'SharedPreferences store round-trips the full pending command',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final store = PreferencesCareerDayContextMutationStore(preferences);
      final command = CareerDayContextWrite(
        mutationId: _mutation,
        baseRevision: 1,
        timeZone: 'Africa/Lagos',
      );

      expect(await store.write('account:one', command), isTrue);
      final restored = await PreferencesCareerDayContextMutationStore(
        preferences,
      ).read('account:one');

      expect(restored?.mutationId, command.mutationId);
      expect(restored?.baseRevision, command.baseRevision);
      expect(restored?.timeZone, command.timeZone);
      expect(await store.remove('account:one'), isTrue);
      expect(await store.read('account:one'), isNull);
    },
  );

  test(
    'a lost configuration race reconciles immediately from the server',
    () async {
      final store = _MutationStore();
      final winner = _context(
        configured: true,
        revision: 2,
        timeZone: 'America/New_York',
      );
      final repository = _Repository()
        ..reads.add(_context())
        ..reads.add(winner)
        ..onPut = (_) => Future<CareerDayContextReceipt>.error(
          const CareerException(CareerFailure.dayContextRevisionConflict),
        );
      final controller = CareerDayContextController(
        deviceTimeZone: _TimeZoneProvider('Africa/Lagos'),
        mutationStore: store,
        mutationId: () => _mutation,
      );
      addTearDown(controller.dispose);

      expect(
        await controller.bind(
          principalKey: 'account:one',
          repository: repository,
        ),
        isTrue,
      );

      expect(repository.readCount, 2);
      expect(repository.writes.single.timeZone, 'Africa/Lagos');
      expect(controller.context, same(winner));
      expect(controller.failure, isNull);
      expect(store.values, isEmpty);
    },
  );

  test('refresh delay uses nextDayAt and backs off stale boundaries', () {
    final now = DateTime.utc(2026, 9, 20, 10);

    expect(
      careerDayRefreshDelay(now: now, nextDayAt: DateTime.utc(2026, 9, 20, 23)),
      const Duration(hours: 13, seconds: 2),
    );
    expect(
      careerDayRefreshDelay(now: now, nextDayAt: null),
      const Duration(minutes: 15),
    );
    expect(
      careerDayRefreshDelay(now: now, nextDayAt: DateTime.utc(2026, 9, 20, 9)),
      const Duration(minutes: 15),
    );
  });

  test(
    'a late old-principal read cannot write into the new principal',
    () async {
      final oldRead = Completer<CareerDayContext>();
      final oldRepository = _Repository()..reads.add(oldRead.future);
      final currentContext = _context(
        configured: true,
        revision: 2,
        timeZone: 'America/New_York',
      );
      final currentRepository = _Repository()..reads.add(currentContext);
      final controller = CareerDayContextController(
        deviceTimeZone: _TimeZoneProvider('Africa/Lagos'),
        mutationStore: _MutationStore(),
        mutationId: () => _mutation,
      );
      addTearDown(controller.dispose);

      final oldBind = controller.bind(
        principalKey: 'account:old',
        repository: oldRepository,
      );
      await controller.bind(
        principalKey: 'account:current',
        repository: currentRepository,
      );
      oldRead.complete(_context());
      await oldBind;

      expect(controller.principalKey, 'account:current');
      expect(controller.context, same(currentContext));
      expect(oldRepository.writes, isEmpty);
      expect(currentRepository.writes, isEmpty);
    },
  );

  test('listener reentry at start shares one synchronization Future', () async {
    final read = Completer<CareerDayContext>();
    final repository = _Repository()..reads.add(read.future);
    final controller = CareerDayContextController(
      deviceTimeZone: _TimeZoneProvider('Africa/Lagos'),
      mutationStore: _MutationStore(),
      mutationId: () => _mutation,
    );
    addTearDown(controller.dispose);
    Future<bool>? reentered;
    controller.addListener(() {
      if (controller.loading) reentered ??= controller.synchronize();
    });

    final original = controller.bind(
      principalKey: 'account:one',
      repository: repository,
    );

    expect(reentered, same(original));
    expect(repository.readCount, 1);
    read.complete(_context(configured: true, revision: 2));
    await original;
    expect(repository.readCount, 1);
  });

  test(
    'listener reentry at completion still shares the active Future',
    () async {
      final repository = _Repository()
        ..reads.add(_context(configured: true, revision: 2));
      final controller = CareerDayContextController(
        deviceTimeZone: _TimeZoneProvider('Africa/Lagos'),
        mutationStore: _MutationStore(),
        mutationId: () => _mutation,
      );
      addTearDown(controller.dispose);
      var sawLoading = false;
      Future<bool>? reentered;
      controller.addListener(() {
        if (controller.loading) sawLoading = true;
        if (sawLoading &&
            !controller.loading &&
            controller.context != null &&
            reentered == null) {
          reentered = controller.synchronize();
        }
      });

      final original = controller.bind(
        principalKey: 'account:one',
        repository: repository,
      );
      await original;

      expect(reentered, same(original));
      expect(repository.readCount, 1);
    },
  );
}

final class _TimeZoneProvider implements DeviceTimeZoneProvider {
  _TimeZoneProvider(this.value);
  final String? value;
  var reads = 0;

  @override
  Future<String?> currentIanaTimeZoneId() async {
    reads++;
    return value;
  }
}

final class _MutationStore implements CareerDayContextMutationStore {
  final values = <String, CareerDayContextWrite>{};
  final events = <String>[];

  @override
  Future<CareerDayContextWrite?> read(String principalKey) async {
    events.add('read:$principalKey');
    return values[principalKey];
  }

  @override
  Future<bool> write(String principalKey, CareerDayContextWrite command) async {
    events.add('write:$principalKey:${command.mutationId}');
    values[principalKey] = command;
    return true;
  }

  @override
  Future<bool> remove(String principalKey) async {
    events.add('remove:$principalKey');
    values.remove(principalKey);
    return true;
  }
}

final class _Repository implements CareerRepository {
  final reads = <FutureOr<CareerDayContext>>[];
  final writes = <CareerDayContextWrite>[];
  FutureOr<CareerDayContextReceipt> Function(CareerDayContextWrite)? onPut;
  var readCount = 0;

  @override
  Future<CareerDayContext> getDayContext() async {
    readCount++;
    if (reads.isEmpty) throw StateError('No day context queued.');
    return reads.removeAt(0);
  }

  @override
  Future<CareerDayContextReceipt> putDayContext(
    CareerDayContextWrite write,
  ) async {
    writes.add(write);
    final handler = onPut;
    if (handler == null) throw StateError('No day context write queued.');
    return handler(write);
  }

  @override
  Future<CareerSummary> getSummary() => throw UnimplementedError();

  @override
  Future<CareerMissionBoard> getMissions() => throw UnimplementedError();

  @override
  Future<CareerPromotionReceipt> promote(CareerPromotionCommand command) =>
      throw UnimplementedError();

  @override
  Future<CareerTradeReasonReceipt> saveTradeReason(CareerTradeReason reason) =>
      throw UnimplementedError();
}

CareerDayContext _context({
  bool configured = false,
  int revision = 1,
  String timeZone = 'Africa/Lagos',
  String serverDate = '2026-09-20',
  DateTime? nextDayAt,
}) => CareerDayContext(
  revision: revision,
  timeZone: configured ? timeZone : 'UTC',
  configured: configured,
  serverDate: serverDate,
  nextDayAt: nextDayAt ?? DateTime.utc(2026, 9, 20, 23),
  createdAt: DateTime.utc(2026, 9, 20, 10),
  updatedAt: configured
      ? DateTime.utc(2026, 9, 20, 10, 0, 1)
      : DateTime.utc(2026, 9, 20, 10),
);

CareerDayContextReceipt _receipt(
  CareerDayContextWrite write,
  CareerDayContext context,
) => CareerDayContextReceipt(
  mutationId: write.mutationId,
  baseRevision: write.baseRevision,
  timeZone: write.timeZone,
  dayContext: context,
);
