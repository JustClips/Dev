"""The 19 alien pets. Each is a small rig: Body is the root part, other parts hang off it
with a joint point (Motor6D pivot). Standard part names are shared by every alien so one
set of animations drives them all:

  Body, Head, LegFL, LegFR, LegBL, LegBR, LegL, LegR, ArmL, ArmR,
  EarL, EarR, Tail, WingL, WingR, Tent1..Tent4

L is the alien's left (+X in Blender, -X in Roblox). Missing parts are simply not animated.
"""
import math
from mathutils import Vector
from lib import (Asset, use, sphere, ico, box, cyl, cone, torus, capsule, tube, eye, arc, join,
                 deform, noise_deform)

DARK = "1B1530"
WHITE = "FFFFFF"
PINK = "FF8FB8"
BLUSH = "FF9EC4"
IRIS = "5A48C8"


def V(*a):
    return Vector(a)


def shade(h, k):
    """Lighten (k>0) or darken (k<0) a hex colour."""
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) for i in (0, 2, 4)]
    if k >= 0:
        c = [round(x + (255 - x) * k) for x in c]
    else:
        c = [round(x * (1 + k)) for x in c]
    return "".join(f"{x:02X}" for x in c)


def face(center, r, eye_size=0.3, spread=0.4, up=0.1, mouth=True, cheeks=True, n_eyes=2,
         pupil=DARK, fwd=-1.0, smile_color=DARK, iris="AUTO", tongue=True, lashes=False, on=None):
    """Cute face on a round head: big sparkly eyes, a smile with a little tongue, blush.
    `on` = the head/body mesh: features are then placed on its actual surface."""
    c = Vector(center)
    spread *= 0.8
    pieces = []
    if iris == "AUTO":
        iris = IRIS

    def surf(d, k):
        if on is not None:
            hit, loc, _, _ = on.ray_cast(c + d * r * 6, -d)
            if hit:
                return loc + d * r * (k - 1)
        return c + d * r * k
    sides = [-1, 1] if n_eyes == 2 else ([0] if n_eyes == 1 else [-1, 0, 1])
    for s in sides:
        d = V(s * spread, fwd, up + (0.18 if n_eyes == 3 and s == 0 else 0)).normalized()
        look = (d + V(0, fwd * 2.5, 0)).normalized()
        size = r * eye_size * (1.15 if n_eyes == 1 else 1)
        pos = surf(d, 0.9)
        pieces.append(eye(pos, size, look=look, pupil=pupil, iris=iris))
        if lashes and s != 0:
            for k in (0, 1):
                lash = capsule(DARK, pos + V(s * size * (0.55 + k * 0.25), 0, size * (0.85 - k * 0.2)),
                               pos + V(s * size * (0.85 + k * 0.3), 0, size * (1.15 - k * 0.15)), size * 0.07, seg=6)
                pieces.append(lash)
    if mouth:
        d = V(0, fwd, up - 0.42).normalized()
        m = surf(d, 0.99)
        pieces.append(arc(smile_color, m, r * 0.13, r * 0.028, keep="below"))
        if tongue:
            pieces.append(sphere("FF6F91", loc=m + V(0, fwd * r * 0.01, -r * 0.1), scale=(r * 0.07, r * 0.035, r * 0.05), seg=10, rings=6))
    if cheeks:
        for s in (-1, 1):
            d = V(s * (spread + 0.26), fwd, up - 0.26).normalized()
            pieces.append(sphere(BLUSH, loc=surf(d, 0.97), scale=(r * 0.15, r * 0.045, r * 0.09), seg=12, rings=6))
    return pieces


def stub_leg(a, col, x, y, top, length, r, name, joint=None, foot=None):
    """A short rounded leg hanging from (x, y, top) down `length`."""
    p = [capsule(col, (x, y, top), (x, y, top - length + r), r)]
    if foot:
        p.append(sphere(foot, loc=(x, y - r * 0.3, top - length + r * 0.6), scale=(r * 1.15, r * 1.4, r * 0.7)))
    a.part(name, p, parent="Body", joint=joint or (x, y, top))


def antenna(a, col, tip, base, top, name, parent="Head", glow=None, r=0.06, ball=0.16):
    p = [tube(col, [base, ((base[0] + top[0]) / 2 * 1.15, (base[1] + top[1]) / 2, (base[2] + top[2]) / 2 + 0.05), top], r)]
    p.append(sphere(tip, loc=top, scale=ball))
    a.part(name, p, parent=parent, joint=base, glow=glow)


# ---------------------------------------------------------------------------- aliens


def blip():
    a = Asset("Alien_Blip", "alien")
    use(a)
    g, belly = "8FE38F", "C9F5C0"
    body = sphere(g, loc=(0, 0, 0.62), scale=(0.78, 0.72, 0.62))
    deform(body, lambda v: Vector((v.x * (1 + max(0, 0.6 - v.z) * 0.35), v.y * (1 + max(0, 0.6 - v.z) * 0.35), max(v.z, 0.04))))
    b2 = sphere(belly, loc=(0, -0.42, 0.42), scale=(0.45, 0.25, 0.32))
    spots = [sphere(shade(g, 0.35), loc=(x, y, z), scale=(0.11, 0.11, 0.06), rot=(rx, ry, 0)) for x, y, z, rx, ry in
             ((0.55, 0.25, 0.95, -20, 40), (-0.5, 0.35, 0.9, -25, -40), (0.1, 0.5, 1.12, -45, 5), (0.68, -0.1, 0.62, 0, 75))]
    feet = [sphere(shade(g, -0.15), loc=(s * 0.35, -0.45, 0.07), scale=(0.17, 0.22, 0.09)) for s in (-1, 1)]
    a.part("Body", [body, b2] + spots + feet + face((0, 0, 0.72), 0.7, eye_size=0.27, spread=0.36, up=0.12, iris="2FA84F", on=body))
    for s, n in ((1, "EarL"), (-1, "EarR")):
        antenna(a, shade(g, -0.2), "FFF27A", (s * 0.25, 0.05, 1.18), (s * 0.45, 0.1, 1.62), n, parent="Body", glow="FFF27A")
    return a


