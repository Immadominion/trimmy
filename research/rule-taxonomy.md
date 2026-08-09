# Trimmy — Rule Taxonomy and Unified Rule Model

**Date:** 2026-08-06 · **Status:** specification, opinionated, intended to be implemented as written
**Scope:** the complete automation surface of Trimmy, the single engine that expresses all of it, its
failure semantics, and its price.

Evidence labels follow the repo convention:
`[Verified]` primary source / live chain / code read · `[Measured]` computed from an identified
experiment or price table cited here · `[Inference]` reasoned from stated verified facts ·
`[Unverified]` still open, with the exact experiment named.

---

## 0. The one-paragraph thesis

Every automation product in finance — a stop-loss, an Acorns round-up, a Binance Auto-Invest plan, a
Beefy auto-compounder, a dead-man switch — is the same sentence with different nouns:

> **on** *some tick*, **if** *some predicate over signals and remembered state* holds, **then** run
> *an atomic batch of calls*, **subject to** *bounds*, **and then** *update the remembered state*.

Trimmy should implement that sentence once. Everything in §1–§2 below is then a **row in a table**,
not a code path. The two design moves that make this actually true rather than merely elegant are in
§3.4 (evaluation returns a *state delta* and a *fire bit*, separately) and §3.7 (fill strategy is a
property of the action, not a rule type — which absorbs TWAP, iceberg and partial fills). If those two
are right, there are no special cases left.

---

## 1. What automation people actually use, and who pays for it

### 1.1 Evidence table

| Product / order type | Provider | Adoption evidence | What the user pays | Label |
|---|---|---|---|---|
| Recurring buy (DCA) | Coinbase | Recurring buys run on the "Simple" fee path; Coinbase does not publish per-feature usage | **≈2.49% effective** (1.99% fee >$200 + ~0.5% spread); Advanced Trade manual DCA is 0.40–0.60% | `[Verified]` fee structure, `[Unverified]` usage share |
| Auto-Invest (DCA) | Binance | Hourly/daily/weekly/bi-weekly/monthly; 200+ assets; up to **100 concurrent plans** per user; product revision driven by 10+ interviews and **1,046 survey responses** | **0.1% (10 bps)** standard spot fee, 0.075% with BNB; periodic zero-fee promos | `[Verified]` |
| DCA / Recurring orders | Jupiter (Solana) | **$996.4k revenue = 2.6%** of Jupiter protocol revenue; Jupiter is ~95% of Solana aggregator share | **0.1% (10 bps)** platform fee on order completion | `[Verified]` |
| Round-ups + auto-save | Acorns | **>10M users** (one source says 5.7M) | **$3/month subscription** (Bronze) | `[Verified]` |
| Automated savings (Nigeria) | PiggyVest | **>6M users**; **₦835bn** paid out in 2024 (+53% YoY); **₦2tn** cumulative payouts; users saving **₦44,000/second** ≈ ₦1.39tn annualised; AUM +76% | **Free to the user.** Monetised on float / spread / partner yield | `[Verified]` |
| Automated savings + micro-investing (Nigeria) | Cowrywise | Daily/weekly/monthly auto-debit plans from ₦1,000; SEC-regulated | Free at the savings layer; fees inside the mutual-fund products | `[Verified]` |
| Auto-compounding vaults | Beefy | Multi-chain yield optimiser, the category standard | **4.5% of yield** (3% strategist / 1% treasury / **0.5% to whoever calls harvest**) | `[Verified]` |
| Auto-compounding vaults | Yearn | Category incumbent | **20% performance fee**; legacy V2 also 2% management | `[Verified]` |
| Limit / stop-loss on a DEX | Autonomy Network (AutoSwap, BSC/Avalanche) | First to ship limit + stop-loss for PancakeSwap and Trader Joe | Gas reimbursement + an executor incentive fee; **no published headline rate** | `[Verified]` existence, `[Unverified]` rate |
| Generic on-chain automation | Gelato | Infra layer used by Pyth and others | **% premium on gas** (executors historically ~2% of gas), premium varies by chain; payable in stablecoins | `[Verified]` shape, `[Unverified]` current exact premium |
| Limit orders | 1inch LOP | Category standard | **No protocol fee in LOP itself**; Fusion adds resolver/integrator fees baked into the quoted spread | `[Verified]` |
| Inheritance / dead-man switch | Sarcophagus, Inheriti, Casa | Sarcophagus raised **$5.47M** from Placeholder/Inflection/Arweave, and still has "a relatively small user base"; a 2026 comparative audit found all three had deal-breakers (centralisation, tokenomics, or cost) | Node-operator fees in SARCO; Casa is a subscription | `[Verified]` |

### 1.2 The three things this table actually says

**(a) Automation is a consumer subscription business at the retail end and a bps business at the
crypto end.** Acorns charges $3/month for round-ups and has ~10M users. PiggyVest charges the user
nothing and has 6M users on float economics. Jupiter and Binance charge 10 bps. Coinbase charges
249 bps and gets away with it because the alternative is friction. **The willingness-to-pay band for
"do this for me automatically" is 10–250 bps of notional, or $3/month.** `[Measured — table above]`

**(b) The expensive automation is the one that is bundled with custody.** Coinbase's 249 bps is not
the price of a cron job; it is the price of a cron job you cannot run yourself because your coins are
in their vault. Binance's 10 bps is the same. Trimmy's entire competitive claim is that it delivers
the cron job **without** the custody, so it must price under the custodial number and near the
non-custodial number. See §5.

**(c) The two most-adopted products in the table are not trader tools.** Acorns (10M) and PiggyVest
(6M) are *savings* products. Jupiter DCA is 2.6% of a trading protocol's revenue. Stop-losses do not
appear anywhere with a user count attached. That is the single most important input to §2.

### 1.3 Honest gaps in this evidence

- No exchange publishes "what % of users placed a stop-loss." I searched for it and it does not
  exist publicly. Every claim you will read online about this is unsourced. `[Verified — absence]`
- Coinbase and Binance publish no per-feature adoption for recurring buys. `[Unverified]`
- **Experiment that would settle both:** instrument Trimmy's own funnel. Log every rule *composed*
  in the UI, not only every rule *armed*. The compose→arm ratio per rule type, on the first 200 real
  users, is a better number than anything a CEX would publish anyway, and it is collectable inside
  the hackathon window.

---

## 2. Which of these are meaningful for an XRP holder — and which are trader fantasy

### 2.1 The audience, stated plainly

7.7M activated XRPL wallets, ~86k new per month, ~60% underwater, mostly retail, mostly mobile,
strongly HODL-cultured, averse to selling. Addressable ceiling today: **FXRP total supply is
149,217,295.727906 FXRP** = **~$156.5M** at the live FTSO XRP/USD of **$1.049107**.
`[Verified — live read of AssetManagerFXRP 0x2a3F…B6A8 → fAsset() 0xAd55…c5bE, totalSupply and
decimals; FtsoV2 0x7BDE…1d20 getFeedById(XRP/USD) = 1049107, decimals 6, Flare mainnet block
66,760,254, 2026-08-06]`

Three facts about this audience dominate the taxonomy:

1. **They will not sell the stack.** Any rule whose default outcome is "you no longer hold XRP" will
   be composed and then abandoned. Rules that sell a *fraction*, or that sell only to *re-buy lower*,
   survive; rules that liquidate do not.
2. **They are underwater, so "protect gains" is the wrong pitch.** For 60% of them there are no
   gains. "Do not miss the exit this time" and "make the bag work while you wait" are the two live
   emotions.
3. **They already have a native limit order and do not know it.** The XRPL DEX **does** support limit
   orders natively via `OfferCreate`. What it does not have, in its own words, is: *"The XRP Ledger
   does not natively represent concepts such as market orders, stop orders, or trading on leverage."*
   `[Verified — xrpl.org/docs/concepts/tokens/decentralized-exchange]` Trimmy must not claim to
   invent the limit order. Its claim is the conditional and the schedule.

### 2.2 What XRPL can and cannot do natively — the honesty column

