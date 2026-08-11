# Trimmy landing page — complete asset prompt pack

This document maps the page's `data-asset-id` hooks plus its reusable background and social assets. It is the production brief for every generated illustration, texture, product render, sticker, and sourced ecosystem mark on the landing page.

Optimized runtime files live under `site/assets/`. High-resolution masters, chroma-key sources, rejected iterations, and generation helpers live outside the deploy root under `design/landing-assets/`.

## Delivery status

- Complete: 23 runtime art assets, five first-party ecosystem vectors, and the 1200×630 social preview.
- Every raster illustration is available as AVIF with WebP fallback; opaque backgrounds use the smaller suitable format through CSS `image-set()`.
- The hero rule card and builder window remain live HTML, as specified.
- The optional Trimmy mark sticker, 16-piece doodle pack, individual doodles, and retained alternates live in `design/landing-assets/` and are not shipped.
- Official XRP faceplates are applied deterministically from `design/landing-assets/brand/xrpl-symbol-black.svg` by `design/landing-assets/sources/composite_xrp_faceplates.py`; the mark is never reconstructed by the image model.

The supplied MOONDU page is a style reference only. Do not reproduce its education imagery, wording, branding, or exact composition. Translate its visual grammar—poster typography, graph paper, saturated slabs, hard shadows, stickers, and playful 3D objects—into Trimmy’s product language: conditions, watching, actions, boundaries, privacy, XRP, and self-custody.

## The production split

Generate:

- Object illustrations, sticker bases, textures, doodles, and the closing collage.
- Optional art-direction renders of the product surfaces for visual reference.

Keep in HTML, SVG, or Figma typography:

- Every headline, label, number, rule value, status, button, chart label, and trust statement.
- The hero rule card and rule-builder window.
- Dashed frames, background grids, card connectors, and circular seal typography.

Source from official files:

- XRPL/XRP, Flare, FAssets, and FTSO marks.
- The existing Trimmy mark geometry.

This split is important. Generated words are unreliable, inaccessible, difficult to update, and often look fake. The page can still use generated shells or supporting illustrations, but meaningful product information must remain crisp live content.

## Global art bible

Prepend this block to every generated-asset prompt below:

```text
Create a production web asset for Trimmy, a professional non-custodial XRP automation product.

ART DIRECTION: bold editorial poster design with playful retro-space mechanics. Combine crisp flat-vector linework, cut-paper sticker shapes, restrained screen-print grain, and selectively used soft clay-like 3D volume. Every main object has a strong 8px near-black contour, a consistent hard shadow offset 12px down and 12px right, and a few small hand-drawn signal marks. Use deliberate asymmetry and a commercially art-directed composition. It should feel energetic and confident, never childish or like a generic crypto campaign.

PALETTE:
near-black ink #191918
charcoal paper #242423
warm ivory #F6F3EC
Trimmy periwinkle #A0B4FA
electric violet #6975F6
deep violet #4D42D7
signal yellow #FFD34E
verified mint #68D8A7
acid lime #9BDC55
hot pink #ED78DB
tangerine #FF8A51

Use no more than two bright colours plus charcoal and ivory in one individual asset. Violet is the dominant product colour, yellow indicates a trigger or attention, mint indicates a verified result, pink indicates privacy, and lime indicates a hard boundary. Lighting on every 3D object comes from the upper left. Use the same three-quarter camera angle, approximately 25 degrees downward, across the complete set. Keep at least 12 percent transparent safe padding on every edge. Produce crisp high-resolution edges suitable for a professional website.
```

Append this negative prompt to every generated asset:

