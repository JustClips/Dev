"""Litter on the ground: single leaves (Leaf_*), trash pieces (Trash_*) and the LeafDump.

Leaves are tiny untextured meshes (light grey, no texture) so the game can tint each one
with MeshPart.Color. About 1 stud long, a slight curl, a little thickness so both sides
render, under 60 triangles. Pivot in the middle, lying flat (Blender +Z up = Roblox +Y up).

Trash pieces lie on their side, about 1.5 studs long, palette-coloured like other props.
The LeafDump is a green shredder bin with an open yellow hopper, 8 wide, 7 deep, 6 tall,
front at -Y (Roblox -Z), pivot at the bottom centre.
"""
import math
import random

import bpy
from mathutils import Vector

from lib import Asset, use, box, cyl, cone, torus, ico, sphere, deform, join
from aliens import shade

THICK = 0.035


def flat_mesh(name, outline, curl=0.12, bend=0.06, twist=0.0, center=(0.0, 0.0)):
    """A fan of triangles from `center` to the outline points (x, y), curled up at the sides
    (curl), bent along its length (bend) and given a little thickness."""
    cx, cy = center
    verts = [(cx, cy, 0.0)] + [(x, y, 0.0) for x, y in outline]
    n = len(outline)
    faces = [(0, 1 + i, 1 + (i + 1) % n) for i in range(n)]
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)

    def shape(v):
        x, y = v.x, v.y
        z = curl * x * x * 4 + bend * (y * y * 2) + twist * x * y
        return Vector((x, y, z))
    deform(o, shape)
    # centre the height so the pivot sits in the middle of the leaf
    zs = [v.co.z for v in o.data.vertices]
    mid = (min(zs) + max(zs)) / 2
    for v in o.data.vertices:
        v.co.z -= mid
    for poly in o.data.polygons:
        poly.use_smooth = True
    mod = o.modifiers.new("Thick", "SOLIDIFY")
    mod.thickness = THICK
    mod.offset = 0
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier="Thick")
    return o


def polar(points):
    """(angle degrees, radius) -> (x, y), angle 0 = -Y (the leaf tip), counter-clockwise."""
    out = []
    for a, r in points:
        t = math.radians(a)
        out.append((math.sin(t) * r, -math.cos(t) * r))
    return out


def leaf_asset(name, outline, **kw):
    a = Asset(name, "prop")
    a.plain = True
    use(a)
    o = flat_mesh(name, outline, **kw)
    a.part("Leaf", [o])
    return a


def maple():
    # five pointed lobes plus a little stem at the base
    pts = [(0, 0.55), (22, 0.3), (45, 0.5), (68, 0.3), (95, 0.42), (130, 0.22), (170, 0.22), (178, 0.42),
           (182, 0.42), (190, 0.22), (230, 0.22), (265, 0.42), (292, 0.3), (315, 0.5), (338, 0.3)]
    return leaf_asset("Leaf_Maple", polar(pts), curl=0.1, bend=0.08)


def oak():
    # rounded lobes (in and out), longer than wide
    pts = []
    for k in range(14):
        a = k * 360 / 14
        r = 0.36 + 0.12 * math.cos(math.radians(a)) + (0.07 if k % 2 == 0 else -0.05)
        pts.append((a, r))
    out = [(x * 0.75, y * 1.1) for x, y in polar(pts)]
    return leaf_asset("Leaf_Oak", out, curl=0.12, bend=0.07)


def birch():
    # oval with a pointed tip and a few serrations
    pts = [(0, 0.55), (25, 0.36), (55, 0.32), (90, 0.3), (125, 0.3), (155, 0.32), (180, 0.36),
           (205, 0.32), (235, 0.3), (270, 0.3), (305, 0.32), (335, 0.36)]
    out = [(x * 0.8, y) for x, y in polar(pts)]
    return leaf_asset("Leaf_Birch", out, curl=0.14, bend=0.06)


def seaweed():
    # a long wavy blade, 1.2 long
    left, right = [], []
    for k in range(7):
        t = k / 6
        y = -0.6 + 1.2 * t
        w = 0.07 + 0.08 * math.sin(math.pi * t)
        sway = 0.08 * math.sin(t * math.pi * 2.2)
        left.append((sway - w, y))
        right.append((sway + w, y))
    outline = right + list(reversed(left))
    return leaf_asset("Leaf_Seaweed", outline, curl=0.2, bend=0.03, twist=0.15, center=(0.0, 0.0))


def paper():
    rnd = random.Random(7)
    pts = [(a, 0.5 + rnd.uniform(-0.08, 0.06)) for a in range(20, 360, 45)]
    a = leaf_asset("Leaf_Paper", polar(pts), curl=0.05, bend=0.02)
    o = a.parts["Leaf"]["obj"]
    deform(o, lambda v: Vector((v.x, v.y, v.z + 0.05 * math.sin(v.x * 9) * math.cos(v.y * 7))))
    return a


