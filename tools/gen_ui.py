"""Writes src/gui/*.model.json: every ScreenGui in the game, in the style from
docs/UI_STYLE.md (clean bright simulator style: white panels, colour headers, thick dark
outline, square corners).

Controllers only look elements up by name, so names here are the contract with
src/client/Controllers. Image ids come from src/shared/Config/Assets.luau.

  python3 tools/gen_ui.py
"""
import json
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "src", "gui")

# ---------------------------------------------------------------- tokens (UI_STYLE.md)
BG = "#272B34"        # charcoal: dim overlay, dark plates (clean bar, tips)
SURFACE = "#F7F8FA"   # white panels
HEADER = "#2F9BFF"    # sky blue header strip
INK = "#17191E"       # outline, dark text
SUB = "#5B6070"       # secondary text on white
ACCENT = "#8BE04E"    # leaf green: selected tab, World Clean bar
SUCCESS = "#3DDC5A"   # buy with cash, claim, go
PREMIUM = "#FFC83C"   # Robux, rare
DANGER = "#FF4D5E"    # close, full
MUTED = "#B5BAC6"     # disabled / owned
WHITE = "#FFFFFF"
PILL_BASE = "#3DDC5A"
PILL_SELL = "#FF9A3C"
PILL_ZONES = "#4C8DFF"
REBIRTH = "#9B6BFF"

RADIUS = 0  # square corners everywhere (Dev: rounded corners looked bad)
STUD_TEXTURE = True  # buttons only: Dev wants the stud background on every button (2026-10-28)
BUTTON_STUD = 0.45  # stud image transparency on buttons (0 = strongest)
STROKE = 4
STUD_TILE = 64
MONTSERRAT = "rbxasset://fonts/families/Montserrat.json"
DISPLAY = {"family": MONTSERRAT, "weight": "Heavy", "style": "Normal"}
BODY = {"family": MONTSERRAT, "weight": "Bold", "style": "Normal"}
BODY_HEAVY = {"family": MONTSERRAT, "weight": "ExtraBold", "style": "Normal"}


def images():
    text = open(os.path.join(ROOT, "src", "shared", "Config", "Assets.luau")).read()
    block = text[text.index("Assets.Images"):]
    return dict(re.findall(r'(\w+) = "(rbxassetid://\d+)"', block))


IMG = images()


def img(name):
    return IMG.get(name) or IMG.get("Icon_" + name, "")


# ---------------------------------------------------------------- primitives
def U(sx, ox, sy, oy):
    return [[sx, ox], [sy, oy]]


def node(name, cls, props=None, children=None, attrs=None):
    n = {"name": name, "className": cls, "properties": props or {}}
    if children:
        n["children"] = [c for c in children if c]
    if attrs:
        n["attributes"] = attrs
    return n


def corner(r=RADIUS, scale=0):
    # Square style: no UICorner at all.
    return None


def border(color=INK, thickness=STROKE, name="Stroke"):
    return node(name, "UIStroke", {"Color": color, "Thickness": thickness, "ApplyStrokeMode": "Border", "LineJoinMode": "Round"})


def text_stroke(thickness=2.5, color=INK):
    return node("TextStroke", "UIStroke", {"Color": color, "Thickness": thickness, "ApplyStrokeMode": "Contextual", "LineJoinMode": "Round"})


def shine(dark="#C9D0DE"):
    # Lighter top edge so buttons read as toys.
    return node("Shine", "UIGradient", {"Color": {"keypoints": [[0, WHITE], [0.55, WHITE], [1, dark]]}, "Rotation": 90})


def autoscale():
    return node("AutoScale", "UIScale", {"Scale": 1})


def padding(l, r=None, t=None, b=None):
    r = l if r is None else r
    t = l if t is None else t
    b = t if b is None else b
    return node("Padding", "UIPadding", {"PaddingLeft": [0, l], "PaddingRight": [0, r], "PaddingTop": [0, t], "PaddingBottom": [0, b]})


def vlist(pad=8, h="Center", v="Top"):
    return node("Layout", "UIListLayout", {"Padding": [0, pad], "FillDirection": "Vertical", "HorizontalAlignment": h,
                                           "VerticalAlignment": v, "SortOrder": "LayoutOrder"})


def hlist(pad=8, h="Center", v="Center"):
    return node("Layout", "UIListLayout", {"Padding": [0, pad], "FillDirection": "Horizontal", "HorizontalAlignment": h,
                                           "VerticalAlignment": v, "SortOrder": "LayoutOrder"})


def base(size, pos=U(0, 0, 0, 0), anchor=(0, 0), **extra):
    # A colour passed by position lands here by mistake (it broke the Index once).
    assert len(anchor) == 2 and all(isinstance(a, (int, float)) for a in anchor), f"bad AnchorPoint {anchor!r}"
    p = {"Size": size, "Position": pos, "AnchorPoint": list(anchor), "BorderSizePixel": 0}
    p.update(extra)
    return p


def frame(name, size, pos=U(0, 0, 0, 0), anchor=(0, 0), bg=None, children=None, **extra):
    extra.setdefault("BackgroundTransparency", 1 if bg is None else 0)
    p = base(size, pos, anchor, **extra)
    if bg is not None:
        p["BackgroundColor3"] = bg
    return node(name, "Frame", p, children)


def studs(tint, transparency=0, tile=48, r=RADIUS):
    # Buttons get a tinted stud texture (Lego-style toy buttons); panels stay flat.
    if not STUD_TEXTURE:
        return None
    return node("Studs", "ImageLabel", base(U(1, 0, 1, 0), BackgroundTransparency=1, Image=img("Stud"), ScaleType="Tile",
                                           TileSize=U(0, tile, 0, tile), ImageColor3=tint, ImageTransparency=transparency, ZIndex=0),
                [corner(r)])


def plate(name, size, pos=U(0, 0, 0, 0), anchor=(0, 0), tint=SURFACE, children=None, stud=0, r=RADIUS, stroke=STROKE, **extra):
    """Panel: flat fill with a soft top-to-bottom shade and a thick dark outline."""
    kids = [corner(r), border(INK, stroke) if stroke else None,
            node("Shade", "UIGradient", {"Color": {"keypoints": [[0, WHITE], [1, "#DCE0E7"]]}, "Rotation": 90})]
    return frame(name, size, pos, anchor, bg=tint, children=kids + (children or []), **extra)


def text(name, value, size, pos=U(0, 0, 0, 0), anchor=(0, 0), ts=20, color=WHITE, display=False, heavy=False,
         stroke=None, xa="Center", ya="Center", children=None, **extra):
    p = base(size, pos, anchor, BackgroundTransparency=1, Text=value, TextColor3=color, TextSize=ts,
             TextXAlignment=xa, TextYAlignment=ya, TextWrapped=True, ZIndex=2)
    if display:
        p["FontFace"] = DISPLAY
    else:
        p["FontFace"] = BODY_HEAVY if heavy else BODY
    p.update(extra)
    kids = []
    if stroke:
        kids.append(text_stroke(stroke))
    return node(name, "TextLabel", p, kids + (children or []))


def icon(name, image, px, pos=U(0, 0, 0, 0), anchor=(0, 0), **extra):
    extra.setdefault("ZIndex", 3)
    return node(name, "ImageLabel", base(U(0, px, 0, px), pos, anchor, BackgroundTransparency=1, Image=img(image),
                                         ScaleType="Fit", **extra))


def button(name, size, pos=U(0, 0, 0, 0), anchor=(0, 0), color=SUCCESS, label=None, ts=24, label_color=WHITE,
           ico=None, ico_px=36, children=None, stud=None, r=RADIUS, stroke=STROKE, dark="#BCC4D4", **extra):
    """A raised button: colour fill, navy outline, lighter top edge, optional icon + label.
    Controllers set text through the child Label (Ui.setText)."""
    kids = [corner(r), border(INK, stroke) if stroke else None, shine(dark)]
    see_through = extra.get("BackgroundTransparency", 0) > 0
    if stud is None and not see_through:
        stud = BUTTON_STUD
    if stud is not None and stud is not False:
        kids.append(studs(color, stud, r=r))
        # Thin light line just inside the outline, like the toy buttons in Dev's reference.
        kids.append(frame("Bevel", U(1, -6, 1, -6), U(0.5, 0, 0.5, 0), (0.5, 0.5), ZIndex=0, children=[
            node("Stroke", "UIStroke", {"Color": WHITE, "Thickness": 2, "Transparency": 0.55, "ApplyStrokeMode": "Border",
                                        "LineJoinMode": "Miter"}),
        ]))
    if ico:
        kids.append(icon("Icon", ico, ico_px, U(0, 8, 0.5, 0), (0, 0.5)))
    if label is not None:
        left = ico_px + 10 if ico else 6
        kids.append(text("Label", label, U(1, -(left + 6), 1, 0), U(0, left, 0, 0), ts=ts, color=label_color, display=True,
                         stroke=2.5 if label_color == WHITE else None, xa="Center" if not ico else "Left"))
    p = base(size, pos, anchor, BackgroundColor3=color, Text="", AutoButtonColor=False, ZIndex=1)
    p.update(extra)
    return node(name, "TextButton", p, kids + (children or []))


BADGE_RED = "#FF2E4D"


def badge(z=6, px=30):
    """Count badge (Pet Sim style but square): red, white outline, white number. Controllers
    set it with Ui.setBadge, which widens it for 2-3 digits and pops it when it changes."""
    return frame("Badge", U(0, px, 0, px), U(1, 9, 0, -9), (1, 0), bg=BADGE_RED, Visible=False, ZIndex=z, children=[
        node("Stroke", "UIStroke", {"Color": WHITE, "Thickness": 2.5, "ApplyStrokeMode": "Border", "LineJoinMode": "Miter"}),
        text("Label", "1", U(1, 0, 1, 0), ts=px - 11, display=True, stroke=2, ZIndex=z + 1),
    ])


