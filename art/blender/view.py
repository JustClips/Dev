"""Open one asset in Blender's window so you can look at it.

Usage (from the repo root, with Blender's GUI):
  blender --python art/blender/view.py -- Habitat

Builds the asset with the same code as build.py, exports its GLB to art/out/, keeps it
in the scene with its palette material, frames the view on it and saves
art/out/<Name>.blend.
"""
import os
import sys
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import aliens  # noqa: E402
import props  # noqa: E402

OUT = os.path.join(HERE, "..", "out")


def find_builder(name):
    for k, fn in props.ALL.items():
        if k.lower() == name.lower():
            return k, fn
    for table in (aliens.ALL, aliens.VARIANTS):
        for k, fn in table.items():
            if k.lower() in (name.lower(), name.lower().removeprefix("alien_")):
                return f"Alien_{k}", fn
    raise SystemExit(f"No asset called {name}")


def frame_view():
    """Material preview shading and the view framed on the model (GUI only)."""
    if bpy.app.background:
        return None
    for window in bpy.context.window_manager.windows:
        for area in window.screen.areas:
            if area.type != "VIEW_3D":
                continue
            for space in area.spaces:
                if space.type == "VIEW_3D":
                    space.shading.type = "MATERIAL"
            region = next(r for r in area.regions if r.type == "WINDOW")
            with bpy.context.temp_override(window=window, area=area, region=region):
                bpy.ops.object.select_all(action="SELECT")
                bpy.ops.view3d.view_all(center=False)
                bpy.ops.object.select_all(action="DESELECT")
    return None


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    name, fn = find_builder(args[0] if args else "Habitat")
    asset = fn()
    asset.export(OUT)
    # a ground plane so the model doesn't float
    bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, 0))
    ground = bpy.context.view_layer.objects.active
    ground.name = "Ground (not exported)"
    mat = bpy.data.materials.new("Ground")
    mat.diffuse_color = (0.55, 0.56, 0.6, 1)
    if mat.use_nodes:
        mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.55, 0.56, 0.6, 1)
    ground.data.materials.append(mat)
    blend = os.path.abspath(os.path.join(OUT, f"{name}.blend"))
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    print(f"Built {name}: {os.path.abspath(os.path.join(OUT, name + '.glb'))}, saved {blend}")
    # the window may not exist yet while the script runs; frame it a moment later
    bpy.app.timers.register(frame_view, first_interval=0.5)


main()
