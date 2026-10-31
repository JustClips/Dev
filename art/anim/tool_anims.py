"""Per-tool player animations and the matching Tool.Grip rotations (remade 2026-10-31).

Every tool gets three loops:
  Tool_<Id>_Hold    upper body while the tool is out (Action). Breathing, a small sway.
  Tool_<Id>_Use     upper body while sweeping (Action2). The stroke of the tool's family.
  Tool_<Id>_Stance  hips and legs while sweeping and standing still (Action3). Feet planted
                    wide, knees bent, the hips shifting with each stroke. SweepController
                    plays it in step with _Use and stops it as soon as you walk.

Families (FAMILY below): scrub (toothbrush), sweep (brooms, duster), rake (pull strokes), mop
(figure-eight), push (push broom lunges), blower (hip-held arc), vacuum (hip-held push/pull).

What makes these better than the first set:
- 30 keyframes a second instead of 8-16 per loop, so linear easing reads as smooth curves.
- Strokes are asymmetric (a quick power stroke and a slower return) instead of plain sines.
- Overlap: the head looks at the tool's business end a few frames late, the hips lead the
  shoulders, the hand arcs a little on the way back.
- The legs take part when standing (Stance), and the tool head is solved so it touches the
  ground in that crouch and hovers just above it while walking.

How it fits together (unchanged):
- The right hand holds the tool at its meta "grip" point. Tool.Grip's rotation is solved so
  that in the reference pose the tool points from the right hand at its "tip" target.
- The left hand is solved per frame (inverse kinematics) onto the meta "grip2" point (or for
  hip tools, a spot on the body next to the handle), so it stays on the tool all the time.

Reads art/out/meta.json (grip, grip2, tip for each Tool_*), writes art/out/anims/
Tool_<Id>_{Hold,Use,Stance}.rbxmx and src/shared/Config/ToolGrips.luau.
Usage: python3 art/anim/tool_anims.py [--plot DIR] [--only Id,Id]
"""
import json
import math
import os
import sys

import numpy as np
from scipy.optimize import minimize

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_anims as B  # noqa: E402
import r15  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
META = os.path.join(ROOT, "art", "out", "meta.json")
GRIPS_LUA = os.path.join(ROOT, "src", "shared", "Config", "ToolGrips.luau")
D = math.radians
S = math.sin
C = math.cos
FPS = 30


def warp(w, k):
    """Phase warp: with k > 0 the first half of the loop (the power stroke) goes faster."""
    return w + k * S(w)


def body(lean=0.0, twist=0.0, shift=(0, 0, 0), head=0.0, roll=0.0, right=(0, 0, 0, 0), left=None):
    """Poses for the upper body. Angles in degrees; arms are (shoulder X, Y, Z, elbow X)."""
    ut = np.array(B.yaw_lean(twist, lean)) @ r15.angles(0, 0, D(roll))
    p = {
        "UpperTorso": (shift, ut.tolist()),
        "Head": ((0, 0, 0), (D(head), -D(twist) * 0.4, 0)),
        "RightUpperArm": ((0, 0, 0), (D(right[0]), D(right[1]), D(right[2]))),
        "RightLowerArm": ((0, 0, 0), (D(right[3]), 0, 0)),
    }
    if left is not None:
        p["LeftUpperArm"] = ((0, 0, 0), (D(left[0]), D(left[1]), D(left[2])))
        p["LeftLowerArm"] = ((0, 0, 0), (D(left[3]), 0, 0))
    return p


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def breathe(w):
    """Hold loop: a slow breath (chest rises, shoulders settle) and a small sway."""
    return dict(lean=1.2 * S(w), shift=(0, 0.025 * (1 - C(w)), 0), twist=2.5 * S(w + 0.6))


# Right arm angles solved to put the hand on the top handle of hip tools; filled by main().
RIGHT = {}


# --- families -------------------------------------------------------------------------------
# pose(w, use, tid) -> upper body poses; w is the loop phase in radians. stance(w) -> hips
# and feet (see legs()). Each family's "ref" pose is where the grip is solved.