def snow():
    a = Asset("Leaf_Snow", "prop")
    a.plain = True
    use(a)
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1)
    o = bpy.context.view_layer.objects.active
    rnd = random.Random(3)
    for v in o.data.vertices:
        v.co = Vector((v.co.x * 0.5, v.co.y * 0.42, v.co.z * 0.2)) * (1 + rnd.uniform(-0.12, 0.12))
    for poly in o.data.polygons:
        poly.use_smooth = True
    a.part("Leaf", [o])
    return a


# ------------------------------------------------------------------------- trash

def trash(name, build):
    def make():
        a = Asset(name, "prop")
        use(a)
        a.part("Body", build())
        return a
    return make


def can():
    red = "D8343C"
    p = [cyl(red, loc=(0, 0, 0.33), r=0.33, h=1.1, rot=(90, 0, 0), verts=14)]
    p.append(cyl("C8C8D2", loc=(0, -0.58, 0.33), r=0.3, h=0.06, rot=(90, 0, 0), verts=14))
    p.append(cyl("C8C8D2", loc=(0, 0.58, 0.33), r=0.3, h=0.06, rot=(90, 0, 0), verts=14))
    p.append(cyl("FFFFFF", loc=(0, 0, 0.33), r=0.335, h=0.3, rot=(90, 0, 0), verts=14))
    return p


def bottle():
    glass = "6FD3A0"
    p = [cyl(glass, loc=(0, 0.15, 0.28), r=0.28, h=0.9, rot=(90, 0, 0), verts=12)]
    p.append(cyl(glass, loc=(0, -0.45, 0.28), r=0.28, r2=0.1, h=0.3, rot=(-90, 0, 0), verts=12))
    p.append(cyl(glass, loc=(0, -0.7, 0.28), r=0.1, h=0.25, rot=(90, 0, 0), verts=10))
    p.append(cyl("2E6FD8", loc=(0, -0.85, 0.28), r=0.12, h=0.08, rot=(90, 0, 0), verts=10))
    p.append(cyl("FFFFFF", loc=(0, 0.15, 0.28), r=0.285, h=0.35, rot=(90, 0, 0), verts=12))
    return p


def paper_ball():
    o = ico("F2EFE6", loc=(0, 0, 0.42), scale=0.45, sub=2)
    rnd = random.Random(11)
    deform(o, lambda v: Vector((v.x, v.y, v.z)) + (Vector((v.x, v.y, v.z - 0.42)).normalized() * rnd.uniform(-0.08, 0.06)))
    return [o]


def juice_box():
    p = [box("FF9A3C", loc=(0, 0, 0.3), size=(0.75, 1.2, 0.6), bevel=0.03)]
    p.append(box("FFFFFF", loc=(0, 0.1, 0.61), size=(0.5, 0.5, 0.02)))
    p.append(box("5BC85B", loc=(0, 0.1, 0.62), size=(0.3, 0.3, 0.02)))
    p.append(cyl("FF5AA0", loc=(0.2, -0.75, 0.45), r=0.04, h=0.5, rot=(80, 0, 0), verts=6))
    return p


def chip_bag():
    o = sphere("FFD23C", loc=(0, 0, 0.18), scale=(0.6, 0.8, 0.18), seg=12, rings=6)
    deform(o, lambda v: Vector((v.x, v.y, v.z + 0.03 * math.sin(v.y * 14))))
    p = [o]
    for y in (-0.82, 0.82):
        p.append(box(shade("FFD23C", -0.15), loc=(0, y, 0.18), size=(1.1, 0.12, 0.05)))
    p.append(box("E8343C", loc=(0, 0, 0.36), size=(0.6, 0.5, 0.02)))
    return p


def bucket():
    blue = "3C8CFF"
    p = [cyl(blue, loc=(0, 0, 0.45), r=0.48, r2=0.38, h=1.0, rot=(90, 0, 0), verts=14, cap=False)]
    p.append(cyl(shade(blue, -0.2), loc=(0, 0.48, 0.45), r=0.38, h=0.05, rot=(90, 0, 0), verts=14))
    p.append(torus(shade(blue, -0.15), loc=(0, -0.5, 0.45), R=0.48, r=0.05, rot=(90, 0, 0), seg=14, mseg=4))
    p.append(torus("C8C8D2", loc=(0, -0.3, 0.45), R=0.5, r=0.025, rot=(0, 90, 0), seg=14, mseg=4))
    return p


