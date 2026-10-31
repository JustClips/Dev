"""Cartoon cash coin for the sell coins (CoinController), Dev 2026-10-31: "i want an actual
model".

Coin_Cash is a chunky gold coin about 1.6 studs across and 0.42 thick:
- A lathed body: a slightly domed face sunk inside a raised rim and a rounded outer bevel, all flat-faceted with toon colour bands baked from a light that
  sits in front of each face, so both faces look the same while it spins.
- A light glint arc on each face.
- A thick "$" (Montserrat Black, extruded and bevelled) standing out of both faces.
- A dark outline shell (inverted hull: a slightly bigger copy with its faces turned inward),
  so the coin has a cartoon outline from every angle. The material has backface culling on,
  which keeps the shell to the silhouette only.
The faces point along Blender +-Y = Roblox +-Z. Pivot at the coin's centre (not the ground):
the game spins it in the air. One part "Body".
"""
import math
import os

import bmesh
import bpy
from mathutils import Vector

from lib import Asset, use

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(HERE, "fonts", "Montserrat-Black.ttf")

FACE = ["FFE680", "FFD23A", "F2B21C", "D9930E"]      # lit .. shadow
RIM = ["FFF4B8", "FFE36A", "FFC93A", "E8A317"]
EDGE = ["FFC93A", "EFA51A", "D98A0C", "B86F08"]
MARK = ["E89A10", "D9840A", "BF6E06", "9E5704"]       # the $ sign: deeper orange
OUTLINE = "3B2208"
SHINE = "FFF8D6"
LIGHT = Vector((0.45, -0.75, 0.5)).normalized()

R = 0.8          # outer radius
SEG = 32         # segments around


def band(n):
    # mirror the normal onto the front so the back face shades like the front
    n = Vector((n.x, -abs(n.y), n.z))
    d = n.dot(LIGHT)
    return 0 if d > 0.8 else 1 if d > 0.45 else 2 if d > 0.0 else 3


def paint(a, o, kinds):
    me = o.data
    layer = me.uv_layers[0] if len(me.uv_layers) else me.uv_layers.new(name="UVMap")
    for poly, kind in zip(me.polygons, kinds):
        if kind == "outline":
            u, v = a.swatch(OUTLINE)
        elif kind == "shine":
            u, v = a.swatch(SHINE)
        else:
            pal = {"face": FACE, "rim": RIM, "edge": EDGE, "mark": MARK}[kind]
            u, v = a.swatch(pal[band(poly.normal)])
        for li in poly.loop_indices:
            layer.data[li].uv = (u, v)
        poly.use_smooth = False


def body():
    """Lathe a profile (radius, y) around the Y axis. Front is -Y."""
    front = [
        (0.0, -0.150, "face"),
        (0.30, -0.140, "face"),
        (0.52, -0.122, "face"),
        (0.55, -0.120, "rim"),     # foot of the rim's inner wall
        (0.59, -0.196, "rim"),
        (0.64, -0.212, "rim"),     # rim top
        (0.71, -0.205, "rim"),
        (0.765, -0.170, "edge"),   # rounded outer bevel
        (R, -0.105, "edge"),
    ]
    back = [(r, -y, k) for r, y, k in reversed(front)]
    prof = front + back
    verts, rings = [], []
    for i, (r, y, _) in enumerate(prof):
        idx = []
        for s in range(SEG):
            t = s * math.tau / SEG
            rr = r
            if r == 0.0:
                if s:
                    idx.append(idx[0])
                    continue
            idx.append(len(verts))
            verts.append(Vector((math.cos(t) * rr, y, math.sin(t) * rr)))
        rings.append(idx)
    faces, kinds = [], []
    for i in range(len(prof) - 1):
        lo, hi = rings[i], rings[i + 1]
        kind = prof[i][2] if i < len(front) else prof[i + 1][2]   # same bands on both sides
        for s in range(SEG):
            j = (s + 1) % SEG
            quad = [lo[s], lo[j], hi[j], hi[s]]
            q = []
            for v in quad:                       # collapse the centre fan to triangles
                if v not in q:
                    q.append(v)
            faces.append(q)
            kinds.append(kind)
    me = bpy.data.meshes.new("coin")
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.update()
    o = bpy.data.objects.new("coin", me)
    bpy.context.collection.objects.link(o)
    outward(o)
    return o, kinds


def outward(o):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(o.data)
    bm.free()
    o.data.update()


