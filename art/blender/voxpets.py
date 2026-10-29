"""Voxel pets: blocky, pixel-coloured animals (cat and dog so far).

Each pet is built from small cubes on a grid (U studs each). Every cube gets a slightly
different shade of its colour, which gives the pixelated look. Parts follow the shared pet
rig names (Body, Head, EarL/R, LegFL/FR/BL/BR, Tail) plus Tail2 for a two-piece tail, and
are rigged at runtime with Motor6Ds like the other pets (AssetLibrary.prepare).

Each pet has its own idle and walk animation. They are keyframed in Blender on empties at
the joints (Idle on frames 0-90, Walk on frames 120-138, 30 fps; open the saved .blend to
scrub or tweak them) and sampled into Roblox KeyframeSequences.

Usage (repo root, headless or inside Blender):
  python art/blender/voxpets.py [Cat Dog]
    -> art/out/Alien_<Name>.glb, art/out/Alien_<Name>.blend, art/out/anims/Pet_<Name>_Idle/_Walk.rbxmx,
       merged into art/out/meta.json

Grid coordinates: x is the pet's left (+X), y runs front (-Y) to back, z is up.
Ranges are half-open: box(x0, x1, ...) fills x0 <= i < x1.
"""
import math
import os
import sys
import json

import bpy
import bmesh
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "anim"))

from lib import Asset  # noqa: E402

U = 0.13            # cube size in studs
FPS = 30
IDLE = (0, 90)      # frames
WALK = (120, 138)
OUT = os.path.join(HERE, "..", "out")

EYE = "241A16"
SHINE = "FFFFFF"


def shade(h, k):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) for i in (0, 2, 4)]
    c = [round(x + (255 - x) * k) if k >= 0 else round(x * (1 + k)) for x in c]
    return "".join(f"{max(0, min(255, x)):02X}" for x in c)


def jitter(col, c):
    """One of four shades of `col`, picked by a hash of the cell: the pixel noise."""
    h = (c[0] * 73856093) ^ (c[1] * 19349663) ^ (c[2] * 83492791)
    k = (-0.07, -0.025, 0.0, 0.05)[h % 4]
    return shade(col, k)


class Part:
    def __init__(self, name, parent=None, joint=None, noise=True):
        self.name, self.parent, self.noise = name, parent, noise
        self.joint = joint            # in grid units, None = centre of the part
        self.cells = {}

    def box(self, x0, x1, y0, y1, z0, z1, col):
        """col: hex, or fn(i, j, k) -> hex / None (None leaves the cell empty)."""
        for i in range(x0, x1):
            for j in range(y0, y1):
                for k in range(z0, z1):
                    cc = col(i, j, k) if callable(col) else col
                    if cc:
                        self.cells[(i, j, k)] = cc
        return self

    def set(self, cells, col):
        for c in cells:
            self.cells[tuple(c)] = col
        return self

    def mirror(self, name, joint=None):
        p = Part(name, self.parent, joint, self.noise)
        p.cells = {(-1 - i, j, k): c for (i, j, k), c in self.cells.items()}
        if self.joint and joint is None:
            p.joint = (-self.joint[0], self.joint[1], self.joint[2])
        return p

    def centre(self):
        lo = [min(c[a] for c in self.cells) for a in range(3)]
        hi = [max(c[a] for c in self.cells) + 1 for a in range(3)]
        return tuple((lo[a] + hi[a]) / 2 for a in range(3))


DIRS = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]