| Capability | Native on XRPL? | Source |
|---|---|---|
| Limit order (resting offer at a price) | **Yes** — `OfferCreate` on the native DEX | `[Verified]` xrpl.org |
| Market order, stop order, leverage | **No**, stated explicitly by xrpl.org | `[Verified]` |
| Time-locked one-shot release | **Yes** — `EscrowCreate` (time / crypto-condition); extended to issued tokens and MPTs by **XLS-85, activated 2026-02-12** | `[Verified]` |
| Programmable escrow release condition | **XLS-0100 Smart Escrows — proposal**, not an activated amendment | `[Verified]` |
| Recurring / subscription payments | **XLS-0078 Subscriptions — Draft** as of Sep 2025 | `[Verified]` |
| Atomic multi-operation batch | **Yes** — XLS-56 Batch Transactions, shipped in rippled 2.5.0 | `[Verified]` |
| Any condition on an *external* signal (price, weather, a bank balance) | **No.** No oracle, no conditional execution | `[Verified — by absence in the amendment list]` |

**The strategic reading.** XLS-0078 and XLS-0100 are the competitive clock on Trimmy's *schedule*
and *escrow* rules. They are not the clock on its *price* and *external-data* rules, because the XRPL
has no oracle and no plan for one. **Trimmy's defensible core is therefore the class of rules whose
predicate reads a signal the XRP Ledger cannot see.** Schedule-only rules are a beachhead, not a moat,
and the spec should say so out loud rather than get surprised by an amendment.

### 2.3 The taxonomy, tiered by whether this audience would genuinely arm it

**Tier A — they will arm these. Build all of them for v1.**

| # | Rule | Why this audience specifically | Sells the stack? |
|---|---|---|---|
| A1 | **Auto-earn / auto-compound idle FXRP** — "any FXRP sitting in my account above X goes to the vault; yield restakes weekly" | Pure upside, zero sell, directly answers "make the bag work while I wait". Beefy proved people pay 4.5% *of yield* for exactly this | No |
| A2 | **Take-profit ladder** — "sell 10% at $2.50, another 10% at $4, another 10% at $8" | HODL-compatible *because it is a ladder of fractions*. This is the single rule that converts "I'll never sell" into "fine, a tenth" | Fraction only |
| A3 | **Buy-the-dip limit** — "if XRP < $0.80, convert 200 USDT0 → FXRP" | Accumulation-flavoured; culturally the most acceptable trade in this community | No (buys) |
| A4 | **DCA-in on a schedule** — "every Friday, 20 USDT0 → FXRP" | The single most-adopted crypto automation product that exists (Binance, Coinbase, Jupiter all ship it) | No (buys) |
| A5 | **Round-up / auto-save on incoming payment** — "every XRP payment I receive, round the amount up to the next whole XRP and stake the difference" | The Acorns (10M users) and PiggyVest (6M users) mechanic, transplanted. Uniquely enabled here by FDC `XRPPayment` attestation of the *user's own* incoming XRPL payments | No |
| A6 | **Recurring payout / drip** — "send 50 XRP to `rXYZ…` on the 1st of every month, funded from the vault" | Remittance and allowance shaped; in Nigeria this is the *product*, not a feature. XRPL Escrow cannot do it (one-shot, pre-funded); XLS-0078 would, but it is Draft | Spends, not sells |
| A7 | **Dead-man switch / inheritance** — "if I have not checked in for 180 days, redeem everything to `rHEIR…`" | Self-custody + long horizon + a base that plans to hold for a decade. Sarcophagus raised $5.47M for this on Ethereum and still has almost no users *because it is a data-escrow product, not a money product*. Trimmy's version moves the money, which is what people actually want | Transfers |

**Tier B — real, smaller, and worth shipping because they carry the demo.**

| # | Rule | Honest read |
|---|---|---|
| B1 | **Stop-loss** — "if XRP < $0.70, convert everything to USDT0" | Genuinely wanted by the trader minority and by anyone who lived through a drawdown. Also the rule most exposed to oracle lag, DEX depth and regret. Ship it, guard it hard (§4.5), do **not** make it the hero of the pitch. Pitching a stop-loss to an XRP HODL audience reads as an insult |
| B2 | **Trailing stop** — "sell if we fall 15% from the high after arming" | The best *demo* in the product because it visibly requires memory that no XRPL primitive has. Small real usage. See §4.1 for the mechanism, which is the most interesting engineering in the spec |
| B3 | **Band rebalance** — "keep 70/30 XRP/USDT0, rebalance when the band breaks by 5%" | Legible to anyone who has ever had a pension. Low frequency, high notional per execution — good unit economics |
| B4 | **Collateral-ratio defence / auto-repay** — "if my health factor < 1.4, sell vault shares and repay" | Only meaningful once the user has a loan. Depends on a Flare lending venue being wired (Kinetic). Real, but downstream of a borrow product Trimmy does not yet have |
| B5 | **OCO group** — "take-profit at $4 **or** stop at $0.70, whichever first, then cancel the other" | Not a rule type. It is a *mutual-cancellation group* over two Tier-A/B rules — one field, `cancelGroup` (§3.6) |

**Tier C — trader fantasy for this audience. Support as primitives, never as products.**

| # | Thing | Verdict |
|---|---|---|
| C1 | **TWAP** | Not a rule. It is a **fill strategy** on an action (§3.7). Exposing "TWAP" as a product to a mobile XRP holder is cargo-culting a CEX UI |
| C2 | **Iceberg** | Same — a fill strategy, and one that only makes sense against an order book. On an AMM it is just slicing, which is what `PARTIAL_OK` already does |
| C3 | **Stop-limit** | A stop-loss with `minOut` set. One guard field, not a rule type |
| C4 | **Anything leveraged** | Out of scope, and the XRP Ledger says it does not represent leverage. Adding it would also drag Trimmy from "automation" into "derivatives venue" for regulatory purposes |
| C5 | **Grid trading / bots** | Enormous engineering, tiny audience, and a support burden. It is a *sequence generator over Trimmy rules* — leave it to a future strategy layer or a third party using the same registry |

**Design consequence.** Seven Tier-A rules, five Tier-B, all expressed by one engine. The product
surface is 12 rules; the code surface is one evaluator, ~6 signal sources, ~8 comparators, ~7 action
verbs, ~11 guards. That is the whole point of §3.

---

## 3. The unified rule model

### 3.1 Shape

```
Rule {
  // ── identity and authority ───────────────────────────────────────────────
  id            : bytes32                 // keccak(owner, salt)
  ownerXrpl     : bytes32                 // XRPL account id
  account       : address                 // PersonalAccount (Smart Accounts)
  armedAtBlock  : uint64
  armingTxId    : bytes32                 // XRPL tx that armed it — the audit anchor

  // ── where the money is between executions ────────────────────────────────
  funding       : Funding

  // ── when to look ─────────────────────────────────────────────────────────
  trigger       : Trigger

  // ── whether to fire ──────────────────────────────────────────────────────
  condition     : Predicate               // pure; over Signals, Consts, and State

  // ── what to do ───────────────────────────────────────────────────────────
  action        : Action                  // an ordered, atomic batch + fill strategy

  // ── what must never happen ───────────────────────────────────────────────
  guards        : Guards

  // ── how many times ───────────────────────────────────────────────────────
  lifetime      : Lifetime

  // ── what it remembers ────────────────────────────────────────────────────
  state         : RuleState               // engine-owned, mutable
  status        : Status
}
```

The rest of §3 defines each field. The claim to check the design against: **every row of §2 must be
expressible without adding a field, and no row may require a code branch named after it.**

### 3.2 Signals — the only way a rule sees the world

A `Signal` is a typed, sourced reading resolved at evaluation time. Every signal resolves to
`(int256 value, uint8 decimals, uint64 observedAt, bool ok)`. `ok == false` is not an exception; it is
data, and it flows into the guard layer (§3.5) as `ORACLE_STALE` or `SOURCE_UNAVAILABLE`.

