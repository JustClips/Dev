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

from lib import sphere, ico, box, cyl, cone, torus, capsule, tube, deform
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


# --- tools added 2026-10-31 (16-tool ladder) -------------------------------------------
# Long two-handed tools share the broom layout: stick from y -1.5 to 2.4, right hand at
# y 0.4, left hand at y 1.6, business end around y -2.6. Hip tools share the blower layout:
# body around y 0.2..1.4 with a top handle at z ~0.6, a tube forward and down to the tip.

def _stick(color, grip, cap, y0=-1.5, y1=2.4, r=0.09):
    """A long handle with a rubber grip wrap, rings and an end cap (broom layout)."""
    mid, h = (y0 + y1) / 2, y1 - y0
    p = [cyl(color, loc=(0, mid, 0), r=r, h=h, rot=(90, 0, 0), verts=12)]
    p.append(cyl(grip, loc=(0, 1.25, 0), r=r + 0.015, h=1.5, rot=(90, 0, 0), verts=12))
    for k in range(5):
        p.append(torus(shade(grip, -0.35), loc=(0, 0.65 + k * 0.3, 0), R=r + 0.015, r=0.016, rot=(90, 0, 0), seg=12, mseg=4))
    p.append(sphere(cap, loc=(0, y1 + 0.05, 0), scale=(r + 0.04, 0.09, r + 0.04), seg=12, rings=8))
    return p


def rake(a):
    """Leaf rake (about 5 studs): wooden stick, green grip, a bright green fan of springy tines
    spreading from a metal collar, held together by a cross brace."""
    wood, green = "C08A50", "4CC85A"
    p = _stick(wood, "2E7D3A", "FFD23C", y0=-1.3)
    p.append(cyl(METAL, loc=(0, -1.4, 0), r=0.13, h=0.3, rot=(90, 0, 0), r2=0.1, verts=12))
    n = 13
    for i in range(n):
        f = (i - (n - 1) / 2) / ((n - 1) / 2)              # -1 .. 1
        x_end = f * 1.05
        y_end = -2.55 + 0.25 * f * f                        # fan edge curves back at the sides
        pts = [(f * 0.08, -1.5, 0), (f * 0.55, -2.05, 0.02), (x_end, y_end, 0.0), (x_end * 1.02, y_end - 0.12, -0.12)]
        p.append(tube(green if i % 2 else shade(green, 0.18), pts, 0.035, seg=6))
    brace = [((f / 6) * 0.75, -2.05 + 0.05 * (f / 6) ** 2, 0.03) for f in range(-6, 7)]
    p.append(tube(shade(green, -0.3), brace, 0.03, seg=6))
    a.part("Handle", p)
    mark(a, "grip2", (0, 1.6, 0))
    mark(a, "tip", (0, -2.6, -0.1))


def push_broom(a):
    """Wide push broom (about 5 studs): red stick, a long wooden block head with a brace from
    the stick, and a thick row of dark bristles."""
    red, wood, bristle = "E04848", "D2A064", "3A3530"
    p = _stick(red, RUBBER, "FFFFFF", y0=-1.9)
    p.append(cyl(METAL, loc=(0, -1.95, 0.0), r=0.13, h=0.25, rot=(90, 0, 0), verts=12))
    p.append(box(wood, loc=(0, -2.2, 0), size=(2.2, 0.32, 0.26), bevel=0.06))
    p.append(box(shade(wood, -0.25), loc=(0, -2.2, 0.14), size=(2.0, 0.2, 0.04)))
    for s in (-1, 1):  # brace from stick to head
        p.append(tube(METAL, [(0, -1.5, 0), (s * 0.7, -2.05, 0.05)], 0.035, seg=6))
    for i in range(22):
        x = -1.02 + i * (2.04 / 21)
        p.append(box(shade(bristle, 0.12 if i % 2 else 0.0), loc=(x, -2.48, 0), size=(0.09, 0.32, 0.2), rot=(0, 0, (i % 3 - 1) * 4)))
    a.part("Handle", p)
    mark(a, "grip2", (0, 1.6, 0))
    mark(a, "tip", (0, -2.62, 0))