def close_button():
    return button("Close", U(0, 52, 0, 52), U(1, -6, 0, 6), (0.5, 0.5), color=DANGER, label="X", ts=30, ZIndex=5)


def screen(children, order=0, enabled=True, inset=False):
    return {"className": "ScreenGui",
            "properties": {"ResetOnSpawn": False, "ZIndexBehavior": "Sibling", "Enabled": enabled, "DisplayOrder": order,
                           "IgnoreGuiInset": inset, "ScreenInsets": "CoreUISafeInsets"},
            "children": children}


def dim():
    # Oversized and centred so it also covers the top bar and safe-area insets (no lighter
    # strips around the edges).
    return node("Dim", "TextButton", base(U(1, 400, 1, 400), U(0.5, 0, 0.5, 0), (0.5, 0.5), BackgroundColor3="#0B0E1E",
                                          BackgroundTransparency=0.6, Text="", AutoButtonColor=False, ZIndex=0))


WIN_W, WIN_H = 820, 520  # every modal window is this size (Dev: mixed sizes looked off)
POP_W, POP_H = 480, 360  # small popups (Welcome back, Tutorial done)


def recentre(children, w, h, W, H):
    """Content laid out for a w x h window, moved so it sits centred in a W x H one: each
    child keeps its old size and its old distance from the centre."""
    dx, dy = (W - w) / 2, (H - h) / 2
    out = []
    for c in children:
        if not c:
            continue
        c = json.loads(json.dumps(c))
        p = c.get("properties", {})
        if "Position" in p:
            (sx, ox), (sy, oy) = p["Position"]
            p["Position"] = [[sx, ox + dx * (1 - 2 * sx)], [sy, oy + dy * (1 - 2 * sy)]]
        if "Size" in p:
            (sx, ox), (sy, oy) = p["Size"]
            p["Size"] = [[sx, ox - 2 * dx * sx], [sy, oy - 2 * dy * sy]]
        out.append(c)
    return out


def zoom(children, k):
    """Content drawn for a small window, scaled up by k (offsets, text, strokes, layouts)
    so it fills the standard window instead of floating small in the middle."""
    def scale_udim2(v):
        (sx, ox), (sy, oy) = v
        return [[sx, round(ox * k, 1)], [sy, round(oy * k, 1)]]

    def walk(n):
        n = json.loads(json.dumps(n))
        p = n.get("properties", {})
        for key in ("Size", "Position", "CellSize", "CellPadding"):
            if key in p:
                p[key] = scale_udim2(p[key])
        for key in ("TextSize", "Thickness", "MaxTextSize", "MinTextSize"):
            if key in p:
                p[key] = round(p[key] * k, 1)
        if "Padding" in p and isinstance(p["Padding"], list):
            p["Padding"] = [p["Padding"][0], round(p["Padding"][1] * k, 1)]
        for key in ("PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom"):
            if key in p:
                p[key] = [p[key][0], round(p[key][1] * k, 1)]
        if "children" in n:
            n["children"] = [walk(c) for c in n["children"]]
        return n
    return [walk(c) for c in children if c]


def window(w, h, title, ico, children, header=HEADER, popup=False, scale=1.0):
    """Modal window: white stud body, coloured stud header strip, red X top-right. Always
    WIN_W x WIN_H (or POP_W x POP_H for popups); smaller layouts are centred inside."""
    W, H = (POP_W, POP_H) if popup else (WIN_W, WIN_H)
    if scale != 1.0:
        children = zoom(children, scale)
        w, h = w * scale, h * scale
    if (w, h) != (W, H):
        children = recentre(children, w, h, W, H)
    return plate("Window", U(0, W, 0, H), U(0.5, 0, 0.5, 0), (0.5, 0.5), SURFACE, [
        autoscale(),
        plate("Header", U(1, 0, 0, 64), tint=header, children=[
            icon("Icon", ico, 48, U(0, 10, 0.5, 0), (0, 0.5)),
            text("Title", title, U(1, -150, 1, 0), U(0, 68, 0, 0), ts=30, display=True, stroke=3, xa="Left"),
        ]),
        close_button(),
    ] + children)


def scroller(name, size, pos, children, canvas_y=True):
    return node(name, "ScrollingFrame", base(size, pos, BackgroundTransparency=1, ScrollBarThickness=8, ScrollBarImageColor3=INK,
                                             CanvasSize=U(0, 0, 0, 0), AutomaticCanvasSize="Y" if canvas_y else "X",
                                             ScrollingDirection="Y" if canvas_y else "X", ZIndex=2), children)


def write(name, tree):
    with open(os.path.join(OUT, name + ".model.json"), "w") as f:
        json.dump(tree, f, indent=1, ensure_ascii=False)
        f.write("\n")


# ---------------------------------------------------------------- HUD
def rail_tile(name, label, ico, color, order):
    return button(name, U(0, 84, 0, 84), color=color, LayoutOrder=order, children=[
        # Label inside the tile (Dev: text hanging off the bottom looked out of bounds).
        icon("Icon", ico, 58, U(0.5, 0, 0, 4), (0.5, 0)),
        text("Label", label, U(1, -10, 0, 20), U(0.5, 0, 1, -4), (0.5, 1), ts=17, display=True, stroke=2.5,
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 17, "MinTextSize": 9})]),
        badge(),
    ])


def pill(name, label, ico, color, order):
    return button(name, U(0, 136, 0, 52), color=color, label=label, ts=21, ico=ico, ico_px=40, LayoutOrder=order)


def hot_slot(name, key, ico, label, order):
    """Roblox-backpack style slot: dark see-through square, number top-left, big icon."""
    return button(name, U(0, 84, 0, 84), color="#0B0E1E", stroke=3, BackgroundTransparency=0.35, LayoutOrder=order, children=[
        icon("Icon", ico, 70, U(0.5, 0, 0.5, -6), (0.5, 0.5)),
        text("Name", label, U(1, -6, 0, 18), U(0.5, 0, 1, -3), (0.5, 1), ts=13, color=WHITE, display=True, stroke=2, ZIndex=4),
        frame("Key", U(0, 22, 0, 22), U(0, 3, 0, 2), ZIndex=4, children=[
            text("Label", key, U(1, 0, 1, 0), ts=16, display=True, stroke=2, xa="Left", ya="Top", ZIndex=5),
        ]),
    ])


def zone_row(zone_id, title, order):
    return button("Zone_" + zone_id, U(1, 0, 0, 50), color=HEADER, stroke=3, LayoutOrder=order, children=[
        icon("Icon", "Zones", 36, U(0, 8, 0.5, 0), (0, 0.5)),
        text("Name", title, U(0.6, -50, 1, 0), U(0, 52, 0, 0), ts=18, display=True, stroke=2.5, xa="Left"),
        text("Price", "", U(0.4, -10, 1, 0), U(1, -10, 0, 0), (1, 0), ts=16, heavy=True, stroke=2.5, xa="Right"),
    ])


