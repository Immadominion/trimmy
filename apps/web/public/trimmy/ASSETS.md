# Trimmy web runtime assets

Copied byte for byte from the current mobile runtime and site-v2 font folders on 24 September 2026. Originals were not modified. No image generation, resizing, re-encoding, or font conversion occurred. `asset-manifest.json` records every origin, byte size and SHA-256; each destination was verified against its source.

## Runtime mapping

Paths below are served beneath `/trimmy/`. Retain the current white canvas, Dejanire reading/controls, sparse Bricolage headings and restrained motion.

| Runtime file | Bytes | Repository origin |
| --- | ---: | --- |
| `token-AAPLx.webp` | 1,578 | `trimmy/apps/mobile/assets/images/ui_review/wall-street-orbit/token-AAPLx.webp` |
| `token-TSLAx.webp` | 3,172 | `trimmy/apps/mobile/assets/images/ui_review/wall-street-orbit/token-TSLAx.webp` |
| `token-METAx.webp` | 3,860 | `trimmy/apps/mobile/assets/images/ui_review/wall-street-orbit/token-METAx.webp` |
| `ruby-pin-1.png` | 33,015 | `trimmy/apps/mobile/assets/images/ui_review/ruby-pin-1.png` |
| `curly-arrow.png` | 9,252 | `trimmy/apps/mobile/assets/images/ui_review/curly-arrow.png` |
| `trimmy-mark.png` | 106,701 | `trimmy/apps/mobile/assets/images/ui_review/trimmy-mark.png` |
| `sal-chair-welcome-v3.webp` | 1,229,330 | `trimmy/apps/mobile/assets/images/ui_review/sal-chair-welcome-v3.webp` |
| `sal-chair-welcome-v3-still.png` | 263,522 | `trimmy/apps/mobile/assets/images/ui_review/sal-chair-welcome-v3-still.png` |
| `sal-neutral-v2.png` | 159,077 | `trimmy/apps/mobile/assets/images/cast/sal-neutral-v2.png` |
| `persona-wolf-avatar-v1.png` | 837,413 | `trimmy/apps/mobile/assets/images/ui_review/persona-wolf-avatar-v1.png` |
| `persona-oracle-avatar-v1.png` | 980,982 | `trimmy/apps/mobile/assets/images/ui_review/persona-oracle-avatar-v1.png` |
| `persona-shark-avatar-v1.png` | 994,607 | `trimmy/apps/mobile/assets/images/ui_review/persona-shark-avatar-v1.png` |
| `rookie-briefcase-v1.png` | 1,263,922 | `trimmy/apps/mobile/assets/images/ui_review/rookie-briefcase-v1.png` |
| `icons/nav-plumpy-market-shop.png` | 970 | `trimmy/apps/mobile/assets/images/ui_review/icons8/nav-plumpy-market-shop.png` |
| `icons/nav-plumpy-desk.png` | 809 | `trimmy/apps/mobile/assets/images/ui_review/icons8/nav-plumpy-desk.png` |
| `icons/nav-plumpy-career.png` | 909 | `trimmy/apps/mobile/assets/images/ui_review/icons8/nav-plumpy-career.png` |
| `icons/nav-plumpy-profile.png` | 976 | `trimmy/apps/mobile/assets/images/ui_review/icons8/nav-plumpy-profile.png` |
| `icons/nav-plumpy-desk.gif` | 27,059 | `trimmy/apps/mobile/assets/images/ui_review/icons8/nav-plumpy-desk.gif` |
| `icons/nav-plumpy-profile.gif` | 22,988 | `trimmy/apps/mobile/assets/images/ui_review/icons8/nav-plumpy-profile.gif` |
| `icons/account-apple-rounded.png` | 1,230 | `trimmy/apps/mobile/assets/images/ui_review/icons8/account-apple-rounded.png` |
| `icons/account-google-rounded.png` | 1,488 | `trimmy/apps/mobile/assets/images/ui_review/icons8/account-google-rounded.png` |
| `icons/account-email-rounded.png` | 834 | `trimmy/apps/mobile/assets/images/ui_review/icons8/account-email-rounded.png` |
| `icons/account-x-standalone-rounded.png` | 1,332 | `trimmy/apps/mobile/assets/images/ui_review/icons8/account-x-standalone-rounded.png` |
| `icons/settings-gear.png` | 1,214 | `trimmy/apps/mobile/assets/images/ui_review/icons8/settings-gear.png` |
| `icons/settings-sound.png` | 803 | `trimmy/apps/mobile/assets/images/ui_review/icons8/settings-sound.png` |
| `icons/settings-haptics.png` | 1,452 | `trimmy/apps/mobile/assets/images/ui_review/icons8/settings-haptics.png` |
| `icons/settings-lock.png` | 1,063 | `trimmy/apps/mobile/assets/images/ui_review/icons8/settings-lock.png` |
| `icons/profile-edit.png` | 1,015 | `trimmy/apps/mobile/assets/images/ui_review/icons8/profile-edit.png` |
| `icons/plumpy-forward.png` | 835 | `trimmy/apps/mobile/assets/images/ui_review/icons8/plumpy-forward.png` |
| `fonts/DejanireSans-Regular.otf` | 103,120 | `trimmy/apps/mobile/assets/fonts/dejanire/DejanireSans-Regular.otf` |
| `fonts/DejanireSans-Medium.otf` | 102,032 | `trimmy/apps/mobile/assets/fonts/dejanire/DejanireSans-Medium.otf` |
| `fonts/DejanireSans-Bold.otf` | 104,520 | `trimmy/apps/mobile/assets/fonts/dejanire/DejanireSans-Bold.otf` |
| `fonts/BricolageGrotesque-Latin.woff2` | 82,332 | `trimmy/apps/site-v2/public/fonts/BricolageGrotesque-Latin.woff2` |
| `fonts/BricolageGrotesque-OFL.txt` | 4,403 | `trimmy/apps/site-v2/public/fonts/BricolageGrotesque-OFL.txt` |

