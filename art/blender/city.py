"""City zone decor in the cartoon style of parkdecor.py (outlined, chunky, bright).

  City_ShopA/B/C/D   rounded shop fronts with scalloped awnings, flower boxes, glass
                     windows and a roof extra (water tank / AC fans that spin /
                     roof garden that sways / chimney that smokes)
  City_BusStop       shelter with rounded roof and glass
  City_HotDog        cart with umbrella and a giant hot dog that turns; steam puffs
  City_Newsstand     kiosk with magazines
  City_TrafficLight  red / yellow / green glow cycle
  City_StreetLamp    curved street lamp with glow
  City_Billboard     billboard with a "sweep" ad and lamps
  City_Statue        golden sweeper hero on a plinth; pigeons walk round it
  City_Bench, City_Hydrant, City_Bin, City_Dumpster   street props
  CityFx_Pigeon      critter
"""
import math
import random

from mathutils import Vector, Matrix

from lib import sphere, cyl, box, torus
from fountain import lathe, ellipse, outlined, paint_faces, place, eye, blob_tube
from parkdecor import (asset, animate, loop, puff, rbox, post, flower, bush_blobs, park_bench, WOOD, WOOD_DARK, WOOD_LIGHT, RED,
                       WHITE, YELLOW, BLUE, PINK, LEAF, LEAF_DARK, LEAF_LIGHT, STONE, STONE_DARK, STONE_LIGHT, FLOWERS)

METAL, METAL_DARK = "8890A0", "3A3F4A"
GLASS = "8ED8FF"
GOLD, GOLD_DARK, GOLD_LIGHT = "FFB52E", "E5841A", "FFE07A"
ORANGE = "FF8A3C"


# ------------------------------------------------------------------ shops

