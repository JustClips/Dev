"""Leaf piles (Clump_*) and long heaps (Drift_*) that replace the flat leaf ground images.

Each one is a single textured part "Clump" (collide off): a low lumpy bed with a ragged rim
plus overlapping curled leaves (or seaweed, paper, grass, shells) lying on it. Every model of
a zone shares one painted 512x512 atlas (art/out/ui/PileAtlas_<Zone>.png, also uploaded as an
image so the game can point all of a zone's piles at the same TextureID):
- 12 cells of 128 px (rows 0-2 and the left half of row 3) hold one leaf or item each, with
  veins, colour variation and edge browning painted in. A leaf's mesh outline matches the
  painted outline, so no alpha is needed.
- The bottom-right 256x256 block is the bed: a dense litter of small leaves.
Pivot at the bottom centre, Blender +Z up (= Roblox +Y). Clumps are about 5.5 x 5.5 with a
ragged rim; drifts are about 7 x 3 x 0.8 with the high side at +Y (Roblox +Z, against the
fence) sloping down toward -Y (Roblox -Z). Everything stays under 250 triangles.
"""
import math
import os
import random

import bpy
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

from lib import Asset

HERE = os.path.dirname(os.path.abspath(__file__))
ATLAS_DIR = os.path.join(HERE, "..", "out", "ui")
SIZE, CELL, MARGIN = 512, 128, 0.07
BED_PX = (256, 256, 256)          # x0, y0 (from the top-left), size
SINK = -0.03                      # rim height: just under the ground so no seam shows


def hexf(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)])


# ------------------------------------------------------------------ outlines (unit size)
# Leaves are about 1 long along Y (stem at +Y, tip at -Y), listed counter-clockwise.

def polar(points, sx=1.0, sy=1.0):
    out = []
    for a, r in points:
        t = math.radians(a)
        out.append((math.sin(t) * r * sx, -math.cos(t) * r * sy))
    return out


MAPLE = polar([(0, 0.5), (28, 0.24), (52, 0.46), (82, 0.24), (112, 0.4), (148, 0.2), (180, 0.3),
               (212, 0.2), (248, 0.4), (278, 0.24), (308, 0.46), (332, 0.24)])
OAK = polar([(0, 0.5), (20, 0.3), (40, 0.42), (62, 0.27), (85, 0.42), (110, 0.27), (138, 0.38), (165, 0.24),
             (180, 0.32), (195, 0.24), (222, 0.38), (250, 0.27), (275, 0.42), (298, 0.27), (320, 0.42), (340, 0.3)], 0.85, 1.05)
BIRCH = polar([(0, 0.52), (35, 0.36), (80, 0.3), (130, 0.31), (180, 0.38), (230, 0.31), (280, 0.3), (325, 0.36)], 0.78, 1.0)
SQUARE = [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)]
VEINS = {"maple": "palm", "oak": "palm", "birch": "pinnate"}
SHAPES = {"maple": MAPLE, "oak": OAK, "birch": BIRCH}


def ccw(outline):
    a = sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(outline, outline[1:] + outline[:1]))
    return outline if a > 0 else list(reversed(outline))


# ------------------------------------------------------------------ painting

def cell_box(i):
    """Top-left pixel of leaf cell i (12 cells, skipping the bed block)."""
    cells = [(c, r) for r in range(4) for c in range(4) if not (r >= 2 and c >= 2)]
    c, r = cells[i]
    return c * CELL, r * CELL


def cell_grid():
    """Unit coordinates (x right, y up, -0.5..0.5 inside the margin) of each pixel in a cell."""
    p = (np.arange(CELL) + 0.5) / CELL
    u = (p - MARGIN) / (1 - 2 * MARGIN) - 0.5
    x, y = np.meshgrid(u, -u)         # image rows go down, unit y goes up
    return x, y


def signed_dist(x, y, outline):
    """Signed distance to a polygon (positive inside)."""
    inside = np.zeros_like(x, dtype=bool)
    d = np.full_like(x, 1e9)
    n = len(outline)
    for i in range(n):
        (x0, y0), (x1, y1) = outline[i], outline[(i + 1) % n]
        inside ^= ((y0 > y) != (y1 > y)) & (x < (x1 - x0) * (y - y0) / (y1 - y0 + 1e-12) + x0)
        ex, ey = x1 - x0, y1 - y0
        t = np.clip(((x - x0) * ex + (y - y0) * ey) / (ex * ex + ey * ey), 0, 1)
        d = np.minimum(d, np.hypot(x - x0 - t * ex, y - y0 - t * ey))
    return np.where(inside, d, -d)


def seg_dist(x, y, a, b):
    ax, ay = a
    bx, by = b
    ex, ey = bx - ax, by - ay
    t = np.clip(((x - ax) * ex + (y - ay) * ey) / (ex * ex + ey * ey + 1e-12), 0, 1)
    return np.hypot(x - ax - t * ex, y - ay - t * ey)


def wobble(x, y, rnd, amp=1.0, freq=6.0):
    """Cheap smooth noise from a few random sine waves (about -1..1)."""
    v = np.zeros_like(x)
    for _ in range(5):
        a = rnd.uniform(0, math.tau)
        f = freq * rnd.uniform(0.6, 1.6)
        v += np.sin((x * math.cos(a) + y * math.sin(a)) * f + rnd.uniform(0, math.tau))
    return v / 2.5 * amp


