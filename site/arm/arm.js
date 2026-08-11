import { buildArmingPayment, toHex, Refusal } from './lib/arming.js';
import { decodeArmingPayment } from './lib/decode.js';
import { lookupAccount, readExecutorFeeUBA, MINTING_FEE_UBA, UnknownAccount } from './lib/chain.js';
import { validateXrplAddress, InvalidAddress } from './lib/xrpl-address.js';

const FXRP       = '0x0b6A3645c240605887a5532109323A3E12273dc7';
const TRIMMY     = '0x19F81AAB43f7a26B0659754b70179aDcAF43ef7C';
const CORE_VAULT = 'rDhpmiPq4BVBDWMVdSrmkgt8thKyRzGV1p';
// Read from the AssetManager at lookup time. Governance can change it, and a payment that no
// longer clears it is under-delivered in silence rather than refused. The literal is only the
// measured fallback for when the read fails.
let executorFeeUBA = 100000n;
// Trimmy stores this in units of the result asset. The decoder names that
// asset explicitly so this value is never presented as XRP when the result is FLR or vault shares.
const KEEPER_FEE_RESULT_UNITS = 9400n;

const $ = (id) => document.getElementById(id);

/**
 * Refuse to run at all on an origin where the checks cannot run.
 *
 * `crypto.subtle`, which verifies the XRPL address checksum, and `navigator.clipboard` are both
 * secure-context only. Served from `http://<lan-ip>/`, which is exactly how this gets demoed from
 * a laptop to a phone, the checksum verify throws `Cannot read properties of undefined` and the
 * generic handler reports it as "could not read your account", blaming the chain for a browser
 * restriction. Every downstream step is gated on that check, so degrading quietly would leave a
 * page that looks like it works and has stopped verifying the one thing it exists to verify.
 *
 * There is deliberately no fallback to an unverified checksum. `getPersonalAccount` derives an
 * account from any string, so an unchecked typo builds an irreversible payment against an account
 * the sender does not control.
 */
function requireSecureContext() {
  if (window.isSecureContext && globalThis.crypto?.subtle) return true;
  const el = $('insecure');
  el.innerHTML =
    '<strong>This page cannot run safely on this address.</strong>'
    + `You have opened it over <span class="mono">${esc(location.protocol)}//${esc(location.host)}</span>. `
    + 'Address-checksum verification needs a secure context, and without it a mistyped XRPL address '
    + 'would silently build a payment for somebody else\'s account. Open it over '
    + '<span class="mono">https</span>, or from <span class="mono">localhost</span>.';
  el.classList.remove('hidden');
  $('lookup').disabled = true;
  $('xrpl').disabled = true;
  return false;
}

