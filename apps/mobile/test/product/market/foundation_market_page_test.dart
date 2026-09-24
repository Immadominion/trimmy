import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/market/market.dart';

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
}
