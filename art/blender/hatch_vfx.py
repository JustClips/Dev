"""Egg hatch VFX meshes for Roblox MeshParts (HatchController).

Builds, from scratch, white meshes that the game tints and animates at runtime:

  VfxHatchRing    flat shockwave ring with a raised outer lip (radius 1)
  VfxHatchSwirl   two-turn energy ribbon that spirals up around the egg (radius 1, height 2)
  VfxHatchPillar  tapered tube of light, flared at the foot (radius 1, height 1)
  VfxHatchSpikes  starburst of thin light rays leaking out of the egg (radius 1)
  VfxHatchCrown   ring of spikes that erupts from the ground (radius 1, height 1)
  VfxHatchStar    chunky four-point sparkle star (radius 1)
  VfxBrick1x1     a single toy brick with its stud (the egg's shell pieces)
  VfxBrick2x1     a 2x1 brick with two studs
  VfxShellChunk   a curved 3x3 patch of the egg's brick shell, studs on the outside

Units: 1 Blender metre = 1 stud, Z up, origin at the centre (bricks, star, spikes) or the
bottom centre (ring, pillar, crown, swirl). Exports art/out/<Name>.glb and merges
kind="vfx" entries into art/out/meta.json, then renders art/vfx/meshes/hatch_preview.png.

Run headless from the repo root (it starts from an empty file):
    blender --background --python art/blender/hatch_vfx.py
or with a pip bpy:  python art/blender/hatch_vfx.py
"""

import json
import math
import os
import random

import bpy  # noqa: E402 (bpy first: it makes bmesh/mathutils importable)
import bmesh
from mathutils import Matrix, Vector

NAMES = ["VfxHatchRing", "VfxHatchSwirl", "VfxHatchPillar", "VfxHatchSpikes", "VfxHatchCrown",
         "VfxHatchStar", "VfxBrick1x1", "VfxBrick2x1", "VfxShellChunk"]


def repo_root():
    here = globals().get("__file__")
    if not here:
        raise RuntimeError("run as a file so __file__ is set")
    return os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(here)), "..", ".."))


# ---------------------------------------------------------------- helpers

def ring_pts(r, z, n, phase=0.0):
    return [Vector((r * math.cos(2 * math.pi * (i + phase) / n),
                    r * math.sin(2 * math.pi * (i + phase) / n), z)) for i in range(n)]


def lathe(bm, profile, n, closed=False):
    """Spin a (r, z) profile around Z. closed=True joins the last row back to the first."""
    rows = [[bm.verts.new(v) for v in ring_pts(r, z, n)] for r, z in profile]
    pairs = list(zip(range(len(rows) - 1), range(1, len(rows))))
    if closed:
        pairs.append((len(rows) - 1, 0))
    for a, b in pairs:
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((rows[a][i], rows[a][j], rows[b][j], rows[b][i]))
    return rows


def box(bm, lo, hi):
    (x0, y0, z0), (x1, y1, z1) = lo, hi
    v = [bm.verts.new(p) for p in ((x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
                                   (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1))]
    for f in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
        bm.faces.new([v[i] for i in f])
    return v


def cylinder(bm, cx, cy, z0, z1, r, n=10, matrix=None):
    bottom = [bm.verts.new(Vector((cx, cy, z0)) + Vector((r * math.cos(2 * math.pi * i / n), r * math.sin(2 * math.pi * i / n), 0))) for i in range(n)]
    top = [bm.verts.new(Vector((cx, cy, z1)) + Vector((r * math.cos(2 * math.pi * i / n), r * math.sin(2 * math.pi * i / n), 0))) for i in range(n)]
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bottom[i], bottom[j], top[j], top[i]))
    bm.faces.new(list(reversed(bottom)))
    bm.faces.new(top)
    if matrix is not None:
        bmesh.ops.transform(bm, matrix=matrix, verts=bottom + top)
    return bottom + top


