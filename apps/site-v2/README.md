# site-v2

The local Trimmy landing page at `http://localhost:5173/`. Standalone, not an
npm workspace. Current copy lives in `docs/design/LANDING_COPY_V4.md` and the
implementation map in `docs/design/WALL_STREET_JOURNEY_STUDY.md`. Older
shortlists and `/world-study` are retained design research.

```sh
npm install
npm run dev
npm run build
```

## Main page

`/` now implements seventeen screens in one viewport. Each wheel gesture,
swipe or arrow-key move advances one screen on the shared Easy Ease animation.
Previous/next buttons and “Skip to the game” also navigate the experience.

- **0–1:** the unchanged black opening and two exact introductory lines.
- **2–8:** separate historical dates, the modern street, ticker and trading floor.
  A connected Blender environment carries the camera through two real corners.
- **9:** the floor gives way to the Trimmy phone.
- **10–14:** 10,000 in virtual money, practice buying/selling at stock prices,
  Sal's missions, selling part of an investment and Rookie-to-Legend progress.
- **15–16:** truthful build status, a closing action to `https://x.com/trimmyhq`,
  and the exact “Trimmy is a Wall Street simulation game.” footer.

The phone is an interactive HTML preview, right of the copy on desktop and
below it on mobile. It uses existing app colors and assets. Company selection
changes the example stock; the trim demo sells 2 of 8 example shares and can
be reset. A persistent Demo label and price notes distinguish illustrative
values from a live feed. It places no order and uses no account or wallet.

## Runtime and editable sources

- `src/story/screens.ts`: all seventeen screens; update V4 first when changing copy.
- `src/components/Screen.tsx`: centered intro, scene copy and product copy.
- `src/components/ProductShowcase.tsx` and `product.css`: phone preview and copy layout.
- `src/lib/stepper.ts`, `useStepper.ts`, `useFrame.ts`: position, input and one
  shared animation loop; frame updates do not pass through React state.
- `src/world/WorldStage.tsx`: lazy-loaded main environment and fallback handling.
- `src/world/engine.ts`: Three.js rendering, GLTF loading with Meshopt decoder
  support, era states, lighting, flags, ticker and particles.
- `src/world/route.ts`: narrative positions mapped onto the shared camera route.
- `public/world/wall-street.glb`: connected exterior, doorway and floor with
  embedded authored PBR textures; source is
  `trimmy/art/production/wall-street/wall-street.blend` and its build scripts.
- `public/world/bull.glb`: separate original bull, generated from the existing
  original concept and prepared in Blender; source/notes are in
  `trimmy/art/production/landing-world-2026-09-23/bull/`.
- `public/world/route.json`: 361 samples, 1.65 m eye height, two 6 m radius turns.
  Its editable route source is `trimmy/art/studies/wall-street-route-2026-09-23/`.
- `public/world/scene-manifest.json`: semantic groups, light and bull anchors.
- `public/world/poster-street.webp`, `poster-floor.webp`: rendered model fallbacks.
- `public/product/PROVENANCE.md`: reused app art and demo boundaries.

The composed environment is inspired by Wall/Broad Street relationships; it is
not a surveyed New York replica. The old generated look image is not loaded
by the main page.

## Sound and retained study

Music at `/audio/music.mp3` has a 30% gain ceiling; floor ambience has 50%.
Both wait for a permitted browser gesture and share the mute control. Source
and mastering notes are in `public/audio/PROVENANCE.md`.

`/world-study` retains the blue-hour concept image, interactive camera blockout
and earlier fourteen-stop story proposal. Those remain research artifacts;
the seventeen-screen main route is the current implementation. Reference
findings are in `docs/design/WALL_STREET_REFERENCE_AUDIT.md`.

## Verification — 23 September 2026

`npm run build` passes TypeScript compilation and the production Vite build.
Vite reports its size warning for the lazy-loaded Three.js/GLTFLoader chunk;
this is not a build failure.

The final environment and bull pass independent GLB header/chunk, accessor
range, node-reference/cycle and triangle-index checks. All 160 Meshopt buffer
views in the environment decode successfully. The environment contains
172,798 triangles across 75 mesh primitives; the bull contains 28,252 triangles.

| Runtime asset | Exact bytes |
|---|---:|
| `world/wall-street.glb` | 6,139,184 |
| `world/bull.glb` | 806,940 |
| `world/route.json` | 104,173 |
| `world/scene-manifest.json` | 4,435 |
| `world/poster-street.webp` | 134,566 |
| `world/poster-floor.webp` | 154,558 |
| `audio/music.mp3` | 1,964,781 |
| `audio/floor.mp3` | 453,829 |

Route checks cover all 361 finite, strictly ordered waypoints. Maximum sample
spacing is 0.29681 m, and all four line/arc junctions have continuous positions
and tangents. The route is 106.84956 m long. These numerical checks do not
constitute a general mesh-collision test or measured browser frame rate.

Desktop browser QA covered all seventeen chapters, stock selection, selling
and resetting the trim example, mute, and the closing screen. The trim example
is internally consistent: selling 2 of 8 shares bought at 100 for 125 each
returns 250, realizes a gain of 50, and leaves 6 shares worth 750.

Portrait browser checks at 390 × 844 and 375 × 667 verified the scene framing,
copy placement, phone reveal, stock selection, mission card, trim controls and
closing CTA. The short-phone layout was corrected to keep actions inside the
bezel and remove overlapping text. Home/End, next/previous, skip, replay and
mute were exercised. The final live scene reports ready with no application
or WebGL errors in the inspected browser console. Audio levels and playback
state were checked; this was not a listening review. Reduced-motion behavior
is implemented but an OS-level reduced-motion browser pass was not performed.

The environment is a rendered, stylized scene. It is not yet at the reference's
photographic realism. No measured mobile-device frame-rate claim is made.

The deployed geometry uses `art/production/wall-street/candidate/wall-street-candidate.blend`
and `refine_history_candidate.py` after the base builder. Follow the production
art README's complete rebuild order to preserve the tree, agreement and flag refinements.
