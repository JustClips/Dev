"""Eggs, tools, vehicles and world props.

Hand tools are modelled along Blender Y with the business end at -Y and a `grip` point
(where the hand holds it). In Roblox that is the part's Z axis; ToolService builds the
Tool.Grip from the grip point in meta.json.
"""
import math
import random
import bpy
from mathutils import Vector
from lib import (Asset, use, sphere, ico, box, cyl, cone, torus, capsule, tube, join,
                 deform, noise_deform)
from aliens import shade, eye

DARK = "1B1530"
WHITE = "FFFFFF"


# ------------------------------------------------------------------------- eggs

def egg_shell(col, h=2.4, r=0.95, z0=0.0):
    e = sphere(col, loc=(0, 0, z0 + h / 2), scale=(r, r, h / 2), seg=20, rings=14)
    mid = z0 + h / 2

    def taper(v):
        t = (v.z - mid) / (h / 2)      # -1 bottom .. 1 top
        k = 1 - max(0, t) * 0.22 + min(0, t) * 0.02
        return Vector((v.x * k, v.y * k, v.z))
    deform(e, taper)
    return e


def on_egg(t, ang, h=2.4, r=0.95, out=1.0):
    """Point on the egg surface: t = height fraction 0..1, ang in degrees."""
    z = h * t
    tt = (z - h / 2) / (h / 2)
    rad = r * math.sqrt(max(0.0, 1 - tt * tt)) * (1 - max(0, tt) * 0.22)
    a = math.radians(ang)
    return Vector((math.cos(a) * rad * out, math.sin(a) * rad * out, z))


def egg(name, base, spots=None, band=None, glow=None, glow_spots=None, stars=False, ring=None):
    a = Asset(f"Egg_{name}", "egg")
    use(a)
    pieces = [egg_shell(base)]
    rnd = random.Random(name)
    if spots:
        for i in range(14):
            t = rnd.uniform(0.15, 0.85)
            ang = rnd.uniform(0, 360)
            p = on_egg(t, ang, out=0.97)
            s = rnd.uniform(0.12, 0.22)
            pieces.append(sphere(spots, loc=p, scale=(s, s, s * 0.9), seg=10, rings=6))
    if band:
        for t, rr in ((0.42, 1.0), (0.58, 0.95)):
            p = on_egg(t, 0)
            pieces.append(torus(band, loc=(0, 0, p.z), R=p.length if False else math.hypot(p.x, p.y) * 1.0, r=0.06, seg=28, mseg=6))
    a.part("Body", pieces)
    gp = []
    if glow_spots:
        for i in range(10):
            t = rnd.uniform(0.15, 0.85)
            ang = rnd.uniform(0, 360)
            p = on_egg(t, ang, out=0.98)
            s = rnd.uniform(0.1, 0.16)
            gp.append(ico(glow_spots, loc=p, scale=(s, s, s), sub=1))
    if stars:
        for i in range(9):
            t = rnd.uniform(0.15, 0.85)
            ang = rnd.uniform(0, 360)
            p = on_egg(t, ang, out=1.0)
            gp.append(ico("FFF5A0", loc=p, scale=0.09, sub=1))
    if ring:
        gp.append(torus(ring, loc=(0, 0, 1.25), R=1.4, r=0.07, rot=(20, 0, 0), seg=36))
    if glow:
        # glowing crack zig-zag around the middle
        pts = [on_egg(0.5 + (0.06 if i % 2 else -0.06), i * 20, out=1.01) for i in range(19)]
        gp.append(tube(glow, pts, 0.05, seg=6))
    if gp:
        a.part("Body_Glow", gp, parent="Body", glow=glow or glow_spots or ring or "FFF5A0")
    return a


EGGS = {
    "Common": lambda: egg("Common", "F2EFE6", spots="BEB8A8"),
    "Uncommon": lambda: egg("Uncommon", "7EE08A", spots="C8F5B4", band="3FA55A"),
    "Rare": lambda: egg("Rare", "5A9BFF", spots="B4D2FF", band="2A5ACD"),
    "Epic": lambda: egg("Epic", "A45AFF", glow_spots="F0B4FF", band="5A2AA0"),
    "Legendary": lambda: egg("Legendary", "FFC83C", spots="FFF0A0", glow="FFFFFF", band="D28C14"),
    "Mythic": lambda: egg("Mythic", "3A1420", glow_spots="FF5A3C", glow="FF7A3C"),
    "Cosmic": lambda: egg("Cosmic", "5A2ABE", stars=True, ring="FF78E6", glow="78FFF0"),
}


# ------------------------------------------------------------------------- hand tools

def hand_tool(name, build, grip):
    a = Asset(f"Tool_{name}", "tool")
    use(a)
    build(a)
    a.extra["grip"] = [round(-grip[0], 3), round(grip[2], 3), round(grip[1], 3)]
    return a


def toothbrush(a):
    blue, white = "5AB4FF", "FFFFFF"
    handle = capsule(blue, (0, 1.2, 0), (0, -1.0, 0), 0.13)
    grip = capsule("2A7ACD", (0, 1.25, 0), (0, 0.4, 0), 0.16)
    rings = [torus("FFE36E", loc=(0, y, 0), R=0.15, r=0.03, rot=(90, 0, 0), seg=14, mseg=4) for y in (0.35, 1.3)]
    dots = [sphere("FF7AB4", loc=(0, y, 0.15), scale=0.04) for y in (0.55, 0.75, 0.95, 1.15)]
    head = box(blue, loc=(0, -1.25, 0.02), size=(0.32, 0.6, 0.16), bevel=0.05)
    bristles = []
    for i in range(5):
        for j, x in enumerate((-0.08, 0.08)):
            col = ("FFFFFF", "9ED8FF", "FF9EC4")[(i + j) % 3]
            bristles.append(box(col, loc=(x, -1.45 + i * 0.1, -0.18), size=(0.12, 0.07, 0.32), bevel=0.02))
    paste = [sphere("7AF0C8", loc=(0, -1.25 + k * 0.12, -0.38 - 0.03 * (k % 2)), scale=(0.1, 0.09, 0.07)) for k in (-1, 0, 1)]
    paste += [sphere(white, loc=(0, -1.25 + k * 0.12, -0.42), scale=(0.05, 0.05, 0.04)) for k in (-1, 1)]
    a.part("Handle", [handle, grip, head] + rings + dots + bristles + paste)


def broom(a):
    wood, straw, band = "B4783C", "FFD25A", "D23C3C"
    stick = cyl(wood, loc=(0, 0.3, 0), r=0.09, h=3.6, rot=(90, 0, 0), verts=10)
    grain = [torus(shade(wood, -0.15), loc=(0, y, 0), R=0.09, r=0.015, rot=(90, 0, 0), seg=10, mseg=4) for y in (-0.6, 0.2, 1.0, 1.6)]
    knob = sphere(shade(wood, -0.2), loc=(0, 2.1, 0), scale=0.12)
    loop = torus("D23C3C", loc=(0, 2.3, 0), R=0.12, r=0.03, rot=(0, 90, 0), seg=12, mseg=4)
    b = cyl(band, loc=(0, -1.55, 0), r=0.16, h=0.25, rot=(90, 0, 0), verts=12)
    head = cone(straw, loc=(0, -2.1, 0), r=0.75, h=1.0, rot=(-90, 0, 0), verts=16)
    deform(head, lambda v: Vector((v.x, v.y, v.z * 0.35)))
    stitches = [box(band, loc=(0, y, 0), size=(w, 0.06, 0.3 * w + 0.05)) for y, w in ((-1.85, 0.62), (-2.05, 0.95))]
    strands = [box(shade(straw, -0.15 if i % 2 else 0.1), loc=(-0.6 + i * 0.15, -2.62, 0), size=(0.07, 0.16, 0.22)) for i in range(9)]
    a.part("Handle", [stick, knob, loop, b, head] + grain + stitches + strands)


