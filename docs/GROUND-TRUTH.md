# Ground Truth — Trimmy

Measured facts about the Coston2 chain state Trimmy depends on, each recorded with the command that
produced it. This file belongs to the Trimmy product workspace. The Dart SDK keeps its own ledger at
[`../../sdk/docs/GROUND-TRUTH.md`](../../sdk/docs/GROUND-TRUTH.md) and Plimsoll keeps its own at
[`../../plimsoll/docs/GROUND-TRUTH.md`](../../plimsoll/docs/GROUND-TRUTH.md) — the three are
deliberately separate so each workspace can be worked on independently. Where a Plimsoll measurement
is load-bearing here it is **restated with its own evidence** rather than cited, so this document is
self-supporting to a reviewer who has only `trimmy/`.

Anything not measured this way is labelled `[Inference]`, `[Speculation]` or `[Unverified]` and must
stay labelled downstream. Re-verify before relying on any of it after **2026-10-31**; protocol
parameters are governance-settable and chain state drifts.

RPC used throughout: `https://coston2-api.flare.network/ext/C/rpc` (chain ID 114).
Explorer API: `https://coston2-explorer.flare.network/api`.

---

## 000. The confidential trigger was completely bypassable. Fixed, redeployed, re-verified — 2026-08-09

The worst defect this project has had, found while driving the first real PRIVATE rule end to end.

`requestEvaluation` took the observed price as a **caller-supplied string**, and `acceptVerdict`
never checked that a verdict answered an instruction *this contract* had sent. Together those gave
any stranger a complete bypass of the confidential trigger:

1. call `requestEvaluation(victimRule, "1", nonce)` — a price they invent
2. the enclave compares `1` against the secret threshold, sees it satisfied, signs `fire = true`,
   and the signed result is published on the proxy's **public, unauthenticated** result endpoint
3. `acceptVerdict` accepts it — the commitment is public, the nonce is unused, and the signature
   really is the registered enclave's
4. `Trimmy.execute` fires the victim's rule at a price its owner never chose

The same primitive also defeats the confidentiality claim on its own: each verdict is one bit of
"is the threshold above or below the number I picked", so roughly **twenty queries binary-search
the secret**. The threshold was secret in name only.

Both failures share one root cause — *the number the enclave compared against came from the
attacker rather than from the chain* — and the fix has two halves:

- **The price is no longer a parameter.** `requestEvaluation(ruleId, nonce)` calls
  `Trimmy.currentPrice(ruleId)`, which re-derives the relative price from the same FTSO feeds the
  execution itself would use. A caller still picks *when* to ask, which is public anyway.
- **A verdict must answer our question.** `requestEvaluation` records the instruction id it sent in
  `pendingAction[ruleId][nonce]`, and `acceptVerdict` refuses any verdict whose `actionId` is not
  that exact id. Verified equal on chain: the `ProvisionRequested` event's `instructionId` and the
  id the proxy serves results under are the same value
  (`0xfccf2394…`, tx `0x60fd3b15…`).

Both attacks re-run against the **live, fixed** contract `0x02EA709e…`:

```console
$ cast call $TRIG "acceptVerdict(...)" 0 true $COMMITMENT 7 ... 0xdeadbeef… "threshold" 1 $REAL_SIG
execution reverted: 0xe6cf311f 0000…0000 0000…0007
                    └ NoEvaluationRequested(ruleId = 0, nonce = 7)

$ cast call $TRIG "requestEvaluation(uint256,string,uint64)" 0 "1" 7 --value 0.01ether
execution reverted            # the caller-supplied-price entry point no longer exists
```

The signature in that first call is a **genuine** enclave signature over a genuine `fire` verdict,
lifted from the public endpoint. It is refused because nobody asked the question.

Regressions: [`test/VerdictBinding.t.sol`](../contracts/test/VerdictBinding.t.sol), 8 tests.

### A superseded image silently blackholed half of all instructions

Found in the same session, and the reason the first provision attempt vanished. Extension 66052 had
**two ACTIVE machines** at the same URL with different measurements — a live v0.3.0 enclave and a
v0.2.0 registry entry whose container no longer existed. A TEE generates its identity on boot, so
the old machine's signing key died with it, but nothing retires the registry row. `_send` routes via
`getRandomTeeIds`, so roughly half of all instructions were drawn into the dead machine and lost,
fee paid, no error anywhere.

The registry has the right mechanism and it belongs to the extension owner:

```console
$ cast send $MGR "disableCodeHashPlatforms(uint256,bytes32,bytes32[])" \
    66052 0x95810e43…  "[$(cast --format-bytes32-string GCP_AMD_SEV)]"
status 1                                      # tx 0xcbc190a5…

$ cast call $MGR "getTeeMachineStatus(address)(uint8)" 0xf5430C46…
4                                             # was 2 (ACTIVE) — retiring the measurement retired the machine

$ for i in $(seq 1 10); do cast call $MGR "getRandomTeeIds(uint256,uint256)(address[])" 66052 1; done | sort -u
[0xB33E5CF59e3ce1D58427B9F4E23d0444c128D3D7]  # 10/10 now route to the live enclave
```

`isAuthorisedTee` rejects the retired machine too, since it requires status 2.

**Redeploying the trigger did not require a new extension or a new enclave registration.**
`setExtensionContracts(extensionId, stateVerifier, instructionsSender)` is owner-callable, so
extension 66052 was re-pointed at the fixed contract in one transaction (`0xd1c0f396…`) while the
enclave kept `EXTENSION_ID=66052` and its machine registration untouched.

### The confidential rule then ran end to end, on real hardware

| step | evidence |
| --- | --- |
| arm PRIVATE rule | rule 0 on `0x19F81AAB…`, `trigger = 3`, **`triggerValue = 0`** |
| commit | `commitmentOf(0) = 0xeca87739…` |
| provision (ECIES) | enclave returned `{"ruleId":0,"commitment":"0xeca87739…","stored":true}` — it decrypted the ciphertext and **independently recomputed the same commitment** |
| request verdict | `pendingAction(0,0) = 0xc2cf1bea…`, price read from FTSO, not supplied |
| verdict | `{"ruleId":0,"fire":true,"commitment":"0xeca87739…","nonce":0,"issuedAt":1786297877}` — no threshold, no margin, no bounds |
| accept | tx `0x9a2af814…`, status 1 |
| execute | tx `0x233df51b…`, `spent = 1000000`, keeper paid 9,400, rule closed |

The threshold `1100000` appears nowhere on chain. Only the enclave ever held it.

**PRIVATE execution costs more gas than the plain path**: 517,962 measured, against the 383,451 of
§0/O-3. The first attempt (`0x486c9122…`) ran out of gas *after* emitting `Executed` — every
transfer succeeded and the tail reverted — so `eth_estimateGas` is not a safe limit for this path.
The keeper sends an explicit limit.

### Live addresses after this fix

| contract | address |
| --- | --- |
| `Trimmy` | `0x19F81AAB43f7a26B0659754b70179aDcAF43ef7C` |
| `TrimmyConfidentialTrigger` | `0x02EA709e2278EACDbA00D4A88caA604E3b35293b` |
| FCC extension | `66052` (re-pointed, not re-registered) |
| TEE machine | `0xB33E5CF59e3ce1D58427B9F4E23d0444c128D3D7`, `GCP_AMD_SEV`, codeHash `0xe9ab7410…` |

Superseded, and left on chain deliberately so the history is checkable:
`Trimmy 0x9c7876df…` and `trigger 0x1121702e…` carry the vulnerable `requestEvaluation`. **Do not
arm a PRIVATE rule against them.**

### Both bounties now run on this one deployment — 2026-08-09

The XRPL leg was re-run against the new address so a reviewer does not have to read two
deployments to see the whole product.