```text
NEGATIVE: no MOONDU branding, no education copy, no pencils, books, graduation caps, cameras, classrooms or school symbols; no copied arrangement from the reference; no stock illustration; no photorealism; no glassmorphism; no transparent glass cards; no neon haze; no purple-blue gradient fog; no gummy blob mascot; no generic corporate SaaS 3D; no thin outlines; no soft floating blob background; no anime; no childish face; no crypto casino imagery; no gold coin rain; no Bitcoin or Ethereum symbols; no distorted XRP symbol; no moon, lambo or trading-bro imagery; no watermark; no extra words; no misspelled text; no clipped object; no rectangular background unless explicitly requested.
```

## Export rules

- Generate transparent PNG masters for isolated objects, then export production WebP and AVIF versions.
- Generate opaque textures as seamless WebP masters.
- Work at 2× the displayed CSS size. Do not upscale a smaller result.
- Use sRGB. Preserve clean unpremultiplied alpha with no white fringe.
- Keep the hard shadow inside the canvas safe area.
- Lock the same image model, lighting reference, outline thickness, and camera angle for the full set.
- Generate the three rule objects first. Reuse them as visual references for lifecycle, security, builder, and closing assets.
- Supply the official Trimmy and XRP/XRPL SVGs as image references wherever a faceplate needs those marks. Do not ask the model to reconstruct either logo from memory.
- Decorative illustrations receive `alt=""`. Product information remains available in adjacent live HTML.

## Integration convention

- Preserve the existing `data-asset-id` on each page slot.
- Replace a slot’s CSS fallback with an `<img>` or `<picture>` inside that same element; do not remove the surrounding semantic copy.
- Give every file explicit intrinsic `width` and `height`. Lazy-load below-the-fold assets, but load the hero rule support art eagerly.
- Use `object-fit:contain` for isolated transparent objects. Never crop their contour or hard shadow.
- Keep `UI-HERO-RULE-CARD` and `UI-RULE-BUILDER-WINDOW` as live components. Generated references are for art direction, not final raster replacements.
- When a generated illustration contains a blank token faceplate, composite the official XRP mark in Figma before export instead of placing a second DOM image over it.

## Asset manifest

