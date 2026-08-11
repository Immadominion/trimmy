---
title: Fees, limits and security
summary: The exact allowance, the keeper fee, the 50-bip oracle floor, the 64-second feed age, and what the contract can never do to you.
order: 7
---

An XRPL arming payment cannot be recalled. This is what a rule can take from you, and what nothing here can take.

## The allowance is exact

The arming batch is two calls, `approve` then `arm`. The approve is sized to the rule's whole life, to the unit.

```text
allowance = totalSellAmount + keeperFeeBudget
```

The rule that ran end to end on Coston2 sold 1,000,000 UBA of FXRP with a 9,400 UBA keeper budget, so its allowance read back on chain as **1,009,400**. Not unlimited, and there is no second approval in the flow. An allowance belongs to the pair (your account, the Trimmy contract), not to a rule, so cancelling leaves it standing: [Managing and cancelling rules](/docs/managing/) covers clearing it.

## The keeper fee

`execute` is permissionless and pays its caller a flat fee out of the proceeds, so the rule funds its own execution and nobody has to be watching it.

The fee has to beat gas. Measured: `execute()` costs 383,451 gas, which at Coston2's 2125 gwei and an FLR/USD of 0.00594005 is $0.00484, or 4,698 UBA of FXRP. Live rules carry a `keeperFeeFlat` of 9,400 UBA, about twice that. Coston2's gas price is a testnet artefact, not Flare's mainnet market. A `PRIVATE` execution costs more: 517,962 gas measured.

`keeperFeeBudget` is a lifetime cap, never exceeded and never paid beyond the proceeds. `arm` refuses a budget too small to fund the rule's executions, because a rule that runs out of fee stops with months left and a live allowance. A protocol fee follows, capped at 50 bips. Live rules carry 0.

## The floor: two legs, 50 bips

`slippageBips` is capped at 50 (0.5%) by a constant in a contract with no admin. The floor comes from FTSO, never from the venue: `oracleOut × (10,000 − slippageBips) / 10,000`, or `minOutAbsolute` when higher. An AMM quote is a number an attacker can move, so it never sets the floor.

The price behind it is two-legged, sell feed against buy feed. A single-leg read against USD is correct only if the buy token is worth exactly $1, on a chain carrying at least five unrelated tokens called "USDC". A threshold is therefore in buy-token base units per one whole sell token.

The floor is on the **gross** fill, so fees come out afterwards and what lands is lower by that much; a net-bound floor is unsatisfiable, since a flat keeper fee is often a larger share of a small part than the 50-bip band. It also **latches** on the first execution so later parts do not chase the market down, decaying back to live over one hour.

A thin or stale venue gives a refusal, not a bad fill: on our pool a 0.05 FXRP sell was refused three times while the pool sat below the oracle, by 36.6 bips when measured, then filled at 5.6 bips once repriced.

## maxFeedAge is 64 seconds, measured

Read live from the contract: 64. Feed age is `block.timestamp − feedTimestamp` as the contract sees it, sampled over five separated windows and 750 samples: largest per-window p99 34 seconds, global maximum 35 seconds. 64 is roughly twice that.

An earlier deployment carried 120 seconds, chosen before that sampling. A five-minute realised XRP move already exceeds the whole 50-bip band, so every extra second of staleness is extractable. The cost, stated plainly: `maxFeedAge` is immutable and there is no proxy, so an FTSO stall longer than 64 seconds halts every rule until feeds recover.

## No owner, no admin, no proxy

No pause, no rescue. The token and venue allowlists are written once in the constructor: 2 tokens (FXRP, WC2FLR) and 2 venues (a V3 router at the 3000 fee tier, a queued vault). Proceeds have one destination, `rule.account`.

## A mandate software can compose but cannot exceed

Every agentic wallet bounds what an agent may do. What differs is who enforces the bound.

| | agentic wallet | Trimmy rule |
| --- | --- | --- |
| enforced by | the vendor | a contract with no admin |
| spend | a policy | an exact allowance: sell amount plus keeper budget |
| scope | configurable | one verb, one venue, one pair, fixed at arm time |
| stop | ask the vendor | `cancel`, or one epoch bump for every rule |

`PersonalAccount.executeUserOp` carries `onlyController`, measured, so an agent holding a keeper key cannot drive your account and its allowance to Trimmy is zero: a compromised agent extracts zero. With a `PRIVATE` rule it never learns your threshold, which lives in the enclave behind an on-chain commitment.

This is not wallet-lessness, which Smart Accounts and Axelar GMP already give you. What a rule adds is persistence.

## What is not safe yet

- **Coston2 testnet only.** Nothing has run on Flare mainnet. See [Availability](/docs/availability/).
- **The pool is ours and thin.** Coston2 had no FXRP pool at all, measured across all 80 factory/token/fee-tier combinations, so we seeded one: about 0.31 FXRP and 50 WC2FLR within ±5%. A testnet pool has no arbitrageurs, so it drifts from the oracle and stays there.
- **`PRIVATE` is strictly weaker than the other three triggers.** It needs one enclave running, and that operator can censor it by declining to act. It is not trustless.
- **The enclave code hash is only partly published:** four bytes of the machine's 32-byte hash.
