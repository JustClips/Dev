"""Cartoon rocks for the map edge: chunky cliff wall segments and boulders.

Built from chamfered, slightly jittered blocks with flat faces. Each face takes a colour
band from a baked light direction, which gives a simple painted, toon look without a
texture. Grass caps are shaped to the rock's real top outline and sit inside it, with turf
tongues hanging down the front face, so nothing hovers.
- Cliff_1..3: wall segments about 24 long (Blender X), 12 deep and 13-17 tall. The stepped
  front faces -Y (Roblox -Z, the model's LookVector), which is the side to turn toward the
  play area. Overlap neighbours by 2-4 studs and mix the three for an unbroken wall.
- Boulder_1..3: free-standing rocks (about 5, 8 and 12 wide). 1 and 3 have grass caps.
Pivot at the bottom centre. The rock goes about 1 stud under the ground so no seam shows.
One part "Body", collide on.
"""
import math
import random

import bmesh
import bpy
from mathutils import Vector, Matrix
from mathutils.geometry import convex_hull_2d

from lib import Asset, use, join

STONE = ["D9CDB8", "BBAE98", "988C7A", "776D60"]   # lit top .. shadow (warm cartoon stone)
GRASS = ["86D94F", "66BE3A", "4C9B2D", "3B7F24"]   # lit top .. shadow


def chunk(size, loc, yaw=0.0, taper=0.85, jitter=0.08, bevel=0.28, rnd=None):
    """A chamfered block (size x, y, z), the top a bit narrower, corners nudged at random."""
    rnd = rnd or random.Random(1)
    sx, sy, sz = size
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel * min(sx, sy, sz) / max(sx, sy, sz) * 0.5 + 0.06,
                    segments=1, affect="EDGES", profile=0.5)
    for v in bm.verts:
        t = v.co.z + 0.5                       # 0 bottom .. 1 top
        k = 1 - (1 - taper) * t
        v.co.x *= k * (1 + rnd.uniform(-jitter, jitter))
        v.co.y *= k * (1 + rnd.uniform(-jitter, jitter))
        v.co.z *= 1 + rnd.uniform(-jitter, jitter) * 0.6
    me = bpy.data.meshes.new("chunk")
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("chunk", me)
    bpy.context.collection.objects.link(o)
    o.data.transform(Matrix.Diagonal((sx, sy, sz, 1)))
    o.data.transform(Matrix.Rotation(yaw, 4, "Z"))
    o.data.transform(Matrix.Translation(Vector(loc) + Vector((0, 0, sz / 2))))
    o["kind"] = "stone"
    return o


