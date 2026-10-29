"""Flat HUD icons: simple bold shapes, flat colour, one shade, one highlight and a thick dark
outline around the whole silhouette (the toy/sticker look Dev picked on 2026-10-28).

Every icon is a list of shapes on a 512 x 512 canvas. Shapes marked as body get the thick
outline (drawn once behind everything, so overlapping parts share one silhouette), a darker
crescent on the lower right and a thin line where they meet other parts. Details and
highlights are drawn on top as they are.

  pip install cairosvg
  python3 art/flat_icons.py [name ...]   -> art/out/icons/<Name>.png (512 x 512)
  python3 art/flat_icons.py --sheet      -> art/out/icon_sheet.png (all icons)

Icons made with ForgeUI (same flat thick-outline look) are kept in art/out/forge/<Name>.png;
when one is there it is used instead of the drawing here (cropped and centred on 512 x 512).
DERIVED icons are ForgeUI icons recoloured, with an optional badge from another icon.

Then upload with tools/upload_assets.py (only changed files are uploaded).
"""
import io
import math
import os
import sys

import cairosvg

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out", "icons")
SIZE = 512
LINE = "#15151C"  # outline: almost black (matches the ForgeUI icons)
W = 22  # outline width (each side) at 512 px

# palette
RED, RED_D = "#FF4B55", "#D8303D"
ORANGE = "#FF9A3C"
YELLOW = "#FFD43B"
GOLD = "#FFC22E"
GREEN = "#5CD65C"
DGREEN = "#2FA84F"
LEAF = "#7BD846"
BLUE = "#4CA8FF"
SKY = "#7FD3FF"
NAVY = "#3B5BDB"
PURPLE = "#9B6BFF"
PINK = "#FF7EB6"
CREAM = "#FFE7C2"
BROWN = "#B7713A"
DBROWN = "#7A4A26"
GREY = "#B9C2CF"
DGREY = "#6B7385"
WHITE = "#FFFFFF"
TAN = "#F2C48D"


def darker(hex_color, k=0.78):
    h = hex_color.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
    return "#%02X%02X%02X" % (int(r * k), int(g * k), int(b * k))


# ------------------------------------------------------------------ shape helpers
class Shape:
    def __init__(self, tag, fill, attrs, body=True, shade=True, line=True, opacity=1.0):
        self.tag, self.fill, self.attrs = tag, fill, attrs
        self.body, self.shade, self.line, self.opacity = body, shade, line, opacity

    def svg(self, **override):
        a = dict(self.attrs)
        a.update(override)
        return "<%s %s/>" % (self.tag, " ".join('%s="%s"' % (k.replace("_", "-"), v) for k, v in a.items()))


def path(d, fill, **kw):
    return Shape("path", fill, {"d": d}, **kw)


def circle(cx, cy, r, fill, **kw):
    return Shape("circle", fill, {"cx": cx, "cy": cy, "r": r}, **kw)


def ellipse(cx, cy, rx, ry, fill, rot=0, **kw):
    a = {"cx": cx, "cy": cy, "rx": rx, "ry": ry}
    if rot:
        a["transform"] = "rotate(%s %s %s)" % (rot, cx, cy)
    return Shape("ellipse", fill, a, **kw)


def rect(x, y, w, h, fill, r=0, rot=0, **kw):
    a = {"x": x, "y": y, "width": w, "height": h, "rx": r}
    if rot:
        a["transform"] = "rotate(%s %s %s)" % (rot, x + w / 2, y + h / 2)
    return Shape("rect", fill, a, **kw)


def poly(points, fill, **kw):
    return Shape("polygon", fill, {"points": " ".join("%s,%s" % p for p in points), "stroke_linejoin": "round"}, **kw)


def star_points(cx, cy, r1, r2, n=5, rot=-90):
    pts = []
    for i in range(n * 2):
        r = r1 if i % 2 == 0 else r2
        a = math.radians(rot + i * 180 / n)
        pts.append((round(cx + r * math.cos(a), 1), round(cy + r * math.sin(a), 1)))
    return pts


def hl(cx, cy, rx, ry, rot=-30, opacity=0.55):
    """White highlight blob (no outline)."""
    return ellipse(cx, cy, rx, ry, WHITE, rot=rot, body=False, shade=False, line=False, opacity=opacity)


def detail(shape):
    shape.body, shape.shade = False, False
    return shape


def stroke_line(d, width=W, color=LINE):
    """An open line drawn on top (a crease, a handle, a mouth)."""
    s = Shape("path", "none", {"d": d, "stroke": color, "stroke_width": width, "stroke_linecap": "round",
                               "stroke_linejoin": "round", "fill": "none"}, body=False, shade=False, line=False)
    s.raw = True
    return s


