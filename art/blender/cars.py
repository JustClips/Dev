"""Low-poly cars for the Garage (asset names stay Vehicle_<Id> from Config/Tools.luau).

Every car is built at scale 1 in Blender units (front = -Y, up = +Z, right = +X) and then
scaled by the car's s. Parts the game uses:
  Body                 everything that doesn't move (PrimaryPart in game)
  Wheel_FL/FR/RL/RR    one per wheel, origin (joint) at the hub, spins about local X
  Brush                the sweeping roller, joint at its axle, spins about local X
  Body_Arms            arms holding the brush (static)
  Body_Glow            headlights / beacons (neon), Tail_Glow  rear lights (neon)
extra["seat"] is where the driver's VehicleSeat goes (Roblox space).
Nothing floats: wheels sit on z=0, axles and frame rails join the wheels to the body
(art/blender floating-piece check runs on every car).
"""
import math

import bpy
from mathutils import Euler, Matrix, Vector

from lib import Asset, use, sphere, box, cyl, cone, torus, capsule, tube, deform
from aliens import shade

TYRE, RIM, DARK, GLASS, METAL = "2A2A33", "D2D2DC", "2A2A3A", "9BD7F5", "B4BCCD"
LAMP, TAIL, AMBER = "FFF5C8", "FF3A4A", "FFB43C"


# ------------------------------------------------------------------ shared kit

def wheel(x, y, r, w):
    """Chunky tyre with tread blocks, a coloured rim and a hub cap; centre (x, y, r)."""
    side = 1 if x > 0 else -1
    p = [cyl(TYRE, loc=(x, y, r), r=r * 0.92, h=w, rot=(0, 90, 0), verts=20)]
    p += [torus(TYRE, loc=(x + side * k * w * 0.42, y, r), R=r * 0.86, r=r * 0.12, rot=(0, 90, 0), seg=20, mseg=6) for k in (-1, 1)]
    p += [box(shade(TYRE, 0.12), loc=(x, y + math.cos(a) * r * 0.95, r + math.sin(a) * r * 0.95), size=(w * 0.9, r * 0.22, r * 0.14),
              rot=(math.degrees(a) + 90, 0, 0)) for a in [i * math.pi / 6 for i in range(12)]]
    p.append(cyl(RIM, loc=(x + side * w / 2, y, r), r=r * 0.55, h=0.08, rot=(0, 90, 0), verts=16))
    p.append(sphere(shade(RIM, -0.25), loc=(x + side * (w / 2 + 0.04), y, r), scale=(0.06, r * 0.22, r * 0.22), seg=12, rings=6))
    p += [sphere("FFFFFF", loc=(x + side * (w / 2 + 0.05), y + math.cos(a) * r * 0.36, r + math.sin(a) * r * 0.36), scale=r * 0.06, seg=6, rings=4)
          for a in [i * math.pi * 2 / 5 for i in range(5)]]
    return p


def running_gear(front, rear, frame_bottom, rail_x):
    """Axles across each wheel pair plus two frame rails from axle to axle, reaching up
    into the body's underside, so the wheels and the body are one connected piece.
    front / rear = (y, r, track_half, width)."""
    p = []
    for (y, r, tx, w) in (front, rear):
        p.append(cyl(DARK, loc=(0, y, r), r=max(0.08, r * 0.16), h=2 * tx - w + 0.1, rot=(0, 90, 0), verts=10))
    zb = min(front[1], rear[1]) - 0.12
    zt = frame_bottom + 0.06
    for x in (-rail_x, rail_x):
        p.append(box(DARK, loc=(x, (front[0] + rear[0]) / 2, (zb + zt) / 2), size=(0.22, abs(rear[0] - front[0]) + 0.3, zt - zb)))
    return p


