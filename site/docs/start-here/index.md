---
title: Start here
summary: What Trimmy is, what you need in your XRPL wallet before you begin, and the shape of the journey from one payment to a rule that runs itself.
order: 1
---

Trimmy turns one XRPL payment into a standing rule that keeps watching the market after you close the tab. When your condition is met, anyone can execute the rule, because the rule carries the fee that pays for its own execution.

**Trimmy runs on Flare Coston2 testnet only.** Nothing has run on Flare mainnet. The XRP in this flow is XRPL testnet XRP and is worth nothing. Everything else behaves as it would with real money.

## What you need before you begin

- An XRPL testnet account, in any wallet that can send a Payment with a memo.
- Testnet XRP in that account.
- Nothing else. No EVM wallet, no FLR for gas, no extension, no account with us.

The wallet-less part is not new. Flare Smart Accounts already lets an XRPL payment drive an EVM call with no EVM wallet and no gas token, and Trimmy is built on Smart Accounts. What Trimmy adds is what the payment leaves behind.

### How much XRP

The arming page itemises the payment for you: what the rule can spend, plus the FAssets minting fee (0.1 XRP), plus the executor fee (0.1 XRP, read from the live asset manager), rounded up so the figure is typeable.

There is a floor, and getting it wrong is silent. Anything from 0.1 to 0.2 XRP inclusive delivers you exactly zero: no revert, no event, the transaction succeeds and every party except you gets paid. The true floor is the minimum minting fee plus the executor fee plus one drop, which is 0.2 XRP and 1 drop. The protocol's own "payment too small" flag reads false across that whole dead zone, so the page computes the outcome instead of trusting the flag.

## What a rule is

A rule is a bounded mandate. Every bound is fixed at the moment you arm it, and no code path changes it afterwards. There is no owner, no admin, no proxy and no pause on the contract.

| Fixed at arming | What it bounds |
| --- | --- |
| Verb | One action only: swap, deposit to a vault, or withdraw from a vault |
| Trigger | One condition: price below, price above, schedule, or private |
| Token pair | Which token is sold and which is received, chosen from an allowlist written into the contract at deploy time |
| Venue | The single router or vault it may touch |
| Total budget | The most the rule can ever spend, across its whole life |
| Amount each time | The size of one part |
| Expiry | At most 365 days |
| Slippage | At most 50 bips |

The allowance your account grants is exact, not unlimited. In the live end to end run it was 1,009,400 units, sized to that one rule, and the proceeds landed with the rule's own account rather than with whoever executed it.

That is also why an AI agent can hold a Trimmy rule safely. Agent wallets give an agent bounded permission enforced by a vendor's infrastructure. A Trimmy rule is the same bound enforced by a contract, and the personal account's `executeUserOp` is `onlyController`, so an agent that composes a rule and is then compromised extracts nothing.

## The shape of the journey

1. **Build the payment.** The arming page builds it in your browser, then decodes the 42 byte memo back from the bytes themselves and tells you in English what signing it authorises. No server sees your rule.
2. **Send one XRPL payment.** Three fields matter: destination, amount, and the memo. Do not add a destination tag. A registered tag overrides the memo entirely and credits the tag holder instead.
3. **Wait for settlement.** The Flare Data Connector has to attest your payment before the rule exists, so arming is not instant. In our live runs the proof arrived after 5 and 8 polls. The closest measured figure we have is 30 direct mints at p50 131 seconds and p95 170 seconds, but that was the public executor on a different branch, so treat it as an order of magnitude, not a promise.
4. **The rule is armed.** It sits on chain, re-evaluating, until it is spent, expired or cancelled.
5. **Someone executes it.** Execution is permissionless. The keeper fee comes out of the proceeds and the remainder goes to your account. There is no code path that sends it anywhere else.

We run our own executor for step 3. The public one did not pick up either of our arming payments, including one that offered a full 100,000 UBA executor fee. That is measured, not assumed: the public executor does not appear to act on the `0xFE` Smart Accounts branch at all.

## What is not built yet

- **One tap signing.** Xaman's hex deep link carries TrustSet transactions only, so a memo-bearing sign request needs their Platform API and a server-held key. The page gives you the three fields to enter in your own wallet instead.
- **A cancel button.** Cancelling is a contract call from your personal account, which today means another XRPL payment and another settlement wait. The contract also supports a guardian who can cancel everything for you in one call.
- **A deep swap market.** The FXRP pool the swap rules trade against is ours and it is thin. Coston2 had no FXRP pool at all.

Next: [Rule types](/docs/rule-types/) covers the four triggers and the three actions, and says which of them are genuinely new.