| Asset ID | Suggested production file | Master size | Background | Role |
|---|---|---:|---|---|
| `BRAND-TRIMMY-MARK-STICKER` | `design/landing-assets/library/trimmy-mark-sticker.webp` | 1024×1024 | transparent | Optional poster treatment; not shipped |
| `BG-DARK-GRAPH-GRID` | `assets/art/texture-dark-grid.webp` | 1920×1920 | opaque seamless | Hero and dark poster sections |
| `BG-CHARCOAL-PAPER-TEXTURE` | `assets/art/texture-charcoal-paper.webp` | 2048×2048 | opaque seamless | Printed paper character |
| `BG-LIGHT-GRAPH-GRID` | `assets/art/texture-light-grid.webp` | 1920×1920 | opaque seamless | Closing CTA and footer |
| `DOODLE-NAV-CONTACT-RING` | `assets/art/nav-ring.svg` | 900×500 | transparent | Hand-drawn nav CTA ring |
| `DOODLE-NAV-ARROW` | `assets/art/nav-arrow.svg` | 600×600 | transparent | Nav CTA pointer |
| `DOODLE-ORBIT-PACK` | `design/landing-assets/library/doodle-pack.webp` | 1254×1254 | transparent | Reusable library pack; not shipped |
| `STICKER-RULE-SEAL` | `assets/art/rule-seal.webp` | 900×900 | transparent | Hero “set once / stays ready” seal |
| `STICKER-NO-CUSTODY` | `assets/art/no-custody-sticker.webp` | 1100×700 | transparent | Hero custody callout |
| `STICKER-ALWAYS-WATCHING` | `assets/art/watching-sticker.webp` | 1100×700 | transparent | Lifecycle callout base |
| `ART-HERO-WATCHER-RADAR` | `assets/art/hero-watcher-radar.webp` | 1200×1200 | transparent | Always-on watching object |
| `ART-HERO-RULE-ROCKET` | `assets/art/hero-rule-courier.webp` | 948×850 | transparent | Rule entering an always-on orbit |
| `UI-HERO-RULE-CARD` | live HTML; optional `hero-rule-card-reference.png` | 1600×1400 | transparent | Rich example rule product surface |
| `ART-RULE-PRICE-TARGET` | `assets/art/rule-price-target.webp` | 1200×900 | transparent | Price-rule tile object |
| `ART-RULE-SCHEDULE-LOOP` | `assets/art/rule-schedule-loop.webp` | 1200×900 | transparent | Scheduled-rule tile object |
| `ART-RULE-PRIVATE-VAULT` | `assets/art/rule-private-vault.webp` | 1200×900 | transparent | Private-rule tile object |
| `ART-LIFECYCLE-REVIEW` | live HTML plus `assets/art/lifecycle-review.webp` | 1200×900 | transparent | Review state supporting object |
| `ART-LIFECYCLE-WATCH` | live HTML plus `assets/art/lifecycle-watch.webp` | 1200×900 | transparent | Watching state supporting object |
| `ART-LIFECYCLE-ACT` | live HTML plus `assets/art/lifecycle-act.webp` | 1200×900 | transparent | Execution state supporting object |
| `ART-PRIVATE-COMPUTE-CORE` | `assets/art/private-compute-core.webp` | 1500×1000 | transparent | Confidential-compute scene |
| `ART-SECURITY-NO-KEYS` | `assets/art/security-no-keys.webp` | 900×900 | transparent | Key stays outside the system |
| `ART-SECURITY-NO-CUSTODY` | `assets/art/security-no-custody.webp` | 900×900 | transparent | Funds do not sit with Trimmy |
| `ART-SECURITY-EXACT-LIMITS` | `assets/art/security-exact-limits.webp` | 900×900 | transparent | Amount/runs/expiry hard stops |
| `ART-BUILDER-XRP-COIN` | `assets/art/builder-setting-arm.webp` | 900×1350 | transparent | Builder left supporting object |
| `ART-BUILDER-LAUNCH-ROCKET` | `assets/art/builder-watcher.webp` | 900×1350 | transparent | Builder right supporting object |
| `UI-RULE-BUILDER-WINDOW` | live HTML; optional `rule-builder-reference.png` | 1600×1400 | transparent | Example builder product surface |
| `ART-CLOSING-AUTOMATION-COLLAGE` | `assets/art/closing-collage.webp` | 2200×1100 | transparent | Final CTA perimeter composition |
| `LOGO-XRPL` | `assets/brands/xrpl.svg` | vector | transparent | Ecosystem rail |
| `LOGO-FLARE` | `assets/brands/flare.svg` | vector | transparent | Ecosystem rail |
| `LOGO-FASSETS` | `assets/brands/fassets.svg` | vector | transparent | Ecosystem rail |
| `LOGO-FTSO` | `assets/brands/ftso.svg` | vector | transparent | Ecosystem rail |
| `ICON-CONFIDENTIAL-COMPUTE` | `assets/brands/confidential-compute.svg` | vector | transparent | Ecosystem rail |
| `OG-TRIMMY` | `assets/og-trimmy.png`; master at `design/landing-assets/og-trimmy-master.png` | 2400×1260 master; 1200×630 export | opaque | Social preview |

## Backgrounds and reusable system assets

### `BRAND-TRIMMY-MARK-STICKER`

```text
Use the supplied Trimmy triform mark as a mandatory silhouette. Preserve its exact outer geometry, proportions, orientation, and negative space. Reinterpret it as a premium enamel poster sticker: solid Trimmy periwinkle body, restrained deep-violet side shading, thick near-black contour, one tiny signal-yellow four-point highlight, and the standard hard down-right shadow. No face, eyes, mouth, limbs, text, or additional symbol. Centre the mark with 16 percent transparent padding. The output must still be recognisable as the original Trimmy mark when shown at 32 pixels.
```