| step | evidence |
| --- | --- |
| build the arming payment | memo `FE0000000000000186A0EBBE0E…`, 42 bytes, `executorFeeUBA = 100000` |
| independent decode | `decode.dart` re-derived the same commitment from the pre-image and printed the two calls in English — no network, no trust in the producer |
| XRPL payment | `384FE782BE520662EA579AB67A2232DE5BD650A8A0E2ACB75C2B8C80514B778A`, `tesSUCCESS`, ledger 19771685 |
| FDC attestation | voting round 1420803, proof after 8 polls |
| execute | `executeDirectMintingWithData` — tx `0xd504f3f3…`, 747,096 gas |
| rule armed | rule 1, `account = 0x07a76b5c…` — the **personal account derived from the XRPL address**, not the EVM key that paid gas |
| keeper executes | tx `0xd88f7cac…`, 476,842 gas, by `0xF0533D37…` — an address that is neither the user nor the deployer |
| fee split | keeper vault shares 65,800 → **75,200**, exactly the `keeperFeeFlat` of 9,400 |

The user held no FLR, ran no EVM wallet, and signed one XRPL payment.

---

## 00a. `getPersonalAccount` is a derivation, not a lookup — measured 2026-08-09

Found while building the arming front end, and it changes what a typo costs.

`MasterAccountController.getPersonalAccount(string)` does not look an XRPL address up in a
registry. It **derives** an EVM address from whatever string it is handed, and it never fails:

```console
$ cast call $CONTROLLER "getPersonalAccount(string)(address)" "rDE4JUm2jaue31VwidRXWuWzf5dQkUxcsB"
0x07a76b5c3d03f5bff4cb3e043b1d17a1b40920bf     # the real one

$ ... "rDE4JUm2jaue31VwidRXWuWzf5dQkUxcsA"     # one character changed
0x6085dbe8e9db0aad03410528d46169360f849617

$ ... "rQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQ1"      # not a real address
0xe66bf6b2782fa70c25b3575094af0088f359f5b4

$ ... "not-an-address"                          # not an address at all
0xff16dc7afcc384afef3a78828b61211ce1e32f8f
```

**A mistyped address therefore does not error. It silently resolves to a different Flare account**,
and an arming payment built against it sets an allowance and arms a rule on an account the sender
does not control. The XRPL payment cannot be recalled, so there is no recovery.

Nothing on the Flare side can catch this — the derivation is legitimate for every input. The only
place it is detectable is offline, before sending, using the four-byte base58check checksum the
address already carries. Both builders now verify it before any chain call:

- [`web/lib/xrpl-address.js`](../web/lib/xrpl-address.js) — SubtleCrypto, no dependency
- [`arming/lib/xrpl_address.dart`](../arming/lib/xrpl_address.dart) — `package:crypto` 3.0.7

Each is covered by a test that mutates **every** character of a real address to every other
character in the XRPL alphabet — 1,900+ variants per implementation — and asserts that none is
accepted. `arm.dart` exits **2** on a refusal, checked directly rather than through a pipe.

---

## 1. A keeper can never drive a personal account — measured 2026-08-06

`PersonalAccount.executeUserOp` carries an `onlyController` modifier. This is the single most
load-bearing fact in the architecture: it rules out every design in which Trimmy submits user
operations on the user's behalf, and forces the allowance-pull model.

```bash
R=https://coston2-api.flare.network/ext/C/rpc
PA=0xa52930f85fe71ce586932cfe682e4437a93e66de   # a live personal account
CTRL=0x434936d4...                              # its controller

# From the controller: succeeds (empty return)
curl -s -X POST $R -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":1,
  "method":"eth_call","params":[{"from":"'$CTRL'","to":"'$PA'","data":"0x2b2ee783"},"latest"]}'
# -> {"result":"0x"}

# From any other address: reverts
curl -s -X POST $R -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":1,
  "method":"eth_call","params":[{"from":"0x0000000000000000000000000000000000000001",
  "to":"'$PA'","data":"0x2b2ee783"},"latest"]}'
# -> error data 0x59907813  = OnlyController()
```

The modifier is present in **both** deployed implementations (§2).

> **Trap.** `cast call $PA "executeUserOp((address,uint256,bytes)[])"` computes a *different*
> selector and fails for an unrelated reason, which reads as confirmation if you are not careful.
> Use raw `eth_call` with the literal selector `0x2b2ee783` when a selector matters.

**Consequence.** The only durable authorization a rule can hold is an exact-size **ERC-20 allowance**
granted inside the arming batch. Combined with a permissionless `execute()` that re-derives every
bound on-chain, the maximum extractable value from a leaked keeper key is zero. Every design that
re-arms a rule by submitting a fresh user operation — sliced/TWAP fills, partial-fill auto-slicing,
take-profit ladders as originally specified — must be redesigned around this.

---

## 2. Two live `MasterAccountController`s on Coston2 — measured 2026-08-06

Both have identical 18-function ABIs. Nothing in the interface reveals which stack you are on.

| Controller | Implementation |
| --- | --- |
| `0x32F662C6…` | `0xb3A633e4…` |
| `0x434936d4…` | `0xe900cf0C…` |

XRPL address `rGrWnRJo77ceUaSUUobmB2JMoFq1muHRMu` owns a personal account under **each**:
`0x4B95de8e…` holding 110,108 FXRP, and `0x293730Bd…` holding 100,383 FXRP. `getPersonalAccount(string)`
returns a different address on each controller.

**Arming against the wrong controller sets an allowance on an empty personal account, and every
subsequent execution reverts on `transferFrom` — silently, permanently, unrecoverably.**

### Which is canonical

Resolve it from the asset manager rather than choosing:

```bash
REG=0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019
AMC=$(cast call $REG "getContractAddressByName(string)(address)" "AssetManagerController" --rpc-url $R)
                                          # 0x1C772F700308aF4c13897cc7b9c41EFfB82c50C0
AM=$(cast call $AMC "getAssetManagers()(address[])" --rpc-url $R | tr -d '[]' | cut -d, -f1)
                                          # 0xc1Ca88b937d0b528842F95d5731ffB586f4fbDFA
cast call $AM "getSmartAccountManager()(address)" --rpc-url $R
cast call $AM "fAsset()(address)"           --rpc-url $R
cast call $AM "lotSize()(uint256)"          --rpc-url $R
```

Live output, **re-run 2026-08-06**:

| Call | Result |
| --- | --- |
| `getSmartAccountManager()` | **`0x434936d47503353f06750Db1A444DBDC5F0AD37c`** |
| `fAsset()` | `0x0b6A3645c240605887a5532109323A3E12273dc7` |
| `lotSize()` | `10000000` AMG = **10 FXRP** (6 decimals, AMG↔UBA identity on this deployment) |

**`0x434936d4…D37c` is canonical.** `0x32F662C6…` is not the controller the asset manager routes
through, and a personal account derived from it will never receive minted FXRP on this path.
`[Verified — live read 2026-08-06, independently reproducing the Plimsoll ledger's 2026-08-02
measurement of the same call.]`

The 10 FXRP lot size is itself a UX constraint: a rule cannot act on an amount finer than the lot
when redemption is involved, and a user cannot arm with less than one lot's worth of FXRP.

**Rule.** Never hardcode a controller. Resolve `AssetManager.getSmartAccountManager()` at runtime,
and have the arming preflight assert that the personal account it is about to arm is (a) derived
from that controller and (b) holds a non-zero balance of the sell token. Five lines that prevent a
permanent silent failure.

`[Unverified]` What routes a given XRPL payment to one controller rather than the other — most
likely a differing Core Vault destination address per stack. **Experiment:** compare
`directMintingPaymentAddress` and `getXrplProviderWallets()` across both stacks.

---

## 3. There is no FXRP swap pool on Coston2 — measured 2026-08-06

