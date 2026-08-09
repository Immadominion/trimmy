# 04 — Attack: authorization and the immutable allowlists

Adversarial pass over the authorization surface of Trimmy. Six questions were set; all six are
answered below, three with a clean refutation and three with a confirmed finding.

**Executable record: `contracts/test/AttackAuth3.t.sol` — 18 tests, all passing.**
Every claim tagged `[Verified]` in this document is backed by a named test in that file or by a
command reproduced inline. Nothing here is asserted from reading alone unless it is tagged
`[Inference]`.

```
forge test --match-path test/AttackAuth3.t.sol
Ran 4 test suites: 18 tests passed, 0 failed, 0 skipped
```

---

## 0. The thing you must know before reading anything else

**The working tree is not what is deployed.** `[Measured] 2026-08-07`

`src/Trimmy.sol` (md5 `af795425e87fc14bb7ccc4994c148a53`) carries a 25-field `Rule` with a new
`pendingAssets` slot (`Trimmy.sol:114`) and a rewritten `claim()` (`:574-609`) that fixes M-2 and
M-3. The contract at `0xeaF2eA3924D5337B2Dd22ae7BFCACEdAc3D913D5` does not have it:

```bash
R=https://coston2-api.flare.network/ext/C/rpc
T=0xeaF2eA3924D5337B2Dd22ae7BFCACEdAc3D913D5
cast rpc eth_call '{"to":"'$T'","data":"0x63a6fef6'"$(printf '%064x' 0)"'"}' latest --rpc-url $R \
  | tr -d '"' | wc -c
# 1539  ->  1536 hex chars  ->  768 bytes  ->  24 words, not 25
```

A 25-field decode fails outright:

```bash
cast call $T "ruleAt(uint256)((address,uint32,uint8,uint8,uint8,uint8,uint8,bool,uint128,uint128,\
uint128,uint128,uint128,uint128,uint64,uint64,uint64,uint64,uint128,uint128,uint128,uint128,\
uint128,uint16,uint16))" 0 --rpc-url $R
# ABI decoding failed: buffer overrun while deserializing
```

So: **AUTH-5 and AUTH-6 below are findings against the tree. AUTH-3, AUTH-4, AUTH-7 and the M-2 /
M-3 defects documented in `03-attack-money.md` are all still live on chain.** Any sentence in this
repository of the form "the deployed contract does X" that was written from the tree after the M-2
/ M-3 edits is now wrong. This is exactly the failure mode `AGENTS.md`'s verification standard
exists to prevent, and it has recurred.

---

## 1. Immutability of `_tokens` and `_venues` — PROVEN, at three levels

### Source level `[Verified]`

Every reference to either array, exhaustively:

```
161:    TokenCfg[] private _tokens;          <- declaration
162:    VenueCfg[] private _venues;          <- declaration
244:            _tokens.push(tokens_[i]);    <- WRITE  (inside constructor)
247:            _venues.push(venues_[i]);    <- WRITE  (inside constructor)
259, 263, 271-272, 276-277, 335-337, 359, 368, 400-401, 454-458, 481, 525, 547, 582   <- all reads
```

Two writes, both inside `constructor` (`Trimmy.sol:229-253`). Both arrays are `private`, so no
child contract can reach them either — and nothing inherits from `Trimmy` anyway.

There is no `owner`, no `admin`, no `pause`, no `rescue`, no `upgradeTo`, no initializer, and no
`assembly` block in `src/`:

```bash
grep -rn "delegatecall\|selfdestruct\|assembly\|create2\|onlyOwner\|Ownable" contracts/src/
# (no matches)
```

The only mutable storage in the whole contract is `_rules`, `epochOf` and `guardianOf`
(`Trimmy.sol:168-171`).

### Bytecode level, on the deployed contract `[Measured] 2026-08-07`

A PUSH-data-aware opcode walk over the 17,220-byte runtime of
`0xeaF2eA3924D5337B2Dd22ae7BFCACEdAc3D913D5`:

| opcode | count |
|---|---:|
| `DELEGATECALL` (0xf4) | **0** |
| `CALLCODE` (0xf2) | **0** |
| `SELFDESTRUCT` (0xff) | **0** |
| `CREATE` (0xf0) / `CREATE2` (0xf5) | **0** |
| `STATICCALL` | 15 |
| `CALL` | 12 |

