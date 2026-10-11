import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:solana/base58.dart';

import 'wallet_trade_signer.dart';

Never _invalid() => throw const WalletTradeException('INVALID_TRANSACTION');

class SolanaInstruction {
  const SolanaInstruction(this.programIndex, this.accounts, this.data);
  final int programIndex;
  final List<int> accounts, data;
}

/// Bounded legacy/v0 parser. Lookup descriptors are counted, never trusted as
/// resolved addresses. The direct-send policy refuses all lookups.
class ReviewedTransaction {
  ReviewedTransaction._(
    this.bytes,
    this.message,
    this.signatures,
    this.accounts,
    this.writable,
    this.instructions,
    this.lookupCount,
    this.signerSlot,
  );
  final Uint8List bytes, message;
  final List<List<int>> signatures;
  final List<String> accounts;
  final List<bool> writable;
  final List<SolanaInstruction> instructions;
  final int lookupCount, signerSlot;

  factory ReviewedTransaction.parse(String encoded, String wallet) {
    try {
      if (encoded.length > 1644) _invalid();
      final bytes = base64Decode(encoded);
      if (base64Encode(bytes) != encoded || bytes.length > 1232) _invalid();
      final reader = _Reader(bytes);
      final count = reader.short();
      if (count < 1 || count > 2) _invalid();
      final signatures = List.generate(count, (_) => reader.take(64));
      if (signatures.any((s) => s.any((b) => b != 0))) _invalid();
      final start = reader.cursor;
      final first = reader.byte();
      final versioned = first & 128 != 0;
      if (versioned && first != 128) _invalid();
      final required = versioned ? reader.byte() : first;
      final readonlySigned = reader.byte(), readonlyUnsigned = reader.byte();
      final keyCount = reader.short();
      if (required != count ||
          readonlySigned >= required ||
          keyCount < required ||
          keyCount > 256 ||
          readonlyUnsigned > keyCount - required) {
        _invalid();
      }
      final accounts = List.generate(
        keyCount,
        (_) => base58encode(reader.take(32)),
      );
      if (accounts.toSet().length != accounts.length) _invalid();
      final slot = accounts.take(required).toList().indexOf(wallet);
      if (slot != (count == 1 ? 0 : 1)) _invalid();
      final writable = List.generate(
        keyCount,
        (i) => i < required
            ? i < required - readonlySigned
            : i < keyCount - readonlyUnsigned,
      );
      reader.take(32); // recent blockhash
      final n = reader.short();
      if (n < 1 || n > 64) _invalid();
      final instructions = <SolanaInstruction>[];
      for (var i = 0; i < n; i++) {
        final program = reader.byte(), accountCount = reader.short();
        if (accountCount > 256) _invalid();
        final indexes = reader.take(accountCount);
        final data = reader.take(reader.short());
        instructions.add(SolanaInstruction(program, indexes, data));
      }
      var lookups = 0, loaded = 0;
      if (versioned) {
        lookups = reader.short();
        if (lookups > 32) _invalid();
        for (var i = 0; i < lookups; i++) {
          reader.take(32);
          for (var j = 0; j < 2; j++) {
            final n = reader.short();
            if (n > 256) _invalid();
            reader.take(n);
            loaded += n;
          }
        }
      }
      if (reader.cursor != bytes.length ||
          keyCount + loaded > 256 ||
          instructions.any(
            (ix) =>
                ix.programIndex >= keyCount ||
                ix.accounts.any((i) => i >= keyCount + loaded),
          )) {
        _invalid();
      }
      return ReviewedTransaction._(
        bytes,
        Uint8List.fromList(bytes.sublist(start)),
        signatures,
        accounts,
        writable,
        instructions,
        lookups,
        slot,
      );
    } on WalletTradeException {
      rethrow;
    } catch (_) {
      return _invalid();
    }
  }

  /// The SDK may fill only this wallet's slot, preserving every message byte.
  Future<void> verifySigned(String encoded, String wallet) async {
    try {
      if (encoded.length > 1644) _invalid();
      final signed = base64Decode(encoded);
      if (base64Encode(signed) != encoded || signed.length != bytes.length) {
        _invalid();
      }
      final offset = 1 + signerSlot * 64;
      for (var i = 0; i < bytes.length; i++) {
        if ((i < offset || i >= offset + 64) && signed[i] != bytes[i]) {
          _invalid();
        }
      }
      final signature = Signature(
        signed.sublist(offset, offset + 64),
        publicKey: SimplePublicKey(
          base58decode(wallet),
          type: KeyPairType.ed25519,
        ),
      );
      if (!await Ed25519().verify(message, signature: signature)) _invalid();
    } catch (_) {
      throw const WalletTradeException('SIGNATURE_MISMATCH');
    }
  }
}

class _Reader {
  _Reader(this.bytes);
  final List<int> bytes;
  int cursor = 0;
  int byte() {
    if (cursor >= bytes.length) _invalid();
    return bytes[cursor++];
  }

  List<int> take(int count) {
    if (count < 0 || cursor + count > bytes.length) _invalid();
    final value = bytes.sublist(cursor, cursor + count);
    cursor += count;
    return value;
  }

  int short() {
    var value = 0;
    for (var i = 0; i < 3; i++) {
      final b = byte();
      value |= (b & 127) << (7 * i);
      if (b & 128 == 0) {
        if (i > 0 && b == 0 || value > 65535) _invalid();
        return value;
      }
    }
    return _invalid();
  }
}
