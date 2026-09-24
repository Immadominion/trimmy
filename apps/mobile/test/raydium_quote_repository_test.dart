import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/markets/raydium_quotes.dart';

import 'support/raydium_quote_fixtures.dart';

final class _PendingQuote {
  _PendingQuote(this.request, this.cancellation);

  final RaydiumQuoteRequest request;
  final RaydiumQuoteCancellation? cancellation;
  final result = Completer<RaydiumStockQuote>();
}

final class _HeldQuoteClient implements RaydiumQuoteClient {
  final calls = <_PendingQuote>[];

  @override
  Future<RaydiumStockQuote> quote(
    RaydiumQuoteRequest request, {
    RaydiumQuoteCancellation? cancellation,
  }) {
    final call = _PendingQuote(request, cancellation);
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

Matcher repositoryFailure(String value) =>
    isA<StockResearchException>().having((error) => error.code, 'code', value);

const alternateRaydiumRequest = RaydiumQuoteRequest.appleAaplx(
  side: RaydiumQuoteSide.buy,
  amountRaw: '20000000',
);

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late DateTime now;
  late _Timers timers;

  setUp(() {
    now = DateTime.parse('2026-09-14T18:00:02.000Z');
    timers = _Timers();
  });

  RaydiumQuoteRepository repository(_HeldQuoteClient client) =>
      RaydiumQuoteRepository(
        client: client,
        clock: () => now,
        timerFactory: timers.create,
      );

  test('identical concurrent requests share one future and one read', () async {
    final client = _HeldQuoteClient();
    final subject = repository(client);
    addTearDown(subject.dispose);

    final first = subject.load(raydiumBuyRequest);
    final second = subject.load(raydiumBuyRequest);
    expect(second, same(first));
    expect(subject.whenIdle, same(first));
    expect(client.calls, hasLength(1));
    expect(subject.state.phase, RaydiumQuotePhase.loading);

    client.calls.single.result.complete(parsedRaydiumQuote());
    await first;
    expect(subject.state.phase, RaydiumQuotePhase.ready);
    expect(subject.state.data!.output.estimatedAmountRaw, '2978849');
    expect(subject.isBusy, isFalse);
    expect(timers.created, hasLength(1));
  });

  test(
    'a changed request waits for cancellation and masks late data',
    () async {
      final client = _HeldQuoteClient();
      final subject = repository(client);
      addTearDown(subject.dispose);

      final first = subject.load(raydiumBuyRequest);
      final second = subject.load(alternateRaydiumRequest);
      expect(client.calls, hasLength(1));
      expect(client.calls.first.cancellation!.isCancelled, isTrue);
      expect(subject.state.request, alternateRaydiumRequest);
      expect(subject.state.phase, RaydiumQuotePhase.loading);

      client.calls.first.result.complete(parsedRaydiumQuote());
      await first;
      await flush();
      expect(client.calls, hasLength(2));
      expect(subject.state.data, isNull);

      client.calls.last.result.complete(
        parsedRaydiumQuote(request: alternateRaydiumRequest),
      );
      await second;
      expect(subject.state.phase, RaydiumQuotePhase.ready);
      expect(subject.state.data!.request, alternateRaydiumRequest);
    },
  );

  test('a loading listener can cancel before client dispatch', () async {
    final client = _HeldQuoteClient();
    final subject = repository(client);
    addTearDown(subject.dispose);
    subject.addListener(() {
      if (subject.state.phase == RaydiumQuotePhase.loading) subject.cancel();
    });

    await subject.load(raydiumBuyRequest);
    expect(client.calls, isEmpty);
    expect(subject.state.phase, RaydiumQuotePhase.cancelled);
    expect(subject.state.errorCode, 'RAYDIUM_QUOTE_CANCELLED');
  });

  test(
    'refreshAfter changes ready to stale without an automatic read',
    () async {
      final client = _HeldQuoteClient();
      final subject = repository(client);
      addTearDown(subject.dispose);
      var notifications = 0;
      subject.addListener(() => notifications++);
      final pending = subject.load(raydiumBuyRequest);
      client.calls.single.result.complete(parsedRaydiumQuote());
      await pending;
      final captured = subject.state;
      final calls = client.calls.length;
      final beforeTimer = notifications;

      now = DateTime.parse('2026-09-14T18:00:10.000Z');
      expect(captured.phase, RaydiumQuotePhase.stale);
      expect(captured.errorCode, 'MARKET_ESTIMATE_STALE');
      expect(captured.isFresh, isFalse);
      expect(subject.state.phase, RaydiumQuotePhase.stale);

      timers.created.single.fire();
      expect(subject.state.phase, RaydiumQuotePhase.stale);
      expect(subject.state.data, same(captured.data));
      expect(client.calls, hasLength(calls));
      expect(notifications, beforeTimer + 1);
    },
  );

  test('an expired response is retained but never reports ready', () async {
    final client = _HeldQuoteClient();
    final subject = repository(client);
    addTearDown(subject.dispose);
    final pending = subject.load(raydiumBuyRequest);
    now = DateTime.parse('2026-09-14T18:00:10.000Z');
    client.calls.single.result.complete(parsedRaydiumQuote());
    await pending;

    expect(subject.state.phase, RaydiumQuotePhase.stale);
    expect(subject.state.errorCode, 'MARKET_ESTIMATE_STALE');
    expect(subject.state.data, isNotNull);
    expect(timers.created, isEmpty);
  });

  test('a materially future server observation never becomes ready', () async {
    final client = _HeldQuoteClient();
    final subject = repository(client);
    addTearDown(subject.dispose);
    final payload = raydiumQuotePayload()
      ..['requestedAt'] = '2026-09-14T18:01:03.000Z'
      ..['receivedAt'] = '2026-09-14T18:01:04.000Z'
      ..['refreshAfter'] = '2026-09-14T18:01:13.000Z';

    final pending = subject.load(raydiumBuyRequest);
    client.calls.single.result.complete(parsedRaydiumQuote(payload: payload));
    await pending;

    expect(subject.state.phase, RaydiumQuotePhase.error);
    expect(subject.state.errorCode, 'RAYDIUM_QUOTE_RESPONSE_INVALID');
    expect(subject.state.data, isNull);
    expect(timers.created, isEmpty);
  });

  test('same-request failures retain data with explicit phases', () async {
    final client = _HeldQuoteClient();
    final subject = repository(client);
    addTearDown(subject.dispose);
    final initial = subject.load(raydiumBuyRequest);
    final quote = parsedRaydiumQuote();
    client.calls.single.result.complete(quote);
    await initial;

    final offline = subject.load(raydiumBuyRequest);
    client.calls.last.result.completeError(
      const StockResearchException('RAYDIUM_QUOTE_NETWORK_ERROR'),
    );
    await offline;
    expect(subject.state.phase, RaydiumQuotePhase.offline);
    expect(subject.state.data, same(quote));
    expect(subject.state.hasRetainedData, isTrue);

    final provider = subject.load(raydiumBuyRequest);
    client.calls.last.result.completeError(
      const StockResearchException('MARKET_RATE_LIMITED'),
    );
    await provider;
    expect(subject.state.phase, RaydiumQuotePhase.error);
    expect(subject.state.errorCode, 'MARKET_RATE_LIMITED');
    expect(subject.state.data, same(quote));
  });

  test('offline and reconnect never fetch automatically', () async {
    final client = _HeldQuoteClient();
    final subject = repository(client);
    addTearDown(subject.dispose);
    final initial = subject.load(raydiumBuyRequest);
    final quote = parsedRaydiumQuote();
    client.calls.single.result.complete(quote);
    await initial;
    final calls = client.calls.length;

    subject.setNetworkAvailable(false);
    expect(subject.state.phase, RaydiumQuotePhase.offline);
    expect(subject.state.data, same(quote));
    await subject.load(raydiumBuyRequest);
    expect(client.calls, hasLength(calls));

    subject.setNetworkAvailable(true);
    expect(subject.state.phase, RaydiumQuotePhase.ready);
    expect(client.calls, hasLength(calls));
    now = DateTime.parse('2026-09-14T18:00:10.000Z');
    subject.setNetworkAvailable(false);
    subject.setNetworkAvailable(true);
    expect(subject.state.phase, RaydiumQuotePhase.stale);
    expect(client.calls, hasLength(calls));
  });

  test(
    'clock failure makes captured and current state safely non-ready',
    () async {
      final client = _HeldQuoteClient();
      var clockFails = false;
      final subject = RaydiumQuoteRepository(
        client: client,
        clock: () {
          if (clockFails) throw StateError('private clock failure');
          return now;
        },
        timerFactory: timers.create,
      );
      addTearDown(subject.dispose);
      final pending = subject.load(raydiumBuyRequest);
      client.calls.single.result.complete(parsedRaydiumQuote());
      await pending;
      final captured = subject.state;
      expect(captured.phase, RaydiumQuotePhase.ready);

      clockFails = true;
      expect(captured.phase, RaydiumQuotePhase.error);
      expect(captured.errorCode, 'RAYDIUM_QUOTE_CLOCK_INVALID');
      expect(captured.isFresh, isFalse);
      expect(captured.hasRetainedData, isTrue);
      expect(timers.created.single.fire, returnsNormally);
      expect(subject.state.phase, RaydiumQuotePhase.error);
      expect(subject.state.errorCode, 'RAYDIUM_QUOTE_CLOCK_INVALID');
      await expectLater(
        subject.load(raydiumBuyRequest),
        throwsA(repositoryFailure('RAYDIUM_QUOTE_CLOCK_INVALID')),
      );
    },
  );

  test('an out-of-contract clock fails before a client read', () async {
    final client = _HeldQuoteClient();
    final subject = RaydiumQuoteRepository(
      client: client,
      clock: () => DateTime.utc(10000),
      timerFactory: timers.create,
    );
    addTearDown(subject.dispose);

    await expectLater(
      subject.load(raydiumBuyRequest),
      throwsA(repositoryFailure('RAYDIUM_QUOTE_CLOCK_INVALID')),
    );
    expect(client.calls, isEmpty);
    expect(subject.state.phase, RaydiumQuotePhase.error);
    expect(subject.state.errorCode, 'RAYDIUM_QUOTE_CLOCK_INVALID');
  });

  test('timer adapter failures never publish ready or break close', () async {
    final factoryClient = _HeldQuoteClient();
    final failedFactory = RaydiumQuoteRepository(
      client: factoryClient,
      clock: () => now,
      timerFactory: (_, _) => throw StateError('private timer factory'),
    );
    final first = failedFactory.load(raydiumBuyRequest);
    factoryClient.calls.single.result.complete(parsedRaydiumQuote());
    await first;
    expect(failedFactory.state.phase, RaydiumQuotePhase.error);
    expect(failedFactory.state.errorCode, 'RAYDIUM_QUOTE_TIMER_INVALID');
    expect(failedFactory.state.data, isNotNull);
    expect(failedFactory.close, returnsNormally);

    final cancelClient = _HeldQuoteClient();
    final throwingCancel = RaydiumQuoteRepository(
      client: cancelClient,
      clock: () => now,
      timerFactory: (_, _) => _ThrowingCancelTimer(),
    );
    final second = throwingCancel.load(raydiumBuyRequest);
    cancelClient.calls.single.result.complete(parsedRaydiumQuote());
    await second;
    expect(throwingCancel.state.phase, RaydiumQuotePhase.ready);
    expect(throwingCancel.close, returnsNormally);
    expect(throwingCancel.state.phase, RaydiumQuotePhase.closed);

    for (final timerFactory in <RaydiumQuoteTimerFactory>[
      (_, callback) {
        callback();
        return _ManualTimer(callback);
      },
      (_, _) => _InactiveTimer(),
    ]) {
      final client = _HeldQuoteClient();
      final subject = RaydiumQuoteRepository(
        client: client,
        clock: () => now,
        timerFactory: timerFactory,
      );
      final pending = subject.load(raydiumBuyRequest);
      client.calls.single.result.complete(parsedRaydiumQuote());
      await pending;
      expect(subject.state.phase, RaydiumQuotePhase.error);
      expect(subject.state.errorCode, 'RAYDIUM_QUOTE_TIMER_INVALID');
      expect(subject.close, returnsNormally);
      subject.dispose();
    }
    failedFactory.dispose();
    throwingCancel.dispose();
  });

  test('cancel and close invalidate late completions', () async {
    final client = _HeldQuoteClient();
    final subject = repository(client);
    final pending = subject.load(raydiumBuyRequest);
    subject.cancel();
    expect(subject.state.phase, RaydiumQuotePhase.cancelled);
    expect(client.calls.single.cancellation!.isCancelled, isTrue);
    client.calls.single.result.complete(parsedRaydiumQuote());
    await pending;
    expect(subject.state.data, isNull);

    final second = subject.load(raydiumBuyRequest);
    expect(client.calls, hasLength(2));
    subject.close();
    expect(subject.state.phase, RaydiumQuotePhase.closed);
    expect(subject.state.data, isNull);
    expect(client.calls.last.cancellation!.isCancelled, isTrue);
    client.calls.last.result.complete(parsedRaydiumQuote());
    await second;
    await expectLater(
      subject.load(raydiumBuyRequest),
      throwsA(repositoryFailure('RAYDIUM_QUOTE_REPOSITORY_CLOSED')),
    );
    subject.dispose();
  });

  test('invalid requests never reach the client', () async {
    final client = _HeldQuoteClient();
    final subject = repository(client);
    addTearDown(subject.dispose);
    await expectLater(
      subject.load(
        const RaydiumQuoteRequest.appleAaplx(
          side: RaydiumQuoteSide.buy,
          amountRaw: '100000001',
        ),
      ),
      throwsA(repositoryFailure('MARKET_INPUT_INVALID')),
    );
    expect(client.calls, isEmpty);
    expect(subject.state.phase, RaydiumQuotePhase.idle);
  });
}
