"""3D scenes for the sponsored-ad thumbnails, built from the game's own models (art/out).

Usage: python art/ads/scenes.py OUT_DIR [--preview] [scene ...]
Renders OUT_DIR/<scene>.png (1920x1080, or 640x360 with --preview).
Text and effects are added afterwards by art/ads/compose.py.
Needs art/out built first: art/blender/build.py, voxpets.py, clouds.py.
"""
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import kit  # noqa: E402

PREVIEW = False

# avatar outfits
NOOB = dict(skin="F5CD30", shirt="0D69AC", pants="A4BD47")
PRO = dict(skin="FFCC99", shirt="1F1F2E", pants="2A2A3A", hair="F2B233", shoes="FFFFFF")
KID = dict(skin="FFCC99", shirt="E8463C", pants="2B4C8C", cap="2F7DE1", shoes="FFFFFF")
GIRL = dict(skin="FFD1AA", shirt="FF6FB0", pants="6A4CD8", hair="5A2E1A", shoes="FFFFFF")


def base(samples=64, **kw):
    kit.reset()
    if PREVIEW:
        kit.setup(640, 360, samples=12, **kw)
    else:
        kit.setup(1920, 1080, samples=samples, **kw)


def backdrop(seed=3, z=0, near=40, zone="Autumn", trees=True):
    """Ground, a tree line and clouds behind the action (camera looks toward +Y)."""
    kit.ground()
    rnd = random.Random(seed)
    if trees:
        for i in range(14):
            x = -70 + i * 11 + rnd.uniform(-3, 3)
            y = near + rnd.uniform(0, 14)
            kit.place(rnd.choice(["Park_TreeAutumn", "Park_TreeAutumn", "Park_TreeRound"]), (x, y, z),
                      yaw=rnd.uniform(0, 360), scale=rnd.uniform(1.6, 2.2))
    for i in range(6):
        kit.place(f"Cloud{i % 5 + 1}", (-160 + i * 65 + rnd.uniform(-10, 10), 260 + rnd.uniform(0, 60), 55 + rnd.uniform(0, 30)),
                  yaw=rnd.uniform(-20, 20), scale=rnd.uniform(3.5, 5))


def thick_leaves(x0, x1, y0, y1, seed=1, keep=None, drifts=0.25):
    """Carpet plus extra heaps on top so it reads as 'a LOT of leaves'."""
    kit.leaf_carpet(x0, x1, y0, y1, step=4.5, seed=seed, keep=keep)
    rnd = random.Random(seed + 10)
    x = x0
    while x <= x1:
        y = y0
        while y <= y1:
            if (keep is None or keep(x, y)) and rnd.random() < drifts:
                kit.place(rnd.choice(["Drift_Autumn1", "Drift_Autumn2", "Clump_Autumn2", "Clump_Autumn3"]),
                          (x + rnd.uniform(-2, 2), y + rnd.uniform(-2, 2), 0.25), yaw=rnd.uniform(0, 360),
                          scale=(rnd.uniform(1.0, 1.4), rnd.uniform(1.0, 1.4), rnd.uniform(1.2, 1.8)))
            y += 6
        x += 6


def flying_leaves(center, n=40, spread=(6, 3, 4), seed=5, scale=(1.2, 2.2)):
    rnd = random.Random(seed)
    for _ in range(n):
        p = (center[0] + rnd.uniform(-spread[0], spread[0]), center[1] + rnd.uniform(-spread[1], spread[1]),
             center[2] + rnd.uniform(0, spread[2]))
        e = kit.place(rnd.choice(["Clump_Autumn1"]) if False else rnd.choice(LEAVES), p,
                      rot=(rnd.uniform(-70, 70), rnd.uniform(-70, 70), rnd.uniform(0, 360)), scale=rnd.uniform(*scale), ground=False)
        tint_leaf(e, rnd)


LEAVES = ["Leaf_Maple", "Leaf_Oak", "Leaf_Birch"]
LEAF_COLS = ["EC7626", "D64228", "F4BA34", "E49428", "C43424"]


def tint_leaf(e, rnd):
    """Leaf_* meshes are untextured (the game tints them); give each a pile colour."""
    kit.recolor(e, kit.mat(rnd.choice(LEAF_COLS), 0.7))


