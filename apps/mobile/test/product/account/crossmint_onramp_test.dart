import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/account/onramp_wallet_signer.dart';
import 'package:trimmy/product/account/crossmint_onramp.dart';

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
}
