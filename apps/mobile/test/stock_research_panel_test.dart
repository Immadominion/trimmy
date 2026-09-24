import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/design_study/craft.dart';
import 'package:trimmy/markets/stock_research.dart';
import 'package:trimmy/markets/stock_research_panel.dart';

import 'support/stock_research_fixtures.dart';

/// Answers discovery from fixtures and records what was asked for. History and
/// quotes are never reached, because this panel only searches.
final class _ScriptedResearchClient implements StockResearchClient {
  _ScriptedResearchClient({this.searchError, this.results = 1});

  final Object? searchError;
  final int results;
  final searches = <(String, int)>[];
  final variantReads = <String>[];
  Map<String, Object?> Function(String query, int limit)? searchResponse;
  Map<String, Object?> Function(String assetId)? variantsResponse;
  Completer<void>? searchGate;
  Completer<void>? variantsGate;

  @override
  Future<StockSearchPage> search(
    String query, {
    int limit = 10,
    StockResearchCancellation? cancellation,
  }) async {
    searches.add((query, limit));
    await searchGate?.future;
    final error = searchError;
    if (error != null) throw error;
    final page =
        searchResponse?.call(query, limit) ??
        stockSearchFixture(query: query, limit: limit);
    if (results == 0) page['results'] = const <Object?>[];
    return StockSearchPage.fromJson(page);
  }

  @override
  Future<StockVariantsPage> variants(
    String assetId, {
    StockResearchCancellation? cancellation,
  }) async {
    variantReads.add(assetId);
    await variantsGate?.future;
    return StockVariantsPage.fromJson(
      variantsResponse?.call(assetId) ?? stockVariantsFixture(assetId: assetId),
    );
  }

  @override
  Future<StockEstimate> estimate(
    StockEstimateRequest request, {
    StockResearchCancellation? cancellation,
  }) async => throw StateError('The panel must not request an estimate.');
}

/// Expiry is scheduled, never fired by a platform clock, and fired by the test
/// when it wants the runtime to notice that a reading has aged out.
final class _HeldTimer implements Timer {
  _HeldTimer(this.callback);

  final void Function() callback;
  var active = true;

  @override
  void cancel() => active = false;

  @override
  bool get isActive => active;

  @override
  int get tick => active ? 0 : 1;
}

final class _UnusedHistoryClient implements StockHistoryClient {
  @override
  Future<StockHistoryPage> history(
    StockHistoryRequest request, {
    StockResearchCancellation? cancellation,
  }) async => throw StateError('The panel must not request history.');
}

final class _UnusedRaydiumClient implements RaydiumQuoteClient {
  @override
  Future<RaydiumStockQuote> quote(
    RaydiumQuoteRequest request, {
    RaydiumQuoteCancellation? cancellation,
  }) async => throw StateError('The panel must not request a venue quote.');
}

Widget _panelApp(
  StockResearchController controller, {
  bool configurationFailed = false,
  TextScaler textScaler = TextScaler.noScaling,
}) => MaterialApp(
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: textScaler),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: StockResearchPanel(
          controller: controller,
          configurationFailed: configurationFailed,
        ),
      ),
    ),
  ),
);

Future<
  ({
    StockResearchController controller,
    _ScriptedResearchClient client,
    void Function(String) advanceTo,
    void Function() expire,
  })