def dollar(front=True):
    """A thick $ standing out of one face (rim top is at |y| 0.21, face at 0.12-0.15)."""
    curve = bpy.data.curves.new("dollar", "FONT")
    curve.body = "$"
    curve.font = bpy.data.fonts.load(FONT, check_existing=True)
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    curve.size = 1.0
    curve.extrude = 0.05
    curve.bevel_depth = 0.0
    curve.bevel_resolution = 0
    curve.resolution_u = 2
    o = bpy.data.objects.new("dollar", curve)
    bpy.context.collection.objects.link(o)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.ops.object.convert(target="MESH")
    o = bpy.context.view_layer.objects.active
    # text is in XY facing +Z: stand it up to face -Y, centre it, scale to fit inside the rim
    me = o.data
    lo = Vector((min(v.co.x for v in me.vertices), min(v.co.y for v in me.vertices), 0))
    hi = Vector((max(v.co.x for v in me.vertices), max(v.co.y for v in me.vertices), 0))
    mid = (lo + hi) / 2
    k = 0.78 / (hi.y - lo.y)                  # $ is 0.78 tall
    for v in me.vertices:
        x, y, z = (v.co.x - mid.x) * k, (v.co.y - mid.y) * k, v.co.z
        # z in [-extrude, extrude] -> depth out of the face
        depth = -0.13 - (z + 0.05) * 0.75     # sinks into the face, top stands at about -0.205
        if front:
            v.co = Vector((x, depth, y))
        else:
            v.co = Vector((-x, -depth, y))    # mirrored so it reads the right way round
    me.update()
    outward(o)
    return o


def face_y(r):
    """Height of the face surface (front, negative y) at radius r."""
    if r <= 0.30:
        return -0.150 + 0.010 * r / 0.30
    return -0.140 + 0.018 * (r - 0.30) / 0.22


def glint(front=True):
    """Cartoon shine: a thin tapered arc and a dot on the face's upper left, standing just
    proud of the face."""
    verts, faces = [], []
    n = 7
    a0, a1 = math.radians(112), math.radians(162)
    for k in range(n + 1):
        t = k / n
        ang = a0 + (a1 - a0) * t
        w = 0.048 * math.sin(math.pi * (0.15 + 0.7 * t))      # tapered ends
        for r in (0.43 - w, 0.43 + w):
            verts.append((math.cos(ang) * r, face_y(r) - 0.008, math.sin(ang) * r))
    for k in range(n):
        faces.append((2 * k, 2 * k + 1, 2 * k + 3, 2 * k + 2))
    c = len(verts)
    ang = math.radians(97)
    cx, cz = math.cos(ang) * 0.43, math.sin(ang) * 0.43
    verts.append((cx, face_y(0.43) - 0.008, cz))
    for k in range(8):
        t = k * math.tau / 8
        verts.append((cx + math.cos(t) * 0.03, face_y(0.43) - 0.008, cz + math.sin(t) * 0.03))
    for k in range(8):
        faces.append((c, c + 1 + k, c + 1 + (k + 1) % 8))
    if not front:
        verts = [(-x, -y, z) for x, y, z in verts]
    me = bpy.data.meshes.new("glint")
    me.from_pydata(verts, [], faces)
    me.update()
    o = bpy.data.objects.new("glint", me)
    bpy.context.collection.objects.link(o)
    # face it away from the coin
    want = -1 if front else 1
    for poly in me.polygons:
        if poly.normal.y * want < 0:
            poly.flip()
    me.update()
    return o


def hull(objs, thick=0.05):
    """Dark outline shell: copy, push every vertex out along its normal, turn the faces in."""
    bm = bmesh.new()
    for o in objs:
        bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * thick
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    me = bpy.data.meshes.new("outline")
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("outline", me)
    bpy.context.collection.objects.link(o)
    return o


def coin_cash():
    a = Asset("Coin_Cash", "prop")
    use(a)
    a.cull = True
    b, kinds = body()
    paint(a, b, kinds)
    marks = [dollar(True), dollar(False)]
    for m in marks:
        paint(a, m, ["mark"] * len(m.data.polygons))
    shines = [glint(True), glint(False)]
    for g in shines:
        paint(a, g, ["shine"] * len(g.data.polygons))
    shell = hull([b])
    paint(a, shell, ["outline"] * len(shell.data.polygons))
    a.part("Body", [b] + marks + shines + [shell])
    a.extra["pivot"] = "centre"
    return a


ALL = {"Coin_Cash": coin_cash}