| Kind | Source | Resolution | Latency / trust | Which rules use it |
|---|---|---|---|---|
| `PRICE(feedId)` | **FTSO v2** `getFeedById(bytes21)` on `FtsoV2` (Flare mainnet `0x7BDE3Df0624114eDB3A67dFe6753e62f4e7c1d20`, resolved from ContractRegistry `0xaD67…6019`) | on-chain, free, in the same tx as execution | **Measured: feed timestamp advances every block; over 8 samples across ~29s the XRP/USD feed moved between 1.049060 and 1.049700 (±3.0 bps) and updated on essentially every block. 25 blocks in 29s ⇒ ~1.16 s/block.** `[Measured — live poll of FtsoV2 XRP/USD, Flare mainnet, blocks 66,760,588–66,760,613, 2026-08-06]` | A2, A3, B1, B2, B3 |
| `CLOCK` | `block.timestamp` | on-chain, free | block granularity | A4, A6, A7 |
| `BALANCE(token, holder)` | ERC-20 `balanceOf` | on-chain, free | exact | A1, A5, B3 |
| `POSITION(vault, holder)` | vault `convertToAssets(shares)` | on-chain, free | exact | A1, B3, B4 |
| `HEALTH(market, holder)` | lending market view | on-chain, free | exact | B4 |
| `XRPL_PAYMENT(filter)` | **FDC** `Payment` / `XRPPayment` attestation | requires an FDC round + Merkle proof supplied by the executor | minutes; costs an attestation | A5, A7 (heartbeat) |
| `XRPL_NONPAYMENT(filter)` | **FDC** `ReferencedPaymentNonexistence` / `XRPPaymentNonexistence` (type `0x09`) | same | minutes | A7 (proof of *no* heartbeat) |
| `WEB2(jq)` | **FDC** `Web2Json`, `sourceId = PublicWeb2` | same | **public by construction — any API key in the header is public** | public-data rules |
| `PRIVATE(extId, key)` | **FCC** TEE extension | attested result from an enclave; credential never leaves | seconds–minutes | the Bounty-2 rules: payday-detection, exchange-balance, invoice-paid |
| `STATE(field)` | the rule's own `RuleState` | on-chain, free | exact | B2 (peak), A4/A6 (nextRunAt), A7 (lastHeartbeat) |

**Opinion.** `STATE` being a first-class signal source is what removes the trailing-stop special case.
A trailing stop is `PRICE(XRP/USD) < STATE(peak) * (1 - δ)`. Nothing about it is structurally
different from a stop-loss; only one operand changed from a constant to a state field.

**Opinion.** `PRIVATE` must present exactly the same interface as `PRICE`. If the FCC extension
returns anything richer than `(value, decimals, observedAt, ok)` plus an attestation blob, the engine
grows a second evaluator and the whole design collapses. Push all TEE-specific structure into the
extension; the rule sees a number.

### 3.3 Predicate — a tiny expression tree, evaluated on-chain

```
Predicate =
  | Cmp(lhs: Operand, op: Op, rhs: Operand)
  | And(Predicate, Predicate)
  | Or (Predicate, Predicate)
  | Not(Predicate)
  | Always

Operand =
  | Sig(Signal)
  | Const(int256, decimals)
  | State(field)
  | Scaled(Operand, bps)          // e.g. Scaled(State(peak), 8500) = peak * 0.85
  | Delta(Operand, Operand)       // a - b, decimal-normalised

Op = LT | LTE | GT | GTE | EQ_WITHIN(bps) | CROSSED_DOWN | CROSSED_UP
```

Two operators earn their place and are not sugar:

- **`CROSSED_DOWN` / `CROSSED_UP`** are *edge*-triggered, not level-triggered. They compare the
  signal now against the signal at the previous evaluation (kept in `RuleState.lastObserved`). Without
  them, a level-triggered recurring rule fires on every single evaluation while the level holds, and
  the only defence is a cooldown, which is a blunt instrument that also suppresses legitimate repeats.
  With them, "buy the dip every time it crosses below $0.80" means what a human means.
- **`EQ_WITHIN(bps)`** is what a band rebalance needs. `Not(EQ_WITHIN)` is the "band broken"
  predicate for B3, so B3 needs no new machinery.

**Decimal discipline.** Every operand carries its own `decimals`; the comparator normalises to the
larger of the two before comparing, in `int256`, with no implicit truncation. FTSO returns
**decimals as `int8` and it varies per feed** — the live read showed XRP/USD at `decimals = 6` and
FLR/USD at `decimals = 8` on the same contract in the same block. `[Verified — live FtsoV2 read,
Flare mainnet, 2026-08-06]` A model that assumes 18 or assumes uniformity is wrong on the very first
feed pair. This is a real bug class, not a formality.

### 3.4 Trigger, and the two-output evaluation

A `Trigger` says *when the engine is allowed to look*. It is deliberately cheap and separate from the
predicate, because looking is free but proving is not.

```
Trigger =
  | ON_BLOCK                        // every keeper poll; predicate over on-chain signals only
  | ON_SCHEDULE(cron | interval)    // wake at nextRunAt
  | ON_ATTESTATION(kind, filter)    // wake when an FDC/FCC attestation matching filter is delivered
  | ON_EVENT(address, topic0)       // wake on a Flare log (e.g. yield harvested, loan updated)
```

Rules whose predicate needs only on-chain signals use `ON_BLOCK` and cost nothing to evaluate. Rules
that need FDC or FCC use `ON_ATTESTATION`, and the attestation is *pushed* by whoever is willing to
pay for it (the executor, reimbursed from the fee). This split is what keeps a $50 DCA rule from
paying for an attestation it does not need.

**The central mechanism.** Evaluation is:

```
evaluate(rule, now) -> (StateDelta delta, bool fire, Reason reason)
```

`delta` is applied **always**. `fire` gates the action. This one signature is the entire reason
trailing stops, DCA schedules, heartbeats, round-up accumulators and rebalance bands are not five
separate subsystems:

| Rule | `delta` (applied every evaluation) | `fire` |
|---|---|---|
| Stop-loss | `lastObserved := price` | `price < k` |
| Trailing stop | `peak := max(peak, price)` (ratcheted, §4.1) | `price < peak*(1-δ)` |
| DCA | — | `now >= nextRunAt`; on fire, `nextRunAt += period` |
| Dead-man | `lastHeartbeat := max(lastHeartbeat, attestedPaymentTime)` | `now - lastHeartbeat > period` |
| Round-up | `pending += ceil(amt) - amt` | `pending >= minSweep` (then `pending := 0`) |
| Rebalance | `lastObserved := weight` | `|weight - target| > band` |

Six rules, one function, no branches named after products.

### 3.5 Actions

```
Action {
  verb    : Verb
  operand : Amount          // ABS(x) | PCT_OF(source, bps) | ALL | UP_TO(x) | ROUNDUP_REMAINDER
  route   : Route           // venue + path + fill strategy
  sink    : Sink            // where the output goes
}

Verb = SWAP | DEPOSIT_VAULT | WITHDRAW_VAULT | REDEEM_TO_XRPL | TRANSFER_FLARE
     | REPAY | CLAIM | COMPOUND

Sink = SAME_ACCOUNT | VAULT(id) | XRPL(address, destinationTag?) | FLARE(address) | REARM(childRuleId)
```

All verbs compile to a `Call[]` batch on the user's `PersonalAccount` via `executeUserOp(Call[])` —
the same EIP-4337-style entry point that a `0xFE` custom instruction uses. `[Verified —
flare-smart-accounts: `struct Call { address target; uint256 value; bytes data; }` and
`function executeUserOp(Call[] calldata _calls) external payable;`]`

**`REARM` is the composition primitive.** A take-profit ladder (A2) is one rule whose sink re-arms
the next rung. A sliced stop-loss is one rule whose sink re-arms the remainder. A grid bot, if anyone
ever wants one, is a generator over `REARM`. This is how the product gets a large surface from a small
engine, and it is why `REARM` is in v1 even though no v1 UI exposes it directly.

**The FAssets quantisation constraint, which the UI must respect.**
`REDEEM_TO_XRPL` is **quantised to lots, and 1 lot = 10 XRP** (≈ $10.49). Redemption also charges
**0.2%**. `[Verified — dev.flare.network/fassets/operational-parameters, Flare Mainnet: lot size
10 XRP, minting cap 170M XRP, redemption fee 0.2%, collateral reservation fee 0.01%, redemption
payment extension 45s; direct minting: minimum minting fee 0.1 XRP, minting fee 0.1%, executor fee
0.2 XRP; vault minimal CR 1.2, pool minimal CR 1.5]`

Consequence: **a recurring payout (A6) below 10 XRP per execution cannot settle to the XRPL at all.**
The engine must either accumulate to a lot boundary or refuse to arm. Silently rounding is
unacceptable. This is exactly the class of footgun Plimsoll exists to catch, and it belongs in the
arming preflight, not in a runtime revert.

