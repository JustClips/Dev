"""Earth props for Sweep the World. They replace the old Moon props under the same asset
names, so the map code keeps placing them where it did:

  hub rocks        Rock_Moon1-3   -> mossy grey rocks
  hub / Park       Crystal_Blue   -> flower patch
  Park             Rock_Crater1-2 -> round bushes
  City             Rock_Dark1-2   -> trash can, dumpster; Crystal_Purple -> fire hydrant
  City + base park Mushroom_Glow  -> park bench
  Beach            Rock_Mars1-2   -> sandy rocks with shells; Crystal_Red -> palm tree;
                   Mushroom_Mars  -> beach umbrella
  Snowy Peaks      Rock_Ice1-2    -> snow-capped rocks; Crystal_Ice -> snowy pine
  base parks       Tree_Bulb/Puff/Tall -> oak, round tree, apple tree; Pond -> water pond
  hub edges        Satellite      -> wooden windmill
  zone gates       ZoneGate       -> wooden gate
"""
import math
import random
from mathutils import Vector
from lib import Asset, use, sphere, ico, box, cyl, cone, torus, tube, deform, noise_deform
from props import WOOD, WOOD_DARK, WOOD_LIGHT

LEAF, LEAF_DARK, LEAF_LIGHT = "5DBB4A", "3F9A3A", "86D45E"
BARK = "7A5232"


def _lumpy_rock(col, seed, size, sub=3, rough=0.25):
    r = ico(col, loc=(0, 0, size[2] * 0.45), scale=size, sub=sub, smooth=False)
    noise_deform(r, rough * min(size), seed=seed, freq=0.6 / max(0.5, min(size) / 2))
    deform(r, lambda v: Vector((v.x, v.y, max(v.z, 0.0))))
    return r


def mossy_rock(name, seed, size):
    a = Asset(name, "prop")
    use(a)
    r = _lumpy_rock("9C9C94", seed, size)
    top = max(v.co.z for v in r.data.vertices)
    moss = sphere(LEAF_DARK, loc=(size[0] * 0.1, 0, top - size[2] * 0.12), scale=(size[0] * 0.55, size[1] * 0.5, size[2] * 0.22), seg=14, rings=7)
    deform(moss, lambda v: Vector((v.x, v.y, max(v.z, top - size[2] * 0.25))))
    a.part("Body", [r, moss], collide=True)
    return a


def sandy_rock(name, seed, size):
    a = Asset(name, "prop")
    use(a)
    rnd = random.Random(seed)
    r = _lumpy_rock("D8C08E", seed, size, rough=0.2)
    shells = []
    for _ in range(3):
        ang = rnd.uniform(0, 360)
        x, y = math.cos(math.radians(ang)) * size[0] * 0.95, math.sin(math.radians(ang)) * size[1] * 0.95
        sh = sphere(rnd.choice(("FFC8B4", "FFF0DC", "F5A0A0")), loc=(x, y, 0.15), scale=(0.35, 0.3, 0.18), seg=10, rings=6)
        shells.append(sh)
    a.part("Body", [r] + shells, collide=True)
    return a


def snowy_rock(name, seed, size):
    a = Asset(name, "prop")
    use(a)
    r = _lumpy_rock("8A8E96", seed, size)
    top = max(v.co.z for v in r.data.vertices)
    cap = sphere("F4F8FC", loc=(0, 0, top - size[2] * 0.2), scale=(size[0] * 0.8, size[1] * 0.75, size[2] * 0.35), seg=16, rings=8)
    deform(cap, lambda v: Vector((v.x, v.y, max(v.z, top - size[2] * 0.4))))
    noise_deform(cap, 0.08 * min(size), seed=seed + 50, freq=0.8)
    a.part("Body", [r, cap], collide=True)
    return a


