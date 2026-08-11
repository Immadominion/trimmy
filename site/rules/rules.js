// The live rule list, read straight from Coston2.
//
// There is no backend, no indexer and no cache. Every number on this page is
// fetched from the chain when the page loads, because the point of the page is
// that you do not have to believe us: the same two calls are in the panel at
// the bottom and you can run them yourself.
//
// `ruleAt(uint256)` returns the Rule struct ABI-encoded as 26 words, one field
// per word. That layout is asserted in `decodeRule` below and verified against
// contracts/src/Trimmy.sol. If a field is added to the struct, the assertion
// fails loudly rather than silently shifting every value by one slot.

const RPC = 'https://coston2-api.flare.network/ext/C/rpc';
const TRIMMY = '0x19F81AAB43f7a26B0659754b70179aDcAF43ef7C';
const EXPLORER = 'https://coston2-explorer.flare.network';

const VERBS = ['Sell on a market', 'Deposit into a vault', 'Withdraw from a vault'];
const TRIGGERS = ['Price falls to', 'Price rises to', 'On a schedule', 'A private price'];
const RULE_WORDS = 26;

const $ = (id) => document.getElementById(id);
const hex = (b) => [...b].map((x) => x.toString(16).padStart(2, '0')).join('');

function fromHex(s) {
  const t = s.replace(/^0x/, '');
  const out = new Uint8Array(t.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(t.substr(i * 2, 2), 16);
  return out;
}

async function ethCall(to, data) {
  const res = await fetch(RPC, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0', id: 1, method: 'eth_call',
      params: [{ to, data }, 'latest'],
    }),
  });
  const json = await res.json();
  if (json.error) throw new Error(json.error.message);
  return fromHex(json.result);
}

const word = (b, i) => {
  let v = 0n;
  for (let k = i * 32; k < (i + 1) * 32; k++) v = (v << 8n) | BigInt(b[k]);
  return v;
};

// Selectors, precomputed rather than hashed in the browser: this page has no
// keccak implementation and does not need one for two constant signatures.
//
// Both were VERIFIED with `cast sig`, not recalled. Recalling them is how you
// get a page that renders an empty state forever: a wrong selector does not
// throw, it returns 0x, which decodes as a count of zero and looks exactly like
// "no rules armed yet".
//
//   cast sig "ruleCount()"       -> 0xf6bcf633
//   cast sig "ruleAt(uint256)"   -> 0x63a6fef6
//   cast sig "tokenAt(uint8)"    -> 0xbc13f2a4
const SEL = {
  ruleCount: '0xf6bcf633',
  ruleAt: '0x63a6fef6',
  tokenAt: '0xbc13f2a4',
};

/// Token decimals, read once and cached for the life of the page.
///
/// This is not a nicety. `keeperFeeFlat` is denominated in the BUY token, and
/// the sell amounts in the SELL token. Formatting both at 6 decimals renders a
/// 0.02 WC2FLR fee (18 decimals) as "20000000000 XRP", which is not a rounding
/// error, it is off by twelve orders of magnitude and it made the page lie.
const decimalsOf = new Map();

async function tokenDecimals(id) {
  if (decimalsOf.has(id)) return decimalsOf.get(id);
  // TokenCfg { address token; bytes21 feedId; uint8 decimals; } -> 3 words
  const raw = await ethCall(TRIMMY, SEL.tokenAt + u256(id));
  const d = Number(word(raw, 2));
  decimalsOf.set(id, d);
  return d;
}

const SYMBOL = { 6: 'FXRP', 18: 'WC2FLR' };

const u256 = (n) => BigInt(n).toString(16).padStart(64, '0');

/** 6-decimal amounts as a decimal string. No floating point, ever. */
function amount(v, decimals = 6) {
  const d = 10n ** BigInt(decimals);
  const whole = v / d;
  const frac = (v % d).toString().padStart(decimals, '0').replace(/0+$/, '');
  return frac ? `${whole}.${frac}` : `${whole}`;
}

function decodeRule(b) {
  if (b.length !== RULE_WORDS * 32) {
    throw new Error(
      `ruleAt returned ${b.length / 32} words, expected ${RULE_WORDS}. ` +
      'The Rule struct changed; update decodeRule before trusting this page.',
    );
  }
  const at = (i) => word(b, i);
  return {
    account: '0x' + hex(b.slice(12, 32)),
    epoch: Number(at(1)),
    sellTokenId: Number(at(2)),
    buyTokenId: Number(at(3)),
    verb: Number(at(4)),
    venueId: Number(at(5)),
    trigger: Number(at(6)),
    active: at(7) === 1n,
    totalSellAmount: at(8),
    partSellAmount: at(9),
    spent: at(10),
    minOutAbsolute: at(11),
    triggerValue: at(12),
    latchedPrice: at(13),
    nextEligibleAt: Number(at(14)),
    expiry: Number(at(15)),
    keeperFeeFlat: at(18),
    keeperFeeBudget: at(19),
    keeperFeePaid: at(20),
    slippageBips: Number(at(22)),
  };
}