def leaf_vac(a):
    """Garden leaf vacuum (hip tool, about 3.5 studs): green motor body with a fat collection
    bag hanging under it, a top handle and a wide suction tube angled to the ground."""
    g, bag = "58B848", "C8A060"
    p = [box(g, loc=(0, 0.75, 0), size=(0.7, 1.0, 0.7), bevel=0.18)]
    p.append(cyl(DARK, loc=(0.37, 0.75, 0), r=0.26, h=0.08, rot=(0, 90, 0), verts=16))
    p += [box(shade(g, -0.3), loc=(0.42, 0.75, k * 0.1), size=(0.04, 0.36, 0.04)) for k in (-1, 0, 1)]
    p.append(sphere(bag, loc=(0, 0.95, -0.55), scale=(0.42, 0.55, 0.38), seg=16, rings=10))      # bag
    p.append(torus(shade(bag, -0.3), loc=(0, 0.95, -0.55), R=0.4, r=0.03, rot=(0, 90, 0), seg=16, mseg=4))
    p.append(cyl(shade(bag, -0.35), loc=(0, 0.45, -0.38), r=0.12, h=0.25, rot=(90, 0, 0), verts=10))
    for y in (0.35, 1.1):
        p.append(cyl(RUBBER, loc=(0, y, 0.45), r=0.07, h=0.22, verts=8))
    p.append(capsule(RUBBER, (0, 0.3, 0.6), (0, 1.15, 0.6), 0.09))
    p.append(box("FFD23C", loc=(0, 0.55, 0.47), size=(0.08, 0.12, 0.12), bevel=0.02))
    t0, t1 = Vector((0, 0.2, -0.1)), Vector((0, -1.7, -0.85))
    p.append(tube(g, [tuple(t0), tuple(t1)], 0.2, seg=14))
    d = (t1 - t0).normalized()
    ang = math.degrees(math.atan2(-d.z, -d.y))
    for f in (0.25, 0.55, 0.85):
        q = t0 + (t1 - t0) * f
        p.append(torus(shade(g, -0.35), loc=tuple(q), R=0.21, r=0.03, rot=(90 + ang, 0, 0), seg=14, mseg=4))
    mouth = t1 + d * 0.12
    p.append(cyl(DARK, loc=tuple(mouth), r=0.21, r2=0.3, h=0.26, rot=(90 + ang, 0, 0), verts=16))
    a.part("Handle", p)
    mark(a, "grip2", tuple(t0 + (t1 - t0) * 0.5))
    mark(a, "tip", tuple(mouth + d * 0.18))


def pressure_washer(a):
    """Pressure washer gun (hip tool, about 3.5 studs): a blue pump block with a little water
    tank and gauge, a pistol handle, and a long steel lance angled down to a yellow nozzle."""
    blue, yel = "3C8CFF", "FFD23C"
    p = [box(blue, loc=(0, 0.8, -0.05), size=(0.62, 1.05, 0.62), bevel=0.14)]
    p.append(cyl("BFE6FF", loc=(0, 1.0, 0.33), r=0.2, h=0.18, verts=14))                     # tank
    p.append(cyl(blue, loc=(0, 1.0, 0.44), r=0.12, h=0.06, verts=12))
    p.append(cyl("FFFFFF", loc=(0.33, 0.6, 0.05), r=0.13, h=0.05, rot=(0, 90, 0), verts=14))  # gauge
    p.append(box("E04848", loc=(0.36, 0.6, 0.08), size=(0.02, 0.02, 0.1)))
    for y in (0.35, 1.15):
        p.append(cyl(RUBBER, loc=(0, y, 0.38), r=0.06, h=0.2, verts=8))
    p.append(capsule(RUBBER, (0, 0.3, 0.52), (0, 1.2, 0.52), 0.09))
    p.append(tube("2A2A33", [(0.0, 1.3, -0.1), (0.25, 1.55, -0.3), (0.15, 1.6, -0.55)], 0.06, seg=8))  # supply hose stub
    l0, l1 = Vector((0, 0.25, -0.15)), Vector((0, -1.95, -0.95))
    p.append(tube(METAL, [tuple(l0), tuple(l1)], 0.06, seg=10))
    d = (l1 - l0).normalized()
    ang = math.degrees(math.atan2(-d.z, -d.y))
    q = l0 + (l1 - l0) * 0.45
    p.append(cyl(RUBBER, loc=tuple(q), r=0.1, h=0.55, rot=(90 + ang, 0, 0), verts=10))         # lance grip
    nz = l1 + d * 0.1
    p.append(cyl(yel, loc=tuple(nz), r=0.08, r2=0.11, h=0.22, rot=(90 + ang, 0, 0), verts=10))
    a.part("Handle", p)
    mark(a, "grip2", tuple(q))
    mark(a, "tip", tuple(nz + d * 0.15))


