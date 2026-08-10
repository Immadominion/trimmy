// Decodes an arming payment back out of its own bytes, into English.
//
// This exists to be *distrustful of the encoder next to it*. The page could simply restate the form
// the user filled in — and that would look identical while proving nothing, because a bug in the
// encoder would be echoed back word for word. So nothing here reads the form. Everything below is
// recovered from the 42-byte memo and the user-operation pre-image, the same two artefacts an
// executor sees, and the commitment is re-derived rather than trusted.
//
// It mirrors `arming/bin/decode.dart`, which does the same job at the command line and exits
// non-zero when a memo does not match its pre-image.

import { keccak256 } from './keccak.js';
import { toHex } from './arming.js';

const VERBS = { 0: 'sell it on a market', 1: 'deposit it into the yield vault', 2: 'withdraw from the yield vault' };
const TRIGGERS = { 0: 'PRICE_BELOW', 1: 'PRICE_ABOVE', 2: 'SCHEDULE', 3: 'PRIVATE' };

const word = (b, off) => {
  let v = 0n;
  for (let i = 0; i < 32; i++) v = (v << 8n) | BigInt(b[off + i]);
  return v;
};
const addressAt = (b, off) => '0x' + toHex(b.slice(off + 12, off + 32));
const esc = (s) => String(s).replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));

const fmtUnits = (v, decimals) => {
  const d = BigInt(10) ** BigInt(decimals);
  const whole = v / d;
  const frac = (v % d).toString().padStart(decimals, '0').replace(/0+$/, '');
  return frac ? `${whole}.${frac}` : `${whole}`;
};

const fmtDuration = (s) => {
  const n = Number(s);
  if (n % 86400 === 0) return n === 86400 ? 'day' : `${n / 86400} days`;
  if (n % 3600 === 0) return n === 3600 ? 'hour' : `${n / 3600} hours`;
  if (n % 60 === 0) return n === 60 ? 'minute' : `${n / 60} minutes`;
  return `${n} seconds`;
};

/**
 * @param memo    the 42 bytes that will travel in the XRPL payment
 * @param userOp  abi.encode(PackedUserOperation) — what the memo commits to
 */
export function decodeArmingPayment(memo, userOp, ctx = {}) {
  const problems = [];

  // ---- the memo, on its own terms -------------------------------------------------------------
  if (memo.length !== 42) problems.push(`the memo is ${memo.length} bytes, and must be exactly 42`);
  if (memo[0] !== 0xfe) problems.push(`the memo opcode is 0x${memo[0].toString(16)}, expected 0xFE`);

  let fee = 0n;
  for (let i = 2; i < 10; i++) fee = (fee << 8n) | BigInt(memo[i]);
  if (fee === 0n) {
    problems.push('the executor fee is zero, so no executor will ever run this payment');
  }

  // ---- does the memo actually commit to this batch? -------------------------------------------
  const commitment = keccak256(userOp);
  const carried = memo.slice(10, 42);
  const matches = carried.length === 32 && commitment.every((b, i) => b === carried[i]);
  if (!matches) {
    problems.push('the memo does not commit to this user operation — the payment would do something else');
  }

  // ---- the batch itself ------------------------------------------------------------------------
  // Layout is fixed by the encoder: after the leading offset word, the head is nine words, and the
  // callData tail begins at the offset the fifth word points at.
  const calls = [];
  try {
    // Head, after the leading offset-to-struct word:
    //   0 sender  1 nonce  2 initCode*  3 callData*  4 accountGasLimits
    //   5 preVerificationGas  6 gasFees  7 paymasterAndData*  8 signature*
    // Slot 4 is a zero-filled value, not a pointer — reading callData from there yields offset 0
    // and the parse walks off the end.
    const base = 32;
    const sender = addressAt(userOp, base);
    const nonce = word(userOp, base + 32);
    const callDataOff = base + Number(word(userOp, base + 32 * 3));
    const callDataLen = Number(word(userOp, callDataOff));
    const cd = userOp.slice(callDataOff + 32, callDataOff + 32 + callDataLen);

    const arrayBase = 4 + 32 + 32;                     // selector, offset-to-array, array length
    const count = Number(word(cd, 4 + 32));
    for (let i = 0; i < count; i++) {
      const elemOff = arrayBase + Number(word(cd, arrayBase + i * 32));
      const target = addressAt(cd, elemOff);
      const dataOff = elemOff + Number(word(cd, elemOff + 64));
      const dataLen = Number(word(cd, dataOff));
      calls.push({ target, data: cd.slice(dataOff + 32, dataOff + 32 + dataLen) });
    }
    ctx = { ...ctx, sender, nonce };
  } catch (e) {
    // Say what went wrong. A bare "could not be decoded" is the kind of message that turns a
    // five-minute diagnosis into an hour of guessing.
    problems.push(
      `the user operation could not be decoded, so what it would do is unknown (${e.message})`,
    );
  }

  // ---- render ----------------------------------------------------------------------------------
  let html = '';
  if (problems.length) {
    html += `<div class="banner bad"><strong>This payment is not safe to send.</strong><ul>`
      + problems.map((p) => `<li>${esc(p)}</li>`).join('') + '</ul></div>';
  }

  html += `<p class="note" style="margin-top:0">Signing this payment would do
    ${calls.length} thing${calls.length === 1 ? '' : 's'}, in order:</p><ol class="plain">`;

  for (const call of calls) {
    const sel = toHex(call.data.slice(0, 4));
    if (sel === '095ea7b3') {
      const spender = addressAt(call.data, 4);
      const amount = word(call.data, 36);
      // Name it only when it really is the contract we expect. An unexpected spender must read as
      // unexpected rather than being dressed up in a friendly label.
      const known = ctx.trimmy && spender.toLowerCase() === ctx.trimmy.toLowerCase();
      const who = known
        ? `<strong>Trimmy</strong> <span class="mono">(${esc(spender)})</span>`
        : `<strong>an unrecognised contract</strong> <span class="mono">${esc(spender)}</span>`;
      html += `<li><strong>Allow spending</strong> — let ${who} move up to
        <strong>${fmtUnits(amount, 6)} XRP</strong> of yours.
        <div class="note">This is an allowance, not a transfer. It is capped at exactly this
        amount and nothing can spend more than it.${
          known ? '' : ' <strong>This is not the Trimmy contract. Do not send this.</strong>'
        }</div></li>`;
    } else if (sel === 'cc0c55f4') {
      html += `<li><strong>Create the rule</strong>${renderRule(call.data)}</li>`;
    } else {
      html += `<li><strong>Unrecognised call</strong> to
        <span class="mono">${esc(call.target)}</span> — selector
        <span class="mono">0x${esc(sel)}</span>.
        <div class="note">This page cannot tell you what it does. Do not send it.</div></li>`;
    }
  }
  html += '</ol>';

  html += `<dl class="kv" style="margin-top:1.2rem">
    <dt>Executor fee</dt><dd>${fmtUnits(fee, 6)} XRP</dd>
    <dt>Commitment</dt><dd>0x${toHex(commitment)}</dd>
    <dt>Memo matches</dt><dd>${matches ? 'yes — re-derived from the bytes above' : 'NO'}</dd>
  </dl>`;

  return { html, problems, matches, commitment };
}

