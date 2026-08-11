---
title: Documentation
summary: How to use Trimmy, from the first payment to cancelling a rule you no longer want.
order: 0
---

These pages are for someone using Trimmy. If you are integrating with it, auditing it, or want the
wire formats and the transaction ledger, read the [developer reference](/developers/) instead.

## Start with these

| Page | What it answers |
| --- | --- |
| [Start here](/docs/start-here/) | What Trimmy is, what you need in your wallet, and the shape of the whole journey |
| [Rule types](/docs/rule-types/) | The four triggers and three actions, and which of them are genuinely new |
| [Arming a rule](/docs/arming/) | Step by step, including the address check that only works offline |
| [What happens after you arm](/docs/after-arming/) | Attestation, execution, and how long each step takes |

## Then, before you commit anything

| Page | What it answers |
| --- | --- |
| [Managing and cancelling rules](/docs/managing/) | How a rule ends by itself, and the three ways to stop one early |
| [Private rules](/docs/private-rules/) | Keeping your trigger price off the chain, and the trust you take on for it |
| [Fees, limits and security](/docs/fees-limits-security/) | The exact allowance, the keeper fee, the price bounds, and what the contract cannot do |
| [Where Trimmy runs today](/docs/availability/) | The honest status: what is incomplete, measured rather than estimated |

## Two things worth knowing before you read anything else

**Trimmy runs on Flare Coston2 testnet.** Nothing here has run on Flare mainnet, and the XRP in
these flows is testnet XRP worth nothing. Every page says so again, because it is the kind of fact
that a reader skims past once and then acts on.

**The wallet-less part is not the new part.** Flare Smart Accounts already lets an XRPL payment
drive an EVM call with no EVM wallet and no gas token, and Trimmy is built on it. What Trimmy adds
is what the payment leaves behind: a rule that persists, keeps evaluating for days, and carries the
fee that pays whoever executes it.

## If you would rather read the source

Every page here has a markdown twin at the same address with `index.md` on the end, so
[/docs/start-here/index.md](/docs/start-here/index.md) is the same page without the markup. The
whole site is also available as a single file at [/llms-full.txt](/llms-full.txt).
