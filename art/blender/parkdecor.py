"""Park decor in the same cartoon style as the fountain (fountain.py): chunky rounded
shapes, bright colours, dark inverted-hull outlines.

  Park_DuckPond     pond with chunky rim stones, lily pads, reeds (sway), arched bridge
  Park_Playground   tower with slide, swing set (swings swing), spring duck (rocks), sandbox
  Park_Gazebo       white gazebo, scalloped striped roof, string lights, weathervane (spins)
  Park_Picnic       picnic table with checked cloth, basket, watermelon, striped umbrella
  Park_Bench        cast-iron and wood bench
  Park_Lamp         curly street lamp with a glowing lantern
  Park_FlowerBed    scalloped brick planter with big cartoon flowers (sway)
  Park_TreeRound    round green tree, Park_TreeAutumn orange tree, Park_TreeTall stacked pine
  Park_Bush         flowering bush, Park_Rock1/2 mossy rocks
  PondFx_Duck, PondFx_Duckling, PondFx_Fish, ParkFx_Leaf   animated by the client

Moving parts are their own parts with a joint (the pivot) and an entry in meta "anim":
  {kind = "sway" | "swing" | "spin", amp = degrees, speed = cycles per second, axis = "x"|"y"|"z"}
(Roblox axes). ParkFxController (client) plays them. Meta "fx" holds spots for the
client's extra meshes (pond path, tree canopy for falling leaves).
"""
import math
import random

import bmesh
from mathutils import Vector, Matrix

import lib
from lib import Asset, use, sphere, cyl, box, ico, torus, join, to_roblox, noise_deform
import fountain as F
from fountain import lathe, ellipse, scallop, hull, outlined, paint_faces, place, eye, blob_tube

WOOD, WOOD_DARK, WOOD_LIGHT = "C48E5C", "805434", "E0B482"
IRON, IRON_LIGHT = "2F5E4A", "4E8A6E"
STONE, STONE_DARK, STONE_LIGHT = F.STONE, F.STONE_DARK, F.STONE_LIGHT
WATER, WATER_DEEP, WATER_LIGHT, FOAM = F.WATER, F.WATER_DEEP, F.WATER_LIGHT, F.FOAM
LEAF, LEAF_DARK, LEAF_LIGHT = "5DBB4A", "3F9A3A", "8BD85E"
AUTUMN, AUTUMN_DARK, AUTUMN_LIGHT = "F28A2E", "D8582A", "FFC24A"
TRUNK, TRUNK_DARK = "9A6236", "6E4224"
RED, WHITE, YELLOW, BLUE, PINK, PURPLE = "F0544A", "FFFFFF", "FFD23A", "4A9BFF", "FF8CB4", "B07CFF"
SAND = "F2DA9C"
INK = F.INK
FLOWERS = ("FF5A7A", "FFD23A", "FFFFFF", "B07CFF", "FF9A3C", "5AB8FF")


def asset(name):
    a = Asset(name, "prop")
    use(a)
    a.cull = True
    a.extra["anim"] = {}
    return a


def animate(a, part, kind, amp, speed, axis="y", phase=0.0):
    """kind: sway / swing / spin (amp degrees), bounce (amp studs), blink (amp = share of
    each cycle the glow part is on, phase = where in the cycle it starts)."""
    a.extra["anim"][part] = {"kind": kind, "amp": amp, "speed": speed, "axis": axis, "phase": phase}


def fx_list(a, key, item):
    a.extra.setdefault("fx", {}).setdefault(key, []).append(item)


def loop(a, asset_name, center, rx, rz, speed, phase=0.0, bob=0.05, wake=False, hop=0.0):
    """A critter that goes round an ellipse (Roblox radii rx, rz) about a Blender-space
    centre. speed = laps per minute-ish (radians per second)."""
    fx_list(a, "loops", {"asset": asset_name, "center": to_roblox(center), "rx": rx, "rz": rz,
                         "speed": speed, "phase": phase, "bob": bob, "wake": wake, "hop": hop})


def puff(a, at, rate=1.0, size=1.0, tint="white"):
    """Smoke or steam puffs rising from a Blender-space point."""
    fx_list(a, "puffs", {"at": to_roblox(at), "rate": rate, "size": size, "tint": tint})


def sweep(color, path, profile, closed=True):
    """Extrude a 2D profile [(x, y)] (x = sideways, y = up) along a 3D path, keeping the
    profile upright where it can (parallel transport)."""
    bm = bmesh.new()
    rings = []
    prev_x = None
    N = len(path)
    for i, p in enumerate(path):
        p = Vector(p)
        d = (Vector(path[min(i + 1, N - 1)]) - Vector(path[max(i - 1, 0)])).normalized()
        if prev_x is None:
            up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((0, 1, 0))
            x = d.cross(up).normalized()
        else:
            x = (prev_x - d * prev_x.dot(d)).normalized()
        prev_x = x
        y = x.cross(d).normalized()
        if y.z < 0:
            y = -y
        rings.append([bm.verts.new(p + x * px + y * py) for (px, py) in profile])
    m = len(profile)
    for a, b in zip(rings, rings[1:]):
        for j in range(m if closed else m - 1):
            k = (j + 1) % m
            bm.faces.new((a[j], a[k], b[k], b[j]))
    if closed:
        bm.faces.new(rings[0])
        bm.faces.new(list(reversed(rings[-1])))
    o = F._obj_from_bm(bm, "sweep")
    for poly in o.data.polygons:
        poly.use_smooth = False
    lib._asset.paint(o, color)
    return o


def rbox(color, loc, size, r=0.08, rot_z=0.0, rot_x=0.0, rot_y=0.0):
    """Rounded box (bevelled)."""
    b = box(color, size=size, bevel=r)
    m = Matrix.Translation(loc) @ Matrix.Rotation(math.radians(rot_z), 4, "Z") @ Matrix.Rotation(math.radians(rot_y), 4, "Y") @ Matrix.Rotation(math.radians(rot_x), 4, "X")
    b.data.transform(m)
    b.data.update()
    return b


def post(color, a, b, r=0.15, seg=8):
    return blob_tube(color, [a, b], lambda u: r, seg=seg)


def flower(loc, col, size=0.35, petals=6):
    x, y, z = loc
    p = []
    for i in range(petals):
        t = math.tau * i / petals
        p.append(sphere(col, loc=(x + math.cos(t) * size * 0.6, y + math.sin(t) * size * 0.6, z), scale=(size * 0.5, size * 0.32, size * 0.18),
                        rot=(0, 0, math.degrees(t)), seg=6, rings=4))
    p.append(sphere(YELLOW if col != YELLOW else "FF8A3C", loc=(x, y, z + 0.05), scale=size * 0.32, seg=8, rings=5))
    return p


