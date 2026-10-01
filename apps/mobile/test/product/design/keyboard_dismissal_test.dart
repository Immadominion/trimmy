import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/design/keyboard_dismissal.dart';

void main() {
  testWidgets(
    'a tap on empty sheet space closes the keyboard; controls and the backdrop keep working',
    (tester) async {
      var pressed = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => KeyboardDismissal(child: child!),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => Padding(
                      padding: const EdgeInsets.all(48),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const TextField(
                            key: Key('amount'),
                            keyboardType: TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                          const SizedBox(height: 120),
                          TextButton(
                            onPressed: () => pressed++,
                            child: const Text('Max'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  child: const Text('Buy'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Buy'));
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('amount'));
      bool focused() => tester
          .widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .focusNode
          .hasFocus;

      await tester.tap(field);
      await tester.pump();
      expect(focused(), isTrue);
      expect(tester.testTextInput.isVisible, isTrue);

      // A control keeps its tap, and the field stays focused.
      await tester.tap(find.text('Max'));
      await tester.pump();
      expect(pressed, 1);
      expect(focused(), isTrue);

      // Empty space inside the sheet closes the keyboard; the sheet stays open.
      await tester.tapAt(
        tester.getTopLeft(find.byType(BottomSheet)) + const Offset(12, 12),
      );
      await tester.pump();
      expect(focused(), isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(find.byType(BottomSheet), findsOneWidget);

      // The backdrop still closes the sheet.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    },
  );

  testWidgets('focus on a non-text control is left alone', (tester) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => KeyboardDismissal(child: child!),
        home: Scaffold(
          body: Center(
            child: TextButton(
              focusNode: node,
              onPressed: () {},
              child: const Text('Go'),
            ),
          ),
        ),
      ),
    );
    node.requestFocus();
    await tester.pump();
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    expect(node.hasFocus, isTrue);
  });
}