def paint_leaf(img, i, shape, base, edge=None, vein=None, seed=1):
    rnd = random.Random(seed)
    x, y = cell_grid()
    outline = SHAPES[shape]
    d = signed_dist(x, y, outline)
    base = hexf(base)
    col = base[None, None, :] * (1 + 0.1 * wobble(x, y, rnd)[..., None] + 0.12 * (-y)[..., None])
    dd = np.maximum(d, 0)
    # browned edges, or just a slightly darker rim
    if edge:
        t = np.clip(1 - dd / 0.11, 0, 1) ** 1.4 * (0.75 + 0.25 * wobble(x, y, rnd, 1, 14))[...]
        t = np.clip(t, 0, 1)[..., None]
        col = col * (1 - t) + hexf(edge)[None, None, :] * t
    else:
        col = col * (1 - 0.18 * np.clip(1 - dd / 0.035, 0, 1))[..., None]
    # veins: a midrib plus side veins, lighter than the leaf
    vcol = hexf(vein) if vein else np.clip(base * 1.25 + 0.06, 0, 1)
    w = np.full_like(x, 1e9)
    w = np.minimum(w, seg_dist(x, y, (0, 0.5), (0, -0.45)) / 0.013)
    if VEINS[shape] == "palm":
        for px, py in outline:
            if math.hypot(px, py) > 0.38:
                w = np.minimum(w, seg_dist(x, y, (0, 0.08), (px * 0.85, py * 0.85)) / 0.009)
    else:
        for k in range(5):
            y0 = 0.32 - k * 0.16
            for s in (-1, 1):
                w = np.minimum(w, seg_dist(x, y, (0, y0), (s * 0.34, y0 - 0.2)) / 0.008)
    vt = (np.clip(1.4 - w, 0, 1) * (d > 0.01))[..., None] * 0.45
    col = col * (1 - vt) + vcol[None, None, :] * vt
    put(img, *cell_box(i), col)


def paint_square(img, i, fn, seed=1):
    """A non-leaf item filling its whole cell; fn(x, y, rnd) -> colour array."""
    rnd = random.Random(seed)
    x, y = cell_grid()
    put(img, *cell_box(i), fn(x, y, rnd))


def put(img, x0, y0, col):
    img[y0:y0 + col.shape[0], x0:x0 + col.shape[1], :] = np.clip(col, 0, 1)


def paint_bed(img, bg, stamps, seed=1, count=460, size=(6, 14), dark=(0.55, 0.92), kind="leaf", ratio=0.5):
    """Dense litter: a noisy background with lots of small rotated leaf or scrap stamps."""
    rnd = random.Random(seed)
    x0, y0, s = BED_PX
    yy, xx = np.mgrid[0:s, 0:s].astype(float)
    col = hexf(bg)[None, None, :] * (1 + 0.12 * wobble(xx / s, yy / s, rnd, 1, 18))[..., None]
    for _ in range(count):
        cx, cy = rnd.uniform(-8, s + 8), rnd.uniform(-8, s + 8)
        a = rnd.uniform(0, math.pi)
        r = rnd.uniform(*size)
        c = hexf(rnd.choice(stamps)) * rnd.uniform(*dark)
        lo_x, hi_x = int(max(cx - r - 2, 0)), int(min(cx + r + 2, s))
        lo_y, hi_y = int(max(cy - r - 2, 0)), int(min(cy + r + 2, s))
        if lo_x >= hi_x or lo_y >= hi_y:
            continue
        px, py = xx[lo_y:hi_y, lo_x:hi_x] - cx, yy[lo_y:hi_y, lo_x:hi_x] - cy
        u = px * math.cos(a) + py * math.sin(a)
        v = -px * math.sin(a) + py * math.cos(a)
        patch = col[lo_y:hi_y, lo_x:hi_x]
        if kind == "leaf":
            half = r * ratio * np.clip(1 - (u / r) ** 2, 0, 1)
            inside = (np.abs(u) < r) & (np.abs(v) < half)
            rim = (np.abs(u) < r + 1) & (np.abs(v) < half + 1.1) & ~inside
            shade_ = 1.08 - 0.3 * np.abs(v) / (half + 1e-6)
            shade_ = np.where(np.abs(v) < 0.7, shade_ * 0.82, shade_)
            patch[rim] *= 0.72
        else:                               # rectangles (paper scraps)
            inside = (np.abs(u) < r) & (np.abs(v) < r * ratio)
            shade_ = 1 - 0.15 * np.abs(v) / (r * ratio)
        patch[inside] = c[None, :] * shade_[inside][:, None]
    put(img, x0, y0, col)


def save_atlas(name, img):
    os.makedirs(ATLAS_DIR, exist_ok=True)
    path = os.path.abspath(os.path.join(ATLAS_DIR, f"PileAtlas_{name}.png"))
    bimg = bpy.data.images.new(f"PileAtlas_{name}", SIZE, SIZE, alpha=False)
    px = np.ones((SIZE, SIZE, 4))
    px[..., :3] = img[::-1]                 # Blender images start at the bottom row
    bimg.pixels = px.ravel().tolist()
    bimg.filepath_raw = path
    bimg.file_format = "PNG"
    bimg.save()
    bpy.data.images.remove(bimg)
    return path


# ------------------------------------------------------------------ zone atlases
# Each zone lists its 12 cells: (kind, args). Leaves are ("leaf", shape, base, edge, vein).