def spike(bm, base_center, direction, length, radius, sides=4, twist=0.0):
    """A thin pyramid from base_center pointing along direction."""
    d = direction.normalized()
    up = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
    a = d.cross(up).normalized()
    b = d.cross(a).normalized()
    base = []
    for i in range(sides):
        t = 2 * math.pi * i / sides + twist
        base.append(bm.verts.new(base_center + (a * math.cos(t) + b * math.sin(t)) * radius))
    tip = bm.verts.new(base_center + d * length)
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new((base[i], base[j], tip))
    bm.faces.new(list(reversed(base)))


def finish(name, bm, mat, smooth=False):
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = smooth
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


# ---------------------------------------------------------------- the meshes

def build_ring(mat):
    """A shockwave: thin flat band with a raised, rounded outer lip (reads well from above
    and from the side). Outer radius 1, bottom at z=0."""
    bm = bmesh.new()
    prof = [(0.72, 0.0), (0.80, 0.02), (0.90, 0.05), (0.97, 0.09), (1.0, 0.06), (0.99, 0.0)]
    lathe(bm, prof, 64, closed=True)
    return finish("VfxHatchRing", bm, mat, smooth=True)


def build_swirl(mat):
    """Two turns of ribbon spiralling up and inward; thick enough to show from both sides."""
    bm = bmesh.new()
    turns, steps = 2.0, 96
    rows = []
    for k in range(steps + 1):
        t = k / steps
        a = 2 * math.pi * turns * t
        r = 1.0 - 0.45 * t
        z = 2.0 * t
        w = 0.32 * math.sin(math.pi * min(1.0, t * 1.15)) + 0.04   # taper at both ends
        th = 0.035
        c, s = math.cos(a), math.sin(a)
        radial = Vector((c, s, 0))
        p = Vector((r * c, r * s, z))
        # ribbon width runs mostly up the spiral (slightly tilted), thickness radial
        up = Vector((0, 0, 1))
        rows.append([bm.verts.new(p + up * (-w / 2) + radial * (-th)),
                     bm.verts.new(p + up * (w / 2) + radial * (-th)),
                     bm.verts.new(p + up * (w / 2) + radial * th),
                     bm.verts.new(p + up * (-w / 2) + radial * th)])
    for k in range(steps):
        a_, b_ = rows[k], rows[k + 1]
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((a_[i], a_[j], b_[j], b_[i]))
    bm.faces.new(list(reversed(rows[0])))
    bm.faces.new(rows[-1])
    return finish("VfxHatchSwirl", bm, mat, smooth=True)


def build_pillar(mat):
    """A tube of light: wide flared foot, straight body, a little narrower at the top.
    Has a wall so both sides render."""
    bm = bmesh.new()
    outer = [(1.0, 0.0), (0.82, 0.04), (0.66, 0.12), (0.58, 0.3), (0.55, 0.6), (0.5, 1.0)]
    inner = [(r - 0.04, z) for r, z in reversed(outer)]
    lathe(bm, outer + inner, 40, closed=True)
    return finish("VfxHatchPillar", bm, mat, smooth=True)


def build_spikes(mat):
    """Light leaking out through the cracks: 16 thin rays of mixed length, mostly sideways
    and up, from the centre."""
    rnd = random.Random(7)
    bm = bmesh.new()
    golden = math.pi * (3 - math.sqrt(5))
    for i in range(16):
        y = 1 - (i + 0.5) / 16 * 1.6          # bias upwards
        rr = math.sqrt(max(0.0, 1 - y * y))
        th = golden * i
        d = Vector((math.cos(th) * rr, math.sin(th) * rr, y))
        length = 0.65 + 0.35 * rnd.random()
        spike(bm, d * 0.05, d, length, 0.045 + 0.03 * rnd.random(), sides=4, twist=rnd.random())
    return finish("VfxHatchSpikes", bm, mat)