def bush_blobs(cx, cy, z, R, cols, seed, n=5):
    rnd = random.Random(seed)
    p = []
    for i in range(n):
        t = math.tau * i / n + rnd.uniform(-0.3, 0.3)
        r = R * 0.55
        s = R * rnd.uniform(0.55, 0.7)
        p.append(sphere(cols[i % len(cols)], loc=(cx + math.cos(t) * r, cy + math.sin(t) * r, z + s * 0.8), scale=(s, s, s * 0.85), seg=10, rings=7))
    s = R * 0.75
    p.append(sphere(cols[0], loc=(cx, cy, z + R * 1.0), scale=(s, s, s * 0.9), seg=10, rings=7))
    return p


# ------------------------------------------------------------------ pond

POND_RX, POND_RY = 10.4, 7.0
POND_Z = 0.3


def pond_r(t):
    return 1 + 0.06 * math.sin(3 * t) + 0.04 * math.cos(5 * t + 1)


def park_duckpond(name="Park_DuckPond"):
    a = asset(name)
    rnd = random.Random(11)
    p = []
    # ground mud ring and water, slightly wobbly ellipse
    def shp(rx, ry):
        return lambda t, r, z: (r * pond_r(t) * math.hypot(rx * math.cos(t), ry * math.sin(t)) / max(rx, ry), z)
    mud = lathe("B89A6A", [(0.0, 0.0), (POND_RX + 1.6, 0.0), (POND_RX + 1.6, 0.12), (0.0, 0.12)], n=48, shape=lambda t, r, z: (r * pond_r(t) * math.hypot((POND_RX + 1.6) * math.cos(t), (POND_RY + 1.6) * math.sin(t)) / (POND_RX + 1.6), z), smooth=False)
    p.append(mud)
    stones = []
    for k in range(26):
        t = math.tau * k / 26 + rnd.uniform(-0.05, 0.05)
        rr = pond_r(t)
        x, y = math.cos(t) * (POND_RX + 0.5) * rr, math.sin(t) * (POND_RY + 0.5) * rr
        if 7.0 < x < 8.6 and abs(y) > 5.5:
            continue  # bridge feet
        s = rnd.uniform(0.85, 1.25)
        st = ico((STONE, STONE_LIGHT, STONE_DARK, "D9CFBF")[k % 4], loc=(x, y, 0.35 * s), scale=(1.15 * s, 0.95 * s, 0.6 * s), sub=2, smooth=True)
        noise_deform(st, 0.12, seed=k)
        stones.append(st)
    p += outlined(stones, 0.05)
    a.part("Body", p, collide=True)

    water = lathe(WATER, [(0.0, -0.2), (POND_RX, -0.2), (POND_RX, POND_Z), (0.0, POND_Z)], n=48,
                  shape=lambda t, r, z: (r * pond_r(t) * math.hypot(POND_RX * math.cos(t), POND_RY * math.sin(t)) / POND_RX, z))
    deep = lathe(WATER_DEEP, [(0.0, POND_Z), (POND_RX * 0.55, POND_Z), (POND_RX * 0.55, POND_Z + 0.01), (0.0, POND_Z + 0.01)], n=40,
                 shape=lambda t, r, z: (r * pond_r(t + 0.4) * math.hypot(POND_RX * math.cos(t), POND_RY * math.sin(t)) / POND_RX, z))
    shines = []
    for (r, deg, span) in ((0.7, 200, 40), (0.82, 20, 30), (0.6, 300, 35)):
        s = lathe(WATER_LIGHT, [(POND_RX * r - 0.15, POND_Z + 0.02), (POND_RX * r + 0.15, POND_Z + 0.02), (POND_RX * r + 0.15, POND_Z + 0.03), (POND_RX * r - 0.15, POND_Z + 0.03)],
                  n=8, t0=math.radians(deg), t1=math.radians(deg + span), smooth=False,
                  shape=lambda t, rr, z: (rr * math.hypot(math.cos(t), (POND_RY / POND_RX) * math.sin(t)), z))
        shines.append(s)
    foam = lathe(FOAM, ellipse(POND_RX - 0.05, POND_Z, 0.18, 0.05, k=6), n=48,
                 shape=lambda t, r, z: (r * pond_r(t) * math.hypot(math.cos(t), (POND_RY / POND_RX) * math.sin(t)), z))
    pads = []
    for (x, y, s, fl) in ((3.8, 3.2, 0.9, True), (-5.2, -2.6, 0.8, False), (0.8, -4.2, 0.7, True), (-2.5, 3.8, 0.6, False), (5.5, -1.0, 0.65, False)):
        notch = rnd.uniform(0, 360)
        pad = lathe(LEAF, [(0.0, 0.0), (s, 0.0), (s, 0.06), (0.0, 0.06)], n=14, t0=math.radians(notch + 25), t1=math.radians(notch + 335), smooth=False)
        place(pad, loc=(x, y, POND_Z + 0.01))
        pads.append(pad)
        if fl:
            for o in flower((0, 0, 0.2), PINK, 0.45):
                place(o, loc=(x, y, POND_Z))
                pads.append(o)
    a.part("Water", [water, deep, foam] + shines + pads)

    # reed clumps with cattails, each sways from its own root
    for idx, (cx, cy) in enumerate(((-9.6, 3.6), (-8.6, -4.6), (9.4, 2.6))):
        reeds = []
        for k in range(7):
            t = k / 7 * math.tau
            bx, by = cx + math.cos(t) * 0.5, cy + math.sin(t) * 0.4
            h = rnd.uniform(1.8, 2.8)
            lean = Vector((math.cos(t), math.sin(t), 0)) * 0.3
            reeds.append(blob_tube(LEAF_DARK if k % 2 else LEAF, [(bx, by, 0.1), (bx + lean.x * 0.5, by + lean.y * 0.5, h * 0.5), (bx + lean.x, by + lean.y, h)],
                                   lambda u: 0.07 * (1 - u * 0.6), seg=5))
            if k % 2 == 0:
                reeds.append(lib.capsule("8A4E2A", (bx + lean.x, by + lean.y, h - 0.1), (bx + lean.x * 1.1, by + lean.y * 1.1, h + 0.45), 0.13, seg=8))
        nm = f"Reeds{idx + 1}"
        a.part(nm, reeds, joint=(cx, cy, 0.0))
        animate(a, nm, "sway", 5, 0.45 + idx * 0.07, "z")

    # arched bridge over the right end
    bx = 7.8
    path = [(bx, (k / 10 - 0.5) * 7.6, 0.5 + 1.0 * math.sin(k / 10 * math.pi)) for k in range(11)]
    deck = sweep(WOOD_LIGHT, path, [(-1.3, -0.12), (1.3, -0.12), (1.3, 0.12), (-1.3, 0.12)])
    planks = []
    for k in range(1, 10):
        u = k / 10
        y = (u - 0.5) * 7.6
        z = 0.5 + 1.0 * math.sin(u * math.pi) + 0.14
        slope = math.degrees(math.atan(1.0 * math.pi / 7.6 * math.cos(u * math.pi)))
        planks.append(rbox(WOOD if k % 2 else WOOD_DARK, (bx, y, z), (2.5, 0.55, 0.08), r=0.03, rot_x=slope))
    rails = []
    for side in (-1.15, 1.15):
        rp = [(bx + side, (k / 10 - 0.5) * 7.6, 1.5 + 1.0 * math.sin(k / 10 * math.pi)) for k in range(11)]
        rails.append(blob_tube(WOOD_DARK, rp, lambda u: 0.11, seg=6))
        for k in range(0, 11, 2):
            u = k / 10
            y = (u - 0.5) * 7.6
            z = 0.5 + 1.0 * math.sin(u * math.pi)
            rails.append(post(WOOD, (bx + side, y, z), (bx + side, y, z + 1.0), r=0.11, seg=6))
            rails.append(sphere(WOOD_LIGHT, loc=(bx + side, y, z + 1.08), scale=0.16, seg=8, rings=5))
    a.part("Bridge", outlined([deck], 0.05) + planks + outlined(rails, 0.035), collide=True)

    # mum and three ducklings paddle round, ripples behind mum; a fish jumps now and then
    for i, nm in enumerate(("PondFx_Duck", "PondFx_Duckling", "PondFx_Duckling", "PondFx_Duckling")):
        loop(a, nm, (-1.2, 0.0, POND_Z), 5.6, 4.0, 0.22, phase=-i * 0.32 - (0.15 if i else 0), bob=0.05, wake=(i == 0))
    a.extra.setdefault("fx", {})["fish"] = [to_roblox(v) for v in ((-4.0, 1.5, POND_Z), (2.0, 2.5, POND_Z), (-1.0, -3.0, POND_Z))]
    return a