AUTUMN = [
    ("leaf", "maple", "E8742A", None, None), ("leaf", "maple", "C8321E", None, None),
    ("leaf", "maple", "F2B731", None, None), ("leaf", "maple", "E07B2C", "6B3B1A", None),
    ("leaf", "oak", "A8642E", None, None), ("leaf", "oak", "D9822B", "7A4A20", None),
    ("leaf", "oak", "B4402A", None, None), ("leaf", "birch", "F3C33A", None, None),
    ("leaf", "birch", "E9A62C", "8A5A22", None), ("leaf", "birch", "F7D65A", None, None),
    ("leaf", "maple", "8A4F24", None, "B57C45"), ("leaf", "oak", "E2A13A", None, None),
]
PARK = [
    ("leaf", "maple", "5BA83A", None, None), ("leaf", "maple", "8CC63F", None, None),
    ("leaf", "oak", "4E9632", None, None), ("leaf", "oak", "9BC844", "C9B648", None),
    ("leaf", "birch", "A9D04A", None, None), ("leaf", "birch", "D4D850", None, None),
    ("leaf", "maple", "C2CF45", "8F9A30", None), ("leaf", "birch", "6FB53E", None, None),
    ("grass", "4E9A2E", "B6E35A"), ("grass", "3E8A2A", "9AD24C"),
    ("leaf", "oak", "7DB83C", None, None), ("leaf", "maple", "E0C04A", None, None),
]
SEAWEED = [
    ("strand", "2F6B3A", "6FAF4E"), ("strand", "4A6A22", "9CB04A"), ("strand", "5A4A22", "A88A3A"),
    ("strand", "2E5A48", "5FA884"), ("shell", "F7B7A3", "D9786A"), ("shell", "F6EBD9", "C9A77E"),
    ("shell", "F2A65A", "C0622E"), ("leaf", "oak", "8A6A2E", None, None),
    ("leaf", "birch", "A88A3A", None, None), ("strand", "3A7A2E", "7FC25A"),
    ("shell", "B9D7F0", "6C93C2"), ("leaf", "maple", "9A5A2A", None, None),
]
PAPER = [
    ("paper", "F4F1E8", "lined"), ("paper", "E8E6DE", "news"), ("paper", "F7F3EA", "plain"),
    ("paper", "EEDCB8", "plain"), ("wrapper", "E8343C", "FFD23C"), ("wrapper", "2E6FD8", "FFFFFF"),
    ("wrapper", "4CB050", "F2F2F2"), ("wrapper", "F2A23C", "8A3AB8"),
    ("leaf", "maple", "D9822B", None, None), ("leaf", "oak", "A8642E", None, None),
    ("leaf", "birch", "F3C33A", None, None), ("paper", "F2EFE6", "news"),
]
SNOW = [
    ("leaf", "maple", "B4402A", None, None), ("leaf", "oak", "8A5A2E", None, None),
    ("leaf", "birch", "D9A23A", None, None), ("leaf", "maple", "C76A2A", "6B3B1A", None),
    ("snow", "F4F8FF", "C9D9EE"), ("snow", "EEF4FD", "B9CCE6"),
    ("leaf", "oak", "A0522D", None, None), ("leaf", "birch", "C9A040", None, None),
    ("leaf", "maple", "7A3B22", None, None), ("snow", "FFFFFF", "D2E0F2"),
    ("leaf", "oak", "B07A3A", None, None), ("leaf", "maple", "D88A30", None, None),
]
GOLD = [
    ("leaf", "maple", "F6C744", "C08A1E", "FFF0A0"), ("leaf", "maple", "E8B030", None, "FFE68A"),
    ("leaf", "maple", "FFD95A", "D79A26", "FFF6C0"), ("leaf", "oak", "E5A92A", None, "FFE07A"),
    ("leaf", "oak", "F7CF4E", "BC8520", "FFF2B0"), ("leaf", "birch", "FFE26A", None, "FFF8D0"),
    ("leaf", "birch", "EDB838", "B98222", "FFEA9A"), ("leaf", "oak", "D99A22", None, "FFD860"),
    ("leaf", "maple", "FFCF3A", None, "FFF3B8"), ("leaf", "birch", "F2C040", None, "FFF0A8"),
    ("leaf", "maple", "C98A1A", None, "F5D068"), ("leaf", "oak", "FFE88A", "D8A030", "FFFBE0"),
]

BEDS = {
    "Autumn": dict(bg="4A301A", stamps=["C8621E", "A8321E", "D9A22A", "8A5A24", "B4702E", "E08A2C"]),
    "Park": dict(bg="2F4A1C", stamps=["5BA83A", "8CC63F", "4E9632", "A9C84A", "6F9A2E", "C2CF45"]),
    "Seaweed": dict(bg="8A7656", stamps=["2F6B3A", "4A6A22", "5A4A22", "3A7A2E", "6A8A3A"], count=260, size=(8, 20), ratio=0.22),
    "Paper": dict(bg="5E5446", stamps=["F4F1E8", "E8E6DE", "D8D2C0", "C8C2B0", "F4F1E8", "D9822B", "A8642E", "E8343C", "2E6FD8"],
                  kind="rect", size=(4, 10), count=260, ratio=0.6),
    "Snow": dict(bg="EEF4FC", stamps=["FFFFFF"], count=0),
    "Gold": dict(bg="7A5410", stamps=["F6C744", "E8B030", "FFD95A", "D99A22", "FFE26A", "C98A1A"]),
}
ZONES = {"Autumn": AUTUMN, "Park": PARK, "Seaweed": SEAWEED, "Paper": PAPER, "Snow": SNOW, "Gold": GOLD}


def grass_fn(dark, light):
    def f(x, y, rnd):
        t = np.clip(y + 0.5, 0, 1)[..., None]
        c = hexf(dark)[None, None, :] * (1 - t) + hexf(light)[None, None, :] * t
        return c * (1 + 0.08 * np.sin(x * 40)[..., None])
    return f


def strand_fn(dark, light):
    def f(x, y, rnd):
        # flat kelp blade: ruffled darker edges, a thin pale midrib, cross wrinkles
        e = np.clip(np.abs(x) * 2, 0, 1)[..., None]
        c = hexf(dark)[None, None, :] * (1 - e * 0.5) + hexf(light)[None, None, :] * e * 0.5
        c = c * (1 + 0.1 * wobble(x, y, rnd, 1, 10)[..., None]) * (1 - 0.1 * (np.sin(y * 45 + x * 6) > 0.6)[..., None])
        rib = np.clip(1 - np.abs(x) / 0.03, 0, 1)[..., None] * 0.35
        return c * (1 - rib) + np.clip(hexf(light) * 1.3, 0, 1)[None, None, :] * rib
    return f


