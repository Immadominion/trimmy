/// Validation shared only by the read-only stock research protocol.
class StockResearchException implements Exception {
  const StockResearchException(this.code);
  final String code;
  @override
  String toString() => 'StockResearchException($code)';
}

Never researchInvalid() =>
    throw const StockResearchException('STOCK_RESPONSE_INVALID');

Map<String, Object?> researchObject(Object? value, Set<String> keys) {
  if (value is! Map ||
      value.keys.any((key) => key is! String) ||
      value.length != keys.length ||
      !keys.every(value.containsKey)) {
    researchInvalid();
  }
  return Map<String, Object?>.from(value);
}

String researchText(Object? value, [int max = 160]) {
  if (value is! String ||
      value.isEmpty ||
      value.length > max ||
      value.trim() != value ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    researchInvalid();
  }
  return value;
}

String? researchNullableText(Object? value, [int max = 160]) =>
    value == null ? null : researchText(value, max);

bool researchMatches(String value, String expression) {
  final match = RegExp(expression).firstMatch(value);
  return match?.start == 0 && match?.end == value.length;
}

String researchAssetId(Object? value) {
  final text = researchText(value, 100);
  if (!researchMatches(text, r'[a-z0-9]+(?:-[a-z0-9]+)*')) {
    researchInvalid();
  }
  return text;
}

String researchVariantId(Object? value) {
  final text = researchText(value);
  if (!researchMatches(text, r'[A-Za-z0-9][A-Za-z0-9._:-]*')) {
    researchInvalid();
  }
  return text;
}

String researchMint(Object? value) {
  final text = researchText(value, 44);
  if (text.length < 32) researchInvalid();
  const alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  var number = BigInt.zero;
  var zeroes = 0;
  for (var i = 0; i < text.length; i++) {
    final digit = alphabet.indexOf(text[i]);
    if (digit < 0) researchInvalid();
    number = number * BigInt.from(58) + BigInt.from(digit);
    if (i == zeroes && text[i] == '1') zeroes++;
  }
  if ((number.bitLength + 7) ~/ 8 + zeroes != 32) researchInvalid();
  return text;
}

int researchInteger(Object? value, int min, int max) {
  if (value is! int || value < min || value > max) researchInvalid();
  return value;
}

num? researchMetric(Object? value) {
  if (value == null) return null;
  if (value is! num ||
      !value.isFinite ||
      value < 0 ||
      value > 9007199254740991) {
    researchInvalid();
  }
  return value;
}

String researchTimestamp(Object? value) {
  final text = researchText(value, 32);
  if (!researchMatches(text, r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z')) {
    researchInvalid();
  }
  final date = DateTime.tryParse(text);
  if (date == null || !date.isUtc || date.toIso8601String() != text) {
    researchInvalid();
  }
  return text;
}

Uri researchSource(Object? value) {
  final text = researchText(value, 2048);
  final uri = Uri.tryParse(text);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment) {
    researchInvalid();
  }
  return uri;
}

List<T> researchList<T>(Object? value, int max, T Function(Object?) parse) {
  if (value is! List || value.length > max) researchInvalid();
  return List<T>.unmodifiable(value.map(parse));
}

void researchUnique<T>(Iterable<T> values) {
  final list = values.toList();
  if (list.toSet().length != list.length) researchInvalid();
}

void researchSchema(Object? value) {
  if (value is! int) researchInvalid();
  if (value != 1) {
    throw const StockResearchException('STOCK_UNSUPPORTED_SCHEMA');
  }
}

/// Integer raw token units. This is never a scaled share quantity.
String researchRawAmount(Object? value) {
  final text = researchText(value, 20);
  if (!researchMatches(text, r'[1-9][0-9]*') ||
      BigInt.parse(text) > BigInt.parse('18446744073709551615')) {
    researchInvalid();
  }
  return text;
}

String formatRawTokenUnits(String raw, int decimals) {
  researchRawAmount(raw);
  researchInteger(decimals, 0, 255);
  if (decimals == 0) return raw;
  final padded = raw.padLeft(decimals + 1, '0');
  return '${padded.substring(0, padded.length - decimals)}.'
      '${padded.substring(padded.length - decimals)}';
}
