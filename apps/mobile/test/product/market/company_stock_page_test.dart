import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/market/market.dart';

import 'market_test_support.dart';
import '../../stock_facts_models_test.dart' as facts_fixtures;

final class _FactsRepository implements StockFactsRepository {
  _FactsRepository(this.load);

  final Future<StockFacts> Function(String assetId) load;
  int detailCalls = 0;

  @override
  Future<StockCardsPage> cards(String query, {int limit = 10}) async =>
      throw StateError('unused');

  @override
  Future<StockFacts> facts(String assetId) {
    detailCalls++;
    return load(assetId);
  }
}

void main() {
  MarketStockDetails details({bool position = true}) => MarketStockDetails(
    company: testCompany(),
    position: position
        ? MarketPosition(
            shares: '2.1605',
            valuePaper: 500,
            averageCostPaper: 231,
            gainPercent: 1.4,
          )
        : null,
    reasons: [
      MarketReason(
        handle: 'nia',
        initials: 'NI',
        note: 'Services revenue keeps growing.',
        entryPrice: '224.10',
        performancePercent: 3.2,
        createdAt: DateTime.utc(2026, 9, 20),
      ),
    ],
    holders: [
      MarketHolder(
        handle: 'tobi',
        initials: 'TO',
        rank: 'Analyst',
        averageEntry: '221.00',
        performancePercent: 4.7,
        isFriend: true,
      ),
    ],
    marketCap: '\$3.5T',
    yearRange: '\$169 to \$260',
    versions: const [
      MarketVersionInfo(
        symbol: 'AAPLx',
        issuer: 'Backed',
        mint: testMint,
        backingDisclosure: 'Backed 1:1. No voting rights.',
        tradingHours: 'Trades 24/7 on chain.',
        status: MarketVersionStatus.verified,
      ),
    ],
  );

  Widget app(
    MarketStockDetails value, {
    double textScale = 1,
    MarketFactsController? factsController,
    Future<void> Function(PaperOrderSide)? onRealTrade,
    String? availableShares,
    String? realPositionLabel,
  }) => MaterialApp(
    theme: ThemeData(useMaterial3: true, fontFamily: 'Manrope'),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: CompanyStockPage(
      details: value,
      orderRepository: FakePaperOrderRepository(),
      clientOrderId: () => 'client-order-1',
      availablePaper: '10000',
      availableShares: availableShares ?? value.position?.shares ?? '0',
      realPositionLabel: realPositionLabel,
      factsController: factsController,
      onRealTrade: onRealTrade,
    ),
  );

  testWidgets('stock page follows required order and exposes all sections', (
    tester,
  ) async {
    await tester.pumpWidget(app(details()));
    expect(find.text('Apple'), findsOneWidget);
    expect(find.text('\$231.42'), findsOneWidget);
    expect(find.textContaining('Holder count unavailable'), findsNothing);
    expect(find.text('Price movement'), findsNothing);
    expect(find.text('Your position'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Comments'), 300);
    expect(find.text('Comments'), findsOneWidget);
    expect(find.byKey(const ValueKey('stock-buy-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('stock-sell-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('stock-trim-button')), findsNothing);

    await tester.ensureVisible(
      find.byKey(const ValueKey('stock-section-holders')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stock-section-holders')));
    await tester.pumpAndSettle();
    expect(find.text('@tobi'), findsNothing);
    expect(find.text('Holders couldn’t load'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('stock-section-about')));
    await tester.pumpAndSettle();
    expect(find.text('Available tokens'), findsOneWidget);
    expect(find.text('Verified'), findsNothing);
  });

  testWidgets('buy and sell remain persistent semantic actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(app(details()));
    final buy = tester.getSemantics(
      find.byKey(const ValueKey('stock-buy-button')),
    );
    final sell = tester.getSemantics(
      find.byKey(const ValueKey('stock-sell-button')),
    );
    expect(buy.label, 'Buy');
    expect(sell.label, 'Sell');
    expect(buy.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(sell.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    semantics.dispose();
  });

  testWidgets(
    'a buy updates this open page and the next sell uses its exact shares',
    (tester) async {
      await tester.pumpWidget(app(details(position: false)));
      await tester.tap(find.byKey(const ValueKey('stock-buy-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('paper-preset-500')));
      await tester.tap(find.byKey(const ValueKey('paper-order-review-button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('paper-order-confirm-button')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('paper-order-done')),
      );
      await tester.tap(find.byKey(const ValueKey('paper-order-done')));
      await tester.pumpAndSettle();
      expect(find.text('2.1605 shares'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('stock-sell-button')));
      await tester.pumpAndSettle();
      final order = tester.widget<PaperOrderFlow>(find.byType(PaperOrderFlow));
      expect(order.availableShares, '2.1605');
      expect(order.availablePaper, '9500');
    },
  );

  testWidgets('sell stays visible but disabled without a position', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(app(details(position: false)));
    final sell = tester.getSemantics(
      find.byKey(const ValueKey('stock-sell-button')),
    );
    expect(sell.label, 'Sell');
    expect(sell.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    semantics.dispose();
  });

  testWidgets('open real asset reacts to a settled buy and full sell', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final actions = <PaperOrderSide>[];
    Future<void> trade(PaperOrderSide side) async => actions.add(side);
    Widget live({String shares = '0', String? label}) => app(
      details(position: false),
      availableShares: shares,
      realPositionLabel: label,
      onRealTrade: trade,
    );
    final sell = find.byKey(const ValueKey('stock-sell-button'));
    await tester.pumpWidget(live());
    expect(
      tester
          .getSemantics(sell)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );

    await tester.pumpWidget(
      live(shares: '0.00591613', label: '0.00593546 AAPLx'),
    );
    await tester.pump();
    expect(find.text('0.00593546 AAPLx'), findsOneWidget);
    expect(
      tester
          .getSemantics(sell)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    await tester.tap(sell);
    await tester.pump();
    expect(actions, [PaperOrderSide.sell]);
    expect(find.byType(PaperOrderFlow), findsNothing);

    await tester.pumpWidget(live());
    await tester.pump();
    expect(find.text('0.00593546 AAPLx'), findsNothing);
    expect(
      tester
          .getSemantics(sell)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );
    semantics.dispose();
  });

  testWidgets(
    'switching to real money clears paper fills and sell availability',
    (tester) async {
      await tester.pumpWidget(app(details(position: false)));
      await tester.tap(find.byKey(const ValueKey('stock-buy-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('paper-preset-500')));
      await tester.tap(find.byKey(const ValueKey('paper-order-review-button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('paper-order-confirm-button')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('paper-order-done')),
      );
      await tester.tap(find.byKey(const ValueKey('paper-order-done')));
      await tester.pumpAndSettle();
      expect(find.text('2.1605 shares'), findsOneWidget);

      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        app(details(position: false), onRealTrade: (_) async {}),
      );
      await tester.pumpAndSettle();
      expect(find.text('2.1605 shares'), findsNothing);
      expect(find.text('Your position'), findsNothing);
      final sell = tester.getSemantics(
        find.byKey(const ValueKey('stock-sell-button')),
      );
      expect(sell.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      semantics.dispose();
    },
  );

  testWidgets('empty social data stays unavailable and uses singular grammar', (
    tester,
  ) async {
    final base = testCompany();
    final company = MarketCompany.fromDiscovery(
      base.asset,
      floorHolders: 1,
      friendFaces: const [MarketFriendFace(handle: 'nia', initials: 'NI')],
      lists: const {MarketList.starterPicks},
    );
    await tester.pumpWidget(
      app(MarketStockDetails(company: company, versions: const [])),
    );

    expect(
      find.text('1 friend and 1 other on the floor holds this.'),
      findsNothing,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('stock-section-reasons')),
    );
    await tester.tap(find.byKey(const ValueKey('stock-section-reasons')));
    await tester.pumpAndSettle();
    final unavailable = find.text('No comments yet');
    await tester.scrollUntilVisible(unavailable, 300);
    expect(unavailable, findsOneWidget);
  });

  testWidgets('stock page has no overflow at 320px and 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(details(), textScale: 2));
    await tester.pump();

    expect(tester.takeException(), isNull);
    final page = find.byType(ListView).first;
    for (var index = 0; index < 5; index++) {
      await tester.drag(page, const Offset(0, -500));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    expect(find.byKey(const ValueKey('stock-buy-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('stock-sell-button')), findsOneWidget);
  });

  testWidgets('company facts load once and fill description and sparkline', (
    tester,
  ) async {
    final response = Completer<StockFacts>();
    final repository = _FactsRepository((_) => response.future);
    final facts = MarketFactsController(repository: repository);
    addTearDown(facts.dispose);
    final base = testCompany();
    final company = MarketCompany.fromDiscovery(
      base.asset,
      lists: const {MarketList.starterPicks},
    );

    await tester.pumpWidget(
      app(
        MarketStockDetails(company: company, versions: const []),
        factsController: facts,
      ),
    );
    await tester.pump();

    expect(repository.detailCalls, 1);
    expect(find.byKey(const ValueKey('stock-facts-loading')), findsNothing);
    expect(
      find.byKey(const ValueKey('stock-facts-chart-loading')),
      findsOneWidget,
    );

    response.complete(StockFacts.fromJson(facts_fixtures.facts()));
    await tester.pumpAndSettle();

    expect(find.text('Apple designs phones and computers.'), findsOneWidget);
    expect(find.byKey(const ValueKey('stock-facts-sparkline')), findsOneWidget);
    expect(
      find.text('-0.66%'),
      findsNothing,
      reason: 'Underlying stock change must not label a token price',
    );
    expect(repository.detailCalls, 1);
  });

  testWidgets(
    'company facts failure leaves the stock and trade controls usable',
    (tester) async {
      final repository = _FactsRepository(
        (_) async =>
            throw const StockFactsException(StockFactsFailure.unavailable),
      );
      final facts = MarketFactsController(repository: repository);
      addTearDown(facts.dispose);
      final base = testCompany();
      final company = MarketCompany.fromDiscovery(
        base.asset,
        lists: const {MarketList.starterPicks},
      );

      await tester.pumpWidget(
        app(
          MarketStockDetails(company: company, versions: const []),
          factsController: facts,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Apple'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('stock-facts-chart-unavailable')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('stock-buy-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('stock-sell-button')), findsOneWidget);
    },
  );

  testWidgets('a late facts response is ignored after the page is disposed', (
    tester,
  ) async {
    final response = Completer<StockFacts>();
    final repository = _FactsRepository((_) => response.future);
    final facts = MarketFactsController(repository: repository);
    final base = testCompany();
    final company = MarketCompany.fromDiscovery(base.asset);

    await tester.pumpWidget(
      app(
        MarketStockDetails(company: company, versions: const []),
        factsController: facts,
      ),
    );
    await tester.pump();
    expect(repository.detailCalls, 1);

    await tester.pumpWidget(const SizedBox());
    facts.dispose();
    response.complete(StockFacts.fromJson(facts_fixtures.facts()));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