def city_shop(name, wall, awning, roof_kind):
    """16 wide x 10 deep x 12 tall, door and display windows on the front (-Y)."""
    a = asset(name)
    W, D, H = 16, 10, 12
    body = rbox(wall, (0, 0, H / 2), (W, D, H), r=0.35)
    paint_faces(body, lambda c: wall if c.z > 1.0 else STONE_DARK)
    cornice = rbox(STONE_LIGHT, (0, 0, H + 0.3), (W + 0.8, D + 0.8, 0.7), r=0.25)
    band = rbox(STONE_LIGHT, (0, -D / 2 - 0.05, 7.6), (W + 0.3, 0.4, 0.45), r=0.15)
    pavement = rbox(STONE, (0, -D / 2 - 1.1, 0.1), (W + 2, 2.2, 0.2), r=0.06)
    door = rbox("5A3A26", (0, -D / 2 - 0.08, 2.1), (2.4, 0.2, 4.1), r=0.4)
    knob = sphere(YELLOW, loc=(0.8, -D / 2 - 0.25, 2.0), scale=0.13, seg=6, rings=4)
    frames = [rbox(WHITE, (x, -D / 2 - 0.06, 2.7), (5.1, 0.2, 3.7), r=0.2) for x in (-4.8, 4.8)]
    sills = []
    boxes = []
    for x in (-5, 0, 5):
        sills.append(rbox(WHITE, (x, -D / 2 - 0.06, 9.6), (2.8, 0.18, 2.8), r=0.2))
        sills.append(rbox(STONE_LIGHT, (x, -D / 2 - 0.3, 8.1), (3.1, 0.55, 0.22), r=0.08))
        boxes.append(rbox(WOOD, (x, -D / 2 - 0.45, 8.45), (2.7, 0.45, 0.45), r=0.08))
        for k in range(2):
            boxes += flower((x - 0.5 + k * 1.0, -D / 2 - 0.5, 8.85), FLOWERS[(k + int(x)) % len(FLOWERS)], 0.3)
    # scalloped striped awning
    awn = []
    for k in range(8):
        x0 = -W / 2 + W / 16 + k * W / 8
        s = rbox(awning if k % 2 == 0 else WHITE, (x0, -D / 2 - 1.15, 5.15), (W / 8, 2.5, 0.16), r=0.04, rot_x=20)
        awn.append(s)
        awn.append(sphere(awning if k % 2 == 0 else WHITE, loc=(x0, -D / 2 - 2.35, 4.7), scale=(W / 16, 0.12, 0.3), seg=8, rings=4))
    sign = rbox(WHITE, (0, -D / 2 - 0.12, 6.7), (10, 0.25, 1.7), r=0.3)
    signin = rbox(awning, (0, -D / 2 - 0.25, 6.7), (9.4, 0.06, 1.25), r=0.25)
    roof = []
    if roof_kind == "tank":
        tank = lathe(WOOD, [(0.0, H + 0.6), (1.7, H + 0.6), (1.7, H + 3.8), (0.0, H + 3.8)], n=12)
        paint_faces(tank, lambda c: WOOD_DARK if int((c.z - H) / 0.8) % 2 else WOOD)
        lid = lathe(WOOD_DARK, [(0.0, H + 3.8), (1.95, H + 3.8), (0.0, H + 5.0)], n=12, smooth=False)
        for o in (tank, lid):
            place(o, loc=(4, 2, 0))
        roof += outlined([tank, lid], 0.05) + [post(METAL_DARK, (4 + dx, 2 + dy, H + 0.6), (4 + dx, 2 + dy, H - 0.1), r=0.1, seg=5) for dx in (-1, 1) for dy in (-1, 1)]
    elif roof_kind == "ac":
        for i, x in enumerate((-4, 2)):
            unit = rbox(STONE_LIGHT, (x, 1.5, H + 1.4), (2.6, 2.0, 1.4), r=0.2)
            roof += outlined([unit], 0.04)
            fan = []
            for k in range(4):
                t = math.tau * k / 4
                fan.append(sphere(METAL, loc=(x + math.cos(t) * 0.3, 0.38, H + 1.4 + math.sin(t) * 0.3), scale=(0.3, 0.04, 0.12), rot=(0, -math.degrees(t), 0), seg=6, rings=3))
            roof.append(torus(METAL_DARK, loc=(x, 0.42, H + 1.4), R=0.62, r=0.06, rot=(90, 0, 0), seg=14, mseg=4))
            a.part(f"Fan{i + 1}", fan, joint=(x, 0.38, H + 1.4))
            animate(a, f"Fan{i + 1}", "spin", 0, 1.5 + i * 0.4, "z")
    elif roof_kind == "garden":
        planter = rbox(WOOD, (0, 1, H + 0.85), (10, 4, 0.5), r=0.12)
        roof += outlined([planter], 0.04)
        plants = []
        for x in range(-4, 5, 2):
            plants += bush_blobs(x, 1, H + 1.0, 0.7, (LEAF, LEAF_DARK, LEAF_LIGHT), x + 9, n=2)
            plants += flower((x + 0.3, 0.3, H + 2.3), FLOWERS[(x + 4) % len(FLOWERS)], 0.35)
        a.part("Garden", plants, joint=(0, 1, H + 1.0))
        animate(a, "Garden", "sway", 3, 0.4, "z")
    else:
        chim = rbox("A0503C", (-5, 2, H + 2.0), (1.7, 1.7, 3.4), r=0.15)
        paint_faces(chim, lambda c: "8A3E2E" if int(c.z / 0.5) % 2 else "A0503C")
        cap = rbox(STONE_DARK, (-5, 2, H + 3.8), (2.1, 2.1, 0.3), r=0.08)
        roof += outlined([chim, cap], 0.04)
        puff(a, (-5, 2, H + 4.1), rate=0.8, size=1.2, tint="smoke")
    a.part("Body", outlined([body, cornice, door, sign] + frames, 0.06) + [band, pavement, knob, signin] + sills + boxes + awn + roof, collide=True)
    a.part("Windows_Glass", [rbox(GLASS, (x, -D / 2 - 0.18, 2.7), (4.4, 0.06, 3.1), r=0.15) for x in (-4.8, 4.8)] +
           [rbox(GLASS, (x, -D / 2 - 0.18, 9.6), (2.2, 0.06, 2.2), r=0.15) for x in (-5, 0, 5)], material="Glass")
    a.extra["sign"] = [0, 6.7, -D / 2 - 0.4]
    return a


