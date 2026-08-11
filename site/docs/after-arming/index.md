---
title: What happens after you arm
summary: The timeline from a settled XRPL payment to a rule that executes itself, with measured times and who does each step.
order: 4
---

Your payment is sent. From here nothing needs you: you can close the tab, and no support desk is
waiting on you. Four things happen, and only the first is yours.

| # | Step | Who does it | Measured on Coston2 |
| --- | --- | --- | --- |
| 1 | The payment validates on XRPL | your wallet | `tesSUCCESS`, ledger 19771685, 2026-08-09 run |
| 2 | The Flare Data Connector attests it | Flare's data providers, on request | proof on the 5th poll in one run, the 8th in another, 20 s apart |
| 3 | Smart Accounts runs the committed batch | an executor | one transaction, 742,307 and 747,096 gas in two runs |
| 4 | The rule executes when its condition is met | anyone | 383,451 gas per run, 517,962 for a private rule |

The numbers here come from two complete runs on chain, 2026-08-07 and 2026-08-09.

## The attestation

Flare does not read the XRP Ledger directly. Someone requests an attestation of your transaction id
from the Flare Data Connector, paying a small fee (1,000 wei in the first run). The request joins a
voting round, and the proof can be fetched once that round finalises.

Measured: the proof arrived on the fifth poll in one run and the eighth in another, 20 seconds
apart. Rounds are usually under two minutes on Coston2, but one took over fifteen. Expect minutes,
not seconds.

## Your batch runs on your account

With the proof in hand the executor calls `executeDirectMintingWithData`, passing both the proof and
the user operation your 42-byte memo commits to. FAssets mints FXRP into the personal account
derived from your XRPL address, and that account runs the two calls you reviewed: the exact
allowance, then the rule.

State before and after, from the 2026-08-07 run:

| | before | after |
| --- | ---: | ---: |
| rules on the contract | 3 | 4 |
| next instruction number | 0 | 1 |
| your account's FXRP | 3.6 | 8.4 |
| allowance to Trimmy | 0 | 1,009,400, exact |

If the memo does not commit to that pre-image, the mint reverts. The executor is a courier: it can
delay your payment, not change it.

## Somebody has to execute the arming, and today it is us

The public Coston2 executor did not pick up either of our arming payments, at 600 seconds each. One
offered it nothing, which explains itself. The other offered the full 100,000 UBA delivery fee and
was still ignored, because the public executor does not act on the `0xFE` Smart Accounts branch that
Trimmy uses. Measured, not assumed, so Trimmy runs its own executor for this step.

The executor is run against your transaction id. Nothing in the repository watches the XRP Ledger
for arming payments on its own.

On the other branch the same executor minted 30 of 30 payments carrying a full fee, median 131
seconds. That is the closest thing to a normal expectation, and it is not our branch.

Until an executor acts, your payment sits at the Core Vault. It does not fail, and nothing happens.
One of our early payments, which carried a zero fee, is still sitting there.

## Then the rule waits, and anyone can run it

The rule is now on chain and `execute()` is permissionless. The contract re-derives every bound at
execution time from the stored rule and a fresh oracle read, so the caller is trusted with nothing
and appears once, as the recipient of the flat fee the rule carries: 9,400 units of the result asset
per run by default, against a measured minimum viable fee of about 4,698 units at 383,451 gas. You
never pay gas.

Demonstrated with a keeper identity that is neither the user nor the deployer: it started with zero,
found the rule, executed it, and ended with exactly the 9,400 it was owed. The proceeds went to the
rule's account, not the caller's.

Timing: our keeper sweeps every 15 seconds by default, and the floor is one block, 1 to 3 seconds
measured. It reads the same feed the contract re-checks, so it has no information advantage. A price
move shorter than one block cannot be caught, and near a threshold the feed oscillates across it, so
failed attempts are ordinary. Call it one-block conditional execution against the FTSO with an
oracle-enforced floor. It is not stop-loss protection.

A scheduled rule is eligible the moment it is armed: the first run happens as soon as somebody runs
it, and the interval governs the gap after that. A private rule needs its threshold provisioned to
the enclave first, and the enclave's operator can decline to issue a verdict, which is why that
trigger is the weakest of the four. See [Rule types](/docs/rule-types/).

## Nobody is on call, including you

After the payment there is nothing to keep open. The rule ends on its own: when its budget is spent,
when it expires, or when you cancel it. Cancelling one rule, or every rule at once with the epoch
bump, is a Flare transaction; from XRPL it costs another payment and the same wait, so set the
expiry you want when you [arm](/docs/arming/).

All of this is Coston2 testnet. Nothing has run on Flare mainnet.
