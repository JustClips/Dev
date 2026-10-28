"""Shared Blender helpers for Sweep the Moon assets.

Conventions (checked against Roblox's GLB importer):
- 1 Blender metre = 1 Roblox stud.
- Build facing -Y with +Z up. Roblox maps Blender (x, y, z) to (-x, z, y), so -Y becomes
  Roblox's forward (-Z) and +Z becomes up.
- Each asset's origin is its ground pivot (feet / base centre).
- Colours come from a small palette texture embedded in the GLB, because Roblox ignores
  plain material colours. Each piece's UVs point at the centre of its swatch.
- An asset is a list of named parts. A part may have a parent part and a joint point
  (used for Motor6D rigs). Parts named *_Glow become Neon in game.
"""
import bpy
import bmesh
import math
import json
import os
from mathutils import Vector, Matrix, Euler

CELL = 4          # pixels per swatch
GRID = 8          # swatches per row -> 64 colours max per asset


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def to_roblox(v):
    """Blender position -> Roblox position."""
    return [round(-v[0], 4), round(v[2], 4), round(v[1], 4)]


class Asset:
    def __init__(self, name, kind="static"):
        self.name = name
        self.kind = kind
        self.colors = []      # hex strings, index = swatch
        self.parts = {}       # name -> dict(obj, parent, joint)
        self.extra = {}
        reset_scene()

    # ---------- palette ----------
    def swatch(self, hexcol):
        hexcol = hexcol.upper().lstrip("#")
        if hexcol not in self.colors:
            if len(self.colors) >= GRID * GRID:
                raise RuntimeError(f"{self.name}: too many colours")
            self.colors.append(hexcol)
        i = self.colors.index(hexcol)
        u = ((i % GRID) + 0.5) / GRID
        v = 1 - ((i // GRID) + 0.5) / GRID
        return u, v

    def paint(self, obj, hexcol):
        u, v = self.swatch(hexcol)
        me = obj.data
        if not me.uv_layers:
            me.uv_layers.new(name="UVMap")
        uv = me.uv_layers.active.data
        for loop in uv:
            loop.uv = (u, v)

    # ---------- parts ----------
    def part(self, name, pieces, parent=None, joint=None, glow=None, material=None, collide=False):
        """Join pieces into one mesh object called `name`."""
        obj = join(pieces, name)
        if obj is None:
            return None
        self.parts[name] = {
            "obj": obj,
            "parent": parent,
            "joint": list(joint) if joint is not None else None,
            "glow": glow,
            "material": material,
            "collide": collide,
        }
        return obj

    def export(self, out_dir):
        os.makedirs(out_dir, exist_ok=True)
        img = build_palette_image(self.name, self.colors)
        mat = palette_material(self.name, img)
        # parent objects in Blender (keeps world transforms) so the hierarchy is visible to Dev
        for name, p in self.parts.items():
            o = p["obj"]
            o.data.materials.clear()
            o.data.materials.append(mat)
        for name, p in self.parts.items():
            if p["parent"]:
                o = p["obj"]
                mw = o.matrix_world.copy()
                o.parent = self.parts[p["parent"]]["obj"]
                o.matrix_world = mw
        path = os.path.join(out_dir, f"{self.name}.glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=False,
                                  export_apply=True, export_yup=True, export_texcoords=True,
                                  export_normals=True, export_materials="EXPORT",
                                  export_image_format="AUTO", export_animations=False)
        meta = {"name": self.name, "kind": self.kind, "parts": {}, **self.extra}
        lo = Vector((1e9, 1e9, 1e9))
        hi = Vector((-1e9, -1e9, -1e9))
        tris = 0
        for name, p in self.parts.items():
            o = p["obj"]
            for v in o.data.vertices:
                w = o.matrix_world @ v.co
                lo = Vector(map(min, lo, w))
                hi = Vector(map(max, hi, w))
            tris += sum(len(poly.vertices) - 2 for poly in o.data.polygons)
            meta["parts"][name] = {
                "parent": p["parent"],
                "joint": to_roblox(p["joint"]) if p["joint"] else None,
                "glow": p["glow"],
                "material": p["material"],
                "collide": p["collide"],
            }
        # Roblox-space bounds: x flips, y<->z swap
        meta["bounds"] = {"min": [round(-hi.x, 3), round(lo.z, 3), round(lo.y, 3)],
                          "max": [round(-lo.x, 3), round(hi.z, 3), round(hi.y, 3)]}
        meta["tris"] = tris
        return path, meta


def reset_scene():
    if bpy.app.background:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        return
    # In Blender's window a factory reset breaks the running script's context,
    # so clear the scene's data instead.
    for coll in (bpy.data.objects, bpy.data.meshes, bpy.data.materials, bpy.data.images,
                 bpy.data.cameras, bpy.data.lights):
        for block in list(coll):
            coll.remove(block)


def build_palette_image(name, colors):
    size = CELL * GRID
    img = bpy.data.images.new(f"{name}_pal", size, size, alpha=False)
    px = [0.0] * (size * size * 4)
    for i, h in enumerate(colors):
        r, g, b = hex_rgb(h)
        cx, cy = (i % GRID) * CELL, (GRID - 1 - i // GRID) * CELL
        for y in range(cy, cy + CELL):
            for x in range(cx, cx + CELL):
                k = (y * size + x) * 4
                px[k:k + 4] = [r, g, b, 1.0]
    img.pixels = px
    img.pack()
    return img


def palette_material(name, img):
    m = bpy.data.materials.new(f"{name}_mat")
    m.use_nodes = True
    nodes = m.node_tree.nodes
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.6
    t = nodes.new("ShaderNodeTexImage")
    t.image = img
    t.interpolation = "Closest"
    m.node_tree.links.new(t.outputs[0], bsdf.inputs["Base Color"])
    return m


# ---------------------------------------------------------------- primitives
_asset = None


def use(asset):
    global _asset
    _asset = asset


def _finish(obj, color, smooth=True, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    obj.location = loc
    obj.rotation_euler = Euler([math.radians(a) for a in rot], "XYZ")
    obj.scale = scale if not isinstance(scale, (int, float)) else (scale, scale, scale)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for poly in obj.data.polygons:
        poly.use_smooth = smooth
    _asset.paint(obj, color)
    return obj


def sphere(color, loc=(0, 0, 0), scale=1, rot=(0, 0, 0), seg=20, rings=12, smooth=True):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=1)
    return _finish(bpy.context.view_layer.objects.active, color, smooth, loc, rot, scale)


def ico(color, loc=(0, 0, 0), scale=1, rot=(0, 0, 0), sub=1, smooth=False):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub, radius=1)
    return _finish(bpy.context.view_layer.objects.active, color, smooth, loc, rot, scale)


def box(color, loc=(0, 0, 0), size=(1, 1, 1), rot=(0, 0, 0), bevel=0.0, smooth=False):
    bpy.ops.mesh.primitive_cube_add(size=1)
    o = bpy.context.view_layer.objects.active
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel > 0:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=2, affect="EDGES", profile=0.5)
        bm.to_mesh(o.data)
        bm.free()
    o2 = _finish(o, color, False, loc, rot, 1)
    if bevel > 0:
        for poly in o2.data.polygons:
            poly.use_smooth = smooth
    return o2


def cyl(color, loc=(0, 0, 0), r=1, h=1, rot=(0, 0, 0), verts=16, r2=None, smooth=True, cap=True):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=h,
                                            end_fill_type="NGON" if cap else "NOTHING")
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r2, depth=h,
                                        end_fill_type="NGON" if cap else "NOTHING")
    o = bpy.context.view_layer.objects.active
    o2 = _finish(o, color, smooth, loc, rot, 1)
    if smooth:
        # keep the caps flat-looking: mark cap faces flat
        for poly in o2.data.polygons:
            if len(poly.vertices) > 4:
                poly.use_smooth = False
    return o2