### 3.6 Guards — the field that makes this safe to hand a stranger

```
Guards {
  maxNotionalPerExec   : uint128   // in USD-equivalent at FTSO
  maxNotionalTotal     : uint128   // lifetime budget
  minOut               : uint128   // absolute floor on the output; this is "stop-limit"
  maxSlippageBips      : uint16    // vs FTSO mid at execution
  oracleMaxStaleness   : uint32    // seconds; reject if observedAt is older
  oracleDeviationBips  : uint16    // reject if |FTSO - venue spot| exceeds this
  maxGasPriceWei       : uint128   // do not execute into a fee spike
  cooldownSeconds      : uint32
  notBefore, notAfter  : uint64
  venueAllowlist       : address[] // no rule may ever route somewhere the user did not name
  cancelGroup          : bytes32   // OCO: first member to fire cancels the rest
  pauseIfCrBelow       : uint16    // FAssets agent collateral-ratio circuit breaker
}
```

Four opinions here, each of which I would defend in review:

1. **`oracleDeviationBips` is mandatory and non-zero.** FTSO is the trigger; the DEX is the venue.
   They are different price surfaces. A rule that trusts FTSO and executes on a DEX without checking
   that the two agree is a free option for anyone who can move the shallower of the two. The measured
   30-second FTSO band of ±3 bps `[Measured, §3.2]` sets the floor — a deviation guard tighter than
   ~10 bps will produce constant false blocks; I would ship **50 bps** as the default and let a rule
   raise it.
2. **`venueAllowlist` is not optional and is not a global.** It is per-rule and it is signed into the
   arming payment's hash commitment. A keeper — including ours — must be structurally incapable of
   routing a user's stop-loss through a venue the user never authorised. This is the single sentence
   that makes "the keeper is centralised at demo time" a survivable answer to a judge.
3. **`minOut` deletes the stop-limit rule type.** Stop-limit is stop-loss + `minOut`. If it needs its
   own type, the model is wrong.
4. **`maxGasPriceWei` matters more on Flare than it looks.** Measured over 40 recent mainnet blocks,
   `baseFeePerGas` sat at a hard **500 gwei** floor (median 500, min 500, max 504.3) while the
   **median effective gas price paid was 1,500 gwei and the max was 9,931 gwei** — a 6.6× spread
   driven entirely by priority tips. `[Measured — 237 contract-call transactions across Flare mainnet
   blocks 66,760,388–66,760,428, receipts read via `eth_getTransactionReceipt`, 2026-08-06]` A rule
   that does not cap gas price will occasionally pay 20× for the same execution.

### 3.7 Fill strategy — where TWAP, iceberg and partial fills go to die

```
Route {
  venue      : address
  path       : bytes
  fill       : ALL_OR_NOTHING
             | PARTIAL_OK(minFillBips)
             | SLICED(n, everySeconds, minFillBips)   // ← TWAP and iceberg both live here
  deadline   : uint32
}
```

`SLICED(n, every, minFill)` is implemented as: execute slice 1, then `REARM` a child rule with
`lifetime.maxExecutions = n-1`, `trigger = ON_SCHEDULE(every)` and the parent's guards inherited.
**TWAP is therefore not a rule type, not a code path, and not a UI concept — it is three integers on a
route.** So is iceberg. So is "my stop-loss was too big for the pool."

This is the second load-bearing generalisation in the spec, alongside §3.4.

### 3.8 Lifetime and status

```
Lifetime { repeat: ONE_SHOT | EVERY(period) | UNTIL_EXHAUSTED(budget) | WHILE(Predicate)
           maxExecutions: uint32, expiry: uint64 }

Status = ARMED | COOLING | NEEDS_ATTENTION | EXHAUSTED | EXPIRED | CANCELLED | COMPLETED
```

`WHILE(Predicate)` is what makes B4 (collateral defence) and A1 (auto-earn above a floor) one thing:
"keep doing this as long as X." It also gives a clean, non-hacky "stop DCA-ing if I have run out of
stablecoin" without inventing a termination reason.

### 3.9 The taxonomy, compiled

Proof that the model is general. No row needs a field that another row does not.

| Rule | Trigger | Condition | Action | Key guards | Lifetime | State used |
|---|---|---|---|---|---|---|
| A1 auto-earn | `ON_BLOCK` | `BALANCE(FXRP) > Const(floor)` | `DEPOSIT_VAULT(PCT_OF(bal,10000))` | cooldown 1d | `WHILE(true)` | — |
| A2 TP ladder | `ON_BLOCK` | `PRICE(XRP) CROSSED_UP Const(k₁)` | `SWAP(PCT_OF(pos,1000)) → REARM(rung₂)` | maxSlip, minOut, dev | `ONE_SHOT` | `lastObserved` |
| A3 dip buy | `ON_BLOCK` | `PRICE(XRP) CROSSED_DOWN Const(k)` | `SWAP(ABS(200 USDT0))` | maxSlip, cooldown | `UNTIL_EXHAUSTED(budget)` | `lastObserved` |
| A4 DCA | `ON_SCHEDULE` | `CLOCK >= State(nextRunAt)` | `SWAP(ABS(20 USDT0)) → VAULT` | maxSlip, maxNotional | `EVERY(7d)`, maxExec 52 | `nextRunAt` |
| A5 round-up | `ON_ATTESTATION(XRPPayment)` | `State(pending) >= Const(minSweep)` | `DEPOSIT_VAULT(ABS(pending))` | maxNotional | `WHILE(true)` | `pending` |
| A6 drip payout | `ON_SCHEDULE` | `CLOCK >= State(nextRunAt) AND POSITION(vault) >= 10 XRP` | `WITHDRAW_VAULT → REDEEM_TO_XRPL(rXYZ)` | lot-quantisation preflight | `EVERY(30d)` | `nextRunAt` |
| A7 dead-man | `ON_SCHEDULE(1d)` | `CLOCK - State(lastHeartbeat) > Const(180d)` | `WITHDRAW_VAULT(ALL) → REDEEM_TO_XRPL(rHEIR)` | notBefore, 14-day grace | `ONE_SHOT` | `lastHeartbeat` |
| B1 stop-loss | `ON_BLOCK` | `PRICE(XRP) < Const(k)` | `SWAP(PCT_OF(pos, x)) → USDT0` | maxSlip, minOut, dev, gasCap | `ONE_SHOT` | `lastObserved` |
| B2 trailing | `ON_BLOCK` | `PRICE(XRP) < Scaled(State(peak), 8500)` | as B1 | as B1 | `ONE_SHOT` | `peak` |
| B3 rebalance | `ON_SCHEDULE(1d)` | `Not(EQ_WITHIN(500))(weight, target)` | `SWAP(Delta(weight,target))` | maxSlip, cooldown | `WHILE(true)` | `lastObserved` |
| B4 CR defence | `ON_EVENT(market)` | `HEALTH < Const(1.4)` | `WITHDRAW_VAULT → REPAY` | maxNotional | `WHILE(health<1.6)` | — |
| B5 OCO | — | — | — | `cancelGroup` shared | — | — |
| C1 TWAP | — | — | `route.fill = SLICED(n, every, minFill)` | — | — | — |
| C3 stop-limit | — | — | B1 with `guards.minOut` set | — | — | — |

---

## 4. Sharp edges

### 4.1 Trailing stops need memory. Who pays, and who updates it?

This is the hardest problem in the taxonomy and it has a clean answer.

**Naïve options and why they fail.**
- *Keeper stores the peak off-chain and asserts it at execution.* The keeper can then lie about the
  peak in either direction. Unacceptable — it converts a non-custodial product into a trusted one.
- *Contract stores the peak, keeper pokes every block.* At the measured Flare block rate (~1.16 s)
  that is ~2.2M pokes/month. At the measured cost of a 65k-gas poke (**$0.000586 at the median
  effective 1,500 gwei and FLR/USD = $0.0060079**) that is **~$1,300/month per rule**. Absurd.

**The design: an on-chain monotone ratchet with a materiality band.**

```solidity
function ratchet(bytes32 ruleId) external {
    (uint256 p, int8 d, uint64 t) = ftsoV2.getFeedById(rule.feedId);
    require(block.timestamp - t <= rule.guards.oracleMaxStaleness, "stale");
    uint256 cur = normalise(p, d);
    require(cur > rule.state.peak * (BPS + rule.epsBips) / BPS, "immaterial");
    rule.state.peak = cur;
    emit Ratcheted(ruleId, cur);
    _payBounty(msg.sender);            // permissionless, small, fixed
}
```