def steering(dash_y, dash_top, wheel_y, wheel_z, colour):
    """Dash-mounted steering column and a 3-spoke wheel facing the driver (+Y)."""
    p = []
    col0 = Vector((0, dash_y + 0.05, dash_top - 0.1))
    col1 = Vector((0, wheel_y, wheel_z))
    p.append(tube(DARK, [tuple(col0), tuple(col1)], 0.07, seg=8))
    d = col1 - col0
    tilt = -math.degrees(math.atan2(d.y, d.z))
    frame_m = Matrix.Translation(col1) @ Euler((math.radians(tilt), 0, 0)).to_matrix().to_4x4()
    rim_r = 0.36
    p.append(torus(DARK, loc=tuple(col1), R=rim_r, r=0.055, rot=(tilt, 0, 0), seg=18, mseg=6))
    for ang in (0, 180, 90):
        sp = box(DARK, loc=(0, 0, 0), size=(rim_r, 0.07, 0.06))
        sp.matrix_world = frame_m @ Matrix.Rotation(math.radians(ang), 4, "Z") @ Matrix.Translation((rim_r / 2, 0, 0))
        _apply(sp)
        p.append(sp)
    p.append(cyl(colour, loc=tuple(col1 + d.normalized() * 0.04), r=0.11, h=0.08, rot=(tilt, 0, 0), verts=12))
    return p


def roller(y, z, r, length, arm_from, colour):
    """Sweeping roller (Brush part) with end discs, and arms (Body_Arms) from arm_from
    (x, y, z inside the body) to each end of the roller."""
    brush = [cyl("FFE678", loc=(0, y, z), r=r * 0.9, h=length, rot=(0, 90, 0), verts=16)]
    brush += [box("FFB43C" if i % 2 else "FF8C3C", loc=(0, y + math.cos(t) * r, z + math.sin(t) * r), size=(length, 0.12, r * 0.45),
                  rot=(math.degrees(t), 0, 0), bevel=0.03) for i, t in enumerate([i * math.pi / 6 for i in range(12)])]
    brush += [cyl(shade(colour, -0.3), loc=(x * (length / 2 + 0.04), y, z), r=r * 0.65, h=0.1, rot=(0, 90, 0), verts=12) for x in (-1, 1)]
    arms = []
    for x in (-1, 1):
        end = (x * (length / 2 + 0.12), y, z)
        arms.append(tube(DARK, [(x * arm_from[0], arm_from[1], arm_from[2]), end], 0.11, seg=8))
        arms.append(cyl(METAL, loc=end, r=r * 0.35, h=0.14, rot=(0, 90, 0), verts=10))
    return brush, arms, (0, y, z)


def side_broom(x, y, arm_from):
    """Round gutter broom on the ground at a front corner, on an arm from the body."""
    p = [cyl(DARK, loc=(x, y, 0.2), r=0.55, h=0.12, verts=16)]
    for i in range(12):
        a = math.radians(i * 30)
        p.append(box("FFC83C", loc=(x + math.cos(a) * 0.42, y + math.sin(a) * 0.42, 0.08), size=(0.32, 0.08, 0.16), rot=(0, -20, i * 30)))
    p.append(tube(DARK, [arm_from, (x, y, 0.26)], 0.09, seg=8))
    return p


def beacon(x, y, z):
    """Amber roof beacon: a dark base on the roof and a glowing dome (returns base, glow)."""
    return [cyl(DARK, loc=(x, y, z + 0.06), r=0.2, h=0.12, verts=12)], [sphere(AMBER, loc=(x, y, z + 0.14), scale=(0.17, 0.17, 0.2), seg=12, rings=6)]


def _apply(o):
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    o.select_set(False)


def _scale(objs, s):
    for o in objs:
        deform(o, lambda v: v * s)


def build_car(name, s, spec):
    """spec: dict with body, glow, tail, wheels {key: (x, y, r, w)}, brush (pieces, arms,
    joint) or None, seat (x, y, z). Builds at scale 1, scales by s, makes the parts."""
    a = Asset(f"Vehicle_{name}", "vehicle")
    use(a)
    parts = spec(a)
    every = parts["body"] + parts["glow"] + parts["tail"] + [o for w in parts["wheels"].values() for o in w[0]]
    if parts.get("brush"):
        every += parts["brush"][0] + parts["brush"][1]
    _scale(every, s)
    a.part("Body", parts["body"], collide=True)
    for key, (pieces, hub) in parts["wheels"].items():
        a.part(f"Wheel_{key}", pieces, parent="Body", joint=tuple(c * s for c in hub))
    if parts.get("brush"):
        brush, arms, joint = parts["brush"]
        a.part("Body_Arms", arms, parent="Body")
        a.part("Brush", brush, parent="Body", joint=tuple(c * s for c in joint))
    if parts["glow"]:
        a.part("Body_Glow", parts["glow"], parent="Body", glow=parts.get("glow_col", LAMP))
    if parts["tail"]:
        a.part("Tail_Glow", parts["tail"], parent="Body", glow=TAIL)
    sx, sy, sz = parts["seat"]
    a.extra["seat"] = [round(-sx * s, 3), round(sz * s, 3), round(sy * s, 3)]
    return a