def mop(a):
    stick = cyl("5AC8A0", loc=(0, 0.3, 0), r=0.09, h=3.6, rot=(90, 0, 0), verts=10)
    tip = sphere("FFFFFF", loc=(0, 2.1, 0), scale=0.13)
    grip = capsule("2A8C6E", (0, 1.9, 0), (0, 1.2, 0), 0.12)
    cap = cyl("FFFFFF", loc=(0, -1.55, 0), r=0.22, h=0.3, rot=(90, 0, 0), verts=12)
    ring = torus("5AC8A0", loc=(0, -1.6, 0), R=0.23, r=0.04, rot=(90, 0, 0), seg=14, mseg=4)
    strands = []
    for i in range(14):
        ang = i * 360 / 14
        x, z = math.cos(math.radians(ang)) * 0.22, math.sin(math.radians(ang)) * 0.22
        strands.append(capsule(("E6F5FF", "B4E6F0", "FFD2E6")[i % 3], (x, -1.65, z), (x * 2.9, -2.6, z * 2.9), 0.075, seg=8))
    bubbles = [sphere("CDEBFF", loc=(x, -2.75, z), scale=0.09) for x, z in ((0.3, 0.2), (-0.35, -0.1), (0.05, -0.4))]
    a.part("Handle", [stick, tip, grip, cap, ring] + strands + bubbles)


def leaf_blower(a):
    o = "FF8C3C"
    body = box(o, loc=(0, 0.6, -0.1), size=(0.7, 1.2, 0.8), bevel=0.15)
    stripe = box("FFFFFF", loc=(0, 0.6, -0.1), size=(0.72, 0.18, 0.82), bevel=0.05)
    engine = cyl("3A3A46", loc=(0.38, 0.6, -0.1), r=0.32, h=0.12, rot=(0, 90, 0), verts=16)
    vents = [box("2A2A33", loc=(0.45, 0.6, -0.1 + k * 0.12), size=(0.04, 0.4, 0.05)) for k in (-1, 0, 1)]
    fuel = cyl("FFD23C", loc=(-0.2, 0.95, 0.32), r=0.1, h=0.1, verts=10)
    grip = capsule("3A3A46", (0, 0.4, 0.45), (0, 1.0, 0.45), 0.1)
    trigger = box("FF3A4A", loc=(0, 0.5, 0.3), size=(0.08, 0.12, 0.14), bevel=0.02)
    tube_ = cyl("3A3A46", loc=(0, -0.7, -0.25), r=0.17, h=1.8, rot=(90, 0, 0), verts=12)
    bands = [torus(o, loc=(0, y, -0.25), R=0.18, r=0.03, rot=(90, 0, 0), seg=14, mseg=4) for y in (-0.2, -0.9)]
    nozzle = cyl(o, loc=(0, -1.7, -0.25), r=0.22, h=0.3, rot=(90, 0, 0), r2=0.3, verts=12)
    a.part("Handle", [body, stripe, engine, fuel, grip, trigger, tube_, nozzle] + vents + bands)


def shop_vac(a):
    y = "FFD23C"
    canister = cyl(y, loc=(0, 0.9, -0.2), r=0.42, h=0.9, rot=(90, 0, 0), verts=18)
    label = cyl("3A3A46", loc=(0, 0.85, -0.2), r=0.43, h=0.25, rot=(90, 0, 0), verts=18)
    lid = cyl("3A3A46", loc=(0, 1.4, -0.2), r=0.44, h=0.15, rot=(90, 0, 0), verts=18)
    wheels = [sphere("2A2A33", loc=(x, 1.25, -0.62), scale=(0.08, 0.12, 0.12)) for x in (-0.3, 0.3)]
    grip = capsule("3A3A46", (0, 0.6, 0.35), (0, 1.2, 0.35), 0.09)
    hose = tube("5A5A6E", [(0.35, 0.6, -0.1), (0.45, 0.2, 0.1), (0.25, -0.2, 0.0), (0.08, -0.5, -0.15)], 0.07)
    wand = cyl("C8C8D2", loc=(0, -0.6, -0.2), r=0.1, h=2.2, rot=(90, 0, 0), verts=10)
    head = box("3A3A46", loc=(0, -1.8, -0.25), size=(1.0, 0.35, 0.25), bevel=0.06)
    brush = box("FFD23C", loc=(0, -1.8, -0.4), size=(0.9, 0.2, 0.08), bevel=0.02)
    a.part("Handle", [canister, label, lid, grip, hose, wand, head, brush] + wheels)


def turbo_vacuum(a):
    p, g = "B45AFF", "5AFFF0"
    body = capsule(p, (0, 1.2, -0.15), (0, 0.2, -0.15), 0.42)
    fins = [box(shade(p, -0.3), loc=(s * 0.45, 1.0, -0.15), size=(0.12, 0.6, 0.5), bevel=0.04) for s in (-1, 1)]
    grip = capsule("2A2A3A", (0, 0.4, 0.42), (0, 1.1, 0.42), 0.09)
    barrel = cyl("2A2A3A", loc=(0, -0.8, -0.15), r=0.18, h=1.6, rot=(90, 0, 0), verts=14)
    mouth = cyl(p, loc=(0, -1.75, -0.15), r=0.25, h=0.35, rot=(90, 0, 0), r2=0.42, verts=16)
    a.part("Handle", [body, grip, barrel, mouth] + fins)
    a.part("Handle_Glow", [torus(g, loc=(0, y, -0.15), R=0.44, r=0.04, rot=(90, 0, 0), seg=20, mseg=6) for y in (0.5, 0.9)]
           + [torus(g, loc=(0, -1.9, -0.15), R=0.4, r=0.04, rot=(90, 0, 0), seg=20, mseg=6)], parent="Handle", glow=g)


TOOLS = {
    "Toothbrush": (toothbrush, (0, 0.85, 0)),
    "Broom": (broom, (0, 1.4, 0)),
    "Mop": (mop, (0, 1.4, 0)),
    "LeafBlower": (leaf_blower, (0, 0.7, 0.45)),
    "ShopVac": (shop_vac, (0, 0.9, 0.35)),
    "TurboVacuum": (turbo_vacuum, (0, 0.75, 0.42)),
}


# ------------------------------------------------------------------------- vehicles

