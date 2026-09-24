import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/markets/stock_history_panel.dart';
import 'package:trimmy/markets/stock_research.dart';
import 'package:trimmy/markets/stock_research_panel.dart';

import 'support/stock_history_fixtures.dart';
import 'support/stock_research_fixtures.dart';

final _at = DateTime.parse('2026-09-14T18:00:02Z');

class _Research implements StockResearchClient {
  final searches = <String>[];
  @override
  Future<StockSearchPage> search(
    String query, {
    int limit = 10,
    StockResearchCancellation? cancellation,
  }) async {
    searches.add(query);
    return StockSearchPage.fromJson(
      stockSearchFixture(query: query, limit: limit),
    );
  }

  @override
  Future<StockVariantsPage> variants(
    String assetId, {
    StockResearchCancellation? cancellation,
  }) async =>
      StockVariantsPage.fromJson(stockVariantsFixture(assetId: assetId));
  @override
  Future<StockEstimate> estimate(
    StockEstimateRequest request, {
    StockResearchCancellation? cancellation,
  }) async => throw StateError('no estimates');
}

class _Raydium implements RaydiumQuoteClient {
  @override
  Future<RaydiumStockQuote> quote(
    RaydiumQuoteRequest request, {
    RaydiumQuoteCancellation? cancellation,
  }) async => throw StateError('no quotes');
}

StockHistoryPage _page(
  StockHistoryRequest request, {
  int count = 3,
  bool gaps = false,
}) {
  final from = int.parse(request.fromUnixSeconds);
  return parsedStockHistory(
    request: request,
    candles: [
      for (var index = 0; index < count; index++)
        stockHistoryCandleFixture(
          startUnixSeconds:
              '${from + index * request.interval.seconds * (gaps ? 2 : 1)}',
          openRaw: '${100 + index * 10}',
          highRaw: '${101 + index * 10}',
          lowRaw: '${99 + index * 10}',
          closeRaw: '${100 + index * 10}',
          volumeRaw: '100',
        ),
    ],
  );
}

class _History implements StockHistoryClient {
  final requests = <StockHistoryRequest>[];
  final pending = <Completer<StockHistoryPage>>[];
  var count = 3;
  var held = false;
  String? error;
  @override
  Future<StockHistoryPage> history(
    StockHistoryRequest request, {
    StockResearchCancellation? cancellation,
  }) async {
    requests.add(request);
    if (held) {
      final completer = Completer<StockHistoryPage>();
      pending.add(completer);
      return completer.future;
    }
    if (error != null) throw StockResearchException(error!);
    return _page(request, count: count);
  }
}

class _Timer implements Timer {
  _Timer(this.callback);
  final void Function() callback;
  bool active = true;
  @override
  void cancel() => active = false;
  @override
  bool get isActive => active;
  @override
  int get tick => 0;
}

Future<
  ({
    StockResearchController controller,
    _History history,
    _Research research,
    void Function() expire,
  })
>
_mount(
  WidgetTester tester, {
  bool browse = false,
  int count = 3,
  String? error,
  bool held = false,
  TextScaler scaler = TextScaler.noScaling,
}) async {
  final history = _History()
    ..count = count
    ..error = error
    ..held = held;
  final research = _Research();
  var now = _at;
  final timers = <_Timer>[];
  final controller = StockResearchController.withClients(
    researchClient: research,
    historyClient: history,
    raydiumClient: _Raydium(),
    clock: () => now,
    timerFactory: (delay, callback) {
      final timer = _Timer(callback);
      timers.add(timer);
      return timer;
    },
  );
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: scaler),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: browse
                ? StockResearchPanel(controller: controller, now: () => now)
                : StockHistoryPanel(controller: controller, now: () => now),
          ),
        ),
      ),
    ),
  );
  if (held) {
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }
  return (
    controller: controller,
    history: history,
    research: research,
    expire: () {
      now = _at.add(const Duration(seconds: 70));
      for (final timer in timers.where((timer) => timer.isActive).toList()) {
        timer.callback();
      }
    },
  );
}

