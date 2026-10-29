"""Ground clutter textures for the leaf tiles (LeafController): each image is a clump of
separate leaves (or seaweed, paper scraps, snow) seen from above, with a dark outline and
flat colours like the HUD icons. One image per tile, turned at random, so the field reads
as a thick carpet of single leaves.

    python3 art/vfx/ground.py        # writes art/out/ui/Ground_<Name>.png
"""
import math
import os
import random

from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(__file__), "..", "out", "ui")
os.makedirs(OUT, exist_ok=True)

S = 256  # output size
K = 3  # supersampling
OUTLINE = (52, 30, 22)


def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c)


def leaf_outline(kind, length, rng):
    """Leaf polygon around (0, 0), tip pointing to -y, in pixels."""
    pts = []
    n = 90
    for i in range(n):
        t = i / n * math.tau
        if kind == "maple":
            r = 0.34 + 0.16 * abs(math.cos(t * 2.5)) ** 2.5 + 0.05 * math.cos(t * 10)
            r *= 1 - 0.3 * max(0, math.cos(t)) ** 10
            x, y = math.sin(t) * r, -math.cos(t) * r
        elif kind == "oak":
            r = 0.5 / math.sqrt((math.cos(t)) ** 2 + (math.sin(t) / 0.62) ** 2) + 0.05 * abs(math.cos(t * 4.5))
            x, y = math.sin(t) * r * 0.85, -math.cos(t) * r * 0.85
        elif kind == "birch":
            r = 0.5 / math.sqrt((math.cos(t)) ** 2 + (math.sin(t) / 0.72) ** 2) + 0.015 * math.cos(t * 24)
            r *= 1 - 0.18 * max(0, -math.cos(t)) ** 3  # pointed tip
            x, y = math.sin(t) * r * 0.8, -math.cos(t) * r * 0.8
        else:  # long willow-like / seaweed blade
            r = 0.5 / math.sqrt((math.cos(t)) ** 2 + (math.sin(t) / 0.34) ** 2)
            x, y = math.sin(t) * r * 0.5, -math.cos(t) * r * 0.5
        pts.append((x * length, y * length))
    return pts


