"""Eggs: smooth, round, cute eggs with patterns painted on the shell.

The shell is one smooth mesh with its own painted texture (zigzag bands, spots, swirls,
cracks, stars), so the patterns are crisp and nothing sticks out or floats. Toppers
(sprout, crystals, crown, horns, star) are sunk into the top of the shell and coloured
from the usual palette swatches, which share the same image.

Built 2.6 tall and 2.1 wide, then scaled by SCALE on export (3.1 tall, the size the game
is tuned to). Pivot at the bottom centre, front at -Y.
"""
import math
import random
import bmesh
import bpy
import numpy as np
from mathutils import Vector
import lib
from lib import Asset, use, sphere, cyl, cone, tube, deform, hex_rgb

H = 2.6          # height
R = 1.05         # widest radius
TAPER = 0.16     # how much narrower the top is
SEG, RINGS = 56, 36
SCALE = 1.2      # applied on export

# Texture layout: the shell's texture on top (TW x TH), the palette swatches below it.
TW, TH = 1024, 512
PAL = 64                     # palette strip height (8 x 8 swatches of 8 px)
IMG_W, IMG_H = TW, TH + PAL
SS = 2                       # supersampling per axis when painting the shell


def shade(hexcol, k):
    """Lighter (k > 0) or darker (k < 0) version of a colour."""
    c = [int(hexcol[i:i + 2], 16) for i in (0, 2, 4)]
    if k >= 0:
        c = [round(v + (255 - v) * k) for v in c]
    else:
        c = [round(v * (1 + k)) for v in c]
    return "".join(f"{v:02X}" for v in c)


def taper_k(tt):
    return 1 - np.maximum(0.0, tt) * TAPER + np.minimum(0.0, tt) * 0.03


def radius_at(t):
    tt = 2 * t - 1
    return R * math.sqrt(max(0.0, 1 - tt * tt)) * float(taper_k(tt))


def on_shell(t, ang, out=1.0):
    """Point on the shell at height fraction t and angle ang (degrees, -90 = front)."""
    a = math.radians(ang)
    r = radius_at(t) * out
    return Vector((math.cos(a) * r, math.sin(a) * r, H * t))


def shell(col):
    e = sphere(col, loc=(0, 0, H / 2), scale=(R, R, H / 2), seg=SEG, rings=RINGS)
    mid = H / 2

    def taper(v):
        k = float(taper_k((v.z - mid) / (H / 2)))
        return Vector((v.x * k, v.y * k, v.z))
    deform(e, taper)
    return e


def shell_uv(x, y, z):
    """Texture coordinate (0..1, 0..1 inside the shell area) of a shell point."""
    s = max(-1.0, min(1.0, (z - H / 2) / (H / 2)))
    v = math.asin(s) / math.pi + 0.5
    u = (math.atan2(y, x) / (2 * math.pi)) % 1.0
    return u, v


# ----------------------------------------------------------------- patterns
# A pattern is fn(P) -> bool mask, where P is an (N, 3) array of shell points. Each comes
# with its colour; later ones paint over earlier ones.

def _t_ang(P):
    return P[:, 2] / H, np.degrees(np.arctan2(P[:, 1], P[:, 0]))


def _tri(x):
    x = np.mod(x, 1.0)
    return 1 - np.abs(2 * x - 1)


def zigzag(t0, amp, teeth, width, phase=0.0):
    def f(P):
        t, ang = _t_ang(P)
        c = t0 + amp * (_tri(ang / 360 * teeth + phase) - 0.5)
        return np.abs(t - c) < width / 2
    return f


def wave(t0, amp, waves, width):
    def f(P):
        t, ang = _t_ang(P)
        c = t0 + amp * np.sin(np.radians(ang) * waves)
        return np.abs(t - c) < width / 2
    return f


def spots(points, grow=0.0):
    """points: (t, ang, radius in studs)."""
    cs = [(np.array(on_shell(t, a)), r + grow) for t, a, r in points]

    def f(P):
        m = np.zeros(len(P), bool)
        for c, r in cs:
            m |= np.sum((P - c) ** 2, axis=1) < r * r
        return m
    return f


def scatter(seed, n, rmin, rmax, tmin=0.12, tmax=0.88, avoid=()):
    """Spread spots evenly-ish round the egg without overlaps. avoid: (tlo, thi) ranges."""
    rnd = random.Random(seed)
    pts = []
    tries = 0
    while len(pts) < n and tries < 4000:
        tries += 1
        t, a, r = rnd.uniform(tmin, tmax), rnd.uniform(0, 360), rnd.uniform(rmin, rmax)
        if any(lo - 0.04 < t < hi + 0.04 for lo, hi in avoid):
            continue
        c = on_shell(t, a)
        if all((c - on_shell(t2, a2)).length > r + r2 + 0.14 for t2, a2, r2 in pts):
            pts.append((t, a, r))
    return pts


def swirl(stripes, width, twist=1.4, tmin=0.0, tmax=1.0):
    """Diagonal stripes that spiral round the egg."""
    def f(P):
        t, ang = _t_ang(P)
        x = (ang / 360 + t * twist) * stripes
        return (np.mod(x, 1.0) < width) & (t >= tmin) & (t <= tmax)
    return f


def cap(t_from, wavy=0.0, waves=6):
    """The top of the egg from height t_from up, with a wavy edge."""
    def f(P):
        t, ang = _t_ang(P)
        return t > t_from + wavy * np.sin(np.radians(ang) * waves)
    return f


def crack_paths(seed, n=5):
    rnd = random.Random(seed)
    segs = []
    for i in range(n):
        a = i * 360 / n + rnd.uniform(-20, 20)
        t = rnd.uniform(0.04, 0.1)
        prev = on_shell(t, a)
        for _ in range(rnd.randint(5, 7)):
            t += rnd.uniform(0.07, 0.11)
            a += rnd.uniform(-24, 24)
            cur = on_shell(min(t, 0.86), a)
            segs.append((prev, cur))
            if rnd.random() < 0.4:  # little side branch
                b = a + rnd.choice((-1, 1)) * rnd.uniform(18, 32)
                segs.append((cur, on_shell(min(t + 0.07, 0.86), b)))
            prev = cur
    return segs