def scrub(w, use, tid):
    if use:
        # Crouched over, scrubbing in quick little circles; the body bobs with each circle.
        return body(lean=-30 + 2 * S(2 * w), twist=-12 + 5 * S(w), shift=(0.03 * S(w), 0.03 * S(2 * w), -0.05 * C(w)),
                    head=18, roll=2 * S(w),
                    right=(40 + 7 * S(w), 4 * C(w), -8 + 7 * C(w), 20 - 6 * S(w)),
                    left=(25, 0, 16, 45))
    b = breathe(w)
    return body(lean=-5 + b["lean"], twist=-8 + b["twist"], shift=b["shift"], head=4 + 2 * S(w + 1.2),
                right=(16 + 2 * S(w), 0, -6, 32 + 2 * S(w)), left=(4 + S(w), 0, -6, 12))


def sweep(w, use, tid):
    if use:
        # Long strokes across the ground: a fast push to the left, a slower return. The
        # shoulders lead, the arm reaches out at the end of each stroke.
        u = warp(w, 0.45)
        swing = 28 * S(u)
        reach = 6 * S(u + 0.5)
        return body(lean=-14 - 3 * C(2 * u), twist=-10 + swing, shift=(0, -0.03 * C(2 * u), 0),
                    head=10, roll=-4 * S(u),
                    right=(30 + reach, 0, -28 - 0.25 * swing, 40 - reach))
    b = breathe(w)
    return body(lean=-12 + b["lean"], twist=-10 + b["twist"], shift=b["shift"], head=9 + 1.5 * S(w + 1),
                right=(28, 0, -28, 40))


def rake(w, use, tid):
    if use:
        # Reach out, bite into the leaves and drag them back toward you; lift a little on
        # the way out. The pull (second half) is the slow strong part.
        u = warp(w, -0.35)
        pull = C(u)                       # 1 = reached out, -1 = pulled in
        lift = max(0.0, S(u)) ** 2        # lifted while going back out
        return body(lean=-16 - 8 * pull, twist=-9 + 6 * S(u + 1.0), shift=(0, 0, -0.18 * pull),
                    head=10 + 4 * pull, roll=-2 * S(u),
                    right=(32 + 14 * pull + 6 * lift, 0, -26, 40 - 18 * pull))
    b = breathe(w)
    return body(lean=-13 + b["lean"], twist=-9 + b["twist"], shift=b["shift"], head=9 + 1.5 * S(w + 1),
                right=(30, 0, -26, 38))


def mop(w, use, tid):
    if use:
        # Figure-eight across the floor, the body rocking into each push.
        push = S(w)
        return body(lean=-16 - 4 * push, twist=-6 + 16 * S(2 * w + 0.3), shift=(0.04 * S(2 * w), 0, -0.22 * push),
                    head=12, roll=-3 * S(2 * w),
                    right=(34 + 6 * push, 0, -22 - 6 * S(2 * w), 34 - 4 * push))
    b = breathe(w)
    return body(lean=-14 + b["lean"], twist=-6 + b["twist"], shift=b["shift"], head=11 + 1.5 * S(w + 1),
                right=(34, 0, -22, 34))


def push(w, use, tid):
    if use:
        # Lunging shoves: drive the wide head forward fast, ease back slower.
        u = warp(w, 0.5)
        f = S(u)
        return body(lean=-15 - 8 * f, twist=-7 + 4 * S(2 * u), shift=(0, -0.03 * abs(f), -0.32 * f),
                    head=11 + 3 * f, right=(32 + 10 * f, 0, -24, 38 - 10 * f))
    b = breathe(w)
    return body(lean=-13 + b["lean"], twist=-7 + b["twist"], shift=b["shift"], head=10 + 1.5 * S(w + 1),
                right=(30, 0, -24, 38))


def blower(w, use, tid):
    if use:
        # Hip-held, swinging the air stream in a wide arc, braced against the push of the air
        # (a little shake on top).
        u = warp(w, 0.25)
        arc = 32 * S(u)
        shake = 0.6 * S(9 * w)
        return body(lean=-7 + 2 * S(2 * u) + shake, twist=-8 + arc, roll=-3 * S(u), head=6,
                    right=add(RIGHT[tid], (2 * S(2 * u), 0, 0, 0)))
    b = breathe(w)
    return body(lean=-6 + b["lean"], twist=-8 + b["twist"], shift=b["shift"], head=5 + 1.5 * S(w + 1), right=RIGHT[tid])


