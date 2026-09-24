import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/markets/stock_history.dart';

import 'support/stock_history_fixtures.dart';

final class _PendingHistory {
  _PendingHistory(this.request, this.cancellation);

  final StockHistoryRequest request;
  final StockResearchCancellation? cancellation;
  final result = Completer<StockHistoryPage>();
}

final class _HeldHistoryClient implements StockHistoryClient {
  final calls = <_PendingHistory>[];

  @override
  Future<StockHistoryPage> history(
    StockHistoryRequest request, {
    StockResearchCancellation? cancellation,
  }) {
    final call = _PendingHistory(request, cancellation);
    calls.add(call);
    return call.result.future;
  }
}

final class _ManualTimer implements Timer {
  _ManualTimer(this.callback);

  final void Function() callback;
  var active = true;

  void fire() {
    if (!active) return;
    active = false;
    callback();
  }

  @override
  void cancel() => active = false;

  @override
  bool get isActive => active;

  @override
  int get tick => active ? 0 : 1;
}

final class _Timers {
  final created = <_ManualTimer>[];

  Timer create(Duration _, void Function() callback) {
    final timer = _ManualTimer(callback);
    created.add(timer);
    return timer;
  }
}

final class _ThrowingCancelTimer implements Timer {
  @override
  void cancel() => throw StateError('private timer failure');

  @override
  bool get isActive => true;

  @override
  int get tick => 0;
}

final class _InactiveTimer implements Timer {
  @override
  void cancel() {}

  @override
  bool get isActive => false;

  @override
  int get tick => 0;
}

Matcher repositoryCode(String value) =>
    isA<StockResearchException>().having((error) => error.code, 'code', value);

