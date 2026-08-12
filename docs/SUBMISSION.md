# Flare Summer Signal, submission draft

Deadline **14 August 2026**. Entering **both** bounties with one project.
Fields below follow the DoraHacks requirement list exactly, in order.

Anything still needing a decision is marked **[DECIDE]**. Anything not yet true
is marked **[PENDING]** rather than written as though it were.

---

## 1. Project name

**Trimmy**

---

## 2. Selected bounty or bounties

**Both.**

- **Bounty 1, Interoperable Asset Products.** Trimmy turns one XRPL payment into
  a standing rule on Flare that acts on FXRP afterwards, using FAssets, Smart
  Accounts, FDC and FTSO together.
- **Bounty 2, Confidential Compute Apps.** A private rule holds its threshold
  inside a GCP Confidential Space enclave on AMD SEV. The chain stores a
  commitment and never learns the number.

They are one product, not two entries. The confidential trigger is a fourth
trigger type on the same contract, which is the honest way to describe it.

---

## 3. Short product description

One XRPL payment leaves behind a rule that keeps watching the market after you
stop. When the condition is met, whoever executes it collects a fee the rule
itself carries, so somebody will.

An XRP holder who wants "sell if it drops" or "put a little into the vault every
week" has two options today: watch the chart themselves, or hand their keys to
somebody who will. The first does not work while you are asleep, and the second
is how most people lose money in this market.

Trimmy is the third option. You sign one ordinary payment from your own XRPL
account. That payment carries a 42-byte memo which arms a rule on Flare with
every bound fixed: amount each time, how many runs, an expiry, and a price band.
Nothing afterwards needs your key, your attention, or an open browser tab, and
nothing can widen those bounds later, including us.

---

## 4. Target user

Three, in the order we can actually reach them.

1. **XRP holders who want a stop without a custodian.** The XRP Ledger's own
   documentation states it "does not natively represent concepts such as market
   orders, stop orders, or trading on leverage." A non-custodial stop for XRP
   does not exist today.
2. **Wallets and XRPL apps** that want to offer limit orders without becoming an
   exchange or holding a balance. They build the memo; the user signs a normal
   payment; the wallet never holds a key.
3. **AI agents with a mandate.** Trimmy ships an MCP server whose four tools are
   all read-only. An assistant can read armed rules and compose a new one, and
   what it produces is a payment for a person to sign. It cannot sign, cannot
   send, and refuses outright to handle a private threshold.

---

## 5. Demo link, video, or working app link

**Working app, live now:**

| | |
|---|---|
| Product | https://trimmy.xyz |
| Build a real arming payment in your browser | https://trimmy.xyz/arm/ |
| Every rule armed right now, read live from Coston2 | https://trimmy.xyz/rules/ |
| Documentation | https://trimmy.xyz/docs/start-here/ |
| Plimsoll | https://plimsoll.trimmy.xyz |
| Flare Dart SDK | https://flaredart.trimmy.xyz |

`/rules/` is the one worth opening first. It reads the contract from the
reader's own browser with no backend and no cache, and the page shows the two
`cast` commands that reproduce it without us.

**Video: [PENDING]** 2 minutes 20 seconds, showing a rule armed from a chat
prompt, signed by a person, and then fired by a keeper nobody had to be online
for.

---

## 6. GitHub repo or technical materials

| | |
|---|---|
| Trimmy | https://github.com/Immadominion/trimmy |
| Plimsoll | https://github.com/Immadominion/plimsoll |
| Flare Dart SDK | https://github.com/Immadominion/flare-dart |

**Published packages**, both released during the program:

- https://pub.dev/packages/flare_network (0.1.0)
- https://pub.dev/packages/flare_network_periphery (0.1.0)

