// Renders what an arming payment will actually do, in plain terms.
//
// ## Why this exists as a separate program
//
// The `0xFE` memo a user signs in Xaman is 42 bytes, 32 of which are a hash. It is unreadable. The
// batch it commits to is delivered to the executor off-chain, so nothing the user sees describes
// where their money is about to go.
//
// A decoder built into the same front end that produced the payment does not fix that: a
// compromised front end takes its own decoder with it, and the user is told a comforting story
// about a hostile batch. So this is a **standalone program with no network access**. It reads a
// pre-image, re-derives the commitment, and describes the calls. And it will do that for a
// payment produced by anyone, including one produced by an attacker.
//
// On stage this decodes a batch we did not generate. That is the point.
//
// Usage:
//   dart run bin/decode.dart --preimage 0x... [--memo FE00...]
//   dart run bin/decode.dart --file out/userop-preimage.hex --memo-file out/memo.hex

import 'dart:io';
import 'dart:typed_data';

import 'package:plimsoll_core/plimsoll_core.dart' as p;

const _fxrp = '0x0b6a3645c240605887a5532109323a3e12273dc7';

const _verbs = ['SWAP', 'DEPOSIT_VAULT', 'EXIT_VAULT'];
const _triggers = ['PRICE_BELOW', 'PRICE_ABOVE', 'SCHEDULE'];

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List _parseHex(String s) {
  final t = s.trim().replaceFirst(RegExp('^0x', caseSensitive: false), '');
  if (t.length.isOdd) throw ArgumentError('odd-length hex');
  return Uint8List.fromList([
    for (var i = 0; i < t.length; i += 2) int.parse(t.substring(i, i + 2), radix: 16),
  ]);
}

BigInt _word(Uint8List d, int i) {
  var v = BigInt.zero;
  for (var k = i * 32; k < (i + 1) * 32; k++) {
    v = (v << 8) | BigInt.from(d[k]);
  }
  return v;
}

/// 6-decimal amounts, rendered as a decimal string. No floating point anywhere, rule 8.
String _fxrpAmount(BigInt uba) {
  final s = uba.toString().padLeft(7, '0');
  final whole = s.substring(0, s.length - 6);
  final frac = s.substring(s.length - 6).replaceFirst(RegExp(r'0+$'), '');
  return frac.isEmpty ? whole : '$whole.$frac';
}

void _describeApprove(Uint8List data) {
  final spender = '0x${_hex(Uint8List.sublistView(data, 16, 36))}';
  final amount = _word(Uint8List.sublistView(data, 4), 1);
  stdout.writeln('  1. APPROVE');
  stdout.writeln('     lets  $spender');
  stdout.writeln('     spend ${_fxrpAmount(amount)} FXRP of yours');
  stdout.writeln('     note  this is an allowance, not a transfer. It is capped at this exact');
  stdout.writeln('           amount, and nothing may spend more than it.');
}

void _describeArm(Uint8List data) {
  final b = Uint8List.sublistView(data, 4);
  int w(int i) => _word(b, i).toInt();
  BigInt bw(int i) => _word(b, i);

  final verb = w(2);
  final trigger = w(4);
  stdout.writeln('  2. ARM A RULE');
  stdout.writeln('     action     ${verb < _verbs.length ? _verbs[verb] : 'UNKNOWN($verb)'}');
  stdout.writeln('     trigger    ${trigger < _triggers.length ? _triggers[trigger] : 'UNKNOWN($trigger)'}');
  stdout.writeln('     sell up to ${_fxrpAmount(bw(5))} (token #${w(0)})');
  stdout.writeln('     per run    ${_fxrpAmount(bw(6))}');
  stdout.writeln('     min out    ${_fxrpAmount(bw(7))}');

  // Trimmy derives the run count itself as ceilDiv(totalSellAmount, partSellAmount) and refuses to
  // execute once spent >= total. State it, rather than leaving a reader to divide two numbers
  // several lines apart: a rule with total == part fires exactly ONCE, and printing only
  // "every 60 seconds" against it describes a recurring rule that does not exist.
  final total = bw(5);
  final perRun = bw(6);
  final runs = perRun > BigInt.zero
      ? (total + perRun - BigInt.one) ~/ perRun
      : BigInt.one;
  stdout.writeln('     runs       $runs (ceilDiv of the two amounts above)');

  if (trigger == 2) {
    if (runs == BigInt.one) {
      stdout.writeln('     every      n/a, one run only, so the ${bw(8)}s interval never applies');
    } else {
      stdout.writeln('     every      ${bw(8)} seconds, after an immediate first run');
    }
  } else {
    stdout.writeln('     threshold  ${bw(8)} (buy-token units per 1 whole sell token)');
  }
  final expiry = bw(9).toInt();
  stdout.writeln('     expires    ${DateTime.fromMillisecondsSinceEpoch(expiry * 1000, isUtc: true)}');
  // O-17: saying "slippage 50 bips max" alone is misleading, because fees come out of the
  // proceeds afterwards. The floor bounds what the VENUE may take; the fees are separate,
  // disclosed deductions. Both are stated, and so is the worst case the user actually receives.
  final part = bw(6);
  final slip = w(10);
  final keeperFee = bw(12);
  final protoBips = w(11);
  stdout.writeln('     venue floor  at most $slip bips below the oracle price');
  stdout.writeln('     keeper fee   ${_fxrpAmount(keeperFee)} per run '
      '(${_fxrpAmount(bw(13))} lifetime cap)');
  stdout.writeln('     protocol fee $protoBips bips of proceeds');
  stdout.writeln('     -> per run you sell ${_fxrpAmount(part)} and receive the proceeds');
  stdout.writeln('        MINUS those fees. The floor above bounds the venue, not the fees.');
}

