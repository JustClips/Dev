"""Flat effect images and small UI glyphs (white, tint with ImageColor3).

  python3 art/blender/fx.py art/out/ui

Writes Rays (sunburst behind a hatch), Glow (soft round light), Sparkle (4-point star for
confetti and particles), Ring (shockwave), the settings glyphs Gear, Music, Speaker, and the
tool particle images FxBubble, FxLeaf, FxStreak, FxDrop.
Only some: python3 art/blender/fx.py art/out/ui FxBubble FxLeaf
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


def chevron(w=256, h=128):
    """Two chevrons pointing right (+U), for the guide beam texture."""
    big_w, big_h = w * 4, h * 4
    alpha = Image.new("L", (big_w, big_h), 0)
    d = ImageDraw.Draw(alpha)
    t = big_h * 0.2
    for cx in (big_w * 0.3, big_w * 0.8):
        tip = cx + big_h * 0.25
        d.polygon([(cx - big_h * 0.25, big_h * 0.1), (cx - big_h * 0.25 + t, big_h * 0.1), (tip + t, big_h / 2),
                   (cx - big_h * 0.25 + t, big_h * 0.9), (cx - big_h * 0.25, big_h * 0.9), (tip, big_h / 2)], fill=255)
    alpha = alpha.resize((w, h), Image.LANCZOS)
    im = Image.new("RGBA", (w, h), WHITE + (0,))
    im.putalpha(alpha)
    save(im, "Chevron")


def arrow_down(size=128):
    """Chunky down arrow, white with a navy outline (readable on any background)."""
    big = size * 4
    s = big / 128
    pts = [(44 * s, 10 * s), (84 * s, 10 * s), (84 * s, 62 * s), (112 * s, 62 * s), (64 * s, 118 * s), (16 * s, 62 * s), (44 * s, 62 * s)]
    outline = Image.new("L", (big, big), 0)
    ImageDraw.Draw(outline).polygon(pts, fill=255)
    outline = outline.filter(ImageFilter.MaxFilter(int(9 * s) | 1))
    fill = Image.new("L", (big, big), 0)
    ImageDraw.Draw(fill).polygon(pts, fill=255)
    im = Image.new("RGBA", (big, big), (27, 31, 58, 0))
    im.putalpha(outline)
    white = Image.new("RGBA", (big, big), WHITE + (255,))
    im.paste(white, (0, 0), fill)
    save(im.resize((size, size), Image.LANCZOS), "ArrowDown")


def fx_bubble(size=128):
    """Soap bubble: thin bright rim, faint fill, a highlight up-left."""
    big = size * 4
    alpha = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(alpha)
    w = big * 0.06
    d.ellipse([w, w, big - w, big - w], fill=46)
    d.ellipse([w, w, big - w, big - w], outline=255, width=int(w))
    d.ellipse([big * 0.24, big * 0.2, big * 0.42, big * 0.36], fill=235)
    alpha = alpha.filter(ImageFilter.GaussianBlur(big * 0.006)).resize((size, size), Image.LANCZOS)
    im = Image.new("RGBA", (size, size), WHITE + (0,))
    im.putalpha(alpha)
    save(im, "FxBubble")


def fx_leaf(size=128):
    """A leaf with a stem and a darker middle vein (tint it green, orange or brown)."""
    big = size * 4
    c = big / 2
    pts = []
    for i in range(0, 181, 6):
        t = math.radians(i)
        x = c + math.sin(t) * big * 0.26 * (1 - 0.25 * math.cos(t))
        y = big * 0.1 + (1 - math.cos(t)) / 2 * big * 0.7
        pts.append((x, y))
    pts += [(2 * c - x, y) for x, y in reversed(pts)]
    alpha = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(alpha)
    d.polygon(pts, fill=255)
    d.line([(c, big * 0.78), (c, big * 0.95)], fill=255, width=int(big * 0.03))
    im = Image.new("RGBA", (big, big), WHITE + (0,))
    im.putalpha(alpha)
    vein = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    vd = ImageDraw.Draw(vein)
    vd.line([(c, big * 0.14), (c, big * 0.8)], fill=(170, 170, 170, 255), width=int(big * 0.022))
    for k in range(1, 4):
        y = big * (0.25 + k * 0.13)
        for sgn in (-1, 1):
            vd.line([(c, y), (c + sgn * big * 0.15, y - big * 0.1)], fill=(190, 190, 190, 255), width=int(big * 0.015))
    vein.putalpha(ImageChops.multiply(vein.getchannel("A"), alpha))
    im = Image.alpha_composite(im, vein)
    save(im.resize((size, size), Image.LANCZOS), "FxLeaf")


def fx_streak(w=64, h=256):
    """A soft air streak along V, brightest in the middle, fading at both ends."""
    alpha = Image.new("L", (w, h), 0)
    px = alpha.load()
    for y in range(h):
        along = math.sin(math.pi * y / (h - 1)) ** 1.5
        for x in range(w):
            across = max(0.0, 1 - abs(x - (w - 1) / 2) / (w * 0.3)) ** 2
            px[x, y] = int(255 * along * across)
    im = Image.new("RGBA", (w, h), WHITE + (0,))
    im.putalpha(alpha)
    save(im, "FxStreak")


def fx_drop(size=128):
    """A water drop with a highlight."""
    big = size * 4
    c = big / 2
    alpha = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(alpha)
    r = big * 0.3
    d.ellipse([c - r, big * 0.88 - 2 * r, c + r, big * 0.88], fill=225)
    d.polygon([(c, big * 0.08), (c + r * 0.93, big * 0.88 - r * 1.35), (c - r * 0.93, big * 0.88 - r * 1.35)], fill=225)
    d.ellipse([c - r * 0.55, big * 0.5, c - r * 0.15, big * 0.62], fill=255)
    alpha = alpha.resize((size, size), Image.LANCZOS)
    im = Image.new("RGBA", (size, size), WHITE + (0,))
    im.putalpha(alpha)
    save(im, "FxDrop")


ALL = {"Rays": rays, "Glow": glow, "Sparkle": sparkle, "Ring": ring, "Gear": gear, "Music": music,
       "Speaker": speaker, "Chevron": chevron, "ArrowDown": arrow_down, "FxBubble": fx_bubble,
       "FxLeaf": fx_leaf, "FxStreak": fx_streak, "FxDrop": fx_drop}
for name in (sys.argv[2:] or ALL):
    ALL[name]()
print("wrote", OUT)
