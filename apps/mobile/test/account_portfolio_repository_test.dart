import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/account/account_data.dart';

import 'support/account_data_fixtures.dart';

const alternateWallet = 'FbP8bwmje245N5k3GTrx7BcKcDwbJNbfvEaEbF8eewY1';

AccountContextSnapshot parsedContext({
  String? address = wallet,
  EmbeddedSolanaWalletStatus? status,
}) {
  final resolved = status ?? EmbeddedSolanaWalletStatus.candidate;
  final embedded = switch (resolved) {
    EmbeddedSolanaWalletStatus.missing => <String, Object?>{
      'status': 'missing',
    },
    EmbeddedSolanaWalletStatus.ambiguous => <String, Object?>{
      'status': 'ambiguous',
    },
    EmbeddedSolanaWalletStatus.candidate => <String, Object?>{
      'status': 'candidate',
      'address': address,
      'verifiedAtUnixSeconds': 1757845201,
    },
  };
  return AccountContextSnapshot.fromEnvelope(
    contextEnvelope(embeddedWallet: embedded),
    expectedUserId: account,
  );
}

AccountHoldingsSnapshot parsedHoldings({
  required DateTime observedAt,
  String address = wallet,
}) {
  final envelope = holdingsEnvelope();
  final walletData = envelope['wallet']! as Map<String, Object?>;
  walletData['address'] = address;
  final holdings = envelope['holdings']! as Map<String, Object?>;
  holdings['observedAt'] = observedAt.toUtc().toIso8601String();
  return AccountHoldingsSnapshot.fromEnvelope(
    envelope,
    expectedUserId: account,
  );
}

final class _Reader implements AccountPortfolioReader {
  _Reader({
    String? accountId,
    required this.contextRead,
    required this.holdingsRead,
  }) : accountId = accountId ?? account;

  @override
  final String accountId;
  Future<AccountContextSnapshot> Function() contextRead;
  Future<AccountHoldingsSnapshot> Function() holdingsRead;
  final calls = <String>[];
  var cancellations = 0;
  var closes = 0;

  @override
  Future<AccountContextSnapshot> readContext() {
    calls.add('context');
    return contextRead();
  }

  @override
  Future<AccountHoldingsSnapshot> readHoldings() {
    calls.add('holdings');
    return holdingsRead();
  }

  @override
  void cancelPending() => cancellations++;

  @override
  void close() => closes++;
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

_Reader _readerAt(DateTime Function() now) => _Reader(
  contextRead: () async => parsedContext(),
  holdingsRead: () async =>
      parsedHoldings(observedAt: now().subtract(const Duration(seconds: 2))),
);

Matcher portfolioFailure(AccountPortfolioIssue issue) => throwsA(
  isA<AccountPortfolioException>().having(
    (error) => error.issue,
    'issue',
    issue,
  ),
);

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late DateTime now;
  late _Timers timers;

  setUp(() {
    now = DateTime.utc(2026, 9, 14, 17, 28, 30);
    timers = _Timers();
  });

  AccountPortfolioRepository repository(
    _Reader reader, {
    Duration age = const Duration(seconds: 10),
    Duration futureSkew = const Duration(seconds: 2),
  }) => AccountPortfolioRepository(
    reader: reader,
    maximumObservationAge: age,
    maximumFutureSkew: futureSkew,
    clock: () => now,
    timerFactory: timers.create,
  );

  test(
    'reads context before holdings and publishes one coherent snapshot',
    () async {
      final reader = _readerAt(() => now);
      final subject = repository(reader);
      addTearDown(subject.dispose);
      final phases = <AccountPortfolioPhase>[];
      subject.addListener(() => phases.add(subject.state.phase));

      await subject.refresh();

      expect(reader.calls, ['context', 'holdings']);
      expect(subject.state.phase, AccountPortfolioPhase.ready);
      expect(subject.readyPortfolio, isNotNull);
      expect(subject.readyPortfolio!.accountId, account);
      expect(subject.readyPortfolio!.context.userId, account);
      expect(subject.readyPortfolio!.holdings.wallet.address, wallet);
      expect(
        subject.readyPortfolio!.holdings.usdc.amountRaw,
        '18446744073709551615',
      );
      expect(
        subject.readyPortfolio!.freshUntil,
        DateTime.utc(2026, 9, 14, 17, 28, 38),
      );
      expect(phases.first, AccountPortfolioPhase.loading);
      expect(phases.last, AccountPortfolioPhase.ready);
    },
  );