void main() {
  test(
    'range requests are bounded, interval-aligned and refer only to AAPLx',
    () {
      for (final period in StockHistoryPeriod.values) {
        final request = period.requestAt(_at);
        expect(request.assetId, stockHistoryAssetId);
        expect(request.variantMint, stockHistoryAaplxMint);
        final bounds = request.validateAt(_at.millisecondsSinceEpoch ~/ 1000);
        expect(bounds.to - bounds.from, period.days * 86400);
        expect(bounds.to % period.interval.seconds, 0);
      }
    },
  );

  test(
    'relative chart detects real gaps and retains the provider time spacing',
    () {
      final request = StockHistoryPeriod.week.requestAt(_at);
      final plot = StockHistoryPlot.fromPage(_page(request, gaps: true))!;
      expect(plot.hasGaps, isTrue);
      expect(
        plot.points.last.time - plot.points.first.time,
        4 * request.interval.seconds,
      );
      expect(plot.changeLabel(0), '0.00%');
      expect(plot.changeLabel(2), '+20.00%');
      expect(StockHistoryPlot.fromPage(_page(request, count: 1)), isNull);
    },
  );

  testWidgets(
    'a company leads into its real token history and back without losing search',
    (tester) async {
      final mounted = await _mount(tester, browse: true);
      expect(mounted.history.requests, isEmpty);
      expect(mounted.research.searches, isEmpty);
      await tester.tap(find.widgetWithText(ActionChip, 'Apple'));
      await tester.pumpAndSettle();
      expect(mounted.research.searches, ['Apple']);
      final details = find.byKey(const ValueKey('stock-details-apple-xstock'));
      await tester.ensureVisible(details);
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(mounted.history.requests, hasLength(1));
      expect(
        mounted.history.requests.single.interval,
        StockHistoryInterval.fourHours,
      );
      expect(find.text('+20.00%'), findsOne);
      expect(find.textContaining('not Apple shares'), findsOne);
      expect(find.textContaining('Solana token address'), findsOne);
      expect(find.byKey(const ValueKey('stock-detail-checked-at')), findsOne);
      mounted.expire();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('stock-detail-stale')), findsOne);
      mounted.controller.setNetworkAvailable(false);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('stock-detail-offline')), findsOne);
      mounted.controller.setNetworkAvailable(true);
      await tester.pumpAndSettle();
      final back = find.byKey(const ValueKey('stock-details-back'));
      await tester.ensureVisible(back);
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.text('Apple (AAPL)'), findsOne);
      expect(mounted.history.requests, hasLength(1));
      expect(mounted.research.searches, ['Apple']);
    },
  );

  testWidgets('each selected period uses its own request and chart', (
    tester,
  ) async {
    final mounted = await _mount(tester);
    await tester.tap(find.byKey(const ValueKey('stock-history-day')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stock-history-month')));
    await tester.pumpAndSettle();
    expect(mounted.history.requests.map((request) => request.interval), [
      StockHistoryInterval.fourHours,
      StockHistoryInterval.oneHour,
      StockHistoryInterval.oneDay,
    ]);
    expect(find.byKey(const ValueKey('stock-history-chart')), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty and single-reading history explain how to continue', (
    tester,
  ) async {
    final mounted = await _mount(tester, count: 0);
    expect(find.byKey(const ValueKey('stock-history-empty')), findsOne);
    expect(find.byKey(const ValueKey('stock-history-chart')), findsNothing);
    mounted.history.count = 1;
    await tester.tap(find.byKey(const ValueKey('stock-history-month')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stock-history-single')), findsOne);
    mounted.history.count = 3;
    await tester.tap(find.byKey(const ValueKey('stock-history-day')));
    await tester.pumpAndSettle();
    expect(find.text('+20.00%'), findsOne);
  });

  testWidgets('a failed lookup recovers through the visible refresh control', (
    tester,
  ) async {
    final mounted = await _mount(tester, error: 'STOCK_HISTORY_RATE_LIMITED');
    expect(find.textContaining('wait a moment'), findsOne);
    mounted.history.error = null;
    await tester.tap(find.byKey(const ValueKey('stock-history-refresh')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('stock-history-error')), findsNothing);
    expect(find.text('+20.00%'), findsOne);
    expect(mounted.history.requests, hasLength(2));
  });

  testWidgets(
    'changing range cannot display a late response from the old range',
    (tester) async {
      final mounted = await _mount(tester, held: true);
      await tester.tap(find.byKey(const ValueKey('stock-history-day')));
      await tester.pump();
      // The repository waits for cancellation to settle before spending quota
      // on the queued range, while the UI already reflects the user's choice.
      expect(mounted.history.requests, hasLength(1));
      mounted.history.pending.first.complete(
        _page(mounted.history.requests.first),
      );
      await tester.pump();
      expect(mounted.history.requests, hasLength(2));
      expect(find.byKey(const ValueKey('stock-history-chart')), findsNothing);
      mounted.history.pending.last.complete(
        _page(mounted.history.requests.last),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('stock-history-chart')), findsOne);
    },
  );

  testWidgets(
    'staleness and reconnect label retained history without fetching',
    (tester) async {
      final mounted = await _mount(tester);
      mounted.expire();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('stock-history-stale')), findsOne);
      expect(find.byKey(const ValueKey('stock-history-chart')), findsOne);
      mounted.controller.setNetworkAvailable(false);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('stock-history-offline')), findsOne);
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('stock-history-refresh')),
            )
            .onPressed,
        isNull,
      );
      mounted.controller.setNetworkAvailable(true);
      await tester.pumpAndSettle();
      expect(mounted.history.requests, hasLength(1));
    },
  );

  testWidgets(
    'chart responds to exploration and fits narrow screens with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _mount(tester, scaler: TextScaler.linear(2));
      final chart = find.byKey(const ValueKey('stock-history-chart'));
      await tester.ensureVisible(chart);
      final rect = tester.getRect(chart);
      await tester.tapAt(Offset(rect.left + 8, rect.center.dy));
      await tester.pumpAndSettle();
      expect(find.text('0.00%'), findsOne);
      expect(tester.takeException(), isNull);
    },
  );
}
