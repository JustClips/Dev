"""Player base pieces in the cartoon style of the park (parkdecor.py): chunky rounded
shapes, bright colours, dark inverted-hull outlines. Same footprints and heights as the
classic pieces they replace (props.py / earth.py), so collisions and base skins still line up.

  Base_Arch       entrance gate: stone-footed log posts, leafy beam, bunting (sways)
  Base_Fence      one 8-stud picket fence segment (lots per base, so kept very light)
  Base_PetHouse   pet cabin: round door, scalloped roof, flag (sways), chimney smoke
  Base_Pond       small pond with a duck family swimming round (client) and a jumping fish
  Base_Hatchery   round egg deck with a straw nest ring (eggs sit on the ring)
  Base_Incubator  lantern stand next to the egg deck
  Base_Lamp       base lamp post with a hanging lantern (meta light point kept)

Eight bases can be on screen at once, so these stay lower-poly than the park pieces.
"""
import math
import random

from mathutils import Vector, Matrix

from lib import sphere, cyl, box, ico, to_roblox, noise_deform, deform
import fountain as F
from fountain import lathe, ellipse, scallop, outlined, paint_faces, place
from parkdecor import (asset, animate, loop, puff, rbox, post, flower, bush_blobs, blob_tube,
                       WOOD, WOOD_DARK, WOOD_LIGHT, LEAF, LEAF_DARK, LEAF_LIGHT, RED, WHITE, YELLOW,
                       BLUE, PINK, PURPLE, STONE, STONE_DARK, STONE_LIGHT, WATER, WATER_DEEP,
                       WATER_LIGHT, FOAM, FLOWERS)

STRAW, STRAW_DARK, STRAW_LIGHT = "E8C25A", "C89A3A", "F6DC8A"
ROOF, ROOF_DARK = "E8574A", "C2413A"
CREAM = "FFF4DE"
GLOW = "FFD68C"


# ------------------------------------------------------------------ arch

def base_arch(name="Base_Arch"):
    a = asset(name)
    solid = []
    bits = []
    for x in (-7, 7):
        foot = lathe(STONE, [(0.0, 0.0), (1.15, 0.0), (1.2, 0.35), (1.05, 0.9), (0.0, 0.9)], n=10, smooth=False)
        place(foot, loc=(x, 0, 0))
        log = lathe(WOOD, [(0.0, 0.8), (0.8, 0.8), (0.72, 4.5), (0.78, 9.0), (0.0, 9.0)], n=12)
        place(log, loc=(x, 0, 0))
        solid += [foot, log]
        for z in (2.2, 5.0, 7.6):
            ring = lathe(WOOD_DARK, ellipse(0.78, z, 0.09, 0.12, k=5), n=12)
            place(ring, loc=(x, 0, 0))
            bits.append(ring)
        # little lantern on the inside of each post
        bits.append(post(WOOD_DARK, (x * 0.89, 0, 6.6), (x * 0.82, -0.9, 6.6), r=0.08, seg=5))
    beam = rbox(WOOD, (0, 0, 9.5), (18.0, 1.6, 1.2), r=0.4)
    cap = rbox(WOOD_DARK, (0, 0, 10.25), (18.5, 1.9, 0.35), r=0.15)
    solid += [beam, cap]
    # leafy crown with flowers on the beam
    leaves = []
    for i, x in enumerate((-8.0, -4.6, 4.6, 8.0)):
        leaves += bush_blobs(x, 0, 10.2, 1.3, (LEAF, LEAF_LIGHT, LEAF_DARK), 30 + i, n=3)
    for i, x in enumerate((-7.6, -4.4, 4.4, 7.6)):
        for o in flower((x, -0.95, 11.0 + 0.3 * math.sin(i * 1.7)), FLOWERS[i % len(FLOWERS)], 0.42):
            leaves.append(o)
    # name board: the game hangs its own sign above, this one is a cheerful plank with a paw
    board = rbox(CREAM, (0, -0.15, 11.6), (8.5, 0.5, 2.4), r=0.25)
    rim = rbox(WOOD_DARK, (0, 0.05, 11.6), (9.0, 0.4, 2.9), r=0.25)
    paw = [sphere(PINK, loc=(0, -0.45, 11.4), scale=(0.55, 0.12, 0.45), seg=10, rings=5)]
    for k, (dx, dz) in enumerate(((-0.55, 0.45), (-0.2, 0.7), (0.2, 0.7), (0.55, 0.45))):
        paw.append(sphere(PINK, loc=(dx, -0.45, 11.4 + dz), scale=(0.17, 0.08, 0.2), seg=8, rings=4))
    a.part("Body", outlined(solid + [board, rim], 0.06) + bits + leaves + paw, collide=True)
    glow = [sphere(GLOW, loc=(x * 0.82, -0.9, 6.15), scale=(0.32, 0.32, 0.42), seg=8, rings=5) for x in (-7, 7)]
    a.part("Lamp_Glow", glow, glow=GLOW)
    # bunting under the beam: two swagged strings of triangle flags
    flags = []
    for side in (-1, 1):
        x0, x1 = side * 0.6, side * 6.2
        for k in range(6):
            u = (k + 0.5) / 6
            x = x0 + (x1 - x0) * u
            z = 8.65 - 0.7 * math.sin(u * math.pi)
            col = (RED, YELLOW, BLUE, PINK, LEAF, PURPLE)[(k + (side > 0) * 3) % 6]
            tri = cyl(col, loc=(x, -0.85, z - 0.45), r=0.5, h=0.06, rot=(90, 0, 0), verts=3, smooth=False)
            deform(tri, lambda v, z=z: Vector((v.x, v.y, z - 0.45 + (v.z - (z - 0.45)) * 1.2)))
            place(tri, loc=(0, 0, 0))
            flags.append(tri)
        line = [(x0 + (x1 - x0) * (k / 8), -0.85, 8.65 - 0.7 * math.sin(k / 8 * math.pi)) for k in range(9)]
        flags.append(blob_tube(WOOD_DARK, line, lambda u: 0.035, seg=4))
    a.part("Bunting", flags, joint=(0, -0.85, 9.0))
    animate(a, "Bunting", "swing", 6, 0.3, "x")
    a.extra["sign"] = [0, 11.4, -0.3]
    return a


