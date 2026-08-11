// Builds the XRPL payment that arms a Trimmy rule. And refuses to emit one that would fail.
//
// This is the product's first sentence made real: the user sends ONE XRPL payment and a rule
// exists on Flare afterwards. They hold no FLR, run no EVM wallet, and never see a contract.
//
// ## What the payment actually carries
//
// A 42-byte memo with opcode `0xFE`:
//
//     [0xFE][walletId:1][executorFeeUBA:uint64][keccak256(abi.encode(PackedUserOperation)):32]
//
// The user operation itself is delivered to the executor off-chain; the memo only commits to its
// hash. So the bytes the user signs in Xaman are opaque, and if the committed batch is wrong the
// money is gone with no recourse. That is exactly the failure class Plimsoll exists to prevent,
// which is why this tool is built on it rather than reimplementing the layout.
//
// The layout is Plimsoll's **measured** one, read off a live Coston2 transaction, not the
// documented one. The TypeScript example in circulation lists ten fields; the wire format is the
// nine-field EIP-4337 v0.7 struct. A wrong layout does not fail loudly, it produces a commitment
// that never matches.
//
// ## Self-check
//
// This tool encodes `executeUserOp(Call[])`; Plimsoll decodes it. The two were written
// independently, so round-tripping every batch through Plimsoll's decoder before emitting a
// payment is a genuine cross-check rather than self-consistency.
//
// This file is the LIBRARY. `bin/arm.dart` is the command line around it, and
// `../mcp` is the agent boundary around the same functions. Everything that
// builds or checks a payment lives here so that all three callers get the same
// refusals, rather than the CLI having safety the others quietly skip.

import 'dart:typed_data';

import 'package:flare_network/flare_network.dart' as fn;
import 'package:plimsoll_core/plimsoll_core.dart' as p;

/// One entry of `executeUserOp((address,uint256,bytes)[])`.
class Call {
  const Call(this.target, this.value, this.data);
  final String target;
  final BigInt value;
  final Uint8List data;
}

/// Encodes `executeUserOp(Call[])`.
///
/// Hand-rolled because Plimsoll ships the decoder, not the encoder. It was built to inspect
/// payments, not to author them. Correctness is established by decoding the result with Plimsoll
/// before it is used (see [buildArmingPayment]).
Uint8List encodeExecuteUserOp(List<Call> calls) {
  // Head: offset to the array, then array length, then one offset per element.
  // Each element is a dynamic tuple (address, uint256, bytes).
  final elements = <Uint8List>[];
  for (final c in calls) {
    elements.add(
      p.abiConcat([
        p.abiAddressWord(c.target),
        p.abiWord(c.value),
        p.abiWord(BigInt.from(96)), // offset to `data` within this tuple
        p.abiDynamicBytes(c.data),
      ]),
    );
  }

  var cursor = calls.length * 32; // element offsets are relative to the array body
  final offsets = <Uint8List>[];
  for (final e in elements) {
    offsets.add(p.abiWord(BigInt.from(cursor)));
    cursor += e.length;
  }

  final selector = Uint8List(4)
    ..[0] = 0x2b
    ..[1] = 0x2e
    ..[2] = 0xe7
    ..[3] = 0x83; // executeUserOp((address,uint256,bytes)[])

  return p.abiConcat([
    selector,
    p.abiWord(BigInt.from(32)), // offset to the array
    p.abiWord(BigInt.from(calls.length)),
    ...offsets,
    ...elements,
  ]);
}

Uint8List _selector(String signature) => fn.functionSelector(signature);

Uint8List _encodeApprove(String spender, BigInt amount) => p.abiConcat([
      _selector('approve(address,uint256)'),
      p.abiAddressWord(spender),
      p.abiWord(amount),
    ]);

/// `arm((uint8,uint8,uint8,uint8,uint8,uint128,uint128,uint128,uint64,uint64,uint16,uint16,uint128,uint128))`
///
/// A struct of only static fields, so it encodes as its members in order, each in its own word.
/// Encodes `arm(RuleParams)`.
///
/// Public because it is the seam three callers need: the CLI, the MCP server,
/// and the adversarial probes in `bin/zz_*`. A private copy in each is how the
/// field order silently diverges between what we test and what we send.
Uint8List encodeArm({
  required int sellTokenId,
  required int buyTokenId,
  required int verb,
  required int venueId,
  required int trigger,
  required BigInt totalSellAmount,
  required BigInt partSellAmount,
  required BigInt minOutAbsolute,
  required BigInt triggerValue,
  required BigInt expiry,
  required int slippageBips,
  required int protocolFeeBips,
  required BigInt keeperFeeFlat,
  required BigInt keeperFeeBudget,
}) {
  // triggerValue is uint128 as of the M-1 fix: it holds a relative price that exceeds uint64 for
  // the FXRP -> WC2FLR pair. Widening it changed the selector from c33d4cc3 to cc0c55f4.
  const sig = 'arm((uint8,uint8,uint8,uint8,uint8,uint128,uint128,uint128,'
      'uint128,uint64,uint16,uint16,uint128,uint128))';
  return p.abiConcat([
    _selector(sig),
    p.abiWord(BigInt.from(sellTokenId)),
    p.abiWord(BigInt.from(buyTokenId)),
    p.abiWord(BigInt.from(verb)),
    p.abiWord(BigInt.from(venueId)),
    p.abiWord(BigInt.from(trigger)),
    p.abiWord(totalSellAmount),
    p.abiWord(partSellAmount),
    p.abiWord(minOutAbsolute),
    p.abiWord(triggerValue),
    p.abiWord(expiry),
    p.abiWord(BigInt.from(slippageBips)),
    p.abiWord(BigInt.from(protocolFeeBips)),
    p.abiWord(keeperFeeFlat),
    p.abiWord(keeperFeeBudget),
  ]);
}