Three properties, all of which matter:

1. **The contract reads FTSO itself.** The caller supplies no price. A caller can therefore *not lie*
   about the peak — the worst they can do is decline to call.
2. **`ratchet` is permissionless and pays a bounty.** Declining to call is the only attack, and it is
   an attack anyone in the world — including the user's own phone app — can defeat for a few tenths
   of a cent. This is what removes "the keeper is centralised" from the risk register, and it is the
   same trick Beefy uses when it routes 0.5 of its 4.5 percentage points to whoever calls `harvest`.
   `[Verified — Beefy fee split: 3% strategist / 1% treasury / 0.5% harvest caller]`
3. **The number of ratchets is logarithmically bounded, not linear in time.** Because the peak is
   monotone and only moves on a `(1+ε)` step, `n ≤ ⌈ln(P_max/P_arm) / ln(1+ε)⌉` for the whole life of
   the rule, regardless of how long it lives or how often it is polled.

**Measured cost of memory** `[Measured — 65,000 gas per ratchet, Flare mainnet gas prices measured in
§3.6, FLR/USD = $0.0060079 from live FtsoV2]`

| ε (materiality band) | Price run | Ratchets | Cost @ 500 gwei | Cost @ 1,500 gwei |
|---|---|---:|---:|---:|
| 0.25% | 1.2× | 74 | $0.0144 | $0.0433 |
| 0.25% | 5× | 645 | $0.1259 | $0.3778 |
| **0.50%** | **1.2×** | **37** | **$0.0072** | **$0.0217** |
| **0.50%** | **2×** | **139** | **$0.0271** | **$0.0814** |
| **0.50%** | **5×** | **323** | **$0.0631** | **$0.1892** |
| 1.00% | 2× | 70 | $0.0137 | $0.0410 |
| 2.00% | 5× | 82 | $0.0160 | $0.0480 |

**Recommendation: ε = 0.50%, default trailing distance δ ≥ 5%.** The trailing stop is then accurate
to within 0.5% of the true high, and the *entire lifetime memory cost of a trailing stop that rides a
5× run* is **under 19 cents**. Trimmy absorbs it and does not itemise it — it is noise against a
single execution fee (§5). Publish the ε in the UI as "we track your high to within 0.5%", because
saying it is more credible than hiding it, and because a user who wants 0.1% can pay for a tighter
band.

**The residual honest risk:** if literally nobody calls `ratchet` during a spike, the peak is stale
*low*, the stop level sits *lower* than it should, and the user rides further down than they asked.
The failure is directional and it hurts the user, not the protocol — which is exactly the wrong
direction for a trust product, and is why the bounty and the permissionless caller are mandatory
rather than nice-to-have. `[Inference — from the monotone-ratchet construction above]`

### 4.2 Where does the capital sit between executions, and is it earning?

It must earn. A recurring rule that parks idle FXRP for 30 days on a base that is 60% underwater is
insulting. But **yield and latency are in direct conflict, and the conflict is verified, not
theoretical**:

| Venue | Withdrawal | Fee | Can it back a latency-sensitive rule? |
|---|---|---|---|
| PersonalAccount, idle FXRP | instant | 0 | Yes — earns nothing |
| **Firelight stXRP** | **two-phase burn + up to a 2-day cooldown, then claim** | — | **No.** A stop-loss backed by stXRP is a stop-loss that executes two days after the crash |
| **Upshift / earnXRP — requested redemption** | **lag = 86,400 s (24h)**, `requestRedeem` → wait → `claimRedemption` | **0.5% withdrawal fee** (doc example: 1.0 FXRP in, 0.995 out) | **No** for price rules; **yes** for scheduled rules that can request 24h ahead |
| **Upshift / earnXRP — instant redemption** | **immediate**, burns LP and returns assets | **higher than 0.5%, not numerically published** | **Yes**, at a cost that must be modelled |

`[Verified — dev.flare.network/fxrp/upshift/request-redeem for the 86,400 s lag, the 0.5% withdrawal
fee and the `requestRedeem`/`previewRedemption`/`claimRedemption` functions; Firelight docs for the
two-phase burn with a maximum 2-day cooldown; the earnXRP 72-hour standard window with an instant
option is stated in Flare's own launch post.]`
`[Unverified — the exact instant-redemption fee on the Upshift FXRP vault. **Experiment:** call
`previewRedemption` / the instant path on the mainnet Upshift FXRP vault for 1, 100 and 10,000 FXRP
and read the fee off the return value. One `cast call`, five minutes, and it changes the guard
defaults in §4.5.]`

**Therefore the funding block carries a liquidity class, and the arming preflight enforces it:**

```
Funding {
  asset          : address
  custody        : DIRECT | VAULT(id)
  liquidityClass : INSTANT | INSTANT_WITH_FEE(bps) | DELAYED(seconds)
  reserveBips    : uint16      // fraction kept liquid, never deposited
  prefundLead    : uint32      // for DELAYED venues: request withdrawal this early
}
```

Rules for the compiler, which are decisions and not suggestions:

- **A price-triggered rule (A2, A3, B1, B2, B3) may only be armed against `INSTANT` or
  `INSTANT_WITH_FEE`.** Arming a stop-loss against `DELAYED` funding must be **refused at compose
  time with the reason stated**, not accepted and then failed at 3am. This is Plimsoll's job and it is
  the single highest-value preflight check in the product.
- **A schedule-triggered rule (A4, A6) may use `DELAYED` funding**, because the engine knows
  `nextRunAt` in advance. It emits a `WITHDRAW_REQUEST` at `nextRunAt − prefundLead` where
  `prefundLead ≥ lag + margin` (so ≥ 24h + margin for Upshift). This is a **second, engine-generated
  rule**, not a new mechanism — which is the model paying for itself.
- **`reserveBips` is the pragmatic default.** For a DCA rule, keep the next 2 executions' worth
  liquid and vault the rest. The user gets ~96% of the yield and 100% of the punctuality.
- **A7 (dead-man) explicitly wants `DELAYED`.** The 24h/2-day lag is a *feature*: it is a final
  window in which a living user can cancel. Do not treat latency as universally bad.

### 4.3 Partial fills

Handled structurally by §3.7, but the semantics need stating:

- `ALL_OR_NOTHING` — the batch reverts if `amountOut < minOut`. Rule stays `ARMED`, records a
  `GUARD_BLOCKED(SLIPPAGE)` attempt, and **does not** consume an execution from `maxExecutions`.
- `PARTIAL_OK(minFillBips)` — fill what the pool allows down to `minFillBips` of the requested size,
  then **automatically `REARM` the remainder** with the same guards and a cooldown. A stop-loss too
  large for the FXRP/USDT0 pool becomes a self-slicing stop-loss without the user learning a new word.
- `SLICED(n, every, minFill)` — TWAP/iceberg, as above.
- Every partial fill emits `PartialFill(ruleId, filled, remaining, childRuleId)` and the remainder is
  visible in the UI as one rule with a progress bar, not as N rules. **The user's mental model must
  stay "one rule"** even when the engine has decomposed it.

`[Unverified — actual FXRP/USDT0 depth on SparkDEX and therefore the notional at which slicing starts
to matter. **Experiment:** quote `exactInputSingle` on the mainnet SparkDEX FXRP/USDT0 pool for
1k / 10k / 50k / 250k FXRP and record realised price impact; that curve sets the default
`maxSlippageBips` and the auto-slice threshold. The FXRP float is only ~$156.5M `[Verified, §2.1]`,
so this is a real constraint, not a formality.]`

### 4.4 What happens when a rule cannot execute

**No silent failures. Ever.** Every evaluation writes a typed outcome, and the user can see the
history of every attempt, including the ones that did nothing.