# ------------------------------------------------------------------ fence

def base_fence(name="Base_Fence"):
    """8 studs along X. 30-odd per base and 8 bases, so: few verts, outlines on posts only."""
    a = asset(name)
    posts = []
    for x in (-4, 4):
        posts.append(box(WOOD, loc=(x, 0, 1.4), size=(0.6, 0.6, 2.8)))
        posts.append(sphere(WOOD_LIGHT, loc=(x, 0, 3.0), scale=(0.42, 0.42, 0.36), seg=8, rings=5))
    rails = [box(WOOD_DARK, loc=(0, 0.05, z), size=(8.0, 0.22, 0.32)) for z in (0.8, 2.15)]
    pickets = []
    for k in range(6):
        x = -3.3 + k * 1.32
        h = 2.5 + 0.18 * math.sin(k * 2.1)
        pickets.append(box(CREAM, loc=(x, -0.12, h / 2 + 0.1), size=(0.62, 0.16, h)))
        tip = box(CREAM, loc=(x, -0.12, h + 0.1 + 0.2), size=(0.62, 0.16, 0.4))
        deform(tip, lambda v, x=x, h=h: Vector((x, v.y, v.z)) if v.z > h + 0.35 else v)
        pickets.append(tip)
    a.part("Body", outlined(posts[::2] + rails, 0.05) + posts[1::2] + pickets, collide=True)
    a.extra.pop("anim")
    return a


# ------------------------------------------------------------------ pet house

