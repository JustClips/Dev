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
    head = box(blue, loc=(0, -1.25, 0.02), size=(0.32, 0.6, 0.16), bevel=0.05)
    bristles = [box(white if i % 2 else "BCE6FF", loc=(0, -1.45 + i * 0.1, -0.16), size=(0.28, 0.07, 0.3), bevel=0.02) for i in range(5)]
    a.part("Handle", [handle, grip, head] + bristles)


def broom(a):
    wood, straw, band = "B4783C", "FFD25A", "D23C3C"
    stick = cyl(wood, loc=(0, 0.3, 0), r=0.09, h=3.6, rot=(90, 0, 0), verts=10)
    knob = sphere(shade(wood, -0.2), loc=(0, 2.1, 0), scale=0.12)
    b = cyl(band, loc=(0, -1.55, 0), r=0.16, h=0.25, rot=(90, 0, 0), verts=12)
    head = cone(straw, loc=(0, -2.1, 0), r=0.75, h=1.0, rot=(-90, 0, 0), verts=16)
    deform(head, lambda v: Vector((v.x, v.y, v.z * 0.35)))
    strands = [box(shade(straw, -0.15), loc=(-0.6 + i * 0.15, -2.62, 0), size=(0.05, 0.12, 0.2)) for i in range(9)]
    a.part("Handle", [stick, knob, b, head] + strands)


def mop(a):
    stick = cyl("5AC8A0", loc=(0, 0.3, 0), r=0.09, h=3.6, rot=(90, 0, 0), verts=10)
    cap = cyl("FFFFFF", loc=(0, -1.55, 0), r=0.2, h=0.3, rot=(90, 0, 0), verts=12)
    strands = []
    for i in range(10):
        ang = i * 36
        x, z = math.cos(math.radians(ang)) * 0.22, math.sin(math.radians(ang)) * 0.22
        strands.append(capsule("E6F5FF" if i % 2 else "B4E6F0", (x, -1.65, z), (x * 2.8, -2.55, z * 2.8), 0.08, seg=8))
    a.part("Handle", [stick, cap] + strands)


def leaf_blower(a):
    o = "FF8C3C"
    body = box(o, loc=(0, 0.6, -0.1), size=(0.7, 1.2, 0.8), bevel=0.15)
    engine = cyl("3A3A46", loc=(0.38, 0.6, -0.1), r=0.32, h=0.12, rot=(0, 90, 0), verts=16)
    grip = capsule("3A3A46", (0, 0.4, 0.45), (0, 1.0, 0.45), 0.1)
    tube_ = cyl("3A3A46", loc=(0, -0.7, -0.25), r=0.17, h=1.8, rot=(90, 0, 0), verts=12)
    nozzle = cyl(o, loc=(0, -1.7, -0.25), r=0.22, h=0.3, rot=(90, 0, 0), r2=0.3, verts=12)
    a.part("Handle", [body, engine, grip, tube_, nozzle])


def shop_vac(a):
    y = "FFD23C"
    canister = cyl(y, loc=(0, 0.9, -0.2), r=0.42, h=0.9, rot=(90, 0, 0), verts=18)
    lid = cyl("3A3A46", loc=(0, 1.4, -0.2), r=0.44, h=0.15, rot=(90, 0, 0), verts=18)
    grip = capsule("3A3A46", (0, 0.6, 0.35), (0, 1.2, 0.35), 0.09)
    wand = cyl("C8C8D2", loc=(0, -0.6, -0.2), r=0.1, h=2.2, rot=(90, 0, 0), verts=10)
    head = box("3A3A46", loc=(0, -1.8, -0.25), size=(1.0, 0.35, 0.25), bevel=0.06)
    a.part("Handle", [canister, lid, grip, wand, head])


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
    t = cyl(col, loc=(x, y, r), r=r, h=w, rot=(0, 90, 0), verts=16)
    h = cyl(hub, loc=(x + (w / 2) * (1 if x > 0 else -1), y, r), r=r * 0.45, h=0.06, rot=(0, 90, 0), verts=12)
    return [t, h]


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
    a.part("Body", pieces)
    # front roller brush spins in game
    by = -L / 2 - 0.9 * s
    brush = cyl("FFE678", loc=(0, by, 0.75 * s), r=0.75 * s, h=W * 1.05, rot=(0, 90, 0), verts=16)
    bristle = [box("FFB43C", loc=(0, by + math.cos(t) * 0.75 * s, 0.75 * s + math.sin(t) * 0.75 * s), size=(W * 1.05, 0.12 * s, 0.25 * s), rot=(math.degrees(t), 0, 0)) for t in [i * math.pi / 4 for i in range(8)]]
    arm = [box("3A3A46", loc=(x * (W / 2 + 0.2), by / 2 - 0.5, 1.0 * s), size=(0.25 * s, abs(by) - L / 2 + 2.5 * s, 0.25 * s)) for x in (-1, 1)]
    a.part("Body_Arms", arm, parent="Body")
    a.part("Brush", [brush] + bristle, parent="Body", joint=(0, by, 0.75 * s))
    lights = [sphere("FFF5C8", loc=(x * (W / 2 - 0.8), -L / 2 - 0.05, wr + 0.8 * s), scale=(0.3 * s, 0.1, 0.3 * s)) for x in (-1, 1)]
    a.part("Body_Glow", lights, parent="Body", glow="FFF5C8")
    a.extra["seat"] = [0, round(wr + 1.8 * s, 3), round(1 * s, 3)]
    return a


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


