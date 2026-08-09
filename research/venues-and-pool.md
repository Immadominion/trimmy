# Trimmy — Venues and Pool (Coston2 action surface)

Status: IN PROGRESS — being written incrementally as reads land.
Date of live reads: 2026-08-06. Chain: Coston2, chainId 114, RPC `https://coston2-api.flare.network/ext/C/rpc`.

FXRP (Coston2): `0x0b6A3645c240605887a5532109323A3E12273dc7`, 6 decimals, totalSupply 4,134,532.6958 FXRP.

## Headline (provisional)

The three "vaults" are **two different products**, not three instances of one:
`0x9E63a5D2…` (TESTearnXRP) and `0xF97B2bBd…` (MyERC4626) are **the same `MyERC4626` Upshift-style
contract with a request/claim withdrawal queue** — they expose `requestRedeem`, `claimWithdraw`,
`lagDuration`, `withdrawalFee`, `depositCap`. `0xC90D6847…` (stXRP / FirelightVault) is a
TransparentUpgradeableProxy over impl `0x9892419e190a63ff46e9DA7da387EeAD8d4a7213`.

`[Measured]` `maxWithdraw(0xdead)` and `maxRedeem(0xdead)` on stXRP both return **0** — consistent with
a non-instant redemption path, not with plain ERC-4626.

`[Measured]` stXRP `maxDeposit(0xdead)` = **899,251.567 FXRP** against `totalAssets` = 100,748.433 FXRP.
Those sum to exactly **1,000,000.000000 FXRP** — i.e. **stXRP carries a hard 1,000,000 FXRP deposit cap.**
This is a deposit cap that no prior document recorded.

(sections filled in below as reads complete)
