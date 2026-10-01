import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trimmy/account/account_controller.dart';
import 'package:trimmy/account/onramp_wallet_signer.dart';
import 'package:trimmy/practice_sync/http_transport.dart';
import 'package:trimmy/product/account/crossmint_onramp.dart';
import '../../support/l10n_harness.dart';

class _Account extends ChangeNotifier implements AccountController {
  @override
  String? accountId = 'account-1';
  @override
  int navigationEpoch = 0;
  @override
  AccountPhase get phase => AccountPhase.active;
  @override
  Future<PracticeAccessToken> freshAccessToken() async =>
      PracticeAccessToken(accountId: accountId!, token: 'test-token');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('checkout pins the official environment and contains no server key', () {
    final order = {
      'environment': 'staging',
      'clientKey': 'ck_staging_public',
      'clientSecret': 'order_only_secret',
      'orderId': 'order1',
    };
    final uri = crossmintCheckoutUri(order);
    expect(uri.scheme, 'https');
    expect(uri.host, 'staging.crossmint.com');
    expect(uri.path, '/sdk/2024-03-05/embedded-checkout');
    final payment = jsonDecode(uri.queryParameters['payment']!) as Map;
    expect(payment['crypto']['enabled'], false);
    expect(payment['fiat']['allowedMethods']['card'], true);
    expect(
      () => crossmintCheckoutUri({...order, 'environment': 'production'}),
      throwsA(isA<OnrampFailure>()),
    );
    expect(
      () => crossmintCheckoutUri({...order, 'clientKey': 'sk_staging_secret'}),
      throwsA(isA<OnrampFailure>()),
    );
  });
  test('wallet signer refuses an unrelated message or a different wallet', () {
    const wallet = 'FVen3X669xLzsi6N2V91DoiyzHzg1uAgqiT8jZ9nS96Z';
    final text =
        'crossmint.com wants you to sign in with your blockchain account:\n$wallet\n\nOwnership proof';
    expect(
      OnrampWalletChallenge.parse(wallet: wallet, message: text).wallet,
      wallet,
    );
    expect(
      () => OnrampWalletChallenge.parse(wallet: wallet, message: 'Pay someone'),
      throwsFormatException,
    );
    expect(
      () => OnrampWalletChallenge.parse(
        wallet: 'GVen3X669xLzsi6N2V91DoiyzHzg1uAgqiT8jZ9nS96Z',
        message: text,
      ),
      throwsFormatException,
    );
    expect(() => checkedOnrampSignature('invalid'), throwsFormatException);
  });

  testWidgets('an error about the last try goes once the entry changes', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final requests = <String>[];
    await http.runWithClient(
      () => tester.pumpWidget(
        localizedTestApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CrossmintOnrampForm(
                account: _Account(),
                origin: Uri.parse('https://trimmy.example'),
                onTransfer: () {},
              ),
            ),
          ),
        ),
      ),
      () => MockClient((request) async {
        requests.add(request.url.path);
        return http.Response(
          jsonEncode({'enabled': true, 'environment': 'staging'}),
          200,
        );
      }),
    );
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    expect(requests, ['/v1/funding/capabilities']);
    final email = find.byKey(const ValueKey('onramp-email'));
    const emailError = 'Enter an email for your receipt.';

    await tester.enterText(email, 'not-an-email');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text(emailError), findsOneWidget);
    await tester.enterText(email, 'not-an-email.');
    await tester.pump();
    expect(find.text(emailError), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('onramp-amount')), '2');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.textContaining('Enter an amount from'), findsOneWidget);
    await tester.tap(find.text(r'$100'));
    await tester.pump();
    expect(find.textContaining('Enter an amount from'), findsNothing);
    // Nothing went to the server past the first look.
    expect(requests, hasLength(1));
  });
}