def shell_fn(light, dark):
    def f(x, y, rnd):
        r = np.hypot(x, y)
        ang = np.arctan2(y, x)
        ridge = (0.5 + 0.5 * np.sin(ang * 14)) * np.clip(r * 2, 0, 1)
        t = np.clip(r * 1.8, 0, 1)
        c = hexf(light)[None, None, :] * (1 - 0.35 * ridge[..., None]) * (1 - 0.15 * t[..., None])
        return c * (1 - 0.3 * t[..., None]) + hexf(dark)[None, None, :] * 0.3 * t[..., None]
    return f


def paper_fn(base, style):
    def f(x, y, rnd):
        c = hexf(base)[None, None, :] * (1 + 0.05 * wobble(x, y, rnd, 1, 9)[..., None])
        # crumple creases
        for _ in range(4):
            a = rnd.uniform(0, math.pi)
            off = rnd.uniform(-0.3, 0.3)
            line = np.abs(x * math.cos(a) + y * math.sin(a) - off)
            c = c * (1 - 0.12 * np.clip(1 - line / 0.02, 0, 1))[..., None]
        if style == "lined":
            c = np.where((np.mod(y + 0.5, 0.1) < 0.012)[..., None], hexf("8FB4E3")[None, None, :], c)
            c = np.where((np.abs(x + 0.33) < 0.008)[..., None], hexf("E88A8A")[None, None, :], c)
        elif style == "news":
            rows = (np.mod(y + 0.5, 0.07) < 0.035) & (np.abs(x) < 0.42)
            cols = np.mod(x + 0.5, 0.33) < 0.29
            gaps = wobble(x * 0.2, np.floor((y + 0.5) / 0.07), rnd, 1, 40) > -0.6
            c = np.where((rows & cols & gaps)[..., None], c * 0.55, c)
            c = np.where(((y > 0.3) & (y < 0.42) & (np.abs(x) < 0.42))[..., None], c * 0.3, c)
        return c
    return f


def wrapper_fn(base, stripe):
    def f(x, y, rnd):
        c = np.where((np.mod(x + y + 1, 0.25) < 0.1)[..., None], hexf(stripe)[None, None, :], hexf(base)[None, None, :])
        sheen = np.clip(1 - np.abs(x - y * 0.4 - 0.1) / 0.12, 0, 1)
        c = c * (1 + 0.15 * wobble(x, y, rnd, 1, 12)[..., None]) + 0.35 * sheen[..., None]
        return c
    return f


def snow_fn(light, shade):
    def f(x, y, rnd):
        t = np.clip(0.5 + 0.5 * wobble(x, y, rnd, 1, 5), 0, 1)[..., None]
        return hexf(light)[None, None, :] * (1 - 0.4 * t) + hexf(shade)[None, None, :] * 0.4 * t
    return f


_atlas_cache = {}


def atlas(zone):
    """Paint (once per build) and return (png path, cell list) for a zone."""
    if zone in _atlas_cache:
        return _atlas_cache[zone]
    cells = ZONES[zone]
    img = np.zeros((SIZE, SIZE, 3))
    for i, c in enumerate(cells):
        kind = c[0]
        if kind == "leaf":
            paint_leaf(img, i, c[1], c[2], c[3], c[4], seed=i * 7 + len(zone))
        elif kind == "grass":
            paint_square(img, i, grass_fn(c[1], c[2]), i)
        elif kind == "strand":
            paint_square(img, i, strand_fn(c[1], c[2]), i)
        elif kind == "shell":
            paint_square(img, i, shell_fn(c[1], c[2]), i)
        elif kind == "paper":
            paint_square(img, i, paper_fn(c[1], c[2]), i)
        elif kind == "wrapper":
            paint_square(img, i, wrapper_fn(c[1], c[2]), i)
        elif kind == "snow":
            paint_square(img, i, snow_fn(c[1], c[2]), i)
    paint_bed(img, seed=len(zone), **BEDS[zone])
    path = save_atlas(zone, img)
    _atlas_cache[zone] = (path, cells)
    return _atlas_cache[zone]


def cell_uv(i, x, y):
    """Unit coords inside cell i -> atlas UV."""
    cx, cy = cell_box(i)
    px = cx + ((x + 0.5) * (1 - 2 * MARGIN) + MARGIN) * CELL
    py = cy + ((0.5 - y) * (1 - 2 * MARGIN) + MARGIN) * CELL
    return px / SIZE, 1 - py / SIZE


def bed_uv(x, y, ext_x, ext_y):
    x0, y0, s = BED_PX
    px = x0 + (x / ext_x + 0.5) * s
    py = y0 + (0.5 - y / ext_y) * s
    return min(max(px / SIZE, 0.502), 0.998), min(max(1 - py / SIZE, 0.002), 0.498)


# ------------------------------------------------------------------ mesh building

class Builder:
    """Collects triangles with per-corner UVs, then makes one mesh object."""

    def __init__(self):
        self.verts, self.faces, self.uvs = [], [], []

    def add(self, verts, faces, uvs):
        base = len(self.verts)
        self.verts += [tuple(v) for v in verts]
        for f in faces:
            self.faces.append(tuple(base + k for k in f))
            self.uvs.append([uvs[k] for k in f])

    def tris(self):
        return sum(len(f) - 2 for f in self.faces)

    def bvh(self):
        return BVHTree.FromPolygons(self.verts, self.faces) if self.faces else None

    def make(self, name):
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.verts, [], self.faces)
        me.update()
        uv = me.uv_layers.new(name="UVMap").data
        k = 0
        for poly, fuv in zip(me.polygons, self.uvs):
            for li, u in zip(poly.loop_indices, fuv):
                uv[li].uv = u
        for poly in me.polygons:
            poly.use_smooth = True
        o = bpy.data.objects.new(name, me)
        bpy.context.collection.objects.link(o)
        return o


def bump(x, y, bumps):
    return sum(h * math.exp(-((x - bx) ** 2 + (y - by) ** 2) / (r * r)) for bx, by, r, h in bumps)