def city_busstop(name="City_BusStop"):
    a = asset(name)
    slab = rbox(STONE, (0, 0, 0.1), (8, 4, 0.2), r=0.06)
    poles = [post(METAL_DARK, (x, y, 0.2), (x, y, 3.9), r=0.12, seg=6) for x in (-3.5, 3.5) for y in (1.2, -0.9)]
    roof = rbox(BLUE, (0, 0.15, 4.05), (8.2, 3.2, 0.35), r=0.17)
    paint_faces(roof, lambda c: WHITE if c.z < 3.95 else BLUE)
    bench = [rbox(WOOD, (0, 0.8, 1.0), (5, 0.8, 0.16), r=0.06), rbox(WOOD_LIGHT, (0, 1.12, 1.5), (5, 0.12, 0.6), r=0.05)] + \
            [post(METAL_DARK, (x, 0.8, 0.2), (x, 0.8, 0.95), r=0.07, seg=5) for x in (-2, 2)]
    sign = [post(METAL_DARK, (4.6, -1.5, 0), (4.6, -1.5, 4.8), r=0.08, seg=6),
            cyl(BLUE, loc=(4.6, -1.5, 4.6), r=0.65, h=0.14, rot=(90, 0, 0), verts=16), cyl(WHITE, loc=(4.6, -1.58, 4.6), r=0.48, h=0.02, rot=(90, 0, 0), verts=16),
            rbox(BLUE, (4.6, -1.6, 4.6), (0.5, 0.03, 0.18), r=0.02)]
    poster = rbox(YELLOW, (-3.62, 0.2, 2.3), (0.06, 1.6, 2.2), r=0.1)
    a.part("Body", outlined([slab, roof] + bench[:2], 0.04) + poles + bench[2:] + sign + [poster], collide=True)
    a.part("Panel_Glass", [rbox(GLASS, (0, 1.25, 2.2), (6.8, 0.06, 2.8), r=0.1), rbox(GLASS, (-3.5, 0.15, 2.2), (0.06, 2.0, 2.8), r=0.1)], material="Glass")
    return a


def city_hotdog(name="City_HotDog"):
    a = asset(name)
    cart = rbox(WHITE, (0, 0, 1.6), (4, 2.2, 1.8), r=0.3)
    paint_faces(cart, lambda c: RED if 1.3 < c.z < 1.9 else WHITE)
    top = rbox(METAL, (0, 0, 2.55), (4.2, 2.4, 0.12), r=0.05)
    wheels = []
    for x in (-1.4, 1.4):
        for y in (-1.18, 1.18):
            wheels.append(cyl("2A2A2A", loc=(x, y, 0.5), r=0.5, h=0.22, rot=(90, 0, 0), verts=14))
            wheels.append(cyl(METAL, loc=(x, y * 1.03, 0.5), r=0.2, h=0.22, rot=(90, 0, 0), verts=8))
    handle = post(METAL, (2, 0, 2.0), (3.0, 0, 2.3), r=0.07, seg=6)
    pole = post(METAL, (0, 0, 2.6), (0, 0, 5.4), r=0.07, seg=6)
    umb = lathe(RED, [(0.0, 5.9), (2.7, 5.1), (2.7, 5.0), (0.0, 5.8)], n=16, smooth=False, shape=lambda t, r, z: (r * (1 + 0.05 * math.cos(t * 8)), z))
    paint_faces(umb, lambda c: YELLOW if int((math.atan2(c.y, c.x) + 4) * 8 / math.pi) % 2 else RED)
    bottles = [cyl(RED, loc=(-1.2, -0.4, 2.85), r=0.15, h=0.5, verts=8), cyl(YELLOW, loc=(-0.8, -0.4, 2.85), r=0.15, h=0.5, verts=8)]
    a.part("Body", outlined([cart, umb], 0.05) + [top, handle, pole] + wheels + bottles, collide=True)
    hd = [blob_tube("E8B05A", [(-1.0, 0, 6.5), (1.0, 0, 6.5)], lambda u: 0.42, seg=10),
          blob_tube("C0504A", [(-1.35, 0, 6.72), (1.35, 0, 6.72)], lambda u: 0.25, seg=10),
          blob_tube(YELLOW, [(-1.0 + 0.25 * k, 0, 6.98 + 0.07 * (k % 2)) for k in range(9)], lambda u: 0.07, seg=5)]
    face = [eye((sx * 0.3, -0.33, 6.75), 0.12) for sx in (-1, 1)]
    a.part("HotDog", outlined(hd[:2], 0.04) + hd[2:] + face, joint=(0, 0, 6.5))
    animate(a, "HotDog", "spin", 0, 0.15, "y")
    puff(a, (-0.6, 0.3, 2.7), rate=1.2, size=0.6, tint="steam")
    return a