const esc = (s) => String(s).replace(/[&<>"]/g, (c) =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

/**
 * Shows an error where its cause is, not at the bottom of the document.
 *
 * `#error` sits after every panel, so a rejected address used to render up to two viewports below
 * the field that produced it, with no scroll and no focus move, so the button appeared to do
 * nothing. `field` puts the message directly under its input and moves focus there.
 */
const showError = (msg, field) => {
  if (field) {
    const slot = $(`${field}Error`);
    slot.textContent = msg;
    slot.classList.remove('hidden');
    $(field).setAttribute('aria-invalid', 'true');
    $(field).focus();
    return;
  }
  $('error').textContent = msg;
  $('error').classList.remove('hidden');
};
const clearError = () => {
  // Empty as well as hide. A hidden element holding a stale error is one CSS mistake away from
  // telling the user their address is mistyped when it is not.
  for (const id of ['error', 'xrplError']) {
    $(id).textContent = '';
    $(id).classList.add('hidden');
  }
  $('xrpl').removeAttribute('aria-invalid');
};

let account = null;   // { xrplAddress, personalAccount, nonce }

if (!requireSecureContext()) throw new Error('insecure origin, page disabled');

$('lookup').addEventListener('click', async () => {
  clearError();
  $('build').disabled = true;
  $('account').classList.add('hidden');
  $('lookup').disabled = true;
  $('lookup').textContent = 'Looking up…';
  try {
    // The checksum is verified BEFORE anything touches the chain. `getPersonalAccount` derives an
    // address from whatever string it is given rather than looking one up, so a mistyped address
    // does not fail, it quietly returns a different account, and a payment armed against it is
    // not recoverable.
    const xrpl = await validateXrplAddress($('xrpl').value);
    account = await lookupAccount(xrpl);
    try {
      ({ fee: executorFeeUBA } = await readExecutorFeeUBA());
    } catch {
      // Keep the measured fallback. Worth noting rather than hiding: if the real fee has since
      // risen above it, the payment under-delivers silently, so the page says which one it used.
      executorFeeUBA = 100000n;
    }

    $('account').innerHTML = `
      <dt>Your account on Flare</dt><dd>${account.personalAccount}</dd>
      <dt>Next instruction</dt><dd>#${account.nonce}</dd>`;
    $('account').classList.remove('hidden');
    $('build').disabled = false;
  } catch (e) {
    if (e instanceof InvalidAddress) showError(e.message, 'xrpl');
    else if (e instanceof UnknownAccount) showError('Flare has no account for this address yet.', 'xrpl');
    else showError('Could not read your account: ' + e.message);
  } finally {
    $('lookup').disabled = false;
    $('lookup').textContent = 'Look up my account';
  }
});

// A changed address invalidates everything derived from it.
$('xrpl').addEventListener('input', () => {
  // Clear the previous complaint as soon as the user acts on it. Leaving it up means a corrected
  // address still reads "that address fails its own checksum".
  clearError();
  account = null;
  $('build').disabled = true;
  $('account').classList.add('hidden');
  $('out').classList.add('hidden');
});

// ---- rule shape -----------------------------------------------------------------------------

function updatePresetFields() {
  const p = $('preset').value;
  const priced = p === 'below';
  const scheduled = p === 'swap' || p === 'vault';
  $('priceRow').style.display = (priced || p === 'private') ? '' : 'none';
  $('everyField').style.display = scheduled ? '' : 'none';
  // The live Coston2 swap venue has demonstrated reliable 0.01 XRP fills. The
  // vault has separately demonstrated a 1 XRP deposit. Start from what has
  // actually executed for each venue instead of carrying one generic amount.
  $('amount').value = p === 'vault' ? '1' : '0.01';
  $('priceLabel').textContent = p === 'private'
    ? 'Secret price, never published on chain (FLR per XRP)'
    : 'Sell if 1 XRP falls to (FLR)';
  $('price').parentElement.style.display = (priced || p === 'private') ? '' : 'none';
}

$('preset').addEventListener('change', updatePresetFields);

const requestedPreset = new URLSearchParams(window.location.search).get('preset');
const allowedPresets = new Set(['below', 'swap', 'vault', 'private']);
if (allowedPresets.has(requestedPreset)) $('preset').value = requestedPreset;
updatePresetFields();

function ruleFromForm() {
  const preset = $('preset').value;
  const xrp = Number($('amount').value);
  if (!(xrp > 0)) throw new Refusal('Amount must be more than zero.');
  const part = BigInt(Math.round(xrp * 1e6));             // FXRP has 6 decimals

  // How many times the rule may fire. Trimmy derives this itself as
  // `ceilDiv(totalSellAmount, partSellAmount)` (Trimmy.sol:451) and reverts `Exhausted()` once
  // `spent >= totalSellAmount`. This page used to send total == part, which meant EVERY rule ran
  // exactly once, while the summary said "every hour". Setting the total from an explicit run
  // count is what makes a schedule actually a schedule.
  const runs = BigInt($('runs').value || 1);
  const amount = part * runs;

  const expiry = BigInt(Math.floor(Date.now() / 1000) + Number($('days').value || 7) * 86400);

  // verb: 0 SWAP, 1 DEPOSIT_VAULT.  trigger: 0 PRICE_BELOW, 2 SCHEDULE, 3 PRIVATE.
  const shape = {
    vault:   { verb: 1, venueId: 1, buyTokenId: 0, trigger: 2 },
    swap:    { verb: 0, venueId: 0, buyTokenId: 1, trigger: 2 },
    below:   { verb: 0, venueId: 0, buyTokenId: 1, trigger: 0 },
    private: { verb: 0, venueId: 0, buyTokenId: 1, trigger: 3 },
  }[preset];

  let triggerValue;
  if (shape.trigger === 2) {
    triggerValue = BigInt($('every').value);              // seconds between runs
  } else if (shape.trigger === 3) {
    // A PRIVATE rule must publish nothing. The threshold goes to the enclave separately.
    triggerValue = 0n;
  } else {
    const flrPerXrp = Number($('price').value);
    if (!(flrPerXrp > 0)) throw new Refusal('Choose a price above zero.');
    triggerValue = BigInt(Math.round(flrPerXrp * 1e18));  // WC2FLR base units per whole XRP
  }

  // `minOutAbsolute` is a floor on ONE part, not on the whole rule, `execute` sells
  // `partSellAmount` and checks the proceeds of that part against it.
  const minOut = shape.verb === 1 ? part * 90n / 100n : 0n;

  return {
    sellTokenId: 0, buyTokenId: shape.buyTokenId,
    verb: shape.verb, venueId: shape.venueId, trigger: shape.trigger,
    totalSellAmount: amount, partSellAmount: part,
    minOutAbsolute: minOut, triggerValue, expiry,
    slippageBips: shape.verb === 0 ? 50 : 0, protocolFeeBips: 0,
    // L2 in the contract: a rule whose fee budget cannot fund its own executions is refused at
    // arm time rather than stopping silently partway through with a live allowance. The budget
    // must therefore cover every run, `keeperFeeFlat * maxExecutions` (Trimmy.sol:457).
    keeperFeeFlat: KEEPER_FEE_RESULT_UNITS, keeperFeeBudget: KEEPER_FEE_RESULT_UNITS * runs,
  };
}

// ---- build ----------------------------------------------------------------------------------

$('build').addEventListener('click', () => {
  clearError();
  try {
    const rule = ruleFromForm();
    const built = buildArmingPayment({
      personalAccount: account.personalAccount,
      nonce: account.nonce,
      fxrp: FXRP,
      trimmy: TRIMMY,
      // Keeper compensation is taken from the result asset by Trimmy._settle;
      // it is not additional FXRP the contract may pull from the user.
      allowance: rule.totalSellAmount,
      rule,
      executorFeeUBA,
    });

    // Decode what was just built, from the bytes, not from the form. This is the only step that
    // can catch an encoder that agreed with itself and with nothing else.
    const plain = decodeArmingPayment(built.memo, built.userOp, {
      knownTokens: { 0: 'XRP', 1: 'FLR' },
      tokenDecimals: { 0: 6, 1: 18 },
      trimmy: TRIMMY, fxrp: FXRP,
    });

    $('decoded').innerHTML = plain.html;
    const bd = paymentBreakdown(rule);
    $('payment').innerHTML =
      copyRow('Amount', `<span class="amount-hero">${xrp(bd.total)}<span>XRP</span></span>`)
      + `<details class="breakdown"><summary>What makes up ${xrp(bd.total)} XRP</summary>
           <dl class="kv">${bd.rows.map(([k, v]) =>
             `<dt>${k}</dt><dd>${xrp(v)} XRP</dd>`).join('')}
           <dt><strong>Total</strong></dt><dd><strong>${xrp(bd.total)} XRP</strong></dd></dl>
           <p class="note">Whatever the rule does not spend stays in your Flare account.</p>
         </details>`
      + copyRow('Pay to', CORE_VAULT)
      + copyRow('Memo (hex)', toHex(built.memo).toUpperCase());
    // A PRIVATE rule's threshold is deliberately absent from this payment. Saying nothing here
    // would leave the user believing the price they typed was carried by it, it is not, and a
    // rule armed without a provisioned secret simply never fires.
    const isPrivate = rule.trigger === 3;
    $('privateStep').classList.toggle('hidden', !isPrivate);
    if (isPrivate) {
      const threshold = BigInt(Math.round(Number($('price').value) * 1e18));
      $('privateCmd').innerHTML = copyRow(
        'Run after the rule exists',
        `go run ./cmd/trimmy-private -rule &lt;id&gt; -threshold ${threshold} ` +
        `-direction 0 -account ${account.personalAccount}`,
      );
    }

    $('out').classList.remove('hidden');
    wireCopyButtons();
    // Move focus to the verdict, not just the scroll position, otherwise "this payment is not
    // safe to send" is delivered to sighted users only. Native focus scrolling already honours
    // prefers-reduced-motion.
    $('verdictHeading').focus();
  } catch (e) {
    showError(e instanceof Refusal ? 'Refused: ' + e.message : 'Could not build it: ' + e.message);
  }
});

/**
 * What the payment must carry, itemised.
 *
 * Under-funding is the most expensive way to get this wrong, and it does not look like an error:
 * the protocol emits its SUCCESS event with `mintedAmountUBA: 0`, pays the fee receiver and the
 * executor, and the recipient gets nothing. So every component is named rather than rolled into
 * one number the user is asked to trust.
 */
function paymentBreakdown(rule) {
  const rows = [
    ['What the rule can spend', rule.totalSellAmount],
    ['Minting fee, taken by FAssets', MINTING_FEE_UBA],
    ['Delivery fee, paid to the executor', executorFeeUBA],
  ];
  const subtotal = rows.reduce((n, [, v]) => n + v, 0n);
  // Round the total UP to whole hundredths of an XRP so the figure is typeable, and show the
  // rounding as its own line rather than letting it look like an unexplained surcharge.
  const cents = (subtotal + 9999n) / 10000n;
  const total = cents * 10000n;
  const slack = total - subtotal;
  if (slack > 0n) rows.push(['Rounded up so the figure is typeable', slack]);
  return { rows, total };
}

const xrp = (uba) => (Number(uba) / 1e6).toFixed(uba % 10000n === 0n ? 2 : 6);

function copyRow(label, value) {
  return `<div class="copy">
      <div style="flex:1">
        <label>${label}</label>
        <div class="val" data-copy>${value}</div>
      </div>
      <button class="ghost" type="button" aria-label="Copy ${label}" style="margin-top:1.15rem">Copy</button>
    </div>`;
}

function wireCopyButtons() {
  for (const row of document.querySelectorAll('.copy')) {
    const btn = row.querySelector('button');
    const val = row.querySelector('[data-copy]');
    btn.addEventListener('click', async () => {
      const text = val.textContent.trim();
      try {
        // Secure-context only. On a plain-http origin this rejects, and an unhandled rejection
        // left the button unchanged, so the user pasted whatever was already on their clipboard
        // into an irreversible payment.
        await navigator.clipboard.writeText(text);
        btn.textContent = 'Copied';
      } catch {
        const range = document.createRange();
        range.selectNodeContents(val);
        const sel = getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
        btn.textContent = 'Select + copy';
      }
      setTimeout(() => { btn.textContent = 'Copy'; }, 1800);
    });
  }
}
