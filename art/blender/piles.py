"""Leaf piles (Clump_*) and long heaps (Drift_*) for the mid distance (about 26-130 studs).

Dev wants piles made of the leaves themselves, matching the separate Leaf_* meshes that fly
around: each pile is 25-40 flat, bright, single-colour leaves (the same outlines as
Leaf_Maple/Oak/Birch, or seaweed blades, paper scraps and snow lumps per zone) heaped
into a mound, overlapping, with a little grass showing between them at the edges. A small
solid-colour core under the middle keeps the mound from looking hollow.
Colours are the same palette LeafMeshes tints the separate leaves with. Every model of a zone
uses one atlas of solid 64 px swatches (art/out/ui/PileAtlas_<Zone>.png, also uploaded as
an image), so the game can share one TextureID per zone. No painted shading.
One part "Clump", collide off, pivot at the bottom centre, Blender +Z up (= Roblox +Y).
Clumps are rounded squares (about 5.8 across, about 7.3 corner to corner) that close into a
carpet on a 5-stud grid with 90-degree turns. Drifts are about 7 x 3 x 0.8, high side at +Y
(Roblox +Z, against the fence) sloping down toward -Y. Each stays under about 400 triangles.
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
SWATCH, GRID = 64, 4                 # 4 x 4 swatches of 64 px -> 256 px atlas


def polar(points, sx=1.0, sy=1.0):
    out = []
    for a, r in points:
        t = math.radians(a)
        out.append((math.sin(t) * r * sx, -math.cos(t) * r * sy))
    return out


def ccw(outline):
    a = sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(outline, outline[1:] + outline[:1]))
    return outline if a > 0 else list(reversed(outline))


# Outlines like the Leaf_* meshes in litter.py, a little simplified (about 1 stud long).
MAPLE = polar([(0, 0.55), (28, 0.28), (52, 0.48), (82, 0.28), (112, 0.42), (148, 0.22), (180, 0.36),
               (212, 0.22), (248, 0.42), (278, 0.28), (308, 0.48), (332, 0.28)])
OAK = polar([(k * 30, 0.4 + (0.08 if k % 2 == 0 else -0.06) + 0.08 * math.cos(math.radians(k * 30))) for k in range(12)], 0.75, 1.1)
BIRCH = polar([(0, 0.55), (35, 0.36), (80, 0.3), (130, 0.31), (180, 0.38), (230, 0.31), (280, 0.3), (325, 0.36)], 0.8, 1.0)
rnd_p = random.Random(7)
PAPER = polar([(a, 0.5 + rnd_p.uniform(-0.1, 0.06)) for a in range(20, 360, 45)])
SHAPES = {"maple": ccw(MAPLE), "oak": ccw(OAK), "birch": ccw(BIRCH), "paper": ccw(PAPER)}

# Zone palettes: the LeafMeshes colours (keep in step with src/client/LeafMeshes.luau),
# plus the colour of the core under the middle (last entry).
ZONES = {
    "Autumn": dict(colors=[(236, 118, 38), (214, 66, 40), (244, 186, 52), (170, 98, 44), (228, 148, 40), (196, 52, 36)],
                   core=(170, 98, 44), kinds=["maple", "maple", "oak", "birch"]),
    "Park": dict(colors=[(112, 176, 62), (150, 196, 70), (196, 204, 70), (232, 182, 52), (92, 150, 58)],
                 core=(92, 150, 58), kinds=["oak", "birch", "maple"]),
    "Seaweed": dict(colors=[(58, 140, 82), (40, 112, 92), (104, 162, 62), (132, 120, 52)],
                    core=(40, 112, 92), kinds=["seaweed"]),
    "Paper": dict(colors=[(246, 246, 240), (232, 226, 210), (212, 226, 242), (244, 232, 160)],
                  core=(232, 226, 210), kinds=["paper", "paper", "maple"]),
    "Snow": dict(colors=[(246, 250, 255), (226, 236, 250), (236, 244, 255)],
                 core=(236, 244, 255), kinds=["snow"]),
    "Gold": dict(colors=[(255, 206, 60), (255, 218, 96), (240, 186, 44)],
                 core=(240, 186, 44), kinds=["maple", "maple", "oak", "birch"]),
}


def swatch_uv(i):
    c, r = i % GRID, i // GRID
    return (c + 0.5) / GRID, 1 - (r + 0.5) / GRID


def palette(zone):
    z = ZONES[zone]
    cols = list(z["colors"])
    if z["core"] not in cols:
        cols.append(z["core"])
    return cols


def atlas(zone):
    """Write the zone's solid-swatch atlas and return its path."""
    cols = palette(zone)
    size = SWATCH * GRID
    img = np.zeros((size, size, 3))
    for i, (r, g, b) in enumerate(cols):
        c, row = i % GRID, i // GRID
        img[row * SWATCH:(row + 1) * SWATCH, c * SWATCH:(c + 1) * SWATCH] = (r / 255, g / 255, b / 255)
    os.makedirs(ATLAS_DIR, exist_ok=True)
    path = os.path.abspath(os.path.join(ATLAS_DIR, f"PileAtlas_{zone}.png"))
    bimg = bpy.data.images.new(f"PileAtlas_{zone}", size, size, alpha=False)
    px = np.ones((size, size, 4))
    px[..., :3] = img[::-1]
    bimg.pixels = px.ravel().tolist()
    bimg.filepath_raw = path
    bimg.file_format = "PNG"
    bimg.save()
    bpy.data.images.remove(bimg)
    return path


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