def wheels_of(layout):
    """layout {any: (x, y, r, w)} -> {"FL"/"FR"/"RL"/"RR": (pieces, hub)}. The name comes
    from the position: the car faces -Y, so the driver's LEFT is +X in Blender (which is
    -X in Roblox, where the car faces -Z and RightVector is +X)."""
    out = {}
    for (x, y, r, w) in layout.values():
        key = ("F" if y < 0 else "R") + ("L" if x > 0 else "R")
        out[key] = (wheel(x, y, r, w), (x, y, r))
    return out


def headlights(xs, y, z, r=0.16):
    return [sphere(LAMP, loc=(x, y, z), scale=(r, 0.06, r * 0.8), seg=12, rings=6) for x in xs]


def taillights(xs, y, z):
    return [box(TAIL, loc=(x, y, z), size=(0.4, 0.06, 0.2), bevel=0.03) for x in xs]


# ------------------------------------------------------------------ the cars

def sweeper_cart(color):
    def spec(a):
        b, glow, tail = [], [], []
        L = {"FL": (-1.55, -1.9, 0.65, 0.55), "FR": (1.55, -1.9, 0.65, 0.55), "RL": (-1.55, 1.9, 0.65, 0.55), "RR": (1.55, 1.9, 0.65, 0.55)}
        b.append(box(color, loc=(0, 0, 0.95), size=(3.0, 5.6, 0.7), bevel=0.15))
        b += running_gear((-1.9, 0.65, 1.55, 0.55), (1.9, 0.65, 1.55, 0.55), 0.6, 0.9)
        for y in (-1.9, 1.9):
            for x in (-1, 1):
                b.append(box(shade(color, -0.2), loc=(x * 1.55, y, 1.42), size=(0.75, 1.7, 0.16), bevel=0.05))
        b.append(box(shade(color, -0.1), loc=(0, -2.0, 1.65), size=(2.8, 1.4, 0.7), bevel=0.2))
        b.append(box(DARK, loc=(0, -2.71, 1.6), size=(1.4, 0.04, 0.35)))
        glow += headlights((-0.95, 0.95), -2.72, 1.72)
        b.append(box(shade(color, -0.3), loc=(0, -1.1, 1.7), size=(2.4, 0.4, 0.8), bevel=0.12))
        b += steering(-1.1, 2.1, -0.55, 2.45, "FF4A4A")
        b.append(box(DARK, loc=(0, 0.3, 1.47), size=(1.4, 1.0, 0.35), bevel=0.1))
        b.append(box(DARK, loc=(0, 0.85, 2.0), size=(1.4, 0.25, 1.0), bevel=0.1))
        # leaf hopper with lid, handle and a window of leaves on the back
        b.append(box(shade(color, -0.15), loc=(0, 2.0, 2.0), size=(2.6, 1.5, 1.4), bevel=0.2))
        b.append(box(shade(color, -0.4), loc=(0, 2.0, 2.74), size=(2.7, 1.6, 0.14), bevel=0.05))
        b.append(box(DARK, loc=(0, 2.76, 2.0), size=(1.8, 0.04, 0.9), bevel=0.02))
        b.append(box(GLASS, loc=(0, 2.78, 2.0), size=(1.7, 0.04, 0.8)))
        b.append(box("E09A3C", loc=(0, 2.8, 1.75), size=(1.6, 0.04, 0.3)))
        b.append(box(METAL, loc=(0, 2.8, 2.55), size=(0.8, 0.12, 0.1), bevel=0.03))
        # canopy, tall enough for a seated avatar's head (roof underside ~4.1 studs over the
        # cushion once the game scales the cart up)
        for x in (-1.3, 1.3):
            for y in (-1.25, 1.1):
                b.append(cyl("E6E6EE", loc=(x, y, 2.845), r=0.07, h=3.09, verts=8))
        b.append(box("FFFFFF", loc=(0, -0.08, 4.43), size=(3.0, 2.9, 0.15), bevel=0.05))
        b.append(box(shade(color, -0.25), loc=(0, -0.08, 4.33), size=(3.1, 3.0, 0.08)))
        bb, bg = beacon(0, -0.08, 4.5)
        b += bb
        glow += bg
        for y in (-2.95, 2.95):
            b.append(box(DARK, loc=(0, y, 0.8), size=(2.9, 0.3, 0.32), bevel=0.1))
        tail += taillights((-1.15, 1.15), 2.81, 1.1)
        brush, arms, joint = roller(-3.65, 0.45, 0.42, 3.2, (1.1, -2.6, 0.8), color)
        return {"body": b, "glow": glow, "tail": tail, "wheels": wheels_of(L), "brush": (brush, arms, joint),
                "seat": (0, 0.3, 1.75), "glow_col": AMBER}
    return spec


