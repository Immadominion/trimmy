// Builds the XRPL arming payment in the browser.
//
// This is a second, independent implementation of what `arming/bin/arm.dart` does. That is
// deliberate and it is also a hazard: two encoders that disagree produce a memo committing to a
// batch nobody intended, and an XRPL payment is irreversible. So `../test/arming.test.mjs` pins
// this file against a memo `arm.dart` actually produced for a payment that settled on chain, if
// the two ever diverge, the test fails rather than a user's money going somewhere unintended.
//
// Everything here is byte-exact with Plimsoll's MEASURED layout, not the documented one: the wire
// format is the nine-field EIP-4337 v0.7 `PackedUserOperation`, where the widely-circulated
// TypeScript example lists ten. A wrong layout does not fail loudly. It produces a commitment that
// never matches, and the payment sits at the Core Vault forever.

import { keccak256 } from './keccak.js';

// ---------------------------------------------------------------------------------------------
// bytes
// ---------------------------------------------------------------------------------------------

export const toHex = (b) => [...b].map((x) => x.toString(16).padStart(2, '0')).join('');

export function fromHex(s) {
  const clean = s.trim().replace(/^0x/i, '').replace(/\s+/g, '');
  if (clean.length % 2 !== 0) throw new Error('hex must have an even number of digits');
  if (!/^[0-9a-fA-F]*$/.test(clean)) throw new Error('not hex');
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(clean.substr(i * 2, 2), 16);
  return out;
}

export function concat(parts) {
  const total = parts.reduce((n, p) => n + p.length, 0);
  const out = new Uint8Array(total);
  let off = 0;
  for (const p of parts) { out.set(p, off); off += p.length; }
  return out;
}

// ---------------------------------------------------------------------------------------------
// ABI
// ---------------------------------------------------------------------------------------------

/** One 32-byte big-endian word. Negative or oversized values are a bug, not a wrap. */
export function abiWord(value) {
  let v = BigInt(value);
  if (v < 0n) throw new Error('abiWord: negative');
  if (v >= (1n << 256n)) throw new Error('abiWord: exceeds 256 bits');
  const out = new Uint8Array(32);
  for (let i = 31; i >= 0 && v > 0n; i--) { out[i] = Number(v & 0xffn); v >>= 8n; }
  return out;
}

/** An address, right-aligned in a word. */
export function abiAddressWord(addr) {
  const b = fromHex(addr);
  if (b.length !== 20) throw new Error(`address must be 20 bytes, got ${b.length}`);
  const out = new Uint8Array(32);
  out.set(b, 12);
  return out;
}

/** A dynamic `bytes`: length word, then the data padded up to a multiple of 32. */
export function abiDynamicBytes(data) {
  const padded = Math.ceil(data.length / 32) * 32;
  const out = new Uint8Array(32 + padded);
  out.set(abiWord(BigInt(data.length)), 0);
  out.set(data, 32);
  return out;
}

export const selector = (signature) =>
  keccak256(new TextEncoder().encode(signature)).slice(0, 4);

// ---------------------------------------------------------------------------------------------
// calls
// ---------------------------------------------------------------------------------------------

/** `approve(address,uint256)` */
export const encodeApprove = (spender, amount) =>
  concat([selector('approve(address,uint256)'), abiAddressWord(spender), abiWord(amount)]);

/**
 * `arm((uint8,uint8,uint8,uint8,uint8,uint128,uint128,uint128,uint128,uint64,uint16,uint16,uint128,uint128))`
 *
 * A struct of only static fields, so it encodes as its members in order, one word each.
 * `triggerValue` is uint128 as of the M-1 fix, it holds a relative price that exceeds uint64 for
 * the FXRP→WC2FLR pair, and widening it changed the selector from c33d4cc3 to cc0c55f4.
 */
export function encodeArm(r) {
  const sig =
    'arm((uint8,uint8,uint8,uint8,uint8,uint128,uint128,uint128,' +
    'uint128,uint64,uint16,uint16,uint128,uint128))';
  return concat([
    selector(sig),
    abiWord(r.sellTokenId), abiWord(r.buyTokenId), abiWord(r.verb),
    abiWord(r.venueId), abiWord(r.trigger),
    abiWord(r.totalSellAmount), abiWord(r.partSellAmount), abiWord(r.minOutAbsolute),
    abiWord(r.triggerValue), abiWord(r.expiry),
    abiWord(r.slippageBips), abiWord(r.protocolFeeBips),
    abiWord(r.keeperFeeFlat), abiWord(r.keeperFeeBudget),
  ]);
}

/**
 * `executeUserOp((address,uint256,bytes)[])`
 *
 * Each element is a dynamic tuple, so the array body is a run of element offsets, relative to the
 * start of the array body, not to the start of the calldata, followed by the elements themselves.
 */
