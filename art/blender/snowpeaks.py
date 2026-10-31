"""Snowy Peaks zone decor in the cartoon style of parkdecor.py (outlined, chunky, bright).

  Snow_Lodge       log cabin with a fat snowy roof, glowing windows; chimney smoke
  Snow_SkiLift     two towers and a cable; the client runs chairs up the cable
  Snow_Igloo       ice-brick igloo; a penguin waddles round it
  Snow_Snowman     snowman with a scarf (flaps) and a top hat
  Snow_Cocoa       cocoa stand with a giant mug; steam puffs
  Snow_Sled        sled with a present
  Snow_FrozenPond  ice pond with snowbanks and a bench; a penguin slides round on it
  Snow_Pine        snowy pine (sways), Snow_Rock1/2 snowy rocks
  SnowFx_Chair, SnowFx_Penguin   moved by the client
"""
import math
import random

from mathutils import Vector, Matrix

import lib
from lib import sphere, cyl, box, ico, torus, to_roblox, noise_deform
from fountain import lathe, ellipse, scallop, outlined, paint_faces, place, eye, blob_tube
from parkdecor import (asset, animate, loop, puff, fx_list, rbox, post, WOOD, WOOD_DARK, WOOD_LIGHT, RED, WHITE, YELLOW, BLUE,
                       PINK, LEAF, LEAF_DARK, STONE, STONE_DARK, STONE_LIGHT)

SNOW, SNOW_SHADE = "F4F8FF", "D6E4F5"
ICE, ICE_DEEP = "BEE2F6", "8CC8EC"
PINE, PINE_DARK = "3E8E4A", "2E6E3C"
METAL, METAL_DARK = "8890A0", "3A3F4A"
ORANGE = "FF8A3C"


def snow_blob(loc, size, seed=0):
    """Soft snow lump with a flat bottom."""
    s = sphere(SNOW, loc=loc, scale=size, seg=12, rings=7)
    z0 = loc[2]
    lib.deform(s, lambda v: Vector((v.x, v.y, max(v.z, z0))))
    paint_faces(s, lambda c: SNOW if c.z > z0 + size[2] * 0.35 else SNOW_SHADE)
    return s