def clump_bed(b, rnd, R=2.9, H=0.26, rings=(5, 10, 16), lumps=4, extra=0.0):
    """Low dome with lumps and a ragged rim; returns the height function used."""
    bumps = [(rnd.uniform(-1.4, 1.4), rnd.uniform(-1.4, 1.4), rnd.uniform(0.6, 1.1), rnd.uniform(0.04, 0.09 + extra))
             for _ in range(lumps)]
    # rounded-square footprint (corners reach about 1.26 R) so a grid of tiles closes up
    # diagonally too, with a gently wavy, ragged rim
    waves = [(f, rnd.uniform(0, math.tau), amp) for f, amp in ((3, 0.04), (5, 0.04), (7, 0.03))]

    def square(a):
        return 1 / (abs(math.cos(a)) ** 6 + abs(math.sin(a)) ** 6) ** (1 / 6)

    rim_r = [R * square(k * math.tau / rings[-1]) * (1 + sum(amp * math.sin(f * k * math.tau / rings[-1] + ph) for f, ph, amp in waves)
                                                     + rnd.uniform(-0.03, 0.03)) for k in range(rings[-1])]

    def rim_at(a):
        n = len(rim_r)
        f = (a / math.tau) * n
        i = int(f) % n
        t = f - int(f)
        return rim_r[i] * (1 - t) + rim_r[(i + 1) % n] * t

    def height(x, y):
        a = math.atan2(y, x) % math.tau
        f = min(math.hypot(x, y) / rim_at(a), 1.0)
        return SINK + (H - SINK) * (1 - f * f) ** 0.7 + bump(x, y, bumps) * (1 - f ** 4)

    verts, uvs = [(0, 0, height(0, 0))], [bed_uv(0, 0, 2 * R * 1.15, 2 * R * 1.15)]
    ring_idx = [[0]]
    ring_ang = [[0.0]]
    fracs = [(k + 1) / len(rings) for k in range(len(rings))]
    for ri, (n, fr) in enumerate(zip(rings, fracs)):
        off = rnd.uniform(0, math.tau / n)
        idx, angs = [], []
        for k in range(n):
            a = (off + k * math.tau / n) % math.tau
            if ri == len(rings) - 1:
                a = k * math.tau / n
                r = rim_r[k]
            else:
                r = rim_at(a) * fr * rnd.uniform(0.92, 1.05)
            x, y = math.cos(a) * r, math.sin(a) * r
            z = SINK if ri == len(rings) - 1 else height(x, y)
            idx.append(len(verts))
            angs.append(a)
            verts.append((x, y, z))
            uvs.append(bed_uv(x, y, 2 * R * 1.15, 2 * R * 1.15))
        order = sorted(range(n), key=lambda k: angs[k])
        ring_idx.append([idx[k] for k in order])
        ring_ang.append([angs[k] for k in order])
    faces = []
    faces += [(0, ring_idx[1][k], ring_idx[1][(k + 1) % len(ring_idx[1])]) for k in range(len(ring_idx[1]))]
    for r in range(1, len(ring_idx) - 1):
        faces += stitch(ring_idx[r], ring_ang[r], ring_idx[r + 1], ring_ang[r + 1])
    b.add(verts, faces, uvs)
    return height


def stitch(ai, aa, bi, ba):
    """Triangles between an inner ring (ai, angles aa) and an outer ring (bi, angles ba), both
    sorted by angle, wound counter-clockwise seen from above."""
    na, nb = len(ai), len(bi)
    base = aa[0]
    ua = [(a - base) % math.tau for a in aa] + [math.tau]
    order = sorted(range(nb), key=lambda j: (ba[j] - base) % math.tau)
    ub = [(ba[j] - base) % math.tau for j in order]
    B = [bi[j] for j in order]
    A = ai + [ai[0]]
    B = B + [B[0]]
    ub = ub + [ub[0] + math.tau]
    faces, i, j = [], 0, 0
    while i < na or j < nb:
        if j >= nb or (i < na and ua[i + 1] <= ub[j + 1]):
            faces.append((A[i], B[j], A[i + 1]))
            i += 1
        else:
            faces.append((A[i], B[j], B[j + 1]))
            j += 1
    return faces


def drift_bed(b, rnd, L=7.0, W=3.0, H=0.8, nx=9, ny=5):
    """Long heap, high near +Y (the fence side) and sloping down toward -Y."""
    bumps = [(rnd.uniform(-2.8, 2.8), rnd.uniform(-0.6, 0.8), rnd.uniform(0.6, 1.0), rnd.uniform(0.05, 0.1)) for _ in range(4)]

    def prof_y(t):          # t 0 at -Y edge, 1 at +Y edge
        return math.sin(math.pi / 2 * t / 0.78) if t < 0.78 else math.cos(math.pi / 2 * (t - 0.78) / 0.22)

    def prof_x(s):          # s -1..1 along the length
        return max(1 - abs(s) ** 3, 0) ** 0.6

    def height(x, y):
        s = x / (L / 2)
        t = (y + W / 2) / W
        if abs(s) >= 1 or t <= 0 or t >= 1:
            return SINK
        return SINK + (H - SINK) * prof_x(s) * prof_y(t) + bump(x, y, bumps) * prof_x(s) * min(prof_y(t) * 2, 1)

    verts, uvs, grid = [], [], []
    for j in range(ny):
        row = []
        for i in range(nx):
            s = -1 + 2 * i / (nx - 1)
            t = j / (ny - 1)
            edge = i in (0, nx - 1) or j in (0, ny - 1)
            x = s * L / 2 * (1 + (rnd.uniform(-0.05, 0.06) if edge else 0))
            y = (t - 0.5) * W
            if edge:
                y += rnd.uniform(-0.18, 0.12) if j == 0 else (rnd.uniform(0, 0.08) if j == ny - 1 else 0)
                if i in (0, nx - 1):
                    x += math.copysign(rnd.uniform(-0.3, 0.2), s)
            z = SINK if edge else height(x, y)
            row.append(len(verts))
            verts.append((x, y, z))
            uvs.append(bed_uv(x, y, L * 1.1, W * 1.25))
        grid.append(row)
    faces = []
    for j in range(ny - 1):
        for i in range(nx - 1):
            a, bb, c, d = grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]
            if (i + j) % 2 == 0:
                faces += [(a, bb, c), (a, c, d)]
            else:
                faces += [(a, bb, d), (bb, c, d)]
    b.add(verts, faces, uvs)
    return height


