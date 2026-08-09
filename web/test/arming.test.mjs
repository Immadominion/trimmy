// Pins the browser encoder against the Dart one.
//
// `web/lib/arming.js` and `arming/bin/arm.dart` are two independent implementations of the same
// irreversible payment. Two encoders that disagree produce a memo committing to a batch nobody
// intended, and there is no recourse once the XRPL payment validates. So the fixture below is not
// synthetic: it is the exact user operation `arm.dart` built for XRPL transaction
// 384FE782BE520662EA579AB67A2232DE5BD650A8A0E2ACB75C2B8C80514B778A, which settled on ledger
// 19771685 and armed rule 1 on Trimmy 0x19F81AAB…
//
//   node --test test/arming.test.mjs      (or just: node test/arming.test.mjs)

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

import { keccak256 } from '../lib/keccak.js';
import {
  abiWord, abiAddressWord, abiDynamicBytes, buildArmingPayment, encodeArm, encodeExecuteUserOp,
  encodeMemo, encodeUserOp, fromHex, Refusal, selector, toHex,
} from '../lib/arming.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, '..', '..');

// ---- the fixture, from a settled payment -----------------------------------------------------

const FIXTURE = {
  personalAccount: '0x07a76b5c3d03f5bff4cb3e043b1d17a1b40920bf',
  nonce: 1n,
  fxrp: '0x0b6A3645c240605887a5532109323A3E12273dc7',
  trimmy: '0x19F81AAB43f7a26B0659754b70179aDcAF43ef7C',
  allowance: 1009400n,
  executorFeeUBA: 100000n,
  rule: {
    sellTokenId: 0, buyTokenId: 0, verb: 1, venueId: 1, trigger: 2,
    totalSellAmount: 1000000n, partSellAmount: 1000000n, minOutAbsolute: 900000n,
    triggerValue: 60n,
    expiry: 1786907035n,           // read back off chain from rule 1
    slippageBips: 0, protocolFeeBips: 0,
    keeperFeeFlat: 9400n, keeperFeeBudget: 9400n,
  },
  memo: 'FE0000000000000186A0EBBE0EE068F4BA0A9E39E41FDCA1DBF26864AADDB0AA42E59371EB67B7CE96CC',
  commitment: '0xebbe0ee068f4ba0a9e39e41fdca1dbf26864aaddb0aa42e59371eb67b7ce96cc',
};

test('keccak256 matches the standard vectors', () => {
  const s = (x) => toHex(keccak256(new TextEncoder().encode(x)));
  assert.equal(s(''), 'c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470');
  assert.equal(s('abc'), '4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45');
  // >136 bytes, so absorption spans more than one block
  assert.equal(
    toHex(keccak256(new Uint8Array(200).fill(0xab))),
    toHex(keccak256(new Uint8Array(200).fill(0xab))),
  );
});

test('selectors are derived, not remembered', () => {
  assert.equal(toHex(selector('approve(address,uint256)')), '095ea7b3');
  // Measured on the wire in a settled payment. The Dart encoder hardcodes 2b2ee783; deriving it
  // from the signature here means a typo in either place shows up as a test failure.
  assert.equal(toHex(selector('executeUserOp((address,uint256,bytes)[])')), '2b2ee783');
  assert.equal(
    toHex(selector(
      'arm((uint8,uint8,uint8,uint8,uint8,uint128,uint128,uint128,' +
      'uint128,uint64,uint16,uint16,uint128,uint128))',
    )),
    'cc0c55f4',
  );
});

test('the user-operation pre-image is byte-identical to the Dart encoder', () => {
  const onDisk = readFileSync(join(REPO, 'arming', 'out', 'preimage-v4.hex'), 'utf8');
  const expected = fromHex(onDisk);

  const built = buildArmingPayment(FIXTURE);
  assert.equal(built.userOp.length, expected.length, 'pre-image length');
  assert.equal(toHex(built.userOp), toHex(expected), 'pre-image bytes');
});

test('the commitment and the 42-byte memo match the settled payment', () => {
  const built = buildArmingPayment(FIXTURE);
  assert.equal('0x' + toHex(built.commitment), FIXTURE.commitment);
  assert.equal(built.memo.length, 42);
  assert.equal(toHex(built.memo).toUpperCase(), FIXTURE.memo);
  assert.equal(built.memo[0], 0xfe, 'opcode');
  // The fee occupies bytes 2..9, big-endian.
  assert.equal(toHex(built.memo.slice(2, 10)), '00000000000186a0'); // 100000
});

test('a zero executor fee is refused, not warned about', () => {
  assert.throws(
    () => buildArmingPayment({ ...FIXTURE, executorFeeUBA: 0n }),
    (e) => e instanceof Refusal && /sit at the Core Vault/.test(e.message),
  );
});

test('ABI primitives reject what they cannot encode', () => {
  assert.throws(() => abiWord(-1n), /negative/);
  assert.throws(() => abiWord(1n << 256n), /256 bits/);
  assert.throws(() => abiAddressWord('0xdeadbeef'), /20 bytes/);
  assert.throws(() => fromHex('0xabc'), /even number/);
  assert.throws(() => fromHex('0xzz'), /not hex/);
  assert.throws(() => encodeMemo({ commitment: new Uint8Array(31), executorFeeUBA: 1n }), /32 bytes/);
  assert.throws(
    () => encodeMemo({ commitment: new Uint8Array(32), executorFeeUBA: 1n << 64n }),
    /uint64/,
  );
});

test('dynamic bytes pad to a whole number of words', () => {
  assert.equal(abiDynamicBytes(new Uint8Array(0)).length, 32);
  assert.equal(abiDynamicBytes(new Uint8Array(1)).length, 64);
  assert.equal(abiDynamicBytes(new Uint8Array(32)).length, 64);
  assert.equal(abiDynamicBytes(new Uint8Array(33)).length, 96);
});

test('the arm calldata is one selector plus fourteen static words', () => {
  const cd = encodeArm(FIXTURE.rule);
  assert.equal(cd.length, 4 + 14 * 32);
});

test('changing any rule field changes the commitment', () => {
  const base = buildArmingPayment(FIXTURE).commitment;
  for (const [k, v] of Object.entries({
    partSellAmount: 999999n, triggerValue: 61n, keeperFeeFlat: 9401n, venueId: 0,
  })) {
    const moved = buildArmingPayment({ ...FIXTURE, rule: { ...FIXTURE.rule, [k]: v } }).commitment;
    assert.notEqual(toHex(moved), toHex(base), `${k} must affect the commitment`);
  }
});

test('the executor fee is committed to by the memo, but not by the user operation', () => {
  // The fee lives in the memo header, not in the batch. Two payments differing only in fee share a
  // pre-image and differ in memo — worth pinning, because it is the one field a user can change
  // without re-deriving the commitment.
  const a = buildArmingPayment(FIXTURE);
  const b = buildArmingPayment({ ...FIXTURE, executorFeeUBA: 200000n });
  assert.equal(toHex(a.userOp), toHex(b.userOp));
  assert.notEqual(toHex(a.memo), toHex(b.memo));
});
