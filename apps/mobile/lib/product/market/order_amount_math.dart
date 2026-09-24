/// The paper ledger uses six fixed decimal places. Presets round down so they
/// can never offer even one microshare more than the position owns.
abstract final class OrderAmountMath {
  static final scale = BigInt.from(1000000);

  static BigInt micros(String value) {
    if (!RegExp(r'^\d+(?:\.\d{0,6})?$').hasMatch(value)) return BigInt.zero;
    final parts = value.split('.');
    return BigInt.parse(parts[0]) * scale +
        BigInt.parse((parts.length == 1 ? '' : parts[1]).padRight(6, '0'));
  }

  static String decimal(BigInt value) {
    final fraction = (value % scale)
        .toString()
        .padLeft(6, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    return '${value ~/ scale}${fraction.isEmpty ? '' : '.$fraction'}';
  }

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
