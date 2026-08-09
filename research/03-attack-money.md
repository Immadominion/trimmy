# 03 — Attack: money

**Target:** the deployed code, not the spec. Trimmy `0xf73a2af06b315adaa1afe2c1a6c1a6933d8a6554`,
Coston2 (chainId 114). Lens: **where does value move, and who ends up short.**

All chain reads below were performed on 2026-08-07 against
`https://coston2-api.flare.network/ext/C/rpc` with `~/.foundry/bin/cast`.
All proofs-of-concept live in
`/Users/mac/Documents/codes/opensauce/flare/trimmy/contracts/test/AttackMoney.t.sol`
and **fail against the current contract**:

```
forge test --match-path test/AttackMoney.t.sol -vv
→ 7 failed, 1 passed
```

| id | severity | one line |
|----|----------|----------|
| M-1 | **critical** | `uint64 latchedPrice` saturates on the live FXRP→WC2FLR pair; the FTSO floor is computed from 10.7% of the real price |
| M-2 | **critical** | `claim()` pays one rule the whole `(Trimmy, period)` withdrawal bucket — the first claimer takes every other user's queued assets |
| M-3 | **high** | a second `_doQueueRedeem` overwrites `claimPeriod`; the earlier period's assets become permanently unclaimable |
| M-4 | **high** | the A12 latch never refreshes, so on a rising market every later part is fillable at the stale price |
| M-5 | medium | `_refund()` sweeps the contract's entire native balance to `msg.sender` |
| M-6 | medium | `_validate` never checks the EXIT_VAULT sell token against the vault's share token |
| M-7 | medium | `minOutAbsolute` is a **gross** floor; fees are deducted after it |
| M-8 | medium | EXIT_VAULT has no floor at all — neither `minOutAbsolute` nor `slippageBips` is read |

---

## Baseline: the live configuration

`[Verified — chain read 2026-08-07]`

```
$ cast call 0xf73a…6554 "tokenAt(uint8)((address,bytes21,uint8))" 0
(0x0b6A3645c240605887a5532109323A3E12273dc7, 0x015852502f5553440…, 6)   FXRP,   XRP/USD
$ cast call 0xf73a…6554 "tokenAt(uint8)((address,bytes21,uint8))" 1
(0xC67DCE33D7A8efA5FfEB961899C73fe01bCe9273, 0x01464c522f5553440…, 18)  WC2FLR, FLR/USD
$ cast call 0xf73a…6554 "maxFeedAge()(uint64)"   → 120
$ cast call 0xf73a…6554 "ruleCount()(uint256)"   → 4
```

FtsoV2 resolves to `0xC4e9c78EA53db782E28f28Fdf80BaF59336B304d`. Live feed reads:

```
XRP/USD → (1022160, 6,  1786077925)   $1.022160
FLR/USD → ( 592822, 8,  1786077936)   $0.00592822
```

Rules 2 and 3 are `verb=1` (DEPOSIT_VAULT), `venueId=1`, `sellTokenId=0`, `buyTokenId=0`,
`latchedPrice=1000000`. **No SWAP rule has been armed yet.** M-1 fires the moment one is.

---

## M-1 — `uint64 latchedPrice` saturates on the live pair, and the floor is derived from it

**Severity: critical. `[Verified]` — failing test `test_M1_uint64ClampMakesFloorMeaningless`.**

### The code

`contracts/src/Trimmy.sol:431-440` computes the relative price at full 256-bit width and then
throws the top bits away:

```solidity
uint256 relative = Quote.convert(
    10 ** uint256(_tokens[r.sellTokenId].decimals), sellFeed, …, buyFeed, …);
price = uint64(relative > type(uint64).max ? type(uint64).max : relative);
```

`Trimmy.sol:389` latches it (`if (r.latchedPrice == 0) r.latchedPrice = price;`) and
`Trimmy.sol:466-468` makes it the **sole** input to the only slippage floor in the system:

```solidity
uint256 oracleOut = (amountIn * uint256(r.latchedPrice)) / (10 ** uint256(sellCfg.decimals));
uint256 floorOut  = (oracleOut * (10_000 - r.slippageBips)) / 10_000;
```

The dimensional analysis is *correct* — `latchedPrice` is buy-base-units per one whole sell token,
and dividing by `10**sellDecimals` is right for both a 6dp and an 18dp sell token. **The width is
not.** The clamp at line 440 is written as if saturation were a theoretical edge; on the deployed
allowlist it is the normal case.

### The arithmetic, for the live pair