def golf_cart(color):
    def spec(a):
        b, glow, tail = [], [], []
        L = {"FL": (-1.35, -1.75, 0.5, 0.45), "FR": (1.35, -1.75, 0.5, 0.45), "RL": (-1.35, 1.75, 0.5, 0.45), "RR": (1.35, 1.75, 0.5, 0.45)}
        b.append(box(color, loc=(0, 0, 0.75), size=(2.5, 5.0, 0.45), bevel=0.12))
        b += running_gear((-1.75, 0.5, 1.35, 0.45), (1.75, 0.5, 1.35, 0.45), 0.53, 0.8)
        # rounded front cowl with headlights
        b.append(box(color, loc=(0, -1.9, 1.3), size=(2.4, 1.3, 0.7), bevel=0.25))
        b.append(sphere(color, loc=(0, -2.45, 1.15), scale=(1.15, 0.35, 0.38), seg=16, rings=8))
        glow += headlights((-0.75, 0.75), -2.62, 1.35, r=0.14)
        b.append(box(shade(color, -0.3), loc=(0, -1.1, 1.6), size=(2.2, 0.3, 0.5), bevel=0.1))
        b += steering(-1.1, 1.85, -0.6, 2.15, "FFFFFF")
        # bench seat for two on a pedestal
        b.append(box("F5F0E6", loc=(0, 0.4, 1.2), size=(2.0, 0.8, 0.45), bevel=0.08))
        b.append(box(DARK, loc=(0, 0.4, 1.55), size=(2.2, 0.9, 0.3), bevel=0.1))
        b.append(box(DARK, loc=(0, 0.95, 2.05), size=(2.2, 0.22, 0.9), bevel=0.1))
        # rear deck with a golf bag and clubs
        b.append(box(shade(color, -0.15), loc=(0, 1.9, 1.27), size=(2.2, 1.0, 0.6), bevel=0.12))
        b.append(cyl("2E5AA8", loc=(0.4, 1.95, 2.25), r=0.28, h=1.4, verts=14))
        b.append(torus("FFFFFF", loc=(0.4, 1.95, 2.95), R=0.28, r=0.04, seg=14, mseg=4))
        for k, (dx, dy) in enumerate(((-0.08, 0.05), (0.1, -0.06), (0.02, 0.1))):
            b.append(cyl(METAL, loc=(0.4 + dx, 1.95 + dy, 3.15), r=0.03, h=0.55, verts=6))
            b.append(box(METAL, loc=(0.4 + dx + 0.06, 1.95 + dy, 3.45), size=(0.16, 0.06, 0.08)))
        # roof on four posts and a windshield between the front posts
        for x in (-1.05, 1.05):
            for y in (-1.0, 1.3):
                b.append(cyl("F0F0F0", loc=(x, y, 2.34), r=0.06, h=2.73, verts=8))
        b.append(box("FFFFFF", loc=(0, 0.15, 3.76), size=(2.5, 3.0, 0.12), bevel=0.05))
        b.append(box(GLASS, loc=(0, -1.0, 2.5), size=(2.04, 0.04, 1.4)))
        for y in (-2.6, 2.6):
            b.append(box(DARK, loc=(0, y, 0.65), size=(2.4, 0.25, 0.28), bevel=0.08))
        tail += taillights((-0.95, 0.95), 2.42, 1.27)
        brush, arms, joint = roller(-3.05, 0.35, 0.3, 2.6, (0.9, -2.4, 0.7), color)
        return {"body": b, "glow": glow, "tail": tail, "wheels": wheels_of(L), "brush": (brush, arms, joint), "seat": (0, 0.4, 1.75)}
    return spec


