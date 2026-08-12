---
title: Rule types
summary: The four triggers and three actions a rule can be built from, what each one is for, and which of them are genuinely new.
order: 3
---

Every rule is two choices: what Trimmy watches (the trigger) and what it does when the condition is met (the action). Both are fixed for the life of the rule. If you have not armed anything yet, read [Start here](/docs/start-here/) first.

## The four triggers

| Trigger | What it does | When you would want it | Genuinely new? |
| --- | --- | --- | --- |
| Price below | Fires when the price of the token you are selling, measured in the token you are buying, falls to your threshold | A standing stop for XRP with nobody watching it and nobody holding your keys | Yes. The XRPL's own documentation states that the ledger does not natively represent market orders or stop orders, and a native `StopOrder` amendment is still an open discussion |
| Price above | The same test, upward | Taking profit at a level you set once, or laddering out | Yes, for the same reason |
| Schedule | Fires every N seconds, minimum 60 | Buying or depositing a fixed amount on a cadence, without reopening anything | **No.** XRPL Escrow has done non-custodial time locks through `FinishAfter` for years |
| Private | Fires when a threshold held inside an enclave is met. The chain holds only a commitment to that number | When publishing your stop price is itself the risk, because a visible stop tells every observer when a large sell arrives | The privacy is new. The trust model is weaker: see below |

### Schedule is not a new capability

An XRPL escrow with `FinishAfter` already releases funds non-custodially at a time you choose. What a scheduled rule adds is that the money then does something (a swap or a vault deposit), and whoever executes it is paid from the rule's own fee, so nobody has to be online when it comes due.

### The price triggers are two-legged

Trimmy never compares one oracle read against a dollar figure. Both legs are read fresh from FTSO, sell feed against buy feed, so your threshold keeps its meaning whatever the counter token is worth. A single-leg comparison would assume the other side is pegged to a dollar. This is why the arming page asks for a price in FLR per XRP.

Both feeds are age checked on every execution. A stale feed, a future-dated feed and an unpriceable pair all revert. Nothing falls back to a guess.

### Private rules are not trustless

A private rule needs one enclave to be running, and its operator can censor it by declining to act. The other three triggers are permissionless: anyone can execute them, and every bound is re-derived on chain from the stored rule and a fresh oracle read. The two are not equally trustless. How it works and what is still unpublished are covered in [Private rules](/docs/private-rules/).

## The three actions

| Action | What happens | Status on Coston2 |
| --- | --- | --- |
| Swap | Sells one part into the allowlisted router. The route comes from the allowlisted pair and fee tier, so nobody can substitute one. The price floor comes from FTSO, not the venue | Live. A 0.01 FXRP sell cost 38 bips, and a 0.05 FXRP sell cost 5.6 bips once the pool was re-centred |
| Deposit to a vault | Deposits one part into the allowlisted ERC-4626 vault, and the shares go to your account | Live. Shares matched the vault's own `previewDeposit` exactly and landed with the rule's account, not the caller |
| Withdraw from a vault | Two phases. Executing queues the redemption, and a separate permissionless `claim` settles it | Implemented and tested, not armable on the live deployment: see below |

### Why a vault exit takes two steps

All three FXRP vaults measured on Coston2 report `maxWithdraw` and `maxRedeem` of zero. They are request-and-claim queues, so no vault exit settles in one transaction. Trimmy uses one rule with two permissionless entry points instead of asking you to re-arm. The vault files the request under a day index, so the earliest claim is the UTC midnight after the vault's own lag.

One limit, stated up front: an exit rule has to sell the vault's share token, and the live Coston2 deployment allowlists FXRP and WC2FLR only. On that deployment an exit rule cannot be armed.

### The swap venue is ours and it is thin

Coston2 had no FXRP pool at all, measured across 80 combinations of factory, counter-token and fee tier. We deployed and seeded one with 0.305637 FXRP and 50 WC2FLR. A 0.05 FXRP sell was refused three times while the pool sat 36.6 bips below the oracle. That is the floor doing its job: a thin or stale venue produces a refusal, never a bad fill, and the refusal costs no gas.

## Bounds that apply to every combination

| Bound | Value |
| --- | --- |
| Maximum slippage | 50 bips |
| Maximum protocol fee | 50 bips |
| Minimum schedule interval | 60 seconds |
| Maximum rule lifetime | 365 days |
| Price latch decay window | 1 hour |

The latch matters if your rule runs in parts. The first part to fire latches its price, and later parts are floored against it, so a partial exit does not chase the market down. It decays back to the live price over an hour, so a rule that latched at a local high is not stuck for the rest of its life.

Any trigger can be paired with any action, as long as the token pair and venue are on the contract's allowlist. That pairing, the exact allowance, the budget and the expiry are the whole mandate. An agent can compose one and cannot exceed it.
