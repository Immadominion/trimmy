---
title: Private triggers and the enclave
summary: How a PRIVATE rule keeps its threshold inside a TEE, what the chain verifies, what has to be trusted, and the two bypasses that were found and closed.
order: 5
---

A `PRIVATE` rule keeps its threshold price out of chain state. The chain holds a commitment, an
enclave holds the number, and the rule cannot fire without a fresh signed verdict from a machine the
TEE registry vouches for. Coston2 only (chain id 114); nothing has run on Flare mainnet. Source:
[`TrimmyConfidentialTrigger.sol`](https://github.com/Immadominion/trimmy/blob/main/contracts/src/TrimmyConfidentialTrigger.sol),
[`extension.go`](https://github.com/Immadominion/trimmy/blob/main/fcc/extension/go/internal/extension/extension.go).

## What runs privately inside the TEE

The enclave is a Go handler in a GCP Confidential Space VM on AMD SEV. It keeps one map, rule id to
`{threshold, commitment, direction, account}`, in process memory: nothing is written to disk, logged,
or returned by any handler. `GET /state` reports counts, never contents.

Three commands under op type `TRIMMY`. The contract's `bytes32` literals and the strings in
[`config.go`](https://github.com/Immadominion/trimmy/blob/main/fcc/extension/go/internal/config/config.go)
must match byte for byte; a mismatch falls through to "unsupported op type", silently.

| command | what the enclave does |
| --- | --- |
| `PROVISION` | ECIES-decrypts the payload via the node's loopback `/decrypt`, stores the secret |
| `EVALUATE` | compares an observed price against the threshold, returns one boolean |
| `FORGET` | deletes the secret, refusing a caller whose account does not match |

`PROVISION` takes `{ruleId, threshold, salt, direction, account}` as JSON with
`DisallowUnknownFields`. The threshold is a decimal string, never a float. It refuses a non-positive
threshold, a salt under 16 characters, a direction other than 0 or 1, an empty account, and an
overwrite by another account. An earlier version read plaintext off the instruction, which would have
published every threshold on chain.

The commitment, literally:

```text
keccak256( decimal(threshold) || 0x1F || salt || 0x1F || byte(direction) )
direction: 0 = below, 1 = above
```

`0x1F` is the ASCII unit separator, so `"1" + "23"` cannot collide with `"12" + "3"`. The direction
byte is inside the hash so a threshold provisioned for below cannot satisfy a rule armed as above.

`EVALUATE` fires when `observed <= threshold` (below) or `observed >= threshold` (above). The response
carries `ruleId`, `fire`, `commitment`, `nonce` and `issuedAt`, and no distance, bounds or margin: a
distance would let repeated queries binary-search the secret. A missing secret is a refusal, and
enclave memory is volatile, so a restart loses every secret. 14 Go tests pin this, including
`TestVerdictLeaksNothingAboutTheThreshold`.

## What is verified or consumed on chain

The trigger is the InstructionSender bound to FCC extension 66052. The registry rejects
`sendInstructions` from any other `msg.sender`.

| function | selector | access |
| --- | --- | --- |
| `commitTrigger(uint256,bytes32)` | `0x5f1ddc2a` | anyone, write-once, records the owner |
| `provision(uint256,bytes)` | `0x4863f523` | rule owner only |
| `requestEvaluation(uint256,uint64)` | `0x654e2eef` | permissionless |
| `acceptVerdict(...)` | `0x8666b696` | permissionless |
| `consumeVerdict(uint256,uint64)` | `0x20531b43` | `onlyTrimmy`, view |
| `isAuthorisedTee(address)` | `0xe35ebda3` | view |

**`requestEvaluation` has no price parameter, and that is the security of the function.** It calls
`Trimmy.currentPrice(ruleId)`, which re-derives the two-legged relative price from the same FTSO feeds
the execution reads, builds `{"ruleId":N,"observedPrice":"P","nonce":K}`, sends it, and records the
returned instruction id in `pendingAction[ruleId][nonce]`. A caller picks only when to ask.

`acceptVerdict` checks, in order: the commitment exists and equals the rule's; the nonce is unused;
`pendingAction[ruleId][nonce]` is non-zero and equals `actionId`; `issuedAt` is not negative, not
older than `MAX_VERDICT_AGE` (90 s), and not more than `MAX_CLOCK_SKEW` (10 s) ahead of the block
clock; the signature recovers to an authorised TEE; and `fire` is true. `_recover` refuses any
signature that is not 65 bytes, and the upper half of the curve order. The signature covers a
domain-separated payload, not the bare result hash, which fails against real node signatures.

```text
resultHash  = keccak256( keccak256(resultData) || actionId || keccak256(submissionTag) || status )
payloadHash = keccak256( abi.encode(bytes32("TEE_ACTION_RESULT"), block.chainid, resultHash) )
digest      = keccak256("\x19Ethereum Signed Message:\n32" || payloadHash)
```

`isAuthorisedTee` requires all three of: the machine serves extension 66052; status is `2`; attested
platform is `bytes32("GCP_AMD_SEV")`. Each read sits in a `try/catch`, because the registry reverts
for an address that was never a machine. Without the platform check a simulated machine passes, and
its code hash is a constant shared by 254 machines.

`Trimmy.execute` calls `consumeVerdict(ruleId, uint64(rule.spent))`, so the nonce advances per
executed part and a verdict cannot be replayed onto a later one. The live verdict for rule 0
([`0x9a2af814`](https://coston2-explorer.flare.network/tx/0x9a2af814704419f6234a3664ac22721f6b355c316bed219326f8a733505b46ef),
97,079 gas) used `submissionTag = "threshold"`, `status = 1`, and an `actionId` equal to the recorded
`pendingAction(0,0)`.

## What trust assumptions exist

**A `PRIVATE` rule's trust model is strictly weaker than the other three triggers, and the code says
so.** `PRICE_BELOW`, `PRICE_ABOVE` and `SCHEDULE` are permissionless and re-derive every bound on
chain from live FTSO. A `PRIVATE` rule's fire decision is asserted by one enclave at a point in time
and no verifier can recompute it.

- **One enclave, and its operator can censor it.** Instructions route through `getRandomTeeIds` over
  the machines the registry holds live for extension 66052. One machine is registered. If its operator
  declines to run, the rule cannot fire. Multi-machine verdicts would be a design change.
- **Staleness is bounded, not eliminated.** 90 s maximum verdict age, 10 s maximum skew ahead.
- **Availability is not durable.** A restart loses every secret and evaluation then refuses.
- **Public attestation evidence is partial.** The platform check is on chain, but the ledger
  publishes only the first four bytes of the machine's code hash (`0xe9ab7410`); read the full
  measurement from the registry yourself. The VM runs `confidential-space-debug`, so its token reports
  `dbgstat: enabled`; a production image would report `disabled`.

What the operator cannot do matters as much. They cannot fire a rule at a price the chain did not
produce, cannot move funds (`PersonalAccount.executeUserOp` is `onlyController`, and proceeds go to
`rule.account`), and cannot exceed the rule's exact allowance, verb, venue, token pair, budget or
expiry, all fixed at arm time. A `PRIVATE` rule is a bounded mandate an agent can compose and cannot
exceed, and the agent never learns the threshold.

## Why this needs confidential compute rather than a normal contract

Contract storage is public. An ordinary rule stores `triggerValue` in the clear, so anyone reading
`ruleAt(id)` knows the price at which a large, price-insensitive sell arrives. The related review
finding (A2) is that the execution floor is a publicly computable target.

The Flare Data Connector cannot substitute. `Web2Json`'s source identifier is `PublicWeb2`: the
request and its headers go on chain and roughly 100 providers each fetch it. That property makes FDC
trustworthy and stops it holding a secret. A commitment alone does not help either: the comparison
needs the plaintext.

Two bypasses were found while driving the first real `PRIVATE` rule. Both are closed.

**The caller supplied the price.** `requestEvaluation(uint256,string,uint64)` (selector `0x987e0204`)
took the observed price as a string. Any stranger could ask "does rule N fire at a price of 1?", read
the genuine signed `fire` verdict off the proxy's public, unauthenticated result endpoint, and push
someone else's rule through `acceptVerdict` at a price its owner never chose. Asked repeatedly, each
verdict is one bit of "is the threshold above or below the number I picked", so roughly twenty queries
binary-search the secret.

**The verdict was unbound.** `acceptVerdict` never checked that a verdict answered an instruction this
contract had sent, so a verdict minted by any other instruction satisfied it, including one an
attacker sent directly. Every other check became decoration.

One root cause: the number the enclave compared against came from the attacker, not the chain. The
fix deleted the price parameter and added the `pendingAction` binding. Pinned by
[`VerdictBinding.t.sol`](https://github.com/Immadominion/trimmy/blob/main/contracts/test/VerdictBinding.t.sol),
8 tests: `test_theEnclaveIsAskedAboutTheChainsPrice`, `test_theQuestionTracksTheChainPrice`,
`test_valueAccounting`, `test_anUnrequestedVerdictIsRefused`,
`test_aVerdictForAnotherInstructionIsRefused`, `test_theAnswerToOurOwnQuestionIsAccepted`,
`test_reAskingInvalidatesTheEarlierAnswer`, `test_requestBeforeBindingIsRefused`. Also
[`ConfidentialTrigger.t.sol`](https://github.com/Immadominion/trimmy/blob/main/contracts/test/ConfidentialTrigger.t.sol)
(11 tests, `test_simulatedPlatformIsRejected` among them) and
[`PrivateTrigger.t.sol`](https://github.com/Immadominion/trimmy/blob/main/contracts/test/PrivateTrigger.t.sol)
(7, including `test_theThresholdIsNotOnChain`).

The binding is checked before the signature, so a verdict nobody asked for is refused whether or not
the enclave really signed it. Against the live contract:

```bash
cast call 0x02EA709e2278EACDbA00D4A88caA604E3b35293b \
  "acceptVerdict(uint256,bool,bytes32,uint64,int64,bytes,bytes32,string,uint8,bytes)" \
  0 true 0xeca87739390ec330326bcb95dfbb5541b2126ada46d3f329b6ce64dcc12c8162 \
  7 1786297877 0x00 0xdead...beef "end" 1 0x00 --rpc-url $R
# reverts 0xe6cf311f... = NoEvaluationRequested(ruleId = 0, nonce = 7)
```