def garbage_truck(color):
    def spec(a):
        b, glow, tail = [], [], []
        L = {"FL": (-1.6, -2.4, 0.75, 0.6), "FR": (1.6, -2.4, 0.75, 0.6), "RL": (-1.6, 2.0, 0.75, 0.6), "RR": (1.6, 2.0, 0.75, 0.6)}
        green = "3C9A50"
        b.append(box(DARK, loc=(0, -0.1, 1.0), size=(2.8, 6.6, 0.4)))
        b += running_gear((-2.4, 0.75, 1.6, 0.6), (2.0, 0.75, 1.6, 0.6), 0.8, 0.9)
        # cab
        b.append(box(color, loc=(0, -2.6, 2.15), size=(3.0, 1.9, 1.9), bevel=0.2))
        b.append(box(GLASS, loc=(0, -3.56, 2.6), size=(2.5, 0.04, 0.75)))
        for x in (-1, 1):
            b.append(box(GLASS, loc=(x * 1.51, -2.75, 2.6), size=(0.04, 1.0, 0.6)))
            b.append(box(DARK, loc=(x * 1.62, -3.3, 2.35), size=(0.18, 0.1, 0.4)))      # mirror
        b.append(box(DARK, loc=(0, -3.56, 1.55), size=(2.0, 0.04, 0.5)))
        glow += headlights((-1.1, 1.1), -3.58, 1.55)
        for x in (-1, 1):
            b.append(box(shade(color, -0.2), loc=(x * 1.6, -2.4, 1.6), size=(0.7, 1.6, 0.14), bevel=0.05))
        # compactor body with ribs, rear hopper and lift arms
        b.append(box(green, loc=(0, 0.75, 2.4), size=(3.1, 4.2, 2.4), bevel=0.15))
        for x in (-1, 1):
            for k in range(5):
                b.append(box(shade(green, -0.2), loc=(x * 1.57, -0.85 + k * 0.8, 2.4), size=(0.06, 0.14, 2.2)))
            # stripe sits just outside the ribs (ribs end at 1.60) so the faces never overlap
            b.append(box(shade(color, 0), loc=(x * 1.635, 0.75, 1.5), size=(0.05, 4.1, 0.18)))
        b.append(box(shade(green, -0.1), loc=(0, 3.2, 2.2), size=(3.0, 0.9, 2.0), bevel=0.15))
        b.append(box("1A1A22", loc=(0, 3.66, 2.55), size=(2.4, 0.04, 0.9)))
        for x in (-1, 1):
            b.append(box(METAL, loc=(x * 1.25, 3.75, 1.5), size=(0.15, 0.25, 1.2)))
        # exhaust stack between cab and body
        b.append(cyl(METAL, loc=(1.2, -1.55, 3.3), r=0.1, h=1.8, verts=10))
        bb, bg = beacon(0, -2.6, 3.1)
        b += bb
        glow += bg
        b.append(box(DARK, loc=(0, -3.7, 1.05), size=(3.0, 0.3, 0.4), bevel=0.1))
        tail += taillights((-1.2, 1.2), 3.66, 1.6)
        brush, arms, joint = roller(-4.25, 0.4, 0.36, 3.0, (1.0, -3.3, 1.0), color)
        return {"body": b, "glow": glow, "tail": tail, "wheels": wheels_of(L), "brush": (brush, arms, joint),
                "seat": (0, -2.5, 2.0), "glow_col": AMBER}
    return spec