def wheel(col, x, y, r, w, hub="D2D2DC"):
    """Chunky cartoon wheel: rounded tyre with tread blocks, coloured rim, hub cap."""
    side = 1 if x > 0 else -1
    t = cyl(col, loc=(x, y, r), r=r * 0.92, h=w, rot=(0, 90, 0), verts=20)
    edges = [torus(col, loc=(x + side * k * w * 0.42, y, r), R=r * 0.86, r=r * 0.12, rot=(0, 90, 0), seg=20, mseg=6) for k in (-1, 1)]
    tread = [box(shade(col, 0.12), loc=(x, y + math.cos(a) * r * 0.95, r + math.sin(a) * r * 0.95), size=(w * 0.9, r * 0.22, r * 0.14),
                 rot=(math.degrees(a) + 90, 0, 0)) for a in [i * math.pi / 6 for i in range(12)]]
    rim = cyl(hub, loc=(x + side * w / 2, y, r), r=r * 0.55, h=0.08, rot=(0, 90, 0), verts=16)
    cap = sphere(shade(hub, -0.25), loc=(x + side * (w / 2 + 0.04), y, r), scale=(0.06, r * 0.22, r * 0.22), seg=12, rings=6)
    bolts = [sphere("FFFFFF", loc=(x + side * (w / 2 + 0.05), y + math.cos(a) * r * 0.36, r + math.sin(a) * r * 0.36), scale=r * 0.06, seg=6, rings=4)
             for a in [i * math.pi * 2 / 5 for i in range(5)]]
    return [t, rim, cap] + edges + tread + bolts


def vehicle(name, s, color, kind):
    a = Asset(f"Vehicle_{name}", "vehicle")
    use(a)
    W, L = 6 * s, 9 * s
    pieces = []
    wr = 1.0 * s
    for x in (-1, 1):
        for y in (-1, 1):
            pieces += wheel("2A2A33", x * (W / 2 - 0.1), y * L * 0.32, wr, 0.8 * s)
    chassis = box(color, loc=(0, 0, wr + 0.6 * s), size=(W - 0.6, L, 1.2 * s), bevel=0.25 * s)
    pieces.append(chassis)
    seat = box("2A2A3A", loc=(0, 1 * s, wr + 1.5 * s), size=(1.6 * s, 1.4 * s, 0.6 * s), bevel=0.15 * s)
    back = box("2A2A3A", loc=(0, 1.75 * s, wr + 2.2 * s), size=(1.6 * s, 0.35 * s, 1.4 * s), bevel=0.12 * s)
    pieces += [seat, back]
    if kind == "cart":
        for x in (-1, 1):
            for y in (-1, 1):
                pieces.append(cyl("E6E6EE", loc=(x * (W / 2 - 0.6), y * 1.6 * s + 0.4 * s, wr + 3.0 * s), r=0.08 * s, h=2.6 * s, verts=8))
        pieces.append(box("FFFFFF", loc=(0, 0.4 * s, wr + 4.3 * s), size=(W - 0.6, 4 * s, 0.25 * s), bevel=0.1 * s))
        pieces.append(box(shade(color, -0.25), loc=(0, -2.6 * s, wr + 1.5 * s), size=(W - 1.2, 1.8 * s, 0.8 * s), bevel=0.2 * s))
    elif kind == "truck":
        pieces.append(box(shade(color, -0.1), loc=(0, -2.3 * s, wr + 2.2 * s), size=(W - 0.8, 2.6 * s, 2.2 * s), bevel=0.3 * s))
        pieces.append(box("9BE6FF", loc=(0, -3.62 * s, wr + 2.6 * s), size=(W - 1.6, 0.05, 1.0 * s), bevel=0.02))
        tank = cyl("DCDCE6", loc=(0, 2.6 * s, wr + 2.4 * s), r=1.5 * s, h=3.2 * s, rot=(90, 0, 0), verts=20)
        pieces.append(tank)
        pieces += [torus(shade(color, -0.3), loc=(0, 2.6 * s + d * s, wr + 2.4 * s), R=1.52 * s, r=0.1 * s, rot=(90, 0, 0)) for d in (-1.2, 1.2)]
    elif kind == "buggy":
        # open roll cage, big antenna flag, chunky bumper
        for x in (-1, 1):
            pieces.append(tube("E6E6EE", [(x * (W / 2 - 0.5), 2.2 * s, wr + 1.2 * s), (x * (W / 2 - 0.6), 1.0 * s, wr + 3.4 * s),
                                          (x * (W / 2 - 0.6), -0.6 * s, wr + 3.4 * s), (x * (W / 2 - 0.5), -1.6 * s, wr + 1.2 * s)], 0.12 * s))
        pieces.append(cyl("E6E6EE", loc=(0, -0.6 * s, wr + 3.4 * s), r=0.12 * s, h=W - 1.2, rot=(0, 90, 0), verts=8))
        pieces.append(cyl("E6E6EE", loc=(0, 1.0 * s, wr + 3.4 * s), r=0.12 * s, h=W - 1.2, rot=(0, 90, 0), verts=8))
        pieces.append(box(shade(color, -0.3), loc=(0, -L / 2 + 0.2, wr + 0.6 * s), size=(W + 0.4, 0.6 * s, 0.8 * s), bevel=0.2 * s))
        pieces.append(cyl("C8C8D2", loc=(-W / 2 + 0.8, 2.6 * s, wr + 3.0 * s), r=0.06 * s, h=3.2 * s, verts=8))
        pieces.append(box("FF5A78", loc=(-W / 2 + 1.3, 2.6 * s, wr + 4.2 * s), size=(1.0 * s, 0.06, 0.6 * s)))
    elif kind == "hover":
        # no wheels: hover pads with glowing rings, sleek nose and fins
        for p in pieces:
            if p not in (chassis, seat, back):
                bpy.data.objects.remove(p, do_unlink=True)
        pieces = [chassis]
        for x in (-1, 1):
            for y in (-1, 1):
                pieces.append(cyl("3A3A46", loc=(x * (W / 2 - 0.6), y * L * 0.32, wr * 0.7), r=0.9 * s, h=0.5 * s, verts=20))
        pieces += [seat, back]
        pieces.append(sphere(shade(color, 0.15), loc=(0, -L / 2 + 0.8 * s, wr + 1.0 * s), scale=(W / 2 - 0.4, 1.8 * s, 0.7 * s)))
        pieces.append(sphere("9BE6FF", loc=(0, -0.9 * s, wr + 2.0 * s), scale=(1.3 * s, 1.0 * s, 0.7 * s)))
        for x in (-1, 1):
            pieces.append(box(shade(color, -0.25), loc=(x * (W / 2 - 0.8), L / 2 - 0.8 * s, wr + 2.0 * s), size=(0.25 * s, 1.6 * s, 1.6 * s), bevel=0.1 * s, rot=(20, 0, 0)))
    elif kind == "rover":
        # six wheels, solar panel wings, mast camera
        for x in (-1, 1):
            pieces += wheel("2A2A33", x * (W / 2 - 0.1), 0, wr, 0.8 * s)
        pieces.append(box(shade(color, -0.1), loc=(0, -1.8 * s, wr + 2.0 * s), size=(W - 1.4, 3.0 * s, 1.8 * s), bevel=0.3 * s))
        for x in (-1, 1):
            pieces.append(box("2A4AA0", loc=(x * (W / 2 + 1.6 * s), 1.2 * s, wr + 2.2 * s), size=(3.0 * s, 4.0 * s, 0.12 * s)))
            for k in range(3):
                pieces.append(box("8CB4FF", loc=(x * (W / 2 + 1.6 * s), 1.2 * s + (k - 1) * 1.3 * s, wr + 2.29 * s), size=(2.7 * s, 1.1 * s, 0.03)))
            pieces.append(cyl("C8C8D2", loc=(x * (W / 2 + 0.1), 1.2 * s, wr + 2.2 * s), r=0.1 * s, h=0.9 * s, rot=(0, 90, 0), verts=8))
        pieces.append(cyl("C8C8D2", loc=(0, -2.4 * s, wr + 3.6 * s), r=0.15 * s, h=1.6 * s, verts=10))
        pieces.append(box("3A3A46", loc=(0, -2.5 * s, wr + 4.5 * s), size=(1.2 * s, 0.7 * s, 0.6 * s), bevel=0.1 * s))
    elif kind == "rocket":
        # jet sweeper: rocket engines out the back, wings and a bubble canopy
        pieces.append(sphere("9BE6FF", loc=(0, -0.4 * s, wr + 2.0 * s), scale=(1.4 * s, 1.8 * s, 1.0 * s)))
        pieces.append(cone(shade(color, 0.2), loc=(0, -L / 2 - 0.2 * s, wr + 0.7 * s), r=1.6 * s, h=1.6 * s, rot=(90, 0, 0), verts=16))
        for x in (-1, 1):
            pieces.append(cyl("C8C8D2", loc=(x * 1.6 * s, L / 2 - 0.4 * s, wr + 1.8 * s), r=0.8 * s, h=3.0 * s, rot=(90, 0, 0), verts=16))
            pieces.append(cone("FF5A3C", loc=(x * 1.6 * s, L / 2 + 1.3 * s, wr + 1.8 * s), r=0.6 * s, h=1.2 * s, rot=(-90, 0, 0), verts=12))
            pieces.append(box(shade(color, -0.25), loc=(x * (W / 2 + 0.9 * s), 1.0 * s, wr + 1.0 * s), size=(2.2 * s, 2.6 * s, 0.2 * s), bevel=0.08 * s, rot=(0, x * -12, 0)))
        pieces.append(box(shade(color, -0.25), loc=(0, L / 2 - 0.6 * s, wr + 3.0 * s), size=(0.25 * s, 1.8 * s, 2.0 * s), bevel=0.08 * s))
    else:  # crawler
        for x in (-1, 1):
            pieces.append(box("3A3A46", loc=(x * (W / 2 - 0.2), 0, wr * 0.9), size=(1.2 * s, L * 0.95, wr * 1.8), bevel=0.5 * s))
        pieces.append(box(shade(color, -0.1), loc=(0, -1.6 * s, wr + 2.4 * s), size=(W - 1.0, 3.4 * s, 2.6 * s), bevel=0.4 * s))
        pieces.append(sphere("9BE6FF", loc=(0, -2.6 * s, wr + 3.2 * s), scale=(1.6 * s, 1.2 * s, 1.1 * s)))
        pieces.append(cyl("C8C8D2", loc=(1.6 * s, 2.8 * s, wr + 3.5 * s), r=0.25 * s, h=3 * s, verts=10))
        pieces.append(sphere("FFFFFF", loc=(1.6 * s, 2.8 * s, wr + 5.1 * s), scale=(0.6 * s, 0.6 * s, 0.2 * s)))
    pieces += car_details(s, W, L, wr, color, kind)
    a.part("Body", pieces)
    # front roller brush spins in game
    by = -L / 2 - 0.9 * s
    brush = cyl("FFE678", loc=(0, by, 0.75 * s), r=0.62 * s, h=W * 1.05, rot=(0, 90, 0), verts=16)
    bristle = [box("FFB43C" if i % 2 else "FF8C3C", loc=(0, by + math.cos(t) * 0.68 * s, 0.75 * s + math.sin(t) * 0.68 * s), size=(W * 1.05, 0.14 * s, 0.3 * s),
                   rot=(math.degrees(t), 0, 0), bevel=0.04 * s) for i, t in enumerate([i * math.pi / 6 for i in range(12)])]
    bristle += [cyl(shade(color, -0.3), loc=(x * W * 0.53, by, 0.75 * s), r=0.4 * s, h=0.12 * s, rot=(0, 90, 0), verts=12) for x in (-1, 1)]
    arm = [box("3A3A46", loc=(x * (W / 2 + 0.2), by / 2 - 0.5, 1.0 * s), size=(0.25 * s, abs(by) - L / 2 + 2.5 * s, 0.25 * s)) for x in (-1, 1)]
    a.part("Body_Arms", arm, parent="Body")
    a.part("Brush", [brush] + bristle, parent="Body", joint=(0, by, 0.75 * s))
    lights = [sphere("FFF5C8", loc=(x * (W / 2 - 0.8), -L / 2 - 0.12 * s, wr + 0.8 * s), scale=(0.34 * s, 0.12 * s, 0.3 * s)) for x in (-1, 1)]
    a.part("Body_Glow", lights, parent="Body", glow="FFF5C8")
    tail = [box("FF3A4A", loc=(x * (W / 2 - 0.7), L / 2 + 0.02, wr + 0.85 * s), size=(0.7 * s, 0.1 * s, 0.3 * s), bevel=0.05 * s) for x in (-1, 1)]
    a.part("Tail_Glow", tail, parent="Body", glow="FF3A4A")
    a.extra["seat"] = [0, round(wr + 1.8 * s, 3), round(1 * s, 3)]
    return a