# ------------------------------------------------------------------ mound shapes

def square(a, p=6):
    return 1 / (abs(math.cos(a)) ** p + abs(math.sin(a)) ** p) ** (1 / p)


def clump_shape(rnd, R=2.9, H=0.3):
    waves = [(f, rnd.uniform(0, math.tau), amp) for f, amp in ((3, 0.04), (5, 0.04), (7, 0.03))]

    def rim(a):
        return R * square(a) * (1 + sum(amp * math.sin(f * a + ph) for f, ph, amp in waves))

    def height(x, y):
        f = min(math.hypot(x, y) / rim(math.atan2(y, x)), 1.0)
        return H * (1 - f * f) ** 0.8

    return rim, height


def drift_shape(L=7.0, W=3.0, H=0.8):
    def prof_y(t):
        return math.sin(math.pi / 2 * t / 0.78) if t < 0.78 else math.cos(math.pi / 2 * (t - 0.78) / 0.22)

    def height(x, y):
        s, t = x / (L / 2), (y + W / 2) / W
        if abs(s) >= 1 or t <= 0 or t >= 1:
            return 0.0
        return H * max(1 - abs(s) ** 3, 0) ** 0.6 * prof_y(t)

    return height


def core_clump(b, rnd, rim, height, uv, scale=0.42, sink=0.06):
    """Solid low dome under the middle of the pile so it never looks hollow."""
    verts, uvs = [(0, 0, height(0, 0) - sink)], [uv]
    rings = []
    for fr, n in ((0.55, 6), (1.0, 10)):
        ring = []
        for k in range(n):
            a = k * math.tau / n
            r = rim(a) * scale * fr
            x, y = math.cos(a) * r, math.sin(a) * r
            z = height(x, y) - sink if fr < 1 else -0.02
            ring.append(len(verts))
            verts.append((x, y, z))
            uvs.append(uv)
        rings.append((ring, [k * math.tau / n for k in range(n)]))
    faces = [(0, rings[0][0][k], rings[0][0][(k + 1) % 6]) for k in range(6)]
    faces += stitch(rings[0][0], rings[0][1], rings[1][0], rings[1][1])
    b.add(verts, faces, uvs)


def core_drift(b, height, uv, L=5.6, W=2.2, sink=0.12, nx=5, ny=4):
    verts, uvs, grid = [], [], []
    for j in range(ny):
        row = []
        for i in range(nx):
            x = (-0.5 + i / (nx - 1)) * L * 0.8
            y = (-0.5 + j / (ny - 1)) * W * 0.75 + 0.1
            edge = i in (0, nx - 1) or j in (0, ny - 1)
            z = -0.02 if edge else max(height(x, y) - sink, 0.0)
            row.append(len(verts))
            verts.append((x, y, z))
            uvs.append(uv)
        grid.append(row)
    faces = []
    for j in range(ny - 1):
        for i in range(nx - 1):
            a, bb, c, d = grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]
            faces += [(a, bb, c), (a, c, d)]
    b.add(verts, faces, uvs)


# ------------------------------------------------------------------ pieces

def rest_on(b, height, x, y):
    """Where a piece lands at x, y: on top of earlier pieces or the mound, whichever is
    higher, with the normal of that surface."""
    ground = Vector((x, y, height(x, y)))
    e = 0.15
    n = Vector((height(x - e, y) - height(x + e, y), height(x, y - e) - height(x, y + e), 2 * e)).normalized()
    tree = b.bvh()
    if tree:
        hit = tree.ray_cast(Vector((x, y, 6)), Vector((0, 0, -1)))
        if hit[0] is not None and hit[0].z > ground.z:
            hn = hit[1] if hit[1].z > 0 else -hit[1]
            return hit[0], (hn + n).normalized()
    return ground, n