def lines(segs, width):
    S = [(np.array(a), np.array(b)) for a, b in segs]

    def f(P):
        m = np.zeros(len(P), bool)
        for a, b in S:
            ab = b - a
            k = np.clip((P - a) @ ab / (ab @ ab), 0, 1)
            d = P - (a + k[:, None] * ab)
            m |= np.sum(d * d, axis=1) < width * width
        return m
    return f


def stars(points, grow=0.0):
    """Little 4-point stars painted on the shell. points: (t, ang, size)."""
    data = []
    for t, a, s in points:
        c = on_shell(t, a)
        n = c.normalized()
        side = Vector((0, 0, 1)).cross(n).normalized()
        vert = n.cross(side).normalized()
        data.append((np.array(c), np.array(side), np.array(vert), s + grow))

    def f(P):
        m = np.zeros(len(P), bool)
        for c, side, vert, s in data:
            d = P - c
            u, v = np.abs(d @ side), np.abs(d @ vert)
            m |= (np.sqrt(u) + np.sqrt(v) < math.sqrt(s)) & (np.sum(d * d, axis=1) < (2 * s) ** 2)
        return m
    return f


def shine():
    """A soft oval highlight on the upper front-left, so the egg reads as round and glossy."""
    c = np.array(on_shell(0.74, -130))

    def f(P):
        d = P - c
        return (d[:, 0] ** 2 + d[:, 1] ** 2) / 0.022 + d[:, 2] ** 2 / 0.06 < 1
    return f


def paint_shell(base, layers):
    """RGB array (TH, TW, 3) of the shell texture. layers: [(colour hex, pattern), ...]."""
    w, h = TW * SS, TH * SS
    u = (np.arange(w) + 0.5) / w
    v = (np.arange(h) + 0.5) / h
    U, V = np.meshgrid(u, v)
    phi = (V - 0.5) * math.pi
    tt = np.sin(phi)
    r = R * np.cos(phi) * taper_k(tt)
    ang = U * 2 * math.pi
    P = np.stack([np.cos(ang) * r, np.sin(ang) * r, H / 2 * (1 + tt)], axis=-1).reshape(-1, 3)
    img = np.tile(np.array(hex_rgb(base)), (len(P), 1))
    for col, fn in layers:
        img[fn(P)] = hex_rgb(col)
    img = img.reshape(h, w, 3)
    # average the supersamples so edges are smooth
    return img.reshape(TH, SS, TW, SS, 3).mean(axis=(1, 3))


# ----------------------------------------------------------------- asset