def bush(name, seed, size, flowers=True):
    a = Asset(name, "prop")
    use(a)
    rnd = random.Random(seed)
    p = []
    for i in range(5):
        ang = i * 72 + rnd.uniform(-15, 15)
        rr = size * 0.45 if i else 0
        p.append(sphere(LEAF if i % 2 else LEAF_DARK, loc=(math.cos(math.radians(ang)) * rr, math.sin(math.radians(ang)) * rr, size * 0.55),
                        scale=size * rnd.uniform(0.55, 0.7), seg=14, rings=8))
    p.append(sphere(LEAF_LIGHT, loc=(0, 0, size * 0.95), scale=size * 0.55, seg=14, rings=8))
    for s in p:
        deform(s, lambda v: Vector((v.x, v.y, max(v.z, 0.0))))
    if flowers:
        for _ in range(8):
            ang = rnd.uniform(0, 360)
            el = rnd.uniform(20, 70)
            d = size * 0.9
            x = math.cos(math.radians(ang)) * math.cos(math.radians(el)) * d
            y = math.sin(math.radians(ang)) * math.cos(math.radians(el)) * d
            z = size * 0.6 + math.sin(math.radians(el)) * d * 0.7
            p.append(sphere(rnd.choice(("FF6E8C", "FFFFFF", "FFD94A")), loc=(x, y, z), scale=size * 0.09, seg=8, rings=5))
    a.part("Body", p, collide=True)
    return a


def flower_patch(name, seed):
    a = Asset(name, "prop")
    use(a)
    rnd = random.Random(seed)
    p = [cyl("6B4A2E", loc=(0, 0, 0.1), r=1.7, h=0.2, verts=20)]
    for _ in range(14):
        ang = rnd.uniform(0, 360)
        rr = rnd.uniform(0, 1.4)
        x, y = math.cos(math.radians(ang)) * rr, math.sin(math.radians(ang)) * rr
        h = rnd.uniform(0.6, 1.2)
        p.append(cyl(LEAF_DARK, loc=(x, y, h / 2), r=0.05, h=h, verts=6))
        col = rnd.choice(("FF5A78", "FFD94A", "B47AFF", "FFFFFF", "FF8C3C"))
        for k in range(5):
            pa = k * 72
            p.append(sphere(col, loc=(x + math.cos(math.radians(pa)) * 0.16, y + math.sin(math.radians(pa)) * 0.16, h), scale=(0.13, 0.13, 0.06), seg=8, rings=5))
        p.append(sphere("FFE36E" if col != "FFD94A" else "FF8C3C", loc=(x, y, h + 0.03), scale=0.08, seg=8, rings=5))
        p.append(sphere(LEAF, loc=(x + 0.12, y, h * 0.45), scale=(0.18, 0.08, 0.05), seg=8, rings=4))
    a.part("Body", p, collide=True)
    return a


def leafy_tree(name, seed, h=8, crown=3.2, fruit=None, shape="round"):
    a = Asset(name, "prop")
    use(a)
    rnd = random.Random(seed)
    trunk = tube(BARK, [(0, 0, 0), (0.15, 0.05, h * 0.4), (-0.1, 0.1, h * 0.75)], lambda i: 0.65 - i * 0.15, seg=10)
    roots = [cone(BARK, loc=(math.cos(math.radians(t)) * 0.5, math.sin(math.radians(t)) * 0.5, 0.3), r=0.35, h=0.8, verts=8,
                  rot=(0, 50, t)) for t in (20, 140, 260)]
    leaves = []
    if shape == "round":
        leaves.append(sphere(LEAF, loc=(0, 0, h), scale=crown, seg=16, rings=10))
        for i in range(5):
            ang = i * 72 + rnd.uniform(-20, 20)
            leaves.append(sphere(LEAF_DARK if i % 2 else LEAF_LIGHT,
                                 loc=(math.cos(math.radians(ang)) * crown * 0.7, math.sin(math.radians(ang)) * crown * 0.7, h - crown * 0.25 + rnd.uniform(0, 0.8)),
                                 scale=crown * rnd.uniform(0.55, 0.7), seg=14, rings=8))
    else:  # tall oval
        leaves.append(sphere(LEAF_DARK, loc=(0, 0, h + 0.5), scale=(crown * 0.8, crown * 0.8, crown * 1.4), seg=16, rings=10))
        leaves.append(sphere(LEAF, loc=(0.4, -0.3, h + 1.2), scale=(crown * 0.6, crown * 0.6, crown * 1.0), seg=14, rings=8))
    extra = []
    if fruit:
        for _ in range(9):
            ang = rnd.uniform(0, 360)
            el = rnd.uniform(-20, 40)
            d = crown * 1.05
            extra.append(sphere(fruit, loc=(math.cos(math.radians(ang)) * math.cos(math.radians(el)) * d,
                                            math.sin(math.radians(ang)) * math.cos(math.radians(el)) * d,
                                            h + math.sin(math.radians(el)) * d), scale=0.28, seg=10, rings=6))
    a.part("Body", [trunk] + roots + leaves + extra, collide=True)
    return a


