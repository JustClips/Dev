"""Beach zone decor in the cartoon style of parkdecor.py (outlined, chunky, bright).

  Beach_HutA/B/C     stilted beach huts with striped walls, porthole, flag (waves)
  Beach_Lifeguard    tower with cabin, ramp, life ring, flag (waves)
  Beach_IceCream     kiosk with a giant cone on top (turns)
  Beach_Volleyball   court, net, ball (bounces)
  Beach_Sandcastle   castle with towers, moat and flag (waves); a crab walks round it
  Beach_Surfboards   rack with three boards
  Beach_Lighthouse   striped lighthouse, the light beam turns; seagulls circle it
  Beach_Boat         rowboat on the sand with oars
  Beach_Palm         palm tree (fronds sway), Beach_Umbrella beach umbrella and towel
  Beach_Rock1/2      sandy rocks with shells and a starfish
  BeachFx_Crab, BeachFx_Gull   critters the client walks / flies round
"""
import math
import random

from mathutils import Vector, Matrix

import lib
from lib import sphere, cyl, box, ico, torus, to_roblox, noise_deform
from fountain import lathe, ellipse, scallop, outlined, paint_faces, place, eye, blob_tube
from parkdecor import (asset, animate, loop, rbox, post, sweep, WOOD, WOOD_DARK, WOOD_LIGHT, RED, WHITE, YELLOW,
                       BLUE, PINK, LEAF, LEAF_DARK, LEAF_LIGHT, WATER, WATER_LIGHT, FOAM, INK)

SAND, SAND_DARK, SAND_LIGHT = "F2DA9C", "D9BB7A", "FFF0C4"
ROPE = "D8B878"
ORANGE = "FF8A3C"
TEAL = "3CC8C0"


def flag(a, name, base, h, col, col2=WHITE):
    """Pole with a cloth flag; the cloth waves round the pole."""
    x, y, z = base
    pole = [post("8890A0", (x, y, z), (x, y, z + h), r=0.07, seg=6), sphere(YELLOW, loc=(x, y, z + h + 0.1), scale=0.14, seg=8, rings=5)]
    cloth = rbox(col, (x + 0.75, y, z + h - 0.45), (1.4, 0.06, 0.8), r=0.02)
    paint_faces(cloth, lambda c: col if c.z > z + h - 0.45 else col2)
    a.part(name, outlined([cloth], 0.025), joint=(x, y, z + h))
    animate(a, name, "sway", 18, 0.35, "y")
    return pole


# ------------------------------------------------------------------ huts

def beach_hut(name, wall, trim):
    a = asset(name)
    deck = rbox(WOOD, (0, 0, 0.75), (6.6, 6.6, 0.3), r=0.08)
    stilts = [post(WOOD_DARK, (x, y, 0), (x, y, 0.7), r=0.22, seg=8) for x in (-2.9, 2.9) for y in (-2.9, 2.9)]
    steps = [rbox(WOOD_LIGHT, (0, -3.6 - i * 0.45, 0.55 - i * 0.25), (2.4, 0.5, 0.14), r=0.05) for i in range(2)]
    walls = rbox(WHITE, (0, 0.4, 3.0), (5.6, 5.0, 4.2), r=0.15)
    paint_faces(walls, lambda c: wall if int((c.x + 10) / 0.8) % 2 else WHITE)
    door = rbox(trim, (0, -2.12, 2.1), (1.7, 0.14, 2.6), r=0.12)
    heart = sphere(WHITE, loc=(0, -2.22, 2.9), scale=(0.18, 0.04, 0.16), seg=8, rings=5)
    knob = sphere(YELLOW, loc=(0.55, -2.25, 2.0), scale=0.11, seg=6, rings=4)
    port = torus(trim, loc=(-1.9, -2.12, 3.3), R=0.55, r=0.12, rot=(90, 0, 0), seg=14, mseg=6)
    glass = cyl("8ED8FF", loc=(-1.9, -2.1, 3.3), r=0.5, h=0.06, rot=(90, 0, 0), verts=14)
    ring = torus(ORANGE, loc=(1.9, -2.15, 3.3), R=0.5, r=0.16, rot=(90, 0, 0), seg=14, mseg=6)
    paint_faces(ring, lambda c: WHITE if int((math.atan2(c.z - 3.3, c.x - 1.9) + 4) * 4 / math.pi) % 2 else ORANGE)
    # chunky scalloped roof, two-tone stripes
    roof = lathe(trim, [(0.0, 5.05), (4.4, 5.05), (4.45, 5.3), (0.25, 7.8), (0.0, 7.85)], n=4, smooth=False,
                 shape=lambda t, r, z: (r, z))
    place(roof, rot_z=45, loc=(0, 0.4, 0))
    paint_faces(roof, lambda c: WHITE if int((math.degrees(math.atan2(c.y - 0.4, c.x)) + 360) / 15) % 2 else trim)
    fringe = []
    for k in range(20):
        t = math.tau * (k + 0.5) / 20
        rr = 3.05 / max(abs(math.cos(t)), abs(math.sin(t)))
        fringe.append(sphere(trim if k % 2 else WHITE, loc=(math.cos(t) * rr, 0.4 + math.sin(t) * rr, 4.95), scale=(0.35, 0.35, 0.25), seg=6, rings=4))
    shells = [sphere(PINK, loc=(x, -3.2, 0.95), scale=(0.2, 0.15, 0.08), seg=6, rings=4) for x in (-1.8, 1.9)]
    pole = flag(a, "Flag", (0, 0.4, 7.8), 1.8, wall)
    a.part("Body", outlined([deck, walls, roof, door], 0.05) + stilts + steps + [heart, knob, port, glass, ring] + fringe + shells + pole, collide=True)
    return a