def mesh_part(a, p):
    """Outside faces of the part's cubes, each face UV'd to its colour swatch."""
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    for c, col in p.cells.items():
        if p.noise and col not in (EYE, SHINE):
            col = jitter(col, c)
        uv = a.swatch(col)
        ctr = Vector(((c[0] + 0.5) * U, (c[1] + 0.5) * U, (c[2] + 0.5) * U))
        for d in DIRS:
            if (c[0] + d[0], c[1] + d[1], c[2] + d[2]) in p.cells:
                continue
            n = Vector(d)
            vdir = Vector((0, 0, 1)) if d[2] == 0 else Vector((0, 1, 0))
            udir = vdir.cross(n)
            fc = ctr + n * U / 2
            vs = [bm.verts.new(fc + (udir * cu + vdir * cv) * U / 2) for cu, cv in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
            f = bm.faces.new(vs)
            for loop in f.loops:
                loop[uvl].uv = uv
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=U * 0.01)
    me = bpy.data.meshes.new(p.name)
    bm.to_mesh(me)
    bm.free()
    for poly in me.polygons:
        poly.use_smooth = False
    o = bpy.data.objects.new(p.name, me)
    bpy.context.collection.objects.link(o)
    return o


def assemble(key, parts):
    """The asset is Alien_<key> (the game's pet model name); its anims are Pet_<key>_Idle/_Walk."""
    name = f"Alien_{key}"
    a = Asset(name, "alien")
    for p in parts:
        o = mesh_part(a, p)
        j = p.joint if p.joint is not None else p.centre()
        a.parts[p.name] = {"obj": o, "parent": p.parent, "joint": [x * U for x in j] if p.parent else None,
                           "glow": None, "material": None, "collide": False}
    a.extra["voxel"] = True
    a.extra["anims"] = {"idle": f"Pet_{key}_Idle", "walk": f"Pet_{key}_Walk"}
    return a


# ----------------------------------------------------------------------------- legs


def legs(col, paw, h, front_y, back_y, sock=None, sock_h=1):
    """Four 2x2 legs, h cubes tall. front_y/back_y: the y of each pair's front cube."""
    out = []
    for name, x0, y0 in (("LegFL", 1, front_y), ("LegFR", -3, front_y), ("LegBL", 1, back_y), ("LegBR", -3, back_y)):
        p = Part(name, "Body", joint=(x0 + 1, y0 + 1, h))
        s = sock if (sock and name.startswith("LegF")) else None
        p.box(x0, x0 + 2, y0, y0 + 2, 0, h, lambda i, j, k, s=s: paw if k == 0 else (s if s and k <= sock_h else col))
        out.append(p)
    return out


# ------------------------------------------------------------------------------ cat


def cat():
    O, S, C, P, B = "F28A2E", "C85F17", "FBE3C2", "FF9AB0", "FFB7C5"   # orange, stripe, cream, pink, blush
    parts = legs(O, C, 4, -5, 3)

    body = Part("Body")
    body.box(-3, 3, -6, 6, 4, 9, lambda i, j, k:
             C if (k == 4 and -4 <= j <= 3) or (j == -6 and k <= 6 and -2 <= i <= 1)
             else S if (k >= 7 and j % 3 == 0 and j > -6) or (k == 8 and i in (-1, 0) and j % 3 == 1)
             else O)
    parts.append(body)

    head = Part("Head", "Body", joint=(0, -6, 8))

    def hcol(i, j, k):
        if k == 13 and j <= -8 and i in (-1, 0):
            return S                                   # forehead stripes
        if k == 12 and j == -10 and i in (-2, 1):
            return S
        if j == -11 and k <= 8 and -3 <= i <= 2:
            return C                                   # chin / lower cheeks
        if k == 7 and -3 <= i <= 2 and j <= -8:
            return C
        return O
    head.box(-4, 4, -11, -5, 7, 14, hcol)
    # face on the front layer (y = -11)
    for x0 in (-3, 1):
        head.set([(x0, -11, 10), (x0 + 1, -11, 10), (x0, -11, 11), (x0 + 1, -11, 11)], EYE)
    head.set([(-3, -11, 11), (1, -11, 11)], SHINE)
    head.set([(-4, -11, 9), (3, -11, 9)], B)          # blush
    head.box(-2, 2, -12, -11, 8, 10, C)               # muzzle
    head.set([(-1, -12, 9), (0, -12, 9)], P)           # nose
    head.set([(-1, -12, 8), (0, -12, 8)], "8C4A3A")    # mouth
    parts.append(head)

    ear = Part("EarL", "Head", joint=(2.5, -8, 14))
    for k, xs in ((14, (1, 2, 3)), (15, (2, 3)), (16, (3,))):
        for x in xs:
            for y in (-9, -8):
                inner = y == -9 and ((k == 14 and x == 2) or (k == 15 and x == 2))
                ear.cells[(x, y, k)] = P if inner else O
    parts += [ear, ear.mirror("EarR")]

    tail = Part("Tail", "Body", joint=(0, 6, 8))
    tail.box(-1, 1, 6, 8, 7, 9, O)
    tail.box(-1, 1, 7, 9, 9, 11, lambda i, j, k: S if k == 10 else O)
    tail2 = Part("Tail2", "Tail", joint=(0, 8, 11))
    tail2.box(-1, 1, 7, 9, 11, 15, lambda i, j, k: S if k in (12, 14) else O)
    tail2.box(-1, 1, 6, 8, 15, 16, S)
    parts += [tail, tail2]
    return assemble("Cat", parts)