Every deployed V3 factory was enumerated via the explorer, then probed exhaustively.

```
factories:      0x9788c2f2…  0xB1D5c751…  0x9C3AFDDE…  0x3370ADDC…  0xc77Aa8Af…
counter-tokens: WNAT 0xC67DCE33…  testUSDT 0xf3803ECA…  testUSDT0 0x21709E63…  testUSDC 0x30e2F4EC…
fee tiers:      100 / 500 / 3000 / 10000

5 × 4 × 4 = 80 × getPool(FXRP, tok, fee)  ->  address(0) for all 80
```

Corroborated independently: the top 50 FXRP holders contain no pool contract, and the 50th holds
1,590 FXRP — so no pool holds more than roughly $1,660 of FXRP.

**Consequence.** Every swap-based rule has nothing to execute against on Coston2 until we deploy and
seed a pool ourselves. That pool is labelled as ours in the submission — a judge will find it
otherwise.

### 3a. So we deployed one, and the SWAP verb now runs live — 2026-08-09

**Pool `0xafcA1C5DfF08b3B8Bacb7721fb8189d2D8E7C3DB`** — FXRP/WC2FLR, fee tier 3000, on factory
`0x9788c2f2…`, which is the factory the allowlisted SwapRouter `0xe2B3aE21…` reports. `token0` is
FXRP (6 dp), `token1` is WC2FLR (18 dp). **It is ours, created for this submission**, and it is thin.

Initialised at the FTSO-derived price, with one concentrated position:

```console
XRP/USD = 1.040918 (8 dp feed, 6 shown)   FLR/USD = 0.00609001
=> 1 FXRP = 170.9222 WC2FLR,  sqrtPriceX96 = 1035806996435315820834485758169448448,  tick 327738
position: ticks [327240, 328260]  (~+/-5%),  L = 155,310,565,707,002
seeded  : 0.305637 FXRP + 49.999999996 WC2FLR
```

**The V3 fork renames the mint callback.** The pool called `flareSwapMintCallback` (selector
`0x8930e8c5`), not `uniswapV3MintCallback`, and reverted with "unrecognized function selector"
against the Uniswap name. Trimmy is unaffected — it only ever calls the SwapRouter and never
receives a pool callback — but a copied V3 integration would hit this at runtime, not compile time.

#### A live swap, two refusals, and what the refusals were telling us

| # | rule | sells | outcome |
| --- | --- | --- | --- |
| 1 | 2 | 0.01 FXRP | **executed** — tx `0x7edff76c…`, received 1.702666 WC2FLR, cost **38 bips** |
| 2 | 3 | 0.05 FXRP | **refused** — `Too little received`, no gas spent |
| 3 | 3 | 0.05 FXRP | still refused, after liquidity was raised 2.66x |
| 4 | 3 | 0.05 FXRP | **executed** — tx `0xc0e9dd88…`, received 8.536698 WC2FLR, cost **5.6 bips** |

Rule 2's fair value at the oracle price is `0.01 x 170.9222 = 1.709222 WC2FLR`; it received
1.702666. Predicted beforehand from the pool maths as 38.4 bips against a measured 38, so the model
and the chain agree. The pool tick moved 327738 → 327721 and its FXRP balance rose 305,637 →
315,637, exactly the 10,000 sold.

**Row 3 is the interesting one, and the first estimate of it was wrong.** Liquidity was raised from
`1.553e14` to `4.126e14` — a 2.66x deepening that an `impact/2 + fee` approximation said was ample —
and the rule was refused anyway. Computing the floor exactly instead of approximating it showed why:

```console
oracle : 171.2618 WC2FLR/FXRP
pool   : 170.6357   ->  pool is -36.6 bips vs oracle
```

The pool had drifted **36.6 bips below the oracle**: rule 2's own swap pushed it down ~17 bips, and
FTSO's XRP/FLR rose ~20 bips in the meantime. With the 30-bip pool fee on top, *no* trade size fit
inside 50 bips — the 0.01 FXRP sell that had succeeded earlier would have been refused too. Depth
was never the binding constraint. **Staleness was.**

On a real market that drift is arbitraged away continuously and for free. **A testnet pool has no
arbitrageurs**, so it decays away from the oracle and stays there. Re-centring it by hand
(`0x38b77fff…`, buying 13.97 WC2FLR worth of FXRP) restored the peg, and the identical rule then
filled at an effective **170.734 against an oracle of 170.83 — 5.6 bips**.

Two things this pins down:

- **The floor is doing exactly what it exists for.** Trimmy refused to sell into a stale pool three
  times; the one time the pool was honestly priced it filled at 5.6 bips. A thin or stale venue
  produces a *refusal*, never a bad fill.
- **The keeper signed none of the three refusals.** Each died in its `eth_call` pre-simulation, so a
  rule that cannot execute costs an RPC round trip rather than gas.

Consequence for anyone reproducing this: **re-centre the pool against FTSO before demonstrating a
swap**, or expect a correct refusal. That is a property of an unarbitraged testnet pool, not of the
contract.

Seeder harness: [`script/SeedPool.s.sol`](../contracts/script/SeedPool.s.sol). It is a harness, not
product code — Trimmy never provides liquidity and never holds an LP position.

---

## 4. The yield venues are live but **have no synchronous exit** — measured 2026-08-06

All three are ERC-4626 over FXRP. FXRP token `0x0b6A3645c240605887a5532109323A3E12273dc7`, total
supply **4,134,532.70**, 6 decimals.

| Vault | Address | `totalAssets` | Share price | `maxWithdraw` |
| --- | --- | ---: | ---: | ---: |
| stXRP / FirelightVault | `0xC90D6847…` | 100,748.43 FXRP | **1.000000** | **0** |
| TESTearnXRP | `0x9E63a5D2…` | 7,216.57 FXRP | **1.05917** | **0** |
| MyERC4626 | `0xF97B2bBd…` | 6,209.45 FXRP | 1.00110 | **0** |

```bash
for V in 0xC90D6847... 0x9E63a5D2... 0xF97B2bBd...; do
  cast call $V "totalAssets()(uint256)"  --rpc-url $R
  cast call $V "totalSupply()(uint256)"  --rpc-url $R
  cast call $V "maxWithdraw(address)(uint256)" 0x000000000000000000000000000000000000dEaD --rpc-url $R
  cast call $V "maxRedeem(address)(uint256)"   0x000000000000000000000000000000000000dEaD --rpc-url $R
done
```

### Three findings that change the design

**4a — `maxWithdraw` and `maxRedeem` are `0` on all three.** Not a stXRP quirk; universal. All three
are **request/claim queues**. **No vault-exit rule can execute synchronously.** That kills drip
payout, the dead-man switch, and any rule that sells a yield position — unless the rule is
two-phase. And the obvious workaround (request now, claim later) needs re-arming, which §1 forbids.

> **Required design.** One rule, **two permissionless entry points**: `execute()` requests the
> redemption and writes `claimableAt`; a separate `claim(ruleId)` completes it. Nobody had
> specified this.

### 4a-bis — the redemption mechanics, read from source and confirmed live 2026-08-07

`TESTearnXRP` `0x9E63a5D282F2fBb7DcE822B98e363b2719D28319` and `MyERC4626`
`0xF97B2bBdB2f4a561806e5038a503eCA81554634E` are **the same Upshift-style contract**. stXRP
`0xC90D6847747b85d1fa2E07859869fb9fB72c0361` is a TransparentUpgradeableProxy over
`0x9892419e190a63ff46e9DA7da387EeAD8d4a7213`. Four findings, each of which would have cost a day:

**(1) The "300-second lag" is a red herring. The real wait is up to ~24 hours.** `lagDuration` reads
**300** live, and because `lagDuration < PERIOD_DURATION (1 days)` the *returned* `_claimableEpoch`
is indeed `block.timestamp + 300`. But that value is **not** what gates the claim. `claimWithdraw`
gates on the **period**:

```solidity
require(_period < _getPeriodFromDate(year, month, day), InvalidPeriod());  // not current or future
// and  _getPeriodFromDate == timestampFromDateTime(y,m,d,0,0,0) / PERIOD_DURATION  == day index
```

`_withdraw` files the request under `period = dayIndex(block.timestamp + lagDuration)`, and the claim
requires the current day index to be **strictly greater**. So:

```
claimableAt = (dayIndex(block.timestamp + lagDuration) + 1) * 86400
```

Minimum wait is therefore the **next UTC midnight**, up to ~24 h — and slightly worse if the request
lands within `lagDuration` of midnight, which pushes it a further day. `[Verified — source +
`getWithdrawalEpoch()` returning `(2026, 8, 7, 1786060800)`, and `1786060800 / 86400 = 20672`]`

**Correction:** earlier notes describing this as a "300 s redemption lag" were wrong, and any demo
or submission copy saying so must be fixed. A drip payout settles **next day**, not in five minutes.

**(2) `requestRedeem` requires you to approve the vault against yourself.** Its body is
`this.redeem(_shares, _receiver, msg.sender)` — an **external self-call**, so inside `_withdraw`,
`_caller == address(vault)` while `_owner` is the original caller. Since `_caller != _owner` it runs
`_spendAllowance(_owner, _caller, _shares)`. Calling `requestRedeem` without first approving the
**vault itself** therefore reverts.

> **Use `redeem(shares, receiver, owner)` directly instead**, with `owner == address(this)`. Then
> `_caller == _owner`, no allowance is spent, and `_withdraw` still queues. Trimmy computes the
> period itself rather than relying on `requestRedeem`'s return value.

**(3) `requestRedeem`'s first return value is NOT the argument `claimWithdraw` expects.** It returns
`_claimableEpoch` (a timestamp); `claimWithdraw` takes a **day-index period**. Passing one where the
other is wanted reverts `InvalidPeriod()` — or, worse, silently targets the wrong bucket.

**(4) `claimWithdraw` credits `msg.sender`.** It reads `_completeWithdraw(msg.sender, _period)`, so
whoever calls it claims *their own* queued withdrawal. Trimmy must therefore be the `receiver` at
request time and must call `claimWithdraw` itself, then forward to `rule.account`.

Live parameters for `TESTearnXRP`, 2026-08-07:

| | |
| --- | ---: |
| `lagDuration` | 300 s |
| `withdrawalFee` | **0** |
| `depositCap` / `depositLimit` | 25,000,000 FXRP |
| `totalAssets` | 7,197.910581 FXRP |
| `totalSupply` | 6,795.784972 shares |
| share price | **1.05917** |

Note the deposit cap has enormous headroom here (7,198 of 25,000,000 used), so the §4c cap-filling
DoS that applies to stXRP **does not** apply to this vault — another reason it is the right lead.

**4b — stXRP has never accrued a unit of yield.** `totalAssets() == totalSupply() ==
100,748,433,000`, so share price is **exactly 1.000000**, and `previewDeposit(1e6) ==
previewRedeem(1e6) == 1e6`. A judge can falsify "auto-earn on a live, funded vault" with two
`cast call`s. **Lead the demo with TESTearnXRP** — 1.05917, a real 5.9% accrued — and disclose its
300 s redemption lag.

**4c — stXRP carries a hard 1,000,000 FXRP global deposit cap.** `maxDeposit(0xdEaD)` = 899,251.567
plus `totalAssets()` = 100,748.433 sums to exactly 1,000,000.000000. Anyone who fills the headroom
DoSes every auto-earn rule pointed at it. That is 22% of Coston2's FXRP float — expensive on
mainnet, patient work on a faucet chain.

---

## 4d. No Coston2 router has the assumed interface — verified 2026-08-06

All five deployed SwapRouters are **Uniswap V3**: `exactInput`, `exactInputSingle`, `exactOutput`,
`exactOutputSingle`. **None implements `swapExactTokensForTokens`.** Any design carrying a
`bytes32 pathHash` over a V2-style `address[] path` is written against a venue interface that does
not exist here. Swap execution must be built against `exactInput` with a V3 encoded path.

```bash
curl -s "https://coston2-explorer.flare.network/api?module=contract&action=getabi\
&address=0xe2B3aE21461c4ad3415210630EA210e9F53CCEBc" | jq -r .result | jq -r '.[].name' | sort -u
```

---

## 5. FTSO v2 — partially measured, one parameter still open

FtsoV2 on Coston2: `0xC4e9c78EA53db782E28f28Fdf80BaF59336B304d`.
XRP/USD feed id: `0x015852502f555344…` (`cast to-ascii` → `XRP/USD`).
`calculateFeeById` returns **0** — reads are free. `[Verified 2026-08-06]`

`getFeedById` returns `(uint256 value, int8 decimals, uint64 timestamp)`.

## 00. M-1 — the deployed contract silently ignored its own slippage floor. Fixed and redeployed.

**Found by adversarial review of the deployed bytecode, reproduced by an independent verifier, fixed,
and the fix proven by a regression test that fails against the old code.**

The contract is **non-upgradeable by design**, so every fix is a redeploy. The chain of addresses is
recorded rather than quietly replaced, because a judge should be able to see the vulnerable bytecode
and the regression test that fails against it.

## 0. REAL hardware attestation — a GCP_AMD_SEV enclave, live on Coston2 — 2026-08-09

| | |
| --- | --- |
| **Trimmy** | `0x9c7876df68b1220d87d2462de8791f13d4f4d452` |
| **TrimmyConfidentialTrigger** | `0x1121702e4bf66d73b42b8cadf6eef9c24268fd8d` |
| **FCC extension** | **66052** |
| **TEE machine** | `0xf5430C468Cde44226DdFfa705419ccD903f1bCD1` |
| **codeHash** (measured) | `0x95810e434ddb5d4ceb2a1a989aea42a6916f9adedb735f947924e51bcf50a1bd` |
| **platform** | `0x4743505f414d445f534556…` = **`GCP_AMD_SEV`** |
| GCP | `n2d-standard-2`, AMD SEV, Confidential Space, `us-central1-b` |

The attestation is a Google-signed JWT with a full certificate chain, carrying `hwmodel:
GCP_AMD_SEV`, `swname: CONFIDENTIAL_SPACE`, `secboot: true`, and the container's `image_id` — which
is what Flare records as `codeHash`. **It is not the simulated sentinel `0x194844cf…` shared by 254
machines.**

### The check that makes the whole claim mean anything

`isAuthorisedTee` requires **all three**: the machine serves *this* extension, its status is live,
and its platform is `GCP_AMD_SEV`. Verified on chain:

| machine | platform | authorised |
| --- | --- | --- |
| `0xf5430C46…` | GCP_AMD_SEV | **true** |
| `0x6cD70D9e…` | TEST_PLATFORM | **false** |
| any stranger | — | **false** |

**Why the platform check exists.** During bring-up our extension briefly had *two* live machines —
one real, one simulated — and `getRandomTeeIds` routed to either. Without the platform check both
were authorised. A `TEST_PLATFORM` machine's codeHash is a network-wide constant, so a verdict it
signs is one **anybody holding that constant could produce**. We would have shipped a
confidentiality claim backed by nothing, and demoed it working, because it does work.

### Five constraints Confidential Space imposes, each measured

1. **The image pins its own environment.** `tee.launch_policy.allow_env_override` lists nine
   variables; the launcher **refuses** any other. Correct — it stops behaviour changing after
   attestation. So `CHAIN_ID=114`, `SIMULATED_TEE=false` and the governance set are **baked into the
   measured image**, and they appear inside the attested claims.
