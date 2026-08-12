---
title: Architecture
summary: How an XRPL payment becomes a rule that keeps executing on Flare, which protocol does what, and exactly what is new about it.
order: 1
---

## What the system does

One XRPL payment arms a rule. The rule stays in Flare storage, re-evaluates for days, and carries
its own execution bounty, so nobody has to be online when its condition is met.

A rule is a bounded mandate. An agent, a front end or a script can compose one, and none of them can
exceed it: the allowance is sized exactly, the verb is one of three, the venue and the token pair are
indices into arrays fixed at deploy time, the lifetime budget and the expiry are written at arm time,
and `cancelAll` bumps an epoch that kills every rule for an account at once. Vendor-enforced agent
permissions do the same thing with infrastructure. This does it with a contract.

## The flow

<figure class="doc-fig">
  <img src="/assets/diagrams/architecture.svg" alt="The full path from one XRPL payment to an executed rule on Flare." loading="lazy">
  <figcaption>One XRPL payment in at the top, an executed rule out at the bottom. You appear once.</figcaption>
</figure>

## Which Flare protocol does what

| protocol | used for |
| --- | --- |
| FAssets | FXRP itself, and direct minting so the arming payment funds the rule it arms |
| FDC | proving the XRPL payment happened. `XRPPayment` attestation, source `testXRP`, proof served by the DA Layer |
| Smart Accounts | deriving the personal account from the XRPL address, and executing the committed batch on it |
| FTSO v2 | both legs of every price. `bytes21` feed ids, `getFeedById` is payable and non-view, `calculateFeeById` is queried and forwarded rather than assumed to be zero |
| FCC (TEE extensions) | `PRIVATE` rules only. The threshold lives in an enclave; the chain holds a commitment |

## One hardcoded address

`ContractRegistry` at `0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019` is the only address literal in
the contract, and it is the same on all four Flare networks. `FtsoV2` is resolved from it on every
read, never cached. Token, venue and vault addresses are constructor arguments: the deploy script
resolves `WNat` and `FtsoV2` from the registry, reads each token's `decimals()` off the token,
reads each feed live and requires a non-zero fresh value, and checks each vault's `asset()` before
broadcasting. After that they are immutable. There is no owner, no admin, no proxy, no pause and no
rescue, so the constructor arguments are the security model.

## What `onlyController` forces

`PersonalAccount.executeUserOp` is `onlyController`. A raw `eth_call` with selector `0x2b2ee783`
returns `0x` from the controller `0x434936d4...` and reverts `OnlyController()` (`0x59907813`) from
any other caller, in both deployed implementations. Two consequences follow, and they shaped
everything else:

- No keeper can drive a user's personal account. A leaked keeper key grants no capability the public
  lacks, because `execute()` is permissionless anyway.
- No rule can re-arm itself. A fresh XRPL payment is the only way to grant new authority.

So the only durable authorisation a user can leave behind is an ERC-20 allowance, granted inside the
arming batch, sized to `totalSellAmount + fee budgets` and never to `type(uint256).max`. A
compromised agent that holds the arming path can still arm a hostile rule, which is why the token
and venue allowlists are immutable and there is no `receiver` field. A compromised agent that holds
only a keeper key extracts nothing.

## The persistence claim, stated precisely

Flare Smart Accounts already let an XRPL payment drive an EVM call with no EVM wallet and no gas
token. Axelar GMP does the same from other chains. Trimmy is built on Smart Accounts and adds
nothing to them. Wallet-lessness is not the new part, and it is not claimed as one.

The new part is what the payment leaves behind. Every one of those paths is immediate dispatch: the
message fires once, now, and is gone. Step 4 above writes a `Rule` that is still there days later,
still re-evaluating against a fresh oracle read, still paying whoever executes it out of its own
proceeds. That is the property, and the allowance above is the whole of the mechanism.

`SCHEDULE` is not a new capability either. XRPL Escrow has done non-custodial time locks through
`FinishAfter` for years. What a scheduled rule adds is an action at the other end and a keeper who is
paid to take it.

## Keepers, and the executor we had to run

`execute()` is callable by anyone. `msg.sender` appears once in it, as the fee recipient. Measured on
Coston2: a plain execution costs 383,451 gas, and a `PRIVATE` execution costs 517,962. At the
testnet gas price of 2125 gwei that is about 4,698 UBA of FXRP, so rules are armed with
`keeperFeeFlat` around 9,400 for a 2x margin, and `arm()` refuses a fee budget that cannot fund the
rule's own maximum execution count. The 2125 gwei is a testnet artefact and is not a mainnet
figure.

Arming needs an executor to submit the FDC proof. We run our own, and that is measured rather than
assumed. Two arming payments settled on XRPL and neither was picked up by the public executor within
600 seconds, including one offering `executorFeeUBA = 100000`. The public executor was measured
acting on the 48-byte `DIRECT_MINTING_EX` branch; on the `0xFE` Smart Accounts branch it did not act
at all.

## Limits

- Coston2 testnet only. Nothing has run on Flare mainnet.
- The FXRP/WC2FLR pool `0xafcA1C5DfF08b3B8Bacb7721fb8189d2D8E7C3DB` is ours and it is thin. Coston2
  had no FXRP pool at all: 5 factories x 4 counter-tokens x 4 fee tiers, 80 of 80 `getPool` calls
  returned `address(0)`. Seeded with 0.305637 FXRP and 50 WC2FLR concentrated within about 5%. A
  0.01 FXRP sell filled at 38 bips; a 0.05 FXRP sell was refused three times, then filled at 5.6
  bips once the pool was re-centred against the oracle.
- `PRIVATE` is strictly weaker than the other three triggers. It needs one enclave running, and its
  operator can censor any such rule by declining to act. It is never trustless.
- The enclave's code hash is published only as its first four bytes, `0xe9ab7410`. The full 32 bytes
  are not yet published.
- The execution floor is publicly computable, so it is a target. An observer can take up to
  `MAX_SLIPPAGE_BIPS` (50) per execution with certainty. That is bounded, not eliminated.

Source: [`contracts/src/Trimmy.sol`](https://github.com/Immadominion/trimmy/blob/main/contracts/src/Trimmy.sol),
[`contracts/script/Deploy.s.sol`](https://github.com/Immadominion/trimmy/blob/main/contracts/script/Deploy.s.sol),
[`research/01-ARCHITECTURE.md`](https://github.com/Immadominion/trimmy/blob/main/research/01-ARCHITECTURE.md),
[`docs/GROUND-TRUTH.md`](https://github.com/Immadominion/trimmy/blob/main/docs/GROUND-TRUTH.md).
