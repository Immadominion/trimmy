from pathlib import Path

from PIL import Image


ART_DIR = Path(__file__).resolve().parent.parent
OUTPUT_DIR = ART_DIR / "doodles"
OUTPUT_DIR.mkdir(exist_ok=True)

names = [
    "sparkle",
    "signal-burst",
    "curled-arrow",
    "selection-corner",
    "orbit-loop",
    "crosshair",
    "double-underline",
    "lightning-tick",
    "dotted-trail",
    "brackets",
    "rough-circle",
    "speed-lines",
    "check-burst",
    "measurement-ticks",
    "irregular-star",
    "looping-connector",
]

sheet = Image.open(ART_DIR / "doodle-pack.png").convert("RGBA")

for index, name in enumerate(names):
    column = index % 4
    row = index // 4
    left = round(column * sheet.width / 4)
    top = round(row * sheet.height / 4)
    right = round((column + 1) * sheet.width / 4)
    bottom = round((row + 1) * sheet.height / 4)
    cell = sheet.crop((left, top, right, bottom))
    bounds = cell.getchannel("A").getbbox()
    if bounds is None:
        raise RuntimeError(f"No visible pixels found for {name}")
    element = cell.crop(bounds)
    max_side = 416
    scale = min(max_side / element.width, max_side / element.height, 1)
    if scale < 1:
        element = element.resize((round(element.width * scale), round(element.height * scale)), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (512, 512), (0, 0, 0, 0))
    canvas.alpha_composite(element, ((512 - element.width) // 2, (512 - element.height) // 2))
    canvas.save(OUTPUT_DIR / f"{name}.png", optimize=True)
