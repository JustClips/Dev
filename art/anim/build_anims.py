"""Generate the pet and player animations as KeyframeSequence .rbxmx files.

Pets: every alien is rigged at runtime as RootPart -> Body -> limbs (see AlienRig.luau),
with joint frames aligned to the model (X right, Y up, front = -Z). So rotations here are
in model axes:
  about X: swing a limb forward/back (+ = toward the front)
  about Y: wag / turn
  about Z: flap sideways (+ tips a limb toward the alien's left, -X)

Usage: python3 build_anims.py  -> writes art/out/anims/*.rbxmx
"""
import math
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", "anims")

PET_TREE = {
    "RootPart": {
        "Body": {
            "Head": {"EarL": {}, "EarR": {}},
            "EarL": {}, "EarR": {},
            "LegFL": {}, "LegFR": {}, "LegBL": {}, "LegBR": {},
            "LegL": {}, "LegR": {}, "ArmL": {}, "ArmR": {},
            "Tail": {}, "WingL": {}, "WingR": {},
            "Tent1": {}, "Tent2": {}, "Tent3": {}, "Tent4": {},
        }
    }
}

R15_TREE = {
    "HumanoidRootPart": {
        "LowerTorso": {
            "UpperTorso": {
                "Head": {},
                "RightUpperArm": {"RightLowerArm": {"RightHand": {}}},
                "LeftUpperArm": {"LeftLowerArm": {"LeftHand": {}}},
            },
        }
    }
}


def mat(rx, ry, rz):
    """CFrame.Angles(rx, ry, rz) rotation matrix (R = Rx * Ry * Rz)."""
    cx, sx = math.cos(rx), math.sin(rx)
    cy, sy = math.cos(ry), math.sin(ry)
    cz, sz = math.cos(rz), math.sin(rz)
    Rx = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    Ry = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    Rz = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]

    def mm(a, b):
        return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
    return mm(mm(Rx, Ry), Rz)


def cframe_xml(pos, rot):
    m = mat(*rot)
    vals = {"X": pos[0], "Y": pos[1], "Z": pos[2]}
    for i in range(3):
        for j in range(3):
            vals[f"R{i}{j}"] = m[i][j]
    inner = "".join(f"<{k}>{v:.5f}</{k}>" for k, v in vals.items())
    return f'<CoordinateFrame name="CFrame">{inner}</CoordinateFrame>'


class Ref:
    n = 0

    @classmethod
    def next(cls):
        cls.n += 1
        return f"RBX{cls.n}"


def pose_xml(name, tree, poses):
    pos, rot = poses.get(name, ((0, 0, 0), (0, 0, 0)))
    kids = "".join(pose_xml(k, sub, poses) for k, sub in tree.items())
    return (f'<Item class="Pose" referent="{Ref.next()}"><Properties>'
            f'<string name="Name">{name}</string>{cframe_xml(pos, rot)}'
            f'<token name="EasingDirection">0</token><token name="EasingStyle">0</token>'
            f'<float name="Weight">1</float></Properties>{kids}</Item>')


def sequence(name, frames, loop, priority, tree):
    """frames: list of (time, {joint: ((x,y,z),(rx,ry,rz))})."""
    Ref.n = 0
    kfs = []
    for t, poses in frames:
        root, sub = next(iter(tree.items()))
        kfs.append(f'<Item class="Keyframe" referent="{Ref.next()}"><Properties>'
                   f'<string name="Name">Keyframe</string><float name="Time">{t:.4f}</float></Properties>'
                   f'{pose_xml(root, sub, poses)}</Item>')
    return ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" version="4">'
            f'<Item class="KeyframeSequence" referent="RBX0"><Properties>'
            f'<string name="Name">{name}</string><bool name="Loop">{"true" if loop else "false"}</bool>'
            f'<token name="Priority">{priority}</token></Properties>{"".join(kfs)}</Item></roblox>')


D = math.radians


def sample(duration, steps, fn):
    return [(duration * i / steps, fn(2 * math.pi * i / steps, duration * i / steps)) for i in range(steps + 1)]


def pet_idle(w, t):
    s = math.sin
    ears = D(9) * s(w + 0.6)
    return {
        "Body": ((0, 0.06 * (1 - math.cos(w)) / 2, 0), (0, 0, D(1.5) * s(w))),
        "Head": ((0, 0, 0), (D(3) * s(w + 1), 0, D(5) * s(w * 0.5))),
        "EarL": ((0, 0, 0), (0, 0, ears)),
        "EarR": ((0, 0, 0), (0, 0, -ears)),
        "Tail": ((0, 0, 0), (0, D(18) * s(w * 2), 0)),
        "WingL": ((0, 0, 0), (0, 0, -D(10) * s(w * 2))),
        "WingR": ((0, 0, 0), (0, 0, D(10) * s(w * 2))),
        "ArmL": ((0, 0, 0), (D(6) * s(w), 0, D(4))),
        "ArmR": ((0, 0, 0), (-D(6) * s(w), 0, -D(4))),
        **{f"Tent{i}": ((0, 0, 0), (D(10) * s(w + i * 1.3), 0, D(8) * s(w + i))) for i in range(1, 5)},
    }