Every numeric claim traces to
[`docs/GROUND-TRUTH.md`](https://github.com/Immadominion/trimmy/blob/main/docs/GROUND-TRUTH.md),
which records the command that produced each measurement. Anything not measured
that way is labelled `[Inference]`, `[Speculation]` or `[Unverified]` and stays
labelled.

---

## 7. How the project uses Flare

Four Flare protocols, each load-bearing. Remove any one and the product stops
working.

**FDC** proves the XRPL payment happened. The arming payment is attested with a
`Payment` attestation, and the Smart Account executes the batch the memo
commits to. Without it there is no trustless bridge from a signature on XRPL to
state on Flare.

**Smart Accounts** are what let an XRPL account drive an EVM call with no FLR
for gas and no Flare key. The rule's owner is the personal account the
controller derives from the XRPL address. This is the piece that makes "sign
once, in the wallet you already have" true rather than aspirational.

**FTSO** decides whether a price rule fires, read fresh on every execution, two
legs (sell feed against buy feed) rather than one leg against an assumed dollar
peg. Both feeds are age checked. A stale feed, a future dated feed and an
unpriceable pair all revert rather than guess.

**FAssets** is the asset itself. The rule acts on FXRP, so the XRP a user
already holds is what the rule spends.

**FCC (Flare Confidential Compute)** carries the fourth trigger. Extension
`66052` runs on TEE machine `0xB33E5CF59e3ce1D58427B9F4E23d0444c128D3D7`,
`GCP_AMD_SEV`, real hardware rather than a simulator.

---

## 8. What was newly built during the program

**All of it.** There is no pre-existing project to separate out.

| repo | first commit | commits |
|---|---|---:|
| flare-dart | 1 August 2026 | 34 |
| plimsoll | 3 August 2026 | 41 |
| trimmy | 10 August 2026 | 21 |

96 commits, every one inside the 29 June to 14 August window. The three repos
were built in that order because each was blocked on the one before it.

**Flare Dart** exists because Flare publishes developer guides for JavaScript,
React, Python, Rust and Go, and none for Dart. Querying Flare's own
documentation search for `dart` or `flutter` returns *"No matching documents
found"*. To be precise, because a reviewer will check: a Flutter app could
always reach Flare over JSON-RPC, and `web3dart` is a maintained general purpose
Dart EVM library. What did not exist is anything Flare specific. This package is
164 generated bindings against Flare's own ABI artifacts: 1,049 read methods,
513 transaction builders, 592 decodable events and 168 decodable custom errors.
Now on pub.dev.

**Plimsoll** exists because an XRPL payment aimed at Flare is one shot and
final, and we lost money proving it. On Coston2, FAssets direct minting takes a
minimum fee of 0.1 XRP and an executor fee of 0.1 XRP, but the protocol's own
`paymentTooSmall` flag only checks against the first. **Anything from 0.1 to 0.2
XRP inclusive delivers exactly zero, silently: no event, no revert, the
transaction succeeds.** The real waterline is 0.2 XRP plus one drop, a sum that
appears in no single protocol setting. Every row of that table was forecast
before the payment was sent, then paid for. Nine findings contradicted the
documentation, including that `PackedUserOperation` is the nine-field EIP-4337
struct rather than the ten-field one in the docs' own example, and that Flare's
published preflight is off by one on all three delay bounds.

**Trimmy** is the product built on top of both.

**Also new during the program, and worth naming because each was a bug first:**
the confidential trigger was completely bypassable in its first form. The
observed price was a caller-supplied string and a verdict was never checked
against the instruction that requested it, which together let any stranger fire
a victim's rule at a price its owner never chose, and let roughly twenty queries
binary-search the secret. Both halves are fixed, redeployed, and both attacks
re-run against the live contract and now revert. That is written up in full in
GROUND-TRUTH rather than quietly patched.

---

## 9. Contract addresses and deployment details

**Network: Flare Coston2 testnet** (chain ID 114).

| | address |
|---|---|
| `Trimmy` | `0x19F81AAB43f7a26B0659754b70179aDcAF43ef7C` |
| `TrimmyConfidentialTrigger` | `0x02EA709e2278EACDbA00D4A88caA604E3b35293b` |
| FCC extension | `66052` |
| TEE machine | `0xB33E5CF59e3ce1D58427B9F4E23d0444c128D3D7`, `GCP_AMD_SEV` |
| FXRP/WC2FLR pool | `0xafcA1C5DfF08b3B8Bacb7721fb8189d2D8E7C3DB` (ours) |

Both halves have run end to end on chain. `https://trimmy.xyz/rules/` shows the
live rules and gives the two `cast` commands to check them without us.

---

## 10. Roadmap and next steps

**Immediately after judging**

- Mainnet deployment. The keeper fee is currently derived from a faucet chain's
  gas market, which is not the real one.
- One-tap signing. Xaman's hex deep link carries `TrustSet` only, so a
  memo-bearing sign request needs their Platform API and a server-held key. That
  is the one piece of the flow that cannot be done from a static page, and it is
  not built.
- Vault exit is implemented and tested but not armable on the live deployment.

**Next**

- More than one enclave. A private rule today needs one enclave to be running
  and its operator can censor it by declining to act. That is a weaker trust
  model than the other three triggers, which are permissionless, and it is
  stated plainly in the docs rather than glossed.
- Wallet SDK, so a wallet can offer limit orders in a few lines.
- Agent mandates beyond read-only, with the signing boundary kept where it is.

---

## Encouraged extras

**Network:** Coston2. Not Songbird, not mainnet. Stated plainly because the
alternative is implying more than is true.

**Distribution and testing so far:** honest answer, thin. Three public
repositories, three live sites, two published pub.dev packages, and a public
live-rules page. No pilot users and no partner conversations. What exists is the
product and the evidence, not traction, and claiming otherwise would be the
easiest thing in this document to disprove.

**What we would point a judge at first:** `https://trimmy.xyz/rules/`, then
`docs/GROUND-TRUTH.md`, then the dead-zone table on
`https://plimsoll.trimmy.xyz`. In that order, because the first is live state,
the second is how every number was obtained, and the third is the one finding
that cost real money to learn.
