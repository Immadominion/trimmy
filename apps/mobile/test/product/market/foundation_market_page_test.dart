import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/market/market.dart';

import 'package:trimmy/product/market/live_trading.dart';

import 'live_trading_test_support.dart';
import 'market_test_support.dart';

void main() {
  Widget app({required Widget home, double textScale = 1}) => MaterialApp(
    theme: ThemeData(useMaterial3: true, fontFamily: 'Manrope'),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: home,
  );

  testWidgets('list keeps separate follow and asset actions', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = FakeMarketSearchGateway();
    final recents = MarketRecentsController();
    addTearDown(gateway.dispose);
    addTearDown(recents.dispose);
    var signIns = 0;
    MarketCompany? opened;
    await tester.pumpWidget(
      app(
        home: FoundationMarketPage(
          companies: [
            testCompany(name: 'A long technology company'),
            testCompany(assetId: 'nvidia', name: 'NVIDIA', symbol: 'NVDA'),
          ],
          searchGateway: gateway,
          recents: recents,
          onOpenCompany: (company) => opened = company,
          onSignIn: () => signIns++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final first = find.byKey(const ValueKey('market-company-apple'));
    final second = find.byKey(const ValueKey('market-company-nvidia'));
    expect(tester.getTopLeft(first).dx, tester.getTopLeft(second).dx);
    expect(
      tester.getTopLeft(second).dy,
      greaterThan(tester.getBottomLeft(first).dy),
    );
    await tester.tap(find.byKey(const ValueKey('market-follow-apple')));
    expect(signIns, 1);
    expect(opened, isNull);
    await tester.tap(find.text('NVIDIA'));
    expect(opened?.assetId, 'nvidia');
    expect(recents.companies.single.assetId, 'nvidia');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'keeps company cards aligned and readable at 320px and 200% text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final apple = testCompany(
        name: 'A very long technology company name',
        symbol: 'LONGTOKEN',
      );
      final nvidia = testCompany(
        assetId: 'nvidia',
        name: 'Nvidia',
        symbol: 'NVDA',
        change: -2.1,
      );
      final gateway = FakeMarketSearchGateway();
      addTearDown(gateway.dispose);

      await tester.pumpWidget(
        app(
          textScale: 2,
          home: FoundationMarketPage(
            companies: [apple, nvidia],
            searchGateway: gateway,
            recents: MarketRecentsController(),
            onOpenCompany: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final first = find.byKey(const ValueKey('market-company-apple'));
      final second = find.byKey(const ValueKey('market-company-nvidia'));
      expect(first, findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -240));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(second, findsOneWidget);
      expect(
        tester.getTopLeft(second).dy,
        greaterThan(tester.getTopLeft(first).dy),
      );
      expect(tester.getTopLeft(second).dx, equals(tester.getTopLeft(first).dx));
    },
  );

  testWidgets(
    'choosing a type filter shows only that type and loads the rest of the Market',
    (tester) async {
      final stock = testCompany(lists: const {MarketList.all});
      final fund = testCompany(
        assetId: 'sp500',
        name: 'SP500',
        symbol: 'SPY',
        lists: const {MarketList.all, MarketList.etfs},
      );
      final gateway = FakeMarketSearchGateway();
      addTearDown(gateway.dispose);
      var loads = 0;
      await tester.pumpWidget(
        app(
          home: FoundationMarketPage(
            companies: [
              stock,
              ...List.generate(20, (i) => testCompany(assetId: 'extra-$i')),
              fund,
            ],
            searchGateway: gateway,
            recents: MarketRecentsController(),
            onOpenCompany: (_) {},
            hasMore: true,
            onLoadMore: () async => loads++,
          ),
        ),
      );
      await tester.pump();
      expect(loads, 0, reason: 'All pages in as the person scrolls');
      expect(find.byKey(const ValueKey('market-list-preIpo')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('market-list-etfs')));
      await tester.pump();
      await tester.pump();
      expect(loads, greaterThan(0));
      expect(find.text('SP500'), findsOneWidget);
      expect(find.text('Apple'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    },
  );

  testWidgets(
    'near the end loads once, failure keeps rows and retry is explicit',
    (tester) async {
      final gateway = FakeMarketSearchGateway(),
          recents = MarketRecentsController();
      addTearDown(gateway.dispose);
      addTearDown(recents.dispose);
      final first = List.generate(
        20,
        (i) => testCompany(assetId: 'company-$i', name: 'Company $i'),
      );
      var rows = first, more = true, loading = false;
      String? error;
      var calls = 0;
      final request = Completer<void>();
      late StateSetter update;
      await tester.pumpWidget(
        app(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return FoundationMarketPage(
                companies: rows,
                searchGateway: gateway,
                recents: recents,
                onOpenCompany: (_) {},
                hasMore: more,
                loadingMore: loading,
                loadMoreMessage: error,
                onLoadMore: () async {
                  calls++;
                  update(() {
                    loading = true;
                    error = null;
                  });
                  if (calls == 1) {
                    await request.future;
                    update(() {
                      loading = false;
                      error = 'Could not load more stocks. Try again.';
                    });
                  } else {
                    update(() {
                      loading = false;
                      more = false;
                      rows = [
                        ...first,
                        testCompany(assetId: 'next', name: 'Next company'),
                      ];
                    });
                  }
                },
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 0);
      final scroll = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      scroll.jumpTo(scroll.maxScrollExtent - 400);
      await tester.pump();
      expect(calls, 1);
      expect(scroll.extentAfter, greaterThan(0));
      scroll.jumpTo(scroll.maxScrollExtent);
      await tester.pump();
      expect(calls, 1);
      request.complete();
      await tester.pump();
      await tester.pump();
      expect(calls, 1);
      expect(find.text('Try again'), findsOneWidget);
      await tester.ensureVisible(find.text('Try again'));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Next company'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a short page fills the viewport without a scroll or repeated request',
    (tester) async {
      final gateway = FakeMarketSearchGateway(),
          recents = MarketRecentsController();
      addTearDown(gateway.dispose);
      addTearDown(recents.dispose);
      var calls = 0;
      final rows = [testCompany()];
      await tester.pumpWidget(
        app(
          home: FoundationMarketPage(
            companies: rows,
            searchGateway: gateway,
            recents: recents,
            onOpenCompany: (_) {},
            hasMore: true,
            onLoadMore: () async {
              calls++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 1);
    },
  );

  testWidgets('guest sees only lists and sorts backed by current data', (
    tester,
  ) async {
    final base = testCompany();
    final company = MarketCompany.fromDiscovery(
      base.asset,
      lists: const {MarketList.starterPicks},
    );
    final gateway = FakeMarketSearchGateway();
    addTearDown(gateway.dispose);

    await tester.pumpWidget(
      app(
        home: FoundationMarketPage(
          companies: [company],
          searchGateway: gateway,
          recents: MarketRecentsController(),
          onOpenCompany: (_) {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey('market-list-all')), findsNothing);
    expect(find.byKey(const ValueKey('market-list-following')), findsNothing);
    expect(find.byKey(const ValueKey('market-list-trending')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('market-sort-button')));
    await tester.pumpAndSettle();
    expect(find.text('Featured'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Change today'), findsNothing);
    expect(find.text('Most held'), findsNothing);
  });

  testWidgets(
    'company card exposes tap and long press without duplicate copy',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final apple = testCompany();
      await tester.pumpWidget(
        app(
          home: Scaffold(
            body: SizedBox(
              width: 340,
              height: 200,
              child: MarketCompanyCard(
                company: apple,
                followed: false,
                onTap: () {},
                onLongPress: () async {},
              ),
            ),
          ),
        ),
      );

      final node = tester.getSemantics(
        find.byKey(const ValueKey('market-company-apple')),
      );
      expect(node.label, contains('Apple'));
      expect(node.label, contains('+1.40%'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.longPress),
        isTrue,
      );
      semantics.dispose();
    },
  );

  testWidgets('the sort sheet scrolls on a small phone at large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    // Day changes add Biggest gains and Biggest drops: five options.
    final company = testCompany();
    final gateway = FakeMarketSearchGateway();
    addTearDown(gateway.dispose);
    await tester.pumpWidget(
      app(
        home: FoundationMarketPage(
          companies: [company],
          searchGateway: gateway,
          recents: MarketRecentsController(),
          onOpenCompany: (_) {},
        ),
      ),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('market-sort-button')),
    );
    await tester.tap(find.byKey(const ValueKey('market-sort-button')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'no overflow');
    await tester.ensureVisible(find.text('Name'));
    await tester.tap(find.text('Name'));
    await tester.pumpAndSettle();
    expect(
      find.text('Featured'),
      findsNothing,
      reason: 'the last option was reachable',
    );
  });

  testWidgets('full-screen search searches while typing and records recents', (
    tester,
  ) async {
    final apple = testCompany();
    final gateway = FakeMarketSearchGateway(
      results: {
        'Apple': [apple],
      },
    );
    final recents = MarketRecentsController();
    addTearDown(gateway.dispose);
    addTearDown(recents.dispose);

    await tester.pumpWidget(
      app(
        home: MarketSearchPage(gateway: gateway, recents: recents),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('market-search-field')),
      'Apple',
    );
    await tester.pump(const Duration(milliseconds: 281));
    await tester.pump();

    expect(gateway.queries, ['Apple']);
    expect(
      find.byKey(const ValueKey('market-search-result-apple')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('market-search-result-apple')));
    await tester.pump();
    expect(recents.companies.single.assetId, 'apple');
  });

  testWidgets('search shows its honest empty and recovery states', (
    tester,
  ) async {
    final gateway = FakeMarketSearchGateway();
    addTearDown(gateway.dispose);
    await tester.pumpWidget(
      app(
        home: MarketSearchPage(
          gateway: gateway,
          recents: MarketRecentsController(),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('market-search-field')),
      'Nope',
    );
    await tester.pump(const Duration(milliseconds: 281));
    await tester.pump();
    expect(find.byKey(const ValueKey('market-search-empty')), findsOneWidget);
    expect(find.textContaining('Nothing called'), findsOneWidget);
  });

  testWidgets('search result stays usable at 320px and 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final company = testCompany(name: 'A very long company name');
    final gateway = FakeMarketSearchGateway(
      results: {
        'AAPL': [company],
      },
    );
    addTearDown(gateway.dispose);
    await tester.pumpWidget(
      app(
        textScale: 2,
        home: MarketSearchPage(
          gateway: gateway,
          recents: MarketRecentsController(),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('market-search-field')),
      'AAPL',
    );
    await tester.pump(const Duration(milliseconds: 281));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('market-search-result-apple')),
      findsOneWidget,
    );
  });

  group('real mode', () {
    final caps = LiveTradingCapabilities.fromJson(capabilitiesV2Json());
    final companies = [
      testCompany(assetId: 'tesla', name: 'Tesla', symbol: 'TSLA'),
      testCompany(),
      testCompany(assetId: 'hims', name: 'Hims', symbol: 'HIMS'),
      discoveryCompany('nvidia', [(xNvidiaMint, 10), (ondoNvidiaMint, 20)]),
    ];

    Future<void> show(
      WidgetTester tester, {
      required bool real,
      LiveTradingCapabilities? capabilities,
    }) async {
      tester.view.physicalSize = const Size(420, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = FakeMarketSearchGateway();
      addTearDown(gateway.dispose);
      await tester.pumpWidget(
        app(
          home: FoundationMarketPage(
            companies: companies,
            searchGateway: gateway,
            recents: MarketRecentsController(),
            onOpenCompany: (_) {},
            realMoney: real,
            liveCapabilities: capabilities ?? caps,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    List<String> order(WidgetTester tester) {
      final ids = ['tesla', 'apple', 'hims', 'nvidia']
          .where(
            (id) => find
                .byKey(ValueKey('market-company-$id'))
                .evaluate()
                .isNotEmpty,
          )
          .toList();
      ids.sort(
        (a, b) => tester
            .getTopLeft(find.byKey(ValueKey('market-company-$a')))
            .dy
            .compareTo(
              tester.getTopLeft(find.byKey(ValueKey('market-company-$b'))).dy,
            ),
      );
      return ids;
    }

    testWidgets('marks tradeable companies and lists them first', (
      tester,
    ) async {
      await show(tester, real: true);
      expect(order(tester), ['apple', 'nvidia', 'tesla', 'hims']);
      expect(
        find.byKey(const ValueKey('market-tradeable-apple')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('market-tradeable-nvidia')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('market-tradeable-tesla')),
        findsNothing,
      );
      // The two row markers only: there is no separate Tradeable list.
      expect(find.text('Tradeable'), findsNWidgets(2));
      expect(find.byKey(const ValueKey('market-list-all')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the marker fits a 320px phone at 200% text', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = FakeMarketSearchGateway();
      addTearDown(gateway.dispose);
      await tester.pumpWidget(
        app(
          textScale: 2,
          home: FoundationMarketPage(
            companies: [
              testCompany(name: 'A very long technology company name'),
            ],
            searchGateway: gateway,
            recents: MarketRecentsController(),
            onOpenCompany: (_) {},
            onSignIn: () {},
            realMoney: true,
            liveCapabilities: caps,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('market-tradeable-apple')),
        findsOneWidget,
      );
    });

    testWidgets('paper mode is unchanged', (tester) async {
      await show(tester, real: false);
      expect(order(tester), ['tesla', 'apple', 'hims', 'nvidia']);
      expect(find.text('Tradeable'), findsNothing);
    });

    testWidgets('paused trading claims nothing is tradeable', (tester) async {
      await show(
        tester,
        real: true,
        capabilities: LiveTradingCapabilities.fromJson(
          capabilitiesV2Json(enabled: false),
        ),
      );
      expect(order(tester), ['tesla', 'apple', 'hims', 'nvidia']);
      expect(find.text('Tradeable'), findsNothing);
    });
  });
}
