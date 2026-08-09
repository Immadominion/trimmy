// Trimmy keeper — permissionless executor.
//
// The keeper is trusted with NOTHING. `Trimmy.execute` re-derives every bound on chain from the
// stored rule and a fresh FTSO read, and `msg.sender` appears in it exactly once: as the recipient
// of the flat keeper fee. So this process holds no authority over anyone's funds, and a leaked
// keeper key buys an attacker no capability the public does not already have.
//
// That also means keeper liveness is not a security property. Anyone can run this. We run one
// because someone has to, not because only we may.
//
// ## Why it simulates first
//
// Near a price threshold the feed oscillates across the trigger, so `execute` reverting is the
// COMMON case, not the exceptional one — the red-team flagged that the cost of those reverts was
// missing from every fee model written. This keeper never pays for one: every candidate is
// simulated with `eth_call` at the current block, and a transaction is only signed and broadcast
// when the simulation succeeds. A revert costs an RPC round trip, not gas.
//
// ## Signing
//
// `flare_network` holds no private keys and never will — a deliberate, permanent non-goal. It
// builds the transaction, prices it, broadcasts the signed bytes, waits for the receipt and
// explains a revert. The signature itself is shelled out to Foundry's `cast mktx`, which is the
// same split the SDK's own broadcast tests use.
//
// Usage:
//   source ~/.flare-dart/coston2-test.env
//   TRIMMY_ADDRESS=0x... dart run bin/keeper.dart --once
//   TRIMMY_ADDRESS=0x... dart run bin/keeper.dart --interval 15

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flare_network/flare_network.dart';

/// One rule as stored on chain, decoded from `ruleAt(uint256)`.
class Rule {
  Rule({
    required this.id,
    required this.account,
    required this.epoch,
    required this.verb,
    required this.trigger,
    required this.active,
    required this.totalSellAmount,
    required this.spent,
    required this.nextEligibleAt,
    required this.expiry,
    required this.keeperFeeFlat,
    required this.pendingShares,
    required this.claimableAt,
  });

  final int id;
  final EthAddress account;
  final int epoch;
  final int verb; // 0 SWAP, 1 DEPOSIT_VAULT, 2 EXIT_VAULT
  final int trigger; // 0 PRICE_BELOW, 1 PRICE_ABOVE, 2 SCHEDULE
  final bool active;
  final BigInt totalSellAmount;
  final BigInt spent;
  final BigInt nextEligibleAt;
  final BigInt expiry;
  final BigInt keeperFeeFlat;
  final BigInt pendingShares;
  final BigInt claimableAt;

  bool get exhausted => spent >= totalSellAmount;

  /// Cheap local filter. Deliberately conservative: it only rules a candidate OUT on conditions
  /// that are certain from stored state. Anything requiring a fresh oracle read — the price
  /// trigger, feed staleness, the execution floor — is left to the on-chain simulation, because
  /// duplicating that logic here would create a second implementation that can silently disagree
  /// with the contract.
  bool get maybeExecutable => active && !exhausted;

  bool get maybeClaimable => verb == 2 && pendingShares > BigInt.zero;
}

class Keeper {
  Keeper(this.client, this.trimmy, this.keeperAddress);

  final FlareClient client;
  final EthAddress trimmy;
  final EthAddress keeperAddress;

  static final _ruleCountSel = functionSelector('ruleCount()');
  static final _ruleAtSel = functionSelector('ruleAt(uint256)');
  static final _executeSel = functionSelector('execute(uint256)');
  static final _claimSel = functionSelector('claim(uint256)');
  static final _epochOfSel = functionSelector('epochOf(address)');

  Uint8List _withUint(Uint8List selector, BigInt value) {
    final out = Uint8List(selector.length + 32)..setAll(0, selector);
    final bytes = _padLeft32(value);
    out.setAll(selector.length, bytes);
    return out;
  }

  static Uint8List _padLeft32(BigInt v) {
    final out = Uint8List(32);
    var x = v;
    for (var i = 31; i >= 0 && x > BigInt.zero; i--) {
      out[i] = (x & BigInt.from(0xff)).toInt();
      x = x >> 8;
    }
    return out;
  }

  static BigInt _word(Uint8List data, int index) {
    final start = index * 32;
    var v = BigInt.zero;
    for (var i = start; i < start + 32; i++) {
      v = (v << 8) | BigInt.from(data[i]);
    }
    return v;
  }