def snow_lodge(name="Snow_Lodge"):
    a = asset(name)
    W, D = 14, 10
    base = rbox(STONE, (0, 0, 0.5), (W + 1, D + 1, 1.0), r=0.3)
    paint_faces(base, lambda c: STONE_DARK if int((c.x + 20) / 1.2 + (c.z > 0.5)) % 2 else STONE)
    logs = []
    for k in range(8):
        z = 1.0 + 0.375 + k * 0.75
        for y in (-D / 2, D / 2):
            logs.append(post(WOOD if k % 2 else WOOD_DARK, (-W / 2 - 0.4, y, z), (W / 2 + 0.4, y, z), r=0.42, seg=8))
        for x in (-W / 2, W / 2):
            logs.append(post(WOOD_DARK if k % 2 else WOOD, (x, -D / 2 - 0.4, z + 0.37), (x, D / 2 + 0.4, z + 0.37), r=0.42, seg=8))
    core = rbox(WOOD_LIGHT, (0, 0, 3.8), (W - 0.4, D - 0.4, 5.6), r=0.1)
    top = 1.0 + 8 * 0.75
    # gable triangles at both ends, under the ridge (the ridge runs along X)
    gables = []
    for x in (-W / 2, W / 2):
        g = rbox(WOOD_LIGHT, (x, 0, top + 1.8), (0.7, D + 0.4, 3.6), r=0.05)
        lib.deform(g, lambda v: Vector((v.x, v.y * max(0.02, 1 - (v.z - top) / 3.6), v.z)))
        gables.append(g)
    roof = []
    for side in (-1, 1):
        slab = rbox("8A3A2A", (0, side * (D / 4 + 0.6), top + 1.75), (W + 2.4, D / 2 + 2.2, 0.45), r=0.15, rot_x=-side * 34)
        roof.append(slab)
        snow = rbox(SNOW, (0, side * (D / 4 + 0.55), top + 2.15), (W + 2.6, D / 2 + 2.2, 0.55), r=0.25, rot_x=-side * 34)
        roof.append(snow)
    roof.append(cyl(SNOW, loc=(0, 0, top + 4.05), r=0.55, h=W + 2.6, rot=(0, 90, 0), verts=10))
    drift = [snow_blob((x, side * (D / 2 + 1.7), top - 0.5), (0.9, 0.7, 0.5)) for x in (-6, -3, 0, 3, 6) for side in (-1, 1)]
    icicles = [lathe(ICE, [(0.0, 0.0), (0.12, 0.0), (0.0, -0.7 - 0.3 * (i % 2))], n=6, smooth=False) for i in range(12)]
    for i, ic in enumerate(icicles):
        place(ic, loc=(-6.5 + i * 1.18, -(D / 2 + 1.9), top - 0.75))
    chim = rbox("A0503C", (4, 2.5, top + 3.0), (1.7, 1.7, 4.2), r=0.15)
    paint_faces(chim, lambda c: "8A3E2E" if int(c.z / 0.5) % 2 else "A0503C")
    chimcap = snow_blob((4, 2.5, top + 5.1), (1.1, 1.1, 0.45))
    door = rbox("5A3A26", (0, -D / 2 - 0.5, 2.6), (2.3, 0.2, 3.3), r=0.45)
    wreath = torus(PINE, loc=(0, -D / 2 - 0.65, 3.4), R=0.45, r=0.13, rot=(90, 0, 0), seg=12, mseg=5)
    bow = sphere(RED, loc=(0, -D / 2 - 0.75, 3.0), scale=(0.2, 0.06, 0.12), seg=6, rings=4)
    porch = rbox(WOOD, (0, -D / 2 - 2.2, 0.8), (8, 3.2, 0.3), r=0.1)
    porch_posts = [post(WOOD_DARK, (x, -D / 2 - 3.6, 0.9), (x, -D / 2 - 3.6, 4.9), r=0.25, seg=8) for x in (-3.8, 3.8)]
    porch_roof = [rbox("8A3A2A", (0, -D / 2 - 2.0, 5.2), (8.6, 3.8, 0.3), r=0.1, rot_x=12), rbox(SNOW, (0, -D / 2 - 2.0, 5.5), (8.8, 3.6, 0.35), r=0.15, rot_x=12)]
    sign = rbox(WOOD_DARK, (0, -D / 2 - 0.55, 4.9), (4, 0.2, 1.0), r=0.2)
    wood = [post(WOOD, (-6.4 + j * 0.64 + k * 0.32, -D / 2 - 1.6, 1.3 + k * 0.56), (-6.4 + j * 0.64 + k * 0.32, -D / 2 - 0.4, 1.3 + k * 0.56), r=0.3, seg=8)
            for k in range(3) for j in range(3 - k)]
    skis = [rbox(c, (5.0 + k * 0.5, -D / 2 - 0.8, 2.0), (0.25, 0.1, 3.6), r=0.05, rot_x=10) for k, c in enumerate((RED, BLUE))]
    a.part("Body", outlined([base, chim, door, porch] + roof, 0.06) + logs + gables + [core, chimcap, wreath, bow, sign] + drift + icicles + porch_posts + porch_roof + wood + skis, collide=True)
    a.part("Windows_Glow", [rbox("FFD27A", (x, -D / 2 - 0.5, 3.5), (2.2, 0.12, 1.8), r=0.2) for x in (-4.4, 4.4)] +
           [rbox("FFD27A", (-W / 2 - 0.5, y, 3.5), (0.12, 2.2, 1.8), r=0.2) for y in (-2, 2)], glow="FFD27A")
    puff(a, (4, 2.5, top + 5.4), rate=0.8, size=1.3, tint="smoke")
    return a


