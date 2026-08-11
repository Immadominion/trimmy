/// The tools an agent may call, and the two things none of them can do.
///
/// ## What this server is for
///
/// Agentic wallets all reach for the same shape: give the agent a bounded
/// permission instead of the keys. Botwallet does it with spending limits and
/// co-signing, Phantom with rules set in advance, Cobo with Pacts, MoonPay by
/// splitting the key with MPC. In every one of them the bound is enforced by
/// the vendor's infrastructure, so the agent's authority is exactly as durable
/// as that company's servers and intentions.
///
/// A Trimmy rule is the same bound enforced by a contract. The allowance is
/// exact rather than unlimited, the verb, venue and token pair are fixed at
/// deploy time, the budget and expiry are fixed at arming, and `epoch` cancels
/// everything in one write. This server exposes that as tools.
///
/// ## The two things it cannot do
///
/// **It cannot sign, and it cannot send.** `trimmy_compose_rule` returns a
/// payment for a human to sign in their own XRPL wallet. There is no signing
/// tool, no key, no broadcast path, and `test/readonly_test.dart` greps this
/// package for the ways one could be added.
///
/// **It cannot learn a private rule's threshold.** This is the subtle one and
/// it drove the design. For a `PRIVATE` rule the threshold is encrypted to the
/// enclave, which means whoever builds the payload holds it in plaintext for a
/// moment. If that were the agent, then "the agent never learns your price"
/// would be false. So `trimmy_compose_rule` **refuses a threshold argument for
/// private rules entirely** and returns the provisioning command for the human
/// to run themselves. The agent composes the shape of the mandate; the number
/// goes from the person to the enclave without passing through the model.
///
/// A tool that quietly accepted the threshold would be more convenient and
/// would make the product's best claim a lie.
///
/// ## A refusal is a successful call
///
/// MCP lets a tool return `isError: true`, and agent frameworks treat that as
/// *the tool broke*: they retry, or fall back, or route around it. A refusal is
/// none of those things. It is the tool working and the answer being no. So
/// `isError` is reserved for "this could not be answered", and a refusal
/// arrives as a successful result whose first line says not to send.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flare_network/flare_network.dart';
import 'package:trimmy_arming/arming.dart';
import 'package:trimmy_arming/xrpl_address.dart';

/// What a tool hands back.
final class ToolResult {
  const ToolResult({required this.text, this.structured, this.isError = false});

  /// Human and model readable. Leads with the decision, because a wall of
  /// detail above the answer is how a refusal gets skimmed past.
  final String text;

  /// The machine readable answer. Amounts are always decimal *strings* with an
  /// explicit unit, never JSON numbers: a double silently rounds, and a rounded
  /// amount cannot be reproduced.
  final Map<String, Object?>? structured;

  /// Reserved for "this could not be answered". Never used for a refusal.
  final bool isError;
}

/// One tool.
abstract interface class TrimmyTool {
  String get name;
  String get title;
  String get description;
  Map<String, Object?> get inputSchema;

  /// Whether answering requires reading Flare.
  ///
  /// Not decoration. The address check and the payment decoder are false, and a
  /// test proves it by handing the tool set a client factory that throws. A
  /// check that needs the network is a check that fails open when the network
  /// is down, and this one guards an irreversible payment.
  bool get readsChain;

  Future<ToolResult> call(Map<String, Object?> arguments);
}

/// Builds the tool set.
///
/// [clientFactory] is a factory rather than a client so a tool that does not
/// read the chain never causes a connection to exist.
List<TrimmyTool> trimmyTools({
  required FlareClient Function() clientFactory,
  String trimmy = defaultTrimmy,
}) =>
    [
      CheckAddressTool(),
      ListRulesTool(clientFactory, trimmy),
      DescribeRuleTool(clientFactory, trimmy),
      ComposeRuleTool(clientFactory, trimmy),
    ];

const defaultTrimmy = '0x19F81AAB43f7a26B0659754b70179aDcAF43ef7C';

