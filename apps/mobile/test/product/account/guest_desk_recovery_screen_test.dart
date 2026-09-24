import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/account/guest_desk_recovery_screen.dart';
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
  testWidgets('preserves the desk until the second explicit restart action', (
    tester,
  ) async {
    var starts = 0;
    var signIns = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: GuestDeskRecoveryScreen(
          onSignIn: () => signIns++,
          onStartNew: () async => starts++,
        ),
      ),
    );

    expect(find.text('Guest session expired'), findsOneWidget);
    expect(find.textContaining('stays untouched'), findsOneWidget);
    expect(starts, 0);

    final signIn = find.byKey(const ValueKey('guest-recovery-sign-in'));
    await _reveal(tester, signIn);
    await tester.tap(signIn.hitTestable());
    expect(signIns, 1);
    expect(starts, 0);

    final start = find.byKey(const ValueKey('guest-recovery-start-new'));
    await _reveal(tester, start);
    await tester.tap(start.hitTestable());
    await tester.pump();
    expect(find.text('Start fresh?'), findsOneWidget);
    expect(starts, 0);

    final keep = find.byKey(const ValueKey('guest-recovery-keep-desk'));
    await _reveal(tester, keep);
    await tester.tap(keep.hitTestable());
    await tester.pump();
    expect(find.text('Guest session expired'), findsOneWidget);
    expect(starts, 0);

    await _reveal(tester, start);
    await tester.tap(start.hitTestable());
    await tester.pump();
    final confirm = find.byKey(
      const ValueKey('guest-recovery-confirm-start-new'),
    );
    await _reveal(tester, confirm);
    await tester.tap(confirm.hitTestable());
    await tester.pump();
    expect(starts, 1);
  });

  testWidgets('failed restart reports preservation and permits a retry', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: GuestDeskRecoveryScreen(
          onStartNew: () async {
            calls++;
            if (calls == 1) throw StateError('offline');
          },
        ),
      ),
    );

    final start = find.byKey(const ValueKey('guest-recovery-start-new'));
    await _reveal(tester, start);
    await tester.tap(start.hitTestable());
    await tester.pump();
    final confirm = find.byKey(
      const ValueKey('guest-recovery-confirm-start-new'),
    );
    await _reveal(tester, confirm);
    await tester.tap(confirm.hitTestable());
    await tester.pumpAndSettle();

    expect(calls, 1);
    final error = find.byKey(const ValueKey('guest-recovery-error'));
    await _reveal(tester, error);
    expect(
      find.text('Couldn’t start again. Your expired desk is still preserved.'),
      findsOneWidget,
    );

    await _reveal(tester, confirm);
    await tester.tap(confirm.hitTestable());
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('stays usable on a small large-text phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: GuestDeskRecoveryScreen(onStartNew: () async {}),
      ),
    );

    final start = find.byKey(const ValueKey('guest-recovery-start-new'));
    await _reveal(tester, start);
    expect(start.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