def beach_lifeguard(name="Beach_Lifeguard"):
    a = asset(name)
    legs = []
    for dx in (-1, 1):
        for dy in (-1, 1):
            legs.append(post(WHITE, (dx * 2.3, dy * 2.3, 0), (dx * 1.7, dy * 1.7, 6.0), r=0.24, seg=8))
            legs.append(sphere(RED, loc=(dx * 2.3, dy * 2.3, 0.1), scale=(0.35, 0.35, 0.15), seg=8, rings=4))
    braces = [post(WHITE, (-2.1, -2.1, 2.5), (2.1, -2.1, 2.5), r=0.12, seg=6), post(WHITE, (-2.0, 2.0, 2.5), (2.0, 2.0, 2.5), r=0.12, seg=6),
              post(WHITE, (-2.1, -2.1, 0.6), (2.0, -2.0, 4.6), r=0.1, seg=6)]
    deck = rbox(WOOD_LIGHT, (0, 0, 6.1), (5.4, 5.4, 0.35), r=0.1)
    cabin = rbox(RED, (0, 0.6, 7.7), (4.0, 3.2, 2.9), r=0.2)
    paint_faces(cabin, lambda c: WHITE if 7.4 < c.z < 8.0 else RED)
    window = rbox("8ED8FF", (0, -1.05, 8.0), (2.8, 0.1, 1.2), r=0.15)
    roof = lathe(RED, [(0.0, 9.0), (3.3, 9.0), (3.35, 9.25), (0.3, 10.7), (0.0, 10.75)], n=4, smooth=False)
    place(roof, rot_z=45, loc=(0, 0.6, 0))
    paint_faces(roof, lambda c: WHITE if int((math.degrees(math.atan2(c.y - 0.6, c.x)) + 360) / 15) % 2 else RED)
    rail = [post(WHITE, (-2.5, -2.5, 7.0), (2.5, -2.5, 7.0), r=0.09, seg=6)] + [post(WHITE, (x, -2.5, 6.2), (x, -2.5, 7.0), r=0.08, seg=6) for x in (-2.5, -1.2, 1.2, 2.5)]
    ramp = []
    for k in range(10):
        ramp.append(rbox(WOOD if k % 2 else WOOD_LIGHT, (0, -3.0 - k * 0.6, 5.7 - k * 0.6), (1.7, 0.55, 0.15), r=0.04))
    for x in (-0.9, 0.9):
        ramp.append(post(WOOD_DARK, (x, -2.6, 6.0), (x, -8.9, -0.1), r=0.12, seg=6))
        ramp.append(post(WHITE, (x, -2.5, 7.0), (x, -8.6, 1.0), r=0.06, seg=5))
    ring = torus(ORANGE, loc=(0, -1.05, 6.85), R=0.6, r=0.18, rot=(90, 0, 0), seg=14, mseg=6)
    paint_faces(ring, lambda c: WHITE if int((math.atan2(c.z - 6.85, c.x) + 4) * 4 / math.pi) % 2 else ORANGE)
    bino = [cyl("2A2A2A", loc=(sx * 0.18 + 1.5, -1.2, 7.05), r=0.12, h=0.4, rot=(90, 0, 0), verts=8) for sx in (-1, 1)]
    pole = flag(a, "Flag", (1.9, 1.9, 10.2), 2.6, RED, YELLOW)
    a.part("Body", outlined(legs[::2] + [deck, cabin, roof], 0.05) + legs[1::2] + braces + [window] + rail + ramp + [ring] + bino + pole, collide=True)
    return a


