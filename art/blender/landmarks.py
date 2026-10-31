"""Zone landmarks: the big themed pieces that make each zone feel like a place.

  Park         Park_Fountain, Park_Playground, Park_Gazebo, Park_Picnic, Park_Lamp,
               Park_FlowerBed, Park_DuckPond
  Beach        Beach_Lifeguard, Beach_HutA/B/C, Beach_IceCream, Beach_Volleyball,
               Beach_Sandcastle, Beach_Surfboards, Beach_Lighthouse, Beach_Boat
  City         City_ShopA/B/C/D, City_BusStop, City_HotDog, City_Newsstand,
               City_TrafficLight, City_StreetLamp, City_Billboard, City_Statue
  Snowy Peaks  Snow_Lodge, Snow_SkiLift, Snow_Igloo, Snow_Snowman, Snow_Cocoa,
               Snow_Sled, Snow_FrozenPond

Same conventions as earth.py: 1 m = 1 stud, front = -Y, origin on the ground in the
middle of the footprint, one "Body" part that collides. Glowing bits (lamps, windows)
are their own *_Glow part so they turn Neon in game. Kept low-poly for phones.
"""
import math
import random
from mathutils import Vector
from lib import Asset, use, sphere, ico, box, cyl, cone, torus, tube, capsule, deform, noise_deform
from props import WOOD, WOOD_DARK, WOOD_LIGHT

LEAF, LEAF_DARK, LEAF_LIGHT = "5DBB4A", "3F9A3A", "86D45E"
STONE, STONE_DARK, STONE_LIGHT = "B8B4AC", "8E8A84", "D8D4CC"
WATER, WATER_DEEP = "5CC4F0", "3A9ED8"
WHITE, RED, YELLOW, BLUE, PINK = "FFFFFF", "E8463C", "FFD23A", "3D8BFF", "FF8CB4"
METAL, METAL_DARK = "6E7682", "3A3F4A"
SNOW, ICE = "F4F8FF", "BEE2F6"
FLOWERS = ("FF5A7A", "FFD23A", "FFFFFF", "B07CFF", "FF9A3C")


def _rot_place(obj, rot=(0, 0, 0), loc=(0, 0, 0)):
    from mathutils import Euler, Matrix
    m = Matrix.Translation(loc) @ Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
    obj.data.transform(m)
    obj.data.update()
    return obj


def beam(color, a, b, w=0.3, d=None):
    """Square post from a to b."""
    a, b = Vector(a), Vector(b)
    o = box(color, size=(w, d or w, (b - a).length), bevel=0.0)
    q = (b - a).to_track_quat("Z", "Y")
    o.data.transform(q.to_matrix().to_4x4())
    o.data.transform(__import__("mathutils").Matrix.Translation((a + b) / 2))
    o.data.update()
    return o


def rod(color, a, b, r=0.12, verts=8):
    a, b = Vector(a), Vector(b)
    o = cyl(color, r=r, h=(b - a).length, verts=verts)
    q = (b - a).to_track_quat("Z", "Y")
    o.data.transform(q.to_matrix().to_4x4())
    o.data.transform(__import__("mathutils").Matrix.Translation((a + b) / 2))
    o.data.update()
    return o


def gable(color, half, z0, h, a0, a1, axis="y"):
    """Triangular prism: base width 2*half at height z0, apex h above, running from a0 to
    a1 along `axis` (the ridge direction)."""
    import bpy
    from lib import _asset
    tri = [(-half, z0), (half, z0), (0, z0 + h)]
    verts = []
    for a in (a0, a1):
        for (u, z) in tri:
            verts.append((u, a, z) if axis == "y" else (a, u, z))
    faces = [(0, 1, 2), (5, 4, 3), (0, 3, 4, 1), (1, 4, 5, 2), (2, 5, 3, 0)]
    me = bpy.data.meshes.new("gable")
    me.from_pydata(verts, [], faces)
    me.update()
    me.validate()
    o = bpy.data.objects.new("gable", me)
    bpy.context.scene.collection.objects.link(o)
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    import lib
    lib._asset.paint(o, color)
    return o