def hud():
    rail = frame("Rail", U(0, 180, 0, 304), U(0, 14, 0.5, -30), (0, 0.5), children=[
        autoscale(),
        node("Layout", "UIGridLayout", {"CellSize": U(0, 84, 0, 84), "CellPadding": U(0, 12, 0, 26), "SortOrder": "LayoutOrder"}),
        rail_tile("ShopButton", "Shop", "Shop", PREMIUM, 1),
        rail_tile("IndexButton", "Index", "Index", "#4CC3FF", 2),
        rail_tile("UpgradesButton", "Upgrades", "Upgrade", "#FF9A3C", 3),
        rail_tile("RebirthButton", "Rebirth", "Rebirth", REBIRTH, 4),
        rail_tile("RewardsButton", "Daily", "Daily", "#FF5FA2", 5),
        rail_tile("GiftsButton", "Gifts", "Gift", "#3DDC5A", 6),
    ])
    pills = frame("Pills", U(0, 432, 0, 52), U(0.5, 0, 0, 6), (0.5, 0), children=[
        autoscale(), hlist(12),
        pill("BaseButton", "Base", "Base", PILL_BASE, 1),
        pill("SellButton", "Sell", "Sell", PILL_SELL, 2),
        pill("ZonesButton", "Zones", "Zones", PILL_ZONES, 3),
    ])
    # Fixed height: a UIListLayout directly in a plate would also stack the Studs image.
    picker = plate("ZonePicker", U(0, 330, 0, 348), U(0.5, 0, 0, 66), (0.5, 0), SURFACE, Visible=False, ZIndex=6,
                   children=[
                       autoscale(),
                       frame("List", U(1, -20, 1, -20), U(0, 10, 0, 10), children=[
                           vlist(8),
                           text("Title", "Teleport", U(1, 0, 0, 28), ts=24, color=INK, display=True, LayoutOrder=0),
                           zone_row("Landing", "Landing Site", 1),
                           zone_row("Crater", "Crater", 2),
                           zone_row("DarkSide", "Dark Side", 3),
                           zone_row("Mars", "Mars Plains", 4),
                           zone_row("Europa", "Europa Ice", 5),
                       ]),
                   ])
    # Moon Clean: small title, a thick bar with a moving shine, the % on the right. Turns
    # orange for the Meteor Shower countdown and the shower itself (HudController).
    moon = plate("MoonPanel", U(0, 380, 0, 52), U(0.5, 0, 0, 66), (0.5, 0), BG, stud=None, stroke=3, children=[
        autoscale(),
        icon("Icon", "Star", 38, U(0, 7, 0.5, 0), (0, 0.5), ZIndex=4),
        text("Title", "MOON CLEAN", U(0, 200, 0, 16), U(0, 52, 0, 4), ts=13, color=ACCENT, display=True, xa="Left", stroke=1.5),
        text("Value", "0%", U(0, 120, 0, 16), U(1, -10, 0, 4), (1, 0), ts=13, color=WHITE, display=True, xa="Right", stroke=1.5),
        frame("Bar", U(1, -62, 0, 20), U(0, 52, 1, -8), (0, 1), bg="#0B0E1E", children=[
            border(INK, 2),
            frame("Fill", U(0.3, 0, 1, 0), bg=ACCENT, ClipsDescendants=True, children=[
                node("Shade", "UIGradient", {"Color": {"keypoints": [[0, WHITE], [1, "#B8C4D8"]]}, "Rotation": 90}),
                frame("Shine", U(0, 40, 1, 0), U(-0.2, 0, 0, 0), bg=WHITE, BackgroundTransparency=0.55, Rotation=0, ZIndex=3),
            ]),
            node("Ticks", "Frame", base(U(1, 0, 1, 0), BackgroundTransparency=1, ZIndex=4), [
                frame(f"Tick{i}", U(0, 2, 1, 0), U(i / 4, -1, 0, 0), bg="#0B0E1E", BackgroundTransparency=0.4, ZIndex=4)
                for i in (1, 2, 3)
            ]),
        ]),
        # Kept for older code paths that set one line of text.
        text("Label", "", U(1, -58, 0, 16), U(0, 52, 0, 4), ts=13, display=True, Visible=False),
    ])
    # Active boosts (server luck, 2x cash): chips stacked in the bottom-right corner.
    # Phones move them to the top right (HudController), clear of the jump button.
    # Boost chips: no box, just a small icon and "2x 14:52". Hover (or tap) shows what the
    # boost does in BoostTip.
    boosts = frame("Boosts", U(0, 220, 0, 180), U(1, -14, 1, -14), (1, 1), children=[
        autoscale(), vlist(2, "Right", "Bottom"),
        node("Template", "TextButton", base(U(0, 0, 0, 28), BackgroundTransparency=1, Text="", AutomaticSize="X",
                                           AutoButtonColor=False, Visible=False, ZIndex=2),
             [hlist(4, "Right"),
              icon("Icon", "Luck", 26, LayoutOrder=1),
              text("Label", "", U(0, 0, 1, 0), ts=17, display=True, stroke=2, AutomaticSize="X", TextWrapped=False,
                   LayoutOrder=2)]),
    ])
    boost_tip = plate("BoostTip", U(0, 260, 0, 0), U(1, -14, 1, -200), (1, 1), BG, stud=None, stroke=3, AutomaticSize="Y",
                      Visible=False, ZIndex=8, children=[
                          autoscale(), padding(10, 10, 8, 8), vlist(2, "Left", "Top"),
                          text("Title", "", U(1, 0, 0, 24), ts=19, color=PREMIUM, display=True, stroke=2, xa="Left", LayoutOrder=1,
                               ZIndex=9),
                          text("Text", "", U(1, 0, 0, 0), ts=15, color=WHITE, heavy=True, xa="Left", ya="Top", AutomaticSize="Y",
                               LayoutOrder=2, ZIndex=9),
                      ])
    # Toasts: no box, just bold text with a thick outline and an optional icon, popping in
    # under the Moon bar. The same message twice turns into "x2" instead of stacking.
    toasts = frame("Toasts", U(0, 640, 0, 220), U(0.5, 0, 0, 132), (0.5, 0), children=[
        autoscale(), vlist(2),
        node("Template", "Frame", base(U(0, 0, 0, 34), BackgroundTransparency=1, AutomaticSize="X", Visible=False), [
            hlist(6),
            icon("Icon", "Cash", 30, LayoutOrder=1, Visible=False),
            text("Text", "", U(0, 0, 1, 0), ts=24, display=True, stroke=3, AutomaticSize="X", TextWrapped=False, LayoutOrder=2),
            text("Count", "", U(0, 0, 1, 0), ts=20, color=PREMIUM, display=True, stroke=3, AutomaticSize="X", TextWrapped=False,
                 LayoutOrder=3, Visible=False),
        ]),
    ])
    announcement = plate("Announcement", U(0, 0, 0, 64), U(0.5, 0, 0.3, 0), (0.5, 0.5), BG, stud=0.5, AutomaticSize="X", Visible=False,
                         children=[
                             autoscale(), padding(24, 24, 0),
                             text("Text", "", U(0, 0, 1, 0), ts=34, color=PREMIUM, display=True, stroke=3, AutomaticSize="X", TextWrapped=False),
                         ])
    wallet = frame("Wallet", U(0, 270, 0, 130), U(0, 14, 1, -14), (0, 1), children=[
        autoscale(), vlist(10, "Left", "Bottom"),
        plate("CashPanel", U(0, 270, 0, 64), tint=SURFACE, LayoutOrder=1, children=[
            icon("Icon", "Cash", 58, U(0, 4, 0.5, 0), (0, 0.5)),
            text("Cash", "$0", U(1, -124, 0, 38), U(0, 64, 0, 4), ts=28, color=INK, display=True, xa="Left",
                 TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 28, "MinTextSize": 14})]),
            text("Income", "+$0/s", U(1, -124, 0, 20), U(0, 64, 0, 38), ts=17, color="#1E9E3A", heavy=True, xa="Left"),
            button("PlusButton", U(0, 44, 0, 44), U(1, -10, 0.5, 0), (1, 0.5), color=SUCCESS, label="+", ts=34, stroke=3),
        ]),
        plate("BackpackPanel", U(0, 270, 0, 56), tint=SURFACE, LayoutOrder=2, children=[
            icon("Icon", "Dust", 50, U(0, 5, 0.5, 0), (0, 0.5)),
            frame("Bar", U(1, -72, 0, 28), U(0, 60, 0.5, 0), (0, 0.5), bg=BG, children=[
                corner(8),
                frame("Fill", U(0.2, 0, 1, 0), bg="#E9C98B", children=[corner(8)]),
                text("Amount", "0 / 50", U(1, 0, 1, 0), ts=17, heavy=True, stroke=2.5, ZIndex=3),
            ]),
            # Sits on the right end of the bar, inside the panel.
            plate("Full", U(0, 58, 0, 22), U(1, -16, 0.5, 0), (1, 0.5), DANGER, stroke=2.5, stud=None, Visible=False, ZIndex=4, children=[
                text("Label", "FULL", U(1, 0, 1, 0), ts=16, display=True, stroke=2, ZIndex=5),
            ]),
        ]),
    ])
    next_tool = plate("NextTool", U(0, 230, 0, 176), tint=SURFACE, LayoutOrder=1, children=[
        plate("Header", U(1, 0, 0, 36), tint=HEADER, children=[
            text("Title", "NEXT TOOL", U(1, 0, 1, 0), ts=22, display=True, stroke=2.5),
        ]),
        icon("Icon", "Tool", 54, U(0, 8, 0, 42)),
        text("ToolName", "Broom", U(1, -72, 0, 26), U(0, 66, 0, 42), ts=22, color=INK, display=True, xa="Left"),
        text("Hint", "", U(1, -72, 0, 36), U(0, 66, 0, 68), ts=14, color=SUB, xa="Left", ya="Top"),
        button("Button", U(1, -20, 0, 48), U(0.5, 0, 1, -10), (0.5, 1), color=SUCCESS, label="Buy", ts=24),
    ])
    right = frame("Right", U(0, 230, 0, 240), U(1, -14, 0.5, 0), (1, 0.5), children=[
        autoscale(), vlist(10, "Right", "Center"),
        next_tool,
        button("AutoButton", U(0, 230, 0, 50), color=BG, label="Auto: OFF", ts=24, ico="Auto", ico_px=40, LayoutOrder=3, Visible=False,
               dark="#9AA3B8"),
    ])
    sweep = button("SweepButton", U(0, 108, 0, 108), U(1, -196, 1, -28), (1, 1), color=SUCCESS, r=54, Visible=False, children=[
        autoscale(),
        icon("Icon", "Tool", 64, U(0.5, 0, 0, 6), (0.5, 0)),
        text("Label", "SWEEP", U(1, 0, 0, 28), U(0.5, 0, 1, -8), (0.5, 1), ts=22, display=True, stroke=2.5),
    ])
    # Own hotbar (the default Roblox backpack is hidden): slot 1 = tool, slot 2 = car.
    bag = hot_slot("BagSlot", "3", "Backpack", "Bag", 3)
    bag["children"].append(badge())
    hotbar = frame("Hotbar", U(0, 290, 0, 88), U(0.5, 0, 1, -12), (0.5, 1), children=[
        autoscale(), hlist(8, "Center", "Bottom"),
        hot_slot("ToolSlot", "1", "Tool", "Toothbrush", 1),
        hot_slot("CarSlot", "2", "Vehicle", "No car", 2),
        bag,
    ])
    # Tutorial step card above the hotbar: "STEP 3/9", what to do, a progress bar. After the
    # tutorial the same card shows nudges ("An egg is ready!") without the step and bar.
    hint = plate("Hint", U(0, 480, 0, 74), U(0.5, 0, 1, -122), (0.5, 1), BG, stud=0.5, Visible=False, ZIndex=21, children=[
        autoscale(),
        icon("Icon", "Star", 52, U(0, 10, 0.5, 0), (0, 0.5)),
        text("Step", "STEP 1/9", U(1, -84, 0, 18), U(0, 72, 0, 6), ts=14, color=PREMIUM, display=True, xa="Left", stroke=1.5),
        text("Text", "", U(1, -84, 0, 36), U(0, 72, 0, 24), ts=20, color=WHITE, display=True, stroke=2.5, xa="Left",
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 21, "MinTextSize": 12})]),
        frame("Bar", U(1, -84, 0, 7), U(0, 72, 1, -9), bg="#2A3260", children=[
            frame("Fill", U(0.1, 0, 1, 0), bg=ACCENT),
        ]),
        frame("Done", U(1, 0, 1, 0), bg=SUCCESS, BackgroundTransparency=1, ZIndex=5, children=[
            text("Label", "✓  Nice!", U(1, 0, 1, 0), ts=30, display=True, stroke=3, TextTransparency=1, ZIndex=6),
        ]),
    ])
    # Tutorial spotlight: the screen dims except a cut-out around one button (four dark
    # frames around it), a pulsing ring on the button and a bouncing arrow above it.
    # TutorialController lays it out. Frames are not Active, so clicks go through.
    dark = dict(bg="#05070F", BackgroundTransparency=0.45, ZIndex=18)
    spot = frame("Spot", U(1, 0, 1, 0), Visible=False, ZIndex=18, children=[
        frame("Top", U(0, 0, 0, 0), **dark),
        frame("Bottom", U(0, 0, 0, 0), **dark),
        frame("Left", U(0, 0, 0, 0), **dark),
        frame("Right", U(0, 0, 0, 0), **dark),
        frame("Ring", U(0, 0, 0, 0), ZIndex=19, children=[border(PREMIUM, 4)]),
    ])
    pointer = node("Pointer", "ImageLabel", base(U(0, 56, 0, 56), anchor=(0.5, 1), BackgroundTransparency=1, Image=img("ArrowDown"),
                                                 Visible=False, ZIndex=20))
    # Sweep combo: a big tilted "x2.4" next to your character that pops every time it goes up,
    # changes colour as it climbs, and a thin bar for the time left before it drops.
    combo = frame("Combo", U(0, 200, 0, 96), U(0.5, 120, 0.5, -40), (0, 0.5), Visible=False, Rotation=-6, children=[
        autoscale(),
        text("Title", "COMBO", U(1, 0, 0, 22), ts=18, color=WHITE, display=True, stroke=2.5, xa="Left"),
        text("Label", "x1.0", U(1, 0, 0, 56), U(0, 0, 0, 18), ts=52, color=PREMIUM, display=True, stroke=4, xa="Left"),
        frame("Bar", U(0, 120, 0, 8), U(0, 2, 0, 80), bg="#0B0E1E", children=[
            border(INK, 2),
            frame("Fill", U(1, 0, 1, 0), bg=PREMIUM),
        ]),
    ])
    write("Hud", screen([rail, pills, moon, boosts, boost_tip, toasts, announcement, wallet, right, sweep, hotbar, hint, combo, picker,
                         spot, pointer], order=1))


