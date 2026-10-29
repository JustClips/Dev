"""Eggs, tools, vehicles and world props.

Hand tools are modelled along Blender Y with the business end at -Y and a `grip` point
(where the hand holds it). In Roblox that is the part's Z axis; ToolService builds the
Tool.Grip from the grip point in meta.json.
"""
import math
import random
import bpy
from mathutils import Euler, Matrix, Vector
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


EGG_H, EGG_R, EGG_LAYERS = 2.4, 0.95, 7


def egg_layers():
    """Blocky egg silhouette: (z_bottom, z_top, half_width) for each stacked square layer,
    following the old smooth egg's outline so sizes in game stay the same."""
    out = []
    th = EGG_H / EGG_LAYERS
    for i in range(EGG_LAYERS):
        t = (i + 0.5) / EGG_LAYERS
        p = on_egg(t, 0)
        half = max(0.3, round(math.hypot(p.x, p.y) / 0.05) * 0.05)
        out.append((i * th, (i + 1) * th, half))
    return out


def stud_row(col, half, zc, step=0.34, size=(0.17, 0.05, 0.13)):
    """Little raised stud tiles all round one layer (four faces), flush on the face."""
    p = []
    n = max(1, int((2 * half - 0.18) / step))
    for side in range(4):
        ang = math.radians(side * 90)
        c, s_ = math.cos(ang), math.sin(ang)
        for k in range(n):
            u = (k - (n - 1) / 2) * step
            x, y = half + size[1] / 2 - 0.01, u   # on the +X face, then turned round
            p.append(box(col, loc=(x * c - y * s_, x * s_ + y * c, zc), size=(size[1], size[0], size[2]),
                         rot=(0, 0, side * 90)))  # no bevel: keeps eggs light (they spawn by the dozen)
    return p


def egg(name, base, studs, band=None, glow=None, glow_studs=None, topper=None, accent=None):
    """Stud-style blocky egg: stacked square layers in an egg silhouette, stud tiles on every
    face, optional coloured band layers, glowing seams, and a themed topper. Every piece
    touches the stack (the floating-piece check runs on all of them)."""
    a = Asset(f"Egg_{name}", "egg")
    use(a)
    rnd = random.Random(name)
    layers = egg_layers()
    body, gp = [], []
    for i, (z0, z1, half) in enumerate(layers):
        col = band if (band and i in (2, 4)) else base
        body.append(box(col, loc=(0, 0, (z0 + z1) / 2), size=(2 * half, 2 * half, z1 - z0 + 0.02), bevel=0.06))
        zc = (z0 + z1) / 2
        tiles = stud_row(shade(col, -0.12), half, zc)
        if glow_studs:
            # a few studs glow instead (picked per egg, the same every build)
            for t in tiles:
                if rnd.random() < 0.3:
                    a.paint(t, glow_studs)
                    gp.append(t)
                else:
                    body.append(t)
        else:
            body += tiles
    top_z, top_half = layers[-1][1], layers[-1][2]
    # small cap block on top
    body.append(box(shade(base, 0.08), loc=(0, 0, top_z + 0.09), size=(top_half * 1.1, top_half * 1.1, 0.2), bevel=0.04))
    cap_top = top_z + 0.19
    if glow:
        # glowing seams between the middle layers (slightly wider than the layer under them)
        for i in (2, 4):
            z = layers[i][1]
            h = min(layers[i][2], layers[i + 1][2]) + 0.03
            gp.append(box(glow, loc=(0, 0, z), size=(2 * h, 2 * h, 0.06)))
    if topper == "sprout":
        body.append(cyl("6B4A2E", loc=(0, 0, cap_top + 0.18), r=0.06, h=0.4, verts=8))
        for x in (-1, 1):
            body.append(box(accent, loc=(x * 0.18, 0, cap_top + 0.36), size=(0.34, 0.14, 0.06), rot=(0, x * -25, 0), bevel=0.03))
    elif topper == "knobs":
        mid = layers[3]
        for x in (-1, 1):
            body.append(cyl(accent, loc=(x * (mid[2] + 0.1), 0, (mid[0] + mid[1]) / 2), r=0.26, h=0.24, rot=(0, 90, 0), verts=8))
            body.append(cyl(shade(accent, -0.2), loc=(x * (mid[2] + 0.23), 0, (mid[0] + mid[1]) / 2), r=0.14, h=0.06, rot=(0, 90, 0), verts=8))
    elif topper == "crystals":
        for (x, y, h, tilt) in ((0, 0, 0.6, 0), (0.17, 0.08, 0.38, 18), (-0.15, -0.1, 0.42, -16)):
            gp.append(cone(accent, loc=(x, y, cap_top + h / 2 - 0.04), r=0.13, h=h, verts=4, rot=(tilt, tilt * 0.5, 45), smooth=False))
    elif topper == "crown":
        c = top_half * 0.5
        for x in (-1, 1):
            for y in (-1, 1):
                body.append(cone(accent, loc=(x * c, y * c, cap_top + 0.12), r=0.11, h=0.3, verts=4, rot=(0, 0, 45), smooth=False))
        gp.append(box("FFFFFF", loc=(0, 0, cap_top + 0.05), size=(0.16, 0.16, 0.16), rot=(0, 0, 45), bevel=0.02))
    elif topper == "horns":
        for x in (-1, 1):
            hx = x * (top_half * 0.55)
            body.append(tube(accent, [(hx, 0, cap_top - 0.12), (hx * 1.6, 0, cap_top + 0.25), (hx * 1.9, 0, cap_top + 0.62)],
                             lambda i: 0.1 - i * 0.03, seg=8))
    elif topper == "orbit":
        mid = layers[3]
        # the ring cuts through the middle layer's corners, so it's held by the egg
        gp.append(torus(accent, loc=(0, 0, (mid[0] + mid[1]) / 2), R=mid[2] * 1.28, r=0.06, rot=(0, 12, 0), seg=40, mseg=6))
        for i in range(6):
            lz0, lz1, lh = layers[1 + i % 5]
            ang = math.radians(i * 60 + 20)
            gp.append(box("FFF5A0", loc=(math.cos(ang) * (lh + 0.02), math.sin(ang) * (lh + 0.02), (lz0 + lz1) / 2 + 0.08),
                          size=(0.1, 0.1, 0.1), rot=(0, 0, 45)))
    a.part("Body", body)
    if gp:
        a.part("Body_Glow", gp, parent="Body", glow=glow or glow_studs or accent or "FFF5A0")
    return a


