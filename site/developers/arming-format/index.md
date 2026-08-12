---
title: The arming payment format
summary: Byte-exact wire spec for the 42 byte 0xFE memo, the nine-field PackedUserOperation pre-image it commits to, and the batch calldata inside it.
order: 3
---

One XRPL payment arms a Trimmy rule. Two artefacts decide what that payment does, and only one of them is on the ledger.

| artefact | where it travels | size |
| --- | --- | --- |
| memo | XRPL `Payment.Memos[0].Memo.MemoData` | 42 bytes |
| user operation pre-image | off chain, handed to an executor | 1,440 bytes for the reference batch below |
| commitment | inside the memo | 32 bytes |

The memo commits to the pre-image and to nothing else. A user signing in Xaman sees 42 bytes, 32 of which are a hash, so nothing visible at signing time describes where the money goes. Everything below is the measured layout, taken from [`web/lib/arming.js`](https://github.com/Immadominion/trimmy/blob/main/web/lib/arming.js), [`arming/bin/arm.dart`](https://github.com/Immadominion/trimmy/blob/main/arming/bin/arm.dart), and a committed fixture from a payment that settled: XRPL transaction `384FE782BE520662EA579AB67A2232DE5BD650A8A0E2ACB75C2B8C80514B778A`, ledger 19771685, which armed rule 1 on Trimmy `0x19F81AAB43f7a26B0659754b70179aDcAF43ef7C`.

Coston2 testnet only. Nothing here has been exercised on Flare mainnet.

## The 42 byte memo

<figure class="doc-fig">
  <img src="/assets/diagrams/memo-layout.svg" alt="The 42 byte memo: opcode, wallet id, executor fee, and a 32 byte commitment." loading="lazy">
  <figcaption>Forty-two bytes. Thirty-two of them are a hash, which is why the decoder exists.</figcaption>
</figure>

| offset | length | field | encoding |
| ---: | ---: | --- | --- |
| 0 | 1 | opcode | `0xFE`, Smart Accounts custom instruction |
| 1 | 1 | `walletId` | single byte, `0` in every payment sent so far |
| 2 | 8 | `executorFeeUBA` | `uint64` big endian, FXRP base units (6 decimals) |
| 10 | 32 | commitment | `keccak256(abi.encode(PackedUserOperation))` |

Any other length is not a short memo, it is a different instruction. The reference payment's memo is `FE0000000000000186A0EBBE0EE068F4BA0A9E39E41FDCA1DBF26864AADDB0AA42E59371EB67B7CE96CC`: opcode `FE`, walletId `00`, fee `00000000000186A0` (100,000 UBA = 0.1 XRP), then commitment `0xebbe0ee068f4ba0a9e39e41fdca1dbf26864aaddb0aa42e59371eb67b7ce96cc`.

The fee lives in the memo header, not in the batch, so two payments differing only in fee share a pre-image and differ in memo. That is the one field you can change without re-deriving the commitment, and it is pinned by a test.

**A zero `executorFeeUBA` does not fail.** It produces a payment nobody executes, which sits at the Core Vault while the XRP has already left the sender's control. Both encoders refuse it rather than warning. `getDirectMintingExecutorFeeUBA` read 100,000 on Coston2.

## The XRPL envelope

[`arming/xrpl/send.mjs`](https://github.com/Immadominion/trimmy/blob/main/arming/xrpl/send.mjs) sets `MemoData` only, with no `MemoType` and no `MemoFormat`, and refuses a memo that is not 84 hex characters starting `FE`.

Two envelope facts matter as much as the bytes:

- **No `DestinationTag`.** A registered tag takes precedence over the memo, the memo is not read at all, and the payment credits the tag holder.
- **Amount floor 200,001 drops.** Measured against the Coston2 asset manager, `getDirectMintingMinimumFeeUBA` and `getDirectMintingExecutorFeeUBA` are 100,000 each. Anything from 0.1 to 0.2 XRP inclusive delivers the recipient exactly zero, with no event and no revert. The protocol's own `paymentTooSmall` flag compares against the first fee only, so it is false across that whole band. Destination is the Core Vault, `rDhpmiPq4BVBDWMVdSrmkgt8thKyRzGV1p`.

## PackedUserOperation: nine fields, not ten

The wire format is the nine-field EIP-4337 v0.7 `PackedUserOperation`. A widely-circulated TypeScript example lists ten. Getting this wrong does not fail loudly. It produces a commitment that never matches the batch, and the mint reverts with `CustomInstructionHashMismatch(bytes32,bytes32)`, selector `0xad79273d`.

`abi.encode` of a single dynamic tuple emits a **leading `0x20` offset word** before the struct. Omitting it shifts every subsequent offset and changes the hash. The 1,440 byte reference pre-image ([fixture](https://github.com/Immadominion/trimmy/blob/main/web/test/fixtures/settled-payment-384FE782.userop.hex)) reads:

| offset | length | field | value in the fixture |
| ---: | ---: | --- | --- |
| 0 | 32 | offset to the struct | `0x20` |
| 32 | 32 | `sender` | `0x07a76b5c3d03f5bff4cb3e043b1d17a1b40920bf` |
| 64 | 32 | `nonce` | `1` |
| 96 | 32 | offset to `initCode` | `0x120` (288) |
| 128 | 32 | offset to `callData` | `0x140` (320) |
| 160 | 32 | `accountGasLimits` | zero word, a value, not a pointer |
| 192 | 32 | `preVerificationGas` | `0` |
| 224 | 32 | `gasFees` | zero word, a value, not a pointer |
| 256 | 32 | offset to `paymasterAndData` | `0x540` (1344) |
| 288 | 32 | offset to `signature` | `0x560` (1376) |
| 320 | 32 | `initCode` | length `0` |
| 352 | 1024 | `callData` | length 964, padded to 992 |
| 1376 | 32 | `paymasterAndData` | length `0` |
| 1408 | 32 | `signature` | length `0` |

Tail offsets are relative to the start of the struct, so they are 32 lower than the file positions above. A decoder that reads `callData` from slot 4 gets the zero-filled `accountGasLimits`, resolves an offset of 0 and walks off the end. [`web/lib/decode.js`](https://github.com/Immadominion/trimmy/blob/main/web/lib/decode.js) names that trap in place.

`sender` and `nonce` are not free choices. `MasterAccountController.getPersonalAccount(string)` **derives** an address from whatever XRPL string it is handed and never fails, so a mistyped address resolves to a different account rather than erroring. `getNonce(address)` lives on the controller, not on the personal account. Two controllers are live on Coston2 with identical 18-function ABIs; the canonical one is `0x434936d47503353f06750Db1A444DBDC5F0AD37c`. Arming against the other sets an allowance on an empty account, permanently.

## The batch calldata

`callData` is `executeUserOp((address,uint256,bytes)[])`, selector `0x2b2ee783`, derived in the JavaScript encoder and hardcoded in the Dart one so a typo in either shows up as a test failure.

| offset in `callData` | length | meaning |
| ---: | ---: | --- |
| 0 | 4 | selector `2b2ee783` |
| 4 | 32 | offset to the array, `0x20` |
| 36 | 32 | array length, `2` |
| 68 | 32 | offset to element 0, `0x40` |
| 100 | 32 | offset to element 1, `0x120` |
| 132 | 224 | element 0 |
| 356 | 608 | element 1 |

Element offsets are relative to the start of the array body (the word after the length), not to the start of the calldata. Each element is a dynamic tuple: address word, `value` word, a fixed `0x60` offset to `data` within the tuple, then a length word and the padded bytes.

The two calls in an arming batch are:

1. `approve(address,uint256)`, selector `095ea7b3`, 68 bytes of data. FXRP `0x0b6A3645c240605887a5532109323A3E12273dc7`, spender Trimmy, amount `1009400` in the fixture. Sized to the rule's whole life, never unlimited.
2. `arm(...)`, selector `cc0c55f4`, 452 bytes: one selector plus fourteen static words.

## The `arm` struct

`arm((uint8,uint8,uint8,uint8,uint8,uint128,uint128,uint128,uint128,uint64,uint16,uint16,uint128,uint128))`. All members are static, so each occupies one word in declaration order with no offset words.

| word | field | notes |
| ---: | --- | --- |
| 0 | `sellTokenId` | index into the constructor-fixed token table |
| 1 | `buyTokenId` | |
| 2 | `verb` | 0 SWAP, 1 DEPOSIT_VAULT, 2 EXIT_VAULT |
| 3 | `venueId` | fixed at deploy time, no mutable registry |
| 4 | `trigger` | 0 PRICE_BELOW, 1 PRICE_ABOVE, 2 SCHEDULE, 3 PRIVATE |
| 5 | `totalSellAmount` | the hard budget for the rule's whole life |
| 6 | `partSellAmount` | runs = `ceilDiv(total, part)` |
| 7 | `minOutAbsolute` | floor on one part, not on the total |
| 8 | `triggerValue` | buy-token base units per one whole sell token, or interval seconds for SCHEDULE, or `0` for PRIVATE |
| 9 | `expiry` | unix seconds |
| 10 | `slippageBips` | `MAX_SLIPPAGE_BIPS` is 50 |
| 11 | `protocolFeeBips` | `MAX_PROTOCOL_FEE_BIPS` is 50 |
| 12 | `keeperFeeFlat` | per execution, in buy-token units |
| 13 | `keeperFeeBudget` | lifetime cap; `arm` refuses a budget that cannot fund the rule's own executions |

This is the shape of the bound. An exact allowance, one verb, one venue, one token pair fixed at deploy time, a budget, an expiry, and an epoch that `cancelAll` bumps to kill every rule at once. An agent can compose these fourteen words; it cannot exceed them.

`triggerValue` became `uint128` in the M-1 fix because a relative price for the FXRP/WC2FLR pair exceeds `uint64`. **That widening changed the selector from `c33d4cc3` to `cc0c55f4`.** The docstring above `_encodeArm` in `arm.dart` still shows the old `uint64` signature; the `sig` constant beneath it is the correct one.

## Verifying a memo against a pre-image

The check is: hash the pre-image, compare bytes 10 to 41 of the memo, then decode the batch. Do it in a program that did not build the payment, because a compromised front end ships its own decoder and will describe a hostile batch in comforting language.

```bash
cd arming
dart run bin/decode.dart --file out/userop-preimage.hex --memo-file out/memo.hex
```

[`arming/bin/decode.dart`](https://github.com/Immadominion/trimmy/blob/main/arming/bin/decode.dart) takes no network access, re-derives the commitment, prints the calls in English, and calls `exit(1)` on a mismatch, a memo that is not 42 bytes, an opcode that is not `0xFE`, an undecodable batch, or a selector it does not recognise. It will do this for a payment produced by anyone, including an attacker. Its browser equivalent is `decodeArmingPayment` in `web/lib/decode.js`, which reads only the memo and the pre-image and never the form the user filled in.

The two encoders are pinned against each other by [`web/test/arming.test.mjs`](https://github.com/Immadominion/trimmy/blob/main/web/test/arming.test.mjs), 10 tests, all passing when run on 2026-08-11 with `node --test test/arming.test.mjs`. The fixture is the settled payment above, not a synthetic vector.

## What goes wrong, in order of cost

| mistake | symptom |
| --- | --- |
| ten-field struct, or no leading `0x20` | commitment never matches, `CustomInstructionHashMismatch` |
| `executorFeeUBA = 0` | nothing reverts, nothing executes, XRP sits at the Core Vault |
| amount in the 0.1 to 0.2 XRP band | mint delivers exactly zero, silently |
| `DestinationTag` present | memo ignored, funds credited to the tag holder |
| wrong controller | allowance set on an empty personal account |
| one wrong character in the XRPL address | a different personal account is derived, no error |

Every one of these produces a valid, irreversible XRPL payment. That is why both builders refuse rather than warn.