def vacuum(w, use, tid):
    if use:
        # Push the nozzle out and pull it back while swinging to each side.
        u = warp(w, 0.4)
        f = S(u)
        return body(lean=-11 - 5 * f, twist=-8 + 14 * S(u + 0.9), shift=(0, 0, -0.3 * f), roll=-2 * S(u + 0.9),
                    head=9, right=add(RIGHT[tid], (4 * f, 0, 0, -3 * f)))
    b = breathe(w)
    return body(lean=-8 + b["lean"], twist=-8 + b["twist"], shift=b["shift"], head=7 + 1.5 * S(w + 1), right=RIGHT[tid])


# --- stances ----------------------------------------------------------------------------------
# Hips: (shift x, y, z), yaw, roll in degrees. Feet: ankle points on the ground (HRP space),
# right then left, plus each foot's yaw (toes turned out).

def stance_for(fam):
    feet = {
        "scrub": ((0.75, 0.15), (-0.75, -0.35), 25, -20),
        "sweep": ((0.8, 0.05), (-0.7, -0.35), 20, -15),
        "rake": ((0.6, 0.35), (-0.65, -0.5), 15, -10),
        "mop": ((0.75, 0.0), (-0.7, -0.4), 20, -15),
        "push": ((0.55, 0.6), (-0.6, -0.55), 10, -5),
        "blower": ((0.8, 0.2), (-0.7, -0.4), 25, -15),
        "vacuum": ((0.7, 0.3), (-0.7, -0.45), 20, -10),
    }[fam]
    drop = DROP[fam]

    def fn(w):
        if fam == "scrub":
            hip = ((0.04 * S(w), -drop + 0.03 * S(2 * w), 0), -8 + 3 * S(w), 2 * S(w))
        elif fam == "sweep":
            u = warp(w, 0.45)
            hip = ((0.14 * S(u), -drop - 0.04 * abs(S(u)), 0), -6 + 10 * S(u), 4 * S(u))
        elif fam == "rake":
            u = warp(w, -0.35)
            hip = ((0, -drop + 0.03 * C(u), -0.12 * C(u)), -6 + 3 * S(u + 1), 0)
        elif fam == "mop":
            hip = ((0.08 * S(2 * w), -drop, -0.1 * S(w)), -4 + 7 * S(2 * w + 0.3), 2 * S(2 * w))
        elif fam == "push":
            u = warp(w, 0.5)
            hip = ((0, -drop - 0.05 * abs(S(u)), -0.22 * S(u)), -4, 0)
        elif fam == "blower":
            u = warp(w, 0.25)
            hip = ((0.1 * S(u), -drop, 0), -6 + 12 * S(u), 3 * S(u))
        else:
            u = warp(w, 0.4)
            hip = ((0.06 * S(u + 0.9), -drop, -0.12 * S(u)), -6 + 7 * S(u + 0.9), 2 * S(u + 0.9))
        return hip, feet
    return fn


DROP = {"scrub": 0.42, "sweep": 0.3, "rake": 0.28, "mop": 0.3, "push": 0.3, "blower": 0.25, "vacuum": 0.25}


def legs(hip, feet, guess=None):
    """LowerTorso + leg poses that keep both feet planted (flat, turned out) on the ground."""
    (shift, yaw, roll), (rf, lf, ryaw, lyaw) = hip, feet
    lt = ((shift[0], shift[1], shift[2]), r15.angles(0, D(yaw), D(roll)).tolist())
    poses = {"LowerTorso": lt}
    out = {}
    for side, (x, z), fy, g in (("Right", rf, ryaw, None if guess is None else guess[0]),
                                ("Left", lf, lyaw, None if guess is None else guess[1])):
        target = np.array([x, r15.GROUND + r15.ANKLE_UP, z])

        def cost(v):
            p = dict(poses)
            p[side + "UpperLeg"] = ((0, 0, 0), (D(v[0]), D(v[1]), D(v[2])))
            p[side + "LowerLeg"] = ((0, 0, 0), (D(v[3]), 0, 0))
            f = r15.solve(p)
            # ankle = lower leg frame * C0 of the ankle joint
            a = (f[side + "LowerLeg"] @ r15.T(0, -0.596, 0))[:3, 3]
            e = a - target
            return float(e @ e) + 1e-5 * (v[1] - fy * 0.5) ** 2 + 1e-6 * v[3] ** 2
        x0 = g if g is not None else np.array([20.0, fy * 0.5, 0.0, -40.0])
        best = minimize(cost, x0, method="L-BFGS-B",
                        bounds=[(-60, 100), (-60, 60), (-40, 40), (-150, 0)], options={"ftol": 1e-14, "gtol": 1e-10})
        v = best.x
        out[side] = v
        poses[side + "UpperLeg"] = ((0, 0, 0), (D(v[0]), D(v[1]), D(v[2])))
        poses[side + "LowerLeg"] = ((0, 0, 0), (D(v[3]), 0, 0))
        f = r15.solve(poses)
        want = r15.angles(0, D(fy), 0)
        poses[side + "Foot"] = ((0, 0, 0), (f[side + "LowerLeg"][:3, :3].T @ want).tolist())
    return poses, (out["Right"], out["Left"])


