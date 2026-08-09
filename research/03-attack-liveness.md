# Attack 03 — Liveness, and the claims

**Written 2026-08-07.** Target: the **deployed** code, not the spec. `Trimmy`
`0xf73a2af06b315adaa1afe2c1a6c1a6933d8a6554` on Coston2 (chainId 114), and the executors that are
supposed to keep it alive: `keeper/bin/keeper.dart`, `arming/bin/arm.dart`,
`tools/execute_arming.py`.

Lens: **stop a rule firing when it should**, and **falsify a claim a judge could check**.

Every claim below is labelled. Three findings ship as tests that **fail against the current code** —
`contracts/test/AttackLiveness.t.sol`:

```
$ forge test --match-path test/AttackLiveness.t.sol
[FAIL: user must receive the assets for every share they burned: 50000000 != 100000000] test_L1_secondQueueOrphansFirstPeriodForever()
[FAIL: L2: a rule must not outlive its own fee budget: 99000000 != 100000000]           test_L2_transferFeeBreaksTheFeeBudgetGuarantee()
[FAIL: jitter is not secret: nextEligibleAt is returned by ruleAt(): 864085 != 0]       test_L3_jitterIsPubliclyReadable()
```

The pre-existing suite is **50 passing tests** — that number in the brief is accurate.
`[Measured — forge test --no-match-path "test/Attack*.t.sol"]`

---

## L-0. The SWAP verb cannot execute on the live deployment, and never will

**This is the top finding.** `[Verified — live chain reads, 2026-08-07]`

Venue 0 is the allowlisted Uniswap V3 SwapRouter with fee tier **3000**:

```
$ cast call 0xf73a…6554 "venueAt(uint8)((address,uint8,uint24))" 0
(0xe2B3aE21461c4ad3415210630EA210e9F53CCEBc, 0, 3000)
$ cast call 0xe2B3aE21…CCEBc "factory()(address)"
0x9788c2f246486884ef1F3Da9782674E9b259Cc63
$ for FEE in 100 500 3000 10000; do cast call 0x9788c2f2…Cc63 \
    "getPool(address,address,uint24)(address)" $FXRP $WC2FLR $FEE; done
0x0000000000000000000000000000000000000000     # 100
0x0000000000000000000000000000000000000000     # 500
0x0000000000000000000000000000000000000000     # 3000
0x0000000000000000000000000000000000000000     # 10000
```

The factory has code (`codesize` 24,535) and answers — it simply has **no FXRP/WC2FLR pool at any
tier**. `getPool(WNAT, testUSDT, …)` is also `address(0)`, so this factory appears to hold no pools
at all.

`_doSwap` (Trimmy.sol:476) builds the path from `abi.encodePacked(sellCfg.token, v.feeTier,
buyCfg.token)` — the fee tier comes from the **immutable** `VenueCfg`, written once in the
constructor (Trimmy.sol:231-233), and *"there is no code path that can change them"* (Trimmy.sol:18-22).

**Failure scenario.** A user arms `SWAP` / `PRICE_BELOW` — the stop-loss, the product's headline.
`arm()` accepts it: `_validate` (Trimmy.sol:337-340) only checks `v.kind == SWAP_ROUTER_V3` and
`sellTokenId != buyTokenId`. It never asks whether a pool exists. `execute()` then reverts inside
`ISwapRouter.exactInput` on every call, for the whole 365-day lifetime of the rule, on every keeper,
forever. The user's allowance sits live and their rule is a no-op. There is no owner, no pause and
no rescue (Trimmy.sol:18).

GROUND-TRUTH §3 already measured "there is no FXRP swap pool on Coston2" and wrote *"That pool is
labelled as ours in the submission"* (docs/GROUND-TRUTH.md:130-132). **The pool was never deployed,
and the contract shipped with a venue pointing at it anyway.** So:

- 2 of 3 verbs work; the third is dead.
- 2 of 3 triggers (`PRICE_BELOW`, `PRICE_ABOVE`) have no working verb to drive *against a swap*.
  They still function on vault verbs with `sellTokenId != buyTokenId`, but that is not the demo.
- **"Trimmy — conditional execution for XRP"** (Trimmy.sol:14) is, on the deployed instance,
  conditional execution for XRP *into one vault*.

**Fix.** Deploy and seed the FXRP/WC2FLR pool at fee tier **3000** on factory `0x9788c2f2…` —
matching the immutable `feeTier` exactly, not any other tier — before the submission. If that is not
possible, say so and redeploy Trimmy with the swap venue removed; a venue that cannot execute is
worse than an absent one because `arm()` accepts rules against it.