  Future<int> ruleCount() async {
    final out = await client.ethCall(to: trimmy, data: _ruleCountSel);
    return _word(out, 0).toInt();
  }

  /// Decodes the packed `Rule` struct. Field order here MUST match `Trimmy.Rule`; ABI encoding
  /// expands each packed field to its own 32-byte word, in declaration order.
  ///
  /// These indices shifted when `triggerValue` and `latchedPrice` widened to `uint128` for the
  /// M-1 fix and the slot layout was reordered. An index that is silently one out makes the keeper
  /// act on the wrong field — `active` reading `trigger`, say — so `keeper_decode_test` pins every
  /// one of them against a live `ruleAt` response.
  Future<Rule> ruleAt(int id) async {
    final out =
        await client.ethCall(to: trimmy, data: _withUint(_ruleAtSel, BigInt.from(id)));
    BigInt w(int i) => _word(out, i);
    return Rule(
      id: id,
      // fromAbiWord takes the 32-byte word directly and enforces that the upper 12 bytes are
      // zero, so a malformed word fails loudly instead of silently truncating to a wrong address.
      account: EthAddress.fromAbiWord(
        Uint8List.sublistView(out, 0, 32),
      ),
      epoch: w(1).toInt(),
      verb: w(4).toInt(),
      trigger: w(6).toInt(),
      active: w(7) != BigInt.zero,
      totalSellAmount: w(8),
      spent: w(10),
      nextEligibleAt: w(14),
      expiry: w(15),
      keeperFeeFlat: w(18),
      pendingShares: w(21),
      claimableAt: w(16),
    );
  }

  Future<int> epochOf(EthAddress account) async {
    final data = Uint8List(_epochOfSel.length + 32)..setAll(0, _epochOfSel);
    data.setAll(_epochOfSel.length + 12, hexToBytes(account.hex));
    final out = await client.ethCall(to: trimmy, data: data);
    return _word(out, 0).toInt();
  }

  /// Simulates at the current block. Returns null when it would succeed, or the revert reason.
  ///
  /// This is the whole cost-control story: a revert here is free.
  Future<String?> simulate(Uint8List calldata) async {
    try {
      await client.ethCall(to: trimmy, data: calldata, from: keeperAddress);
      return null;
    } on Object catch (e) {
      final text = e.toString();
      // Map the custom-error selector back to a name where we can, so logs are readable rather
      // than a bare 4-byte blob.
      for (final entry in _knownErrors.entries) {
        if (text.contains(entry.key)) return entry.value;
      }
      return text.length > 160 ? '${text.substring(0, 160)}…' : text;
    }
  }

  static final Map<String, String> _knownErrors = {
    bytesToHex(functionSelector('NotYetEligible(uint64)')): 'NotYetEligible',
    bytesToHex(functionSelector('TriggerNotMet(uint256,uint64)')): 'TriggerNotMet',
    bytesToHex(functionSelector('RuleInactive(uint256)')): 'RuleInactive',
    bytesToHex(functionSelector('RuleExpired(uint256)')): 'RuleExpired',
    bytesToHex(functionSelector('StaleEpoch(uint32,uint32)')): 'StaleEpoch',
    bytesToHex(functionSelector('Exhausted()')): 'Exhausted',
    bytesToHex(functionSelector('FloorBreached(uint256,uint256)')): 'FloorBreached',
    bytesToHex(functionSelector('FeedStale(uint64,uint256,uint64)')): 'FeedStale',
    bytesToHex(functionSelector('NotYetClaimable(uint64)')): 'NotYetClaimable',
    bytesToHex(functionSelector('NothingPending()')): 'NothingPending',
  };

  /// Builds, prices, signs and broadcasts. The SDK does everything except the signature.
  Future<String> send(Uint8List calldata, String privateKey) async {
    final request = await client.prepareTransaction(
      TransactionRequest(from: keeperAddress, to: trimmy, data: calldata),
    );
    final nonce = await client.getTransactionCount(keeperAddress);

    final result = await Process.run('cast', [
      'mktx',
      '--private-key',
      privateKey,
      '--rpc-url',
      FlareChain.coston2.rpcUrl,
      '--chain',
      '${FlareChain.coston2.chainId}',
      '--nonce',
      '$nonce',
      '--gas-limit',
      '${request.gas ?? BigInt.from(600000)}',
      trimmy.hex,
      bytesToHex(calldata),
    ]);
    if (result.exitCode != 0) {
      throw StateError('cast mktx failed: ${result.stderr}');
    }

    final raw = (result.stdout as String).trim();
    final hash = await client.sendRawTransaction(hexToBytes(raw));
    final receipt = await client.waitForReceipt(hash);
    if (!receipt.succeeded) {
      final why = await client.explainRevert(receipt);
      throw StateError('reverted after mining: ${why?.description ?? 'unknown'}');
    }
    return bytesToHex(hash);
  }