# ---------------------------------------------------------------- Shop
SHOP_CELL = (250, 236)  # 3 cards per row in the 778 px wide list


def shop():
    """One scrolling page (Steal an Egg style): special offers on top, then server boosts,
    gamepasses, tools, eggs and cash packs at the bottom. ShopController clones Section and
    Card for each block and sizes each section to its rows."""
    featured = plate("Featured", U(1, 0, 0, 160), tint=BG, stud=None, LayoutOrder=1, Visible=False, children=[
        node("Banner", "ImageLabel", base(U(1, 0, 1, 0), BackgroundTransparency=1, Image=img("BannerStarter"), ScaleType="Crop", ZIndex=1)),
        plate("Tag", U(0, 150, 0, 30), U(0, 14, 0, 12), tint=BADGE_RED, stroke=3, stud=None, ZIndex=3, children=[
            text("Label", "SPECIAL OFFER", U(1, 0, 1, 0), ts=16, display=True, stroke=2, ZIndex=4),
        ]),
        text("Title", "Starter Pack", U(0.6, 0, 0, 40), U(0, 16, 0, 46), ts=34, display=True, stroke=3, xa="Left", ZIndex=3),
        text("Desc", "", U(0.6, 0, 0, 44), U(0, 16, 0, 88), ts=18, heavy=True, stroke=2.5, xa="Left", ya="Top", ZIndex=3,
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 18, "MinTextSize": 11})]),
        text("Note", "One time only", U(0, 170, 0, 22), U(1, -14, 0, 14), (1, 0), ts=16, display=True, stroke=2.5, xa="Right",
             color=PREMIUM, ZIndex=3),
        button("Buy", U(0, 170, 0, 56), U(1, -14, 1, -14), (1, 1), color=PREMIUM, label="", ts=28, label_color=INK, ZIndex=3),
    ])
    # A limited offer the game made you (backpack full, rare egg growing...): stays here for a while.
    offer = plate("Offer", U(1, 0, 0, 108), tint="#FF5FA2", stud=0.25, Visible=False, children=[
        node("Glow", "ImageLabel", base(U(0, 150, 0, 150), U(0, 52, 0.5, 0), (0.5, 0.5), BackgroundTransparency=1, Image=img("Glow"),
                                        ImageColor3=WHITE, ImageTransparency=0.35, ZIndex=1)),
        icon("Icon", "Star", 82, U(0, 52, 0.5, 0), (0.5, 0.5)),
        plate("Tag", U(0, 150, 0, 26), U(0, 104, 0, 10), tint=BADGE_RED, stroke=3, stud=None, ZIndex=3, children=[
            text("Label", "LIMITED OFFER", U(1, 0, 1, 0), ts=15, display=True, stroke=2, ZIndex=4),
        ]),
        text("Timer", "", U(0, 120, 0, 26), U(0, 262, 0, 10), ts=17, display=True, stroke=2.5, xa="Left", color=PREMIUM, ZIndex=3),
        text("Title", "", U(1, -310, 0, 30), U(0, 104, 0, 38), ts=24, display=True, stroke=3, xa="Left", ZIndex=3,
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 24, "MinTextSize": 12})]),
        text("Desc", "", U(1, -310, 0, 34), U(0, 104, 0, 68), ts=15, heavy=True, stroke=2, xa="Left", ya="Top", ZIndex=3,
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 15, "MinTextSize": 10})]),
        button("Buy", U(0, 170, 0, 56), U(1, -14, 0.5, 0), (1, 0.5), color=PREMIUM, label="", ts=26, label_color=INK, ZIndex=3),
    ])
    cw, ch = SHOP_CELL
    section = frame("Section", U(1, 0, 0, 300), Visible=False, children=[
        plate("Header", U(1, 0, 0, 44), tint=HEADER, stud=0.3, children=[
            icon("Icon", "Star", 34, U(0, 8, 0.5, 0), (0, 0.5)),
            text("Title", "Section", U(0.6, 0, 1, 0), U(0, 50, 0, 0), ts=24, display=True, stroke=3, xa="Left"),
            text("Note", "", U(0.5, -20, 1, 0), U(1, -12, 0, 0), (1, 0), ts=15, display=True, stroke=2.5, xa="Right", color=PREMIUM),
        ]),
        frame("Grid", U(1, 0, 1, -54), U(0, 0, 0, 54), children=[
            node("Layout", "UIGridLayout", {"CellSize": U(0, cw, 0, ch), "CellPadding": U(0, 12, 0, 12), "SortOrder": "LayoutOrder",
                                            "HorizontalAlignment": "Left"}),
        ]),
    ])
    card = plate("Card", U(0, cw, 0, ch), tint=WHITE, stud=0.2, Visible=False, children=[
        node("Glow", "ImageLabel", base(U(0, 140, 0, 140), U(0.5, 0, 0, 46), (0.5, 0.5), BackgroundTransparency=1, Image=img("Glow"),
                                        ImageColor3=PREMIUM, ImageTransparency=0.45, ZIndex=1)),
        icon("Icon", "Shop", 76, U(0.5, 0, 0, 8), (0.5, 0)),
        plate("Tag", U(0, 110, 0, 26), U(0, 8, 0, 8), tint=BADGE_RED, stroke=3, stud=None, Visible=False, ZIndex=4, children=[
            text("Label", "BEST", U(1, 0, 1, 0), ts=15, display=True, stroke=2, ZIndex=5),
        ]),
        # Name and Desc shrink to fit their boxes, so long names ("16x Server Luck (15 min)")
        # and descriptions never run into the Buy button.
        text("Name", "Item", U(1, -16, 0, 40), U(0.5, 0, 0, 86), (0.5, 0), ts=20, color=INK, display=True,
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 20, "MinTextSize": 12})]),
        text("Desc", "", U(1, -16, 0, 46), U(0.5, 0, 0, 128), (0.5, 0), ts=14, color=SUB, heavy=True, ya="Top",
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 14, "MinTextSize": 9})]),
        button("Buy", U(1, -20, 0, 44), U(0.5, 0, 1, -10), (0.5, 1), color=SUCCESS, label="", ts=22),
        button("Gift", U(0, 44, 0, 44), U(1, -10, 1, -10), (1, 1), color="#FF7EB6", ico="Gift", ico_px=34, Visible=False),
    ])
    lst = scroller("List", U(1, -24, 1, -86), U(0, 12, 0, 74), [vlist(14), padding(4, 14, 4, 10), featured, offer, section])
    empty = text("Empty", "Nothing here right now. Check back soon!", U(1, -40, 0, 60), U(0.5, 0, 0.5, 0), (0.5, 0.5), ts=20, color=SUB,
                 heavy=True, Visible=False)
    gift_row = button("Template", U(1, -10, 0, 46), color=HEADER, label="Player", ts=18, stroke=3, Visible=False)
    gift = plate("GiftPicker", U(0, 380, 0, 330), U(0.5, 0, 0.5, 20), (0.5, 0.5), SURFACE, Visible=False, ZIndex=10, children=[
        plate("Header", U(1, 0, 0, 52), tint="#FF7EB6", children=[
            icon("Icon", "Gift", 38, U(0, 8, 0.5, 0), (0, 0.5)),
            text("Title", "Gift to...", U(1, -110, 1, 0), U(0, 54, 0, 0), ts=28, display=True, stroke=3, xa="Left"),
        ]),
        button("Close", U(0, 44, 0, 44), U(1, -6, 0, 6), (0.5, 0.5), color=DANGER, label="X", ts=26, ZIndex=11),
        scroller("List", U(1, -24, 1, -72), U(0, 12, 0, 62), [vlist(8), padding(2), gift_row]),
        text("Empty", "No one else is here yet.", U(1, -24, 0, 40), U(0, 12, 0.5, 0), ts=18, color=SUB, heavy=True, Visible=False),
    ])
    write("Shop", screen([dim(), window(WIN_W, WIN_H, "Shop", "Shop", [lst, card, empty, gift], header="#E9A21F")],
                         order=10, enabled=False))