def beach_icecream(name="Beach_IceCream"):
    a = asset(name)
    stand = rbox(WHITE, (0, 0, 1.6), (6.0, 3.4, 3.2), r=0.25)
    paint_faces(stand, lambda c: PINK if 1.0 < c.z < 1.9 else WHITE)
    counter = rbox("C8E8FF", (0, -1.2, 3.25), (6.2, 1.4, 0.18), r=0.07)
    posts = [post(WHITE, (x, y, 3.2), (x, y, 6.2), r=0.1, seg=6) for x in (-2.8, 2.8) for y in (-1.6, 1.6)]
    roof = lathe(PINK, [(0.0, 6.1), (3.6, 6.1), (3.6, 6.35), (0.0, 6.55)], n=4, smooth=False)
    place(roof, rot_z=45)
    roof.data.transform(Matrix.Diagonal((1.15, 0.8, 1, 1)))
    paint_faces(roof, lambda c: WHITE if int((c.x + 10) / 0.9) % 2 else PINK)
    scallops = [sphere(PINK if k % 2 else WHITE, loc=(-3.0 + k * 0.6, -2.1, 6.05), scale=(0.32, 0.12, 0.25), seg=6, rings=4) for k in range(11)]
    stools = []
    for x in (-1.8, 0, 1.8):
        stools.append(post("8890A0", (x, -2.9, 0), (x, -2.9, 1.2), r=0.08, seg=6))
        stools.append(cyl(PINK, loc=(x, -2.9, 1.25), r=0.42, h=0.18, verts=12))
    tubs = [cyl(c, loc=(-1.6 + i * 0.8, -1.2, 3.42), r=0.3, h=0.15, verts=10) for i, c in enumerate(("FFF4DE", PINK, "8A5A3A", "9AE08A", YELLOW))]
    a.part("Body", outlined([stand, counter, roof], 0.05) + posts + scallops + stools + tubs, collide=True)
    cone = lathe("E8B05A", [(0.0, 6.6), (0.25, 6.6), (1.2, 9.2), (0.0, 9.2)], n=12, smooth=False)
    paint_faces(cone, lambda c: "D49A40" if int((c.z * 2.5 + math.atan2(c.y, c.x) * 1.2) % 2) else "E8B05A")
    scoops = [sphere(PINK, loc=(0, 0, 9.7), scale=(1.3, 1.3, 1.0), seg=14, rings=9),
              sphere("FFF4DE", loc=(0, 0, 10.8), scale=(1.0, 1.0, 0.85), seg=14, rings=9)]
    drips = [sphere(PINK, loc=(math.cos(t) * 1.15, math.sin(t) * 1.15, 9.25), scale=(0.22, 0.22, 0.35), seg=8, rings=5) for t in (0.3, 1.9, 3.6, 5.0)]
    sprinkles = [sphere(c, loc=(math.cos(t) * 0.8, math.sin(t) * 0.8, 11.3), scale=(0.12, 0.05, 0.05), rot=(0, 0, math.degrees(t) * 3), seg=5, rings=3)
                 for t, c in zip((0.2, 1.1, 2.0, 3.0, 3.9, 4.8, 5.6), (RED, BLUE, YELLOW, "9AE08A", RED, PURPLE_C, BLUE))]
    cherry = [sphere(RED, loc=(0, 0, 11.75), scale=0.32, seg=10, rings=6), post(LEAF_DARK, (0, 0, 12.0), (0.25, 0.1, 12.5), r=0.04, seg=4)]
    a.part("Cone", outlined([cone] + scoops, 0.05) + drips + sprinkles + cherry, joint=(0, 0, 6.6))
    animate(a, "Cone", "spin", 0, 0.08, "y")
    return a


