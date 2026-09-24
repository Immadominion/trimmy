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
