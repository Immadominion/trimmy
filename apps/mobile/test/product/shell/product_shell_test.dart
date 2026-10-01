import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/l10n/l10n.dart';
import 'package:trimmy/product/design/product_theme.dart';
import 'package:trimmy/product/shell/product_shell.dart';

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