def cap_on(rocks, rnd, drips=2, thick=0.55):
    """Grass cap shaped to the actual top of the given rock blocks: it follows their top
    outline (a slight lip past the edge), its bottom sits 0.3 inside the rock so nothing
    hovers, and rounded turf tongues hang down the front (-Y) face with their backs inside
    the rock."""
    pts, zs = [], []
    for r in rocks:
        top = max(v.co.z for v in r.data.vertices)
        for v in r.data.vertices:
            if v.co.z > top - 0.45:
                pts.append(Vector((v.co.x, v.co.y)))
                zs.append(v.co.z)
    hull = [pts[i] for i in convex_hull_2d(pts)]
    area = sum(a.x * b.y - b.x * a.y for a, b in zip(hull, hull[1:] + hull[:1]))
    if area < 0:
        hull.reverse()
    c = sum(hull, Vector((0, 0))) / len(hull)
    bottom, top = min(zs) - 0.3, max(zs) + thick

    def out(p, d):            # push a point d studs away from the centre
        v = p - c
        return p + v.normalized() * d if v.length > 1e-6 else p

    rings = [[out(p, -0.15) for p in hull], [out(p, 0.18) for p in hull], [c + (p - c) * 0.86 for p in hull]]
    heights = [bottom, top - 0.3, top]
    verts = []
    for ring, z in zip(rings, heights):
        verts += [(p.x, p.y, z) for p in ring]
    n = len(hull)
    faces = []
    for r in range(2):
        for i in range(n):
            j = (i + 1) % n
            faces.append((r * n + i, r * n + j, (r + 1) * n + j, (r + 1) * n + i))
    verts.append((c.x, c.y, top + 0.05))
    faces += [(2 * n + i, 2 * n + (i + 1) % n, 3 * n) for i in range(n)]
    me = bpy.data.meshes.new("cap")
    me.from_pydata(verts, [], faces)
    me.update()
    o = bpy.data.objects.new("cap", me)
    bpy.context.collection.objects.link(o)
    pieces = [o]
    # tongues along the front-facing edges of the outline
    edges = []
    for i in range(n):
        a, b = hull[i], hull[(i + 1) % n]
        d = b - a
        nrm = Vector((d.y, -d.x)).normalized()       # outward for a counter-clockwise ring
        if nrm.y < -0.6 and d.length > 1.5:
            edges.append((a, b, nrm))
    edges.sort(key=lambda e: -(e[1] - e[0]).length)
    for k in range(min(drips, len(edges) * 3)):
        a, b, nrm = edges[k % len(edges)]
        t = (k // len(edges) + 0.5) / max(1, math.ceil(drips / len(edges))) if len(edges) < drips else 0.5
        t = min(max(t + rnd.uniform(-0.15, 0.15), 0.15), 0.85)
        p = a + (b - a) * t - nrm * 0.12
        w = min(rnd.uniform(2.2, 3.2), (b - a).length * 0.6)
        hang = rnd.uniform(1.2, 2.0)
        ang = math.atan2((b - a).y, (b - a).x)
        tongue = chunk((w, 0.5, hang + 0.4), (0, 0, 0), ang, taper=1.2, jitter=0.04, bevel=0.9, rnd=rnd)
        tongue.data.transform(Matrix.Translation((p.x, p.y, bottom + 0.4 - hang)))
        pieces.append(tongue)
    o = join(pieces, "cap")
    o["kind"] = "grass"
    return o


LIGHT = Vector((0.35, -0.55, 0.76)).normalized()


def colour_faces(a, obj, pal, rnd):
    """Baked cartoon light: each flat face takes a band of the palette from how much it
    faces the light, with an occasional one-step shift so big walls aren't uniform."""
    me = obj.data
    layer = me.uv_layers[0] if len(me.uv_layers) else me.uv_layers.new(name="UVMap")
    uv = layer.data
    for poly in me.polygons:
        d = poly.normal.dot(LIGHT)
        i = 0 if d > 0.72 else 1 if d > 0.35 else 2 if d > -0.05 else 3
        if 0 < i < 3 and rnd.random() < 0.18:
            i += rnd.choice((-1, 1))
        u, v = a.swatch(pal[i])
        for li in poly.loop_indices:
            uv[li].uv = (u, v)
        poly.use_smooth = False


def finish(a, pieces):
    rnd = random.Random(len(a.name))
    for p in pieces:
        colour_faces(a, p, GRASS if p.get("kind") == "grass" else STONE, rnd)
    a.part("Body", pieces, collide=True)
    return a


def cliff(name, seed, length=24.0, depth=12.0, height=15.0):
    def make():
        a = Asset(name, "prop")
        use(a)
        rnd = random.Random(seed)
        pieces = []
        # three big overlapping blocks make one continuous wall, all topped at the same height
        n = 3
        wall = []
        for k in range(n):
            x = -length / 2 + length * (k + 0.5) / n + rnd.uniform(-0.6, 0.6)
            w = length / n * rnd.uniform(1.3, 1.45)
            d = depth * rnd.uniform(0.8, 0.92)
            yaw = math.radians(rnd.uniform(-5, 5))
            wall.append(chunk((w, d, height + 1), (x, depth * 0.05, -1), yaw, taper=0.88, jitter=0.07, rnd=rnd))
        pieces += wall
        # bulges on the front face: mid-height blocks and rocks at the foot
        for k in range(2):
            x = -length / 2 + length * (k + 0.5) / 2 + rnd.uniform(-2.5, 2.5)
            w, d = rnd.uniform(6.5, 9), rnd.uniform(4.5, 6)
            h = height * rnd.uniform(0.4, 0.62)
            yaw = math.radians(rnd.uniform(-12, 12))
            block = chunk((w, d, h + 1), (x, -depth * 0.36, -1), yaw, taper=0.8, jitter=0.1, rnd=rnd)
            pieces += [block, cap_on([block], rnd, drips=1)]
        for k in range(3):
            x = -length / 2 + length * (k + 0.5) / 3 + rnd.uniform(-2.5, 2.5)
            sz = rnd.uniform(2.4, 3.6)
            pieces.append(chunk((sz * 1.3, sz, sz * 0.8 + 0.6), (x, -depth * 0.58 + rnd.uniform(-0.3, 0.3), -0.6),
                                math.radians(rnd.uniform(0, 90)), taper=0.75, jitter=0.12, rnd=rnd))
        # one long turf top over the whole segment (a little past each end so neighbours join),
        # with rounded tongues hanging down the front
        pieces.append(cap_on(wall, rnd, drips=5))
        a.extra["segment"] = {"length": length, "depth": depth, "height": height}
        return finish(a, pieces)
    return make


def boulder(name, seed, size, capped=True, extra=0):
    def make():
        a = Asset(name, "prop")
        use(a)
        rnd = random.Random(seed)
        sx, sy, sz = size
        yaw = math.radians(rnd.uniform(-10, 10))
        pieces = [chunk((sx, sy, sz + 0.6), (0, 0, -0.6), yaw, taper=0.78, jitter=0.1, bevel=0.35, rnd=rnd)]
        if capped:
            pieces.append(cap_on([pieces[0]], rnd, drips=1 if sx < 9 else 2))
        for k in range(extra):
            ang = rnd.uniform(0, math.tau)
            s = min(sx, sy) * rnd.uniform(0.35, 0.5)
            pieces.append(chunk((s * 1.2, s, s * 0.8 + 0.5), (math.cos(ang) * sx * 0.5, math.sin(ang) * sy * 0.5, -0.5),
                                ang, taper=0.75, jitter=0.12, rnd=rnd))
        return finish(a, pieces)
    return make


ALL = {
    "Cliff_1": cliff("Cliff_1", 3, height=15),
    "Cliff_2": cliff("Cliff_2", 7, height=16),
    "Cliff_3": cliff("Cliff_3", 12, height=14),
    "Boulder_1": boulder("Boulder_1", 21, (8, 6.5, 5.5), True, 1),
    "Boulder_2": boulder("Boulder_2", 22, (5, 4.2, 3.6), False, 1),
    "Boulder_3": boulder("Boulder_3", 23, (12, 9.5, 8), True, 2),
}
