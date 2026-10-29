"""Cartoon rocks for the map edge: chunky cliff wall segments and boulders.

Built from chamfered, slightly jittered blocks with flat faces. Each face takes a colour
from its slope (light tops, mid sides, dark undersides), which gives a simple painted, toon
look without a texture. Tall blocks wear a thick grass cap with a few drips hanging over the
front edge.
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


def cap(size, top, loc, yaw, rnd, drips=2):
    """Grass cap on a block whose top is size (x, y) at height top: a thick chamfered slab
    a little wider than the block, plus rounded drips hanging over the front (-Y) edge."""
    sx, sy = size
    pieces = [chunk((sx * 1.06, sy * 1.06, 0.9), (0, 0, -0.55), 0, taper=0.92, jitter=0.03, bevel=0.6, rnd=rnd)]
    for k in range(drips):
        # rounded tongues of turf hanging over the front edge
        x = (k + 0.5) / drips * sx * 0.8 - sx * 0.4 + rnd.uniform(-0.6, 0.6)
        w = rnd.uniform(2.4, 3.4)
        hang = rnd.uniform(1.4, 2.4)
        pieces.append(chunk((w, 0.55, hang), (x, -sy * 0.52, -0.2 - hang), 0, taper=1.25, jitter=0.05, bevel=0.9, rnd=rnd))
    o = join(pieces, "cap")
    o.data.transform(Matrix.Rotation(yaw, 4, "Z"))
    o.data.transform(Matrix.Translation(Vector(loc) + Vector((0, 0, top))))
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
        for k in range(n):
            x = -length / 2 + length * (k + 0.5) / n + rnd.uniform(-0.6, 0.6)
            w = length / n * rnd.uniform(1.3, 1.45)
            d = depth * rnd.uniform(0.8, 0.92)
            yaw = math.radians(rnd.uniform(-5, 5))
            pieces.append(chunk((w, d, height + 1), (x, depth * 0.05, -1), yaw, taper=0.88, jitter=0.07, rnd=rnd))
        # bulges on the front face: mid-height blocks and rocks at the foot
        for k in range(2):
            x = -length / 2 + length * (k + 0.5) / 2 + rnd.uniform(-2.5, 2.5)
            w, d = rnd.uniform(6.5, 9), rnd.uniform(4.5, 6)
            h = height * rnd.uniform(0.4, 0.62)
            yaw = math.radians(rnd.uniform(-12, 12))
            pieces.append(chunk((w, d, h + 1), (x, -depth * 0.36, -1), yaw, taper=0.8, jitter=0.1, rnd=rnd))
            pieces.append(cap((w * 0.8, d * 0.8), h, (x, -depth * 0.36, 0), yaw, rnd, drips=1))
        for k in range(3):
            x = -length / 2 + length * (k + 0.5) / 3 + rnd.uniform(-2.5, 2.5)
            sz = rnd.uniform(2.4, 3.6)
            pieces.append(chunk((sz * 1.3, sz, sz * 0.8 + 0.6), (x, -depth * 0.58 + rnd.uniform(-0.3, 0.3), -0.6),
                                math.radians(rnd.uniform(0, 90)), taper=0.75, jitter=0.12, rnd=rnd))
        # one long turf top over the whole segment (a little past each end so neighbours join),
        # with rounded tongues hanging down the front
        pieces.append(cap((length + 0.8, depth * 0.86), height, (0, depth * 0.05, 0), 0, rnd, drips=5))
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
            pieces.append(cap((sx * 0.78, sy * 0.78), sz, (0, 0, 0), yaw, rnd, drips=1 if sx < 9 else 2))
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
