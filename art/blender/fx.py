"""Flat effect images and small UI glyphs (white, tint with ImageColor3).

  python3 art/blender/fx.py art/out/ui

Writes Rays (sunburst behind a hatch), Glow (soft round light), Sparkle (4-point star for
confetti and particles), Ring (shockwave), and the settings glyphs Gear, Music, Speaker.
"""
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else "art/out/ui"
os.makedirs(OUT, exist_ok=True)
WHITE = (255, 255, 255)


def save(im, name):
    im.save(os.path.join(OUT, name + ".png"))


def rays(size=512, count=14):
    big = size * 2
    mask = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(mask)
    c = big / 2
    half = math.pi / count * 0.55
    for i in range(count):
        a = i * 2 * math.pi / count
        pts = [(c, c)]
        for t in (a - half, a + half):
            pts.append((c + math.cos(t) * big, c + math.sin(t) * big))
        d.polygon(pts, fill=255)
    # Fade out towards the edge and leave the centre soft.
    fade = Image.new("L", (big, big), 0)
    fd = ImageDraw.Draw(fade)
    for r in range(int(c), 0, -4):
        v = int(255 * (1 - r / c) ** 0.9)
        fd.ellipse([c - r, c - r, c + r, c + r], fill=v)
    alpha = ImageChops.multiply(mask, fade)
    alpha = alpha.filter(ImageFilter.GaussianBlur(3)).resize((size, size), Image.LANCZOS)
    im = Image.new("RGBA", (size, size), WHITE + (0,))
    im.putalpha(alpha)
    save(im, "Rays")


def glow(size=256):
    alpha = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(alpha)
    c = size / 2
    for r in range(int(c), 0, -1):
        v = int(255 * (1 - r / c) ** 2.2)
        d.ellipse([c - r, c - r, c + r, c + r], fill=v)
    im = Image.new("RGBA", (size, size), WHITE + (0,))
    im.putalpha(alpha)
    save(im, "Glow")


def sparkle(size=128):
    big = size * 4
    alpha = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(alpha)
    c = big / 2
    long, thin = big * 0.48, big * 0.09
    d.polygon([(c, c - long), (c + thin, c - thin), (c + long, c), (c + thin, c + thin),
               (c, c + long), (c - thin, c + thin), (c - long, c), (c - thin, c - thin)], fill=255)
    glow_l = alpha.filter(ImageFilter.GaussianBlur(big * 0.04))
    alpha = ImageChops.lighter(alpha, glow_l).resize((size, size), Image.LANCZOS)
    im = Image.new("RGBA", (size, size), WHITE + (0,))
    im.putalpha(alpha)
    save(im, "Sparkle")


def ring(size=256):
    big = size * 4
    alpha = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(alpha)
    w = big * 0.07
    d.ellipse([w, w, big - w, big - w], outline=255, width=int(w))
    alpha = alpha.filter(ImageFilter.GaussianBlur(big * 0.012)).resize((size, size), Image.LANCZOS)
    im = Image.new("RGBA", (size, size), WHITE + (0,))
    im.putalpha(alpha)
    save(im, "Ring")


def gear(size=128, teeth=8):
    big = size * 4
    alpha = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(alpha)
    c = big / 2
    outer, inner, hole = big * 0.46, big * 0.34, big * 0.15
    pts = []
    steps = teeth * 4
    for i in range(steps):
        a = (i / steps) * 2 * math.pi - math.pi / 2
        r = outer if i % 4 in (0, 1) else inner
        pts.append((c + math.cos(a) * r, c + math.sin(a) * r))
    d.polygon(pts, fill=255)
    d.ellipse([c - inner * 1.0, c - inner * 1.0, c + inner * 1.0, c + inner * 1.0], fill=255)
    d.ellipse([c - hole, c - hole, c + hole, c + hole], fill=0)
    alpha = alpha.resize((size, size), Image.LANCZOS)
    im = Image.new("RGBA", (size, size), WHITE + (0,))
    im.putalpha(alpha)
    save(im, "Gear")


def music(size=128):
    big = size * 4
    alpha = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(alpha)
    s = big / 128
    # Two notes joined by a beam.
    d.ellipse([18 * s, 82 * s, 50 * s, 108 * s], fill=255)
    d.ellipse([70 * s, 70 * s, 102 * s, 96 * s], fill=255)
    d.rectangle([42 * s, 26 * s, 50 * s, 96 * s], fill=255)
    d.rectangle([94 * s, 14 * s, 102 * s, 84 * s], fill=255)
    d.polygon([(42 * s, 26 * s), (102 * s, 14 * s), (102 * s, 32 * s), (42 * s, 44 * s)], fill=255)
    alpha = alpha.resize((size, size), Image.LANCZOS)
    im = Image.new("RGBA", (size, size), WHITE + (0,))
    im.putalpha(alpha)
    save(im, "Music")


def speaker(size=128):
    big = size * 4
    alpha = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(alpha)
    s = big / 128
    d.rectangle([14 * s, 46 * s, 38 * s, 82 * s], fill=255)
    d.polygon([(38 * s, 46 * s), (66 * s, 20 * s), (66 * s, 108 * s), (38 * s, 82 * s)], fill=255)
    for r, w in ((26, 9), (44, 9)):
        box = [64 * s - r * s, 64 * s - r * s, 64 * s + r * s, 64 * s + r * s]
        d.arc([box[0] + 14 * s, box[1], box[2] + 14 * s, box[3]], -45, 45, fill=255, width=int(w * s))
    alpha = alpha.resize((size, size), Image.LANCZOS)
    im = Image.new("RGBA", (size, size), WHITE + (0,))
    im.putalpha(alpha)
    save(im, "Speaker")


rays()
glow()
sparkle()
ring()
gear()
music()
speaker()
print("wrote", OUT)