// Verified with `cast sig`, not recalled. A wrong selector does not throw: it
// returns 0x, which decodes as zero and looks exactly like an empty answer.
const _selRuleCount = 'f6bcf633'; // ruleCount()
const _selRuleAt = '63a6fef6'; // ruleAt(uint256)
const _selTokenAt = 'bc13f2a4'; // tokenAt(uint8)
const _selPersonalAccount = 'd09318d4'; // getPersonalAccount(string)
const _selNonce = '2d0335ab'; // getNonce(address)
const _selByName = '82760fca'; // getContractAddressByName(string)
const _selAssetManagers = 'b87b82f0'; // getAssetManagers()
const _selExecutorFee = 'd561f156'; // getDirectMintingExecutorFeeUBA()

/// The canonical MasterAccountController: the only one in the registry's own
/// contract list, checked rather than assumed.
const _controller = '0x434936d47503353f06750Db1A444DBDC5F0AD37c';
const _registry = '0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019';
const _fxrp = '0x0b6A3645c240605887a5532109323A3E12273dc7';

/// ABI-encodes a single `string` argument: offset, length, padded bytes.
String _abiString(String v) {
  final b = utf8.encode(v);
  final padded = List<int>.from(b)..addAll(List.filled((32 - b.length % 32) % 32, 0));
  return _u256(32) +
      _u256(b.length) +
      padded.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
}

const _verbs = ['sell on a market', 'deposit into a vault', 'withdraw from a vault'];
const _triggers = ['price falls to', 'price rises to', 'on a schedule', 'a private price'];

String _u256(int n) => n.toRadixString(16).padLeft(64, '0');

BigInt _word(Uint8List b, int i) {
  var v = BigInt.zero;
  for (var k = i * 32; k < (i + 1) * 32; k++) {
    v = (v << 8) | BigInt.from(b[k]);
  }
  return v;
}

/// Decimal string, never a double. Rule 8.
String _amount(BigInt v, int decimals) {
  final s = v.toString().padLeft(decimals + 1, '0');
  final whole = s.substring(0, s.length - decimals);
  final frac = s.substring(s.length - decimals).replaceFirst(RegExp(r'0+$'), '');
  return frac.isEmpty ? whole : '$whole.$frac';
}

Uint8List _hexToBytes(String s) {
  final t = s.replaceFirst(RegExp('^0x'), '');
  return Uint8List.fromList([
    for (var i = 0; i < t.length; i += 2) int.parse(t.substring(i, i + 2), radix: 16),
  ]);
}

/// One decoded rule, in the units a reader thinks in.
final class _Rule {
  const _Rule(this.id, this.raw, this.sellDecimals, this.buyDecimals);

  final int id;
  final Uint8List raw;
  final int sellDecimals;
  final int buyDecimals;

  String get account => '0x${raw.sublist(12, 32).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  int get verb => _word(raw, 4).toInt();
  int get trigger => _word(raw, 6).toInt();
  bool get active => _word(raw, 7) == BigInt.one;
  BigInt get total => _word(raw, 8);
  BigInt get part => _word(raw, 9);
  BigInt get spent => _word(raw, 10);
  BigInt get triggerValue => _word(raw, 12);
  int get expiry => _word(raw, 15).toInt();
  BigInt get keeperFeeFlat => _word(raw, 18);
  BigInt get keeperFeePaid => _word(raw, 20);
  int get slippageBips => _word(raw, 22).toInt();

  String get status {
    if (spent >= total) return 'finished';
    if (!active) return 'cancelled';
    if (expiry != 0 && DateTime.now().millisecondsSinceEpoch ~/ 1000 > expiry) return 'expired';
    return 'watching';
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'status': status,
        'owner': account,
        'action': _verbs.elementAtOrNull(verb) ?? 'verb $verb',
        'trigger': _triggers.elementAtOrNull(trigger) ?? 'trigger $trigger',
        'amountEachTime': {'amount': _amount(part, sellDecimals), 'decimals': sellDecimals},
        'totalBudget': {'amount': _amount(total, sellDecimals), 'decimals': sellDecimals},
        'spent': {'amount': _amount(spent, sellDecimals), 'decimals': sellDecimals},
        'keeperFeePerRun': {'amount': _amount(keeperFeeFlat, buyDecimals), 'decimals': buyDecimals},
        'keeperFeePaid': {'amount': _amount(keeperFeePaid, buyDecimals), 'decimals': buyDecimals},
        // Deliberately absent for a private rule, because it is absent on chain.
        if (trigger != 3)
          'triggerValue': triggerValue.toString()
        else
          'triggerValue': 'not on chain: this rule is private',
        'slippageBips': verb == 0 ? slippageBips : null,
        'expiry': expiry == 0
            ? null
            : DateTime.fromMillisecondsSinceEpoch(expiry * 1000, isUtc: true).toIso8601String(),
      };
}