def text(x, y, value, size, fill=WHITE, weight=900):
    s = Shape("text", fill, {}, body=False, shade=False, line=False)
    s.raw_svg = ('<text x="%s" y="%s" font-family="Montserrat, Arial Black, sans-serif" font-weight="%s" font-size="%s" '
                 'text-anchor="middle" dominant-baseline="central" fill="%s" stroke="%s" stroke-width="%s" '
                 'paint-order="stroke" stroke-linejoin="round">%s</text>' % (x, y, weight, size, fill, LINE, W * 0.9, value))
    return s


# ------------------------------------------------------------------ renderer
def render_svg(shapes):
    parts = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % (SIZE, SIZE, SIZE, SIZE)]
    defs = []
    # 1. one outline behind every body shape
    parts.append('<g fill="%s" stroke="%s" stroke-width="%d" stroke-linejoin="round" stroke-linecap="round">' % (LINE, LINE, W * 2))
    for s in shapes:
        if s.body:
            parts.append(s.svg())
    parts.append("</g>")
    # 2. fills, shades, inner lines, details in order
    for i, s in enumerate(shapes):
        if getattr(s, "raw_svg", None):
            parts.append(s.raw_svg)
            continue
        if getattr(s, "raw", False):
            parts.append(s.svg())
            continue
        op = ' opacity="%s"' % s.opacity if s.opacity != 1 else ""
        if s.body and s.shade and s.fill != "none":
            cid = "c%d" % i
            defs.append('<clipPath id="%s">%s</clipPath>' % (cid, s.svg()))
            parts.append('<g%s>%s<g clip-path="url(#%s)"><g transform="translate(-16 -16)">%s</g></g></g>' % (
                op, s.svg(fill=darker(s.fill)), cid, s.svg(fill=s.fill)))
        else:
            parts.append("<g%s>%s</g>" % (op, s.svg(fill=s.fill)))
        if s.line:
            parts.append(s.svg(fill="none", stroke=LINE, stroke_width=W * 0.55, stroke_linejoin="round"))
    parts.append("</svg>")
    if defs:
        parts.insert(1, "<defs>%s</defs>" % "".join(defs))
    return "".join(parts)


# ------------------------------------------------------------------ icons
ICONS = {}


def icon(name):
    def deco(fn):
        ICONS[name] = fn
        return fn
    return deco


def egg_shape(cx, cy, w, h, fill, **kw):
    # Egg: narrower top. Cubic path around (cx, cy) with half width w and half height h.
    top, bot = cy - h, cy + h
    d = ("M %s %s C %s %s %s %s %s %s C %s %s %s %s %s %s Z" % (
        cx, top,
        cx + w * 0.78, top, cx + w, cy - h * 0.05, cx + w, cy + h * 0.28,
        cx + w, bot + h * 0.02, cx - w, bot + h * 0.02, cx - w, cy + h * 0.28))
    d = d.replace(" Z", " C %s %s %s %s %s %s Z" % (cx - w, cy - h * 0.05, cx - w * 0.78, top, cx, top))
    return path(d, fill, **kw)


@icon("Egg")
def _egg():
    return [egg_shape(256, 268, 150, 205, CREAM), hl(200, 170, 34, 62, rot=20)]


@icon("Alien")  # pets: a paw print
def _paw():
    return [
        path("M 256 236 C 330 236 392 300 392 362 C 392 420 340 440 300 430 C 280 425 268 418 256 418 "
             "C 244 418 232 425 212 430 C 172 440 120 420 120 362 C 120 300 182 236 256 236 Z", ORANGE),
        ellipse(118, 216, 46, 60, ORANGE, rot=-28),
        ellipse(204, 136, 50, 66, ORANGE, rot=-8),
        ellipse(308, 136, 50, 66, ORANGE, rot=8),
        ellipse(394, 216, 46, 60, ORANGE, rot=28),
        hl(212, 300, 30, 18, rot=-20), hl(196, 112, 14, 22, rot=-8), hl(300, 112, 14, 22, rot=8),
    ]


@icon("Base")  # a house
def _house():
    return [
        rect(108, 236, 296, 220, CREAM, r=8),
        rect(318, 70, 54, 110, RED, r=6),
        path("M 256 64 L 468 262 L 418 262 L 256 116 L 94 262 L 44 262 Z", RED),
        path("M 256 116 L 418 262 L 94 262 Z", RED, body=False, line=False, shade=False),
        rect(212, 318, 88, 138, BLUE, r=40),
        rect(134, 284, 56, 56, SKY, r=8, shade=False),
        rect(322, 284, 56, 56, SKY, r=8, shade=False),
        hl(150, 300, 10, 14, rot=0, opacity=0.6),
    ]


