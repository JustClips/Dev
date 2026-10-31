"""Scene kit for ad thumbnails: imports the game's own GLBs (art/out) into a Blender scene,
adds a blocky player avatar, a grass ground, autumn leaf carpet, sky, sun and camera,
and renders with Cycles. Used by art/ads/scenes.py."""
import math
import os
import random

import bpy
from mathutils import Vector, Euler, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "out"))
_cache = {}
INK = "24304A"  # outline colour of the cartoon props (art/blender/fountain.py)


def srgb(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return tuple(((x + 0.055) / 1.055) ** 2.4 if x > 0.04045 else x / 12.92 for x in c) + (1,)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _cache.clear()


def mat(hexcol, rough=0.6, emit=0.0, name=None):
    key = name or f"m_{hexcol}_{rough}_{emit}"
    m = bpy.data.materials.get(key)
    if m:
        return m
    m = bpy.data.materials.new(key)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = srgb(hexcol)
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = srgb(hexcol)
        b.inputs["Emission Strength"].default_value = emit
    return m


def split_ink(o):
    """Move the ink-coloured outline faces to their own material whose back faces are see-through."""
    import numpy as np
    me = o.data
    if not me.materials or not me.uv_layers:
        return
    m = me.materials[0]
    tex = next((n for n in m.node_tree.nodes if n.type == "TEX_IMAGE"), None) if m and m.use_nodes else None
    if tex is None or tex.image is None:
        return
    img = tex.image
    w, h = img.size
    if not w:
        return
    px = np.array(img.pixels[:]).reshape(h, w, img.channels)[:, :, :3]
    ink = np.array([int(INK[i:i + 2], 16) / 255 for i in (0, 2, 4)])
    # image pixels are linear floats for sRGB images? compare in both spaces
    lin = np.where(ink > 0.04045, ((ink + 0.055) / 1.055) ** 2.4, ink / 12.92)
    uv = me.uv_layers.active.data
    hits = []
    for poly in me.polygons:
        u, v = uv[poly.loop_start].uv
        x = min(w - 1, max(0, int(u * w)))
        y = min(h - 1, max(0, int(v * h)))
        c = px[y, x]
        hits.append(min(np.abs(c - ink).max(), np.abs(c - lin).max()) < 0.03 or c.max() < 0.25)  # any near-black ink
    if not any(hits):
        return
    im = m.copy()
    im.name = m.name + "_ink"
    cull_simple(im)
    me.materials.append(im)
    idx = len(me.materials) - 1
    for poly, hit in zip(me.polygons, hits):
        if hit:
            poly.material_index = idx


def cull_simple(m):
    nt = m.node_tree
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    link = out.inputs["Surface"].links[0]
    src = link.from_socket
    nt.links.remove(link)
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    # see-through from behind, and for every non-camera ray (else the shell shadows its own model)
    lp = nt.nodes.new("ShaderNodeLightPath")
    inv = nt.nodes.new("ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.inputs[0].default_value = 1.0
    nt.links.new(lp.outputs["Is Camera Ray"], inv.inputs[1])
    mx = nt.nodes.new("ShaderNodeMath")
    mx.operation = "MAXIMUM"
    nt.links.new(geo.outputs["Backfacing"], mx.inputs[0])
    nt.links.new(inv.outputs[0], mx.inputs[1])
    nt.links.new(mx.outputs[0], mix.inputs[0])
    nt.links.new(src, mix.inputs[1])
    nt.links.new(tr.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])


def _import(name):
    """Import art/out/<name>.glb once into a hidden source collection; return its root objects."""
    if name in _cache:
        return _cache[name]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, name + ".glb"))
    new = [o for o in bpy.data.objects if o not in before]
    col = bpy.data.collections.new("src_" + name)
    for o in new:
        for c in list(o.users_collection):
            c.objects.unlink(o)
        col.objects.link(o)
        if o.type == "MESH":
            for m in o.data.materials:
                if m and m.use_nodes:
                    for n in m.node_tree.nodes:
                        if n.type == "TEX_IMAGE":
                            n.interpolation = "Closest"

    for o in new:
        if o.type == "MESH":
            split_ink(o)
    # bounds
    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
    bpy.context.view_layer.update()
    for o in new:
        if o.type == "MESH":
            for c in o.bound_box:
                w = o.matrix_world @ Vector(c)
                lo = Vector(map(min, lo, w))
                hi = Vector(map(max, hi, w))
    _cache[name] = (col, lo, hi)
    return _cache[name]