# ---------------------------------------------------------------- Index
def bar(name, size, pos, anchor, fill, label, ts=26):
    return frame(name, size, pos, anchor, bg="#0B0E1E", children=[
        border(INK, 3),
        frame("Fill", U(0.3, 0, 1, 0), bg=fill, children=[]),
        text("Label", label, U(1, 0, 1, 0), ts=ts, display=True, stroke=3, ZIndex=4),
    ])


def index():
    """Pet index (Steal an Egg style): a zone panel on the left, rarity-coloured cards,
    the picked pet on the right, zone progress and total progress bars."""
    card = button("Template", U(0, 0, 0, 0), color="#BEBEBE", stroke=3, Visible=False, children=[
        node("Viewport", "ViewportFrame", base(U(1, -8, 1, -30), U(0.5, 0, 1, -4), (0.5, 1), BackgroundTransparency=1,
                                               Ambient="#C8D0E8", LightColor=WHITE, LightDirection=[-1, -1, -1], ZIndex=2)),
        text("Name", "???", U(1, -6, 0, 26), U(0.5, 0, 0, 2), (0.5, 0), ts=18, display=True, stroke=2.5, ZIndex=4,
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 19, "MinTextSize": 9})]),
    ])
    body = plate("Body", U(1, -24, 1, -156), U(0, 12, 0, 76), tint=BG, stud=0.6, children=[
        plate("Zone", U(0, 150, 1, -84), U(0, 10, 0, 10), tint="#3B4FA8", stud=0.2, children=[
            text("Name", "Landing Site", U(1, -10, 0, 70), U(0.5, 0, 0, 8), (0.5, 0), ts=26, display=True, stroke=3),
            icon("Icon", "Zones", 90, U(0.5, 0, 0.5, 0), (0.5, 0.5)),
            button("Prev", U(0, 54, 0, 46), U(0, 10, 1, -10), (0, 1), color=HEADER, label="<", ts=26),
            button("Next", U(0, 54, 0, 46), U(1, -10, 1, -10), (1, 1), color=HEADER, label=">", ts=26),
        ]),
        scroller("Grid", U(1, -410, 1, -84), U(0, 170, 0, 10), [
            node("Layout", "UIGridLayout", {"CellSize": U(0, 118, 0, 132), "CellPadding": U(0, 8, 0, 8), "SortOrder": "LayoutOrder",
                                            "HorizontalAlignment": "Left"}),
            padding(3), card,
        ]),
        bar("Progress", U(1, -410, 0, 52), U(0, 170, 1, -12), (0, 1), SUCCESS, "0/7"),
        plate("Detail", U(0, 220, 1, -20), U(1, -10, 0, 10), (1, 0), "#4A5170", stud=0.5, children=[
            node("Viewport", "ViewportFrame", base(U(1, -16, 0, 150), U(0.5, 0, 0, 8), (0.5, 0), BackgroundTransparency=1,
                                                   Ambient="#C8D0E8", LightColor=WHITE, LightDirection=[-1, -1, -1], ZIndex=2)),
            text("Name", "", U(1, -12, 0, 32), U(0.5, 0, 0, 160), (0.5, 0), ts=26, display=True, stroke=3,
                 TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 26, "MinTextSize": 12})]),
            text("Rarity", "", U(1, -12, 0, 26), U(0.5, 0, 0, 192), (0.5, 0), ts=22, display=True, stroke=3),
            text("Income", "", U(1, -12, 0, 28), U(0.5, 0, 0, 220), (0.5, 0), ts=24, color="#7CFF8C", display=True, stroke=3),
            text("Hint", "", U(1, -16, 0, 56), U(0.5, 0, 1, -8), (0.5, 1), ts=14, color="#E0E4F0", heavy=True, ya="Bottom"),
        ]),
    ])
    total = bar("Total", U(1, -24, 0, 56), U(0, 12, 1, -12), (0, 1), "#4CC3FF", "Unlocked: 0/47", ts=30)
    write("Index", screen([dim(), window(WIN_W, WIN_H, "Pet Index", "Index", [body, total], header="#4CC3FF")], order=10, enabled=False))


# ---------------------------------------------------------------- Inventory
SEE = "#0B0E1E"  # see-through dark (native backpack look)


def inv_tab(name, label, ico, order):
    return button("Tab" + name, U(0, 76, 0, 76), color=SEE, stroke=3, BackgroundTransparency=0.3, LayoutOrder=order, children=[
        text("Label", label, U(1, 0, 0, 22), U(0, 0, 0, 2), ts=17, display=True, stroke=2, ZIndex=4),
        icon("Icon", ico, 50, U(0.5, 0, 1, -2), (0.5, 1)),
    ])


def inventory():
    """Backpack (Steal an Egg style): a see-through grid above the hotbar, filter tabs on
    its left, a search box, and an action card on its right when something is picked."""
    W, H = 640, 316
    tabs = frame("Tabs", U(0, 76, 0, 248), U(0, -10, 0, 0), (1, 0), children=[
        vlist(10, "Center", "Top"),
        inv_tab("Pets", "Pets", "Alien", 1),
        inv_tab("Eggs", "Eggs", "Egg", 2),
        inv_tab("Items", "Items", "Potion", 3),
    ])
    card = frame("Template", U(0, 0, 0, 0), bg="#000000", BackgroundTransparency=0.45, Visible=False, children=[
        border("#FFFFFF", 0, "Stroke"),
        node("Viewport", "ViewportFrame", base(U(1, -6, 1, -20), U(0.5, 0, 0, 2), (0.5, 0), BackgroundTransparency=1,
                                               Ambient="#C8D0E8", LightColor=WHITE, LightDirection=[-1, -1, -1], ZIndex=2)),
        icon("Icon", "Potion", 66, U(0.5, 0, 0, 4), (0.5, 0), Visible=False),
        text("Name", "", U(1, -4, 0, 30), U(0.5, 0, 1, -1), (0.5, 1), ts=13, display=True, stroke=2, ZIndex=4,
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 14, "MinTextSize": 8})]),
        frame("Placed", U(0, 20, 0, 20), U(0, 3, 0, 3), bg=SUCCESS, Visible=False, ZIndex=4, children=[
            border(INK, 2), text("Label", "E", U(1, 0, 1, 0), ts=14, display=True, stroke=1.5, ZIndex=5),
        ]),
        text("Count", "", U(0, 66, 0, 18), U(1, -3, 0, 2), (1, 0), ts=14, display=True, stroke=2, xa="Right", Visible=False, ZIndex=4,
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 15, "MinTextSize": 8})]),
        node("Select", "TextButton", base(U(1, 0, 1, 0), BackgroundTransparency=1, Text="", ZIndex=6)),
    ])
    grid = scroller("Grid", U(1, -24, 1, -74), U(0, 12, 0, 66), [
        node("Layout", "UIGridLayout", {"CellSize": U(0, 96, 0, 96), "CellPadding": U(0, 8, 0, 8), "SortOrder": "LayoutOrder",
                                        "HorizontalAlignment": "Left"}),
        padding(2), card,
    ])
    search = node("Search", "TextBox", base(U(0, 200, 0, 38), U(1, -12, 0, 12), (1, 0), BackgroundColor3="#000000",
                                            BackgroundTransparency=0.45, Text="", PlaceholderText="search", PlaceholderColor3="#9AA3B8",
                                            TextColor3=WHITE, TextSize=20, FontFace=BODY_HEAVY, ClearTextOnFocus=False,
                                            TextXAlignment="Left", ZIndex=3), [padding(10, 10, 0)])
    detail = frame("Detail", U(0, 230, 1, 0), U(1, 10, 0, 0), bg=SEE, BackgroundTransparency=0.15, Visible=False, children=[
        border(INK, 3),
        node("Viewport", "ViewportFrame", base(U(1, -16, 0, 120), U(0.5, 0, 0, 8), (0.5, 0), BackgroundTransparency=1,
                                               Ambient="#C8D0E8", LightColor=WHITE, LightDirection=[-1, -1, -1], ZIndex=2)),
        icon("Icon", "Potion", 100, U(0.5, 0, 0, 16), (0.5, 0), Visible=False),
        text("Name", "", U(1, -12, 0, 28), U(0.5, 0, 0, 128), (0.5, 0), ts=21, display=True, stroke=2.5,
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 22, "MinTextSize": 11})]),
        text("Rarity", "", U(1, -12, 0, 20), U(0.5, 0, 0, 156), (0.5, 0), ts=17, display=True, stroke=2),
        text("Info", "", U(1, -16, 0, 40), U(0.5, 0, 0, 178), (0.5, 0), ts=14, color="#C8D0E8", heavy=True, ya="Top"),
        button("Primary", U(1, -16, 0, 44), U(0.5, 0, 1, -58), (0.5, 1), color=SUCCESS, label="Place", ts=20, Visible=False),
        button("Secondary", U(1, -16, 0, 40), U(0.5, 0, 1, -10), (0.5, 1), color=DANGER, label="Sell", ts=18, Visible=False),
    ])
    win = frame("Window", U(0, W, 0, H), U(0.5, 44, 1, -112), (0.5, 1), bg=SEE, BackgroundTransparency=0.3, children=[
        autoscale(), border(INK, 3),
        text("Title", "All Items", U(0, 300, 0, 32), U(0, 14, 0, 6), ts=28, display=True, stroke=2.5, xa="Left"),
        text("Count", "Pets: 0/60", U(0, 300, 0, 22), U(0, 14, 0, 38), ts=18, display=True, stroke=2, xa="Left"),
        search, grid,
        text("Empty", "Nothing here yet. Sweep dust to find eggs!", U(1, -24, 0, 60), U(0, 12, 0.5, 10), ts=20, color="#C8D0E8",
             heavy=True, Visible=False),
        tabs, detail,
    ])
    write("Inventory", screen([win], order=6, enabled=False))