def cone(color, loc=(0, 0, 0), r=1, h=1, rot=(0, 0, 0), verts=16, smooth=True):
    return cyl(color, loc, r, h, rot, verts, r2=0.0, smooth=smooth)


def torus(color, loc=(0, 0, 0), R=1, r=0.25, rot=(0, 0, 0), seg=24, mseg=8):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=seg, minor_segments=mseg)
    return _finish(bpy.context.view_layer.objects.active, color, True, loc, rot, 1)


def capsule(color, a, b, r, seg=12):
    """Capsule between points a and b (Blender coords)."""
    a, b = Vector(a), Vector(b)
    d = b - a
    length = d.length
    mid = (a + b) / 2
    bpy.ops.mesh.primitive_cylinder_add(vertices=seg, radius=r, depth=max(length, 0.001), end_fill_type="NOTHING")
    c = bpy.context.view_layer.objects.active
    s1 = sphere(color, loc=a, scale=r, seg=seg, rings=8)
    s2 = sphere(color, loc=b, scale=r, seg=seg, rings=8)
    rot = d.to_track_quat("Z", "Y").to_euler()
    c.location = mid
    c.rotation_euler = rot
    bpy.ops.object.select_all(action="DESELECT")
    c.select_set(True)
    bpy.context.view_layer.objects.active = c
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for poly in c.data.polygons:
        poly.use_smooth = True
    _asset.paint(c, color)
    return join([c, s1, s2], "capsule")


