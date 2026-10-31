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

U = 0.13            # cube size in studs (BASE_U times the pet's SCALE while it builds)
BASE_U = U
# Bigger pets: same cube grid, bigger cubes.
SCALE = {"Dragon": 1.5, "Phoenix": 1.8, "Kitsune": 1.6, "AutumnStag": 1.4, "Peacock": 1.2, "Griffin": 1.6, "Dolphin": 1.3, "Shark": 1.4, "SeaSerpent": 1.6, "Bulldog": 1.1, "RoboPup": 1.2, "Gargoyle": 1.6, "SnowLeopard": 1.1, "Mammoth": 1.6, "FrostEagle": 1.5, "Yeti": 1.6, "ButterflyQueen": 1.5, "Kraken": 1.6, "MechaRex": 1.5, "AuroraWhale": 1.6, "DustBunny": 1.9, "Koi": 1.2, "Flamingo": 1.1, "RedPanda": 1.1, "MossGolem": 1.6, "Pegasus": 1.6, "Pelican": 1.2, "SeaTurtle": 1.2, "Walrus": 1.3, "MantaRay": 1.3, "Orca": 1.4, "Narwhal": 1.4, "CoralDragon": 1.6, "GoldenSeahorse": 1.5, "PoliceDog": 1.1, "CyberWolf": 1.2, "JetpackMonkey": 1.2, "NeonDragon": 1.5, "GoldenLion": 1.3, "MuskOx": 1.2, "PolarBear": 1.3, "FrostBat": 1.2, "WoollyRhino": 1.4, "CrystalStag": 1.4, "IceDragon": 1.6, "GlacierTitan": 1.8, "Capybara": 1.3, "Axolotl": 1.2, "Sloth": 1.4, "Chameleon": 1.2, "LuckyCat": 1.35}
FPS = 30
IDLE = (0, 90)      # frames
WALK = (120, 138)
RUN = (150, 162)
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
    def __init__(self, name, parent=None, joint=None, noise=True, glow=None):
        """glow: hex colour; the part turns Neon in that colour in game (eyes, horns)."""
        self.name, self.parent, self.noise, self.glow = name, parent, noise, glow
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

    def rbox(self, x0, x1, y0, y1, z0, z1, col, edges=(True, True, True)):
        """box() with the 12 edges trimmed off, for a rounder block. edges = which axes'
        edge rows to trim (x-running, y-running, z-running)."""
        def f(i, j, k):
            ex, ey, ez = i in (x0, x1 - 1), j in (y0, y1 - 1), k in (z0, z1 - 1)
            if (edges[0] and ey and ez) or (edges[1] and ex and ez) or (edges[2] and ex and ey):
                return None
            return col(i, j, k) if callable(col) else col
        return self.box(x0, x1, y0, y1, z0, z1, f)

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


def assemble(key, parts, name=None, kind="alien"):
    """The asset is Alien_<key> (the game's pet model name); its anims are Pet_<key>_Idle/_Walk.
    Field mobs pass name="Mob_<key>", kind="mob": their anims are Mob_<key>_<Anim>."""
    name = name or f"Alien_{key}"
    a = Asset(name, kind)
    for p in parts:
        o = mesh_part(a, p)
        j = p.joint if p.joint is not None else p.centre()
        a.parts[p.name] = {"obj": o, "parent": p.parent, "joint": [x * U for x in j] if p.parent else None,
                           "glow": p.glow, "material": None, "collide": False}
    if kind == "alien":
        a.extra["voxel"] = True
        a.extra["anims"] = {"idle": f"Pet_{key}_Idle", "walk": f"Pet_{key}_Walk"}
    else:
        a.extra["rig"] = True
        a.extra["anims"] = {k.lower(): f"{name}_{k}" for k in ANIMS[key]}
    return a


# ----------------------------------------------------------------------------- legs


def legs(col, paw, h, front_y, back_y, sock=None, sock_h=1, spread=0):
    """Four 2x2 legs, h cubes tall. front_y/back_y: the y of each pair's front cube.
    spread moves each side out by that many cubes (for wider bodies)."""
    out = []
    L, R = 1 + spread, -3 - spread
    for name, x0, y0 in (("LegFL", L, front_y), ("LegFR", R, front_y), ("LegBL", L, back_y), ("LegBR", R, back_y)):
        p = Part(name, "Body", joint=(x0 + 1, y0 + 1, h))
        s = sock if (sock and name.startswith("LegF")) else None
        p.box(x0, x0 + 2, y0, y0 + 2, 0, h, lambda i, j, k, s=s: paw if k == 0 else (s if s and k <= sock_h else col))
        out.append(p)
    return out


# ------------------------------------------------------------------------------ cat


def cat(key="Cat", O="F28A2E", S="C85F17", C="FBE3C2", P="FF9AB0", B="FFB7C5"):
    # orange, stripe, cream, pink, blush
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
    return assemble(key, parts)


# ------------------------------------------------------------------------------ dog


def dog(key="Dog", T="D98C45", C="FAEBD3", E="8A4E24", N="2A1C16", P="FF7A8E", saddle=None, spots=None, ears_up=False):
    # tan, cream, ear brown, nose, tongue
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
    for p in parts:
        for c, col in list(p.cells.items()):
            if col != T:
                continue
            if saddle and p.name in ("Body", "Tail") and c[2] >= 8 and c[1] > -6:
                p.cells[c] = saddle                          # dark back (shepherd)
            elif spots and (c[0] * 7 + c[1] * 5 + c[2] * 11) % 9 == 0:
                p.cells[c] = spots                           # spots (dalmatian)
    if ears_up:                                              # pointy upright ears
        parts = [p for p in parts if p.name not in ("EarL", "EarR")]
        ear = Part("EarL", "Head", joint=(2.5, -8.5, 15))
        for k, xs in ((15, (1, 2, 3)), (16, (1, 2, 3)), (17, (2, 3)), (18, (3,))):
            for x in xs:
                ear.cells[(x, -9, k)] = E
        parts += [ear, ear.mirror("EarR")]
    return assemble(key, parts)


def eyes(head, y, z, xs=(-3, 1), w=2, h=2, shine=True):
    """Square black eyes with a white shine pixel at the top outer corner (no shine on
    white faces, where it would read as a missing corner)."""
    for x0 in xs:
        head.box(x0, x0 + w, y, y + 1, z, z + h, EYE)
        if shine:
            head.set([(x0 if x0 < 0 else x0 + w - 1, y, z + h - 1)], SHINE)


# --------------------------------------------------------------------------- bunny


def bunny():
    W, G, P, N = "F4F1EC", "B8B2AB", "FFB3C6", "FF8FA8"     # white, grey patch, inner ear, nose
    parts = []
    for name, x0, y0, big in (("LegFL", 1, -4, False), ("LegFR", -3, -4, False), ("LegBL", 1, 2, True), ("LegBR", -3, 2, True)):
        p = Part(name, "Body", joint=(x0 + 1, y0 + 1, 3))
        p.box(x0, x0 + 2, y0, y0 + 2, 0, 3, W)
        if big:                                             # big back feet
            p.box(x0, x0 + 2, y0 - 2, y0, 0, 1, W)
        parts.append(p)
    body = Part("Body")
    body.rbox(-3, 3, -5, 5, 2, 8, lambda i, j, k: G if (k >= 6 and 0 <= j <= 3 and i >= -1) else W)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -5, 7))
    head.rbox(-4, 4, -10, -4, 6, 12, lambda i, j, k: G if (k >= 10 and i >= 1 and j >= -8) else W, edges=(True, False, True))
    eyes(head, -10, 9, shine=False)
    head.box(-2, 2, -11, -10, 7, 9, W)                     # muzzle
    head.set([(-1, -11, 8), (0, -11, 8)], N)
    head.set([(-3, -10, 8), (2, -10, 8)], P)              # blush
    parts.append(head)
    ear = Part("EarL", "Head", joint=(2, -7, 12))
    ear.box(1, 3, -8, -6, 12, 18, lambda i, j, k: P if (j == -8 and i == 1 and 13 <= k <= 16) else (G if k >= 17 else W))
    parts += [ear, ear.mirror("EarR")]
    tail = Part("Tail", "Body", joint=(0, 5, 5))
    tail.rbox(-1, 1, 5, 7, 4, 7, W, edges=(False, False, False))
    parts.append(tail)
    return assemble("Bunny", parts)


# ------------------------------------------------------------------------ squirrel


def squirrel():
    R, B, D, T = "B9582A", "F3D9B1", "7A3A18", "D98A55"     # red-brown, belly, dark, tail light
    parts = legs(R, D, 3, -4, 2)
    body = Part("Body")
    body.rbox(-3, 3, -5, 4, 3, 8, lambda i, j, k: B if (k == 3 or (j == -5 and k <= 6 and -2 <= i <= 1)) else R, edges=(True, False, False))
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -5, 7))
    head.box(-4, 4, -10, -4, 6, 12, lambda i, j, k: B if (j == -10 and k <= 7 and -3 <= i <= 2) else R)
    eyes(head, -10, 9)
    head.box(-2, 2, -11, -10, 7, 9, B)
    head.set([(-1, -11, 8), (0, -11, 8)], "3A2218")
    head.set([(-1, -11, 7), (0, -11, 7)], "FFFFFF")       # buck teeth
    parts.append(head)
    ear = Part("EarL", "Head", joint=(2.5, -6.5, 12))
    ear.box(2, 4, -7, -6, 12, 14, R)
    ear.set([(3, -7, 14)], D)                              # ear tuft
    parts += [ear, ear.mirror("EarR")]
    tail = Part("Tail", "Body", joint=(0, 4, 5))
    tail.box(-2, 2, 4, 7, 3, 9, lambda i, j, k: T if j == 6 and k % 2 else R)
    tail2 = Part("Tail2", "Tail", joint=(0, 6, 9))
    tail2.box(-2, 2, 5, 9, 9, 14, lambda i, j, k: T if j == 8 or k == 13 else R)
    tail2.box(-2, 2, 3, 6, 13, 15, lambda i, j, k: T if k == 14 else R)    # curl over the back
    parts += [tail, tail2]
    acorn = Part("Acorn", "Body", joint=(0, -6, 3), noise=False)     # held between the front paws
    acorn.box(-1, 1, -7, -5, 2, 4, "A8682E")
    acorn.box(-1, 1, -7, -5, 4, 5, "6B4220")
    parts.append(acorn)
    return assemble("Squirrel", parts)


# ------------------------------------------------------------------------- raccoon


def raccoon():
    G, L, M, D, N = "8F8C89", "E2DFDA", "45403D", "3A3634", "1E1A18"   # grey, light, mask, dark, nose
    parts = legs(G, D, 4, -5, 3)
    for p in parts:
        for c in list(p.cells):
            if c[2] <= 1:
                p.cells[c] = D                             # dark paws
    body = Part("Body")
    body.box(-3, 3, -6, 6, 4, 9, lambda i, j, k: L if k == 4 and -4 <= j <= 3 else (shade(G, -0.12) if k == 8 else G))
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -6, 8))

    def hcol(i, j, k):
        if j == -11:
            if 9 <= k <= 11 and i not in (-1, 0):
                return M                                   # the mask
            if k == 12 and i in (-3, -2, 1, 2):
                return L                                   # white brows
            if k <= 8:
                return L
        return G
    head.box(-4, 4, -11, -5, 7, 14, hcol)
    eyes(head, -11, 10)
    head.box(-2, 2, -13, -11, 7, 9, L)                     # snout
    head.set([(-1, -13, 8), (0, -13, 8)], N)
    parts.append(head)
    ear = Part("EarL", "Head", joint=(3, -7.5, 14))
    ear.box(2, 4, -8, -7, 14, 16, lambda i, j, k: L if k == 15 else G)
    ear.set([(2, -8, 14)], M)
    parts += [ear, ear.mirror("EarR")]
    ring = lambda i, j, k: D if j % 2 else G             # noqa: E731
    tail = Part("Tail", "Body", joint=(0, 6, 7))
    tail.box(-1, 1, 6, 10, 6, 8, ring)
    tail.box(-2, 2, 7, 10, 6, 8, lambda i, j, k: ring(i, j, k) if abs(i + 0.5) < 2 else None)
    tail2 = Part("Tail2", "Tail", joint=(0, 10, 7))
    tail2.box(-2, 2, 10, 14, 5, 8, lambda i, j, k: None if (i in (-2, 1) and k in (5, 7)) else (D if j >= 13 else ring(i, j, k)))
    parts += [tail, tail2]
    return assemble("Raccoon", parts)


# ---------------------------------------------------------------------------- duck


def duck():
    Y, O, LY = "FFD43B", "FF8A1F", "FFE680"
    parts = []
    leg = Part("LegL", "Body", joint=(1.5, -0.5, 3))
    leg.box(1, 2, -1, 0, 1, 3, O)
    leg.box(0, 3, -3, 0, 0, 1, O)                          # webbed foot
    parts += [leg, leg.mirror("LegR")]
    body = Part("Body")
    body.rbox(-4, 4, -4, 5, 2, 9, lambda i, j, k: LY if (j == -4 or k == 2) else Y)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -2, 9))
    head.rbox(-3, 3, -5, 1, 9, 15, Y, edges=(True, False, True))
    eyes(head, -5, 12, xs=(-2, 1), w=1, h=2)
    head.box(-1, 1, -3, -1, 15, 16, Y)                     # hair tuft
    head.set([(0, -2, 16)], Y)
    parts.append(head)
    bill = Part("Bill", "Head", joint=(0, -5, 11), noise=False)
    bill.box(-2, 2, -7, -5, 11, 12, O)
    bill.box(-2, 2, -7, -5, 10, 11, shade(O, -0.15))
    parts.append(bill)
    wing = Part("WingL", "Body", joint=(4, -1, 8))
    wing.box(4, 5, -2, 4, 4, 8, lambda i, j, k: shade(Y, -0.08) if j >= 2 and k <= 5 else LY)
    parts += [wing, wing.mirror("WingR")]
    tail = Part("Tail", "Body", joint=(0, 5, 7))
    tail.box(-1, 1, 5, 6, 7, 9, Y)
    tail.set([(-1, 6, 8), (0, 6, 8)], Y)
    parts.append(tail)
    return assemble("Duck", parts)


# ----------------------------------------------------------------------------- fox


def fox(key="Fox", O="E8742A", W="F7F1E8", D="2B2220"):
    parts = legs(O, D, 4, -5, 3)
    for p in parts:
        for c in list(p.cells):
            if c[2] <= 1:
                p.cells[c] = D                              # black socks
    body = Part("Body")
    body.box(-3, 3, -6, 6, 4, 9, lambda i, j, k: W if (k == 4 and -5 <= j <= 3) or (j == -6 and k <= 7 and -2 <= i <= 1) else O)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -6, 8))
    head.box(-4, 4, -11, -5, 7, 13, lambda i, j, k: W if j == -11 and k <= 8 and i in (-4, -3, 2, 3) else O)
    eyes(head, -11, 9)
    head.box(-2, 2, -14, -11, 7, 9, lambda i, j, k: O if k == 8 and abs(i + 0.5) < 1 else W)   # snout
    head.set([(-1, -14, 8), (0, -14, 8)], D)
    parts.append(head)
    ear = Part("EarL", "Head", joint=(2.5, -7.5, 13))
    for k, xs in ((13, (1, 2, 3)), (14, (2, 3)), (15, (3,))):
        for x in xs:
            ear.cells[(x, -8, k)] = D if k == 15 else (W if (k == 13 and x == 2) else O)
    parts += [ear, ear.mirror("EarR")]
    tail = Part("Tail", "Body", joint=(0, 6, 7))
    tail.box(-1, 1, 6, 9, 6, 9, O)
    tail2 = Part("Tail2", "Tail", joint=(0, 9, 7))
    tail2.rbox(-2, 2, 8, 13, 5, 10, lambda i, j, k: W if j >= 11 else O, edges=(True, False, True))
    parts += [tail, tail2]
    return assemble(key, parts)


# -------------------------------------------------------------------------- turtle


def turtle():
    G, S, P, R, Y = "7CC46A", "4F7F33", "8DB45A", "C9B06A", "E9D89A"   # skin, shell, plate, rim, belly
    parts = []
    for name, x0, y0 in (("LegFL", 3, -5), ("LegFR", -5, -5), ("LegBL", 3, 3), ("LegBR", -5, 3)):
        p = Part(name, "Body", joint=(x0 + 1, y0 + 1, 2))
        p.box(x0, x0 + 2, y0, y0 + 2, 0, 2, G)
        parts.append(p)

    def shell(i, j, k):
        if k == 2:
            return Y
        if k == 3:
            return R
        if (i % 3 == 0) or (j % 3 == 0):
            return S
        return P
    body = Part("Body")
    body.rbox(-5, 5, -6, 6, 2, 7, shell)
    body.rbox(-3, 3, -4, 4, 7, 8, lambda i, j, k: S if (i % 3 == 0 or j % 3 == 0) else P, edges=(False, False, True))
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -6, 4))
    head.rbox(-3, 3, -10, -5, 3, 8, G, edges=(True, False, False))
    eyes(head, -10, 5, xs=(-2, 1), w=1, h=2)
    head.set([(-1, -10, 4), (0, -10, 4)], shade(G, -0.35))     # smile
    parts.append(head)
    tail = Part("Tail", "Body", joint=(0, 6, 3))
    tail.box(-1, 1, 6, 8, 3, 4, G)
    parts.append(tail)
    return assemble("Turtle", parts)


# ------------------------------------------------------------------------- penguin


def penguin():
    B, W, Y, O = "26282E", "F4F4F0", "FFC93C", "FF8A1F"
    parts = []
    foot = Part("LegL", "Body", joint=(2, -1, 1))
    foot.box(1, 3, -3, 0, 0, 1, O)
    parts += [foot, foot.mirror("LegR")]
    body = Part("Body")
    body.rbox(-4, 4, -3, 4, 1, 12, lambda i, j, k: W if (j == -3 and -3 <= i <= 2 and 2 <= k <= 9) else B)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, 0, 12))

    def hcol(i, j, k):
        if j == -3 and -2 <= i <= 1 and 12 <= k <= 14:
            return W
        if j == -3 and i in (-3, 2) and k == 12:
            return Y                                        # yellow cheeks
        return B
    head.rbox(-3, 3, -3, 3, 12, 17, hcol)
    eyes(head, -3, 14, xs=(-2, 1), w=1, h=2)
    head.box(-1, 1, -5, -3, 13, 14, O)                     # beak
    parts.append(head)
    wing = Part("WingL", "Body", joint=(4, 0.5, 10))
    wing.box(4, 5, -1, 2, 4, 10, B)
    parts += [wing, wing.mirror("WingR")]
    tail = Part("Tail", "Body", joint=(0, 4, 2))
    tail.box(-1, 1, 4, 5, 1, 3, B)
    parts.append(tail)
    return assemble("Penguin", parts)


# --------------------------------------------------------------------------- panda


def panda():
    W, K, G, GD = "F2F2EE", "232326", "6DBE45", "3F8A2A"
    parts = legs(K, K, 4, -6, 4, spread=1)
    body = Part("Body")
    body.rbox(-4, 4, -7, 7, 4, 11, lambda i, j, k: K if -5 <= j <= -2 else W)    # black shoulder band
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -7, 10))
    head.rbox(-5, 5, -13, -6, 9, 17, W)
    for x0 in (-4, 2):                                       # eye patches, tilted
        head.box(x0, x0 + 2, -13, -12, 11, 14, K)
        head.set([(x0 + (1 if x0 < 0 else 0), -13, 10)], K)
    head.set([(-3, -13, 13), (2, -13, 13)], SHINE)
    head.set([(-3, -13, 12), (2, -13, 12)], EYE)
    head.box(-2, 2, -14, -13, 9, 11, W)                      # muzzle
    head.set([(-1, -14, 10), (0, -14, 10)], K)
    parts.append(head)
    ear = Part("EarL", "Head", joint=(3.5, -9.5, 17))
    ear.box(2, 5, -10, -9, 17, 19, K)
    parts += [ear, ear.mirror("EarR")]
    bamboo = Part("Bamboo", "Head", joint=(0, -14, 9), noise=False)
    bamboo.box(-6, 6, -15, -14, 9, 10, lambda i, j, k: GD if i in (-3, 2) else G)
    bamboo.box(5, 7, -15, -14, 10, 11, "8FD86A")             # leaf
    parts.append(bamboo)
    tail = Part("Tail", "Body", joint=(0, 7, 9))
    tail.box(-1, 1, 7, 8, 8, 10, W)
    parts.append(tail)
    return assemble("Panda", parts)


# ----------------------------------------------------------------------------- owl


def owl():
    W, G, Y, B, O = "F3F3F7", "C9CBD8", "FFD23F", "E7A93A", "D88A2A"
    parts = []
    foot = Part("LegL", "Body", joint=(2, -1, 2))
    foot.box(1, 3, -3, 0, 0, 1, O)
    foot.box(1, 3, -1, 0, 1, 2, O)
    parts += [foot, foot.mirror("LegR")]
    speck = lambda i, j, k: G if (i * 3 + j * 5 + k * 7) % 11 == 0 else W     # noqa: E731
    body = Part("Body")
    body.rbox(-4, 4, -3, 4, 2, 11, speck)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, 0, 11))
    head.rbox(-4, 4, -3, 4, 11, 17, speck)
    for x0 in (-4, 0):                                       # big yellow eyes, 4x4
        head.box(x0, x0 + 4, -4, -3, 12, 16, lambda i, j, k, x0=x0: None if (i - x0 in (0, 3) and k in (12, 15)) else Y)
        px = x0 + 1
        head.box(px, px + 2, -4, -3, 13, 15, EYE)
        head.set([(px if x0 < 0 else px + 1, -4, 14)], SHINE)
    head.box(-1, 1, -5, -3, 11, 12, B)                       # beak
    head.set([(-1, -4, 12), (0, -4, 12)], B)
    parts.append(head)
    ear = Part("EarL", "Head", joint=(2.5, 0.5, 17))
    ear.box(2, 4, 0, 1, 17, 18, G)
    ear.set([(3, 0, 18)], G)
    parts += [ear, ear.mirror("EarR")]
    wing = Part("WingL", "Body", joint=(4, 0.5, 10))
    wing.box(4, 5, -2, 3, 4, 10, lambda i, j, k: G if (j + k) % 3 == 0 else W)
    parts += [wing, wing.mirror("WingR")]
    tail = Part("Tail", "Body", joint=(0, 4, 3))
    tail.box(-2, 2, 4, 5, 2, 5, lambda i, j, k: G if k == 2 else W)
    parts.append(tail)
    a = assemble("Owl", parts)
    a.extra["float"] = True
    return a


# --------------------------------------------------------------------------- tiger


def tiger():
    O, K, W, N = "F08A24", "1E1A18", "F8F1E4", "C8545A"
    parts = legs(O, W, 5, -7, 5)
    for p in parts:
        for c in list(p.cells):
            if c[2] in (2, 3) and (c[1] % 2 == 0):
                p.cells[c] = K                               # leg stripes
    body = Part("Body")
    body.box(-3, 3, -8, 8, 5, 10, lambda i, j, k:
             W if (k == 5 and -6 <= j <= 5) or (j == -8 and k <= 7 and -2 <= i <= 1)
             else K if (j % 3 == 0 and k >= 7 and abs(i + 0.5) < 2.6 and (k == 9 or abs(i + 0.5) > 1.6)) else O)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -8, 9))

    def hcol(i, j, k):
        if j == -13 and k <= 9 and i in (-4, -3, 2, 3):
            return W                                       # white cheeks
        if k == 14 and i in (-2, 1) and j <= -10:
            return K                                       # forehead stripes
        if k == 13 and i in (-1, 0) and j == -13:
            return K
        if i in (-4, 3) and j in (-11, -9) and k >= 10:
            return K                                       # side stripes
        return O
    head.box(-4, 4, -13, -7, 8, 15, hcol)
    eyes(head, -13, 11)
    head.box(-2, 2, -15, -13, 8, 11, W)                      # muzzle
    head.set([(-1, -15, 10), (0, -15, 10)], N)
    head.set([(-1, -15, 8), (0, -15, 8)], K)
    parts.append(head)
    ear = Part("EarL", "Head", joint=(3, -10.5, 15))
    ear.box(2, 4, -11, -10, 15, 17, lambda i, j, k: W if (k == 15 and i == 2) else O)
    ear.set([(2, -10, 15), (3, -10, 15), (2, -10, 16), (3, -10, 16)], K)    # black backs
    parts += [ear, ear.mirror("EarR")]
    stripe = lambda i, j, k: K if j % 2 == 0 else O        # noqa: E731
    tail = Part("Tail", "Body", joint=(0, 8, 8))
    tail.box(-1, 1, 8, 12, 7, 9, stripe)
    tail2 = Part("Tail2", "Tail", joint=(0, 12, 8))
    tail2.box(-1, 1, 12, 14, 7, 9, stripe)
    tail2.box(-1, 1, 13, 15, 9, 12, lambda i, j, k: K if k >= 11 or k == 10 else O)
    parts += [tail, tail2]
    return assemble("Tiger", parts)


# ---------------------------------------------------------------------------- lion


def lion(key="Lion", G="E8A93A", M="A0581E", MD="7A3E14", L="F6DFB0", N="4A2A20"):
    parts = legs(G, L, 5, -7, 5)
    body = Part("Body")
    body.box(-3, 3, -8, 8, 5, 11, lambda i, j, k: L if k == 5 and -6 <= j <= 5 else G)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -8, 10))
    head.rbox(-6, 6, -12, -6, 7, 19, lambda i, j, k: MD if (i + k) % 4 == 0 else M)    # the mane
    for c in [c for c in head.cells if -4 <= c[0] < 4 and 9 <= c[2] < 16 and c[1] == -12]:
        del head.cells[c]
    head.box(-4, 4, -14, -11, 9, 16, G)                       # face
    eyes(head, -14, 12)
    head.box(-2, 2, -15, -14, 9, 12, L)                       # muzzle
    head.set([(-1, -15, 11), (0, -15, 11)], N)
    head.set([(-1, -15, 9), (0, -15, 9)], shade(L, -0.25))
    parts.append(head)
    ear = Part("EarL", "Head", joint=(3.5, -10.5, 19))
    ear.box(3, 5, -11, -10, 19, 20, G)
    parts += [ear, ear.mirror("EarR")]
    tail = Part("Tail", "Body", joint=(0, 8, 9))
    tail.box(-1, 1, 8, 12, 8, 10, G)
    tail2 = Part("Tail2", "Tail", joint=(0, 12, 9))
    tail2.box(-1, 1, 12, 15, 7, 9, G)
    tail2.rbox(-2, 2, 14, 17, 5, 9, lambda i, j, k: MD if k == 5 else M, edges=(True, False, True))   # tuft
    parts += [tail, tail2]
    return assemble(key, parts)


# ---------------------------------------------------------------------- arctic wolf


def arctic_wolf(key="ArcticWolf", W="DCE6F0", G="AEBFD3", B="F8FBFF", N="2A2E38", I="6FE6FF"):
    parts = legs(W, G, 6, -8, 6)
    body = Part("Body")
    body.box(-3, 3, -9, 9, 6, 12, lambda i, j, k: B if (k == 6 and -7 <= j <= 6) or (j == -9 and k <= 9 and -2 <= i <= 1) else (G if k == 11 and abs(i + 0.5) < 2 else W))
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -9, 11))
    head.box(-4, 4, -15, -9, 10, 17, lambda i, j, k: G if k == 16 else W)
    head.box(-2, 2, -18, -15, 10, 13, lambda i, j, k: B if k < 12 else W)    # long snout
    head.set([(-1, -18, 12), (0, -18, 12), (-1, -17, 12), (0, -17, 12)], N)
    eye_cells = [(x, -15, z) for x in (-3, -2, 1, 2) for z in (13, 14)]
    for c in eye_cells:
        head.cells.pop(c, None)
    parts.append(head)
    glow = Part("Eyes_Glow", "Head", joint=(0, -15, 13.5), noise=False, glow=I)
    glow.set(eye_cells, I)
    parts.append(glow)
    ear = Part("EarL", "Head", joint=(3, -11.5, 17))
    ear.box(2, 4, -12, -11, 17, 19, lambda i, j, k: G if i == 3 or k == 18 else W)
    ear.set([(3, -12, 19)], G)
    parts += [ear, ear.mirror("EarR")]
    tail = Part("Tail", "Body", joint=(0, 9, 10))
    tail.box(-1, 1, 9, 12, 9, 12, W)
    tail2 = Part("Tail2", "Tail", joint=(0, 12, 9))
    tail2.rbox(-2, 2, 11, 16, 6, 11, lambda i, j, k: B if j >= 14 else W, edges=(True, False, True))
    parts += [tail, tail2]
    return assemble(key, parts)


# ------------------------------------------------------------------------- unicorn


