// Builds hostile arming preimages to test decode.dart, the "independent decoder".
import 'dart:io';
import 'dart:typed_data';
import 'package:plimsoll_core/plimsoll_core.dart' as p;

class Call { const Call(this.t, this.v, this.d); final String t; final BigInt v; final Uint8List d; }

Uint8List enc(List<Call> calls) {
  final els = <Uint8List>[];
  for (final c in calls) {
    els.add(p.abiConcat([p.abiAddressWord(c.t), p.abiWord(c.v), p.abiWord(BigInt.from(96)), p.abiDynamicBytes(c.d)]));
  }
  var cur = calls.length * 32; final offs = <Uint8List>[];
  for (final e in els) { offs.add(p.abiWord(BigInt.from(cur))); cur += e.length; }
  final sel = Uint8List(4)..[0]=0x2b..[1]=0x2e..[2]=0xe7..[3]=0x83;
  return p.abiConcat([sel, p.abiWord(BigInt.from(32)), p.abiWord(BigInt.from(calls.length)), ...offs, ...els]);
}
Uint8List bs(String s){final t=s.startsWith('0x')?s.substring(2):s;return Uint8List.fromList([for(var i=0;i<t.length;i+=2)int.parse(t.substring(i,i+2),radix:16)]);}
String hx(Uint8List b)=>'0x${b.map((x)=>x.toRadixString(16).padLeft(2,'0')).join()}';

Uint8List approve(String sp, BigInt amt) => p.abiConcat([bs('095ea7b3'), p.abiAddressWord(sp), p.abiWord(amt)]);
Uint8List armCd({required int verb, required int trigger, required BigInt total, required BigInt part,
  required BigInt minOut, required BigInt trig, required BigInt expiry, required BigInt fee, required BigInt budget}) =>
  p.abiConcat([bs('c33d4cc3'),
    p.abiWord(BigInt.zero), p.abiWord(BigInt.zero), p.abiWord(BigInt.from(verb)), p.abiWord(BigInt.one),
    p.abiWord(BigInt.from(trigger)), p.abiWord(total), p.abiWord(part), p.abiWord(minOut),
    p.abiWord(trig), p.abiWord(expiry), p.abiWord(BigInt.zero), p.abiWord(BigInt.zero),
    p.abiWord(fee), p.abiWord(budget)]);

const FXRP = '0x0b6A3645c240605887a5532109323A3E12273dc7';
const TRIMMY = '0xf73a2af06b315adaa1afe2c1a6c1a6933d8a6554';
const EVIL   = '0x00000000000000000000000000000000dEaDbEeF';
const PA     = '0x07a76b5c3d03f5bff4cb3e043b1d17a1b40920bf';

void write(String name, List<Call> calls) {
  final op = p.PackedUserOperation(sender: PA, nonce: BigInt.zero, callData: enc(calls));
  final pre = op.encode();
  final memo = p.MemoCodec.encodeSmartAccount(
      opcode: p.SmartAccountOpcode.customInstruction, payload: p.keccak256(pre),
      executorFeeUBA: BigInt.from(10000));
  Directory('/tmp/trimmy-attack').createSync(recursive: true);
  File('/tmp/trimmy-attack/$name.hex').writeAsStringSync(hx(pre));
  File('/tmp/trimmy-attack/$name.memo').writeAsStringSync(hx(memo));
  stdout.writeln('$name -> /tmp/trimmy-attack/$name.hex (${pre.length}B)');
}

void main() {
  final amt = BigInt.from(1009400);
  final exp = BigInt.from(DateTime.now().toUtc().add(const Duration(days: 7)).millisecondsSinceEpoch ~/ 1000);
  final arm = armCd(verb:1, trigger:2, total:BigInt.from(1000000), part:BigInt.from(1000000),
      minOut:BigInt.from(900000), trig:BigInt.from(60), expiry:exp, fee:BigInt.from(9400), budget:BigInt.from(9400));

  write('honest', [Call(FXRP, BigInt.zero, approve(TRIMMY, amt)), Call(TRIMMY, BigInt.zero, arm)]);
  // A: approve goes to the attacker; the "arm" call targets an attacker contract with the same selector.
  write('hostile-target', [Call(FXRP, BigInt.zero, approve(EVIL, amt)), Call(EVIL, BigInt.zero, arm)]);
  // B: honest-looking batch plus an undescribed native-value transfer (data < 4 bytes).
  write('hidden-value', [Call(FXRP, BigInt.zero, approve(TRIMMY, amt)), Call(TRIMMY, BigInt.zero, arm),
      Call(EVIL, BigInt.from(10) * BigInt.from(10).pow(18), Uint8List(0))]);
  // C: truncated approve — selector only.
  write('short-approve', [Call(FXRP, BigInt.zero, bs('095ea7b3'))]);
  // D: expiry at the uint64 ceiling.
  write('huge-expiry', [Call(TRIMMY, BigInt.zero, armCd(verb:1, trigger:2, total:BigInt.from(1000000),
      part:BigInt.from(1000000), minOut:BigInt.from(900000), trig:BigInt.from(60),
      expiry:BigInt.two.pow(64) - BigInt.one, fee:BigInt.from(9400), budget:BigInt.from(9400)))]);
}
