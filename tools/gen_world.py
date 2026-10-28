"""Writes src/workspace/Moon/*.model.json: the gameplay parts of the map.

Only gameplay parts live here (base pads, spawns, the sell pad, gates, invisible walls).
Terrain and all the Blender props are built at runtime by WorldService from
src/shared/Config/World.luau, so keep the numbers below in sync with that file.

  python3 tools/gen_world.py
"""
import json
import math
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "src", "workspace", "Moon")

FIELD_MIN, FIELD_MAX = (-56, -196), (56, 196)
BASE_INNER, BASE_W, BASE_D = 62, 92, 88
FLOOR_Y = 1  # bases sit on a 1-stud platform (World.BaseFloorY)
HUB_X = BASE_INNER + BASE_D + 2   # 152
HUB_Z = 200
CORRIDOR_HALF = 12
ZONES = [  # id, min, max, groundY
    ("Crater", (-120, -452), (120, -232), -8),
    ("DarkSide", (-120, -704), (120, -488), 0),
    ("Mars", (-120, -956), (120, -740), 0),
]
CORRIDORS = [  # zone, zmin, zmax, gateZ, gate ground y
    ("Crater", -232, -196, -205, 0),
    ("DarkSide", -488, -452, -479, 0),
    ("Mars", -740, -704, -713, 0),
]
GATE_COLORS = {"Crater": "#78C8FF", "DarkSide": "#B478FF", "Mars": "#FF8C5A"}
BASE_LOCAL = {
    "Hatchery": (0, -28), "HatcheryRadius": 9, "Spawn": (-18, -31),
    "ParkMin": (-42, -14), "ParkMax": (42, 42),
}


def base_frame(i):
    side = -1 if i <= 4 else 1
    row = (i - 1) % 4
    z = -147 + row * 98
    x = side * (BASE_INNER + BASE_D / 2)
    # look at the field (x = 0): local -Z points toward -side*X
    return x, z, side


def to_world(i, lx, lz):
    x, z, side = base_frame(i)
    # CFrame.lookAt toward the field: look = (-side, 0, 0), right = (0, 0, -side)
    wx = x + (-side) * (-lz)
    wz = z - side * lx
    return wx, wz


def base_yaw(i):
    """Orientation Y (degrees) for parts in base i, matching CFrame.lookAt toward the field."""
    _, _, side = base_frame(i)
    return 90 if side == 1 else -90


def part(name, size, pos, color="#FFFFFF", material="SmoothPlastic", orient=None, cls="Part", children=None, **extra):
    props = {"Anchored": True, "Size": size, "Color": color, "Material": material,
             "TopSurface": "Smooth", "BottomSurface": "Smooth",
             "CFrame": {"position": pos, "orientation": orient or [0, 0, 0]}}
    props.update(extra)
    n = {"name": name, "className": cls, "properties": props}
    if children:
        n["children"] = children
    return n


def invisible(**extra):
    d = dict(Transparency=1, CanCollide=False, CanQuery=False, CanTouch=False, CastShadow=False)
    d.update(extra)
    return d


def model(children, **props):
    n = {"className": "Model", "children": children}
    if props:
        n["properties"] = props
    return n


def write(name, tree):
    with open(os.path.join(OUT, name + ".model.json"), "w") as f:
        json.dump(tree, f, indent=1, ensure_ascii=False)
        f.write("\n")


def wall(name, x0, z0, x1, z1, y0=-10, h=70):
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    sx, sz = max(abs(x1 - x0), 2), max(abs(z1 - z0), 2)
    return part(name, [sx, h, sz], [cx, y0 + h / 2, cz], "#000000", **invisible(CanCollide=True))