RAINBOW_BANDS = ["FF6B7A", "FFA24A", "FFE15A", "7EE07A", "6AB8FF", "B98BFF"]


def unicorn():
    W, H, S, P = "FAF8FF", "C8B8E8", "F5D6E8", "E58FB4"
    parts = legs(W, H, 7, -7, 5)
    for p in parts:
        for c in list(p.cells):
            if c[2] <= 1:
                p.cells[c] = H                               # hooves
    body = Part("Body")
    body.rbox(-3, 3, -8, 8, 7, 13, W)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -7, 12))
    head.box(-2, 2, -9, -5, 11, 17, W)                       # neck
    head.rbox(-3, 3, -13, -7, 16, 21, W, edges=(True, False, False))
    head.box(-2, 2, -15, -13, 16, 19, S)                      # muzzle
    head.set([(-2, -15, 17), (1, -15, 17)], P)                # nostrils
    eyes(head, -13, 19, xs=(-3, 1), shine=False)
    parts.append(head)
    horn = Part("Horn_Glow", "Head", joint=(0, -10, 21), noise=False, glow="FFD54A")
    horn.box(-1, 1, -11, -9, 21, 22, "FFD54A")
    horn.box(-1, 0, -11, -10, 22, 25, "FFD54A")
    parts.append(horn)
    mane = Part("Mane", "Head", joint=(0, -6, 17))
    mane.box(-1, 1, -8, -4, 12, 22, lambda i, j, k: None if (j == -8 and k < 20) else RAINBOW_BANDS[(k + j) % 6])
    parts.append(mane)
    ear = Part("EarL", "Head", joint=(2, -8.5, 21))
    ear.box(1, 3, -9, -8, 21, 23, lambda i, j, k: P if (i == 1 and k == 21) else W)
    parts += [ear, ear.mirror("EarR")]
    tail = Part("Tail", "Body", joint=(0, 8, 11))
    tail.box(-1, 1, 8, 10, 9, 13, lambda i, j, k: RAINBOW_BANDS[k % 6])
    tail2 = Part("Tail2", "Tail", joint=(0, 9.5, 9))
    tail2.box(-1, 1, 9, 12, 4, 10, lambda i, j, k: RAINBOW_BANDS[k % 6])
    parts += [tail, tail2]
    return assemble("Unicorn", parts)


# --------------------------------------------------------------------------- dragon


def dragon(key="Dragon", R="D8342C", D="8E1C18", B="FFC36A", C="F4E6C8", M="FF7A3A", aura="Embers"):
    parts = legs(R, C, 5, -7, 5)
    body = Part("Body")
    body.box(-3, 3, -8, 8, 5, 11, lambda i, j, k: B if (k == 5 and -6 <= j <= 5) or (j == -8 and k <= 9 and -2 <= i <= 1) else R)
    for j in range(-6, 8, 3):                                # back spikes
        body.set([(-1, j, 11), (0, j, 11)], C)
        body.set([(-1, j + 1, 11), (0, j + 1, 11)], C)
        body.set([(-1, j, 12), (0, j, 12)], C)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -8, 10))
    head.box(-4, 4, -14, -8, 9, 15, R)
    head.box(-3, 3, -17, -14, 9, 12, lambda i, j, k: B if k == 9 else R)       # snout
    head.set([(-2, -17, 11), (1, -17, 11)], D)              # nostrils
    head.set([(-3, -17, 9), (2, -17, 9), (-3, -16, 9), (2, -16, 9)], "FFFFFF")  # little fangs
    eyes(head, -14, 12)
    for x in (-4, 3):                                         # horns sweeping back
        head.set([(x, -11, 15), (x, -10, 15), (x, -10, 16), (x, -9, 16), (x, -9, 17), (x, -8, 17), (x, -8, 18)], C)
    parts.append(head)
    wing = Part("WingL", "Body", joint=(3, -3, 10))
    for d in range(7):
        for j in range(-6, -6 + 9 - d):
            bone = j == -6 or d in (0, 3, 6)
            wing.cells[(3 + d, j, 10 + (1 if d >= 4 else 0) + (1 if d == 6 else 0))] = D if bone else M
    parts += [wing, wing.mirror("WingR")]
    tail = Part("Tail", "Body", joint=(0, 8, 8))
    tail.box(-1, 1, 8, 12, 7, 9, R)
    tail2 = Part("Tail2", "Tail", joint=(0, 12, 8))
    tail2.box(-1, 1, 12, 16, 6, 8, lambda i, j, k: C if k == 7 and j % 2 == 0 else R)
    tail2.box(-2, 2, 16, 18, 6, 8, D)                        # spade tip
    tail2.set([(-1, 18, 6), (0, 18, 6), (-1, 18, 7), (0, 18, 7)], D)
    parts += [tail, tail2]
    a = assemble(key, parts)
    a.extra["aura"] = aura
    a.extra["float"] = True
    return a


# -------------------------------------------------------------------------- phoenix


def phoenix():
    O, G, R, Y = "FF7A1A", "FFC23A", "E8361E", "FFE07A"
    parts = []
    leg = Part("LegL", "Body", joint=(1.5, 0.5, 3))
    leg.box(1, 2, 0, 1, 1, 3, G)
    leg.box(1, 3, -1, 1, 0, 1, G)
    parts += [leg, leg.mirror("LegR")]
    body = Part("Body")
    body.rbox(-3, 3, -3, 5, 3, 10, lambda i, j, k: G if (j == -3 and k <= 7) else (R if k == 3 else O))
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -2, 9))
    head.rbox(-3, 3, -6, 0, 9, 14, O, edges=(True, False, True))
    eyes(head, -6, 11, xs=(-2, 1), w=1, h=2)
    head.box(-1, 1, -8, -6, 10, 12, lambda i, j, k: G if k == 11 else shade(G, -0.25))    # beak
    parts.append(head)
    crest = Part("Crest_Glow", "Head", joint=(0, -3, 14), noise=False, glow=Y)
    crest.set([(0, -3, 14), (0, -3, 15), (0, -2, 16), (-1, -2, 14), (-1, -1, 15), (-1, 0, 16), (0, -1, 17)], Y)
    parts.append(crest)
    wing = Part("WingL", "Body", joint=(3, 0, 8))
    for d in range(9):
        for j in range(-2, 5 - d // 2):
            wing.cells[(3 + d, j, 8 + d // 3)] = R if (d >= 6 or j == 5 - d // 2 - 1) else (G if d == 0 else O)
    parts += [wing, wing.mirror("WingR")]
    tail = Part("Tail_Glow", "Body", joint=(0, 5, 5), noise=False, glow="FF9A2A")
    for t in range(7):                                       # flame feathers streaming back and down
        y, z = 5 + t, 5 - t // 2
        for x in (-1, 0):
            tail.cells[(x, y, z)] = O
        if t >= 3:
            tail.cells[(-2, y, z - 1)] = O
            tail.cells[(1, y, z - 1)] = O
    parts.append(tail)
    a = assemble("Phoenix", parts)
    a.extra["float"] = True
    a.extra["aura"] = "PhoenixFlame"
    return a


# -------------------------------------------------------------------------- kitsune


def kitsune():
    W, G, R, P = "F8F6F2", "F2C14E", "E0454E", "FFB3C6"
    parts = legs(W, G, 4, -5, 3)
    body = Part("Body")
    body.box(-3, 3, -6, 6, 4, 9, lambda i, j, k: G if (k == 8 and i in (-1, 0) and j % 4 == 0) else W)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -6, 8))
    head.box(-4, 4, -11, -5, 7, 13, W)
    eyes(head, -11, 10, h=1, shine=False)                   # calm, narrow eyes
    head.set([(-3, -11, 11), (-4, -11, 11), (2, -11, 11), (3, -11, 11)], R)    # red eye markings
    head.set([(-1, -11, 12), (0, -11, 12)], R)
    head.box(-2, 2, -14, -11, 7, 9, W)
    head.set([(-1, -14, 8), (0, -14, 8)], "2B2220")
    parts.append(head)
    ear = Part("EarL", "Head", joint=(2.5, -7.5, 13))
    for k, xs in ((13, (1, 2, 3)), (14, (2, 3)), (15, (3,)), (16, (3,))):
        for x in xs:
            ear.cells[(x, -8, k)] = G if k >= 15 else (P if (k == 13 and x == 2) else W)
    parts += [ear, ear.mirror("EarR")]
    # Nine tails fanned out behind, each its own part so they can wave one after another.
    for n in range(9):
        ang = math.radians(-72 + n * 18)
        t = Part(f"Tail{n + 1}", "Body", joint=(0, 6, 7))
        for step in range(8):
            r = step * 0.9
            x = round(math.sin(ang) * r * 0.9)
            z = 7 + round(math.cos(ang) * r)
            y = 6 + round(step * 0.55)
            col = G if step >= 6 else W
            for dx in (-1, 0):
                t.cells[(x + dx, y, z)] = col
            if 2 <= step <= 5:
                t.cells[(x + (1 if x >= 0 else -2), y, z)] = col
        parts.append(t)
    a = assemble("Kitsune", parts)
    a.extra["aura"] = "FoxFire"
    a.extra["float"] = True
    return a


# ---------------------------------------------------------------------- autumn stag


LEAVES = ["E8742A", "D8452C", "F2B33A", "B8562A", "F0943A"]


def leafy(i, j, k):
    """A patchwork of autumn leaf colours, in 2x2 clumps."""
    h = ((i // 2) * 73856093) ^ ((j // 2) * 19349663) ^ ((k // 2) * 83492791)
    return LEAVES[h % len(LEAVES)]


def autumn_stag():
    W, H, T, N = "8A5A30", "3E2A1A", "C8955A", "2A1C16"
    parts = legs(W, H, 8, -8, 6)
    for p in parts:
        for c in list(p.cells):
            if c[2] >= 6:
                p.cells[c] = leafy(*c)                        # leaves creep down the legs
    body = Part("Body")
    body.rbox(-3, 3, -9, 9, 8, 14, leafy, edges=(True, False, False))
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -8, 13))
    head.box(-2, 2, -10, -6, 12, 18, leafy)                   # neck
    head.rbox(-3, 3, -14, -9, 17, 22, lambda i, j, k: T if j == -14 else leafy(i, j, k), edges=(True, False, False))
    head.box(-2, 2, -16, -14, 17, 20, T)                      # muzzle
    head.set([(-1, -16, 19), (0, -16, 19)], N)
    eye_cells = [(x, -14, z) for x in (-3, -2, 1, 2) for z in (20,)]
    for c in eye_cells:
        head.cells.pop(c, None)
    parts.append(head)
    glow = Part("Eyes_Glow", "Head", joint=(0, -14, 20), noise=False, glow="FFE07A")
    glow.set(eye_cells, "FFE07A")
    parts.append(glow)
    antlers = Part("Antlers", "Head", joint=(0, -11, 22))
    for side in (-1, 1):
        def put(x, y, z, col=W):
            antlers.cells[(x if side > 0 else -1 - x, y, z)] = col
        for t in range(9):                                    # main beam: up and out
            put(1 + t // 2, -11 + t // 4, 22 + t)
        for t in range(4):                                    # front tines
            put(2 + t // 3, -12 - t, 25 + t // 2)
            put(4 + t // 3, -11 - t, 28 + t // 2)
        for (x0, y0, z0) in ((5, -9, 30), (3, -15, 26), (5, -14, 29)):   # leaf clumps on the tips
            for dx in (0, 1):
                for dy in (0, 1):
                    for dz in (0, 1):
                        put(x0 + dx, y0 + dy, z0 + dz, leafy(x0 + dx, y0 + dy, z0 + dz))
    parts.append(antlers)
    ear = Part("EarL", "Head", joint=(3, -10.5, 21))
    ear.box(3, 5, -11, -10, 20, 22, T)
    parts += [ear, ear.mirror("EarR")]
    tail = Part("Tail", "Body", joint=(0, 9, 12))
    tail.box(-1, 1, 9, 11, 11, 13, "F6E6C8")
    parts.append(tail)
    a = assemble("AutumnStag", parts)
    a.extra["aura"] = "Leaves"
    return a


# ===================================================================== zone: Park


def hedgehog():
    S, SD, C, N = "8C6440", "5E4128", "F1D9B5", "2A1C16"
    parts = legs(C, shade(C, -0.2), 2, -4, 2)
    body = Part("Body")
    body.rbox(-4, 4, -5, 5, 2, 8, lambda i, j, k: C if (k == 2 or (j == -5 and k <= 4)) else (SD if (i + j + k) % 2 else S))
    for i in range(-4, 4):                                   # spikes poking up and out
        for j in range(-4, 5):
            if (i + j) % 2 == 0:
                body.cells[(i, j, 8)] = SD
    for j in range(-3, 5, 2):
        body.cells[(-5, j, 5)] = SD
        body.cells[(4, j, 5)] = SD
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -5, 4))
    head.rbox(-3, 3, -9, -4, 2, 7, C)
    head.box(-1, 1, -11, -9, 3, 5, C)                         # pointy snout
    head.set([(-1, -11, 4), (0, -11, 4)], N)
    eyes(head, -9, 5, xs=(-2, 1), w=1, h=1)
    parts.append(head)
    ear = Part("EarL", "Head", joint=(2, -5.5, 7))
    ear.set([(2, -6, 7)], C)
    parts += [ear, ear.mirror("EarR")]
    return assemble("Hedgehog", parts)


def frog():
    G, B, D, W = "6CC24A", "D8F0A0", "3E8A2E", "FFFFFF"
    parts = []
    for name, x0, side in (("LegBL", 3, 1), ("LegBR", -6, -1)):
        p = Part(name, "Body", joint=(x0 + 1.5, 2, 3))
        p.box(x0, x0 + 3, 0, 5, 0, 3, lambda i, j, k: D if (i + j) % 3 == 0 else G)
        parts.append(p)
    for name, x0 in (("LegFL", 2), ("LegFR", -4)):
        p = Part(name, "Body", joint=(x0 + 1, -4, 2))
        p.box(x0, x0 + 2, -5, -3, 0, 2, G)
        parts.append(p)
    body = Part("Body")
    body.rbox(-4, 4, -5, 4, 1, 6, lambda i, j, k: B if (k == 1 or j == -5) else (D if (i * 2 + j + k) % 5 == 0 else G))
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -3, 5))
    head.rbox(-4, 4, -7, -2, 4, 8, lambda i, j, k: B if k == 4 else G, edges=(True, False, True))
    head.box(-3, 3, -8, -7, 5, 6, D)                          # wide smile
    for x0 in (-4, 2):                                        # eye bumps on top
        head.box(x0, x0 + 2, -6, -4, 8, 10, W)
        head.box(x0, x0 + 2, -7, -6, 8, 10, EYE)
        head.set([(x0 if x0 < 0 else x0 + 1, -7, 9)], SHINE)
    parts.append(head)
    return assemble("Frog", parts)


def swan():
    W, O, K, G = "F7F7F4", "FF8A2A", "26262A", "5E5E66"
    parts = []
    leg = Part("LegL", "Body", joint=(2, -0.5, 2))
    leg.box(2, 3, -1, 0, 0, 2, G)
    leg.box(1, 4, -3, 0, 0, 1, G)
    parts += [leg, leg.mirror("LegR")]
    body = Part("Body")
    body.rbox(-4, 4, -5, 6, 2, 8, W)
    body.box(-2, 2, 6, 8, 6, 9, W)                            # tail up
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -5, 7))
    head.box(-1, 1, -6, -4, 7, 14, W)                         # long neck
    head.rbox(-2, 2, -8, -4, 14, 17, W, edges=(False, False, True))
    head.box(-1, 1, -11, -8, 14, 16, lambda i, j, k: K if j == -8 else (shade(O, -0.15) if k == 14 else O))   # beak
    eyes(head, -8, 16, xs=(-2, 1), w=1, h=1)
    parts.append(head)
    wing = Part("WingL", "Body", joint=(4, 0, 7))
    wing.box(4, 5, -3, 6, 3, 8, lambda i, j, k: shade(W, -0.06) if (j + k) % 3 == 0 else W)
    parts += [wing, wing.mirror("WingR")]
    return assemble("Swan", parts)


def beaver():
    B, D, L, T, N = "8B5A2B", "5E3A1C", "C89A62", "3A2A20", "201410"
    parts = legs(D, D, 2, -5, 2, spread=1)
    body = Part("Body")
    body.rbox(-4, 4, -6, 5, 2, 9, lambda i, j, k: L if (j == -6 and k <= 6 and -2 <= i <= 1) else B)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -6, 7))
    head.rbox(-4, 4, -11, -5, 5, 11, B, edges=(True, False, True))
    head.box(-2, 2, -12, -11, 5, 8, L)                        # muzzle
    head.set([(-1, -12, 7), (0, -12, 7)], N)
    head.set([(-1, -12, 5), (0, -12, 5), (-1, -12, 4), (0, -12, 4)], "FFF6E0")   # big teeth
    eyes(head, -11, 8)
    parts.append(head)
    ear = Part("EarL", "Head", joint=(3, -7.5, 11))
    ear.set([(3, -8, 11), (2, -8, 11)], D)
    parts += [ear, ear.mirror("EarR")]
    tail = Part("Tail", "Body", joint=(0, 5, 3))
    tail.box(-3, 3, 5, 12, 2, 3, lambda i, j, k: shade(T, 0.18) if (i + j) % 2 else T)   # flat paddle
    parts.append(tail)
    return assemble("Beaver", parts)


def peacock():
    B, T, G, Y, K, GR = "1F5FD0", "2AA6A0", "2E9E5A", "F2C14E", "1A2A6A", "8A8A92"
    parts = []
    leg = Part("LegL", "Body", joint=(1.5, 0.5, 4))
    leg.box(1, 2, 0, 1, 1, 4, GR)
    leg.box(1, 3, -1, 1, 0, 1, GR)
    parts += [leg, leg.mirror("LegR")]
    body = Part("Body")
    body.rbox(-3, 3, -3, 4, 4, 10, B)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -2, 9))
    head.box(-1, 1, -4, -2, 9, 14, T)                         # neck
    head.rbox(-2, 2, -5, -1, 14, 17, B, edges=(False, False, True))
    head.box(-1, 1, -7, -5, 15, 16, "C8B08A")                 # beak
    eyes(head, -5, 16, xs=(-2, 1), w=1, h=1)
    for x in (-1, 0, 1):                                      # crest
        head.set([(x if x < 1 else 0, -2, 17 + (x % 2)), (x if x < 1 else 0, -2, 18 + (x % 2))], T)
        head.set([(x if x < 1 else 0, -2, 19 + (x % 2))], Y)
    parts.append(head)
    fan = Part("Tail", "Body", joint=(0, 4, 8))
    R = 12
    for i in range(-R, R + 1):                                # the big fan behind it
        for k in range(0, R + 1):
            d = (i * i + k * k) ** 0.5
            if d <= R:
                x = i
                z = 7 + k
                ring = d % 4
                col = G if d < 3 else (K if ring < 0.8 and d > 5 and (i + k) % 3 == 0 else (Y if ring < 1.4 and d > 5 and (i + k) % 3 == 0 else (T if d > R - 1.2 else G)))
                fan.cells[(x, 5, z)] = col
    parts.append(fan)
    wing = Part("WingL", "Body", joint=(3, 0, 9))
    wing.box(3, 4, -2, 4, 5, 9, shade(B, -0.15))
    parts += [wing, wing.mirror("WingR")]
    return assemble("Peacock", parts)


def griffin():
    T, TD, W, Y, BR, BW = "D9A45A", "A8743A", "F7F4EE", "F2B21E", "7A4A22", "E9D2A8"
    parts = legs(T, Y, 5, -7, 5)
    for p in parts:
        if p.name.startswith("LegF"):
            for c in list(p.cells):
                p.cells[c] = W if c[2] >= 2 else Y            # feathered front legs, yellow talons
    body = Part("Body")
    body.box(-3, 3, -8, 8, 5, 11, lambda i, j, k: W if j <= -5 else (TD if k == 10 and abs(i + 0.5) < 2 else T))
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -8, 10))
    head.rbox(-3, 3, -13, -7, 10, 16, W, edges=(True, False, True))
    head.box(-1, 1, -15, -13, 11, 14, lambda i, j, k: shade(Y, -0.2) if k == 11 else Y)    # hooked beak
    eyes(head, -13, 14, xs=(-3, 1), w=2, h=1)
    for x in (-3, 2):                                          # feather tufts
        head.set([(x, -9, 16), (x, -8, 17)], W)
    parts.append(head)
    wing = Part("WingL", "Body", joint=(3, -4, 10))
    for d in range(10):
        for j in range(-7, -7 + 10 - d):
            wing.cells[(3 + d, j, 10 + d // 3)] = BW if j >= -7 + 10 - d - 2 else (BR if (d + j) % 2 else shade(BR, 0.15))
    parts += [wing, wing.mirror("WingR")]
    tail = Part("Tail", "Body", joint=(0, 8, 9))
    tail.box(-1, 1, 8, 13, 8, 10, T)
    tail2 = Part("Tail2", "Tail", joint=(0, 13, 9))
    tail2.box(-2, 2, 13, 16, 7, 10, TD)
    parts += [tail, tail2]
    a = assemble("Griffin", parts)
    a.extra["aura"] = "GoldDust"
    a.extra["float"] = True
    return a


# ===================================================================== zone: Beach


def crab():
    R, RD, C, W = "E2483A", "A82A22", "F6C8A8", "FFFFFF"
    parts = []
    body = Part("Body")
    body.rbox(-5, 5, -3, 3, 2, 6, lambda i, j, k: C if k == 2 else (RD if (i + j) % 4 == 0 and k == 5 else R))
    body.box(-1, 1, -4, -3, 3, 4, RD)                           # little mouth
    parts.append(body)
    for name, x, y in (("LegFL", 5, -1), ("LegBL", 5, 1), ("LegFR", -6, -1), ("LegBR", -6, 1)):
        p = Part(name, "Body", joint=(x + (0 if x > 0 else 1), y + 0.5, 3))
        out = 1 if x > 0 else -1
        p.set([(x, y, 3), (x + out, y, 2), (x + 2 * out, y, 1), (x + 2 * out, y, 0)], RD)
        parts.append(p)
    claw = Part("ArmL", "Body", joint=(3, -3, 4))
    claw.box(3, 4, -5, -3, 3, 5, R)                              # arm
    claw.box(3, 7, -9, -5, 3, 7, lambda i, j, k: None if (j <= -8 and k in (4, 5) and i in (4, 5)) else (C if k == 3 else R))   # pincer
    parts += [claw, claw.mirror("ArmR")]
    stalk = Part("EarL", "Body", joint=(2, -2, 6))
    stalk.set([(2, -2, 6), (2, -2, 7)], R)
    stalk.set([(2, -2, 8), (3, -2, 8), (2, -2, 9), (3, -2, 9)], W)
    stalk.set([(2, -3, 8), (3, -3, 8)], EYE)
    stalk.set([(3, -3, 9)], SHINE)
    stalk.set([(2, -3, 9)], EYE)
    parts += [stalk, stalk.mirror("EarR")]
    return assemble("Crab", parts)


def seagull():
    W, G, Y, R, GD = "F7F7F4", "AEB6C2", "FFD43B", "E8361E", "7A8494"
    parts = []
    leg = Part("LegL", "Body", joint=(1.5, -0.5, 3))
    leg.box(1, 2, -1, 0, 1, 3, Y)
    leg.box(0, 3, -3, 0, 0, 1, Y)
    parts += [leg, leg.mirror("LegR")]
    body = Part("Body")
    body.rbox(-3, 3, -4, 6, 2, 8, lambda i, j, k: G if k == 7 else W)
    body.box(-2, 2, 6, 9, 5, 7, lambda i, j, k: GD if j == 8 else W)   # tail
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -2, 8))
    head.rbox(-3, 3, -5, 0, 8, 13, W, edges=(True, False, True))
    eyes(head, -5, 11, xs=(-2, 1), w=1, h=1)
    head.box(-1, 1, -8, -5, 9, 10, Y)                            # beak with a red dot
    head.set([(-1, -7, 8), (0, -7, 8)], R)
    parts.append(head)
    wing = Part("WingL", "Body", joint=(3, 0, 7))
    wing.box(3, 4, -2, 7, 3, 7, lambda i, j, k: GD if j >= 5 else G)
    parts += [wing, wing.mirror("WingR")]
    a = assemble("Seagull", parts)
    a.extra["float"] = True
    return a


def seal():
    G, GS, B, N = "9AA3AE", "7C8592", "D8DEE6", "2A2E38"
    parts = []
    body = Part("Body")
    body.rbox(-3, 3, -7, 6, 0, 6, lambda i, j, k: B if (k <= 1 and j < 3) else (GS if (i * 3 + j * 5 + k) % 9 == 0 else G))
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -6, 5))
    head.rbox(-3, 3, -11, -5, 4, 10, G, edges=(True, False, True))
    head.box(-2, 2, -12, -11, 5, 7, B)                           # muzzle
    head.set([(-1, -12, 7), (0, -12, 7)], N)
    head.set([(-2, -12, 6), (1, -12, 6)], GS)                   # whisker dots
    eyes(head, -11, 8, xs=(-3, 1))
    parts.append(head)
    for name, x0 in (("LegFL", 3), ("LegFR", -5)):
        f = Part(name, "Body", joint=(x0 + (0 if x0 > 0 else 2), -3, 1))
        f.box(x0, x0 + 2, -5, -1, 0, 1, GS)
        parts.append(f)
    tail = Part("Tail", "Body", joint=(0, 6, 1))
    tail.box(-3, -1, 6, 9, 0, 1, GS)
    tail.box(1, 3, 6, 9, 0, 1, GS)
    tail.box(-1, 1, 6, 7, 0, 2, G)
    parts.append(tail)
    return assemble("Seal", parts)


def fishlike(name, top, belly, length, radius, fin=None, dorsal=3, fluke_vertical=False, snout=3, teeth=False, paint=None, horn=None):
    """Dolphins and sharks: a tapered body along y, a snout, a dorsal fin, side flippers
    and a tail fluke. Floats."""
    parts = []
    half = length // 2

    def r_at(j):
        t = (j + half) / length                    # 0 at the nose, 1 at the tail
        return max(1.6, radius * (1 - abs(t - 0.35) * 1.3))
    body = Part("Body")
    for j in range(-half + snout, half - 3):
        rr = r_at(j)
        for i in range(-radius, radius):
            for k in range(-radius, radius):
                if (i + 0.5) ** 2 + ((k + 0.5) * 1.15) ** 2 <= rr * rr:
                    col = belly if k < -rr * 0.25 else top
                    body.cells[(i, j, k + radius + 2)] = paint(i, j, k, col) if paint else col
    for d in range(dorsal):                         # dorsal fin, filled down to the back
        for j in range(-1 - d, 2 - d * 2 + dorsal):
            for i in (-1, 0):
                back = max([c[2] for c in body.cells if c[0] == i and c[1] == j] or [2 * radius + 1])
                for z in range(back + 1, 2 * radius + 3 + d):
                    body.cells.setdefault((i, j, z), top if not fin else fin)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -half + snout, radius + 2))
    for j in range(-half, -half + snout):
        for i in (-1, 0):
            for k in (radius + 1, radius + 2):
                head.cells[(i, j, k)] = belly if k == radius + 1 else top
    if horn:                                         # narwhal tusk: a long spiral spike
        for n in range(9):
            head.cells[(0 if n % 2 else -1, -half - n, radius + 2)] = horn if n % 2 else shade(horn, -0.2)
    if teeth:
        for i in range(-3, 3):
            head.cells[(i, -half + snout - 1, radius + 1)] = "FFFFFF"
    eyes(head, -half + snout - 1, radius + 3, xs=(-radius + 1, radius - 2), w=1, h=1)
    for c in [c for c in body.cells if c[1] == -half + snout and c[2] == radius + 3 and c[0] in (-radius + 1, radius - 2)]:
        del body.cells[c]
    parts.append(head)
    flip = Part("WingL", "Body", joint=(radius - 1, -half + snout + 3, radius + 1))
    flip.box(radius - 1, radius + 3, -half + snout + 2, -half + snout + 5, radius, radius + 1, top)
    parts += [flip, flip.mirror("WingR")]
    tail = Part("Tail", "Body", joint=(0, half - 3, radius + 2))
    tail.box(-1, 1, half - 3, half + 1, radius + 1, radius + 3, top)
    if fluke_vertical:                              # shark tail: big upper lobe, small lower lobe, swept back
        for n in range(4):
            tail.box(-1, 1, half + n, half + n + 1, radius + 1 - min(n, 2), radius + 4 + 2 * n, top)
    else:
        tail.box(-4, 4, half + 1, half + 3, radius + 1, radius + 2, top)
    parts.append(tail)
    a = assemble(name, parts)
    a.extra["float"] = True
    return a


def dolphin():
    return fishlike("Dolphin", "6A9AD8", "E8F0FA", 22, 4, dorsal=3, snout=3)


