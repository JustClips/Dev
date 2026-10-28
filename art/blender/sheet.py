"""Stitch preview PNGs into one contact sheet: python3 sheet.py out.png a.png b.png ..."""
import sys
from PIL import Image, ImageDraw
files = sys.argv[2:]
ims = [Image.open(f).convert("RGB") for f in files]
w, h = ims[0].size
cols = min(5, len(ims))
rows = (len(ims) + cols - 1) // cols
sheet = Image.new("RGB", (cols * w, rows * h), (20, 20, 30))
d = ImageDraw.Draw(sheet)
for i, (im, f) in enumerate(zip(ims, files)):
    x, y = (i % cols) * w, (i // cols) * h
    sheet.paste(im, (x, y))
    d.text((x + 6, y + 6), f.split("/")[-1].replace(".png", ""), fill=(255, 255, 255))
sheet.save(sys.argv[1])
