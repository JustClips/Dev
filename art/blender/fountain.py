"""The Park fountain plaza and its animated water meshes (cartoon style).

  Park_Fountain       the fountain itself: tiled plaza, scalloped stone basin with a
                      fat rounded lip, a two-bowl centre piece with a golden fish on top,
                      four frogs on the rim, lily pads and a flower-bush ring. Parts:
                      Body (basin + plaza, collides), Statue (centre, collides),
                      Critters (fish + frogs), Garden (bushes, lily pads), Water.
  FountainFx_*        water VFX meshes the client animates (FountainController):
                      Jet (fish spout column), Umbrella (spray falling from the jet),
                      Curtain1/2 (water sheets falling off each bowl), Drips1/2 (rings of
                      drops that slide down the sheets), SplashRing1/2 (foam where the
                      sheets land), Ripple (ring that grows and fades), Arc (frog spout),
                      Splash (where an arc lands), Drop (one droplet).

Every FX mesh is built at its real size from the same constants as the fountain, so the
game never has to stretch it. Where each one goes is written into the fountain's meta
("fx", Roblox model space), so code and model can't drift apart.

Same conventions as landmarks.py: 1 m = 1 stud, front = -Y, origin on the ground.
Cartoon look: chunky rounded shapes, bright colours, dark inverted-hull outlines.
"""
import math
import random

import bmesh
import bpy
from mathutils import Vector, Matrix

import lib
from lib import Asset, use, sphere, cyl, torus, box, join, to_roblox

# ------------------------------------------------------------------ palette
STONE, STONE_DARK, STONE_LIGHT = "C9CDD6", "9AA0AE", "E9E5DC"
STONE_WARM = "DCD3C4"
TILE_A, TILE_B, GROUT = "E9DFC9", "D3C6AC", "A99C86"
WATER, WATER_DEEP, WATER_LIGHT, FOAM = "47B8F5", "2C8FD8", "8FDBFF", "EAFBFF"
GOLD, GOLD_DARK, GOLD_LIGHT = "FFB52E", "E5841A", "FFE07A"
FROG, FROG_DARK, FROG_BELLY = "6CCB4A", "3E9A36", "C6EE8E"
LEAF, LEAF_DARK, LEAF_LIGHT = "5DBB4A", "3F9A3A", "86D45E"
INK = "24304A"
MOUTH = "7A2A2A"
FLOWERS = ("FF5A7A", "FFD23A", "FFFFFF", "B07CFF", "FF9A3C")

# ------------------------------------------------------------------ dimensions
LOBES = 8               # scallops on the basin
WALL_IN, WALL_OUT = 6.5, 7.2
LIP_Z = 1.45            # top of the basin wall
POOL_Z = 1.05           # pool water surface
POOL_R = 6.55
BOWL1_R, BOWL1_Z = 3.3, 5.2     # rim radius, rim height
BOWL1_W = 5.0                    # water surface in bowl 1
BOWL2_R, BOWL2_Z = 1.75, 7.55
BOWL2_W = 7.38
FISH_MOUTH_Z = 9.75
JET_H = 1.4             # jet column above the fish mouth
FROG_R = 6.85           # frogs sit on the lip at this radius
FROG_ANGLES = (45, 135, 225, 315)
ARC_LEN, ARC_DROP, ARC_PEAK = 2.6, 1.15, 0.9   # frog spout: forward, down, rise


# ------------------------------------------------------------------ helpers

def _obj_from_bm(bm, name="mesh"):
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return o


def lathe(color, profile, n=40, shape=None, smooth=True, t0=0.0, t1=None):
    """Spin a closed (r, z) loop around Z. shape(t, r, z) -> (r, z) bends it per angle,
    which makes the scallops. t0..t1 (radians) makes a partial ring with end caps."""
    full = t1 is None
    t1 = math.tau if full else t1
    steps = n if full else max(2, n)
    bm = bmesh.new()
    rows = []
    count = steps if full else steps + 1
    for i in range(count):
        t = t0 + (t1 - t0) * i / steps
        row = []
        for (r, z) in profile:
            rr, zz = shape(t, r, z) if shape else (r, z)
            row.append(bm.verts.new((rr * math.cos(t), rr * math.sin(t), zz)))
        rows.append(row)
    m = len(profile)
    pairs = [(i, (i + 1) % count) for i in range(count if full else count - 1)]
    for a, b in pairs:
        ra, rb = rows[a], rows[b]
        for j in range(m):
            k = (j + 1) % m
            quad = [ra[j], rb[j], rb[k], ra[k]]
            uniq = []
            for v in quad:
                if all((v.co - u.co).length > 1e-5 for u in uniq):
                    uniq.append(v)
            if len(uniq) >= 3:
                try:
                    bm.faces.new(uniq)
                except ValueError:
                    pass
    if not full:
        for row in (rows[0], rows[-1]):
            try:
                bm.faces.new(row)
            except ValueError:
                pass
    o = _obj_from_bm(bm, "lathe")
    for poly in o.data.polygons:
        poly.use_smooth = smooth
    lib._asset.paint(o, color)
    return o