# ------------------------------------------------------------------ coin pouch
# Coin_Pouch: the cash drop that pops out of leaf piles (DropController), Dev 2026-10-31:
# "where is the model for coin pouch". A chunky cartoon money sack about 2.3 studs tall:
# - a lumpy lathed burlap body that bulges at the bottom and cinches in at the neck,
# - a frilly flared top with a dark inside and three gold coins (the Coin_Cash shape)
#   poking out of it,
# - a gold rope tied round the neck with a knot and two tassel ends at the front,
# - a big gold "$" bent onto the front of the sack,
# - the same dark inverted-hull outline as the coin.
# Toon colour bands like the coin. Front is Blender -Y. Pivot at the sack's middle (the
# game bobs and spins it in the air). One part "Body".

SACK = ["E9B977", "D49A55", "B87C3C", "8F5A26"]       # lit .. shadow
SACK_IN = ["5A3514", "4A2A0F", "3D220C", "2E1908"]
ROPE = ["FFE07A", "F2BE36", "D99A16", "AD740B"]
POUCH_LIGHT = Vector((0.45, -0.75, 0.5)).normalized()
PSEG = 36

# (radius, height) of the outside, bottom to the lip of the opening
SACK_OUT = [
    (0.0, 0.0), (0.38, 0.02), (0.68, 0.10), (0.86, 0.26), (0.95, 0.47), (0.95, 0.70),
    (0.87, 0.93), (0.70, 1.13), (0.50, 1.28), (0.36, 1.38), (0.33, 1.46), (0.38, 1.56),
    (0.52, 1.70), (0.66, 1.84), (0.70, 1.90),
]
# lip, then down into the opening to a dark floor the coins sit on
SACK_IN_PROF = [(0.70, 1.90), (0.62, 1.88), (0.46, 1.74), (0.34, 1.62), (0.0, 1.60)]


def pband(n):
    d = n.dot(POUCH_LIGHT)
    return 0 if d > 0.7 else 1 if d > 0.3 else 2 if d > -0.2 else 3


def ppaint(a, o, pal):
    me = o.data
    layer = me.uv_layers[0] if len(me.uv_layers) else me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        u, v = a.swatch(pal[pband(poly.normal)] if isinstance(pal, list) else pal)
        for li in poly.loop_indices:
            layer.data[li].uv = (u, v)
        poly.use_smooth = False


def lump(t, z):
    """Lumpy cloth: soft bumps on the body, frilly waves on the flared top."""
    if z > 1.55:
        k = (z - 1.55) / 0.35
        return 1 + 0.13 * k * math.sin(7 * t)
    return 1 + 0.035 * math.sin(3 * t + 0.6) + 0.02 * math.sin(5 * t + z * 3)


def lathe(prof, name, wobble=True):
    verts, rings = [], []
    for r, z in prof:
        idx = []
        if r == 0.0:
            idx = [len(verts)] * PSEG
            verts.append(Vector((0, 0, z)))
        else:
            for s in range(PSEG):
                t = s * math.tau / PSEG
                rr = r * (lump(t, z) if wobble else 1)
                idx.append(len(verts))
                verts.append(Vector((math.cos(t) * rr, math.sin(t) * rr, z)))
        rings.append(idx)
    faces = []
    for i in range(len(prof) - 1):
        lo, hi = rings[i], rings[i + 1]
        for s in range(PSEG):
            j = (s + 1) % PSEG
            q = []
            for v in (lo[s], lo[j], hi[j], hi[s]):
                if v not in q:
                    q.append(v)
            faces.append(q)
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.update()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    return o


def sack_radius(z):
    for (r0, z0), (r1, z1) in zip(SACK_OUT, SACK_OUT[1:]):
        if z0 <= z <= z1:
            return r0 + (r1 - r0) * (z - z0) / max(z1 - z0, 1e-6)
    return SACK_OUT[-1][0]


def face_out(o, centre):
    """Turn every face away from a centre point."""
    me = o.data
    for poly in me.polygons:
        c = poly.center
        if poly.normal.dot(c - centre) < 0:
            poly.flip()
    me.update()