// ---------------------------------------------------------------------------
// trimmy_check_address
// ---------------------------------------------------------------------------

/// `trimmy_check_address`, the check that only works before the payment.
final class CheckAddressTool implements TrimmyTool {
  CheckAddressTool();

  @override
  String get name => 'trimmy_check_address';

  @override
  String get title => 'Check an XRPL address before it is used';

  @override
  bool get readsChain => false;

  @override
  String get description => '''
Verify an XRPL address against its own four byte checksum. Offline: no network,
no chain, no dependency on anything being up.

Call this before composing any rule, and never skip it. Flare derives a personal
account from the address STRING and the derivation never fails: one changed
character yields a different, entirely valid looking account that the sender does
not control. There is no on chain check that catches this, and the XRPL payment
cannot be recalled. The checksum is the only place a typo is detectable, and it
is only detectable before the payment is sent.''';

  @override
  Map<String, Object?> get inputSchema => {
        'type': 'object',
        'properties': {
          'address': {
            'type': 'string',
            'description': 'The XRPL classic address, for example rDE4JUm2jaue31VwidRXWuWzf5dQkUxcsB',
          },
        },
        'required': ['address'],
      };

  @override
  Future<ToolResult> call(Map<String, Object?> arguments) async {
    final address = arguments['address'];
    if (address is! String || address.isEmpty) {
      return const ToolResult(text: 'No address given.', isError: true);
    }
    try {
      final ok = validateXrplAddress(address);
      return ToolResult(
        text: 'OK. $ok passes its own checksum and is safe to use as the owner of a rule.',
        structured: {'address': ok, 'valid': true},
      );
    } on InvalidXrplAddress catch (e) {
      // A refusal, not an error. The tool worked; the answer is no.
      return ToolResult(
        text: 'DO NOT USE THIS ADDRESS. It fails its own checksum, so it is mistyped: ${e.toString()}\n\n'
            'Do not correct it yourself and do not proceed. Ask the person to copy it '
            'again from their wallet. Flare would accept this string and derive an '
            'account nobody controls, and the payment could not be recalled.',
        structured: {'address': address, 'valid': false},
      );
    }
  }
}

// ---------------------------------------------------------------------------
// trimmy_list_rules / trimmy_describe_rule
// ---------------------------------------------------------------------------

/// `eth_call`, through the SDK's own helper rather than the raw RPC.
///
/// `FlareClient` exposes no signing API at all, which is the property that
/// makes it safe to hand this process to an agent: there is no call to make.
Future<Uint8List> _ethCall(FlareClient client, String to, String data) =>
    client.ethCall(to: EthAddress.parse(to), data: _hexToBytes(data));

Future<_Rule> _readRule(FlareClient client, String trimmy, int id) async {
  final raw = await _ethCall(client, trimmy, _selRuleAt + _u256(id));
  if (raw.length != 26 * 32) {
    throw StateError(
      'ruleAt returned ${raw.length ~/ 32} words, expected 26. The Rule struct '
      'changed; this decoder must be updated before its output is trusted.',
    );
  }
  final sellId = _word(raw, 2).toInt();
  final buyId = _word(raw, 3).toInt();
  final sell = await _ethCall(client, trimmy, _selTokenAt + _u256(sellId));
  final buy = await _ethCall(client, trimmy, _selTokenAt + _u256(buyId));
  return _Rule(id, raw, _word(sell, 2).toInt(), _word(buy, 2).toInt());
}

/// `trimmy_list_rules`, every rule on the deployment.
final class ListRulesTool implements TrimmyTool {
  const ListRulesTool(this._client, this._trimmy);

