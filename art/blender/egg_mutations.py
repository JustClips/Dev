"""3D add-ons for eggs upgraded by the weather (one per mutation), in the eggs' brick style.

The game puts EggMut_<Mutation> on a growing egg next to its repainted skin
(tools/egg_skins.py, AssetLibrary.applyMutation). Same frame as the eggs (art/blender/eggs.py):
built for an egg 2.6 tall and 1.05 wide with its pivot at the bottom centre, then scaled by
eggs.SCALE on export, so the add-on lines up with any egg at scale 1.

  Frozen      snow cap with icicles, ice crystals at the foot          (part Ice = ice)
  Wet         puddle at the foot, drips running down the shell         (part Water = glass)
  Shocked     three lightning bolts sticking out of the shell          (glow)
  Windswept   a tilted ring of autumn leaves blowing around it
  Bloodlit    a red crescent moon hanging over it (red mist comes from particles)  (glow)
  Starlit     little stars and a moon floating around it               (glow)
  Starstruck  a big gold star stuck in the top, with sparks             (glow sparks)
  Golden      stacks and piles of gold coins at the foot               (part Gold = shiny)
  Rainbow     a brick rainbow arching over it
  Disco       a mirror disco ball hanging over it

Run headless from the repo root with a pip bpy:
    python art/blender/egg_mutations.py [Names...]
-> art/out/EggMut_<Mutation>.glb, meta in art/out/meta.json (kind "eggmut"), and a
preview render art/vfx/meshes/egg_mutations.png.
"""
import json
import math
import os
import random
import sys

import bpy  # noqa: F401  (bpy first: makes mathutils importable)
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import lib  # noqa: E402
import eggs  # noqa: E402
from eggs import BrickEgg, Vox, H, R, BRICK, radius_at, use  # noqa: E402

S = BRICK


def asset(name):
    a = BrickEgg(f"EggMut_{name}")
    a.kind = "eggmut"
    use(a)
    return a


def part(a, name, voxes, glow=None):
    objs = [v.mesh(a, name + str(i)) for i, v in enumerate(voxes)]
    objs = [o for o in objs if o]
    if objs:
        a.part(name, objs, glow=glow)


def framed(origin, z_axis, up_hint=(0, 0, 1)):
    """A Vox frame at origin whose local Z is z_axis."""
    z = Vector(z_axis).normalized()
    hint = Vector(up_hint)
    if abs(z.dot(hint.normalized())) > 0.95:
        hint = Vector((1, 0, 0))
    x = hint.cross(z).normalized()
    y = z.cross(x).normalized()
    return Vox(S, origin=origin, X=x, Y=y, Z=z)


def shell_dist(p):
    """How far a point is outside the egg shell (negative = inside), roughly."""
    t = p.z / H
    if t < 0 or t > 1:
        return 1e9
    return math.hypot(p.x, p.y) - radius_at(t)


# ---------------------------------------------------------------- the add-ons

def frozen():
    a = asset("Frozen")
    rnd = random.Random("frozen")
    # snow cap: a layer of bricks over the top of the shell with a wavy lower edge
    cap = Vox(S)

    def capf(lp, wp):
        t = wp.z / H
        edge = 0.74 + 0.04 * math.sin(math.atan2(wp.y, wp.x) * 5)
        d = shell_dist(wp)
        if t > edge and -S * 0.2 < d < S * 1.3:
            return "F4FAFF" if rnd.random() < 0.8 else "DDEEFF"
        if wp.z > H - S * 0.5 and wp.z < H + S * 1.6 and math.hypot(wp.x, wp.y) < 0.35:
            return "F4FAFF"
        return None
    cap.fill((-R - 2 * S, -R - 2 * S, H * 0.7), (R + 2 * S, R + 2 * S, H + 2 * S), capf)
    part(a, "Snow", [cap])
    # icicles hanging from the cap's edge, and ice crystals at the foot
    ice = []
    for k in range(11):
        ang = k / 11 * 2 * math.pi + rnd.uniform(-0.15, 0.15)
        t = 0.74 + 0.04 * math.sin(ang * 5) - 0.01
        r = radius_at(t) + S * 0.6
        top = Vector((math.cos(ang) * r, math.sin(ang) * r, H * t))
        length = rnd.randint(3, 6)
        v = Vox(S, origin=top - Vector((S / 2, S / 2, 0)))
        for i in range(length):
            v.cells[(0, 0, -i - 1)] = "BDE6FF" if i < length - 1 else "E8F7FF"
        ice.append(v)
    for k in range(5):
        ang = k / 5 * 2 * math.pi + rnd.uniform(-0.3, 0.3)
        base = Vector((math.cos(ang) * (R + 0.15), math.sin(ang) * (R + 0.15), 0))
        tilt = Vector((math.cos(ang) * 0.5, math.sin(ang) * 0.5, 1))
        v = framed(base, tilt)
        h = rnd.randint(4, 7)
        for z in range(h):
            w = 1 if z < h - 2 else 0
            for x in range(-w, w + 1):
                for y in range(-w, w + 1):
                    if abs(x) + abs(y) <= w:
                        v.cells[(x, y, z)] = "9ED8FF" if (x + y + z) % 3 else "D8F2FF"
        ice.append(v)
    part(a, "Ice", ice)
    return a


