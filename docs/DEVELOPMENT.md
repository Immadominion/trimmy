# Development

## Tools

Node 24 and npm 10.9.8 are pinned at the root. Flutter 3.44.2 / Dart 3.12.2 is pinned in `.flutter-version`. Native Android and iOS builds also need their normal platform SDKs. PostgreSQL binaries are required for the isolated database harnesses.

```bash
npm ci
node tool/prepare-public-assets.mjs
npm run build:backend
```

The font preparation command changes missing commercial-font references to the bundled OFL Manrope font. It also substitutes original Trimmy sound cues for library mixes that cannot be redistributed with source, and silences the marketing preview's licensed crowd bed. It does not overwrite licensed files when they exist. Public builds will therefore differ typographically from the product screenshots. Do not commit private font binaries.

## API

```bash
npm run dev:api
```

This starts the API at `http://localhost:4100`. Without configuration, authenticated persistence and external providers are unavailable. The server does not automatically load `.env`:

```bash
cp .env.example .env
# Fill only the settings needed for your own environment.
npm run build:backend
node --env-file=.env apps/api/dist/index.js
```

Persistent gameplay requires `PRACTICE_DATABASE_URL`, `PRIVY_APP_ID` and `PRIVY_VERIFICATION_KEY`. Linked-wallet operations additionally use the server-only Privy secret and their explicit capability settings. Provider keys, authenticated RPC URLs and database credentials belong on the API server, never in Dart defines or Vite variables.

Use `.env.example` as the configuration reference. Apply migrations with a separate privileged connection using `npm run db:migrate`; run the API with the restricted role. TLS verification is required. See [database setup and tests](../infra/README.md). Never point test harnesses at a production database.

## Flutter app

```bash
cd apps/mobile
flutter pub get --enforce-lockfile
cp account-config.example.json account-config.local.json
```

Set the public Privy app/client identifiers and API URLs in that ignored JSON file, then:

```bash
flutter run --flavor production --dart-define-from-file=account-config.local.json
```

A physical phone needs an API endpoint reachable from the phone; `localhost` refers to the phone itself. Configure native auth callback schemes and provider origins for your own app. The default `main.dart` is the actual product. `ui_review.dart` and `design_study.dart` are separate historical review entries.

### Wallet backup configuration

The optional `TRIMMY_WALLET_RECOVERY_URL` stays empty until browser recovery is configured and verified. The current native link accepts only `https://web-production-e8138.up.railway.app/wallet-recovery`; changing hosts also requires updating that allowlist and its tests. The app passes only the expected public address in a URL fragment. Browser sign-in is independent of the native session.

The recovery page needs a **web** Privy client under the same app, with its exact HTTPS origin allowed. Do not reuse or relax the native-only client, create another wallet, or put a server secret in either app. Configure `VITE_PRIVY_APP_CLIENT_ID` on the web service, rebuild, verify sign-in and wallet matching, then enable the native URL. See [web recovery](../apps/web/README.md).

### Android wallet funding

**Add money → Crypto → Transfer from wallet** uses the official Android Mobile Wallet Adapter client SDK, pinned to `com.solanamobile:mobile-wallet-adapter-clientlib-ktx:2.0.7`. A compatible external wallet signs and broadcasts a reviewed SOL or USDC transfer on Solana mainnet. The recipient remains the signed-in user's Privy embedded wallet: this does not change Trimmy authentication, the account wallet or the stock-trade signer. iOS and web do not expose this adapter flow.

Funding is disabled by default. In addition to the existing authenticated Solana adapters and `TRIMMY_LIVE_STOCKS=solana_mainnet`, configure the API environment:

```dotenv
TRIMMY_MWA_FUNDING=enabled
# Inject TRIMMY_WALLET_REVIEW_KEY from the server's secret store.
```

`TRIMMY_WALLET_REVIEW_KEY` must be an independent, cryptographically random 32-byte key encoded as exactly **64 hexadecimal characters**. It is required when funding is enabled. Keep it server-only; never reuse a provider credential or put it in Dart defines, source, logs or the example environment file. Preserve the same key across replicas and restarts: rotating it invalidates outstanding review receipts and prevents their recovery.

The app checks `/v1/wallet/funding/capabilities` before offering new transfers. Signing reviews expire after 90 seconds; exact-transaction status checks remain available afterward. Confirmation updates the balance automatically. An interrupted wallet handoff retains a pending record rather than automatically sending again. Disabling new funding keeps status reconciliation available while the adapters and review key remain configured.

The production Digital Asset Links certificate mapping for `com.trimmy.trimmy` is maintained in the marketing site's branch and must be served at `https://trimmy.xyz/.well-known/assetlinks.json`. Verify that it matches the submitted APK's signing certificate; building this mobile branch does not publish that mapping.

Local tests and the APK build do not prove a physical transfer. Before enabling this flow for users, verify connection, review, approval, return-to-app, cancellation/reconnect and interrupted-transfer recovery on a compatible Android wallet. Separately verify an explicitly authorized transfer's onchain recipient, amount and automatic balance update. No completed physical-wallet transfer is claimed here.

### Android signing and the development Seeker

For a local release-mode update to a Seeker already using your debug certificate, explicitly retain that certificate:

```bash
TRIMMY_DEVICE_DEBUG_SIGNING=true flutter run --flavor production --release --dart-define-from-file=account-config.local.json
```

This override is for that development device only. Distributable releases require release signing configured through ignored `apps/mobile/android/key.properties`, with the keystore kept outside the repository. Leave `TRIMMY_DEVICE_DEBUG_SIGNING` unset for distribution; release builds fail when signing is missing.

Never uninstall or clear the funded app to resolve a signing mismatch. Stop and use the certificate that matches the installed app. The override does not make different debug certificates compatible.

## Web and marketing

```bash
cp apps/web/.env.example apps/web/.env.local
npm run dev:web
```

The web product uses port 4174. Supply your API origin and public client identifiers. The development relay supports `/api` only in local development; production needs the exact HTTPS origin permitted by the API. Do not use the original developer's deployment as a test backend.

The marketing site has its own package:

```bash
cd apps/site-v2
npm ci
npm run dev
```

## Checks

```bash
npm run check
npm run test:practice-db
npm run test:migration-db
npm run test:deployment
```

```bash
cd apps/mobile
flutter analyze
flutter test
```

The database scripts create disposable clusters inside ignored runtime folders. They do not require production credentials. Content integrity checks ensure authored definitions and generated Dart/TypeScript representations stay aligned.

Before publishing, run `gitleaks dir --redact .` against a clean export, inspect `git diff --cached`, and verify that private config, raw commercial fonts, build products and local audit artifacts are absent. `.github/workflows/verify.yml` runs the public build checks.