# ------------------------------------------------------------------ items on the bed

def surface(b, x, y):
    """Top surface (point, normal) at x, y: the highest bed or item triangle, else the ground."""
    tree = b.bvh()
    if tree:
        hit = tree.ray_cast(Vector((x, y, 5)), Vector((0, 0, -1)))
        if hit[0] is not None:
            n = hit[1] if hit[1].z > 0 else -hit[1]
            return hit[0], n
    return Vector((x, y, 0)), Vector((0, 0, 1))


def frame(normal, yaw, tilt=(0.0, 0.0)):
    """Rotation: yaw about Z, small extra tilt, then lean onto the surface normal."""
    lean = Vector((0, 0, 1)).rotation_difference(normal).to_matrix()
    t = Matrix.Rotation(tilt[0], 3, "X") @ Matrix.Rotation(tilt[1], 3, "Y")
    return lean @ t @ Matrix.Rotation(yaw, 3, "Z")


def place(b, local, faces, uvs, x, y, yaw, lift=0.012, tilt=(0.0, 0.0), sink=0.0):
    p, n = surface(b, x, y)
    m = frame(n, yaw, tilt)
    origin = p + n * (lift - sink)
    b.add([origin + m @ Vector(v) for v in local], faces, uvs)


def leaf(b, cell, shape, x, y, size, yaw, rnd, tilt=(0.0, 0.0), sink=0.0):
    outline = ccw(SHAPES[shape])
    curl = rnd.uniform(0.12, 0.28)
    bend = rnd.uniform(-0.05, 0.12)
    cx, cy = 0.0, 0.04
    pts = [(cx, cy)] + outline
    local = [(px * size, py * size, size * (curl * (px * 2) ** 2 * 0.5 + bend * (py * 2) ** 2 * 0.5)) for px, py in pts]
    uvs = [cell_uv(cell, px, py) for px, py in pts]
    n = len(outline)
    faces = [(0, 1 + k, 1 + (k + 1) % n) for k in range(n)]
    place(b, local, faces, uvs, x, y, yaw, tilt=tilt, sink=sink)


def sheet(b, cell, x, y, sx, sy, yaw, rnd, crumple=0.08, n=3):
    """A crumpled square sheet (paper scraps and wrappers), n x n vertices."""
    local, uvs = [], []
    for j in range(n):
        for i in range(n):
            u, v = i / (n - 1) - 0.5, j / (n - 1) - 0.5
            edge = i in (0, n - 1) or j in (0, n - 1)
            z = rnd.uniform(0.3, 1.0) * crumple * (0.6 if edge else 1.4)
            local.append((u * sx + rnd.uniform(-0.05, 0.05), v * sy + rnd.uniform(-0.05, 0.05), z))
            uvs.append(cell_uv(cell, u, v))
    faces = []
    for j in range(n - 1):
        for i in range(n - 1):
            a, bb, c, d = j * n + i, j * n + i + 1, (j + 1) * n + i + 1, (j + 1) * n + i
            faces += [(a, bb, c), (a, c, d)]
    place(b, local, faces, uvs, x, y, yaw)


def strand(b, cell, x, y, length, width, yaw, rnd, segs=5):
    """A wavy seaweed ribbon draped over the bed, vertex by vertex."""
    pts, uvs = [], []
    wave = rnd.uniform(0.08, 0.18)
    phase = rnd.uniform(0, math.tau)
    c, s = math.cos(yaw), math.sin(yaw)
    for k in range(segs + 1):
        t = k / segs
        along = (t - 0.5) * length
        side = wave * math.sin(t * math.pi * 2 + phase)
        w = width * (0.55 + 0.45 * math.sin(math.pi * min(t * 1.2, 1)))
        for e in (-1, 1):
            lx, ly = side + e * w / 2, along
            wx, wy = x + lx * c - ly * s, y + lx * s + ly * c
            p, _ = surface(b, wx, wy)
            pts.append((wx, wy, p.z + 0.016 + 0.01 * (1 + math.sin(t * 11))))
            uvs.append(cell_uv(cell, e * 0.5, t - 0.5))
    faces = []
    for k in range(segs):
        a, bb, cc, d = 2 * k, 2 * k + 1, 2 * k + 3, 2 * k + 2
        faces += [(a, bb, cc), (a, cc, d)]
    # keep the winding facing up
    fixed = []
    for f in faces:
        v0, v1, v2 = (Vector(pts[i]) for i in f)
        fixed.append(f if (v1 - v0).cross(v2 - v0).z > 0 else (f[0], f[2], f[1]))
    b.add(pts, fixed, uvs)


def shell(b, cell, x, y, size, yaw, rnd, ribs=7):
    """A shallow scalloped cone (a clam shell) lying on the bed."""
    local, uvs = [(0, 0.15 * size, 0.16 * size)], [cell_uv(cell, 0, 0.15)]
    for k in range(ribs):
        a = math.radians(-70 + 140 * k / (ribs - 1))
        r = size * (0.5 if k % 2 == 0 else 0.44)
        px, py = math.sin(a) * r, -math.cos(a) * r + 0.2 * size
        local.append((px, py, 0.02))
        uvs.append(cell_uv(cell, px / size * 0.9, py / size * 0.9))
    local.append((0, 0.3 * size, 0.03))
    uvs.append(cell_uv(cell, 0, 0.3))
    faces = [(0, 1 + k + 1, 1 + k) for k in range(ribs - 1)]
    faces.append((0, 1, ribs + 1))
    faces.append((0, ribs + 1, ribs))
    # make sure the faces point up
    out = []
    for f in faces:
        v0, v1, v2 = (Vector(local[i]) for i in f)
        out.append(f if (v1 - v0).cross(v2 - v0).z > 0 else (f[0], f[2], f[1]))
    place(b, local, out, uvs, x, y, yaw, lift=0.0)


