# 03 — Attack: the oracle path

**Lens:** oracle. **Target:** deployed code, not a spec.
`contracts/src/Quote.sol`, `contracts/src/Trimmy.sol` (`_readFeeds`, `_evaluateTrigger`, `_doSwap`),
against Trimmy `0xf73a2af06b315adaa1afe2c1a6c1a6933d8a6554` on Coston2 (chainId 114).

**Reproduction of everything below:**

```bash
cd contracts && forge test --match-path 'test/oracle/*' -vv     # 17 of 28 tests FAIL by design
python3 tools/sample_latch_drift.py 48000 400                   # 28.8 h, stride 400
python3 tools/sample_latch_drift.py 900 1                       # 901 contiguous blocks
```

Result at the time of writing: `AttackOracle.t.sol` 6 fail / 5 pass, `AttackOracle2.t.sol` 5 fail /
6 pass, `AttackOracle3.t.sol` (this pass) **6 fail / 0 pass**. A failing test here is a proven
finding; a passing test is a refuted one, kept so it is not re-attacked.

---

## 0. Live chain reads used throughout

`[Verified]` FtsoV2 resolved from the registry, not recalled:

```
$ cast call 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019 \
    "getContractAddressByName(string)(address)" "FtsoV2" --rpc-url $R
0xC4e9c78EA53db782E28f28Fdf80BaF59336B304d
```

`[Verified]` The deployed allowlist, read off the deployed contract:

```
$ cast call 0xf73a…6554 'tokenAt(uint8)((address,bytes21,uint8))' 0
(0x0b6A3645c240605887a5532109323A3E12273dc7, 0x015852502f5553440000…, 6)   # FXRP,   XRP/USD
$ cast call 0xf73a…6554 'tokenAt(uint8)((address,bytes21,uint8))' 1
(0xC67DCE33D7A8efA5FfEB961899C73fe01bCe9273, 0x01464c522f5553440000…, 18)  # WC2FLR, FLR/USD
$ cast call 0xf73a…6554 'maxFeedAge()(uint64)'   ->  120
```

`[Measured]` Live feeds, block 33727889-ish, 2026-08-07:

| feed | value | decimals | price |
|---|---:|---:|---|
| XRP/USD | 1 021 607 | 6 | $1.021607 |
| FLR/USD | 593 189 | 8 | $0.00593189 |

`calculateFeeById` returns **0** for both. `[Verified]`

**Relative price of the deployed pair: 172.19 WC2FLR per XRP = 1.7219 × 10²⁰ WC2FLR wei.**

`[Measured]` `tools/sample_latch_drift.py`, 1022 **pinned** block reads (`eth_call` pinned to the
same block whose `timestamp` it is compared against — the methodology GROUND-TRUTH §5 requires):

```
XRP leg signed age (block.ts - feed.ts): min 0  p50 0  p99 24  max 32
FLR leg signed age:                      min 0  p50 0  p99 24  max 32
readings with the feed AHEAD of the block clock: 0 / 1022, both legs
drift of XRP/FLR over  300 s: p50  13.7  p99  57.1  max  60.1 bips
drift of XRP/FLR over 3600 s: p50  22.1  p99  82.4  max 108.3 bips
drift of XRP/FLR over 21600s: p50  46.1  p99 133.0  max 133.0 bips
drift of XRP/FLR over 86400s: p50 140.3  p99 201.7  max 201.7 bips
```

`[Verified]` All four live rules are `DEPOSIT_VAULT`, `sellTokenId == buyTokenId == 0`, `spent ==
total`, `active == false`, `latchedPrice == 1000000`. The swap path is armed-and-untested on chain,
which is why the clamp below has not yet cost anyone money.

---

## The headline

> **The FTSO price never reaches the floor it is supposed to set.**
>
> On the deployed FXRP → WC2FLR pair the price is truncated by 9.33× before it is stored
> (`Trimmy.sol:440`), and whatever survives is frozen forever at whatever value the *first
> permissionless caller* chose to latch (`Trimmy.sol:389`). `Quote.sol` is exact and irrelevant.

---

## NEW findings, this pass (O-15 … O-19)

The previous oracle pass attacked properties of a *single* execution. This pass attacks the only
property that exists *across* executions: `Rule.latchedPrice`.

