import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/career/career.dart';
import 'package:trimmy/product/design/product_theme.dart';
import 'package:trimmy/product/settings/settings.dart';

import '../career/reason_sharing_test_support.dart';

void main() {
  testWidgets('shows the server choice only after it loads', (tester) async {
    final gate = Completer<ReasonPrivacy>();
    final repository = FakeReasonSharingRepository()
      ..privacyReads.add(gate.future);
    final controller = _controller();
    unawaited(
      controller.bind(principalKey: 'account:one', repository: repository),
    );
    await tester.pumpWidget(_app(controller));

    expect(find.text('Who can see my comments'), findsOneWidget);
    expect(find.text('Loading your choice.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-reason-privacy-loading')),
      findsOneWidget,
    );
    expect(find.text('Nobody'), findsNothing);

    gate.complete(testPrivacy());
    await tester.pumpAndSettle();

    expect(find.text('Nobody'), findsOneWidget);
    expect(find.text('Only you can see your comments.'), findsOneWidget);
  });

  testWidgets(
    'Everyone asks for consent, then reads as saving until the server confirms',
    (tester) async {
      final gate = Completer<ReasonPrivacyReceipt>();
      final repository = FakeReasonSharingRepository()
        ..privacyReads.add(testPrivacy())
        ..onPut = (_) => gate.future;
      final controller = _controller();
      await controller.bind(
        principalKey: 'account:one',
        repository: repository,
      );
      await tester.pumpWidget(_app(controller));

      await tester.tap(find.byKey(const ValueKey('settings-reason-privacy')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reason-privacy-consent')),
        findsNothing,
      );
      expect(find.text('Save'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('reason-privacy-option-everyone')),
      );
      await tester.pumpAndSettle();
      expect(find.text(reasonPrivacyConsentLine), findsOneWidget);
      expect(repository.writes, isEmpty);

      await tester.tap(find.byKey(const ValueKey('reason-privacy-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(repository.writes.single.visibility, ReasonVisibility.everyone);
      expect(find.text('Saving Everyone.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings-reason-privacy-saving')),
        findsOneWidget,
      );
      expect(find.text('Everyone'), findsNothing);
      expect(find.textContaining('Saved.'), findsNothing);

      gate.complete(testReceipt(repository.writes.single));
      await tester.pumpAndSettle();

      expect(find.text('Everyone'), findsOneWidget);
      expect(
        find.text('Saved. Anyone in Trimmy can see them on each stock page.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Friends can be chosen and stays marked as not available', (
    tester,
  ) async {
    final repository = FakeReasonSharingRepository()
      ..privacyReads.add(testPrivacy())
      ..onPut = (write) => testReceipt(write);
    final controller = _controller();
    await controller.bind(principalKey: 'account:one', repository: repository);
    await tester.pumpWidget(_app(controller));

    await tester.tap(find.byKey(const ValueKey('settings-reason-privacy')));
    await tester.pumpAndSettle();
    expect(find.text(reasonPrivacyFriendsLine), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('reason-privacy-option-friends')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reason-privacy-consent')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('reason-privacy-confirm')));
    await tester.pumpAndSettle();

    expect(repository.writes.single.visibility, ReasonVisibility.friends);
    expect(find.text('Friends'), findsOneWidget);
    expect(find.text('Saved. $reasonPrivacyFriendsLine'), findsOneWidget);
  });

  testWidgets('Friends explains active sharing when the server enables it', (
    tester,
  ) async {
    final repository = FakeReasonSharingRepository()
      ..privacyReads.add(
        testPrivacy(
          revision: 2,
          visibility: ReasonVisibility.friends,
          friendsSharing: FriendsSharingAvailability.available,
        ),
      );
    final controller = _controller();
    await controller.bind(principalKey: 'account:one', repository: repository);
    await tester.pumpWidget(_app(controller));

    expect(find.text(reasonPrivacyFriendsAvailableLine), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-reason-privacy')));
    await tester.pumpAndSettle();
    expect(find.text(reasonPrivacyFriendsAvailableLine), findsNWidgets(2));
    expect(find.text(reasonPrivacyFriendsLine), findsNothing);
  });

  testWidgets('a failed save stays unsaved and retry replays the same write', (
    tester,
  ) async {
    var puts = 0;
    final repository = FakeReasonSharingRepository()
      ..privacyReads.add(testPrivacy())
      ..onPut = (write) {
        puts++;
        if (puts == 1) {
          throw const ReasonSharingException(ReasonSharingFailure.timeout);
        }
        return testReceipt(write);
      };
    final controller = _controller();
    await controller.bind(principalKey: 'account:one', repository: repository);
    await tester.pumpWidget(_app(controller));

    await tester.tap(find.byKey(const ValueKey('settings-reason-privacy')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('reason-privacy-option-everyone')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reason-privacy-confirm')));
    await tester.pumpAndSettle();

    expect(
      find.text('Saving took too long. Everyone is not saved yet.'),
      findsOneWidget,
    );
    expect(find.text('Everyone'), findsNothing);
    final retry = find.byKey(const ValueKey('settings-reason-privacy-retry'));
    expect(retry, findsOneWidget);

    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(repository.writes, hasLength(2));
    expect(repository.writes[0].mutationId, repository.writes[1].mutationId);
    expect(find.text('Everyone'), findsOneWidget);
    expect(find.textContaining('Saved.'), findsOneWidget);
  });

  testWidgets('a change made elsewhere is shown as refreshed', (tester) async {
    final repository = FakeReasonSharingRepository()
      ..privacyReads.add(testPrivacy())
      ..privacyReads.add(
        testPrivacy(revision: 2, visibility: ReasonVisibility.friends),
      )
      ..onPut = (_) => Future<ReasonPrivacyReceipt>.error(
        const ReasonSharingException(ReasonSharingFailure.revisionConflict),
      );
    final controller = _controller();
    await controller.bind(principalKey: 'account:one', repository: repository);
    await tester.pumpWidget(_app(controller));

    await tester.tap(find.byKey(const ValueKey('settings-reason-privacy')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('reason-privacy-option-everyone')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reason-privacy-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Friends'), findsOneWidget);
    expect(
      find.text(
        'Changed on another device. Refreshed. $reasonPrivacyFriendsLine',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-reason-privacy-retry')),
      findsNothing,
    );
  });

  testWidgets('a load failure offers retry and keeps the row unopenable', (
    tester,
  ) async {
    final repository = FakeReasonSharingRepository()
      ..privacyReads.add(
        Future<ReasonPrivacy>.error(
          const ReasonSharingException(ReasonSharingFailure.offline),
        ),
      )
      ..privacyReads.add(testPrivacy());
    final controller = _controller();
    await controller.bind(principalKey: 'account:one', repository: repository);
    await tester.pumpWidget(_app(controller));

    expect(
      find.text('You are offline. Your choice could not load.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('settings-reason-privacy')));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('settings-reason-privacy-retry')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nobody'), findsOneWidget);
  });

  testWidgets('the settings screen shows the row only with a controller', (
    tester,
  ) async {
    await tester.pumpWidget(_settings(null));
    expect(find.byKey(const ValueKey('settings-reason-privacy')), findsNothing);

    final repository = FakeReasonSharingRepository()
      ..privacyReads.add(testPrivacy());
    final controller = _controller();
    await controller.bind(principalKey: 'account:one', repository: repository);
    await tester.pumpWidget(_settings(controller));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-reason-privacy')),
      420,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Who can see my comments'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-holdings-visibility')),
      findsNothing,
    );
  });
}

ReasonPrivacyController _controller() {
  final controller = ReasonPrivacyController(
    mutationId: () => testReasonMutation,
  );
  addTearDown(controller.dispose);
  return controller;
}

Widget _app(ReasonPrivacyController controller) => MaterialApp(
  theme: productTheme(),
  home: Scaffold(body: ReasonPrivacyRow(controller: controller)),
);

Widget _settings(ReasonPrivacyController? controller) => MaterialApp(
  theme: productTheme(),
  home: ProductSettingsScreen(
    reasonPrivacy: controller,
    state: ProductSettingsState(
      account: SettingsAccountState(
        signedIn: false,
        handle: '@mira',
        persona: 'The Wolf',
      ),
      notifications: const {},
      quietHours: const SettingsQuietHours(
        enabled: false,
        startLabel: '10:00 PM',
        endLabel: '7:00 AM',
        available: false,
      ),
      appearance: const SettingsAppearanceState(
        soundEnabled: false,
        hapticsEnabled: false,
        animationsEnabled: true,
        systemReduceMotionEnabled: false,
        languageLabel: 'English',
      ),
      paper: const SettingsPaperState(limit: 10000),
      money: const SettingsMoneyState(
        availability: SettingsFeatureAvailability.comingSoon,
      ),
      wallet: const SettingsWalletState(
        availability: SettingsFeatureAvailability.unavailable,
      ),
    ),
  ),
);