def pond_duck(name, scale, body, wing, adult=True):
    a = asset(name)
    s = scale
    p = [sphere(body, loc=(0, 0.1 * s, 0.35 * s), scale=(0.55 * s, 0.75 * s, 0.42 * s), seg=14, rings=9)]
    tail = sphere(body, loc=(0, 0.75 * s, 0.6 * s), scale=(0.2 * s, 0.25 * s, 0.18 * s), rot=(-35, 0, 0), seg=8, rings=5)
    head = sphere(body, loc=(0, -0.5 * s, 0.95 * s), scale=0.36 * s, seg=14, rings=9)
    wings = [sphere(wing, loc=(sx * 0.5 * s, 0.15 * s, 0.45 * s), scale=(0.1 * s, 0.45 * s, 0.25 * s), rot=(-10, 0, 0), seg=8, rings=5) for sx in (-1, 1)]
    beak = sphere("FF9A3C", loc=(0, -0.86 * s, 0.88 * s), scale=(0.17 * s, 0.2 * s, 0.07 * s), seg=8, rings=5)
    eyes = [eye((sx * 0.17 * s, -0.75 * s, 1.03 * s), 0.09 * s, look=(sx * 0.3, -1, 0.1)) for sx in (-1, 1)]
    cheeks = [sphere(PINK, loc=(sx * 0.27 * s, -0.7 * s, 0.86 * s), scale=(0.06 * s, 0.03 * s, 0.04 * s), seg=6, rings=4) for sx in (-1, 1)]
    extra = []
    if adult:
        extra.append(sphere(IRON_LIGHT, loc=(0, -0.5 * s, 1.12 * s), scale=(0.33 * s, 0.33 * s, 0.22 * s), seg=10, rings=6))
    pieces = outlined(p + [head, tail], 0.035 * s) + wings + [beak] + eyes + cheeks + extra
    a.part("Body", pieces)
    return a


def pond_fish():
    a = asset("PondFx_Fish")
    body = sphere("FF8A3C", loc=(0, 0, 0), scale=(0.22, 0.5, 0.28), seg=12, rings=8)
    tail = sphere("FFB45A", loc=(0, 0.55, 0.05), scale=(0.05, 0.22, 0.24), seg=8, rings=5)
    spots = [sphere(WHITE, loc=(0.12, 0.05, 0.1), scale=(0.1, 0.15, 0.1), seg=6, rings=4)]
    eyes = [eye((sx * 0.16, -0.3, 0.08), 0.06, look=(sx, -0.5, 0.1)) for sx in (-1, 1)]
    a.part("Body", outlined([body, tail], 0.025) + spots + eyes)
    return a


def leaf_fx():
    """One flat cartoon leaf, untextured so the client tints it (orange/yellow/green)."""
    a = Asset("ParkFx_Leaf", "prop")
    use(a)
    a.plain = True
    bm = bmesh.new()
    k = 8
    top, bot = [], []
    for i in range(k + 1):
        u = i / k
        w = math.sin(u * math.pi) * 0.28 * (1 - 0.3 * u)
        y = (u - 0.5) * 0.8
        z = 0.06 * math.sin(u * math.pi)
        top.append(bm.verts.new((-w, y, z)))
        bot.append(bm.verts.new((w, y, z)))
    mid = [bm.verts.new((0, (i / k - 0.5) * 0.8, 0.09 * math.sin(i / k * math.pi))) for i in range(k + 1)]
    for i in range(k):
        for (A, B) in ((top, mid), (mid, bot)):
            try:
                bm.faces.new((A[i], A[i + 1], B[i + 1], B[i]))
            except ValueError:
                pass
    # second side so it shows from both sides
    faces = list(bm.faces)
    for f in faces:
        try:
            bm.faces.new(list(reversed(f.verts)))
        except ValueError:
            pass
    o = F._obj_from_bm(bm, "leaf")
    lib._asset.paint(o, WHITE)
    stem = blob_tube(WHITE, [(0, 0.38, 0.0), (0, 0.55, 0.05)], lambda u: 0.025, seg=4)
    a.part("Body", [o, stem])
    return a


