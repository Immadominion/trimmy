/// Exact presentation helpers for account reads. Raw integer strings are
/// never converted through floating point, and nothing here prices a balance.
library;

/// Formats a raw integer amount with [decimals] fractional digits, grouping
/// the whole part with commas and trimming trailing zeros. Invalid input
/// returns null so a screen can say the amount is unavailable instead of
/// showing a wrong number.
String? formatRawUnits(String raw, int decimals) {
  if (decimals < 0 || decimals > 30 || raw.length > 40) return null;
  if (RegExp(r'^(0|[1-9][0-9]*)$').stringMatch(raw) != raw) return null;
  final padded = raw.padLeft(decimals + 1, '0');
  final whole = padded.substring(0, padded.length - decimals);
  var fraction = padded.substring(padded.length - decimals);
  fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
  final grouped = StringBuffer();
  for (var index = 0; index < whole.length; index++) {
    final remaining = whole.length - index;
    grouped.write(whole[index]);
    if (remaining > 1 && remaining % 3 == 1) grouped.write(',');
  }
  return fraction.isEmpty ? grouped.toString() : '$grouped.$fraction';
}

/// Shows the start and end of a long address so a person can compare it with
/// another screen. The full value belongs in the accessibility label.
String shortenAddress(String address) {
  if (address.length <= 12) return address;
  return '${address.substring(0, 4)}…${address.substring(address.length - 4)}';
}

/// Local wall-clock time as HH:MM for "checked at" notes.
String formatClockTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}