Zero `DELEGATECALL` closes the library / proxy vector by construction: there is no code path that
can execute foreign code in Trimmy's storage context. Zero `SELFDESTRUCT` closes redeployment at
the same address. Zero `CREATE*` closes the "constructor re-entry" question in the brief — Trimmy
never deploys anything, and its own constructor cannot be re-entered because constructor code is
not part of the runtime object.

### Dispatch-table level `[Measured]`

Every `PUSH4` constant in the runtime, resolved:

```
0x06433b1b REGISTRY()              0x0362fe3a MAX_SLIPPAGE_BIPS()     0x15b78a17 MAX_PROTOCOL_FEE_BIPS()
0x437d6171 MIN_SCHEDULE_INTERVAL() 0xdc10da40 MAX_RULE_LIFETIME()     0x69e7c3d7 maxFeedAge()
0x64df049e protocolFeeRecipient()  0x582805d9 epochOf(address)        0xacd52e8d guardianOf(address)
0x9f181b5e tokenCount()            0x8d640d4b venueCount()            0xf6bcf633 ruleCount()
0xbc13f2a4 tokenAt(uint8)          0x5ad2dfd6 venueAt(uint8)          0x63a6fef6 ruleAt(uint256)
0x25e89883 ftsoV2()                0xfe0d94c1 execute(uint256)        0x379607f5 claim(uint256)
0x8a0dac4a setGuardian(address)    0x40e58ee5 cancel(uint256)          0x18cb2b18 cancelAll()
0xcc0c55f4 arm((uint8,uint8,uint8,uint8,uint8,uint128,uint128,uint128,uint128,uint64,uint16,uint16,uint128,uint128))
```

plus three non-selectors: `0x4e487b71` (`Panic(uint256)`), `0x01e13380` (= 31,536,000 =
`MAX_RULE_LIFETIME`), and the masks `0xffff0000` / `0xffffffff`.

**22 selectors, 22 declared public functions, no residue.** There is no undeclared entry point in
the deployed bytecode. `arm()` is `0xcc0c55f4`, matching the fixed build.

The live allowlist, read from the deployed contract:

```
tokenAt(0) = (0x0b6A3645c240605887a5532109323A3E12273dc7, 0x015852502f5553440000…, 6)   FXRP, XRP/USD
tokenAt(1) = (0xC67DCE33D7A8efA5FfEB961899C73fe01bCe9273, 0x01464c522f5553440000…, 18)  WC2FLR, FLR/USD
venueAt(0) = (0xe2B3aE21461c4ad3415210630EA210e9F53CCEBc, SWAP_ROUTER_V3, 3000)
venueAt(1) = (0x9E63a5D282F2fBb7DcE822B98e363b2719D28319, QUEUED_VAULT, 0)
tokenAt(2) -> reverts UnknownToken(2)  (0x7ab99bd2…0002)
```

### Behavioural level `[Verified]`

`testFuzz_AUTH1_arbitraryCalldataNeverMutatesTheAllowlist` — 10,000 runs of a raw
`address(trimmy).call{value: v}(abi.encodePacked(sel, payload))` from a fuzzed `caller`, with a
fuzzed 4-byte selector and fuzzed calldata tail, asserting that
`keccak(tokenCount, venueCount, tokenAt(0), tokenAt(1), venueAt(0), venueAt(1))` is unchanged after
every one. It is. `test_AUTH1b` additionally reads storage slots 0 and 1 (the two array length
words) directly with `vm.load` and shows they stay at 2 across every entry point.

**Verdict: REFUTED as an attack. The allowlists are write-once, and this is the strongest-supported
claim in the whole codebase.**

---

## 2. A hostile CONTRACT arming a rule, and whether `nonReentrant` is enough — REFUTED

`arm()` binds `account: msg.sender` (`Trimmy.sol:303`) with no code-size check, so a contract can
arm. Trimmy then calls back into `rule.account` at two sites:

- `Trimmy.sol:422` — `sellToken.safeTransferFrom(r.account, address(this), amount)` (sender-side hook)
- `Trimmy.sol:634` — `proceedsToken.safeTransfer(r.account, toUser)` (receiver-side hook)

and into `msg.sender` at a third, which the brief did not list and which is the one that actually
matters:

- `Trimmy.sol:723` — `msg.sender.call{value: bal}("")` inside `_refund`, a raw call with all
  remaining gas, reached at the end of every `execute`.

