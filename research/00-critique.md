# Trimmy research pack — adversarial completeness review

**Date:** 2026-08-06 · **Reviewer:** completeness critic · **Status:** adversarial; findings are ranked by
whether they block shipping, not by how interesting they are.

**Documents reviewed (read in full on disk):**

- `/Users/mac/Documents/codes/opensauce/flare/trimmy/research/keeper-security.md` (1,322 lines)
- `/Users/mac/Documents/codes/opensauce/flare/trimmy/research/rule-taxonomy.md` (883 lines)
- `/Users/mac/Documents/codes/opensauce/flare/trimmy/research/gcp-confidential-space.md` (1,148 lines)
- `/Users/mac/Documents/codes/opensauce/flare/trimmy/research/fcc-extension.md` (1,758 lines)

Every `[Measured]` claim I make below was produced by me on **2026-08-06** against
`https://coston2-api.flare.network/ext/C/rpc` (chainId 114, confirmed) and the Coston2 Blockscout API,
with the exact command shown. Where I could not verify something I say so.

**Overall assessment.** This is a strong pack. `keeper-security.md` is the best document in it and, where
I re-tested it, it holds up under adversarial re-verification. The problem is not rigour inside each
document — it is that **the four documents were written independently, do not agree with each other on
the central architectural question, and collectively left unchecked the one three-minute experiment that
determines whether the headline product can be demonstrated at all.**

---

## 0. The headline