def city_newsstand(name="City_Newsstand"):
    a = asset(name)
    rnd = random.Random(3)
    kiosk = rbox("3F8F4E", (0, 0, 2.0), (4.4, 3.4, 4.0), r=0.25)
    roof = rbox("2F6F3C", (0, 0, 4.25), (5.0, 4.0, 0.45), r=0.2)
    awn = rbox("2F6F3C", (0, -2.2, 3.6), (5.0, 1.3, 0.16), r=0.06, rot_x=-12)
    shelf = rbox(WOOD_LIGHT, (0, -1.9, 1.6), (4.0, 0.7, 0.16), r=0.05)
    mags = [rbox(rnd.choice((RED, YELLOW, BLUE, PINK, WHITE)), (-1.6 + k * 0.64, -1.9, 1.75), (0.55, 0.45, 0.07), r=0.02, rot_z=rnd.uniform(-8, 8)) for k in range(6)]
    covers = [rbox(rnd.choice((RED, YELLOW, BLUE, WHITE)), (-1.6 + k * 0.8, -1.75, 2.8), (0.6, 0.05, 0.8), r=0.03) for k in range(5)]
    sign = [rbox(WHITE, (0, -2.1, 4.75), (3.0, 0.15, 0.7), r=0.15), rbox(RED, (0, -2.2, 4.75), (2.6, 0.04, 0.45), r=0.1)]
    a.part("Body", outlined([kiosk, roof, awn], 0.05) + [shelf] + mags + covers + sign, collide=True)
    return a


def city_trafficlight(name="City_TrafficLight"):
    a = asset(name)
    pole = lathe(METAL_DARK, [(0.0, 0.0), (0.45, 0.0), (0.4, 0.4), (0.17, 0.6), (0.16, 8.0), (0.0, 8.1)], n=10)
    arm = post(METAL_DARK, (0, 0, 7.6), (0, -3.6, 7.6), r=0.13, seg=6)
    box_ = rbox(YELLOW, (0, -3.6, 6.6), (1.0, 0.8, 2.8), r=0.3)
    visors = [lathe("2A2A2A", [(0.36, 0.0), (0.46, 0.0), (0.46, 0.4), (0.36, 0.4)], n=10, t0=0, t1=math.pi, smooth=False) for _ in range(3)]
    for v, z in zip(visors, (7.45, 6.6, 5.75)):
        place(v, rot_x=-90, loc=(0, -4.0, z))
    button = rbox(YELLOW, (0, -0.25, 3.5), (0.4, 0.3, 0.55), r=0.08)
    a.part("Body", outlined([pole, box_], 0.05) + [arm, button] + visors, collide=True)
    for nm, col, z, ph, on in (("Red_Glow", "FF4A3C", 7.45, 0.0, 0.45), ("Yellow_Glow", "FFD23A", 6.6, 0.45, 0.12), ("Green_Glow", "4AE07A", 5.75, 0.57, 0.43)):
        a.part(nm, [cyl(col, loc=(0, -4.02, z), r=0.33, h=0.06, rot=(90, 0, 0), verts=12)], glow=col)
        animate(a, nm, "blink", on, 0.1, "y", phase=ph)
    return a


