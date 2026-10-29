"""Cartoon border for the map edge: continuous cliff wall pieces and boulders.

Cliff_1..4 are 24-stud wall pieces that join edge to edge into one unbroken cliff:
- The rock face is a grid of flat facets: rock pillars that stick out by different amounts,
  with a strata step and a talus at the foot, so no two stretches look the same.
- Grass covers the whole top, rolls over the front edge as a thick lip and hangs down in
  uneven scallops (no separate caps that could float or leave bare patches).
- Both ends of every piece have the same profile at the same height, so any piece can sit
  next to any other with no seam or gap. The top dips and rises in between.
- The front (the rock face) is Blender -Y = Roblox -Z, the model's LookVector: turn it toward
  the play area. Depth is about 14 (front face to back), height 15 at the ends.
Boulder_1..3 are rounded lumpy rocks about 5, 8 and 12 wide with grass over their tops.
Colours: flat faces take a band of the palette from a baked light direction (toon look).
Pivot at the bottom centre; everything goes about 1 stud under the ground. One part "Body",
collide on.
"""
import math
import random

import bmesh
import bpy
from mathutils import Vector

from lib import Asset, use, join

STONE = ["DDD3C2", "BFB4A1", "9C917F", "776E61"]   # lit .. shadow (warm cartoon stone)
GRASS = ["8EDC55", "6CC23E", "52A12F", "3D8226"]   # lit .. shadow
LIGHT = Vector((0.35, -0.55, 0.76)).normalized()

LENGTH, DEPTH, HEIGHT = 24.0, 14.0, 15.0
NX = 12                                             # columns along the length (2 studs)


def band(normal, rnd, wobble=True):
    d = normal.dot(LIGHT)
    i = 0 if d > 0.72 else 1 if d > 0.35 else 2 if d > -0.05 else 3
    if wobble and 0 < i < 3 and rnd.random() < 0.15:
        i += rnd.choice((-1, 1))
    return i


def paint(a, o, kinds, rnd):
    """Give every face its palette swatch (kinds[k] = "grass"/"stone" per face)."""
    layer = o.data.uv_layers[0] if len(o.data.uv_layers) else o.data.uv_layers.new(name="UVMap")
    for poly, kind in zip(o.data.polygons, kinds):
        pal = GRASS if kind == "grass" else STONE
        u, v = a.swatch(pal[band(poly.normal, rnd, wobble=kind == "grass")])
        for li in poly.loop_indices:
            layer.data[li].uv = (u, v)
        poly.use_smooth = False


def make_mesh(name, verts, tris):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], tris)
    me.update()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    # every face outward (face order is kept, so per-face kinds still line up)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    me.update()
    return o


# ------------------------------------------------------------------ cliff wall

