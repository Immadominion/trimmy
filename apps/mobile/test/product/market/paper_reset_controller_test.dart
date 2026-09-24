import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trimmy/product/market/market.dart';
import 'package:trimmy/product/market/paper_portfolio_cache.dart';

const _principal = '71000000-0000-4000-8000-000000000001';
const _mutationA = '81000000-0000-4000-8000-000000000001';
const _mutationB = '81000000-0000-4000-8000-000000000002';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'ambiguous failure survives restart and replays the exact request',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final store = PreferencesPaperResetMutationStore(preferences);
      await PaperPortfolioCache.write(
        preferences,
        _principal,
        _portfolio(7),
        now: DateTime.utc(2026, 9, 20, 12),
      );
      final offline = _ResetRepository((_) async {
        throw const PaperResetException(PaperResetFailure.offline);
      });
      final first = PaperResetController(
        principalKey: _principal,
        repository: offline,
        store: store,
        mutationId: () => _mutationA,
      );
      await first.initialize();

      await expectLater(
        first.submit(baseRevision: 7),
        throwsA(
          isA<PaperResetException>().having(
            (error) => error.failure,
            'failure',
            PaperResetFailure.offline,
          ),
        ),
      );
      expect(first.state.hasPendingMutation, isTrue);
      expect(first.state.pending?.mutationId, _mutationA);
      expect(first.state.pending?.baseRevision, 7);
      first.dispose();

      final replay = _ResetRepository((request) async => _success(request));
      final restored = PaperResetController(
        principalKey: _principal,
        repository: replay,
        store: store,
        mutationId: () => _mutationB,
      );
      await restored.initialize();
      expect(restored.state.phase, PaperResetPhase.pending);

      final result = await restored.submit(baseRevision: 99);

      expect(replay.requests, hasLength(1));
      expect(replay.requests.single.mutationId, _mutationA);
      expect(replay.requests.single.baseRevision, 7);
      expect(result.receipt.revision, 8);
      expect(restored.state.phase, PaperResetPhase.succeeded);
      expect((await store.read(_principal))?.mutationId, _mutationA);
      expect(
        (await PaperPortfolioCache.read(
          preferences,
          _principal,
          now: DateTime.utc(2026, 9, 20, 12),
        ))?.revision,
        7,
      );

      await PaperPortfolioCache.invalidate(
        preferences,
        _principal,
        minimumRevision: result.receipt.revision,
      );
      expect(await PaperPortfolioCache.read(preferences, _principal), isNull);

      expect(await restored.acknowledgeApplied(result), isTrue);

      expect(await store.read(_principal), isNull);
    },
  );

  test('concurrent submits share one mutation and one network call', () async {
    final preferences = await SharedPreferences.getInstance();
    final release = Completer<PaperResetResult>();
    final repository = _ResetRepository((_) => release.future);
    final controller = PaperResetController(
      principalKey: _principal,
      repository: repository,
      store: PreferencesPaperResetMutationStore(preferences),
      mutationId: () => _mutationA,
    );
    await controller.initialize();

    final first = controller.submit(baseRevision: 3);
    final second = controller.submit(baseRevision: 3);
    await Future<void>.delayed(Duration.zero);
    expect(repository.requests, hasLength(1));
    release.complete(_success(repository.requests.single));

    expect(await first, same(await second));
    expect(repository.requests.single.mutationId, _mutationA);
  });

  test(
    'shared failed submit has one observed error chain and remains retryable',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final release = Completer<PaperResetResult>();
      final repository = _ResetRepository((_) => release.future);
      final controller = PaperResetController(
        principalKey: _principal,
        repository: repository,
        store: PreferencesPaperResetMutationStore(preferences),
        mutationId: () => _mutationA,
      );
      await controller.initialize();
      final first = controller.submit(baseRevision: 3);
      final second = controller.submit(baseRevision: 99);
      final firstExpectation = expectLater(
        first,
        throwsA(
          isA<PaperResetException>().having(
            (error) => error.failure,
            'failure',
            PaperResetFailure.offline,
          ),
        ),
      );
      final secondExpectation = expectLater(
        second,
        throwsA(isA<PaperResetException>()),
      );
      while (repository.requests.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      release.completeError(
        const PaperResetException(PaperResetFailure.offline),
        StackTrace.current,
      );

      await Future.wait([firstExpectation, secondExpectation]);
      await Future<void>.delayed(Duration.zero);
      expect(repository.requests, hasLength(1));
      expect(controller.state.pending?.baseRevision, 3);
      expect(controller.state.failure, PaperResetFailure.offline);
    },
  );

  test(
    'stale and no-op are definitive and require a fresh confirmation',
    () async {
      final preferences = await SharedPreferences.getInstance();
      var attempts = 0;
      final repository = _ResetRepository((_) async {
        attempts++;
        throw PaperResetException(
          attempts == 1
              ? PaperResetFailure.staleRevision
              : PaperResetFailure.notNeeded,
        );
      });
      var ids = 0;
      final controller = PaperResetController(
        principalKey: _principal,
        repository: repository,
        store: PreferencesPaperResetMutationStore(preferences),
        mutationId: () => ids++ == 0 ? _mutationA : _mutationB,
      );
      await controller.initialize();

      await expectLater(
        controller.submit(baseRevision: 2),
        throwsA(isA<PaperResetException>()),
      );
      expect(controller.state.phase, PaperResetPhase.stale);
      expect(controller.state.pending, isNull);

      await expectLater(
        controller.submit(baseRevision: 4),
        throwsA(isA<PaperResetException>()),
      );
      expect(repository.requests.last.mutationId, _mutationB);
      expect(repository.requests.last.baseRevision, 4);
      expect(controller.state.phase, PaperResetPhase.notNeeded);
      expect(controller.state.pending, isNull);
    },
  );

  test(
    'store rejects a different pending payload for the same principal',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final store = PreferencesPaperResetMutationStore(preferences);
      final first = PaperResetRequest(mutationId: _mutationA, baseRevision: 1);
      final different = PaperResetRequest(
        mutationId: _mutationB,
        baseRevision: 1,
      );
      await store.write(_principal, first);

      await expectLater(
        store.write(_principal, different),
        throwsA(
          isA<PaperResetException>().having(
            (error) => error.failure,
            'failure',
            PaperResetFailure.protectedStorage,
          ),
        ),
      );
      expect(await store.read(_principal), first);
    },
  );

  test(
    'a confirmed reset stays successful when pending cleanup fails',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final delegate = PreferencesPaperResetMutationStore(preferences);
      final controller = PaperResetController(
        principalKey: _principal,
        repository: _ResetRepository((request) async => _success(request)),
        store: _ClearFailingStore(delegate),
        mutationId: () => _mutationA,
      );
      await controller.initialize();

      final result = await controller.submit(baseRevision: 5);

      expect(result.receipt.revision, 6);
      expect(controller.state.phase, PaperResetPhase.succeeded);
      expect(controller.state.result, same(result));
      expect(controller.state.hasPendingMutation, isTrue);
      expect(controller.state.failure, isNull);

      expect(await controller.acknowledgeApplied(result), isFalse);

      expect(controller.state.failure, PaperResetFailure.protectedStorage);
      expect((await delegate.read(_principal))?.mutationId, _mutationA);
    },
  );

  test(
    'definitive error cleanup failure leaves an honest retry state',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final controller = PaperResetController(
        principalKey: _principal,
        repository: _ResetRepository((_) async {
          throw const PaperResetException(PaperResetFailure.staleRevision);
        }),
        store: _ClearFailingStore(
          PreferencesPaperResetMutationStore(preferences),
        ),
        mutationId: () => _mutationA,
      );
      await controller.initialize();

      await expectLater(
        controller.submit(baseRevision: 5),
        throwsA(
          isA<PaperResetException>().having(
            (error) => error.failure,
            'failure',
            PaperResetFailure.protectedStorage,
          ),
        ),
      );

      expect(controller.state.phase, PaperResetPhase.failed);
      expect(controller.state.hasPendingMutation, isTrue);
      expect(controller.state.failure, PaperResetFailure.protectedStorage);
      expect(controller.state.busy, isFalse);
    },
  );
}