def ellipse(cx, cz, rx, rz, k=10, a0=0.0, a1=math.tau, closed=True):
    """(r, z) points round an ellipse, counter-clockwise, for lathe profiles."""
    pts = []
    n = k if closed else k + 1
    for i in range(n):
        a = a0 + (a1 - a0) * i / k
        pts.append((cx + rx * math.cos(a), cz + rz * math.sin(a)))
    return pts


def scallop(lobes, amp, phase=0.0, rmin=0.0):
    """Bulge the radius in `lobes` round scallops (only beyond rmin)."""
    def f(t, r, z):
        if r <= rmin:
            return r, z
        w = abs(math.cos((t + phase) * lobes / 2))
        return r * (1 + amp * (w - 0.5)), z
    return f


def basin_r(t):
    return scallop(LOBES, 0.08)(t, 1.0, 0)[0]


def hull(objs, thick=0.06):
    """Dark outline shell: push every vertex out along its normal and turn the faces in."""
    bm = bmesh.new()
    for o in objs:
        bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bm.normal_update()
    for v in bm.verts:
        v.co += v.normal * thick
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    me = bpy.data.meshes.new("outline")
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("outline", me)
    bpy.context.scene.collection.objects.link(o)
    for poly in o.data.polygons:
        poly.use_smooth = True
    lib._asset.paint(o, INK)
    return o


def outlined(pieces, thick=0.06):
    return pieces + [hull([p], thick) for p in pieces]


def paint_faces(obj, fn):
    """Colour each face by fn(face centre) -> hex."""
    me = obj.data
    uv = me.uv_layers.active.data
    for poly in me.polygons:
        u, v = lib._asset.swatch(fn(poly.center))
        for li in poly.loop_indices:
            uv[li].uv = (u, v)
    return obj


def place(obj, rot_z=0.0, loc=(0, 0, 0), rot_x=0.0):
    m = Matrix.Translation(loc) @ Matrix.Rotation(math.radians(rot_z), 4, "Z") @ Matrix.Rotation(math.radians(rot_x), 4, "X")
    obj.data.transform(m)
    obj.data.update()
    return obj


def eye(loc, size, look=(0, -1, 0)):
    """Low-poly cartoon eye: white, big dark pupil, one shine dot."""
    look = Vector(look).normalized()
    p = Vector(loc)
    return join([sphere("FFFFFF", loc=p, scale=(size, size * 0.9, size * 1.08), seg=12, rings=8),
                 sphere("1B1530", loc=p + look * size * 0.55, scale=(size * 0.72, size * 0.5, size * 0.82), seg=10, rings=6),
                 sphere("FFFFFF", loc=p + look * size * 1.0 + Vector((0.3, 0, 0.3)) * size, scale=size * 0.26, seg=6, rings=4)], "eye")


def teardrop(color, loc, size, down=True, seg=10):
    """Round drop with a pointed tail (tail up when the drop falls)."""
    prof = []
    k = 8
    for i in range(k + 1):
        a = -math.pi / 2 + math.pi * i / k
        r = math.cos(a)
        z = math.sin(a)
        if z > 0:
            r *= (1 - z) ** 0.9   # pull the top into a point
            z = z * 1.7
        prof.append((max(r, 0.0), z))
    pts = [(r * size, z * size) for (r, z) in prof]
    o = lathe(color, pts, n=seg)
    if not down:
        o.data.transform(Matrix.Rotation(math.pi, 4, "X"))
    o.data.transform(Matrix.Translation(loc))
    o.data.update()
    return o


def blob_tube(color, pts, r_fn, seg=8):
    """Smooth tube through a polyline with radius r_fn(i/len)."""
    bm = bmesh.new()
    rings = []
    N = len(pts)
    prev_x = None
    for i, p in enumerate(pts):
        p = Vector(p)
        d = (Vector(pts[min(i + 1, N - 1)]) - Vector(pts[max(i - 1, 0)])).normalized()
        if prev_x is None:
            up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
            x = d.cross(up).normalized()
        else:
            # parallel transport: keep the ring from twisting along the tube
            x = (prev_x - d * prev_x.dot(d)).normalized()
        prev_x = x
        y = d.cross(x).normalized()
        r = r_fn(i / (N - 1))
        rings.append([bm.verts.new(p + (x * math.cos(a) + y * math.sin(a)) * r)
                      for a in (math.tau * j / seg for j in range(seg))])
    for a, b in zip(rings, rings[1:]):
        for j in range(seg):
            k = (j + 1) % seg
            bm.faces.new((a[j], a[k], b[k], b[j]))
    tip0 = bm.verts.new(Vector(pts[0]) - (Vector(pts[1]) - Vector(pts[0])).normalized() * r_fn(0) * 0.8)
    tip1 = bm.verts.new(Vector(pts[-1]) + (Vector(pts[-1]) - Vector(pts[-2])).normalized() * r_fn(1) * 0.8)
    for j in range(seg):
        k = (j + 1) % seg
        bm.faces.new((rings[0][k], rings[0][j], tip0))
        bm.faces.new((rings[-1][j], rings[-1][k], tip1))
    o = _obj_from_bm(bm, "tube")
    for poly in o.data.polygons:
        poly.use_smooth = True
    lib._asset.paint(o, color)
    return o


