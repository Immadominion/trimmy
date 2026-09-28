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

Tradeable tokens are found automatically by the token directory (`apps/api/src/stock-token-directory.ts`); nobody approves a token by hand. A token qualifies when two independent sources agree: the Market's curated source (Tokens.xyz) lists it as a stock, fund or commodity token, and its mint carries the pinned identity of a supported issuer (metadata, mint, freeze and delegate authorities, metadata host, decimals) with rules that allow ordinary transfers. On-chain keys alone can be copied onto a lookalike mint, so the listing is required. The directory sweeps the catalog every 30 minutes and checks a new token the moment an order names it. Every order is then reviewed and simulated, and refused when its price is more than 3% worse than Jupiter's market price plus the token's fees (or, with no market price, when Jupiter's price impact exceeds 5%). `stock-trading-registry.generated.ts` seeds the directory with tokens proven earlier; entries are never deleted, only suspended, so holdings and history keep recognizing them.

Issuer disclosures, eligibility attestations and offer decisions live in `apps/api/src/stock-issuers.ts`. The preview endpoint refuses a quote until the user has accepted the current attestation for that issuer, and it refuses a buy if the token's transfer fee has risen above the admitted one. Capabilities v2 (`/v1/trading/capabilities?schema=2`) publishes the tradeable assets, every issuer's disclosure with whether Trimmy offers it, and a reason for each Market token that cannot be traded. Version 1 keeps the xStocks-only contract that installed apps expect.

Every token in capabilities v2 carries its market state (`apps/api/src/stock-market-state.ts`): most trade around the clock; Ondo's trade in the US sessions Ondo lists for each token. Ondo's live status page (`ondo-market-status.ts`) decides, the session calendar (`us-equity-calendar.ts`) is the fallback, and a mint paused on chain reads as paused by its issuer. The app disables ordering while a token is closed and says when it opens.

Each admitted token has one route. Most use Jupiter's aggregator. Tokens whose liquidity exists only with market makers, such as Ondo's, use JupiterZ RFQ orders: a market maker quotes a fixed price, pays the network fee and signs after the user. The review decodes the order engine's `fill` instruction, requires the maker's own accounts on the other side and the exact quoted amounts, and simulates. Ondo's makers mint just in time, after the user signs; a buy's simulation may then stop at the maker's delivery, which the review accepts only when the logs prove the user's side ran and only the maker's transfer lacked funds. Aggregator routes may pass through a third token in the user's own account or close the user's wrapped SOL back to SOL; every other token account of the user's that a transaction touches must keep its balance in simulation. Because Solana identifies a transaction by its first signature, the maker's, settlement finds an RFQ transaction by looking for the user's signature among the wallet's recent transactions. Tokens with an issuer transfer fee widen the slippage tolerance by that fee, because Jupiter quotes before it; the simulated net delivery is what the review checks and the app shows.

The live stock adapter in `apps/api/src/live-stock-orders.ts` validates the route, amounts, approved programs and fees, simulates the prepared transaction, and reconciles submission on Solana. Its runtime capability is disabled unless explicitly configured. The staging Crossmint onramp binds checkout to a verified recipient and checks provider order status. Staging completion is not a mainnet deposit.

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
