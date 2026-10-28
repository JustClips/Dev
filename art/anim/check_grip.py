"""Prints ToolService's grip constants for the player pose in build_anims.py, and checks it.

The right hand holds the tool HAND_GAP studs below the top grip point; the left hand should
land on that top point. Tools are scaled so the right hand to the head is REACH studs, and
the grip is rotated so the head rests just above the ground in the hold pose.
Usage: python3 art/anim/check_grip.py
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_anims  # noqa: E402
import r15  # noqa: E402

REACH = 3.3
HAND_GAP = 1.2
HOVER = 0.25  # head this far above the ground
AIM = math.radians(-4)  # head slightly inward of straight ahead


def frames(twist):
    return r15.solve(build_anims.player_pose(twist))


def grip_rotation(f):
    F = f["RightGrip"]
    g = F[:3, 3]
    dy = r15.GROUND + HOVER - g[1]
    horiz = math.sqrt(max(REACH * REACH - dy * dy, 0.01))
    target = np.array([g[0] + horiz * math.sin(AIM), r15.GROUND + HOVER, g[2] - horiz * math.cos(AIM)])
    d = (target - g) / np.linalg.norm(target - g)
    x = np.cross(d, [0, 1, 0])
    x /= np.linalg.norm(x)
    y = np.cross(-d, x)
    return F[:3, :3].T @ np.column_stack([x, y, -d])  # tool model axes in the grip attachment frame


def main():
    f = frames(build_anims.PLAYER_TWIST)
    M = grip_rotation(f)
    for twist in (build_anims.PLAYER_TWIST - build_anims.SWEEP_SWING, build_anims.PLAYER_TWIST,
                  build_anims.PLAYER_TWIST + build_anims.SWEEP_SWING):
        f2 = frames(twist)
        F = f2["RightGrip"]
        head = F[:3, 3] + F[:3, :3] @ M @ np.array([0, 0, -REACH])
        top = F[:3, 3] + F[:3, :3] @ M @ np.array([0, 0, HAND_GAP])
        left = np.linalg.norm(f2["LeftGrip"][:3, 3] - top)
        print(f"twist {twist:+4d}: head {head.round(2)} (ground {r15.GROUND}), left hand off the handle by {left:.2f}")
    cols = [M[:, 0], M[:, 1], M[:, 2]]
    fmt = lambda v: "Vector3.new({:.4f}, {:.4f}, {:.4f})".format(*v)  # noqa: E731
    print("\n-- ToolService constants")
    print(f"local TOOL_REACH = {REACH}\nlocal HAND_GAP = {HAND_GAP}")
    print(f"local GRIP_ROTATION = CFrame.fromMatrix(Vector3.zero, {fmt(cols[0])}, {fmt(cols[1])}, {fmt(cols[2])}):Inverse()")


if __name__ == "__main__":
    main()
