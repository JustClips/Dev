"""Particle textures drawn in code (no ForgeUI needed for these simple shapes).

Vfx_Star: a white cartoon 4-point twinkle star with a soft halo, for coin sparkles. White so
ParticleEmitter.Color tints it.

Usage: python3 tools/gen_vfx.py   (writes art/out/ui/Vfx_Star.png)
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "art", "out", "ui")
S = 256
K = 4  # supersampling


def star_points(cx, cy, outer, inner, n=4, rot=-math.pi / 2, curve=6):
    """Points of a star with concave (curved-in) sides."""
    pts = []
    for i in range(n):
        a0 = rot + i * math.tau / n
        a1 = a0 + math.tau / n
        tip0 = (cx + math.cos(a0) * outer, cy + math.sin(a0) * outer)
        tip1 = (cx + math.cos(a1) * outer, cy + math.sin(a1) * outer)
        mid = ((a0 + a1) / 2)
        ctrl = (cx + math.cos(mid) * inner, cy + math.sin(mid) * inner)
        for k in range(curve):
            t = k / curve
            x = (1 - t) ** 2 * tip0[0] + 2 * (1 - t) * t * ctrl[0] + t * t * tip1[0]
            y = (1 - t) ** 2 * tip0[1] + 2 * (1 - t) * t * ctrl[1] + t * t * tip1[1]
            pts.append((x, y))
    return pts


def star():
    size = S * K
    c = size / 2
    halo = Image.new("L", (size, size), 0)
    ImageDraw.Draw(halo).ellipse((c - size * 0.2, c - size * 0.2, c + size * 0.2, c + size * 0.2), fill=110)
    halo = halo.filter(ImageFilter.GaussianBlur(size * 0.08))
    shape = Image.new("L", (size, size), 0)
    ImageDraw.Draw(shape).polygon(star_points(c, c, size * 0.47, size * 0.0), fill=255)
    alpha = Image.composite(shape, halo, shape)
    img = Image.merge("RGBA", (Image.new("L", (size, size), 255),) * 3 + (alpha,))
    return img.resize((S, S), Image.LANCZOS)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "Vfx_Star.png")
    star().save(path)
    print("wrote", path)