def moon_mite():
    a = Asset("Alien_MoonMite", "alien")
    use(a)
    c, spot = "C8C8D7", "8E8EA8"
    shell = sphere(c, loc=(0, 0.1, 0.62), scale=(0.62, 0.7, 0.45))
    spots = [sphere(spot, loc=(x, y, z), scale=0.12) for x, y, z in ((0.25, 0.2, 1.0), (-0.3, 0.35, 0.95), (0.05, 0.5, 0.9), (-0.1, -0.05, 1.04))]
    a.part("Body", [shell] + spots)
    head = sphere(shade(c, 0.25), loc=(0, -0.55, 0.62), scale=0.42)
    a.part("Head", [head] + face((0, -0.55, 0.62), 0.42, eye_size=0.36, spread=0.42, up=0.18, cheeks=False, iris="3A8FD8", on=head), parent="Body", joint=(0, -0.38, 0.62))
    for s, n in ((1, "EarL"), (-1, "EarR")):
        antenna(a, "6E6E88", "9EF0FF", (s * 0.15, -0.72, 0.95), (s * 0.4, -0.95, 1.35), n, glow="9EF0FF", r=0.04, ball=0.1)
    for (x, y, n) in ((0.45, -0.2, "LegFL"), (-0.45, -0.2, "LegFR"), (0.45, 0.4, "LegBL"), (-0.45, 0.4, "LegBR")):
        p = [tube("6E6E88", [(x * 0.8, y, 0.55), (x * 1.35, y, 0.45), (x * 1.45, y, 0.05)], 0.07)]
        a.part(n, p, parent="Body", joint=(x * 0.8, y, 0.55))
    return a


def dusty():
    a = Asset("Alien_Dusty", "alien")
    use(a)
    c, inner = "DCC8A0", "F5D9C8"
    fluff = ico(c, loc=(0, 0, 0.85), scale=0.72, sub=3, smooth=True)
    noise_deform(fluff, 0.09, seed=3, freq=3.5)
    puffs = [ico(shade(c, 0.12), loc=V(math.cos(t) * 0.55, math.sin(t) * 0.5, 0.85 + math.sin(t * 3) * 0.2), scale=0.28, sub=2, smooth=True)
             for t in [i * math.pi / 3 for i in range(6)]]
    a.part("Body", [fluff] + puffs + face((0, 0, 0.9), 0.72, eye_size=0.28, spread=0.36, up=0.05, iris="9A6A3A", on=fluff))
    for s, n in ((1, "EarL"), (-1, "EarR")):
        ear = sphere(c, loc=(s * 0.32, 0.05, 1.75), scale=(0.16, 0.1, 0.48), rot=(0, s * -12, 0))
        inn = sphere(inner, loc=(s * 0.32, -0.04, 1.75), scale=(0.1, 0.05, 0.36), rot=(0, s * -12, 0))
        a.part(n, [ear, inn], parent="Body", joint=(s * 0.28, 0.05, 1.35))
    for s, n in ((1, "LegL"), (-1, "LegR")):
        foot = sphere(shade(c, -0.15), loc=(s * 0.3, -0.12, 0.12), scale=(0.2, 0.3, 0.13))
        a.part(n, [foot], parent="Body", joint=(s * 0.3, 0, 0.3))
    return a


def glorp():
    a = Asset("Alien_Glorp", "alien")
    use(a)
    g = "6EE65A"
    body = sphere(g, loc=(0, 0, 0.85), scale=(0.8, 0.75, 0.85))
    deform(body, lambda v: Vector((v.x * (1 + max(0, 0.5 - v.z) * 0.5), v.y * (1 + max(0, 0.5 - v.z) * 0.5), max(v.z, 0.04))))
    drips = [sphere(g, loc=(math.cos(t) * 0.8, math.sin(t) * 0.75, 0.12), scale=(0.18, 0.18, 0.14)) for t in [i * math.pi / 4 + 0.3 for i in range(8)]]
    mouth = sphere("2A6E22", loc=(0, -0.76, 0.6), scale=(0.28, 0.08, 0.16))
    tongue = sphere("FF7A9A", loc=(0, -0.78, 0.52), scale=(0.14, 0.05, 0.07))
    a.part("Body", [body, mouth, tongue] + drips + [eye((0, -0.68, 1.12), 0.24, look=(0, -1, 0.1))])
    for s, n in ((1, "EarL"), (-1, "EarR")):
        stalk = tube(shade(g, -0.15), [(s * 0.35, 0, 1.45), (s * 0.55, -0.05, 1.85), (s * 0.6, -0.1, 2.05)], 0.08)
        ball = eye((s * 0.6, -0.12, 2.12), 0.2, look=(s * 0.2, -1, 0))
        a.part(n, [stalk, ball], parent="Body", joint=(s * 0.35, 0, 1.45))
    return a


def zib():
    a = Asset("Alien_Zib", "alien")
    use(a)
    c, suit = "5ADCC8", "3A4A7A"
    torso = sphere(suit, loc=(0, 0, 0.75), scale=(0.34, 0.28, 0.4))
    belt = torus("FFD24A", loc=(0, 0, 0.6), R=0.31, r=0.05, rot=(0, 0, 0))
    a.part("Body", [torso, belt])
    head = sphere(c, loc=(0, 0, 1.55), scale=(0.62, 0.55, 0.52))
    deform(head, lambda v: Vector((v.x * (1 - max(0, 1.45 - v.z) * 0.6), v.y, v.z)))
    eyes = []
    for s in (-1, 1):
        e = sphere(DARK, loc=(s * 0.25, -0.44, 1.55), scale=(0.18, 0.08, 0.26), rot=(0, s * 25, 0))
        sh = sphere(WHITE, loc=(s * 0.2, -0.5, 1.65), scale=0.05)
        eyes += [e, sh]
    smile = join([arc(DARK, (0, -0.5, 1.3), 0.08, 0.02),
                  sphere(BLUSH, loc=(0.36, -0.38, 1.36), scale=(0.08, 0.03, 0.05)),
                  sphere(BLUSH, loc=(-0.36, -0.38, 1.36), scale=(0.08, 0.03, 0.05))], "smile")
    a.part("Head", [head, smile] + eyes, parent="Body", joint=(0, 0, 1.1))
    for s, n in ((1, "EarL"), (-1, "EarR")):
        antenna(a, shade(c, -0.25), "FF5AD2", (s * 0.18, 0, 2.0), (s * 0.42, 0.1, 2.45), n, glow="FF5AD2")
    for s, n in ((1, "ArmL"), (-1, "ArmR")):
        arm = capsule(c, (s * 0.36, 0, 0.98), (s * 0.5, -0.05, 0.6), 0.09)
        hand = sphere(c, loc=(s * 0.52, -0.06, 0.55), scale=0.12)
        a.part(n, [arm, hand], parent="Body", joint=(s * 0.34, 0, 1.0))
    for s, n in ((1, "LegL"), (-1, "LegR")):
        leg = capsule(suit, (s * 0.16, 0, 0.45), (s * 0.18, 0, 0.18), 0.1)
        boot = sphere("E8E8F0", loc=(s * 0.18, -0.06, 0.1), scale=(0.13, 0.18, 0.1))
        a.part(n, [leg, boot], parent="Body", joint=(s * 0.16, 0, 0.45))
    return a