### `BG-DARK-GRAPH-GRID`

```text
Create a perfectly seamless square charcoal poster-paper background. Base colour #191918 with a subtle fibrous surface, restrained screen-print ink-density variation, and a square grid every 160 pixels using 2px warm-gray lines at very low contrast. The grid must remain straight and usable behind text. Add only a few extremely faint rubbed diagonal marks near the perimeter. Keep the centre quiet. No focal object, symbols, stars, letters, border, vignette, gradient, spotlight, or visible tile seam.
```

### `BG-CHARCOAL-PAPER-TEXTURE`

```text
Create a perfectly seamless 2048-pixel charcoal paper texture with no grid. Use #242423 as the base. Add subtle recycled-paper fibres, tiny screen-print pigment irregularities, occasional soft rubbed patches, and sparse dry-brush traces no darker than six percent from the base. It must add physical print character without reading as digital TV noise. No scratches that resemble damage, no stains, no symbols, no lighting direction, and no vignette.
```

### `BG-LIGHT-GRAPH-GRID`

```text
Create a perfectly seamless warm-ivory editorial paper background. Base #F6F3EC with fine natural paper fibres and a square graphite grid every 160 pixels using restrained 2px lines. The grid should feel screen printed rather than mathematically sterile, while remaining straight and production clean. Keep enough contrast for the grid to remain visible at 25 percent scale. No object, word, stain, torn edge, shadow, or vignette.
```

### `DOODLE-NAV-CONTACT-RING`

```text
Create two imperfect concentric hand-drawn charcoal loops around an empty horizontal capsule-shaped safe area. The loops should feel drawn in one confident marker stroke, not wobbly or childish. Add three short signal ticks at the upper right. Transparent background, no words, no fill, no shadow. The empty centre must fit a 120 by 44 pixel button. Deliver as editable SVG paths as well as transparent PNG.
```

### `DOODLE-NAV-ARROW`

```text
Create one compact hand-drawn curved arrow that starts above and to the right, curls once, and points down-left toward a button. Use a charcoal dry-marker stroke with one small signal-yellow accent tick. Transparent background, no text, no circle, no shadow. Keep the arrow readable at 28 pixels.
```

### `DOODLE-ORBIT-PACK`

```text
Create a clean 4-by-4 sprite sheet containing sixteen isolated editorial doodles with generous spacing: four-point sparkle, three-line burst, curled arrow, dashed selection corner, elliptical orbit loop, small crosshair, double underline, lightning tick, dotted trail, tiny bracket, rough circle, short speed lines, check burst, measurement ticks, irregular star, and looping connector. Use strong near-black hand-inked strokes with occasional single-colour signal-yellow, violet, mint, or lime accents. No words. Elements must not touch. Also export each doodle as an individual SVG or transparent PNG.
```

## Hero assets

### `STICKER-RULE-SEAL`

```text
Create a circular acid-lime editorial seal with a slightly irregular screen-printed edge, thick near-black outline, double inner ring, tiny measurement ticks, and the standard hard shadow. Reserve a clean circular text path around the perimeter and a clear centre for an upward-right arrow. Production wording, typeset separately in SVG, is “SET ONCE” on the upper arc and “STAYS READY” on the lower arc. Generate the primary asset without letters so the typography can be exact. No extra icon, face, star, or gradient.
```

### `STICKER-NO-CUSTODY`

```text
Create an irregular tangerine ticket sticker, rotated about six degrees counter-clockwise, with a thick near-black contour, tiny perforation marks, one hard shadow, and a clear two-line type area. The production words, overlaid later as live SVG or HTML, are “NO” and “CUSTODY”. Add one small mint shield-check symbol at the lower edge. Generate the master without text. No wallet, hands, coin pile, or bank-vault cliché.
```

### `STICKER-ALWAYS-WATCHING`

