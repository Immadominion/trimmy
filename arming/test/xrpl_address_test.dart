import 'package:test/test.dart';
import 'package:trimmy_arming/xrpl_address.dart';

void main() {
  group('validateXrplAddress', () {
    test('accepts addresses this project has really used', () {
      for (final a in [
        'rDE4JUm2jaue31VwidRXWuWzf5dQkUxcsB', // our funded testnet account
        'rDhpmiPq4BVBDWMVdSrmkgt8thKyRzGV1p', // the FAssets Core Vault
      ]) {
        expect(validateXrplAddress(a), a);
      }
    });

    test('rejects the one-character typo the controller silently accepts', () {
      // getPersonalAccount() maps this to 0x6085dbe8..., a different account, with no error.
      expect(
        () => validateXrplAddress('rDE4JUm2jaue31VwidRXWuWzf5dQkUxcsA'),
        throwsA(isA<InvalidXrplAddress>().having(
          (e) => e.message, 'message', contains('checksum'))),
      );
    });

    test('rejects things that are not addresses', () {
      for (final bad in ['', '   ', 'not-an-address', '0x38d58d1BEA8FF21fd8397494f17F64A99bcF8E83']) {
        expect(() => validateXrplAddress(bad), throwsA(isA<InvalidXrplAddress>()));
      }
    });

    test('rejects characters outside the XRPL alphabet', () {
      // 0, O, I and l are excluded because they are confusable.
      expect(
        () => validateXrplAddress('rDE4JUm2jaue31VwidRXWuWzf5dQkUx0sB'),
        throwsA(isA<InvalidXrplAddress>().having(
          (e) => e.message, 'message', contains('valid character'))),
      );
    });

    test('every single-character substitution in a real address is caught', () {
      const base = 'rDE4JUm2jaue31VwidRXWuWzf5dQkUxcsB';
      const alphabet = 'rpshnaf39wBUDNEGHJKLM4PQRST7VWXYZ2bcdeCg65jkm8oFqi1tuvAxyz';
      var checked = 0;
      final slipped = <String>[];
      for (var i = 1; i < base.length; i++) {
        for (final c in alphabet.split('')) {
          if (c == base[i]) continue;
          final candidate = base.substring(0, i) + c + base.substring(i + 1);
          checked++;
          try {
            validateXrplAddress(candidate);
            slipped.add(candidate);
          } on InvalidXrplAddress {
            // expected
          }
        }
      }
      expect(slipped, isEmpty, reason: '${slipped.length} of $checked typos were accepted');
      expect(checked, greaterThan(1800));
    });
  });
}