---

## L-1. A sliced vault exit permanently orphans its first payout bucket

**PoC: `test_L1_secondQueueOrphansFirstPeriodForever`, FAILS.** `[Verified]`
*(Overlaps `test/AttackMoney.t.sol::test_M3_…`, found independently by the money lens. Recorded here
because the liveness reading is different: the reference keeper is what walks the rule into it.)*

`_doQueueRedeem` (Trimmy.sol:516-537) **overwrites** the bucket pointer on every part:

```solidity
r.pendingShares += shares.toUint128();
r.claimPeriod   = period;      // <-- overwrite, not append
r.claimableAt   = claimableAt;
```

`claim` (Trimmy.sol:543-566) then claims exactly one bucket and zeroes the counter wholesale:

```solidity
IQueuedVault(v.target).claimWithdraw(r.claimPeriod);
r.pendingShares = 0;
```

The vault files each request under `period = dayIndex(now + lagDuration)` and refuses a claim until
`dayIndex(now) > period` — i.e. the next UTC midnight, `B`. So there is a window each day, exactly
`lagDuration` (300 s) wide, in which the period rolls forward while the previous period is *still
not claimable*:

```
t2 ∈ [B − 300, B)   →   dayIndex(t2 + 300) = P+1,  but claim(P) needs t ≥ B
```

`MIN_SCHEDULE_INTERVAL` is 60 s (Trimmy.sol:138). A 60-second `EXIT_VAULT` rule sweeps that 300 s
window every single day. No keeper behaviour avoids it — the claim is not yet legal.

**Failure scenario (the test).** `totalSellAmount = 100e6`, `partSellAmount = 50e6`, interval 60 s.
Part 1 at `B−330` files under `P`. Part 2 at `B−270` files under `P+1` and overwrites `claimPeriod`.
`pendingShares` is now `100e6` — counting both. `claim()` at `B + 3 days` pays **50e6**, sets
`pendingShares = 0`, and every later `claim()` reverts `NothingPending`. The 50e6 in bucket `P` is
still credited to Trimmy in the vault (`pendingWithdrawAssets(trimmy, P) == 50e6`) and **no code
path can ever reach it** — `claim` takes no period argument and there is no rescue function.

The keeper actively drives this: `sweep` tries `claim` first, logs the `NotYetClaimable` revert, then
falls through and calls `execute` anyway (keeper/bin/keeper.dart:242-256 → 265).

**Fix.** `mapping(uint256 ruleId => mapping(uint64 period => uint128 shares))`, and
`claim(uint256 ruleId, uint64 period)`. Or, minimally, refuse a second `_doQueueRedeem` while
`pendingShares != 0` and `claimPeriod != period` — that converts silent loss into a revert.

---

## L-2. The L2 "fee budget funds the rule" guarantee is void under a transfer fee

**PoC: `test_L2_transferFeeBreaksTheFeeBudgetGuarantee`, FAILS.** `[Verified]`

Two mitigations in this contract contradict each other.

**A9** (Trimmy.sol:395-404) charges the *measured balance delta*, because FAssets transfer fees are a
governance switch and Trimmy is not upgradeable:

```solidity
uint256 received = sellToken.balanceOf(address(this)) - balBefore;
r.spent += received.toUint128();
```

**L2** (Trimmy.sol:352-358) refuses to arm a rule whose budget cannot fund its executions, computing
the count from the *requested* sizes:

```solidity
uint256 maxExecutions = _ceilDiv(p.totalSellAmount, p.partSellAmount);
if (uint256(p.keeperFeeFlat) * maxExecutions > p.keeperFeeBudget) revert …;
```

If the sell token charges a fee, `spent` grows slower than `partSellAmount` per call, so the rule
needs **more** executions than `maxExecutions` — but the budget was sized for `maxExecutions` exactly.

**Failure scenario (the test).** `total = 100e6`, `part = 50e6`, `keeperFeeFlat = 1e6`,
`keeperFeeBudget = 2e6` — precisely what `_validate` demands. Governance turns on a 1% transfer fee.
After the two funded executions: `spent = 99,000,000`, `keeperFeePaid = 2e6`, `budgetLeft = 0`, and
`r.active == true` with 1e6 of principal outstanding. Every further execution pays the keeper
**zero** (`_settle`, Trimmy.sol:578-581 clamps `keeperFee` to `budgetLeft`), so no rational keeper
touches it. Worse, `_advance` (Trimmy.sol:597) never sets `active = false` because
`spent >= totalSellAmount` is never true — the rule stays live, with a live allowance, until
`expiry`, up to `MAX_RULE_LIFETIME` = 365 days.

