# 02 — Architecture attack

**Date:** 2026-08-06 · **Network:** Coston2 (chainId 114) · **Posture:** hostile by assignment.
**Target:** the corrected architecture. `research/01-ARCHITECTURE.md` **does not exist on disk** — see
§0. The design under attack is therefore reconstructed from the three documents that *do* specify it:
`keeper-security.md` §3.1–§3.7 and §4 (the `Rule` struct, `arm()`, `execute()`, the twelve invariants),
`docs/GROUND-TRUTH.md`, and `AGENTS.md` §"Rules that encode real findings". Where those disagree I
attack the version in `keeper-security.md` §3.5, because it is the only executable specification in
the pack.

Labels: `[Verified]` primary source or live chain · `[Measured]` computed by an experiment described
here · `[Inference]` reasoned from stated verified facts · `[Unverified]` open, with the experiment named.

Every `[Measured]` result below was produced by me on **2026-08-06** against
`https://coston2-api.flare.network/ext/C/rpc`, with the command or script shown.

---

## 0. The finding that precedes all the others

**`research/01-ARCHITECTURE.md` does not exist.** `[Verified — `find` over `trimmy/`, 2026-08-06]`

```
trimmy/AGENTS.md
trimmy/docs/GROUND-TRUTH.md
trimmy/research/{00-critique,00-tee-cost-decision,controller-canonical,
                 fcc-extension,ftso-in-contract,gcp-critique...,keeper-security,
                 rule-taxonomy,venues-and-pool}.md
```

