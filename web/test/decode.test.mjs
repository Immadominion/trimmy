import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { decodeArmingPayment } from '../lib/decode.js';
import { fromHex, buildArmingPayment } from '../lib/arming.js';

const F = {
  personalAccount: '0x07a76b5c3d03f5bff4cb3e043b1d17a1b40920bf', nonce: 1n,
  fxrp: '0x0b6A3645c240605887a5532109323A3E12273dc7',
  trimmy: '0x19F81AAB43f7a26B0659754b70179aDcAF43ef7C',
  allowance: 1009400n, executorFeeUBA: 100000n,
  rule: { sellTokenId:0, buyTokenId:0, verb:1, venueId:1, trigger:2,
    totalSellAmount:1000000n, partSellAmount:1000000n, minOutAbsolute:900000n,
    triggerValue:60n, expiry:1786907035n, slippageBips:0, protocolFeeBips:0,
    keeperFeeFlat:9400n, keeperFeeBudget:9400n },
};

test('recovers the settled payment from its bytes alone', () => {
  const b = buildArmingPayment(F);
  const d = decodeArmingPayment(b.memo, b.userOp, { trimmy: F.trimmy });
  assert.equal(d.problems.length, 0, JSON.stringify(d.problems));
  assert.equal(d.matches, true);
  assert.match(d.html, /1 XRP/);
  assert.match(d.html, /deposit it into the yield vault/);
  // This fixture is a REAL settled payment with total == part, so ceilDiv gives exactly one run.
  // This assertion used to demand "every minute" — it was pinning the bug in place: the rule can
  // only ever fire once, and saying otherwise is the one thing this decoder exists to prevent.
  assert.match(d.html, /once, as soon as somebody runs it/);
  assert.doesNotMatch(d.html, /every minute/);
  assert.match(d.html, /1\.0094 XRP/);          // the allowance, decoded not restated
  assert.match(d.html, /0\.0094 XRP per run/);  // keeper fee
});

test('a tampered pre-image is caught', () => {
  const b = buildArmingPayment(F);
  const bad = Uint8Array.from(b.userOp);
  bad[bad.length - 40] ^= 0x01;                 // flip one bit inside the arm calldata
  const d = decodeArmingPayment(b.memo, bad);
  assert.equal(d.matches, false);
  assert.ok(d.problems.some(p => /does not commit/.test(p)));
});

test('a zero executor fee is reported as fatal', () => {
  const b = buildArmingPayment(F);
  const memo = Uint8Array.from(b.memo);
  memo.fill(0, 2, 10);
  const d = decodeArmingPayment(memo, b.userOp);
  assert.ok(d.problems.some(p => /executor fee is zero/.test(p)));
});

test('a PRIVATE rule publishes no threshold and says so', () => {
  const b = buildArmingPayment({ ...F, rule: { ...F.rule, verb:0, venueId:0, buyTokenId:1,
    trigger:3, triggerValue:0n, slippageBips:50 } });
  const d = decodeArmingPayment(b.memo, b.userOp);
  assert.match(d.html, /secret price held only inside a secure enclave/);
  assert.match(d.html, /Nothing on the public ledger reveals your price/);
});

test('an unrecognised call is flagged rather than glossed over', () => {
  const b = buildArmingPayment(F);
  const bad = Uint8Array.from(b.userOp);
  // Corrupt the arm() selector; the decoder must refuse to describe it.
  const i = bad.findIndex((_, j) =>
    bad[j]===0xcc && bad[j+1]===0x0c && bad[j+2]===0x55 && bad[j+3]===0xf4);
  assert.ok(i > 0, 'selector found');
  bad[i] = 0xde; bad[i+1] = 0xad;
  const d = decodeArmingPayment(b.memo, bad);
  assert.match(d.html, /Unrecognised call/);
  assert.match(d.html, /Do not send it/);
});

test('a spender that is not Trimmy is called out, not labelled', async () => {
  const { decodeArmingPayment } = await import('../lib/decode.js');
  const { buildArmingPayment } = await import('../lib/arming.js');
  const F2 = { ...F, trimmy: '0x000000000000000000000000000000000000dEaD' };
  const b = buildArmingPayment(F2);
  const d = decodeArmingPayment(b.memo, b.userOp, { trimmy: F.trimmy });
  assert.match(d.html, /an unrecognised contract/);
  assert.match(d.html, /Do not send this/);

  const good = buildArmingPayment(F);
  const dg = decodeArmingPayment(good.memo, good.userOp, { trimmy: F.trimmy });
  assert.match(dg.html, /<strong>Trimmy<\/strong>/);
  assert.doesNotMatch(dg.html, /Do not send this/);
});

test('a one-shot rule is never described as recurring', async () => {
  const { decodeArmingPayment } = await import('../lib/decode.js');
  const { buildArmingPayment } = await import('../lib/arming.js');
  // total == part is exactly what the page used to send for EVERY rule: ceilDiv(1,1) = 1 run.
  const b = buildArmingPayment({ ...F, rule: { ...F.rule, totalSellAmount: 1000000n,
    partSellAmount: 1000000n, trigger: 2, triggerValue: 3600n } });
  const d = decodeArmingPayment(b.memo, b.userOp, { trimmy: F.trimmy });
  assert.match(d.html, /once, as soon as somebody runs it/);
  assert.match(d.html, /happens <strong>once<\/strong>/);
  assert.doesNotMatch(d.html, /every hour/);
});

test('a repeating rule states its run count and its total', async () => {
  const { decodeArmingPayment } = await import('../lib/decode.js');
  const { buildArmingPayment } = await import('../lib/arming.js');
  const b = buildArmingPayment({ ...F, rule: { ...F.rule, totalSellAmount: 12000000n,
    partSellAmount: 1000000n, trigger: 2, triggerValue: 3600n },
    allowance: 12000000n + 9400n * 12n });
  const d = decodeArmingPayment(b.memo, b.userOp, { trimmy: F.trimmy });
  assert.match(d.html, /12 times — the first straight away, then every hour/);
  assert.match(d.html, /Up to <strong>12<\/strong> runs of 1 XRP/);
  assert.match(d.html, /<strong>12 XRP<\/strong> in all/);
});

test('the run count uses the contract ceiling, not plain division', async () => {
  const { decodeArmingPayment } = await import('../lib/decode.js');
  const { buildArmingPayment } = await import('../lib/arming.js');
  // ceilDiv(2_500_000, 1_000_000) = 3. Plain division says 2 and under-reports the commitment.
  const b = buildArmingPayment({ ...F, rule: { ...F.rule, totalSellAmount: 2500000n,
    partSellAmount: 1000000n, trigger: 2, triggerValue: 3600n },
    allowance: 2500000n + 9400n * 3n });
  const d = decodeArmingPayment(b.memo, b.userOp, { trimmy: F.trimmy });
  assert.match(d.html, /Up to <strong>3<\/strong> runs/);
});