def car_details(s, W, L, wr, color, kind):
    """Shared car dressing: racing stripe, bumpers, grille, steering wheel, mirrors,
    exhausts and a dust hopper with a window (it's a sweeper after all)."""
    top = wr + 1.2 * s
    p = []
    p.append(box("FFFFFF", loc=(0, 0, top + 0.02), size=(0.9 * s, L * 0.98, 0.06 * s), bevel=0.02 * s))
    p.append(box(shade(color, -0.35), loc=(0, 0, top + 0.03), size=(0.25 * s, L * 0.99, 0.07 * s)))
    for y in (-1, 1):
        p.append(box("3A3A46", loc=(0, y * (L / 2 + 0.1 * s), wr + 0.45 * s), size=(W - 0.2, 0.45 * s, 0.45 * s), bevel=0.15 * s))
    for k in range(4):
        p.append(box("2A2A33", loc=(-0.75 * s + k * 0.5 * s, -L / 2 - 0.02, wr + 1.0 * s), size=(0.12 * s, 0.1 * s, 0.45 * s)))
    for x in (-1, 1):
        p.append(box(shade(color, -0.2), loc=(x * (W / 2 - 0.25), 0, wr + 0.25 * s), size=(0.35 * s, L * 0.55, 0.3 * s), bevel=0.1 * s))
    if kind != "hover":
        p.append(cyl("2A2A3A", loc=(0, 0.1 * s, wr + 2.0 * s), r=0.12 * s, h=1.2 * s, rot=(-40, 0, 0), verts=8))
        p.append(torus("2A2A3A", loc=(0, -0.3 * s, wr + 2.45 * s), R=0.45 * s, r=0.07 * s, rot=(50, 0, 0), seg=18, mseg=6))
    for x in (-1, 1):
        p.append(cyl("C8C8D2", loc=(x * (W / 2 - 0.9 * s), L / 2 + 0.2 * s, wr + 0.6 * s), r=0.18 * s, h=0.8 * s, rot=(90, 0, 0), verts=10))
        p.append(sphere("C8C8D2", loc=(x * (W / 2 + 0.15 * s), -0.6 * s, wr + 2.1 * s), scale=(0.15 * s, 0.1 * s, 0.22 * s)))
    if kind in ("cart", "buggy", "crawler"):
        hy = 2.9 * s if kind != "crawler" else 2.6 * s
        p.append(box(shade(color, -0.15), loc=(0, hy, wr + 2.0 * s), size=(W * 0.62, 1.6 * s, 1.6 * s), bevel=0.3 * s))
        p.append(box("B4E6FF", loc=(0, hy - 0.81 * s, wr + 2.1 * s), size=(W * 0.4, 0.04 * s, 0.9 * s)))
        p.append(box("A0A0AA", loc=(0, hy - 0.83 * s, wr + 1.85 * s), size=(W * 0.38, 0.04 * s, 0.35 * s)))
    return p