# ---------------------------------------------------------------- Base panels (Active pets / Growing eggs)
SAND = "#E9D3B0"


def side_button(name, label, ico, color, order):
    return button(name, U(0, 80, 0, 80), color=color, LayoutOrder=order, children=[
        icon("Icon", ico, 56, U(0.5, 0, 0, 4), (0.5, 0)),
        text("Label", label, U(1, -10, 0, 20), U(0.5, 0, 1, -4), (0.5, 1), ts=17, display=True, stroke=2.5,
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 17, "MinTextSize": 9})]),
        badge(),
    ])


def list_window(screen_name, title, ico, header_color, head_button, row_children, footer):
    """Pets / Eggs: a normal window (same size as every other) with a 2-column list."""
    row = plate("Template", U(0, 0, 0, 0), tint="#2E3340", stroke=3, Visible=False, children=[
        node("Viewport", "ViewportFrame", base(U(0, 70, 0, 70), U(0, 4, 0.5, 0), (0, 0.5), BackgroundTransparency=1,
                                               Ambient="#C8D0E8", LightColor=WHITE, LightDirection=[-1, -1, -1], ZIndex=2)),
        text("Name", "", U(1, -214, 0, 28), U(0, 80, 0, 10), ts=21, display=True, stroke=2.5, xa="Left",
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 21, "MinTextSize": 10})]),
        text("Sub", "", U(1, -214, 0, 24), U(0, 80, 0, 40), ts=18, color="#7CFF8C", display=True, stroke=2, xa="Left"),
    ] + row_children)
    body = [
        head_button,
        scroller("List", U(1, -24, 1, -164), U(0, 12, 0, 76), [
            node("Layout", "UIGridLayout", {"CellSize": U(0, 380, 0, 84), "CellPadding": U(0, 10, 0, 10), "SortOrder": "LayoutOrder",
                                            "HorizontalAlignment": "Left"}),
            padding(4, 12, 4, 4), row,
        ]),
        text("Empty", "", U(1, -60, 0, 80), U(0.5, 0, 0.45, 0), (0.5, 0.5), ts=22, color=SUB, heavy=True, Visible=False),
        footer,
    ]
    write(screen_name, screen([dim(), window(WIN_W, WIN_H, title, ico, body, header=header_color)], order=10, enabled=False))


def base_panels():
    # Eggs / Pets buttons on the right edge (HudController moves them to the top right on phones).
    buttons = frame("Buttons", U(0, 80, 0, 216), U(1, -14, 0.5, -130), (1, 1), children=[
        autoscale(), vlist(28, "Right", "Bottom"),
        side_button("EggsButton", "Eggs", "Egg", DANGER, 1),
        side_button("PetsButton", "Pets", "Alien", "#FF9A3C", 2),
    ])
    write("BasePanels", screen([buttons], order=4))
    head = dict(size=U(0, 150, 0, 44), pos=U(1, -64, 0, 32), anchor=(1, 0.5))
    list_window(
        "PetsPanel", "0/4 Active", "Alien", "#FF9A3C",
        button("AddSlot", head["size"], head["pos"], head["anchor"], color=DANGER, label="+ Slots", ts=20, ZIndex=5),
        [button("Action", U(0, 120, 0, 48), U(1, -10, 0.5, 0), (1, 0.5), color=DANGER, label="Unequip", ts=19)],
        button("EquipBest", U(0, 320, 0, 56), U(0.5, 0, 1, -14), (0.5, 1), color=SUCCESS, label="Equip Best", ts=26))
    list_window(
        "EggsPanel", "Growing Eggs", "Egg", DANGER,
        button("OpenAll", head["size"], head["pos"], head["anchor"], color=PREMIUM, label="Open All", ts=20, label_color=INK, ZIndex=5),
        [button("Action", U(0, 120, 0, 48), U(1, -10, 0.5, 0), (1, 0.5), color=SUCCESS, label="Open", ts=19)],
        button("PlaceEggs", U(0, 320, 0, 56), U(0.5, 0, 1, -14), (0.5, 1), color="#4C8DFF", label="Place Eggs", ts=24))


# ---------------------------------------------------------------- Hover card (pets and eggs in parks)
def hover():
    line = lambda name, order, ts, color: text(name, "", U(1, 0, 0, ts + 6), ts=ts, color=color, display=True, stroke=2,
                                               xa="Left", LayoutOrder=order, TextWrapped=False)
    card = frame("Card", U(0, 250, 0, 0), bg=BG, BackgroundTransparency=0.08, AutomaticSize="Y", Visible=False, ZIndex=10, children=[
        autoscale(), border(INK, 3), padding(12, 12, 8, 10), vlist(2, "Left", "Top"),
        line("Name", 1, 22, WHITE),
        line("Weight", 2, 18, WHITE),
        line("Income", 3, 18, "#7CFF8C"),
        line("Extra", 4, 15, "#C8D0E8"),
    ])
    tree = screen([card], order=30, inset=True)
    tree["properties"]["ScreenInsets"] = "None"
    write("Hover", tree)


# ---------------------------------------------------------------- Egg placement banner
def placing():
    """Shown while holding an egg: what you're placing, Cancel, and Go to Base when far."""
    bar_ = plate("Bar", U(0, 520, 0, 92), U(0.5, 0, 1, -112), (0.5, 1), BG, stud=0.5, children=[
        autoscale(),
        icon("Icon", "Egg", 76, U(0, 6, 0.5, 0), (0, 0.5)),
        text("Title", "Click a spot in your pet park", U(1, -250, 0, 32), U(0, 88, 0, 12), ts=22, color=WHITE, display=True,
             stroke=2.5, xa="Left", TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 22, "MinTextSize": 10})]),
        text("Sub", "", U(1, -250, 0, 26), U(0, 88, 0, 50), ts=17, color=ACCENT, heavy=True, xa="Left", stroke=2),
        button("GoBase", U(0, 140, 0, 44), U(1, -10, 0, 8), (1, 0), color=SUCCESS, label="Go to Base", ts=18, Visible=False),
        button("Cancel", U(0, 140, 0, 34), U(1, -10, 1, -8), (1, 1), color=DANGER, label="Cancel (Q)", ts=16),
    ])
    write("Placing", screen([bar_], order=8, enabled=False))


# ---------------------------------------------------------------- Rewards (daily, playtime, group, event)
def reward_card(name, top, order, w, h, ico_px):
    """Daily / gift card: label on top, big icon, reward text, a CLAIMED overlay."""
    return button(name, U(0, w, 0, h), color=WHITE, stroke=3, LayoutOrder=order, children=[
        text("Day", top, U(1, 0, 0, 24), U(0.5, 0, 0, 2), (0.5, 0), ts=18, color=INK, display=True, ZIndex=4),
        icon("Icon", "Gift", ico_px, U(0.5, 0, 0.5, 2), (0.5, 0.5)),
        text("Reward", "", U(1, -6, 0, 22), U(0.5, 0, 1, -3), (0.5, 1), ts=15, color=INK, display=True, ZIndex=4,
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 16, "MinTextSize": 8})]),
        frame("Done", U(1, 0, 1, 0), bg="#0B0E1E", BackgroundTransparency=0.45, Visible=False, ZIndex=6, children=[
            text("Label", "✓", U(1, 0, 1, 0), ts=54, color=SUCCESS, display=True, stroke=3, ZIndex=7),
        ]),
    ])


