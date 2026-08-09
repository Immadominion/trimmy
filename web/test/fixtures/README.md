# Fixtures

## `settled-payment-384FE782.userop.hex`

`abi.encode(PackedUserOperation)` for a payment that **settled on XRPL** and armed a real rule.

| | |
| --- | --- |
| XRPL transaction | `384FE782BE520662EA579AB67A2232DE5BD650A8A0E2ACB75C2B8C80514B778A` |
| ledger | 19771685 (`tesSUCCESS`) |
| built by | `arming/bin/arm.dart` |
| memo | `FE0000000000000186A0EBBE0E…` |
| commitment | `0xebbe0ee068f4ba0a9e39e41fdca1dbf26864aaddb0aa42e59371eb67b7ce96cc` |
| armed | rule 1 on Trimmy `0x19F81AAB43f7a26B0659754b70179aDcAF43ef7C` |

It lives here, committed, rather than being read out of `arming/out/` — that directory is working
output and is gitignored, so the cross-check silently did not run from a fresh clone. This is the
one test that stops the browser encoder from emitting a memo that commits to a batch nobody
intended, so it must run everywhere.

Nothing in it is secret. Every byte of it is on a public ledger.
