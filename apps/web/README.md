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
before their first paper trade. Real-money trading remains unavailable.

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