def snow_skilift(name="Snow_SkiLift"):
    """Towers 36 studs apart along Y; meta fx lift: the client runs chairs along the cable."""
    a = asset(name)
    L = 18
    p = []
    outl = []
    for y, h in ((-L, 12), (L, 16)):
        p.append(rbox(STONE, (0, y, 0.5), (3, 3, 1), r=0.2))
        outl.append(lathe(METAL, [(0.0, 0.0), (0.7, 0.0), (0.5, 0.6), (0.45, h), (0.0, h)], n=10))
        place(outl[-1], loc=(0, y, 0))
        outl.append(rbox(RED, (0, y, h + 0.3), (6.2, 0.9, 0.7), r=0.25))
        for x in (-2.6, 2.6):
            p.append(cyl(METAL_DARK, loc=(x, y, h - 0.1), r=0.5, h=0.32, rot=(90, 0, 0), verts=12))
        p.append(snow_blob((0, y, h + 0.65), (3.0, 0.55, 0.35)))
    for x in (-2.6, 2.6):
        p.append(post("2A2A2A", (x, -L, 12.3), (x, L, 16.3), r=0.07, seg=5))
    a.part("Body", outlined(outl, 0.05) + p, collide=True)
    for x, a0, a1 in ((2.6, (2.6, -L, 12.3), (2.6, L, 16.3)), (-2.6, (-2.6, L, 16.3), (-2.6, -L, 12.3))):
        fx_list(a, "lifts", {"from": to_roblox(a0), "to": to_roblox(a1), "count": 4, "speed": 0.04})
    return a


def lift_chair():
    a = asset("SnowFx_Chair")
    hang = post(METAL_DARK, (0, 0, 0), (0, 0, -3.1), r=0.06, seg=5)
    grip = sphere(METAL_DARK, loc=(0, 0, 0), scale=0.18, seg=8, rings=5)
    seat = rbox(RED, (0, 0, -3.35), (2.4, 1.0, 0.25), r=0.1)
    back = rbox(RED, (0, 0.5, -2.8), (2.4, 0.2, 1.1), r=0.1)
    bar = post(METAL_DARK, (-1.2, -0.6, -2.95), (1.2, -0.6, -2.95), r=0.05, seg=5)
    side = [post(METAL_DARK, (sx * 1.2, 0, -3.1), (sx * 1.2, 0.5, -2.3), r=0.05, seg=5) for sx in (-1, 1)]
    cap = snow_blob((0.4, 0.1, -3.22), (0.4, 0.3, 0.15))
    a.part("Body", outlined([seat, back], 0.04) + [hang, grip, bar, cap] + side)
    return a


def snow_igloo(name="Snow_Igloo"):
    a = asset(name)
    dome = lathe(SNOW, [(0.0, 0.0)] + [(4.2 * math.cos(u * math.pi / 2), 3.6 * math.sin(u * math.pi / 2)) for u in (k / 8 for k in range(9))], n=20)
    paint_faces(dome, lambda c: SNOW_SHADE if (int(c.z / 0.9) + int((math.atan2(c.y, c.x) + 4) * 20 / math.tau + (int(c.z / 0.9) % 2) * 0.5)) % 2 else SNOW)
    rings = [torus(ICE, loc=(0, 0, z), R=4.2 * math.sqrt(max(0.0, 1 - (z / 3.6) ** 2)) + 0.02, r=0.07, seg=20, mseg=3) for z in (0.9, 1.8, 2.7)]
    tunnel = lathe(SNOW, [(0.0, -2.6), (1.6, -2.6), (1.6, 0.0), (0.0, 0.0)], n=12, t0=0, t1=math.pi)
    tunnel.data.transform(Matrix.Translation((0, -6.0, 0)) @ Matrix.Rotation(math.radians(90), 4, "X"))
    hole = lathe("2A3A5A", [(0.0, 0.0), (1.05, 0.0), (1.05, 0.06), (0.0, 0.06)], n=10, t0=0, t1=math.pi, smooth=False)
    hole.data.transform(Matrix.Translation((0, -6.05, 0.0)) @ Matrix.Rotation(math.radians(90), 4, "X"))
    fish = [sphere(ORANGE, loc=(2.6, -4.6, 0.15), scale=(0.25, 0.45, 0.12), seg=8, rings=5), sphere(ORANGE, loc=(2.6, -4.1, 0.15), scale=(0.05, 0.18, 0.15), seg=6, rings=4)]
    a.part("Body", outlined([dome, tunnel], 0.05) + rings + [hole] + fish, collide=True)
    loop(a, "SnowFx_Penguin", (0, 0, 0.0), 6.2, 6.2, 0.3, bob=0.0, hop=0.1)
    return a


