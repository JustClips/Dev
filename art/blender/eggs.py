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


# ----------------------------------------------------------------- the seven eggs

def common():
    base = "FFF4DE"
    return egg("Common", base, [
        ("D7B184", spots(scatter("common", 16, 0.05, 0.12))),
    ])


def uncommon():
    base = "92E27C"
    pts = scatter("unc", 10, 0.08, 0.13, 0.1, 0.86, avoid=[(0.38, 0.56)])
    return egg("Uncommon", base, [
        ("5DBE58", spots(pts)),
        ("3E9E46", zigzag(0.47, 0.1, 8, 0.15)),
        ("FFFFFF", zigzag(0.47, 0.1, 8, 0.09)),
    ], topper="sprout", accent="3FA55A")


def rare():
    base = "7DBDFF"
    pts = scatter("rare", 12, 0.1, 0.17, 0.1, 0.88, avoid=[(0.42, 0.6)])
    return egg("Rare", base, [
        ("FFFFFF", spots(pts)),
        ("2F66C8", zigzag(0.51, 0.11, 9, 0.17)),
        ("4E8EF0", zigzag(0.51, 0.11, 9, 0.1)),
    ])


def epic():
    base = "A66BFF"
    pts = scatter("epic", 8, 0.05, 0.08, 0.15, 0.85)
    return egg("Epic", base, [
        ("C891FF", swirl(5, 0.38, twist=1.1, tmin=0.0, tmax=0.92)),
        ("FFFFFF", stars([(t, a, s * 1.4) for t, a, s in pts])),
    ], glow="F3BFFF", topper="crystals", accent="F3BFFF")


def legendary():
    base = "FFC93A"
    return egg("Legendary", base, [
        ("FFE58C", cap(0.76, wavy=0.025, waves=8)),
        ("D98A12", wave(0.42, 0.045, 6, 0.2)),
        ("FFFFFF", wave(0.42, 0.045, 6, 0.1)),
        ("FF4F7B", spots([(0.42 + 0.045 * math.sin(math.radians(a) * 6), a, 0.075) for a in range(15, 360, 60)])),
    ], glow="FFFFFF", topper="crown", accent="FFE070")


def mythic():
    base = "3B2034"
    segs = crack_paths("mythic")
    return egg("Mythic", base, [
        ("57304D", cap(0.78, wavy=0.03, waves=5)),
        ("B8321E", lines(segs, 0.075)),
        ("FF8A3C", lines(segs, 0.045)),
        ("FFE08A", lines(segs, 0.018)),
    ], glow="FF7A3C", topper="horns", accent="F0E2C8")


# ----------------------------------------------------------------- brick eggs
# An egg-shaped mosaic of small Lego bricks: the shell is voxelised into little cubes and
# only their outside faces are kept, so the outline steps like a brick build. Every face
# shows a brick tile with a stud (painted, so the mesh stays light).

TILE = 64          # px per brick tile in the atlas
TILES_X = TW // TILE


def brick_tile(hexcol):
    """A TILE x TILE brick face: soft bevel and a round stud lit from the top-left."""
    base = np.array(hex_rgb(hexcol))
    n = TILE
    y, x = np.mgrid[0:n, 0:n]
    u, v = (x + 0.5) / n, (y + 0.5) / n          # v up (image rows go bottom to top)
    img = np.tile(base, (n, n, 1)).astype(float)
    light, dark = np.minimum(1, base * 0.55 + 0.45), base * 0.62
    e = 0.07
    img[(v > 1 - e)] = light                      # top edge
    img[(u < e) & (v > e)] = light * 0.5 + base * 0.5
    img[(v < e)] = dark                           # bottom edge
    img[(u > 1 - e) & (v < 1 - e)] = dark * 0.5 + base * 0.5
    # stud: shadow, then the stud, then a light crescent
    cx, cy, r = 0.5, 0.5, 0.27
    d_sh = np.hypot(u - cx - 0.05, v - cy + 0.06)
    img[d_sh < r] = base * 0.72
    d = np.hypot(u - cx, v - cy)
    img[d < r] = base * 1.0
    img[(d < r) & (np.hypot(u - cx + 0.06, v - cy - 0.07) > r * 0.92)] = np.minimum(1, base * 0.8 + 0.2)
    img[(d < r) & (np.hypot(u - cx - 0.03, v - cy + 0.035) > r)] = base * 0.85
    img[(d < r * 0.42) & (np.hypot(u - cx + 0.09, v - cy - 0.09) < r * 0.2)] = np.minimum(1, base * 0.6 + 0.4)
    return img