For FXRP → WC2FLR the exponent in `Quote.convert` (`Quote.sol:92-93`) is
`(18 + 8) − (6 + 6) = +14`:

```
relative = mulDiv(1e6, 1022160 × 1e14, 592822) = 172_422_750_842_580_066_191   (1.724e20)
uint64 max                                     =  18_446_744_073_709_551_615   (1.845e19)
ratio                                          = 9.347
```

`[Measured]` — computed by the contract's own `Quote.convert`, asserted in the PoC.

So `latchedPrice` stores **18.4467 WC2FLR per FXRP** when the truth is **172.42**. The reverse
direction is fine and that is exactly why nothing caught it: WC2FLR → FXRP gives
`exponent = −14`, `relative = 5799`, comfortably inside uint64 (`test_M1c_reverseDirectionFits`
passes). The existing 50-test suite never exercises the live pair at all — `Trimmy.t.sol:66-68`
pairs a 6dp token on a 6dp feed with a 6dp token on a 6dp feed, exponent 0, relative `3e6`.

### The failure scenario

A user arms `SWAP FXRP → WC2FLR`, 100 FXRP, `slippageBips = 50` (the strictest value
`MAX_SLIPPAGE_BIPS` permits), `minOutAbsolute = 0`. Fair proceeds at the oracle price are
17,242 WC2FLR. The enforced floor is 1,835 WC2FLR.

A searcher watching the mempool sandwiches the `exactInput` call on the V3 pool, pushing the
execution price down to 20 WC2FLR/FXRP, and unwinds after. The user receives 2,000 WC2FLR.
`_doSwap`'s check `actualOut < floorOut` — `2000e18 < 1835e18` — is **false**, so the trade
settles. Extraction is bounded only by pool depth, up to **89.3% of notional**, on a rule whose
declared tolerance was 0.5%.

```
[FAIL: M-1: enforced floor is far below the oracle floor:
       1835451035334100385692 < 17156063708836716586004]
  true relative (WC2FLR wei per 1 FXRP): 172422750842580066191
  uint64 max                            :  18446744073709551615
  fair proceeds  (wei WC2FLR): 17242275084258006619100
  actual proceeds(wei WC2FLR):  2000000000000000000000
  user loss %                : 89
```

### The same defect from the trigger side

`test_M1b_priceTriggerCannotSeeA9xMove` (also failing). Because `price` saturates,
`PRICE_ABOVE` on the live pair compares `type(uint64).max < r.triggerValue`, which is false for
every representable threshold. **A `PRICE_ABOVE` FXRP→WC2FLR rule fires unconditionally.** The PoC
pumps FLR 9.34x against XRP — a move that takes 1 FXRP from buying 172 WC2FLR down to 18.5 — and
the rule still executes. Symmetrically, `PRICE_BELOW` can never fire, and the user cannot even
*express* the threshold they want: 172e18 does not fit in `uint64`.

This is not a "prices could theoretically be large" argument. It is the current price of the two
tokens this contract was deployed to trade, chosen deliberately per GROUND-TRUTH §"Counter-token
choice" *because* it "exercises the quote path properly".

### Fix

`latchedPrice`, `triggerValue` and the `price` return of `_evaluateTrigger` must be `uint128`
(1.7e38 leaves ~18 orders of headroom over the worst allowlisted pair), and the saturating clamp at
`Trimmy.sol:440` must become a **revert**, never a silent truncation. The contract is
non-upgradeable, so this requires a redeploy; the four existing rules are DEPOSIT_VAULT and do not
depend on `latchedPrice`, so nothing is lost by migrating.

Interim mitigation without a redeploy: **do not arm any FXRP→WC2FLR SWAP rule against
`0xf73a…6554`**, and set `minOutAbsolute` to a real buy-token-denominated floor on any SWAP rule
that is armed, since `Trimmy.sol:469` lets it override the broken oracle floor upward.

---

## M-2 — `claim()` hands one rule the entire per-period withdrawal bucket

**Severity: critical. `[Verified]` — failing test
`test_M2_firstClaimerStealsEveryOtherUsersQueuedAssets`.**

`Trimmy.sol:516-537` queues every EXIT_VAULT redemption with `receiver == address(this)`:

```solidity
IQueuedVault(v.target).redeem(shares, address(this), address(this));
uint64 period = ((block.timestamp + lag) / 1 days).toUint64();
r.claimPeriod = period;
```