def rewards():
    days = frame("Days", U(1, -24, 0, 140), U(0, 12, 0, 116), children=[
        hlist(10, "Center", "Center"),
    ] + [reward_card(f"Day{i}", f"Day {i}", i, 102, 136, 72) for i in range(1, 8)])
    group = plate("Group", U(0.5, -18, 0, 100), U(0, 12, 0, 358), tint="#4C8DFF", stud=0.3, stroke=3, children=[
        icon("Icon", "Group", 70, U(0, 4, 0.5, 0), (0, 0.5)),
        text("Text", "Join our group for 2 Luck Potions + cash!", U(1, -220, 1, -8), U(0, 78, 0, 4), ts=16, display=True,
             stroke=2, xa="Left"),
        button("Claim", U(0, 124, 0, 50), U(1, -10, 0.5, 0), (1, 0.5), color=SUCCESS, label="Claim", ts=22),
    ])
    event = plate("Event", U(0.5, -18, 0, 100), U(1, -12, 0, 358), (1, 0), tint="#FF78E6", stud=0.3, stroke=3, children=[
        icon("Icon", "Event", 70, U(0, 4, 0.5, 0), (0, 0.5)),
        text("Name", "Meteor Weekend", U(1, -220, 0, 28), U(0, 78, 0, 6), ts=21, display=True, stroke=2.5, xa="Left",
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 22, "MinTextSize": 10})]),
        text("Info", "", U(1, -220, 0, 44), U(0, 78, 0, 34), ts=14, display=True, stroke=2, xa="Left", ya="Top",
             TextScaled=True, children=[node("Fit", "UITextSizeConstraint", {"MaxTextSize": 15, "MinTextSize": 8})]),
        button("SignUp", U(0, 124, 0, 50), U(1, -10, 0.5, 0), (1, 0.5), color=PREMIUM, label="Sign up", ts=20, label_color=INK),
    ])
    body = [
        text("Streak", "Streak: 0 days", U(1, -32, 0, 30), U(0.5, 0, 0, 80), (0.5, 0), ts=22, color=SUB, heavy=True),
        days,
        button("ClaimDaily", U(0, 300, 0, 56), U(0.5, 0, 0, 274), (0.5, 0), color=SUCCESS, label="Claim Day 1", ts=26),
        group, event,
    ]
    write("Daily", screen([dim(), window(WIN_W, WIN_H, "Daily Rewards", "Daily", body, header="#FF5FA2")], order=10, enabled=False))

    # Playtime gifts: their own window (green Gifts button on the rail).
    gifts = frame("Gifts", U(1, -24, 0, 340), U(0, 12, 0, 124), children=[
        node("Layout", "UIGridLayout", {"CellSize": U(0, 210, 0, 160), "CellPadding": U(0, 16, 0, 16), "SortOrder": "LayoutOrder",
                                        "HorizontalAlignment": "Center"}),
    ] + [reward_card(f"Gift{i}", "5:00", i, 210, 160, 92) for i in range(1, 7)])
    gift_body = [
        text("Info", "Free gifts the longer you play! They reset when you rejoin.", U(1, -24, 0, 30), U(0.5, 0, 0, 82), (0.5, 0),
             ts=20, color=SUB, heavy=True),
        gifts,
    ]
    write("Playtime", screen([dim(), window(WIN_W, WIN_H, "Playtime Gifts", "Gift", gift_body, header=SUCCESS)], order=10, enabled=False))

    # Stay offer: pops when the player opens the Roblox menu (about to leave).
    stay = plate("Window", U(0, 440, 0, 230), U(0.5, 0, 0.5, 0), (0.5, 0.5), SURFACE, children=[
        autoscale(),
        plate("Header", U(1, 0, 0, 56), tint="#FF5FA2", children=[
            icon("Icon", "PotionLuck", 42, U(0, 8, 0.5, 0), (0, 0.5)),
            text("Title", "Wait! Free potion!", U(1, -130, 1, 0), U(0, 58, 0, 0), ts=28, display=True, stroke=3, xa="Left"),
        ]),
        button("Close", U(0, 48, 0, 48), U(1, -6, 0, 6), (0.5, 0.5), color=DANGER, label="X", ts=28, ZIndex=5),
        text("Text", "Stay 5 more minutes and get a free Luck Potion!", U(1, -40, 0, 64), U(0.5, 0, 0, 68), (0.5, 0), ts=20,
             color=INK, heavy=True),
        button("Stay", U(0, 260, 0, 58), U(0.5, 0, 1, -14), (0.5, 1), color=SUCCESS, label="Stay & get it!", ts=26),
    ])
    chip = plate("Chip", U(0, 0, 0, 40), U(0.5, 0, 0, 116), (0.5, 0), BG, stud=0.5, stroke=3, AutomaticSize="X", Visible=False,
                 children=[
                     autoscale(), padding(48, 14, 0),
                     icon("Icon", "PotionLuck", 44, U(0, -46, 0.5, 0), (0, 0.5)),
                     text("Label", "Free potion in 5:00", U(0, 0, 1, 0), ts=19, color=ACCENT, display=True, stroke=2.5,
                          AutomaticSize="X", TextWrapped=False),
                 ])
    write("Stay", screen([chip, frame("Popup", U(1, 0, 1, 0), Visible=False, children=[stay])], order=14))


def rebirth():
    body = [
        icon("Big", "Rebirth", 110, U(0, 22, 0, 80)),
        text("Mult", "Cash x1 → x1.5", U(1, -160, 0, 44), U(0, 140, 0, 86), ts=30, color=INK, display=True, xa="Left"),
        text("Info", "Resets your cash, tools, cars and upgrades.\nKeeps your aliens, index and zones.", U(1, -160, 0, 50),
             U(0, 140, 0, 132), ts=17, color=SUB, xa="Left", ya="Top"),
        text("Cost", "Cost: $0", U(1, -40, 0, 30), U(0.5, 0, 0, 202), (0.5, 0), ts=22, color=INK, heavy=True),
        button("RebirthButton", U(0, 300, 0, 62), U(0.5, 0, 0, 244), (0.5, 0), color=SUCCESS, label="Rebirth!", ts=32),
        button("SkipButton", U(0, 300, 0, 50), U(0.5, 0, 0, 318), (0.5, 0), color=PREMIUM, label="Skip", ts=24, label_color=INK),
    ]
    write("Rebirth", screen([dim(), window(520, 392, "Rebirth", "Rebirth", body, header=REBIRTH, scale=1.25)], order=10, enabled=False))


# ---------------------------------------------------------------- Offer + Welcome back
def offer():
    win = plate("Window", U(0, 420, 0, 196), U(0.5, 0, 1, -20), (0.5, 1), SURFACE, children=[
        autoscale(),
        plate("Header", U(1, 0, 0, 42), tint=PREMIUM, children=[
            icon("Icon", "Star", 32, U(0, 8, 0.5, 0), (0, 0.5)),
            text("Title", "Offer", U(1, -110, 1, 0), U(0, 48, 0, 0), ts=26, display=True, stroke=3, xa="Left"),
        ]),
        button("Close", U(0, 44, 0, 44), U(1, -6, 0, 6), (0.5, 0.5), color=DANGER, label="X", ts=26, ZIndex=5),
        text("Text", "", U(1, -28, 0, 70), U(0, 14, 0, 50), ts=18, color=INK, heavy=True, xa="Left", ya="Top"),
        button("Buy", U(0, 200, 0, 52), U(0.5, 0, 1, -12), (0.5, 1), color=PREMIUM, label="", ts=26, label_color=INK),
    ])
    write("Offer", screen([win], order=12, enabled=False))

    welcome = window(460, 350, "Welcome back!", "Cash", popup=True, children=[
        icon("Big", "Cash", 96, U(0.5, 0, 0, 72), (0.5, 0)),
        text("Amount", "+$0", U(1, -40, 0, 46), U(0.5, 0, 0, 166), (0.5, 0), ts=40, color="#1E9E3A", display=True),
        text("Text", "", U(1, -40, 0, 40), U(0.5, 0, 0, 218), (0.5, 0), ts=17, color=SUB),
        button("Collect", U(0, 190, 0, 56), U(0.5, -100, 1, -16), (0.5, 1), color=SUCCESS, label="Collect", ts=28),
        button("Double", U(0, 190, 0, 56), U(0.5, 100, 1, -16), (0.5, 1), color=PREMIUM, label="2x", ts=24, label_color=INK),
    ], header=PILL_BASE)
    write("WelcomeBack", screen([dim(), welcome], order=12, enabled=False))


# ---------------------------------------------------------------- Hatch
def hatch():
    """Egg opening. In the world when you're near the egg (HatchController moves the camera),
    otherwise in the Stage window. Card = what hatched, with Place on base / Keep in bag."""
    stage = frame("Stage", U(0, 520, 0, 520), U(0.5, 0, 0.45, 0), (0.5, 0.5), Visible=False, children=[
        autoscale(),
        node("Rays", "ImageLabel", base(U(1.25, 0, 1.25, 0), U(0.5, 0, 0.5, 0), (0.5, 0.5), BackgroundTransparency=1,
                                        Image=img("Rays"), ImageColor3=ACCENT, ImageTransparency=1, ZIndex=0)),
        node("Glow", "ImageLabel", base(U(1, 0, 1, 0), U(0.5, 0, 0.5, 0), (0.5, 0.5), BackgroundTransparency=1,
                                        Image=img("Glow"), ImageColor3=ACCENT, ImageTransparency=1, ZIndex=0)),
        node("Viewport", "ViewportFrame", base(U(0, 440, 0, 440), U(0.5, 0, 0.5, 0), (0.5, 0.5), BackgroundTransparency=1,
                                               Ambient="#AEB8D8", LightColor=WHITE, LightDirection=[-1, -1, -1], ZIndex=1)),
    ])
    card = plate("Card", U(0, 480, 0, 132), U(0.5, 0, 1, -184), (0.5, 1), BG, stud=None, stroke=4, Visible=False, ZIndex=4, children=[
        autoscale(),
        text("Rarity", "LEGENDARY", U(1, -20, 0, 22), U(0.5, 0, 0, 10), (0.5, 0), ts=18, display=True, stroke=2, ZIndex=5),
        text("Name", "", U(1, -20, 0, 44), U(0.5, 0, 0, 30), (0.5, 0), ts=36, display=True, stroke=3, ZIndex=5, TextScaled=True),
        text("Info", "", U(1, -20, 0, 26), U(0.5, 0, 0, 78), (0.5, 0), ts=20, heavy=True, stroke=2, ZIndex=5, RichText=True),
        plate("New", U(0, 100, 0, 38), U(1, 14, 0, -14), (1, 0), PREMIUM, stroke=3, stud=None, Rotation=8, Visible=False, ZIndex=6,
              children=[text("Label", "NEW!", U(1, 0, 1, 0), ts=24, color=INK, display=True, ZIndex=7)]),
        frame("Choice", U(0, 440, 0, 54), U(0.5, 0, 1, 12), (0.5, 0), Visible=False, ZIndex=5, children=[
            hlist(14),
            button("Place", U(0, 220, 0, 54), color=SUCCESS, label="Place on base", ts=22, LayoutOrder=1, ZIndex=5),
            button("Keep", U(0, 190, 0, 54), color=HEADER, label="Keep in bag", ts=22, LayoutOrder=2, ZIndex=5),
        ]),
        text("Hint", "Click to skip", U(1, 0, 0, 22), U(0.5, 0, 1, 8), (0.5, 0), ts=16, heavy=True, stroke=2, ZIndex=5,
             TextTransparency=0.15),
    ])
    confetti = frame("Confetti", U(1, 0, 1, 0), ZIndex=8, children=[
        node("Template", "ImageLabel", base(U(0, 26, 0, 26), anchor=(0.5, 0.5), BackgroundTransparency=1, Image=img("Sparkle"),
                                            Visible=False, ZIndex=8)),
    ])
    flash = frame("Flash", U(1, 0, 1, 0), bg=WHITE, BackgroundTransparency=1, ZIndex=10)
    tree = screen([stage, card, confetti, flash], order=20, enabled=False, inset=True)
    tree["properties"]["ScreenInsets"] = "None"
    write("Hatch", tree)