# --- the tool list ---------------------------------------------------------------------------
FAMILY = {
    "Toothbrush": "scrub",
    "Broom": "sweep", "GoldenBroom": "sweep", "RainbowDuster": "sweep",
    "Rake": "rake",
    "Mop": "mop", "DiamondMop": "mop",
    "PushBroom": "push",
    "LeafBlower": "blower", "StormBlower": "blower", "PressureWasher": "blower",
    "ShopVac": "vacuum", "TurboVacuum": "vacuum", "LeafVac": "vacuum", "TornadoVac": "vacuum",
    "GalaxyVacuum": "vacuum",
}
POSE = {"scrub": scrub, "sweep": sweep, "rake": rake, "mop": mop, "push": push, "blower": blower, "vacuum": vacuum}
# aim: ("ground", hover, yaw) puts the tip `hover` above the ground (while walking) straight
# out from the hand; ("at", (x, y, z)) points grip -> tip at a point (HRP space).
# hold/use: loop length in seconds. Heavier tools stroke slower.
FAM = {
    "scrub": dict(aim=("ground", None, 4), two=False, hold=2.4, use=0.42),
    "sweep": dict(aim=("ground", None, -4), two=True, hold=2.6, use=0.85),
    "rake": dict(aim=("ground", None, -2), two=True, hold=2.6, use=1.0),
    "mop": dict(aim=("ground", None, 0), two=True, hold=2.6, use=1.2),
    "push": dict(aim=("ground", None, 0), two=True, hold=2.6, use=0.8),
    "blower": dict(aim=("at", (0.6, r15.GROUND, -5.0)), two=True, left=(-0.42, -0.3, -0.1), hold=2.6, use=1.7),
    "vacuum": dict(aim=("at", (0.4, r15.GROUND + 0.2, -4.6)), two=True, left=(-0.48, -0.3, 0.0), hold=2.6, use=1.0),
}
# A few tools stroke faster or slower than their family.
SPEED = {"GoldenBroom": 0.9, "RainbowDuster": 0.85, "TurboVacuum": 0.75, "GalaxyVacuum": 0.8, "TornadoVac": 0.85,
         "StormBlower": 0.9, "DiamondMop": 0.9}
RIGHT_HAND = (0.45, -0.2, -1.0)  # hip tools: right hand on the top handle (HRP space)


def style(tid):
    fam = FAMILY[tid]
    s = dict(FAM[fam])
    s["family"] = fam
    s["pose"] = lambda w, use, tid=tid, fam=fam: POSE[fam](w, use, tid)
    s["stance"] = stance_for(fam)
    s["use"] = s["use"] * SPEED.get(tid, 1.0)
    return s


# --- tool geometry ------------------------------------------------------------------------

def tool_points(meta, tid, st):
    m = meta[f"Tool_{tid}"]
    grip = np.array(m.get("grip", [0, 0, 0]), float)
    lo = np.array(m["bounds"]["min"], float)
    tip = np.array(m["tip"], float) if "tip" in m else np.array([0, 0, lo[2]])
    if "left" in st:
        # Hip tools: the tube grip is out of reach for Roblox arms, so the left hand steadies
        # the side of the body next to the handle instead.
        return grip, grip + np.array(st["left"]), tip
    if "grip2" in m:
        grip2 = np.array(m["grip2"], float)
    else:
        grip2 = grip + np.array([0, 0, 1.2])
    return grip, grip2, tip


