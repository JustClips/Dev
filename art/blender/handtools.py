"""Hand tools (asset names Tool_<Id>). Blender axes: the tool's business end points -Y,
up is +Z. Every tool keeps one "Handle" part (plus optional extras) and meta points in
Roblox space (same conversion as grip):
  grip   right hand (set from the TOOLS tuple by props.hand_tool)
  grip2  left hand (two-handed tools only)
  tip    the business end, for VFX (brush head, mop head, nozzles)
Sizes are the real in-game sizes (no auto-rescale): Toothbrush ~3, Broom/Mop ~5,
Leaf Blower ~3, Shop Vac / Turbo Vacuum ~3.5 studs.
"""
import math

from mathutils import Vector

from lib import sphere, box, cyl, cone, torus, capsule, tube, deform
from aliens import shade

DARK, METAL, RUBBER = "2A2A33", "C8C8D2", "3A3A46"


def mark(a, key, p):
    """Meta point in Roblox space (x flips, y<->z), like props.hand_tool's grip."""
    a.extra[key] = [round(-p[0], 3), round(p[2], 3), round(p[1], 3)]


def toothbrush(a):
    import props  # the toothbrush itself lives in props (already reworked)
    props.toothbrush(a)
    mark(a, "tip", (0, -1.25, -0.3))


def broom(a):
    """Push broom on a long wooden stick (about 5 studs): grip wrap, hanging cap, metal
    ferrule, a fanned straw head with two stitch bands and a ragged edge."""
    wood, straw, red = "B4783C", "FFD25A", "D23C3C"
    p = [cyl(wood, loc=(0, 0.45, 0), r=0.09, h=3.9, rot=(90, 0, 0), verts=12)]          # y -1.5 .. 2.4
    p += [torus(shade(wood, -0.18), loc=(0, y, 0), R=0.09, r=0.012, rot=(90, 0, 0), seg=12, mseg=4) for y in (-0.9, -0.2, 2.0)]
    p.append(cyl(RUBBER, loc=(0, 1.25, 0), r=0.105, h=1.5, rot=(90, 0, 0), verts=12))     # grip wrap
    for k in range(6):
        p.append(torus(DARK, loc=(0, 0.6 + k * 0.26, 0), R=0.105, r=0.018, rot=(90, 0, 0), seg=12, mseg=4))
    p.append(cyl(red, loc=(0, 2.45, 0), r=0.12, h=0.14, rot=(90, 0, 0), verts=12))
    p.append(torus(red, loc=(0, 2.6, 0), R=0.1, r=0.03, rot=(0, 90, 0), seg=12, mseg=4))
    p.append(cyl(METAL, loc=(0, -1.6, 0), r=0.15, h=0.35, rot=(90, 0, 0), r2=0.12, verts=12))  # ferrule
    head = cone(straw, loc=(0, -2.15, 0), r=0.85, h=1.0, rot=(-90, 0, 0), verts=18)
    deform(head, lambda v: Vector((v.x, v.y, v.z * 0.32)))
    p.append(head)
    for y, w in ((-1.95, 0.62), (-2.2, 0.98)):
        p.append(box(red, loc=(0, y, 0), size=(w, 0.07, 0.3 * w + 0.06)))
    for i in range(11):
        x = -0.8 + i * 0.16
        p.append(box(shade(straw, -0.15 if i % 2 else 0.08), loc=(x, -2.72, 0), size=(0.08, 0.2, 0.2), rot=(0, 0, (i - 5) * 3)))
    a.part("Handle", p)
    mark(a, "grip2", (0, 1.6, 0))
    mark(a, "tip", (0, -2.65, 0))