`contracts/test/AttackAuth3.t.sol` builds an ERC-777-style `HookERC20` that calls
`IHookReceiver(to).tokensReceived(...)` on every inbound transfer, a `HostileAccount` that is the
`rule.account`, and a `HostileKeeper` that re-enters from the `_refund` callback.

`[Verified] test_AUTH2_hostileAccountCannotReenterExecuteOrClaim` — from inside `_settle`, all
three of `execute(ownRule)`, `execute(strangersRule)` and `claim(id)` revert with
`ReentrancyGuardReentrantCall()` (`0x3ee5aeb5`). OZ's `ReentrancyGuardTransient` uses **one**
transient slot for the whole contract, so `execute` and `claim` being separate entry points does
not create a cross-function gap — the brief's specific worry is unfounded.

`[Verified] test_AUTH2c_keeperCannotReenterFromTheRefundCallback` — the `_refund` raw call is the
most dangerous-looking callback in the contract (unbounded gas, attacker-controlled target) and it
is likewise inside the guard.

`arm()`, `cancel()`, `cancelAll()` and `setGuardian()` are **not** `nonReentrant` and are reachable
from the hook. `[Verified] test_AUTH2b_reentrantArmAndCancelAllCannotCorruptTheLiveRule` proves
this is harmless:

- Re-entering `arm()` pushes onto `_rules` while the outer frame holds a `Rule storage` pointer into
  that same array. Solidity places dynamic-array elements at `keccak(slot) + i*size`, so growth does
  not relocate element `i`; the test asserts `spent`, `account` and `nextEligibleAt` are all still
  correct on the outer rule after `_advance` writes through the held pointer.
- Re-entering `cancelAll()` bumps the **attacker's own** epoch and kills the attacker's own rules.
  A bystander's rule armed in the same suite is untouched and executes normally afterwards.

**Verdict: REFUTED. `nonReentrant` on `execute` and `claim` is sufficient.** Note also that neither
FXRP nor WC2FLR has a transfer hook today, so the hostile-token half of this is hypothetical — but
the refutation above does not depend on that, which is the point of testing it with a hooking mock.

---

## 3. Guardians

`guardianOf` is written at exactly one site (`Trimmy.sol:666`, `guardianOf[msg.sender] = guardian`)
and read at exactly one site (`Trimmy.sol:673`, inside `cancel`). That is the entire surface.