2. **One container per VM.** The proxy and redis need a separate instance
   (`trimmy-proxy`, `e2-small`, `10.128.0.2`).
3. **linux/amd64 only.** An arm64 image fails with `no matching manifest for linux/amd64`.
4. **`register-tee -h` is written on chain.** Left at its default it registers `localhost`, which
   FTDC can never reach.
5. **Zonal SEV capacity is real.** `us-central1-a` returned "resources available to fulfill the
   request" — the enclave runs in `us-central1-b`.

### A silent ABI bug worth recording

`getTeeMachineWithAttestationData` returns a **struct**, not five values. Declaring five returns
compiles, and the *selector is identical*, so the call succeeds — but the record contains a dynamic
`string`, so the encodings differ, the return decode fails, and a `try/catch` reports **"not
authorised" for every machine, including the real one**. It was caught only because the on-chain
`extensionId`, `status` and `platform` were each verified correct while the predicate still said
`false`. The mock in `ConfidentialTrigger.t.sol` now uses the struct shape so the mistake cannot
pass the suite.

`[Unverified]` The VM uses `confidential-space-debug`, so the token carries `dbgstat: enabled`. A
production image would report `disabled`. Stated because a judge can read it in the token.

---

## 0a. Earlier: the simulated-TEE deployment — 2026-08-08

| | |
| --- | --- |
| **Trimmy** (PRIVATE enabled) | `0x6c74bC1154D32839A0900686450a9e2930c7bb46` |
| **TrimmyConfidentialTrigger** | `0xaBB8139fFB90FFD229594FbF5d5E6c4EE3910A97` |
| **FCC extension id** | **66031** |
| `FlareTeeManager` (diamond) | `0x1a9C4A0f9D76c0b1D91d22E24E573a9b377618aE` |

Verified independently of the registration tool's own output:

```bash
cast call 0x1a9C4A0f9D76c0b1D91d22E24E573a9b377618aE \
  "getTeeExtensionInstructionsSender(uint256)(address)" 66031 --rpc-url $R
# -> 0xaBB8139fFB90FFD229594FbF5d5E6c4EE3910A97
```

`setExtensionId(66031)` cost **64,474 gas**, and a second call reverts `ExtensionIdAlreadySet`
(`0x88f9fe3d`) — set-once holds on chain, not just in the source.

### Three findings from wiring it up

**(1) The TEE registries are NOT in `ContractRegistry`.** `TeeExtensionRegistry`,
`TeeMachineRegistry` and `FlareTeeManager` all resolve to `address(0)`. `[Verified]` So the rule
"only `ContractRegistry.address` is ever hardcoded" cannot be honoured by resolution for this
subsystem. It is honoured instead by making the manager a **deploy-time argument**, never a literal
in the contract, with the script probing it before deploying anything against it.

**(2) `FlareTeeManager` is one diamond serving BOTH registry interfaces.** `getRandomTeeIds` and
`getTeeExtensionInstructionsSender` both answer on the same address. `[Verified]` The scaffold's own
`config/coston2/deployed-addresses.json` lists the same address, which is an independent check on
the one Plimsoll's census found.

**(3) 482 public extensions were registered before ours, and that killed the obvious design.**
`setExtensionId()` originally *scanned* from `0x10000` to `nextPublicExtensionId()`, one external
call per id — over a million gas, growing without bound as the network fills. It now takes the id
and **verifies** it against the registry: O(1), and exactly as safe, because the registry is still
the authority and an id that does not point back at the contract is rejected.

`[Unverified]` **`teeAddress` is currently the deployer, not an enclave.** It is immutable and
`acceptVerdict` requires `ecrecover` to return exactly it, so the real value can only be bound once
a TEE machine registers and its signing address is known. Until then the confidential path is
deployed, registered and wired — but **not yet backed by a real enclave**, and no submission
material may imply otherwise.

### The complete fix set from adversarial review

Ten findings, every one closed with a regression test that fails against the code it describes.
**66 core tests green**; the proof-of-concept exploits are kept in `test/research/` as evidence.

| # | Severity | What it was |
| --- | --- | --- |
| **M-1** | critical | `uint64` saturation. For the only sell-side pair the allowlist permits, the relative price is ~1.7e20 — **9.3x past `uint64`** — so the latch saturated and a rule armed at 50 bips settled at **10.7% of oracle fair value** while reporting it had honoured its floor. |
| **M-2** | high | `claim()` paid a rule out of the whole per-period vault bucket. A rule that queued 1 unit was paid 100,000,001. |
| **M-3** | medium | A second queued redemption overwrote `claimPeriod` while `pendingShares` accumulated, orphaning the first bucket. |
| **AUTH-3** | medium | `cancelAll()` bumped `epochOf[msg.sender]`, so a **guardian pressing the panic button bumped its own empty epoch** and the rule ran anyway. |
| **AUTH-4** | medium | `claim()` bypassed `_load`, charging fees on a rule the owner had cancelled. |
| **AUTH-5** | medium | *Introduced by our own M-3 fix.* `try…catch {}` swallowed **every** failure, then paid from the shared balance. |
| **AUTH-7** | medium | `_refund()` sent `address(this).balance` — one caller collected another's FLR. |
| **M-2d** | medium | `_validate` never asserted an EXIT_VAULT rule sells the venue's *share* token. |
| **AUTH-6** | low | EXIT_VAULT charges the keeper twice per part; the budget was sized for one. |
| **AUTH-9** | low | Constructor validated decimals and nothing else, on a contract with no setter and no rescue. |

Plus two from the oracle lens, resolved by argument rather than by patch:

- **O-16 / O-18** — the latch was permanent and unconditional, so latching at a local maximum
  **bricked a rule for its whole life**, and one future-dated feed poisoned the floor forever. Fixed
  together: the latch now decays linearly to the live price over one hour and never sits below live,
  and `requireFresh` refuses anything more than 10 s ahead of the block clock.
- **O-17** — reported as "the floor is on gross, the user receives less". Implemented as proposed, it
  **broke two tests**, which settled it: a flat keeper fee is routinely a larger fraction of a small
  part than the whole 50-bip band, so a net-bound floor is unsatisfiable by any venue and every such
  rule would silently never execute. The floor bounds what an *adversary* takes through the venue —
  that is gross. The real defect was disclosure, and it is fixed in `arming/bin/decode.dart`.
- **O-19** — the reviewer was right and the earlier reasoning here was wrong. `maxFeedAge` was 120 s
  on liveness grounds, but a five-minute realised XRP move already exceeds the entire 50-bip band,
  so every extra second of staleness is extractable. Now **64 s**, 2x the measured max-of-p99.

**Two claims survived attack and are the ones the submission may keep.** Proven at source,
**deployed-bytecode**, dispatch-table and fuzz levels: the token and venue allowlists are write-once
with no owner, upgrade or selfdestruct path; and a hostile contract as `rule.account` cannot
re-enter — refuted against a *hooking* mock, so it holds for any future allowlist rather than
resting on "FXRP has no transfer hooks today".

| Deployment | Status |
| --- | --- |
| `0xf73a2af06b315adaa1afe2c1a6c1a6933d8a6554` | **M-1 vulnerable — do not use** |
| `0xeaF2eA3924D5337B2Dd22ae7BFCACEdAc3D913D5` | M-1 fixed, M-3 still latent |
| **`0x3719bAC08F50eC2E165c3078412987d1a39C6D9C`** | **current — M-1 and M-3 both fixed** |

Loop re-verified on the current deployment after each redeploy: rule armed, keeper executed it
independently, fee paid (28,200 → 37,600 vault shares).

### M-3 — the vault exit could orphan a bucket, and a stranger could strand the payout

Two halves, both closed on the current deployment:

**(a) A second queued redemption orphaned the first.** `_doQueueRedeem` accumulated
`pendingShares +=` while overwriting the scalar `claimPeriod`. A second part landing in a different
day-bucket left the first bucket unreachable — `claim()` can only ever name one period. Fixed by
allowing **one outstanding redemption per rule**: a second queue reverts `RedemptionAlreadyPending`.
That is safe precisely because `claim()` is permissionless — anyone can clear the block.

**(b) A stranger could strand the user's assets.** The real vault exposes
`claim(uint256 year, uint256 month, uint256 day, address receiver)` — **public, no access control**.
A third party can push our bucket into Trimmy before we call `claimWithdraw`, making our call a
no-op. `claim()` settled the balance *delta* around its own call, so the user would have been paid
**zero** and the assets left in a contract with no sweep. Fixed by recording `pendingAssets` at
queue time and paying `min(pendingAssets, balanceOf(this))`, tolerating a `claimWithdraw` that moves
nothing.

Regression: `test/M3Regression.t.sol`, 4 tests, against a mock faithful to the verified vault source
**including its push-claim** — the function the original report's own mock omitted, which is why the
report concluded the assets "sit in the vault" when they in fact strand in Trimmy.

### What was wrong

`Rule.latchedPrice` and `Rule.triggerValue` were `uint64`. Both hold a **relative** price — buy-token
base units per one whole sell token. For the allowlisted FXRP → WC2FLR pair, `Quote.convert`'s
exponent is `(18 + 8) − (6 + 6) = +14`, so the value is **~1.72e20 against a `uint64` max of
1.84e19 — a 9.34× overflow.**

Three consequences, each measured:

1. **The floor did not bite.** `_doSwap` derives `floorOut` from `latchedPrice`. Saturated, that
   floor is ~10.7% of oracle fair value. A rule armed at **50 bips** of slippage settled at
   **~11% of fair value** and reported success. Effective tolerance ≈ **8,930 bips, 179× the
   declared figure.**
2. **`PRICE_ABOVE` fired 5× below its threshold**, because the strictest expressible `uint64`
   threshold was already far under the live price.
3. **`PRICE_BELOW` could not fire after a 9× crash** — every price in that band saturated to the
   same sentinel, so a protective stop was inert exactly when it mattered.

And the consent surface lied: `arming/bin/decode.dart` printed *"slippage 50 bips max"* to the user
about to sign an irreversible XRPL payment.

### Why it was not yet exploitable, and why that is not a reprieve

No FXRP/WC2FLR pool exists — `getPool` returns `address(0)` for all four fee tiers — and all live
rules were `DEPOSIT_VAULT`, which never reads `latchedPrice`. Zero funds were ever at risk.

But GROUND-TRUTH §3 says the plan is to **seed that pool ourselves**, and the contract has no proxy.
Seeding it would have armed the defect with no way to patch. The bug was harmless only by accident
of timing.

### The fix

Both fields widen to `uint128`, the slot layout is reorganised into 8 slots, and the saturating
clamp in `_evaluateTrigger` is **deleted** — an unrepresentable price now reverts rather than
silently becoming a wrong floor (rule 7: unknown means do not execute). A zero threshold on a price
trigger is also refused at arm time.

Regression: `test/M1Verify.t.sol`, 7 tests. `test_floorIsEnforcedAtDeclaredSlippage` fails against
the old code and passes against the new. `test_priceBelowFiresOnACrash` proves a protective stop now
fires. One of these tests is worth quoting in full, because it is the clearest statement of the bug:
a user asking to *"sell if 1 XRP drops below 150 WC2FLR"* — `150e18` — **could not express that
threshold at all** under `uint64`.

### What the fix broke downstream, and how it was caught

The struct reorder shifted the keeper's word indices: `keeperFeeFlat` 16→18, `pendingShares` 19→21,
`claimableAt` 22→16. The keeper decodes `ruleAt` **by word index**, so a stale index would have had
it read `trigger` as `active`. And `arm()`'s selector changed from `c33d4cc3` to **`cc0c55f4`**.
Both updated, and the full loop re-verified on the new deployment: rule armed, keeper executed it,
fee paid 18,800 → 28,200.

---

## 0. The whole product, end to end, from one XRPL payment — 2026-08-07

**A user holding no FLR, running no EVM wallet, signing nothing but an XRPL payment, ended up with
a rule that executed itself and paid them.** Every step below is a public transaction.

| # | Step | Transaction | Outcome |
| --- | --- | --- | --- |
| 1 | XRPL payment, 5 XRP, 42-byte `0xFE` memo | `E41504D3356C15789D4B6602F0F2E8B151F04FFAA5BBF2E3F71640C92B59B6E0` | `tesSUCCESS`, ledger 19698983 |
| 2 | FDC attestation, voting round 1418293 | `0x0a3f05f72f9425f93ff64290d862ffc6498e82e0dfb7a6f7e57448ea035a82d9` | fee 1000 wei; proof after 5 polls |
| 3 | `executeDirectMintingWithData(proof, userOp)` | `0x86d54bd6821b7598cde03d68f0e1642da1b4714a52e91e445396095bc12cf6cc` | 742,307 gas |
| 4 | keeper executes the rule | `0xa74e9fc270bef95449e5821c0403c26b28c00b095d0e7b7a25bc2496e18a37b1` | proceeds paid |

State transitions, measured before and after:

| | before | after |
| --- | ---: | ---: |
| `Trimmy.ruleCount()` | 3 | **4** |
| controller `getNonce(pa)` | 0 | **1** (user operation consumed) |
| personal-account FXRP | 3,600,000 | **8,400,000** (+4.8 FXRP minted) |
| allowance PA → Trimmy | 0 | **1,009,400** (exact, not unlimited) |
| personal-account vault shares | 0 | **934,733** |
| keeper vault shares | 9,400 | **18,800** |

Rule 3 reads back with `account` = the personal account `0x07A76b5C…20bf`, `active = true`,
`DEPOSIT_VAULT` / `SCHEDULE`, `keeperFeeFlat = 9400`.

**Step 3 is the one nobody had done.** Nothing in Plimsoll's evidence shows a `0xFE` Smart Accounts
payment executed end to end — its measurements all used the 48-byte `DIRECT_MINTING_EX` branch.

### Trimmy must run its own executor — measured, not assumed

Two arming payments were sent. Both were `tesSUCCESS` on XRPL. **Neither was ever picked up by the
public executor**, at 600 s each:

| XRPL tx | `executorFeeUBA` | picked up? |
| --- | ---: | --- |
| `C122663D…326104` | **0** | no |
| `E41504D3…59B6E0` | **100,000** | no |

The first reproduces Plimsoll GROUND-TRUTH §10.3 — *"the executor earns nothing, so nobody
volunteers"* — and its 5 XRP is still sitting at the Core Vault, which is exactly what that section
predicts. `arm.dart` now **refuses** to emit a zero-executor-fee payment for that reason.

The second is the new finding: **a full executor fee was offered and it was still ignored.** §10.3
does not explain that; the routing branch does. Plimsoll measured the public executor on
`DIRECT_MINTING_EX`; on `0xFE` Smart Accounts it does not appear to act at all.

> **Consequence for the architecture.** Running our own executor is not optional hardening for
> Trimmy — it is required for the only branch the product uses. `tools/execute_arming.py` does it,
> reusing Plimsoll's GATE 3 pipeline rather than reimplementing attestation.

---

## 0a. Trimmy is live on Coston2 and has executed a real rule — 2026-08-07