def grass(b, cell, x, y, rnd, blades=3):
    """A tuft of blades, each a triangle with a back face so it shows from both sides."""
    for _ in range(blades):
        a = rnd.uniform(0, math.tau)
        h = rnd.uniform(0.28, 0.45)
        w = rnd.uniform(0.07, 0.1)
        lean = rnd.uniform(0.05, 0.18)
        c, s = math.cos(a), math.sin(a)
        bx, by = x + rnd.uniform(-0.12, 0.12), y + rnd.uniform(-0.12, 0.12)
        p, _ = surface(b, bx, by)
        base = p.z - 0.03
        v = [(bx - s * w, by + c * w, base), (bx + s * w, by - c * w, base),
             (bx + c * lean, by + s * lean, base + h)]
        uv = [cell_uv(cell, -0.4, -0.5), cell_uv(cell, 0.4, -0.5), cell_uv(cell, 0, 0.5)]
        b.add(v, [(0, 1, 2)], uv)
        b.add(v, [(0, 2, 1)], uv)          # separate back face


def snowball(b, cell, x, y, size, rnd):
    """A soft snow lump: a squashed, lumpy octahedron-ish dome (8 triangles)."""
    p, _ = surface(b, x, y)
    ring = []
    for k in range(6):
        a = k * math.tau / 6 + rnd.uniform(-0.2, 0.2)
        r = size * rnd.uniform(0.85, 1.1)
        ring.append((x + math.cos(a) * r, y + math.sin(a) * r, p.z - 0.05))
    top = (x + rnd.uniform(-0.1, 0.1), y + rnd.uniform(-0.1, 0.1), p.z + size * 0.45)
    verts = [top] + ring
    uvs = [cell_uv(cell, 0, 0)] + [cell_uv(cell, math.cos(k * math.tau / 6) * 0.45, math.sin(k * math.tau / 6) * 0.45) for k in range(6)]
    b.add(verts, [(0, 1 + k, 1 + (k + 1) % 6) for k in range(6)], uvs)


# ------------------------------------------------------------------ assets

def scatter_points(rnd, n, R, min_gap=0.55, spread=0.92):
    pts = []
    tries = 0
    while len(pts) < n and tries < 4000:
        tries += 1
        r = R * spread * math.sqrt(rnd.random())
        a = rnd.uniform(0, math.tau)
        x, y = math.cos(a) * r, math.sin(a) * r
        if all(math.hypot(x - px, y - py) > min_gap for px, py in pts):
            pts.append((x, y))
    # lay outer leaves first so the middle ones end up on top of the heap
    pts.sort(key=lambda p: -math.hypot(*p))
    return pts


def leaf_cells(cells):
    return [i for i, c in enumerate(cells) if c[0] == "leaf"]


def finish(name, zone, b, material=None):
    path, _ = atlas(zone)
    a = Asset(name, "prop")
    a.texture = path
    o = b.make(name)
    a.parts["Clump"] = {"obj": o, "parent": None, "joint": None, "glow": None,
                        "material": material, "collide": False, "plain": False}
    a.extra["atlas"] = f"PileAtlas_{zone}"
    return a


def leafy_clump(name, zone, seed, n_leaves, material=None, rings=(5, 10, 16)):
    def make():
        Asset(name, "prop")              # resets the scene before painting
        path, cells = atlas(zone)
        rnd = random.Random(seed)
        b = Builder()
        clump_bed(b, rnd, rings=rings)
        lc = leaf_cells(cells)
        for x, y in scatter_points(rnd, n_leaves, 2.95, 0.55):
            i = rnd.choice(lc)
            leaf(b, i, cells[i][1], x, y, rnd.uniform(0.95, 1.35), rnd.uniform(0, math.tau), rnd,
                 tilt=(rnd.uniform(-0.15, 0.15), rnd.uniform(-0.15, 0.15)))
        return finish(name, zone, b, material)
    return make


def park_clump(name, seed):
    def make():
        Asset(name, "prop")
        path, cells = atlas("Park")
        rnd = random.Random(seed)
        b = Builder()
        clump_bed(b, rnd)
        lc = leaf_cells(cells)
        gc = [i for i, c in enumerate(cells) if c[0] == "grass"]
        for x, y in scatter_points(rnd, 13, 2.95, 0.55):
            i = rnd.choice(lc)
            leaf(b, i, cells[i][1], x, y, rnd.uniform(0.9, 1.25), rnd.uniform(0, math.tau), rnd,
                 tilt=(rnd.uniform(-0.15, 0.15), rnd.uniform(-0.15, 0.15)))
        for x, y in scatter_points(rnd, 4, 2.6, 1.0, 0.95):
            grass(b, rnd.choice(gc), x, y, rnd)
        return finish(name, "Park", b)
    return make


def seaweed_clump(name, seed):
    def make():
        Asset(name, "prop")
        path, cells = atlas("Seaweed")
        rnd = random.Random(seed)
        b = Builder()
        clump_bed(b, rnd, H=0.2)
        sc = [i for i, c in enumerate(cells) if c[0] == "strand"]
        hc = [i for i, c in enumerate(cells) if c[0] == "shell"]
        lc = leaf_cells(cells)
        for x, y in scatter_points(rnd, 9, 2.6, 0.6):
            strand(b, rnd.choice(sc), x, y, rnd.uniform(1.4, 2.1), rnd.uniform(0.45, 0.65), rnd.uniform(0, math.tau), rnd)
        for x, y in scatter_points(rnd, 2, 2.4, 1.0):
            i = rnd.choice(lc)
            leaf(b, i, cells[i][1], x, y, rnd.uniform(0.8, 1.1), rnd.uniform(0, math.tau), rnd)
        for x, y in scatter_points(rnd, 3, 2.2, 1.2):
            shell(b, rnd.choice(hc), x, y, rnd.uniform(0.35, 0.5), rnd.uniform(0, math.tau), rnd)
        return finish(name, "Seaweed", b)
    return make