def tube(color, points, r, seg=10):
    """Chain of capsules through points."""
    pieces = []
    for i in range(len(points) - 1):
        pieces.append(capsule(color, points[i], points[i + 1], r if not callable(r) else r(i), seg))
    return join(pieces, "tube")


def eye(loc, size, look=(0, -1, 0), white="FFFFFF", pupil="1B1530", shine=True, iris=None):
    """Big sparkly cartoon eye at loc (Blender coords) facing `look`: a white, a coloured
    iris, a dark pupil and two shine dots (big top-right, small bottom-left)."""
    look = Vector(look).normalized()
    p = Vector(loc)
    flat = (size * 0.78, size * 0.5, size * 0.88)
    pieces = [sphere(white, loc=p, scale=(size, size * 0.9, size * 1.08), seg=20, rings=12)]
    if iris:
        pieces.append(sphere(iris, loc=p + look * size * 0.5, scale=flat, seg=18, rings=10))
        pieces.append(sphere(pupil, loc=p + look * size * 0.62, scale=(flat[0] * 0.6, flat[1] * 0.8, flat[2] * 0.62), seg=14, rings=8))
    else:
        pieces.append(sphere(pupil, loc=p + look * size * 0.52, scale=flat, seg=18, rings=10))
    if shine:
        pieces.append(sphere(white, loc=p + look * size * 0.98 + Vector((0.28, 0, 0.32)) * size, scale=size * 0.24, seg=10, rings=6))
        pieces.append(sphere(white, loc=p + look * size * 0.98 + Vector((-0.22, 0, -0.28)) * size, scale=size * 0.11, seg=8, rings=5))
    return join(pieces, "eye")


def arc(color, loc, R, r, rot=(90, 0, 0), keep="below", seg=20):
    """Half a torus: a smile line (keep='below') or a frown/brow (keep='above')."""
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, major_segments=seg, minor_segments=6)
    o = bpy.context.view_layer.objects.active
    bm = bmesh.new()
    bm.from_mesh(o.data)
    cut = [v for v in bm.verts if (v.co.y > r * 0.3 if keep == "below" else v.co.y < -r * 0.3)]
    bmesh.ops.delete(bm, geom=cut, context="VERTS")
    bm.to_mesh(o.data)
    bm.free()
    # torus lies in XY; after rot=(90,0,0) its -Y half becomes the lower half (a smile)
    return _finish(o, color, True, loc, rot, 1)


def join(pieces, name):
    pieces = [p for p in pieces if p is not None]
    if not pieces:
        return None
    bpy.ops.object.select_all(action="DESELECT")
    for p in pieces:
        p.select_set(True)
    bpy.context.view_layer.objects.active = pieces[0]
    if len(pieces) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    o.data.name = name
    return o


def mirror_x(obj, name=None):
    """Duplicate an object mirrored across X (Blender X = creature side)."""
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.duplicate()
    d = bpy.context.view_layer.objects.active
    d.scale = (-1, 1, 1)
    bpy.ops.object.transform_apply(scale=True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    if name:
        d.name = name
        d.data.name = name
    return d


def copy(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.duplicate()
    return bpy.context.view_layer.objects.active


def deform(obj, fn):
    """Move every vertex with fn(Vector)->Vector (world coords, transforms already applied)."""
    for v in obj.data.vertices:
        v.co = fn(v.co.copy())
    obj.data.update()
    return obj


def noise_deform(obj, amount, seed=1, freq=1.0):
    import mathutils.noise as N
    def f(co):
        n = N.noise_vector(co * freq + Vector((seed * 13.1, seed * 7.7, seed * 3.3)))
        return co + n * amount
    return deform(obj, f)


def write_meta(meta_list, path):
    with open(path, "w") as f:
        json.dump(meta_list, f, indent=1)