def _instance(name, parent, offset):
    col, lo, hi = _import(name)
    e = bpy.data.objects.new(name + "_inst", None)
    e.instance_type = "COLLECTION"
    e.instance_collection = col
    bpy.context.scene.collection.objects.link(e)
    e.parent = parent
    e.location = offset
    return e


def place(name, loc=(0, 0, 0), yaw=0, scale=1.0, rot=None, ground=True):
    """Instance a game model, centred on loc (bottom on loc.z unless ground=False).
    yaw in degrees around Z. Model front is Blender -Y."""
    _, lo, hi = _import(name)
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    _instance(name, e, (-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -(lo.z if ground else (lo.z + hi.z) / 2)))
    e.location = loc
    e.rotation_euler = Euler([math.radians(a) for a in rot]) if rot else Euler((0, 0, math.radians(yaw)))
    e.scale = (scale,) * 3 if isinstance(scale, (int, float)) else scale
    return e


def size(name):
    _, lo, hi = _import(name)
    return hi - lo


def setup(w=1920, h=1080, samples=48, sky_top="4FA8F0", sky_bot="CFEFFF", sun_energy=4.0,
          sun_rot=(48, 0, -35), world_strength=1.0):
    s = bpy.context.scene
    s.render.engine = "CYCLES"
    s.cycles.device = "CPU"
    s.cycles.samples = samples
    s.cycles.use_denoising = True
    s.cycles.max_bounces = 4
    s.render.resolution_x = w
    s.render.resolution_y = h
    s.render.resolution_percentage = 100
    s.view_settings.view_transform = "Standard"
    s.view_settings.look = "Medium High Contrast" if "Medium High Contrast" in [i.identifier for i in s.view_settings.bl_rna.properties["look"].enum_items] else "None"
    s.render.film_transparent = False
    # sky: vertical gradient seen by camera, flat light for lighting
    wd = bpy.data.worlds.new("sky")
    wd.use_nodes = True
    nt = wd.node_tree
    nt.nodes.clear()
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = srgb(sky_bot)
    ramp.color_ramp.elements[1].position = 0.45
    ramp.color_ramp.elements[1].color = srgb(sky_top)
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs[1].default_value = world_strength
    outn = nt.nodes.new("ShaderNodeOutputWorld")
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], bg.inputs[0])
    nt.links.new(bg.outputs[0], outn.inputs[0])
    # Generated Z for world goes 0..1 bottom..top -> remap: horizon 0.5
    mr = nt.nodes.new("ShaderNodeMapRange")
    mr.inputs[1].default_value = 0.5
    mr.inputs[2].default_value = 0.85
    nt.links.new(sep.outputs["Z"], mr.inputs[0])
    nt.links.new(mr.outputs[0], ramp.inputs[0])
    s.world = wd
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = sun_energy
    sun.angle = math.radians(6)
    so = bpy.data.objects.new("sun", sun)
    so.rotation_euler = Euler([math.radians(a) for a in sun_rot])
    s.collection.objects.link(so)
    return s


def camera(loc, target, lens=35):
    cd = bpy.data.cameras.new("cam")
    cd.lens = lens
    cam = bpy.data.objects.new("cam", cd)
    cam.location = loc
    d = Vector(target) - Vector(loc)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(cam)
    bpy.context.scene.camera = cam
    return cam


def ground(color="72CC4E", size=600, z=0.0):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, z))
    g = bpy.context.object
    g.data.materials.append(mat(color, 0.9))
    return g


def disc(color, r, loc, z=0.02):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=0.04, vertices=48, location=(loc[0], loc[1], z))
    o = bpy.context.object
    o.data.materials.append(mat(color, 0.9))
    return o


def leaf_carpet(x0, x1, y0, y1, step=5.0, seed=1, keep=None, zone="Autumn", jitter=0.6):
    """Tile Clump_<zone>1-4 on a grid, like the game's leaf carpet. keep(x, y) -> bool filters cells."""
    rnd = random.Random(seed)
    names = [f"Clump_{zone}{i}" for i in range(1, 5) if os.path.exists(os.path.join(OUT, f"Clump_{zone}{i}.glb"))]
    out = []
    x = x0
    while x <= x1:
        y = y0
        while y <= y1:
            if keep is None or keep(x, y):
                out.append(place(rnd.choice(names), (x + rnd.uniform(-jitter, jitter), y + rnd.uniform(-jitter, jitter), 0),
                                 yaw=rnd.choice([0, 90, 180, 270]) + rnd.uniform(-10, 10), scale=rnd.uniform(1.0, 1.15)))
            y += step
        x += step
    return out


