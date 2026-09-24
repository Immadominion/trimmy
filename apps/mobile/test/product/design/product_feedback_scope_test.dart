import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/design/product_feedback_scope.dart';
import 'package:trimmy/ui_review/review_feedback.dart';

class FeedbackSpy extends ReviewFeedback {
  int prepared = 0, presses = 0;
  @override
  Future<void> prepareTap() async {
    prepared++;
  }

  @override
  Future<void> prepareWork() async {}
  @override
  void press({bool selection = false}) {
    presses++;
    haptics = false;
    super.press(selection: selection);
  }
}

void main() {
  testWidgets(
    'returning entry prepares feedback; buttons and sheets emit once',
    (tester) async {
      final feedback = FeedbackSpy();
      addTearDown(feedback.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) =>
              ProductFeedbackScope(feedback: feedback, child: child!),
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  FilledButton(onPressed: () {}, child: const Text('Buy')),
                  TextButton(
                    onPressed: () => feedback.press(),
                    child: const Text('Explicit cue'),
                  ),
                  TextButton(
                    onPressed: () => showModalBottomSheet<void>(
                      context: context,
                      builder: (_) => TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close sheet'),
                      ),
                    ),
                    child: const Text('Open sheet'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(feedback.prepared, 1);
      await tester.tap(find.text('Buy'));
      await tester.pump();
      expect(feedback.presses, 1);
      await tester.tap(find.text('Explicit cue'));
      await tester.pump();
      expect(feedback.presses, 2);
      await tester.tap(find.text('Open sheet'));
      await tester.pumpAndSettle();
      expect(feedback.presses, 3);
      await tester.tap(find.text('Close sheet'));
      await tester.pumpAndSettle();
      expect(feedback.presses, 4);
    },
  );

  testWidgets(
    'disabled controls, drags, long presses and cancellation stay silent',
    (tester) async {
      final feedback = FeedbackSpy();
      addTearDown(feedback.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ProductFeedbackScope(
            feedback: feedback,
            child: Scaffold(
              body: ListView(
                children: [
                  const FilledButton(onPressed: null, child: Text('Disabled')),
                  TextButton(onPressed: () {}, child: const Text('Enabled')),
                  const SizedBox(height: 1600),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Disabled'));
      await tester.pump();
      await tester.longPress(find.text('Enabled'));
      await tester.pump();
      final cancelled = await tester.startGesture(
        tester.getCenter(find.text('Enabled')),
      );
      await cancelled.cancel();
      await tester.drag(find.text('Enabled'), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(feedback.presses, 0);
    },
  );
}
