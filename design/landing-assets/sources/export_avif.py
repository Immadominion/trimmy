#!/usr/bin/env python3
"""Export alpha-safe AVIF siblings for Trimmy's production WebP artwork."""

from __future__ import annotations

import argparse
from pathlib import Path

import pillow_avif  # noqa: F401 — registers AVIF support with Pillow
from PIL import Image


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_dir", type=Path)
    args = parser.parse_args()

    sources = sorted(args.source_dir.glob("*.webp"))
    if not sources:
        raise SystemExit(f"No WebP files found in {args.source_dir}")

    for source in sources:
        destination = source.with_suffix(".avif")
        with Image.open(source) as opened:
            opened.load()
            source_has_alpha = "A" in opened.getbands()
            image = opened.convert("RGBA" if source_has_alpha else "RGB")
            quality = 66 if source_has_alpha else 54
            image.save(destination, format="AVIF", quality=quality, speed=6)

        with Image.open(destination) as exported:
            exported.load()
            if source_has_alpha and "A" not in exported.getbands():
                destination.unlink(missing_ok=True)
                raise RuntimeError(f"Alpha channel was lost while exporting {source.name}")
            if exported.size != image.size:
                destination.unlink(missing_ok=True)
                raise RuntimeError(f"Dimensions changed while exporting {source.name}")

        print(f"{source.name} -> {destination.name} ({destination.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
