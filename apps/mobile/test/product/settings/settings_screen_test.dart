import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/design/product_theme.dart';
import 'package:trimmy/product/settings/settings.dart';

void main() {
  testWidgets('sound and haptic switches delegate independently', (
    tester,
  ) async {
    bool? sound;
    bool? haptics;
    await tester.pumpWidget(
      MaterialApp(
        theme: productTheme(),
        home: ProductSettingsScreen(
          state: _state(),
          onSoundChanged: (v) => sound = v,
          onHapticsChanged: (v) => haptics = v,
        ),
      ),
    );
    await _show(tester, 'Sound');
    await tester.tap(find.byKey(const ValueKey('settings-sound')));
    expect(sound, false);
    expect(haptics, isNull);
    await _show(tester, 'Haptics');
    await tester.tap(find.byKey(const ValueKey('settings-haptics')));
    expect(haptics, false);
  });

  testWidgets('shows guest settings without dead financial actions', (
    tester,
  ) async {
    await tester.pumpWidget(_app(state: _state()));

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('@mira'), findsNothing);
    expect(find.text('The Wolf'), findsOneWidget);

    expect(find.text('Money'), findsNothing);
    expect(find.text('Wallet'), findsNothing);
    expect(find.text('Currency'), findsNothing);
    expect(find.text('Deposit partner'), findsNothing);
    expect(find.text('Bank accounts'), findsNothing);
    expect(find.text('Cards'), findsNothing);
  });

  testWidgets(
    'notification switches delegate changes and unavailable stays safe',
    (tester) async {
      SettingsNotificationKind? changedKind;
      bool? changedValue;
      final state = _state(
        notifications: {
          SettingsNotificationKind.wallStreetOpen:
              const SettingsNotificationValue(enabled: true),
          SettingsNotificationKind.priceAlerts: const SettingsNotificationValue(
            enabled: false,
            available: false,
          ),
        },
      );

      await tester.pumpWidget(
        _app(
          state: state,
          onNotificationChanged: (kind, enabled) {
            changedKind = kind;
            changedValue = enabled;
          },
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('notification-wallStreetOpen')),
      );
      expect(changedKind, SettingsNotificationKind.wallStreetOpen);
      expect(changedValue, isFalse);

      await _show(tester, 'Price alerts');
      changedKind = null;
      changedValue = null;
      await tester.tap(find.byKey(const ValueKey('notification-priceAlerts')));
      expect(changedKind, isNull);
      expect(changedValue, isNull);
      expect(find.text('Not available yet.'), findsWidgets);
    },
  );

  testWidgets('paper reset requires confirmation before delegating', (
    tester,
  ) async {
    var resets = 0;
    await tester.pumpWidget(
      _app(
        state: _state(resetAvailable: true),
        onResetPaper: () async {
          resets += 1;
          return SettingsPaperResetReceipt(
            revision: 4,
            currentRevision: 4,
            paperBalance: '10,000',
            resetAt: DateTime.utc(2026, 9, 20, 12),
          );
        },
      ),
    );

    await _show(tester, 'Reset paper');
    await tester.tap(find.byKey(const ValueKey('settings-reset-paper')));
    await tester.pumpAndSettle();
    expect(find.text('Reset your paper desk?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(resets, 0);

    await tester.tap(find.byKey(const ValueKey('settings-reset-paper')));
    await tester.pumpAndSettle();
    final confirm = find.byKey(const ValueKey('confirm-reset-paper'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('paper-reset-confirmation')),
      'Reset my paper desk',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('paper-reset-confirmation')),
      'reset my paper desk',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(resets, 1);
    expect(find.text('Paper desk reset'), findsOneWidget);
    expect(find.text('Your desk is ready with 10,000 paper.'), findsOneWidget);
  });

  testWidgets('paper reset receipt reports preserved newer activity', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        state: _state(resetAvailable: true),
        onResetPaper: () async => SettingsPaperResetReceipt(
          revision: 4,
          currentRevision: 5,
          paperBalance: '9,250',
          resetAt: DateTime.utc(2026, 9, 20, 12),
        ),
      ),
    );

    await _show(tester, 'Reset paper');
    await tester.tap(find.byKey(const ValueKey('settings-reset-paper')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('paper-reset-confirmation')),
      'reset my paper desk',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('confirm-reset-paper')));
    await tester.pumpAndSettle();

    expect(
      find.text('Newer trades were kept. Your balance is 9,250 paper.'),
      findsOneWidget,
    );
    expect(find.textContaining('Your fresh desk is ready'), findsNothing);
  });

  testWidgets('paper reset confirmation is labeled and reports a stale desk', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        state: _state(resetAvailable: true),
        onResetPaper: () async => throw const SettingsPaperResetException(
          SettingsPaperResetFailure.staleRevision,
        ),
      ),
    );

    await _show(tester, 'Reset paper');
    await tester.tap(find.byKey(const ValueKey('settings-reset-paper')));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('paper-reset-confirmation'));
    expect(
      find.bySemanticsLabel('Confirmation phrase. Type reset my paper desk.'),
      findsOneWidget,
    );
    expect(find.text('Reset paper desk'), findsOneWidget);

    await tester.enterText(field, 'reset my paper desk');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('confirm-reset-paper')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Your paper desk changed. It was refreshed. Review it, then confirm the reset again.',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('privacy, legal and closure rows call only supplied actions', (
    tester,
  ) async {
    SettingsVisibility? visibility;
    var openedTerms = false;
    var closeRequests = 0;
    await tester.pumpWidget(
      _app(
        state: _state(signedIn: true),
        onHoldingsVisibilityChanged: (next) => visibility = next,
        onTerms: () => openedTerms = true,
        onCloseAccount: () => closeRequests += 1,
      ),
    );

    await _show(tester, 'Who sees my holdings');
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('settings-holdings-visibility')),
        matching: find.text('Friends'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nobody').last);
    await tester.pumpAndSettle();
    expect(visibility, SettingsVisibility.nobody);

    await _show(tester, 'Terms');
    await tester.tap(find.text('Terms'));
    expect(openedTerms, isTrue);

    await _show(tester, 'Close account');
    await tester.tap(find.byKey(const ValueKey('settings-close-account')));
    expect(closeRequests, 1);
  });

  testWidgets('remains scrollable on a small phone with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: _app(state: _state(signedIn: true), onCloseAccount: () {}),
      ),
    );
    await _show(tester, 'Close account');

    expect(find.text('Close account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hides settings that have no production contract', (
    tester,
  ) async {
    await tester.pumpWidget(_app(state: _state(includePrivacy: false)));

    expect(find.byKey(const ValueKey('settings-reset-paper')), findsNothing);
    expect(
      find.byKey(const ValueKey('settings-holdings-visibility')),
      findsNothing,
    );
    expect(find.text('Support'), findsNothing);
    expect(find.text('Report a bug'), findsNothing);
  });
}