VEHICLES = {
    "SweeperCart": lambda: vehicle("SweeperCart", 1.0, "50C878", "cart"),
    "DustTruck": lambda: vehicle("DustTruck", 1.35, "FFB428", "truck"),
    "MoonBuggy": lambda: vehicle("MoonBuggy", 1.15, "FF8C3C", "buggy"),
    "HoverSweeper": lambda: vehicle("HoverSweeper", 1.5, "B478FF", "hover"),
    "MoonCrawler": lambda: vehicle("MoonCrawler", 1.8, "5AA0FF", "crawler"),
    "SolarRover": lambda: vehicle("SolarRover", 2.0, "F0F0F5", "rover"),
    "RocketSweeper": lambda: vehicle("RocketSweeper", 2.2, "FF4A5A", "rocket"),
}


# ------------------------------------------------------------------------- world props

def rock(name, col, seed, size=(3, 3, 2), sub=3, rough=0.25):
    a = Asset(name, "prop")
    use(a)
    r = ico(col, loc=(0, 0, size[2] * 0.45), scale=size, sub=sub, smooth=False)
    noise_deform(r, rough * min(size), seed=seed, freq=0.6 / max(0.5, min(size) / 2))
    deform(r, lambda v: Vector((v.x, v.y, max(v.z, 0.0))))
    a.part("Body", [r], collide=True)
    return a


def crystal(name, col, seed, n=5, h=4.0):
    a = Asset(name, "prop")
    use(a)
    rnd = random.Random(seed)
    base = ico(shade(col, -0.55), loc=(0, 0, 0.3), scale=(1.4, 1.4, 0.6), sub=1)
    a.part("Body", [base], collide=True)
    gl = []
    for i in range(n):
        ang = rnd.uniform(0, 360)
        tilt = rnd.uniform(0, 30) if i else 0
        hh = h * rnd.uniform(0.5, 1.0) if i else h
        rr = hh * 0.16
        x, y = (math.cos(math.radians(ang)) * 0.6, math.sin(math.radians(ang)) * 0.6) if i else (0, 0)
        c = cyl(col, loc=(x, y, hh / 2), r=rr, h=hh * 0.75, verts=6, smooth=False)
        tip = cone(col, loc=(x, y, hh * 0.875 + 0.0), r=rr, h=hh * 0.25, verts=6, smooth=False)
        cc = join([c, tip], "c")
        cc.rotation_euler = (math.radians(tilt), 0, math.radians(ang))
        import bpy
        bpy.ops.object.select_all(action="DESELECT")
        cc.select_set(True)
        bpy.context.view_layer.objects.active = cc
        bpy.ops.object.transform_apply(rotation=True)
        gl.append(cc)
    a.part("Body_Glow", gl, parent="Body", glow=col)
    return a


def alien_tree(name, trunk, top, glow, seed, h=9):
    a = Asset(name, "prop")
    use(a)
    rnd = random.Random(seed)
    pts = [(0, 0, 0), (0.3, 0.1, h * 0.35), (-0.2, 0.2, h * 0.7), (0.1, 0, h)]
    t = tube(trunk, pts, lambda i: 0.85 - i * 0.18, seg=10)
    caps = [sphere(top, loc=(0.1, 0, h + 0.4), scale=(2.6, 2.6, 1.3))]
    for i in range(3):
        ang = i * 120 + rnd.uniform(-20, 20)
        caps.append(sphere(shade(top, -0.12), loc=(math.cos(math.radians(ang)) * 1.8, math.sin(math.radians(ang)) * 1.8, h - 0.3), scale=(1.4, 1.4, 0.8)))
    a.part("Body", [t] + caps, collide=True)
    bulbs = []
    for i in range(7):
        ang = rnd.uniform(0, 360)
        rr = rnd.uniform(1.0, 2.4)
        bulbs.append(sphere(glow, loc=(math.cos(math.radians(ang)) * rr, math.sin(math.radians(ang)) * rr, h - 0.6 - rnd.uniform(0, 1.2)), scale=0.22))
    a.part("Body_Glow", bulbs, parent="Body", glow=glow)
    return a


def mushroom(name, stem, cap, glow, seed):
    a = Asset(name, "prop")
    use(a)
    rnd = random.Random(seed)
    pieces = []
    gl = []
    for i in range(3):
        x, y = (rnd.uniform(-1.2, 1.2), rnd.uniform(-1.2, 1.2)) if i else (0, 0)
        h = rnd.uniform(1.5, 3.5) if i else 4
        pieces.append(cyl(stem, loc=(x, y, h / 2), r=0.22 * h / 3, h=h, verts=10))
        c = sphere(cap, loc=(x, y, h), scale=(h * 0.45, h * 0.45, h * 0.25))
        deform(c, lambda v, hh=h: Vector((v.x, v.y, max(v.z, hh - 0.05))))
        pieces.append(c)
        for k in range(4):
            ang = rnd.uniform(0, 360)
            gl.append(sphere(glow, loc=(x + math.cos(math.radians(ang)) * h * 0.25, y + math.sin(math.radians(ang)) * h * 0.25, h + h * 0.18), scale=0.12 * h / 3 + 0.05))
    a.part("Body", pieces, collide=True)
    a.part("Body_Glow", gl, parent="Body", glow=glow)
    return a


WOOD, WOOD_DARK, WOOD_LIGHT, STRAW = "C48E5C", "805434", "E0B482", "F5D26E"


def plank_x(col, x0, x1, y, z, w, h, gap=0.0):
    return box(col, loc=((x0 + x1) / 2, y, z), size=(abs(x1 - x0) - gap, w, h), bevel=min(w, h) * 0.2)


def fence():
    """One 8-stud wooden fence segment along X (centered): posts, two rails and an X brace."""
    a = Asset("Fence", "prop")
    use(a)
    p = []
    for x in (-4, 4):
        p.append(box(WOOD_DARK, loc=(x, 0, 1.4), size=(0.55, 0.55, 2.8), bevel=0.08))
        p.append(cone(WOOD_DARK, loc=(x, 0, 2.95), r=0.4, h=0.35, verts=4, rot=(0, 0, 45), smooth=False))
    for z in (0.7, 2.3):
        p.append(plank_x(WOOD, -4, 4, 0, z, 0.3, 0.35))
    for sgn in (-1, 1):
        brace = box(WOOD_LIGHT, loc=(0, 0.02, 1.5), size=(8.2, 0.22, 0.28), bevel=0.05, rot=(0, sgn * 11, 0))
        p.append(brace)
    a.part("Body", p, collide=True)
    return a