def crater_crab():
    a = Asset("Alien_CraterCrab", "alien")
    use(a)
    c, belly = "F0785A", "FFC8A0"
    shell = sphere(c, loc=(0, 0, 0.75), scale=(0.95, 0.7, 0.45))
    deform(shell, lambda v: Vector((v.x, v.y, max(v.z, 0.55 + (v.z - 0.55) * 0.3) if v.z < 0.55 else v.z)))
    b = sphere(belly, loc=(0, -0.05, 0.55), scale=(0.8, 0.6, 0.22))
    spikes = [cone(shade(c, -0.2), loc=(x, 0.2, 1.15), r=0.1, h=0.25) for x in (-0.45, 0, 0.45)]
    mouth = join([arc(DARK, (0, -0.68, 0.7), 0.12, 0.03), sphere("FF6F91", loc=(0, -0.69, 0.62), scale=(0.06, 0.03, 0.04)),
                  sphere(BLUSH, loc=(0.4, -0.58, 0.78), scale=(0.11, 0.04, 0.06)), sphere(BLUSH, loc=(-0.4, -0.58, 0.78), scale=(0.11, 0.04, 0.06))], "mouth")
    a.part("Body", [shell, b, mouth] + spikes)
    for s, n in ((1, "EarL"), (-1, "EarR")):
        stalk = tube(shade(c, -0.1), [(s * 0.25, -0.45, 1.0), (s * 0.3, -0.5, 1.45)], 0.06)
        e = eye((s * 0.3, -0.55, 1.55), 0.17, look=(0, -1, 0.1))
        a.part(n, [stalk, e], parent="Body", joint=(s * 0.25, -0.45, 1.0))
    for s, n in ((1, "ArmL"), (-1, "ArmR")):
        arm = tube(c, [(s * 0.8, -0.3, 0.75), (s * 1.15, -0.65, 0.85)], 0.11)
        claw = sphere(shade(c, 0.1), loc=(s * 1.2, -0.95, 0.9), scale=(0.32, 0.3, 0.24))
        pincer = cone(shade(c, -0.15), loc=(s * 1.2, -1.25, 0.95), r=0.12, h=0.35, rot=(90, 0, 0))
        a.part(n, [arm, claw, pincer], parent="Body", joint=(s * 0.8, -0.3, 0.75))
    for (x, y, n) in ((0.85, 0.0, "LegFL"), (-0.85, 0.0, "LegFR"), (0.75, 0.35, "LegBL"), (-0.75, 0.35, "LegBR")):
        p = [tube(shade(c, -0.1), [(x * 0.9, y, 0.6), (x * 1.3, y, 0.55), (x * 1.4, y, 0.05)], 0.07)]
        a.part(n, p, parent="Body", joint=(x * 0.9, y, 0.6))
    return a


def nebby():
    a = Asset("Alien_Nebby", "alien")
    use(a)
    c = "788CFF"
    lift = 0.9
    dome = sphere(c, loc=(0, 0, 1.0 + lift), scale=(0.85, 0.85, 0.7))
    deform(dome, lambda v: Vector((v.x, v.y, max(v.z, 0.8 + lift))))
    rim = torus(shade(c, 0.3), loc=(0, 0, 0.82 + lift), R=0.82, r=0.1)
    a.part("Body", [dome, rim] + face((0, 0, 1.08 + lift), 0.83, eye_size=0.24, spread=0.36, up=0.0, iris="3A5AD8", on=dome))
    a.part("Body_Glow", [sphere("D7B4FF", loc=(x, y, z + lift), scale=0.09) for x, y, z in
                         ((0.4, 0.3, 1.5), (-0.3, 0.45, 1.45), (0.1, 0.6, 1.6), (-0.55, 0.0, 1.3), (0.55, -0.15, 1.35))],
           parent="Body", glow="D7B4FF")
    for i, ang in enumerate((45, 135, 225, 315)):
        t = math.radians(ang)
        x, y = math.cos(t) * 0.45, math.sin(t) * 0.45
        pts = [(x, y, 0.85 + lift), (x * 1.15, y * 1.15, 0.45 + lift), (x * 1.05, y * 1.05, 0.05 + lift), (x * 1.25, y * 1.25, -0.35 + lift)]
        a.part(f"Tent{i + 1}", [tube(shade(c, 0.15), pts, 0.09)], parent="Body", joint=(x, y, 0.85 + lift))
    a.extra["float"] = True
    return a


def orbo():
    a = Asset("Alien_Orbo", "alien")
    use(a)
    c = "50BEFF"
    lift = 0.7
    body = sphere(c, loc=(0, 0, 0.9 + lift), scale=0.85, seg=24, rings=14)
    belly = sphere(shade(c, 0.4), loc=(0, -0.3, 0.75 + lift), scale=(0.55, 0.5, 0.5))
    a.part("Body", [body, belly] + face((0, 0, 0.95 + lift), 0.85, eye_size=0.3, n_eyes=1, up=0.12, iris="1E7FD0", on=body))
    a.part("Body_Glow", [torus("FFE36E", loc=(0, 0, 0.95 + lift), R=1.2, r=0.07, rot=(18, 10, 0), seg=32)], parent="Body", glow="FFE36E")
    for s, n in ((1, "ArmL"), (-1, "ArmR")):
        a.part(n, [sphere(shade(c, -0.1), loc=(s * 0.92, -0.05, 0.75 + lift), scale=(0.16, 0.16, 0.24))], parent="Body", joint=(s * 0.8, 0, 0.9 + lift))
    a.extra["float"] = True
    return a