- **Can anyone set another account's guardian?** No. `[Verified]
  testFuzz_AUTH3_nobodyCanSetAnotherAccountsGuardian`, 10,000 runs over `(who, guardian)`.
- **Can a guardian cancel rules it should not?** No. `cancel` matches on `guardianOf[r.account]`, so
  a guardian's reach is exactly the accounts that named it. `[Verified] test_AUTH3b`, fourth leg.
- **Can a guardian gain more than cancellation?** No. `[Verified] test_AUTH3b` — arming "for" the
  protected account binds the rule to the guardian instead (`arm` always uses `msg.sender`), so the
  guardian cannot create a rule that pulls the account's allowance; and there is no path by which a
  guardian receives proceeds.

Two things the guardian mechanism gets wrong, neither of which is a privilege escalation:

### AUTH-3 [MEDIUM] — the guardian's panic button is wired to the wrong account

`cancelAll()` (`Trimmy.sol:682-686`) never reads `guardianOf`. A guardian pressing it bumps
`epochOf[guardian]` and leaves the protected account's rules completely live.

`[Verified] test_AUTH3c_guardianPanicButtonBumpsTheWrongEpoch` — after the guardian calls
`cancelAll()`, `epochOf(guardian) == 1`, `epochOf(alice) == 0`, and the rule the guardian meant to
kill executes on the very next call. This reproduces `02-ARCHITECTURE-ATTACK.md:377` ("`cancelAll`
authorises `account` or `guardians[account]`") as an unimplemented design intent, and it is the same
defect the earlier `test_A1_guardianCancelAllBumpsTheWrongEpoch` recorded. **It is still present in
both the tree and the deployment.** A guardian holding N rules must cancel them one at a time and
will be front-run on the last one.

### AUTH-8 [INFORMATIONAL] — cancellation is one-way, and does not revoke the allowance

There is no `uncancel`. A compromised or merely mistaken guardian permanently bricks every rule it
touches, and recovery costs the user a fresh XRPL arming payment (`arming/bin/arm.dart`) — an
irreversible on-ledger transaction. Conversely, neither `cancel` nor `cancelAll` revokes the ERC-20
allowance on the personal account; the panic button stops Trimmy from *using* it but leaves it
standing, so "I cancelled everything" is not the same as "I am no longer exposed". Both are design
consequences rather than bugs, but neither is stated anywhere the user will read it.

---

## 4. Epochs

`epochOf` is written at exactly one site (`Trimmy.sol:683-684`) and read at two
(`Trimmy.sol:304` in `arm`, `Trimmy.sol:697` in `_load`).

- **Can an attacker bump someone else's epoch?** No. `[Verified]
  testFuzz_AUTH4_nobodyCanBumpAnotherAccountsEpoch`, 10,000 runs.
- **Can a rule be killed by a `cancelAll` that should not have killed it?** No — `arm` stamps
  `epochOf[msg.sender]` at arm time, so only the account's own subsequent bump can invalidate it.
- **Can a rule survive a `cancelAll` that should have killed it?** **Yes, on the `claim` path.**

### AUTH-4 [MEDIUM] — `claim()` bypasses `_load` entirely

`claim()` (`Trimmy.sol:574-609`) checks `ruleId` bounds, `verb == EXIT_VAULT`, `pendingShares != 0`
and `claimableAt`. It checks **none** of `r.active`, `r.expiry`, `r.epoch`. `_load` is not called.

`[Verified] test_AUTH4c_panicButtonDoesNotStopAClaimAndStillPaysAStrangerAFee` — Alice arms an
`EXIT_VAULT` rule with `keeperFeeFlat = 1 FXRP` and `protocolFeeBips = 50`, one part executes and
queues, then she calls **both** `cancel(id)` and `cancelAll()`. After the day boundary an unrelated
address calls `claim(id)`; it succeeds, the stranger is paid the keeper fee, and
`protocolFeeRecipient` is paid the protocol fee, out of a rule the owner cancelled twice.

Paying out the queued assets after cancellation is defensible — the shares are already burned and
the user is owed the money. **Charging a keeper fee and a protocol fee on a cancelled rule is not.**
A user who hits the panic button because their account is compromised has no way to stop value
leaving, and the amount is bounded only by `keeperFeeBudget`.

This is the contract-side half of `03-attack-offchain.md`'s OFF-9, which described the same gap from
the keeper's side (the keeper's epoch guard makes it *skip* those claims, so the user's assets sit
in the vault queue while anyone else can take the fee for freeing them).

**Fix:** on the `claim` path, if `r.epoch != epochOf[r.account]` or `!r.active`, set
`keeperFee = 0` and `protocolFee = 0` and pay the whole balance to `r.account`.

---

## 5. What a leaked keeper key confers — the claim survives, with one correction

Every occurrence of `msg.sender` and `msg.value` in `Trimmy.sol`, and what each grants:

| line | site | what it confers |
|---|---|---|
| `303` | `arm`: `account: msg.sender` | binds the new rule to the caller. A keeper arming a rule arms it **against itself**, and its own allowance to Trimmy is zero. |
| `304` | `arm`: `epoch: epochOf[msg.sender]` | stamps the caller's own epoch. |
| `331` | `Armed` event | none. |
| `608` | `Claimed` event | none. |
| `630` | `_settle`: `safeTransfer(msg.sender, keeperFee)` | the keeper fee, capped by `keeperFeeFlat`, `keeperFeeBudget - keeperFeePaid` and `proceeds`. Available to **anyone** who calls `execute`/`claim`. |
| `636` | `Executed` event | none. |
| `666` | `setGuardian`: `guardianOf[msg.sender]` | sets the caller's **own** guardian only. |
| `673` | `cancel` auth check | cancels only rules the caller owns or guards. |
| `683-685` | `cancelAll`: `epochOf[msg.sender]` | bumps the caller's **own** epoch only. |
| `708` | `_readFeeds`: `msg.value < fee` | pays the FTSO fee; `calculateFeeById` returns 0 today. |
| `723` | `_refund`: `msg.sender.call{value: address(this).balance}` | **sweeps the contract's entire native balance.** See AUTH-7. |

`[Verified] test_AUTH5_leakedKeeperKeyGrantsNothingThePublicLacks` — the leaked key can execute (so
can anyone, and the proceeds still go to `r.account`); arming with it produces a rule bound to the
leaked key that reverts on `transferFrom` forever; and it cannot cancel Alice's rule
(`NotAuthorised`), set her guardian, or bump her epoch.

**Verdict: the claim holds — with a correction to the contract's own NatSpec.** `Trimmy.sol:388`
says "`msg.sender` appears exactly once in this function, as the keeper-fee recipient. That is the
entirety of what a keeper is trusted with." That is false as written: `execute` reaches `msg.sender`
three times (`630`, `708`, `723`), and the third one is a balance sweep. The *conclusion* is still
right, because the sweep is available to the public too — but a comment that miscounts its own code
is exactly the kind of thing a reader takes on trust.

---

## 6. Value stuck in the contract

### AUTH-7 [MEDIUM] — one caller takes the FLR another caller sent

`receive() external payable {}` (`Trimmy.sol:732`) accepts native from anyone. `_refund()`
(`Trimmy.sol:720-726`) sends `address(this).balance`, not `msg.value - fee`.

`[Verified] test_AUTH6_oneCallerTakesTheFlrAnotherCallerSent` — a donor sends 5 FLR; an unrelated
address then calls `execute` with `msg.value == 0` and walks away with all 5.

This is M-5 from `03-attack-money.md`, unchanged and still deployed. It is restated here because
question 6 asks it directly and because the authorization framing is sharper: there is **no rescue
function anywhere in the contract**, so `_refund` is the only exit for native value, and it always
routes to the wrong person. Anyone who pre-funds Trimmy expecting it to cover future FTSO fees loses
the money and gains nothing — `_readFeeds` gates on `msg.value`, never on balance, so a pre-funded
balance cannot pay a fee even in principle.

**Fix:** thread `msg.value - fee` out of `_readFeeds` and refund exactly that.

### AUTH-5 [MEDIUM, TREE ONLY] — the new `claim()` pays one rule out of another rule's assets

This is a **new** finding against the in-flight M-2/M-3 fix, not against the deployment.

```solidity
// Trimmy.sol:594-599
try IQueuedVault(v.target).claimWithdraw(r.claimPeriod) returns (uint256) {}
catch {}