def transform(pts, cx, cy, angle):
    ca, sa = math.cos(angle), math.sin(angle)
    return [(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in pts]


def draw_leaf(d, kind, cx, cy, length, angle, color, rng):
    pts = transform(leaf_outline(kind, length, rng), cx, cy, angle)
    w = max(2, int(length * 0.06))
    d.polygon(pts, fill=OUTLINE)
    # Shrink toward the centre for the fill so the outline stays visible.
    inner = [(cx + (x - cx) * (1 - w / length * 1.6), cy + (y - cy) * (1 - w / length * 1.6)) for x, y in pts]
    d.polygon(inner, fill=color)
    # One shade: the half away from the light.
    ca, sa = math.cos(angle), math.sin(angle)
    half = [p for p in inner if (p[0] - cx) * ca + (p[1] - cy) * sa > 0]
    if len(half) > 2:
        d.polygon([(cx - sa * length * 0.5, cy + ca * length * 0.5)] + half + [(cx + sa * length * 0.5, cy - ca * length * 0.5)],
                  fill=shade(color, 0.86))
    # Vein and stem.
    tip = (cx + sa * length * 0.42, cy - ca * length * 0.42)
    base = (cx - sa * length * 0.5, cy + ca * length * 0.5)
    stem = (cx - sa * length * 0.56, cy + ca * length * 0.56)
    if kind == "blade":
        return
    d.line([tip, base], fill=shade(color, 0.62), width=max(1, w // 2))
    if kind != "blade":
        d.line([base, stem], fill=OUTLINE, width=max(2, int(w * 0.7)))
    if kind in ("maple", "oak"):
        for k in (-1, 1):
            for f in (0.1, -0.15):
                a = (cx - sa * length * f, cy + ca * length * f)
                b = (a[0] + (ca * k - sa * 0.6) * length * 0.25, a[1] + (sa * k + ca * 0.6) * length * 0.25)
                d.line([a, b], fill=shade(color, 0.7), width=max(1, w // 2))


def clump(name, palette, kinds, count, seed, size_range=(0.42, 0.62), spread=0.38):
    rng = random.Random(seed)
    img = Image.new("RGBA", (S * K, S * K), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = S * K / 2
    for i in range(count):
        a = rng.random() * math.tau
        r = (rng.random() ** 0.6) * spread * S * K
        cx, cy = c + math.cos(a) * r, c + math.sin(a) * r
        length = rng.uniform(*size_range) * S * K * 0.6
        color = rng.choice(palette)
        draw_leaf(d, rng.choice(kinds), cx, cy, length, rng.random() * math.tau, color, rng)
    img = img.resize((S, S), Image.LANCZOS)
    img.save(os.path.join(OUT, f"Ground_{name}.png"))
    print("wrote", name)


def paper(name, seed):
    """City litter: paper scraps, receipts and cardboard bits."""
    rng = random.Random(seed)
    img = Image.new("RGBA", (S * K, S * K), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = S * K / 2
    for i in range(9):
        a = rng.random() * math.tau
        r = (rng.random() ** 0.6) * 0.34 * S * K
        cx, cy = c + math.cos(a) * r, c + math.sin(a) * r
        w, h = rng.uniform(0.12, 0.22) * S * K, rng.uniform(0.08, 0.16) * S * K
        ang = rng.random() * math.tau
        corners = [(-w / 2, -h / 2), (w / 2, -h / 2 + rng.uniform(-6, 6) * K), (w / 2, h / 2), (-w / 2 + rng.uniform(-8, 8) * K, h / 2)]
        pts = transform(corners, cx, cy, ang)
        kind = rng.random()
        color = (240, 236, 224) if kind < 0.5 else (200, 150, 96) if kind < 0.8 else (150, 186, 224)
        d.polygon(pts, fill=OUTLINE)
        inner = [(cx + (x - cx) * 0.9, cy + (y - cy) * 0.9) for x, y in pts]
        d.polygon(inner, fill=color)
        if color[0] > 230:  # writing lines on paper
            for k in range(3):
                f = -0.25 + k * 0.25
                p0 = transform([(-w * 0.32, h * f)], cx, cy, ang)[0]
                p1 = transform([(w * 0.3, h * f)], cx, cy, ang)[0]
                d.line([p0, p1], fill=(160, 170, 190), width=2 * K)
    # A couple of brown leaves on top.
    for i in range(3):
        a = rng.random() * math.tau
        draw_leaf(d, "oak", c + math.cos(a) * 60 * K, c + math.sin(a) * 60 * K, 52 * K, rng.random() * math.tau,
                  rng.choice([(170, 120, 70), (150, 100, 60)]), rng)
    img = img.resize((S, S), Image.LANCZOS)
    img.save(os.path.join(OUT, f"Ground_{name}.png"))
    print("wrote", name)


def snow(name, seed):
    """Snowy Peaks: a soft drift of snow lumps with blue shade and a few sparkles."""
    rng = random.Random(seed)
    img = Image.new("RGBA", (S * K, S * K), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = S * K / 2
    blobs = []
    for i in range(10):
        a = rng.random() * math.tau
        r = (rng.random() ** 0.7) * 0.3 * S * K
        blobs.append((c + math.cos(a) * r, c + math.sin(a) * r, rng.uniform(0.1, 0.17) * S * K))
    for x, y, r in blobs:
        d.ellipse([x - r - 3 * K, y - r - 3 * K, x + r + 3 * K, y + r + 3 * K], fill=(120, 150, 190))
    for x, y, r in blobs:
        d.ellipse([x - r, y - r, x + r, y + r], fill=(206, 224, 246))
    for x, y, r in blobs:
        d.ellipse([x - r * 0.8 - r * 0.15, y - r * 0.8 - r * 0.2, x + r * 0.8 - r * 0.15, y + r * 0.8 - r * 0.2], fill=(250, 252, 255))
    for i in range(6):
        x, y = c + rng.uniform(-0.3, 0.3) * S * K, c + rng.uniform(-0.3, 0.3) * S * K
        d.ellipse([x - 4 * K, y - 4 * K, x + 4 * K, y + 4 * K], fill=(200, 235, 255))
    img = img.resize((S, S), Image.LANCZOS)
    img.save(os.path.join(OUT, f"Ground_{name}.png"))
    print("wrote", name)


AUTUMN = [(240, 128, 40), (226, 70, 44), (250, 196, 54), (196, 98, 46), (255, 160, 50)]
PARK = [(250, 206, 60), (232, 150, 40), (150, 196, 64), (120, 176, 60), (206, 92, 48)]
SEAWEED = [(56, 140, 84), (96, 168, 70), (40, 112, 96), (70, 150, 60)]
GOLD = [(255, 214, 70), (255, 190, 40), (255, 236, 130)]

if __name__ == "__main__":
    for i in range(3):
        clump(f"Autumn{i + 1}", AUTUMN, ["maple", "maple", "oak", "birch"], 20, 11 + i)
        clump(f"Park{i + 1}", PARK, ["birch", "oak", "maple"], 20, 31 + i)
    for i in range(2):
        clump(f"Seaweed{i + 1}", SEAWEED, ["blade"], 18, 51 + i, size_range=(0.6, 0.9))
        paper(f"Paper{i + 1}", 71 + i)
        snow(f"Snow{i + 1}", 91 + i)
    clump("Gold", GOLD, ["maple", "oak", "birch"], 20, 7)