const esc = (s) => String(s).replace(/[&<>"]/g, (c) =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

const short = (a) => a.slice(0, 8) + '…' + a.slice(-4);

function statusOf(r) {
  const now = Math.floor(Date.now() / 1000);
  if (r.spent >= r.totalSellAmount) return { label: 'Finished', kind: 'done' };
  if (!r.active) return { label: 'Cancelled', kind: 'off' };
  if (r.expiry && now > r.expiry) return { label: 'Expired', kind: 'off' };
  return { label: 'Watching', kind: 'live' };
}

function describe(r) {
  const part = amount(r.partSellAmount, r.sellDecimals);
  const verb = VERBS[r.verb] ?? `verb ${r.verb}`;
  if (r.trigger === 2) {
    const s = Number(r.triggerValue);
    const every = s % 86400 === 0 ? `${s / 86400} day(s)` :
                  s % 3600 === 0 ? `${s / 3600} hour(s)` :
                  s % 60 === 0 ? `${s / 60} minute(s)` : `${s} seconds`;
    return `${verb}, ${part} ${r.sellSymbol} every ${every}`;
  }
  if (r.trigger === 3) return `${verb}, ${part} ${r.sellSymbol} at a price held inside an enclave`;
  const dir = r.trigger === 0 ? 'falls to' : 'rises to';
  return `${verb}, ${part} ${r.sellSymbol} when the price ${dir} ${amount(r.triggerValue, 18)}`;
}

function card(id, r) {
  const st = statusOf(r);
  const runs = r.partSellAmount > 0n
    ? (r.totalSellAmount + r.partSellAmount - 1n) / r.partSellAmount : 1n;
  const done = r.partSellAmount > 0n ? r.spent / r.partSellAmount : 0n;
  const pct = r.totalSellAmount > 0n
    ? Number((r.spent * 100n) / r.totalSellAmount) : 0;
  const sell = (v) => `${amount(v, r.sellDecimals)} ${r.sellSymbol}`;
  const buy = (v) => `${amount(v, r.buyDecimals)} ${r.buySymbol}`;
  // Slippage bounds the venue, so it means nothing for a vault deposit or exit
  // where there is no venue price to slip against. Printing "0.00%" there
  // reads as "we allow zero slippage", which is a stronger claim than the truth.
  const bound = r.verb === 0 ? `${(r.slippageBips / 100).toFixed(2)}%` : 'n/a for vaults';

  return `<article class="rule">
    <header class="rule__head">
      <div>
        <p class="rule__id">Rule ${id}</p>
        <h3 class="rule__what">${esc(describe(r))}</h3>
      </div>
      <span class="rule__status rule__status--${st.kind}">${st.label}</span>
    </header>

    <div class="rule__bar" role="img"
         aria-label="${done} of ${runs} runs used">
      <span style="width:${pct}%"></span>
    </div>
    <p class="rule__progress">${done} of ${runs} run${runs === 1n ? '' : 's'} used
      (${amount(r.spent, r.sellDecimals)} of ${sell(r.totalSellAmount)})</p>

    <dl class="rule__facts">
      <div><dt>Owner</dt><dd><a href="${EXPLORER}/address/${r.account}">${short(r.account)}</a></dd></div>
      <div><dt>Trigger</dt><dd>${esc(TRIGGERS[r.trigger] ?? r.trigger)}</dd></div>
      <div><dt>Fee per run</dt><dd>${buy(r.keeperFeeFlat)}</dd></div>
      <div><dt>Fee paid so far</dt><dd>${buy(r.keeperFeePaid)}</dd></div>
      <div><dt>Price bound</dt><dd>${bound}</dd></div>
      <div><dt>Expires</dt><dd>${r.expiry
        ? new Date(r.expiry * 1000).toISOString().slice(0, 16).replace('T', ' ') + ' UTC'
        : 'never'}</dd></div>
    </dl>

    ${r.trigger === 3 ? `<p class="rule__note"><b>The trigger price is not on this page because it
      is not on the chain.</b> It exists only inside the enclave. What you can see here is
      everything anybody can see.</p>` : ''}
  </article>`;
}

async function load() {
  const status = $('status');
  const list = $('list');
  try {
    const countRaw = await ethCall(TRIMMY, SEL.ruleCount);
    const count = Number(word(countRaw, 0));

    status.className = 'rules__status rules__status--ok';
    status.textContent = count === 0
      ? 'No rules armed yet.'
      : `${count} rule${count === 1 ? '' : 's'} armed on this deployment.`;

    if (count === 0) { list.innerHTML = ''; return; }

    // Sequential rather than parallel: four calls against a public RPC do not
    // need a burst, and a burst is how you get rate limited on a free endpoint.
    const cards = [];
    for (let i = 0; i < count; i++) {
      const raw = await ethCall(TRIMMY, SEL.ruleAt + u256(i));
      const r = decodeRule(raw);
      r.sellDecimals = await tokenDecimals(r.sellTokenId);
      r.buyDecimals = await tokenDecimals(r.buyTokenId);
      r.sellSymbol = SYMBOL[r.sellDecimals] ?? `token ${r.sellTokenId}`;
      r.buySymbol = SYMBOL[r.buyDecimals] ?? `token ${r.buyTokenId}`;
      cards.push(card(i, r));
    }
    list.innerHTML = cards.join('');
  } catch (e) {
    // Say what failed and what the reader can do, rather than "an error
    // occurred". The most likely cause is the public RPC, not the contract.
    status.className = 'rules__status rules__status--bad';
    status.innerHTML = `Could not read the chain: ${esc(e.message)}.<br>
      <span class="t-sm">The contract is at
      <a href="${EXPLORER}/address/${TRIMMY}">${TRIMMY}</a> and you can read it directly
      with the commands below. This page has no backend, so if the public Coston2 RPC is
      down there is nothing here to fall back to.</span>`;
    list.innerHTML = '';
  }
}

load();