def mop(a):
    """String mop (about 5 studs): teal stick with a grip and a hanging cap, a white clamp
    with a teal ring, and thick strands spreading out, with a few soap bubbles stuck on."""
    teal = "5AC8A0"
    p = [cyl(teal, loc=(0, 0.5, 0), r=0.09, h=3.8, rot=(90, 0, 0), verts=12)]            # y -1.4 .. 2.4
    p.append(capsule("2A8C6E", (0, 2.2, 0), (0, 1.0, 0), 0.115))
    p.append(sphere("FFFFFF", loc=(0, 2.45, 0), scale=0.13, seg=12, rings=8))
    p.append(cyl("FFFFFF", loc=(0, -1.55, 0), r=0.24, h=0.35, rot=(90, 0, 0), verts=14))
    p.append(torus(teal, loc=(0, -1.62, 0), R=0.25, r=0.045, rot=(90, 0, 0), seg=14, mseg=4))
    p.append(box(METAL, loc=(0, -1.75, 0.0), size=(0.56, 0.12, 0.2), bevel=0.04))
    for i in range(16):
        ang = math.radians(i * 360 / 16)
        x, z = math.cos(ang) * 0.2, math.sin(ang) * 0.2
        mid = (x * 2.2, -2.15, z * 2.2)
        end = (x * 3.0 + 0.04 * math.sin(i), -2.6, z * 3.0)
        p.append(tube(("E6F5FF", "B4E6F0", "FFD2E6")[i % 3], [(x, -1.7, z), mid, end], 0.07, seg=8))
    for (x, z) in ((0.35, 0.25), (-0.4, -0.1), (0.05, -0.45)):
        p.append(sphere("CDEBFF", loc=(x * 1.6, -2.62, z * 1.6), scale=0.1, seg=10, rings=6))
    a.part("Handle", p)
    mark(a, "grip2", (0, 1.6, 0))
    mark(a, "tip", (0, -2.55, 0))


def leaf_blower(a):
    """Hand-held leaf blower (about 3 studs): engine body with a pull starter, fuel cap and
    vents, a top handle with a trigger, and a blow tube angled forward and down to a flared
    nozzle."""
    o = "FF8C3C"
    p = [box(o, loc=(0, 0.55, 0), size=(0.7, 1.1, 0.75), bevel=0.15)]
    p.append(box("FFFFFF", loc=(0, 0.55, 0), size=(0.72, 0.16, 0.77), bevel=0.05))
    p.append(cyl(RUBBER, loc=(0.38, 0.6, 0), r=0.3, h=0.1, rot=(0, 90, 0), verts=18))           # fan cover
    p += [box(DARK, loc=(0.44, 0.6, k * 0.1), size=(0.04, 0.42, 0.04)) for k in (-1, 0, 1)]
    p.append(cyl("FFD23C", loc=(-0.2, 0.85, 0.4), r=0.1, h=0.1, verts=10))                       # fuel cap
    p.append(box(DARK, loc=(-0.36, 0.3, 0.1), size=(0.06, 0.16, 0.12)))                          # pull starter
    # top handle on two posts, trigger under it
    for y in (0.25, 1.0):
        p.append(cyl(RUBBER, loc=(0, y, 0.48), r=0.07, h=0.24, verts=8))
    p.append(capsule(RUBBER, (0, 0.2, 0.62), (0, 1.05, 0.62), 0.09))
    p.append(box("FF3A4A", loc=(0, 0.45, 0.48), size=(0.08, 0.12, 0.12), bevel=0.02))
    # blow tube: out of the front of the body, angled down, with bands and a flared nozzle
    t0, t1 = Vector((0, 0.05, -0.15)), Vector((0, -1.85, -0.8))
    p.append(tube(RUBBER, [tuple(t0), tuple(t1)], 0.16, seg=12))
    d = (t1 - t0).normalized()
    ang = math.degrees(math.atan2(-d.z, -d.y))
    for f in (0.3, 0.7):
        q = t0 + (t1 - t0) * f
        p.append(torus(o, loc=tuple(q), R=0.17, r=0.03, rot=(90 + ang, 0, 0), seg=14, mseg=4))
    nz = t1 + d * 0.12
    p.append(cyl(o, loc=tuple(nz), r=0.17, r2=0.26, h=0.3, rot=(90 + ang, 0, 0), verts=14))
    a.part("Handle", p)
    mark(a, "grip2", tuple(t0 + (t1 - t0) * 0.5))
    mark(a, "tip", tuple(t1 + d * 0.3))