**`Trimmy` — `0xf73a2af06b315adaa1afe2c1a6c1a6933d8a6554`** ([explorer](https://coston2-explorer.flare.network/address/0xf73a2af06b315adaa1afe2c1a6c1a6933d8a6554))

An auto-earn rule was armed and executed against **TESTearnXRP**, a real third-party vault we do not
control. Three transactions, all on chain:

| Step | Tx |
| --- | --- |
| `approve` (exact size, never unlimited) | `0x7b88ac308da099e52874f8f4b1cc26ebf9df6c11b6b140bb12dfab878bed4a81` |
| `arm` | `0x6d791f9e02e74f7a65e843dcb155b6f27a9aa374b5e74681ed4f4b32d9ed68f0` |
| `execute` (permissionless) | `0xf682b1ae694c0d0a7996acc64f8d9cc06cc095155bd5333a53370881001ec11a` |

Measured outcome: FXRP `23.150001 → 22.150001` (−1 FXRP), TESTearnXRP shares `0 → 944133`. That
share figure equals `previewDeposit(1 FXRP)` **exactly**, and the shares landed with
`rule.account` — not with the caller. `rule.spent` became `1000000` and `rule.active` flipped to
`false` on exhaustion, as the invariant requires.

### A rule fired with nobody pressing the button — 2026-08-07

The product claim is that a rule executes itself. Demonstrating that requires an executor who is
**not** the user, so a separate keeper identity was generated
(`0xF0533D37F7ed8d1C45A87Bb35750DA4665bd6D9E`), funded with gas only, and given no authority of any
kind. Rule 2 was armed and left alone; the keeper found it, simulated it, and executed it.

| | before | after | delta |
| --- | ---: | ---: | ---: |
| user vault shares | 1,888,266 | 2,822,999 | **+934,733** |
| keeper vault shares | **0** | **9,400** | **+9,400** |

`execute` tx `0x50ef27fd67464424b23687b740df65d2aa7d729d8b3df16deb314173f244a720`.

The keeper started from zero, earned exactly the flat fee it was owed, and the proceeds went to
`rule.account`. It never held an allowance, a balance or a key belonging to the user. This is the
testable form of "the keeper is trusted with nothing", and it is the sentence the submission may
keep.

An earlier run had the keeper and the user on the **same** address, which made the split visible in
the event log but not in balances — unverifiable, and a judge would say so. Hence the separate
identity.

### The XRPL arming payload is verified four independent ways — 2026-08-07

`trimmy/arming` builds the `0xFE` payment from Plimsoll's **measured** `PackedUserOperation` layout.
For our XRPL account `rDE4JUm2jaue31VwidRXWuWzf5dQkUxcsB`:

| | |
| --- | --- |
| personal account | `0x07a76b5c3d03f5bff4cb3e043b1d17a1b40920bf` |
| `controllerAddress()` on it | `0x434936d4…` — the canonical one |
| `xrplOwner()` on it | `rDE4JUm2jaue31VwidRXWuWzf5dQkUxcsB` |
| `getNonce(pa)` on the controller | `0` |
| batch | `approve(Trimmy, 1_009_400)` then `arm(...)` |
| memo | 42 bytes, `FE 00 0000000000000000 ‖ keccak256(userOp)` |

The four checks, each against something we did not write:

1. **Selector** — our `arm(...)` selector `c33d4cc3` equals `cast sig`'s.
2. **Commitment** — our `keccak256(abi.encode(userOp))` equals `cast keccak` of the same pre-image.
3. **Decoder round-trip** — Plimsoll's independently-written `decodeExecuteUserOp` decodes the batch
   our encoder produced, and the tool **refuses to emit a payment** if it does not.
4. **The live contract** — simulating that exact `arm` calldata against the deployed Trimmy from the
   personal account returns a rule id.

`getNonce` lives on the **controller**, not the personal account: `getNonce()` and `nonce()` both
revert on the account itself. Worth recording, because guessing wrong there produces an
`InvalidNonce` revert after an irreversible payment.

### O-3 is settled: `execute()` costs 383,451 gas

```
383,451 gas × 2125 gwei = 0.8148 C2FLR = $0.00484   (FLR/USD 0.00594005)
                                       = 0.004698 FXRP = 4,698 UBA
```

**Minimum viable `keeperFeeFlat` ≈ 4,698 UBA; use ~9,400 (0.0094 FXRP) for 2× margin.** A rule armed
with a flat fee below that is one no rational keeper will ever execute — which is why `arm()`
refuses a fee budget that cannot fund the rule's own executions (L2).

`[Unverified]` Coston2's 2125 gwei is a testnet artefact and is not Flare mainnet's gas market. The
mainnet figure needs its own measurement before this number is quoted as a production fee.

---

### Every feed has a different decimal scale — read live 2026-08-07

`FtsoV2` resolved from the registry at runtime: `0xC4e9c78EA53db782E28f28Fdf80BaF59336B304d`.
Feed IDs are **`bytes21`** — one category byte (`0x01` = crypto) plus the ASCII name, zero-padded to
20 bytes.

| Feed | `bytes21` id | value | dec | price |
| --- | --- | ---: | ---: | ---: |
| FLR/USD | `0x01464c522f5553440…` | 593965 | **8** | $0.00593965 |
| XRP/USD | `0x015852502f5553440…` | 1028774 | **6** | $1.028774 |
| BTC/USD | `0x014254432f5553440…` | 6435271 | **2** | $64,352.71 |
| ETH/USD | `0x014554482f5553440…` | 1900993 | **3** | $1,900.993 |
| USDT/USD | `0x01555344542f55534…` | 999158 | **6** | $0.999158 |
| USDC/USD | `0x01555344432f55534…` | 999823 | **6** | $0.999823 |
| USDX/USD | `0x01555344582f55534…` | 99346 | **5** | $0.99346 |
| SGB/USD | `0x015347422f5553440…` | 1015880 | **9** | $0.00101588 |

```bash
R=https://coston2-api.flare.network/ext/C/rpc
FTSO=$(cast call 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019 \
  "getContractAddressByName(string)(address)" "FtsoV2" --rpc-url $R)
cast call $FTSO "getFeedById(bytes21)(uint256,int8,uint64)" \
  0x015852502f55534400000000000000000000000000 --rpc-url $R
```

**Eight feeds, six distinct decimal scales, in one read.** This is the live proof of the SDK's rule
2 — any code that hardcodes a scale, or reuses one feed's scale for another, is wrong for six of
these eight. It is also why `Quote.convert` carries `value` and `decimals` together and treats
`decimals` as a signed `int8`.

### Counter-token choice — verified 2026-08-07

`WNat` resolves from the registry to **`0xC67DCE33D7A8efA5FfEB961899C73fe01bCe9273`**, symbol
`WC2FLR`, **18 decimals**. FXRP `0x0b6A3645c240605887a5532109323A3E12273dc7` is `FTestXRP`,
**6 decimals**.

We pair **FXRP/WC2FLR**, not FXRP/testUSDT. Coston2 carries at least five unrelated "USDC" tokens
and three "testUSDT" variants, all participant-deployed and of unknown provenance — a bad basis for
an allowlist that is immutable for the contract's life. `WNat` is resolved from the registry, so it
carries no trust assumption, and both legs have real FTSO feeds at **different scales** (6 dp token
with a 6 dp feed against an 18 dp token with an 8 dp feed), which exercises the quote path properly
rather than trivially.

### Staleness, measured correctly — 2026-08-06

Two earlier passes disagreed (7/8 at 0–4 s with a 29 s outlier; 12/12 at exactly 6 s). Both measured
the **wrong quantity** — `wallclock_at_curl − ts`, with the RPC caching layer in between — whereas a
contract sees `block.timestamp − ts`.

Redone properly: **400 contiguous blocks**, each pairing `eth_getBlockByNumber` with an `eth_call` of
`getFeedById(XRP/USD)` *pinned to that same block*, so the quantity measured is exactly the one the
contract sees.

| Quantity | p50 | p90 | p99 | max |
| --- | ---: | ---: | ---: | ---: |
| Feed age (`block.timestamp − ts`) | **0 s** | 2 s | 5 s | **7 s** |
| Inter-block gap | **1 s** | — | 2 s | 2 s |

Feed value changed on **107 of 399** block steps (27%). XRP/USD moved 18.1 bips over the 414 s
window, with zero excursions ≥10 bips below the median. `[Measured]`

### O-2 is settled — 5 separated windows, 750 samples, 2026-08-07

```bash
python3 tools/sample_feed_age.py 5 150 210
```

| window | p50 | p90 | p99 | max | gap p50 | gap max |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0 s | 15 s | **34 s** | 35 s | 1 s | 20 s |
| 2 | 0 s | 14 s | **34 s** | 35 s | 1 s | 20 s |
| 3 | 0 s | 12 s | **25 s** | 27 s | 1 s | 21 s |
| 4 | 0 s | 14 s | **25 s** | 26 s | 1 s | 22 s |
| 5 | 0 s | 21 s | **33 s** | 34 s | 1 s | 25 s |

**Max of the per-window p99s: 34 s. Global max: 35 s.**

This is the number, and it vindicates sampling more than one window. The earlier single-window pass
reported a p99 of **5 s** and a max of **7 s** — roughly seven times tighter. A `maxFeedAge` derived
from that window would have refused to execute through ordinary chain behaviour, permanently,
because the parameter is `immutable` on a non-upgradeable contract.

**Deployed value: 120 s.** Deliberately above the 68 s that doubling the max-of-p99 suggests. The
asymmetry justifies it: too tight is a permanent liveness failure that can only be fixed by
redeploying, while too loose is bounded on the other side by the FTSO-derived execution floor, which
rejects a bad fill regardless of how the price was aged.

> **Two bugs in the measurement tool itself, both silent.** The first version used a recalled
> function selector (`0xc65e6b42`; the real one is `0x93e9f806`, per `cast sig`) and reported six
> consecutive empty windows without an error, because it *skipped* failed calls instead of
> reporting them. Both are fixed: the selector is verified, and failures are counted and printed.
> Silence is not success.

### What the latency measurement actually proves

The keeper's floor is **one block — 1 to 3 seconds measured.** That is fast, and nobody else on
Flare has it.

But the keeper reads *the same feed the contract will re-check*, so it has **zero information
advantage** and provides no protection faster than the feed itself. Three consequences:

- A wick shorter than one block is untradeable. `execute()` re-checks the trigger, so if the feed
  recovers in block N+1 the transaction **reverts**.
- Near a threshold the value oscillates across it, so **reverts are the common case** and the keeper
  eats gas for them. That cost term is missing from every fee model written so far.
- The realised price is set by the depth of a pool we seeded ourselves, floored at
  `oracleOut × (1 − maxSlippageBips)` — and an attacker takes that band with certainty (§9 A2).

**Therefore: never say "stop-loss protection".** Say *"one-block conditional execution against the
FTSO with an oracle-enforced floor, 1–3 seconds measured."* True, demonstrable on stage, and not
falsifiable by a judge.

### Decimal normalisation

`decimals` is `int8` and **may be negative**. Comparing a feed value to a user threshold without
handling that sign is a classic money bug. The normalisation must be written once, fuzz-tested, and
used everywhere.

---

## 6. The TEE machine census — measured 2026-08-06

`FlareTeeManager` (Coston2): `0x1a9C4A0f9D76c0b1D91d22E24E573a9b377618aE`.

Of **268 active TEE machines**:

| Platform | Count |
| --- | ---: |
| `TEST_PLATFORM` (simulated) | **254** |
| `GCP_AMD_SEV` | 7 |
| `GCP_INTEL_TDX` | 7 |

The simulated machines are **routable** — `getRandomTeeIds`, the function `sendInstructions` actually
uses for selection, returned one:

```bash
cast call 0x1a9C4A0f9D76c0b1D91d22E24E573a9b377618aE \
  "getRandomTeeIds(uint256,uint256)(address[])" 65553 1 --rpc-url $R
# -> [0x0fcAB6A37ce455113824aE1655143DD30946085a]   proxy: trycloudflare.com tunnel
```

Flare's own production machine and a laptop behind an ngrok tunnel carry the identical on-chain
status, `2`.

**This contradicts Flare's own documentation**, which states in three places in
`fce-sign/TESTNET_DEPLOYMENT.md` that FTDC rejects simulated TEEs. The chain is the authority; the
docs are stale. `[Verified — live reads]`

**But** every simulated machine shares the same `codeHash`
`0x194844cf417dde867073e5ab7199fa4d21fd82b5dbe2bdea8b3d7fc18d10fdc2` — a sentinel constant in
Flare's own tooling. It therefore **proves nothing about which code is running**, and any "verify the
code hash on-chain" step in a simulated deployment is decoration, not a guarantee.

`[Unverified]` Whether `TEST_PLATFORM` acceptance survives the judging window. Acceptance today
contradicts written policy, so the likeliest explanation is a hackathon-period relaxation that can
revert. **Experiment:** re-run the census on 2026-08-14 and 2026-08-18 and check our own machine's
`getTeeMachineStatus` is still `2`.

---

## 7. Restated from Plimsoll — direct minting fees and the dead zone

Restated here with its own provenance so this document stands alone. Measured 2026-08-02 against the
Coston2 asset manager `0xc1Ca88b937d0b528842F95d5731ffB586f4fbDFA`, resolved through the registry.

| Setting | Raw | Meaning |
| --- | ---: | --- |
| `getDirectMintingFeeBIPS` | 25 | 0.25% |
| `getDirectMintingMinimumFeeUBA` | 100000 | 0.1 XRP |
| `getDirectMintingExecutorFeeUBA` | 100000 | 0.1 XRP |
| `getDirectMintingOthersCanExecuteAfterSeconds` | 7200 | 2 h executor exclusivity |
| `getDirectMintingLargeMintingThresholdUBA` | 1e11 | 100,000 XRP |
| `getDirectMintingHourlyLimitUBA` | 1e11 | 100,000 XRP/hour |
| `getDirectMintingDailyLimitUBA` | 5e11 | 500,000 XRP/day |
| `directMintingPaymentAddress` | `rDhpmiPq4BVBDWMVdSrmkgt8thKyRzGV1p` | Core Vault, XRPL testnet |

**The dead zone.** Anything from 0.1 to 0.2 XRP inclusive delivers the recipient **exactly zero**,
silently — no event, no revert, transaction succeeds. The true floor is `minimumMintingFeeUBA +
executorFeeUBA + 1` = **0.2 XRP + 1 drop**, a number that appears in no single protocol setting and
moves whenever governance changes either component. The protocol's own `paymentTooSmall` flag checks
only against the first of the two, so it is `false` across the entire dead zone.

This is why the arming preflight computes the outcome rather than trusting a protocol flag, and why
Trimmy refuses to arm a rule whose fee cannot cover its own execution.

---

## 8. Open — must be measured before the corresponding code is written

| # | Question | Blocks |
| --- | --- | --- |
| O-1 | Do fee-only direct mints (`netMintAmountXrp: 0`) succeed or revert? Sources assert both. | The arming payment shape — the product's first sentence |
| O-2 | Does `AssetManager.redeem` accept a third-party redeemer with a user-specified XRPL destination? | Drip payout and the dead-man switch |
| O-3 | In-contract FTSO feed age distribution (§5) | `maxFeedAge` |
| O-4 | Gas cost of `execute()` on Coston2 | The minimum viable keeper fee, and the refuse-to-arm threshold |
| O-5 | Keeper latency from an FTSO tick crossing a trigger to `execute()` landing | Whether a stop-loss means anything at all |
| O-6 | Does Flare have a propagating public mempool? `txpool_*` absent, pending filter empty — but that is one RPC's behaviour | How loudly we may claim MEV resistance |
