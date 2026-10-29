"""Hexagon tiles for the upgrade tree window (pointy-top, square-cornered style).

HexTile: white fill + thick near-black outline (the game adds a soft UIGradient shade). Tinted in game with
ImageColor3 (the outline stays dark because tinting multiplies).
HexRing: just a white outline ring, a bit bigger, for the selected / affordable glow.

    python3 art/hex_tiles.py   ->  art/out/ui/HexTile.png, art/out/ui/HexRing.png
"""
import math
import os

from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "out", "ui")
SS = 4  # supersampling
H = 256
W = round(H * math.sqrt(3) / 2)  # 222
INK = (23, 25, 30, 255)


def hex_points(cx, cy, r):
    return [(cx + r * math.cos(math.radians(60 * i - 90)), cy + r * math.sin(math.radians(60 * i - 90))) for i in range(6)]


def tile():
    w, h = W * SS, H * SS
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx, cy, r = w / 2, h / 2, h / 2 - 2 * SS
    d.polygon(hex_points(cx, cy, r), fill=INK)
    d.polygon(hex_points(cx, cy, r - 13 * SS), fill=(255, 255, 255, 255))
    return im.resize((W, H), Image.LANCZOS)


def ring():
    w, h = W * SS, H * SS
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx, cy, r = w / 2, h / 2, h / 2 - 2 * SS
    d.polygon(hex_points(cx, cy, r), fill=(255, 255, 255, 255))
    d.polygon(hex_points(cx, cy, r - 16 * SS), fill=(0, 0, 0, 0))
    return im.resize((W, H), Image.LANCZOS)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    tile().save(os.path.join(OUT, "HexTile.png"))
    ring().save(os.path.join(OUT, "HexRing.png"))
    print("wrote", OUT)