def build_crown(mat):
    """A ring of 12 spikes on a low band, leaning slightly out; erupts from the ground."""
    bm = bmesh.new()
    lathe(bm, [(0.86, 0.0), (1.0, 0.0), (1.0, 0.08), (0.86, 0.08)], 48, closed=True)
    n = 12
    for i in range(n):
        a = 2 * math.pi * i / n
        c, s = math.cos(a), math.sin(a)
        tall = 1.0 if i % 2 == 0 else 0.62
        base = Vector((0.93 * c, 0.93 * s, 0.04))
        d = Vector((0.18 * c, 0.18 * s, 1.0))
        spike(bm, base, d, tall, 0.11, sides=4, twist=a)
    return finish("VfxHatchCrown", bm, mat)


def build_star(mat):
    """A chunky four-point sparkle with a thin cross, so it reads from any angle."""
    bm = bmesh.new()
    prof = []
    pts = 8
    for i in range(pts):
        a = 2 * math.pi * i / pts + math.pi / 2
        r = 1.0 if i % 2 == 0 else 0.26
        prof.append(Vector((r * math.cos(a), 0.0, r * math.sin(a))))
    for depth_axis in (Vector((0, 1, 0)), Vector((1, 0, 0))):
        rot = Matrix.Identity(3) if depth_axis.y else Matrix.Rotation(math.pi / 2, 3, 'Z')
        front = [bm.verts.new(rot @ (p + Vector((0, 0.09, 0)) * 0)) for p in prof]
        c0 = bm.verts.new(rot @ Vector((0, 0.16, 0)))
        c1 = bm.verts.new(rot @ Vector((0, -0.16, 0)))
        for i in range(pts):
            j = (i + 1) % pts
            bm.faces.new((front[i], front[j], c0))
            bm.faces.new((front[j], front[i], c1))
    return finish("VfxHatchStar", bm, mat)


STUD_R, STUD_H = 0.3, 0.17


def brick(bm, nx, ny, origin=Vector((0, 0, 0)), unit=1.0, height=0.6):
    """A toy brick nx x ny units with studs on top, centred on origin (x/y) with its body
    centred on z."""
    w, d, h = nx * unit, ny * unit, height * unit
    gap = 0.02 * unit
    box(bm, (origin.x - w / 2 + gap, origin.y - d / 2 + gap, origin.z - h / 2),
        (origin.x + w / 2 - gap, origin.y + d / 2 - gap, origin.z + h / 2))
    for i in range(nx):
        for j in range(ny):
            cx = origin.x - w / 2 + unit * (i + 0.5)
            cy = origin.y - d / 2 + unit * (j + 0.5)
            cylinder(bm, cx, cy, origin.z + h / 2, origin.z + h / 2 + STUD_H * unit, STUD_R * unit, n=12)


def build_brick1x1(mat):
    bm = bmesh.new()
    brick(bm, 1, 1)
    bmesh.ops.translate(bm, vec=Vector((0, 0, -STUD_H / 2)), verts=bm.verts)  # centre the whole thing
    return finish("VfxBrick1x1", bm, mat)


def build_brick2x1(mat):
    bm = bmesh.new()
    brick(bm, 2, 1)
    bmesh.ops.translate(bm, vec=Vector((0, 0, -STUD_H / 2)), verts=bm.verts)
    return finish("VfxBrick2x1", bm, mat)


def build_shell_chunk(mat):
    """A 3x3 patch of bricks on a sphere of radius 3.2 (like a piece of the egg's shell),
    studs facing outward, centred on the origin. Width about 3 units."""
    bm = bmesh.new()
    R = 3.2
    step = 1.0 / R
    for i in range(-1, 2):
        for j in range(-1, 2):
            if (i, j) in ((1, 1),):        # a broken corner
                continue
            sub = bmesh.new()
            brick(sub, 1, 1)
            # bricks on the sphere: rotate by the angles of their grid position
            ax, ay = j * step, -i * step
            m = Matrix.Rotation(ax, 4, 'X') @ Matrix.Rotation(ay, 4, 'Y') @ Matrix.Translation((0, 0, R))
            bmesh.ops.transform(sub, matrix=m, verts=sub.verts)
            me = bpy.data.meshes.new("tmp")
            sub.to_mesh(me)
            sub.free()
            bm.from_mesh(me)
            bpy.data.meshes.remove(me)
    bmesh.ops.translate(bm, vec=Vector((0, 0, -R - 0.15)), verts=bm.verts)
    return finish("VfxShellChunk", bm, mat)