def street_sweeper(color):
    def spec(a):
        b, glow, tail = [], [], []
        L = {"FL": (-1.35, -1.6, 0.55, 0.5), "FR": (1.35, -1.6, 0.55, 0.5), "RL": (-1.35, 1.8, 0.55, 0.5), "RR": (1.35, 1.8, 0.55, 0.5)}
        b.append(box(DARK, loc=(0, 0, 0.85), size=(2.6, 5.4, 0.5)))
        b += running_gear((-1.6, 0.55, 1.35, 0.5), (1.8, 0.55, 1.35, 0.5), 0.6, 0.8)
        # cab-forward with a big windshield
        b.append(box(color, loc=(0, -1.7, 1.95), size=(2.7, 1.8, 1.7), bevel=0.2))
        b.append(box(GLASS, loc=(0, -2.61, 2.25), size=(2.4, 0.04, 0.9)))
        for x in (-1, 1):
            b.append(box(GLASS, loc=(x * 1.36, -1.8, 2.3), size=(0.04, 1.2, 0.8)))
        glow += headlights((-0.9, 0.9), -2.62, 1.4)
        # hopper with a water tank on top
        b.append(box("F0F0F5", loc=(0, 1.2, 2.05), size=(2.7, 2.8, 1.9), bevel=0.2))
        b.append(box(color, loc=(0, 1.2, 1.6), size=(2.74, 2.84, 0.25)))
        b.append(cyl("5AA0E6", loc=(0, 1.2, 3.55), r=0.8, h=2.4, rot=(90, 0, 0), verts=16))
        for y in (0.3, 2.1):
            b.append(torus(DARK, loc=(0, y, 3.55), R=0.8, r=0.05, rot=(90, 0, 0), seg=16, mseg=4))
        # gutter brooms at the front corners
        for x in (-1, 1):
            b += side_broom(x * 1.45, -2.9, (x * 1.1, -2.5, 0.75))
        for x in (-0.7, 0.7):
            bb, bg = beacon(x, -1.7, 2.8)
            b += bb
            glow += bg
        tail += taillights((-1.0, 1.0), 2.61, 1.5)
        # main roller under the middle, between the axles
        brush, arms, joint = roller(0.1, 0.42, 0.38, 2.2, (0.7, 0.1, 0.7), color)
        return {"body": b, "glow": glow, "tail": tail, "wheels": wheels_of(L), "brush": (brush, arms, joint),
                "seat": (0, -1.5, 1.8), "glow_col": AMBER}
    return spec


def lawn_tractor(color):
    def spec(a):
        b, glow, tail = [], [], []
        L = {"FL": (-1.05, -1.7, 0.42, 0.35), "FR": (1.05, -1.7, 0.42, 0.35), "RL": (-1.25, 1.3, 0.75, 0.6), "RR": (1.25, 1.3, 0.75, 0.6)}
        b.append(box(DARK, loc=(0, -0.2, 0.7), size=(1.6, 4.0, 0.3)))
        b += running_gear((-1.7, 0.42, 1.05, 0.35), (1.3, 0.75, 1.25, 0.6), 0.55, 0.6)
        # long hood with a grille
        b.append(box(color, loc=(0, -1.45, 1.2), size=(1.5, 1.9, 0.75), bevel=0.25))
        b.append(box(DARK, loc=(0, -2.41, 1.15), size=(1.0, 0.04, 0.45)))
        glow += headlights((-0.45, 0.45), -2.42, 1.45, r=0.1)
        b.append(cyl(DARK, loc=(0.45, -1.2, 1.75), r=0.06, h=0.4, verts=8))
        # console and steering
        b.append(box(shade(color, -0.25), loc=(0, -0.35, 1.2), size=(0.8, 0.4, 0.7), bevel=0.1))
        b += steering(-0.35, 1.55, 0.0, 1.95, "FFD23C")
        # rear body, fender deck and the seat
        b.append(box(color, loc=(0, 1.2, 1.25), size=(1.6, 1.8, 0.8), bevel=0.15))
        b.append(box(color, loc=(0, 1.3, 1.65), size=(2.9, 1.6, 0.25), bevel=0.1))
        b.append(box(DARK, loc=(0, 1.3, 1.9), size=(1.0, 0.8, 0.25), bevel=0.08))
        b.append(box(DARK, loc=(0, 1.75, 2.3), size=(1.0, 0.2, 0.8), bevel=0.08))
        # mower deck hung under the frame, with a side chute
        b.append(box(shade(color, -0.35), loc=(0, -0.2, 0.35), size=(2.3, 1.4, 0.25), bevel=0.08))
        for x in (-0.5, 0.5):
            b.append(box(DARK, loc=(x, -0.2, 0.52), size=(0.1, 0.1, 0.2)))
        b.append(box(shade(color, -0.35), loc=(1.3, -0.2, 0.32), size=(0.4, 0.6, 0.18), rot=(0, -15, 0)))
        tail += taillights((-0.6, 0.6), 2.11, 1.3)
        brush, arms, joint = roller(-2.7, 0.3, 0.27, 2.0, (0.6, -2.1, 0.7), color)
        return {"body": b, "glow": glow, "tail": tail, "wheels": wheels_of(L), "brush": (brush, arms, joint), "seat": (0, 1.3, 2.05)}
    return spec


