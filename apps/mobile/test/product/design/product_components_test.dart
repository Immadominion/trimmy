import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/design/product_components.dart';
import 'package:trimmy/product/design/product_theme.dart';

void main() {
  testWidgets('the complete visible button face accepts taps', (tester) async {
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ProductButton(
                label: 'Continue',
                onPressed: () => presses += 1,
              ),
            ),
          ),
        ),
      ),
    );

    final button = find.byType(ProductButton);
    final inkWell = find.descendant(of: button, matching: find.byType(InkWell));
    expect(tester.getSize(inkWell).width, tester.getSize(button).width);

    final rect = tester.getRect(button);
    await tester.tapAt(Offset(rect.right - 12, rect.center.dy - 3));
    await tester.pump();

    expect(presses, 1);
  });
}