function renderRule(data) {
  const at = (i) => word(data, 4 + i * 32);
  const buyTokenId = Number(at(1));
  const verb = Number(at(2));
  const trigger = Number(at(4));
  const total = at(5), part = at(6), minOut = at(7), triggerValue = at(8), expiry = at(9);
  const slippage = Number(at(10)), keeperFee = at(12);

  // The contract's own arithmetic, not an approximation of it: Trimmy computes
  // `maxExecutions = ceilDiv(totalSellAmount, partSellAmount)` and refuses to execute once
  // `spent >= totalSellAmount`. Dividing without the ceiling under-reports a rule whose total is
  // not a whole multiple of its part.
  const runs = part > 0n ? (total + part - 1n) / part : 1n;
  const once = runs === 1n;

  let when;
  if (trigger === 2) {
    // A rule is eligible the moment it is armed (`nextEligibleAt = block.timestamp`), so the
    // interval governs the gap between runs, never the wait for the first one. Saying "every hour"
    // about a rule that can only run once is the exact misreading this decoder exists to prevent.
    when = once
      ? 'once, as soon as somebody runs it for you'
      : `${runs} times — the first straight away, then every ${fmtDuration(triggerValue)}`;
  } else if (trigger === 0) {
    when = `when 1 XRP falls to ${fmtUnits(triggerValue, 18)} FLR or below`;
  } else if (trigger === 1) {
    when = `when 1 XRP rises to ${fmtUnits(triggerValue, 18)} FLR or above`;
  } else if (trigger === 3) {
    when = 'at a secret price held only inside a secure enclave';
  } else {
    when = `trigger #${trigger}`;
  }

  const expiryDate = new Date(Number(expiry) * 1000).toISOString().replace('T', ' ').slice(0, 16);

  let out = `<div style="margin-top:.4rem">`;
  out += `<div>Take <strong>${fmtUnits(part, 6)} XRP</strong> and
    <strong>${esc(VERBS[verb] ?? `verb #${verb}`)}</strong>, <strong>${esc(when)}</strong>.</div>`;
  // State the count in every case. Gating this on `runs > 1` is what let a one-shot rule be
  // described as a recurring one with nothing to correct the impression.
  out += once
    ? `<div class="note">This happens <strong>once</strong>, and then the rule is finished.
       ${trigger === 2 ? 'The interval never applies, because there is no second run.' : ''}</div>`
    : `<div class="note">Up to <strong>${runs}</strong> runs of ${fmtUnits(part, 6)} XRP —
       <strong>${fmtUnits(total, 6)} XRP</strong> in all, if every one of them fires.</div>`;
  out += `<div class="note">Expires ${esc(expiryDate)} UTC. Anything unspent stays yours.</div>`;

  if (trigger === 3) {
    out += `<div class="note"><strong>Nothing on the public ledger reveals your price.</strong>
      The chain stores only a commitment to it; the number itself is delivered to the enclave
      encrypted, and it never leaves.</div>`;
  }
  if (verb === 0) {
    out += `<div class="note">Each sale must land within ${slippage / 100}% of the oracle price,
      or it does not happen at all.</div>`;
  }
  if (verb === 1 && minOut > 0n) {
    out += `<div class="note">Must return at least ${fmtUnits(minOut, 6)} vault shares.</div>`;
  }
  out += `<div class="note">Whoever runs it for you earns ${fmtUnits(keeperFee, 6)} XRP per run,
    paid out of the proceeds. You never pay gas.</div>`;
  out += '</div>';
  return out;
}
