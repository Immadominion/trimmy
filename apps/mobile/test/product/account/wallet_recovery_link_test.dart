import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/account/wallet_recovery_link.dart';

void main() {
  const origin = 'https://web-production-e8138.up.railway.app/wallet-recovery';
  const wallet = 'GtuuDXDJwaYCzFkushTrS3Sd68cKdNSqGKHcw8MsKXqF';

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
        origin.replaceFirst('.app/', '.app.evil.example/'),
        origin.replaceFirst('https://', 'https://user:secret@'),
        origin.replaceFirst('.app/', '.app:8443/'),
        '$origin?token=secret',
        '$origin#address=$wallet',
        '$origin/../other',
        'https://web-production-e8138.up.railway.app/',
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