  final FlareClient Function() _client;
  final String _trimmy;

  @override
  String get name => 'trimmy_list_rules';

  @override
  String get title => 'List every rule armed on Trimmy';

  @override
  bool get readsChain => true;

  @override
  String get description => '''
Read every rule currently armed on the Trimmy contract, with its status, its
remaining budget, and what it will do. Reads Flare Coston2 live.

Rules are public, so this returns all of them, not only a particular owner's.
A private rule's threshold price is not included, because it is not on chain:
only a commitment to it is.''';

  @override
  Map<String, Object?> get inputSchema => {'type': 'object', 'properties': <String, Object?>{}};

  @override
  Future<ToolResult> call(Map<String, Object?> arguments) async {
    final client = _client();
    try {
      final countRaw = await _ethCall(client, _trimmy, _selRuleCount);
      final count = _word(countRaw, 0).toInt();
      if (count == 0) {
        return const ToolResult(
          text: 'No rules are armed on this deployment yet.',
          structured: {'count': 0, 'rules': []},
        );
      }
      final rules = <Map<String, Object?>>[];
      final lines = <String>[];
      for (var i = 0; i < count; i++) {
        final r = await _readRule(client, _trimmy, i);
        rules.add(r.toJson());
        lines.add('  ${r.id}. [${r.status}] ${_verbs.elementAtOrNull(r.verb)}, '
            '${_amount(r.part, r.sellDecimals)} each time, '
            '${_triggers.elementAtOrNull(r.trigger)}');
      }
      return ToolResult(
        text: '$count rule${count == 1 ? '' : 's'} on $_trimmy (Flare Coston2):\n'
            '${lines.join('\n')}',
        structured: {'count': count, 'contract': _trimmy, 'rules': rules},
      );
    } finally {
      client.close();
    }
  }
}

/// `trimmy_describe_rule`, one rule, in full.
final class DescribeRuleTool implements TrimmyTool {
  const DescribeRuleTool(this._client, this._trimmy);

  final FlareClient Function() _client;
  final String _trimmy;

  @override
  String get name => 'trimmy_describe_rule';

  @override
  String get title => 'Describe one Trimmy rule in full';

  @override
  bool get readsChain => true;

  @override
  String get description => '''
Read one rule by id and return every field: what it does, what it has spent,
what it can still spend, its price bound, its keeper fee, and when it expires.

For a private rule the threshold price is absent, because the chain does not
hold it. Do not infer it, and do not ask the user to reveal it.''';

  @override
  Map<String, Object?> get inputSchema => {
        'type': 'object',
        'properties': {
          'ruleId': {'type': 'integer', 'minimum': 0, 'description': 'The rule id, as shown by trimmy_list_rules.'},
        },
        'required': ['ruleId'],
      };

  @override
  Future<ToolResult> call(Map<String, Object?> arguments) async {
    final id = arguments['ruleId'];
    if (id is! int || id < 0) {
      return const ToolResult(text: 'ruleId must be a non-negative integer.', isError: true);
    }
    final client = _client();
    try {
      final countRaw = await _ethCall(client, _trimmy, _selRuleCount);
      final count = _word(countRaw, 0).toInt();
      if (id >= count) {
        return ToolResult(
          text: 'There is no rule $id. The contract has $count rule${count == 1 ? '' : 's'}, '
              'numbered 0 to ${count - 1}.',
          structured: {'ruleId': id, 'exists': false, 'count': count},
        );
      }
      final r = await _readRule(client, _trimmy, id);
      return ToolResult(
        text: 'Rule $id is ${r.status}. It will ${_verbs.elementAtOrNull(r.verb)}, '
            '${_amount(r.part, r.sellDecimals)} at a time, ${_triggers.elementAtOrNull(r.trigger)}. '
            'It has spent ${_amount(r.spent, r.sellDecimals)} of '
            '${_amount(r.total, r.sellDecimals)}.'
            '${r.trigger == 3 ? '\n\nThis is a private rule. Its threshold price is not on chain '
                'and this tool cannot read it.' : ''}',
        structured: r.toJson(),
      );
    } finally {
      client.close();
    }
  }
}