void main(List<String> args) {
  // NOTE: `int main()` does NOT set the process exit code in Dart. Every refusal below calls
  // exit() explicitly, so a shell guard or CI step can actually act on it.
  String? arg(String n) {
    final i = args.indexOf('--$n');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  var preimageHex = arg('preimage');
  final file = arg('file');
  if (preimageHex == null && file != null) preimageHex = File(file).readAsStringSync();
  if (preimageHex == null) {
    stderr.writeln('need --preimage <hex> or --file <path>');
    exit(2);
  }

  final preimage = _parseHex(preimageHex);
  final commitment = p.keccak256(preimage);

  stdout.writeln('Trimmy arming payment, independent decode');
  stdout.writeln('  (no network, no trust in whoever produced this payment)\n');
  stdout.writeln('  user operation : ${preimage.length} bytes');
  stdout.writeln('  commitment     : 0x${_hex(commitment)}');

  // If a memo was supplied, the commitment must match it. This is the check that catches a payment
  // whose visible memo does not correspond to the batch being described.
  final memoHex = arg('memo') ??
      (arg('memo-file') != null ? File(arg('memo-file')!).readAsStringSync() : null);
  if (memoHex != null) {
    final memo = _parseHex(memoHex);
    if (memo.length != 42) {
      stdout.writeln('\n  MEMO REJECTED: ${memo.length} bytes, must be 42');
      exit(1);
    }
    if (memo[0] != 0xFE) {
      stdout.writeln('\n  MEMO REJECTED: opcode 0x${memo[0].toRadixString(16)}, expected 0xFE');
      exit(1);
    }
    final carried = Uint8List.sublistView(memo, 10, 42);
    for (var i = 0; i < 32; i++) {
      if (carried[i] != commitment[i]) {
        stdout.writeln('\n  ****  MEMO DOES NOT MATCH THIS USER OPERATION  ****');
        stdout.writeln('  memo commits to : 0x${_hex(carried)}');
        stdout.writeln('  this batch is   : 0x${_hex(commitment)}');
        stdout.writeln('  DO NOT SIGN. The payment would run a batch other than the one below.');
        exit(1);
      }
    }
    stdout.writeln('  memo           : matches this batch');
  }

  // Decode with Plimsoll, which knows the measured wire format.
  final op = p.PackedUserOperation.decode(preimage);
  switch (op) {
    case p.UserOpUndecodable(:final reason):
      stdout.writeln('\n  UNDECODABLE: $reason');
      exit(1);
    case p.UserOpDecoded(:final op):
      stdout.writeln('  sender         : ${op.sender}');
      stdout.writeln('  nonce          : ${op.nonce}');

      final batch = op.decodeCalls();
      switch (batch) {
        case p.CallBatchUndecodable(:final reason):
          stdout.writeln('\n  BATCH UNDECODABLE: $reason');
          exit(1);
        case p.CallBatchDecoded(:final calls):
          stdout.writeln('\n  This payment will do ${calls.length} thing(s):\n');
          for (final c in calls) {
            final data = c.data;
            if (data.length >= 4) {
              final sel = _hex(Uint8List.sublistView(data, 0, 4));
              if (sel == '095ea7b3') {
                _describeApprove(data);
                stdout.writeln('');
                continue;
              }
              if (sel == 'cc0c55f4') {
                _describeArm(data);
                stdout.writeln('');
                continue;
              }
              stdout.writeln('  ?. UNRECOGNISED CALL to ${c.target}');
              stdout.writeln('     selector 0x$sel. This decoder does not know it.');
              stdout.writeln('     Treat that as a reason NOT to sign, not as a detail.');
              stdout.writeln('');
            }
          }
          final touchesFxrp =
              calls.any((c) => c.target.toLowerCase() == _fxrp);
          if (!touchesFxrp) {
            stdout.writeln('  NOTE: no call touches FXRP. Check that is what you meant.');
          }
      }
  }
  exit(0);
}
