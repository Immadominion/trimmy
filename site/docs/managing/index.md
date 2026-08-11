---
title: Managing and cancelling rules
summary: How to find your rules, how one ends by itself, and the three ways to stop one early: cancel, an epoch bump, or a guardian.
order: 5
---

You armed a rule and closed the browser. It keeps working. Here is how to look at one, how it stops on its own, and how to stop it early.

## Find your account, then your rules

Rules are stored against your personal account, not your XRPL address. Derive the account from the canonical controller, then read the rules:

```bash
R=https://coston2-api.flare.network/ext/C/rpc
CTRL=0x434936d47503353f06750Db1A444DBDC5F0AD37c
TRIMMY=0x19F81AAB43f7a26B0659754b70179aDcAF43ef7C

cast call $CTRL "getPersonalAccount(string)(address)" "rYourXRPLAddress" --rpc-url $R
cast call $TRIMMY "ruleCount()(uint256)" --rpc-url $R
```

Trimmy keeps every rule in one global array. `ruleCount()` gives its length and `ruleAt(id)` returns one rule. There is no per-account index, so finding yours means reading rules and comparing the first field, `account`, with your personal account. `ruleCount()` returned `4` when this page was written, so a scan is quick today. It will not stay quick.

The fields worth reading are `active`, `spent` against `totalSellAmount`, `expiry` and `epoch`. [Fees, limits and security](/docs/fees-limits-security/) explains the fee and slippage fields.

## How a rule ends without you

**It spends its total.** Each execution adds the amount actually pulled to `spent`. When `spent` reaches `totalSellAmount`, `active` flips to false in that same transaction and the rule can never run again.

**Its expiry passes.** Every execution path reverts `RuleExpired` once the block clock is past `expiry`. Expiry is fixed at arm time and can be at most 365 days out (`MAX_RULE_LIFETIME`, read live as 31,536,000 seconds).

Rule 1 on the live deployment is the first kind. It reads back `totalSellAmount` 1,000,000, `spent` 1,000,000, `active` false, `keeperFeePaid` 9,400 of a 9,400 budget. It closed itself and paid the keeper what it owed. A finished rule is not deleted: it stays in the array as a permanent read-only record.

## Cancel one rule

`cancel(ruleId)` sets `active` to false. Two addresses may call it: the rule's own account, and the guardian that account has appointed. Nobody else, including us.

Cancelling does not touch the ERC-20 allowance your arming payment granted. That allowance is held by your personal account against the Trimmy contract, not against a rule, so it survives. A dead rule cannot draw on it, because `execute` refuses an inactive rule before it pulls anything, but another live rule on the same account can, capped by its own `totalSellAmount`. To take it back, set the allowance to zero in a call from the personal account.

## Cancel everything in one write

`cancelAll(account)` adds one to `epochOf[account]`. Every rule records the epoch it was armed under, and every execution path rejects a rule whose stored epoch is not current. One storage write kills every rule on the account, whether that is one rule or fifty. Rules armed afterwards carry the new epoch and are unaffected.

| how a rule ends | who acts | scope |
| --- | --- | --- |
| `spent` reaches `totalSellAmount` | nobody | that rule |
| `expiry` passes | nobody | that rule |
| `cancel(ruleId)` | account or guardian | that rule |
| `cancelAll(account)` | account or guardian | every rule on the account |

## Guardians, and why the panic button needs one

`setGuardian(address)` names one address that may cancel on your account's behalf. A guardian can call `cancel` and `cancelAll` and nothing else: it cannot arm, move your tokens or change your allowance.

It matters because of how your account is driven. `PersonalAccount.executeUserOp` is `onlyController`, measured on chain, so a call from your account has to arrive as an XRPL payment plus an attestation round trip: minutes, not seconds. Plimsoll measured direct-mint settlement over 30 payments at p50 131 s and p95 170 s, on the branch the public executor does act on. Trimmy uses the `0xFE` Smart Accounts branch, which the public executor ignored even with a full fee offered, so we run our own executor for it. A guardian is an ordinary EVM address, so its cancel lands in one block.

Neither the command-line arming tool nor the web page builds a `setGuardian`, `cancel` or `cancelAll` batch today. They build the approve-and-arm batch only. Both calls are live on the contract, but you compose them yourself.

## claimableAt and claimPeriod

These belong to vault-exit rules, which settle in two steps because no FXRP vault on Coston2 has a synchronous exit: `maxWithdraw` and `maxRedeem` read zero on all three measured. `execute` queues the redemption and writes `claimableAt` and `claimPeriod`; a separate permissionless `claim(ruleId)` collects the assets for `rule.account`.

The wait is longer than the vault's `lagDuration` suggests. The vault files the request under a day-index bucket and its claim check requires the current day index to be strictly greater, so the earliest claim is the next UTC midnight: up to about 24 hours, and a further day if the request lands within `lagDuration` of midnight. `TESTearnXRP` reports a `lagDuration` of 300 seconds, which is not the number that gates the claim.

Cancelling a rule with a redemption pending does not strand the money. `claim` deliberately skips the liveness check `execute` applies, so a cancelled or epoch-bumped rule still pays its assets to `rule.account`, with keeper and protocol fees zeroed.

One limit, plainly: no vault-exit rule can be armed against the current deployment. The token allowlist holds FXRP and WC2FLR only, and a vault-exit rule must sell the vault's share token, so `arm` reverts `VaultAssetMismatch`. Simulated against the live contract on 2026-08-11.