def coins(center, n=24, spread=(5, 2, 5), seed=9, scale=(0.9, 1.4), name="Coin_Cash"):
    rnd = random.Random(seed)
    for _ in range(n):
        p = (center[0] + rnd.uniform(-spread[0], spread[0]), center[1] + rnd.uniform(-spread[1], spread[1]),
             center[2] + rnd.uniform(0, spread[2]))
        kit.place(name, p, rot=(rnd.uniform(-40, 40), rnd.uniform(-30, 30), rnd.uniform(-60, 60)),
                  scale=rnd.uniform(*scale), ground=False)


def sparkles(center, n=10, spread=(5, 1, 4), seed=4, col="FFF6B0"):
    rnd = random.Random(seed)
    import bpy
    for _ in range(n):
        p = (center[0] + rnd.uniform(-spread[0], spread[0]), center[1] + rnd.uniform(-spread[1], spread[1]),
             center[2] + rnd.uniform(0, spread[2]))
        bpy.ops.mesh.primitive_ico_sphere_add(radius=rnd.uniform(0.08, 0.18), location=p)
        bpy.context.object.data.materials.append(kit.glow_mat(col, 8))


# ------------------------------------------------------------------ scenes
def messy():
    """Left half of the before/after: a yard buried in leaves, noob with a toothbrush, shocked."""
    base(sun_rot=(52, 0, -30))
    backdrop()
    thick_leaves(-40, 40, -24, 40, seed=2, drifts=0.55)
    p = kit.avatar((0, -14.5, 0.55), yaw=12, face="wow", arm_r=(-55, 0, 8), arm_l=(-10, 0, -25), head=(8, 0, 0), **NOOB)
    kit.hold(p, "Tool_Toothbrush", rot=(90, 0, 0), scale=1.3)
    flying_leaves((2, -12, 1.5), n=12, spread=(4, 2, 4), seed=3)
    cam = kit.camera((5.0, -33, 4.6), (3.5, -12, 4.2), lens=40)  # subject sits in the left half of the split
    kit.dof(cam, (0, -14.5, 3), 4.0)


def clean():
    """Right half: same yard spotless, pro with the Galaxy Vacuum, pets, coins and sparkles."""
    base(sun_rot=(52, 0, -30))
    backdrop()
    kit.leaf_carpet(-40, 40, 14, 40, step=4.5, seed=2)  # leaves only far away
    p = kit.avatar((0, -14.5, 0), yaw=-8, face="grin", arm_r=(-70, 0, 0), arm_l=(-150, 0, -20), **PRO)
    kit.hold(p, "Tool_GalaxyVacuum", rot=(20, 0, 0), scale=1.3)
    kit.place("Alien_Dragon", (-5.4, -13, 0), yaw=25, scale=1.6)
    kit.place("Alien_Unicorn", (4.3, -12.5, 0), yaw=-30, scale=1.6)
    coins((0, -11, 5.5), n=16, spread=(8, 1.5, 3), scale=(0.5, 0.8))
    cam = kit.camera((-5.0, -33, 4.6), (-3.5, -12, 4.2), lens=40)  # subject in the right half
    kit.dof(cam, (0, -14.5, 3), 4.0)


def noob_vs_pro():
    """Two players side by side on one leaf field: noob with a toothbrush vs pro on a giant vacuum."""
    base(sun_rot=(50, 0, -25))
    backdrop()
    thick_leaves(-40, 1, -24, 40, seed=5, drifts=0.5)
    kit.leaf_carpet(1, 40, 10, 40, step=4.5, seed=6)
    p = kit.avatar((-4.2, -14, 0.55), yaw=18, face="wow", arm_r=(-50, 0, 6), **NOOB)
    kit.hold(p, "Tool_Toothbrush", rot=(90, 0, 0), scale=1.3)
    q = kit.avatar((4.2, -14, 0), yaw=-18, face="grin", arm_r=(-80, 0, 0), arm_l=(-150, 0, -25), **PRO)
    kit.hold(q, "Tool_TornadoVac", rot=(10, 0, 0), scale=1.6)
    kit.place("Alien_Phoenix", (7.6, -12, 0), yaw=-35, scale=1.5)
    flying_leaves((-4, -14, 2.5), n=12, spread=(4, 2, 3), seed=7)
    cam = kit.camera((0, -36, 4.4), (0, -12, 4.0), lens=40)
    kit.dof(cam, (0, -14, 3), 4.5)