def frame(normal, yaw, tilt=(0.0, 0.0)):
    """Rotation: yaw about Z, small extra tilt, then lean onto the surface normal."""
    lean = Vector((0, 0, 1)).rotation_difference(normal).to_matrix()
    t = Matrix.Rotation(tilt[0], 3, "X") @ Matrix.Rotation(tilt[1], 3, "Y")
    return lean @ t @ Matrix.Rotation(yaw, 3, "Z")



def put(b, height, local, faces, uv, x, y, yaw, lift=0.015, tilt=(0.0, 0.0)):
    p, n = rest_on(b, height, x, y)
    m = frame(n, yaw, tilt)
    o = p + n * lift
    b.add([o + m @ Vector(v) for v in local], faces, [uv] * len(local))


def leaf(b, height, uv, shape, x, y, size, yaw, rnd, tilt=(0.0, 0.0)):
    outline = SHAPES[shape]
    curl, bend = rnd.uniform(0.1, 0.22), rnd.uniform(-0.04, 0.1)
    pts = [(0.0, 0.04)] + outline
    local = [(px * size, py * size, size * (curl * (px * 2) ** 2 + bend * (py * 2) ** 2) * 0.5) for px, py in pts]
    n = len(outline)
    put(b, height, local, [(0, 1 + k, 1 + (k + 1) % n) for k in range(n)], uv, x, y, yaw, tilt=tilt)


def blade(b, height, uv, x, y, length, width, yaw, rnd, segs=3):
    """Seaweed blade like Leaf_Seaweed: a wavy strip, draped on the pile."""
    local = []
    phase = rnd.uniform(0, math.tau)
    for k in range(segs + 1):
        t = k / segs
        along = (t - 0.5) * length
        sway = 0.12 * math.sin(t * math.pi * 2 + phase)
        w = width * (0.55 + 0.45 * math.sin(math.pi * min(t * 1.2, 1)))
        local += [(sway - w / 2, along, 0.03 * math.sin(t * 5)), (sway + w / 2, along, 0.03 * math.sin(t * 5))]
    faces = []
    for k in range(segs):
        a, bb, c, d = 2 * k, 2 * k + 1, 2 * k + 3, 2 * k + 2
        faces += [(a, bb, c), (a, c, d)]
    put(b, height, local, faces, uv, x, y, yaw)


def lump(b, height, uv, x, y, size, rnd):
    """Snow lump like Leaf_Snow: a squashed dome of 7 triangles."""
    local = [(rnd.uniform(-0.08, 0.08) * size, rnd.uniform(-0.08, 0.08) * size, size * 0.4)]
    for k in range(7):
        a = k * math.tau / 7 + rnd.uniform(-0.15, 0.15)
        r = size * rnd.uniform(0.42, 0.55)
        local.append((math.cos(a) * r, math.sin(a) * r * 0.85, -0.04))
    faces = [(0, 1 + k, 1 + (k + 1) % 7) for k in range(7)]
    put(b, height, local, faces, uv, x, y, rnd.uniform(0, math.tau), lift=0.0)


def piece(b, height, zone, rnd, x, y, big=1.0):
    z = ZONES[zone]
    kind = rnd.choice(z["kinds"])
    uv = swatch_uv(rnd.randrange(len(z["colors"])))
    yaw = rnd.uniform(0, math.tau)
    tilt = (rnd.uniform(-0.18, 0.18), rnd.uniform(-0.18, 0.18))
    if kind == "seaweed":
        blade(b, height, uv, x, y, rnd.uniform(1.1, 1.5) * big, rnd.uniform(0.26, 0.36), yaw, rnd)
    elif kind == "snow":
        lump(b, height, uv, x, y, rnd.uniform(0.9, 1.25) * big, rnd)
    else:
        leaf(b, height, uv, kind, x, y, rnd.uniform(1.05, 1.4) * big, yaw, rnd, tilt)


def scatter(rnd, n, rim, gap=0.5, spread=0.98):
    """Points over the footprint, denser toward the middle, outer ones first so the middle
    ones end up on top."""
    pts, tries = [], 0
    while len(pts) < n and tries < 6000:
        tries += 1
        a = rnd.uniform(0, math.tau)
        f = rnd.random() ** 0.8
        r = rim(a) * spread * f
        x, y = math.cos(a) * r, math.sin(a) * r
        g = gap * (0.45 + 0.75 * f)              # tighter in the middle so leaves heap up there
        if all(math.hypot(x - px, y - py) > g for px, py in pts):
            pts.append((x, y))
    pts.sort(key=lambda p: -math.hypot(*p))
    return pts


