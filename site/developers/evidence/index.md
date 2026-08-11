---
title: Evidence
summary: A transaction-by-transaction ledger of everything Trimmy has done on Flare Coston2, including the refusals that cost no gas.
order: 7
---

## Scope

Everything here is on Flare **Coston2** (chain ID 114). Nothing has run on Flare mainnet. Each
figure is recorded in
[`docs/GROUND-TRUTH.md`](https://github.com/Immadominion/trimmy/blob/main/docs/GROUND-TRUTH.md)
with the command that produced it. Hashes ending in `…` are truncated there; the full 32 bytes are
unrecorded.

## The XRPL armed path

One XRPL payment. No EVM wallet, no FLR held. Deployment
`Trimmy 0x19F81AAB43f7a26B0659754b70179aDcAF43ef7C`, 2026-08-09.

| Step | Evidence | Proves |
| --- | --- | --- |
| Payment built | memo `FE0000000000000186A0EBBE0E…`, 42 bytes, `executorFeeUBA = 100000` | the `0xFE` Smart Accounts branch |
| Decoded offline | `decode.dart` re-derived the commitment from the pre-image | the producer is not trusted |
| XRPL payment | `384FE782BE520662EA579AB67A2232DE5BD650A8A0E2ACB75C2B8C80514B778A`, `tesSUCCESS`, ledger 19771685 | the only signature |
| FDC attestation | round 1420803, proof after 8 polls | provable on Flare |
| Smart Accounts | `executeDirectMintingWithData`, tx `0xd504f3f3…`, 747,096 gas | mint plus batch, one call |
| Rule armed | rule 1, `account = 0x07a76b5c…` | derived from the XRPL address, not the gas payer |
| Keeper execution | tx `0xd88f7cac…`, 476,842 gas, sender `0xF0533D37…` | not the user, not the deployer |
| Fee split | keeper vault shares 65,800 → 75,200 | the 9,400 `keeperFeeFlat`, in balances not events |

An earlier run put keeper and user on one address: the split showed only in the event log.

The same path ran on 2026-08-07 on an earlier deployment, untruncated: XRPL
`E41504D3356C15789D4B6602F0F2E8B151F04FFAA5BBF2E3F71640C92B59B6E0` (ledger 19698983), FDC
`0x0a3f05f72f9425f93ff64290d862ffc6498e82e0dfb7a6f7e57448ea035a82d9` (round 1418293), execution
`0x86d54bd6821b7598cde03d68f0e1642da1b4714a52e91e445396095bc12cf6cc` (742,307 gas), keeper
`0xa74e9fc270bef95449e5821c0403c26b28c00b095d0e7b7a25bc2496e18a37b1`. The allowance it set was
**1,009,400**: exact, never unlimited.

**The public executor never acted.** Two arming payments, both `tesSUCCESS`, both watched 600 s:
`C122663D…326104` at `executorFeeUBA = 0`, and `E41504D3…59B6E0` at `executorFeeUBA = 100,000`.
Neither was picked up: a full fee was offered and the `0xFE` branch still ignored, so we run our own
executor.

## Execution against a vault that is not ours

TESTearnXRP `0x9E63a5D282F2fBb7DcE822B98e363b2719D28319`, a third-party vault, share price
**1.05917**. Trimmy `0xf73a2af0…`, 2026-08-07, the M-1 vulnerable build (see provenance).

| Step | Tx |
| --- | --- |
| `approve`, exact size | `0x7b88ac308da099e52874f8f4b1cc26ebf9df6c11b6b140bb12dfab878bed4a81` |
| `arm` | `0x6d791f9e02e74f7a65e843dcb155b6f27a9aa374b5e74681ed4f4b32d9ed68f0` |
| `execute`, permissionless | `0xf682b1ae694c0d0a7996acc64f8d9cc06cc095155bd5333a53370881001ec11a` |

FXRP 23.150001 → 22.150001. Vault shares 0 → **944,133**, exactly `previewDeposit(1 FXRP)`,
credited to `rule.account` and not the caller.

A separate keeper `0xF0533D37F7ed8d1C45A87Bb35750DA4665bd6D9E`, funded with gas and given no
authority, executed rule 2 in
`0x50ef27fd67464424b23687b740df65d2aa7d729d8b3df16deb314173f244a720`: user shares 1,888,266 →
2,822,999, keeper shares 0 → 9,400. `PersonalAccount.executeUserOp` is `onlyController`: selector
`0x2b2ee783` reverts `OnlyController()` `0x59907813` for anyone else, so a leaked keeper key drives
nothing.

## The live swaps

Pool `0xafcA1C5DfF08b3B8Bacb7721fb8189d2D8E7C3DB`, FXRP/WC2FLR, fee tier 3000. **It is ours and it
is thin**: 0.305637 FXRP and 49.999999996 WC2FLR at `L = 155,310,565,707,002`. Coston2 had no FXRP
pool beforehand (80 `getPool` calls, 5 factories x 4 counter-tokens x 4 fee tiers, all
`address(0)`).

| # | Sells | Outcome |
| --- | --- | --- |
| 1 | 0.01 FXRP | executed, tx `0x7edff76c…`, received 1.702666 WC2FLR, **38 bips** |
| 2 | 0.05 FXRP | refused, `Too little received`, **no gas** |
| 3 | 0.05 FXRP | refused after liquidity was raised 2.66x, **no gas** |
| 4 | 0.05 FXRP | executed, tx `0xc0e9dd88…`, received 8.536698 WC2FLR, **5.6 bips** |

Row 1's oracle fair value was `0.01 x 170.9222 = 1.709222 WC2FLR`. The model predicted 38.4 bips
beforehand; the chain returned 38. The tick moved 327738 → 327721 and the pool's FXRP balance rose
305,637 → 315,637, exactly the sale.

## The three refusals

The refused rows are the best evidence here.

**They cost nothing.** Each died in the keeper's `eth_call` pre-simulation, so the keeper signed
none of them. A rule that cannot execute costs an RPC round trip.

**They refuted our own first diagnosis.** We assumed depth was binding, deepened the pool 2.66x from
`1.553e14` to `4.126e14`, and were refused again. Computing the floor exactly showed the pool at
170.6357 against an oracle of 171.2618: **36.6 bips below**, from row 1's own impact plus an FTSO
move. With the 30-bip pool fee on top, no trade size fit inside the declared 50 bips. Staleness was
binding, not depth, and a testnet pool has no arbitrageurs. Re-centring by hand (tx `0x38b77fff…`)
restored the peg and the same rule filled at 170.734 against 170.83.

The ledger counts three refusals across rows 2 and 3, then one fill at 5.6 bips once the venue was
priced honestly. A stale venue gives a refusal, never a bad fill.

## The confidential path

| Step | Evidence |
| --- | --- |
| Arm | rule 0 on `0x19F81AAB…`, `trigger = 3`, **`triggerValue = 0`** |
| Commit | `commitmentOf(0) = 0xeca87739…` |
| Provision | enclave returned `{"ruleId":0,"commitment":"0xeca87739…","stored":true}`, recomputing the commitment itself |
| Request | `pendingAction(0,0) = 0xc2cf1bea…`, price from FTSO, not the caller |
| Verdict | `{"ruleId":0,"fire":true,"commitment":"0xeca87739…","nonce":0,"issuedAt":1786297877}`, no threshold, no bounds |
| Accept | tx `0x9a2af814…`, status 1 |
| Execute | tx `0x233df51b…`, `spent = 1000000`, keeper paid 9,400, rule closed |

The threshold `1100000` appears nowhere on chain.

The enclave is a real `GCP_AMD_SEV` machine, `0xB33E5CF59e3ce1D58427B9F4E23d0444c128D3D7`, not the
simulated sentinel `0x194844cf417dde867073e5ab7199fa4d21fd82b5dbe2bdea8b3d7fc18d10fdc2` shared by
254 of Coston2's 268 active TEE machines. **Only the first four bytes of its code hash are published
(`0xe9ab7410…`). The full 32 bytes are not.**

PRIVATE costs **517,962 gas** against **383,451** for the plain path. The first attempt
(`0x486c9122…`) ran out of gas after emitting `Executed`, so `eth_estimateGas` is unsafe here; the
keeper sends an explicit limit.

Two free refusals against the fixed trigger, both `cast call`: a genuine enclave signature over a
genuine `fire` verdict is rejected with `NoEvaluationRequested(0, 7)` (`0xe6cf311f`) because nobody
asked it, and the caller-supplied-price entry point `requestEvaluation(uint256,string,uint64)` no
longer exists. Regression:
[`VerdictBinding.t.sol`](https://github.com/Immadominion/trimmy/blob/main/contracts/test/VerdictBinding.t.sol),
8 tests.

**PRIVATE's trust model is strictly weaker than the other three triggers.** It needs an enclave
running, and its operator can censor a rule by declining to act. Not trustless.

## Provenance

CREATE transactions and constructor arguments, from
[`contracts/broadcast/`](https://github.com/Immadominion/trimmy/tree/main/contracts/broadcast).

| Contract | Address | CREATE tx |
| --- | --- | --- |
| `Trimmy` | `0x19F81AAB43f7a26B0659754b70179aDcAF43ef7C` | `0x3a0c889aa9ba135f0cebc5d802eb01eb0b6e6e713980eb2b0f2caa12f3fc179a` |
| `TrimmyConfidentialTrigger` | `0x02EA709e2278EACDbA00D4A88caA604E3b35293b` | `0xb0f3ef76b8cd05bc793da39f45da25b945bc86987e074bb80969e563ec8bb782` |
| Pool `initialize(uint160)` | `0xafcA1C5DfF08b3B8Bacb7721fb8189d2D8E7C3DB` | `0xdc41179dbe8c05a9ef7efe35b32e136fbf3d253ce9f8c68a8b15101f37ff7119` |

```text
tokens_  [(0x0b6A3645c240605887a5532109323A3E12273dc7,
           0x015852502f55534400000000000000000000000000, 6),   // FXRP, XRP/USD
          (0xC67DCE33D7A8efA5FfEB961899C73fe01bCe9273,
           0x01464c522f55534400000000000000000000000000, 18)]  // WC2FLR, FLR/USD
venues_  [(0xe2B3aE21461c4ad3415210630EA210e9F53CCEBc, 0, 3000),  // SwapRouter
          (0x9E63a5D282F2fBb7DcE822B98e363b2719D28319, 1, 0)]     // TESTearnXRP
maxFeedAge_            64
protocolFeeRecipient_  0x38d58d1BEA8FF21fd8397494f17F64A99bcF8E83
confidentialTrigger_   0x02EA709e2278EACDbA00D4A88caA604E3b35293b
```

The whole action surface: two tokens, two venues, written once in
[`src/Trimmy.sol`](https://github.com/Immadominion/trimmy/blob/main/contracts/src/Trimmy.sol)'s
constructor. No setter, no owner, no upgrade path.

Superseded deployments, left on chain:

| Address | Status |
| --- | --- |
| `0xf73a2af06b315adaa1afe2c1a6c1a6933d8a6554` | M-1 vulnerable, do not use |
| `0xeaF2eA3924D5337B2Dd22ae7BFCACEdAc3D913D5` | M-1 fixed, M-3 latent |
| `0x3719bAC08F50eC2E165c3078412987d1a39C6D9C` | M-1 and M-3 fixed |
| `0x6c74bC1154D32839A0900686450a9e2930c7bb46` | simulated TEE |
| `0x9c7876df…`, trigger `0x1121702e…` | vulnerable `requestEvaluation`, do not arm PRIVATE against it |

Non-upgradeable, so every fix is a redeploy: `arm()`'s selector moved from `c33d4cc3` to `cc0c55f4`
when the price fields widened. Regressions for the two money bugs:
[`M1Verify.t.sol`](https://github.com/Immadominion/trimmy/blob/main/contracts/test/M1Verify.t.sol)
(7 tests) and
[`M3Regression.t.sol`](https://github.com/Immadominion/trimmy/blob/main/contracts/test/M3Regression.t.sol)
(4 tests), with 66 core tests green.
[`test/research/`](https://github.com/Immadominion/trimmy/tree/main/contracts/test/research)
holds exploits, many written to fail, so no pass ratio is quoted.