def shell():
    pink = "FFB6A0"
    pts = []
    p = []
    for k in range(7):
        a = math.radians(-60 + k * 20)
        p.append(cone(shade(pink, -0.05 * (k % 2)), loc=(math.sin(a) * 0.35, -math.cos(a) * 0.35 + 0.3, 0.12),
                      r=0.14, h=0.75, rot=(90, 0, -math.degrees(a)), verts=6))
    p.append(box(shade(pink, -0.2), loc=(0, 0.45, 0.1), size=(0.3, 0.2, 0.18), bevel=0.04))
    return p


def pizza_box():
    p = [box("D2A064", loc=(0, 0, 0.12), size=(1.5, 1.5, 0.24), bevel=0.02)]
    p.append(box("E8343C", loc=(0, 0, 0.245), size=(0.7, 0.7, 0.01)))
    p.append(box("FFFFFF", loc=(0, 0, 0.25), size=(0.5, 0.2, 0.01)))
    return p


def cup():
    p = [cyl("FFFFFF", loc=(0, 0, 0.32), r=0.32, r2=0.24, h=0.95, rot=(90, 0, 0), verts=12)]
    p.append(cyl("E8343C", loc=(0, -0.05, 0.32), r=0.31, r2=0.27, h=0.35, rot=(90, 0, 0), verts=12))
    p.append(cyl("C8C8D2", loc=(0, -0.5, 0.32), r=0.35, h=0.07, rot=(90, 0, 0), verts=12))
    p.append(cyl("FF5AA0", loc=(0.1, -0.75, 0.42), r=0.035, h=0.55, rot=(70, 0, 0), verts=6))
    return p


# ------------------------------------------------------------------------- dump

def leaf_dump():
    """Green shredder bin (8 x 7 x 6) with an open yellow hopper on top, a dark chute and
    hazard stripes on the front, wheels and a lever. Front at -Y."""
    a = Asset("LeafDump", "prop")
    use(a)
    green, yellow, dark = "3FA34D", "FFC83C", "2A2A33"
    p = [box(green, loc=(0, 0, 2.0), size=(7.6, 6.4, 3.6), bevel=0.25)]                    # bin z 0.2 .. 3.8
    p.append(box(shade(green, -0.2), loc=(0, 0, 0.35), size=(7.8, 6.6, 0.5), bevel=0.12))  # base skirt
    p.append(box(shade(green, -0.15), loc=(0, 0, 3.85), size=(7.8, 6.6, 0.25), bevel=0.08))  # rim
    # hopper: four slanted yellow walls opening upwards, z 3.9 .. 6.0
    for sx, sy, w, rot in ((0, -1, 6.6, (-25, 0, 0)), (0, 1, 6.6, (25, 0, 0)), (-1, 0, 5.8, (0, 25, 0)), (1, 0, 5.8, (0, -25, 0))):
        size = (w, 0.2, 2.2) if sy else (0.2, w, 2.2)
        p.append(box(yellow, loc=(sx * 3.05, sy * 2.65, 4.95), size=size, rot=rot, bevel=0.06))
    p.append(box(dark, loc=(0, 0, 3.95), size=(5.0, 4.0, 0.1)))                             # dark mouth
    for k in range(5):
        p.append(cyl("8A8A96", loc=(-1.6 + k * 0.8, 0, 4.05), r=0.14, h=3.6, rot=(90, 0, 0), verts=8))  # shredder rollers
    # front: chute, hazard stripes, recycle badge
    p.append(box(dark, loc=(0, -3.22, 1.4), size=(3.2, 0.1, 1.2), bevel=0.05))
    for k in range(7):
        p.append(box(yellow if k % 2 == 0 else dark, loc=(-3.0 + k * 1.0, -3.23, 3.25), size=(1.0, 0.06, 0.45), rot=(0, 30, 0)))
    p.append(cyl("FFFFFF", loc=(2.4, -3.24, 2.0), r=0.55, h=0.06, rot=(90, 0, 0), verts=16))
    p.append(torus(green, loc=(2.4, -3.28, 2.0), R=0.35, r=0.07, rot=(90, 0, 0), seg=12, mseg=4))
    # wheels and lever
    for x in (-3.3, 3.3):
        for y in (-2.4, 2.4):
            p.append(cyl(dark, loc=(x, y, 0.45), r=0.45, h=0.4, rot=(0, 90, 0), verts=12))
    p.append(cyl("C8C8D2", loc=(3.95, -1.0, 3.0), r=0.08, h=1.4, rot=(0, 20, 0), verts=8))
    p.append(sphere("E8343C", loc=(4.2, -1.0, 3.65), scale=0.2, seg=10, rings=6))
    a.part("Body", p, collide=True)
    return a


# ------------------------------------------------------------------------- backpack

