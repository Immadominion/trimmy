# Architecture

Trimmy teaches stock decisions through a simulated working life. The first order introduces the mechanics; the recurring experience is evidence, decisions and feedback.

## Product surfaces

`apps/mobile/lib/main.dart` starts the current Flutter product in `lib/product/`. `apps/web` is the React web product. `apps/site-v2` is the separate marketing website. Older study entry points remain for migration and regression coverage; they are not the primary app.

The startup sequence is animated welcome → paper introduction → guided first stock order → congratulations → sign-in or explicit guest → reminder/funding choices → Desk. Career delivers 20 sequential three-stage workdays from `content/workdays/intern-v1.json` through the API and database migrations.

## State and authority

- Account identity is verified server-side. A client-supplied account ID is not authority.
- Guests explicitly opt in. A guest's installation credential scopes its saved paper activity.
- Paper quotes and order receipts are server-owned; an idempotency key preserves an uncertain submission for reconciliation.
- Career completion and Trims are persisted through database functions. Display animation does not award points.
- Real/Paper is account-scoped UI state persisted across restarts. It selects the trading and holdings path; it never grants permission to spend.
- Real cash currently means the connected Solana wallet's USDC balance. SOL and the supported stock token are separate unit balances, not an invented USD portfolio total.

## Market and wallets

Tokens.xyz readers normalize discovery, facts and token-price history. Missing provider information remains unavailable rather than being manufactured. Solana RPC supplies wallet balances and top token accounts; top accounts are not a complete census of individual owners. Token-account ownership and names require separate resolution.

Privy manages identity and the embedded wallet. Server code validates wallet ownership. A wallet-message ownership check is separate from transaction approval.

The live stock adapter in `apps/api/src/live-stock-orders.ts` validates the initial AAPLx/USDC route, amounts, approved programs and fees, simulates the prepared transaction, and reconciles submission on Solana. Its runtime capability is disabled unless explicitly configured. The staging Crossmint onramp binds checkout to a verified recipient and checks provider order status. Staging completion is not a mainnet deposit.

## Repository map

| Path | Contents |
| --- | --- |
| `apps/mobile` | Flutter app, bundled motion/art/audio, widget and integration tests |
| `apps/api` | Fastify API, persistence adapters and provider boundaries |
| `apps/web` | Browser product using the same API |
| `apps/site-v2` | Marketing site |
| `packages/domain` | Pure amount, eligibility and other shared rules |
| `infra/migrations` | Ordered PostgreSQL schema and authorization changes |
| `content` | Versioned practice and workday definitions |
| `contracts` | Shared API/data schemas |
| `tool` | Content checks, isolated test tools and runtime utilities |

## Current limits

Real execution is feature-gated; the current deployment is not advertised as a generally available brokerage. Crossmint uses staging credentials. Completed payment delivery and an end-to-end real trade have not been verified in this publication pass. Reminder preferences are stored, but preferences alone do not establish scheduled notification delivery. Social features require their server readiness gates. Sui, Base and BNB remain planned integrations.
