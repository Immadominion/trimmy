import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/markets/stock_research.dart';
import 'support/stock_research_fixtures.dart';

class Pending<T> {
  Pending(this.key, this.cancellation);
  final Object key;
  final StockResearchCancellation? cancellation;
  final result = Completer<T>();
}

class HeldResearchClient implements StockResearchClient {
  final searches = <Pending<StockSearchPage>>[];
  final variantsCalls = <Pending<StockVariantsPage>>[];
  final estimates = <Pending<StockEstimate>>[];
  @override
  Future<StockSearchPage> search(
    String query, {
    int limit = 10,
    StockResearchCancellation? cancellation,
  }) {
    final call = Pending<StockSearchPage>((query, limit), cancellation);
    searches.add(call);
    return call.result.future;
  }

  @override
  Future<StockVariantsPage> variants(
    String assetId, {
    StockResearchCancellation? cancellation,
  }) {
    final call = Pending<StockVariantsPage>(assetId, cancellation);
    variantsCalls.add(call);
    return call.result.future;
  }

  @override
  Future<StockEstimate> estimate(
    StockEstimateRequest request, {
    StockResearchCancellation? cancellation,
  }) {
    final call = Pending<StockEstimate>(request, cancellation);
    estimates.add(call);
    return call.result.future;
  }
}

StockResearchRepository _buildRepository(
  HeldResearchClient client, {
  DateTime Function()? now,
}) => StockResearchRepository(
  client: client,
  now: now ?? () => DateTime.parse('2026-09-14T18:00:02.000Z'),
);

