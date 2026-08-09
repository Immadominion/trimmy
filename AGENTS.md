# AGENTS.md — Trimmy

Operational guidance for anyone, human or agent, working in `trimmy/`.

**This workspace is not the SDK and it is not Plimsoll.** [`../sdk/AGENTS.md`](../sdk/AGENTS.md)
governs `sdk/`; [`../plimsoll/AGENTS.md`](../plimsoll/AGENTS.md) governs `plimsoll/`. Their rules do
not automatically apply here, and vice versa. Trimmy *depends on* both as libraries and never edits
either — a need becomes a change request against that workspace, made deliberately, not an inline
edit.

## What this is

**Conditional execution for XRP.** One XRPL payment arms a rule; the rule then executes itself,
forever, without the user present, without an EVM wallet, and without holding a gas token.

The XRP Ledger natively has no stop orders, no market orders, no leverage and no scheduled or
recurring payments. So an XRPL self-custody holder who wants *any* automation must keep their coins
on a centralized exchange. That is the gap. Flare closes it because Smart Accounts + FAssets + FDC
are the only stack where a non-EVM user holding zero gas token can drive a contract.

Read [`research/01-ARCHITECTURE.md`](research/01-ARCHITECTURE.md) for the design and
[`../docs/2026-08-06-PIVOT-RESEARCH.md`](../docs/2026-08-06-PIVOT-RESEARCH.md) for why this product
and not another.

## Read before writing code

In this order. Skipping them means rediscovering things that are already measured, on chain, today.

1. [`docs/GROUND-TRUTH.md`](docs/GROUND-TRUTH.md) — live measured values. **Check here before
   trusting any number, including numbers in this file.**
2. [`research/01-ARCHITECTURE.md`](research/01-ARCHITECTURE.md) — the corrected design
3. [`research/02-ARCHITECTURE-ATTACK.md`](research/02-ARCHITECTURE-ATTACK.md) — how it fails
4. [`research/00-critique.md`](research/00-critique.md) — what the first research pass got wrong

## Rules that encode real findings

Each of these was paid for with a measurement. Violating one reintroduces a bug we already found.

1. **A keeper can never drive a personal account.** `PersonalAccount.executeUserOp` is
   `onlyController` — it reverts `OnlyController()` (`0x59907813`) for every caller but the
   controller. The *only* durable authorization is an exact-size ERC-20 **allowance** granted inside
   the arming batch. Any design that "re-arms" by submitting a new user operation is impossible.
   See GROUND-TRUTH §1.
2. **Pin exactly one `MasterAccountController`, and assert it before signing.** Two are live on
   Coston2 with identical ABIs. Arming against the wrong one sets an allowance on an empty account
   and every execution reverts on `transferFrom` forever — silently, permanently, unrecoverably. The
   canonical one is whatever `AssetManager.getSmartAccountManager()` returns, resolved at runtime.
   Never hardcode it. See GROUND-TRUTH §2.
3. **`execute()` is permissionless and re-derives every bound on-chain.** Not "the keeper is
   trusted with limits" — the keeper is trusted with *nothing*. Every constraint is recomputed from
   FTSO and the stored rule at execution time, so the maximum damage from a leaked keeper key is
   zero and keeper liveness stops being a security property.
4. **Never let a venue tell you what anything is worth.** The execution floor derives from FTSO,
   never from an AMM quote. A venue-spot deviation check is itself an AMM read and hands an attacker
   a cheap censorship primitive: move the shallow side, block every rule in the pair.
5. **One oracle read is not a price.** A quote has two legs. A single XRP/USD read only produces a
   correct floor if the buy token is worth exactly $1 — so either read both legs, or pin the
   permitted buy tokens by address and enforce membership at arm time. Coston2 carries at least five
   unrelated "USDC" tokens.
6. **Staleness is measured against `block.timestamp`, not wall clock.** A feed age computed from
   when your script ran is not the age the contract sees. `maxFeedAge` comes from the in-contract
   p99, measured. See GROUND-TRUTH §5.
7. **Unknown means do not execute.** A stale feed, an unresolvable condition, an unavailable venue —
   all refuse. Absence of a detected problem is not evidence of safety. Inherited from Plimsoll and
   it holds here for the same reason.
8. **Exact integers, always.** No floating point anywhere, including JSON. XRPL drops, FAssets UBA,
   AMG and FXRP token units are distinct quantities; mixing them is the class of bug that costs
   users money silently.
9. **No signing, no keys, no custody** in any component that touches a user's funds. Trimmy holds an
   allowance, never a balance and never a key.

## Verification standard

Inherited from the SDK and Plimsoll, and non-negotiable here.

- Every measured fact goes in [`docs/GROUND-TRUTH.md`](docs/GROUND-TRUTH.md) **with the command
  that produced it**. Anything not measured is labelled `[Inference]`, `[Speculation]` or
  `[Unverified]`, and stays labelled downstream.
- A test that exercises our own implementation on both sides proves self-consistency and nothing
  else. Encoding paths are checked against **Foundry** (`cast sig`, `cast calldata`, `cast abi-encode`).
- Integration tests assert **invariants**, never specific amounts, so they stay meaningful as the
  chain moves.
- Fuzz and property tests are required, not optional — especially for fee arithmetic, decimal
  normalisation and the execution floor.
- Every rule derived from contract source records the address and the block it was read at.
- **Never write `vm.warp(block.timestamp + N)`. Use `vm.warp(vm.getBlockTimestamp() + N)`.** We build
  with `via_ir = true`, and the IR optimiser treats `block.timestamp` as loop-invariant — which it
  genuinely is inside a real transaction. `vm.warp` changes it out of band, which the optimiser
  cannot see, so in a loop the expression is hoisted and every iteration warps to the *same*
  timestamp. Time silently stops advancing and the test proves nothing. This cost us a real
  debugging cycle on `test_execute_finalPartTakesRemainder`, where two `vm.warp` calls both landed
  on `864120`. The cheatcode read is opaque to the optimiser and is always correct. The same applies
  to any timestamp captured for a mock (e.g. feed publication times).

## Known limits — state these, do not paper over them

- **There is no FXRP swap venue on Coston2.** 80 `getPool` calls across all five deployed V3
  factories return `address(0)`. Swap-based rules are demonstrated against a pool **we deploy and
  seed ourselves**, and the submission says so plainly. The yield venues, by contrast, are live and
  funded. See GROUND-TRUTH §3 and §4.
- **The "single XRPL payment" claim is true of arming only.** A rule over FXRP presupposes FXRP, and
  minting is lot-quantised with its own fees. The honest first-run journey is two payments. Lead
  with that rather than letting it collide with the demo on stage.
- **The two halves of the product have different trust models.** Permissionlessly-executable rules
  and enclave-gated (FCC private-trigger) rules are not equally trustless. Say which is which,
  every time.
- **A simulated TEE proves nothing about which code is running.** Its `codeHash` is a network-wide
  constant shared by 254 machines. If we ship on simulated attestation, the "verify the code hash"
  step is decoration and must not be presented as a guarantee.

## Scope

There is no scope reduction for time. The deadline is a fact to be reported, never an argument for
shipping less. If something cannot be finished, say so plainly and keep working on it.