  test(
    'concurrent refreshes share one operation instead of hitting client busy',
    () async {
      final gate = Completer<AccountContextSnapshot>();
      final reader = _Reader(
        contextRead: () => gate.future,
        holdingsRead: () async => parsedHoldings(
          observedAt: now.subtract(const Duration(seconds: 1)),
        ),
      );
      final subject = repository(reader);
      addTearDown(subject.dispose);

      final first = subject.refresh();
      final second = subject.refresh();
      expect(identical(first, second), isTrue);
      expect(reader.calls, ['context']);
      gate.complete(parsedContext());
      await Future.wait([first, second]);

      expect(reader.calls, ['context', 'holdings']);
      expect(subject.state.phase, AccountPortfolioPhase.ready);
    },
  );

  test(
    'missing or ambiguous wallet stops before holdings and clears balances',
    () async {
      final reader = _readerAt(() => now);
      final subject = repository(reader);
      addTearDown(subject.dispose);
      await subject.refresh();
      expect(subject.readyPortfolio, isNotNull);

      reader.calls.clear();
      reader.contextRead = () async => parsedContext(
        address: null,
        status: EmbeddedSolanaWalletStatus.missing,
      );
      await subject.refresh();
      expect(reader.calls, ['context']);
      expect(subject.state.phase, AccountPortfolioPhase.error);
      expect(subject.state.issue, AccountPortfolioIssue.walletMissing);
      expect(subject.state.portfolio, isNull);

      reader.calls.clear();
      reader.contextRead = () async => parsedContext(
        address: null,
        status: EmbeddedSolanaWalletStatus.ambiguous,
      );
      await subject.refresh();
      expect(reader.calls, ['context']);
      expect(subject.state.issue, AccountPortfolioIssue.walletAmbiguous);
      expect(subject.state.portfolio, isNull);
    },
  );

  test(
    'a newly linked wallet drops the previous wallet before holdings finish',
    () async {
      final reader = _readerAt(() => now);
      final subject = repository(reader);
      addTearDown(subject.dispose);
      await subject.refresh();

      final holdingsGate = Completer<AccountHoldingsSnapshot>();
      reader.contextRead = () async => parsedContext(address: alternateWallet);
      reader.holdingsRead = () => holdingsGate.future;
      final refresh = subject.refresh();
      await flush();

      expect(subject.state.phase, AccountPortfolioPhase.loading);
      expect(
        subject.state.context!.embeddedSolanaWallet.address,
        alternateWallet,
      );
      expect(subject.state.portfolio, isNull);

      holdingsGate.complete(
        parsedHoldings(
          observedAt: now.subtract(const Duration(seconds: 1)),
          address: alternateWallet,
        ),
      );
      await refresh;
      expect(subject.state.phase, AccountPortfolioPhase.ready);
      expect(subject.readyPortfolio!.holdings.wallet.address, alternateWallet);
    },
  );

  test(
    'context and holdings wallet mismatch fails closed without retained data',
    () async {
      final reader = _Reader(
        contextRead: () async => parsedContext(),
        holdingsRead: () async => parsedHoldings(
          observedAt: now.subtract(const Duration(seconds: 1)),
          address: alternateWallet,
        ),
      );
      final subject = repository(reader);
      addTearDown(subject.dispose);

      await subject.refresh();
      expect(subject.state.phase, AccountPortfolioPhase.error);
      expect(subject.state.issue, AccountPortfolioIssue.walletChanged);
      expect(subject.state.portfolio, isNull);
    },
  );