def snow_plow(color):
    def spec(a):
        b, glow, tail = [], [], []
        orange = "FF8C2A"
        L = {"FL": (-1.4, -1.7, 0.6, 0.5), "FR": (1.4, -1.7, 0.6, 0.5), "RL": (-1.4, 1.6, 0.6, 0.5), "RR": (1.4, 1.6, 0.6, 0.5)}
        b.append(box(color, loc=(0, 0, 1.0), size=(2.7, 5.6, 0.45), bevel=0.1))
        b += running_gear((-1.7, 0.6, 1.4, 0.5), (1.6, 0.6, 1.4, 0.5), 0.78, 0.85)
        # pickup cab and hood
        b.append(box(color, loc=(0, -0.5, 1.92), size=(2.7, 1.7, 1.4), bevel=0.2))
        b.append(box(color, loc=(0, -2.1, 1.52), size=(2.6, 1.6, 0.6), bevel=0.15))
        b.append(box(GLASS, loc=(0, -1.36, 2.2), size=(2.3, 0.04, 0.7)))
        for x in (-1, 1):
            b.append(box(GLASS, loc=(x * 1.36, -0.5, 2.2), size=(0.04, 1.2, 0.6)))
            b.append(box(shade(color, -0.2), loc=(x * 1.38, -1.7, 1.35), size=(0.12, 1.4, 0.15)))
        b.append(box(DARK, loc=(0, -2.91, 1.45), size=(1.6, 0.04, 0.35)))
        glow += headlights((-0.9, 0.9), -2.92, 1.55)
        # light bar on the roof
        b.append(box(DARK, loc=(0, -0.5, 2.68), size=(1.8, 0.3, 0.12)))
        for x in (-0.6, 0.6):
            glow.append(box(AMBER, loc=(x, -0.5, 2.8), size=(0.5, 0.26, 0.16), bevel=0.04))
        # bed with a salt spreader
        b.append(box(shade(color, -0.1), loc=(0, 1.75, 1.32), size=(2.7, 2.0, 0.2)))
        for x in (-1, 1):
            b.append(box(color, loc=(x * 1.28, 1.75, 1.72), size=(0.15, 2.0, 0.6)))
        b.append(box(color, loc=(0, 2.68, 1.72), size=(2.7, 0.15, 0.6)))
        b.append(box(orange, loc=(0, 1.6, 1.77), size=(1.4, 1.2, 0.7), bevel=0.1))
        # plow blade on two push arms
        for x in (-0.8, 0.8):
            b.append(tube(DARK, [(x, -2.75, 0.95), (x, -3.35, 0.6)], 0.1, seg=8))
        for k, (dz, ang) in enumerate(((0.25, 25), (0.65, 0), (1.0, -20))):
            b.append(box(orange, loc=(0, -3.45 - 0.08 * (1 - k), dz), size=(3.6, 0.14, 0.42), rot=(ang, 0, 0)))
        for x in (-1.8, 1.8):
            b.append(box(DARK, loc=(x, -3.45, 0.6), size=(0.08, 0.4, 1.1)))
        tail += taillights((-1.0, 1.0), 2.77, 1.55)
        brush, arms, joint = roller(-2.95, 0.3, 0.27, 2.4, (0.9, -2.6, 0.85), color)
        return {"body": b, "glow": glow, "tail": tail, "wheels": wheels_of(L), "brush": (brush, arms, joint),
                "seat": (0, -0.4, 1.9), "glow_col": AMBER}
    return spec