L2's stated purpose was to prevent exactly this: *"a rule whose fee budget cannot fund its own
executions stops silently partway through, with months left to run and a live allowance"*
(Trimmy.sol:352-353). Under the one condition A9 exists for, it does.

**Fix.** Size the budget with headroom (`maxExecutions + 1`, or a bips-based fee), and deactivate on
`remaining < some dust threshold` rather than only on exact exhaustion.

---

## L-3. The `_advance` jitter is not a timing defence — it is public state

**PoC: `test_L3_jitterIsPubliclyReadable`, FAILS.** `[Verified]`

Trimmy.sol:604-612:

```solidity
// A2 mitigation three: jitter, so execution timing is not predictable for an observer
// positioning around the floor. Derived from state an observer cannot cheaply steer
// within the same block.
uint64 jitter = uint64(uint256(keccak256(abi.encode(blockhash(block.number - 1), r.spent, r.account))) % 30);
r.nextEligibleAt = block.timestamp.toUint64() + MIN_SCHEDULE_INTERVAL + jitter;
```

Three problems, in increasing order of how much they matter.

1. **The result is written to public storage and returned by a public view.** The test executes a
   price-triggered rule and reads `trimmy.ruleAt(id).nextEligibleAt` — `864085`, exact, one
   `eth_call`. An "observer positioning around the floor" does not need the preimage; they need one
   RPC call. The stated defence is decorative. `[Verified — PoC]`

2. **All three inputs are public and none is future.** `blockhash(block.number - 1)` is the parent
   hash, fixed before the transaction runs; `r.spent` and `r.account` are storage. A block proposer
   building block `N` knows `blockhash(N-1)` and can therefore *choose* the jitter by choosing
   whether to include the keeper's `execute` in `N` or `N+1` — a 2-way (or k-way) grind over a 30 s
   range. `[Inference — from the code, not exercised on chain; Flare's C-chain has no public mempool
   we could confirm (GROUND-TRUTH O-6 is still open), so the grind may not be reachable in practice.]`

3. **It is a liveness cost, not just a failed defence.** The jitter branch applies to
   `PRICE_BELOW` / `PRICE_ABOVE` — the stop-loss. A sliced price-triggered exit can fire at most once
   per **60–89 seconds**, whatever the market does. A 4-part exit takes 3–4.5 minutes minimum. That
   bound belongs in the copy next to *"one-block conditional execution … 1–3 seconds measured"*
   (GROUND-TRUTH:510-512), which is true only of the **first** part.

**Reorg / blockhash availability** `[Inference — code reading]`: `nextEligibleAt` is derived and
written in the same transaction as the execution it advances, so a reorg that drops the execute drops
the schedule with it — consistent, no stranded state. `blockhash(block.number - 1)` is available on
Flare's Avalanche-derived C-chain and returns zero only at genesis; a zero hash degrades jitter to a
deterministic function of `(spent, account)`, which is no worse than it already is. No liveness bug
here — only the false claim.

**Fix.** Delete the jitter and the comment, or move the unpredictability where it can survive: a
commit-reveal or a keeper-supplied nonce bounded on chain. Do not ship a mitigation whose own output
is a public getter.

---

## L-4. The reference keeper dies on the first transient error, permanently

`[Verified — keeper/bin/keeper.dart:227-283, 331-341]`

```dart
do {
  final r = await keeper.sweep(dryRun ? null : privateKey);
  …
  if (!once) await Future<void>.delayed(Duration(seconds: interval));
} while (!once);
} finally {
  client.close();
}
```

There is a `finally`. There is **no `catch`**, at any level. `sweep` awaits, uncaught:
`ruleCount()`, `ruleAt()`, `epochOf()` (2 `eth_call`s per rule per sweep), `simulate()` — which does
catch — then `prepareTransaction`, `getTransactionCount`, `Process.run('cast')`,
`sendRawTransaction`, `waitForReceipt`, and `send` explicitly `throw StateError` on a mined revert
(keeper.dart:221).