The vault keys its queue by `pendingWithdrawAssets[receiver][period]` (`Interfaces.sol:78`), i.e.
**by receiver, not by rule**. Trimmy is the receiver for every rule of every user. Then
`Trimmy.sol:543-566`:

```solidity
uint256 before = asset.balanceOf(address(this));
IQueuedVault(v.target).claimWithdraw(r.claimPeriod);   // drains the WHOLE bucket
uint256 assets = asset.balanceOf(address(this)) - before;
…
_settle(r, ruleId, asset, assets, 0);                  // → all of it to ONE r.account
```

`claimWithdraw(period)` credits `msg.sender` the full bucket. The measured delta is therefore
*every* user's queued assets for that day, and `_settle` sends the remainder to a single
`r.account`.

**Failure scenario:** Alice and Bob each queue a 100 FXRP vault exit on the same UTC day. Whoever
calls `claim(aliceRule)` first — and `claim` is permissionless by design, `Trimmy.sol:543` — pays
Alice 200 FXRP. `claim(bobRule)` then re-enters `claimWithdraw` on an emptied bucket, measures a
delta of 0, zeroes `r.pendingShares`, and pays Bob nothing. Bob's shares are already burned.

```
[FAIL: M-2: alice must receive exactly her own 100 FXRP: 200000000 != 100000000]
  alice received: 200000000
  bob   received: 0
```

There is no owner, no pause and no rescue function (`Trimmy.sol:18-22`), so this is unrecoverable
once it happens.

**Why it is not live today:** neither allowlisted token is the TESTearnXRP share token, so
EXIT_VAULT currently reverts (see M-6). The bug is one allowlist entry away from being live, and a
redeploy that "adds the vault share token so exits work" walks straight into it.

**Fix:** track per-rule entitlement. Either (a) record `assetsOwed` returned by `redeem` on the
rule and cap the payout at `min(assetsOwed, measuredDelta)`, keeping the rest in a
per-`(period)` ledger; or (b) give each rule its own receiver via a minimal per-rule
clone/escrow so the vault's own `receiver` keying does the isolation.

---

## M-3 — a second queue orphans the first period's assets

**Severity: high. `[Verified]` — failing test `test_M3_secondQueueOrphansTheFirstPeriodsAssets`.**

`Trimmy.sol:532-534`:

```solidity
r.pendingShares += shares.toUint128();   // accumulates
r.claimPeriod    = period;               // OVERWRITES
r.claimableAt    = claimableAt;          // OVERWRITES
```

`pendingShares` accumulates but `claimPeriod` is a single slot. A multi-part EXIT_VAULT rule
(`partSellAmount < totalSellAmount`, which the contract explicitly supports and `MIN_SCHEDULE_INTERVAL`
is only 60 s) whose parts straddle a UTC midnight files under two different day indices. The second
part overwrites the pointer to the first.

`claim()` then claims only the surviving period and zeroes `pendingShares` (`Trimmy.sol:560-562`),
so the earlier bucket can never be reached again — `claim` reverts `NothingPending` thereafter, and
`claimWithdraw` is not callable from anywhere else in the contract.

```
[FAIL: M-3: alice must receive both parts, not just the last period: 50000000 != 100000000]
  period1 still stranded in vault: 50000000
  alice received: 50000000
```

**Fix:** `claimPeriod` must be a set, not a scalar — e.g. `mapping(uint256 ruleId => uint64[])`,
with `claim(ruleId, period)` claiming one at a time and decrementing `pendingShares` by that
period's share, or refuse a second `_doQueueRedeem` while `pendingShares != 0`.

---

## M-4 — the A12 latch is one-sided

**Severity: high. `[Verified]` — failing test `test_M4_staleLatchLetsLaterPartsFillAtTheOldPrice`.**

`Trimmy.sol:387-389` latches on the first fire and `Trimmy.sol:462-467` never refreshes it. The
comment justifies this against a *falling* market: "a partial exit does not chase the market down."

In a *rising* market the same latch is a floor that is too **low**, and it stays wrong for up to
`MAX_RULE_LIFETIME` = 365 days. Every later part of a DCA/`SCHEDULE` rule is a standing offer at
the price of part one, minus slippage.

**Failure scenario** (PoC): a 2-part rule, 50 FXRP each, sells at 3.00 USDT and latches
`3_000_000`. XRP doubles to 6.00. Part 2 is worth 300 USDT; the enforced floor is
`50e6 × 3e6 / 1e6 × 0.995 = 149.25` USDT. A searcher fills at the old price and pockets the
difference:

```
[FAIL: M-4: part 2 filled 50% below the live oracle price: 150000000 < 298500000]
  fair value of part 2 (USDT): 300000000
  what the user received     : 150000000
```

The A2 argument — "the extractable band is linear in slippage, so 50 bips is a 2–4x reduction" —
does not hold here. The extractable band is `max(slippage, driftSinceLatch)`, and drift is
unbounded.

**Fix:** floor against `min(latchedPrice, livePrice)` — that keeps the A12 protection against
chasing a crash down while removing the free option in the other direction. One line at
`Trimmy.sol:466`.

---

## M-5 — `_refund()` sweeps the whole native balance

**Severity: medium. `[Verified]` — failing test `test_M5_refundSweepsWholeNativeBalance`.**

`Trimmy.sol:675-681`:

```solidity
uint256 bal = address(this).balance;   // not msg.value - fee
if (bal > 0) { (bool ok,) = msg.sender.call{value: bal}(""); ok; }
```

`receive() external payable {}` (`Trimmy.sol:687`) is open and `ISwapRouter.exactInput` is payable
and may refund. Any native the contract ever holds — a donation, a router refund, a mistaken
transfer — is paid to whoever calls `execute` next, which is permissionless.

```
[FAIL: M-5: keeper swept native it never supplied: 5000000000000000000 != 0]
  keeper native gain: 5000000000000000000
```

`calculateFeeById` returns 0 today (GROUND-TRUTH §5), so keepers send `msg.value = 0` and sweep
whatever is there for free. No user funds are at risk *today* because Trimmy holds no native by
design — but there is no rescue function, so this is also the only way anything sent here ever
comes back, and it comes back to the wrong person.

**Fix:** `uint256 refund = msg.value - fee;` computed in `_readFeeds` and threaded through.

---

## M-6 — EXIT_VAULT arms with an unchecked sell token

**Severity: medium. `[Verified]` — failing test `test_M6_exitVaultArmsWithTheWrongSellToken`.**

`Trimmy.sol:341-350`:

```solidity
address underlying = IQueuedVault(v.target).asset();
address sellToken  = _tokens[p.sellTokenId].token;
if (p.verb == Verb.DEPOSIT_VAULT && underlying != sellToken) revert VaultAssetMismatch(…);
```

The assertion is gated on `DEPOSIT_VAULT`. For `EXIT_VAULT` nothing checks that the sell token is
the vault's **share** token — which is what `_doQueueRedeem` burns. `execute` pulls
`sellCfg.token` from the user (`Trimmy.sol:400`) and then calls
`redeem(shares, address(this), address(this))` against Trimmy's *own* share balance. The two are
unrelated.

On the live allowlist neither FXRP nor WC2FLR is the TESTearnXRP share token, so:

- **Every EXIT_VAULT rule armable against `0xf73a…6554` today is dead.** `arm` accepts it; `execute`
  reverts in `redeem` forever. The arming payment is an irreversible XRPL transaction
  (`arming/bin/arm.dart`), so the user pays for a rule that can never run, and leaves a live FXRP
  allowance behind.
- If Trimmy ever holds share tokens from any source — anyone can `transfer` them in — the redeem
  succeeds against the donated shares and the user's pulled FXRP is **stranded in the contract with
  no rescue function**:

```
[FAIL: M-6: user's sell tokens are stranded forever: 100000000 != 0]
  user FXRP debited      : 100000000
  FXRP stranded in Trimmy: 100000000
```

**Fix:** in `_validate`, for `EXIT_VAULT`, require `_tokens[p.sellTokenId].token == v.target`.

---

## M-7 — `minOutAbsolute` is a gross floor, not a net one

**Severity: medium. `[Verified]` — code read, `Trimmy.sol:469`, `493`, `578-591`.**

`_doSwap` enforces the floor against `actualOut`, which is the **gross** balance delta, and only
afterwards does `_settle` subtract `keeperFee` and `protocolFee`. So a user who sets
`minOutAbsolute = X` — the one parameter documented as "user floor, independent of oracle"
(`01-ARCHITECTURE.md:170`) — can receive `X − keeperFee − protocolFee`.

Compounding it, `_settle` has no unit sanity check anywhere. `keeperFeeFlat` is denominated in the
**output** token; `partSellAmount` in the sell token; `_validate` (`Trimmy.sol:354-358`) relates
`keeperFeeFlat` only to `keeperFeeBudget`, never to expected proceeds. And when the fee exceeds the
proceeds, `Trimmy.sol:581` silently clamps instead of reverting:

```solidity
if (keeperFee > proceeds) keeperFee = proceeds;   // → protocolFee 0, toUser 0
```

A user who sets `keeperFeeFlat` at 18-decimal scale while selling into a 6-decimal token — exactly
the mistake the FXRP/WC2FLR pairing invites — hands the keeper **100% of every fill**, with no
revert and no event distinguishable from a normal execution. The arming CLI already carries a
version of this confusion: `arming/bin/arm.dart:287` sets
`minOutAbsolute: amount * 90 / 100`, i.e. 90% of the *sell* amount, compared by the contract
against *output* units. It is harmless only because that path hardcodes `verb: 1` (DEPOSIT_VAULT)
on a 1:1, same-decimal vault.

**Fix:** enforce `toUser >= r.minOutAbsolute` in `_settle`, and revert rather than clamp when
`keeperFeeFlat > proceeds`.

---

## M-8 — EXIT_VAULT has no floor at all

**Severity: medium. `[Verified]` — `grep -n "minOutAbsolute\|slippageBips" src/Trimmy.sol`.**

The only reads are:

```
468:  uint256 floorOut = (oracleOut * (10_000 - r.slippageBips)) / 10_000;   // _doSwap
469:  if (r.minOutAbsolute > floorOut) floorOut = r.minOutAbsolute;          // _doSwap
509:  if (shares < r.minOutAbsolute) revert FloorBreached(…);                // _doDeposit
```

Neither `_doQueueRedeem` nor `claim` consults either field. A vault exit settles at whatever the
vault pays, whenever it pays it, with the user's declared floor ignored. `execute` still reads and
staleness-checks both FTSO feeds on that path (`Trimmy.sol:382-385`) and still spends the gas —
the oracle is read and then not used for anything.

**Fix:** apply `assets >= r.minOutAbsolute` in `claim`, or state explicitly in the rule struct that
EXIT_VAULT is unfloored so arming tooling can refuse to build one.

---

## Paths checked and found sound

Recorded so a later reader does not re-derive them.

- **`_settle` cannot underflow.** `protocolFee = ((proceeds − keeperFee) × bips) / 10_000` with
  `bips ≤ 50`, so `protocolFee ≤ proceeds − keeperFee` and `toUser = proceeds − keeperFee −
  protocolFee ≥ 0`. `keeperFee` is clamped to both `budgetLeft` and `proceeds` first
  (`Trimmy.sol:578-581`). `[Verified]`
- **The protocol fee base excludes the keeper fee**, which is the user-favourable ordering.
  `[Verified — Trimmy.sol:583]`
- **Rounding remainders go to the user.** `protocolFee` and `oracleOut` both floor; the residue
  falls into `toUser`. `[Verified]`
- **`_doSwap` dimensional analysis is correct for both 6dp and 18dp sell tokens** —
  `amountIn × latchedPrice / 10**sellDecimals` is buy-base-units. The defect in M-1 is width, not
  units. `[Verified — checked against `Quote.convert`'s derivation, `Quote.sol:66-71`]`
- **`r.spent += received` before the venue call is safe.** A venue revert reverts the whole
  transaction and the storage write with it; `execute` and `claim` are both `nonReentrant`
  (transient), and `_refund`'s raw call is the last statement, inside the guard.
  `[Verified — Trimmy.sol:372, 404, 543]`
- **`received` is the measured `balanceOf` delta**, so a fee-on-transfer sell token debits `spent`
  correctly (A9). `[Verified — Trimmy.sol:399-404]`
- **The reverse swap direction (WC2FLR→FXRP) is numerically sound.** `relative = 5799`, truncation
  error 7e-8 relative, four orders below the 50-bip band. `[Measured —
  `test_M1c_reverseDirectionFits` passes]`

---

## Suggested order of work

1. **M-1** and **M-2** are redeploy-blocking. Neither is patchable in place — there is no proxy.
2. **M-3**, **M-6**, **M-8** are the EXIT_VAULT cluster; fixing them together is one change to
   `_validate`, `_doQueueRedeem` and `claim`.
3. **M-4** and **M-7** are one line each in `_doSwap` / `_settle`.
4. **M-5** is cosmetic until the FTSO fee is switched on, at which point it is a real leak.

Before the redeploy, add the live pair to the test fixtures. The single reason M-1 survived 50
passing tests is that every test token is 6dp on a 6dp feed, which puts `exponent = 0` and
`relative = 3e6` — nine orders of magnitude away from the boundary the deployment actually sits on.