def fence():
    """One 8-stud fence segment along X (centered), posts at both ends."""
    a = Asset("Fence", "prop")
    use(a)
    p = []
    for x in (-4, 4):
        p.append(cyl("C8CCD8", loc=(x, 0, 1.4), r=0.22, h=2.8, verts=10))
        p.append(sphere("FFD23C", loc=(x, 0, 2.9), scale=0.28))
    for z in (0.9, 2.1):
        p.append(cyl("8C96AA", loc=(0, 0, z), r=0.12, h=8, rot=(0, 90, 0), verts=8))
    a.part("Body", p, collide=True)
    return a


def base_arch():
    a = Asset("BaseArch", "prop")
    use(a)
    p = []
    for x in (-7, 7):
        p.append(box("D2D6E2", loc=(x, 0, 4.5), size=(1.4, 1.4, 9), bevel=0.25))
        p.append(box("5A6478", loc=(x, 0, 0.3), size=(2.0, 2.0, 0.6), bevel=0.15))
    p.append(box("D2D6E2", loc=(0, 0, 9.4), size=(16.5, 1.6, 1.2), bevel=0.3))
    # sign board (SurfaceGui is added in game)
    p.append(box("2A3248", loc=(0, 0, 11.4), size=(11, 0.5, 3.0), bevel=0.3))
    a.part("Body", p, collide=True)
    a.part("Body_Glow", [box("5AFFC8", loc=(0, -0.3, 9.4), size=(15, 0.1, 0.25))], parent="Body", glow="5AFFC8")
    a.extra["sign"] = [0, 11.4, -0.3]
    return a


def hatchery():
    """Delivery pad: a round platform with a glowing ring (eggs incubate on it)."""
    a = Asset("Hatchery", "prop")
    use(a)
    p = [cyl("8C96AA", loc=(0, 0, 0.3), r=9, h=0.6, verts=32),
         cyl("D2D6E2", loc=(0, 0, 0.75), r=8.2, h=0.3, verts=32)]
    for i in range(6):
        ang = math.radians(i * 60 + 30)
        p.append(cyl("5A6478", loc=(math.cos(ang) * 8.6, math.sin(ang) * 8.6, 1.4), r=0.25, h=1.6, verts=8))
    a.part("Body", p, collide=True)
    a.part("Body_Glow", [torus("5AFFC8", loc=(0, 0, 0.92), R=7.6, r=0.18, seg=48, mseg=6),
                         torus("5AFFC8", loc=(0, 0, 0.92), R=2.2, r=0.12, seg=24, mseg=6)], parent="Body", glow="5AFFC8")
    return a


def incubator():
    a = Asset("Incubator", "prop")
    use(a)
    base = cyl("5A6478", loc=(0, 0, 0.4), r=1.6, h=0.8, verts=18)
    top = cyl("5A6478", loc=(0, 0, 4.6), r=1.3, h=0.5, verts=18)
    a.part("Body", [base, top], collide=True)
    a.part("Body_Glass", [cyl("BCE6FF", loc=(0, 0, 2.55), r=1.4, h=3.6, verts=18)], parent="Body", material="Glass")
    a.part("Body_Glow", [torus("5AFFC8", loc=(0, 0, 0.85), R=1.45, r=0.08, seg=24, mseg=6)], parent="Body", glow="5AFFC8")
    return a


def habitat():
    a = Asset("Habitat", "prop")
    use(a)
    dome = sphere("E6EAF2", loc=(0, 0, 0), scale=(9, 9, 7), seg=24, rings=12)
    deform(dome, lambda v: Vector((v.x, v.y, max(v.z, 0))))
    ribs = [torus("B4BCCD", loc=(0, 0, 0), R=8.95, r=0.25, rot=(90, 0, ang), seg=32, mseg=6) for ang in (0, 60, 120)]
    for r in ribs:
        deform(r, lambda v: Vector((v.x, v.y, max(v.z, 0))))
    door = box("5A6478", loc=(0, -8.6, 2.2), size=(3.6, 2, 4.4), bevel=0.4)
    win = [sphere("5AB4FF", loc=(math.cos(math.radians(a_)) * 8.3, math.sin(math.radians(a_)) * 8.3, 3.2), scale=(1.0, 1.0, 1.0)) for a_ in (-60, -120)]
    a.part("Body", [dome, door] + ribs, collide=True)
    a.part("Body_Glow", win + [box("FFE678", loc=(0, -9.6, 4.8), size=(2.4, 0.2, 0.3))], parent="Body", glow="FFE678")
    return a


def lamp():
    a = Asset("Lamp", "prop")
    use(a)
    p = [cyl("5A6478", loc=(0, 0, 0.3), r=0.6, h=0.6, verts=12), cyl("B4BCCD", loc=(0, 0, 4), r=0.18, h=8, verts=10),
         box("5A6478", loc=(0, -0.6, 8.0), size=(0.4, 1.6, 0.3))]
    a.part("Body", p, collide=True)
    a.part("Body_Glow", [sphere("FFF0C8", loc=(0, -1.3, 7.7), scale=(0.5, 0.5, 0.35))], parent="Body", glow="FFF0C8")
    a.extra["light"] = [0, 7.5, -1.3]
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
