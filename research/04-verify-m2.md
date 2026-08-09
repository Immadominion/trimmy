# M-2 — verification: the shared per-period vault withdrawal bucket

**Verdict: M-2 REPRODUCES on the deployed contract.** Proven by a Foundry test running the
*byte-identical runtime bytecode* of `0xeaF2eA3924D5337B2Dd22ae7BFCACEdAc3D913D5`, not a
transcription of it. A rule that queued **1 base unit** was paid **100,000,001 base units** — the
entire pooled bucket, including another account's whole exit.

**Severity as deployed: HIGH, latent.** The mechanism is critical in shape (unbounded cross-user
theft, plus a permanent-loss griefing variant any passerby can trigger for gas). It is *not*
currently exploitable through any honest path, because `EXIT_VAULT` is unreachable on the live
allowlist. But it is unlocked by a single unauthenticated ERC-20 transfer — no redeploy, no
governance action, no allowlist change.

**HEAD is fixed.** `src/Trimmy.sol` grew a `pendingAssets` field at **16:03 on 2026-08-07 — during
this investigation** — which caps the payout. The fix is correct under every scenario I could
construct. **It is not deployed.**

Test file: `/Users/mac/Documents/codes/opensauce/flare/trimmy/contracts/test/M2Verify.t.sol`
(11 tests, all passing). Bytecode fixture:
`/Users/mac/Documents/codes/opensauce/flare/trimmy/contracts/test/fixtures/trimmy-deployed-initcode.hex`.

---

## 1. Method — testing the deployed contract, not a model of it

Every previous attempt at M-2 (`test/VerifyM2.t.sol`, `test/RefuteM2.t.sol`) hand-transcribed
Trimmy's claim logic, which leaves the conclusion hostage to transcription error. I avoided that
entirely.

`broadcast/Deploy.s.sol/114/run-1786085219320.json` records the creation transaction for
`0xeaF2eA39…`. I stripped the ABI-encoded constructor tail off that calldata and kept the init
prefix, then re-ran it in Foundry with local mocks substituted for the Coston2 allowlist. Token and
venue configuration lives in *storage*, so it can differ freely; the two immutables (`maxFeedAge`,
`protocolFeeRecipient`) are baked into *code*, so I passed the live values `120` and
`0x38d58d1BEA8FF21fd8397494f17F64A99bcF8E83`.

The result is asserted equal to the chain: `[Measured]`

```
test_deployedBytecodeIsByteIdenticalToCoston2  PASS
  keccak256(local runtime) == keccak256(eth_getCode(0xeaF2eA39…))
                           == 0x260468008c61c42709beaf28f15dce15a969cfe4354ebf4082ca462a95d6b725
  runtime bytes: 17220
```

So the tests below execute the same EVM code that is live on Coston2. A companion test
(`test_headIsNotTheDeployedBytecode`) asserts HEAD hashes differently, so the file cannot silently
degrade into testing one contract twice.

### The deployed contract is provably pre-fix `[Measured]`

| Probe | Deployed `0xeaF2eA39…` | HEAD |
|---|---|---|
| `ruleAt(0)` return width | **24** words | 25 words (`pendingAssets` appended) |
| `RedemptionAlreadyPending(uint64)` selector `0x075ae391` in runtime | **absent** | present |
| runtime size | 17,220 bytes | 17,387 bytes |

---

## 2. The vault side is exactly as M-2 describes `[Verified]`

Fetched from the explorer, contract `MyERC4626`, allowlisted as `venueAt(1)`:

```
curl -s "https://coston2-explorer.flare.network/api?module=contract&action=getsourcecode\
&address=0x9E63a5D282F2fBb7DcE822B98e363b2719D28319"
```

Line numbers below are into that verified source.

**The bucket is keyed `[receiver][period]` and is additive** — `_withdraw`, L379-388:

```solidity
uint256 period = _getPeriodFromDate(year, month, day);   // dayIndex(now + lagDuration), L376-377
if (pendingWithdrawAssets[_receiver][period] == 0) { uniqueReceivers[period].push(_receiver); }
pendingWithdrawAssets[_receiver][period] += _assets;     // L385  <-- POOLED
pendingWithdrawShares[_receiver][period] += _shares;     // L386
```

**`claimWithdraw(period)` drains the whole bucket to `msg.sender`, with no notion of who asked** —
L86-95:

```solidity
function claimWithdraw(uint256 _period) public returns (uint256 _assets) {
    require(_period < _getPeriodFromDate(year, month, day), InvalidPeriod());
    (, _assets, ) = _completeWithdraw(msg.sender, _period);   // L92
```

`_completeWithdraw`, L394-412, deletes the entire entry and transfers **all** of it:

```solidity
_assets = pendingWithdrawAssets[_receiverAddr][_period];      // L401
require(_assets > 0, NoPendingWithdrawAssets());              // L402  <-- REVERTS, not silent 0
delete pendingWithdrawAssets[_receiverAddr][_period];         // L407
SafeERC20.safeTransfer(IERC20(asset()), _receiverAddr, _assets);  // L411  <-- WHOLE bucket
```

**`PERIOD_DURATION = 1 days`** (L15), so `_getPeriodFromDate` is exactly the UTC day index, which
matches Trimmy's `((block.timestamp + lag) / 1 days)` at `Trimmy.sol:559`.

**And the decisive fact: Trimmy is a single shared receiver for every rule.** `Trimmy.sol:552`
passes `address(this)` as the receiver for all of them:

```solidity
uint256 assets = IQueuedVault(v.target).redeem(shares, address(this), address(this));
```

So `pendingWithdrawAssets[Trimmy][period]` is one pot that every rule redeeming that day pays into,
and `claimWithdraw` empties it in one go. The deployed `claim()` then measured the balance delta
around that call and handed **the entire delta** to whichever single rule was named:

```solidity
uint256 before = asset.balanceOf(address(this));
IQueuedVault(v.target).claimWithdraw(r.claimPeriod);
uint256 assets = asset.balanceOf(address(this)) - before;   // the whole pot
...
_settle(r, ruleId, asset, assets, 0);                        // paid to ONE rule.account
```

Two additional unauthenticated entry points on the vault matter and are modelled in the test:
`claim(uint256 year, uint256 month, uint256 day, address receiverAddr)` is `public` with **no access
control** (L133-152), and `setLagDuration(uint256)` is `public` with **no access control** (L182).

---

## 3. What reproduces, on the deployed bytecode

### 3.1 First claimer takes the entire bucket — the M-2 claim, confirmed `[Measured]`

`test_M2_deployed_firstClaimerTakesTheWholeBucket` — two rules, two different accounts, one period:

```
precondition: pendingWithdrawAssets[Trimmy][10] == 100000001   (both rules pooled)
mallory queued        : 1
mallory was paid      : 100000001
alice queued          : 100000000
then alice's claim()  : revert NoPendingWithdrawAssets()
alice's rule still reports pendingShares == 100000000
```

Mallory's rule was paid 100,000,000× what it queued. Alice's position is gone, and because the real
vault *reverts* rather than returning zero, her rule cannot even be closed out. Trimmy has no owner,
no sweep and no rescue function, so this is terminal.

### 3.2 No attacker required `[Measured]`

`test_M2_deployed_sameUserSecondRuleIsWedged` — one honest user, two of her own rules, same day. The
first `claim()` takes both positions; the second reverts forever with `pendingShares == 30000000`.
The money is not stolen here (both rules pay the same account), but the second rule is permanently
wedged. This means M-2 is not only an adversarial finding: **the ordinary two-rules-in-one-day case
is already broken.**

### 3.3 A passerby can permanently destroy a position for gas `[Measured]`

`test_M2_deployed_publicPushClaimPermanentlyBricksTheRule` — this is the variant I consider worst,
and it needs no attacker profit motive at all.

The vault's `claim(y, m, d, receiver)` (L133) is public and unauthenticated. Any address can call
`vault.claim(y, m, d, Trimmy)`. That drains `[Trimmy][period]` and pushes the assets **into Trimmy**.
Now the deployed `Trimmy.claim()` — which has no `try/catch` — calls `claimWithdraw` on an empty
bucket, hits `require(_assets > 0)` at L402, and **the entire transaction reverts**.

```
bucket pushed out; 200000000 FXRP now sitting inside Trimmy
keeper claim  -> revert NoPendingWithdrawAssets()
+3650 days, alice claim -> revert NoPendingWithdrawAssets()
alice paid: 0        rule pendingShares: 100000000 (bricked)
permanently locked in Trimmy: 200000000
```

There is no code path in Trimmy that can ever move that token again. This is unrecoverable loss of
100% of the position, inflicted unilaterally by any third party, at the cost of one transaction.

---

## 4. Reachability — why this is latent rather than live

`_doQueueRedeem` burns **share** tokens that Trimmy must already hold. The live allowlist does not
contain the share token. `[Measured]` 2026-08-07:

```
tokenCount 2   tokenAt(0) 0x0b6A3645…(FXRP, XRP/USD, 6dp)
               tokenAt(1) 0xC67DCE33…(WC2FLR, FLR/USD, 18dp)
venueCount 2   venueAt(1) 0x9E63a5D2…(QUEUED_VAULT)      <-- share token is a VENUE, not a TOKEN
TESTearnXRP.balanceOf(0xeaF2eA39…) == 0
ruleCount 1, and rule 0 is verb=1 (DEPOSIT_VAULT), spent, inactive — no EXIT_VAULT rule exists
```

