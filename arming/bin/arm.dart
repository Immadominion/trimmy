// The command line around `package:trimmy_arming/arming.dart`.
//
// Everything that builds or validates a payment lives in the library, so this
// file is argument parsing and printing. A refusal reaches the shell as a
// non-zero exit, because a warning nobody can act on is not a safety feature.
//
// Usage:
//   TRIMMY_ADDRESS=0x... dart run bin/arm.dart --xrpl rDE4... --amount 1000000

import 'dart:io';
import 'dart:typed_data';

import 'package:flare_network/flare_network.dart' as fn;
import 'package:plimsoll_core/plimsoll_core.dart' as p;
import 'package:trimmy_arming/arming.dart';
import 'package:trimmy_arming/xrpl_address.dart';

Future<void> main(List<String> args) async {
  String? arg(String name) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final trimmy = Platform.environment['TRIMMY_ADDRESS'];
  final xrplRaw = arg('xrpl') ?? Platform.environment['XRPL_TEST_ADDRESS'];
  if (trimmy == null || xrplRaw == null) {
    stderr.writeln('need TRIMMY_ADDRESS and --xrpl <address>');
    exit(2);
  }

  // Check the checksum BEFORE anything touches the chain. `getPersonalAccount` derives an address
  // from whatever string it is handed rather than looking one up, so a mistyped address does not
  // fail here. It quietly resolves to a different account, and the payment armed against it
  // cannot be recalled. See docs/GROUND-TRUTH.md.
  final String xrpl;
  try {
    xrpl = validateXrplAddress(xrplRaw);
  } on InvalidXrplAddress catch (e) {
    stderr.writeln('REFUSING TO ARM: $e');
    exit(2);
  }

  final part = BigInt.parse(arg('amount') ?? '1000000');
  final keeperFee = BigInt.parse(arg('keeper-fee') ?? '9400');

  // How many times the rule may fire. Trimmy derives this itself as
  // ceilDiv(totalSellAmount, partSellAmount) and reverts Exhausted() once spent >= total, so
  // sending total == part produces a rule that runs EXACTLY ONCE, whatever interval it carries.
  // This tool used to do that unconditionally while printing "every 60 seconds".
  final runs = BigInt.parse(arg('runs') ?? '1');
  if (runs <= BigInt.zero) {
    stderr.writeln('REFUSING TO ARM: --runs must be at least 1');
    exit(2);
  }
  final amount = part * runs;
  final executorFee = BigInt.parse(arg('executor-fee') ?? '0');

  const fxrp = '0x0b6A3645c240605887a5532109323A3E12273dc7';
  const controller = '0x434936d47503353f06750Db1A444DBDC5F0AD37c';

  final client = fn.FlareClient(fn.FlareChain.coston2);
  try {
    // Rule 2: resolve, never hardcode. Assert the controller we are about to arm against is the
    // one the AssetManager itself points at, two are live on Coston2 with identical ABIs, and
    // arming against the wrong one sets an allowance on an empty account, permanently.
    final personalAccount = await _call(
      client,
      controller,
      'getPersonalAccount(string)',
      [_abiString(xrpl)],
    );
    final pa = '0x${personalAccount.sublist(12, 32).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';

    final nonceBytes = await _call(client, controller, 'getNonce(address)', [
      p.abiAddressWord(pa),
    ]);
    final nonce = _toBigInt(nonceBytes);

    final armCalldata = encodeArm(
      sellTokenId: 0,
      buyTokenId: 0,
      verb: 1, // DEPOSIT_VAULT
      venueId: 1,
      trigger: 2, // SCHEDULE
      totalSellAmount: amount,
      partSellAmount: part,
      // A floor on ONE part: execute() sells partSellAmount and checks that part's proceeds.
      minOutAbsolute: part * BigInt.from(90) ~/ BigInt.from(100),
      triggerValue: BigInt.from(60),
      expiry: BigInt.from(
        DateTime.now().toUtc().add(const Duration(days: 7)).millisecondsSinceEpoch ~/ 1000,
      ),
      slippageBips: 0,
      protocolFeeBips: 0,
      keeperFeeFlat: keeperFee,
      // L2: the budget must fund every execution or the contract refuses to arm at all.
      keeperFeeBudget: keeperFee * runs,
    );

    final payment = buildArmingPayment(
      personalAccount: pa,
      nonce: nonce,
      fxrp: fxrp,
      trimmy: trimmy,
      allowance: amount + keeperFee * runs,
      armCalldata: armCalldata,
      executorFeeUBA: executorFee,
    );

    stdout.writeln('XRPL arming payment');
    stdout.writeln('  xrpl account     : $xrpl');
    stdout.writeln('  personal account : ${payment.personalAccount}');
    stdout.writeln('  nonce            : ${payment.nonce}');
    stdout.writeln('  calls            : ${payment.calls.length} '
        '(approve ${amount + keeperFee}, arm)');
    stdout.writeln('  userOp bytes     : ${payment.userOp.encode().length}');
    stdout.writeln('  commitment       : ${fn.bytesToHex(payment.commitment)}');
    stdout.writeln('  memo (42 bytes)  : ${fn.bytesToHex(payment.memo).substring(2).toUpperCase()}');
    stdout.writeln('');
    stdout.writeln('  userOp pre-image (deliver to the executor off-chain):');
    stdout.writeln('  ${fn.bytesToHex(payment.userOp.encode())}');
  } finally {
    client.close();
  }
}

Future<Uint8List> _call(
  fn.FlareClient client,
  String to,
  String signature,
  List<Uint8List> argsEncoded,
) async {
  final data = p.abiConcat([fn.functionSelector(signature), ...argsEncoded]);
  return client.ethCall(to: fn.EthAddress.parse(to, validateChecksum: false), data: data);
}

Uint8List _abiString(String s) {
  final bytes = Uint8List.fromList(s.codeUnits);
  return p.abiConcat([
    p.abiWord(BigInt.from(32)),
    p.abiWord(BigInt.from(bytes.length)),
    Uint8List(((bytes.length + 31) ~/ 32) * 32)..setAll(0, bytes),
  ]);
}

BigInt _toBigInt(Uint8List b) {
  var v = BigInt.zero;
  for (final x in b) {
    v = (v << 8) | BigInt.from(x);
  }
  return v;
}