def penguin():
    a = asset("SnowFx_Penguin")
    body = sphere("2A3348", loc=(0, 0, 0.75), scale=(0.55, 0.5, 0.75), seg=14, rings=9)
    belly = sphere(WHITE, loc=(0, -0.22, 0.7), scale=(0.42, 0.33, 0.6), seg=12, rings=8)
    face = sphere(WHITE, loc=(0, -0.3, 1.2), scale=(0.33, 0.22, 0.24), seg=10, rings=6)
    beak = sphere(ORANGE, loc=(0, -0.55, 1.15), scale=(0.1, 0.14, 0.06), seg=6, rings=4)
    feet = [sphere(ORANGE, loc=(sx * 0.2, -0.2, 0.06), scale=(0.15, 0.22, 0.06), seg=6, rings=4) for sx in (-1, 1)]
    flips = [sphere("2A3348", loc=(sx * 0.55, 0, 0.8), scale=(0.1, 0.22, 0.4), rot=(0, sx * 20, 0), seg=8, rings=5) for sx in (-1, 1)]
    eyes = [eye((sx * 0.14, -0.42, 1.3), 0.08) for sx in (-1, 1)]
    cheeks = [sphere(PINK, loc=(sx * 0.25, -0.45, 1.13), scale=(0.07, 0.03, 0.04), seg=6, rings=3) for sx in (-1, 1)]
    scarf = torus(RED, loc=(0, 0, 1.0), R=0.42, r=0.09, seg=14, mseg=5)
    a.part("Body", outlined([body], 0.03) + [belly, face, beak, scarf] + feet + flips + eyes + cheeks)
    return a


def snow_snowman(name="Snow_Snowman"):
    a = asset(name)
    balls = [snow_blob((0, 0, 0), (1.6, 1.6, 1.6)) if False else sphere(SNOW, loc=(0, 0, 1.4), scale=1.6, seg=14, rings=9),
             sphere(SNOW, loc=(0, 0, 3.6), scale=1.15, seg=14, rings=9),
             sphere(SNOW, loc=(0, 0, 5.2), scale=0.85, seg=14, rings=9)]
    for b in balls:
        paint_faces(b, lambda c: SNOW_SHADE if c.y > 0.4 else SNOW)
    nose = lathe(ORANGE, [(0.0, 0.0), (0.16, 0.0), (0.0, 0.9)], n=8, smooth=False)
    nose.data.transform(Matrix.Translation((0, -0.75, 5.2)) @ Matrix.Rotation(math.radians(90), 4, "X"))
    eyes = [sphere("1B1530", loc=(sx * 0.3, -0.72, 5.5), scale=(0.11, 0.06, 0.13), seg=6, rings=4) for sx in (-1, 1)]
    mouth = [sphere("1B1530", loc=(math.sin(t) * 0.4, -0.75 + 0.05 * abs(math.sin(t)), 4.95 - 0.1 * math.cos(t)), scale=0.06, seg=5, rings=3) for t in (-0.8, -0.4, 0, 0.4, 0.8)]
    cheeks = [sphere(PINK, loc=(sx * 0.5, -0.65, 5.15), scale=(0.12, 0.04, 0.08), seg=6, rings=3) for sx in (-1, 1)]
    buttons = [sphere("1B1530", loc=(0, -1.12 + (z - 3.3) * 0.25, z), scale=0.13, seg=6, rings=4) for z in (3.3, 3.8, 4.2)]
    arms = [blob_tube(WOOD_DARK, [(sx * 1.0, 0, 3.8), (sx * 2.0, 0, 4.4), (sx * 2.5, 0, 5.1)], lambda u: 0.09 * (1 - 0.4 * u), seg=5) for sx in (-1, 1)]
    twigs = [post(WOOD_DARK, (sx * 2.2, 0, 4.7), (sx * 2.6, 0, 4.6), r=0.05, seg=4) for sx in (-1, 1)]
    hat = [cyl("2A2A2A", loc=(0, 0, 5.95), r=0.95, h=0.12, verts=16), cyl("2A2A2A", loc=(0, 0, 6.55), r=0.62, h=1.1, verts=16), torus(RED, loc=(0, 0, 6.15), R=0.62, r=0.07, seg=16, mseg=4)]
    collar = torus(RED, loc=(0, 0, 4.5), R=0.8, r=0.24, seg=16, mseg=6)
    paint_faces(collar, lambda c: WHITE if int((math.atan2(c.y, c.x) + 4) * 10 / math.pi) % 2 else RED)
    a.part("Body", outlined(balls + hat[:2], 0.05) + [nose, collar, hat[2]] + eyes + mouth + cheeks + buttons + arms + twigs, collide=True)
    tail = rbox(RED, (0.6, -0.65, 3.85), (0.45, 0.16, 1.3), r=0.07, rot_x=10, rot_y=20)
    paint_faces(tail, lambda c: WHITE if int((c.z - 3) / 0.3) % 2 else RED)
    a.part("Scarf", [tail], joint=(0.6, -0.7, 4.5))
    animate(a, "Scarf", "sway", 12, 0.6, "y")
    return a