def base_pethouse(name="Base_PetHouse"):
    a = asset(name)
    W, D, H = 11.0, 9.0, 5.2
    solid, bits = [], []
    # stone footing and porch
    solid.append(rbox(STONE, (0, 0, 0.3), (W + 1.4, D + 1.4, 0.6), r=0.3))
    solid.append(rbox(WOOD_DARK, (0, -D / 2 - 1.3, 0.35), (5.0, 2.2, 0.5), r=0.2))
    # chunky log walls: rounded rows that stick out at the corners
    rows = 4
    walls = []
    for k in range(rows):
        z = 0.6 + (k + 0.5) * H / rows
        col = WOOD if k % 2 == 0 else WOOD_LIGHT
        th = H / rows
        for y in (-D / 2, D / 2):
            walls.append(rbox(col, (0, y, z), (W + 0.8, 0.7, th), r=0.3))
        for x in (-W / 2, W / 2):
            walls.append(rbox(col, (x, 0, z), (0.7, D - 0.6, th), r=0.3))
    top = 0.6 + H
    ridge = 3.6
    # gable triangles (front and back)
    for y in (-D / 2, D / 2):
        g = box(WOOD_LIGHT, loc=(0, y, top + ridge / 2), size=(W + 0.2, 0.6, ridge))
        deform(g, lambda v, top=top: Vector((v.x * max(0.02, 1 - (v.z - top) / ridge), v.y, v.z)))
        bits.append(g)
    # roof: two thick slabs with a scalloped lower edge, plus a round ridge
    slope = math.degrees(math.atan2(ridge, W / 2))
    length = math.hypot(W / 2 + 1.2, ridge * (W / 2 + 1.2) / (W / 2))
    roof = []
    for sgn in (-1, 1):
        cx = sgn * (W / 2 + 1.2) / 2
        cz = top + ridge / 2 + 0.35
        roof.append(rbox(ROOF, (cx, 0, cz), (length, D + 2.0, 0.6), r=0.25, rot_y=sgn * slope))
        for k in range(7):
            yk = -D / 2 - 0.6 + k * (D + 1.2) / 6
            ex = sgn * (W / 2 + 1.05)
            bits.append(sphere(ROOF_DARK, loc=(ex, yk, top - 0.15), scale=(0.5, 0.75, 0.32), seg=8, rings=5))
    roof.append(cyl(ROOF_DARK, loc=(0, 0, top + ridge + 0.55), r=0.5, h=D + 2.2, rot=(90, 0, 0), verts=10))
    # chimney (starts inside the roof)
    chim = rbox(STONE_DARK, (W / 4, D / 4, top + ridge * 0.6 + 1.0), (1.3, 1.3, ridge * 0.6 + 2.2), r=0.2)
    chim_top = rbox(STONE, (W / 4, D / 4, top + ridge * 0.6 + 2.2), (1.7, 1.7, 0.45), r=0.15)
    # round pet door with a frame and a bone sign
    door = cyl("3A2618", loc=(0, -D / 2 - 0.36, 2.5), r=1.6, h=0.1, rot=(90, 0, 0), verts=16)
    door_lo = box("3A2618", loc=(0, -D / 2 - 0.36, 1.65), size=(3.2, 0.1, 1.7))
    frame = lathe(WOOD_DARK, ellipse(1.75, 0, 0.22, 0.22, k=5), n=16, t0=0, t1=math.pi)
    place(frame, rot_x=90, loc=(0, -D / 2 - 0.45, 2.5))
    jambs = [rbox(WOOD_DARK, (x, -D / 2 - 0.45, 1.6), (0.44, 0.44, 1.9), r=0.15) for x in (-1.75, 1.75)]
    bone = [rbox(WHITE, (0, -D / 2 - 0.5, 4.75), (2.0, 0.3, 0.45), r=0.2)]
    for x in (-1.05, 1.05):
        for dz in (-0.22, 0.22):
            bone.append(sphere(WHITE, loc=(x, -D / 2 - 0.5, 4.75 + dz), scale=0.33, seg=8, rings=5))
    # food bowl with a bone, and a ball by the porch
    bowl = lathe(BLUE, [(0.0, 0.0), (0.6, 0.0), (0.8, 0.45), (0.65, 0.45), (0.5, 0.15), (0.0, 0.15)], n=12)
    place(bowl, loc=(3.2, -D / 2 - 1.4, 0))
    kib = sphere("A8683A", loc=(3.2, -D / 2 - 1.4, 0.3), scale=(0.55, 0.55, 0.15), seg=8, rings=4)
    ball = sphere(RED, loc=(-3.4, -D / 2 - 1.7, 0.45), scale=0.45, seg=10, rings=6)
    stripe = sphere(WHITE, loc=(-3.4, -D / 2 - 1.7, 0.45), scale=(0.47, 0.47, 0.12), rot=(30, 0, 0), seg=10, rings=4)
    # flower boxes under the side windows
    planters = []
    for sx in (-1, 1):
        x = sx * (W / 2 + 0.55)
        planters.append(rbox(WOOD_DARK, (x, 0, 2.2), (0.6, 2.6, 0.5), r=0.12))
        for k, dy in enumerate((-0.8, 0.0, 0.8)):
            for o in flower((x, dy, 2.6), FLOWERS[(k + sx) % len(FLOWERS)], 0.32):
                planters.append(o)
        frm = lathe(WOOD_DARK, ellipse(0.95, 0, 0.16, 0.16, k=5), n=12)
        frm.data.transform(Matrix.Translation((x - sx * 0.1, 0, 3.8)) @ Matrix.Rotation(math.radians(90), 4, "Y"))
        planters.append(frm)
    a.part("Body", outlined(solid + roof + [chim, chim_top, bowl, ball], 0.06) + walls + bits + [door, door_lo, frame, kib, stripe] + jambs + bone + planters,
           collide=True)
    glow = []
    for sx in (-1, 1):
        g = cyl(GLOW, loc=(sx * (W / 2 + 0.36), 0, 3.8), r=0.85, h=0.1, rot=(0, 90, 0), verts=12)
        glow.append(g)
    a.part("Windows_Glow", glow, glow=GLOW)
    # pennant on the roof ridge
    fx0 = -W / 4
    pole = post(WOOD_DARK, (fx0, -D / 2 + 1.0, top + ridge * 0.5), (fx0, -D / 2 + 1.0, top + ridge + 2.6), r=0.08, seg=5)
    zc = top + ridge + 2.1
    cloth = box(YELLOW, loc=(fx0 + 0.75, -D / 2 + 1.0, zc), size=(1.5, 0.06, 1.0))
    deform(cloth, lambda v: Vector((v.x, v.y, zc + (v.z - zc) * max(0.05, 1 - (v.x - fx0) / 1.5))))
    paw = sphere(RED, loc=(fx0 + 0.6, -D / 2 + 0.95, top + ridge + 2.1), scale=(0.18, 0.05, 0.18), seg=6, rings=4)
    a.part("Flag", outlined([pole], 0.04) + [cloth, paw], joint=(fx0, -D / 2 + 1.0, top + ridge * 0.5))
    animate(a, "Flag", "sway", 10, 0.35, "y")
    puff(a, (W / 4, D / 4, top + ridge * 0.6 + 2.5), rate=0.7, size=1.0, tint="smoke")
    return a