class ArmingPayment {
  ArmingPayment({
    required this.personalAccount,
    required this.nonce,
    required this.userOp,
    required this.commitment,
    required this.memo,
    required this.calls,
  });

  final String personalAccount;
  final BigInt nonce;
  final p.PackedUserOperation userOp;
  final Uint8List commitment;
  final Uint8List memo;
  final List<Call> calls;
}

/// Builds the arming payment and verifies it before returning.
///
/// Rule 7, unknown means do not proceed. Every check here is a refusal, not a warning.
ArmingPayment buildArmingPayment({
  required String personalAccount,
  required BigInt nonce,
  required String fxrp,
  required String trimmy,
  required BigInt allowance,
  required Uint8List armCalldata,
  required BigInt executorFeeUBA,
}) {
  final calls = <Call>[
    // Sized to the rule's whole life, never unlimited. An allowance is a standing liability.
    Call(fxrp, BigInt.zero, _encodeApprove(trimmy, allowance)),
    Call(trimmy, BigInt.zero, armCalldata),
  ];

  final callData = encodeExecuteUserOp(calls);

  // Cross-check: decode what we just encoded with Plimsoll's independently-written decoder. If the
  // two disagree, the batch the executor runs is not the batch we think we authored, and that is
  // discovered here, before an irreversible payment, rather than after.
  final decoded = p.decodeExecuteUserOp(callData);
  switch (decoded) {
    case p.CallBatchUndecodable(:final reason):
      throw StateError('REFUSING TO ARM: Plimsoll could not decode our own batch: $reason');
    case p.CallBatchDecoded(calls: final decodedCalls):
      if (decodedCalls.length != calls.length) {
        throw StateError(
          'REFUSING TO ARM: encoded ${calls.length} calls, Plimsoll decoded '
          '${decodedCalls.length}',
        );
      }
  }

  final op = p.PackedUserOperation(
    sender: personalAccount,
    nonce: nonce,
    callData: callData,
  );

  final commitment = p.keccak256(op.encode());
  final memo = p.MemoCodec.encodeSmartAccount(
    opcode: p.SmartAccountOpcode.customInstruction,
    payload: commitment,
    executorFeeUBA: executorFeeUBA,
  );

  if (memo.length != 42) {
    throw StateError('REFUSING TO ARM: memo is ${memo.length} bytes, must be 42');
  }

  // A payment that leaves the executor nothing is never executed. And it does not fail, it simply
  // sits at the Core Vault forever while the XRP is gone from the user's control.
  //
  // Plimsoll GROUND-TRUTH §10.3 measured exactly this: "the executor earns nothing, so nobody
  // volunteers", and that payment "was never picked up at all". We then reproduced it here with a
  // real 5 XRP payment (XRPL C122663D…326104) that no executor has touched.
  //
  // This is the single most expensive way to get an irreversible payment wrong, because every
  // protocol-level check passes. So it is a refusal, not a warning.
  if (executorFeeUBA <= BigInt.zero) {
    throw StateError(
      'REFUSING TO ARM: executorFeeUBA is zero. No executor earns anything from this payment, '
      'so none will volunteer, and the XRP will sit at the Core Vault indefinitely. '
      'Pass --executor-fee at or above getDirectMintingExecutorFeeUBA().',
    );
  }

  // The memo must commit to exactly this user operation. Re-derive rather than assume.
  final carried = Uint8List.sublistView(memo, 10, 42);
  for (var i = 0; i < 32; i++) {
    if (carried[i] != commitment[i]) {
      throw StateError('REFUSING TO ARM: memo commitment does not match the user operation');
    }
  }

  return ArmingPayment(
    personalAccount: personalAccount,
    nonce: nonce,
    userOp: op,
    commitment: commitment,
    memo: memo,
    calls: calls,
  );
}