  test(
    'cached state and repository stop reporting ready at the exact deadline',
    () async {
      final reader = _readerAt(() => now);
      final subject = repository(reader);
      addTearDown(subject.dispose);
      var notifications = 0;
      subject.addListener(() => notifications++);
      await subject.refresh();
      final captured = subject.state;
      final deadline = captured.portfolio!.freshUntil;
      final beforeExpiryNotifications = notifications;

      now = deadline;
      expect(captured.phase, AccountPortfolioPhase.stale);
      expect(captured.issue, AccountPortfolioIssue.observationExpired);
      expect(captured.portfolioIsFresh, isFalse);
      expect(subject.state.phase, AccountPortfolioPhase.stale);
      expect(subject.readyPortfolio, isNull);

      timers.created.last.fire();
      expect(subject.state.phase, AccountPortfolioPhase.stale);
      expect(notifications, beforeExpiryNotifications + 1);
    },
  );

  test(
    'cached ready state fails closed when its injected clock throws',
    () async {
      var clockFails = false;
      var clockOutOfContract = false;
      final reader = _readerAt(() => now);
      final subject = AccountPortfolioRepository(
        reader: reader,
        maximumObservationAge: const Duration(seconds: 5),
        maximumFutureSkew: const Duration(seconds: 2),
        clock: () {
          if (clockFails) throw StateError('private clock failure');
          if (clockOutOfContract) return DateTime.utc(10000);
          return now;
        },
        timerFactory: timers.create,
      );
      addTearDown(subject.dispose);

      await subject.refresh();
      final captured = subject.state;
      expect(captured.phase, AccountPortfolioPhase.ready);

      clockFails = true;
      expect(captured.phase, AccountPortfolioPhase.error);
      expect(captured.issue, AccountPortfolioIssue.invalidConfiguration);
      expect(captured.portfolioIsFresh, isFalse);
      expect(captured.hasRetainedPortfolio, isTrue);
      expect(subject.readyPortfolio, isNull);
      expect(timers.created.single.fire, returnsNormally);
      expect(subject.state.phase, AccountPortfolioPhase.error);
      expect(subject.state.issue, AccountPortfolioIssue.invalidConfiguration);

      subject.setNetworkAvailable(false);
      expect(subject.state.phase, AccountPortfolioPhase.offline);
      expect(() => subject.setNetworkAvailable(true), returnsNormally);
      expect(subject.state.phase, AccountPortfolioPhase.error);
      expect(subject.state.issue, AccountPortfolioIssue.invalidConfiguration);

      clockFails = false;
      clockOutOfContract = true;
      expect(captured.phase, AccountPortfolioPhase.error);
      expect(captured.issue, AccountPortfolioIssue.invalidConfiguration);
      expect(captured.portfolioIsFresh, isFalse);
    },
  );

  test('clock failure during expiry scheduling publishes an error', () async {
    var clockReads = 0;
    final reader = _readerAt(() => now);
    final subject = AccountPortfolioRepository(
      reader: reader,
      maximumObservationAge: const Duration(seconds: 5),
      maximumFutureSkew: const Duration(seconds: 2),
      clock: () {
        clockReads++;
        if (clockReads > 1) throw StateError('private scheduling clock');
        return now;
      },
      timerFactory: timers.create,
    );
    addTearDown(subject.dispose);

    await expectLater(subject.refresh(), completes);
    expect(subject.state.phase, AccountPortfolioPhase.error);
    expect(subject.state.issue, AccountPortfolioIssue.invalidConfiguration);
    expect(subject.state.portfolio, isNotNull);
    expect(subject.readyPortfolio, isNull);
    expect(timers.created, isEmpty);
  });