def lunar_slug():
    a = Asset("Alien_LunarSlug", "alien")
    use(a)
    c, belly = "B4DCFF", "E6F4FF"
    front = sphere(c, loc=(0, -0.35, 0.55), scale=(0.55, 0.75, 0.55))
    foot = sphere(belly, loc=(0, 0, 0.15), scale=(0.6, 1.3, 0.16))
    a.part("Body", [front, foot] + face((0, -0.55, 0.65), 0.5, eye_size=0.26, spread=0.42, up=0.05, iris="3AA0C8", on=front))
    tail = sphere(c, loc=(0, 0.75, 0.35), scale=(0.42, 0.7, 0.35))
    a.part("Tail", [tail], parent="Body", joint=(0, 0.25, 0.4))
    a.part("Tail_Glow", [ico("9BFFF5", loc=(0, 0.5, 1.0), scale=(0.22, 0.22, 0.42), sub=1),
                         ico("9BFFF5", loc=(0.2, 0.75, 0.85), scale=(0.14, 0.14, 0.28), sub=1, rot=(0, 20, 0)),
                         ico("9BFFF5", loc=(-0.2, 0.3, 0.88), scale=(0.13, 0.13, 0.26), sub=1, rot=(0, -20, 0))],
           parent="Tail", glow="9BFFF5")
    for s, n in ((1, "EarL"), (-1, "EarR")):
        stalk = tube(shade(c, -0.15), [(s * 0.2, -0.55, 0.95), (s * 0.32, -0.65, 1.4)], 0.05)
        ball = sphere(shade(c, -0.15), loc=(s * 0.33, -0.66, 1.45), scale=0.09)
        a.part(n, [stalk, ball], parent="Body", joint=(s * 0.2, -0.55, 0.95))
    return a


def zorblax():
    a = Asset("Alien_Zorblax", "alien")
    use(a)
    c, dark = "AA5AFF", "4A2A7A"
    torso = sphere(c, loc=(0, 0, 1.0), scale=(0.55, 0.42, 0.55))
    belly = sphere(shade(c, 0.35), loc=(0, -0.22, 0.9), scale=(0.38, 0.25, 0.38))
    a.part("Body", [torso, belly])
    a.part("Body_Glow", [ico("5AFFE0", loc=(0, -0.42, 1.12), scale=0.12, sub=1)], parent="Body", glow="5AFFE0")
    head = sphere(c, loc=(0, -0.05, 1.95), scale=(0.55, 0.5, 0.5))
    fins = [cone(dark, loc=(s * 0.45, 0.05, 2.35), r=0.12, h=0.45, rot=(0, s * -35, 0)) for s in (-1, 1)]
    fins.append(cone(dark, loc=(0, 0.05, 2.5), r=0.14, h=0.5))
    a.part("Head", [head] + fins + face((0, -0.05, 1.95), 0.52, eye_size=0.22, n_eyes=3, spread=0.42, up=0.08, pupil="2A0050", iris="1FB89A", on=head),
           parent="Body", joint=(0, 0, 1.5))
    for s, n in ((1, "ArmL"), (-1, "ArmR")):
        arm = tube(c, [(s * 0.5, 0, 1.3), (s * 0.8, -0.1, 1.0), (s * 0.85, -0.2, 0.7)], 0.1)
        claw = sphere(dark, loc=(s * 0.86, -0.24, 0.6), scale=0.14)
        a.part(n, [arm, claw], parent="Body", joint=(s * 0.48, 0, 1.3))
    for s, n in ((1, "LegL"), (-1, "LegR")):
        leg = capsule(dark, (s * 0.25, 0, 0.6), (s * 0.28, 0, 0.18), 0.13)
        foot = sphere(dark, loc=(s * 0.28, -0.1, 0.1), scale=(0.17, 0.24, 0.1))
        a.part(n, [leg, foot], parent="Body", joint=(s * 0.25, 0, 0.6))
    return a


def quad_base(a, c, belly, body_len=0.9, h=0.75, r=0.45, leg_r=0.12):
    torso = sphere(c, loc=(0, 0.1, h), scale=(r, body_len * 0.7, r * 0.92))
    b = sphere(belly, loc=(0, 0.05, h - r * 0.35), scale=(r * 0.75, body_len * 0.55, r * 0.55))
    legs = []
    for (sx, sy, n) in ((1, -1, "LegFL"), (-1, -1, "LegFR"), (1, 1, "LegBL"), (-1, 1, "LegBR")):
        x, y = sx * r * 0.6, 0.1 + sy * body_len * 0.42
        legs.append((x, y, n))
    return [torso, b], legs


def comet_cat():
    a = Asset("Alien_CometCat", "alien")
    use(a)
    c, belly = "FF96DC", "FFE0F4"
    body, legs = quad_base(a, c, belly)
    a.part("Body", body)
    for x, y, n in legs:
        stub_leg(a, c, x, y, 0.6, 0.6, 0.12, n, foot=belly)
    head = sphere(c, loc=(0, -0.65, 1.35), scale=(0.55, 0.48, 0.48))
    muzzle = sphere(belly, loc=(0, -1.05, 1.22), scale=(0.24, 0.12, 0.15))
    nose = sphere("FF5A9A", loc=(0, -1.15, 1.3), scale=0.05)
    star = ico("FFE36E", loc=(0, -1.0, 1.62), scale=(0.1, 0.04, 0.1), sub=1)
    ears = []
    for s in (-1, 1):
        ears.append(cone(c, loc=(s * 0.3, -0.6, 1.8), r=0.17, h=0.36, rot=(0, s * -15, 0)))
        ears.append(cone("FFC8E8", loc=(s * 0.3, -0.66, 1.79), r=0.1, h=0.26, rot=(0, s * -15, 0)))
    a.part("Head", [head, muzzle, nose, star] + ears + face((0, -0.65, 1.38), 0.5, eye_size=0.26, spread=0.42, up=0.12, mouth=False, iris="D84A9A", on=head),
           parent="Body", joint=(0, -0.45, 1.0))
    tail = tube(c, [(0, 0.75, 0.9), (0, 1.05, 1.15), (0, 1.15, 1.5)], 0.08)
    a.part("Tail", [tail], parent="Body", joint=(0, 0.72, 0.9))
    a.part("Tail_Glow", [sphere("FFB14A", loc=(0, 1.2, 1.7), scale=(0.22, 0.22, 0.3)),
                         cone("FFE36E", loc=(0, 1.3, 2.0), r=0.16, h=0.45, rot=(-20, 0, 0))],
           parent="Tail", glow="FFB14A")
    return a


