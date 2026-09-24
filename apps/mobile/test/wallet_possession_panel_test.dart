import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/account/wallet_possession_panel.dart';

import 'support/wallet_possession_fakes.dart';

Future<void> mount(WidgetTester tester, ProofHarness h, {double scale = 1}) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: WalletPossessionPanel(controller: h.controller),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets(
    'opening performs no work; a separate tap signs the reviewed message',
    (tester) async {
      final h = ProofHarness();
      addTearDown(h.close);
      await mount(tester, h);
      expect(h.contextReads, 0);
      expect(h.client.issued, 0);
      expect(find.text('Sign message'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('wallet-proof-prepare')));
      await tester.pumpAndSettle();
      expect(h.signer.messages, isEmpty);
      expect(find.text(proofWallet), findsOneWidget);
      await tester.tap(find.text('Read the full message'));
      await tester.pumpAndSettle();
      expect(find.text(proofChallenge().message), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('wallet-proof-sign')),
      );
      await tester.tap(find.byKey(const ValueKey('wallet-proof-sign')));
      await tester.pumpAndSettle();
      expect(h.signer.messages, hasLength(1));
      expect(find.text('Wallet checked'), findsOneWidget);
      expect(find.text('Sign message'), findsNothing);
    },
  );

  testWidgets('missing wallet is explicit and never creates one', (
    tester,
  ) async {
    final h = ProofHarness();
    addTearDown(h.close);
    h.context = proofContext(missingStatus: 'missing');
    await mount(tester, h);
    await tester.tap(find.byKey(const ValueKey('wallet-proof-prepare')));
    await tester.pumpAndSettle();
    expect(
      find.text('There is no Solana wallet linked to this account yet.'),
      findsOneWidget,
    );
    expect(h.client.issued, 0);
    expect(h.signer.messages, isEmpty);
  });

  testWidgets(
    'narrow screen at 200 percent text keeps review and cancel reachable',
    (tester) async {
      final h = ProofHarness();
      addTearDown(h.close);
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await h.controller.prepare();
      await mount(tester, h, scale: 2);
      await tester.ensureVisible(find.text('Read the full message'));
      await tester.tap(find.text('Read the full message'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('wallet-proof-cancel')),
      );
      await tester.tap(find.byKey(const ValueKey('wallet-proof-cancel')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(h.signer.messages, isEmpty);
      expect(
        find.text('Check stopped. You can start again when you are ready.'),
        findsOneWidget,
      );
    },
  );
}
