import '../../core/paper_decimal.dart';

/// Formats an exact non-negative paper amount for a compact money surface.
///
/// Accounting keeps up to six decimal places. The UI rounds that exact string
/// to two places, groups the whole part, then removes unnecessary zeroes. No
/// floating-point conversion is involved. The result is written the English
/// way ("1,234.5"); screens show it through `AppFormats.number`.
String formatPaperForDisplay(String raw) {
  final micros = tryPaperMicros(raw, grouped: true);
  if (micros == null) return raw;
  final cents = (micros + BigInt.from(5000)) ~/ BigInt.from(10000);
  return paperDecimal(cents * BigInt.from(10000), grouped: true);
}
