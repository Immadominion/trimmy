---
title: Private rules
summary: How a PRIVATE rule keeps your trigger price off the chain, and the exact trust you take on in exchange.
order: 6
---

## The number you do not want to publish

You want a rule that sells if XRP falls to a certain price. On a `PRICE_BELOW` rule that price is
stored as `triggerValue`, where anyone can read it. It announces the exact price at which a large,
price-insensitive sell will arrive. Centralised venues do not publish their stop books, and this is
the reason.

A `PRIVATE` rule is the same rule with the number withheld. Everything else stays public: the
amount, the venue, the token pair, the budget, the expiry. The other three triggers are in
[Rule types](/docs/rule-types/).

## What the chain holds instead

A commitment: a hash of your number that proves you fixed it in advance without revealing it. The
rule stores `triggerValue = 0`, and the trigger contract stores
`keccak256(threshold ‖ 0x1f ‖ salt ‖ 0x1f ‖ direction)`.

The salt is a random string of at least 16 characters, and it is what makes the commitment worth
anything: stop prices sit in a small, guessable range, so without one somebody could hash candidates
until one matched.

## Where your number actually lives

In the memory of one enclave: a Google Confidential Space virtual machine on AMD SEV hardware. You
encrypt the threshold to that enclave's public key before it goes anywhere, so what crosses the
chain is ciphertext and the only plaintext copy is inside the machine.

Nothing is written to disk. Enclave memory is volatile, so a restart loses every secret and those
rules stop firing until you provision again. A store that survived a restart would be one we could
read.

## What the enclave answers

When a keeper wants to run your rule, the contract asks the enclave one question. The price in it is
read from FTSO by the contract itself and is never supplied by the caller. An earlier version took
it as an argument, which let a stranger fire another user's rule at an invented price and recover
the secret in about twenty queries. That is fixed, with regression tests.

A real reply:
`{"ruleId":0,"fire":true,"commitment":"0xeca87739…","nonce":0,"issuedAt":1786297877}`. A yes or a
no, the commitment it refers to, a replay-proof nonce, and the time it was formed. No threshold, no
margin, no distance from firing. A distance would leak the number across repeated questions, so the
enclave never computes one. The contract refuses a verdict older than 90 seconds.

| What an observer sees | Public |
| --- | --- |
| The rule, its amount, venue, pair, budget and expiry | yes |
| The commitment, the verdict, and the trade after it | yes |
| Your threshold, and how close the price got | no |

This hides the trigger, not the history. On Coston2, rule 0 was armed with a threshold of
`1100000`, provisioned, evaluated and executed, and that value appears nowhere on chain.

## What you are trusting

The trust model for `PRIVATE` is strictly weaker than the other three triggers. All of it:

- **One enclave, not a quorum. We run it.**
- **Its operator can censor you by declining to act.** A private rule needs a fresh signed verdict,
  so if we stop running the extension, your rule stops firing. `PRICE_BELOW`, `PRICE_ABOVE` and
  `SCHEDULE` are permissionless: anyone can execute them, and every bound is re-derived on chain.
- **There is no on-chain heartbeat.** A silent enclave and a price that never reached your number
  look identical from outside. It is not built.
- **You are trusting AMD SEV and Google's attestation, which we did not build.** The contract
  accepts a verdict only from a live machine registered to this extension and reporting
  `GCP_AMD_SEV`. It rejects `TEST_PLATFORM`, which matters: 254 of 268 active TEE machines on
  Coston2 are simulated, hold the same live status on chain as real hardware, and share one code
  hash constant, so a verdict from one proves nothing about what code ran.
- **The full code hash is not published,** only its first four bytes, `0xe9ab7410…`. Until all 32
  are out, nobody outside can rebuild the image and check the running code against it.

A dishonest verdict is bounded: it only permits the rule to run. Execution re-derives the price
from FTSO, applies the oracle floor and the slippage cap, respects the budget and the expiry, and
pays proceeds to your own account. The worst a lying enclave achieves is firing your rule early, at
a price inside the floor. Cancelling calls `forget`, which asks the enclave to drop your secret, and
you are trusting that it did.

## Arming one today

Provisioning is a command-line step, on Coston2 only
([where Trimmy runs today](/docs/availability/)).

```bash
go run ./cmd/trimmy-private \
  -rule 0 -threshold 1100000 -direction 0 -account 0x07a76b5c…
```

A private execution costs 517,962 gas against 383,451 for the plain path.

## If software is composing the rule

A Trimmy rule is a bounded mandate an agent can compose but cannot exceed: an exact allowance rather
than an unlimited one, one verb, one venue, one token pair fixed at deploy time, a hard budget, an
expiry, and an epoch counter that cancels everything at once. A compromised agent extracts nothing,
because `PersonalAccount.executeUserOp` is `onlyController` and the agent is not the controller.

A private rule adds one thing: the software composing it never learns your price. It handles a
commitment and a ciphertext, and neither reveals the number, so it can pick the venue, size and
schedule without knowing when your rule fires. That holds only if you do the encrypting.
