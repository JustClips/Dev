"""Particle / beam textures for weather events and the Egg Rain.

  python3 art/vfx/textures.py   # writes art/out/ui/Vfx_*.png
  python3 tools/upload_assets.py  # uploads them as Images (Assets.Images.Vfx_*)

All white-on-transparent unless noted, so ParticleEmitter.Color / Beam.Color can tint them.
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "out", "ui")
os.makedirs(OUT, exist_ok=True)
SS = 4  # supersampling


def save(img, name, size):
    img = img.resize(size, Image.LANCZOS)
    img.save(os.path.join(OUT, f"Vfx_{name}.png"))
    print("wrote", name)


def canvas(w, h):
    return Image.new("RGBA", (w * SS, h * SS), (255, 255, 255, 0))


def alpha_from(mask, color=(255, 255, 255)):
    img = Image.new("RGBA", mask.size, color + (0,))
    img.putalpha(mask)
    return img


# Rain streak: thin, bright in the middle, fading at both ends.
def rain():
    w, h = 16, 128
    m = Image.new("L", (w * SS, h * SS), 0)
    px = m.load()
    for y in range(h * SS):
        t = y / (h * SS)
        a = math.sin(t * math.pi) ** 0.7 * (0.35 + 0.65 * t)
        for x in range(w * SS):
            d = abs(x - w * SS / 2) / (w * SS * 0.18)
            px[x, y] = int(255 * a * max(0, 1 - d * d))
    save(alpha_from(m.filter(ImageFilter.GaussianBlur(2))), "Rain", (w, h))


# Snowflake: six arms with little branches and a soft glow.
def snow():
    s = 128
    m = Image.new("L", (s * SS, s * SS), 0)
    d = ImageDraw.Draw(m)
    c = s * SS / 2
    r = s * SS * 0.42
    lw = int(SS * 5)
    for i in range(6):
        a = i * math.pi / 3
        ex, ey = c + math.cos(a) * r, c + math.sin(a) * r
        d.line([(c, c), (ex, ey)], fill=255, width=lw)
        for f in (0.45, 0.7):
            bx, by = c + math.cos(a) * r * f, c + math.sin(a) * r * f
            for side in (-1, 1):
                b = a + side * math.pi / 4
                l = r * (0.32 if f < 0.6 else 0.22)
                d.line([(bx, by), (bx + math.cos(b) * l, by + math.sin(b) * l)], fill=255, width=lw)
    d.ellipse([c - SS * 9, c - SS * 9, c + SS * 9, c + SS * 9], fill=255)
    glow = m.filter(ImageFilter.GaussianBlur(SS * 6)).point(lambda v: int(v * 0.6))
    m = Image.composite(m, glow, m)
    save(alpha_from(m), "Snow", (s, s))


# Leaf: pointed oval with a centre vein and side veins (veins slightly darker), white so it tints.
def leaf():
    s = 128
    img = canvas(s, s)
    d = ImageDraw.Draw(img)
    c = s * SS / 2
    pts = []
    for i in range(80):
        t = i / 79 * math.pi * 2
        x = math.sin(t) * s * SS * 0.24
        y = -math.cos(t) * s * SS * 0.44
        x *= 1 - 0.35 * abs(math.cos(t)) ** 3
        pts.append((c + x, c + y))
    d.polygon(pts, fill=(255, 255, 255, 255))
    vein = (200, 200, 200, 255)
    d.line([(c, c - s * SS * 0.42), (c, c + s * SS * 0.47)], fill=vein, width=SS * 3)
    for k in range(-3, 4):
        y0 = c + k * s * SS * 0.1
        for side in (-1, 1):
            d.line([(c, y0), (c + side * s * SS * 0.17, y0 - s * SS * 0.08)], fill=vein, width=SS * 2)
    # Keep the veins inside the leaf.
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    img.putalpha(mask)
    save(img, "Leaf", (s, s))


# Soft round glow (light motes, flashes, egg glow).
def glow():
    s = 128
    m = Image.new("L", (s, s), 0)
    px = m.load()
    for y in range(s):
        for x in range(s):
            r = math.hypot(x - s / 2 + 0.5, y - s / 2 + 0.5) / (s / 2)
            px[x, y] = int(255 * max(0, 1 - r) ** 2.2)
    save(alpha_from(m.resize((s * SS, s * SS))), "Glow", (s, s))


# Four-point sparkle star with a glow core.
def star():
    s = 128
    m = Image.new("L", (s, s), 0)
    px = m.load()
    for y in range(s):
        for x in range(s):
            dx, dy = abs(x - s / 2 + 0.5) / (s / 2), abs(y - s / 2 + 0.5) / (s / 2)
            ray = max(0, 1 - dx * 6) * max(0, 1 - dy) + max(0, 1 - dy * 6) * max(0, 1 - dx)
            core = max(0, 1 - math.hypot(dx, dy) * 2.2) ** 2
            px[x, y] = int(255 * min(1, ray ** 1.5 + core))
    save(alpha_from(m.resize((s * SS, s * SS))), "Star", (s, s))


# Ring (landing marker under a falling egg, splash).
def ring():
    s = 256
    m = Image.new("L", (s * SS, s * SS), 0)
    d = ImageDraw.Draw(m)
    c = s * SS / 2
    r = s * SS * 0.44
    d.ellipse([c - r, c - r, c + r, c + r], outline=255, width=SS * 14)
    inner = Image.new("L", m.size, 0)
    ImageDraw.Draw(inner).ellipse([c - r * 0.82, c - r * 0.82, c + r * 0.82, c + r * 0.82], fill=70)
    m = Image.composite(m, inner.filter(ImageFilter.GaussianBlur(SS * 20)), m)
    save(alpha_from(m.filter(ImageFilter.GaussianBlur(SS))), "Ring", (s, s))


# Trail: bright head fading to nothing (U = along the trail).
def trail():
    w, h = 128, 32
    m = Image.new("L", (w, h), 0)
    px = m.load()
    for y in range(h):
        v = 1 - abs(y - h / 2 + 0.5) / (h / 2)
        for x in range(w):
            u = 1 - x / (w - 1)
            px[x, y] = int(255 * (u ** 1.6) * v ** 1.2)
    save(alpha_from(m.resize((w * SS, h * SS))), "Trail", (w, h))


# Rainbow band for a curved Beam: colour stripes across the beam's width (V), soft edges.
def rainbow():
    w, h = 8, 256
    img = Image.new("RGBA", (w, h))
    px = img.load()
    cols = [(255, 70, 70), (255, 150, 50), (255, 230, 60), (90, 220, 90), (60, 170, 255), (110, 90, 255), (190, 90, 255)]
    for y in range(h):
        t = y / (h - 1)
        f = t * (len(cols) - 1)
        i = min(int(f), len(cols) - 2)
        k = f - i
        c = tuple(int(cols[i][j] * (1 - k) + cols[i + 1][j] * k) for j in range(3))
        edge = min(t, 1 - t) / 0.12
        a = int(220 * min(1, edge))
        for x in range(w):
            px[x, y] = c + (a,)
    img.save(os.path.join(OUT, "Vfx_Rainbow.png"))
    print("wrote Rainbow")


# Aurora curtain: bright lower edge, streaks fading upward (V = up the curtain), white to tint.
def aurora():
    w, h = 256, 256
    rng = random.Random(4)
    streak = [0.5 + 0.5 * rng.random() for _ in range(w)]
    for _ in range(3):
        streak = [(streak[i - 1] + streak[i] * 2 + streak[(i + 1) % w]) / 4 for i in range(w)]
    m = Image.new("L", (w, h), 0)
    px = m.load()
    for y in range(h):
        t = y / (h - 1)  # 0 top, 1 bottom
        base = (t ** 2.5) * 0.9 + (math.exp(-((1 - t) * 14)) * 0.6)
        side = min(t, 1 - t)
        for x in range(w):
            px[x, y] = int(255 * min(1, base * streak[x]) * min(1, (1 - t) * 12 + 0.0) * min(1, side * 30 + 0.2))
    save(alpha_from(m.resize((w * 2, h * 2)).filter(ImageFilter.GaussianBlur(2))), "Aurora", (w, h))


# Big red moon for the Blood Moon sky (Sky.MoonTextureId).
def blood_moon():
    s = 256
    img = Image.new("RGBA", (s * SS, s * SS), (0, 0, 0, 0))
    c = s * SS / 2
    r = s * SS * 0.36
    halo = Image.new("L", img.size, 0)
    ImageDraw.Draw(halo).ellipse([c - r * 1.25, c - r * 1.25, c + r * 1.25, c + r * 1.25], fill=150)
    halo = halo.filter(ImageFilter.GaussianBlur(SS * 22))
    img = Image.composite(Image.new("RGBA", img.size, (255, 40, 40, 255)), img, halo)
    disk = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(disk)
    d.ellipse([c - r, c - r, c + r, c + r], fill=(205, 38, 38, 255))
    rng = random.Random(7)
    for _ in range(14):
        a, k = rng.random() * math.tau, rng.random() ** 0.6 * 0.75
        cr = r * (0.07 + rng.random() * 0.12)
        x, y = c + math.cos(a) * r * k, c + math.sin(a) * r * k
        d.ellipse([x - cr, y - cr, x + cr, y + cr], fill=(150, 20, 25, 255))
    img.alpha_composite(disk)
    save(img, "BloodMoon", (s, s))


# Music note for the disco.
def note():
    s = 128
    m = Image.new("L", (s * SS, s * SS), 0)
    d = ImageDraw.Draw(m)
    k = SS
    d.ellipse([22 * k, 82 * k, 58 * k, 108 * k], fill=255)
    d.ellipse([70 * k, 70 * k, 106 * k, 96 * k], fill=255)
    d.rectangle([50 * k, 22 * k, 58 * k, 96 * k], fill=255)
    d.rectangle([98 * k, 12 * k, 106 * k, 84 * k], fill=255)
    d.polygon([(50 * k, 22 * k), (106 * k, 10 * k), (106 * k, 28 * k), (50 * k, 40 * k)], fill=255)
    save(alpha_from(m), "Note", (s, s))


# Mirror-ball facets for a SpecialMesh sphere (UV wraps around it): bright square tiles
# with dark grout and a few hot spots.
def disco_tiles():
    w, h = 512, 256
    img = Image.new("RGBA", (w, h), (40, 40, 48, 255))
    d = ImageDraw.Draw(img)
    rng = random.Random(3)
    cell = 16
    for y in range(0, h, cell):
        for x in range(0, w, cell):
            v = rng.randint(150, 235)
            tint = rng.choice([(1, 1, 1), (1, 0.9, 1), (0.9, 0.95, 1), (1, 1, 0.92)])
            c = tuple(int(v * t) for t in tint)
            if rng.random() < 0.06:
                c = (255, 255, 255)
            d.rectangle([x + 1, y + 1, x + cell - 2, y + cell - 2], fill=c + (255,))
    img.save(os.path.join(OUT, "Vfx_DiscoTiles.png"))
    print("wrote DiscoTiles")


# Confetti: a small rectangle with a fold line (white so it tints).
def confetti():
    s = 64
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([14, 22, 50, 42], fill=(255, 255, 255, 255))
    d.line([(32, 22), (32, 42)], fill=(215, 215, 215, 255), width=2)
    img.save(os.path.join(OUT, "Vfx_Confetti.png"))
    print("wrote Confetti")


# Rain curtain for far-away rain sheets (Beam texture, tiles in both directions).
def rain_sheet():
    w, h = 256, 256
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    rng = random.Random(11)
    for _ in range(260):
        x = rng.randrange(w)
        y = rng.randrange(h)
        l = rng.randint(18, 46)
        a = rng.randint(60, 200)
        for k in (-h, 0, h):
            d.line([(x, y + k), (x - 3, y + l + k)], fill=a, width=1)
    m = m.filter(ImageFilter.GaussianBlur(0.6))
    alpha_from(m).save(os.path.join(OUT, "Vfx_RainSheet.png"))
    print("wrote RainSheet")


# Scorch mark left by lightning (dark, soft, with cracks).
def scorch():
    s = 256
    m = Image.new("L", (s * SS, s * SS), 0)
    d = ImageDraw.Draw(m)
    c = s * SS / 2
    d.ellipse([c - s * SS * 0.3, c - s * SS * 0.3, c + s * SS * 0.3, c + s * SS * 0.3], fill=200)
    rng = random.Random(5)
    for i in range(9):
        a = i / 9 * math.tau + rng.random() * 0.4
        x, y = c, c
        for _ in range(6):
            nx = x + math.cos(a) * s * SS * 0.07
            ny = y + math.sin(a) * s * SS * 0.07
            d.line([(x, y), (nx, ny)], fill=230, width=SS * 4)
            x, y, a = nx, ny, a + rng.uniform(-0.6, 0.6)
    m = m.filter(ImageFilter.GaussianBlur(SS * 6))
    alpha_from(m, (20, 16, 14)).resize((s, s), Image.LANCZOS).save(os.path.join(OUT, "Vfx_Scorch.png"))
    print("wrote Scorch")


# Soft filled light spot (disco floor lights, strike glow on the ground).
def spot():
    s = 128
    m = Image.new("L", (s, s), 0)
    px = m.load()
    for y in range(s):
        for x in range(s):
            r = math.hypot(x - s / 2 + 0.5, y - s / 2 + 0.5) / (s / 2)
            px[x, y] = int(255 * min(1, max(0, (1 - r) * 2.2)) ** 1.5)
    alpha_from(m).save(os.path.join(OUT, "Vfx_Spot.png"))
    print("wrote Spot")


# Water droplet for splashes.
def droplet():
    s = 64
    m = Image.new("L", (s * SS, s * SS), 0)
    d = ImageDraw.Draw(m)
    k = SS
    d.ellipse([20 * k, 26 * k, 44 * k, 50 * k], fill=255)
    d.polygon([(32 * k, 8 * k), (21 * k, 34 * k), (43 * k, 34 * k)], fill=255)
    save(alpha_from(m), "Droplet", (s, s))


def moon(name, base, crater, glow):
    s = 256
    img = Image.new("RGBA", (s * SS, s * SS), (0, 0, 0, 0))
    c = s * SS / 2
    r = s * SS * 0.36
    halo = Image.new("L", img.size, 0)
    ImageDraw.Draw(halo).ellipse([c - r * 1.25, c - r * 1.25, c + r * 1.25, c + r * 1.25], fill=150)
    halo = halo.filter(ImageFilter.GaussianBlur(SS * 22))
    img = Image.composite(Image.new("RGBA", img.size, glow + (255,)), img, halo)
    disk = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(disk)
    d.ellipse([c - r, c - r, c + r, c + r], fill=base + (255,))
    rng = random.Random(7)
    for _ in range(14):
        a, k2 = rng.random() * math.tau, rng.random() ** 0.6 * 0.75
        cr = r * (0.07 + rng.random() * 0.12)
        x, y = c + math.cos(a) * r * k2, c + math.sin(a) * r * k2
        d.ellipse([x - cr, y - cr, x + cr, y + cr], fill=crater + (255,))
    img.alpha_composite(disk)
    save(img, name, (s, s))


def rainbow_moon():
    s = 256
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    px = img.load()
    c = s / 2
    r = s * 0.36
    for y in range(s):
        for x in range(s):
            dx, dy = x - c + 0.5, y - c + 0.5
            dist = math.hypot(dx, dy)
            hue = (math.atan2(dy, dx) / math.tau + 0.5 + dist / s * 0.6) % 1
            import colorsys
            cr, cg, cb = colorsys.hsv_to_rgb(hue, 0.55, 1)
            if dist <= r:
                px[x, y] = (int(cr * 255), int(cg * 255), int(cb * 255), 255)
            elif dist <= r * 1.35:
                a = int(170 * (1 - (dist - r) / (r * 0.35)) ** 2)
                px[x, y] = (int(cr * 255), int(cg * 255), int(cb * 255), a)
    img.save(os.path.join(OUT, "Vfx_RainbowMoon.png"))
    print("wrote RainbowMoon")


for f in (rain, snow, leaf, glow, star, ring, trail, rainbow, aurora, blood_moon, note,
          disco_tiles, confetti, rain_sheet, scorch, spot, droplet, rainbow_moon):
    f()
moon("GoldMoon", (255, 205, 70), (225, 160, 40), (255, 190, 60))
moon("MegaMoon", (235, 240, 255), (190, 200, 225), (180, 210, 255))