# ---------------------------------------------------------------- avatar
def _box(name, size, loc, color, parent=None, bevel=0.08):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel:
        m = o.modifiers.new("bev", "BEVEL")
        m.width = bevel
        m.segments = 3
    o.data.materials.append(color if isinstance(color, bpy.types.Material) else mat(color, 0.55))
    bpy.ops.object.shade_smooth()
    if parent:
        o.parent = parent
        o.matrix_parent_inverse = parent.matrix_world.inverted()
    return o


def _pivot(name, loc, parent=None):
    e = bpy.data.objects.new(name, None)
    e.location = loc
    bpy.context.scene.collection.objects.link(e)
    if parent:
        e.parent = parent
        e.location = Vector(loc) - parent.matrix_world.translation if False else loc
    return e


def avatar(loc=(0, 0, 0), yaw=0, skin="F5CD30", shirt="0D69AC", pants="A4BD47", hair=None, scale=1.0,
           arm_r=(0, 0, 0), arm_l=(0, 0, 0), leg_r=(0, 0, 0), leg_l=(0, 0, 0), head=(0, 0, 0),
           face="smile", cap=None, shoes=None):
    """Classic blocky Roblox-style avatar (5 studs tall), built at the origin then moved.
    Limb rotations are degrees (x forward swing, y, z out) around the shoulder/hip.
    Returns dict of pivots, incl. 'hand_r'/'hand_l' empties for holding tools."""
    root = bpy.data.objects.new("Avatar", None)
    bpy.context.scene.collection.objects.link(root)
    parts = {}

    def piv(n, p, parent):
        e = bpy.data.objects.new(n, None)
        bpy.context.scene.collection.objects.link(e)
        e.parent = parent
        e.location = p
        parts[n] = e
        return e

    def child_box(n, size, off, color, parent, bevel=0.08):
        o = _box(n, size, (0, 0, 0), color, bevel=bevel)
        o.parent = parent
        o.location = off
        return o

    torso = piv("torso", (0, 0, 3.0), root)
    child_box("Torso", (2, 1, 2), (0, 0, 0), shirt, torso)
    # legs
    for side, sx, rot in (("r", 0.5, leg_r), ("l", -0.5, leg_l)):
        hip = piv("hip_" + side, (sx, 0, -1.0), torso)
        hip.rotation_euler = Euler([math.radians(a) for a in rot])
        child_box("Leg_" + side, (0.98, 1, 2), (0, 0, -1.0), pants, hip)
        if shoes:
            child_box("Shoe_" + side, (1.0, 1.04, 0.35), (0, -0.02, -1.85), shoes, hip, bevel=0.06)
    # arms
    for side, sx, rot in (("r", 1.5, arm_r), ("l", -1.5, arm_l)):
        sh = piv("shoulder_" + side, (sx, 0, 0.5), torso)
        sh.rotation_euler = Euler([math.radians(a) for a in rot])
        child_box("Arm_" + side, (1, 1, 2), (0, 0, -0.5), skin, sh)
        child_box("Sleeve_" + side, (1.04, 1.04, 0.7), (0, 0, 0.18), shirt, sh, bevel=0.06)
        hand = piv("hand_" + side, (0, 0, -1.35), sh)
    # head
    neck = piv("neck", (0, 0, 1.0), torso)
    neck.rotation_euler = Euler([math.radians(a) for a in head])
    bpy.ops.mesh.primitive_cylinder_add(radius=0.62, depth=1.2, vertices=32, location=(0, 0, 0))
    hd = bpy.context.object
    hd.name = "Head"
    m = hd.modifiers.new("bev", "BEVEL")
    m.width = 0.22
    m.segments = 4
    hd.data.materials.append(mat(skin, 0.5))
    bpy.ops.object.shade_smooth()
    hd.parent = neck
    hd.location = (0, 0, 0.62)
    hd.scale = (1.0, 0.95, 1.0)
    black = mat("1A1A1A", 0.3)
    if face:
        for fx in (-0.22, 0.22):
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.1, location=(0, 0, 0))
            e = bpy.context.object
            e.scale = (0.75, 0.3, 1.25) if face != "wow" else (0.95, 0.3, 1.0)
            e.data.materials.append(black)
            e.parent = neck
            e.location = (fx, -0.6, 0.78)
        if face in ("smile", "grin"):
            bpy.ops.mesh.primitive_torus_add(major_radius=0.26 if face == "smile" else 0.3, minor_radius=0.045,
                                             major_segments=32, minor_segments=8)
            t = bpy.context.object
            # keep lower half only
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.select_all(action="DESELECT")
            bpy.ops.object.mode_set(mode="OBJECT")
            for v in t.data.vertices:
                v.select = v.co.y > 0.02
            bpy.ops.object.mode_set(mode="EDIT")
            bpy.ops.mesh.delete(type="VERT")
            bpy.ops.object.mode_set(mode="OBJECT")
            t.rotation_euler = (math.radians(90), 0, 0)
            t.data.materials.append(black)
            t.parent = neck
            t.location = (0, -0.6, 0.62)
            t.scale = (1, 1, 0.8)
        elif face == "wow":
            bpy.ops.mesh.primitive_uv_sphere_add(radius=0.14, location=(0, 0, 0))
            o = bpy.context.object
            o.scale = (0.9, 0.3, 1.2)
            o.data.materials.append(black)
            o.parent = neck
            o.location = (0, -0.6, 0.42)
    if hair:
        o = child_box("Hair", (1.32, 1.22, 0.45), (0, 0.05, 1.22), hair, neck, bevel=0.15)
        o2 = child_box("HairBack", (1.32, 0.35, 0.9), (0, 0.5, 0.95), hair, neck, bevel=0.12)
    if cap:
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.68, location=(0, 0, 0))
        c = bpy.context.object
        c.scale = (1, 1, 0.62)
        c.data.materials.append(mat(cap, 0.5))
        bpy.ops.object.shade_smooth()
        c.parent = neck
        c.location = (0, 0, 1.12)
        bpy.ops.mesh.primitive_cylinder_add(radius=0.42, depth=0.08)
        b = bpy.context.object
        b.scale = (1, 1.3, 1)
        b.data.materials.append(mat(cap, 0.5))
        b.parent = neck
        b.location = (0, -0.75, 1.0)
    root.location = loc
    root.rotation_euler = (0, 0, math.radians(yaw))
    root.scale = (scale,) * 3
    parts["root"] = root
    return parts