// ---------------------------------------------------------------------------
// trimmy_compose_rule
// ---------------------------------------------------------------------------

/// `trimmy_compose_rule`, build a payment the human signs.
///
/// The one tool that produces something actionable, and the one that most needs
/// to be unable to act.
final class ComposeRuleTool implements TrimmyTool {
  const ComposeRuleTool(this._client, this._trimmy);

  final FlareClient Function() _client;
  final String _trimmy;

  @override
  String get name => 'trimmy_compose_rule';

  @override
  String get title => 'Compose the XRPL payment that arms a rule';

  @override
  bool get readsChain => true;

  @override
  String get description => '''
Describe the rule a person wants, and get back the exact XRPL payment that would
arm it: destination, amount, and the 42 byte memo, together with a plain reading
of what signing it authorises.

This tool cannot send the payment and holds no key. It returns fields for a human
to enter in their own XRPL wallet. Present them and stop; do not claim the rule
exists until the person confirms they sent it.

For a private rule, do NOT pass a threshold. This tool refuses one on purpose:
the threshold is encrypted to the enclave, so whoever builds that payload sees
it in plaintext, and that must not be the agent. It returns the provisioning
command for the person to run themselves, so the number goes from them to the
enclave without passing through this conversation.

Call trimmy_check_address on the owner's address first, always.''';

  @override
  Map<String, Object?> get inputSchema => {
        'type': 'object',
        'properties': {
          'xrplAddress': {'type': 'string', 'description': 'The owner\'s XRPL address. Check it first.'},
          'action': {
            'type': 'string',
            'enum': ['sell', 'deposit', 'withdraw'],
            'description': 'sell on a market, deposit into a vault, or withdraw from a vault.',
          },
          'trigger': {
            'type': 'string',
            'enum': ['price_below', 'price_above', 'schedule', 'private'],
          },
          'amountEachTime': {
            'type': 'string',
            'description': 'Decimal string in whole FXRP, for example "0.5". Never a number.',
          },
          'runs': {'type': 'integer', 'minimum': 1, 'description': 'How many times at most.'},
          'triggerValue': {
            'type': 'string',
            'description':
                'For price triggers, the threshold as a decimal string. For schedule, the interval '
                'in seconds. MUST BE OMITTED for a private rule, and passing it there is refused.',
          },
        },
        'required': ['xrplAddress', 'action', 'trigger', 'amountEachTime', 'runs'],
      };