# ------------------------------------------------------------------ assets

def finish(name, zone, b, material=None):
    path = atlas(zone)
    a = Asset(name, "prop")
    a.texture = path
    o = b.make(name)
    a.parts["Clump"] = {"obj": o, "parent": None, "joint": None, "glow": None,
                        "material": material, "collide": False, "plain": False}
    a.extra["atlas"] = f"PileAtlas_{zone}"
    return a


def core_uv(zone):
    return swatch_uv(palette(zone).index(ZONES[zone]["core"]))


BUDGET = 400


def clump(name, zone, seed, count, material=None):
    def make():
        Asset(name, "prop")
        rnd = random.Random(seed)
        rim, height = clump_shape(rnd, H=0.24 if zone == "Seaweed" else 0.3)
        b = Builder()
        core_clump(b, rnd, rim, height, core_uv(zone))
        gap = 0.7 if zone == "Snow" else 0.6
        for x, y in scatter(rnd, count, rim, gap):
            before = (len(b.verts), len(b.faces), len(b.uvs))
            piece(b, height, zone, rnd, x, y)
            if b.tris() > BUDGET:            # stay under budget: drop the piece and stop
                b.verts, b.faces, b.uvs = b.verts[:before[0]], b.faces[:before[1]], b.uvs[:before[2]]
                break
        return finish(name, zone, b, material)
    return make


def drift(name, zone, seed, count):
    def make():
        Asset(name, "prop")
        rnd = random.Random(seed)
        height = drift_shape()
        b = Builder()
        core_drift(b, height, core_uv(zone))
        pts, tries = [], 0
        while len(pts) < count and tries < 6000:
            tries += 1
            x, y = rnd.uniform(-3.3, 3.3), rnd.uniform(-1.45, 1.35)
            if height(x, y) <= 0.02 and rnd.random() < 0.6:
                continue
            if all(math.hypot(x - px, y - py) > 0.5 for px, py in pts):
                pts.append((x, y))
        pts.sort(key=lambda p: height(*p))      # low ones first, the ridge ends on top
        for x, y in pts:
            before = (len(b.verts), len(b.faces), len(b.uvs))
            piece(b, height, zone, rnd, x, y)
            if b.tris() > BUDGET:
                b.verts, b.faces, b.uvs = b.verts[:before[0]], b.faces[:before[1]], b.uvs[:before[2]]
                break
        return finish(name, zone, b)
    return make


ALL = {
    "Clump_Autumn1": clump("Clump_Autumn1", "Autumn", 11, 34),
    "Clump_Autumn2": clump("Clump_Autumn2", "Autumn", 23, 36),
    "Clump_Autumn3": clump("Clump_Autumn3", "Autumn", 37, 30),
    "Clump_Autumn4": clump("Clump_Autumn4", "Autumn", 41, 33),
    "Clump_Park1": clump("Clump_Park1", "Park", 51, 33),
    "Clump_Park2": clump("Clump_Park2", "Park", 63, 30),
    "Clump_Park3": clump("Clump_Park3", "Park", 77, 35),
    "Clump_Seaweed1": clump("Clump_Seaweed1", "Seaweed", 81, 40),
    "Clump_Seaweed2": clump("Clump_Seaweed2", "Seaweed", 93, 36),
    "Clump_Paper1": clump("Clump_Paper1", "Paper", 101, 36),
    "Clump_Paper2": clump("Clump_Paper2", "Paper", 117, 32),
    "Clump_Snow1": clump("Clump_Snow1", "Snow", 121, 34),
    "Clump_Snow2": clump("Clump_Snow2", "Snow", 133, 30),
    "Clump_Gold1": clump("Clump_Gold1", "Gold", 141, 34, material="Foil"),
    "Drift_Autumn1": drift("Drift_Autumn1", "Autumn", 151, 36),
    "Drift_Autumn2": drift("Drift_Autumn2", "Autumn", 163, 34),
    "Drift_Park1": drift("Drift_Park1", "Park", 171, 34),
    "Drift_Snow1": drift("Drift_Snow1", "Snow", 181, 36),
    "Drift_Seaweed1": drift("Drift_Seaweed1", "Seaweed", 191, 38),
    "Drift_Paper1": drift("Drift_Paper1", "Paper", 201, 34),
}