def hold(parts, tool, side="r", rot=(90, 0, 0), off=(0, 0, 0), scale=1.0):
    """Put a tool model in the avatar's hand, pivoting on its meta 'grip'.
    rot (90, 0, 0) points the tool's tip along the arm; (0, 0, 0) points it forward when the arm hangs."""
    import json
    meta = json.load(open(os.path.join(OUT, "meta.json"))).get(tool, {})
    g = meta.get("grip", [0, 0, 0])
    e = bpy.data.objects.new(tool, None)
    bpy.context.scene.collection.objects.link(e)
    _instance(tool, e, (g[0], -g[2], -g[1]))  # Roblox (x, y, z) -> Blender (-x, z, y), negated
    e.parent = parts["hand_" + side]
    e.location = off
    e.rotation_euler = Euler([math.radians(a) for a in rot])
    e.scale = (scale,) * 3
    return e


def glow_mat(hexcol, strength=3.0):
    return mat(hexcol, 0.4, emit=strength)


def recolor(obj_root, material):
    """Override materials of an instanced model by making a real copy (for tinting VFX meshes)."""
    inst = next(c for c in obj_root.children if c.instance_type == "COLLECTION")
    for o in inst.instance_collection.objects:
        if o.type == "MESH":
            c = o.copy()
            c.data = o.data.copy()
            c.data.materials.clear()
            c.data.materials.append(material)
            bpy.context.scene.collection.objects.link(c)
            c.parent = obj_root
            c.matrix_parent_inverse.identity()
            c.matrix_basis = Matrix.Translation(inst.location) @ o.matrix_world
    bpy.data.objects.remove(inst)
    return obj_root


def dof(cam, target, fstop=2.8):
    cam.data.dof.use_dof = True
    cam.data.dof.focus_distance = (Vector(target) - cam.location).length
    cam.data.dof.aperture_fstop = fstop


def render(path):
    s = bpy.context.scene
    s.render.filepath = path
    s.render.image_settings.file_format = "PNG"
    bpy.ops.render.render(write_still=True)