def hatch():
    """Giant glowing mythic egg on a leaf pile, rare pets around it."""
    base(sun_rot=(55, 0, 20), sky_top="6A4CFF", sky_bot="FF9AD5")
    backdrop(seed=8)
    kit.leaf_carpet(-40, 40, -24, 40, step=4.5, seed=8)
    kit.place("Egg_Cosmic", (0, -7.5, 0.3), yaw=-10, scale=2.6)
    kit.place("Alien_Dragon", (-7.2, -12, 0.3), yaw=40, scale=1.5)
    kit.place("Alien_Kitsune", (7.2, -12, 0.3), yaw=-40, scale=1.5)
    cam = kit.camera((0, -33, 3.2), (0, -9, 5.4), lens=40)


def money():
    """Player rakes a leaf pile and cash coins burst out of it."""
    base(sun_rot=(50, 0, -35))
    backdrop(seed=11)
    thick_leaves(-40, 40, -24, 40, seed=11, drifts=0.35)
    mound((3.5, -9), radius=4.5, height=4, n=26, seed=13)
    p = kit.avatar((-3.2, -14.5, 0.5), yaw=-25, face="grin", arm_r=(-60, 0, 10), arm_l=(-60, 0, -10), **KID)
    kit.hold(p, "Tool_Rake", rot=(70, 0, -20), scale=1.4)
    coins((3.5, -10, 4.5), n=30, spread=(6, 2, 5), scale=(0.55, 0.9))
    flying_leaves((2.5, -11, 3), n=20, spread=(4, 2, 4), seed=12)
    cam = kit.camera((-1.0, -33, 4.0), (0.5, -11, 4.6), lens=40)


def mound(center, radius, height, n, seed, scale=(1.6, 2.2)):
    """A heap of leaf clumps (the game's Clump_Autumn models stacked)."""
    rnd = random.Random(seed)
    for i in range(n):
        a = rnd.uniform(0, math.tau)
        r = rnd.uniform(0, 1) ** 0.7 * radius
        h = max(0.0, height * (1 - r / radius)) * rnd.uniform(0.75, 1.0)
        kit.place(rnd.choice(["Clump_Autumn1", "Clump_Autumn2", "Clump_Autumn3", "Clump_Autumn4"]),
                  (center[0] + math.cos(a) * r, center[1] + math.sin(a) * r * 0.8, h),
                  rot=(rnd.uniform(-25, 25), rnd.uniform(-25, 25), rnd.uniform(0, 360)), scale=rnd.uniform(*scale))


def giant_pile():
    """Tiny player in front of a mountain of leaves."""
    base(sun_rot=(42, 0, -40))
    backdrop(seed=14, near=70)
    kit.leaf_carpet(-50, 50, -20, 60, step=4.5, seed=14)
    rnd = random.Random(15)
    # stack scaled drifts/clumps into a mountain
    for i in range(70):
        a = rnd.uniform(0, math.tau)
        r = rnd.uniform(0, 1) ** 0.7 * 16
        h = max(0.0, 15 - r * 0.95) * rnd.uniform(0.75, 1.0)
        kit.place(rnd.choice(["Clump_Autumn1", "Clump_Autumn2", "Clump_Autumn3", "Clump_Autumn4"]),
                  (math.cos(a) * r, 18 + math.sin(a) * r * 0.7, h), yaw=rnd.uniform(0, 360),
                  rot=(rnd.uniform(-25, 25), rnd.uniform(-25, 25), rnd.uniform(0, 360)), scale=rnd.uniform(2.6, 3.4))
    for i in range(10):
        a = rnd.uniform(0, math.tau)
        kit.place("Drift_Autumn1", (math.cos(a) * 13, 18 + math.sin(a) * 9, 0), yaw=math.degrees(a) + 90, scale=(3, 3, 3))
    p = kit.avatar((0.5, -6, 0.4), yaw=12, face="wow", arm_r=(-20, 0, 25), arm_l=(-150, 0, -25), head=(-10, 0, 0), **KID)
    kit.hold(p, "Tool_Broom", rot=(90, 0, 0), scale=1.1)
    flying_leaves((0, 6, 8), n=30, spread=(14, 6, 10), seed=16, scale=(2.0, 3.5))
    cam = kit.camera((-2.0, -20, 3.0), (0, 10, 9.0), lens=28)