def puff_fx():
    """Soft cartoon puff (three blobs), untextured so the client tints it smoke or steam."""
    a = Asset("ParkFx_Puff", "prop")
    use(a)
    a.plain = True
    a.part("Body", [sphere(WHITE, loc=(0, 0, 0), scale=0.5, seg=10, rings=6),
                    sphere(WHITE, loc=(0.35, 0.1, 0.12), scale=0.36, seg=8, rings=5),
                    sphere(WHITE, loc=(-0.3, -0.1, 0.18), scale=0.32, seg=8, rings=5)])
    return a


# ------------------------------------------------------------------ playground

def park_playground(name="Park_Playground"):
    a = asset(name)
    p = []
    # rubbery mat in two colours
    mat = lathe("6FC3A0", [(0.0, 0.0), (1.0, 0.0), (1.0, 0.12), (0.0, 0.12)], n=40,
                shape=lambda t, r, z: (r * 1.0 / ((abs(math.cos(t)) / 11.0) ** 4 + (abs(math.sin(t)) / 7.5) ** 4) ** 0.25, z), smooth=False)
    edge = lathe("4FA383", ellipse(1.0, 0.1, 0.012, 0.12, k=6), n=40,
                 shape=lambda t, r, z: (r * 1.0 / ((abs(math.cos(t)) / 11.0) ** 4 + (abs(math.sin(t)) / 7.5) ** 4) ** 0.25, z))
    p += [mat, edge]
    tx = -5.5
    posts = []
    for dx in (-1.7, 1.7):
        for dy in (-1.7, 1.7):
            posts.append(lathe(BLUE, [(0.0, 0.0), (0.3, 0.0), (0.3, 0.2), (0.22, 0.3), (0.22, 6.6), (0.28, 6.7), (0.0, 6.8)], n=10))
            place(posts[-1], loc=(tx + dx, dy, 0))
    deck = rbox(YELLOW, (tx, 0, 3.0), (3.9, 3.9, 0.35), r=0.1)
    panels = []
    for dy in (-1.7, 1.7):
        panels.append(rbox(RED, (tx, dy, 3.8), (3.2, 0.18, 1.2), r=0.08))
        panels.append(lathe(YELLOW, [(0.0, -0.11), (0.38, -0.11), (0.38, 0.11), (0.0, 0.11)], n=14, smooth=False))
        place(panels[-1], loc=(tx, dy * 1.01, 3.8), rot_x=90)
    roof = lathe(RED, [(0.0, 6.6), (2.9, 6.6), (2.95, 6.75), (0.25, 8.6), (0.0, 8.65)], n=4, smooth=False)
    place(roof, rot_z=45)
    paint_faces(roof, lambda c: WHITE if (math.degrees(math.atan2(c.y - 0, c.x - tx)) % 90) < 45 else RED)
    roof.data.transform(Matrix.Translation((tx, 0, 0)))
    flag = [post(WHITE, (tx, 0, 8.5), (tx, 0, 9.8), r=0.06, seg=6)]
    a.part("Body", p + outlined(posts + [deck, roof], 0.05) + panels + flag, collide=True)

    # pinwheel on the roof tip spins
    pin = []
    for i in range(4):
        t = math.tau * i / 4
        blade = sphere((RED, YELLOW, BLUE, "6FC3A0")[i], loc=(math.cos(t) * 0.35, 0, math.sin(t) * 0.35 + 9.8), scale=(0.32, 0.04, 0.16),
                       rot=(0, -math.degrees(t), 0), seg=8, rings=5)
        pin.append(blade)
    pin.append(sphere(WHITE, loc=(0, -0.05, 9.8), scale=0.1, seg=6, rings=4))
    for o in pin:
        o.data.transform(Matrix.Translation((tx, -0.1, 0)))
    a.part("Pinwheel", pin, joint=(tx, -0.1, 9.8))
    animate(a, "Pinwheel", "spin", 0, 0.6, "z")

    # slide down the front, curvy
    sp = []
    for k in range(13):
        u = k / 12
        sp.append((tx + 0.6 * math.sin(u * math.pi), -2.0 - u * 6.0, 3.15 - 2.9 * (u - 0.08 * math.sin(u * math.tau))))
    slide = sweep(YELLOW, sp, [(-0.85, 0.5), (-0.85, 0.0), (-0.7, -0.15), (0.7, -0.15), (0.85, 0.0), (0.85, 0.5), (0.7, 0.5), (0.7, 0.05), (-0.7, 0.05), (-0.7, 0.5)])
    ladder = []
    for z in range(1, 6):
        ladder.append(post(WOOD_LIGHT, (tx - 0.6, 2.25, z * 0.55), (tx + 0.6, 2.25, z * 0.55), r=0.08, seg=6))
    for sx in (-0.65, 0.65):
        ladder.append(post(BLUE, (tx + sx, 2.6, 0), (tx + sx, 1.8, 3.2), r=0.1, seg=6))
    a.part("Slide", outlined([slide], 0.04) + ladder, collide=True)

    # swing set
    sx0 = 5.0
    frame = []
    for dx in (-4.4, 4.4):
        frame.append(post(RED, (sx0 + dx, -1.5, 0), (sx0 + dx, 0, 5.2), r=0.17, seg=8))
        frame.append(post(RED, (sx0 + dx, 1.5, 0), (sx0 + dx, 0, 5.2), r=0.17, seg=8))
        frame.append(sphere(YELLOW, loc=(sx0 + dx, 0, 5.25), scale=0.3, seg=8, rings=5))
    frame.append(post(RED, (sx0 - 4.5, 0, 5.2), (sx0 + 4.5, 0, 5.2), r=0.2, seg=8))
    a.part("Swings", outlined(frame, 0.04), collide=True)
    for k, dx in enumerate((-2.0, 2.0)):
        sw = []
        for cx in (-0.55, 0.55):
            sw.append(blob_tube("8890A0", [(sx0 + dx + cx, 0, 5.05), (sx0 + dx + cx, 0, 1.4)], lambda u: 0.04, seg=4))
        seat = rbox(BLUE if k else YELLOW, (sx0 + dx, 0, 1.3), (1.4, 0.6, 0.14), r=0.06)
        sw += outlined([seat], 0.03)
        nm = f"Swing{k + 1}"
        a.part(nm, sw, joint=(sx0 + dx, 0, 5.1))
        animate(a, nm, "swing", 22 + k * 6, 0.42 + k * 0.05, "x")

    # spring rider duck
    rx, ry = 4.6, -5.0
    a.part("SpringBase", [cyl("8890A0", loc=(rx, ry, 0.15), r=0.5, h=0.3, verts=10)])
    rider = []
    spring = []
    for i in range(14):
        t = i / 13
        spring.append((rx + math.cos(t * 5 * math.tau) * 0.22, ry + math.sin(t * 5 * math.tau) * 0.22, 0.3 + t * 0.8))
    rider.append(blob_tube("E0E4EA", spring, lambda u: 0.05, seg=5))
    body = sphere(YELLOW, loc=(rx, ry, 1.6), scale=(0.5, 0.85, 0.45), seg=12, rings=8)
    head = sphere(YELLOW, loc=(rx, ry - 0.7, 2.35), scale=0.38, seg=12, rings=8)
    beak = sphere("FF9A3C", loc=(rx, ry - 1.05, 2.3), scale=(0.18, 0.22, 0.08), seg=8, rings=5)
    eyes = [eye((rx + sx * 0.17, ry - 0.98, 2.45), 0.09, look=(sx * 0.3, -1, 0.1)) for sx in (-1, 1)]
    handles = [post(RED, (rx - 0.4, ry - 0.75, 2.1), (rx + 0.4, ry - 0.75, 2.1), r=0.06, seg=6)]
    rider += outlined([body, head], 0.04) + [beak] + eyes + handles
    a.part("Rider", rider, joint=(rx, ry, 0.3))
    animate(a, "Rider", "sway", 9, 0.7, "x")

    # sandbox
    sb = []
    sbx, sby = 5.2, 4.6
    for (dx, dy, w, d) in ((0, -1.6, 5.2, 0.4), (0, 1.6, 5.2, 0.4), (-2.4, 0, 0.4, 3.6), (2.4, 0, 0.4, 3.6)):
        sb.append(rbox(WOOD if dx == 0 else WOOD_LIGHT, (sbx + dx, sby + dy, 0.35), (w, d, 0.7), r=0.08))
    sand = rbox(SAND, (sbx, sby, 0.45), (4.5, 2.9, 0.3), r=0.1)
    castle = [cyl("E6C680", loc=(sbx - 1.0, sby, 0.85), r=0.45, r2=0.35, h=0.6, verts=8),
              cyl("E6C680", loc=(sbx - 1.0, sby, 1.3), r=0.3, r2=0.22, h=0.35, verts=8)]
    bucket = [cyl(RED, loc=(sbx + 1.0, sby + 0.4, 0.85), r=0.32, r2=0.4, h=0.6, verts=10),
              torus("8890A0", loc=(sbx + 1.0, sby + 0.4, 1.1), R=0.3, r=0.03, rot=(90, 0, 0), seg=10, mseg=4)]
    spade = [post(BLUE, (sbx + 0.2, sby - 0.6, 0.7), (sbx + 0.9, sby - 0.9, 1.3), r=0.05, seg=5),
             sphere(BLUE, loc=(sbx + 0.1, sby - 0.55, 0.66), scale=(0.2, 0.05, 0.14), seg=6, rings=4)]
    a.part("Sandbox", outlined(sb, 0.04) + [sand] + castle + bucket + spade, collide=True)
    return a