**Failure scenario.** Any one of: an HTTP 429 from the public Coston2 RPC; a socket timeout (we hit
one during this review — `cast call` on `ruleAt(3)` returned *"operation timed out"* against
`coston2-api.flare.network`); a nonce race with a second keeper; the keeper EOA running out of
C2FLR; `cast` not on `PATH`; a rule that reverts *after* passing simulation because the FTSO ticked
between the `eth_call` and inclusion — the exact case GROUND-TRUTH:504-506 says is *"the common
case"* near a threshold. Any of these terminates the process. There is no supervisor, no systemd
unit, no restart loop and no back-off anywhere in the repo. `[Verified — grep]`

The product claim is that *"the rule then executes itself, with no further action from the user"*
(Trimmy.sol:15-16). Combined with L-6 (nobody else runs an executor for this branch), the whole
liveness story rests on a Dart process with no error handling.

**Fix.** `try { await keeper.sweep(...) } catch (e, s) { log; } ` inside the loop, with exponential
back-off, plus a balance precheck and a restart supervisor. Four lines.

---

## L-5. The keeper refuses to claim a vault exit that the *contract* would allow

`[Verified — keeper/bin/keeper.dart:236-256 vs Trimmy.sol:543-549]`

`claim()` deliberately checks neither `active`, nor `epoch`, nor `expiry` — only `verb`,
`pendingShares` and `claimableAt`. That is **correct**, and it is the right call: shares are already
burned by phase one, so the assets must stay reachable after a cancellation. The brief asks whether
that is a hole; it is not — the hole is that the keeper does not honour it.

```dart
if (rule.active && rule.epoch != await epochOf(rule.account)) {
  skipped++;
  _log(i, 'skip', 'stale epoch (cancelAll)');
  continue;                    // <-- before the maybeClaimable branch
}
if (rule.maybeClaimable) { … }
```

**Failure scenario.** A user arms `EXIT_VAULT`. `execute()` burns their shares and queues the payout
for the next UTC midnight. Before midnight the user presses the panic button — `cancelAll()`
(Trimmy.sol:637-641), which bumps `epochOf[account]` and leaves `r.active == true`. From that moment
our keeper `continue`s past the rule forever. The assets sit in the vault credited to Trimmy,
claimable by a single `claim(ruleId)` that nobody will send. The user, by the product's own premise,
*"holds no FLR, runs no EVM wallet"* (GROUND-TRUTH:267) and cannot send it themselves.

Note the same block also means a cancelled-by-`cancel()` rule *is* claimed (because `active` is then
`false`, so the guard short-circuits) — so the behaviour is inconsistent between the two
cancellation paths, which is a strong hint it was unintended rather than a policy.

**Fix.** Move the `maybeClaimable` branch above the epoch guard, and make the guard skip only the
`execute` path.

---

## L-6. Every external dependency, and what happens when it is absent

`[Verified — file:line for each; behaviour on absence is Inference from the code unless marked]`

| # | Dependency | Where | If absent / changed |
|---|---|---|---|
| 1 | **FlareContractRegistry** `0xaD67…6019` | Trimmy.sol:128-129 (hardcoded `constant`) | If `getContractAddressByHash(keccak256(abi.encode("FtsoV2")))` ever returns `address(0)` — a rename, a registry migration — `ftsoV2()` returns zero and `_readFeeds`'s `calculateFeeById` reverts on the extcodesize check. **Every rule, every keeper, permanently bricked.** No cached address, no fallback, no pause, no upgrade. `[Verified today: resolves to 0xC4e9c78EA53db782E28f28Fdf80BaF59336B304d]` |
| 2 | **FTSOv2 feed liveness** | Trimmy.sol:666-672, Quote.sol:52-60 | `maxFeedAge` = 120 s, **immutable**. Any feed outage past 120 s halts every rule until it recovers. Measured p99 is 34 s / max 35 s (GROUND-TRUTH:477), so the margin is ~3.4×. `[Verified — maxFeedAge()==120 on chain]` |
| 3 | **FTSO feed fee** | Trimmy.sol:662-663 | Zero today. Trimmy handles a non-zero fee via `msg.value`. **The keeper cannot.** See L-7. |
| 4 | **SwapRouter `0xe2B3…` + factory `0x9788…`** | Trimmy.sol:481, venue 0 | No pool exists. See **L-0**. |
| 5 | **TESTearnXRP `0x9E63…`** (third party) | venue 1 | `lagDuration()` is read live each execute (Trimmy.sol:524). If the vault pauses deposits, changes `lagDuration`, or is upgraded, `execute`/`claim` revert. Immutable venue: no substitution. Deposit cap headroom is large (7.2k of 25M), so the §4c cap-fill DoS does not apply here. `[Verified — GROUND-TRUTH §4a-bis, re-read]` |
| 6 | **FAssets `MasterAccountController`** | arming/bin/arm.dart:259 — **hardcoded** | See **L-8**. |
| 7 | **FDC verifier** `fdc-verifiers-testnet.flare.network` | plimsoll/tool/gate3/pipeline.py:40 | Arming impossible. Shared API key `00000000-0000-0000-0000-000000000000` (pipeline.py:45). |
| 8 | **FDC DA layer** `ctn2-data-availability.flare.network` | pipeline.py:41 | Proof never retrievable → the paid attestation and the XRPL payment are both lost. |
| 9 | **XRPL testnet** `s.altnet.rippletest.net` | pipeline.py:39 | No arming payments. |
| 10 | **Plimsoll sibling repo** `../../plimsoll/tool/gate3` | tools/execute_arming.py:38-41 | `sys.exit` on import. **A judge who clones only `trimmy/` cannot run the executor at all.** No submodule, no vendored copy, no requirements file. `[Verified — the path exists on this machine only]` |
| 11 | **Foundry `cast` on `PATH`** | keeper.dart:197, pipeline.py | Keeper cannot sign. Declared in no manifest; `Process.run` throws → L-4 kills the daemon. |
| 12 | **Our own FDC executor** | tools/execute_arming.py | See **L-6b** — the single largest liveness dependency in the product. |