EGGS = {
    "Common": lambda: egg("Common", "F2EFE6", studs=True),
    "Uncommon": lambda: egg("Uncommon", "7EE08A", studs=True, band="3FA55A", topper="sprout", accent="3FA55A"),
    "Rare": lambda: egg("Rare", "8CB8FF", studs=True, band="4A7ADF", topper="knobs", accent="DCE8FF"),
    "Epic": lambda: egg("Epic", "A45AFF", studs=True, band="6A30C0", glow_studs="F0B4FF", topper="crystals", accent="F0B4FF"),
    "Legendary": lambda: egg("Legendary", "FFC83C", studs=True, band="D28C14", glow="FFFFFF", topper="crown", accent="FFF0A0"),
    "Mythic": lambda: egg("Mythic", "3A2A3A", studs=True, band="2A1A26", glow="FF7A3C", glow_studs="FF5A3C", topper="horns", accent="E8DCC8"),
    "Cosmic": lambda: egg("Cosmic", "4A2AAE", studs=True, band="2A1A6E", glow="78FFF0", topper="orbit", accent="FF78E6"),
}


# ------------------------------------------------------------------------- hand tools

def hand_tool(name, build, grip):
    a = Asset(f"Tool_{name}", "tool")
    use(a)
    build(a)
    a.extra["grip"] = [round(-grip[0], 3), round(grip[2], 3), round(grip[1], 3)]
    return a


