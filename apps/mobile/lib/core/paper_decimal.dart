/// Exact conversions between paper decimal strings and micros.
///
/// The paper ledger keeps six fixed decimal places. Amounts travel as plain
/// decimal strings ("1234.5", "-0.000001") and are added, compared and
/// rounded as BigInt micros, so no floating point touches an amount. These
/// are the only copies of that conversion; screens format the results for
/// people with `AppFormats`.
library;

final _scale = BigInt.from(1000000);
final _plainPaper = RegExp(r'^(?:0|[1-9][0-9]*)(?:\.[0-9]{1,6})?$');

/// Micros for an already validated decimal of at most six places, such as
/// "12.5" or "-0.25". A trailing point reads as whole ("12." is 12).
/// Throws [FormatException] for anything that is not a decimal, like
/// [BigInt.parse] does; validate untrusted text first or use
/// [tryPaperMicros].
BigInt paperMicros(String value) {
  final negative = value.startsWith('-');
  final parts = (negative ? value.substring(1) : value).split('.');
  final micros =
      BigInt.parse(parts[0]) * _scale +
      BigInt.parse(
        (parts.length == 1 ? '' : parts[1]).padRight(6, '0').padLeft(1, '0'),
      );
  return negative ? -micros : micros;
}

/// Micros for a non-negative paper decimal with no leading zeros and at most
/// six places ("0", "12", "12.345678"). Null for anything else. With
/// [grouped], English thousands commas are ignored first ("1,234.5").
BigInt? tryPaperMicros(String value, {bool grouped = false}) {
  final text = grouped ? value.replaceAll(',', '') : value;
  if (!_plainPaper.hasMatch(text)) return null;
  return paperMicros(text);
}

/// The plain decimal for [micros]: no trailing zeros, no point for whole
/// amounts, a leading "-" when negative ("1234.5", "-0.25", "12"). With
/// [grouped], the whole part gets English thousands commas ("1,234.5").
String paperDecimal(BigInt micros, {bool grouped = false}) {
  final negative = micros.isNegative;
  final absolute = micros.abs();
  final whole = (absolute ~/ _scale).toString();
  final fraction = (absolute % _scale)
      .toString()
      .padLeft(6, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return '${negative ? '-' : ''}${grouped ? groupThousands(whole) : whole}'
      '${fraction.isEmpty ? '' : '.$fraction'}';
}

/// English thousands commas for a whole number: "1234567" becomes
/// "1,234,567" and "-1234" becomes "-1,234". Anything else is returned
/// unchanged.
/// Screens then hand the result to `AppFormats.number` for the reader's
/// separators.
String groupThousands(String digits) {
  if (!RegExp(r'^-?[0-9]+$').hasMatch(digits)) return digits;
  return digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}