### L-6b. "One XRPL payment" requires a second, private channel and a funded EVM operator

`[Verified — arm.dart:10-20 and 318-319; GROUND-TRUTH:291-315; on-chain tx senders]`

The `0xFE` memo carries only `keccak256(abi.encode(userOp))` — 32 bytes of commitment. The user
operation **pre-image itself is delivered off-chain**; `arm.dart` prints it with the instruction
*"deliver to the executor off-chain"* (arm.dart:318-319). GROUND-TRUTH §0 then establishes, by
measurement, that the public executor **ignores the `0xFE` branch entirely** even at a full
`executorFeeUBA` of 100,000.

So the real dependency graph for "one XRPL payment" is:

1. the user's XRPL payment (irreversible, ≥0.2 XRP + 1 drop past the dead zone, §7), **plus**
2. an out-of-band delivery of the pre-image to us, **plus**
3. our operator paying the FDC attestation fee, **plus**
4. our operator paying gas for `executeDirectMintingWithData`.

Confirmed on chain: steps 2 and 3 of the §0 table were both sent
`from 0x38d58d1bea8ff21fd8397494f17f64a99bcf8e83` — our funded EOA, not the user's.
`[Verified — cast tx 0x0a3f05f7…, 0x86d54bd6…]`

If our executor is not running when the payment lands, **the XRP is gone and no rule exists**. That
is precisely the failure `arm.dart:206-221` refuses zero-fee payments to avoid — and the code
correctly refuses that one while the architecture walks into the same outcome by a different route,
with no timeout, no refund path and no user-visible signal.

**What is still safe to say:** *"the user signs one XRPL payment and nothing else."* That is true and
demonstrated. **What is not:** any phrasing implying the payment is self-sufficient, or that the
system is permissionless end to end. Arming is **not** permissionless today; execution is.

**Fix for the submission.** State it: "arming is executed by our FDC executor because the public
executor does not serve the `0xFE` branch — measured, §0. Execution is permissionless and was proven
so by an independent keeper (`0xF0533D37…`)." Both halves are demonstrable and the second is the
strong one.

---

## L-7. A non-zero FTSO fee halts the keeper, and the contract's mitigation is unreachable

`[Verified — Trimmy.sol:662-663 vs keeper.dart:162-175, 191-211]`

The contract does the right thing:

```solidity
uint256 fee = ftso.calculateFeeById(sellFeedId) + ftso.calculateFeeById(buyFeedId);
if (msg.value < fee) revert InsufficientFeeValue(msg.value, fee);
```

`execute` is `payable` precisely so *"the caller can cover an FTSO feed fee if governance ever sets
one"* (Trimmy.sol:370-371). The keeper never sends value:

- `simulate` → `client.ethCall(to:, data:, from:)` — no `value` (keeper.dart:164).
- `send` → `TransactionRequest(from:, to:, data:)` — no `value` (keeper.dart:192-194); `cast mktx` is
  invoked with `--nonce`, `--gas-limit`, target and calldata, **no `--value`** (keeper.dart:197-211).

