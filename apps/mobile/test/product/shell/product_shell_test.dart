import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/l10n/l10n.dart';
import 'package:trimmy/product/design/product_theme.dart';
import 'package:trimmy/product/shell/product_shell.dart';
import 'package:trimmy/product/shell/product_tab_top.dart';

void main() {
  testWidgets('four destinations switch one persistent app shell', (
    tester,
  ) async {
    final changes = <ProductTab>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: ProductShell(
          desk: const _CounterPage(label: 'Desk body'),
          market: const _CounterPage(label: 'Market body'),
          floor: const _CounterPage(label: 'Floor body'),
          profile: const _CounterPage(label: 'Profile body'),
          onTabChanged: changes.add,
        ),
      ),
    );

    expect(find.text('Desk body'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('product-tab-market')));
    await tester.pumpAndSettle();
    expect(find.text('Market body'), findsOneWidget);
    expect(changes, [ProductTab.market]);

    await tester.tap(find.text('Increase'));
    await tester.tap(find.byKey(const ValueKey('product-tab-floor')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('product-tab-market')));
    await tester.pumpAndSettle();
    expect(find.text('Count 1'), findsOneWidget);
  });

  testWidgets('tapping the open tab again scrolls only that tab to the start', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: const ProductShell(
          desk: _LongPage(label: 'desk'),
          market: _OwnScrollPage(label: 'market'),
          floor: _LongPage(label: 'floor'),
          profile: _LongPage(label: 'profile'),
        ),
      ),
    );
    double offset(String label) => tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(ValueKey('list-$label'), skipOffstage: false),
            matching: find.byType(Scrollable, skipOffstage: false),
            matchRoot: true,
          ),
        )
        .position
        .pixels;
    Future<void> tab(String name) async {
      await tester.tap(find.byKey(ValueKey('product-tab-$name')));
      await tester.pumpAndSettle();
    }

    Future<void> scroll(String label) async {
      await tester.drag(
        find.byKey(ValueKey('list-$label')),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
    }

    await scroll('desk');
    await tab('floor');
    await scroll('floor');
    // Switching tabs keeps each tab where it was.
    await tab('desk');
    expect(offset('desk'), greaterThan(0));
    await tab('desk');
    expect(offset('desk'), 0);
    expect(offset('floor'), greaterThan(0));

    // A page with its own scroll controller hears it too.
    await tab('market');
    await scroll('market');
    await tab('market');
    expect(offset('market'), 0);
    expect(offset('floor'), greaterThan(0));
  });

  testWidgets('tab names fit a narrow phone in every language', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    for (final (locale, desk) in [
      (const Locale('en'), 'Desk'),
      (const Locale('es', '419'), 'Escritorio'),
      (const Locale('pt', 'BR'), 'Mesa'),
      (const Locale('fr'), 'Bureau'),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: productTheme(),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ProductShell(
            desk: SizedBox(),
            market: SizedBox(),
            floor: SizedBox(),
            profile: SizedBox(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(desk), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('the tab bar holds at the largest accessibility text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    // iOS's largest accessibility size.
    tester.platformDispatcher.textScaleFactorTestValue = 3.1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ProductShell(
          desk: SizedBox(),
          market: SizedBox(),
          floor: SizedBox(),
          profile: SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Desk'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'no overflow in the bar');
  });
}

class _CounterPage extends StatefulWidget {
  const _CounterPage({required this.label});
  final String label;
  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<_CounterPage> {
  var count = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Text(widget.label),
        Text('Count $count'),
        TextButton(
          onPressed: () => setState(() => count++),
          child: const Text('Increase'),
        ),
      ],
    ),
  );
}

class _LongPage extends StatelessWidget {
  const _LongPage({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => ListView(
    key: ValueKey('list-$label'),
    children: [
      for (var i = 0; i < 60; i++)
        SizedBox(height: 60, child: Text('$label $i')),
    ],
  );
}

class _OwnScrollPage extends StatefulWidget {
  const _OwnScrollPage({required this.label});
  final String label;
  @override
  State<_OwnScrollPage> createState() => _OwnScrollPageState();
}

class _OwnScrollPageState extends State<_OwnScrollPage>
    with ProductTabTopListener {
  final _scroll = ScrollController();
  @override
  void onTabTop() => productScrollTo(context, _scroll, 0);
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    key: ValueKey('list-${widget.label}'),
    controller: _scroll,
    children: [
      for (var i = 0; i < 60; i++)
        SizedBox(height: 60, child: Text('${widget.label} $i')),
    ],
  );
}
