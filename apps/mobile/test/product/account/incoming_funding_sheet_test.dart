import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/account/account_controller.dart';
import 'package:trimmy/account/incoming_funding_controller.dart';
import 'package:trimmy/account/incoming_funding_store.dart';
import 'package:trimmy/account/mobile_wallet_service.dart';
import 'package:trimmy/product/account/incoming_funding_sheet.dart';
import 'package:trimmy/product/design/product_theme.dart';
import '../../account/incoming_funding_test.dart' as support;

class _Account extends ChangeNotifier implements AccountController {
  _Account(this.funding);
  final IncomingFundingController funding;
  @override
  IncomingFundingController createIncomingFunding({
    bool allowNew = true,
    MobileWalletService? wallet,
    FundingIntentStore? store,
  }) => funding;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'review and uncertain states fit a narrow phone at large text size',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = support.Harness();
      final bound = _Account(h.controller);
      await tester.pumpWidget(
        MaterialApp(
          theme: productTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(body: IncomingFundingSheet(account: bound)),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.runAsync(() async {
        await h.controller.connect();
        await h.controller.prepare('SOL', '0.005');
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Continue in wallet'), findsOneWidget);
      await tester.ensureVisible(find.text('Continue in wallet'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      h.wallet.failure = const MobileWalletException(
        'MOBILE_WALLET_OUTCOME_UNKNOWN',
      );
      await tester.runAsync(h.controller.confirm);
      await tester.pump();
      expect(find.text('Check your wallet'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() => h.controller.reconcileSignature('wrong'));
      await tester.pump();
      expect(
        find.text(
          'That transaction doesn’t match this transfer. Check the ID in your wallet.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      bound.dispose();
    },
  );
}
