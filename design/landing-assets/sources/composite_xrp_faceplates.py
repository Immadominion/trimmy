#!/usr/bin/env python3
"""Apply the official XRPL symbol to generated XRP faceplates.

The image model intentionally left these plates blank. This script keeps the
official vector geometry exact, then treats the mark as a surface decal by
scaling and rotating it to each plate. Run without --apply to produce preview
PNGs only; use --apply after visual QA to update production WebP/AVIF files.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from io import BytesIO
from pathlib import Path

import cairosvg
import pillow_avif  # noqa: F401 — registers AVIF support with Pillow
from PIL import Image


ROOT = Path(__file__).resolve().parents[3]
LANDING = ROOT / "design" / "landing-assets"
SITE_ART = ROOT / "site" / "assets" / "art"
MASTERS = LANDING / "masters"
PREVIEWS = LANDING / "composited-preview"
SYMBOL = LANDING / "brand" / "xrpl-symbol-black.svg"


@dataclass(frozen=True)
class Placement:
    center_x: int
    center_y: int
    width: int
    height: int
    rotation: float = 0


@dataclass(frozen=True)
class Asset:
    master: str
    output: str
    production_size: tuple[int, int]
    placements: tuple[Placement, ...]


ASSETS = (
    Asset("hero-watcher-radar-v7.png", "hero-watcher-radar", (1200, 1200),
          (Placement(553, 520, 96, 78, -1),)),
    Asset("rule-price-target-v2.png", "rule-price-target", (1200, 900),
          (Placement(414, 501, 122, 60),)),
    Asset("lifecycle-act-v2.png", "lifecycle-act", (1200, 900),
          (Placement(283, 413, 82, 32), Placement(901, 560, 78, 38, 5))),
    Asset("security-no-custody.png", "security-no-custody", (900, 900),
          (Placement(231, 480, 76, 37),)),
    Asset("security-exact-limits.png", "security-exact-limits", (900, 900),
          (Placement(449, 433, 100, 53),)),
    Asset("builder-setting-arm-v2.png", "builder-setting-arm", (900, 1350),
          (Placement(250, 347, 58, 48, -1),)),
    Asset("builder-watcher.png", "builder-watcher", (900, 1350),
          (Placement(482, 614, 72, 60, -2),)),
    Asset("closing-collage-v2.png", "closing-collage", (2200, 1100),
          (Placement(211, 194, 48, 36, -2), Placement(303, 862, 155, 109))),
)


def render_symbol() -> Image.Image:
    png = cairosvg.svg2png(url=str(SYMBOL), output_width=1192, output_height=900)
    symbol = Image.open(BytesIO(png)).convert("RGBA")
    alpha = symbol.getchannel("A")
    symbol = symbol.crop(alpha.getbbox())
    ink = Image.new("RGBA", symbol.size, (25, 25, 24, 0))
    ink.putalpha(symbol.getchannel("A"))
    return ink


def place(base: Image.Image, symbol: Image.Image, placement: Placement, scale_x: float, scale_y: float) -> None:
    width = round(placement.width * scale_x)
    height = round(placement.height * scale_y)
    decal = symbol.resize((width, height), Image.Resampling.LANCZOS)
    if placement.rotation:
        decal = decal.rotate(
            placement.rotation,
            resample=Image.Resampling.BICUBIC,
            expand=True,
        )
    center_x = round(placement.center_x * scale_x)
    center_y = round(placement.center_y * scale_y)
    left = center_x - decal.width // 2
    top = center_y - decal.height // 2
    base.alpha_composite(decal, (left, top))


def process(asset: Asset, symbol: Image.Image, apply: bool) -> None:
    master_path = MASTERS / asset.master
    base = Image.open(master_path).convert("RGBA")
    production_width, production_height = asset.production_size
    scale_x = base.width / production_width
    scale_y = base.height / production_height

    for placement in asset.placements:
        place(base, symbol, placement, scale_x, scale_y)

    PREVIEWS.mkdir(parents=True, exist_ok=True)
    preview = base.resize(asset.production_size, Image.Resampling.LANCZOS)
    preview_path = PREVIEWS / f"{asset.output}.png"
    preview.save(preview_path, format="PNG", optimize=True)
    print(f"preview {preview_path.relative_to(ROOT)}")

    if not apply:
        return

    master_output = MASTERS / f"{asset.output}-xrp.png"
    base.save(master_output, format="PNG", optimize=True)
    preview.save(SITE_ART / f"{asset.output}.webp", format="WEBP", quality=88, method=6)
    preview.save(SITE_ART / f"{asset.output}.avif", format="AVIF", quality=66, speed=6)
    print(f"applied {asset.output}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    symbol = render_symbol()
    for asset in ASSETS:
        process(asset, symbol, args.apply)


if __name__ == "__main__":
    main()