def wet():
    a = asset("Wet")
    rnd = random.Random("wet")
    puddle = Vox(S, origin=(0, 0, -S))

    def pf(lp, wp):
        ang = math.atan2(wp.y, wp.x)
        rr = math.hypot(wp.x, wp.y)
        edge = R * (1.6 + 0.18 * math.sin(ang * 3) + 0.1 * math.sin(ang * 7 + 1))
        if R * 0.6 < rr < edge:
            return "6FB2FF" if rr < edge - S * 1.5 else "A9D4FF"
        return None
    puddle.fill((-R * 2, -R * 2, 0), (R * 2, R * 2, S), pf)
    drips = Vox(S)
    for k in range(9):
        ang = k / 9 * 2 * math.pi + rnd.uniform(-0.2, 0.2)
        t0 = rnd.uniform(0.55, 0.9)
        t1 = t0 - rnd.uniform(0.18, 0.35)
        steps = int((t0 - t1) * H / S)
        for i in range(steps + 1):
            t = t0 - i * S / H
            r = radius_at(t) + S * 0.5
            p = Vector((math.cos(ang) * r, math.sin(ang) * r, t * H))
            c = (math.floor(p.x / S), math.floor(p.y / S), math.floor(p.z / S))
            drips.cells[c] = "7DBBFF"
        # a fat drop at the end
        t = t1
        r = radius_at(t) + S * 0.9
        p = Vector((math.cos(ang) * r, math.sin(ang) * r, t * H))
        c = (math.floor(p.x / S), math.floor(p.y / S), math.floor(p.z / S))
        for d in [(0, 0, 0), (0, 0, -1), (1, 0, -1), (0, 1, -1), (-1, 0, -1), (0, -1, -1), (0, 0, -2)]:
            drips.cells[(c[0] + d[0], c[1] + d[1], c[2] + d[2])] = "A9D4FF"
    part(a, "Water", [puddle, drips])
    return a


def bolt_cells(v, length, rnd):
    """A zigzag lightning bolt along local +Z in the XZ plane, 2 cells thick."""
    x, z = 0, 0
    path = []
    while z < length:
        run = rnd.randint(2, 3)
        for _ in range(run):
            path.append((x, z))
            z += 1
        step = rnd.choice([-3, 3]) if not path or abs(x) < 3 else (-3 if x > 0 else 3)
        sgn = 1 if step > 0 else -1
        for _ in range(abs(step)):
            x += sgn
            path.append((x, z))
    for i, (x, z) in enumerate(path):
        fat = 1 if i < len(path) * 0.6 else 0
        for dx in range(-fat, fat + 1):
            for y in (0, 1):
                v.cells[(x + dx, y, z)] = "FFF06A"


def shocked():
    a = asset("Shocked")
    rnd = random.Random("shock")
    bolts = []
    for k, (ang, t, tilt) in enumerate([(-100, 0.7, 0.55), (20, 0.5, 0.35), (140, 0.82, 0.8)]):
        rad = math.radians(ang)
        r = radius_at(t) - S
        base = Vector((math.cos(rad) * r, math.sin(rad) * r, t * H))
        out = Vector((math.cos(rad), math.sin(rad), tilt))
        v = framed(base, out)
        bolt_cells(v, 9 + k * 2, rnd)
        bolts.append(v)
    part(a, "Bolts", bolts, glow="FFF06A")
    return a


