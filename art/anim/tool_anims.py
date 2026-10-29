"""Per-tool player animations (hold + use) and the matching Tool.Grip rotations.

Every tool gets its own style: the toothbrush is held in one hand and scrubbed fast close to
the ground, the broom sweeps side to side with two hands, the mop pushes and pulls, the leaf
blower is held at the hip and swept across, and the vacuums push and pull at the hip.

How it fits together:
- The right hand holds the tool at its meta "grip" point. Each style poses the right arm and
  body by hand; the tool's rotation in the hand (Tool.Grip) is solved so that in the style's
  reference pose the tool points from the right hand at its "tip" target (on the ground for
  brushes and mops, a spot on the ground in front for blowers and vacuums).
- The left hand is solved per frame (inverse kinematics) onto the meta "grip2" point, so it
  stays on the handle or tube through the whole animation.
- Tools are used at their modelled size (ToolService no longer rescales them).

Reads art/out/meta.json (grip, grip2, tip for each Tool_*), writes
art/out/anims/Tool_<Id>_Hold.rbxmx / Tool_<Id>_Use.rbxmx and src/shared/Config/ToolGrips.luau.
Usage: python3 art/anim/tool_anims.py [--plot DIR]
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


def body(lean=0.0, twist=0.0, shift=(0, 0, 0), head=0.0, right=(0, 0, 0, 0), left=None):
    """Poses for the upper body. Angles in degrees; arms are (shoulder X, Y, Z, elbow X)."""
    p = {
        "UpperTorso": (shift, B.yaw_lean(twist, lean)),
        "Head": ((0, 0, 0), (D(head), -D(twist) * 0.5, 0)),
        "RightUpperArm": ((0, 0, 0), (D(right[0]), D(right[1]), D(right[2]))),
        "RightLowerArm": ((0, 0, 0), (D(right[3]), 0, 0)),
    }
    if left is not None:
        p["LeftUpperArm"] = ((0, 0, 0), (D(left[0]), D(left[1]), D(left[2])))
        p["LeftLowerArm"] = ((0, 0, 0), (D(left[3]), 0, 0))
    return p


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


# --- styles ------------------------------------------------------------------------------
# Each pose function takes (w, use): w is the loop phase in radians, use is False for the
# hold loop and True for the use loop. "ref" is the pose the grip is solved in.

def toothbrush(w, use):
    if use:
        # Bent right over, scrubbing fast with short strokes; the free hand braced on the knee.
        s = S(w)
        return body(lean=-34 + 1.5 * S(2 * w), twist=-14 + 4 * s, shift=(0, 0.04 * S(2 * w), -0.32 * s), head=22,
                    right=(42 + 3 * s, 0, -8, 18 - 3 * s),
                    left=(22, 0, 14, 38))
    # Standing, brush carried low in front, a small bounce.
    return body(lean=-4, twist=-8 + 2 * S(w), head=4 + 1.5 * S(w),
                right=(14 + 3 * S(w), 0, -6, 30), left=(4, 0, -6, 12))


def broom(w, use):
    if use:
        # Strokes across the ground: a quick push and a slower return.
        swing = 24 * S(w + 0.35 * S(w))
        return body(lean=-12, twist=-10 + swing, head=10 + 3 * S(2 * w), right=(28, 0, -28, 40))
    return body(lean=-12, twist=-10 + 2 * S(w), head=10 + 1.5 * S(w), right=(28, 0, -28, 40))


def mop(w, use):
    if use:
        # Push and pull with a little figure-eight, the body rocking into each push.
        push = S(w)
        return body(lean=-15 - 3 * push, twist=-6 + 9 * S(2 * w), shift=(0, 0.06 * push, -0.4 * push),
                    head=12, right=(34 + 4 * push, 0, -22, 34))
    return body(lean=-14, twist=-6 + 2 * S(w), head=11 + 1.5 * S(w), right=(34, 0, -22, 34))


# Right arm angles solved to put the hand at a spot (see RIGHT_HAND below); filled by main().
RIGHT = {}


def blower(w, use):
    if use:
        # Hip-held, sweeping the air stream across the ground in front.
        sweep = 26 * S(w)
        return body(lean=-8 + 2 * S(2 * w), twist=-8 + sweep, head=6, right=RIGHT["LeafBlower"])
    return body(lean=-6, twist=-8 + 2 * S(w), head=5 + 1.5 * S(w), right=RIGHT["LeafBlower"])


def shopvac(w, use):
    if use:
        # Push the nozzle out and pull it back, swinging a little to each side.
        push = S(w)
        return body(lean=-11 - 3 * push, twist=-8 + 8 * S(2 * w),
                    shift=(0, 0, -0.3 * push), head=9, right=add(RIGHT["ShopVac"], (2 * push, 0, 0, 0)))
    return body(lean=-8, twist=-8 + 2 * S(w), head=7 + 1.5 * S(w), right=RIGHT["ShopVac"])


def turbo(w, use):
    if use:
        # Faster and punchier: a sharp shove forward with a kick back, sweeping side to side.
        push = S(w) + 0.35 * S(2 * w)
        return body(lean=-12 - 3 * push, twist=-8 + 14 * S(w + 0.8), shift=(0, 0, -0.32 * push),
                    head=9, right=add(RIGHT["TurboVacuum"], (2 * push, 0, 0, 0)))
    return body(lean=-9, twist=-8 + 2.5 * S(w), head=7 + 1.5 * S(w), right=RIGHT["TurboVacuum"])


# aim: ("ground", hover, yaw) puts the tip just above the ground straight out from the hand
# (yaw turns it, + to the left); ("at", (x, y, z)) points grip -> tip at a point (HRP space).
STYLES = {
    "Toothbrush": dict(pose=toothbrush, ref=(0.0, True), aim=("ground", 0.25, 4), two=False,
                       hold=(1.6, 8), use=(0.34, 8)),
    "Broom": dict(pose=broom, ref=(0.0, True), aim=("ground", 0.25, -4), two=True,
                  hold=(2.0, 8), use=(0.8, 12)),
    "Mop": dict(pose=mop, ref=(0.0, True), aim=("ground", 0.15, 0), two=True,
                hold=(2.0, 8), use=(1.0, 12)),
    "LeafBlower": dict(pose=blower, ref=(0.0, True), aim=("at", (0.6, r15.GROUND, -5.0)), two=True, left=(-0.42, -0.3, -0.1),
                       hold=(2.0, 8), use=(1.6, 16)),
    "ShopVac": dict(pose=shopvac, ref=(0.0, True), aim=("at", (0.4, r15.GROUND + 0.2, -4.6)), two=True, left=(-0.48, -0.3, 0.0),
                    hold=(2.0, 8), use=(0.9, 12)),
    "TurboVacuum": dict(pose=turbo, ref=(0.0, True), aim=("at", (0.4, r15.GROUND + 0.2, -4.8)), two=True, left=(-0.48, -0.3, -0.05),
                        hold=(2.0, 8), use=(0.6, 12)),
}


# Hip-held tools: where the right hand holds the top handle in the hold pose (HRP space).
RIGHT_HAND = {
    "LeafBlower": (0.45, -0.2, -1.0),
    "ShopVac": (0.45, -0.25, -1.0),
    "TurboVacuum": (0.45, -0.2, -1.0),
}


# --- tool geometry ------------------------------------------------------------------------

def tool_points(meta, tid):
    m = meta[f"Tool_{tid}"]
    if "left" in STYLES[tid]:
        # Hip tools: the tube grip is out of reach for Roblox arms, so the left hand steadies
        # the side of the body next to the handle instead.
        g = np.array(m.get("grip", [0, 0, 0]), float)
        lo = np.array(m["bounds"]["min"], float)
        tip = np.array(m["tip"], float) if "tip" in m else np.array([0, 0, lo[2]])
        return g, g + np.array(STYLES[tid]["left"]), tip
    grip = np.array(m.get("grip", [0, 0, 0]), float)
    lo = np.array(m["bounds"]["min"], float)
    tip = np.array(m["tip"], float) if "tip" in m else np.array([0, 0, lo[2]])
    if "grip2" in m:
        grip2 = np.array(m["grip2"], float)
    elif tid in ("Broom", "Mop", "Toothbrush"):
        grip2 = grip + np.array([0, 0, 1.2])
    else:
        grip2 = grip + 0.45 * (tip - grip) + np.array([0, -0.3, 0])
    return grip, grip2, tip


def basis(look, up):
    """Columns x, y, z of a frame looking along `look` (z = -look) with y close to `up`."""
    z = -look / np.linalg.norm(look)
    x = np.cross(up, z)
    x /= np.linalg.norm(x)
    y = np.cross(z, x)
    return np.column_stack([x, y, z])


def solve_grip(style, grip, tip):
    w, use = style["ref"]
    F = r15.solve(style["pose"](w, use))["RightGrip"]
    g = F[:3, 3]
    length = np.linalg.norm(tip - grip)
    kind = style["aim"][0]
    if kind == "ground":
        hover, yaw = style["aim"][1], D(style["aim"][2])
        dy = r15.GROUND + hover - g[1]
        horiz = math.sqrt(max(length * length - dy * dy, 0.01))
        if length < abs(dy):
            print(f"  ! tool too short for the pose: needs {abs(dy):.2f}, has {length:.2f}")
        target = g + np.array([-horiz * math.sin(yaw), dy, -horiz * math.cos(yaw)])
    else:
        target = np.array(style["aim"][1], float)
    d = target - g
    Rw = basis(d, np.array([0, 1, 0])) @ basis(tip - grip, np.array([0, 1, 0])).T  # model -> HRP
    return F[:3, :3].T @ Rw  # model axes in the grip attachment frame


def tool_world(frames, M, grip, p):
    F = frames["RightGrip"]
    return F[:3, 3] + F[:3, :3] @ M @ (p - grip)


# --- left hand IK ---------------------------------------------------------------------------
LEFT_REST = np.array([30, 10, 60, 40], float)
LEFT_BOUNDS = [(-60, 160), (-90, 90), (-40, 135), (0, 140)]
RIGHT_REST = np.array([20, 0, -20, 40], float)
RIGHT_BOUNDS = [(-60, 160), (-90, 90), (-135, 40), (0, 140)]


def to_segment(p, a, b):
    """Offset from p to the closest point of segment a-b, and how far along (0..1) it is."""
    ab = b - a
    t = 0.0 if ab @ ab < 1e-9 else min(1.0, max(0.0, float((p - a) @ ab / (ab @ ab))))
    return a + t * ab - p, t


def solve_arm(side, poses, target, guess, rest, bounds, target_end=None):
    """Arm angles that put the hand on `target`, or anywhere on target..target_end (the hand
    may slide back along a tube to a spot it can reach, preferring the target end)."""
    def cost(x):
        p = dict(poses)
        p[side + "UpperArm"] = ((0, 0, 0), (D(x[0]), D(x[1]), D(x[2])))
        p[side + "LowerArm"] = ((0, 0, 0), (D(x[3]), 0, 0))
        f = r15.solve(p)
        h = f[side + "Grip"][:3, 3]
        if target_end is None:
            e, t = target - h, 0.0
        else:
            e, t = to_segment(h, target, target_end)
        return float(e @ e) + 0.01 * t * t + 2e-5 * float((x - rest) @ (x - rest)) + (0 if guess is None else 2e-4 * float((x - guess) @ (x - guess)))
    opts = {"ftol": 1e-14, "gtol": 1e-10}
    if guess is not None:
        return minimize(cost, guess, method="L-BFGS-B", bounds=bounds, options=opts).x
    # No previous frame to start from: try a spread of starting poses, keep the best.
    best = None
    for a in (0, 40, 80):
        for c in ((-60, -20, 20) if side == "Right" else (-20, 20, 60)):
            for d in (20, 70, 120):
                for b in (-30, 0, 30):
                    r = minimize(cost, np.array([a, b, c, d], float), method="L-BFGS-B", bounds=bounds, options=opts)
                    if best is None or r.fun < best.fun:
                        best = r
    return best.x


def solve_left(poses, target, guess, target_end=None):
    return solve_arm("Left", poses, target, guess, LEFT_REST, LEFT_BOUNDS, target_end)


def frames_for(style, M, pts, use, n_steps, duration):
    grip, grip2, tip = pts
    out = []
    guess = None
    worst = 0.0
    for i in range(n_steps + 1):
        w = 2 * math.pi * i / n_steps
        poses = style["pose"](w, use)
        if style["two"]:
            f = r15.solve(poses)
            target = tool_world(f, M, grip, grip2)
            slide = style.get("slide", 0.0)
            end = None
            if slide > 0:
                u = (grip2 - tip) / np.linalg.norm(grip2 - tip)
                end = tool_world(f, M, grip, grip2 + slide * u)
            guess = solve_left(poses, target, guess, end)
            poses["LeftUpperArm"] = ((0, 0, 0), (D(guess[0]), D(guess[1]), D(guess[2])))
            poses["LeftLowerArm"] = ((0, 0, 0), (D(guess[3]), 0, 0))
            f = r15.solve(poses)
            h = f["LeftGrip"][:3, 3]
            miss = to_segment(h, target, end)[0] if end is not None else target - h
            worst = max(worst, float(np.linalg.norm(miss)))
        out.append((duration * i / n_steps, poses))
    return out, worst


def rot_lua(M):
    cols = [M[:, 0], M[:, 1], M[:, 2]]
    v = lambda c: "Vector3.new({:.4f}, {:.4f}, {:.4f})".format(*c)  # noqa: E731
    return f"CFrame.fromMatrix(Vector3.zero, {v(cols[0])}, {v(cols[1])}, {v(cols[2])})"


def plot(path, tid, style, M, pts, clips):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    grip, grip2, tip = pts
    fig, axes = plt.subplots(2, 3, figsize=(15, 10))
    bones = [("LowerTorso", "UpperTorso"), ("UpperTorso", "Head"), ("UpperTorso", "RightUpperArm"),
             ("RightUpperArm", "RightLowerArm"), ("RightLowerArm", "RightHand"), ("UpperTorso", "LeftUpperArm"),
             ("LeftUpperArm", "LeftLowerArm"), ("LeftLowerArm", "LeftHand"), ("HumanoidRootPart", "LowerTorso")]
    for row, (name, frames) in enumerate(clips):
        picks = [frames[0], frames[len(frames) // 4], frames[len(frames) // 2]]
        for col, (view, ia, ib) in enumerate([("side (Z,Y)", 2, 1), ("front (X,Y)", 0, 1), ("top (X,Z)", 0, 2)]):
            ax = axes[row][col]
            for k, (t, poses) in enumerate(picks):
                f = r15.solve(poses)
                c = ["C0", "C1", "C2"][k]
                for a, b in bones:
                    pa, pb = f[a][:3, 3], f[b][:3, 3]
                    ax.plot([pa[ia], pb[ia]], [pa[ib], pb[ib]], c, lw=2, alpha=0.6)
                g = tool_world(f, M, grip, grip)
                tp = tool_world(f, M, grip, tip)
                g2 = tool_world(f, M, grip, grip2)
                ax.plot([g[ia], tp[ia]], [g[ib], tp[ib]], c + "-", lw=4)
                ax.plot(tp[ia], tp[ib], c + "o")
                if style["two"]:
                    lh = f["LeftGrip"][:3, 3]
                    ax.plot(g2[ia], g2[ib], "kx")
                    ax.plot(lh[ia], lh[ib], c + "s", ms=4)
            if ib == 1:
                ax.axhline(r15.GROUND, color="brown")
            ax.set_aspect("equal")
            ax.set_xlim(-4, 4) if ia != 2 else ax.set_xlim(2, -8)
            ax.set_title(f"{tid} {name} {view}")
    fig.tight_layout()
    fig.savefig(os.path.join(path, f"{tid}.png"), dpi=60)
    plt.close(fig)


def main():
    plot_dir = sys.argv[sys.argv.index("--plot") + 1] if "--plot" in sys.argv else None
    meta = json.load(open(META))
    os.makedirs(B.OUT, exist_ok=True)
    for tid, target in RIGHT_HAND.items():
        RIGHT[tid] = (0, 0, 0, 0)
        poses = STYLES[tid]["pose"](0.0, False)
        x = solve_arm("Right", poses, np.array(target), None, RIGHT_REST, RIGHT_BOUNDS)
        RIGHT[tid] = tuple(round(float(v), 1) for v in x)
        print(tid, "right arm", RIGHT[tid])
    lua = ["--!strict", "-- Generated by art/anim/tool_anims.py from art/out/meta.json. Do not edit by hand.",
           "-- Per tool: the rotation of the tool model in the right hand's grip attachment, matched to",
           "-- the Tool_<Id>_Hold / Tool_<Id>_Use animations (Tool.Grip uses its inverse).",
           "return {"]
    for tid, style in STYLES.items():
        if f"Tool_{tid}" not in meta:
            print("skip", tid, "(no meta)")
            continue
        pts = tool_points(meta, tid)
        print(tid, "length", round(float(np.linalg.norm(pts[2] - pts[0])), 2))
        M = solve_grip(style, pts[0], pts[2])
        clips = []
        for kind, use, prio in (("Hold", False, 2), ("Use", True, 3)):
            dur, steps = style["use" if use else "hold"]
            frames, worst = frames_for(style, M, pts, use, steps, dur)
            clips.append((kind, frames))
            name = f"Tool_{tid}_{kind}"
            with open(os.path.join(B.OUT, f"{name}.rbxmx"), "w") as fh:
                fh.write(B.sequence(name, frames, True, prio, B.R15_TREE))
            lows = min(tool_world(r15.solve(p), M, pts[0], pts[2])[1] for _, p in frames) - r15.GROUND
            print(f"  {name}: tip lowest {lows:+.2f} above ground"
                  + (f", left hand off by up to {worst:.2f}" if style["two"] else ""))
        lua.append(f"\t{tid} = {rot_lua(M)},")
        if plot_dir:
            plot(plot_dir, tid, style, M, pts, clips)
    lua.append("}")
    with open(GRIPS_LUA, "w") as fh:
        fh.write("\n".join(lua) + "\n")
    print("wrote", GRIPS_LUA)


if __name__ == "__main__":
    main()