def basis(look, up):
    """Columns x, y, z of a frame looking along `look` (z = -look) with y close to `up`."""
    z = -look / np.linalg.norm(look)
    x = np.cross(up, z)
    x /= np.linalg.norm(x)
    y = np.cross(z, x)
    return np.column_stack([x, y, z])


def with_hips(poses, st, w):
    """Upper body poses on top of the standing crouch (hips lowered and shifted)."""
    p = dict(poses)
    hip, _ = st["stance"](w)
    p["LowerTorso"] = ((hip[0][0], hip[0][1], hip[0][2]), r15.angles(0, D(hip[1]), D(hip[2])))
    return p


def solve_grip(st, grip, tip):
    # Reference: the use pose at phase 0 standing in the crouch; the tip just touches the
    # ground there (so it hovers DROP above it while walking).
    F = r15.solve(with_hips(st["pose"](0.0, True), st, 0.0))["RightGrip"]
    g = F[:3, 3]
    length = np.linalg.norm(tip - grip)
    kind = st["aim"][0]
    if kind == "ground":
        yaw = D(st["aim"][2])
        dy = r15.GROUND + 0.05 - g[1]
        horiz = math.sqrt(max(length * length - dy * dy, 0.01))
        if length < abs(dy):
            print(f"  ! tool too short for the pose: needs {abs(dy):.2f}, has {length:.2f}")
        target = g + np.array([-horiz * math.sin(yaw), dy, -horiz * math.cos(yaw)])
    else:
        target = np.array(st["aim"][1], float) - np.array([0, DROP[st["family"]], 0])
    d = target - g
    Rw = basis(d, np.array([0, 1, 0])) @ basis(tip - grip, np.array([0, 1, 0])).T  # model -> HRP
    return F[:3, :3].T @ Rw  # model axes in the grip attachment frame


def tool_world(frames, M, grip, p):
    F = frames["RightGrip"]
    return F[:3, 3] + F[:3, :3] @ M @ (p - grip)


# --- arm IK -------------------------------------------------------------------------------------
LEFT_REST = np.array([30, 10, 60, 40], float)
LEFT_BOUNDS = [(-60, 160), (-90, 90), (-40, 135), (0, 140)]
RIGHT_REST = np.array([20, 0, -20, 40], float)
RIGHT_BOUNDS = [(-60, 160), (-90, 90), (-135, 40), (0, 140)]


def solve_arm(side, poses, target, guess, rest, bounds):
    def cost(x):
        p = dict(poses)
        p[side + "UpperArm"] = ((0, 0, 0), (D(x[0]), D(x[1]), D(x[2])))
        p[side + "LowerArm"] = ((0, 0, 0), (D(x[3]), 0, 0))
        h = r15.solve(p)[side + "Grip"][:3, 3]
        e = target - h
        return float(e @ e) + 2e-5 * float((x - rest) @ (x - rest)) + (0 if guess is None else 2e-4 * float((x - guess) @ (x - guess)))
    opts = {"ftol": 1e-14, "gtol": 1e-10}
    if guess is not None:
        return minimize(cost, guess, method="L-BFGS-B", bounds=bounds, options=opts).x
    best = None
    for a in (0, 40, 80):
        for c in ((-60, -20, 20) if side == "Right" else (-20, 20, 60)):
            for d in (20, 70, 120):
                for b in (-30, 0, 30):
                    r = minimize(cost, np.array([a, b, c, d], float), method="L-BFGS-B", bounds=bounds, options=opts)
                    if best is None or r.fun < best.fun:
                        best = r
    return best.x


def look_at(f, point):
    """Head angles (pitch, yaw) in the UpperTorso frame to look at a point."""
    ut = f["UpperTorso"]
    head = f["Head"][:3, 3]
    d = ut[:3, :3].T @ (point - head)
    yaw = math.atan2(-d[0], -d[2])
    pitch = math.atan2(d[1], math.hypot(d[0], d[2]))
    return pitch, yaw


