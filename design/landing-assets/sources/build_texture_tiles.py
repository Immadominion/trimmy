from pathlib import Path

from PIL import Image, ImageDraw, ImageOps, ImageStat


ART_DIR = Path(__file__).resolve().parent.parent
SOURCE_DIR = ART_DIR / "sources"


def graded_source(path: Path, size: int, target: tuple[int, int, int], strength: float) -> Image.Image:
    image = Image.open(path).convert("RGB")
    edge = min(image.size)
    left = (image.width - edge) // 2
    top = (image.height - edge) // 2
    image = image.crop((left, top, left + edge, top + edge)).resize((size, size), Image.Resampling.LANCZOS)
    luminance = ImageOps.grayscale(image)
    mean = ImageStat.Stat(luminance).mean[0]
    delta = luminance.point(lambda value: max(0, min(255, round(128 + (value - mean) * strength))))
    channels = [delta.point(lambda value, base=base: max(0, min(255, base + value - 128))) for base in target]
    return Image.merge("RGB", channels)


def mirrored_tile(source: Path, size: int, target: tuple[int, int, int], strength: float) -> Image.Image:
    half = size // 2
    patch = graded_source(source, half, target, strength)
    tile = Image.new("RGB", (size, size))
    tile.paste(patch, (0, 0))
    tile.paste(ImageOps.mirror(patch), (half, 0))
    tile.paste(ImageOps.flip(patch), (0, half))
    tile.paste(ImageOps.flip(ImageOps.mirror(patch)), (half, half))
    return tile


def add_grid(image: Image.Image, spacing: int, color: tuple[int, int, int, int], width: int) -> Image.Image:
    overlay = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    for offset in range(0, image.width, spacing):
        draw.line((offset, 0, offset, image.height), fill=color, width=width)
        draw.line((0, offset, image.width, offset), fill=color, width=width)
    return Image.alpha_composite(image.convert("RGBA"), overlay).convert("RGB")


dark_source = SOURCE_DIR / "texture-charcoal-source-v1.png"
light_source = SOURCE_DIR / "texture-ivory-source-v1.png"

charcoal = mirrored_tile(dark_source, 2048, (36, 36, 35), 0.52)
charcoal.save(ART_DIR / "texture-charcoal-paper.png", optimize=True)

light_paper = mirrored_tile(light_source, 2048, (246, 243, 236), 0.48)
light_paper.save(ART_DIR / "texture-light-paper.png", optimize=True)

dark_grid = mirrored_tile(dark_source, 1920, (25, 25, 24), 0.46)
dark_grid = add_grid(dark_grid, 160, (246, 243, 236, 18), 2)
dark_grid.save(ART_DIR / "texture-dark-grid.png", optimize=True)

light_grid = mirrored_tile(light_source, 1920, (246, 243, 236), 0.44)
light_grid = add_grid(light_grid, 160, (25, 25, 24, 30), 2)
light_grid.save(ART_DIR / "texture-light-grid.png", optimize=True)
