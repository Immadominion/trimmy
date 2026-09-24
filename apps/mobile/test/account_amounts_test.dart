import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/account/account_amounts.dart';

void main() {
  test('raw units format exactly with grouping and trimmed fractions', () {
    expect(formatRawUnits('0', 9), '0');
    expect(formatRawUnits('1', 9), '0.000000001');
    expect(formatRawUnits('1000000000', 9), '1');
    expect(formatRawUnits('1500000000', 9), '1.5');
    expect(formatRawUnits('9007199254740991', 9), '9,007,199.254740991');
    expect(
      formatRawUnits('18446744073709551615', 6),
      '18,446,744,073,709.551615',
    );
    expect(formatRawUnits('123456', 0), '123,456');
    expect(formatRawUnits('10', 6), '0.00001');
  });

  test('malformed or unsafe raw units are refused rather than guessed', () {
    for (final bad in ['', '-1', '01', '1.5', '1e9', ' 1', 'abc', '1' * 41]) {
      expect(formatRawUnits(bad, 9), isNull, reason: bad);
    }
    expect(formatRawUnits('1', -1), isNull);
    expect(formatRawUnits('1', 31), isNull);
  });

  test('addresses shorten from both ends and short values stay whole', () {
    expect(
      shortenAddress('FVen3X669xLzsi6N2V91DoiyzHzg1uAgqiT8jZ9nS96Z'),
      'FVen…S96Z',
    );
    expect(shortenAddress('short'), 'short');
  });

  test('clock time uses two-digit local hours and minutes', () {
    final value = DateTime(2026, 9, 15, 7, 5);
    expect(formatClockTime(value), '07:05');
  });
}