def city_streetlamp(name="City_StreetLamp"):
    a = asset(name)
    pole = lathe(METAL, [(0.0, 0.0), (0.45, 0.0), (0.4, 0.5), (0.18, 0.8), (0.14, 8.6), (0.0, 8.7)], n=10)
    neck = blob_tube(METAL, [(0, 0, 8.4), (0, -0.3, 9.2), (0, -1.0, 9.6), (0, -1.8, 9.5)], lambda u: 0.12, seg=6)
    shade = lathe(METAL_DARK, [(0.0, 9.75), (0.8, 9.2), (0.75, 9.1), (0.0, 9.6)], n=12, smooth=False)
    place(shade, loc=(0, -2.0, 0))
    curls = [blob_tube(METAL, [(0, 0, 7.6), (0, -0.4, 7.7), (0, -0.6, 8.1), (0, -0.4, 8.4)], lambda u: 0.05, seg=5)]
    a.part("Body", outlined([pole, shade], 0.04) + [neck] + curls, collide=True)
    bulb = sphere("FFF4CC", loc=(0, -2.0, 9.1), scale=(0.45, 0.45, 0.3), seg=10, rings=6)
    a.part("Lamp_Glow", [bulb], glow="FFF4CC")
    return a


def city_billboard(name="City_Billboard"):
    a = asset(name)
    legs = [post(METAL_DARK, (x, 0.5, 0), (x, 0.5, 10), r=0.3, seg=8) for x in (-5, 5)]
    frame = rbox(METAL_DARK, (0, 0.3, 12.5), (16, 0.5, 6), r=0.25)
    panel = rbox("8ED8FF", (0, 0.0, 12.5), (15.2, 0.12, 5.3), r=0.2)
    paint_faces(panel, lambda c: LEAF if c.z < 10.8 else "8ED8FF")
    sun = cyl(YELLOW, loc=(-5, -0.12, 13.6), r=1.2, h=0.05, rot=(90, 0, 0), verts=16)
    rays = [rbox(YELLOW, (-5 + math.cos(t) * 1.7, -0.12, 13.6 + math.sin(t) * 1.7), (0.5, 0.04, 0.2), r=0.05, rot_y=-math.degrees(t)) for t in (math.tau * k / 8 for k in range(8))]
    face = [sphere("1B1530", loc=(-5 + sx * 0.4, -0.16, 13.8), scale=(0.1, 0.03, 0.14), seg=6, rings=4) for sx in (-1, 1)]
    broom = [rbox(WOOD, (2.0, -0.14, 12.4), (0.35, 0.06, 4.6), r=0.1, rot_y=35), rbox(YELLOW, (3.5, -0.14, 10.6), (1.6, 0.06, 1.4), r=0.2, rot_y=35)]
    leaves = [sphere(c, loc=(x, -0.15, z), scale=(0.5, 0.05, 0.3), rot=(0, k * 40, 0), seg=8, rings=4) for k, (x, z, c) in enumerate(((5.2, 11.2, "F0802A"), (6.2, 11.6, RED), (5.6, 12.2, YELLOW)))]
    walk = [rbox(METAL, (0, -0.8, 9.4), (15, 1.2, 0.15), r=0.05)] + [post(METAL, (x, -0.8, 9.5), (x, -1.4, 10.0), r=0.06, seg=5) for x in (-5, 0, 5)]
    a.part("Body", outlined(legs + [frame], 0.05) + [panel, sun] + rays + face + broom + leaves + walk, collide=True)
    a.part("Lamps_Glow", [sphere("FFF4CC", loc=(x, -1.45, 10.05), scale=(0.3, 0.2, 0.15), seg=8, rings=4) for x in (-5, 0, 5)], glow="FFF4CC")
    return a