# ------------------------------------------------------------------ pond

PRX, PRY, PZ = 6.4, 4.4, 0.25


def base_pond(name="Base_Pond"):
    a = asset(name)
    rnd = random.Random(5)
    wob = lambda t: 1 + 0.05 * math.sin(3 * t + 0.5) + 0.03 * math.cos(5 * t)
    stones = []
    n = 18
    for k in range(n):
        t = math.tau * k / n + rnd.uniform(-0.06, 0.06)
        rr = wob(t)
        x, y = math.cos(t) * (PRX + 0.55) * rr, math.sin(t) * (PRY + 0.55) * rr
        s = rnd.uniform(0.85, 1.2)
        st = ico((STONE, STONE_LIGHT, STONE_DARK, "D9CFBF")[k % 4], loc=(x, y, 0.3 * s), scale=(1.05 * s, 0.85 * s, 0.55 * s), sub=2, smooth=True)
        noise_deform(st, 0.1, seed=k + 40)
        stones.append(st)
    a.part("Body", outlined(stones, 0.05), collide=True)
    shape = lambda t, r, z: (r * wob(t) * math.hypot(PRX * math.cos(t), PRY * math.sin(t)) / PRX, z)
    water = lathe(WATER, [(0.0, -0.5), (PRX, -0.5), (PRX, PZ), (0.0, PZ)], n=36, shape=shape)
    deep = lathe(WATER_DEEP, [(0.0, PZ), (PRX * 0.5, PZ), (PRX * 0.5, PZ + 0.01), (0.0, PZ + 0.01)], n=24, shape=shape, smooth=False)
    foam = lathe(FOAM, ellipse(PRX - 0.05, PZ, 0.16, 0.05, k=5), n=36,
                 shape=lambda t, r, z: (r * wob(t) * math.hypot(math.cos(t), (PRY / PRX) * math.sin(t)), z))
    pads = []
    for (x, y, s, fl) in ((2.6, 2.0, 0.75, True), (-3.6, -1.6, 0.65, False), (0.5, -2.6, 0.55, True), (-1.8, 2.4, 0.5, False)):
        notch = rnd.uniform(0, 360)
        pad = lathe(LEAF, [(0.0, 0.0), (s, 0.0), (s, 0.05), (0.0, 0.05)], n=10, t0=math.radians(notch + 25), t1=math.radians(notch + 335), smooth=False)
        place(pad, loc=(x, y, PZ + 0.01))
        pads.append(pad)
        if fl:
            for o in flower((0, 0, 0.18), PINK, 0.4):
                place(o, loc=(x, y, PZ))
                pads.append(o)
    a.part("Water", [water, deep, foam] + pads)
    # one reed clump that sways
    cx, cy = -6.9, 2.4
    reeds = []
    for k in range(5):
        t = k / 5 * math.tau
        bx, by = cx + math.cos(t) * 0.4, cy + math.sin(t) * 0.3
        h = rnd.uniform(1.6, 2.4)
        lean = Vector((math.cos(t), math.sin(t), 0)) * 0.3
        reeds.append(blob_tube(LEAF_DARK if k % 2 else LEAF, [(bx, by, 0.1), (bx + lean.x * 0.5, by + lean.y * 0.5, h * 0.5), (bx + lean.x, by + lean.y, h)],
                               lambda u: 0.07 * (1 - u * 0.6), seg=4))
        if k % 2 == 0:
            from lib import capsule
            reeds.append(capsule("8A4E2A", (bx + lean.x, by + lean.y, h - 0.1), (bx + lean.x * 1.1, by + lean.y * 1.1, h + 0.4), 0.12, seg=6))
    a.part("Reeds", reeds, joint=(cx, cy, 0.0))
    animate(a, "Reeds", "sway", 5, 0.5, "z")
    for i, nm in enumerate(("PondFx_Duck", "PondFx_Duckling", "PondFx_Duckling")):
        loop(a, nm, (0.0, 0.0, PZ), 3.9, 2.5, 0.25, phase=-i * 0.42 - (0.15 if i else 0), bob=0.05, wake=(i == 0))
    a.extra.setdefault("fx", {})["fish"] = [to_roblox(v) for v in ((-2.4, 0.4, PZ), (2.2, -0.6, PZ))]
    return a


