/// Failures contain only stable application categories, never provider text,
/// signatures, tokens or the signed message.
enum WalletPossessionFailure {
  invalidConfiguration,
  invalidChallenge,
  invalidSignature,
  invalidResponse,
  accountMismatch,
  walletMismatch,
  unauthenticated,
  walletMissing,
  walletAmbiguous,
  challengeExpired,
  challengeNotFound,
  signatureRejected,
  notConfigured,
  rateLimited,
  unavailable,
  timeout,
  cancelled,
  busy,
  closed,
}

class WalletPossessionException implements Exception {
  const WalletPossessionException(this.failure);
  final WalletPossessionFailure failure;

  @override
  String toString() => 'WalletPossessionException(${failure.name})';
}

Never _fail(WalletPossessionFailure failure) =>
    throw WalletPossessionException(failure);

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
final _instant = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$');
const _base58 = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

bool _matches(RegExp expression, String value) {
  final match = expression.firstMatch(value);
  return match?.start == 0 && match?.end == value.length;
}

/// Bounded base58 length validation. Cryptographic proof is checked by the API.
bool _base58Bytes(String value, int length) {
  if (value.length < length || value.length > length * 2) return false;
  var number = BigInt.zero;
  var zeroes = 0;
  for (var index = 0; index < value.length; index++) {
    final digit = _base58.indexOf(value[index]);
    if (digit < 0) return false;
    if (index == zeroes && digit == 0) zeroes++;
    number = number * BigInt.from(58) + BigInt.from(digit);
  }
  return number != BigInt.zero &&
      zeroes + (number.bitLength + 7) ~/ 8 == length;
}

bool isWalletPossessionAddress(String value) =>
    value.length >= 32 && value.length <= 44 && _base58Bytes(value, 32);

bool isWalletPossessionSignature(String value) =>
    value.length >= 64 && value.length <= 128 && _base58Bytes(value, 64);

Map<String, Object?> _object(
  Object? value,
  Set<String> keys,
  WalletPossessionFailure failure,
) {
  if (value is! Map<String, Object?> ||
      value.length != keys.length ||
      !keys.every(value.containsKey)) {
    _fail(failure);
  }
  return value;
}

String _id(Object? value, WalletPossessionFailure failure) {
  if (value is! String || !_matches(_uuid, value)) _fail(failure);
  return value;
}

DateTime _time(Object? value, WalletPossessionFailure failure) {
  if (value is! String || !_matches(_instant, value)) _fail(failure);
  final parsed = DateTime.tryParse(value);
  if (parsed == null || parsed.year < 1 || parsed.toIso8601String() != value) {
    _fail(failure);
  }
  return parsed;
}

/// Only this fixed, domain-separated statement can reach the native signer.
/// A server-provided message is reconstructed byte-for-byte from validated
/// fields, including the account and nonce inside the message itself.
final class WalletPossessionChallenge {
  WalletPossessionChallenge._({
    required this.challengeId,
    required this.accountId,
    required this.walletAddress,
    required this.network,
    required this.message,
    required this.nonce,
    required this.issuedAt,
    required this.expiresAt,
  });