def brick_shell(a, size, colour_of):
    """Voxel egg mesh. colour_of(Vector centre, (i, j, k)) -> hex. Returns (obj, atlas rgb)."""
    colors = []
    cells = {}
    nz = int(round(H / size))
    nxy = int(math.ceil(R / size)) + 1
    for k in range(nz):
        z = (k + 0.5) * size
        rr = radius_at(z / H)
        for i in range(-nxy, nxy):
            for j in range(-nxy, nxy):
                x, y = (i + 0.5) * size, (j + 0.5) * size
                if x * x + y * y <= rr * rr:
                    cells[(i, j, k)] = None
    for c in cells:
        i, j, k = c
        col = colour_of(Vector(((i + 0.5) * size, (j + 0.5) * size, (k + 0.5) * size)), c).upper()
        if col not in colors:
            colors.append(col)
        cells[c] = colors.index(col)

    dirs = [((1, 0, 0)), ((-1, 0, 0)), ((0, 1, 0)), ((0, -1, 0)), ((0, 0, 1)), ((0, 0, -1))]
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    sh = TH / IMG_H
    pad = 1.5 / TILE
    for (i, j, k), ci in cells.items():
        centre = Vector(((i + 0.5) * size, (j + 0.5) * size, (k + 0.5) * size))
        for d in dirs:
            if (i + d[0], j + d[1], k + d[2]) in cells:
                continue
            n = Vector(d)
            vdir = Vector((0, 0, 1)) if d[2] == 0 else Vector((0, 1, 0))
            udir = vdir.cross(n)
            fc = centre + n * size / 2
            corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
            verts = [bm.verts.new(fc + (udir * cu + vdir * cv) * size / 2) for cu, cv in corners]
            f = bm.faces.new(verts)
            tx, ty = ci % TILES_X, ci // TILES_X
            for loop, (cu, cv) in zip(f.loops, corners):
                uu = (tx + (pad if cu < 0 else 1 - pad)) * TILE / TW
                vv = (ty + (pad if cv < 0 else 1 - pad)) * TILE / TH
                loop[uvl].uv = (uu, PAL / IMG_H + vv * sh)
    mesh = bpy.data.meshes.new("Body")
    bm.to_mesh(mesh)
    bm.free()
    for poly in mesh.polygons:
        poly.use_smooth = False
    o = bpy.data.objects.new("Body", mesh)
    bpy.context.collection.objects.link(o)

    atlas = np.ones((TH, TW, 3))
    for ci, col in enumerate(colors):
        tx, ty = ci % TILES_X, ci // TILES_X
        atlas[ty * TILE:(ty + 1) * TILE, tx * TILE:(tx + 1) * TILE] = brick_tile(col)
    return o, atlas


def brick_egg(name, size, colour_of):
    a = EggAsset(f"Egg_{name}")
    use(a)
    body, atlas = brick_shell(a, size, colour_of)
    a.shell_rgb = atlas
    a.swatch("FFFFFF")  # palette strip needs one colour
    a.part("Body", [body])
    return a


def cosmic():
    """Blue brick mosaic with patches of light blue and sprinkles of pink, lilac and white."""
    import mathutils.noise as N
    rnd = random.Random("cosmic-bricks")
    blues = ["2F5FD8", "3B72EA", "4A84F2"]

    def colour_of(p, cell):
        t = p.z / H
        nv = N.noise(p * 1.6 + Vector((3.1, 7.7, 1.3)))
        r = rnd.random()
        if r < 0.05:
            return "F4F7FF"            # white
        if r < 0.10:
            return "E7A8F2"            # pink
        if r < 0.14:
            return "B49CF6"            # lilac
        if nv > 0.32:
            return "8FB8FF"            # light blue patches
        if nv < -0.35:
            return "2448B8"            # deep blue patches
        b = blues[min(2, int(rnd.random() * 2 + t * 1.4))]
        return b

    return brick_egg("Cosmic", 0.11, colour_of)


EGGS = {
    "Common": common,
    "Uncommon": uncommon,
    "Rare": rare,
    "Epic": epic,
    "Legendary": legendary,
    "Mythic": mythic,
    "Cosmic": cosmic,
}