# ------------------------------------------------------------------------------ dog


def dog():
    T, C, E, N, P = "D98C45", "FAEBD3", "8A4E24", "2A1C16", "FF7A8E"   # tan, cream, ear brown, nose, tongue
    parts = legs(T, C, 5, -6, 4, sock=C, sock_h=1)

    body = Part("Body")
    body.box(-3, 3, -7, 7, 5, 10, lambda i, j, k:
             C if (k == 5 and -5 <= j <= 4) or (j <= -6 and k <= 8 and -2 <= i <= 1) else T)
    parts.append(body)

    head = Part("Head", "Body", joint=(0, -7, 9))

    def hcol(i, j, k):
        if j == -12 and k <= 10 and -3 <= i <= 2:
            return C                                   # cream face mask
        if j == -12 and k == 14 and i in (-3, 2):
            return C                                   # eyebrow dots
        return T
    head.box(-4, 4, -12, -6, 8, 15, hcol)
    for x0 in (-3, 1):
        head.set([(x0, -12, 12), (x0 + 1, -12, 12), (x0, -12, 13), (x0 + 1, -12, 13)], EYE)
    head.set([(-3, -12, 13), (1, -12, 13)], SHINE)
    head.box(-2, 2, -15, -12, 8, 11, C)                # snout
    head.set([(-1, -15, 10), (0, -15, 10)], N)         # nose
    head.set([(-1, -15, 8), (0, -15, 8)], "8C5A44")    # mouth
    head.set([(-1, -14, 7), (0, -14, 7), (-1, -13, 7), (0, -13, 7)], P)   # tongue
    parts.append(head)

    ear = Part("EarL", "Head", joint=(4, -9, 15))
    ear.box(3, 5, -10, -8, 15, 16, E)
    ear.box(4, 5, -10, -8, 10, 15, lambda i, j, k: shade(E, -0.15) if k == 10 else E)
    parts += [ear, ear.mirror("EarR")]

    tail = Part("Tail", "Body", joint=(0, 7, 9))
    tail.box(-1, 1, 7, 9, 9, 13, T)
    tail2 = Part("Tail2", "Tail", joint=(0, 8, 13))
    tail2.box(-1, 1, 6, 9, 13, 15, lambda i, j, k: C if j == 6 else T)
    parts += [tail, tail2]
    return assemble("Dog", parts)


PETS = {"Cat": cat, "Dog": dog}


# ------------------------------------------------------------------------- animation
# Each pose fn(w) returns {part: (offset xyz in studs, rotation xyz in degrees)} in Blender
# axes about the part's joint, relative to its parent. w runs 0..2pi over one loop.
# Rotation about X swings a leg (+ = foot goes back), about Z turns (yaw), about Y rolls.

s, c = math.sin, math.cos