def city_statue(name="City_Statue"):
    """A chunky golden sweeper with a broom on a plinth, the city's hero."""
    a = asset(name)
    base = lathe(STONE, [(0.0, 0.0), (4.6, 0.0), (4.6, 0.5), (4.3, 0.7), (0.0, 0.7)], n=8, smooth=False)
    place(base, rot_z=22.5)
    plinth = rbox(STONE_LIGHT, (0, 0, 2.4), (4, 4, 3.4), r=0.3)
    capb = rbox(STONE, (0, 0, 4.2), (4.6, 4.6, 0.45), r=0.15)
    plaque = rbox(GOLD_DARK, (0, -2.05, 2.4), (2.6, 0.08, 1.0), r=0.15)
    z0 = 4.4
    legs = [blob_tube(GOLD, [(sx * 0.45, 0, z0), (sx * 0.45, 0, z0 + 1.9)], lambda u: 0.42, seg=10) for sx in (-1, 1)]
    shoes = [sphere(GOLD_DARK, loc=(sx * 0.45, -0.2, z0 + 0.15), scale=(0.45, 0.6, 0.25), seg=10, rings=6) for sx in (-1, 1)]
    body = sphere(GOLD, loc=(0, 0, z0 + 3.0), scale=(1.05, 0.7, 1.25), seg=16, rings=10)
    head = sphere(GOLD, loc=(0, 0, z0 + 4.75), scale=0.8, seg=16, rings=10)
    cap = [sphere(GOLD_DARK, loc=(0, 0.05, z0 + 5.2), scale=(0.82, 0.82, 0.45), seg=14, rings=8),
           sphere(GOLD_DARK, loc=(0, -0.7, z0 + 5.05), scale=(0.55, 0.45, 0.08), seg=10, rings=5)]
    eyes = [sphere(GOLD_LIGHT, loc=(sx * 0.28, -0.72, z0 + 4.8), scale=(0.12, 0.05, 0.17), seg=8, rings=5) for sx in (-1, 1)]
    smile = torus(GOLD_DARK, loc=(0, -0.75, z0 + 4.45), R=0.25, r=0.05, rot=(90, 0, 0), seg=12, mseg=4)
    arms = [blob_tube(GOLD, [(1.0, 0, z0 + 3.6), (1.6, -0.2, z0 + 4.4), (2.0, -0.2, z0 + 5.3)], lambda u: 0.3, seg=8),
            blob_tube(GOLD, [(-1.0, 0, z0 + 3.6), (-1.3, -0.6, z0 + 2.9), (-0.9, -0.9, z0 + 2.6)], lambda u: 0.3, seg=8)]
    broom = [post(GOLD_DARK, (1.4, -0.2, z0 + 3.5), (3.2, -0.2, z0 + 7.6), r=0.12, seg=6),
             rbox(GOLD_DARK, (3.5, -0.2, z0 + 8.2), (1.7, 0.45, 1.2), r=0.2, rot_y=-24)]
    ring = []
    for k in range(8):
        t = math.radians(k * 45 + 22.5)
        ring += bush_blobs(math.cos(t) * 3.7, math.sin(t) * 3.7, 0.3, 0.5, (LEAF, LEAF_DARK), k, n=2)
        ring += flower((math.cos(t) * 3.7, math.sin(t) * 3.7, 1.25), FLOWERS[k % 5], 0.3)
    a.part("Body", outlined([base, plinth, capb, body, head] + legs + arms, 0.05) + [plaque, smile] + shoes + cap + eyes + broom + ring, collide=True)
    for i in range(3):
        loop(a, "CityFx_Pigeon", (0, 0, 0.0), 5.6, 5.6, 0.25 - i * 0.04, phase=i * 2.0, bob=0.0, hop=0.12)
    return a


def city_hydrant(name="City_Hydrant"):
    a = asset(name)
    body = lathe(RED, [(0.0, 0.0), (0.55, 0.0), (0.55, 0.2), (0.4, 0.3), (0.4, 1.3), (0.5, 1.4), (0.45, 1.6), (0.2, 1.9), (0.0, 1.95)], n=12)
    caps = [cyl(YELLOW, loc=(sx * 0.5, 0, 1.0), r=0.18, h=0.3, rot=(0, 90, 0), verts=8) for sx in (-1, 1)] + [cyl(YELLOW, loc=(0, -0.5, 1.0), r=0.22, h=0.25, rot=(90, 0, 0), verts=8)]
    knob = sphere(YELLOW, loc=(0, 0, 2.0), scale=0.14, seg=6, rings=4)
    a.part("Body", outlined([body], 0.04) + caps + [knob], collide=True)
    return a