def quasar_pup():
    a = Asset("Alien_QuasarPup", "alien")
    use(a)
    c, belly = "8C78FF", "D8D0FF"
    body, legs = quad_base(a, c, belly, body_len=1.0, h=0.8, r=0.5)
    collar = torus("FF5A7A", loc=(0, -0.45, 1.0), R=0.36, r=0.07, rot=(70, 0, 0))
    tag = ico("FFE36E", loc=(0, -0.68, 0.8), scale=(0.1, 0.04, 0.1), sub=1)
    a.part("Body", body + [collar, tag])
    for x, y, n in legs:
        stub_leg(a, c, x, y, 0.62, 0.62, 0.13, n, foot=belly)
    head = sphere(c, loc=(0, -0.75, 1.45), scale=(0.55, 0.5, 0.5))
    snout = sphere(belly, loc=(0, -1.15, 1.32), scale=(0.28, 0.2, 0.18))
    nose = sphere(DARK, loc=(0, -1.33, 1.4), scale=(0.09, 0.06, 0.07))
    tongue = sphere("FF7A9A", loc=(0.08, -1.25, 1.18), scale=(0.07, 0.05, 0.1))
    a.part("Head", [head, snout, nose, tongue] + face((0, -0.75, 1.5), 0.52, eye_size=0.25, spread=0.42, up=0.15, mouth=False, iris="5A48C8", on=head),
           parent="Body", joint=(0, -0.5, 1.05))
    for s, n in ((1, "EarL"), (-1, "EarR")):
        ear = sphere(shade(c, -0.2), loc=(s * 0.55, -0.7, 1.4), scale=(0.12, 0.2, 0.38), rot=(0, s * 20, 0))
        tip = sphere("5AFFF0", loc=(s * 0.62, -0.7, 1.05), scale=0.1)
        a.part(n, [ear], parent="Head", joint=(s * 0.45, -0.7, 1.72))
        a.part(n + "_Glow", [tip], parent=n, glow="5AFFF0")
    a.part("Tail", [tube(c, [(0, 0.85, 1.0), (0, 1.1, 1.35)], 0.1), sphere(belly, loc=(0, 1.12, 1.42), scale=0.14)], parent="Body", joint=(0, 0.8, 1.0))
    return a


def star_whale():
    a = Asset("Alien_StarWhale", "alien")
    use(a)
    c, belly = "3C78FF", "BCD8FF"
    lift = 1.0
    body = sphere(c, loc=(0, 0, 1.2 + lift), scale=(0.95, 1.5, 0.9))
    deform(body, lambda v: Vector((v.x * (1 - max(0, v.y) * 0.35), v.y, v.z - max(0, v.y) * 0.1 * (v.z - 1.2 - lift))))
    b = sphere(belly, loc=(0, -0.2, 0.75 + lift), scale=(0.7, 1.1, 0.45))
    a.part("Body", [body, b] + face((0, -0.6, 1.25 + lift), 0.9, eye_size=0.22, spread=0.55, up=0.0, iris="2A5AE0", on=body))
    a.part("Body_Glow", [ico("FFF5A0", loc=(x, y, z + lift), scale=(0.1, 0.1, 0.03), sub=1) for x, y, z in
                         ((0.3, 0.2, 2.05), (-0.25, 0.5, 2.0), (0.0, -0.3, 2.12), (0.4, 0.8, 1.8), (-0.45, -0.1, 1.95))],
           parent="Body", glow="FFF5A0")
    for s, n in ((1, "WingL"), (-1, "WingR")):
        fin = sphere(shade(c, -0.15), loc=(s * 1.1, -0.1, 0.95 + lift), scale=(0.55, 0.3, 0.08), rot=(0, s * -25, s * 15))
        a.part(n, [fin], parent="Body", joint=(s * 0.75, -0.1, 1.05 + lift))
    tail = [sphere(c, loc=(0, 1.6, 1.25 + lift), scale=(0.35, 0.4, 0.3))]
    for s in (-1, 1):
        tail.append(sphere(shade(c, -0.15), loc=(s * 0.45, 2.0, 1.3 + lift), scale=(0.5, 0.25, 0.08), rot=(0, 0, s * -20)))
    a.part("Tail", tail, parent="Body", joint=(0, 1.3, 1.25 + lift))
    a.extra["float"] = True
    return a


def galaxy_gus():
    a = Asset("Alien_GalaxyGus", "alien")
    use(a)
    suit, gold, skin = "F5F5FA", "FFC83C", "8CE650"
    torso = sphere(suit, loc=(0, 0, 1.05), scale=(0.7, 0.6, 0.7))
    panel = box(gold, loc=(0, -0.58, 1.1), size=(0.42, 0.06, 0.3), bevel=0.04)
    lights = [sphere(col, loc=(x, -0.63, 1.12), scale=0.05) for x, col in ((-0.12, "FF5A5A"), (0, "5AFF8C"), (0.12, "5AB4FF"))]
    pack = box("B4B4C8", loc=(0, 0.55, 1.15), size=(0.7, 0.35, 0.8), bevel=0.08)
    a.part("Body", [torso, panel, pack] + lights)
    helmet_c = (0, -0.05, 2.05)
    alien = sphere(skin, loc=helmet_c, scale=0.45)
    glass = sphere("CDEBFF", loc=helmet_c, scale=0.62, seg=24, rings=14)
    deform(glass, lambda v: v if v.y > -0.25 else Vector((v.x, -0.25 + (v.y + 0.25) * 0.98, v.z)))
    ring = torus(gold, loc=(0, -0.05, 1.5), R=0.45, r=0.08)
    a.part("Head", [alien, ring] + face(helmet_c, 0.45, eye_size=0.3, spread=0.4, up=0.1, iris="2FA84F", on=alien), parent="Body", joint=(0, 0, 1.55))
    a.part("Head_Glass", [glass], parent="Head", material="Glass")
    for s, n in ((1, "ArmL"), (-1, "ArmR")):
        arm = capsule(suit, (s * 0.65, 0, 1.3), (s * 0.85, -0.1, 0.85), 0.16)
        glove = sphere(gold, loc=(s * 0.88, -0.12, 0.75), scale=0.17)
        a.part(n, [arm, glove], parent="Body", joint=(s * 0.6, 0, 1.3))
    for s, n in ((1, "LegL"), (-1, "LegR")):
        leg = capsule(suit, (s * 0.3, 0, 0.55), (s * 0.32, 0, 0.22), 0.18)
        boot = sphere(gold, loc=(s * 0.32, -0.08, 0.12), scale=(0.2, 0.28, 0.12))
        a.part(n, [leg, boot], parent="Body", joint=(s * 0.3, 0, 0.55))
    return a