Brand mark: `trimmy-mark.png` is the actual current mobile 512×512 transparent Trimmy mark, copied unchanged from `trimmy/apps/mobile/assets/images/ui_review/trimmy-mark.png` (106,701 bytes). Use `/trimmy/trimmy-mark.png`. It visually matches the smaller site-v2 mark; no raster resizing was done here.

## Onboarding note decorations

The current mobile short note uses `curly-arrow.png` and `ruby-pin-1.png`, now available at `/trimmy/curly-arrow.png` and `/trimmy/ruby-pin-1.png`. The arrow is 512×512; the pin is 472×488. These are exact copies of the existing runtime PNGs. The pin was already a raster copy of the repository SVG; this pass performs no rasterization or edits. Source provenance is documented in `docs/SESSION_HANDOFF.md`; the actual production `ProductIntroduction` reuses `lib/ui_review/review_welcome_note.dart`.

The white rim/lilac inset note is layout, not a new background image. Preserve the short finite entrance, settle immediately for reduced motion, and keep the pin/arrow decorative. Current copy/navigation comes from `docs/design/STARTUP_NAVIGATION.md`. These pre-existing note decorations do not carry a newly asserted open-source license in this copy.

| File | SHA-256 (source and copied destination) |
| --- | --- |
| `curly-arrow.png` | `39f99d95a0f3bcc68752f1fd92348defe8411b0ede7ac621a52f6c15179f8d71` |
| `ruby-pin-1.png` | `0c91cdb349cb043a6bf84fcfbcac3cd603ac1abb8492ec6e5b414558e65cea37` |

## Company token images

`token-AAPLx.webp`, `token-TSLAx.webp` and `token-METAx.webp` are byte-for-byte copies of the approved mobile Wall Street orbit images. Use them only for the corresponding exact variant symbols; retain real API company names and a fallback for other variants. They are Tokens.xyz identity images, not newly generated company artwork. The pinned source record is `trimmy/art/studies/welcome-orbit-2026-09-23/token-sources/manifest.json`, which records provider URLs, variant mints and hashes. Mobile, pinned provider source and web copy hashes match. No additional trademark/image license grant is asserted by copying the existing assets.

| File | Bytes | SHA-256 (source and copied destination) |
| --- | ---: | --- |
| `token-AAPLx.webp` | 1,578 | `bd8d24b623585e72dd0f317d50b5c4e5ff1a67a8baba1eb839d85f4c4ca95e36` |
| `token-TSLAx.webp` | 3,172 | `0724237d5386ce7eba1a9f59ea1b5b4fda7cd4c904c05868ced64432bf2db946` |
| `token-METAx.webp` | 3,860 | `f01dfdf631640e31cf76ad2c04ea0a457f125469d22dcb070fbbaa3159197db6` |

## Chair animation

`sal-chair-welcome-v3.webp` and `sal-chair-welcome-v3-still.png` are the exact current mobile q92 delivery pair. The take is 960×800 with genuine alpha, 3,499 ms encoded, 64 encoded frames (84 authored frames at 24 fps with identical held poses merged), and loop count 1. Play once on the intended screen entry; leave the matching settled poster afterward. Do not remount/restart the image during unrelated state updates. Use only the still when `prefers-reduced-motion: reduce` is set; provide an image-error fallback to the still as well.