final class _ResetRepository implements PaperResetRepository {
  _ResetRepository(this.handler);

  final Future<PaperResetResult> Function(PaperResetRequest request) handler;
  final List<PaperResetRequest> requests = [];

  @override
  Future<PaperResetResult> reset(PaperResetRequest request) {
    requests.add(request);
    return handler(request);
  }
}

final class _ClearFailingStore implements PaperResetMutationStore {
  _ClearFailingStore(this.delegate);

  final PaperResetMutationStore delegate;

  @override
  Future<PaperResetRequest?> read(String principalKey) =>
      delegate.read(principalKey);

  @override
  Future<void> write(String principalKey, PaperResetRequest request) =>
      delegate.write(principalKey, request);

  @override
  Future<void> clear(String principalKey, PaperResetRequest request) async {
    throw const PaperResetException(PaperResetFailure.protectedStorage);
  }
}

PaperResetResult _success(PaperResetRequest request) => PaperResetResult(
  request: request,
  receipt: PaperResetReceipt(
    mutationId: request.mutationId,
    previousRevision: request.baseRevision,
    revision: request.baseRevision + 1,
    resetAt: DateTime.utc(2026, 9, 20, 12),
  ),
  portfolio: PaperResetPortfolio(
    revision: request.baseRevision + 1,
    startingCashPaper: '10000',
    cashPaper: '10000',
  ),
);

PaperPortfolioSnapshot _portfolio(int revision) => PaperPortfolioSnapshot(
  revision: revision,
  startingCashPaper: '10000',
  cashPaper: '9000',
  positions: const [],
  recentOrders: const [],
  valuation: PaperPortfolioValuation.notIncluded(
    portfolioRevision: revision,
    cashPaper: '9000',
    openPositions: const [],
  ),
  openedAt: null,
  updatedAt: null,
);