void main() {
  test('clock failure rejects before a research client read', () async {
    final client = HeldResearchClient();
    final repository = _buildRepository(
      client,
      now: () => throw StateError('private clock failure'),
    );
    addTearDown(repository.dispose);

    await expectLater(
      repository.search('Apple'),
      throwsA(
        isA<StockResearchException>().having(
          (error) => error.code,
          'code',
          'STOCK_INVALID_CONFIGURATION',
        ),
      ),
    );
    expect(client.searches, isEmpty);
    expect(repository.searchState.phase, StockResearchPhase.error);
    expect(repository.searchState.errorCode, 'STOCK_INVALID_CONFIGURATION');
  });

  test('a later clock failure cancels every active research channel', () async {
    final client = HeldResearchClient();
    var clockFails = false;
    final repository = _buildRepository(
      client,
      now: () {
        if (clockFails) throw StateError('private clock failure');
        return DateTime.parse('2026-09-14T18:00:02.000Z');
      },
    );
    addTearDown(repository.dispose);

    final search = repository.search('Apple');
    expect(client.searches, hasLength(1));
    clockFails = true;
    await expectLater(
      repository.loadVariants('apple'),
      throwsA(
        isA<StockResearchException>().having(
          (error) => error.code,
          'code',
          'STOCK_INVALID_CONFIGURATION',
        ),
      ),
    );

    expect(client.searches.single.cancellation!.isCancelled, isTrue);
    expect(client.variantsCalls, isEmpty);
    expect(repository.searchState.phase, StockResearchPhase.error);
    expect(repository.variantsState.phase, StockResearchPhase.error);
    client.searches.single.result.complete(
      StockSearchPage.fromJson(stockSearchFixture()),
    );
    await search;
    expect(repository.searchState.data, isNull);
  });

  test(
    'captured ready state becomes stale and contains clock failures',
    () async {
      final client = HeldResearchClient();
      var now = DateTime.parse('2026-09-14T18:00:02.000Z');
      var clockFails = false;
      final repository = _buildRepository(
        client,
        now: () {
          if (clockFails) throw StateError('private clock failure');
          return now;
        },
      );
      addTearDown(repository.dispose);

      final pending = repository.search('Apple');
      client.searches.single.result.complete(
        StockSearchPage.fromJson(stockSearchFixture()),
      );
      await pending;
      final captured = repository.searchState;
      expect(captured.phase, StockResearchPhase.ready);

      now = DateTime.parse('2026-09-14T18:01:00.000Z');
      expect(captured.phase, StockResearchPhase.stale);
      expect(captured.errorCode, 'STOCK_TIMEOUT');
      expect(captured.hasRetainedData, isTrue);

      clockFails = true;
      expect(() => captured.phase, returnsNormally);
      expect(captured.phase, StockResearchPhase.error);
      expect(captured.errorCode, 'STOCK_INVALID_CONFIGURATION');
      expect(
        captured.needsRefresh(DateTime.parse('2026-09-14T18:00:02.000Z')),
        isTrue,
      );
    },
  );

  test(
    'a loading listener may cancel before any client work is dispatched',
    () async {
      final client = HeldResearchClient();
      final repository = _buildRepository(client);
      addTearDown(repository.dispose);
      repository.addListener(() {
        if (repository.searchState.phase == StockResearchPhase.loading) {
          repository.cancelSearch();
        }
      });
      await repository.search('Apple');
      expect(client.searches, isEmpty);
      expect(repository.searchState.phase, StockResearchPhase.cancelled);
    },
  );

  test(
    'new search cancels old query and ignored cancellation cannot replace newer results',
    () async {
      final client = HeldResearchClient();
      final repository = _buildRepository(client);
      addTearDown(repository.dispose);
      final first = repository.search('Apple');
      final second = repository.search('Apple stock');
      expect(client.searches.first.cancellation!.isCancelled, isTrue);
      client.searches.last.result.complete(
        StockSearchPage.fromJson(stockSearchFixture(query: 'Apple stock')),
      );
      await second;
      client.searches.first.result.complete(
        StockSearchPage.fromJson(stockSearchFixture()),
      );
      await first;
      expect(repository.searchState.phase, StockResearchPhase.ready);
      expect(repository.searchState.data!.query, 'Apple stock');
      expect(repository.searchState.requestKey, ('Apple stock', 10));
    },
  );

  test(
    'same-query failed refresh retains explicitly stale data; different query never inherits it',
    () async {
      final client = HeldResearchClient();
      final repository = _buildRepository(client);
      addTearDown(repository.dispose);
      final first = repository.search('Apple');
      final original = StockSearchPage.fromJson(stockSearchFixture());
      client.searches.last.result.complete(original);
      await first;
      final retry = repository.search('Apple');
      expect(repository.searchState.phase, StockResearchPhase.loading);
      expect(repository.searchState.hasRetainedData, isTrue);
      client.searches.last.result.completeError(
        const StockResearchException('STOCK_NETWORK_ERROR'),
      );
      await retry;
      expect(repository.searchState.phase, StockResearchPhase.offline);
      expect(repository.searchState.data, same(original));
      expect(
        repository.searchState.needsRefresh(
          DateTime.parse('2026-09-14T18:00:10Z'),
        ),
        isTrue,
      );
      final other = repository.search('Tesla');
      expect(repository.searchState.data, isNull);
      client.searches.last.result.completeError(
        const StockResearchException('STOCK_PROVIDER_AUTH_FAILED'),
      );
      await other;
      expect(repository.searchState.phase, StockResearchPhase.error);
      expect(repository.searchState.errorCode, 'STOCK_PROVIDER_AUTH_FAILED');
    },
  );

  test(
    'channels are independent and no successful search clears a failed estimate',
    () async {
      final client = HeldResearchClient();
      final repository = _buildRepository(client);
      addTearDown(repository.dispose);
      final search = repository.search('Apple');
      final variants = repository.loadVariants('apple');
      const request = StockEstimateRequest(
        assetId: 'apple',
        variantMint: researchAaplxMint,
        side: StockEstimateSide.buy,
        amountRaw: '10000000',
      );
      final estimate = repository.estimate(request);
      client.estimates.single.result.completeError(
        const StockResearchException('MARKET_RATE_LIMITED'),
      );
      await estimate;
      client.variantsCalls.single.result.complete(
        StockVariantsPage.fromJson(stockVariantsFixture()),
      );
      await variants;
      client.searches.single.result.complete(
        StockSearchPage.fromJson(stockSearchFixture()),
      );
      await search;
      expect(repository.searchState.phase, StockResearchPhase.ready);
      expect(repository.variantsState.data!.assetId, 'apple');
      expect(repository.estimateState.phase, StockResearchPhase.error);
      expect(repository.estimateState.errorCode, 'MARKET_RATE_LIMITED');
      expect(repository.estimateState.data, isNull);
    },
  );

  test(
    'foreground network signal cancels in-flight reads and requires explicit retry',
    () async {
      final client = HeldResearchClient();
      final repository = _buildRepository(client);
      addTearDown(repository.dispose);
      final pending = repository.search('Apple');
      repository.setNetworkAvailable(false);
      expect(repository.searchState.phase, StockResearchPhase.offline);
      expect(client.searches.single.cancellation!.isCancelled, isTrue);
      client.searches.single.result.complete(
        StockSearchPage.fromJson(stockSearchFixture()),
      );
      await pending;
      expect(repository.searchState.data, isNull);
      await repository.search('Apple');
      expect(client.searches.length, 1);
      repository.setNetworkAvailable(true);
      expect(client.searches.length, 1);
      expect(repository.searchState.phase, StockResearchPhase.offline);
      final retry = repository.search('Apple');
      client.searches.last.result.complete(
        StockSearchPage.fromJson(stockSearchFixture()),
      );
      await retry;
      expect(repository.searchState.phase, StockResearchPhase.ready);
    },
  );

  test(
    'explicit cancellation and disposal reject late updates without listener leaks',
    () async {
      final client = HeldResearchClient();
      final repository = _buildRepository(client);
      var notifications = 0;
      repository.addListener(() {
        notifications++;
      });
      final pending = repository.search('Apple');
      repository.cancelSearch();
      expect(repository.searchState.phase, StockResearchPhase.cancelled);
      client.searches.single.result.complete(
        StockSearchPage.fromJson(stockSearchFixture()),
      );
      await pending;
      expect(repository.searchState.data, isNull);
      final variants = repository.loadVariants('apple');
      final before = notifications;
      repository.dispose();
      expect(client.variantsCalls.single.cancellation!.isCancelled, isTrue);
      client.variantsCalls.single.result.complete(
        StockVariantsPage.fromJson(stockVariantsFixture()),
      );
      await variants;
      expect(notifications, before);
      await expectLater(
        repository.search('Apple'),
        throwsA(
          isA<StockResearchException>().having(
            (e) => e.code,
            'code',
            'STOCK_REPOSITORY_CLOSED',
          ),
        ),
      );
    },
  );

  test(
    'estimate refresh preserves raw amounts but marks old result stale during timeout',
    () async {
      final client = HeldResearchClient();
      final repository = _buildRepository(client);
      addTearDown(repository.dispose);
      const request = StockEstimateRequest(
        assetId: 'apple',
        variantMint: researchAaplxMint,
        side: StockEstimateSide.buy,
        amountRaw: '10000000',
      );
      final first = repository.estimate(request);
      client.estimates.last.result.complete(
        StockEstimate.fromJson(stockEstimateFixture()),
      );
      await first;
      expect(
        repository.estimateState.needsRefresh(
          DateTime.parse('2026-09-14T18:00:10Z'),
        ),
        isTrue,
      );
      final retry = repository.estimate(request);
      client.estimates.last.result.completeError(
        const StockResearchException('STOCK_TIMEOUT'),
      );
      await retry;
      expect(repository.estimateState.phase, StockResearchPhase.error);
      expect(repository.estimateState.hasRetainedData, isTrue);
      expect(
        repository.estimateState.data!.output.estimatedAmountRaw,
        '18446744073709551615',
      );
    },
  );

  test(
    'a discovery result expiring while its request is in flight is never ready',
    () async {
      final client = HeldResearchClient();
      var now = DateTime.parse('2026-09-14T18:00:02.000Z');
      final repository = _buildRepository(client, now: () => now);
      addTearDown(repository.dispose);

      final pending = repository.search('Apple');
      expect(repository.searchState.phase, StockResearchPhase.loading);
      now = DateTime.parse('2026-09-14T18:01:00.000Z');
      client.searches.single.result.complete(
        StockSearchPage.fromJson(stockSearchFixture()),
      );
      await pending;

      expect(repository.searchState.phase, StockResearchPhase.error);
      expect(repository.searchState.errorCode, 'STOCK_TIMEOUT');
      expect(repository.searchState.data, isNull);
      expect(repository.searchState.refreshAfter, isNull);
    },
  );

  test(
    'an estimate reaching refreshAfter while in flight is never ready',
    () async {
      final client = HeldResearchClient();
      var now = DateTime.parse('2026-09-14T18:00:02.000Z');
      final repository = _buildRepository(client, now: () => now);
      addTearDown(repository.dispose);

      final pending = repository.estimate(
        const StockEstimateRequest(
          assetId: 'apple',
          variantMint: researchAaplxMint,
          side: StockEstimateSide.buy,
          amountRaw: '10000000',
        ),
      );
      expect(repository.estimateState.phase, StockResearchPhase.loading);
      now = DateTime.parse('2026-09-14T18:00:10.000Z');
      client.estimates.single.result.complete(
        StockEstimate.fromJson(stockEstimateFixture()),
      );
      await pending;

      expect(repository.estimateState.phase, StockResearchPhase.error);
      expect(repository.estimateState.errorCode, 'MARKET_ESTIMATE_STALE');
      expect(repository.estimateState.data, isNull);
      expect(repository.estimateState.refreshAfter, isNull);
    },
  );
}
