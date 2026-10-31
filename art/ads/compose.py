"""Turn the rendered scenes (art/ads/scenes.py) into finished ad thumbnails: big outlined
text, badges, sparkles, arrows and a before/after split.

Usage: python3 art/ads/compose.py RENDER_DIR OUT_DIR
Writes OUT_DIR/<ad>.png at 1920x1080 (Roblox sponsored ads and thumbnails are 16:9) plus
OUT_DIR/<ad>_notext.png for the image-only control, and OUT_DIR/contact_sheet.png.
Keep text in the top two thirds: Roblox draws the title / player count over the bottom.
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageEnhance, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(HERE, "..", "blender", "fonts", "Montserrat-Black.ttf")
W, H = 1920, 1080
INK = (20, 16, 40)

YELLOW = ((255, 247, 120), (255, 176, 0))
WHITE = ((255, 255, 255), (214, 232, 255))
GREEN = ((190, 255, 120), (40, 200, 60))
RED = ((255, 150, 120), (235, 40, 40))
CYAN = ((170, 255, 255), (40, 170, 255))
PINK = ((255, 190, 245), (230, 60, 200))
GOLD = ((255, 240, 150), (240, 150, 20))


def font(px):
    return ImageFont.truetype(FONT, px)


def gradient(size, top, bottom):
    w, h = size
    g = Image.new("RGBA", (1, h))
    for y in range(h):
        t = y / max(1, h - 1)
        g.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
    return g.resize((w, h))


def text_layer(text, px, fill=YELLOW, stroke=None, shadow=10, ink=INK):
    """Chunky game-thumbnail text: gradient fill, thick dark outline, hard drop shadow."""
    f = font(px)
    stroke = stroke or max(6, px // 9)
    l, t, r, b = f.getbbox(text, stroke_width=stroke)
    pad = stroke + shadow + 8
    w, h = r - l + pad * 2, b - t + pad * 2
    org = (pad - l, pad - t)
    lay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    # shadow
    d.text((org[0] + shadow * 0.6, org[1] + shadow), text, font=f, fill=ink + (200,), stroke_width=stroke, stroke_fill=ink + (200,))
    # outline
    d.text(org, text, font=f, fill=ink + (255,), stroke_width=stroke, stroke_fill=ink + (255,))
    # gradient fill through a mask
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).text(org, text, font=f, fill=255)
    bb = mask.getbbox()
    g = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    g.paste(gradient((w, bb[3] - bb[1]), *fill), (0, bb[1]))
    lay.paste(g, (0, 0), mask)
    # glossy top highlight
    hl = Image.new("L", (w, h), 0)
    hd = ImageDraw.Draw(hl)
    hd.rectangle((0, 0, w, bb[1] + (bb[3] - bb[1]) * 0.42), fill=70)
    hl = ImageChops.multiply(hl, mask)
    lay.paste((255, 255, 255, 255), (0, 0), hl)
    return lay


def put(img, layer, center, angle=0):
    if angle:
        layer = layer.rotate(angle, resample=Image.BICUBIC, expand=True)
    x = int(center[0] - layer.width / 2)
    y = int(center[1] - layer.height / 2)
    img.alpha_composite(layer, (max(-layer.width, x), max(-layer.height, y)))
    return layer.size


def title(img, text, center, px, fill=YELLOW, angle=-3, max_w=1800):
    lay = text_layer(text, px, fill)
    if lay.width > max_w:
        px = int(px * max_w / lay.width)
        lay = text_layer(text, px, fill)
    return put(img, lay, center, angle)


def badge(img, text, center, px, bg=(235, 40, 40), fg=(255, 255, 255), angle=0, pad=(28, 14), border=8):
    """Square label (no rounded corners, like the game's UI)."""
    f = font(px)
    l, t, r, b = f.getbbox(text)
    w, h = r - l + pad[0] * 2 + border * 2, b - t + pad[1] * 2 + border * 2
    lay = Image.new("RGBA", (w + 12, h + 12), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    d.rectangle((10, 12, w + 10, h + 10), fill=INK + (190,))
    d.rectangle((0, 0, w, h), fill=INK + (255,))
    d.rectangle((border, border, w - border, h - border), fill=bg + (255,))
    d.rectangle((border, border, w - border, border + (h - 2 * border) * 0.45), fill=tuple(min(255, c + 35) for c in bg) + (255,))
    d.text((border + pad[0] - l, border + pad[1] - t), text, font=f, fill=fg + (255,), stroke_width=max(2, px // 14), stroke_fill=INK + (255,))
    put(img, lay, center, angle)


def star(img, center, r, color=(255, 250, 200), glow=True):
    """Four-point sparkle with a soft glow."""
    lay = Image.new("RGBA", (int(r * 4), int(r * 4)), (0, 0, 0, 0))
    c = r * 2
    d = ImageDraw.Draw(lay)
    k = r * 0.22
    pts = [(c, c - r), (c + k, c - k), (c + r, c), (c + k, c + k), (c, c + r), (c - k, c + k), (c - r, c), (c - k, c - k)]
    if glow:
        g = Image.new("RGBA", lay.size, (0, 0, 0, 0))
        ImageDraw.Draw(g).ellipse((c - r * 0.8, c - r * 0.8, c + r * 0.8, c + r * 0.8), fill=color + (150,))
        lay.alpha_composite(g.filter(ImageFilter.GaussianBlur(r * 0.4)))
    d.polygon(pts, fill=color + (255,))
    img.alpha_composite(lay, (int(center[0] - c), int(center[1] - c)))


def sparkle_field(img, box, n, seed=1, rr=(14, 34), color=(255, 250, 200)):
    rnd = random.Random(seed)
    for _ in range(n):
        star(img, (rnd.uniform(box[0], box[2]), rnd.uniform(box[1], box[3])), rnd.uniform(*rr), color)


def glow(img, center, radius, color, strength=0.8):
    g = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(g).ellipse((center[0] - radius, center[1] - radius, center[0] + radius, center[1] + radius),
                              fill=color + (int(255 * strength),))
    g = g.filter(ImageFilter.GaussianBlur(radius * 0.45))
    # screen-like: add light
    base = img.convert("RGB")
    lit = ImageChops.screen(base, Image.composite(g.convert("RGB"), Image.new("RGB", img.size), g.split()[3]))
    img.paste(lit.convert("RGBA"))


def rays(img, center, color=(255, 240, 160), n=18, strength=0.35, length=1400):
    """Sun-burst rays, screened over the picture."""
    g = Image.new("L", img.size, 0)
    d = ImageDraw.Draw(g)
    for i in range(n):
        a0 = (i / n) * math.tau
        a1 = a0 + math.tau / n * 0.45
        d.polygon([center, (center[0] + math.cos(a0) * length, center[1] + math.sin(a0) * length),
                   (center[0] + math.cos(a1) * length, center[1] + math.sin(a1) * length)], fill=int(255 * strength))
    # fade with distance
    fade = Image.new("L", img.size, 0)
    ImageDraw.Draw(fade).ellipse((center[0] - length * 0.7, center[1] - length * 0.7, center[0] + length * 0.7, center[1] + length * 0.7), fill=255)
    fade = fade.filter(ImageFilter.GaussianBlur(length * 0.25))
    g = ImageChops.multiply(g, fade).filter(ImageFilter.GaussianBlur(3))
    col = Image.new("RGB", img.size, color)
    lit = ImageChops.screen(img.convert("RGB"), Image.composite(col, Image.new("RGB", img.size), g))
    img.paste(lit.convert("RGBA"))


def arrow(img, a, b, color=(255, 214, 0), width=46):
    """Chunky right-pointing arrow from a to b with a dark outline."""
    lay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    ang = math.atan2(b[1] - a[1], b[0] - a[0])
    L = math.dist(a, b)
    head = width * 1.5

    def pts(w, hl, ext):
        local = [(-ext, -w / 2), (L - hl, -w / 2), (L - hl, -w * 1.1), (L + ext * 1.6, 0), (L - hl, w * 1.1), (L - hl, w / 2), (-ext, w / 2)]
        return [(a[0] + x * math.cos(ang) - y * math.sin(ang), a[1] + x * math.sin(ang) + y * math.cos(ang)) for x, y in local]
    d.polygon([(x + 8, y + 10) for x, y in pts(width + 18, head, 9)], fill=INK + (170,))
    d.polygon(pts(width + 18, head, 9), fill=INK + (255,))
    d.polygon(pts(width, head - 4, 0), fill=color + (255,))
    img.alpha_composite(lay)


def bar(img, box, frac, fill=(60, 220, 90), label=None):
    x0, y0, x1, y1 = box
    d = ImageDraw.Draw(img)
    d.rectangle((x0 + 8, y0 + 10, x1 + 8, y1 + 10), fill=INK + (170,))
    d.rectangle(box, fill=INK + (255,))
    b = 8
    d.rectangle((x0 + b, y0 + b, x1 - b, y1 - b), fill=(60, 60, 80, 255))
    fx = x0 + b + (x1 - x0 - 2 * b) * frac
    d.rectangle((x0 + b, y0 + b, fx, y1 - b), fill=fill + (255,))
    d.rectangle((x0 + b, y0 + b, fx, y0 + b + (y1 - y0 - 2 * b) * 0.4), fill=tuple(min(255, c + 50) for c in fill) + (255,))
    if label:
        put(img, text_layer(label, int((y1 - y0) * 0.62), WHITE, shadow=4), ((x0 + x1) / 2, (y0 + y1) / 2 + 2))


def grade(img, sat=1.18, con=1.06, vignette=0.28):
    rgb = img.convert("RGB")
    rgb = ImageEnhance.Color(rgb).enhance(sat)
    rgb = ImageEnhance.Contrast(rgb).enhance(con)
    if vignette:
        m = Image.new("L", img.size, 0)
        ImageDraw.Draw(m).ellipse((-W * 0.15, -H * 0.25, W * 1.15, H * 1.25), fill=255)
        m = m.filter(ImageFilter.GaussianBlur(220))
        dark = ImageEnhance.Brightness(rgb).enhance(1 - vignette)
        rgb = Image.composite(rgb, dark, m)
    return rgb.convert("RGBA")


def load(rdir, name):
    return Image.open(os.path.join(rdir, name + ".png")).convert("RGBA").resize((W, H), Image.LANCZOS)


# ------------------------------------------------------------------ ads
def split(rdir, angle_px=160):
    """Messy left, clean right, diagonal white divider."""
    a, b = load(rdir, "messy"), load(rdir, "clean")
    m = Image.new("L", (W, H), 0)
    mid = W / 2
    ImageDraw.Draw(m).polygon([(mid + angle_px, 0), (W, 0), (W, H), (mid - angle_px, H)], fill=255)
    img = Image.composite(b, a, m)
    d = ImageDraw.Draw(img)
    d.line([(mid + angle_px, -10), (mid - angle_px, H + 10)], fill=INK + (255,), width=34)
    d.line([(mid + angle_px, -10), (mid - angle_px, H + 10)], fill=(255, 255, 255, 255), width=18)
    return img


def ad_before_after_100(rdir):
    img = grade(split(rdir))
    sparkle_field(img, (1100, 200, 1850, 800), 14, seed=2)
    badge(img, "0%", (330, 470), 92, bg=(235, 50, 50), angle=4)
    badge(img, "100%", (1600, 470), 92, bg=(40, 190, 70), angle=-4)
    title(img, "CLEAN 100%!", (W / 2, 175), 210, YELLOW, angle=-2)
    return img


def ad_before_after_words(rdir):
    img = grade(split(rdir))
    sparkle_field(img, (1100, 200, 1850, 800), 14, seed=3)
    title(img, "BEFORE", (430, 150), 150, RED, angle=3)
    title(img, "AFTER", (1490, 150), 150, GREEN, angle=-3)
    return img


def ad_noob_vs_pro(rdir):
    img = grade(load(rdir, "noob_vs_pro"))
    sparkle_field(img, (1060, 300, 1750, 850), 12, seed=4)
    title(img, "NOOB", (480, 170), 170, WHITE, angle=4)
    title(img, "PRO", (1450, 170), 190, GOLD, angle=-4)
    title(img, "VS", (W / 2, 300), 220, RED, angle=-8)
    return img


def ad_hatch(rdir):
    img = load(rdir, "hatch")
    rays(img, (W / 2, 470), (255, 235, 170), n=20, strength=0.4)
    glow(img, (W / 2, 520), 360, (140, 200, 255), 0.55)
    img = grade(img, vignette=0.35)
    sparkle_field(img, (450, 150, 1470, 850), 22, seed=5)
    title(img, "HATCH RARE PETS!", (W / 2, 135), 170, YELLOW, angle=-2)
    badge(img, "COSMIC", (W / 2, 890), 70, bg=(120, 70, 255), angle=-3)
    return img


def ad_money(rdir):
    img = load(rdir, "money")
    glow(img, (1180, 420), 380, (255, 220, 90), 0.5)
    img = grade(img)
    sparkle_field(img, (850, 120, 1650, 700), 18, seed=6)
    title(img, "LEAVES = $$$", (W / 2 - 40, 150), 200, GREEN, angle=-3)
    return img


def ad_giant_pile(rdir):
    img = grade(load(rdir, "giant_pile"), vignette=0.3)
    title(img, "CAN YOU CLEAN", (W / 2, 120), 150, WHITE, angle=-2)
    title(img, "THIS?!", (W / 2, 300), 230, YELLOW, angle=-2)
    return img


def ad_upgrade(rdir):
    img = load(rdir, "tools")
    glow(img, (1440, 470), 330, (190, 140, 255), 0.5)
    img = grade(img)
    sparkle_field(img, (1180, 160, 1800, 860), 16, seed=7)
    arrow(img, (520, 560), (700, 540))
    arrow(img, (1010, 540), (1190, 510))
    badge(img, "LVL 1", (330, 330), 60, bg=(140, 140, 160), angle=4)
    badge(img, "LVL 50", (880, 260), 64, bg=(50, 140, 255), angle=-2)
    badge(img, "LVL 999", (1460, 90), 74, bg=(170, 70, 255), angle=-4)
    title(img, "UPGRADE!", (520, 120), 170, YELLOW, angle=-4, max_w=1000)
    return img


def ad_car(rdir):
    img = grade(load(rdir, "car"))
    sparkle_field(img, (700, 350, 1150, 700), 10, seed=8)
    title(img, "DRIVE & CLEAN!", (W / 2, 140), 190, YELLOW, angle=-3)
    return img


def ad_pet_army(rdir):
    img = grade(load(rdir, "pet_army"))
    title(img, "GET A PET ARMY!", (W / 2, 135), 180, CYAN, angle=-2)
    return img


ADS = {
    "A_clean100_split": (ad_before_after_100, "split"),
    "B_before_after": (ad_before_after_words, "split"),
    "C_noob_vs_pro": (ad_noob_vs_pro, "noob_vs_pro"),
    "D_hatch_pets": (ad_hatch, "hatch"),
    "E_leaves_cash": (ad_money, "money"),
    "F_giant_pile": (ad_giant_pile, "giant_pile"),
    "G_upgrade_ladder": (ad_upgrade, "tools"),
    "H_sweeper_car": (ad_car, "car"),
    "I_pet_army": (ad_pet_army, "pet_army"),
}


def main(rdir, out):
    os.makedirs(out, exist_ok=True)
    thumbs = []
    for name, (fn, scene) in ADS.items():
        img = fn(rdir).convert("RGB")
        img.save(os.path.join(out, name + ".png"))
        img.save(os.path.join(out, name + ".jpg"), quality=92)
        raw = split(rdir) if scene == "split" else load(rdir, scene)
        if name != "B_before_after":
            grade(raw).convert("RGB").save(os.path.join(out, "notext_" + name.split("_", 1)[1] + ".jpg"), quality=92)
        thumbs.append((name, img))
    # contact sheet, plus how big they look on a phone (about 300 px wide)
    tw, th = 640, 360
    cols = 3
    rows = math.ceil(len(thumbs) / cols)
    sheet = Image.new("RGB", (cols * tw, rows * (th + 40)), (24, 24, 34))
    d = ImageDraw.Draw(sheet)
    for i, (n, im) in enumerate(thumbs):
        x, y = (i % cols) * tw, (i // cols) * (th + 40)
        sheet.paste(im.resize((tw, th), Image.LANCZOS), (x, y + 40))
        d.text((x + 10, y + 8), n, font=font(22), fill=(255, 255, 255))
    sheet.save(os.path.join(out, "contact_sheet.jpg"), quality=90)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