def roof_slab(color, p0, p1, a0, a1, t, axis="y"):
    """Flat slab from p0 to p1 (u, z) running a0..a1 along `axis`, thickness t."""
    du, dz = p1[0] - p0[0], p1[1] - p0[1]
    L = math.hypot(du, dz)
    mid_u, mid_z, mid_a = (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2, (a0 + a1) / 2
    if axis == "y":
        o = box(color, size=(L, abs(a1 - a0), t))
        return _rot_place(o, rot=(0, -math.degrees(math.atan2(dz, du)), 0), loc=(mid_u, mid_a, mid_z))
    o = box(color, size=(abs(a1 - a0), L, t))
    return _rot_place(o, rot=(math.degrees(math.atan2(dz, du)), 0, 0), loc=(mid_a, mid_u, mid_z))


def flowers(cx, cy, z, radius, count, seed):
    rnd = random.Random(seed)
    p = []
    for _ in range(count):
        a = rnd.uniform(0, math.tau)
        r = radius * math.sqrt(rnd.random())
        x, y = cx + math.cos(a) * r, cy + math.sin(a) * r
        p.append(sphere(rnd.choice(FLOWERS), loc=(x, y, z + 0.25), scale=(0.28, 0.28, 0.2), seg=8, rings=5))
    return p


# ------------------------------------------------------------------------- Park

def park_fountain(name):
    a = Asset(name, "prop")
    use(a)
    p = [cyl(STONE, loc=(0, 0, 0.6), r=8, h=1.2, verts=24, smooth=False),
         cyl(STONE_LIGHT, loc=(0, 0, 1.25), r=8.2, h=0.2, verts=24, smooth=False),
         cyl(WATER, loc=(0, 0, 1.0), r=7.3, h=0.3, verts=24),
         cyl(STONE, loc=(0, 0, 2.6), r=0.9, h=3.0, verts=12),
         cyl(STONE, loc=(0, 0, 4.1), r=3.2, r2=3.6, h=0.6, verts=20, smooth=False),
         cyl(WATER, loc=(0, 0, 4.42), r=3.2, h=0.1, verts=20),
         cyl(STONE, loc=(0, 0, 5.4), r=0.5, h=2.0, verts=10),
         cyl(STONE, loc=(0, 0, 6.5), r=1.5, r2=1.8, h=0.4, verts=16, smooth=False),
         cyl(WATER, loc=(0, 0, 6.72), r=1.5, h=0.1, verts=16),
         sphere(STONE_LIGHT, loc=(0, 0, 7.3), scale=0.5, seg=10, rings=6)]
    # water spilling off the bowls
    p.append(cyl(WATER, loc=(0, 0, 2.7), r=3.3, r2=3.5, h=3.2, verts=20, cap=False))
    p.append(cyl(WATER, loc=(0, 0, 5.4), r=1.5, r2=1.7, h=2.0, verts=16, cap=False))
    p.append(cone(WATER, loc=(0, 0, 8.0), r=0.5, h=1.6, verts=10))
    # flower ring around the basin
    p += flowers(0, 0, 0, 0, 0, 1)
    for k in range(12):
        ang = math.radians(k * 30 + 15)
        p.append(sphere(LEAF_DARK if k % 2 else LEAF, loc=(math.cos(ang) * 9.2, math.sin(ang) * 9.2, 0.5), scale=(1.0, 1.0, 0.8), seg=10, rings=6))
        p.append(sphere(FLOWERS[k % len(FLOWERS)], loc=(math.cos(ang) * 9.2, math.sin(ang) * 9.2, 1.25), scale=0.3, seg=8, rings=5))
    a.part("Body", p, collide=True)
    return a


def park_playground(name):
    """Climbing tower with a slide, a swing set and a sandbox, on a rubber mat (20 x 14)."""
    a = Asset(name, "prop")
    use(a)
    p = [box("E86A4A", loc=(0, 0, 0.05), size=(22, 15, 0.1))]
    # tower (left)
    tx, ty = -6, 0
    for dx in (-1.6, 1.6):
        for dy in (-1.6, 1.6):
            p.append(cyl(BLUE, loc=(tx + dx, ty + dy, 3.5), r=0.2, h=7, verts=8))
    p.append(box(WOOD_LIGHT, loc=(tx, ty, 3.0), size=(3.6, 3.6, 0.3)))
    for dy in (-1.6, 1.6):
        p.append(box(YELLOW, loc=(tx, ty + dy, 3.8), size=(3.4, 0.12, 1.2)))
    p.append(cone(RED, loc=(tx, ty, 7.8), r=2.8, h=1.8, verts=4, smooth=False, rot=(0, 0, 45)))
    # ladder on the back
    for z in range(1, 6):
        p.append(rod(WOOD, (tx - 0.6, ty + 2.2, z * 0.55), (tx + 0.6, ty + 2.2, z * 0.55), r=0.07))
    p.append(rod(BLUE, (tx - 0.6, ty + 2.2, 0), (tx - 0.6, ty + 1.7, 3.1), r=0.1))
    p.append(rod(BLUE, (tx + 0.6, ty + 2.2, 0), (tx + 0.6, ty + 1.7, 3.1), r=0.1))
    # slide toward the front
    sl = box(YELLOW, size=(1.6, 6.4, 0.2))
    _rot_place(sl, rot=(-28, 0, 0), loc=(tx, ty - 4.6, 1.6))
    p.append(sl)
    for side in (-0.85, 0.85):
        rail = box(YELLOW, size=(0.15, 6.4, 0.5))
        _rot_place(rail, rot=(-28, 0, 0), loc=(tx + side, ty - 4.6, 1.85))
        p.append(rail)
    # swing set (right)
    sx = 5
    for dx in (-4.5, 4.5):
        p.append(rod(RED, (sx + dx, -1.4, 0), (sx + dx, 0, 5.2), r=0.16))
        p.append(rod(RED, (sx + dx, 1.4, 0), (sx + dx, 0, 5.2), r=0.16))
    p.append(rod(RED, (sx - 4.6, 0, 5.2), (sx + 4.6, 0, 5.2), r=0.18))
    for k, dx in enumerate((-2, 2)):
        for cx in (-0.5, 0.5):
            p.append(rod(METAL, (sx + dx + cx, 0, 5.1), (sx + dx + cx, 0, 1.3), r=0.04, verts=4))
        p.append(box(BLUE if k else YELLOW, loc=(sx + dx, 0, 1.25), size=(1.3, 0.5, 0.12)))
    # sandbox (front right)
    p.append(box(WOOD, loc=(sx, -5, 0.35), size=(6, 3.6, 0.7)))
    p.append(box("F2DA9C", loc=(sx, -5, 0.6), size=(5.4, 3.0, 0.2)))
    p.append(cone(RED, loc=(sx - 1, -5, 0.95), r=0.4, h=0.5, verts=8))
    p.append(cyl(BLUE, loc=(sx + 1.2, -4.6, 0.9), r=0.35, r2=0.45, h=0.5, verts=8))
    a.part("Body", p, collide=True)
    return a


def park_gazebo(name):
    a = Asset(name, "prop")
    use(a)
    R = 6.0
    p = [cyl(STONE_LIGHT, loc=(0, 0, 0.4), r=R + 0.6, h=0.8, verts=8, smooth=False),
         cyl(WOOD_LIGHT, loc=(0, 0, 0.85), r=R + 0.2, h=0.1, verts=8, smooth=False),
         box(STONE_LIGHT, loc=(0, -R - 1.0, 0.2), size=(3, 1.4, 0.4))]
    for k in range(8):
        ang = math.radians(k * 45 + 22.5)
        x, y = math.cos(ang) * R, math.sin(ang) * R
        p.append(cyl(WHITE, loc=(x, y, 3.5), r=0.25, h=5.4, verts=8))
        # railing between posts, open at the front
        nxt = math.radians((k + 1) * 45 + 22.5)
        x2, y2 = math.cos(nxt) * R, math.sin(nxt) * R
        if not (y < -1 and y2 < -1):
            p.append(rod(WHITE, (x, y, 2.0), (x2, y2, 2.0), r=0.1, verts=6))
    p.append(cyl("C0504A", loc=(0, 0, 6.6), r=R + 1.2, r2=0.6, h=3.4, verts=8, smooth=False))
    p.append(cyl(WHITE, loc=(0, 0, 6.3), r=R + 0.6, h=0.4, verts=8, smooth=False))
    p.append(sphere(YELLOW, loc=(0, 0, 8.6), scale=0.45, seg=10, rings=6))
    # bench ring inside
    for k in range(3):
        ang = math.radians(90 + (k - 1) * 70)
        p.append(box(WOOD, loc=(math.cos(ang) * (R - 1.2), math.sin(ang) * (R - 1.2), 1.4), size=(3, 0.9, 0.2), rot=(0, 0, math.degrees(ang) + 90)))
    a.part("Body", p, collide=True)
    return a


def park_picnic(name):
    a = Asset(name, "prop")
    use(a)
    p = [box("4AA8FF", loc=(0, 0, 0.03), size=(7, 6, 0.06))]
    p.append(box(WOOD, loc=(0, 0, 1.5), size=(4.0, 1.8, 0.2)))
    # red and white check cloth
    for i in range(4):
        for j in range(2):
            p.append(box(RED if (i + j) % 2 else WHITE, loc=(-1.5 + i, -0.45 + j * 0.9, 1.62), size=(1.0, 0.9, 0.04)))
    for dx in (-1.6, 1.6):
        p.append(rod(WOOD_DARK, (dx, -0.9, 0), (dx, 0.9, 1.45), r=0.1, verts=4))
        p.append(rod(WOOD_DARK, (dx, 0.9, 0), (dx, -0.9, 1.45), r=0.1, verts=4))
    for dy in (-1.6, 1.6):
        p.append(box(WOOD_LIGHT, loc=(0, dy, 0.85), size=(4.0, 0.6, 0.15)))
    # basket, sandwich, juice
    p.append(box("C89A5A", loc=(-0.8, 0.1, 2.0), size=(1.0, 0.7, 0.6)))
    p.append(torus("A07040", loc=(-0.8, 0.1, 2.3), R=0.4, r=0.05, rot=(90, 0, 0), seg=10, mseg=4))
    p.append(cyl("FF9A3C", loc=(0.9, -0.2, 1.9), r=0.15, h=0.5, verts=8))
    p.append(box("F2DA9C", loc=(0.4, 0.3, 1.72), size=(0.6, 0.6, 0.15)))
    a.part("Body", p, collide=True)
    return a


def park_lamp(name):
    a = Asset(name, "prop")
    use(a)
    p = [cyl(METAL_DARK, loc=(0, 0, 0.3), r=0.45, r2=0.3, h=0.6, verts=8),
         cyl(METAL_DARK, loc=(0, 0, 3.4), r=0.14, h=6, verts=8),
         cyl(METAL_DARK, loc=(0, 0, 6.5), r=0.5, r2=0.25, h=0.3, verts=8),
         cone(METAL_DARK, loc=(0, 0, 7.75), r=0.7, h=0.5, verts=8)]
    a.part("Body", p, collide=True)
    a.part("Lamp_Glow", [cyl("FFE9A8", loc=(0, 0, 7.05), r=0.42, r2=0.55, h=0.9, verts=8)], glow="FFE9A8")
    return a


def park_flowerbed(name):
    a = Asset(name, "prop")
    use(a)
    p = [cyl(STONE, loc=(0, 0, 0.35), r=3.4, h=0.7, verts=16, smooth=False),
         cyl("6B4A2E", loc=(0, 0, 0.62), r=3.0, h=0.2, verts=16)]
    for k in range(10):
        ang = math.radians(k * 36)
        p.append(sphere(LEAF if k % 2 else LEAF_DARK, loc=(math.cos(ang) * 2.2, math.sin(ang) * 2.2, 0.9), scale=(0.7, 0.7, 0.5), seg=8, rings=5))
    p += flowers(0, 0, 0.8, 2.6, 28, 7)
    p.append(sphere(LEAF_DARK, loc=(0, 0, 1.3), scale=(1.0, 1.0, 1.1), seg=10, rings=6))
    a.part("Body", p, collide=True)
    return a


def duck(col="FFFFFF"):
    return [sphere(col, loc=(0, 0, 0.35), scale=(0.45, 0.65, 0.35), seg=10, rings=6),
            sphere(col, loc=(0, -0.45, 0.8), scale=0.28, seg=10, rings=6),
            cone("FF9A3C", loc=(0, -0.78, 0.78), r=0.1, h=0.25, rot=(90, 0, 0), verts=6),
            sphere("1B1530", loc=(0.15, -0.6, 0.88), scale=0.05, seg=6, rings=4),
            sphere("1B1530", loc=(-0.15, -0.6, 0.88), scale=0.05, seg=6, rings=4)]


def park_duckpond(name):
    a = Asset(name, "prop")
    use(a)
    rim = [ico(STONE_DARK if k % 3 == 0 else STONE, loc=(math.cos(math.radians(t)) * 11, math.sin(math.radians(t)) * 7.5, 0.4),
               scale=(1.8, 1.4, 0.9), sub=1) for k, t in enumerate(range(0, 360, 18))]
    water = cyl(WATER, loc=(0, 0, 0.15), r=1, h=0.25, verts=32)
    deform(water, lambda v: Vector((v.x * 10.4, v.y * 7.0, v.z)))
    p = rim + [water]
    for (x, y, rz, col) in ((-3, 1.5, 30, WHITE), (-1.8, 2.4, 10, YELLOW), (3.5, -2, 200, WHITE)):
        d = duck(col)
        for o in d:
            _rot_place(o, rot=(0, 0, rz), loc=(x, y, 0.15))
        p += d
    p += [cyl(LEAF, loc=(x, y, 0.32), r=0.9, h=0.05, verts=10) for x, y in ((4, 3), (-5, -3), (1, -4))]
    p += [cyl(LEAF_DARK, loc=(-9 + k * 0.3, 4.5, 1.0), r=0.07, h=2.0, verts=5) for k in range(5)]
    p += [cyl(LEAF_DARK, loc=(8.5 + k * 0.3, -4, 1.0), r=0.07, h=2.0, verts=5) for k in range(4)]
    # little wooden bridge over one end
    for k in range(9):
        t = (k - 4) / 4
        p.append(box(WOOD_LIGHT if k % 2 else WOOD, loc=(7.5, t * 3.4, 1.2 - t * t * 0.9), size=(2.4, 0.75, 0.2), rot=(-t * 25, 0, 0)))
    for side in (-1.15, 1.15):
        for k in range(5):
            t = (k - 2) / 2
            p.append(cyl(WOOD_DARK, loc=(7.5 + side, t * 3.4, 1.5 - t * t * 0.9), r=0.1, h=1.2, verts=6))
        p.append(tube(WOOD_DARK, [(7.5 + side, (t - 2) / 2 * 3.4, 2.1 - ((t - 2) / 2) ** 2 * 0.9) for t in range(5)], 0.08, seg=6))
    a.part("Body", p, collide=True)
    return a


# ------------------------------------------------------------------------ Beach

def beach_lifeguard(name):
    a = Asset(name, "prop")
    use(a)
    p = []
    for dx in (-2, 2):
        for dy in (-2, 2):
            p.append(rod(WHITE, (dx * 1.15, dy * 1.15, 0), (dx * 0.8, dy * 0.8, 6), r=0.2, verts=8))
    p.append(rod(WHITE, (-2.2, -2.2, 2.5), (2.2, -2.2, 2.5), r=0.12))
    p.append(rod(WHITE, (-2.1, 2.1, 2.5), (2.1, 2.1, 2.5), r=0.12))
    p.append(box(WOOD_LIGHT, loc=(0, 0, 6.1), size=(5, 5, 0.3)))
    p.append(box(RED, loc=(0, 0.6, 7.6), size=(4.0, 3.2, 2.8)))
    p.append(box(WHITE, loc=(0, 0.6, 7.6), size=(4.05, 3.25, 0.5)))
    p.append(box("8ED8FF", loc=(0, -1.0, 7.9), size=(3.0, 0.05, 1.3)))
    roof = cone(RED, loc=(0, 0.6, 9.6), r=3.4, h=1.4, verts=4, smooth=False, rot=(0, 0, 45))
    p.append(roof)
    # railing at the front of the deck
    p.append(rod(WHITE, (-2.4, -2.4, 7), (2.4, -2.4, 7), r=0.08))
    for x in (-2.4, 0, 2.4):
        p.append(rod(WHITE, (x, -2.4, 6.2), (x, -2.4, 7), r=0.08))
    # ramp down the front
    for k in range(10):
        p.append(box(WOOD if k % 2 else WOOD_LIGHT, loc=(0, -3.0 - k * 0.6, 5.7 - k * 0.6), size=(1.6, 0.55, 0.15)))
    for x in (-0.85, 0.85):
        p.append(beam(WOOD_DARK, (x, -2.5, 6.1), (x, -9.0, -0.1), w=0.18, d=0.4))
        p.append(rod(WHITE, (x, -2.5, 7.0), (x, -8.6, 1.0), r=0.06, verts=5))
    # flag and life ring
    p.append(cyl(METAL, loc=(1.8, 1.8, 11), r=0.07, h=4, verts=6))
    p.append(box(RED, loc=(2.6, 1.8, 12.62), size=(1.5, 0.05, 0.45)))
    p.append(box(YELLOW, loc=(2.6, 1.8, 12.18), size=(1.5, 0.05, 0.45)))
    p.append(torus("FF6A3C", loc=(0, -0.98, 6.8), R=0.6, r=0.18, rot=(90, 0, 0), seg=12, mseg=6))
    a.part("Body", p, collide=True)
    return a


def beach_hut(name, wall, trim):
    a = Asset(name, "prop")
    use(a)
    p = [box(WOOD, loc=(0, 0, 0.4), size=(6.4, 6.4, 0.8)),
         box(WOOD_LIGHT, loc=(0, -3.6, 0.3), size=(3, 1.2, 0.2))]
    # striped walls
    for k in range(6):
        p.append(box(wall if k % 2 == 0 else WHITE, loc=(-2.5 + k, 0.4, 3.0), size=(1.0, 5.0, 4.4)))
    p.append(box(trim, loc=(0, -2.15, 1.9), size=(1.9, 0.1, 2.6)))
    p.append(sphere(YELLOW, loc=(0.7, -2.25, 1.9), scale=0.12, seg=6, rings=4))
    p.append(box("8ED8FF", loc=(0, -2.12, 4.3), size=(1.4, 0.06, 0.9)))
    # pitched roof
    p.append(gable(wall, 3.0, 5.2, 2.2, -2.1, 2.9))
    for side in (-1, 1):
        p.append(roof_slab(trim, (side * 3.6, 4.95), (0, 7.55), -2.6, 3.4, 0.3))
    p.append(box(WHITE, loc=(0, -3.0, 0.9), size=(1.2, 0.6, 0.3)))
    a.part("Body", p, collide=True)
    return a


def beach_icecream(name):
    a = Asset(name, "prop")
    use(a)
    p = [box(WHITE, loc=(0, 0, 1.6), size=(6, 3.4, 3.2)),
         box(PINK, loc=(0, -1.72, 1.6), size=(6.05, 0.08, 1.0)),
         box("C8E8FF", loc=(0, -1.0, 3.25), size=(5.6, 1.2, 0.1))]
    for x in (-2.8, 2.8):
        for y in (-1.6, 1.6):
            p.append(cyl(WHITE, loc=(x, y, 4.7), r=0.1, h=3, verts=6))
    for k in range(6):
        p.append(box(PINK if k % 2 == 0 else WHITE, loc=(-2.5 + k, 0, 6.3), size=(1.0, 4.2, 0.3), rot=(0, 0, 0)))
    # big cone on the roof
    p.append(cone("E8B05A", loc=(0, 0, 8.2), r=1.2, h=3.2, rot=(180, 0, 0), verts=12, smooth=False))
    p.append(sphere(PINK, loc=(0, 0, 10.0), scale=1.25, seg=14, rings=8))
    p.append(sphere("FFF4DE", loc=(0, 0, 11.1), scale=0.95, seg=14, rings=8))
    p.append(sphere(RED, loc=(0, 0, 12.1), scale=0.3, seg=8, rings=5))
    # little stools
    for x in (-1.8, 0, 1.8):
        p.append(cyl(METAL, loc=(x, -2.8, 0.6), r=0.08, h=1.2, verts=6))
        p.append(cyl(PINK, loc=(x, -2.8, 1.25), r=0.4, h=0.15, verts=10))
    a.part("Body", p, collide=True)
    return a


def beach_volleyball(name):
    a = Asset(name, "prop")
    use(a)
    p = []
    # court lines on the sand
    for (x, y, sx, sy) in ((0, -6, 8.2, 0.15), (0, 6, 8.2, 0.15), (-4, 0, 0.15, 12.1), (4, 0, 0.15, 12.1)):
        p.append(box(WHITE, loc=(x, y, 0.03), size=(sx, sy, 0.06)))
    for x in (-5, 5):
        p.append(cyl(WOOD, loc=(x, 0, 2.6), r=0.18, h=5.2, verts=8))
    p.append(box(WHITE, loc=(0, 0, 4.8), size=(10, 0.06, 0.25)))
    net = box("2A2A2A", loc=(0, 0, 4.0), size=(9.8, 0.04, 1.5))
    p.append(net)
    p.append(box(WHITE, loc=(0, 0, 3.25), size=(10, 0.06, 0.1)))
    ball = [sphere(WHITE, loc=(2.5, -3, 0.45), scale=0.45, seg=12, rings=8),
            torus(YELLOW, loc=(2.5, -3, 0.45), R=0.45, r=0.05, seg=12, mseg=4),
            torus(BLUE, loc=(2.5, -3, 0.45), R=0.45, r=0.05, rot=(90, 0, 0), seg=12, mseg=4)]
    a.part("Body", p + ball, collide=True)
    return a


def beach_sandcastle(name):
    a = Asset(name, "prop")
    use(a)
    SAND, SAND_D = "F0D79C", "D9BB7A"
    p = [cyl(SAND_D, loc=(0, 0, 0.3), r=5.5, h=0.6, verts=16, smooth=False)]
    p.append(box(SAND, loc=(0, 0, 1.6), size=(6, 6, 2.2)))
    for x in (-3, 3):
        for y in (-3, 3):
            p.append(cyl(SAND, loc=(x, y, 2.0), r=1.0, h=3.4, verts=10, smooth=False))
            p.append(cone(SAND_D, loc=(x, y, 4.2), r=1.15, h=1.1, verts=10, smooth=False))
    p.append(cyl(SAND, loc=(0, 0, 3.8), r=1.6, h=2.4, verts=12, smooth=False))
    for k in range(8):
        ang = math.radians(k * 45)
        p.append(box(SAND, loc=(math.cos(ang) * 1.5, math.sin(ang) * 1.5, 5.15), size=(0.5, 0.5, 0.5)))
    p.append(box("8A6A40", loc=(0, -3.05, 1.2), size=(1.2, 0.1, 1.6)))
    p.append(cyl(METAL_DARK, loc=(0, 0, 6.4), r=0.05, h=2.4, verts=5))
    p.append(box(RED, loc=(0.45, 0, 7.2), size=(0.9, 0.04, 0.6)))
    # moat, bucket and spade
    p.append(torus(WATER, loc=(0, 0, 0.05), R=6.2, r=0.4, seg=24, mseg=4))
    p.append(cyl(BLUE, loc=(6.8, -3, 0.5), r=0.5, r2=0.65, h=1.0, verts=10))
    p.append(box(YELLOW, loc=(-6.6, -3, 0.15), size=(0.5, 1.6, 0.1), rot=(0, 0, 30)))
    a.part("Body", p, collide=True)
    return a


def beach_surfboards(name):
    a = Asset(name, "prop")
    use(a)
    p = [box(WOOD, loc=(0, 0, 1.0), size=(4.4, 0.4, 0.3)),
         box(WOOD, loc=(0, 0, 2.6), size=(4.4, 0.4, 0.3))]
    for x in (-2.1, 2.1):
        p.append(box(WOOD_DARK, loc=(x, 0, 1.6), size=(0.3, 0.4, 3.2)))
    for k, col in enumerate((RED, BLUE, YELLOW)):
        b = sphere(col, scale=(0.55, 0.12, 3.0), seg=12, rings=8)
        _rot_place(b, rot=(-12, 0, 0), loc=(-1.3 + k * 1.3, -0.5, 3.0))
        stripe = box(WHITE, size=(0.08, 0.26, 5.2))
        _rot_place(stripe, rot=(-12, 0, 0), loc=(-1.3 + k * 1.3, -0.5, 3.0))
        p += [b, stripe]
    a.part("Body", p, collide=True)
    return a


def beach_lighthouse(name):
    a = Asset(name, "prop")
    use(a)
    p = []
    for k in range(14):
        t = (k + 0.5) / 14
        ang = k * 25.7
        p.append(ico(STONE_DARK if k % 3 else STONE, loc=(math.cos(math.radians(ang)) * 6.5, math.sin(math.radians(ang)) * 6.5, 0.8),
                     scale=(2.2, 1.8, 1.4), sub=1))
    p.append(cyl(STONE_LIGHT, loc=(0, 0, 1.0), r=5.5, h=2.0, verts=16, smooth=False))
    # striped tower (8 bands)
    for k in range(8):
        z0 = 2 + k * 3
        r0, r1 = 3.4 - k * 0.15, 3.4 - (k + 1) * 0.15
        p.append(cyl(RED if k % 2 == 0 else WHITE, loc=(0, 0, z0 + 1.5), r=r0, r2=r1, h=3, verts=16))
    p.append(box("3A6A9A", loc=(0, -3.3, 3.6), size=(1.4, 0.4, 2.8)))
    for z in (9, 15, 21):
        p.append(box("8ED8FF", loc=(0, -3.3 + (z - 2) / 3 * 0.15 + 0.1, z), size=(0.9, 0.3, 1.2)))
    p.append(cyl(METAL_DARK, loc=(0, 0, 26.2), r=3.4, h=0.4, verts=16))
    for k in range(12):
        ang = math.radians(k * 30)
        p.append(cyl(METAL_DARK, loc=(math.cos(ang) * 3.2, math.sin(ang) * 3.2, 27.0), r=0.06, h=1.2, verts=4))
    p.append(torus(METAL_DARK, loc=(0, 0, 27.6), R=3.2, r=0.07, seg=16, mseg=4))
    for k in range(6):
        ang = math.radians(k * 60)
        p.append(cyl(METAL_DARK, loc=(math.cos(ang) * 1.8, math.sin(ang) * 1.8, 28.2), r=0.1, h=3.2, verts=4))
    p.append(cone(RED, loc=(0, 0, 30.6), r=2.4, h=1.8, verts=16, smooth=False))
    p.append(sphere(METAL_DARK, loc=(0, 0, 31.7), scale=0.35, seg=8, rings=5))
    a.part("Body", p, collide=True)
    a.part("Lamp_Glow", [cyl("FFF0A0", loc=(0, 0, 28.2), r=1.5, h=3.0, verts=12)], glow="FFF0A0")
    return a


def beach_boat(name):
    a = Asset(name, "prop")
    use(a)
    hull = sphere("3D8BFF", scale=(1.6, 4.2, 1.0), seg=16, rings=8)
    deform(hull, lambda v: Vector((v.x, v.y, min(v.z, 0.0) + 1.0)))
    inner = sphere(WOOD_LIGHT, scale=(1.4, 4.0, 0.8), seg=16, rings=8)
    deform(inner, lambda v: Vector((v.x, v.y, min(v.z, 0.0) + 1.05)))
    p = [hull, inner, torus(WHITE, loc=(0, 0, 1.0), R=1, r=0.12, seg=20, mseg=4)]
    deform(p[2], lambda v: Vector((v.x * 1.6, v.y * 4.15, v.z)))
    for y in (-1.2, 1.2):
        p.append(box(WOOD, loc=(0, y, 0.8), size=(2.8, 0.6, 0.15)))
    for side in (-1, 1):
        o = box(WOOD_DARK, size=(0.15, 4.4, 0.1))
        _rot_place(o, rot=(0, side * -12, side * 20), loc=(side * 1.4, 0.3, 1.0))
        p.append(o)
    p.append(box(WHITE, loc=(1.62, -2.2, 0.8), size=(0.05, 1.4, 0.35)))
    _rot_place(p[0], loc=(0, 0, -0.2))
    _rot_place(p[1], loc=(0, 0, -0.2))
    a.part("Body", p, collide=True)
    return a


# ------------------------------------------------------------------------- City

def city_shop(name, wall, awning, roof_kind):
    """Low shop front, 16 wide x 10 deep x 12 tall, door and display windows on the front."""
    a = Asset(name, "prop")
    use(a)
    W, D, H = 16, 10, 12
    p = [box(wall, loc=(0, 0, H / 2), size=(W, D, H)),
         box(STONE_LIGHT, loc=(0, 0, H + 0.3), size=(W + 0.6, D + 0.6, 0.6)),
         box(STONE, loc=(0, -D / 2 - 1.0, 0.1), size=(W + 2, 2.0, 0.2))]
    # ground floor: door and two windows
    p.append(box("5A3A26", loc=(0, -D / 2 - 0.05, 2.0), size=(2.4, 0.1, 4.0)))
    p.append(sphere(YELLOW, loc=(0.8, -D / 2 - 0.15, 2.0), scale=0.12, seg=6, rings=4))
    for x in (-4.8, 4.8):
        p.append(box(WHITE, loc=(x, -D / 2 - 0.05, 2.6), size=(5.0, 0.12, 3.6)))
    # striped awning
    for k in range(8):
        aw = box(awning if k % 2 == 0 else WHITE, size=(W / 8, 2.4, 0.15))
        _rot_place(aw, rot=(-20, 0, 0), loc=(-W / 2 + W / 16 + k * W / 8, -D / 2 - 1.1, 5.1))
        p.append(aw)
    # sign board
    p.append(box(WHITE, loc=(0, -D / 2 - 0.1, 6.8), size=(10, 0.2, 1.6)))
    p.append(box(awning, loc=(0, -D / 2 - 0.2, 6.8), size=(9.4, 0.06, 1.2)))
    # upstairs windows with sills
    for x in (-5, 0, 5):
        p.append(box(WHITE, loc=(x, -D / 2 - 0.08, 9.4), size=(2.6, 0.12, 2.6)))
        p.append(box(STONE_LIGHT, loc=(x, -D / 2 - 0.3, 8.0), size=(3.0, 0.5, 0.2)))
        p.append(box(LEAF, loc=(x, -D / 2 - 0.45, 8.3), size=(2.6, 0.4, 0.4)))
    if roof_kind == "tank":
        p.append(cyl(WOOD, loc=(4, 2, H + 2.6), r=1.6, h=3.0, verts=12))
        p.append(cone(WOOD_DARK, loc=(4, 2, H + 4.6), r=1.8, h=1.0, verts=12))
        for dx in (-1, 1):
            for dy in (-1, 1):
                p.append(cyl(METAL_DARK, loc=(4 + dx, 2 + dy, H + 0.9), r=0.1, h=1.2, verts=4))
    elif roof_kind == "ac":
        for x in (-4, 2):
            p.append(box(STONE_LIGHT, loc=(x, 1.5, H + 1.3), size=(2.6, 2.0, 1.4)))
            p.append(cyl(METAL, loc=(x, 0.48, H + 1.3), r=0.5, h=0.06, rot=(90, 0, 0), verts=10))
    elif roof_kind == "garden":
        p.append(box(WOOD, loc=(0, 1, H + 0.8), size=(10, 4, 0.4)))
        for x in range(-4, 5, 2):
            p.append(sphere(LEAF if x % 4 else LEAF_DARK, loc=(x, 1, H + 1.6), scale=(0.9, 0.9, 0.8), seg=8, rings=5))
    else:  # chimney
        p.append(box("A0503C", loc=(-5, 2, H + 2.0), size=(1.6, 1.6, 3.2)))
    a.part("Body", p, collide=True)
    a.part("Windows_Glass", [box("8ED8FF", loc=(x, -D / 2 - 0.12, 2.6), size=(4.4, 0.06, 3.0)) for x in (-4.8, 4.8)] +
           [box("8ED8FF", loc=(x, -D / 2 - 0.15, 9.4), size=(2.1, 0.06, 2.1)) for x in (-5, 0, 5)], material="Glass")
    a.extra["sign"] = [0, 6.8, -D / 2 - 0.3]
    return a


def city_busstop(name):
    a = Asset(name, "prop")
    use(a)
    p = [box(STONE, loc=(0, 0, 0.1), size=(8, 4, 0.2))]
    for x in (-3.5, 3.5):
        p.append(box(METAL_DARK, loc=(x, 1.2, 2.0), size=(0.2, 0.2, 3.8)))
        p.append(box(METAL_DARK, loc=(x, -0.9, 2.0), size=(0.2, 0.2, 3.8)))
    p.append(box(BLUE, loc=(0, 0.1, 4.0), size=(7.8, 3.0, 0.3)))
    p.append(box(WOOD, loc=(0, 0.8, 1.0), size=(5, 0.8, 0.15)))
    for x in (-2, 2):
        p.append(box(METAL_DARK, loc=(x, 0.8, 0.5), size=(0.15, 0.6, 0.9)))
    p.append(cyl(METAL_DARK, loc=(4.6, -1.5, 2.3), r=0.08, h=4.6, verts=6))
    p.append(cyl(BLUE, loc=(4.6, -1.5, 4.5), r=0.6, h=0.12, rot=(90, 0, 0), verts=14))
    p.append(cyl(WHITE, loc=(4.6, -1.57, 4.5), r=0.45, h=0.02, rot=(90, 0, 0), verts=14))
    # poster on the side panel
    p.append(box(YELLOW, loc=(-3.6, 0.2, 2.3), size=(0.05, 1.6, 2.2)))
    a.part("Body", p, collide=True)
    a.part("Panel_Glass", [box("8ED8FF", loc=(0, 1.25, 2.2), size=(6.8, 0.06, 2.8)),
                           box("8ED8FF", loc=(-3.5, 0.15, 2.2), size=(0.06, 2.0, 2.8))], material="Glass")
    return a


def city_hotdog(name):
    a = Asset(name, "prop")
    use(a)
    p = [box(WHITE, loc=(0, 0, 1.6), size=(4, 2.2, 1.8), bevel=0.1),
         box(RED, loc=(0, -1.12, 1.6), size=(4.0, 0.05, 0.6)),
         box(METAL, loc=(0, 0, 2.55), size=(4.1, 2.3, 0.1))]
    for x in (-1.4, 1.4):
        p.append(cyl("2A2A2A", loc=(x, -1.15, 0.5), r=0.5, h=0.2, rot=(90, 0, 0), verts=12))
        p.append(cyl("2A2A2A", loc=(x, 1.15, 0.5), r=0.5, h=0.2, rot=(90, 0, 0), verts=12))
    p.append(rod(METAL, (2, 0, 2.0), (3, 0, 2.3), r=0.06))
    p.append(cyl(METAL, loc=(0, 0, 4.2), r=0.06, h=3.2, verts=6))
    p.append(cone(RED, loc=(0, 0, 5.6), r=2.6, h=0.9, verts=8, smooth=False))
    for k in range(8):
        ang = math.radians(k * 45 + 22.5)
        p.append(sphere(YELLOW, loc=(math.cos(ang) * 2.3, math.sin(ang) * 2.3, 5.05), scale=(0.5, 0.5, 0.2), seg=8, rings=4))
    # giant hot dog on top of the umbrella pole
    p.append(capsule("E8B05A", (-0.9, 0, 6.4), (0.9, 0, 6.4), 0.38, seg=10))
    p.append(capsule("C0504A", (-1.2, 0, 6.6), (1.2, 0, 6.6), 0.22, seg=10))
    p.append(tube(YELLOW, [(-0.9, 0, 6.85), (-0.45, 0, 6.95), (0, 0, 6.85), (0.45, 0, 6.95), (0.9, 0, 6.85)], 0.06, seg=6))
    a.part("Body", p, collide=True)
    return a


def city_newsstand(name):
    a = Asset(name, "prop")
    use(a)
    p = [box("3F8F4E", loc=(0, 0, 2.0), size=(4.4, 3.4, 4.0)),
         box("2F6F3C", loc=(0, 0, 4.2), size=(5.0, 4.0, 0.4)),
         box("2F6F3C", loc=(0, -2.2, 3.6), size=(5.0, 1.2, 0.15)),
         box(WOOD_LIGHT, loc=(0, -1.85, 1.6), size=(4.0, 0.6, 0.15))]
    rnd = random.Random(3)
    for k in range(6):
        p.append(box(rnd.choice((RED, YELLOW, BLUE, PINK, WHITE)), loc=(-1.6 + k * 0.64, -1.85, 1.75), size=(0.55, 0.45, 0.06), rot=(0, 0, rnd.uniform(-8, 8))))
    for k in range(5):
        p.append(box(rnd.choice((RED, YELLOW, BLUE, WHITE)), loc=(-1.6 + k * 0.8, -1.73, 2.8), size=(0.6, 0.05, 0.8)))
    p.append(box(WHITE, loc=(0, -2.05, 4.6), size=(3.0, 0.15, 0.6)))
    p.append(box(RED, loc=(0, -2.14, 4.6), size=(2.6, 0.04, 0.4)))
    a.part("Body", p, collide=True)
    return a


def city_trafficlight(name):
    a = Asset(name, "prop")
    use(a)
    p = [cyl(METAL_DARK, loc=(0, 0, 0.2), r=0.4, h=0.4, verts=10),
         cyl(METAL_DARK, loc=(0, 0, 4), r=0.16, h=8, verts=8),
         rod(METAL_DARK, (0, 0, 7.6), (0, -3.6, 7.6), r=0.12),
         box(YELLOW, loc=(0, -3.6, 6.6), size=(0.9, 0.7, 2.6), bevel=0.1),
         box("2A2A2A", loc=(0, -3.6, 6.6), size=(0.92, 0.5, 2.4))]
    for z in (7.4, 6.6, 5.8):
        p.append(cone("2A2A2A", loc=(0, -4.0, z + 0.25), r=0.4, h=0.3, rot=(90, 0, 0), verts=8))
    # crossing button box
    p.append(box(YELLOW, loc=(0, -0.25, 3.5), size=(0.35, 0.25, 0.5)))
    a.part("Body", p, collide=True)
    a.part("Red_Glow", [cyl(RED, loc=(0, -3.88, 7.4), r=0.3, h=0.06, rot=(90, 0, 0), verts=10)], glow="FF4A3C")
    a.part("Green_Glow", [cyl("4AE07A", loc=(0, -3.88, 5.8), r=0.3, h=0.06, rot=(90, 0, 0), verts=10)], glow="4AE07A")
    return a


def city_streetlamp(name):
    a = Asset(name, "prop")
    use(a)
    p = [cyl(METAL, loc=(0, 0, 0.3), r=0.35, h=0.6, verts=8),
         cyl(METAL, loc=(0, 0, 4.5), r=0.13, h=9, verts=8),
         rod(METAL, (0, 0, 8.8), (0, -1.6, 9.3), r=0.1),
         box(METAL, loc=(0, -2.0, 9.3), size=(0.7, 1.4, 0.3))]
    a.part("Body", p, collide=True)
    a.part("Lamp_Glow", [box("FFF4CC", loc=(0, -2.0, 9.12), size=(0.55, 1.2, 0.08))], glow="FFF4CC")
    return a


def city_billboard(name):
    a = Asset(name, "prop")
    use(a)
    p = []
    for x in (-5, 5):
        p.append(cyl(METAL_DARK, loc=(x, 0.5, 5), r=0.3, h=10, verts=8))
    p.append(box(METAL_DARK, loc=(0, 0.3, 12.5), size=(16, 0.5, 6)))
    p.append(box(WHITE, loc=(0, 0, 12.5), size=(15.2, 0.1, 5.3)))
    # a sunny "sweep" ad: sky, sun, a broom and three leaves
    p.append(box("8ED8FF", loc=(0, -0.08, 12.9), size=(15.0, 0.05, 4.4)))
    p.append(box(LEAF, loc=(0, -0.08, 10.4), size=(15.0, 0.06, 0.8)))
    p.append(cyl(YELLOW, loc=(-5, -0.1, 13.6), r=1.2, h=0.05, rot=(90, 0, 0), verts=14))
    st = box(WOOD, size=(0.35, 0.06, 4.6))
    _rot_place(st, rot=(0, 35, 0), loc=(2.0, -0.12, 12.4))
    br = box(YELLOW, size=(1.6, 0.06, 1.4))
    _rot_place(br, rot=(0, 35, 0), loc=(3.5, -0.12, 10.5))
    p += [st, br]
    for k, (x, z, c) in enumerate(((5.2, 11.2, "F0802A"), (6.2, 11.6, RED), (5.6, 12.2, YELLOW))):
        lf = sphere(c, scale=(0.5, 0.06, 0.3), seg=8, rings=4)
        _rot_place(lf, rot=(0, k * 40, 0), loc=(x, -0.13, z))
        p.append(lf)
    # catwalk and lamps
    p.append(box(METAL, loc=(0, -0.8, 9.4), size=(15, 1.2, 0.15)))
    for x in (-5, 0, 5):
        p.append(rod(METAL, (x, -0.8, 9.5), (x, -1.4, 10.0), r=0.06))
    a.part("Body", p, collide=True)
    return a


def city_statue(name):
    """A golden sweeper with a broom on a plinth, the city's hero."""
    a = Asset(name, "prop")
    use(a)
    GOLD, GOLD_D = "F2C14E", "D49A2A"
    p = [cyl(STONE, loc=(0, 0, 0.3), r=4.6, h=0.6, verts=8, smooth=False),
         box(STONE_LIGHT, loc=(0, 0, 2.3), size=(4, 4, 3.4)),
         box(STONE, loc=(0, 0, 4.15), size=(4.6, 4.6, 0.4)),
         box(GOLD_D, loc=(0, -2.02, 2.4), size=(2.6, 0.05, 1.0))]
    z0 = 4.35
    # blocky figure
    p.append(box(GOLD, loc=(-0.45, 0, z0 + 1.0), size=(0.8, 0.8, 2.0)))
    p.append(box(GOLD, loc=(0.45, 0, z0 + 1.0), size=(0.8, 0.8, 2.0)))
    p.append(box(GOLD, loc=(0, 0, z0 + 3.0), size=(1.9, 1.0, 2.0)))
    p.append(box(GOLD, loc=(0, 0, z0 + 4.6), size=(1.3, 1.3, 1.2), bevel=0.15))
    arm = box(GOLD, size=(0.7, 0.7, 1.9))
    _rot_place(arm, rot=(0, -40, 0), loc=(1.5, -0.2, z0 + 3.2))
    arm2 = box(GOLD, size=(0.7, 0.7, 1.9))
    _rot_place(arm2, rot=(-50, 0, 0), loc=(-1.3, -0.6, z0 + 3.2))
    p += [arm, arm2]
    # broom raised high
    st = cyl(GOLD_D, r=0.12, h=5.2, verts=6)
    _rot_place(st, rot=(0, 35, 0), loc=(2.6, -0.2, z0 + 5.0))
    head = box(GOLD_D, size=(1.6, 0.4, 1.1))
    _rot_place(head, rot=(0, 35, 0), loc=(4.0, -0.2, z0 + 7.1))
    p += [st, head]
    # flower ring
    for k in range(8):
        ang = math.radians(k * 45 + 22.5)
        p.append(sphere(LEAF, loc=(math.cos(ang) * 3.6, math.sin(ang) * 3.6, 0.9), scale=(0.7, 0.7, 0.5), seg=8, rings=5))
        p.append(sphere(FLOWERS[k % 5], loc=(math.cos(ang) * 3.6, math.sin(ang) * 3.6, 1.35), scale=0.25, seg=6, rings=4))
    a.part("Body", p, collide=True)
    return a


# ---------------------------------------------------------------- Snowy Peaks

def snow_cap(loc, size):
    s = sphere(SNOW, loc=loc, scale=size, seg=14, rings=8)
    deform(s, lambda v: Vector((v.x, v.y, max(v.z, loc[2]))))
    return s


def snow_lodge(name):
    a = Asset(name, "prop")
    use(a)
    W, D, H = 14, 10, 6
    p = [box(STONE, loc=(0, 0, 0.5), size=(W + 1, D + 1, 1.0))]
    # log walls
    for k in range(8):
        z = 1.0 + 0.375 + k * 0.75
        for y in (-D / 2, D / 2):
            p.append(cyl(WOOD if k % 2 else WOOD_DARK, loc=(0, y, z), r=0.4, h=W + 0.8, rot=(0, 90, 0), verts=8))
        for x in (-W / 2, W / 2):
            p.append(cyl(WOOD_DARK if k % 2 else WOOD, loc=(x, 0, z + 0.37), r=0.4, h=D + 0.8, rot=(90, 0, 0), verts=8))
    p.append(box(WOOD_LIGHT, loc=(0, 0, 3.8), size=(W - 0.4, D - 0.4, 5.6)))
    # roof with snow
    top = 1.0 + 8 * 0.75
    p.append(gable(WOOD_LIGHT, D / 2 + 0.3, top, 3.6, -W / 2 - 0.3, W / 2 + 0.3, axis="x"))
    for side in (-1, 1):
        p.append(roof_slab("8A3A2A", (side * (D / 2 + 1.4), top - 0.9), (0, top + 3.95), -W / 2 - 1.2, W / 2 + 1.2, 0.4, axis="x"))
        p.append(roof_slab(SNOW, (side * (D / 2 + 1.3), top - 0.55), (0, top + 4.3), -W / 2 - 1.1, W / 2 + 1.1, 0.35, axis="x"))
    p.append(box("A0503C", loc=(4, 2.5, H + 6.0), size=(1.6, 1.6, 4.0)))
    p.append(snow_cap((4, 2.5, H + 8.0), (1.0, 1.0, 0.4)))
    # door, porch, sign
    p.append(box("5A3A26", loc=(0, -D / 2 - 0.45, 2.6), size=(2.2, 0.15, 3.2)))
    p.append(box(WOOD, loc=(0, -D / 2 - 2.2, 0.8), size=(8, 3.2, 0.3)))
    for x in (-3.8, 3.8):
        p.append(cyl(WOOD_DARK, loc=(x, -D / 2 - 3.6, 2.9), r=0.25, h=4.2, verts=8))
    p.append(box("8A3A2A", loc=(0, -D / 2 - 2.0, 5.2), size=(8.6, 3.8, 0.3), rot=(-12, 0, 0)))
    p.append(box(SNOW, loc=(0, -D / 2 - 2.0, 5.45), size=(8.6, 3.6, 0.3), rot=(-12, 0, 0)))
    p.append(box(WOOD_DARK, loc=(0, -D / 2 - 0.5, 4.9), size=(4, 0.2, 1.0)))
    # firewood stack and skis by the door
    for k in range(3):
        for j in range(3 - k):
            p.append(cyl(WOOD, loc=(-6.4 + j * 0.62 + k * 0.31, -D / 2 - 1.2, 1.3 + k * 0.55), r=0.3, h=1.4, rot=(90, 0, 0), verts=8))
    for k, col in enumerate((RED, BLUE)):
        sk = box(col, size=(0.25, 0.1, 3.6))
        _rot_place(sk, rot=(10, 0, 0), loc=(5.0 + k * 0.5, -D / 2 - 0.8, 2.0))
        p.append(sk)
    a.part("Body", p, collide=True)
    a.part("Windows_Glow", [box("FFD27A", loc=(x, -D / 2 - 0.45, 3.4), size=(2.2, 0.1, 1.8)) for x in (-4.4, 4.4)] +
           [box("FFD27A", loc=(-W / 2 - 0.45, y, 3.4), size=(0.1, 2.2, 1.8)) for y in (-2, 2)], glow="FFD27A")
    return a


def snow_skilift(name):
    """Two lift towers 36 studs apart along Y with a cable and four chairs hanging off it."""
    a = Asset(name, "prop")
    use(a)
    L = 18
    p = []
    for y, h in ((-L, 12), (L, 16)):
        p.append(box(STONE, loc=(0, y, 0.5), size=(3, 3, 1)))
        p.append(cyl(METAL, loc=(0, y, h / 2), r=0.5, h=h, verts=10))
        p.append(box(METAL_DARK, loc=(0, y, h + 0.3), size=(6, 0.8, 0.6)))
        for x in (-2.6, 2.6):
            p.append(cyl(METAL_DARK, loc=(x, y, h - 0.1), r=0.45, h=0.3, rot=(90, 0, 0), verts=10))
        p.append(snow_cap((0, y, h + 0.6), (3.0, 0.5, 0.3)))
    for x in (-2.6, 2.6):
        p.append(rod("2A2A2A", (x, -L, 12.3), (x, L, 16.3), r=0.06, verts=5))
    for k, t in enumerate((0.2, 0.45, 0.7, 0.92)):
        x = -2.6 if k % 2 else 2.6
        y = -L + t * 2 * L
        z = 12.3 + t * 4
        p.append(rod(METAL_DARK, (x, y, z), (x, y, z - 3.2), r=0.06, verts=4))
        p.append(box(BLUE if k % 2 else RED, loc=(x, y, z - 3.4), size=(2.4, 1.0, 0.25)))
        p.append(box(BLUE if k % 2 else RED, loc=(x, y + 0.5, z - 2.8), size=(2.4, 0.2, 1.1)))
        p.append(rod(METAL_DARK, (x - 1.2, y - 0.6, z - 3.0), (x + 1.2, y - 0.6, z - 3.0), r=0.05, verts=4))
    a.part("Body", p, collide=True)
    return a


def snow_igloo(name):
    a = Asset(name, "prop")
    use(a)
    dome = sphere(SNOW, loc=(0, 0, 0), scale=(4.2, 4.2, 3.6), seg=20, rings=12, smooth=False)
    deform(dome, lambda v: Vector((v.x, v.y, max(v.z, 0.0))))
    p = [dome]
    for z in (0.9, 1.8, 2.6, 3.2):
        r = 4.25 * math.sqrt(max(0.0, 1 - (z / 3.6) ** 2))
        p.append(torus(ICE, loc=(0, 0, z), R=r, r=0.06, seg=20, mseg=3))
    tun = cyl(SNOW, r=1.5, h=3.0, rot=(90, 0, 0), verts=12, smooth=False)
    deform(tun, lambda v: Vector((v.x, v.y, max(v.z, -0.5))))
    _rot_place(tun, loc=(0, -4.2, 0.5))
    p.append(tun)
    p.append(cyl("2A3A5A", loc=(0, -5.72, 0.9), r=0.9, h=0.05, rot=(90, 0, 0), verts=12))
    a.part("Body", p, collide=True)
    return a


def snow_snowman(name):
    a = Asset(name, "prop")
    use(a)
    p = [sphere(SNOW, loc=(0, 0, 1.4), scale=1.6, seg=16, rings=10),
         sphere(SNOW, loc=(0, 0, 3.6), scale=1.15, seg=16, rings=10),
         sphere(SNOW, loc=(0, 0, 5.2), scale=0.8, seg=14, rings=8),
         cone("FF8A2A", loc=(0, -1.0, 5.2), r=0.15, h=0.9, rot=(90, 0, 0), verts=8),
         sphere("1B1530", loc=(0.3, -0.7, 5.45), scale=0.1, seg=6, rings=4),
         sphere("1B1530", loc=(-0.3, -0.7, 5.45), scale=0.1, seg=6, rings=4),
         torus(RED, loc=(0, 0, 4.5), R=0.8, r=0.22, seg=14, mseg=6),
         box(RED, loc=(0.6, -0.6, 3.9), size=(0.4, 0.15, 1.2), rot=(10, 0, 20)),
         cyl("2A2A2A", loc=(0, 0, 5.95), r=0.9, h=0.1, verts=14),
         cyl("2A2A2A", loc=(0, 0, 6.5), r=0.6, h=1.0, verts=14),
         torus(RED, loc=(0, 0, 6.1), R=0.6, r=0.06, seg=14, mseg=4)]
    for z in (3.3, 3.8, 4.2):
        p.append(sphere("1B1530", loc=(0, -1.12 + (z - 3.3) * 0.25, z), scale=0.12, seg=6, rings=4))
    for side in (-1, 1):
        p.append(tube(WOOD_DARK, [(side * 1.0, 0, 3.8), (side * 2.0, 0, 4.4), (side * 2.4, 0, 5.0)], 0.08, seg=5))
    a.part("Body", p, collide=True)
    return a


def snow_cocoa(name):
    a = Asset(name, "prop")
    use(a)
    p = [box(WOOD, loc=(0, 0, 1.6), size=(6, 3.4, 3.2)),
         box(WOOD_LIGHT, loc=(0, -1.1, 3.3), size=(6.2, 1.4, 0.2))]
    for x in (-2.9, 2.9):
        p.append(cyl(WOOD_DARK, loc=(x, -1.6, 4.4), r=0.15, h=2.4, verts=6))
        p.append(cyl(WOOD_DARK, loc=(x, 1.6, 4.4), r=0.15, h=2.4, verts=6))
    for k in range(6):
        p.append(box(RED if k % 2 == 0 else WHITE, loc=(-2.5 + k, 0, 5.75), size=(1.0, 4.2, 0.3)))
    p.append(snow_cap((0, 0, 5.9), (3.2, 2.2, 0.35)))
    # big mug sign
    p.append(cyl(WHITE, loc=(0, -1.8, 7.3), r=1.0, h=1.6, rot=(0, 0, 0), verts=14))
    p.append(cyl("6B3A1E", loc=(0, -1.8, 8.1), r=0.85, h=0.05, verts=14))
    p.append(torus(WHITE, loc=(1.1, -1.8, 7.3), R=0.45, r=0.12, rot=(90, 0, 0), seg=12, mseg=6))
    p.append(sphere(WHITE, loc=(0, -1.8, 8.3), scale=(0.5, 0.5, 0.3), seg=8, rings=5))
    p.append(cyl(WOOD_DARK, loc=(0, -1.8, 6.1), r=0.12, h=0.8, verts=6))
    for x in (-1.5, 0, 1.5):
        p.append(cyl(RED, loc=(x, -1.2, 3.55), r=0.2, h=0.4, verts=8))
    a.part("Body", p, collide=True)
    return a


def snow_sled(name):
    a = Asset(name, "prop")
    use(a)
    p = []
    for x in (-0.8, 0.8):
        p.append(tube(RED, [(x, 1.6, 0.1), (x, -1.4, 0.1), (x, -1.9, 0.5), (x, -1.7, 0.8)], 0.08, seg=6))
        for y in (-0.8, 0.8):
            p.append(cyl(RED, loc=(x, y, 0.35), r=0.06, h=0.5, verts=4))
    for k in range(5):
        p.append(box(WOOD if k % 2 else WOOD_LIGHT, loc=(0, -1.0 + k * 0.5, 0.65), size=(2.0, 0.4, 0.12)))
    # a present riding on it
    p.append(box(BLUE, loc=(0, 0.2, 1.2), size=(1.0, 1.0, 0.9)))
    p.append(box(YELLOW, loc=(0, 0.2, 1.2), size=(1.05, 0.2, 0.95)))
    p.append(box(YELLOW, loc=(0, 0.2, 1.2), size=(0.2, 1.05, 0.95)))
    a.part("Body", p, collide=True)
    return a


def snow_frozenpond(name):
    a = Asset(name, "prop")
    use(a)
    ice = cyl(ICE, loc=(0, 0, 0.12), r=1, h=0.2, verts=28)
    deform(ice, lambda v: Vector((v.x * 11, v.y * 8, v.z)))
    p = [ice]
    rnd = random.Random(4)
    for t in range(0, 360, 20):
        x, y = math.cos(math.radians(t)) * 11.5, math.sin(math.radians(t)) * 8.4
        p.append(snow_cap((x, y, 0), (rnd.uniform(1.6, 2.4), rnd.uniform(1.4, 2.0), rnd.uniform(0.6, 1.0))))
    # skating swirls and a bench with skates
    for (x, y, R) in ((-3, 1, 2.2), (2.5, -1.5, 1.6), (4, 2.5, 1.0)):
        p.append(torus(WHITE, loc=(x, y, 0.23), R=R, r=0.04, seg=20, mseg=3))
    p.append(box(WOOD, loc=(0, 10.5, 1.0), size=(4, 0.8, 0.2)))
    for x in (-1.6, 1.6):
        p.append(box(WOOD_DARK, loc=(x, 10.5, 0.5), size=(0.2, 0.7, 1.0)))
    for x in (-0.5, 0.3):
        p.append(box(WHITE, loc=(x, 10.4, 1.35), size=(0.35, 0.8, 0.5)))
        p.append(box(METAL, loc=(x, 10.4, 1.07), size=(0.06, 0.9, 0.08)))
    a.part("Body", p, collide=True)
    return a


ALL = {
    "Park_Fountain": lambda: park_fountain("Park_Fountain"),
    "Park_Playground": lambda: park_playground("Park_Playground"),
    "Park_Gazebo": lambda: park_gazebo("Park_Gazebo"),
    "Park_Picnic": lambda: park_picnic("Park_Picnic"),
    "Park_Lamp": lambda: park_lamp("Park_Lamp"),
    "Park_FlowerBed": lambda: park_flowerbed("Park_FlowerBed"),
    "Park_DuckPond": lambda: park_duckpond("Park_DuckPond"),
    "Beach_Lifeguard": lambda: beach_lifeguard("Beach_Lifeguard"),
    "Beach_HutA": lambda: beach_hut("Beach_HutA", PINK, "D8456A"),
    "Beach_HutB": lambda: beach_hut("Beach_HutB", "6AB8FF", "2F6FC0"),
    "Beach_HutC": lambda: beach_hut("Beach_HutC", YELLOW, "E08A2A"),
    "Beach_IceCream": lambda: beach_icecream("Beach_IceCream"),
    "Beach_Volleyball": lambda: beach_volleyball("Beach_Volleyball"),
    "Beach_Sandcastle": lambda: beach_sandcastle("Beach_Sandcastle"),
    "Beach_Surfboards": lambda: beach_surfboards("Beach_Surfboards"),
    "Beach_Lighthouse": lambda: beach_lighthouse("Beach_Lighthouse"),
    "Beach_Boat": lambda: beach_boat("Beach_Boat"),
    "City_ShopA": lambda: city_shop("City_ShopA", "E8A07A", RED, "tank"),
    "City_ShopB": lambda: city_shop("City_ShopB", "8EC8E8", "2F6FC0", "ac"),
    "City_ShopC": lambda: city_shop("City_ShopC", "F2D98A", "3F9A3A", "garden"),
    "City_ShopD": lambda: city_shop("City_ShopD", "C8A0E0", "8A4AC0", "chimney"),
    "City_BusStop": lambda: city_busstop("City_BusStop"),
    "City_HotDog": lambda: city_hotdog("City_HotDog"),
    "City_Newsstand": lambda: city_newsstand("City_Newsstand"),
    "City_TrafficLight": lambda: city_trafficlight("City_TrafficLight"),
    "City_StreetLamp": lambda: city_streetlamp("City_StreetLamp"),
    "City_Billboard": lambda: city_billboard("City_Billboard"),
    "City_Statue": lambda: city_statue("City_Statue"),
    "Snow_Lodge": lambda: snow_lodge("Snow_Lodge"),
    "Snow_SkiLift": lambda: snow_skilift("Snow_SkiLift"),
    "Snow_Igloo": lambda: snow_igloo("Snow_Igloo"),
    "Snow_Snowman": lambda: snow_snowman("Snow_Snowman"),
    "Snow_Cocoa": lambda: snow_cocoa("Snow_Cocoa"),
    "Snow_Sled": lambda: snow_sled("Snow_Sled"),
    "Snow_FrozenPond": lambda: snow_frozenpond("Snow_FrozenPond"),
}
