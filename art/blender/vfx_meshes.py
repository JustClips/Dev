"""Rain VFX meshes for Roblox MeshParts.

Builds VfxSplashCrown, VfxRipple, VfxDrop and VfxSplashSheet from scratch,
exports each to art/vfx/meshes/<Name>.glb and renders art/vfx/meshes/preview.png.

Units: 1 Blender metre = 1 stud, Z up, origin at the bottom centre of each mesh.

Run headless:
    blender --background --python art/blender/vfx_meshes.py

Everything is built inside its own scene ("VFX_Meshes"), so running it in an
open Blender session does not touch the file's other scenes.
"""

import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

SCENE_NAME = "VFX_Meshes"
MAT_NAME = "VfxWhite"
NAMES = ["VfxSplashCrown", "VfxRipple", "VfxDrop", "VfxSplashSheet"]


def repo_root():
    here = globals().get("__file__")
    if not here:
        raise RuntimeError("run as a file (blender --python ...) so __file__ is set")
    return os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(here)), "..", ".."))


# ---------------------------------------------------------------- helpers

def ring(r, z, n, phase=0.0):
    return [Vector((r * math.cos(2 * math.pi * (i + phase) / n),
                    r * math.sin(2 * math.pi * (i + phase) / n), z)) for i in range(n)]


def lathe(bm, profile, n, loop=False):
    """Spin a (r, z) profile around Z. Points with r == 0 become single poles."""
    rows = []
    for r, z in profile:
        if r < 1e-6:
            rows.append(bm.verts.new((0.0, 0.0, z)))
        else:
            rows.append([bm.verts.new(v) for v in ring(r, z, n)])
    pairs = list(zip(range(len(rows) - 1), range(1, len(rows))))
    if loop:
        pairs.append((len(rows) - 1, 0))
    for a, b in pairs:
        ra, rb = rows[a], rows[b]
        for i in range(n):
            j = (i + 1) % n
            if isinstance(ra, list) and isinstance(rb, list):
                bm.faces.new((ra[i], ra[j], rb[j], rb[i]))
            elif isinstance(ra, list):
                bm.faces.new((ra[i], ra[j], rb))
            else:
                bm.faces.new((ra, rb[j], rb[i]))


def thick_wall(bm, rows, n, top, thickness):
    """Open-topped, open-bottomed wall with thickness.

    rows: list of (r, z) for the outer surface, bottom to top (last row is
    replaced per-vertex by top(i) -> (r, z)). Inner surface is offset inward.
    The top and bottom rim strips are marked sharp.
    """
    outer, inner = [], []
    for k, (r, z) in enumerate(rows):
        o_row, i_row = [], []
        for i in range(n):
            rr, zz = top(i) if k == len(rows) - 1 else (r, z)
            a = 2 * math.pi * i / n
            c, s = math.cos(a), math.sin(a)
            o_row.append(bm.verts.new((rr * c, rr * s, zz)))
            ri = rr - thickness
            i_row.append(bm.verts.new((ri * c, ri * s, zz)))
        outer.append(o_row)
        inner.append(i_row)
    sharp = []
    for k in range(len(rows) - 1):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((outer[k][i], outer[k][j], outer[k + 1][j], outer[k + 1][i]))
            bm.faces.new((inner[k][j], inner[k][i], inner[k + 1][i], inner[k + 1][j]))
    for k in (0, len(rows) - 1):
        for i in range(n):
            j = (i + 1) % n
            f = bm.faces.new((outer[k][i], inner[k][i], inner[k][j], outer[k][j]))
            sharp.extend(f.edges)
    return sharp


def finish(name, bm, mat, sharp_edges=()):
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)  # outward, per island
    for f in bm.faces:
        f.smooth = True
    for e in sharp_edges:
        e.smooth = False
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    return ob


# ---------------------------------------------------------------- meshes

def build_splash_crown(mat):
    """~1.0 wide, ~0.7 tall flared ring with 8 spikes, each tipped by a bead."""
    bm = bmesh.new()
    spikes, per = 8, 3
    n = spikes * per
    r_top, z_top = 0.44, 0.40
    r_peak, z_peak = 0.48, 0.62

    def top(i):
        return (r_peak, z_peak) if i % per == 0 else (r_top, z_top)

    sharp = thick_wall(bm, [(0.30, 0.0), (0.36, 0.22), (r_top, z_top)], n, top, 0.03)

    bead_r = 0.035
    for s in range(spikes):
        a = 2 * math.pi * (s * per) / n
        centre = Vector(((r_peak - 0.015) * math.cos(a), (r_peak - 0.015) * math.sin(a), z_peak + 0.02))
        bmesh.ops.create_uvsphere(bm, u_segments=6, v_segments=4, radius=bead_r,
                                  matrix=Matrix.Translation(centre))
    return finish("VfxSplashCrown", bm, mat, sharp)


def build_ripple(mat):
    """Flat ring on the ground: radius 1.0, ring thickness 0.06, height 0.02."""
    bm = bmesh.new()
    profile = [(0.975, 0.0), (1.025, 0.0), (1.03, 0.01),
               (1.02, 0.02), (0.98, 0.02), (0.97, 0.01)]
    lathe(bm, profile, 40, loop=True)
    return finish("VfxRipple", bm, mat)