PURPLE_C = "B07CFF"


def beach_volleyball(name="Beach_Volleyball"):
    a = asset(name)
    lines = [rbox(WHITE, (x, y, 0.03), (sx, sy, 0.06), r=0.01) for (x, y, sx, sy) in ((0, -6, 8.2, 0.18), (0, 6, 8.2, 0.18), (-4, 0, 0.18, 12.1), (4, 0, 0.18, 12.1))]
    posts_ = [lathe(WOOD, [(0.0, 0.0), (0.3, 0.0), (0.22, 0.3), (0.2, 5.1), (0.28, 5.2), (0.0, 5.3)], n=10) for _ in (0, 1)]
    place(posts_[0], loc=(-5, 0, 0))
    place(posts_[1], loc=(5, 0, 0))
    tops = [sphere(RED, loc=(x, 0, 5.4), scale=0.25, seg=8, rings=5) for x in (-5, 5)]
    net = rbox("2A2A2A", (0, 0, 4.0), (9.8, 0.05, 1.5), r=0.01)
    paint_faces(net, lambda c: "F4F4F4" if (int((c.x + 10) / 0.35) + int(c.z / 0.35)) % 2 else "2A2A2A")
    band = [rbox(WHITE, (0, 0, z), (10.0, 0.08, 0.2), r=0.03) for z in (4.8, 3.25)]
    a.part("Body", outlined(posts_, 0.04) + lines + tops + [net] + band, collide=True)
    ball = sphere(WHITE, loc=(2.5, -3, 1.6), scale=0.5, seg=14, rings=9)
    paint_faces(ball, lambda c: YELLOW if (c.x - 2.5) > 0.15 else (BLUE if (c.y + 3) > 0.15 else WHITE))
    a.part("Ball", outlined([ball], 0.03), joint=(2.5, -3, 1.6))
    animate(a, "Ball", "bounce", 1.3, 0.8, "y")
    return a


def beach_sandcastle(name="Beach_Sandcastle"):
    a = asset(name)
    mound = lathe(SAND_DARK, [(0.0, 0.0), (5.6, 0.0), (5.2, 0.4), (0.0, 0.6)], n=24, shape=scallop(9, 0.06))
    moat = lathe(WATER, ellipse(6.2, 0.06, 0.55, 0.08, k=6), n=32)
    keep = rbox(SAND, (0, 0, 1.7), (6.0, 6.0, 2.4), r=0.3)
    crenel = []
    for k in range(16):
        t = (k + 0.5) / 16
        side = int(t * 4)
        u = (t * 4) % 1
        x, y = [(-3 + 6 * u, -3), (3, -3 + 6 * u), (3 - 6 * u, 3), (-3, 3 - 6 * u)][side]
        crenel.append(rbox(SAND, (x * 0.95, y * 0.95, 3.1), (0.6, 0.6, 0.5), r=0.08))
    towers, caps = [], []
    for x in (-3, 3):
        for y in (-3, 3):
            towers.append(lathe(SAND, [(0.0, 0.0), (1.2, 0.0), (1.05, 3.6), (1.25, 3.7), (1.25, 4.1), (0.0, 4.1)], n=12, shape=scallop(6, 0.05)))
            place(towers[-1], loc=(x, y, 0))
            caps.append(lathe(SAND_DARK, [(0.0, 4.1), (1.25, 4.1), (0.0, 5.4)], n=10, smooth=False))
            place(caps[-1], loc=(x, y, 0))
    tall = lathe(SAND, [(0.0, 2.9), (1.7, 2.9), (1.5, 5.4), (1.75, 5.5), (1.75, 5.9), (0.0, 5.9)], n=14, shape=scallop(7, 0.05))
    gate = rbox("8A6A40", (0, -3.05, 1.3), (1.3, 0.12, 1.8), r=0.3)
    windows = [rbox("8A6A40", (x * 3, -4.2 if y < 0 else 4.2, 2.6), (0.3, 0.1, 0.5), r=0.1) for x in (-1, 1) for y in (-1,)]
    shells = [sphere(c, loc=(math.cos(t) * 5.0, math.sin(t) * 5.0, 0.45), scale=(0.25, 0.2, 0.1), seg=6, rings=4)
              for t, c in zip((0.5, 1.7, 2.6, 4.1, 5.3), (PINK, WHITE, ORANGE, PINK, WHITE))]
    bucket = [lathe(BLUE, [(0.0, 0.0), (0.5, 0.0), (0.65, 1.0), (0.55, 1.0), (0.42, 0.1), (0.0, 0.1)], n=12), torus(YELLOW, loc=(7.0, -3, 1.0), R=0.55, r=0.04, rot=(90, 0, 0), seg=12, mseg=4)]
    place(bucket[0], loc=(7.0, -3, 0))
    spade = [post(RED, (-6.0, -3.6, 0.5), (-6.6, -2.4, 1.6), r=0.06, seg=5), rbox(RED, (-5.9, -3.8, 0.12), (0.6, 0.8, 0.08), r=0.05, rot_z=25)]
    pole = flag(a, "Flag", (0, 0, 5.9), 1.8, RED, YELLOW)
    a.part("Body", outlined([keep, tall] + towers + caps, 0.05) + [mound, moat, gate] + crenel + windows + shells + bucket + spade + pole, collide=True)
    loop(a, "BeachFx_Crab", (0, 0, 0.0), 6.9, 6.9, 0.35, bob=0.0, hop=0.08)
    return a