def windswept():
    a = asset("Windswept")
    rnd = random.Random("wind")
    cols = ["E85C1E", "F28A2A", "FFB940", "C8381E", "9AB83A"]
    leaves = []
    tilt = Matrix.Rotation(math.radians(18), 3, "X")
    n = 14
    for k in range(n):
        ang = k / n * 2 * math.pi
        rr = R * 1.55 + 0.12 * math.sin(k * 1.7)
        p = tilt @ Vector((math.cos(ang) * rr, math.sin(ang) * rr, 0))
        p.z += H * 0.48 + 0.15 * math.sin(k * 2.3)
        tangent = tilt @ Vector((-math.sin(ang), math.cos(ang), 0.35))
        v = framed(p, Vector((0, 0, 1)).lerp(tangent, 0.6))
        c = cols[k % len(cols)]
        dark = eggs.shade(c, -0.25)
        for (x, y) in [(0, 0), (1, 0), (-1, 0), (0, 1), (1, 1), (0, -1), (2, 0), (-1, 1)]:
            v.cells[(x, y, 0)] = dark if (x, y) == (0, 0) else c
        leaves.append(v)
    part(a, "Leaves", leaves)
    return a


def crescent(v, r, cut, offset, colour, depth=2):
    n = int(r / S) + 1
    for x in range(-n, n + 1):
        for z in range(-n, n + 1):
            px, pz = (x + 0.5) * S, (z + 0.5) * S
            if math.hypot(px, pz) < r and math.hypot(px - offset[0], pz - offset[1]) > cut:
                for y in range(depth):
                    v.cells[(x, y, z)] = colour


def bloodlit():
    a = asset("Bloodlit")
    moon = Vox(S, origin=(0, -S, H + 0.75))
    crescent(moon, 0.55, 0.47, (0.22, 0.12), "FF3B30")
    part(a, "Moon", [moon], glow="FF3B30")
    return a


def star4(v, r, colour):
    n = int(r / S)
    for x in range(-n, n + 1):
        for z in range(-n, n + 1):
            if abs(x) * abs(z) == 0 or (abs(x) <= 1 and abs(z) <= 1):
                if abs(x) + abs(z) <= n:
                    v.cells[(x, 0, z)] = colour


def starlit():
    a = asset("Starlit")
    rnd = random.Random("starlit")
    stars = []
    for k in range(6):
        ang = k / 6 * 2 * math.pi + 0.3
        rr = R * 1.45 + rnd.uniform(-0.1, 0.15)
        p = Vector((math.cos(ang) * rr, math.sin(ang) * rr, H * rnd.uniform(0.35, 1.0)))
        v = framed(p, Vector((math.cos(ang), math.sin(ang), 0)))
        star4(v, rnd.choice([0.25, 0.33, 0.4]), "E6EEFF")
        stars.append(v)
    moon = Vox(S, origin=(0.35, -S, H + 0.55))
    crescent(moon, 0.32, 0.27, (0.12, 0.08), "E6EEFF")
    stars.append(moon)
    part(a, "Stars", stars, glow="CFDCFF")
    return a


def star5(v, r_out, r_in, colour, depth=2):
    pts = []
    for i in range(10):
        ang = math.pi / 2 + i * math.pi / 5
        rr = r_out if i % 2 == 0 else r_in
        pts.append((math.cos(ang) * rr, math.sin(ang) * rr))

    def inside(x, z):
        c = False
        j = len(pts) - 1
        for i in range(len(pts)):
            xi, zi = pts[i]
            xj, zj = pts[j]
            if (zi > z) != (zj > z) and x < (xj - xi) * (z - zi) / (zj - zi) + xi:
                c = not c
            j = i
        return c
    n = int(r_out / S) + 1
    for x in range(-n, n + 1):
        for z in range(-n, n + 1):
            if inside((x + 0.5) * S, (z + 0.5) * S):
                for y in range(depth):
                    v.cells[(x, y, z)] = colour


