import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'incoming_funding_models.dart';

class FundingIntent {
  const FundingIntent({
    required this.accountId,
    required this.subject,
    required this.recipient,
    required this.requestHash,
    required this.review,
    this.signature,
  });
  final String accountId, subject, recipient, requestHash;
  final FundingReview review;
  final String? signature;
  FundingIntent withSignature(String value) => FundingIntent(
    accountId: accountId,
    subject: subject,
    recipient: recipient,
    requestHash: requestHash,
    review: review,
    signature: value,
  );
  Map<String, Object?> toJson() => {
    'accountId': accountId,
    'subject': subject,
    'recipient': recipient,
    'requestHash': requestHash,
    'review': review.envelope,
    'signature': signature,
  };
  factory FundingIntent.parse(Object? value) {
    if (value is! Map ||
        value['accountId'] is! String ||
        value['subject'] is! String ||
        value['recipient'] is! String ||
        value['requestHash'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['requestHash'] as String) ||
        value['signature'] != null &&
            (value['signature'] is! String ||
                !fundingSignature(value['signature'] as String))) {
      throw const FundingFailure('PENDING_STORAGE_INVALID');
    }
    return FundingIntent(
      accountId: value['accountId'] as String,
      subject: value['subject'] as String,
      recipient: value['recipient'] as String,
      requestHash: value['requestHash'] as String,
      review: FundingReview.parse(value['review']),
      signature: value['signature'] as String?,
    );
  }
}

abstract interface class FundingIntentStore {
  Future<FundingIntent?> read();

  /// Claims empty storage or updates the same transaction; never overwrites another.
  Future<void> save(FundingIntent intent);
  Future<void> clear(String requestHash);
}

/// One journal for external funding, independent of the logged-in account.
/// Signatures and reviews are retained for reconciliation; no bearer is stored.
class SharedFundingIntentStore implements FundingIntentStore {
  static const _key = 'trimmy.externalFunding.pending.v1';
  static Future<void> _tail = Future.value();
  Future<T> _serial<T>(Future<T> Function() run) {
    final future = _tail.then((_) => run());
    _tail = future.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return future;
  }

  Future<FundingIntent?> _read(SharedPreferences prefs) async {
    await prefs.reload();
    final value = prefs.getString(_key);
    if (value == null) return null;
    if (value.length > 8192) {
      throw const FundingFailure('PENDING_STORAGE_INVALID');
    }
    try {
      return FundingIntent.parse(jsonDecode(value));
    } catch (_) {
      throw const FundingFailure('PENDING_STORAGE_INVALID');
    }
  }

  @override
  Future<FundingIntent?> read() =>
      _serial(() async => _read(await SharedPreferences.getInstance()));
  @override
  Future<void> save(FundingIntent intent) => _serial(() async {
    final prefs = await SharedPreferences.getInstance(),
        existing = await _read(prefs);
    if (existing != null &&
        (existing.requestHash != intent.requestHash ||
            existing.accountId != intent.accountId ||
            existing.subject != intent.subject ||
            existing.recipient != intent.recipient)) {
      throw const FundingFailure('PENDING_TRANSFER');
    }
    if (!await prefs.setString(_key, jsonEncode(intent.toJson()))) {
      throw const FundingFailure('STORAGE_UNAVAILABLE');
    }
  });
  @override
  Future<void> clear(String requestHash) => _serial(() async {
    final prefs = await SharedPreferences.getInstance(),
        existing = await _read(prefs);
    if (existing?.requestHash == requestHash && !await prefs.remove(_key)) {
      throw const FundingFailure('STORAGE_UNAVAILABLE');
    }
  });
}