# ------------------------------------------------------------------ fountain pieces

def plaza():
    """Two rings of chunky paving tiles on a grout disc."""
    p = [lathe(GROUT, [(0.0, 0.0), (9.7, 0.0), (9.7, 0.12), (0.0, 0.12)], n=48, smooth=False)]
    rings = ((7.35, 8.5, 18, 0.0), (8.58, 9.65, 22, 0.5))
    for (r0, r1, count, off) in rings:
        gap = 0.07
        for i in range(count):
            t0 = math.tau * (i + off) / count + gap / r1
            t1 = math.tau * (i + 1 + off) / count - gap / r1
            prof = [(r0 + 0.04, 0.05), (r1 - 0.04, 0.05), (r1 - 0.04, 0.2), (r1 - 0.12, 0.27),
                    (r0 + 0.12, 0.27), (r0 + 0.04, 0.2)]
            p.append(lathe(TILE_A if i % 2 == 0 else TILE_B, prof, n=4, t0=t0, t1=t1, smooth=False))
    return p


def basin():
    shape = scallop(LOBES, 0.08)
    foot = lathe(STONE_DARK, ellipse(WALL_OUT + 0.05, 0.28, 0.32, 0.26, k=5, a0=-math.pi / 2, a1=math.pi / 2, closed=False)
                 + [(WALL_IN + 0.2, 0.54), (WALL_IN + 0.2, 0.02)], n=48, shape=shape)
    wall = lathe(STONE, [(WALL_IN, 0.1), (WALL_OUT, 0.1), (WALL_OUT, LIP_Z), (WALL_IN, LIP_Z)], n=48, shape=shape)
    lip = lathe(STONE_LIGHT, ellipse((WALL_IN + WALL_OUT) / 2, LIP_Z + 0.12, (WALL_OUT - WALL_IN) / 2 + 0.28, 0.27, k=8),
                n=48, shape=shape)
    floor = lathe(WATER_DEEP, [(0.0, 0.1), (WALL_IN + 0.05, 0.1), (WALL_IN + 0.05, 0.3), (0.0, 0.3)], n=40, shape=shape, smooth=False)
    pieces = outlined([foot, wall, lip], 0.07) + [floor]
    # chunky stone bricks on the outside of the wall, two staggered rows
    for row, (z, off) in enumerate(((0.72, 0.0), (1.16, 0.5))):
        count = 40
        for i in range(count):
            t = math.tau * (i + off) / count
            r = WALL_OUT * basin_r(t) + 0.02
            col = (STONE_WARM, STONE, STONE_LIGHT)[(i * 7 + row * 3) % 3]
            b = box(col, size=(0.9, 0.14, 0.36))
            place(b, rot_z=math.degrees(t) + 90, loc=(r * math.cos(t), r * math.sin(t), z))
            pieces.append(b)
    # fat posts with ball caps between the scallops
    for k in range(LOBES):
        t = math.tau * (k + 0.5) / LOBES
        r = WALL_OUT * basin_r(t) - 0.15
        x, y = r * math.cos(t), r * math.sin(t)
        post = lathe(STONE_LIGHT, [(0.0, 0.0), (0.55, 0.0), (0.55, 0.25), (0.45, 0.35), (0.45, 1.75),
                                   (0.55, 1.85), (0.55, 2.0), (0.0, 2.0)], n=10)
        ball = sphere(STONE, loc=(0, 0, 2.3), scale=0.38, seg=10, rings=6)
        knob = sphere(GOLD, loc=(0, 0, 2.72), scale=0.13, seg=6, rings=4)
        for o in (post, ball, knob):
            place(o, loc=(x, y, 0))
        pieces += [post, ball, knob]
    return pieces


def baluster(color, z0, z1, r):
    """Bulgy cartoon column from z0 to z1 with base and top rings."""
    h = z1 - z0
    prof = [(0.0, z0), (r * 1.35, z0), (r * 1.35, z0 + h * 0.08), (r * 1.1, z0 + h * 0.14),
            (r * 0.8, z0 + h * 0.22), (r * 1.2, z0 + h * 0.45), (r * 1.05, z0 + h * 0.6),
            (r * 0.65, z0 + h * 0.8), (r * 0.9, z0 + h * 0.92), (r * 1.15, z1), (0.0, z1)]
    return lathe(color, prof, n=24)


