import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/design_study/sample_evidence.dart';

Widget _paper({
  double textScale = 1,
  bool reduceMotion = false,
  bool systemReduceMotion = false,
  bool accessibleNavigation = false,
}) => MaterialApp(
  theme: ThemeData(fontFamily: 'Manrope'),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(textScale),
      disableAnimations: systemReduceMotion,
      accessibleNavigation: accessibleNavigation,
    ),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: SampleEvidence(reduceMotion: reduceMotion),
        ),
      ),
    ),
  ),
);

Finder _slip(int number) => find.byKey(
  ValueKey('sample-response-${number.toString().padLeft(2, '0')}'),
);

double _lift(WidgetTester tester, int number) => tester
    .widget<Transform>(
      find.byKey(ValueKey('sample-lift-${number.toString().padLeft(2, '0')}')),
    )
    .transform
    .storage[13];

void _phone(WidgetTester tester, {double width = 390}) {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _open(WidgetTester tester, int number) async {
  await tester.ensureVisible(_slip(number));
  await tester.tap(_slip(number));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    for (final entry in [
      ('Manrope', 'assets/fonts/manrope/Manrope-Variable.ttf'),
      ('Rubik', 'assets/fonts/rubik/Rubik-Variable.ttf'),
    ]) {
      await (FontLoader(entry.$1)..addFont(rootBundle.load(entry.$2))).load();
    }
  });

  testWidgets('source states the result and group before opening any slip', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(_paper());
    expect(find.text('Aster product trial'), findsOneWidget);
    expect(find.text('September 2026'), findsOneWidget);
    expect(find.text('10 invited beta testers / 10 replies'), findsOneWidget);
    expect(find.text('8 of 10 liked Aster.'), findsOneWidget);
    expect(find.text('2 said “Not for me.”'), findsOneWidget);
    expect(
      find.text(
        'All ten invited testers replied. Other customers were not asked.',
      ),
      findsOneWidget,
    );
    expect(find.text('Liked'), findsNWidgets(8));
    expect(find.text('Not for me'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('sample-opened-response')), findsNothing);

    final firstRow = tester.getRect(_slip(1)).top;
    final paperTop = tester.getRect(find.byType(SampleEvidence)).top;
    expect(
      firstRow - paperTop,
      lessThanOrEqualTo(150),
      reason: 'Response slips must appear near the start of the source paper',
    );
    expect(
      tester.getRect(find.text('8 of 10 liked Aster.')).top,
      greaterThan(tester.getRect(_slip(10)).bottom),
    );
    for (var number = 1; number <= 10; number++) {
      final rect = tester.getRect(_slip(number));
      expect(rect.width, greaterThanOrEqualTo(48));
      expect(rect.height, greaterThanOrEqualTo(48));
      if (number <= 5) expect(rect.top, firstRow);
      if (number > 5) expect(rect.top, greaterThan(firstRow));
    }
    expect(tester.getRect(_slip(6)).top, tester.getRect(_slip(10)).top);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'each response has full semantics and the selected identity updates',
    (tester) async {
      _phone(tester);
      await tester.pumpWidget(_paper());
      await tester.ensureVisible(_slip(3));
      expect(
        tester.getSemantics(_slip(3)),
        matchesSemantics(
          label: 'Tester 03. Liked it. Invited beta tester.',
          hint: 'Open response slip',
          isButton: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      await _open(tester, 3);
      expect(find.text('Tester 03 · Liked it'), findsOneWidget);
      expect(
        tester.getSemantics(_slip(3)),
        matchesSemantics(
          label: 'Tester 03. Liked it. Invited beta tester.',
          hint: 'Close response slip',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      await _open(tester, 10);
      expect(find.text('Tester 10 · Not for me'), findsOneWidget);
      expect(find.text('Tester 03 · Liked it'), findsNothing);
      expect(
        find.text('Invited beta tester\nAster product trial · September 2026'),
        findsOneWidget,
      );
      // Selecting a different slip never changes the fixed survey totals.
      expect(find.text('8 of 10 liked Aster.'), findsOneWidget);
      await _open(tester, 10);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('sample-opened-response')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('200 percent text reflows and every response remains operable', (
    tester,
  ) async {
    _phone(tester, width: 320);
    await tester.pumpWidget(_paper(textScale: 2));
    final firstRow = tester.getRect(_slip(1)).top;
    expect(tester.getRect(_slip(2)).top, firstRow);
    expect(tester.getRect(_slip(3)).top, greaterThan(firstRow));
    for (var number = 1; number <= 10; number++) {
      await _open(tester, number);
      await tester.pumpAndSettle();
      final rect = tester.getRect(_slip(number));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320));
      expect(rect.width, greaterThanOrEqualTo(48));
      expect(rect.height, greaterThanOrEqualTo(48));
      expect(
        tester.takeException(),
        isNull,
        reason: 'Response $number must fit',
      );
    }
    await tester.ensureVisible(
      find.text(
        'All ten invited testers replied. Other customers were not asked.',
      ),
    );
    expect(find.text('Tester 10 · Not for me'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'lift reverses continuously and disposal cancels the finite motion',
    (tester) async {
      _phone(tester);
      await tester.pumpWidget(_paper());
      await _open(tester, 3);
      await tester.pump(const Duration(milliseconds: 80));
      final interrupted = _lift(tester, 3);
      expect(interrupted, lessThan(0));
      expect(interrupted, greaterThan(-4));
      await _open(tester, 4);
      expect(_lift(tester, 3), closeTo(interrupted, .001));
      await tester.pumpAndSettle();
      expect(_lift(tester, 3), 0);
      expect(_lift(tester, 4), -4);
      expect(tester.binding.transientCallbackCount, 0);
      await _open(tester, 5);
      await tester.pump(const Duration(milliseconds: 70));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in ['widget', 'system', 'accessibility']) {
    testWidgets(
      '$mode reduced motion settles an interrupted slip immediately',
      (tester) async {
        _phone(tester);
        await tester.pumpWidget(_paper());
        await _open(tester, 3);
        await tester.pump(const Duration(milliseconds: 80));
        expect(_lift(tester, 3), greaterThan(-4));
        await tester.pumpWidget(
          _paper(
            reduceMotion: mode == 'widget',
            systemReduceMotion: mode == 'system',
            accessibleNavigation: mode == 'accessibility',
          ),
        );
        expect(_lift(tester, 3), -4);
        await _open(tester, 4);
        expect(_lift(tester, 3), 0);
        expect(_lift(tester, 4), -4);
        expect(find.text('Tester 04 · Liked it'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 250));
        expect(tester.binding.transientCallbackCount, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a focused slip supports keyboard activation', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_paper());
    await _open(tester, 3);
    expect(find.text('Tester 03 · Liked it'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sample-opened-response')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('Tester 03 · Liked it'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
