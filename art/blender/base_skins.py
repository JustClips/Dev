"""Base skins: 5 themed versions of a full player base (deck, walls, corner pillars, arch,
egg pad, incubators, lamps, pet house, trader stall, park fence and decor).

Every piece is built at its own origin by a small function that returns (solid, glow)
piece lists, then placed with the same layout as World.Base in the game, so each piece
can later be exported as its own GLB prop (Skin_<Theme>_<Piece>).

Layout (Blender coords, 1 m = 1 stud): the base is 92 x 88, the entrance is at -Y
(Roblox -Z), Roblox local X is Blender -X.

Preview in Blender:  exec this file, then  build("autumn"); render("autumn", "out.png")
"""
import math
import os
import random
import sys

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import lib  # noqa: E402

lib.GRID = 16  # preview dioramas hold many colours; single exported props stay under 64
from lib import Asset, use, sphere, ico, box, cyl, cone, torus, join, hex_rgb  # noqa: E402


# Lighter primitives for whole-base skins (8 bases can be on screen at once): no bevel on
# small boxes (it can't be seen from the camera) and fewer sphere segments.
def box(color, loc=(0, 0, 0), size=(1, 1, 1), rot=(0, 0, 0), bevel=0.0, smooth=False):
    if bevel and min(size) < 0.8:
        bevel = 0.0
    return lib.box(color, loc=loc, size=size, rot=rot, bevel=bevel, smooth=smooth)


def sphere(color, loc=(0, 0, 0), scale=1, rot=(0, 0, 0), seg=12, rings=8, smooth=True):
    return lib.sphere(color, loc=loc, scale=scale, rot=rot, seg=min(seg, 12), rings=min(rings, 8), smooth=smooth)


def cyl(color, loc=(0, 0, 0), r=1, h=1, rot=(0, 0, 0), verts=16, r2=None, smooth=True, cap=True):
    return lib.cyl(color, loc=loc, r=r, h=h, rot=rot, verts=min(verts, 16 if r > 2 else 10), r2=r2, smooth=smooth, cap=cap)


def cone(color, loc=(0, 0, 0), r=1, h=1, rot=(0, 0, 0), verts=16, smooth=True):
    return cyl(color, loc, r, h, rot, verts, r2=0.0, smooth=smooth)


def torus(color, loc=(0, 0, 0), R=1, r=0.25, rot=(0, 0, 0), seg=24, mseg=8):
    return lib.torus(color, loc=loc, R=R, r=r, rot=rot, seg=min(seg, 24), mseg=min(mseg, 6))

W, D = 92, 88
PARK = (-42, -14, 42, 42)  # xmin, ymin, xmax, ymax
GATE = 12
SOLID, GLOW = [], []


def shade(h, k):
    r, g, b = hex_rgb(h)
    if k >= 0:
        r, g, b = (c + (1 - c) * k for c in (r, g, b))
    else:
        r, g, b = (c * (1 + k) for c in (r, g, b))
    return "%02X%02X%02X" % tuple(max(0, min(255, round(c * 255))) for c in (r, g, b))


def put(fn, x=0.0, y=0.0, yaw=0.0, s=1.0, **kw):
    """Build a piece at the origin and move it into place."""
    solid, glow = fn(**kw)
    for lst, out in ((solid, SOLID), (glow, GLOW)):
        if lst:
            o = join(lst, fn.__name__)
            o["cat"] = category(fn.__name__)
            o.scale = (s, s, s)
            o.rotation_euler = (0, 0, math.radians(yaw))
            o.location = (x, y, 0)
            out.append(o)


# Exported part per piece kind. Skins are visual only: the classic base stays in place,
# invisible, and keeps every collision (floor, walls, fences, arch, habitat, park props).
CATS = {"platform": ("Body", False), "wall": ("Walls", False), "pillar": ("Pillars", False),
        "fence": ("Fences", False), "arch": ("Arch", False), "hatchery": ("Hatchery", False),
        "incubator": ("Incubators", False), "lamp": ("Lamps", False), "house": ("House", False),
        "stall": ("Stall", False),
        # Castle Keep's front wall either side of the gatehouse really blocks (the classic
        # base has no front wall), so each side is its own simple colliding part
        "frontl": ("FrontWallL", True), "frontr": ("FrontWallR", True)}


def category(fn_name):
    key = fn_name.split("_")[-1]
    return CATS[key][0] if key in CATS else "Decor"


def line(fn, a, b, step=8.0, **kw):
    """Segments of fn(L=...) along a line (each segment is built along X)."""
    a, b = Vector(a), Vector(b)
    d = b - a
    n = max(1, round(d.length / step))
    ang = math.degrees(math.atan2(d.y, d.x))
    for i in range(n):
        m = a + d * ((i + 0.5) / n)
        put(fn, m.x, m.y, ang, L=d.length / n, **kw)


def oval(col, rx, ry, z, h):
    o = cyl(col, loc=(0, 0, z), r=1, h=h, verts=32)
    return lib.deform(o, lambda v: Vector((v.x * rx, v.y * ry, v.z)))


def ring(n, r, start=0.0):
    return [(math.cos(start + i * 2 * math.pi / n) * r, math.sin(start + i * 2 * math.pi / n) * r) for i in range(n)]


def bands(cols, loc, r, h, n, r2=None, verts=16):
    """Stacked cylinder bands in alternating colours (candy canes, totems)."""
    x, y, z0 = loc
    out = []
    for i in range(n):
        rr = r if r2 is None else r + (r2 - r) * (i + 0.5) / n
        out.append(cyl(cols[i % len(cols)], loc=(x, y, z0 + (i + 0.5) * h / n), r=rr, h=h / n + 0.01, verts=verts))
    return out


def gable(wall, roof, roof2, W_, D_, H, ridge, z0=0.0, over=1.0, thick=0.5, rows=5):
    """Simple house box with a gable roof (ridge along Y); returns pieces."""
    p = [box(wall, loc=(0, 0, z0 + H / 2), size=(W_, D_, H))]
    # gable triangles
    for yy in (-D_ / 2, D_ / 2):
        for k in range(rows):
            t0, t1 = k / rows, (k + 1) / rows
            hw = (W_ / 2) * (1 - (t0 + t1) / 2)
            p.append(box(wall, loc=(0, yy, z0 + H + ridge * (t0 + t1) / 2), size=(hw * 2, 0.4, ridge / rows + 0.02)))
    half = W_ / 2 + over
    slope = math.degrees(math.atan2(ridge, W_ / 2))
    length = math.hypot(half, ridge * half / (W_ / 2))
    for sgn in (-1, 1):
        for k in range(rows):
            t = (k + 0.5) / rows
            cx = sgn * half * (1 - t)
            cz = z0 + H + ridge * (1 - abs(cx) / (W_ / 2)) + thick * 0.6
            p.append(box(roof if k % 2 == 0 else roof2, loc=(cx, 0, cz), size=(length / rows + 0.3, D_ + over * 1.6, thick),
                         rot=(0, sgn * slope, 0), bevel=0.08))
    return p


def leaf_pile(cols, r=1.2, n=7, seed=1):
    rnd = random.Random(seed)
    out = []
    for i in range(n):
        a = rnd.uniform(0, 2 * math.pi)
        d = rnd.uniform(0, r * 0.6)
        out.append(ico(rnd.choice(cols), loc=(math.cos(a) * d, math.sin(a) * d, 0.25 + rnd.uniform(0, 0.25)),
                       scale=(r * 0.45, r * 0.35, 0.3), rot=(0, 0, rnd.uniform(0, 180)), sub=1))
    return out


def blob_tree(trunk, cols, h=7, r=3.0, seed=1, n=5):
    rnd = random.Random(seed)
    p = [cyl(trunk, loc=(0, 0, h / 2), r=0.55, r2=0.4, h=h, verts=10)]
    p.append(ico(cols[0], loc=(0, 0, h + 0.3), scale=(r, r, r * 0.85), sub=2))
    for i in range(n):
        a = i * 2 * math.pi / n + rnd.uniform(-0.3, 0.3)
        p.append(ico(cols[(i + 1) % len(cols)], loc=(math.cos(a) * r * 0.75, math.sin(a) * r * 0.75, h - 0.4 + rnd.uniform(-0.4, 0.8)),
                     scale=r * rnd.uniform(0.55, 0.7), sub=2))
    return p


def pumpkin(col="F28C28", r=1.0, loc=(0, 0, 0)):
    x, y, z = loc
    p = []
    for k in range(5):
        a = k * math.pi / 5
        p.append(sphere(col if k % 2 else shade(col, -0.08), loc=(x, y, z + r * 0.7), scale=(r, r * 0.55, r * 0.7), rot=(0, 0, math.degrees(a)), seg=16, rings=10))
    p.append(cyl("4E7A2E", loc=(x, y, z + r * 1.45), r=r * 0.12, h=r * 0.4, verts=6, rot=(10, 0, 0)))
    return p


# =============================================================================== THEMES
T = {}


def theme(name):
    def deco(fn):
        T[name] = fn
        return fn
    return deco


