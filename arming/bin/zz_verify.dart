import 'dart:io';
import 'dart:typed_data';
import 'package:plimsoll_core/plimsoll_core.dart' as p;
class Call { const Call(this.t,this.v,this.d); final String t; final BigInt v; final Uint8List d; }
Uint8List enc(List<Call> calls){final els=<Uint8List>[];
 for(final c in calls){els.add(p.abiConcat([p.abiAddressWord(c.t),p.abiWord(c.v),p.abiWord(BigInt.from(96)),p.abiDynamicBytes(c.d)]));}
 var cur=calls.length*32; final offs=<Uint8List>[];
 for(final e in els){offs.add(p.abiWord(BigInt.from(cur)));cur+=e.length;}
 final sel=Uint8List(4)..[0]=0x2b..[1]=0x2e..[2]=0xe7..[3]=0x83;
 return p.abiConcat([sel,p.abiWord(BigInt.from(32)),p.abiWord(BigInt.from(calls.length)),...offs,...els]);}
Uint8List bs(String s){final t=s.startsWith('0x')?s.substring(2):s;return Uint8List.fromList([for(var i=0;i<t.length;i+=2)int.parse(t.substring(i,i+2),radix:16)]);}
String hx(Uint8List b)=>'0x${b.map((x)=>x.toRadixString(16).padLeft(2,'0')).join()}';
Uint8List approve(String sp,BigInt amt)=>p.abiConcat([bs('095ea7b3'),p.abiAddressWord(sp),p.abiWord(amt)]);
Uint8List armCd(BigInt total,BigInt part,BigInt minOut,BigInt trig,BigInt expiry,BigInt fee,BigInt budget)=>
 p.abiConcat([bs('c33d4cc3'),p.abiWord(BigInt.zero),p.abiWord(BigInt.zero),p.abiWord(BigInt.one),p.abiWord(BigInt.one),
  p.abiWord(BigInt.two),p.abiWord(total),p.abiWord(part),p.abiWord(minOut),p.abiWord(trig),p.abiWord(expiry),
  p.abiWord(BigInt.zero),p.abiWord(BigInt.zero),p.abiWord(fee),p.abiWord(budget)]);
const FXRP='0x0b6A3645c240605887a5532109323A3E12273dc7';
const WC2FLR='0xC67DCE33D7A8efA5FfEB961899C73fe01bCe9273';
const TRIMMY='0xf73a2af06b315adaa1afe2c1a6c1a6933d8a6554';
const EVIL='0x00000000000000000000000000000000dEaDbEeF';
const PA='0x07a76b5c3d03f5bff4cb3e043b1d17a1b40920bf';
void write(String n,List<Call> c){final op=p.PackedUserOperation(sender:PA,nonce:BigInt.zero,callData:enc(c));
 final pre=op.encode();
 final memo=p.MemoCodec.encodeSmartAccount(opcode:p.SmartAccountOpcode.customInstruction,payload:p.keccak256(pre),executorFeeUBA:BigInt.from(10000));
 File('/tmp/trimmy-attack/$n.hex').writeAsStringSync(hx(pre));
 File('/tmp/trimmy-attack/$n.memo').writeAsStringSync(hx(memo));
 stdout.writeln('$n written');}
void main(){
 final amt=BigInt.from(1009400);
 final exp=BigInt.from(DateTime.utc(2026,8,14).millisecondsSinceEpoch~/1000);
 final arm=armCd(BigInt.from(1000000),BigInt.from(1000000),BigInt.from(900000),BigInt.from(60),exp,BigInt.from(9400),BigInt.from(9400));
 // Baseline with a FIXED expiry so honest/hostile differ only where it matters.
 write('h2-honest',[Call(FXRP,BigInt.zero,approve(TRIMMY,amt)),Call(TRIMMY,BigInt.zero,arm)]);
 // (1) allowance goes to the REAL Trimmy; only the ARM target is hostile.
 write('h2-armtarget',[Call(FXRP,BigInt.zero,approve(TRIMMY,amt)),Call(EVIL,BigInt.zero,arm)]);
 // (2) approve target is a DIFFERENT allowlisted token (18dp), still labelled "FXRP" at 6dp.
 write('h2-wrongtoken',[Call(WC2FLR,BigInt.zero,approve(TRIMMY,amt)),Call(TRIMMY,BigInt.zero,arm)]);
 // (3) approve target is WC2FLR, spender EVIL, unlimited.
 write('h2-wc2flr-evil',[Call(WC2FLR,BigInt.zero,approve(EVIL,BigInt.two.pow(256)-BigInt.one)),Call(TRIMMY,BigInt.zero,arm)]);
}