`grep -n latchedPrice src/Trimmy.sol` returns exactly three lines: the declaration (89), the
one-time write (389), and the read (467). **There is no code path in Trimmy.sol that ever writes it
a second time.** Not `_advance` (596-614), not `_settle` (571-594), not `cancel` (625-631).

### O-15 — CRITICAL. The first executor picks the floor for the entire rule, and the first executor is anybody.

`[Verified]` `arm` writes `nextEligibleAt: block.timestamp.toUint64()` (`Trimmy.sol:301`), so a rule
is executable by any address in the very next block. `execute` is permissionless
(`Trimmy.sol:372`). The first call writes `latchedPrice` (`Trimmy.sol:389`) and every later part is
floored against it (`Trimmy.sol:466-468`).

An attacker therefore does not have to beat the oracle. It simply **declines to execute until the
oracle prints a low**, then executes one part at that low, and the floor for the rest of the rule's
life is that low.

`[Measured]` The 24 h range of XRP/FLR on Coston2 is 201.7 bips — that is the p99 *and* the max of a
single sampled day, not a tail event. `MAX_RULE_LIFETIME` is 365 days, so the attacker's waiting
window is effectively unbounded.

**Failure scenario (PoC, fails against current code):**
`test/oracle/AttackOracle3.t.sol::test_O15_keeperChosenLatchWidensTheFloorByTheWholeDailyRange`

```
latched (stale) relative: 5692        # keeper waited one day for the low
live relative           : 5806
fair out for part 2     : 580600
actually delivered      : 566354
loss vs FTSO, bips      : 245         # the rule authorised 50
[FAIL] 566354 < 577697
```

245 bips extracted on a rule whose only stated bound is 50. Deliberately run on **WC2FLR → FXRP**,
the direction where the O-1 clamp does *not* bite, so this is not a restatement of O-1.

**Fix:** re-latch when the live price is more favourable than the latch —
`if (price > r.latchedPrice) r.latchedPrice = price;` for a sell-side rule — or bound the latch's
age and recompute past it. The current one-way latch is strictly worse than no latch for the
attacker-favourable direction.

### O-16 — HIGH. The same write, inverted, is a permanent one-transaction denial of service.

`[Verified]` If part 1 executes at a local **maximum**, `floorOut` for every later part is
`amountIn × thatMaximum × 0.995`, forever. The market no longer offers it, no refresh exists, and
the user's only remedy is `cancel` — which is exactly the outcome an attacker wanting the allowance
gone would choose.

Attacker cost: one execution at a price they were happy to pay (they can even take the keeper fee
for it). Victim cost: the remainder of a rule that may have 364 days to run, with a live FXRP
allowance to Trimmy the whole time.

**Failure scenario (PoC):**
`test/oracle/AttackOracle3.t.sol::test_O16_latchingAtALocalMaximumBricksTheRuleForItsWholeLife`

```
floor still demanded  : 589537        # latched 201 bips above market
fair value at market  : 580600
parts filled after 28 honest days: 1  # 28 consecutive honest attempts, all reverted
[FAIL] 100000000000000000000 <= 100000000000000000000
```

The loop feeds the venue an **honest fill at the live oracle price** on each of 28 days. Every one
reverts.

### O-17 — MEDIUM. The floor is checked on gross proceeds; the fees are taken afterwards.

`[Verified]` `Trimmy.sol:493` asserts `actualOut >= floorOut`. `Trimmy.sol:583-591` then removes
`keeperFee` and `protocolFee` **from that same `actualOut`** and sends the remainder to
`r.account`. Nothing re-checks the remainder against the oracle.

`MAX_PROTOCOL_FEE_BIPS` is 50 (`Trimmy.sol:137`) — the same size as `MAX_SLIPPAGE_BIPS`. So the
band visible to the account is up to **2×** what the `slippageBips` parameter names, before a flat
keeper fee that has no cap beyond `keeperFeeBudget`.

**Failure scenario (PoC):**
`test/oracle/AttackOracle3.t.sol::test_O17_theFloorIsOnGrossProceedsNotOnWhatTheAccountReceives`