  @override
  Future<ToolResult> call(Map<String, Object?> arguments) async {
    final address = arguments['xrplAddress'];
    if (address is! String) {
      return const ToolResult(text: 'xrplAddress is required.', isError: true);
    }
    // The checksum gate is repeated here rather than trusted to have happened.
    // A tool that assumes an earlier tool was called is a tool that fails open.
    try {
      validateXrplAddress(address);
    } on InvalidXrplAddress catch (e) {
      return ToolResult(
        text: 'REFUSED. That XRPL address fails its own checksum: $e\n\n'
            'Nothing was composed. Ask the person to copy the address again.',
        structured: {'composed': false, 'reason': 'address_checksum'},
      );
    }

    final trigger = arguments['trigger'];
    if (trigger == 'private' && arguments['triggerValue'] != null) {
      // The refusal that makes the product's best claim true.
      return const ToolResult(
        text: 'REFUSED, and this refusal is deliberate.\n\n'
            'You passed a threshold for a private rule. The point of a private rule is that '
            'the number never reaches anything except the enclave, and it cannot do that if it '
            'passes through this conversation first.\n\n'
            'Compose the rule again without triggerValue. This tool will return the command '
            'the person runs themselves to send the threshold straight to the enclave.',
        structured: {'composed': false, 'reason': 'threshold_must_not_reach_the_agent'},
      );
    }

    final action = arguments['action'] as String?;
    final amountEach = arguments['amountEachTime'] as String?;
    final runs = arguments['runs'];
    if (action == null || amountEach == null || runs is! int || runs < 1) {
      return const ToolResult(
        text: 'action, amountEachTime and runs are all required.',
        isError: true,
      );
    }

    final BigInt part;
    try {
      part = _parseUnits(amountEach, 6);
    } on FormatException catch (e) {
      return ToolResult(text: 'amountEachTime is not a decimal amount: $e', isError: true);
    }
    if (part <= BigInt.zero) {
      return const ToolResult(text: 'amountEachTime must be greater than zero.', isError: true);
    }

    final client = _client();
    try {
      // Everything below is read live rather than assumed. The account is
      // DERIVED from the address string, the nonce moves, and the executor fee
      // is a governance parameter: a payment built on a stale copy of any of
      // the three is a payment that fails after it can no longer be recalled.
      final paRaw = await _ethCall(client, _controller, _selPersonalAccount + _abiString(address));
      final personalAccount =
          '0x${paRaw.sublist(paRaw.length - 20).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
      if (BigInt.parse(personalAccount.substring(2), radix: 16) == BigInt.zero) {
        return ToolResult(
          text: 'REFUSED. Flare has no account for $address yet, so an allowance armed against '
              'it would land nowhere and could not be recovered.',
          structured: {'composed': false, 'reason': 'no_personal_account'},
        );
      }

      final nonceRaw = await _ethCall(client, _controller, _selNonce + _u256(0).substring(0, 24) +
          personalAccount.substring(2));
      final nonce = _word(nonceRaw, 0);

      final feeUBA = await _readExecutorFee(client);
      if (feeUBA <= BigInt.zero) {
        return const ToolResult(
          text: 'REFUSED. The executor fee read as zero, and a payment that pays the executor '
              'nothing is never picked up: it sits at the Core Vault while the XRP is gone.',
          structured: {'composed': false, 'reason': 'executor_fee_zero'},
        );
      }

      final total = part * BigInt.from(runs);
      final keeperFee = _keeperFeeUBA;
      final allowance = total + keeperFee * BigInt.from(runs);

      // A private rule is composed with triggerValue 0 on chain. The number
      // itself never enters this process: see the refusal above.
      final isPrivate = trigger == 'private';
      final triggerIndex = switch (trigger) {
        'price_below' => 0,
        'price_above' => 1,
        'schedule' => 2,
        _ => 3,
      };
      final verbIndex = switch (action) {
        'sell' => 0,
        'deposit' => 1,
        _ => 2,
      };
      final BigInt triggerValue;
      if (isPrivate) {
        triggerValue = BigInt.zero;
      } else {
        final raw = arguments['triggerValue'];
        if (raw is! String) {
          return const ToolResult(
            text: 'triggerValue is required for a price or schedule rule.',
            isError: true,
          );
        }
        triggerValue = triggerIndex == 2 ? BigInt.parse(raw) : _parseUnits(raw, 18);
      }

      final expiry = BigInt.from(
        DateTime.now().toUtc().add(const Duration(days: 7)).millisecondsSinceEpoch ~/ 1000,
      );

      final armCalldata = encodeArm(
        sellTokenId: 0,
        buyTokenId: verbIndex == 0 ? 1 : 0,
        verb: verbIndex,
        venueId: verbIndex == 0 ? 0 : 1,
        trigger: triggerIndex,
        totalSellAmount: total,
        partSellAmount: part,
        minOutAbsolute: verbIndex == 1 ? part * BigInt.from(90) ~/ BigInt.from(100) : BigInt.zero,
        triggerValue: triggerValue,
        expiry: expiry,
        slippageBips: verbIndex == 0 ? 50 : 0,
        protocolFeeBips: 0,
        keeperFeeFlat: keeperFee,
        keeperFeeBudget: keeperFee * BigInt.from(runs),
      );

      // buildArmingPayment is the SAME function the command line uses, and it
      // refuses rather than warns. The agent boundary must not have weaker
      // safety than the CLI.
      final payment = buildArmingPayment(
        personalAccount: personalAccount,
        nonce: nonce,
        fxrp: _fxrp,
        trimmy: _trimmy,
        allowance: allowance,
        armCalldata: armCalldata,
        executorFeeUBA: feeUBA,
      );

      final memoHex = payment.memo.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
      final send = _amount(total + feeUBA + _mintingFeeUBA, 6);

      return ToolResult(
        text: 'Composed. Nothing has been sent, and this server cannot send it.\n\n'
            'The person signs ONE XRPL payment, in their own wallet, with these three fields:\n\n'
            '  Destination : the FAssets Core Vault for Coston2\n'
            '  Amount      : $send XRP\n'
            '  Memo (hex)  : $memoHex\n\n'
            'Do not add a destination tag. A registered tag overrides the memo and credits the '
            'tag holder instead.\n\n'
            'What signing it authorises, and nothing else:\n'
            '  1. Allow Trimmy to move at most ${_amount(allowance, 6)} FXRP. Exact, not unlimited.\n'
            '  2. Arm a rule: ${_verbs[verbIndex]}, ${_amount(part, 6)} FXRP at a time, '
            'up to $runs time${runs == 1 ? '' : 's'}, ${_triggers[triggerIndex]}'
            '${isPrivate ? ' held inside the enclave' : ''}.\n\n'
            '${isPrivate ? _privateFollowUp : ''}'
            'The rule does not exist until the payment settles and Flare attests it. Say so, and '
            'do not report the rule as armed before the person confirms they sent it.',
        structured: {
          'composed': true,
          'sendable': false,
          'personalAccount': personalAccount,
          'nonce': nonce.toString(),
          'amountToSend': {'amount': send, 'unit': 'XRP'},
          'memoHex': memoHex,
          'allowance': {'amount': _amount(allowance, 6), 'unit': 'FXRP'},
          'commitment':
              '0x${payment.commitment.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}',
          'isPrivate': isPrivate,
          if (isPrivate) 'thresholdHandledBy': 'the person, directly to the enclave',
        },
      );
    } on StateError catch (e) {
      // buildArmingPayment refuses by throwing. A refusal is an answer.
      return ToolResult(
        text: 'REFUSED. $e\n\nNothing was composed and nothing should be sent.',
        structured: {'composed': false, 'reason': 'builder_refused'},
      );
    } finally {
      client.close();
    }
  }
}