def beach_surfboards(name="Beach_Surfboards"):
    a = asset(name)
    rack = [rbox(WOOD, (0, 0, z), (4.6, 0.45, 0.3), r=0.08) for z in (1.0, 2.6)]
    legs = [rbox(WOOD_DARK, (x, 0, 1.6), (0.32, 0.45, 3.2), r=0.08) for x in (-2.2, 2.2)]
    boards = []
    for k, (col, stripe) in enumerate(((RED, WHITE), (TEAL, YELLOW), (YELLOW, ORANGE))):
        b = sphere(col, scale=(0.6, 0.13, 3.0), seg=16, rings=10)
        paint_faces(b, lambda c, stripe=stripe, col=col: stripe if abs(c.x) < 0.12 else col)
        b.data.transform(Matrix.Translation((-1.35 + k * 1.35, -0.5, 3.0)) @ Matrix.Rotation(math.radians(-12), 4, "X"))
        boards.append(b)
    fins = [sphere(c, loc=(-1.35 + k * 1.35, -0.12, 0.6), scale=(0.05, 0.25, 0.3), seg=6, rings=4) for k, c in enumerate((WHITE, YELLOW, ORANGE))]
    a.part("Body", outlined(rack + legs + boards, 0.04) + fins, collide=True)
    return a


