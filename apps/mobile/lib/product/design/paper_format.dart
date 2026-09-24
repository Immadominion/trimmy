/// Formats an exact non-negative paper amount for a compact money surface.
///
/// Accounting keeps up to six decimal places. The UI rounds that exact string
/// to two places, groups the whole part, then removes unnecessary zeroes. No
/// floating-point conversion is involved.
String formatPaperForDisplay(String raw) {
  final normalized = raw.replaceAll(',', '');
  final match = RegExp(
    r'^(0|[1-9][0-9]*)(?:\.([0-9]{1,6}))?$',
  ).firstMatch(normalized);
  if (match == null) return raw;

  final fraction = (match.group(2) ?? '').padRight(6, '0');
  final micros =
      BigInt.parse(match.group(1)!) * BigInt.from(1000000) +
      BigInt.parse(fraction.isEmpty ? '0' : fraction);
  final cents = (micros + BigInt.from(5000)) ~/ BigInt.from(10000);
  final whole = cents ~/ BigInt.from(100);
  final remainder = (cents % BigInt.from(100)).toInt();
  final grouped = whole.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  if (remainder == 0) return grouped;
  final decimal = remainder
      .toString()
      .padLeft(2, '0')
      .replaceFirst(RegExp(r'0$'), '');
  return '$grouped.$decimal';
}
