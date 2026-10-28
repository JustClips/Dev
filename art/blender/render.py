"""Render preview PNGs of exported GLBs (Cycles CPU, small, for checking the look).

Usage: python render.py out_dir name1 name2 ...   (renders <out_dir>/<name>.glb to <out_dir>/preview/<name>.png)
"""
import bpy
import sys
import os
import math
from mathutils import Vector


def render(glb, png, size=448, yaw=-22):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
        for m in o.data.materials:
            if m and m.use_nodes:
                for n in m.node_tree.nodes:
                    if n.type == "TEX_IMAGE":
                        n.interpolation = "Closest"
    center = (lo + hi) / 2
    radius = max((hi - lo).length / 2, 0.5)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.08, 0.09, 0.16, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.9
    fill = bpy.data.worlds.new("fill")  # noqa: F841 (kept simple: ambient comes from the background)
    scene.world = world
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 50
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    a = math.radians(yaw)
    dist = radius * 3.2
    cam.location = center + Vector((math.sin(a) * dist, -math.cos(a) * dist, radius * 1.1))
    d = center - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 2.6
    so = bpy.data.objects.new("sun", sun)
    so.rotation_euler = (math.radians(50), 0, math.radians(-40))
    scene.collection.objects.link(so)
    # ground disc
    bpy.ops.mesh.primitive_circle_add(radius=radius * 4, fill_type="NGON", location=(center.x, center.y, lo.z))
    g = bpy.context.object
    gm = bpy.data.materials.new("g")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.35, 0.36, 0.42, 1)
    g.data.materials.append(gm)
    scene.render.filepath = png
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    out = sys.argv[1]
    os.makedirs(os.path.join(out, "preview"), exist_ok=True)
    for name in sys.argv[2:]:
        render(os.path.join(out, f"{name}.glb"), os.path.join(out, "preview", f"{name}.png"))