def beach_lighthouse(name="Beach_Lighthouse"):
    a = asset(name)
    rnd = random.Random(5)
    rocks = []
    for k in range(12):
        t = math.tau * k / 12 + rnd.uniform(-0.1, 0.1)
        s = rnd.uniform(1.6, 2.3)
        r = ico(("9EA4B2", "BCC1CC", "7E8494")[k % 3], loc=(math.cos(t) * 6.4, math.sin(t) * 6.4, 0.6 * s), scale=(s, s * 0.85, s * 0.6), sub=2, smooth=True)
        noise_deform(r, 0.2, seed=k)
        rocks.append(r)
    base = lathe("E9E5DC", [(0.0, 0.0), (5.6, 0.0), (5.6, 1.6), (5.3, 2.0), (0.0, 2.0)], n=24)
    prof = [(0.0, 2.0)]
    for i in range(9):
        z = 2.0 + i * 3.0
        r = 3.5 - i * 0.16 + 0.12 * math.sin(i * 1.3)
        prof.append((r, z))
    prof.append((2.15, 26.6))
    prof.append((0.0, 26.6))
    tower = lathe(RED, prof, n=24)
    paint_faces(tower, lambda c: RED if int((c.z - 2.0) / 3.0) % 2 == 0 else WHITE)
    door = rbox("3A6A9A", (0, -3.45, 3.6), (1.5, 0.3, 2.8), r=0.5)
    wins = [rbox("8ED8FF", (0, -3.3 + (z - 2) / 3 * 0.16 + 0.05, z), (0.9, 0.3, 1.2), r=0.3) for z in (9, 15, 21)]
    balcony = lathe("3A3F4A", [(0.0, 26.4), (3.6, 26.4), (3.6, 26.8), (0.0, 26.8)], n=20)
    rail = [torus("3A3F4A", loc=(0, 0, 27.7), R=3.4, r=0.08, seg=20, mseg=4)] + [post("3A3F4A", (math.cos(t) * 3.4, math.sin(t) * 3.4, 26.8), (math.cos(t) * 3.4, math.sin(t) * 3.4, 27.7), r=0.06, seg=4)
                                                                             for t in (math.tau * k / 12 for k in range(12))]
    cage = [post("3A3F4A", (math.cos(t) * 1.9, math.sin(t) * 1.9, 26.8), (math.cos(t) * 1.9, math.sin(t) * 1.9, 29.8), r=0.1, seg=5) for t in (math.tau * k / 6 for k in range(6))]
    roof = lathe(RED, [(0.0, 29.7), (2.6, 29.7), (2.6, 30.0), (0.3, 31.7), (0.0, 31.8)], n=16)
    knob = sphere(YELLOW, loc=(0, 0, 32.0), scale=0.4, seg=10, rings=6)
    a.part("Body", outlined(rocks + [base, tower, roof], 0.06) + [door, balcony, knob] + wins + rail + cage, collide=True)
    a.part("Lamp_Glow", [cyl("FFF0A0", loc=(0, 0, 28.25), r=1.5, h=2.9, verts=12)], glow="FFF0A0")
    beams = []
    for side in (-1, 1):
        b = lathe("FFF6C0", [(0.0, 0.0), (0.6, 0.0), (1.5, 6.5), (0.0, 6.5)], n=10, smooth=False)
        b.data.transform(Matrix.Translation((0, 0, 28.3)) @ Matrix.Rotation(math.radians(90 * side), 4, "Y"))
        beams.append(b)
    a.part("Beam_Glow", beams, glow="FFF6C0", joint=(0, 0, 28.3))
    animate(a, "Beam_Glow", "spin", 0, 0.12, "y")
    for i in range(3):
        loop(a, "BeachFx_Gull", (0, 0, 31.0 + i * 2.5), 9 + i * 3, 7 + i * 2, 0.35 - i * 0.07, phase=i * 2.1, bob=0.5, hop=0.0)
    return a


def beach_boat(name="Beach_Boat"):
    a = asset(name)
    prof = [(0.0, 0.0), (1.4, 0.15), (1.7, 0.7), (1.75, 1.2), (1.55, 1.25), (1.45, 0.75), (1.2, 0.45), (0.0, 0.4)]
    hull = lathe(BLUE, prof, n=20, shape=lambda t, r, z: (r * math.sqrt(1 / ((math.cos(t) / 1.0) ** 2 + (math.sin(t) / 2.6) ** 2)), z))
    paint_faces(hull, lambda c: WHITE if c.z > 1.0 else (RED if c.z < 0.35 else BLUE))
    seats = [rbox(WOOD, (0, y, 0.95), (2.8, 0.6, 0.15), r=0.05) for y in (-1.2, 1.2)]
    oars = []
    for side in (-1, 1):
        oars.append(post(WOOD_LIGHT, (side * 0.6, -1.6, 1.1), (side * 2.6, 2.2, 0.15), r=0.07, seg=5))
        oars.append(sphere(WOOD_LIGHT, loc=(side * 2.6, 2.3, 0.12), scale=(0.25, 0.5, 0.06), seg=8, rings=4))
    name_plate = rbox(WHITE, (1.75, -2.0, 0.85), (0.05, 1.3, 0.35), r=0.05)
    ring = torus(ORANGE, loc=(0, 3.4, 0.25), R=0.5, r=0.15, seg=14, mseg=6)
    a.part("Body", outlined([hull], 0.05) + seats + oars + [name_plate, ring], collide=True)
    return a


