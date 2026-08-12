---
title: Where Trimmy runs today
summary: The honest status list: Coston2 testnet only, a thin pool that is ours, our own executor, and what would have to change before real money.
order: 9
---

## Coston2 testnet, and nowhere else

Trimmy runs on Flare's Coston2 test network, chain ID 114, against XRPL testnet XRP. Nothing has
ever run on Flare mainnet, so you cannot use Trimmy with real money today.

What runs, each with a public transaction behind it:

| Piece | State |
| --- | --- |
| `Trimmy` `0x19F81AAB…` | live, rules armed and executed |
| Arming from one XRPL payment, no EVM wallet, no FLR | live |
| `PRICE_BELOW`, `PRICE_ABOVE`, `SCHEDULE` | live, permissionless execution |
| `PRIVATE` on a real AMD SEV enclave | live, one machine |
| Swap into WC2FLR | live, against a pool we deployed |
| Deposit into an ERC-4626 vault | live, against TESTearnXRP, which we do not control |
| One-tap signing from a wallet | not built |

Older deployments are still on chain and carry a bypassable version of the confidential trigger. Do
not arm a private rule against `Trimmy 0x9c7876df…` or trigger `0x1121702e…`; they are left there so
the history stays checkable.

## The swap pool is ours, and it is thin

Coston2 had no FXRP pool at all: all 80 combinations of 5 deployed V3 factories, 4 counter-tokens
and 4 fee tiers returned the zero address. So we deployed and seeded one ourselves.

Pool `0xafcA1C5D…`, FXRP against WC2FLR, 0.30% fee tier, seeded with **0.305637 FXRP and
49.999999996 WC2FLR** in one position, about 5% either side of the FTSO price. That is the whole
depth.

| Sell | Result |
| --- | --- |
| 0.01 FXRP | executed, 38 bips of cost against the oracle |
| 0.05 FXRP | refused, refused again after a 2.66x deepening, then executed at 5.6 bips |

The refusals matter more than the fills. The pool had drifted 36.6 bips below the oracle, and with
the 0.30% fee on top no trade size fitted inside the rule's 50 bip floor. Depth was not the binding
constraint; staleness was. A testnet pool has no arbitrageurs to correct that drift, so it decays
until we re-centre it by hand. The rule refused rather than filling badly, which is what the floor
is for, and the refusals cost no gas: they died in the keeper's pre-simulation.

## We run our own executor, and we have to

An arming payment is meant to be picked up by a public executor that collects a fee. We sent two,
both `tesSUCCESS` on XRPL, and watched each for 600 seconds:

| Executor fee offered | Picked up |
| --- | --- |
| 0 | no |
| 100,000 UBA, the protocol's full executor fee | no |

The first is expected: our tool now refuses to build a zero-fee payment. The second is the
finding, that a full fee was offered and the payment was still ignored. The public executor appears
not to act on the `0xFE` Smart Accounts branch at all, and that is the only branch Trimmy uses, so
we run our own. That is a dependency on us.

## One-tap signing is not built

The arming page builds the payment in your browser and explains what signing it would authorise.
What it cannot do is hand that payment to your wallet in one tap: Xaman's hex deep link carries
TrustSet transactions only, and a memo-bearing request needs Xaman's Platform API with a server-held
key. The page gives you the three fields to type into any XRPL wallet instead.

## The private path runs on one enclave

One Google Confidential Space machine on AMD SEV, run by us. Its operator can censor a private rule
by declining to act, no on-chain heartbeat distinguishes censorship from a quiet market, enclave
memory is volatile so a restart drops every threshold, and the full 32 byte code hash is not
published. [Private rules](/docs/private-rules/) sets this out in context. Multi-machine verdicts
are a design change, not a setting.

## Other measured limits

- **Vault exits are not instant.** All three FXRP vaults report `maxWithdraw` of zero: they are
  request-and-claim queues. An exit runs in two steps, and the claim cannot land before the next
  UTC midnight, so the wait reaches roughly 24 hours.
- **FAssets works in lots of 10 FXRP,** so minting and redemption cannot go finer than that.
- **The fee numbers are testnet numbers.** The keeper fee of 9,400 UBA is twice the 4,698 UBA that
  383,451 gas costs at Coston2's 2125 gwei, and that gas price is a testnet artefact.
- **A mistyped XRPL address does not error.** The controller derives a Flare account from any
  string, so a typo resolves to a real account you do not control and the payment cannot be
  recalled. Our tools verify the checksum offline first.

## What would have to be true before this handles real money

1. A deployment on Flare mainnet, which has never happened.
2. A real FXRP venue with depth and arbitrageurs, not a pool we seeded with 0.305637 FXRP.
3. Mainnet gas measured, so the keeper fee comes from that market, not a faucet chain.
4. Either a public executor that acts on the `0xFE` branch, or a funded commitment that we keep
   running ours.
5. More than one enclave for `PRIVATE`, an on-chain heartbeat so censorship is visible, and the full
   code hash published so anyone can rebuild the image and compare.
6. One-tap signing, or an equally checked manual path: hand-copying a 42 byte memo does not survive
   real users.
7. An independent review of the deployed bytecode. The contracts have no owner, no proxy and no
   pause, which is deliberate and means every fix is a redeploy.

Measured between 2026-08-06 and 2026-08-09 on Coston2. Chain state drifts and protocol parameters
are governance-settable, so re-check anything you rely on.
