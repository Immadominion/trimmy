# Trimmy: AI-friendly automation for XRP

> Markdown twin of https://trimmy.xyz/, same content, no markup.

---

Set the condition. Keep your keys.

# AI-FRIENDLY AUTOMATION FOR XRP

Set a rule for your XRP. Trimmy keeps watch and acts when your conditions are met, without taking custody or asking you to stay online.

[Try Trimmy ↗](/arm/)
[Read the docs](/docs/start-here/)

SET ONCE↗STAYS READY

Example rule

## Sell if XRP falls

Watching

▶
Play example

XRP→FLR

When
1 XRP reaches 150 FLR or less

Then
Exchange 0.01 XRP for FLR

Total limit0.12 XRP

Each time0.01 XRP

At most12 times

EndsIn 7 days

Price limitWithin 0.5% of the checked rate

Running feePaid from each result

•
Watching the priceWaiting for the condition you set.

✓ Your keys stay with you. Anything unspent stays yours.

NO CUSTODY

Built for XRP on Flare

- XRPL

- Flare

- FAssets

- FTSO

- Confidential Compute

## WE WANTED ONE RULE. EVERYTHING ELSE WANTED THE KEYS.

Trimmy started as something we wanted for ourselves. Set a price for our XRP, close the laptop, and have it act without us. We went looking for that and found five holes where the product should have been.

-
Gap 01

### XRP settles in seconds, then forgets you.

A payment on the XRP Ledger is one shot and final. There is no if it falls to 150 and no every Friday. A standing instruction has to live somewhere, and every somewhere on offer was a company holding the coins.

So the rule lives on Flare. It is a contract anyone can read, armed by one ordinary XRPL payment that you sign from your own account.

-
Gap 02

### Automation was priced in keys.

Every service that could do this wanted an API key with withdrawal rights, or a deposit into an account we did not control. The thing that goes wrong is not the rule misfiring. It is the operator leaving.

So Trimmy holds nothing. No key, no balance, no customer ledger. What it may do is written into the rule itself: amount each time, how many times, an expiry, and a price band. Anything unspent was never ours.

-
Gap 03

### An AI can tell you what to do, and then stop.

Assistants got good at reading a market and stayed useless at acting on one, because the only way to let software act is to give it a key, and a key is all or nothing. Nobody sensible hands that to a chat window.

So the mandate is the rule, not the key. Trimmy ships an MCP server. An assistant can read what is armed and compose a new rule in plain language. It cannot sign, cannot send, and refuses outright to touch a private threshold.

-
Gap 04

### Your threshold is your strategy.

Put a sell price on a public chain and you have published your plan. Anyone can read it, price around it, or simply copy it. Automation that leaks the number is not automation you can use at size.

So the number never reaches the chain. A private rule keeps it inside a hardware enclave. The chain stores a hash. The rule receives a signed yes or no and never learns the value.

-
Gap 05

### The tools we needed did not exist, so we wrote those first.

Flare publishes developer guides for JavaScript, React, Python, Rust and Go. None for Dart, which is what we build in. And nothing described how to put an instruction inside an XRPL memo safely, which meant guessing at the bytes that decide where money goes on a payment that cannot be recalled.

So Trimmy is the third thing we built, not the first. Both of the others are open source and stand on their own.