def mega_sweeper(color):
    def spec(a):
        b, glow, tail = [], [], []
        L = {"FL": (-1.75, -2.2, 0.7, 0.65), "FR": (1.75, -2.2, 0.7, 0.65), "RL": (-1.75, 2.2, 0.7, 0.65), "RR": (1.75, 2.2, 0.7, 0.65)}
        b.append(box(DARK, loc=(0, 0, 1.0), size=(3.4, 6.6, 0.6)))
        b += running_gear((-2.2, 0.7, 1.75, 0.65), (2.2, 0.7, 1.75, 0.65), 0.7, 1.1)
        # big hopper body with stripes and vents
        b.append(box(color, loc=(0, 0.9, 2.3), size=(3.5, 4.4, 2.0), bevel=0.2))
        for z in (1.7, 2.9):
            b.append(box("FFFFFF", loc=(0, 0.9, z), size=(3.54, 4.44, 0.14)))
        for x in (-1, 1):
            for k in range(3):
                b.append(box("1A1A22", loc=(x * 1.76, 0.0 + k * 0.9, 2.3), size=(0.04, 0.6, 0.35)))
        # cab with glass
        b.append(box(shade(color, -0.15), loc=(0, -2.2, 2.05), size=(2.4, 1.8, 1.5), bevel=0.2))
        b.append(box(GLASS, loc=(0, -3.11, 2.3), size=(2.1, 0.04, 0.8)))
        for x in (-1, 1):
            b.append(box(GLASS, loc=(x * 1.21, -2.3, 2.3), size=(0.04, 1.2, 0.7)))
        b.append(box(DARK, loc=(0, -2.2, 2.85), size=(2.5, 1.9, 0.1)))
        glow += headlights((-1.2, 1.2), -3.32, 1.2, r=0.2)
        b.append(box(DARK, loc=(0, -3.4, 1.2), size=(3.2, 0.2, 0.5), bevel=0.08))
        for x in (-0.8, 0.8):
            bb, bg = beacon(x, -2.2, 2.9)
            b += bb
            glow += bg
        # twin exhaust stacks on the hopper
        for x in (-1.3, 1.3):
            b.append(cyl(METAL, loc=(x, 2.6, 3.85), r=0.12, h=1.2, verts=10))
            b.append(cyl(DARK, loc=(x, 2.6, 4.47), r=0.14, h=0.06, verts=10))
        for x in (-1, 1):
            b += side_broom(x * 1.85, -3.7, (x * 1.4, -3.2, 0.9))
        tail += taillights((-1.3, 1.3), 3.11, 1.6)  # on the hopper's rear face
        brush, arms, joint = roller(-4.25, 0.48, 0.45, 3.8, (1.2, -3.2, 0.9), color)
        return {"body": b, "glow": glow, "tail": tail, "wheels": wheels_of(L), "brush": (brush, arms, joint),
                "seat": (0, -2.1, 2.0), "glow_col": AMBER}
    return spec


VEHICLES = {
    "SweeperCart": lambda: build_car("SweeperCart", 1.0, sweeper_cart("50C878")),
    "MoonBuggy": lambda: build_car("MoonBuggy", 1.15, golf_cart("FF8C3C")),
    "DustTruck": lambda: build_car("DustTruck", 1.35, garbage_truck("FFB428")),
    "HoverSweeper": lambda: build_car("HoverSweeper", 1.5, street_sweeper("B478FF")),
    "MoonCrawler": lambda: build_car("MoonCrawler", 1.8, lawn_tractor("5AA0FF")),
    "SolarRover": lambda: build_car("SolarRover", 2.0, snow_plow("F0F0F5")),
    "RocketSweeper": lambda: build_car("RocketSweeper", 2.2, mega_sweeper("FF4A5A")),
}