```text
Create a compact violet ticket-shaped sticker with one clipped corner, an ivory dashed inner frame, thick near-black outline, green active-status dot, two yellow signal ticks, and a hard offset shadow. Leave a clear two-line area for context-specific live wording: “CLEAR FIRST”, “STILL WATCHING”, or “WITHIN LIMITS”. Generate the base without wording so one asset can support all three states. No eye, face, clock, or satellite inside the sticker.
```

### `ART-HERO-WATCHER-RADAR`

```text
Create a substantial mechanical monitoring instrument in three-quarter view. It has a compact periwinkle body, a circular forward-facing radar dish, deep-violet joints, a signal-yellow elliptical orbit, two small antenna fins, one mint live-pulse indicator, and a hand-drawn tangerine trajectory line. Put a clean blank circular faceplate at the centre for the supplied official XRP glyph to be composited later. It must communicate persistent watching without using an eye, face, surveillance camera, server, or alarm. The silhouette should remain legible between 120 and 220 CSS pixels.
```

### `ART-HERO-RULE-ROCKET`

```text
Create a professional mechanical rule courier travelling diagonally from upper right toward the hero product card. Its body is an ivory rule ticket with two blank stacked label strips and a bold directional arrow, held by a compact tangerine capsule with violet fins. A curved hand-drawn exhaust path contains three yellow signal ticks and one mint confirmation pulse. It should read as an approved instruction entering an always-on orbit, not as a cartoon toy rocket. No words, fireball, moon, starscape, or character face.
```

### `UI-HERO-RULE-CARD`

The production version is live HTML. Use this prompt only to generate an art-direction reference or a blank outer shell for Figma:

```text
Create a front-facing professional product rule card with a slight one-degree clockwise rotation. Use a warm-ivory main surface, charcoal outer border, violet status accents, yellow trigger label, mint verification area, compact near-black body type, and the standard hard violet shadow. It must feel like precise financial software placed inside a bold editorial poster—not a generic dashboard card.

Typeset this exact hierarchy if producing a visual reference:

small eyebrow: “EXAMPLE RULE”
title: “Sell if XRP falls”
status: “WATCHING” with a green live dot

market pair: “XRP → FLR”
trigger line: “WHEN” / “1 XRP reaches 150 FLR or less”
action line: “THEN” / “Exchange 0.01 XRP for FLR”

four boundary cells:
“TOTAL LIMIT” / “0.12 XRP”
“EACH TIME” / “0.01 XRP”
“AT MOST” / “12 TIMES”
“ENDS” / “IN 7 DAYS”

two quiet rows:
“PRICE LIMIT” / “WITHIN 0.5% OF THE CHECKED RATE”
“RUNNING FEE” / “PAID FROM EACH RESULT”

interactive example state area, shown in its resting state:
“WATCHING THE PRICE”
“WAITING FOR THE CONDITION YOU SET.”

The live component progresses through three truthful example states:
“WATCHING” → “CONDITION MET” → “EXCHANGE COMPLETE”
Final result: “0.01 XRP EXCHANGED” / “0.11 XRP REMAINS AVAILABLE.”
Keep the replay control and every state label as live HTML, never baked into generated artwork.

footer:
“YOUR KEYS STAY WITH YOU.”
“ANYTHING UNSPENT STAYS YOURS.”

Include a restrained threshold sparkline with one dashed trigger line. Do not add a wallet balance, made-up live price, last-check timestamp, transaction hash, APY, performance metric, or unsupported status. Keep the title and condition dominant, limits compact, and the custody statement clearly separated.
```

For the final website, generate only the border/surface treatment and keep every word and value as live HTML.

## Rule-card object set

Generate these three objects in one session with the same seed, camera, scale, lighting, and outline thickness.

### `ART-RULE-PRICE-TARGET`

