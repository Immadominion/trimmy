// XRPL address validation, with the checksum actually checked.
//
// This is not cosmetic input validation. `MasterAccountController.getPersonalAccount(string)` is a
// **deterministic derivation, not a registry lookup**, measured on Coston2, it returns a
// plausible-looking account for any string at all:
//
//   rDE4JUm2jaue31VwidRXWuWzf5dQkUxcsB  ->  0x07a76b5c...      (the real one)
//   rDE4JUm2jaue31VwidRXWuWzf5dQkUxcsA  ->  0x6085dbe8...      (one character changed)
//   not-an-address                      ->  0xff16dc7a...      (not an address at all)
//
// So a typo does not fail. It silently derives a different Flare account, and this tool would then
// build an arming payment that sets an allowance and arms a rule on an account the sender does not
// control, irreversibly, because an XRPL payment cannot be recalled.
//
// A base58check address carries its own four-byte checksum precisely so this is detectable
// offline, before anything is sent. Rule 7: refuse rather than proceed on an unknown.

import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;

const _alphabet = 'rpshnaf39wBUDNEGHJKLM4PQRST7VWXYZ2bcdeCg65jkm8oFqi1tuvAxyz';

const int _accountPrefix = 0x00; // 'r' addresses
const int _payloadLength = 21; // 1 prefix byte + 20 account id bytes

/// Thrown when an address cannot be trusted. The message is meant for a person.
class InvalidXrplAddress implements Exception {
  const InvalidXrplAddress(this.message);
  final String message;
  @override
  String toString() => message;
}

Uint8List _base58Decode(String s) {
  final index = <String, int>{
    for (var i = 0; i < _alphabet.length; i++) _alphabet[i]: i,
  };

  var num = BigInt.zero;
  for (final ch in s.split('')) {
    final v = index[ch];
    if (v == null) {
      throw InvalidXrplAddress('"$ch" is not a valid character in an XRPL address.');
    }
    num = num * BigInt.from(58) + BigInt.from(v);
  }

  final bytes = <int>[];
  while (num > BigInt.zero) {
    bytes.insert(0, (num & BigInt.from(0xff)).toInt());
    num = num >> 8;
  }
  // Leading zero characters are significant and encode leading zero bytes.
  for (final ch in s.split('')) {
    if (ch != _alphabet[0]) break;
    bytes.insert(0, 0);
  }
  return Uint8List.fromList(bytes);
}

/// Validates an XRPL classic address, returning it unchanged.
///
/// Throws [InvalidXrplAddress] rather than returning a bool, because every caller here is about to
/// build an irreversible payment and none of them should be able to ignore the result.
String validateXrplAddress(String address) {
  final s = address.trim();
  if (s.isEmpty) throw const InvalidXrplAddress('No XRPL address given.');
  if (!s.startsWith('r')) {
    throw const InvalidXrplAddress('An XRPL address starts with "r".');
  }
  if (s.length < 25 || s.length > 35) {
    throw InvalidXrplAddress(
      'That is ${s.length} characters; an XRPL address is 25 to 35.',
    );
  }

  final decoded = _base58Decode(s);
  if (decoded.length != _payloadLength + 4) {
    throw const InvalidXrplAddress('That is not a well-formed XRPL address.');
  }

  final payload = Uint8List.sublistView(decoded, 0, _payloadLength);
  final checksum = Uint8List.sublistView(decoded, _payloadLength);
  if (payload[0] != _accountPrefix) {
    throw const InvalidXrplAddress('That is not an XRPL account address.');
  }

  final expected = sha256.convert(sha256.convert(payload).bytes).bytes;
  for (var i = 0; i < 4; i++) {
    if (expected[i] != checksum[i]) {
      throw const InvalidXrplAddress(
        'That address fails its own checksum. It is mistyped. Copy it from your wallet '
        'rather than retyping it.',
      );
    }
  }
  return s;
}