| Reason | Consumes an execution? | Status change | Retry | User told? |
|---|---|---|---|---|
| `NOT_DUE` | No | — | next tick | no (noise) |
| `CONDITION_FALSE` | No | — | next tick | no (noise) |
| `COOLING` | No | `COOLING` | after cooldown | in UI only |
| `ORACLE_STALE` | No | — | next tick | after 3 consecutive |
| `ORACLE_DEVIATION` | No | — | next tick | after 3 consecutive |
| `GAS_TOO_HIGH` | No | — | next tick | after 10 consecutive |
| `SLIPPAGE_EXCEEDED` | No | — | next tick, backoff | after 3 consecutive |
| `INSUFFICIENT_BALANCE` | No | `NEEDS_ATTENTION` | on balance change | **immediately** |
| `FUNDS_LOCKED` (vault lag) | No | `NEEDS_ATTENTION` | after unlock | **immediately** |
| `VENUE_PAUSED` / not in allowlist | No | `NEEDS_ATTENTION` | manual | **immediately** |
| `FASSETS_CR_BREACH` | No | `NEEDS_ATTENTION` | on recovery | **immediately** |
| `LOT_QUANTISATION` (redeem < 10 XRP) | No | **refused at arming** | — | at compose time |
| `EXPIRED` | — | `EXPIRED` | never | **immediately** |
| `EXECUTED` | Yes | `COOLING`/`EXHAUSTED`/`COMPLETED` | per lifetime | **immediately** |

Three rules of thumb behind that table:

1. **A blocked execution never consumes `maxExecutions`.** Guards protect the user; they must not
   silently eat the user's budget. A DCA plan that hit slippage on week 3 still buys 52 times.
2. **Escalation is by consecutive-failure count, not by single event.** One stale FTSO read at 04:12
   is noise. Three in a row is an incident. Notification fatigue kills trust in an automation product
   faster than a missed execution does.
3. **The notification channel is the XRPL account the user already has.** A memo-bearing dust payment
   to the user's own XRPL address is a notification that requires no push token, no email, no app
   install, and no new trust relationship — and it lands in Xaman, where they already look. Note the
   Plimsoll dead-zone finding when sizing it: a notification payment must clear the reserve-plus-fee
   dead zone or it is worse than useless.

**A design principle worth writing on the wall.** The engine must be **fail-closed on money and
fail-open on attempts**: it never executes when uncertain, and it never gives up on a rule because a
transient check failed.

### 4.5 The oracle/venue seam, stated as a threat, not a footnote

FTSO is the trigger surface; SparkDEX (or whichever venue) is the settlement surface. Measured, FTSO
XRP/USD moves ±3 bps within 30 seconds and updates roughly every block `[Measured, §3.2]`. Any rule
that triggers on FTSO and settles on an AMM without checking that the two agree is writing a free
option to whoever can move the shallower book. The `oracleDeviationBips` guard (default **50 bps**)
plus `minOut` closes it, and the pair should be **non-optional fields on every `SWAP` action**, not
defaults a rule may set to zero.

### 4.6 Arming has a floor price, and it constrains the whole product

A fee-only `0xFE` arming payment (`netMintAmountXrp: 0`) still costs the **minimum direct minting fee
of 0.1 XRP plus the 0.2 XRP executor fee** ≈ **0.3 XRP ≈ $0.3147** at the live FTSO XRP/USD.
`[Verified fees — dev.flare.network/fassets/operational-parameters; Measured USD — live FtsoV2
XRP/USD = $1.049107, 2026-08-06]`

Consequences the UI must respect:
- A rule whose *total expected notional* is under ~$30 costs the user >1% just to arm. **Refuse to
  arm rules below a stated minimum notional**, and say why. Better to lose the rule than to take
  someone's $5.
- **Batch arming.** One `0xFE` payment carries a `Call[]` batch, so *arming five rules costs the same
  0.3 XRP as arming one.* The UI should therefore push "set up your whole plan, then arm once" rather
  than "arm one rule at a time." This is a real, verified economy of scale and it should shape the
  onboarding flow.
- **Re-arming must not require a new XRPL payment.** The arming user-op grants the Trimmy executor a
  bounded, rule-scoped authorisation; edits within those bounds (raise a stop level, change a
  schedule) are signed off-chain against the same authorisation. Edits that *widen* the bounds require
  a new arming payment. This is the difference between a product people keep using and one they arm
  once and abandon. `[Inference — from the verified `approve` + inner-call pattern in the Smart
  Accounts fee-only custom instruction docs; the exact authorisation contract is Trimmy's to write.]`

### 4.7 Nonce, and the one operational landmine

`PackedUserOperation.nonce` must equal `getNonce(personalAccount)` at execution. **Two XRPL payments
built against the same `getNonce` will not both land — one reverts with `InvalidNonce` and its XRP
sits at the Core Vault until recovered via a `0xE0` skip-memo payment (which itself must carry a
positive net mint amount, because fee-only direct mints revert).** `[Verified —
flare-smart-accounts, Failure Handling & Recovery]`

For Trimmy this means: **the arming path must serialise per account.** One in-flight arming payment
per XRPL address, ever. The UI must queue rather than allow a user to fire two arming payments while
the first is unconfirmed. This is not a nice-to-have; it is a money-stuck bug that Flare's own docs
call the common cause of reverts, and it is precisely what Plimsoll's BR-5 nonce check exists to
prevent.

---

## 5. Pricing

### 5.1 The measured cost floor

`[Measured — 237 contract-call transactions across Flare mainnet blocks 66,760,388–66,760,428,
receipts read directly, 2026-08-06. FLR/USD = $0.0060079 from live FtsoV2 (decimals 8).]`

| Quantity | Value |
|---|---|
| `baseFeePerGas` | median **500 gwei**, min 500, max 504.3 (a hard floor) |
| Effective gas price actually paid | median **1,500 gwei**, min 500.2, max **9,931** |
| `gasUsed`, contract calls | min 24,698 · p25 28,939 · **median 82,779** · p75 203,464 · p90 537,290 · max 3,091,180 |

| Trimmy operation | Assumed gas | Cost @ 500 gwei | Cost @ 1,500 gwei |
|---|---:|---:|---:|
| `ratchet` (FTSO read + 1 SSTORE) | 65,000 | $0.000195 | $0.000586 |
| Simple execution (transferFrom + swap) | 203,464 (measured p75) | $0.000611 | $0.001834 |
| Full execution (pull + instant vault redeem + swap + fee accrual) | 400,000 | $0.001202 | $0.003605 |
| Heavy execution (p90 observed) | 537,290 | $0.001614 | $0.004842 |
| Worst realistic execution | 800,000 | $0.002403 | $0.007209 |

**Gas is not the cost driver.** A full Trimmy execution costs about **half a cent**. The real
per-execution costs are (a) keeper/RPC infrastructure amortised, (b) FDC attestation fees for rules
that need one, (c) the FCC TEE machine for private-trigger rules, which is a *fixed monthly* cost, not
a marginal one.

`[Unverified — the FDC per-attestation fee. `typeAndSourceFee(bytes32,bytes32)` on
`FdcRequestFeeConfigurations` (Flare mainnet `0x259852Ae6d5085bDc0650D3887825f7b76F0c4fe`) reverted
for `("Payment","XRP")`, `("Web2Json","PublicWeb2")` and `("ReferencedPaymentNonexistence","XRP")` —
either the signature differs from the one I used or those pairs are unconfigured on mainnet.
**Experiment:** pull the verified ABI from the Flare block explorer for that address and re-read, or
read `getRequestFee(bytes)` with a correctly ABI-encoded request body. It moves the marginal cost of
A5 and A7 only.]`

`[Unverified — GCP Confidential Space VM price. Both attempts at cloud.google.com's confidential-VM
pricing page returned 404 or truncated content. **Experiment:** `gcloud compute machine-types
describe` plus the regional SKU from the Cloud Billing Catalog API, or the pricing calculator export.
It sets the fixed monthly floor under the FCC rule class only.]`

### 5.2 The competitive fee board

