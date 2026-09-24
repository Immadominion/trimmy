import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