> **There is no FXRP swap venue on Coston2. Not a shallow one — none.** I searched every deployed
> Uniswap-V3-style factory on the chain against FXRP paired with WNAT and three separate USD test
> tokens across four fee tiers: 80 `getPool` calls, **80 zero addresses.** The top 50 FXRP holders
> contain no pool contract of any kind. Both `keeper-security.md` (open question #3) and
> `rule-taxonomy.md` (open question #2) listed "which venue, and how deep?" as unresolved and neither
> ran the check. Six of the twelve rules in the taxonomy — and the entire `execute()` function that
> `keeper-security.md` spends 1,300 lines securing — are swap rules.

Everything else in this review is downstream of that, or of the second finding: **two of the three
design documents specify an execution model that the third one proves cannot be built.**

---

## 1. What is missing

### M1 — The swap venue does not exist on Coston2. `[Measured]` — BLOCKING

Method and raw result:

```bash
# 1. Enumerate every SwapRouter on Coston2 via the explorer, read each one's factory()
curl -s "https://coston2-explorer.flare.network/api/v2/search?q=SwapRouter"
#   -> 0xe2B3aE21..., 0x080D6335..., 0xD50C432f..., 0x20c3cFE7..., 0x06e346eB...
# factory() on each:
#   0x9788c2f246486884ef1F3Da9782674E9b259Cc63
#   0xB1D5c751b5EE5Db2FBBae7Ad32F0b4a3a1161CD1
#   0x9C3AFDDEa87a726891A44C037242393D524CAcFE
#   0x3370ADDC755eC06A8C30D0aba9017cf9407E4521
#   0xc77Aa8Af896E78e31982915Df0EAEEB4bca3C44d

# 2. 5 factories x 4 counter-tokens x 4 fee tiers = 80 getPool calls
FXRP=0x0b6A3645c240605887a5532109323A3E12273dc7
# counter-tokens: WNAT 0xC67DCE33..., testUSDT 0xf3803ECA..., testUSDT0 0x21709E63..., testUSDC 0x30e2F4EC...
# fee tiers: 100 / 500 / 3000 / 10000
cast call $FAC "getPool(address,address,uint24)(address)" $FXRP $TOK $FEE --rpc-url $R
# RESULT: address(0) for all 80 combinations.
```

The three `Router` contracts the explorer returns (`0x78AA7556…`, `0x50302d5C…`, `0xD2a3dBEe…`) either
revert on `factory()` or return undecodable data — they are not V2 routers.

Corroborating read, top 50 FXRP holders (`GET /api/v2/tokens/0x0b6A…3dc7/holders`): the list is EOAs,
`PersonalAccount` proxies, one `FirelightVault`, several `MyERC4626`, one `CollateralPool`, one
`TESTearnXRP`, one `FAssetOFTAdapter`. **No pool contract appears.** The 50th holder holds 1,590 FXRP,
so the ceiling on FXRP held by any pool on Coston2 is under ~1,590 FXRP (~$1,660 at the live feed).

Coston2 FXRP total supply: `4,134,532.695800 FXRP` (6 decimals, `totalSupply()` live). So there are 4.1M
FXRP on the chain and none of it is in a pool.

**Consequence.** `keeper-security.md` §3.5 `execute()` calls
`IRouter(r.venue).swapExactTokensForTokens(...)`. There is no `r.venue`. Rules A2 (take-profit ladder),
A3 (buy-the-dip), A4 (DCA), B1 (stop-loss), B2 (trailing stop) and B3 (band rebalance) are all `SWAP`
verbs. `rule-taxonomy.md` §4.3 and §4.5 specify `maxSlippageBips` defaults and an `oracleDeviationBips`
guard against a venue spot price that does not exist. This is not "the default may be dishonest"; it is
"there is nothing to execute against."

**What does exist on Coston2 and is funded** `[Measured — `asset()` and `totalAssets()` live]`:

| Vault | Address | asset | totalAssets |
|---|---|---|---|
| FirelightVault (proxy) | `0xC90D6847747b85d1fa2E07859869fb9fB72c0361` | FXRP | 100,828.43 FXRP |
| TESTearnXRP | `0x9E63a5D282F2fBb7DcE822B98e363b2719D28319` | FXRP | 7,328.01 FXRP |
| MyERC4626 | `0xF97B2bBdB2f4a561806e5038a503eCA81554634E` | FXRP | 6,209.45 FXRP |

So **yield venues are live and funded; swap venues are absent.** That asymmetry should drive the demo
plan (§4).

### M2 — There are two live MasterAccountControllers on Coston2, and nobody noticed. `[Measured]` — BLOCKING

`keeper-security.md` treats `0x434936d47503353f06750Db1A444DBDC5F0AD37c` as *the* controller.
`rule-taxonomy.md`'s source list cites the same hex as the **Flare mainnet** MasterAccountController.
Both are incomplete. Live reads:

| PersonalAccount | `xrplOwner()` | `controllerAddress()` | `implementation()` | FXRP held |
|---|---|---|---|---|
| `0x4B95de8e7D991eBa793140F13dfC73eAC7E0F457` | `rGrWnRJo77ceUaSUUobmB2JMoFq1muHRMu` | `0x32F662C6…` | `0xb3A633e4…` | **110,108.00** |
| `0x293730Bd7f4C23AE0c325B41f5CB0e40BD7C385A` | **`rGrWnRJo77ceUaSUUobmB2JMoFq1muHRMu`** | `0x434936d4…` | `0xe900cf0C…` | **100,383.51** |
| `0xa52930f85fe71ce586932cfe682e4437a93e66de` | `rKXeXaqGB1Lnbt4SEv397HhcxJKh4hkSwL` | `0x434936d4…` | `0xe900cf0C…` | — |
| `0xcaC1922eE874F14b44f58828a0c460773Da6DbC3` | `rHc5rwf3XS7PHxaJUeiafavZrcvJ7dy8w2` | `0x32F662C6…` | `0xb3A633e4…` | 7,314.54 |

**One XRPL address owns two different personal accounts, on two different controllers, holding 110k and
100k FXRP respectively.** And the derivation function disagrees:

```bash
cast call 0x434936d4… "getPersonalAccount(string)(address)" "rEXAMPLEtestaccount1234567890abcd"
# -> 0xB0046aa502DdB900274CB2294346Bb5664DF7317
cast call 0x32F662C6… "getPersonalAccount(string)(address)" "rEXAMPLEtestaccount1234567890abcd"
# -> 0xF5dAcb32075c62a61370919034bC7e3720875E56
```

The two implementations have **identical ABIs** (I diffed the verified ABIs of `0xe900cf0C…` and
`0xb3A633e4…` — same 18 functions), so this is a parallel/redeployed stack, not a version fork. That
makes it *more* dangerous, not less: nothing in the interface tells you which one you are on.

**Consequence.** `Trimmy.arm()` binds a rule to `msg.sender`. If the arming payment routes through
controller A while the user's FXRP sits in the account under controller B, `arm()` succeeds, the
allowance is set on an empty account, and **every execution reverts on `transferFrom` forever.** The
failure is silent at arm time and permanent at run time. No document mentions that more than one
controller exists.

### M3 — The counter-asset is unspecified, and the oracle floor silently assumes a peg

`keeper-security.md` §3.5 step 5 computes `oracleOut = _quote(amount, price, dec, r.sellToken,
r.buyToken)` from a **single** FTSO read (`r.feedId`, e.g. XRP/USD). A quote needs both legs. The only
way one feed suffices is if `buyToken` is assumed to be worth exactly $1. That assumption is nowhere
stated, is not validated at arm time, and sits inside the function that is the product's headline
security parameter.

Compounding it: `rule-taxonomy.md` names `USDT0` throughout with no address. On Coston2 the explorer
returns at least five distinct "USDC" tokens and three "testUSDT" variants, all participant-deployed
`[Measured — explorer search]`. Nobody chose one, and nobody checked whether the chosen one has an FTSO
feed. **Either the floor needs a second `getFeedById` call for the buy leg, or the contract must
enforce that `buyToken` is a member of a hard-coded USD-pegged set — and the choice must be written
down.**

### M4 — The keeper is asserted, never designed or costed

`keeper-security.md` establishes that `execute()` should be permissionless and that the keeper is "a
convenience, not a capability" — correct. It then never says what the keeper *is*.
`rule-taxonomy.md` §5.4 asserts "a $200/month keeper" at "10,000 executions/month" with no derivation.

Unanswered: how does a keeper enumerate armed rules (event scan? an indexer? the Flare indexer DB?); at
a 1.87s block time, does it simulate every armed rule every block; what is the per-block RPC cost at
N=100 / N=1,000 rules; what is the latency budget between an FTSO tick crossing a trigger and the
`execute()` landing, and how does that compare to the `maxFeedAge` it must satisfy. For a stop-loss
product the answer to the last one *is* the product quality, and it is unmeasured.

### M5 — The Plimsoll integration is load-bearing and entirely unspecified

Both `keeper-security.md` (T6, A6, checklist ×3) and `rule-taxonomy.md` (D9) name Plimsoll as the
mitigation for the highest-severity residual risk: the user signs 42 opaque bytes in Xaman. The
requirement is repeated at least five times ("Plimsoll must decode the batch and display every `approve`
target and amount, the `receiver`, the `venue`, and the lifetime cap"). **Nothing anywhere states how.**
Plimsoll validates `0xFE`/`0xFF` Smart Accounts instructions generically; decoding `Trimmy.arm(RuleParams)`
into plain language requires Trimmy-specific ABI knowledge and a versioning story for when the deployed
Trimmy is newer than the Plimsoll that decodes it. This is a build task of unknown size on the critical
path of the trust argument.

### M6 — The first-run user journey is never walked end to end

The pitch is "a single XRPL payment arms a rule." A stop-loss on FXRP presupposes the user *has* FXRP in
their personal account. Getting FXRP requires minting, which is lot-quantised (`lotSize()` on
`AssetManagerFXRP 0xc1Ca88b937d0b528842F95d5731ffB586f4fbDFA` returns `1e7` AMG `[Measured]`; mainnet lot
= 10 XRP `[their verified read]`) and carries the 0.1 XRP minimum mint fee + 0.2 XRP executor fee. So the
honest first-run flow is **at least two XRPL payments** — mint, then arm — and possibly three if the
user's FXRP lands under the wrong controller (M2). The one-payment claim is true of the *arming step*
only. No document walks the whole path, and the demo script will collide with this on day one.

### M7 — No regulatory or duty-of-care framing at all

Tier A includes A7, a dead-man switch that transfers a user's entire holding to a named heir — a
testamentary instrument. `rule-taxonomy.md` §5.3(b) notices in one clause that a subscription "walks
toward an advisory framing that a non-custodial rule engine should stay far away from" and then drops
the subject. A stop-loss product with a published fee schedule, a keeper the operator runs, and an
inheritance feature deserves at least a stated position. Not a blocker for a hackathon; a blocker for the
"product must be complete" standard.

### M8 — There is no integrated critical path across the two bounties

`fcc-extension.md` §5.8 has an 8-task plan with several full-day items (async EVAL plumbing alone is
"budget a full day"). Bounty 1 — the executor contract, the keeper, the front end, the Plimsoll
integration, the venue problem (M1) — has **no plan at all** in any document. The two are never
reconciled against each other or against the 2026-08-14 19:59 deadline. Eight days, two bounties, one
team, zero sequencing.

---

## 2. Asserted but unverified

I re-tested the load-bearing claims rather than trusting labels. Two things I expected to break did not,
and I say so; four did.

### Claims that SURVIVED re-verification (credit where due)

- **`executeUserOp` is `onlyController` — fully reproduces.** `[Measured, mine]` Raw `eth_call` with
  selector `0x2b2ee783` on `0xa52930f8…`: from `0x1111…1111` reverts `0x59907813` (`OnlyController()`,
  confirmed via `cast sig`); from `0x434936d4…` returns `0x`. Exactly as the document states. *Note for
  reproducers:* `cast call PA "executeUserOp((address,uint256,bytes)[])" "[]"` computes a different
  selector and fails misleadingly — use raw `eth_call`. **This is the most reliable claim in the pack and
  it is the one that decides the architecture.**
- **FXRP EIP-2612 `permit` really does exist.** `[Measured, mine]` `nonces(address)` returns `0` (not a
  revert) and `permit(...)` with junk reverts `0x822a64c8` = `ERC20PermitInvalidSignature()`. The
  document inferred this from `DOMAIN_SEPARATOR()` alone, which is weak evidence — but the conclusion is
  right, and so is the far more important corollary that `permit` is useless here because the personal
  account is a contract and `permit` uses `ecrecover`.

### U1 — The 29-second FTSO staleness observation does not reproduce, and the metric is wrong anyway

`keeper-security.md` §T4 builds a normative requirement (`maxFeedAge = 60s`, an enforced revert) on a
single sample where `getFeedById` returned a 29-second-old timestamp.

`[Measured, mine]` 12 samples, 2s apart, ~70s wall, same feed and contract
(`FtsoV2 0xC4e9c78E…`, `0x015852502f55534400…`):

```
wall=1786009604 v=1041991 dec=6 ts=1786009598  age=6s
wall=1786009609 v=1041991 dec=6 ts=1786009603  age=6s
wall=1786009620 v=1041991 dec=6 ts=1786009614  age=6s
wall=1786009624 v=1042371 dec=6 ts=1786009618  age=6s
wall=1786009627 v=1042243 dec=6 ts=1786009621  age=6s
wall=1786009634 v=1042370 dec=6 ts=1786009628  age=6s
wall=1786009640 v=1042369 dec=6 ts=1786009634  age=6s
wall=1786009645 v=1042496 dec=6 ts=1786009639  age=6s
wall=1786009649 v=1042877 dec=6 ts=1786009643  age=6s
wall=1786009658 v=1042877 dec=6 ts=1786009652  age=6s
wall=1786009665 v=1043003 dec=6 ts=1786009659  age=6s
wall=1786009670 v=1043130 dec=6 ts=1786009664  age=6s
```

**12 of 12 at exactly 6 seconds, zero variance.** The document's own table shows 7 of 8 at 0–4s. Two
independent runs that disagree on the *modal* age by 2–6 seconds are not measuring the same thing —
because both of us measured `wallclock_of_the_curl − ts`, and **the contract sees
`block.timestamp − ts`**. Those differ by the RPC's block lag plus network RTT. `calculateFeeById`
confirmed still `0` `[Measured, mine]`.

The recommendation (enforce `maxFeedAge` against the third return value) is right and should be kept.
The *evidence* for the specific 60s threshold is one outlier measured with the wrong clock. The stated
experiment must be re-specified to sample `block.timestamp − ts` from inside a contract, not
`date +%s − ts` from a shell.

### U2 — Every `GROUND-TRUTH.md` citation is uncheckable from this repository

`keeper-security.md` cites `plimsoll/docs/GROUND-TRUTH.md` §§1, 4, 5, 6, 7, 8, 10, 11, 18 for its most
operationally decisive numbers: p50 131s / p95 170s settlement, the 0.2 XRP + 1 drop dead zone,
`othersCanExecuteAfterSeconds = 7200`, the 1.87s block time, the 30/30 mint result, the standing public
executor `0x103b3840…`, and the "a payment leaving the executor nothing is never executed" finding that
justifies the entire preflight-refusal design.

`/Users/mac/Documents/codes/opensauce/flare/trimmy/` contains **only** `research/`. The file is not
present. I am not saying the numbers are wrong — they are probably fine — but they are labelled
`[Measured]` against a source no reviewer of this pack can open, and several of them are the sole basis
for normative design decisions (I-4's `MAX_RULE_LIFETIME`, the guardian's justification, the
refuse-to-arm threshold). **They need to be restated with their raw evidence inside the Trimmy pack, or
the pack is not self-supporting.**

### U3 — "Autonomy's documented stop-loss default is `amountOutMin = 0`" is an inference dressed as `[Verified]`

The document quotes Autonomy's own comment: *"The min/max can also be used to limit downside during
flash crashes, e.g. `amountOutMin` could be set to 10% lower than `amountOutMax` for a stop loss, if
desired."* That is a **permissive** comment. The document reads it as evidence that the *default* is
zero and that the mitigation is "opt-in and defaulted off" — a claim the quoted text does not support.
It may well be true of the deployed front end; nothing in the quoted source establishes it. The free-option
argument does not need this claim (the structural point stands on its own), so the safest fix is to
soften the label rather than to defend it.

### U4 — `fcc-extension.md`'s async EVAL model depends on an endpoint the author never read

§5.5b declares the asynchronous design **forced and non-optional** ("Do not attempt a synchronous
`EVAL`. Budget a full day"), and then §5.5b's own closing note says:

> `[Unverified]` The exact request shape of the sign-port endpoint the extension calls to sign an
> arbitrary `ActionResult`. … *Experiment:* read `tee-node/internal/extension/server/server.go`
> `registerRoutes()` in full and mirror the request struct — a 10-minute task.

A 10-minute task that gates a full-day build item, on the critical path, was not done. Everything
downstream (`signViaSignPort`, `postActionResponse`, step 4b of the build plan) is written against an
imagined interface.

### U5 — `gcp-confidential-space.md`'s headline is a census, not a test, and the fallback has no trigger

§2 proves 254 `TEST_PLATFORM` machines currently sit at status `2` and are returned by
`getRandomTeeIds`. That is strong evidence and the correction to the earlier pass was the right call.
But it does **not** prove that *our* `register-tee -command rRap` will complete today, and the document's
own open question #1 concedes this is "the plan's only real risk". Recommendation #2 then says to re-run
the census "on demo day, and again the morning of 2026-08-14" — **by which point the GCP fallback
(quota check → billing upgrade → possible 48h wait, per §6.2) cannot be executed.** The fallback is
costed to the cent and has no decision date. It needs one, and it needs to be several days before the
14th.

### U6 — `rule-taxonomy.md`'s entire cost model is a mainnet measurement inside a Coston2 spec

§3.6, §4.1 and §5.1 measure Flare **mainnet** blocks 66,760,388–66,760,428, price FLR at $0.0060079 from
the **mainnet** FtsoV2 `0x7BDE3Df0…`, and derive every dollar figure — the $0.19 lifetime ratchet cost,
the $0.0036 execution cost, the "14.6× over gas" margin column — from them. The product will be built
and demoed on Coston2, where C2FLR has no price. This is defensible as a mainnet projection and is
probably the right modelling choice, but it is presented without that caveat, and `keeper-security.md`'s
open question #5 ("gas cost of `execute()` on Flare → deploy to Coston2 and measure") is still open.

---

## 3. Contradictions, and which side is right

### C1 — Can anything other than the controller drive the personal account? **This is the fatal one.**

| Document | Claim |
|---|---|
| `keeper-security.md` C1 | **No.** `onlyController`. *"A Trimmy keeper holding any key whatsoever cannot make the personal account do anything."* Therefore: allowance-only, Trimmy pulls with `transferFrom`. |
| `rule-taxonomy.md` §3.5 | **Yes.** *"All verbs compile to a `Call[]` batch on the user's `PersonalAccount` via `executeUserOp(Call[])`"* — for `SWAP`, `DEPOSIT_VAULT`, `WITHDRAW_VAULT`, `REDEEM_TO_XRPL`, `TRANSFER_FLARE`, `REPAY`, `CLAIM`, `COMPOUND`, and `REARM`. |
| `fcc-extension.md` §5.6/§5.7 | **Yes.** `fire()` ends in `_executeRule(ruleId)`; the §5.7 diagram terminates `TrimmyRule.fire(verdict, sig) ──► verify ──► executeUserOp(Call[] calls)`. |

**`keeper-security.md` is right.** I independently reproduced the revert (§2, "claims that survived") and
confirmed the modifier is present in *both* deployed implementations. **Two of the three design documents
specify an execution model that cannot be built.**

This is not a wording problem. It structurally invalidates:

- **`REARM` (D4), and therefore `SLICED`/TWAP/iceberg (D3, §3.7) and `PARTIAL_OK` auto-slicing (§4.3),
  and the A2 take-profit ladder.** A child rule armed by Trimmy has `msg.sender == Trimmy`, not the
  personal account — so `keeper-security.md`'s C3 (*"`Trimmy.arm()` binds a rule to `msg.sender` and that
  is a complete, unforgeable statement of which XRPL user armed this"*) **fails for every rearmed rule.**
  Two of `rule-taxonomy.md`'s twelve headline decisions rest on an authorization the platform does not
  grant.
- **`REDEEM_TO_XRPL` (A6 drip payout, A7 dead-man switch).** Trimmy can pull FXRP via allowance, but then
  *Trimmy* is the FAssets redeemer. Whether the XRP can still be directed to the user's `rHEIR…` address
  depends on the redeem signature accepting a destination — plausible, but **unchecked by anyone**, and
  it changes who the counterparty is.
- **`DEPOSIT_VAULT` (A1, the rule `rule-taxonomy.md` D12 says to *lead with*).** Shares are minted to
  Trimmy, not the user, unless Trimmy explicitly forwards them. That converts "Trimmy never holds the
  assets" (§5.5's stated justification for having no AUM fee) into "Trimmy holds them for one
  transaction". Recoverable, but it must be written down and the fee argument re-made.

### C2 — `maxGasPrice`: mandatory guard or deleted vector?

`keeper-security.md` I-7 and T10: *"Trimmy should not need this modifier, because Trimmy should not
reimburse gas… Charging a fixed fee and letting the keeper bear its own gas **deletes the entire
vector**."* `rule-taxonomy.md` §3.6 opinion 4: *"`maxGasPriceWei` **matters more on Flare than it
looks**"*, backed by a genuinely good measurement (median effective 1,500 gwei vs a 500 gwei base fee
floor, max 9,931 gwei — a 6.6× tip-driven spread), and §4.4 makes `GAS_TOO_HIGH` a first-class outcome.

**`keeper-security.md` is right, and `rule-taxonomy.md` has the wrong payer in mind.** If the keeper bears
its own gas and earns a fee fixed in `buyToken`, a gas spike is the *keeper's* margin problem. Putting
`maxGasPriceWei` on the *user's* rule then does nothing protective and one thing harmful: it makes the
rule unexecutable during exactly the congestion where a stop-loss matters, converting a keeper economics
problem into a user liveness failure. The 6.6× measurement is valuable — keep it, use it to size
`keeperFeeFlat`, and drop the guard.

### C3 — One fee or two? The document contradicts itself internally.

`keeper-security.md` §7 A1 states the finding plainly: under permissionless execution the execution fee
*"will be competed to the gas cost"*, so Trimmy's revenue must be a **separate `protocolFee` committed in
the rule**, and *"`keeperFee` and `protocolFee` are different fees with different economics and the
contract needs both."* But **§3.3's `Rule` struct, in the same document, has `keeperFeeFlat`,
`keeperFeeBips`, `keeperFeeTotalCap`, `keeperFeePaid` — and no protocol fee field at all.** And
`rule-taxonomy.md` D11 sets a single "10 bps, floor 0.05 XRP, cap 25 XRP" whose §5.4 margin column
compares it to *gas* ("14.6× over gas"), i.e. prices it as the keeper fee.

**A1 is right; the struct and D11 are both wrong.** The rule needs four fee fields (keeper flat/bips,
protocol bips + recipient) and the pricing section needs re-deriving, because 10 bps *minus* whatever the
keeper competes down to is Trimmy's actual revenue, and §5.6's $138k/year already-small figure is
therefore an overestimate.

### C4 — "Re-arming must not require a new XRPL payment" — signed by whom?

`rule-taxonomy.md` §4.6: *"edits within those bounds (raise a stop level, change a schedule) are signed
off-chain against the same authorisation."* `keeper-security.md` C1 + §3.6: the user has **no EVM key**;
the only path in is an FDC-attested XRPL payment; even *cancelling* costs one payment and p50 131s.

**`keeper-security.md` is right and `rule-taxonomy.md`'s §4.6 bullet has no signer.** The user's key is an
XRPL key. XRPL's signing scheme is not EIP-191, and a large share of Xaman accounts use **Ed25519**, which
`ecrecover` cannot recover at all. There is no XRPL-signature verifier in any contract described in the
pack. As written, this is not implementable — and it is labelled `[Inference]` while carrying the weight
of *"the difference between a product people keep using and one they arm once and abandon."*

**The fix nobody proposed** is in §5 (A4): generalise the guardian from cancel-only to
**cancel-or-tighten-only**, and let the user name an EVM address at arm time that may lower a cap, raise
a floor, shorten an expiry, or cancel — never the reverse. That is strictly safe by the same argument
that makes the cancel-only guardian safe, and it recovers most of §4.6's product value without inventing
a signature scheme.

### C5 — Do fee-only direct mints work, or revert?

The context brief and `rule-taxonomy.md` §4.6 both build the arming model on *"a fee-only `0xFE` arming
payment (`netMintAmountXrp: 0`)"*. `rule-taxonomy.md` §4.7, six paragraphs later, says of the recovery
path: *"a `0xE0` skip-memo payment (**which itself must carry a positive net mint amount, because
fee-only direct mints revert**)"* `[Verified — flare-smart-accounts, Failure Handling & Recovery]`.

Both cite the same source. They cannot both be right. Either fee-only direct mints revert — in which case
**every arming payment must mint FXRP** and the "arm without minting" premise in the project brief is
wrong — or they don't, and the `0xE0` caveat is wrong. **This is the cheapest contradiction in the pack to
resolve and it sits directly under the product's first sentence.** One Coston2 payment settles it.

### C6 — The two rule structs share almost no fields

`keeper-security.md` §3.3 and `rule-taxonomy.md` §3.1/§3.6 are both presented as the rule model to
implement. They have essentially no overlap: `span` (which `keeper-security.md` calls *"the cleanest
anti-griefing primitive in any of the prior art"*, lifted from CoW) **does not exist** in the taxonomy,
which uses `cooldownSeconds`; `latched` does not exist in the taxonomy; `pathHash` does not exist in the
taxonomy; `oracleDeviationBips`, `pauseIfCrBelow`, `cancelGroup`, `venueAllowlist` and the whole
`Funding`/`liquidityClass` block do not exist in `keeper-security.md`. These were written without
reading each other and **someone has to merge them before a line of Solidity is written.**

### C7 — Does the contract read the venue's price or not?

`rule-taxonomy.md` D7 makes `oracleDeviationBips` (FTSO vs **venue spot**) mandatory on every `SWAP`.
`keeper-security.md` T4 states the opposite rule as a slogan: *"trigger from FTSO, floor from FTSO,
execute on the AMM, and **never let the AMM tell you what anything is worth**."*

**`keeper-security.md` is closer to right.** Reading venue spot to compare against FTSO *is* reading the
AMM. Because the comparison can only cause a revert it is not directly exploitable for theft — but it
hands any attacker who can move the shallow side a cheap, repeatable **censorship** primitive: push the
pool 51 bps off, and every Trimmy stop-loss in that pair is blocked. And `keeper-security.md`'s
`require(minOut >= floorOut)` plus the post-swap `require(out >= floorOut)` already subsume the
protective intent. Ship `keeper-security.md`'s version; drop the deviation guard.

### C8 — The Bounty-2 trust argument evaporates on the configuration the pack recommends shipping

`gcp-confidential-space.md` §9.3 is admirably blunt: under `TEST_PLATFORM` the `codeHash` is the constant
`0x194844cf…`, *"identical across every simulated machine on the network. It therefore **proves nothing
about which code is running.**"* `fcc-extension.md` §5.3's credential protocol, step 2, instructs the user
to *"verify codeHash on-chain — `TeeExtensionRegistry` says this hash is whitelisted for extension
`EXTENSION_ID`. Verify the reproducible build matches our published source. **ONLY THEN proceed**"*, and
calls this *"the part that makes this trustworthy rather than 'trust us'."*

**Under the recommended simulated path, step 2 verifies nothing.** The hash the user checks is shared
with 253 other machines. `fcc-extension.md` never mentions this; `gcp-confidential-space.md` never notes
that its recommendation guts the other document's trust model. A judge who curls `/info`, sees
`0x194844cf…`, and asks *"so what stops you reading the user's Kraken API key?"* currently has no answer.

---

## 4. The single biggest risk, and what to do first

**The biggest risk is not a security property. It is that Trimmy's headline product has no venue to
execute against on the chain it will be demoed on, and the team does not know it yet (M1).** Every
security control in `keeper-security.md` — the oracle-derived floor, `maxSlippageBips`, `pathHash`,
`minOut`, the MEV analysis — protects a swap that cannot happen. A week from the deadline, discovering
this while writing the demo script would be fatal.

Ranked second, and close: **C1** — two documents specify an unbuildable execution model, and the affected
verbs are exactly the non-swap rules that would otherwise be the escape hatch from M1.

### Do this first, in this order

1. **Decide the demo venue today.** Three options; pick one deliberately and state the cost:
   - **(a) Deploy and seed your own FXRP/testUSDT pool on Coston2.** Cheapest, ~1 hour, and the 4.1M FXRP
     float means you can seed it. But every slippage number you then publish is self-dealing, and you
     must say so in the submission or a judge will find it.
   - **(b) Demo Bounty 1 against Flare mainnet**, where SparkDEX FXRP liquidity actually exists.
     `rule-taxonomy.md` §2.1 already reads mainnet. Real money, real risk, no faucet.
   - **(c) Re-cut v1 around the venues that *are* live and funded on Coston2** — the FirelightVault
     (100,828 FXRP), TESTearnXRP (7,328 FXRP) and MyERC4626 (6,209 FXRP), all confirmed ERC-4626 over
     FXRP `[Measured]`. That means leading with **A1 auto-earn, A5 round-up, A6 drip, A7 dead-man** and
     demoting the swap rules to "designed, awaiting venue."
   **Recommendation: (c), with (a) as a clearly-labelled demo pool for one stop-loss.** Option (c) is what
   `rule-taxonomy.md`'s own §2.3 and D12 already argue for on audience grounds ("lead with A1/A4/A5, not
   B1"; "pitching a stop-loss to an XRP HODL audience reads as an insult"). The chain has now
   independently made the same argument. Two independent lines of reasoning converging on the same
   product decision is the strongest signal in this review.
2. **Pin the controller (M2)** and make the arming preflight assert, before the XRPL payment is signed,
   that the personal account it is about to arm is (i) derived from the pinned controller and (ii) holds
   a non-zero balance of `sellToken`. This is a five-line check that prevents a permanent silent failure.
3. **Resolve C1 by rewriting `rule-taxonomy.md` §3.5's action model as allowance-pull**, then re-derive
   which verbs survive. `REARM`, and therefore D3 and D4, currently do not. Do this before merging the
   two rule structs (C6).
4. **Settle C5 with one Coston2 payment.** It is under an hour and it is under the product's first
   sentence.
5. **Set a hard GCP go/no-go date of 2026-08-10** (U5), not demo day.

---

## 5. What everyone assumed that might be false

### A1 — "The arming payment grants a bounded, rule-scoped authorization." — the product's first sentence

The pack's own strongest finding narrows this more than anyone acknowledged. `keeper-security.md` proves
the only durable authorization available is a **plain ERC-20 allowance on one token** (no EIP-3009, no
usable `permit`, no session key, no module system, no delegate). So the honest statement is:

> *Trimmy can automate anything expressible as "spend up to N of token X on this account's behalf."*

It **cannot** automate anything requiring the account to *act*: no vault deposit that mints shares to the
user, no FAssets redemption initiated by the user, no XRPL payout from the user's account, no re-arm.
The pitch in the project brief ("an XRPL payment arms a rule that afterwards executes itself") and the
architecture that is actually available are not the same product, and **every non-swap rule in Tier A
sits on the wrong side of that line.** This is the core-premise attack the brief asked for, and the
answer is: the premise survives, but only for a narrower rule class than the taxonomy claims, and the
narrowing has not been done.

### A2 — "FXRP is a liquid, tradeable asset."

On Coston2, definitively false `[Measured — M1]`. On mainnet, the pack's own numbers make it marginal:
~$156.5M float `[their verified read]` and 14 wrapped-XRP products sharing 14,352 addresses
`[their number]`. `keeper-security.md` T8 identifies the systemic consequence — *"a cluster of stop
losses at a round number is a visible liquidation cascade"* — and `rule-taxonomy.md` §5.6 then prices the
product for a volume that would cause exactly that. Nobody connected the two. Against a $156.5M float, a
product whose success case is "many users arm stop-losses at round numbers" has a self-defeating scaling
law, and the honest cap on the swap-rule business is much lower than the pricing model assumes.

### A3 — "Permissionless execution gives liveness."

`keeper-security.md` argues correctly that permissionless execution takes the damage from a leaked keeper
key to zero. It then reuses the same property as a *liveness* argument ("if our keeper dies, anyone can
execute"). **These are not the same claim, and the pack's own evidence contradicts the second one:**
GROUND-TRUTH §10.3, as quoted, records a payment that left the executor nothing sitting unexecuted for
five minutes, with the conclusion *"a latency figure gathered only from payments somebody wanted to
execute says nothing about the ones nobody does."* Permissionless execution provides liveness only if
someone has already paid the **fixed** cost of building and running a competing keeper. With no venue, no
volume and a $138k/year revenue ceiling (their own §5.6 arithmetic), nobody will. For the hackathon and
well beyond, **Trimmy's keeper is the only keeper.** Say the security claim; do not say the liveness
claim.

### A4 — "The user has no EVM key" is treated as immovable

Everything painful in the design descends from this: the 131-second cancel, the guardian workaround, the
unimplementable §4.6 re-arm (C4), the inability to drive the account. But `keeper-security.md` C2 also
establishes that **the arming batch is completely unrestricted** — arbitrary targets, arbitrary calldata,
atomic. Nobody asked what else that batch could set up.

**The unexplored move: generalise the guardian from *cancel-only* to *monotonically-safe-only*.** A user
names an EVM address at arm time (their own browser key, a hardware wallet, Trimmy's front end) that may
only make a rule **strictly less capable** — lower a cap, raise a floor, shorten an expiry, tighten
slippage, cancel. Never widen anything, never execute, never receive funds. The safety argument is
identical to the one already made for the cancel-only guardian, and it recovers most of §4.6's product
value ("raise a stop level, change a schedule") without an XRPL payment and without inventing a signature
scheme. This looks like the highest-leverage unexamined design move in the pack.

### A5 — "A simulated TEE is good enough for Bounty 2."

`gcp-confidential-space.md` recommends it and is honest about what is lost. But what is lost is precisely
the property the bounty is named after, and — per C8 — it silently voids `fcc-extension.md`'s entire
"trustworthy rather than trust us" argument. The $21/8-day real-hardware path is costed to the cent in
§5.2 and needs one `gcloud` command. **The risky assumption is not the simulation; it is that the
decision can be deferred to demo day** (U5).

### A6 — "Twelve rule types from one engine" is free

`rule-taxonomy.md`'s unification is genuinely good, and its two load-bearing generalisations (§3.4's
state-delta/fire split; §3.7's fill-as-a-route-property) are the best original thinking in the pack. But
§3.7 is implemented via `REARM`, which C1 kills. And what remains — §3.3's predicate tree with
`CROSSED_UP`/`CROSSED_DOWN`/`EQ_WITHIN` and per-operand decimal normalisation, §3.2's nine signal
sources, §3.6's thirteen guards, §3.8's four lifetime modes — is a small virtual machine.
`keeper-security.md` §5.3 says the opposite and is right: *"**Do not ship a general predicate language in
v1** … For an 8-day build, ship two `direction` values plus a time mode, hard-coded."*

Two documents in the same pack, eight days out, one specifying a hard-coded three-branch enum and the
other an expression evaluator. **`keeper-security.md` is right, and the taxonomy's §3 should be reframed
as the v2 architecture with a hard-coded v1 subset called out explicitly** — which is also a better
story for a judge than an unfinished VM.

### A7 — "Permissionless execution and confidential triggers can coexist"

`keeper-security.md` T8 proposes the hybrid: *"private trigger, public bounds — the enclave may choose
the MOMENT, but the contract still enforces floor, notional, expiry, receiver and venue."* This is the
right shape. But note what it costs: the moment a TEE gates `execute()`, the caller is no longer
"anyone" — it is "anyone holding a fresh signed verdict", and verdicts come from one enclave with a
30-minute result TTL `[fcc-extension §5.3, verified]` and a volatile in-memory credential store that a
VM restart wipes `[fcc-extension §5.3, stated]`. So T1's headline result — *"the maximum damage from a
leaked keeper key is exactly zero"* — **does not hold for the FCC rule class**, where the enclave
operator (us) can censor every private-trigger rule by simply not running. `fcc-extension.md`'s own
`MAX_VERDICT_AGE` exists precisely because of this. Neither document states that the two halves of the
product have different trust models. **They do, and the submission should say which rules are in which
class.**

---

## 6. Summary table of findings

| # | Finding | Type | Severity | First action |
|---|---|---|---|---|
| M1 | No FXRP swap venue exists on Coston2 (80/80 `getPool` = 0; no pool in top-50 holders) | Missing | **Blocking** | Choose demo venue today (§4.1) |
| C1 | Two of three docs specify `executeUserOp`-driven execution; `onlyController` forbids it | Contradiction | **Blocking** | Rewrite taxonomy §3.5 as allowance-pull |
| M2 | Two live MasterAccountControllers on Coston2; one XRPL address → two accounts, 110k and 100k FXRP | Missing | **Blocking** | Pin controller + preflight balance assert |
| C5 | "Fee-only mints work" vs "fee-only direct mints revert" — same source, same doc | Contradiction | High | One Coston2 payment |
| C3 | `keeperFee` vs `protocolFee`: doc's own §7 contradicts its own §3.3 struct and D11 pricing | Contradiction | High | Add both fields; re-derive §5.6 |
| C4 | Re-arm "signed off-chain" has no signer (no EVM key; Ed25519 XRPL accounts) | Contradiction | High | Adopt tighten-only guardian (A4) |
| M3 | Counter-asset unspecified; oracle floor silently assumes a $1 peg on the buy leg | Missing | High | Second feed read, or hard-coded pegged set |
| C8 | Simulated TEE makes `fcc-extension` §5.3 step 2 vacuous; Bounty-2 trust argument voided | Contradiction | High | GCP go/no-go by 2026-08-10 |
| U2 | Every GROUND-TRUTH citation is uncheckable from this repo | Unverified | High | Restate raw evidence in-pack |
| M8 | No integrated critical path across two bounties, 8 days | Missing | High | Build one calendar |
| U4 | Async EVAL design rests on an unread sign-port interface | Unverified | Medium | The 10-minute read |
| C6 | The two rule structs share almost no fields | Contradiction | Medium | Merge before any Solidity |
| U1 | 29s FTSO staleness did not reproduce (12/12 at 6s); wrong clock used | Unverified | Medium | Re-measure `block.timestamp − ts` in-contract |
| C2 | `maxGasPrice` mandatory vs deleted | Contradiction | Medium | Drop the guard; keep the measurement |
| C7 | `oracleDeviationBips` mandatory vs "never let the AMM price anything" | Contradiction | Medium | Drop the deviation guard |
| M4 | Keeper never designed or costed | Missing | Medium | Size per-block simulation at N rules |
| M5 | Plimsoll↔Trimmy decoding unspecified but load-bearing for the trust argument | Missing | Medium | Scope it |
| M6 | First-run journey needs ≥2 XRPL payments; pitch says one | Missing | Medium | Rewrite the demo script |
| U6 | Mainnet gas/price model presented inside a Coston2 spec | Unverified | Low | Add the caveat |
| U3 | Autonomy `amountOutMin = 0` default is inference labelled `[Verified]` | Unverified | Low | Soften the label |
| U5 | GCP fallback costed precisely, with no decision date | Unverified | Low | 2026-08-10 |
| M7 | No regulatory framing for an inheritance product | Missing | Low | State a position |

---

## 7. Reproduction commands for my own findings

```bash
export PATH="$PATH:$HOME/.foundry/bin"
R=https://coston2-api.flare.network/ext/C/rpc
FXRP=0x0b6A3645c240605887a5532109323A3E12273dc7

# M1 — no FXRP pool on any Coston2 V3 factory
for FAC in 0x9788c2f246486884ef1F3Da9782674E9b259Cc63 \
           0xB1D5c751b5EE5Db2FBBae7Ad32F0b4a3a1161CD1 \
           0x9C3AFDDEa87a726891A44C037242393D524CAcFE \
           0x3370ADDC755eC06A8C30D0aba9017cf9407E4521 \
           0xc77Aa8Af896E78e31982915Df0EAEEB4bca3C44d; do
  for TOK in 0xC67DCE33D7A8efA5FfEB961899C73fe01bCe9273 \
             0xf3803ECA2C08E5Be901118BD1A6bCB0Cb01B6d6A \
             0x21709E63fC7F264F329e0826Ea82197694B82775 \
             0x30e2F4EcC079D4BD7fABc0fA99de93Bc1FEa2244; do
    for FEE in 100 500 3000 10000; do
      cast call $FAC "getPool(address,address,uint24)(address)" $FXRP $TOK $FEE --rpc-url $R
    done; done; done   # all zero

curl -s "https://coston2-explorer.flare.network/api/v2/tokens/$FXRP/holders"   # no pool in top 50

# M2 — two controllers, one XRPL address, two accounts
for PA in 0x4B95de8e7D991eBa793140F13dfC73eAC7E0F457 0x293730Bd7f4C23AE0c325B41f5CB0e40BD7C385A; do
  cast call $PA "xrplOwner()(string)"         --rpc-url $R
  cast call $PA "controllerAddress()(address)" --rpc-url $R
  cast call $PA "implementation()(address)"    --rpc-url $R
done
cast call 0x434936d47503353f06750Db1A444DBDC5F0AD37c "getPersonalAccount(string)(address)" "rEXAMPLEtestaccount1234567890abcd" --rpc-url $R
cast call 0x32F662C63c1E24bB59B908249962F00B61C6638f "getPersonalAccount(string)(address)" "rEXAMPLEtestaccount1234567890abcd" --rpc-url $R

# C1 confirmation — use raw eth_call; `cast call` computes the wrong selector for this signature
D=0x2b2ee78300000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000
curl -s -X POST $R -H 'content-type: application/json' -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_call\",\"params\":[{\"from\":\"0x434936d47503353f06750db1a444dbdc5f0ad37c\",\"to\":\"0xa52930f85fe71ce586932cfe682e4437a93e66de\",\"data\":\"$D\"},\"latest\"]}"   # -> "0x"
curl -s -X POST $R -H 'content-type: application/json' -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_call\",\"params\":[{\"from\":\"0x1111111111111111111111111111111111111111\",\"to\":\"0xa52930f85fe71ce586932cfe682e4437a93e66de\",\"data\":\"$D\"},\"latest\"]}"   # -> 0x59907813

# FXRP permit really exists
cast call $FXRP "nonces(address)(uint256)" 0x1111111111111111111111111111111111111111 --rpc-url $R   # 0, not a revert
# permit(...) with junk -> 0x822a64c8 = ERC20PermitInvalidSignature()

# Live ERC-4626 FXRP vaults (the venues that DO exist)
for V in 0xC90D6847747b85d1fa2E07859869fb9fB72c0361 \
         0x9E63a5D282F2fBb7DcE822B98e363b2719D28319 \
         0xF97B2bBdB2f4a561806e5038a503eCA81554634E; do
  cast call $V "asset()(address)" --rpc-url $R; cast call $V "totalAssets()(uint256)" --rpc-url $R
done
```

---

## 8. What this review did not check

Stated plainly so the next reviewer knows where the holes are.

- `plimsoll/docs/GROUND-TRUTH.md` — **not present on this machine.** All settlement-latency, dead-zone,
  executor-pin and block-time figures in `keeper-security.md` are unverified from here (U2).
- The Flare mainnet reads in `rule-taxonomy.md` §2.1 and §5.1 — I worked on Coston2 only.
- The Go/TEE source claims in `fcc-extension.md` — I did not clone `tee-node`, `tee-proxy` or
  `go-flare-common`. The document's re-verification pass reads as careful and I have no reason to doubt
  it, but I did not independently confirm `ProxyTimeout = 2s`, the two-signature footgun, or the
  `/direct` message-shape finding. Those are the three findings most worth a second reader.
- GCP pricing tables in `gcp-confidential-space.md` — not re-fetched. The arithmetic in §5.2 checks out
  against the stated unit prices.
- Whether `AssetManager.redeem` accepts a third-party redeemer with a user-specified XRPL destination —
  this is the experiment that determines whether A6/A7 survive C1, and nobody has run it.