def tutorial_done():
    """Shown once when the tutorial is finished, with the reward it gave."""
    rewards_row = frame("Rewards", U(1, -28, 0, 132), U(0.5, 0, 0, 120), (0.5, 0), children=[
        hlist(12, "Center", "Center"),
        reward_card("Cash", "Cash", 1, 120, 128, 70),
        reward_card("Luck", "Potion", 2, 120, 128, 70),
        reward_card("CashPotion", "Potion", 3, 120, 128, 70),
    ])
    body = [
        text("Sub", "You're a real Moon Sweeper now. Here's a gift to get going:", U(1, -40, 0, 44), U(0.5, 0, 0, 72), (0.5, 0),
             ts=18, color=INK, heavy=True),
        rewards_row,
        button("Ok", U(0, 220, 0, 58), U(0.5, 0, 1, -16), (0.5, 1), color=SUCCESS, label="Awesome!", ts=26),
    ]
    write("TutorialDone", screen([dim(), window(480, 360, "Tutorial done!", "Star", body, header=SUCCESS, popup=True)], order=12, enabled=False))


def settings():
    """Gear button in the top bar (next to Roblox's own buttons) and the Settings window
    with Music and Sound effects sliders."""
    gear = node("Gear", "ImageButton", base(U(0, 44, 0, 44), U(0, 116, 0, 12), BackgroundColor3="#000000",
                                            BackgroundTransparency=0.3, Image="", AutoButtonColor=False), [
        node("Corner", "UICorner", {"CornerRadius": [1, 0]}),  # matches Roblox's own round top bar buttons
        icon("Icon", "Gear", 28, U(0.5, 0, 0.5, 0), (0.5, 0.5)),
    ])
    write("Topbar", screen([gear], order=6, inset=True))

    def row(name, label, ico, y):
        return plate(name, U(1, -28, 0, 84), U(0, 14, 0, y), tint=WHITE, stud=0.2, children=[
            button("Mute", U(0, 60, 0, 60), U(0, 12, 0.5, 0), (0, 0.5), color=HEADER, children=[
                icon("Icon", ico, 40, U(0.5, 0, 0.5, 0), (0.5, 0.5)),
            ]),
            text("Label", label, U(0, 220, 0, 30), U(0, 86, 0, 8), ts=22, color=INK, display=True, xa="Left"),
            text("Value", "60%", U(0, 80, 0, 30), U(1, -14, 0, 8), (1, 0), ts=22, color=HEADER, display=True, xa="Right"),
            frame("Track", U(1, -112, 0, 16), U(0, 86, 0, 52), bg="#0B0E1E", children=[
                border(INK, 3),
                frame("Fill", U(0.6, 0, 1, 0), bg=SUCCESS),
                frame("Knob", U(0, 22, 0, 34), U(0.6, 0, 0.5, 0), (0.5, 0.5), bg=WHITE, ZIndex=3, children=[border(INK, 3)]),
                node("Hit", "TextButton", base(U(1, 24, 0, 48), U(0.5, 0, 0.5, 0), (0.5, 0.5), BackgroundTransparency=1, Text="",
                                                ZIndex=4)),
            ]),
        ])

    body = [
        row("Music", "Music", "Music", 80),
        row("Sfx", "Sound effects", "Speaker", 176),
        text("Track", "", U(1, -28, 0, 22), U(0, 14, 1, -12), (0, 1), ts=15, color=SUB, heavy=True),
    ]
    write("Settings", screen([dim(), window(520, 310, "Settings", "Gear", body, header="#5A6585", scale=1.4)], order=10, enabled=False))


# ---------------------------------------------------------------- Garage
def garage():
    row = plate("Template", U(1, -12, 0, 92), tint=WHITE, stud=0.2, Visible=False, children=[
        icon("Icon", "Vehicle", 74, U(0, 6, 0.5, 0), (0, 0.5)),
        text("Name", "Car", U(1, -270, 0, 30), U(0, 86, 0, 8), ts=24, color=INK, display=True, xa="Left"),
        text("Stats", "", U(1, -270, 0, 22), U(0, 86, 0, 40), ts=15, color=SUB, xa="Left"),
        text("Price", "", U(1, -270, 0, 20), U(0, 86, 0, 62), ts=15, color="#1E9E3A", heavy=True, xa="Left"),
        button("Main", U(0, 160, 0, 44), U(1, -12, 0, 6), (1, 0), color=SUCCESS, label="Buy", ts=22),
        button("Robux", U(0, 160, 0, 32), U(1, -12, 0, 56), (1, 0), color=PREMIUM, label="", ts=16, label_color=INK, Visible=False),
    ])
    lst = scroller("List", U(1, -28, 1, -128), U(0, 14, 0, 76), [vlist(10), padding(2, 2, 4, 4), row])
    hint = text("Hint", "Cars sweep a huge area and hold more dust. Spawn one here or from slot 2.", U(1, -28, 0, 36),
                U(0, 14, 1, -10), (0, 1), ts=15, color=SUB, heavy=True)
    write("Garage", screen([dim(), window(640, 470, "Garage", "Vehicle", [lst, hint], header="#FF9A3C", scale=1.08)], order=10, enabled=False))


# ---------------------------------------------------------------- Upgrades
def upgrades():
    row = plate("Template", U(1, -12, 0, 84), tint=WHITE, stud=0.2, Visible=False, children=[
        icon("Icon", "Upgrade", 66, U(0, 8, 0.5, 0), (0, 0.5)),
        text("Name", "Upgrade", U(1, -260, 0, 28), U(0, 88, 0, 6), ts=22, color=INK, display=True, xa="Left"),
        text("Desc", "", U(1, -260, 0, 20), U(0, 88, 0, 33), ts=15, color=SUB, xa="Left"),
        frame("Pips", U(1, -260, 0, 16), U(0, 88, 0, 59), children=[
            hlist(4, "Left", "Center"),
            frame("Template", U(0, 18, 0, 14), bg=MUTED, Visible=False, children=[border(INK, 2)]),
        ]),
        text("Effect", "", U(0, 120, 0, 20), U(1, -172, 0, 8), (1, 0), ts=16, color="#1E9E3A", heavy=True, xa="Right"),
        button("Buy", U(0, 150, 0, 50), U(1, -12, 0.5, 0), (1, 0.5), color=SUCCESS, label="", ts=22),
    ])
    lst = scroller("List", U(1, -28, 1, -92), U(0, 14, 0, 76), [vlist(10), padding(2, 2, 4, 4), row])
    write("Upgrades", screen([dim(), window(640, 500, "Upgrades", "Upgrade", [lst], header="#FF9A3C")], order=10, enabled=False))


# ---------------------------------------------------------------- Loading
def loading():
    root = frame("Root", U(1, 0, 1, 0), bg=BG, children=[
        node("Studs", "ImageLabel", base(U(1, 0, 1, 0), BackgroundTransparency=1, Image=img("Stud"), ScaleType="Tile",
                                        TileSize=U(0, 96, 0, 96), ImageColor3="#2A3260", ImageTransparency=0.55, ZIndex=0)),
        frame("Center", U(0, 560, 0, 470), U(0.5, 0, 0.5, 0), (0.5, 0.5), children=[
            autoscale(),
            node("Logo", "ImageLabel", base(U(0, 520, 0, 300), U(0.5, 0, 0, 0), (0.5, 0), BackgroundTransparency=1,
                                            Image=img("Logo"), ScaleType="Fit", ZIndex=2)),
            plate("Bar", U(0, 480, 0, 46), U(0.5, 0, 0, 322), (0.5, 0), tint=SURFACE, stud=0.2, children=[
                frame("Track", U(1, -16, 1, -16), U(0.5, 0, 0.5, 0), (0.5, 0.5), bg="#2A3260", children=[
                    frame("Fill", U(0.02, 0, 1, 0), bg=ACCENT),
                ]),
                text("Percent", "0%", U(1, 0, 1, 0), ts=20, display=True, stroke=2.5, ZIndex=4),
            ]),
            text("Status", "Loading...", U(1, 0, 0, 28), U(0.5, 0, 0, 380), (0.5, 0), ts=20, heavy=True, stroke=2.5),
            text("Tip", "", U(1, 0, 0, 44), U(0.5, 0, 0, 418), (0.5, 0), ts=16, color="#C8D0E8", heavy=True),
        ]),
    ])
    tree = screen([root], order=100, enabled=False, inset=True)
    tree["properties"]["ScreenInsets"] = "None"
    write("Loading", tree)


def main():
    os.makedirs(OUT, exist_ok=True)
    missing = [n for n in ("Stud", "Icon_Shop", "BannerStarter") if n not in IMG]
    if missing:
        raise SystemExit(f"Assets.luau is missing images {missing}; run tools/upload_assets.py first")
    hud()
    shop()
    index()
    inventory()
    base_panels()
    placing()
    hover()
    rewards()
    rebirth()
    offer()
    hatch()
    settings()
    tutorial_done()
    garage()
    upgrades()
    loading()
    print("ui written to", OUT)


if __name__ == "__main__":
    main()