def cliff(name, seed):
    def make():
        a = Asset(name, "prop")
        use(a)
        rnd = random.Random(seed)
        xs = [-LENGTH / 2 + LENGTH * i / NX for i in range(NX + 1)]

        def fade(i):              # 0 at both ends, 1 in the middle: ends match every piece
            t = i / NX
            return min(1.0, min(t, 1 - t) * 5)

        # rock pillars: neighbouring columns share a pillar now and then
        pillar, p = [], rnd.uniform(0, 1.2)
        for i in range(NX + 1):
            if rnd.random() < 0.8:
                p = rnd.uniform(0, 2.6)
            pillar.append(p)
        top_bump = [0.0] * (NX + 1)
        for _ in range(3):
            c, w, h = rnd.uniform(0.2, 0.8) * NX, rnd.uniform(1.5, 3.5), rnd.uniform(-1.2, 2.6)
            for i in range(NX + 1):
                top_bump[i] += h * math.exp(-((i - c) / w) ** 2)
        lip = [rnd.choice((0.9, 1.3, 1.7, 2.3, 3.0)) for _ in range(NX + 1)]
        strata = rnd.uniform(0.45, 0.6)

        face = -DEPTH / 2                         # the front face line

        def profile(i):
            """Cross-section at column i: (y, z, kind) from the front foot, up the face,
            over the top and down the back."""
            f = fade(i)
            top = HEIGHT + top_bump[i] * f

            def out(k):
                return face - pillar[i] * k * f

            lip_low = top - (lip[i] if 0 < i < NX else 1.6)
            return [
                (face - 1.5 - 0.7 * f * rnd.random(), -1.0, "stone"),   # talus at the foot
                (face - 0.9 - 0.4 * f * rnd.random(), 1.4, "stone"),
                (out(1.0), top * 0.3, "stone"),
                (out(1.0) + 0.35 * f, top * strata, "stone"),          # strata step
                (out(0.8), top * strata + 0.4, "stone"),
                (out(0.6), lip_low - 0.7, "stone"),
                (face - 0.1, lip_low, "grass"),                        # bottom of the turf lip
                (face - 0.8, top - 0.5, "grass"),                      # the lip bulges out
                (face - 0.4, top, "grass"),
                (face + DEPTH * 0.3, top + 0.35 * f, "grass"),
                (face + DEPTH * 0.65, top + 0.2 * f, "grass"),
                (DEPTH / 2, top - 0.2, "grass"),
                (DEPTH / 2 + 0.4, top * 0.5, "stone"),
                (DEPTH / 2 + 0.2, -1.0, "stone"),
            ]

        cols = [profile(i) for i in range(NX + 1)]
        m = len(cols[0])
        verts = [Vector((xs[i], y, z)) for i in range(NX + 1) for (y, z, _) in cols[i]]
        tris, kinds = [], []
        for i in range(NX):
            for j in range(m - 1):
                a0, a1 = i * m + j, i * m + j + 1
                b0, b1 = (i + 1) * m + j, (i + 1) * m + j + 1
                kind = "grass" if cols[i][j][2] == "grass" else "stone"
                if (i + j) % 2:
                    tris += [(a0, b0, b1), (a0, b1, a1)]
                else:
                    tris += [(a0, b0, a1), (b0, b1, a1)]
                kinds += [kind, kind]
        # close both ends with the profile polygon (fan from its centre)
        for i in (0, NX):
            c = sum((verts[i * m + j] for j in range(m)), Vector()) / m
            ci = len(verts)
            verts.append(c)
            for j in range(m):
                tris.append((ci, i * m + j, i * m + (j + 1) % m))
                kinds.append("grass" if cols[i][j][2] == "grass" and cols[i][(j + 1) % m][2] == "grass" else "stone")
        wall = make_mesh("wall", verts, tris)
        paint(a, wall, kinds, rnd)
        # boulders at the foot, varied
        pieces = [wall]
        for _ in range(rnd.randint(2, 4)):
            x = rnd.uniform(-LENGTH / 2 + 3, LENGTH / 2 - 3)
            s = rnd.uniform(2.4, 4.2)
            pieces.append(lump(a, rnd, (s * 1.35, s, s * 0.9), (x, face - 1.4 - s * 0.35, -0.4), grass_top=s > 3.2, sub=1))
        o = join(pieces, "Body")
        a.part("Body", [o], collide=True)
        a.extra["segment"] = {"length": LENGTH, "depth": DEPTH, "height": HEIGHT}
        return a
    return make


# ------------------------------------------------------------------ boulders

def lump(a, rnd, size, loc, grass_top=True, sub=2):
    """Rounded, lumpy rock: a squashed icosphere with its corners nudged, flat faces, the
    bottom pressed flat under the ground. Faces that look up are grass when grass_top."""
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
    sx, sy, sz = size
    for v in bm.verts:
        n = v.co.copy()
        k = 1 + rnd.uniform(-0.12, 0.12)
        v.co = Vector((n.x * sx / 2 * k, n.y * sy / 2 * k, max(n.z, -0.35) * sz * 0.75 * k))
    bmesh.ops.translate(bm, verts=bm.verts, vec=Vector(loc) + Vector((0, 0, sz * 0.26)))
    me = bpy.data.meshes.new("lump")
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("lump", me)
    bpy.context.collection.objects.link(o)
    kinds = ["grass" if grass_top and (p.normal.z > 0.62 or (p.normal.z > 0.38 and rnd.random() < 0.45)) else "stone"
             for p in me.polygons]
    paint(a, o, kinds, rnd)
    return o


def boulder(name, seed, size, grass_top=True, extra=0):
    def make():
        a = Asset(name, "prop")
        use(a)
        rnd = random.Random(seed)
        pieces = [lump(a, rnd, size, (0, 0, -0.6), grass_top)]
        sx, sy, sz = size
        for _ in range(extra):
            ang = rnd.uniform(0, math.tau)
            s = min(sx, sy) * rnd.uniform(0.32, 0.45)
            pieces.append(lump(a, rnd, (s * 1.2, s, s * 0.8), (math.cos(ang) * sx * 0.48, math.sin(ang) * sy * 0.48, -0.4),
                               grass_top and s > 2.5, sub=1))
        a.part("Body", pieces, collide=True)
        return a
    return make


ALL = {
    "Cliff_1": cliff("Cliff_1", 3),
    "Cliff_2": cliff("Cliff_2", 7),
    "Cliff_3": cliff("Cliff_3", 12),
    "Cliff_4": cliff("Cliff_4", 19),
    "Boulder_1": boulder("Boulder_1", 21, (8, 6.5, 5.5), True, 1),
    "Boulder_2": boulder("Boulder_2", 22, (5, 4.2, 3.6), False, 1),
    "Boulder_3": boulder("Boulder_3", 23, (12, 9.5, 8), True, 2),
}