def backpack():
    """Leaf backpack in the blocky pet style: an open-top bag (2.2 wide, 2.6 tall, 1.2 deep)
    with straps, a front pocket with a leaf badge and side pockets. "Fill" is the untextured
    leaf heap inside (pivot at its bottom, see meta parts.Fill.joint); the game scales its
    height from empty to full, and at full height it bulges over the rim.
    Pivot at the centre of the face that touches the player's back; the bag sticks out
    toward Blender +Y = Roblox +Z."""
    a = Asset("Backpack", "prop")
    use(a)
    green, dark, trim, strap = "5BB04A", "3E7F33", "F2C14E", "4A3A2C"
    W, D, H, T = 2.2, 1.2, 2.6, 0.12          # outer size and wall thickness
    z0, z1 = -H / 2, H / 2
    p = []
    p.append(box(green, loc=(0, D / 2, z0 + T / 2), size=(W, D, T)))                 # bottom
    p.append(box(green, loc=(0, T / 2, 0), size=(W, T, H)))                          # back
    p.append(box(green, loc=(0, D - T / 2, 0), size=(W, T, H)))                      # front
    for sx in (-1, 1):
        p.append(box(green, loc=(sx * (W / 2 - T / 2), D / 2, 0), size=(T, D, H)))   # sides
    # rim and corner trims
    for y in (T / 2, D - T / 2):
        p.append(box(trim, loc=(0, y, z1 - 0.06), size=(W + 0.06, T + 0.06, 0.14)))
    for sx in (-1, 1):
        p.append(box(trim, loc=(sx * (W / 2 - T / 2), D / 2, z1 - 0.06), size=(T + 0.06, D + 0.06, 0.14)))
    p.append(box(dark, loc=(0, D / 2, z0 + 0.06), size=(W + 0.04, D + 0.04, 0.12)))            # base band
    # front pocket with a flap, buckle and leaf badge
    p.append(box(dark, loc=(0, D + 0.15, -0.45), size=(1.5, 0.3, 1.0)))
    p.append(box(green, loc=(0, D + 0.17, -0.02), size=(1.56, 0.34, 0.24)))
    p.append(box(trim, loc=(0, D + 0.33, -0.2), size=(0.22, 0.04, 0.26)))
    p.append(box("8BE04E", loc=(0, D + 0.31, -0.6), size=(0.42, 0.04, 0.26), rot=(0, 35, 0)))
    p.append(box("8BE04E", loc=(0, D + 0.31, -0.6), size=(0.26, 0.04, 0.42), rot=(0, 35, 0)))
    # side pockets
    for sx in (-1, 1):
        p.append(box(dark, loc=(sx * (W / 2 + 0.1), D / 2, -0.55), size=(0.2, 0.8, 0.9)))
    # straps: down the back face and over the shoulders (toward -Y, over the player)
    for sx in (-1, 1):
        x = sx * 0.55
        p.append(box(strap, loc=(x, -0.04, -0.05), size=(0.26, 0.08, 2.3)))
        p.append(box(strap, loc=(x, -0.35, z1 - 0.02), size=(0.26, 0.7, 0.08)))
        p.append(box(trim, loc=(x, -0.05, -0.8), size=(0.3, 0.1, 0.12)))
    a.part("Body", p)
    # leaf heap: fills the inside up to a little dome over the rim
    iw, idp = W - 2 * T - 0.04, D - 2 * T - 0.04
    bottom = z0 + T
    heap = [box("FFFFFF", loc=(0, D / 2, bottom + (H - T - 0.1) / 2), size=(iw, idp, H - T - 0.1))]
    heap.append(sphere("FFFFFF", loc=(0, D / 2, z1 - 0.12), scale=(iw / 2 * 1.02, idp / 2 * 1.02, 0.38), seg=12, rings=6))
    fill = a.part("Fill", heap, joint=(0, D / 2, bottom), plain=True)
    return a


ALL = {
    "Leaf_Maple": maple,
    "Leaf_Oak": oak,
    "Leaf_Birch": birch,
    "Leaf_Seaweed": seaweed,
    "Leaf_Paper": paper,
    "Leaf_Snow": snow,
    "Trash_Can": trash("Trash_Can", can),
    "Trash_Bottle": trash("Trash_Bottle", bottle),
    "Trash_PaperBall": trash("Trash_PaperBall", paper_ball),
    "Trash_JuiceBox": trash("Trash_JuiceBox", juice_box),
    "Trash_ChipBag": trash("Trash_ChipBag", chip_bag),
    "Trash_Bucket": trash("Trash_Bucket", bucket),
    "Trash_Shell": trash("Trash_Shell", shell),
    "Trash_PizzaBox": trash("Trash_PizzaBox", pizza_box),
    "Trash_Cup": trash("Trash_Cup", cup),
    "LeafDump": leaf_dump,
    "Backpack": backpack,
}