def astro_axolotl():
    a = Asset("Alien_AstroAxolotl", "alien")
    use(a)
    c, belly = "FFA0C8", "FFE0EC"
    body, legs = quad_base(a, c, belly, body_len=1.2, h=0.55, r=0.48)
    a.part("Body", body)
    for x, y, n in legs:
        stub_leg(a, c, x * 1.2, y, 0.45, 0.45, 0.11, n, foot=shade(c, 0.2))
    head = sphere(c, loc=(0, -0.85, 0.95), scale=(0.7, 0.5, 0.45))
    a.part("Head", [head] + face((0, -0.85, 0.98), 0.5, eye_size=0.25, spread=0.75, up=0.18, cheeks=True, iris="D8407A", on=head),
           parent="Body", joint=(0, -0.55, 0.75))
    for s, n in ((1, "EarL"), (-1, "EarR")):
        gills = [capsule("FF5A9A", (s * 0.55, -0.8, 1.05 + k * 0.2), (s * (0.95 + k * 0.05), -0.75, 1.15 + k * 0.32), 0.06) for k in (-1, 0, 1)]
        a.part(n, gills, parent="Head", joint=(s * 0.55, -0.8, 1.05))
        a.part(n + "_Glow", [sphere("FFE36E", loc=(s * (0.95 + k * 0.05), -0.75, 1.15 + k * 0.32), scale=0.08) for k in (-1, 0, 1)], parent=n, glow="FFE36E")
    tail = sphere(c, loc=(0, 1.15, 0.6), scale=(0.18, 0.75, 0.32))
    fin = sphere(shade(c, 0.25), loc=(0, 1.3, 0.75), scale=(0.05, 0.6, 0.3))
    a.part("Tail", [tail, fin], parent="Body", joint=(0, 0.6, 0.6))
    return a


def void_king():
    a = Asset("Alien_VoidKing", "alien")
    use(a)
    c, cape, gold = "2A1440", "6A1AAA", "FFC83C"
    torso = sphere(c, loc=(0, 0, 1.25), scale=(0.75, 0.6, 0.85))
    cape_m = sphere(cape, loc=(0, 0.25, 1.05), scale=(0.85, 0.5, 1.0))
    deform(cape_m, lambda v: v if v.y > 0.1 else Vector((v.x, 0.1 + (v.y - 0.1) * 0.2, v.z)))
    collar = torus(gold, loc=(0, 0, 1.95), R=0.5, r=0.08)
    a.part("Body", [torso, cape_m, collar])
    head = sphere(c, loc=(0, -0.05, 2.45), scale=(0.6, 0.55, 0.55))
    crown = [cyl(gold, loc=(0, -0.05, 2.95), r=0.42, h=0.2, verts=10)]
    crown += [cone(gold, loc=(math.cos(t) * 0.38, -0.05 + math.sin(t) * 0.38, 3.18), r=0.08, h=0.28, verts=6) for t in [i * math.pi / 3 for i in range(6)]]
    horns = [cone("E0D0FF", loc=(s * 0.55, -0.05, 2.85), r=0.1, h=0.55, rot=(0, s * -40, 0)) for s in (-1, 1)]
    a.part("Head", [head] + crown + horns + face((0, -0.05, 2.45), 0.55, eye_size=0.3, spread=0.42, up=0.05, iris="C85AFF",
                                                   smile_color="E0D0FF", on=head), parent="Body", joint=(0, 0, 2.0))
    a.part("Head_Glow", [ico("FF5AFF", loc=(0, -0.42, 3.0), scale=0.08, sub=1)], parent="Head", glow="C85AFF")
    for s, n in ((1, "ArmL"), (-1, "ArmR")):
        arm = capsule(c, (s * 0.7, 0, 1.6), (s * 1.0, -0.15, 1.05), 0.17)
        claw = [cone("E0D0FF", loc=(s * (1.0 + k * 0.08), -0.25, 0.85), r=0.05, h=0.22, rot=(180, 0, 0)) for k in (-1, 0, 1)]
        a.part(n, [arm] + claw, parent="Body", joint=(s * 0.65, 0, 1.6))
    for s, n in ((1, "LegL"), (-1, "LegR")):
        leg = capsule(c, (s * 0.32, 0, 0.6), (s * 0.35, 0, 0.2), 0.2)
        a.part(n, [leg], parent="Body", joint=(s * 0.32, 0, 0.6))
    return a


def eclipse_dragon():
    a = Asset("Alien_EclipseDragon", "alien")
    use(a)
    c, belly, horn = "FF5028", "FFC85A", "3A1A10"
    body, legs = quad_base(a, c, belly, body_len=1.4, h=1.0, r=0.62, leg_r=0.16)
    spikes = [cone(horn, loc=(0, y, 1.62 - abs(y) * 0.15), r=0.1, h=0.3, verts=6) for y in (-0.4, 0.0, 0.4)]
    a.part("Body", body + spikes)
    a.part("Body_Glow", [sphere("FFE36E", loc=(0, -0.05, 0.62), scale=(0.35, 0.65, 0.12))], parent="Body", glow="FFB43C")
    for x, y, n in legs:
        stub_leg(a, c, x, y, 0.85, 0.85, 0.16, n, foot=horn)
    neck = capsule(c, (0, -0.7, 1.2), (0, -1.0, 1.75), 0.25)
    head = sphere(c, loc=(0, -1.15, 1.95), scale=(0.6, 0.62, 0.52))
    snout = sphere(belly, loc=(0, -1.6, 1.85), scale=(0.3, 0.25, 0.2))
    horns = [cone(horn, loc=(s * 0.3, -0.95, 2.4), r=0.08, h=0.5, rot=(-30, s * -20, 0)) for s in (-1, 1)]
    a.part("Head", [neck, head, snout] + horns + face((0, -1.15, 2.0), 0.55, eye_size=0.3, spread=0.5, up=0.25, mouth=False, cheeks=True, pupil="3A0A00", iris="E07A10", on=head),
           parent="Body", joint=(0, -0.6, 1.2))
    for s, n in ((1, "WingL"), (-1, "WingR")):
        bone = tube(horn, [(s * 0.5, -0.1, 1.5), (s * 1.3, 0.0, 2.1), (s * 2.0, 0.2, 1.8)], 0.06)
        mem = sphere("7A2A8A", loc=(s * 1.2, 0.15, 1.6), scale=(0.85, 0.45, 0.05), rot=(0, s * -20, 0))
        a.part(n, [bone, mem], parent="Body", joint=(s * 0.5, -0.1, 1.5))
    tail = tube(c, [(0, 0.95, 1.0), (0, 1.5, 0.8), (0, 2.0, 0.6)], lambda i: 0.22 - i * 0.07)
    tip = cone(horn, loc=(0, 2.25, 0.58), r=0.16, h=0.35, rot=(-90, 0, 0), verts=4)
    a.part("Tail", [tail, tip], parent="Body", joint=(0, 0.9, 1.0))
    return a