def shark():
    a = fishlike("Shark", "6E7E8E", "F2F4F6", 26, 5, dorsal=5, fluke_vertical=True, snout=2, teeth=True)
    return a


def sea_serpent(key="SeaSerpent", T="1FA59A", TD="137068", G="F2C14E", B="B8F0E0", I="7FF6FF", aura="Bubbles", coral=None):
    parts = []
    head = Part("Head", "Body", joint=(0, -6, 8))
    head.rbox(-3, 3, -12, -5, 6, 11, lambda i, j, k: B if k == 6 else T, edges=(True, False, True))
    head.box(-2, 2, -14, -12, 6, 9, lambda i, j, k: B if k == 6 else T)     # snout
    head.set([(-2, -14, 8), (1, -14, 8)], TD)
    for x in (-3, 2):                                         # horns
        head.set([(x, -8, 11), (x, -7, 12), (x, -6, 13)], G)
        if coral:                                             # branching coral antlers
            o = -1 if x < 0 else 1
            head.set([(x, -6, 14), (x, -5, 15), (x + o, -6, 15), (x + 2 * o, -6, 16), (x, -5, 16), (x, -4, 17), (x + o, -7, 14)], coral)
    eye_cells = [(x, -12, 9) for x in (-3, -2, 1, 2)]
    for c in eye_cells:
        head.cells.pop(c, None)
    parts.append(head)
    glow = Part("Eyes_Glow", "Head", joint=(0, -12, 9), noise=False, glow=I)
    glow.set(eye_cells, I)
    parts.append(glow)
    fin = Part("Fin", "Head", joint=(0, -6, 11))
    fin.set([(0, j, k) for j in range(-8, -3) for k in (11, 12) if not (k == 12 and j == -8)], G)
    fin.set([(-1, j, k) for j in range(-8, -3) for k in (11, 12) if not (k == 12 and j == -8)], G)
    parts.append(fin)
    scale = lambda i, j, k: B if k <= 1 + 4 - 4 else (TD if (i + j + k) % 3 == 0 else T)   # noqa: E731

    def segment(name, parent, y0, z0, r=3):
        p = Part(name, parent, joint=(0, y0, z0 + r))
        for j in range(y0, y0 + 6):
            for i in range(-r, r):
                for k in range(z0, z0 + 2 * r):
                    if (i + 0.5) ** 2 + (k - z0 - r + 0.5) ** 2 <= r * r + 1:
                        p.cells[(i, j, k)] = B if k == z0 else (TD if (i + j + k) % 3 == 0 else T)
        p.set([(0, j, z0 + 2 * r) for j in range(y0 + 1, y0 + 5, 2)], G)         # back spines
        p.set([(-1, j, z0 + 2 * r) for j in range(y0 + 1, y0 + 5, 2)], G)
        return p
    body = segment("Body", None, -6, 4)
    s1 = segment("Seg1", "Body", 0, 3)
    s2 = segment("Seg2", "Seg1", 6, 2)
    s3 = segment("Seg3", "Seg2", 12, 2, r=2)
    tail = Part("Tail", "Seg3", joint=(0, 18, 4))
    tail.box(-1, 1, 18, 22, 3, 5, T)
    tail.box(-3, 3, 21, 23, 2, 7, lambda i, j, k: G if abs(i + 0.5) >= 1.5 or k in (2, 6) else T)    # fin tip
    parts = [body, s1, s2, s3, tail] + parts
    a = assemble(key, parts)
    a.extra["float"] = True
    a.extra["aura"] = aura
    return a


# ====================================================================== zone: City


def pigeon():
    G, GL, D, N1, N2, O = "8E96A3", "B4BBC6", "4A505C", "5FA88A", "8A6AB0", "E8963C"
    parts = []
    leg = Part("LegL", "Body", joint=(1.5, -0.5, 2))
    leg.box(1, 2, -1, 0, 1, 2, "D86A6A")
    leg.box(1, 3, -2, 0, 0, 1, "D86A6A")
    parts += [leg, leg.mirror("LegR")]
    body = Part("Body")
    body.rbox(-3, 3, -4, 5, 2, 8, lambda i, j, k: GL if (j == -4 and k <= 5) else G)
    body.box(-2, 2, 5, 8, 4, 6, lambda i, j, k: D if j == 7 else G)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -2, 8))
    head.rbox(-2, 2, -5, -1, 8, 12, lambda i, j, k: (N1 if (i + k) % 2 else N2) if k <= 9 else G, edges=(False, False, True))
    head.box(-1, 1, -7, -5, 10, 11, "C8BFB4")
    head.set([(-1, -5, 11), (0, -5, 11)], "F6F2EA")         # cere
    eyes(head, -5, 11, xs=(-2, 1), w=1, h=1)
    head.set([(-2, -5, 10), (1, -5, 10)], O)                  # orange rings under the eyes
    parts.append(head)
    wing = Part("WingL", "Body", joint=(3, 0, 7))
    wing.box(3, 4, -2, 6, 3, 7, lambda i, j, k: D if j in (2, 4) else G)
    parts += [wing, wing.mirror("WingR")]
    a = assemble("Pigeon", parts)
    a.extra["float"] = True
    return a


def rat():
    G, GD, P, B = "8C7F78", "6A5E58", "F2A0A8", "D8CCC4"
    parts = legs(GD, P, 2, -4, 2)
    body = Part("Body")
    body.rbox(-3, 3, -5, 5, 2, 7, lambda i, j, k: B if k == 2 else G)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -5, 5))
    head.rbox(-3, 3, -9, -4, 3, 8, G, edges=(True, False, True))
    head.box(-1, 1, -12, -9, 4, 6, G)                          # pointy snout
    head.set([(-1, -12, 5), (0, -12, 5)], P)
    head.set([(-3, -11, 5), (2, -11, 5)], "E8E0D8")            # whiskers
    eyes(head, -9, 6, xs=(-2, 1), w=1, h=1)
    parts.append(head)
    ear = Part("EarL", "Head", joint=(2.5, -6.5, 8))
    ear.box(1, 4, -7, -6, 8, 11, lambda i, j, k: None if (k == 10 and i in (1, 3)) else (P if (i == 2 and k == 9) else G))
    parts += [ear, ear.mirror("EarR")]
    tail = Part("Tail", "Body", joint=(0, 5, 3))
    tail.set([(0, 5 + t, 3 + (1 if t > 3 else 0)) for t in range(6)], P)
    tail2 = Part("Tail2", "Tail", joint=(0, 11, 4))
    tail2.set([(0, 11 + t, 4 + (1 if t in (2, 3) else (2 if t > 3 else 0))) for t in range(6)], P)
    parts += [tail, tail2]
    return assemble("Rat", parts)


def corgi():
    O, W, D, N = "E8963C", "FAF3E8", "B86A24", "2A1C16"
    parts = legs(O, W, 2, -6, 4)
    for p in parts:
        if p.name.startswith("LegF"):
            for c in p.cells:
                p.cells[c] = W
    body = Part("Body")
    body.rbox(-3, 3, -7, 7, 2, 7, lambda i, j, k: W if (k == 2 or (j <= -6 and k <= 5)) else O)
    body.rbox(-2, 2, 7, 9, 3, 7, W)                            # fluffy butt, no tail
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -7, 6))
    head.rbox(-4, 4, -12, -6, 6, 12, lambda i, j, k: W if (j == -12 and (k <= 8 or i in (-1, 0))) else O, edges=(True, False, True))
    head.box(-2, 2, -14, -12, 6, 9, W)
    head.set([(-1, -14, 8), (0, -14, 8)], N)
    head.set([(-1, -14, 6), (0, -14, 6)], "FF7A8E")            # tongue
    eyes(head, -12, 9)
    parts.append(head)
    ear = Part("EarL", "Head", joint=(2.5, -8.5, 12))
    for k, xs in ((12, (1, 2, 3)), (13, (1, 2, 3)), (14, (2, 3)), (15, (3,))):
        for x in xs:
            ear.cells[(x, -9, k)] = "FFC8B0" if (x == 2 and k in (12, 13)) else O
    parts += [ear, ear.mirror("EarR")]
    return assemble("Corgi", parts)


def bulldog():
    F, W, M, R, S = "D8B48A", "FAF3E8", "3A2A22", "C8302A", "D8DDE4"
    parts = legs(F, W, 3, -6, 4, spread=1)
    body = Part("Body")
    body.rbox(-4, 4, -7, 6, 3, 9, lambda i, j, k: W if (j <= -6 and k <= 7 and -2 <= i <= 1) else F)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -7, 8))
    head.rbox(-5, 5, -12, -6, 6, 13, lambda i, j, k: M if (j == -12 and 6 <= k <= 9 and -3 <= i <= 2) else (W if (j == -12 and i in (-1, 0) and k >= 10) else F))
    head.set([(-1, -13, 8), (0, -13, 8)], "1A1210")            # nose
    head.set([(-3, -13, 6), (2, -13, 6), (-2, -13, 6), (1, -13, 6)], "FFFFFF")   # underbite teeth
    eyes(head, -12, 10, xs=(-4, 2))
    for c in [(x, -12, z) for x in (-5, 4) for z in (6, 7)]:   # jowls
        head.cells[c] = F
    parts.append(head)
    ear = Part("EarL", "Head", joint=(4, -8.5, 13))
    ear.set([(3, -9, 13), (4, -9, 13), (4, -9, 12)], M)
    parts += [ear, ear.mirror("EarR")]
    collar = Part("Collar", "Body", joint=(0, -6, 8), noise=False)
    for i in range(-4, 4):
        for k in (8,):
            collar.cells[(i, -8, k)] = S if i % 2 == 0 else R
    collar.box(-4, 4, -7, -6, 8, 9, R)
    parts.append(collar)
    tail = Part("Tail", "Body", joint=(0, 6, 7))
    tail.set([(-1, 6, 7), (0, 6, 7), (0, 7, 8)], F)
    parts.append(tail)
    return assemble("Bulldog", parts)


def robo_pup():
    M, D, J, C = "B8C2CC", "5A6672", "8A96A4", "5FF0FF"
    parts = legs(M, D, 4, -6, 4)
    for p in parts:
        for c in list(p.cells):
            if c[2] == 2:
                p.cells[c] = J                                  # knee joints
    body = Part("Body")
    body.box(-3, 3, -7, 7, 4, 9, lambda i, j, k: D if (k == 8 and j % 3 == 0) or (i in (-3, 2) and j % 4 == 0) else M)
    parts.append(body)
    core = Part("Core_Glow", "Body", joint=(0, -7, 6), noise=False, glow=C)
    core.box(-1, 1, -8, -7, 5, 7, C)
    parts.append(core)
    head = Part("Head", "Body", joint=(0, -7, 8))
    head.box(-4, 4, -12, -6, 7, 13, lambda i, j, k: D if (k == 12 and abs(i + 0.5) < 2) else M)
    head.box(-2, 2, -14, -12, 7, 10, M)
    head.set([(-1, -14, 9), (0, -14, 9)], D)
    head.set([(-2, -14, 7), (-1, -14, 7), (0, -14, 7), (1, -14, 7)], D)    # speaker grill mouth
    visor = [(x, -12, z) for x in range(-3, 3) for z in (10, 11)]
    for v in visor:
        head.cells.pop(v, None)
    parts.append(head)
    eyes_ = Part("Visor_Glow", "Head", joint=(0, -12, 10.5), noise=False, glow=C)
    eyes_.set(visor, C)
    parts.append(eyes_)
    ear = Part("EarL", "Head", joint=(3, -8.5, 13))
    ear.box(2, 4, -9, -8, 13, 15, D)
    parts += [ear, ear.mirror("EarR")]
    ant = Part("Antenna_Glow", "Head", joint=(0, -9, 13), noise=False, glow="FF5A7A")
    ant.set([(0, -9, 14), (0, -9, 15)], "FF5A7A")
    parts.append(ant)
    ant_rod = Part("Antenna", "Head", joint=(0, -9, 13))
    ant_rod.set([(0, -9, 13)], D)
    parts.append(ant_rod)
    tail = Part("Tail", "Body", joint=(0, 7, 8))
    tail.set([(0, 7, 8), (0, 8, 9), (0, 8, 10), (0, 9, 11)], D)
    parts.append(tail)
    return assemble("RoboPup", parts)


def gargoyle():
    S, SD, MO, E = "8A8C90", "66686E", "6A8A4A", "FF7A3A"
    parts = legs(S, SD, 4, -6, 4, spread=1)
    stone = lambda i, j, k: SD if (i * 7 + j * 3 + k * 5) % 9 == 0 else (MO if (i + j * 2 + k) % 23 == 0 else S)   # noqa: E731
    body = Part("Body")
    body.rbox(-4, 4, -6, 6, 4, 11, stone)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -6, 10))
    head.rbox(-4, 4, -11, -5, 9, 15, stone, edges=(True, False, True))
    head.box(-3, 3, -13, -11, 9, 11, stone)                   # snarling jaw
    head.set([(-3, -13, 10), (2, -13, 10)], "E8E4DA")          # tusks
    eye_cells = [(x, -11, 13) for x in (-3, -2, 1, 2)]
    for c in eye_cells:
        head.cells.pop(c, None)
    for x in (-4, 3):                                         # curled horns
        head.set([(x, -8, 15), (x, -7, 16), (x, -6, 16), (x, -5, 15)], SD)
    parts.append(head)
    glow = Part("Eyes_Glow", "Head", joint=(0, -11, 13), noise=False, glow=E)
    glow.set(eye_cells, E)
    parts.append(glow)
    wing = Part("WingL", "Body", joint=(4, -2, 10))
    for d in range(9):
        for j in range(-5, -5 + 9 - d):
            bone = j == -5 or d in (0, 4, 8)
            wing.cells[(4 + d, j, 10 + d // 2)] = SD if bone else S
    parts += [wing, wing.mirror("WingR")]
    tail = Part("Tail", "Body", joint=(0, 6, 6))
    tail.box(-1, 1, 6, 10, 5, 7, S)
    tail.box(-2, 2, 10, 12, 5, 7, SD)
    parts.append(tail)
    a = assemble("Gargoyle", parts)
    a.extra["float"] = True
    a.extra["aura"] = "Gloom"
    return a


# ----------------------------------------------------------------- Snowy Peaks (zone Europa)


def snow_hare():
    W, B, K, P, N = "F6F8FC", "C8D4E4", "2A2E38", "F4B8C8", "E88AA0"   # white, blue-grey, black tips, inner ear, nose
    parts = []
    for name, x0, y0, big in (("LegFL", 1, -4, False), ("LegFR", -3, -4, False), ("LegBL", 1, 2, True), ("LegBR", -3, 2, True)):
        p = Part(name, "Body", joint=(x0 + 1, y0 + 1, 3))
        p.box(x0, x0 + 2, y0, y0 + 2, 0, 3, W)
        if big:                                             # big snowshoe feet
            p.box(x0, x0 + 2, y0 - 3, y0, 0, 1, lambda i, j, k: B if j == y0 - 3 else W)
        parts.append(p)
    body = Part("Body")
    body.rbox(-3, 3, -5, 5, 2, 8, lambda i, j, k: B if (k == 7 and (i + j) % 3 == 0) else W)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -5, 7))
    head.rbox(-4, 4, -10, -4, 6, 12, W, edges=(True, False, True))
    eyes(head, -10, 9, shine=False)
    head.box(-2, 2, -11, -10, 7, 9, W)
    head.set([(-1, -11, 8), (0, -11, 8)], N)
    head.set([(-3, -10, 8), (2, -10, 8)], P)
    parts.append(head)
    ear = Part("EarL", "Head", joint=(2, -7, 12))
    ear.box(1, 3, -8, -6, 12, 19, lambda i, j, k: K if k >= 18 else (P if (j == -8 and i == 1 and 13 <= k <= 16) else W))
    parts += [ear, ear.mirror("EarR")]
    tail = Part("Tail", "Body", joint=(0, 5, 5))
    tail.rbox(-1, 1, 5, 7, 4, 7, W, edges=(False, False, False))
    parts.append(tail)
    return assemble("SnowHare", parts)


def mountain_goat():
    W, G, H, D, N = "F2F0EA", "C8C4BA", "4A4440", "2A2624", "8A8078"   # wool, shade, horn, hoof, nose
    parts = legs(W, D, 6, -6, 4, sock=G, sock_h=2)
    body = Part("Body")
    body.rbox(-3, 3, -7, 7, 6, 12, lambda i, j, k: G if k == 6 or (k == 7 and (i + j) % 2) else W)   # shaggy belly fringe
    body.box(-1, 1, -8, -6, 8, 12, W)                                  # neck ruff
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -7, 11))
    head.box(-3, 3, -12, -7, 11, 16, W)
    head.box(-2, 2, -14, -12, 11, 14, W)                               # long face
    head.set([(-1, -14, 13), (0, -14, 13)], N)
    head.box(-1, 1, -13, -11, 8, 11, lambda i, j, k: G if k == 8 else W)   # beard
    eyes(head, -12, 14, xs=(-3, 2), w=1, h=1, shine=False)
    parts.append(head)
    horns = Part("Horns", "Head", joint=(0, -9, 16))
    for x in (-2, 1):                                                  # short black horns curving back
        horns.set([(x, -10, 16), (x, -10, 17), (x, -9, 18), (x, -8, 19), (x, -7, 19)], H)
    parts.append(horns)
    ear = Part("EarL", "Head", joint=(3, -9, 15))
    ear.box(3, 5, -10, -9, 14, 15, lambda i, j, k: "E8C8C0" if i == 3 else W)
    parts += [ear, ear.mirror("EarR")]
    tail = Part("Tail", "Body", joint=(0, 7, 11))
    tail.box(-1, 1, 7, 8, 10, 12, W)
    parts.append(tail)
    return assemble("MountainGoat", parts)


def snow_leopard():
    W, G, R, C, I = "E6E8EC", "C2C8D0", "4A4E58", "F8FAFC", "8ED8E8"    # pale grey, shade, rosette, belly, ice eyes
    parts = legs(W, C, 4, -6, 4)
    for p in parts:
        for c in list(p.cells):
            if (c[0] + c[1] + c[2]) % 4 == 0 and c[2] > 0:
                p.cells[c] = R

    def ros(i, j, k):                                                  # ring spots
        a, b = (i + 7) % 4, (j + 9 + (k // 2) * 2) % 4
        return R if (k >= 7 and ((a == 0 and b < 3) or (b == 0 and a < 3)) and (i + j + k) % 3) else None
    body = Part("Body")
    body.box(-3, 3, -7, 7, 4, 9, lambda i, j, k: C if k == 4 and -5 <= j <= 5 else (ros(i, j, k) or W))
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -7, 8))
    head.rbox(-4, 4, -12, -6, 7, 13, lambda i, j, k: R if (k == 12 and (i + j) % 3 == 0) else W, edges=(True, False, True))
    head.box(-2, 2, -13, -12, 7, 10, C)
    head.set([(-1, -13, 9), (0, -13, 9)], "D88A9A")
    head.set([(-1, -13, 7), (0, -13, 7)], R)
    eye_cells = [(x, -12, z) for x in (-3, -2, 1, 2) for z in (10,)]
    for c in eye_cells:
        head.cells.pop(c, None)
    head.set([(x, -12, 11) for x in (-3, -2, 1, 2)], G)                # brow
    parts.append(head)
    glow = Part("Eyes_Glow", "Head", joint=(0, -12, 10.5), noise=False, glow=I)
    glow.set(eye_cells, I)
    parts.append(glow)
    ear = Part("EarL", "Head", joint=(3, -9, 13))
    ear.box(2, 4, -9, -8, 13, 14, lambda i, j, k: R if i == 3 else W)
    parts += [ear, ear.mirror("EarR")]
    tail = Part("Tail", "Body", joint=(0, 7, 8))                       # very long, very thick tail
    tail.rbox(-2, 2, 7, 12, 6, 10, lambda i, j, k: R if j % 3 == 0 else W, edges=(True, False, False))
    tail2 = Part("Tail2", "Tail", joint=(0, 12, 8))
    tail2.rbox(-2, 2, 12, 17, 6, 10, lambda i, j, k: R if j % 3 == 0 or j == 16 else W, edges=(True, False, False))
    parts += [tail, tail2]
    return assemble("SnowLeopard", parts)


def mammoth():
    F, FD, S, T, E = "8A5A36", "6A4228", "A8744A", "F4ECDA", "241A16"   # fur, dark fur, light fur, tusk
    parts = legs(FD, "3A2A20", 6, -7, 5, spread=1)
    for p in parts:
        p.box(min(c[0] for c in p.cells) - 0, max(c[0] for c in p.cells) + 1, min(c[1] for c in p.cells), max(c[1] for c in p.cells) + 1, 5, 6, F)
    shag = lambda i, j, k: FD if (i * 5 + j * 3 + k * 7) % 7 == 0 else (S if (i + 2 * j + k) % 11 == 0 else F)   # noqa: E731
    body = Part("Body")
    body.rbox(-5, 5, -8, 8, 5, 15, shag)
    body.rbox(-4, 4, -7, 2, 15, 17, shag)                               # shoulder hump
    for c in [c for c in body.cells if c[2] <= 6 and (c[0] + c[1]) % 2 == 0]:   # shaggy dark underside
        body.cells[c] = FD
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -8, 13))
    head.rbox(-4, 4, -12, -7, 9, 17, shag, edges=(True, False, True))
    head.rbox(-3, 3, -11, -8, 17, 19, FD)                               # domed top
    eyes(head, -12, 13, xs=(-4, 3), w=1, h=1, shine=False)
    parts.append(head)
    trunk = Part("Trunk", "Head", joint=(0, -12.5, 11))
    trunk.box(-1, 1, -14, -12, 6, 12, F)
    trunk2 = Part("Trunk2", "Trunk", joint=(0, -13, 6))
    trunk2.box(-1, 1, -14, -12, 3, 6, F)
    trunk2.box(-1, 1, -16, -14, 3, 4, FD)                              # curled tip
    parts += [trunk, trunk2]
    for x, nm in ((2, "TuskL"), (-3, "TuskR")):
        t = Part(nm, "Head", joint=(x + 0.5, -12, 10), noise=False)
        t.set([(x, -12, 10), (x, -13, 9), (x, -14, 8), (x, -15, 8), (x, -16, 9), (x, -17, 10), (x, -17, 11)], T)
        parts.append(t)
    ear = Part("EarL", "Head", joint=(4, -9, 14))
    ear.box(4, 5, -10, -8, 11, 15, FD)
    parts += [ear, ear.mirror("EarR")]
    tail = Part("Tail", "Body", joint=(0, 8, 12))
    tail.box(-1, 1, 8, 9, 8, 12, F)
    tail.box(-1, 1, 8, 9, 7, 8, FD)
    parts.append(tail)
    return assemble("Mammoth", parts)


def frost_eagle():
    W, B, BD, I, Y, K = "F6F8FC", "7AA8D8", "4A72A8", "B8F0FF", "F2C230", "2A2E38"   # white, ice blue, deep blue, ice, beak, talon
    parts = []
    leg = Part("LegL", "Body", joint=(1.5, 0, 3))
    leg.box(1, 3, -1, 1, 1, 3, Y)
    leg.box(1, 3, -2, 1, 0, 1, lambda i, j, k: K if j == -2 else Y)
    parts += [leg, leg.mirror("LegR")]
    body = Part("Body")
    body.rbox(-3, 3, -4, 6, 3, 10, lambda i, j, k: BD if (k == 9 and j % 2) else (W if j == -4 else B))
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -3, 10))
    head.rbox(-3, 3, -7, -2, 9, 14, W, edges=(True, False, True))
    head.box(-1, 1, -9, -7, 10, 13, Y)                                  # hooked beak
    head.set([(-1, -9, 9), (0, -9, 9)], Y)
    head.set([(-1, -9, 12), (0, -9, 12)], shade(Y, -0.25))
    eyes(head, -7, 12, xs=(-3, 2), w=1, h=1, shine=False)
    head.set([(-3, -7, 13), (2, -7, 13)], "C8CCD8")                     # fierce brow
    parts.append(head)
    wing = Part("WingL", "Body", joint=(3, -1, 9))
    for d in range(10):                                                # long swept wing, ice-tipped
        for j in range(-3, 4 - d // 3):
            tip = d >= 7 and j >= 1 - d // 3
            wing.cells[(3 + d, j, 9 - d // 4)] = I if tip else (BD if j == -3 or d % 3 == 0 else B)
    parts += [wing, wing.mirror("WingR")]
    tail = Part("Tail", "Body", joint=(0, 6, 6))
    tail.box(-2, 2, 6, 10, 5, 6, lambda i, j, k: I if j == 9 else BD)
    parts.append(tail)
    a = assemble("FrostEagle", parts)
    a.extra["float"] = True
    a.extra["aura"] = "Frost"
    return a


def yeti():
    W, WS, F, FD, H, I, M = "F4F6FA", "D4DCE8", "8EA2BE", "6A7E9C", "C8E8FF", "7EE8FF", "3A2A40"   # fur, fur shade, face, dark face, horn, ice, mouth
    fur = lambda i, j, k: WS if (i * 3 + j * 7 + k * 5) % 9 == 0 else W   # noqa: E731
    parts = []
    leg = Part("LegL", "Body", joint=(2.5, 0, 6))
    leg.rbox(1, 5, -2, 2, 1, 7, fur, edges=(False, False, True))
    leg.box(1, 5, -3, 2, 0, 1, F)                                       # big feet
    parts += [leg, leg.mirror("LegR")]
    body = Part("Body")
    body.rbox(-5, 5, -3, 4, 6, 17, fur)
    body.box(-3, 3, -4, -3, 8, 14, WS)                                  # chest
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -1, 16))
    head.rbox(-4, 4, -5, 3, 16, 23, fur)
    head.box(-3, 3, -6, -5, 16, 21, lambda i, j, k: FD if k <= 17 else F)   # blue face
    eyes(head, -6, 19, xs=(-3, 1), w=2, h=1)
    head.set([(-2, -6, 17), (1, -6, 17)], "FFFFFF")                     # fangs
    head.set([(-1, -6, 17), (0, -6, 17)], M)
    head.box(-2, 2, -6, -5, 21, 22, WS)                                 # brow tuft
    parts.append(head)
    horns = Part("Horns_Glow", "Head", joint=(0, -1, 23), noise=False, glow=H)
    for x in (-4, 3):
        horns.set([(x, -1, 23), (x, -1, 24), (x + (1 if x < 0 else -1) * 0, 0, 25)], H)
    parts.append(horns)
    arm = Part("ArmL", "Body", joint=(6, 0, 15))
    arm.rbox(5, 8, -2, 2, 5, 16, fur, edges=(False, False, True))
    arm.box(5, 8, -2, 2, 3, 5, F)                                       # hands
    parts += [arm, arm.mirror("ArmR")]
    ice = Part("Crystals_Glow", "Body", joint=(0, 4, 12), noise=False, glow=I)   # ice shards on its back
    ice.set([(-2, 4, 12), (-2, 5, 13), (-2, 5, 14), (1, 4, 10), (1, 5, 11), (0, 4, 14), (0, 5, 15), (0, 6, 16)], I)
    parts.append(ice)
    a = assemble("Yeti", parts)
    a.extra["aura"] = "Snowfall"
    return a


# ----------------------------------------------------------------- zone Cosmic pets


def butterfly_queen():
    D, PU, PK, OR, WH, K, G = "3A2450", "9A5AE0", "FF7AC8", "FFB04A", "FFFFFF", "1E1428", "FFE27A"
    parts = []
    body = Part("Body")
    body.rbox(-2, 2, -4, 7, 4, 9, lambda i, j, k: PU if j % 2 else D, edges=(True, False, True))
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -4, 7))
    head.rbox(-3, 3, -9, -3, 5, 11, D, edges=(True, False, True))
    eyes(head, -9, 7, xs=(-3, 1), w=2, h=2)
    parts.append(head)
    crown = Part("Crown_Glow", "Head", joint=(0, -6, 11), noise=False, glow=G)
    crown.box(-2, 2, -7, -5, 11, 12, G)
    crown.set([(-2, -7, 12), (0, -7, 12), (1, -6, 12), (-2, -5, 12), (1, -5, 12), (-1, -6, 13)], G)
    parts.append(crown)
    ant = Part("Antennae_Glow", "Head", joint=(0, -8, 11), noise=False, glow=G)
    for x in (-2, 1):
        o = -1 if x < 0 else 1
        ant.set([(x + o, -8, 11), (x + o, -9, 12), (x + 2 * o, -10, 13), (x + 2 * o, -11, 13)], G)
    parts.append(ant)

    def wcol(i, j, k):                    # i >= 1: distance out from the body
        if (i, j) in ((5, -4), (8, -3), (4, 3), (6, 2)):
            return WH                     # white spots
        if i <= 3:
            return PU
        return PK if i <= 6 else OR
    wing = Part("WingL", "Body", joint=(2, 0, 7))
    for i in range(1, 14):                # upper wing, rounded
        for j in range(-9, 1):
            if (i - 1) ** 2 / 150 + (j + 3) ** 2 / 36 <= 1:
                wing.cells[(i + 1, j, 7)] = wcol(i, j, 7)
    for i in range(1, 10):                # lower wing with a tail
        for j in range(0, 8):
            if (i - 1) ** 2 / 70 + (j - 1) ** 2 / 36 <= 1:
                wing.cells[(i + 1, j, 7)] = wcol(i, j, 7)
    wing.set([(4, 8, 7), (4, 9, 7), (5, 9, 7)], OR)
    edge = [c for c in wing.cells if any((c[0] + dx, c[1] + dy, 7) not in wing.cells for dx, dy in ((1, 0), (0, 1), (0, -1))) and c[0] > 2]
    for c in edge:
        wing.cells[c] = K                 # black wing border
    parts += [wing, wing.mirror("WingR")]
    a = assemble("ButterflyQueen", parts)
    a.extra["float"] = True
    a.extra["aura"] = "Petals"
    return a


