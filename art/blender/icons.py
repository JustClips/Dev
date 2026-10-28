"""Render the UI icon set: chunky 3D objects with a thick navy outline on transparent PNGs.

One look for every icon (same outline weight, camera, light), so the set reads as a set.
Usage: python icons.py [filter ...]  -> art/out/icons/<name>.png (512x512, cropped to fill)
"""
import math
import os
import sys
import random

import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from lib import (Asset, use, sphere, ico, box, cyl, cone, torus, capsule, tube, join, deform,  # noqa: E402
                 noise_deform, build_palette_image, palette_material)
import props  # noqa: E402
import aliens  # noqa: E402

OUT = os.path.join(HERE, "..", "out", "icons")
NAVY = (0.106, 0.122, 0.227, 1)
SIZE = 512


def finish(a):
    img = build_palette_image(a.name, a.colors)
    mat = palette_material(a.name, img)
    for p in a.parts.values():
        p["obj"].data.materials.clear()
        p["obj"].data.materials.append(mat)
    return [p["obj"] for p in a.parts.values()]


def outline(objs, width):
    m = bpy.data.materials.new("outline")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    mix = nt.nodes.new("ShaderNodeMixShader")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs[0].default_value = NAVY
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
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
    nt.links.new(em.outputs[0], mix.inputs[1])
    nt.links.new(tr.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])
    for o in objs:
        o.data.materials.append(m)
        mod = o.modifiers.new("hull", "SOLIDIFY")
        mod.thickness = width
        mod.offset = 1
        mod.use_flip_normals = True
        mod.material_offset = len(o.data.materials) - 1
        mod.use_rim = False