def bowl(R, z_rim, depth, lobes, water_z):
    """Scalloped bowl: rounded underside, fat rim. Returns (stone pieces, water piece, drips)."""
    shape = scallop(lobes, 0.07, rmin=R * 0.6)
    under = [(0.0, z_rim - depth), (R * 0.35, z_rim - depth + 0.02), (R * 0.7, z_rim - depth * 0.7),
             (R * 0.92, z_rim - depth * 0.3)]
    rim = ellipse(R - 0.08, z_rim - 0.06, 0.24, 0.2, k=8, a0=-math.pi / 2, a1=math.pi, closed=False)
    inner = [(R - 0.4, water_z - 0.3), (0.0, water_z - 0.3)]
    stone = lathe(STONE_LIGHT, under + rim + inner, n=40, shape=shape)
    band = lathe(STONE, ellipse(R * 0.7, z_rim - depth * 0.68, 0.14, 0.1, k=6), n=40, shape=scallop(lobes, 0.07, rmin=0))
    water = lathe(WATER, [(0.0, water_z - 0.12), (R - 0.3, water_z - 0.12), (R - 0.3, water_z), (0.0, water_z)],
                  n=40, shape=shape)
    shine = lathe(WATER_LIGHT, ellipse(R * 0.55, water_z + 0.005, R * 0.12, 0.012, k=4), n=24)
    drips = []
    for k in range(lobes):
        t = math.tau * k / lobes
        r = (R + 0.05) * (1 + 0.07 * 0.5)
        d = teardrop(WATER, (0, 0, 0), 0.13, down=False)
        d.data.transform(Matrix.Diagonal((1, 1, 1.8, 1)))
        place(d, loc=(r * math.cos(t), r * math.sin(t), z_rim - 0.32))
        drips.append(d)
    return outlined([stone], 0.06) + [band], [water, shine], drips


def statue():
    """Plinth, two columns and two bowls."""
    p = []
    plinth = lathe(STONE, [(0.0, 0.25), (2.0, 0.25), (2.0, 1.3), (1.85, 1.45), (1.5, 1.5), (1.5, 1.7), (0.0, 1.7)], n=8, smooth=False)
    place(plinth, rot_z=22.5)
    trim = lathe(STONE_LIGHT, ellipse(1.95, 1.35, 0.14, 0.14, k=6), n=8, smooth=False)
    place(trim, rot_z=22.5)
    p += outlined([plinth], 0.06) + [trim]
    col1 = baluster(STONE_LIGHT, 1.7, BOWL1_Z - 0.9, 0.75)
    col2 = baluster(STONE_LIGHT, BOWL1_W - 0.1, BOWL2_Z - 0.55, 0.42)
    p += outlined([col1, col2], 0.05)
    s1, w1, d1 = bowl(BOWL1_R, BOWL1_Z, 1.0, 12, BOWL1_W)
    s2, w2, d2 = bowl(BOWL2_R, BOWL2_Z, 0.6, 10, BOWL2_W)
    p += s1 + s2
    # golden collar the fish sits on
    collar = lathe(GOLD, [(0.0, BOWL2_W - 0.2), (0.62, BOWL2_W - 0.2), (0.7, BOWL2_W + 0.05), (0.55, BOWL2_W + 0.25), (0.0, BOWL2_W + 0.25)], n=16)
    p += outlined([collar], 0.04)
    return p, w1 + w2, d1 + d2


