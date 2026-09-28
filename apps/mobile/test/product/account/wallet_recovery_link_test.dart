import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/account/wallet_recovery_link.dart';

void main() {
  const origin = 'https://app.trimmy.xyz/wallet-recovery';
  const wallet = 'FVen3X669xLzsi6N2V91DoiyzHzg1uAgqiT8jZ9nS96Z';

  test(
    'recovery link keeps only the expected public address in its fragment',
    () {
      final uri = walletRecoveryLink(origin, wallet)!;
      expect(uri.scheme, 'https');
      expect(uri.userInfo, isEmpty);
      expect(uri.hasQuery, isFalse);
      expect(uri.fragment, 'address=$wallet');
      expect(uri.removeFragment().toString(), origin);
    },
  );

  test(
    'unconfigured, redirected or credential-bearing destinations fail closed',
    () {
      for (final target in [
        '',
        origin.replaceFirst('https:', 'http:'),
        origin.replaceFirst('.xyz/', '.xyz.evil.example/'),
        origin.replaceFirst('https://', 'https://user:secret@'),
        origin.replaceFirst('.xyz/', '.xyz:8443/'),
        '$origin?token=secret',
        '$origin#address=$wallet',
        '$origin/../other',
        'https://app.trimmy.xyz/',
      ]) {
        expect(walletRecoveryLink(target, wallet), isNull, reason: target);
      }
    },
  );

  test('malformed public addresses cannot become browser parameters', () {
    for (final address in [
      '',
      'not-a-wallet',
      '11111111111111111111111111111111',
      '$wallet&token=secret',
      '$wallet\n',
      '${wallet}1',
    ]) {
      expect(walletRecoveryLink(origin, address), isNull);
    }
  });
}