@icon("Cash")  # gold coin stack
def _cash():
    shapes = []
    for i, y in enumerate((392, 340, 288)):
        shapes.append(ellipse(236, y + 22, 150, 52, GOLD, shade=False))
        shapes.append(rect(86, y - 30, 300, 52, GOLD, shade=False, line=False))
        shapes.append(ellipse(236, y - 30, 150, 52, YELLOW, shade=False))
    shapes += [
        circle(330, 190, 128, GOLD),
        circle(330, 190, 92, YELLOW, body=False, shade=False),
        text(330, 196, "$", 150, fill=GOLD),
        hl(270, 120, 26, 16, rot=-35),
    ]
    return shapes


@icon("Dust")  # a pile of autumn leaves
def _leaves():
    def leaf(cx, cy, s, rot, col):
        d = ("M %s %s C %s %s %s %s %s %s C %s %s %s %s %s %s Z" % (
            cx, cy - s, cx + s * 0.9, cy - s * 0.6, cx + s * 0.7, cy + s * 0.6, cx, cy + s,
            cx - s * 0.7, cy + s * 0.6, cx - s * 0.9, cy - s * 0.6, cx, cy - s))
        sh = path(d, col)
        sh.attrs["transform"] = "rotate(%s %s %s)" % (rot, cx, cy)
        vein = stroke_line("M %s %s L %s %s" % (cx, cy - s * 0.7, cx, cy + s * 0.9), width=W * 0.5)
        vein.attrs["transform"] = "rotate(%s %s %s)" % (rot, cx, cy)
        return [sh, vein]
    out = [path("M 60 440 C 90 330 190 290 256 290 C 322 290 422 330 452 440 Z", BROWN)]
    out += leaf(170, 330, 92, -50, ORANGE)
    out += leaf(345, 330, 92, 50, RED)
    out += leaf(256, 230, 118, 0, YELLOW)
    out.append(hl(230, 180, 14, 34, rot=0))
    return out


@icon("Star")
def _star():
    return [poly(star_points(256, 270, 214, 100), YELLOW), hl(200, 200, 26, 40, rot=35)]


@icon("Luck")  # four-leaf clover
def _clover():
    out = [path("M 262 300 C 280 360 300 410 340 460", "none", body=False, shade=False, line=False)]
    out = [stroke_line("M 256 280 C 270 350 300 410 344 458", width=W * 2.6),
           stroke_line("M 256 280 C 270 350 300 410 344 458", width=W * 1.1, color=DGREEN)]
    for ang in (0, 90, 180, 270):
        a = math.radians(ang - 45)
        cx, cy = 256 + 92 * math.cos(a), 240 + 92 * math.sin(a)
        heart = path("M %s %s C %s %s %s %s %s %s C %s %s %s %s %s %s Z" % (
            256, 240, 256 - 30, 240 - 40, 256 - 130, 240 - 40, 256 - 105, 240 - 120,
            256 - 80, 240 - 175, 256 - 10, 240 - 150, 256, 240), GREEN)
        heart.attrs["transform"] = "rotate(%s 256 240)" % (ang + 45 - 90 + 45)
        out.append(heart)
    out += [circle(256, 240, 30, LEAF, body=False, shade=False), hl(196, 160, 16, 28, rot=-40)]
    return out


@icon("Gift")
def _gift():
    return [
        rect(84, 226, 344, 240, RED, r=10),
        rect(60, 160, 392, 90, RED, r=10),
        rect(226, 160, 60, 306, YELLOW, shade=False),
        path("M 256 160 C 200 60 110 80 140 140 C 160 170 220 168 256 160 Z", YELLOW),
        path("M 256 160 C 312 60 402 80 372 140 C 352 170 292 168 256 160 Z", YELLOW),
        hl(130, 190, 30, 12, rot=0),
    ]


@icon("Shop")  # a little shop with a striped awning
def _shop():
    out = [rect(88, 220, 336, 236, CREAM, r=8),
           rect(140, 300, 96, 156, BLUE, r=8, shade=False),
           rect(270, 290, 110, 90, SKY, r=8, shade=False)]
    out.append(path("M 60 120 L 452 120 L 452 216 C 452 246 404 246 404 216 C 404 246 356 246 356 216 "
                    "C 356 246 306 246 306 216 C 306 246 256 246 256 216 C 256 246 206 246 206 216 "
                    "C 206 246 156 246 156 216 C 156 246 108 246 108 216 C 108 246 60 246 60 216 Z", RED))
    for x in (108, 206, 306, 404):
        out.append(path("M %s 120 L %s 120 L %s 216 C %s 246 %s 246 %s 216 Z" % (x - 48 + 48, x + 50 - 2, x + 50 - 2, x + 50 - 2,
                                                                              x - 0, x), WHITE, body=False, shade=False, line=False))
    out.append(rect(60, 70, 392, 56, RED_D, r=10))
    out.append(hl(300, 316, 14, 22, rot=20, opacity=0.6))
    return out