const alternateRequest = StockHistoryRequest.appleAaplx(
  interval: StockHistoryInterval.fourHours,
  fromUnixSeconds: stockHistoryFrom,
  toUnixSeconds: '1789358400',
);

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late DateTime now;
  late _Timers timers;

  setUp(() {
    now = DateTime.parse('2026-09-14T18:00:02.000Z');
    timers = _Timers();
  });

  StockHistoryRepository repository(_HeldHistoryClient client) =>
      StockHistoryRepository(
        client: client,
        clock: () => now,
        timerFactory: timers.create,
      );

  test('identical concurrent requests share one future and one read', () async {
    final client = _HeldHistoryClient();
    final subject = repository(client);
    addTearDown(subject.dispose);

    final first = subject.load(stockHistoryRequest);
    final second = subject.load(stockHistoryRequest);
    expect(second, same(first));
    expect(subject.whenIdle, same(first));
    expect(client.calls, hasLength(1));
    expect(subject.state.phase, StockHistoryPhase.loading);

    client.calls.single.result.complete(parsedStockHistory());
    await first;
    expect(subject.state.phase, StockHistoryPhase.ready);
    expect(subject.state.data!.candles.first.openRaw, '1.2300');
    expect(subject.isBusy, isFalse);
  });

  test(
    'a changed window waits for the cancelled read and late data cannot replace it',
    () async {
      final client = _HeldHistoryClient();
      final subject = repository(client);
      addTearDown(subject.dispose);

      final first = subject.load(stockHistoryRequest);
      final second = subject.load(alternateRequest);
      expect(client.calls, hasLength(1));
      expect(client.calls.first.cancellation!.isCancelled, isTrue);
      expect(subject.state.request, alternateRequest);
      expect(subject.state.phase, StockHistoryPhase.loading);

      client.calls.first.result.complete(parsedStockHistory());
      await first;
      await flush();
      expect(client.calls, hasLength(2));
      expect(subject.state.request, alternateRequest);
      expect(subject.state.data, isNull);

      client.calls.last.result.complete(
        parsedStockHistory(request: alternateRequest, candles: const []),
      );
      await second;
      expect(subject.state.phase, StockHistoryPhase.ready);
      expect(subject.state.data!.interval, StockHistoryInterval.fourHours);
      expect(subject.state.data!.candles, isEmpty);
    },
  );

  test('a loading listener can cancel before client dispatch', () async {
    final client = _HeldHistoryClient();
    final subject = repository(client);
    addTearDown(subject.dispose);
    subject.addListener(() {
      if (subject.state.phase == StockHistoryPhase.loading) subject.cancel();
    });

    await subject.load(stockHistoryRequest);
    expect(client.calls, isEmpty);
    expect(subject.state.phase, StockHistoryPhase.cancelled);
    expect(subject.state.errorCode, 'STOCK_HISTORY_CANCELLED');
  });

  test(
    'refreshAfter changes ready to stale without an automatic read',
    () async {
      final client = _HeldHistoryClient();
      final subject = repository(client);
      addTearDown(subject.dispose);
      var notifications = 0;
      subject.addListener(() => notifications++);
      final pending = subject.load(stockHistoryRequest);
      client.calls.single.result.complete(parsedStockHistory());
      await pending;
      final captured = subject.state;
      final calls = client.calls.length;
      final beforeTimer = notifications;
      expect(timers.created, hasLength(1));

      now = DateTime.parse('2026-09-14T18:00:16.000Z');
      expect(captured.phase, StockHistoryPhase.stale);
      expect(captured.errorCode, 'STOCK_HISTORY_STALE');
      expect(captured.isFresh, isFalse);

      timers.created.single.fire();
      expect(subject.state.phase, StockHistoryPhase.stale);
      expect(subject.state.data, same(captured.data));
      expect(client.calls, hasLength(calls));
      expect(notifications, beforeTimer + 1);
    },
  );

  test('clock failure makes captured ready state safely non-ready', () async {
    final client = _HeldHistoryClient();
    var clockFails = false;
    final subject = StockHistoryRepository(
      client: client,
      clock: () {
        if (clockFails) throw StateError('private clock failure');
        return now;
      },
      timerFactory: timers.create,
    );
    addTearDown(subject.dispose);
    final pending = subject.load(stockHistoryRequest);
    client.calls.single.result.complete(parsedStockHistory());
    await pending;
    final captured = subject.state;
    expect(captured.phase, StockHistoryPhase.ready);

    clockFails = true;
    expect(() => captured.phase, returnsNormally);
    expect(captured.phase, StockHistoryPhase.error);
    expect(captured.errorCode, 'STOCK_HISTORY_INVALID_CONFIGURATION');
    expect(captured.isFresh, isFalse);
    expect(captured.hasRetainedData, isTrue);
    expect(timers.created.single.fire, returnsNormally);
    expect(subject.state.phase, StockHistoryPhase.error);
    expect(subject.state.errorCode, 'STOCK_HISTORY_INVALID_CONFIGURATION');
  });

  test('an invalid clock fails closed before a history read', () async {
    final client = _HeldHistoryClient();
    final subject = StockHistoryRepository(
      client: client,
      clock: () => DateTime.utc(10000),
      timerFactory: timers.create,
    );
    addTearDown(subject.dispose);

    await expectLater(
      subject.load(stockHistoryRequest),
      throwsA(repositoryCode('STOCK_HISTORY_INVALID_CONFIGURATION')),
    );
    expect(client.calls, isEmpty);
    expect(subject.state.phase, StockHistoryPhase.error);
    expect(subject.state.errorCode, 'STOCK_HISTORY_INVALID_CONFIGURATION');
  });

  test('broken timer adapters never publish ready or break close', () async {
    for (final timerFactory in <StockHistoryTimerFactory>[
      (_, _) => throw StateError('private timer factory'),
      (_, callback) {
        callback();
        return _ManualTimer(callback);
      },
      (_, _) => _InactiveTimer(),
    ]) {
      final client = _HeldHistoryClient();
      final subject = StockHistoryRepository(
        client: client,
        clock: () => now,
        timerFactory: timerFactory,
      );
      final pending = subject.load(stockHistoryRequest);
      client.calls.single.result.complete(parsedStockHistory());
      await pending;
      expect(subject.state.phase, StockHistoryPhase.error);
      expect(subject.state.errorCode, 'STOCK_HISTORY_TIMER_INVALID');
      expect(subject.close, returnsNormally);
      subject.dispose();
    }

    final client = _HeldHistoryClient();
    final subject = StockHistoryRepository(
      client: client,
      clock: () => now,
      timerFactory: (_, _) => _ThrowingCancelTimer(),
    );
    final pending = subject.load(stockHistoryRequest);
    client.calls.single.result.complete(parsedStockHistory());
    await pending;
    expect(subject.state.phase, StockHistoryPhase.ready);
    expect(subject.close, returnsNormally);
    expect(subject.state.phase, StockHistoryPhase.closed);
    subject.dispose();
  });

  test(
    'an already expired response is retained but never becomes ready',
    () async {
      final client = _HeldHistoryClient();
      final subject = repository(client);
      addTearDown(subject.dispose);
      final pending = subject.load(stockHistoryRequest);
      now = DateTime.parse('2026-09-14T18:00:16.000Z');
      client.calls.single.result.complete(parsedStockHistory());
      await pending;

      expect(subject.state.phase, StockHistoryPhase.stale);
      expect(subject.state.errorCode, 'STOCK_HISTORY_STALE');
      expect(subject.state.data, isNotNull);
      expect(timers.created, isEmpty);
    },
  );

  test(
    'failed same-window refresh retains data and exposes failure phase',
    () async {
      final client = _HeldHistoryClient();
      final subject = repository(client);
      addTearDown(subject.dispose);
      final initial = subject.load(stockHistoryRequest);
      final page = parsedStockHistory();
      client.calls.single.result.complete(page);
      await initial;

      final retry = subject.load(stockHistoryRequest);
      expect(subject.state.phase, StockHistoryPhase.loading);
      expect(subject.state.data, same(page));
      client.calls.last.result.completeError(
        const StockResearchException('STOCK_HISTORY_NETWORK_ERROR'),
      );
      await retry;
      expect(subject.state.phase, StockHistoryPhase.offline);
      expect(subject.state.data, same(page));
      expect(subject.state.hasRetainedData, isTrue);

      final providerRetry = subject.load(stockHistoryRequest);
      client.calls.last.result.completeError(
        const StockResearchException('STOCK_HISTORY_RATE_LIMITED'),
      );
      await providerRetry;
      expect(subject.state.phase, StockHistoryPhase.error);
      expect(subject.state.errorCode, 'STOCK_HISTORY_RATE_LIMITED');
      expect(subject.state.data, same(page));
    },
  );

  test('offline and reconnect transitions never fetch automatically', () async {
    final client = _HeldHistoryClient();
    final subject = repository(client);
    addTearDown(subject.dispose);
    final initial = subject.load(stockHistoryRequest);
    final page = parsedStockHistory();
    client.calls.single.result.complete(page);
    await initial;
    final calls = client.calls.length;

    subject.setNetworkAvailable(false);
    expect(subject.state.phase, StockHistoryPhase.offline);
    expect(subject.state.data, same(page));
    await subject.load(stockHistoryRequest);
    expect(client.calls, hasLength(calls));

    subject.setNetworkAvailable(true);
    expect(subject.state.phase, StockHistoryPhase.ready);
    expect(client.calls, hasLength(calls));
    now = DateTime.parse('2026-09-14T18:00:16.000Z');
    subject.setNetworkAvailable(false);
    subject.setNetworkAvailable(true);
    expect(subject.state.phase, StockHistoryPhase.stale);
    expect(client.calls, hasLength(calls));
  });

  test(
    'cancel and close invalidate late completions and expose terminal state',
    () async {
      final client = _HeldHistoryClient();
      final subject = repository(client);
      final pending = subject.load(stockHistoryRequest);
      subject.cancel();
      expect(subject.state.phase, StockHistoryPhase.cancelled);
      expect(client.calls.single.cancellation!.isCancelled, isTrue);
      client.calls.single.result.complete(parsedStockHistory());
      await pending;
      expect(subject.state.data, isNull);

      final second = subject.load(stockHistoryRequest);
      expect(client.calls, hasLength(2));
      subject.close();
      expect(subject.state.phase, StockHistoryPhase.closed);
      expect(subject.state.data, isNull);
      expect(client.calls.last.cancellation!.isCancelled, isTrue);
      client.calls.last.result.complete(parsedStockHistory());
      await second;
      expect(subject.state.phase, StockHistoryPhase.closed);
      await expectLater(
        subject.load(stockHistoryRequest),
        throwsA(repositoryCode('STOCK_HISTORY_REPOSITORY_CLOSED')),
      );
      subject.dispose();
    },
  );

  test('invalid request never reaches the reader', () async {
    final client = _HeldHistoryClient();
    final subject = repository(client);
    addTearDown(subject.dispose);
    await expectLater(
      subject.load(
        const StockHistoryRequest.appleAaplx(
          interval: StockHistoryInterval.oneHour,
          fromUnixSeconds: '01789344000',
          toUnixSeconds: stockHistoryTo,
        ),
      ),
      throwsA(repositoryCode('STOCK_HISTORY_INPUT_INVALID')),
    );
    expect(client.calls, isEmpty);
    expect(subject.state.phase, StockHistoryPhase.idle);
  });

  test('a custom reader cannot return a different request window', () async {
    final client = _HeldHistoryClient();
    final subject = repository(client);
    addTearDown(subject.dispose);
    final pending = subject.load(stockHistoryRequest);
    client.calls.single.result.complete(
      parsedStockHistory(request: alternateRequest, candles: const []),
    );
    await pending;
    expect(subject.state.phase, StockHistoryPhase.error);
    expect(subject.state.errorCode, 'STOCK_HISTORY_RESPONSE_INVALID');
    expect(subject.state.data, isNull);
  });
}