# ------------------------------------------------------------------ gazebo

def park_gazebo(name="Park_Gazebo"):
    a = asset(name)
    R = 6.0
    base = lathe(STONE, [(0.0, 0.0), (R + 0.7, 0.0), (R + 0.7, 0.55), (R + 0.55, 0.7), (0.0, 0.7)], n=8, smooth=False)
    place(base, rot_z=22.5)
    floor = lathe(WOOD_LIGHT, [(0.0, 0.7), (R + 0.3, 0.7), (R + 0.3, 0.82), (0.0, 0.82)], n=8, smooth=False)
    place(floor, rot_z=22.5)
    paint_faces(floor, lambda c: WOOD if int((c.x + 20) / 0.9) % 2 else WOOD_LIGHT)
    steps = [rbox(STONE_LIGHT, (0, -R - 0.9 + i * 0.45, 0.15 + i * 0.22), (3.2, 0.7, 0.3 + i * 0.44), r=0.06) for i in range(2)]
    posts, rails, balus = [], [], []
    for k in range(8):
        ang = math.radians(k * 45 + 22.5)
        x, y = math.cos(ang) * R, math.sin(ang) * R
        posts.append(lathe(WHITE, [(0.0, 0.8), (0.42, 0.8), (0.42, 1.1), (0.28, 1.25), (0.28, 5.7), (0.4, 5.85), (0.4, 6.1), (0.0, 6.1)], n=10))
        place(posts[-1], loc=(x, y, 0))
        nxt = math.radians((k + 1) * 45 + 22.5)
        x2, y2 = math.cos(nxt) * R, math.sin(nxt) * R
        if not (y < -1 and y2 < -1):
            rails.append(post(WHITE, (x, y, 2.3), (x2, y2, 2.3), r=0.12, seg=6))
            for j in range(1, 5):
                u = j / 5
                bx, by = x + (x2 - x) * u, y + (y2 - y) * u
                balus.append(lathe(WHITE, [(0.0, 0.8), (0.12, 0.8), (0.17, 1.4), (0.09, 2.0), (0.12, 2.25), (0.0, 2.25)], n=6))
                place(balus[-1], loc=(bx, by, 0))
    benches = []
    for k in range(3):
        ang = math.radians(90 + (k - 1) * 60)
        benches.append(rbox(WOOD, (math.cos(ang) * (R - 1.1), math.sin(ang) * (R - 1.1), 1.45), (3.0, 0.9, 0.18), r=0.05, rot_z=math.degrees(ang) + 90))
    a.part("Body", outlined([base, floor], 0.05) + steps + outlined(posts, 0.04) + rails + balus + benches, collide=True)

    # scalloped, striped roof with a trim of hanging flags
    roof = lathe(RED, [(0.0, 6.0), (R + 1.4, 6.0), (R + 1.45, 6.25), (R + 1.0, 6.65), (2.0, 8.6), (0.5, 9.4), (0.0, 9.5)], n=16, smooth=False,
                 shape=lambda t, r, z: (r * (1 + 0.03 * math.cos(t * 8)), z))
    place(roof, rot_z=22.5)
    paint_faces(roof, lambda c: WHITE if int((math.degrees(math.atan2(c.y, c.x)) + 360 + 22.5) / 22.5) % 2 else RED)
    trim = lathe(YELLOW, ellipse(R + 1.35, 6.05, 0.16, 0.14, k=6), n=16)
    place(trim, rot_z=22.5)
    bunting = []
    for k in range(32):
        t = math.tau * (k + 0.5) / 32
        r = R + 1.32
        tri = lathe((RED, YELLOW, BLUE, "6FC3A0")[k % 4], [(0.0, -0.45), (0.28, 0.0), (0.0, 0.0)], n=3, smooth=False)
        tri.data.transform(Matrix.Diagonal((1, 0.25, 1, 1)))
        place(tri, rot_z=math.degrees(t) + 90, loc=(math.cos(t) * r, math.sin(t) * r, 5.95))
        bunting.append(tri)
    ball = sphere(YELLOW, loc=(0, 0, 9.65), scale=0.35, seg=10, rings=6)
    a.part("Roof", outlined([roof], 0.06) + [trim, ball] + bunting, collide=True)

    bulbs = []
    for k in range(24):
        t = math.tau * k / 24
        bulbs.append(sphere("FFF1A8", loc=(math.cos(t) * (R + 1.0), math.sin(t) * (R + 1.0), 5.55 + 0.12 * math.cos(t * 8)), scale=0.13, seg=6, rings=4))
    a.part("Lights_Glow", bulbs, glow="FFE58A")

    # weathervane: arrow with a little bird on top, turns slowly
    vane = [post("3A3F4A", (0, 0, 9.9), (0, 0, 11.4), r=0.05, seg=6),
            post("3A3F4A", (-0.9, 0, 11.0), (0.9, 0, 11.0), r=0.05, seg=6),
            lib.cone(GOLD_V, loc=(1.05, 0, 11.0), r=0.14, h=0.35, rot=(0, 90, 0), verts=6),
            sphere(GOLD_V, loc=(-0.95, 0, 11.0), scale=(0.08, 0.25, 0.2), seg=6, rings=4),
            sphere(GOLD_V, loc=(0, 0, 11.55), scale=(0.25, 0.16, 0.18), seg=8, rings=5),
            sphere(GOLD_V, loc=(0.2, 0, 11.75), scale=0.12, seg=8, rings=5)]
    a.part("Vane", vane, joint=(0, 0, 10.0))
    animate(a, "Vane", "sway", 40, 0.06, "y")
    return a


