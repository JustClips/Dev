"""Weather mutation skins for the brick eggs.

An egg's texture is a brick-tile atlas (one 64 px brick per colour, art/blender/eggs.py)
above a small palette strip. A mutation repaints it: every pixel goes through the
mutation's colour map (keeping the bevel and stud shading), then each brick tile gets the
mutation's detail on top (frost on Frozen bricks, a water bead on Wet ones, sparks on
Charged, cracks on Bloodlit, little stars on Starlit, mirror facets on Disco...). The game
swaps the egg's TextureID to the skin (AssetLibrary.applyMutation) and adds the mutation's
3D add-on (art/blender/egg_mutations.py).

  python3 tools/egg_skins.py <dir with Egg_<Rarity>.glb>   # -> art/out/ui/EggSkin_<Rarity>_<Mutation>.png
      (build the eggs first: art/blender/eggs.py EGGS -> export)
  python3 tools/egg_skins.py <dir> --sheet out.png           # also a preview sheet
Then upload with tools/upload_assets.py.
"""
import colorsys
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
from pet_skins import glb_image  # noqa: E402

UI = os.path.join(ROOT, "art", "out", "ui")
RARITIES = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Cosmic"]
TILE, TH = 64, 512          # brick tile size, height of the atlas part (palette strip below)


def hx(h):
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)])


def lum(img):
    return img[..., 0] * 0.299 + img[..., 1] * 0.587 + img[..., 2] * 0.114


def ramp(img, t, stops):
    """Maps t (0..1, per pixel) through colour stops."""
    stops = [hx(s) for s in stops]
    n = len(stops) - 1
    x = np.clip(t, 0, 1) * n
    i = np.minimum(np.floor(x).astype(int), n - 1)
    f = (x - i)[..., None]
    a = np.stack(stops)[i]
    b = np.stack(stops)[i + 1]
    return a + (b - a) * f


def hsv_map(img, fn):
    out = np.empty_like(img)
    flat_in, flat_out = img.reshape(-1, 3), out.reshape(-1, 3)
    for k, (r, g, b) in enumerate(flat_in):
        flat_out[k] = fn(*colorsys.rgb_to_hsv(r, g, b))
    return out


# ---------------------------------------------------------------- colour maps (whole image)
# t = luminance stretched over the egg's own range, so pale and dark eggs both use the ramp.

def golden(img, t, k):
    return ramp(img, 0.08 + 0.78 * t, ["5A2E00", "C97A08", "F2B526", "FFE47A", "FFF6CC"])


def wet(img, t, k):
    out = hsv_map(img, lambda h, s, v: colorsys.hsv_to_rgb(h, min(1, s * 1.3 + 0.05), v * 0.74))
    return out * 0.8 + hx("2F6DFF") * 0.2


def frozen(img, t, k):
    ice = ramp(img, t, ["4F93D0", "A9DAF5", "F4FCFF"])
    return img * 0.2 + ice * 0.8


def shocked(img, t, k):
    return ramp(img, t, ["15123A", "3B2C9A", "8E7BFF", "FFF07A"])


def windswept(img, t, k):
    warm = ramp(img, t, ["5A2410", "D8641E", "FFB04A", "FFE6B0"])
    return img * 0.45 + warm * 0.55


def bloodlit(img, t, k):
    return ramp(img, t, ["1A0206", "5C0A14", "B81E2A", "FF5A50"])


def starlit(img, t, k):
    return ramp(img, t, ["080C2E", "1E2C78", "4A6BE8", "9FB8FF"])


def starstruck(img, t, k):
    return ramp(img, 0.1 + 0.8 * t, ["6A3206", "D88A1C", "FFCB4A", "FFF2C0"])


def disco(img, t, k):
    return ramp(img, t, ["2E3242", "6C7488", "B8C0D4", "F2F4FA"])


def rainbow(img, t, k):
    # each brick colour gets its own hue (k = tile index map), lit by its own shading
    hue = (k * 0.137) % 1.0
    out = np.empty_like(img)
    for idx in np.unique(k):
        m = k == idx
        h = (idx * 0.137) % 1.0
        r, g, b = colorsys.hsv_to_rgb(h, 0.62, 1.0)
        out[m] = np.array([r, g, b]) * (0.45 + 0.6 * t[m][:, None])
    return np.clip(out, 0, 1)