The poster matches the actual decoded final WebP frame. Sal makes a head glance/nod beside a separately swiveling chair. This is not a camera orbit, facial-expression rig or tracked hand contact. Source, source-frame checks and runtime export validation are retained under `trimmy/art/studies/parallel-ui-iphone/sal-fal-pilot-2026-09-24/sign-in-chair-v3/`. The lower-quality old v2 animation is intentionally absent from this set.

## Font notices and unresolved permissions

- **Bricolage Grotesque:** the source includes SIL Open Font License 1.1, copyright 2022 The Bricolage Grotesque Project Authors. The exact accompanying notice is copied as `fonts/BricolageGrotesque-OFL.txt`; preserve it with the font. This copy is the existing site-v2 Latin WOFF2, not a new conversion of the mobile TTF. Follow the notice's redistribution and reserved-name conditions if later modifying or redistributing the font.
- **Dejanire Sans:** Regular, Medium and Bold OTF files were supplied locally by the user and are already bundled in mobile. `docs/SESSION_HANDOFF.md` records that provenance. No Dejanire EULA, invoice, license file, or permission for self-hosted web embedding was found in the inspected font folder and repository font notes. Copying existing files does not establish such a grant. Treat web redistribution/embedding entitlement as unresolved before public deployment; do not describe these as OFL or freely redistributable. The mobile font README's OFL statement describes its listed Google Fonts families, not these later-added Dejanire files.

## Art and Icons8 provenance

The Sal, persona and Rookie images are existing project-generated Trimmy artwork. Their local source records establish origin, not an open-source license grant; no separate blanket asset license was found in this pass. The Fal/Meshy model and texture history is recorded in the Sal pilot. No new provider calls were made.

- Sal identity: `trimmy/apps/mobile/assets/images/cast/sal-neutral-v2.png`; pilot reference provenance at `trimmy/art/studies/parallel-ui-iphone/sal-fal-pilot-2026-09-24/reference-provenance.json`.
- Persona portraits: originals/prompts under `trimmy/art/studies/parallel-ui-iphone/character-animation-2026-09-24/avatars/`; mobile byte-match record in `trimmy/art/studies/parallel-ui-seeker/desk-persona-pfps-2026-09-24.md`.
- Rookie briefcase and settings utilities: `trimmy/art/studies/parallel-ui-seeker/profile-rank-2026-09-24/ASSETS.md`.
- Navigation: Desk/Profile source records in `trimmy/art/studies/parallel-ui-seeker/desk-v2-2026-09-24/ICONS8.md`; Career in `trimmy/art/studies/parallel-ui-seeker/market-v2-2026-09-24/ICONS8.md`; Market Shop in `docs/design/BUY_SELL_PASS_2026-09-24.md`.
- Sign-in icons: `trimmy/art/studies/parallel-ui-iphone/sign-in-icons-2026-09-24.json` and `sign-in-x-standalone-2026-09-24.json`.

Icons8 is the publisher of the copied nav/account/utility icons. The inspected local records identify catalogue/CDN sources but do not include an Icons8 purchase entitlement or applicable redistribution/attribution license. Retain source attribution records and verify the project's existing entitlement/required credit before public release; this asset copy does not invent a grant. Apple, Google and X marks also remain their respective brand marks.

Current source catalogue identities:

| Asset | Source catalogue |
| --- | --- |
| Market Shop | https://icons8.com/icon/6T6IHsKRCex4/shop |
| Desk | https://icons8.com/icon/HrPdlcIGvAy3/home |
| Career | https://icons8.com/icon/d3t7YzH6uz0N/briefcase |
| Profile | https://icons8.com/icon/3WOdQWsvoKMC/person |
| Apple | https://icons8.com/icon/101403/mac-os |
| Google | https://icons8.com/icon/85795/google-logo |
| Email | https://icons8.com/icon/85500/new-post |
| X standalone | https://icons8.com/icon/Q33YQBzI2lZs/twitterx--v2 |
| Settings | https://icons8.com/icon/aPtgRkkLiNl2/settings |
| Sound | https://icons8.com/icon/WupqaUCz76vQ/sound |
| Haptics | https://icons8.com/icon/15g41hZd9jPC/shake-phone |
| Lock | https://icons8.com/icon/kIbLxKLhgEdA/lock |
| Profile edit | https://icons8.com/icon/ZoV7kTmPeAqA/edit |

`plumpy-forward.png` is copied from the existing Icons8 mobile directory; no exact catalogue ID was established in the inspected records, so none is invented here.

Desk and Profile have their current official GIF/still pairs. Career uses the current briefcase PNG; the stale Career medal GIF was not copied. Market Shop is a still asset. Any finite CSS motion for these stills must respect reduced motion and must not be described as authored GIF animation. Account provider icons are static PNGs.