def snow_cocoa(name="Snow_Cocoa"):
    a = asset(name)
    stand = rbox(WOOD, (0, 0, 1.6), (6, 3.4, 3.2), r=0.25)
    paint_faces(stand, lambda c: WOOD_DARK if int((c.x + 10) / 0.75) % 2 else WOOD)
    counter = rbox(WOOD_LIGHT, (0, -1.1, 3.3), (6.3, 1.5, 0.22), r=0.08)
    posts_ = [post(WOOD_DARK, (x, y, 3.2), (x, y, 5.6), r=0.16, seg=6) for x in (-2.9, 2.9) for y in (-1.6, 1.6)]
    roof = rbox(RED, (0, 0, 5.75), (6.4, 4.4, 0.35), r=0.15)
    paint_faces(roof, lambda c: WHITE if int((c.x + 10) / 1.0) % 2 else RED)
    snowroof = snow_blob((0, 0, 5.92), (3.3, 2.3, 0.45))
    mug = lathe(WHITE, [(0.0, 0.0), (1.0, 0.0), (1.05, 1.7), (0.85, 1.7), (0.8, 0.2), (0.0, 0.2)], n=16)
    paint_faces(mug, lambda c: RED if 0.6 < c.z < 0.95 else WHITE)
    cocoa = cyl("6B3A1E", loc=(0, 0, 1.45), r=0.84, h=0.06, verts=16)
    cream = [sphere(WHITE, loc=(math.cos(t) * 0.35, math.sin(t) * 0.35, 1.6), scale=(0.35, 0.35, 0.22), seg=8, rings=5) for t in (0, 2.1, 4.2)] + [sphere(WHITE, loc=(0, 0, 1.85), scale=0.3, seg=8, rings=5)]
    handle = torus(WHITE, loc=(1.15, 0, 0.9), R=0.45, r=0.13, rot=(90, 0, 0), seg=12, mseg=6)
    mugbits = [mug, cocoa, handle] + cream
    for o in mugbits:
        place(o, loc=(0, -1.8, 6.4))
    pole = post(WOOD_DARK, (0, -1.8, 5.8), (0, -1.8, 6.45), r=0.12, seg=6)
    cups = [lathe(RED, [(0.0, 0.0), (0.2, 0.0), (0.24, 0.42), (0.0, 0.42)], n=8) for _ in range(3)]
    for k, cp in enumerate(cups):
        place(cp, loc=(-1.5 + k * 1.5, -1.2, 3.42))
    a.part("Body", outlined([stand, counter, roof, mug], 0.05) + posts_ + [snowroof, pole] + mugbits[1:] + cups, collide=True)
    puff(a, (0, -1.8, 8.3), rate=1.0, size=0.8, tint="steam")
    return a