def golden_broom(a):
    """Golden broom (about 5 studs): a gold stick with jewel rings, a crown-like ferrule and a
    shiny gold straw head with a red band, glinting gems on top."""
    gold, gold_d, ruby = "FFC83C", "D29A1E", "E83A5A"
    p = _stick(gold, "8C5A1E", ruby)
    for y in (-0.9, 2.0):
        p.append(torus(gold_d, loc=(0, y, 0), R=0.1, r=0.025, rot=(90, 0, 0), seg=12, mseg=4))
    p.append(cyl(gold_d, loc=(0, -1.6, 0), r=0.17, h=0.35, rot=(90, 0, 0), r2=0.13, verts=12))
    for k in range(6):  # crown points
        ang = math.radians(k * 60)
        p.append(cone(gold, loc=(math.cos(ang) * 0.17, -1.42, math.sin(ang) * 0.17), r=0.05, h=0.14, rot=(-90, 0, 0), verts=6))
    head = cone(gold, loc=(0, -2.15, 0), r=0.9, h=1.0, rot=(-90, 0, 0), verts=18)
    deform(head, lambda v: Vector((v.x, v.y, v.z * 0.32)))
    p.append(head)
    p.append(box(ruby, loc=(0, -1.98, 0), size=(0.66, 0.08, 0.32)))
    for i in range(11):
        x = -0.85 + i * 0.17
        p.append(box(shade(gold, -0.12 if i % 2 else 0.12), loc=(x, -2.74, 0), size=(0.09, 0.22, 0.2), rot=(0, 0, (i - 5) * 3)))
    a.part("Handle", p)
    gems = [ico("FFFFFF", loc=(x, -1.98, 0.17), scale=0.06) for x in (-0.22, 0, 0.22)]
    gems.append(ico("FFF4B4", loc=(0, 2.48, 0), scale=0.08))
    a.part("Handle_Glow", gems, parent="Handle", glow="FFF4B4")
    mark(a, "grip2", (0, 1.6, 0))
    mark(a, "tip", (0, -2.7, 0))


def storm_blower(a):
    """Storm blower (hip tool, about 3.5 studs): a navy twin-fan engine with a lightning stripe,
    a top handle, and two blow tubes joined into one big flared nozzle."""
    navy, bolt = "2E3C78", "FFE03C"
    p = [box(navy, loc=(0, 0.7, 0), size=(0.8, 1.15, 0.78), bevel=0.18)]
    for s in (-1, 1):
        p.append(cyl(DARK, loc=(s * 0.42, 0.7, 0), r=0.3, h=0.08, rot=(0, 90, 0), verts=18))
        p += [box(bolt, loc=(s * 0.47, 0.7, k * 0.12), size=(0.03, 0.4, 0.04)) for k in (-1, 1)]
    # lightning bolt on top
    zig = [(-0.12, 1.15, 0.4), (0.08, 0.85, 0.4), (-0.06, 0.8, 0.4), (0.12, 0.4, 0.4)]
    p.append(tube(bolt, zig, 0.05, seg=6))
    for y in (0.25, 1.1):
        p.append(cyl(RUBBER, loc=(0, y, 0.5), r=0.07, h=0.22, verts=8))
    p.append(capsule(RUBBER, (0, 0.2, 0.63), (0, 1.15, 0.63), 0.09))
    p.append(box("FF3A4A", loc=(0, 0.45, 0.5), size=(0.08, 0.12, 0.12), bevel=0.02))
    t1 = Vector((0, -1.8, -0.82))
    for s in (-1, 1):
        t0 = Vector((s * 0.2, 0.05, -0.15))
        m = Vector((s * 0.14, -1.0, -0.5))
        p.append(tube(navy, [tuple(t0), tuple(m), tuple(t1)], 0.13, seg=12))
    d = (t1 - Vector((0, 0.05, -0.15))).normalized()
    ang = math.degrees(math.atan2(-d.z, -d.y))
    p.append(torus(bolt, loc=tuple(t1 - d * 0.25), R=0.2, r=0.035, rot=(90 + ang, 0, 0), seg=14, mseg=4))
    nz = t1 + d * 0.15
    p.append(cyl(navy, loc=tuple(nz), r=0.2, r2=0.36, h=0.38, rot=(90 + ang, 0, 0), verts=16))
    a.part("Handle", p)
    a.part("Handle_Glow", [torus(bolt, loc=tuple(nz + d * 0.2), R=0.35, r=0.04, rot=(90 + ang, 0, 0), seg=18, mseg=6)],
           parent="Handle", glow=bolt)
    mark(a, "grip2", tuple(Vector((0, 0.05, -0.15)) + (t1 - Vector((0, 0.05, -0.15))) * 0.5))
    mark(a, "tip", tuple(nz + d * 0.25))