[Sibling project
Flare Dart
Typed bindings for Flare's own contracts, so FTSO feeds, FDC attestations, FAssets and Smart Accounts are an import rather than a week of hand-rolled ABIs.
flaredart.trimmy.xyz ↗](https://flaredart.trimmy.xyz/)
[Sibling project
Plimsoll
Know what your XRPL payment will do on Flare before you sign it. It computes the outcome from live chain state and refuses the ones that lose money.
plimsoll.trimmy.xyz ↗](https://plimsoll.trimmy.xyz/)

## RULES FOR THE MOMENTS YOU CAN’T WAIT FOR.

Price moves, scheduled actions, and private conditions. Each has the amount, runs, and expiry you approve.

←
1 / 3

→

### Price rules

Choose the market condition and exact amount. Trimmy acts only when the number reaches your rule.

### Scheduled rules

Choose the cadence once. The next run stays available without asking you to reopen the app.

### Private rules

Keep the threshold inside confidential compute. The rule receives a signed result, not your number.

## ONE DECISION. A RULE THAT STAYS.

Review every boundary, leave the rule watching, and let it act only when the condition and limits agree.

Review
Watching
Act

01 / Review

### Know exactly what the rule can do.

Condition, action, total amount, amount each time, runs, expiry, and price limit are visible before approval.

CLEAR FIRST

Review rule

Sell if XRP fallsReady to approve
Ready

When
1 XRP ≤ 150 FLR

Then
Exchange 0.01 XRP for FLR

Maximum
0.12 XRP across 12 runs

Expiry
In 7 days

✓ Anything unspent stays yours.

02 / Watching

### Close the tab. Keep the rule.

The standing rule remains available while Trimmy checks the approved condition. No open browser session is required.

STILL WATCHING

Rule status

Rule activeWatching your price
12 runs left

✓ No open tab required.

03 / Act

### Act only inside your limits.

The action becomes available only when the condition is met and every amount, run, expiry, and oracle boundary still passes.

WITHIN LIMITS

Execution

Condition met0.01 XRP exchanged for FLR

Runs left
11

Total left
0.11 XRP

✓ Oracle and permission checks passed.

Private rules

## PRIVATE NUMBER. VERIFIABLE ANSWER.

Your threshold stays inside confidential compute. The rule receives a signed yes-or-no result and never needs the number itself.

[Read the trust model ↗](https://github.com/Immadominion/trimmy/tree/main/docs)

Private condition••••••

Confidential computeValue stays sealed

Verified resultCondition met

## POWERFUL AUTOMATION. NARROW PERMISSION.

What Trimmy may do is bounded by the rule, not remembered by an operator.

01

### No keys

Your secret never enters Trimmy. Approval happens from your XRP account.

02

### No custody

Trimmy does not take possession of your funds or maintain a customer balance.

03

### Exact limits

Amount, repetitions, expiry, slippage, and acceptable execution are bounded on-chain.

[Review the evidence](https://github.com/Immadominion/trimmy/blob/main/docs/GROUND-TRUTH.md)
[Inspect the code ↗](https://github.com/Immadominion/trimmy)

## A RULE IS A PRIMITIVE. HERE IS WHAT TO BUILD.

Trimmy is one product on top of a small idea: money that can be told what to do later, without being handed over now. Everything below is the same primitive pointed somewhere else.

For wallets

### Limit orders without becoming an exchange.

A self-custody XRP wallet adds sell if it drops and buy every payday without holding a balance, running a matching engine, or taking on the licence that comes with either. The wallet builds the memo. The user signs a normal payment.

Built on the arming memo layout, 42 bytes

For agents

### An assistant with a mandate it cannot exceed.

Point an AI agent at the MCP server and it can read every rule the user has armed, explain what one would do, and compose a new one in plain language. Signing stays with the person, so the worst an agent can do is suggest.

Built on four read-only MCP tools over stdio

For treasuries

### Payroll that converts itself on schedule.

A business holding XRP against costs it pays in something else stops timing the market by hand. Convert a fixed amount on a fixed cadence, bounded by a total and an expiry, and let the finance lead approve it once instead of every Friday.

Built on scheduled rules with a per-run cap

For merchants

### A floor price on money you already took.

Accept XRP at the till and set the rate below which the margin stops working. If it gets there, the conversion happens without anyone watching a chart, and if it never does, nothing moves and nothing was ever escrowed.

Built on price rules against FTSO feeds

For funds

### An entry price that stays a trade secret.

The number that defines a strategy is the one thing a public chain will happily publish. Keep it inside confidential compute instead, and let followers see the fill after it happens rather than the plan before it does.

Built on private rules, threshold held in a TEE

For savers

### A deposit habit with nothing to remember.

Put a little into the yield vault every week, bounded by an amount, a count, and a date it stops. No subscription, no open tab, no app that has to survive a phone upgrade for the plan to keep working.

Built on vault rules with a hard expiry

Every one of these is the same three moving parts: a rule you arm, a condition Flare checks, and limits nothing can widen after the fact.

[Read the developer docs](/developers/)
[See these in detail ↗](/docs/use-cases/)

## SET IT UP ONCE. GET ON WITH YOUR DAY.

Choose a condition, set the boundaries, and review the payment before approving anything.

- 1 Choose a rule

- 2 Set the limits

- 3 Review and approve

Start with a rule

### Pick your starting rule.

You’ll set the exact amount, limits, and schedule next.

Choose a rule

Price dropSell below a level↘

Timed exchangeExchange over time↻

Vault depositDeposit over time↗

Private priceAdvanced setup●

Continue to setup ↗

Rule preview

Price ruleSell if XRP falls
Example

When1 XRP reaches 150 FLR or less

ThenExchange 0.01 XRP for FLR

Each time
0.01 XRP

At most
12 times

Ends
In 7 days

✓Review before approvalYou’ll review the full rule before anything moves.

## SET THE RULE. GET BACK TO YOUR DAY.

Your rule can keep watching. You don’t have to.

[Try Trimmy ↗](/arm/?preset=below)
[Read the docs](/docs/start-here/)