# --------------------------------------------------------------- shared base platform
def platform(c):
    p = [box(c["trim"], loc=(0, 0, -1.05), size=(W, D, 2.1))]
    # floor pattern (inset 2 studs for the trim)
    fw, fd = W - 4, D - 4
    if c.get("floor") == "planks":
        n = int(fd // 3)
        for i in range(n):
            y = -fd / 2 + (i + 0.5) * fd / n
            p.append(box(c["deck"][i % len(c["deck"])], loc=(0, y, 0.0), size=(fw, fd / n - 0.12, 0.2), bevel=0.04))
    else:  # tiles
        s = c.get("tile", 8)
        nx, ny = int(fw // s), int(fd // s)
        for i in range(nx):
            for j in range(ny):
                col = c["deck"][(i + j) % len(c["deck"])]
                p.append(box(col, loc=(-fw / 2 + (i + 0.5) * fw / nx, -fd / 2 + (j + 0.5) * fd / ny, 0.0),
                             size=(fw / nx - 0.15, fd / ny - 0.15, 0.2), bevel=0.04))
    # ramp at the entrance
    p.append(box(c["trim"], loc=(0, -D / 2 - 1.5, -0.55), size=(W, 3.3, 0.3), rot=(-18, 0, 0)))
    # park ground and the path
    x0, y0, x1, y1 = PARK
    p.append(box(c["park"], loc=((x0 + x1) / 2, (y0 + y1) / 2, 0.15), size=(x1 - x0, y1 - y0, 0.3), bevel=0.1))
    p.append(box(c["path"], loc=(0, -35, 0.13), size=(10, 13, 0.2), bevel=0.05))
    return p, []


def outer_walls(c, wall, pillar):
    w, d = W / 2 - 0.6, D / 2 - 0.6
    line(wall, (-w, -d + 4), (-w, d - 3), c=c)
    line(wall, (w, -d + 4), (w, d - 3), c=c)
    line(wall, (-w + 3, d), (w - 3, d), c=c)
    for x in (-1, 1):
        for y in (-1, 1):
            put(pillar, x * (W / 2 - 1.5), y * (D / 2 - 1.5), c=c)


def park_fence(c, fence):
    x0, y0, x1, y1 = PARK
    g = GATE / 2
    line(fence, (x0, y0), (-g, y0), c=c)
    line(fence, (g, y0), (x1, y0), c=c)
    line(fence, (x1, y0), (x1, y1), c=c)
    line(fence, (x1, y1), (x0, y1), c=c)
    line(fence, (x0, y1), (x0, y0), c=c)


def layout(c, P):
    """Places every piece of a theme. P maps piece names to builder functions."""
    put(platform, c=c)
    outer_walls(c, P["wall"], P["pillar"])
    park_fence(c, P["fence"])
    put(P["arch"], 0, -42, c=c)
    put(P["hatchery"], 0, -28, c=c)
    for x in (-13, 13):
        put(P["incubator"], x, -24, c=c)
    for x in (-40, 40):
        put(P["lamp"], x, -40, c=c)
    put(P["house"], 29, 31, 33, c=c)
    # the Pet Trader NPC stands at (-31, -28) facing +X (the path): the stall sits in front
    put(P["stall"], -26.8, -28, 90, c=c)
    P["decor"](c)


# ============================================================ 1. AUTUMN HARVEST
AUT = dict(floor="planks", deck=["C48E5C", "B9824F", "CF9A66"], trim="805434", park="8DB255", path="B08A5A",
           wood="C48E5C", dark="805434", light="E0B482", straw="F2CF6A", orange="F28C28", red="D9442B",
           yellow="F5C342", leaves=["F28C28", "D9442B", "F5C342", "E06A1F"], glow="FFC56B")


def aut_wall(c, L):
    p = []
    for x in (-L / 2, L / 2):
        p.append(box(c["dark"], loc=(x, 0, 1.6), size=(0.7, 0.7, 3.2), bevel=0.1))
    for z, col in ((1.1, c["wood"]), (2.5, c["light"])):
        p.append(box(col, loc=(0, 0, z), size=(L, 0.4, 0.45), bevel=0.1, rot=(0, (1 if z < 2 else -1) * 1.5, 0)))
    return p, []


def aut_fence(c, L):
    p = [box(c["dark"], loc=(x, 0, 1.2), size=(0.5, 0.5, 2.4), bevel=0.08) for x in (-L / 2, L / 2)]
    for z in (0.8, 1.8):
        p.append(box(c["wood"], loc=(0, 0, z), size=(L, 0.3, 0.32), bevel=0.06))
    for i in range(int(L // 1.6)):
        x = -L / 2 + 0.8 + i * 1.6
        p.append(box(c["light"], loc=(x, 0.18, 1.3), size=(0.5, 0.12, 2.1), bevel=0.05))
        p.append(cone(c["light"], loc=(x, 0.18, 2.5), r=0.35, h=0.4, verts=4, rot=(90, 45, 0), smooth=False))
    return p, []


def aut_pillar(c):
    p = [cyl(c["dark"], loc=(0, 0, 3.5), r=1.1, h=7, verts=12),
         cyl(c["orange"], loc=(0, 0, 1.2), r=1.2, h=0.6, verts=12),
         box(c["dark"], loc=(0, 0, 7.6), size=(2.4, 2.4, 0.4), bevel=0.08),
         cone(c["red"], loc=(0, 0, 9.4), r=1.5, h=1.3, verts=4, rot=(0, 0, 45), smooth=False)]
    p += pumpkin(c["orange"], 0.7, (1.2, -1.2, 0))
    g = [box(c["glow"], loc=(0, 0, 8.4), size=(1.4, 1.4, 1.2))]
    return p, g


def aut_arch(c):
    p = []
    for x in (-7, 7):
        p.append(cyl(c["dark"], loc=(x, 0, 5), r=0.85, h=10, verts=12))
        p.append(box("8C8C96", loc=(x, 0, 0.4), size=(2.2, 2.2, 0.8), bevel=0.3))
        p += pumpkin(c["orange"], 1.0, (x + (1.8 if x > 0 else -1.8), -1.4, 0))
        p += pumpkin(c["yellow"], 0.6, (x + (2.9 if x > 0 else -2.9), -0.2, 0))
        p.append(box(c["straw"], loc=(x + (1.4 if x > 0 else -1.4), 1.6, 0.7), size=(2.4, 1.6, 1.4), bevel=0.3))
    p.append(box(c["wood"], loc=(0, 0, 10.2), size=(18, 1.4, 1.2), bevel=0.2))
    p.append(box(c["dark"], loc=(0, 0, 10.9), size=(19, 1.6, 0.3), bevel=0.08))
    for k in range(4):
        p.append(box(c["light"] if k % 2 else c["wood"], loc=(0, 0, 11.3 + k * 0.75), size=(11, 0.5, 0.72), bevel=0.06))
    p.append(box(c["dark"], loc=(0, 0.15, 12.45), size=(11.6, 0.4, 3.4), bevel=0.1))
    # leaf garland sagging between the posts
    for i in range(29):
        t = i / 28
        x = -6.6 + t * 13.2
        z = 9.4 - math.sin(t * math.pi) * 1.8
        p.append(ico(c["leaves"][i % 4], loc=(x, -0.85, z), scale=(0.45, 0.2, 0.4), rot=(0, i * 37, 0), sub=1))
    return p, []


def aut_hatchery(c):
    p = [cyl(c["dark"], loc=(0, 0, 0.3), r=9, h=0.6, verts=32),
         cyl(c["straw"], loc=(0, 0, 0.7), r=8.5, h=0.3, verts=32),
         torus(shade(c["straw"], -0.1), loc=(0, 0, 0.95), R=5.6, r=0.9, seg=40, mseg=8),
         cyl(shade(c["straw"], 0.25), loc=(0, 0, 0.9), r=2.2, h=0.12, verts=20)]
    for i, (x, y) in enumerate(ring(10, 8.3, 0.3)):
        p += pumpkin([c["orange"], c["yellow"], c["red"]][i % 3], 0.55, (x, y, 0.8))
    return p, []


def aut_incubator(c):
    p = [box(c["straw"], loc=(0, 0, 0.75), size=(2.6, 2.0, 1.5), bevel=0.3)]
    p += pumpkin(c["orange"], 1.0, (0, 0, 1.45))
    g = [box(c["glow"], loc=(x, -0.98, 2.4), size=(0.28, 0.1, 0.28), rot=(0, 45, 0)) for x in (-0.35, 0.35)]
    g.append(box(c["glow"], loc=(0, -0.98, 1.85), size=(0.8, 0.1, 0.18)))
    return p, g


def aut_lamp(c):
    p = [box(c["dark"], loc=(0, 0, 0.3), size=(1.4, 1.4, 0.6), bevel=0.15),
         box(c["wood"], loc=(0, 0, 4), size=(0.5, 0.5, 8), bevel=0.08),
         box(c["dark"], loc=(0, -0.8, 8.0), size=(0.35, 2.0, 0.35), bevel=0.06),
         cyl("5A5A66", loc=(0, -1.5, 7.55), r=0.04, h=0.6, verts=6)]
    p += pumpkin(c["orange"], 0.8, (0, -1.5, 5.9))
    g = [box(c["glow"], loc=(x, -2.28, 6.65), size=(0.22, 0.08, 0.22), rot=(0, 45, 0)) for x in (-0.28, 0.28)]
    g.append(box(c["glow"], loc=(0, -2.28, 6.2), size=(0.6, 0.08, 0.14)))
    return p, g


def aut_house(c):
    red, white = "C8402F", "FFF4E6"
    p = gable(red, "6B4A3A", "5A3D30", 12, 10, 6, 4.5, z0=0.4)
    p.insert(0, box("8C8C96", loc=(0, 0, 0.2), size=(13, 11, 0.4), bevel=0.15))
    for x in (-6, 6):
        for y in (-5, 5):
            p.append(box(white, loc=(x, y, 3.4), size=(0.5, 0.5, 6), bevel=0.05))
    # barn door with X brace
    p.append(box(white, loc=(0, -5.1, 2.4), size=(5, 0.2, 4.2)))
    p.append(box(red, loc=(0, -5.2, 2.4), size=(4.4, 0.2, 3.6)))
    for s in (-1, 1):
        p.append(box(white, loc=(0, -5.32, 2.4), size=(5.3, 0.15, 0.35), rot=(0, s * 39, 0)))
    p.append(box(white, loc=(0, -5.15, 8.3), size=(2.2, 0.2, 2.0)))
    p.append(box("3A2618", loc=(0, -5.25, 8.3), size=(1.6, 0.2, 1.4)))
    p.append(box(c["straw"], loc=(0, -5.4, 7.9), size=(1.4, 0.4, 0.6), bevel=0.2))
    # weathervane rooster-ish arrow
    p.append(cyl("3A3F4A", loc=(0, 0, 12.2), r=0.08, h=2.2, verts=6))
    p.append(box("3A3F4A", loc=(0, 0, 12.9), size=(1.8, 0.1, 0.12)))
    p.append(cone("3A3F4A", loc=(0.95, 0, 12.9), r=0.25, h=0.4, verts=3, rot=(0, 90, 0), smooth=False))
    for i, (x, y) in enumerate([(-4.5, -6.6), (4.2, -6.8), (5.8, -6.0)]):
        p += pumpkin(c["leaves"][i], 0.7 + 0.2 * (i % 2), (x, y, 0))
    p.append(box(c["straw"], loc=(-6.8, -3, 0.75), size=(1.6, 2.6, 1.5), bevel=0.3))
    return p, []


def aut_stall(c):
    p = []
    # apple cart
    p.append(box(c["wood"], loc=(0, 0, 1.9), size=(7, 3.4, 1.6), bevel=0.15))
    p.append(box(c["dark"], loc=(0, 0, 2.8), size=(7.3, 3.7, 0.3), bevel=0.08))
    for x in (-2.4, 2.4):
        p.append(torus(c["dark"], loc=(x, -1.9, 1.1), R=1.0, r=0.2, rot=(90, 0, 0), seg=16, mseg=6))
        p.append(cyl(c["light"], loc=(x, -1.9, 1.1), r=0.25, h=0.4, rot=(90, 0, 0), verts=8))
    rnd = random.Random(3)
    for i in range(22):
        p.append(sphere(rnd.choice(["D93A2B", "E85A3A", "8CC63F", "F5C342"]), loc=(rnd.uniform(-3, 3), rnd.uniform(-1.4, 1.4), 3.2 + rnd.uniform(0, 0.4)), scale=0.42, seg=10, rings=6))
    # awning on posts
    for x in (-3.4, 3.4):
        for y in (-1.6, 1.6):
            p.append(box(c["dark"], loc=(x, y, 3.8), size=(0.3, 0.3, 3.4)))
    for i in range(8):
        p.append(box(c["orange"] if i % 2 else "FFF4DE", loc=(-3.6 + (i + 0.5) * 0.9, 0, 5.8), size=(0.9, 4.2, 0.25), rot=(-8, 0, 0)))
    p.append(box(c["light"], loc=(0, -2.3, 6.4), size=(5, 0.3, 1.1), bevel=0.08))
    return p, []


def aut_decor(c):
    for (x, y, s) in [(-36, -6, 1), (37, 2, 1.1), (-4, 37, 1.25), (12, 34, 0.9), (-38, 30, 1)]:
        put(lambda c=c, s=s, x=x: (blob_tree("6B4A3A", c["leaves"], h=7, r=3.2, seed=int(x)), []), x, y, s=s)
    # pumpkin patch where the pond is
    def patch(c):
        p = [box("6B4A3A", loc=(0, 0, 0.35), size=(14, 9, 0.2), bevel=0.3)]
        for i in range(-3, 4):
            p.append(box("4E7A2E", loc=(i * 1.9, 0, 0.5), size=(0.3, 8, 0.15)))
        rnd = random.Random(7)
        for i in range(9):
            p += pumpkin(rnd.choice([c["orange"], c["orange"], c["yellow"]]), rnd.uniform(0.6, 1.1), (rnd.uniform(-5.5, 5.5), rnd.uniform(-3, 3), 0.4))
        # scarecrow
        p.append(box(c["dark"], loc=(6.5, 3.5, 2.8), size=(0.3, 0.3, 5.6)))
        p.append(box(c["dark"], loc=(6.5, 3.5, 4.0), size=(3.4, 0.25, 0.25)))
        p.append(box("4A7FC1", loc=(6.5, 3.5, 3.6), size=(1.6, 0.9, 1.8), bevel=0.2))
        p.append(sphere(c["straw"], loc=(6.5, 3.5, 5.1), scale=0.7))
        p.append(cyl("8A5A3A", loc=(6.5, 3.5, 5.75), r=1.2, h=0.1, verts=16))
        p.append(cone("8A5A3A", loc=(6.5, 3.5, 6.2), r=0.6, h=0.9, verts=16))
        return p, []
    put(patch, -19, 22, c=c)
    # leaf piles everywhere (the game is about sweeping!)
    rnd = random.Random(11)
    for i in range(14):
        x, y = rnd.uniform(-40, 40), rnd.uniform(-12, 40)
        put(lambda i=i: (leaf_pile(c["leaves"], 1.6, 9, seed=i), []), x, y)
    for (x, y) in [(-25, -40), (24, -40), (-42, -20), (42, -20)]:
        put(lambda: (leaf_pile(c["leaves"], 1.4, 7, seed=x), []), x, y)
    for (x, y) in [(38, -30), (-38, -30)]:
        put(lambda: ([box(c["straw"], loc=(0, 0, 0.75), size=(2.6, 1.6, 1.5), bevel=0.3),
                      box(c["straw"], loc=(0.4, 1.7, 0.75), size=(2.6, 1.6, 1.5), bevel=0.3),
                      box(c["straw"], loc=(0.2, 0.85, 2.2), size=(2.6, 1.6, 1.5), bevel=0.3, rot=(0, 0, 8))], []), x, y)


@theme("autumn")
def autumn():
    layout(AUT, dict(wall=aut_wall, fence=aut_fence, pillar=aut_pillar, arch=aut_arch, hatchery=aut_hatchery,
                     incubator=aut_incubator, lamp=aut_lamp, house=aut_house, stall=aut_stall, decor=aut_decor))
    return dict(ground="9CC45A", sky=(0.62, 0.78, 0.95))


# ============================================================ 2. CANDY KINGDOM
CAN = dict(floor="tiles", tile=8, deck=["FFC2DA", "FFF2F7"], trim="6B3B24", park="9FF0C8", path="F7B2D0",
           pink="FF5C9E", red="E8323C", white="FFFFFF", blue="7FD6FF", yellow="FFE066", purple="B98CFF",
           choc="6B3B24", wafer="E8B877", glow="FF8AC4")


def candy_cane(c, h, r, hook=True, cols=None, x=0.0, y=0.0, z=0.0, side=1):
    cols = cols or [c["red"], c["white"]]
    p = bands(cols, (x, y, z), r, h, int(h / (r * 1.2)) | 1, verts=14)
    if hook:
        R = r * 2.6
        for i in range(12):
            a = math.pi * i / 11
            p.append(sphere(cols[i % 2], loc=(x + side * (R - math.cos(a) * R), y, z + h + math.sin(a) * R), scale=r * 1.05, seg=12, rings=8))
    return p


def can_wall(c, L):
    p = []
    for x in (-L / 2, L / 2):
        p += candy_cane(c, 3.2, 0.35, hook=False, x=x)
        p.append(sphere(c["pink"], loc=(x, 0, 3.4), scale=(0.55, 0.55, 0.45)))
    for z, col in ((1.1, c["white"]), (2.4, c["pink"])):
        p.append(cyl(col, loc=(0, 0, z), r=0.28, h=L, rot=(0, 90, 0), verts=10))
    return p, []


def can_fence(c, L):
    p = []
    n = max(2, int(L // 3))
    for i in range(n):
        x = -L / 2 + (i + 0.5) * L / n
        p.append(cyl("F5E6C8", loc=(x, 0, 1.0), r=0.12, h=2.0, verts=6))
        col = [c["pink"], c["blue"], c["yellow"], c["purple"]][i % 4]
        p.append(cyl(col, loc=(x, 0, 2.2), r=0.75, h=0.28, rot=(90, 0, 0), verts=18))
        p.append(torus(c["white"], loc=(x, 0, 2.2), R=0.42, r=0.09, rot=(90, 0, 0), seg=12, mseg=3))
    p.append(cyl(c["white"], loc=(0, 0, 1.0), r=0.18, h=L, rot=(0, 90, 0), verts=8))
    return p, []


def can_pillar(c):
    p = candy_cane(c, 7, 0.9, hook=False)
    p.append(cyl(c["choc"], loc=(0, 0, 0.3), r=1.5, h=0.6, verts=16))
    g = [sphere(c["glow"], loc=(0, 0, 7.6), scale=(1.3, 1.3, 1.1))]
    return p, g


def can_arch(c):
    p = []
    for x in (-7, 7):
        p += candy_cane(c, 10, 0.9, x=x, side=-1 if x > 0 else 1)  # hooks curl inward
        p.append(cyl(c["choc"], loc=(x, 0, 0.35), r=1.6, h=0.7, verts=16))
        for k, col in enumerate([c["pink"], c["yellow"], c["blue"]]):
            p.append(sphere(col, loc=(x + (2 if x > 0 else -2), -1 + k * 1.1, 0.7), scale=(0.8, 0.8, 0.75)))
    # chocolate bar beam
    p.append(box(c["choc"], loc=(0, 0, 9.4), size=(14, 1.4, 1.6), bevel=0.15))
    for i in range(7):
        p.append(box(shade(c["choc"], 0.12), loc=(-6 + i * 2, -0.75, 9.4), size=(1.7, 0.2, 1.2), bevel=0.1))
    # wafer sign
    p.append(box(c["wafer"], loc=(0, 0, 12.0), size=(11, 0.8, 3.4), bevel=0.15))
    for i in range(6):
        p.append(box(shade(c["wafer"], -0.15), loc=(-4.6 + i * 1.84, -0.42, 12.0), size=(0.12, 0.1, 3.2)))
    p.append(box(c["white"], loc=(0, 0, 13.85), size=(11.3, 1.0, 0.4), bevel=0.15))
    for i in range(9):
        p.append(cyl(c["white"], loc=(-5 + i * 1.25, -0.45, 13.55 - (i % 3) * 0.2), r=0.2, h=0.6 + (i % 3) * 0.4, verts=8))
    for i, col in enumerate([c["red"], c["yellow"], c["blue"], c["pink"], c["purple"]]):
        p.append(sphere(col, loc=(-4 + i * 2, 0, 14.4), scale=(0.65, 0.65, 0.55)))
    return p, []


def can_hatchery(c):
    p = [cyl(c["choc"], loc=(0, 0, 0.35), r=9, h=0.7, verts=36),
         cyl(c["pink"], loc=(0, 0, 0.85), r=8.6, h=0.3, verts=36)]
    for (x, y) in ring(22, 8.6):
        p.append(cyl(c["pink"], loc=(x, y, 0.45), r=0.4, h=0.8, verts=8))
        p.append(sphere(c["pink"], loc=(x, y, 0.05), scale=0.4, seg=8, rings=6))
    for (x, y) in ring(20, 5.6):
        p.append(sphere(c["white"], loc=(x, y, 1.15), scale=(0.95, 0.95, 0.7), seg=12, rings=8))
        p.append(cone(c["white"], loc=(x, y, 1.75), r=0.4, h=0.6, verts=8))
    rnd = random.Random(5)
    for i in range(60):
        a, d = rnd.uniform(0, 2 * math.pi), rnd.uniform(1, 8.2)
        if 4.4 < d < 6.8:
            continue
        p.append(box(rnd.choice([c["yellow"], c["blue"], c["purple"], c["white"], c["red"]]), loc=(math.cos(a) * d, math.sin(a) * d, 1.03), size=(0.5, 0.14, 0.1), rot=(0, 0, rnd.uniform(0, 180))))
    return p, []


def can_incubator(c):
    p = []
    for i in range(12):
        a = i * 2 * math.pi / 12
        p.append(box(c["blue"] if i % 2 else c["white"], loc=(math.cos(a) * 1.3, math.sin(a) * 1.3, 0.9), size=(0.72, 0.3, 1.8), rot=(0, -8, math.degrees(a) + 90)))
    p.append(cyl(c["wafer"], loc=(0, 0, 0.9), r=1.3, h=1.8, verts=16))
    for k, (r, z) in enumerate([(1.5, 2.1), (1.15, 2.7), (0.75, 3.2)]):
        p.append(torus(c["pink"], loc=(0, 0, z), R=r, r=0.45, seg=20, mseg=8))
    p.append(sphere(c["pink"], loc=(0, 0, 3.6), scale=0.5))
    g = [sphere(c["red"], loc=(0, 0, 4.15), scale=0.45)]
    return p, g


def can_lamp(c):
    p = bands([c["white"], c["pink"]], (0, 0, 0), 0.3, 7.5, 9, verts=10)
    p.append(cyl(c["choc"], loc=(0, 0, 0.25), r=0.9, h=0.5, verts=14))
    g = [cyl(c["white"], loc=(0, 0, 8.8), r=1.8, h=0.5, rot=(90, 0, 0), verts=28)]
    for k, col in enumerate([c["pink"], c["blue"], c["yellow"]]):
        g.append(torus(col, loc=(0, -0.28, 8.8), R=0.45 + k * 0.45, r=0.16, rot=(90, 0, 0), seg=24, mseg=4))
    return p, g


def can_house(c):
    ging, icing = "B5652F", c["white"]
    p = gable(ging, icing, "FFE3EF", 12, 10, 6, 4.8, z0=0.4, thick=0.7)
    p.insert(0, box(c["choc"], loc=(0, 0, 0.2), size=(13, 11, 0.4), bevel=0.15))
    for x in (-6, 6):
        for y in (-5, 5):
            p.append(box(icing, loc=(x, y, 3.4), size=(0.5, 0.5, 6), bevel=0.2))
    for y in (-5.25, 5.25):
        for i in range(10):
            p.append(sphere(icing, loc=(-5.4 + i * 1.2, y, 6.45), scale=(0.55, 0.3, 0.4), seg=10, rings=6))
    p.append(box(c["pink"], loc=(0, -5.15, 2.0), size=(3, 0.2, 3.6), bevel=0.2))
    for x in (-1.9, 1.9):
        p += candy_cane(c, 4.2, 0.3, hook=False, x=x, y=-5.4, z=0.4)
    rnd = random.Random(2)
    for sgn in (-1, 1):
        for i in range(8):
            t = rnd.uniform(0.15, 0.85)
            y = rnd.uniform(-4.5, 4.5)
            x = sgn * 6.5 * (1 - t)
            p.append(sphere(rnd.choice([c["red"], c["yellow"], c["blue"], c["purple"], c["pink"]]), loc=(x, y, 0.4 + 6 + 4.8 * t + 0.8), scale=(0.5, 0.5, 0.4)))
    for x in (-3.5, 3.5):
        p.append(cyl(c["white"], loc=(x, -5.2, 4.1), r=0.9, h=0.25, rot=(90, 0, 0), verts=20))
        for k in range(4):
            p.append(box(c["red"], loc=(x, -5.35, 4.1), size=(1.5, 0.05, 0.3), rot=(0, k * 45, 0)))
    return p, []


def can_stall(c):
    p = [box(c["blue"], loc=(0, 0, 1.8), size=(6.5, 3.2, 2.2), bevel=0.3),
         box(c["white"], loc=(0, 0, 3.0), size=(6.8, 3.5, 0.3), bevel=0.1)]
    for x in (-2.3, 2.3):
        p.append(torus(c["choc"], loc=(x, -1.75, 0.8), R=0.75, r=0.2, rot=(90, 0, 0), seg=16, mseg=6))
    p.append(cyl(c["white"], loc=(0, 0, 5), r=0.12, h=4, verts=8))
    for i in range(10):
        a = i * 36
        p.append(cyl(c["pink"] if i % 2 else c["white"], loc=(0, 0, 7.4), r=4.0, r2=0.0, h=1.6, verts=3, rot=(0, 0, a), smooth=False))
    # big ice cream sign
    p.append(cone(c["wafer"], loc=(2.6, 0, 4.4), r=0.8, h=2.2, rot=(180, 0, 0), verts=12))
    for k, col in enumerate([c["pink"], "FFF6D6", "7BD389"]):
        p.append(sphere(col, loc=(2.6, 0, 5.8 + k * 0.85), scale=0.85))
    p.append(sphere(c["red"], loc=(2.6, 0, 8.1), scale=0.3))
    return p, []


def can_decor(c):
    def lolly(c, cols, h=7, r=2.4):
        p = [cyl(c["white"], loc=(0, 0, h / 2), r=0.25, h=h, verts=8)]
        p.append(cyl(cols[0], loc=(0, 0, h + r * 0.8), r=r, h=0.6, rot=(90, 0, 0), verts=28))
        for k in range(3):
            p.append(torus(cols[(k + 1) % len(cols)], loc=(0, -0.32, h + r * 0.8), R=r * (0.3 + k * 0.25), r=0.17, rot=(90, 0, 0), seg=24, mseg=4))
        return p, []

    def cotton(c, col, h=6):
        p = [cyl("F5E6C8", loc=(0, 0, h / 2), r=0.3, h=h, verts=8)]
        rnd = random.Random(h)
        for i in range(6):
            p.append(ico(col, loc=(rnd.uniform(-1.4, 1.4), rnd.uniform(-1.4, 1.4), h + rnd.uniform(0, 2)), scale=rnd.uniform(1.5, 2.2), sub=2, smooth=True))
        return p, []

    put(lolly, -36, -6, c=c, cols=[c["pink"], c["white"], c["yellow"]])
    put(lolly, 37, 2, c=c, cols=[c["blue"], c["white"], c["purple"]])
    put(cotton, -4, 37, c=c, col=c["pink"], h=7)
    put(cotton, 14, 33, c=c, col=c["blue"], h=5)
    put(cotton, -38, 30, c=c, col=c["purple"], h=6)

    def pond(c):
        p = [oval(c["choc"], 7, 5, 0.25, 0.3)]
        for i, (x, y) in enumerate(ring(16, 1)):
            p.append(box(c["wafer"], loc=(x * 7.4, y * 5.4, 0.5), size=(1.6, 1.0, 1.0), rot=(0, 0, math.degrees(math.atan2(y, x))), bevel=0.1))
        return p, []
    put(pond, -19, 22, c=c)
    rnd = random.Random(4)
    for i in range(12):
        x, y = rnd.uniform(-40, 40), rnd.uniform(-10, 40)
        if abs(x + 19) < 9 and abs(y - 22) < 7:
            continue
        col = rnd.choice([c["red"], c["yellow"], c["blue"], c["purple"], c["pink"]])
        put(lambda col=col: ([sphere(col, loc=(0, 0, 0.3), scale=(1.1, 1.1, 1.1))], []), x, y)
    for (x, y) in [(-25, -40), (25, -40), (38, -30), (-38, -30)]:
        put(lambda: ([sphere(c["pink"], loc=(0, 0, 0.4), scale=(1.6, 1.6, 1.4)), cone(c["white"], loc=(0, 0, 1.9), r=0.8, h=1.2, verts=10)], []), x, y)


@theme("candy")
def candy():
    layout(CAN, dict(wall=can_wall, fence=can_fence, pillar=can_pillar, arch=can_arch, hatchery=can_hatchery,
                     incubator=can_incubator, lamp=can_lamp, house=can_house, stall=can_stall, decor=can_decor))
    return dict(ground="FFD9EA", sky=(0.85, 0.80, 0.98))


# ============================================================ 3. WINTER LODGE
WIN = dict(floor="planks", deck=["A87B57", "9A6F4D", "B58863"], trim="5E3F2A", park="EAF2FA", path="C9DCEB",
           wood="A87B57", dark="5E3F2A", snow="F7FBFF", ice="BFE6FF", red="D9343B", green="2F7D4E",
           stone="9AA0AA", glow="FFC56B")


def snowcap(x, y, z, sx, sy, col="F7FBFF"):
    return sphere(col, loc=(x, y, z), scale=(sx, sy, 0.35), seg=14, rings=8)


def win_wall(c, L):
    p = []
    for x in (-L / 2, L / 2):
        p.append(cyl(c["dark"], loc=(x, 0, 1.7), r=0.4, h=3.4, verts=10))
        p.append(snowcap(x, 0, 3.45, 0.55, 0.55))
    for z in (1.1, 2.6):
        p.append(cyl(c["wood"], loc=(0, 0, z), r=0.3, h=L, rot=(0, 90, 0), verts=10))
    p.append(box(c["snow"], loc=(0, 0, 2.95), size=(L, 0.5, 0.25), bevel=0.1))
    p.append(box(c["snow"], loc=(0, 0.4, 0.3), size=(L, 1.2, 0.6), bevel=0.25))
    return p, []


def win_fence(c, L):
    p = [cyl(c["dark"], loc=(x, 0, 1.2), r=0.3, h=2.4, verts=8) for x in (-L / 2, L / 2)]
    p += [snowcap(x, 0, 2.45, 0.4, 0.4) for x in (-L / 2, L / 2)]
    for z in (0.9, 1.9):
        p.append(cyl(c["wood"], loc=(0, 0, z), r=0.2, h=L, rot=(0, 90, 0), verts=8))
    p.append(box(c["snow"], loc=(0, 0, 2.12), size=(L, 0.35, 0.16), bevel=0.06))
    return p, []


def win_pillar(c):
    p = [cyl(c["dark"], loc=(0, 0, 3.5), r=1.1, h=7, verts=12),
         cyl(c["red"], loc=(0, 0, 1.2), r=1.2, h=0.6, verts=12),
         box(c["dark"], loc=(0, 0, 7.6), size=(2.4, 2.4, 0.4), bevel=0.08),
         snowcap(0, 0, 9.3, 1.4, 1.4)]
    for x in (-0.6, 0.6):
        for y in (-0.6, 0.6):
            p.append(box(c["dark"], loc=(x, y, 8.4), size=(0.2, 0.2, 1.2)))
    p.append(box(c["dark"], loc=(0, 0, 9.05), size=(1.8, 1.8, 0.25)))
    g = [box(c["glow"], loc=(0, 0, 8.4), size=(1.1, 1.1, 1.1))]
    return p, g


def win_arch(c):
    p = []
    for x in (-7, 7):
        p.append(cyl(c["dark"], loc=(x, 0, 5), r=0.85, h=10, verts=12))
        p.append(box(c["stone"], loc=(x, 0, 0.4), size=(2.2, 2.2, 0.8), bevel=0.3))
        p.append(snowcap(x, 0, 0.85, 1.3, 1.3))
        p.append(snowcap(x, 0.6, 0.3, 2.0, 1.6))
    p.append(cyl(c["wood"], loc=(0, 0, 10.2), r=0.75, h=18, rot=(0, 90, 0), verts=12))
    p.append(box(c["snow"], loc=(0, 0, 10.95), size=(18.2, 1.5, 0.5), bevel=0.22))
    for k in range(4):
        p.append(box(shade(c["wood"], 0.15) if k % 2 else c["wood"], loc=(0, 0, 11.6 + k * 0.75), size=(11, 0.5, 0.72), bevel=0.06))
    p.append(box(c["dark"], loc=(0, 0.15, 12.75), size=(11.6, 0.4, 3.4), bevel=0.1))
    p.append(box(c["snow"], loc=(0, 0, 14.6), size=(12, 1.2, 0.6), bevel=0.25))
    for i in range(16):
        x = -8.4 + i * 1.12
        L = 0.6 + (i * 7 % 5) * 0.25
        p.append(cone(c["ice"], loc=(x, -0.55, 9.45 - L / 2), r=0.18, h=L, rot=(180, 0, 0), verts=6))
    # wreath on the beam
    p.append(torus(c["green"], loc=(0, -1.0, 9.3), R=1.1, r=0.38, rot=(90, 0, 0), seg=20, mseg=8))
    p.append(box(c["red"], loc=(0, -1.4, 8.4), size=(0.9, 0.2, 0.6), bevel=0.1))
    for i, (x, z) in enumerate(ring(6, 1.1)):
        p.append(sphere(c["red"], loc=(x, -1.4, 9.3 + z), scale=0.17, seg=8, rings=6))
    return p, []


def win_hatchery(c):
    p = [cyl(c["stone"], loc=(0, 0, 0.3), r=9, h=0.6, verts=32),
         cyl(c["ice"], loc=(0, 0, 0.7), r=8.4, h=0.3, verts=32),
         torus(c["snow"], loc=(0, 0, 0.95), R=5.6, r=0.9, seg=40, mseg=8),
         cyl(shade(c["ice"], 0.4), loc=(0, 0, 0.88), r=2.2, h=0.12, verts=20)]
    for (x, y) in ring(12, 8.7):
        p.append(ico(c["stone"], loc=(x, y, 0.9), scale=(0.7, 0.7, 0.55), sub=1))
        p.append(snowcap(x, y, 1.35, 0.6, 0.6))
    return p, []


def snowman(c, s=1.0, lantern=True):
    p = [sphere(c["snow"], loc=(0, 0, 1.1 * s), scale=1.2 * s),
         sphere(c["snow"], loc=(0, 0, 2.8 * s), scale=0.85 * s),
         sphere(c["snow"], loc=(0, 0, 4.0 * s), scale=0.6 * s),
         cone("F28C28", loc=(0, -0.85 * s, 4.0 * s), r=0.12 * s, h=0.6 * s, rot=(90, 0, 0), verts=8),
         torus(c["red"], loc=(0, 0, 3.45 * s), R=0.6 * s, r=0.2 * s, seg=16, mseg=6),
         box(c["red"], loc=(0.4 * s, -0.55 * s, 3.0 * s), size=(0.3 * s, 0.15 * s, 0.8 * s)),
         cyl("2A2A33", loc=(0, 0, 4.55 * s), r=0.7 * s, h=0.1 * s, verts=16),
         cyl("2A2A33", loc=(0, 0, 4.95 * s), r=0.45 * s, h=0.8 * s, verts=16),
         cyl(c["red"], loc=(0, 0, 4.7 * s), r=0.47 * s, h=0.18 * s, verts=16)]
    for x in (-0.22, 0.22):
        p.append(sphere("2A2A33", loc=(x * s, -0.5 * s, 4.2 * s), scale=0.09 * s, seg=8, rings=6))
    for z in (2.5, 2.9, 3.3):
        p.append(sphere("2A2A33", loc=(0, -0.8 * s, z * s - 0.2 * s), scale=0.09 * s, seg=8, rings=6))
    p.append(box(c["dark"], loc=(-1.25 * s, -0.2 * s, 3.0 * s), size=(1.4 * s, 0.12 * s, 0.12 * s), rot=(0, -30, 0)))
    g = []
    if lantern:
        p.append(box("3A3F4A", loc=(-1.9 * s, -0.2 * s, 2.7 * s), size=(0.7 * s, 0.7 * s, 0.12 * s)))
        g.append(box(c["glow"], loc=(-1.9 * s, -0.2 * s, 2.25 * s), size=(0.55 * s, 0.55 * s, 0.75 * s)))
    return p, g


def win_incubator(c):
    return snowman(c, 0.8)


def win_lamp(c):
    iron = "3A3F4A"
    p = [cyl(iron, loc=(0, 0, 0.3), r=0.8, h=0.6, verts=12), cyl(iron, loc=(0, 0, 4), r=0.22, h=8, verts=10),
         box(iron, loc=(0, 0, 8.05), size=(1.4, 1.4, 0.2)), cone(iron, loc=(0, 0, 8.6), r=1.0, h=0.9, verts=4, rot=(0, 0, 45), smooth=False),
         snowcap(0, 0, 8.95, 0.9, 0.9)]
    for x in (-0.6, 0.6):
        for y in (-0.6, 0.6):
            p.append(box(iron, loc=(x, y, 7.4), size=(0.12, 0.12, 1.2)))
    p.append(torus(c["green"], loc=(0, 0, 5.5), R=0.5, r=0.22, seg=14, mseg=6))
    p.append(box(c["red"], loc=(0, -0.7, 5.3), size=(0.5, 0.15, 0.4)))
    g = [box(c["glow"], loc=(0, 0, 7.4), size=(1.0, 1.0, 1.0))]
    return p, g


def win_house(c):
    Wh, Dh, H = 12, 10, 5.6
    p = [box(c["stone"], loc=(0, 0, 0.25), size=(Wh + 1.2, Dh + 1.2, 0.5), bevel=0.2)]
    n = 7
    for k in range(n):
        z = 0.5 + (k + 0.5) * H / n
        for y in (-Dh / 2, Dh / 2):
            p.append(cyl(c["wood"] if k % 2 else shade(c["wood"], -0.1), loc=(0, y, z), r=H / n / 2 + 0.05, h=Wh + 1.2, rot=(0, 90, 0), verts=10))
        for x in (-Wh / 2, Wh / 2):
            p.append(cyl(c["wood"] if k % 2 == 0 else shade(c["wood"], -0.1), loc=(x, 0, z), r=H / n / 2 + 0.05, h=Dh + 1.2, rot=(90, 0, 0), verts=10))
    roof = gable(c["wood"], c["snow"], shade(c["snow"], -0.04), Wh, Dh, 0.01, 4.6, z0=0.5 + H, thick=1.0, over=1.4)
    bpy.data.objects.remove(roof[0])  # gable() also makes a wall box; the log walls replace it
    p += roof[1:]
    for i in range(14):
        x = -6.5 + i * 1.0
        p.append(cone(c["ice"], loc=(x, -Dh / 2 - 1.2, 0.5 + H - 0.1 - (0.3 + (i * 3 % 4) * 0.15)), r=0.13, h=0.6 + (i * 3 % 4) * 0.3, rot=(180, 0, 0), verts=6))
    p.append(box(c["stone"], loc=(3.5, 2.5, 0.5 + H + 3.5), size=(1.4, 1.4, 5), bevel=0.15))
    p.append(snowcap(3.5, 2.5, 0.5 + H + 6.1, 0.9, 0.9))
    p.append(box(c["dark"], loc=(0, -Dh / 2 - 0.35, 2.3), size=(2.8, 0.3, 3.8), bevel=0.1))
    p.append(torus(c["green"], loc=(0, -Dh / 2 - 0.6, 3.3), R=0.7, r=0.25, rot=(90, 0, 0), seg=16, mseg=6))
    p.append(snowcap(0, -Dh / 2 - 2.0, 0.3, 3.5, 1.8))
    g = []
    for x in (-3.8, 3.8):
        p.append(box(c["dark"], loc=(x, -Dh / 2 - 0.35, 3.4), size=(2.0, 0.3, 1.8), bevel=0.06))
        g.append(box(c["glow"], loc=(x, -Dh / 2 - 0.45, 3.4), size=(1.5, 0.2, 1.3)))
    return p, g


def win_stall(c):
    p = [box(c["wood"], loc=(0, 0, 1.4), size=(6.5, 3, 2.8), bevel=0.15),
         box(c["dark"], loc=(0, 0, 2.9), size=(7, 3.4, 0.3), bevel=0.08),
         box(c["snow"], loc=(0, 0.2, 3.15), size=(6.6, 2.6, 0.2), bevel=0.08)]
    for x in (-3.3, 3.3):
        for y in (-1.5, 1.5):
            p.append(box(c["dark"], loc=(x, y, 4.2), size=(0.3, 0.3, 2.8)))
    for i in range(8):
        p.append(box(c["red"] if i % 2 else c["snow"], loc=(-3.5 + (i + 0.5) * 0.875, 0, 5.75), size=(0.875, 4.2, 0.3), rot=(-10, 0, 0)))
    p.append(box(c["snow"], loc=(0, 0.3, 6.1), size=(7.2, 3.8, 0.35), bevel=0.15, rot=(-10, 0, 0)))
    for i, x in enumerate((-2, -0.6, 0.8, 2.2)):
        col = [c["red"], c["snow"], c["green"], "4A7FC1"][i]
        p.append(cyl(col, loc=(x, -0.7, 3.45), r=0.38, h=0.7, verts=12))
        p.append(cyl("6B3B24", loc=(x, -0.7, 3.78), r=0.3, h=0.08, verts=12))
        p.append(torus(col, loc=(x + 0.4, -0.7, 3.45), R=0.2, r=0.06, rot=(90, 0, 0), seg=10, mseg=4))
    return p, []


def pine(c, h=9, r=3.4):
    p = [cyl(c["dark"], loc=(0, 0, 1), r=0.5, h=2, verts=8)]
    for k in range(3):
        z = 1.5 + k * h * 0.26
        rr = r * (1 - k * 0.25)
        p.append(cone(c["green"], loc=(0, 0, z + h * 0.2), r=rr, h=h * 0.4, verts=12))
        p.append(cone(c["snow"], loc=(0, 0, z + h * 0.32), r=rr * 0.62, h=h * 0.25, verts=12))
    return p, []


def win_decor(c):
    for (x, y, s) in [(-36, -6, 1), (37, 2, 1.15), (-4, 37, 1.3), (12, 34, 0.9), (-38, 30, 1.05), (26, 12, 0.8)]:
        put(pine, x, y, s=s, c=c)

    def pond(c):
        p = [oval(c["ice"], 7, 5, 0.3, 0.25)]
        for (x, y) in ring(16, 1):
            p.append(ico(c["stone"], loc=(x * 7.3, y * 5.3, 0.4), scale=(1.1, 0.9, 0.6), sub=1))
            p.append(snowcap(x * 7.3, y * 5.3, 0.85, 0.9, 0.8))
        return p, []
    put(pond, -19, 22, c=c)
    put(lambda c: snowman(c, 1.1, lantern=False), -8, 18, 20, c=c)
    rnd = random.Random(9)
    for (x, y) in [(38, -30), (-38, -30), (6, 4), (-30, -8)]:
        def gifts(c=c):
            p = []
            for k in range(3):
                col = rnd.choice([c["red"], c["green"], "4A7FC1", "F2C230"])
                sz = rnd.uniform(1.0, 1.6)
                gx, gy = k * 1.4 - 1.4, rnd.uniform(-0.5, 0.5)
                p.append(box(col, loc=(gx, gy, sz / 2), size=(sz, sz, sz), rot=(0, 0, rnd.uniform(0, 40)), bevel=0.06))
                p.append(box(c["snow"], loc=(gx, gy, sz / 2), size=(sz + 0.05, 0.25, sz + 0.05), rot=(0, 0, 0)))
            return p, []
        put(gifts, x, y)
    for i in range(10):
        x, y = rnd.uniform(-40, 40), rnd.uniform(-10, 40)
        put(lambda: ([snowcap(0, 0, 0.3, rnd.uniform(1.5, 2.6), rnd.uniform(1.2, 2))], []), x, y)


@theme("winter")
def winter():
    layout(WIN, dict(wall=win_wall, fence=win_fence, pillar=win_pillar, arch=win_arch, hatchery=win_hatchery,
                     incubator=win_incubator, lamp=win_lamp, house=win_house, stall=win_stall, decor=win_decor))
    return dict(ground="EEF4FA", sky=(0.70, 0.82, 0.95))


# ============================================================ 4. TIKI BEACH
TIK = dict(floor="planks", deck=["E3B878", "D8A867", "ECC58A"], trim="8A5A34", park="62CC64", path="F5DFA8",
           bamboo="C9B061", bdark="8E7A3A", thatch="E2BC62", thatch2="C99E45", wood="8A5A34",
           pink="FF5C8A", teal="2EC4C9", orange="FF8C42", yellow="FFD23F", sand="F5DFA8", glow="FF9A3C")


def tik_wall(c, L):
    p = []
    n = max(2, int(L / 0.75))
    for i in range(n):
        x = -L / 2 + (i + 0.5) * L / n
        h = 3.0 + (0.35 if i % 3 == 0 else 0)
        p.append(cyl(c["bamboo"] if i % 2 else shade(c["bamboo"], -0.08), loc=(x, 0, h / 2), r=0.34, h=h, verts=8))
        p.append(cone(c["bamboo"], loc=(x, 0, h + 0.2), r=0.34, h=0.4, verts=8))
    for z in (0.9, 2.3):
        p.append(cyl(c["bdark"], loc=(0, -0.3, z), r=0.14, h=L, rot=(0, 90, 0), verts=6))
    return p, []


def tik_fence(c, L):
    p = []
    for x in (-L / 2, L / 2):
        p.append(cyl(c["wood"], loc=(x, 0, 1.2), r=0.3, h=2.4, verts=8))
        p.append(sphere(c["wood"], loc=(x, 0, 2.45), scale=0.32, seg=8, rings=6))
    for z in (1.0, 2.0):
        for i in range(8):
            t0, t1 = i / 8, (i + 1) / 8
            sag = 0.35 * (math.sin(t0 * math.pi) + math.sin(t1 * math.pi)) / 2
            p.append(cyl("D9C79A", loc=(-L / 2 + (t0 + t1) / 2 * L, 0, z - sag), r=0.09, h=L / 8 + 0.05, rot=(0, 90, 0), verts=6))
    return p, []


def torch(c, h=4.5):
    p = [cyl(c["bamboo"], loc=(0, 0, h / 2), r=0.22, h=h, verts=8)]
    for z in (h * 0.3, h * 0.6):
        p.append(torus(c["bdark"], loc=(0, 0, z), R=0.24, r=0.06, seg=10, mseg=4))
    p.append(cyl(c["thatch2"], loc=(0, 0, h + 0.35), r=0.35, r2=0.55, h=0.7, verts=10))
    g = [cone(c["glow"], loc=(0, 0, h + 1.2), r=0.42, h=1.1, verts=10), sphere(c["yellow"], loc=(0, 0, h + 0.85), scale=0.35)]
    return p, g


def tik_pillar(c):
    p, g = torch(c, 7.0)
    p += [cyl(c["wood"], loc=(0, 0, 0.3), r=1.3, h=0.6, verts=12)]
    for (x, y) in ring(5, 1.3):
        p.append(ico("8E8C88", loc=(x, y, 0.5), scale=0.45, sub=1))
    return p, g


def totem(c, h=10, r=1.1):
    p = []
    seg = 3
    cols = [c["wood"], shade(c["wood"], 0.18), shade(c["wood"], -0.1)]
    for k in range(seg):
        z0 = k * h / seg
        zc = z0 + h / seg / 2
        p.append(cyl(cols[k], loc=(0, 0, zc), r=r, h=h / seg - 0.05, verts=12))
        face = [c["teal"], c["orange"], c["pink"]][k]
        for x in (-0.42, 0.42):
            p.append(box("FFFFFF", loc=(x, -r * 0.92, zc + 0.35), size=(0.55, 0.3, 0.45), bevel=0.08))
            p.append(box("2A1A10", loc=(x, -r * 1.02, zc + 0.35), size=(0.25, 0.2, 0.25)))
            p.append(box(face, loc=(x, -r * 0.95, zc + 0.75), size=(0.7, 0.3, 0.16)))
        p.append(box(shade(c["wood"], -0.3), loc=(0, -r * 0.95, zc - 0.55), size=(1.2, 0.3, 0.4), bevel=0.08))
        p.append(box("FFFFFF", loc=(0, -r * 1.03, zc - 0.55), size=(1.0, 0.2, 0.12)))
        p.append(box(cols[k], loc=(0, -r * 1.05, zc + 0.05), size=(0.3, 0.4, 0.5), bevel=0.08))
    return p


def thatch_slab(c, L, Dp, z, n=3):
    p = []
    for k in range(n):
        p.append(box(c["thatch"] if k % 2 == 0 else c["thatch2"], loc=(0, 0, z - k * 0.35), size=(L - k * 0.2, Dp + k * 0.9, 0.45), bevel=0.15))
    return p


def tik_arch(c):
    p = []
    for x in (-7, 7):
        t = totem(c, 10, 1.1)
        for o in t:
            o.location.x += x
        p += t
        p.append(box("8E8C88", loc=(x, 0, 0.3), size=(2.6, 2.6, 0.6), bevel=0.3))
        for k, col in enumerate([c["pink"], c["yellow"], c["orange"]]):
            p.append(ico(col, loc=(x + (2 if x > 0 else -2), -1.2 + k, 0.5), scale=(0.6, 0.6, 0.35), sub=1))
    p.append(cyl(c["bamboo"], loc=(0, 0, 10.4), r=0.6, h=18.5, rot=(0, 90, 0), verts=10))
    p += thatch_slab(c, 19.5, 2.4, 11.4)
    for i in range(30):
        p.append(cone(c["thatch2"] if i % 2 else c["thatch"], loc=(-9.5 + i * 0.66, -1.3, 10.6), r=0.35, h=1.1, rot=(180, 0, 0), verts=5))
    p.append(box(c["bamboo"], loc=(0, -0.4, 13.2), size=(11, 0.5, 3.0), bevel=0.1))
    for i in range(12):
        p.append(cyl(shade(c["bamboo"], -0.1 if i % 2 else 0.05), loc=(-5.0 + i * 0.91, -0.7, 13.2), r=0.42, h=3.0, verts=8))
    # flower lei along the beam
    for i in range(22):
        t = i / 21
        p.append(ico([c["pink"], c["yellow"], c["orange"], "FFFFFF"][i % 4], loc=(-6.3 + t * 12.6, -0.9, 9.3 - math.sin(t * math.pi) * 1.5), scale=0.34, sub=1))
    return p, []


def tik_hatchery(c):
    p = [cyl(c["wood"], loc=(0, 0, 0.3), r=9, h=0.6, verts=32),
         cyl(c["sand"], loc=(0, 0, 0.7), r=8.5, h=0.3, verts=32)]
    for (x, y) in ring(26, 5.6):
        p.append(ico("8E8C88", loc=(x, y, 0.95), scale=(0.7, 0.6, 0.5), sub=1))
    for i, (x, y) in enumerate(ring(14, 8.0, 0.2)):
        col = [c["pink"], "FFFFFF", c["orange"]][i % 3]
        p.append(cone(col, loc=(x, y, 1.05), r=0.55, h=0.6, verts=8, rot=(0, 0, i * 20)))
    p.append(cyl(shade(c["sand"], 0.3), loc=(0, 0, 0.88), r=2.2, h=0.12, verts=20))
    return p, []


def tik_incubator(c):
    return torch(c, 3.6)


def tik_lamp(c):
    p, g = torch(c, 7.5)
    p.append(cyl(c["wood"], loc=(0, 0, 0.25), r=0.8, h=0.5, verts=10))
    return p, g


def tik_house(c):
    p = []
    for x in (-5, 5):
        for y in (-4, 4):
            p.append(cyl(c["wood"], loc=(x, y, 1.6), r=0.4, h=3.2, verts=8))
    p.append(box(c["wood"], loc=(0, 0, 3.4), size=(11.5, 9.5, 0.4), bevel=0.1))
    n = 26
    for i in range(n):
        x = -5.2 + (i + 0.5) * 10.4 / n
        for y in (-4.2, 4.2):
            if y < 0 and abs(x) < 1.4:
                continue
            p.append(cyl(c["bamboo"] if i % 2 else shade(c["bamboo"], -0.08), loc=(x, y, 5.6), r=0.22, h=4.2, verts=6))
    for i in range(21):
        y = -4.2 + (i + 0.5) * 8.4 / 21
        for x in (-5.2, 5.2):
            p.append(cyl(c["bamboo"] if i % 2 else shade(c["bamboo"], -0.08), loc=(x, y, 5.6), r=0.22, h=4.2, verts=6))
    p.append(box("3A2618", loc=(0, -4.25, 5.2), size=(2.6, 0.2, 3.4)))
    # thatch hip roof = stacked shrinking slabs
    for k in range(6):
        s = 1 - k / 6.5
        p.append(box(c["thatch"] if k % 2 == 0 else c["thatch2"], loc=(0, 0, 8.0 + k * 0.85), size=(14 * s, 12 * s, 1.0), bevel=0.3))
    p.append(cone(c["thatch"], loc=(0, 0, 13.6), r=1.4, h=1.6, verts=8))
    # ladder
    for x in (-0.9, 0.9):
        p.append(box(c["wood"], loc=(x, -6.0, 1.7), size=(0.25, 0.25, 3.8), rot=(-25, 0, 0)))
    for k in range(5):
        p.append(box(c["bamboo"], loc=(0, -6.8 + k * 0.4, 0.4 + k * 0.75), size=(2.0, 0.2, 0.2)))
    for i, (x, y) in enumerate([(-3, -4.6), (3, -4.6)]):
        p.append(ico([c["pink"], c["yellow"]][i], loc=(x, y, 4.2), scale=0.5, sub=1))
    return p, []


def tik_stall(c):
    p = [box(c["bamboo"], loc=(0, 0, 1.6), size=(6.5, 2.6, 3.2), bevel=0.2)]
    for i in range(14):
        p.append(cyl(shade(c["bamboo"], -0.1 if i % 2 else 0.05), loc=(-3.0 + i * 0.46, -1.35, 1.6), r=0.24, h=3.2, verts=6))
    p.append(box(c["wood"], loc=(0, 0, 3.3), size=(7, 3, 0.3), bevel=0.08))
    for x in (-3.2, 3.2):
        for y in (-1.2, 1.2):
            p.append(cyl(c["bamboo"], loc=(x, y, 4.6), r=0.2, h=2.8, verts=6))
    p += thatch_slab(c, 8.5, 4.5, 6.4)
    for i, x in enumerate((-2, -0.6, 0.8, 2.2)):
        p.append(sphere("6B4A2A", loc=(x, -0.6, 3.85), scale=0.5, seg=10, rings=8))
        p.append(cyl("7BD389", loc=(x + 0.2, -0.6, 4.4), r=0.04, h=0.8, verts=4, rot=(0, 20, 0)))
    for k, col in enumerate([c["teal"], c["pink"]]):
        p.append(box(col, loc=(4.0 + k * 0.9, 0.5, 2.6), size=(0.8, 0.25, 5), bevel=0.35, rot=(0, -12 + k * 6, 0)))
    return p, []


def palm(c, h=9, lean=12, seed=1):
    p = []
    rnd = random.Random(seed)
    n = 9
    top = Vector((0, 0, 0))
    for k in range(n):
        t = (k + 0.5) / n
        x = math.sin(math.radians(lean)) * h * t * t
        z = h * t
        p.append(cyl(c["wood"] if k % 2 else shade(c["wood"], 0.15), loc=(x, 0, z), r=0.55 - 0.2 * t, r2=0.42 - 0.2 * t, h=h / n + 0.1, verts=8, rot=(0, lean * t * 1.4, 0)))
        top = Vector((x, 0, z + h / n / 2))
    for i in range(7):
        a = i * 2 * math.pi / 7 + rnd.uniform(-0.2, 0.2)
        L = 4.2
        mid = top + Vector((math.cos(a) * L / 2, math.sin(a) * L / 2, -0.4))
        p.append(box("3FAE4A" if i % 2 else "2E8B3E", loc=tuple(mid), size=(L, 1.1, 0.15), rot=(0, 22, math.degrees(a)), bevel=0.05))
    for k in range(3):
        a = k * 2.1
        p.append(sphere("6B4A2A", loc=(top.x + math.cos(a) * 0.5, math.sin(a) * 0.5, top.z - 0.5), scale=0.4, seg=10, rings=8))
    return p, []


def tik_decor(c):
    for (x, y, s, yaw) in [(-36, -6, 1, 30), (37, 2, 1.1, 200), (-4, 37, 1.2, 120), (14, 34, 0.9, 260), (-38, 30, 1.0, 330)]:
        put(palm, x, y, yaw, s=s, c=c, seed=int(x))

    def lagoon(c):
        p = [oval(c["teal"], 7, 5, 0.3, 0.3), oval(c["sand"], 8.2, 6.2, 0.2, 0.3)]
        for (x, y) in ring(10, 1, 0.4):
            p.append(ico("8E8C88", loc=(x * 7.6, y * 5.6, 0.45), scale=(0.9, 0.7, 0.5), sub=1))
        return p, []
    put(lagoon, -19, 22, c=c)

    def umbrella(c):
        p = [cyl("FFFFFF", loc=(0, 0, 2.4), r=0.1, h=4.8, verts=6)]
        for i in range(8):
            p.append(cyl([c["pink"], "FFFFFF"][i % 2], loc=(0, 0, 4.6), r=3.0, r2=0.0, h=1.2, verts=3, rot=(0, 0, i * 45), smooth=False))
        p.append(box(c["teal"], loc=(1.5, 1.5, 0.35), size=(1.6, 3.4, 0.1)))
        return p, []
    put(umbrella, 30, -6, c=c)
    put(umbrella, -8, 12, c=c)
    for (x, y, col) in [(38, -30, "teal"), (-38, -30, "orange")]:
        put(lambda col=col: ([box(c[col], loc=(0, 0, 2.4), size=(1.4, 0.3, 4.8), bevel=0.6, rot=(0, 8, 0)), box("FFFFFF", loc=(0, -0.16, 2.4), size=(0.2, 0.05, 4.4))], []), x, y)


@theme("tiki")
def tiki():
    layout(TIK, dict(wall=tik_wall, fence=tik_fence, pillar=tik_pillar, arch=tik_arch, hatchery=tik_hatchery,
                     incubator=tik_incubator, lamp=tik_lamp, house=tik_house, stall=tik_stall, decor=tik_decor))
    return dict(ground="F5DFA8", sky=(0.55, 0.85, 0.98))


# ============================================================ 5. CASTLE KEEP
CAS = dict(floor="tiles", tile=6, deck=["BDB8AE", "ADA89E", "C8C3B9"], trim="7D7A74", park="6FBF4A", path="D6CBB0",
           stone="B8B3A8", sdark="8E8A82", blue="3A5BD9", gold="F2C230", red="D93A3A", hedge="3E9A44",
           cream="FFF4DE", glow="FFB347")


def merlons(c, L, z, depth=1.2, h=0.9, step=1.6):
    p = []
    n = max(1, int(L // step))
    for i in range(n):
        if i % 2 == 0:
            p.append(box(c["stone"], loc=(-L / 2 + (i + 0.5) * L / n, 0, z + h / 2), size=(L / n, depth, h), bevel=0.06))
    return p


def cas_wall(c, L):
    p = [box(c["stone"], loc=(0, 0, 1.4), size=(L, 1.1, 2.8), bevel=0.08),
         box(c["sdark"], loc=(0, 0, 2.9), size=(L, 1.3, 0.25), bevel=0.05)]
    p += merlons(c, L, 3.0, 1.1, 0.8, 1.4)
    for x in (-L / 2 + 0.6, L / 2 - 0.6):
        p.append(box(c["sdark"], loc=(x, 0, 1.6), size=(1.3, 1.5, 3.2), bevel=0.1))
    p.append(box(c["sdark"], loc=(0, -0.6, 0.7), size=(L * 0.3, 0.1, 0.4)))
    return p, []


def cas_fence(c, L):
    p = [box(c["hedge"], loc=(0, 0, 0.9), size=(L, 1.4, 1.8), bevel=0.4)]
    for x in (-L / 2, L / 2):
        p.append(box(c["sdark"], loc=(x, 0, 1.0), size=(1.0, 1.0, 2.0), bevel=0.1))
        p.append(sphere(c["gold"], loc=(x, 0, 2.3), scale=0.38, seg=10, rings=6))
    return p, []


def tower(c, r=2.2, h=9, roof=None, flag=True):
    roof = roof or c["blue"]
    p = [cyl(c["stone"], loc=(0, 0, h / 2), r=r, h=h, verts=16),
         cyl(c["sdark"], loc=(0, 0, h + 0.2), r=r + 0.3, h=0.4, verts=16),
         cone(roof, loc=(0, 0, h + 0.4 + r * 1.1), r=r + 0.4, h=r * 2.2, verts=16),
         cyl(c["gold"], loc=(0, 0, h + 0.4 + r * 2.2 + 0.4), r=0.07, h=1.4, verts=6)]
    if flag:
        p.append(box(c["red"], loc=(0.55, 0, h + 0.4 + r * 2.2 + 0.85), size=(1.0, 0.06, 0.6)))
    g = [box(c["glow"], loc=(0, -r + 0.05, h * 0.62), size=(0.6, 0.2, 1.0))]
    return p, g


def cas_pillar(c):
    return tower(c, 1.5, 7, flag=False)


def cas_arch(c):
    p, g = [], []
    for x in (-7.5, 7.5):
        p.append(box(c["stone"], loc=(x, 0, 7), size=(5, 5, 14), bevel=0.12))
        for o in merlons(c, 5.4, 14, 5.4, 1.0, 1.08):
            o.location.x += x
            p.append(o)
        p.append(cone(c["blue"], loc=(x, 0, 17.2), r=3.6, h=5, verts=4, rot=(0, 0, 45), smooth=False))
        p.append(cyl(c["gold"], loc=(x, 0, 20.3), r=0.08, h=1.6, verts=6))
        p.append(box(c["red"], loc=(x + 0.6, 0, 20.7), size=(1.2, 0.06, 0.7)))
        # banner
        p.append(box(c["blue"], loc=(x, -2.6, 8.5), size=(2.4, 0.15, 4.5)))
        p.append(cone(c["blue"], loc=(x, -2.6, 5.9), r=1.2, h=0.8, verts=3, rot=(-90, 0, 0), smooth=False))
        p.append(box(c["gold"], loc=(x, -2.7, 9.4), size=(1.0, 0.1, 1.0), rot=(0, 45, 0)))
        p.append(box(c["gold"], loc=(x, -2.65, 10.8), size=(2.6, 0.12, 0.25)))
        g.append(box(c["glow"], loc=(x, -2.55, 12.3), size=(0.7, 0.1, 1.1)))
        for k in range(3):
            p.append(box(c["sdark"], loc=(x, -2.52, 2 + k * 1.2), size=(5.05, 0.1, 0.12)))
    # gate wall over the opening (10 wide, 9 high)
    p.append(box(c["stone"], loc=(0, 0, 11.5), size=(10, 3.6, 5), bevel=0.08))
    p += [o for o in merlons(c, 10, 14, 3.6, 1.0, 1.25)]
    for x in (-4.6, 4.6):  # rounded corners of the gate opening
        p.append(box(c["stone"], loc=(x, 0, 8.6), size=(1.0, 3.4, 1.4), rot=(0, 45 if x < 0 else -45, 0)))
    # portcullis (raised)
    for i in range(7):
        p.append(box("3A3F4A", loc=(-3.6 + i * 1.2, -1.9, 10.6), size=(0.22, 0.22, 2.4)))
    for z in (9.8, 11.2):
        p.append(box("3A3F4A", loc=(0, -1.9, z), size=(8.4, 0.2, 0.2)))
    for i in range(7):
        p.append(cone("3A3F4A", loc=(-3.6 + i * 1.2, -1.9, 9.2), r=0.15, h=0.4, rot=(180, 0, 0), verts=4))
    p.append(box(c["sdark"], loc=(0, -1.95, 12.6), size=(7.5, 0.3, 1.8), bevel=0.1))
    return p, g


def cas_hatchery(c):
    p = [cyl(c["sdark"], loc=(0, 0, 0.3), r=9, h=0.6, verts=36),
         cyl(c["stone"], loc=(0, 0, 0.75), r=8.4, h=0.3, verts=36),
         torus(c["gold"], loc=(0, 0, 0.92), R=8.2, r=0.22, seg=48, mseg=6),
         cyl(c["red"], loc=(0, 0, 0.9), r=6.4, h=0.12, verts=36),
         torus(c["gold"], loc=(0, 0, 1.0), R=5.6, r=0.35, seg=40, mseg=6),
         cyl(c["gold"], loc=(0, 0, 0.98), r=2.2, h=0.12, verts=20)]
    for (x, y) in ring(8, 8.9, math.pi / 8):
        p.append(box(c["stone"], loc=(x, y, 1.3), size=(0.9, 0.9, 2.0), bevel=0.1))
        p.append(sphere(c["gold"], loc=(x, y, 2.5), scale=0.35, seg=10, rings=6))
    return p, []


def cas_incubator(c):
    p = [box(c["stone"], loc=(0, 0, 0.3), size=(2.2, 2.2, 0.6), bevel=0.1),
         cyl(c["stone"], loc=(0, 0, 1.6), r=0.55, r2=0.45, h=2.2, verts=10),
         cyl("3A3F4A", loc=(0, 0, 3.0), r=0.6, r2=1.2, h=0.7, verts=12),
         torus(c["gold"], loc=(0, 0, 3.35), R=1.2, r=0.1, seg=16, mseg=4)]
    g = [cone(c["glow"], loc=(0, 0, 3.9), r=0.9, h=1.4, verts=10), sphere("FFE066", loc=(0, 0, 3.5), scale=0.6)]
    return p, g


def cas_lamp(c):
    p = [box(c["stone"], loc=(0, 0, 0.4), size=(1.6, 1.6, 0.8), bevel=0.1),
         box(c["stone"], loc=(0, 0, 3.6), size=(0.9, 0.9, 6), bevel=0.08),
         box(c["sdark"], loc=(0, 0, 6.7), size=(1.5, 1.5, 0.3), bevel=0.05),
         cone(c["blue"], loc=(0, 0, 8.6), r=1.1, h=1.0, verts=4, rot=(0, 0, 45), smooth=False),
         box(c["sdark"], loc=(0, 0, 8.0), size=(1.5, 1.5, 0.2))]
    for x in (-0.6, 0.6):
        for y in (-0.6, 0.6):
            p.append(box("3A3F4A", loc=(x, y, 7.4), size=(0.15, 0.15, 1.1)))
    g = [box(c["glow"], loc=(0, 0, 7.4), size=(1.0, 1.0, 0.9))]
    return p, g


def cas_house(c):
    p, g = tower(c, 4.6, 10, flag=True)
    p.insert(0, cyl(c["sdark"], loc=(0, 0, 0.3), r=5.4, h=0.6, verts=20))
    p.append(cyl(c["stone"], loc=(0, 0, 10.6), r=5.2, h=1.0, verts=20))
    for (x, y) in ring(10, 5.0):
        p.append(box(c["stone"], loc=(x, y, 11.5), size=(1.2, 1.2, 1.0), rot=(0, 0, math.degrees(math.atan2(y, x))), bevel=0.06))
    p.append(cyl("6B4A2A", loc=(0, -4.45, 2.2), r=1.4, h=0.4, rot=(90, 0, 0), verts=16))
    p.append(box("6B4A2A", loc=(0, -4.45, 1.2), size=(2.8, 0.4, 2.2)))
    p.append(box(c["sdark"], loc=(0, -5.3, 0.3), size=(3.6, 1.6, 0.6), bevel=0.08))
    for k in range(4):
        z = 1.5 + k * 2.4
        p.append(torus(c["sdark"], loc=(0, 0, z), R=4.62, r=0.08, seg=24, mseg=4))
    p.append(box(c["blue"], loc=(0, -4.75, 7.2), size=(2.4, 0.15, 3.0)))
    p.append(box(c["gold"], loc=(0, -4.85, 7.4), size=(0.9, 0.1, 0.9), rot=(0, 45, 0)))
    return p, g


def cas_stall(c):
    p = [box("8A5A34", loc=(0, 0, 1.1), size=(6, 2.6, 2.2), bevel=0.1),
         box(c["cream"], loc=(0, 0, 2.25), size=(6.4, 3.0, 0.2))]
    for x in (-3, 3):
        p.append(cyl("8A5A34", loc=(x, 0.8, 3.4), r=0.15, h=4.8, verts=6))
    for i in range(10):
        p.append(cyl(c["red"] if i % 2 else c["cream"], loc=(0, 0.8, 6.3), r=4.4, r2=0.0, h=2.2, verts=3, rot=(0, 0, i * 36), smooth=False))
    p.append(cyl(c["gold"], loc=(0, 0.8, 7.7), r=0.1, h=1.0, verts=6))
    p.append(box(c["blue"], loc=(0.5, 0.8, 8.0), size=(1.0, 0.06, 0.5)))
    for i, x in enumerate((-2, 0, 2)):
        p.append(cyl("3A3F4A", loc=(x, -1.6, 1.4), r=0.9, h=0.15, rot=(90, 0, 0), verts=3 + (i % 2) * 13))
        p.append(box(c["gold"], loc=(x, -1.7, 1.4), size=(0.3, 0.1, 0.3), rot=(0, 45, 0)))
    return p, []


def cas_decor(c):
    def topiary(c, kind=0, h=5):
        p = [cyl("6B4A2A", loc=(0, 0, h / 2), r=0.3, h=h, verts=8), box("C47A4A", loc=(0, 0, 0.6), size=(1.8, 1.8, 1.2), bevel=0.15)]
        if kind == 0:
            p.append(sphere(c["hedge"], loc=(0, 0, h), scale=2.0))
            p.append(sphere(c["hedge"], loc=(0, 0, h * 0.55), scale=1.2))
        else:
            p.append(cone(c["hedge"], loc=(0, 0, h + 0.6), r=2.2, h=5, verts=14))
        return p, []
    for i, (x, y, s) in enumerate([(-36, -6, 1), (37, 2, 1.1), (-4, 37, 1.2), (14, 34, 0.9), (-38, 30, 1.0), (-30, -8, 0.8)]):
        put(topiary, x, y, s=s, c=c, kind=i % 2)

    def fountain(c):
        p = [cyl(c["sdark"], loc=(0, 0, 0.6), r=6.5, h=1.2, verts=32),
             cyl("4AA8F0", loc=(0, 0, 1.15), r=5.9, h=0.2, verts=32),
             cyl(c["stone"], loc=(0, 0, 2.2), r=0.8, h=2.2, verts=12),
             cyl(c["stone"], loc=(0, 0, 3.4), r=2.6, r2=2.2, h=0.6, verts=24),
             cyl("4AA8F0", loc=(0, 0, 3.72), r=2.1, h=0.1, verts=24),
             cyl(c["stone"], loc=(0, 0, 4.6), r=0.4, h=1.8, verts=10),
             sphere(c["gold"], loc=(0, 0, 5.7), scale=0.5)]
        for (x, y) in ring(12, 3.2):
            p.append(sphere("9ED8FF", loc=(x * 0.75, y * 0.75, 2.5), scale=(0.25, 0.25, 0.7), seg=8, rings=6))
        return p, []
    put(fountain, -19, 22, c=c)
    for (x, y) in [(38, -30), (-38, -30), (24, -38), (-24, -38)]:
        put(lambda: ([cyl("8A5A34", loc=(0, 0, 3), r=0.1, h=6, verts=6), box(c["blue"], loc=(0.8, 0, 4.6), size=(1.6, 0.06, 2.6)),
                      box(c["gold"], loc=(0.8, -0.05, 4.8), size=(0.6, 0.06, 0.6), rot=(0, 45, 0))], []), x, y)


def cas_wall_frontl(c, L):
    return cas_wall(c, L)


def cas_wall_frontr(c, L):
    return cas_wall(c, L)


@theme("castle")
def castle():
    layout(CAS, dict(wall=cas_wall, fence=cas_fence, pillar=cas_pillar, arch=cas_arch, hatchery=cas_hatchery,
                     incubator=cas_incubator, lamp=cas_lamp, house=cas_house, stall=cas_stall, decor=cas_decor))
    # front wall from the corner towers to the gatehouse (its towers span x = 5..10)
    w, d = W / 2 - 0.6, D / 2 - 0.6
    line(cas_wall_frontl, (-w + 3, -d), (-10.2, -d), c=CAS)
    line(cas_wall_frontr, (10.2, -d), (w - 3, -d), c=CAS)
    return dict(ground="7FC25A", sky=(0.60, 0.78, 0.98))



# ============================================================ 6. HALLOWEEN NIGHT
HAL = dict(floor="planks", deck=["4A3B5C", "40334F", "554566"], trim="2A2238", park="3F5C3B", path="5A4A3A",
           wood="5A4636", dark="2A2238", iron="1E1A26", stone="8A8798", sdark="6A6778", orange="FF8A1E",
           purple="8E44D9", green="7CFF6B", bone="EDE6D3", ghost="F4F2FF", glow="FFB13D")


def jack(c, r=1.0, loc=(0, 0, 0), face=-1):
    """Jack-o-lantern: a pumpkin with a glowing face on the -Y side (face=-1) or +Y."""
    x, y, z = loc
    p = pumpkin(c["orange"], r, loc)
    fy = y + face * r * 0.55
    g = [box(c["glow"], loc=(x + dx * r, fy, z + r * 0.85), size=(r * 0.24, 0.1, r * 0.24), rot=(0, 45, 0)) for dx in (-0.3, 0.3)]
    g.append(box(c["glow"], loc=(x, fy, z + r * 0.5), size=(r * 0.62, 0.1, r * 0.14)))
    return p, g


def hal_wall(c, L):
    """Wrought-iron fence: posts with spear tips, two rails, a stone footing."""
    p = [box(c["sdark"], loc=(0, 0, 0.3), size=(L, 1.0, 0.6))]
    n = max(2, int(L // 1.4))
    for i in range(n + 1):
        x = -L / 2 + i * L / n
        p.append(cyl(c["iron"], loc=(x, 0, 2.0), r=0.09, h=2.8, verts=6))
        p.append(cone(c["iron"], loc=(x, 0, 3.55), r=0.2, h=0.5, verts=4))
    for z in (1.2, 2.9):
        p.append(box(c["iron"], loc=(0, 0, z), size=(L, 0.14, 0.14)))
    return p, []


def hal_fence(c, L):
    """Crooked old picket fence."""
    rnd = random.Random(int(L * 100))
    p = [box(c["dark"], loc=(x, 0, 1.2), size=(0.45, 0.45, 2.4)) for x in (-L / 2, L / 2)]
    for z in (0.8, 1.7):
        p.append(box(c["wood"], loc=(0, 0, z), size=(L, 0.25, 0.3), rot=(0, rnd.uniform(-2, 2), 0)))
    for i in range(int(L // 1.6)):
        x = -L / 2 + 0.8 + i * 1.6
        h = rnd.uniform(1.8, 2.4)
        p.append(box(shade(c["wood"], rnd.uniform(-0.15, 0.1)), loc=(x, 0.16, h / 2), size=(0.5, 0.1, h), rot=(0, rnd.uniform(-9, 9), 0)))
    return p, []


def hal_pillar(c):
    p = [box(c["stone"], loc=(0, 0, 3.4), size=(2.2, 2.2, 6.8), bevel=0.12),
         box(c["sdark"], loc=(0, 0, 6.95), size=(2.7, 2.7, 0.4), bevel=0.08),
         box(c["sdark"], loc=(0, 0, 0.4), size=(2.7, 2.7, 0.8), bevel=0.08)]
    jp, jg = jack(c, 0.9, (0, 0, 7.1))
    return p + jp, jg


def bat(c, x, y, z, s=1.0, yaw=0):
    a = math.radians(yaw)
    p = [sphere(c["iron"], loc=(x, y, z), scale=(0.35 * s, 0.3 * s, 0.3 * s))]
    for sgn in (-1, 1):
        wx, wy = x + math.cos(a) * sgn * 0.75 * s, y + math.sin(a) * sgn * 0.75 * s
        p.append(cone(c["iron"], loc=(wx, wy, z + 0.1 * s), r=0.55 * s, h=0.12 * s, verts=3,
                      rot=(0, 0, yaw + (0 if sgn > 0 else 180)), smooth=False))
    return p


def hal_arch(c):
    p, g = [], []
    for x in (-7, 7):
        p.append(box(c["stone"], loc=(x, 0, 5), size=(2.2, 2.2, 10), bevel=0.15))
        p.append(box(c["sdark"], loc=(x, 0, 10.2), size=(2.8, 2.8, 0.5), bevel=0.08))
        p.append(box(c["sdark"], loc=(x, 0, 0.5), size=(2.8, 2.8, 1.0), bevel=0.08))
        jp, jg = jack(c, 1.1, (x, 0, 10.4))
        p += jp
        g += jg
        jp, jg = jack(c, 0.8, (x + (1.9 if x > 0 else -1.9), -1.2, 0))
        p += jp
        g += jg
    # iron arch over the gate, with curls, and a hanging sign board
    for R in (6.2, 5.6):
        p.append(lib.arc(c["iron"], loc=(0, 0, 10.4), R=R, r=0.16, rot=(90, 0, 0), keep="above", seg=32))
    for x in (-6.2, 6.2):
        p.append(torus(c["iron"], loc=(x * 0.75, 0, 11.4), R=0.6, r=0.1, rot=(90, 0, 0), seg=12, mseg=4))
    for x in (-3.5, 3.5):
        p.append(cyl(c["iron"], loc=(x, 0, 12.1), r=0.04, h=1.6, verts=4))
    p.append(box(c["wood"], loc=(0, 0, 10.9), size=(8.4, 0.4, 1.4), rot=(0, 3, 0)))
    for i, x in enumerate((-3.2, 0.2, 3.0)):
        p += bat(c, x, -0.6, 15.0 + (i % 2) * 0.8, 1.0, 10 * i)
    # cobweb in the corner of the arch: rings + spokes
    for k in range(3):
        p.append(torus(c["bone"], loc=(-5.6, -0.3, 11.2), R=0.5 + k * 0.45, r=0.035, rot=(90, 0, 0), seg=10, mseg=3))
    for k in range(5):
        a = math.radians(-90 + k * 22)
        p.append(box(c["bone"], loc=(-5.6 + math.cos(a) * 0.8, -0.3, 11.2 + math.sin(a) * 0.8), size=(1.6, 0.04, 0.04),
                     rot=(0, -math.degrees(a), 0)))
    return p, g


def hal_hatchery(c):
    p = [cyl(c["sdark"], loc=(0, 0, 0.3), r=9, h=0.6, verts=32),
         cyl(c["stone"], loc=(0, 0, 0.72), r=8.5, h=0.3, verts=32),
         torus(c["purple"], loc=(0, 0, 0.95), R=5.6, r=0.7, seg=40, mseg=6),
         cyl(shade(c["purple"], 0.3), loc=(0, 0, 0.9), r=2.2, h=0.12, verts=20)]
    g = []
    for i, (x, y) in enumerate(ring(10, 8.0, 0.3)):
        h = 0.8 + (i % 3) * 0.35
        p.append(cyl(c["bone"], loc=(x, y, 0.85 + h / 2), r=0.22, h=h, verts=8))
        g.append(sphere(c["glow"], loc=(x, y, 0.95 + h + 0.15), scale=(0.16, 0.16, 0.28)))
    return p, g


def hal_incubator(c):
    """Bubbling cauldron on three legs over a little fire pit."""
    p = [sphere(c["iron"], loc=(0, 0, 1.5), scale=(1.4, 1.4, 1.1)),
         torus(c["iron"], loc=(0, 0, 2.3), R=1.2, r=0.18, seg=20, mseg=6)]
    for k in range(3):
        a = k * 2 * math.pi / 3
        p.append(cyl(c["iron"], loc=(math.cos(a) * 0.9, math.sin(a) * 0.9, 0.35), r=0.15, h=0.7, verts=6))
    for k in range(5):
        a = k * 2 * math.pi / 5
        p.append(ico("6A4B3A", loc=(math.cos(a) * 1.0, math.sin(a) * 1.0, 0.15), scale=(0.35, 0.25, 0.15), sub=1))
    g = [cyl(c["green"], loc=(0, 0, 2.2), r=1.1, h=0.15, verts=20)]
    for (x, y, r) in ((0.3, 0.2, 0.3), (-0.4, -0.1, 0.22), (0.1, -0.5, 0.18)):
        g.append(sphere(c["green"], loc=(x, y, 2.4), scale=r))
    return p, g


def hal_lamp(c):
    p = [box(c["iron"], loc=(0, 0, 0.3), size=(1.2, 1.2, 0.6)),
         cyl(c["iron"], loc=(0, 0, 3.6), r=0.18, h=6.6, verts=8),
         box(c["iron"], loc=(0, -0.5, 6.95), size=(0.2, 1.2, 0.2)),
         box(c["iron"], loc=(0, -1.0, 6.6), size=(1.1, 1.1, 0.12))]
    for x in (-0.45, 0.45):
        for y in (-0.55, -1.45):
            p.append(box(c["iron"], loc=(x, y, 6.15), size=(0.1, 0.1, 0.9)))
    # witch hat on the lantern
    p.append(cyl(c["iron"], loc=(0, -1.0, 6.75), r=0.95, h=0.1, verts=14))
    p.append(cone(c["iron"], loc=(0.1, -1.0, 7.55), r=0.55, h=1.6, verts=10, rot=(0, 12, 0)))
    p.append(cyl(c["purple"], loc=(0, -1.0, 6.9), r=0.57, h=0.18, verts=12))
    g = [box(c["purple"], loc=(0, -1.0, 6.1), size=(0.8, 0.8, 0.85))]
    return p, g


def hal_house(c):
    wall, roof, roof2 = "5B4A7A", "2A2238", "352B47"
    p = gable(wall, roof, roof2, 12, 10, 6.5, 6.0, z0=0.5)
    p.insert(0, box(c["sdark"], loc=(0, 0, 0.25), size=(13, 11, 0.5), bevel=0.15))
    g = []
    for x in (-6, 6):
        for y in (-5, 5):
            p.append(box(c["dark"], loc=(x, y, 3.75), size=(0.6, 0.6, 6.5)))
    # door + step
    p.append(box(c["dark"], loc=(0, -5.15, 2.2), size=(2.6, 0.3, 3.6)))
    p.append(cyl(c["dark"], loc=(0, -5.15, 4.0), r=1.3, h=0.3, rot=(90, 0, 0), verts=14))
    p.append(box(c["sdark"], loc=(0, -6.0, 0.25), size=(3.6, 1.6, 0.5)))
    # glowing windows and a round attic window
    for x in (-3.8, 3.8):
        p.append(box(c["dark"], loc=(x, -5.2, 4.2), size=(2.0, 0.3, 2.2)))
        g.append(box(c["glow"], loc=(x, -5.3, 4.2), size=(1.5, 0.2, 1.7)))
        p.append(box(c["dark"], loc=(x, -5.4, 4.2), size=(1.6, 0.2, 0.15)))
        p.append(box(c["dark"], loc=(x, -5.4, 4.2), size=(0.15, 0.2, 1.8)))
    p.append(torus(c["dark"], loc=(0, -5.2, 9.0), R=0.9, r=0.18, rot=(90, 0, 0), seg=16, mseg=4))
    g.append(cyl(c["green"], loc=(0, -5.15, 9.0), r=0.8, h=0.2, rot=(90, 0, 0), verts=16))
    # crooked tower at the back corner
    p.append(cyl(wall, loc=(4.8, 3.6, 5.5), r=2.0, h=11, verts=12))
    p.append(cone(roof, loc=(4.8, 3.6, 13.0), r=2.7, h=4.0, verts=12, rot=(0, 8, 0)))
    g.append(box(c["glow"], loc=(4.8, 1.55, 8.4), size=(0.9, 0.2, 1.3)))
    # chimney + bats
    p.append(box(c["sdark"], loc=(-3.5, 2.0, 11.5), size=(1.2, 1.2, 4)))
    p += bat(c, -1.5, -2, 15.5, 1.2, 20) + bat(c, 2.0, -3, 16.5, 1.0, -15)
    jp, jg = jack(c, 0.8, (-2.2, -6.4, 0))
    return p + jp, g + jg


def hal_stall(c):
    # not exported (the game keeps its own Pet Trader stall); a simple crate for the preview
    return [], []


def tombstone(c, kind=0, s=1.0, x=0.0, y=0.0):
    p = []
    if kind == 0:
        p.append(box(c["stone"], loc=(x, y, 1.0 * s), size=(1.6 * s, 0.5 * s, 2.0 * s)))
        p.append(cyl(c["stone"], loc=(x, y, 2.0 * s), r=0.8 * s, h=0.5 * s, rot=(90, 0, 0), verts=12))
        for z in (1.5, 1.1):
            p.append(box(c["sdark"], loc=(x, y - 0.27 * s, z * s), size=(0.9 * s, 0.05, 0.12 * s)))
    else:
        p.append(box(c["stone"], loc=(x, y, 1.3 * s), size=(0.45 * s, 0.45 * s, 2.6 * s)))
        p.append(box(c["stone"], loc=(x, y, 1.9 * s), size=(1.6 * s, 0.45 * s, 0.45 * s)))
    p.append(box("3A3046", loc=(x, y - 0.9 * s, 0.32), size=(1.4 * s, 1.8 * s, 0.12)))
    return p


def dead_tree(c, h=8, seed=1):
    rnd = random.Random(seed)
    p = [cyl(c["dark"], loc=(0, 0, h / 2), r=0.7, r2=0.35, h=h, verts=8)]
    for i in range(5):
        a = i * 2 * math.pi / 5 + rnd.uniform(-0.3, 0.3)
        z = h * rnd.uniform(0.5, 0.9)
        L = rnd.uniform(2.0, 3.4)
        tilt = rnd.uniform(35, 60)
        reach = L / 2 * math.sin(math.radians(tilt))
        mid = (math.cos(a) * reach, math.sin(a) * reach, z + L / 2 * math.cos(math.radians(tilt)))
        p.append(cyl(c["dark"], loc=mid, r=0.22, r2=0.08, h=L, verts=6, rot=(0, tilt, math.degrees(a))))
    return p


def ghost(c, s=1.0):
    p = [sphere(c["ghost"], loc=(0, 0, 2.6 * s), scale=0.9 * s),
         cyl(c["ghost"], loc=(0, 0, 1.7 * s), r=1.15 * s, r2=0.9 * s, h=1.8 * s, verts=12)]
    for x in (-0.3, 0.3):
        p.append(sphere(c["iron"], loc=(x * s, -0.8 * s, 2.7 * s), scale=(0.14 * s, 0.08 * s, 0.22 * s)))
    p.append(sphere(c["iron"], loc=(0, -0.85 * s, 2.25 * s), scale=(0.18 * s, 0.08 * s, 0.14 * s)))
    return p


def hal_decor(c):
    for (x, y, h, sd) in [(-36, -6, 8, 1), (37, 2, 9, 2), (-4, 37, 10, 3), (12, 34, 7, 4), (-38, 30, 8, 5)]:
        put(lambda h=h, sd=sd: (dead_tree(c, h, sd), []), x, y, sd * 40)

    def swamp(c):
        p = [oval("4A7A3A", 7, 5, 0.3, 0.3)]
        for (x, y) in ring(14, 1, 0.2):
            p.append(ico(c["sdark"], loc=(x * 7.4, y * 5.4, 0.45), scale=(0.9, 0.8, 0.5), sub=1))
        g = [sphere(c["green"], loc=(x, y, 0.5), scale=r) for (x, y, r) in ((-2, 1, 0.4), (1.5, -1, 0.3), (3, 1.5, 0.25), (-3.5, -1.5, 0.3))]
        return p, g
    put(swamp, -19, 22, c=c)

    def graveyard(c):
        p = []
        rnd = random.Random(8)
        for i in range(7):
            p += tombstone(c, i % 2, rnd.uniform(0.8, 1.1), (i % 4) * 3.0 - 4.5, (i // 4) * 3.5)
        return p, []
    put(graveyard, 22, 10, -10, c=c)
    put(lambda: (ghost(c, 1.2), []), 8, 20, 20)
    put(lambda: (ghost(c, 0.9), []), -30, 12, -30)
    rnd = random.Random(13)
    for (x, y) in [(-25, -40), (25, -40), (38, -30), (-38, -30), (-10, 4), (30, -8), (-26, 36)]:
        r = rnd.uniform(0.6, 1.1)
        put(lambda r=r: jack(c, r, (0, 0, 0)), x, y, rnd.uniform(-30, 30))
    for i in range(6):
        put(lambda i=i: (bat(c, 0, 0, rnd.uniform(14, 20), 1.3, i * 50), []), rnd.uniform(-35, 35), rnd.uniform(-10, 38))


@theme("halloween")
def halloween():
    layout(HAL, dict(wall=hal_wall, fence=hal_fence, pillar=hal_pillar, arch=hal_arch, hatchery=hal_hatchery,
                     incubator=hal_incubator, lamp=hal_lamp, house=hal_house, stall=hal_stall, decor=hal_decor))
    return dict(ground="3A3348", sky=(0.32, 0.24, 0.48))

# =============================================================================== build + render
def build(name):
    SOLID.clear()
    GLOW.clear()
    a = Asset(f"BaseSkin_{name}", "preview")
    use(a)
    env = T[name]()
    img = lib.build_palette_image(a.name, a.colors)
    mat = lib.palette_material(a.name, img)
    gmat = lib.palette_material(a.name + "_glow", img)
    nt = gmat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = [n for n in nt.nodes if n.type == "TEX_IMAGE"][0]
    nt.links.new(tex.outputs[0], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = 2.5
    for o in SOLID:
        o.data.materials.clear()
        o.data.materials.append(mat)
    for o in GLOW:
        o.data.materials.clear()
        o.data.materials.append(gmat)
    env["colors"] = len(a.colors)
    env["objects"] = len(SOLID) + len(GLOW)
    _env[name] = env
    return env


_env = {}


def render(name, path, view="hero", size=(1600, 1000)):
    env = _env[name]
    scene = bpy.context.scene
    for o in list(bpy.data.objects):
        if o.type in ("CAMERA", "LIGHT") or o.name.startswith("_ground"):
            bpy.data.objects.remove(o)
    # ground
    bpy.ops.mesh.primitive_plane_add(size=600, location=(0, 0, -2.1))
    g = bpy.context.object
    g.name = "_ground"
    gm = bpy.data.materials.new("_ground")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*[c ** 2.2 for c in hex_rgb(env["ground"])], 1)
    g.data.materials.append(gm)
    scene.render.engine = "BLENDER_EEVEE"
    try:
        scene.eevee.taa_render_samples = 64
        scene.eevee.use_shadows = True
    except Exception:
        pass
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.get("_sky") or bpy.data.worlds.new("_sky")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (*env["sky"], 1)
    bg.inputs[1].default_value = 0.45
    scene.world = world
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 35
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    target = Vector((0, 2, 0))
    if view == "hero":
        cam.location = Vector((-58, -96, 62))
        target = Vector((0, 0, -2))
        cam_data.lens = 31
    elif view == "front":
        cam.location = Vector((-20, -72, 22))
        target = Vector((-4, -30, 5))
        cam_data.lens = 30
    else:  # top
        cam.location = Vector((0, -40, 150))
        target = Vector((0, 0, 0))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 4.2
    sun.angle = math.radians(8)
    so = bpy.data.objects.new("sun", sun)
    so.rotation_euler = (math.radians(48), math.radians(8), math.radians(-35))
    scene.collection.objects.link(so)
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


# =============================================================================== export
TRI_BUDGET = 9000  # per MeshPart (Roblox allows ~20k; stay well under)


def _tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def _split_by_colour(o, asset):
    """Glow parts become Neon with ONE colour in game, so split a glow object per swatch."""
    import bmesh
    uv = o.data.uv_layers.active.data
    groups = {}
    for poly in o.data.polygons:
        u, v = uv[poly.loop_start].uv
        i = int(u * lib.GRID) + int((1 - v) * lib.GRID) * lib.GRID
        groups.setdefault(asset.colors[i], []).append(poly.index)
    out = []
    for col, faces in groups.items():
        c = lib.copy(o)
        bm = bmesh.new()
        bm.from_mesh(c.data)
        keep = set(faces)
        bm.faces.ensure_lookup_table()
        bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.index not in keep], context="FACES")
        bm.to_mesh(c.data)
        bm.free()
        out.append((col, c))
    bpy.data.objects.remove(o)
    return out


def export(name, out_dir=None):
    """Builds skin `name` and exports art/out/Skin_<Name>.glb: one MeshPart per piece kind
    (split to stay under TRI_BUDGET), glow split per colour. Returns (path, meta)."""
    out_dir = out_dir or os.path.join(HERE, "..", "out")
    build(name)
    a = lib._asset
    a.name = "Skin_" + name.capitalize()
    groups = {}
    for o in SOLID:
        if o["cat"] == "Stall":
            # the game keeps its own Pet Trader stall (tinted in the skin colour) so the
            # trader NPC, its sign and the sell prompt stay where players know them
            bpy.data.objects.remove(o)
            continue
        groups.setdefault(o["cat"], []).append(o)
    collide = {v[0]: v[1] for v in CATS.values()}
    for cat, objs in groups.items():
        objs.sort(key=_tris)
        chunks, cur, n = [], [], 0
        for o in objs:
            t = _tris(o)
            if cur and n + t > TRI_BUDGET:
                chunks.append(cur)
                cur, n = [], 0
            cur.append(o)
            n += t
        chunks.append(cur)
        for k, chunk in enumerate(chunks):
            pname = cat if k == 0 else f"{cat}{k + 1}"
            bpy.context.view_layer.update()
            a.part(pname, chunk, collide=collide.get(cat, False))
    # glow: per colour, joined across the whole skin (no collisions)
    by_col = {}
    for o in GLOW:
        for col, piece in _split_by_colour(o, a):
            by_col.setdefault(col, []).append(piece)
    for i, (col, pieces) in enumerate(sorted(by_col.items())):
        a.part(f"Body_Glow{i + 1}", pieces, parent="Body", glow=col)
    path, meta = a.export(out_dir)
    meta["kind"] = "prop"
    return path, meta


def export_all(names=None, out_dir=None):
    import json
    out_dir = out_dir or os.path.join(HERE, "..", "out")
    meta_path = os.path.join(out_dir, "meta.json")
    allmeta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
    report = {}
    for n in names or list(T):
        path, meta = export(n, out_dir)
        allmeta[meta["name"]] = meta
        report[meta["name"]] = {"tris": meta["tris"], "parts": len(meta["parts"])}
    json.dump(allmeta, open(meta_path, "w"), indent=1, sort_keys=True)
    return report