def tornado_vac(a):
    """Tornado vac (hip tool, about 3.5 studs): a teal motor with a clear cyclone chamber that
    shows a swirl inside, a top handle and a wide wand to a flat floor head."""
    teal, glass = "28B4B4", "C8F4FF"
    p = [capsule(teal, (0, 1.35, -0.1), (0, 0.3, -0.1), 0.38)]
    p.append(cyl(glass, loc=(0, 0.8, 0.25), r=0.3, h=0.42, verts=18))                          # cyclone chamber
    p.append(cyl(DARK, loc=(0, 0.8, 0.48), r=0.31, h=0.05, verts=18))
    for y in (0.4, 1.25):
        p.append(cyl(DARK, loc=(0, y, 0.45), r=0.06, h=0.24, verts=8))
    p.append(capsule(DARK, (0, 0.35, 0.6), (0, 1.3, 0.6), 0.09))
    w0, w1 = Vector((0, 0.0, -0.2)), Vector((0, -1.75, -0.85))
    p.append(tube(METAL, [tuple(w0), tuple(w1)], 0.11, seg=12))
    d = (w1 - w0).normalized()
    ang = math.degrees(math.atan2(-d.z, -d.y))
    p.append(box(teal, loc=tuple(w1 + d * 0.15), size=(1.0, 0.32, 0.24), rot=(ang * 0.0, 0, 0), bevel=0.07))
    a.part("Handle", p)
    swirl = []
    for k in range(14):  # spiral inside the chamber
        t = k / 13
        ang2 = t * 4 * math.pi
        r = 0.08 + 0.16 * t
        swirl.append((math.cos(ang2) * r, 0.8 + math.sin(ang2) * r, 0.08 + 0.32 * t))
    glow = [tube("78FFF0", swirl, 0.025, seg=6)]
    glow.append(torus("78FFF0", loc=(0, 0.82, -0.1), R=0.39, r=0.035, rot=(90, 0, 0), seg=20, mseg=6))
    a.part("Handle_Glow", glow, parent="Handle", glow="78FFF0")
    mark(a, "grip2", tuple(w0 + (w1 - w0) * 0.45))
    mark(a, "tip", tuple(w1 + d * 0.15 + Vector((0, 0, -0.1))))


def diamond_mop(a):
    """Diamond mop (about 5 studs): a white stick with cyan bands, a silver clamp and a mop
    head made of glowing crystal strands that fan out at the floor."""
    cyan, white = "5AE6FF", "F4FAFF"
    p = _stick(white, "2A8CC8", cyan, y0=-1.4)
    p.append(cyl(METAL, loc=(0, -1.55, 0), r=0.24, h=0.35, rot=(90, 0, 0), verts=14))
    p.append(torus(cyan, loc=(0, -1.62, 0), R=0.25, r=0.045, rot=(90, 0, 0), seg=14, mseg=4))
    a.part("Handle", p)
    strands = []
    for i in range(12):
        ang = math.radians(i * 30)
        x, z = math.cos(ang) * 0.2, math.sin(ang) * 0.2
        mid = (x * 2.2, -2.15, z * 2.2)
        end = (x * 3.0, -2.6, z * 3.0)
        strands.append(tube(("A0F4FF", "D2FAFF", "78DCFF")[i % 3], [(x, -1.7, z), mid, end], 0.06, seg=6))
        strands.append(ico("FFFFFF", loc=end, scale=0.09))
    a.part("Handle_Glow", strands, parent="Handle", glow="A0F4FF")
    mark(a, "grip2", (0, 1.6, 0))
    mark(a, "tip", (0, -2.55, 0))