def sack_dollar():
    """A thick gold $ bent onto the front of the sack."""
    curve = bpy.data.curves.new("pdollar", "FONT")
    curve.body = "$"
    curve.font = bpy.data.fonts.load(FONT, check_existing=True)
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    curve.size = 1.0
    curve.extrude = 0.05
    curve.resolution_u = 2
    o = bpy.data.objects.new("pdollar", curve)
    bpy.context.collection.objects.link(o)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.ops.object.convert(target="MESH")
    o = bpy.context.view_layer.objects.active
    me = o.data
    xs = [v.co.x for v in me.vertices]
    ys = [v.co.y for v in me.vertices]
    mx, my = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    k = 0.9 / (max(ys) - min(ys))            # 0.9 studs tall
    zc = 0.66                                # centre height on the sack
    for v in me.vertices:
        x, y, z = (v.co.x - mx) * k, (v.co.y - my) * k, v.co.z
        h = zc + y
        R = sack_radius(h) * 1.04 + (z + 0.05) * 1.0 + 0.02    # stands well out of the lumpy cloth
        ang = -math.pi / 2 + x / sack_radius(h)                 # around the front (-Y)
        v.co = Vector((math.cos(ang) * R, math.sin(ang) * R, h))
    me.update()
    outward(o)
    face_out(o, Vector((0, 0, zc)))
    return o


def rope():
    """Gold rope round the neck, a knot at the front and two tassel ends."""
    bpy.ops.mesh.primitive_torus_add(major_radius=0.40, minor_radius=0.075,
                                     major_segments=28, minor_segments=8, location=(0, 0, 1.44))
    ring = bpy.context.view_layer.objects.active
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=0.14, location=(0, -0.47, 1.44))
    knot = bpy.context.view_layer.objects.active
    knot.scale = (1.25, 0.9, 1.0)
    pieces = [ring, knot]
    for side in (-1, 1):
        # a short tail hanging down from the knot, ending in a tassel
        x0, x1 = side * 0.06, side * 0.20
        top, bot = Vector((x0, -0.52, 1.38)), Vector((x1, -0.66, 1.08))
        d = bot - top
        bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.05, depth=d.length,
                                            location=(top + bot) / 2)
        tail = bpy.context.view_layer.objects.active
        tail.rotation_mode = "QUATERNION"
        tail.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
        bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=0.11, radius2=0.04, depth=0.2,
                                        location=bot + Vector((0, 0, -0.06)))
        tassel = bpy.context.view_layer.objects.active
        pieces += [tail, tassel]
    for p in pieces:
        bpy.context.view_layer.objects.active = p
        bpy.ops.object.select_all(action="DESELECT")
        p.select_set(True)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return pieces


def top_coins():
    """Three Coin_Cash-shaped coins poking out of the opening, tilted every which way."""
    out = []
    spots = [((-0.16, 0.06, 1.86), (20, 0, 25)), ((0.20, 0.10, 1.80), (-15, 0, -35)),
             ((0.02, -0.14, 1.93), (8, 0, -5))]
    for loc, rot in spots:
        b, kinds = body()
        b.scale = (0.42, 0.42, 0.42)
        b.rotation_euler = [math.radians(a) for a in rot]
        b.location = loc
        bpy.context.view_layer.objects.active = b
        bpy.ops.object.select_all(action="DESELECT")
        b.select_set(True)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        out.append((b, kinds))
    return out


def coin_pouch():
    a = Asset("Coin_Pouch", "prop")
    use(a)
    a.cull = True
    outer = lathe(SACK_OUT, "sack")
    face_out(outer, Vector((0, 0, 0.8)))
    ppaint(a, outer, SACK)
    inner = lathe(SACK_IN_PROF, "sack_in")
    for poly in inner.data.polygons:            # the inside faces up, into the opening
        if poly.normal.z < 0:
            poly.flip()
    inner.data.update()
    ppaint(a, inner, SACK_IN)
    mark = sack_dollar()
    ppaint(a, mark, ROPE)
    ropes = rope()
    for r in ropes:
        ppaint(a, r, ROPE)
    coins3 = top_coins()
    for b, kinds in coins3:
        paint(a, b, kinds)
    shell = hull([outer], 0.06)
    a.paint(shell, OUTLINE)
    rope_shell = hull(ropes, 0.035)
    a.paint(rope_shell, OUTLINE)
    mark_shell = hull([mark], 0.03)
    a.paint(mark_shell, OUTLINE)
    coin_shells = [hull([b], 0.03) for b, _ in coins3]
    for s in coin_shells:
        a.paint(s, OUTLINE)
    pieces = [outer, inner, mark] + ropes + [b for b, _ in coins3] + [shell, rope_shell, mark_shell] + coin_shells
    # pivot at the sack's middle
    for p in pieces:
        p.location.z -= 1.0
        bpy.context.view_layer.objects.active = p
        bpy.ops.object.select_all(action="DESELECT")
        p.select_set(True)
        bpy.ops.object.transform_apply(location=True)
    a.part("Body", pieces)
    a.extra["pivot"] = "centre"
    return a


ALL["Coin_Pouch"] = coin_pouch