def tools():
    """Upgrade ladder: the same player three times, bigger and with a better tool each step."""
    base(sun_rot=(50, 0, -20))
    backdrop(seed=18)
    kit.leaf_carpet(-40, 40, -24, 40, step=4.5, seed=18, keep=lambda x, y: x < -3 or y > 2)
    steps = [(-8.5, 1.0, NOOB, "Tool_Toothbrush", "wow", (90, 0, 0), 1.3, (-45, 0, 6)),
             (-1.0, 1.25, KID, "Tool_LeafBlower", "smile", (10, 0, 0), 1.2, (-70, 0, 0)),
             (6.5, 1.6, PRO, "Tool_GalaxyVacuum", "grin", (10, 0, 0), 1.3, (-75, 0, 0))]
    for x, sc, outfit, tool, face, rot, ts, arm in steps:
        side = "l" if x > 3 else "r"  # the pro holds it on the side facing the middle
        arms = {"arm_l": arm} if side == "l" else {"arm_r": arm}
        p = kit.avatar((x, -12, 0.45 if x < -3 else 0), yaw=-6 * (x / 8), face=face, scale=sc, **arms, **outfit)
        kit.hold(p, tool, side=side, rot=rot, scale=ts)
    cam = kit.camera((0, -34, 5.0), (0, -11, 5.2), lens=40)


def car():
    """Sweeper cart driving through the leaves, leaving a clean stripe."""
    base(sun_rot=(50, 0, -50))
    backdrop(seed=21)
    # clean lane behind the cart (cart drives toward the camera, -Y)
    kit.leaf_carpet(-40, 40, -24, 40, step=4.5, seed=21, keep=lambda x, y: abs(x) > 3.6 or y < -16)
    import bpy
    kit.place("Vehicle_SweeperCart", (0, -11, 0), yaw=-18, scale=1.25)
    p = kit.avatar((0.3, -10.3, 0.9), yaw=-18, face="grin", leg_r=(-80, 0, 0), leg_l=(-80, 0, 0),
                   arm_r=(-60, 0, 0), arm_l=(-60, 0, 0), scale=0.85, **GIRL)
    flying_leaves((4.5, -13, 0.5), n=10, spread=(1.5, 2, 3), seed=22)
    flying_leaves((-4.5, -13, 0.5), n=10, spread=(1.5, 2, 3), seed=23)
    cam = kit.camera((-13, -26, 3.0), (0, -11, 3.4), lens=40)


def pet_army():
    """Player leading a crowd of pets across the leaves."""
    base(sun_rot=(48, 0, -30))
    backdrop(seed=25)
    kit.leaf_carpet(-40, 40, -24, 40, step=4.5, seed=25)
    p = kit.avatar((0, -13.5, 0.5), yaw=0, face="grin", arm_r=(-150, 0, 15), arm_l=(-20, 0, -15), **KID)
    kit.hold(p, "Tool_LeafBlower", rot=(-60, 0, 0), scale=1.2)
    pets = ["Alien_Dragon", "Alien_Unicorn", "Alien_Kitsune", "Alien_Lion", "Alien_Tiger", "Alien_Panda",
            "Alien_Fox", "Alien_Dog", "Alien_Cat", "Alien_Penguin", "Alien_ArcticWolf", "Alien_Owl", "Alien_Bunny", "Alien_Duck"]
    rnd = random.Random(26)
    i = 0
    for row in range(1, 4):
        n = row * 2 + 1
        for k in range(n):
            if i >= len(pets):
                break
            x = (k - (n - 1) / 2) * 4.2
            y = -13.5 + row * 4.2
            kit.place(pets[i], (x + rnd.uniform(-0.4, 0.4), y, 0.5), yaw=rnd.uniform(-15, 15), scale=1.8)
            i += 1
    cam = kit.camera((0, -29, 7.0), (0, -8, 3.4), lens=36)


SCENES = {f.__name__: f for f in (messy, clean, noob_vs_pro, hatch, money, giant_pile, tools, car, pet_army)}

if __name__ == "__main__":
    args = sys.argv[1:]
    out = args.pop(0)
    if "--preview" in args:
        args.remove("--preview")
        PREVIEW = True
    os.makedirs(out, exist_ok=True)
    for name in args or SCENES:
        SCENES[name]()
        kit.render(os.path.join(out, name + ".png"))