```text
Create a polished clay-like 3D threshold instrument for a signal-yellow product tile. Show a periwinkle token disc travelling on a short mechanical track toward a bold yellow trigger gate, with a tangerine indicator needle, one marked threshold line, and three small signal ticks. The token face remains a clean blank plate for the official XRP mark. Three-quarter view, upper-left lighting, near-black editorial contour, compact hard shadow. No candlestick chart, dollar sign, number, UI panel, word, or speculative trading imagery.
```

### `ART-RULE-SCHEDULE-LOOP`

```text
Create a matching clay-like 3D recurring calendar mechanism for a periwinkle product tile. Combine an ivory calendar block, electric-violet rotating repeat ring, signal-yellow selected tab, and a small clock dial. Include exactly one complete loop arrow to communicate recurrence. Use the same camera, scale, light, contour, and hard shadow as the price object. No dates, weekday letters, text, hourglass, or alarm-clock face.
```

### `ART-RULE-PRIVATE-VAULT`

```text
Create a matching clay-like 3D privacy device for a hot-pink product tile. A sealed pink condition capsule enters a deep-violet lock chamber; a dotted input signal disappears inside; one mint verified-result pulse exits. The hidden threshold must never be visible. Use the same camera, scale, light, contour, and hard shadow as the other two rule objects. No code, hacker, anonymous mask, server rack, password field, word, or number.
```

## Lifecycle support assets

The surrounding product screens remain live HTML and use the same dimensions so the frame does not jump when a tab changes.

### `ART-LIFECYCLE-REVIEW`

```text
Create a compact supporting object for the “Review” state: an ivory rule ticket held open by a violet mechanical clamp, with three visibly bounded rows, one signal-yellow trigger marker, and one mint approval check waiting outside the ticket. The composition should point toward the live review interface and reinforce “everything is visible before approval.” No text, number, fake signature, wallet, or full UI frame.
```

Live interface facts next to it:

```text
REVIEW RULE
Sell if XRP falls
READY
WHEN — 1 XRP ≤ 150 FLR
THEN — Exchange 0.01 XRP for FLR
MAXIMUM — 0.12 XRP across 12 runs
EXPIRY — In 7 days
Anything unspent stays yours.
```

### `ART-LIFECYCLE-WATCH`

```text
Create a compact supporting object for the “Watching” state: the same monitoring radar language as the hero, reduced to a clean violet circular instrument with five completed check marks around its orbit, one mint live pulse, and a yellow condition marker waiting ahead. Point the visual energy toward the live status panel. No eye, text, market price, last-check time, server, or alarm.
```

Live interface facts next to it:

```text
RULE STATUS
Watching your price
ACTIVE
RULE ACTIVE
12 runs left
No open tab required.
```

### `ART-LIFECYCLE-ACT`

```text
Create a compact supporting object for the “Act” state: a periwinkle XRP faceplate passes through a yellow condition gate into a mint verified output ring, with three locked boundary stops still visibly engaged around the path. Add a restrained confirmation burst, not confetti. Point the composition toward the execution receipt. No text, quantity, token-logo reconstruction, celebratory character, or explosion.
```

Live interface facts next to it:

```text
EXECUTION
Condition met
0.01 XRP exchanged for FLR
RUNS LEFT — 11
TOTAL LEFT — 0.11 XRP
Oracle and permission checks passed.
```

## Private-compute asset

### `ART-PRIVATE-COMPUTE-CORE`

```text
Create a wide left-to-right confidential-compute scene with three separated stages and enough central negative space for live labels.

Left: an ivory sealed condition capsule containing only four masked dots.
Centre: a substantial hot-pink and deep-violet compute chamber with a physical closed seam, inner signal glow kept subtle, and no visible data.
Right: a mint checked result ticket emerging from the chamber.

Connect the stages with a dotted violet path that disappears at the chamber wall and resumes only as a signed yes-or-no result. The hidden threshold must never appear outside the centre. Use thick contours and the standard hard shadow. No words, code, lock stock icon, hacker imagery, cloud server, blockchain nodes, or public ledger graphic.
```