def nova_queen():
    a = Asset("Alien_NovaQueen", "alien")
    use(a)
    c, dress, gold = "FFF5C8", "FFD25A", "FFB43C"
    lift = 0.5
    skirt = cyl(dress, loc=(0, 0, 0.95 + lift), r=0.8, r2=0.28, h=1.15, verts=28)
    deform(skirt, lambda v: Vector((v.x, v.y, v.z + 0.05 * math.sin(math.atan2(v.y, v.x) * 8) * max(0, 1.2 + lift - v.z))))
    ruffles = [torus(shade(dress, 0.45), loc=(0, 0, 0.42 + lift), R=0.78, r=0.07, seg=28),
               torus(shade(dress, 0.45), loc=(0, 0, 0.95 + lift), R=0.55, r=0.05, seg=24),
               torus(gold, loc=(0, 0, 1.48 + lift), R=0.3, r=0.05, seg=20)]
    stars = [ico("FFFFFF", loc=(math.cos(t) * 0.62, math.sin(t) * 0.62, 0.7 + lift + 0.1 * (k % 2)), scale=0.06, sub=1)
             for k, t in enumerate([i * math.pi / 4 for i in range(8)])]
    torso = sphere(c, loc=(0, 0, 1.6 + lift), scale=(0.35, 0.3, 0.4))
    a.part("Body", [skirt, torso] + ruffles + stars)
    head = sphere(c, loc=(0, 0, 2.35 + lift), scale=0.45)
    hair = sphere("FF96C8", loc=(0, 0.12, 2.45 + lift), scale=(0.5, 0.45, 0.45))
    deform(hair, lambda v: v if v.y > -0.05 else Vector((v.x, -0.05 + (v.y + 0.05) * 0.2, v.z)))
    a.part("Head", [head, hair] + face((0, 0, 2.35 + lift), 0.45, eye_size=0.27, spread=0.38, up=0.05, pupil="5A2A8A", iris="9A4AD8", on=head),
           parent="Body", joint=(0, 0, 1.95 + lift))
    a.part("Head_Glow", [ico("FFF08C", loc=(0, -0.05, 2.95 + lift), scale=(0.22, 0.08, 0.22), sub=1)]
           + [ico("FFF08C", loc=(s * 0.25, 0.0, 2.85 + lift), scale=(0.11, 0.05, 0.11), sub=1) for s in (-1, 1)],
           parent="Head", glow="FFF08C")
    for s, n in ((1, "ArmL"), (-1, "ArmR")):
        arm = [capsule(c, (s * 0.32, 0, 1.85 + lift), (s * 0.65, -0.1, 1.45 + lift), 0.08)]
        if s == -1:
            arm += [capsule(gold, (s * 0.68, -0.15, 1.35 + lift), (s * 0.72, -0.25, 2.0 + lift), 0.035)]
            star = ico("FFF08C", loc=(s * 0.72, -0.27, 2.12 + lift), scale=(0.16, 0.06, 0.16), sub=1)
            arm.append(star)
        a.part(n, arm, parent="Body", joint=(s * 0.3, 0, 1.85 + lift))
    for s, n in ((1, "WingL"), (-1, "WingR")):
        w = [sphere("B4F0FF", loc=(s * 0.6, 0.35, 2.0 + lift), scale=(0.55, 0.06, 0.4), rot=(0, s * -30, 0)),
             sphere("B4F0FF", loc=(s * 0.5, 0.35, 1.45 + lift), scale=(0.35, 0.05, 0.25), rot=(0, s * 30, 0))]
        a.part(n, w, parent="Body", joint=(s * 0.15, 0.25, 1.75 + lift), glow="B4F0FF")
    a.extra["float"] = True
    return a


def cosmo():
    a = Asset("Alien_Cosmo", "alien")
    use(a)
    c, deep = "FF78E6", "5A2ABE"
    lift = 1.0
    body = sphere(deep, loc=(0, 0, 1.4 + lift), scale=(0.95, 0.85, 1.05), seg=24, rings=14)
    belly = sphere(c, loc=(0, -0.35, 1.25 + lift), scale=(0.65, 0.5, 0.7))
    a.part("Body", [body, belly])
    a.part("Body_Glow", [ico("FFFFFF", loc=(x, y, z + lift), scale=0.06, sub=1) for x, y, z in
                         ((0.6, 0.3, 1.9), (-0.5, 0.5, 1.7), (0.2, 0.7, 2.1), (-0.7, -0.1, 1.2), (0.75, -0.2, 1.0), (0.0, 0.8, 1.4))]
           + [torus("FFE36E", loc=(0, 0, 1.3 + lift), R=1.55, r=0.07, rot=(75, 0, 20), seg=36),
              torus("78FFF0", loc=(0, 0, 1.3 + lift), R=1.75, r=0.05, rot=(65, 0, -35), seg=36)],
           parent="Body", glow="FFE36E")
    head = sphere(deep, loc=(0, -0.1, 2.75 + lift), scale=0.65)
    ears = [cone(deep, loc=(s * 0.42, -0.05, 3.35 + lift), r=0.22, h=0.5, rot=(0, s * -20, 0)) for s in (-1, 1)]
    a.part("Head", [head] + ears + face((0, -0.1, 2.78 + lift), 0.65, eye_size=0.27, spread=0.4, up=0.1, pupil="FF2AC8", smile_color="FFFFFF", iris="FF2AC8", on=head),
           parent="Body", joint=(0, 0, 2.25 + lift))
    a.part("Head_Glow", [torus("FFF08C", loc=(0, 0.1, 3.65 + lift), R=0.45, r=0.06, rot=(10, 0, 0))], parent="Head", glow="FFF08C")
    for s, n in ((1, "ArmL"), (-1, "ArmR")):
        a.part(n, [capsule(c, (s * 0.85, 0, 1.8 + lift), (s * 1.25, -0.2, 1.3 + lift), 0.16)], parent="Body", joint=(s * 0.8, 0, 1.8 + lift))
    tail = tube(c, [(0, 0.7, 0.7 + lift), (0, 1.0, 0.25 + lift), (0, 1.3, 0.0 + lift)], lambda i: 0.3 - i * 0.12)
    a.part("Tail", [tail], parent="Body", joint=(0, 0.6, 0.8 + lift))
    a.extra["float"] = True
    return a


ALL = {
    "Blip": blip, "MoonMite": moon_mite, "Dusty": dusty,
    "Glorp": glorp, "Zib": zib, "CraterCrab": crater_crab,
    "Nebby": nebby, "Orbo": orbo, "LunarSlug": lunar_slug,
    "Zorblax": zorblax, "CometCat": comet_cat, "QuasarPup": quasar_pup,
    "StarWhale": star_whale, "GalaxyGus": galaxy_gus, "AstroAxolotl": astro_axolotl,
    "VoidKing": void_king, "EclipseDragon": eclipse_dragon, "NovaQueen": nova_queen,
    "Cosmo": cosmo,
}