class EggAsset(Asset):
    """An Asset whose image holds the painted shell texture above the palette swatches."""

    def __init__(self, name):
        super().__init__(name, "egg")
        self.shell_rgb = None
        self.shell_obj = None

    def export(self, out_dir):
        shell_rgb = self.shell_rgb
        for p in self.parts.values():
            for v in p["obj"].data.vertices:
                v.co *= SCALE
        orig = lib.build_palette_image

        def build(name, colors):
            pal = orig(name + "_p", colors)
            n = pal.size[0]
            pp = np.array(pal.pixels[:]).reshape(n, n, 4)
            img = bpy.data.images.new(f"{name}_tex", IMG_W, IMG_H, alpha=False)
            px = np.ones((IMG_H, IMG_W, 4))
            # palette strip: 8 px swatches in the bottom-left PAL x PAL square
            big = np.repeat(np.repeat(pp, PAL // n, axis=0), PAL // n, axis=1)
            px[:PAL, :PAL] = big
            px[:PAL, PAL:, :3] = 1.0
            px[PAL:, :, :3] = shell_rgb
            img.pixels = px.reshape(-1).tolist()
            img.pack()
            return img
        lib.build_palette_image = build
        try:
            return super().export(out_dir)
        finally:
            lib.build_palette_image = orig


def remap_palette_uvs(obj):
    """Palette UVs (0..1 of the swatch grid) -> the PAL square at the bottom-left."""
    for loop in obj.data.uv_layers.active.data:
        u, v = loop.uv
        loop.uv = (u * PAL / IMG_W, v * PAL / IMG_H)


def set_shell_uvs(obj):
    me = obj.data
    uv = me.uv_layers.active.data
    sh = TH / IMG_H
    for poly in me.polygons:
        coords = [shell_uv(*me.vertices[me.loops[li].vertex_index].co) for li in poly.loop_indices]
        us = [c[0] for c in coords]
        # faces across the seam: keep their u values together
        if max(us) - min(us) > 0.5:
            coords = [(c[0] + 1.0 if c[0] < 0.5 else c[0], c[1]) for c in coords]
        # pole vertices: use the face's other u values
        for k, li in enumerate(poly.loop_indices):
            co = me.vertices[me.loops[li].vertex_index].co
            u, v = coords[k]
            if abs(co.x) < 1e-6 and abs(co.y) < 1e-6:
                others = [c[0] for j, c in enumerate(coords) if j != k]
                u = sum(others) / max(1, len(others))
            uv[li].uv = (u, PAL / IMG_H + v * sh)


def star_mesh(col, loc, R1=0.36, R2=0.17, depth=0.16):
    """A chubby 5-point star standing up, facing the front."""
    pts = []
    for k in range(10):
        ang = math.radians(90 + k * 36)
        rr = R1 if k % 2 == 0 else R2
        pts.append((math.cos(ang) * rr, math.sin(ang) * rr))
    bm = bmesh.new()
    front = [bm.verts.new((x, -depth / 2, z)) for x, z in pts]
    back = [bm.verts.new((x, depth / 2, z)) for x, z in pts]
    cf = bm.verts.new((0, -depth / 2 - 0.05, 0))
    cb = bm.verts.new((0, depth / 2 + 0.05, 0))
    for i in range(10):
        j = (i + 1) % 10
        bm.faces.new((front[i], front[j], cf))
        bm.faces.new((back[j], back[i], cb))
        bm.faces.new((front[j], front[i], back[i], back[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("Star")
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new("Star", mesh)
    bpy.context.collection.objects.link(o)
    return lib._finish(o, col, False, loc)


def egg(name, base, layers=(), glow=None, topper=None, accent=None, highlight=True):
    """layers: [(colour hex, pattern), ...] painted on the shell in order."""
    a = EggAsset(f"Egg_{name}")
    use(a)
    body = shell(base)
    layers = list(layers) + ([(shade(base, 0.5), shine())] if highlight else [])
    a.shell_rgb = paint_shell(base, layers)
    a.shell_obj = body

    pieces, gp = [], []
    top = H
    if topper == "sprout":
        pieces.append(cyl("6B4A2E", loc=(0, 0, top + 0.08), r=0.075, h=0.36, verts=10))
        for x in (-1, 1):
            pieces.append(sphere(accent, loc=(x * 0.21, 0, top + 0.3), scale=(0.24, 0.12, 0.05),
                                 rot=(0, x * -28, 0), seg=16, rings=8))
    elif topper == "crystals":
        for (x, y, h, rx, ry) in ((0, 0, 0.66, 0, 0), (0.2, 0.05, 0.42, 0, 24), (-0.19, -0.06, 0.46, 0, -22),
                                  (0.02, 0.2, 0.36, -22, 0), (0.0, -0.21, 0.32, 22, 0)):
            gp.append(cone(accent, loc=(x, y, top + h / 2 - 0.14), r=0.12, h=h, verts=6, rot=(rx, ry, 0), smooth=False))
    elif topper == "crown":
        t_c = 0.93
        rc = radius_at(t_c)
        z = H * t_c
        pieces.append(cyl(accent, loc=(0, 0, z + 0.07), r=rc + 0.04, h=0.18, verts=32))
        for k in range(5):
            ang = math.radians(k * 72 - 90)
            pieces.append(cone(accent, loc=(math.cos(ang) * rc, math.sin(ang) * rc, z + 0.27), r=0.11, h=0.28, verts=4, smooth=False))
            gp.append(sphere("FFFFFF", loc=(math.cos(ang) * rc, math.sin(ang) * rc, z + 0.43), scale=0.065, seg=10, rings=6))
        gp.append(sphere("FF4F7B", loc=(0, -(rc + 0.04), z + 0.07), scale=(0.08, 0.04, 0.08), seg=12, rings=6))
    elif topper == "horns":
        for x in (-1, 1):
            b = on_shell(0.84, 90 + x * 90, out=0.88)
            pieces.append(tube(accent, [tuple(b), (b.x * 1.3, 0, b.z + 0.25), (b.x * 1.5, 0, b.z + 0.55)],
                               lambda i: 0.12 - i * 0.04, seg=10))
    elif topper == "star":
        gp.append(star_mesh(accent, (0, 0, top + 0.24)))

    for o in pieces + gp:
        remap_palette_uvs(o)
    set_shell_uvs(body)
    a.part("Body", [body] + pieces)
    if gp:
        a.part("Body_Glow", gp, parent="Body", glow=glow or accent or "FFFFFF")
    return a


# ----------------------------------------------------------------- brick eggs
# Every egg is a mosaic of small Lego bricks: shapes are voxelised into little cubes and
# only their outside faces are kept, so outlines step like a brick build. Every face
# shows a brick tile with a stud from an atlas (painted, so the mesh stays light).
# Bricks in a glow colour go into a separate *_Glow part (Neon in game).

TILE = 64          # px per brick tile in the atlas
TILES_X = TW // TILE
BRICK = 0.11       # shell brick size (pre-scale)


def brick_tile(hexcol):
    """A TILE x TILE brick face: soft bevel and a round stud lit from the top-left."""
    base = np.array(hex_rgb(hexcol))
    n = TILE
    y, x = np.mgrid[0:n, 0:n]
    u, v = (x + 0.5) / n, (y + 0.5) / n          # v up (image rows go bottom to top)
    img = np.tile(base, (n, n, 1)).astype(float)
    light, dark = np.minimum(1, base * 0.55 + 0.45), base * 0.62
    e = 0.07
    img[(v > 1 - e)] = light
    img[(u < e) & (v > e)] = light * 0.5 + base * 0.5
    img[(v < e)] = dark
    img[(u > 1 - e) & (v < 1 - e)] = dark * 0.5 + base * 0.5
    cx, cy, r = 0.5, 0.5, 0.27
    img[np.hypot(u - cx - 0.05, v - cy + 0.06) < r] = base * 0.72
    d = np.hypot(u - cx, v - cy)
    img[d < r] = base
    img[(d < r) & (np.hypot(u - cx + 0.06, v - cy - 0.07) > r * 0.92)] = np.minimum(1, base * 0.8 + 0.2)
    img[(d < r) & (np.hypot(u - cx - 0.03, v - cy + 0.035) > r)] = base * 0.85
    img[(d < r * 0.42) & (np.hypot(u - cx + 0.09, v - cy - 0.09) < r * 0.2)] = np.minimum(1, base * 0.6 + 0.4)
    return img


class BrickEgg(EggAsset):
    """An egg asset whose image is a brick-tile atlas (one tile per colour) above the
    palette strip."""

    def __init__(self, name):
        super().__init__(name)
        self.bricks = []
        self.anim = {}       # part -> motion spec for the idle loop
        self.swatch("FFFFFF")

    def tile(self, hexcol):
        hexcol = hexcol.upper()
        if hexcol not in self.bricks:
            self.bricks.append(hexcol)
        return self.bricks.index(hexcol)

    def export(self, out_dir):
        atlas = np.ones((TH, TW, 3))
        for ci, col in enumerate(self.bricks):
            tx, ty = ci % TILES_X, ci // TILES_X
            atlas[ty * TILE:(ty + 1) * TILE, tx * TILE:(tx + 1) * TILE] = brick_tile(col)
        self.shell_rgb = atlas
        return super().export(out_dir)


class Vox:
    """A brick grid with its own frame: cell (i, j, k) has its centre at
    origin + X * (i + .5) * size + Y * (j + .5) * size + Z * (k + .5) * size."""

    def __init__(self, size, origin=(0, 0, 0), X=(1, 0, 0), Y=(0, 1, 0), Z=(0, 0, 1)):
        self.size = size
        self.origin = Vector(origin)
        self.X, self.Y, self.Z = Vector(X).normalized(), Vector(Y).normalized(), Vector(Z).normalized()
        self.cells = {}

    def local(self, c):
        return Vector(((c[0] + 0.5) * self.size, (c[1] + 0.5) * self.size, (c[2] + 0.5) * self.size))

    def world(self, c):
        lp = self.local(c)
        return self.origin + self.X * lp.x + self.Y * lp.y + self.Z * lp.z

    def fill(self, lo, hi, colour_of):
        """colour_of(local point, world point) -> hex or None, over the local box lo..hi."""
        s = self.size
        for i in range(math.floor(lo[0] / s), math.ceil(hi[0] / s)):
            for j in range(math.floor(lo[1] / s), math.ceil(hi[1] / s)):
                for k in range(math.floor(lo[2] / s), math.ceil(hi[2] / s)):
                    c = (i, j, k)
                    col = colour_of(self.local(c), self.world(c))
                    if col:
                        self.cells[c] = col.upper()
        return self

    def mesh(self, a, name, keep=None):
        """Mesh of the outside faces of the cells for which keep(colour) is true (all by
        default); hidden faces between any two filled cells are left out."""
        s = self.size
        dirs = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]
        bm = bmesh.new()
        uvl = bm.loops.layers.uv.new("UVMap")
        sh = TH / IMG_H
        pad = 1.5 / TILE
        corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
        count = 0
        for c, col in self.cells.items():
            if keep and not keep(col):
                continue
            centre = self.world(c)
            ci = a.tile(col)
            tx, ty = ci % TILES_X, ci // TILES_X
            for d in dirs:
                if (c[0] + d[0], c[1] + d[1], c[2] + d[2]) in self.cells:
                    continue
                n = self.X * d[0] + self.Y * d[1] + self.Z * d[2]
                vdir = self.Z if d[2] == 0 else self.Y
                udir = vdir.cross(n)
                fc = centre + n * s / 2
                verts = [bm.verts.new(fc + (udir * cu + vdir * cv) * s / 2) for cu, cv in corners]
                f = bm.faces.new(verts)
                for loop, (cu, cv) in zip(f.loops, corners):
                    uu = (tx + (pad if cu < 0 else 1 - pad)) * TILE / TW
                    vv = (ty + (pad if cv < 0 else 1 - pad)) * TILE / TH
                    loop[uvl].uv = (uu, PAL / IMG_H + vv * sh)
                count += 1
        if not count:
            bm.free()
            return None
        mesh = bpy.data.meshes.new(name)
        bm.to_mesh(mesh)
        bm.free()
        for poly in mesh.polygons:
            poly.use_smooth = False
        o = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(o)
        return o


def egg_shell(colour_of, size=BRICK):
    """The egg itself as bricks. colour_of(world point, t, angle) -> hex."""
    v = Vox(size)

    def f(lp, wp):
        t = wp.z / H
        if not 0 <= t <= 1:
            return None
        rr = radius_at(t)
        if wp.x * wp.x + wp.y * wp.y > rr * rr:
            return None
        return colour_of(wp, t, math.degrees(math.atan2(wp.y, wp.x)))
    nxy = R + size
    return v.fill((-nxy, -nxy, 0), (nxy, nxy, H), f)


def blob(size, centre, radius, colour, glow_frac=0.0, seed=0):
    """A round little chunk of bricks."""
    rnd = random.Random(seed)
    v = Vox(size, origin=Vector(centre) - Vector((radius, radius, radius)))

    def f(lp, wp):
        if (wp - Vector(centre)).length > radius:
            return None
        return colour
    return v.fill((0, 0, 0), (2 * radius, 2 * radius, 2 * radius), f)


def brick_ring(size, centre, R_, r, colours, tilt=(0, 0, 0)):
    """A ring of bricks (torus) tilted by `tilt` degrees. colours: list cycled by angle."""
    from mathutils import Euler
    rot = Euler([math.radians(t) for t in tilt]).to_matrix()
    X, Y, Z = rot @ Vector((1, 0, 0)), rot @ Vector((0, 1, 0)), rot @ Vector((0, 0, 1))
    ext = R_ + r + size
    origin = Vector(centre) - X * ext - Y * ext - Z * (r + size)
    v = Vox(size, origin, X, Y, Z)

    def f(lp, wp):
        x, y, z = lp.x - ext, lp.y - ext, lp.z - (r + size)
        q = math.hypot(x, y) - R_
        if q * q + z * z > r * r:
            return None
        ang = (math.degrees(math.atan2(y, x)) + 360) % 360
        return colours[int(ang / 360 * len(colours) * 3) % len(colours)]
    return v.fill((0, 0, 0), (2 * ext, 2 * ext, 2 * (r + size)), f)


def _seg_dist(p, a, b):
    ab = b - a
    k = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (p - (a + ab * k)).length, k


def brick_wing(a, side, shoulder, name):
    """A thick feathered wing of small bricks: a rounded root, six feathers fanning up and
    out (thinner towards the tips) and a gold leading edge. Returns the mesh object."""
    s = side
    sweep = math.radians(18)
    out = Vector((s * math.cos(sweep), math.sin(sweep), 0))
    up = Vector((0, 0, 1))
    nrm = up.cross(out)
    size = 0.085
    span = 2.0
    v = Vox(size, origin=shoulder - nrm * 0.3, X=out, Y=nrm, Z=up)
    feathers = [(8, 1.25), (22, 1.6), (36, 1.85), (50, 1.9), (64, 1.7), (78, 1.35), (90, 0.95)]
    segs = []
    for elev, L in feathers:
        e = math.radians(elev)
        segs.append((Vector((0, 0, 0)), Vector((math.cos(e) * L, 0, math.sin(e) * L)), L))
    arm = (Vector((0, 0, 0)), Vector((math.cos(math.radians(50)) * 1.2, 0, math.sin(math.radians(50)) * 1.2)))

    def f(lp, wp):
        p = Vector((lp.x, lp.y - 0.3, lp.z))   # back to shoulder-relative (y = across the wing)
        dist = Vector((p.x, 0, p.z)).length
        # gold arm along the leading edge, a bit in front of the feathers
        da, ka = _seg_dist(Vector((p.x, p.y + 0.2, p.z)), arm[0], arm[1])
        if da < 0.12 - 0.05 * ka:
            return GOLD
        inside = dist < 0.42
        for a0, b0, L in segs:
            d, k = _seg_dist(Vector((p.x, 0, p.z)), a0, b0)
            if d < 0.17 * (1 - 0.6 * k) + 0.03:
                inside = True
                break
        if not inside:
            return None
        # thickness: chunky at the root, thin at the tips
        half = 0.2 * (1 - 0.6 * min(1, dist / 1.9)) + 0.04
        if abs(p.y) > half:
            return None
        if dist < 0.42:
            return "A7E9DA"
        if dist < 1.05:
            return "D4F5EC"
        return "F6FBFF"
    v.fill((-0.3, 0, -0.5), (span, 0.6, span), f)
    return v.mesh(a, name)


# ----------------------------------------------------------------- shared egg build

def build(a, shell_vox, glow_colours=(), extra=()):
    """Turns the shell (and any other Body voxels) into Body and Body_Glow parts.
    extra: more Vox grids that belong to the body (horns, sprout stems...)."""
    glow_colours = {c.upper() for c in glow_colours}
    body, glow = [], []
    for v in [shell_vox] + list(extra):
        body.append(v.mesh(a, "b", keep=lambda c: c not in glow_colours))
        glow.append(v.mesh(a, "g", keep=lambda c: c in glow_colours))
    a.part("Body", [o for o in body if o])
    gl = [o for o in glow if o]
    if gl:
        glow_col = next(iter(glow_colours))
        a.part("Body_Glow", gl, parent="Body", glow=glow_col)


def moving(a, name, objs, joint, motion, glow=None):
    """A part that moves in the idle loop: joint (pre-scale) and motion spec."""
    objs = [o for o in objs if o]
    a.part(name, objs, parent="Body", joint=tuple(Vector(joint) * SCALE), glow=glow)
    a.anim[name] = dict(motion, joint=Vector(joint))


def finish(a, name):
    if a.anim:
        a.extra["rig"] = True
        a.extra["anim"] = f"Egg_{name}Idle"
    return a


def noise_pick(seed):
    import mathutils.noise as N
    off = Vector((seed * 3.1, seed * 7.7, seed * 1.3))
    return lambda p, f=1.6: N.noise(p * f + off)


# ----------------------------------------------------------------- the seven eggs

def common():
    """Plain cream bricks with a few brown speckle bricks. No extras: it's the common one."""
    a = BrickEgg("Egg_Common")
    use(a)
    rnd = random.Random("common")

    def col(p, t, ang):
        return "B98B5E" if rnd.random() < 0.06 else ("FFF4DE" if rnd.random() < 0.8 else "F2E4C6")
    build(a, egg_shell(col))
    return finish(a, "Common")


def uncommon():
    """Green bricks with a white zigzag band and a brick sprout that sways."""
    a = BrickEgg("Egg_Uncommon")
    use(a)
    rnd = random.Random("unc")

    def col(p, t, ang):
        zz = 0.47 + 0.09 * (_tri(ang / 360 * 8) - 0.5)
        if abs(t - zz) < 0.045:
            return "FFFFFF"
        if abs(t - zz) < 0.085:
            return "3E9E46"
        return "6CC85E" if rnd.random() < 0.25 else "8FDF7A"
    build(a, egg_shell(col))
    top = Vector((0, 0, H - 0.08))
    s = 0.09
    stem = Vox(s, origin=top - Vector((s / 2, s / 2, 0))).fill((0, 0, 0), (s, s, 0.4),
                                                               lambda lp, wp: "7A5232")
    leaves = []
    for x in (-1, 1):
        c = top + Vector((x * 0.26, 0, 0.36))
        lv = Vox(s, origin=c - Vector((0.3, 0.3, 0.3)))
        lv.fill((0, 0, 0), (0.6, 0.6, 0.6),
                lambda lp, wp, c=c, x=x: ("3FA55A" if (((wp.x - c.x) / 0.27) ** 2 + ((wp.y - c.y) / 0.12) ** 2 +
                                                       ((wp.z - c.z - x * 0.0 - (wp.x - c.x) * x * 0.45) / 0.09) ** 2) < 1 else None))
        leaves.append(lv)
    moving(a, "Sprout", [stem.mesh(a, "stem")] + [lv.mesh(a, "leaf") for lv in leaves], top,
           {"sway": 9, "cycles": 2})
    return finish(a, "Uncommon")


def rare():
    """Sky-blue bricks with white spot bricks, a blue zigzag and a turning ring of bricks."""
    a = BrickEgg("Egg_Rare")
    use(a)
    spots_ = [on_shell(t, ang) for t, ang, r in scatter("rare", 12, 0.12, 0.16, 0.1, 0.88, avoid=[(0.42, 0.6)])]
    rnd = random.Random("rare")

    def col(p, t, ang):
        zz = 0.51 + 0.1 * (_tri(ang / 360 * 9) - 0.5)
        if abs(t - zz) < 0.05:
            return "4E8EF0"
        if abs(t - zz) < 0.085:
            return "2F66C8"
        if any((p - c).length < 0.17 for c in spots_):
            return "FFFFFF"
        return "6FB2FF" if rnd.random() < 0.2 else "7DBDFF"
    build(a, egg_shell(col))
    centre = Vector((0, 0, H * 0.5))
    ringv = brick_ring(0.09, centre, 1.55, 0.09, ["FFFFFF", "BFE0FF"], tilt=(14, 0, 0))
    moving(a, "RingA", [ringv.mesh(a, "ring")], centre, {"spin": 1})
    return finish(a, "Rare")


def epic():
    """Purple swirl bricks with glowing brick crystals growing out of the top."""
    a = BrickEgg("Egg_Epic")
    use(a)
    rnd = random.Random("epic")
    glow = "F3BFFF"

    def col(p, t, ang):
        x = (ang / 360 + t * 1.1) * 5
        if (x % 1.0) < 0.38:
            return "C891FF"
        return glow if rnd.random() < 0.03 else "A66BFF"
    build(a, egg_shell(col), glow_colours=[glow])
    top = Vector((0, 0, H - 0.18))
    crystals = []
    for (x, y, h, lean) in ((0, 0, 0.8, (0, 0)), (0.22, 0.05, 0.5, (0.35, 0.1)), (-0.2, -0.06, 0.55, (-0.35, -0.1)),
                            (0.02, 0.22, 0.42, (0.05, 0.35)), (0.0, -0.22, 0.38, (0, -0.35))):
        base = top + Vector((x, y, 0))
        tip = base + Vector((lean[0] * h, lean[1] * h, h))
        cv = Vox(0.08, origin=base - Vector((0.4, 0.4, 0)))

        def f(lp, wp, base=base, tip=tip, h=h):
            d, k = _seg_dist(wp, base, tip)
            return (glow if k > 0.5 else "D59CFF") if d < 0.13 * (1 - 0.8 * k) + 0.02 else None
        cv.fill((0, 0, 0), (0.8, 0.8, h + 0.1), f)
        crystals.append(cv.mesh(a, "crystal"))
    moving(a, "Crystals", crystals, top, {"bob": 0.08, "spin": 1}, glow=glow)
    return finish(a, "Epic")


def legendary():
    """Gold bricks with a white wavy band and red gem bricks, a floating brick crown and a
    turning gold-and-white brick ring."""
    a = BrickEgg("Egg_Legendary")
    use(a)
    rnd = random.Random("leg")

    def col(p, t, ang):
        wv = 0.42 + 0.045 * math.sin(math.radians(ang) * 6)
        if abs(t - wv) < 0.045:
            return "FF4F7B" if (ang % 60) < 8 else "FFFFFF"
        if abs(t - wv) < 0.09:
            return "D98A12"
        if t > 0.78:
            return "FFE58C"
        return "FFD24D" if rnd.random() < 0.25 else "FFC93A"
    build(a, egg_shell(col))
    cc = Vector((0, 0, H + 0.12))
    crown = Vox(0.08, origin=cc - Vector((0.5, 0.5, 0)))

    def fcrown(lp, wp):
        x, y, z = wp.x - cc.x, wp.y - cc.y, wp.z - cc.z
        r = math.hypot(x, y)
        ang = math.degrees(math.atan2(y, x)) % 72
        spike = 0.18 + 0.22 * max(0.0, 1 - abs(ang - 36) / 18)
        if 0.3 < r < 0.42 and z < spike:
            if z > spike - 0.09 and spike > 0.3:
                return "FFFFFF"
            if 0.05 < z < 0.13 and abs(ang - 36) < 8:
                return "FF4F7B"
            return "FFC83A"
        return None
    crown.fill((0, 0, 0), (1.0, 1.0, 0.5), fcrown)
    moving(a, "Crown", [crown.mesh(a, "crown")], cc, {"bob": 0.1, "spin": 1})
    centre = Vector((0, 0, H * 0.48))
    ringv = brick_ring(0.09, centre, 1.6, 0.09, ["FFC83A", "FFFFFF"], tilt=(-12, 10, 0))
    moving(a, "RingA", [ringv.mesh(a, "ring")], centre, {"spin": -1})
    return finish(a, "Legendary")


def mythic():
    """Dark bricks with glowing lava cracks, bone horns, and glowing lava chunks orbiting."""
    a = BrickEgg("Egg_Mythic")
    use(a)
    rnd = random.Random("myth")
    lava = "FF7A3C"
    segs = crack_paths("mythic")

    def col(p, t, ang):
        if any(_seg_dist(p, s0, s1)[0] < 0.06 for s0, s1 in segs):
            return lava
        if t > 0.78:
            return "57304D"
        return "45283D" if rnd.random() < 0.25 else "3B2034"
    shell = egg_shell(col)
    horns = []
    for x in (-1, 1):
        b = on_shell(0.84, 90 + x * 90, out=0.85)
        pts = [b, Vector((b.x * 1.3, 0, b.z + 0.28)), Vector((b.x * 1.5, 0, b.z + 0.6))]
        hv = Vox(0.08, origin=b - Vector((0.6, 0.6, 0.2)))

        def f(lp, wp, pts=pts):
            for i in range(2):
                d, k = _seg_dist(wp, pts[i], pts[i + 1])
                tt = (i + k) / 2
                if d < 0.16 * (1 - 0.75 * tt) + 0.03:
                    return "F0E2C8" if tt < 0.7 else "C9B48E"
            return None
        horns.append(hv.fill((0, 0, 0), (1.2, 1.2, 1.2), f))
    build(a, shell, glow_colours=[lava], extra=horns)
    centre = Vector((0, 0, H * 0.45))
    chunks = []
    for i in range(3):
        ang = math.radians(i * 120 + 15)
        c = centre + Vector((math.cos(ang) * 1.55, math.sin(ang) * 1.55, (i - 1) * 0.35))
        chunks.append(blob(0.09, c, 0.22, lava).mesh(a, "chunk"))
    moving(a, "Orbit", chunks, centre, {"spin": 1, "bob": 0.12}, glow=lava)
    return finish(a, "Mythic")


# ----------------------------------------------------------------- celestial extras (Cosmic)

GOLD, GOLD_DARK = "FFC83A", "E09A1C"


def _mesh_obj(name, bm, col, smooth=True):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(o)
    return lib._finish(o, col, smooth)


def _pal(objs):
    """Point palette-painted pieces at the palette strip (the brick atlas fills the rest)."""
    for o in objs:
        remap_palette_uvs(o)
    return objs


def bar(col, pts, r, sides=6, smooth=True, closed=False):
    """A tube swept along pts (list of Vectors), capped unless closed."""
    pts = [Vector(p) for p in pts]
    bm = bmesh.new()
    rings = []
    a = None
    n = len(pts)
    for i, p in enumerate(pts):
        if closed:
            d = (pts[(i + 1) % n] - pts[(i - 1) % n]).normalized()
        else:
            d = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
        a = d.orthogonal().normalized() if a is None else (a - d * a.dot(d)).normalized()
        b = d.cross(a).normalized()
        rings.append([bm.verts.new(p + (a * math.cos(k * 2 * math.pi / sides) + b * math.sin(k * 2 * math.pi / sides)) * r)
                      for k in range(sides)])
    if closed:
        rings.append(rings[0])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(sides):
            bm.faces.new((r0[k], r0[(k + 1) % sides], r1[(k + 1) % sides], r1[k]))
    if not closed:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _mesh_obj("bar", bm, col, smooth)


def ring(col, centre, R_, r, tilt=(0, 0, 0), seg=48, sides=6):
    from mathutils import Euler
    rot = Euler([math.radians(t) for t in tilt]).to_matrix()
    pts = [Vector(centre) + rot @ Vector((math.cos(k * 2 * math.pi / seg) * R_, math.sin(k * 2 * math.pi / seg) * R_, 0))
           for k in range(seg)]
    return bar(col, pts, r, sides, closed=True)


def diamond(col, centre, along, side, L, W, T, smooth=False):
    """A flat crystal diamond (bipyramid) from centre along `along`."""
    along, side = Vector(along).normalized(), Vector(side).normalized()
    nrm = along.cross(side).normalized()
    c = Vector(centre)
    bm = bmesh.new()
    tip0 = bm.verts.new(c)
    tip1 = bm.verts.new(c + along * L)
    mid = c + along * L * 0.4
    sv = [bm.verts.new(mid + side * W / 2), bm.verts.new(mid + nrm * T / 2),
          bm.verts.new(mid - side * W / 2), bm.verts.new(mid - nrm * T / 2)]
    for k in range(4):
        bm.faces.new((tip0, sv[k], sv[(k + 1) % 4]))
        bm.faces.new((tip1, sv[(k + 1) % 4], sv[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return _mesh_obj("diamond", bm, col, smooth)


def cage_pt(t, ang, off=0.1):
    p = on_shell(t, ang)
    r = math.hypot(p.x, p.y)
    k = (r + off) / max(r, 1e-6)
    return Vector((p.x * k, p.y * k, p.z))


def cage_path(t0, a0, t1, a1, n=10, off=0.1):
    return [cage_pt(t0 + (t1 - t0) * i / n, a0 + (a1 - a0) * i / n, off) for i in range(n + 1)]


def cosmic():
    """Blue brick mosaic in a gold cage, with thick brick wings, a brick halo and glowing
    rings."""
    a = BrickEgg("Egg_Cosmic")
    use(a)
    pick = noise_pick(1)
    rnd = random.Random("cosmic-bricks")
    blues = ["2F5FD8", "3B72EA", "4A84F2"]

    def col(p, t, ang):
        nv = pick(p)
        r = rnd.random()
        if r < 0.05:
            return "F4F7FF"
        if r < 0.10:
            return "E7A8F2"
        if r < 0.14:
            return "B49CF6"
        if nv > 0.32:
            return "8FB8FF"
        if nv < -0.35:
            return "2448B8"
        return blues[min(2, int(rnd.random() * 2 + t * 1.4))]
    shell = egg_shell(col)
    body = shell.mesh(a, "shell")

    gold = []
    for m in (-60, -120, 0, 180, 60, 120):
        gold.append(bar(GOLD, cage_path(0.07, m, 0.93, m, n=16), 0.04))
    gold.append(ring(GOLD, (0, 0, H * 0.93), radius_at(0.93) + 0.1, 0.045))
    gold.append(ring(GOLD, (0, 0, H * 0.07), radius_at(0.07) + 0.1, 0.045))
    for a0 in range(0, 360, 60):
        mid = a0 + 30
        top, bot, left, right = (0.82, mid), (0.18, mid), (0.5, a0), (0.5, a0 + 60)
        for p0, p1 in ((bot, left), (left, top), (top, right), (right, bot)):
            gold.append(bar(GOLD, cage_path(p0[0], p0[1], p1[0], p1[1], n=8), 0.032))
        for t, ang in (top, bot, left, right):
            gold.append(sphere(GOLD_DARK, loc=tuple(cage_pt(t, ang, 0.1)), scale=0.065, seg=10, rings=6))
    a.part("Body", [body] + _pal(gold))
    c = cage_pt(0.5, -90, 0.06)
    a.part("Gem", _pal([diamond("9FF7FF", c - Vector((0, 0, 0.45)), (0, 0, 1), (1, 0, 0), 0.9, 0.5, 0.24)]),
           parent="Body", glow="A8FFF6")

    for side, name in ((1, "WingL"), (-1, "WingR")):   # Blender +X is Roblox's left
        shoulder = Vector((side * (R + 0.04), 0.12, H * 0.6))
        moving(a, name, [brick_wing(a, side, shoulder, name)], shoulder, {"flap": side})
    hc = Vector((0, 0, H + 0.45))
    halo = brick_ring(0.07, hc, 0.42, 0.07, ["FFC83A", "FFE07A"], tilt=(12, 0, 0))
    moving(a, "Halo", [halo.mesh(a, "halo")], hc, {"bob": 0.09, "spin": 1})
    centre = Vector((0, 0, H * 0.5))
    moving(a, "RingA", _pal([ring("4FF0D0", centre, 1.8, 0.03, tilt=(0, 18, 0))]), centre, {"spin": 1}, glow="4FF0D0")
    moving(a, "RingB", _pal([ring("FF8AE6", centre + Vector((0, 0, 0.15)), 1.55, 0.025, tilt=(10, -16, 0))]), centre,
           {"spin": -1}, glow="FF8AE6")
    a.part("RingBase", _pal([ring("4FF0D0", (0, 0, 0.04), 1.55, 0.045)]), parent="Body", glow="4FF0D0")
    return finish(a, "Cosmic")


# ----------------------------------------------------------------- idle animation
# Keyframed in Blender on empties at each moving part's joint (open the saved .blend to
# see or tweak it), then sampled into a Roblox KeyframeSequence.

ANIM_LEN = 5.0       # seconds, loops
FPS = 24


def keyframe_idle(anim):
    """anim: {part: {"joint": Vector, and any of: "flap": side, "sway": degrees,
    "spin": turns, "bob": studs, "cycles": n}}. Returns {part: empty}."""
    scn = bpy.context.scene
    scn.render.fps = FPS
    end = int(ANIM_LEN * FPS)
    scn.frame_start, scn.frame_end = 0, end
    empties = {}
    for name, m in anim.items():
        e = bpy.data.objects.new(f"Joint_{name}", None)
        e.location = m["joint"]
        e.rotation_mode = "XYZ"
        bpy.context.collection.objects.link(e)
        empties[name] = e
        cyc = m.get("cycles", 2 if "flap" in m else 1)
        steps = cyc * 4
        for i in range(steps + 1):
            f = round(end * i / steps)
            w = 2 * math.pi * cyc * i / steps
            if "flap" in m:
                sd = m["flap"]
                # slow up-down swing about the front-back axis, with a little forward sweep
                e.rotation_euler = (0, math.radians(-sd * 16 * math.sin(w)), math.radians(sd * 6 * math.sin(w + 1.2)))
                e.keyframe_insert("rotation_euler", frame=f)
            if "sway" in m:
                e.rotation_euler[1] = math.radians(m["sway"] * math.sin(w))
                e.keyframe_insert("rotation_euler", frame=f, index=1)
            if "bob" in m:
                e.location = m["joint"] + Vector((0, 0, m["bob"] * math.sin(w)))
                e.keyframe_insert("location", frame=f)
        if "spin" in m:
            for i in range(5):
                e.rotation_euler[2] = m["spin"] * 2 * math.pi * i / 4
                e.keyframe_insert("rotation_euler", frame=round(end * i / 4), index=2)
        e.location = m["joint"]
        e.rotation_euler = (0, 0, 0)
        ad = e.animation_data
        for fc in _fcurves(ad.action) if ad and ad.action else []:
            linear = "spin" in m and fc.data_path == "rotation_euler" and fc.array_index == 2
            for kp in fc.keyframe_points:
                kp.interpolation = "LINEAR" if linear else "BEZIER"
    return empties


def _fcurves(action):
    if hasattr(action, "fcurves") and len(getattr(action, "fcurves", [])):
        return list(action.fcurves)
    out = []
    for layer in getattr(action, "layers", []):
        for strip in layer.strips:
            for bag in strip.channelbags:
                out += list(bag.fcurves)
    return out


def _to_roblox_matrix(m3):
    """Rotation in Blender axes -> Roblox axes (x, y, z) = (-x, z, y)."""
    from mathutils import Matrix
    P = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))
    r = P @ m3 @ P.inverted()
    return [[r[i][j] for j in range(3)] for i in range(3)]


def sample_idle(empties, name):
    """Samples the empties' motion into a KeyframeSequence (.rbxmx text)."""
    import sys
    import os
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "anim"))
    from build_anims import sequence
    scn = bpy.context.scene
    scn.frame_set(0)
    rest = {k: e.matrix_world.copy() for k, e in empties.items()}
    tree = {"RootPart": {"Body": {k: {} for k in empties}}}
    frames = []
    for f in range(0, int(ANIM_LEN * FPS) + 1, 2):   # 12 keyframes a second
        scn.frame_set(f)
        poses = {}
        for k, e in empties.items():
            d = e.matrix_world @ rest[k].inverted()
            j = rest[k].to_translation()
            rot = d.to_3x3()
            move = d.to_translation() + rot @ j - j
            move = Vector((-move.x, move.z, move.y)) * SCALE
            poses[k] = ((move.x, move.y, move.z), _to_roblox_matrix(rot))
        frames.append((f / FPS, poses))
    scn.frame_set(0)
    return sequence(name, frames, True, 0, tree)


EGGS = {
    "Common": common,
    "Uncommon": uncommon,
    "Rare": rare,
    "Epic": epic,
    "Legendary": legendary,
    "Mythic": mythic,
    "Cosmic": cosmic,
}