# ---------------------------------------------------------------- per-brick detail
# Drawn in tile space: u right, v up, both 0..1 (image rows run downwards, so row = 1 - v).

def tile_uv():
    y, x = np.mgrid[0:TILE, 0:TILE]
    return (x + 0.5) / TILE, 1 - (y + 0.5) / TILE


U, V = tile_uv()
STUD = np.hypot(U - 0.5, V - 0.5) < 0.29


def paint(tile, mask, colour, alpha=1.0):
    c = hx(colour) if isinstance(colour, str) else np.array(colour)
    tile[mask] = tile[mask] * (1 - alpha) + c * alpha


def seg_mask(pts, width):
    """Mask of a polyline through pts (u, v) with the given width."""
    m = np.zeros((TILE, TILE), bool)
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        dx, dy = x1 - x0, y1 - y0
        L2 = dx * dx + dy * dy
        tt = np.clip(((U - x0) * dx + (V - y0) * dy) / L2, 0, 1)
        m |= np.hypot(U - (x0 + tt * dx), V - (y0 + tt * dy)) < width
    return m


def star_mask(cx, cy, r):
    d = np.abs(U - cx) * np.abs(V - cy)
    return ((np.abs(U - cx) < r * 0.18) & (np.abs(V - cy) < r)) | ((np.abs(V - cy) < r * 0.18) & (np.abs(U - cx) < r)) | (np.hypot(U - cx, V - cy) < r * 0.3)


def detail_frozen(tile, i, rnd):
    # snow on the top edge with a wavy lower edge, frost glints
    edge = 0.8 + 0.05 * np.sin(U * 9 + i) + 0.03 * np.sin(U * 23 + i * 2)
    paint(tile, V > edge, "FFFFFF", 0.92)
    paint(tile, (V > edge - 0.04) & (V <= edge), "D8EEFF", 0.7)
    for _ in range(2):
        cx, cy = rnd.uniform(0.15, 0.85), rnd.uniform(0.12, 0.6)
        paint(tile, star_mask(cx, cy, 0.07) & ~STUD, "FFFFFF", 0.85)


def detail_wet(tile, i, rnd):
    # a water bead with its own shine, and a wet streak
    cx, cy = 0.74, 0.26
    bead = np.hypot(U - cx, (V - cy) * 1.15) < 0.12
    paint(tile, bead, "9CC8FF", 0.65)
    paint(tile, np.hypot(U - cx + 0.035, V - cy - 0.04) < 0.035, "FFFFFF", 0.95)
    paint(tile, seg_mask([(0.12, 0.92), (0.12, 0.55)], 0.025), "FFFFFF", 0.45)


def detail_shocked(tile, i, rnd):
    # a small spark crackling across every third brick
    if i % 3:
        return
    y = rnd.uniform(0.3, 0.75)
    pts = [(0.04, y), (0.35, y + 0.14), (0.55, y - 0.1), (0.96, y + 0.06)]
    paint(tile, seg_mask(pts, 0.04), "FFF5A0", 0.3)
    paint(tile, seg_mask(pts, 0.014), "FFFFFF", 1.0)


def detail_bloodlit(tile, i, rnd):
    pts = [(rnd.uniform(0.1, 0.9), 0.98)]
    for _ in range(4):
        x, y = pts[-1]
        pts.append((min(0.95, max(0.05, x + rnd.uniform(-0.2, 0.2))), y - rnd.uniform(0.18, 0.28)))
    paint(tile, seg_mask(pts, 0.045), "FF3A20", 0.35)
    paint(tile, seg_mask(pts, 0.02), "FF8A50", 1.0)


def detail_starlit(tile, i, rnd):
    for _ in range(3):
        cx, cy = rnd.uniform(0.1, 0.9), rnd.uniform(0.1, 0.9)
        paint(tile, star_mask(cx, cy, rnd.uniform(0.04, 0.08)), "FFFFFF", 0.95)


def detail_starstruck(tile, i, rnd):
    cx, cy = rnd.choice([(0.15, 0.85), (0.85, 0.85), (0.15, 0.15), (0.85, 0.15)])
    paint(tile, star_mask(cx, cy, 0.11), "FFFFFF", 0.95)


def detail_golden(tile, i, rnd):
    shine = np.abs((U + V) - 1.15) < 0.05
    paint(tile, shine, "FFFFFF", 0.55)
    paint(tile, np.abs((U + V) - 1.32) < 0.02, "FFFFFF", 0.4)


