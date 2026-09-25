# Production readiness

Status checked September 25, 2026. Trimmy has a working game and a guarded Solana trading path. It is not yet a complete production wallet. This audit separates technical checks from completed transactions and release requirements.

## Verified and fixed

- **11 stock identities:** the deployed [server registry](../apps/api/src/stock-trading-catalog.ts) binds AAPLx, TSLAx, NVDAx, MSFTx, AMZNx, GOOGLx, METAx, COINx, HOODx, NFLXx and AMDx to issuer-confirmed Solana mints. Discovery alone cannot enable trading.
- **Order verification:** unsigned buy reviews and simulations passed for all 11, plus AAPLx sell checks. Buy/sell indicative quotes were also checked for all 11. No new transaction was signed or broadcast during this audit. The older demo separately records a completed $2 AAPLx buy. Other completed trades and every sell route remain unverified; liquidity and provider routes can change.
- **Balances and recovery:** holdings V2 aggregates validated stock accounts and distinguishes total holdings from canonical-account spendable balances. Token-2022 display scaling is preserved. The mobile flow uses trading capabilities, refreshes wallet state, and reconciles pending orders before another submission. Older holdings clients retain V1 responses.
- **Gameplay and feedback:** Career/community browser preflights, stale draft revisions, lost draft-save responses and failed sound preparation now have regression coverage. Paper and Real ledgers remain separate.
- **Reminders:** native Android/iOS local scheduling and Career tap routing are implemented for daily or Monday/Wednesday/Friday check-ins around 7 PM local time. This is not a social or transaction push-delivery system.
- **Checks:** backend and relevant mobile tests passed; targeted analysis passed. The committed-history secret scan found no leaks in the 14 commits scanned. That scan does not certify private/untracked files or later changes.

## Before broader real-money use

| Gap | Required follow-through |
| --- | --- |
| **Withdrawals and wallet recovery/export** | Ship a reviewed send/withdrawal path and a safe provider-backed recovery/export flow. Validate destination, network, fees, cancellation and interrupted-session recovery. Historical UI-review screens do not implement these features. |
| **Complete real trade history** | Add a paginated account history with confirmed, failed and pending orders, amounts, fees and explorer links. Latest-order recovery is not a complete statement or external-wallet activity history. |
| **Portfolio valuation** | Add timestamped stock/SOL USD prices and explicit stale/unavailable states, respecting each mint's display scaling. Today the cash card represents USDC, SOL is shown separately, and real stock values are unavailable. Do not present this as total account equity. |
| **Policies and issuer eligibility** | Reconcile in-app Terms/Privacy with actual trading, funding and data handling. Confirm issuer/geographic eligibility requirements and implement the required controls before broad access. A verified mint, successful simulation or user checkbox is not eligibility approval. |
| **Card funding** | Crossmint is staging; its test funds cannot finance a mainnet trade. Obtain production onramp approval and validate supported regions, fees, checkout return and actual delivery. Add durable provider-order/webhook reconciliation for support beyond the current status window. |
| **Native reminder validation** | Verify delivery and tap routing on Seeker and iPhone, including denial/revocation, quiet mode, sign-out/account switch, app restart, Android reboot and timezone changes. Android delivery can be delayed by OS battery scheduling. Compile or channel tests alone do not prove delivery. |

Live sells currently spend the canonical token account. Tokens in other owned accounts still count toward holdings but require a separately reviewed transfer before they become spendable; no automatic consolidation is implemented.

For distributable Android builds, use release signing. Keep development certificate overrides local and never uninstall a funded app to bypass an update mismatch. See [Development](DEVELOPMENT.md#android-signing-and-the-development-seeker) and [Crossmint funding](architecture/CROSSMINT_ONRAMP.md).
