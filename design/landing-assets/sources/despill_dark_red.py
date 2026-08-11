import argparse

from PIL import Image


parser = argparse.ArgumentParser(description="Neutralize dark red chroma fringe while preserving bright brand accents.")
parser.add_argument("input")
parser.add_argument("output")
args = parser.parse_args()

image = Image.open(args.input).convert("RGBA")
cleaned = []

for red, green, blue, alpha in image.getdata():
    if alpha and red < 180 and red > green + 4 and red > blue + 4 and green < 120 and blue < 120:
        neutral = max(green, blue)
        cleaned.append((neutral, neutral, neutral, alpha))
    else:
        cleaned.append((red, green, blue, alpha))

image.putdata(cleaned)
image.save(args.output, optimize=True)
