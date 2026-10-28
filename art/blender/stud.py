"""Seamless stud tile for UI panels (tint with ImageColor3). python3 stud.py out.png"""
import sys
from PIL import Image, ImageDraw, ImageFilter
S = 128  # one stud per tile
base = (226, 226, 226)
im = Image.new("RGB", (S * 4, S * 4), base)
hi = Image.new("L", im.size, 0)
sh = Image.new("L", im.size, 0)
d_hi, d_sh = ImageDraw.Draw(hi), ImageDraw.Draw(sh)
r = S * 0.30
for gy in range(4):
    for gx in range(4):
        cx, cy = gx * S + S / 2, gy * S + S / 2
        d_sh.ellipse([cx - r + 7, cy - r + 9, cx + r + 7, cy + r + 9], fill=170)
        d_hi.ellipse([cx - r - 3, cy - r - 4, cx + r - 3, cy + r - 4], fill=150)
sh = sh.filter(ImageFilter.GaussianBlur(5))
hi = hi.filter(ImageFilter.GaussianBlur(3))
im.paste((130, 130, 138), (0, 0), sh)
im.paste((255, 255, 255), (0, 0), hi)
top = Image.new("L", im.size, 0)
dt = ImageDraw.Draw(top)
for gy in range(4):
    for gx in range(4):
        cx, cy = gx * S + S / 2, gy * S + S / 2
        dt.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
im.paste((240, 240, 240), (0, 0), top)
im = im.resize((S, S), Image.LANCZOS) if False else im.resize((256, 256), Image.LANCZOS)
im.save(sys.argv[1])