@icon("Index")  # a book with a paw
def _book():
    return [
        rect(96, 70, 320, 380, BLUE, r=18),
        rect(96, 70, 56, 380, NAVY, r=14, shade=False),
        rect(150, 420, 266, 40, CREAM, r=8, shade=False),
        circle(290, 270, 52, CREAM, body=False, shade=False),
        circle(240, 196, 20, CREAM, body=False, shade=False), circle(290, 182, 20, CREAM, body=False, shade=False),
        circle(340, 196, 20, CREAM, body=False, shade=False),
        hl(200, 110, 40, 12, rot=0),
    ]


@icon("Upgrade")  # big up arrow
def _upgrade():
    return [poly([(256, 50), (452, 262), (340, 262), (340, 456), (172, 456), (172, 262), (60, 262)], GREEN),
            hl(220, 150, 20, 46, rot=40)]


@icon("Rebirth")  # purple loop arrows
def _rebirth():
    return [
        path("M 256 70 A 186 186 0 0 1 438 220 L 486 220 L 400 320 L 314 220 L 360 220 "
             "A 110 110 0 0 0 256 146 Z", PURPLE),
        path("M 256 442 A 186 186 0 0 1 74 292 L 26 292 L 112 192 L 198 292 L 152 292 "
             "A 110 110 0 0 0 256 366 Z", PURPLE),
        poly(star_points(256, 256, 62, 28), YELLOW),
        hl(250, 98, 34, 12, rot=0),
    ]


@icon("Auto")  # green loop arrows with an A
def _auto():
    return [
        path("M 256 70 A 186 186 0 0 1 438 220 L 486 220 L 400 320 L 314 220 L 360 220 "
             "A 110 110 0 0 0 256 146 Z", GREEN),
        path("M 256 442 A 186 186 0 0 1 74 292 L 26 292 L 112 192 L 198 292 L 152 292 "
             "A 110 110 0 0 0 256 366 Z", GREEN),
        text(256, 262, "A", 150, fill=YELLOW),
    ]


@icon("Daily")  # calendar with a star
def _calendar():
    return [
        rect(72, 100, 368, 350, WHITE, r=22),
        rect(72, 100, 368, 100, RED, r=22, shade=False),
        rect(142, 56, 40, 90, DGREY, r=20, shade=False), rect(330, 56, 40, 90, DGREY, r=20, shade=False),
        poly(star_points(256, 320, 96, 44), YELLOW),
    ]


@icon("Timer")  # stopwatch
def _timer():
    return [
        rect(222, 38, 68, 60, GREY, r=10),
        rect(352, 92, 50, 44, GREY, r=10, rot=40),
        circle(256, 284, 182, WHITE),
        circle(256, 284, 140, CREAM, body=False, shade=False),
        stroke_line("M 256 284 L 256 182", width=W * 1.2),
        stroke_line("M 256 284 L 330 320", width=W * 1.2),
        circle(256, 284, 18, RED, body=False, shade=False),
        hl(180, 190, 26, 44, rot=40),
    ]


@icon("Lock")
def _lock():
    return [
        path("M 150 240 L 150 170 C 150 40 362 40 362 170 L 362 240 L 304 240 L 304 172 C 304 110 208 110 208 172 "
             "L 208 240 Z", GREY),
        rect(90, 220, 332, 240, GOLD, r=30),
        circle(256, 320, 32, DBROWN, body=False, shade=False),
        rect(240, 330, 32, 70, DBROWN, r=12, body=False, shade=False, line=False),
        hl(150, 260, 30, 12, rot=0),
    ]


@icon("Boost")  # lightning bolt
def _bolt():
    return [poly([(300, 36), (110, 290), (240, 290), (196, 476), (402, 202), (272, 202)], YELLOW),
            hl(250, 120, 14, 50, rot=35)]


@icon("Speed")  # a running shoe with speed lines
def _shoe():
    return [
        stroke_line("M 40 230 L 120 230", width=W * 1.2), stroke_line("M 24 300 L 110 300", width=W * 1.2),
        path("M 130 170 C 170 160 220 150 250 170 C 290 210 360 250 430 270 C 470 280 480 330 470 360 "
             "L 130 360 C 120 300 120 230 130 170 Z", RED),
        rect(120, 350, 368, 60, WHITE, r=26),
        stroke_line("M 220 220 L 260 200", width=W * 0.7), stroke_line("M 250 250 L 290 230", width=W * 0.7),
        hl(170, 200, 18, 34, rot=10),
    ]


@icon("Sell")  # price tag with a dollar sign
def _tag():
    return [
        path("M 240 50 L 446 50 C 456 50 462 56 462 66 L 462 272 L 250 484 L 28 262 Z", ORANGE),
        circle(392, 120, 30, CREAM, body=False, shade=False),
        text(236, 276, "$", 200, fill=YELLOW),
    ]


