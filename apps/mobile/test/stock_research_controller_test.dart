import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/markets/stock_research.dart';

import 'support/raydium_quote_fixtures.dart';
import 'support/stock_history_fixtures.dart';
import 'support/stock_research_fixtures.dart';

final class _Pending<T> {
  _Pending(this.key, this.cancellation);

  final Object key;
  final Object? cancellation;
  final result = Completer<T>();
}

final class _HeldResearchClient implements StockResearchClient {
  final searches = <_Pending<StockSearchPage>>[];
  final variantCalls = <_Pending<StockVariantsPage>>[];
  final estimates = <_Pending<StockEstimate>>[];

  @override
  Future<StockSearchPage> search(
    String query, {
    int limit = 10,
    StockResearchCancellation? cancellation,
  }) {
    final call = _Pending<StockSearchPage>((query, limit), cancellation);
    searches.add(call);
    return call.result.future;
  }

  @override
  Future<StockVariantsPage> variants(
    String assetId, {
    StockResearchCancellation? cancellation,
  }) {
    final call = _Pending<StockVariantsPage>(assetId, cancellation);
    variantCalls.add(call);
    return call.result.future;
  }

  @override
  Future<StockEstimate> estimate(
    StockEstimateRequest request, {
    StockResearchCancellation? cancellation,
  }) {
    final call = _Pending<StockEstimate>(request, cancellation);
    estimates.add(call);
    return call.result.future;
  }
}

final class _HeldHistoryClient implements StockHistoryClient {
  final calls = <_Pending<StockHistoryPage>>[];

  @override
  Future<StockHistoryPage> history(
    StockHistoryRequest request, {
    StockResearchCancellation? cancellation,
  }) {
    final call = _Pending<StockHistoryPage>(request, cancellation);
    calls.add(call);
    return call.result.future;
  }
}

final class _HeldRaydiumClient implements RaydiumQuoteClient {
  final calls = <_Pending<RaydiumStockQuote>>[];

  @override
  Future<RaydiumStockQuote> quote(
    RaydiumQuoteRequest request, {
    RaydiumQuoteCancellation? cancellation,
  }) {
    final call = _Pending<RaydiumStockQuote>(request, cancellation);
    calls.add(call);
    return call.result.future;
  }
}

final class _ManualTimer implements Timer {
  var active = true;

  @override
  void cancel() => active = false;

  @override
  bool get isActive => active;

  @override
  int get tick => active ? 0 : 1;
}

final class _InactiveTimer implements Timer {
  @override
  void cancel() {}

  @override
  bool get isActive => false;

  @override
  int get tick => 0;
}

const _jupiterBuy = StockEstimateRequest(
  assetId: 'apple',
  variantMint: researchAaplxMint,
  side: StockEstimateSide.buy,
  amountRaw: '10000000',
);

Matcher _runtimeFailure(String value) =>
    isA<StockResearchException>().having((error) => error.code, 'code', value);