uint256 owed  = r.pendingAssets;
uint256 held  = asset.balanceOf(address(this));
uint256 assets = owed < held ? owed : held;
```

Two problems compound:

1. **`held` is the contract's whole balance of the asset**, which is every other rule's money.
   `min(owed, held)` bounds a rule's payout by its own entitlement *from above*, but nothing bounds
   it by what **this** claim actually collected. A rule whose vault bucket under-delivers is topped
   up out of the ambient balance.
2. **Every revert from `claimWithdraw` is swallowed.** The comment justifies this by the vault's
   public push path — a third party may already have delivered the bucket. But `catch {}` cannot
   tell "already delivered" from "reverted", "wrong period", or "ran out of gas in the sub-call".
   A claim can now settle in full while the vault call fails outright.

`[Verified] test_AUTH7_claimTopsUpOneRuleOutOfAnothersDeliveredAssets` — Alice and Bob each queue
1,000 FXRP into the same day-bucket. The vault delivers 10% less than it recorded at `redeem` time
(a withdrawal fee; `TESTearnXRP.withdrawalFee` reads 0 today per GROUND-TRUTH §4a-bis, but it is a
live parameter and nothing in Trimmy depends on it staying 0). Alice claims first: `claimWithdraw`
drains the pooled bucket, delivering 1,800; `held == 1800`, `owed == 1000`, so **Alice is paid in
full and the entire 200 shortfall is displaced onto Bob**, who receives 800. Under a correct
accounting each would absorb 100.

`[Verified] test_AUTH7b_claimSettlesEvenWhenTheVaultCallReverts` — with `claimWithdraw` reverting
unconditionally and 1,000 FXRP of ambient balance present, `claim()` settles 1,000 to the user and
the vault's bucket is never touched.

**Fix:** measure the delta around the `claimWithdraw` call as the *primary* number, and use
`pendingAssets` only as an upper bound:
`assets = min(pendingAssets, balanceAfter - balanceBefore + alreadyCreditedToThisRule)`. If the
vault's push path really is a concern, track credited-but-unclaimed per rule rather than reading the
shared balance. Do not swallow the revert reason: distinguish "bucket already empty" from every
other failure.

### AUTH-6 [LOW, TREE AND DEPLOYMENT] — `claim()` draws on a budget `_validate` sized for executions only

`_validate` (`Trimmy.sol:376-380`) certifies that `keeperFeeFlat * ceilDiv(total, part) <=
keeperFeeBudget` — the L2 guarantee that "a rule whose fee budget cannot fund its own executions
stops silently partway through … Refuse to arm it". But `claim()` reaches the same `_settle` and
draws the same `keeperFeeFlat` (`Trimmy.sol:621-628`), and an `EXIT_VAULT` rule needs one claim per
execution.

`[Verified] test_AUTH6d_claimDrainsTheBudgetValidateSizedForExecutionsAlone` — a 2-part rule armed
with the exact minimum budget `_validate` demands (2 FXRP) is exhausted after 2 executions **and 2
claims**. A 4-part rule loses keeper incentive halfway through, which is precisely the silent
mid-rule stall L2 exists to prevent.

**Fix:** for `EXIT_VAULT`, require `keeperFeeFlat * 2 * maxExecutions <= keeperFeeBudget`.

### Cross-rule paths that are now clean

`[Verified] test_AUTH6b_pooledBucketNoLongerLetsOneRuleTakeAnothers` — with the tree's
`pendingAssets`, the first claimer of a pooled `(Trimmy, period)` bucket is credited only its own
entitlement and the remainder waits in the contract for the other rule. M-2 is fixed **in the tree**;
the previously-failing `test_B1_oneRuleClaimsAnotherAccountsRedemption` now reports the attacker
receiving 1 FXRP instead of 10,001. It is still live on chain.

`[Verified] test_AUTH6c_secondQueueIsNowRefusedRatherThanOrphaned` — M-3 is fixed in the tree by
refusing a second queue while one is outstanding (`Trimmy.sol:545`). The cost is a liveness coupling
that did not exist before: a multi-part `EXIT_VAULT` rule cannot advance until somebody clears the
previous claim, which is at minimum the next UTC midnight. The test walks the full stalled-then-
released sequence. Worth an explicit note in the rule taxonomy — a "daily drip out of the vault" is
now a **two-day** cycle in the worst case.

### AUTH-9 [LOW] — the constructor validates decimals and nothing else

`Trimmy.sol:229-253` verifies `IERC20Metadata(token).decimals()` against the declared value — good,
and the only assertion made. It does not check `protocolFeeRecipient != address(0)` (a zero value
would make `_settle` revert on `safeTransfer` for every rule with `protocolFeeBips > 0`, bricking
them permanently), does not check `venues_[i].target != address(0)`, and does not check that a
venue's declared `kind` matches its target. Because there is no setter and no rescue, any of these
is a permanent, unrecoverable deployment. **The live values are correct** — `protocolFeeRecipient`
reads `0x38d58d1BEA8FF21fd8397494f17F64A99bcF8E83` and both venues resolve — so there is no live
impact. `[Measured]` This is a note for the next deploy script, not a bug in this one.

---

## Summary

| id | severity | status | where |
|---|---|---|---|
| Allowlist immutability | — | **REFUTED as an attack** (proven at 4 levels) | source + deployed bytecode |
| Reentrancy via `rule.account` / `_refund` | — | **REFUTED** | tree + deployed |
| AUTH-3 guardian panic button bumps the wrong epoch | medium | confirmed, unfixed | `Trimmy.sol:682-686` |
| AUTH-4 `claim()` bypasses `_load`; fees charged after cancellation | medium | confirmed, unfixed | `Trimmy.sol:574-580` |
| AUTH-5 new `claim()` pays out of ambient balance, swallows reverts | medium | **new**, tree only | `Trimmy.sol:594-599` |
| AUTH-6 keeper budget under-sized 2x for `EXIT_VAULT` | low | **new**, tree + deployed | `Trimmy.sol:376-380` |
| AUTH-7 `_refund` sweeps the whole native balance (M-5) | medium | confirmed, unfixed | `Trimmy.sol:720-726` |
| AUTH-8 cancellation is one-way and leaves the allowance | informational | by design, undocumented | `Trimmy.sol:670-686` |
| AUTH-9 constructor validates only decimals | low | no live impact | `Trimmy.sol:229-253` |
| Tree/deployment divergence | process | **must be resolved before any claim about "the deployed contract"** | §0 |

Nothing in this pass found a way to move another account's funds to an attacker-chosen address. The
two cross-user paths that exist (AUTH-5, and M-2 as still deployed) both move value between *users*
via the vault's pooled accounting; the destination is always some `rule.account`, never a caller-
supplied address. `_settle` having no `receiver` parameter (`Trimmy.sol:614-637`) remains the single
most valuable structural decision in the contract.