def main():
    os.makedirs(OUT, exist_ok=True)
    for old in ("Ground", "Decor"):
        p = os.path.join(OUT, old + ".model.json")
        if os.path.exists(p):
            os.remove(p)

    # ---------------- Rocket + sell pad ----------------
    write("Rocket", model([
        # The sell zone itself is a distance check (BackpackService); this marks the spot
        # and lights it. The visible pad and signs are built by MapBuilder.
        part("SellPad", [0.2, 30, 30], [0, 0.62, 0], "#3CFF9E", "Neon", orient=[0, 0, 90], Shape="Cylinder",
             **invisible(), children=[{"name": "Light", "className": "PointLight",
                                       "properties": {"Color": "#3CFF9E", "Range": 26, "Brightness": 1.2}}]),
    ]))

    # ---------------- Bases ----------------
    bases = []
    for i in range(1, 9):
        x, z, side = base_frame(i)
        yaw = base_yaw(i)
        hx, hz = to_world(i, *BASE_LOCAL["Hatchery"])
        sx, sz = to_world(i, *BASE_LOCAL["Spawn"])
        pmin, pmax = BASE_LOCAL["ParkMin"], BASE_LOCAL["ParkMax"]
        pcx, pcz = to_world(i, (pmin[0] + pmax[0]) / 2, (pmin[1] + pmax[1]) / 2)
        r = BASE_LOCAL["HatcheryRadius"]
        bases.append({"name": f"Base{i}", "className": "Model", "properties": {}, "attributes": {"BaseIndex": i}, "children": [
            part("Plot", [BASE_W, 1, BASE_D], [x, FLOOR_Y - 0.5, z], "#C4CAD6", orient=[0, yaw, 0], **invisible()),
            part("Pad", [5, r * 2, r * 2], [hx, FLOOR_Y + 2, hz], "#5AFFC8", orient=[0, 0, 90], Shape="Cylinder", **invisible()),
            part("Spawn", [4, 1, 4], [sx, FLOOR_Y + 0.5, sz], "#FFFFFF", orient=[0, yaw, 0], **invisible()),
            part("Park", [pmax[0] - pmin[0], 1, pmax[1] - pmin[1]], [pcx, FLOOR_Y + 0.5, pcz], "#58C4A0", orient=[0, yaw, 0], **invisible()),
        ]})
    write("Bases", {"className": "Folder", "children": bases})

    # ---------------- Gates ----------------
    gates = []
    for zone, zmin, zmax, gz, gy in CORRIDORS:
        # The sign on the barrier is built by ZoneService (name, price, lock).
        gates.append(part(f"Gate_{zone}", [CORRIDOR_HALF * 2 - 2, 14, 1], [0, gy + 7, gz], GATE_COLORS[zone], "ForceField",
                          Transparency=0.15, CastShadow=False))
    write("Gates", model(gates))

    # ---------------- Walls ----------------
    walls = [
        wall("HubWest", -HUB_X, -HUB_Z, -HUB_X, HUB_Z),
        wall("HubEast", HUB_X, -HUB_Z, HUB_X, HUB_Z),
        wall("HubSouth", -HUB_X, HUB_Z, HUB_X, HUB_Z),
        wall("HubNorthW", -HUB_X, -HUB_Z, -CORRIDOR_HALF, -HUB_Z),
        wall("HubNorthE", CORRIDOR_HALF, -HUB_Z, HUB_X, -HUB_Z),
    ]
    for zone, zmin, zmax, gz, gy in CORRIDORS:
        walls.append(wall(f"Corridor{zone}W", -CORRIDOR_HALF - 1, zmin, -CORRIDOR_HALF - 1, zmax, y0=-20))
        walls.append(wall(f"Corridor{zone}E", CORRIDOR_HALF + 1, zmin, CORRIDOR_HALF + 1, zmax, y0=-20))
    for k, (zone, mn, mx, gy) in enumerate(ZONES):
        y0 = gy - 10
        walls.append(wall(f"{zone}West", mn[0] - 1, mn[1], mn[0] - 1, mx[1], y0=y0))
        walls.append(wall(f"{zone}East", mx[0] + 1, mn[1], mx[0] + 1, mx[1], y0=y0))
        # south side (toward the hub) has the incoming corridor
        walls.append(wall(f"{zone}SouthW", mn[0], mx[1] + 1, -CORRIDOR_HALF, mx[1] + 1, y0=y0))
        walls.append(wall(f"{zone}SouthE", CORRIDOR_HALF, mx[1] + 1, mx[0], mx[1] + 1, y0=y0))
        if k < len(ZONES) - 1:
            walls.append(wall(f"{zone}NorthW", mn[0], mn[1] - 1, -CORRIDOR_HALF, mn[1] - 1, y0=y0))
            walls.append(wall(f"{zone}NorthE", CORRIDOR_HALF, mn[1] - 1, mx[0], mn[1] - 1, y0=y0))
        else:
            walls.append(wall(f"{zone}North", mn[0], mn[1] - 1, mx[0], mn[1] - 1, y0=y0))
    # safety floor far below, in case terrain hasn't loaded yet
    walls.append(part("SafetyFloor", [1200, 2, 1700], [0, -60, -380], "#000000", **invisible(CanCollide=True)))
    write("Walls", model(walls))
    print("world written to", OUT)


if __name__ == "__main__":
    main()