BUILDERS = [build_ring, build_swirl, build_pillar, build_spikes, build_crown, build_star,
            build_brick1x1, build_brick2x1, build_shell_chunk]


# ---------------------------------------------------------------- export

def white_material():
    mat = bpy.data.materials.get("VfxWhite") or bpy.data.materials.new("VfxWhite")
    mat.diffuse_color = (1, 1, 1, 1)
    return mat


def export_glb(ob, path):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    loc = ob.location.copy()
    ob.location = (0, 0, 0)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True,
                              export_apply=True, export_yup=True, export_materials='EXPORT')
    ob.location = loc


def bounds(ob):
    xs = [v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in xs), min(v.y for v in xs), min(v.z for v in xs)))
    hi = Vector((max(v.x for v in xs), max(v.y for v in xs), max(v.z for v in xs)))
    # Roblox axes: (-x, z, y)
    return {"min": [round(-hi.x, 3), round(lo.z, 3), round(lo.y, 3)],
            "max": [round(-lo.x, 3), round(hi.z, 3), round(hi.y, 3)]}


def render_preview(objs, path):
    scene = bpy.context.scene
    for k, ob in enumerate(objs):
        ob.location = ((k % 5) * 3.0 - 6.0, 0, -(k // 5) * 3.2)
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = 16.5
    cam = bpy.data.objects.new("Cam", cam_data)
    scene.collection.objects.link(cam)
    cam.location = (0, -20, 6)
    target = Vector((0, 0, -1.4))
    cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = cam
    world = bpy.data.worlds.new("W")
    world.color = (0.05, 0.07, 0.12)
    scene.world = world
    # Cycles on the CPU (headless machines often have no GPU / EGL for Workbench).
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 24
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.07, 0.12, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.5
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-30))
    scene.collection.objects.link(sun)
    cols = [(1, .85, .3, 1), (.6, .4, 1, 1), (.4, .8, 1, 1), (1, 1, .7, 1), (1, .35, .35, 1),
            (1, .9, .4, 1), (.4, .9, .5, 1), (.35, .6, 1, 1), (.9, .55, 1, 1)]
    for ob, c in zip(objs, cols):
        m = bpy.data.materials.new("Prev" + ob.name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = c
        bsdf.inputs["Roughness"].default_value = 0.45
        ob.data.materials[0] = m
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 760
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    root = repo_root()
    out = os.path.join(root, "art", "out")
    os.makedirs(out, exist_ok=True)
    if bpy.app.background:
        bpy.ops.wm.read_factory_settings(use_empty=True)
    mat = white_material()
    objs = [b(mat) for b in BUILDERS]
    meta_path = os.path.join(out, "meta.json")
    meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
    for ob in objs:
        export_glb(ob, os.path.join(out, ob.name + ".glb"))
        meta[ob.name] = {"bounds": bounds(ob), "kind": "vfx", "name": ob.name,
                         "parts": {ob.name: {"collide": False, "glow": None, "joint": None,
                                             "material": None, "parent": None}},
                         "tris": sum(len(p.vertices) - 2 for p in ob.data.polygons)}
        print(ob.name, "tris", meta[ob.name]["tris"])
    json.dump(meta, open(meta_path, "w"), indent=1)
    prev = os.path.join(root, "art", "vfx", "meshes", "hatch_preview.png")
    os.makedirs(os.path.dirname(prev), exist_ok=True)
    render_preview(objs, prev)


main()
