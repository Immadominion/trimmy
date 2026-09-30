import '../../core/paper_decimal.dart';

/// The paper ledger uses six fixed decimal places. Presets round down so they
/// can never offer even one microshare more than the position owns.
abstract final class OrderAmountMath {
  static final scale = BigInt.from(1000000);

  static BigInt micros(String value) =>
      RegExp(r'^\d+(?:\.\d{0,6})?$').hasMatch(value)
      ? paperMicros(value)
      : BigInt.zero;

  static String decimal(BigInt value) => paperDecimal(value);

  static String portion(String shares, int percent) =>
      decimal(micros(shares) * BigInt.from(percent) ~/ BigInt.from(100));

  static String cents(String value) =>
      decimal(micros(value) ~/ BigInt.from(10000) * BigInt.from(10000));

  static String sharesForCash(
    String cash,
    String price, {
    bool selling = false,
  }) {
    final p = micros(price);
    if (p <= BigInt.zero) return '0';
    final numerator = micros(cash) * scale;
    return decimal((numerator + (selling ? p - BigInt.one : BigInt.zero)) ~/ p);
  }

  static String cashForShares(String shares, String price) =>
      decimal(micros(shares) * micros(price) ~/ scale);
}