@icon("Zones")  # the Earth
def _globe():
    return [
        circle(256, 256, 206, BLUE),
        path("M 140 130 C 200 100 260 120 250 170 C 240 220 180 210 170 260 C 160 300 110 300 80 270 "
             "C 70 210 90 160 140 130 Z", GREEN, shade=False),
        path("M 300 240 C 350 220 420 250 430 300 C 420 360 380 410 330 430 C 310 380 330 340 300 320 "
             "C 280 300 270 260 300 240 Z", GREEN, shade=False),
        path("M 300 80 C 340 80 380 100 400 130 C 370 150 330 140 300 120 Z", GREEN, shade=False),
        hl(170, 150, 30, 60, rot=40, opacity=0.4),
    ]


@icon("Group")  # two friends
def _group():
    return [
        circle(330, 170, 72, TAN), path("M 214 420 C 214 300 446 300 446 420 Z", BLUE),
        circle(190, 190, 82, TAN), path("M 60 450 C 60 310 320 310 320 450 Z", GREEN),
        hl(160, 160, 16, 26, rot=30),
    ]


@icon("Event")  # party popper
def _event():
    return [
        poly([(70, 450), (180, 190), (330, 340)], PURPLE),
        stroke_line("M 120 360 L 220 400", width=W * 0.8, color=YELLOW),
        stroke_line("M 150 290 L 260 340", width=W * 0.8, color=PINK),
        circle(330, 120, 26, YELLOW), circle(420, 200, 22, PINK), circle(260, 70, 18, BLUE), circle(440, 320, 20, GREEN),
        poly(star_points(380, 100, 44, 20), YELLOW),
        stroke_line("M 260 190 C 290 150 300 120 300 90", width=W * 0.9),
    ]


@icon("Meteor")  # egg rain: a falling egg with speed streaks
def _egg_rain():
    return [
        stroke_line("M 330 70 L 430 20", width=W * 1.3), stroke_line("M 380 140 L 490 90", width=W * 1.3),
        stroke_line("M 260 40 L 330 8", width=W * 1.1),
        egg_shape(230, 300, 130, 176, CREAM), hl(180, 220, 28, 52, rot=20),
        path("M 110 430 L 150 380 L 190 420 L 230 370 L 270 420 L 310 380 L 350 430 Z", WHITE, shade=False, body=False),
    ]


def cloud(cx, cy, s, fill=WHITE):
    """Puffy cloud centred on (cx, cy), about 2s wide."""
    return [
        path("M %s %s C %s %s %s %s %s %s C %s %s %s %s %s %s C %s %s %s %s %s %s "
             "C %s %s %s %s %s %s C %s %s %s %s %s %s Z" % (
                 cx - s, cy + s * 0.45,
                 cx - s * 1.25, cy + s * 0.45, cx - s * 1.2, cy - s * 0.15, cx - s * 0.72, cy - s * 0.1,
                 cx - s * 0.7, cy - s * 0.75, cx + s * 0.05, cy - s * 0.85, cx + s * 0.2, cy - s * 0.35,
                 cx + s * 0.55, cy - s * 0.65, cx + s * 1.15, cy - s * 0.4, cx + s * 0.95, cy + s * 0.05,
                 cx + s * 1.3, cy + s * 0.1, cx + s * 1.3, cy + s * 0.45, cx + s, cy + s * 0.45,
                 cx + s * 0.4, cy + s * 0.45, cx - s * 0.4, cy + s * 0.45, cx - s, cy + s * 0.45), fill),
        hl(cx - s * 0.35, cy - s * 0.35, s * 0.22, s * 0.12, rot=-15),
    ]


def drop(cx, cy, s, fill=BLUE):
    d = "M %s %s C %s %s %s %s %s %s C %s %s %s %s %s %s C %s %s %s %s %s %s Z" % (
        cx, cy - s,
        cx + s * 0.25, cy - s * 0.4, cx + s * 0.62, cy, cx + s * 0.62, cy + s * 0.38,
        cx + s * 0.62, cy + s * 1.05, cx - s * 0.62, cy + s * 1.05, cx - s * 0.62, cy + s * 0.38,
        cx - s * 0.62, cy, cx - s * 0.25, cy - s * 0.4, cx, cy - s)
    return path(d, fill)


@icon("Weather_Rain")
def _w_rain():
    return [drop(150, 400, 62), drop(270, 430, 62), drop(390, 400, 62)] + cloud(256, 210, 170, GREY)


@icon("Weather_Thunderstorm")
def _w_storm():
    return (cloud(256, 190, 170, DGREY) +
            [poly([(290, 250), (170, 400), (250, 400), (210, 500), (360, 330), (280, 330), (330, 250)], YELLOW)])


@icon("Weather_Snow")
def _w_snow():
    out = []
    for i in range(3):
        a = i * 60
        out.append(rect(236, 50, 40, 412, SKY, r=20, rot=a, shade=False))
    for i in range(6):
        a = math.radians(i * 60 - 90)
        cx, cy = 256 + math.cos(a) * 140, 256 + math.sin(a) * 140
        out.append(circle(round(cx), round(cy), 34, WHITE, shade=False))
    out.append(circle(256, 256, 64, WHITE))
    return out


