"""World matrices (Blender space) of a blocky R15 body and the tool for every frame of a
tool's Use + Stance loop, read back from the generated .rbxmx files. Feeds the Blender
preview render (art/anim/preview_render.py).
Usage: python3 art/anim/preview_data.py Broom [Rake ...] > frames.json
"""
import json
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import r15  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
ANIMS = os.path.join(ROOT, "art", "out", "anims")
P = np.array([[-1, 0, 0], [0, 0, 1], [0, 1, 0]], float)  # Roblox <-> Blender axes
SIZES = {"HumanoidRootPart": None, "LowerTorso": (1.99, 0.4, 1.0), "UpperTorso": (1.94, 1.7, 1.0), "Head": (1.16, 1.18, 1.16),
         "RightUpperArm": (1.0, 1.24, 1.0), "RightLowerArm": (1.0, 1.12, 1.0), "RightHand": (0.98, 0.32, 1.03),
         "LeftUpperArm": (1.0, 1.24, 1.0), "LeftLowerArm": (1.0, 1.12, 1.0), "LeftHand": (0.98, 0.32, 1.03),
         "RightUpperLeg": (0.99, 1.36, 0.97), "RightLowerLeg": (0.99, 1.3, 0.97), "RightFoot": (1.0, 0.31, 1.0),
         "LeftUpperLeg": (0.99, 1.36, 0.97), "LeftLowerLeg": (0.99, 1.3, 0.97), "LeftFoot": (1.0, 0.31, 1.0)}


def read(name):
    text = open(os.path.join(ANIMS, name + ".rbxmx")).read()
    frames = []
    for kf in re.findall(r'<Item class="Keyframe".*?<float name="Time">([\d.]+)</float></Properties>(.*?)(?=<Item class="Keyframe"|</Item></roblox>)', text, re.S):
        t, body = kf
        poses = {}
        for name_, cf in re.findall(r'<string name="Name">(\w+)</string><CoordinateFrame name="CFrame">(.*?)</CoordinateFrame>', body):
            v = {k: float(x) for k, x in re.findall(r"<(\w+)>([-\d.e]+)</\1>", cf)}
            rot = [[v[f"R{i}{j}"] for j in range(3)] for i in range(3)]
            poses[name_] = ((v["X"], v["Y"], v["Z"]), np.array(rot))
        frames.append((float(t), poses))
    return frames


def grip_rotation(tid):
    text = open(os.path.join(ROOT, "src", "shared", "Config", "ToolGrips.luau")).read()
    m = re.search(tid + r" = CFrame\.fromMatrix\(Vector3\.zero, (.*)\),", text)
    cols = [list(map(float, c)) for c in re.findall(r"Vector3\.new\(([-\d.]+), ([-\d.]+), ([-\d.]+)\)", m.group(1))]
    return np.column_stack(cols)


def to_blender(rot, pos):
    out = np.eye(4)
    out[:3, :3] = P @ rot @ P
    out[:3, 3] = P @ pos
    return out.round(5).tolist()


def tool(tid):
    meta = json.load(open(os.path.join(ROOT, "art", "out", "meta.json")))[f"Tool_{tid}"]
    grip = np.array(meta["grip"], float)
    M = grip_rotation(tid)
    use, stance = read(f"Tool_{tid}_Use"), read(f"Tool_{tid}_Stance")
    out = []
    for i, (t, poses) in enumerate(use):
        p = dict(poses)
        p.update(stance[i % len(stance)][1])
        f = r15.solve(p)
        parts = {k: to_blender(f[k][:3, :3], f[k][:3, 3]) for k, s in SIZES.items() if s}
        F = f["RightGrip"]
        R = F[:3, :3] @ M
        # Blender vertex v -> Roblox model p = P v -> world = F_pos + R (p - grip)
        tw = np.eye(4)
        tw[:3, :3] = P @ R @ P
        tw[:3, 3] = P @ (F[:3, 3] - R @ grip)
        parts["Tool"] = tw.round(5).tolist()
        out.append(parts)
    return {"sizes": {k: [s[0], s[2], s[1]] for k, s in SIZES.items() if s}, "frames": out, "fps": len(use) / max(use[-1][0], 1e-3)}


if __name__ == "__main__":
    json.dump({tid: tool(tid) for tid in sys.argv[1:]}, sys.stdout)
