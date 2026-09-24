enum SocialLookupFailure {
  invalidConfiguration,
  invalidUsername,
  unauthenticated,
  accountMismatch,
  unavailable,
  rateLimited,
  notFound,
  invalidResponse,
  timeout,
  cancelled,
  busy,
  closed,
}

class SocialLookupException implements Exception {
  const SocialLookupException(this.failure);
  final SocialLookupFailure failure;

  @override
  String toString() => 'SocialLookupException(${failure.name})';
}

bool isXUsername(String value) {
  final match = RegExp(r'[A-Za-z0-9_]{1,15}').firstMatch(value);
  return match?.start == 0 && match?.end == value.length;
}

Never invalidSocialResponse() =>
    throw const SocialLookupException(SocialLookupFailure.invalidResponse);

Map<String, dynamic> socialObject(Object? value, Set<String> keys) {
  if (value is! Map<String, dynamic> ||
      value.length != keys.length ||
      !keys.every(value.containsKey)) {
    invalidSocialResponse();
  }
  return value;
}

/// A public profile observed at one time. Its ID is an exact decimal string;
/// neither this result nor the username proves that the caller owns the account.
final class XPublicProfile {
  const XPublicProfile._({
    required this.id,
    required this.username,
    required this.name,
    required this.lookedUpAt,
  });

  final String id;
  final String username;
  final String name;
  final DateTime lookedUpAt;
  bool get ownershipVerified => false;
  bool get invitationCreated => false;

  factory XPublicProfile.fromEnvelope(
    Object? value, {
    required String expectedUsername,
  }) {
    final envelope = socialObject(value, const {
      'schemaVersion',
      'profile',
      'invitationCreated',
    });
    if (envelope['schemaVersion'] is! int ||
        envelope['schemaVersion'] != 1 ||
        envelope['invitationCreated'] != false ||
        !isXUsername(expectedUsername)) {
      invalidSocialResponse();
    }
    final profile = socialObject(envelope['profile'], const {
      'provider',
      'id',
      'username',
      'name',
      'lookedUpAt',
      'ownershipVerified',
    });
    final id = profile['id'];
    final username = profile['username'];
    final name = profile['name'];
    final rawTime = profile['lookedUpAt'];
    if (profile['provider'] != 'x' ||
        profile['ownershipVerified'] != false ||
        id is! String ||
        RegExp(r'^[1-9][0-9]{0,19}$').firstMatch(id)?.group(0) != id ||
        BigInt.parse(id) > BigInt.parse('18446744073709551615') ||
        username is! String ||
        !isXUsername(username) ||
        username.toLowerCase() != expectedUsername.toLowerCase() ||
        name is! String ||
        name.trim().isEmpty ||
        name.runes.length > 100 ||
        name.runes.any((value) => value >= 0xd800 && value <= 0xdfff) ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name) ||
        rawTime is! String ||
        !RegExp(
          r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
        ).hasMatch(rawTime)) {
      invalidSocialResponse();
    }
    final time = DateTime.tryParse(rawTime);
    if (time == null || !time.isUtc || time.toIso8601String() != rawTime) {
      invalidSocialResponse();
    }
    return XPublicProfile._(
      id: id,
      username: username,
      name: name,
      lookedUpAt: time,
    );
  }
}
