import 'package:solana/base58.dart';

import 'send_transaction_policy.dart';

const fundingUsdcMint = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
final _u64 = BigInt.parse('18446744073709551615');

class FundingFailure implements Exception {
  const FundingFailure(this.code);
  final String code;
}

bool fundingAddress(String value) {
  try {
    return value.length >= 32 &&
        value.length <= 44 &&
        base58decode(value).length == 32;
  } catch (_) {
    return false;
  }
}

bool fundingSignature(String value) {
  try {
    return value.length >= 64 &&
        value.length <= 88 &&
        base58decode(value).length == 64;
  } catch (_) {
    return false;
  }
}

BigInt? fundingRaw(String value, {bool positive = false}) {
  if (!RegExp(r'^(0|[1-9][0-9]{0,19})$').hasMatch(value)) return null;
  final n = BigInt.parse(value);
  return n > _u64 || positive && n == BigInt.zero ? null : n;
}

/// Exact decimal conversion; never rounds or goes through a double.
String? fundingAmountRaw(String text, String asset) {
  if (!{'SOL', 'USDC'}.contains(asset)) return null;
  final decimals = asset == 'SOL' ? 9 : 6;
  if (!RegExp(r'^(0|[1-9][0-9]*)(\.[0-9]+)?$').hasMatch(text) ||
      text.length > 32) {
    return null;
  }
  final parts = text.split('.');
  final fraction = parts.length == 2 ? parts[1] : '';
  if (fraction.length > decimals) return null;
  final raw =
      BigInt.parse(parts[0]) * BigInt.from(10).pow(decimals) +
      BigInt.parse(fraction.padRight(decimals, '0'));
  return raw > BigInt.zero && raw <= _u64 ? raw.toString() : null;
}

class FundingReview {
  FundingReview._(
    this.envelope,
    this.from,
    this.recipient,
    this.asset,
    this.amountRaw,
    this.receivedRaw,
    this.feeRaw,
    this.rentRaw,
    this.createsAccount,
    this.expiresAt,
    this.transaction,
    this.token,
  );
  final Map<String, Object?> envelope;
  final String from, recipient, asset, amountRaw, receivedRaw, feeRaw, rentRaw;
  final bool createsAccount;
  final DateTime expiresAt;
  final String transaction, token;
  int get decimals => asset == 'SOL' ? 9 : 6;

  factory FundingReview.parse(Object? value) {
    Never invalid() => throw const FundingFailure('INVALID_REVIEW');
    if (value is! Map<String, Object?>) invalid();
    final review = value['review'];
    if (review is! Map<String, Object?>) invalid();
    final asset = review['asset'];
    if (asset is! Map<String, Object?>) invalid();
    final id = asset['kind'] == 'sol' && asset['mint'] == null
        ? 'SOL'
        : asset['kind'] == 'token' && asset['mint'] == fundingUsdcMint
        ? 'USDC'
        : null;
    final from = review['from'], to = review['destination'];
    final amount = review['amountRaw'], received = review['receivedRaw'];
    final fee = review['networkFeeLamports'],
        rent = review['accountRentLamports'];
    final creates = review['createsAccount'];
    final expiry = review['expiresAt'];
    final wire = value['unsignedTransaction'], token = value['reviewToken'];
    if (id == null ||
        asset['symbol'] != id ||
        asset['decimals'] != (id == 'SOL' ? 9 : 6) ||
        asset['uiMultiplier'] != '1' ||
        from is! String ||
        !fundingAddress(from) ||
        to is! String ||
        !fundingAddress(to) ||
        from == to ||
        amount is! String ||
        fundingRaw(amount, positive: true) == null ||
        received != amount ||
        fee is! String ||
        fundingRaw(fee) == null ||
        rent is! String ||
        fundingRaw(rent) == null ||
        creates is! bool ||
        expiry is! String ||
        DateTime.tryParse(expiry) == null ||
        wire is! String ||
        wire.isEmpty ||
        wire.length > 1644 ||
        token is! String ||
        token.isEmpty ||
        token.length > 1200) {
      invalid();
    }
    return FundingReview._(
      value,
      from,
      to,
      id,
      amount,
      received as String,
      fee,
      rent,
      creates,
      DateTime.parse(expiry).toUtc(),
      wire,
      token,
    );
  }

  Future<void> validate({
    required String expectedFrom,
    required String expectedRecipient,
    required String expectedAsset,
    required String expectedAmount,
    required DateTime now,
    bool allowExpired = false,
  }) async {
    if (from != expectedFrom ||
        recipient != expectedRecipient ||
        asset != expectedAsset ||
        amountRaw != expectedAmount) {
      throw const FundingFailure('REVIEW_MISMATCH');
    }
    if (!allowExpired &&
        (!now.toUtc().isBefore(expiresAt) ||
            expiresAt.isAfter(now.toUtc().add(const Duration(minutes: 3))))) {
      throw const FundingFailure('REVIEW_EXPIRED');
    }
    await checkSendTransaction(
      transaction: transaction,
      from: expectedFrom,
      destination: expectedRecipient,
      assetId: expectedAsset,
      decimals: decimals,
      amountRaw: expectedAmount,
      receivedRaw: receivedRaw,
      createsAccount: createsAccount,
      networkFeeLamports: feeRaw,
      accountRentLamports: rentRaw,
    );
  }
}

enum FundingStatus { pending, confirmed, failed }

class FundingReceipt {
  const FundingReceipt(this.status, this.slot);
  final FundingStatus status;
  final int? slot;
  factory FundingReceipt.parse(Object? value) {
    if (value is! Map) throw const FundingFailure('INVALID_STATUS');
    final status = switch (value['status']) {
      'pending' => FundingStatus.pending,
      'confirmed' => FundingStatus.confirmed,
      'failed' => FundingStatus.failed,
      _ => throw const FundingFailure('INVALID_STATUS'),
    };
    final slot = value['slot'];
    if (slot != null && (slot is! int || slot < 0) ||
        status != FundingStatus.pending && slot == null) {
      throw const FundingFailure('INVALID_STATUS');
    }
    return FundingReceipt(status, slot as int?);
  }
}
