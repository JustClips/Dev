"""Render a tool animation preview (blocky R15 body + the tool) to PNG frames.

Run inside Blender:  blender --background --factory-startup --python preview_render.py -- \
    frames.json Tool_Broom.glb out_dir Broom
frames.json comes from art/anim/preview_data.py (Blender-space world matrices per frame).
"""
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
data_path, glb, out_dir, tid = argv[:4]
data = json.load(open(data_path))[tid]
os.makedirs(out_dir, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try:
        scene.render.engine = engine
        break
    except TypeError:
        continue
scene.render.resolution_x = 360
scene.render.resolution_y = 360
scene.view_settings.view_transform = "Standard"


def mat(name, rgb):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = 0.8
    return m


COL = {"Head": (1.0, 0.8, 0.3), "UpperTorso": (0.15, 0.45, 0.85), "LowerTorso": (0.12, 0.3, 0.6),
       "Arm": (1.0, 0.8, 0.3), "Hand": (1.0, 0.8, 0.3), "Leg": (0.2, 0.6, 0.3), "Foot": (0.15, 0.15, 0.18)}
objs = {}
for name, size in data["sizes"].items():
    bpy.ops.mesh.primitive_cube_add(size=1)
    o = bpy.context.object
    o.name = name
    o.data.transform(Matrix.Diagonal((size[0], size[1], size[2], 1)))
    key = next((k for k in ("Head", "UpperTorso", "LowerTorso", "Hand", "Foot", "Arm", "Leg") if k in name), "Arm")
    o.data.materials.append(mat(name, COL[key]))
    bev = o.modifiers.new("b", "BEVEL")
    bev.width = 0.06
    bev.segments = 2
    objs[name] = o

before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=glb)
parts = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
for o in parts:
    for m in o.data.materials:
        if m and m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type == "TEX_IMAGE":
                    n.interpolation = "Closest"
tool = bpy.data.objects.new("ToolRoot", None)
scene.collection.objects.link(tool)
for o in parts:
    if o.parent is None:
        mw = o.matrix_world.copy()
        o.parent = tool
        o.matrix_parent_inverse = Matrix.Identity(4)
        o.matrix_basis = mw

# ground, light, camera (front three-quarter, a bit above)
bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, -3.19))
bpy.context.object.data.materials.append(mat("ground", (0.45, 0.62, 0.35)))
sun = bpy.data.lights.new("sun", "SUN")
sun.energy = 3.0
so = bpy.data.objects.new("sun", sun)
so.rotation_euler = (math.radians(40), math.radians(15), math.radians(-30))
scene.collection.objects.link(so)
world = bpy.data.worlds.new("w")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.7, 0.9, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
scene.world = world
cam_data = bpy.data.cameras.new("cam")
cam_data.lens = 35
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
target = Vector((-0.4, -1.8, -1.6))  # Roblox front (-Z) is Blender -Y
cam.location = target + Vector((-8.0, -8.5, 3.0))
cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
scene.camera = cam

for i, frame in enumerate(data["frames"][:-1]):
    for name, o in objs.items():
        o.matrix_world = Matrix(frame[name])
    tool.matrix_world = Matrix(frame["Tool"])
    scene.render.filepath = os.path.join(out_dir, f"{i:03d}.png")
    bpy.ops.render.render(write_still=True)
print("rendered", len(data["frames"]) - 1)
