---
title: Arming a rule
summary: Step by step: check your XRPL address offline, choose the rule, read the independent decode, then send one XRPL payment carrying three fields.
order: 3
---

Trimmy is live on Flare Coston2 testnet only. Nothing has run on Flare mainnet. The XRP you send is
testnet XRP and is worth nothing.

You need an XRPL testnet address, its wallet, and testnet XRP. No EVM wallet, no FLR, no extension.
That is not new: Smart Accounts already lets an XRPL payment drive a contract call with no gas
token, and Trimmy is built on it. What this payment buys is a rule that stays armed afterwards.

## 1. Open the arming page

Open [trimmy.xyz/arm](https://trimmy.xyz/arm/) over https, or `localhost` if you run it yourself.
On plain http it disables its address field: step 2 needs `crypto.subtle`, which browsers give only
to secure origins, and a page that stopped checking quietly would be worse than one that refuses.

## 2. Enter your XRPL address

Paste it, then press "Look up my account". Your browser verifies the address's four-byte
base58check checksum offline, before any network call. Only then does the page ask Flare, read-only,
which account that address controls.

### A mistyped address cannot be caught on Flare

`MasterAccountController.getPersonalAccount` derives an address from any string. It is not a lookup,
and it never fails. Measured on Coston2:

| String handed to the contract | Address returned |
| --- | --- |
| `rDE4JUm2jaue31VwidRXWuWzf5dQkUxcsB` | `0x07a76b5c…`, the real account |
| `rDE4JUm2jaue31VwidRXWuWzf5dQkUxcsA`, one character changed | `0x6085dbe8…` |

A typo therefore does not error. It resolves to a different Flare account, and a payment armed
against it sets an allowance and creates a rule on an account you do not control. It cannot be
recalled or refunded, so nothing recovers it.

The checksum your address already carries is the only place this is detectable, and before you send
is the only time. Hence the browser check, whose test mutates every character of a real address into
every other character of the XRPL alphabet, 1,900+ variants, and accepts none. Copy your address
from your wallet rather than retyping it.

## 3. Choose the rule

Pick a preset, then set the amount each time, how many times, how often or at what price, and the
expiry. [Rule types](/docs/rule-types/) covers what each one does and does not do.

Other bounds are fixed in the contract, with no setter: the pair and venue are set at deploy time, a
sale must land within 50 basis points of the oracle price, schedules cannot run faster than every 60
seconds, and no rule lives past 365 days.

So what you sign is a bounded mandate: an exact allowance rather than an unlimited one, one verb,
one venue, one token pair, a hard budget, an expiry, and a cancel-all. An agent can compose a rule
inside that boundary and cannot exceed it, and it cannot reach your account another way:
`PersonalAccount.executeUserOp` is `onlyController`, measured.

## 4. Read what you would be authorising

Press "Build the payment" and read the panel stamped "Memo verified" or "Do not send".

A 42-byte memo decides the whole outcome on Flare, and nobody reads it by eye. The page could
restate the form you filled in, which would look identical and prove nothing: an encoder bug would be
echoed back word for word. Instead a separate decoder reads the bytes it built, re-derives the
commitment, and describes what it finds, reading nothing from the form. It refuses the payment if
the memo does not commit to the batch, if the spender is not Trimmy, or if a selector is
unrecognised.

## 5. Send the payment

From any XRPL wallet, send one payment with three fields:

```text
Destination : rDhpmiPq4BVBDWMVdSrmkgt8thKyRzGV1p
Amount      : the XRP figure the page shows
Memo        : MemoData = the 84 hex characters the page shows
```

**Do not add a destination tag.** A registered tag overrides the memo entirely and credits the tag
holder: the payment goes to a stranger and no rule exists.

For twelve runs of 0.01 XRP:

| Component | Amount |
| --- | --- |
| What the rule can spend | 0.12 XRP |
| Minting fee, taken by FAssets | 0.10 XRP |
| Delivery fee, paid to the executor | 0.10 XRP |
| Total | 0.32 XRP |

The minting fee is 0.25% with a 0.1 XRP minimum, so the minimum applies here. The delivery fee is
read live, because governance can change it. Unspent budget stays in your account.

Never send less than the figure shown. Anything from 0.1 to 0.2 XRP inclusive delivers you exactly
zero, with no revert and no event, and the XRP is gone. The floor is 0.2 XRP and one drop.

## One-tap signing is not built

You copy three fields by hand. Xaman's hex deep link carries TrustSet transactions only, so it
cannot carry a Payment with Memos. A memo-bearing request needs Xaman's Platform API and a
server-held key, which a static page cannot have. It is missing, not faked.

## If you chose a private rule

The payment carries no threshold price and cannot: anything in it sits on a public ledger forever.
Arming sets `triggerValue = 0`. It fires only once you run the command the page gives you, which
encrypts your price to the enclave and commits a hash of it. This trust model is weaker than the
other three: it needs one enclave running, and that operator can censor it by declining to act. It
is not trustless.

Next: [What happens after you arm](/docs/after-arming/).