def base_arch():
    """Wooden gate: two log posts, a beam, a hanging plank sign (text added in game)."""
    a = Asset("BaseArch", "prop")
    use(a)
    p = []
    for x in (-7, 7):
        p.append(cyl(WOOD_DARK, loc=(x, 0, 4.6), r=0.75, h=9.2, verts=12))
        p.append(cyl(WOOD, loc=(x, 0, 9.3), r=0.8, h=0.25, verts=12))
        for z in (1.5, 4.0, 6.5):
            p.append(torus(WOOD_LIGHT, loc=(x, 0, z), R=0.76, r=0.06, seg=16, mseg=4))
        p.append(box("8C8C96", loc=(x, 0, 0.35), size=(2.0, 2.0, 0.7), bevel=0.3))
    p.append(box(WOOD, loc=(0, 0, 9.5), size=(17.5, 1.3, 1.1), bevel=0.2))
    p.append(box(WOOD_DARK, loc=(0, 0, 10.15), size=(18.5, 1.5, 0.3), bevel=0.08))
    for x in (-5.5, 5.5):
        p.append(box(WOOD_LIGHT, loc=(x * 0.95, 0, 7.6), size=(4.2, 0.4, 0.4), bevel=0.08, rot=(0, x / abs(x) * -38, 0)))
    # plank sign board (SurfaceGui is added in game)
    for k in range(4):
        p.append(box(WOOD_LIGHT if k % 2 else WOOD, loc=(0, 0, 10.4 + k * 0.75), size=(11, 0.5, 0.72), bevel=0.06))
    p.append(box(WOOD_DARK, loc=(0, 0.15, 11.55), size=(11.6, 0.4, 3.4), bevel=0.1))
    a.part("Body", p, collide=True)
    a.extra["sign"] = [0, 11.4, -0.3]
    return a


def hatchery():
    """Egg pad: a round wooden deck with a straw nest ring (eggs incubate on it)."""
    a = Asset("Hatchery", "prop")
    use(a)
    p = [cyl(WOOD_DARK, loc=(0, 0, 0.3), r=9, h=0.6, verts=32),
         cyl(WOOD, loc=(0, 0, 0.72), r=8.4, h=0.3, verts=32)]
    for i in range(-7, 8):
        half = math.sqrt(max(0.0, 8.3 ** 2 - (i * 1.1) ** 2))
        p.append(box(WOOD_DARK, loc=(i * 1.1 + 0.55, 0, 0.88), size=(0.06, half * 2, 0.04)))
    p.append(torus(STRAW, loc=(0, 0, 0.95), R=5.6, r=0.9, seg=40, mseg=8))
    noise = torus(shade(STRAW, -0.12), loc=(0, 0, 1.15), R=5.6, r=0.6, seg=40, mseg=6)
    noise_deform(noise, 0.18, seed=4, freq=2.2)
    p.append(noise)
    p.append(cyl(shade(STRAW, 0.2), loc=(0, 0, 0.92), r=2.2, h=0.12, verts=20))
    for i in range(8):
        ang = math.radians(i * 45 + 22.5)
        p.append(box(WOOD_DARK, loc=(math.cos(ang) * 8.7, math.sin(ang) * 8.7, 1.1), size=(0.5, 0.5, 1.6), bevel=0.08))
    a.part("Body", p, collide=True)
    return a


def incubator():
    """Wooden lantern stand next to the egg pad (warm light at night)."""
    a = Asset("Incubator", "prop")
    use(a)
    base = box(WOOD_DARK, loc=(0, 0, 0.3), size=(2.4, 2.4, 0.6), bevel=0.15)
    post = box(WOOD, loc=(0, 0, 2.6), size=(0.6, 0.6, 4.2), bevel=0.1)
    top = box(WOOD_DARK, loc=(0, 0, 4.85), size=(1.6, 1.6, 0.3), bevel=0.08)
    roof = cone(WOOD_DARK, loc=(0, 0, 5.75), r=1.25, h=0.8, verts=4, rot=(0, 0, 45), smooth=False)
    frame = [box(WOOD_DARK, loc=(x, y, 5.1), size=(0.15, 0.15, 0.9)) for x in (-0.6, 0.6) for y in (-0.6, 0.6)]
    a.part("Body", [base, post, top, roof] + frame, collide=True)
    a.part("Body_Glow", [box("FFD68C", loc=(0, 0, 5.1), size=(1.0, 1.0, 0.8), bevel=0.1)], parent="Body", glow="FFD68C")
    return a


def habitat():
    """Wooden pet hut for the pet park: plank cabin, shingled gable roof, round pet door
    facing the front (-Y), a porch step, a round window and a bone sign over the door."""
    a = Asset("Habitat", "prop")
    use(a)
    W, D, H = 12.0, 10.0, 5.5   # wall footprint and wall height
    p = []
    # stone footing and wooden floor deck
    p.append(box("8C8C96", loc=(0, 0, 0.25), size=(W + 1.2, D + 1.2, 0.5), bevel=0.2))
    p.append(box(WOOD_DARK, loc=(0, 0, 0.65), size=(W + 0.6, D + 0.6, 0.3), bevel=0.08))
    # plank walls: horizontal logs, alternating shades
    rows = 7
    for k in range(rows):
        z = 0.8 + (k + 0.5) * (H / rows)
        col = WOOD if k % 2 == 0 else WOOD_LIGHT
        th = H / rows - 0.06
        for y in (-D / 2, D / 2):
            p.append(box(col, loc=(0, y, z), size=(W, 0.5, th), bevel=0.1))
        for x in (-W / 2, W / 2):
            p.append(box(col, loc=(x, 0, z), size=(0.5, D, th), bevel=0.1))
    # corner posts
    for x in (-W / 2, W / 2):
        for y in (-D / 2, D / 2):
            p.append(box(WOOD_DARK, loc=(x, y, 0.8 + H / 2), size=(0.9, 0.9, H + 0.2), bevel=0.15))
    # gable ends: plank rows cut along the roof slope, so the triangle under the roof is closed
    top = 0.8 + H
    ridge = 4.2
    rows_g = 5
    rh = ridge / rows_g

    def half_width(z):
        return max((W / 2 + 0.25) * (1 - (z - top) / ridge), 0.05)

    for y in (-D / 2, D / 2):
        for k in range(rows_g):
            z0, z1 = top + k * rh, top + (k + 1) * rh
            plank = box(WOOD if k % 2 else WOOD_LIGHT, loc=(0, y, (z0 + z1) / 2), size=(W + 0.5, 0.45, rh - 0.06))
            deform(plank, lambda v: Vector((math.copysign(half_width(v.z), v.x), v.y, v.z)))
            p.append(plank)
    # roof: two sloped panels made of shingle rows, plus a ridge beam
    half = W / 2 + 1.0
    slope = math.degrees(math.atan2(ridge, W / 2))
    length = math.hypot(half, ridge * half / (W / 2))
    roof_cols = ("C0504A", "A8443F")
    for sgn in (-1, 1):
        for k in range(6):
            t = (k + 0.5) / 6
            cx = sgn * half * (1 - t)
            cz = top + ridge * (1 - abs(cx) / (W / 2)) + 0.4
            p.append(box(roof_cols[k % 2], loc=(cx, 0, cz), size=(length / 6 + 0.35, D + 1.6, 0.45),
                         rot=(0, sgn * slope, 0), bevel=0.1))
    p.append(cyl(WOOD_DARK, loc=(0, 0, top + ridge + 0.45), r=0.4, h=D + 1.8, rot=(90, 0, 0), verts=10))
    # chimney
    p.append(box("8C8C96", loc=(W / 4, D / 4, top + ridge + 0.2), size=(1.2, 1.2, 3.0), bevel=0.15))
    p.append(box("6E6E78", loc=(W / 4, D / 4, top + ridge + 1.8), size=(1.5, 1.5, 0.35), bevel=0.08))
    # porch step in front of the door
    p.append(box(WOOD_DARK, loc=(0, -D / 2 - 1.1, 0.3), size=(4.4, 1.8, 0.6), bevel=0.12))
    # round pet door: dark opening with a wooden ring frame
    p.append(cyl("3A2618", loc=(0, -D / 2 - 0.2, 2.6), r=1.6, h=0.3, rot=(90, 0, 0), verts=24))
    p.append(box("3A2618", loc=(0, -D / 2 - 0.2, 1.75), size=(3.2, 0.3, 1.7)))
    p.append(torus(WOOD_DARK, loc=(0, -D / 2 - 0.4, 2.6), R=1.65, r=0.22, rot=(90, 0, 0), seg=24, mseg=6))
    for x in (-1.65, 1.65):
        p.append(box(WOOD_DARK, loc=(x, -D / 2 - 0.4, 1.7), size=(0.44, 0.44, 1.8), bevel=0.08))
    # bone sign above the door
    p.append(box("F2EEE4", loc=(0, -D / 2 - 0.45, 4.95), size=(2.2, 0.3, 0.5), bevel=0.15))
    for x in (-1.15, 1.15):
        for z in (-0.25, 0.25):
            p.append(sphere("F2EEE4", loc=(x, -D / 2 - 0.45, 4.95 + z), scale=0.36, seg=12, rings=8))
    # side window frames
    for x in (-W / 2 - 0.3, W / 2 + 0.3):
        p.append(torus(WOOD_DARK, loc=(x, 0, 3.6), R=1.0, r=0.16, rot=(0, 90, 0), seg=20, mseg=6))
    # food bowl by the door
    p.append(cyl("4A90E2", loc=(2.9, -D / 2 - 1.3, 0.25), r=0.75, r2=0.55, h=0.5, verts=16))
    a.part("Body", p, collide=True)
    # warm light in the windows
    glow = [cyl("FFD68C", loc=(x, 0, 3.6), r=0.88, h=0.2, rot=(0, 90, 0), verts=20)
            for x in (-W / 2 - 0.27, W / 2 + 0.27)]
    a.part("Body_Glow", glow, parent="Body", glow="FFD68C")
    return a


