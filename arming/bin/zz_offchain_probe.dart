// Attack probe: differential-test arm.dart's hand-rolled encodeExecuteUserOp
// against `cast abi-encode`, and probe decode.dart's robustness.
import 'dart:typed_data';
import 'package:plimsoll_core/plimsoll_core.dart' as p;

class Call {
  const Call(this.target, this.value, this.data);
  final String target;
  final BigInt value;
  final Uint8List data;
}

// VERBATIM COPY of arm.dart:50-85
Uint8List encodeExecuteUserOp(List<Call> calls) {
  final elements = <Uint8List>[];
  for (final c in calls) {
    elements.add(p.abiConcat([
      p.abiAddressWord(c.target),
      p.abiWord(c.value),
      p.abiWord(BigInt.from(96)),
      p.abiDynamicBytes(c.data),
    ]));
  }
  var cursor = calls.length * 32;
  final offsets = <Uint8List>[];
  for (final e in elements) {
    offsets.add(p.abiWord(BigInt.from(cursor)));
    cursor += e.length;
  }
  final selector = Uint8List(4)..[0]=0x2b..[1]=0x2e..[2]=0xe7..[3]=0x83;
  return p.abiConcat([
    selector,
    p.abiWord(BigInt.from(32)),
    p.abiWord(BigInt.from(calls.length)),
    ...offsets,
    ...elements,
  ]);
}

String hex(Uint8List b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
Uint8List bytes(String s) {
  final t = s.startsWith('0x') ? s.substring(2) : s;
  return Uint8List.fromList([for (var i=0;i<t.length;i+=2) int.parse(t.substring(i,i+2), radix:16)]);
}

void emit(String name, List<Call> calls) {
  final enc = encodeExecuteUserOp(calls);
  print('CASE $name');
  print('  OURS 0x${hex(Uint8List.sublistView(enc,4))}');
  final d = p.decodeExecuteUserOp(enc);
  switch (d) {
    case p.CallBatchUndecodable(:final reason): print('  PLIMSOLL: UNDECODABLE $reason');
    case p.CallBatchDecoded(:final calls):
      print('  PLIMSOLL: ${calls.length} call(s)');
      for (final c in calls) { print('    target=${c.target} value=${c.valueOrZero} data=0x${hex(c.data)}'); }
  }
}

void main() {
  final a = '0x0b6A3645c240605887a5532109323A3E12273dc7';
  final b = '0xf73a2af06b315adaa1afe2c1a6c1a6933d8a6554';
  final c = '0xC67DCE33D7A8efA5FfEB961899C73fe01bCe9273';
  emit('0-calls', []);
  emit('1-call-empty-data', [Call(a, BigInt.zero, Uint8List(0))]);
  emit('1-call-4bytes', [Call(a, BigInt.zero, bytes('deadbeef'))]);
  emit('1-call-33bytes', [Call(a, BigInt.one, bytes('00'*33))]);
  emit('2-calls', [Call(a, BigInt.zero, bytes('095ea7b3')), Call(b, BigInt.zero, bytes('c33d4cc3'+'11'*64))]);
  emit('3-calls', [Call(a, BigInt.zero, bytes('aa')), Call(b, BigInt.from(7), Uint8List(0)), Call(c, BigInt.zero, bytes('bb'*70))]);
}