def snow_sled(name="Snow_Sled"):
    a = asset(name)
    runners = [blob_tube(RED, [(x, 1.6, 0.1), (x, -1.4, 0.1), (x, -1.9, 0.5), (x, -1.7, 0.85)], lambda u: 0.09, seg=6) for x in (-0.8, 0.8)]
    struts = [post(RED, (x, y, 0.1), (x, y, 0.6), r=0.07, seg=5) for x in (-0.8, 0.8) for y in (-0.8, 0.8)]
    slats = [rbox(WOOD if k % 2 else WOOD_LIGHT, (0, -1.0 + k * 0.5, 0.65), (2.0, 0.42, 0.13), r=0.05) for k in range(5)]
    gift = rbox(BLUE, (0, 0.2, 1.2), (1.0, 1.0, 0.9), r=0.1)
    paint_faces(gift, lambda c: YELLOW if abs(c.x) < 0.12 or abs(c.y - 0.2) < 0.12 else BLUE)
    bow = [sphere(YELLOW, loc=(sx * 0.2, 0.2, 1.72), scale=(0.22, 0.1, 0.14), rot=(0, sx * 25, 0), seg=6, rings=4) for sx in (-1, 1)]
    rope = blob_tube(WOOD_LIGHT, [(-0.8, -1.7, 0.85), (0, -2.4, 0.6), (0.8, -1.7, 0.85)], lambda u: 0.04, seg=4)
    a.part("Body", outlined(runners + [gift], 0.035) + struts + slats + bow + [rope], collide=True)
    return a


def snow_frozenpond(name="Snow_FrozenPond"):
    a = asset(name)
    ice = lathe(ICE, [(0.0, 0.0), (1.0, 0.0), (1.0, 0.22), (0.0, 0.22)], n=32, shape=lambda t, r, z: (r * math.hypot(11 * math.cos(t), 8 * math.sin(t)) * (1 + 0.04 * math.sin(5 * t)), z))
    deep = lathe(ICE_DEEP, [(0.0, 0.22), (0.6, 0.22), (0.6, 0.23), (0.0, 0.23)], n=24, shape=lambda t, r, z: (r * math.hypot(11 * math.cos(t), 8 * math.sin(t)), z))
    cracks = [blob_tube(WHITE, [(x, y, 0.24), (x + dx * 0.5, y + dy * 0.5, 0.24), (x + dx, y + dy, 0.24)], lambda u: 0.04, seg=4)
              for (x, y, dx, dy) in ((-3, 1, 2.2, 1.0), (2.5, -1.5, 1.6, -1.2), (4, 2.5, -1.0, 1.4), (-5, -3, 1.4, -0.6))]
    swirls = [torus(WHITE, loc=(x, y, 0.235), R=R, r=0.035, seg=20, mseg=3) for (x, y, R) in ((-3, 1, 2.2), (2.5, -1.5, 1.6))]
    rnd = random.Random(4)
    banks = []
    for t in range(0, 360, 24):
        x, y = math.cos(math.radians(t)) * 11.6, math.sin(math.radians(t)) * 8.5
        if 70 < t < 110:
            continue
        banks.append(snow_blob((x, y, 0), (rnd.uniform(1.6, 2.4), rnd.uniform(1.4, 2.0), rnd.uniform(0.6, 1.0))))
    bench = [rbox(WOOD, (0, 10.5, 1.0), (4, 0.8, 0.2), r=0.06)] + [rbox(WOOD_DARK, (x, 10.5, 0.5), (0.2, 0.7, 1.0), r=0.05) for x in (-1.6, 1.6)]
    skates = []
    for x in (-0.5, 0.3):
        skates += [rbox(WHITE, (x, 10.4, 1.35), (0.35, 0.8, 0.5), r=0.1), rbox(METAL, (x, 10.4, 1.07), (0.06, 0.9, 0.08), r=0.02)]
    a.part("Body", outlined([ice] + bench[:1], 0.05) + [deep] + cracks + swirls + banks + bench[1:] + skates, collide=True)
    loop(a, "SnowFx_Penguin", (0, 0, 0.22), 6.5, 4.5, 0.45, bob=0.0, hop=0.0)
    loop(a, "SnowFx_Penguin", (0, 0, 0.22), 6.5, 4.5, 0.45, phase=-0.5, bob=0.0, hop=0.0)
    return a