def fish():
    """Chubby golden fish standing on its tail, mouth up, spitting the jet."""
    z = BOWL2_W + 0.2
    body = sphere(GOLD, loc=(0, 0, z + 1.25), scale=(0.72, 0.62, 1.05), seg=16, rings=10)
    # bend it a little forward like it's jumping
    lib.deform(body, lambda v: Vector((v.x, v.y - 0.12 * max(0.0, v.z - (z + 1.2)) ** 2, v.z)))
    belly = sphere(GOLD_LIGHT, loc=(0, -0.3, z + 1.05), scale=(0.5, 0.36, 0.72), seg=12, rings=7)
    tail = []
    for side in (-1, 1):
        f = sphere(GOLD_DARK, loc=(0, 0, 0), scale=(0.22, 0.12, 0.62), seg=12, rings=8)
        f.data.transform(Matrix.Rotation(math.radians(side * 38), 4, "Y"))
        f.data.transform(Matrix.Translation((side * 0.38, 0.05, z + 0.2)))
        f.data.update()
        tail.append(f)
    knot = sphere(GOLD, loc=(0, 0, z + 0.45), scale=(0.34, 0.3, 0.32), seg=12, rings=8)
    fins = []
    for side in (-1, 1):
        f = sphere(GOLD_DARK, loc=(0, 0, 0), scale=(0.12, 0.3, 0.38), seg=10, rings=6)
        f.data.transform(Matrix.Rotation(math.radians(side * -35), 4, "Y"))
        f.data.transform(Matrix.Translation((side * 0.72, 0.05, z + 1.1)))
        f.data.update()
        fins.append(f)
    dorsal = sphere(GOLD_DARK, loc=(0, 0.62, z + 1.35), scale=(0.08, 0.32, 0.5), seg=10, rings=6)
    lips = torus("FF7A4A", loc=(0, -0.22, FISH_MOUTH_Z - 0.1), R=0.22, r=0.1, seg=16, mseg=6)
    lips.data.transform(Matrix.Translation((0, 0, 0)))
    gullet = cyl(MOUTH, loc=(0, -0.22, FISH_MOUTH_Z - 0.12), r=0.16, h=0.1, verts=12)
    eyes = [eye((sx * 0.3, -0.5, z + 1.75), 0.2, look=(sx * 0.25, -1, 0.15)) for sx in (-1, 1)]
    cheeks = [sphere("FF8FA0", loc=(sx * 0.45, -0.5, z + 1.45), scale=(0.12, 0.05, 0.08), seg=6, rings=4) for sx in (-1, 1)]
    scales = []
    for (x, zz) in ((-0.25, 1.0), (0.25, 1.0), (0.0, 0.75), (-0.35, 1.3), (0.35, 1.3)):
        scales.append(sphere(GOLD_LIGHT, loc=(x, 0.45, z + zz), scale=(0.14, 0.06, 0.12), seg=6, rings=4))
    return outlined([body] + tail, 0.045) + [knot, dorsal, belly, lips, gullet] + fins + eyes + cheeks + scales


def frog(angle):
    """Little frog on the lip, facing the middle, mouth open with a spout coming out."""
    z = LIP_Z + 0.32
    body = sphere(FROG, loc=(0, 0, z + 0.35), scale=(0.62, 0.58, 0.45), seg=12, rings=8)
    head = sphere(FROG, loc=(0, -0.25, z + 0.8), scale=(0.58, 0.48, 0.4), seg=12, rings=8)
    belly = sphere(FROG_BELLY, loc=(0, -0.42, z + 0.3), scale=(0.42, 0.25, 0.32), seg=8, rings=6)
    legs = []
    for sx in (-1, 1):
        legs.append(sphere(FROG_DARK, loc=(sx * 0.55, 0.05, z + 0.12), scale=(0.3, 0.45, 0.17), seg=8, rings=5))
        legs.append(sphere(FROG, loc=(sx * 0.32, -0.5, z + 0.06), scale=(0.17, 0.2, 0.1), seg=6, rings=4))
    bumps = [sphere(FROG, loc=(sx * 0.27, -0.25, z + 1.12), scale=0.22, seg=8, rings=6) for sx in (-1, 1)]
    eyes = [eye((sx * 0.27, -0.37, z + 1.16), 0.15, look=(sx * 0.2, -1, 0.1)) for sx in (-1, 1)]
    mouth = sphere(MOUTH, loc=(0, -0.66, z + 0.66), scale=(0.17, 0.1, 0.13), seg=12, rings=6)
    cheeks = [sphere("FF8FA0", loc=(sx * 0.4, -0.58, z + 0.75), scale=(0.1, 0.04, 0.06), seg=6, rings=4) for sx in (-1, 1)]
    spots = [sphere(FROG_DARK, loc=(x, 0.3, zz), scale=(0.1, 0.06, 0.08), seg=6, rings=4)
             for (x, zz) in ((-0.2, z + 0.6), (0.25, z + 0.45), (0.0, z + 0.75))]
    pieces = outlined([body, head], 0.04) + bumps + legs + [belly, mouth] + eyes + cheeks + spots
    # face the centre: front is -Y, so turn -Y toward the origin
    rot = math.degrees(math.radians(angle) - math.pi / 2)
    x, y = FROG_R * math.cos(math.radians(angle)), FROG_R * math.sin(math.radians(angle))
    for o in pieces:
        place(o, rot_z=rot, loc=(x, y, 0))
    mouth_pt = Matrix.Translation((x, y, 0)) @ Matrix.Rotation(math.radians(rot), 4, "Z") @ Vector((0, -0.7, z + 0.66))
    return pieces, mouth_pt