def frames_for(st, M, pts, use, duration, crouch):
    """Keyframes for one loop. crouch=True adds the stance hips (used only to check the
    tip; the Use/Hold clips themselves never key the hips)."""
    grip, grip2, tip = pts
    n = max(12, round(duration * FPS))
    raw, guess, worst, tips = [], None, 0.0, []
    for i in range(n + 1):
        w = 2 * math.pi * i / n
        poses = st["pose"](w, use)
        solve_p = with_hips(poses, st, w) if crouch else poses
        if st["two"]:
            f = r15.solve(solve_p)
            target = tool_world(f, M, grip, grip2)
            guess = solve_arm("Left", solve_p, target, guess, LEFT_REST, LEFT_BOUNDS)
            for p in (poses, solve_p):
                p["LeftUpperArm"] = ((0, 0, 0), (D(guess[0]), D(guess[1]), D(guess[2])))
                p["LeftLowerArm"] = ((0, 0, 0), (D(guess[3]), 0, 0))
            f = r15.solve(solve_p)
            worst = max(worst, float(np.linalg.norm(target - f["LeftGrip"][:3, 3])))
        f = r15.solve(solve_p)
        tips.append(tool_world(f, M, grip, tip))
        raw.append((duration * i / n, poses, solve_p))
    # Head: look at the business end a few frames late (overlap), blended with the pose's
    # own head angle so it never snaps.
    lag = max(1, round(0.12 * FPS))
    out = []
    for i, (t, poses, solve_p) in enumerate(raw):
        j = (i - lag) % n
        f = r15.solve(solve_p)
        pitch, yaw = look_at(f, tips[j])
        base = poses["Head"][1]
        hp = 0.45 * max(-0.6, min(0.5, pitch)) + 0.55 * base[0] - 0.25
        hy = 0.5 * max(-0.7, min(0.7, yaw)) + 0.5 * base[1]
        poses["Head"] = ((0, 0, 0), (hp, hy, 0))
        out.append((t, poses))
    return out, worst, tips


def stance_frames(st, duration):
    n = max(12, round(duration * FPS))
    out, guess = [], None
    for i in range(n + 1):
        w = 2 * math.pi * i / n
        hip, feet = st["stance"](w)
        poses, guess = legs(hip, feet, guess)
        out.append((duration * i / n, poses))
    return out


STANCE_TREE = {
    "HumanoidRootPart": {
        "LowerTorso": {
            "RightUpperLeg": {"RightLowerLeg": {"RightFoot": {}}},
            "LeftUpperLeg": {"LeftLowerLeg": {"LeftFoot": {}}},
        }
    }
}


def rot_lua(M):
    cols = [M[:, 0], M[:, 1], M[:, 2]]
    v = lambda c: "Vector3.new({:.4f}, {:.4f}, {:.4f})".format(*c)  # noqa: E731
    return f"CFrame.fromMatrix(Vector3.zero, {v(cols[0])}, {v(cols[1])}, {v(cols[2])})"


BONES = [("LowerTorso", "UpperTorso"), ("UpperTorso", "Head"), ("UpperTorso", "RightUpperArm"),
         ("RightUpperArm", "RightLowerArm"), ("RightLowerArm", "RightHand"), ("UpperTorso", "LeftUpperArm"),
         ("LeftUpperArm", "LeftLowerArm"), ("LeftLowerArm", "LeftHand"), ("HumanoidRootPart", "LowerTorso"),
         ("LowerTorso", "RightUpperLeg"), ("RightUpperLeg", "RightLowerLeg"), ("RightLowerLeg", "RightFoot"),
         ("LowerTorso", "LeftUpperLeg"), ("LeftUpperLeg", "LeftLowerLeg"), ("LeftLowerLeg", "LeftFoot")]