@icon("Weather_Windy")
def _w_windy():
    return [
        stroke_line("M 40 170 C 180 170 260 160 300 120 C 330 90 300 40 260 60", width=W * 1.4),
        stroke_line("M 30 260 C 200 260 330 260 400 230 C 460 200 440 140 390 160", width=W * 1.4),
        stroke_line("M 60 350 C 160 350 220 350 260 380", width=W * 1.4),
        path("M 330 470 C 300 400 340 330 440 300 C 470 380 430 450 330 470 Z", ORANGE),
        stroke_line("M 340 460 C 370 400 400 360 440 310", width=W * 0.5),
    ]


@icon("Weather_Rainbow")
def _w_rainbow():
    out = []
    for r, col in ((210, RED), (175, ORANGE), (140, YELLOW), (105, GREEN), (70, BLUE)):
        out.append(path("M %s 350 A %s %s 0 0 1 %s 350 L %s 350 A %s %s 0 0 0 %s 350 Z" % (
            256 - r, r, r, 256 + r, 256 + r - 35, r - 35, r - 35, 256 - r + 35), col, shade=False))
    return out + cloud(110, 380, 80) + cloud(400, 380, 80)


@icon("Weather_GoldenHour")
def _w_sun():
    out = []
    for i in range(8):
        a = i * 45
        out.append(rect(236, 30, 40, 100, ORANGE, r=20, rot=0, shade=False))
        out[-1].attrs["transform"] = "rotate(%s 256 256)" % a
    return out + [circle(256, 256, 130, GOLD), hl(210, 200, 36, 22, rot=-35)]


@icon("Weather_BloodMoon")
def _w_blood():
    return [circle(256, 256, 200, RED), circle(190, 200, 34, RED_D, body=False, shade=False),
            circle(320, 310, 46, RED_D, body=False, shade=False), circle(300, 170, 22, RED_D, body=False, shade=False),
            circle(180, 330, 24, RED_D, body=False, shade=False), hl(160, 140, 40, 22, rot=-35)]


@icon("Weather_Aurora")
def _w_aurora():
    return [
        path("M 40 330 C 120 180 200 300 270 170 C 330 60 420 170 470 90 L 470 230 C 420 300 340 200 280 300 "
             "C 210 420 120 300 40 450 Z", "#5CF2B4"),
        path("M 40 450 C 120 300 210 420 280 300 C 340 200 420 300 470 230 L 470 300 C 420 380 340 290 280 380 "
             "C 210 480 120 380 40 500 Z", PURPLE, shade=False),
        poly(star_points(130, 110, 50, 20, n=4, rot=0), YELLOW, shade=False),
        poly(star_points(380, 360, 36, 15, n=4, rot=0), WHITE, shade=False),
    ]


@icon("Weather_Disco")
def _w_disco():
    out = [stroke_line("M 256 20 L 256 80", width=W * 0.8), circle(256, 280, 190, GREY)]
    cols = [SKY, PINK, YELLOW, PURPLE, GREEN, BLUE]
    k = 0
    for gy in range(120, 460, 56):
        for gx in range(80, 460, 56):
            if (gx + 28 - 256) ** 2 + (gy + 28 - 280) ** 2 < 165 ** 2:
                out.append(rect(gx + 4, gy + 4, 48, 48, cols[k % len(cols)], r=4, body=False, shade=False, line=False, opacity=0.85))
                k += 1
    out.append(hl(190, 200, 40, 24, rot=-35, opacity=0.8))
    return out


@icon("Backpack")
def _backpack():
    return [
        rect(96, 120, 320, 340, ORANGE, r=70),
        path("M 190 130 C 190 50 322 50 322 130 L 290 130 C 290 90 222 90 222 130 Z", DBROWN),
        rect(140, 300, 232, 130, darker(ORANGE, 0.9), r=30, shade=False),
        rect(230, 300, 52, 36, YELLOW, r=10, shade=False),
        hl(150, 180, 22, 44, rot=20),
    ]


@icon("Tool")
@icon("Tool_Broom")
def _broom():
    return [
        rect(236, 20, 40, 290, BROWN, r=16, rot=0),
        path("M 150 300 L 362 300 L 420 470 L 92 470 Z", YELLOW),
        rect(140, 280, 232, 50, RED, r=14),
        stroke_line("M 190 360 L 170 460", width=W * 0.55), stroke_line("M 256 360 L 256 460", width=W * 0.55),
        stroke_line("M 322 360 L 342 460", width=W * 0.55),
        hl(250, 80, 8, 30, rot=0),
    ]


@icon("Tool_Toothbrush")
def _toothbrush():
    return [
        rect(60, 230, 330, 60, SKY, r=30, rot=-30),
        rect(330, 90, 120, 64, WHITE, r=14, rot=-30),
        rect(340, 140, 100, 34, BLUE, r=10, rot=-30),
        hl(150, 300, 40, 10, rot=-30),
    ]