def bushes():
    rnd = random.Random(3)
    p = []
    for k in range(12):
        t = math.tau * (k + 0.5) / 12
        r = 10.35
        cx, cy = r * math.cos(t), r * math.sin(t)
        for j in range(3):
            a = t + (j - 1) * 0.11
            rr = r + rnd.uniform(-0.2, 0.25)
            s = rnd.uniform(0.55, 0.75) * (1.15 if j == 1 else 1)
            col = (LEAF, LEAF_DARK, LEAF_LIGHT)[(k + j) % 3]
            p.append(sphere(col, loc=(rr * math.cos(a), rr * math.sin(a), s * 0.75), scale=(s, s, s * 0.85), seg=9, rings=6))
        for j in range(3):
            a = t + rnd.uniform(-0.15, 0.15)
            rr = r + rnd.uniform(-0.3, 0.3)
            p.append(sphere(FLOWERS[(k + j) % len(FLOWERS)], loc=(rr * math.cos(a), rr * math.sin(a), 1.25 + rnd.uniform(-0.1, 0.15)),
                            scale=0.16, seg=6, rings=4))
    return p


def lily_pads():
    p = []
    rnd = random.Random(5)
    for (r, deg, s) in ((4.6, 10, 0.75), (5.2, 100, 0.6), (4.4, 170, 0.7), (5.4, 250, 0.55), (4.8, 300, 0.8)):
        t = math.radians(deg)
        notch = rnd.uniform(0, 360)
        pad = lathe(LEAF, [(0.0, 0.0), (s, 0.0), (s, 0.06), (0.0, 0.06)], n=16,
                    t0=math.radians(notch + 25), t1=math.radians(notch + 360 - 25), smooth=False)
        place(pad, loc=(r * math.cos(t), r * math.sin(t), POOL_Z + 0.01))
        p.append(pad)
        vein = lathe(LEAF_LIGHT, [(0.0, 0.0), (s * 0.35, 0.0), (s * 0.35, 0.075), (0.0, 0.075)], n=10, smooth=False)
        place(vein, loc=(r * math.cos(t), r * math.sin(t), POOL_Z + 0.01))
        p.append(vein)
        if deg in (100, 300):
            fl = []
            for i in range(6):
                a = math.tau * i / 6
                petal = sphere("FF9AC8", loc=(0.16 * math.cos(a), 0.16 * math.sin(a), 0.18), scale=(0.17, 0.08, 0.1), rot=(0, -30, math.degrees(a)), seg=6, rings=4)
                fl.append(petal)
            fl.append(sphere(GOLD_LIGHT, loc=(0, 0, 0.2), scale=0.09, seg=8, rings=5))
            for o in fl:
                place(o, loc=(r * math.cos(t), r * math.sin(t), POOL_Z + 0.02))
            p += fl
    return p


def pool_water():
    shape = scallop(LOBES, 0.08)
    w = lathe(WATER, [(0.0, POOL_Z - 0.4), (POOL_R, POOL_Z - 0.4), (POOL_R, POOL_Z), (0.0, POOL_Z)], n=56, shape=shape)
    # cartoon highlight swooshes on the surface
    shines = []
    for (r, deg, span) in ((3.6, 200, 50), (5.0, 30, 35), (4.4, 290, 40)):
        s = lathe(WATER_LIGHT, [(r - 0.12, POOL_Z), (r + 0.12, POOL_Z), (r + 0.12, POOL_Z + 0.015), (r - 0.12, POOL_Z + 0.015)],
                  n=8, t0=math.radians(deg), t1=math.radians(deg + span), smooth=False)
        shines.append(s)
    foam = lathe(FOAM, ellipse(WALL_IN - 0.02, POOL_Z, 0.16, 0.06, k=6), n=56, shape=shape)
    return [w, foam] + shines


def fx_points(frog_mouths):
    """Where the client puts each FX mesh (Roblox model space)."""
    curtain1_bottom = POOL_Z
    return {
        "jet": to_roblox((0, -0.22, FISH_MOUTH_Z)),
        "jetTop": to_roblox((0, -0.22, FISH_MOUTH_Z + JET_H)),
        "bowl2": to_roblox((0, 0, BOWL2_Z - 0.1)),
        "bowl2Water": to_roblox((0, 0, BOWL2_W)),
        "bowl1": to_roblox((0, 0, BOWL1_Z - 0.1)),
        "bowl1Water": to_roblox((0, 0, BOWL1_W)),
        "pool": to_roblox((0, 0, curtain1_bottom)),
        "frogs": [to_roblox(m) for m in frog_mouths],
        "poolR": POOL_R,
        "bowl1R": BOWL1_R,
        "bowl2R": BOWL2_R,
    }


def park_fountain(name="Park_Fountain"):
    a = Asset(name, "prop")
    use(a)
    a.cull = True
    a.part("Body", plaza() + basin(), collide=True)
    stone, water, drips = statue()
    a.part("Statue", stone, collide=True)
    critters = fish()
    mouths = []
    for ang in FROG_ANGLES:
        pieces, m = frog(ang)
        critters += pieces
        mouths.append(m)
    a.part("Critters", critters)
    a.part("Garden", bushes() + lily_pads())
    a.part("Water", pool_water() + water + drips)
    a.extra["fx"] = fx_points(mouths)
    return a


