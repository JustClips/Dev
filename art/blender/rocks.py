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

LENGTH, DEPTH, HEIGHT = 24.0, 16.0, 30.0


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


# ------------------------------------------------------------------ cliffs

def mesa(a, rnd, center, radius, height, sides=None, tilt=0.0):
    """One chunky rock mass: an irregular prism with faceted sides (each ring nudged in or
    out), a strata step, a flat grass top and a grass lip that spills over the edge in uneven
    drips. Built as one closed mesh, so the grass can't float or leave bare spots."""
    n = sides or rnd.randint(7, 9)
    cx, cy = center
    rx, ry = radius
    ang = [k * math.tau / n + rnd.uniform(-0.25, 0.25) for k in range(n)]
    base = [rnd.uniform(0.85, 1.15) for _ in range(n)]
    h = height
    step = rnd.uniform(0.4, 0.6) * h
    drip = [rnd.choice((0.6, 1.0, 1.5, 2.2)) for _ in range(n)]
    # rings: (height, radius scale, jitter, kind); the lip rings are per point
    rings = [
        (lambda k: -1.0, 1.08, 0.06, "stone"),
        (lambda k: step - 0.6, 1.0, 0.1, "stone"),
        (lambda k: step + rnd.uniform(-0.8, 0.8), 0.9, 0.05, "stone"),   # strata ledge steps in
        (lambda k: h - 0.9 - drip[k], 0.88, 0.08, "stone"),
        (lambda k: h - 0.7 - drip[k] * 0.9, 0.95, 0.0, "grass"),   # bottom of the turf drip
        (lambda k: h - 0.35, 0.97, 0.0, "grass"),            # lip bulge
        (lambda k: h, 0.91, 0.0, "grass"),
    ]
    verts, ring_idx, ring_kind = [], [], []
    for zf, sc, jit, kind in rings:
        idx = []
        for k in range(n):
            r = base[k] * sc * (1 + rnd.uniform(-jit, jit))
            x = cx + math.cos(ang[k]) * rx * r
            y = cy + math.sin(ang[k]) * ry * r
            z = zf(k)
            idx.append(len(verts))
            verts.append(Vector((x + tilt * z * 0.08, y, z)))
        ring_idx.append(idx)
        ring_kind.append(kind)
    tris, kinds = [], []
    for r in range(len(rings) - 1):
        lo, hi = ring_idx[r], ring_idx[r + 1]
        kind = "grass" if ring_kind[r] == "grass" else "stone"
        for k in range(n):
            j = (k + 1) % n
            tris += [(lo[k], lo[j], hi[j]), (lo[k], hi[j], hi[k])]
            kinds += [kind, kind]
    # flat grass top with a slight dome
    top = ring_idx[-1]
    c = len(verts)
    verts.append(Vector((cx, cy, h + 0.3)))
    for k in range(n):
        tris.append((top[k], top[(k + 1) % n], c))
        kinds.append("grass")
    o = make_mesh("mesa", verts, tris)
    paint(a, o, kinds, rnd)
    return o


def cliff(name, seed):
    """A 24-stud stretch of border: a cluster of rock masses in three rows, low ones in front,
    tall ones behind, each a different height, with gaps and cracks between them and fallen
    rocks at the foot. Masses run a little past both ends so neighbouring pieces interlock."""
    def make():
        a = Asset(name, "prop")
        use(a)
        rnd = random.Random(seed)
        pieces = []
        rows = (                     # (y of row, radius range, height range, count)
            (DEPTH * 0.3, (7.0, 9.0), (20, 30), 2),     # back: tall masses and peaks
            (0.0, (5.5, 7.0), (12, 19), 3),             # middle
            (-DEPTH * 0.35, (3.6, 5.0), (5, 10), 3),    # front: low shoulders
        )
        for y, (r0, r1), (h0, h1), count in rows:
            for k in range(count):
                x = -LENGTH / 2 + LENGTH * (k + 0.5) / count + rnd.uniform(-2.0, 2.0)
                r = rnd.uniform(r0, r1)
                hgt = rnd.uniform(h0, h1)
                if rnd.random() < 0.25:
                    hgt *= 0.7            # a broken-down one now and then
                pieces.append(mesa(a, rnd, (x, y + rnd.uniform(-1.2, 1.2)), (r * rnd.uniform(0.9, 1.25), r * rnd.uniform(0.75, 1.0)),
                                   hgt, tilt=rnd.uniform(-1, 1)))
        # fallen rocks at the foot
        for _ in range(rnd.randint(3, 5)):
            x = rnd.uniform(-LENGTH / 2 + 2, LENGTH / 2 - 2)
            s = rnd.uniform(1.8, 3.6)
            pieces.append(lump(a, rnd, (s * 1.35, s, s * 0.9), (x, -DEPTH * 0.35 - 3.5 - rnd.uniform(0, 2), -0.4),
                               grass_top=s > 3.0, sub=1))
        a.part("Body", pieces, collide=True)
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