GOLD_V = "FFB52E"


# ------------------------------------------------------------------ small pieces

def park_bench(name="Park_Bench"):
    a = asset(name)
    planks = []
    for i in range(3):
        planks.append(rbox((WOOD, WOOD_LIGHT, WOOD)[i], (0, -0.45 + i * 0.36, 1.05), (3.4, 0.3, 0.14), r=0.05))
    for i in range(2):
        planks.append(rbox((WOOD_LIGHT, WOOD)[i], (0, 0.42, 1.55 + i * 0.42), (3.4, 0.12, 0.3), r=0.05, rot_x=-12))
    iron = []
    for sx in (-1.45, 1.45):
        iron.append(blob_tube(IRON, [(sx, -0.6, 0), (sx, -0.5, 0.6), (sx, -0.55, 1.0), (sx, 0.0, 1.0), (sx, 0.45, 1.0), (sx, 0.5, 1.6), (sx, 0.55, 2.3)],
                              lambda u: 0.08, seg=6))
        iron.append(blob_tube(IRON, [(sx, 0.4, 0), (sx, 0.35, 0.6), (sx, 0.1, 0.95)], lambda u: 0.07, seg=6))
        iron.append(blob_tube(IRON, [(sx, -0.55, 1.0), (sx, -0.7, 1.35), (sx, -0.55, 1.5), (sx, -0.35, 1.35)], lambda u: 0.06, seg=6))
        iron.append(sphere(IRON_LIGHT, loc=(sx, -0.6, 0.05), scale=(0.16, 0.2, 0.08), seg=8, rings=4))
        iron.append(sphere(IRON_LIGHT, loc=(sx, 0.4, 0.05), scale=(0.16, 0.2, 0.08), seg=8, rings=4))
    a.part("Body", outlined(planks, 0.035) + iron, collide=True)
    return a


def park_lamp(name="Park_Lamp"):
    a = asset(name)
    pole = lathe(IRON, [(0.0, 0.0), (0.55, 0.0), (0.55, 0.2), (0.4, 0.45), (0.25, 0.6), (0.18, 0.9), (0.14, 1.0), (0.14, 5.6),
                        (0.22, 5.75), (0.16, 5.9), (0.0, 5.9)], n=10)
    flute = [lathe(IRON_LIGHT, ellipse(0.17, z, 0.05, 0.06, k=5), n=10) for z in (1.4, 3.5, 5.2)]
    curl = [blob_tube(IRON, [(0, 0, 5.4), (0.45, 0, 5.6), (0.55, 0, 6.0), (0.3, 0, 6.1)], lambda u: 0.05, seg=5),
            blob_tube(IRON, [(0, 0, 5.4), (-0.45, 0, 5.6), (-0.55, 0, 6.0), (-0.3, 0, 6.1)], lambda u: 0.05, seg=5)]
    cage = lathe(IRON, [(0.0, 5.85), (0.42, 5.85), (0.42, 6.0), (0.0, 6.0)], n=6, smooth=False)
    cap = lathe(IRON, [(0.0, 7.25), (0.75, 7.25), (0.7, 7.4), (0.2, 7.85), (0.0, 7.9)], n=6, smooth=False)
    knob = sphere(IRON_LIGHT, loc=(0, 0, 8.0), scale=0.15, seg=8, rings=5)
    bars = [post(IRON, (math.cos(t) * 0.55, math.sin(t) * 0.55, 6.0), (math.cos(t) * 0.68, math.sin(t) * 0.68, 7.25), r=0.04, seg=4)
            for t in (math.tau * k / 6 for k in range(6))]
    a.part("Body", outlined([pole, cap], 0.04) + flute + curl + [cage, knob] + bars, collide=True)
    glass = lathe("FFE9A8", [(0.0, 6.0), (0.5, 6.0), (0.62, 7.2), (0.0, 7.2)], n=6, smooth=False)
    a.part("Lamp_Glow", [glass], glow="FFE9A8")
    return a


