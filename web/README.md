# Trimmy — the arming page

A static page that builds an XRPL arming payment in the browser and then shows, in plain English,
exactly what signing it would authorise.

No wallet connect, no install, no server, no dependencies, no build step. Open it and it works.

```bash
cd trimmy/web
python3 -m http.server 8731     # any static server; ES modules need http, not file://
open http://127.0.0.1:8731/

node --test "test/*.test.mjs"   # 22 tests
```

## Why the page is shaped like this

The interesting part is not the form. It is section 3, **"What you would be authorising"**.

An XRPL payment aimed at Flare is irreversible, and the only thing that decides its outcome is a
42-byte memo that is unreadable by eye. So the page does not restate the form back to the user —
that would look identical while proving nothing, because a bug in the encoder would be echoed back
word for word. Instead [`lib/decode.js`](lib/decode.js) reads the **built bytes**, re-derives the
commitment, and describes what it finds. If the encoder and the decoder ever disagree, the page says
the payment is not safe to send.

## What is checked before anything is built

| check | why |
| --- | --- |
| XRPL address checksum | `getPersonalAccount` **derives** an address from any string rather than looking one up — a typo silently resolves to a different account. See [`GROUND-TRUTH §00a`](../docs/GROUND-TRUTH.md). |
| executor fee > 0 | A zero-fee payment is never executed, does not fail, and sits at the Core Vault while the XRP is gone. Reproduced with a real 5 XRP payment. |
| memo is 42 bytes, opcode `0xFE` | Anything else is not a Smart Accounts instruction. |
| memo commits to this batch | Re-derived from the pre-image, not assumed. |
| spender is really Trimmy | An unexpected spender reads as unexpected, not as a friendly label. |
| every call is recognised | An unknown selector is reported as unknown, with "do not send it". |

## Files

| file | what it is |
| --- | --- |
| [`lib/keccak.js`](lib/keccak.js) | Keccak-256. Hand-written because a CDN script tag is a third party who can change the commitment you are about to sign. Verified against standard vectors. |
| [`lib/arming.js`](lib/arming.js) | ABI encoding, `PackedUserOperation`, memo. A second implementation of `arming/bin/arm.dart`. |
| [`lib/decode.js`](lib/decode.js) | Reads a payment back out of its own bytes. Trusts nothing above it. |
| [`lib/chain.js`](lib/chain.js) | The two read-only Coston2 calls. Extracted from the page so it can be tested. |
| [`lib/xrpl-address.js`](lib/xrpl-address.js) | base58check validation. |

## The test that makes this safe

`web/lib/arming.js` and `arming/bin/arm.dart` are two independent encoders for the same
irreversible payment. Two encoders that disagree produce a memo committing to a batch nobody
intended.

So the fixture in [`test/arming.test.mjs`](test/arming.test.mjs) is not synthetic. It is the exact
user operation `arm.dart` built for XRPL transaction `384FE782…B778A`, which settled on ledger
19771685 and armed rule 1 on Trimmy `0x19F81AAB…`. The test asserts the browser encoder reproduces
that pre-image **byte for byte** and the same 42-byte memo.

The address validator is tested by mutating every character of a real address to every other
character in the XRPL alphabet — 1,900+ variants — and asserting none is accepted.

## What is not built

**One-tap signing.** Xaman's hex deep link (`https://xaman.app/detect/<hex>`) is documented as
carrying **TrustSet transactions only**, so it cannot carry a Payment with Memos. A memo-bearing
sign request needs Xaman's Platform API, which needs an API key held by a server. That is the one
piece of this flow that cannot be done from a static page, and it is deliberately absent rather
than faked.

Today the page gives you the three payment fields to enter in any XRPL wallet, with the memo most
of all.