def kraken(key="Kraken", R="B8304A", RD="7A1E36", SP="E86A80", Y="FFD23F", SU="F4A0B0", aura="Bubbles"):
    # red, dark, spots, eye, suckers
    parts = []
    body = Part("Body")
    body.rbox(-5, 5, -5, 5, 4, 15, lambda i, j, k: SP if (i * 5 + j * 3 + k * 7) % 13 == 0 and k > 6 else (RD if k == 4 else R))
    body.rbox(-4, 4, -4, 4, 15, 16, R)                 # rounded dome top
    eye_cells = []
    for x0 in (-5, 2):
        body.box(x0, x0 + 3, -6, -5, 8, 11, Y)
        eye_cells += [(x0, -6, 9), (x0 + 1, -6, 9), (x0 + 2, -6, 9)]
    body.set(eye_cells, EYE)                           # goat-like slit pupils
    parts.append(body)
    dirs = [(-1, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (1, 1), (0, 1), (0, -1)]
    for n, (dx, dy) in enumerate(dirs):
        bx, by = dx * 3 - (1 if dx <= 0 else 0) + (0 if dx else -1), dy * 3 - (1 if dy <= 0 else 0) + (0 if dy else -1)
        if (dx, dy) == (0, -1):
            continue                                       # keep the face clear
        t = Part(f"Tent{n + 1}", "Body", joint=(bx + 1, by + 1, 4))
        t2 = Part(f"Tent{n + 1}b", f"Tent{n + 1}", joint=(bx + 1 + dx * 5, by + 1 + dy * 5, 1))
        for s_ in range(10):
            x, y = bx + dx * s_, by + dy * s_
            z = max(0, 3 - s_) if s_ < 8 else s_ - 7
            col = lambda i, j, k: SU if k == 0 and (i + j) % 2 == 0 else R    # noqa: E731
            (t if s_ < 5 else t2).box(x, x + 2, y, y + 2, z, z + (2 if s_ < 4 else 1) + (1 if s_ < 2 else 0), col)
        parts += [t, t2]
    a = assemble(key, parts)
    if aura:
        a.extra["aura"] = aura
    return a


def mecha_rex():
    M, P, K, N, C, W = "3A4250", "5A6678", "22262E", "FF3AD8", "4FF0FF", "E8ECF2"
    parts = []
    leg = Part("LegL", "Body", joint=(3.5, 1, 8))
    leg.box(2, 5, -1, 3, 3, 8, lambda i, j, k: P if k >= 6 else M)
    leg.box(2, 5, 0, 3, 1, 3, M)
    leg.box(2, 5, -3, 3, 0, 1, K)                       # big clawed foot
    leg.set([(2, -4, 0), (4, -4, 0)], W)
    parts += [leg, leg.mirror("LegR")]
    body = Part("Body")
    body.box(-4, 4, -4, 8, 7, 14, lambda i, j, k: P if k == 13 or (j % 4 == 0) else M)
    parts.append(body)
    stripes = Part("Stripes_Glow", "Body", joint=(0, 2, 10), noise=False, glow=N)
    stripes.set([(x, j, 10) for x in (-5, 4) for j in range(-3, 8)], N)
    stripes.set([(0, j, 14) for j in range(-3, 8, 2)] + [(-1, j, 14) for j in range(-3, 8, 2)], N)   # spine plates
    parts.append(stripes)
    head = Part("Head", "Body", joint=(0, -4, 13))
    head.box(-4, 4, -13, -3, 12, 18, lambda i, j, k: P if k == 17 else M)
    for c in [(x, -13, z) for x in range(-4, 4) for z in (12,)]:
        head.cells.pop(c, None)
    head.set([(x, -13, 13) for x in (-3, -1, 1, 3)], W)            # top teeth
    visor = [(x, -13, 16) for x in (-4, -3, 2, 3)] + [(x, -12, 16) for x in (-4, 3)]
    for v in visor:
        head.cells.pop(v, None)
    parts.append(head)
    eyes_ = Part("Visor_Glow", "Head", joint=(0, -13, 16), noise=False, glow=C)
    eyes_.set(visor, C)
    parts.append(eyes_)
    jaw = Part("Jaw", "Head", joint=(0, -4, 11))
    jaw.box(-3, 3, -12, -4, 10, 12, lambda i, j, k: W if (k == 11 and j == -12 and i % 2 == 0) else K)
    parts.append(jaw)
    arm = Part("ArmL", "Body", joint=(4.5, -3, 10))
    arm.box(4, 5, -4, -2, 8, 11, P)
    arm.set([(4, -5, 8)], W)
    parts += [arm, arm.mirror("ArmR")]
    tail = Part("Tail", "Body", joint=(0, 8, 11))
    tail.box(-3, 3, 8, 14, 9, 13, lambda i, j, k: P if j % 3 == 0 else M)
    tail2 = Part("Tail2", "Tail", joint=(0, 14, 11))
    tail2.box(-2, 2, 14, 20, 10, 12, lambda i, j, k: N if j == 19 else M)
    parts += [tail, tail2]
    a = assemble("MechaRex", parts)
    a.extra["aura"] = "Sparks"
    return a


def aurora_whale():
    B, BD, BL, G1, G2, G3 = "2E4A9A", "1E3270", "C8D8F0", "5AFFB0", "4FD8FF", "B07AFF"
    aur = [G1, G2, G3]
    parts = []
    body = Part("Body")
    body.rbox(-5, 5, -10, 10, 4, 13, lambda i, j, k: BL if (k <= 5 and (i % 2 == 0 or k == 4)) else (BD if (k == 12 and (i * 3 + j) % 5 == 0) else B))
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -10, 8))
    head.rbox(-5, 5, -16, -9, 4, 12, lambda i, j, k: BL if (k <= 5 and (i % 2 == 0 or k == 4)) else B, edges=(True, True, True))
    for x in (-5, 4):
        head.set([(x, -12, 8)], EYE)
        head.set([(x, -12, 9)], SHINE)
    parts.append(head)
    fin = Part("FinL", "Body", joint=(5, -4, 6))
    fin.box(5, 10, -5, -2, 5, 6, lambda i, j, k: BL if j == -5 else B)
    parts += [fin, fin.mirror("FinR")]
    tail = Part("Tail", "Body", joint=(0, 10, 9))
    tail.rbox(-3, 3, 9, 16, 6, 11, B)
    tail2 = Part("Tail2", "Tail", joint=(0, 16, 8))
    for i in range(-7, 7):
        for j in range(15, 19):
            if abs(i + 0.5) + (j - 15) * 1.5 <= 7 and not (abs(i + 0.5) < 1 and j == 18):
                tail2.cells[(i, j, 8)] = BD if j == 15 else B
    parts += [tail, tail2]
    glow = Part("Aurora_Glow", "Body", joint=(0, 0, 13), noise=False, glow=G2)
    for j in range(-12, 12):
        glow.cells[(0 if j % 2 else -1, j, 13)] = aur[(j // 3) % 3]
    for j in range(-8, 9):                             # aurora bands down the sides
        for x in (-6, 5):
            if (j + 9) % 4 < 2:
                glow.cells[(x, j, 10 - (j + 9) % 4)] = aur[(j // 4) % 3]
    parts.append(glow)
    a = assemble("AuroraWhale", parts)
    a.extra["float"] = True
    a.extra["aura"] = "Aurora"
    return a


# --------------------------------------------------------------- field mob: dust bunny
# Not a pet: the big wild bunnies that hop around the leaf fields (DustBunnyService).
# Model Mob_DustBunny, anims Mob_DustBunny_Idle / _Walk (slow hop) / _Run (fleeing).


def dust_bunny():
    F, FS, FL, P, N, B, L, LV = "EFE4D2", "DDCFBC", "FBF6EE", "FFB0C4", "F27E98", "FFC9D6", "F2A33A", "C8641E"
    # fur, dusty fur, light fur (belly, cheeks), inner ear, nose, blush, leaf, leaf vein
    fur = lambda i, j, k: FS if (i * 7 + j * 5 + k * 3) % 19 == 0 else F    # noqa: E731  dust speckles
    parts = []
    for name, x0 in (("LegFL", 1), ("LegFR", -3)):                 # small front paws
        p = Part(name, "Body", joint=(x0 + 1, -4, 4))
        p.box(x0, x0 + 2, -5, -3, 0, 4, lambda i, j, k: FL if k == 0 else F)
        parts.append(p)
    for name, x0 in (("LegBL", 2), ("LegBR", -5)):                 # big haunches with long feet
        p = Part(name, "Body", joint=(x0 + 1.5, 3, 5))
        p.rbox(x0, x0 + 3, 0, 6, 1, 6, fur, edges=(True, False, False))
        p.box(x0, x0 + 3, -3, 3, 0, 1, lambda i, j, k: FL if j <= -2 else F)
        p.set([(x0, -3, 0), (x0 + 2, -3, 0)], FS)                # toe lines
        parts.append(p)
    body = Part("Body")
    body.rbox(-4, 4, -5, 6, 2, 10, lambda i, j, k: FL if (j <= -4 and k <= 7 and -2 <= i <= 1) or k == 2 else fur(i, j, k))
    body.rbox(-3, 3, -3, 5, 10, 11, fur)                             # rounded back
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -4, 9))
    head.rbox(-5, 5, -10, -2, 8, 16, fur, edges=(True, True, True))
    head.box(-5, 5, -10, -9, 8, 11, lambda i, j, k: FL if abs(i + 0.5) >= 2 else None)    # puffy cheeks
    for x0 in (-4, 2):                                                                    # big eyes, 2x3 with a shine
        head.box(x0, x0 + 2, -11, -10, 11, 14, EYE)
        head.set([(x0 if x0 < 0 else x0 + 1, -11, 13)], SHINE)
    head.set([(-5, -10, 10), (4, -10, 10), (-5, -11, 10), (4, -11, 10)], B)              # blush
    head.box(-2, 2, -11, -10, 9, 11, FL)                                                  # muzzle
    head.set([(-1, -11, 11), (0, -11, 11), (-1, -12, 11), (0, -12, 11)], N)             # nose
    head.set([(-1, -11, 9), (0, -11, 9)], "FFFFFF")                                       # buck teeth
    head.set([(-3, -11, 10), (-4, -11, 10), (2, -11, 10), (3, -11, 10)], FS)            # whiskers
    head.box(-3, 3, -9, -3, 16, 17, lambda i, j, k: FS if (i + j) % 3 == 0 else F)       # tuft on top
    parts.append(head)
    ear = Part("EarL", "Head", joint=(2.5, -5, 16))
    ear.rbox(1, 4, -6, -4, 16, 25, lambda i, j, k: P if (j == -6 and i == 2 and 17 <= k <= 23) else (FS if k == 24 else F), edges=(False, False, True))
    parts.append(ear)
    earR = ear.mirror("EarR")
    for c in list(earR.cells):                                       # right ear flops over at the tip
        if c[2] >= 22:
            del earR.cells[c]
    earR.box(-4, -1, -6, -4, 22, 23, F)
    earR.box(-6, -3, -6, -4, 21, 22, FS)
    parts.append(earR)
    leaf = Part("Leaf", "Head", joint=(-2, -6, 17))                  # a leaf stuck on its head
    for (i, j) in [(-3, -7), (-2, -7), (-3, -6), (-2, -6), (-1, -6), (-4, -6), (-3, -5), (-2, -5), (-2, -8), (-1, -5), (-2, -4)]:
        leaf.cells[(i, j, 17)] = LV if (i == -2 or j == -6) and (i, j) != (-4, -6) else L
    leaf.cells[(-2, -9, 17)] = LV                                    # stem
    parts.append(leaf)
    tail = Part("Tail", "Body", joint=(0, 6, 6))
    tail.rbox(-2, 2, 6, 9, 4, 8, FL, edges=(False, False, False))
    parts.append(tail)
    for p in parts:                                                  # no doubled-up cubes: they z-fight
        if p is not body:
            for c in p.cells:
                body.cells.pop(c, None)
    return assemble("DustBunny", parts, name="Mob_DustBunny", kind="mob")


# ------------------------------------------------------- Park extras (3 per rarity)


def bird(key, body_col, belly, wing_col, beak, legs_col, head_col=None, crest=None, tail_len=2, size=(3, 4, 5), beak_len=2):
    """A round voxel bird (robin, crow, puffin, parrot...). Flies with fly()."""
    hx, by, bz = size                                   # half width, body half length, body height
    head_col = head_col or body_col
    parts = []
    leg = Part("LegL", "Body", joint=(1.5, 0, 2))
    leg.box(1, 2, -1, 1, 1, 2, legs_col)
    leg.box(1, 3, -2, 1, 0, 1, legs_col)
    parts += [leg, leg.mirror("LegR")]
    body = Part("Body")
    body.rbox(-hx, hx, -by, by + 1, 2, 2 + bz + 1, lambda i, j, k: belly if (j <= -by + 1 and k <= bz) or (k == 2) else body_col)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -by + 2, 2 + bz))
    head.rbox(-hx + 1, hx - 1, -by - 2, -by + 3, 2 + bz, 2 + bz + 5, head_col, edges=(True, False, True))
    eyes(head, -by - 2, bz + 5, xs=(-hx + 1, hx - 2), w=1, h=1)
    head.box(-1, 1, -by - 2 - beak_len, -by - 2, bz + 3, bz + 5, beak)
    if crest:
        head.set([(0, -by, 2 + bz + 5), (-1, -by, 2 + bz + 5), (0, -by + 1, 2 + bz + 6), (-1, -by + 2, 2 + bz + 6)], crest)
    parts.append(head)
    wing = Part("WingL", "Body", joint=(hx, 0, bz + 1))
    wing.box(hx, hx + 1, -by + 1, by, 3, bz + 2, lambda i, j, k: shade(wing_col, -0.12) if j >= by - 2 else wing_col)
    parts += [wing, wing.mirror("WingR")]
    tail = Part("Tail", "Body", joint=(0, by, bz))
    tail.box(-2, 2, by + 1, by + 1 + tail_len, bz - 1, bz + 1, lambda i, j, k: shade(wing_col, -0.15) if j == by + tail_len else wing_col)
    parts.append(tail)
    a = assemble(key, parts)
    a.extra["float"] = True
    return a


def ladybug():
    R, K, W = "E8322E", "1E1A1E", "FFFFFF"
    parts = []
    for n, (x0, y0) in enumerate([(2, -3), (-4, -3), (2, 0), (-4, 0), (2, 3), (-4, 3)]):
        nm = ["LegFL", "LegFR", "LegML", "LegMR", "LegBL", "LegBR"][n]
        p = Part(nm, "Body", joint=(x0 + 1 if x0 > 0 else x0 + 1, y0, 2))
        p.box(x0 + (1 if x0 > 0 else 0), x0 + (2 if x0 > 0 else 1), y0, y0 + 1, 0, 2, K)
        p.box(x0 + (2 if x0 > 0 else -1), x0 + (3 if x0 > 0 else 0), y0, y0 + 1, 0, 1, K)
        parts.append(p)
    body = Part("Body")
    spots = {(-3, -2), (2, -2), (-1, 1), (0, 1), (-4, 3), (3, 3), (-2, 5), (1, 5)}
    body.rbox(-5, 5, -4, 7, 1, 7, lambda i, j, k: K if (i in (-1, 0) and k >= 5) or ((i, j) in spots and k >= 4) else (K if k == 1 else R))
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -4, 3))
    head.rbox(-3, 3, -7, -3, 1, 5, K, edges=(True, False, True))
    head.box(-3, -1, -8, -7, 3, 5, W)
    head.box(1, 3, -8, -7, 3, 5, W)
    head.set([(-2, -8, 3), (1, -8, 3)], K)
    parts.append(head)
    ant = Part("EarL", "Head", joint=(1.5, -6, 5))
    ant.set([(1, -6, 5), (1, -7, 6), (2, -8, 7)], K)
    parts += [ant, ant.mirror("EarR")]
    return assemble("Ladybug", parts)


def chipmunk():
    B, D, W, C = "B8743A", "4A2C18", "F6E4C8", "E8A868"
    parts = legs(B, D, 2, -4, 2)
    body = Part("Body")
    body.rbox(-3, 3, -5, 4, 2, 7, lambda i, j, k: W if k == 2 or (j == -5 and k <= 5) else (D if i in (-3, 2) and k >= 4 else (W if i in (-2, 1) and k >= 5 else (D if i in (-1, 0) and k == 6 else B))))
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -5, 6))
    head.rbox(-4, 4, -10, -4, 5, 11, lambda i, j, k: W if (j == -10 and k <= 7) else (D if (k == 10 and i in (-1, 0)) else B), edges=(True, False, True))
    head.box(-4, 4, -10, -8, 6, 8, lambda i, j, k: C if abs(i + 0.5) >= 2.5 else None)    # stuffed cheeks
    eyes(head, -10, 8, xs=(-3, 1))
    head.set([(-3, -10, 10), (2, -10, 10)], W)                      # eye stripes
    head.box(-1, 1, -11, -10, 6, 8, W)
    head.set([(-1, -11, 7), (0, -11, 7)], D)
    parts.append(head)
    ear = Part("EarL", "Head", joint=(2.5, -6.5, 11))
    ear.box(2, 4, -7, -6, 11, 12, B)
    parts += [ear, ear.mirror("EarR")]
    tail = Part("Tail", "Body", joint=(0, 4, 4))
    tail.box(-1, 1, 4, 6, 3, 6, B)
    tail2 = Part("Tail2", "Tail", joint=(0, 5, 6))
    tail2.box(-1, 1, 5, 7, 6, 11, lambda i, j, k: D if j == 6 and k % 2 else B)
    parts += [tail, tail2]
    return assemble("Chipmunk", parts)


def bee():
    Y, K, W, S = "FFC928", "2A2224", "E8F4FF", "F6F0E0"
    parts = []
    body = Part("Body")
    body.rbox(-3, 3, -3, 7, 3, 9, lambda i, j, k: K if j in (0, 1, 4, 5) else Y)
    body.set([(-1, 7, 5), (0, 7, 5), (0, 8, 5)], K)                  # stinger
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -3, 6))
    head.rbox(-3, 3, -7, -2, 3, 9, Y, edges=(True, False, True))
    eyes(head, -7, 5, xs=(-3, 1), w=2, h=3)
    head.set([(-1, -7, 4), (0, -7, 4)], "C88A20")
    parts.append(head)
    ant = Part("EarL", "Head", joint=(1, -5, 9))
    ant.set([(1, -5, 9), (1, -6, 10), (2, -7, 11)], K)
    parts += [ant, ant.mirror("EarR")]
    wing = Part("WingL", "Body", joint=(2, 1, 9))
    for i in range(2, 8):
        for j in range(-1, 5):
            if (i - 4.5) ** 2 / 9 + (j - 1.5) ** 2 / 8 <= 1:
                wing.cells[(i, j, 9)] = W if (i + j) % 3 else S
    parts += [wing, wing.mirror("WingR")]
    leg = Part("LegL", "Body", joint=(1, 0, 3))
    leg.set([(1, -1, 2), (1, 1, 2), (1, 3, 2)], K)
    parts += [leg, leg.mirror("LegR")]
    a = assemble("Bee", parts)
    a.extra["float"] = True
    return a


def snail():
    G, GL, SH, SD, E = "B8C88A", "D8E4B0", "C8803A", "8A4E22", "241A16"
    parts = []
    body = Part("Body")
    body.rbox(-2, 2, -6, 8, 0, 3, lambda i, j, k: GL if k == 0 else G, edges=(True, False, True))
    parts.append(body)
    shell = Part("Shell", "Body", joint=(0, 2, 3))
    def sh(i, j, k):
        r = math.hypot(j - 2.5, k - 7.5)
        return SD if abs((r + math.atan2(k - 7.5, j - 2.5) * 0.9) % 2.4 - 1.2) < 0.45 else SH
    for i in range(-3, 3):
        for j in range(-2, 8):
            for k in range(3, 13):
                if (j - 2.5) ** 2 + (k - 7.5) ** 2 <= 25 and abs(i + 0.5) <= 3 - max(0, abs(j - 2.5) - 3) * 0.5:
                    shell.cells[(i, j, k)] = sh(i, j, k)
    parts.append(shell)
    head = Part("Head", "Body", joint=(0, -6, 2))
    head.rbox(-2, 2, -9, -5, 1, 5, G, edges=(True, False, True))
    head.set([(-1, -9, 2), (0, -9, 2)], shade(G, -0.25))
    parts.append(head)
    for nm, x in (("EarL", 1), ("EarR", -2)):
        st = Part(nm, "Head", joint=(x + 0.5, -7, 5))
        st.set([(x, -7, 5), (x, -7, 6), (x, -8, 7)], G)
        st.set([(x, -8, 8)], E)
        parts.append(st)
    return assemble("Snail", parts)


def fawn(key="Fawn", B="C8823A", W="FAF0E0", D="7A4A22", N="2A1C16", antlers=None, glow=None, spots=True):
    parts = legs(B, D, 7, -6, 4)
    body = Part("Body")
    body.rbox(-3, 3, -7, 7, 7, 12, lambda i, j, k: W if k == 7 or (spots and ((k == 11 and (i * 3 + j) % 5 == 0) or (i in (-3, 2) and k == 10 and j % 3 == 0))) else B)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -6, 11))
    head.box(-2, 2, -8, -5, 11, 15, B)                               # neck
    head.rbox(-3, 3, -12, -6, 14, 19, B, edges=(True, False, False))
    head.box(-2, 2, -14, -12, 14, 16, W)
    head.set([(-1, -14, 16), (0, -14, 16), (-1, -14, 15), (0, -14, 15)], N)
    eyes(head, -12, 17, xs=(-3, 1))
    parts.append(head)
    ear = Part("EarL", "Head", joint=(3, -8, 18))
    ear.box(3, 6, -9, -7, 18, 19, lambda i, j, k: "F2B8A8" if j == -9 and i == 4 else B)
    parts += [ear, ear.mirror("EarR")]
    tail = Part("Tail", "Body", joint=(0, 7, 11))
    tail.box(-1, 1, 7, 8, 10, 12, lambda i, j, k: W if k == 10 else B)
    parts.append(tail)
    if antlers:                                                      # branching antlers
        ant = Part("Antlers_Glow" if glow else "Antlers", "Head", joint=(0, -9, 19), noise=not glow, glow=glow)
        for x, o in ((-2, -1), (1, 1)):
            ant.set([(x, -9, 19), (x, -9, 20), (x + o, -9, 21), (x + o, -9, 22), (x + 2 * o, -9, 23), (x + 2 * o, -9, 24),
                     (x + o, -10, 22), (x + o, -11, 23), (x + 3 * o, -9, 23), (x + 3 * o, -8, 24), (x + 2 * o, -8, 25)], antlers)
        parts.append(ant)
    return assemble(key, parts)


def goose():
    W, G, O, K = "F6F6F2", "D8DCE0", "F28A24", "2A2A2A"
    parts = []
    leg = Part("LegL", "Body", joint=(1.5, 0, 3))
    leg.box(1, 2, -1, 1, 1, 3, O)
    leg.box(0, 3, -3, 1, 0, 1, O)
    parts += [leg, leg.mirror("LegR")]
    body = Part("Body")
    body.rbox(-4, 4, -5, 7, 2, 9, lambda i, j, k: G if k == 2 else W)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -4, 8))
    head.box(-1, 1, -6, -4, 8, 15, W)                                # long neck
    head.rbox(-2, 2, -8, -3, 15, 19, W, edges=(True, False, True))
    head.box(-1, 1, -11, -8, 16, 17, O)
    head.box(-1, 1, -10, -8, 15, 16, shade(O, -0.15))
    eyes(head, -8, 17, xs=(-2, 1), w=1, h=1, shine=False)
    parts.append(head)
    wing = Part("WingL", "Body", joint=(4, 0, 8))
    wing.box(4, 5, -3, 6, 4, 8, lambda i, j, k: G if j >= 4 else W)
    parts += [wing, wing.mirror("WingR")]
    tail = Part("Tail", "Body", joint=(0, 7, 7))
    tail.box(-2, 2, 7, 9, 7, 9, lambda i, j, k: G if j == 8 else W)
    parts.append(tail)
    return assemble("Goose", parts)


def badger():
    G, GD, K, W = "8A8A90", "6A6A70", "1E1E22", "F4F4F0"
    parts = legs(K, K, 3, -6, 4, spread=1)
    body = Part("Body")
    body.rbox(-4, 4, -7, 7, 3, 9, lambda i, j, k: K if k == 3 else (GD if (i + j + k) % 5 == 0 else G))
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -7, 7))
    def face(i, j, k):
        if i in (-1, 0):
            return W
        if i in (-3, -2, 1, 2):
            return K
        return W
    head.rbox(-4, 4, -12, -6, 5, 11, face, edges=(True, False, True))
    head.box(-2, 2, -14, -12, 5, 8, lambda i, j, k: W if i in (-1, 0) else K)
    head.set([(-1, -14, 7), (0, -14, 7)], K)
    head.set([(-3, -12, 9), (2, -12, 9)], SHINE)                     # eyes in the black stripes
    parts.append(head)
    ear = Part("EarL", "Head", joint=(3.5, -8, 11))
    ear.box(3, 5, -9, -8, 10, 11, W)
    parts += [ear, ear.mirror("EarR")]
    tail = Part("Tail", "Body", joint=(0, 7, 7))
    tail.box(-1, 1, 7, 9, 6, 8, G)
    parts.append(tail)
    return assemble("Badger", parts)


def koi():
    O, W, R = "FF7A2A", "FAF6F0", "E8402A"
    def paint(i, j, k, col):
        if col == W:
            return W
        return O if (i // 2 + j // 3 + k // 2) % 3 else (W if (i + j) % 4 == 0 else R)
    a = fishlike("Koi", O, W, 18, 3, fin=R, dorsal=2, snout=2, paint=paint)
    return a


def flamingo():
    P, PL, PD, K, Y = "FF8AB8", "FFB8D4", "E8608E", "2A2224", "FFE8A0"
    parts = []
    leg = Part("LegL", "Body", joint=(1, 0, 10))
    leg.box(0, 2, -1, 1, 1, 10, PD)
    leg.box(0, 2, -3, 1, 0, 1, PD)
    parts += [leg, leg.mirror("LegR")]
    body = Part("Body")
    body.rbox(-3, 3, -4, 6, 10, 16, lambda i, j, k: PL if k == 10 else P)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -3, 15))
    head.box(-1, 1, -5, -3, 15, 18, P)                               # S-shaped neck
    head.box(-1, 1, -4, -2, 18, 22, P)
    head.box(-1, 1, -6, -3, 22, 24, P)
    head.rbox(-2, 2, -8, -3, 24, 28, P, edges=(True, False, True))
    head.box(-1, 1, -10, -8, 25, 27, lambda i, j, k: Y)
    head.box(-1, 1, -12, -10, 24, 26, K)                              # bent black beak tip
    eyes(head, -8, 26, xs=(-2, 1), w=1, h=1)
    parts.append(head)
    wing = Part("WingL", "Body", joint=(3, 0, 15))
    wing.box(3, 4, -3, 6, 11, 15, lambda i, j, k: K if j == 5 else PD)
    parts += [wing, wing.mirror("WingR")]
    tail = Part("Tail", "Body", joint=(0, 6, 13))
    tail.box(-2, 2, 6, 8, 12, 14, PD)
    parts.append(tail)
    return assemble("Flamingo", parts)