**Failure scenario.** Governance sets `calculateFeeById` above zero — a documented possibility, which
is why the contract carries the code (Interfaces.sol:17-20). From that block, every `execute` and
every simulation reverts `InsufficientFeeValue`. Every rule stops. The reference keeper has no code
path that can attach value, so recovery requires a keeper code change and redeploy — and, because
`InsufficientFeeValue` is **not** in `_knownErrors` (keeper.dart:177-188), the logs show a truncated
raw hex blob rather than the reason. The keeper's own stated principle — *"a keeper that goes quiet is
indistinguishable from a keeper that is broken"* (keeper.dart:260) — fails for the one governance
event it was designed to survive.

`_knownErrors` is also missing `InsufficientFeeValue`, `ZeroAmount`, `FeedValueZero`, `NoRule`,
`WrongVerb` and `VaultAssetMismatch`.

**Fix.** Query `calculateFeeById` for both legs before sending, attach `--value fee`, and add the
error to the map. Note the contract refunds any excess (Trimmy.sol:675-681), so over-sending is safe.

---

## L-8. `arm.dart` hardcodes the controller — the exact thing GROUND-TRUTH §2 forbids

`[Verified — arming/bin/arm.dart:259, 263-277; GROUND-TRUTH:104-107]`

GROUND-TRUTH §2 is unambiguous, and calls this the fix for *"a permanent silent failure"*:

> **Rule.** Never hardcode a controller. Resolve `AssetManager.getSmartAccountManager()` at runtime,
> and have the arming preflight assert that the personal account it is about to arm is (a) derived
> from that controller and (b) holds a non-zero balance of the sell token. Five lines that prevent a
> permanent silent failure.

`arm.dart` does none of the three:

```dart
const controller = '0x434936d47503353f06750Db1A444DBDC5F0AD37c';   // line 259 — hardcoded
…
// Rule 2: resolve, never hardcode. Assert the controller we are about to arm against is the
// one the AssetManager itself points at …                          // lines 263-265 — the comment
final personalAccount = await _call(client, controller, 'getPersonalAccount(string)', …);
```

The comment describes the check. The code performs no such check: there is no read of
`AssetManagerController`, no `getAssetManagers()`, no `getSmartAccountManager()`, and no
`balanceOf` on the personal account anywhere in the file. The `--amount` is never compared against
what the account will actually hold.

**Failure scenario.** Two `MasterAccountController`s are live on Coston2 with identical 18-function
ABIs (GROUND-TRUTH §2), and *"nothing in the interface reveals which stack you are on."* If the asset
manager is repointed to `0x32F662C6…` — a governance action, not an exotic one — `arm.dart` keeps
deriving a personal account from the stale controller, and every check it *does* run
(`getPersonalAccount`, `getNonce`, the decoder round-trip, the memo length, the commitment match)
still passes. The user sends an irreversible XRPL payment. The batch sets an allowance on an account
that will never receive the minted FXRP. Every `execute` then reverts on `transferFrom`, silently,
forever. This is the failure the doc says the five lines exist to prevent, and the five lines are
not there.

Secondary: `arm.dart` also hardcodes the rule shape — `verb: 1` (DEPOSIT_VAULT), `venueId: 1`,
`trigger: 2` (SCHEDULE), `triggerValue: 60` (arm.dart:281-284). **A user with no EVM wallet cannot
arm a price-triggered rule at all**, because the only tool that builds the payment cannot express
one. Combined with L-0, no XRPL-only user can reach a price trigger by any route.

**Fix.** Add the five lines. They are cheap and the doc already wrote them.

---

## L-9. There is no XRPL-reachable cancel

`[Verified — Trimmy.sol:620-641; arm.dart has no cancel mode]`

`cancel`, `cancelAll` and `setGuardian` all key off `msg.sender` on Flare. A user whose only
credential is an XRPL key can reach them only by sending **another** `0xFE` arming payment through
the same FDC path — which costs another ≥0.2 XRP, needs the pre-image delivered out of band, and
needs our executor to be up (L-6b). `arm.dart` cannot build such a payment: it emits `approve` +
`arm` and nothing else (arm.dart:165-169).

**Failure scenario.** A rule is misbehaving — say a `SWAP` rule against the non-existent pool (L-0)
burning keeper gas on reverts, or a vault that has started losing money. The user wants out. The
"panic button" (`cancelAll`, Trimmy.sol:633) is documented as the safety valve but is unreachable
from the only credential the product's target user holds, and is *most* unreachable exactly when the
executor infrastructure is the thing that has failed.