def toothbrush(a):
    """A big cartoon toothbrush: white handle with blue rubber grips, a thin neck, an oval
    head with rows of round bristle tufts (white and blue) and a striped toothpaste swirl.
    Head at -Y, bristles face -Z, the hand holds the top end (+Y)."""
    white, blue, blue_dark, mint = "F4F7FB", "3C9BFF", "2268C8", "7AF0C8"
    p = []
    # handle: tapered white body from the end cap (+Y) down to the neck
    body = cyl(white, loc=(0, 0.55, 0), r=0.17, h=1.9, rot=(90, 0, 0), verts=16)
    deform(body, lambda v: Vector((v.x * (0.75 + 0.25 * (v.y - -0.4) / 1.9),
                                   v.y, v.z * (0.75 + 0.25 * (v.y - -0.4) / 1.9))))
    p.append(body)
    p.append(sphere(white, loc=(0, 1.5, 0), scale=(0.17, 0.12, 0.17), seg=16, rings=8))
    # blue rubber grip panels on top and sides, plus a thumb rest
    p.append(box(blue, loc=(0, 0.95, 0.12), size=(0.22, 0.75, 0.12), bevel=0.05))
    for x in (-0.13, 0.13):
        p.append(box(blue, loc=(x, 0.95, 0), size=(0.1, 0.7, 0.2), bevel=0.04))
    for k in range(4):
        p.append(box(blue_dark, loc=(0, 0.7 + k * 0.17, 0.19), size=(0.18, 0.06, 0.04), bevel=0.015))
    p.append(box(blue, loc=(0, -0.05, 0.13), size=(0.16, 0.3, 0.08), bevel=0.035))
    # hanging hole ring at the end
    p.append(torus(blue_dark, loc=(0, 1.55, 0), R=0.08, r=0.025, rot=(0, 90, 0), seg=12, mseg=4))
    # neck: thin, bending slightly up toward the head
    neck = cyl(white, loc=(0, -0.65, 0.02), r=0.085, h=0.6, rot=(90, 0, 0), verts=12)
    p.append(neck)
    # head: rounded oval paddle
    head = cyl(white, loc=(0, -1.25, 0.03), r=0.2, h=0.12, verts=20)
    deform(head, lambda v: Vector((v.x, -1.25 + (v.y + 1.25) * 2.4, v.z)))
    p.append(head)
    a.part("Handle", p)
    # bristles: one rounded block (white roots, blue tips) with shallow grooves between rows
    L, Wd, H = 0.66, 0.34, 0.3
    yc, z0 = -1.25, -0.03
    tufts = [box(white, loc=(0, yc, z0 - H * 0.35), size=(Wd, L, H * 0.7), bevel=0.06, smooth=True),
             box(blue, loc=(0, yc, z0 - H * 0.82), size=(Wd + 0.01, L + 0.01, H * 0.36), bevel=0.08, smooth=True)]
    for k in range(1, 6):
        tufts.append(box("C9D6E6", loc=(0, yc - L / 2 + k * L / 6, z0 - H * 0.35), size=(Wd + 0.02, 0.025, H * 0.6)))
    # toothpaste: a striped swirl lying along the bristle tips (mint with a white stripe)
    tip = z0 - H - 0.05
    pts = [(0.02 * math.sin(t * 2.2), yc + 0.27 - t * 0.09, tip - 0.02 * math.sin(t * 1.3)) for t in range(7)]
    paste = [tube(mint, pts, 0.085, seg=10),
             tube("FFFFFF", [(x + 0.03, y, z - 0.05) for x, y, z in pts], 0.035, seg=8),
             sphere(mint, loc=(pts[0][0], pts[0][1] + 0.02, tip - 0.06), scale=(0.07, 0.06, 0.08), seg=10, rings=6)]
    a.part("Bristles", tufts + paste, parent="Handle")


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
    top = wr + 1.2 * s  # top face of the chassis: everything on the car stands on it
    if kind == "cart":
        # canopy posts run from the chassis top up into the roof (they used to stop short)
        roof_z = wr + 4.3 * s
        post_h = roof_z - top
        for x in (-1, 1):
            for y in (-1, 1):
                pieces.append(cyl("E6E6EE", loc=(x * (W / 2 - 0.6), y * 1.6 * s + 0.4 * s, top + post_h / 2), r=0.1 * s, h=post_h, verts=8))
                pieces.append(cyl("C8C8D2", loc=(x * (W / 2 - 0.6), y * 1.6 * s + 0.4 * s, top + 0.08 * s), r=0.2 * s, h=0.16 * s, verts=10))
        pieces.append(box("FFFFFF", loc=(0, 0.4 * s, roof_z), size=(W - 0.6, 4 * s, 0.25 * s), bevel=0.1 * s))
        pieces.append(box(shade(color, -0.25), loc=(0, 0.4 * s, roof_z - 0.12 * s), size=(W - 0.4, 4.2 * s, 0.12 * s), bevel=0.05 * s))
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
        # antenna stands on the chassis, the flag hangs from its top
        pieces.append(cyl("C8C8D2", loc=(-W / 2 + 0.8, 2.6 * s, top + 1.6 * s), r=0.06 * s, h=3.2 * s, verts=8))
        pieces.append(cyl("3A3A46", loc=(-W / 2 + 0.8, 2.6 * s, top + 0.1 * s), r=0.18 * s, h=0.2 * s, verts=10))
        pieces.append(box("FF5A78", loc=(-W / 2 + 0.8 + 0.5 * s, 2.6 * s, top + 2.85 * s), size=(1.0 * s, 0.06, 0.6 * s)))
    elif kind == "hover":
        # no wheels: hover pads with glowing rings, sleek nose and fins
        for p in pieces:
            if p not in (chassis, seat, back):
                bpy.data.objects.remove(p, do_unlink=True)
        pieces = [chassis]
        for x in (-1, 1):
            for y in (-1, 1):
                # pads tucked under the chassis (their top sinks into its underside)
                pieces.append(cyl("3A3A46", loc=(x * (W / 2 - 0.6), y * L * 0.32, wr - 0.2 * s), r=0.9 * s, h=0.5 * s, verts=20))
        pieces += [seat, back]
        pieces.append(sphere(shade(color, 0.15), loc=(0, -L / 2 + 0.8 * s, wr + 1.0 * s), scale=(W / 2 - 0.4, 1.8 * s, 0.7 * s)))
        # glass bubble sits on the chassis (its bottom dips into the top)
        pieces.append(sphere("9BE6FF", loc=(0, -0.9 * s, top + 0.6 * s), scale=(1.3 * s, 1.0 * s, 0.7 * s)))
        for x in (-1, 1):
            pieces.append(box(shade(color, -0.25), loc=(x * (W / 2 - 0.8), L / 2 - 0.8 * s, wr + 2.0 * s), size=(0.25 * s, 1.6 * s, 1.6 * s), bevel=0.1 * s, rot=(20, 0, 0)))
    elif kind == "rover":
        # six wheels, solar panel wings, mast camera
        for x in (-1, 1):
            pieces += wheel("2A2A33", x * (W / 2 - 0.1), 0, wr, 0.8 * s)
        pieces.append(box(shade(color, -0.1), loc=(0, -1.8 * s, wr + 2.0 * s), size=(W - 1.4, 3.0 * s, 1.8 * s), bevel=0.3 * s))
        wing_z = wr + 2.2 * s
        for x in (-1, 1):
            pieces.append(box("2A4AA0", loc=(x * (W / 2 + 1.6 * s), 1.2 * s, wing_z), size=(3.0 * s, 4.0 * s, 0.12 * s)))
            for k in range(3):
                pieces.append(box("8CB4FF", loc=(x * (W / 2 + 1.6 * s), 1.2 * s + (k - 1) * 1.3 * s, wing_z + 0.075 * s), size=(2.7 * s, 1.1 * s, 0.03 * s)))
            # wing mount: a post up from the chassis top, then an arm out to the panel's edge
            px = x * (W / 2 - 0.6)
            pieces.append(cyl("C8C8D2", loc=(px, 1.2 * s, (top + wing_z) / 2), r=0.14 * s, h=wing_z - top + 0.14 * s, verts=10))
            pieces.append(tube("C8C8D2", [(px, 1.2 * s, wing_z), (x * (W / 2 + 0.2 * s), 1.2 * s, wing_z)], 0.12 * s, seg=8))
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
        # tail fin stands on the chassis (it used to hover above it)
        pieces.append(box(shade(color, -0.25), loc=(0, L / 2 - 0.6 * s, top + 0.95 * s), size=(0.25 * s, 1.8 * s, 2.0 * s), bevel=0.08 * s))
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
    # arms run from inside the chassis' front face out to the brush hubs, in front of the
    # front wheels (they used to run through the wheels and stop short of the hubs)
    arm = []
    for x in (-1, 1):
        start = (x * (W / 2 - 0.6), -L / 2 + 0.4 * s, wr + 0.35 * s)
        end = (x * W * 0.53, by, 0.75 * s)
        arm.append(tube("3A3A46", [start, end], 0.16 * s, seg=8))
        arm.append(cyl("C8C8D2", loc=end, r=0.24 * s, h=0.2 * s, rot=(0, 90, 0), verts=10))
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
    # bumpers the same width as the body (they used to stick out past its sides)
    for y in (-1, 1):
        p.append(box("3A3A46", loc=(0, y * (L / 2 + 0.1 * s), wr + 0.45 * s), size=(W - 0.7, 0.45 * s, 0.45 * s), bevel=0.15 * s))
    for k in range(4):
        p.append(box("2A2A33", loc=(-0.75 * s + k * 0.5 * s, -L / 2 - 0.02, wr + 1.0 * s), size=(0.12 * s, 0.1 * s, 0.45 * s)))
    for x in (-1, 1):
        p.append(box(shade(color, -0.2), loc=(x * (W / 2 - 0.25), 0, wr + 0.25 * s), size=(0.35 * s, L * 0.55, 0.3 * s), bevel=0.1 * s))
    if kind != "hover":
        # dashboard in front of the seat, steering column out of it, wheel with spokes on
        # the column's end (they used to float above the floor)
        # The dash is body-coloured (darker) with a light panel facing the driver (+Y), so
        # it doesn't read as a second seat.
        dash_y = -0.9 * s
        p.append(box(shade(color, -0.3), loc=(0, dash_y, top + 0.35 * s), size=(W * 0.45, 0.5 * s, 0.7 * s), bevel=0.15 * s))
        p.append(box("E6E6EE", loc=(0, dash_y + 0.24 * s, top + 0.42 * s), size=(W * 0.36, 0.04 * s, 0.4 * s), bevel=0.015 * s))
        p.append(box("9BE6FF", loc=(-0.6 * s, dash_y + 0.27 * s, top + 0.45 * s), size=(0.45 * s, 0.03 * s, 0.25 * s)))
        p.append(box("FFD23C", loc=(0.6 * s, dash_y + 0.27 * s, top + 0.45 * s), size=(0.3 * s, 0.03 * s, 0.25 * s)))
        col0 = Vector((0, dash_y + 0.1 * s, top + 0.55 * s))
        col1 = Vector((0, -0.35 * s, top + 1.1 * s))
        p.append(tube("2A2A3A", [tuple(col0), tuple(col1)], 0.09 * s, seg=8))
        # The wheel's axis runs along the column, so it faces the driver. Rotating about X
        # by t turns +Z into (0, -sin t, cos t); t = -atan2(dy, dz) lines that up with the
        # column. In the wheel's own frame X is left/right and +Y points down the rim.
        d = col1 - col0
        tilt = -math.degrees(math.atan2(d.y, d.z))
        frame_rot = Euler((math.radians(tilt), 0, 0)).to_matrix().to_4x4()
        wheel_m = Matrix.Translation(col1) @ frame_rot
        rim_r = 0.45 * s
        p.append(torus("2A2A3A", loc=tuple(col1), R=rim_r, r=0.07 * s, rot=(tilt, 0, 0), seg=18, mseg=6))
        # three spokes from the hub to the rim, in the ring's plane: right, left, bottom
        for ang in (0, 180, 90):
            sp = box("2A2A3A", loc=(0, 0, 0), size=(rim_r, 0.08 * s, 0.07 * s))
            sp.matrix_world = wheel_m @ Matrix.Rotation(math.radians(ang), 4, "Z") @ Matrix.Translation((rim_r / 2, 0, 0))
            bpy.context.view_layer.update()
            bpy.ops.object.select_all(action="DESELECT")
            sp.select_set(True)
            bpy.context.view_layer.objects.active = sp
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
            sp.select_set(False)
            p.append(sp)
        # hub cap on the column's end, facing the driver
        n = d.normalized()
        p.append(cyl("FF4A4A", loc=tuple(col1 + n * 0.05 * s), r=0.14 * s, h=0.1 * s, rot=(tilt, 0, 0), verts=12))
    if kind not in ("hover", "rocket"):
        # one tailpipe under the rear bumper, coming out of the chassis' underside (the old
        # pair ran straight through the bumper's ends)
        tx = W / 2 - 1.2 * s
        p.append(cyl("4A4A55", loc=(tx, L / 2 + 0.05 * s, wr + 0.1 * s), r=0.13 * s, h=0.5 * s, rot=(90, 0, 0), verts=10))
        p.append(cyl("1E1E26", loc=(tx, L / 2 + 0.3 * s, wr + 0.1 * s), r=0.085 * s, h=0.04 * s, rot=(90, 0, 0), verts=10))
    for x in (-1, 1):
        # mirrors on short stalks from the body's top edge (they used to float beside the car)
        base_pt = (x * (W / 2 - 0.45), -1.3 * s, top - 0.05 * s)
        tip = (x * (W / 2 + 0.05 * s), -1.3 * s, top + 0.55 * s)
        p.append(tube("C8C8D2", [base_pt, tip], 0.06 * s, seg=6))
        p.append(sphere("C8C8D2", loc=(tip[0] + x * 0.1 * s, tip[1], tip[2] + 0.12 * s), scale=(0.18 * s, 0.1 * s, 0.24 * s)))
    if kind in ("cart", "buggy", "crawler"):
        hy = 2.9 * s if kind != "crawler" else 2.6 * s
        # dust hopper behind the seat: a bin with a darker hinged lid and a handle, and a
        # window on its BACK showing the swept leaves (the window used to face the seat,
        # so from behind it was a plain box)
        hz = wr + 2.0 * s
        p.append(box(shade(color, -0.15), loc=(0, hy, hz), size=(W * 0.62, 1.6 * s, 1.6 * s), bevel=0.3 * s))
        p.append(box(shade(color, -0.4), loc=(0, hy, hz + 0.8 * s), size=(W * 0.62 + 0.12 * s, 1.7 * s, 0.16 * s), bevel=0.06 * s))
        p.append(box("C8C8D2", loc=(0, hy + 0.84 * s, hz + 0.62 * s), size=(0.9 * s, 0.14 * s, 0.12 * s), bevel=0.04 * s))
        back = hy + 0.8 * s
        p.append(box("2A2A3A", loc=(0, back + 0.01 * s, hz - 0.05 * s), size=(W * 0.44, 0.04 * s, 0.95 * s), bevel=0.02 * s))
        p.append(box("B4E6FF", loc=(0, back + 0.03 * s, hz - 0.05 * s), size=(W * 0.4, 0.04 * s, 0.85 * s)))
        p.append(box("E09A3C", loc=(0, back + 0.05 * s, hz - 0.33 * s), size=(W * 0.38, 0.04 * s, 0.28 * s)))
        p.append(box("C8642E", loc=(0, back + 0.06 * s, hz - 0.18 * s), size=(W * 0.3, 0.04 * s, 0.08 * s)))
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
    # starts inside the roof so it never floats above the slope
    p.append(box("8C8C96", loc=(W / 4, D / 4, top + (1.0 + ridge + 1.7) / 2), size=(1.2, 1.2, ridge + 0.7), bevel=0.15))
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
    """The market in the middle of the hub (kept under the old asset name "Rocket" so the
    map code needs no change). Players sell what they swept on the ring around it.
    A square wooden market hall on a stone base: striped awnings, a counter with crates of
    fruit on each side, a scale, sacks, recycling bins at the corners, a hip roof with a
    cupola and a flag, and a blank sign board over the front (-Y) for text in game.
    Fits inside the sell ring (radius 15): footprint about 22 x 22 studs."""
    a = Asset("Rocket", "prop")
    use(a)
    stone, stone_dark = "B9B4AA", "8E8A82"
    roof, roof_dark = "C0504A", "A8443F"
    red, cream = "E8463C", "FFF4DE"
    S = 8.0          # half size of the hall (posts at +-S)
    post_h = 8.0
    p = []
    # stone base with a step all round
    p.append(box(stone_dark, loc=(0, 0, 0.3), size=(2 * S + 5, 2 * S + 5, 0.6), bevel=0.2))
    p.append(box(stone, loc=(0, 0, 0.8), size=(2 * S + 3, 2 * S + 3, 0.5), bevel=0.15))
    for i in range(-3, 4):
        for j in range(-3, 4):
            if (i + j) % 2 == 0:
                p.append(box("C9C4BA", loc=(i * 2.4, j * 2.4, 1.07), size=(2.3, 2.3, 0.06)))
    base = 1.05
    # posts: corners plus middles, each with a stone foot and a beam cap
    for x in (-S, 0, S):
        for y in (-S, 0, S):
            if x == 0 and y == 0:
                continue
            p.append(box(stone_dark, loc=(x, y, base + 0.4), size=(1.5, 1.5, 0.8), bevel=0.15))
            p.append(box(WOOD_DARK, loc=(x, y, base + post_h / 2), size=(0.9, 0.9, post_h), bevel=0.12))
    top = base + post_h
    for y in (-S, S):
        p.append(box(WOOD, loc=(0, y, top + 0.35), size=(2 * S + 1.6, 1.0, 0.7), bevel=0.12))
    for x in (-S, S):
        p.append(box(WOOD, loc=(x, 0, top + 0.35), size=(1.0, 2 * S + 1.6, 0.7), bevel=0.12))
    # hip roof (square pyramid) with an overhang, plus a ridge cap
    rf = cone(roof, loc=(0, 0, top + 0.7 + 2.7), r=(S + 1.2) * math.sqrt(2), h=5.4, verts=4, rot=(0, 0, 45), smooth=False)
    p.append(rf)
    p.append(cone(roof_dark, loc=(0, 0, top + 0.82), r=(S + 1.3) * math.sqrt(2), h=0.25, verts=4, rot=(0, 0, 45), smooth=False))
    # cupola sunk into the roof top, with a little roof and a flag
    c0 = top + 4.9                     # inside the roof, below the slope at the cupola walls
    c1 = top + 7.0
    p.append(box(WOOD_LIGHT, loc=(0, 0, (c0 + c1) / 2), size=(2.6, 2.6, c1 - c0), bevel=0.1))
    for x in (-1.3, 1.3):
        for y in (-1.3, 1.3):
            p.append(box(WOOD_DARK, loc=(x, y, (c0 + c1) / 2), size=(0.35, 0.35, c1 - c0 + 0.05), bevel=0.05))
    p.append(cone(roof, loc=(0, 0, c1 + 0.85), r=2.6, h=1.8, verts=4, rot=(0, 0, 45), smooth=False))
    p.append(cyl("5A5A66", loc=(0, 0, c1 + 2.4), r=0.08, h=2.6, verts=8))
    p.append(box("4CAF50", loc=(0.75, 0, c1 + 3.2), size=(1.4, 0.08, 0.8)))
    # striped awnings sloping out from the beams on all four sides
    stripes = 9
    # each awning hangs from the beam's outer face and slopes down and out
    AW_L, AW_ANG = 3.0, 25
    in_y, in_z = -S - 0.45, top + 0.3
    dy, dz = math.cos(math.radians(AW_ANG)) * AW_L, math.sin(math.radians(AW_ANG)) * AW_L
    aw_cy, aw_cz = in_y - dy / 2, in_z - dz / 2
    out_y, out_z = in_y - dy, in_z - dz
    for side in range(4):
        ang = side * 90
        for k in range(stripes):
            t = -S + (k + 0.5) * (2 * S / stripes)
            col = red if k % 2 == 0 else cream
            aw = box(col, loc=(t, aw_cy, aw_cz), size=(2 * S / stripes + 0.02, AW_L, 0.15), rot=(AW_ANG, 0, 0))
            scallop = cyl(col, loc=(t, out_y, out_z), r=2 * S / stripes / 2, h=0.15, rot=(90, 0, 0), verts=12)
            deform(scallop, lambda v: Vector((v.x, v.y, min(v.z, out_z))))
            for o in (aw, scallop):
                o.rotation_euler = (0, 0, math.radians(ang))
                bpy.context.view_layer.update()
                o.select_set(True)
                bpy.context.view_layer.objects.active = o
                bpy.ops.object.transform_apply(rotation=True)
                o.select_set(False)
                p.append(o)
    # one stall counter per side, with fruit crates on it
    fruit = ("FF5A4A", "FFB13C", "8BD448", "FFE04A")
    for side in range(4):
        ang = math.radians(side * 90)
        c, s_ = math.cos(ang), math.sin(ang)

        def at(x, y):
            return (x * c - y * s_, x * s_ + y * c)
        pieces = []
        cx, cy = at(0, -S + 1.6)
        pieces.append(box(WOOD, loc=(cx, cy, base + 1.0), size=(9, 1.6, 2.0) if side % 2 == 0 else (1.6, 9, 2.0), bevel=0.1))
        pieces.append(box(WOOD_DARK, loc=(cx, cy, base + 2.1), size=(9.6, 2.0, 0.25) if side % 2 == 0 else (2.0, 9.6, 0.25), bevel=0.06))
        for n, off in enumerate((-3.2, -1.1, 1.1, 3.2)):
            bx, by = at(off, -S + 1.6)
            pieces.append(box(WOOD_LIGHT, loc=(bx, by, base + 2.6), size=(1.8, 1.4, 0.75), bevel=0.06))
            col = fruit[(n + side) % 4]
            for fx in (-0.45, 0, 0.45):
                for fy in (-0.3, 0.3):
                    qx, qy = at(off + fx, -S + 1.6 + fy)
                    pieces.append(sphere(col, loc=(qx, qy, base + 3.05), scale=0.27, seg=10, rings=6))
        p.extend(pieces)
    # scale on the front counter, sacks and barrels inside
    sx, sy = 0, -S + 1.6
    p.append(cyl("5A5A66", loc=(4.4, sy, base + 2.9), r=0.08, h=1.2, verts=8))
    p.append(box("5A5A66", loc=(4.4, sy, base + 3.5), size=(1.6, 0.12, 0.12)))
    for x in (3.7, 5.1):
        p.append(cyl("D9B44A", loc=(x, sy, base + 3.1), r=0.4, r2=0.25, h=0.15, verts=12))
        p.append(cyl("5A5A66", loc=(x, sy, base + 3.3), r=0.025, h=0.42, verts=6))
    for (x, y) in ((-4.5, 3.5), (-3.2, 4.6), (4.2, 4.0)):
        sack = sphere("D8C39A", loc=(x, y, base + 0.75), scale=(0.75, 0.7, 0.85), seg=12, rings=8)
        p.append(sack)
        p.append(cyl("A88E5E", loc=(x, y, base + 1.65), r=0.2, h=0.3, verts=8))
    for (x, y) in ((0, 3.0), (1.6, 4.4)):
        p.append(cyl(WOOD, loc=(x, y, base + 1.0), r=0.8, h=2.0, verts=14))
        for z in (0.35, 1.65):
            p.append(torus("6E6E78", loc=(x, y, base + z), R=0.8, r=0.06, seg=16, mseg=4))
    # recycling bins at the four outer corners
    bins = ("3E8EDE", "4CAF50", "F2C230", "E8463C")
    for k, (x, y) in enumerate(((-S - 1.8, -S - 1.8), (S + 1.8, -S - 1.8), (S + 1.8, S + 1.8), (-S - 1.8, S + 1.8))):
        p.append(box(bins[k], loc=(x, y, base + 1.1), size=(1.6, 1.6, 2.2), bevel=0.15))
        p.append(box(bins[k], loc=(x, y, base + 2.35), size=(1.8, 1.8, 0.3), bevel=0.1))
        p.append(box(cream, loc=(x, y - 0.81, base + 1.3), size=(0.8, 0.05, 0.8)))
    # blank sign board over the front, on two short posts above the beam
    for x in (-3.5, 3.5):
        p.append(box(WOOD_DARK, loc=(x, -S - 1.0, top + 0.75), size=(0.4, 1.1, 0.4), bevel=0.05))
    p.append(box(WOOD_DARK, loc=(0, -S - 1.75, top + 1.8), size=(9.6, 0.5, 2.8), bevel=0.12))
    p.append(box(cream, loc=(0, -S - 2.05, top + 1.8), size=(9.0, 0.1, 2.2)))
    # warm lanterns hanging under the front and back beams
    lamps, p_rods = [], []
    for (x, y) in ((-4, -S), (4, -S), (-4, S), (4, S)):
        lamps.append(box("FFD68C", loc=(x, y, top - 0.9), size=(0.6, 0.6, 0.7), bevel=0.08))
        p_rods.append(cyl("5A5A66", loc=(x, y, top - 0.25), r=0.05, h=0.7, verts=6))
        p_rods.append(box(WOOD_DARK, loc=(x, y, top - 0.5), size=(0.75, 0.75, 0.12)))
    a.part("Body", p + p_rods, collide=True)
    a.part("Body_Glow", lamps, parent="Body", glow="FFD68C")
    a.extra["sign"] = [0, round(top + 1.8, 2), -round(S + 2.11, 2)]
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

# Sweep the World: Earth versions of the old Moon props, under the same names.
import earth  # noqa: E402  (imported last: it uses the helpers above)
ALL.update(earth.ALL)