def red_panda():
    R, D, W, K = "D8642A", "5A2A1A", "FAF2E6", "2A1C16"
    parts = legs(D, K, 3, -6, 3)
    body = Part("Body")
    body.rbox(-3, 3, -7, 6, 3, 8, lambda i, j, k: D if k == 3 else R)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -7, 7))
    def face(i, j, k):
        if j == -12 and k <= 8:
            return W
        if j == -12 and k in (11, 12) and i in (-4, -3, 2, 3):
            return W                                                 # eyebrow patches
        if j == -12 and k in (9, 10) and i in (-4, 3):
            return D                                                 # tear marks
        return R
    head.rbox(-5, 5, -12, -6, 6, 13, face, edges=(True, False, True))
    head.box(-2, 2, -13, -12, 6, 8, W)
    head.set([(-1, -13, 7), (0, -13, 7)], K)
    eyes(head, -12, 9, xs=(-3, 1))
    parts.append(head)
    ear = Part("EarL", "Head", joint=(3.5, -8, 13))
    ear.box(2, 5, -9, -8, 13, 15, lambda i, j, k: W if (i == 2 or k == 14) else R)
    parts += [ear, ear.mirror("EarR")]
    tail = Part("Tail", "Body", joint=(0, 6, 6))
    tail.rbox(-2, 2, 6, 11, 4, 8, lambda i, j, k: D if j % 3 == 0 else R, edges=(True, False, False))
    tail2 = Part("Tail2", "Tail", joint=(0, 11, 6))
    tail2.rbox(-2, 2, 11, 16, 4, 8, lambda i, j, k: D if j % 3 == 0 else R, edges=(True, False, False))
    parts += [tail, tail2]
    return assemble("RedPanda", parts)


def moss_golem(key="MossGolem", S="8A8C84", SD="6A6C66", M="5AA03A", MD="3E7A2A", F="FF8AC8", E="9AFF6A", aura="Spores"):
    stone = lambda i, j, k: SD if (i * 5 + j * 3 + k * 7) % 9 == 0 else S   # noqa: E731
    mossy = lambda i, j, k: (M if (i + k) % 3 else MD) if k >= 14 else stone(i, j, k)   # noqa: E731
    parts = []
    leg = Part("LegL", "Body", joint=(3, 0, 6))
    leg.box(1, 5, -2, 2, 0, 6, stone)
    parts += [leg, leg.mirror("LegR")]
    body = Part("Body")
    body.rbox(-6, 6, -3, 4, 6, 17, mossy)
    for (x, y, z) in [(-4, -3, 17), (2, -2, 17), (5, 0, 16), (-6, 1, 15), (0, 2, 17)]:
        body.cells[(x, y, z)] = F                                    # little flowers in the moss
    parts.append(body)
    head = Part("Head", "Body", joint=(0, 0, 17))
    head.rbox(-4, 4, -4, 3, 17, 22, lambda i, j, k: (M if (i + j) % 3 else MD) if k == 21 else stone(i, j, k))
    eye_cells = [(x, -4, 19) for x in (-3, -2, 1, 2)]
    for c in eye_cells:
        head.cells.pop(c, None)
    head.set([(-1, -4, 21), (0, -4, 22), (-1, -3, 22), (0, -3, 23)], M)   # sprout
    parts.append(head)
    glow = Part("Eyes_Glow", "Head", joint=(0, -4, 19), noise=False, glow=E)
    glow.set(eye_cells, E)
    parts.append(glow)
    arm = Part("ArmL", "Body", joint=(7, 0, 16))
    arm.rbox(6, 10, -2, 2, 3, 17, mossy, edges=(False, False, True))
    parts += [arm, arm.mirror("ArmR")]
    a = assemble(key, parts)
    a.extra["aura"] = aura
    return a


def pegasus():
    W, H, G, B, BL = "FAFAFF", "D8D4E8", "FFD54A", "C8DCFF", "8AB8FF"
    parts = legs(W, G, 7, -7, 5)
    for p in parts:
        for c in list(p.cells):
            if c[2] <= 1:
                p.cells[c] = G                                       # golden hooves
    body = Part("Body")
    body.rbox(-3, 3, -8, 8, 7, 13, W)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -7, 12))
    head.box(-2, 2, -9, -5, 11, 17, W)
    head.rbox(-3, 3, -13, -7, 16, 21, W, edges=(True, False, False))
    head.box(-2, 2, -15, -13, 16, 19, H)
    head.set([(-2, -15, 17), (1, -15, 17)], shade(H, -0.3))
    eyes(head, -13, 19, xs=(-3, 1), shine=False)
    parts.append(head)
    mane = Part("Mane", "Head", joint=(0, -6, 17))
    mane.box(-1, 1, -8, -4, 12, 22, lambda i, j, k: None if (j == -8 and k < 20) else (BL if (k + j) % 3 == 0 else B))
    parts.append(mane)
    ear = Part("EarL", "Head", joint=(2, -8.5, 21))
    ear.box(1, 3, -9, -8, 21, 23, W)
    parts += [ear, ear.mirror("EarR")]
    wing = Part("WingL", "Body", joint=(3, -3, 12))
    for d in range(10):                                              # big feathered wing
        for j in range(-5, 3 - d // 3):
            wing.cells[(3 + d, j, 12 + d // 3)] = G if j == 2 - d // 3 else (BL if d >= 7 else (B if d >= 4 and (j + d) % 2 == 0 else W))
    parts += [wing, wing.mirror("WingR")]
    tail = Part("Tail", "Body", joint=(0, 8, 11))
    tail.box(-1, 1, 8, 10, 9, 13, B)
    tail2 = Part("Tail2", "Tail", joint=(0, 9.5, 9))
    tail2.box(-1, 1, 9, 12, 4, 10, lambda i, j, k: BL if k % 2 else B)
    parts += [tail, tail2]
    a = assemble("Pegasus", parts)
    a.extra["float"] = True
    a.extra["aura"] = "GoldDust"
    return a


# ------------------------------------------------------- Beach extras (3 per rarity)


def starfish():
    O, OD, OL = "F2843A", "C85A22", "FFC08A"
    parts = []
    body = Part("Body")
    body.rbox(-3, 3, -3, 3, 0, 3, lambda i, j, k: OL if (i + j) % 3 == 0 and k == 2 else O)
    eyes(body, -4, 1, xs=(-2, 1), w=1, h=1)
    body.set([(-1, -4, 0), (0, -4, 0)], OD)
    parts.append(body)
    for n in range(5):
        a = math.radians(90 + n * 72)
        dx, dy = math.cos(a), -math.sin(a)
        arm = Part(f"Arm{n + 1}", "Body", joint=(dx * 2.5, dy * 2.5, 1))
        for t in [x / 2 for x in range(4, 15)]:
            x, y = round(dx * t - 0.5), round(dy * t - 0.5)
            w = 1 if t > 5 else 2
            for ox in range(w):
                for oy in range(w):
                    arm.cells[(x + ox, y + oy, 0)] = OL if (int(t) % 2 == 0 and ox == 0) else O
                    if t < 5:
                        arm.cells[(x + ox, y + oy, 1)] = O
        parts.append(arm)
    return assemble("Starfish", parts)


def clownfish():
    O, W, K = "FF7A1E", "FAFAF6", "1E1A1E"
    def paint(i, j, k, col):
        band = j % 6
        if band in (0, 1):
            return W
        if band in (2, 5) and abs(i + 0.5) >= 1:
            return K
        return O
    return fishlike("Clownfish", O, O, 14, 3, fin=O, dorsal=2, snout=2, paint=paint)


def pelican():
    return bird("Pelican", "F4F4F0", "FAFAF6", "B8BCC4", "F2B84A", "E8A040", head_col="FAFAF6", size=(3, 5, 6), beak_len=5, tail_len=2)


def sea_turtle():
    G, GD, S, SD, Y = "6AB89A", "3E8A6E", "8A6A3A", "5A4224", "E8DCA0"
    parts = []
    for name, x0, y0, big in (("LegFL", 4, -5, True), ("LegFR", -8, -5, True), ("LegBL", 3, 3, False), ("LegBR", -6, 3, False)):
        p = Part(name, "Body", joint=(x0 + (0 if x0 > 0 else (4 if big else 3)), y0 + 1, 3))
        p.box(x0, x0 + (4 if big else 3), y0, y0 + (3 if big else 2), 2, 3, lambda i, j, k: GD if (i + j) % 3 == 0 else G)
        parts.append(p)
    def shell(i, j, k):
        if k == 2:
            return Y
        return SD if (i % 3 == 0 or j % 3 == 0) else S
    body = Part("Body")
    body.rbox(-4, 4, -6, 6, 2, 6, shell)
    body.rbox(-3, 3, -4, 4, 6, 7, shell, edges=(False, False, True))
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -6, 4))
    head.rbox(-2, 2, -10, -5, 2, 6, lambda i, j, k: GD if (i + j + k) % 4 == 0 else G, edges=(True, False, False))
    eyes(head, -10, 4, xs=(-2, 1), w=1, h=1)
    parts.append(head)
    a = assemble("SeaTurtle", parts)
    a.extra["float"] = True
    return a


def octopus():
    return kraken("Octopus", R="9A5AD8", RD="6A3A9A", SP="C89AF2", Y="FFE27A", SU="E8C8FF", aura=None)


def pufferfish():
    Y, YD, W, K, F = "F2D24A", "C8A030", "FAF4DC", "4A3A20", "FFAA3A"
    parts = []
    body = Part("Body")
    for i in range(-5, 5):
        for j in range(-5, 5):
            for k in range(2, 12):
                d = (i + 0.5) ** 2 + (j + 0.5) ** 2 + (k - 6.5) ** 2
                if d <= 25:
                    body.cells[(i, j, k)] = W if k <= 4 else (YD if (i * 3 + j * 5 + k) % 7 == 0 else Y)
    for (i, j, k) in [(-6, -1, 7), (5, 0, 8), (-1, 5, 8), (0, -1, 12), (-3, 2, 11), (2, -3, 11), (-6, 2, 5), (5, -3, 5), (3, 3, 10), (-4, -3, 10)]:
        body.cells[(i, j, k)] = K                                    # spikes
    eyes(body, -6, 7, xs=(-4, 2), w=2, h=2)
    body.set([(-1, -6, 5), (0, -6, 5)], F)                           # little mouth
    parts.append(body)
    fin = Part("WingL", "Body", joint=(5, -1, 6))
    fin.box(5, 6, -1, 2, 5, 8, F)
    parts += [fin, fin.mirror("WingR")]
    tail = Part("Tail", "Body", joint=(0, 5, 7))
    tail.box(-1, 1, 5, 7, 6, 8, F)
    tail.box(-2, 2, 7, 8, 5, 9, F)
    parts.append(tail)
    a = assemble("Pufferfish", parts)
    a.extra["float"] = True
    return a


def walrus():
    B, BD, T, N, K = "A8784E", "8A5E3A", "F6EEDA", "6A4A32", "241A16"
    parts = []
    body = Part("Body")
    body.rbox(-5, 5, -7, 8, 0, 9, lambda i, j, k: BD if (i * 3 + j * 5 + k * 7) % 11 == 0 else B)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -6, 8))
    head.rbox(-4, 4, -11, -5, 5, 12, B, edges=(True, False, True))
    head.rbox(-4, 4, -13, -11, 5, 9, lambda i, j, k: N if (i + k) % 2 else B)   # whiskered muzzle
    head.set([(-3, -13, 4), (-3, -13, 3), (-3, -13, 2), (2, -13, 4), (2, -13, 3), (2, -13, 2), (-3, -12, 4), (2, -12, 4)], T)   # tusks
    eyes(head, -11, 10, xs=(-3, 2), w=1, h=1)
    parts.append(head)
    for name, x0 in (("LegFL", 5), ("LegFR", -8)):
        f = Part(name, "Body", joint=(x0 + (0 if x0 > 0 else 3), -3, 1))
        f.box(x0, x0 + 3, -5, -1, 0, 1, BD)
        parts.append(f)
    tail = Part("Tail", "Body", joint=(0, 8, 1))
    tail.box(-4, -1, 8, 11, 0, 1, BD)
    tail.box(1, 4, 8, 11, 0, 1, BD)
    tail.box(-1, 1, 8, 9, 0, 2, B)
    parts.append(tail)
    return assemble("Walrus", parts)


def manta_ray():
    D, DL, W, C = "2A3A5A", "3E5A82", "F2F6FA", "6AE8FF"
    parts = []
    body = Part("Body")
    body.rbox(-3, 3, -5, 6, 2, 5, lambda i, j, k: W if k == 2 else D)
    eyes(body, -6, 3, xs=(-3, 2), w=1, h=1)
    body.box(-3, -1, -7, -5, 2, 4, D)                               # head fins
    body.box(1, 3, -7, -5, 2, 4, D)
    parts.append(body)
    wing = Part("WingL", "Body", joint=(3, 0, 3))
    for d in range(1, 11):
        for j in range(-5 + d // 2, 5 - d // 3):
            wing.cells[(2 + d, j, 3)] = C if (d in (4, 7) and j % 2 == 0) else (DL if (j + d) % 4 == 0 else D)
    parts += [wing, wing.mirror("WingR")]
    tail = Part("Tail", "Body", joint=(0, 6, 3))
    tail.set([(0, 6 + n, 3) for n in range(9)] + [(-1, 6 + n, 3) for n in range(4)], D)
    parts.append(tail)
    a = assemble("MantaRay", parts)
    a.extra["float"] = True
    return a


def orca():
    K, W = "1E2028", "F8F8FA"
    def paint(i, j, k, col):
        if j in (-8, -7, -6) and k == 2 and abs(i + 0.5) >= 2:
            return W                                                 # eye patch
        return col
    return fishlike("Orca", K, W, 28, 5, dorsal=4, snout=3, paint=paint)


def narwhal():
    B, BL, H = "7A8EA8", "D8E0EA", "F6F0DC"
    def paint(i, j, k, col):
        return shade(col, -0.18) if col == B and (i * 5 + j * 3 + k * 7) % 6 == 0 else col
    return fishlike("Narwhal", B, BL, 24, 4, dorsal=0, snout=3, paint=paint, horn=H)


def coral_dragon():
    return sea_serpent("CoralDragon", T="FF6A6A", TD="D8404A", G="FFC26A", B="FFE0D0", I="FFF07A", aura="Bubbles", coral="FF8AC8")


def golden_seahorse():
    G, GD, GL, F, K = "F2C232", "C8962A", "FFE88A", "FF9A3A", "241A16"
    parts = []
    body = Part("Body")
    body.rbox(-3, 3, -3, 3, 6, 15, lambda i, j, k: GL if j == -3 and k <= 12 else (GD if k % 3 == 0 else G), edges=(True, True, False))
    body.set([(0, 3, k) for k in range(8, 15)] + [(-1, 3, k) for k in range(8, 15)], F)     # back fin
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -1, 15))
    head.rbox(-3, 3, -4, 2, 15, 20, G, edges=(True, False, True))
    head.box(-1, 1, -8, -4, 16, 18, G)                              # long snout
    head.set([(-1, -2, 20), (0, -1, 20), (-1, 0, 21), (0, 1, 21), (-1, 1, 22)], F)        # crown
    eyes(head, -4, 18, xs=(-3, 2), w=1, h=1)
    parts.append(head)
    tail = Part("Tail", "Body", joint=(0, 0, 6))
    tail.box(-2, 2, -1, 2, 3, 6, G)
    tail2 = Part("Tail2", "Tail", joint=(0, 1, 3))
    tail2.set([(x, 1, 2) for x in (-1, 0)] + [(x, 2, 1) for x in (-1, 0)] + [(x, 3, 1) for x in (-1, 0)] + [(x, 4, 2) for x in (-1, 0)] + [(x, 4, 3) for x in (-1, 0)] + [(x, 3, 3) for x in (-1, 0)], GD)
    parts += [tail, tail2]
    a = assemble("GoldenSeahorse", parts)
    a.extra["float"] = True
    a.extra["aura"] = "GoldDust"
    return a


# -------------------------------------------------------- City extras (3 per rarity)


def alley_cat():
    return cat("AlleyCat", O="8A8C96", S="4E5058", C="D8DADE", P="E89AA8", B="C8A0A8")


def hamster(key="Hamster", G="F2B05A", W="FFF4E0", P="FFB0C0"):
    parts = []
    for name, x0, y0 in (("LegFL", 1, -3), ("LegFR", -3, -3), ("LegBL", 1, 2), ("LegBR", -3, 2)):
        p = Part(name, "Body", joint=(x0 + 1, y0 + 1, 1))
        p.box(x0, x0 + 2, y0, y0 + 2, 0, 1, P)
        parts.append(p)
    body = Part("Body")
    body.rbox(-4, 4, -4, 5, 1, 8, lambda i, j, k: W if (k <= 3 or (j == -4 and k <= 5)) else G)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -3, 6))
    head.rbox(-4, 4, -8, -2, 4, 10, lambda i, j, k: W if (j == -8 and k <= 6) else G, edges=(True, False, True))
    head.box(-5, 5, -7, -4, 4, 7, lambda i, j, k: W if abs(i + 0.5) >= 3.5 else None)     # chubby cheeks
    eyes(head, -8, 7, xs=(-3, 2), w=1, h=2)
    head.set([(-1, -8, 6), (0, -8, 6)], P)
    head.set([(-1, -8, 5), (0, -8, 5)], "FFFFFF")
    parts.append(head)
    ear = Part("EarL", "Head", joint=(2.5, -5, 10))
    ear.box(2, 4, -5, -4, 10, 11, lambda i, j, k: P if i == 2 else G)
    parts += [ear, ear.mirror("EarR")]
    return assemble(key, parts)


def crow():
    return bird("Crow", "2A2A36", "3A3A48", "22222E", "4A4A56", "3A3A40", size=(3, 4, 5), tail_len=3)


def pug():
    F, M, K, P = "E2C08E", "3A2E2A", "241A16", "FF7A8E"
    parts = legs(F, F, 3, -5, 3, spread=0)
    body = Part("Body")
    body.rbox(-4, 4, -6, 5, 3, 9, F)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -6, 8))
    head.rbox(-4, 4, -11, -5, 7, 14, lambda i, j, k: M if (j == -11 and k <= 10 and -3 <= i <= 2) else (shade(F, -0.15) if (k == 12 and j == -11) else F))
    head.box(-2, 2, -12, -11, 7, 10, M)                              # squished black muzzle
    head.set([(-1, -12, 9), (0, -12, 9)], K)
    head.set([(-1, -12, 7), (0, -12, 7)], P)
    for x0 in (-4, 2):                                               # big round eyes
        head.box(x0, x0 + 2, -12, -11, 10, 12, K)
        head.set([(x0 if x0 < 0 else x0 + 1, -12, 11)], SHINE)
    parts.append(head)
    ear = Part("EarL", "Head", joint=(4, -8, 14))
    ear.set([(3, -8, 14), (4, -8, 14), (4, -8, 13)], M)
    parts += [ear, ear.mirror("EarR")]
    tail = Part("Tail", "Body", joint=(0, 5, 8))
    tail.set([(-1, 5, 8), (0, 5, 9), (-1, 5, 10), (0, 4, 10), (-1, 4, 9)], F)    # curly tail
    parts.append(tail)
    return assemble("Pug", parts)


def dalmatian():
    return dog("Dalmatian", T="F8F8F6", C="FFFFFF", E="2A2A2E", N="1E1E22", spots="2A2A2E")


def parrot():
    return bird("Parrot", "E8382A", "F2D23A", "2A7AE8", "F2F2E8", "8A8A8A", crest="E8382A", tail_len=5)


def police_dog():
    return dog("PoliceDog", T="C8884A", C="E8C89A", E="2A2420", N="1E1A18", saddle="2A2420", ears_up=True)


def neon_cat():
    a = cat("NeonCat", O="2A2442", S="FF3AD8", C="4A4270", P="5AF0FF", B="FF3AD8")
    a.extra["aura"] = "Sparks"
    return a


def cyber_wolf():
    return arctic_wolf("CyberWolf", W="4A5262", G="2E343E", B="8A96A8", N="1A1E24", I="FF3A4A")


def jetpack_monkey():
    B, BL, F, M, J, FL = "8A5A32", "F2D8B0", "F2D8B0", "6A4024", "9AA4B0", "FF9A2A"
    parts = []
    leg = Part("LegL", "Body", joint=(2, 0, 5))
    leg.box(1, 3, -1, 1, 1, 5, B)
    leg.box(1, 3, -2, 1, 0, 1, M)
    parts += [leg, leg.mirror("LegR")]
    body = Part("Body")
    body.rbox(-4, 4, -3, 3, 5, 12, lambda i, j, k: BL if (j == -3 and 6 <= k <= 10 and -2 <= i <= 1) else B)
    parts.append(body)
    pack = Part("Jetpack", "Body", joint=(0, 3, 9))
    pack.box(-4, -1, 3, 6, 5, 11, lambda i, j, k: shade(J, -0.2) if k in (5, 10) else J)
    pack.box(1, 4, 3, 6, 5, 11, lambda i, j, k: shade(J, -0.2) if k in (5, 10) else J)
    pack.box(-1, 1, 3, 5, 7, 10, "E83A3A")
    parts.append(pack)
    flame = Part("Flame_Glow", "Jetpack", joint=(0, 4.5, 5), noise=False, glow=FL)
    flame.set([(x, y, z) for x in (-3, -2, 2, 3) for y in (4,) for z in (3, 4)] + [(x, 4, 2) for x in (-3, 2)], FL)
    parts.append(flame)
    head = Part("Head", "Body", joint=(0, 0, 12))
    head.rbox(-4, 4, -4, 3, 12, 18, B)
    head.rbox(-3, 3, -5, -3, 12, 17, F, edges=(True, False, True))   # face
    eyes(head, -5, 15, xs=(-3, 1))
    head.set([(-1, -5, 13), (0, -5, 13)], M)
    head.box(-4, 4, -5, -4, 17, 18, "5A6070")                      # goggles strap
    head.set([(-3, -5, 17), (-2, -5, 17), (1, -5, 17), (2, -5, 17)], "8AE8FF")
    parts.append(head)
    ear = Part("EarL", "Head", joint=(4, -1, 15))
    ear.box(4, 5, -2, 0, 14, 16, F)
    parts += [ear, ear.mirror("EarR")]
    arm = Part("ArmL", "Body", joint=(4.5, 0, 11))
    arm.box(4, 6, -1, 1, 5, 12, B)
    arm.box(4, 6, -1, 1, 4, 5, F)
    parts += [arm, arm.mirror("ArmR")]
    tail = Part("Tail", "Body", joint=(0, 3, 6))
    tail.set([(-1, 3, 6), (-1, 4, 6), (-1, 5, 7), (-1, 6, 8), (-1, 6, 9), (-1, 5, 10)], B)
    parts.append(tail)
    a = assemble("JetpackMonkey", parts)
    a.extra["float"] = True
    return a


def neon_dragon():
    return dragon("NeonDragon", R="2A2A4A", D="FF3AD8", B="5AF0FF", C="5AF0FF", M="7A3AE8", aura="Sparks")


def golden_lion():
    a = lion("GoldenLion", G="F2C232", M="D89A1E", MD="A8701A", L="FFE89A", N="8A5A1A")
    a.extra["aura"] = "GoldDust"
    return a


# ------------------------------------------------- Snowy Peaks extras (3 per rarity)


def arctic_fox():
    return fox("ArcticFox", O="F4F6FA", W="FFFFFF", D="8A96A8")


def lemming():
    return hamster("Lemming", G="8A5A3A", W="E8D8C0", P="F2A8B0")


def puffin():
    return bird("Puffin", "22222A", "FAFAF6", "1E1E26", "F2782A", "F2782A", head_col="F4F4F0", size=(3, 4, 5), beak_len=2)


def husky():
    return dog("Husky", T="F6F6F8", C="FFFFFF", E="5A6270", N="1E1E22", saddle="6A7282", ears_up=True)


def reindeer():
    a = fawn("Reindeer", B="8A5E3A", W="E8DCC8", D="4A3020", N="E8322E", antlers="C8A878", spots=False)
    return a


def musk_ox():
    F, FD, H, L = "5A3E2A", "3E2A1C", "D8CCB0", "8A7A68"
    shag = lambda i, j, k: FD if (i * 5 + j * 3 + k * 7) % 7 == 0 else F    # noqa: E731
    parts = legs(L, FD, 4, -6, 4, spread=1)
    body = Part("Body")
    body.rbox(-5, 5, -7, 7, 3, 11, shag)
    body.rbox(-3, 3, -6, 2, 11, 13, shag)                             # hump
    for c in [c for c in body.cells if c[2] <= 4 and (c[0] + c[1]) % 2 == 0]:
        body.cells[c] = FD                                           # long fringe
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -7, 9))
    head.rbox(-3, 3, -12, -6, 5, 11, shag, edges=(True, False, True))
    head.box(-2, 2, -13, -12, 5, 8, L)
    eyes(head, -12, 9, xs=(-3, 2), w=1, h=1)
    for x, o in ((-4, -1), (3, 1)):                                  # horns curving down and out
        head.set([(x, -9, 11), (x + o, -9, 11), (x + o, -9, 10), (x + o, -10, 9), (x + 2 * o, -10, 8), (x + 2 * o, -11, 8)], H)
    head.box(-3, 3, -9, -7, 11, 12, H)                               # horn boss
    parts.append(head)
    tail = Part("Tail", "Body", joint=(0, 7, 9))
    tail.box(-1, 1, 7, 8, 7, 10, FD)
    parts.append(tail)
    return assemble("MuskOx", parts)


def polar_bear():
    W, WS, K, B = "F6F6F2", "D8DCE0", "241A16", "E8E0D0"
    parts = legs(W, WS, 4, -7, 5, spread=1)
    body = Part("Body")
    body.rbox(-5, 5, -8, 8, 4, 12, lambda i, j, k: WS if (i * 3 + j * 5 + k * 7) % 13 == 0 else W)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -8, 10))
    head.rbox(-4, 4, -13, -7, 8, 14, W, edges=(True, False, True))
    head.box(-2, 2, -15, -13, 8, 11, B)
    head.set([(-1, -15, 10), (0, -15, 10)], K)
    head.set([(-1, -15, 8), (0, -15, 8)], WS)
    eyes(head, -13, 11, xs=(-3, 2), w=1, h=1)
    parts.append(head)
    ear = Part("EarL", "Head", joint=(3, -9, 14))
    ear.box(2, 4, -10, -9, 14, 15, W)
    parts += [ear, ear.mirror("EarR")]
    tail = Part("Tail", "Body", joint=(0, 8, 10))
    tail.box(-1, 1, 8, 9, 9, 11, W)
    parts.append(tail)
    return assemble("PolarBear", parts)