def snow_pine(name="Snow_Pine"):
    a = asset(name)
    trunk = lathe("7A4A2A", [(0.0, 0.0), (0.7, 0.0), (0.45, 0.3), (0.4, 2.2), (0.0, 2.2)], n=10)
    a.part("Body", outlined([trunk], 0.04), collide=True)
    tiers = []
    caps = []
    for i, (z, r, h) in enumerate(((1.6, 2.7, 2.6), (3.3, 2.15, 2.3), (4.8, 1.6, 2.1), (6.1, 1.05, 1.8))):
        prof = [(0.0, z), (r, z), (r * 1.02, z + 0.15)] + [(r * (1 - u) ** 1.2, z + 0.15 + h * u) for u in (0.3, 0.6, 0.85)] + [(0.0, z + h)]
        tiers.append(lathe(PINE if i % 2 else PINE_DARK, prof, n=12, shape=lambda t, rr, zz, i=i: (rr * (1 + 0.09 * math.cos(t * 7 + i)), zz)))
        cprof = [(0.0, z + h * 0.35), (r * 0.72, z + h * 0.35), (r * 0.78, z + h * 0.28)] + [(r * 0.7 * (1 - u) ** 1.2, z + h * 0.38 + h * 0.55 * u) for u in (0.3, 0.6, 0.85)] + [(0.0, z + h * 0.97)]
        caps.append(lathe(SNOW, cprof, n=12, shape=lambda t, rr, zz, i=i: (rr * (1 + 0.12 * math.cos(t * 7 + i)), zz)))
    star = sphere(YELLOW, loc=(0, 0, 8.05), scale=0.25, seg=8, rings=5)
    a.part("Canopy", outlined(tiers, 0.05) + caps + [star], joint=(0, 0, 1.0))
    animate(a, "Canopy", "sway", 1.2, 0.3, "z")
    return a


def snow_rock(name, seed, scale):
    a = asset(name)
    h = scale[2]
    rk = ico("9EA4B2", loc=(0, 0, 0.5 * h), scale=scale, sub=2, smooth=True)
    noise_deform(rk, 0.18, seed=seed)
    paint_faces(rk, lambda c: "7E8494" if c.z < 0.35 * h else "9EA4B2")
    cap = snow_blob((0, 0, h * 1.12), (scale[0] * 0.78, scale[1] * 0.72, h * 0.5))
    a.part("Body", outlined([rk, cap], 0.05), collide=True)
    return a


ALL = {
    "Snow_Lodge": snow_lodge,
    "Snow_SkiLift": snow_skilift,
    "Snow_Igloo": snow_igloo,
    "Snow_Snowman": snow_snowman,
    "Snow_Cocoa": snow_cocoa,
    "Snow_Sled": snow_sled,
    "Snow_FrozenPond": snow_frozenpond,
    "Snow_Pine": snow_pine,
    "Snow_Rock1": lambda: snow_rock("Snow_Rock1", 14, (2.0, 1.6, 1.3)),
    "Snow_Rock2": lambda: snow_rock("Snow_Rock2", 15, (3.5, 2.5, 2.1)),
    "SnowFx_Chair": lift_chair,
    "SnowFx_Penguin": penguin,
}
