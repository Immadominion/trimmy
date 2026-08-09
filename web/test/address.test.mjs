import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateXrplAddress, InvalidAddress } from '../lib/xrpl-address.js';

// Real addresses this project has actually used on chain.
const GOOD = [
  'rDE4JUm2jaue31VwidRXWuWzf5dQkUxcsB',   // our funded testnet account
  'rDhpmiPq4BVBDWMVdSrmkgt8thKyRzGV1p',   // the FAssets Core Vault
];

test('accepts addresses that are really in use', async () => {
  for (const a of GOOD) assert.equal(await validateXrplAddress(a), a);
});

test('rejects the single-character typo that the controller would silently accept', async () => {
  // getPersonalAccount() maps this to 0x6085dbe8… — a different account entirely, with no error.
  await assert.rejects(
    () => validateXrplAddress('rDE4JUm2jaue31VwidRXWuWzf5dQkUxcsA'),
    (e) => e instanceof InvalidAddress && /checksum/.test(e.message),
  );
});

test('rejects things that are not addresses at all', async () => {
  for (const bad of ['', '   ', 'not-an-address', '0x38d58d1BEA8FF21fd8397494f17F64A99bcF8E83']) {
    await assert.rejects(() => validateXrplAddress(bad), InvalidAddress);
  }
});

test('rejects characters outside the XRPL alphabet', async () => {
  // '0', 'O', 'I' and 'l' are excluded precisely because they are confusable.
  await assert.rejects(
    () => validateXrplAddress('rDE4JUm2jaue31VwidRXWuWzf5dQkUx0sB'),
    (e) => e instanceof InvalidAddress && /valid character/.test(e.message),
  );
});

test('rejects a well-formed address of the wrong length', async () => {
  await assert.rejects(() => validateXrplAddress('rDE4JUm'), InvalidAddress);
});

test('every single-character substitution in a real address is caught', async () => {
  // The checksum is 4 bytes, so a random corruption slips through about 1 time in 4 billion.
  // Across a whole address this should be a clean sweep, and if it ever is not, the failure is
  // one a user would pay for.
  const base = GOOD[0];
  const alphabet = 'rpshnaf39wBUDNEGHJKLM4PQRST7VWXYZ2bcdeCg65jkm8oFqi1tuvAxyz';
  let checked = 0, slipped = [];
  for (let i = 1; i < base.length; i++) {
    for (const c of alphabet) {
      if (c === base[i]) continue;
      const candidate = base.slice(0, i) + c + base.slice(i + 1);
      checked++;
      try { await validateXrplAddress(candidate); slipped.push(candidate); } catch { /* expected */ }
    }
  }
  assert.equal(slipped.length, 0, `${slipped.length} of ${checked} typos were accepted`);
  assert.ok(checked > 1800, `only ${checked} variants tested`);
});
