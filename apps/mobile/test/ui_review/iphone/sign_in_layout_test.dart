import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/ui_review/review_optional_setup.dart';

const _methods = ['email', 'Apple', 'Google', 'X'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final scenario in [
    (name: 'iPhone', size: const Size(393, 852), textScale: 1.0),
    (name: 'compact phone', size: const Size(320, 568), textScale: 1.0),
    (
      name: 'compact phone with large text',
      size: const Size(320, 568),
      textScale: 2.0,
    ),
  ]) {
    testWidgets('sign-in actions remain reachable on ${scenario.name}', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        size: scenario.size,
        textScale: scenario.textScale,
      );

      expect(find.text('Welcome back.'), findsOneWidget);
      expect(find.text('Your next move is waiting.'), findsOneWidget);
      expect(find.text('Back to welcome'), findsNothing);
      expect(find.byTooltip('Close sign in'), findsOneWidget);
      expect(tester.takeException(), isNull);

      for (final method in _methods) {
        final action = _methodAction(method);
        expect(action, findsOneWidget);
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        expect(action.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('each sign-in method opens an honest dismissible preview', (
    tester,
  ) async {
    var closeCount = 0;
    await _pumpPage(tester, onClose: () => closeCount++);

    for (final method in _methods) {
      final action = _methodAction(method);
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      await tester.tap(action);
      await tester.pumpAndSettle();

      expect(find.text('$method sign-in preview'), findsOneWidget);
      expect(
        find.textContaining('No account has been connected'),
        findsOneWidget,
      );
      expect(closeCount, 0);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.text('$method sign-in preview'), findsNothing);
      expect(find.byTooltip('Close sign in'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    expect(closeCount, 0);
  });

  testWidgets('close sign-in returns through its provided callback', (
    tester,
  ) async {
    var closeCount = 0;
    await _pumpPage(tester, onClose: () => closeCount++);

    await tester.tap(find.byTooltip('Close sign in'));
    await tester.pumpAndSettle();

    expect(closeCount, 1);
    expect(tester.takeException(), isNull);
  });

  for (final accessibilityNavigation in [false, true]) {
    testWidgets(
      accessibilityNavigation
          ? 'accessible navigation leaves sign-in settled and usable'
          : 'reduced motion leaves sign-in settled and usable',
      (tester) async {
        await _pumpPage(
          tester,
          disableAnimations: !accessibilityNavigation,
          accessibleNavigation: accessibilityNavigation,
        );

        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 2),
        );

        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(find.text('Welcome back.'), findsOneWidget);
        final email = _methodAction('email');
        await tester.ensureVisible(email);
        await tester.pumpAndSettle();
        expect(email.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('save progress keeps its existing account options and return', (
    tester,
  ) async {
    var closeCount = 0;
    await _pumpPage(tester, signIn: false, onClose: () => closeCount++);

    expect(find.text('Keep your career with you.'), findsOneWidget);
    expect(find.text('@reviewer'), findsOneWidget);
    for (final method in _methods) {
      expect(find.text('Continue with $method'), findsOneWidget);
    }
    expect(
      find.text('UI preview • Sign-in is not connected here.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Back to my desk'));
    await tester.pumpAndSettle();
    expect(closeCount, 1);
    expect(tester.takeException(), isNull);
  });
}

Finder _methodAction(String method) => find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.button == true &&
      widget.properties.label == 'Continue with $method',
  description: 'accessible Continue with $method button',
);

Future<void> _pumpPage(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  double textScale = 1,
  bool signIn = true,
  bool disableAnimations = true,
  bool accessibleNavigation = false,
  VoidCallback? onClose,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true, fontFamily: 'Dejanire Sans'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          padding: const EdgeInsets.only(top: 47, bottom: 34),
          disableAnimations: disableAnimations,
          accessibleNavigation: accessibleNavigation,
        ),
        child: child!,
      ),
      home: ReviewAccountOptionsPage(
        signIn: signIn,
        username: signIn ? null : 'reviewer',
        onClose: onClose ?? () {},
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
}
