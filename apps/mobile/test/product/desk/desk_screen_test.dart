import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/design/product_theme.dart';
import 'package:trimmy/product/desk/desk_models.dart';
import 'package:trimmy/product/desk/desk_screen.dart';
import 'package:trimmy/product/market/market_craft.dart';

void main() {
  testWidgets('real desk keeps funding and history independently reachable', (
    tester,
  ) async {
    var funding = 0;
    var history = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: DeskScreen(
          real: true,
          realBalance: r'$3.00',
          snapshot: DeskSnapshot.newRookie(handle: 'rookie'),
          onOpenMarket: () {},
          onAddMoney: () => funding++,
          onOpenPortfolio: () => history++,
        ),
      ),
    );
    await tester.tap(find.text('Add money'));
    expect(funding, 1);
    final action = find.byKey(const ValueKey('real-trade-history'));
    await tester.scrollUntilVisible(
      action,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(action);
    expect(history, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('portfolio overlaps only the latest three holding logos', (
    tester,
  ) async {
    final holdings = List.generate(
      4,
      (i) => DeskHolding(
        assetId: 'stock-$i',
        variantMint: 'mint-$i',
        name: 'Stock $i',
        symbol: 'ST$i',
        quantity: '1',
        valuePaper: '100',
        changePercent: 0,
        logoUrl: 'https://example.test/stock-$i.png',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: DeskScreen(
          snapshot: DeskSnapshot(
            handle: '',
            paperValue: '10000',
            wallStreetLine: '',
            holdings: holdings,
          ),
          onOpenMarket: () {},
        ),
      ),
    );
    final first = find.byKey(const ValueKey('desk-stack-stock-0-mint-0'));
    final second = find.byKey(const ValueKey('desk-stack-stock-1-mint-1'));
    expect(first, findsOneWidget);
    expect(
      find.byKey(const ValueKey('desk-stack-stock-2-mint-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desk-stack-stock-3-mint-3')),
      findsNothing,
    );
    expect(
      tester.getTopLeft(second).dx,
      lessThan(tester.getTopRight(first).dx),
    );
    final logo = tester.widget<CompanyLogo>(
      find.descendant(of: first, matching: find.byType(CompanyLogo)),
    );
    expect(logo.logoUrl, 'https://example.test/stock-0.png');
    expect(tester.takeException(), isNull);
  });

  testWidgets('new desk names paper and keeps one route to the market', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: DeskScreen(
          snapshot: DeskSnapshot.newRookie(handle: 'rookie'),
          onOpenMarket: () => opened++,
          onAddMoney: () {},
        ),
      ),
    );

    expect(find.text('Account balance'), findsOneWidget);
    expect(find.textContaining('10,000'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('desk-empty-open-market')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(find.text('No stocks yet'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('desk-empty-open-market')));
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desk remains usable at phone width and 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(
          theme: productTheme(),
          home: DeskScreen(
            snapshot: DeskSnapshot.newRookie(handle: 'a-long-floor-name'),
            onOpenMarket: () {},
            onAddMoney: () {},
          ),
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('desk-empty-open-market')),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('desk-empty-open-market')),
      findsOneWidget,
    );
  });

  testWidgets('an offline confirmed desk is visibly stale and retryable', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: DeskScreen(
          snapshot: DeskSnapshot.newRookie(handle: 'rookie'),
          statusMessage:
              'Showing your last confirmed paper desk. Trading is paused until Trimmy reconnects.',
          onRetry: () => retries++,
          onOpenMarket: () {},
          onAddMoney: () {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey('paper-desk-stale')), findsOneWidget);
    expect(find.textContaining('Trading is paused'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });

  testWidgets('partial valuation is labelled as known value, not a total', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: DeskScreen(
          snapshot: const DeskSnapshot(
            handle: 'rookie',
            paperValue: '9,750',
            paperValueState: DeskPaperValueState.partial,
            wallStreetLine: 'Stocks trade here 24/7.',
            holdings: [
              DeskHolding(
                assetId: 'apple',
                variantMint: 'mint-a',
                name: 'Apple',
                symbol: 'AAPLx',
                quantity: '1',
                valuePaper: '250',
                changePercent: 2,
              ),
              DeskHolding(
                assetId: 'apple',
                variantMint: 'mint-b',
                name: 'Apple',
                symbol: 'AAPLon',
                quantity: '1',
                valuePaper: null,
                changePercent: null,
              ),
            ],
          ),
          onOpenMarket: () {},
        ),
      ),
    );

    expect(find.text('Known value'), findsOneWidget);
    expect(find.text('Some prices unavailable'), findsOneWidget);
    expect(find.text('Account balance'), findsNothing);
  });

  testWidgets('unavailable valuation shows cash honestly', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: DeskScreen(
          snapshot: const DeskSnapshot(
            handle: 'rookie',
            paperValue: '9,500',
            paperValueState: DeskPaperValueState.unavailable,
            wallStreetLine: 'Stocks trade here 24/7.',
          ),
          onOpenMarket: () {},
        ),
      ),
    );

    expect(find.text('Cash balance'), findsNWidgets(2));
    expect(find.text('Position prices unavailable'), findsOneWidget);
  });

  testWidgets('career counters stay legible on the paper background', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: DeskScreen(
          snapshot: DeskSnapshot.newRookie(
            handle: 'rookie',
            streak: 1,
            trims: 10,
          ),
          onOpenMarket: () {},
          onAddMoney: () {},
        ),
      ),
    );

    final streakText = tester.widget<Text>(
      find.byKey(const ValueKey('desk-streak-count')),
    );
    final trimsText = tester.widget<Text>(
      find.byKey(const ValueKey('desk-trims-count')),
    );
    expect(streakText.style?.color, ProductColor.ink);
    expect(trimsText.style?.color, ProductColor.ink);
    expect(
      tester.getCenter(find.byKey(const ValueKey('desk-streak-count'))).dy,
      closeTo(
        tester.getCenter(find.byKey(const ValueKey('desk-trims-count'))).dy,
        .1,
      ),
    );
  });

  testWidgets('guest can reach sign in without a disabled money control', (
    tester,
  ) async {
    var signInTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: DeskScreen(
          snapshot: DeskSnapshot.newRookie(handle: 'rookie'),
          onOpenMarket: () {},
          onSignIn: () => signInTaps++,
        ),
      ),
    );

    expect(find.text('Money coming later'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('desk-save-progress')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('desk-save-progress')));
    expect(signInTaps, 1);
  });

  testWidgets('career header wraps safely on a narrow large-text phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(
          theme: productTheme(),
          home: DeskScreen(
            snapshot: DeskSnapshot.newRookie(
              handle: 'a-very-long-floor-name',
              rank: 'Senior Trader',
              streak: 1234,
              trims: 12345,
            ),
            onOpenMarket: () {},
          ),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('desk-career-counters')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey('desk-career-counters')), findsOneWidget);
    expect(find.text('1234'), findsOneWidget);
    expect(find.text('12345'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
