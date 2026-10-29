"""Used by tools/publish_place.py. Copy the repo's Rojo tree into OUT and rewrite LiveSync-style JSON values into forms
Rojo 7 understands (hex colours, Font dicts, gradients, CFrame with orientation in degrees)."""
import json, math, os, re, shutil, sys
REPO, OUT = sys.argv[1], sys.argv[2]
shutil.rmtree(OUT, ignore_errors=True)
shutil.copytree(os.path.join(REPO, "src"), os.path.join(OUT, "src"))
HEX = re.compile(r"^#[0-9A-Fa-f]{6}$")
COLOR_PROPS = {"Ambient", "OutdoorAmbient", "ColorShift_Top", "ColorShift_Bottom", "TintColor", "FogColor"}

def hexrgb(h):
    return [int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)]

def is_color_prop(k):
    return k.endswith("Color3") or k == "Color" or k in COLOR_PROPS or k.endswith("Color")

def cframe(d):
    x, y, z = d.get("position", [0, 0, 0])
    rx, ry, rz = [math.radians(a) for a in d.get("orientation", [0, 0, 0])]
    # Roblox orientation is applied Y, X, Z (CFrame.fromOrientation = fromEulerAnglesYXZ)
    def rot_x(a): return [[1, 0, 0], [0, math.cos(a), -math.sin(a)], [0, math.sin(a), math.cos(a)]]
    def rot_y(a): return [[math.cos(a), 0, math.sin(a)], [0, 1, 0], [-math.sin(a), 0, math.cos(a)]]
    def rot_z(a): return [[math.cos(a), -math.sin(a), 0], [math.sin(a), math.cos(a), 0], [0, 0, 1]]
    def mul(a, b): return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    m = mul(mul(rot_y(ry), rot_x(rx)), rot_z(rz))
    return {"CFrame": {"position": [x, y, z], "orientation": m}}

PART_CLASSES = {"Part", "WedgePart", "CornerWedgePart", "TrussPart", "MeshPart", "SpawnLocation", "Seat", "VehicleSeat", "UnionOperation"}
UDIM2 = {"Position", "Size", "CanvasSize", "CellPadding", "CellSize", "TileSize"}
UDIM = {"CornerRadius", "Padding", "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight"}

def nums(v, n):
    return isinstance(v, list) and len(v) == n and all(isinstance(x, (int, float)) for x in v)

def conv(k, v, cls=None):
    if is_color_prop(k) and (isinstance(v, str) and HEX.match(v) or nums(v, 3)):
        rgb = hexrgb(v) if isinstance(v, str) else ([n / 255 for n in v] if max(v) > 1 else v)
        if k == "Color" and cls in PART_CLASSES:
            return {"Color3uint8": [round(c * 255) for c in rgb]}
        return {"Color3": rgb}
    if k in UDIM2 and isinstance(v, list) and len(v) == 2 and all(nums(x, 2) for x in v):
        return {"UDim2": [[x[0], round(x[1])] for x in v]}
    if k in UDIM and nums(v, 2):
        return {"UDim": [v[0], round(v[1])]}
    if k == "AnchorPoint" and nums(v, 2):
        return {"Vector2": v}
    if nums(v, 3) and k in ("Size", "LightDirection", "Velocity", "Offset"):
        return {"Vector3": v}
    if isinstance(v, dict):
        if k == "CFrame" and ("position" in v or "orientation" in v):
            return cframe(v)
        if k == "FontFace" and "family" in v:
            return {"Font": {"family": v["family"], "weight": v.get("weight", "Regular"), "style": v.get("style", "Normal")}}
        if "keypoints" in v:
            kps = v["keypoints"]
            if kps and isinstance(kps[0], list) and isinstance(kps[0][1], (int, float)):
                return {"NumberSequence": {"keypoints": [{"time": t, "value": val, "envelope": 0} for t, val in kps]}}
            out = []
            for t, c in kps:
                out.append({"time": t, "color": hexrgb(c) if isinstance(c, str) else c})
            return {"ColorSequence": {"keypoints": out}}
    return v

def fix_node(n):
    if "properties" in n:
        n["properties"] = {k: conv(k, v, n.get("className")) for k, v in n["properties"].items()}
    for c in n.get("children", []):
        fix_node(c)

for root, _, files in os.walk(os.path.join(OUT, "src")):
    for f in files:
        if f.endswith(".model.json") or f.endswith(".meta.json"):
            p = os.path.join(root, f)
            d = json.load(open(p))
            fix_node(d)
            json.dump(d, open(p, "w"), indent=1)

proj = json.load(open(os.path.join(REPO, "default.project.json")))
def fix_proj(n):
    if isinstance(n, dict):
        if "$properties" in n:
            n["$properties"] = {k: conv(k, v) for k, v in n["$properties"].items()}
        for k, v in n.items():
            if not k.startswith("$"):
                fix_proj(v)
fix_proj(proj["tree"])
json.dump(proj, open(os.path.join(OUT, "default.project.json"), "w"), indent=1)
print("ok")