```
oracle value of the part: 580600
floor the venue cleared : 577697      # 50 bips, as authorised
what the account got    : 573814
account loss vs FTSO, bp: 116         # 50 slippage + 50 protocol + flat keeper fee
[FAIL] 573814 < 577697
```

**Fix:** take fees before the floor check, or check `proceeds - keeperFee - protocolFee >= floorOut`.

### O-18 — MEDIUM. The unbounded future-timestamp branch is not a one-block problem; it poisons the floor permanently.

`[Verified]` `Quote.sol:52-60` measures age only on the `block.timestamp > feed.timestamp` branch. A
feed dated in the future is age zero however far ahead and whatever price it carries. O-4 (previous
pass) shows the read is accepted. This shows the damage does not end there: the accepted price is
written into `latchedPrice` and becomes the floor for the rest of the rule, long after the feed is
honest again.

`[Measured]` The comment justifying the branch (`Quote.sol:48-51`) says "a feed one second ahead of
the block clock is normal". Over **1022 pinned block reads on both allowlisted feeds,
`min(block.timestamp − feed.timestamp) == 0` and 0/1022 readings had the feed ahead.** The
unbounded window is buying liveness that was never observed to be at risk.

> Methodology note, because I got this wrong first: an *unpinned* `cast call` at `latest` paired
> with a separate `cast block latest` did show the feed 1–5 s ahead. That is the two calls landing
> on different blocks — the same error class GROUND-TRUTH §5 records for feed age. Pinned, the
> effect is exactly zero. I am reporting the pinned number.

**Failure scenario (PoC):**
`test/oracle/AttackOracle3.t.sol::test_O18_oneFutureDatedReadPoisonsTheFloorPermanently`

```
fair out : 580600
delivered: 481381     # 1710 bips below FTSO, on a feed that has been honest for a day
[FAIL] 481381 < 577697
```

**Fix:** `if (feed.timestamp > block.timestamp + SKEW) revert FeedStale(...)` with `SKEW` a small
constant (2 s covers anything measured). Symmetric bounds cost nothing.

### O-19 — MEDIUM. GROUND-TRUTH's stated justification for `maxFeedAge = 120` is false.

`[Verified]` GROUND-TRUTH §5 justifies 120 s over the 68 s its own data suggests with:

> "too loose is bounded on the other side by the FTSO-derived execution floor, which rejects a bad
> fill regardless of how the price was aged."

**The floor *is* the aged price.** `floorOut = amountIn × latchedPrice × (1 − slippage)`
(`Trimmy.sol:466-468`), and `latchedPrice` came from that same possibly-120-s-stale read
(`Trimmy.sol:389` ← `_evaluateTrigger:431` ← `_readFeeds:666-672`). A stale price is not caught by
the floor; it *becomes* the floor. With O-15 it becomes the floor permanently. The asymmetry
argument that sized the parameter does not hold, and the parameter is `immutable` on a
non-upgradeable contract (`Trimmy.sol:143`).

`[Measured]` Against the two numbers that matter:

| quantity | measured | deployed / authorised |
|---|---:|---:|
| worst feed age, 1022 pinned reads | 32 s | `maxFeedAge` = 120 s (3.75×) |
| worst XRP/FLR move over 300 s | 60.1 bips | `MAX_SLIPPAGE_BIPS` = 50 |

**Failure scenarios (PoC):** `test_O19a_stalenessWindowIsOversizedAgainstItsOwnMeasurement`
(`120 > 64`), `test_O19b_fiveMinuteRealisedMoveExceedsTheWholeSlippageBudget` (`60 > 50`).

**Answering the question directly — "is 120 s of staleness enough to profit given 50 bips?"**
`[Measured]` Yes, and the two bands are additive because nothing compares the aged price to a fresh
one. Worst 120 s move measured on Coston2 is 38.94 bips (`sample_rel_volatility.py`, two separated
901-block windows). Extractable band = 38.94 + 50 = **88.94 bips**, versus the 50 the rule
authorised. That is a *calm testnet* sample and a lower bound: XRP mainnet realised volatility is
higher. And per O-15 the correct number is not the 120 s move at all — it is the move since the
latch, which measured 201.7 bips over one day and is unbounded over 365.

---

