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


def assemble(key, parts):
    """The asset is Alien_<key> (the game's pet model name); its anims are Pet_<key>_Idle/_Walk."""
    name = f"Alien_{key}"
    a = Asset(name, "alien")
    for p in parts:
        o = mesh_part(a, p)
        j = p.joint if p.joint is not None else p.centre()
        a.parts[p.name] = {"obj": o, "parent": p.parent, "joint": [x * U for x in j] if p.parent else None,
                           "glow": p.glow, "material": None, "collide": False}
    a.extra["voxel"] = True
    a.extra["anims"] = {"idle": f"Pet_{key}_Idle", "walk": f"Pet_{key}_Walk"}
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


def fox():
    O, W, D = "E8742A", "F7F1E8", "2B2220"
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
    return assemble("Fox", parts)


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
    return assemble("Owl", parts)


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


def lion():
    G, M, MD, L, N = "E8A93A", "A0581E", "7A3E14", "F6DFB0", "4A2A20"
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
    return assemble("Lion", parts)


# ---------------------------------------------------------------------- arctic wolf


def arctic_wolf():
    W, G, B, N, I = "DCE6F0", "AEBFD3", "F8FBFF", "2A2E38", "6FE6FF"
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
    return assemble("ArcticWolf", parts)


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


def dragon():
    R, D, B, C, M = "D8342C", "8E1C18", "FFC36A", "F4E6C8", "FF7A3A"
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
    a = assemble("Dragon", parts)
    a.extra["aura"] = "Embers"
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


PETS = {"Cat": cat, "Dog": dog, "Bunny": bunny, "Squirrel": squirrel, "Raccoon": raccoon, "Duck": duck,
        "Fox": fox, "Turtle": turtle, "Penguin": penguin,
        "Panda": panda, "Owl": owl, "Tiger": tiger,
        "Lion": lion, "ArcticWolf": arctic_wolf, "Unicorn": unicorn,
        "Dragon": dragon, "Phoenix": phoenix, "Kitsune": kitsune,
        "AutumnStag": autumn_stag}


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
    "Owl": {"Idle": owl_idle, "Walk": owl_walk},
    "Tiger": {"Idle": tiger_idle, "Walk": walk(30, 0.04, 14, -4, 3)},
    "Lion": {"Idle": lion_idle, "Walk": walk(28, 0.04, 10, -4, 0)},
    "ArcticWolf": {"Idle": wolf_idle, "Walk": walk(36, 0.07, 12, -8, 4)},
    "Unicorn": {"Idle": unicorn_idle, "Walk": prance},
    "Dragon": {"Idle": dragon_idle, "Walk": dragon_walk},
    "Phoenix": {"Idle": phoenix_idle, "Walk": phoenix_walk},
    "Kitsune": {"Idle": kitsune_idle, "Walk": kitsune_walk},
    "AutumnStag": {"Idle": stag_idle, "Walk": stag_walk},
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
    json.dump(allm, open(meta_path, "w"), indent=1)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    main([x for x in args if x in PETS])