# ------------------------------------------------------------------ water FX meshes
# Origins: Jet at its base, Umbrella/Curtain/Drips at the top centre, SplashRing/Ripple/
# Splash on the water surface, Arc at the frog's mouth (pointing -Y), Drop at its centre.

def fx_asset(name):
    a = Asset(name, "prop")
    use(a)
    a.cull = True
    return a


def fx_jet():
    a = fx_asset("FountainFx_Jet")
    H = JET_H
    prof = [(0.0, -0.1)]
    k = 14
    for i in range(k + 1):
        z = H * i / k
        r = 0.2 + 0.05 * math.sin(i * 1.7) - 0.06 * (i / k)
        prof.append((max(r, 0.08), z))
    prof.append((0.0, H + 0.05))
    core = lathe(WATER_LIGHT, prof, n=12)
    paint_faces(core, lambda c: FOAM if (c.y < -0.08 and c.x > -0.05) else WATER_LIGHT)
    crown = []
    for i in range(7):
        t = math.tau * i / 7
        crown.append(sphere(FOAM if i % 2 else WATER_LIGHT, loc=(0.2 * math.cos(t), 0.2 * math.sin(t), H + 0.05), scale=0.13, seg=8, rings=5))
    crown.append(sphere(FOAM, loc=(0, 0, H + 0.15), scale=0.2, seg=10, rings=6))
    a.part("Body", [core] + crown)
    return a


UMB_REACH, UMB_DROP, UMB_PEAK = 1.3, 1.7, 0.45


def fx_umbrella():
    """Palm-crown spray on top of the jet: short fat arcs that curl out and break into
    drops (origin = jet top). The client drops FountainFx_Drop from each arc end."""
    a = fx_asset("FountainFx_Umbrella")
    q = 2 * UMB_DROP + 4 * UMB_PEAK
    b = (q + math.sqrt(q * q - 4 * UMB_DROP * UMB_DROP)) / 2
    k = b - UMB_DROP
    p = []
    n = 8
    for i in range(n):
        t = math.tau * i / n
        pts = []
        for s in range(11):
            u = s / 10
            r = UMB_REACH * u
            pts.append((r * math.cos(t), r * math.sin(t), k * u - b * u * u))
        p.append(blob_tube(WATER_LIGHT if i % 2 else FOAM, pts[:-1],
                           lambda u: 0.13 - 0.04 * u + 0.02 * math.sin(u * 15), seg=8))
        # the tip breaks up into two blobs
        for (u, rad) in ((0.97, 0.09), (1.06, 0.065)):
            r = UMB_REACH * u
            p.append(sphere(WATER_LIGHT, loc=(r * math.cos(t), r * math.sin(t), k * u - b * u * u), scale=rad, seg=8, rings=5))
    a.part("Body", p)
    a.extra["fx"] = {"reach": UMB_REACH, "drop": UMB_DROP}
    return a


def fx_curtain(name, R, drop, lobes):
    """Ribbons of water pouring off each scallop tip of a bowl rim (origin = rim top centre)."""
    a = fx_asset(name)
    k = 7
    prof = []
    for i in range(k + 1):
        u = i / k
        prof.append((R + 0.1 + 0.4 * u ** 1.5, -drop * u))
    loop = prof + [(r - 0.07, z) for (r, z) in reversed(prof)]
    ribbons = []
    half = math.pi / lobes * 0.55
    for i in range(lobes):
        c = math.tau * i / lobes

        def shape(t, r, z, c=c):
            # narrower at the top, splayed and wavy at the bottom
            u = -z / drop
            zz = z
            if u > 0.97:
                zz = z + 0.1 * math.sin((t - c) * 40) + 0.05
            return r, zz
        rb = lathe(WATER, loop, n=6, shape=shape, t0=c - half, t1=c + half)

        def col(cen, c=c):
            d = (math.atan2(cen.y, cen.x) - c + math.pi) % math.tau - math.pi
            return FOAM if abs(d) < half * 0.25 else (WATER_LIGHT if abs(d) < half * 0.65 else WATER)
        paint_faces(rb, col)
        ribbons.append(rb)
    a.part("Body", ribbons)
    return a


def fx_drips(name, R, lobes):
    """Blobs that slide down the ribbons, two per ribbon (origin = rim top centre).
    The client moves the ring down and widens it to follow the ribbons' flare."""
    a = fx_asset(name)
    p = []
    half = math.pi / lobes * 0.55
    for i in range(lobes):
        c = math.tau * i / lobes
        for j, (dt, dz) in enumerate(((-0.4, 0.0), (0.45, -0.35))):
            t = c + dt * half
            r = R + 0.16
            p.append(teardrop(FOAM if j == 0 else WATER_LIGHT, (r * math.cos(t), r * math.sin(t), dz), 0.1, down=True, seg=8))
    a.part("Body", p)
    return a


