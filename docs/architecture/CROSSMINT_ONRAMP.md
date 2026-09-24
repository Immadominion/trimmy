# Crossmint funding

Implemented September 24, 2026. Staging credentials are configured on the Railway API service. No live payment has been submitted or claimed as tested.

## User flow

Add money (Desk, first-stock follow-up, or Settings) → create/reuse the existing Privy Solana wallet → Pay by card or Transfer crypto.

Card: USD amount and receipt email → verify ownership of the receiving wallet when needed → Crossmint checkout in the system browser → return to Trimmy → verify delivery. Crossmint handles card entry, its supported wallet payment methods, identity checks, geographic eligibility and fee presentation. Bank transfer is not advertised by this integration.

Transfer: existing Solana address, copy action, USDC/SOL balance and explicit refresh remain available. Live stock execution remains controlled by its separate existing verifier and feature gate; enabling funding does not enable trades.

## API configuration

Set these on the API service, never in Flutter build defines:

```
CROSSMINT_ENVIRONMENT=staging
CROSSMINT_SERVER_SIDE_API_KEY=<server key>
CROSSMINT_CLIENT_SIDE_API_KEY=<client key>
```

Use server scopes `orders.create`, `orders.read`, `users.create`; client scope `orders.read`. Both keys must belong to the same project and environment. The server fails configuration if key environment prefixes disagree. Omitted/disabled environment leaves card funding unavailable. Staging uses Solana devnet USDC; production uses Solana mainnet USDC. Production requires Crossmint approval and Onramp enablement, not only keys.

The mobile client obtains its scoped public client key with its authenticated order response. The secret server key never crosses the API boundary. Local development may load a gitignored `.env.crossmint` with the existing API environment; do not place secret values in this document, `.env.example`, chat or client code.

## Integration boundaries

- `/v1/funding/capabilities`: public availability and environment.
- Authenticated POST `/wallet`: server derives the recipient from Privy's verified linked-wallet record. It links that wallet to the receipt-email identity at Crossmint and returns the ownership challenge.
- POST `/verify`: local Ed25519 verification of the exact Crossmint challenge, followed by Crossmint verification. The mobile signer is message-only and rechecks account identity before and after native signing.
- POST `/orders`: fixed USDC mint, fixed Solana chain, bounded USD amount, server-derived wallet. Creates an unpaid order; no payment-processing API is exposed.
- POST `/status`: authenticated server lookup, with an account-bound signed grant. Success requires completed Solana delivery to the expected wallet, rather than payment completion or a browser callback.

Grants are authenticated, environment-bound, purpose-bound, time-limited and tied to the Trimmy account. Challenges live for 10 minutes; verified-wallet grants for one hour; order status grants for 24 hours. API responses are no-store. Provider bodies and raw errors are not logged or returned. No card/KYC documents enter Trimmy.

The app persists unfinished checkout credentials in platform secure storage under the account ID before opening the browser. Reopening resumes that order. Creation is never automatically retried; same-instance replay IDs reuse the unpaid order. The in-memory replay cache does not guarantee idempotency across API restarts; an uncertain creation can leave an unused unpaid provider order, but cannot charge a card. Delivery remains at the provider/wallet even if the app closes. Production operational follow-up should add durable order records and webhook reconciliation for longer history/support beyond the current status-grant window.

## Build and verification

`url_launcher` was added for system-browser checkout. The Seeker needs a normal native rebuild of its existing actual-app configuration before the payment handoff can run; hot reload alone cannot register the new plugin. Do not install an APK compiled without the existing account/API defines.

Local checks cover environment mismatch, guest rejection, forged proofs/grants, server-bound recipient and mint, invalid amounts, duplicate unpaid orders, pending versus completed delivery and cross-account status access. Flutter checks cover guest opt-in, first-trade recovery, reminder decisions, checkout URL environment and message-only challenge validation. Native Android compile succeeded. Live provider checkout, eligibility, KYC and actual funds delivery await configured credentials and an approved environment.

Staging activation verification (September 24): Crossmint accepted an ephemeral test wallet, verified its signed ownership challenge, created an unpaid $10 order (HTTP 201), and returned pending order status (HTTP 200). Railway deployment `94a0c66d-2e22-4663-a0f7-70b2eb4629b8` reached SUCCESS. The public capabilities endpoint reports staging/USDC/Solana; unauthenticated wallet requests return 401. All 649 API tests and both mobile onramp tests passed. Completed card payment, client checkout authorization and token delivery remain unverified. Staging funds do not increase the mainnet balance or enable live stock execution.

The first-stock handoff also persists reminder choices and requests Android notification permission. Reminder delivery/scheduling is not implemented by this funding work; do not claim those preferences already schedule notifications.

## Official references

- https://docs.crossmint.com/onramp/quickstarts/flutter
- https://docs.crossmint.com/onramp/guides/onramp-to-external-wallets
- https://docs.crossmint.com/api-reference/users/link-wallet
- https://docs.crossmint.com/onramp/api-reference/create-order
- https://docs.crossmint.com/onramp/api-reference/get-order
- https://docs.crossmint.com/payments/embedded/guides/webview-integration
- https://docs.crossmint.com/onramp/concepts/payment-methods
- https://help.crossmint.com/articles/2804023362-how-do-i-get-production-access-to-crossmint
