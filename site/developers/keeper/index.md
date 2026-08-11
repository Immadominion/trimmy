---
title: Running a keeper
summary: What the Trimmy executor polls, why it simulates before it signs, what it earns, the measured gas, and why running your own is required rather than optional.
order: 4
---

A Trimmy rule executes because somebody calls `execute(uint256)` and gets paid for it. That somebody is a keeper. This page documents the reference implementation, [`keeper/bin/keeper.dart`](https://github.com/Immadominion/trimmy/blob/main/keeper/bin/keeper.dart), which is about 350 lines of Dart on our own Flare SDK.

Coston2 testnet only. No part of this has run on Flare mainnet.

## The keeper holds no authority

`Trimmy.execute` re-derives every bound on chain from the stored rule and a fresh two-legged FTSO read. `msg.sender` appears in the function exactly once, as the recipient of the flat keeper fee. Nothing a caller supplies can loosen a bound.

Below that sits the fact the whole architecture rests on: `PersonalAccount.executeUserOp` carries `onlyController`. Measured on a live personal account, a raw `eth_call` with the literal selector `0x2b2ee783` returns `0x` from the controller and reverts `OnlyController()`, error data `0x59907813`, from any other address. The modifier is present in both deployed implementations.

So a leaked keeper key buys an attacker nothing the public does not already have, and the same is true of a compromised agent that composed the rule: the only durable authorization a rule holds is an exact-size ERC-20 allowance granted inside the arming batch. Maximum extraction from either is zero.

A note on the trap: `cast call $PA "executeUserOp((address,uint256,bytes)[])"` computes a different selector and fails for an unrelated reason, which reads as confirmation if you are not careful. Use raw `eth_call` when a selector matters.

Keeper liveness is therefore not a security property. Anyone can run one. We run one because someone has to.

## What it polls

One sweep is `ruleCount()`, then `ruleAt(uint256)` for every id, sequentially. Each rule is decoded **by word index** from the ABI-expanded struct:

| word | field | word | field |
| ---: | --- | ---: | --- |
| 0 | `account` | 14 | `nextEligibleAt` |
| 1 | `epoch` | 15 | `expiry` |
| 4 | `verb` | 16 | `claimableAt` |
| 6 | `trigger` | 18 | `keeperFeeFlat` |
| 7 | `active` | 21 | `pendingShares` |
| 8 | `totalSellAmount` | | |
| 10 | `spent` | | |

These indices are load-bearing and they have moved. The M-1 fix widened `triggerValue` and `latchedPrice` to `uint128` and reordered slots, shifting `keeperFeeFlat` from 16 to 18, `pendingShares` from 19 to 21 and `claimableAt` from 22 to 16. An index one out makes the keeper read `trigger` where it expects `active`, with no error.

The local filter is deliberately weak. A candidate is ruled out only on facts that are certain from stored state: `active`, `spent >= totalSellAmount`, and a stale epoch (`rule.epoch != epochOf(rule.account)`, which is what `cancelAll` bumps). Anything needing a fresh oracle read, the price trigger, feed staleness, the execution floor, is left to the chain. Reimplementing that logic in the keeper would create a second implementation that can silently disagree with the contract.

For `EXIT_VAULT` rules with `pendingShares > 0` the keeper also tries `claim(uint256)`, because the yield venues have no synchronous exit.

## It simulates before it signs

Near a price threshold the feed oscillates across the trigger, so a reverting `execute` is the common case, not the exceptional one. Every candidate is simulated with `eth_call` at the current block, from the keeper address, and a transaction is signed only if that simulation succeeds. A revert costs an RPC round trip instead of gas.

This is measurable rather than aspirational. During the swap work the contract refused three sells into a pool that had drifted 36.6 bips below the oracle, and **the keeper signed none of the three**. Each died in pre-simulation. The one execution against an honestly priced pool filled at 5.6 bips.

Custom-error selectors are mapped back to names so the log reads as a reason rather than a 4 byte blob: `NotYetEligible`, `TriggerNotMet`, `RuleInactive`, `RuleExpired`, `StaleEpoch`, `Exhausted`, `FloorBreached`, `FeedStale`, `NotYetClaimable`, `NothingPending`.

## Signing

The SDK holds no private keys and never will. It builds the transaction, prices it, broadcasts the signed bytes, waits for the receipt and explains a revert. The signature itself is shelled out to Foundry's `cast mktx`, so `cast` must be on your PATH.

The gas limit comes from `prepareTransaction`, which pads the estimate to the larger of estimate plus 5 percent and estimate plus 75,000. The node adds no buffer of its own.

## Measured gas and what a keeper earns

| path | gas | source |
| --- | ---: | --- |
| `execute()`, plain | 383,451 | settles open question O-3 |
| `execute()`, live keeper transaction `0xd88f7cac…` | 476,842 | current deployment, 2026-08-09 |
| `execute()`, PRIVATE trigger | 517,962 | confidential path |
| `executeDirectMintingWithData` (the arming leg, not the keeper's) | 747,096 | same run |

At Coston2's 2125 gwei, 383,451 gas is 0.8148 C2FLR, about $0.00484 at FLR/USD 0.00594005, which is 4,698 UBA of FXRP. So the minimum viable `keeperFeeFlat` is roughly 4,698 UBA and rules are armed at 9,400 (0.0094 FXRP) for 2x margin. Coston2's 2125 gwei is a testnet artefact and is not Flare mainnet's gas market; the mainnet figure needs its own measurement before anyone quotes it as a production fee.

The fee is paid out of the proceeds, in the proceeds token. Measured on a rule executed by a keeper that started from zero: keeper vault shares 0 to 9,400, user vault shares +934,733, proceeds to `rule.account` and not to the caller. On the current deployment the same split showed as keeper shares 65,800 to 75,200, exactly the `keeperFeeFlat` of 9,400. The keeper identity used for that demonstration was `0xF0533D37F7ed8d1C45A87Bb35750DA4665bd6D9E`, funded with gas only.

Run the keeper on a different address from the user's. With both on one address the split is visible in the event log but not in balances, which makes it unverifiable.

## Running it

The Dart packages depend on two sibling repositories by path, so a clone of `trimmy` alone does not resolve. [`setup.sh`](https://github.com/Immadominion/trimmy/blob/main/setup.sh) clones them.

```bash
./setup.sh                       # puts sdk/ and plimsoll/ beside this repo, then verifies
cd keeper
source ~/.flare-dart/coston2-test.env

export TRIMMY_ADDRESS=0x19F81AAB43f7a26B0659754b70179aDcAF43ef7C
export KEEPER_ADDRESS=0x...      # falls back to COSTON2_TEST_ADDRESS
export KEEPER_KEY=0x...          # falls back to COSTON2_TEST_KEY

dart run bin/keeper.dart --once             # one sweep, then exit
dart run bin/keeper.dart --interval 15      # loop, 15 s between sweeps (the default)
dart run bin/keeper.dart --once --dry-run   # simulate, never sign
```

With no key present the keeper runs dry regardless. `TRIMMY_ADDRESS` is required and the process exits 2 without it. Output is one line per decision, `HH:MM:SS  rule <id>  EXEC|CLAIM|skip  <detail>`, then a summary of rules scanned, executed and skipped. A skip always states why. A keeper that goes quiet is indistinguishable from a keeper that is broken.

## Why you have to run an executor at all

The keeper executes armed rules. A second, separate role executes the arming payment itself, and that one is not optional either.

Two arming payments were sent, both `tesSUCCESS` on XRPL, and **neither was picked up by the public Flare executor** after 600 seconds each. The first offered `executorFeeUBA = 0`, which the fee argument already predicts. The second offered a full 100,000 UBA fee and was still ignored. The public executor was measured on the 48 byte `DIRECT_MINTING_EX` branch; on the 42 byte `0xFE` Smart Accounts branch it does not appear to act at all. That is the only branch Trimmy uses, so [`tools/execute_arming.py`](https://github.com/Immadominion/trimmy/blob/main/tools/execute_arming.py) does the job, reusing an existing attestation pipeline rather than reimplementing it.

## Limits of this implementation

- **It does not drive PRIVATE rules.** A PRIVATE rule's `execute` calls `consumeVerdict`, which needs a fresh enclave verdict accepted on chain first. The keeper's trigger handling covers 0, 1 and 2. Simulation will simply refuse a PRIVATE rule, so it costs nothing, but it also never fires from this process.
- **PRIVATE gas is not safe to estimate.** One attempt ran out of gas after emitting `Executed`, so every transfer succeeded and the tail reverted. That path needs an explicit limit rather than `eth_estimateGas`.
- **It attaches no `msg.value`.** `execute` is payable so a caller can cover an FTSO feed fee. `calculateFeeById` returned 0 on Coston2 (verified 2026-08-06). If governance ever sets a fee, this keeper reverts with `InsufficientFeeValue` until it is changed.
- **The scan is O(n) and sequential**, one `ruleAt` round trip per rule per sweep, plus an `epochOf` call per active rule. Fine at current rule counts, not a design for thousands.
- **No mempool assumptions.** Whether Flare has a propagating public mempool is an open question in the repo's own notes, and keeper latency from a tick crossing a trigger to `execute` landing has not been measured.

Contracts: 92 Foundry tests, `cd contracts && forge test --no-match-path "test/research/*"`.