def park_flowerbed(name="Park_FlowerBed"):
    a = asset(name)
    rnd = random.Random(7)
    sh = scallop(8, 0.08)
    wall = lathe("D9826A", [(2.7, 0.0), (3.4, 0.0), (3.4, 0.6), (2.7, 0.6)], n=40, shape=sh, smooth=False)
    paint_faces(wall, lambda c: "C46A55" if int((math.atan2(c.y, c.x) + 4) * 6) % 2 else "D9826A")
    lip = lathe(STONE_LIGHT, ellipse(3.05, 0.68, 0.48, 0.14, k=8), n=40, shape=sh)
    soil = lathe("6B4A2E", [(0.0, 0.3), (2.9, 0.3), (2.9, 0.65), (0.0, 0.65)], n=24, shape=sh, smooth=False)
    leaves = []
    for k in range(9):
        t = math.tau * k / 9
        leaves += bush_blobs(math.cos(t) * 2.2, math.sin(t) * 2.2, 0.55, 0.65, (LEAF, LEAF_DARK, LEAF_LIGHT), k, n=3)
    leaves += bush_blobs(0, 0, 0.6, 1.0, (LEAF_DARK, LEAF), 99, n=4)
    a.part("Body", outlined([wall, lip], 0.04) + [soil] + leaves, collide=True)
    fl = []
    for k in range(14):
        t = math.tau * k / 14 + rnd.uniform(-0.1, 0.1)
        r = rnd.uniform(1.0, 2.5)
        x, y = math.cos(t) * r, math.sin(t) * r
        h = rnd.uniform(1.3, 2.0)
        fl.append(blob_tube(LEAF_DARK, [(x, y, 0.6), (x * 1.05, y * 1.05, h)], lambda u: 0.05, seg=4))
        fl += flower((x * 1.05, y * 1.05, h), FLOWERS[k % len(FLOWERS)], rnd.uniform(0.35, 0.5))
    a.part("Flowers", fl, joint=(0, 0, 0.6))
    animate(a, "Flowers", "sway", 3, 0.5, "z")
    return a


def park_picnic(name="Park_Picnic"):
    a = asset(name)
    blanket = rbox("4AA8FF", (0, 0, 0.04), (7.0, 6.0, 0.08), r=0.03)
    paint_faces(blanket, lambda c: "4AA8FF" if (int((c.x + 10) / 1.0) + int((c.y + 10) / 1.0)) % 2 else "8FCBFF")
    top = rbox(WOOD, (0, 0, 1.5), (4.2, 2.0, 0.22), r=0.07)
    cloth = rbox(RED, (0, 0, 1.64), (3.9, 1.8, 0.05), r=0.02)
    paint_faces(cloth, lambda c: RED if (int((c.x + 10) / 0.5) + int((c.y + 10) / 0.5)) % 2 else WHITE)
    legs = []
    for dx in (-1.6, 1.6):
        legs.append(post(WOOD_DARK, (dx, -0.95, 0), (dx, 0.95, 1.45), r=0.11, seg=6))
        legs.append(post(WOOD_DARK, (dx, 0.95, 0), (dx, -0.95, 1.45), r=0.11, seg=6))
    seats = [rbox(WOOD_LIGHT, (0, dy, 0.85), (4.2, 0.65, 0.16), r=0.06) for dy in (-1.7, 1.7)]
    basket = [rbox("D8A060", (-0.9, 0.15, 1.98), (1.0, 0.7, 0.62), r=0.1),
              torus("A07040", loc=(-0.9, 0.15, 2.3), R=0.4, r=0.06, rot=(90, 0, 0), seg=12, mseg=5)]
    melon = lathe("4FB548", [(0.0, 0.0), (0.45, 0.0), (0.45, 0.06), (0.0, 0.06)], n=6, t0=0, t1=math.pi, smooth=False)
    flesh = lathe("FF5A6A", [(0.0, 0.06), (0.38, 0.06), (0.38, 0.12), (0.0, 0.12)], n=6, t0=0, t1=math.pi, smooth=False)
    for o in (melon, flesh):
        place(o, loc=(0.6, 0.2, 1.67))
    seeds = [sphere("1B1530", loc=(0.6 + math.cos(t) * 0.22, 0.2 + math.sin(t) * 0.22, 1.8), scale=0.03, seg=4, rings=3) for t in (0.6, 1.4, 2.3)]
    juice = [cyl("FF9A3C", loc=(1.3, -0.4, 1.9), r=0.16, h=0.5, verts=8), cyl(WHITE, loc=(1.3, -0.4, 2.2), r=0.17, h=0.08, verts=8),
             post(PINK, (1.3, -0.4, 2.2), (1.4, -0.35, 2.55), r=0.03, seg=4)]
    pole = post(WHITE, (0, 0, 1.6), (0, 0, 4.4), r=0.08, seg=6)
    a.part("Body", outlined([top, basket[0]] + seats, 0.035) + [blanket, cloth] + legs + basket[1:] + [melon, flesh, pole] + seeds + juice, collide=True)
    umb = lathe(RED, [(0.0, 4.35), (2.6, 3.75), (2.6, 3.65), (0.0, 4.25)], n=16, smooth=False, shape=lambda t, r, z: (r * (1 + 0.04 * math.cos(t * 8)), z))
    paint_faces(umb, lambda c: WHITE if int((math.atan2(c.y, c.x) + 4) * 8 / math.pi) % 2 else "FFD23A")
    knob = sphere(RED, loc=(0, 0, 4.5), scale=0.15, seg=8, rings=5)
    a.part("Umbrella", outlined([umb], 0.04) + [knob], joint=(0, 0, 1.6))
    animate(a, "Umbrella", "sway", 1.5, 0.35, "x")
    return a


