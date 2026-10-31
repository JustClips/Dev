"""Forward kinematics for the default R15 rig, so tool grips and player animations can be
checked offline: where does the broom head end up in each animation frame?

Joint offsets come from a real Roblox server (Players:CreateHumanoidModelFromDescription
with a blank HumanoidDescription, dumped through Luau Execution on 2026-10-28).
Frames are 4x4 numpy matrices in HumanoidRootPart space (Y up, front = -Z).
The ground is GROUND studs below the HumanoidRootPart centre (HipHeight 2.19 + half of 2).
"""
import math

import numpy as np

GROUND = -3.19

# Part1 -> (Part0, C0 position in Part0, C1 position in Part1). All rig attachments have
# identity rotation on the default rig.
JOINTS = {
    "LowerTorso": ("HumanoidRootPart", (0, -1.0, 0), (0, -0.2, 0)),
    "UpperTorso": ("LowerTorso", (0, 0.2, 0), (0, -0.849, 0)),
    "Head": ("UpperTorso", (0, 0.849, 0), (0, -0.576, 0)),
    "RightUpperArm": ("UpperTorso", (0.972, 0.598, 0), (-0.501, 0.419, 0)),
    "RightLowerArm": ("RightUpperArm", (0, -0.355, 0), (0, 0.275, 0)),
    "RightHand": ("RightLowerArm", (0, -0.532, 0), (0, 0.132, 0)),
    "LeftUpperArm": ("UpperTorso", (-0.972, 0.598, 0), (0.501, 0.419, 0)),
    "LeftLowerArm": ("LeftUpperArm", (0, -0.355, 0), (0, 0.275, 0)),
    "LeftHand": ("LeftLowerArm", (0, -0.532, 0), (0, 0.132, 0)),
    # legs (rig attachments dumped through Luau Execution on 2026-10-31)
    "RightUpperLeg": ("LowerTorso", (0.5, -0.2, 0), (0, 0.471, 0)),
    "RightLowerLeg": ("RightUpperLeg", (0, -0.449, 0), (0, 0.413, 0)),
    "RightFoot": ("RightLowerLeg", (0, -0.596, 0), (0, 0.106, 0)),
    "LeftUpperLeg": ("LowerTorso", (-0.5, -0.2, 0), (0, 0.471, 0)),
    "LeftLowerLeg": ("LeftUpperLeg", (0, -0.449, 0), (0, 0.413, 0)),
    "LeftFoot": ("LeftLowerLeg", (0, -0.596, 0), (0, 0.106, 0)),
}
ORDER = ["LowerTorso", "UpperTorso", "Head", "RightUpperArm", "RightLowerArm", "RightHand",
         "LeftUpperArm", "LeftLowerArm", "LeftHand",
         "RightUpperLeg", "RightLowerLeg", "RightFoot", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot"]
# Ankle joint height above the ground with straight legs (foot centre 0.106 below the ankle,
# half a foot 0.156 below that).
ANKLE_UP = 0.262


def T(x, y, z):
    m = np.eye(4)
    m[:3, 3] = (x, y, z)
    return m


def R(m3):
    m = np.eye(4)
    m[:3, :3] = m3
    return m


def angles(rx, ry, rz):
    """Roblox CFrame.Angles(rx, ry, rz) = Rx * Ry * Rz."""
    cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return Rx @ Ry @ Rz


def pose_matrix(pose):
    """A pose is ((x,y,z), rot) where rot is (rx,ry,rz) angles or a 3x3 matrix."""
    pos, rot = pose
    rot = np.asarray(rot, dtype=float)
    m3 = rot if rot.shape == (3, 3) else angles(*rot)
    return T(*pos) @ R(m3)


def solve(poses):
    """World (HRP-space) frames of every part for a dict of joint poses."""
    frames = {"HumanoidRootPart": np.eye(4)}
    for name in ORDER:
        parent, c0, c1 = JOINTS[name]
        tr = pose_matrix(poses.get(name, ((0, 0, 0), (0, 0, 0))))
        frames[name] = frames[parent] @ T(*c0) @ tr @ np.linalg.inv(T(*c1))
    # Tool grips (RightGripAttachment / LeftGripAttachment): 0.158 below the hand, Rx(-90).
    grip = T(0, -0.158, 0) @ R(angles(-math.pi / 2, 0, 0))
    frames["RightGrip"] = frames["RightHand"] @ grip
    frames["LeftGrip"] = frames["LeftHand"] @ grip
    return frames