## Findings from the previous oracle pass that are STILL LIVE

Re-run and re-verified against the current source, not taken on trust.

### O-1 / O-2 — CRITICAL. The `uint64` clamp throws away 89.3% of the deployed pair's floor.

`[Verified]` `Trimmy.sol:440`:

```solidity
price = uint64(relative > type(uint64).max ? type(uint64).max : relative);
```

`relative` is buy-token base units per one whole sell token. For FXRP → WC2FLR that is
`(XRP/FLR) × 10¹⁸`. At the live ratio of 172.19 it is **1.7219 × 10²⁰**, and `type(uint64).max` is
1.8447 × 10¹⁹ — **9.33× smaller**. The clamp bites whenever `XRP > 18.45 × FLR`; FLR would have to
reach $0.0554 (9.3× its live price) for it to stop.

`[Verified]` PoC output, `test_O2_floorAcceptsAnEightyNinePercentHaircut`:

```
fair value of 100 FXRP (WC2FLR wei): 17191801031530992296300
what the user actually received    :  1835634580000000000000
loss, bips                         : 8932
```

**A "50 bip" rule accepts an 89.32% haircut.** Anyone can be the keeper; the extraction is a
sandwich around a swap whose `amountOutMinimum` is 10.7% of fair value.

Note for whoever fixes this: widening `latchedPrice` alone is not enough. `triggerValue` is `uint64`
too (`Trimmy.sol:86`), and the arming ABI hardcodes it — `arming/bin/arm.dart:115` encodes
`arm((uint8,uint8,uint8,uint8,uint8,uint128,uint128,uint128,uint64,uint64,uint16,uint16,uint128,uint128))`.
The fix is a redeploy plus an arming-tool change, and the XRPL arming payment is irreversible.

### O-3 — CRITICAL. On the deployed pair, price triggers are constant functions.

`[Verified]` Because `price` is pinned at `type(uint64).max`:

- `PRICE_BELOW` (`Trimmy.sol:443`, `price > triggerValue` ⇒ revert) can **never** fire unless
  `triggerValue == type(uint64).max` exactly. `test_O3_priceBelowStopLossNeverFires` reverts
  `TriggerNotMet(18446744073709551615, 18446744073709551614)` after a **70% crash**.
- `PRICE_ABOVE` (`Trimmy.sol:445`) fires **unconditionally** for every expressible threshold.
- The one threshold that does fire, `type(uint64).max`, means "1 XRP ≤ 18.446 WC2FLR" — an 89%
  crash — and fills at 171.9. `test_O3_priceBelowAtMaxThresholdFiresAtNineTimesTheStop`.

A stop-loss product whose stop is a constant is not a stop-loss.

### O-4 — MEDIUM. Unbounded future timestamp (see O-18 for the composition).

`[Verified]` `test_O4_farFutureFeedTimestampBypassesStaleness`: a feed dated `block.timestamp + 365
days` executes. `Quote.sol:54`.

### O-7 — MEDIUM. Two of three verbs have no oracle floor at all.

`[Verified]` `_doDeposit` (`Trimmy.sol:498-512`) floors only against user-supplied `minOutAbsolute`;
`sellFeed`, `buyFeed` and `latchedPrice` do not appear in it.
`test_O7_vaultDepositHasNoOracleFloor` accepts a 99% share-price haircut inside a 50-bip rule.
`claim` (`Trimmy.sol:543-566`) has no floor whatsoever, not even `minOutAbsolute`. Both feeds are
still read, paid for and staleness-gated in `execute`, so a stale feed bricks a verb that never uses
a price (`test_O7_exitVaultIsBrickedByAFeedItNeverUses`, `test_O8_*`).

`Quote.sol:8` — "The execution floor for every Trimmy rule is computed here" — is false for 2 of 3
verbs.

### O-8 — MEDIUM. The four live rules make the oracle pure downside.

`[Verified]` `_validate` rejects `sellTokenId == buyTokenId` only for `Verb.SWAP` (`Trimmy.sol:340`).
`arm.dart:281-282` passes `sellTokenId: 0, buyTokenId: 0` for the vault verb, and all four on-chain
rules carry it (`latchedPrice == 1000000` confirms: `mulDiv(10⁶, v, v) == 10⁶` for every `v`). The
price output is an algebraic constant while every FTSO revert path — `FeedStale`, `FeedValueZero`,
`InsufficientFeeValue` — stays armed against it.