  test(
    'expired and materially future observations can never become ready',
    () async {
      final reader = _readerAt(() => now);
      final subject = repository(reader);
      addTearDown(subject.dispose);

      reader.holdingsRead = () async =>
          parsedHoldings(observedAt: now.subtract(const Duration(seconds: 10)));
      await subject.refresh();
      expect(subject.state.phase, AccountPortfolioPhase.stale);
      expect(subject.state.issue, AccountPortfolioIssue.observationExpired);
      expect(subject.readyPortfolio, isNull);

      reader.holdingsRead = () async =>
          parsedHoldings(observedAt: now.add(const Duration(seconds: 3)));
      await subject.refresh();
      expect(subject.state.phase, AccountPortfolioPhase.error);
      expect(subject.state.issue, AccountPortfolioIssue.observationInFuture);
      expect(subject.readyPortfolio, isNull);
    },
  );

  test(
    'cancel invalidates a late completion and keeps only same-wallet data',
    () async {
      final reader = _readerAt(() => now);
      final subject = repository(reader);
      addTearDown(subject.dispose);
      await subject.refresh();
      final previous = subject.readyPortfolio;

      final contextGate = Completer<AccountContextSnapshot>();
      reader.contextRead = () => contextGate.future;
      final refresh = subject.refresh();
      subject.cancelRefresh();
      expect(subject.state.phase, AccountPortfolioPhase.cancelled);
      expect(subject.state.portfolio, same(previous));
      expect(reader.cancellations, 1);

      reader.contextRead = () async => parsedContext();
      reader.holdingsRead = () async =>
          parsedHoldings(observedAt: now.subtract(const Duration(seconds: 1)));
      final restart = subject.refresh();
      expect(subject.whenIdle, same(restart));
      contextGate.complete(parsedContext(address: alternateWallet));
      await refresh;
      expect(subject.state.phase, AccountPortfolioPhase.loading);
      expect(subject.state.portfolio, same(previous));
      await restart;
      expect(subject.state.phase, AccountPortfolioPhase.ready);
      expect(reader.calls.skip(2), ['context', 'context', 'holdings']);
    },
  );

  test(
    'offline transition cancels work, keeps scoped data, and never auto-fetches',
    () async {
      final reader = _readerAt(() => now);
      final subject = repository(reader);
      addTearDown(subject.dispose);
      await subject.refresh();
      final calls = reader.calls.length;

      subject.setNetworkAvailable(false);
      expect(subject.state.phase, AccountPortfolioPhase.offline);
      expect(subject.state.hasRetainedPortfolio, isTrue);
      await subject.refresh();
      expect(reader.calls.length, calls);

      now = subject.state.portfolio!.freshUntil;
      expect(subject.readyPortfolio, isNull);
      subject.setNetworkAvailable(true);
      expect(subject.state.phase, AccountPortfolioPhase.stale);
      expect(subject.state.issue, AccountPortfolioIssue.observationExpired);
      expect(reader.calls.length, calls);
    },
  );

  test(
    'going offline invalidates an in-flight result before it can publish',
    () async {
      final holdingsGate = Completer<AccountHoldingsSnapshot>();
      final reader = _Reader(
        contextRead: () async => parsedContext(),
        holdingsRead: () => holdingsGate.future,
      );
      final subject = repository(reader);
      addTearDown(subject.dispose);

      final refresh = subject.refresh();
      await flush();
      expect(subject.state.phase, AccountPortfolioPhase.loading);
      subject.setNetworkAvailable(false);
      expect(subject.state.phase, AccountPortfolioPhase.offline);
      expect(reader.cancellations, 1);

      holdingsGate.complete(
        parsedHoldings(observedAt: now.subtract(const Duration(seconds: 1))),
      );
      await refresh;
      expect(subject.state.phase, AccountPortfolioPhase.offline);
      expect(subject.state.portfolio, isNull);
    },
  );