def pet_walk(w, t):
    s, c = math.sin, math.cos
    leg = D(32) * s(w)
    return {
        "Body": ((0, 0.14 * abs(s(w)), 0), (D(3) * s(2 * w), 0, D(4) * s(w))),
        "Head": ((0, 0, 0), (D(5) * s(2 * w + 0.5), 0, -D(3) * s(w))),
        "LegFL": ((0, 0, 0), (leg, 0, 0)), "LegBR": ((0, 0, 0), (leg, 0, 0)),
        "LegFR": ((0, 0, 0), (-leg, 0, 0)), "LegBL": ((0, 0, 0), (-leg, 0, 0)),
        "LegL": ((0, 0, 0), (leg, 0, 0)), "LegR": ((0, 0, 0), (-leg, 0, 0)),
        "ArmL": ((0, 0, 0), (-D(28) * s(w), 0, D(6))), "ArmR": ((0, 0, 0), (D(28) * s(w), 0, -D(6))),
        "EarL": ((0, 0, 0), (D(6) * c(2 * w), 0, D(12) * s(2 * w))),
        "EarR": ((0, 0, 0), (D(6) * c(2 * w), 0, -D(12) * s(2 * w))),
        "Tail": ((0, 0, 0), (0, D(25) * s(w), 0)),
        "WingL": ((0, 0, 0), (0, 0, -D(28) * s(2 * w))),
        "WingR": ((0, 0, 0), (0, 0, D(28) * s(2 * w))),
        **{f"Tent{i}": ((0, 0, 0), (D(22) * s(w + i * 1.57), 0, 0)) for i in range(1, 5)},
    }


def pet_happy():
    frames = []
    steps = 12
    for i in range(steps + 1):
        u = i / steps
        t = 1.0 * u
        jump = 4 * u * (1 - u)  # parabola 0..1..0
        spin = D(360) * min(1, u * 1.15)
        arms = D(150) * math.sin(math.pi * u)
        frames.append((t, {
            "Body": ((0, 1.3 * jump, 0), (0, spin, 0)),
            "Head": ((0, 0, 0), (-D(12) * jump, 0, 0)),
            "ArmL": ((0, 0, 0), (arms, 0, D(20) * jump)), "ArmR": ((0, 0, 0), (arms, 0, -D(20) * jump)),
            "EarL": ((0, 0, 0), (0, 0, D(25) * jump)), "EarR": ((0, 0, 0), (0, 0, -D(25) * jump)),
            "LegL": ((0, 0, 0), (D(25) * jump, 0, 0)), "LegR": ((0, 0, 0), (D(25) * jump, 0, 0)),
            "LegFL": ((0, 0, 0), (D(30) * jump, 0, 0)), "LegFR": ((0, 0, 0), (D(30) * jump, 0, 0)),
            "LegBL": ((0, 0, 0), (-D(30) * jump, 0, 0)), "LegBR": ((0, 0, 0), (-D(30) * jump, 0, 0)),
            "Tail": ((0, 0, 0), (0, D(35) * math.sin(u * 4 * math.pi), 0)),
            "WingL": ((0, 0, 0), (0, 0, -D(40) * math.sin(u * 4 * math.pi))),
            "WingR": ((0, 0, 0), (0, 0, D(40) * math.sin(u * 4 * math.pi))),
        }))
    return frames


def player_sweep(w, t):
    s = math.sin
    return {
        "UpperTorso": ((0, 0, 0), (D(8), D(22) * s(w), 0)),
        "RightUpperArm": ((0, 0, 0), (D(62), 0, D(10) * s(w))),
        "RightLowerArm": ((0, 0, 0), (D(15), 0, 0)),
        "LeftUpperArm": ((0, 0, 0), (D(55), 0, -D(25))),
        "LeftLowerArm": ((0, 0, 0), (D(25), 0, 0)),
        "Head": ((0, 0, 0), (-D(6), -D(10) * s(w), 0)),
    }


def main():
    os.makedirs(OUT, exist_ok=True)
    clips = {
        "Pet_Idle": sequence("Pet_Idle", sample(2.4, 12, pet_idle), True, 0, PET_TREE),
        "Pet_Walk": sequence("Pet_Walk", sample(0.56, 8, pet_walk), True, 1, PET_TREE),
        "Pet_Happy": sequence("Pet_Happy", pet_happy(), False, 2, PET_TREE),
        "Player_Sweep": sequence("Player_Sweep", sample(0.7, 8, player_sweep), True, 2, R15_TREE),
    }
    for name, xml in clips.items():
        with open(os.path.join(OUT, f"{name}.rbxmx"), "w") as f:
            f.write(xml)
        print("wrote", name, len(xml), "bytes")


if __name__ == "__main__":
    main()
