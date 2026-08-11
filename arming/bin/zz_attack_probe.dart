// TEMPORARY attack probe, delete after use.
import 'dart:io';
import 'dart:typed_data';

import 'package:plimsoll_core/plimsoll_core.dart' as p;
import 'package:trimmy_arming/arming.dart' as a;

String hex(Uint8List b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List h(String s) {
  final t = s.replaceFirst('0x', '');
  return Uint8List.fromList([
    for (var i = 0; i < t.length; i += 2) int.parse(t.substring(i, i + 2), radix: 16)
  ]);
}

void emit(String label, List<a.Call> calls) {
  final enc = a.encodeExecuteUserOp(calls);
  stdout.writeln('$label\t0x${hex(enc)}');
  final d = p.decodeExecuteUserOp(enc);
  switch (d) {
    case p.CallBatchUndecodable(:final reason):
      stdout.writeln('$label\tPLIMSOLL-UNDECODABLE: $reason');
    case p.CallBatchDecoded(:final calls):
      for (var i = 0; i < calls.length; i++) {
        stdout.writeln('$label\tcall$i target=${calls[i].target} '
            'value=${calls[i].value} dataLen=${calls[i].data.length} data=0x${hex(calls[i].data)}');
      }
  }
}

void main() {
  const t0 = '0x0b6A3645c240605887a5532109323A3E12273dc7';
  const t1 = '0xf73a2af06b315adaa1afe2c1a6c1a6933d8a6554';
  const t2 = '0xC67DCE33D7A8efA5FfEB961899C73fe01bCe9273';

  final d1 = h('095ea7b3'
      '000000000000000000000000f73a2af06b315adaa1afe2c1a6c1a6933d8a6554'
      '00000000000000000000000000000000000000000000000000000000000f4240');
  final d2 = h('deadbeef');
  final empty = Uint8List(0);
  final d33 = Uint8List.fromList(List<int>.generate(33, (i) => i + 1)); // not word aligned

  emit('ONE', [a.Call(t0, BigInt.zero, d1)]);
  emit('TWO', [a.Call(t0, BigInt.zero, d1), a.Call(t1, BigInt.from(7), d2)]);
  emit('THREE', [
    a.Call(t0, BigInt.zero, d1),
    a.Call(t1, BigInt.from(7), d2),
    a.Call(t2, BigInt.zero, d33),
  ]);
  emit('EMPTYDATA', [a.Call(t0, BigInt.from(123), empty), a.Call(t1, BigInt.zero, d2)]);
  emit('ZEROCALLS', <a.Call>[]);
}
