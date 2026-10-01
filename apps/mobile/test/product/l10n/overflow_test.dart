import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/ui_review/review_feedback.dart';

import '../../support/l10n_harness.dart';
import 'l10n_screens.dart';

/// Scrolls the screen's main list to the end, a page at a time, so rows
/// built on demand are laid out too. Fails on the first overflow.
Future<void> _scrollThrough(WidgetTester tester, String where) async {
  final lists = find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable && widget.axisDirection == AxisDirection.down,
  );
  if (lists.hitTestable().evaluate().isEmpty) return;
  final list = lists.hitTestable().first;
  for (var page = 0; page < 10; page++) {
    final before = tester.state<ScrollableState>(list).position.pixels;
    await tester.drag(list, const Offset(0, -400), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull, reason: '$where, page $page');
    if (tester.state<ScrollableState>(list).position.pixels == before) break;
  }
}

void main() {
  setUp(() async {
    quietAudioForL10nScreens();
    await ReviewFeedback.shared.load();
    ReviewFeedback.shared.sound = false;
    ReviewFeedback.shared.haptics = false;
  });

  for (final locale in longLocales) {
    for (final screen in l10nScreens) {
      testWidgets('$locale: ${screen.name} fits a 375x667 phone at 130% text', (
        tester,
      ) async {
        final context = await pumpL10nScreen(
          tester,
          screen,
          locale,
          textScale: 1.3,
        );
        expect(tester.takeException(), isNull, reason: screen.name);
        if (screen.reveal != null) {
          await screen.reveal!(tester);
          await settleL10nScreen(tester);
          expect(tester.takeException(), isNull, reason: screen.name);
        }
        await _scrollThrough(tester, screen.name);
        await disposeL10nScreen(tester, context);
      });
    }
  }
}