def rainbow_duster(a):
    """Rainbow duster (about 5 studs): a long white stick and a big round plume of feathers in
    rainbow bands (red outside to violet in the middle)."""
    p = _stick("FFFFFF", "B45AFF", "FF6EC8", y0=-1.5)
    p.append(cyl("FFD23C", loc=(0, -1.6, 0), r=0.16, h=0.3, rot=(90, 0, 0), r2=0.12, verts=12))
    bands = ["FF4A5A", "FF9A3C", "FFE03C", "5AD25A", "3CA0FF", "9A5AFF"]
    for ring, col in enumerate(bands):
        n = max(3, 14 - ring * 2)
        rr = 0.75 - ring * 0.12
        for k in range(n):
            ang = 2 * math.pi * (k + 0.5 * ring) / n
            x, z = math.cos(ang) * rr, math.sin(ang) * rr * 0.55
            f = sphere(col, loc=(x, -2.2 - 0.06 * ring, z), scale=(0.2, 0.42, 0.12), seg=10, rings=6,
                       rot=(0, 0, math.degrees(math.atan2(x, 1.0)) * 0.6))
            p.append(f)
    p.append(sphere("FFFFFF", loc=(0, -2.55, 0), scale=(0.18, 0.18, 0.12), seg=12, rings=8))
    a.part("Handle", p)
    mark(a, "grip2", (0, 1.6, 0))
    mark(a, "tip", (0, -2.65, 0))


def galaxy_vacuum(a):
    """Galaxy vacuum (hip tool, about 3.5 studs): a deep purple pod with gold trim, a starry
    glass dome, a top handle and a long barrel with glowing pink rings to a wide mouth."""
    pc, gold, pink = "3C1E6E", "FFC83C", "FF6EE6"
    p = [capsule(pc, (0, 1.35, -0.1), (0, 0.25, -0.1), 0.44)]
    p += [box(shade(pc, 0.25), loc=(s * 0.46, 1.0, -0.1), size=(0.12, 0.7, 0.5), bevel=0.04) for s in (-1, 1)]
    p.append(torus(gold, loc=(0, 0.3, -0.1), R=0.42, r=0.04, rot=(90, 0, 0), seg=20, mseg=6))
    p.append(sphere("1E0F3C", loc=(0, 0.8, 0.28), scale=(0.28, 0.28, 0.2), seg=16, rings=10))     # dome
    for y in (0.4, 1.25):
        p.append(cyl(gold, loc=(0, y, 0.45), r=0.06, h=0.24, verts=8))
    p.append(capsule(DARK, (0, 0.35, 0.6), (0, 1.3, 0.6), 0.09))
    b0, b1 = Vector((0, -0.05, -0.15)), Vector((0, -1.6, -0.75))
    p.append(tube(pc, [tuple(b0), tuple(b1)], 0.18, seg=14))
    d = (b1 - b0).normalized()
    ang = math.degrees(math.atan2(-d.z, -d.y))
    mouth = b1 + d * 0.12
    p.append(cyl(gold, loc=tuple(mouth), r=0.26, r2=0.45, h=0.36, rot=(90 + ang, 0, 0), verts=18))
    a.part("Handle", p)
    glow = [ico("FFFFFF", loc=(x, 0.8 + y, 0.42), scale=0.035) for x, y in ((0.08, 0.05), (-0.1, -0.08), (0.02, -0.15), (-0.04, 0.12))]
    for f in (0.3, 0.6, 0.85):
        q = b0 + (b1 - b0) * f
        glow.append(torus(pink, loc=tuple(q), R=0.2, r=0.035, rot=(90 + ang, 0, 0), seg=16, mseg=6))
    glow.append(torus(pink, loc=tuple(mouth + d * 0.18), R=0.43, r=0.04, rot=(90 + ang, 0, 0), seg=20, mseg=6))
    a.part("Handle_Glow", glow, parent="Handle", glow=pink)
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
    "Rake": (rake, (0, 0.4, 0)),
    "PushBroom": (push_broom, (0, 0.4, 0)),
    "LeafVac": (leaf_vac, (0, 0.72, 0.6)),
    "PressureWasher": (pressure_washer, (0, 0.75, 0.52)),
    "GoldenBroom": (golden_broom, (0, 0.4, 0)),
    "StormBlower": (storm_blower, (0, 0.68, 0.63)),
    "TornadoVac": (tornado_vac, (0, 0.82, 0.6)),
    "DiamondMop": (diamond_mop, (0, 0.4, 0)),
    "RainbowDuster": (rainbow_duster, (0, 0.4, 0)),
    "GalaxyVacuum": (galaxy_vacuum, (0, 0.82, 0.6)),
}