Widget _app({
  required ProductSettingsState state,
  SettingsNotificationChanged? onNotificationChanged,
  SettingsPaperReset? onResetPaper,
  ValueChanged<SettingsVisibility>? onHoldingsVisibilityChanged,
  VoidCallback? onTerms,
  VoidCallback? onCloseAccount,
}) => MaterialApp(
  theme: productTheme(),
  home: ProductSettingsScreen(
    state: state,
    onNotificationChanged: onNotificationChanged,
    onResetPaper: onResetPaper,
    onHoldingsVisibilityChanged: onHoldingsVisibilityChanged,
    onTerms: onTerms,
    onCloseAccount: onCloseAccount,
  ),
);

ProductSettingsState _state({
  bool signedIn = false,
  bool includePrivacy = true,
  bool resetAvailable = false,
  Map<SettingsNotificationKind, SettingsNotificationValue> notifications =
      const {},
}) => ProductSettingsState(
  account: SettingsAccountState(
    signedIn: signedIn,
    handle: '@mira',
    persona: 'The Wolf',
    email: signedIn ? 'mira@example.com' : null,
    signInMethods: signedIn
        ? const {SettingsSignInMethod.email, SettingsSignInMethod.x}
        : const {},
  ),
  notifications: notifications,
  quietHours: const SettingsQuietHours(
    enabled: true,
    startLabel: '10:00 PM',
    endLabel: '7:00 AM',
  ),
  appearance: const SettingsAppearanceState(
    soundEnabled: true,
    hapticsEnabled: true,
    animationsEnabled: true,
    systemReduceMotionEnabled: false,
    languageLabel: 'English',
  ),
  paper: SettingsPaperState(limit: 10000, resetAvailable: resetAvailable),
  money: const SettingsMoneyState(
    availability: SettingsFeatureAvailability.comingSoon,
  ),
  wallet: const SettingsWalletState(
    availability: SettingsFeatureAvailability.unavailable,
  ),
  privacy: includePrivacy
      ? const SettingsPrivacyState(
          holdingsVisibility: SettingsVisibility.friends,
        )
      : null,
);

Future<void> _show(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    420,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}