| Provider | What it automates | Headline price | Custody |
|---|---|---|---|
| **Coinbase recurring buy** | DCA | **~249 bps** (1.99% + ~0.5% spread) | Custodial |
| Coinbase Advanced (manual DCA) | — | 40–60 bps | Custodial |
| **Binance Auto-Invest** | DCA | **10 bps** (7.5 with BNB); periodic 0 bps promos | Custodial |
| **Jupiter DCA / Recurring** | DCA | **10 bps** on order completion | Non-custodial |
| 1inch Limit Order Protocol | limit orders | **0 bps protocol fee** (Fusion: resolver spread in the quote) | Non-custodial |
| **Beefy** | auto-compounding | **450 bps of yield** (300 strategist / 100 treasury / **50 to the harvest caller**) | Non-custodial |
| Yearn | auto-compounding | **2,000 bps of yield** | Non-custodial |
| **Gelato** | generic automation | % **premium on gas** (~2% executor share historically) | Infra |
| Autonomy Network | limit/stop on DEX | gas + executor incentive, no published rate | Non-custodial |
| **Acorns** | round-ups | **$3/month** | Custodial |
| **PiggyVest / Cowrywise** | auto-save | **free**; monetised on float/spread | Custodial |
| **Trimmy (recommended)** | all of the above | **10 bps, floor 0.05 XRP, cap 25 XRP, on success only** | **Non-custodial** |

### 5.3 The three candidate models, evaluated

**(a) Gas-multiple (the Gelato/Autonomy model).** Charge `k × gas`. At $0.0036 of gas, even `k = 10`
yields $0.036 per execution. Correct-shaped for infrastructure sold to developers; **wrong for a
consumer product**, because it prices a $50,000 stop-loss and a $50 DCA identically, and it makes
revenue collapse toward zero exactly because Flare is cheap. **Reject.**

**(b) Subscription (the Acorns model).** $3/month. Acorns proves it works — at 10M users, on a
population with a bank account and payroll. Applied here it fails on three counts: it charges the 60%
who are underwater for a rule that has not fired; it has no denomination story (charge in what? FXRP,
monthly, from a self-custody account — that is a recurring pull authorisation, which is the exact
trust the product exists to avoid); and "pay us monthly to manage your money" walks toward an advisory
framing that a non-custodial rule engine should stay far away from. **Reject as the primary model.**
Keep it in the drawer as a *power-user* SKU (§5.5).

**(c) Basis points of executed notional, success-only.** Matches how the user perceives value
(a stop-loss on $20,000 is worth more than one on $200), matches every crypto comparable in the
board, is denominated in the asset already moving, requires no recurring authorisation, and produces
zero revenue when Trimmy fails — which is the correct alignment for a product whose entire pitch is
trust. **Accept.**

### 5.4 The recommendation, with the arithmetic

> **10 bps of executed notional. Floor 0.05 XRP. Cap 25 XRP. Charged on successful execution only,
> in the output asset. Arming is free beyond the ~0.3 XRP the Flare/FAssets stack itself charges.
> `ratchet` costs are absorbed. No subscription.**

`fee = clamp(notional × 0.0010, 0.05 XRP, 25 XRP)`

| Executed notional | Trimmy fee | Effective rate | vs Coinbase recurring (249 bps) | vs Binance spot (10 bps) | Margin over gas @1,500 gwei ($0.0036) |
|---:|---:|---:|---:|---:|---:|
| $10 | $0.0525 (floor) | 52.5 bps | $0.249 → **4.7× cheaper** | $0.010 → 5.3× dearer | 14.6× |
| $25 | $0.0525 (floor) | 21.0 bps | $0.623 → **11.9× cheaper** | $0.025 → 2.1× dearer | 14.6× |
| $50 | $0.0525 (floor) | 10.5 bps | $1.245 → **23.7× cheaper** | $0.050 → 1.05× dearer | 14.6× |
| **$52.5 (break-even)** | $0.0525 | **10.0 bps** | — | **parity with Binance** | 14.6× |
| $100 | $0.100 | 10 bps | $2.49 → **24.9× cheaper** | parity | 27.7× |
| $500 | $0.500 | 10 bps | $12.45 → 24.9× cheaper | parity | 139× |
| $1,000 | $1.00 | 10 bps | $24.90 | parity | 277× |
| $5,000 | $5.00 | 10 bps | $124.50 | parity | 1,387× |
| $20,000 | $20.00 | 10 bps | $498.00 | parity | 5,548× |
| **$26,228 (cap bites)** | **$26.23** | 10 bps | — | — | — |
| $100,000 | $26.23 (cap) | 2.6 bps | $2,490 → **95× cheaper** | $100 → **3.8× cheaper** | 7,277× |

`[Measured — 10 bps applied to notional; floor 0.05 XRP and cap 25 XRP converted at the live FTSO
XRP/USD of $1.049107; gas cost from the measured p75/400k-gas execution at the measured median
effective 1,500 gwei with FLR/USD = $0.0060079.]`

**Why each number.**

- **10 bps** is deliberately *exactly* Binance Auto-Invest and *exactly* Jupiter DCA. It must never be
  possible for a user to say "I keep it on the exchange because Trimmy is more expensive." At 10 bps
  the answer is "the price is the same and you keep your keys," which is the entire pitch in one
  sentence. Charging 15 or 25 bps would earn ~50–150% more revenue and forfeit that sentence. Not
  worth it.
- **Floor 0.05 XRP (~$0.052)** is 14.6× the measured full-execution gas cost and ~2.6× a $0.02/execution
  amortised keeper cost at 10,000 executions/month on a $200/month keeper. It makes a $10 micro-round-up
  cost 52.5 bps, which is still **4.7× cheaper than Coinbase's recurring buy** — so the floor never
  makes Trimmy the expensive option against the product it is actually replacing.
- **Cap 25 XRP (~$26.23, biting at ~$26,228 notional)** is the deliberate concession. There is no
  cost justification for charging a whale $100 to run the same 400k-gas transaction, and whales are
  the users who most need a stop-loss to work and who most loudly compare fees. Above the cap Trimmy
  is cheaper than Binance. This is a growth decision, taken knowingly.
- **Success-only** is non-negotiable. `GUARD_BLOCKED`, `ORACLE_STALE`, `INSUFFICIENT_BALANCE` and
  every other outcome in §4.4 are free. A product that charges for not doing the thing cannot be
  trusted with the thing.
- **Absorb `ratchet`.** The whole-lifetime memory cost of a trailing stop through a 5× run is
  **$0.19** `[Measured, §4.1]`, against a single execution fee that starts at $0.052 and is typically
  dollars. Itemising it would cost more in user confusion than it recovers.

### 5.5 What is *not* in the recommendation, and why

- **No management fee, no AUM fee.** Trimmy never holds the assets. Charging on AUM would require
  measuring something it does not custody, and invites the advisory framing.
- **No yield performance fee** on A1 auto-earn, even though Beefy gets 450 bps and Yearn 2,000. The
  vault (Firelight/Upshift) already charges; stacking a second performance fee on top of a
  0.5%-withdrawal-fee vault produces a headline APY the user will correctly find insulting. Charge the
  10 bps on the *deposit execution* and stop.
- **Pass-throughs are disclosed, never marked up.** FAssets redemption 0.2%, Upshift withdrawal 0.5%,
  DEX swap fee, FDC attestation fee. These appear as separate, named line items in the preflight
  estimate. Marking up a pass-through is how a trust product dies.
- **Optional second SKU, later, not at launch: "Trimmy Pro", flat ~$5/month, 0 bps.** Break-even
  against 10 bps at ~$5,000 of monthly executed notional, so it is an honest offer to high-frequency
  rebalancers and nobody else. It is a retention product, not an acquisition one, and shipping it in
  v1 would muddy the "we only get paid when it works" message that is the strongest thing about the
  pricing. **Ship 10 bps alone.**

### 5.6 Revenue sanity check, stated as arithmetic rather than hope

FXRP float is **~$156.5M** `[Verified, §2.1]`. Suppose Trimmy reaches the same penetration that all
14 existing wrapped-XRP yield products *together* reached — 14,352 addresses, 0.19% of XRPL wallets —
and suppose the average armed rule executes on $400 of notional, 2× per month.

- 14,352 rules × $400 × 2 = **$11.5M/month executed notional**
- at 10 bps → **$11,482/month**, ~$138k/year `[Measured — arithmetic from the stated assumptions]`

That is a real number and a small one, and stating it honestly is more useful than a TAM slide. The
two levers that matter are **executions per rule per month** (which is a product-design lever: A1, A4
and B3 are recurring; B1 and B2 are one-shot — so the taxonomy should *lead with the recurring rules*)
and **notional per execution** (which is why the cap is at $26k rather than $2.6k). The pricing does
not need to change to make the business work; the **rule mix** does. That is the argument for shipping
Tier A in full rather than shipping two rule types.

---