export function encodeExecuteUserOp(calls) {
  const elements = calls.map((c) => concat([
    abiAddressWord(c.target),
    abiWord(c.value ?? 0n),
    abiWord(96n),                 // offset to `data` within this tuple
    abiDynamicBytes(c.data),
  ]));

  let cursor = calls.length * 32;
  const offsets = [];
  for (const e of elements) { offsets.push(abiWord(BigInt(cursor))); cursor += e.length; }

  // Measured selector for this signature; `selector()` reproduces it, and the test asserts they
  // agree so a typo in the signature string cannot pass silently.
  return concat([
    selector('executeUserOp((address,uint256,bytes)[])'),
    abiWord(32n),                 // offset to the array
    abiWord(BigInt(calls.length)),
    ...offsets,
    ...elements,
  ]);
}

// ---------------------------------------------------------------------------------------------
// PackedUserOperation (EIP-4337 v0.7, nine fields)
// ---------------------------------------------------------------------------------------------

const HEAD_SIZE = 32 * 9;

/**
 * `abi.encode(userOp)`, the exact bytes an executor passes as `_data`.
 *
 * A single dynamic tuple is encoded behind a leading offset word, so the output starts with 0x20.
 * Omitting that word produces a different hash and a mint that reverts with
 * `CustomInstructionHashMismatch`.
 */
export function encodeUserOp({ sender, nonce, callData }) {
  const empty = new Uint8Array(0);
  const tails = [
    abiDynamicBytes(empty),      // initCode
    abiDynamicBytes(callData),
    abiDynamicBytes(empty),      // paymasterAndData
    abiDynamicBytes(empty),      // signature
  ];

  let cursor = HEAD_SIZE;
  const ptr = [];
  for (const t of tails) { ptr.push(BigInt(cursor)); cursor += t.length; }

  return concat([
    abiWord(32n),                // offset to the struct itself
    abiAddressWord(sender),
    abiWord(nonce),
    abiWord(ptr[0]),             // initCode
    abiWord(ptr[1]),             // callData
    new Uint8Array(32),          // accountGasLimits
    abiWord(0n),                 // preVerificationGas
    new Uint8Array(32),          // gasFees
    abiWord(ptr[2]),             // paymasterAndData
    abiWord(ptr[3]),             // signature
    ...tails,
  ]);
}

// ---------------------------------------------------------------------------------------------
// memo
// ---------------------------------------------------------------------------------------------

/** `[0xFE][walletId:1][executorFeeUBA:uint64][commitment:32]`, 42 bytes exactly. */
export function encodeMemo({ commitment, executorFeeUBA, walletId = 0 }) {
  if (commitment.length !== 32) throw new Error('commitment must be 32 bytes');
  const fee = BigInt(executorFeeUBA);
  if (fee < 0n || fee >= (1n << 64n)) throw new Error('executorFeeUBA must fit uint64');
  const out = new Uint8Array(42);
  out[0] = 0xfe;
  out[1] = walletId;
  let f = fee;
  for (let i = 9; i >= 2 && f > 0n; i--) { out[i] = Number(f & 0xffn); f >>= 8n; }
  out.set(commitment, 10);
  return out;
}

// ---------------------------------------------------------------------------------------------
// the whole payment
// ---------------------------------------------------------------------------------------------

export class Refusal extends Error {}

/**
 * Builds the arming payment, refusing rather than warning.
 *
 * The `executorFeeUBA > 0` check is the expensive one. A payment that leaves the executor nothing
 * is never executed, and it does not fail, it sits at the Core Vault while the XRP is gone from
 * the user's control. Every protocol-level check passes. We reproduced it with a real 5 XRP payment
 * that no executor ever touched.
 */
export function buildArmingPayment({
  personalAccount, nonce, fxrp, trimmy, allowance, rule, executorFeeUBA,
}) {
  if (BigInt(executorFeeUBA) <= 0n) {
    throw new Refusal(
      'executorFeeUBA is zero. No executor earns anything from this payment, so none will ' +
      'volunteer, and the XRP will sit at the Core Vault indefinitely.',
    );
  }

  const calls = [
    // Sized to the rule's whole life, never unlimited. An allowance is a standing liability.
    { target: fxrp, value: 0n, data: encodeApprove(trimmy, allowance) },
    { target: trimmy, value: 0n, data: encodeArm(rule) },
  ];

  const callData = encodeExecuteUserOp(calls);
  const userOp = encodeUserOp({ sender: personalAccount, nonce, callData });
  const commitment = keccak256(userOp);
  const memo = encodeMemo({ commitment, executorFeeUBA });

  if (memo.length !== 42) throw new Refusal(`memo is ${memo.length} bytes, must be 42`);

  // Re-derive rather than assume: the memo must commit to exactly this user operation.
  for (let i = 0; i < 32; i++) {
    if (memo[10 + i] !== commitment[i]) {
      throw new Refusal('memo commitment does not match the user operation');
    }
  }

  return { calls, callData, userOp, commitment, memo };
}
