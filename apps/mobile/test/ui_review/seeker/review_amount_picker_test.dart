import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/ui_review/review_amount_picker.dart';
import 'package:trimmy/ui_review/review_feedback.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ReviewFeedback.shared.sound = false;
    ReviewFeedback.shared.haptics = false;
  });

  testWidgets(
    'selected increments stay fixed across repeated plus and minus taps',
    (tester) async {
      final host = GlobalKey<_AmountHostState>();
      await tester.pumpWidget(_host(_AmountHost(key: host)));
      await tester.tap(find.byTooltip('Increase amount by 100 dollars'));
      await tester.pumpAndSettle();
      expect(host.currentState!.result, 200);
      await tester.tap(find.byTooltip('Increase amount by 100 dollars'));
      await tester.pumpAndSettle();
      expect(host.currentState!.result, 300);

      await tester.tap(find.text('\$50'));
      await tester.pumpAndSettle();
      expect(host.currentState!.result, 50);
      await tester.tap(find.byTooltip('Increase amount by 50 dollars'));
      await tester.pumpAndSettle();
      expect(host.currentState!.result, 100);
      await tester.tap(find.byTooltip('Increase amount by 50 dollars'));
      await tester.pumpAndSettle();
      expect(host.currentState!.result, 150);
      await tester.tap(find.byTooltip('Decrease amount by 50 dollars'));
      await tester.pumpAndSettle();
      expect(host.currentState!.result, 100);

      await tester.tap(find.text('\$25'));
      await tester.pumpAndSettle();
      expect(host.currentState!.result, 25);
      await tester.tap(find.byTooltip('Increase amount by 25 dollars'));
      await tester.pumpAndSettle();
      expect(host.currentState!.result, 50);
      await tester.tap(find.byTooltip('Increase amount by 25 dollars'));
      await tester.pumpAndSettle();
      expect(host.currentState!.result, 75);
      await tester.tap(find.byTooltip('Decrease amount by 25 dollars'));
      await tester.pumpAndSettle();
      expect(host.currentState!.result, 50);
    },
  );

  testWidgets(
    'committed decimals become a stable increment without repeated doubling',
    (tester) async {
      final host = GlobalKey<_AmountHostState>();
      await tester.pumpWidget(_host(_AmountHost(key: host)));
      await _openEditor(tester);
      final field = find.byKey(const ValueKey('review-amount-input'));
      await tester.enterText(field, '42.75');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(field, findsNothing);
      await tester.tap(find.byTooltip('Increase amount by 42.75 dollars'));
      await tester.pumpAndSettle();
      expect(host.currentState!.result, 85.50);
      await tester.tap(find.byTooltip('Increase amount by 42.75 dollars'));
      await tester.pumpAndSettle();
      expect(host.currentState!.result, 128.25);

      // Looking at the editor without changing its text does not reset the step.
      await _openEditor(tester);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Increase amount by 42.75 dollars'));
      await tester.pumpAndSettle();
      expect(host.currentState!.result, 171);
    },
  );

  testWidgets('plus commits a pending custom draft and keeps that increment', (
    tester,
  ) async {
    final host = GlobalKey<_AmountHostState>();
    await tester.pumpWidget(_host(_AmountHost(key: host)));
    await _openEditor(tester);
    final field = find.byKey(const ValueKey('review-amount-input'));
    await tester.enterText(field, '18.25');
    await tester.pump();
    await tester.tap(find.byTooltip('Increase amount by 18.25 dollars'));
    await tester.pumpAndSettle();
    expect(host.currentState!.result, 36.50);
    expect(field, findsNothing);
    await tester.tap(find.byTooltip('Increase amount by 18.25 dollars'));
    await tester.pumpAndSettle();
    expect(host.currentState!.result, 54.75);
  });

  testWidgets(
    'custom decimal edits keep their native text and report invalid drafts',
    (tester) async {
      final host = GlobalKey<_AmountHostState>();
      await tester.pumpWidget(_host(_AmountHost(key: host)));
      await _openEditor(tester);
      final field = find.byKey(const ValueKey('review-amount-input'));
      await tester.enterText(field, '42.');
      await tester.pump();
      expect(host.currentState!.result, 42);
      expect(tester.widget<TextField>(field).controller!.text, '42.');
      await tester.enterText(field, '42.75');
      await tester.pump();
      expect(host.currentState!.result, 42.75);
      await tester.enterText(field, '');
      await tester.pump();
      expect(host.currentState!.result, isNull);
      expect(find.text('Enter an amount.'), findsOneWidget);
      // Intermediate keystrokes do not silently replace the committed step.
      expect(find.byTooltip('Increase amount by 100 dollars'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(field, findsOneWidget);
      expect(host.currentState!.result, isNull);
      await tester.tap(find.text('\$50'));
      await tester.pumpAndSettle();
      expect(host.currentState!.result, 50);
      expect(find.text('Enter an amount.'), findsNothing);
      expect(field, findsNothing);
    },
  );

  testWidgets('bounds prevent invalid submission and stepping past limits', (
    tester,
  ) async {
    final host = GlobalKey<_AmountHostState>();
    await tester.pumpWidget(_host(_AmountHost(key: host)));
    await _openEditor(tester);
    final field = find.byKey(const ValueKey('review-amount-input'));
    await tester.enterText(field, '10001');
    await tester.pump();
    expect(host.currentState!.result, isNull);
    expect(find.text('Choose up to \$10000.'), findsOneWidget);
    await tester.enterText(field, '9999');
    await tester.pump();
    await tester.tap(find.byTooltip('Increase amount by 9999 dollars'));
    await tester.pumpAndSettle();
    expect(host.currentState!.result, 10000);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Increase amount by 9999 dollars'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await _openEditor(tester);
    await tester.enterText(field, '0');
    await tester.pump();
    expect(host.currentState!.result, isNull);
    expect(find.text('Choose at least \$1.'), findsOneWidget);
    await tester.enterText(field, '2');
    await tester.pump();
    await tester.tap(find.byTooltip('Decrease amount by 2 dollars'));
    await tester.pumpAndSettle();
    expect(host.currentState!.result, 1);
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('Decrease amount by 2 dollars'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'decimal comma works and excess fraction digits are not accepted',
    (tester) async {
      final host = GlobalKey<_AmountHostState>();
      await tester.pumpWidget(_host(_AmountHost(key: host)));
      await _openEditor(tester);
      final field = find.byKey(const ValueKey('review-amount-input'));
      await tester.enterText(field, '18,25');
      await tester.pump();
      expect(host.currentState!.result, 18.25);
      await tester.enterText(field, '18,255');
      await tester.pump();
      expect(host.currentState!.result, 18.25);
      expect(tester.widget<TextField>(field).controller!.text, '18,25');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(field, findsNothing);
      expect(host.currentState!.result, 18.25);
    },
  );

  testWidgets(
    '320-wide large text remains usable with keyboard and reduced motion',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final host = GlobalKey<_AmountHostState>();
      await tester.pumpWidget(
        _host(_AmountHost(key: host), textScale: 2, bottomInset: 300),
      );
      await tester.tap(find.text('\$50'));
      await tester.pump();
      expect(host.currentState!.result, 50);
      expect(tester.takeException(), isNull);
      for (final switcher in tester.widgetList<AnimatedSwitcher>(
        find.byType(AnimatedSwitcher),
      )) {
        expect(switcher.duration, Duration.zero);
      }
      await _openEditor(tester);
      final field = find.byKey(const ValueKey('review-amount-input'));
      await tester.enterText(field, '123.45');
      await tester.pump();
      expect(host.currentState!.result, 123.45);
      await tester.ensureVisible(find.text('Done'));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(field, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _openEditor(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('review-amount-edit'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Widget _host(Widget child, {double textScale = 1, double bottomInset = 0}) =>
    MaterialApp(
      theme: ThemeData(useMaterial3: true, fontFamily: 'Dejanire Sans'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(textScale),
          viewInsets: EdgeInsets.only(bottom: bottomInset),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: child,
        ),
      ),
    );

class _AmountHost extends StatefulWidget {
  const _AmountHost({super.key});
  @override
  State<_AmountHost> createState() => _AmountHostState();
}

class _AmountHostState extends State<_AmountHost> {
  double value = 100;
  double? result = 100;

  @override
  Widget build(BuildContext context) => ReviewAmountPicker(
    value: value,
    onChanged: (next) => setState(() {
      result = next;
      if (next != null) value = next;
    }),
  );
}
