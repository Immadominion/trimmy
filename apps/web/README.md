# Trimmy web product

The default entry is the new React/TypeScript practice product. It uses the same
API and paper ledger as the actual Flutter mobile app, with a web-native layout.
The public marketing website in `apps/site-v2` is separate.

## Run locally

From `trimmy/`, using the repository's Node 24 environment:

```sh
npm run dev:web
npm run test:web
npm run build:web
```

Open **http://127.0.0.1:4174/**. `.env.development` contains only public routing
configuration. The loopback-only Vite adapter forwards an allowlisted set of
practice and market requests to the deployed API. It uses the browser guest's
own credential; it contains no provider or server secret. Writes affect a real
server-backed **paper** desk, never a wallet or real-money balance.

## Current working slice

- Compact first day: welcome, pinned note, three real company choices, paper quote,
  confirmed receipt and Desk. Skip saves an empty desk; returning traders bypass it.
- Optional guest entry, without sign-in or automatic guest creation during browsing.
- Desk with actual paper cash, positions, expiring exact-token valuation and receipts.
- Paged Market, debounced company search, facts, token selection and real token charts.
- Paper buy/sell amount, expiring server quote, deliberate confirmation and durable receipt.
- Exact Max sell, quote/revision validation, duplicate-submit guards and recovery of an
  uncertain order using the original idempotency key after reload.
- Email/Google/X account sign-in, last-used method, guest claim and account restore.
- Company PFPs with the mobile coin treatment, useful Profile and saved trader editing.
- Illustrated Career with 20 sequential assignments, evidence/decision/handoff,
  saved notes, exact retry recovery and read-only filed work. Rank, Trims, streak
  and milestones use the same shared API as mobile.
- Mobile scenery, character-motion preference, reduced motion and four work cues
  with a persisted browser mute control.
- Browser history/deep links, keyboard chart inspection, responsive navigation,
  white/lilac mobile identity and the approved Sal v3 animation/poster.

Guest access is stored in this browser and scoped to the API. Blocked/corrupt
storage, an expired guest or a changed tab cannot silently create a replacement
desk. Writes require Web Locks so two tabs cannot race the command journal.
Paper amounts use exact fixed-point strings and shared domain arithmetic.

## Own money (Real mode)

Signed-in accounts can switch between Paper and Real, account by account, as on
mobile. The switch sits on the Home balance card; Home balances and holdings,
Fast buy, the Market's Tradeable markers and company order entry change
together, and Real is pine green with a "Real money" label wherever it shows.
Guests only ever see Paper; asking for Real (or Add money) sends them to sign
in and lands them in Real afterwards. The code lives in `src/product/money/`.

- **Wallet.** A Privy embedded Solana wallet, created only on "Create wallet".
  Setup refreshes the Privy user first, requires exactly one embedded wallet,
  then waits for the server's fresh context read to report the same address.
- **Holdings v2.** USDC is the cash headline, SOL is shown for fees, stock
  tokens are shown in shares (display scaling) with no invented value, and
  what an order can spend is shown apart from the total.
- **Add money.** Crypto deposit (Recommended): the linked wallet's Solana
  address as a QR code, with mobile's copy. Card funding is "Coming soon" and
  makes no request.
- **Live orders.** Every token the API's trading capabilities (schema 3) list,
  never a fixed set: the API admits tokens automatically, and a company page
  rereads the list when it opens. Sells have no per-token cap. The issuer's warning comes before the eligibility tick;
  the review shows the warning, terms, fees and expiry before Confirm; the
  wallet signs the exact reviewed transaction (one signer, or the taker's slot
  of a JupiterZ RFQ order); the order id is stored and read back before
  execute; a lost reply is reconciled by id and never resent. Market states,
  the market-maker minimum and maker delivery at fill are shown as on mobile.
- **History.** Submitted orders with explorer links; pending ones are
  reconciled by id.

**Entry points for other screens** (all from `src/product/money/money-api.ts`,
available anywhere under `ProductApp`, which mounts `MoneyProvider` per
signed-in account):

- `useMoney().openFundWallet()` opens the Add money sheet (crypto deposit,
  wallet creation included) and switches the account to Real, as mobile's
  `_openFunding` does. A first-day "fund wallet" step only needs this call.