def lamp():
    """Wooden lamp post with a hanging lantern."""
    a = Asset("Lamp", "prop")
    use(a)
    p = [box(WOOD_DARK, loc=(0, 0, 0.3), size=(1.4, 1.4, 0.6), bevel=0.15), box(WOOD, loc=(0, 0, 4), size=(0.45, 0.45, 8), bevel=0.08),
         box(WOOD_DARK, loc=(0, -0.7, 8.0), size=(0.35, 1.8, 0.35), bevel=0.06),
         box(WOOD_DARK, loc=(0, -0.35, 7.3), size=(0.25, 1.2, 0.25), bevel=0.04, rot=(-40, 0, 0)),
         cyl("5A5A66", loc=(0, -1.3, 7.6), r=0.04, h=0.5, verts=6),
         cone(WOOD_DARK, loc=(0, -1.3, 7.3), r=0.45, h=0.35, verts=4, rot=(0, 0, 45), smooth=False)]
    a.part("Body", p, collide=True)
    a.part("Body_Glow", [box("FFD68C", loc=(0, -1.3, 6.8), size=(0.55, 0.55, 0.7), bevel=0.08)], parent="Body", glow="FFD68C")
    a.extra["light"] = [0, 6.8, -1.3]
    return a


def pond():
    a = Asset("Pond", "prop")
    use(a)
    rim = [ico("8E8C88", loc=(math.cos(math.radians(t)) * 7, math.sin(math.radians(t)) * 5, 0.3), scale=(1.4, 1.1, 0.8), sub=1)
           for t in range(0, 360, 24)]
    a.part("Body", rim, collide=True)
    goo = cyl("5AFFB4", loc=(0, 0, 0.12), r=1, h=0.2, verts=32)
    deform(goo, lambda v: Vector((v.x * 6.6, v.y * 4.6, v.z)))
    a.part("Body_Glow", [goo], parent="Body", glow="5AFFB4")
    return a


def flag():
    a = Asset("Flag", "prop")
    use(a)
    pole = cyl("E6E6EE", loc=(0, 0, 6), r=0.15, h=12, verts=10)
    base = cyl("5A6478", loc=(0, 0, 0.2), r=0.8, h=0.4, verts=12)
    cloth = box("FFFFFF", loc=(2.4, 0, 10.4), size=(4.6, 0.1, 3.0))
    stripe = [box("3C78FF", loc=(2.4, -0.06, 10.4 + d), size=(4.6, 0.02, 0.35)) for d in (-0.8, 0.0, 0.8)]
    a.part("Body", [pole, base, cloth] + stripe, collide=True)
    return a


def satellite():
    a = Asset("Satellite", "prop")
    use(a)
    legs = [cyl("8C96AA", loc=(math.cos(math.radians(t)) * 1.2, math.sin(math.radians(t)) * 1.2, 1.5), r=0.15, h=3.2, rot=(0, 0, 0), verts=8) for t in (0, 120, 240)]
    hub = sphere("D2D6E2", loc=(0, 0, 3.3), scale=0.8)
    dish = sphere("E6EAF2", loc=(0, -0.6, 4.8), scale=(3.0, 3.0, 1.0), rot=(60, 0, 0))
    deform(dish, lambda v: v)
    ant = cyl("5A6478", loc=(0, -1.6, 5.8), r=0.08, h=2.2, rot=(60, 0, 0), verts=8)
    a.part("Body", legs + [hub, dish, ant], collide=True)
    a.part("Body_Glow", [sphere("FF5A5A", loc=(0, -2.2, 6.6), scale=0.2)], parent="Body", glow="FF5A5A")
    return a