### O-9 — MEDIUM. The only executor cannot pay a fee the contract insists on.

`[Verified]` `_readFeeds` reverts `InsufficientFeeValue` when `msg.value < fee`
(`Trimmy.sol:663`). `keeper/bin/keeper.dart` attaches value nowhere: `grep -n "value" keeper.dart`
finds only a local variable name and a comment; the send path shells out to `cast mktx` (line
198-213) with no `--value`. The day governance sets a nonzero FTSO fee, every rule bricks for this
keeper.

### O-10 — MEDIUM. `minOutAbsolute`, the only user-side defence against O-1/O-2, bricks the dust tail.

`[Verified]` `Trimmy.sol:392-394` shrinks the final part to the remainder; `Trimmy.sol:469` does not
shrink `minOutAbsolute` with it. `test_O10_minOutAbsoluteBricksTheDustTail`: a 50-WC2FLR tail worth
291 200 FXRP units is measured against a floor of 580 000, forever.

---

## Refuted — do not re-attack

| claim | verdict | evidence |
|---|---|---|
| `_readFeeds` splits the fee as "half", underpaying one leg | **False** | `half = calculateFeeById(sellFeedId)`, `fee - half = buyFee`. Exact for asymmetric fees. `test_O5_asymmetricFeesAreSplitCorrectly` passes with fees 9/1: the legs receive 9 and 1. `[Verified]` |
| `sell.value * scale` overflows for the allowlisted pairs | **False** | exponent = (18+8)−(6+6) = 14, scale = 10¹⁴. Overflow needs an XRP/USD mantissa ≥ 1.158×10⁶³; observed 1.02×10⁶. Headroom > 10⁵⁰×. And it is Solidity 0.8 checked arithmetic — a revert, never a wrap. `test_O13` passes. `[Verified]` |
| Cross-leg timestamp skew is exploitable | **Unreachable in practice** | The code has no gap check and would accept legs 239 s apart (`test_O14` passes, proving the gap is unchecked). Measured: `|ts_xrp − ts_flr|` p50/p99/max = 0/0/0 over 1802 pinned reads. Real in the code, empty on chain. `[Measured]` |
| FTSO publishes ahead of the block clock on Coston2 | **False, pinned** | 0/1022 pinned reads. The 1–5 s "ahead" I first saw was two RPC calls on different blocks. `[Measured]` |
| A stale price is caught by the FTSO floor (GROUND-TRUTH §5) | **False** | See O-19. The floor is derived from the stale price. `[Verified]` |

---

## Ranked repair list

1. **Widen the price field.** `latchedPrice` and `triggerValue` to `uint128` (or store `relative`
   normalised to 1e18 with an explicit `priceScale`). Until then the deployed FXRP → WC2FLR swap
   path must not be used. Redeploy + `arm.dart:115` ABI change.
2. **Make the latch monotone in the user's favour, or age-bounded.** One line at `Trimmy.sol:389`
   removes both O-15 and O-16.
3. **Bound the future branch.** `Quote.sol:54` — reject `feed.timestamp > block.timestamp + 2`.
4. **Check the floor on net, not gross.** `Trimmy.sol:493` / `Trimmy.sol:583-591`.
5. **Give the vault verbs a floor, or stop charging them for an oracle they do not use.**
   `Trimmy.sol:498-512`, `543-566`.
6. **Tighten `maxFeedAge` to ~64 s** (2× the max-of-p99, which is what the data supports) once (2)
   removes the liveness asymmetry that justified 120.
7. **Teach the keeper to attach `msg.value`.** `keeper/bin/keeper.dart`.

---

## Artefacts

- `contracts/test/oracle/AttackOracle3.t.sol` — 6 new PoCs, all failing against current code.
- `tools/sample_latch_drift.py` — pinned signed-feed-age and multi-horizon drift measurement.
- Prior pass, re-verified: `contracts/test/oracle/AttackOracle.t.sol`,
  `contracts/test/oracle/AttackOracle2.t.sol`.