def pine(name, seed, snowy=True):
    a = Asset(name, "prop")
    use(a)
    p = [cyl(BARK, loc=(0, 0, 1.0), r=0.45, h=2.0, verts=10)]
    tiers = ((3.2, 2.6, 1.6), (2.5, 2.4, 3.3), (1.8, 2.2, 4.9), (1.1, 1.9, 6.4))
    for r, h, z in tiers:
        p.append(cone("2F7A45", loc=(0, 0, z + h / 2), r=r, h=h, verts=12, smooth=False))
        if snowy:
            sn = cone("F4F8FC", loc=(0, 0, z + h / 2 + 0.25), r=r * 0.8, h=h * 0.8, verts=12, smooth=False)
            deform(sn, lambda v, zz=z + h * 0.55: Vector((v.x * 1.04, v.y * 1.04, max(v.z, zz))))
            p.append(sn)
    a.part("Body", p, collide=True)
    return a


def _place(obj, rot=(0, 0, 0), loc=(0, 0, 0)):
    """Rotate an object (degrees, about its origin) then move it, baking both into the mesh."""
    import bpy
    from mathutils import Euler, Matrix
    m = Matrix.Translation(loc) @ Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
    obj.data.transform(m)
    obj.data.update()
    return obj


def palm(name, seed):
    a = Asset(name, "prop")
    use(a)
    rnd = random.Random(seed)
    pts = [(0, 0, 0), (0.4, 0, 2.5), (1.1, 0, 5), (2.0, 0, 7.2)]
    trunk = tube("B98A5A", pts, lambda i: 0.5 - i * 0.08, seg=10)
    rings = [torus("8C6440", loc=(0.4 * t / 2.5 if t < 2.5 else 0.4 + 0.7 * (t - 2.5) / 2.5, 0, t), R=0.47 - t * 0.02, r=0.08, seg=12, mseg=4)
             for t in (1.0, 2.0, 3.0, 4.0)]
    top = Vector(pts[-1])
    leaves = []
    for i in range(7):
        ang = i * (360 / 7) + rnd.uniform(-10, 10)
        for seg_i, (dist, drop, size) in enumerate(((1.0, 0.15, 1.2), (2.3, -0.25, 1.1), (3.4, -0.95, 0.8))):
            lf = sphere(LEAF if (i + seg_i) % 2 else LEAF_DARK, loc=(0, 0, 0), scale=(size, 0.55 * size, 0.1), seg=12, rings=6)
            _place(lf, rot=(0, 15 + seg_i * 20, ang), loc=(top.x + math.cos(math.radians(ang)) * dist,
                                                         top.y + math.sin(math.radians(ang)) * dist, top.z + drop))
            leaves.append(lf)
    nuts = [sphere("6B4A2E", loc=(top.x + math.cos(math.radians(t)) * 0.35, math.sin(math.radians(t)) * 0.35, top.z - 0.35), scale=0.3, seg=10, rings=6)
            for t in (0, 120, 240)]
    a.part("Body", [trunk] + rings + leaves + nuts, collide=True)
    return a