def plot(path, tid, st, M, pts, use_frames, stance):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    grip, _, tip = pts
    fig, axes = plt.subplots(1, 3, figsize=(15, 5))
    picks = [0, len(use_frames) // 4, len(use_frames) // 2, 3 * len(use_frames) // 4]
    for col, (view, ia, ib) in enumerate([("side (Z,Y)", 2, 1), ("front (X,Y)", 0, 1), ("top (X,Z)", 0, 2)]):
        ax = axes[col]
        for k, i in enumerate(picks):
            poses = dict(use_frames[i][1])
            poses.update(stance[min(i, len(stance) - 1)][1])
            f = r15.solve(poses)
            c = ["C0", "C1", "C2", "C3"][k]
            for a, b in BONES:
                pa, pb = f[a][:3, 3], f[b][:3, 3]
                ax.plot([pa[ia], pb[ia]], [pa[ib], pb[ib]], c, lw=2, alpha=0.6)
            g = tool_world(f, M, grip, grip)
            tp = tool_world(f, M, grip, tip)
            ax.plot([g[ia], tp[ia]], [g[ib], tp[ib]], c + "-", lw=4)
            ax.plot(tp[ia], tp[ib], c + "o")
        if ib == 1:
            ax.axhline(r15.GROUND, color="brown")
        ax.set_aspect("equal")
        ax.set_xlim(-4, 4) if ia != 2 else ax.set_xlim(2, -8)
        ax.set_title(f"{tid} use+stance {view}")
    fig.tight_layout()
    fig.savefig(os.path.join(path, f"{tid}.png"), dpi=60)
    plt.close(fig)


def main():
    plot_dir = sys.argv[sys.argv.index("--plot") + 1] if "--plot" in sys.argv else None
    only = set(sys.argv[sys.argv.index("--only") + 1].split(",")) if "--only" in sys.argv else None
    meta = json.load(open(META))
    os.makedirs(B.OUT, exist_ok=True)
    for tid, fam in FAMILY.items():
        if fam in ("blower", "vacuum"):
            RIGHT[tid] = (0, 0, 0, 0)
            poses = POSE[fam](0.0, False, tid)
            x = solve_arm("Right", poses, np.array(RIGHT_HAND), None, RIGHT_REST, RIGHT_BOUNDS)
            RIGHT[tid] = tuple(round(float(v), 1) for v in x)
    lua = ["--!strict", "-- Generated by art/anim/tool_anims.py from art/out/meta.json. Do not edit by hand.",
           "-- Per tool: the rotation of the tool model in the right hand's grip attachment, matched to",
           "-- the Tool_<Id>_Hold / _Use / _Stance animations (Tool.Grip uses its inverse).",
           "return {"]
    old = {}
    if os.path.exists(GRIPS_LUA):
        for line in open(GRIPS_LUA):
            line = line.rstrip("\n")
            if line.startswith("\t") and " = CFrame" in line:
                old[line.strip().split(" ")[0]] = line
    for tid in FAMILY:
        if f"Tool_{tid}" not in meta:
            print("skip", tid, "(no meta)")
            continue
        if only and tid not in only:
            if tid in old:
                lua.append(old[tid])
            continue
        st = style(tid)
        pts = tool_points(meta, tid, st)
        M = solve_grip(st, pts[0], pts[2])
        use_frames, worst, tips_crouch = frames_for(st, M, pts, True, st["use"], True)
        _, _, tips_walk = frames_for(st, M, pts, True, st["use"], False)
        hold_frames, _, _ = frames_for(st, M, pts, False, st["hold"], False)
        stance = stance_frames(st, st["use"])
        for kind, frames, prio, tree in (("Hold", hold_frames, 2, B.R15_TREE), ("Use", use_frames, 3, B.R15_TREE),
                                         ("Stance", stance, 4, STANCE_TREE)):
            name = f"Tool_{tid}_{kind}"
            with open(os.path.join(B.OUT, f"{name}.rbxmx"), "w") as fh:
                fh.write(B.sequence(name, frames, True, prio, tree))
        lo_c = min(t[1] for t in tips_crouch) - r15.GROUND
        hi_c = max(t[1] for t in tips_crouch) - r15.GROUND
        lo_w = min(t[1] for t in tips_walk) - r15.GROUND
        print(f"{tid:15s} {st['family']:7s} tip above ground: standing {lo_c:+.2f}..{hi_c:+.2f}, walking from {lo_w:+.2f}"
              + (f", left hand off by up to {worst:.2f}" if st["two"] else ""))
        lua.append(f"\t{tid} = {rot_lua(M)},")
        if plot_dir:
            os.makedirs(plot_dir, exist_ok=True)
            plot(plot_dir, tid, st, M, pts, use_frames, stance)
    lua.append("}")
    with open(GRIPS_LUA, "w") as fh:
        fh.write("\n".join(lua) + "\n")
    print("wrote", GRIPS_LUA)


if __name__ == "__main__":
    main()
