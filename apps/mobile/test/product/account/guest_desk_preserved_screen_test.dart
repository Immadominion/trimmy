import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/account/guest_desk_preserved_screen.dart';
import 'package:trimmy/product/design/product_theme.dart';

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  final scrollable = find.byType(Scrollable).first;
  for (var attempt = 0; attempt < 20; attempt++) {
    if (finder.hitTestable().evaluate().isNotEmpty) return;
    await tester.drag(scrollable, const Offset(0, -180));
    await tester.pump();
  }
  expect(finder.hitTestable(), findsOneWidget);
}

void main() {
  testWidgets('explains preservation and opens the saved desk', (tester) async {
    var continued = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: GuestDeskPreservedScreen(onContinue: () => continued = true),
      ),
    );

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.textContaining('guest trades stay separate'), findsOneWidget);
    expect(find.textContaining('Sign out to return'), findsOneWidget);

    final button = find.byKey(const ValueKey('open-saved-desk'));
    await _reveal(tester, button);
    await tester.tap(button.hitTestable());
    await tester.pump();
    expect(continued, isTrue);
  });

  testWidgets('remains scrollable on a small large-text phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: GuestDeskPreservedScreen(onContinue: () {}),
      ),
    );

    final button = find.byKey(const ValueKey('open-saved-desk'));
    await _reveal(tester, button);
    expect(tester.takeException(), isNull);
    expect(button.hitTestable(), findsOneWidget);
  });

  testWidgets('expired guest copy never promises that sign-out reopens it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: GuestDeskPreservedScreen(expired: true, onContinue: () {}),
      ),
    );

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.textContaining('preserved separately'), findsOneWidget);
    expect(find.textContaining('can no longer trade or merge'), findsOneWidget);
    expect(find.textContaining('Sign out to return'), findsNothing);
    final button = find.byKey(const ValueKey('open-saved-desk'));
    await _reveal(tester, button);
    expect(find.text('Go to my desk'), findsOneWidget);
  });
}