def beach_palm(name="Beach_Palm"):
    a = asset(name)
    seg = []
    pts = [(0.15 * math.sin(u * 2.2) + 0.9 * u * u, 0, u * 7.0) for u in (k / 10 for k in range(11))]
    for k in range(10):
        p0, p1 = Vector(pts[k]), Vector(pts[k + 1])
        seg.append(blob_tube("A8763E" if k % 2 else "8C5E2E", [p0, p1], lambda u, k=k: 0.42 - k * 0.022 + 0.06 * math.sin(u * math.pi), seg=8))
    top = Vector(pts[-1])
    nuts = [sphere("6E4224", loc=top + Vector((math.cos(t) * 0.35, math.sin(t) * 0.35, -0.35)), scale=0.3, seg=8, rings=5) for t in (0.3, 2.4, 4.4)]
    a.part("Body", outlined(seg, 0.04) + nuts, collide=True)
    fr = []
    for k in range(7):
        t = math.tau * k / 7
        d = Vector((math.cos(t), math.sin(t), 0))
        path = [top + d * (3.4 * u) + Vector((0, 0, 0.9 * math.sin(u * math.pi * 0.8) - 1.4 * u * u)) for u in (i / 6 for i in range(7))]
        fr.append(blob_tube(LEAF if k % 2 else LEAF_DARK, path, lambda u: 0.42 * math.sin(math.pi * (0.15 + 0.85 * u)) + 0.05, seg=6))
    a.part("Fronds", outlined(fr, 0.04), joint=tuple(top))
    animate(a, "Fronds", "sway", 4, 0.4, "z")
    return a


def beach_umbrella(name="Beach_Umbrella"):
    a = asset(name)
    towel = rbox(TEAL, (0.6, -0.6, 0.03), (2.2, 3.6, 0.06), r=0.03)
    paint_faces(towel, lambda c: WHITE if int((c.y + 10) / 0.6) % 2 else TEAL)
    pole = post(WHITE, (0, 0, 0), (0, 0, 4.2), r=0.08, seg=6)
    cooler = [rbox(BLUE, (-1.3, -1.0, 0.45), (1.2, 0.8, 0.8), r=0.1), rbox(WHITE, (-1.3, -1.0, 0.9), (1.25, 0.85, 0.15), r=0.06)]
    ball = sphere(RED, loc=(1.6, 1.4, 0.5), scale=0.5, seg=12, rings=8)
    paint_faces(ball, lambda c: WHITE if (c.z - 0.5) > 0.2 else (YELLOW if c.x > 1.6 else RED))
    a.part("Body", outlined([cooler[0], ball], 0.035) + [towel, pole, cooler[1]], collide=True)
    can = lathe(RED, [(0.0, 4.2), (2.8, 3.4), (2.8, 3.3), (0.0, 4.1)], n=16, smooth=False, shape=lambda t, r, z: (r * (1 + 0.05 * math.cos(t * 8)), z))
    paint_faces(can, lambda c: WHITE if int((math.atan2(c.y, c.x) + 4) * 8 / math.pi) % 2 else RED)
    a.part("Canopy", outlined([can], 0.04) + [sphere(RED, loc=(0, 0, 4.3), scale=0.16, seg=8, rings=5)], joint=(0, 0, 0))
    animate(a, "Canopy", "sway", 1.5, 0.3, "z")
    return a


def beach_rock(name, seed, scale):
    a = asset(name)
    h = scale[2]
    rk = ico(SAND, loc=(0, 0, 0.5 * h), scale=scale, sub=2, smooth=True)
    noise_deform(rk, 0.2, seed=seed)
    paint_faces(rk, lambda c: "C9A46A" if c.z < 0.3 * h else ("DDBE86" if c.z < 0.75 * h else "EBD3A0"))
    star = []
    for i in range(5):
        t = math.tau * i / 5
        star.append(sphere(ORANGE, loc=(scale[0] * 0.75 + math.cos(t) * 0.25, -scale[1] * 0.5 + math.sin(t) * 0.25, h * 0.9), scale=(0.28, 0.1, 0.06), rot=(0, 0, math.degrees(t)), seg=6, rings=3))
    shells = [sphere(PINK, loc=(-scale[0] * 1.0, -scale[1] * 0.3, 0.15), scale=(0.3, 0.25, 0.12), seg=8, rings=4),
              sphere(WHITE, loc=(scale[0] * 0.2, scale[1] * 1.0, 0.12), scale=(0.25, 0.2, 0.1), seg=8, rings=4)]
    a.part("Body", outlined([rk], 0.05) + star + shells, collide=True)
    return a