## 6. Summary of decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | One engine: `on Trigger: if Predicate(Signals, State) then Action with Guards, then StateDelta` | §3; every row of the taxonomy compiles to it with no product-named branches |
| D2 | Evaluation returns `(StateDelta, fire)` separately | §3.4; removes the trailing-stop, DCA-schedule, heartbeat and round-up special cases at once |
| D3 | Fill strategy is a route property, not a rule type | §3.7; absorbs TWAP, iceberg, partial fills and oversized stops |
| D4 | `REARM` sink as the composition primitive | §3.5; ladders, slices and grids become data |
| D5 | Trailing-stop memory via a permissionless, bounty-paid, FTSO-reading monotone ratchet at ε = 0.5% | §4.1; log-bounded cost (<$0.19 through a 5× run), keeper cannot lie about the peak |
| D6 | Funding carries a liquidity class; price-triggered rules may not be armed against `DELAYED` funding | §4.2; verified Firelight 2-day cooldown and Upshift 24h/0.5% make this a correctness issue |
| D7 | `oracleDeviationBips` (default 50) and `minOut` are mandatory on every `SWAP` | §4.5; FTSO-vs-venue divergence is a free option otherwise |
| D8 | No silent failures; blocked attempts never consume `maxExecutions`; escalate on consecutive count | §4.4 |
| D9 | Refuse at compose time: sub-lot `REDEEM_TO_XRPL`, sub-$30 total notional, `DELAYED` funding under a price trigger | §3.5, §4.2, §4.6; this is Plimsoll's job and its best justification |
| D10 | Serialise arming per XRPL account (one in-flight `0xFE` at a time) | §4.7; `InvalidNonce` strands XRP at the Core Vault |
| D11 | **10 bps, floor 0.05 XRP, cap 25 XRP, success-only, no subscription** | §5.4; parity with Binance and Jupiter, 24.9× under Coinbase, 14.6–5,548× over gas |
| D12 | Lead the product with A1/A4/A5 (recurring, non-selling), not B1 (stop-loss) | §2.3, §5.6; matches both the audience's culture and the revenue arithmetic |

---

## 7. Open questions, each with the experiment that settles it

1. **Upshift FXRP instant-redemption fee.** Not published. → `cast call` `previewRedemption` / the
   instant path on the mainnet Upshift FXRP vault at 1 / 100 / 10,000 FXRP. Sets the guard defaults
   and whether B1/B2 can be vault-funded at all.
2. **FXRP/USDT0 depth on SparkDEX.** → quote `exactInputSingle` at 1k / 10k / 50k / 250k FXRP and
   record price impact. Sets `maxSlippageBips` defaults and the auto-slice threshold. FXRP float is
   only ~$156.5M, so this binds sooner than intuition suggests.
3. **FDC per-attestation fee.** `typeAndSourceFee` reverted for the three pairs I tried on mainnet
   `0x259852Ae…c4fe`. → pull the verified ABI from the explorer and re-read, or use
   `getRequestFee(bytes)` with a properly encoded request. Only affects A5/A7 marginal cost.
4. **GCP Confidential Space price.** Pricing pages 404'd / truncated. → Cloud Billing Catalog API or
   `gcloud`. Fixed monthly floor under the FCC rule class only.
5. **Compose→arm conversion by rule type.** No public data exists for any CEX. → instrument Trimmy's
   own funnel from day one and log composes, not just arms. This is also submissible traction
   evidence under the hackathon's user-acquisition criterion.
6. **Does a permissionless `ratchet` bounty actually attract callers at $0.0006/call?** → deploy on
   Coston2, arm 20 trailing stops, publish the bounty, and measure the observed lag between an FTSO
   high and the corresponding `Ratcheted` event. If nobody calls, the fallback is that Trimmy's own
   keeper calls it and the permissionless path remains as the censorship escape hatch.

---

## Sources

- [XRPL — Decentralized Exchange](https://xrpl.org/docs/concepts/tokens/decentralized-exchange)
- [XLS-0078: Subscriptions](https://xls.xrpl.org/xls/XLS-0078-subscriptions.html) · [XLS-0100: Smart Escrows](https://xls.xrpl.org/xls/XLS-0100-smart-escrows.html) · [Known Amendments](https://xrpl.org/resources/known-amendments)
- [Flare — FAssets Operational Parameters](https://dev.flare.network/fassets/operational-parameters)
- [Flare — Upshift Request Redeem](https://dev.flare.network/fxrp/upshift/request-redeem) · [FXRP Overview](https://dev.flare.network/fxrp/overview)
- [Flare — EarnXRP launch](https://flare.network/news/earnxrp-launches-on-flare-the-first-xrp-denominated-yield-product) · [Firelight FAQ](https://docs.firelight.finance/getting-started-with-firelight/frequently-asked-questions-faqs)
- [Flare Smart Accounts — memo-field custom instruction / `executeUserOp`](https://dev.flare.network/smart-accounts/memo-field-custom-instruction)
- [Jupiter — Does Recurring charge any fees?](https://support.jup.ag/hc/en-us/articles/18601113074460-Does-Jupiter-Recurring-charge-any-fees) · [Jupiter Recurring docs](https://developers.jup.ag/docs/recurring)
- [Binance — Auto-Invest](https://www.binance.com/en/support/faq/what-is-auto-invest-and-how-to-use-it-3dd41bc1d4ea4879863ffbf2211a17fe) · [New and Improved Auto-Invest](https://www.binance.com/en/blog/earn/new-and-improved-autoinvest-learn-more-about-the-new-features-8505103344833586172)
- [Coinbase recurring buy cost breakdown](https://www.cryptoryancy.com/coinbase-recurring-buy-fees/) · [Coinbase fees](https://www.datawallet.com/crypto/coinbase-fees)
- [Beefy — Fees Breakdown](https://docs.beefy.finance/ecosystem/beefy-bulletins/beefy-finance-fees-breakdown) · [Yearn/Beefy/Convex comparison](https://www.spark.money/tools/defi-yield-aggregator-comparison)
- [Gelato — pricing & rate limits](https://docs.gelato.network/web3-services/vrf/pricing-and-rate-limits) · [gelato-network README](https://github.com/gelatodigital/gelato-network/blob/master/README.md)
- [1inch Limit Order Protocol / Fusion](https://mixbytes.io/blog/modern-dex-es-how-they-re-made-1inch-limit-order-protocols) · [1inch Fusion FAQ](https://help.1inch.com/en/articles/6800254-1inch-fusion-faq)
- [Autonomy Network — AutoSwap](https://docs.autonomynetwork.io/autonomy-docs/autonomy-network/products/autoswap/how-it-works)
- [Acorns review — pricing and users (NerdWallet)](https://www.nerdwallet.com/investing/reviews/acorns) · [DollarSprout](https://dollarsprout.com/acorns-review/)
- [PiggyVest 2024 Savings Report](https://www.piggyvest.com/reports/2024) · [PiggyVest ₦835bn disbursed](https://techpoint.africa/news/piggyvest-disburses-billions-users/) · [₦2tn payouts](https://technext24.com/2025/01/20/piggyvest-crossed-%E2%82%A62-trillion-payouts/)
- [Cowrywise — automated savings](https://cowrywise.com/blog/what-is-cowrywise/)
- [Sarcophagus — $5.47M raise (Decrypt)](https://decrypt.co/90032/crypto-dead-mans-switch-sarcophagus-raises-5-47m-from-vcs-via-dao) · [Crypto inheritance protocol audit](https://dev.to/duzf8mjxkvea/i-audited-every-crypto-inheritance-protocol-so-you-dont-have-to-58c8)
- Live chain reads, Flare mainnet (chainId 14) via `https://flare-api.flare.network/ext/C/rpc`, 2026-08-06: ContractRegistry `0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019`, FtsoV2 `0x7BDE3Df0624114eDB3A67dFe6753e62f4e7c1d20`, AssetManagerFXRP `0x2a3Fe068cD92178554cabcf7c95ADf49B4B0B6A8`, FXRP `0xAd552A648C74D49E10027AB8a618A3ad4901c5bE`, MasterAccountController `0x434936d47503353f06750Db1A444DBDC5F0AD37c`, FdcHub `0xc25c749DC27Efb1864Cb3DADa8845B7687eB2d44`, FdcRequestFeeConfigurations `0x259852Ae6d5085bDc0650D3887825f7b76F0c4fe`