def rocket():
    """The Rocket at the middle of the hub. Players sell dust on the ring around it."""
    a = Asset("Rocket", "prop")
    use(a)
    white, red, dark = "F5F5FA", "FF4A4A", "3A3F4A"
    body = cyl(white, loc=(0, 0, 16), r=5, h=22, verts=28)
    nose = sphere(red, loc=(0, 0, 27), scale=(5, 5, 9), seg=28, rings=14)
    deform(nose, lambda v: Vector((v.x * max(0.0, 1 - (v.z - 27) / 9) ** 0.6 if v.z > 27 else v.x,
                                   v.y * max(0.0, 1 - (v.z - 27) / 9) ** 0.6 if v.z > 27 else v.y, max(v.z, 27))))
    band = [cyl(red, loc=(0, 0, z), r=5.08, h=1.2, verts=28) for z in (8.5, 20)]
    skirt = cyl(dark, loc=(0, 0, 3.5), r=6.2, r2=5, h=3, verts=28)
    fins = []
    for i in range(4):
        ang = i * 90 + 45
        f = box(red, loc=(math.cos(math.radians(ang)) * 6.5, math.sin(math.radians(ang)) * 6.5, 5.5), size=(3.5, 0.6, 7), rot=(0, 0, ang), bevel=0.2)
        fins.append(f)
    legs = []
    for i in range(4):
        ang = i * 90
        x, y = math.cos(math.radians(ang)), math.sin(math.radians(ang))
        legs.append(tube("B4BCCD", [(x * 5.5, y * 5.5, 6), (x * 8.5, y * 8.5, 1.2)], 0.35, seg=8))
        legs.append(cyl(dark, loc=(x * 8.6, y * 8.6, 0.4), r=1.0, h=0.8, verts=12))
    windows_frame = [torus("B4BCCD", loc=(0, -4.95, z), R=1.25, r=0.25, rot=(90, 0, 0), seg=20, mseg=6) for z in (15, 23.5)]
    door = box(dark, loc=(0, -4.85, 12), size=(3.2, 0.6, 4.6), bevel=0.4)
    ramp = box("B4BCCD", loc=(0, -8.2, 5.2), size=(3.2, 7.4, 0.4), rot=(-38, 0, 0))
    a.part("Body", [body, nose, skirt, door, ramp] + band + fins + legs + windows_frame, collide=True)
    a.part("Body_Glow", [cyl("9BE6FF", loc=(0, -5.0, z), r=1.1, h=0.2, rot=(90, 0, 0), verts=18) for z in (15, 23.5)]
           + [cyl("FFB43C", loc=(0, 0, 1.6), r=4.2, h=0.4, verts=24)], parent="Body", glow="9BE6FF")
    return a


def zone_gate():
    a = Asset("ZoneGate", "prop")
    use(a)
    p = []
    for x in (-13, 13):
        p.append(box("5A6478", loc=(x, 0, 7), size=(4, 4, 14), bevel=0.5))
        p.append(box("3A3F4A", loc=(x, 0, 0.5), size=(5, 5, 1), bevel=0.3))
        p.append(sphere("B4BCCD", loc=(x, 0, 14.6), scale=(1.6, 1.6, 1.0)))
    p.append(box("5A6478", loc=(0, 0, 15.5), size=(30, 3, 3), bevel=0.6))
    p.append(box("2A3248", loc=(0, -1.6, 15.5), size=(16, 0.3, 2.2), bevel=0.2))
    a.part("Body", p, collide=True)
    a.part("Body_Glow", [box("FFFFFF", loc=(x, -2.05, 7), size=(0.5, 0.1, 12)) for x in (-13, 13)], parent="Body", glow="FFFFFF")
    a.extra["sign"] = [0, 15.5, -1.8]
    return a


def earth():
    a = Asset("Earth", "prop")
    use(a)
    ocean = sphere("3C8CFF", loc=(0, 0, 0), scale=10, seg=32, rings=18)
    land = []
    rnd = random.Random(7)
    for i in range(14):
        th = rnd.uniform(0, 2 * math.pi)
        ph = rnd.uniform(-1.1, 1.1)
        p = Vector((math.cos(ph) * math.cos(th), math.cos(ph) * math.sin(th), math.sin(ph))) * 9.75
        s = rnd.uniform(1.5, 3.4)
        land.append(sphere("5AC85A" if abs(ph) < 1.0 else "FFFFFF", loc=p * 0.985, scale=(s, s, s * 0.18), rot=(math.degrees(ph) - 90, 0, math.degrees(th) + 90)))
    a.part("Body", [ocean] + land)
    return a


def signpost():
    a = Asset("Signpost", "prop")
    use(a)
    a.part("Body", [cyl("B4783C", loc=(0, 0, 2), r=0.2, h=4, verts=8),
                    box("D2A064", loc=(0, 0, 3.6), size=(4, 0.3, 1.4), bevel=0.15)], collide=True)
    a.extra["sign"] = [0, 3.6, -0.2]
    return a


ALL = {}
for k, fn in EGGS.items():
    ALL[f"Egg_{k}"] = fn
for k, (fn, grip) in TOOLS.items():
    ALL[f"Tool_{k}"] = (lambda k=k, fn=fn, grip=grip: hand_tool(k, fn, grip))
for k, fn in VEHICLES.items():
    ALL[f"Vehicle_{k}"] = fn
ALL.update({
    "Rock_Moon1": lambda: rock("Rock_Moon1", "A8A6A0", 1, (3.2, 2.6, 2.0)),
    "Rock_Moon2": lambda: rock("Rock_Moon2", "9A9894", 2, (6, 4.5, 3.4)),
    "Rock_Moon3": lambda: rock("Rock_Moon3", "B4B2AC", 3, (1.6, 1.4, 1.1), sub=2),
    "Rock_Crater1": lambda: rock("Rock_Crater1", "7C8AA8", 4, (4, 3.2, 2.6)),
    "Rock_Crater2": lambda: rock("Rock_Crater2", "6A7894", 5, (7, 5, 4)),
    "Rock_Dark1": lambda: rock("Rock_Dark1", "4A3A66", 6, (4, 3.4, 3.0)),
    "Rock_Dark2": lambda: rock("Rock_Dark2", "3A2E52", 7, (7, 5.5, 5)),
    "Rock_Mars1": lambda: rock("Rock_Mars1", "B45A3C", 8, (4, 3.2, 2.6)),
    "Rock_Mars2": lambda: rock("Rock_Mars2", "9A4630", 9, (7.5, 5, 4.5)),
    "Crystal_Blue": lambda: crystal("Crystal_Blue", "78E6FF", 11),
    "Crystal_Purple": lambda: crystal("Crystal_Purple", "C878FF", 12, n=6, h=5),
    "Crystal_Red": lambda: crystal("Crystal_Red", "FF784A", 13, n=4, h=4.5),
    "Rock_Ice1": lambda: rock("Rock_Ice1", "B4DCF0", 14, (4, 3.2, 2.6)),
    "Rock_Ice2": lambda: rock("Rock_Ice2", "96C3E1", 15, (7, 5, 4.2)),
    "Crystal_Ice": lambda: crystal("Crystal_Ice", "D2F8FF", 16, n=7, h=5.5),
    "Tree_Bulb": lambda: alien_tree("Tree_Bulb", "8C64B4", "5AE6B4", "FFF08C", 21),
    "Tree_Puff": lambda: alien_tree("Tree_Puff", "6478A0", "FF96DC", "9BFFF5", 22, h=7),
    "Tree_Tall": lambda: alien_tree("Tree_Tall", "5A8C78", "8CDCFF", "FFB4F0", 23, h=11),
    "Mushroom_Glow": lambda: mushroom("Mushroom_Glow", "E6E0F5", "B45AFF", "9BFFF5", 31),
    "Mushroom_Mars": lambda: mushroom("Mushroom_Mars", "F5E0C8", "FF7A3C", "FFF08C", 32),
    "Fence": fence,
    "BaseArch": base_arch,
    "Hatchery": hatchery,
    "Incubator": incubator,
    "Habitat": habitat,
    "Lamp": lamp,
    "Pond": pond,
    "Flag": flag,
    "Satellite": satellite,
    "Rocket": rocket,
    "ZoneGate": zone_gate,
    "Earth": earth,
    "Signpost": signpost,
})