def tree(name, kind):
    a = asset(name)
    rnd = random.Random(len(name))
    trunk_h = {"round": 3.6, "autumn": 3.4, "tall": 2.2}[kind]
    trunk = lathe(TRUNK, [(0.0, 0.0), (0.95, 0.0), (0.6, 0.35), (0.48, 0.9), (0.42, trunk_h), (0.3, trunk_h + 0.6), (0.0, trunk_h + 0.6)], n=10)
    roots = [blob_tube(TRUNK, [(0, 0, 0.5), (math.cos(t) * 0.8, math.sin(t) * 0.8, 0.12), (math.cos(t) * 1.1, math.sin(t) * 1.1, 0.0)],
                       lambda u: 0.18 * (1 - 0.6 * u), seg=6) for t in (0.4, 2.3, 4.2)]
    knot = sphere(TRUNK_DARK, loc=(0.0, -0.44, 1.8), scale=(0.15, 0.06, 0.2), seg=6, rings=4)
    a.part("Body", outlined([trunk] + roots, 0.04) + [knot], collide=True)
    c = []
    if kind in ("round", "autumn"):
        cols = (LEAF, LEAF_DARK, LEAF_LIGHT) if kind == "round" else (AUTUMN, AUTUMN_DARK, AUTUMN_LIGHT)
        blobs = [((0, 0, trunk_h + 2.2), 2.3), ((1.6, 0.4, trunk_h + 1.3), 1.5), ((-1.5, 0.6, trunk_h + 1.4), 1.55), ((0.3, -1.4, trunk_h + 1.2), 1.4),
                 ((-0.4, 1.5, trunk_h + 1.6), 1.45), ((0.8, 0.6, trunk_h + 3.4), 1.35), ((-0.8, -0.5, trunk_h + 3.2), 1.3)]
        main = []
        for i, (loc, r) in enumerate(blobs):
            main.append(sphere(cols[i % 2], loc=loc, scale=(r, r, r * 0.9), seg=12, rings=8))
        hl = [sphere(cols[2], loc=(loc[0] - 0.25 * r, loc[1] - 0.35 * r, loc[2] + 0.4 * r), scale=(r * 0.45, r * 0.35, r * 0.3), seg=8, rings=5)
              for (loc, r) in blobs[:5]]
        extra = []
        if kind == "round":
            for i in range(9):
                t = rnd.uniform(0, math.tau)
                z = trunk_h + rnd.uniform(1.0, 3.6)
                extra.append(sphere(RED, loc=(math.cos(t) * 2.2, math.sin(t) * 2.2, z), scale=0.2, seg=6, rings=4))
        c = outlined(main, 0.06) + hl + extra
        top = trunk_h + 4.6
        canopy = {"center": to_roblox((0, 0, trunk_h + 2.0)), "radius": 2.6}
    else:
        tiers = [(trunk_h + 0.2, 2.6, 2.4), (trunk_h + 1.9, 2.1, 2.2), (trunk_h + 3.4, 1.55, 2.0), (trunk_h + 4.8, 1.0, 1.7)]
        for i, (z, r, h) in enumerate(tiers):
            prof = [(0.0, z), (r, z), (r * 1.02, z + 0.15)] + [(r * (1 - u) ** 1.2, z + 0.15 + h * u) for u in (0.3, 0.6, 0.85)] + [(0.0, z + h)]
            tier = lathe(LEAF_DARK if i % 2 else "3E8E4A", prof, n=12, shape=lambda t, rr, zz, i=i: (rr * (1 + 0.08 * math.cos(t * 7 + i)), zz))
            c.append(tier)
        c = outlined(c, 0.05)
        c.append(sphere(YELLOW, loc=(0, 0, trunk_h + 6.6), scale=0.25, seg=8, rings=5))
        top = trunk_h + 6.6
        canopy = {"center": to_roblox((0, 0, trunk_h + 2.0)), "radius": 2.0}
    a.part("Canopy", c, joint=(0, 0, trunk_h * 0.4))
    animate(a, "Canopy", "sway", 1.4, 0.3 + 0.05 * len(name) % 3 * 0.05, "z")
    a.extra["fx"] = {"canopy": canopy["center"], "radius": canopy["radius"], "leaves": kind}
    return a


def park_bush(name="Park_Bush"):
    a = asset(name)
    blobs = bush_blobs(0, 0, 0.0, 1.3, (LEAF, LEAF_DARK), 3, n=5)
    rnd = random.Random(2)
    fl = []
    for i in range(7):
        t = rnd.uniform(0, math.tau)
        z = rnd.uniform(0.7, 1.9)
        r = 1.35 - abs(z - 1.2) * 0.4
        fl += flower((math.cos(t) * r, math.sin(t) * r, z), FLOWERS[i % len(FLOWERS)], 0.3)
    a.part("Body", outlined(blobs, 0.04) + fl, collide=True)
    return a


def park_rock(name, seed, scale):
    a = asset(name)
    h = scale[2]
    rk = ico(STONE, loc=(0, 0, 0.55 * h), scale=scale, sub=2, smooth=True)
    noise_deform(rk, 0.18, seed=seed)
    paint_faces(rk, lambda c: "7E8494" if c.z < 0.3 * h else ("9EA4B2" if c.z < 0.75 * h else "BCC1CC"))
    moss = ico(LEAF, loc=(0.1, 0.1, h * 1.25), scale=(scale[0] * 0.7, scale[1] * 0.65, h * 0.35), sub=2, smooth=True)
    noise_deform(moss, 0.08, seed=seed + 3)
    paint_faces(moss, lambda c: LEAF_LIGHT if c.z > h * 1.45 else LEAF)
    pebbles = [ico("9EA4B2", loc=(scale[0] * 1.1, -scale[1] * 0.4, 0.15), scale=0.3, sub=1, smooth=True),
               ico("7E8494", loc=(-scale[0] * 0.9, scale[1] * 0.7, 0.12), scale=0.22, sub=1, smooth=True)]
    a.part("Body", outlined([rk, moss], 0.05) + pebbles, collide=True)
    return a


ALL = {
    "Park_DuckPond": park_duckpond,
    "Park_Playground": park_playground,
    "Park_Gazebo": park_gazebo,
    "Park_Picnic": park_picnic,
    "Park_Bench": park_bench,
    "Park_Lamp": park_lamp,
    "Park_FlowerBed": park_flowerbed,
    "Park_TreeRound": lambda: tree("Park_TreeRound", "round"),
    "Park_TreeAutumn": lambda: tree("Park_TreeAutumn", "autumn"),
    "Park_TreeTall": lambda: tree("Park_TreeTall", "tall"),
    "Park_Bush": park_bush,
    "Park_Rock1": lambda: park_rock("Park_Rock1", 1, (1.6, 1.3, 1.0)),
    "Park_Rock2": lambda: park_rock("Park_Rock2", 2, (1.1, 1.0, 0.8)),
    "PondFx_Duck": lambda: pond_duck("PondFx_Duck", 1.0, WHITE, "E6ECF2", adult=True),
    "PondFx_Duckling": lambda: pond_duck("PondFx_Duckling", 0.55, YELLOW, "FFC22A", adult=False),
    "PondFx_Fish": pond_fish,
    "ParkFx_Leaf": leaf_fx,
    "ParkFx_Puff": puff_fx,
}
