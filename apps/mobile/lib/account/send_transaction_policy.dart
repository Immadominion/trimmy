import 'package:solana/solana.dart' show Ed25519HDPublicKey;
import 'reviewed_transaction.dart';
import 'wallet_trade_signer.dart';

const _system = '11111111111111111111111111111111';
const _compute = 'ComputeBudget111111111111111111111111111111';
const _ata = 'ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL';
const _token = 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
const _token2022 = 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb';
const _usdc = 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v';
Never _reject() => throw const WalletTradeException('INVALID_TRANSACTION');
BigInt _raw(String value) {
  if (!RegExp(r'^(?:0|[1-9][0-9]{0,19})$').hasMatch(value)) _reject();
  final number = BigInt.parse(value);
  if (number > BigInt.parse('18446744073709551615')) _reject();
  return number;
}

BigInt _little(List<int> bytes, int start, int size) {
  if (start + size > bytes.length) _reject();
  var out = BigInt.zero;
  for (var i = size - 1; i >= 0; i--) {
    out = out * BigInt.from(256) + BigInt.from(bytes[start + i]);
  }
  return out;
}

bool _equal(List<String> actual, List<String> expected) =>
    actual.length == expected.length &&
    List.generate(
      actual.length,
      (i) => actual[i] == expected[i],
    ).every((x) => x);
Future<String> _associated(String owner, String mint, String program) async =>
    (await Ed25519HDPublicKey.findProgramAddress(
      programId: Ed25519HDPublicKey.fromBase58(_ata),
      seeds: [
        owner,
        program,
        mint,
      ].map((key) => Ed25519HDPublicKey.fromBase58(key).bytes),
    )).toBase58();

/// Offline checks of the direct send, independent of API instruction labels.
/// Token-2022 receipt/rent remain estimates: this is not an issuer-state oracle.
Future<void> checkSendTransaction({
  required String transaction,
  required String from,
  required String destination,
  required String assetId,
  required int decimals,
  required String amountRaw,
  required String receivedRaw,
  required bool createsAccount,
  required String networkFeeLamports,
  required String accountRentLamports,
}) async {
  try {
    final tx = ReviewedTransaction.parse(transaction, from);
    if (tx.signatures.length != 1 ||
        tx.lookupCount != 0 ||
        from == destination) {
      _reject();
    }
    Ed25519HDPublicKey.fromBase58(destination);
    final amount = _raw(amountRaw),
        received = _raw(receivedRaw),
        fee = _raw(networkFeeLamports),
        rent = _raw(accountRentLamports);
    if (amount == BigInt.zero ||
        received == BigInt.zero ||
        received > amount ||
        fee > BigInt.from(25000) ||
        rent > BigInt.from(10000000) ||
        decimals < 0 ||
        decimals > 18) {
      _reject();
    }
    final isSol = assetId == 'SOL', mint = assetId == 'USDC' ? _usdc : assetId;
    if (isSol &&
            (decimals != 9 ||
                createsAccount ||
                rent != BigInt.zero ||
                received != amount) ||
        assetId == 'USDC' && (decimals != 6 || received != amount) ||
        !createsAccount && rent != BigInt.zero ||
        createsAccount && rent == BigInt.zero) {
      _reject();
    }
    BigInt? units, price;
    var transfers = 0, creations = 0;
    String? transferProgram, creationProgram;
    final writable = {from};
    for (final ix in tx.instructions) {
      final program = tx.accounts[ix.programIndex],
          keys = ix.accounts.map((i) => tx.accounts[i]).toList();
      final data = ix.data;
      if (tx.writable[ix.programIndex]) _reject();
      if (program == _compute) {
        if (keys.isNotEmpty) _reject();
        if (data.length == 5 && data[0] == 2 && units == null) {
          units = _little(data, 1, 4);
        } else if (data.length == 9 && data[0] == 3 && price == null) {
          price = _little(data, 1, 8);
        } else {
          _reject();
        }
      } else if (program == _system && isSol) {
        if (++transfers != 1 ||
            data.length != 12 ||
            _little(data, 0, 4) != BigInt.two ||
            _little(data, 4, 8) != amount ||
            !_equal(keys, [from, destination])) {
          _reject();
        }
        writable.add(destination);
      } else if (!isSol && {_token, _token2022}.contains(program)) {
        if (++transfers != 1 ||
            keys.length != 4 ||
            data.length != 10 ||
            data[0] != 12 ||
            _little(data, 1, 8) != amount ||
            data[9] != decimals) {
          _reject();
        }
        if (assetId == 'USDC' && program != _token) _reject();
        final source = await _associated(from, mint, program),
            target = await _associated(destination, mint, program);
        if (!_equal(keys, [source, mint, target, from])) _reject();
        transferProgram = program;
        writable.addAll([source, target]);
      } else if (!isSol && program == _ata) {
        if (++creations != 1 ||
            transfers != 0 ||
            !createsAccount ||
            keys.length != 6 ||
            data.length != 1 ||
            data[0] != 1 ||
            !{_token, _token2022}.contains(keys[5])) {
          _reject();
        }
        final tokenProgram = keys[5],
            target = await _associated(destination, mint, tokenProgram);
        if (!_equal(keys, [
          from,
          target,
          destination,
          mint,
          _system,
          tokenProgram,
        ])) {
          _reject();
        }
        creationProgram = tokenProgram;
        writable.add(target);
      } else {
        _reject();
      }
    }
    if (transfers != 1 ||
        creations != (createsAccount ? 1 : 0) ||
        creationProgram != null && creationProgram != transferProgram ||
        units == null ||
        units < BigInt.one ||
        units > BigInt.from(200000) ||
        price == null ||
        price > BigInt.from(100000) ||
        BigInt.from(5000) +
                (units * price + BigInt.from(999999)) ~/ BigInt.from(1000000) !=
            fee) {
      _reject();
    }
    for (var i = 0; i < tx.accounts.length; i++) {
      if (tx.writable[i] != writable.contains(tx.accounts[i])) _reject();
    }
  } on WalletTradeException {
    rethrow;
  } catch (_) {
    _reject();
  }
}