Live labels over or beside the asset:

```text
PRIVATE CONDITION — ••••••••
CONFIDENTIAL COMPUTE — VALUE STAYS SEALED
CONDITION MET — SIGNED RESULT
```

## Security proof assets

### `ART-SECURITY-NO-KEYS`

```text
Create a professional flat editorial security object showing a private key-shaped mechanical object remaining outside a sealed violet automation boundary. A bold ivory boundary line separates the owner’s key from the mechanism; a small mint shield-check remains on the owner side. The composition must communicate “the key never enters.” No red prohibition symbol, generic padlock, hacker hood, password field, words, or hand holding a key.
```

### `ART-SECURITY-NO-CUSTODY`

```text
Create a professional flat editorial security object showing a periwinkle XRP faceplate remaining in its owner’s protected orbit while a narrow automation arm operates only along a marked permission rail. The token never enters or rests inside the mechanism. Use violet, ivory, and signal yellow with one mint confirmation marker. Leave the token face blank for official XRP artwork. No hands grabbing money, wallet vault, pile of coins, bank building, word, or arrow implying Trimmy receives the funds.
```

### `ART-SECURITY-EXACT-LIMITS`

```text
Create a professional flat editorial permission controller containing exactly three locked mechanical dials around a blank token faceplate. The dials represent amount, repetitions, and expiry. Each dial has a physical stop that visibly prevents movement past its boundary. Use lime, yellow, and periwinkle with near-black contours and the standard shadow. No words, numbers, gauge clutter, infinity sign, unlock state, or distorted token logo.
```

## Builder assets

### `ART-BUILDER-XRP-COIN`

```text
Create a vertical left-side supporting illustration that leans inward toward a rule-builder panel. Show a periwinkle XRP faceplate mounted in a compact mechanical setting arm. The arm is placing a signal-yellow rule ticket into three physical sliders representing condition, amount, and duration. Keep the XRP face blank for the supplied official mark. Add one curved tangerine cable and two small inked sparks. No humanoid face, hand, word, number, wallet, or control-screen text. Compose the right edge to point directly toward the form and let the lower part break outside the panel.
```

### `ART-BUILDER-LAUNCH-ROCKET`

```text
Create a vertical right-side supporting illustration that leans inward toward a rule-builder panel. Reuse the hero watcher mechanism from a new three-quarter angle. It receives a check-marked blank rule ticket and emits one mint verification pulse into a stable orbit. Violet body, yellow ticket, orange cable, thick contour, and the same lighting and shadow. No face, words, rocket flame, moon, star field, or unrelated token.
```

### `UI-RULE-BUILDER-WINDOW`

The production version is live HTML. Use this prompt only for a visual reference or blank Figma shell:

```text
Create a front-facing “Rule preview” product window for a serious XRP automation tool, placed on a signal-yellow poster panel. Use a fully rounded warm-ivory shell that cleanly clips the compact browser bar at the top, a charcoal outline, violet action accents, yellow condition accent, mint review footer, softly rounded internal boundary cells, and one hard shadow. Keep the interface spacious and credible.

The production form beside this window exposes four live choices—Price drop, Timed exchange, Vault deposit, and Private price—and recolors/retypesets this same preview. Keep those choices, their focus states, and all changing preview copy as live HTML rather than generated pixels.

Default exact content:
window title: “RULE PREVIEW”
small type: “PRICE RULE”
state: “EXAMPLE”
rule title: “Sell if XRP falls”
first logic row: “WHEN” / “1 XRP reaches 150 FLR or less”
second logic row: “THEN” / “Exchange 0.01 XRP for FLR”
three filled boundary fields:
“EACH TIME” / “0.01 XRP”
“AT MOST” / “12 TIMES”
“ENDS” / “IN 7 DAYS”
footer title: “REVIEW BEFORE APPROVAL”
footer note: “You’ll review the full rule before anything moves.”

Do not add a wallet balance, submit transaction button, live market price, fake address, transaction hash, gas estimate, APY, or confirmation state. This is a truthful example preview that leads into full setup and review.
```