# ------------------------------------------------------------------ hatchery + incubator

def base_hatchery(name="Base_Hatchery"):
    """Same heights as the classic egg pad: deck top 0.87, nest ring R 5.6 (eggs sit on it)."""
    a = asset(name)
    deck = lathe(WOOD_DARK, [(0.0, 0.0), (8.8, 0.0), (9.0, 0.3), (8.8, 0.6), (0.0, 0.6)], n=48, shape=scallop(12, 0.3, rmin=8.0))
    top = lathe(WOOD, [(0.0, 0.6), (8.4, 0.6), (8.4, 0.87), (0.0, 0.87)], n=48, shape=scallop(12, 0.3, rmin=8.0), smooth=False)
    paint_faces(top, lambda c: WOOD_LIGHT if int((math.atan2(c.y, c.x) + math.pi) / math.tau * 16) % 2 else WOOD)
    nest = lathe(STRAW, ellipse(5.6, 0.95, 0.95, 0.5, k=8), n=32)
    tufts = []
    rnd = random.Random(9)
    for k in range(20):
        t = math.tau * k / 20 + rnd.uniform(-0.1, 0.1)
        r = 5.6 + rnd.choice((-0.8, 0.8))
        tufts.append(sphere((STRAW_DARK, STRAW_LIGHT)[k % 2], loc=(math.cos(t) * r, math.sin(t) * r, 1.15), scale=(0.45, 0.25, 0.18),
                            rot=(0, 0, math.degrees(t) + rnd.uniform(-40, 40)), seg=6, rings=4))
    centre = lathe(STRAW_LIGHT, [(0.0, 0.87), (2.2, 0.87), (2.0, 0.98), (0.0, 0.98)], n=16, smooth=False)
    # a little sun pattern in the middle
    rays = []
    for k in range(8):
        t = math.tau * k / 8
        rays.append(sphere(YELLOW, loc=(math.cos(t) * 2.7, math.sin(t) * 2.7, 0.9), scale=(0.55, 0.22, 0.05), rot=(0, 0, math.degrees(t)), seg=6, rings=3))
    posts = []
    for i in range(8):
        t = math.radians(i * 45 + 22.5)
        x, y = math.cos(t) * 8.7, math.sin(t) * 8.7
        posts.append(cyl(WOOD_DARK, loc=(x, y, 0.95), r=0.3, h=1.3, verts=8))
        posts.append(sphere(FLOWERS[i % len(FLOWERS)], loc=(x, y, 1.75), scale=(0.4, 0.4, 0.32), seg=8, rings=5))
    a.part("Body", outlined([deck, nest], 0.06) + [top, centre] + tufts + rays + posts, collide=True)
    a.extra.pop("anim")
    return a