@icon("Tool_Mop")
def _mop():
    out = [rect(236, 20, 40, 300, BROWN, r=16), rect(160, 300, 192, 56, BLUE, r=18)]
    for x in (170, 210, 250, 290, 330):
        out.append(rect(x - 16, 340, 34, 130, WHITE, r=17))
    out.append(hl(250, 80, 8, 30, rot=0))
    return out


@icon("Tool_LeafBlower")
def _blower():
    return [
        rect(250, 210, 240, 76, GREY, r=30, rot=-12),
        rect(60, 160, 230, 200, ORANGE, r=50),
        path("M 120 160 C 120 80 250 80 250 160 L 214 160 C 214 120 156 120 156 160 Z", DGREY),
        circle(170, 262, 50, DGREY, body=False, shade=False),
        hl(100, 210, 16, 30, rot=20),
    ]


@icon("Tool_ShopVac")
def _shopvac():
    return [
        stroke_line("M 330 160 C 420 120 470 200 440 300 L 420 430", width=W * 2.4),
        stroke_line("M 330 160 C 420 120 470 200 440 300 L 420 430", width=W * 1.1, color=DGREY),
        rect(380, 420, 100, 44, GREY, r=12),
        rect(70, 170, 280, 280, YELLOW, r=50),
        rect(60, 130, 300, 70, DGREY, r=24),
        circle(120, 456, 26, LINE, body=False, shade=False), circle(300, 456, 26, LINE, body=False, shade=False),
        hl(120, 250, 18, 46, rot=10),
    ]


@icon("Tool_TurboVacuum")
def _turbovac():
    return [
        rect(236, 30, 40, 280, DGREY, r=16),
        rect(200, 150, 112, 170, RED, r=40),
        rect(100, 310, 312, 100, RED, r=30),
        rect(90, 390, 332, 40, DGREY, r=16),
        poly([(270, 190), (230, 250), (262, 250), (240, 300), (292, 230), (258, 230)], YELLOW, shade=False),
        hl(150, 330, 30, 10, rot=0),
    ]


def vehicle(body, extra):
    def build():
        out = list(extra.get("back", []))
        out += [
            path(body, extra["color"]),
            rect(250, 160, 120, 100, SKY, r=18, shade=False) if extra.get("window", True) else None,
            circle(150, 400, 62, DGREY), circle(150, 400, 26, GREY, body=False, shade=False),
            circle(380, 400, 62, DGREY), circle(380, 400, 26, GREY, body=False, shade=False),
        ]
        out += extra.get("front", [])
        out.append(hl(140, 250, 30, 12, rot=0))
        return [s for s in out if s]
    return build


CAR = "M 60 260 L 100 140 L 400 140 L 452 260 L 470 260 C 480 260 486 270 486 280 L 486 380 L 26 380 L 26 290 Z"
TRUCK = "M 26 150 L 300 150 L 300 200 L 420 200 L 486 290 L 486 380 L 26 380 Z"
for name, color, shape, extra in (
    ("Vehicle", BLUE, CAR, {}),
    ("Car_MoonBuggy", GREEN, CAR, {"front": [rect(70, 96, 380, 30, WHITE, r=10)]}),   # golf cart
    ("Car_SweeperCart", ORANGE, CAR, {"front": [rect(2, 340, 120, 70, YELLOW, r=20)]}),
    ("Car_DustTruck", DGREEN, TRUCK, {"window": False, "front": [rect(330, 220, 90, 70, SKY, r=12, shade=False)]}),  # garbage
    ("Car_HoverSweeper", YELLOW, TRUCK, {"window": False, "front": [rect(330, 220, 90, 70, SKY, r=12, shade=False),
                                                                   circle(470, 410, 48, ORANGE)]}),  # street sweeper
    ("Car_SolarRover", RED, CAR, {"front": [rect(450, 230, 50, 190, GREY, r=10)]}),  # snow plow
    ("Car_MoonCrawler", GREEN, CAR, {"front": [rect(180, 90, 160, 60, GREEN, r=10)]}),
    ("Car_RocketSweeper", PURPLE, TRUCK, {"window": False, "front": [rect(330, 220, 90, 70, SKY, r=12, shade=False),
                                                                     poly(star_points(150, 260, 60, 28), YELLOW)]}),
):
    ICONS[name] = vehicle(shape, dict(extra, color=color))


def potion(liquid, symbol=None):
    def build():
        out = [
            path("M 206 60 L 306 60 L 306 180 C 400 210 440 280 440 330 C 440 420 360 470 256 470 "
                 "C 152 470 72 420 72 330 C 72 280 112 210 206 180 Z", "#E8F6FF"),
            path("M 92 320 C 140 290 200 340 256 320 C 312 300 372 290 420 320 C 430 400 360 450 256 450 "
                 "C 152 450 82 400 92 320 Z", liquid, line=False),
            rect(190, 34, 132, 52, BROWN, r=14),
            hl(170, 260, 22, 40, rot=30),
        ]
        if symbol:
            out += symbol()
        return out
    return build