/// The keeper fee, in buy-token units, sized at roughly twice the measured cost
/// of one execution on Coston2. Testnet only: Flare mainnet has a different gas
/// market and this number has not been measured there.
final _keeperFeeUBA = BigInt.from(9400);

/// The FAssets minting fee floor. Measured, and the reason it is not inferred:
/// anything from the minting fee to the sum of both fees delivers exactly zero,
/// silently, in a transaction that succeeds.
final _mintingFeeUBA = BigInt.from(100000);

const _privateFollowUp =
    'Because this is a private rule, the threshold price is NOT in the payment above and is '
    'not known to this conversation. After the rule is armed, the person runs this themselves '
    'so the number goes straight to the enclave:\n\n'
    '  cd fcc/extension/tools && go run ./cmd/trimmy-private --rule <id> --threshold <price>\n\n';

/// Reads the live executor fee: registry, then controller, then asset manager.
Future<BigInt> _readExecutorFee(FlareClient client) async {
  final controllerRaw =
      await _ethCall(client, _registry, _selByName + _abiString('AssetManagerController'));
  final controller =
      '0x${controllerRaw.sublist(controllerRaw.length - 20).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  final managers = await _ethCall(client, controller, _selAssetManagers);
  final first =
      '0x${managers.sublist(64 + 12, 64 + 32).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  final raw = await _ethCall(client, first, _selExecutorFee);
  return _word(raw, 0);
}

/// Parses a decimal string into base units. Never accepts a double: a rounded
/// amount cannot be reproduced, and this one becomes an irreversible payment.
BigInt _parseUnits(String value, int decimals) {
  final m = RegExp(r'^(\d+)(?:\.(\d+))?$').firstMatch(value.trim());
  if (m == null) throw FormatException('expected a decimal string, got "$value"');
  final frac = (m.group(2) ?? '').padRight(decimals, '0');
  if (frac.length > decimals) {
    throw FormatException('$value has more than $decimals decimal places');
  }
  return BigInt.parse(m.group(1)! + frac);
}

/// Pretty JSON for the text half of a result, when a tool wants to show one.
String prettyJson(Object? value) => const JsonEncoder.withIndent('  ').convert(value);