def umbrella(name):
    a = Asset(name, "prop")
    use(a)
    p = [cyl("F4F4F4", loc=(0, 0, 2.2), r=0.1, h=4.4, verts=8)]
    for k in range(8):
        wedge = cone("FF5A5A" if k % 2 == 0 else "FFFFFF", loc=(0, 0, 4.5), r=3.2, h=1.2, verts=24, smooth=False)
        lo, hi = math.radians(k * 45), math.radians((k + 1) * 45)

        def clip(v, lo=lo, hi=hi):
            ang = math.atan2(v.y, v.x) % (2 * math.pi)
            if lo <= ang <= hi or v.length < 1e-6:
                return v
            # pull vertices outside this wedge onto its nearest edge
            edge = lo if abs((ang - lo + math.pi) % (2 * math.pi) - math.pi) < abs((ang - hi + math.pi) % (2 * math.pi) - math.pi) else hi
            r = math.hypot(v.x, v.y)
            return Vector((math.cos(edge) * r, math.sin(edge) * r, v.z))
        deform(wedge, clip)
        p.append(wedge)
    p.append(torus("FF5A5A", loc=(0, 0, 3.92), R=3.15, r=0.08, seg=24, mseg=4))
    p.append(sphere("FFFFFF", loc=(0, 0, 5.15), scale=0.18, seg=8, rings=5))
    # towel and a bucket underneath
    p.append(box("4AA8FF", loc=(1.2, -0.6, 0.03), size=(1.6, 3.0, 0.06)))
    p.append(box("FFFFFF", loc=(1.2, -0.6, 0.04), size=(1.6, 0.4, 0.07)))
    p.append(cyl("FFD94A", loc=(-1.4, 0.8, 0.35), r=0.4, r2=0.5, h=0.7, verts=12))
    a.part("Body", p, collide=True)
    return a


def bench(name):
    a = Asset(name, "prop")
    use(a)
    p = []
    for x in (-1.6, 1.6):
        p.append(box("3A3F4A", loc=(x, 0, 0.6), size=(0.2, 1.4, 1.2), bevel=0.04))
        p.append(box("3A3F4A", loc=(x, 0.6, 1.5), size=(0.2, 0.2, 1.6), bevel=0.04, rot=(-10, 0, 0)))
    for k in range(3):
        p.append(box(WOOD if k % 2 else WOOD_LIGHT, loc=(0, -0.45 + k * 0.45, 1.2), size=(4.0, 0.38, 0.14), bevel=0.04))
    for k in range(2):
        p.append(box(WOOD if k % 2 else WOOD_LIGHT, loc=(0, 0.72, 1.75 + k * 0.5), size=(4.0, 0.14, 0.36), bevel=0.04, rot=(-10, 0, 0)))
    a.part("Body", p, collide=True)
    return a


def trash_can(name):
    a = Asset(name, "prop")
    use(a)
    p = [cyl("7A8496", loc=(0, 0, 1.1), r=0.75, r2=0.85, h=2.2, verts=16)]
    for z in (0.5, 1.1, 1.7):
        p.append(torus("5E6878", loc=(0, 0, z), R=0.82, r=0.05, seg=16, mseg=4))
    p.append(cyl("5E6878", loc=(0, 0, 2.3), r=0.92, r2=0.7, h=0.25, verts=16))
    p.append(cyl("5E6878", loc=(0, 0, 2.5), r=0.12, h=0.2, verts=8))
    p.append(box("F4F4F4", loc=(0.2, -0.3, 2.45), size=(0.5, 0.4, 0.06), rot=(0, 0, 25)))
    a.part("Body", p, collide=True)
    return a


def dumpster(name):
    a = Asset(name, "prop")
    use(a)
    p = [box("3F8F4E", loc=(0, 0, 1.4), size=(5.0, 2.8, 2.4), bevel=0.15)]
    p.append(box("2F6F3C", loc=(0, 0, 2.68), size=(5.1, 2.9, 0.2), bevel=0.05))
    for x in (-2.0, 2.0):
        p.append(cyl("2A2A2A", loc=(x, -1.1, 0.25), r=0.25, h=0.25, rot=(0, 90, 0), verts=10))
        p.append(cyl("2A2A2A", loc=(x, 1.1, 0.25), r=0.25, h=0.25, rot=(0, 90, 0), verts=10))
    p.append(box("F4F4F4", loc=(0, -1.42, 1.6), size=(1.8, 0.05, 0.6)))
    p.append(sphere("3A3A3A", loc=(-1.0, 0.4, 3.05), scale=(0.6, 0.5, 0.4), seg=10, rings=6))
    a.part("Body", p, collide=True)
    return a


