---
title: Use cases
summary: Six things a standing rule is good for, each anchored to a product that exists today, including one that already runs on the same rails Trimmy uses.
order: 2
---

A Trimmy rule is a small primitive: money that can be told what to do later, without being handed over now. This page is what that is good for, anchored to products that exist rather than to hypotheticals.

**Nothing on this page is a partnership, an integration, or an endorsement.** No product named here has any relationship with Trimmy, and none of them has been asked. Everything below is read off public documentation and public announcements, dated, so you can check it. Where a product already does part of what a rule would do, that is said plainly rather than hidden.

## The one that already exists

In late February 2026, Flare and [Xaman](https://xaman.app/) shipped a one-click DeFi vault for XRP as an xApp inside the wallet, [Flare XRPFi Yield](https://xaman.app/blog/flare), built on Flare Smart Accounts and FAssets. An XRPL account signs once, a Flare Smart Account it controls holds the position, and the user keeps self-custody throughout.

That matters here for two reasons, and the first one is uncomfortable.

**It proves the rails, and it is not Trimmy's idea.** The claim that an XRPL account can drive a contract on Flare without giving up custody is not a thing Trimmy is asking anyone to take on faith. A production wallet with millions of users shipped it six months ago, on the same Smart Accounts and the same FAssets that Trimmy arms rules through. If you doubt the model, that is the thing to look at, not us.

**What it does not do is repeat, and it does not wait.** One click, one deposit, now. There is no *deposit a little every week*, no *only if the price falls to my number*, and no bound that says *at most twelve times and never after the 30th*. Signing once to move money once is a different product from signing once to authorise a rule that keeps its own limits for a month.

That difference is the whole of Trimmy. A rule is the standing version of the transaction that product already makes.

## Six shapes

### For wallets: limit orders without becoming an exchange

**Anchored to:** [Sologenic DEX](https://www.sologenic.com/ecosystem/sologenic-decentralized-exchange), which trades XRPL assets against the ledger's own order book and its XLS-30 AMM, and [Xaman Swap](https://xaman.app/), which routes swaps natively on the ledger.

Both execute a swap you ask for now. Neither offers a standing stop, because the XRP Ledger does not natively represent one: a native stop order amendment is still an open discussion, not a shipped feature. A wallet that wants *sell if it drops to 150* has to either watch the market itself and hold a key to act, or send its users somewhere custodial.

With a rule it does neither. The wallet composes the 42-byte memo, the user signs an ordinary payment from their own account, and the standing order lives on Flare as a contract with the amount, the count, the expiry and the price band already fixed. The wallet never holds a balance and never holds a key, so it does not acquire the obligations that come with either.

**Built on:** the [arming memo layout](/docs/arming/), and price rules from [Rule types](/docs/rule-types/).

### For agents: a mandate an assistant cannot exceed

**Anchored to:** any assistant that speaks the Model Context Protocol. Trimmy ships an MCP server over stdio with four tools, and every one of them is read-only.

The reason assistants do not act on money is not that they are bad at deciding. It is that the only lever available to them is a key, and a key is all or nothing. Handing one to a chat window means handing over everything the key can reach, forever, on the strength of a system prompt.

A rule inverts that. An assistant can list what is armed, describe any rule in plain language, check that an address is well formed, and compose a new rule. What it produces is a payment for a person to sign, so the worst it can do is suggest. It cannot sign, cannot send, and refuses outright when asked to handle a private threshold, because a threshold that reaches an agent is a threshold that has left the enclave.

**Built on:** `trimmy_list_rules`, `trimmy_describe_rule`, `trimmy_check_address`, `trimmy_compose_rule`.

### For treasuries: payroll that converts itself

**Anchored to:** any business holding XRP against costs it settles in something else.

The manual version is somebody with a calendar reminder and a spreadsheet, converting a fixed amount every Friday, which is both a job nobody wants and a single point of failure when that person is on leave. The custodial version is an exchange account with an API key, which is a different risk wearing a suit.

A scheduled rule is approved once by whoever is allowed to approve it, and then bounded: this much each run, this many runs, stop on this date. Anyone can execute it and is paid from the rule's own fee, so nothing depends on a particular machine being awake.

**Built on:** scheduled rules, minimum cadence 60 seconds, with a per-run cap and a hard expiry.

### For merchants: a floor price on money already taken

**Anchored to:** any XRPL payment processor settling to a merchant who thinks in another currency.

The exposure between accepting XRP and converting it is real and nobody wants to staff it. A price rule sets the rate below which the margin stops working. If the market gets there, the conversion happens without anyone watching a chart. If it never does, nothing moves, and at no point was anything escrowed or deposited anywhere.

Two legs are read fresh from FTSO on every check, sell feed against buy feed, so the threshold keeps its meaning whatever the counter asset is worth. A stale feed reverts rather than guesses.

**Built on:** price rules against FTSO feeds, with the slippage band in [Fees, limits and security](/docs/fees-limits-security/).

### For funds: an entry price that stays a trade secret

**Anchored to:** anyone whose published stop is itself the risk.

A visible threshold tells every observer when a large sell arrives. On a public chain, an automated strategy publishes its own plan as the price of being automated, and copy traders get the entry before the fill.

A private rule holds the number inside a hardware enclave. The chain stores a commitment to it, the enclave signs a yes or no against a price the contract re-derives itself, and the rule never learns the value. Read [Private rules](/docs/private-rules/) before relying on this: it needs one enclave to be running, its operator can censor it by declining to act, and that is a weaker trust model than the other three triggers, which are permissionless.

**Built on:** private rules, threshold held in a TEE, commitment on chain.

### For savers: a deposit habit with nothing to remember

**Anchored to:** the Flare vault ecosystem the XRPFi Yield xApp already reaches, and the ERC-4626 vaults on Flare that a rule can deposit into directly.

The one-click version needs a click. The rule version needs a signature, once, and then puts a little in every week until the date it stops. There is no subscription to cancel, no tab to leave open, and no app that has to survive a phone upgrade for the plan to keep working. Shares go to the account the rule belongs to, not to whoever executed it.

**Built on:** vault rules against an allowlisted ERC-4626 vault, with a hard expiry.

## What a rule is not good for

Worth saying, because a primitive that claims to fit everything fits nothing.

- **Anything needing sub-minute reaction.** The scheduled cadence floors at 60 seconds and execution is permissionless, so a rule fires when somebody executes it and the condition holds, not on the tick. This is not a trading engine.
- **Anything needing discretion.** A rule cannot change its mind, read news, or size a position differently on the day. Every bound is fixed when it is armed and nothing can widen it afterwards, including us. That is the safety property, and it is also the limitation.
- **Anything where the venue matters more than the price.** The route comes from an allowlisted pair and fee tier, so nobody can substitute one, and that also means nobody can pick a better one.
- **Private rules, if you need censorship resistance.** See above. One enclave, one operator, one way to be stopped.

## Next

- [Rule types](/docs/rule-types/) for what each trigger and action actually does, including which of them are genuinely new.
- [Arming](/docs/arming/) for the memo layout a wallet would build.
- [Live rules](/rules/) for every rule armed right now, read from the chain in your own browser.
