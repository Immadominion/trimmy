import 'dart:convert';

import 'wallet_possession_models.dart';

/// An explicit user action signs only a validated, fixed Trimmy challenge.
/// This capability cannot create a wallet, sign a transaction or send funds.
abstract interface class WalletPossessionSigner {
  Future<String> sign({
    required String expectedSubject,
    required WalletPossessionChallenge challenge,
  });
}

/// Privy Flutter 0.10.2 returns standard base64. The Trimmy API expects base58.
/// This checks encoding and byte count only; the server verifies the signature.
String walletPossessionSignatureFromBase64(String value) {
  const invalid = WalletPossessionException(
    WalletPossessionFailure.invalidSignature,
  );
  if (value.length != 88) throw invalid;
  final List<int> bytes;
  try {
    bytes = base64.decode(value);
  } catch (_) {
    throw invalid;
  }
  if (bytes.length != 64 || base64.encode(bytes) != value) throw invalid;
  var number = BigInt.zero;
  for (final byte in bytes) {
    number = (number << 8) | BigInt.from(byte);
  }
  if (number == BigInt.zero) throw invalid;
  const alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  final digits = <String>[];
  final radix = BigInt.from(58);
  while (number > BigInt.zero) {
    digits.add(alphabet[(number % radix).toInt()]);
    number ~/= radix;
  }
  for (final byte in bytes) {
    if (byte != 0) break;
    digits.add('1');
  }
  return digits.reversed.join();
}