  test(
    'same-wallet timeout retains the prior snapshot but does not call it ready',
    () async {
      final reader = _readerAt(() => now);
      final subject = repository(reader);
      addTearDown(subject.dispose);
      await subject.refresh();
      final previous = subject.readyPortfolio;

      reader.holdingsRead = () async =>
          throw const AccountDataException(AccountDataFailure.timeout);
      await subject.refresh();

      expect(subject.state.phase, AccountPortfolioPhase.offline);
      expect(subject.state.issue, AccountPortfolioIssue.timeout);
      expect(subject.state.portfolio, same(previous));
      expect(subject.state.hasRetainedPortfolio, isTrue);
      expect(subject.readyPortfolio, isNull);
    },
  );

  test(
    'account mismatch clears data and permanently retires the reader',
    () async {
      final reader = _readerAt(() => now);
      final subject = repository(reader);
      addTearDown(subject.dispose);
      await subject.refresh();
      reader.contextRead = () async =>
          throw const AccountDataException(AccountDataFailure.accountMismatch);

      await subject.refresh();
      expect(subject.state.phase, AccountPortfolioPhase.accountChanged);
      expect(subject.state.context, isNull);
      expect(subject.state.portfolio, isNull);
      expect(reader.closes, 1);
      await expectLater(
        subject.refresh(),
        portfolioFailure(AccountPortfolioIssue.accountChanged),
      );
    },
  );

  test(
    'explicit account switch cancels and ignores the old account response',
    () async {
      final contextGate = Completer<AccountContextSnapshot>();
      final reader = _Reader(
        contextRead: () => contextGate.future,
        holdingsRead: () async => parsedHoldings(observedAt: now),
      );
      final subject = repository(reader);
      addTearDown(subject.dispose);
      final refresh = subject.refresh();

      subject.invalidateForAccountSwitch(activeAccountId: otherAccount);
      expect(subject.state.phase, AccountPortfolioPhase.accountChanged);
      expect(subject.state.portfolio, isNull);
      expect(reader.cancellations, 1);
      expect(reader.closes, 1);
      contextGate.complete(parsedContext());
      await refresh;
      expect(subject.state.phase, AccountPortfolioPhase.accountChanged);
      expect(reader.calls, ['context']);
    },
  );

  test(
    'same canonical account does not invalidate and authentication loss clears',
    () async {
      final reader = _readerAt(() => now);
      final subject = repository(reader);
      addTearDown(subject.dispose);
      await subject.refresh();
      subject.invalidateForAccountSwitch(
        activeAccountId: account.toUpperCase(),
      );
      expect(subject.state.phase, AccountPortfolioPhase.ready);

      reader.contextRead = () async =>
          throw const AccountDataException(AccountDataFailure.unauthenticated);
      await subject.refresh();
      expect(subject.state.phase, AccountPortfolioPhase.error);
      expect(subject.state.issue, AccountPortfolioIssue.unauthenticated);
      expect(subject.state.context, isNull);
      expect(subject.state.portfolio, isNull);
    },
  );

  test(
    'dispose cancels, closes, clears data, and rejects later refreshes',
    () async {
      final reader = _readerAt(() => now);
      final subject = repository(reader);
      await subject.refresh();

      subject.dispose();
      expect(subject.state.phase, AccountPortfolioPhase.closed);
      expect(subject.state.context, isNull);
      expect(subject.state.portfolio, isNull);
      expect(reader.cancellations, 1);
      expect(reader.closes, 1);
      await expectLater(
        subject.refresh(),
        portfolioFailure(AccountPortfolioIssue.closed),
      );
    },
  );

  test(
    'invalid reader binding and invalid freshness policy fail at construction',
    () {
      _Reader invalidReader(String id) => _Reader(
        accountId: id,
        contextRead: () async => parsedContext(),
        holdingsRead: () async => parsedHoldings(observedAt: now),
      );

      expect(
        () => repository(invalidReader(account.toUpperCase())),
        portfolioFailure(AccountPortfolioIssue.invalidConfiguration),
      );
      expect(
        () => AccountPortfolioRepository(
          reader: invalidReader(account),
          maximumObservationAge: Duration.zero,
        ),
        portfolioFailure(AccountPortfolioIssue.invalidConfiguration),
      );
    },
  );
}