void main() {
  late DateTime now;
  late _HeldResearchClient researchClient;
  late _HeldHistoryClient historyClient;
  late _HeldRaydiumClient raydiumClient;
  late StockResearchController subject;

  setUp(() {
    now = DateTime.parse('2026-09-14T18:00:02.000Z');
    researchClient = _HeldResearchClient();
    historyClient = _HeldHistoryClient();
    raydiumClient = _HeldRaydiumClient();
    subject = StockResearchController.withClients(
      researchClient: researchClient,
      historyClient: historyClient,
      raydiumClient: raydiumClient,
      clock: () => now,
    );
  });

  tearDown(() => subject.dispose());

  test(
    'configured channels remain separate and retain their provenance',
    () async {
      final search = subject.search('Apple');
      final variants = subject.loadVariants('apple');
      final jupiter = subject.loadJupiterEstimate(_jupiterBuy);
      final history = subject.loadTokensHistory(stockHistoryRequest);
      final raydium = subject.loadRaydiumComparison(raydiumBuyRequest);

      researchClient.searches.single.result.complete(
        StockSearchPage.fromJson(stockSearchFixture()),
      );
      researchClient.variantCalls.single.result.complete(
        StockVariantsPage.fromJson(stockVariantsFixture()),
      );
      researchClient.estimates.single.result.complete(
        StockEstimate.fromJson(stockEstimateFixture()),
      );
      historyClient.calls.single.result.complete(parsedStockHistory());
      raydiumClient.calls.single.result.complete(parsedRaydiumQuote());
      await Future.wait([search, variants, jupiter, history, raydium]);

      final state = subject.state;
      expect(state.phase, StockResearchRuntimePhase.active);
      expect(state.discovery.search.phase, StockResearchReadPhase.ready);
      expect(state.discovery.variants.phase, StockResearchReadPhase.ready);
      expect(state.jupiterEstimate.data!.provider, 'jupiter-swap-v2');
      expect(state.tokensHistory.data!.provider, 'tokens-xyz-v1');
      expect(state.raydiumComparison.data!.provider, 'raydium-trade-api');
      expect(state.jupiterEstimate.data, isNot(state.raydiumComparison.data));
      expect(subject.capabilities.publicReads, isTrue);
      expect(subject.capabilities.walletAccess, isFalse);
      expect(subject.capabilities.transactionConstruction, isFalse);
      expect(subject.capabilities.simulation, isFalse);
      expect(subject.capabilities.signing, isFalse);
      expect(subject.capabilities.broadcast, isFalse);
      expect(subject.capabilities.execution, isFalse);
    },
  );

  test(
    'identical concurrent requests share one future and one client read',
    () async {
      final searchA = subject.search('Apple');
      final searchB = subject.search('Apple');
      final variantsA = subject.loadVariants('apple');
      final variantsB = subject.loadVariants('apple');
      final jupiterA = subject.loadJupiterEstimate(_jupiterBuy);
      final jupiterB = subject.loadJupiterEstimate(_jupiterBuy);
      final historyA = subject.loadTokensHistory(stockHistoryRequest);
      final historyB = subject.loadTokensHistory(stockHistoryRequest);
      final raydiumA = subject.loadRaydiumComparison(raydiumBuyRequest);
      final raydiumB = subject.loadRaydiumComparison(raydiumBuyRequest);

      expect(searchB, same(searchA));
      expect(variantsB, same(variantsA));
      expect(jupiterB, same(jupiterA));
      expect(historyB, same(historyA));
      expect(raydiumB, same(raydiumA));
      expect(researchClient.searches, hasLength(1));
      expect(researchClient.variantCalls, hasLength(1));
      expect(researchClient.estimates, hasLength(1));
      expect(historyClient.calls, hasLength(1));
      expect(raydiumClient.calls, hasLength(1));

      researchClient.searches.single.result.complete(
        StockSearchPage.fromJson(stockSearchFixture()),
      );
      researchClient.variantCalls.single.result.complete(
        StockVariantsPage.fromJson(stockVariantsFixture()),
      );
      researchClient.estimates.single.result.complete(
        StockEstimate.fromJson(stockEstimateFixture()),
      );
      historyClient.calls.single.result.complete(parsedStockHistory());
      raydiumClient.calls.single.result.complete(parsedRaydiumQuote());
      await Future.wait([searchA, variantsA, jupiterA, historyA, raydiumA]);
    },
  );

  test(
    'background cancels reads, masks late callbacks, and resume is quiet',
    () async {
      final search = subject.search('Apple');
      final jupiter = subject.loadJupiterEstimate(_jupiterBuy);
      final history = subject.loadTokensHistory(stockHistoryRequest);
      final raydium = subject.loadRaydiumComparison(raydiumBuyRequest);
      subject.setForeground(false);

      expect(subject.state.phase, StockResearchRuntimePhase.background);
      expect(
        subject.discoveryState.search.phase,
        StockResearchReadPhase.background,
      );
      expect(
        (researchClient.searches.single.cancellation!
                as StockResearchCancellation)
            .isCancelled,
        isTrue,
      );
      expect(
        (researchClient.estimates.single.cancellation!
                as StockResearchCancellation)
            .isCancelled,
        isTrue,
      );
      expect(
        (historyClient.calls.single.cancellation! as StockResearchCancellation)
            .isCancelled,
        isTrue,
      );
      expect(
        (raydiumClient.calls.single.cancellation! as RaydiumQuoteCancellation)
            .isCancelled,
        isTrue,
      );
      await Future.wait([search, jupiter, history, raydium]);

      researchClient.searches.single.result.complete(
        StockSearchPage.fromJson(stockSearchFixture()),
      );
      researchClient.estimates.single.result.complete(
        StockEstimate.fromJson(stockEstimateFixture()),
      );
      historyClient.calls.single.result.complete(parsedStockHistory());
      raydiumClient.calls.single.result.complete(parsedRaydiumQuote());
      await Future<void>.delayed(Duration.zero);
      expect(subject.discoveryState.search.data, isNull);
      expect(subject.jupiterEstimateState.data, isNull);
      expect(subject.tokensHistoryState.data, isNull);
      expect(subject.raydiumComparisonState.data, isNull);

      subject.setForeground(true);
      expect(researchClient.searches, hasLength(1));
      expect(researchClient.estimates, hasLength(1));
      expect(historyClient.calls, hasLength(1));
      expect(raydiumClient.calls, hasLength(1));
      expect(subject.state.phase, StockResearchRuntimePhase.active);
    },
  );

  test('offline and reconnect transitions never fetch automatically', () async {
    subject.setNetworkAvailable(false);
    expect(subject.state.phase, StockResearchRuntimePhase.offline);
    expect(subject.discoveryState.search.phase, StockResearchReadPhase.offline);
    await expectLater(
      subject.search('Apple'),
      throwsA(_runtimeFailure('STOCK_RESEARCH_RUNTIME_OFFLINE')),
    );
    expect(researchClient.searches, isEmpty);

    subject.setNetworkAvailable(true);
    expect(subject.state.phase, StockResearchRuntimePhase.active);
    expect(researchClient.searches, isEmpty);
    final pending = subject.search('Apple');
    expect(researchClient.searches, hasLength(1));
    researchClient.searches.single.result.complete(
      StockSearchPage.fromJson(stockSearchFixture()),
    );
    await pending;
  });

  test(
    'disabled guest configuration never constructs a transport or reads',
    () async {
      subject.dispose();
      var transportFactories = 0;
      subject = StockResearchController.create(
        config: StockResearchConfig.parse(apiUrl: ''),
        httpClientFactory: () {
          transportFactories++;
          return MockClient((_) async => throw StateError('must not dispatch'));
        },
      );

      expect(subject.enabled, isFalse);
      expect(subject.state.phase, StockResearchRuntimePhase.disabled);
      expect(
        subject.discoveryState.search.phase,
        StockResearchReadPhase.disabled,
      );
      expect(
        subject.jupiterEstimateState.phase,
        StockResearchReadPhase.disabled,
      );
      expect(subject.tokensHistoryState.phase, StockResearchReadPhase.disabled);
      expect(
        subject.raydiumComparisonState.phase,
        StockResearchReadPhase.disabled,
      );
      await expectLater(
        subject.loadJupiterEstimate(_jupiterBuy),
        throwsA(_runtimeFailure('STOCK_RESEARCH_RUNTIME_DISABLED')),
      );
      subject.setForeground(false);
      subject.setNetworkAvailable(false);
      expect(transportFactories, 0);
    },
  );

  test('clock failure is contained and prevents every client call', () async {
    subject.dispose();
    subject = StockResearchController.withClients(
      researchClient: researchClient,
      historyClient: historyClient,
      raydiumClient: raydiumClient,
      clock: () => throw StateError('private clock failure'),
    );

    expect(subject.state.phase, StockResearchRuntimePhase.invalidConfiguration);
    expect(subject.discoveryState.search.phase, StockResearchReadPhase.error);
    await expectLater(
      subject.search('Apple'),
      throwsA(_runtimeFailure('STOCK_RESEARCH_RUNTIME_CLOCK_INVALID')),
    );
    await expectLater(
      subject.loadTokensHistory(stockHistoryRequest),
      throwsA(_runtimeFailure('STOCK_RESEARCH_RUNTIME_CLOCK_INVALID')),
    );
    await expectLater(
      subject.loadRaydiumComparison(raydiumBuyRequest),
      throwsA(_runtimeFailure('STOCK_RESEARCH_RUNTIME_CLOCK_INVALID')),
    );
    expect(researchClient.searches, isEmpty);
    expect(historyClient.calls, isEmpty);
    expect(raydiumClient.calls, isEmpty);
  });

  test(
    'captured states expire independently and contain later clock failure',
    () async {
      final jupiter = subject.loadJupiterEstimate(_jupiterBuy);
      final history = subject.loadTokensHistory(stockHistoryRequest);
      final raydium = subject.loadRaydiumComparison(raydiumBuyRequest);
      researchClient.estimates.single.result.complete(
        StockEstimate.fromJson(stockEstimateFixture()),
      );
      historyClient.calls.single.result.complete(parsedStockHistory());
      raydiumClient.calls.single.result.complete(parsedRaydiumQuote());
      await Future.wait([jupiter, history, raydium]);
      final captured = subject.state;

      now = DateTime.parse('2026-09-14T18:00:10.000Z');
      expect(captured.jupiterEstimate.phase, StockResearchReadPhase.stale);
      expect(captured.jupiterEstimate.errorCode, 'STOCK_RESEARCH_DATA_STALE');
      expect(captured.raydiumComparison.phase, StockResearchReadPhase.stale);
      expect(captured.tokensHistory.phase, StockResearchReadPhase.ready);

      subject.dispose();
      var clockFails = false;
      subject = StockResearchController.withClients(
        researchClient: _HeldResearchClient(),
        historyClient: _HeldHistoryClient(),
        raydiumClient: _HeldRaydiumClient(),
        clock: () {
          if (clockFails) throw StateError('private clock failure');
          return DateTime.parse('2026-09-14T18:00:02.000Z');
        },
      );
      final stateBeforeFailure = subject.state.discovery.search;
      clockFails = true;
      expect(() => stateBeforeFailure.phase, returnsNormally);
      // Idle data has no freshness assertion; the runtime itself still fails
      // closed as soon as the broken clock is observed.
      expect(
        subject.state.phase,
        StockResearchRuntimePhase.invalidConfiguration,
      );
    },
  );

  test(
    'close settles exposed work and rejects late results permanently',
    () async {
      final pending = subject.search('Apple');
      var notifications = 0;
      subject.addListener(() => notifications++);
      subject.close();
      await pending;
      final afterClose = notifications;
      expect(subject.state.phase, StockResearchRuntimePhase.closed);

      researchClient.searches.single.result.complete(
        StockSearchPage.fromJson(stockSearchFixture()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(notifications, afterClose);
      expect(subject.discoveryState.search.data, isNull);
      await expectLater(
        subject.search('Apple'),
        throwsA(_runtimeFailure('STOCK_RESEARCH_RUNTIME_CLOSED')),
      );
    },
  );

  test(
    'a synchronous timer adapter fails closed without rescheduling',
    () async {
      subject.dispose();
      var timerCalls = 0;
      subject = StockResearchController.withClients(
        researchClient: researchClient,
        historyClient: historyClient,
        raydiumClient: raydiumClient,
        clock: () => now,
        timerFactory: (_, callback) {
          timerCalls++;
          callback();
          return _ManualTimer();
        },
      );

      final pending = subject.loadJupiterEstimate(_jupiterBuy);
      researchClient.estimates.single.result.complete(
        StockEstimate.fromJson(stockEstimateFixture()),
      );
      await pending;

      expect(timerCalls, 1);
      expect(
        subject.state.phase,
        StockResearchRuntimePhase.invalidConfiguration,
      );
      expect(subject.state.errorCode, 'STOCK_RESEARCH_RUNTIME_TIMER_INVALID');
      expect(subject.jupiterEstimateState.phase, StockResearchReadPhase.error);
    },
  );

  test('an inactive timer adapter fails the whole runtime closed', () async {
    subject.dispose();
    subject = StockResearchController.withClients(
      researchClient: researchClient,
      historyClient: historyClient,
      raydiumClient: raydiumClient,
      clock: () => now,
      timerFactory: (_, _) => _InactiveTimer(),
    );

    final pending = subject.loadJupiterEstimate(_jupiterBuy);
    researchClient.estimates.single.result.complete(
      StockEstimate.fromJson(stockEstimateFixture()),
    );
    await pending;

    expect(subject.state.phase, StockResearchRuntimePhase.invalidConfiguration);
    expect(subject.state.errorCode, 'STOCK_RESEARCH_RUNTIME_TIMER_INVALID');
    await expectLater(
      subject.search('Apple'),
      throwsA(_runtimeFailure('STOCK_RESEARCH_RUNTIME_TIMER_INVALID')),
    );
    expect(researchClient.searches, isEmpty);
  });

  test(
    'configured API origin is immutable and exact across runtime creation',
    () async {
      subject.dispose();
      final seen = <Uri>[];
      subject = StockResearchController.create(
        config: StockResearchConfig.parse(apiUrl: 'https://one.example'),
        httpClientFactory: () => MockClient((request) async {
          seen.add(request.url);
          return http.Response(
            jsonEncode(stockSearchFixture()),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        clock: () => now,
      );
      expect(subject.apiOrigin, Uri.parse('https://one.example'));
      await subject.search('Apple');
      expect(
        seen.single,
        Uri.parse(
          'https://one.example/v1/markets/stocks/search?query=Apple&limit=10',
        ),
      );

      subject.close();
      expect(subject.apiOrigin, Uri.parse('https://one.example'));
      final replacement = StockResearchController.create(
        config: StockResearchConfig.parse(apiUrl: 'https://two.example'),
        httpClientFactory: () => MockClient((_) async {
          throw StateError('replacement should stay idle');
        }),
        clock: () => now,
      );
      addTearDown(replacement.dispose);
      expect(replacement.apiOrigin, Uri.parse('https://two.example'));
      expect(replacement.state.phase, StockResearchRuntimePhase.active);
    },
  );
}