- `<FundWalletSheet onClose={…}/>` (`fund-wallet-sheet.tsx`) is the same
  sheet as a component, for a screen that manages its own open state.
- `useMoney()` also gives `available` (signed in with an API), `real`,
  `setReal(value)`, the wallet state and `capabilities`.
- `requestRealAfterSignIn()` remembers, for ten minutes in this tab, that a
  guest chose Real before signing in.

Configuration: `VITE_TRIMMY_PRODUCT_API_URL`, `VITE_PRIVY_APP_ID` and the web
client's `VITE_PRIVY_APP_CLIENT_ID` (see
[the API and provider requests](../../docs/WEB_API_REQUESTS.md)). Locally the
relay forwards the money routes. Tests use recorded capabilities and Market
variants, real Ed25519 keys, a contract-faithful fake of the trading routes
and the API's own signature verifier; no test signs with a real wallet or
reaches mainnet.

## Android download prompt

Welcome, the first receipt and Profile recommend the mobile app. Until the
signed Android build is published, the prompt says **Download coming soon** and
links to Trimmy's launch updates. Set `VITE_TRIMMY_ANDROID_APK_URL` to the public
absolute HTTPS build URL, then rebuild/restart the web app. The same prompt will
show **Download for Android** and **APK download**. Downloads are never automatic;
an Android APK is not offered as an iPhone install.

To revisit the welcome without resetting a saved desk, open `/#welcome`.
Continue recognises an existing completed
introduction and returns to that desk without requiring another buy.

## Next milestones

[The current roadmap](../../docs/ARCHITECTURE.md)
tracks comments/reasons, following, complete trade history and hosted release
verification. [Current Career parity and the shared summary defect](../../docs/ARCHITECTURE.md)
records the assignment contract and remaining backend repair for people filing
before their first paper trade. Real-money trading is described below.

A production build needs `VITE_TRIMMY_PRODUCT_API_URL` set to a canonical HTTPS
API origin and the deployed web origin explicitly permitted by that API. The
local `/api` adapter is development-only and is not included in the static
bundle. Unconfigured production builds show an unavailable state. Hosting,
CORS coverage for newer routes, and genuine browser OAuth still need release
verification. Do not reuse the native Privy client ID for web.

## Source and evidence

- `src/product/`: new product UI, strict market/practice clients and durable session.
- `dev-api.ts`: bounded local adapter, same-origin/Host checks, route allowlist,
  isolated headers and request/response deadlines and size limits.
- `test/product-*.test.ts`: market contracts, relay boundaries, practice recovery
  and actual React journey tests.
- `public/trimmy/ASSETS.md`: exact mobile asset reuse and licensing provenance.
- `artifacts/verification/web-product-2026-09-24/` at the workspace root:
  live read evidence, build/test logs and browser walkthrough record.

The older wallet/research/sample workspace remains in `src/App.tsx` with its
regression tests and account modules. It is no longer the default entry and its
fictional fixtures are not imported by the new product. Existing verified
Privy token binding, account lifecycle and followed-stock contracts remain
available for the remaining web features.

## Wallet recovery

`/wallet-recovery` is a separate, client-only entry for the native app's Privy
Solana wallet. It does not start a guest desk or call the practice API. Configure
`VITE_PRIVY_APP_ID` for the same Privy application as mobile and a web-compatible
`VITE_PRIVY_APP_CLIENT_ID`; verify the deployed HTTPS origin in Privy before
opening the native entry. Never supply an app secret to this build.

The optional `#address=PUBLIC_SOLANA_ADDRESS` pins the expected linked wallet.
Invalid or mismatched addresses block export; direct visits require selection.
Sign-in disables signup and automatic wallet creation. The explicit recovery
button invokes [Privy's Solana React export
UI](https://docs.privy.io/wallets/wallets/export). It does not read tokens or keys,
copy an export result, or send one to the app, server or storage. Identity changes
clear selection and invalidate pending UI continuations. Only Privy's isolated
window displays the key; closing that window is not proof of a completed backup.

Serve this entry with no-store, no-referrer and frame-denial headers. The native
link stays disabled until the hosted page and provider sign-in have been checked.
Tests cover the mocked SDK boundary and account/target races; a successful build
is not evidence of a live key export. No live export is part of automated tests.
