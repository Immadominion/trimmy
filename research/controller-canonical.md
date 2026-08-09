# controller-canonical — which MasterAccountController is canonical on Coston2

**Status:** BLOCKING question — RESOLVED for Q1. Live reads 2026-08-06, chainId 114.
**RPC:** `https://coston2-api.flare.network/ext/C/rpc`

---

## Headline

`FlareContractRegistry.getAllContracts()` on Coston2 registers **exactly one**
`MasterAccountController`:

```
MasterAccountController = 0x434936d47503353f06750Db1A444DBDC5F0AD37c
```

`0x32F662C63c1E24bB59B908249962F00B61C6638f` **is not in the registry under any name.**
That is the canonical/non-canonical split. `[Verified]`

---

## 1. What Flare officially publishes

`[Verified]` — `cast call 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019 "getAllContracts()(string[],address[])" --rpc-url https://coston2-api.flare.network/ext/C/rpc`

The Coston2 registry returns 69 names. The tail of the list (the FAssets/Smart-Accounts block):

| Registry name | Address |
|---|---|
| `AssetManagerController` | `0x1C772F700308aF4c13897cc7b9c41EFfB82c50C0` |
| `AssetManagerFXRP` | `0xc1Ca88b937d0b528842F95d5731ffB586f4fbDFA` |
| **`MasterAccountController`** | **`0x434936d47503353f06750Db1A444DBDC5F0AD37c`** |
| `DelegationAccountManager` | `0x5Ddb590530EF66775E6225671eaBD94959e9AE0e` |

Two side-effects of this read:

- **AssetManagerFXRP on Coston2 is confirmed** as `0xc1Ca88b937d0b528842F95d5731ffB586f4fbDFA`.
  The prior pass flagged this as "believed — re-verify, do not trust". It is now `[Verified]` from
  the registry, which is the primary source Flare itself directs integrators to.
- `FtsoV2` = `0xC4e9c78EA53db782E28f28Fdf80BaF59336B304d`, matching the prior pass. `[Verified]`

`0x32F662C6…` does not appear anywhere in `getAllContracts()`. `[Verified]`

**Why the registry is the authoritative source, not a docs page.** Flare's own integration guidance
(`@flarenetwork/flare-periphery-contracts` / `flare-wagmi-periphery-package`, and every
dev.flare.network guide) resolves addresses through `FlareContractRegistry` at the network-invariant
address `0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019`. A contract that is *not* in the registry cannot be
found by any conformant integrator, which by itself settles which of the two stacks Flare considers
live.

---

## 2. What distinguishes the two — see §2 table below (filled in by second read batch)

## 3. The routing question — see §3

## 4. The preflight assertion — see §4