def city_bin(name="City_Bin"):
    a = asset(name)
    can = lathe("3F8F4E", [(0.0, 0.0), (0.7, 0.0), (0.8, 1.9), (0.0, 1.9)], n=14)
    paint_faces(can, lambda c: "2F6F3C" if int(math.atan2(c.y, c.x) * 14 / math.pi) % 2 else "3F8F4E")
    lid = lathe("2F6F3C", [(0.0, 1.9), (0.9, 1.9), (0.85, 2.1), (0.3, 2.3), (0.0, 2.35)], n=14)
    leaf = [sphere(c, loc=(x, y, 2.05), scale=(0.25, 0.15, 0.05), rot=(0, 20, k * 50), seg=6, rings=3) for k, (x, y, c) in enumerate(((0.4, 0.3, ORANGE), (-0.3, 0.5, YELLOW)))]
    a.part("Body", outlined([can, lid], 0.04) + leaf, collide=True)
    return a


def city_dumpster(name="City_Dumpster"):
    a = asset(name)
    body = rbox("3F7FBF", (0, 0, 1.4), (4.4, 2.6, 2.4), r=0.2)
    lids = [rbox("2F5F9A", (sx * 1.1, 0.1, 2.75), (2.1, 2.7, 0.2), r=0.08, rot_x=-6) for sx in (-1, 1)]
    wheels = [cyl("2A2A2A", loc=(x, y, 0.25), r=0.25, h=0.2, rot=(90, 0, 0), verts=10) for x in (-1.8, 1.8) for y in (-1.0, 1.0)]
    stripe = rbox(YELLOW, (0, -1.32, 1.6), (3.8, 0.04, 0.3), r=0.05)
    bag = sphere("3A3F4A", loc=(1.2, -0.2, 3.0), scale=(0.6, 0.5, 0.45), seg=10, rings=6)
    a.part("Body", outlined([body] + lids, 0.05) + wheels + [stripe, bag], collide=True)
    return a


def pigeon():
    a = asset("CityFx_Pigeon")
    body = sphere("9AA0B4", loc=(0, 0.05, 0.4), scale=(0.28, 0.42, 0.3), seg=12, rings=8)
    head = sphere("7A8096", loc=(0, -0.35, 0.72), scale=0.2, seg=10, rings=6)
    neck = sphere("6FB59A", loc=(0, -0.25, 0.55), scale=(0.2, 0.18, 0.15), seg=8, rings=5)
    beak = sphere(ORANGE, loc=(0, -0.55, 0.7), scale=(0.05, 0.1, 0.04), seg=6, rings=3)
    tail = sphere("6E7488", loc=(0, 0.5, 0.42), scale=(0.15, 0.25, 0.06), rot=(15, 0, 0), seg=8, rings=4)
    legs = [post(ORANGE, (sx * 0.1, 0.05, 0.15), (sx * 0.1, 0.05, 0.0), r=0.03, seg=4) for sx in (-1, 1)]
    eyes = [eye((sx * 0.1, -0.48, 0.78), 0.05, look=(sx, -1, 0)) for sx in (-1, 1)]
    a.part("Body", outlined([body, head], 0.025) + [neck, beak, tail] + legs + eyes)
    return a


ALL = {
    "City_ShopA": lambda: city_shop("City_ShopA", "E8A07A", "F0544A", "tank"),
    "City_ShopB": lambda: city_shop("City_ShopB", "8EC8E8", "2F6FC0", "ac"),
    "City_ShopC": lambda: city_shop("City_ShopC", "F2D98A", "3F9A3A", "garden"),
    "City_ShopD": lambda: city_shop("City_ShopD", "C8A0E0", "8A4AC0", "chimney"),
    "City_BusStop": city_busstop,
    "City_HotDog": city_hotdog,
    "City_Newsstand": city_newsstand,
    "City_TrafficLight": city_trafficlight,
    "City_StreetLamp": city_streetlamp,
    "City_Billboard": city_billboard,
    "City_Statue": city_statue,
    "City_Bench": lambda: park_bench("City_Bench"),
    "City_Hydrant": city_hydrant,
    "City_Bin": city_bin,
    "City_Dumpster": city_dumpster,
    "CityFx_Pigeon": pigeon,
}