>
_mount(
  WidgetTester tester, {
  Object? searchError,
  int results = 1,
  String at = '2026-09-14T18:00:02.000Z',
  bool configurationFailed = false,
  bool disabled = false,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  final client = _ScriptedResearchClient(
    searchError: searchError,
    results: results,
  );
  var now = DateTime.parse(at);
  final timers = <_HeldTimer>[];
  final controller = disabled
      ? StockResearchController.create(
          config: StockResearchConfig.parse(apiUrl: ''),
        )
      : StockResearchController.withClients(
          researchClient: client,
          historyClient: _UnusedHistoryClient(),
          raydiumClient: _UnusedRaydiumClient(),
          clock: () => now,
          timerFactory: (delay, callback) {
            final timer = _HeldTimer(callback);
            timers.add(timer);
            return timer;
          },
        );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    _panelApp(
      controller,
      configurationFailed: configurationFailed,
      textScaler: textScaler,
    ),
  );
  await tester.pumpAndSettle();
  return (
    controller: controller,
    client: client,
    advanceTo: (String instant) => now = DateTime.parse(instant),
    expire: () {
      for (final timer in timers.where((timer) => timer.isActive).toList()) {
        timer.callback();
      }
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('opening the panel reads nothing until a search is asked for', (
    tester,
  ) async {
    final mounted = await _mount(tester);
    expect(mounted.client.searches, isEmpty);
    expect(mounted.client.variantReads, isEmpty);
    expect(find.textContaining('Explore stocks on Solana'), findsOne);
    expect(find.byKey(const ValueKey('stock-research-search')), findsOne);
  });

  testWidgets('an empty box is refused without reaching the provider', (
    tester,
  ) async {
    final mounted = await _mount(tester);
    await tester.tap(find.byKey(const ValueKey('stock-research-search')));
    await tester.pumpAndSettle();
    expect(mounted.client.searches, isEmpty);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('stock-research-refused')))
          .data,
      'Type a company name or symbol first.',
    );
  });

  testWidgets('a search shows the provider reading and says what it is not', (
    tester,
  ) async {
    final mounted = await _mount(tester);
    await tester.enterText(
      find.byKey(const ValueKey('stock-research-query')),
      'Apple',
    );
    await tester.tap(find.byKey(const ValueKey('stock-research-search')));
    await tester.pumpAndSettle();
    expect(mounted.client.searches, [('Apple', 10)]);
    expect(find.text('Apple (AAPL)'), findsOne);
    expect(find.text('Apple xStock'), findsOne);
    expect(find.text('Issued by Backed'), findsOne);
    expect(find.text('Price \$200.50'), findsOne);
    expect(find.text('Liquidity \$100,000'), findsOne);
    expect(find.text('Traded in a day \$15,000'), findsOne);
    // The provenance asserts all of this, so the panel states it.
    expect(find.textContaining('not a full list'), findsOne);
    expect(find.textContaining('not a price you could trade at'), findsOne);
  });

  testWidgets(
    'prices preserve cents above a thousand and tiny metrics stay positive',
    (tester) async {
      final mounted = await _mount(tester);
      mounted.client.searchResponse = (query, limit) {
        final page = stockSearchFixture(query: query, limit: limit);
        final asset = (page['results'] as List).single as Map<String, Object?>;
        final variant =
            (asset['variants'] as List).single as Map<String, Object?>;
        final market = variant['market'] as Map<String, Object?>;
        market['priceUsd'] = 1234.56;
        market['liquidityUsd'] = 0.00000001;
        market['volume24hUsd'] = 0;
        return page;
      };
      await tester.enterText(
        find.byKey(const ValueKey('stock-research-query')),
        'Apple',
      );
      await tester.tap(find.byKey(const ValueKey('stock-research-search')));
      await tester.pumpAndSettle();
      expect(find.text('Price \$1,234.56'), findsOne);
      expect(find.text('Liquidity <\$0.0001'), findsOne);
      expect(find.text('Traded in a day \$0'), findsOne);
    },
  );

  testWidgets('a tiny price and a missing metric cannot look like zero', (
    tester,
  ) async {
    final mounted = await _mount(tester);
    mounted.client.searchResponse = (query, limit) {
      final page = stockSearchFixture(query: query, limit: limit);
      final asset = (page['results'] as List).single as Map<String, Object?>;
      final variant =
          (asset['variants'] as List).single as Map<String, Object?>;
      final market = variant['market'] as Map<String, Object?>;
      market['priceUsd'] = 0.00000001;
      market['liquidityUsd'] = null;
      market['volume24hUsd'] = 100000.75;
      return page;
    };
    await tester.enterText(
      find.byKey(const ValueKey('stock-research-query')),
      'Apple',
    );
    await tester.tap(find.byKey(const ValueKey('stock-research-search')));
    await tester.pumpAndSettle();
    expect(find.text('Price <\$0.0001'), findsOne);
    expect(find.text('Liquidity not given'), findsOne);
    expect(find.text('Traded in a day \$100,000.75'), findsOne);
  });

  testWidgets('no control in the panel can buy, sell or size an order', (
    tester,
  ) async {
    await _mount(tester);
    await tester.enterText(
      find.byKey(const ValueKey('stock-research-query')),
      'Apple',
    );
    await tester.tap(find.byKey(const ValueKey('stock-research-search')));
    await tester.pumpAndSettle();
    // Every control the panel offers, by the words on it.
    final labels = <String>[
      ...tester
          .widgetList<CraftButton>(find.byType(CraftButton))
          .map((button) => button.label),
      ...tester
          .widgetList<TextButton>(find.byType(TextButton))
          .map((button) => (button.child as Text?)?.data ?? ''),
    ];
    expect(labels, isNotEmpty);
    for (final label in labels) {
      for (final word in const [
        'buy',
        'sell',
        'amount',
        'order',
        'trade',
        'swap',
        'confirm',
      ]) {
        expect(
          label.toLowerCase(),
          isNot(contains(word)),
          reason: 'a read-only panel offered a control saying "$label"',
        );
      }
    }
    // One field only, and it is the search box.
    expect(find.byType(TextField), findsOne);
    expect(find.byKey(const ValueKey('stock-research-query')), findsOne);
  });

  testWidgets('every version is a second, explicit read', (tester) async {
    final mounted = await _mount(tester);
    await tester.enterText(
      find.byKey(const ValueKey('stock-research-query')),
      'Apple',
    );
    await tester.tap(find.byKey(const ValueKey('stock-research-search')));
    await tester.pumpAndSettle();
    expect(mounted.client.variantReads, isEmpty);
    await tester.ensureVisible(
      find.byKey(const ValueKey('stock-variants-apple')),
    );
    await tester.tap(find.byKey(const ValueKey('stock-variants-apple')));
    await tester.pumpAndSettle();
    expect(mounted.client.variantReads, ['apple']);
    expect(find.byKey(const ValueKey('stock-variant-apple-xstock')), findsOne);
  });

  testWidgets('one omitted flagged version is disclosed beside visible rows', (
    tester,
  ) async {
    final mounted = await _mount(tester);
    mounted.client.searchResponse = (query, limit) {
      final page = stockSearchFixture(query: query, limit: limit);
      final asset = (page['results'] as List).single as Map<String, Object?>;
      asset['advisories'] = [
        {
          'mint': researchUsdcMint,
          'variantId': 'apple-flagged',
          'status': 'caution',
          'providerStatus': 'caution',
          'reason': 'Fixture warning for an omitted version.',
          'since': '2026-09-14T17:00:00.000Z',
        },
      ];
      return page;
    };
    await tester.enterText(
      find.byKey(const ValueKey('stock-research-query')),
      'Apple',
    );
    await tester.tap(find.byKey(const ValueKey('stock-research-search')));
    await tester.pumpAndSettle();

    expect(find.text('Apple xStock'), findsOne);
    expect(find.byKey(const ValueKey('stock-variants-hidden-apple')), findsOne);
    expect(mounted.client.variantReads, isEmpty);
  });

  testWidgets('versions expire independently and refresh only when asked', (
    tester,
  ) async {
    final mounted = await _mount(tester);
    mounted.client.variantsResponse = (assetId) => {
      ...stockVariantsFixture(assetId: assetId),
      'refreshAfter': '2026-09-14T18:00:30.000Z',
    };
    await tester.enterText(
      find.byKey(const ValueKey('stock-research-query')),
      'Apple',
    );
    await tester.tap(find.byKey(const ValueKey('stock-research-search')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('stock-variants-apple')),
    );
    await tester.tap(find.byKey(const ValueKey('stock-variants-apple')));
    await tester.pumpAndSettle();

    mounted.advanceTo('2026-09-14T18:00:40.000Z');
    mounted.expire();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stock-research-stale')), findsNothing);
    expect(find.byKey(const ValueKey('stock-variants-stale-apple')), findsOne);
    expect(find.text('Price \$200.50'), findsOne);
    expect(mounted.client.variantReads, ['apple']);

    mounted.client.variantsResponse = (assetId) =>
        stockVariantsFixture(assetId: assetId);
    await tester.ensureVisible(find.text('Refresh versions'));
    await tester.tap(find.text('Refresh versions'));
    await tester.pumpAndSettle();
    expect(mounted.client.variantReads, ['apple', 'apple']);
    expect(
      find.byKey(const ValueKey('stock-variants-stale-apple')),
      findsNothing,
    );
  });

  testWidgets('offline retained rows offer no active version request', (
    tester,
  ) async {
    final mounted = await _mount(tester);
    await tester.enterText(
      find.byKey(const ValueKey('stock-research-query')),
      'Apple',
    );
    await tester.tap(find.byKey(const ValueKey('stock-research-search')));
    await tester.pumpAndSettle();
    mounted.controller.setNetworkAvailable(false);
    await tester.pumpAndSettle();
    expect(find.text('Price \$200.50'), findsOne);
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('stock-variants-apple')),
          )
          .onPressed,
      isNull,
    );
    mounted.controller.setNetworkAvailable(true);
    await tester.pumpAndSettle();
    expect(mounted.client.searches, [('Apple', 10)]);
    expect(mounted.client.variantReads, isEmpty);
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('stock-variants-apple')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('background interruption leaves an explicit retry state', (
    tester,
  ) async {
    final mounted = await _mount(tester);
    final gate = Completer<void>();
    mounted.client.searchGate = gate;
    await tester.enterText(
      find.byKey(const ValueKey('stock-research-query')),
      'Apple',
    );
    await tester.tap(find.byKey(const ValueKey('stock-research-search')));
    await tester.pumpAndSettle();
    mounted.controller.setForeground(false);
    await tester.pump();
    mounted.controller.setForeground(true);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stock-research-cancelled')), findsOne);
    expect(mounted.client.searches, [('Apple', 10)]);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Apple (AAPL)'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a refused earlier request cannot overwrite a newer search', (
    tester,
  ) async {
    final mounted = await _mount(tester);
    await tester.enterText(
      find.byKey(const ValueKey('stock-research-query')),
      'Apple',
    );
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('stock-research-query')),
    );
    // Both user intents happen before the first rejection's microtask settles.
    mounted.controller.setNetworkAvailable(false);
    field.onSubmitted!('Apple');
    mounted.controller.setNetworkAvailable(true);
    field.controller!.text = 'AAPL';
    field.onSubmitted!('AAPL');
    await tester.pumpAndSettle();
    expect(mounted.client.searches, [('AAPL', 10)]);
    expect(find.text('Apple (AAPL)'), findsOne);
    expect(find.byKey(const ValueKey('stock-research-refused')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reopening preserves the displayed query without another read', (
    tester,
  ) async {
    final mounted = await _mount(tester);
    await tester.enterText(
      find.byKey(const ValueKey('stock-research-query')),
      'Apple',
    );
    await tester.tap(find.byKey(const ValueKey('stock-research-search')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_panelApp(mounted.controller));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('stock-research-query')))
          .controller!
          .text,
      'Apple',
    );
    expect(find.text('Price \$200.50'), findsOne);
    expect(mounted.client.searches, [('Apple', 10)]);
  });

  testWidgets(
    'switching runtimes detaches old state and listens to the new one',
    (tester) async {
      final mounted = await _mount(tester);
      await tester.enterText(
        find.byKey(const ValueKey('stock-research-query')),
        'Apple',
      );
      await tester.tap(find.byKey(const ValueKey('stock-research-search')));
      await tester.pumpAndSettle();
      final replacement = StockResearchController.withClients(
        researchClient: _ScriptedResearchClient(results: 0),
        historyClient: _UnusedHistoryClient(),
        raydiumClient: _UnusedRaydiumClient(),
        clock: () => DateTime.parse('2026-09-14T18:00:02.000Z'),
        timerFactory: (delay, callback) => _HeldTimer(callback),
      );
      addTearDown(replacement.dispose);
      await tester.pumpWidget(_panelApp(replacement));
      await tester.pumpAndSettle();
      expect(find.text('Apple (AAPL)'), findsNothing);
      final heading = tester.widget<Text>(find.text('Stock prices'));
      mounted.controller.setNetworkAvailable(false);
      await tester.pump();
      expect(
        tester.widget<Text>(find.text('Stock prices')),
        same(heading),
        reason: 'the detached runtime must not rebuild the current panel',
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('stock-research-query')),
            )
            .controller!
            .text,
        isEmpty,
      );
      await replacement.search('AAPL');
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Nothing listed for "AAPL". Try another company name or symbol.',
        ),
        findsOne,
      );
    },
  );

  testWidgets('a dismissed sheet ignores a late provider result', (
    tester,
  ) async {
    final mounted = await _mount(tester);
    final gate = Completer<void>();
    mounted.client.searchGate = gate;
    await tester.enterText(
      find.byKey(const ValueKey('stock-research-query')),
      'Apple',
    );
    await tester.tap(find.byKey(const ValueKey('stock-research-search')));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(StockResearchPanel), findsNothing);
    expect(mounted.controller.discoveryState.search.data?.query, 'Apple');
  });

  testWidgets('a narrow panel supports large text and scrolls to versions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _mount(tester, textScaler: TextScaler.linear(2));
    await tester.enterText(
      find.byKey(const ValueKey('stock-research-query')),
      'Apple',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('stock-research-search')),
    );
    await tester.tap(find.byKey(const ValueKey('stock-research-search')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('stock-variants-apple')),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('stock-variants-apple')),
    );
    await tester.tap(find.byKey(const ValueKey('stock-variants-apple')));
    await tester.pumpAndSettle();
    expect(find.text('Price \$200.50'), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a provider failure is explained without a code', (tester) async {
    await _mount(
      tester,
      searchError: const StockResearchException('STOCK_RATE_LIMITED'),
    );
    await tester.enterText(
      find.byKey(const ValueKey('stock-research-query')),
      'Apple',
    );
    await tester.tap(find.byKey(const ValueKey('stock-research-search')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('stock-research-failure')))
          .data,
      'Too many looks in a row. Wait a moment.',
    );
    expect(find.textContaining('STOCK_'), findsNothing);
  });

  testWidgets('nothing listed is reported as nothing, not as a failure', (
    tester,
  ) async {
    await _mount(tester, results: 0);
    await tester.enterText(
      find.byKey(const ValueKey('stock-research-query')),
      'Apple',
    );
    await tester.tap(find.byKey(const ValueKey('stock-research-search')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Nothing listed for "Apple". Try another company name or symbol.',
      ),
      findsOne,
    );
    expect(find.byKey(const ValueKey('stock-research-failure')), findsNothing);
  });

  testWidgets('a reading past its refresh time is labelled, not hidden', (
    tester,
  ) async {
    // The fixture refreshes after 18:01:00, so this reading starts fresh.
    final mounted = await _mount(tester, at: '2026-09-14T18:00:02.000Z');
    await tester.enterText(
      find.byKey(const ValueKey('stock-research-query')),
      'Apple',
    );
    await tester.tap(find.byKey(const ValueKey('stock-research-search')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stock-research-stale')), findsNothing);

    mounted.advanceTo('2026-09-14T18:02:00.000Z');
    mounted.expire();
    await tester.pumpAndSettle();
    expect(
      find.textContaining('passed its refresh time'),
      findsOne,
      reason: 'an aged reading must say so',
    );
    // The reading someone is looking at is not snatched away, only labelled.
    expect(find.text('Apple (AAPL)'), findsOne);
    expect(find.text('Price \$200.50'), findsOne);
  });

  testWidgets('a build with no market origin offers no search at all', (
    tester,
  ) async {
    await _mount(tester, disabled: true);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('stock-research-unavailable')),
          )
          .data,
      'Stock prices are not set up in this build.',
    );
    expect(find.byKey(const ValueKey('stock-research-search')), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a failed configuration says so rather than looking ready', (
    tester,
  ) async {
    await _mount(tester, configurationFailed: true);
    expect(find.byKey(const ValueKey('stock-research-unavailable')), findsOne);
    expect(find.byKey(const ValueKey('stock-research-search')), findsNothing);
  });
}