def frost_bat():
    D, M, I, E, P = "4A4A6A", "6A7AA8", "B8F0FF", "8AF0FF", "F2A8C8"
    parts = []
    body = Part("Body")
    body.rbox(-3, 3, -3, 4, 3, 9, lambda i, j, k: shade(D, 0.15) if j == -3 else D)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -2, 9))
    head.rbox(-3, 3, -5, 1, 8, 13, D, edges=(True, False, True))
    eye_cells = [(x, -5, 11) for x in (-2, 1)]
    for c in eye_cells:
        head.cells.pop(c, None)
    head.set([(-1, -5, 9), (0, -5, 9)], P)
    head.set([(-2, -5, 8), (1, -5, 8)], "FFFFFF")                    # fangs
    parts.append(head)
    glow = Part("Eyes_Glow", "Head", joint=(0, -5, 11), noise=False, glow=E)
    glow.set(eye_cells, E)
    parts.append(glow)
    ear = Part("EarL", "Head", joint=(2, -2, 13))
    ear.box(1, 3, -3, -1, 13, 16, lambda i, j, k: P if i == 1 and k < 15 else D)
    parts += [ear, ear.mirror("EarR")]
    wing = Part("WingL", "Body", joint=(3, 0, 8))
    for d in range(11):
        for j in range(-3, 4 - (d % 4 == 3) * 2 - d // 4):
            wing.cells[(3 + d, j, 8 + d // 4)] = D if (j == -3 or d in (0, 4, 8)) else (I if d >= 8 else M)
    parts += [wing, wing.mirror("WingR")]
    leg = Part("LegL", "Body", joint=(1.5, 2, 3))
    leg.box(1, 2, 2, 3, 1, 3, D)
    parts += [leg, leg.mirror("LegR")]
    a = assemble("FrostBat", parts)
    a.extra["float"] = True
    a.extra["aura"] = "Frost"
    return a


def woolly_rhino():
    F, FD, H, K = "7A5A3E", "5A402A", "E8E0CC", "241A16"
    shag = lambda i, j, k: FD if (i * 5 + j * 3 + k * 7) % 7 == 0 else F    # noqa: E731
    parts = legs(FD, K, 5, -7, 5, spread=1)
    body = Part("Body")
    body.rbox(-5, 5, -8, 8, 5, 14, shag)
    body.rbox(-4, 4, -7, 0, 14, 16, shag)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -8, 11))
    head.rbox(-3, 3, -15, -7, 6, 12, shag, edges=(True, False, True))
    head.box(-1, 1, -15, -13, 12, 17, H)                             # big front horn
    head.box(-1, 1, -16, -15, 15, 18, H)
    head.box(-1, 1, -12, -10, 12, 14, H)                             # small horn
    eyes(head, -11, 10, xs=(-4, 3), w=1, h=1)
    parts.append(head)
    ear = Part("EarL", "Head", joint=(3, -8, 12))
    ear.box(2, 4, -8, -7, 12, 14, F)
    parts += [ear, ear.mirror("EarR")]
    tail = Part("Tail", "Body", joint=(0, 8, 12))
    tail.box(-1, 1, 8, 9, 9, 12, FD)
    parts.append(tail)
    return assemble("WoollyRhino", parts)


def crystal_stag():
    a = fawn("CrystalStag", B="B8D8F2", W="F2FAFF", D="6A8AB8", N="4A6A9A", antlers="8AF0FF", glow="8AF0FF", spots=False)
    a.extra["aura"] = "Frost"
    return a


def ice_dragon():
    return dragon("IceDragon", R="8AC8F2", D="3A6AB8", B="E8F8FF", C="FFFFFF", M="B8E8FF", aura="Frost")


def glacier_titan():
    return moss_golem("GlacierTitan", S="A8D0E8", SD="7AA8D0", M="FAFCFF", MD="D8E8F4", F="8AF0FF", E="5AF0FF", aura="Snowfall")


# ---------------------------------------------------------------- daily-streak exclusives
# One per finished 7-day login streak (Capybara, Axolotl, Sloth, Chameleon). Never in eggs.


def capybara():
    T, TD, M, N, Y, O = "B5824A", "8E6236", "7A5232", "3A2A1E", "FFD84A", "F28A1E"
    # tan fur, darker fur, muzzle, nose, petals, flower centre
    fur = lambda i, j, k: TD if (i * 5 + j * 3 + k * 7) % 11 == 0 else T    # noqa: E731
    parts = legs(T, TD, 3, -6, 4, spread=1)
    body = Part("Body")
    body.rbox(-5, 5, -6, 8, 3, 11, fur)
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -6, 9))
    head.rbox(-4, 4, -11, -6, 7, 14, fur, edges=(True, False, False))
    head.box(-4, 4, -15, -11, 7, 12, lambda i, j, k: M if j == -15 or k == 7 else T)     # long blunt snout
    head.set([(-2, -15, 10), (1, -15, 10)], N)                                         # nostrils
    head.set([(-1, -15, 8), (0, -15, 8)], N)                                           # mouth
    eyes(head, -12, 12, xs=(-4, 2), w=2, h=1, shine=False)                             # sleepy calm eyes
    parts.append(head)
    ear = Part("EarL", "Head", joint=(3, -6, 14))
    ear.box(2, 4, -7, -5, 14, 15, TD)
    parts += [ear, ear.mirror("EarR")]
    flower = Part("Flower", "Head", joint=(0, -8, 14))              # a sunflower on its head
    for (i, j) in [(-2, -9), (-2, -8), (1, -9), (1, -8), (-1, -10), (0, -10), (-1, -7), (0, -7)]:
        flower.cells[(i, j, 14)] = Y
    for (i, j) in [(-2, -10), (1, -10), (-2, -7), (1, -7)]:
        flower.cells[(i, j, 14)] = shade(Y, -0.12)
    parts.append(flower)
    centre = Part("FlowerCentre_Glow", "Flower", joint=(0, -8, 14), noise=False, glow=O)
    centre.set([(-1, -9, 14), (0, -9, 14), (-1, -8, 14), (0, -8, 14)], O)
    parts.append(centre)
    a = assemble("Capybara", parts)
    a.extra["aura"] = "Petals"
    return a


def axolotl():
    P, PB, PD, M = "FFA6C8", "FFD6E6", "E87AA8", "B84A7A"
    GILLS = ("FF4A5A", "FF9A2A", "FFE04A"), ("5AD86A", "4AA8FF", "A86AFF")
    parts = legs(P, PD, 2, -4, 3, spread=1)
    body = Part("Body")
    body.rbox(-3, 3, -5, 7, 2, 7, lambda i, j, k: PB if k == 2 else (PD if (i + j) % 7 == 0 and k == 6 else P))
    body.box(-1, 1, -3, 6, 7, 8, PD)                                 # back ridge
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -5, 4))
    head.rbox(-5, 5, -10, -5, 2, 8, lambda i, j, k: PB if k == 2 else P)
    eyes(head, -10, 5, xs=(-4, 2), w=2, h=2)
    head.set([(-2, -10, 3), (1, -10, 3), (-1, -10, 2), (0, -10, 2)], M)             # smile
    head.set([(-4, -10, 4), (3, -10, 4)], "FF7AA8")                                  # blush
    parts.append(head)
    for side, cols in (("L", GILLS[0]), ("R", GILLS[1])):            # three rainbow gill stalks a side
        g = Part(f"Gill{side}", "Head", joint=((5 if side == "L" else -5), -7, 6))
        for n, (y, col) in enumerate(zip((-9, -7, -5), cols)):
            for d in range(4):
                x = 5 + d if side == "L" else -6 - d
                g.cells[(x, y, 4 + n + d)] = col if d < 3 else shade(col, 0.35)
        parts.append(g)
    tail = Part("Tail", "Body", joint=(0, 7, 4))
    tail.box(-1, 1, 7, 11, 3, 6, P)
    tail.box(-1, 1, 7, 11, 6, 8, lambda i, j, k: PB if k == 7 and j % 2 else PD)     # fin on top
    tail2 = Part("Tail2", "Tail", joint=(0, 11, 4))
    tail2.box(-1, 1, 11, 15, 3, 5, P)
    tail2.box(-1, 1, 11, 15, 5, 8, lambda i, j, k: None if k - 5 > 14 - j else (PB if (j + k) % 2 else PD))
    parts += [tail, tail2]
    a = assemble("Axolotl", parts)
    a.extra["aura"] = "Bubbles"
    return a


def sloth():
    B, BD, F, D, C, H, HW = "8A6A4A", "6E5236", "E8D4B0", "4A3424", "F0E6D0", "4A6AD8", "FFFFFF"
    # fur, dark fur, face, eye patch, claws, nightcap blue, nightcap white
    fur = lambda i, j, k: BD if (i * 3 + j * 5 + k * 7) % 10 == 0 else B    # noqa: E731
    parts = []
    leg = Part("LegL", "Body", joint=(2.5, 0, 4))
    leg.box(1, 4, -2, 2, 0, 4, lambda i, j, k: C if k == 0 and j == -2 else fur(i, j, k))
    parts += [leg, leg.mirror("LegR")]
    body = Part("Body")
    body.rbox(-5, 5, -3, 4, 4, 15, lambda i, j, k: shade(F, -0.08) if j == -3 and abs(i + 0.5) < 3 and 6 <= k <= 12 else fur(i, j, k))
    parts.append(body)
    head = Part("Head", "Body", joint=(0, 0, 15))

    def face(i, j, k):
        if j == -5:
            if k in (18, 19) and i in (-4, -3, -2, 1, 2, 3):
                return D                                             # dark eye stripes
            if 16 <= k <= 21 and abs(i + 0.5) <= 3.5:
                return F
        return fur(i, j, k)
    head.rbox(-5, 5, -5, 4, 15, 23, face)
    head.set([(-3, -5, 18), (-2, -5, 18), (1, -5, 18), (2, -5, 18)], EYE)            # sleepy closed eyes
    head.set([(-1, -6, 17), (0, -6, 17)], D)                                         # nose
    head.set([(-2, -5, 16), (-1, -5, 16), (0, -5, 16), (1, -5, 16)], shade(F, -0.25))   # smile
    parts.append(head)
    cap = Part("Cap", "Head", joint=(0, -1, 23))                     # striped nightcap
    cap.box(-5, 5, -5, 4, 23, 24, HW)
    stripe = lambda k: HW if k % 3 == 0 else H                       # noqa: E731
    cap.box(-4, 4, -4, 3, 24, 26, lambda i, j, k: stripe(k))
    cap.box(-3, 3, -3, 2, 26, 28, lambda i, j, k: stripe(k))
    parts.append(cap)
    tip = Part("CapTip", "Cap", joint=(0, -1, 28))                   # floppy tip with a pom-pom
    tip.box(-2, 2, -2, 1, 28, 30, lambda i, j, k: stripe(k))
    tip.box(1, 4, -2, 1, 29, 30, H)
    tip.box(3, 5, -2, 1, 27, 29, lambda i, j, k: HW if k == 27 else H)
    tip.box(4, 7, -2, 1, 24, 27, HW)
    parts.append(tip)
    arm = Part("ArmL", "Body", joint=(6, 0, 14))                     # long arms with cream claws
    arm.rbox(5, 8, -2, 2, 5, 15, fur, edges=(False, False, True))
    arm.set([(5, -2, 4), (6, -2, 4), (7, -2, 4), (5, -2, 3), (7, -2, 3)], C)
    parts += [arm, arm.mirror("ArmR")]
    a = assemble("Sloth", parts)
    a.extra["aura"] = "Leaves"
    return a


def chameleon():
    G, GD, GL, K = "F2C23A", "C8901E", "FFE88A", "FFF6C0"
    # gold, dark gold, light gold, sparkle
    scale = lambda i, j, k: GD if (i * 5 + j * 3 + k * 7) % 9 == 0 else G   # noqa: E731
    parts = legs(G, GD, 4, -4, 3, spread=1)
    body = Part("Body")
    body.rbox(-3, 3, -5, 6, 4, 11, lambda i, j, k: GL if k == 4 else scale(i, j, k))
    body.box(-1, 1, -4, 5, 11, 12, lambda i, j, k: GD if j % 2 else None)           # spiky ridge
    parts.append(body)
    head = Part("Head", "Body", joint=(0, -5, 8))
    head.rbox(-3, 3, -10, -5, 5, 11, lambda i, j, k: GL if k == 5 else scale(i, j, k), edges=(True, False, False))
    head.box(-2, 2, -8, -5, 11, 13, lambda i, j, k: GD if k == 12 else G)          # helmet casque
    head.set([(-2, -10, 6), (-1, -10, 6), (0, -10, 6), (1, -10, 6)], GD)            # long smile
    parts.append(head)
    eye = Part("EyeL", "Head", joint=(3, -8, 9))                     # bulging turret eyes
    eye.box(3, 4, -9, -6, 8, 11, lambda i, j, k: GL if (j, k) != (-8, 9) else None)
    eye.set([(4, -8, 9)], GL)
    eye.set([(4, -9, 9)], EYE)
    eyeR = eye.mirror("EyeR")
    parts += [eye, eyeR]
    tail = Part("Tail", "Body", joint=(0, 6, 7))
    tail.box(-1, 1, 6, 9, 6, 8, scale)
    tail2 = Part("Tail2", "Tail", joint=(0, 9, 6))                   # curled tail
    for (j, k) in [(9, 7), (10, 7), (11, 6), (11, 5), (11, 4), (10, 3), (9, 3), (8, 4), (8, 5), (9, 5)]:
        for i in (-1, 0):
            tail2.cells[(i, j, k)] = scale(i, j, k)
    parts += [tail, tail2]
    sparkle = Part("Sparkle_Glow", "Body", joint=(0, 0, 11), noise=False, glow=K)
    sparkle.set([(-1, -2, 11), (0, 0, 11), (-1, 2, 11), (0, 4, 11)], K)
    for c in sparkle.cells:
        body.cells.pop(c, None)
    parts.append(sparkle)
    a = assemble("Chameleon", parts)
    a.extra["aura"] = "GoldDust"
    return a


# Lucky Wheel exclusive (Dev, 2026-10-31): a beckoning lucky cat. White calico coat, red
# collar with a glowing gold bell and a gold coin on its back; the front left paw waves.
def lucky_cat():
    W, WS, O, K, P, R, G, GD = "FAF6EE", "E6DFD2", "F29A38", "2E2A2A", "FF9AB0", "E0303A", "FFD23F", "D9A21E"
    # white, white shade, orange patch, black patch, pink, red collar, gold, dark gold

    def coat(i, j, k):
        if (i - 2) ** 2 + (j - 2) ** 2 <= 5 and k >= 6:
            return O                                        # orange patch over the hips
        if (i + 2) ** 2 + (j + 3) ** 2 <= 3 and k >= 7:
            return K                                        # black patch on the shoulder
        return W
    parts = legs(W, W, 4, -5, 3)
    for c in parts[0].cells:                                # pink paw pads on the waving paw
        if c[2] == 0:
            parts[0].cells[c] = "FFC2CF"
    body = Part("Body")
    body.box(-3, 3, -6, 6, 4, 9, lambda i, j, k: WS if k == 4 else coat(i, j, k))
    parts.append(body)

    head = Part("Head", "Body", joint=(0, -6, 8))

    def hcol(i, j, k):
        if k >= 12 and 1 <= i <= 3 and j >= -10:
            return O                                        # orange patch over one ear
        if k >= 12 and -4 <= i <= -3 and j >= -8:
            return K                                        # black patch over the other
        return W
    head.box(-4, 4, -11, -5, 7, 14, hcol)
    for x0 in (-4, 1):                                      # happy closed eyes (^ ^)
        head.set([(x0, -11, 10), (x0 + 1, -11, 11), (x0 + 2, -11, 10)], EYE)
    head.set([(-4, -11, 9), (3, -11, 9)], P)               # blush (under the eyes)
    head.box(-2, 2, -12, -11, 8, 10, W)                    # muzzle
    head.set([(-1, -12, 9), (0, -12, 9)], P)               # nose
    head.set([(-1, -12, 8), (0, -12, 8)], "8C4A3A")        # mouth
    for side in (-1, 1):                                    # whiskers
        x = 4 if side > 0 else -5
        head.set([(x, -10, 9), (x, -10, 8)], WS)
    parts.append(head)

    ear = Part("EarL", "Head", joint=(2.5, -8, 14))
    for k, xs in ((14, (1, 2, 3)), (15, (2, 3)), (16, (3,))):
        for x in xs:
            for y in (-9, -8):
                inner = y == -9 and x == 2
                ear.cells[(x, y, k)] = P if inner else (O if y == -8 else W)
    earR = ear.mirror("EarR")
    for c in earR.cells:
        if earR.cells[c] == O:
            earR.cells[c] = K
    parts += [ear, earR]

    collar = Part("Collar", "Head", joint=(0, -8, 7), noise=False)
    collar.box(-4, 4, -11, -5, 6, 7, lambda i, j, k: R if i in (-4, 3) or j in (-11, -6) else None)
    parts.append(collar)
    bell = Part("Bell_Glow", "Collar", joint=(0, -12, 6), noise=False, glow=G)
    bell.box(-1, 1, -12, -11, 4, 6, G)
    bell.set([(-1, -12, 3), (0, -12, 3)], GD)
    parts.append(bell)

    coin = Part("Coin_Glow", "Body", joint=(0, 0, 9), noise=False, glow=G)  # gold koban on its back
    coin.box(-1, 1, -2, 3, 9, 10, G)
    coin.box(-2, 2, -1, 2, 9, 10, G)
    coin.set([(-1, 0, 10), (0, 0, 10)], GD)
    parts.append(coin)

    tail = Part("Tail", "Body", joint=(0, 6, 8))
    tail.box(-1, 1, 6, 8, 7, 9, W)
    tail.box(-1, 1, 7, 9, 9, 11, lambda i, j, k: K if k == 10 else W)
    tail2 = Part("Tail2", "Tail", joint=(0, 8, 11))
    tail2.box(-1, 1, 7, 9, 11, 15, lambda i, j, k: O if k in (12, 14) else W)
    tail2.box(-1, 1, 6, 8, 15, 16, O)
    parts += [tail, tail2]
    a = assemble("LuckyCat", parts)
    a.extra["aura"] = "GoldDust"
    return a


PETS = {"Cat": cat, "Dog": dog, "Bunny": bunny, "Squirrel": squirrel, "Raccoon": raccoon, "Duck": duck,
        "Fox": fox, "Turtle": turtle, "Penguin": penguin,
        "Panda": panda, "Owl": owl, "Tiger": tiger,
        "Lion": lion, "ArcticWolf": arctic_wolf, "Unicorn": unicorn,
        "Dragon": dragon, "Phoenix": phoenix, "Kitsune": kitsune,
        "AutumnStag": autumn_stag,
        "Hedgehog": hedgehog, "Frog": frog, "Swan": swan, "Beaver": beaver, "Peacock": peacock, "Griffin": griffin,
        "Crab": crab, "Seagull": seagull, "Seal": seal, "Dolphin": dolphin, "Shark": shark, "SeaSerpent": sea_serpent,
        "Pigeon": pigeon, "Rat": rat, "Corgi": corgi, "Bulldog": bulldog, "RoboPup": robo_pup, "Gargoyle": gargoyle,
        "SnowHare": snow_hare, "MountainGoat": mountain_goat, "SnowLeopard": snow_leopard, "Mammoth": mammoth, "FrostEagle": frost_eagle, "Yeti": yeti,
        "ButterflyQueen": butterfly_queen, "Kraken": kraken, "MechaRex": mecha_rex, "AuroraWhale": aurora_whale,
        "DustBunny": dust_bunny,
        "Ladybug": ladybug, "Chipmunk": chipmunk, "Bee": bee, "Snail": snail, "Fawn": fawn, "Goose": goose,
        "Badger": badger, "Koi": koi, "Flamingo": flamingo, "RedPanda": red_panda, "MossGolem": moss_golem, "Pegasus": pegasus,
        "Starfish": starfish, "Clownfish": clownfish, "Pelican": pelican, "SeaTurtle": sea_turtle, "Octopus": octopus, "Pufferfish": pufferfish,
        "Walrus": walrus, "MantaRay": manta_ray, "Orca": orca, "Narwhal": narwhal, "CoralDragon": coral_dragon, "GoldenSeahorse": golden_seahorse,
        "AlleyCat": alley_cat, "Hamster": hamster, "Crow": crow, "Pug": pug, "Dalmatian": dalmatian, "Parrot": parrot,
        "PoliceDog": police_dog, "NeonCat": neon_cat, "CyberWolf": cyber_wolf, "JetpackMonkey": jetpack_monkey, "NeonDragon": neon_dragon, "GoldenLion": golden_lion,
        "ArcticFox": arctic_fox, "Lemming": lemming, "Puffin": puffin, "Husky": husky, "Reindeer": reindeer, "MuskOx": musk_ox,
        "PolarBear": polar_bear, "FrostBat": frost_bat, "WoollyRhino": woolly_rhino, "CrystalStag": crystal_stag, "IceDragon": ice_dragon, "GlacierTitan": glacier_titan,
        "Capybara": capybara, "Axolotl": axolotl, "Sloth": sloth, "Chameleon": chameleon, "LuckyCat": lucky_cat}


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


def bunny_idle(w):
    sniff = s(10 * w) * max(0.0, s(w))                      # nose twitches in bursts
    return {
        "Body": ((0, 0, 0.012 * (1 - c(2 * w))), (0, 0, 0)),
        "Head": ((0, 0, 0.006 * sniff), (-2 * sniff, 3 * s(w + 0.5), 10 * s(w))),
        "EarL": ((0, 0, 0), (6 * s(w), -6 - 8 * max(0.0, s(2 * w)) ** 4, 0)),
        "EarR": ((0, 0, 0), (6 * s(w + 0.4), 6, 0)),
        "Tail": ((0, 0, 0), (0, 0, 10 * s(6 * w))),
    }


def hop(w):
    """Bunny hop: both front legs, then both back legs, with a big arc."""
    up = max(0.0, s(w))
    return {
        "Body": ((0, 0, 0.32 * up), (-10 * c(w), 0, 0)),
        "Head": ((0, 0, 0), (6 * c(w), 0, 0)),
        "LegFL": ((0, 0, 0), (-30 * up, 0, 0)), "LegFR": ((0, 0, 0), (-30 * up, 0, 0)),
        "LegBL": ((0, 0, 0), (40 * up, 0, 0)), "LegBR": ((0, 0, 0), (40 * up, 0, 0)),
        "EarL": ((0, 0, 0), (22 * up, -6, 0)), "EarR": ((0, 0, 0), (22 * up, 6, 0)),
        "Tail": ((0, 0, 0), (0, 0, 0)),
    }


def squirrel_idle(w):
    nib = s(12 * w) * (s(w) > 0)                          # nibbling the acorn
    flick = 18 * max(0.0, s(3 * w)) ** 6
    return {
        "Body": ((0, 0, 0.01 * (1 - c(2 * w))), (-3 + 1.5 * s(2 * w), 0, 0)),
        "Head": ((0, 0, 0), (-5 - 4 * nib, 0, 12 * s(w + 2) * (s(w) <= 0))),
        "Acorn": ((0, 0, 0.01 * nib), (0, 0, 0)),
        "Tail": ((0, 0, 0), (-flick, 0, 6 * s(w))),
        "Tail2": ((0, 0, 0), (12 * s(2 * w) + flick, 0, 10 * s(w - 0.8))),
        "EarL": ((0, 0, 0), (0, -10 * max(0.0, s(4 * w + 1)) ** 8, 0)),
    }


def raccoon_idle(w):
    rub = s(8 * w)                                        # rubbing its paws together
    return {
        "Body": ((0, 0, 0.012 * (1 - c(2 * w))), (0, 0, 0)),
        "Head": ((0, 0, 0), (-3 * s(2 * w), 0, 16 * s(w) * abs(s(w)))),   # shifty looks
        "LegFL": ((0, 0, 0), (-14 + 8 * rub, 0, -6)),
        "LegFR": ((0, 0, 0), (-14 - 8 * rub, 0, 6)),
        "Tail": ((0, 0, 0), (4 * s(w), 0, 14 * s(w))),
        "Tail2": ((0, 0, 0), (6 * s(w - 1), 0, 20 * s(w - 1))),
        "EarL": ((0, 0, 0), (0, -8 * max(0.0, s(3 * w)) ** 6, 0)),
    }


def duck_idle(w):
    flap = 35 * max(0.0, s(6 * w)) * (s(w) > 0.6)        # a little wing flutter now and then
    return {
        "Body": ((0, 0, 0.01 * (1 - c(2 * w))), (0, 0, 0)),
        "Head": ((0, 0.02 * s(2 * w), 0), (-5 * s(2 * w), 6 * s(w + 1), 14 * s(w))),
        "Bill": ((0, 0, 0), (-6 * max(0.0, s(5 * w)) ** 6, 0, 0)),
        "WingL": ((0, 0, 0), (0, -flap, 0)), "WingR": ((0, 0, 0), (0, flap, 0)),
        "Tail": ((0, 0, 0), (0, 0, 14 * s(4 * w))),
    }


def waddle(w):
    leg = 30 * s(w)
    return {
        "Body": ((0, 0, 0.05 * abs(s(w))), (2 * s(2 * w), 9 * s(w), 6 * s(w))),
        "Head": ((0, 0, 0), (-5 * s(2 * w), -5 * s(w), -4 * s(w))),
        "LegL": ((0, 0, 0), (leg, 0, 0)), "LegR": ((0, 0, 0), (-leg, 0, 0)),
        "WingL": ((0, 0, 0), (0, -12 * abs(s(w)), 0)), "WingR": ((0, 0, 0), (0, 12 * abs(s(w)), 0)),
        "Tail": ((0, 0, 0), (0, 0, 20 * s(w))),
    }


def fox_idle(w):
    sit = 1 - c(w)                                         # settles down a little, then back
    return {
        "Body": ((0, 0, -0.03 * sit), (-4 * sit, 0, 0)),
        "Head": ((0, 0, 0), (4 * sit - 3 * s(2 * w), 6 * s(w + 1), 14 * s(w))),
        "LegBL": ((0, 0, 0), (-12 * sit, 0, 0)), "LegBR": ((0, 0, 0), (-12 * sit, 0, 0)),
        "EarL": ((0, 0, 0), (0, -14 * max(0.0, s(4 * w)) ** 8, 0)),
        "EarR": ((0, 0, 0), (0, 10 * max(0.0, s(4 * w + 2)) ** 8, 0)),
        "Tail": ((0, 0, 0), (-6, 0, 14 * s(w))),
        "Tail2": ((0, 0, 0), (8 * s(2 * w), 0, 30 * s(w - 0.9))),
    }


def turtle_idle(w):
    peek = (1 - c(w)) / 2                                  # head slides in and out of the shell
    return {
        "Body": ((0, 0, 0.006 * s(2 * w)), (0, 0, 0)),
        "Head": ((0, 0.26 * peek, -0.03 * peek), (-6 * s(2 * w) * (1 - peek), 0, 10 * s(3 * w) * (1 - peek))),
        "LegFL": ((0, 0, 0), (0, 0, 8 * s(4 * w))), "LegFR": ((0, 0, 0), (0, 0, -8 * s(4 * w))),
        "Tail": ((0, 0, 0), (0, 0, 20 * s(6 * w))),
    }


def crawl(w):
    leg = 22 * s(w)
    return {
        "Body": ((0, 0, 0.02 * abs(s(w))), (0, 3 * s(w), 2 * s(w))),
        "Head": ((0, 0, 0), (-4 * s(2 * w), 0, -6 * s(w))),
        "LegFL": ((0, 0, 0), (leg, 0, 0)), "LegBR": ((0, 0, 0), (leg, 0, 0)),
        "LegFR": ((0, 0, 0), (-leg, 0, 0)), "LegBL": ((0, 0, 0), (-leg, 0, 0)),
        "Tail": ((0, 0, 0), (0, 0, 15 * s(w))),
    }


def penguin_idle(w):
    flap = 40 * max(0.0, s(5 * w)) * (s(w) > 0.5)
    return {
        "Body": ((0, 0, 0.01 * (1 - c(2 * w))), (0, 4 * s(w), 0)),
        "Head": ((0, 0, 0), (-6 * s(2 * w), 8 * s(w + 1), 16 * s(w))),
        "WingL": ((0, 0, 0), (0, -10 - flap, 0)), "WingR": ((0, 0, 0), (0, 10 + flap, 0)),
        "Tail": ((0, 0, 0), (0, 0, 12 * s(4 * w))),
    }


def penguin_walk(w):
    p = waddle(w)
    p["Body"] = ((0, 0, 0.04 * abs(s(w))), (0, 14 * s(w), 8 * s(w)))
    p["WingL"] = ((0, 0, 0), (0, -25 - 15 * abs(s(w)), 0))
    p["WingR"] = ((0, 0, 0), (0, 25 + 15 * abs(s(w)), 0))
    return p


def panda_idle(w):
    chew = s(10 * w)
    return {
        "Body": ((0, 0, 0.012 * (1 - c(2 * w))), (0, 2.5 * s(w), 0)),
        "Head": ((0, 0, 0.008 * chew), (-3 * chew, 3 * s(w), 6 * s(w))),
        "Bamboo": ((0, 0, 0.01 * chew), (0, 4 * s(w), 6 * s(2 * w))),
        "EarL": ((0, 0, 0), (0, -6 * max(0.0, s(3 * w)) ** 6, 0)),
        "EarR": ((0, 0, 0), (0, 6 * max(0.0, s(3 * w + 2)) ** 6, 0)),
        "Tail": ((0, 0, 0), (0, 0, 10 * s(4 * w))),
    }


def heavy_walk(w):
    p = walk(24, 0.03, 8, 0, 4)(w)
    p["Body"] = ((0, 0, 0.03 * abs(s(w))), (2 * s(2 * w), 6 * s(w), 3 * s(w)))
    p["Bamboo"] = ((0, 0, 0), (0, 3 * s(w), 0))
    return p


def owl_idle(w):
    # Quick owl head turns: snaps to look left, holds, snaps right, holds.
    turn = 70 * max(-1.0, min(1.0, 3 * s(w)))
    blink = max(0.0, s(4 * w)) ** 10
    return {
        "Body": ((0, 0, 0.01 * (1 - c(2 * w))), (0, 0, 0)),
        "Head": ((0, 0, -0.02 * blink), (0, 8 * s(2 * w), turn)),
        "EarL": ((0, 0, 0), (0, -10 * blink, 0)), "EarR": ((0, 0, 0), (0, 10 * blink, 0)),
        "WingL": ((0, 0, 0), (0, -6 - 20 * max(0.0, s(3 * w)) ** 6, 0)),
        "WingR": ((0, 0, 0), (0, 6 + 20 * max(0.0, s(3 * w)) ** 6, 0)),
        "Tail": ((0, 0, 0), (6 * s(2 * w), 0, 0)),
    }


def owl_walk(w):
    up = max(0.0, s(w))
    flap = 55 * abs(s(2 * w))
    return {
        "Body": ((0, 0, 0.25 * up), (-6 * up, 0, 0)),
        "Head": ((0, 0, 0), (5 * up, 0, 0)),
        "LegL": ((0, 0, 0), (-25 * up, 0, 0)), "LegR": ((0, 0, 0), (-25 * up, 0, 0)),
        "WingL": ((0, 0, 0), (0, -flap, 0)), "WingR": ((0, 0, 0), (0, flap, 0)),
        "Tail": ((0, 0, 0), (-12 * up, 0, 0)),
    }