def cat_idle(w):
    look = 14 * s(w) + 4 * s(3 * w)
    twitch = 22 * max(0.0, s(5 * w + 1)) ** 8          # quick ear flicks
    return {
        "Body": ((0, 0, 0.015 * (1 - c(2 * w))), (1.2 * s(2 * w), 0, 0)),
        "Head": ((0, 0, 0), (-4 * s(2 * w + 0.5), 4 * s(w + 0.8), look)),
        "EarL": ((0, 0, 0), (0, -twitch, 0)),
        "EarR": ((0, 0, 0), (0, 0.6 * twitch * (s(w) > 0), 0)),
        "Tail": ((0, 0, 0), (6 * s(w), 0, 18 * s(w))),
        "Tail2": ((0, 0, 0), (10 * s(w - 0.8), 0, 26 * s(w - 1.0))),
    }


def dog_idle(w):
    pant = s(6 * w)                                       # panting
    wag = s(8 * w)                                        # happy tail
    return {
        "Body": ((0, 0, 0.012 * (1 + pant)), (0.8 * pant, 0, 0)),
        "Head": ((0, 0, 0.01 * pant), (-3 * pant - 4 * s(w), 6 * s(w + 0.4), 10 * s(w))),
        "EarL": ((0, 0, 0), (4 * pant, -5 - 4 * s(2 * w), 0)),
        "EarR": ((0, 0, 0), (4 * pant, 5 + 4 * s(2 * w), 0)),
        "Tail": ((0, 0, 0), (-8, 0, 28 * wag)),
        "Tail2": ((0, 0, 0), (0, 0, 22 * s(8 * w - 0.9))),
    }


def walk(swing, bob, tail_wag, tail_up, ear_flop):
    def f(w):
        leg = swing * s(w)
        return {
            "Body": ((0, 0, bob * abs(s(w))), (2.5 * s(2 * w), 2.5 * s(w), 0)),
            "Head": ((0, 0, 0), (-3 * s(2 * w + 0.6), -2 * s(w), 3 * s(w))),
            "LegFL": ((0, 0, 0), (leg, 0, 0)), "LegBR": ((0, 0, 0), (leg, 0, 0)),
            "LegFR": ((0, 0, 0), (-leg, 0, 0)), "LegBL": ((0, 0, 0), (-leg, 0, 0)),
            "EarL": ((0, 0, 0), (ear_flop * s(2 * w), -ear_flop * 0.6 * s(2 * w), 0)),
            "EarR": ((0, 0, 0), (ear_flop * s(2 * w), ear_flop * 0.6 * s(2 * w), 0)),
            "Tail": ((0, 0, 0), (tail_up, 0, tail_wag * s(w))),
            "Tail2": ((0, 0, 0), (0, 0, tail_wag * 0.8 * s(w - 0.9))),
        }
    return f


ANIMS = {
    "Cat": {"Idle": cat_idle, "Walk": walk(30, 0.05, 14, 6, 4)},
    "Dog": {"Idle": dog_idle, "Walk": walk(34, 0.06, 26, -6, 14)},
}


def joint_empties(a):
    """An empty at every joint, parented like the parts, with each mesh parented to its
    empty so the Blender viewport shows the animation."""
    empties = {}
    for name, p in a.parts.items():
        o = p["obj"]
        if p["joint"] is None:      # Body pivots about its centre, like the Roblox rig
            bb = [o.matrix_world @ Vector(v) for v in o.bound_box]
            loc = sum(bb, Vector()) / 8
        else:
            loc = Vector(p["joint"])
        e = bpy.data.objects.new(f"Joint_{name}", None)
        e.empty_display_type = "SPHERE"
        e.empty_display_size = U * 0.8
        e.location = loc
        e.rotation_mode = "XYZ"
        bpy.context.collection.objects.link(e)
        empties[name] = e
    bpy.context.view_layer.update()
    for name, p in a.parts.items():
        e = empties[name]
        if p["parent"]:
            e.parent = empties[p["parent"]]
            e.matrix_parent_inverse = empties[p["parent"]].matrix_world.inverted()
        o = p["obj"]
        mw = o.matrix_world.copy()
        o.parent = e
        o.matrix_parent_inverse = e.matrix_world.inverted()
        o.matrix_world = mw
    bpy.context.view_layer.update()
    return empties