def base_incubator(name="Base_Incubator"):
    a = asset(name)
    foot = rbox(WOOD_DARK, (0, 0, 0.3), (2.4, 2.4, 0.6), r=0.25)
    pole = lathe(WOOD, [(0.0, 0.6), (0.38, 0.6), (0.3, 1.2), (0.28, 4.6), (0.0, 4.6)], n=8)
    plate = rbox(WOOD_DARK, (0, 0, 4.75), (1.7, 1.7, 0.3), r=0.12)
    roof = lathe(ROOF, [(0.0, 5.55), (1.2, 5.55), (1.05, 5.7), (0.25, 6.05), (0.0, 6.15)], n=8, shape=scallop(8, 0.08, rmin=0.9))
    bars = [post(WOOD_DARK, (x, y, 4.9), (x, y, 5.6), r=0.07, seg=4) for x in (-0.6, 0.6) for y in (-0.6, 0.6)]
    egg = sphere(CREAM, loc=(0, 0, 0.95), scale=(0.3, 0.3, 0.38), seg=8, rings=6)
    spots = [sphere(PINK, loc=(0.18 * math.cos(t), 0.18 * math.sin(t) - 0.1, 1.02), scale=(0.08, 0.04, 0.08), seg=5, rings=3) for t in (0.5, 2.5)]
    a.part("Body", outlined([foot, pole, plate, roof], 0.05) + bars + [egg] + spots, collide=True)
    glow = sphere(GLOW, loc=(0, 0, 5.15), scale=(0.55, 0.55, 0.45), seg=10, rings=6)
    a.part("Lamp_Glow", [glow], glow=GLOW)
    a.extra.pop("anim")
    return a


def base_lamp(name="Base_Lamp"):
    """Same light point as the classic Lamp: lantern hangs at (0, -1.3, 6.8) Blender."""
    a = asset(name)
    foot = rbox(STONE, (0, 0, 0.3), (1.5, 1.5, 0.6), r=0.25)
    pole = lathe(WOOD, [(0.0, 0.6), (0.34, 0.6), (0.26, 1.2), (0.24, 8.0), (0.0, 8.0)], n=8)
    knob = sphere(WOOD_LIGHT, loc=(0, 0, 8.15), scale=0.3, seg=8, rings=5)
    arm = blob_tube(WOOD_DARK, [(0, 0, 7.6), (0, -0.6, 8.0), (0, -1.3, 7.9), (0, -1.3, 7.6)], lambda u: 0.11, seg=5)
    hood = lathe(ROOF, [(0.0, 7.25), (0.6, 7.25), (0.5, 7.4), (0.12, 7.65), (0.0, 7.7)], n=8)
    place(hood, loc=(0, -1.3, 0))
    base = lathe(WOOD_DARK, [(0.0, 6.25), (0.42, 6.25), (0.42, 6.38), (0.0, 6.38)], n=8, smooth=False)
    place(base, loc=(0, -1.3, 0))
    a.part("Body", outlined([foot, pole, hood], 0.05) + [knob, arm, base], collide=True)
    glow = lathe(GLOW, [(0.0, 6.38), (0.36, 6.38), (0.44, 7.25), (0.0, 7.25)], n=8, smooth=False)
    place(glow, loc=(0, -1.3, 0))
    a.part("Lamp_Glow", [glow], glow=GLOW)
    a.extra["light"] = [0, 6.8, -1.3]
    a.extra.pop("anim")
    return a


ALL = {
    "Base_Arch": base_arch,
    "Base_Fence": base_fence,
    "Base_PetHouse": base_pethouse,
    "Base_Pond": base_pond,
    "Base_Hatchery": base_hatchery,
    "Base_Incubator": base_incubator,
    "Base_Lamp": base_lamp,
}