def starstruck():
    a = asset("Starstruck")
    # the star lands at a slant, half sunk into the top of the shell
    top = Vector((0.12, 0, H + 0.28))
    tilt = Matrix.Rotation(math.radians(-22), 3, "Y")
    v = Vox(S, origin=top, X=tilt @ Vector((1, 0, 0)), Y=Vector((0, 1, 0)), Z=tilt @ Vector((0, 0, 1)))
    star5(v, 0.7, 0.3, "FFD34D", depth=3)
    v.origin = top - v.Y * S * 1.5
    part(a, "Star", [v])
    rnd = random.Random("struck")
    sparks = []
    for k in range(5):
        ang = k / 5 * 2 * math.pi
        p = Vector((math.cos(ang) * R * 1.35, math.sin(ang) * R * 1.35, H * rnd.uniform(0.6, 1.05)))
        s = framed(p, Vector((math.cos(ang), math.sin(ang), 0)))
        star4(s, 0.22, "FFF2B0")
        sparks.append(s)
    part(a, "Sparks", sparks, glow="FFE68A")
    return a


def coin(v, cx, cy, z, colour, rim):
    for x in range(-2, 3):
        for y in range(-2, 3):
            if x * x + y * y <= 5:
                v.cells[(cx + x, cy + y, z)] = rim if x * x + y * y >= 4 else colour


def golden():
    a = asset("Golden")
    rnd = random.Random("gold")
    v = Vox(S)
    for k in range(7):
        ang = k / 7 * 2 * math.pi + rnd.uniform(-0.2, 0.2)
        rr = R * rnd.uniform(1.25, 1.6)
        cx, cy = round(math.cos(ang) * rr / S), round(math.sin(ang) * rr / S)
        stack = rnd.randint(1, 5) if k % 2 == 0 else 1
        for z in range(stack):
            coin(v, cx + rnd.randint(-1, 1) * (z > 0), cy, z, "FFC93A", "E8A317")
    part(a, "Gold", [v])
    return a


def rainbow():
    a = asset("Rainbow")
    bands = ["FF4D4D", "FF9A3C", "FFE04A", "5BD866", "4CA8FF", "9B6BFF"]
    arc = Vox(S, origin=(0, R * 0.55, 0))   # just behind the egg (front is -Y)
    r_in, width = H * 0.9, S
    n = int((r_in + width * len(bands)) / S) + 1
    for x in range(-n, n + 1):
        for z in range(0, n + 1):
            d = math.hypot((x + 0.5) * S, (z + 0.5) * S)
            b = int((d - r_in) / width)
            if 0 <= b < len(bands):
                for y in range(2):
                    arc.cells[(x, y, z)] = bands[len(bands) - 1 - b]
    part(a, "Arc", [arc])
    return a


def disco():
    a = asset("Disco")
    centre = Vector((0, 0, H + 0.75))
    v = Vox(S, origin=centre)
    n = 4
    for x in range(-n, n + 1):
        for y in range(-n, n + 1):
            for z in range(-n, n + 1):
                d = math.sqrt(x * x + y * y + z * z)
                if n - 1.2 <= d <= n + 0.2:
                    v.cells[(x, y, z)] = ["E8ECF4", "B8C0D0", "FFFFFF", "8A93A8"][(x + 2 * y + 3 * z) % 4]
    for z in range(n + 1, n + 6):
        v.cells[(0, 0, z)] = "40465A"
    part(a, "Ball", [v])
    return a


ALL = {
    "Frozen": frozen, "Wet": wet, "Shocked": shocked, "Windswept": windswept, "Bloodlit": bloodlit,
    "Starlit": starlit, "Starstruck": starstruck, "Golden": golden, "Rainbow": rainbow, "Disco": disco,
}


def main(names):
    root = os.path.abspath(os.path.join(HERE, "..", ".."))
    out = os.path.join(root, "art", "out")
    meta_path = os.path.join(out, "meta.json")
    meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
    for name, fn in ALL.items():
        if names and name not in names:
            continue
        lib.reset_scene()
        a = fn()
        path, m = a.export(out)
        meta[a.name] = m
        print("built", a.name, m["tris"], "tris", list(m["parts"]))
    json.dump(meta, open(meta_path, "w"), indent=1)


if __name__ == "__main__":
    main([n for n in sys.argv[1:] if not n.startswith("-")])