def hydrant(name):
    a = Asset(name, "prop")
    use(a)
    red = "E8463C"
    p = [cyl(red, loc=(0, 0, 0.12), r=0.55, h=0.24, verts=14),
         cyl(red, loc=(0, 0, 0.9), r=0.38, h=1.4, verts=14),
         sphere(red, loc=(0, 0, 1.6), scale=(0.42, 0.42, 0.32), seg=14, rings=8),
         cyl("FFD94A", loc=(0, 0, 1.95), r=0.12, h=0.25, verts=8),
         torus("C0392F", loc=(0, 0, 1.45), R=0.4, r=0.06, seg=14, mseg=4)]
    for ang in (0, 180, 270):
        x, y = math.cos(math.radians(ang)), math.sin(math.radians(ang))
        p.append(cyl("FFD94A" if ang == 270 else red, loc=(x * 0.5, y * 0.5, 1.05), r=0.16, h=0.3,
                     rot=(90 if ang in (90, 270) else 0, 0 if ang in (90, 270) else 90, 0), verts=10))
    a.part("Body", p, collide=True)
    return a


def windmill(name):
    a = Asset(name, "prop")
    use(a)
    p = [cyl(WOOD_LIGHT, loc=(0, 0, 3.5), r=2.0, r2=1.4, h=7, verts=8, smooth=False),
         cone("C0504A", loc=(0, 0, 7.8), r=1.8, h=1.8, verts=8, smooth=False),
         box(WOOD_DARK, loc=(0, -1.85, 1.0), size=(1.0, 0.3, 2.0)),
         cyl(WOOD_DARK, loc=(0, -1.85, 6.6), r=0.25, h=0.8, rot=(90, 0, 0), verts=8)]
    a.part("Body", p, collide=True)
    # the sails are their own part so the game can spin them about the hub (meta joint)
    sails = [cyl(WOOD_DARK, loc=(0, -2.3, 6.6), r=0.35, h=0.3, rot=(90, 0, 0), verts=8)]
    for k in range(4):
        ang = k * 90 + 20
        c, s = math.cos(math.radians(ang)), math.sin(math.radians(ang))
        sails.append(box(WOOD_DARK, loc=(c * 1.9, -2.3, 6.6 + s * 1.9), size=(3.8, 0.12, 0.2), rot=(0, -ang, 0)))
        sails.append(box("F4EEDC", loc=(c * 2.2, -2.32, 6.6 + s * 2.2), size=(2.8, 0.06, 0.9), rot=(0, -ang, 0)))
    a.part("Sails", sails, joint=(0, -2.3, 6.6))
    return a


def water_pond(name):
    a = Asset(name, "prop")
    use(a)
    rim = [ico("8E8C88", loc=(math.cos(math.radians(t)) * 7, math.sin(math.radians(t)) * 5, 0.3), scale=(1.4, 1.1, 0.8), sub=1)
           for t in range(0, 360, 24)]
    water = cyl("4AA8E8", loc=(0, 0, 0.12), r=1, h=0.2, verts=32)
    deform(water, lambda v: Vector((v.x * 6.6, v.y * 4.6, v.z)))
    pads = [cyl("5DBB4A", loc=(x, y, 0.24), r=0.7, h=0.05, verts=12) for x, y in ((-2.5, 1.0), (1.8, -1.6), (3.0, 1.8))]
    flower = sphere("FF8CB4", loc=(1.8, -1.6, 0.4), scale=(0.25, 0.25, 0.15), seg=8, rings=5)
    reeds = [cyl(LEAF_DARK, loc=(-5.2 + k * 0.25, 2.6, 0.9), r=0.06, h=1.8, verts=6) for k in range(4)]
    a.part("Body", rim + [water] + pads + [flower] + reeds, collide=True)
    return a