def keyframe(empties, rest, fn, frames):
    f0, f1 = frames
    for f in range(f0, f1 + 1):
        w = 2 * math.pi * (f - f0) / (f1 - f0)
        pose = fn(w)
        for name, e in empties.items():
            off, rot = pose.get(name, ((0, 0, 0), (0, 0, 0)))
            e.location = rest[name] + Vector(off)
            e.rotation_euler = [math.radians(r) for r in rot]
            e.keyframe_insert("location", frame=f)
            e.keyframe_insert("rotation_euler", frame=f)


P = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))     # Blender axes -> Roblox axes


def sample(a, empties, name, frames, priority):
    from build_anims import sequence
    scn = bpy.context.scene
    f0, f1 = frames

    def local(k, e):
        par = a.parts[k]["parent"]
        pm = empties[par].matrix_world if par else Matrix.Identity(4)
        return pm.inverted() @ e.matrix_world

    scn.frame_set(f0)
    rest = {k: local(k, e) for k, e in empties.items()}
    tree = {"RootPart": {"Body": {}}}
    kids = {}
    for k, p in a.parts.items():
        if p["parent"]:
            kids.setdefault(p["parent"], {})[k] = {}
    def nest(k):
        return {c: nest(c) for c in kids.get(k, {})}
    tree["RootPart"]["Body"] = nest("Body")
    out = []
    step = 1 if f1 - f0 <= 24 else 2
    for f in range(f0, f1 + 1, step):
        scn.frame_set(f)
        poses = {}
        for k, e in empties.items():
            t = rest[k].inverted() @ local(k, e)
            mv = t.to_translation()
            r = P @ t.to_3x3() @ P.inverted()
            poses[k] = ((-mv.x, mv.z, mv.y), [[r[i][j] for j in range(3)] for i in range(3)])
        out.append(((f - f0) / FPS, poses))
    scn.frame_set(f0)
    return sequence(name, out, True, priority, tree)


def build(key, out_dir=OUT):
    a = PETS[key]()
    path, meta = a.export(out_dir)
    empties = joint_empties(a)
    rest = {k: e.location.copy() for k, e in empties.items()}
    scn = bpy.context.scene
    scn.render.fps = FPS
    scn.frame_start, scn.frame_end = IDLE[0], WALK[1]
    keyframe(empties, rest, ANIMS[key]["Idle"], IDLE)
    keyframe(empties, rest, ANIMS[key]["Walk"], WALK)
    for e in empties.values():
        ad = e.animation_data
        if ad and ad.action:
            # the walk starts where the idle ends; hold steady between them
            for m in getattr(ad.action, "fcurves", []) or []:
                for kp in m.keyframe_points:
                    kp.interpolation = "LINEAR"
    anim_dir = os.path.join(out_dir, "anims")
    os.makedirs(anim_dir, exist_ok=True)
    for kind, frames, prio in (("Idle", IDLE, 0), ("Walk", WALK, 1)):
        nm = f"Pet_{key}_{kind}"
        with open(os.path.join(anim_dir, f"{nm}.rbxmx"), "w") as fh:
            fh.write(sample(a, empties, nm, frames, prio))
    blend = os.path.abspath(os.path.join(out_dir, f"{a.name}.blend"))
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    tris = meta["tris"]
    print(f"built {a.name}: {tris} tris, {len(meta['parts'])} parts -> {path}, {blend}")
    return a, meta, empties


def main(keys):
    meta_path = os.path.join(OUT, "meta.json")
    allm = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
    for k in keys or PETS:
        _, m, _ = build(k)
        allm[m["name"]] = m
    json.dump(allm, open(meta_path, "w"), indent=1, sort_keys=True)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    main([x for x in args if x in PETS])