`setGuardian` is the intended answer, but nothing in `arm.dart` sets one, and no rule on chain has a
guardian: `guardianOf` is unset for all four rules' accounts. `[Verified — arm.dart builds a 2-call
batch]`

**Fix.** Add a `--cancel` mode to `arm.dart` that emits `setGuardian(ourAddress)` in the arming batch
(third call), so a support path exists, and document that the guardian can only cancel, never move
funds (`cancel` sets `active = false` and nothing else — Trimmy.sol:625-631; that is correctly
minimal).

---

## Claims audit

### GROUND-TRUTH §0 and §0a, re-run against the chain 2026-08-07

| Claim | Verdict |
|---|---|
| Step 2 tx `0x0a3f05f7…`, FDC attestation, fee 1000 wei | **Verified.** `status 0x1`; log payload carries `0x3e8` = 1000, `XRPPayment`, `testXRP`, and the XRPL id `e41504d3…59b6e0` matching step 1 |
| Step 3 tx `0x86d54bd6…`, **742,307 gas** | **Verified exactly.** `gasUsed 742307`, to = AssetManager `0xc1ca88b9…`, selector `0xa7556da6` |
| Step 4 tx `0xa74e9fc2…`, "keeper executes the rule" | **Verified, and it is the strongest artefact in the pack.** `from 0xf0533d37f7ed8d1c45a87bb35750da4665bd6d9e` — the independent keeper — `to` Trimmy, calldata `0xfe0d94c1` + `3` |
| `ruleCount()` 3 → **4** | **Verified.** Reads 4 today |
| personal-account FXRP → 8,400,000 | **Verified/consistent.** Reads 7,400,000 today = 8,400,000 − the 1,000,000 spent by step 4 |
| allowance PA → Trimmy → **1,009,400** | **Verified/consistent.** Reads **9,400** today = 1,009,400 − 1,000,000. See the note below |
| PA vault shares → **934,733** | **Verified exactly.** Reads 934,733 |
| Rule 3 `account = 0x07A76b5C…20bf`, `DEPOSIT_VAULT`/`SCHEDULE`, `keeperFeeFlat = 9400` | **Verified** — all three |
| Rule 3 `active = true` | **FALSE today.** `ruleAt(3)` returns `active = false`, `spent = 1000000 = totalSellAmount`. The sentence is in the same section as the step-4 execution that exhausted it, so it is a stale present-tense assertion rather than an error — but a judge re-running the read finds it false. **Add "at the time of the read, before step 4."** |
| `maxFeedAge` deployed = **120** | **Verified** |
| `MAX_SLIPPAGE_BIPS` = 50, 2 tokens, 2 venues, allowlist contents | **Verified** — all match the brief exactly |
| **"O-3 is settled: `execute()` costs 383,451 gas"** | **FALSIFIED.** See below |
| §3 "no FXRP swap pool on Coston2" | **Still true**, and now fatal — see L-0 |
| "50 passing tests" | **Verified** — `50 tests passed, 0 failed` |

#### The one number a judge can falsify with a single `cast receipt`

GROUND-TRUTH:386 states flatly: **"O-3 is settled: `execute()` costs 383,451 gas."**

All three real `execute` transactions say otherwise. `[Measured]`

| tx | rule | gasUsed |
|---|---|---:|
| `0xf682b1ae…` | 0 | **456,908** |
| `0x50ef27fd…` | 2 | **471,126** |
| `0xa74e9fc2…` | 3 | **471,126** |

The quoted figure is **18.6–22.9 % low**. Propagating the real number, the minimum viable
`keeperFeeFlat` is ~**5,772 UBA**, not 4,698 — the deployed 9,400 still covers it, so no rule is
broken, but the headline is wrong.

The gas *price* is also unsupported. The doc computes at **2125 gwei**; the effective gas price of
`0xa74e9fc2…` was **1500 gwei**, and `cast gas-price` returns **650 gwei** right now. Real cost of
that transaction: `471,126 × 1500 gwei = 0.7067 C2FLR = $0.0042`. `[Measured]`

**Fix.** Replace with: *"`execute()` costs 456,908–471,126 gas, measured across three on-chain
executions (DEPOSIT_VAULT path). At the 1500 gwei observed, that is 0.71 C2FLR ≈ $0.0042 ≈ 4,100
UBA; `keeperFeeFlat = 9,400` gives ~2.3× margin. Coston2 gas prices are a testnet artefact — 650 to
2125 gwei observed in one day — and are not Flare mainnet's market."*

### The README-able claims

| Claim | Verdict on the **current code** |
|---|---|
| **"The keeper is trusted with nothing"** | **Nearly true, and demonstrated** — `0xF0533D37…` started at zero, executed rule 3, took exactly `keeperFeeFlat`. But `_refund()` (Trimmy.sol:675-681) sends `address(this).balance` — the **whole** native balance — to `msg.sender`, not the excess of `msg.value`, and `receive() external payable {}` (line 687) accepts anything. Any native FLR that reaches Trimmy belongs to the next keeper. `[Verified — code; also caught independently as `test_M5_refundSweepsWholeNativeBalance`]` **Say "trusted with no user token and no authority" and fix `_refund` to track `msg.value`.** |
| **"One XRPL payment"** | **True of what the user signs; false of what the system needs.** See L-6b: pre-image out of band + our FDC executor + our gas. |
| **"Holds an allowance, never a balance"** | **True across transactions** — every path measures proceeds and forwards the remainder to `r.account` in the same call (`_settle`, Trimmy.sol:571-594). One caveat: L-1's orphaned bucket is a *vault* balance credited to Trimmy that Trimmy can never move. |
| **"`approve` (exact size, never unlimited)"** (GROUND-TRUTH:327) | **"Never unlimited" is true; "exact size" is not.** `arm.dart:303` approves `amount + keeperFee`, but the keeper fee is paid out of *proceeds*, never pulled by allowance. So 1,009,400 was approved for a rule that could only ever pull 1,000,000, and **9,400 of standing allowance survives the rule's death** — verified live: `allowance(PA, Trimmy) == 9400` with rule 3 `active == false`. Change to `allowance: amount`. |
| **`keeperFeeFlat` "≈4,698 UBA"** | **Unit-unsafe as guidance.** The field is *buyToken* units (Trimmy.sol:90, Architecture:175) — vault shares for `DEPOSIT_VAULT`, WC2FLR (18 dp) for an FXRP→WC2FLR swap. A user following the doc's UBA figure on a swap rule arms a fee of 9.4e-15 WC2FLR: economically zero, so no rational keeper executes and the rule never fires. Our keeper would do it anyway — it never checks profitability (keeper.dart:265-279) — which means "a market of keepers" is asserted, not demonstrated. `[Verified — code reading]` |
| **`protocolFeeRecipient`** | `0x38d58d1BEA8FF21fd8397494f17F64A99bcF8E83` — **the same EOA that armed rules 0–2, paid the FDC fee and sent the direct mint.** The "protocol fee sink" is the deployer's hot key. `protocolFeeBips` is 0 on all four rules so nothing has flowed, but a judge reading "no owner, no admin" next to a fee sink that is the deploy key will ask. `[Verified — chain reads]` |

---

## Ranked

| | Finding | Severity | Costs |
|---|---|---|---|
| **L-0** | SWAP verb dead — no pool at the immutable fee tier | **Critical** | The headline verb, both price triggers, the demo |
| **L-1** | Sliced vault exit orphans a payout bucket forever | **Critical** | User funds, unrecoverably |
| **L-6b** | Arming is not permissionless; XRP is lost if our executor is down | **High** | A falsifiable claim + irreversible user loss |
| **L-8** | `arm.dart` hardcodes the controller; no preflight asserts | **High** | Permanent silent failure after an irreversible payment |
| **L-4** | Keeper dies on the first transient error | **High** | All liveness, in one uncaught exception |
| **L-7** | Non-zero FTSO fee halts every rule; keeper can't pay it | **Medium** | Total halt on a governance switch |
| **L-2** | Fee budget guarantee void under a transfer fee | **Medium** | Rules stall with a live allowance for up to a year |
| **L-5** | Keeper won't claim after `cancelAll` | **Medium** | User's exited assets stranded behind a manual call |
| **§0** | `execute()` gas overstated as settled at 383,451 | **Medium** | The one number a judge checks in 30 seconds |
| **L-3** | Jitter is public state; advertised as a timing defence | **Medium** | A claim that falsifies with one `eth_call` |
| **L-9** | No XRPL-reachable cancel | **Low** | The panic button the target user cannot press |

### What is genuinely strong and should be said louder

`0xa74e9fc2…` — an address with no allowance, no balance and no authority found a rule, simulated
it, executed it, took exactly its flat fee, and the proceeds went to `rule.account`. That is
verified, on chain, from an independent identity. It is the best sentence in the pack, and none of
the above touches it.
