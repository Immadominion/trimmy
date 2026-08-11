---
title: Deployments
summary: Every Trimmy contract deployed on Coston2, current and superseded, with what was wrong with each and a cast block that reads live state.
order: 6
---

Everything is on **Flare Coston2 testnet**, chain id 114, RPC
`https://coston2-api.flare.network/ext/C/rpc`. Nothing has been deployed to Flare mainnet.

[`Trimmy.sol`](https://github.com/Immadominion/trimmy/blob/main/contracts/src/Trimmy.sol) has no owner, no proxy, no pause and no rescue path,
and its token and venue allowlists are written once in the constructor. Every fix is therefore a
redeploy, and every superseded address stays on chain. They are listed here with what was wrong,
because a reader should be able to load the vulnerable bytecode and the regression test that fails
against it.

## Current

| what | address | notes |
| --- | --- | --- |
| `Trimmy` | [`0x19F81AAB43f7a26B0659754b70179aDcAF43ef7C`](https://coston2-explorer.flare.network/address/0x19F81AAB43f7a26B0659754b70179aDcAF43ef7C) | deployed 2026-08-09, 4,533,573 gas |
| `TrimmyConfidentialTrigger` | [`0x02EA709e2278EACDbA00D4A88caA604E3b35293b`](https://coston2-explorer.flare.network/address/0x02EA709e2278EACDbA00D4A88caA604E3b35293b) | deployed 2026-08-09, 2,376,295 gas |
| FCC extension id | `66052` | `getTeeExtensionInstructionsSender(66052)` returns the trigger |
| TEE machine | `0xB33E5CF59e3ce1D58427B9F4E23d0444c128D3D7` | `GCP_AMD_SEV`, status 2, code hash `0xe9ab7410…` |
| FXRP/WC2FLR pool | [`0xafcA1C5DfF08b3B8Bacb7721fb8189d2D8E7C3DB`](https://coston2-explorer.flare.network/address/0xafcA1C5DfF08b3B8Bacb7721fb8189d2D8E7C3DB) | ours, fee tier 3000, thin |
| keeper identity | `0xF0533D37F7ed8d1C45A87Bb35750DA4665bd6D9E` | gas only, holds no authority |
| extension owner | `0x38d58d1BEA8FF21fd8397494f17F64A99bcF8E83` | deployer, extension governance signer |

Bring-up costs on this deployment: `setExtensionId` 81,640 gas, `setTrimmy` 26,751, `commitTrigger`
68,257, `provision` 156,063, `requestEvaluation` 314,468, `acceptVerdict` 97,079. An earlier
deployment measured `setExtensionId` at 64,474.

Execution costs, all measured on chain: plain vault path 383,451 gas, `PRIVATE` path 517,962
([`0x233df51b`](https://coston2-explorer.flare.network/tx/0x233df51b6d536438fd96fa78e1e655ba8c7f25465da4c012187990353d329d66)),
keeper-run vault path 476,842, swap path 930,919 and 844,049. A first `PRIVATE` attempt
([`0x486c9122`](https://coston2-explorer.flare.network/tx/0x486c91227d73e0067f3dd7a0a0fae6b65bc12c6d621cd786df76ed063657df6b))
consumed 523,240 gas and ran out after emitting `Executed`, so `eth_estimateGas` is not a safe limit
on this path and the keeper sends an explicit one.

## Superseded `Trimmy` deployments

| address | what was wrong |
| --- | --- |
| `0xf73a2aF06B315adAA1afe2C1A6C1A6933d8A6554` | M-1: `latchedPrice` and `triggerValue` were `uint64`, but the FXRP to WC2FLR relative price is ~1.7e20, a 9.34x overflow. The slippage floor saturated to ~10.7% of oracle fair value while reporting 50 bips. Regression: [`M1Verify.t.sol`](https://github.com/Immadominion/trimmy/blob/main/contracts/test/M1Verify.t.sol), 7 tests |
| `0xeaF2eA3924D5337B2Dd22ae7BFCACEdAc3D913D5` | M-1 fixed, M-3 still latent |
| `0x3719bAC08F50eC2E165c3078412987d1a39C6D9C` | M-3 fixed: a second queued redemption orphaned the first bucket, and a stranger's push-claim could strand the payout. Regression: [`M3Regression.t.sol`](https://github.com/Immadominion/trimmy/blob/main/contracts/test/M3Regression.t.sol), 4 tests. No `PRIVATE` support |
| `0xf9475Ec998AA2F79c7AbecC01497679bd607269c` | predates `PRIVATE`: `confidentialTrigger()` reverts. NEEDS-VERIFICATION: the ledger records no specific defect for this one |
| `0x6c74bC1154D32839A0900686450a9e2930c7bb46` | first `PRIVATE`-capable build, paired with a trigger that pinned one immutable `teeAddress` and was never backed by a real enclave |
| `0xa995226C200C3785Ea8243C253F6ff7fcDBEc59F` | enclave bring-up, extension 66040. `ruleCount()` is 0. NEEDS-VERIFICATION: no defect recorded |
| `0x0b3200222275F3c7B543e54D85A7acF373a9670f` | enclave bring-up, extension 66041. `ruleCount()` is 0. NEEDS-VERIFICATION: no defect recorded |
| `0xAD5BfAedA2014c1dC0ACCBA88A212d9Be7d1895f` | enclave bring-up, extension 66050. `ruleCount()` is 0. NEEDS-VERIFICATION: no defect recorded |
| `0x9C7876df68B1220D87D2462de8791f13d4F4D452` | paired with the trigger carrying the caller-supplied-price `requestEvaluation`. **Do not arm a `PRIVATE` rule against it** |

## Superseded `TrimmyConfidentialTrigger` deployments

| address | extension | what was wrong |
| --- | --- | --- |
| `0xaBB8139fFB90FFD229594FbF5d5E6c4EE3910A97` | 66031 | `teeAddress` is immutable and set to the deployer `0x38d58d1B…`, not an enclave. A TEE generates its identity keypair on boot, so its signing address cannot exist at construction time. The design was replaced by asking the registry |
| `0x5A9176E70A3dCb014a6E04f6Cddaaca44DC4eF80` | 66040 | bring-up. NEEDS-VERIFICATION: no defect recorded |
| `0xFA6bF4cCA728B717aaAc42043274C5827d575C5D` | 66041 | bring-up. NEEDS-VERIFICATION: no defect recorded |
| `0xA1cfe8fB965b11DE6ae2939B52e0F0d05d1BB7c3` | 66050 | bring-up, still the registered sender for 66050. NEEDS-VERIFICATION: no defect recorded |
| `0x1121702E4bf66d73b42b8cadf6eEf9c24268fd8D` | 66052 | both closed bypasses: `requestEvaluation(uint256,string,uint64)` took a caller-supplied price, and `acceptVerdict` did not bind a verdict to a request ([`VerdictBinding.t.sol`](https://github.com/Immadominion/trimmy/blob/main/contracts/test/VerdictBinding.t.sol), 8 tests). It still reports `extensionId() = 66052`, but 66052's registered sender is now the current trigger, so it can no longer send instructions |

Extension 66052 was re-pointed rather than re-registered:
`setExtensionContracts(66052, stateVerifier, instructionsSender)` in one transaction
([`0xd1c0f396`](https://coston2-explorer.flare.network/tx/0xd1c0f39657f11a7b750ba41b7d67b5fac53e9a71f0e1e8198a31ea21e96e9b81),
38,875 gas), while the enclave kept `EXTENSION_ID=66052` and its machine registration untouched.

## TEE machines

| address | platform | status | notes |
| --- | --- | --- | --- |
| `0xB33E5CF59e3ce1D58427B9F4E23d0444c128D3D7` | `GCP_AMD_SEV` | 2 | current. `n2d-standard-2`, AMD SEV, Confidential Space, `us-central1-b`. Only the first four bytes of its code hash (`0xe9ab7410`) are published |
| `0xf5430C468Cde44226DdFfa705419ccD903f1bCD1` | `GCP_AMD_SEV` | 4 | superseded v0.2.0 image, code hash `0x95810e434ddb5d4ceb2a1a989aea42a6916f9adedb735f947924e51bcf50a1bd`. Its container was gone but the registry row stayed ACTIVE, so `getRandomTeeIds` drew roughly half of all instructions into it and lost them, fee paid. Retired with `disableCodeHashPlatforms` ([`0xcbc190a5`](https://coston2-explorer.flare.network/tx/0xcbc190a5ecc1b460ff99cf6cd63a612a7850a5ac7aa558c2fbc535ecb9ca662b), 129,790 gas), after which 10 of 10 draws routed to the live machine |

## Infrastructure this depends on

`ContractRegistry` `0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019` is the only hardcoded address in the
system; `FtsoV2`, `WNat` and the asset manager are resolved through it at runtime.

`FlareTeeManager` `0x1a9C4A0f9D76c0b1D91d22E24E573a9b377618aE` is one diamond serving both the
extension registry and the machine registry. **It is not in `ContractRegistry`**: `FlareTeeManager`,
`TeeExtensionRegistry` and `TeeMachineRegistry` all resolve to `address(0)` there. It is passed as a
deploy-time argument instead, and
[`DeployConfidential.s.sol`](https://github.com/Immadominion/trimmy/blob/main/contracts/script/DeployConfidential.s.sol) probes both interfaces
before deploying against it.

| what | address |
| --- | --- |
| `FtsoV2` | `0xC4e9c78EA53db782E28f28Fdf80BaF59336B304d` |
| FXRP (`FTestXRP`, 6 dp) | `0x0b6A3645c240605887a5532109323A3E12273dc7` |
| WNat (`WC2FLR`, 18 dp) | `0xC67DCE33D7A8efA5FfEB961899C73fe01bCe9273` |
| SwapRouter (V3, venue 0) | `0xe2B3aE21461c4ad3415210630EA210e9F53CCEBc` |
| `TESTearnXRP` (ERC-4626, venue 1) | `0x9E63a5D282F2fBb7DcE822B98e363b2719D28319` |
| V3 factory behind the pool | `0x9788c2f246486884ef1F3Da9782674E9b259Cc63` |
| canonical `MasterAccountController` | `0x434936d47503353f06750Db1A444DBDC5F0AD37c` |
| `PoolSeeder` harness | `0x3D82474D6F1fd002B78E5D109B612aF7C1aDE9b4` |

**The pool is ours and it is thin.** Coston2 had no FXRP pool at all: 5 factories by 4 counter-tokens
by 4 fee tiers, all 80 `getPool` calls returned `address(0)`. So the FXRP/WC2FLR pool was created and
seeded for this submission. Read on 2026-08-11 it holds 0.807006 FXRP and 133.728846069346589882
WC2FLR at tick 327741, liquidity 412,567,935,903,071. A 0.01 FXRP sell filled at 38 bips; a 0.05 sell was
refused three times while the pool sat 36.6 bips below the oracle, then filled at 5.6 bips once it was
re-centred. A testnet pool has no arbitrageurs, so re-centre it against FTSO before expecting a swap
to fill.

Two further limits worth stating here. Trimmy runs its own arming executor, because the public one
ignored the `0xFE` Smart Accounts branch on both attempts, including one offering the full
`executorFeeUBA` of 100,000. And the vault venues have no synchronous exit, so a vault-exit rule is
two-phase.

## Check this page against the chain

```bash
export R=https://coston2-api.flare.network/ext/C/rpc
export T=0x19F81AAB43f7a26B0659754b70179aDcAF43ef7C
export G=0x02EA709e2278EACDbA00D4A88caA604E3b35293b
export M=0x1a9C4A0f9D76c0b1D91d22E24E573a9b377618aE
export TEE=0xB33E5CF59e3ce1D58427B9F4E23d0444c128D3D7

cast call $G "extensionId()(uint256)"                          --rpc-url $R  # 66052
cast call $G "trimmy()(address)"                               --rpc-url $R  # $T
cast call $T "confidentialTrigger()(address)"                  --rpc-url $R  # $G
cast call $M "getTeeExtensionInstructionsSender(uint256)(address)" 66052 --rpc-url $R  # $G
cast call $M "getTeeMachineStatus(address)(uint8)"     $TEE     --rpc-url $R  # 2
cast call $G "isAuthorisedTee(address)(bool)"          $TEE     --rpc-url $R  # true
cast call $G "isAuthorisedTee(address)(bool)" 0xf5430C468Cde44226DdFfa705419ccD903f1bCD1 \
                                                               --rpc-url $R  # false
cast call $M "getTeeMachineWithAttestationData(address)((address,address,string,bytes32,bytes32))" \
             $TEE                                              --rpc-url $R  # platform GCP_AMD_SEV
cast call $T "tokenCount()(uint256)"                           --rpc-url $R  # 2
cast call $T "venueCount()(uint256)"                           --rpc-url $R  # 2
cast call 0xafcA1C5DfF08b3B8Bacb7721fb8189d2D8E7C3DB "liquidity()(uint128)" --rpc-url $R
```

Read at 2026-08-11. Chain state drifts, so re-run rather than trusting the comments.
Full deployment ledger with the command behind every figure:
[`docs/GROUND-TRUTH.md`](https://github.com/Immadominion/trimmy/blob/main/docs/GROUND-TRUTH.md).