def wooden_gate(name):
    a = Asset(name, "prop")
    use(a)
    p = []
    for x in (-13, 13):
        p.append(box("9C9C94", loc=(x, 0, 0.6), size=(4.6, 4.6, 1.2), bevel=0.3))
        p.append(cyl(WOOD_DARK, loc=(x, 0, 8), r=1.5, h=14, verts=12))
        for z in (3, 7, 11):
            p.append(torus(WOOD_LIGHT, loc=(x, 0, z), R=1.52, r=0.12, seg=16, mseg=4))
    p.append(box(WOOD, loc=(0, 0, 15.5), size=(31, 2.4, 2.2), bevel=0.3))
    p.append(box(WOOD_DARK, loc=(0, 0, 16.8), size=(32, 2.8, 0.5), bevel=0.15))
    for x in (-10, 10):
        p.append(box(WOOD_LIGHT, loc=(x, 0, 13.3), size=(4.5, 0.5, 0.5), rot=(0, 40 if x < 0 else -40, 0), bevel=0.1))
    # sign board on the front of the beam (text added in game)
    p.append(box(WOOD_DARK, loc=(0, -1.35, 15.5), size=(16, 0.3, 2.4), bevel=0.1))
    p.append(box("FFF4DE", loc=(0, -1.52, 15.5), size=(15.2, 0.06, 1.8)))
    for x in (-13, 13):
        p.append(sphere(LEAF, loc=(x, 0, 15.6), scale=(1.8, 1.8, 1.2), seg=12, rings=8))
    a.part("Body", p, collide=True)
    a.extra["sign"] = [0, 15.5, -1.8]
    return a


ALL = {
    "Rock_Moon1": lambda: mossy_rock("Rock_Moon1", 1, (3.2, 2.6, 2.0)),
    "Rock_Moon2": lambda: mossy_rock("Rock_Moon2", 2, (6, 4.5, 3.4)),
    "Rock_Moon3": lambda: mossy_rock("Rock_Moon3", 3, (1.6, 1.4, 1.1)),
    "Rock_Crater1": lambda: bush("Rock_Crater1", 4, 1.8),
    "Rock_Crater2": lambda: bush("Rock_Crater2", 5, 2.8, flowers=False),
    "Crystal_Blue": lambda: flower_patch("Crystal_Blue", 11),
    "Rock_Dark1": lambda: trash_can("Rock_Dark1"),
    "Rock_Dark2": lambda: dumpster("Rock_Dark2"),
    "Crystal_Purple": lambda: hydrant("Crystal_Purple"),
    "Mushroom_Glow": lambda: bench("Mushroom_Glow"),
    "Rock_Mars1": lambda: sandy_rock("Rock_Mars1", 8, (4, 3.2, 2.6)),
    "Rock_Mars2": lambda: sandy_rock("Rock_Mars2", 9, (7.5, 5, 4.5)),
    "Crystal_Red": lambda: palm("Crystal_Red", 13),
    "Mushroom_Mars": lambda: umbrella("Mushroom_Mars"),
    "Rock_Ice1": lambda: snowy_rock("Rock_Ice1", 14, (4, 3.2, 2.6)),
    "Rock_Ice2": lambda: snowy_rock("Rock_Ice2", 15, (7, 5, 4.2)),
    "Crystal_Ice": lambda: pine("Crystal_Ice", 16),
    "Tree_Bulb": lambda: leafy_tree("Tree_Bulb", 21, h=7, crown=3.0),
    "Tree_Puff": lambda: leafy_tree("Tree_Puff", 22, h=8, crown=2.6, shape="tall"),
    "Tree_Tall": lambda: leafy_tree("Tree_Tall", 23, h=8, crown=3.2, fruit="E8463C"),
    "Pond": lambda: water_pond("Pond"),
    "Satellite": lambda: windmill("Satellite"),
    "ZoneGate": lambda: wooden_gate("ZoneGate"),
}