def crab():
    a = asset("BeachFx_Crab")
    body = sphere("F0544A", loc=(0, 0, 0.35), scale=(0.55, 0.4, 0.25), seg=12, rings=8)
    claws = []
    for sx in (-1, 1):
        claws.append(post("F0544A", (sx * 0.4, -0.2, 0.35), (sx * 0.65, -0.5, 0.5), r=0.07, seg=5))
        claws.append(sphere("F0544A", loc=(sx * 0.7, -0.6, 0.55), scale=(0.18, 0.14, 0.12), seg=8, rings=5))
        for k in range(3):
            claws.append(post("D8402E", (sx * 0.4, -0.05 + k * 0.18, 0.3), (sx * 0.75, 0.0 + k * 0.22, 0.0), r=0.04, seg=4))
    eyes = [post("F0544A", (sx * 0.15, -0.25, 0.5), (sx * 0.18, -0.3, 0.75), r=0.04, seg=4) for sx in (-1, 1)] + \
           [eye((sx * 0.18, -0.3, 0.82), 0.09, look=(0, -1, 0.2)) for sx in (-1, 1)]
    a.part("Body", outlined([body], 0.03) + claws + eyes)
    return a


def gull():
    a = asset("BeachFx_Gull")
    body = sphere(WHITE, loc=(0, 0, 0), scale=(0.3, 0.6, 0.28), seg=12, rings=8)
    head = sphere(WHITE, loc=(0, -0.55, 0.2), scale=0.22, seg=10, rings=6)
    beak = sphere(YELLOW, loc=(0, -0.8, 0.17), scale=(0.06, 0.14, 0.05), seg=6, rings=4)
    wings = []
    for sx in (-1, 1):
        w = blob_tube("C9D0DA", [(sx * 0.2, 0, 0.1), (sx * 0.8, 0.05, 0.35), (sx * 1.5, 0.15, 0.2)], lambda u: 0.14 * (1 - 0.6 * u), seg=5)
        w.data.transform(Matrix.Diagonal((1, 1.8, 0.5, 1)))
        wings.append(w)
        wings.append(sphere("3A3F4A", loc=(sx * 1.5, 0.2, 0.18), scale=(0.15, 0.15, 0.05), seg=6, rings=3))
    eyes = [sphere("1B1530", loc=(sx * 0.15, -0.65, 0.28), scale=0.04, seg=6, rings=3) for sx in (-1, 1)]
    a.part("Body", outlined([body, head], 0.025) + [beak] + wings + eyes)
    return a


ALL = {
    "Beach_HutA": lambda: beach_hut("Beach_HutA", PINK, "D8456A"),
    "Beach_HutB": lambda: beach_hut("Beach_HutB", "6AB8FF", "2F6FC0"),
    "Beach_HutC": lambda: beach_hut("Beach_HutC", YELLOW, "E08A2A"),
    "Beach_Lifeguard": beach_lifeguard,
    "Beach_IceCream": beach_icecream,
    "Beach_Volleyball": beach_volleyball,
    "Beach_Sandcastle": beach_sandcastle,
    "Beach_Surfboards": beach_surfboards,
    "Beach_Lighthouse": beach_lighthouse,
    "Beach_Boat": beach_boat,
    "Beach_Palm": beach_palm,
    "Beach_Umbrella": beach_umbrella,
    "Beach_Rock1": lambda: beach_rock("Beach_Rock1", 8, (2.2, 1.8, 1.4)),
    "Beach_Rock2": lambda: beach_rock("Beach_Rock2", 9, (3.4, 2.6, 2.2)),
    "BeachFx_Crab": crab,
    "BeachFx_Gull": gull,
}