ICONS["Potion"] = potion(PURPLE)
ICONS["PotionCash"] = potion(GREEN, lambda: [text(256, 380, "$", 120, fill=YELLOW)])
ICONS["PotionLuck"] = potion(LEAF, lambda: [poly(star_points(256, 380, 56, 26), YELLOW, shade=False)])
ICONS["PotionSpeed"] = potion(BLUE, lambda: [poly([(270, 320), (220, 390), (254, 390), (236, 450), (296, 370), (262, 370)], YELLOW, shade=False)])
ICONS["PotionHatch"] = potion(ORANGE, lambda: [egg_shape(256, 386, 40, 54, CREAM)])


# ------------------------------------------------------------------ output
FORGE = os.path.join(HERE, "out", "forge")
MARGIN = 14

# name: (ForgeUI source, hue shift in degrees, saturation factor, badge icon or None)
DERIVED = {
    "Auto": ("Rebirth", -160, 0.9, None),      # purple loop -> green loop
    "PotionLuck": ("Potion", -170, 0.9, "Luck"),  # purple -> leaf green, clover badge
    "PotionCash": ("Potion", 135, 1.0, "Cash"),   # purple -> gold, coins badge
}


def fit(im):
    """Crop to the drawing and centre it on a square canvas with a small margin."""
    from PIL import Image
    im = im.convert("RGBA")
    im = im.crop(im.getbbox())
    w, h = im.size
    k = (SIZE - 2 * MARGIN) / max(w, h)
    im = im.resize((max(1, round(w * k)), max(1, round(h * k))), Image.LANCZOS)
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.alpha_composite(im, ((SIZE - im.size[0]) // 2, (SIZE - im.size[1]) // 2))
    return out


def hue_shift(im, degrees, sat, around=275, width=40):
    """Turn one colour of a ForgeUI icon into another: only pixels whose hue is within
    `width` degrees of `around` (purple by default) are shifted, so corks, glass, stars
    and outlines keep their colours."""
    import numpy as np
    from PIL import Image
    a = im.getchannel("A")
    hsv = np.array(im.convert("RGB").convert("HSV")).astype(np.int32)
    h = hsv[..., 0] * 360 // 256
    diff = np.abs((h - around + 180) % 360 - 180)
    mask = (diff <= width) & (hsv[..., 1] > 50)
    hsv[..., 0] = np.where(mask, (hsv[..., 0] + round(degrees / 360 * 256)) % 256, hsv[..., 0])
    hsv[..., 1] = np.where(mask, np.minimum(255, (hsv[..., 1] * sat).astype(np.int32)), hsv[..., 1])
    rgb = Image.fromarray(hsv.astype(np.uint8), "HSV").convert("RGB")
    out = rgb.convert("RGBA")
    out.putalpha(a)
    return out


def image(name):
    from PIL import Image
    src = os.path.join(FORGE, name + ".png")
    if os.path.exists(src):
        return fit(Image.open(src))
    if name in DERIVED:
        base, deg, sat, badge = DERIVED[name]
        if os.path.exists(os.path.join(FORGE, base + ".png")):
            im = hue_shift(image(base), deg, sat)
            if badge:
                b = image(badge).resize((230, 230), Image.LANCZOS)
                im.alpha_composite(b, (SIZE - 250, SIZE - 250))
            return im
    return Image.open(io.BytesIO(cairosvg.svg2png(bytestring=render_svg(ICONS[name]()).encode(),
                                                  output_width=SIZE, output_height=SIZE))).convert("RGBA")


def png(name):
    buf = io.BytesIO()
    image(name).save(buf, "PNG")
    return buf.getvalue()


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    os.makedirs(OUT, exist_ok=True)
    names = args or sorted(set(ICONS) | set(DERIVED))
    if "--sheet" in sys.argv:
        from PIL import Image
        cols = 8
        rows = math.ceil(len(names) / cols)
        cell = 160
        sheet = Image.new("RGBA", (cols * cell, rows * cell), (60, 160, 90, 255))
        for i, n in enumerate(names):
            im = Image.open(io.BytesIO(png(n))).resize((cell - 16, cell - 16), Image.LANCZOS)
            sheet.alpha_composite(im, ((i % cols) * cell + 8, (i // cols) * cell + 8))
        sheet.save(os.path.join(OUT, "..", "icon_sheet.png"))
        print("sheet:", len(names))
        return
    for n in names:
        with open(os.path.join(OUT, n + ".png"), "wb") as f:
            f.write(png(n))
    print("wrote", len(names), "icons")


if __name__ == "__main__":
    main()
