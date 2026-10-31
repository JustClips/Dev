"""Cartoon cloud meshes for the drifting sky clouds (WeatherController).

Builds Cloud1..Cloud5 from metaballs (puffy blobs that merge smoothly), cuts a soft flat
bottom, exports art/out/<Name>.glb, adds them to art/out/meta.json (kind "vfx") and
renders art/out/renders/clouds.png.

    python3 art/blender/clouds.py     # needs bpy (pip install bpy)

Units: 1 metre = 1 stud. Each cloud is about 10 studs wide; the game scales them up.
No texture: the game colours them (white, or grey in rain) and Roblox lighting shades
the underside.
"""
import json
import math
import os
import random

import bpy  # noqa: I001 (bpy first: the pip build only exposes bmesh after it)
import bmesh
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "art", "out")

# Puffs per cloud: (x, y, z, radius). x is the long side, z up, bottom near z = 0.
CLOUDS = {
    "Cloud1": [(-3.2, 0, 0.9, 1.6), (-1.4, 0.2, 1.7, 2.2), (0.6, -0.1, 2.2, 2.6), (2.6, 0.2, 1.5, 2.0), (4.0, 0, 0.8, 1.3), (0.3, 1.3, 1.2, 1.8), (-0.6, -1.2, 1.0, 1.6)],
    "Cloud2": [(-2.4, 0, 1.0, 1.7), (-0.4, 0.1, 2.0, 2.4), (1.8, 0, 1.4, 1.9), (0.6, 1.1, 1.0, 1.5), (-1.2, -1.0, 0.9, 1.4)],
    "Cloud3": [(-1.6, 0, 0.9, 1.5), (0.2, 0, 1.6, 2.0), (1.8, 0.1, 0.9, 1.3), (0.0, -0.9, 0.8, 1.3)],
    "Cloud4": [(-4.4, 0, 0.7, 1.2), (-2.8, 0.2, 1.3, 1.8), (-0.8, 0, 1.8, 2.2), (1.2, 0.1, 2.3, 2.5), (3.2, -0.1, 1.5, 1.9), (4.8, 0, 0.8, 1.2), (0.2, 1.2, 1.0, 1.6), (2.0, -1.1, 0.9, 1.5)],
    "Cloud5": [(-2.0, 0, 0.8, 1.4), (-0.6, 0.1, 1.5, 1.9), (0.9, 0, 2.4, 2.2), (2.3, 0.1, 1.3, 1.6), (0.6, 0.9, 0.8, 1.4)],
}
CUT = 0.35  # flat bottom height


def clear():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.metaballs, bpy.data.materials):
        for item in list(coll):
            coll.remove(item)


def white():
    mat = bpy.data.materials.new("CloudWhite")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (1, 1, 1, 1)
    bsdf.inputs["Roughness"].default_value = 0.9
    mat.diffuse_color = (1, 1, 1, 1)
    return mat


def build(name, puffs, mat):
    mb = bpy.data.metaballs.new(name + "_mb")
    mb.resolution = 0.32
    mb.render_resolution = 0.32
    mb.threshold = 0.6
    for x, y, z, r in puffs:
        el = mb.elements.new()
        el.co = (x, y, z)
        el.radius = r * 1.05
        el.stiffness = 6.0
    mob = bpy.data.objects.new(name + "_mb", mb)
    bpy.context.scene.collection.objects.link(mob)
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(mob.evaluated_get(dg))
    bpy.data.objects.remove(mob, do_unlink=True)

    bm = bmesh.new()
    bm.from_mesh(me)
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, CUT), plane_no=(0, 0, 1), clear_inner=True)
    edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    if edges:
        bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    for v in bm.verts:
        v.co.z -= CUT
    # centre on x/y, bottom at 0
    xs = [v.co.x for v in bm.verts]
    ys = [v.co.y for v in bm.verts]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    for v in bm.verts:
        v.co.x -= cx
        v.co.y -= cy
    bm.to_mesh(me)
    bm.free()
    me.name = name
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = True
    # Flat bottom faces stay flat-shaded so the base reads as a clean edge.
    for p in me.polygons:
        if abs(p.normal.z + 1) < 1e-3:
            p.use_smooth = False
    dec = ob.modifiers.new("dec", "DECIMATE")
    dec.ratio = 1.0
    me.calc_loop_triangles()
    if len(me.loop_triangles) > 3000:
        dec.ratio = 3000 / len(me.loop_triangles)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.modifier_apply(modifier="dec")
    ob.select_set(False)
    return ob


def export(ob):
    for o in bpy.context.scene.objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, ob.name + ".glb"), export_format="GLB",
                              use_selection=True, export_apply=True, export_yup=True, export_materials="EXPORT")


def render(objs, path):
    x = -sum(o.dimensions.x + 2 for o in objs) / 2
    for o in objs:
        o.location.x = x + o.dimensions.x / 2
        x += o.dimensions.x + 2
    scene = bpy.context.scene
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    scene.collection.objects.link(cam)
    cam.location = Vector((0, -46, 2))
    cam.rotation_euler = (Vector((0, 0, 2.2)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 32
    scene.camera = cam
    world = bpy.data.worlds.new("W")
    world.color = (0.3, 0.55, 0.9)
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.3, 0.55, 0.9, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(35), math.radians(20), 0)
    scene.collection.objects.link(sun)
    scene.render.engine = "CYCLES"  # Workbench/EEVEE need a GPU context
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 360
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def main():
    clear()
    mat = white()
    objs = [build(n, p, mat) for n, p in CLOUDS.items()]
    meta_path = os.path.join(OUT, "meta.json")
    meta = json.load(open(meta_path))
    for ob in objs:
        export(ob)
        me = ob.data
        me.calc_loop_triangles()
        xs = [v.co.x for v in me.vertices]
        ys = [v.co.y for v in me.vertices]
        zs = [v.co.z for v in me.vertices]
        # Roblox space: x, z(up)->y, -y->z
        meta[ob.name] = {
            "bounds": {"max": [round(max(xs), 3), round(max(zs), 3), round(-min(ys), 3)],
                       "min": [round(min(xs), 3), round(min(zs), 3), round(-max(ys), 3)]},
            "kind": "vfx", "name": ob.name,
            "parts": {ob.name: {"collide": False, "glow": None, "joint": None, "material": None, "parent": None}},
            "tris": len(me.loop_triangles),
        }
        print(ob.name, len(me.loop_triangles), "tris", [round(d, 2) for d in ob.dimensions])
    json.dump(meta, open(meta_path, "w"), indent=1)
    os.makedirs(os.path.join(OUT, "renders"), exist_ok=True)
    render(objs, os.path.join(OUT, "renders", "clouds.png"))


if __name__ == "__main__":
    main()
