# Trimmy landing asset sources

This directory contains the non-deployable working files for the production landing-page art.

- `masters/` — selected transparent PNG masters plus retained visual iterations.
- `sources/` — original chroma-key generations and the deterministic cleanup/export helpers.
- `doodles/` — the sixteen individually extracted doodle PNGs.
- `brand/` — original Trimmy mark source and unused raster size variants.
- `library/` — optional generated assets that are part of the design kit but not loaded by the page.
- `composited-preview/` — approved production-size previews with the official XRP decal applied.
- `og.html` — exact HTML composition used to typeset the social preview.
- `og-trimmy-master.png` — the 2400×1260 social-preview master.

The optimized files consumed by the website remain in `site/assets/art/`, while `site/ASSET-PROMPTS.md` is the complete prompt and integration brief. Keeping this source set outside `site/` prevents roughly 77 MB of masters and iterations from being included in production deployment.

`sources/composite_xrp_faceplates.py` applies the exact official vector as a surface decal and regenerates the affected WebP/AVIF pairs. `sources/export_avif.py` reproduces alpha-safe AVIF exports for the complete runtime set.