def shop_vac(a):
    """Shop vacuum (about 3.5 studs) carried at the hip: canister on caster wheels with a
    lid and clips, a top carry handle, a ribbed hose to a metal wand angled forward and
    down, and a wide floor nozzle."""
    y = "FFD23C"
    p = [cyl(y, loc=(0, 0.9, -0.15), r=0.45, h=1.0, rot=(90, 0, 0), verts=20)]                  # canister y 0.4..1.4
    p.append(cyl(RUBBER, loc=(0, 0.85, -0.15), r=0.46, h=0.22, rot=(90, 0, 0), verts=20))
    p.append(cyl(RUBBER, loc=(0, 1.45, -0.15), r=0.47, h=0.14, rot=(90, 0, 0), verts=20))        # lid
    for x in (-1, 1):
        p.append(box(DARK, loc=(x * 0.47, 1.3, -0.15), size=(0.06, 0.2, 0.14)))                  # clips
        p.append(sphere(DARK, loc=(x * 0.3, 1.0, -0.62), scale=(0.08, 0.1, 0.1), seg=10, rings=6))  # casters
        p.append(cyl(METAL, loc=(x * 0.3, 1.0, -0.53), r=0.03, h=0.12, verts=6))
    for y_ in (0.55, 1.25):
        p.append(cyl(RUBBER, loc=(0, y_, 0.36), r=0.06, h=0.2, verts=8))
    p.append(capsule(RUBBER, (0, 0.5, 0.48), (0, 1.3, 0.48), 0.09))
    # hose from the canister's front, curling round to the wand
    hose = [(0.0, 0.42, -0.1), (0.25, 0.1, 0.0), (0.3, -0.25, -0.2), (0.12, -0.5, -0.38)]
    p.append(tube("5A5A6E", hose, 0.08, seg=10))
    for k in range(1, 3):
        p.append(sphere("4A4A5A", loc=hose[k], scale=0.1, seg=8, rings=6))
    w0, w1 = Vector((0.12, -0.5, -0.38)), Vector((0.0, -2.0, -0.95))
    p.append(tube(METAL, [tuple(w0), tuple(w1)], 0.08, seg=10))
    p.append(box(RUBBER, loc=(0.0, -2.08, -1.0), size=(1.0, 0.35, 0.22), bevel=0.06))
    p.append(box(y, loc=(0.0, -2.08, -1.12), size=(0.95, 0.25, 0.06)))
    a.part("Handle", p)
    mark(a, "grip2", tuple(w0 + (w1 - w0) * 0.45))
    mark(a, "tip", (0.0, -2.1, -1.12))


def turbo_vacuum(a):
    """Turbo vacuum (about 3.5 studs): a sleek motor pod with fins and a dust chamber, top
    handle, a long barrel angled forward and down with glowing rings, and a wide mouth."""
    pc, g = "B45AFF", "5AFFF0"
    p = [capsule(pc, (0, 1.3, -0.1), (0, 0.25, -0.1), 0.42)]                                    # motor pod
    p += [box(shade(pc, -0.3), loc=(s * 0.45, 1.05, -0.1), size=(0.12, 0.65, 0.55), bevel=0.04) for s in (-1, 1)]
    p.append(cyl("C8F0FF", loc=(0, 0.75, 0.25), r=0.22, h=0.25, verts=16))                     # dust chamber
    p.append(cyl(DARK, loc=(0, 0.75, 0.39), r=0.24, h=0.04, verts=16))
    for y_ in (0.4, 1.2):
        p.append(cyl(DARK, loc=(0, y_, 0.42), r=0.06, h=0.26, verts=8))
    p.append(capsule(DARK, (0, 0.35, 0.56), (0, 1.25, 0.56), 0.09))
    b0, b1 = Vector((0, -0.05, -0.15)), Vector((0, -1.55, -0.7))
    p.append(tube(DARK, [tuple(b0), tuple(b1)], 0.17, seg=14))
    d = (b1 - b0).normalized()
    ang = math.degrees(math.atan2(-d.z, -d.y))
    mouth = b1 + d * 0.12
    p.append(cyl(pc, loc=tuple(mouth), r=0.24, r2=0.42, h=0.35, rot=(90 + ang, 0, 0), verts=16))
    a.part("Handle", p)
    glow = [torus(g, loc=(0, y_, -0.1), R=0.44, r=0.04, rot=(90, 0, 0), seg=20, mseg=6) for y_ in (0.55, 1.0)]
    for f in (0.35, 0.7):
        q = b0 + (b1 - b0) * f
        glow.append(torus(g, loc=tuple(q), R=0.18, r=0.035, rot=(90 + ang, 0, 0), seg=16, mseg=6))
    glow.append(torus(g, loc=tuple(mouth + d * 0.17), R=0.4, r=0.04, rot=(90 + ang, 0, 0), seg=20, mseg=6))
    a.part("Handle_Glow", glow, parent="Handle", glow=g)
    mark(a, "grip2", tuple(b0 + (b1 - b0) * 0.45))
    mark(a, "tip", tuple(mouth + d * 0.2))


# name -> (builder, right-hand grip in Blender coords)
TOOLS = {
    "Toothbrush": (toothbrush, (0, 0.85, 0)),
    "Broom": (broom, (0, 0.4, 0)),
    "Mop": (mop, (0, 0.4, 0)),
    "LeafBlower": (leaf_blower, (0, 0.62, 0.62)),
    "ShopVac": (shop_vac, (0, 0.9, 0.48)),
    "TurboVacuum": (turbo_vacuum, (0, 0.8, 0.56)),
}