## Closing asset

### `ART-CLOSING-AUTOMATION-COLLAGE`

```text
Create a wide closing editorial collage for placement over a warm-ivory graph-paper background. Keep the central 54 percent completely clear for live headline text.

Around the perimeter arrange these existing system objects at different scales: watcher radar at upper left, yellow blank rule ticket at upper right, periwinkle XRP faceplate with an orange orbit at lower left, lime three-stop permission controller at lower right, small pink private-condition capsule near the middle edge, and three tiny signal bursts. All objects should point inward without crossing the headline safe zone. Use consistent contours, lighting, shadows, and screen-print grain. No words, rectangular background, duplicated object at the same scale, moon, generic rocket, or confetti.
```

The live closing headline is:

```text
SET THE RULE.
GET BACK TO
YOUR DAY.
```

## Ecosystem marks

### `LOGO-XRPL`, `LOGO-FLARE`, `LOGO-FASSETS`, `LOGO-FTSO`

Do not use an image-generation prompt. Download each official SVG from the project owner’s brand or developer resources. Preserve its geometry and clear-space rules. Create a one-colour warm-ivory treatment for the dark ecosystem rail only if the official license permits it. Provide the original full-colour file as the source master.

Do not use the ecosystem strip as customer proof. Its label must remain “Built for XRP on Flare” or another accurate technology attribution.

### `ICON-CONFIDENTIAL-COMPUTE`

First check whether Flare provides an official mark. If none exists, use this custom-icon prompt:

```text
Create a simple one-colour vector symbol for confidential compute: a small sealed chamber represented by two nested rounded squares, with an input dot entering on the left and a verified check dot leaving on the right. Use a uniform 2.5px stroke, rounded line caps, no fill, no padlock, no shield, no letters, and no resemblance to an existing third-party logo. Deliver as editable SVG in warm ivory and near-black variants.
```

## Open Graph and social preview

### `OG-TRIMMY`

Generate at 2400×1260 and export at 1200×630. The safest workflow is to generate the texture and illustration composition without words, then typeset the exact copy in Figma.

```text
Create a complete social-preview composition on the dark charcoal graph-paper surface. Keep a 96-pixel safe margin at final 1200×630 size.

Left 54 percent: large condensed poster headline with this exact copy:
“AI-FRIENDLY
AUTOMATION
FOR XRP”

Treat “AI-FRIENDLY” in warm ivory, “AUTOMATION” on a signal-yellow block, “FOR” as a large ivory outline, and “XRP” on a violet block with a dashed selection frame.

Right 46 percent: the rich example rule card at a slight one-degree tilt, with the watcher radar partially behind it and a lime rule seal near the lower corner.

Top left, small: the supplied Trimmy mark and word “TRIMMY”.
Bottom left: “trimmy.xyz”.

Do not include testnet language, technical stack names, unsupported performance claims, customer logos, price speculation, or any additional slogan.
```

## Final consistency checklist

- [x] The same outline thickness and hard down-right shadow appear across the full asset set.
- [x] 3D objects share one image model, three-quarter camera, and upper-left light.
- [x] Each asset stays within the approved palette; extra signal colours remain small accents.
- [x] Every token face uses a supplied official logo, never a generated approximation.
- [x] Every meaningful word and value also exists as live HTML.
- [x] No product screen invents live data or a state Trimmy does not expose.
- [x] Transparent exports have clean edges with no white matte.
- [x] Background textures tile without visible seams.
- [x] The hero, product tiles, builder, and closing composition still read when decorative art is hidden.
- [x] Mobile crops or removes only decoration; it never removes product facts or actions.
- [x] No education object or composition has been copied from the reference.