def tiger_idle(w):
    stretch = max(0.0, s(w)) ** 2                          # a long stretch, then a yawn
    yawn = max(0.0, -s(w)) ** 2
    return {
        "Body": ((0, 0, -0.06 * stretch), (-8 * stretch, 0, 0)),
        "Head": ((0, 0, 0), (-18 * yawn + 6 * stretch, 0, 6 * s(2 * w) * (1 - yawn))),
        "LegFL": ((0, -0.12 * stretch, 0), (-30 * stretch, 0, 0)), "LegFR": ((0, -0.12 * stretch, 0), (-30 * stretch, 0, 0)),
        "EarL": ((0, 0, 0), (0, -12 * yawn, 0)), "EarR": ((0, 0, 0), (0, 12 * yawn, 0)),
        "Tail": ((0, 0, 0), (-4, 0, 16 * s(w))),
        "Tail2": ((0, 0, 0), (10 * s(2 * w), 0, 24 * s(w - 1))),
    }


def lion_idle(w):
    shake = s(14 * w) * max(0.0, s(w)) ** 4                 # proud mane shake now and then
    return {
        "Body": ((0, 0, 0.015 * (1 - c(2 * w))), (1.5 * s(2 * w), 0, 0)),
        "Head": ((0, 0, 0), (-4 + 3 * s(2 * w), 14 * shake, 10 * s(w + 2) * (1 - abs(shake)))),
        "EarL": ((0, 0, 0), (0, -8 * abs(shake), 0)), "EarR": ((0, 0, 0), (0, 8 * abs(shake), 0)),
        "Tail": ((0, 0, 0), (-6, 0, 16 * s(w))),
        "Tail2": ((0, 0, 0), (12 * s(2 * w), 0, 26 * s(w - 1))),
    }


def wolf_idle(w):
    howl = max(0.0, s(w)) ** 3                              # throws its head back to howl
    return {
        "Body": ((0, 0, -0.03 * howl), (-6 * howl, 0, 0)),
        "Head": ((0, 0, 0.02 * howl), (-40 * howl, 0, 10 * s(2 * w) * (1 - howl))),
        "LegBL": ((0, 0, 0), (-10 * howl, 0, 0)), "LegBR": ((0, 0, 0), (-10 * howl, 0, 0)),
        "EarL": ((0, 0, 0), (12 * howl, 0, 0)), "EarR": ((0, 0, 0), (12 * howl, 0, 0)),
        "Tail": ((0, 0, 0), (-10, 0, 12 * s(w))),
        "Tail2": ((0, 0, 0), (6 * s(2 * w), 0, 20 * s(w - 1))),
    }


def unicorn_idle(w):
    stamp = max(0.0, s(2 * w)) ** 4 * (s(w) > 0)            # paws the ground with a front hoof
    return {
        "Body": ((0, 0, 0.015 * (1 - c(2 * w))), (0, 0, 0)),
        "Head": ((0, 0, 0), (-6 * s(2 * w), 3 * s(w), 10 * s(w + 1))),
        "Mane": ((0, 0, 0), (0, 10 * s(3 * w), 0)),
        "LegFL": ((0, 0, 0.0), (-40 * stamp, 0, 0)),
        "EarL": ((0, 0, 0), (0, -8 * max(0.0, s(4 * w)) ** 6, 0)),
        "EarR": ((0, 0, 0), (0, 8 * max(0.0, s(4 * w + 1)) ** 6, 0)),
        "Tail": ((0, 0, 0), (-4, 0, 14 * s(w))),
        "Tail2": ((0, 0, 0), (8 * s(2 * w), 0, 22 * s(w - 1))),
    }


def prance(w):
    p = walk(38, 0.1, 14, -6, 4)(w)
    p["Head"] = ((0, 0, 0), (-8 * s(2 * w), 0, 4 * s(w)))
    p["Mane"] = ((0, 0, 0), (12 * s(2 * w + 1), 6 * s(w), 0))
    return p


def dragon_idle(w):
    stretch = max(0.0, s(w)) ** 3                           # a big wing stretch now and then
    return {
        "Body": ((0, 0, 0.02 * (1 - c(2 * w))), (2 * s(2 * w), 0, 0)),
        "Head": ((0, 0, 0), (-5 * s(2 * w) - 10 * stretch, 0, 12 * s(w + 2))),
        "WingL": ((0, 0, 0), (0, -10 - 35 * stretch + 4 * s(4 * w), 0)),
        "WingR": ((0, 0, 0), (0, 10 + 35 * stretch - 4 * s(4 * w), 0)),
        "Tail": ((0, 0, 0), (-4, 0, 14 * s(w))),
        "Tail2": ((0, 0, 0), (8 * s(2 * w), 0, 26 * s(w - 1))),
    }


def dragon_walk(w):
    p = walk(30, 0.05, 14, -4, 0)(w)
    p["WingL"] = ((0, 0, 0), (0, -14 - 10 * s(2 * w), 0))
    p["WingR"] = ((0, 0, 0), (0, 14 + 10 * s(2 * w), 0))
    return p


def phoenix_idle(w):
    flap = s(2 * w)
    return {
        "Body": ((0, 0, 0.08 * s(2 * w + 1)), (-4 * s(2 * w), 0, 3 * s(w))),
        "Head": ((0, 0, 0), (4 * s(2 * w), 4 * s(w), 14 * s(w))),
        "Crest_Glow": ((0, 0, 0), (8 * s(4 * w), 0, 0)),
        "WingL": ((0, 0, 0), (0, -30 * flap, 0)), "WingR": ((0, 0, 0), (0, 30 * flap, 0)),
        "Tail_Glow": ((0, 0, 0), (6 * s(2 * w - 1), 0, 8 * s(w))),
        "LegL": ((0, 0, 0), (30, 0, 0)), "LegR": ((0, 0, 0), (30, 0, 0)),
    }


def phoenix_walk(w):
    flap = s(2 * w)
    return {
        "Body": ((0, 0, 0.06 * s(2 * w + 1)), (-14, 0, 4 * s(w))),
        "Head": ((0, 0, 0), (10, 0, 0)),
        "Crest_Glow": ((0, 0, 0), (-12, 0, 0)),
        "WingL": ((0, 0, 0), (0, -45 * flap, 0)), "WingR": ((0, 0, 0), (0, 45 * flap, 0)),
        "Tail_Glow": ((0, 0, 0), (10 + 6 * s(2 * w), 0, 6 * s(w))),
        "LegL": ((0, 0, 0), (50, 0, 0)), "LegR": ((0, 0, 0), (50, 0, 0)),
    }


def kitsune_tails(w, amp, speed=1):
    return {f"Tail{n + 1}": ((0, 0, 0), (amp * 0.5 * s(speed * w - n * 0.6), amp * s(speed * w - n * 0.6), 0)) for n in range(9)}


def kitsune_idle(w):
    p = {
        "Body": ((0, 0, 0.015 * (1 - c(2 * w))), (0, 0, 0)),
        "Head": ((0, 0, 0), (-4 * s(2 * w), 5 * s(w + 1), 14 * s(w))),
        "EarL": ((0, 0, 0), (0, -12 * max(0.0, s(4 * w)) ** 8, 0)),
        "EarR": ((0, 0, 0), (0, 12 * max(0.0, s(4 * w + 2)) ** 8, 0)),
    }
    p.update(kitsune_tails(w, 12, 2))
    return p


def kitsune_walk(w):
    p = walk(30, 0.08, 0, 0, 6)(w)
    p.pop("Tail"), p.pop("Tail2")
    p.update(kitsune_tails(w, 10, 2))
    return p


def stag_idle(w):
    graze = max(0.0, s(w)) ** 2                              # lowers its head to graze, then looks up
    return {
        "Body": ((0, 0, 0.015 * (1 - c(2 * w))), (-2 * graze, 0, 0)),
        "Head": ((0, 0, 0), (28 * graze - 4 * s(2 * w) * (1 - graze), 0, 10 * s(w + 2) * (1 - graze))),
        "Antlers": ((0, 0, 0), (0, 3 * s(3 * w), 0)),
        "EarL": ((0, 0, 0), (0, -14 * max(0.0, s(5 * w)) ** 8, 0)),
        "EarR": ((0, 0, 0), (0, 14 * max(0.0, s(5 * w + 2)) ** 8, 0)),
        "Tail": ((0, 0, 0), (-10 * max(0.0, s(6 * w)) ** 4, 0, 0)),
    }


def stag_walk(w):
    p = walk(30, 0.05, 0, 0, 3)(w)
    p["Head"] = ((0, 0, 0), (-4 * s(2 * w), 0, 3 * s(w)))
    p["Antlers"] = ((0, 0, 0), (0, 2 * s(2 * w), 0))
    p["Tail"] = ((0, 0, 0), (-8 * abs(s(w)), 0, 0))
    p.pop("Tail2")
    return p


def hedgehog_idle(w):
    sniff = s(12 * w) * max(0.0, s(w))
    curl = max(0.0, -s(w)) ** 4                               # tucks in now and then
    return {
        "Body": ((0, 0, -0.04 * curl), (6 * curl, 0, 0)),
        "Head": ((0, 0.04 * curl, 0), (-3 * sniff + 25 * curl, 0, 12 * s(2 * w) * (1 - curl))),
        "LegFL": ((0, 0, 0), (-20 * curl, 0, 0)), "LegFR": ((0, 0, 0), (-20 * curl, 0, 0)),
    }


def frog_idle(w):
    croak = max(0.0, s(3 * w)) ** 6
    return {
        "Body": ((0, 0, 0.01 * (1 - c(2 * w))), (0, 0, 0)),
        "Head": ((0, 0, 0.02 * croak), (-8 * croak, 0, 8 * s(w))),
    }


def frog_hop(w):
    up = max(0.0, s(w))
    return {
        "Body": ((0, 0, 0.45 * up), (-14 * c(w) * (up > 0), 0, 0)),
        "Head": ((0, 0, 0), (8 * up, 0, 0)),
        "LegBL": ((0, 0, 0), (55 * up, 0, 0)), "LegBR": ((0, 0, 0), (55 * up, 0, 0)),
        "LegFL": ((0, 0, 0), (-30 * up, 0, 0)), "LegFR": ((0, 0, 0), (-30 * up, 0, 0)),
    }


def swan_idle(w):
    preen = max(0.0, s(w)) ** 3
    return {
        "Body": ((0, 0, 0.01 * (1 - c(2 * w))), (0, 2 * s(w), 0)),
        "Head": ((0, 0, 0), (-8 * s(2 * w) + 30 * preen, 0, 18 * s(w + 1) + 40 * preen)),
        "WingL": ((0, 0, 0), (0, -25 * preen, 0)), "WingR": ((0, 0, 0), (0, 6 * s(2 * w), 0)),
    }


def beaver_idle(w):
    slap = max(0.0, s(2 * w)) ** 8
    gnaw = s(14 * w) * (s(w) < 0)
    return {
        "Body": ((0, 0, 0.01 * (1 - c(2 * w))), (0, 0, 0)),
        "Head": ((0, 0, 0.005 * gnaw), (-3 * gnaw, 0, 10 * s(w) * (s(w) > 0))),
        "Tail": ((0, 0, 0.0), (-40 * slap, 0, 0)),
        "EarL": ((0, 0, 0), (0, -8 * max(0.0, s(5 * w)) ** 8, 0)),
    }


def peacock_idle(w):
    show = (1 - c(w)) / 2                                     # fans the tail out and back
    return {
        "Body": ((0, 0, 0.01 * (1 - c(2 * w))), (0, 3 * s(3 * w) * show, 0)),
        "Head": ((0, 0, 0), (-6 * s(2 * w), 0, 16 * s(w + 1))),
        "Tail": ((0, 0, 0), (40 * (1 - show) - 6, 0, 4 * s(4 * w) * show)),
        "WingL": ((0, 0, 0), (0, -6 * show, 0)), "WingR": ((0, 0, 0), (0, 6 * show, 0)),
    }


def peacock_walk(w):
    p = waddle(w)
    p["Tail"] = ((0, 0, 0), (36, 0, 6 * s(w)))
    p["Body"] = ((0, 0, 0.04 * abs(s(w))), (2 * s(2 * w), 5 * s(w), 4 * s(w)))
    return p


def griffin_idle(w):
    p = dragon_idle(w)
    p["Head"] = ((0, 0, 0), (-5 * s(2 * w), 8 * s(3 * w), 24 * max(-1.0, min(1.0, 2 * s(w)))))   # bird-like head snaps
    return p


def crab_idle(w):
    snapL = max(0.0, s(4 * w)) ** 6
    snapR = max(0.0, s(4 * w + 2)) ** 6
    return {
        "Body": ((0, 0, 0.01 * (1 - c(2 * w))), (0, 4 * s(w), 0)),
        "ArmL": ((0, 0, 0), (-20 * snapL, 0, 10 * snapL)), "ArmR": ((0, 0, 0), (-20 * snapR, 0, -10 * snapR)),
        "EarL": ((0, 0, 0), (0, 10 * s(2 * w), 0)), "EarR": ((0, 0, 0), (0, -10 * s(2 * w + 1), 0)),
    }


def crab_walk(w):
    return {
        "Body": ((0.04 * s(w), 0, 0.03 * abs(s(2 * w))), (0, 5 * s(w), 6 * s(w))),
        "LegFL": ((0, 0, 0), (0, 25 * s(2 * w), 0)), "LegBL": ((0, 0, 0), (0, -25 * s(2 * w), 0)),
        "LegFR": ((0, 0, 0), (0, -25 * s(2 * w), 0)), "LegBR": ((0, 0, 0), (0, 25 * s(2 * w), 0)),
        "ArmL": ((0, 0, 0), (-10 * s(w), 0, 0)), "ArmR": ((0, 0, 0), (10 * s(w), 0, 0)),
        "EarL": ((0, 0, 0), (0, 8 * s(2 * w), 0)), "EarR": ((0, 0, 0), (0, -8 * s(2 * w), 0)),
    }


def seal_idle(w):
    clap = max(0.0, s(6 * w)) * (s(w) > 0.3)
    return {
        "Body": ((0, 0, 0.01 * (1 - c(2 * w))), (-4 * (s(w) > 0.3), 0, 0)),
        "Head": ((0, 0, 0), (-12 * (s(w) > 0.3) - 4 * s(2 * w), 0, 14 * s(w + 2) * (s(w) <= 0.3))),
        "LegFL": ((0, 0, 0.0), (0, -45 * clap, 0)), "LegFR": ((0, 0, 0), (0, 45 * clap, 0)),
        "Tail": ((0, 0, 0), (-10 * abs(s(3 * w)), 0, 0)),
    }


def seal_walk(w):
    hump = abs(s(w))
    return {
        "Body": ((0, 0, 0.08 * hump), (-8 * s(2 * w), 0, 0)),
        "Head": ((0, 0, 0), (8 * s(2 * w), 0, 0)),
        "LegFL": ((0, 0, 0), (30 * s(w), 0, 0)), "LegFR": ((0, 0, 0), (30 * s(w), 0, 0)),
        "Tail": ((0, 0, 0), (-20 * hump, 0, 0)),
    }


def swim(roll, kick, bob=0.08):
    def f(w):
        return {
            "Body": ((0, 0, bob * s(w)), (5 * s(w + 1), roll * s(w), 4 * s(w))),
            "Head": ((0, 0, 0), (-4 * s(w), 0, 4 * s(w + 0.5))),
            "WingL": ((0, 0, 0), (0, -15 * s(2 * w), 0)), "WingR": ((0, 0, 0), (0, 15 * s(2 * w), 0)),
            "Tail": ((0, 0, 0), (kick * s(2 * w), 0, 6 * s(w))),
        }
    return f


def serpent(speed, amp):
    def f(w):
        return {
            "Body": ((0, 0, 0.1 * s(w)), (0, 0, amp * 0.5 * s(speed * w))),
            "Head": ((0, 0, 0), (-6 * s(w), 0, -amp * 0.6 * s(speed * w + 0.6))),
            "Seg1": ((0, 0, 0), (6 * s(speed * w - 0.8), 0, amp * s(speed * w - 0.8))),
            "Seg2": ((0, 0, 0), (6 * s(speed * w - 1.6), 0, amp * s(speed * w - 1.6))),
            "Seg3": ((0, 0, 0), (6 * s(speed * w - 2.4), 0, amp * s(speed * w - 2.4))),
            "Tail": ((0, 0, 0), (8 * s(speed * w - 3.2), 0, amp * 1.2 * s(speed * w - 3.2))),
            "Fin": ((0, 0, 0), (0, 6 * s(2 * w), 0)),
        }
    return f


def fly(amp, legs=("LegL", "LegR"), quad=False, base=None):
    """Flying pets (meta.float): hover with slow flaps, fly forward with fast ones, legs
    tucked up. base: the pet's own idle to keep its head/tail motion from."""
    def pose(w, flap_speed, flap_amp, pitch):
        p = dict(base(w)) if base else {}
        flap = s(flap_speed * w)
        p["Body"] = ((0, 0, 0.08 * s(flap_speed * w + 1.4)), (pitch, 0, 3 * s(w)))
        p["WingL"] = ((0, 0, 0), (0, -flap_amp * flap, 0))
        p["WingR"] = ((0, 0, 0), (0, flap_amp * flap, 0))
        if quad:
            for n in ("LegFL", "LegFR"):
                p[n] = ((0, 0, 0), (-35, 0, 0))
            for n in ("LegBL", "LegBR"):
                p[n] = ((0, 0, 0), (45, 0, 0))
        else:
            for n in legs:
                p[n] = ((0, 0, 0), (45, 0, 0))
        return p
    return {"Idle": lambda w: pose(w, 2, amp, -4), "Walk": lambda w: pose(w, 2, amp * 1.4, -14)}


def rat_idle(w):
    sniff = s(14 * w) * max(0.0, s(w))
    up = max(0.0, -s(w)) ** 3                                  # stands up on its back legs to look around
    return {
        "Body": ((0, 0, 0.06 * up), (-25 * up, 0, 0)),
        "Head": ((0, 0, 0), (-4 * sniff + 15 * up, 0, 20 * s(3 * w) * up)),
        "LegFL": ((0, 0, 0), (-30 * up, 0, 0)), "LegFR": ((0, 0, 0), (-30 * up, 0, 0)),
        "LegBL": ((0, 0, 0), (25 * up, 0, 0)), "LegBR": ((0, 0, 0), (25 * up, 0, 0)),
        "EarL": ((0, 0, 0), (0, -8 * max(0.0, s(5 * w)) ** 6, 0)),
        "Tail": ((0, 0, 0), (0, 0, 14 * s(2 * w))), "Tail2": ((0, 0, 0), (0, 0, 22 * s(2 * w - 1))),
    }


def corgi_idle(w):
    wiggle = s(10 * w) * max(0.0, s(w))                        # butt wiggle
    return {
        "Body": ((0, 0, 0.01 * (1 - c(2 * w))), (0, 0, 6 * wiggle)),
        "Head": ((0, 0, 0), (-4 * s(2 * w), 8 * s(w + 2), 10 * s(w))),
        "EarL": ((0, 0, 0), (0, -6 * max(0.0, s(4 * w)) ** 6, 0)),
        "EarR": ((0, 0, 0), (0, 6 * max(0.0, s(4 * w + 1)) ** 6, 0)),
    }


def bulldog_idle(w):
    huff = s(4 * w)
    return {
        "Body": ((0, 0, 0.012 * (1 + huff)), (1.5 * huff, 0, 0)),
        "Head": ((0, 0, 0), (-3 * huff, 0, 8 * s(w))),
        "Tail": ((0, 0, 0), (0, 0, 30 * s(10 * w))),
        "EarL": ((0, 0, 0), (0, -6 * max(0.0, s(3 * w)) ** 6, 0)),
    }


def robo_idle(w):
    scan = 30 * s(w)
    return {
        "Body": ((0, 0, 0.01 * (1 - c(2 * w))), (0, 0, 0)),
        "Head": ((0, 0, 0), (-4 * s(4 * w) * 0, 0, scan)),
        "Antenna_Glow": ((0, 0.0, 0), (20 * s(6 * w), 0, 0)),
        "Antenna": ((0, 0, 0), (20 * s(6 * w), 0, 0)),
        "EarL": ((0, 0, 0), (0, -15 * (s(3 * w) > 0.7), 0)), "EarR": ((0, 0, 0), (0, 15 * (s(3 * w) > 0.7), 0)),
        "Tail": ((0, 0, 0), (0, 0, 35 * s(8 * w))),
    }


def robo_walk(w):
    p = walk(30, 0.03, 30, 0, 0)(w)
    p.pop("Tail2")
    p["Antenna_Glow"] = ((0, 0, 0), (15 * s(2 * w), 0, 0))
    p["Antenna"] = ((0, 0, 0), (15 * s(2 * w), 0, 0))
    return p


def goat_idle(w):
    chew = s(8 * w) * (s(w) < 0.3)
    butt = max(0.0, s(w)) ** 6                              # lowers its head for a little headbutt
    return {
        "Body": ((0, 0, 0.01 * (1 - c(2 * w))), (2 * butt, 0, 0)),
        "Head": ((0, -0.05 * butt, 0), (30 * butt - 3 * chew, 0, 12 * s(w + 2) * (1 - butt))),
        "EarL": ((0, 0, 0), (0, -10 * max(0.0, s(4 * w)) ** 6, 0)),
        "EarR": ((0, 0, 0), (0, 10 * max(0.0, s(4 * w + 1)) ** 6, 0)),
        "Tail": ((0, 0, 0), (-20 * max(0.0, s(6 * w)) ** 4, 0, 0)),
    }


def leopard_idle(w):
    p = cat_idle(w)
    p["Tail"] = ((0, 0, 0), (-10 + 6 * s(w), 0, 24 * s(w)))
    p["Tail2"] = ((0, 0, 0), (-20 + 10 * s(w - 0.8), 0, 34 * s(w - 1.0)))
    return p


def mammoth_idle(w):
    swing = s(w)
    trumpet = max(0.0, s(w + 1)) ** 8                      # trunk up, trumpet
    return {
        "Body": ((0, 0, 0.02 * (1 - c(2 * w))), (0, 2 * s(w), 0)),
        "Head": ((0, 0, 0), (-3 * s(2 * w) - 8 * trumpet, 0, 6 * s(w))),
        "Trunk": ((0, 0, 0), (-60 * trumpet + 6 * swing * (1 - trumpet), 0, 14 * swing * (1 - trumpet))),
        "Trunk2": ((0, 0, 0), (-50 * trumpet + 10 * s(2 * w), 0, 10 * swing)),
        "EarL": ((0, 0, 0), (0, 0, -18 * max(0.0, s(3 * w)) ** 2)),
        "EarR": ((0, 0, 0), (0, 0, 18 * max(0.0, s(3 * w)) ** 2)),
        "Tail": ((0, 0, 0), (0, 0, 20 * s(4 * w))),
    }


def mammoth_walk(w):
    p = walk(22, 0.04, 14, 0, 0)(w)
    p["Body"] = ((0, 0, 0.04 * abs(s(w))), (1.5 * s(2 * w), 5 * s(w), 3 * s(w)))
    p["Trunk"] = ((0, 0, 0), (8 * s(2 * w), 0, 14 * s(w)))
    p["Trunk2"] = ((0, 0, 0), (12 * s(2 * w - 0.6), 0, 12 * s(w - 0.6)))
    p["EarL"] = ((0, 0, 0), (0, 0, -10 * abs(s(w))))
    p["EarR"] = ((0, 0, 0), (0, 0, 10 * abs(s(w))))
    return p


def eagle_idle(w):
    return {
        "Head": ((0, 0, 0), (-4 * s(2 * w), 6 * s(3 * w), 30 * max(-1.0, min(1.0, 2.5 * s(w))))),
        "Tail": ((0, 0, 0), (6 * s(2 * w), 0, 8 * s(w))),
    }


def yeti_idle(w):
    roar = max(0.0, s(w)) ** 4                              # arms up and a big roar
    breathe = s(2 * w)
    beat = s(10 * w) * (s(w) < -0.3)                        # chest thumps
    return {
        "Body": ((0, 0, 0.02 * breathe), (-6 * roar + 1.5 * breathe, 0, 0)),
        "Head": ((0, 0, 0), (-18 * roar + 2 * breathe, 0, 10 * s(w + 2) * (1 - roar))),
        "ArmL": ((0, 0, 0), (-30 * roar - 35 * abs(beat), -60 * roar - 6 * breathe, 25 * abs(beat))),
        "ArmR": ((0, 0, 0), (-30 * roar - 35 * abs(s(10 * w + 1.5)) * (s(w) < -0.3), 60 * roar + 6 * breathe, -25 * abs(s(10 * w + 1.5)) * (s(w) < -0.3))),
        "Horns_Glow": ((0, 0, 0), (0, 0, 0)),
    }


def yeti_walk(w):
    swing = 28 * s(w)
    return {
        "Body": ((0, 0, 0.08 * abs(s(w))), (4, 5 * s(w), 6 * s(w))),
        "Head": ((0, 0, 0), (-4 * s(2 * w), -4 * s(w), -5 * s(w))),
        "LegL": ((0, 0, 0), (swing, 0, 0)), "LegR": ((0, 0, 0), (-swing, 0, 0)),
        "ArmL": ((0, 0, 0), (-swing * 1.1, -8, 0)), "ArmR": ((0, 0, 0), (swing * 1.1, 8, 0)),
    }


def butterfly(speed, amp, pitch):
    def f(w):
        flap = 0.5 + 0.5 * s(speed * w)
        return {
            "Body": ((0, 0, 0.1 * s(speed * w + 1.5)), (pitch, 0, 4 * s(w))),
            "Head": ((0, 0, 0), (-4 * s(2 * w), 0, 8 * s(w))),
            "Antennae_Glow": ((0, 0, 0), (10 * s(3 * w), 0, 0)),
            "WingL": ((0, 0, 0), (0, -(10 + amp * flap), 0)),
            "WingR": ((0, 0, 0), (0, 10 + amp * flap, 0)),
        }
    return f


def kraken_anim(speed, amp, bob):
    def f(w):
        p = {"Body": ((0, 0, bob * (1 - c(2 * w))), (2 * s(2 * w), 3 * s(w), 0))}
        for n in range(8):
            ph = speed * w + n * 0.9
            p[f"Tent{n + 1}"] = ((0, 0, 0), (amp * 0.5 * s(ph), amp * 0.4 * c(ph), amp * 0.6 * s(ph)))
            p[f"Tent{n + 1}b"] = ((0, 0, 0), (amp * 0.8 * s(ph - 1), 0, amp * s(ph - 1)))
        return p
    return f


def rex_idle(w):
    roar = max(0.0, s(w)) ** 6
    return {
        "Body": ((0, 0, 0.02 * (1 - c(2 * w))), (-4 * roar, 0, 0)),
        "Head": ((0, 0, 0), (-20 * roar + 2 * s(2 * w), 0, 16 * s(w + 2) * (1 - roar))),
        "Jaw": ((0, 0, 0), (35 * roar + 4 * max(0.0, s(6 * w)) ** 8, 0, 0)),
        "ArmL": ((0, 0, 0), (-20 * roar + 10 * s(3 * w), 0, 0)), "ArmR": ((0, 0, 0), (-20 * roar + 10 * s(3 * w + 1), 0, 0)),
        "Tail": ((0, 0, 0), (4 * roar, 0, 12 * s(w))),
        "Tail2": ((0, 0, 0), (0, 0, 18 * s(w - 1))),
    }


def rex_walk(w):
    swing = 30 * s(w)
    return {
        "Body": ((0, 0, 0.06 * abs(s(w))), (2, 4 * s(w), 5 * s(w))),
        "Head": ((0, 0, 0), (-4 * s(2 * w), -4 * s(w), -6 * s(w))),
        "Jaw": ((0, 0, 0), (8 * max(0.0, s(2 * w)), 0, 0)),
        "LegL": ((0, 0, 0), (swing, 0, 0)), "LegR": ((0, 0, 0), (-swing, 0, 0)),
        "ArmL": ((0, 0, 0), (-15 * s(w), 0, 0)), "ArmR": ((0, 0, 0), (15 * s(w), 0, 0)),
        "Tail": ((0, 0, 0), (0, 0, -10 * s(w))),
        "Tail2": ((0, 0, 0), (0, 0, -16 * s(w - 0.8))),
    }


def whale(speed, amp):
    def f(w):
        return {
            "Body": ((0, 0, 0.12 * s(speed * w)), (3 * s(speed * w + 1), 3 * s(w), 0)),
            "Head": ((0, 0, 0), (-3 * s(speed * w), 0, 0)),
            "FinL": ((0, 0, 0), (0, -amp * 0.6 * s(speed * w), 0)), "FinR": ((0, 0, 0), (0, amp * 0.6 * s(speed * w), 0)),
            "Tail": ((0, 0, 0), (-amp * 0.5 * s(speed * w - 0.6), 0, 0)),
            "Tail2": ((0, 0, 0), (-amp * s(speed * w - 1.4), 0, 0)),
        }
    return f