def render(name, objs, yaw=-25, pitch=18, outline_w=None, zoom=1.0):
    scene = bpy.context.scene
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    center = (lo + hi) / 2
    radius = (hi - lo).length / 2
    outline(objs, outline_w or radius * 0.045)
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 32
    scene.cycles.transparent_max_bounces = 128
    scene.cycles.max_bounces = 8
    scene.cycles.use_denoising = True
    scene.render.resolution_x = SIZE
    scene.render.resolution_y = SIZE
    scene.render.film_transparent = True
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (1, 1, 1, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.75
    scene.world = world
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = radius * 2.25 / zoom
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    a, p = math.radians(yaw), math.radians(pitch)
    d = Vector((math.sin(a) * math.cos(p), -math.cos(a) * math.cos(p), math.sin(p)))
    cam.location = center + d * radius * 6
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 2.6
    sun.angle = math.radians(25)
    so = bpy.data.objects.new("sun", sun)
    so.rotation_euler = (math.radians(40), math.radians(-15), math.radians(-35))
    scene.collection.objects.link(so)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{name}.png")
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    crop_to_fill(path)


def crop_to_fill(path, pad=0.03):
    """Crops the render to the icon's visible pixels (plus a thin margin) and scales it
    back to SIZE, so every icon fills its frame and reads big in the UI."""
    import numpy as np
    img = bpy.data.images.load(path)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    ys, xs = np.nonzero(px[:, :, 3] > 0.02)
    if len(xs) == 0:
        return
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    side = int(max(x1 - x0, y1 - y0) * (1 + pad * 2))
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    out = np.zeros((side, side, 4), dtype=np.float32)
    sx0, sy0 = cx - side // 2, cy - side // 2
    for oy in range(side):
        yy = sy0 + oy
        if 0 <= yy < h:
            lo, hi = max(sx0, 0), min(sx0 + side, w)
            out[oy, lo - sx0:hi - sx0] = px[yy, lo:hi]
    crop = bpy.data.images.new(f"{os.path.basename(path)}_crop", side, side, alpha=True)
    crop.pixels[:] = out.ravel()
    crop.scale(SIZE, SIZE)
    crop.filepath_raw = path
    crop.file_format = "PNG"
    crop.save()
    bpy.data.images.remove(crop)
    bpy.data.images.remove(img)


# --------------------------------------------------------------------- icon scenes

def new(name):
    a = Asset(f"Icon_{name}", "icon")
    use(a)
    return a


def coin(a, loc, tilt=0):
    gold, deep = "FFC83C", "E09A14"
    c = cyl(gold, loc=loc, r=1.0, h=0.3, rot=(tilt, 0, 0), verts=28)
    rim = torus(deep, loc=loc, R=0.82, r=0.06, rot=(tilt, 0, 0), seg=28, mseg=6)
    return [c, rim]


def ic_cash():
    a = new("Cash")
    p = []
    p += coin(a, (0.25, 0.2, 0.15))
    p += coin(a, (-0.15, 0.0, 0.48))
    face = cyl("FFC83C", loc=(0.1, -0.35, 1.05), r=1.0, h=0.3, rot=(70, 0, 0), verts=28)
    rim = torus("E09A14", loc=(0.1, -0.45, 1.08), R=0.8, r=0.07, rot=(70, 0, 0), seg=28, mseg=6)
    moon = sphere("FFF0A0", loc=(0.0, -0.52, 1.12), scale=(0.42, 0.08, 0.42), rot=(-20, 0, 0))
    bite = sphere("FFC83C", loc=(0.22, -0.56, 1.22), scale=(0.36, 0.09, 0.36), rot=(-20, 0, 0))
    a.part("Body", p + [face, rim, moon, bite])
    return a, {}


def ic_dust():
    a = new("Dust")
    pile = ico("D8D2C4", loc=(0, 0, 0.0), scale=(1.4, 1.2, 0.85), sub=3, smooth=True)
    noise_deform(pile, 0.12, seed=4, freq=2.0)
    deform(pile, lambda v: Vector((v.x, v.y, max(v.z, 0))))
    top = ico("ECE8DE", loc=(-0.2, -0.1, 0.55), scale=(0.7, 0.6, 0.45), sub=2, smooth=True)
    sparkles = [ico("FFFFFF", loc=(x, -0.6, z), scale=s, sub=1) for x, z, s in ((0.9, 1.1, 0.16), (-0.8, 1.3, 0.12), (0.2, 1.5, 0.1))]
    a.part("Body", [pile, top] + sparkles)
    return a, {"pitch": 22}


def ic_egg():
    a = new("Egg")
    shell = props.egg_shell("7EE08A")
    rnd = random.Random(3)
    spots = []
    for i in range(7):
        p = props.on_egg(rnd.uniform(0.2, 0.8), rnd.uniform(200, 340), out=0.97)
        spots.append(sphere("C8F5B4", loc=p, scale=0.2, seg=10, rings=6))
    a.part("Body", [shell] + spots)
    return a, {"yaw": -10}


def ic_shop():
    a = new("Shop")
    basket = box("FF8C3C", loc=(0, 0, 0.6), size=(2.2, 1.5, 1.2), bevel=0.15)
    deform(basket, lambda v: Vector((v.x * (1 + (v.z - 0.6) * 0.18), v.y * (1 + (v.z - 0.6) * 0.18), v.z)))
    stripe = box("FFC896", loc=(0, -0.77, 0.75), size=(1.9, 0.05, 0.25))
    handle = torus("5A6478", loc=(0, 0, 1.25), R=0.85, r=0.09, rot=(90, 0, 0), seg=24, mseg=6)
    deform(handle, lambda v: Vector((v.x, v.y, max(v.z, 1.25))))
    goods = [sphere("FF5A5A", loc=(-0.5, 0.1, 1.35), scale=0.38), sphere("5AE6B4", loc=(0.35, 0.15, 1.3), scale=0.32),
             props.egg_shell("FFF0A0", h=0.9, r=0.35, z0=1.0)]
    goods[-1].location = (0, 0, 0)
    a.part("Body", [basket, stripe, handle] + goods)
    return a, {}


def ic_index():
    a = new("Index")
    cover = box("3C78FF", loc=(0, 0, 0), size=(2.0, 0.35, 2.5), bevel=0.1, rot=(0, 0, 0))
    pages = box("FFFFFF", loc=(0.05, 0.08, 0.0), size=(1.85, 0.3, 2.35))
    spine = cyl("2A5ACD", loc=(-1.0, 0.0, 0), r=0.22, h=2.5, verts=12)
    face = sphere("8FE38F", loc=(0.1, -0.22, 0.15), scale=(0.62, 0.12, 0.62))
    eyes = [sphere("1B1530", loc=(0.1 + s * 0.22, -0.33, 0.25), scale=(0.11, 0.05, 0.15)) for s in (-1, 1)]
    ant = [capsule("8FE38F", (0.1 + s * 0.2, -0.22, 0.7), (0.1 + s * 0.4, -0.22, 1.0), 0.05) for s in (-1, 1)]
    a.part("Body", [cover, pages, spine, face] + eyes + ant)
    return a, {"yaw": -18, "pitch": 8}


def arrow_arc(col, R, start, end, z=0, r=0.16):
    pts = []
    for i in range(13):
        t = math.radians(start + (end - start) * i / 12)
        pts.append((math.cos(t) * R, 0, math.sin(t) * R + z))
    body = tube(col, pts, r, seg=10)
    t = math.radians(end)
    tip = Vector((math.cos(t) * R, 0, math.sin(t) * R + z))
    tangent = Vector((-math.sin(t), 0, math.cos(t))) * (1 if end > start else -1)
    head = cone(col, loc=tip + tangent * 0.2, r=r * 2.6, h=0.6, verts=12)
    rot = tangent.to_track_quat("Z", "Y").to_euler()
    head.rotation_euler = rot
    bpy.ops.object.select_all(action="DESELECT")
    head.select_set(True)
    bpy.context.view_layer.objects.active = head
    bpy.ops.object.transform_apply(rotation=True)
    return [body, head]


def ic_rebirth():
    a = new("Rebirth")
    planet = sphere("B45AFF", loc=(0, 0, 0), scale=0.85)
    band = torus("FFE36E", loc=(0, 0, 0), R=0.86, r=0.07, rot=(70, 0, 0))
    arrows = arrow_arc("5AFFC8", 1.45, 200, 340) + arrow_arc("5AFFC8", 1.45, 20, 160)
    a.part("Body", [planet, band] + arrows)
    return a, {"yaw": 0, "pitch": 4}


def ic_base():
    a = props.habitat()
    return a, {"yaw": -20, "pitch": 20}


def ic_sell():
    a = props.rocket()
    return a, {"yaw": -15, "pitch": 10}


def ic_zones():
    a = new("Zones")
    ring = torus("5A6478", loc=(0, 0, 0), R=1.2, r=0.28, rot=(90, 0, 0), seg=32, mseg=10)
    inner = cyl("78E6FF", loc=(0, 0.05, 0), r=1.0, h=0.1, rot=(90, 0, 0), verts=28)
    swirl = torus("C878FF", loc=(0, -0.05, 0), R=0.55, r=0.1, rot=(90, 0, 0), seg=24, mseg=6)
    dot = sphere("FFFFFF", loc=(0, -0.1, 0), scale=(0.2, 0.08, 0.2))
    studs = [sphere("FFD23C", loc=(math.cos(math.radians(t)) * 1.2, -0.25, math.sin(math.radians(t)) * 1.2), scale=0.13) for t in range(0, 360, 60)]
    base = box("5A6478", loc=(0, 0, -1.55), size=(1.6, 0.8, 0.35), bevel=0.1)
    a.part("Body", [ring, inner, swirl, dot, base] + studs)
    return a, {"yaw": -15, "pitch": 6}


def ic_luck():
    a = new("Luck")
    leaves = []
    for k in range(4):
        t = math.radians(45 + k * 90)
        for s in (-1, 1):
            off = Vector((math.cos(t + s * 0.35), 0, math.sin(t + s * 0.35))) * 0.62
            leaves.append(sphere("50D25A", loc=off, scale=(0.42, 0.12, 0.42)))
    stem = capsule("3CA046", (0, 0, 0), (0.35, 0, -1.25), 0.09)
    star = ico("FFE36E", loc=(0, -0.15, 0), scale=(0.28, 0.1, 0.28), sub=1)
    a.part("Body", leaves + [stem, star])
    return a, {"yaw": 0, "pitch": 4}


def bolt_mesh(col, depth=0.4):
    pts = [(-0.2, 1.3), (0.75, 1.3), (0.25, 0.25), (0.8, 0.25), (-0.45, -1.4), (-0.05, -0.15), (-0.6, -0.15)]
    me = bpy.data.meshes.new("bolt")
    verts = [(x, -depth / 2, z) for x, z in pts] + [(x, depth / 2, z) for x, z in pts]
    n = len(pts)
    faces = [list(range(n))[::-1], list(range(n, 2 * n))]
    for i in range(n):
        j = (i + 1) % n
        faces.append([i, j, n + j, n + i])
    me.from_pydata(verts, [], faces)
    me.update()
    o = bpy.data.objects.new("bolt", me)
    bpy.context.scene.collection.objects.link(o)
    import lib
    lib._asset.paint(o, col)
    bev = o.modifiers.new("b", "BEVEL")
    bev.width = 0.06
    bev.segments = 2
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.ops.object.modifier_apply(modifier="b")
    return o


def ic_boost():
    a = new("Boost")
    a.part("Body", [bolt_mesh("FFD23C")])
    return a, {"yaw": -12, "pitch": 4}


def ic_gift():
    a = new("Gift")
    b = box("FF5A9A", loc=(0, 0, 0), size=(1.8, 1.8, 1.4), bevel=0.08)
    lid = box("FF5A9A", loc=(0, 0, 0.8), size=(2.0, 2.0, 0.4), bevel=0.08)
    r1 = box("FFE36E", loc=(0, 0, 0.2), size=(0.35, 2.05, 2.05))
    r2 = box("FFE36E", loc=(0, 0, 0.2), size=(2.05, 0.35, 2.05))
    bows = [torus("FFE36E", loc=(s * 0.38, 0, 1.25), R=0.35, r=0.1, rot=(90, s * 30, 0), seg=18, mseg=6) for s in (-1, 1)]
    a.part("Body", [b, lid, r1, r2] + bows)
    return a, {}


def ic_vehicle():
    a = props.vehicle("SweeperCart", 1.0, "50C878", "cart")
    return a, {"yaw": -35, "pitch": 18}


def ic_tool():
    a = new("Tool")
    props.broom(a)
    for p in a.parts.values():
        o = p["obj"]
        o.rotation_euler = (math.radians(90), math.radians(35), 0)
    shaft = box("5AE650", loc=(1.5, 0, 0.3), size=(0.45, 0.4, 1.3), bevel=0.06)
    head = cone("5AE650", loc=(1.5, 0, 1.25), r=0.65, h=0.7, verts=4, rot=(0, 0, 45))
    a.part("Arrow", [shaft, head])
    bpy.context.view_layer.update()
    return a, {"yaw": 0, "pitch": 6}


def ic_auto():
    a = new("Auto")
    g = cyl("5AE6B4", loc=(0, 0, 0), r=1.0, h=0.5, rot=(90, 0, 0), verts=24)
    teeth = [box("5AE6B4", loc=(math.cos(math.radians(t)) * 1.1, 0, math.sin(math.radians(t)) * 1.1), size=(0.42, 0.5, 0.42), rot=(0, -t, 0)) for t in range(0, 360, 45)]
    hole = cyl("2A8C78", loc=(0, -0.05, 0), r=0.42, h=0.55, rot=(90, 0, 0), verts=20)
    arrows = arrow_arc("FFFFFF", 1.75, 120, 230, r=0.12)
    a.part("Body", [g, hole] + teeth + arrows)
    return a, {"yaw": 0, "pitch": 4}


def star_mesh(col, r1=1.2, r2=0.55, depth=0.45):
    pts = []
    for i in range(10):
        t = math.radians(90 + i * 36)
        rr = r1 if i % 2 == 0 else r2
        pts.append((math.cos(t) * rr, math.sin(t) * rr))
    me = bpy.data.meshes.new("star")
    n = len(pts)
    verts = [(x, 0, z) for x, z in pts] + [(0, -depth, 0), (0, depth * 0.6, 0)]
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces.append([j, i, n])
        faces.append([i, j, n + 1])
    me.from_pydata(verts, [], faces)
    me.update()
    o = bpy.data.objects.new("star", me)
    bpy.context.scene.collection.objects.link(o)
    import lib
    lib._asset.paint(o, col)
    return o


def ic_star():
    a = new("Star")
    a.part("Body", [star_mesh("FFC83C")])
    return a, {"yaw": -10, "pitch": 4}


def ic_lock():
    a = new("Lock")
    b = box("FFC83C", loc=(0, 0, 0), size=(1.8, 0.8, 1.5), bevel=0.15)
    sh = torus("B4BCCD", loc=(0, 0, 0.75), R=0.6, r=0.17, rot=(90, 0, 0), seg=24, mseg=8)
    deform(sh, lambda v: Vector((v.x, v.y, max(v.z, 0.7))))
    hole = sphere("5A3A14", loc=(0, -0.42, 0.1), scale=(0.18, 0.05, 0.18))
    slot = box("5A3A14", loc=(0, -0.41, -0.18), size=(0.12, 0.04, 0.4))
    a.part("Body", [b, sh, hole, slot])
    return a, {"yaw": -15, "pitch": 8}


def ic_timer():
    a = new("Timer")
    body = cyl("FF5A5A", loc=(0, 0, 0), r=1.1, h=0.5, rot=(90, 0, 0), verts=28)
    face = cyl("FFFFFF", loc=(0, -0.2, 0), r=0.88, h=0.2, rot=(90, 0, 0), verts=28)
    btn = cyl("5A6478", loc=(0, 0, 1.3), r=0.22, h=0.4, verts=12)
    hands = [box("1B1F3A", loc=(0, -0.33, 0.25), size=(0.1, 0.05, 0.6)), box("1B1F3A", loc=(0.18, -0.33, 0), size=(0.45, 0.05, 0.1))]
    a.part("Body", [body, face, btn] + hands)
    return a, {"yaw": -10, "pitch": 6}


def ic_meteor():
    a = new("Meteor")
    rock = ico("8C7A6E", loc=(0.45, 0, -0.45), scale=0.75, sub=2)
    noise_deform(rock, 0.12, seed=2, freq=2)
    flame = [cone(c, loc=(-0.2 - k * 0.35, 0, 0.2 + k * 0.35), r=0.65 - k * 0.15, h=1.4, rot=(0, -45, 0), verts=16) for k, c in enumerate(("FF8C3C", "FFC83C", "FFF0A0"))]
    a.part("Body", [rock] + flame)
    return a, {"yaw": 0, "pitch": 4}


def ic_alien():
    a = aliens.blip()
    return a, {"yaw": -12, "pitch": 10}


def ic_upgrade():
    a = new("Upgrade")
    shaft = box("5AE650", loc=(0, 0, -0.45), size=(0.9, 0.55, 1.5), bevel=0.08)
    head = cone("5AE650", loc=(0, 0, 0.75), r=1.35, h=1.1, verts=4, rot=(0, 0, 45))
    star = star_mesh("FFD23C", r1=0.55, r2=0.25, depth=0.3)
    star.location = (1.15, -0.3, -0.85)
    a.part("Body", [shaft, head, star])
    return a, {"yaw": -12, "pitch": 6}


def ic_speed():
    a = new("Speed")
    sole = box("5A6478", loc=(0.15, 0, -1.05), size=(2.1, 1.0, 0.35), bevel=0.1)
    foot = box("78E6FF", loc=(0.25, 0, -0.65), size=(1.9, 0.95, 0.6), bevel=0.2)
    leg = box("78E6FF", loc=(-0.35, 0, 0.25), size=(0.95, 0.9, 1.4), bevel=0.2)
    cuff = box("FFFFFF", loc=(-0.35, 0, 1.0), size=(1.1, 1.0, 0.3), bevel=0.08)
    stripe = box("FFD23C", loc=(0.1, -0.5, -0.55), size=(1.2, 0.08, 0.2), bevel=0.03)
    lines = [box("FFFFFF", loc=(-1.6, 0, z), size=(0.8 - k * 0.15, 0.25, 0.16), bevel=0.05)
             for k, z in enumerate((0.4, -0.15, -0.7))]
    a.part("Body", [sole, foot, leg, cuff, stripe] + lines)
    return a, {"yaw": -8, "pitch": 6}


def ic_backpack():
    a = new("Backpack")
    body = box("FF9A3C", loc=(0, 0, 0), size=(1.7, 1.0, 2.1), bevel=0.3)
    flap = box("E07A1E", loc=(0, -0.05, 0.75), size=(1.75, 1.05, 0.7), bevel=0.22)
    pocket = box("E07A1E", loc=(0, -0.55, -0.35), size=(1.2, 0.3, 0.8), bevel=0.15)
    buckle = box("FFD23C", loc=(0, -0.6, 0.4), size=(0.35, 0.12, 0.3), bevel=0.04)
    handle = torus("5A6478", loc=(0, 0, 1.15), R=0.35, r=0.09, rot=(90, 0, 0), seg=18, mseg=6)
    dust = [sphere("C8CCDC", loc=(x, -0.2, 1.3), scale=0.22) for x in (-0.45, 0.45)]
    a.part("Body", [body, flap, pocket, buckle, handle] + dust)
    return a, {"yaw": -20, "pitch": 10}


ICONS = {
    "Cash": ic_cash, "Dust": ic_dust, "Egg": ic_egg, "Shop": ic_shop, "Index": ic_index, "Rebirth": ic_rebirth,
    "Base": ic_base, "Sell": ic_sell, "Zones": ic_zones, "Luck": ic_luck, "Boost": ic_boost, "Gift": ic_gift,
    "Vehicle": ic_vehicle, "Tool": ic_tool, "Auto": ic_auto, "Star": ic_star, "Lock": ic_lock, "Timer": ic_timer,
    "Meteor": ic_meteor, "Alien": ic_alien, "Upgrade": ic_upgrade, "Speed": ic_speed, "Backpack": ic_backpack,
}


# ---------------------------------------------------------------- tools, cars, potions

def tool_icon(tool_id):
    def build():
        a = new(f"Tool_{tool_id}")
        props.TOOLS[tool_id][0](a)
        for p in a.parts.values():
            p["obj"].rotation_euler = (math.radians(-90), math.radians(-40), 0)
        bpy.context.view_layer.update()
        return a, {"yaw": 0, "pitch": 6}
    return build


def car_icon(car_id):
    def build():
        a = props.VEHICLES[car_id]()
        a.name = f"Icon_Car_{car_id}"
        return a, {"yaw": -38, "pitch": 20}
    return build


def potion(name, liquid, symbol):
    def build():
        a = new(name)
        flask = sphere("E6F5FF", loc=(0, 0, 0), scale=1.0, seg=24, rings=14)
        deform(flask, lambda v: v if v.z > 0.28 else v * 0.95)
        juice = sphere(liquid, loc=(0, 0, 0), scale=0.995, seg=24, rings=14)
        deform(juice, lambda v: Vector((v.x, v.y, min(v.z, 0.3))))
        surface = cyl(aliens.shade(liquid, 0.3), loc=(0, 0, 0.3), r=0.95, h=0.02, verts=24)
        shine = sphere("FFFFFF", loc=(-0.45, -0.75, 0.35), scale=(0.16, 0.08, 0.28))
        neck = cyl("E6F5FF", loc=(0, 0, 1.15), r=0.32, h=0.6, verts=16)
        rim = torus("E6F5FF", loc=(0, 0, 1.42), R=0.34, r=0.08, seg=18, mseg=6)
        cork = cyl("B4783C", loc=(0, 0, 1.6), r=0.27, r2=0.32, h=0.4, verts=14)
        bubbles = [sphere(aliens.shade(liquid, 0.4), loc=(x, -0.86, z), scale=r) for x, z, r in ((0.3, -0.3, 0.1), (0.05, 0.05, 0.07), (-0.2, -0.45, 0.08))]
        a.part("Body", [flask, juice, surface, shine, neck, rim, cork] + bubbles + symbol())
        return a, {"yaw": -10, "pitch": 8}
    return build


def sym_clover():
    leaves = [sphere("3CDC5A", loc=(math.cos(t) * 0.24, -0.98, -0.15 + math.sin(t) * 0.24), scale=(0.2, 0.05, 0.2)) for t in [i * math.pi / 2 + math.pi / 4 for i in range(4)]]
    return leaves


def sym_coin():
    return [cyl("FFD23C", loc=(0, -0.98, -0.15), r=0.38, h=0.08, rot=(90, 0, 0), verts=20),
            box("E0A020", loc=(0, -1.03, -0.15), size=(0.12, 0.04, 0.4))]


def sym_bolt():
    o = bolt_mesh("FFE36E", depth=0.08)
    o.scale = (0.35, 0.35, 0.35)
    o.location = (0, -0.98, -0.15)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return [o]


def sym_egg():
    return [sphere("FFF5DC", loc=(0, -0.95, -0.15), scale=(0.24, 0.12, 0.32)),
            sphere("FF9A3C", loc=(0.08, -1.05, -0.05), scale=(0.06, 0.03, 0.06))]


def ic_daily():
    a = new("Daily")
    page = box("FFFFFF", loc=(0, 0, 0), size=(2.0, 0.4, 1.9), bevel=0.12)
    top = box("FF4A5A", loc=(0, 0, 0.85), size=(2.05, 0.45, 0.55), bevel=0.12)
    rings = [torus("5A6478", loc=(x, 0, 1.15), R=0.16, r=0.05, rot=(90, 0, 0), seg=14, mseg=5) for x in (-0.55, 0.55)]
    grid = [box("C8D2E6", loc=(-0.6 + (i % 3) * 0.6, -0.22, 0.25 - (i // 3) * 0.45), size=(0.42, 0.04, 0.3)) for i in range(6)]
    star = star_mesh("FFD23C", r1=0.45, r2=0.2, depth=0.18)
    star.location = (0.55, -0.35, -0.35)
    a.part("Body", [page, top, star] + rings + grid)
    return a, {"yaw": -14, "pitch": 8}


def ic_group():
    a = new("Group")
    pieces = []
    for x, col, sz in ((-0.75, "5AB4FF", 0.8), (0.75, "FF8C3C", 0.8), (0, "5AE650", 1.0)):
        y = -0.3 if x == 0 else 0.2
        pieces.append(box("FFD23C", loc=(x, y, 0.9 * sz), size=(0.7 * sz, 0.7 * sz, 0.7 * sz), bevel=0.12 * sz))
        pieces.append(box(col, loc=(x, y, 0.0), size=(1.0 * sz, 0.6 * sz, 0.95 * sz), bevel=0.15 * sz))
        pieces += [sphere(DARKC, loc=(x + s * 0.13 * sz, y - 0.36 * sz, 0.95 * sz), scale=0.06 * sz) for s in (-1, 1)]
    a.part("Body", pieces)
    return a, {"yaw": -8, "pitch": 10}


def ic_event():
    a = new("Event")
    t = box("B45AFF", loc=(0, 0, 0), size=(2.4, 0.3, 1.4), bevel=0.15)
    holes = [cyl("7A2ACD", loc=(x, 0, 0), r=0.22, h=0.34, rot=(90, 0, 0), verts=14) for x in (-1.2, 1.2)]
    star = star_mesh("FFD23C", r1=0.5, r2=0.22, depth=0.2)
    star.location = (0, -0.2, 0)
    dots = [box("FFFFFF", loc=(0.75, -0.17, z), size=(0.06, 0.04, 0.16)) for z in (-0.45, -0.15, 0.15, 0.45)]
    a.part("Body", [t, star] + holes + dots)
    return a, {"yaw": -10, "pitch": 8}


DARKC = "1B1530"
for _t in props.TOOLS:
    ICONS[f"Tool_{_t}"] = tool_icon(_t)
for _c in props.VEHICLES:
    ICONS[f"Car_{_c}"] = car_icon(_c)
ICONS.update({
    "Potion": potion("Potion", "B45AFF", lambda: []),
    "PotionLuck": potion("PotionLuck", "5AE650", sym_clover),
    "PotionCash": potion("PotionCash", "FFC83C", sym_coin),
    "PotionSpeed": potion("PotionSpeed", "5AB4FF", sym_bolt),
    "PotionHatch": potion("PotionHatch", "FF7AB4", sym_egg),
    "Daily": ic_daily, "Group": ic_group, "Event": ic_event,
})


def main(filters):
    for name, fn in ICONS.items():
        if filters and not any(name.startswith(f) for f in filters):
            continue
        a, opts = fn()
        objs = finish(a)
        render(name, objs, **opts)
        print("icon", name)


if __name__ == "__main__":
    main(sys.argv[1:])