# ------------------------------------------------------------------ zone variants
# Eggs found in later zones hatch variants of the Landing pets: recoloured, with a zone
# accessory on top (crystals, shadow horns, a magma flame, a frost beanie). Must match
# Aliens.luau ZONE_SETS.

KEEP = {WHITE, DARK, BLUSH, PINK, "FF6F91", "1B1530", "FFFFFF"}


def _rgb(h):
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)]


def _hex(c):
    return "".join(f"{max(0, min(255, round(x))):02X}" for x in c)


def _tint(h, target, k, light=0.0):
    c = _rgb(h)
    t = _rgb(target)
    lum = (c[0] * 0.3 + c[1] * 0.59 + c[2] * 0.11) / 255
    tl = (t[0] * 0.3 + t[1] * 0.59 + t[2] * 0.11) / 255
    # keep the original brightness so shading details survive
    scaled = [x * (lum / max(tl, 0.05)) for x in t]
    out = [c[i] * (1 - k) + scaled[i] * k for i in range(3)]
    if light > 0:
        out = [x + (255 - x) * light for x in out]
    elif light < 0:
        out = [x * (1 + light) for x in out]
    return _hex(out)


def _top(a):
    """Top-centre point and width of the head (or body if there's no head)."""
    o = a.parts.get("Head", a.parts["Body"])["obj"]
    zs = [v.co.z for v in o.data.vertices]
    top = max(zs)
    cut = top - (top - min(zs)) * 0.12
    pts = [v.co for v in o.data.vertices if v.co.z >= cut]
    cx = sum(p.x for p in pts) / len(pts)
    cy = sum(p.y for p in pts) / len(pts)
    xs = [v.co.x for v in o.data.vertices]
    return Vector((cx, cy, top)), (max(xs) - min(xs)), ("Head" if "Head" in a.parts else "Body")


def acc_crystal(a):
    top, w, parent = _top(a)
    k = max(0.35, w * 0.45)
    shards = []
    for i, (dx, tilt, h, col) in enumerate(((0, 0, 1.0, "7AE6FF"), (-0.35, -28, 0.7, "FF9AF0"), (0.35, 28, 0.75, "B4F5FF"))):
        shards.append(cone(col, loc=top + Vector((dx * k, 0.05, h * k * 0.32)), r=0.13 * k, h=h * k * 0.75, verts=5, rot=(0, tilt, 0), smooth=False))
    a.part("Zone_Glow", shards, parent=parent, glow="7AE6FF")


def acc_shadow(a):
    top, w, parent = _top(a)
    k = max(0.35, w * 0.45)
    horns = [tube("3A1A5A", [top + Vector((s * 0.28 * k, 0, -0.05 * k)), top + Vector((s * 0.42 * k, 0, 0.3 * k)),
                             top + Vector((s * 0.3 * k, 0.05, 0.55 * k))], lambda i: 0.09 * k - i * 0.03 * k) for s in (-1, 1)]
    a.part("Zone", horns, parent=parent)
    wisps = [sphere("B45AFF", loc=top + Vector((s * 0.3 * k, 0.05, 0.6 * k)), scale=0.07 * k) for s in (-1, 1)]
    a.part("Zone_Glow", wisps, parent="Zone", glow="B45AFF")


def acc_magma(a):
    top, w, parent = _top(a)
    k = max(0.35, w * 0.45)
    flame = [cone("FF7A1E", loc=top + Vector((0, 0, 0.3 * k)), r=0.22 * k, h=0.7 * k, verts=8),
             cone("FFD23C", loc=top + Vector((0.12 * k, -0.05, 0.22 * k)), r=0.13 * k, h=0.45 * k, verts=8, rot=(0, 18, 0)),
             cone("FFB43C", loc=top + Vector((-0.13 * k, 0.03, 0.2 * k)), r=0.12 * k, h=0.4 * k, verts=8, rot=(0, -20, 0))]
    a.part("Zone_Glow", flame, parent=parent, glow="FF9A2E")


def acc_frost(a):
    top, w, parent = _top(a)
    k = max(0.35, w * 0.45)
    hat = sphere("7AB4FF", loc=top + Vector((0, 0, -0.08 * k)), scale=(0.42 * k, 0.42 * k, 0.3 * k))
    deform(hat, lambda v: Vector((v.x, v.y, max(v.z, top.z - 0.08 * k))))
    band = torus("FFFFFF", loc=top + Vector((0, 0, -0.06 * k)), R=0.4 * k, r=0.08 * k, seg=20)
    pom = sphere("FFFFFF", loc=top + Vector((0, 0, 0.3 * k)), scale=0.13 * k)
    flakes = [ico("E6F8FF", loc=top + Vector((s * 0.2 * k, -0.33 * k, 0.07 * k)), scale=(0.06 * k, 0.02, 0.06 * k), sub=1) for s in (-1, 1)]
    a.part("Zone", [hat, band, pom] + flakes, parent=parent)


ZONE_SETS = [
    ("Crystal", "78DCFF", 0.5, 0.15, acc_crystal, ["Blip", "MoonMite", "Glorp", "CraterCrab", "Orbo", "LunarSlug", "CometCat"]),
    ("Shadow", "965AE6", 0.6, -0.25, acc_shadow, ["Dusty", "Zib", "Nebby", "Zorblax", "QuasarPup", "StarWhale", "GalaxyGus"]),
    ("Magma", "FF6E32", 0.55, 0.0, acc_magma, ["Blip", "CraterCrab", "LunarSlug", "CometCat", "AstroAxolotl", "EclipseDragon", "VoidKing"]),
    ("Frost", "BEEBFF", 0.55, 0.25, acc_frost, ["MoonMite", "Glorp", "Orbo", "QuasarPup", "StarWhale", "NovaQueen", "EclipseDragon"]),
]


def variant(prefix, target, k, light, acc, base):
    def build():
        a = ALL[base]()
        a.name = f"Alien_{prefix}{base}"
        a.colors = [c if c in KEEP else _tint(c, target, k, light) for c in a.colors]
        use(a)
        acc(a)
        return a
    return build


VARIANTS = {}
for _prefix, _target, _k, _light, _acc, _bases in ZONE_SETS:
    for _base in _bases:
        VARIANTS[_prefix + _base] = variant(_prefix, _target, _k, _light, _acc, _base)