def bunny_mob_idle(w):
    """Sniffs, looks around, then sits up on its haunches and washes its face."""
    sniff = s(12 * w) * (s(w) < 0.2)
    up = max(0.0, s(w)) ** 2                                      # sits up for the first half
    wash = s(10 * w) * up
    return {
        "Body": ((0, 0.04 * up, 0.08 * up), (-22 * up + 0.8 * s(2 * w), 0, 0)),
        "Head": ((0, 0, 0.01 * sniff), (14 * up - 3 * sniff + 6 * wash, 4 * s(w + 1) * (1 - up), 18 * s(2 * w + 2) * (1 - up))),
        "LegFL": ((0, 0, 0), (-60 * up + 25 * wash, 0, -10 * up)), "LegFR": ((0, 0, 0), (-60 * up - 25 * wash, 0, 10 * up)),
        "LegBL": ((0, 0, 0), (22 * up, 0, 0)), "LegBR": ((0, 0, 0), (22 * up, 0, 0)),
        "EarL": ((0, 0, 0), (8 * s(w) - 10 * wash, -4 - 10 * max(0.0, s(3 * w)) ** 8, 0)),
        "EarR": ((0, 0, 0), (6 * s(w + 0.5), 4, 0)),
        "Leaf": ((0, 0, 0), (0, 6 * s(2 * w), 0)),
        "Tail": ((0, 0, 0), (0, 0, 14 * s(8 * w))),
    }


def bunny_mob_hop(height, stretch, ears_back):
    """One big hop per loop: crouch, launch with the back legs, stretch out in the air,
    land on the front paws, back feet come down last."""
    def f(w):
        t = (w / (2 * math.pi)) % 1.0
        air = max(0.0, s(2 * math.pi * (t - 0.1) / 0.8 * 0.5)) if 0.1 <= t <= 0.9 else 0.0
        crouch = max(0.0, c(2 * math.pi * t)) ** 6                # squash at take-off and landing
        launch = max(0.0, s(2 * math.pi * t)) if t < 0.5 else 0.0
        land = max(0.0, -s(2 * math.pi * t)) if t >= 0.5 else 0.0
        return {
            "Body": ((0, 0, height * air - 0.06 * crouch), (-14 * launch + 16 * land, 0, 0)),
            "Head": ((0, 0, -0.03 * crouch), (8 * launch - 10 * land, 0, 0)),
            "LegFL": ((0, 0, 0), (-stretch * launch * 0.6 - 30 * land, 0, 0)),
            "LegFR": ((0, 0, 0), (-stretch * launch * 0.6 - 30 * land, 0, 0)),
            "LegBL": ((0, 0, 0), (stretch * launch + 15 * land, 0, 0)),
            "LegBR": ((0, 0, 0), (stretch * launch + 15 * land, 0, 0)),
            "EarL": ((0, 0, 0), (ears_back * air + 12 * crouch, -6, 0)),
            "EarR": ((0, 0, 0), (ears_back * air + 12 * crouch, 6, 0)),
            "Leaf": ((0, 0, 0), (-10 * air, 0, 0)),
            "Tail": ((0, 0, 0), (-12 * air, 0, 0)),
        }
    return f


def bug_walk(w):
    p = walk(30, 0.01, 0, 0, 0)(w)
    p["LegML"] = ((0, 0, 0), (-30 * s(w), 0, 0))
    p["LegMR"] = ((0, 0, 0), (30 * s(w), 0, 0))
    p["EarL"] = ((0, 0, 0), (10 * s(2 * w), 0, 0))
    p["EarR"] = ((0, 0, 0), (10 * s(2 * w + 1), 0, 0))
    return p


def bug_idle(w):
    return {
        "Body": ((0, 0, 0.01 * (1 - c(2 * w))), (0, 0, 0)),
        "Head": ((0, 0, 0), (-4 * s(2 * w), 0, 10 * s(w))),
        "EarL": ((0, 0, 0), (12 * s(3 * w), 0, 0)), "EarR": ((0, 0, 0), (12 * s(3 * w + 1.2), 0, 0)),
    }


def bee_idle(w):
    return {"Head": ((0, 0, 0), (-4 * s(2 * w), 0, 12 * s(w))),
            "EarL": ((0, 0, 0), (10 * s(4 * w), 0, 0)), "EarR": ((0, 0, 0), (10 * s(4 * w + 1), 0, 0))}


def bee_fly(speed, pitch):
    def f(w):
        p = bee_idle(w)
        buzz = s(speed * w)
        p["Body"] = ((0.04 * s(3 * w), 0, 0.1 * s(2 * w)), (pitch, 0, 4 * s(w)))
        p["WingL"] = ((0, 0, 0), (0, -25 - 30 * buzz, 0))
        p["WingR"] = ((0, 0, 0), (0, 25 + 30 * buzz, 0))
        return p
    return f


def snail_idle(w):
    return {
        "Body": ((0, 0, 0), (0, 0, 0)),
        "Shell": ((0, 0, 0.01 * s(2 * w)), (0, 2 * s(w), 0)),
        "Head": ((0, 0, 0), (-4 * s(2 * w), 0, 12 * s(w))),
        "EarL": ((0, 0, 0), (14 * s(2 * w), 0, 8 * s(w))), "EarR": ((0, 0, 0), (14 * s(2 * w + 1), 0, -8 * s(w))),
    }


def snail_walk(w):
    p = snail_idle(w)
    p["Body"] = ((0, -0.04 * s(2 * w), 0), (0, 0, 0))
    p["Head"] = ((0, -0.06 * max(0.0, s(2 * w)), 0), (-3, 0, 4 * s(w)))
    return p


def goose_idle(w):
    honk = max(0.0, s(w)) ** 8
    p = duck_idle(w)
    p.pop("Bill", None)
    p["Head"] = ((0, 0, 0), (-25 * honk - 4 * s(2 * w), 0, 14 * s(w) * (1 - honk)))
    p["WingL"] = ((0, 0, 0), (0, -40 * honk, 0))
    p["WingR"] = ((0, 0, 0), (0, 40 * honk, 0))
    return p


def badger_idle(w):
    dig = max(0.0, s(w)) ** 2 * s(14 * w)
    return {
        "Body": ((0, 0, 0.01 * (1 - c(2 * w))), (6 * max(0.0, s(w)) ** 2, 0, 0)),
        "Head": ((0, 0, 0), (12 * max(0.0, s(w)) ** 2, 0, 8 * s(w + 2))),
        "LegFL": ((0, 0, 0), (-30 * dig, 0, 0)), "LegFR": ((0, 0, 0), (30 * dig, 0, 0)),
        "Tail": ((0, 0, 0), (0, 0, 10 * s(4 * w))),
    }


def flamingo_idle(w):
    tuck = min(1.0, 3 * max(0.0, s(w)))                                 # stands on one leg
    return {
        "Body": ((0, 0, 0.01 * s(2 * w)), (0, 0, 2 * s(w))),
        "Head": ((0, 0, 0), (-6 * s(2 * w), 0, 16 * s(w + 1))),
        "LegL": ((0, 0, 0.05 * tuck), (75 * tuck, 0, 0)),
        "WingL": ((0, 0, 0), (0, -6 * max(0.0, s(5 * w)) ** 6, 0)), "WingR": ((0, 0, 0), (0, 6 * max(0.0, s(5 * w)) ** 6, 0)),
        "Tail": ((0, 0, 0), (0, 0, 8 * s(3 * w))),
    }


def flamingo_walk(w):
    swing = 30 * s(w)
    return {
        "Body": ((0, 0, 0.05 * abs(s(w))), (0, 0, 4 * s(w))),
        "Head": ((0, 0.03 * s(2 * w), 0), (-6 * s(2 * w), 0, -4 * s(w))),
        "LegL": ((0, 0, 0), (swing, 0, 0)), "LegR": ((0, 0, 0), (-swing, 0, 0)),
    }


def golem_idle(w):
    p = yeti_idle(w)
    p.pop("Horns_Glow", None)
    p["Head"] = ((0, 0, 0), (-8 * max(0.0, s(w)) ** 4, 0, 12 * s(w + 2)))
    return p


def starfish_idle(w):
    p = {"Body": ((0, 0, 0.01 * s(2 * w)), (0, 0, 6 * s(w)))}
    for n in range(5):
        p[f"Arm{n + 1}"] = ((0, 0, 0), (0, 0, 0))
    lift = 18 * max(0.0, s(2 * w)) ** 4                           # waves one arm
    p["Arm1"] = ((0, 0, 0), (-lift, 0, 0))
    return p


def starfish_walk(w):
    p = {"Body": ((0, 0, 0.03 * abs(s(2 * w))), (0, 0, 20 * s(w)))}
    for n in range(5):
        p[f"Arm{n + 1}"] = ((0, 0, 0), (10 * s(2 * w + n * 1.3), 10 * c(2 * w + n * 1.3), 0))
    return p


def flipper_swim(speed, amp):
    def f(w):
        stroke = s(speed * w)
        return {
            "Body": ((0, 0, 0.08 * s(speed * w + 1)), (4 * s(speed * w), 3 * s(w), 0)),
            "Head": ((0, 0, 0), (-5 * s(2 * w), 0, 10 * s(w))),
            "LegFL": ((0, 0, 0), (20 * stroke, -amp * stroke, 0)), "LegFR": ((0, 0, 0), (20 * stroke, amp * stroke, 0)),
            "LegBL": ((0, 0, 0), (0, -amp * 0.4 * s(speed * w + 1), 0)), "LegBR": ((0, 0, 0), (0, amp * 0.4 * s(speed * w + 1), 0)),
        }
    return f


def puffer(speed, amp):
    def f(w):
        puff = max(0.0, s(w)) ** 6
        return {
            "Body": ((0, 0, 0.1 * s(2 * w)), (6 * puff, 4 * s(w), 6 * s(speed * w * 0.5))),
            "WingL": ((0, 0, 0), (0, 0, -amp * s(speed * 4 * w))), "WingR": ((0, 0, 0), (0, 0, amp * s(speed * 4 * w))),
            "Tail": ((0, 0, 0), (0, 0, amp * 1.4 * s(speed * 2 * w))),
        }
    return f


def manta(speed, amp):
    def f(w):
        flap = s(speed * w)
        return {
            "Body": ((0, 0, 0.12 * s(speed * w - 1)), (3 * s(speed * w), 0, 4 * s(w))),
            "WingL": ((0, 0, 0), (0, -amp * flap, 0)), "WingR": ((0, 0, 0), (0, amp * flap, 0)),
            "Tail": ((0, 0, 0), (6 * s(speed * w - 1.5), 0, 10 * s(w))),
        }
    return f


def seahorse(speed):
    def f(w):
        return {
            "Body": ((0, 0, 0.12 * s(speed * w)), (4 * s(speed * w), 0, 8 * s(w))),
            "Head": ((0, 0, 0), (-6 * s(speed * w + 1), 0, 12 * s(w + 1))),
            "Tail": ((0, 0, 0), (12 * s(speed * w - 1), 0, 0)),
            "Tail2": ((0, 0, 0), (20 * s(speed * w - 2), 0, 0)),
        }
    return f


def monkey_fly(speed, pitch):
    def f(w):
        return {
            "Body": ((0, 0, 0.12 * s(speed * w)), (pitch, 4 * s(w), 6 * s(w))),
            "Head": ((0, 0, 0), (-4 * s(2 * w), 0, 14 * s(w + 1))),
            "ArmL": ((0, 0, 0), (-30 + 20 * s(2 * w), -40, 0)), "ArmR": ((0, 0, 0), (-30 + 20 * s(2 * w + 1), 40, 0)),
            "LegL": ((0, 0, 0), (20 + 12 * s(2 * w), 0, 0)), "LegR": ((0, 0, 0), (20 + 12 * s(2 * w + 1.5), 0, 0)),
            "Flame_Glow": ((0, 0, 0), (0, 0, 0)),
            "Tail": ((0, 0, 0), (0, 0, 20 * s(2 * w))),
            "EarL": ((0, 0, 0), (0, -6 * s(3 * w), 0)), "EarR": ((0, 0, 0), (0, 6 * s(3 * w), 0)),
        }
    return f


def hamster_idle(w):
    nib = s(14 * w) * (s(w) > 0)
    return {
        "Body": ((0, 0, 0.012 * (1 - c(2 * w))), (0, 0, 0)),
        "Head": ((0, 0, 0.008 * nib), (-3 * nib, 0, 12 * s(w + 2) * (s(w) <= 0))),
        "LegFL": ((0, 0, 0.03 * max(0.0, s(w))), (-40 * max(0.0, s(w)), 0, 0)),
        "LegFR": ((0, 0, 0.03 * max(0.0, s(w))), (-40 * max(0.0, s(w)), 0, 0)),
        "EarL": ((0, 0, 0), (0, -8 * max(0.0, s(4 * w)) ** 6, 0)),
    }



def capy_idle(w):
    chew = s(8 * w) * (s(w) > 0)                            # chews, then looks around
    return {
        "Body": ((0, 0, 0.01 * (1 - c(2 * w))), (0, 0, 0)),
        "Head": ((0, 0, 0.006 * chew), (-2 * chew, 0, 12 * s(w) * (s(w) <= 0))),
        "EarL": ((0, 0, 0), (0, -14 * max(0.0, s(5 * w)) ** 8, 0)),
        "EarR": ((0, 0, 0), (0, 14 * max(0.0, s(5 * w + 2)) ** 8, 0)),
        "Flower": ((0, 0, 0), (0, 0, 20 * s(w))),
    }


def capy_walk(w):
    p = walk(26, 0.03, 0, 0, 6)(w)
    p["Flower"] = ((0, 0, 0), (6 * s(2 * w), 6 * s(w), 0))
    return p


def axo_idle(w):
    wave = s(3 * w)
    return {
        "Body": ((0, 0, 0.01 * s(2 * w)), (0, 0, 3 * s(w))),
        "Head": ((0, 0, 0), (-3 * s(2 * w), 0, 10 * s(w + 1))),
        "GillL": ((0, 0, 0), (8 * wave, -10 * wave, 0)),
        "GillR": ((0, 0, 0), (8 * wave, 10 * wave, 0)),
        "Tail": ((0, 0, 0), (0, 0, 14 * s(w))),
        "Tail2": ((0, 0, 0), (0, 0, 22 * s(w - 1))),
    }


def axo_walk(w):
    p = walk(34, 0.02, 0, 0, 0)(w)
    p["Body"] = ((0, 0, 0.02 * abs(s(w))), (0, 0, 8 * s(w)))     # wiggles side to side
    p["Head"] = ((0, 0, 0), (0, 0, -8 * s(w)))
    p["Tail"] = ((0, 0, 0), (0, 0, 22 * s(w - 0.6)))
    p["Tail2"] = ((0, 0, 0), (0, 0, 30 * s(w - 1.4)))
    p["GillL"] = ((0, 0, 0), (12 * s(2 * w), -8, 0))
    p["GillR"] = ((0, 0, 0), (12 * s(2 * w), 8, 0))
    return p


def sloth_idle(w):
    nod = max(0.0, s(w)) ** 3                               # dozes off, then wakes up
    return {
        "Body": ((0, 0, 0.015 * s(2 * w)), (2 * s(2 * w), 0, 0)),
        "Head": ((0, 0, 0), (14 * nod, 0, 6 * s(w + 2) * (1 - nod))),
        "Cap": ((0, 0, 0), (4 * nod, 0, 0)),
        "CapTip": ((0, 0, 0), (0, -10 * s(2 * w), 0)),
        "ArmL": ((0, 0, 0), (0, -4 - 3 * s(2 * w), 0)),
        "ArmR": ((0, 0, 0), (-40 * max(0.0, s(w + 3.2)) ** 6, 4 + 3 * s(2 * w), 0)),   # sleepy wave
    }


def sloth_walk(w):
    swing = 18 * s(w)
    return {
        "Body": ((0, 0, 0.04 * abs(s(w))), (3, 0, 5 * s(w))),
        "Head": ((0, 0, 0), (4, -5 * s(w), -4 * s(w))),
        "Cap": ((0, 0, 0), (0, 0, 0)),
        "CapTip": ((0, 0, 0), (0, -14 * s(w - 0.8), 0)),
        "LegL": ((0, 0, 0), (swing, 0, 0)), "LegR": ((0, 0, 0), (-swing, 0, 0)),
        "ArmL": ((0, 0, 0), (-swing * 1.3, -6, 0)), "ArmR": ((0, 0, 0), (swing * 1.3, 6, 0)),
    }


def chameleon_idle(w):
    return {
        "Body": ((0, 0, 0.01 * s(2 * w)), (0, 2 * s(w), 0)),
        "Head": ((0, 0, 0), (-3 * s(2 * w), 0, 8 * s(w))),
        "EyeL": ((0, 0, 0), (12 * s(3 * w), 0, 25 * s(2 * w))),     # each eye looks its own way
        "EyeR": ((0, 0, 0), (12 * s(2 * w + 1), 0, 25 * s(3 * w + 2))),
        "Tail": ((0, 0, 0), (4 * s(w), 0, 0)),
        "Tail2": ((0, 0, 0), (-10 * s(w), 0, 0)),
    }


def chameleon_walk(w):
    p = walk(30, 0.02, 8, 0, 0)(w)
    p["Body"] = ((0, 0, 0.02 * abs(s(w))), (0, 4 * s(w), 6 * s(w)))
    p["EyeL"] = ((0, 0, 0), (0, 0, 20 * s(w)))
    p["EyeR"] = ((0, 0, 0), (0, 0, -20 * s(w + 1)))
    p["Tail2"] = ((0, 0, 0), (-8 * s(2 * w), 0, 0))
    return p


def lucky_cat_idle(w):
    p = cat_idle(w)
    beckon = 18 * s(4 * w)                                  # the lucky wave: paw up beside the face
    p["LegFL"] = ((0.3, -0.5, 0.72), (-10 + beckon, -135, 0))
    p["Body"] = ((0, 0, 0.015 * (1 - c(2 * w))), (-4 + 1.5 * s(4 * w), 0, 0))
    p["Collar"] = ((0, 0, 0), (0, 0, 0))
    p["Bell_Glow"] = ((0, 0, 0), (10 * s(4 * w + 0.6), 0, 0))
    return p


def lucky_cat_walk(w):
    p = walk(30, 0.05, 14, 6, 4)(w)
    p["Bell_Glow"] = ((0, 0, 0), (14 * s(2 * w), 0, 0))
    return p


ANIMS = {
    "Cat": {"Idle": cat_idle, "Walk": walk(30, 0.05, 14, 6, 4)},
    "Dog": {"Idle": dog_idle, "Walk": walk(34, 0.06, 26, -6, 14)},
    "Bunny": {"Idle": bunny_idle, "Walk": hop},
    "Squirrel": {"Idle": squirrel_idle, "Walk": walk(36, 0.1, 10, -10, 0)},
    "Raccoon": {"Idle": raccoon_idle, "Walk": walk(28, 0.04, 16, 4, 6)},
    "Duck": {"Idle": duck_idle, "Walk": waddle},
    "Fox": {"Idle": fox_idle, "Walk": walk(32, 0.05, 18, 0, 6)},
    "Turtle": {"Idle": turtle_idle, "Walk": crawl},
    "Penguin": {"Idle": penguin_idle, "Walk": penguin_walk},
    "Panda": {"Idle": panda_idle, "Walk": heavy_walk},
    "Owl": fly(45, base=owl_idle),
    "Tiger": {"Idle": tiger_idle, "Walk": walk(30, 0.04, 14, -4, 3)},
    "Lion": {"Idle": lion_idle, "Walk": walk(28, 0.04, 10, -4, 0)},
    "ArcticWolf": {"Idle": wolf_idle, "Walk": walk(36, 0.07, 12, -8, 4)},
    "Unicorn": {"Idle": unicorn_idle, "Walk": prance},
    "Dragon": fly(35, quad=True, base=dragon_idle),
    "Phoenix": {"Idle": phoenix_idle, "Walk": phoenix_walk},
    "Kitsune": {"Idle": kitsune_idle, "Walk": kitsune_walk},
    "AutumnStag": {"Idle": stag_idle, "Walk": stag_walk},
    "Hedgehog": {"Idle": hedgehog_idle, "Walk": walk(44, 0.02, 0, 0, 0)},
    "Frog": {"Idle": frog_idle, "Walk": frog_hop},
    "Swan": {"Idle": swan_idle, "Walk": waddle},
    "Beaver": {"Idle": beaver_idle, "Walk": walk(30, 0.03, 0, 0, 0)},
    "Peacock": {"Idle": peacock_idle, "Walk": peacock_walk},
    "Griffin": fly(35, quad=True, base=griffin_idle),
    "Crab": {"Idle": crab_idle, "Walk": crab_walk},
    "Seagull": fly(55, base=duck_idle),
    "Seal": {"Idle": seal_idle, "Walk": seal_walk},
    "Dolphin": {"Idle": swim(6, 14), "Walk": swim(10, 26, 0.12)},
    "Shark": {"Idle": swim(4, 10), "Walk": swim(6, 20, 0.1)},
    "SeaSerpent": {"Idle": serpent(1, 14), "Walk": serpent(2, 22)},
    "Pigeon": fly(50, base=duck_idle),
    "Rat": {"Idle": rat_idle, "Walk": walk(40, 0.03, 0, 0, 0)},
    "Corgi": {"Idle": corgi_idle, "Walk": walk(46, 0.05, 0, 0, 6)},
    "Bulldog": {"Idle": bulldog_idle, "Walk": heavy_walk},
    "RoboPup": {"Idle": robo_idle, "Walk": robo_walk},
    "Gargoyle": fly(35, quad=True, base=dragon_idle),
    "SnowHare": {"Idle": bunny_idle, "Walk": hop},
    "MountainGoat": {"Idle": goat_idle, "Walk": walk(34, 0.07, 0, 0, 6)},
    "SnowLeopard": {"Idle": leopard_idle, "Walk": walk(30, 0.04, 16, -8, 3)},
    "Mammoth": {"Idle": mammoth_idle, "Walk": mammoth_walk},
    "FrostEagle": fly(40, base=eagle_idle),
    "Yeti": {"Idle": yeti_idle, "Walk": yeti_walk},
    "ButterflyQueen": {"Idle": butterfly(6, 50, -4), "Walk": butterfly(2, 65, -12)},
    "Kraken": {"Idle": kraken_anim(1, 14, 0.02), "Walk": kraken_anim(2, 24, 0.05)},
    "MechaRex": {"Idle": rex_idle, "Walk": rex_walk},
    "AuroraWhale": {"Idle": whale(1, 18), "Walk": whale(2, 26)},
    "Capybara": {"Idle": capy_idle, "Walk": capy_walk},
    "Axolotl": {"Idle": axo_idle, "Walk": axo_walk},
    "Sloth": {"Idle": sloth_idle, "Walk": sloth_walk},
    "Chameleon": {"Idle": chameleon_idle, "Walk": chameleon_walk},
    "LuckyCat": {"Idle": lucky_cat_idle, "Walk": lucky_cat_walk},
    "DustBunny": {"Idle": bunny_mob_idle, "Walk": bunny_mob_hop(1.0, 30, 20), "Run": bunny_mob_hop(2.4, 55, 45)},
    "Ladybug": {"Idle": bug_idle, "Walk": bug_walk},
    "Chipmunk": {"Idle": rat_idle, "Walk": walk(40, 0.08, 10, -10, 0)},
    "Bee": {"Idle": bee_fly(12, -4), "Walk": bee_fly(6, -14)},
    "Snail": {"Idle": snail_idle, "Walk": snail_walk},
    "Fawn": {"Idle": unicorn_idle, "Walk": prance},
    "Goose": {"Idle": goose_idle, "Walk": waddle},
    "Badger": {"Idle": badger_idle, "Walk": heavy_walk},
    "Koi": {"Idle": swim(5, 16), "Walk": swim(8, 26, 0.12)},
    "Flamingo": {"Idle": flamingo_idle, "Walk": flamingo_walk},
    "RedPanda": {"Idle": lion_idle, "Walk": walk(30, 0.05, 14, 0, 4)},
    "MossGolem": {"Idle": golem_idle, "Walk": yeti_walk},
    "Pegasus": fly(40, quad=True, base=unicorn_idle),
    "Starfish": {"Idle": starfish_idle, "Walk": starfish_walk},
    "Clownfish": {"Idle": swim(5, 18), "Walk": swim(8, 28, 0.12)},
    "Pelican": fly(45, base=duck_idle),
    "SeaTurtle": {"Idle": flipper_swim(1, 25), "Walk": flipper_swim(2, 40)},
    "Octopus": {"Idle": kraken_anim(1, 16, 0.02), "Walk": kraken_anim(2, 26, 0.05)},
    "Pufferfish": {"Idle": puffer(1, 25), "Walk": puffer(2, 35)},
    "Walrus": {"Idle": seal_idle, "Walk": seal_walk},
    "MantaRay": {"Idle": manta(1, 22), "Walk": manta(2, 32)},
    "Orca": {"Idle": swim(4, 10), "Walk": swim(6, 20, 0.1)},
    "Narwhal": {"Idle": swim(5, 12), "Walk": swim(7, 22, 0.1)},
    "CoralDragon": {"Idle": serpent(1, 14), "Walk": serpent(2, 22)},
    "GoldenSeahorse": {"Idle": seahorse(1), "Walk": seahorse(2)},
    "AlleyCat": {"Idle": cat_idle, "Walk": walk(30, 0.05, 14, 6, 4)},
    "Hamster": {"Idle": hamster_idle, "Walk": walk(44, 0.04, 0, 0, 4)},
    "Crow": fly(50, base=duck_idle),
    "Pug": {"Idle": bulldog_idle, "Walk": walk(40, 0.05, 0, 0, 4)},
    "Dalmatian": {"Idle": dog_idle, "Walk": walk(34, 0.06, 26, -6, 14)},
    "Parrot": fly(55, base=duck_idle),
    "PoliceDog": {"Idle": wolf_idle, "Walk": walk(34, 0.06, 18, -6, 0)},
    "NeonCat": {"Idle": cat_idle, "Walk": walk(30, 0.05, 14, 6, 4)},
    "CyberWolf": {"Idle": wolf_idle, "Walk": walk(36, 0.07, 12, -8, 4)},
    "JetpackMonkey": {"Idle": monkey_fly(2, -4), "Walk": monkey_fly(2, -18)},
    "NeonDragon": fly(35, quad=True, base=dragon_idle),
    "GoldenLion": {"Idle": lion_idle, "Walk": walk(28, 0.04, 10, -4, 0)},
    "ArcticFox": {"Idle": fox_idle, "Walk": walk(32, 0.05, 18, 0, 6)},
    "Lemming": {"Idle": hamster_idle, "Walk": walk(44, 0.04, 0, 0, 4)},
    "Puffin": fly(55, base=duck_idle),
    "Husky": {"Idle": wolf_idle, "Walk": walk(34, 0.06, 20, -10, 0)},
    "Reindeer": {"Idle": unicorn_idle, "Walk": prance},
    "MuskOx": {"Idle": mammoth_idle, "Walk": heavy_walk},
    "PolarBear": {"Idle": panda_idle, "Walk": heavy_walk},
    "FrostBat": fly(60, base=bee_idle),
    "WoollyRhino": {"Idle": bulldog_idle, "Walk": heavy_walk},
    "CrystalStag": {"Idle": unicorn_idle, "Walk": prance},
    "IceDragon": fly(35, quad=True, base=dragon_idle),
    "GlacierTitan": {"Idle": golem_idle, "Walk": yeti_walk},
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
    global U
    U = BASE_U * SCALE.get(key, 1)
    a = PETS[key]()
    path, meta = a.export(out_dir)
    empties = joint_empties(a)
    rest = {k: e.location.copy() for k, e in empties.items()}
    scn = bpy.context.scene
    scn.render.fps = FPS
    ranges = {"Idle": IDLE, "Walk": WALK, "Run": RUN}
    scn.frame_start, scn.frame_end = IDLE[0], max(ranges[k][1] for k in ANIMS[key])
    for kind in ANIMS[key]:
        keyframe(empties, rest, ANIMS[key][kind], ranges[kind])
    for e in empties.values():
        ad = e.animation_data
        if ad and ad.action:
            # the walk starts where the idle ends; hold steady between them
            for m in getattr(ad.action, "fcurves", []) or []:
                for kp in m.keyframe_points:
                    kp.interpolation = "LINEAR"
    anim_dir = os.path.join(out_dir, "anims")
    os.makedirs(anim_dir, exist_ok=True)
    prefix = a.name if a.kind != "alien" else f"Pet_{key}"
    for kind in ANIMS[key]:
        frames, prio = ranges[kind], (0 if kind == "Idle" else 1)
        nm = f"{prefix}_{kind}"
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
    json.dump(allm, open(meta_path, "w"), indent=1)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    main([x for x in args if x in PETS])