`AGENTS.md` links to it twice as the normative design ("read in this order… 2. `01-ARCHITECTURE.md` —
the corrected design"). `00-critique.md` §4 lists five things to do "first", of which items 1, 3 and 4
are *design decisions that were supposed to land in that file*. **Eight days from the deadline there is
no merged architecture — there are three mutually contradictory ones and a critique of them.**

This is not a documentation complaint. Every finding below is a defect in a *specification the team
believes is settled*. Because it is unmerged, `00-critique.md`'s own C6 ("the two rule structs share
almost no fields… someone has to merge them before a line of Solidity is written") is still open, and
the merge is where half of these bugs get fixed or permanently baked in. **Fix: write
`01-ARCHITECTURE.md` before any Solidity, and treat this document as its input.**

---

## 1. Severity ranking

| # | Finding | Class | Severity | Extractable / cost |
|---|---|---|---|---|
| **A1** | `venue`, `buyToken` and `receiver` are free `address` fields chosen by the front end; a malicious or compromised front end drains `totalSellAmount` with every invariant satisfied | Money / authz | **Critical** | 100% of every armed allowance |
| **A2** | The oracle-derived floor is a *publicly computable target price*; any observer atomically pushes the pool to exactly `floorOut` and pockets the whole slippage band. Needs no keeper key. | Money / MEV | **Critical** | `Σ totalSellAmount × price × maxSlippageBips/10⁴`, riskless |
| **A3** | `execute()` calls `swapExactTokensForTokens` — **no router deployed on Coston2 has that function.** All five are V3 (`exactInput`/`exactInputSingle`) | Premise | **Critical** | Demo does not run |
| **A4** | `maxWithdraw()` and `maxRedeem()` are **0 on all three FXRP vaults**. No vault-exit rule can execute, ever | Premise / liveness | **Critical** | Kills A6, A7, take-profit-on-yield |
| **A5** | `pathHash` is specified as `keccak256(abi.encode(path))` in §3.3 and checked as `keccak256(path)` in §3.5 — a rule armed to spec is permanently unexecutable with a live allowance | Money / liveness | **High** | Rule bricked, allowance stranded |
| **A6** | `keeperFeeFlat` is `uint64` "in buyToken units" with no decimals binding. Off by 10¹² either way → rule either never executes or reverts `DustExecution` forever | Money / liveness | **High** | Rule bricked |
| **A7** | `cancelAll()`'s epoch check is unimplementable — `Rule` has no `epoch` field and `execute()` never reads one. The panic button is a no-op | Authz / liveness | **High** | Panic button does nothing |
| **A8** | Dust remainder: `totalSellAmount % partSellAmount` produces a final part that always reverts `DustExecution`; no path closes the rule or revokes the allowance | Liveness | **High** | Allowance stranded to `expiry` |
| **A9** | `spent += amount` before `transferFrom`; a fee-on-transfer `sellToken` overstates the lifetime cap and then reverts `FloorBreached` forever. FAssets transfer fees are a governance switch | Money | **High** (mainnet) | Silent overcharge → total brick |
| **A10** | Keeper-fee cap exhaustion strands the tail of every multi-part rule: fee → 0, no rational executor, user has no EVM key | Liveness / economics | **High** | Tail of every DCA rule |
| **A11** | Stop-loss latency is fine; **stop-loss *semantics* are not.** The keeper cannot beat the feed it reads. A wick that reverts within one block latches nothing and fires nothing | Premise / honesty | **High** | Claim falsifiable on stage |
| **A12** | `latched` is written but never read in §3.5; §5.1 describes the opposite behaviour. Whichever is implemented, the floor tracks the falling price, so a latched multi-part stop-loss is a capitulation ladder | Money | **High** | Sells the whole cap into the crash |
| **A13** | stXRP share price is **exactly 1.000000** — `totalAssets == totalSupply` to the unit. The lead "auto-earn" demo deposits into a vault that has never accrued one unit of yield | Honesty | **High** | Judge falsifies in one `cast call` |
| **A14** | stXRP has a hard 1,000,000 FXRP deposit cap with 899,251 FXRP of headroom; a whale fills it and every auto-earn rule reverts | Liveness / griefing | Medium | DoS costs the attacker a lockup |
| **A15** | `out` is the router's *reported* return, not a measured balance delta; Trimmy also has no `sweep`, so donated `buyToken` is permanently stuck and silently redistributed | Money | Medium | Bounded, ugly |
| **A16** | The user signs a 32-byte commitment to calldata only *our own* decoder can read. Plimsoll is written by the same team | Trust / honesty | Medium | The whole Bounty-1 trust story |
| **A17** | FCC rule class: enclave operator censors by not running; volatile in-memory credential store wiped by a VM restart, with no on-chain signal | Liveness | Medium | Every private-trigger rule |
| **A18** | Coston2 block production stalls to 25 s in some windows (2 s in mine). During a stall nothing lands — which is exactly when a crash would happen | Liveness | Medium | Episodic |

---

## 2. Find the money bug

### A1 — Critical. The front end is the attacker, and every invariant holds while it drains you.

`keeper-security.md` §3.3 declares:

```solidity
address  buyToken;
address  receiver;   // MUST be `account` unless explicitly named at arm time
address  venue;      // the ONE router permitted for this rule
```

Nothing in `_validate()`, in the twelve invariants I-1…I-12, or in §3.7's list of deliberate absences
constrains any of these three to a set. Worse, §3.7 *forbids* the control that would:

> no settable venue registry, no settable fee, no settable oracle address

That is an argument against a *mutable* registry. It has been read as an argument against any
allowlist at all, and consequently there is none.

**Failure sequence** (no keeper key, no contract bug, no oracle manipulation):

1. Attacker controls the Trimmy front end — by compromise, by a malicious dependency in the arming
   page, or by being a hostile clone the user reached from a phishing link.
2. Attacker deploys `EvilToken` (mints itself freely, 6 decimals) and `EvilVenue`, a contract exposing
   the exact `swapExactTokensForTokens(uint256,uint256,address[],address,uint256) returns (uint256)`
   shape §3.5 calls.
3. The arming batch it builds is
   `[FXRP.approve(Trimmy, cap), Trimmy.arm({sellToken: FXRP, buyToken: EvilToken, venue: EvilVenue,
   receiver: attacker, minOutAbsolute: 1, maxSlippageBips: 1, …})]`.
   `maxSlippageBips = 1` and `minOutAbsolute = 1` both satisfy I-5 (`> 0`).
4. The user opens Xaman and sees **42 opaque bytes** committing to `keccak256(PackedUserOperation)`
   `[Verified — keeper-security.md C2 and §3.6 note at line 845]`. There is nothing to read.
5. Every subsequent `execute()`: `transferFrom(account, Trimmy, partSellAmount)` pulls real FXRP;
   `forceApprove(EvilVenue, amount)`; `EvilVenue` keeps the FXRP and mints
   `oracleOut` `EvilToken` to Trimmy; `out >= floorOut` passes by construction;
   `safeTransfer(receiver = attacker, out - fee)` sends worthless tokens to the attacker.
6. Repeat until `spent == totalSellAmount`.

Check the invariants: I-1 holds (no caller restriction). I-2 holds (exact allowance). **I-3 holds** —
the caller loosened nothing; the *rule* was already hostile. I-5 holds. I-8 holds. I-10 holds
(`out > fee` in EvilToken units). I-12 holds — `receiver` *was* "explicitly named at arm time".
**Twelve invariants, zero violations, total loss.**

Two sub-variants, both cheaper:

- **Rigged `decimals()`.** `_quote(amount, price, dec, sellToken, buyToken)` must read the buy leg's
  decimals. If it does so at execute time, an attacker-supplied `buyToken` returning 36 on the first
  call makes `oracleOut` — hence `floorOut` — vanishingly small against a *real* venue, and the user's
  FXRP is swapped for dust on a real pool. If instead decimals are cached at arm time, `arm()` makes an
  external call to an arbitrary contract and **violates I-9** (`arm()` performs no external call that
  can transfer control) — which §C4 establishes is dangerous specifically because the AssetManager's
  reentrancy guard is *open* during the arming batch. There is no third option in the current spec.
- **The peg assumption** (`00-critique.md` M3). One FTSO read only prices a two-leg quote if
  `buyToken == $1`. Coston2 carries at least five unrelated "USDC" tokens `[Measured — critique M3]`.
  An attacker does not even need a fake token; picking the *wrong real* USDC is enough.

**Fix — three parts, all required.**

1. `buyToken` and `venue` become `immutable` constructor-set allowlists (`mapping` written once in the
   constructor, no setter). This is compatible with §3.7's non-upgradeability: a new venue is a new
   Trimmy deployment, exactly as CoW and 1inch do it.
2. `receiver` is removed from `RuleParams` entirely and hard-set to `account`. A payout to a third
   party is a *different verb* with a different risk story, not a field. (The dead-man switch A7 needs
   third-party payout — build it as a separate contract with its own review, not as a struct field on
   the swap executor.)
3. Both legs of the quote get an FTSO feed pinned at arm time by `bytes21 feedId`, plus a compile-time
   `decimals` constant per allowlisted `buyToken`. No `decimals()` call anywhere, at arm or execute
   time.

This also closes the credible-in-a-demo version of the attack: a judge who asks *"what stops your
front end from putting a different `venue` in the batch?"* currently has no answer other than "Plimsoll
would tell you", and Plimsoll is ours (A16).

---

### A2 — Critical. The oracle floor is a public target price. The slippage band is free money for anyone.

This is the one that is not in any prior document, and it inverts the pack's headline security claim.

§3.5 step 5:

```solidity
uint256 oracleOut = _quote(amount, price, dec, r.sellToken, r.buyToken);
uint256 floorOut  = _max(oracleOut * (10_000 - r.maxSlippageBips) / 10_000, r.minOutAbsolute);
require(minOut >= floorOut, MinOutTooLow());
...
require(out >= floorOut, FloorBreached());
```

Every input to `floorOut` is public: `amount` is derivable from the rule, `price`/`dec` from FTSO,
`maxSlippageBips` and `minOutAbsolute` from the `Armed` event. **`floorOut` is a number any observer
can compute for any block before the block is produced.** And the contract will accept exactly it.

**Failure sequence** — one transaction, atomic, riskless:

1. Attacker computes `floorOut` for `ruleId` at the current FTSO price.
2. Same tx, step 1: swap `sellToken → buyToken` on `r.venue` until the pool's marginal output for
   `amount` is exactly `floorOut`.
3. Same tx, step 2: `Trimmy.execute(ruleId, minOut = floorOut, path)`. `out == floorOut`; both
   `require`s pass at equality.
4. Same tx, step 3: swap back. The pool is restored; the attacker's inventory is unchanged plus the
   user's `oracleOut − floorOut`, minus two AMM fees.

Profit per execution = `oracleOut × maxSlippageBips / 10_000 − 2 × poolFee × tradeSize`. On a 30 bps
pool with `maxSlippageBips = 100`, that is positive for any `amount` above a small threshold, and it
scales linearly with the user's notional.

**Maximum extractable across the system = `Σ_rules totalSellAmount × price × maxSlippageBips / 10_000`,
realised with certainty, by an attacker with no keys and no privileges.**

Three things make this worse here than in the general MEV case:

- The trade is **scheduled and public**. A DCA rule announces its own execution window (`t0`,
  `interval`, `span`) at arm time. `keeper-security.md` §5.2 then *recommends* `span = interval`
  (no window restriction) for price-triggered rules, deleting the jitter that was the one defence.
- The venue is **a pool we seeded ourselves** (`GROUND-TRUTH` §3: 80/80 `getPool` = `address(0)`;
  there is no other option on Coston2). Its depth is whatever we choose, so the cost of moving it to
  the target is whatever we choose, and it will be small.
- `00-critique.md` **C7 chose the side that makes this cheapest.** It resolved "read venue spot or
  not?" in favour of "never let the AMM tell you what anything is worth" — correct against censorship,
  but it removes the only signal that would let `execute()` notice the pool has been pushed 100 bps off
  oracle. C7 and T3 (MEV, "severity bounded, likelihood **high**") are in direct conflict and the pack
  never notices.

**The honest restatement of T1.** `keeper-security.md` T1 says *"the maximum damage from a leaked
keeper key is exactly zero"*, and `AGENTS.md` rule 3 repeats it as *"the maximum damage from a leaked
keeper key is zero."* Both are **true and irrelevant**. The key confers nothing because `execute()` is
permissionless — which is the same property that hands the extraction to *everyone*. The claim that
survives is:

> A leaked keeper key grants **no capability that the public does not already have.** The value
> extractable by *any* adversary from an armed rule is bounded by `maxSlippageBips` of its notional,
> per execution, and that bound is reached, not approached.

Say that. A judge who asks "so what does the attacker get?" and hears "zero" will not believe it, and
should not.

**Fix.**

1. `MAX_SLIPPAGE_BIPS` must be *small* and stated — 25–50 bips, not the 100–200 that
   `rule-taxonomy.md` §4.3 defaults to. Every basis point is a direct transfer to a sandwicher.
2. Cap `partSellAmount` against pool depth at arm time. This is a one-time read of the pool at
   arming, not a per-execution AMM price read, so it does not reintroduce the C7 censorship primitive.
3. Reintroduce jitter for **all** directions, reversing §5.2: `span << interval` even for stop-losses.
   A stop-loss that may fire up to `span` seconds late is strictly better than one that fires at a
   time the attacker picked.
4. State the residual honestly in the submission. This is not fixable to zero on a public AMM without
   private orderflow or a batch auction, and Coston2 has neither.

---

### A5 — High. A rule armed to spec can never execute, and its allowance is stranded.

§3.3: `bytes32 pathHash; // keccak256(abi.encode(path))`
§3.5 step 6: `require(keccak256(path) == r.pathHash, WrongPath());`

`abi.encode(bytes memory)` prepends a 32-byte offset and a 32-byte length and right-pads to a word.
`keccak256(path)` hashes the raw bytes. **They are never equal for any non-empty `path`.** A rule armed
by a front end that implemented §3.3 reverts `WrongPath()` on every execution attempt, forever, while
the exact-size FXRP allowance remains live until `expiry`. No cancel path revokes the allowance
(§3.6's own note: *"does NOT touch the allowance"*).

**Fix.** Delete `path` from the caller interface entirely. Store the encoded path *in the rule* at arm
time. The caller supplies nothing but `ruleId` and `minOut`. This removes a whole class of
mismatch bug and shrinks the caller-controlled surface I-3 has to defend, at the cost of some calldata
gas once per rule instead of once per execution.

---

### A6 — High. `keeperFeeFlat` is `uint64` "in buyToken units" and nothing binds the decimals.

`uint64 keeperFeeFlat;` with `buyToken` a free 18-or-6-decimal address (A1). If the front end computes
a $0.05 flat fee assuming 6-decimal USDT (`50_000`) and `buyToken` is 18-decimal, the keeper earns
5×10⁻¹⁴ tokens and no rational executor ever runs the rule — **silent permanent liveness failure with a
live allowance.** In the other direction (18-decimal intent, 6-decimal token) `fee` exceeds `out` and
`require(out > fee, DustExecution())` reverts every execution — **the same failure, louder.**
`uint64` max is ≈1.8×10¹⁹, i.e. 18.4 units of an 18-decimal token, so the overflow case is
representable and reachable.

**Fix.** Fee is denominated in `sellToken` (FXRP, 6 decimals, known) and taken from `amount` before
the swap, or — better — the flat fee is expressed in **USD with the FTSO's own decimals** and converted
at execution using the price already read in step 3. Either way, remove "buyToken units" from a field
whose decimals the contract does not know.

---

### A8 — High. The dust remainder brick.

Step 4: `amount = _min(r.partSellAmount, r.totalSellAmount - r.spent)`. If `totalSellAmount` is not an
exact multiple of `partSellAmount`, the final part is `totalSellAmount % partSellAmount`, which can be
one unit. Step 9 then evaluates `fee = keeperFeeFlat + …` — a *flat* fee against a dust output — and
`require(out > fee, DustExecution())` reverts. The rule sits at `executed < n`, `spent < totalSellAmount`,
permanently un-executable, with the residual allowance live until `expiry`.

`_validate()` cannot simply require divisibility, because `partSellAmount` is also the per-execution
cap and users think in round notionals.

**Fix.** In step 4, if `totalSellAmount - r.spent < partSellAmount` **and** the remainder cannot
support `keeperFeeFlat`, absorb it into the previous part (`amount = totalSellAmount - spent` only when
it clears the fee floor, otherwise treat the rule as complete: set `spent = totalSellAmount`, emit
`Completed`, and let the allowance lapse). Add invariant: **a rule always reaches a terminal state; no
input produces a rule that is neither executable nor complete.**

---

### A9 — High on mainnet. `spent` is credited before the transfer, and FAssets transfer fees are a switch.

Step 7 writes `r.spent += uint128(amount)` before step 8's `safeTransferFrom`. If `sellToken` takes a
transfer fee, the contract receives `amount × (1 − f)` but charges the user's lifetime cap the full
`amount`, and then swaps the smaller received balance — producing `out < floorOut` and reverting
`FloorBreached()`. The user is overcharged against their cap *and* the rule bricks.

`[Verified — live 2026-08-06]` **FXRP on Coston2 has no transfer fee today.** The Coston2
`AssetManagerFXRP` `0xc1Ca88b937d0b528842F95d5731ffB586f4fbDFA` reverts with the diamond
`FunctionNotFound` sentinel `0x5416eb98…` for `transferFeeMillionths()`,
`fassetTransferFeeMillionths()` and `transferFeeSettings()`, and FXRP itself reverts on
`transferFeeMillionths()`:

```bash
cast call 0xc1Ca88b937d0b528842F95d5731ffB586f4fbDFA "transferFeeMillionths()(uint256)" --rpc-url $R
# execution reverted, data 0x5416eb983ba60fb1…   (diamond FunctionNotFound)
cast call 0x0b6A3645c240605887a5532109323A3E12273dc7 "transferFeeMillionths()(uint256)" --rpc-url $R
# execution reverted
```

`[Inference]` This deployment predates the FAssets transfer-fee module. That module exists in FAssets
and is a **governance-settable parameter on mainnet**. A contract with no upgrade path (§3.7, I-11)
that assumes zero transfer fee is a contract that dies the day governance turns one on, with every
armed rule stranded.

**Fix.** Measure the delta, always:
```solidity
uint256 before = IERC20(r.sellToken).balanceOf(address(this));
IERC20(r.sellToken).safeTransferFrom(r.account, address(this), amount);
uint256 received = IERC20(r.sellToken).balanceOf(address(this)) - before;
r.spent += uint128(received);          // charge what actually arrived
```
and recompute `oracleOut`/`floorOut` from `received`, not from `amount`. Same treatment for `out` in
step 8 (see A15). Cost: two extra `SLOAD`-class reads. This is not defensive programming; it is the
difference between "works today" and "works".

`[Unverified]` Whether Flare mainnet FXRP currently has a non-zero transfer fee. **Experiment:**
`cast call <mainnet AssetManagerFXRP> "transferFeeMillionths()(uint256)" --rpc-url https://flare-api.flare.network/ext/C/rpc`.

---

### A12 — High. `latched` is dead code, and either reading of it makes the stop-loss worse.

§3.5 step 3 writes `r.latched = true` and **never reads it anywhere in the function.** §5.1 describes
the intended semantics — *"once `price <= triggerPrice` has been observed once… subsequent parts check
only the schedule and the floor, not the trigger"* — which the code does not implement. So the spec is
ambiguous, and both resolutions are bad:

- **As written** (re-check the trigger every part): `latched` is a pointless SSTORE, and the
  oscillation griefing vector T7 that latching was introduced to delete is still open.
- **As §5.1 describes**: after the first fill the rule sells the remaining parts on schedule alone,
  with `floorOut` recomputed each time from the **live, falling** price. `floorOut` therefore tracks
  the crash down. A user with `n = 10` who set a stop at $0.95 sells part 1 at $0.95 and parts 2–10 at
  whatever the oracle prints on the way to $0.40 — each one individually "within slippage". **The
  floor is not a floor; it is a moving average of the disaster.**

§5.1's own mitigation — *"my recommendation is latch, with `n = 1` as the default"* — is a default, and
a default is not an invariant. Nothing forbids `n = 10`.

**Fix.** Pick one and make it normative. Recommended: latch, **and** add `uint256 latchedPrice` set on
the first trigger, with every subsequent part's floor computed from `min(livePrice, latchedPrice)`'s
*more favourable* side — i.e. `floorOut = _max(quote(amount, latchedPrice) × (1 − slip), minOutAbsolute)`.
A stop-loss then never sells below the price the user actually specified, and a rule that cannot clear
that floor simply does not execute. That is the correct semantics of "stop at $0.95", and it is what a
user believes they bought.

---

### A15 — Medium. `out` is a claim, not a measurement.

`uint256 out = IRouter(...).swapExactTokensForTokens(...)` — the contract trusts the venue's return
value and then transfers `fee + (out − fee)` of `buyToken`. Uniswap V2's `swapExactTokensForTokens`
returns `amounts[]` computed from *reserves*, not from the recipient's balance delta; V3's
`exactInput` returns the true `amountOut`. Since `venue` is unconstrained (A1) the return value is
attacker-controlled in general.

Because Trimmy normally holds zero `buyToken`, an over-report simply reverts the second transfer —
annoying, not exploitable. But `execute()` has no `sweep` and §3.7 forbids one, so **any `buyToken`
donated to the Trimmy address is permanently stuck**, and an over-reporting venue silently
redistributes it to whoever executes next. Small, but it is an accounting identity that does not hold:
`Σ transferred out ≠ Σ received`.

**Fix.** Measure `out` as a `balanceOf` delta on `buyToken` across the swap. Combined with A9 this makes
the contract's accounting identity exact: *what the user was charged equals what arrived, and what was
paid out equals what the swap produced.*

---

## 3. Attack the authorization

**Given only a leaked keeper key, an armed rule, and unlimited adversarial transactions, the maximum
extractable is — correctly — zero, and the claim is worth almost nothing.** Here is the proof and then
the reason it does not matter.

**Proof.** Enumerate every function that moves value and every place `msg.sender` appears.

| Function | Does it read `msg.sender` for authorization? | Consequence for a key holder |
|---|---|---|
| `PersonalAccount.executeUserOp` | Yes — `onlyController`, reverts `0x59907813` `OnlyController()` for every caller but `0x434936d4…`. `[Verified — raw `eth_call` selector `0x2b2ee783`, reproduced independently by two passes, GROUND-TRUTH §1]` | The key cannot drive the account. No user operation, no re-arm, no allowance change. |
| `Trimmy.arm` | Yes, but only to *bind* — `rules[id].account = msg.sender`. A keeper arming a rule binds it to the keeper's own address, whose FXRP allowance to Trimmy is zero. | Can create rules that are self-referential and inert. |
| `Trimmy.execute` | **No** (I-1). `msg.sender` appears once, as the fee recipient. | The key confers nothing the public lacks. |
| `Trimmy.cancel` | Yes — `r.account` or `r.guardian`. The keeper is neither. | Cannot cancel. |
| `Trimmy.cancelAll` | Yes — `account` or `guardians[account]`. | Cannot cancel. |
| ERC-20 allowance | Granted by the personal account to the **Trimmy contract address**, not to a keeper EOA. | The key cannot call `transferFrom`. |

There is no `owner`, no `AccessControl`, no proxy, no `delegatecall`, no `rescueTokens`, no pause, and
no function accepting caller-supplied call targets (§3.7). **A leaked keeper key therefore extracts
exactly zero.** That part of the design is sound and the reasoning behind it is the best work in the
pack.

**And it is the wrong threat model.** Three attackers sit strictly above the keeper:

1. **Any observer** extracts `maxSlippageBips` of every execution (A2). No key required. This is the
   real answer to "what is the maximum extractable", and it is not zero — it is *the entire slippage
   band on every rule in the system, with certainty*.
2. **The front end** extracts 100% (A1). No key required, no contract bug. The keeper key is the
   least valuable secret in the system; the front-end deploy key is the most valuable, and no document
   models it.
3. **The enclave operator** (us) censors every FCC-gated rule by not running (A17), and
   `keeper-security.md` T1's zero-damage result explicitly does not cover that class —
   `00-critique.md` A7 already identified this and it has not been fixed.

**Fix.** Retire "maximum damage from a leaked keeper key is zero" as the headline. Replace it with a
ranked adversary table — front end > any MEV searcher > enclave operator > keeper — and state the bound
for each. The keeper row is the only zero. Publishing that table is a *stronger* submission than
publishing the zero, because it is the one a judge cannot knock down.

**One genuine authorization gap that is not about keys — A7.** §3.6:

```solidity
function cancelAll(address account) external {
    epoch[account] += 1;                        // every rule stores its arming epoch;
    emit EpochAdvanced(account, epoch[account]); // execute() requires r.epoch == epoch[account]
}
```

The comment describes a check that does not exist. `struct Rule` (§3.3) has **no `epoch` field**, and
`execute()` (§3.5) reads no epoch. As specified, `cancelAll` increments a counter nothing consults.
This is the "panic button" — the thing that makes the 131-second XRPL cancel round trip tolerable
(§3.6: *"the difference between a usable panic button and an unusable one"*) — and it is inert.

Second gap in the same function: `cancel()` checks `msg.sender == r.guardian` (per-rule) while
`cancelAll()` checks `msg.sender == guardians[account]` (per-account). **Two different guardian
registries**, and nothing in `arm()` writes the second one. A user who names a guardian gets per-rule
cancel and no panic button.

**Fix.** Add `uint32 epoch` to `Rule`, set from `epoch[msg.sender]` in `arm()`, and add
`require(r.epoch == epoch[r.account], Superseded())` to `execute()` step 1. Choose one guardian
registry — per-account is the right one, since it is the account, not the rule, whose safety the
guardian protects — and write it in the arming batch.

---

## 4. Attack liveness

Ranked by how cheaply an attacker stops a rule that should fire.

**L1 — Fill the vault cap. `[Measured]`** stXRP `0xC90D6847…`:

```
maxDeposit(0xdEaD)  = 899,251.567000 FXRP
totalAssets()       = 100,748.433000 FXRP
                      ─────────────────────
                      1,000,000.000000 FXRP exactly
```

A hard global deposit cap. Any depositor who fills the remaining 899,251 FXRP makes **every** Trimmy
auto-earn rule targeting stXRP revert. Coston2 FXRP total supply is 4,134,532.70 `[Verified —
GROUND-TRUTH §4]`, so 899k is 22% of the float — expensive but reachable, and the attacker's capital is
not at risk because they can request redemption afterwards. On testnet, where FXRP is mintable from a
faucet, "expensive" means "patient". **Fix:** `_validate()` reads `maxDeposit` at arm time (fine), and
`execute()` treats a cap revert as a distinguishable outcome rather than an opaque failure, so the
front end can tell the user their rule is blocked rather than broken.

**L2 — Exhaust the fee cap.** `keeperFeeTotalCap` bounds *lifetime* fees. On a 52-week DCA rule with a
cap sized for the median week, the tail weeks compute `fee = cap − paid = 0`. `require(out > fee)`
passes, so nothing reverts — the rule is *executable but unprofitable*, and **no rational keeper runs
it.** Permissionless execution is a security property, not a liveness property (`00-critique.md` A3
says this and it is right); the user cannot self-execute because they have no EVM key (C1). The rule
silently stops working with months left on the clock and a live allowance. **Fix:** `_validate()`
requires `keeperFeeTotalCap >= n × (keeperFeeFlat + maxExpectedBipsFee)`. Refuse to arm a rule that
cannot pay for its own executions — the same principle `GROUND-TRUTH` §7 already applies to the direct
minting dead zone.

**L3 — the dust brick (A8)** and **L4 — the `pathHash` brick (A5)**: both produce a rule that is
permanently un-executable with a stranded allowance, and neither has a recovery path, because
`cancel()` deliberately does not revoke the allowance and the user has no EVM key.

**L5 — No vault exit exists at all. `[Measured]`** This is the one that kills whole product lines:

| Vault | `maxWithdraw(0xdEaD)` | `maxRedeem(0xdEaD)` | `lagDuration()` |
|---|---:|---:|---:|
| stXRP / FirelightVault `0xC90D6847…` | **0** | **0** | (no such fn) |
| TESTearnXRP `0x9E63a5D2…` | **0** | **0** | 300 s |
| MyERC4626 `0xF97B2bBd…` | **0** | **0** | 86,400 s |

```bash
for V in 0xC90D6847747b85d1fa2E07859869fb9fB72c0361 \
         0x9E63a5D282F2fBb7DcE822B98e363b2719D28319 \
         0xF97B2bBdB2f4a561806e5038a503eCA81554634E; do
  cast call $V "maxWithdraw(address)(uint256)" 0x000000000000000000000000000000000000dEaD --rpc-url $R
  cast call $V "maxRedeem(address)(uint256)"   0x000000000000000000000000000000000000dEaD --rpc-url $R
done   # 0 0 0 0 0 0
```

`venues-and-pool.md` measured this for stXRP alone and read it as a stXRP quirk. **It is universal on
Coston2.** All three are request/claim queues (`lagDuration` 5 min and 24 h). Consequences:

- Every `WITHDRAW_VAULT` verb is unexecutable synchronously. A stop-loss *on a yield position* — the
  natural composition of the two live product lines — cannot exist.
- A6 drip payout and A7 dead-man switch both need to get assets *out*; neither can.
- A two-phase rule (`requestRedeem` now, `claimWithdraw` after `lagDuration`) needs a rule that
  survives across the lag and re-fires — i.e. re-arming — which `onlyController` forbids
  (`00-critique.md` C1). **The obvious workaround is the exact thing the platform makes impossible.**

**Fix.** Model the queue explicitly: `execute()` on a withdraw rule calls `requestRedeem` and writes
`claimableAt = block.timestamp + lagDuration`; a *second*, separate permissionless
`claim(ruleId)` entry point does `claimWithdraw` once `block.timestamp >= claimableAt`. Two entry
points, one rule, no re-arming. This is buildable and nobody has specified it.

**L6 — Coston2 stops making blocks.** `[Measured — mine, 2026-08-06]` Over 400 contiguous blocks:
inter-block gap p50 1 s, p90 1 s, p99 2 s, **max 2 s**; feed age (`block.timestamp − feed.timestamp`)
p50 0 s, p90 2 s, p99 5 s, **max 7 s**. That window was benign. `ftso-in-contract.md` measured a
different window on the same day and got block gaps to **25 s** and feed ages to **31 s**. Both are
correct; **Coston2 block production is episodically bursty and the tail is real.** During a stall no
transaction lands, no rule executes, and `maxFeedAge` — whatever p99 it is set from — is being derived
from a distribution with a fat, window-dependent tail. Setting `maxFeedAge` from a single window's p99
will produce a rule that refuses to execute during exactly the stalls that matter. **Fix:** sample
`maxFeedAge` across *several separated* windows, take the max of the p99s, and add margin; and treat
`StaleFeed` as an expected outcome the front end explains, not an error.

**L7 — the enclave simply does not run (A17).** For FCC-gated rules the caller is not "anyone", it is
"anyone holding a fresh signed verdict", and verdicts come from one enclave with a 30-minute result TTL
and a credential store held **in volatile memory that a VM restart wipes** `[fcc-extension.md §5.3, as
cited in 00-critique.md C8/A7]`. A GCP live-migration or a maintenance reboot silently voids every
private-trigger rule, with no on-chain event and no user notification. `AGENTS.md` "Known limits"
already says the two halves have different trust models; this is the concrete mechanism, and it needs a
**heartbeat**: the enclave publishes a signed liveness ping on-chain, and the front end shows a rule as
*degraded* the moment the ping goes stale.

---

## 5. Attack the premise

### A3 — Critical. The reference `execute()` calls a function that exists nowhere on Coston2.

`[Verified — explorer ABI, 2026-08-06]` The five `SwapRouter` contracts on Coston2 expose exactly:

```
WETH9, exactInput, exactInputSingle, exactOutput, exactOutputSingle, factory,
flareSwapSwapCallback, multicall, refundETH, selfPermit, selfPermitAllowed,
selfPermitAllowedIfNecessary, selfPermitIfNecessary, sweepToken, sweepTokenWithFee,
unwrapWETH9, unwrapWETH9WithFee
```

```bash
curl -s "https://coston2-explorer.flare.network/api?module=contract&action=getabi&address=0xe2B3aE21461c4ad3415210630EA210e9F53CCEBc" \
 | python3 -c "import sys,json;print([f['name'] for f in json.loads(json.load(sys.stdin)['result']) if f['type']=='function'])"
```

**These are Uniswap V3 routers. There is no `swapExactTokensForTokens` on any of them.** The
signature §3.5 calls — `swapExactTokensForTokens(uint256,uint256,address[],address,uint256) returns
(uint256)` — is neither V2 (which returns `uint[] memory`) nor V3. It is invented, and it is the single
external call the entire 1,300-line security document exists to protect. Downstream: `bytes32 pathHash`
+ `_decodePath(path) → address[]` is a **V2 path model**; V3 paths are packed
`(address,uint24,address,…)` bytes and go to `exactInput(ExactInputParams)`. Every line of §3.5
steps 6 and 8 is written against the wrong venue interface.

Compounding it: `GROUND-TRUTH` §3 establishes there is **no FXRP pool at all** on Coston2 (80/80
`getPool` = `address(0)`), so the demo venue is a pool we deploy ourselves. That pool will be a V3
pool, because V3 is what is deployed. **Fix:** rewrite `execute()` step 8 against
`ISwapRouter.exactInput(ExactInputParams{path, recipient, deadline, amountIn, amountOutMinimum})`,
store the packed V3 `path` in the rule (which also fixes A5), and set `recipient = address(this)` so
the balance-delta measurement of A15 works.

### A11 — High. The latency is fine. The semantics are not. `[Measured]`

Nobody had checked whether a keeper can observe an FTSO trigger and land a transaction fast enough for
a stop-loss to mean anything. I checked. Method: 400 contiguous Coston2 blocks, each paired
`eth_getBlockByNumber` + `eth_call getFeedById(XRP/USD)` pinned to that block, batched 100 JSON-RPC
calls per request. Script: `scratchpad/lat.py`.

| Quantity | Result |
|---|---|
| Feed age seen by a contract (`block.timestamp − ts`) | p50 **0 s**, p90 2 s, p99 5 s, max **7 s** |
| Inter-block gap | p50 **1 s**, p90 1 s, p99 2 s, max **2 s** |
| Feed **value** changed between consecutive blocks | **107 of 399 steps (27%)** |
| XRP/USD total range over the 414-second window | 1.034873 → 1.036742 = **18.1 bips** |
| Excursions ≥10 bips below the window median | **0** |

**What this proves.** The keeper's minimum reaction time is one block: it reads the same
`getFeedById` the contract will read, so it cannot see a trigger before the block that publishes it,
and its transaction lands in the next block at the earliest. Observed floor ≈ **1–3 seconds** from
feed publication to execution. That is genuinely fast and the latency objection does not land.

**What it destroys.** Precisely *because* the keeper reads the same feed as the contract, the keeper has
**zero information advantage and therefore provides zero protection faster than the feed itself.**
Three consequences a judge can push on:

1. **A wick shorter than one block is untradeable.** The trigger is re-checked in `execute()`
   (`require(price <= r.triggerPrice)`). If the feed prints below the trigger in block N and back above
   in block N+1, the keeper's transaction lands in N+1 and **reverts**. `latched` does not help: it is
   only written on a *successful* execution (§3.5 step 3), so a reverted attempt latches nothing. The
   product fires on **sustained** moves only.
2. **Near a threshold, reverts are the common case, and the keeper pays for them.** The feed changes on
   27% of blocks; a crossing by definition happens at the boundary, where the value oscillates across
   it. Every failed attempt costs the keeper gas and earns nothing, and `keeperFeeFlat` was sized
   against *successful* executions. `00-critique.md` M4 ("the keeper is asserted, never designed or
   costed") is still open and this is the term that was missing from the cost model.
3. **The realised price is set by pool depth, not by the trigger.** On a pool we seed ourselves, the
   execution price for a meaningful notional is whatever our own liquidity gives — floored at
   `oracleOut × (1 − maxSlippageBips)`, and A2 says an attacker takes that band with certainty.

**The honest claim, which is still a good one:**

> Trimmy reacts to a sustained FTSO move within one Coston2 block — 1–3 seconds `[Measured]` — with
> the execution price floored at the live oracle less a stated slippage band. It does not protect
> against sub-block wicks, and no keeper-based design on a public chain can.

**Do not say** "stop-loss protection". **Do say** "one-block conditional execution against the FTSO,
with an oracle-enforced floor". The second claim is true, measurable on stage, and nobody else on
Flare has it.

### A13 — High. The lead demo vault has never earned anything. `[Measured]`

```
stXRP 0xC90D6847…   totalAssets() = 100,748,433,000
                    totalSupply() = 100,748,433,000
                    previewDeposit(1e6) = 1,000,000
                    previewRedeem(1e6)  = 1,000,000
```

**Share price exactly 1.000000, to the unit.** `00-critique.md` §4 recommends option (c): lead with
the vaults, "A1 auto-earn". The vault it leads with pays nothing and has never paid anything.

The other two do have a share price above 1 — TESTearnXRP `7,216,567,418 / 6,813,399,509 = 1.05917`,
MyERC4626 `6,209,448,445 / 6,202,625,501 = 1.00110` `[Measured]` — but both have
`maxWithdraw == maxRedeem == 0` (L5), so the yield is unrealisable.

**Fix.** Lead with TESTearnXRP (real 5.9% accrued share price, 300 s redemption lag), state the lag,
and demo the two-phase request/claim rule from L5's fix. That is a *better* demo than a 1:1 vault
because the queue is a real integration problem solved on stage. And say plainly that stXRP is a
zero-yield test deployment — a judge runs two `cast call`s and finds it otherwise.

### A16 — Medium. The user signs 32 bytes that only our own tool can read.

`[Verified — keeper-security.md C2 and §3.6]` The `0xFE` memo commits to
`keccak256(PackedUserOperation)`; the user in Xaman sees 42 opaque bytes. The arming batch is
unrestricted — arbitrary targets, arbitrary calldata, atomic.

So the entire safety of arming reduces to: *can the user verify the preimage of that hash?* The answer
in the pack is "Plimsoll decodes it". Plimsoll is written by the same team as the front end that
produces the preimage. **If the front end is compromised, so is the decoder that would reveal it**
(A1). This is a genuine, unavoidable, and *interesting* problem — and the submission is stronger for
stating it than for eliding it.

**Fix, and it is cheap:** make the decoder independently runnable. Publish the `RuleParams` ABI, ship
`plimsoll decode <memo-hex>` as a standalone CLI with no network dependency on our servers, and show a
judge decoding a batch we did not generate. That converts "trust our tool" into "here is a tool,
here is the spec, decode it yourself" — which is the same move that makes reproducible builds
meaningful in the FCC half of the submission, and it costs a day.

### The premise itself survives — narrowed.

Is there a protocol constraint that makes this undemonstrable by 2026-08-14? **No.** The constraints
are real but each has a buildable answer inside the window:

| Constraint | Status | Answer |
|---|---|---|
| No FXRP swap pool on Coston2 | `[Verified]` blocking for swap rules | Deploy a **V3** pool (A3), seed it, label it as ours |
| No router with the assumed ABI | `[Verified]` A3 | Rewrite step 8 against `exactInput` |
| No synchronous vault exit | `[Measured]` A4/L5 | Two-phase request/claim rule — buildable, unspecified |
| `onlyController` forbids re-arming | `[Verified]` | Allowance-pull only; two entry points instead of re-arm |
| 10 FXRP lot quantisation, 0.2 XRP + 1 drop dead zone | `[Verified]` | Preflight refuses to arm below the floor |
| Keeper latency | `[Measured]` 1–3 s | Fine; restate the claim (A11) |

The premise that dies is the *marketing* premise. "One XRPL payment arms a rule" is true of arming
only — the first run needs a mint payment first, lot-quantised at 10 FXRP with a 0.2 XRP + 1 drop
floor `[Verified — GROUND-TRUTH §2, §7]`. `AGENTS.md` already says this under "Known limits". **Make
sure it is in the demo script and the first slide, not only in the limits section**, because the demo
will show two payments and a judge will notice.

---

## 6. Honesty audit — every claim a judge could falsify on stage

| Claim as currently written | Verdict | What to say instead |
|---|---|---|
| "The maximum damage from a leaked keeper key is zero" (T1, `AGENTS.md` r3) | **True but misleading.** Zero because the key confers nothing — the same property that gives the extraction to everyone (A2) | "A leaked keeper key grants no capability the public lacks. Adversarial extraction is bounded by `maxSlippageBips` per execution, and reached." |
| "The keeper is trusted with nothing" | **True.** Verified by function-by-function enumeration (§3) | Keep. It is the strongest true claim in the pack. |
| "One XRPL payment arms a rule" | **True of arming; false of first run** | "One payment arms it. Getting FXRP in the first place is a separate mint, lot-quantised at 10 FXRP." |
| "Permissionless execution gives liveness" | **False** (`00-critique.md` A3, and A10/L2 here) | "Permissionless execution means a leaked key is worthless. Liveness comes from our keeper — we are the only keeper." |
| "Verify the code hash on-chain" (FCC step 2) | **Vacuous under `TEST_PLATFORM`** — the hash `0x194844cf…` is shared by 254 machines `[Verified — GROUND-TRUTH §6]` | Either ship on GCP_AMD_SEV, or say the attestation is simulated and the hash proves nothing. Do not present it as a guarantee. |
| "Auto-earn on a live, funded vault" | **Half true.** stXRP share price is exactly 1.000000 (A13) | Lead with TESTearnXRP at 1.05917, disclose the 300 s redemption lag |
| "Stop-loss" | **Overclaims** (A11) | "One-block conditional execution against FTSO with an oracle-enforced floor" |
| "Trimmy never holds the assets" | **False for one transaction** per execution — `transferFrom` into Trimmy, then out (`00-critique.md` C1) | "Trimmy holds an allowance, never a balance, except within a single atomic transaction." |
| "`execute()` re-derives every bound on-chain" | **True, and it is the good part** | Keep — but note it re-derives from a *rule the front end wrote* (A1) |
| "80/80 `getPool` = 0, so we seeded our own pool" | **True, verified, and disclosing it is a strength** | Keep, verbatim. It is the most credible sentence in the submission. |

---

## 7. What I did not check

Stated so the next reviewer knows where the holes are.

- **`01-ARCHITECTURE.md` itself** — it does not exist. If it lands and diverges from
  `keeper-security.md` §3.5, every code-level finding in §2 must be re-checked against it. §§3–6
  (authorization, liveness, premise, honesty) are design-level and survive a rewrite.
- **`_quote()`'s body** — never written down anywhere in the pack. A1's decimals attack and
  `GROUND-TRUTH` §5's negative-`int8`-decimals warning both land in that function and it is
  unspecified. **Experiment:** write it, fuzz it against a reference implementation in Python over
  `dec ∈ [−18, 18]` × both token decimals ∈ {6, 18}, and check the identity
  `quote(quote(x, p), 1/p) ≈ x` within 1 unit.
- **Whether a Coston2 V3 pool can actually be created and seeded with FXRP.** The factories exist and
  return `address(0)` for every FXRP pair; `createPool` was not attempted. **Experiment:**
  `createPool(FXRP, testUSDT, 3000)` then `mint` against `0x9788c2f2…`, and measure the gas and the
  C2FLR needed. This is on the critical path for A3 and nobody has run it.
- **Mainnet FXRP transfer fee** (A9). One `cast call`.
- **The FCC half's code paths** — I attacked its trust model (A16, A17, honesty row 5) from the
  existing documents, not its source. `00-critique.md` U4's unread sign-port interface is still unread.
- **Gas cost of `execute()`** — `GROUND-TRUTH` O-4, still open, and A10/L2's fee-cap sizing depends on
  it.