DISCO_GLINTS = ["FF6AD5", "6AE8FF", "FFE45A", "9B7BFF", "6BFF9A"]


def detail_disco(tile, i, rnd):
    grid = (np.abs(U - 0.5) < 0.02) | (np.abs(V - 0.5) < 0.02) | (U < 0.04) | (V < 0.04)
    paint(tile, grid & ~STUD, "3A3F50", 0.7)
    q = rnd.randrange(4)
    qx, qy = (q % 2) * 0.5, (q // 2) * 0.5
    quad = (U >= qx + 0.04) & (U < qx + 0.48) & (V >= qy + 0.04) & (V < qy + 0.48) & ~STUD
    paint(tile, quad, DISCO_GLINTS[i % len(DISCO_GLINTS)], 0.75)
    paint(tile, star_mask(0.8, 0.8, 0.08), "FFFFFF", 1.0)


def detail_none(tile, i, rnd):
    pass


MUTATIONS = {
    "Golden": (golden, detail_golden),
    "Rainbow": (rainbow, detail_none),
    "Wet": (wet, detail_wet),
    "Shocked": (shocked, detail_shocked),
    "Frozen": (frozen, detail_frozen),
    "Windswept": (windswept, detail_none),
    "Bloodlit": (bloodlit, detail_bloodlit),
    "Starlit": (starlit, detail_starlit),
    "Starstruck": (starstruck, detail_starstruck),
    "Disco": (disco, detail_disco),
}


def tiles_of(img):
    """(row, col) of every used brick tile in the atlas (unused cells are flat white)."""
    out = []
    for ty in range(TH // TILE):
        for tx in range(img.shape[1] // TILE):
            cell = img[ty * TILE:(ty + 1) * TILE, tx * TILE:(tx + 1) * TILE]
            if cell.min() < 0.995:
                out.append((ty, tx))
    return out


def skin(src, mutation):
    import random
    img = np.asarray(src, dtype=float)[..., :3] / 255
    colour, detail = MUTATIONS[mutation]
    L = lum(img)
    used = L < 0.995
    lo, hi = (np.percentile(L[used], 2), np.percentile(L[used], 98)) if used.any() else (0, 1)
    t = np.clip((L - lo) / max(0.08, hi - lo), 0, 1)
    k = np.zeros(L.shape, int)   # tile index per pixel (palette strip = -1 -> its own hue)
    tiles = tiles_of(img)
    for idx, (ty, tx) in enumerate(tiles):
        k[ty * TILE:(ty + 1) * TILE, tx * TILE:(tx + 1) * TILE] = idx + 1
    out = colour(img, t, k)
    for idx, (ty, tx) in enumerate(tiles):
        rnd = random.Random(f"{mutation}{idx}")
        cell = out[ty * TILE:(ty + 1) * TILE, tx * TILE:(tx + 1) * TILE]
        detail(cell, idx, rnd)
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8))


def main():
    src_dir = sys.argv[1]
    os.makedirs(UI, exist_ok=True)
    sheet_path = sys.argv[sys.argv.index("--sheet") + 1] if "--sheet" in sys.argv else None
    rows = []
    for r in RARITIES:
        src = glb_image(os.path.join(src_dir, f"Egg_{r}.glb"))
        row = []
        src_tiles = tiles_of(np.asarray(src, dtype=float)[..., :3] / 255)
        for m in MUTATIONS:
            im = skin(src, m)
            im.save(os.path.join(UI, f"EggSkin_{r}_{m}.png"), optimize=True)
            row.append(im)
        rows.append((row, src_tiles))
        print("skins", r)
    if sheet_path:
        # the used brick tiles of each skin (up to 6), one row per rarity, a column per mutation
        n = 6
        cw = TILE * n + 8
        sheet = Image.new("RGB", (cw * len(MUTATIONS), (TILE + 8) * len(RARITIES)), (30, 34, 44))
        for ri, (row, src_tiles) in enumerate(rows):
            for mi, im in enumerate(row):
                for ti, (ty, tx) in enumerate(src_tiles[:n]):
                    cell = im.crop((tx * TILE, ty * TILE, (tx + 1) * TILE, (ty + 1) * TILE))
                    sheet.paste(cell, (mi * cw + ti * TILE, ri * (TILE + 8)))
        sheet.save(sheet_path)

if __name__ == "__main__":
    main()