def fx_splash_ring(name, R):
    """Foam and little splash petals where a curtain lands (origin = water surface centre)."""
    a = fx_asset(name)
    rnd = random.Random(int(R * 10))
    p = []
    n = max(12, int(R * 7))
    for i in range(n):
        t = math.tau * i / n
        r = R + rnd.uniform(-0.1, 0.1)
        x, y = r * math.cos(t), r * math.sin(t)
        p.append(sphere(FOAM, loc=(x, y, 0.05), scale=(0.24, 0.24, 0.13), seg=8, rings=5))
        if i % 2 == 0:
            h = rnd.uniform(0.25, 0.45)
            d = teardrop(WATER_LIGHT if i % 4 else FOAM, (0, 0, 0), 0.09, down=False, seg=8)
            d.data.transform(Matrix.Diagonal((1, 1, 1 + h * 4, 1)))
            d.data.transform(Matrix.Rotation(math.radians(25), 4, "X"))
            place(d, rot_z=math.degrees(t) - 90, loc=(x * 1.04, y * 1.04, 0.15))
            p.append(d)
    a.part("Body", p)
    return a


def fx_ripple():
    """Flat cartoon ring, radius 1 (the client scales it up while it fades)."""
    a = fx_asset("FountainFx_Ripple")
    ring = lathe(FOAM, ellipse(1.0, 0.02, 0.07, 0.025, k=6), n=40)
    inner = lathe(WATER_LIGHT, ellipse(0.86, 0.015, 0.04, 0.015, k=6), n=40)
    a.part("Body", [ring, inner])
    return a


def arc_points(k=12):
    pts = []
    for i in range(k + 1):
        u = i / k
        y = -ARC_LEN * u
        z = ARC_PEAK * 4 * u * (1 - u) * 0.5 - ARC_DROP * u ** 1.5
        pts.append((0.0, y, z))
    return pts


def fx_arc():
    a = fx_asset("FountainFx_Arc")
    pts = arc_points()
    core = blob_tube(WATER_LIGHT, pts, lambda u: 0.13 + 0.05 * u + 0.02 * math.sin(u * 14), seg=8)
    paint_faces(core, lambda c: FOAM if c.z > 0 and c.x > 0 else WATER_LIGHT)
    a.part("Body", [core])
    a.extra["fx"] = {"land": to_roblox(pts[-1])}
    return a


def fx_splash():
    """Small crown splash with a bubble in the middle (origin = water surface)."""
    a = fx_asset("FountainFx_Splash")
    p = [sphere(FOAM, loc=(0, 0, 0.05), scale=(0.35, 0.35, 0.12), seg=10, rings=6)]
    for i in range(7):
        t = math.tau * i / 7
        d = teardrop(WATER_LIGHT if i % 2 else FOAM, (0, 0, 0), 0.08, down=False, seg=8)
        d.data.transform(Matrix.Diagonal((1, 1, 2.6, 1)))
        d.data.transform(Matrix.Rotation(math.radians(35), 4, "X"))
        place(d, rot_z=math.degrees(t) - 90, loc=(0.3 * math.cos(t), 0.3 * math.sin(t), 0.1))
        p.append(d)
    a.part("Body", p)
    return a


def fx_drop():
    a = fx_asset("FountainFx_Drop")
    a.part("Body", [teardrop(WATER_LIGHT, (0, 0, 0), 0.12, down=True, seg=10)])
    return a


ALL = {
    "Park_Fountain": park_fountain,
    "FountainFx_Jet": fx_jet,
    "FountainFx_Umbrella": fx_umbrella,
    "FountainFx_Curtain1": lambda: fx_curtain("FountainFx_Curtain1", BOWL1_R, BOWL1_Z - 0.1 - POOL_Z, 12),
    "FountainFx_Curtain2": lambda: fx_curtain("FountainFx_Curtain2", BOWL2_R, BOWL2_Z - 0.1 - BOWL1_W, 10),
    "FountainFx_Drips1": lambda: fx_drips("FountainFx_Drips1", BOWL1_R, 12),
    "FountainFx_Drips2": lambda: fx_drips("FountainFx_Drips2", BOWL2_R, 10),
    "FountainFx_SplashRing1": lambda: fx_splash_ring("FountainFx_SplashRing1", BOWL1_R + 0.4),
    "FountainFx_SplashRing2": lambda: fx_splash_ring("FountainFx_SplashRing2", BOWL2_R + 0.35),
    "FountainFx_Ripple": fx_ripple,
    "FountainFx_Arc": fx_arc,
    "FountainFx_Splash": fx_splash,
    "FountainFx_Drop": fx_drop,
}