  /// One pass over every rule.
  Future<({int scanned, int executed, int skipped})> sweep(String? privateKey) async {
    final count = await ruleCount();
    var executed = 0;
    var skipped = 0;

    for (var i = 0; i < count; i++) {
      final rule = await ruleAt(i);

      // Epoch is checked here as well as on chain so a cancelAll'd rule is not even simulated.
      if (rule.active && rule.epoch != await epochOf(rule.account)) {
        skipped++;
        _log(i, 'skip', 'stale epoch (cancelAll)');
        continue;
      }

      if (rule.maybeClaimable) {
        final data = _withUint(_claimSel, BigInt.from(i));
        final why = await simulate(data);
        if (why == null) {
          if (privateKey != null) {
            final hash = await send(data, privateKey);
            _log(i, 'CLAIM', hash);
          } else {
            _log(i, 'CLAIM', 'would execute (dry run)');
          }
          executed++;
          continue;
        }
        _log(i, 'skip', 'claim: $why');
      }

      if (!rule.maybeExecutable) {
        skipped++;
        // Say why. A keeper that goes quiet is indistinguishable from a keeper that is broken.
        _log(i, 'skip', rule.exhausted ? 'exhausted' : 'inactive (cancelled)');
        continue;
      }

      final data = _withUint(_executeSel, BigInt.from(i));
      final why = await simulate(data);
      if (why != null) {
        skipped++;
        _log(i, 'skip', why);
        continue;
      }

      if (privateKey != null) {
        final hash = await send(data, privateKey);
        _log(i, 'EXEC', hash);
      } else {
        _log(i, 'EXEC', 'would execute (dry run) — fee ${rule.keeperFeeFlat}');
      }
      executed++;
    }

    return (scanned: count, executed: executed, skipped: skipped);
  }

  void _log(int id, String verb, String detail) {
    final ts = DateTime.now().toUtc().toIso8601String().substring(11, 19);
    stdout.writeln('$ts  rule $id  $verb  $detail');
  }
}

Future<void> main(List<String> args) async {
  final address = Platform.environment['TRIMMY_ADDRESS'];
  if (address == null) {
    stderr.writeln('TRIMMY_ADDRESS is required');
    exit(2);
  }
  // Prefer a dedicated keeper identity. The keeper must NOT be the user's account: if the two
  // are the same address the fee split is invisible in balances and the claim is unverifiable.
  final privateKey = Platform.environment['KEEPER_KEY'] ??
      Platform.environment['COSTON2_TEST_KEY'];
  final keeperAddr = Platform.environment['KEEPER_ADDRESS'] ??
      Platform.environment['COSTON2_TEST_ADDRESS'];
  final dryRun = args.contains('--dry-run') || privateKey == null;

  final once = args.contains('--once');
  final intervalIdx = args.indexOf('--interval');
  final interval = intervalIdx >= 0 && intervalIdx + 1 < args.length
      ? int.parse(args[intervalIdx + 1])
      : 15;

  final client = FlareClient(FlareChain.coston2);
  try {
    await client.verifyChainId();
    final keeper = Keeper(
      client,
      // Addresses arrive from the environment in whatever case the user pasted, so checksum
      // validation is off here; the value is our own configuration, not untrusted input.
      EthAddress.parse(address, validateChecksum: false),
      EthAddress.parse(
        keeperAddr ?? '0x0000000000000000000000000000000000000001',
        validateChecksum: false,
      ),
    );

    stdout.writeln('Trimmy keeper');
    stdout.writeln('  contract : $address');
    stdout.writeln('  mode     : ${dryRun ? 'DRY RUN (simulate only)' : 'LIVE'}');
    stdout.writeln('  interval : ${once ? 'single sweep' : '${interval}s'}');
    stdout.writeln('');

    do {
      final r = await keeper.sweep(dryRun ? null : privateKey);
      stdout.writeln(
        '-- swept ${r.scanned} rule(s): ${r.executed} executed, ${r.skipped} skipped',
      );
      if (!once) await Future<void>.delayed(Duration(seconds: interval));
    } while (!once);
  } finally {
    client.close();
  }
}