So an `EXIT_VAULT` rule can only name FXRP or WC2FLR as its sell token. `execute()` pulls that many
FXRP and then asks the vault to burn that many **shares** from a Trimmy holding zero — it reverts.
`test_exitVaultIsUnreachableWithoutDonatedShares` confirms this against the deployed bytecode.
Nothing in `contracts/script/` or the Dart SDK arms an `EXIT_VAULT` rule (grep: no hits).

**But the lock is on the outside of the door.** `test_oneShareTransferUnlocksTheVulnerablePath`
shows that a single permissionless `TESTearnXRP.transfer(Trimmy, n)` — from the victim setting up
her own exit, or from anyone at all — makes the whole vulnerable path live immediately, with no
redeploy and no configuration change. And note that allowlisting the share token is precisely what
anyone would have to do to make `EXIT_VAULT` usable as intended, at which point this becomes a
first-class critical.

That is the basis for grading it **High/latent** rather than Critical-live: no user funds are at
risk *right now*, but the gap between "safe" and "fully exploitable" is one ERC-20 transfer.

Secondary note: `_validate` asserts `underlying == sellToken` for `DEPOSIT_VAULT`
(`Trimmy.sol:366-368`) but imposes **no equivalent constraint for `EXIT_VAULT`**. That missing
assertion is why a nonsensical FXRP-selling exit rule can be armed at all, and why the FXRP it pulls
is silently stranded in the contract.

---

## 5. HEAD is fixed — verified, including the hard cases

The concurrent edit records the vault's own answer at queue time and pays from that, capping against
the balance actually on hand (`Trimmy.sol:597-599`), and tolerates the push-claim by making the
`claimWithdraw` call optional (`Trimmy.sol:594-595`):

```solidity
try IQueuedVault(v.target).claimWithdraw(r.claimPeriod) returns (uint256) {} catch {}
uint256 owed = r.pendingAssets;
uint256 held = asset.balanceOf(address(this));
uint256 assets = owed < held ? owed : held;
```

All four HEAD tests pass `[Measured]`:

| Test | Result |
|---|---|
| `test_M2_head_firstClaimerCannotOverTake` | mallory paid exactly 1; alice then paid exactly 100000000 |
| `test_M2_head_sameUserTwoRulesBothSettle` | both rules settle, neither wedged |
| `test_M2_head_publicPushClaimStillPaysTheUser` | user paid 100000000 after a hostile push |
| `test_M2_head_pushClaimPlusSharedBucketStillSettlesBothExactly` | two accounts, one bucket, hostile push: each paid exactly its own |

I tried to break the cap and could not. `pendingAssets` is the return value of the same `redeem`
call that credits the bucket, so a rule cannot record an entitlement it did not fund; and because
the payout is `min(owed, held)`, a rule can never draw more than its own recorded entitlement even
when another rule's assets are sitting in the contract. `[Inference]` — this is reasoning over the
code plus the four passing scenarios, not an exhaustive proof.

**The fix is only in the working tree. `0xeaF2eA39…` is still the vulnerable build.**

---

## 6. Collateral observations

- **`test/VerifyM2.t.sol` and `test/RefuteM2.t.sol` are now stale and red** (4 failing tests). Both
  were written against pre-fix Trimmy and assert that theft occurs; HEAD correctly prevents it, so
  they fail. `RefuteM2.t.sol` is also misnamed — its tests were written to *confirm* the finding.
  They should be retired in favour of `M2Verify.t.sol`, which covers both builds. I did not delete
  them because another agent appears to be editing this tree concurrently.
- **`test/VerifyM3Independent.t.sol` is likewise stale** — 2 tests now fail with
  `RedemptionAlreadyPending`, which is the new guard at `Trimmy.sol:545` doing its job.
- **`MyERC4626.setLagDuration` is public and unauthenticated** (vault source L182). Anyone can move
  every future redemption's day-bucket arbitrarily far out. Trimmy reads `lagDuration()` in the same
  transaction as `redeem`, so its recorded `claimPeriod` stays *consistent* and no funds are
  misdirected — but claim timing is fully attacker-controlled. Vault-side, testnet demo contract;
  recorded for completeness, not actioned.
- The whole-file suite currently has 62 failing tests across the oracle and M-3 workstreams. Those
  are other agents' in-flight findings and stale post-M-1 repros, not regressions from this work.
  `test/M2Verify.t.sol` is 11/11 green.

---

## 7. Recommendation

1. **Do not enable `EXIT_VAULT` on any deployment of `0xeaF2eA39…`.** Treat the current contract as
   having a non-functional exit verb.
2. **Redeploy with the HEAD fix before allowlisting the share token**, which is the change that would
   otherwise turn this from latent to critical.
3. Add the missing `EXIT_VAULT` sell-token assertion in `_validate` — require the sell token to be
   the venue's share token — so the FXRP-stranding shape cannot be armed at all.
4. Keep the `try/catch` around `claimWithdraw`. The public push-claim is not hypothetical; it is the
   cheapest attack in this document.