  factory WalletPossessionChallenge.fromEnvelope(
    Object? value, {
    required String expectedAccountId,
    required String expectedWalletAddress,
  }) {
    const invalid = WalletPossessionFailure.invalidChallenge;
    _id(expectedAccountId, invalid);
    if (!isWalletPossessionAddress(expectedWalletAddress)) _fail(invalid);
    final envelope = _object(value, {'schemaVersion', 'challenge'}, invalid);
    if (envelope['schemaVersion'] != 1) _fail(invalid);
    final data = _object(envelope['challenge'], {
      'challengeId',
      'walletAddress',
      'network',
      'message',
      'issuedAt',
      'expiresAt',
    }, invalid);
    final challengeId = _id(data['challengeId'], invalid);
    final wallet = data['walletAddress'];
    if (wallet is! String || !isWalletPossessionAddress(wallet)) _fail(invalid);
    if (wallet != expectedWalletAddress) {
      _fail(WalletPossessionFailure.walletMismatch);
    }
    if (data['network'] != 'mainnet-beta') _fail(invalid);
    final issuedAt = _time(data['issuedAt'], invalid);
    final expiresAt = _time(data['expiresAt'], invalid);
    final lifetime = expiresAt.difference(issuedAt);
    if (lifetime < const Duration(seconds: 30) ||
        lifetime > const Duration(minutes: 15)) {
      _fail(invalid);
    }
    final message = data['message'];
    if (message is! String || message.length > 1024) _fail(invalid);
    final lines = message.split('\n');
    if (lines.length != 10 ||
        !lines[4].startsWith('account: ') ||
        !lines[7].startsWith('nonce: ')) {
      _fail(invalid);
    }
    final accountId = _id(lines[4].substring(9), invalid);
    if (accountId != expectedAccountId) {
      _fail(WalletPossessionFailure.accountMismatch);
    }
    final nonce = lines[7].substring(7);
    if (!_matches(RegExp(r'^[0-9a-f]{64}$'), nonce)) _fail(invalid);
    final expected = [
      'Trimmy wallet possession',
      'This signature proves you control this wallet for your Trimmy account.',
      'It authorizes no transfer, swap or payment.',
      'challenge: $challengeId',
      'account: $accountId',
      'wallet: $wallet',
      'network: mainnet-beta',
      'nonce: $nonce',
      'issued: ${data['issuedAt']}',
      'expires: ${data['expiresAt']}',
    ].join('\n');
    if (message != expected) _fail(invalid);
    return WalletPossessionChallenge._(
      challengeId: challengeId,
      accountId: accountId,
      walletAddress: wallet,
      network: 'mainnet-beta',
      message: message,
      nonce: nonce,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
    );
  }

  final String challengeId, accountId, walletAddress, network, message, nonce;
  final DateTime issuedAt, expiresAt;

  bool isExpired(DateTime now) => !now.toUtc().isBefore(expiresAt);
}

/// Evidence of the server's possession check. This is not trade permission.
/// The response has no challenge ID; that association comes from the client's
/// exact request, while wallet/network/times are checked against its challenge.
final class WalletPossessionReceipt {
  WalletPossessionReceipt._({
    required this.challengeId,
    required this.accountId,
    required this.walletAddress,
    required this.network,
    required this.verifiedAt,
    required this.bindingId,
    required this.bindingVerifiedAt,
  });

  factory WalletPossessionReceipt.fromEnvelope(
    Object? value, {
    required WalletPossessionChallenge challenge,
  }) {
    const invalid = WalletPossessionFailure.invalidResponse;
    final data = _object(value, {
      'schemaVersion',
      'kind',
      'walletAddress',
      'network',
      'possessionSignatureVerified',
      'verifiedAt',
      'binding',
    }, invalid);
    if (data['schemaVersion'] != 1 ||
        data['kind'] != 'wallet_possession' ||
        data['possessionSignatureVerified'] != true ||
        data['network'] != challenge.network ||
        data['walletAddress'] != challenge.walletAddress) {
      _fail(invalid);
    }
    final verifiedAt = _time(data['verifiedAt'], invalid);
    if (verifiedAt.isBefore(challenge.issuedAt) ||
        !verifiedAt.isBefore(challenge.expiresAt)) {
      _fail(invalid);
    }
    final binding = _object(data['binding'], {'id', 'verifiedAt'}, invalid);
    final bindingId = _id(binding['id'], invalid);
    final bindingVerifiedAt = _time(binding['verifiedAt'], invalid);
    // A previously recorded binding can be reused, so it can predate this proof.
    if (bindingVerifiedAt.isAfter(verifiedAt)) _fail(invalid);
    return WalletPossessionReceipt._(
      challengeId: challenge.challengeId,
      accountId: challenge.accountId,
      walletAddress: challenge.walletAddress,
      network: challenge.network,
      verifiedAt: verifiedAt,
      bindingId: bindingId,
      bindingVerifiedAt: bindingVerifiedAt,
    );
  }

  final String challengeId, accountId, walletAddress, network, bindingId;
  final DateTime verifiedAt, bindingVerifiedAt;
  bool get possessionSignatureVerified => true;
}