def build_drop(mat):
    """Teardrop, 0.12 wide, 0.3 tall, point up."""
    bm = bmesh.new()
    R = 0.06
    profile = [(0.0, 0.0)]
    for deg in (-60, -30, 0, 30):
        a = math.radians(deg)
        profile.append((R * math.cos(a), R + R * math.sin(a)))
    profile += [(0.036, 0.15), (0.021, 0.21), (0.009, 0.26), (0.0, 0.30)]
    lathe(bm, profile, 12)
    return finish("VfxDrop", bm, mat)


def build_splash_sheet(mat):
    """Low wide flared skirt, 1.4 wide, 0.35 tall, open top, jagged rim."""
    bm = bmesh.new()
    jags, per = 12, 3
    n = jags * per
    rng = random.Random(7)
    heights = [rng.uniform(0.55, 1.0) for _ in range(jags)]
    heights[0] = 1.0  # tallest jag hits exactly 0.35
    r_top, z_top = 0.64, 0.22

    def top(i):
        if i % per == 0:
            h = heights[i // per]
            return (0.70, z_top + (0.35 - z_top) * h)
        return (r_top, z_top)

    rows = [(0.26, 0.0), (0.42, 0.07), (0.56, 0.15), (r_top, z_top)]
    sharp = thick_wall(bm, rows, n, top, 0.025)
    return finish("VfxSplashSheet", bm, mat, sharp)


# ---------------------------------------------------------------- scene / export

def fresh_scene():
    old = bpy.data.scenes.get(SCENE_NAME)
    if old:
        for ob in list(old.objects):
            bpy.data.objects.remove(ob, do_unlink=True)
        bpy.data.scenes.remove(old)
    for name in NAMES + ["VfxPreviewCam", "VfxPreviewSun"]:
        ob = bpy.data.objects.get(name)
        if ob:
            bpy.data.objects.remove(ob, do_unlink=True)
    for name in NAMES:
        me = bpy.data.meshes.get(name)
        if me and me.users == 0:
            bpy.data.meshes.remove(me)
    return bpy.data.scenes.new(SCENE_NAME)


def white_material():
    mat = bpy.data.materials.get(MAT_NAME) or bpy.data.materials.new(MAT_NAME)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (1, 1, 1, 1)
        bsdf.inputs["Roughness"].default_value = 0.4
    mat.diffuse_color = (1, 1, 1, 1)
    return mat


def export_glb(scene, ob, path):
    # Expects `scene` to be the window's active scene (see main()).
    vl = bpy.context.view_layer
    for o in scene.objects:
        o.select_set(False)
    ob.select_set(True)
    vl.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=True,
                              export_apply=True, export_yup=True,
                              export_materials='EXPORT')


def render_preview(scene, objs, path):
    xs = {"VfxRipple": -2.1, "VfxSplashCrown": -0.25, "VfxSplashSheet": 1.25, "VfxDrop": 2.55}
    for ob in objs:
        ob.location.x = xs[ob.name]

    cam_data = bpy.data.cameras.new("VfxPreviewCam")
    cam_data.lens = 50
    cam = bpy.data.objects.new("VfxPreviewCam", cam_data)
    scene.collection.objects.link(cam)
    target = Vector((-0.2, 0.0, 0.2))
    cam.location = Vector((-0.2, -8.2, 3.2))
    cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
    scene.camera = cam

    world = bpy.data.worlds.get("VfxPreviewWorld") or bpy.data.worlds.new("VfxPreviewWorld")
    world.color = (0.05, 0.08, 0.13)
    scene.world = world

    scene.render.engine = 'BLENDER_WORKBENCH'
    sh = scene.display.shading
    sh.light = 'STUDIO'
    sh.color_type = 'MATERIAL'
    sh.show_cavity = True
    sh.show_shadows = True
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 640
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    root = repo_root()
    out_dir = os.path.join(root, "art", "vfx", "meshes")
    os.makedirs(out_dir, exist_ok=True)

    window = bpy.context.window or bpy.context.window_manager.windows[0]
    prev_scene = window.scene
    if prev_scene.name == SCENE_NAME:
        others = [s for s in bpy.data.scenes if s.name != SCENE_NAME]
        prev_scene = others[0] if others else bpy.data.scenes.new("Scene")
        window.scene = prev_scene
    scene = fresh_scene()
    window.scene = scene
    try:
        return build_all(scene, out_dir)
    finally:
        window.scene = prev_scene


def build_all(scene, out_dir):
    mat = white_material()
    objs = [build_splash_crown(mat), build_ripple(mat), build_drop(mat), build_splash_sheet(mat)]
    for ob in objs:
        scene.collection.objects.link(ob)
    bpy.context.view_layer.update()
    stats = {}
    for ob in objs:
        me = ob.data
        me.calc_loop_triangles()
        bb = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
        stats[ob.name] = {
            "tris": len(me.loop_triangles),
            "size": [round(max(v[i] for v in bb) - min(v[i] for v in bb), 3) for i in range(3)],
            "zmin": round(min(v.z for v in bb), 4),
        }
        export_glb(scene, ob, os.path.join(out_dir, ob.name + ".glb"))

    render_preview(scene, objs, os.path.join(out_dir, "preview.png"))
    return stats


if __name__ == "__main__":
    print(main())