def paper_clump(name, seed):
    def make():
        Asset(name, "prop")
        path, cells = atlas("Paper")
        rnd = random.Random(seed)
        b = Builder()
        clump_bed(b, rnd, H=0.2)
        pc = [i for i, c in enumerate(cells) if c[0] == "paper"]
        wc = [i for i, c in enumerate(cells) if c[0] == "wrapper"]
        lc = leaf_cells(cells)
        pts = scatter_points(rnd, 14, 2.95, 0.6)
        for k, (x, y) in enumerate(pts):
            yaw = rnd.uniform(0, math.tau)
            if k % 3 == 0:
                sheet(b, rnd.choice(wc), x, y, rnd.uniform(0.45, 0.7), rnd.uniform(0.3, 0.45), yaw, rnd, 0.06)
            elif k % 3 == 1:
                sheet(b, rnd.choice(pc), x, y, rnd.uniform(0.8, 1.2), rnd.uniform(0.7, 1.0), yaw, rnd, 0.12)
            else:
                i = rnd.choice(lc)
                leaf(b, i, cells[i][1], x, y, rnd.uniform(0.9, 1.2), yaw, rnd)
        return finish(name, "Paper", b)
    return make


def snow_clump(name, seed):
    def make():
        Asset(name, "prop")
        path, cells = atlas("Snow")
        rnd = random.Random(seed)
        b = Builder()
        clump_bed(b, rnd, H=0.36, rings=(6, 12, 18, 24), lumps=6, extra=0.06)
        lc = leaf_cells(cells)
        sc = [i for i, c in enumerate(cells) if c[0] == "snow"]
        for x, y in scatter_points(rnd, 3, 2.2, 0.9):
            snowball(b, rnd.choice(sc), x, y, rnd.uniform(0.45, 0.7), rnd)
        # leaves poke out of the snow: steeply tilted and pushed partly in
        for k, (x, y) in enumerate(scatter_points(rnd, 7, 2.5, 0.8)):
            i = rnd.choice(lc)
            tilt = (rnd.uniform(0.3, 0.5) * rnd.choice((-1, 1)), rnd.uniform(-0.2, 0.2)) if k % 2 else (0.1, 0.0)
            leaf(b, i, cells[i][1], x, y, rnd.uniform(1.0, 1.3), rnd.uniform(0, math.tau), rnd, tilt=tilt, sink=0.04)
        return finish(name, "Snow", b)
    return make


def drift(name, zone, seed, n_leaves=14, snow=False):
    def make():
        Asset(name, "prop")
        path, cells = atlas(zone)
        rnd = random.Random(seed)
        b = Builder()
        drift_bed(b, rnd, H=0.8)
        lc = leaf_cells(cells)
        pts = []
        tries = 0
        while len(pts) < n_leaves and tries < 4000:
            tries += 1
            x, y = rnd.uniform(-3.1, 3.1), rnd.uniform(-1.3, 1.1)
            if all(math.hypot(x - px, y - py) > 0.6 for px, py in pts):
                pts.append((x, y))
        pts.sort(key=lambda p: abs(p[0]))
        pts.reverse()
        for x, y in pts:
            i = rnd.choice(lc)
            if snow:
                leaf(b, i, cells[i][1], x, y, rnd.uniform(1.0, 1.3), rnd.uniform(0, math.tau), rnd,
                     tilt=(rnd.uniform(0.3, 0.5) * rnd.choice((-1, 1)), 0), sink=0.04)
            else:
                leaf(b, i, cells[i][1], x, y, rnd.uniform(0.95, 1.35), rnd.uniform(0, math.tau), rnd,
                     tilt=(rnd.uniform(-0.15, 0.15), rnd.uniform(-0.15, 0.15)))
        if zone == "Park":
            gc = [i for i, c in enumerate(cells) if c[0] == "grass"]
            for x in (-2.6, 0.4, 2.8):
                grass(b, rnd.choice(gc), x, rnd.uniform(-1.4, -1.0), rnd)
        return finish(name, zone, b)
    return make


ALL = {
    "Clump_Autumn1": leafy_clump("Clump_Autumn1", "Autumn", 11, 15),
    "Clump_Autumn2": leafy_clump("Clump_Autumn2", "Autumn", 23, 16),
    "Clump_Autumn3": leafy_clump("Clump_Autumn3", "Autumn", 37, 14),
    "Clump_Autumn4": leafy_clump("Clump_Autumn4", "Autumn", 41, 15),
    "Clump_Park1": park_clump("Clump_Park1", 51),
    "Clump_Park2": park_clump("Clump_Park2", 63),
    "Clump_Park3": park_clump("Clump_Park3", 77),
    "Clump_Seaweed1": seaweed_clump("Clump_Seaweed1", 81),
    "Clump_Seaweed2": seaweed_clump("Clump_Seaweed2", 93),
    "Clump_Paper1": paper_clump("Clump_Paper1", 101),
    "Clump_Paper2": paper_clump("Clump_Paper2", 117),
    "Clump_Snow1": snow_clump("Clump_Snow1", 121),
    "Clump_Snow2": snow_clump("Clump_Snow2", 133),
    "Clump_Gold1": leafy_clump("Clump_Gold1", "Gold", 141, 15, material="Foil"),
    "Drift_Autumn1": drift("Drift_Autumn1", "Autumn", 151, 13),
    "Drift_Autumn2": drift("Drift_Autumn2", "Autumn", 163, 13),
    "Drift_Park1": drift("Drift_Park1", "Park", 171, 11),
    "Drift_Snow1": drift("Drift_Snow1", "Snow", 181, 7, snow=True),
}
